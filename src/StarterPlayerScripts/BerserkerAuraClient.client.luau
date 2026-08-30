-- VERSION: 2026-08-19 #5
-- LocalScript: BerserkerAuraClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt eine mehrschichtige rote Energie-Aura um den Charakter, solange der kontrollierte
-- Berserk-Modus aktiv ist (player:GetAttribute("BerserkActive") == true, siehe
-- HeatHandler.lua). Rein visuell, läuft für ALLE Spieler (nicht nur den lokalen), damit
-- andere den Berserker auch sehen -- der Server sagt nur "Berserk = true", der Client
-- baut Partikel/Licht/Beams komplett lokal, um keine Server-/Netzwerkleistung für rein
-- visuelle Effekte zu verschwenden.
--
-- Vier Ebenen (siehe Konzept-Vorlage):
--   1. Body Glow    -- Highlight um den ganzen Charakter, pulsiert leicht
--   2. Flame Aura   -- mehrere ParticleEmitter an Rumpf/Armen/Beinen, Energie läuft am
--                      Körper HOCH statt explosionsartig wegzufliegen
--   3. Ground Aura  -- flacher Ring unter dem Spieler, folgt mit leichter Verzögerung
--   4. Energy Wisps -- dünne Beams zwischen Attachments, erscheinen/verschwinden kurz
--
-- Eskalation nach Heat-Wert (nicht nach Zeit -- ein fester "BerserkerEndsAt"-Timer
-- existiert serverseitig nicht, siehe HeatHandler.lua): 85 = Einstieg in Berserk, 100 =
-- Meltdown-Schwelle. fraction = (heat-85)/(100-85), 0 bis 1.
--   0-30%:   hauptsächlich Glühen, wenige Partikel
--   30-70%:  stärkere Flammen + Funken
--   70-100%: aggressivere Wisps, Boden pulsiert
--
-- Bei Ende: kein hartes Abschalten -- Aura kollabiert kurz zum Körper, dann WHUMM +
-- Shockwave-Ring, erst danach wird alles zerstört.
--
-- Schlag-Reaktion: nutzt das bereits vorhandene ShowDamageEvent (feuert bei JEDEM
-- Treffer des lokalen Spielers, inkl. isFinisher-Flag) -- kein neuer RemoteEvent nötig.
-- Aura expandiert kurz + Funkenburst, beim Finisher (3. Combo-Schlag) deutlich stärker.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ShowDamageEvent = RemoteEventUtils.GetOrCreate("ShowDamageEvent")
local localPlayer = Players.LocalPlayer

local AURA_COLOR = Color3.fromRGB(255, 60, 40)
local AURA_COLOR_HOT = Color3.fromRGB(255, 160, 60) -- Funken/Wisps etwas heller/oranger als die Basis-Flammen

local BERSERK_HEAT_START = 85
local BERSERK_HEAT_END = 110 -- angehoben von 100, konsistent mit der neuen Heat-Skala (siehe HeatHandler.lua/SkinSelectionGui.lua) -- höchste Aura-Stufe wird jetzt erst bei tiefem Meltdown erreicht, statt schon exakt bei Meltdown-Beginn

local activeAuras = {} -- [player] = { ...alle Instanzen + Zustand... }

-- ===== Eskalations-Fraktion (0-1) aus dem aktuellen Heat-Wert =====
local function getEscalationFraction(player)
	local heat = player:GetAttribute("Heat") or BERSERK_HEAT_START
	return math.clamp((heat - BERSERK_HEAT_START) / (BERSERK_HEAT_END - BERSERK_HEAT_START), 0, 1)
end

-- ===== Ebene 1: Body Glow (Highlight) =====
local function createBodyGlow(character)
	local highlight = Instance.new("Highlight")
	highlight.Name = "BerserkHighlight"
	highlight.FillColor = AURA_COLOR
	highlight.OutlineColor = AURA_COLOR_HOT
	highlight.FillTransparency = 0.8
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	return highlight
end

-- ===== Ebene 2: Flame Aura -- an mehreren Körperteilen, Partikel laufen am Körper HOCH
-- (leicht nach aussen), statt explosionsartig wegzufliegen. =====
local FLAME_ATTACHMENT_PARTS = { "HumanoidRootPart", "UpperTorso", "LeftHand", "RightHand" }

