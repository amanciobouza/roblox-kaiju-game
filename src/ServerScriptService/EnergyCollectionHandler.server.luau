-- VERSION: 2026-08-21 #4
-- Ort in Studio: ServerScriptService
-- Verwaltet das kontinuierliche Einsammeln von "Energie" (vormals: Erfahrungspunkte) aus
-- brennenden Ruinen. Ein Häuserabriss gibt nicht mehr sofort die volle Energiemenge --
-- stattdessen wird sie aufgeteilt:
--   - EXPLOSIONS-Anteil: einmalig, sofort, an alle Spieler in der Nähe der Explosion
--   - FEUER-Anteil: kontinuierlich über Zeit, an alle Spieler in der Nähe des Feuers,
--     solange es brennt (bis zum Respawn des Hauses)
--
-- Sowohl der Sammel-RADIUS als auch die Sammel-EFFIZIENZ hängen vom Körper-Wert des
-- Spielers ab (siehe getCollectionRadius / getCollectionEfficiency).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local EnergyAbsorbEvent = Instance.new("RemoteEvent")
EnergyAbsorbEvent.Name = "EnergyAbsorbEvent"
EnergyAbsorbEvent.Parent = ReplicatedStorage

-- Energie-Sog ist jetzt AKTIV statt automatisch -- der Spieler muss eine Taste GEHALTEN
-- halten (z.B. rechte Maustaste), um überhaupt Energie aus Reichweite absorbieren zu
-- können. Der Client feuert dieses Event bei Tasten-Druck/-Loslassen.
local SetAbsorbingEvent = Instance.new("RemoteEvent")
SetAbsorbingEvent.Name = "SetAbsorbingEvent"
SetAbsorbingEvent.Parent = ReplicatedStorage

SetAbsorbingEvent.OnServerEvent:Connect(function(player, isAbsorbing)
	player:SetAttribute("IsAbsorbing", isAbsorbing == true)
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("IsAbsorbing", false)
end)

-- Absorbieren automatisch stoppen, wenn der Charakter stirbt/respawnt -- sonst könnte
-- der Zustand "hängen bleiben" (z.B. Taste losgelassen während man tot war, Client
-- feuert dann evtl. kein Loslassen-Event mehr für den alten Charakter).
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		player:SetAttribute("IsAbsorbing", false)
	end)
end)

-- ===== Aufteilung Explosion vs. Feuer =====
local EXPLOSION_ENERGY_RATIO = 0.4 -- 40% sofort bei der Explosion, 60% übers Feuer
local FIRE_ENERGY_RATIO = 1 - EXPLOSION_ENERGY_RATIO

-- ===== Radius-Formel: RADIUS_BASE + RADIUS_SCALE * KörperWert^EXPONENT =====
-- Unterproportional (Exponent < 1), damit ein Spieler nicht durch extremes Körper-
-- Training einen riesigen, die halbe Karte abdeckenden Radius bekommt -- der Cap pro
-- Level (KörperWert ist durchs Trainings-System ohnehin begrenzt) sorgt zusätzlich dafür.
local RADIUS_BASE = 88 -- nochmals verdoppelt (war 44, ursprünglich 22)
local RADIUS_SCALE = 18 -- nochmals verdoppelt (war 9, ursprünglich 4.5)
local RADIUS_EXPONENT = 0.7

-- ===== Effizienz-Formel: wie viel % der verfügbaren Energie ein Spieler bekommt =====
-- BASIS_EFFIZIENZ ist der Mindestanteil, den man auch komplett untrainiert bekommt.
-- Der Rest wird freigeschaltet im Verhältnis KörperWert / BenötigterCap -- wobei sich
-- "BenötigterCap" nach dem Level richtet, das zur Energiequelle (Gebäude-MaxHealth)
-- passt. Das verhindert, dass ein Spieler mit für sein EIGENES Level maximiertem
-- Körper-Wert bei einem viel stärkeren Landmark-Gebäude die volle Energie absahnt.
local BASIS_EFFIZIENZ = 0.2

