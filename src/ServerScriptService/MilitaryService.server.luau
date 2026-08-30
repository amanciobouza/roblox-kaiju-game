-- VERSION: 2026-08-26 #2
-- FEATURE: despawnMilitaryForCity global exponiert (_G.DespawnMilitaryForCity)
-- Ort in Studio: ServerScriptService
--
-- Alert-Level 4: Panzer, Raketenwerfer und Militär-Helikopter greifen den Spieler aktiv
-- an. Anzahl pro Typ skaliert mit Stadtgrösse (siehe CityAlertConfig.lua,
-- MilitaryTankCount/MilitaryRocketLauncherCount/MilitaryHelicopterCount).
--
-- WICHTIG -- erwartete Modelle: ServerStorage.MilitaryModels.Tank / RocketLauncher /
-- Helicopter, jeweils mit gesetztem PrimaryPart.
--
-- WICHTIG -- erwartete Spawn-Punkte (EIGENE, separate Ordner pro Einheiten-Typ):
--   Workspace.MilitarySpawns.[Stadtname].Tank.[irgendein Name] (Parts)
--   Workspace.MilitarySpawns.[Stadtname].RocketLauncher.[irgendein Name] (Parts)
--   Workspace.MilitarySpawns.[Stadtname].Helicopter.[irgendein Name] (Parts)
--
-- Panzer bewegen sich bewusst EINFACH (nur horizontal + Höhenanpassung ans Gelände,
-- KEIN Kippen an Hängen) -- das hat sich beim Feuerwehrauto-System als deutlich
-- robuster erwiesen als komplexe Hang-Ausrichtung.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CityAlertConfig = require(ReplicatedStorage:WaitForChild("CityAlertConfig"))
-- Refactoring: das Bodenfahrzeug-Abstandssystem lebt jetzt in einem eigenen Modul --
-- gehörte konzeptionell nie wirklich hierher, da FireEngineController.lua es genauso
-- mitnutzt. Vorher als _G-Funktionen direkt hier definiert.
local GroundVehicleSeparation = require(script.Parent:WaitForChild("GroundVehicleSeparation"))

local MILITARY_SPAWNS_ROOT = "MilitarySpawns"
local LEVEL4_ALARM_SOUND_ID = "rbxassetid://93574748731319"

-- ===== Sound-IDs pro Einheit (Bewegung + Schuss) -- PLATZHALTER, bitte mit echten
-- Sound-IDs befüllen. Bewegungs-Sound läuft in Dauerschleife, solange die Einheit aktiv
-- ist; Schuss-Sound spielt einmalig bei jedem Angriff.
local UNIT_SOUNDS = {
	Tank = { movement = "rbxassetid://135855037438124", fire = "rbxassetid://119600156281658" },
	RocketLauncher = { movement = "rbxassetid://117090892434908", fire = "rbxassetid://8741569477" },
	Helicopter = { movement = "rbxassetid://4595866624", fire = "rbxassetid://123619882242196" },
}

-- [cityName] = { Tank = {unit, ...}, RocketLauncher = {...}, Helicopter = {...} }
local activeUnits = {}

-- [cityName] = Gesamtzahl aller Einheiten (Tank+RocketLauncher+Helicopter zusammen),
-- die bei der letzten Alert-Level-4-Welle gespawnt wurden -- da besiegte Einheiten aus
-- activeUnits entfernt werden, lässt sich "besiegt/gesamt" nur mit dieser zusätzlichen
-- Gesamtzahl berechnen.
local totalMilitarySpawnedByCity = {}

-- Fürs CITY-BROKEN-Task-Panel: "wie viele von wie vielen sind besiegt".
_G.GetMilitaryUnitCounts = function(cityName)
	local total = totalMilitarySpawnedByCity[cityName] or 0
	local unitsByType = activeUnits[cityName]
	local stillActive = 0
	if unitsByType then
		for _, units in pairs(unitsByType) do
			stillActive += #units
		end
	end
	return { destroyed = math.max(total - stillActive, 0), total = total }
end

-- Fürs Eskalations-Gate in CityAlertService.lua: Level 3->4 (Military) soll erst
-- weitersteigen, sobald KEINE aktiven Militär-Einheiten dieser Stadt mehr existieren.
_G.HasActiveMilitaryUnits = function(cityName)
	local unitsByType = activeUnits[cityName]
	if not unitsByType then
		return false
	end
	for _, units in pairs(unitsByType) do
		if #units > 0 then
			return true
		end
	end
	return false
end

-- ===== Boden-Höhe per Raycast (gleiches, bewährtes Muster wie FireEngineController.lua)
local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getGroundExcludeInstances()
	local excluded = {}
	local houseTag = _G.HOUSE_TAG or "KaijuHouse"
	for _, house in ipairs(game:GetService("CollectionService"):GetTagged(houseTag)) do
		table.insert(excluded, house)
	end
	for cityName, unitsByType in pairs(activeUnits) do
		for _, units in pairs(unitsByType) do
			for _, unit in ipairs(units) do
				if unit.Model then
					table.insert(excluded, unit.Model)
				end
			end
		end
	end
	return excluded
end

local function getGroundY(position, fallbackY)
	groundRayParams.FilterDescendantsInstances = getGroundExcludeInstances()
	local origin = Vector3.new(position.X, position.Y + 50, position.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -300, 0), groundRayParams)
	if result then
		return result.Position.Y
	end
	return fallbackY
end

-- ===== Billboard-Health-Bar (gleiches Muster wie BarricadeClusterService.lua) =====
local barBillboardHideGeneration = {}

local function createUnitBillboard(anchorPart, label)
	local size
	if anchorPart:IsA("Model") then
		local _, modelSize = anchorPart:GetBoundingBox()
		size = modelSize
	elseif anchorPart:IsA("BasePart") then
		size = anchorPart.Size
	else
		size = Vector3.new(4, 4, 4)
	end
	local topOffsetY = size.Y / 2 + 3

	local billboard = Instance.new("BillboardGui")
	billboard.Name = label .. "HealthBar"
	billboard.Size = UDim2.new(0, 100, 0, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500
	billboard.Enabled = true -- Militär-Einheiten zeigen ihre Health-Bar dauerhaft (im Gegensatz zu Häusern/Barrikaden), da sie aktiv bekämpft werden sollen
	billboard.Parent = anchorPart

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.new(1, 0, 0, 14)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.LuckiestGuy
	hpLabel.TextScaled = true
	hpLabel.TextColor3 = Color3.new(1, 1, 1)
	hpLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	hpLabel.TextStrokeTransparency = 0
	hpLabel.Text = label
	hpLabel.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 8)
	track.Position = UDim2.new(0, 0, 0, 16)
	track.BackgroundTransparency = 1
	track.Parent = billboard

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Thickness = 1.5
	trackStroke.Color = Color3.new(0, 0, 0)
	trackStroke.Transparency = 0.3
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(220, 70, 60) -- rot -- deutlich als "feindliche Einheit" erkennbar
	fill.BorderSizePixel = 0
	fill.Parent = track

	return billboard
end

local function updateUnitBillboard(billboard, health, maxHealth)
	if not billboard then
		return
	end
	local fill = billboard:FindFirstChild("Fill", true)
	if not fill then
		return
	end
	local ratio = math.clamp(health / math.max(maxHealth, 1), 0, 1)
	fill.Size = UDim2.new(ratio, 0, 1, 0)
