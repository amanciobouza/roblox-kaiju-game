-- VERSION: 2026-08-26 #2
-- FEATURE: ReleaseHealthFloor ergänzt -- explizite, sofortige Freigabe des Health-Schutzes
-- Ort in Studio: ServerScriptService
--
-- Zwei zusammengehörige Mechaniken für den Playable Prologue ("The Fall"):
--
--   1) Nachschub-Welle: ab Alert 4 (Militär-Ankunft) rückt kontinuierlich WEITERE
--      Verstärkung nach -- unabhängig vom normalen, einmaligen Level-4-Spawn-Schub des
--      regulären Alert-Systems. Das Intervall zwischen den Wellen wird mit der Zeit
--      IMMER KÜRZER, wodurch der Spieler zunehmend von der schieren Menge überwältigt
--      wird ("Escalation" + "Guardian"-Phasen im Prolog-Konzept).
--
--   2) Health-Untergrenze: damit der Spieler durch diese Nachschub-Welle nicht bereits
--      VOR der eigentlichen Guardian-Phase (Alert 5) stirbt (was dem geskripteten
--      Erzähl-Ablauf widersprechen würde -- "The Fall" soll erst bei/nach dem Guardian
--      passieren), kann die Health während Alert 1-4 nicht unter HEALTH_FLOOR_RATIO
--      fallen. Erst mit Alert 5 wird dieser Schutz aufgehoben.
--
-- Nutzt _G.SpawnReinforcementUnit (siehe MilitaryService.lua) für die eigentlichen
-- Einheiten -- dadurch profitieren Nachschub-Einheiten automatisch von der bestehenden
-- Bewegungs-/Kampf-KI, ohne dass diese Logik hier dupliziert werden muss.

local Players = game:GetService("Players")

local PrologueReinforcementService = {}

-- ===== Konfiguration =====
local REINFORCEMENT_UNIT_TYPES = { "Tank", "Helicopter", "RocketLauncher" }
local INITIAL_INTERVAL_SECONDS = 20 -- Zeit zwischen Nachschub-Wellen zu Beginn (Alert 4)
local MIN_INTERVAL_SECONDS = 6 -- kürzestmögliches Intervall (gegen Ende, maximale Bedrohung)
local INTERVAL_SHRINK_PER_WAVE = 1.5 -- wie viel sich das Intervall pro Welle verkürzt

local HEALTH_FLOOR_RATIO = 0.2 -- Spieler kann während Alert 1-4 nicht unter 20% Health fallen
local HEALTH_FLOOR_ACTIVE_UNTIL_ALERT_LEVEL = 5 -- ab dieser Stufe wird der Schutz aufgehoben

-- [cityName] = true, solange die Nachschub-Welle für diese Stadt aktiv läuft. Verhindert
-- doppelte, parallel laufende Wellen-Loops für dieselbe Stadt.
local activeReinforcementLoops = {}

-- [player] = RBXScriptConnection der aktiven Health-Floor-Verbindung -- ermöglicht eine
-- EXPLIZITE, sofortige Freigabe von aussen (siehe ReleaseHealthFloor), statt sich
-- ausschliesslich auf den indirekten Alert-Level-Check innerhalb des Listeners selbst zu
-- verlassen (der nur bei einer tatsächlichen HealthChanged-Änderung erneut prüft).
local activeHealthFloorConnections = {}

