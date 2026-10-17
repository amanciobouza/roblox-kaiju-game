-- Rein lokale Darstellung. Vorlagen enthalten nur begrenzt viele Emitter; keine
-- serverseitigen Partikel-Instanzen oder laufenden Replikationen von Emitter-Raten.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage:WaitForChild("DestructionEffectConfig", 10))
local Visuals = {}
local function getDestructionEffectScale(maxHealth)
	return math.clamp(1 + (maxHealth ^ 0.3) * 0.3, 1, 6)
end

local function playDustCloudEffect(groundPosition, boundsSize)
	-- Wie bei einer kontrollierten Hochhaus-Sprengung: die Staubwolke breitet sich
	-- RADIAL/KREISFÖRMIG am Boden nach ALLEN SEITEN aus, statt wie Rauch nach oben zu
	-- steigen. Nutzt Robloxs EINGEBAUTE "Disk"-Emitter-Form -- die emittiert nativ radial
	-- von der Kreisfläche nach aussen, kein manuelles Rotieren einzelner Emitter nötig
	-- (der frühere Ansatz mit 28 rotierten Attachments hat aus unbekanntem Grund nicht
	-- gerendert -- dieser native Weg ist der von Roblox dafür vorgesehene).
	local footprintRadius = math.max(boundsSize.X, boundsSize.Z, 6) / 2
	local scale = math.clamp(1 + (footprintRadius ^ 0.35) * 0.5, 1.4, 5)

	local dustAnchor = Instance.new("Part")
	dustAnchor.Name = "DustCloudAnchor"
	dustAnchor.Anchored = true
	dustAnchor.CanCollide = false
	dustAnchor.CanQuery = false
	dustAnchor.CanTouch = false
	dustAnchor.CastShadow = false
	dustAnchor.Transparency = 1
	dustAnchor.Size = Vector3.new(footprintRadius * 2.2, 0.2, footprintRadius * 2.2)
	-- Um 90° gekippt, damit die Disk-Fläche FLACH/HORIZONTAL liegt (parallel zum Boden) --
	-- eine unrotierte Disk stünde sonst senkrecht wie ein Rad.
	dustAnchor.CFrame = CFrame.new(groundPosition)
	dustAnchor.Parent = workspace
	Debris:AddItem(dustAnchor, Config.DustDuration)

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "DustCloud"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 198, 192)) -- hellgrau
	dust.Shape = Enum.ParticleEmitterShape.Cylinder
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	dust.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward -- WICHTIG: emittiert radial VOM Rand weg

	-- Partikel BLÄHEN SICH AUF (klein -> gross) und werden dann wieder kleiner/verblassen
	-- -- "aufblähen und langsam verschwinden", keine aufsteigende Rauchsäule.
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 5 * scale),
		NumberSequenceKeypoint.new(0.35, 15 * scale),
		NumberSequenceKeypoint.new(0.7, 19 * scale),
		NumberSequenceKeypoint.new(1, 16 * scale),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.25, 0),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	local lifetimeScale = math.clamp(scale * 0.6, 1, 1.8)
	dust.Lifetime = NumberRange.new(2.8 * lifetimeScale, 3.6 * lifetimeScale)

	local speedScale = math.clamp(scale * 0.5, 1, 2.5)
	dust.Speed = NumberRange.new(footprintRadius * 0.35 * speedScale, footprintRadius * 0.55 * speedScale)
	dust.SpreadAngle = Vector2.new(15, 15)
	dust.Acceleration = Vector3.new(0, -6, 0) -- bremst die Steighöhe zügig, bleibt bodennah
	dust.Drag = 1.2
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-25, 25)

	-- WICHTIG: Kontinuierliche Emission über "Rate" statt einmaligem Emit()-Ausstoss --
	-- das ist exakt die Technik, die beim Feuer-Rauch (SmokePlume) nachweislich
	-- funktioniert. Ein kurzer, hoher Rate-Stoss über 0.4s erzeugt denselben "Wumms"-
	-- Effekt wie ein einmaliger Ausstoss, aber zuverlässig sichtbar.
	local totalParticles = math.clamp(math.floor(55 * scale), 40, Config.MaxDustParticles)
	dust.Rate = totalParticles / 0.4
	dust.Parent = dustAnchor

	task.delay(0.4, function()
		if dust.Parent then
			dust.Rate = 0
		end
	end)

	task.delay(Config.DustDuration, function()
		dustAnchor:Destroy()
	end)
	return dustAnchor
