-- ModuleScript: BuildingConfig
-- Ort in Studio: ReplicatedStorage
--
-- Die Lebenspunkte der Gebaeude, je Gebaeudetyp und im Repo.
--
-- ===== Warum es diese Datei gibt =====
-- Bis hierher standen die Werte ausschliesslich als Attribute an den Instanzen in Studio.
-- Die Spec nennt das ausdruecklich als Rueckstand (balancing.building-values-live-in-config):
-- "Die Werte eines Gebaeudes stehen zentral je GEBAEUDETYP im Repo, nicht als Attribut an
-- jeder einzelnen Instanz in Studio."
--
-- Was daran schiefgeht, hat diese Sitzung zweimal gezeigt. Im Village waren alle 23
-- AlertValue-Attribute eine von Hand nachgerechnete Formel (MaxHealth mal 0.01) -- 23
-- Gelegenheiten, sich zu vertippen, fuer keine einzige eigene Aussage. Und in City traegt
-- TB_City_FireStation_L2 hundert Lebenspunkte, weil ihm schlicht das Attribut fehlt und
-- der stille Vorgabewert griff: ein Fuenftel eines Schlags fuer ein Bauwerk der Stufe 2.
--
-- ===== Was hier steht und was noch nicht =====
-- DIESE DATEI WIRD NOCH NICHT ANGEWANDT. Sie ist die Soll-Seite: der Gebaeudebericht
-- (StudioTools/GebaeudeBericht) vergleicht sie mit dem, was in Studio wirklich steht, und
-- meldet die Abweichung. Erst wenn beide Seiten uebereinstimmen, lohnt der Schritt, die
-- Werte VON HIER aus zu setzen -- vorher waere es eine stille Aenderung am Spiel.
--
-- ===== Die Regel hinter den Zahlen =====
-- Brasshaven ist die durchgerechnete Stadt und damit der Massstab: ein Gebaeude der Stufe
-- L1 haelt 15 Schlaege des Spielers, der die Stadt BETRITT, L2 haelt 45 und L3 haelt 89.
-- Mehrteilige Bauwerke werden als GANZES gemessen -- die Summe ihrer Abschnitte ergibt die
-- Trefferzahl ihrer Stufe.
--
-- Eintrittsschaden je Stadt (hergeleitet aus Stufenobergrenze, ARM_CAP_SCALE und dem
-- DamagePercent des erwarteten Skins, geprueft gegen die Werte in CityAlertConfig):
--   Village      Level  0, Riftborn      18 je Schlag
--   Brasshaven   Level 10, Ironpulse    135
--   City         Level 20, Epochbreaker 614

local BuildingConfig = {}

BuildingConfig.SchlaegeJeStufe = { L1 = 15, L2 = 45, L3 = 89 }

-- Village -- GEMESSEN am 19.09.2026, entspricht bereits dem Massstab.
-- 23 Teile, 4 825 Lebenspunkte. Bei 18 Schaden sind das 6 bis 56 Schlaege je Gebaeude.
BuildingConfig.Village = {
	Village_SmallChapel_L3 = { MaxHealth = 1000, EnergyType = "Spirit" },
	Village_Mill_L3 = { MaxHealth = 500, EnergyType = "Heat" },
	Village_Workshop_L2 = { MaxHealth = 300, EnergyType = "Heat" },
	Village_Stable_L2 = { MaxHealth = 250, EnergyType = "Heat" },
	Village_Barn_L2 = { MaxHealth = 200, EnergyType = "Heat" },
	Village_Farmhouse_L1 = { MaxHealth = 125, EnergyType = "Heat" },
	Village_Cottage_L1 = { MaxHealth = 100, EnergyType = "Heat" },
}

