-- Script: ShowdownService
-- Ort in Studio: ServerScriptService
--
-- Der Showdown: der Zweikampf zwischen Spieler und Guardian, den das Spiel filmisch
-- inszeniert, während der Spieler weiterkämpft.
--
-- Die Absicht steht in ReplicatedStorage.Specs.ShowdownSpec, die Zahlen in
-- ShowdownConfig. Hier steht nur, wie es abläuft.
--
-- ===== Was hier entschieden wird und was nicht =====
-- Der Server entscheidet, OB ein Showdown läuft, für wen, und wann ein Angriffs-Shot
-- gezeigt werden darf. Er weiss als Einziger, wer wem Schaden zugefügt hat.
-- Die Kamera, der Filmstreifen und die Steuerungsumstellung sind reine Anzeige und
-- gehören dem Client (ShowdownClient).
--
-- ===== Jeder Spieler hat seinen eigenen =====
-- Der Guardian führt EINEN Kampf, aber jeder Beteiligte hat seine eigene Sitzung mit
-- eigener Mindestdauer und eigenem Aufgeben-Knopf. Wer als Zweiter dazustösst, soll seine
-- vollen fünfzehn Sekunden bekommen und nicht in eine Sequenz fallen, die drei Sekunden
-- später endet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local ShowdownConfig = require(ReplicatedStorage:WaitForChild("ShowdownConfig"))

local ShowdownStateEvent = RemoteEventUtils.GetOrCreate("ShowdownStateEvent")
local ShowdownShotEvent = RemoteEventUtils.GetOrCreate("ShowdownShotEvent")
local ShowdownGiveUpEvent = RemoteEventUtils.GetOrCreate("ShowdownGiveUpEvent")
local DebugShowdownEvent = RemoteEventUtils.GetOrCreate("DebugShowdownEvent")

-- [player] = { cityName, startedAt, minimumDuration, lastShotAt, lastShotPriority }
local sessions = {}

-- Wer hat wen wann getroffen. Beides nötig, denn erst die GEGENSEITIGKEIT macht aus einem
-- Überfall einen Kampf.
local playerHitGuardianAt = {} -- [player] = { [cityName] = os.clock() }
local guardianHitPlayerAt = {} -- [player] = os.clock()

-- [player] = { [cityName] = Zeitpunkt, ab dem wieder gestartet werden darf }
local reentryLockUntil = {}

-- Debug-Schalter: verkürzt die Mindestdauer, damit die Ausstiege durchgespielt werden
-- können, ohne jedes Mal fünfzehn Sekunden zu warten.
local debugShortDuration = false

local function clockNow()
	return os.clock()
end

local function nested(store, player)
	local entry = store[player]
	if not entry then
		entry = {}
		store[player] = entry
	end
	return entry
end

-- ===== Ausschlüsse =====
-- Drei Situationen, in denen die Bedingung erfüllt sein kann, ein Showdown aber falsch
-- wäre. Siehe showdown.excluded-situations in der Spec.
local function isBlocked(player, cityName)
	-- Im Prolog: der führt eigene Kamerafahrten UND fügt dem Guardian selbst Schaden zu.
	-- Zwei Kamerasysteme gegeneinander laufen zu lassen ist der sicherste Weg zu genau
	-- den Flacker- und Sprungfehlern, vor denen CLAUDE.md warnt.
	if player:GetAttribute("IsInPrologue") == true then
		return "Prolog"
	end

	-- Gegen einen besiegten Guardian: er bleibt liegen, bis die Stadt bricht. Schaden auf
	-- einen Liegenden soll nichts auslösen.
	if not (_G.HasActiveGuardian and _G.HasActiveGuardian(cityName)) then
		return "kein lebender Guardian"
	end

	-- Während CITY BROKEN: die 75 Sekunden freie Zerstörung sind ausdrücklich die
	-- Belohnungsphase ohne Eskalation.
	local cityAlertFolder = ReplicatedStorage:FindFirstChild("CityAlert")
	local broken = cityAlertFolder and cityAlertFolder:FindFirstChild(cityName .. "CityBroken")
	if broken and broken.Value == true then
		return "CITY BROKEN"
	end

	local lock = reentryLockUntil[player] and reentryLockUntil[player][cityName]
	if lock and clockNow() < lock then
		return string.format("Sperre nach Aufgeben (%.0fs)", lock - clockNow())
	end

	return nil
end

-- ===== Starten und Beenden =====