local function createFlameEmitterAt(part)
	local attachment = Instance.new("Attachment")
	attachment.Name = "BerserkFlameAttachment"
	attachment.Parent = part

	local flames = Instance.new("ParticleEmitter")
	flames.Name = "BerserkFlames"
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new(AURA_COLOR, AURA_COLOR_HOT)
	flames.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	flames.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	flames.Lifetime = NumberRange.new(0.5, 0.8)
	flames.Rate = 10 -- Basis-Rate, wird pro Frame nach Eskalationsstufe hochskaliert
	flames.Speed = NumberRange.new(3, 5)
	-- Energie läuft HOCH und leicht nach aussen -- kein SpreadAngle=180 (das würde in
	-- alle Richtungen explodieren), sondern ein enger Kegel nach oben.
	flames.SpreadAngle = Vector2.new(25, 25)
	flames.Acceleration = Vector3.new(0, 6, 0)
	flames.LightEmission = 0.85
	flames.Parent = attachment

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "BerserkSparks"
	sparks.Color = ColorSequence.new(AURA_COLOR_HOT)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.3, 0.5)
	sparks.Rate = 0 -- nur bei Eskalationsstufe 2+ per :Emit() ausgelöst, kein Dauerregen
	sparks.Speed = NumberRange.new(4, 8)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 1
	sparks.Parent = attachment

	return { attachment = attachment, flames = flames, sparks = sparks }
end

-- ===== Ebene 3: Ground Aura -- flacher Ring unter dem Spieler, folgt mit leichter
-- Verzögerung (zieht beim Laufen leicht hinterher). =====
local function createGroundRing()
	local ring = Instance.new("Part")
	ring.Name = "BerserkGroundRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 6, 6)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = AURA_COLOR
	ring.Transparency = 0.55
	ring.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = ring
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "BerserkGroundDust"
	dust.Color = ColorSequence.new(AURA_COLOR_HOT)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.6, 1)
	dust.Rate = 6
	dust.Speed = NumberRange.new(1, 3)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Parent = attachment

	return { part = ring, dust = dust }
end

-- ===== Ebene 4: Energy Wisps -- dünne Beams zwischen zwei Attachments um den Körper,
-- die periodisch kurz erscheinen und wieder verschwinden. =====
local WISP_COUNT = 3

local function createWisps(rootPart)
	local wisps = {}
	for i = 1, WISP_COUNT do
		local angle = (i / WISP_COUNT) * math.pi * 2
		local offset1 = Vector3.new(math.cos(angle) * 2.5, math.random(-2, 2), math.sin(angle) * 2.5)
		local offset2 = offset1 + Vector3.new(math.random(-2, 2), math.random(1, 3), math.random(-2, 2))

		local a0 = Instance.new("Attachment")
		a0.Position = offset1
		a0.Parent = rootPart
		local a1 = Instance.new("Attachment")
		a1.Position = offset2
		a1.Parent = rootPart

		local beam = Instance.new("Beam")
		beam.Name = "BerserkWisp"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(AURA_COLOR_HOT)
		beam.Width0 = 0.15
		beam.Width1 = 0.02
		beam.Transparency = NumberSequence.new(1) -- startet unsichtbar, wird stufenweise eingeblendet
		beam.FaceCamera = true
		beam.Parent = rootPart

		table.insert(wisps, { beam = beam, a0 = a0, a1 = a1, nextCycleAt = os.clock() + math.random() * 2 })
	end
	return wisps
end

-- ===== Manuelle Interpolation für Beam.Transparency -- TweenService kann
-- NumberSequence-Properties (wie Beam.Transparency) nicht direkt animieren, deshalb hier
-- von Hand über einen kurzen Heartbeat-Loop interpoliert. =====
local function tweenBeamTransparency(beam, fromValue, toValue, duration)
	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < duration and beam.Parent do
			local t = (os.clock() - startTime) / duration
			local current = fromValue + (toValue - fromValue) * t
			beam.Transparency = NumberSequence.new(current)
			task.wait()
		end
		if beam.Parent then
			beam.Transparency = NumberSequence.new(toValue)
		end
	end)
end

