--============================================================
-- TRENCHBORN INSTALLER
-- LARGE CITY -- die vier neuen Bauwerke auf einmal
--
--   Hotel     LargeCity_LuxuryWaterfrontResort_L3
--   Spital    LargeCity_CentralHospital_L3
--   Stadion   LargeCity_Stadium_L3
--   Arena     LargeCity_UptownArena_L3
--
-- ===== So wird es benutzt =====
-- In Studio, in der Command Bar, EINE Zeile:
--
--   require(game.ServerScriptService.TrenchbornInstallers.LargeCity.LargeCityNewBuildings).Install()
--
-- Danach stehen alle vier in der Welt, sind zerstoerbar und geben Belohnungen. Sie landen
-- in einer Reihe am Rand der bestehenden Stadt -- schieb sie in Studio dorthin, wo sie
-- hingehoeren, und speichere. Die Meldung am Ende nennt jede Position.
--
-- Zum Rueckgaengigmachen: .Uninstall()
--
-- ===== Warum dieses Werkzeug ueberhaupt noetig ist =====
-- Die vier Bauwerke liegen als CODE im Asset-Workshop, nicht als Modelle: ihre
-- GoldenMaster-Module ERZEUGEN die Geometrie, sie platzieren nichts. Und nur das Hotel
-- bringt einen eigenen Installer mit, der aus Geometrie ein Spielobjekt macht. Fuer Spital,
-- Stadion und Arena fehlt er -- ohne ihn haetten sie keine Lebenspunkte, keinen
-- KaijuHouse-Tag und waeren blosse Kulisse: nicht zerstoerbar, ohne Belohnung, ohne
-- Alarmwert. Dieses Modul holt das nach, nach dem Vorbild des Hotel-Installers.
--
-- Anders als die beiden Installer unter City/ stattet dieses Modul nicht ein BESTEHENDES
-- Modell aus, sondern baut zuerst. Es ist wie jene ein einmaliges Studio-Werkzeug und
-- laeuft im Spiel nicht mit.
--============================================================

local M = {}

M.VERSION = "LargeCityNewBuildings_v01"

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HOUSE_TAG = "KaijuHouse"
local CITY_NAME = "LargeCity"

-- ===== Lebenspunkte =====
-- 64 000 je Bauwerk -- der Wert, den das Hotel aus dem Workshop mitbringt. Die vier bleiben
-- damit untereinander stimmig.
--
-- ACHTUNG fuers Balancing: gemessen an Brasshaven ist das zu wenig. Dort haelt ein
-- L3-Bauwerk 89 Schlaege; bei LargeCitys Eintrittsschaden von 1 780 waeren das rund
-- 158 000. Mit 64 000 sind es 36 Schlaege. Das ist bewusst NICHT hier korrigiert: die
-- Gebaeudewerte der Stadt gehoeren in einem Zug angefasst, nicht einzeln, und LargeCity ist
-- noch nicht durchgerechnet (siehe CityAlertConfig).
local MAX_HEALTH = 64000

-- Alle vier auf Heat, wie das Hotel. Die Verteilung der fuenf Energietypen ueber die
-- Gebaeude einer Stadt ist eine offene Gestaltungsfrage und gehoert nicht in ein
-- Installationswerkzeug.
local ENERGY_TYPE = "Heat"

-- Abstand zwischen zwei abgestellten Bauwerken.
local LUECKE = 40

