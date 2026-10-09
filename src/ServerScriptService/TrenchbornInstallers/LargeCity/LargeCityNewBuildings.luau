--============================================================
-- TRENCHBORN INSTALLER
-- LARGE CITY -- die neun Bauwerke auf einmal
--
--   Hotel       LargeCity_LuxuryWaterfrontResort_L3
--   Spital      LargeCity_CentralHospital_L3
--   Stadion     LargeCity_Stadium_L3   ACHTUNG, siehe unten
--   Arena       LargeCity_UptownArena_L3
--   Turm        LargeCity_SummitTower_L3
--   Wohnen      LargeCity_UptownResidences_L3
--   Sporthotel  LargeCity_StadiumHotel_L3
--   Parkhaus    LargeCity_UptownParking_L3
--   Chemie      LargeCity_MeridianPharma_L3
--
-- ===== So wird es benutzt =====
-- In Studio, in der Command Bar, EINE Zeile:
--
--   require(game.ServerScriptService.TrenchbornInstallers.LargeCity.LargeCityNewBuildings).Install()
--
-- Danach stehen alle neun in der Welt, zerstoerbar und mit Belohnung. Sie landen in einer
-- Reihe am Rand der bestehenden Stadt -- schieb sie in Studio an ihren Platz und speichere.
-- Die Meldung am Ende nennt jede Position.
--
-- Vorhandene aeltere Fassungen werden dabei ENTFERNT: jedes Paket bringt sein eigenes
-- Uninstall mit, und das laeuft vor dem Neubau.
--
-- Zum Rueckgaengigmachen: .Uninstall()
--
-- ===== Was sich am 19.09.2026 geaendert hat =====
-- Die Bauwerke kommen jetzt als VOLLSTAENDIGE Pakete aus dem Asset-Workshop: jedes bringt
-- seinen eigenen Installer mit, der Geometrie, Dressing UND die Spielwerte setzt --
-- Lebenspunkte, EnergyType, KaijuHouse-Tag, Zerstoerungsgruppen.
--
-- Vorher hatte nur das Hotel einen; fuer Spital, Stadion und Arena musste dieses Modul die
-- Ausstattung nachbauen, sonst waeren sie blosse Kulisse gewesen. Das faellt damit weg --
-- und mit ihm die Gefahr, dass die hier nachgebauten Werte von denen des Pakets abweichen.
-- Dieses Modul stellt jetzt nur noch auf, was die Pakete liefern.
--
-- Am selben Tag kamen Turm, Wohnen und Sporthotel dazu, tags darauf das Parkhaus --
-- acht statt vier, und am 20.09. kam die Chemiefabrik dazu. Sie ist zugleich das erste
-- Bauwerk im Viertel MedicalTech -- die acht davor liegen alle in Uptown oder am Wasser.
--
-- Offen bleibt nur noch das Kraftwerk: seinem Zweig fehlt der Installer, und ohne ihn
-- waere es blosse Kulisse.
--============================================================

local M = {}

M.VERSION = "LargeCityNewBuildings_v08"

-- Studios Verlauf. Damit macht Strg+Z einen Einbau rueckgaengig -- ohne diese Marken
-- sind Aenderungen aus der Command Bar unwiderruflich, und genau das hat am
-- 20.09.2026 wehgetan.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local HOUSE_TAG = "KaijuHouse"
local CITY_NAME = "LargeCity"
local LUECKE = 40

