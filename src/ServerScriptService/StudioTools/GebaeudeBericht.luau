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
-- ===== Wenn eine neue Funktion "attempt to call a nil value" sagt =====
-- Dann liegt die ALTE Fassung im Require-Zwischenspeicher. Wer ein Modul in dieser
-- Studio-Sitzung schon einmal requiret hat, bekommt bei jedem weiteren require denselben
-- Rueckgabewert zurueck -- Rojo ersetzt beim Sync nur den Quelltext, nicht den bereits
-- geladenen Wert. Ausweg: einen Klon requiren, den kennt der Zwischenspeicher nicht.
--
--   require(game.ServerScriptService.StudioTools.GebaeudeBericht:Clone()).Warum("X")
--
-- Deshalb greift dieses Modul auch nirgends auf "script" zu: ein Klon hat keinen Parent.
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HOUSE_TAG = "KaijuHouse"

-- Die Soll-Seite des Abgleichs. Fehlt sie, laeuft der Bericht ohne Abgleich weiter -- die
-- reine Bestandsaufnahme ist auch fuer Staedte nuetzlich, fuer die noch nichts festgelegt ist.
local BuildingConfig do
	local modul = ReplicatedStorage:FindFirstChild("BuildingConfig")
	if modul and modul:IsA("ModuleScript") then
		-- Als Klon, sonst kaeme die Fassung aus dem Zwischenspeicher der Sitzung -- siehe
		-- den Hinweis zum Require-Zwischenspeicher im Kopf dieser Datei.
		local ok, ergebnis = pcall(require, modul:Clone())
		if ok then
			BuildingConfig = ergebnis
		else
			warn("[Kaiju Debug] Gebaeudebericht: BuildingConfig laesst sich nicht laden -- " .. tostring(ergebnis))
		end
	end
end

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
-- Gibt das MODELL zurueck, nicht seinen Namen. Der Abgleich weiter unten summiert je
-- Bauwerk, und zwei Marinas mit demselben Namen muessen dabei zwei Bauwerke bleiben --
-- ueber den Namen waeren sie eines mit doppelten Lebenspunkten.
local function abschnittVon(haus)
	if haus:GetAttribute("RespawnMode") ~= "ParentGroup" then
		return nil
	end
	local knoten = haus.Parent
	while knoten and knoten ~= Workspace do
		if knoten:IsA("Model")
			and (knoten:GetAttribute("UsesSectionHealth") == true
				or knoten:GetAttribute("SpawnAsSingleAsset") == true) then
			return knoten
		end
		knoten = knoten.Parent
	end
	-- Sagt "ich bin ein Abschnitt", findet aber kein Bauwerk ueber sich. Das ist ein Fehler
	-- in Studio und darf nicht als eigenstaendiges Haus durchrutschen.
	return nil, true
end

-- Nach aussen gegeben, damit GebaeudeWerteSetzen dieselbe Aufloesung benutzt. Zwei Kopien
-- dieser Logik waeren der sichere Weg dahin, dass der Bericht etwas anderes zaehlt als der
-- Setzer schreibt -- und dann streiten zwei Werkzeuge ueber dieselbe Stadt.
M.StadtVon = stadtVon
M.BauwerkVon = abschnittVon