------------------------------------------------------------
-- Die vier Bauwerke
------------------------------------------------------------
-- Das Hotel bringt seinen eigenen Installer mit und wird deshalb nur weitergereicht.
-- Die drei anderen haben nur GoldenMaster und Dressing -- ihre Ausstattung steht hier.
local BAUWERKE = {
	{
		Name = "Hotel",
		ModelName = "LargeCity_LuxuryWaterfrontResort_L3",
		Installer = "LargeCityWaterfrontResortInstaller",
	},
	{
		Name = "Spital",
		ModelName = "LargeCity_CentralHospital_L3",
		BuildingType = "Hospital",
		Specification = "LargeCityCentralHospitalSpecification",
		GoldenMaster = "LargeCityCentralHospitalGoldenMaster",
		Schritte = {
			{ Modul = "LargeCityCentralHospitalDressing", Funktion = "Apply" },
			{ Modul = "LargeCityCentralHospitalGeometryRefinement", Funktion = "Apply" },
			{ Modul = "LargeCityCentralHospitalRoofFix", Funktion = "Apply" },
		},
	},
	{
		Name = "Stadion",
		ModelName = "LargeCity_Stadium_L3",
		BuildingType = "Stadium",
		Specification = "LargeCityStadiumSpecification",
		GoldenMaster = "LargeCityStadiumGoldenMaster",
		Schritte = {
			{ Modul = "LargeCityStadiumDressing", Funktion = "Apply" },
			-- Das Anzeigetafel-Spiel ist Zierde. Faellt es aus, soll das Bauwerk trotzdem
			-- stehen -- deshalb unten in pcall.
			{ Modul = "LargeCityStadiumPong", Funktion = "Attach", Optional = true },
		},
	},
	{
		Name = "Arena",
		ModelName = "LargeCity_UptownArena_L3",
		BuildingType = "Arena",
		Specification = "LargeCityUptownArenaSpecification",
		GoldenMaster = "LargeCityUptownArenaGoldenMaster",
		Schritte = {
			{ Modul = "LargeCityUptownArenaDressing", Funktion = "Apply" },
		},
	},
}

------------------------------------------------------------
-- Hilfen
------------------------------------------------------------

local function paket()
	local ordner = ReplicatedStorage:WaitForChild("TrenchbornAssetWorkshop", 10)
	assert(ordner, "ReplicatedStorage.TrenchbornAssetWorkshop fehlt -- laeuft Rojo?")
	return ordner
end

local function modul(ordner, name)
	local eintrag = ordner:WaitForChild(name, 10)
	assert(eintrag, "Workshop-Modul '" .. name .. "' fehlt -- zeigt das Submodul auf 'game-integration'?")
	return require(eintrag)
end

-- Der Ort, an dem die Stadt haengt: der Vorfahre, der "CityName" traegt -- dieselbe
-- Aufloesung, die auch CityAlertService benutzt. Ueber den Namen zu gehen waere bruechig,
-- der Ordner heisst in Studio nicht zwingend wie die Stadt.
local function stadtOrdner()
	for _, haus in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		local knoten = haus
		while knoten and knoten ~= Workspace do
			if knoten:GetAttribute("CityName") == CITY_NAME then
				return knoten
			end
			knoten = knoten.Parent
		end
	end
	return nil
end

-- Wo die bestehende Stadt aufhoert und auf welcher Hoehe sie steht. Die neuen Bauwerke
-- kommen daneben, damit sie nicht in vorhandenen stecken.
local function stadtGrenzen(ordner)
	local minX, maxX, minY, minZ, maxZ = math.huge, -math.huge, math.huge, math.huge, -math.huge
	local gefunden = false
	for _, haus in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		if haus:IsDescendantOf(ordner) and haus:IsA("Model") then
			local ok, rahmen, groesse = pcall(function()
				return haus:GetBoundingBox()
			end)
			if ok and rahmen then
				gefunden = true
				minX = math.min(minX, rahmen.Position.X - groesse.X * 0.5)
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
	return { MaxX = maxX, MinY = minY, MitteZ = (minZ + maxZ) * 0.5, MinX = minX }
end

-- Setzt das Bauwerk so ab, dass seine Unterkante auf der Hoehe der uebrigen Stadt liegt.
local function stelleAb(model, x, y, z)
	local ok, rahmen, groesse = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not rahmen then
		return nil
	end
	local unterkante = rahmen.Position.Y - groesse.Y * 0.5
	local drehpunkt = model:GetPivot().Position
	local ziel = Vector3.new(
		x + (drehpunkt.X - rahmen.Position.X),
		y + (drehpunkt.Y - unterkante),
		z + (drehpunkt.Z - rahmen.Position.Z))
	model:PivotTo(CFrame.new(ziel))
	return groesse
end

