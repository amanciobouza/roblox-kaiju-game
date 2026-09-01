-- VERSION: 2026-08-26 #3
-- FEATURE: despawnEnginesForCity global exponiert (_G.DespawnFireEnginesForCity)
-- ServerScript: FireEngineController
-- Ort in Studio: ServerScriptService
--
-- Reagiert auf CityAlertLevelChanged (Level 2 = "Fire Response"). Spawnt Feuerwehrautos
-- für die betroffene Stadt, lässt sie zur grössten/wichtigsten aktiven Feuerquelle fahren
-- und dort löschen (entzieht der Feuerquelle kontinuierlich remainingEnergy -- der
-- Spieler kann daraus keine Energie mehr absorbieren, sobald sie bei 0 ist).
--
-- Feuerwehrautos sind selbst zerstörbar (alle 5 Angriffstypen), geben eine kleine
-- Coin-Belohnung, KEINE grosse XP, und erzeugen deutlich mehr Alert als ein normales
-- Haus -- das Zerstören schützt die eigene Thermal Energy, beschleunigt aber den
-- nächsten Alert-Level. Keine menschlichen Feuerwehrleute -- die Fahrzeuge selbst sind
-- die Gameplay-Einheiten.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local PathfindingService = game:GetService("PathfindingService")

local CityAlertConfig = require(ReplicatedStorage:WaitForChild("CityAlertConfig"))
-- Refactoring: das Bodenfahrzeug-Abstandssystem lebt jetzt in einem eigenen Modul (vorher
-- als _G-Funktionen in MilitaryService.lua definiert, obwohl beide Systeme es nutzen).
local GroundVehicleSeparation = require(script.Parent:WaitForChild("GroundVehicleSeparation"))

local FIRE_ENGINE_TAG = "FireEngine"
local ShowDamageEvent = RemoteEventUtils.GetOrCreate("ShowDamageEvent")
-- Ziel-Löschdauer bei aktivem, ununterbrochenem Löschen -- bewusst deutlich kürzer als
-- selbst die kürzeste Respawn-/Feuer-Dauer (GROUP_SECTION_ENERGY_TIME = 12s in
-- HouseHandler.lua), damit die Feuerwehr ein Gebäude bei durchgehendem Einsatz IMMER vor
-- dem natürlichen Respawn fertig löschen kann, unabhängig von dessen Grösse.
local EXTINGUISH_TARGET_DURATION = 8
_G.FIRE_ENGINE_TAG = FIRE_ENGINE_TAG

-- Zentraler Debug-Schalter -- auf true setzen, um alle "[Kaiju-Debug]"/"[Jitter-Debug]"
-- Ausgaben wieder einzuschalten, ohne jede einzelne Print-Zeile suchen zu müssen.
local DEBUG_ENABLED = false
local function debugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

-- Verhindert wiederholtes Warnen für dieselbe Stadt (siehe findCitySpawnPoint-Aufrufer
-- weiter unten) -- eine defekte/fehlende Studio-Konfiguration soll das Output-Fenster
-- nicht bei jedem Alert-Level-Wechsel erneut zuspammen.
local warnedMissingSpawnByCity = {}

local SIREN_SOUND_ID = "rbxassetid://530137633"
local EXPLOSION_SOUND_ID = "rbxassetid://846518756"

-- [cityName] = true/false -- ob der Wasserturm DIESER Stadt noch intakt ist. Startet
-- bei true für Städte, die laut Config überhaupt einen Bonus haben könnten (Village).
-- Wird von _G.RemoveWaterTowerBonus() live aktualisiert, sobald der Turm fällt -- wirkt
-- sich SOFORT auf alle aktuell aktiven UND künftig gespawnten Fahrzeuge dieser Stadt aus.
local waterTowerIntactByCity = {}
for _, cityName in ipairs(CityAlertConfig.CityOrder) do
	waterTowerIntactByCity[cityName] = CityAlertConfig.GetCityConfig(cityName).WaterTowerEfficiencyBonus > 0
end

_G.RemoveWaterTowerBonus = function(waterTowerInstance)
	local cityName = _G.ResolveCityName and _G.ResolveCityName(waterTowerInstance)
	if cityName and waterTowerIntactByCity[cityName] ~= nil then
		waterTowerIntactByCity[cityName] = false
	end
end

_G.RestoreWaterTowerBonus = function(waterTowerInstance)
	local cityName = _G.ResolveCityName and _G.ResolveCityName(waterTowerInstance)
	if cityName and waterTowerIntactByCity[cityName] ~= nil then
		waterTowerIntactByCity[cityName] = true
	end
end

-- [cityName] = { engines = {Model, ...} } -- damit wir bei Level-Rückgang gezielt genau
-- die Fahrzeuge DIESER Stadt einziehen können, nicht versehentlich fremde.
local activeEnginesByCity = {}
for _, cityName in ipairs(CityAlertConfig.CityOrder) do
	activeEnginesByCity[cityName] = {}
end

-- [cityName] = Anzahl, die bei der letzten Alert-Level-2-Welle gespawnt wurde -- da
-- besiegte Fahrzeuge aus activeEnginesByCity entfernt werden (siehe unten), lässt sich
-- "besiegt/gesamt" nur mit dieser zusätzlichen Gesamtzahl berechnen.
local totalEnginesSpawnedByCity = {}

-- Fürs CITY-BROKEN-Task-Panel: "wie viele von wie vielen sind besiegt".
_G.GetFireEngineCounts = function(cityName)
	local total = totalEnginesSpawnedByCity[cityName] or 0
	local stillActive = activeEnginesByCity[cityName] and #activeEnginesByCity[cityName] or 0
	return { destroyed = math.max(total - stillActive, 0), total = total }
end

-- Fürs Eskalations-Gate in CityAlertService.lua: Level 1->2 (Emergency) soll erst
-- weitersteigen, sobald KEINE aktiven Feuerwehrautos dieser Stadt mehr existieren
-- (Response besiegt), auch wenn der Fortschritt schon über der nächsten Schwelle liegt.
_G.HasActiveFireEngines = function(cityName)
	local engines = activeEnginesByCity[cityName]
	return engines ~= nil and #engines > 0
end

