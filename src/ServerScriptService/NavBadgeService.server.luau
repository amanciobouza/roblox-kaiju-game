-- Script: NavBadgeService
-- Ort in Studio: ServerScriptService
--
-- Merkt sich, an welchen Menüpunkten ein rotes Lämpchen leuchtet -- über den Neustart
-- hinweg. Ohne das hinge es vom Zufall ab: wer nach einem freigeschalteten Achievement
-- noch weiterspielt, sähe den Hinweis; wer sofort abschaltet, nie.
--
-- ===== Warum der Client meldet und nicht der Server =====
-- Fast alle Auslöser sind clientseitige Ereignisse: ArchiveRevealedEvent,
-- AchievementUnlockedEvent, ResearchCompleteEvent, und die Geschenk-Bereitschaft rechnet
-- GiftClient ohnehin selbst aus. Der Client weiss es also zuerst. Ihn melden zu lassen
-- spart, dieselbe Logik ein zweites Mal serverseitig zu bauen -- und die Angabe ist rein
-- kosmetisch: wer sie fälscht, bekommt einen roten Punkt, sonst nichts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local NavBadgeEvent = RemoteEventUtils.GetOrCreate("NavBadgeEvent")

-- Als Attribute am Spieler, wie bei Statistiken, Achievements und Archiv -- dadurch im
-- Studio-Explorer nachvollziehbar und für den eigenen Client automatisch lesbar.
local NAV_BADGE_PREFIX = "NavBadge_"

-- Nur diese Schlüssel werden angenommen. Ein Client, der beliebige Namen schicken darf,
-- könnte den Spieler mit Attributen zumüllen; die Liste kostet nichts und schliesst das aus.
local VALID_KEYS = {
	Monster = true,
	Achievements = true,
	Talents = true,
	Gifts = true,
	Faction = true,
	Archive = true,
}

-- Zusätzlich zum Lämpchen: WELCHE Einträge neu sind. Das Lämpchen sagt nur "da ist
-- etwas" -- wer das Panel öffnet, soll auf einen Blick sehen, was. Als
-- kommagetrennte Zeichenkette, weil Attribute keine Tabellen aufnehmen.
local NAV_ITEMS_PREFIX = "NavBadgeItems_"

-- Obergrenze, damit die Zeichenkette nicht unbegrenzt waechst: wer zwanzig Dinge
-- ungesehen liegen laesst, braucht keine Aufzaehlung mehr, sondern nur den Hinweis.
local MAX_ITEMS_PER_KEY = 20

NavBadgeEvent.OnServerEvent:Connect(function(player, key, on, itemId)
	if type(key) ~= "string" or not VALID_KEYS[key] then
		return
	end
	-- nil statt false: ein ausgeschaltetes Lämpchen soll kein Attribut hinterlassen,
	-- sonst wächst der Speicherstand mit Einträgen, die nichts aussagen.
	player:SetAttribute(NAV_BADGE_PREFIX .. key, on == true or nil)

	local itemsName = NAV_ITEMS_PREFIX .. key
	if not on then
		player:SetAttribute(itemsName, nil)
		return
	end
	if type(itemId) ~= "string" or itemId == "" or string.find(itemId, ",", 1, true) then
		return -- kein Einzeleintrag, nur das Lämpchen (z.B. Geschenke)
	end
	local current = player:GetAttribute(itemsName)
	if type(current) ~= "string" or current == "" then
		player:SetAttribute(itemsName, itemId)
		return
	end
	-- Doppelte vermeiden, sonst steht derselbe Eintrag nach zwei Sitzungen zweimal drin.
	for existing in string.gmatch(current, "[^,]+") do
		if existing == itemId then
			return
		end
	end
	if select(2, string.gsub(current, ",", ",")) + 1 < MAX_ITEMS_PER_KEY then
		player:SetAttribute(itemsName, current .. "," .. itemId)
	end
end)

-- ===== Speicherstand =====
-- Gleiches Muster wie Talente, Achievements, Statistiken und Archiv.

-- Ergebnis: { Archive = "AlertHelicopter,Tank", Gifts = true }. Die Zeichenkette nennt die
-- ungesehenen Eintraege, ein blosses true steht fuer "etwas Neues, aber ohne Einzelangabe"
-- (Geschenke rechnen sich selbst aus und haben keine Ids).
-- Loescht alle Laempchen. Gerufen vom Debug-Reset: sie verweisen auf "neue" Eintraege,
-- die es nach einem Reset nicht mehr gibt -- ein rotes Laempchen an einem leeren Archiv
-- waere ein Hinweis auf nichts.
_G.ResetPlayerNavBadges = function(player)
	local removed = 0
	for key in pairs(VALID_KEYS) do
		if player:GetAttribute(NAV_BADGE_PREFIX .. key) ~= nil then
			removed += 1
		end
		player:SetAttribute(NAV_BADGE_PREFIX .. key, nil)
		player:SetAttribute(NAV_ITEMS_PREFIX .. key, nil)
	end
	print(string.format("[Kaiju-Debug] Menue-Laempchen von %s geloescht -- %d aktiv gewesen.", player.Name, removed))
	return removed
end

_G.GetNavBadgeSaveData = function(player)
	local saved = {}
	for key in pairs(VALID_KEYS) do
		if player:GetAttribute(NAV_BADGE_PREFIX .. key) == true then
			saved[key] = player:GetAttribute(NAV_ITEMS_PREFIX .. key) or true
		end
	end
	return saved
end

_G.LoadNavBadgeSaveData = function(player, saveData)
	if type(saveData) ~= "table" then
		return
	end
	local count = 0
	for key, value in pairs(saveData) do
		-- Unbekannte Schlüssel überspringen: ein Menüpunkt kann umbenannt oder entfernt
		-- worden sein, und ein alter Speicherstand darf daran nicht scheitern.
		if type(key) == "string" and VALID_KEYS[key] then
			player:SetAttribute(NAV_BADGE_PREFIX .. key, true)
			if type(value) == "string" then
				player:SetAttribute(NAV_ITEMS_PREFIX .. key, value)
			end
			count += 1
		end
	end
	if count > 0 then
		print(string.format("[Kaiju-Debug] Menü-Lämpchen geladen für %s -- %d aktiv.", player.Name, count))
	end
end

Players.PlayerRemoving:Connect(function(player)
	-- Nichts aufzuräumen: die Attribute verschwinden mit dem Spieler-Objekt. Der Handler
	-- steht hier nur, damit klar ist, dass das Absicht ist und nicht vergessen wurde.
end)

print("[Kaiju] NavBadgeService bereit -- Menü-Lämpchen überleben den Neustart.")