-- SmallTown (Brasshaven) -- GEMESSEN am 19.09.2026. Das ist der MASSSTAB: die Trefferzahlen
-- 15 / 45 / 89 sind hier gespielt und bestaetigt worden, Village und City sind daraus
-- abgeleitet. Wer hier etwas aendert, aendert die Grundlage aller drei Staedte.
--
-- Vollstaendig sind es 59 Teile und 156 000 Lebenspunkte. Gemessen wurden am 19.09.2026
-- aber nur 56 und 143 200: es fehlten die drei ungetaggten Fluegel des RoadsideMotel_L3
-- (12 000) und 800 an einem Brueckenabschnitt. Beides ist unten vermerkt.
--
-- Bei 135 Schaden (Level 10, Ironpulse) treffen alle drei Stufen ihre Vorgabe genau:
-- 2 000 = 14.8 Schlaege, 6 000 = 44.4, 12 000 = 88.9.
BuildingConfig.SmallTown = {
	-- ===== L1: 15 Schlaege =====
	SmallHouseA_Ranch = { MaxHealth = 2000, EnergyType = "Heat" }, -- 5 Stueck; steht auf "Thermal"
	SmallHouseB_Craftsman = { MaxHealth = 2000, EnergyType = "Heat" }, -- 5 Stueck
	SmallHouseC_GableCottage = { MaxHealth = 2000, EnergyType = "Heat" }, -- 13 Stueck
	SmallHouseD_Duplex = { MaxHealth = 2000, EnergyType = "Heat" }, -- 8 Stueck
	SmallTown_AutoRepair_L1 = { MaxHealth = 2000, EnergyType = "Heat" }, -- 2 Stueck; eines steht auf "Energy"
	SmallTown_Diner_L1 = { MaxHealth = 2000, EnergyType = "Heat" }, -- 2 Stueck
	SmallTown_GeneralStore_L1 = { MaxHealth = 2000, EnergyType = "Heat" },
	SmallTown_HardwareStore_L1 = { MaxHealth = 2000, EnergyType = "Heat" },
	SmallTown_Laundromat_L1 = { MaxHealth = 2000, EnergyType = "Heat" },
	SmallTown_WaterTower_L1 = { MaxHealth = 2000, EnergyType = "Heat" },

	-- ===== L2: 45 Schlaege =====
	GasStation_WolfFuel_L2 = { MaxHealth = 6000, EnergyType = "Chemical" }, -- 2 Stueck
	SmallTownChurch_L2 = { MaxHealth = 6000, EnergyType = "Spirit" },
	SmallTown_FireStation_L2 = { MaxHealth = 6000, EnergyType = "Heat" },
	SmallTown_SheriffStation_L2 = { MaxHealth = 6000, EnergyType = "Heat" },
	SmallTown_Bridge_L2 = {
		-- Zwei Bruecken, und sie sind NICHT gleich: bei einer traegt Deck_B 1 200 statt
		-- 2 000. Diese Bruecke faellt in 38.5 Schlaegen statt in 45. Kein Drama, aber auch
		-- keine Absicht, die irgendwo stuende -- die andere Bruecke ist die Vorlage.
		MaxHealth = 6000,
		Abschnitte = { Deck_A = 2000, Deck_B = 2000, Deck_C = 2000 },
	},

	-- ===== L3: 89 Schlaege =====
	-- Der Kern haelt mit 37 Schlaegen am laengsten, die Fluegel fallen in 26.
	SmallTownSupermarket_L3 = {
		MaxHealth = 12000,
		EnergyType = "Heat",
		Abschnitte = { Section_A = 3500, Section_B = 5000, Section_C = 3500 },
	},
	SmallTownSchool_L3 = {
		MaxHealth = 12000,
		EnergyType = "Spirit",
		Abschnitte = { Wing_A = 3500, Wing_B = 5000, Wing_C = 3500 },
	},

	RoadsideMotel_L3 = {
		-- ===== Das Bauwerk, das da war und nicht zaehlte =====
		-- Es steht unter Workspace.Cities.Smalltown, traegt ueber seinen Vorfahren das
		-- richtige CityName und ist mit 3 500 / 5 000 / 3 500 vollstaendig ausgestattet.
		-- Nur trug KEINER seiner drei Fluegel den Tag KaijuHouse -- damit war es Kulisse:
		-- nicht angreifbar, kein Ertrag, kein Alarm, in keinem Bericht.
		--
		-- Gefunden wurde es nicht im Explorer, sondern durch eine Differenz: die Messung vom
		-- 18.09.2026 zaehlte 59 Teile und 155 200 Lebenspunkte, die vom 19.09. nur noch 56
		-- und 143 200 -- exakt 3 Teile und 12 000 weniger. Ein Gebaeude ohne Tag sieht in
		-- Studio vollkommen richtig aus; nur die Summe verraet es.
		MaxHealth = 12000,
		Abschnitte = { Wing_A = 3500, Wing_B = 5000, Wing_C = 3500 },
	},
}