-- Wo die Fahrzeuge herkommen: nutzt ein Modell aus ReplicatedStorage, falls eines mit
-- diesem Namen existiert (für ein von dir gestaltetes Feuerwehrauto-Modell). Existiert
-- keines, wird ein einfaches, funktionales Ersatz-Fahrzeug aus Blöcken gebaut -- damit
-- das System auch ohne fertiges Modell sofort spielbar ist.
local function buildFallbackFireEngine()
	local model = Instance.new("Model")
	model.Name = "FireEngine"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(8, 5, 16)
	body.Color = Color3.fromRGB(200, 30, 30)
	body.Material = Enum.Material.Metal
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model
	model.PrimaryPart = body

	local cab = Instance.new("Part")
	cab.Name = "Cab"
	cab.Size = Vector3.new(7.5, 4, 5)
	cab.Color = Color3.fromRGB(220, 220, 220)
	cab.Material = Enum.Material.Metal
	cab.Parent = model
	cab:PivotTo(body.CFrame * CFrame.new(0, 4.5, -5))
	local cabWeld = Instance.new("WeldConstraint")
	cabWeld.Part0 = body
	cabWeld.Part1 = cab
	cabWeld.Parent = body

	local ladder = Instance.new("Part")
	ladder.Name = "Ladder"
	ladder.Size = Vector3.new(1.5, 1.5, 10)
	ladder.Color = Color3.fromRGB(230, 200, 40)
	ladder.Material = Enum.Material.Metal
	ladder.Parent = model
	ladder:PivotTo(body.CFrame * CFrame.new(0, 3.5, 2))
	local ladderWeld = Instance.new("WeldConstraint")
	ladderWeld.Part0 = body
	ladderWeld.Part1 = ladder
	ladderWeld.Parent = body

	for _, offset in ipairs({ Vector3.new(-4.2, -2.5, -5.5), Vector3.new(4.2, -2.5, -5.5), Vector3.new(-4.2, -2.5, 5.5), Vector3.new(4.2, -2.5, 5.5) }) do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(2, 3, 3)
		wheel.Color = Color3.fromRGB(20, 20, 20)
		wheel.Material = Enum.Material.Plastic
		wheel.Parent = model
		wheel:PivotTo(body.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90)))
		local wheelWeld = Instance.new("WeldConstraint")
		wheelWeld.Part0 = body
		wheelWeld.Part1 = wheel
		wheelWeld.Parent = body
	end

	local light = Instance.new("PointLight")
	light.Name = "SirenLight"
	light.Color = Color3.fromRGB(255, 40, 30)
	light.Brightness = 3
	light.Range = 16
	light.Parent = cab

	return model
end

local function getFireEngineTemplate()
	local custom = ReplicatedStorage:FindFirstChild("FireEngine")
	local template
	if custom then
		template = custom:Clone()
	else
		template = buildFallbackFireEngine()
	end

	-- WICHTIG: PrimaryPart absichern -- ein eigenes, in Studio gebautes/importiertes
	-- Modell hat sehr häufig KEIN PrimaryPart gesetzt. Ohne PrimaryPart ist das Fahrzeug
	-- für die Fokus-Zielsuche (SpecialAttackHandler.lua, engine.PrimaryPart) komplett
	-- unsichtbar/nicht anvisierbar, obwohl alles andere (Spawnen, Fahren) trotzdem
	-- funktioniert.
	if not template.PrimaryPart then
		local fallbackPart = template:FindFirstChildWhichIsA("BasePart", true)
		if fallbackPart then
			template.PrimaryPart = fallbackPart
		end
	end

	return template
end


