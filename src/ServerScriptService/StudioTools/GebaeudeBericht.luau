--============================================================
-- STUDIO-WERKZEUG: Gebaeudewerte einer Stadt auslesen
--
-- ===== So wird es benutzt =====
-- In Studio, in der Command Bar, EINE Zeile:
--
--   require(game.ServerScriptService.StudioTools.GebaeudeBericht).Print("Village")
--
-- Ohne Argument kommen ALLE Staedte. Die Ausgabe ist fertiges Lua und kann direkt in eine
-- Config kopiert werden -- sie ist das Ziel der ganzen Uebung, nicht eine Tabelle zum
-- Abtippen.
--
-- Laeuft im BEARBEITUNGSMODUS, ein Playtest ist nicht noetig: die Werte stehen als
-- Attribute an den Modellen und sind dort schon vorhanden.
--
-- ===== Warum es das gibt =====
-- Die Gebaeudewerte des Village stehen ausschliesslich in Studio an den Modellen -- im Repo
-- nirgends. Das ist die letzte offene Abweichung des Spec-Pruefers
-- (village.buildings-declared-centrally), und sie ist mehr als Buchhaltung: ohne die Werte
-- laesst sich weder ausrechnen, was ein Durchgang wert ist, noch ob die Alarmschwellen
-- passen, noch auf welche Levelstrecke die Stadt ausgelegt ist. Bei jeder Balance-Frage
-- fehlte bisher genau diese Zahl.
--
-- ===== Es laeuft beim Serverstart automatisch mit =====
-- CityAlertService ruft es am Ende seines Durchgang-Berichts auf, fuer die Staedte, die
-- dort in BERICHT_BEIM_START stehen (heute nur das Village). So steht die Ausgabe nach
-- jedem Start im Output, ohne dass jemand daran denken muss.
--
-- Sobald die Werte einer Stadt in einer Config erfasst sind, gehoert sie aus jener Liste
-- entfernt: dann ist die Ausgabe nur noch Laerm, und der Spec-Pruefer wacht ueber die
-- Config statt ueber diesen Bericht.
--============================================================

local M = {}

M.VERSION = "GebaeudeBericht_v01"

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local HOUSE_TAG = "KaijuHouse"

-- Dieselbe Aufloesung wie im CityAlertService: der naechste Vorfahre, der "CityName"
-- traegt. Ueber Ordnernamen zu gehen waere bruechig -- in Studio heisst der Ordner nicht
-- zwingend wie die Stadt (Brasshaven liegt unter "Smalltown").
local function stadtVon(instanz)
	local knoten = instanz
	while knoten and knoten ~= Workspace do
		local name = knoten:GetAttribute("CityName")
		if name then
			return name
		end
		knoten = knoten.Parent
	end
	return nil
end

-- Ein Gebaeude ist ein Abschnitt eines groesseren Bauwerks, wenn es das sagt. Diese
-- Unterscheidung muss mit in den Bericht: drei Abschnitte zu je 3 500 sind etwas anderes
-- als drei Haeuser zu je 3 500 -- sie teilen sich Respawn und Alarmwert.
local function abschnittVon(haus)
	if haus:GetAttribute("RespawnMode") ~= "ParentGroup" then
		return nil
	end
	local knoten = haus.Parent
	while knoten and knoten ~= Workspace do
		if knoten:IsA("Model")
			and (knoten:GetAttribute("UsesSectionHealth") == true
				or knoten:GetAttribute("SpawnAsSingleAsset") == true) then
			return knoten.Name
		end
		knoten = knoten.Parent
	end
	return "(Wurzel fehlt)"
end

local function luaText(wert)
	if type(wert) == "string" then
		return string.format("%q", wert)
	end
	return tostring(wert)
end

local function sammle(nurStadt)
	local staedte = {}
	for _, haus in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		local stadt = stadtVon(haus)
		if stadt and (not nurStadt or stadt == nurStadt) then
			local eintrag = staedte[stadt]
			if not eintrag then
				eintrag = { Zeilen = {}, Reihenfolge = {}, Teile = 0, Leben = 0, Alarm = 0, OhneWert = 0 }
				staedte[stadt] = eintrag
			end

			local leben = haus:GetAttribute("MaxHealth")
			local alarm = haus:GetAttribute("AlertValue")
			local energie = haus:GetAttribute("EnergyType")
			local gehoertZu = abschnittVon(haus)

			-- Gleiche Werte werden zusammengefasst: zwoelf identische Haeuser sollen eine
			-- Zeile mit Anzahl ergeben, nicht zwoelf Zeilen.
			local schluessel = table.concat({
				haus.Name, tostring(leben), tostring(alarm), tostring(energie), tostring(gehoertZu),
			}, "|")

			local zeile = eintrag.Zeilen[schluessel]
			if not zeile then
				zeile = {
					Name = haus.Name, Leben = leben, Alarm = alarm,
					Energie = energie, GehoertZu = gehoertZu, Anzahl = 0,
				}
				eintrag.Zeilen[schluessel] = zeile
				table.insert(eintrag.Reihenfolge, zeile)
			end
			zeile.Anzahl += 1

			eintrag.Teile += 1
			eintrag.Leben += leben or 0
			if alarm then
				eintrag.Alarm += alarm
			else
				eintrag.OhneWert += 1
			end
		end
	end
	return staedte
end

function M.Print(nurStadt)
	local staedte = sammle(nurStadt)

	local namen = {}
	for stadt in pairs(staedte) do
		table.insert(namen, stadt)
	end
	table.sort(namen)

	if #namen == 0 then
		warn("[Kaiju Debug] Gebaeudebericht: keine Gebaeude gefunden"
			.. (nurStadt and (" fuer '" .. nurStadt .. "'") or "")
			.. " -- traegt der Stadtordner das Attribut CityName?")
		return
	end

	print("-- ===== Gebaeudebericht (" .. M.VERSION .. ") =====")
	for _, stadt in ipairs(namen) do
		local eintrag = staedte[stadt]

		-- Stabile Reihenfolge: schwerste Gebaeude zuerst, dann nach Namen.
		table.sort(eintrag.Reihenfolge, function(a, b)
			if (a.Leben or 0) ~= (b.Leben or 0) then
				return (a.Leben or 0) > (b.Leben or 0)
			end
			return a.Name < b.Name
		end)

		print(stadt .. " = {")
		for _, zeile in ipairs(eintrag.Reihenfolge) do
			local teile = { string.format("Name = %q", zeile.Name) }
			table.insert(teile, "Anzahl = " .. zeile.Anzahl)
			table.insert(teile, "MaxHealth = " .. luaText(zeile.Leben))
			table.insert(teile, "AlertValue = " .. luaText(zeile.Alarm))
			if zeile.Energie then
				table.insert(teile, "EnergyType = " .. luaText(zeile.Energie))
			end
			if zeile.GehoertZu then
				table.insert(teile, string.format("AbschnittVon = %q", zeile.GehoertZu))
			end
			print("\t{ " .. table.concat(teile, ", ") .. " },")
		end
		print("}")
		print(string.format("-- %d Teile, %d Lebenspunkte, %d Alarmpunkte%s",
			eintrag.Teile, eintrag.Leben, eintrag.Alarm,
			eintrag.OhneWert > 0
				and string.format(" -- ACHTUNG: %d Teile ohne eigenes AlertValue, die laufen "
					.. "ueber AlertPerHP", eintrag.OhneWert)
				or ""))
		print("")
	end
end

return M