-- City -- SOLL. Heute steht in Studio ueberall weniger, zwischen Faktor 2.3 und 12.3.
--
-- Gemessen am 19.09.2026: 94 Teile, 290 350 Lebenspunkte, also 472 Schlaege fuer die ganze
-- Stadt -- weniger als die Haelfte von Brasshavens 1 150, obwohl City spaeter kommt und
-- 94 statt 59 Teile hat. Mit den Werten hier sind es 1 513.
--
-- Bei den mehrteiligen Bauwerken steht die Summe am Bauwerk und die Aufteilung darunter.
-- Die Aufteilung behaelt die Verhaeltnisse, die heute in Studio stehen -- welcher Abschnitt
-- der zaeheste ist, ist eine Entscheidung ueber das Bauwerk und nicht ueber die Balance.
BuildingConfig.City = {
	-- ===== Einzelgebaeude =====
	TB_City_Lighthouse_L3 = { MaxHealth = 54600, EnergyType = "Heat" }, -- war 20000, EnergyType "Thermal"
	TB_City_PowerStation_L3 = { MaxHealth = 54600, EnergyType = "Electric" }, -- war 20000
	TB_City_Hospital_L2 = { MaxHealth = 27600, EnergyType = "Chemical" }, -- war 12000
	TB_City_Hotel_L2 = { MaxHealth = 27600, EnergyType = "Heat" }, -- war 8000, 3 Stueck
	TB_City_LargeApartment_L2 = { MaxHealth = 27600, EnergyType = "Heat" }, -- war 6000, 2 Stueck
	TB_City_SmallOffice_L1 = { MaxHealth = 9200, EnergyType = "Heat" }, -- war 4000, 7 Stueck
	TB_City_Warehouse_L1 = { MaxHealth = 9200, EnergyType = "Heat" }, -- war 4000, 4 Stueck
	TB_City_Apartment_L1 = { MaxHealth = 9200, EnergyType = "Heat" }, -- war 3000, 7 Stueck
	TB_City_Townhouse_L1 = { MaxHealth = 9200, EnergyType = "Heat" }, -- war 2000, 14 Stueck, EnergyType "Thermal"

	-- ===== Mehrteilige Bauwerke: Summe und Aufteilung =====
	TB_City_ShoppingMall_L3 = {
		MaxHealth = 54600, -- war 20000
		Abschnitte = { CentralAtrium = 21840, LeftRetailWing = 16380, RightRetailWing = 16380 },
	},
	TB_City_ContainerYardCranes_L3 = {
		MaxHealth = 54600, -- war 21000
		Abschnitte = {
			Section_05_CraneA = 10400, Section_06_CraneB = 10400,
			Section_03_ContainerBlockB = 9100, Section_02_ContainerBlockA = 7800,
			Section_04_ContainerBlockC = 7800, Section_07_ServiceYard = 5200,
			Section_01_GateOffice = 3900,
		},
	},
	TB_City_MarinaYachtHarbor_L3 = {
		MaxHealth = 54600, -- war 19000, 2 Stueck
		Abschnitte = {
			Section_02_HarborClub = 11500, Section_03_MainQuay = 11500,
			Section_07_ServiceDock = 8600, Section_05_DockB = 7200,
			Section_04_DockA = 5750, Section_06_DockC = 5750,
			Section_01_Entrance = 4300,
		},
	},
	TB_City_PierBoardwalk_L2 = {
		MaxHealth = 27600, -- war 6000, 2 Stueck
		Abschnitte = {
			Section_04 = 6450, Section_06 = 5500, Section_01 = 4600,
			Section_02 = 3680, Section_03 = 3680, Section_05 = 3690,
		},
	},
	TB_City_HarborMarket_L2 = {
		MaxHealth = 27600, -- war 6000
		Abschnitte = {
			Section_02_MainHall = 9200, Section_03_ColdStorage = 6900,
			Section_04_ServiceWing = 6900, Section_01_MarketFront = 4600,
		},
	},
	TB_City_SeafoodRestaurant_L2 = {
		MaxHealth = 27600, -- war 2250, 3 Stueck -- der groesste Abstand der ganzen Stadt
		Abschnitte = {
			Section_01_DiningHall = 12270, Section_02_KitchenService = 9200,
			Section_03_WaterfrontTerrace = 6130,
		},
	},
	TB_City_FireStation_L2 = {
		-- Der Rumpf trug 100 Lebenspunkte -- der stille Vorgabewert, weil ihm das Attribut
		-- fehlte. Er zaehlt trotzdem als angreifbares Teil und fiel in einem Fuenftel
		-- Schlag. Die Werte gehoeren an die Abschnitte, nicht an ihn.
		--
		-- ZU ENTSCHEIDEN IN STUDIO: der Rumpf traegt den Tag KaijuHouse und wird deshalb
		-- weiter mitgezaehlt. Entweder verliert er den Tag -- dann stimmen 27 600 --, oder
		-- er behaelt ihn, dann meldet der Abgleich 27 700. Beides ist vertretbar; still
		-- daneben liegen ist es nicht.
		MaxHealth = 27600, -- war 2850
		Abschnitte = { Section_01_MainStation = 20000, Section_02_HoseTower = 7600 },
	},
	TB_City_PoliceStation_L2 = {
		-- Stand hier zuerst ohne das Suffix _L2, weil der Gebaeudebericht vom 19.09.2026 den
		-- Namen so ausgab. Der Setzer hat es am 20.09. widerlegt: in der Welt heisst es
		-- TB_City_PoliceStation_L2. Ein Name, den niemand nachprueft, ist eine Vermutung --
		-- und diese hier haette die Polizeiwache still auf ihren alten Werten gelassen.
		MaxHealth = 27600, -- war 2750
		Abschnitte = { Section_01_MainStation = 20000, Section_02_VehicleGarage = 7600 },
	},
}

