-- VERSION: 2026-08-19 #53
-- Script (kein LocalScript!): AlertHelicopterService
-- Ort in Studio: ServerScriptService
--
-- Alert-Level 1: ein unzerstörbarer Helikopter mit Suchscheinwerfer zeigt reine Präsenz
-- -- kein Kampf, keine Interaktion. Fliegt in einer Ellipsen-Flugbahn, deren zwei
-- Brennpunkte der Spieler (letzter Angreifer dieser Stadt) und das GRÖSSTE (nach
-- MaxHealth) bisher zerstörte Gebäude dieser Stadt sind. Bleibt als Hintergrund-Präsenz
-- auch bei höheren Alert-Leveln (2, 3, ...) weiter aktiv -- verschwindet erst, wenn die
-- Stadt komplett auf Level 0 zurückfällt.
--
-- WICHTIG -- erwartetes Helikopter-Modell: ServerStorage.AlertHelicopterModel
--  - PrimaryPart muss gesetzt sein (bestimmt Position + Ausrichtung beim Fliegen)
--  - Optional: ein SpotLight-Descendant (irgendwo im Modell, z.B. in einem Part namens
--    "Searchlight") -- wird automatisch gefunden und leicht schwenkend nach unten
--    ausgerichtet animiert. Ohne SpotLight funktioniert der Helikopter trotzdem, nur
--    ohne den Scheinwerfer-Effekt.
--  - Keine Scripts/Humanoid nötig -- der Helikopter ist rein dekorativ, komplett
--    serverseitig positioniert.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Flughöhe skaliert dynamisch mit dem Level des Ziel-Spielers (siehe getFlightHeight
-- weiter unten): bei Spieler-Level 0 ungefähr Sprunghöhe, bei Spieler-Level 50 ungefähr
-- Augenhöhe -- UND immer mindestens so hoch wie das grösste zerstörte Gebäude.
local MAX_PLAYER_LEVEL = 50
local JUMP_HEIGHT_RATIO = 0.5 -- entspricht der Sprunghöhen-Formel in PlayerSetup.lua (characterHeight * 0.5)
local EYE_LEVEL_RATIO = 0.9 -- Augen sitzen ungefähr bei 90% der Charakterhöhe
local BUILDING_CLEARANCE = 15 -- Mindestabstand über dem Gebäude, damit der Helikopter sichtbar drüber fliegt
local ORBIT_PERIOD = 28 -- Sekunden für eine volle Ellipsen-Umrundung (halbierte Geschwindigkeit)
local ELLIPSE_WIDENING = 0.9 -- wie viel breiter die Ellipse ist als die reine Verbindungslinie (0 = Linie, 1 = sehr rund)
local ORBIT_SIZE_BUFFER = 30 -- fester Zusatz-Abstand zu den Brennpunkten (additiv statt multiplikativ -- verhindert übertriebene Grösse bei weit auseinanderliegenden Brennpunkten)
local MAX_SPEED = 45 -- Studs/Sekunde -- verhindert schnelles "Herbeischiessen" bei Brennpunkt-Wechseln (z.B. Gebäude-Respawn)
local FALLBACK_ORBIT_RADIUS = 60 -- falls (noch) kein zerstörtes Gebäude bekannt ist, um den Spieler kreisen
local BOB_AMPLITUDE = 4 -- Studs, wie stark der Helikopter beim Fliegen auf und ab schwingt
local BOB_SPEED = 0.9 -- wie schnell das Auf-und-Ab-Schwingen ist
-- Brennpunkt-Glättung: verhindert ein Springen/Teleportieren der Flugbahn, wenn sich der
-- Brennpunkt ändert (z.B. ein stärkeres Gebäude wird zerstört) -- die tatsächlich für die
-- Ellipse genutzten Positionen nähern sich den neuen Zielpositionen graduell an, statt
-- sie sofort zu übernehmen. Wert = Anteil der Annäherung pro Sekunde (höher = schneller).
local FOCUS_SMOOTHING_RATE = 0.6

-- [cityName][houseInstance] = { position = Vector3, maxHealth = number, height = number }
-- WICHTIG: speichert ALLE aktuell zerstörten Gebäude (nicht nur das stärkste) -- sobald
-- ein Gebäude respawnt, wird sein Eintrag entfernt (siehe _G.UnregisterDestroyedBuilding-
-- ForHelicopter) und der nächststärkste verbleibende Eintrag übernimmt automatisch den
-- Brennpunkt.
local destroyedBuildings = {}
-- [cityName] = Player (letzter Angreifer dieser Stadt)
local lastAttacker = {}
-- [cityName] = { model = Model, angle = number, searchlights = {SpotLight, ...} }
local activeHelicopters = {}