-- Reihenfolge = Reihenfolge des Abstellens. Jeder Eintrag ist der Name des Installers im
-- Paket; alles Weitere -- Modellname, Lebenspunkte, Energietyp -- steht dort und wird hier
-- bewusst NICHT wiederholt.
local BAUWERKE = {
	{ Name = "Hotel", Installer = "LargeCityWaterfrontResortInstaller" },
	{ Name = "Spital", Installer = "LargeCityCentralHospitalInstaller" },
	-- Das Stadion bekommt sein dekoratives Pong mit. Das SPIELBARE baut
	-- StadiumPongService beim Serverstart darueber (es raeumt das dekorative weg und setzt
	-- eigene Teile auf dieselben Feldmasse). Beides hier einzuschalten ist trotzdem
	-- richtig: faellt der Dienst je aus, steht im Stadion weiterhin ein Pong.
	--
	-- ===== ACHTUNG: der Name weicht ab (04.10.2026) =====
	-- In der Welt heisst das Stadion "LargeCityStadium", und StadiumPongService sucht
	-- genau danach. DIESER Installer vergibt aber weiterhin "LargeCity_Stadium_L3" -- der
	-- Name steht im Paket (LargeCityStadiumSpecification.AssetId) und damit im Submodul,
	-- nicht hier.
	--
	-- Wer den Installer heute erneut laufen laesst, bekommt also ein Stadion, in dem Pong
	-- NICHT anspringt -- und im Zweifel ein zweites neben dem bestehenden. Entweder danach
	-- von Hand umbenennen, oder die AssetId im Workshop-Zweig nachziehen und das Submodul
	-- mergen (siehe CLAUDE.md, "Submodul aktualisieren").
	{ Name = "Stadion", Installer = "LargeCityStadiumInstaller", Optionen = { EnablePong = true } },
	{ Name = "Arena", Installer = "LargeCityUptownArenaInstaller" },
	{ Name = "Turm", Installer = "LargeCitySummitTowerInstaller" },
	{ Name = "Wohnen", Installer = "LargeCityUptownResidencesInstaller" },
	{ Name = "Sporthotel", Installer = "LargeCityStadiumHotelInstaller" },
	{ Name = "Parkhaus", Installer = "LargeCityUptownParkingInstaller" },
	{ Name = "Chemie", Installer = "LargeCityMeridianPharmaInstaller" },
}

------------------------------------------------------------
-- Hilfen
------------------------------------------------------------

local function paket()
	local ordner = ReplicatedStorage:WaitForChild("TrenchbornAssetWorkshop", 10)
	assert(ordner, "ReplicatedStorage.TrenchbornAssetWorkshop fehlt -- laeuft Rojo?")
	return ordner
end

local function installerVon(ordner, name)
	local eintrag = ordner:WaitForChild(name, 10)
	assert(eintrag, "Workshop-Modul '" .. name .. "' fehlt -- zeigt das Submodul auf "
		.. "'game-integration', und ist es aktuell?")
	return require(eintrag)
end

-- ===== Die Stadt finden, auch wenn sie leer ist =====
-- Hier wurde zuerst von einem getaggten GEBAEUDE aus nach oben gesucht. Das ging genau so
-- lange gut, wie die Stadt schon bebaut war -- wer ihre alten Bauwerke wegwirft, um die
-- neuen zu setzen, steht danach vor "Keine LargeCity gefunden". Der Anker war die
-- Bebauung, und gesucht war die Stadt.
--
-- Jetzt wird nach dem Ort selbst gesucht: nach dem Attribut CityName, das der
-- Stadt-Container traegt (dieselbe Angabe, ueber die auch CityAlertService zuordnet). Ein
-- leerer Ordner wird damit genauso gefunden wie ein voller.
local function stadtOrdner()
	-- Erst der uebliche Ort. Das spart den grossen Durchlauf im Normalfall.
	local staedte = Workspace:FindFirstChild("Cities")
	if staedte then
		for _, knoten in ipairs(staedte:GetChildren()) do
			if knoten:GetAttribute("CityName") == CITY_NAME then
				return knoten
			end
		end
	end

	-- Sonst die ganze Welt. Ein einmaliges Studio-Werkzeug darf sich das leisten, und es
	-- ist allemal besser als eine Fehlermeldung, die nur den halben Grund nennt.
	for _, knoten in ipairs(Workspace:GetDescendants()) do
		if knoten:GetAttribute("CityName") == CITY_NAME then
			return knoten
		end
	end

	-- Zuletzt ueber den Namen. Nur als Rueckfall: der Ordner heisst in Studio nicht
	-- zwingend wie die Stadt -- Brasshaven liegt unter "Smalltown".
	if staedte then
		for _, knoten in ipairs(staedte:GetChildren()) do
			if string.lower(knoten.Name) == string.lower(CITY_NAME) then
				return knoten
			end
		end
	end
	return nil