-- LargeCity: Level 30-40, Chronovore; Eintrittsschaden 1780 bei voller Arm-Trainingskappe.
-- L1/L2/L3 halten 15/45/89 Grundtreffer. Alle 21 Workshop-Typen sind L3.
-- Zaehlung im Studio am 04.10.2026: 65 angreifbare Instanzen; weitere Typen werden
-- ueber ihr eindeutiges _L1/_L2/_L3-Suffix zugeordnet. Unbekannte Typen werden gemeldet.
BuildingConfig.LargeCity = {
	L1 = { MaxHealth = 26700 },
	L2 = { MaxHealth = 80100 },
	L3 = { MaxHealth = 158400 },
}
BuildingConfig.LargeCityMasterTypes = {
	B01 = "LargeCity_LuxuryWaterfrontResort_L3",
	B02 = "LargeCity_CentralHospital_L3",
	B03 = "LargeCity_Stadium_L3",
	B04 = "LargeCity_UptownArena_L3",
	B05 = "LargeCity_SummitTower_L3",
	B06 = "LargeCity_UptownResidences_L3",
	B07 = "LargeCity_StadiumHotel_L3",
	B08 = "LargeCity_UptownParking_L3",
	B09 = "LargeCity_MeridianPharma_L3",
	B10 = "LargeCity_PowerUtility_L3",
	N01 = "LargeCity_EmberlineResponseHQ_L3",
	N02 = "LargeCity_PoliceHQ_L3",
	N03 = "LargeCity_ResidentialTower_L3",
	N04 = "LargeCity_OfficeTower_L3",
	N05 = "LargeCity_CityHotel_L3",
	N06 = "LargeCity_Courthouse_L3",
	N07 = "LargeCity_CentralStation_L3",
	N08 = "LargeCity_OceanGalleria_L3",
	N09 = "LargeCity_CoastConventionCentre_L3",
	N10 = "LargeCity_TropicalSignalTower_L3",
	N11 = "LargeCity_TropicalHighRise_L3",
}
-- ===== Gemessen am 06.10.2026: JEDES Gebaeude war L3 =====
-- Amancio nach dem abgebrochenen Durchgang: "Die Gebaeude haben sich viel zu schwer
-- angefuehlt." Der Bericht erklaert es:
--
--   LargeCity: 65 Gebaeude, ALLE mit 158 400 HP -- 10 296 000 insgesamt
--   City:      94 Gebaeude, 3 680 bis 54 600 HP -- 1 008 400 insgesamt
--
-- Die Stufenkurve selbst ist richtig und deckt sich mit City: L1 haelt 15 Grundtreffer,
-- L2 45, L3 89. Falsch war die MISCHUNG. City hat zwei L3-Wahrzeichen und drei Dutzend
-- L1-Haeuser; LargeCity hatte 65 Mal das Wahrzeichen. Bei 1 780 Schaden je Schlag sind das
-- 89 Treffer an jedem einzelnen Haus -- fuenfmal so viel wie die 17.5 Treffer, die ein
-- City-Gebaeude im Schnitt braucht.
--
-- ===== Die Regel fuer die Mischung =====
-- Nach der ZAHL DER INSTANZEN, nicht nach dem Namen: was einmal in der Stadt steht, ist ein
-- Wahrzeichen und darf 89 Treffer kosten. Was acht Mal steht, ist Grundbestand und kostet
-- 15. Das ist genau die Form, die City hat, und sie laesst sich am Bericht nachpruefen,
-- statt von Hand gepflegt zu werden.
--
-- WICHTIG zum Namen: alle 21 Werkstatt-Typen heissen "_L3", weil das die Stufe ihres
-- PAKETS ist, nicht ihre Rolle in der Stadt. Die Eintraege hier gewinnen ueber die
-- Suffix-Zuordnung darueber -- deshalb behaelt ein Buerohaus seinen Namen und bekommt
-- trotzdem L1-Leben. Umbenennen waere Studio-Arbeit an 65 Modellen fuer nichts.