-- Findet das aktuell STÄRKSTE (nach MaxHealth) noch zerstörte Gebäude einer Stadt, oder
-- nil, falls gerade keines zerstört ist (alle respawnt).
local function getStrongestDestroyedBuilding(cityName)
	local buildings = destroyedBuildings[cityName]
	if not buildings then
		return nil
	end
	local best = nil
	for _, data in pairs(buildings) do
		local dataHealth = tonumber(data.maxHealth) or 0
		local bestHealth = best and (tonumber(best.maxHealth) or 0) or -1
		if not best or dataHealth >= bestHealth then
			best = data
		end
	end
	return best
end

-- Von HouseHandler.lua bei JEDER Zerstörung aufgerufen.
_G.RegisterDestroyedBuildingForHelicopter = function(cityName, house, position, maxHealth, attackerPlayer, buildingHeight)
	destroyedBuildings[cityName] = destroyedBuildings[cityName] or {}
	destroyedBuildings[cityName][house] = { position = position, maxHealth = tonumber(maxHealth) or 0, height = buildingHeight or 0 }
	if attackerPlayer then
		lastAttacker[cityName] = attackerPlayer
	end
end

-- Von HouseHandler.lua bei JEDEM Respawn aufgerufen -- entfernt das Gebäude aus der
-- Liste der aktuell zerstörten Gebäude. Falls es gerade der Brennpunkt war, übernimmt
-- automatisch das nächststärkste verbleibende zerstörte Gebäude (siehe
-- getStrongestDestroyedBuilding).
_G.UnregisterDestroyedBuildingForHelicopter = function(cityName, house)
	if destroyedBuildings[cityName] then
		destroyedBuildings[cityName][house] = nil
	end
end

local function getHelicopterTemplate()
	local template = ServerStorage:FindFirstChild("AlertHelicopterModel")
	if not template then
		warn("[AlertHelicopterService] ServerStorage.AlertHelicopterModel nicht gefunden -- Level-1-Helikopter bleibt wirkungslos.")
	end
	return template
end

local function findSearchlights(model)
	local lights = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("SpotLight") then
			table.insert(lights, descendant)
		end
	end
	return lights
end

local function spawnHelicopter(cityName)
	if activeHelicopters[cityName] then
		print("[AlertHelicopterService] Helikopter für '" .. cityName .. "' bereits aktiv -- kein erneuter Spawn.")
		return
	end
	local template = getHelicopterTemplate()
	if not template then
		return -- getHelicopterTemplate warnt bereits selbst
	end
	print("[AlertHelicopterService] Vorlage gefunden, klone Helikopter für '" .. cityName .. "'...")

	local model = template:Clone()
	model.Name = "AlertHelicopter_" .. cityName
	if not model.PrimaryPart then
		warn("[AlertHelicopterService] AlertHelicopterModel hat keinen PrimaryPart gesetzt -- kann nicht positioniert werden.")
		model:Destroy()
		return
	end
	model.Parent = Workspace
	print("[AlertHelicopterService] Helikopter für '" .. cityName .. "' erfolgreich in Workspace gespawnt.")

	-- Helikopter-Sound -- läuft in Dauerschleife, solange der Helikopter aktiv ist,
	-- verschwindet automatisch mit dem Modell (kein separates Aufräumen nötig).
	local sound = Instance.new("Sound")
	sound.Name = "HelicopterSound"
	sound.SoundId = "rbxassetid://119671916103305"
	sound.Looped = true
	sound.Volume = 0.7
	sound.RollOffMaxDistance = 400
	sound.RollOffMinDistance = 30
	sound.Parent = model.PrimaryPart
	if sound.SoundId ~= "" and sound.SoundId ~= "rbxassetid://0" then
		sound:Play()
	end

	-- Ankunfts-Sound -- spielt einmalig beim Erscheinen (nicht in Dauerschleife wie der
	-- Motoren-Sound oben). Ersetzt den bisherigen Ankündigungs-Sound bei jedem
	-- Alert-Level-Wechsel -- dieser hier spielt gezielt nur, wenn der Helikopter erscheint.
	local arrivalSound = Instance.new("Sound")
	arrivalSound.Name = "HelicopterArrivalSound"
	arrivalSound.SoundId = "rbxassetid://9125773667"
	arrivalSound.Volume = 0.9
	arrivalSound.RollOffMaxDistance = 400
	arrivalSound.RollOffMinDistance = 30
	arrivalSound.Parent = model.PrimaryPart
	if arrivalSound.SoundId ~= "" and arrivalSound.SoundId ~= "rbxassetid://0" then
		arrivalSound:Play()
	end

	activeHelicopters[cityName] = {
		model = model,
		angle = 0,
		searchlights = findSearchlights(model),
	}