end

-- ===== Alarm-Sound beim Erreichen von Level 4 (gleiches Muster wie Barrikaden-Alarm) =====
local function playLevel4Alarm(position)
	local sound = Instance.new("Sound")
	sound.Name = "MilitaryAlarm"
	sound.SoundId = LEVEL4_ALARM_SOUND_ID
	sound.Volume = 0.7
	sound.RollOffMaxDistance = 500
	sound.RollOffMinDistance = 40
	sound.Parent = Workspace

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	sound.Parent = anchor

	if sound.SoundId ~= "" and sound.SoundId ~= "rbxassetid://0" then
		sound:Play()
	end
	sound.Ended:Connect(function()
		anchor:Destroy()
	end)
	game:GetService("Debris"):AddItem(anchor, 15)
end

-- ===== Mündungsfeuer: Funken + kleine Wolke am Abschusspunkt (für ALLE Einheiten beim
-- Schiessen) =====
-- Feuer-Ausstoss an der Warhead-Position beim Abschuss -- kurzer, heisser Feuerstoss
-- (nicht wie das kühlere Mündungsfeuer/die Funken, eher wie ein Abgas-/Zünd-Ausstoss).
local function createLaunchFireEffect(position, direction)
	local anchor = Instance.new("Part")
	anchor.Name = "LaunchFireAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local fireAttachment = Instance.new("Attachment")
	fireAttachment.Parent = anchor
	if direction then
		fireAttachment.CFrame = CFrame.lookAt(Vector3.new(), direction)
	end

	local fire = Instance.new("ParticleEmitter")
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 40, 20)),
	})
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.25, 0.4)
	fire.Speed = NumberRange.new(14, 24)
	fire.SpreadAngle = Vector2.new(10, 10)
	fire.Rate = 0
	fire.LightEmission = 1
	if direction then
		fire.EmissionDirection = Enum.NormalId.Front
	end
	fire.Parent = fireAttachment
	fire:Emit(18)

	game:GetService("Debris"):AddItem(anchor, 2)
end

-- Grössere Startwolke am Abschusspunkt -- deutlich mehr Volumen als die kleine
-- Mündungswolke, bleibt kurz stehen und verzieht sich langsam.
local function createLaunchSmokeCloud(position)
	local anchor = Instance.new("Part")
	anchor.Name = "LaunchSmokeAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local smokeAttachment = Instance.new("Attachment")
	smokeAttachment.Parent = anchor
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(210, 205, 195))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.5, 6),
		NumberSequenceKeypoint.new(1, 9),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.5, 2.2)
	smoke.Speed = NumberRange.new(1, 4)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = smokeAttachment
	smoke:Emit(10)

	game:GetService("Debris"):AddItem(anchor, 3)
end


local EXPLOSION_SOUND_ID = "rbxassetid://133231415589127"

-- Explosion beim Einschlag eines Projektils (Rakete) -- deutlich grösser/dramatischer
-- als das einfache Mündungsfeuer, mit passendem Sound.
local function createProjectileExplosion(position)
	local anchor = Instance.new("Part")
	anchor.Name = "ProjectileExplosionAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	-- Feuerball.
	local fireAttachment = Instance.new("Attachment")
	fireAttachment.Parent = anchor
	local fireball = Instance.new("ParticleEmitter")
	fireball.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 130, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 40, 30)),
	})
	fireball.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0.5) })
	fireball.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	fireball.Lifetime = NumberRange.new(0.3, 0.5)
	fireball.Speed = NumberRange.new(10, 20)
	fireball.SpreadAngle = Vector2.new(180, 180)
	fireball.Rate = 0
	fireball.LightEmission = 1
	fireball.Parent = fireAttachment
	fireball:Emit(20)

	-- Rauch danach.
	local smokeAttachment = Instance.new("Attachment")
	smokeAttachment.Parent = anchor
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 85, 80))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1, 1.6)
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = smokeAttachment
	smoke:Emit(8)

	-- Kurzer heller Lichtblitz.
	local flashLight = Instance.new("PointLight")
	flashLight.Color = Color3.fromRGB(255, 200, 120)
	flashLight.Range = 20
	flashLight.Brightness = 6
	flashLight.Parent = anchor
	TweenService:Create(flashLight, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()

	local explosionSound = Instance.new("Sound")
	explosionSound.SoundId = EXPLOSION_SOUND_ID
	explosionSound.Volume = 0.9
	explosionSound.Parent = anchor
	if explosionSound.SoundId ~= "" and explosionSound.SoundId ~= "rbxassetid://0" then
		explosionSound:Play()
	end

	game:GetService("Debris"):AddItem(anchor, 3)
end

local function createMuzzleEffect(position, direction)
	local anchor = Instance.new("Part")
	anchor.Name = "MuzzleEffectAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	-- Funken: kurzer, gerichteter Burst in Schussrichtung.
	local sparkAttachment = Instance.new("Attachment")
	sparkAttachment.Parent = anchor
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkle_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100), Color3.fromRGB(255, 255, 255))
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.15, 0.3)
	sparks.Speed = NumberRange.new(12, 22)
	sparks.SpreadAngle = Vector2.new(15, 15)
	sparks.Rate = 0
	sparks.LightEmission = 1
	if direction then
		sparks.EmissionDirection = Enum.NormalId.Front
		sparkAttachment.CFrame = CFrame.lookAt(Vector3.new(), direction)
	end
	sparks.Parent = sparkAttachment
	task.wait()
	sparks:Emit(16)

	-- Rauch-/Mündungswolke: expandiert kurz und blendet aus.
	local cloudAttachment = Instance.new("Attachment")
	cloudAttachment.Parent = anchor
	local cloud = Instance.new("ParticleEmitter")
	cloud.Texture = "rbxasset://textures/particles/smoke_main.dds"
	cloud.Color = ColorSequence.new(Color3.fromRGB(220, 220, 225))
	cloud.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(0.5, 4), NumberSequenceKeypoint.new(1, 5) })
	cloud.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.4), NumberSequenceKeypoint.new(1, 1) })
	cloud.Lifetime = NumberRange.new(0.8, 1.1)
	cloud.Speed = NumberRange.new(2, 5)
	cloud.SpreadAngle = Vector2.new(25, 25)
	cloud.Rate = 0
	if direction then
		cloud.EmissionDirection = Enum.NormalId.Front
		cloudAttachment.CFrame = CFrame.lookAt(Vector3.new(), direction)
	end
	cloud.Parent = cloudAttachment
	task.wait()
	cloud:Emit(20)

	game:GetService("Debris"):AddItem(anchor, 2)
end

-- ===== Sichtbare Rakete mit Rauchfahne: fliegt vom Abschusspunkt zum Ziel, dann Impact
-- + Schaden. =====
local ROCKET_FLIGHT_DURATION = 0.8

