-- VERSION: 2026-08-25 #12
-- FEATURE: _G.SetCityManuallyDriven ergänzt (organische Beiträge für Prolog blockieren)
-- Ort in Studio: ServerScriptService
--
-- Kern des City-Alert-Systems. JEDE Stadt hat ihren EIGENEN, unabhängigen Alert-Level und
-- Alert-Fortschritt -- Zerstörung in Village erhöht NIEMALS den Alert von SmallTown/City/etc.
--
-- Architektur: dieses Script kennt nur "Alert-Fortschritt steigt/sinkt, Level wechselt
-- bei Schwellenwerten". Was bei Level 2 tatsächlich PASSIERT (Feuerwehrautos etc.) lebt
-- in FireResponseService.lua / FireEngineController.lua -- diese abonnieren einfach
-- CityAlertLevelChanged. Künftige Alert-Level 3+ brauchen NUR einen weiteren Eintrag in
-- CityAlertConfig + einen weiteren Listener, OHNE dieses Script anzufassen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CityAlertConfig = require(ReplicatedStorage:WaitForChild("CityAlertConfig"))

-- [cityName] = { level = number, progress = number, lastGainAt = os.clock() }
-- WICHTIG: Level 0 ist jetzt die neue Baseline (vorher war das Level 1). Level 1 ist neu
-- der "Helikopter"-Zustand (Präsenz-Anzeige, kein echter Kampf) -- startet, sobald das
-- ERSTE Gebäude einer Stadt zerstört wurde (progress > 0), nicht schwellenwert-basiert
-- wie die höheren Level. Level 2+ (Feuerwehr, Barrikaden, ...) bleiben unverändert an
-- ihren bisherigen Schwellenwerten (AlertThresholdLevel2 etc.).
local cityState = {}
for _, cityName in ipairs(CityAlertConfig.CityOrder) do
	cityState[cityName] = { level = 0, progress = 0, lastGainAt = 0 }
end

-- Event, auf das andere Systeme (FireResponseService etc.) reagieren können, OHNE dass
-- dieses Script sie kennen muss. Feuert mit (cityName, newLevel, oldLevel).
local CityAlertLevelChanged = Instance.new("BindableEvent")
CityAlertLevelChanged.Name = "CityAlertLevelChanged"
CityAlertLevelChanged.Parent = script
_G.CityAlertLevelChanged = CityAlertLevelChanged

-- Optionaler Live-Wert pro Stadt (für HUD/Debug) -- unter ReplicatedStorage, damit Clients
-- ihn direkt lesen können, ohne ein eigenes RemoteEvent zu brauchen.
local cityAlertFolder = Instance.new("Folder")
cityAlertFolder.Name = "CityAlertValues"
cityAlertFolder.Parent = ReplicatedStorage

local cityLevelValues = {} -- [cityName] = IntValue
local cityProgressValues = {} -- [cityName] = NumberValue
local cityMaxLevelValues = {} -- [cityName] = IntValue (kapitelabhaengige Hoechststufe)
for _, cityName in ipairs(CityAlertConfig.CityOrder) do
	local levelValue = Instance.new("IntValue")
	levelValue.Name = cityName .. "Level"
	levelValue.Value = 0
	levelValue.Parent = cityAlertFolder
	cityLevelValues[cityName] = levelValue

	local progressValue = Instance.new("NumberValue")
	progressValue.Name = cityName .. "Progress"
	progressValue.Value = 0
	progressValue.Parent = cityAlertFolder
	cityProgressValues[cityName] = progressValue

	-- Die AKTUELL geltende Hoechststufe. Seit sie vom Kapitel abhaengt, kann der Client
	-- sie nicht mehr aus dem Config ableiten -- dort steht nur der Kapitel-I-Wert. Das
	-- HUD zeichnet daraus die gedimmten "Deckel"-Sterne.
	local maxLevelValue = Instance.new("IntValue")
	maxLevelValue.Name = cityName .. "MaxLevel"
	maxLevelValue.Value = CityAlertConfig.GetCityConfig(cityName).MaxAlertLevel or 5
	maxLevelValue.Parent = cityAlertFolder
	cityMaxLevelValues[cityName] = maxLevelValue