local function stattAus(model, bauwerk, spezifikation, gruppen)
	model.Name = bauwerk.ModelName
	model:SetAttribute("AssetId", spezifikation.AssetId)
	model:SetAttribute("DisplayName", spezifikation.DisplayName)
	model:SetAttribute("City", spezifikation.City)
	model:SetAttribute("BuildingType", bauwerk.BuildingType)
	model:SetAttribute("CityTier", 4)
	model:SetAttribute("MaxHealth", MAX_HEALTH)
	model:SetAttribute("EnergyType", ENERGY_TYPE)
	model:SetAttribute("DestructionGroupCount", gruppen)
	model:SetAttribute("UsesSharedMainGameDestruction", true)
	model:SetAttribute("InstallerReady", true)

	-- Der Tag ist das, was aus Geometrie ein Ziel macht: daran haengen Schaden, Belohnung,
	-- Respawn und Alarmwert (siehe CLAUDE.md, CollectionService-Tags).
	if not CollectionService:HasTag(model, HOUSE_TAG) then
		CollectionService:AddTag(model, HOUSE_TAG)
	end
end

------------------------------------------------------------
-- Einbau
------------------------------------------------------------

function M.Install(zielOrdner)
	local ordner = paket()
	local stadt = zielOrdner or stadtOrdner()
	assert(stadt, "Keine LargeCity gefunden -- kein Vorfahre mit CityName = 'LargeCity'. "
		.. "Entweder den Ordner direkt uebergeben: .Install(workspace.Cities.LargeCity)")

	local grenzen = stadtGrenzen(stadt)
	local x = grenzen and (grenzen.MaxX + LUECKE) or 0
	local bodenY = grenzen and grenzen.MinY or 0
	local z = grenzen and grenzen.MitteZ or 0

	print("[Kaiju Debug] LargeCity-Einbau in '" .. stadt:GetFullName() .. "' -- " .. M.VERSION)

	local gesetzt = 0
	for _, bauwerk in ipairs(BAUWERKE) do
		local vorhandenes = stadt:FindFirstChild(bauwerk.ModelName)
		if vorhandenes then
			vorhandenes:Destroy()
		end

		local model
		if bauwerk.Installer then
			-- Das Hotel bringt seinen Installer selbst mit -- nicht nachbauen, sondern nutzen.
			model = modul(ordner, bauwerk.Installer).Install(stadt)
		else
			local spezifikation = modul(ordner, bauwerk.Specification)
			model = modul(ordner, bauwerk.GoldenMaster).Build(stadt)

			for _, schritt in ipairs(bauwerk.Schritte) do
				local angewandt = modul(ordner, schritt.Modul)
				if schritt.Optional then
					local ok, fehler = pcall(angewandt[schritt.Funktion], model)
					if not ok then
						warn("[Kaiju Debug] " .. bauwerk.Name .. ": '" .. schritt.Modul
							.. "' uebersprungen -- " .. tostring(fehler))
					end
				else
					angewandt[schritt.Funktion](model)
				end
			end

			local gruppenOrdner = model:FindFirstChild("DestructionGroups")
			local gruppen = gruppenOrdner and #gruppenOrdner:GetChildren() or 0
			stattAus(model, bauwerk, spezifikation, gruppen)
		end

		local groesse = stelleAb(model, x, bodenY, z)
		local ort = model:GetPivot().Position
		gesetzt += 1
		print(string.format("[Kaiju Debug]   %-8s '%s' bei %.0f, %.0f, %.0f -- %d Lebenspunkte, %s.",
			bauwerk.Name, model.Name, ort.X, ort.Y, ort.Z,
			model:GetAttribute("MaxHealth") or 0,
			CollectionService:HasTag(model, HOUSE_TAG) and "zerstoerbar" or "OHNE TAG"))

		x += (groesse and groesse.X or 100) + LUECKE
	end

	print(string.format("[Kaiju Debug] %d Bauwerke gesetzt. Sie stehen in einer Reihe am "
		.. "oestlichen Rand -- in Studio an ihren Platz schieben und speichern.", gesetzt))
	return gesetzt
end

function M.Uninstall(zielOrdner)
	local stadt = zielOrdner or stadtOrdner()
	if not stadt then
		return 0
	end
	local entfernt = 0
	for _, bauwerk in ipairs(BAUWERKE) do
		local model = stadt:FindFirstChild(bauwerk.ModelName)
		if model then
			model:Destroy()
			entfernt += 1
		end
	end
	print("[Kaiju Debug] LargeCity-Einbau zurueckgenommen -- " .. entfernt .. " Bauwerke entfernt.")
	return entfernt
end

return M