local function startShowdown(player, cityName)
	if sessions[player] then
		return
	end
	local blocked = isBlocked(player, cityName)
	if blocked then
		print(string.format("[Kaiju-Debug] Showdown für %s nicht gestartet -- %s.", player.Name, blocked))
		return
	end

	local guardianModel = _G.GetGuardianModel and _G.GetGuardianModel(cityName)
	if not guardianModel then
		return
	end

	local minimumDuration = debugShortDuration
		and ShowdownConfig.DebugMinimumDuration
		or ShowdownConfig.MinimumDuration

	sessions[player] = {
		cityName = cityName,
		startedAt = clockNow(),
		minimumDuration = minimumDuration,
		lastShotAt = 0,
		lastShotPriority = 0,
	}

	if _G.RecordStat then
		-- Begonnene UND bestandene werden gezählt; der Unterschied erzählt, wie oft
		-- jemand aufgegeben hat.
		_G.RecordStat(player, "ShowdownsStarted")
	end

	ShowdownStateEvent:FireClient(player, true, {
		cityName = cityName,
		guardian = guardianModel,
		minimumDuration = minimumDuration,
	})

	print(string.format(
		"[Kaiju-Debug] Showdown gestartet: %s gegen Guardian %s (Mindestdauer %.0fs).",
		player.Name, cityName, minimumDuration))
end

local function endShowdown(player, reason)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil

	if reason == "Aufgegeben" then
		nested(reentryLockUntil, player)[session.cityName] =
			clockNow() + ShowdownConfig.ReentryLockAfterGiveUp
	end

	if reason == "Guardian besiegt" and _G.RecordStat then
		_G.RecordStat(player, "ShowdownsWon")
	end

	ShowdownStateEvent:FireClient(player, false, {
		reason = reason,
		victory = reason == "Guardian besiegt",
	})

	print(string.format(
		"[Kaiju-Debug] Showdown beendet: %s nach %.1fs -- %s.",
		player.Name, clockNow() - session.startedAt, reason))
end

-- ===== Meldestellen für die anderen Dienste =====

-- Wird bei JEDEM Treffer zwischen Spieler und Guardian gerufen. `kind` ist
-- "PlayerToGuardian" oder "GuardianToPlayer".
--
-- Erst wenn beide Richtungen innerhalb des Zeitfensters vorliegen, startet der Showdown.
-- "Gegenseitig" ist genau das, was einen Kampf von einem Überfall unterscheidet.
_G.NotifyShowdownDamage = function(kind, player, cityName)
	if not player or not player.Parent or not cityName then
		return
	end
	local now = clockNow()

	if kind == "PlayerToGuardian" then
		nested(playerHitGuardianAt, player)[cityName] = now
	elseif kind == "GuardianToPlayer" then
		guardianHitPlayerAt[player] = now
	else
		return
	end

	if sessions[player] then
		return -- läuft schon
	end

	local playerHit = playerHitGuardianAt[player] and playerHitGuardianAt[player][cityName]
	local guardianHit = guardianHitPlayerAt[player]
	if not playerHit or not guardianHit then
		return
	end
	if now - playerHit <= ShowdownConfig.TriggerWindow
		and now - guardianHit <= ShowdownConfig.TriggerWindow then
		startShowdown(player, cityName)
	end
end

-- Meldet einen Angriff, der einen Shot verdient. `shotName` ist ein Schlüssel aus
-- ShowdownConfig.Shots.
--
-- `target` ist bei Guardian-Angriffen der angegriffene Spieler und bei Spielerangriffen
-- der Spieler selbst -- der Shot geht immer nur an den, dessen Showdown läuft.
_G.NotifyShowdownAttack = function(shotName, player, cityName)
	local shot = ShowdownConfig.Shots[shotName]
	if not shot or not player then
		return
	end
	local session = sessions[player]
	if not session or session.cityName ~= cityName then
		return
	end

	local now = clockNow()
	local priority = ShowdownConfig.ShotPriority[shot.source] or 0

	-- Mindestabstand: der Guardian schlägt alle drei Sekunden zu; bekäme jeder Angriff
	-- einen Shot, würde die Kamera im Sekundentakt schneiden.
	--
	-- Ein Angriff mit HÖHEREM Vorrang darf einen laufenden Shot trotzdem nicht ablösen --
	-- der Vorrang entscheidet nur bei Gleichzeitigkeit, nicht rückwirkend.
	if now - session.lastShotAt < ShowdownConfig.ShotMinimumGap then
		return
	end

	session.lastShotAt = now
	session.lastShotPriority = priority

	local guardianModel = _G.GetGuardianModel and _G.GetGuardianModel(cityName)
	ShowdownShotEvent:FireClient(player, shotName, guardianModel)

	print(string.format("[Kaiju-Debug] Showdown-Shot für %s: %s.", player.Name, shotName))
end

_G.IsShowdownActive = function(player)
	return sessions[player] ~= nil
end

_G.EndShowdown = function(player, reason)
	endShowdown(player, reason or "beendet")
end