end

-- ===== Stadt-Auflösung: läuft die Ancestor-Kette hoch und sucht das erste "CityName"-
-- Attribut. So muss NUR der Stadt-Container in Studio (z.B. workspace.Cities.Village)
-- das Attribut CityName="Village" tragen -- alle Häuser/Feuerwehrautos/etc. darunter
-- werden automatisch zugeordnet, ohne jedes einzelne Objekt markieren zu müssen. =====
local function resolveCityName(instance)
	-- Direktes Attribut hat Vorrang (z.B. falls ein einzelnes Objekt explizit einer
	-- anderen Stadt zugeordnet werden soll).
	local direct = instance:GetAttribute("CityName")
	if direct then
		return direct
	end

	local current = instance.Parent
	while current do
		local cityName = current:GetAttribute("CityName")
		if cityName then
			return cityName
		end
		current = current.Parent
	end

	return nil
end
_G.ResolveCityName = resolveCityName

-- ===== Level-Übergänge: aktuell nur 1<->2, aber generisch genug für 3+ =====
local function setCityLevel(cityName, newLevel)
	local state = cityState[cityName]
	if not state or state.level == newLevel then
		return
	end
	local oldLevel = state.level
	state.level = newLevel
	if cityLevelValues[cityName] then
		cityLevelValues[cityName].Value = newLevel
	end
	-- Lebensstatistik: eine erreichte Alarmstufe ist ein STADT-Ereignis ohne einzelnen
	-- Verursacher. Sie geht deshalb an alle Spieler, die gerade in dieser Stadt sind --
	-- im Koop hat sie miterlebt, wer dabei war. Nur AUFSTIEGE zählen.
	if newLevel > oldLevel and _G.RecordStatForCity then
		_G.RecordStatForCity(cityName, "AlertReached." .. newLevel .. "." .. cityName)
	end

	CityAlertLevelChanged:Fire(cityName, newLevel, oldLevel)

	-- Eskalations-Zähler (Stufe 2/3/4, siehe EscalationService.lua) zurücksetzen, sobald
	-- die Stadt komplett auf die neue Baseline (Level 0) zurückfällt -- alle bis dahin
	-- gespawnten Eskalations-Einheiten (Barrikaden, zusätzliche Feuerwehr, Militär) sollen
	-- dann ebenfalls despawnen bzw. der Zähler soll für den nächsten Alert-Zyklus wieder
	-- bei 0 starten.
	if newLevel == 0 and _G.ResetEscalation then
		_G.ResetEscalation(cityName)
	end
end

-- ===== Kapitel-abhängige Höchststufe =====
-- Die drei Figuren sind zugleich die drei Kapitel (siehe CLAUDE.md). Dieselbe Karte
-- härtet sich über die Kapitel hinweg: das Village lernt in Kapitel II das Militär
-- kennen, SmallTown steigt auf Stufe 5, und in Kapitel III bekommt auch das Village
-- einen Guardian. Eine Stadt, die man in Kapitel I gebrochen hat, ist damit später
-- wieder eine echte Aufgabe.
--
-- Gewählter Ansatz: HÖCHSTES KAPITEL IM RAUM GEWINNT. Der Alarmzustand gehört der
-- STADT, nicht dem einzelnen Spieler -- eine Stufe, ein Fortschritt, für alle
-- Anwesenden. Steht ein Jaeger im Village, gilt dessen Kapitel auch für den Kaiju
-- daneben. Das ist die einfachste der drei Auflösungen und bewusst als Startpunkt
-- gewählt; die Kehrseite ist, dass ein Neuling in eine Eskalation geraten kann, für die
-- er nicht ausgerüstet ist.
local FACTION_CHAPTER = { Kaiju = 1, Jaeger = 2, Ronin = 3 }

local function getHighestChapterInCity(cityName)
	local highest = 1
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName then
			local chapter = FACTION_CHAPTER[player:GetAttribute("Faction")] or 1
			if chapter > highest then
				highest = chapter
			end
		end
	end
	return highest
end