-- ===== Nachschub-Welle =====
local function startReinforcementWave(cityName)
	if activeReinforcementLoops[cityName] then
		return -- läuft schon
	end
	activeReinforcementLoops[cityName] = true

	task.spawn(function()
		local interval = INITIAL_INTERVAL_SECONDS
		local waveIndex = 0

		while activeReinforcementLoops[cityName] do
			task.wait(interval)
			if not activeReinforcementLoops[cityName] then
				break -- wurde während des Wartens gestoppt (z.B. Guardian besiegt/Prolog endet)
			end

			waveIndex += 1
			local unitType = REINFORCEMENT_UNIT_TYPES[((waveIndex - 1) % #REINFORCEMENT_UNIT_TYPES) + 1]
			if _G.SpawnReinforcementUnit then
				local unit = _G.SpawnReinforcementUnit(cityName, unitType)
				if unit then
					print("[PrologueReinforcementService] Nachschub-Welle #" .. waveIndex .. " für '" .. cityName .. "': " .. unitType .. " (nächstes Intervall: " .. math.floor(interval * 10) / 10 .. "s)")
				end
			end

			interval = math.max(MIN_INTERVAL_SECONDS, interval - INTERVAL_SHRINK_PER_WAVE)
		end
	end)
end

-- Startet die Nachschub-Welle für eine Stadt -- aufzurufen, sobald die Prolog-Stadt Alert
-- 4 erreicht (z.B. über einen _G.CityAlertLevelChanged-Listener im Prolog-Orchestrierungs-
-- Script). Sicher mehrfach aufrufbar (läuft dann nur einmal tatsächlich).
function PrologueReinforcementService.Start(cityName)
	startReinforcementWave(cityName)
end

-- Stoppt die Nachschub-Welle wieder -- aufzurufen, sobald der Prolog-Kampf endet (Guardian
-- besiegt den Spieler, "The Fall" beginnt) oder der Prolog aus einem anderen Grund
-- abgebrochen wird.
function PrologueReinforcementService.Stop(cityName)
	activeReinforcementLoops[cityName] = nil
end

-- ===== Health-Untergrenze =====
-- Hält die Health eines Prolog-Spielers während Alert 1-4 bei mindestens
-- HEALTH_FLOOR_RATIO -- verhindert einen zu frühen, ungewollten Tod durch die
-- Nachschub-Welle, bevor die eigentliche, geskriptete "Fall"-Sequenz (Guardian-Phase,
-- Alert 5) überhaupt beginnt. Läuft pro Charakter, bis der Schutz durch Erreichen von
-- Alert 5 aufgehoben wird oder der Charakter stirbt/wechselt.
local function protectPlayerHealthFloor(player, character, cityName)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local connection
	connection = humanoid.HealthChanged:Connect(function(health)
		if not player:GetAttribute("IsInPrologue") then
			connection:Disconnect()
			activeHealthFloorConnections[player] = nil
			return
		end

		local alertLevel = _G.GetCityAlertLevel and _G.GetCityAlertLevel(cityName)
		if alertLevel and alertLevel >= HEALTH_FLOOR_ACTIVE_UNTIL_ALERT_LEVEL then
			-- Guardian-Phase erreicht -- Schutz endgültig aufheben, echter Tod jetzt möglich.
			connection:Disconnect()
			activeHealthFloorConnections[player] = nil
			return
		end

		local floor = humanoid.MaxHealth * HEALTH_FLOOR_RATIO
		if health < floor then
			humanoid.Health = floor
		end
	end)
	activeHealthFloorConnections[player] = connection

	humanoid.Died:Connect(function()
		connection:Disconnect()
		activeHealthFloorConnections[player] = nil
	end)
end

-- Hebt die Health-Untergrenze für einen Spieler EXPLIZIT und SOFORT auf -- unabhängig vom
-- indirekten Alert-Level-Check innerhalb des HealthChanged-Listeners (der erst bei der
-- NÄCHSTEN tatsächlichen Health-Änderung erneut geprüft würde). Aufzurufen, sobald "The
-- Fall" beginnt (siehe PrologueOrchestrator.lua -- triggerTheFall), damit die
-- geskriptete Health-Abnahme dort garantiert nicht durch diesen Schutz konterkariert wird.
function PrologueReinforcementService.ReleaseHealthFloor(player)
	local connection = activeHealthFloorConnections[player]
	if connection then
		connection:Disconnect()
		activeHealthFloorConnections[player] = nil
	end
end

-- Aktiviert die Health-Untergrenze für einen Spieler -- aufzurufen, sobald der Prolog für
-- diesen Spieler beginnt (nach dem Setzen von IsInPrologue=true).
function PrologueReinforcementService.ProtectPlayer(player, cityName)
	if player.Character then
		protectPlayerHealthFloor(player, player.Character, cityName)
	end
	player.CharacterAdded:Connect(function(character)
		if player:GetAttribute("IsInPrologue") then
			protectPlayerHealthFloor(player, character, cityName)
		end
	end)
end

return PrologueReinforcementService