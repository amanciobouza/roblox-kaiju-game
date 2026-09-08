-- Script: TelemetryService
-- Ort in Studio: ServerScriptService
--
-- Zeichnet auf, was ein Playtest beantworten soll (siehe Specs/VillageChapterOneSpec,
-- Regel village.telemetry-answers-the-questions).
--
-- ===== Ein reiner Beobachter =====
-- Dieser Dienst ändert NICHTS und wird von niemandem gerufen. Er liest ausschliesslich,
-- was ohnehin schon da ist: die Lebensstatistik zählt bereits Attacks.Punch, Attacks.Jump,
-- Attacks.Focus, Attacks.Area, Zerstörungen je Stadt, AlertReached.<Stufe> und
-- CityBroken.<Stadt>; Hitze und Berserker stehen als Attribute am Spieler; Level, Münzen
-- und Kraftwerte hängen als Objekte an ihm.
--
-- Deshalb kostet diese Aufzeichnung keine einzige Änderung an einem laufenden System --
-- und kann keines kaputt machen.
--
-- ===== Ereignisstrom, nicht Endwerte =====
-- Aus Endwerten lassen sich Heat-Verlauf, Specials pro Minute und die Frage "ab wann
-- fühlt es sich wiederholt an" nicht rekonstruieren. Aufgezeichnet wird deshalb ein
-- Strom mit Zeitstempeln:
--   * SELTENE Ereignisse einzeln, sobald sie eintreten (Alarmwechsel, Berserker,
--     Meltdown, Levelaufstieg, Verteidigung besiegt, Stadtbruch).
--   * HÄUFIGE Vorgänge als Zwischenstand alle 15 Sekunden mit Zuwächsen -- jeden
--     einzelnen Schlag zu protokollieren ergäbe über tausend Zeilen je Lauf und wäre
--     im Ausgabefenster nicht mehr lesbar.
--
-- ===== Ein Lauf =====
-- Beginnt beim ERSTEN SCHADEN in einer Stadt und endet mit CITY BROKEN. Die Uhr läuft
-- nur, solange der Spieler in dieser Stadt ist -- ein Rückzug ins Sanctuary ist laut
-- Spezifikation eine legitime Entscheidung und darf die wichtigste Kennzahl nicht
-- verfälschen. Beide Zeiten werden mitgeschrieben, damit später gewählt werden kann.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local PREFIX = "[Kaiju-Telemetrie]"

-- Wie oft der Zustand abgetastet wird. Zwei Sekunden reichen: die schnellste beobachtete
-- Grösse ist die Hitze, und die ändert sich in dieser Spanne nicht sprunghaft.
local SAMPLE_INTERVAL = 2

-- Abstand zwischen zwei Zwischenständen. 15 Sekunden ergeben bei einem
-- Zwanzig-Minuten-Lauf 80 Zeilen -- genug für eine Verlaufskurve, wenig genug fürs
-- Ausgabefenster.
local SNAPSHOT_INTERVAL = 15

-- Ob der Spieler im Meltdown ist, beantwortet HeatHandler selbst (_G.GetHeatStage) --
-- hier steht bewusst KEINE eigene Schwelle mehr.
--
-- Vorher stand hier fest 100 mit der Begründung, für die Auswertung genüge die
-- Grundschwelle. Das war falsch: das Talent "Overheat Specialist" hebt die Schwelle auf
-- bis zu 109. Bei einem Spieler mit diesem Talent zählte alles zwischen 100 und seiner
-- echten Schwelle hier als Meltdown, im Spiel aber nicht -- und weil in diesem Bereich
-- weder die Mindestdauer-Sperre noch die langsame Meltdown-Abkühlung greifen, pendelte
-- der Wert um die 100 und erzeugte eine Kette von Meltdown-Ereignissen, die es nie gab.
-- Ein Messwerkzeug, das seine eigene Schwelle mitführt, misst irgendwann etwas anderes
-- als das System, das es beobachten soll.
local function isInMeltdown(player)
	return _G.GetHeatStage and _G.GetHeatStage(player) == "Meltdown"
end

-- Zuwächse dieser Statistiken landen in jedem Zwischenstand. Sie beantworten zusammen
-- fast alle Kennzahlen aus der Spezifikation -- darunter die neue Frage, ob der Schlag
-- ueberhaupt noch benutzt wird.
local TRACKED_STATS = {
	"BuildingsDestroyed",
	"DamageDealt",
	"DamageTaken",
	"CoinsCollected",
	"Attacks.Punch",
	"Attacks.Jump",
	"Attacks.Focus",
	"Attacks.Area",
	"FireEnginesDestroyed",
	"BarricadesDestroyed",
	"GeneratorsDestroyed",
}

local ENERGY_TYPES = { "Heat", "Chemical", "Electric", "Radiation", "Spirit" }

local enabled = true

-- [player] = Laufzustand, siehe startRun
local runs = {}

local function stat(player, key)
	return player:GetAttribute("Stat_" .. key) or 0
end

local function valueOf(player, name, childName)
	local holder = player:FindFirstChild(name)
	if not holder then
		return 0
	end
	if childName then
		local child = holder:FindFirstChild(childName)
		return child and child.Value or 0
	end
	return holder.Value or 0