-- Auch fuer andere Dienste: CityDefenderService leitet daraus ab, WELCHE
-- Guardian-Generation in dieser Stadt erscheint (die Kette wandert je Kapitel eine
-- Stadt nach vorne).
_G.GetHighestChapterInCity = getHighestChapterInCity

-- MaxAlertLevel bleibt der Grundwert und zugleich der Rückfall: Städte, die in jedem
-- Kapitel dieselbe Höchststufe haben (City, LargeCity, MegaCity), brauchen kein
-- MaxAlertLevelByChapter.
-- [cityName] = zuletzt veroeffentlichte Obergrenze -- verhindert eine Ausgabe pro Aufruf.
local lastReportedMaxLevel = {}

local function getMaxAlertLevel(cityName, config)
	local byChapter = config.MaxAlertLevelByChapter
	if type(byChapter) == "table" then
		local level = byChapter[getHighestChapterInCity(cityName)]
		if type(level) == "number" then
			return level
		end
	end
	return config.MaxAlertLevel or 5
end

-- Berechnet die geltende Obergrenze neu und veroeffentlicht sie fuer den Client.
-- Bewusst NICHT nur aus checkLevelThresholds heraus: das laeuft nur, wenn sich der
-- Fortschritt aendert. Betritt ein Jaeger eine ruhige Stadt, muesste das HUD sonst warten,
-- bis jemand etwas zerstoert.
local function refreshMaxAlertLevel(cityName)
	local config = CityAlertConfig.GetCityConfig(cityName)
	local base = config.MaxAlertLevel or 5
	local effective = getMaxAlertLevel(cityName, config)

	if lastReportedMaxLevel[cityName] ~= effective then
		lastReportedMaxLevel[cityName] = effective
		if cityMaxLevelValues[cityName] then
			cityMaxLevelValues[cityName].Value = effective
		end
		print(string.format(
			"[Kaiju-Debug] %s: Hoechststufe %d (Grundwert %d, hoechstes Kapitel im Raum: %d)",
			cityName, effective, base, getHighestChapterInCity(cityName)))
	end
	return effective
end