-- Berechnet eine CFrame, bei der die LÄNGSACHSE des Zylinders (lokale X-Achse bei
-- Enum.PartType.Cylinder) exakt entlang "direction" zeigt -- robuster als
-- CFrame.lookAt() + nachträgliche Korrektur-Rotation, da hier direkt die passende
-- Achse gesetzt wird, statt sich auf eine Rotations-Reihenfolge zu verlassen.
local function cylinderOrientedCFrame(position, direction)
	if direction.Magnitude < 0.001 then
		return CFrame.new(position)
	end
	local rightAxis = direction.Unit -- wird zur Längsachse (lokale X-Achse) des Zylinders
	local worldUp = Vector3.new(0, 1, 0)
	if math.abs(rightAxis:Dot(worldUp)) > 0.99 then
		worldUp = Vector3.new(1, 0, 0) -- Fallback, falls die Richtung fast senkrecht ist
	end
	local upAxis = rightAxis:Cross(worldUp):Cross(rightAxis).Unit
	return CFrame.fromMatrix(position, rightAxis, upAxis)
end

local function fireVisibleRocket(fromPosition, toPosition, onImpact)
	local rocket = Instance.new("Part")
	rocket.Name = "MilitaryRocket"
	rocket.Shape = Enum.PartType.Cylinder
	rocket.Size = Vector3.new(2.2, 0.5, 0.5)
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanQuery = false
	rocket.Material = Enum.Material.Metal
	rocket.Color = Color3.fromRGB(80, 80, 85)
	rocket.CFrame = cylinderOrientedCFrame(fromPosition, toPosition - fromPosition)
	rocket.Parent = Workspace

	-- Rauchfahne: Trail zwischen zwei Attachments am Heck der Rakete. Dicker und
	-- langsamer auflösend als vorher.
	local trailAttachment0 = Instance.new("Attachment")
	trailAttachment0.Position = Vector3.new(-1, 0, 0.2)
	trailAttachment0.Parent = rocket
	local trailAttachment1 = Instance.new("Attachment")
	trailAttachment1.Position = Vector3.new(-1, 0, -0.2)
	trailAttachment1.Parent = rocket

	local trail = Instance.new("Trail")
	trail.Attachment0 = trailAttachment0
	trail.Attachment1 = trailAttachment1
	trail.Color = ColorSequence.new(Color3.fromRGB(220, 220, 220))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 1.8 -- deutlich länger als vorher (0.6) -- löst sich langsamer auf
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 5) }) -- deutlich dicker als vorher
	trail.Parent = rocket

	-- Feuerdüse: kontinuierliche Flamme am Heck während des ganzen Flugs, plus ein
	-- Leuchten (PointLight) am Antrieb -- die Rakete wirkt dadurch aktiv angetrieben,
	-- nicht nur ein fliegendes Metallteil mit Rauch dahinter.
	local engineAttachment = Instance.new("Attachment")
	engineAttachment.Position = Vector3.new(-1.1, 0, 0)
	engineAttachment.Parent = rocket

	local engineFlame = Instance.new("ParticleEmitter")
	engineFlame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 150, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 50, 20)),
	})
	engineFlame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.1) })
	engineFlame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.8) })
	engineFlame.Lifetime = NumberRange.new(0.12, 0.2)
	engineFlame.Speed = NumberRange.new(6, 10)
	engineFlame.Rate = 60
	engineFlame.LightEmission = 1
	engineFlame.EmissionDirection = Enum.NormalId.Back
	engineFlame.Parent = engineAttachment

	local engineGlow = Instance.new("PointLight")
	engineGlow.Color = Color3.fromRGB(255, 170, 80)
	engineGlow.Range = 8
	engineGlow.Brightness = 3
	engineGlow.Parent = engineAttachment

	local startTime = os.clock()
	task.spawn(function()
		while os.clock() - startTime < ROCKET_FLIGHT_DURATION and rocket.Parent do
			local t = (os.clock() - startTime) / ROCKET_FLIGHT_DURATION
			local currentPosition = fromPosition:Lerp(toPosition, t)
			-- Leichter Bogen nach oben, damit die Flugbahn nicht stur geradlinig wirkt.
			currentPosition = currentPosition + Vector3.new(0, math.sin(t * math.pi) * 4, 0)
			-- WICHTIG: gleiche Hilfsfunktion wie beim Spawnen -- vorher fehlte die
			-- Korrektur hier, wodurch die Rakete ab dem ersten Frame quer statt längs flog.
			local nextPositionEstimate = fromPosition:Lerp(toPosition, math.min(t + 0.02, 1))
			nextPositionEstimate = nextPositionEstimate + Vector3.new(0, math.sin(math.min(t + 0.02, 1) * math.pi) * 4, 0)
			rocket.CFrame = cylinderOrientedCFrame(currentPosition, nextPositionEstimate - currentPosition)
			task.wait()
		end

		local impactPosition = rocket.Parent and rocket.Position or toPosition
		if rocket.Parent then
			rocket:Destroy()
		end
		createProjectileExplosion(impactPosition)
		if onImpact then
			onImpact()
		end
	end)
end

-- ===== Panzergranate: existierte bisher nur als Aufruf, nie als tatsächliche Funktion
-- (dadurch stürzte JEDER Panzer-Schuss ab, inkl. Rückstoss/Zittern, die im Code danach
-- stehen und dadurch nie erreicht wurden). Analog zu fireVisibleRocket, aber deutlich
-- schneller/direkter (keine Bogenflugbahn, kein Rauch-Trail) -- eine Panzergranate fliegt
-- viel zu schnell für sichtbaren Rauch, stattdessen eine kurze, helle Leuchtspur.
local TANK_SHELL_FLIGHT_DURATION = 0.25

local function fireTankShell(fromPosition, toPosition, onImpact)
	local shell = Instance.new("Part")
	shell.Name = "TankShell"
	shell.Shape = Enum.PartType.Cylinder
	shell.Size = Vector3.new(1, 0.3, 0.3)
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.Material = Enum.Material.Metal
	shell.Color = Color3.fromRGB(60, 60, 65)
	shell.CFrame = cylinderOrientedCFrame(fromPosition, toPosition - fromPosition)
	shell.Parent = Workspace

	-- Leuchtspur (Tracer) statt Rauchfahne -- kurz und hell, passt zu einer schnell
	-- fliegenden Granate statt einer angetriebenen Rakete.
	local trailAttachment0 = Instance.new("Attachment")
	trailAttachment0.Position = Vector3.new(-0.5, 0, 0)
	trailAttachment0.Parent = shell
	local trailAttachment1 = Instance.new("Attachment")
	trailAttachment1.Position = Vector3.new(0.5, 0, 0)
	trailAttachment1.Parent = shell

	local trail = Instance.new("Trail")
	trail.Attachment0 = trailAttachment0
	trail.Attachment1 = trailAttachment1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.3
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Parent = shell

	local startTime = os.clock()
	task.spawn(function()
		while os.clock() - startTime < TANK_SHELL_FLIGHT_DURATION and shell.Parent do
			local t = (os.clock() - startTime) / TANK_SHELL_FLIGHT_DURATION
			local currentPosition = fromPosition:Lerp(toPosition, t)
			shell.CFrame = cylinderOrientedCFrame(currentPosition, toPosition - fromPosition)
			task.wait()
		end

		local impactPosition = shell.Parent and shell.Position or toPosition
		if shell.Parent then
			shell:Destroy()
		end
		createProjectileExplosion(impactPosition)
		if onImpact then
			onImpact()
		end
	end)
end