end

-- Summe aller tatsaechlich erhaltenen Energie. Die Lebenszaehler steigen nur beim
-- Einsammeln, nicht beim Zerstoeren -- genau die Groesse, die die Spezifikation meint.
local function totalEnergyReceived(player)
	local sum = 0
	for _, energyType in ipairs(ENERGY_TYPES) do
		sum += player:GetAttribute("LifetimeEnergy" .. energyType) or 0
	end
	return sum
end

local function snapshotOf(player)
	local values = {}
	for _, key in ipairs(TRACKED_STATS) do
		values[key] = stat(player, key)
	end
	values.EnergyReceived = totalEnergyReceived(player)
	values.Coins = valueOf(player, "leaderstats", "Coins")
	values.XP = valueOf(player, "XP")
	values.Level = valueOf(player, "leaderstats", "Level")
	values.ArmPower = valueOf(player, "ArmPower")
	values.LegPower = valueOf(player, "LegPower")
	values.BodyPower = valueOf(player, "BodyPower")
	return values
end

local function emit(eventName, player, payload)
	if not enabled then
		return
	end
	local run = runs[player]
	payload = payload or {}
	payload.event = eventName
	payload.player = player.Name
	payload.city = run and run.city or player:GetAttribute("CurrentCityName")
	-- Zwei Uhren: die reine Spielzeit in der Stadt (fuer die 20-Minuten-Kennzahl) und
	-- die verstrichene Zeit seit Laufbeginn (fuer den Vergleich mit Rueckzuegen).
	payload.cityTime = run and math.floor(run.cityTime * 10) / 10 or 0
	payload.wallTime = run and math.floor((os.clock() - run.startedAt) * 10) / 10 or 0

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	print(PREFIX, ok and encoded or tostring(payload.event))
end

local function startRun(player, cityName)
	runs[player] = {
		city = cityName,
		startedAt = os.clock(),
		cityTime = 0,
		lastSnapshotAt = 0,
		baseline = snapshotOf(player),
		previous = snapshotOf(player),
		alertLevel = -1,
		berserk = false,
		meltdown = false,
		level = valueOf(player, "leaderstats", "Level"),
		heatSamples = {},
	}
	emit("RunStart", player, { entryLevel = runs[player].level })
end

local function finishRun(player, reason)
	local run = runs[player]
	if not run then
		return
	end
	local final = snapshotOf(player)
	local totals = {}
	for key, value in pairs(final) do
		local base = run.baseline[key] or 0
		totals[key] = value - base
	end

	-- Hitzeverteilung als Histogramm über die Baender der Spezifikation. Der Mittelwert
	-- allein waere nutzlos: 50 % koennte "immer lau" oder "staendig zwischen 0 und 100"
	-- bedeuten, und das ist derselbe Unterschied wie zwischen gut und kaputt.
	--
	-- ACHTUNG, die 100 hier sind NICHT die Meltdown-Schwelle des Spielers (die ist per
	-- Talent verschiebbar, siehe isInMeltdown oben), sondern die feste Bandgrenze der
	-- Spezifikation. Beides muss getrennt bleiben: die Baender vergleichen alle Laeufe auf
	-- derselben Skala, das Ereignis meldet, was diesem Spieler tatsaechlich widerfahren
	-- ist.
	local bands = { normal = 0, warm = 0, hot = 0, berserk = 0, meltdown = 0 }
	for _, heat in ipairs(run.heatSamples) do
		if heat >= 100 then
			bands.meltdown += 1
		elseif heat >= 85 then
			bands.berserk += 1
		elseif heat >= 60 then
			bands.hot += 1
		elseif heat >= 25 then
			bands.warm += 1
		else
			bands.normal += 1
		end
	end

	emit("RunEnd", player, {
		reason = reason,
		exitLevel = valueOf(player, "leaderstats", "Level"),
		totals = totals,
		heatBands = bands,
		heatSampleCount = #run.heatSamples,
	})
	runs[player] = nil
end

-- ===== Abtastung =====

local accumulator = 0