local function checkLevelThresholds(cityName)
	local state = cityState[cityName]
	local config = CityAlertConfig.GetCityConfig(cityName)
	-- Konzept-Vorgabe: nicht jede Stadt kennt alle Alert-Stufen (z.B. Village in
	-- Kapitel I nur bis Level 3) -- gilt NUR für den Aufstieg, der Abstieg bleibt
	-- uneingeschränkt möglich. Verlässt der Jaeger das Village wieder, fällt die
	-- Obergrenze also zurück, die bereits erreichte Stufe bleibt aber bestehen, bis der
	-- Fortschritt sinkt. Das ist gewollt: eine losgetretene Eskalation soll nicht
	-- verschwinden, nur weil jemand weggeht.
	local maxLevel = refreshMaxAlertLevel(cityName)

	-- Schleife statt einzelner if/elseif-Prüfung: ein direkter Sprung (z.B. per Debug-
	-- Regler von Level 1 auf einen Fortschritt weit über der Level-3-Schwelle) soll ALLE
	-- fälligen Stufen in einem Aufruf durchlaufen, nicht nur die jeweils nächste.
	local changed = true
	local safetyCounter = 0
	while changed and safetyCounter < 10 do
		changed = false
		safetyCounter += 1

		if state.level == 0 and state.progress > 0 and maxLevel >= 1 then
			-- Neuer Level-1-Übergang: event-basiert (erstes zerstörtes Gebäude erhöht
			-- progress sofort über 0), NICHT schwellenwert-basiert wie die höheren Level.
			setCityLevel(cityName, 1)
			changed = true
		elseif state.level == 1 then
			if state.progress <= 0 then
				-- Fortschritt ist komplett auf 0 zerfallen (keine Zerstörung mehr seit
				-- langem) -- zurück zur echten Baseline, Helikopter verschwindet.
				setCityLevel(cityName, 0)
				changed = true
			elseif maxLevel >= 2 and state.progress >= config.AlertThresholdLevel2 then
				setCityLevel(cityName, 2)
				changed = true
			end
		elseif state.level == 2 then
			if state.progress < config.AlertThresholdLevel2 then
				-- Fortschritt ist (durch Zerfall) wieder unter die Schwelle gefallen --
				-- zurück zu Level 1. Erfüllt die Vorgabe "System muss Rückkehr zu
				-- niedrigeren Alert-Zuständen unterstützen".
				setCityLevel(cityName, 1)
				changed = true
			elseif maxLevel >= 3 and config.AlertThresholdLevel3 and state.progress >= config.AlertThresholdLevel3 then
				-- Rein threshold-basiert -- die Emergency-Response (Feuerwehr) muss NICHT
				-- besiegt sein, um weiterzueskalieren. Ob sie besiegt wurde, ist stattdessen
				-- Voraussetzung für "Stadt fällt"/Free Destruction (kommt als eigenes
				-- Feature) -- siehe _G.HasActiveFireEngines weiter unten im Code.
				setCityLevel(cityName, 3)
				changed = true
			end
		elseif state.level == 3 then
			if config.AlertThresholdLevel3 and state.progress < config.AlertThresholdLevel3 then
				-- Zurück zu Level 2 (nicht direkt zu 1) -- konsistent mit dem einen
				-- Schritt zurück pro Zerfalls-Unterschreitung, wie beim 2->1 Übergang.
				setCityLevel(cityName, 2)
				changed = true
			elseif maxLevel >= 4 and config.AlertThresholdLevel4 and state.progress >= config.AlertThresholdLevel4 then
				setCityLevel(cityName, 4)
				changed = true
			end
		elseif state.level == 4 then
			if config.AlertThresholdLevel4 and state.progress < config.AlertThresholdLevel4 then
				-- Zurück zu Level 3 (nicht direkt zu 2) -- konsistent mit dem einen Schritt
				-- zurück pro Zerfalls-Unterschreitung.
				setCityLevel(cityName, 3)
				changed = true
			elseif maxLevel >= 5 and config.AlertThresholdLevel5 and state.progress >= config.AlertThresholdLevel5 then
				setCityLevel(cityName, 5)
				changed = true
			end
		elseif state.level == 5 and config.AlertThresholdLevel5 and state.progress < config.AlertThresholdLevel5 then
			-- Zurück zu Level 4 (nicht direkt zu 3) -- konsistent mit dem einen Schritt
			-- zurück pro Zerfalls-Unterschreitung.
			setCityLevel(cityName, 4)
			changed = true
		end
	end
	-- Künftige Alert-Level 6+: hier einfach weitere elseif-Zweige mit ihren eigenen
	-- Schwellenwerten aus der Config ergänzen -- der Rest des Systems (Zerfall,
	-- Stadt-Auflösung, Event-Feuern) funktioniert bereits generisch.
end

-- Für die drei Response-Systeme (FireEngineController/BarricadeClusterService/
-- MilitaryService): sobald deren letzte Einheit einer Stadt fällt, hier aufrufen, damit
-- die Eskalation SOFORT greift, statt erst beim nächsten Gebäude-Treffer erneut geprüft
-- zu werden.
_G.CheckCityAlertLevelThresholds = checkLevelThresholds

