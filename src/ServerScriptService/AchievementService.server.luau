-- VERSION: 2026-08-25 #4
-- FEATURE: IsInPrologue-Isolation in incrementCounter (Sicherheitsnetz)
-- Ort in Studio: ServerScriptService
--
-- Trackt Fortschritt (Zähler + Flags) und schaltet Achievements frei. Jedes Achievement
-- wird als Spieler-Attribut gespeichert ("Achievement_<id>" = true, sobald freigeschaltet)
-- -- der Client kann darüber direkt live reagieren (Toast-Benachrichtigung, Panel-Update).
--
-- Zähler-Attribute (z.B. "Counter_BuildingsDestroyed") laufen separat, damit auch der
-- FORTSCHRITT (nicht nur "geschafft/nicht geschafft") anzeigbar ist.
--
-- Persistenz: läuft NICHT über eine eigene DataStore-Verbindung, sondern über zwei
-- exponierte Funktionen, die PlayerSetup.lua beim Laden/Speichern des allgemeinen
-- Spielstands mit aufruft (siehe _G.GetAchievementSaveData / _G.LoadAchievementSaveData).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementsConfig = require(ReplicatedStorage:WaitForChild("AchievementsConfig"))

local achievementUnlockedEvent = Instance.new("RemoteEvent")
achievementUnlockedEvent.Name = "AchievementUnlockedEvent"
achievementUnlockedEvent.Parent = ReplicatedStorage

-- ===== Grundfunktionen =====
local function isUnlocked(player, achievementId)
	return player:GetAttribute("Achievement_" .. achievementId) == true
end

local function unlockAchievement(player, achievementId)
	if isUnlocked(player, achievementId) then
		return
	end
	local achievement = AchievementsConfig.ById[achievementId]
	if not achievement then
		warn("[AchievementService] Unbekannte Achievement-ID:", achievementId)
		return
	end
	player:SetAttribute("Achievement_" .. achievementId, true)
	achievementUnlockedEvent:FireClient(player, achievementId)
end
_G.UnlockAchievement = unlockAchievement

-- Setzt ALLE Achievements (freigeschaltet + Zähler-Fortschritt) für einen Spieler zurück
-- -- fürs Debug-Reset-Tool (siehe PlayerSetup.lua, ResetPlayerDataEvent).
_G.ResetPlayerAchievements = function(player)
	for _, achievement in ipairs(AchievementsConfig.List) do
		player:SetAttribute("Achievement_" .. achievement.id, nil)
		if achievement.type == "counter" then
			player:SetAttribute("Counter_" .. (achievement.counterKey or achievement.id), nil)
		end
	end
	-- Sonder-Zähler, die keinem einzelnen Achievement 1:1 entsprechen (z.B. Serientäter
	-- läuft über eine eigene lokale Tabelle statt eines counterKey), ebenfalls zurücksetzen.
	player:SetAttribute("Counter_SerialOffender", nil)
	player:SetAttribute("Counter_SerialOffender", nil)
	-- Lokale (nicht-Attribut-basierte) Zustandstabelle für "Serientäter" wird weiter
	-- unten in dieser Datei zusätzlich geleert (siehe reachedLevel5Cities), da diese
	-- Variable an dieser Stelle im Script noch nicht deklariert ist.
end

-- Erhöht einen Zähler um "amount" und schaltet automatisch frei, sobald der Threshold
-- des zugehörigen Achievements erreicht ist.
local function incrementCounter(player, counterName, amount, achievementId)
	-- Prolog-Isolation (zusätzliches Sicherheitsnetz): der Prolog-Kaiju ist ein
	-- temporärer, vom echten Fortschritt komplett getrennter Zustand -- keine echten
	-- Achievement-Fortschritte während des Prologs, unabhängig von der Quelle.
	if player:GetAttribute("IsInPrologue") == true then
		return player:GetAttribute("Counter_" .. counterName) or 0
	end

	amount = amount or 1
	local current = player:GetAttribute("Counter_" .. counterName) or 0
	local newValue = current + amount
	player:SetAttribute("Counter_" .. counterName, newValue)

	if achievementId then
		local achievement = AchievementsConfig.ById[achievementId]
		if achievement and achievement.threshold and newValue >= achievement.threshold then
			unlockAchievement(player, achievementId)
		end
	end
	return newValue
