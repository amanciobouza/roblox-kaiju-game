-- VERSION: 2026-08-21 #6
-- Script (kein LocalScript!): CityBrokenService
-- Ort in Studio: ServerScriptService
--
-- Vierter und letzter Baustein aus dem grossen Alert-Konzept: CITY BROKEN.
--
-- Jede Stadt hat pro Alert-Stufe (2-5) eine "Aufgabe" -- sobald die jeweilige Response
-- (Feuerwehr/Barrikaden/Militär/Guardian) besiegt ist, gilt die Aufgabe als erledigt.
-- Eine Stadt kennt dabei NUR die Aufgaben bis zu ihrem eigenen MaxAlertLevel (siehe
-- CityAlertConfig.lua) -- Village z.B. hat gar keine Military-/Titan-Protocol-Aufgabe.
--
-- Sobald eine Stadt auf ihrer MAXIMALEN Stufe steht UND alle dortigen Aufgaben erledigt
-- sind, bricht die Stadt für 75 Sekunden zusammen ("CITY BROKEN"): freie Zerstörung,
-- keine neue Eskalation. Danach fällt der Alert komplett auf 0 zurück ("Stadt beruhigt
-- sich").
--
-- Aufgaben-Status wird pro Stadt als BoolValue unter ReplicatedStorage.CityAlertValues
-- bereitgestellt (gleiche Ordner-Konvention wie CityAlertService.lua), damit der Client
-- sie direkt lesen kann -- kein eigenes RemoteEvent nötig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CityAlertConfig = require(ReplicatedStorage:WaitForChild("CityAlertConfig"))
local cityAlertFolder = ReplicatedStorage:WaitForChild("CityAlertValues")

local FREE_DESTRUCTION_DURATION = 75 -- Sekunden

-- Jede Aufgabe: welchem Alert-Level sie entspricht, Anzeige-Text, und wie ihr
-- Erledigt-Status geprüft wird (liefert true, sobald die Response besiegt ist).
local TASK_DEFINITIONS = {
	{ level = 2, id = "Emergency", icon = "🚒", label = "Emergency Response eliminated", isComplete = function(cityName)
		return not (_G.HasActiveFireEngines and _G.HasActiveFireEngines(cityName))
	end, getCounts = function(cityName)
		return (_G.GetFireEngineCounts and _G.GetFireEngineCounts(cityName)) or nil
	end },
	{ level = 3, id = "Defense", icon = "🛡️", label = "Defense Barricades eliminated", isComplete = function(cityName)
		-- Nutzt _G.AreAllBarricadesDefeated statt nur "keine aktuell aktiven Barrikaden"
		-- -- Barrikaden erscheinen gestaffelt (erst sobald ein Flankengebäude unter 50%
		-- HP fällt), daher könnten sonst noch nie ausgelöste Cluster übersehen werden
		-- (z.B. 1 von 3 möglichen Clustern besiegt, aber 2 wurden nie ausgelöst -- das
		-- zählt NICHT als vollständig erledigt).
		return (_G.AreAllBarricadesDefeated and _G.AreAllBarricadesDefeated(cityName)) or false
	end, getCounts = function(cityName)
		return (_G.GetBarricadeCounts and _G.GetBarricadeCounts(cityName)) or nil
	end },
	{ level = 4, id = "Military", icon = "🎖️", label = "Military eliminated", isComplete = function(cityName)
		-- Nur als erledigt werten, wenn tatsächlich mindestens eine Einheit in diesem
		-- Zyklus gespawnt wurde (analog zur Barrikaden-Prüfung) -- verhindert, dass der
		-- Task fälschlich als erledigt gilt, falls das Spawnen selbst fehlschlägt.
		local counts = _G.GetMilitaryUnitCounts and _G.GetMilitaryUnitCounts(cityName)
		if not counts or counts.total <= 0 then
			return false
		end
		return not (_G.HasActiveMilitaryUnits and _G.HasActiveMilitaryUnits(cityName))
	end, getCounts = function(cityName)
		return (_G.GetMilitaryUnitCounts and _G.GetMilitaryUnitCounts(cityName)) or nil
	end },
	{ level = 5, id = "Titan", icon = "🤖", label = "Guardian eliminated", isComplete = function(cityName)
		return not (_G.HasActiveGuardian and _G.HasActiveGuardian(cityName))
	end },
	-- Kein getCounts für Guardian -- ein einzelner Boss hat kein sinnvolles "X von Y".
}

-- Fürs Client-HUD bereitgestellte Werte pro Stadt+Aufgabe, plus CITY-BROKEN-Status.
local taskCompleteValues = {} -- [cityName][taskId] = BoolValue
local taskApplicableValues = {} -- [cityName][taskId] = BoolValue -- kennt die Stadt diese Stufe überhaupt?
local taskProgressValues = {} -- [cityName][taskId] = StringValue -- "1/2" fürs Panel
local cityBrokenValues = {} -- [cityName] = BoolValue
local cityBrokenEndsAtValues = {} -- [cityName] = NumberValue

for _, cityName in ipairs(CityAlertConfig.CityOrder) do
	taskCompleteValues[cityName] = {}
	taskApplicableValues[cityName] = {}
	taskProgressValues[cityName] = {}
	for _, task in ipairs(TASK_DEFINITIONS) do
		local completeValue = Instance.new("BoolValue")
		completeValue.Name = cityName .. "Task_" .. task.id .. "_Complete"
		completeValue.Value = false
		completeValue.Parent = cityAlertFolder
		taskCompleteValues[cityName][task.id] = completeValue

		local applicableValue = Instance.new("BoolValue")
		applicableValue.Name = cityName .. "Task_" .. task.id .. "_Applicable"
		applicableValue.Value = false -- wird dynamisch in der laufenden Prüfung aktualisiert (siehe unten), nicht mehr statisch beim Start
		applicableValue.Parent = cityAlertFolder
		taskApplicableValues[cityName][task.id] = applicableValue

		-- Fortschritts-Anzeige (z.B. "1/2") -- nur für Aufgaben mit getCounts (Guardian
		-- hat keine, bleibt leer).
		if task.getCounts then
			local progressValue = Instance.new("StringValue")
			progressValue.Name = cityName .. "Task_" .. task.id .. "_Progress"
			progressValue.Value = ""
			progressValue.Parent = cityAlertFolder
			taskProgressValues[cityName][task.id] = progressValue
		end
	end

	local brokenValue = Instance.new("BoolValue")
	brokenValue.Name = cityName .. "CityBroken"
	brokenValue.Value = false
	brokenValue.Parent = cityAlertFolder
	cityBrokenValues[cityName] = brokenValue

	local endsAtValue = Instance.new("NumberValue")
	endsAtValue.Name = cityName .. "CityBrokenEndsAt"
	endsAtValue.Value = 0
	endsAtValue.Parent = cityAlertFolder
	cityBrokenEndsAtValues[cityName] = endsAtValue
end

-- [cityName] = true, solange das Freie-Zerstörung-Fenster aktiv ist -- verhindert
-- doppeltes Auslösen, während der Timer bereits läuft.
local cityBrokenActive = {}

local function triggerCityBroken(cityName)
	if cityBrokenActive[cityName] then
		return
	end
	cityBrokenActive[cityName] = true

	-- Lebensstatistik: wie die Alarmstufen ein Stadt-Ereignis ohne einzelnen Verursacher
	-- (triggerCityBroken kennt keinen Spieler) -- geht an alle, die gerade dort sind.
	if _G.RecordStatForCity then
		_G.RecordStatForCity(cityName, "CityBroken")
		_G.RecordStatForCity(cityName, "CityBroken." .. cityName)
	end

	local endsAt = os.clock() + FREE_DESTRUCTION_DURATION
	cityBrokenValues[cityName].Value = true
	cityBrokenEndsAtValues[cityName].Value = endsAt

	print("[CityBrokenService] '" .. cityName .. "' ist CITY BROKEN -- " .. FREE_DESTRUCTION_DURATION .. "s freie Zerstörung.")

	task.delay(FREE_DESTRUCTION_DURATION, function()
		cityBrokenValues[cityName].Value = false
		cityBrokenEndsAtValues[cityName].Value = 0
		cityBrokenActive[cityName] = false

		-- Stadt beruhigt sich komplett -- Alert fällt sofort auf 0 zurück.
		if _G.ResetCityAlert then
			_G.ResetCityAlert(cityName)
		end
		print("[CityBrokenService] '" .. cityName .. "': Freie-Zerstörung-Fenster beendet, Stadt beruhigt sich.")
	end)
end

-- ===== Laufende Prüfung: pro Stadt alle anwendbaren Aufgaben checken. Läuft nur alle
-- 0.5s (kein Grund für jeden Frame -- Aufgaben-Status ändert sich nicht ständig). =====
local CHECK_INTERVAL = 0.5
local lastCheckAt = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastCheckAt < CHECK_INTERVAL then
		return
	end
	lastCheckAt = now

	for _, cityName in ipairs(CityAlertConfig.CityOrder) do
		if not cityBrokenActive[cityName] then
			local config = CityAlertConfig.GetCityConfig(cityName)
			local maxLevel = config.MaxAlertLevel or 5
			local currentLevel = _G.GetCityAlertLevel and _G.GetCityAlertLevel(cityName)

			local allApplicableTasksComplete = true
			for _, task in ipairs(TASK_DEFINITIONS) do
				-- WICHTIG: "anwendbar" heisst jetzt "die Stadt hat diese Stufe TATSÄCHLICH
				-- schon erreicht" (currentLevel >= task.level) -- nicht mehr nur "könnte sie
				-- theoretisch erreichen" (maxLevel >= task.level). Sonst würde z.B. die
				-- Barrikaden-Aufgabe schon bei Level 2 auftauchen, obwohl noch gar keine
				-- Barrikaden existieren.
				local hasReachedTaskLevel = currentLevel ~= nil and currentLevel >= task.level
				taskApplicableValues[cityName][task.id].Value = hasReachedTaskLevel

				if task.level <= maxLevel then
					-- "Erledigt" nur zählbar, wenn die Stadt die Stufe auch wirklich erreicht
					-- hat -- sonst würde "keine aktiven Barrikaden" (weil nie gespawnt) fälschlich
					-- als "besiegt" durchgehen.
					local isComplete = hasReachedTaskLevel and task.isComplete(cityName)
					taskCompleteValues[cityName][task.id].Value = isComplete
					if not isComplete then
						allApplicableTasksComplete = false
					end

					-- Fortschritts-Anzeige ("1/2") aktualisieren, sobald die Stufe erreicht ist.
					if task.getCounts and taskProgressValues[cityName][task.id] then
						if hasReachedTaskLevel then
							local counts = task.getCounts(cityName)
							if counts and counts.total > 0 then
								taskProgressValues[cityName][task.id].Value = counts.destroyed .. "/" .. counts.total
							else
								taskProgressValues[cityName][task.id].Value = ""
							end
						else
							taskProgressValues[cityName][task.id].Value = ""
						end
					end
				end
			end

			-- Nur auslösen, wenn die Stadt WIRKLICH auf ihrer höchsten Stufe steht --
			-- sonst würde z.B. Village (Deckel 3) schon bei Level 1 "fertig" wirken, weil
			-- es dort schlicht noch keine Military-/Titan-Aufgabe zu erledigen gibt.
			if currentLevel == maxLevel and allApplicableTasksComplete then
				triggerCityBroken(cityName)
			end
		end
	end
end)

print("[Kaiju] CityBrokenService bereit -- CITY BROKEN nach " .. FREE_DESTRUCTION_DURATION .. "s freier Zerstörung.")