-- Alle Sitzungen einer Stadt beenden -- gerufen, wenn der Guardian fällt.
_G.EndShowdownsForCity = function(cityName, reason)
	for player, session in pairs(sessions) do
		if session.cityName == cityName then
			endShowdown(player, reason or "beendet")
		end
	end
end

-- ===== Aufgeben =====

ShowdownGiveUpEvent.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session then
		return
	end
	-- Die Mindestdauer wird SERVERSEITIG geprüft. Der Knopf erscheint clientseitig erst
	-- nach Ablauf, aber ein Client, der das Ereignis früher feuert, darf damit nicht
	-- durchkommen.
	if clockNow() - session.startedAt < session.minimumDuration then
		return
	end
	endShowdown(player, "Aufgegeben")
end)

-- ===== Laufende Überwachung =====
-- Prüft die Endbedingungen, die nicht als Ereignis eintreffen: Tod des Spielers und die
-- gerissene Leine. Der Sieg über den Guardian kommt dagegen als Aufruf aus
-- CityDefenderService.

local ACCUMULATOR_STEP = 0.25
local accumulator = 0

RunService.Heartbeat:Connect(function(deltaTime)
	accumulator += deltaTime
	if accumulator < ACCUMULATOR_STEP then
		return
	end
	accumulator = 0

	for player, session in pairs(sessions) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")

		if not humanoid or humanoid.Health <= 0 then
			endShowdown(player, "Spieler gefallen")
		elseif not (_G.HasActiveGuardian and _G.HasActiveGuardian(session.cityName)) then
			-- Der Guardian ist verschwunden, ohne dass die Niederlage gemeldet wurde --
			-- etwa weil die Stadt zurückgesetzt wurde.
			endShowdown(player, "Guardian nicht mehr da")
		elseif rootPart then
			local guardianModel = _G.GetGuardianModel and _G.GetGuardianModel(session.cityName)
			local guardianRoot = guardianModel and guardianModel.PrimaryPart
			if guardianRoot then
				-- Waagerecht messen, wie überall beim Guardian: sein Wurzelteil sitzt auf
				-- Hüfthöhe des Skeletts, und die Höhe würde sonst voll mitzählen.
				local flat = (rootPart.Position - guardianRoot.Position) * Vector3.new(1, 0, 1)
				if flat.Magnitude > (_G.GetGuardianLeashRadius and _G.GetGuardianLeashRadius() or 220) then
					-- Ein Filmstreifen ohne Kampf dahinter ist der schnellste Weg, dem
					-- Mittel seine Wirkung zu nehmen.
					endShowdown(player, "Leine gerissen")
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
	playerHitGuardianAt[player] = nil
	guardianHitPlayerAt[player] = nil
	reentryLockUntil[player] = nil
end)

-- ===== Debug-Panel =====

_G.DebugForceShowdown = function(player)
	local cityName = player:GetAttribute("CurrentCityName")
	if not cityName then
		print("[Kaiju-Debug] Showdown erzwingen: Spieler steht in keiner Stadt.")
		return
	end
	-- Die Sperre nach dem Aufgeben umgehen: beim Testen will man nicht 45 Sekunden warten.
	if reentryLockUntil[player] then
		reentryLockUntil[player][cityName] = nil
	end
	startShowdown(player, cityName)
end

_G.DebugTriggerShowdownShot = function(player, shotName)
	local session = sessions[player]
	if not session then
		print("[Kaiju-Debug] Shot auslösen: kein Showdown aktiv.")
		return
	end
	-- Den Mindestabstand für den Testschalter aufheben, sonst wartet man je Versuch sechs
	-- Sekunden -- das ist der Unterschied zwischen zwanzig Versuchen pro Stunde und dreien.
	session.lastShotAt = 0
	_G.NotifyShowdownAttack(shotName, player, session.cityName)
end

_G.DebugSetShowdownShortDuration = function(enabled)
	debugShortDuration = enabled == true
	print(string.format(
		"[Kaiju-Debug] Showdown-Mindestdauer: %s.",
		debugShortDuration and (ShowdownConfig.DebugMinimumDuration .. "s (verkürzt)")
			or (ShowdownConfig.MinimumDuration .. "s (normal)")))
end

-- Ein Ereignis für alle vier Schalter statt vier Ereignisse: sie gehören zusammen und
-- werden zusammen entfernt, falls das Panel je aufgeräumt wird.
DebugShowdownEvent.OnServerEvent:Connect(function(player, action, payload)
	if action == "Force" then
		_G.DebugForceShowdown(player)
	elseif action == "Shot" then
		_G.DebugTriggerShowdownShot(player, payload)
	elseif action == "ShortDuration" then
		_G.DebugSetShowdownShortDuration(payload)
	elseif action == "End" then
		endShowdown(player, "Debug")
	end
end)

print("[Kaiju] ShowdownService bereit.")
