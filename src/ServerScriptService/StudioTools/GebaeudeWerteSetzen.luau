--============================================================
-- STUDIO-WERKZEUG: die Werte aus BuildingConfig an die Modelle schreiben
--
-- ===== So wird es benutzt =====
-- In Studio, in der Command Bar. ERST schauen:
--
--   require(game.ServerScriptService.StudioTools.GebaeudeWerteSetzen).Vorschau("City")
--
-- Dann, wenn die Liste stimmt:
--
--   require(game.ServerScriptService.StudioTools.GebaeudeWerteSetzen).Anwenden("City")
--
-- Danach die Place SPEICHERN -- das Werkzeug aendert Attribute an Modellen im Workspace,
-- und der Workspace liegt nicht im Repo.
--
-- Laeuft im BEARBEITUNGSMODUS. Im Playtest waere es sinnlos: die Aenderung verschwaende mit
-- der Sitzung, und genau dieses Missverstaendnis kostet sonst einen Abend.
--
-- ===== Warum es das gibt =====
-- Die Lebenspunkte der Gebaeude stehen als Attribute an rund hundert Instanzen in Studio.
-- Sie von Hand nachzuziehen heisst hundert Gelegenheiten, sich zu vertippen -- und ein
-- Tippfehler faellt nicht auf, er macht nur ein Haus zu weich. Genau so ist
-- TB_City_FireStation_L2 zu seinen hundert Lebenspunkten gekommen.
--
-- Das Werkzeug schreibt nur, was in BuildingConfig steht, und meldet jeden Fall, den es
-- NICHT zuordnen kann, statt ihn stillschweigend zu ueberspringen.
--
-- ===== Was es ausdruecklich NICHT ist =====
-- Es ist kein Dienst. Nichts im laufenden Spiel ruft es auf, und es soll auch nichts.
-- Die Werte bleiben nach dem Lauf Studio-Attribute wie bisher -- das Werkzeug tippt nur
-- schneller und richtiger als ein Mensch. Der Schritt, die Config zur Laufzeit ANZUWENDEN,
-- ist ein anderer und bewusst nicht gegangen.
--============================================================

local M = {}

M.VERSION = "GebaeudeWerteSetzen_v01"

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HOUSE_TAG = "KaijuHouse"

-- Beide Module muessen da sein, sonst hat das Werkzeug nichts zu tun. Ohne Zeitgrenze
-- wuerde es bei fehlendem Rojo-Sync stumm haengen -- man sieht dann gar nichts und sucht
-- den Fehler im Spiel statt in der Synchronisation.
--
-- Geholt wird immer ein KLON. Sonst reicht es nicht, dieses Werkzeug frisch zu laden: die
-- Module, die es selbst requiret, kaemen weiter aus dem Zwischenspeicher der Sitzung. Genau
-- daran ist der erste Lauf gescheitert -- das Werkzeug war neu, sein BuildingConfig war es
-- nicht, und es meldete eine Stadt als unbekannt, die in der Datei laengst stand.
--
-- Vertretbar, weil hier nur Daten gelesen werden und beides reine Datenmodule sind. Fuer
-- einen Dienst im laufenden Spiel waere es falsch -- dort ist der Zwischenspeicher der Sinn
-- der Sache.
local function holen(eltern, name)
	local modul = eltern:WaitForChild(name, 10)
	if not modul then
		error(string.format("%s: %q liegt nicht in %s. Hat Rojo synchronisiert?",
			M.VERSION, name, eltern:GetFullName()), 0)
	end
	return require(modul:Clone())
end

local BuildingConfig = holen(ReplicatedStorage, "BuildingConfig")

-- Dieselbe Aufloesung wie der Bericht, aus dem Bericht geholt. Siehe dort.
-- Ueber ServerScriptService statt ueber script.Parent, damit auch ein Klon dieses Moduls
-- laeuft -- ein Klon hat keinen Parent. Klone sind hier kein Sonderfall, sondern der
-- uebliche Weg, den Require-Zwischenspeicher zu umgehen (siehe Kopf der Datei).
local werkzeuge = game:GetService("ServerScriptService"):WaitForChild("StudioTools", 10)
if not werkzeuge then
	error(M.VERSION .. ": ServerScriptService.StudioTools fehlt. Hat Rojo synchronisiert?", 0)
end
local Bericht = holen(werkzeuge, "GebaeudeBericht")

-- Ermittelt den Soll-Wert eines einzelnen getaggten Teils.
-- Rueckgabe: leben, energie, grund
--   leben == nil heisst "nicht zuordenbar", grund sagt warum.
local function sollWertFuer(haus, sollStadt)
	local bauwerk, wurzellos = Bericht.BauwerkVon(haus)
	if wurzellos then
		return nil, nil, "als Abschnitt markiert, aber ohne Bauwerk darueber"
	end

	local typ = BuildingConfig.GetTypeName(bauwerk or haus, Bericht.StadtVon(haus))
	local eintrag = sollStadt[typ]
	if not eintrag then
		return nil, nil, string.format("Typ %q steht nicht in BuildingConfig", typ)
	end

	if eintrag.Abschnitte then
		local wert = eintrag.Abschnitte[haus.Name]
		if not wert then
			return nil, nil, string.format(
				"Abschnitt %q von %q steht nicht in der Aufteilung", haus.Name, typ)
		end
		return wert, eintrag.EnergyType, nil
	end

	if bauwerk then
		-- Ein Bauwerk ohne Aufteilung, aber mit Abschnitten in der Welt: wuerde man hier
		-- den vollen Wert an JEDEN Abschnitt schreiben, haette das Bauwerk am Ende ein
		-- Vielfaches davon. Lieber melden als falsch rechnen.
		return nil, nil, string.format(
			"%q hat in der Welt Abschnitte, in der Config aber keine Aufteilung", typ)
	end

	return eintrag.MaxHealth, eintrag.EnergyType, nil