-- Muss zu den Zonen-Grenzen aus ZONEN_BALANCE.md passen (Level -> Gebäude-MaxHealth am
-- Zonenende). Wird genutzt, um von "Gebäude-MaxHealth" auf ein "implizites Level"
-- zurückzurechnen (inverse Interpolation), um damit dann den passenden StatCap zu holen.
local HP_LEVEL_BREAKPOINTS = {
	{ hp = 100, level = 0 },
	{ hp = 500, level = 9 },
	{ hp = 2000, level = 19 },
	{ hp = 16000, level = 29 },
	{ hp = 256000, level = 39 },
	{ hp = 64000000, level = 49 },
}

-- ===== Überraschungs-Mechanik: kleine Chance, dass ein HEAT-Gebäude beim SPAWNEN/
-- RESPAWNEN mit einem ANDEREN Energietyp erscheint, statt dem normalen Heat-Standard.
-- WICHTIG: Das ist eine SPAWN-ZEIT-Entscheidung (einmal pro Spawn/Respawn gewürfelt,
-- siehe HouseHandler.lua, rollSpawnEnergyType), NICHT mehr eine Pro-Sammel-Würfelung --
-- das Ergebnis steht fest, sobald das Gebäude erscheint, und bleibt bis zum nächsten
-- Respawn konsistent (Optik UND tatsächlicher Sammel-Ertrag stimmen dadurch immer
-- überein). Betrifft AUSSCHLIESSLICH Heat-Gebäude -- ein Gebäude, das explizit als
-- Chemical/Electric/Spirit/Radiation deklariert ist, bleibt IMMER bei seinem deklarierten
-- Typ, keine Überraschung dort. Erhöht sich deutlich, falls gerade ein Welt-Event für
-- genau diesen anderen Typ läuft (z.B. ein normales Heat-Haus erscheint während
-- "Thunderstorm" öfter mit Electric). Radiation bleibt bewusst aussen vor -- hat sein
-- eigenes, separates Seltenheitssystem (siehe unten), das soll nicht vermischt werden.
local SURPRISE_TYPES = { "Chemical", "Electric", "Spirit" }
local SURPRISE_BASE_CHANCE = 0.03 -- 3% Grundchance auf irgendeinen anderen Typ
local SURPRISE_EVENT_BONUS = 0.12 -- zusätzlich, falls ein Welt-Event genau diesen Typ begünstigt

