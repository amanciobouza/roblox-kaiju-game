-- Script: StatsService
-- Ort in Studio: ServerScriptService
--
-- Lebenslange Spielerstatistiken über alle Sessions. Getrennt vom Achievement-System:
-- dessen Zähler (Counter_BuildingsDestroyed) sind an Schwellen gebunden und hören
-- konzeptionell bei der höchsten Stufe auf, interessant zu sein. Hier zählt alles weiter.
--
-- ===== Zuschreibung im Mehrspielerbetrieb =====
-- Ereignisse mit ANGREIFER (Gebäude, Militär, Guardian, Schaden) gehen an den Spieler,
-- der sie verursacht hat -- die Aufrufer geben ihn mit.
--
-- Ereignisse ohne Angreifer (Alarmstufe erreicht, CITY BROKEN) sind Stadt-Ereignisse.
-- Sie gehen an ALLE Spieler, die sich gerade in dieser Stadt aufhalten
-- (CurrentCityName, wird von CityAlertService sekündlich gepflegt). Das ist die
-- Auslegung, die im Koop trägt: wer dabei war, hat es miterlebt.
--
-- ===== Schlüssel =====
-- Flache Zeichenketten mit Punkt als Trenner, damit ein neuer Wert kein Schema-Update
-- braucht:
--   PlaytimeSeconds
--   BuildingsDestroyed             BuildingsDestroyed.City
--   MilitaryDestroyed.Tank         MilitaryDestroyed.Helicopter
--   GuardianDefeated               GuardianDefeated.City
--   HitBy.Guardian.City            HitBy.Military.Tank
--   Attacks.Punch                  MaxDamage.Punch
--
-- WICHTIG: Gebäude werden als getaggte SEKTIONEN gezählt, nicht als ganze Bauwerke.
-- Ein Asset wie die Marina trägt 7 KaijuHouse-Tags und zählt entsprechend als 7. Das
-- ist bewusst so -- es entspricht dem, was die Achievement-Schwellen schon tun, und
-- braucht keine ParentGroup-Auflösung.

local Players = game:GetService("Players")

local STAT_ATTRIBUTE_PREFIX = "Stat_"

-- [player] = os.clock() beim letzten Verbuchen der Spielzeit
local playtimeMarks = {}

local PLAYTIME_TICK_SECONDS = 30

-- ===== Speicher =====
-- Statistiken liegen als Attribute am Spieler, damit sie ohne eigene Tabelle sichtbar
-- und im Studio-Explorer nachvollziehbar sind -- dasselbe Muster wie bei Energien und
-- Achievement-Zählern.
local function getStat(player, key)
	return player:GetAttribute(STAT_ATTRIBUTE_PREFIX .. key) or 0
end

local function setStat(player, key, value)
	player:SetAttribute(STAT_ATTRIBUTE_PREFIX .. key, value)
end

-- ===== Öffentliche API =====

-- Zählt einen Wert hoch. amount darf fehlen (= 1).
_G.RecordStat = function(player, key, amount)
	if not player or not key then
		return
	end
	-- Prolog-Läufe zählen nicht in die Lebensstatistik: der Prolog ist eine geskriptete
	-- Sequenz mit eigenen Zahlen, sein Beitrag würde die Statistik verfälschen.
	if player:GetAttribute("IsInPrologue") == true then
		return
	end
	setStat(player, key, getStat(player, key) + (amount or 1))
end

-- Hält den HÖCHSTEN je erreichten Wert fest (für "höchster Schadenswert pro Angriffstyp").
_G.RecordStatMax = function(player, key, value)
	if not player or not key or type(value) ~= "number" then
		return
	end
	if player:GetAttribute("IsInPrologue") == true then
		return
	end
	if value > getStat(player, key) then
		setStat(player, key, value)
	end
end

-- Stadt-Ereignis ohne Angreifer: geht an alle Spieler in dieser Stadt.
_G.RecordStatForCity = function(cityName, key, amount)
	if not cityName or not key then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName then
			_G.RecordStat(player, key, amount)
		end
	end
end

-- ===== Speicherstand-Anbindung =====
-- Gleiches Muster wie Talente und Achievements: PlayerSetup ruft diese beiden Funktionen
-- beim Speichern und Laden auf und muss die einzelnen Schlüssel nicht kennen.

_G.GetStatsSaveData = function(player)
	-- Spielzeit vor dem Speichern nachführen, sonst fehlt die angebrochene Periode.
	if playtimeMarks[player] then
		local now = os.clock()
		_G.RecordStat(player, "PlaytimeSeconds", math.floor(now - playtimeMarks[player]))
		playtimeMarks[player] = now
	end

	local stats = {}
	for name, value in pairs(player:GetAttributes()) do
		if string.sub(name, 1, #STAT_ATTRIBUTE_PREFIX) == STAT_ATTRIBUTE_PREFIX then
			stats[string.sub(name, #STAT_ATTRIBUTE_PREFIX + 1)] = value
		end
	end
	return stats
end

_G.LoadStatsSaveData = function(player, saveData)
	if type(saveData) ~= "table" then
		return
	end
	local count = 0
	for key, value in pairs(saveData) do
		if type(value) == "number" then
			setStat(player, key, value)
			count += 1
		end
	end
	print(string.format("[Kaiju-Debug] Statistiken geladen für %s -- %d Werte.", player.Name, count))
end

-- Liefert alle Statistiken als Tabelle -- für Anzeige/Debug.
_G.GetStats = function(player)
	return _G.GetStatsSaveData(player)
end

-- ===== Spielzeit =====
-- Periodisch statt nur beim Verlassen: sonst geht die laufende Sitzung bei einem
-- Absturz komplett verloren. Der Autosave in PlayerSetup läuft alle 120s, diese
-- Nachführung häufiger, damit der gespeicherte Wert nie weit hinterherhinkt.
Players.PlayerAdded:Connect(function(player)
	playtimeMarks[player] = os.clock()
end)

Players.PlayerRemoving:Connect(function(player)
	-- Gleiche Falle wie beim Talentbaum: PlayerSetup holt sich die Statistiken in
	-- seinem eigenen PlayerRemoving-Handler über _G.GetStatsSaveData, und der rechnet
	-- die angebrochene Spielzeit aus playtimeMarks nach. Sofortiges Leeren würde je
	-- nach Startreihenfolge die letzte Periode verschlucken.
	task.defer(function()
		playtimeMarks[player] = nil
	end)
end)

task.spawn(function()
	while true do
		task.wait(PLAYTIME_TICK_SECONDS)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local mark = playtimeMarks[player]
			if mark then
				_G.RecordStat(player, "PlaytimeSeconds", math.floor(now - mark))
				playtimeMarks[player] = now
			end
		end
	end
end)

print("[Kaiju] StatsService bereit -- lebenslange Statistiken über alle Sessions.")