RunService.Heartbeat:Connect(function(deltaTime)
	accumulator += deltaTime
	if accumulator < SAMPLE_INTERVAL then
		return
	end
	local elapsed = accumulator
	accumulator = 0

	if not enabled then
		return
	end

	local cityAlertFolder = ReplicatedStorage:FindFirstChild("CityAlertValues")

	for _, player in ipairs(Players:GetPlayers()) do
		-- ACHTUNG: CityAlertService setzt dieses Attribut ausserhalb jeder Stadt auf die
		-- ZEICHENKETTE "None", nicht auf nil (siehe getCurrentCityForPosition). Eine
		-- Pruefung auf blosse Anwesenheit geht darauf herein -- ein Trainingslauf im
		-- Sanctuary startete so einen vollstaendigen Stadtlauf mit city="None" und
		-- alert=-1, dessen Stadtuhr nie lief.
		local cityName = player:GetAttribute("CurrentCityName")
		if cityName == "None" then
			cityName = nil
		end
		local run = runs[player]

		-- Der Prolog zaehlt nicht mit: er ist eine geskriptete Sequenz mit eigenen
		-- Zahlen, genau wie in der Lebensstatistik.
		if player:GetAttribute("IsInPrologue") == true then
			continue
		end

		if not run then
			-- Ein Lauf beginnt beim ERSTEN SCHADEN in einer Stadt, nicht beim Betreten:
			-- die Zeit, in der man sich umsieht, gehoert nicht in den Kampfwert.
			if cityName and stat(player, "DamageDealt") > 0 then
				local seenDamage = player:GetAttribute("TelemetrySeenDamage") or 0
				if stat(player, "DamageDealt") > seenDamage then
					startRun(player, cityName)
					run = runs[player]
				end
			end
			player:SetAttribute("TelemetrySeenDamage", stat(player, "DamageDealt"))
			if not run then
				continue
			end
		end

		-- Die Stadt-Uhr laeuft nur, solange der Spieler dort ist.
		local inCity = cityName == run.city
		if inCity then
			run.cityTime += elapsed
		end

		-- Hitze: jede Abtastung ins Histogramm, Zustandswechsel als eigenes Ereignis.
		--
		-- NUR waehrend die Stadtuhr laeuft. Der Rueckzug ins Sanctuary haelt den Lauf an;
		-- was dort passiert, gehoert nicht in seine Zahlen. Trainingsschlaege erzeugen
		-- ebenfalls Hitze, und ohne diese Bedingung landete ein halbstuendiges Training
		-- vollstaendig in der Hitzeverteilung eines Stadtlaufs -- samt jedem Berserker-
		-- und Meltdown-Ereignis, das dabei anfiel.
		local heat = player:GetAttribute("Heat") or 0
		if inCity then
			table.insert(run.heatSamples, heat)

			local berserk = player:GetAttribute("BerserkActive") == true
			if berserk ~= run.berserk then
				run.berserk = berserk
				emit(berserk and "BerserkStart" or "BerserkEnd", player, { heat = heat })
			end

			local meltdown = isInMeltdown(player)
			if meltdown ~= run.meltdown then
				run.meltdown = meltdown
				if meltdown then
					emit("Meltdown", player, { heat = heat })
				end
			end
		end

		local level = valueOf(player, "leaderstats", "Level")
		if level > run.level then
			run.level = level
			emit("LevelUp", player, { level = level })
		end

		-- Alarmstufe der Stadt, in der der Lauf laeuft.
		if cityAlertFolder then
			local levelValue = cityAlertFolder:FindFirstChild(run.city .. "Level")
			local alert = levelValue and levelValue.Value or -1
			if alert ~= run.alertLevel then
				local previous = run.alertLevel
				run.alertLevel = alert
				if previous >= 0 then
					emit("AlertLevel", player, { level = alert, from = previous })
				end
			end

			local brokenValue = cityAlertFolder:FindFirstChild(run.city .. "CityBroken")
			if brokenValue and brokenValue.Value == true then
				finishRun(player, "CityBroken")
				continue
			end
		end

		-- Zwischenstand mit Zuwaechsen seit dem letzten.
		if run.cityTime - run.lastSnapshotAt >= SNAPSHOT_INTERVAL then
			run.lastSnapshotAt = run.cityTime
			local current = snapshotOf(player)
			local delta = {}
			for key, value in pairs(current) do
				local before = run.previous[key] or 0
				if value ~= before then
					delta[key] = value - before
				end
			end
			run.previous = current
			emit("Snapshot", player, {
				heat = heat,
				alert = run.alertLevel,
				level = current.Level,
				coins = current.Coins,
				arm = current.ArmPower,
				leg = current.LegPower,
				body = current.BodyPower,
				delta = delta,
			})
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	finishRun(player, "PlayerLeft")
end)

-- ===== Schalter =====

_G.SetTelemetryEnabled = function(value)
	enabled = value == true
	print(string.format("%s Aufzeichnung %s.", PREFIX, enabled and "an" or "aus"))
	if not enabled then
		for player in pairs(runs) do
			runs[player] = nil
		end
	end
end

_G.IsTelemetryEnabled = function()
	return enabled
end

-- Von Hand beenden, etwa wenn ein Lauf abgebrochen wird.
_G.EndTelemetryRun = function(player, reason)
	finishRun(player, reason or "Manuell")
end

-- Schalter aus dem Debug-Panel. Eigenes Ereignis statt eines gemeinsamen: die
-- Telemetrie soll auch dann noch abschaltbar sein, wenn alles andere umgebaut wird.
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local DebugTelemetryEvent = RemoteEventUtils.GetOrCreate("DebugTelemetryEvent")

DebugTelemetryEvent.OnServerEvent:Connect(function(player, wanted)
	_G.SetTelemetryEnabled(wanted)
	-- Zustand zurueckmelden, damit der Knopf nicht raten muss.
	DebugTelemetryEvent:FireClient(player, _G.IsTelemetryEnabled())
end)

print(PREFIX .. " bereit -- Ereignisstrom mit dem Praefix '" .. PREFIX .. "'.")