end
_G.IncrementAchievementCounter = incrementCounter

-- ===== Persistenz: von PlayerSetup.lua beim Laden/Speichern aufgerufen. =====
_G.GetAchievementSaveData = function(player)
	local unlocked = {}
	local counters = {}
	local savedCounterKeys = {} -- verhindert doppeltes Speichern, falls mehrere Achievements sich einen counterKey teilen
	for _, achievement in ipairs(AchievementsConfig.List) do
		if isUnlocked(player, achievement.id) then
			unlocked[achievement.id] = true
		end
		if achievement.type == "counter" then
			local counterKey = achievement.counterKey or achievement.id
			if not savedCounterKeys[counterKey] then
				local value = player:GetAttribute("Counter_" .. counterKey)
				if value then
					counters[counterKey] = value
				end
				savedCounterKeys[counterKey] = true
			end
		end
	end
	return { unlocked = unlocked, counters = counters }
end

_G.LoadAchievementSaveData = function(player, saveData)
	if not saveData then
		return
	end
	if saveData.unlocked then
		for achievementId in pairs(saveData.unlocked) do
			player:SetAttribute("Achievement_" .. achievementId, true)
		end
	end
	if saveData.counters then
		for counterKey, value in pairs(saveData.counters) do
			player:SetAttribute("Counter_" .. counterKey, value)
		end
	end
end

-- ===== Hooks: Zerstörung =====
_G.OnBuildingDestroyedForAchievements = function(player)
	if not player then
		return
	end
	local total = incrementCounter(player, "BuildingsDestroyed", 1)
	for _, id in ipairs({ "FirstCracks", "WreckingBall", "Ravager", "Apocalypse" }) do
		local achievement = AchievementsConfig.ById[id]
		if achievement and total >= achievement.threshold then
			unlockAchievement(player, id)
		end
	end
end

-- ===== Hooks: Alert-Eskalation =====
local reachedLevel5Cities = {} -- [player] = { [cityName] = true }

-- Reset-Funktion um die Bereinigung dieser lokalen (nicht-Attribut-basierten) Tabelle
-- erweitern -- konnte nicht direkt in der ursprünglichen Definition weiter oben stehen,
-- da reachedLevel5Cities dort noch nicht deklariert war.
local baseResetPlayerAchievements = _G.ResetPlayerAchievements
_G.ResetPlayerAchievements = function(player)
	if baseResetPlayerAchievements then
		baseResetPlayerAchievements(player)
	end
	reachedLevel5Cities[player] = nil
end

local function onCityAlertLevelChanged(cityName, newLevel, oldLevel)
	if newLevel < oldLevel then
		return -- nur beim AUFSTIEG relevant
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName then
			if newLevel >= 1 then
				unlockAchievement(player, "Noticed")
			end
			if newLevel >= 5 then
				reachedLevel5Cities[player] = reachedLevel5Cities[player] or {}
				if not reachedLevel5Cities[player][cityName] then
					reachedLevel5Cities[player][cityName] = true
					local count = 0
					for _ in pairs(reachedLevel5Cities[player]) do
						count += 1
					end
					player:SetAttribute("Counter_SerialOffender", count)
					if count >= 3 then
						unlockAchievement(player, "SerialOffender")
					end
				end
			end
		end
	end
end

task.spawn(function()
	local attempts = 0
	while not _G.CityAlertLevelChanged and attempts < 100 do
		task.wait(0.1)
		attempts += 1
	end
	if _G.CityAlertLevelChanged then
		_G.CityAlertLevelChanged.Event:Connect(onCityAlertLevelChanged)
	else
		warn("[AchievementService] _G.CityAlertLevelChanged nie gefunden -- Alert-Achievements bleiben wirkungslos.")
	end
end)

-- "Erste X besiegt"-Achievements: nutzen jeweils einen einmaligen Zähler pro Spieler
-- (kein direktes Event vorhanden -- werden von den jeweiligen Kampf-Scripts über diese
-- Funktionen aufgerufen, siehe unten in FireEngineController.lua/
-- BarricadeClusterService.lua/MilitaryService.lua/CityDefenderService.lua).
_G.OnFireEngineDestroyedForAchievements = function(player)
	if player then
		unlockAchievement(player, "EmergencyDefeated")
	end
end
_G.OnBarricadeDestroyedForAchievements = function(player)
	if player then
		unlockAchievement(player, "BreakthroughAchieved")
	end