-- Wahrzeichen (L3, 89 Treffer) -- je einmal in der Stadt
BuildingConfig.LargeCity.LargeCity_LuxuryWaterfrontResort_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_CentralHospital_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_Stadium_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_UptownArena_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_EmberlineResponseHQ_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_PoliceHQ_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_Courthouse_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_CentralStation_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_CoastConventionCentre_L3 = { MaxHealth = 158400 }
BuildingConfig.LargeCity.LargeCity_TropicalSignalTower_L3 = { MaxHealth = 158400 }

-- Grossbauten (L2, 45 Treffer) -- zwei bis vier Mal, Tuerme und Infrastruktur
BuildingConfig.LargeCity.LargeCity_SummitTower_L3 = { MaxHealth = 80100 }
BuildingConfig.LargeCity.LargeCity_TropicalHighRise_L3 = { MaxHealth = 80100 }
BuildingConfig.LargeCity.LargeCity_MeridianPharma_L3 = { MaxHealth = 80100 }
BuildingConfig.LargeCity.LargeCity_PowerUtility_L3 = { MaxHealth = 80100 }
BuildingConfig.LargeCity.LargeCity_OceanGalleria_L3 = { MaxHealth = 80100 }

-- Grundbestand (L1, 15 Treffer) -- vier bis acht Mal, der Teppich der Stadt
BuildingConfig.LargeCity.LargeCity_OfficeTower_L3 = { MaxHealth = 26700 }
BuildingConfig.LargeCity.LargeCity_ResidentialTower_L3 = { MaxHealth = 26700 }
BuildingConfig.LargeCity.LargeCity_UptownResidences_L3 = { MaxHealth = 26700 }
BuildingConfig.LargeCity.LargeCity_UptownParking_L3 = { MaxHealth = 26700 }
BuildingConfig.LargeCity.LargeCity_CityHotel_L3 = { MaxHealth = 26700 }
BuildingConfig.LargeCity.LargeCity_StadiumHotel_L3 = { MaxHealth = 26700 }