-- Fürs CITY-BROKEN-Feature (siehe CityBrokenService.lua): setzt eine Stadt komplett auf
-- Level 0 zurück, nachdem das Freie-Zerstörung-Fenster abgelaufen ist ("Stadt beruhigt
-- sich"). Direkter Sprung statt normalem Zerfall -- bewusst sofort, nicht schrittweise.
_G.ResetCityAlert = function(cityName)
	local state = cityState[cityName]
	if not state then
		return
	end
	state.progress = 0
	if cityProgressValues[cityName] then
		cityProgressValues[cityName].Value = 0
	end
	setCityLevel(cityName, 0)
end

-- ===== Erkennung: in welcher Stadt befindet sich der Spieler gerade? =====
-- Berechnet die räumliche Ausdehnung jeder Stadt EINMALIG aus den Bounding-Boxen aller
-- Nachfahren des jeweiligen CityName-Containers (kein zusätzliches Trigger-Volumen in
-- Studio nötig) und prüft periodisch, in welcher (falls überhaupt) sich jeder Spieler
-- befindet. Setzt "CurrentCityName" als Attribut am Spieler ("None" falls in keiner
-- Stadt) -- der Client liest das für die Alert-Level-Anzeige im HUD.

-- [cityName] = { minX, maxX, minZ, maxZ } -- wird beim ersten Zugriff pro Stadt berechnet
-- und dann zwischengespeichert (Städte bewegen sich nicht, einmal reicht).
local cityBounds = {}

local function computeCityBounds(cityName)
	local container
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:GetAttribute("CityName") == cityName and (descendant:IsA("Model") or descendant:IsA("Folder")) then
			container = descendant
			break
		end
	end
	if not container then
		return nil
	end

	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local foundAny = false
	for _, part in ipairs(container:GetDescendants()) do
		if part:IsA("BasePart") then
			foundAny = true
			local pos = part.Position
			minX = math.min(minX, pos.X)
			maxX = math.max(maxX, pos.X)
			minZ = math.min(minZ, pos.Z)
			maxZ = math.max(maxZ, pos.Z)
		end
	end
	if not foundAny then
		return nil
	end

	-- Kleiner Puffer nach aussen, damit der Übergang nicht exakt an der letzten
	-- Hauswand endet, sondern die Stadt sich noch etwas darüber hinaus "anfühlt".
	local PADDING = 20
	return { minX = minX - PADDING, maxX = maxX + PADDING, minZ = minZ - PADDING, maxZ = maxZ + PADDING }
end

local function getCurrentCityForPosition(position)
	for _, cityName in ipairs(CityAlertConfig.CityOrder) do
		if cityBounds[cityName] == nil then
			cityBounds[cityName] = computeCityBounds(cityName) or false -- false = "schon versucht, nichts gefunden"
		end
		local bounds = cityBounds[cityName]
		if bounds then
			if position.X >= bounds.minX and position.X <= bounds.maxX and position.Z >= bounds.minZ and position.Z <= bounds.maxZ then
				return cityName
			end
		end
	end
	return "None"
end

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local currentCity = getCurrentCityForPosition(rootPart.Position)
				if player:GetAttribute("CurrentCityName") ~= currentCity then
					player:SetAttribute("CurrentCityName", currentCity)
				end
			end
		end
		-- Die Anwesenheit hat sich moeglicherweise geaendert -- also auch das hoechste
		-- Kapitel im Raum und damit die Obergrenze jeder Stadt.
		for _, cityName in ipairs(CityAlertConfig.CityOrder) do
			refreshMaxAlertLevel(cityName)
		end

		task.wait(1) -- reicht völlig -- Städte wechseln sich nicht sekündlich
	end
end)

-- ===== Öffentliche API: Alert für eine Stadt erhöhen =====
-- "instance" ist das zerstörte Objekt (Haus, Feuerwehrauto, ...) -- daraus wird die
-- Stadt aufgelöst. "amount" ist der Alert-Betrag (z.B. schon vorberechnet aus MaxHealth,
-- oder ein fester Wert wie FireEngineDestroyAlertValue).
-- Städte, die komplett manuell/extern gesteuert werden (z.B. der Prolog mit seiner
-- zeitbasierten Eskalation) -- organische Beiträge (Gebäude-Zerstörung etc.) werden für
-- diese Städte IGNORIERT, damit sie nicht mit der externen Steuerung um den Fortschritt
-- konkurrieren (führte sonst zu sichtbar hin- und herspringenden Alert-Leveln: schnelle
-- Zerstörung drückt den Level organisch hoch, die externe Steuerung setzt ihn beim
-- nächsten periodischen Check wieder auf den "eigentlich korrekten" Wert zurück).
local manuallyDrivenCities = {} -- [cityName] = true

_G.SetCityManuallyDriven = function(cityName, isManual)
	manuallyDrivenCities[cityName] = isManual or nil
end