local function createAura(character)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	local flameEmitters = {}
	for _, partName in ipairs(FLAME_ATTACHMENT_PARTS) do
		local part = character:FindFirstChild(partName)
		if part then
			flameEmitters[partName] = createFlameEmitterAt(part)
		end
	end

	local light = Instance.new("PointLight")
	light.Name = "BerserkerAuraLight"
	light.Color = AURA_COLOR
	light.Brightness = 3
	light.Range = 12
	light.Parent = rootPart

	return {
		highlight = createBodyGlow(character),
		flameEmitters = flameEmitters,
		light = light,
		groundRing = createGroundRing(),
		wisps = createWisps(rootPart),
		rootPart = rootPart,
		character = character,
		pulseUntil = 0, -- für die Schlag-Reaktion (siehe unten)
		collapsing = false,
	}
end

-- Kollaps + Shockwave beim Enden -- KEIN hartes Abschalten. Partikel-Geschwindigkeit
-- kehrt sich kurz um (Energie zieht zum Körper zurück), dann ein kurzer WHUMM-Ring, erst
-- danach wird alles zerstört.
local COLLAPSE_DURATION = 0.35

local function playCollapseAndShockwave(aura, onComplete)
	if aura.collapsing then
		return
	end
	aura.collapsing = true

	for _, emitterInfo in pairs(aura.flameEmitters) do
		emitterInfo.flames.Acceleration = Vector3.new(0, -14, 0) -- Energie zieht zurück Richtung Körper
		emitterInfo.flames.Speed = NumberRange.new(1, 2)
	end
	if aura.highlight then
		local collapseTween = TweenService:Create(aura.highlight, TweenInfo.new(COLLAPSE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			FillTransparency = 0.3,
			OutlineTransparency = 0,
		})
		collapseTween:Play()
	end

	task.delay(COLLAPSE_DURATION, function()
		-- Shockwave-Ring: kurz aufblitzender, expandierender Ring + Funkenburst.
		if aura.rootPart and aura.rootPart.Parent then
			local shockwave = Instance.new("Part")
			shockwave.Name = "BerserkEndShockwave"
			shockwave.Shape = Enum.PartType.Cylinder
			shockwave.Size = Vector3.new(0.2, 2, 2)
			shockwave.Anchored = true
			shockwave.CanCollide = false
			shockwave.CanQuery = false
			shockwave.Material = Enum.Material.Neon
			shockwave.Color = AURA_COLOR_HOT
			shockwave.Transparency = 0.2
			shockwave.CFrame = CFrame.new(aura.rootPart.Position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
			shockwave.Parent = workspace

			local expandTween = TweenService:Create(shockwave, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.2, 22, 22),
				Transparency = 1,
			})
			expandTween:Play()
			expandTween.Completed:Connect(function()
				shockwave:Destroy()
			end)

			for _, emitterInfo in pairs(aura.flameEmitters) do
				emitterInfo.sparks:Emit(14)
			end
		end

		if onComplete then
			onComplete()
		end
	end)
end

local function destroyAuraImmediate(aura)
	if not aura then
		return
	end
	if aura.highlight then
		aura.highlight:Destroy()
	end
	for _, emitterInfo in pairs(aura.flameEmitters) do
		emitterInfo.flames.Enabled = false
		emitterInfo.sparks.Enabled = false
		emitterInfo.attachment:Destroy()
	end
	if aura.light then
		aura.light:Destroy()
	end
	if aura.groundRing then
		aura.groundRing.part:Destroy()
	end
	for _, wispInfo in ipairs(aura.wisps or {}) do
		wispInfo.beam:Destroy()
		wispInfo.a0:Destroy()
		wispInfo.a1:Destroy()
	end
end

-- ===== Punch-/Combo-Reaktion: nutzt das bestehende ShowDamageEvent (nur für den
-- LOKALEN Spieler relevant -- das Event feuert ohnehin nur an den Angreifer selbst). =====
ShowDamageEvent.OnClientEvent:Connect(function(_damage, isFinisher)
	local aura = activeAuras[localPlayer]
	if not aura or aura.collapsing then
		return
	end
	aura.pulseUntil = os.clock() + (isFinisher and 0.35 or 0.2)
	aura.pulseStrength = isFinisher and 1.6 or 1.2 -- Finisher expandiert deutlich stärker

	for _, emitterInfo in pairs(aura.flameEmitters) do
		emitterInfo.sparks:Emit(isFinisher and 16 or 6)
	end
end)