-- ===== Warum zaehlt dieses Bauwerk nicht mit? =====
--
--   require(game.ServerScriptService.StudioTools.GebaeudeBericht).Warum("RoadsideMotel_L3")
--
-- Ein Bauwerk kann im Explorer stehen und trotzdem in keinem Bericht auftauchen. Dafuer
-- gibt es genau drei Gruende, und von aussen sehen alle drei gleich aus: es ist einfach
-- nicht da. Diese Funktion sagt, welcher es ist.
function M.Warum(name)
	local modell = Workspace:FindFirstChild(name, true)
	if not modell then
		warn(string.format("[Kaiju Debug] %q liegt nicht im Workspace -- Schreibweise pruefen.", name))
		return
	end

	print(string.format("-- ===== %s =====", modell:GetFullName()))

	local stadt = stadtVon(modell)
	if stadt then
		print(string.format("-- Stadt: %q (ueber das Attribut CityName eines Vorfahren)", stadt))
	else
		warn("[Kaiju Debug] GRUND 1: kein Vorfahre traegt das Attribut CityName. Das Bauwerk "
			.. "gehoert damit zu keiner Stadt und faellt aus jedem Bericht heraus.")
	end

	-- Die Teile, die ein Spieler angreifen kann, sind die getaggten -- nicht die Modelle.
	local getaggt, ungetaggt = {}, {}
	for _, kind in ipairs(modell:GetDescendants()) do
		if kind:IsA("Model") or kind:IsA("BasePart") then
			if CollectionService:HasTag(kind, HOUSE_TAG) then
				table.insert(getaggt, kind)
			elseif kind:GetAttribute("MaxHealth") then
				-- Traegt Lebenspunkte, aber keinen Tag: sieht aus wie ein Gebaeude, ist aber
				-- keines. Das ist der Fall, der am leichtesten uebersehen wird.
				table.insert(ungetaggt, kind)
			end
		end
	end
	if CollectionService:HasTag(modell, HOUSE_TAG) then
		table.insert(getaggt, modell)
	end

	if #getaggt == 0 then
		warn(string.format("[Kaiju Debug] GRUND 2: kein einziges Teil traegt den Tag %q. "
			.. "Ohne Tag ist es Kulisse -- nicht angreifbar, kein Ertrag, kein Alarm.", HOUSE_TAG))
	else
		print(string.format("-- %d Teile mit Tag %q:", #getaggt, HOUSE_TAG))
		local summe = 0
		for _, teil in ipairs(getaggt) do
			local leben = teil:GetAttribute("MaxHealth")
			summe += leben or 0
			print(string.format("--   %s  MaxHealth = %s, RespawnMode = %s, EnergyType = %s",
				teil.Name, tostring(leben), tostring(teil:GetAttribute("RespawnMode")),
				tostring(teil:GetAttribute("EnergyType"))))
		end
		print(string.format("-- zusammen %d Lebenspunkte", summe))
	end

	for _, teil in ipairs(ungetaggt) do
		warn(string.format("[Kaiju Debug] GRUND 3: %q traegt MaxHealth = %s, aber nicht den "
			.. "Tag %q -- es zaehlt nirgends mit. (RespawnMode = %s)",
			teil.Name, tostring(teil:GetAttribute("MaxHealth")), HOUSE_TAG,
			tostring(teil:GetAttribute("RespawnMode"))))
	end

	-- Fuer mehrteilige Bauwerke muss die Wurzel eines der beiden Merkmale tragen, sonst
	-- findet abschnittVon sie nicht und die Abschnitte gelten als eigenstaendige Haeuser.
	--
	-- Das wird auch geprueft, wenn heute noch NICHTS getaggt ist: wer gerade dabei ist, ein
	-- Bauwerk in Betrieb zu nehmen, soll alles Fehlende in EINEM Lauf sehen und nicht nach
	-- jedem Handgriff einen neuen brauchen.
	if #getaggt + #ungetaggt > 1 then
		local wurzelOk = modell:GetAttribute("UsesSectionHealth") == true
			or modell:GetAttribute("SpawnAsSingleAsset") == true
		if not wurzelOk then
			warn("[Kaiju Debug] Die Wurzel traegt weder UsesSectionHealth noch "
				.. "SpawnAsSingleAsset. Ihre Abschnitte werden dann als einzelne Haeuser "
				.. "gezaehlt statt als ein Bauwerk -- getrennter Respawn, getrennte "
				.. "Trefferzahl.")
		end
		for _, teil in ipairs(getaggt) do
			if teil ~= modell and teil:GetAttribute("RespawnMode") ~= "ParentGroup" then
				warn(string.format("[Kaiju Debug] %q hat RespawnMode = %s statt "
					.. "\"ParentGroup\" -- es respawnt allein statt mit seinem Bauwerk.",
					teil.Name, tostring(teil:GetAttribute("RespawnMode"))))
			end
		end
	end
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
				eintrag = {
					Zeilen = {}, Reihenfolge = {}, Teile = 0, Leben = 0, Alarm = 0, OhneWert = 0,
					-- Je Bauwerk-INSTANZ: fuer den Abgleich gegen die Config. Bei mehrteiligen
					-- Bauwerken zaehlt die Summe ihrer Abschnitte, nicht der einzelne Abschnitt.
					Bauwerke = {}, Wurzellos = 0,
				}
				staedte[stadt] = eintrag
			end

			local leben = haus:GetAttribute("MaxHealth")
			local alarm = haus:GetAttribute("AlertValue")
			local energie = haus:GetAttribute("EnergyType")
			local bauwerk, wurzellos = abschnittVon(haus)
			if wurzellos then
				eintrag.Wurzellos += 1
			end
			local gehoertZu = bauwerk and bauwerk.Name or (wurzellos and "(Wurzel fehlt)" or nil)

			-- Ein eigenstaendiges Haus ist sein eigenes Bauwerk.
			local schluesselBauwerk = bauwerk or haus
			local summe = eintrag.Bauwerke[schluesselBauwerk]
			if not summe then
				summe = { Typ = BuildingConfig and BuildingConfig.GetTypeName(schluesselBauwerk, stadt) or schluesselBauwerk.Name, Leben = 0, Energien = {} }
				eintrag.Bauwerke[schluesselBauwerk] = summe
			end
			summe.Leben += leben or 0
			if energie then
				summe.Energien[energie] = true
			end

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

-- ===== Abgleich Studio gegen BuildingConfig =====
-- Meldet nur, was ABWEICHT. Eine Liste, die bei jedem Start 94 Zeilen "passt" ausgibt,
-- liest nach dem dritten Mal niemand mehr -- und genau dann faellt die eine Zeile nicht
-- auf, die nicht passt.
local function abgleich(stadt, eintrag)
	local soll = BuildingConfig and BuildingConfig[stadt]
	if not soll then
		print(string.format("-- Abgleich: fuer %s stehen keine Soll-Werte in BuildingConfig.", stadt))
		return
	end

	-- Je Typ die Lebenspunkte aller seiner Instanzen sammeln.
	local jeTyp = {}
	local typReihenfolge = {}
	for _, bauwerk in pairs(eintrag.Bauwerke) do
		local zusammen = jeTyp[bauwerk.Typ]
		if not zusammen then
			zusammen = { Anzahl = 0, Kleinstes = math.huge, Groesstes = 0, Energien = {} }
			jeTyp[bauwerk.Typ] = zusammen
			table.insert(typReihenfolge, bauwerk.Typ)
		end
		zusammen.Anzahl += 1
		zusammen.Kleinstes = math.min(zusammen.Kleinstes, bauwerk.Leben)
		zusammen.Groesstes = math.max(zusammen.Groesstes, bauwerk.Leben)
		for energie in pairs(bauwerk.Energien) do
			zusammen.Energien[energie] = true
		end
	end
	table.sort(typReihenfolge)

	local meldungen = {}
	local passend = 0

	for _, typ in ipairs(typReihenfolge) do
		local ist = jeTyp[typ]
		local sollEintrag = soll[typ]

		if not sollEintrag then
			table.insert(meldungen, string.format("%s (%dx): steht nicht in BuildingConfig.%s",
				typ, ist.Anzahl, stadt))
		else
			local sollLeben = sollEintrag.MaxHealth
			local istText = ist.Kleinstes == ist.Groesstes
				and tostring(ist.Kleinstes)
				or string.format("%d bis %d -- die Instanzen sind untereinander uneinig",
					ist.Kleinstes, ist.Groesstes)

			if ist.Kleinstes == sollLeben and ist.Groesstes == sollLeben then
				passend += 1
			else
				table.insert(meldungen, string.format("%s (%dx): ist %s, soll %d%s",
					typ, ist.Anzahl, istText, sollLeben,
					ist.Kleinstes > 0 and ist.Kleinstes == ist.Groesstes
						and string.format("  (Faktor %.1f)", sollLeben / ist.Kleinstes)
						or ""))
			end

			if sollEintrag.EnergyType then
				for energie in pairs(ist.Energien) do
					if energie ~= sollEintrag.EnergyType then
						table.insert(meldungen, string.format("%s: EnergyType ist %q, soll %q",
							typ, energie, sollEintrag.EnergyType))
					end
				end
			end
		end
	end

	-- Der umgekehrte Fall: in der Config festgelegt, in der Welt nicht zu finden. Meist ein
	-- Tippfehler im Namen -- und der wuerde sonst still nie greifen.
	local sollNamen = {}
	for typ in pairs(soll) do
		table.insert(sollNamen, typ)
	end
	table.sort(sollNamen)
	for _, typ in ipairs(sollNamen) do
		if not jeTyp[typ] then
			table.insert(meldungen, string.format("%s: steht in der Config, kommt in der Welt nicht vor.", typ))
		end
	end

	if #meldungen == 0 then
		print(string.format("-- Abgleich %s: alle %d Gebaeudetypen stimmen mit BuildingConfig ueberein.",
			stadt, passend))
		return
	end

	print(string.format("-- Abgleich %s: %d Typen passen, %d Meldungen.", stadt, passend, #meldungen))
	for _, meldung in ipairs(meldungen) do
		print("--   " .. meldung)
	end
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
		if eintrag.Wurzellos > 0 then
			warn(string.format("[Kaiju Debug] Gebaeudebericht: %d Teile in %s sind als Abschnitt "
				.. "markiert (RespawnMode = ParentGroup), haben aber kein Bauwerk ueber sich. "
				.. "Sie respawnen nie mit einer Gruppe.", eintrag.Wurzellos, stadt))
		end
		abgleich(stadt, eintrag)
		print("")
	end
end

return M