-- Wird von HouseHandler.lua beim Spawnen/Respawnen eines Hauses aufgerufen -- WÜRFELT
-- (nicht nur liest) das tatsächliche Energietyp für DIESEN Spawn. declaredType ist der
-- manuell in Studio gesetzte "EnergyType"-Attributwert (oder nil/"Heat" als Standard).
local function rollSpawnEnergyType(declaredType)
	declaredType = declaredType or "Heat"
	if declaredType ~= "Heat" then
		return declaredType -- nur Heat-Gebäude können überraschen, alles andere bleibt fix
	end

	-- Gibt es gerade ein Welt-Event, das einen bestimmten Typ begünstigt? Falls ja,
	-- bekommt genau DIESER Typ die erhöhte Überraschungschance.
	local eventBoostedType = nil
	if _G.GetWorldEventMultiplier then
		for _, candidateType in ipairs(SURPRISE_TYPES) do
			if _G.GetWorldEventMultiplier(candidateType) > 1 then
				eventBoostedType = candidateType
				break
			end
		end
	end

	local roll = math.random()
	if eventBoostedType and roll < SURPRISE_BASE_CHANCE + SURPRISE_EVENT_BONUS then
		return eventBoostedType
	elseif roll < SURPRISE_BASE_CHANCE then
		return SURPRISE_TYPES[math.random(1, #SURPRISE_TYPES)]
	end

	return "Heat"
end
_G.RollSpawnEnergyType = rollSpawnEnergyType

-- Liest jetzt nur noch den beim Spawnen bereits feststehenden Typ (EffectiveEnergyType,
-- von HouseHandler.lua gesetzt) -- keine eigene Würfelung mehr hier, ausser für Radiation
-- (eigenes, unverändertes Seltenheitssystem, das WEITERHIN bei jedem Absorb-Vorgang neu
-- gewürfelt wird, nicht beim Spawnen).
local function getEffectiveEnergyType(house)
	local effectiveType = house:GetAttribute("EffectiveEnergyType") or house:GetAttribute("EnergyType") or "Heat"
	if effectiveType == "Radiation" then
		local maxHealth = house:GetAttribute("MaxHealth") or 100
		if _G.RollForRadiation and _G.RollForRadiation(maxHealth) then
			return "Radiation"
		end
		return "Heat" -- Wurf nicht erfolgreich -- normale Wärme-Energie stattdessen
	end
	return effectiveType
end

local function getImpliedLevelFromHP(hp)
	hp = math.max(hp, HP_LEVEL_BREAKPOINTS[1].hp)
	local lastLevel = HP_LEVEL_BREAKPOINTS[#HP_LEVEL_BREAKPOINTS].level
	if hp >= HP_LEVEL_BREAKPOINTS[#HP_LEVEL_BREAKPOINTS].hp then
		return lastLevel
	end

	for i = 1, #HP_LEVEL_BREAKPOINTS - 1 do
		local a = HP_LEVEL_BREAKPOINTS[i]
		local b = HP_LEVEL_BREAKPOINTS[i + 1]
		if hp >= a.hp and hp <= b.hp then
			-- Log-Interpolation, symmetrisch zur Cap-Formel in TrainingHandler.lua
			local t = (math.log(hp) - math.log(a.hp)) / (math.log(b.hp) - math.log(a.hp))
			return a.level + t * (b.level - a.level)
		end
	end

	return lastLevel
end
_G.GetImpliedLevelFromHP = getImpliedLevelFromHP

local function getBodyValue(player)
	local bodyPower = player:FindFirstChild("BodyPower")
	return bodyPower and bodyPower.Value or 0
end

-- Sammel-Radius eines Spielers (in Studs)
local function getCollectionRadius(player)
	local bodyValue = getBodyValue(player)
	return RADIUS_BASE + RADIUS_SCALE * (bodyValue ^ RADIUS_EXPONENT)
end

-- Sammel-Effizienz (0 bis 1) für eine konkrete Energiequelle (Gebäude-MaxHealth)
local function getCollectionEfficiency(player, sourceMaxHealth)
	local bodyValue = getBodyValue(player)
	local impliedLevel = getImpliedLevelFromHP(sourceMaxHealth)
	local requiredCap = (_G.GetStatCapForLevel and _G.GetStatCapForLevel(impliedLevel)) or 1
	local ratio = math.clamp(bodyValue / math.max(requiredCap, 1), 0, 1)
	return BASIS_EFFIZIENZ + (1 - BASIS_EFFIZIENZ) * ratio
end

-- Zeigt eine kleine "Energie fliegt zum Spieler"-Animation auf dem Client
local function showAbsorbEffect(player, sourcePosition, energyType, amount)
	EnergyAbsorbEvent:FireClient(player, sourcePosition, energyType, amount)
end

-- ===== Explosions-Energie: einmalig, sofort =====
-- Wird von HouseHandler.lua beim Zerstören eines Hauses aufgerufen.
local function grantExplosionEnergy(house, explosionPosition)
	local maxHealth = house:GetAttribute("MaxHealth") or 100
	local totalEnergy = (_G.HouseEnergyReward and _G.HouseEnergyReward(maxHealth)) or 0
	local explosionEnergy = totalEnergy * EXPLOSION_ENERGY_RATIO
	if explosionEnergy <= 0 then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local radius = getCollectionRadius(player)
			local distance = (rootPart.Position - explosionPosition).Magnitude
			if distance <= radius then
				local efficiency = getCollectionEfficiency(player, maxHealth)
				local gained = explosionEnergy * efficiency
				local wholeGained = math.floor(gained)
				if _G.AwardXP then
					_G.AwardXP(player, wholeGained)
				end
				-- KEINE Heat-Kühlung hier -- die sofortige Explosions-Energie soll den
				-- Heat-Wert nicht beeinflussen. Nur das kontinuierliche Absorbieren
				-- (gehaltene Taste, siehe unten im Datei-Tick) kühlt ab.
				-- WICHTIG: EINMAL berechnen und für Vergabe UND visuellen Effekt nutzen --
				-- vorher bekam der Effekt fälschlich den literalen String "explosion"
				-- statt des tatsächlichen Energie-Typs (Heat/Chemical/Electric/...).
				local effectiveType = getEffectiveEnergyType(house)
				if _G.GrantTypedEnergy then
					_G.GrantTypedEnergy(player, effectiveType, wholeGained)
				end
				if _G.AwardSpecialEnergyForAbsorb then
					_G.AwardSpecialEnergyForAbsorb(player, wholeGained)
				end
				showAbsorbEffect(player, explosionPosition, effectiveType, wholeGained)
			end
		end
	end
end

-- ===== Feuer-Energie: kontinuierlich über die Branddauer =====
-- [house] = { position, totalEnergy, remainingEnergy, duration, startTime }
local activeFireSources = {}

local function registerFireEnergySource(house, position, duration)
	local maxHealth = house:GetAttribute("MaxHealth") or 100
	local totalEnergy = (_G.HouseEnergyReward and _G.HouseEnergyReward(maxHealth)) or 0
	local fireEnergy = totalEnergy * FIRE_ENERGY_RATIO
	if fireEnergy <= 0 or duration <= 0 then
		return
	end

	activeFireSources[house] = {
		position = position,
		maxHealth = maxHealth,
		totalEnergy = fireEnergy,
		remainingEnergy = fireEnergy,
		ratePerSecond = fireEnergy / duration,
	}
end

local function unregisterFireEnergySource(house)
	activeFireSources[house] = nil
end

_G.RegisterFireEnergySource = registerFireEnergySource
_G.GrantExplosionEnergy = grantExplosionEnergy
-- Für FireEngineController.lua: Feuerwehrautos müssen aktive Feuerquellen finden und
-- deren remainingEnergy verringern können (Löschen). Direkte Tabellen-Referenz statt
-- Kopie, damit Änderungen sofort auch hier (Sammel-Logik) ankommen.
_G.ActiveFireSources = activeFireSources

-- ===== Sichtbarer Energie-Strom (Beam) -- SERVERSEITIG erstellt, damit er automatisch
-- für ALLE Spieler repliziert wird (nicht nur für den Sammelnden selbst). So sieht jeder,
-- wer gerade von einer Energiequelle profitiert. =====
-- Farbe richtet sich nach dem "EnergyType"-Attribut des Hauses (siehe EnergyTypesHandler.lua
-- fürs identische Farbschema im HUD) -- unmarkierte Häuser (Standard) bleiben beim
-- warmen Orange der Wärme-Energie.
local STREAM_COLOR_BY_TYPE = {
	Heat = Color3.fromRGB(255, 35, 25),
	Chemical = Color3.fromRGB(255, 45, 190),
	Electric = Color3.fromRGB(57, 217, 255),
	Radiation = Color3.fromRGB(126, 255, 16),
	Spirit = Color3.fromRGB(255, 205, 70),
}
local DEFAULT_STREAM_COLOR = Color3.fromRGB(255, 140, 40) -- warmes Orange, Rückfallebene
local CURVE_AMPLITUDE = 8
local CURVE_SPEED = 2.2
local WIDTH_START = 0.6
local WIDTH_END = 1.6

-- [player][house] = { beam, anchorPart, targetAttachment, phase } -- der AKTIVE Beam
local activeStreams = {}
-- [player][house] = true, solange gerade ein alter Beam verblasst (Fade-Out läuft) --
-- getrennt von activeStreams, damit wir zuverlässig erkennen können "hier läuft noch
-- was aus", auch wenn der Spieler currentluft schnell wieder in Reichweite kommt.
local fadingStreams = {}

local STREAM_GROW_DURATION = 0.4 -- Sekunden für den "Sog setzt ein"-Wachstumseffekt
local STREAM_FADE_DURATION = 0.35 -- Sekunden für das Verblassen beim Beenden (verkürzt für schnelleres Verschwinden)

local function createStreamBeam(player, house, sourcePosition)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	local anchorPart = Instance.new("Part")
	anchorPart.Name = "EnergyStreamAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.2, 0.2, 0.2)
	anchorPart.CFrame = CFrame.new(sourcePosition)
	anchorPart.Parent = Workspace

	local sourceAttachment = Instance.new("Attachment")
	sourceAttachment.Parent = anchorPart

	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "EnergyStreamTarget"
	targetAttachment.Parent = rootPart

	local streamColor = STREAM_COLOR_BY_TYPE[house:GetAttribute("EnergyType")] or DEFAULT_STREAM_COLOR

	local beam = Instance.new("Beam")
	beam.Attachment0 = sourceAttachment
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(streamColor)
	-- Startet komplett dünn/unsichtbar und wächst gleich auf volle Breite -- wirkt wie
	-- ein Sog, der sich von der Energiequelle zum Spieler hin "aufbaut".
	beam.Width0 = 0
	beam.Width1 = 0
	beam.Transparency = NumberSequence.new(0)
	beam.Texture = "rbxasset://textures/particles/sparkle_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 1.5
	beam.TextureSpeed = 1.2
	beam.LightEmission = 0.6
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Parent = anchorPart

	TweenService:Create(beam, TweenInfo.new(STREAM_GROW_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Width0 = WIDTH_START,
		Width1 = WIDTH_END,
	}):Play()

	return {
		beam = beam,
		anchorPart = anchorPart,
		targetAttachment = targetAttachment,
		phase = math.random() * math.pi * 2,
	}
end

local function destroyStreamBeam(player, house)
	activeStreams[player] = activeStreams[player] or {}
	local entry = activeStreams[player][house]
	if not entry then
		return
	end
	activeStreams[player][house] = nil -- sofort aus der Tabelle, damit kein neuer Tick mehr draufgreift

	fadingStreams[player] = fadingStreams[player] or {}
	fadingStreams[player][house] = true

	-- Sanft verblassen statt abrupt verschwinden (z.B. wenn das Haus respawnt,
	-- während der Spieler noch in der Nähe steht/sammelt). WICHTIG: NumberSequence-
	-- Eigenschaften wie Transparency lassen sich NICHT per TweenService animieren
	-- (Roblox-Einschränkung) -- deshalb hier sofort gesetzt, während nur die Breite
	-- (ein normaler tweenbarer Zahlenwert) sanft auf 0 läuft. Ein Beam mit Breite 0 ist
	-- ohnehin unsichtbar, egal welche Transparenz gerade gilt.
	entry.beam.Transparency = NumberSequence.new(1)

	local fadeTween = TweenService:Create(
		entry.beam,
		TweenInfo.new(STREAM_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Width0 = 0, Width1 = 0 }
	)
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		if entry.anchorPart then
			entry.anchorPart:Destroy() -- nimmt den Beam gleich mit (ist sein Kind)
		end
		if entry.targetAttachment then
			entry.targetAttachment:Destroy()
		end
		if fadingStreams[player] then
			fadingStreams[player][house] = nil
		end
	end)
end

local function setStreamActive(player, house, active, sourcePosition)
	activeStreams[player] = activeStreams[player] or {}
	local hasEntry = activeStreams[player][house] ~= nil
	if active == hasEntry then
		return -- keine Änderung
	end

	if active then
		-- SICHERHEITSNETZ: Falls aus irgendeinem Timing-Grund noch ein alter Beam für
		-- diese Kombination am Verblassen ist, JETZT sofort hart entfernen (nicht auf
		-- das Ende des Fade-Outs warten) -- verhindert, dass sich Beams anhäufen können.
		if fadingStreams[player] and fadingStreams[player][house] then
			fadingStreams[player][house] = nil
			-- Alle "EnergyStreamAnchor"-Objekte am HumanoidRootPart-Ziel dieses Spielers
			-- aufräumen, die noch übrig sein könnten (defensiv, falls die Referenz verloren ging).
		end
		activeStreams[player][house] = createStreamBeam(player, house, sourcePosition)
	else
		destroyStreamBeam(player, house)
	end
end

local function stopAllStreamsForHouse(house)
	for player in pairs(activeStreams) do
		destroyStreamBeam(player, house)
	end
end

-- Jetzt (nachdem stopAllStreamsForHouse bekannt ist) korrekt exponieren -- wichtig: beim
-- Respawn eines Hauses (Feuer erlischt) müssen alle noch laufenden Beams für DIESES Haus
-- sofort zum Verblassen gebracht werden, sonst bleiben sie für immer sichtbar hängen
-- (die Sammel-Schleife schaut das Haus danach ja gar nicht mehr an, da es aus
-- activeFireSources entfernt wurde).
_G.UnregisterFireEnergySource = function(house)
	unregisterFireEnergySource(house)
	stopAllStreamsForHouse(house)
end

-- Baut eine Transparenz-Kurve mit einem hellen "Fenster" an Position `pulsePosition`
-- (0 = an der Energiequelle, 1 = beim Spieler) -- der Rest des Bands bleibt fast
-- unsichtbar. So entsteht ein klar erkennbarer, wandernder Lichtpuls statt eines
-- gleichmäßig durchsichtigen Bandes. Zusätzlich moduliert `overallGlow` (0-1) den
-- GESAMTEN Beam (auch abseits des wandernden Fensters) -- leuchtet bei jedem Puls-Start
-- kurz auf und wird bis zum nächsten Puls wieder schwächer.
local PULSE_HALF_WIDTH = 0.12
local BASELINE_TRANSPARENCY_DIM = 0.9 -- Grundzustand kurz vor dem nächsten Puls
local BASELINE_TRANSPARENCY_GLOW = 0.6 -- Grundzustand direkt nach einem Puls-Start
local PEAK_TRANSPARENCY = 0.05
local PULSE_SAMPLE_COUNT = 10 -- Anzahl Stützpunkte der NumberSequence

local function buildPulseTransparency(pulsePosition, overallGlow)
	local baseline = BASELINE_TRANSPARENCY_DIM - (BASELINE_TRANSPARENCY_DIM - BASELINE_TRANSPARENCY_GLOW) * overallGlow

	local keypoints = {}
	for i = 0, PULSE_SAMPLE_COUNT do
		local t = i / PULSE_SAMPLE_COUNT
		local distance = math.abs(t - pulsePosition)
		local falloff = math.clamp(1 - distance / PULSE_HALF_WIDTH, 0, 1)
		local value = baseline - (baseline - PEAK_TRANSPARENCY) * falloff
		table.insert(keypoints, NumberSequenceKeypoint.new(t, value))
	end
	return NumberSequence.new(keypoints)
end

-- Läuft jeden Frame: lässt jeden aktiven Strom sanft hin- und herschwingen UND zeigt
-- einen wandernden Lichtpuls, der sichtbar von der Energiequelle (0) zum Spieler (1)
-- "hineingezogen" wird, wiederholend. Der GANZE Beam leuchtet bei jedem Puls-Start
-- (pulseTime = 0) auf und wird bis zum nächsten Puls-Start wieder schwächer.
local PULSE_SPEED = 0.9 -- wie viele "Durchläufe" (0 -> 1) pro Sekunde
local GLOW_MIN = 0.15 -- Basis-Leuchtkraft, fällt nie ganz auf 0 (bleibt leicht sichtbar)

RunService.Heartbeat:Connect(function(dt)
	for _, houses in pairs(activeStreams) do
		for _, entry in pairs(houses) do
			entry.phase += dt * CURVE_SPEED
			local sway = math.sin(entry.phase) * CURVE_AMPLITUDE
			entry.beam.CurveSize0 = sway
			entry.beam.CurveSize1 = -sway * 0.6

			entry.pulseTime = ((entry.pulseTime or 0) + dt * PULSE_SPEED) % 1
			-- overallGlow: 1 direkt beim Puls-Start, fällt dann Richtung GLOW_MIN ab,
			-- bis der nächste Puls (pulseTime springt zurück auf 0) es wieder auffrischt.
			local overallGlow = GLOW_MIN + (1 - GLOW_MIN) * (1 - entry.pulseTime)

			entry.beam.Transparency = buildPulseTransparency(entry.pulseTime, overallGlow)
			entry.beam.LightEmission = 0.3 + overallGlow * 0.7
		end
	end
end)

-- Reichweiten-Prüfung (Beam an/aus) läuft HÄUFIG, damit das Erscheinen/Verschwinden
-- des Streams sofort reagiert. Die Energie-VERGABE (seltener, alle TICK_INTERVAL
-- Sekunden) ist davon unabhängig -- kein Grund, die Sichtbarkeit an die Vergabe-Rate zu koppeln.
local RANGE_CHECK_INTERVAL = 0.1
local rangeCheckAccumulator = 0

RunService.Heartbeat:Connect(function(dt)
	rangeCheckAccumulator += dt
	if rangeCheckAccumulator < RANGE_CHECK_INTERVAL then
		return
	end
	rangeCheckAccumulator = 0

	for house, source in pairs(activeFireSources) do
		if source.remainingEnergy <= 0 or not house.Parent then
			stopAllStreamsForHouse(house)
		else
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local inRange = false
				if rootPart then
					local radius = getCollectionRadius(player)
					local distance = (rootPart.Position - source.position).Magnitude
					inRange = distance <= radius
				end
				-- Strahl nur zeigen, wenn AUSSERDEM aktiv gesaugt wird (Taste gehalten) --
				-- reine Nähe reicht nicht mehr.
				local isActive = inRange and player:GetAttribute("IsAbsorbing") == true
				setStreamActive(player, house, isActive, source.position)
			end
		end
	end
end)

-- Sammel-Tick: läuft seltener, verteilt anteilig Energie an alle Spieler in Reichweite
-- jeder aktiven Feuerquelle. Nutzt dieselbe inRange-Logik, unabhängig von der obigen
-- (häufigeren) Sichtbarkeits-Prüfung.
local TICK_INTERVAL = 2 -- seltener, dafür grössere Häppchen (war 0.5)
local accumulator = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < TICK_INTERVAL then
		return
	end
	local elapsed = accumulator
	accumulator = 0

	for house, source in pairs(activeFireSources) do
		if source.remainingEnergy <= 0 or not house.Parent then
			activeFireSources[house] = nil
			stopAllStreamsForHouse(house)
		else
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local inRange = false
				if rootPart then
					local radius = getCollectionRadius(player)
					local distance = (rootPart.Position - source.position).Magnitude
					inRange = distance <= radius
				end

				-- Energie fliesst nur, wenn der Spieler AUSSERDEM aktiv saugt (Taste
				-- gehalten, z.B. rechte Maustaste) -- reine Nähe allein reicht nicht mehr.
				if inRange and player:GetAttribute("IsAbsorbing") then
					local efficiency = getCollectionEfficiency(player, source.maxHealth)
					local gained = math.min(source.ratePerSecond * elapsed * efficiency, source.remainingEnergy)
					if gained > 0 then
						source.remainingEnergy -= gained
						local wholeGained = math.floor(gained)
						if _G.AwardXP then
							_G.AwardXP(player, wholeGained)
						end
						-- Heat-System: Energie absorbieren ist der einzige Weg, Hitze abzubauen.
						if _G.CoolHeatFromAbsorption then
							_G.CoolHeatFromAbsorption(player, wholeGained)
						end
						-- Erweitertes Energie-System: welcher der 5 Typen vergeben wird, hängt
						-- vom optionalen "EnergyType"-Attribut am Haus ab (Standard: "Heat" --
						-- alle unmarkierten Häuser verhalten sich also wie bisher).
						-- WICHTIG: EINMAL berechnen und für Vergabe UND visuellen Effekt nutzen --
						-- vorher bekam der Effekt fälschlich den literalen String "fire" statt
						-- des tatsächlichen Energie-Typs.
						local effectiveType = getEffectiveEnergyType(house)
						if _G.GrantTypedEnergy then
							_G.GrantTypedEnergy(player, effectiveType, wholeGained)
						end
						if _G.AwardSpecialEnergyForAbsorb then
							_G.AwardSpecialEnergyForAbsorb(player, wholeGained)
						end
						showAbsorbEffect(player, source.position, effectiveType, wholeGained)
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if activeStreams[player] then
		for house in pairs(activeStreams[player]) do
			destroyStreamBeam(player, house)
		end
		activeStreams[player] = nil
	end
end)