-- MegaCity: Level 40-50, Aeon Tyrant, 34568 Schaden je Grundtreffer.
-- Gleicher Massstab wie LargeCity: L1/L2/L3 = 15/45/89 Treffer.
-- MC-01 bis MC-21 sind die grossen Workshop-Bauwerke (L3).
BuildingConfig.MegaCity = {
	L1 = { MaxHealth = 518500 },
	L2 = { MaxHealth = 1555600 },
	L3 = { MaxHealth = 3076600 },
	["MC-01"] = { MaxHealth = 3076600 },
	["MC-02"] = { MaxHealth = 3076600 },
	["MC-03"] = { MaxHealth = 3076600 },
	["MC-04"] = { MaxHealth = 3076600 },
	["MC-05"] = { MaxHealth = 3076600 },
	["MC-06"] = { MaxHealth = 3076600 },
	["MC-07"] = { MaxHealth = 3076600 },
	["MC-08"] = { MaxHealth = 3076600 },
	["MC-09"] = { MaxHealth = 3076600 },
	["MC-10"] = { MaxHealth = 3076600 },
	["MC-11"] = { MaxHealth = 3076600 },
	["MC-12"] = { MaxHealth = 3076600 },
	["MC-13"] = { MaxHealth = 3076600 },
	["MC-14"] = { MaxHealth = 3076600 },
	["MC-15"] = { MaxHealth = 3076600 },
	["MC-16"] = { MaxHealth = 3076600 },
	["MC-17"] = { MaxHealth = 3076600 },
	["MC-18"] = { MaxHealth = 3076600 },
	["MC-19"] = { MaxHealth = 3076600 },
	["MC-20"] = { MaxHealth = 3076600 },
	["MC-21"] = { MaxHealth = 3076600 },
}

-- Layout-Kopien haben LC-xx-Namen. MasterId/AssetId bewahren den eigentlichen Typ.
function BuildingConfig.GetTypeName(model, cityName)
	local name = model.Name
	if cityName == "MegaCity" then
		local asset = model:GetAttribute("AssetId")
		if asset and BuildingConfig.MegaCity[asset] then return asset end
		local id = name:match("^(MC%-[0-9][0-9])%-[0-9]+$") or name:match("^(MC%-[0-9][0-9])$")
		if id and BuildingConfig.MegaCity[id] then return id end
		local tier = name:match("_L([123])$") or (type(asset) == "string" and asset:match("_L([123])$"))
		return tier and ("L" .. tier) or name
	end
	if cityName ~= "LargeCity" then return name end
	local master = BuildingConfig.LargeCityMasterTypes[model:GetAttribute("MasterId")]
	local asset = model:GetAttribute("AssetId")
	if master then return master end
	if asset and BuildingConfig.LargeCity[asset] then return asset end
	if BuildingConfig.LargeCity[name] then return name end
	local tier = name:match("_L([123])$") or (type(asset) == "string" and asset:match("_L([123])$"))
	return tier and ("L" .. tier) or name
end

return BuildingConfig