end
_G.OnMilitaryUnitDestroyedForAchievements = function(player)
	if player then
		unlockAchievement(player, "WarZone")
	end
end
_G.OnGuardianDefeatedForAchievements = function(player)
	if player then
		unlockAchievement(player, "GuardianSlayer")
	end
end

-- ===== Hooks: Berserker & Meltdown =====
local wasMeltdown = {} -- [player] = bool, für den Übergangs-basierten "Feuerprobe"-Zähler

Players.PlayerAdded:Connect(function(player)
	player:GetAttributeChangedSignal("BerserkActive"):Connect(function()
		if player:GetAttribute("BerserkActive") then
			unlockAchievement(player, "LossOfControl")
		end
	end)
	player:GetAttributeChangedSignal("Heat"):Connect(function()
		local heat = player:GetAttribute("Heat") or 0
		if heat >= 100 then
			unlockAchievement(player, "CoreMeltdown")
		end
		if heat >= 110 then
			unlockAchievement(player, "AtTheLimit")
		end

		local isMeltdownNow = heat >= 100
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if wasMeltdown[player] and not isMeltdownNow and humanoid and humanoid.Health > 0 then
			incrementCounter(player, "TrialByFire", 1, "TrialByFire")
		end
		wasMeltdown[player] = isMeltdownNow
	end)

	-- ===== Hooks: Fortschritt =====
	player:GetAttributeChangedSignal("Level"):Connect(function()
		local level = player:GetAttribute("Level") or 0
		if level >= 10 then
			unlockAchievement(player, "FirstSteps")
		end
		if level >= 25 then
			unlockAchievement(player, "TitanLevel")
		end
	end)

	local function checkFullyTrained()
		local armCap = player:GetAttribute("ArmStatCap")
		local legCap = player:GetAttribute("LegStatCap")
		local bodyCap = player:GetAttribute("StatCap")
		local arm = player:FindFirstChild("ArmPower")
		local leg = player:FindFirstChild("LegPower")
		local body = player:FindFirstChild("BodyPower")
		if armCap and legCap and bodyCap and arm and leg and body
			and arm.Value >= armCap and leg.Value >= legCap and body.Value >= bodyCap then
			unlockAchievement(player, "FullyTrained")
		end
	end
	task.spawn(function()
		local arm = player:WaitForChild("ArmPower", 10)
		local leg = player:WaitForChild("LegPower", 10)
		local body = player:WaitForChild("BodyPower", 10)
		if arm and leg and body then
			arm:GetPropertyChangedSignal("Value"):Connect(checkFullyTrained)
			leg:GetPropertyChangedSignal("Value"):Connect(checkFullyTrained)
			body:GetPropertyChangedSignal("Value"):Connect(checkFullyTrained)
		end
	end)

	-- ===== Hooks: Charaktere (Kaiju ist aktuell Standard-/einzige spielbare Fraktion) =====
	unlockAchievement(player, "KaijuAwakens")

	local function checkFactionUnlocks()
		if _G.GetFactionUnlockStatus then
			if _G.GetFactionUnlockStatus(player, "Jaeger") then
				unlockAchievement(player, "JaegerUnlocked")
			end
			if _G.GetFactionUnlockStatus(player, "Ronin") then
				unlockAchievement(player, "RoninUnlocked")
			end
			if isUnlocked(player, "JaegerUnlocked") and isUnlocked(player, "RoninUnlocked") then
				unlockAchievement(player, "Trinity")
			end
		end
	end
	task.spawn(function()
		while player.Parent do
			checkFactionUnlocks()
			task.wait(3)
		end
	end)
end)

-- ===== Hooks: Spezialangriffe =====
_G.OnFocusAttackUsedForAchievements = function(player)
	if player then
		incrementCounter(player, "Focused", 1, "Focused")
	end
end
_G.OnAreaAttackUsedForAchievements = function(player)
	if player then
		incrementCounter(player, "FieldOfFire", 1, "FieldOfFire")
	end
end
_G.OnSpecialEnergyGainedForAchievements = function(player, amount)
	if player and amount and amount > 0 then
		incrementCounter(player, "EnergyMaster", amount, "EnergyMaster")
	end
end

print("[Kaiju] AchievementService bereit -- " .. #AchievementsConfig.List .. " Achievements definiert.")