end

local function playDestructionSound(groundPosition)
	if Config.ExplosionSoundId == "" or Config.ExplosionSoundId == "rbxassetid://0" then
		return
	end

	local soundAnchor = Instance.new("Part")
	soundAnchor.Name = "DestructionSoundAnchor"
	soundAnchor.Anchored = true
	soundAnchor.CanCollide = false
	soundAnchor.CanQuery = false
	soundAnchor.CanTouch = false
	soundAnchor.CastShadow = false
	soundAnchor.Transparency = 1
	soundAnchor.Size = Vector3.new(1, 1, 1)
	soundAnchor.CFrame = CFrame.new(groundPosition)
	soundAnchor.Parent = workspace
	Debris:AddItem(soundAnchor, 5)

	local destructionSound = Instance.new("Sound")
	destructionSound.Name = "DestructionSound"
	destructionSound.SoundId = Config.ExplosionSoundId
	destructionSound.Volume = 1
	destructionSound.RollOffMaxDistance = Config.ViewDistance
	destructionSound.Parent = soundAnchor
	destructionSound:Play()

	return soundAnchor
end

local function playExplosionEffect(position, maxHealth)
	local groundCFrame = CFrame.new(position)

	local effectAnchor = Instance.new("Part")
	effectAnchor.Name = "ExplosionEffectAnchor"
	effectAnchor.Anchored = true
	effectAnchor.CanCollide = false
	effectAnchor.CanQuery = false
	effectAnchor.CanTouch = false
	effectAnchor.CastShadow = false
	effectAnchor.Transparency = 1
	effectAnchor.Size = Vector3.new(1, 1, 1)
	effectAnchor.CFrame = groundCFrame
	effectAnchor.Parent = workspace
	Debris:AddItem(effectAnchor, Config.ExplosionDuration)

	-- Eigenes Partikel-VFX (ServerStorage.Effects.HouseExplosionVFX) statt/zusätzlich
	-- zum generischen Roblox-Explosion-Effekt.
	local effectsFolder = ReplicatedStorage:FindFirstChild(Config.TemplateFolder)
	local vfxTemplate = effectsFolder and effectsFolder:FindFirstChild("HouseExplosionVFX")

	-- Skalierungsfaktor basierend auf der Gebäudegröße (MaxHealth) -- kleine Häuser (100 HP)
	-- bekommen jetzt spürbar größere Explosionen als vorher, riesige Mega-City-Gebäude einen
	-- gedeckelten Maximalwert (sonst würde die Explosion absurd riesig werden).
	local explosionScale = getDestructionEffectScale(maxHealth)

	if vfxTemplate and #vfxTemplate:GetChildren() > 0 then
		local vfxClone = vfxTemplate:Clone()

		-- WICHTIG: Statt uns auf PivotTo() zu verlassen (das bei manchen VFX-Assets
		-- verschachtelte Teile ohne echtes BasePart NICHT mitbewegt -- die blieben dann
		-- an ihrer Ursprungsposition, z.B. nahe (0,0,0), hängen), hängen wir JEDEN
		-- gefundenen ParticleEmitter direkt an unseren bereits korrekt positionierten
		-- effectAnchor um. So ist die Position garantiert richtig, unabhängig von der
		-- internen Struktur des VFX-Assets.
		local emitters = {}
		for _, descendant in ipairs(vfxClone:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				table.insert(emitters, descendant)
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.Transparency = 1
			end
		end

		for _, emitter in ipairs(emitters) do
			emitter.Parent = effectAnchor
			emitter.Enabled = false

			-- Partikel-Größe mit dem Skalierungsfaktor multiplizieren (jeder Keypoint
			-- der bestehenden Size-Kurve wird vergrößert, Form/Verlauf bleibt erhalten).
			local scaledKeypoints = {}
			for _, keypoint in ipairs(emitter.Size.Keypoints) do
				table.insert(
					scaledKeypoints,
					NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * explosionScale, keypoint.Envelope * explosionScale)
				)
			end
			emitter.Size = NumberSequence.new(scaledKeypoints)

			-- Mehr Partikel bei größeren Häusern, damit die Explosion auch "voller" wirkt
			local baseEmitCount = emitter:GetAttribute("EmitCount") or 30
			emitter:Emit(math.clamp(math.floor(baseEmitCount * explosionScale), 1,
				math.floor(Config.MaxExplosionParticles / math.max(#emitters, 1))))
		end

		vfxClone:Destroy() -- die leere Hülle wird nicht mehr gebraucht, nur die Emitter selbst
	else
		-- Fallback: generischer Roblox-Explosion-Effekt, falls kein eigenes VFX vorbereitet ist
		local explosion = Instance.new("Explosion")
		explosion.Position = groundCFrame.Position
		explosion.BlastRadius = 12 * explosionScale
		explosion.BlastPressure = 0 -- rein visueller Effekt, keine Wucht/Umgebungsschaden
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = workspace
		Debris:AddItem(explosion, Config.ExplosionDuration)
	end

	-- Sound wird jetzt SOFORT nach dem Zerstören abgespielt (siehe playDestructionSound
	-- weiter unten, aufgerufen direkt neben dem Staubwirbel) -- nicht mehr hier, verzögert
	-- zusammen mit der visuellen Explosion.

	task.delay(Config.ExplosionDuration, function()
		effectAnchor:Destroy()
	end)
	return effectAnchor
end

local function createFire(position, maxHealth)
	local groundCFrame = CFrame.new(position)
	-- Dieselbe gedämpfte Skalierung wie bei der Explosion (siehe getDestructionEffectScale)
	-- -- kleine Häuser brennen/rauchen spürbar kleiner als grosse, aber selbst ein
	-- Mega-City-Gebäude bekommt keine absurd riesige Feuersäule.
	local fireScale = getDestructionEffectScale(maxHealth)

	local fireAnchor = Instance.new("Part")
	fireAnchor.Name = "HouseFireAnchor"
	fireAnchor.Anchored = true
	fireAnchor.CanCollide = false
	fireAnchor.CanQuery = false
	fireAnchor.CanTouch = false
	fireAnchor.CastShadow = false
	fireAnchor.Transparency = 1
	fireAnchor.Size = Vector3.new(1, 1, 1)
	fireAnchor.CFrame = groundCFrame
	fireAnchor.Parent = workspace

	-- Lokale Kopie des Feuer-VFX (HouseFireVFX), falls vorhanden -- sonst
	-- Fallback auf Robloxs eingebautes Fire-Objekt. Genau wie bei der Explosion: ALLE
	-- ParticleEmitter im VFX werden direkt an den Anker umgehängt (unabhängig von der
	-- internen Struktur des Assets), damit die Position garantiert stimmt.
	local effectsFolder = ReplicatedStorage:FindFirstChild(Config.TemplateFolder)
	local fireVfxTemplate = effectsFolder and effectsFolder:FindFirstChild("HouseFireVFX")

	local fire, customEmitters
	if fireVfxTemplate and #fireVfxTemplate:GetChildren() > 0 then
		local vfxClone = fireVfxTemplate:Clone()
		customEmitters = {}
		for _, descendant in ipairs(vfxClone:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				table.insert(customEmitters, descendant)
			end
		end
		for _, emitter in ipairs(customEmitters) do
			emitter.Parent = fireAnchor
			emitter.Enabled = true

			-- Grösse (jeder Keypoint der bestehenden Size-Kurve) und Rate mit dem
			-- Skalierungsfaktor multiplizieren -- Form/Verlauf der Kurve bleibt erhalten,
			-- nur die Grössenordnung passt sich dem Gebäude an.
			local scaledKeypoints = {}
			for _, keypoint in ipairs(emitter.Size.Keypoints) do
				table.insert(
					scaledKeypoints,
					NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * fireScale, keypoint.Envelope * fireScale)
				)
			end
			emitter.Size = NumberSequence.new(scaledKeypoints)
			emitter.Rate = math.min(emitter.Rate * fireScale, Config.MaxFireParticleRate / math.max(#customEmitters, 1))
		end
		vfxClone:Destroy() -- leere Hülle, nicht mehr gebraucht
	else
		fire = Instance.new("Fire")
		fire.Size = 10 * fireScale
		fire.Heat = 3 * fireScale
		fire.Parent = fireAnchor
	end

	-- ParticleEmitter statt Smoke-Objekt: lässt sich als schmale, aufsteigende Rauchfahne
	-- gestalten (enger Streuwinkel, klare Aufwärtsrichtung) statt einer breiten Wolke.
	-- Grösse UND Aufsteigrate ebenfalls mit fireScale skaliert -- ein grosses Gebäude
	-- raucht spürbar mehr/breiter als ein kleines.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "SmokePlume"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 70, 75))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2 * fireScale),
		NumberSequenceKeypoint.new(0.5, 6 * fireScale),
		NumberSequenceKeypoint.new(1, 10 * fireScale),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Rate = Config.SmokeParticleRate
	smoke.Speed = NumberRange.new(6, 10)
	smoke.SpreadAngle = Vector2.new(5, 5) -- eng gehalten -> Fahne statt breiter Wolke
	smoke.Acceleration = Vector3.new(0, 2, 0) -- beschleunigt weiter nach oben, je höher sie steigt
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-20, 20)
	smoke.Parent = fireAnchor

	local rates = {}
	for _, emitter in ipairs(customEmitters or {}) do rates[emitter] = emitter.Rate end
	return { anchor = fireAnchor, fire = fire, smoke = smoke, rates = rates,
		size = fire and fire.Size, heat = fire and fire.Heat }
end

-- Absolutes Feueralter statt verzoegerter Aufgaben: nach Stream-In oder Annaeherung
-- wird die aktuelle Ausklingphase fortgesetzt, nicht erneut von vorne gestartet.
function Visuals.UpdateFire(state, remaining)
	local fadeTime = Config.FireDieDuration + Config.SmokeReduceDuration + Config.SmokeFadeDuration
	local elapsed = math.max(fadeTime - remaining, 0)
	local strength = 1 - math.clamp(elapsed / Config.FireDieDuration, 0, 1)
	if state.fire then
		state.fire.Size = state.size * strength
		state.fire.Heat = state.heat * strength
	end
	for emitter, rate in pairs(state.rates) do emitter.Rate = rate * strength end
	local smokeStrength = 1
	if elapsed > Config.FireDieDuration then
		smokeStrength = 1 - 0.6 * math.clamp((elapsed - Config.FireDieDuration) / Config.SmokeReduceDuration, 0, 1)
	end
	if elapsed > Config.FireDieDuration + Config.SmokeReduceDuration then
		smokeStrength = 0.4 * (1 - math.clamp((elapsed - Config.FireDieDuration - Config.SmokeReduceDuration) / Config.SmokeFadeDuration, 0, 1))
	end
	state.smoke.Rate = Config.SmokeParticleRate * smokeStrength
end
Visuals.Dust = playDustCloudEffect
Visuals.Sound = playDestructionSound
Visuals.Explosion = playExplosionEffect
Visuals.CreateFire = createFire
return Visuals