end

local function despawnHelicopter(cityName)
	local heli = activeHelicopters[cityName]
	if not heli then
		return
	end
	if heli.model then
		heli.model:Destroy()
	end
	activeHelicopters[cityName] = nil
end

-- Berechnet die aktuelle Flughöhe: interpoliert zwischen Sprunghöhe (Spieler-Level 0)
-- und Augenhöhe (Spieler-Level 50), basierend auf der TATSÄCHLICHEN aktuellen Grösse
-- des Ziel-Spielers (skaliert ja mit Skin-Stufe) -- UND immer mindestens so hoch wie
-- das grösste zerstörte Gebäude plus etwas Abstand.
local function getFlightHeight(cityName, groundY)
	local attacker = lastAttacker[cityName]
	local characterHeight = 20 -- Fallback, falls kein Spieler-Charakter verfügbar ist
	local playerLevel = 0

	if attacker and attacker.Parent and attacker.Character then
		local ok, _, size = pcall(function()
			return attacker.Character:GetBoundingBox()
		end)
		if ok and size then
			characterHeight = size.Y
		end
		local leaderstats = attacker:FindFirstChild("leaderstats")
		if leaderstats and leaderstats:FindFirstChild("Level") then
			playerLevel = leaderstats.Level.Value
		end
	end

	local jumpHeightEquivalent = characterHeight * JUMP_HEIGHT_RATIO
	local eyeLevelEquivalent = characterHeight * EYE_LEVEL_RATIO
	local t = math.clamp(playerLevel / MAX_PLAYER_LEVEL, 0, 1)
	local heightAboveGround = jumpHeightEquivalent + (eyeLevelEquivalent - jumpHeightEquivalent) * t

	-- Immer mindestens so hoch wie das grösste zerstörte Gebäude, damit der Helikopter
	-- sichtbar drüber fliegt, unabhängig von der Spieler-Grösse.
	local building = getStrongestDestroyedBuilding(cityName)
	if building and building.height and building.height > 0 then
		heightAboveGround = math.max(heightAboveGround, building.height + BUILDING_CLEARANCE)
	end

	return heightAboveGround
end

-- Berechnet die aktuellen zwei Brennpunkte für eine Stadt: letzter Angreifer (falls noch
-- im Spiel) + STÄRKSTES aktuell zerstörtes Gebäude (kann wechseln, sobald ein stärkeres
-- zerstört wird ODER das bisherige respawnt). Falls GAR kein Gebäude mehr zerstört ist,
-- liegen BEIDE Brennpunkte auf dem Spieler (er kreist dann quasi über dem Spieler).
-- Drosselung für die Diagnose-Prints unten -- läuft bei jedem Heartbeat-Tick, ohne
-- Drosselung würde das die Konsole komplett fluten.
local lastFociDebugPrintAt = {}
local FOCI_DEBUG_PRINT_INTERVAL = 3