local function addCityAlert(instance, amount)
	if not amount or amount <= 0 then
		return
	end
	local cityName = resolveCityName(instance)
	if not cityName then
		warn("[CityAlertService] Konnte keine Stadt für '" .. instance:GetFullName() .. "' auflösen -- fehlt ein 'CityName'-Attribut an einem Vorfahren?")
		return
	end
	if manuallyDrivenCities[cityName] then
		return -- diese Stadt wird extern gesteuert -- organische Beiträge ignorieren
	end

	local state = cityState[cityName]
	if not state then
		warn("[CityAlertService] Unbekannte Stadt '" .. cityName .. "' -- in CityAlertConfig.Cities nicht konfiguriert.")
		return
	end

	local config = CityAlertConfig.GetCityConfig(cityName)
	state.progress = math.max(state.progress + amount, 0)
	state.lastGainAt = os.clock()
	if cityProgressValues[cityName] then
		cityProgressValues[cityName].Value = state.progress
	end

	checkLevelThresholds(cityName)
end
_G.AddCityAlert = addCityAlert

-- Direkte Variante von addCityAlert -- arbeitet mit dem Stadtnamen selbst statt einer
-- Instanz, die erst über die Ancestor-Kette aufgelöst werden müsste. Praktisch für
-- programmatische Steuerung (z.B. zeitbasierte Eskalation im Prolog), wo es keine
-- sinnvolle "auslösende Instanz" gibt.
_G.SetCityAlertProgress = function(cityName, amount)
	local state = cityState[cityName]
	if not state then
		warn("[CityAlertService] SetCityAlertProgress: Unbekannte Stadt '" .. cityName .. "'.")
		return
	end
	state.progress = math.max(amount, 0)
	state.lastGainAt = os.clock()
	if cityProgressValues[cityName] then
		cityProgressValues[cityName].Value = state.progress
	end
	checkLevelThresholds(cityName)
end

-- Setzt den Fortschritt EXAKT auf die Schwelle der angegebenen Ziel-Stufe (liest die
-- passende AlertThresholdLevelN aus CityAlertConfig). Für Level 1 wird auf 0 gesetzt
-- (unterhalb jeder Schwelle). Nützlich für zeitbasierte, von der tatsächlichen Zerstörung
-- unabhängige Eskalation.
_G.SetCityAlertLevel = function(cityName, targetLevel)
	if targetLevel <= 1 then
		_G.SetCityAlertProgress(cityName, 0)
		return
	end
	local config = CityAlertConfig.GetCityConfig(cityName)
	local thresholdKey = "AlertThresholdLevel" .. tostring(targetLevel)
	local threshold = config[thresholdKey]
	if not threshold then
		warn("[CityAlertService] SetCityAlertLevel: '" .. thresholdKey .. "' nicht in der Konfiguration von '" .. cityName .. "' gefunden.")
		return
	end
	_G.SetCityAlertProgress(cityName, threshold)
end

-- Bequemlichkeits-Funktion: berechnet den Alert-Wert eines Gebäudes automatisch aus
-- MaxHealth (falls kein eigenes "AlertValue"-Attribut in Studio gesetzt wurde) und fügt
-- ihn direkt der richtigen Stadt hinzu. Von HouseHandler.lua beim Zerstören aufgerufen.
_G.AddCityAlertForBuilding = function(house)
	local explicitValue = house:GetAttribute("AlertValue")
	if explicitValue then
		addCityAlert(house, explicitValue)
		return
	end

	local cityName = resolveCityName(house)
	local config = CityAlertConfig.GetCityConfig(cityName or "")
	local maxHealth = house:GetAttribute("MaxHealth") or 0
	addCityAlert(house, maxHealth * config.AlertPerHP)
end

_G.GetCityAlertLevel = function(cityName)
	local state = cityState[cityName]
	return state and state.level or 1
end

_G.GetCityAlertProgress = function(cityName)
	local state = cityState[cityName]
	return state and state.progress or 0
end