-- ===== Haupt-Update-Schleife: Eskalationsstufen, Ground-Ring-Folgen, Wisp-Zyklen,
-- Schlag-Puls-Abklingen. =====
RunService.Heartbeat:Connect(function()
	for player, aura in pairs(activeAuras) do
		if aura.collapsing or not aura.rootPart or not aura.rootPart.Parent then
			continue
		end

		local fraction = getEscalationFraction(player)

		-- Schlag-Puls: kurzzeitige Verstärkung, klingt danach zurück auf den normalen,
		-- eskalationsabhängigen Wert ab.
		local now = os.clock()
		local pulseActive = now < aura.pulseUntil
		local pulseMultiplier = pulseActive and (aura.pulseStrength or 1) or 1

		-- Flammen-Rate + Geschwindigkeit skalieren mit Eskalationsstufe (10 bei 0% bis 34
		-- bei 100%) und dem Schlag-Puls obendrauf.
		local baseRate = 10 + fraction * 24
		for _, emitterInfo in pairs(aura.flameEmitters) do
			emitterInfo.flames.Rate = baseRate * pulseMultiplier
			-- Ab Stufe 2 (30%+) fällt gelegentlich ein kleiner, automatischer Funkenregen.
			if fraction >= 0.3 and math.random() < 0.02 then
				emitterInfo.sparks:Emit(3)
			end
		end

		-- Highlight pulsiert leicht, stärker in höheren Stufen.
		if aura.highlight then
			local pulse = (math.sin(now * 4) + 1) / 2
			local baseTransparency = 0.85 - fraction * 0.1
			aura.highlight.FillTransparency = baseTransparency - pulse * 0.05 * pulseMultiplier
		end

		-- Ground Ring: folgt mit leichter Verzögerung (zieht beim Laufen hinterher),
		-- pulsiert stärker in Stufe 3 (70%+).
		if aura.groundRing then
			local targetPosition = aura.rootPart.Position - Vector3.new(0, 3, 0)
			local currentPosition = aura.groundRing.part.Position
			local followed = currentPosition:Lerp(targetPosition, 0.15)
			aura.groundRing.part.CFrame = CFrame.new(followed) * CFrame.Angles(0, 0, math.rad(90))
			if fraction >= 0.7 then
				local groundPulse = (math.sin(now * 8) + 1) / 2
				aura.groundRing.part.Transparency = 0.4 - groundPulse * 0.25
			else
				aura.groundRing.part.Transparency = 0.55
			end
		end

		-- Energy Wisps: periodisch ein-/ausblenden, häufiger + kürzerer Zyklus in
		-- höheren Stufen (wirkt "aggressiver um den Spieler schlagend").
		for _, wispInfo in ipairs(aura.wisps) do
			if now >= wispInfo.nextCycleAt then
				local cycleDuration = math.max(1.6 - fraction * 1.1, 0.4)
				wispInfo.nextCycleAt = now + cycleDuration + math.random() * cycleDuration * 0.5

				if fraction >= 0.2 then -- unter Stufe 1 bleiben Wisps komplett aus
					tweenBeamTransparency(wispInfo.beam, 1, 0.3, 0.12)
					task.delay(0.18, function()
						if wispInfo.beam.Parent then
							tweenBeamTransparency(wispInfo.beam, 0.3, 1, 0.25)
						end
					end)
				end
			end
		end
	end
end)

local function setupPlayer(player)
	player:GetAttributeChangedSignal("BerserkActive"):Connect(function()
		local isActive = player:GetAttribute("BerserkActive") == true

		local character = player.Character
		if isActive then
			if character and not activeAuras[player] then
				activeAuras[player] = createAura(character)
			end
		else
			local aura = activeAuras[player]
			if aura then
				playCollapseAndShockwave(aura, function()
					destroyAuraImmediate(aura)
					activeAuras[player] = nil
				end)
			end
		end
	end)

	player.CharacterAdded:Connect(function(character)
		local aura = activeAuras[player]
		if aura then
			destroyAuraImmediate(aura) -- kein Kollaps-Effekt nötig -- der alte Charakter existiert eh nicht mehr
			activeAuras[player] = nil
		end
		if player:GetAttribute("BerserkActive") == true then
			activeAuras[player] = createAura(character)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	local aura = activeAuras[player]
	if aura then
		destroyAuraImmediate(aura)
		activeAuras[player] = nil
	end
end)