local function getFociForCity(cityName)
	local shouldPrint = (os.clock() - (lastFociDebugPrintAt[cityName] or 0)) >= FOCI_DEBUG_PRINT_INTERVAL
	if shouldPrint then
		lastFociDebugPrintAt[cityName] = os.clock()
	end

	local attacker = lastAttacker[cityName]
	local playerPosition = nil
	if shouldPrint then
		if not attacker then
			print("[AlertHelicopterService] Kein lastAttacker für '" .. cityName .. "' bekannt.")
		elseif not attacker.Parent then
			print("[AlertHelicopterService] lastAttacker für '" .. cityName .. "' ist nicht mehr im Spiel.")
		elseif not attacker.Character then
			print("[AlertHelicopterService] lastAttacker für '" .. cityName .. "' hat aktuell keinen Character.")
		end
	end

	if attacker and attacker.Parent and attacker.Character then
		-- WICHTIG: nur verfolgen, solange der Spieler noch in DIESER Stadt ist -- sonst
		-- würde der Helikopter ihm bis ins Sanctuary oder in andere Städte hinterherfliegen.
		if attacker:GetAttribute("CurrentCityName") == cityName then
			local rootPart = attacker.Character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				playerPosition = rootPart.Position
			elseif shouldPrint then
				print("[AlertHelicopterService] lastAttacker-Character für '" .. cityName .. "' hat kein HumanoidRootPart.")
			end
		elseif shouldPrint then
			print("[AlertHelicopterService] lastAttacker für '" .. cityName .. "' hat die Stadt verlassen -- wird nicht mehr verfolgt.")
		end
	end

	local building = getStrongestDestroyedBuilding(cityName)

	if playerPosition and building then
		return playerPosition, building.position
	elseif playerPosition then
		-- Kein Gebäude (mehr) zerstört -- beide Brennpunkte auf den Spieler legen.
		return playerPosition, playerPosition
	elseif building then
		if shouldPrint then
			print("[AlertHelicopterService] '" .. cityName .. "': kein Spieler-Fokus verfügbar -- kreise nur um das Gebäude.")
		end
		return building.position, building.position + Vector3.new(FALLBACK_ORBIT_RADIUS, 0, 0)
	end
	return nil, nil
end

-- Bewegt einen aktiven Helikopter einen Schritt entlang seiner Ellipsen-Flugbahn weiter.
local function updateHelicopter(cityName, heli, deltaTime)
	local rawFocusA, rawFocusB = getFociForCity(cityName)
	if not rawFocusA or not rawFocusB then
		return
	end

	-- Brennpunkt-Glättung: nähert die tatsächlich genutzten Positionen graduell den neuen
	-- Zielwerten an, statt sie sofort zu übernehmen -- verhindert ein Springen der
	-- Flugbahn, wenn sich der Brennpunkt ändert (z.B. stärkeres Gebäude zerstört).
	if not heli.smoothedFocusA then
		heli.smoothedFocusA = rawFocusA
		heli.smoothedFocusB = rawFocusB
	end
	local smoothAlpha = math.clamp(FOCUS_SMOOTHING_RATE * deltaTime, 0, 1)
	heli.smoothedFocusA = heli.smoothedFocusA:Lerp(rawFocusA, smoothAlpha)
	heli.smoothedFocusB = heli.smoothedFocusB:Lerp(rawFocusB, smoothAlpha)
	local focusA, focusB = heli.smoothedFocusA, heli.smoothedFocusB

	local center = (focusA + focusB) / 2
	local diff = focusB - focusA
	local distance = Vector3.new(diff.X, 0, diff.Z).Magnitude

	-- Ellipsen-Geometrie: die Verbindungslinie der Brennpunkte ist die grosse Halbachse
	-- (a), die kleine Halbachse (b) macht die Ellipse "breiter" als eine reine Linie.
	-- ORBIT_SIZE_MULTIPLIER vergrössert den gesamten Abstand zu den Brennpunkten.
	local semiMajor = math.max(distance / 2 + ORBIT_SIZE_BUFFER, 5)
	local semiMinor = math.max(semiMajor * ELLIPSE_WIDENING, 5)

	-- Rotationswinkel der Ellipse in der XZ-Ebene (Ausrichtung entlang der
	-- Brennpunkt-Verbindungslinie).
	local rotationAngle = math.atan2(diff.Z, diff.X)

	heli.angle = heli.angle + (2 * math.pi / ORBIT_PERIOD) * deltaTime
	if heli.angle > 2 * math.pi then
		heli.angle = heli.angle - 2 * math.pi
	end

	-- Punkt auf der (noch unrotierten) Ellipse, dann um rotationAngle in die
	-- Brennpunkt-Richtung gedreht.
	local localX = math.cos(heli.angle) * semiMajor
	local localZ = math.sin(heli.angle) * semiMinor
	local worldX = center.X + localX * math.cos(rotationAngle) - localZ * math.sin(rotationAngle)
	local worldZ = center.Z + localX * math.sin(rotationAngle) + localZ * math.cos(rotationAngle)
	local flightHeight = getFlightHeight(cityName, center.Y)
	-- Leichtes vertikales Schweben (Auf und Ab) für einen natürlicheren, weniger
	-- roboterhaften Flug.
	local bobOffset = math.sin(os.clock() * BOB_SPEED) * BOB_AMPLITUDE
	local idealPosition = Vector3.new(worldX, center.Y + flightHeight + bobOffset, worldZ)

	-- Höchstgeschwindigkeits-Begrenzung: bewegt sich maximal MAX_SPEED Studs/Sekunde von
	-- der aktuellen zur idealen Position -- verhindert schnelles "Herbeischiessen", wenn
	-- sich die Brennpunkte stark ändern (z.B. ein Gebäude respawnt und der zweite
	-- Brennpunkt springt dadurch auf den Spieler).
	if not heli.currentPosition then
		heli.currentPosition = idealPosition
	end
	local toIdeal = idealPosition - heli.currentPosition
	local maxStep = MAX_SPEED * deltaTime
	if toIdeal.Magnitude > maxStep then
		heli.currentPosition = heli.currentPosition + toIdeal.Unit * maxStep
	else
		heli.currentPosition = idealPosition
	end
	local targetPosition = heli.currentPosition

	-- Ausrichtung: leicht voraus schauen (nächster Punkt auf der Bahn), für eine
	-- natürliche Flugrichtung statt starrem Blick geradeaus.
	local lookAheadAngle = heli.angle + 0.1
	local lookLocalX = math.cos(lookAheadAngle) * semiMajor
	local lookLocalZ = math.sin(lookAheadAngle) * semiMinor
	local lookWorldX = center.X + lookLocalX * math.cos(rotationAngle) - lookLocalZ * math.sin(rotationAngle)
	local lookWorldZ = center.Z + lookLocalX * math.sin(rotationAngle) + lookLocalZ * math.cos(rotationAngle)
	local lookTarget = Vector3.new(lookWorldX, targetPosition.Y, lookWorldZ)

	local ok = pcall(function()
		heli.model:PivotTo(CFrame.lookAt(targetPosition, lookTarget))
	end)
	if not ok then
		return
	end

	-- Suchscheinwerfer: langsam schwenkend nach unten gerichtet, für den "suchenden"
	-- Effekt -- reine Kosmetik, kein Gameplay-Zweck.
	for _, light in ipairs(heli.searchlights) do
		light.Angle = 35 + math.sin(os.clock() * 0.6) * 8
	end