-- ===== Debug-Werkzeug: Alert-Fortschritt der Stadt, in der der Spieler gerade steht,
-- direkt per Schieberegler setzen (0-100%, wobei 100% deutlich über der Level-2-Schwelle
-- liegt, damit man auch testen kann, ob der Übergang sauber funktioniert). Nur wirksam,
-- wenn der Spieler seinen eigenen Debug-Modus aktiviert hat. =====
local DebugSetCityAlertEvent = Instance.new("RemoteEvent")
DebugSetCityAlertEvent.Name = "DebugSetCityAlertEvent"
DebugSetCityAlertEvent.Parent = ReplicatedStorage

DebugSetCityAlertEvent.OnServerEvent:Connect(function(player, targetLevel)
	if not player:GetAttribute("DebugMode") then
		return
	end
	local cityName = player:GetAttribute("CurrentCityName")
	if not cityName or cityName == "None" or not cityState[cityName] then
		return -- Spieler steht gerade in keiner erkannten Stadt
	end

	targetLevel = math.clamp(math.floor(tonumber(targetLevel) or 0), 0, 5)
	local config = CityAlertConfig.GetCityConfig(cityName)

	-- Fortschritt auf die exakte Schwelle der Zielstufe setzen -- checkLevelThresholds
	-- übernimmt danach den eigentlichen Stufenwechsel und respektiert dabei automatisch
	-- MaxAlertLevel dieser Stadt (z.B. Village stoppt bei 3, SmallTown bei 4 -- ein
	-- höherer Zielwert würde dort einfach auf der jeweiligen Obergrenze bleiben).
	local targetProgress
	if targetLevel <= 0 then
		targetProgress = 0
	elseif targetLevel == 1 then
		targetProgress = 1 -- knapp über 0 -- Level 1 ist event-basiert, keine eigene Schwelle
	else
		local thresholdKey = "AlertThresholdLevel" .. targetLevel
		targetProgress = config[thresholdKey]
		if not targetProgress then
			-- Diese Stadt kennt diese Stufe gar nicht (z.B. Village hat kein
			-- AlertThresholdLevel5) -- höchste bekannte Schwelle nutzen, damit der
			-- Regler nicht wirkungslos bleibt, sondern die Stadt an ihre reale
			-- Obergrenze bringt.
			targetProgress = config.AlertThresholdLevel4 or config.AlertThresholdLevel3 or config.AlertThresholdLevel2 or 1
		end
	end

	local state = cityState[cityName]
	state.progress = targetProgress
	state.lastGainAt = os.clock()
	if cityProgressValues[cityName] then
		cityProgressValues[cityName].Value = state.progress
	end
	checkLevelThresholds(cityName)
end)

-- ===== Alert-Zerfall: sinkt NUR, solange sich KEIN Spieler mehr in der Stadt
-- befindet (Rückzug) -- nicht mehr rein zeitbasiert. Wer in der Stadt bleibt und
-- weiterkämpft (auch mit kurzen Pausen zwischendurch), hält den Alert-Level oben, egal
-- wie lange der letzte Punktezuwachs her ist -- "aussitzen" innerhalb der Stadt bringt
-- nichts mehr. AlertDecayDelay wird jetzt als Gnadenfrist NACH dem tatsächlichen
-- Verlassen interpretiert (nicht mehr als Pause seit dem letzten Treffer).
local cityEmptySince = {} -- [cityName] = os.clock(), wann zuletzt kein Spieler mehr drin war (nil = aktuell noch jemand drin)

local function isAnyPlayerInCity(cityName)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName then
			return true
		end
	end
	return false
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for _, cityName in ipairs(CityAlertConfig.CityOrder) do
		local state = cityState[cityName]
		if state.progress > 0 then
			if isAnyPlayerInCity(cityName) then
				cityEmptySince[cityName] = nil -- jemand ist (wieder) da -- Zerfall pausiert
			else
				if not cityEmptySince[cityName] then
					cityEmptySince[cityName] = now
				end
				local config = CityAlertConfig.GetCityConfig(cityName)
				if now - cityEmptySince[cityName] >= config.AlertDecayDelay then
					state.progress = math.max(state.progress - config.AlertDecayRate * dt, 0)
					if cityProgressValues[cityName] then
						cityProgressValues[cityName].Value = state.progress
					end
					checkLevelThresholds(cityName)
				end
			end
		end
	end
end)