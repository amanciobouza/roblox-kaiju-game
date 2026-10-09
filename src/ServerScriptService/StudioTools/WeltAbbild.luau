--============================================================
-- STUDIO-WERKZEUG: die Welt als Lua ins Repo
--
-- ===== So wird es benutzt =====
-- In Studio, im BEARBEITUNGSMODUS, in der Command Bar:
--
--   require(game.ServerScriptService.StudioTools.WeltAbbild:Clone()).Print()
--
-- Dann im Output alles markieren, kopieren und nach
-- src/ReplicatedStorage/WeltAbbild.luau einfuegen. Das Ergebnis ist ein gueltiges
-- Lua-Modul -- keine Tabelle zum Abtippen, sondern eine Datei zum Ablegen.
--
-- Mit einem Namen nur ein Ausschnitt, falls die Ausgabe zu lang wird:
--   ....Print("City")
--
-- ===== Warum es das gibt =====
-- Der Workspace liegt NICHT im Repo. Terrain, Modelle und Platzierungen existieren
-- ausschliesslich in Amancios Place-Datei. Geht sie verloren, ist das Spiel weg -- und
-- zwar der Teil, den kein Skript wiederherstellen kann: wo die Haeuser stehen, welche
-- Stadt sie sind, wie viele Lebenspunkte jedes hat, wo die Barrikaden-Marker liegen.
--
-- Das ist die groesste Luecke der ganzen Architektur, und sie ist keine Design-Frage
-- (Stand 30.09.2026).
--
-- ===== Was es sichert und was NICHT =====
-- GESICHERT wird, was ein Mensch platziert und eingetippt hat:
--   * jede Instanz mit mindestens einem Tag oder mindestens einem Attribut
--   * ihr Pfad unter dem Workspace, ihre Klasse, ihre vollstaendige CFrame
--   * alle ihre Tags und Attribute
--
-- NICHT gesichert wird die Geometrie: die Teile, Meshes und Texturen. Die kommen aus
-- Vorlagen (ServerStorage.KaijuModels, HiddenHouses, den Installern, dem Asset-Workshop)
-- und stehen damit ohnehin im Repo oder lassen sich neu bauen. Genau diese Trennung macht
-- das Abbild klein genug, um es ueberhaupt fuehren zu koennen: rund 300 Eintraege statt
-- 33 000 Teile.
--
-- Es ist ein PROTOKOLL, noch keine Wiederherstellung. Zum Zurueckspielen braucht es ein
-- zweites Werkzeug, das die Vorlagen an die festgehaltenen CFrames setzt. Das lohnt erst,
-- wenn das Abbild einmal steht -- ohne Daten gibt es nichts zurueckzuspielen.
--============================================================

local M = {}

M.VERSION = "WeltAbbild_v01"

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- Ordner, die nichts zur Welt beitragen: erzeugte Figuren, Effekte, Trümmer. Sie tragen
-- zur Laufzeit Tags und Attribute und wuerden das Abbild mit Wegwerfzeug fluten.
local UEBERSPRINGEN = {
	Terrain = true,
	Camera = true,
	Debris = true,
	Effects = true,
	Ruins = true,
}

local function pfadUnterWorkspace(instanz)
	local teile = {}
	local knoten = instanz
	while knoten and knoten ~= Workspace do
		table.insert(teile, 1, knoten.Name)
		knoten = knoten.Parent
	end
	return table.concat(teile, ".")
end

-- Attribute koennen Typen haben, die sich nicht als Lua-Literal schreiben lassen. Was
-- hier nicht bekannt ist, wird GEMELDET und nicht stillschweigend weggelassen -- ein
-- fehlendes Attribut im Abbild waere beim Zurueckspielen nicht zu bemerken.
local function alsLua(wert)
	local art = typeof(wert)
	if art == "number" then
		-- %.6g haelt ganze Zahlen ganz und schneidet Fliesskomma sinnvoll ab.
		return string.format("%.6g", wert)
	elseif art == "string" then
		return string.format("%q", wert)
	elseif art == "boolean" then
		return tostring(wert)
	elseif art == "Vector3" then
		return string.format("Vector3.new(%.4f, %.4f, %.4f)", wert.X, wert.Y, wert.Z)
	elseif art == "Color3" then
		return string.format("Color3.new(%.4f, %.4f, %.4f)", wert.R, wert.G, wert.B)
	elseif art == "CFrame" then
		return string.format("CFrame.new(%s)", table.concat({ wert:GetComponents() }, ", "))
	end
	return nil, art