end

-- Skripte werden im Repo gepflegt. Hier werden lediglich deren Rojo-Vorlagen geklont.
local function megaRuntimeVorlagen()
	local template = game:GetService("ServerStorage"):FindFirstChild("MegaCityFinalAssembly")
	assert(template, "MegaCityFinalAssembly fehlt in ServerStorage; zuerst Rojo synchronisieren")
	local buildings = template:FindFirstChild("Buildings")
	assert(buildings, "MegaCity-Vorlage hat keinen Buildings-Ordner")
	local result = {}
	for _, model in ipairs(buildings:GetChildren()) do
		local typ = BuildingConfig.GetTypeName(model, "MegaCity")
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("Script") and child.Source:find("local function runtimeModule()", 1, true) then
				result[typ] = child
			end
		end
	end
	return result
end

local function durchlauf(stadt, schreiben)
	if (stadt == "LargeCity" or stadt == "MegaCity") and schreiben then
		assert(not game:GetService("RunService"):IsRunning(), "Gebaeude-HP im Bearbeitungsmodus setzen")
	end
	local sollStadt = BuildingConfig[stadt]
	if not sollStadt then
		warn(string.format("[Kaiju Debug] %s: fuer %q stehen keine Werte in BuildingConfig. "
			.. "Bekannt sind Village, SmallTown, City, LargeCity und MegaCity.", M.VERSION, tostring(stadt)))
		return
	end

	local vorlagen = stadt == "MegaCity" and megaRuntimeVorlagen() or {}
	local aenderungen, meldungen = {}, {}
	local unveraendert, teile = 0, 0

	for _, haus in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		if Bericht.StadtVon(haus) == stadt then
			teile += 1
			local soll, energie, grund = sollWertFuer(haus, sollStadt)
			if not soll then
				table.insert(meldungen, string.format("%s: %s", haus:GetFullName(), grund))
			else
				local typ = BuildingConfig.GetTypeName(haus, stadt)
				local vorlage = vorlagen[typ]
				local runtime = vorlage and haus:FindFirstChild(vorlage.Name)
				local runtimeFalsch = vorlage and (not runtime or not runtime:IsA("Script") or runtime.Source ~= vorlage.Source)
				local ist = haus:GetAttribute("MaxHealth")
				local istEnergie = haus:GetAttribute("EnergyType")
				local energieFalsch = energie ~= nil and istEnergie ~= energie

				if ist == soll and not energieFalsch and not runtimeFalsch then
					unveraendert += 1
				else
					table.insert(aenderungen, {
						Haus = haus, Ist = ist, Soll = soll,
						Runtime = runtimeFalsch and runtime or nil, Vorlage = runtimeFalsch and vorlage or nil,
						IstEnergie = istEnergie, SollEnergie = energieFalsch and energie or nil,
					})
				end
			end
		end
	end

	if teile == 0 then
		warn(string.format("[Kaiju Debug] %s: keine getaggten Gebaeude in %q gefunden -- "
			.. "traegt der Stadtordner das Attribut CityName?", M.VERSION, stadt))
		return
	end

	-- Beide Endstaedte werden erst geschrieben, wenn der gesamte Bestand zugeordnet ist.
	if (stadt == "LargeCity" or stadt == "MegaCity") and schreiben and #meldungen > 0 then
		for _, meldung in ipairs(meldungen) do warn("[" .. stadt .. " HP] " .. meldung) end
		error(stadt .. ": unbekannte Typen/Abschnitte; keine Gebaeudewerte geschrieben")
	end

	table.sort(aenderungen, function(a, b)
		return a.Haus:GetFullName() < b.Haus:GetFullName()
	end)

	print(string.format("-- ===== %s: %s, %d Teile =====",
		M.VERSION, schreiben and "ANWENDEN" or "Vorschau", teile))

	for _, a in ipairs(aenderungen) do
		local text = string.format("%s: MaxHealth %s -> %d",
			a.Haus:GetFullName(), tostring(a.Ist), a.Soll)
		if a.SollEnergie then
			text ..= string.format(", EnergyType %s -> %q", tostring(a.IstEnergie), a.SollEnergie)
		end
		if a.Vorlage then text ..= ", Gebaeudeskript aus Rojo-Vorlage aktualisieren" end
		print("--   " .. text)

		if schreiben then
			a.Haus:SetAttribute("MaxHealth", a.Soll)
			if stadt == "LargeCity" or stadt == "MegaCity" then
				a.Haus:SetAttribute("Health", a.Soll)
			end
			if a.Vorlage then
				local replacement = a.Vorlage:Clone()
				if a.Runtime then
					replacement.Disabled = a.Runtime.Disabled
					a.Runtime:Destroy()
				end
				replacement.Parent = a.Haus
			end
			if a.SollEnergie then
				a.Haus:SetAttribute("EnergyType", a.SollEnergie)
			end
		end
	end

	for _, meldung in ipairs(meldungen) do
		warn("[Kaiju Debug] " .. M.VERSION .. " uebersprungen -- " .. meldung)
	end

	print(string.format("-- %d geaendert%s, %d standen schon richtig, %d uebersprungen.",
		#aenderungen, schreiben and "" or " (waeren)", unveraendert, #meldungen))

	if schreiben and #aenderungen > 0 then
		print("-- Jetzt die Place SPEICHERN, sonst ist die Aenderung mit dem naechsten "
			.. "Schliessen weg.")
	end
end

function M.Vorschau(stadt)
	durchlauf(stadt, false)
end

function M.Anwenden(stadt)
	durchlauf(stadt, true)
end

return M