end

-- ===== Level-Wechsel abonnieren: spawnt bei Erreichen von Level 1 (von 0 aus), despawnt
-- erst beim Rückfall auf Level 0 -- bleibt bei höheren Leveln (2, 3, ...) als
-- Hintergrund-Präsenz aktiv.
-- WICHTIG: wartet notfalls kurz auf _G.CityAlertLevelChanged, statt nur EINMALIG beim
-- eigenen Start zu prüfen -- Scripts direkt unter ServerScriptService starten in
-- unbestimmter Reihenfolge, dieses Script könnte also vor CityAlertService.lua laufen,
-- wodurch die Verbindung sonst nie zustande käme. =====
task.spawn(function()
	local attempts = 0
	while not _G.CityAlertLevelChanged and attempts < 100 do
		task.wait(0.1)
		attempts += 1
	end
	if not _G.CityAlertLevelChanged then
		warn("[AlertHelicopterService] _G.CityAlertLevelChanged nie gefunden (10s Timeout) -- Helikopter bleibt wirkungslos. Läuft CityAlertService.lua?")
		return
	end

	_G.CityAlertLevelChanged.Event:Connect(function(cityName, newLevel, oldLevel)
		print("[AlertHelicopterService] Level-Wechsel für '" .. cityName .. "': " .. oldLevel .. " -> " .. newLevel)
		if newLevel >= 1 and oldLevel == 0 then
			print("[AlertHelicopterService] Versuche Helikopter für '" .. cityName .. "' zu spawnen...")
			spawnHelicopter(cityName)
		elseif newLevel == 0 then
			despawnHelicopter(cityName)
			destroyedBuildings[cityName] = nil
			lastAttacker[cityName] = nil
		end
	end)
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for cityName, heli in pairs(activeHelicopters) do
		updateHelicopter(cityName, heli, deltaTime)
	end
end)

print("[Kaiju] AlertHelicopterService bereit -- Level 1 (Präsenz-Helikopter, bleibt bei höheren Leveln aktiv).")