local function findNearestPlayerInCity(cityName, fromPosition)
	local nearest, nearestDistance = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName and player.Character then
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if rootPart and humanoid and humanoid.Health > 0 then
				local distance = (rootPart.Position - fromPosition).Magnitude
				if distance < nearestDistance then
					nearest, nearestDistance = player, distance
				end
			end
		end
	end
	return nearest
end

-- ===== Reaktive Spawn-Punkte finden (EIGENE, separat von Barrikaden) =====
-- Erwartet eigene Ordner pro Einheiten-Typ statt eines gemeinsamen:
-- Workspace.MilitarySpawns.[Stadt].Tank / .RocketLauncher / .Helicopter
local function getMilitarySpawnPoints(cityName, unitType)
	local root = Workspace:FindFirstChild(MILITARY_SPAWNS_ROOT)
	if not root then
		return {}
	end
	local cityFolder = root:FindFirstChild(cityName)
	if not cityFolder then
		return {}
	end
	local typeFolder = cityFolder:FindFirstChild(unitType)
	if not typeFolder then
		return {}
	end
	local points = {}
	for _, child in ipairs(typeFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	return points
end

local function pickRandomSpawnPoint(cityName, unitType)
	local points = getMilitarySpawnPoints(cityName, unitType)
	if #points == 0 then
		return nil
	end
	return points[math.random(1, #points)]
end

-- ===== Schaden-API (für Kampf-Scripts) =====
_G.DamageMilitaryUnit = function(cityName, unitType, unitId, amount, attackerPlayer)
	local unitsByType = activeUnits[cityName]
	local units = unitsByType and unitsByType[unitType]
	if not units then
		return false
	end
	for i, unit in ipairs(units) do
		if unit.Id == unitId then
			unit.Health = math.max(0, unit.Health - amount)
			updateUnitBillboard(unit.Billboard, unit.Health, unit.MaxHealth)
			if unit.Health <= 0 then
				if unit.Model then
					GroundVehicleSeparation.Unregister(unit.Model)
					unit.Model:Destroy()
				end
				table.remove(units, i)

				-- Achievements: "Erste Militär-Einheit besiegt".
				if attackerPlayer and _G.OnMilitaryUnitDestroyedForAchievements then
					_G.OnMilitaryUnitDestroyedForAchievements(attackerPlayer)
				end

				-- Eskalation SOFORT prüfen, sobald die letzte Militär-Einheit dieser
				-- Stadt fällt.
				if _G.HasActiveMilitaryUnits and not _G.HasActiveMilitaryUnits(cityName) and _G.CheckCityAlertLevelThresholds then
					_G.CheckCityAlertLevelThresholds(cityName)
				end
				return true
			end
			return false
		end
	end
	return false
end

_G.GetMilitaryUnitInfo = function(model)
	local cityName = model:GetAttribute("CityName")
	local unitType = model:GetAttribute("UnitType")
	local unitId = model:GetAttribute("UnitId")
	return cityName, unitType, unitId
end

-- ===== Spawnen einer einzelnen Einheit =====
local nextUnitId = 1

local function spawnUnit(cityName, unitType, templateFolder, spawnPart, config)
	local template = templateFolder:FindFirstChild(unitType)
	if not template then
		warn("[MilitaryService] ServerStorage.MilitaryModels." .. unitType .. " nicht gefunden -- Einheit übersprungen.")
		return nil
	end

	local model = template:Clone()
	model.Name = unitType .. "_" .. cityName .. "_" .. nextUnitId
	if not model.PrimaryPart then
		warn("[MilitaryService] " .. unitType .. "-Modell hat keinen PrimaryPart -- Einheit übersprungen.")
		model:Destroy()
		return nil
	end
	model:PivotTo(spawnPart.CFrame)
	model.Parent = Workspace

	-- Bodenfahrzeuge sofort registrieren, damit andere Fahrzeuge sie von Anfang an als
	-- Hindernis kennen -- Helikopter bewusst ausgenommen (fliegen, kein Bodenabstand nötig).
	if unitType == "Tank" or unitType == "RocketLauncher" then
		GroundVehicleSeparation.RegisterPosition(model, unitType, spawnPart.Position)
	end

	local unitId = nextUnitId
	nextUnitId += 1
	model:SetAttribute("CityName", cityName)
	model:SetAttribute("UnitType", unitType)
	model:SetAttribute("UnitId", unitId)
	CollectionService:AddTag(model, "MilitaryUnit")

	local maxHealth = config[unitType .. "HP"] or 5000
	local billboard = createUnitBillboard(model.PrimaryPart, unitType)

	-- Bewegungs-Sound in Dauerschleife (falls eine ID hinterlegt ist) -- läuft, solange
	-- die Einheit existiert, egal ob sie sich gerade bewegt oder steht (einfacher als ein
	-- Start/Stopp-Zustand, reicht für ein "Motor läuft"-Gefühl).
	local soundIds = UNIT_SOUNDS[unitType] or {}
	local movementSound = nil
	if soundIds.movement and soundIds.movement ~= "" then
		movementSound = Instance.new("Sound")
		movementSound.Name = "MovementSound"
		movementSound.SoundId = soundIds.movement
		movementSound.Looped = true
		movementSound.Volume = 0.6
		movementSound.RollOffMaxDistance = 300
		movementSound.RollOffMinDistance = 25
		movementSound.Parent = model.PrimaryPart
		movementSound:Play()
	end

	local unit = {
		Id = unitId,
		Model = model,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Billboard = billboard,
		LastAttackAt = 0,
	}
	return unit
end



-- ===== Panzer-Verhalten: bewegt sich einfach (nur horizontal + Höhe) auf den Spieler
-- zu, bleibt in Angriffsreichweite stehen und feuert periodisch. =====
local TANK_GROUND_CLEARANCE = 3
local TANK_ATTACK_COOLDOWN = 8
local TANK_DUST_INTERVAL = 0.3 -- Sekunden zwischen zwei Staubwolken-Ausstössen beim Fahren

-- Kleine Staubwolke hinter dem Panzer -- expandiert kurz und blendet aus.
local function createTankDustCloud(position, behindDirection)
	local anchor = Instance.new("Part")
	anchor.Name = "TankDustAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position - behindDirection * 3 + Vector3.new(0, 0.5, 0))
	anchor.Parent = Workspace

	local dustAttachment = Instance.new("Attachment")
	dustAttachment.Parent = anchor
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(180, 165, 140))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.7, 1.1)
	dust.Speed = NumberRange.new(1, 3)
	dust.Rate = 0
	dust.Parent = dustAttachment
	dust:Emit(4)

	game:GetService("Debris"):AddItem(anchor, 2)
end

local function updateTank(cityName, unit, config)
	if not unit.Model or not unit.Model.Parent then
		return
	end
	local target = findNearestPlayerInCity(cityName, unit.Model.PrimaryPart.Position)
	if not target or not target.Character then
		return
	end
	local rootPart = target.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then
		return
	end

	local currentPosition = unit.Model.PrimaryPart.Position
	local toTarget = rootPart.Position - currentPosition
	local horizontalToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	local distance = horizontalToTarget.Magnitude
	local attackRange = config.TankAttackRange or 60

	if distance > attackRange then
		-- Bewegt sich auf den Spieler zu -- NUR horizontal + Höhenanpassung, kein Kippen.
		-- WICHTIG: bremst bis knapp INNERHALB der Reichweite ab (attackRange - 2), nicht
		-- exakt bis an die Grenze -- sonst könnten Rundungsungenauigkeiten dazu führen,
		-- dass "distance" hauchdünn über attackRange hängen bleibt und der Panzer nie in
		-- den Angriffs-Zweig wechselt (steht dann scheinbar in Reichweite, greift aber nie an).
		local effectiveStopDistance = math.max(attackRange - 2, 0)
		local direction = horizontalToTarget.Unit
		local speed = config.TankSpeed or 12
		local step = direction * speed * RunService.Heartbeat:Wait()
		if step.Magnitude > distance - effectiveStopDistance then
			step = direction * math.max(distance - effectiveStopDistance, 0)
		end
		local newPosition = currentPosition + step
		local groundY = getGroundY(newPosition, currentPosition.Y)
		newPosition = Vector3.new(newPosition.X, groundY + TANK_GROUND_CLEARANCE, newPosition.Z)
		-- Mindestabstand zu anderen Bodenfahrzeugen einhalten, bevor die finale Position
		-- übernommen wird.
		newPosition = GroundVehicleSeparation.ApplySeparation(unit.Model, "Tank", newPosition)
		GroundVehicleSeparation.RegisterPosition(unit.Model, "Tank", newPosition)
		local facingCFrame = CFrame.lookAt(newPosition, newPosition + direction)
		unit.Model:PivotTo(facingCFrame)

		-- Staubwolke hinter dem Fahrzeug, gedrosselt.
		if os.clock() - (unit.LastDustAt or 0) >= TANK_DUST_INTERVAL then
			unit.LastDustAt = os.clock()
			createTankDustCloud(newPosition, direction)
		end
	else
		-- In Reichweite -- zum Spieler ausrichten und periodisch angreifen.
		local facingCFrame = CFrame.lookAt(currentPosition, currentPosition + horizontalToTarget.Unit)
		GroundVehicleSeparation.RegisterPosition(unit.Model, "Tank", currentPosition)

		if os.clock() - unit.LastAttackAt >= TANK_ATTACK_COOLDOWN then
			unit.LastAttackAt = os.clock()

			-- Kanonenrohr-Position: nutzt den tatsächlichen "CannonMuzzle"-Part/Attachment
			-- im Modell (einmalig gesucht, danach am Unit gecacht) -- deutlich präziser als
			-- ein geschätzter Höhen-Offset. Fällt nur zurück, falls im Modell keiner
			-- gefunden wird.
			if unit.CannonMuzzleObject == nil and unit.CannonMuzzleSearched == nil then
				unit.CannonMuzzleSearched = true
				unit.CannonMuzzleObject = unit.Model:FindFirstChild("CannonMuzzle", true)
				if not unit.CannonMuzzleObject then
					warn("[MilitaryService] Kein 'CannonMuzzle'-Part/Attachment in " .. unit.Model:GetFullName() .. " gefunden -- nutze geschätzten Höhen-Offset stattdessen.")
				end
			end

			local muzzlePosition
			if unit.CannonMuzzleObject and unit.CannonMuzzleObject.Parent then
				muzzlePosition = unit.CannonMuzzleObject:IsA("Attachment")
					and unit.CannonMuzzleObject.WorldPosition
					or unit.CannonMuzzleObject.Position
			else
				-- Fallback: PrimaryPart liegt vermutlich auf Chassis-/Bodenhöhe, nicht auf
				-- Kanonenrohr-Höhe -- geschätzter Offset, falls kein CannonMuzzle gefunden wurde.
				muzzlePosition = currentPosition + horizontalToTarget.Unit * 4 + Vector3.new(0, 4, 0)
			end

			createMuzzleEffect(muzzlePosition, horizontalToTarget.Unit)
			local fireSoundId = (UNIT_SOUNDS.Tank and UNIT_SOUNDS.Tank.fire) or ""
			if fireSoundId ~= "" then
				local fireSound = Instance.new("Sound")
				fireSound.SoundId = fireSoundId
				fireSound.Volume = 0.8
				fireSound.Parent = unit.Model.PrimaryPart
				fireSound:Play()
				game:GetService("Debris"):AddItem(fireSound, 3)
			end
			local shellStartPosition = muzzlePosition
			local shellTargetPosition = rootPart.Position
			fireTankShell(shellStartPosition, shellTargetPosition, function()
				if humanoid.Parent and humanoid.Health > 0 then
					humanoid:TakeDamage(config.TankDamage or 25)
				end
			end)

			-- Rückstoss auslösen -- wird unten (bei der Ausrichtung "in Reichweite")
			-- als abklingender Wert mit eingerechnet, statt über eine separate,
			-- konkurrierende Bewegungs-Schleife (die mit der normalen PivotTo-Logik
			-- kollidieren würde -- gleiches Problem wie beim Feuerwehrauto-System).
			unit.TankRecoilAmount = 1
			-- Zusätzliches, ECHTES Zittern (zufällige kleine Ausschläge) obendrauf --
			-- der reine Rückstoss allein wirkt als sanfte, gerichtete Kippbewegung, das
			-- Zittern soll den Feuerstoss zusätzlich klar spürbar/sichtbar machen.
			unit.TankShakeAmount = 1
		end

		-- Rückstoss-Wackeln: klingt über ein paar Frames ab, fliesst in dieselbe
		-- PivotTo-Zuweisung wie die normale Ausrichtung mit ein.
		if unit.TankRecoilAmount and unit.TankRecoilAmount > 0.01 then
			local recoilOffset = CFrame.new(0, 0, 1.0 * unit.TankRecoilAmount) * CFrame.Angles(math.rad(2 * unit.TankRecoilAmount), 0, 0)
			facingCFrame = facingCFrame * recoilOffset
			unit.TankRecoilAmount = unit.TankRecoilAmount * 0.8 -- klingt exponentiell ab
		end
		-- Zufälliges Zittern: kleine, in jede Richtung zufällig schwankende Ausschläge,
		-- klingt schneller ab als der Rückstoss selbst (kurz und knackig statt lang
		-- nachschwingend).
		if unit.TankShakeAmount and unit.TankShakeAmount > 0.01 then
			local shakeStrength = 0.15 * unit.TankShakeAmount
			local shakeOffset = CFrame.new(
				(math.random() - 0.5) * shakeStrength,
				(math.random() - 0.5) * shakeStrength,
				0
			) * CFrame.Angles(
				math.rad((math.random() - 0.5) * 4 * unit.TankShakeAmount),
				math.rad((math.random() - 0.5) * 4 * unit.TankShakeAmount),
				math.rad((math.random() - 0.5) * 4 * unit.TankShakeAmount)
			)
			facingCFrame = facingCFrame * shakeOffset
			unit.TankShakeAmount = unit.TankShakeAmount * 0.6 -- klingt deutlich schneller ab als der Rückstoss
		end
		unit.Model:PivotTo(facingCFrame)
	end
end

-- ===== Raketenwerfer-Verhalten: stationär, feuert periodisch auf Spieler in
-- Reichweite. =====
local ROCKET_LAUNCHER_ATTACK_COOLDOWN = 3.5

local function updateRocketLauncher(cityName, unit, config)
	if not unit.Model or not unit.Model.Parent then
		return
	end
	local currentPosition = unit.Model.PrimaryPart.Position
	local target = findNearestPlayerInCity(cityName, currentPosition)
	if not target or not target.Character then
		return
	end
	local rootPart = target.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then
		return
	end

	local toTarget = rootPart.Position - currentPosition
	local horizontalToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	local distance = horizontalToTarget.Magnitude
	local attackRange = config.RocketLauncherAttackRange or 100

	if horizontalToTarget.Magnitude > 0.1 then
		-- 180°-Korrektur: das Modell ist mit umgekehrter Vorderseite aufgebaut, ohne
		-- diese Korrektur zeigt es vom Ziel weg statt darauf.
		local facingCFrame = CFrame.lookAt(currentPosition, currentPosition + horizontalToTarget.Unit) * CFrame.Angles(0, math.rad(180), 0)
		unit.Model:PivotTo(facingCFrame)
	end

	if distance <= attackRange and os.clock() - unit.LastAttackAt >= ROCKET_LAUNCHER_ATTACK_COOLDOWN then
		unit.LastAttackAt = os.clock()

		-- Exakte Mündungspunkte nutzen (LauncherTurret.MissileRack.MissileMuzzle1-6),
		-- reihum durch alle sechs -- Fallback auf eine berechnete Position, falls die
		-- Struktur mal nicht passt.
		local launchPosition = currentPosition + horizontalToTarget.Unit * 3 + Vector3.new(0, 1, 0)
		local missileRack = unit.Model:FindFirstChild("MissileRack", true)
		if missileRack then
			unit.RocketMuzzleIndex = (unit.RocketMuzzleIndex or 0) % 6 + 1
			local muzzle = missileRack:FindFirstChild("MissileMuzzle" .. unit.RocketMuzzleIndex)
			if muzzle then
				launchPosition = muzzle:IsA("BasePart") and muzzle.Position or muzzle:GetPivot().Position
			end

			-- Feuer-Ausstoss an der zum abgefeuerten Geschoss passenden Warhead-Position
			-- (gleicher Index wie der genutzte Mündungspunkt).
			local warhead = missileRack:FindFirstChild("Warhead" .. unit.RocketMuzzleIndex)
			if warhead then
				local warheadPosition = warhead:IsA("BasePart") and warhead.Position or warhead:GetPivot().Position
				createLaunchFireEffect(warheadPosition, horizontalToTarget.Unit)
			end
		end
		createMuzzleEffect(launchPosition, horizontalToTarget.Unit)
		createLaunchSmokeCloud(launchPosition)

		local fireSoundId = (UNIT_SOUNDS.RocketLauncher and UNIT_SOUNDS.RocketLauncher.fire) or ""
		if fireSoundId ~= "" then
			local fireSound = Instance.new("Sound")
			fireSound.SoundId = fireSoundId
			fireSound.Volume = 0.85
			fireSound.Parent = unit.Model.PrimaryPart
			fireSound:Play()
			game:GetService("Debris"):AddItem(fireSound, 3)
		end

		-- Sichtbare Rakete mit Rauchfahne -- Schaden erst beim Einschlag, nicht sofort.
		local targetPositionAtLaunch = rootPart.Position
		fireVisibleRocket(launchPosition, targetPositionAtLaunch, function()
			if humanoid.Parent and humanoid.Health > 0 then
				humanoid:TakeDamage(config.RocketLauncherDamage or 40)
			end
		end)
	end
end

-- ===== Helikopter-Verhalten: fliegt NAH an den Spieler heran, feuert eine kurze Salve,
-- zieht sich dann elliptisch zurück ("Nachladen"), kehrt danach zurück -- statt
-- dauerhaft zu hovern und ununterbrochen zu feuern. =====
local HELICOPTER_CLOSE_RANGE = 35 -- Studs -- wie nah der Helikopter beim Anflug herankommt
local HELICOPTER_RETREAT_DISTANCE = 100 -- Studs -- wie weit er sich beim Rückzug entfernt
local HELICOPTER_BURST_SHOT_COUNT = 3 -- Schüsse pro Salve
local HELICOPTER_BURST_SHOT_INTERVAL = 0.35 -- Sekunden zwischen den Schüssen EINER Salve
local HELICOPTER_RELOAD_DURATION = 3 -- Sekunden "Nachladen" am Rückzugspunkt, bevor er erneut anfliegt
local HELICOPTER_ARRIVAL_THRESHOLD = 8 -- Studs -- gilt als "angekommen" am Ziel-Punkt
local HELICOPTER_MIN_HEIGHT_ABOVE_GROUND = 18 -- Studs -- Mindest-Flughöhe über dem TATSÄCHLICHEN Gelände, unabhängig von der Spieler-Position
local HELICOPTER_HEIGHT_ABOVE_TARGET = 25 -- Studs -- Ziel-Flughöhe über dem Spieler

local function fireHelicopterShot(unit, currentPosition, targetPosition, humanoid, config)
	local toTargetDirection = (targetPosition - currentPosition)
	if toTargetDirection.Magnitude < 0.01 then
		return
	end
	toTargetDirection = toTargetDirection.Unit

	-- Exakte Mündungspunkte nutzen (Helicopter.RocketPods.LeftRocketMuzzle /
	-- RightRocketMuzzle), abwechselnd links/rechts pro Schuss -- Fallback auf eine
	-- berechnete Position, falls die Struktur mal nicht passt.
	local launchPosition = currentPosition + toTargetDirection * 3
	local rocketPods = unit.Model:FindFirstChild("RocketPods", true)
	if rocketPods then
		unit.HeliNextMuzzleSide = unit.HeliNextMuzzleSide == "Right" and "Left" or "Right"
		local muzzle = rocketPods:FindFirstChild(unit.HeliNextMuzzleSide .. "RocketMuzzle")
		if muzzle then
			launchPosition = muzzle:IsA("BasePart") and muzzle.Position or muzzle:GetPivot().Position
		end
	end

	-- Mündungsfeuer vorne + zusätzliche kleine Wolke am HECK des Raketenwerfers
	-- (entgegen der Schussrichtung -- sieht aus wie Abgas-/Rückstoss-Rauch beim Abschuss).
	createMuzzleEffect(launchPosition, toTargetDirection)
	createMuzzleEffect(launchPosition - toTargetDirection * 2, -toTargetDirection)

	local fireSoundId = (UNIT_SOUNDS.Helicopter and UNIT_SOUNDS.Helicopter.fire) or ""
	if fireSoundId ~= "" then
		local fireSound = Instance.new("Sound")
		fireSound.SoundId = fireSoundId
		fireSound.Volume = 0.75
		fireSound.Parent = unit.Model.PrimaryPart
		fireSound:Play()
		game:GetService("Debris"):AddItem(fireSound, 3)
	end

	-- Sichtbare Rakete mit Rauchstreifen -- Schaden erst beim Einschlag, nicht sofort
	-- (gleiche Funktion wie beim Raketenwerfer, für konsistentes Aussehen).
	fireVisibleRocket(launchPosition, targetPosition, function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid:TakeDamage(config.HelicopterDamage or 10)
		end
	end)
end

local function updateHelicopterUnit(cityName, unit, config)
	if not unit.Model or not unit.Model.Parent then
		return
	end
	local currentPosition = unit.Model.PrimaryPart.Position
	local target = findNearestPlayerInCity(cityName, currentPosition)
	if not target or not target.Character then
		return
	end
	local rootPart = target.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then
		return
	end

	-- Zustand pro Einheit initialisieren, falls noch nicht vorhanden.
	if not unit.HeliState then
		unit.HeliState = "Approach"
		unit.HeliBurstShotsLeft = HELICOPTER_BURST_SHOT_COUNT
		unit.HeliStateChangedAt = os.clock()
		unit.HeliRetreatAngle = math.random() * math.pi * 2
		unit.HeliApproachAngle = math.random() * math.pi * 2
	end

	local desiredPosition
	if unit.HeliState == "Approach" or unit.HeliState == "Burst" then
		-- WICHTIG: hält einen horizontalen Mindestabstand zum Spieler (wie der
		-- AlertHelicopterService aus Level 1) -- vorher zielte der Anflug direkt ÜBER den
		-- Spieler (0 horizontaler Abstand), obwohl HELICOPTER_CLOSE_RANGE definiert war,
		-- aber nie tatsächlich für die Zielposition verwendet wurde.
		local offset = Vector3.new(math.cos(unit.HeliApproachAngle), 0, math.sin(unit.HeliApproachAngle)) * HELICOPTER_CLOSE_RANGE
		desiredPosition = rootPart.Position + offset + Vector3.new(0, HELICOPTER_HEIGHT_ABOVE_TARGET, 0)
	elseif unit.HeliState == "Retreat" or unit.HeliState == "Reload" then
		-- Elliptischer Rückzugspunkt: Winkel-Versatz um den Spieler, weiter weg + höher.
		local offset = Vector3.new(math.cos(unit.HeliRetreatAngle), 0, math.sin(unit.HeliRetreatAngle)) * HELICOPTER_RETREAT_DISTANCE
		desiredPosition = rootPart.Position + offset + Vector3.new(0, HELICOPTER_HEIGHT_ABOVE_TARGET + 15, 0)
	else
		desiredPosition = currentPosition
	end

	local toDesired = desiredPosition - currentPosition
	local distance = toDesired.Magnitude

	if distance > 5 then
		local direction = toDesired.Unit
		local speed = config.HelicopterSpeed or 18
		local step = direction * speed * RunService.Heartbeat:Wait()
		if step.Magnitude > distance then
			step = toDesired
		end
		local newPosition = currentPosition + step

		-- Mindest-Flughöhe über dem TATSÄCHLICHEN Gelände (nicht nur relativ zum
		-- Spieler) -- verhindert zu tiefes Fliegen, z.B. wenn der Spieler in einer Senke
		-- steht oder der Helikopter über abfallendes Terrain fliegt.
		local groundY = getGroundY(newPosition, newPosition.Y - HELICOPTER_MIN_HEIGHT_ABOVE_GROUND)
		local minY = groundY + HELICOPTER_MIN_HEIGHT_ABOVE_GROUND
		if newPosition.Y < minY then
			newPosition = Vector3.new(newPosition.X, minY, newPosition.Z)
		end

		local facingDirection
		if unit.HeliState == "Retreat" or unit.HeliState == "Reload" then
			-- Beim Rückzug in FLUGRICHTUNG ausrichten, nicht mehr zum Spieler --
			-- sieht sonst so aus, als würde der Helikopter rückwärts wegfliegen.
			facingDirection = Vector3.new(direction.X, 0, direction.Z)
		else
			facingDirection = Vector3.new(rootPart.Position.X - newPosition.X, 0, rootPart.Position.Z - newPosition.Z)
		end
		local facingCFrame = facingDirection.Magnitude > 0.1
			and CFrame.lookAt(newPosition, newPosition + facingDirection.Unit)
			or CFrame.new(newPosition)
		unit.Model:PivotTo(facingCFrame)
		currentPosition = newPosition
	end

	-- Zustandsübergänge.
	if unit.HeliState == "Approach" then
		if distance <= HELICOPTER_ARRIVAL_THRESHOLD then
			unit.HeliState = "Burst"
			unit.HeliBurstShotsLeft = HELICOPTER_BURST_SHOT_COUNT
			unit.HeliStateChangedAt = os.clock()
			unit.LastAttackAt = 0 -- erlaubt sofort den ersten Schuss der Salve
		end
	elseif unit.HeliState == "Burst" then
		if unit.HeliBurstShotsLeft > 0 and os.clock() - unit.LastAttackAt >= HELICOPTER_BURST_SHOT_INTERVAL then
			unit.LastAttackAt = os.clock()
			unit.HeliBurstShotsLeft -= 1
			fireHelicopterShot(unit, currentPosition, rootPart.Position, humanoid, config)
		end
		if unit.HeliBurstShotsLeft <= 0 then
			-- Salve fertig -- zurückziehen zum Nachladen. Neue zufällige Winkel für
			-- Abwechslung bei jedem Rückzug + dem nächsten Anflug.
			unit.HeliState = "Retreat"
			unit.HeliRetreatAngle = math.random() * math.pi * 2
			unit.HeliApproachAngle = math.random() * math.pi * 2
			unit.HeliStateChangedAt = os.clock()
		end
	elseif unit.HeliState == "Retreat" then
		if distance <= HELICOPTER_ARRIVAL_THRESHOLD then
			unit.HeliState = "Reload"
			unit.HeliStateChangedAt = os.clock()
		end
	elseif unit.HeliState == "Reload" then
		if os.clock() - unit.HeliStateChangedAt >= HELICOPTER_RELOAD_DURATION then
			unit.HeliState = "Approach"
			unit.HeliStateChangedAt = os.clock()
		end
	end
end

-- ===== Alle Einheiten einer Stadt spawnen (bei Level 4) =====
local function spawnMilitaryForCity(cityName)
	local existingUnits = activeUnits[cityName]
	if existingUnits then
		-- Zusätzliches Sicherheitsnetz: nur abbrechen, wenn dort auch WIRKLICH noch
		-- mindestens eine lebende Einheit steht -- eine leere, aber nicht-nil Tabelle
		-- (z.B. Restzustand nach einem Sprung-Reset) soll einen Neuaufbau nicht mehr
		-- blockieren können.
		local hasAnyUnit = false
		for _, units in pairs(existingUnits) do
			if #units > 0 then
				hasAnyUnit = true
				break
			end
		end
		if hasAnyUnit then
			return -- schon aktiv
		end
		activeUnits[cityName] = nil
	end
	local config = CityAlertConfig.GetCityConfig(cityName)
	local templateFolder = ServerStorage:FindFirstChild("MilitaryModels")
	if not templateFolder then
		warn("[MilitaryService] ServerStorage.MilitaryModels nicht gefunden -- Level 4 bleibt wirkungslos.")
		return
	end

	activeUnits[cityName] = { Tank = {}, RocketLauncher = {}, Helicopter = {} }

	local unitCounts = {
		Tank = config.MilitaryTankCount or 1,
		RocketLauncher = config.MilitaryRocketLauncherCount or 1,
		Helicopter = config.MilitaryHelicopterCount or 1,
	}

	local firstSpawnPosition = nil
	local totalSpawnedThisWave = 0
	for unitType, count in pairs(unitCounts) do
		for _ = 1, count do
			local spawnPart = pickRandomSpawnPoint(cityName, unitType)
			if not spawnPart then
				warn("[MilitaryService] Keine Spawn-Punkte für '" .. cityName .. "' / '" .. unitType .. "' gefunden (Workspace.MilitarySpawns." .. cityName .. "." .. unitType .. ") -- übersprungen.")
			else
				firstSpawnPosition = firstSpawnPosition or spawnPart.Position
				local unit = spawnUnit(cityName, unitType, templateFolder, spawnPart, config)
				if unit then
					table.insert(activeUnits[cityName][unitType], unit)
					totalSpawnedThisWave += 1
				end
			end
		end
	end
	totalMilitarySpawnedByCity[cityName] = totalSpawnedThisWave

	if firstSpawnPosition then
		playLevel4Alarm(firstSpawnPosition)
	end
	print("[MilitaryService] Level 4 für '" .. cityName .. "' aktiviert -- " .. #activeUnits[cityName].Tank .. " Panzer, " .. #activeUnits[cityName].RocketLauncher .. " Raketenwerfer, " .. #activeUnits[cityName].Helicopter .. " Helikopter.")
end

-- Spawnt EINE einzelne zusätzliche Einheit (unabhängig vom normalen Level-4-Spawn-Schub)
-- -- gedacht für die Prolog-Nachschub-Welle (siehe geplantes PrologueReinforcementService),
-- die kontinuierlich weitere Verstärkung nachschickt, um den Spieler von der Menge her zu
-- überwältigen. Reiht die neue Einheit in dieselbe activeUnits-Verwaltung ein wie der
-- normale Level-4-Spawn, wodurch sie automatisch von der bestehenden Heartbeat-Update-
-- Schleife (Bewegung/KI/Kampf/Schaden) mitversorgt wird -- keine duplizierte Logik nötig.
_G.SpawnReinforcementUnit = function(cityName, unitType)
	local templateFolder = ServerStorage:FindFirstChild("MilitaryModels")
	if not templateFolder then
		warn("[MilitaryService] ServerStorage.MilitaryModels nicht gefunden -- Nachschub-Einheit übersprungen.")
		return nil
	end

	local config = CityAlertConfig.GetCityConfig(cityName)
	local spawnPart = pickRandomSpawnPoint(cityName, unitType)
	if not spawnPart then
		warn("[MilitaryService] Keine Spawn-Punkte für '" .. cityName .. "' / '" .. unitType .. "' gefunden -- Nachschub-Einheit übersprungen.")
		return nil
	end

	activeUnits[cityName] = activeUnits[cityName] or { Tank = {}, RocketLauncher = {}, Helicopter = {} }
	local unit = spawnUnit(cityName, unitType, templateFolder, spawnPart, config)
	if unit then
		table.insert(activeUnits[cityName][unitType], unit)
		totalMilitarySpawnedByCity[cityName] = (totalMilitarySpawnedByCity[cityName] or 0) + 1
	end
	return unit
end

local function despawnMilitaryForCity(cityName)
	local unitsByType = activeUnits[cityName]
	if not unitsByType then
		return
	end
	for _, units in pairs(unitsByType) do
		for _, unit in ipairs(units) do
			if unit.Model then
				GroundVehicleSeparation.Unregister(unit.Model)
				unit.Model:Destroy()
			end
		end
	end
	activeUnits[cityName] = nil
end
_G.DespawnMilitaryForCity = despawnMilitaryForCity

-- ===== Update-Schleife: bewegt/greift alle aktiven Einheiten jeden Heartbeat an. =====
RunService.Heartbeat:Connect(function()
	for cityName, unitsByType in pairs(activeUnits) do
		local config = CityAlertConfig.GetCityConfig(cityName)
		for _, unit in ipairs(unitsByType.Tank) do
			local ok, err = pcall(updateTank, cityName, unit, config)
			if not ok then
				warn("[MilitaryService] Fehler bei Panzer-Update:", err)
			end
		end
		for _, unit in ipairs(unitsByType.RocketLauncher) do
			local ok, err = pcall(updateRocketLauncher, cityName, unit, config)
			if not ok then
				warn("[MilitaryService] Fehler bei Raketenwerfer-Update:", err)
			end
		end
		for _, unit in ipairs(unitsByType.Helicopter) do
			local ok, err = pcall(updateHelicopterUnit, cityName, unit, config)
			if not ok then
				warn("[MilitaryService] Fehler bei Helikopter-Update:", err)
			end
		end
	end
end)

-- ===== Level-Wechsel abonnieren -- wartet notfalls auf _G.CityAlertLevelChanged (gleiche
-- Absicherung wie bei FireEngineController.lua/AlertHelicopterService.lua, da Scripts
-- direkt unter ServerScriptService in unbestimmter Reihenfolge starten). =====
task.spawn(function()
	local attempts = 0
	while not _G.CityAlertLevelChanged and attempts < 100 do
		task.wait(0.1)
		attempts += 1
	end
	if not _G.CityAlertLevelChanged then
		warn("[MilitaryService] _G.CityAlertLevelChanged nie gefunden (10s Timeout) -- Level 4 bleibt wirkungslos. Läuft CityAlertService.lua?")
		return
	end

	_G.CityAlertLevelChanged.Event:Connect(function(cityName, newLevel, oldLevel)
		print("[Kaiju-Debug] MilitaryService: CityAlertLevelChanged empfangen -- Stadt:", cityName, "neu:", newLevel, "alt:", oldLevel)
		if newLevel == 4 and oldLevel == 3 then
			print("[Kaiju-Debug] MilitaryService: löse spawnMilitaryForCity aus für", cityName)
			spawnMilitaryForCity(cityName)
		elseif newLevel < 4 and oldLevel >= 4 then
			-- WICHTIG: reagiert jetzt auf JEDEN Abfall unter Level 4, nicht nur den
			-- exakten 4->3-Schritt -- ein Sprung-Reset (z.B. CITY BROKEN: 4->0 oder 5->0
			-- in einem Schritt statt schrittweise) hätte den alten, exakten Trigger sonst
			-- NIE ausgelöst. Die Folge: activeUnits[cityName] blieb als (leere, aber
			-- NICHT nil) Tabelle stehen und blockierte jeden künftigen Spawn-Versuch
			-- stillschweigend über den spawnMilitaryForCity()-Guard weiter unten --
			-- exakt das gemeldete "Militär erscheint ab dem 2./3. Mal nicht mehr".
			despawnMilitaryForCity(cityName)
		end
		-- Zähler-Reset, sobald die Stadt komplett zur Ruhe kommt -- sonst könnte ein
		-- Sprung-Reset (z.B. CITY BROKEN, Level 5 -> 0 in einem Schritt statt schrittweise)
		-- den alten Gesamt-Zähler vom vorigen Zyklus stehen lassen, was die CITY-BROKEN-
		-- Aufgabe fälschlich als "schon aktiviert gewesen" werten könnte.
		if newLevel == 0 then
			totalMilitarySpawnedByCity[cityName] = 0
		end
	end)
end)

print("[Kaiju] MilitaryService bereit -- Level 4 (Panzer, Raketenwerfer, Helikopter).")