end

local function cframeVon(instanz)
	if instanz:IsA("BasePart") then
		return instanz.CFrame
	end
	if instanz:IsA("Model") then
		local ok, pivot = pcall(function()
			return instanz:GetPivot()
		end)
		if ok then
			return pivot
		end
	end
	return nil
end

-- Sammelt alles, was ein Mensch angefasst hat: Tag oder Attribut.
local function sammle(nurStadt)
	local eintraege = {}

	for _, instanz in ipairs(Workspace:GetDescendants()) do
		local ueberspringen = false
		local knoten = instanz
		while knoten and knoten ~= Workspace do
			if UEBERSPRINGEN[knoten.Name] then
				ueberspringen = true
				break
			end
			knoten = knoten.Parent
		end

		if not ueberspringen then
			local attribute = instanz:GetAttributes()
			local tags = CollectionService:GetTags(instanz)
			local hatAttribute = next(attribute) ~= nil

			if hatAttribute or #tags > 0 then
				local pfad = pfadUnterWorkspace(instanz)
				if not nurStadt or pfad:find(nurStadt, 1, true) then
					table.insert(eintraege, {
						pfad = pfad,
						klasse = instanz.ClassName,
						cframe = cframeVon(instanz),
						tags = tags,
						attribute = attribute,
					})
				end
			end
		end
	end

	table.sort(eintraege, function(a, b)
		return a.pfad < b.pfad
	end)

	return eintraege
end

function M.Print(nurStadt)
	local eintraege = sammle(nurStadt)

	if #eintraege == 0 then
		warn(string.format("[Kaiju Debug] %s: nichts gefunden%s. Laeuft das im "
			.. "Bearbeitungsmodus, und ist der Workspace geladen?",
			M.VERSION, nurStadt and (" fuer '" .. nurStadt .. "'") or ""))
		return
	end

	print("-- Welt-Abbild (" .. M.VERSION .. "), erzeugt aus Studio.")
	print("-- Kopieren nach src/ReplicatedStorage/WeltAbbild.luau.")
	print("--")
	print("-- Festgehalten ist, was ein Mensch platziert und eingetippt hat: Pfad, Klasse,")
	print("-- CFrame, Tags und Attribute. NICHT die Geometrie -- die kommt aus Vorlagen.")
	print(string.format("-- %d Eintraege%s.", #eintraege,
		nurStadt and (", gefiltert auf '" .. nurStadt .. "'") or ""))
	print("")
	print("return {")

	local uebersprungeneWerte = 0
	for _, eintrag in ipairs(eintraege) do
		local zeile = { string.format("\t[%q] = { Klasse = %q", eintrag.pfad, eintrag.klasse) }

		if eintrag.cframe then
			table.insert(zeile, string.format("CFrame = CFrame.new(%s)",
				table.concat({ eintrag.cframe:GetComponents() }, ", ")))
		end

		if #eintrag.tags > 0 then
			local tagListe = {}
			for _, tag in ipairs(eintrag.tags) do
				table.insert(tagListe, string.format("%q", tag))
			end
			table.insert(zeile, "Tags = { " .. table.concat(tagListe, ", ") .. " }")
		end

		-- Attribute in stabiler Reihenfolge: sonst sieht jede Ausgabe anders aus und der
		-- Unterschied zweier Abbilder waere nicht zu lesen.
		local namen = {}
		for name in pairs(eintrag.attribute) do
			table.insert(namen, name)
		end
		table.sort(namen)

		if #namen > 0 then
			local paare = {}
			for _, name in ipairs(namen) do
				local text, unbekannt = alsLua(eintrag.attribute[name])
				if text then
					table.insert(paare, string.format("%s = %s", name, text))
				else
					uebersprungeneWerte += 1
					warn(string.format("[Kaiju Debug] %s: Attribut %q an %q hat den Typ %q "
						.. "und fehlt im Abbild -- alsLua() kennt ihn nicht.",
						M.VERSION, name, eintrag.pfad, tostring(unbekannt)))
				end
			end
			if #paare > 0 then
				table.insert(zeile, "Attribute = { " .. table.concat(paare, ", ") .. " }")
			end
		end

		print(table.concat(zeile, ", ") .. " },")
	end

	print("}")
	print("")
	print(string.format("-- Ende. %d Eintraege%s.", #eintraege,
		uebersprungeneWerte > 0
			and string.format(", ACHTUNG: %d Attributwerte fehlen (siehe Warnungen oben)",
				uebersprungeneWerte)
			or ""))
end

return M