-- HP-Balken über dem Fahrzeug -- gleiches Muster wie bei Militär-Einheiten
-- (MilitaryService.lua, createUnitBillboard), damit Feuerwehrautos genauso erkennbar
-- angreifbar wirken.
local function createFireEngineHealthBar(engine)
	local anchorPart = engine.PrimaryPart or engine:FindFirstChildWhichIsA("BasePart")
	if not anchorPart then
		return nil
	end

	local size
	local ok, _, modelSize = pcall(function()
		return engine:GetBoundingBox()
	end)
	size = (ok and modelSize) or Vector3.new(8, 8, 8)
	local topOffsetY = size.Y / 2 + 3

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FireEngineHealthBar"
	billboard.Size = UDim2.new(0, 100, 0, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500
	billboard.Enabled = true -- dauerhaft sichtbar, wie bei Militär-Einheiten (aktiv bekämpfbares Ziel)
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
	hpLabel.Text = "🚒 Fire Engine"
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

local function updateFireEngineHealthBar(engine)
	local billboard = engine.PrimaryPart and engine.PrimaryPart:FindFirstChild("FireEngineHealthBar")
	if not billboard then
		return
	end
	local fill = billboard:FindFirstChild("Fill", true)
	if not fill then
		return
	end
	local health = engine:GetAttribute("Health") or 0
	local maxHealth = engine:GetAttribute("MaxHealth") or 1
	local ratio = math.clamp(health / math.max(maxHealth, 1), 0, 1)
	fill.Size = UDim2.new(ratio, 0, 1, 0)
end

-- [house] = engine -- welches Fahrzeug aktuell dieses Gebäude anfährt/löscht. Verhindert,
-- dass mehrere Feuerwehrautos unabhängig voneinander alle dasselbe (meist energiereichste)
-- Feuer wählen und andere brennende Gebäude ignorieren.
local claimedFireTargets = {}

local function findBestFireTargetInCity(cityName, requestingEngine)
	if not _G.ActiveFireSources or not _G.ResolveCityName then
		return nil
	end

	local bestHouse, best, bestEnergy = nil, nil, 0
	for house, source in pairs(_G.ActiveFireSources) do
		if source.remainingEnergy > 0 and house.Parent then
			local claimedBy = claimedFireTargets[house]
			-- Bereits von einem ANDEREN, noch aktiven Fahrzeug beansprucht -> überspringen.
			-- Ein Claim von einem zerstörten/entfernten Fahrzeug zählt nicht mehr.
			local isClaimedByOtherActiveEngine = claimedBy
				and claimedBy ~= requestingEngine
				and claimedBy.Parent
				and not claimedBy:GetAttribute("Destroyed")
			if not isClaimedByOtherActiveEngine and _G.ResolveCityName(house) == cityName and source.remainingEnergy > bestEnergy then
				bestHouse, best, bestEnergy = house, source, source.remainingEnergy
			end
		end
	end
	return best, bestHouse
end

-- ===== Firefighter Extinguishing Feedback: zeigt über dem Gebäude, wie weit der
-- Löschvorgang fortgeschritten ist. Fortschritt wird direkt aus totalEnergy/
-- remainingEnergy der bestehenden Feuerquelle berechnet (siehe
-- EnergyCollectionHandler.lua) -- kein separates Tracking nötig, bleibt automatisch
-- erhalten, wenn der Löschvorgang unterbrochen wird (Fahrzeug zerstört), da
-- remainingEnergy selbst unverändert stehen bleibt.
local extinguishBillboards = {} -- [house] = BillboardGui

local function getOrCreateExtinguishBillboard(house)
	if extinguishBillboards[house] and extinguishBillboards[house].Parent then
		return extinguishBillboards[house]
	end

	local anchorPart = house.PrimaryPart
	if not anchorPart then
		return nil
	end

	local size
	local ok, _, modelSize = pcall(function()
		return house:GetBoundingBox()
	end)
	size = (ok and modelSize) or Vector3.new(8, 8, 8)
	local topOffsetY = size.Y / 2 + 3

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ExtinguishProgressBar"
	billboard.Size = UDim2.new(0, 130, 0, 34)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 400
	billboard.Parent = anchorPart

	local label = Instance.new("TextLabel")
	label.Name = "StatusLabel"
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 200, 255)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Text = "EXTINGUISHING"
	label.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 12)
	track.Position = UDim2.new(0, 0, 0, 18)
	track.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
	track.Parent = billboard

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(70, 170, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	extinguishBillboards[house] = billboard
	return billboard
end

-- Aktualisiert die Anzeige mit dem aktuellen Fortschritt (0-1) -- wird bei jedem Tick
-- aufgerufen, während mindestens ein Fahrzeug aktiv löscht.
local function updateExtinguishBillboard(house, ratio)
	local billboard = getOrCreateExtinguishBillboard(house)
	if not billboard then
		return
	end
	local fill = billboard:FindFirstChild("Fill", true)
	if fill then
		fill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
	end
end

-- Erfolgs-Sequenz: Text wechselt kurz zu "EXTINGUISHED!", der volle Balken bleibt
-- sichtbar, dann verschwindet die ganze Anzeige.
local function playExtinguishSuccessSequence(house)
	local billboard = extinguishBillboards[house]
	if not billboard or not billboard.Parent then
		return
	end
	extinguishBillboards[house] = nil -- ab jetzt niemand mehr aktualisieren lassen

	local label = billboard:FindFirstChild("StatusLabel", true)
	local fill = billboard:FindFirstChild("Fill", true)
	if label then
		label.Text = "EXTINGUISHED!"
		label.TextColor3 = Color3.fromRGB(120, 255, 150)
	end
	if fill then
		fill.Size = UDim2.new(1, 0, 1, 0)
	end

	task.delay(1.3, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

-- Räumt eine evtl. noch hängende Anzeige sofort weg (z.B. falls das Haus respawnt/
-- verschwindet, bevor der Löschvorgang fertig war).
local function clearExtinguishBillboard(house)
	local billboard = extinguishBillboards[house]
	if billboard then
		extinguishBillboards[house] = nil
		if billboard.Parent then
			billboard:Destroy()
		end
	end
end

-- ===== Zerstörbarkeit =====
-- Wird von CombatHandler.lua / HouseHandler.lua (Sprung) / SpecialAttackHandler.lua
-- (Fokus/Fläche) genauso aufgerufen wie _G.DamageHouse -- gleiche Angriffe, gleiches
-- Prinzip, nur ein anderes Ziel.
local function damageFireEngine(engine, amount, attackerPlayer)
	if not engine or not engine.Parent or engine:GetAttribute("Destroyed") then
		return
	end
	local health = math.max((engine:GetAttribute("Health") or 0) - amount, 0)
	engine:SetAttribute("Health", health)
	updateFireEngineHealthBar(engine)

	if health <= 0 then
		engine:SetAttribute("Destroyed", true)
		GroundVehicleSeparation.Unregister(engine)

		-- Achievements: "Erste Feuerwehr besiegt".
		if attackerPlayer and _G.RecordStat then
		_G.RecordStat(attackerPlayer, "FireEnginesDestroyed")
	end

	if attackerPlayer and _G.OnFireEngineDestroyedForAchievements then
			_G.OnFireEngineDestroyedForAchievements(attackerPlayer)
		end

		-- Zufriedenstellender Zerstörungs-Effekt: kurzer Explosions-Flash + Sound, dann weg.
		local primaryPart = engine.PrimaryPart
		if primaryPart then
			local explosion = Instance.new("Explosion")
			explosion.Position = primaryPart.Position
			explosion.BlastRadius = 0 -- rein visuell/akustisch, kein zusätzlicher Flächenschaden an Häusern
			explosion.BlastPressure = 0
			explosion.Parent = Workspace

			local sound = Instance.new("Sound")
			sound.SoundId = EXPLOSION_SOUND_ID
			sound.Volume = 1
			sound.Parent = primaryPart
			if sound.SoundId ~= "" and sound.SoundId ~= "rbxassetid://0" then
				sound:Play()
			end
		end

		if attackerPlayer then
			-- Kleine Coin-Belohnung, bewusst KEINE grosse XP (laut Vorgabe) -- zählt aber
			-- zum Zerstörungs-Combo des Spielers.
			local leaderstats = attackerPlayer:FindFirstChild("leaderstats")
			if leaderstats and leaderstats:FindFirstChild("Coins") then
				local coinReward = math.max(math.floor((engine:GetAttribute("MaxHealth") or 0) * 0.05), 5)
				leaderstats.Coins.Value += coinReward
				if _G.RecordStat then
					_G.RecordStat(attackerPlayer, "CoinsCollected", coinReward)
				end
			end

			-- Zähler für Jaeger-Fraktions-Freischaltung (siehe FactionUnlockService.lua) --
			-- beweist, dass der Spieler Alert Level 2 tatsächlich erlebt/bekämpft hat.
			attackerPlayer:SetAttribute("FireEnginesDestroyed", (attackerPlayer:GetAttribute("FireEnginesDestroyed") or 0) + 1)

			-- Deutlich mehr Alert als ein normales Haus -- Zerstören schützt die eigene
			-- Thermal Energy, beschleunigt aber den nächsten Alert-Level.
			if _G.AddCityAlert then
				local cityName = engine:GetAttribute("CityName")
				local config = CityAlertConfig.GetCityConfig(cityName or "")
				_G.AddCityAlert(engine, config.FireEngineDestroyAlertValue)
			end
		end

		task.delay(0.15, function()
			engine:Destroy()
		end)

		-- Aus der Tracking-Liste entfernen (fehlte bisher) -- sonst würde
		-- _G.HasActiveFireEngines() dauerhaft "noch aktiv" melden, selbst nachdem alle
		-- Fahrzeuge zerstört sind, und das Eskalations-Gate in CityAlertService.lua nie
		-- freigeben.
		local cityName = engine:GetAttribute("CityName")
		local engines = cityName and activeEnginesByCity[cityName]
		if engines then
			for i = #engines, 1, -1 do
				if engines[i] == engine then
					table.remove(engines, i)
				end
			end
			-- Eskalation SOFORT prüfen, sobald die letzte Feuerwehr dieser Stadt fällt --
			-- statt bis zum nächsten Gebäude-Treffer zu warten.
			if #engines == 0 and _G.CheckCityAlertLevelThresholds then
				_G.CheckCityAlertLevelThresholds(cityName)
			end
		end
	end
end
_G.DamageFireEngine = damageFireEngine
-- Fürs Aufräumen einer evtl. noch hängenden Löschanzeige, falls das Haus respawnt/erneut
-- zerstört wird, während der Löschvorgang unterbrochen (nicht abgeschlossen) war (siehe
-- HouseHandler.lua, extinguishHouseFire).
_G.ClearExtinguishBillboard = clearExtinguishBillboard
-- Zeigt die Löschanzeige sofort bei 0% an, sobald ein Gebäude zerstört wird/zu brennen
-- beginnt -- nicht erst, wenn ein Fahrzeug tatsächlich mit dem Löschen beginnt. Wird von
-- HouseHandler.lua direkt beim Entzünden des Feuers aufgerufen.
_G.ShowExtinguishBillboard = function(house)
	updateExtinguishBillboard(house, 0)
end

-- Von den Angriffs-Scripts genutzt, um alle Feuerwehrautos in Reichweite einer Position
-- zu finden -- exakt analog zu getHousesInRange in CombatHandler.lua.
_G.GetFireEnginesInRange = function(position, radius)
	local result = {}
	for _, engine in ipairs(CollectionService:GetTagged(FIRE_ENGINE_TAG)) do
		if not engine:GetAttribute("Destroyed") and engine.PrimaryPart then
			if (engine.PrimaryPart.Position - position).Magnitude <= radius then
				table.insert(result, engine)
			end
		end
	end
	return result
end

-- ===== Sprung-Schaden (Touch-basiert, analog zu onHouseTouched in HouseHandler.lua) =====
local Players = game:GetService("Players")
local JUMP_FALL_VELOCITY_THRESHOLD = -5
local TRAMPLE_COOLDOWN = 0.5
local lastTrampleTime = {} -- [engine] = { [player] = os.clock() }
local recentFallVelocity = {} -- [player] = number, wird von einem einfachen Heartbeat-Tracker unten gepflegt

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			recentFallVelocity[player] = rootPart.AssemblyLinearVelocity.Y
		end
	end
end)

local function handleFireEngineTouch(engine, hit)
	if engine:GetAttribute("Destroyed") then
		return
	end
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then
		return
	end

	lastTrampleTime[engine] = lastTrampleTime[engine] or {}
	local now = os.clock()
	local last = lastTrampleTime[engine][player]
	if last and now - last < TRAMPLE_COOLDOWN then
		return
	end
	lastTrampleTime[engine][player] = now

	local baseDamage = character:GetAttribute("Damage") or 10
	local berserkerMultiplier = (_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0
	baseDamage = baseDamage * berserkerMultiplier

	local state = humanoid:GetState()
	local recentVelocityY = recentFallVelocity[player] or 0
	local isJumping = state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or recentVelocityY < JUMP_FALL_VELOCITY_THRESHOLD

	local damage = baseDamage
	if isJumping then
		-- Gleiche Bein-Verhältnis-Formel wie bei Häusern: 1x bis 2x je nach Bein-Training.
		local legPower = player:FindFirstChild("LegPower")
		local legValue = legPower and legPower.Value or 0
		local legCap = math.max(player:GetAttribute("LegStatCap") or 1, 1)
		local legRatio = math.clamp(legValue / legCap, 0, 1)
		damage = baseDamage * (1 + legRatio)

		if _G.AddJumpHeat then
			_G.AddJumpHeat(player)
		end

		-- Lebensstatistik: gezählt wird der SPRUNGANGRIFF (ein Treffer), nicht jeder Sprung.
		if _G.RecordStat then
			_G.RecordStat(player, "Attacks.Jump")
		end
	end

	damageFireEngine(engine, damage, player)
end

-- WICHTIG: Touched wird auf ALLEN Fahrzeugteilen verbunden, nicht nur auf PrimaryPart --
-- ein Fahrzeug besteht aus mehreren Teilen (Kabine, Räder, etc.), landet der Spieler auf
-- einem ANDEREN Teil als dem PrimaryPart, wurde der Treffer vorher gar nicht erkannt
-- (v.a. bei Sprungangriffen spürbar, da man selten exakt das eine PrimaryPart trifft).
local function connectFireEngineTouch(engine)
	for _, part in ipairs(engine:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Touched:Connect(function(hit)
				handleFireEngineTouch(engine, hit)
			end)
		end
	end
end

-- ===== Zielsuche =====
-- ===== Geländehöhe + -neigung per Raycast ermitteln (für Fahrt + realistische Hangneigung) =====
local GROUND_CLEARANCE = 3 -- Studs Abstand zwischen Fahrzeug-Unterseite und Boden (von 2 auf 3 erhöht als Puffer gegen kleine lokale Boden-Abweichungen)
local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude

-- WICHTIG: schliesst jetzt auch Gebäude (KaijuHouse-Tag) vom Raycast aus, nicht nur
-- Feuerwehrfahrzeuge -- in Gebäudenähe konnte der Raycast sonst manchmal das Dach statt
-- den tatsächlichen Boden treffen, wodurch die berechnete Höhe zwischen "Boden" und
-- "Dach" hin- und hersprang -- das erklärt das Ruckeln/Steckenbleiben spezifisch in
-- Gebäudenähe (auf freier Strecke lief die Fahrt ja bereits sauber).
local function getGroundExcludeInstances()
	local excluded = CollectionService:GetTagged(FIRE_ENGINE_TAG)
	local houseTag = _G.HOUSE_TAG or "KaijuHouse"
	for _, house in ipairs(CollectionService:GetTagged(houseTag)) do
		table.insert(excluded, house)
	end
	return excluded
end
groundRayParams.FilterDescendantsInstances = getGroundExcludeInstances()

-- Gibt Höhe UND Oberflächen-Normale zurück (Normale = "wohin zeigt der Boden", z.B. bei
-- einem 30°-Hang entsprechend gekippt) -- damit kann das Fahrzeug seine Neigung an den
-- tatsächlichen Hang anpassen, statt immer horizontal zu bleiben.
local function getGroundInfo(position, fallbackY)
	groundRayParams.FilterDescendantsInstances = getGroundExcludeInstances()

	local origin = Vector3.new(position.X, position.Y + 50, position.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -300, 0), groundRayParams)
	if result then
		return result.Position.Y, result.Normal, result
	end
	return fallbackY, Vector3.new(0, 1, 0), nil -- kein Treffer -- alte Höhe, keine Neigung
end

-- ===== Pathfinding: realistischer Weg über Gelände, meidet Wasser komplett, weicht
-- soliden Hindernissen (Häuser, Bäume -- alles mit CanCollide=true) automatisch aus. =====
-- WICHTIG: Setzt voraus, dass Bäume/Hindernisse in deiner Welt CanCollide=true haben --
-- nur dann erkennt Roblox' Pathfinding sie automatisch als zu umgehende Hindernisse.
-- Wasser wird über den Terrain-Material-Kosten "Water = unendlich teuer" gemieden, falls
-- es sich um Roblox-Terrain-Wasser handelt. Falls dein Wasser stattdessen ein einzelnes
-- Part ist (kein Terrain), muss dieses Part CanCollide=true haben, damit es ebenfalls
-- als Hindernis erkannt wird.
local function computePathWaypoints(startPosition, targetPosition)
	local path = PathfindingService:CreatePath({
		AgentRadius = 4.5,
		AgentHeight = 9,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 6,
		Costs = {
			Water = math.huge, -- Terrain-Wasser komplett meiden
			Grass = 1,
			Ground = 1,
			Sand = 1.2,
			Mud = 2,
		},
	})

	local ok = pcall(function()
		path:ComputeAsync(startPosition, targetPosition)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	end
	return nil
end



-- ===== Ein einzelnes Feuerwehrauto: fährt zum Ziel, löscht, sucht neues Ziel, oder
-- wartet, falls gerade kein Feuer aktiv ist. =====
local function runFireEngine(engine, cityName, config)
	local body = engine.PrimaryPart
	if not body then
		return
	end

	-- Falls ein eigenes Modell mit "RoofWaterCannon" vorhanden ist, übernimmt dessen
	-- eigenes Licht-/Wasserstrahl-Script (im Modell selbst) die komplette Visualisierung
	-- -- wir müssen dann nur noch die Attribute setzen (WaterSprayEnabled) und das
	-- Fahrzeug zum Ziel drehen, da das Script selbst nicht zielt. Ohne so ein Modell
	-- (Ersatz-Fahrzeug aus Blöcken) nutzen wir stattdessen einen einfachen, selbst
	-- gebauten Wasserstrahl-Beam als Fallback-Visualisierung.
	local hasCustomWaterCannon = engine:FindFirstChild("RoofWaterCannon", true) ~= nil
	debugPrint("[Kaiju-Debug]", engine.Name, "hasCustomWaterCannon:", hasCustomWaterCannon, "(false = nutzt Fallback-Beam)")

	local waterBeam, targetAnchor
	if not hasCustomWaterCannon then
		-- Wasserstrahl-Beam wird EINMAL pro Fahrzeug aufgebaut (nicht pro Löschvorgang) --
		-- die Ziel-Instanz wird über eine lokale Variable (Closure) referenziert, NICHT über
		-- ein Attribut, da SetAttribute keine Instanzen als Wert akzeptiert.
		--
		-- Hoher Bogen: Beam-Krümmung folgt der Blickrichtung (Z-Achse) der Attachments --
		-- beide zeigen hier nach OBEN, wodurch der Strahl erst nach oben "abschiesst" und
		-- dann von oben ins Ziel fällt, statt einer geraden/nur leicht gekrümmten Linie.
		local sourceAttachment = Instance.new("Attachment")
		sourceAttachment.Name = "WaterSource"
		sourceAttachment.CFrame = CFrame.new(0, 3, 6) * CFrame.Angles(-math.rad(90), 0, 0)
		sourceAttachment.Parent = body

		targetAnchor = Instance.new("Part")
		targetAnchor.Name = "WaterTargetAnchor"
		targetAnchor.Anchored = true
		targetAnchor.CanCollide = false
		targetAnchor.CanQuery = false
		targetAnchor.Transparency = 1
		targetAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
		targetAnchor.Parent = Workspace

		local targetAttachment = Instance.new("Attachment")
		targetAttachment.CFrame = CFrame.Angles(math.rad(90), 0, 0)
		targetAttachment.Parent = targetAnchor

		waterBeam = Instance.new("Beam")
		waterBeam.Name = "WaterBeam"
		waterBeam.Attachment0 = sourceAttachment
		waterBeam.Attachment1 = targetAttachment
		waterBeam.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255))
		waterBeam.Width0 = 2.5
		waterBeam.Width1 = 1.2
		waterBeam.Transparency = NumberSequence.new(0)
		waterBeam.LightEmission = 0.3
		waterBeam.Segments = 16
		-- Grosse Curve-Werte -- zusammen mit den nach oben zeigenden Attachments ergibt
		-- das einen echten hohen Bogen (schiesst hoch, fällt von oben ins Ziel), statt
		-- nur einer leichten Krümmung.
		waterBeam.CurveSize0 = 16
		waterBeam.CurveSize1 = 10
		waterBeam.FaceCamera = true
		waterBeam.Enabled = false
		waterBeam.Parent = body

		-- WICHTIG: targetAnchor bleibt eigenständig im Workspace, NICHT als Kind des
		-- Fahrzeugs -- sonst würde engine:PivotTo() (zum Fahren) den Anker versehentlich
		-- mitbewegen, obwohl er fest an der Feuer-Position bleiben soll.
		engine.Destroying:Connect(function()
			if targetAnchor.Parent then
				targetAnchor:Destroy()
			end
		end)
	end

	-- Geglättete Boden-Normale -- persistiert über die gesamte Lebenszeit des Fahrzeugs
	-- (nicht pro Zielsuche neu), damit die Neigung sich sanft anpasst statt bei jedem
	-- Frame hart auf den frisch gemessenen Wert zu springen (kleine Unebenheiten im
	-- Gras/Terrain könnten sonst zu ruckartigen, "deformiert" wirkenden Drehungen führen).
	local smoothedGroundY = nil
	local lastJitterDebugAt = 0 -- für die temporäre Diagnose-Ausgabe weiter unten
	-- Geglätteter Nick-Winkel (Kippen NUR in Fahrtrichtung, kein seitliches Rollen) --
	-- vorsichtig und stark gedämpft wieder eingeführt, nachdem die volle 3D-Boden-
	-- Ausrichtung (Normale + right/up/forward-Matrix) mehrfach zu Ruckeln/Rutschen führte.
	local smoothedPitch = 0

	-- Bewegung erfolgt jetzt rein horizontal + Höhenanpassung (kein Kippen an Hängen mehr,
	-- siehe weiter unten) -- PivotMath/VehiclePivotMath wird dafür nicht mehr gebraucht.
	-- Falls das Fahrzeug einen PivotVehicle-Event hat, wird darüber gefeuert, sonst
	-- direkt per engine:PivotTo().
	local pivotVehicleEvent = engine:FindFirstChild("PivotVehicle")

	task.spawn(function()
		local claimedHouse = nil -- welches Gebäude DIESES Fahrzeug aktuell beansprucht
		while engine.Parent and not engine:GetAttribute("Destroyed") do
			-- Vorheriges Ziel freigeben, bevor neu gesucht wird -- sonst würde dieses
			-- Fahrzeug sein eigenes altes Ziel dauerhaft blockieren, selbst nachdem es
			-- längst weitergezogen ist.
			if claimedHouse then
				claimedFireTargets[claimedHouse] = nil
				claimedHouse = nil
			end

			local target, targetHouse = findBestFireTargetInCity(cityName, engine)
			debugPrint("[Kaiju-Debug]", engine.Name, "sucht Ziel in", cityName, "-> gefunden:", target ~= nil)

			if not target then
				if waterBeam then
					waterBeam.Enabled = false
				end
				engine:SetAttribute("WaterSprayEnabled", false)
				task.wait(1) -- kein aktives Feuer gerade -- kurz warten und erneut prüfen
			else
				claimedFireTargets[targetHouse] = engine
				claimedHouse = targetHouse

				-- Halte-Position: ein Stück VOR dem Haus (in Richtung des Fahrzeugs), nicht
				-- im Haus selbst -- Pathfinding zielt auf diesen Punkt, nicht auf das
				-- Feuer direkt (das wäre meist unerreichbar/im Hindernis).
				local towardEngine = (body.Position - target.position)
				local horizontalToEngine = Vector3.new(towardEngine.X, 0, towardEngine.Z)
				if horizontalToEngine.Magnitude < 0.1 then
					horizontalToEngine = Vector3.new(1, 0, 0)
				end
				local stopPosition = target.position + horizontalToEngine.Unit * config.FirefightingRange

				local waypoints = computePathWaypoints(body.Position, stopPosition)
				debugPrint("[Kaiju-Debug]", engine.Name, "Pathfinding-Ergebnis:", waypoints and (#waypoints .. " Wegpunkte") or "fehlgeschlagen, nutze direkte Linie")

				-- Prüft, ob "target" noch die TATSÄCHLICH aktive Feuerquelle dieses Hauses
				-- ist -- falls das Haus zwischenzeitlich respawnt ist (z.B. weil das
				-- natürliche Ausgehen des Feuers schneller war als das Fahrzeug), wurde
				-- der Eintrag aus _G.ActiveFireSources entfernt, auch wenn "target" als
				-- Lua-Tabelle selbst noch existiert und remainingEnergy > 0 zeigen könnte.
				-- Ohne diese Prüfung würde das Fahrzeug an einer "Geister-Feuerquelle"
				-- hängen bleiben, statt sich sofort ein neues Ziel zu suchen.
				local function isTargetStillActive()
					return _G.ActiveFireSources and _G.ActiveFireSources[targetHouse] == target
				end

				local function driveTowards(destination)
					-- Stecken-Erkennung: falls sich das Fahrzeug über einen Zeitraum kaum
					-- bewegt hat (z.B. weil der exakte Stopp-Punkt durch ein Gebäude
					-- blockiert/unzugänglich ist), gilt es als "angekommen" statt endlos mit
					-- minimalen Schritten weiterzuversuchen -- das erzeugte das leichte
					-- Zittern, wenn die letzte kleine Distanz nie ganz geschlossen werden
					-- konnte.
					local stuckCheckPosition = body.Position
					local stuckCheckStartedAt = os.clock()
					local STUCK_CHECK_INTERVAL = 1.5
					local STUCK_MOVEMENT_THRESHOLD = 1.5 -- Studs -- weniger Bewegung als das in diesem Zeitraum gilt als "steckt fest"

					while engine.Parent and not engine:GetAttribute("Destroyed") and target.remainingEnergy > 0 and isTargetStillActive() do
						local toDestination = destination - body.Position
						local horizontalDistance = Vector3.new(toDestination.X, 0, toDestination.Z).Magnitude
						if horizontalDistance <= 2 then
							return true
						end

						-- Stecken-Prüfung: alle STUCK_CHECK_INTERVAL Sekunden nachschauen,
						-- ob sich seit der letzten Prüfung überhaupt nennenswert etwas bewegt
						-- hat.
						if os.clock() - stuckCheckStartedAt >= STUCK_CHECK_INTERVAL then
							local movedDistance = (body.Position - stuckCheckPosition).Magnitude
							if movedDistance < STUCK_MOVEMENT_THRESHOLD then
								debugPrint("[Kaiju-Debug]", engine.Name, "steckt fest (kaum Bewegung in", STUCK_CHECK_INTERVAL, "s) -- gilt als angekommen, Rest-Distanz:", horizontalDistance)
								return true
							end
							stuckCheckPosition = body.Position
							stuckCheckStartedAt = os.clock()
						end

						local direction = Vector3.new(toDestination.X, 0, toDestination.Z).Unit
						local step = direction * config.FireEngineSpeed * RunService.Heartbeat:Wait()
						if step.Magnitude > horizontalDistance then
							step = Vector3.new(toDestination.X, 0, toDestination.Z)
						end

						local newPosition = body.Position + step

						-- Mindestabstand zu anderen Bodenfahrzeugen (auch aus dem
						-- Militär-System) einhalten, bevor die Boden-Höhe/Neigung berechnet wird.
						newPosition = GroundVehicleSeparation.ApplySeparation(engine, "FireEngine", newPosition)
						GroundVehicleSeparation.RegisterPosition(engine, "FireEngine", newPosition)

						-- WICHTIG: zurück auf EINE einzelne Boden-Messung an der
						-- Fahrzeug-MITTE (body.Position, nicht die vorausschauende
						-- Schritt-Position) -- die Zwei-Punkt-Mittelung (vorne+hinten) hat
						-- ein neues Problem eingeführt (Heck versinkt bei ungleichem
						-- Gelände zwischen den beiden Messpunkten). Einfacher, aber
						-- vorhersehbarer: eine Messung an der Mitte, plus etwas mehr
						-- GROUND_CLEARANCE als Puffer gegen kleine lokale Abweichungen.
						local groundY, groundNormal, groundHit = getGroundInfo(body.Position, body.Position.Y)

						-- Ausreisser-Erkennung: eine Messung, die plötzlich stark vom
						-- bisherigen Wert abweicht (z.B. Treffer auf eine Baumkrone/einen
						-- Stamm statt echten Boden -- Bäume haben keinen Tag zum gezielten
						-- Ausschliessen wie Gebäude), wird komplett verworfen, statt sie
						-- überhaupt in die Glättung einfliessen zu lassen.
						local OUTLIER_THRESHOLD = 6 -- Studs -- grössere Sprünge gelten als unplausibel
						local isOutlier = smoothedGroundY ~= nil and math.abs(groundY - smoothedGroundY) > OUTLIER_THRESHOLD
						if isOutlier then
							groundY = smoothedGroundY -- kompletter Sprung wird ignoriert, alter Wert bleibt bestehen
						end

						-- Höhen-Glättung: nähert sich dem neu gemessenen Wert nur schrittweise
						-- an, statt bei jedem Frame hart zu springen -- auf steilen Hängen
						-- reagiert die Rohmessung empfindlicher auf kleine Positions-
						-- Unterschiede, was ohne Glättung ruckelig wirkt.
						if smoothedGroundY == nil then
							smoothedGroundY = groundY
						else
							smoothedGroundY = smoothedGroundY + (groundY - smoothedGroundY) * 0.12
						end
						newPosition = Vector3.new(newPosition.X, smoothedGroundY + GROUND_CLEARANCE, newPosition.Z)

						-- Temporäre Diagnose -- gedrosselt (alle ~0.3s).
						if os.clock() - lastJitterDebugAt >= 0.3 then
							lastJitterDebugAt = os.clock()
							debugPrint(string.format(
								"[Jitter-Debug] rawY=%.2f smoothY=%.2f bodyY=%.2f",
								groundY, smoothedGroundY, body.Position.Y
								))
						end

						-- Nick-Winkel (Kippen NUR in Fahrtrichtung, kein seitliches Rollen) --
						-- berechnet aus der Komponente der Boden-Normale ENTLANG der
						-- Fahrtrichtung. Stark begrenzt + gedämpft, um die früheren Probleme
						-- (Ruckeln/Rutschen bei voller 3D-Ausrichtung) zu vermeiden.
						local MAX_PITCH_ANGLE = math.rad(18) -- nie mehr als 18° Kippung, egal wie steil lokal gemessen
						local rawPitch = 0
						if groundNormal.Y > 0.3 then -- Sicherheitsprüfung wie vorher: sehr steile/senkrechte Treffer ignorieren
							local flatDirection = Vector3.new(direction.X, 0, direction.Z)
							if flatDirection.Magnitude > 0.01 then
								rawPitch = math.asin(math.clamp(-groundNormal:Dot(flatDirection.Unit), -1, 1))
								rawPitch = math.clamp(rawPitch, -MAX_PITCH_ANGLE, MAX_PITCH_ANGLE)
							end
						end
						-- Sehr langsame Annäherung (5% pro Frame) -- die Kippung soll sich
						-- kaum merklich anpassen, nicht abrupt springen.
						smoothedPitch = smoothedPitch + (rawPitch - smoothedPitch) * 0.05

						-- WICHTIG: Fahrzeug bewegt sich horizontal + passt die Höhe ans
						-- Gelände an, PLUS eine sanfte, begrenzte Nick-Kippung in
						-- Fahrtrichtung -- bewusst OHNE seitliches Rollen (das war beim
						-- letzten Versuch der komplexeste/fehleranfälligste Teil).
						local levelCFrame = CFrame.lookAt(newPosition, newPosition + Vector3.new(direction.X, 0, direction.Z))
						local tiltedCFrame = levelCFrame * CFrame.Angles(smoothedPitch, 0, 0)
						if pivotVehicleEvent then
							pivotVehicleEvent:Fire(tiltedCFrame)
						else
							engine:PivotTo(tiltedCFrame)
						end
					end
					return false
				end

				local reachedStop = false
				if waypoints then
					for _, waypoint in ipairs(waypoints) do
						if not engine.Parent or engine:GetAttribute("Destroyed") or target.remainingEnergy <= 0 then
							break
						end
						reachedStop = driveTowards(waypoint.Position)
					end
				else
					-- Kein Pfad gefunden (z.B. Ziel komplett unzugänglich) -- direkte Linie
					-- als Sicherheitsnetz, damit das Fahrzeug nicht einfach stehen bleibt.
					reachedStop = driveTowards(stopPosition)
				end

				debugPrint("[Kaiju-Debug]", engine.Name, "hat Fahr-Schleife verlassen, verbleibende Energie am Ziel:", target.remainingEnergy)
				if not engine.Parent or engine:GetAttribute("Destroyed") then
					break
				end

				-- Löschen: solange in Reichweite, Ziel noch existiert und noch Energie hat.
				-- Fahrzeug zum Ziel ausrichten (das Licht-/Spray-Script selbst zielt nicht),
				-- damit die am Modell fest montierte Kanone ungefähr in Richtung Feuer zeigt.
				local faceTarget = CFrame.lookAt(body.Position, Vector3.new(target.position.X, body.Position.Y, target.position.Z))
				engine:PivotTo(faceTarget)

				-- HINWEIS: Bewusst KEINE direkte CFrame-Manipulation der Düse mehr --
				-- das hat bei verschweissten Modell-Teilen andere Teile an falsche
				-- Positionen springen lassen (Weld-Beziehungen brechen, wenn man ein
				-- verschweisstes Teil direkt umsetzt). Die Ausrichtung des ganzen
				-- Fahrzeugs zum Ziel (oben, faceTarget) reicht als Annäherung -- für
				-- einen echten Bogen bei deinem eigenen Wassersystem müsste das in
				-- deinem eigenen Licht-/Spray-Script gelöst werden (z.B. über die
				-- Emitter-Eigenschaften selbst, nicht über die Teil-Position).

				if targetAnchor then
					targetAnchor.CFrame = CFrame.new(target.position)
				end
				if waterBeam then
					waterBeam.Enabled = true
				end
				engine:SetAttribute("WaterSprayEnabled", true)
				debugPrint("[Kaiju-Debug]", engine.Name, "beginnt zu löschen, Distanz zum Ziel:", (target.position - body.Position).Magnitude, "remainingEnergy:", target.remainingEnergy)

				while engine.Parent and not engine:GetAttribute("Destroyed") and target.remainingEnergy > 0 and isTargetStillActive() do
					-- WICHTIG: dynamische Rate statt fester config.FirefightingRate --
					-- die feste Rate reichte bei grossen Gebäuden bei weitem nicht aus, um
					-- vor dem natürlichen Respawn (RESPAWN_TIME) fertig zu löschen (z.B.
					-- Megacity: rechnerisch ~2000s statt der gewünschten <30s). Die Rate wird
					-- daher aus der TATSÄCHLICHEN Energiemenge DIESES Ziels berechnet, sodass
					-- jedes Gebäude -- unabhängig von seiner Grösse -- innerhalb von
					-- EXTINGUISH_TARGET_DURATION komplett löschbar ist, deutlich schneller als
					-- selbst die kürzeste Respawn-Zeit (GROUP_SECTION_ENERGY_TIME = 12s).
					local rate = config.FirefightingRate
					if target.totalEnergy and target.totalEnergy > 0 then
						rate = target.totalEnergy / EXTINGUISH_TARGET_DURATION
					end
					if waterTowerIntactByCity[cityName] then
						rate = rate * (1 + config.WaterTowerEfficiencyBonus)
					end
					target.remainingEnergy = math.max(target.remainingEnergy - rate * RunService.Heartbeat:Wait(), 0)

					-- Firefighter Extinguishing Feedback: Fortschritt direkt aus
					-- totalEnergy/remainingEnergy berechnen (1 = frisch entzündet, 0 = fertig
					-- gelöscht) -- daher 1 minus das Verhältnis für die Fortschrittsanzeige.
					if targetHouse and target.totalEnergy and target.totalEnergy > 0 then
						updateExtinguishBillboard(targetHouse, 1 - (target.remainingEnergy / target.totalEnergy))
					end
				end
				debugPrint("[Kaiju-Debug]", engine.Name, "Löschvorgang beendet, remainingEnergy:", target.remainingEnergy, "nochAktiv:", isTargetStillActive(), "engine.Parent:", engine.Parent ~= nil, "Destroyed:", engine:GetAttribute("Destroyed"))

				-- Feuer wirklich VOLLSTÄNDIG gelöscht (nicht nur unterbrochen, weil das
				-- Fahrzeug zerstört wurde oder wegfährt) -- Feuer+Rauch sofort entfernen,
				-- damit klar sichtbar ist, dass gelöscht wurde, und damit keine weitere
				-- Energie mehr daraus absorbiert werden kann. NUR wenn das Fahrzeug die
				-- Quelle selbst auf 0 gebracht hat (isTargetStillActive) -- falls das Haus
				-- zwischenzeitlich von selbst respawnt ist, wurde das bereits anderweitig
				-- erledigt, kein zweiter Aufruf nötig.
				if target.remainingEnergy <= 0 and isTargetStillActive() and targetHouse and _G.ExtinguishHouseFire then
					playExtinguishSuccessSequence(targetHouse)
					_G.ExtinguishHouseFire(targetHouse)
					debugPrint("[Kaiju-Debug]", engine.Name, "hat Feuer bei", targetHouse:GetFullName(), "vollständig gelöscht")
				end

				if waterBeam then
					waterBeam.Enabled = false
				end
				engine:SetAttribute("WaterSprayEnabled", false)
			end
		end

		-- Fahrzeug ist zerstört/entfernt worden -- letztes beanspruchtes Ziel freigeben,
		-- sonst bliebe es fälschlich für immer "besetzt", obwohl niemand mehr dran arbeitet.
		if claimedHouse then
			claimedFireTargets[claimedHouse] = nil
		end
	end)
end

-- ===== Sirenen beim Start von Alert Level 2 =====
local function playDistantSirens(position)
	local sound = Instance.new("Sound")
	sound.Name = "DistantSiren"
	sound.SoundId = SIREN_SOUND_ID
	sound.Volume = 0.6
	sound.RollOffMaxDistance = 400
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
	task.delay(12, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

-- ===== Auf Alert-Level-Wechsel reagieren =====
local function findCitySpawnPoint(cityName)
	-- Sucht DIREKT nach "FireEngineSpawn"-Parts (davon gibt's normalerweise nur wenige
	-- im ganzen Workspace) und prüft für jeden gefundenen dessen Stadt-Zugehörigkeit --
	-- robuster als andersherum "erstes Objekt mit passendem CityName" zu suchen, da
	-- mittlerweile auch JEDES Haus ein eigenes CityName-Attribut trägt (siehe
	-- HouseHandler.lua) und ein Haus zufällig vor dem eigentlichen Stadt-Container
	-- gefunden werden könnte, je nach Workspace-Reihenfolge (die sich durchs Zerstören/
	-- Respawnen von Häusern auch noch laufend ändert).
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant.Name == "FireEngineSpawn" and descendant:IsA("BasePart") then
			if _G.ResolveCityName and _G.ResolveCityName(descendant) == cityName then
				return descendant.Position
			end
		end
	end

	-- Fallback: kein FireEngineSpawn-Part gefunden -- stattdessen den Stadt-Container
	-- selbst suchen (Pivot-Position als grobe Näherung).
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:GetAttribute("CityName") == cityName and (descendant:IsA("Model") or descendant:IsA("Folder")) then
			if descendant:IsA("Model") then
				local ok, cframe = pcall(function()
					return descendant:GetPivot()
				end)
				if ok then
					return cframe.Position
				end
			end
		end
	end
	return nil
end

local function spawnEnginesForCity(cityName)
	debugPrint("[Kaiju-Debug] spawnEnginesForCity aufgerufen für:", cityName)

	-- Sicherheitsnetz: falls von einem früheren, verpassten Despawn (Sprung-Reset,
	-- siehe Listener weiter unten) noch Fahrzeuge in der Tabelle/Welt hängen, erst
	-- aufräumen -- sonst würden sich Fahrzeuge bei jedem erneuten Hochfahren auf
	-- Level 2 verdoppeln, statt sauber neu zu starten.
	if activeEnginesByCity[cityName] and #activeEnginesByCity[cityName] > 0 then
		for _, engine in ipairs(activeEnginesByCity[cityName]) do
			if engine.Parent then
				engine:Destroy()
			end
		end
		activeEnginesByCity[cityName] = {}
	end

	local config = CityAlertConfig.GetCityConfig(cityName)
	totalEnginesSpawnedByCity[cityName] = config.FireEngineCount or 0

	-- Falls die Welt (Streaming) noch nicht komplett geladen ist, existiert der
	-- FireEngineSpawn-Part evtl. noch nicht im Moment des Alert-Level-Wechsels --
	-- bis zu 10s lang mehrfach erneut versuchen, statt sofort aufzugeben.
	local spawnPosition
	local attempts = 0
	repeat
		spawnPosition = findCitySpawnPoint(cityName)
		if not spawnPosition then
			attempts += 1
			task.wait(0.5)
		end
	until spawnPosition or attempts >= 20

	if not spawnPosition then
		-- Nur EINMAL pro Stadt warnen -- verhindert wiederholtes Zuspammen des
		-- Output-Fensters, falls dieselbe Stadt bei jedem Alert-Level-Wechsel erneut ohne
		-- Spawn-Punkt dasteht (z.B. weil das Objekt in Studio fehlt).
		if not warnedMissingSpawnByCity[cityName] then
			warnedMissingSpawnByCity[cityName] = true
			warn("[FireEngineController] Kein Spawn-Punkt für Stadt '" .. cityName .. "' gefunden (auch nach 10s Warten) -- fehlt ein Objekt mit CityName-Attribut oder ein 'FireEngineSpawn'-Part darunter?")
		end
		return
	end
	debugPrint("[Kaiju-Debug] Spawn-Position gefunden:", spawnPosition, "FireEngineCount:", config.FireEngineCount, "(nach", attempts, "Versuchen)")

	playDistantSirens(spawnPosition)

	-- ===== Firefighter Extinguishing Feedback: zeigt über dem Gebäude, wie weit der
	for i = 1, config.FireEngineCount do
		local engine = getFireEngineTemplate()
		engine.Name = "FireEngine_" .. cityName .. "_" .. i
		engine:SetAttribute("CityName", cityName)
		engine:SetAttribute("MaxHealth", config.FireEngineHP)
		engine:SetAttribute("Health", config.FireEngineHP)
		engine:SetAttribute("Destroyed", false)
		-- Aktiviert das Blinklicht-Script im Fahrzeug-Modell (falls vorhanden) -- Sirenen/
		-- Blaulicht laufen während der gesamten Alert-Level-2-Reaktion.
		engine:SetAttribute("EmergencyLightsEnabled", true)
		CollectionService:AddTag(engine, FIRE_ENGINE_TAG)

		-- WICHTIG: alle Teile verankern (Anchored = true). Die Bewegung läuft komplett
		-- über engine:PivotTo() (Teleport-Schritte, kein echtes Fahrphysik-Fahrzeug) --
		-- unverankerte Teile würden zwischen den Teleport-Schritten trotzdem der
		-- Schwerkraft/Kollision unterliegen und beim Kontakt mit hügeligem Gelände
		-- auseinandergerissen werden. CanCollide bleibt unverändert, damit Treffer-
		-- Erkennung (Touched/Angriffe) weiterhin normal funktioniert.
		for _, part in ipairs(engine:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end

		local offset = Vector3.new((i - 1) * 10 - (config.FireEngineCount - 1) * 5, 3, 0)
		engine.Parent = Workspace
		-- WICHTIG: wird an PivotMath.groundAlignedCFrame() weitergegeben (siehe
		-- driveTowards weiter unten) -- war bisher nirgends gesetzt, das Modul bekam also
		-- immer 'nil' übergeben, was auf Schrägen zu Wackeln/Steckenbleiben führen konnte.
		engine:SetAttribute("GroundClearance", GROUND_CLEARANCE)
		local spawnAt = spawnPosition + offset
		local groundY = getGroundInfo(spawnAt, spawnAt.Y)
		engine:PivotTo(CFrame.new(spawnAt.X, groundY + GROUND_CLEARANCE, spawnAt.Z))
		GroundVehicleSeparation.RegisterPosition(engine, "FireEngine", spawnAt)
		createFireEngineHealthBar(engine)

		table.insert(activeEnginesByCity[cityName], engine)
		connectFireEngineTouch(engine)
		runFireEngine(engine, cityName, config)
	end
end

local function despawnEnginesForCity(cityName)
	for _, engine in ipairs(activeEnginesByCity[cityName]) do
		if engine.Parent then
			-- Sanftes Abziehen statt hartem Despawn-Pop: kurz ausblenden, dann weg.
			engine:SetAttribute("Destroyed", true) -- stoppt die Lösch-/Fahr-Loop
			GroundVehicleSeparation.Unregister(engine)
			task.delay(0.5, function()
				if engine.Parent then
					engine:Destroy()
				end
			end)
		end
	end
	activeEnginesByCity[cityName] = {}
end
_G.DespawnFireEnginesForCity = despawnEnginesForCity

-- WICHTIG: wartet notfalls kurz auf _G.CityAlertLevelChanged, statt nur EINMALIG beim
-- eigenen Start zu prüfen -- Scripts direkt unter ServerScriptService starten in
-- unbestimmter Reihenfolge, dieses Script könnte also vor CityAlertService.lua laufen,
-- wodurch die Verbindung sonst nie zustande käme (gleicher Bugtyp wie zuvor bei
-- AlertHelicopterService.lua gefunden).
task.spawn(function()
	local attempts = 0
	while not _G.CityAlertLevelChanged and attempts < 100 do
		task.wait(0.1)
		attempts += 1
	end
	if not _G.CityAlertLevelChanged then
		warn("[FireEngineController] _G.CityAlertLevelChanged nie gefunden (10s Timeout) -- Feuerwehr bleibt wirkungslos. Läuft CityAlertService.lua?")
		return
	end

	_G.CityAlertLevelChanged.Event:Connect(function(cityName, newLevel, oldLevel)
		debugPrint("[Kaiju-Debug] CityAlertLevelChanged:", cityName, oldLevel, "->", newLevel)
		if newLevel == 2 and oldLevel == 1 then
			spawnEnginesForCity(cityName)
		elseif newLevel < 2 and oldLevel >= 2 then
			-- WICHTIG: reagiert auf JEDEN Abfall unter Level 2, nicht nur den exakten
			-- 2->1-Schritt -- ein Sprung-Reset (z.B. CITY BROKEN: 4->0 in einem Schritt)
			-- hätte den alten, exakten Trigger sonst nie ausgelöst und activeEnginesByCity
			-- wäre dauerhaft mit inzwischen zerstörten/unsichtbaren Fahrzeugen hängen
			-- geblieben (gleicher Bug wie zuvor bei MilitaryService/CityDefenderService
			-- gefunden und behoben).
			despawnEnginesForCity(cityName)
		end
		-- Künftige Alert-Level 3+: hier weitere elseif-Zweige für neue Übergänge ergänzen.
	end)
end)