end

-- Wo die bestehende Stadt aufhoert und auf welcher Hoehe sie steht.
local function stadtGrenzen(ordner)
	local maxX, minY, minZ, maxZ = -math.huge, math.huge, math.huge, -math.huge
	local gefunden = false
	for _, haus in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		if haus:IsDescendantOf(ordner) and haus:IsA("Model") then
			local ok, rahmen, groesse = pcall(function()
				return haus:GetBoundingBox()
			end)
			if ok and rahmen then
				gefunden = true
				maxX = math.max(maxX, rahmen.Position.X + groesse.X * 0.5)
				minY = math.min(minY, rahmen.Position.Y - groesse.Y * 0.5)
				minZ = math.min(minZ, rahmen.Position.Z - groesse.Z * 0.5)
				maxZ = math.max(maxZ, rahmen.Position.Z + groesse.Z * 0.5)
			end
		end
	end
	if not gefunden then
		return nil
	end
	return { MaxX = maxX, MinY = minY, MitteZ = (minZ + maxZ) * 0.5 }
end

------------------------------------------------------------
-- Einbau
------------------------------------------------------------

-- ===== Install fasst nichts an, was schon steht =====
-- Am 20.09.2026 hat .Install() alle neun zurueckgenommen und neu in die Reihe gestellt --
-- und damit die Arbeit vernichtet, die Amancio zuvor mit dem Platzieren hatte. Ein
-- Werkzeug, das man zweimal aufruft, darf beim zweiten Mal nicht zerstoeren, was nach dem
-- ersten Mal entstanden ist.
--
-- Deshalb gilt jetzt: WAS SCHON IN DER WELT STEHT, BLEIBT UNBERUEHRT. Gesetzt wird nur,
-- was fehlt.
--
--   .Install()                    -- setzt die fehlenden, ruehrt vorhandene nicht an
--   .Install(nil, "Chemie")       -- nur dieses eine, und ersetzt es auch wenn es steht
--   .Neuaufstellen()              -- das alte Verhalten, ausdruecklich verlangt
--
-- Zusaetzlich setzt jeder Aufruf eine Marke in Studios Verlauf: Strg+Z macht ihn rueckgaengig.
function M.Install(zielOrdner, nurName, alleNeu)
	local ordner = paket()
	local stadt = zielOrdner or stadtOrdner()
	assert(stadt, "Keine LargeCity gefunden -- kein Objekt in der Welt traegt das Attribut "
		.. "CityName = 'LargeCity', und unter Workspace.Cities gibt es auch keinen Ordner "
		.. "dieses Namens. Sonst den Ordner direkt uebergeben: "
		.. ".Install(workspace.Cities.LargeCity)")

	local grenzen = stadtGrenzen(stadt)
	local x = grenzen and (grenzen.MaxX + LUECKE) or 0
	local bodenY = grenzen and grenzen.MinY or 0
	local z = grenzen and grenzen.MitteZ or 0

	pcall(function()
		ChangeHistoryService:SetWaypoint("LargeCity-Einbau davor")
	end)

	print("[Kaiju Debug] LargeCity-Einbau in '" .. stadt:GetFullName() .. "' -- " .. M.VERSION)

	if nurName then
		local bekannt = false
		for _, bauwerk in ipairs(BAUWERKE) do
			if bauwerk.Name == nurName then
				bekannt = true
			end
		end
		assert(bekannt, "Unbekanntes Bauwerk '" .. tostring(nurName) .. "'. Moeglich sind: "
			.. "Hotel, Spital, Stadion, Arena, Turm, Wohnen, Sporthotel, Parkhaus, Chemie.")
	end

	local gesetzt = 0
	for _, bauwerk in ipairs(BAUWERKE) do
		if nurName and bauwerk.Name ~= nurName then
			continue
		end
		local installer = installerVon(ordner, bauwerk.Installer)

		-- Steht es schon? Dann in Ruhe lassen -- es sei denn, es ist ausdruecklich GEMEINT
		-- (nurName) oder es wird ausdruecklich neu aufgestellt (alleNeu).
		local vorhanden = installer.ModelName and stadt:FindFirstChild(installer.ModelName)
		if vorhanden and not nurName and not alleNeu then
			print(string.format("[Kaiju Debug]   %-10s steht bereits -- unberuehrt gelassen.",
				bauwerk.Name))
			continue
		end

		-- Die alte Fassung zuerst weg. Das Paket kennt seinen eigenen Modellnamen und
		-- raeumt auch Reste seines GoldenMasters auf -- besser als hier Namen zu raten.
		pcall(function()
			installer.Uninstall(stadt)
		end)

		local optionen = {}
		for schluessel, wert in pairs(bauwerk.Optionen or {}) do
			optionen[schluessel] = wert
		end
		-- Abstellen auf Stadthoehe. Das Paket richtet selbst am Boden aus, es braucht dafuer
		-- nur zu wissen, wo der Boden liegt.
		optionen.CFrame = CFrame.new(x, bodenY, z)
		optionen.GroundCFrame = CFrame.new(x, bodenY, z)

		local model = installer.Install(stadt, optionen)

		-- Jedes Paket bringt eine eigene Pruefung mit. Sie hier auszulassen hiesse, sich auf
		-- "hat nicht geworfen" zu verlassen -- und genau so sind frueher Bauwerke ohne
		-- Lebenspunkte in der Welt gelandet.
		local geprueft, fehler = true, nil
		if type(installer.Validate) == "function" then
			geprueft, fehler = pcall(function()
				return installer.Validate(model)
			end)
		end

		gesetzt += 1
		local ort = model:GetPivot().Position
		print(string.format("[Kaiju Debug]   %-10s '%s' bei %.0f, %.0f, %.0f -- %s Lebenspunkte, "
			.. "%s, %s.", bauwerk.Name, model.Name, ort.X, ort.Y, ort.Z,
			tostring(model:GetAttribute("MaxHealth")),
			tostring(model:GetAttribute("EnergyType")),
			CollectionService:HasTag(model, HOUSE_TAG) and "zerstoerbar" or "OHNE TAG"))
		if not geprueft then
			warn("[Kaiju Debug]   " .. bauwerk.Name .. ": Paket-Pruefung schlug fehl -- "
				.. tostring(fehler))
		end

		local ok, _, groesse = pcall(function()
			return model:GetBoundingBox()
		end)
		x += ((ok and groesse) and groesse.X or 100) + LUECKE
	end

	print(string.format("[Kaiju Debug] %d Bauwerk(e) gesetzt. %s in Studio an den Platz "
		.. "schieben und speichern.", gesetzt,
		gesetzt > 1 and "Sie stehen in einer Reihe am oestlichen Rand --" or "Es steht am oestlichen Rand --"))
	pcall(function()
		ChangeHistoryService:SetWaypoint("LargeCity-Einbau")
	end)
	return gesetzt
end

-- Alle neun zurueckziehen und neu in die Reihe stellen. Das war frueher das Verhalten von
-- Install und hat unbemerkt Platzierungsarbeit vernichtet -- jetzt muss man es benennen.
function M.Neuaufstellen(zielOrdner)
	return M.Install(zielOrdner, nil, true)
end

function M.Uninstall(zielOrdner)
	local ordner = paket()
	local stadt = zielOrdner or stadtOrdner()
	if not stadt then
		return 0
	end
	local entfernt = 0
	for _, bauwerk in ipairs(BAUWERKE) do
		local ok = pcall(function()
			installerVon(ordner, bauwerk.Installer).Uninstall(stadt)
		end)
		if ok then
			entfernt += 1
		end
	end
	print("[Kaiju Debug] LargeCity-Einbau zurueckgenommen -- " .. entfernt .. " Bauwerke entfernt.")
	return entfernt
end

return M
