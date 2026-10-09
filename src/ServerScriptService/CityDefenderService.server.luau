-- VERSION: 2026-08-26 #2
-- FEATURE: _G.DespawnGuardianForCity ergänzt
-- Ort in Studio: ServerScriptService
--
-- Alert-Level 5: Guardian-Jaeger-Boss ("Mk I" -- Konzept geändert: Village und
-- SmallTown haben KEINEN Guardian, erst ab City. Aktuell für City konfiguriert,
-- LargeCity/Megacity folgen später). Verhalten nach Konzept-Vorlage:
--   SCAN -> POSITIONIEREN -> BLOCKIEREN -> KONTERN
-- statt permanent hinter dem Spieler herzurennen. Beobachtet, wohin sich der Spieler
-- bewegt, und stellt sich VOR wichtige Gebäude (per "GuardianProtect"-Tag markiert,
-- Fallback: das Gebäude mit der höchsten MaxHealth der Stadt), sobald er sich nähert.
--
-- Drei Waffensysteme:
--   Aegis Shield (links)   -- solange der Guardian aktiv vor einem Gebäude blockiert,
--                             nimmt dieses Gebäude KEINEN Schaden (siehe
--                             HouseHandler.lua, _G.IsGuardianProtectingBuilding)
--   Impact Fist (rechts)   -- Nahkampf-Schlag mit Rückstoss, Cooldown
--   Repulsor Pulse (Brust) -- periodischer Flächen-Rückstoss um den Guardian herum
--
-- Visor dunkel in Ruhe, hell sobald der Spieler als Bedrohung erkannt wird (Zustand
-- wechselt von SCAN zu POSITION/BLOCK/COUNTER).
--
-- WICHTIG -- erwartetes Modell: ServerStorage.GuardianModels.City (falls vorhanden,
-- wird bevorzugt). Existiert keins, wird automatisch ein einfacher Block-Platzhalter
-- gebaut (analog zum Feuerwehrauto-Fallback in FireEngineController.lua).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local CityAlertConfig = require(ReplicatedStorage:WaitForChild("CityAlertConfig"))
-- Glaettung der Darstellung beim Betrachter. Die Bewegung selbst bleibt serverseitig --
-- an der Position des Guardians haengt seine Reichweite (siehe dort).
local SmoothMotion = require(ReplicatedStorage:WaitForChild("SmoothMotion"))
local ShowdownConfig = require(ReplicatedStorage:WaitForChild("ShowdownConfig"))

local GUARDIAN_PROTECT_TAG = "GuardianProtect"

-- Wie viele Gebäude der Rückfall in einer noch nicht ausgestalteten Stadt schützt (siehe
-- findProtectedBuildings). Bei rund 20 Sektionen je Stadt ist ein Viertel genug, damit
-- der Guardian nicht an einer Ecke klebt, und wenig genug, dass es eine Auswahl bleibt.
local FALLBACK_PROTECTED_COUNT = 5

-- ===== Provokation =====
-- Wer den Guardian trifft, wird sein Ziel -- unabhaengig davon, wo das geschuetzte
-- Gebaeude steht. Ohne das konnte man ihn aus sicherer Entfernung beschiessen, waehrend
-- er stur an seinem Posten stand: einer der Gruende, warum er passiv wirkte.
--
-- Die LEINE haelt ihn trotzdem am Gebaeude. Ohne sie waere er ein gewoehnlicher
-- Verfolger, und die Stufe-5-Idee -- er verteidigt etwas, du musst an ihm vorbei -- ginge
-- verloren. Gemessen wird vom Gebaeude, nicht vom Guardian: so kann er nie weiter
-- abkommen, als die Leine lang ist, egal wie lange die Verfolgung dauert.
local DEFAULT_GUARDIAN_LEASH_RADIUS = 256


-- Wie lange ein Angriff auf ein Gebaeude nachwirkt. Jeder weitere Treffer setzt die Uhr
-- zurueck -- der Guardian bleibt also, solange dort gekaempft wird.
local BUILDING_ALERT_DURATION = 10

-- Zustandswechsel melden -- und NUR die. Vorher gab die Update-Schleife bei jedem
-- Durchlauf eine Zeile aus, mehrmals pro Sekunde und Stadt; im Output ging dadurch alles
-- andere unter. Interessant ist ohnehin nur der Moment, in dem der Guardian etwas anderes
-- tut als vorher.
local function setGuardianState(guardian, cityName, newState, detail)
	if guardian.state == newState then
		return
	end
	guardian.state = newState
	print(string.format(
		"[Kaiju-Debug] Guardian %s: %s%s",
		cityName,
		newState,
		detail and (" -- " .. detail) or ""
	))
end

-- Platzhalter-Sound-IDs -- bitte bei Gelegenheit durch echte ersetzen.
local DEPLOY_SOUND_ID = "rbxassetid://9081625499" -- Sirenen/Dampf beim Aufstehen
local IMPACT_FIST_SOUND_ID = "" -- KCHUNK beim Fausthieb
local REPULSOR_SOUND_ID = "" -- Energie-Impuls
local SHIELD_ACTIVATE_SOUND_ID = "" -- CHUNK-CHUNK-WHOOM beim Schild-Ausfahren
local DEFEAT_SOUND_ID = "" -- beim Niedergehen

-- [cityName] = { model=, humanoid=, state=..., ... } -- nur EIN Guardian gleichzeitig pro Stadt.
local activeGuardians = {}

-- [model] = Animations-Schnittstelle aus GuardianRuntimeController.Attach. Schwache
-- Schluessel: wird das Modell zerstoert, verschwindet der Eintrag von selbst.
local guardianAnimation = setmetatable({}, { __mode = "k" })

-- [model] = "WardenShepherd" / "MarshalRoadblock" / "AegisInterceptor". Entscheidet,
-- welche Angriffsanimation gespielt wird.
local guardianAssetName = setmetatable({}, { __mode = "k" })

-- ===== Platzhalter-Modell (falls kein eigenes vorbereitet ist) =====
local function buildFallbackGuardian()
	local model = Instance.new("Model")
	model.Name = "Guardian"

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(10, 12, 6)
	torso.Color = Color3.fromRGB(70, 75, 85)
	torso.Material = Enum.Material.Metal
	torso.TopSurface = Enum.SurfaceType.Smooth
	torso.BottomSurface = Enum.SurfaceType.Smooth
	torso.Parent = model
	model.PrimaryPart = torso

	-- Kopf: klein, tief zwischen den Schultern.
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(3.5, 2.5, 3.5)
	head.Color = Color3.fromRGB(50, 54, 60)
	head.Material = Enum.Material.Metal
	head.Parent = model
	head:PivotTo(torso.CFrame * CFrame.new(0, 6, -0.5))
	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.Parent = torso

	-- Visor: schmaler horizontaler Balken, dunkel in Ruhe.
	local visor = Instance.new("Part")
	visor.Name = "Visor"
	visor.Size = Vector3.new(2.6, 0.35, 0.2)
	visor.Color = Color3.fromRGB(20, 20, 20)
	visor.Material = Enum.Material.Neon
	visor.CanCollide = false
	visor.Parent = model
	visor:PivotTo(head.CFrame * CFrame.new(0, 0, -1.8))
	local visorWeld = Instance.new("WeldConstraint")
	visorWeld.Part0 = head
	visorWeld.Part1 = visor
	visorWeld.Parent = head

	-- Brust-Reaktor (Repulsor-Ursprung + visueller Fokuspunkt).
	local core = Instance.new("Part")
	core.Name = "ChestCore"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(1, 2.2, 2.2)
	core.Color = Color3.fromRGB(80, 180, 255)
	core.Material = Enum.Material.Neon
	core.CanCollide = false
	core.Parent = model
	core:PivotTo(torso.CFrame * CFrame.new(0, 1, -3.1) * CFrame.Angles(0, 0, math.rad(90)))
	local coreWeld = Instance.new("WeldConstraint")
	coreWeld.Part0 = torso
	coreWeld.Part1 = core
	coreWeld.Parent = torso

	local coreLight = Instance.new("PointLight")
	coreLight.Color = Color3.fromRGB(80, 180, 255)
	coreLight.Brightness = 2
	coreLight.Range = 14
	coreLight.Parent = core

	-- Linker Arm: Aegis Shield.
	local leftArm = Instance.new("Part")
	leftArm.Name = "LeftArm"
	leftArm.Size = Vector3.new(3, 9, 3)
	leftArm.Color = Color3.fromRGB(60, 65, 75)
	leftArm.Material = Enum.Material.Metal
	leftArm.Parent = model
	leftArm:PivotTo(torso.CFrame * CFrame.new(-6.5, 0, 0))
	local leftArmWeld = Instance.new("WeldConstraint")
	leftArmWeld.Part0 = torso
	leftArmWeld.Part1 = leftArm
	leftArmWeld.Parent = torso

	local shieldPanel = Instance.new("Part")
	shieldPanel.Name = "AegisShieldPanel"
	shieldPanel.Size = Vector3.new(0.5, 8, 6)
	shieldPanel.Color = Color3.fromRGB(90, 150, 220)
	shieldPanel.Material = Enum.Material.ForceField
	shieldPanel.Transparency = 1 -- unsichtbar, bis aktiviert
	shieldPanel.CanCollide = false
	shieldPanel.Parent = model
	shieldPanel:PivotTo(leftArm.CFrame * CFrame.new(-2.5, 0, 0))
	local shieldWeld = Instance.new("WeldConstraint")
	shieldWeld.Part0 = leftArm
	shieldWeld.Part1 = shieldPanel
	shieldWeld.Parent = leftArm

	-- Rechter Arm: Impact Fist.
	local rightArm = Instance.new("Part")
	rightArm.Name = "RightArm"
	rightArm.Size = Vector3.new(3, 9, 3)
	rightArm.Color = Color3.fromRGB(60, 65, 75)
	rightArm.Material = Enum.Material.Metal
	rightArm.Parent = model
	rightArm:PivotTo(torso.CFrame * CFrame.new(6.5, 0, 0))
	local rightArmWeld = Instance.new("WeldConstraint")
	rightArmWeld.Part0 = torso
	rightArmWeld.Part1 = rightArm
	rightArmWeld.Parent = torso

	local fist = Instance.new("Part")
	fist.Name = "ImpactFist"
	fist.Size = Vector3.new(4, 4, 4)
	fist.Color = Color3.fromRGB(50, 54, 60)
	fist.Material = Enum.Material.Metal
	fist.Parent = model
	fist:PivotTo(rightArm.CFrame * CFrame.new(0, -5.5, 0))
	local fistWeld = Instance.new("WeldConstraint")
	fistWeld.Part0 = rightArm
	fistWeld.Part1 = fist
	fistWeld.Parent = rightArm

	-- Beine + schwere Füsse.
	for _, offset in ipairs({ Vector3.new(-3, -9.5, 0), Vector3.new(3, -9.5, 0) }) do
		local leg = Instance.new("Part")
		leg.Name = "Leg"
		leg.Size = Vector3.new(3.5, 7, 3.5)
		leg.Color = Color3.fromRGB(55, 60, 68)
		leg.Material = Enum.Material.Metal
		leg.Parent = model
		leg:PivotTo(torso.CFrame * CFrame.new(offset))
		local legWeld = Instance.new("WeldConstraint")
		legWeld.Part0 = torso
		legWeld.Part1 = leg
		legWeld.Parent = torso

		local foot = Instance.new("Part")
		foot.Name = "Foot"
		foot.Size = Vector3.new(4.5, 2, 6)
		foot.Color = Color3.fromRGB(45, 48, 54)
		foot.Material = Enum.Material.Metal
		foot.Parent = model
		foot:PivotTo(leg.CFrame * CFrame.new(0, -4.5, -1))
		local footWeld = Instance.new("WeldConstraint")
		footWeld.Part0 = leg
		footWeld.Part1 = foot
		footWeld.Parent = leg
	end

	return model
end

-- ===== TEMPORÄR: Guardians aus dem Asset-Workshop =====
-- Baut das Modell zur Laufzeit aus ReplicatedStorage.TrenchbornAssetWorkshop, statt ein
-- fertiges Modell aus ServerStorage.GuardianModels zu klonen.
--
-- BEWUSST nur GoldenMaster.Build + Dressing.Apply -- NICHT <Asset>Installer.Install().
-- Der Installer hängt zusätzlich die workshop-eigene Gameplay- und Reaktionslogik an, die
-- gegen die Zustandsmaschine hier (SCAN/POSITION/BLOCK/COUNTER) arbeiten würde.
-- ===== Welcher Guardian erscheint wo? =====
-- Die drei Workshop-Assets bilden eine Vererbungskette: Marshal baut das Warden-Modell
-- und tauscht dessen Ausruestung, Aegis baut den Marshal. Das Grundgeruest ist deshalb in
-- allen dreien dasselbe -- die Namensbruecke weiter unten (Visor, ImpactFist, ChestCore)
-- traegt fuer alle.
--
-- Die Zuordnung haengt am KAPITEL: in Kapitel I beginnt die Guardian-Kette bei City, und
-- jedes weitere Kapitel schiebt sie eine Stadt nach vorne.
--
--   Kapitel I     City -> Warden-I   LargeCity -> Marshal-II   MegaCity  -> Aegis-III
--   Kapitel II    SmallTown -> I     City      -> II           LargeCity -> III
--   Kapitel III   Village -> I       SmallTown -> II           City      -> III
--
-- Welches Kapitel gilt, entscheidet der hoechste anwesende Spieler (siehe
-- CityAlertService, _G.GetHighestChapterInCity) -- derselbe Wert, der auch die
-- Hoechst-Alarmstufe bestimmt. Beides muss zusammenpassen: eine Stadt bekommt ihren
-- Guardian erst, wenn sie Stufe 5 ueberhaupt erreichen kann.
--
-- Zum Abschalten: GUARDIAN_LADDER leeren -- dann greift wieder ServerStorage/Platzhalter.

-- Staedte nach Groesse. Bewusst NICHT CityAlertConfig.CityOrder: dort steht PrologueCity
-- mit drin, die keinen Platz in dieser Staffel hat (der Prolog ist geskriptet und behaelt
-- seinen Guardian aus ServerStorage).
local CITY_SIZE_LADDER = { "Village", "SmallTown", "City", "LargeCity", "MegaCity" }

-- Welche Generation ihren eigenen Runtime-Controller mitbringt. Wer hier fehlt, bekommt
-- den generischen GuardianRuntimeController.
-- Woher die Kennwerte einer Faehigkeit kommen. Nur fuer Generationen, deren Effekte ueber
-- AbilityRequested laufen.
local ASSET_ABILITY_CONFIG = {
	BastionColossus = "BastionColossusGameplayConfig",
	SovereignApex = "SovereignApexGameplayConfig",
}

local ASSET_RUNTIME_CONTROLLER = {
	BastionColossus = "BastionColossusRuntimeController",
	SovereignApex = "SovereignApexRuntimeController",
}

local GUARDIAN_LADDER = {
	{ asset = "WardenShepherd", label = "Warden-I Shepherd" },
	{ asset = "MarshalRoadblock", label = "Marshal-II Roadblock" },
	{ asset = "AegisInterceptor", label = "Aegis-III Interceptor" },
	{ asset = "BastionColossus", label = "Bastion-IV Colossus" },
	{ asset = "SovereignApex", label = "Sovereign-V Apex" },
}

-- ===== Wie eine Generation kaempft =====
-- Amancio am 22.09.2026: Nr. 1 ist Nahkaempfer. Nr. 2 und 5 stehen dazwischen -- sie
-- suchen den Koerperkontakt, halten aber auch gern Abstand. Nr. 3 und 4 sind Fernkaempfer.
--
-- Das deckt sich mit ihrer Ausruestung: der Warden traegt einen Schockstock, der Marshal
-- Schild UND Pulskanone, der Sovereign eine Lanze, die sticht UND strahlt -- waehrend der
-- Aegis (Ionenkanonen, Raketensalve) und der Bastion (Schienenkanone) auf Entfernung
-- gebaut sind.
--
-- Die ZAHLEN bleiben in CityAlertConfig; hier steht nur, wie eine Generation sie nutzt.
-- Alle drei Abstaende sind Vielfache von GuardianRepulsorRadius -- so bleibt der Stil
-- ueber alle Staedte gleich, waehrend die Staerke der Stadt gehoert.
--
--   Fernreichweite  ab dieser Entfernung feuert der Flaechenangriff
--   Wunschabstand   wo er stehen BLEIBEN will; 0 heisst "heran bis auf Schlagreichweite"
--   Abstandsposten  wohin ein Mischtyp nach einem Nahkampftreffer zurueckweicht
--   HaeltAbstand    wie lange er dort bleibt, in Sekunden; 0 heisst "er weicht nie"
local GUARDIAN_KAMPFSTIL = {
	WardenShepherd = { Art = "Nahkaempfer", Fernreichweite = 1.3, Wunschabstand = 0, Abstandsposten = 0, HaeltAbstand = 0 },
	MarshalRoadblock = { Art = "Mischtyp", Fernreichweite = 2.4, Wunschabstand = 0, Abstandsposten = 1.6, HaeltAbstand = 5 },
	AegisInterceptor = { Art = "Fernkaempfer", Fernreichweite = 3.2, Wunschabstand = 2.6, Abstandsposten = 2.6, HaeltAbstand = 0 },
	BastionColossus = { Art = "Fernkaempfer", Fernreichweite = 3.2, Wunschabstand = 2.6, Abstandsposten = 2.6, HaeltAbstand = 0 },
	SovereignApex = { Art = "Mischtyp", Fernreichweite = 2.4, Wunschabstand = 0, Abstandsposten = 1.6, HaeltAbstand = 5 },
}

-- Guardians ohne Generation -- die aus ServerStorage geklonten Modelle -- verhalten sich
-- wie bisher: heran bis auf Schlagreichweite, Flaechenangriff kurz davor.
local KAMPFSTIL_RUECKFALL =
	{ Art = "Nahkaempfer", Fernreichweite = 1.3, Wunschabstand = 0, Abstandsposten = 0, HaeltAbstand = 0 }

local function kampfstil(guardian)
	return GUARDIAN_KAMPFSTIL[guardian.assetName] or KAMPFSTIL_RUECKFALL
end

-- In Kapitel I steht der erste Guardian in City -- Position 3 der Staffel oben.
local FIRST_GUARDIAN_CITY_IN_CHAPTER_1 = 3

-- Ausserhalb der Groessenstaffel: die PrologueCity bekommt IMMER denselben Guardian.
--
-- Der Prolog ist eine geskriptete Sequenz und der erste Guardian, den ein Spieler
-- ueberhaupt sieht -- er soll die Einfuehrung sein und nicht davon abhaengen, welches
-- Kapitel jemand gerade spielt. Ein Ronin, der den Prolog nochmal ansieht, trifft
-- denselben Gegner wie beim ersten Mal.
--
-- Seit dem 21.09.2026 ist das der MARSHAL-II ROADBLOCK statt des Warden-I: er bringt
-- RiotShield und PulseCannon mit (MarshalRoadblockGameplayConfig), also Schild und Kanone.
-- Der Prolog zeigt damit gleich beides -- etwas, das der Spieler brechen muss, und etwas,
-- das zurueckschiesst.
local FIXED_GUARDIAN_CITIES = {
	PrologueCity = 2, -- Index in GUARDIAN_LADDER -- Marshal-II Roadblock
}

local cityLadderIndex = {}
for index, cityName in ipairs(CITY_SIZE_LADDER) do
	cityLadderIndex[cityName] = index
end

local function getGuardianPlan(cityName)
	if #GUARDIAN_LADDER == 0 then
		return nil
	end

	local fixedIndex = FIXED_GUARDIAN_CITIES[cityName]
	if fixedIndex then
		return GUARDIAN_LADDER[math.min(fixedIndex, #GUARDIAN_LADDER)]
	end

	local cityIndex = cityLadderIndex[cityName]
	if not cityIndex then
		return nil
	end

	local chapter = 1
	if _G.GetHighestChapterInCity then
		chapter = _G.GetHighestChapterInCity(cityName) or 1
	end

	local firstGuardianCity = FIRST_GUARDIAN_CITY_IN_CHAPTER_1 - (chapter - 1)
	local rung = cityIndex - firstGuardianCity + 1
	if rung < 1 then
		return nil -- Stadt liegt in diesem Kapitel noch unterhalb der Guardian-Kette
	end

	-- Seit es alle fuenf Generationen gibt, geht die Rechnung auf: fuenf Staedte, fuenf
	-- Stufen, und in Kapitel 3 -- wenn der Warden in Village beginnt -- werden alle fuenf
	-- gebraucht. Die Klemmung greift damit nicht mehr; sie bleibt als Netz stehen, falls
	-- die Leiter je wieder kuerzer wird als die Staedteliste.
	--
	-- Zur Erinnerung, was daraus folgt (FIRST_GUARDIAN_CITY_IN_CHAPTER_1 = City):
	--   Kapitel 1: City=I, LargeCity=II, MegaCity=III  (Village/SmallTown ohne Guardian)
	--   Kapitel 2: SmallTown=I ... MegaCity=IV
	--   Kapitel 3: Village=I ... MegaCity=V
	return GUARDIAN_LADDER[math.min(rung, #GUARDIAN_LADDER)]
end


local function buildWardenGuardian(plan)
	local workshop = ReplicatedStorage:FindFirstChild("TrenchbornAssetWorkshop")
	if not workshop then
		warn("[CityDefenderService] ReplicatedStorage.TrenchbornAssetWorkshop nicht gefunden -- nutze Platzhalter statt Warden.")
		return nil
	end

	local ok, model = pcall(function()
		local builder = require(workshop:WaitForChild(plan.asset .. "GoldenMaster", 5))
		local dressing = require(workshop:WaitForChild(plan.asset .. "Dressing", 5))

		-- Build() setzt model.Parent selbst -- deshalb ein Ablage-Ordner, aus dem das
		-- fertige Modell wieder herausgelöst wird (der Aufrufer parentet nach Workspace).
		local staging = Instance.new("Folder")
		staging.Name = "WardenStaging"
		staging.Parent = ServerStorage

		local built = builder.Build(staging)
		dressing.Apply(built) -- sucht "VisorSensor"/"Lens" -- MUSS vor dem Umbenennen laufen

		-- FleetRig: baut aus der starren Geometrie ein Motor6D-Skelett mit Humanoid und
		-- Animator. VOR den Umbenennungen weiter unten -- es sucht seine Quellteile ueber
		-- feste Namen und wirft, wenn eines fehlt.
		--
		-- Danach ist das Modell physisch ein anderes: alle Teile sind unverankert und
		-- kollisionsfrei an Steuerteile geschweisst, und model.PrimaryPart zeigt auf ein
		-- NEU erzeugtes HumanoidRootPart. Die Kollision stellt der Block weiter unten
		-- wieder her; die Sohlenhoehe wird nicht mehr von Hand gesetzt, sondern ueber
		-- guardian.soleOffset aus der Bounding Box abgeleitet.
		local rig = require(workshop:WaitForChild("GuardianFleetRig", 5))
		rig.Apply(built)

		-- Animations-Steuerung anhaengen. Attach() erwartet eine gameplayApi-Instanz mit
		-- drei BindableEvents -- wir uebergeben bewusst einen leeren Platzhalter und
		-- feuern nie darauf: die Workshop-Gameplay-Logik wuerde gegen die
		-- Zustandsmaschine hier arbeiten. Genutzt wird nur api.PlayAnimation, damit
		-- SCAN/POSITION/BLOCK/COUNTER die alleinige Autoritaet bleibt.
		-- Bastion und Sovereign bringen EIGENE Runtime-Controller mit, die ihre
		-- Animationsnamen und ihre Faehigkeiten kennen. Der generische kennt beides nicht.
		--
		-- Warden, Marshal und Aegis bleiben bewusst auf dem generischen Controller, obwohl
		-- es fuer zwei davon inzwischen auch eigene gaebe: ihr Weg laeuft heute, und ihn
		-- umzustellen waere eine Aenderung an Funktionierendem ohne Anlass.
		local controllerName = ASSET_RUNTIME_CONTROLLER[plan.asset] or "GuardianRuntimeController"
		local controller = require(workshop:WaitForChild(controllerName, 5))

		-- Der Ordner heisst "Gameplay", weil die Reactions-Module des Workshops genau
		-- danach suchen (model:WaitForChild("Gameplay")). Er bleibt trotzdem ein
		-- Platzhalter: die drei Ereignisse darin feuern wir SELBST, und die Gameplay-Logik
		-- des Workshops wird nicht angehaengt -- sie brauechte eine zweite
		-- Zustandsmaschine neben der hier.
		local gameplay = Instance.new("Folder")
		gameplay.Name = "Gameplay"
		for _, eventName in ipairs({ "AbilityRequested", "DamageTaken", "StateChanged" }) do
			local event = Instance.new("BindableEvent")
			event.Name = eventName
			event.Parent = gameplay
		end
		gameplay.Parent = built

		guardianAnimation[built] = controller.Attach(built, gameplay)
		guardianAssetName[built] = plan.asset

		-- Der Aegis bringt seine Effekte nicht als aufrufbares Modul mit, sondern als
		-- Reaktionen auf AbilityRequested -- Ionenstrahlen, Raketensalve, Schildfeld.
		-- Warden und Marshal brauchen das nicht, ihre Effekte rufen wir direkt auf.
		if plan.asset == "AegisInterceptor" then
			local reactions = workshop:FindFirstChild("AegisInterceptorReactions")
			if reactions then
				local okReactions, err = pcall(function()
					require(reactions).Attach(built)
				end)
				if not okReactions then
					warn("[CityDefenderService] AegisInterceptorReactions nicht angehaengt: " .. tostring(err))
				end
			end
		end

		built.Parent = nil
		staging:Destroy()
		return built
	end)

	if not ok or not model then
		warn("[CityDefenderService] " .. plan.label .. " konnte nicht gebaut werden (" .. tostring(model) .. ") -- nutze Platzhalter.")
		return nil
	end

	-- Die frueher hier stehende Verschiebung des Roots auf Sohlenhoehe ist ENTFALLEN.
	-- Sie funktionierte nur, solange der Root ein loses, unverankertes Einzelteil war --
	-- ihn allein zu verschieben veraenderte die Geometrie nicht. Seit FleetRig laeuft, ist
	-- er die Wurzel des Skeletts: ihn zu verschieben zieht das ganze Modell mit und
	-- verbiegt die Pose. Die Bodenhaltung uebernimmt jetzt guardian.soleOffset, das weiter
	-- unten aus der Bounding Box gegen die PrimaryPart-Position berechnet wird.

	-- Der Workshop baut jedes Teil mit CanCollide = false -- als reines Anschauungsmodell
	-- richtig, als Boss falsch: der Spieler läuft sonst mühelos durch den Warden hindurch.
	-- NUR sichtbare Teile fest machen; die sechs unsichtbaren Hitbox-Blöcke und der
	-- unsichtbare Root bleiben durchlässig, sonst entstünde eine unsichtbare Wand rings
	-- um das Modell. Alle Teile sind Anchored -- feste Kollision kostet also keine Physik.
	local solidParts = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			descendant.CanCollide = true
			solidParts += 1
		end
	end

	-- Namens-Brücke: der Dienst sucht feste Teilenamen (setVisorActive, fireImpactFist,
	-- beginRepulsorPulse, setAegisShieldDeployed). Der Warden bringt eigene Namen mit.
	-- Was nicht zugeordnet wird, ist überall nil-geprüft und schaltet nur die jeweilige
	-- Optik ab -- keine Fehler.
	local visor = model:FindFirstChild("VisorSensor", true)
	if visor then
		visor.Name = "Visor"
	end

	-- ACHTUNG: "RightHand" ist beim Warden ein FOLDER. Der Dienst tweent .Position am
	-- gefundenen Objekt -- ein Folder würde dort abstürzen. Deshalb die Handfläche darin.
	-- Direkt nach der Handflaeche suchen statt ueber "RightHand". FleetRig legt ein
	-- STEUERTEIL desselben Namens an -- eine Suche nach "RightHand" kann seit dem Rig
	-- dieses Teil finden statt des urspruenglichen Ordners, und ein Part hat kein Kind
	-- "Palm". Die Handflaeche selbst ist eindeutig benannt und vom Rig unberuehrt.
	local palm = model:FindFirstChild("Palm", true)
	if palm and palm:IsA("BasePart") then
		palm.Name = "ImpactFist"
	else
		palm = nil
	end

	-- "ChestCore" heisst beim Warden bereits so -- der Repulsor-Puls findet es von selbst.
	--
	-- "AegisShieldPanel" wird BEWUSST NICHT zugeordnet: der Warden hat keinen Armschild,
	-- sondern einen Schockstock. setAegisShieldDeployed blendet sein Panel im Ruhezustand
	-- auf Transparency 1 -- ein echtes Warden-Teil würde dabei verschwinden. Der
	-- Schild-EFFEKT (Schadensabsorption, _G.IsGuardianProtectingBuilding) hängt am
	-- Zustand, nicht am Teil, und funktioniert weiterhin.

	print(
		"[Kaiju-Debug] Guardian-Modell: " .. plan.label .. " gebaut (temporär)",
		"-- Visor:", visor and "ja" or "NEIN",
		"| ImpactFist:", palm and "ja" or "NEIN",
		"| ChestCore:", model:FindFirstChild("ChestCore", true) and "ja" or "NEIN",
		"| feste Teile:", solidParts
	)

	return model
end

local function getGuardianTemplate(cityName)
	-- Temporärer Vorrang vor ServerStorage, siehe GUARDIAN_LADDER oben.
	local plan = getGuardianPlan(cityName)
	if plan then
		local warden = buildWardenGuardian(plan)
		if warden then
			return warden
		end
		-- Fehlgeschlagen: unten normal weiter mit ServerStorage/Platzhalter.
	end

	local folder = ServerStorage:FindFirstChild("GuardianModels")
	local custom = folder and folder:FindFirstChild(cityName)
	if custom then
		if custom:IsA("Model") then
			return custom:Clone()
		else
			-- Häufiger Stolperstein: ein Folder statt Model unter GuardianModels.<Stadt>
			-- angelegt -- ein Folder hat kein PrimaryPart und würde weiter unten mit
			-- einem kryptischen Engine-Fehler abstürzen. Hier klar und früh warnen,
			-- stattdessen den Platzhalter nutzen.
			warn("[CityDefenderService] ServerStorage.GuardianModels." .. cityName .. " ist ein " .. custom.ClassName .. ", aber ein 'Model' wird erwartet (braucht PrimaryPart) -- nutze Platzhalter stattdessen.")
		end
	end
	return buildFallbackGuardian()
end

-- ===== Health-Bar (gleiches Muster wie an anderen Stellen im Projekt) =====
local function createHealthBar(guardian)
	local anchorPart = guardian.model.PrimaryPart

	-- Höhe der Leiste aus der Modellgrösse ableiten statt fest 11 Studs über dem
	-- PrimaryPart. Beim Platzhalter (rund 21 Studs hoch, PrimaryPart in der Mitte)
	-- kommt dabei praktisch derselbe Wert heraus wie bisher -- bei einem 42 Studs hohen
	-- Modell wie dem Warden-I Shepherd lag die Leiste dagegen mitten auf der Brust.
	local barOffsetY = 11
	local okBounds, boundsCFrame, boundsSize = pcall(function()
		return guardian.model:GetBoundingBox()
	end)
	if okBounds and boundsSize then
		local modelTopY = boundsCFrame.Position.Y + boundsSize.Y * 0.5
		barOffsetY = (modelTopY - anchorPart.Position.Y) + 9
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GuardianHealthBar"
	billboard.Size = UDim2.new(0, 220, 0, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, barOffsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 600
	billboard.Parent = anchorPart

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.LuckiestGuy
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.Text = "GUARDIAN"
	nameLabel.Parent = billboard

	local shieldTrack = Instance.new("Frame")
	shieldTrack.Size = UDim2.new(1, 0, 0, 10)
	shieldTrack.Position = UDim2.new(0, 0, 0, 18)
	shieldTrack.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	shieldTrack.Parent = billboard
	local shieldFill = Instance.new("Frame")
	shieldFill.Name = "ShieldFill"
	shieldFill.Size = UDim2.new(1, 0, 1, 0)
	shieldFill.BackgroundColor3 = Color3.fromRGB(90, 160, 230)
	shieldFill.BorderSizePixel = 0
	shieldFill.Parent = shieldTrack

	local hpTrack = Instance.new("Frame")
	hpTrack.Size = UDim2.new(1, 0, 0, 10)
	hpTrack.Position = UDim2.new(0, 0, 0, 30)
	hpTrack.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	hpTrack.Parent = billboard
	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(220, 70, 60)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpTrack

	return { billboard = billboard, shieldFill = shieldFill, hpFill = hpFill }
end

local function updateHealthBar(guardian)
	if not guardian.healthBar then
		return
	end
	local shieldRatio = math.clamp(guardian.shield / math.max(guardian.maxShield, 1), 0, 1)
	local hpRatio = math.clamp(guardian.hp / math.max(guardian.maxHP, 1), 0, 1)
	guardian.healthBar.shieldFill.Size = UDim2.new(shieldRatio, 0, 1, 0)
	guardian.healthBar.hpFill.Size = UDim2.new(hpRatio, 0, 1, 0)
end

-- ===== Visor: dunkel in Ruhe, hell sobald der Spieler als Bedrohung erkannt wurde =====
-- Der Visor zeigt den Zustand, ist aber NIE aus.
--
-- Vorher gab es nur "rot" und fast schwarz (20,20,20). Auf Alarmstufe 5 sah ein
-- patrouillierender Guardian damit aus, als waere er abgeschaltet -- gerade dann, wenn er
-- am ehesten zu sehen ist. Ein ruhiges Blau liest sich als "wach, aber jagt nicht"; das
-- Rot bleibt dem Moment vorbehalten, in dem er ein Ziel hat, und behaelt so seine Wirkung.
local VISOR_PATROL_COLOR = Color3.fromRGB(60, 170, 220)
local VISOR_ALERT_COLOR = Color3.fromRGB(255, 60, 50)

local VISOR_DEFEATED_COLOR = Color3.fromRGB(18, 18, 20)

-- Besiegt: Licht aus. Danach zuckt es noch ein paar Mal kurz nach -- eine Maschine, in
-- der es aussetzt, bevor sie ganz stehen bleibt. Laeuft in dem Fenster von rund zwei
-- Sekunden, das dem Umkippen bleibt, bevor das Modell entfernt wird.
local VISOR_DEFEAT_FLICKERS = 3

local function setVisorDefeated(guardian)
	local visor = guardian.model and guardian.model:FindFirstChild("Visor", true)
	if not visor then
		return
	end
	guardian.visorMode = "Defeated"
	visor.Color = VISOR_DEFEATED_COLOR

	task.spawn(function()
		for _ = 1, VISOR_DEFEAT_FLICKERS do
			task.wait(math.random(15, 45) / 100)
			-- Bei jedem Durchgang neu pruefen: das Modell wird zwei Sekunden nach der
			-- Niederlage zerstoert, und dann darf hier nichts mehr angefasst werden.
			if not visor.Parent or guardian.visorMode ~= "Defeated" then
				return
			end
			visor.Color = VISOR_ALERT_COLOR
			task.wait(0.06)
			if visor.Parent then
				visor.Color = VISOR_DEFEATED_COLOR
			end
		end
	end)
end

local function setVisorActive(guardian, active)
	-- Ein besiegter Guardian bleibt dunkel. Ohne diese Sperre koennte ein letzter
	-- Update-Durchlauf ihn wieder anschalten, waehrend er schon umkippt.
	if guardian.visorMode == "Defeated" then
		return
	end
	local mode = active and "Alert" or "Patrol"
	-- Nur bei einer AENDERUNG tweenen. Die Aufrufer rufen je Bild auf; ohne diese Sperre
	-- entstuende sechzigmal pro Sekunde ein neuer 0.4-Sekunden-Tween auf dasselbe Teil,
	-- die sich gegenseitig ueberschreiben und den Farbwechsel nie sauber ausspielen.
	if guardian.visorMode == mode then
		return
	end
	local visor = guardian.model:FindFirstChild("Visor", true)
	if not visor then
		return
	end
	guardian.visorMode = mode
	TweenService:Create(visor, TweenInfo.new(0.4), {
		Color = active and VISOR_ALERT_COLOR or VISOR_PATROL_COLOR,
	}):Play()
end

-- ===== Geschützte Gebäude finden: getaggt, sonst das Gebäude mit der höchsten
-- MaxHealth dieser Stadt. =====
-- Ein bezugsfaehiges Teil eines geschuetzten Gebaeudes finden.
--
-- Frueher stand hier 'house.PrimaryPart or house:FindFirstChildWhichIsA("BasePart")'.
-- Das hat zwei Luecken, und beide enden lautlos damit, dass der Guardian das Gebaeude
-- ueberspringt und reglos stehen bleibt:
--   * FindFirstChildWhichIsA sucht ohne zweites Argument nur DIREKTE Kinder. Ein
--     Asset-Root, dessen Kinder Ordner sind, liefert nichts.
--   * Ist der Tag an einem BasePart statt an einem Model gesetzt, gibt es gar kein Kind
--     -- und '.PrimaryPart' auf einem Part ist kein gueltiger Zugriff.
local function resolveHousePart(house)
	if house:IsA("BasePart") then
		return house
	end
	if house:IsA("Model") and house.PrimaryPart then
		return house.PrimaryPart
	end
	return house:FindFirstChildWhichIsA("BasePart", true) -- rekursiv
end

local function findProtectedBuildings(cityName)
	local tagged = {}
	for _, house in ipairs(CollectionService:GetTagged(GUARDIAN_PROTECT_TAG)) do
		if not house:GetAttribute("Destroyed") and house:GetAttribute("CityNameResolved") ~= false then
			-- WICHTIG: nach Stadt filtern. Vorher nahm dieser Zweig JEDES getaggte Gebäude
			-- der ganzen Welt -- sobald irgendwo eines markiert war, hätte der Guardian
			-- jeder Stadt dasselbe, womöglich weit entfernte Gebäude bewacht. Solange
			-- nichts getaggt ist, greift der Rückfall darunter und es fiel nicht auf.
			-- Seit der Spawn-Punkt ersatzweise aus diesem Gebäude abgeleitet wird, würde
			-- der Fehler den Guardian in der falschen Stadt erscheinen lassen.
			local houseCity = _G.ResolveCityName and _G.ResolveCityName(house)
			if houseCity == cityName then
				table.insert(tagged, house)
			end
		end
	end
	if #tagged > 0 then
		return tagged, false
	end

	-- Rückfall: keine getaggten Gebäude in dieser Stadt -- nimm die GRÖSSTEN nach
	-- MaxHealth.
	--
	-- Betrifft Städte, die noch nicht ausgestaltet sind: der GuardianProtectTagger vergibt
	-- den Tag anhand von 'BuildingLevel' (L2/L3), und dieses Attribut tragen bisher nur
	-- die Assets, die durch die TrenchbornInstallers gelaufen sind. LargeCity, MegaCity
	-- und Village werden gerade erst mit typisierten Gebäuden bestückt.
	--
	-- Früher wählte dieser Zweig EIN einziges Gebäude. Das war der Hauptgrund, warum der
	-- Guardian passiv wirkte: er verteidigte eine einzelne Ecke und blieb untätig, sobald
	-- der Spieler irgendwo anders zerstörte. Mehrere Gebäude geben ihm überall in der
	-- Stadt etwas zu tun.
	--
	-- BEWUSST dynamisch statt über Tags gelöst: in einer Stadt im Umbau würden gesetzte
	-- Tags beim Ersetzen der Gebäude verschwinden. Dieser Zweig rechnet jedes Mal neu und
	-- hört von selbst auf zu greifen, sobald die Stadt echte L2/L3-Gebäude hat.
	local candidates = {}
	if _G.HOUSE_TAG and _G.ResolveCityName then
		for _, house in ipairs(CollectionService:GetTagged(_G.HOUSE_TAG)) do
			if not house:GetAttribute("Destroyed") and _G.ResolveCityName(house) == cityName then
				table.insert(candidates, house)
			end
		end
	end

	table.sort(candidates, function(a, b)
		return (a:GetAttribute("MaxHealth") or 0) > (b:GetAttribute("MaxHealth") or 0)
	end)

	local result = {}
	for index = 1, math.min(FALLBACK_PROTECTED_COUNT, #candidates) do
		table.insert(result, candidates[index])
	end
	return result, true
end

-- ===== Schild-Block: wer sich hinter seinen Schild stellt =====
-- Der Marshal-II traegt einen "RiotShield" am linken Unterarm (MarshalRoadblockGoldenMaster),
-- die gemeinsame Animationsbibliothek hat dafuer "ShieldBlock", und das Client-Verzeichnis in
-- GuardianRuntimeAnimation kennt den Namen. Benutzt hat das bisher niemand: getroffen wurde
-- immer nur "DamageReact" gespielt, der Schild haette genauso gut fehlen koennen.
--
-- Bewusst NUR der Marshal:
--   * Warden-I hat keinen Schild, sondern einen Schockstock.
--   * Aegis-III hat einen -- aber sein Schildfeld laeuft ueber setAegisShieldDeployed als
--     Reaktion auf AbilityRequested. Zwei Wege fuer dieselbe Sache waeren ein Fehler.
--   * Bastion und Sovereign haengen an eigenen Runtime-Controllern mit eigenen
--     Animationsnamen -- "ShieldBlock" kennen die gar nicht.
local SHIELD_BLOCK_ASSETS = { MarshalRoadblock = true }

-- So lange bleibt die Block-Haltung stehen, bevor Stehen/Laufen sie wieder abloest. Laenger
-- als die Drosselung der Trefferreaktion (0.6s): bei anhaltenden Schlaegen soll er
-- durchgehend hinter dem Schild bleiben und nicht dazwischen in Idle zurueckfallen.
local SHIELD_BLOCK_HOLD = 1.2

-- ===== Schaden-API =====
local function damageGuardian(cityName, amount, attackerPlayer)
	local guardian = activeGuardians[cityName]
	if not guardian or guardian.defeated then
		return
	end

	-- WICHTIG: die Regenerations-Sperre gilt für JEDEN Treffer, nicht nur für Treffer auf
	-- den Schild. Vorher stand diese Zeile nur im Schild-Zweig -- sobald der Schild einmal
	-- auf 0 war, lief die 10-Sekunden-Sperre durch, obwohl der Spieler ununterbrochen auf
	-- die HP einschlug. Danach lud der Schild komplett nach und der Kampf begann von vorn:
	-- der Guardian war so nicht zu besiegen. Der Kommentar unten ("falls eine Weile kein
	-- Treffer kam") beschreibt das hier gemeinte Verhalten.
	guardian.lastHitAt = os.clock()

	-- Wer trifft, zieht die Aufmerksamkeit auf sich. Der Guardian jagt ihn danach, bis
	-- dieser die Stadt verlassen hat -- ohne Frist und ohne Abstandsgrenze (siehe die
	-- Bedrohungsauswahl in updateGuardian).
	if attackerPlayer then
		guardian.provokedBy = attackerPlayer
		guardian.provokedAt = os.clock()
		-- Showdown: eine der beiden Haelften der Ausloesebedingung. Erst wenn AUCH der
		-- Guardian den Spieler getroffen hat, wird daraus ein Kampf (ShowdownService).
		if _G.NotifyShowdownDamage then
			_G.NotifyShowdownDamage("PlayerToGuardian", attackerPlayer, cityName)
		end
	end

	-- Sichtbare Reaktion auf den Treffer. Gedrosselt: bei schnellen Schlagfolgen wuerde
	-- sonst je Treffer neu angesetzt und die Animation nie ueber ihre ersten Bilder
	-- hinauskommen.
	if guardian.animation and os.clock() - (guardian.lastDamageReactAt or 0) >= 0.6 then
		guardian.lastDamageReactAt = os.clock()
		-- Solange sein Schild traegt, geht er hinter den Schild, statt zu zucken. Der
		-- Schildvorrat wird erst WEITER UNTEN abgezogen -- hier gilt also der Stand VOR
		-- diesem Treffer, und genau der ist gemeint: auch der Schlag, der den Schild
		-- leert, wird noch geblockt. Danach zuckt er wieder, und das ist der sichtbare
		-- Unterschied zwischen "Schild haelt" und "es geht an die HP".
		if SHIELD_BLOCK_ASSETS[guardian.assetName] and guardian.shield > 0 then
			-- Die Haltung sperren, sonst schiebt der naechste Bild-Durchlauf sofort
			-- wieder Idle oder Walk darueber (siehe playGuardianLoop).
			guardian.animationBusyUntil = os.clock() + SHIELD_BLOCK_HOLD
			guardian.animation.PlayAnimation("ShieldBlock")
			if not guardian.shieldBlockGemeldet then
				guardian.shieldBlockGemeldet = true
				print(string.format(
					"[Kaiju Debug] Guardian %s blockt mit dem Schild (Schild %.0f von %.0f).",
					cityName, guardian.shield, guardian.maxShield or 0))
			end
		else
			guardian.animation.PlayAnimation("DamageReact")
		end
		guardian.loopAnimation = nil
	end

	-- Zeitstempel fuer die Regeneration am Ende der Datei: sie setzt erst
	-- GUARDIAN_REGEN_DELAY Sekunden nach dem letzten Treffer ein, damit er sich nicht
	-- mitten im Kampf zwischen zwei Schlaegen erholt.
	guardian.lastDamageAt = os.clock()

	if guardian.shield > 0 then
		guardian.shield = math.max(guardian.shield - amount, 0)
		if guardian.shield <= 0 and guardian.shieldBlockGemeldet then
			-- Zuruecksetzen, damit die Meldung wiederkommt, wenn der Schild nachgeladen
			-- hat (GuardianShieldRegenDelay) und er sich erneut dahinterstellt.
			guardian.shieldBlockGemeldet = false
			print(string.format(
				"[Kaiju Debug] Guardian %s: Schild durchbrochen -- ab jetzt geht es an die HP.",
				cityName))
		end
	else
		guardian.hp = math.max(guardian.hp - amount, 0)
	end
	updateHealthBar(guardian)

	if guardian.hp <= 0 then
		guardian.defeated = true
		setGuardianState(guardian, cityName, "Defeated")
		setVisorDefeated(guardian)

		-- Der Showdown endet mit einem eigenen Shot auf den fallenden Guardian -- er ist
		-- der Hoehepunkt der gesamten Alarmstufen-Eskalation und bekommt deshalb einen
		-- anderen Abgang als Weglaufen oder Aufgeben.
		if _G.EndShowdownsForCity then
			_G.EndShowdownsForCity(cityName, "Guardian besiegt")
		end

		-- Achievements: "Ersten Guardian besiegt".
		-- Lebensstatistik. Im Mehrspielerbetrieb zaehlt der LETZTE Treffer: attackerPlayer
		-- ist der, dessen Schaden den Guardian auf 0 gebracht hat.
		-- ===== Die Belohnung des Guardians =====
		-- Fest aus der Config, NICHT aus seinen Lebenspunkten -- siehe GuardianXPReward
		-- dort. Städte ohne die beiden Werte zahlen nichts; das ist sichtbar als bekannte
		-- Abweichung im Spec-Prüfer und nicht still.
		if attackerPlayer then
			local config = CityAlertConfig.GetCityConfig(cityName)
			if _G.AwardXP and config.GuardianXPReward then
				_G.AwardXP(attackerPlayer, config.GuardianXPReward)
			end
			if _G.AwardCoins and config.GuardianCoinsReward then
				_G.AwardCoins(attackerPlayer, config.GuardianCoinsReward)
			end
		end

		if attackerPlayer and _G.RecordStat then
			_G.RecordStat(attackerPlayer, "GuardianDefeated")
			_G.RecordStat(attackerPlayer, "GuardianDefeated." .. cityName)

			-- Kapitelabschluss: wer dem MegaCity-Guardian den TÖDLICHEN Treffer versetzt,
			-- hat das Kapitel durchgespielt. Im Mehrspielerbetrieb zählt ausdrücklich nur
			-- der letzte Schlag, nicht die Beteiligung.
			if cityName == "MegaCity" then
				_G.RecordStat(attackerPlayer, "ChaptersCompleted")

				-- Mit WELCHER Fraktion -- bis hierher wurde das nirgends festgehalten, und
				-- ohne diese Angabe ist die Freischaltung von Jaeger und Ronin nicht
				-- auswertbar: Jaeger verlangt diesen Sieg mit Kaiju, Ronin mit Jaeger.
				-- Daran haengen ausserdem die vier Completed-Achievements, die bis heute
				-- als 'dormant' markiert waren.
				local faction = attackerPlayer:GetAttribute("Faction") or "Kaiju"
				local factionKey = "ChaptersCompleted." .. faction
				local previous = attackerPlayer:GetAttribute("Stat_" .. factionKey) or 0
				_G.RecordStat(attackerPlayer, factionKey)

				-- Wie viele VERSCHIEDENE Fraktionen es geschafft haben. Nur beim ersten Mal
				-- je Fraktion hochzaehlen, sonst wuerde dreimal Kaiju wie alle drei
				-- Fraktionen aussehen -- daran haengt "Meister aller Klingen".
				if previous == 0 then
					_G.RecordStat(attackerPlayer, "ChaptersCompletedFactions")
				end
			end
		end

		if attackerPlayer and _G.OnGuardianDefeatedForAchievements then
			_G.OnGuardianDefeatedForAchievements(attackerPlayer)
		end

		local primaryPart = guardian.model.PrimaryPart
		if primaryPart then
			local defeatSound = Instance.new("Sound")
			defeatSound.SoundId = DEFEAT_SOUND_ID
			defeatSound.Volume = 1
			defeatSound.Parent = primaryPart
			if defeatSound.SoundId ~= "" and defeatSound.SoundId ~= "rbxassetid://0" then
				defeatSound:Play()
			end
		end

		-- Der besiegte Guardian BLEIBT liegen, bis er ersetzt wird. Er verschwand
		-- frueher nach zwei Sekunden -- das nahm dem Sieg seinen sichtbaren Beleg. Er ist
		-- dabei harmlos: guardian.defeated laesst updateGuardian, damageGuardian und
		-- handleGuardianTouch sofort zurueckkehren.
		if guardian.animation then
			-- Mit Rig uebernimmt die Defeat-Animation das Zusammenbrechen. Ein zusaetzliches
			-- PivotTo wuerde dagegen arbeiten und die Pose verbiegen.
			--
			-- Die Dauerschleife MUSS dabei geleert werden. Sonst bleibt "Walk" als laufend
			-- eingetragen -- und eine Schleife, die noch als aktiv gilt, wird von
			-- playGuardianLoop nie neu gesetzt und damit auch nie beendet.
			--
			-- Von Hand und nicht ueber playGuardianAction: das steht erst 700 Zeilen
			-- weiter unten, und ein Name vor seiner Deklaration loest in Lua still auf nil
			-- auf (vom Quelltext-Pruefer hier auch prompt gemeldet).
			guardian.loopAnimation = nil
			guardian.animationBusyUntil = math.huge
			guardian.animation.PlayAnimation("Defeat")
		else
			-- Ohne Rig (ServerStorage-Platzhalter) bleibt das Umkippen von Hand.
			local currentCFrame = guardian.model:GetPivot()
			local fallCFrame = currentCFrame * CFrame.Angles(math.rad(80), 0, 0)
			task.spawn(function()
				pcall(function()
					guardian.model:PivotTo(fallCFrame)
				end)
			end)
		end

		-- KEIN zeitgesteuerter Respawn. Der Guardian bleibt liegen, bis die Alarmstufe
		-- unter 5 faellt -- und das passiert erst, wenn die Stadt gebrochen ist und die
		-- freie Zerstoerungsphase abgelaufen ist (CITY BROKEN setzt 5 -> 0). Das Abraeumen
		-- uebernimmt dann despawnGuardianForCity, das genau daran haengt.
		--
		-- Ein Respawn nach fester Zeit lief quer zu diesem Konzept: er haette einen
		-- zweiten Guardian in eine Stadt gesetzt, deren Guardian-Aufgabe bereits erledigt
		-- ist, und den Sieg damit wieder entwertet.
	end
end
_G.DamageGuardian = damageGuardian

-- ===== Sprung-Schaden (Touch-basiert, gleiches Muster wie bei Feuerwehrautos in
-- FireEngineController.lua und bei Häusern in HouseHandler.lua) =====
-- UNTERSCHIED zu den Feuerwehrautos: dort macht auch blosses Berühren Schaden. Bei einem
-- Boss, neben dem man dauerhaft steht, wäre das geschenkter Dauerschaden -- hier zählt
-- deshalb NUR der echte Sprungangriff.
local JUMP_FALL_VELOCITY_THRESHOLD = -5
local TRAMPLE_COOLDOWN = 0.5
local recentFallVelocity = {} -- [player] = Y-Geschwindigkeit

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			recentFallVelocity[player] = rootPart.AssemblyLinearVelocity.Y
		end
	end
end)

local function handleGuardianTouch(cityName, hit)
	local guardian = activeGuardians[cityName]
	if not guardian or guardian.defeated then
		return
	end
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local state = humanoid:GetState()
	local velocityY = recentFallVelocity[player] or 0
	local isJumping = state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or velocityY < JUMP_FALL_VELOCITY_THRESHOLD
	if not isJumping then
		return
	end

	guardian.lastTrampleAt = guardian.lastTrampleAt or {}
	local now = os.clock()
	local last = guardian.lastTrampleAt[player]
	if last and now - last < TRAMPLE_COOLDOWN then
		return
	end
	guardian.lastTrampleAt[player] = now

	local baseDamage = (character:GetAttribute("Damage") or 10)
		* ((_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0)

	-- Gleiche Bein-Verhältnis-Formel wie bei Häusern und Feuerwehrautos: 1x bis 2x.
	local legPower = player:FindFirstChild("LegPower")
	local legValue = legPower and legPower.Value or 0
	local legCap = math.max(player:GetAttribute("LegStatCap") or 1, 1)
	local legRatio = math.clamp(legValue / legCap, 0, 1)

	if _G.AddJumpHeat then
		_G.AddJumpHeat(player)
	end

	-- Lebensstatistik: gezählt wird der SPRUNGANGRIFF (ein Treffer), nicht jeder Sprung.
	if _G.RecordStat then
		_G.RecordStat(player, "Attacks.Jump")
	end

	damageGuardian(cityName, baseDamage * (1 + legRatio), player)
end

-- Touched auf ALLEN sichtbaren Teilen verbinden, nicht nur auf dem PrimaryPart: der
-- Guardian besteht aus vielen Teilen, und man landet selten genau auf dem einen. Die
-- unsichtbaren Hitbox-Blöcke und der Root bleiben aussen vor.
local function connectGuardianTouch(cityName, model)
	local connected = 0
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			part.Touched:Connect(function(hit)
				handleGuardianTouch(cityName, hit)
			end)
			connected += 1
		end
	end
	return connected
end

_G.GetGuardianInfo = function(model)
	for cityName, guardian in pairs(activeGuardians) do
		if guardian.model == model then
			return cityName
		end
	end
	return nil
end

_G.IsGuardianProtectingBuilding = function(house)
	for _, guardian in pairs(activeGuardians) do
		if not guardian.defeated and guardian.state == "Block" and guardian.protectingBuilding == house then
			return true
		end
	end
	return false
end

-- Fürs CITY-BROKEN-Feature (siehe CityBrokenService.lua): true, solange diese Stadt
-- gerade einen aktiven, NICHT besiegten Guardian hat. Ein Guardian, der noch nicht
-- (re-)gespawnt ist (z.B. während der Respawn-Verzögerung nach einer Niederlage) zählt
-- als "kein aktiver Guardian" -- die Aufgabe "Titan Protocol" gilt in diesem Fenster als
-- erledigt, bis der nächste Guardian erscheint.
_G.HasActiveGuardian = function(cityName)
	local guardian = activeGuardians[cityName]
	return guardian ~= nil and not guardian.defeated
end

-- Liefert das tatsächliche Guardian-Modell einer Stadt (oder nil) -- für Szenen, die den
-- Guardian direkt manipulieren müssen (z.B. Prolog-Kinematik: Guardian dreht sich zum
-- Meer, siehe PrologueOrchestrator.lua).
_G.GetGuardianModel = function(cityName)
	local guardian = activeGuardians[cityName]
	return guardian and guardian.model
end

-- ===== Waffensysteme =====
-- cityName wird fuer die Statistik gebraucht ("HitBy.Guardian.<Stadt>"). Der Parameter
-- FEHLTE: die Zeile griff auf eine nicht existierende globale Variable zu und warf beim
-- Verketten. Aufgefallen ist das nie, weil der Nahangriff wegen zu knapp gemessener
-- Reichweite ueberhaupt nicht ausloeste -- ein Fehler, der hinter einem anderen lag.
local function fireImpactFist(guardian, cityName, target, config)
	if os.clock() - (guardian.lastFistAt or 0) < config.GuardianImpactFistCooldown then
		return
	end
	guardian.lastFistAt = os.clock()

	local fist = guardian.model:FindFirstChild("ImpactFist", true)
	local rootPart = guardian.model.PrimaryPart
	if fist then
		-- Kolben fahren kurz zurück (KCHUNK), dann Schlag nach vorne.
		local originalOffset = fist.Position - rootPart.Position
		local windupTween = TweenService:Create(fist, TweenInfo.new(0.15), {
			Position = fist.Position - rootPart.CFrame.LookVector * 1.5,
		})
		windupTween:Play()
		windupTween.Completed:Wait()

		local strikeTween = TweenService:Create(fist, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = rootPart.Position + originalOffset,
		})
		strikeTween:Play()
	end

	local fistSound = Instance.new("Sound")
	fistSound.SoundId = IMPACT_FIST_SOUND_ID
	fistSound.Volume = 0.9
	fistSound.Parent = rootPart
	if fistSound.SoundId ~= "" and fistSound.SoundId ~= "rbxassetid://0" then
		fistSound:Play()
	end
	Debris:AddItem(fistSound, 3)

	local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if targetHumanoid and targetRoot and targetHumanoid.Health > 0 then
		targetHumanoid:TakeDamage(config.GuardianImpactFistDamage)
		-- Die zweite Haelfte der Showdown-Bedingung.
		if _G.NotifyShowdownDamage then
			_G.NotifyShowdownDamage("GuardianToPlayer", target, cityName)
		end
		if _G.RecordStat then
			_G.RecordStat(target, "HitBy.Guardian")
			_G.RecordStat(target, "HitBy.Guardian." .. cityName)
			_G.RecordStat(target, "DamageTaken", config.GuardianImpactFistDamage)
		end
		local pushDirection = (targetRoot.Position - rootPart.Position)
		pushDirection = Vector3.new(pushDirection.X, 0, pushDirection.Z)
		if pushDirection.Magnitude > 0.1 then
			pushDirection = pushDirection.Unit
			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			bodyVelocity.Velocity = pushDirection * config.GuardianImpactFistKnockback + Vector3.new(0, 15, 0)
			bodyVelocity.Parent = targetRoot
			Debris:AddItem(bodyVelocity, 0.2)
		end
	end
end

-- ===== Flaechenangriff in zwei Schritten =====
-- Der Angriff war frueher EIN Block: Schaden sofort, Effekt hinterher. Die
-- Telegraph-Zeiten in den Workshop-Konfigurationen (0.55 bis 1.35 Sekunden) liefen dem
-- Schaden also hinterher und warnten vor nichts -- eine dokumentierte Absicht, die nie
-- eingeloest wurde.
--
-- Jetzt: beginRepulsorPulse belegt den Cooldown und startet Ton und Effekt, danach
-- wartet der Aufrufer die Ansatzphase ab und ruft applyRepulsorPulse. Erst dann trifft
-- es. Das ist die Voraussetzung dafuer, dass die Showdown-Kamera den Angriff ZEIGEN
-- kann statt ihn nur zu bestaetigen -- und es macht den Guardian fair, weil man ihm
-- erstmals ausweichen kann.
--
-- Der Nahkampf (fireImpactFist) bleibt bewusst sofort: ein Schlag aus 14 Studs SOLL
-- schnell sein, sonst wird der Guardian im Nahbereich zahnlos.
local function beginRepulsorPulse(guardian, cityName, config)
	if os.clock() - (guardian.lastRepulsorAt or 0) < config.GuardianRepulsorCooldown then
		return nil
	end
	guardian.lastRepulsorAt = os.clock()

	local core = guardian.model:FindFirstChild("ChestCore", true)
	local rootPart = guardian.model.PrimaryPart
	local origin = core and core.Position or rootPart.Position

	if core then
		local pulseTween = TweenService:Create(core, TweenInfo.new(0.15), { Transparency = 0 })
		pulseTween:Play()
	end

	local repulsorSound = Instance.new("Sound")
	repulsorSound.SoundId = REPULSOR_SOUND_ID
	repulsorSound.Volume = 0.9
	repulsorSound.Parent = rootPart
	if repulsorSound.SoundId ~= "" and repulsorSound.SoundId ~= "rbxassetid://0" then
		repulsorSound:Play()
	end
	Debris:AddItem(repulsorSound, 3)

	return origin
end

-- Teilt den Schaden aus. Wird erst NACH der Ansatzphase gerufen (siehe oben).
local function applyRepulsorPulse(guardian, cityName, config, origin)
	if guardian.defeated then
		return -- waehrend der Ansatzphase gefallen: der Impuls verpufft
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName and player.Character then
			local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
				-- Waagerecht messen, wie beim Ausloeser: origin ist der ChestCore und liegt
				-- weit ueber dem Boden -- dreidimensional gemessen zaehlte diese Hoehe voll
				-- mit und der Impuls traf niemanden, obwohl er sichtbar feuerte. Der
				-- Halbmesser des Spielers wird NICHT abgezogen (siehe attackIfInRange).
				local flat = (targetRoot.Position - origin) * Vector3.new(1, 0, 1)
				local distance = flat.Magnitude
				if distance <= config.GuardianRepulsorRadius then
					targetHumanoid:TakeDamage(config.GuardianRepulsorDamage)
					if _G.NotifyShowdownDamage then
						_G.NotifyShowdownDamage("GuardianToPlayer", player, cityName)
					end
					-- Lebensstatistik: der Repulsor trifft alle Spieler im Radius -- hier
					-- ist "player" die Schleifenvariable, also das getroffene Ziel.
					if _G.RecordStat then
						_G.RecordStat(player, "HitBy.Guardian")
						_G.RecordStat(player, "HitBy.Guardian." .. cityName)
						_G.RecordStat(player, "DamageTaken", config.GuardianRepulsorDamage)
					end
					local pushDirection = (targetRoot.Position - origin)
					pushDirection = Vector3.new(pushDirection.X, 0, pushDirection.Z)
					if pushDirection.Magnitude > 0.1 then
						pushDirection = pushDirection.Unit
						local bodyVelocity = Instance.new("BodyVelocity")
						bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
						bodyVelocity.Velocity = pushDirection * config.GuardianRepulsorKnockback + Vector3.new(0, 20, 0)
						bodyVelocity.Parent = targetRoot
						Debris:AddItem(bodyVelocity, 0.2)
					end
				end
			end
		end
	end
end

-- ===== Aegis Shield sichtbar aus-/einfahren =====
local workshopModuleCache = {}

local function requireWorkshopModule(name)
	local cached = workshopModuleCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local workshop = ReplicatedStorage:FindFirstChild("TrenchbornAssetWorkshop")
	local module = workshop and workshop:FindFirstChild(name)
	if not module then
		workshopModuleCache[name] = false
		warn("[CityDefenderService] Workshop-Modul '" .. name .. "' nicht gefunden -- Effekte bleiben aus.")
		return nil
	end
	local ok, loaded = pcall(require, module)
	if not ok then
		workshopModuleCache[name] = false
		warn("[CityDefenderService] Workshop-Modul '" .. name .. "' laedt nicht: " .. tostring(loaded))
		return nil
	end
	workshopModuleCache[name] = loaded
	return loaded
end

local function setAegisShieldDeployed(guardian, deployed)
	-- Der Aegis-III traegt sein Schildfeld nicht als Teil im Modell, sondern als REAKTION
	-- auf AbilityRequested (drei schwebende Panels vor dem Rumpf). Das muss VOR der
	-- Pruefung darunter passieren: "AegisShieldPanel" existiert bei ihm gar nicht, die
	-- Funktion kaeme sonst nie weiter. Nur beim Ausfahren gefeuert -- das Feld raeumt sich
	-- nach seiner eigenen Duration selbst ab.
	if deployed and guardian.assetName == "AegisInterceptor" and not guardian.aegisFieldUp then
		guardian.aegisFieldUp = true
		local gameplay = guardian.model:FindFirstChild("Gameplay")
		local requested = gameplay and gameplay:FindFirstChild("AbilityRequested")
		local values = requireWorkshopModule("AegisInterceptorGameplayConfig")
		if requested and values then
			pcall(function()
				requested:Fire("DirectionalAegis", nil, values.DirectionalAegis)
			end)
		end
	elseif not deployed then
		guardian.aegisFieldUp = false
	end

	local shieldPanel = guardian.model:FindFirstChild("AegisShieldPanel", true)
	if not shieldPanel then
		return
	end
	if deployed and not guardian.shieldDeployed then
		guardian.shieldDeployed = true
		local shieldSound = Instance.new("Sound")
		shieldSound.SoundId = SHIELD_ACTIVATE_SOUND_ID
		shieldSound.Volume = 0.8
		shieldSound.Parent = guardian.model.PrimaryPart
		if shieldSound.SoundId ~= "" and shieldSound.SoundId ~= "rbxassetid://0" then
			shieldSound:Play()
		end
		Debris:AddItem(shieldSound, 3)
		TweenService:Create(shieldPanel, TweenInfo.new(0.3), { Transparency = 0.35 }):Play()
	elseif not deployed and guardian.shieldDeployed then
		guardian.shieldDeployed = false
		TweenService:Create(shieldPanel, TweenInfo.new(0.3), { Transparency = 1 }):Play()
	end
end

-- ===== Haupt-Verhalten: SCAN -> POSITIONIEREN -> BLOCKIEREN -> KONTERN =====
local ARRIVAL_THRESHOLD = 4

-- ===== Bodenverfolgung beim Laufen =====
-- Die Bewegung unten verschiebt den Guardian nur waagerecht -- die Höhe blieb dadurch auf
-- dem Wert vom Spawn-Punkt stehen, und der Guardian schwebte über jedem Gelände, das
-- tiefer liegt. Hier wird die Zielposition auf den tatsächlichen Boden gesetzt.
--
-- Ausgeschlossen werden das Guardian-Modell selbst (sonst trifft der Strahl seine eigenen
-- Füsse) und alle Spielerfiguren. Gebäude zählen bewusst ALS Boden -- ein Guardian, der
-- über Trümmer steigt, sieht besser aus als einer, der darin versinkt.
local GROUND_RAY_UP = 60
local GROUND_RAY_DOWN = 400

-- ===== Laufanimation =====
-- Prozedural statt per Rig: alle Teile des Warden-Modells sind verankert, ihre CFrames
-- lassen sich also direkt setzen. Pro Bild wird jedes Beinteil um den HÜFTPUNKT gedreht,
-- die beiden Beine gegenphasig -- dazu ein leichtes Auf und Ab des ganzen Körpers.
--
-- Bewusst KEIN Kniebeugen in dieser Fassung: ein starres Schwingen um die Hüfte liest
-- sich bei einem schweren Panzerbein sauber, während ein schlecht sitzender Kniewinkel
-- sofort kaputt aussieht. Lässt sich später ergänzen, wenn das Grundgefühl stimmt.
--
-- Die Teilenamen sind die des Warden-I Shepherd. Der Platzhalter-Guardian benennt seine
-- Beine anders ("Leg"/"Foot", ohne Seite) -- für ihn bleibt das Gerüst leer und es wird
-- wie bisher nichts animiert.
local WALK_CYCLE_SPEED = 1.15 -- Schrittzyklen pro Sekunde
local WALK_LEG_SWING_DEGREES = 20
local WALK_BODY_BOB_STUDS = 0.45
local WALK_BLEND_PER_SECOND = 4 -- wie schnell die Animation ein- und ausblendet

-- ===== Bewegung ueber die Wurzel statt ueber das ganze Modell =====
-- Gilt nur fuer Guardians MIT Rig (siehe stepTowards). Ein Schalter und keine feste
-- Entscheidung, weil ich die Annahme dahinter nicht pruefen kann, ohne es zu sehen: dass
-- alle Teile des Rigs als EIN Koerper an der Wurzel haengen. Stimmt das nicht, bleibt beim
-- Laufen etwas stehen -- dann hier auf false, und es ist wieder wie vorher.
local BEWEGUNG_UEBER_WURZEL = true

local WALK_LEG_PART_SUFFIXES = {
	"UpperLeg", "ThighPlate",
	"KneeBearing", "KneeGuard", "KneeJointCover", "KneeJointHub",
	"LowerLeg", "ShinPlate", "RearHydraulic",
	"Ankle", "FootHeel", "FootMain", "ToeOuter", "ToeInner",
}

-- Merkt sich die Ruhelage jedes Beinteils RELATIV zum Modell-Pivot. Dadurch bleibt die
-- Animation unabhängig davon, wo der Guardian gerade steht und wohin er schaut.
local function captureWalkRig(guardian)
	local model = guardian.model
	local pivot = model:GetPivot()
	local rig = {}

	for _, side in ipairs({ "Left", "Right" }) do
		local hip = model:FindFirstChild(side .. "HipBearing", true)
		if hip and hip:IsA("BasePart") then
			local leg = { hipLocal = pivot:ToObjectSpace(hip.CFrame).Position, rest = {} }
			local count = 0
			for _, suffix in ipairs(WALK_LEG_PART_SUFFIXES) do
				local part = model:FindFirstChild(side .. suffix, true)
				if part and part:IsA("BasePart") then
					leg.rest[part] = pivot:ToObjectSpace(part.CFrame)
					count += 1
				end
			end
			if count > 0 then
				table.insert(rig, leg)
			end
		end
	end

	guardian.walkRig = rig
	guardian.walkPhase = 0
	guardian.walkBlend = 0
	return rig
end

-- Setzt die Beine auf die Pose zum aktuellen Phasenwinkel. Bei walkBlend = 0 landen sie
-- exakt wieder in der Ruhelage -- die Funktion darf also jedes Bild laufen, auch im Stand.
local function applyWalkPose(guardian)
	local rig = guardian.walkRig
	if not rig or #rig == 0 then
		return
	end
	local pivot = guardian.model:GetPivot()
	for index, leg in ipairs(rig) do
		local phaseSign = (index == 1) and 1 or -1
		local angle = math.rad(WALK_LEG_SWING_DEGREES)
			* (guardian.walkBlend or 0)
			* math.sin(guardian.walkPhase or 0)
			* phaseSign
		-- Drehung um die Hüfte, ausgedrückt in Modellkoordinaten: an den Hüftpunkt
		-- verschieben, um die seitliche Achse (X) drehen, zurückverschieben.
		local hipPivot = CFrame.new(leg.hipLocal)
		local rotation = hipPivot * CFrame.Angles(angle, 0, 0) * hipPivot:Inverse()
		for part, rest in pairs(leg.rest) do
			part.CFrame = pivot * rotation * rest
		end
	end
end

-- Gegenstück fürs Stehen: blendet die Animation aus, bis die Beine wieder exakt in der
-- Ruhelage stehen. Ohne das bliebe der Guardian mitten im Schritt eingefroren stehen.
-- Fester Zeitschritt statt echtem Delta -- updateGuardian läuft pro Heartbeat, das reicht
-- für eine Überblendung völlig.
local function relaxWalkPose(guardian)
	if not guardian.walkRig or (guardian.walkBlend or 0) <= 0 then
		return
	end
	guardian.walkBlend = math.max(guardian.walkBlend - (1 / 60) * WALK_BLEND_PER_SECOND, 0)
	applyWalkPose(guardian)
end

local function groundedPosition(guardian, position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { guardian.model }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore

	local result = Workspace:Raycast(
		position + Vector3.new(0, GROUND_RAY_UP, 0),
		Vector3.new(0, -(GROUND_RAY_UP + GROUND_RAY_DOWN), 0),
		params
	)
	if not result then
		return position -- kein Boden gefunden (z.B. über Wasser) -- Höhe unverändert lassen
	end
	return Vector3.new(position.X, result.Position.Y + (guardian.soleOffset or 0), position.Z)
end

-- ===== Verhalten des Guardians =====
-- Fuenf Zustaende. Der Leitgedanke ist nicht "Schaden machen", sondern VERDRAENGEN: der
-- Guardian will den Spieler aus der Stadt schieben, nicht ihn toeten.
--
--   Idle      steht und wartet -- am Patrouillenpunkt oder beim verteidigten Gebaeude
--   Patrol    laeuft zu einem anderen Punkt der Stadt
--   Defend    ein geschuetztes Gebaeude wird angegriffen: stellt sich dazwischen
--   Engage    draengt einen Spieler weg (weil er getroffen wurde oder jemand zu nah kam)
--   Return    kehrt zurueck, nachdem der Spieler weit genug weg ist
--
-- Die Patrouille ist Teil des Entwurfs und kein Beiwerk: nur wenn der Guardian sich
-- zeitweise entfernt, hat der Spieler ein Zeitfenster, in dem er ein paar Haeuser
-- zerstoeren kann. Ein Guardian, der immer am selben Fleck steht, macht die Stufe
-- entweder trivial (man weicht ihm aus) oder unspielbar (man kommt nie vorbei).
local ENGAGE_RADIUS = 90 -- ab hier faellt der Guardian einen Spieler von sich aus an
local PUSH_OUT_DISTANCE = 220 -- so weit muss der Spieler weg sein, damit er ablaesst

-- Ab dieser Entfernung bricht der Guardian ab und kehrt zurueck. Wird auch vom
-- ShowdownService gebraucht: reisst die Leine, endet der Showdown, sonst saesse der
-- Spieler im Filmstreifen und schaute einem Riesen beim Weggehen zu.
--
-- MUSS unter der Konstanten stehen: weiter oben haette PUSH_OUT_DISTANCE auf ein nicht
-- existierendes Global aufgeloest, und die Funktion haette still nil geliefert.
_G.GetGuardianLeashRadius = function()
	return PUSH_OUT_DISTANCE
end
local PATROL_DWELL_MIN = 8 -- Verweildauer an einem Patrouillenpunkt
local PATROL_DWELL_MAX = 18

-- Einen neuen Patrouillenpunkt suchen: die Position eines zufaelligen Hauses DIESER
-- Stadt. Bewusst ueber die Haeuser statt ueber die Stadtgrenzen -- ein Punkt aus dem
-- Huellquader koennte im Wasser, im Fels oder auf unbebauter Flaeche liegen.
local function pickPatrolPoint(cityName)
	if not _G.HOUSE_TAG or not _G.ResolveCityName then
		return nil
	end
	local candidates = {}
	for _, house in ipairs(CollectionService:GetTagged(_G.HOUSE_TAG)) do
		if not house:GetAttribute("Destroyed") and _G.ResolveCityName(house) == cityName then
			local part = resolveHousePart(house)
			if part then
				table.insert(candidates, part.Position)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(1, #candidates)]
end

-- ===== Animationen =====
-- Die Angriffe heissen je Generation anders. Der Warden fuehrt den Schockstock und den
-- Warnimpuls, der Marshal Pulskanone und Fangnetz, der Aegis die Ionenkanonen und die
-- Raketensalve. Die Namen sind die Build-Funktionen der GuardianAnimationLibrary.
-- Welcher Showdown-Shot zum Flaechenangriff welcher Generation gehoert, und wie lange
-- dessen Ansatzphase dauert. Die Zeiten stehen in ShowdownConfig, damit Kamera und
-- Schaden garantiert denselben Wert benutzen -- eine Spec-Regel prueft das.
local SHOWDOWN_PULSE_SHOT = {
	WardenShepherd = "WarningPulse",
	MarshalRoadblock = "ContainmentNet",
	AegisInterceptor = "ShoulderMissiles",
	BastionColossus = "GroundSlam",
	SovereignApex = "ApexLanceBeam",
}

local GUARDIAN_ATTACK_ANIMATIONS = {
	WardenShepherd = { Fist = "ShockBaton", Pulse = "WarningPulse" },
	MarshalRoadblock = { Fist = "PulseCannonFire", Pulse = "ContainmentNetLaunch" },
	AegisInterceptor = { Fist = "TwinIonCannons", Pulse = "ShoulderMissileSalvo" },
	-- Die beiden neuen Generationen belegen dieselben zwei Plaetze: ein naher Angriff und
	-- ein Flaechenangriff. Ausgewaehlt nach Reichweite und Ansatzzeit aus ihren
	-- GameplayConfigs -- der Flaechenangriff braucht eine Ansatzphase, die die Kamera
	-- zeigen kann (siehe ShowdownConfig.GuardianTelegraph).
	BastionColossus = { Fist = "RightSiegeFist", Pulse = "GroundSlam" },
	SovereignApex = { Fist = "ApexLanceThrust", Pulse = "ApexLanceBeam" },
}

-- Die Effekte liegen NEBEN den Animationen, in eigenen Modulen. Die Animation bewegt nur
-- das Skelett; Licht, Funken, Ionenstrahlen und Raketenspuren kommen von dort.
--
-- Die drei Generationen sind unterschiedlich angebunden, und das ist keine Willkuer des
-- Workshops, sondern folgt seiner Bauweise:
--
--   Warden   WardenShepherdCombatVFX -- direkt aufrufbar, ShockBaton(model) /
--            WarningPulse(model, config)
--   Marshal  GuardianCombatVFX -- direkt aufrufbar, Pulse / ContainmentNet mit
--            (model, target, ability). Genau die beiden ruft auch der generische
--            RuntimeController auf; wir rufen sie selbst, damit die Zustandsmaschine hier
--            die Autoritaet behaelt und der Controller nicht mit eigenen Idle-Umschaltungen
--            dazwischenfaehrt.
--   Aegis    AegisInterceptorReactions -- EREIGNISGESTEUERT. Das Modul haengt sich an
--            einen Ordner "Gameplay" im Modell und hoert dort auf AbilityRequested. Ein
--            Direktaufruf ist nicht vorgesehen; deshalb heisst unser Platzhalter-Ordner
--            "Gameplay" und wir feuern das Ereignis.
--
-- Die Sicht-Werte (Telegrafierdauer, Flugzeit, Raketenzahl, Splash-Radius) kommen aus den
-- GameplayConfigs des Workshops -- sie gehoeren zur Optik. Die KAMPFWERTE bleiben in
-- CityAlertConfig; keine Zahl steht an zwei Orten.
-- Telegrafierdauer des Warnimpulses: rein visuell (wie lange das gruene Licht auflaedt),
-- deshalb hier und nicht in CityAlertConfig -- dort stehen die Kampfwerte.
local WARNING_PULSE_TELEGRAPH = 0.6

-- ===== Das Fangnetz haelt fest =====
-- Die Optik des Netzes kommt aus dem Werkstatt-Modul, die Wirkung steht hier.
--
-- Festgehalten wird ueber WalkSpeed -- derselbe Weg, den auch die Trainingsstationen gehen.
-- Und wie dort braucht es ein Attribut dazu: der HeatHandler schreibt WalkSpeed in seiner
-- Schleife fortlaufend neu (BaseWalkSpeed mal Hitze mal Sprint) und wuerde das Festhalten
-- sonst im naechsten Durchlauf wieder aufheben. Er setzt beim Training bereits aus; das
-- Attribut hier steht in derselben Prueffung.
--
-- ===== Warum nichts gemerkt wird =====
-- Naheliegend waere, das Tempo vor dem Fangen zu merken und danach zurueckzuschreiben. Genau
-- das hat im Bestand schon einmal Schaden angerichtet (siehe PlayerSetup, _G.RecalculateJumpPower):
-- wer sich einen Wert merkt, waehrend ein anderes System ihn gerade auf 0 gesetzt hat, merkt
-- sich die 0 und macht sie dauerhaft. Deshalb wird beim Loesen neu berechnet, nicht
-- zurueckgeschrieben.
local NET_HELD_ATTRIBUTE = "GuardianNetHeld"

-- ===== Wie stark das Netz bremst =====
-- Amancio am 27.09.2026: auf 20 % des normalen Tempos. Hier stand 0 -- die Figur blieb also
-- schlicht stehen. Ein Fangnetz soll zaeh machen, nicht einfrieren; erst wenn man sich noch
-- bewegen KANN, liest sich die Behinderung ueberhaupt als Netz.
--
-- Der Wert gehoert der Faehigkeit, nicht der Stadt: 20 % sind in jeder Stadt 20 %, waehrend
-- die Staerke einer Stadt ueber Schaden und Lebenspunkte ausgedrueckt wird. Deshalb steht er
-- hier und nicht in CityAlertConfig -- dieselbe Ueberlegung wie bei GUARDIAN_KAMPFSTIL.
--
-- Die DAUER kommt weiter aus dem Workshop-Config und wird von OnClosed mitgeliefert, damit
-- die Optik des Netzes und die Bremswirkung genau gleich lang laufen.
local NETZ_TEMPO_ANTEIL = 0.2

-- ===== Warum das Tempo je Bild neu gesetzt wird =====
-- Das Rig des Kaiju (KaijuStageOneRig, Paketstand 1.3.4) schreibt humanoid.WalkSpeed in
-- JEDEM Durchlauf seiner Schleife auf einen festen Wert -- 10 beim Gehen, 16 beim Laufen --
-- und kennt weder das Fangnetz noch den HeatHandler. Ein einmal gesetzter Wert waere nach
-- einem Bild wieder weg.
--
-- Genau daran war vom Netz nichts zu spueren, obwohl es auf 0 gesetzt hat: der Server setzte
-- 0, das Rig im selben Durchlauf wieder 10. Es fiel nur niemandem auf, weil beides
-- serverseitig laeuft und keine Fehlermeldung entsteht.
--
-- Solange das Rig keinen Haken fuer eine Tempo-Aenderung anbietet, haelt diese Schleife den
-- Wert dagegen. Sie laeuft ausschliesslich, solange ein Netz haelt.
local function holdTargetInNet(player, duration)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Grundlage ist das Grundtempo der Figur, nicht der gerade gemessene Wert: der koennte
	-- vom Rig (10), von der Hitze oder von einem Training stammen. Siehe den Hinweis oben --
	-- wer sich einen Augenblickswert merkt, merkt sich irgendwann eine 0.
	local grundTempo = player:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed
	local netzTempo = grundTempo * NETZ_TEMPO_ANTEIL

	player:SetAttribute(NET_HELD_ATTRIBUTE, true)
	humanoid.WalkSpeed = netzTempo

	local bremse
	bremse = RunService.Heartbeat:Connect(function()
		-- Das Attribut ist die einzige Wahrheit darueber, ob noch gebremst wird -- so endet
		-- die Schleife auch dann, wenn das Loesen unten aus einem anderen Grund kommt.
		if player:GetAttribute(NET_HELD_ATTRIBUTE) ~= true or not player.Parent then
			bremse:Disconnect()
			return
		end
		local jetzigerCharakter = player.Character
		local jetzigerHumanoid = jetzigerCharakter and jetzigerCharakter:FindFirstChildOfClass("Humanoid")
		if not jetzigerHumanoid or jetzigerHumanoid.Health <= 0 then
			-- Gestorben oder neu gespawnt: das Netz haelt niemanden mehr.
			player:SetAttribute(NET_HELD_ATTRIBUTE, nil)
			bremse:Disconnect()
			return
		end
		if jetzigerHumanoid.WalkSpeed ~= netzTempo then
			jetzigerHumanoid.WalkSpeed = netzTempo
		end
	end)

	print(string.format(
		"[Kaiju-Debug] Fangnetz bremst %s auf %.1f von %.1f (%.0f %%) fuer %.1f s.",
		player.Name, netzTempo, grundTempo, NETZ_TEMPO_ANTEIL * 100, duration or 0))

	task.delay(duration or 4, function()
		if not player.Parent then
			return
		end
		player:SetAttribute(NET_HELD_ATTRIBUTE, nil)

		-- Der HeatHandler setzt das genaue Tempo im naechsten Durchlauf selbst. Bis dahin --
		-- und fuer den Fall, dass er gar nicht laeuft -- das Grundtempo: lieber einen Moment
		-- lang ohne Hitze-Aufschlag laufen als fuer immer stehenbleiben.
		local currentCharacter = player.Character
		local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
		local baseWalkSpeed = player:GetAttribute("BaseWalkSpeed")
		if currentHumanoid and baseWalkSpeed then
			currentHumanoid.WalkSpeed = baseWalkSpeed
		end
		print(string.format("[Kaiju-Debug] Fangnetz loest sich -- %s kann wieder laufen.", player.Name))
	end)
end

-- kind ist "Fist" (Nahangriff) oder "Pulse" (Flaechenangriff) -- die beiden Rollen, die
-- die Zustandsmaschine kennt. Welche Faehigkeit das je Generation ist, steht hier.
local function playGuardianVFX(guardian, kind, config, target)
	local asset = guardian.assetName
	if not asset then
		return
	end

	if asset == "WardenShepherd" then
		local vfx = requireWorkshopModule("WardenShepherdCombatVFX")
		if not vfx then
			return
		end
		pcall(function()
			if kind == "Fist" then
				vfx.ShockBaton(guardian.model)
			else
				vfx.WarningPulse(guardian.model, {
					TelegraphDuration = WARNING_PULSE_TELEGRAPH,
					Radius = config.GuardianRepulsorRadius,
				})
			end
		end)
		return
	end

	if asset == "MarshalRoadblock" then
		local vfx = requireWorkshopModule("GuardianCombatVFX")
		local values = requireWorkshopModule("MarshalRoadblockGameplayConfig")
		if not vfx or not values or not target then
			return
		end
		pcall(function()
			if kind == "Fist" then
				vfx.Pulse(guardian.model, target.Character, values.PulseCannon)
			else
				-- Das Netz haelt den Gefangenen fest. Die Wirkung steht HIER und nicht im
				-- Werkstatt-Modul: dort liegt die Optik, hier liegen die Kampfwerte -- so ist
				-- es auch bei den anderen Generationen aufgeteilt.
				--
				-- Der Zeitpunkt kommt dagegen von dort. Zwischen Abschuss und Zuschnappen
				-- liegen Telegrafierdauer und Flugzeit, und beide Zahlen stehen im Modul.
				-- Wer hier selbst mitzaehlte, haette sie ein zweites Mal -- und beim naechsten
				-- Feinschliff der Optik faenge das Netz lautlos daneben.
				local ability = table.clone(values.ContainmentNet)
				ability.OnClosed = function(duration)
					holdTargetInNet(target, duration)
				end
				vfx.ContainmentNet(guardian.model, target.Character, ability)
			end
		end)
		return
	end

	-- Bastion und Sovereign gehen denselben Weg wie der Aegis: ihre Effekte haengen als
	-- Reaktion am BindableEvent AbilityRequested, das ihr Runtime-Controller anlegt.
	-- Der Name der Faehigkeit ist derselbe wie der der Animation (siehe
	-- GUARDIAN_ATTACK_ANIMATIONS) -- deshalb genuegt hier eine Tabelle statt zweier Zweige.
	local abilityConfigModule = ASSET_ABILITY_CONFIG[asset]
	if abilityConfigModule then
		local gameplay = guardian.model:FindFirstChild("Gameplay")
		local requested = gameplay and gameplay:FindFirstChild("AbilityRequested")
		local values = requireWorkshopModule(abilityConfigModule)
		local animations = GUARDIAN_ATTACK_ANIMATIONS[asset]
		local abilityName = animations and (kind == "Fist" and animations.Fist or animations.Pulse)
		if not requested or not values or not abilityName or not target then
			return
		end
		pcall(function()
			requested:Fire(abilityName, target.Character, values[abilityName])
		end)
		return
	end

	if asset == "AegisInterceptor" then
		-- Der Ereignisweg: AegisInterceptorReactions haengt am Ordner "Gameplay" und
		-- reagiert auf AbilityRequested. Angehaengt wird es beim Bau (siehe unten).
		local gameplay = guardian.model:FindFirstChild("Gameplay")
		local requested = gameplay and gameplay:FindFirstChild("AbilityRequested")
		local values = requireWorkshopModule("AegisInterceptorGameplayConfig")
		if not requested or not values or not target then
			return
		end
		pcall(function()
			if kind == "Fist" then
				requested:Fire("TwinIonCannons", target.Character, values.TwinIonCannons)
			else
				-- Kopie mit ueberschriebener LockDuration: die Workshop-Vorgabe von 2.0s
				-- waere so lang, dass man aus dem Wirkradius spazieren kann. Kopie und
				-- nicht Zuweisung -- die Konfiguration des Workshops gehoert dem Workshop.
				local missiles = table.clone(values.ShoulderMissiles)
				missiles.LockDuration = ShowdownConfig.GuardianTelegraph.AegisInterceptor
				requested:Fire("ShoulderMissiles", target.Character, missiles)
			end
		end)
	end
end

-- Wie lange eine Angriffsanimation laufen darf, bevor Laufen/Stehen sie wieder ablosen.
local ATTACK_ANIMATION_HOLD = 1.2

-- Einmalige Animation (Angriff, Treffer, Niederlage). Sperrt die Dauerschleife kurz,
-- sonst wuerde der naechste Bild-Durchlauf sofort wieder "Walk" oder "Idle" senden.
local function playGuardianAction(guardian, name)
	local api = guardian.animation
	if not api or not name then
		return
	end
	guardian.animationBusyUntil = os.clock() + ATTACK_ANIMATION_HOLD
	guardian.loopAnimation = nil
	api.PlayAnimation(name)
end

-- Dauerschleife (Walk, Idle, AlertIdle). Nur bei Wechsel senden -- die Aufrufer laufen je
-- Bild, und jedes Senden geht als RemoteEvent an alle Clients.
local function playGuardianLoop(guardian, name)
	local api = guardian.animation
	if not api then
		return
	end
	if os.clock() < (guardian.animationBusyUntil or 0) then
		return
	end
	if guardian.loopAnimation == name then
		return
	end
	guardian.loopAnimation = name
	api.PlayAnimation(name)

	-- ===== Die Spur, die fehlte =====
	-- Beim Guardian, der nicht laeuft, war von aussen nicht zu unterscheiden, ob der
	-- Server die Laufanimation gar nicht ANFORDERT oder ob sie angefordert wird und beim
	-- Client nichts passiert. Das sind zwei voellig verschiedene Fehler, und ich habe
	-- zweimal den falschen vermutet.
	--
	-- Nur beim WECHSEL, nicht je Bild -- die Sperre oben sorgt dafuer. Eine Zeile je
	-- Zustandswechsel ist lesbar; sechzig je Sekunde waeren es nicht.
	print(string.format("[Kaiju-Debug] Guardian-Animation angefordert: %q (Modell sagt jetzt %q).",
		tostring(name), tostring(guardian.model:GetAttribute("GuardianAnimationState"))))
end

-- Einen Schritt in Richtung Ziel gehen. Gibt true zurueck, wenn er angekommen ist.
-- Enthaelt die gesamte Fortbewegung: Bodenhaftung, Laufanimation, Blickrichtung.
-- ===== blickZiel: laufen und schauen sind zwei verschiedene Richtungen =====
-- Ohne diesen Zusatz schaut der Guardian immer dorthin, wo er hingeht. Beim Loesen aus dem
-- Handgemenge liegt sein Ziel aber HINTER ihm -- er drehte dem Spieler also den Ruecken zu
-- und ging weg. Das sah nach Flucht aus, nicht nach dem Abstandnehmen eines Gegners, der
-- seine Reichweite sucht.
--
-- IM SPIEL BESTAETIGT am 27.09.2026: "Wenn sich der Guardian zurueckzieht oder Abstand zum
-- Spieler sucht, dann soll er rueckwaerts laufen und sich nicht einfach umdrehen."
--
-- Mit blickZiel bleibt der Blick dort, die Beine gehen woanders hin -- und weil das Rig
-- eine eigene Animation dafuer mitbringt (BuildWalkBackward), sieht man auch Schritte
-- rueckwaerts statt einer vorwaerts laufenden Figur, die sich seitlich schiebt.
local function stepTowards(guardian, config, destination, blickZiel)
	local rootPart = guardian.model.PrimaryPart
	local currentPosition = rootPart.Position
	local flat = (destination - currentPosition) * Vector3.new(1, 0, 1)
	local horizontalDistance = flat.Magnitude

	if horizontalDistance <= ARRIVAL_THRESHOLD then
		return true
	end

	local direction = flat.Unit
	local deltaTime = RunService.Heartbeat:Wait()

	-- ===== Nach dem Yield neu pruefen =====
	-- Heartbeat:Wait() gibt einen Bildschritt lang nach, und genau in dieser Luecke kann
	-- damageGuardian den Guardian besiegen. Alles darunter lief bisher trotzdem weiter: es
	-- verschob das Modell und schickte "Walk" an die Clients -- also an einen Gegner, der
	-- gerade zusammengebrochen war.
	--
	-- IM SPIEL BESTAETIGT am 20.09.2026: "Als der Guardian starb, ist sein Licht
	-- ausgegangen, was korrekt ist. Ich habe ihn dann aber noch immer laufen sehen, auch
	-- wenn es an Ort und Stelle war."
	--
	-- Derselbe Fall wie beim Trainings-Gauntlet (siehe CLAUDE.md, Yield-Rennen).
	if guardian.defeated or not guardian.model or not guardian.model.Parent then
		return true
	end

	local step = direction * config.GuardianMoveSpeed * deltaTime
	if step.Magnitude > horizontalDistance then
		step = flat
	end
	local newPosition = groundedPosition(guardian, currentPosition + step)

	-- Blickrichtung: standardmaessig die Laufrichtung, mit blickZiel aber der Punkt, den er
	-- im Auge behalten soll. Faellt das Ziel mit seiner eigenen Lage zusammen, gilt wieder
	-- die Laufrichtung -- ein Blick auf den eigenen Standort waere keine Richtung.
	local blick = direction
	if blickZiel then
		local flachZumBlick = (blickZiel - newPosition) * Vector3.new(1, 0, 1)
		if flachZumBlick.Magnitude > 0.1 then
			blick = flachZumBlick.Unit
		end
	end

	-- Rueckwaerts heisst: er geht der Richtung entgegen, in die er schaut. Der Schwellwert
	-- von -0.2 statt 0 laesst seitliches Umkreisen noch als Vorwaertsgehen gelten -- sonst
	-- schaltete die Animation bei jedem Seitenschritt hin und her.
	local rueckwaerts = blick:Dot(direction) < -0.2

	if guardian.animation then
		-- Mit Rig laeuft die Animation ueber Motor6D. Die prozedurale Pose UND das Wiegen
		-- muessen dann unterbleiben: beide verstellen dieselben Teile bzw. die Hoehe und
		-- wuerden gegen die Animation arbeiten.
		playGuardianLoop(guardian, rueckwaerts and "WalkBackward" or "Walk")
	else
		-- Auch die prozedurale Pose laeuft rueckwaerts: der Phasenwinkel geht zurueck, die
		-- Beine schwingen also in der anderen Reihenfolge. Ohne das saehe ein
		-- zurueckweichender Guardian aus, als ginge er vorwaerts und wuerde geschoben.
		local phasenRichtung = rueckwaerts and -1 or 1
		guardian.walkPhase = (guardian.walkPhase or 0)
			+ phasenRichtung * deltaTime * WALK_CYCLE_SPEED * math.pi * 2
		guardian.walkBlend = math.min((guardian.walkBlend or 0) + deltaTime * WALK_BLEND_PER_SECOND, 1)
		-- Koerper wiegt im Schritttakt, zweimal pro Zyklus -- einmal je aufsetzendem Fuss.
		local bob = math.abs(math.sin(guardian.walkPhase)) * WALK_BODY_BOB_STUDS * guardian.walkBlend
		newPosition = newPosition + Vector3.new(0, bob, 0)
	end

	-- ===== Warum die Beine beim Laufen stillstanden =====
	-- Model:PivotTo() setzt die CFrame JEDES Teils -- es verschiebt den Guardian als
	-- starren Block. Bei einem Modell mit Rig laeuft die Animation aber ueber Motor6D, und
	-- die Pose, die der Client daraus gerade gebaut hat, wird von diesen Server-CFrames
	-- Bild fuer Bild ueberschrieben. Das Ergebnis ist ein Guardian, der ueber den Boden
	-- gleitet, ohne einen Schritt zu machen.
	--
	-- Es passt zum Befund, dass seine anderen Animationen sichtbar sind: Angriff, Treffer
	-- und Niederlage spielt er im STAND -- da laeuft kein PivotTo dagegen.
	--
	-- IM SPIEL BESTAETIGT am 26.09.2026: "Der Guardian bewegt seine Beine nicht beim
	-- Laufen."
	--
	-- Mit Rig wird deshalb nur noch die WURZEL gesetzt. Weil model.PrimaryPart auf sie
	-- zeigt, ist das dieselbe Zielposition wie bei PivotTo; die uebrigen Teile haengen als
	-- ein Koerper daran (GuardianFleetRig schweisst sie an Steuerteile) und folgen mit --
	-- nur eben, ohne dass ihre Animationspose ueberschrieben wird.
	--
	-- Ohne Rig bleibt es beim alten Weg: dort gibt es keine Motor6D-Animation, die man
	-- zerstoeren koennte, und die prozedurale Beinpose braucht das starre Setzen.
	local ziel = CFrame.lookAt(newPosition, newPosition + blick)
	if guardian.animation and BEWEGUNG_UEBER_WURZEL then
		rootPart.CFrame = ziel
	else
		guardian.model:PivotTo(ziel)
	end
	-- Dem Client sein Ziel nennen, damit er die Schritte dazwischen glaetten kann. Beide
	-- Zweige oben setzen die Pose fortlaufend, und beide werden nur mit der Netzwerkrate
	-- repliziert -- siehe SmoothMotion. Die Bewegung selbst bleibt hier: an der Position des
	-- Guardians haengt seine Reichweite.
	SmoothMotion.SetTarget(guardian.model, ziel)

	if not guardian.animation then
		applyWalkPose(guardian)
	end
	return false
end

-- Stehen bleiben und einen Punkt anschauen.
-- alert = true: er hat ein Ziel im Blick (AlertIdle), sonst die ruhige Pose.
local function faceAndStand(guardian, lookAtPosition, alert)
	local rootPart = guardian.model.PrimaryPart
	local standPosition = groundedPosition(guardian, rootPart.Position)
	local toLook = (lookAtPosition - standPosition) * Vector3.new(1, 0, 1)
	if toLook.Magnitude > 0.1 then
		-- Auch das Stehen laeuft je Tick durch und dreht ihn dem Ziel nach -- ohne Glaettung
		-- ruckelt schon dieses Nachdrehen.
		SmoothMotion.PivotTo(guardian.model, CFrame.lookAt(standPosition, standPosition + toLook))
	end
	if guardian.animation then
		playGuardianLoop(guardian, alert and "AlertIdle" or "Idle")
	else
		relaxWalkPose(guardian)
	end
end

-- Angreifen, wenn in Reichweite. Beide Angriffe haben eine eigene Cooldown-Sperre, der
-- Aufruf je Bild ist deshalb unbedenklich.
-- ===== Wie breit die Bedrohung ist =====
-- Der Guardian braucht diesen Wert an zwei Stellen: um zu wissen, wo er stehen bleiben soll,
-- und um zu wissen, ob sein Arm reicht. Beide rechneten ihn bisher als NULL, und deshalb
-- lief er in die Spielerfigur hinein (gemeldet am 26.09.2026).
--
-- ===== Warum es die Bounding Box nicht sein darf =====
-- Genau daran ist der erste Versuch gescheitert, und der Kommentar weiter unten haelt es
-- fest: character:GetBoundingBox() misst die volle Ausdehnung samt ausgestreckter
-- Gliedmassen, beim skalierten Kaiju rund 142 Studs Breite. Mit einem Halbmesser von 71 war
-- jede Luecke auf 0 geklemmt und der Nahangriff haette aus 89 Studs ausgeloest. Die Antwort
-- darauf war, den Wert ganz zu streichen -- damit war die eine Uebertreibung durch die
-- andere ersetzt.
--
-- ===== Was es stattdessen ist =====
-- Der KaijuBodyCollider. Diesen Klotz schweisst KaijuStageOneService der Figur selbst an,
-- und er IST ihr Kollisionskoerper -- 8x14x6 Studs mal Bau-Groesse. Wenn der Guardian
-- "nicht in den Spieler laufen" soll, ist genau dieser Koerper gemeint, nicht die Spannweite
-- ihrer Arme. Er ist ein Vielfaches kleiner als die Bounding Box und liegt damit im
-- brauchbaren Bereich.
--
-- Die Obergrenze ist das Sicherheitsnetz gegen einen erneuten Klemmfall: was auch immer
-- kuenftig gemessen wird, es kann die Luecke nicht mehr beliebig auffressen.
local THREAT_RADIUS_MAX = 40
local THREAT_RADIUS_FALLBACK = 6

local function threatRadius(character)
	if not character then
		return 0
	end

	local collider = character:FindFirstChild("KaijuBodyCollider")
	if collider and collider:IsA("BasePart") then
		return math.min(math.max(collider.Size.X, collider.Size.Z) * 0.5, THREAT_RADIUS_MAX)
	end

	-- Ohne Kaiju-Modell (blanker Avatar, Debug-Vergleich): die Wurzel ist schmal und
	-- skaliert mit -- ein brauchbares Mass fuer einen Koerper ohne angebautes Rig.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		return math.min(math.max(root.Size.X, root.Size.Z) * 0.5, THREAT_RADIUS_MAX)
	end

	return THREAT_RADIUS_FALLBACK
end

local function attackIfInRange(guardian, cityName, config, target, targetPosition)
	-- WAAGERECHT messen. Seit FleetRig laeuft, sitzt PrimaryPart auf Huefthoehe des
	-- Skeletts statt auf der Sohle -- bei einer rund 42 Studs hohen Figur liegt ein
	-- Spieler zu seinen Fuessen damit schon aus geometrischen Gruenden ueber 20 Studs
	-- entfernt. Gegen GuardianImpactFistRange (14) gemessen konnte der Nahangriff
	-- dadurch NIE ausloesen, egal wie dicht man stand.
	local flat = (targetPosition - guardian.model.PrimaryPart.Position) * Vector3.new(1, 0, 1)
	-- Beide Halbmesser, denn gemessen wird von Mittelpunkt zu Mittelpunkt: seiner und der
	-- der Bedrohung. Sonst ist "Luecke" nicht die Luecke zwischen zwei Koerpern.
	--
	-- Der Halbmesser der Bedrohung kam hier einmal aus character:GetBoundingBox() und war
	-- mit 71 Studs so gross, dass jede Luecke auf 0 fiel und der Nahangriff aus 89 Studs
	-- ausgeloest haette. Er wurde daraufhin gestrichen -- womit er null war und der Guardian
	-- in den Spieler hineinlief. threatRadius misst jetzt den Kollisionskoerper statt der
	-- Spannweite (siehe dort); beide Uebertreibungen sind damit vom Tisch.
	--
	-- WICHTIG: derselbe Wert muss in den Stehabstand eingehen (strikeDistance weiter unten).
	-- Stehen und Zuschlagen gegen verschiedene Massstaebe gerechnet heisst: er bleibt auf
	-- Armlaenge stehen und schlaegt trotzdem nie.
	local distance = math.max(
		flat.Magnitude - (guardian.bodyRadius or 0) - threatRadius(target and target.Character),
		0
	)

	local stil = kampfstil(guardian)
	local animations = GUARDIAN_ATTACK_ANIMATIONS[guardian.assetName]
	-- Die Animation wird nur gespielt, wenn der Angriff auch WIRKLICH ausgeloest hat --
	-- beide Angriffsfunktionen haben eine eigene Cooldown-Sperre und tun sonst nichts.
	-- Ohne diese Pruefung zuckte er je Bild, ohne zuzuschlagen.
	if distance <= config.GuardianImpactFistRange then
		local before = guardian.lastFistAt
		fireImpactFist(guardian, cityName, target, config)
		if guardian.lastFistAt ~= before then
			local name = animations and animations.Fist
			playGuardianAction(guardian, name)
			playGuardianVFX(guardian, "Fist", config, target)

			-- ===== Der Mischtyp loest sich nach dem Treffer wieder =====
			-- Nr. 2 und 5 sollen den Koerperkontakt SUCHEN und trotzdem gern Abstand
			-- halten. Beides zugleich geht nicht als fester Abstand -- es ist ein
			-- Wechsel: heran, zuschlagen, zurueck auf Schussdistanz, wieder heran.
			-- Ausgeloest wird er hier, weil der Nahkampftreffer der Moment ist, ab dem
			-- das Zurueckweichen etwas bedeutet.
			if stil.HaeltAbstand > 0 then
				guardian.haeltAbstandBis = os.clock() + stil.HaeltAbstand
			end

			-- Ausgabe nur bei einem TATSAECHLICHEN Treffer -- die Cooldowns (3s bzw. 6s)
			-- halten das von selbst lesbar. Ohne sie war nicht zu unterscheiden, ob der
			-- Guardian nicht angreift oder ob nur die Wirkung ausbleibt.
			print(string.format(
				"[Kaiju-Debug] Guardian %s greift an: %s (Nahkampf, %s, %.0f Studs, Schaden %s)",
				cityName, name or "ohne Animation", stil.Art, distance,
				tostring(config.GuardianImpactFistDamage)
			))
		end
	elseif distance <= config.GuardianRepulsorRadius * stil.Fernreichweite then
		local origin = beginRepulsorPulse(guardian, cityName, config)
		if origin then
			local name = animations and animations.Pulse
			playGuardianAction(guardian, name)
			playGuardianVFX(guardian, "Pulse", config, target)

			-- ===== Wo der Schuss EINSCHLAEGT =====
			-- Beim Nahkaempfer ist der Impuls eine Druckwelle um den eigenen Koerper --
			-- da ist die Brust der richtige Mittelpunkt.
			--
			-- Fuer einen Fernkaempfer waere genau das sinnlos: eine Welle um sich selbst,
			-- geschlagen aus 60 Studs Entfernung, trifft niemanden. Sein Schuss muss dort
			-- landen, wo das Ziel steht. Der Radius bleibt derselbe (GuardianRepulsorRadius)
			-- -- es ist derselbe Einschlag, nur an einem anderen Ort.
			--
			-- Ausweichen bleibt moeglich und ist weiter der Sinn der Ansatzphase: der Ort
			-- wird JETZT festgelegt, getroffen wird erst nach dem Telegraph. Wer sich
			-- bewegt, steht dann nicht mehr dort.
			local einschlag = origin
			if stil.Art ~= "Nahkaempfer" then
				einschlag = targetPosition
			end

			-- Die Ansatzphase: hier hat der Showdown seinen Aufhaenger. Der Shot laeuft
			-- genau so lange, wie es dauert, bis der Schaden eintritt -- die Kamera faehrt
			-- also im Moment des Einschlags zurueck.
			local telegraph = ShowdownConfig.GuardianTelegraph[guardian.assetName] or 0
			if _G.NotifyShowdownAttack and SHOWDOWN_PULSE_SHOT[guardian.assetName] then
				_G.NotifyShowdownAttack(SHOWDOWN_PULSE_SHOT[guardian.assetName], target, cityName)
			end

			print(string.format(
				"[Kaiju-Debug] Guardian %s setzt an: %s (%s, %.0f Studs, Einschlag %s, "
					.. "Ansatz %.2fs, Schaden %s)",
				cityName, name or "ohne Animation", stil.Art, distance,
				stil.Art == "Nahkaempfer" and "bei sich" or "beim Ziel",
				telegraph, tostring(config.GuardianRepulsorDamage)
			))

			if telegraph > 0 then
				task.delay(telegraph, function()
					applyRepulsorPulse(guardian, cityName, config, einschlag)
				end)
			else
				applyRepulsorPulse(guardian, cityName, config, einschlag)
			end
		end
	end
end

-- Lebender Spieler mit Wurzelteil, sonst nil.
local function livingRoot(player)
	if not player or not player.Character then
		return nil
	end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root then
		return root
	end
	return nil
end

local function updateGuardian(cityName, guardian, config)
	if guardian.defeated or not guardian.model or not guardian.model.Parent then
		return
	end
	local rootPart = guardian.model.PrimaryPart
	if not rootPart then
		return
	end

	-- Schild-Regeneration, falls eine Weile kein Treffer kam.
	if guardian.shield < guardian.maxShield and os.clock() - (guardian.lastHitAt or 0) >= config.GuardianShieldRegenDelay then
		guardian.shield = math.min(guardian.shield + guardian.maxShield * config.GuardianShieldRegenRate * (1 / 60), guardian.maxShield)
		updateHealthBar(guardian)
	end

	local now = os.clock()
	local _, usesFallback = findProtectedBuildings(cityName)
	guardian.usesFallbackBuildings = usesFallback

	-- ===== 1. Wird ein geschuetztes Gebaeude angegriffen? =====
	local defendBuilding, defendPart = nil, nil
	if guardian.alertBuilding then
		local fresh = now - (guardian.alertAt or 0) <= BUILDING_ALERT_DURATION
		if fresh and guardian.alertBuilding.Parent and not guardian.alertBuilding:GetAttribute("Destroyed") then
			defendPart = resolveHousePart(guardian.alertBuilding)
			if defendPart then
				defendBuilding = guardian.alertBuilding
			end
		end
		if not defendBuilding then
			guardian.alertBuilding = nil
			guardian.alertPlayer = nil
		end
	end

	-- ===== 2. Wen bekaempft er? =====
	-- Reihenfolge: wer IHN getroffen hat, dann der Angreifer eines Gebaeudes, dann wer ihm
	-- zu nahe kommt.
	--
	-- Wer den Guardian angreift, hat VORRANG vor jedem Gebaeude: er laesst die Bewachung
	-- fallen und geht auf den Angreifer. Ein Waechter, der sich schlagen laesst und dabei
	-- brav vor seinem Haus stehen bleibt, ist keine Bedrohung.
	local threat, threatRoot, hunting = nil, nil, false

	-- Die Jagd endet NICHT nach einer Frist und nicht nach Metern, sondern erst, wenn der
	-- Spieler die Stadt verlassen hat. Frueher galt PUSH_OUT_DISTANCE ab dem Kampfbeginn --
	-- wer wegrannte, hatte die 220 Studs nach wenigen Sekunden hinter sich und wurde
	-- mitten in der Stadt in Ruhe gelassen.
	--
	-- Die Abbruchbedingung verlangt BEIDES: ausserhalb der Stadt UND weit weg. Nur auf
	-- CurrentCityName zu hoeren waere zu scharf -- zwischen zwei Stadt-Huellquadern gibt es
	-- Luecken, in denen kurzzeitig "None" steht, und der Guardian wuerde dort grundlos
	-- abdrehen.
	if guardian.provokedBy then
		local root = livingRoot(guardian.provokedBy)
		local stillHere = false
		if root then
			local inCity = guardian.provokedBy:GetAttribute("CurrentCityName") == cityName
			local distanceFromGuardian = ((root.Position - rootPart.Position) * Vector3.new(1, 0, 1)).Magnitude
			stillHere = inCity or distanceFromGuardian <= PUSH_OUT_DISTANCE
		end
		if stillHere then
			threat, threatRoot, hunting = guardian.provokedBy, root, true
		else
			guardian.provokedBy = nil
		end
	end

	if not threat and defendBuilding then
		local root = livingRoot(guardian.alertPlayer)
		if root then
			threat, threatRoot = guardian.alertPlayer, root
		end
	end

	if not threat then
		local closest, closestDistance = nil, math.huge
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("CurrentCityName") == cityName then
				local root = livingRoot(player)
				if root then
					local flat = (root.Position - rootPart.Position) * Vector3.new(1, 0, 1)
					local distance = flat.Magnitude
					if distance < closestDistance then
						closest, closestDistance = player, distance
					end
				end
			end
		end
		if closest and closestDistance <= ENGAGE_RADIUS then
			threat, threatRoot = closest, livingRoot(closest)
		end
	end

	-- Waehrend der Jagd wird kein Gebaeude gedeckt -- er soll dem Angreifer nach, nicht
	-- zwischen ihm und einem Haus kleben bleiben.
	if hunting then
		defendBuilding, defendPart = nil, nil
	end

	-- ===== 3. Der Anker: wovon aus gemessen wird =====
	-- Beim Verteidigen das Gebaeude, sonst der letzte Patrouillenpunkt. Die Leine haengt
	-- am ANKER, nicht am Guardian -- so kann er sich nie weiter als der Radius entfernen,
	-- egal wie lange eine Verfolgung dauert und wohin der Spieler laeuft.
	-- Ohne Gebaeude ist der Anker die Stelle, an der der Kampf BEGANN -- einmal beim
	-- Auftauchen der Bedrohung festgehalten, nicht der zuletzt erreichte Patrouillenpunkt.
	--
	-- Genau daran scheiterte es vorher: waehrend einer Patrouille liegt patrolAnchor weit
	-- hinter dem Guardian. Wer ihn unterwegs angriff, war vom alten Punkt aus sofort
	-- weiter als PUSH_OUT_DISTANCE entfernt und galt als bereits verdraengt -- der
	-- Guardian kehrte um, statt sich zu wehren. Im Stillstand fiel es nicht auf, weil
	-- patrolAnchor dort seine eigene Position ist.
	local anchorPosition
	if defendPart then
		anchorPosition = defendPart.Position
		guardian.engageAnchor = nil
	else
		if not guardian.engageAnchor then
			guardian.engageAnchor = rootPart.Position
		end
		anchorPosition = guardian.engageAnchor
	end
	local leashRadius = config.GuardianLeashRadius or DEFAULT_GUARDIAN_LEASH_RADIUS

	-- ===== 4. Bedrohung: verdraengen =====
	if threat then
		local threatFromAnchor = (threatRoot.Position - anchorPosition) * Vector3.new(1, 0, 1)
		local threatDistanceFromAnchor = threatFromAnchor.Magnitude

		-- Die Jagd hat ihre eigene Abbruchbedingung oben (Stadt verlassen). Nur die
		-- uebrigen Faelle -- Gebaeude decken, Naeherungsangriff -- enden nach Metern.
		if not hunting and threatDistanceFromAnchor > PUSH_OUT_DISTANCE then
			-- Weit genug verdraengt -- ablassen und zurueckkehren.
			guardian.alertBuilding = nil
			guardian.alertPlayer = nil
			guardian.provokedBy = nil
			guardian.engageAnchor = nil
			guardian.returnTarget = anchorPosition
			setGuardianState(guardian, cityName, "Return", "Spieler verdraengt")
		else
			setVisorActive(guardian, true)
			guardian.protectingBuilding = defendBuilding

			-- Ziel: zwischen Anker und Spieler stehen, dabei bis auf Schlagreichweite
			-- heran. Das leistet beides zugleich -- er deckt das Gebaeude UND draengt.
			-- Auf Armlaenge herangehen, gemessen ab der Koerperoberflaeche -- sonst
			-- liefe er in den Spieler hinein und stemmte sich dauerhaft gegen dessen
			-- Kollision.
			-- ===== Wie nah er ueberhaupt heran WILL =====
			-- Das haengt an der Generation (siehe GUARDIAN_KAMPFSTIL): der Nahkaempfer geht
			-- bis auf Schlagreichweite, der Fernkaempfer bleibt auf Schussdistanz stehen,
			-- und der Mischtyp wechselt -- nach einem Nahkampftreffer weicht er fuer ein
			-- paar Sekunden zurueck und kommt danach wieder.
			--
			-- Der Nahkampf-Fall ist unveraendert: sein Halbmesser plus die halbe Armlaenge.
			-- Vorher stand dort 0.8 -- gemessen kam er damit auf eine Luecke von 14 bis 15
			-- Studs zum Stehen, also GENAU an der Schwelle von 14, und der Baton loeste mal
			-- aus und mal nicht. Die Haelfte laesst spuerbaren Spielraum.
			local stil = kampfstil(guardian)
			local abstandsFaktor = stil.Wunschabstand
			if stil.HaeltAbstand > 0 and os.clock() < (guardian.haeltAbstandBis or 0) then
				abstandsFaktor = stil.Abstandsposten
			end

			-- Der Halbmesser der BEDROHUNG geht mit ein, nicht nur sein eigener. Ohne ihn
			-- war der Zielpunkt ein Mittelpunktabstand von rund 28 Studs -- also ein Punkt
			-- INNERHALB der Spielerfigur, deren Kollisionskoerper bei hohen Stufen ueber 20
			-- Studs Halbmesser hat. Er lief bis in sie hinein und stemmte sich gegen ihre
			-- Kollision (gemeldet am 26.09.2026).
			--
			-- Derselbe Wert steht in der Reichweitenpruefung von attackIfInRange. Die beiden
			-- gehoeren zusammen: waechst der Stehabstand, ohne dass die Pruefung mitwaechst,
			-- bleibt er brav auf Armlaenge stehen und schlaegt nie zu.
			local threatHalfWidth = threatRadius(threat and threat.Character)

			local strikeDistance
			if abstandsFaktor <= 0 then
				strikeDistance = (guardian.bodyRadius or 0) + threatHalfWidth
					+ config.GuardianImpactFistRange * 0.5
			else
				strikeDistance = (guardian.bodyRadius or 0) + threatHalfWidth
					+ config.GuardianRepulsorRadius * abstandsFaktor
			end

			local destination
			if defendPart then
				local reach = math.min(threatDistanceFromAnchor, leashRadius)
				local stopShort = math.min(strikeDistance, reach)
				local direction = threatDistanceFromAnchor > 0.1 and threatFromAnchor.Unit or rootPart.CFrame.LookVector
				destination = anchorPosition + direction * math.max(reach - stopShort, 0)
			else
				-- Kein Gebaeude zu decken: auf den Spieler zu, bis auf seinen Wunschabstand.
				local toThreat = (threatRoot.Position - rootPart.Position) * Vector3.new(1, 0, 1)
				local distance = toThreat.Magnitude
				local direction = distance > 0.1 and toThreat.Unit or rootPart.CFrame.LookVector
				local vorruecken = distance - strikeDistance
				if abstandsFaktor <= 0 then
					-- Nahkaempfer: nur vor, nie zurueck. Steht der Spieler dicht vor ihm,
					-- bleibt er stehen und schlaegt -- zurueckweichen saehe aus, als wiche
					-- er aus, und das ist das Gegenteil seiner Rolle.
					vorruecken = math.max(vorruecken, 0)
				end
				-- Bei negativem Wert geht er rueckwaerts: genau so loest sich ein
				-- Fernkaempfer oder ein Mischtyp aus dem Handgemenge.
				destination = rootPart.Position + direction * vorruecken
			end

			-- Im Kampf bleibt der Blick auf der Bedrohung, egal wohin die Beine gehen. Das
			-- deckt beide Richtungen ab: beim Vorruecken aendert es nichts (Blick- und
			-- Laufrichtung sind dieselbe), beim Abstandnehmen weicht er rueckwaerts aus,
			-- statt sich wegzudrehen.
			local arrived = stepTowards(guardian, config, destination, threatRoot.Position)
			if arrived then
				faceAndStand(guardian, threatRoot.Position, true)
				setAegisShieldDeployed(guardian, defendBuilding ~= nil)
				setGuardianState(guardian, cityName, defendBuilding and "Defend" or "Engage",
					defendBuilding and ("deckt " .. defendBuilding.Name .. " gegen " .. threat.Name)
						or ("draengt " .. threat.Name))
			else
				setAegisShieldDeployed(guardian, false)
				setGuardianState(guardian, cityName, defendBuilding and "Defend" or "Engage",
					defendBuilding and ("laeuft zu " .. defendBuilding.Name)
						or ("verfolgt " .. threat.Name))
			end
			-- Auch im Laufen angreifen -- die Annaeherung war frueher eine tote Phase.
			attackIfInRange(guardian, cityName, config, threat, threatRoot.Position)
			return
		end
	end

	guardian.engageAnchor = nil -- keine Bedrohung mehr: naechster Kampf setzt neu an

	-- ===== 5. Rueckkehr =====
	if guardian.returnTarget then
		setVisorActive(guardian, false)
		setAegisShieldDeployed(guardian, false)
		if stepTowards(guardian, config, guardian.returnTarget) then
			guardian.patrolAnchor = guardian.returnTarget
			guardian.returnTarget = nil
			guardian.patrolUntil = now + math.random(PATROL_DWELL_MIN, PATROL_DWELL_MAX)
			setGuardianState(guardian, cityName, "Idle", "zurueck auf Posten")
		end
		return
	end

	-- ===== 6. Patrouille =====
	setVisorActive(guardian, false)
	setAegisShieldDeployed(guardian, false)
	guardian.protectingBuilding = nil

	if guardian.patrolTarget then
		if stepTowards(guardian, config, guardian.patrolTarget) then
			guardian.patrolAnchor = guardian.patrolTarget
			guardian.patrolTarget = nil
			guardian.patrolUntil = now + math.random(PATROL_DWELL_MIN, PATROL_DWELL_MAX)
			setGuardianState(guardian, cityName, "Idle", "am Patrouillenpunkt")
		end
		return
	end

	if not guardian.patrolUntil then
		guardian.patrolUntil = now + math.random(PATROL_DWELL_MIN, PATROL_DWELL_MAX)
	end
	if now >= guardian.patrolUntil then
		local point = pickPatrolPoint(cityName)
		if point then
			guardian.patrolTarget = point
			setGuardianState(guardian, cityName, "Patrol", "neuer Punkt")
		else
			-- Nichts gefunden (alles zerstoert?) -- spaeter erneut versuchen, statt es
			-- jedes Bild zu wiederholen.
			guardian.patrolUntil = now + PATROL_DWELL_MIN
		end
		return
	end

	faceAndStand(guardian, rootPart.Position + rootPart.CFrame.LookVector * 10)
	setGuardianState(guardian, cityName, "Idle")
end

-- ===== Spawn-Zeremonie: Bodenplatten, Sirenen, Dampf, langsames Aufrichten, dann
-- "GUARDIAN DEPLOYED". =====
local function playDeploySequence(cityName, spawnPosition)
	local deploySound = Instance.new("Sound")
	deploySound.SoundId = DEPLOY_SOUND_ID
	deploySound.Volume = 0.9
	deploySound.Parent = Workspace
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(spawnPosition)
	anchor.Parent = Workspace
	deploySound.Parent = anchor
	if deploySound.SoundId ~= "" and deploySound.SoundId ~= "rbxassetid://0" then
		deploySound:Play()
	end

	-- Dampf-Ausstoss am Boden.
	local steamAttachment = Instance.new("Attachment")
	steamAttachment.Parent = anchor
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Color3.fromRGB(210, 210, 215))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(1, 1.5)
	steam.Speed = NumberRange.new(3, 6)
	steam.Rate = 0
	steam.Parent = steamAttachment
	steam:Emit(24)

	Debris:AddItem(anchor, 15)

	-- "GUARDIAN DEPLOYED" an alle Spieler dieser Stadt.
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName then
			if _G.FlashCityAlertIndicator then
				_G.FlashCityAlertIndicator(Color3.fromRGB(90, 160, 230))
			end
		end
	end
end

-- ===== Spawnen/Despawnen =====
local function findCitySpawnPoint(cityName)
	local cityContainer
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:GetAttribute("CityName") == cityName then
			cityContainer = descendant
			break
		end
	end
	if not cityContainer then
		return nil
	end
	local spawnPart = cityContainer:FindFirstChild("GuardianSpawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.Position
	end

	-- RÜCKFALL 1: vor das Gebäude, das der Guardian ohnehin bewachen wird.
	--
	-- Sinnvoller als der Modell-Pivot: der Guardian verbringt sein ganzes Leben damit,
	-- sich vor dieses Gebäude zu stellen -- dort zu erscheinen erspart ihm den langen
	-- Anmarsch und liegt garantiert innerhalb der Stadt. Der Pivot eines Stadtmodells
	-- kann dagegen irgendwo liegen, auch unter dem Boden oder in einem Gebäude.
	--
	-- Gedacht als Notnagel für Städte ohne vorbereiteten 'GuardianSpawn'-Part. Für eine
	-- inszenierte Ankunft (Sichtachse, Abstand, Blickrichtung) gehört weiterhin ein
	-- eigener Part in den Workspace -- deshalb die Warnung.
	local buildings = findProtectedBuildings(cityName)
	local building = buildings and buildings[1]
	local buildingPart = building and (building.PrimaryPart or building:FindFirstChildWhichIsA("BasePart", true))
	if buildingPart then
		local ok, _, size = pcall(function()
			return building:GetBoundingBox()
		end)
		-- Etwas Abstand, damit er nicht IM Gebäude steht.
		local offset = (ok and size) and math.max(size.X, size.Z) * 0.6 + 25 or 45
		warn(
			string.format(
				"[CityDefenderService] '%s' hat keinen 'GuardianSpawn'-Part -- Guardian erscheint "
					.. "ersatzweise %d Studs vor '%s'. Für eine kontrollierte Ankunft bitte in Studio "
					.. "einen 'GuardianSpawn'-Part in der Stadt anlegen.",
				cityName,
				math.floor(offset),
				building.Name
			)
		)
		return buildingPart.Position + Vector3.new(offset, 0, 0)
	end

	-- RÜCKFALL 2: Modell-Pivot. Letzte Möglichkeit, oft unschön, aber besser als gar
	-- kein Guardian -- ohne ihn lässt sich die Stadt nicht abschliessen.
	if cityContainer:IsA("Model") then
		local ok, cframe = pcall(function()
			return cityContainer:GetPivot()
		end)
		if ok then
			warn(
				"[CityDefenderService] '"
					.. cityName
					.. "' hat weder 'GuardianSpawn' noch ein geschütztes Gebäude -- Guardian erscheint am Modell-Pivot der Stadt."
			)
			return cframe.Position
		end
	end
	return nil
end

_G.SpawnGuardianForCity = function(cityName)
	local existing = activeGuardians[cityName]
	if existing then
		-- Zusätzliches Sicherheitsnetz (gleiches Muster wie kürzlich bei
		-- MilitaryService): nur abbrechen, wenn dort auch WIRKLICH noch ein lebendiges
		-- Modell steht -- ein Rest-Eintrag nach einem Sprung-Reset soll einen
		-- Neuaufbau nicht mehr dauerhaft blockieren können.
		if existing.model and existing.model.Parent then
			return
		end
		activeGuardians[cityName] = nil
	end
	local config = CityAlertConfig.GetCityConfig(cityName)
	if not config.GuardianHP then
		warn("[CityDefenderService] Keine Guardian-Werte für '" .. cityName .. "' konfiguriert -- übersprungen (bisher nur City vorbereitet).")
		return
	end

	local spawnPosition = findCitySpawnPoint(cityName)
	if not spawnPosition then
		warn("[CityDefenderService] Kein Spawn-Punkt für '" .. cityName .. "' gefunden (fehlt ein 'GuardianSpawn'-Part?).")
		return
	end

	local model = getGuardianTemplate(cityName)
	model.Name = "Guardian_" .. cityName
	if not model.PrimaryPart then
		-- Häufiger Stolperstein: PrimaryPart in Studio schlicht vergessen zu setzen.
		-- Automatisch das GRÖSSTE BasePart im Modell als PrimaryPart nutzen (meist der
		-- Torso/Körper-Kern -- sinnvoller als irgendein zufälliges kleines Teil), statt
		-- den Spawn komplett zu verweigern.
		local largestPart = nil
		local largestVolume = 0
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
				if volume > largestVolume then
					largestVolume = volume
					largestPart = descendant
				end
			end
		end
		if largestPart then
			model.PrimaryPart = largestPart
			warn("[CityDefenderService] Guardian-Modell '" .. cityName .. "' hatte keinen PrimaryPart gesetzt -- '" .. largestPart.Name .. "' automatisch als PrimaryPart übernommen. Empfehlung: in Studio manuell setzen (Model -> PrimaryPart-Property).")
		else
			warn("[CityDefenderService] Guardian-Modell hat keinen PrimaryPart UND kein einziges BasePart gefunden -- Spawn abgebrochen.")
			model:Destroy()
			return
		end
	end
	model:PivotTo(CFrame.new(spawnPosition))
	-- Ab jetzt glaettet der Client seine Bewegung (siehe SmoothMotion). Der Spawn selbst
	-- bekommt KEIN Ziel mitgeteilt: das erste Ziel setzt der erste Bewegungsschritt, und bis
	-- dahin steht das Modell dort, wo der Server es hingestellt hat.
	SmoothMotion.Track(model)

	-- ===== Auf die Zielhoehe bringen =====
	-- Die Guardian-Modelle bringen ihre eigene Groesse mit, und die hatte mit der
	-- Spielfigur nichts zu tun: der City-Guardian war KLEINER als der Spieler, gegen den
	-- er antritt. Ein Boss, zu dem man hinunterschaut, ist keiner.
	--
	-- IM SPIEL BESTAETIGT am 20.09.2026: "Der Guardian war zu klein. Um ihn ernst zu
	-- nehmen, muss er etwas groesser sein als die Spielfigur."
	--
	-- Gemessen statt gerechnet: die Hoehe kommt aus der Bounding Box des fertig
	-- zusammengebauten Modells, nicht aus einer Zahl im Modell. Muss VOR soleOffset und
	-- bodyRadius weiter unten geschehen -- die beiden leiten sich aus derselben Box ab und
	-- waeren sonst auf die alte Groesse geeicht.
	-- ===== Jeder Ausgang meldet sich =====
	-- Bis zum 20.09.2026 sprach hier nur der Erfolg. Fehlte GuardianHeightStuds oder liess
	-- sich das Modell nicht vermessen, geschah lautlos nichts -- und der Guardian stand in
	-- seiner Eigengroesse da, ohne dass irgendwo stuende, warum. Genau so ist er ueber
	-- Wochen kleiner geblieben als die Figur, gegen die er antritt.
	local zielHoehe = config.GuardianHeightStuds
	if not (zielHoehe and zielHoehe > 0) then
		warn(string.format("[Kaiju-Debug] Guardian '%s': kein GuardianHeightStuds in der "
			.. "Config -- er behaelt die Eigengroesse seines Modells.", cityName))
	else
		local okBox, _, boxGroesse = pcall(function()
			return model:GetBoundingBox()
		end)
		if not (okBox and boxGroesse and boxGroesse.Y > 0.01) then
			warn(string.format("[Kaiju-Debug] Guardian '%s': Hoehe nicht messbar -- "
				.. "keine Skalierung auf %.0f Studs.", cityName, zielHoehe))
		else
			local faktor = zielHoehe / boxGroesse.Y
			if math.abs(faktor - 1) <= 0.01 then
				print(string.format("[Kaiju-Debug] Guardian '%s': steht bereits auf %.1f "
					.. "Studs -- nichts zu tun.", cityName, boxGroesse.Y))
			else
				local okScale = pcall(function()
					model:ScaleTo(model:GetScale() * faktor)
				end)
				if okScale then
					print(string.format("[Kaiju-Debug] Guardian '%s': %.1f auf %.1f Studs "
						.. "skaliert (Faktor %.2f).", cityName, boxGroesse.Y, zielHoehe, faktor))
				else
					warn(string.format("[Kaiju-Debug] Guardian '%s': ScaleTo fehlgeschlagen -- "
						.. "er bleibt bei %.1f Studs.", cityName, boxGroesse.Y))
				end
			end
		end
	end

	model.Parent = Workspace
	CollectionService:AddTag(model, "Guardian")
	local touchParts = connectGuardianTouch(cityName, model)
	print("[Kaiju-Debug] Guardian '" .. cityName .. "' gespawnt -- Sprung-Trefferflächen verbunden:", touchParts)

	local guardian = {
		model = model,
		hp = config.GuardianHP,
		maxHP = config.GuardianHP,
		shield = config.GuardianShieldHP,
		maxShield = config.GuardianShieldHP,
		state = "Scan",
		defeated = false,
		lastHitAt = 0,
		lastFistAt = 0,
		lastRepulsorAt = 0,
		shieldDeployed = false,
		-- Nur fuer die Ausgabe: verhindert, dass bei jedem einzelnen Treffer eine Zeile
		-- "blockt mit dem Schild" kommt. Wird zurueckgesetzt, wenn der Schild bricht.
		shieldBlockGemeldet = false,
		-- Animations-Schnittstelle und Generation. Beide fehlen bei Guardians, die aus
		-- ServerStorage geklont werden -- dort greift der prozedurale Rueckfall.
		animation = guardianAnimation[model],
		assetName = guardianAssetName[model],
	}

	-- Visor sofort auf die Patrouillenfarbe setzen, statt auf den ersten Durchlauf der
	-- Update-Schleife zu warten. Der Workshop liefert das Teil in seiner Bau-Farbe aus --
	-- ohne das erschiene der Guardian den ersten Moment mit totem Visor, ausgerechnet
	-- waehrend der Auftritt laeuft und alle hinsehen.
	setVisorActive(guardian, false)

	-- Abstand des PrimaryPart zur Sohle merken. Die Modelle unterscheiden sich darin
	-- erheblich (Platzhalter: Torso, rund 15 Studs über der Sohle -- Warden: Root genau
	-- AUF der Sohle). Beim Laufen wird der Wert gebraucht, um den Guardian auf dem Boden
	-- zu halten, statt ihn auf der Spawn-Höhe schweben zu lassen.
	guardian.soleOffset = 0
	local okBounds, boundsCFrame, boundsSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if okBounds and boundsSize then
		guardian.soleOffset = model.PrimaryPart.Position.Y - (boundsCFrame.Position.Y - boundsSize.Y * 0.5)

		-- Waagerechter Halbmesser des Koerpers. Die Angriffsreichweiten im Config sind
		-- ARMLAENGEN -- was der Guardian ueber seinen eigenen Koerper hinaus erreicht --
		-- gemessen wird aber ab PrimaryPart, also ab seiner Mitte. Bei einer rund 26 Studs
		-- breiten Figur liegen die 14 Studs des Nahangriffs damit INNERHALB seines Rumpfes:
		-- die Kollision haelt den Spieler weiter draussen, als der Arm laut Config reicht,
		-- und der Baton konnte nie ausloesen. Der Impuls (Radius 22) kam durch -- genau das
		-- Bild, das im Spiel zu sehen war.
		guardian.bodyRadius = math.max(boundsSize.X, boundsSize.Z) * 0.5
	end

	-- Ruhelage der Beine erfassen. MUSS nach dem PivotTo auf den Spawn-Punkt passieren --
	-- die Posen werden relativ zum Modell-Pivot gespeichert, das Modell muss dafür fertig
	-- platziert sein.
	local walkRig = captureWalkRig(guardian)
	-- Welcher der beiden Wege gilt, entscheidet alles Weitere: MIT Rig laeuft die
	-- Animation ueber Motor6D beim Client, OHNE Rig ueber die prozedurale Beinpose hier.
	-- Steht hier "Rig: nein" und zugleich "Beine erfasst: 0", kann sich nichts bewegen --
	-- dann fehlen dem Modell die Teile 'LeftHipBearing' / 'RightHipBearing'.
	print(string.format("[Kaiju-Debug] Guardian '%s' Laufanimation -- Rig: %s, Beine erfasst: %d.",
		cityName, guardian.animation and "ja" or "nein", #walkRig))

	guardian.healthBar = createHealthBar(guardian)
	activeGuardians[cityName] = guardian

	playDeploySequence(cityName, spawnPosition)
end

-- Einziger Weg, auf dem ein Guardian das Spielfeld verlaesst: die Alarmstufe faellt unter
-- 5. Nach einer Niederlage heisst das konkret, dass die Stadt gebrochen wurde und die
-- freie Zerstoerungsphase vorbei ist -- bis dahin liegt er sichtbar da.
local function despawnGuardianForCity(cityName)
	local guardian = activeGuardians[cityName]
	if not guardian then
		return
	end
	-- Zuerst die Animations-Schnittstelle: ihr Destroy() entfernt die Client-Skripte aus
	-- den PlayerGuis und das RemoteEvent aus ReplicatedStorage. Ohne das bliebe je
	-- besiegtem Guardian ein totes Skript-Paar zurueck.
	if guardian.animation then
		pcall(function()
			guardian.animation.Destroy()
		end)
	end
	if guardian.model and guardian.model.Parent then
		guardian.model:Destroy()
	end
	activeGuardians[cityName] = nil
end
_G.DespawnGuardianForCity = despawnGuardianForCity

-- ===== Angegriffenes Gebäude melden =====
-- Wird von HouseHandler.damageHouse bei JEDEM Treffer aufgerufen.
--
-- Ohne das reagierte der Guardian nur auf NÄHE: der Spieler musste nah genug an einem
-- geschützten Gebäude stehen. Wer aus grösserer Entfernung zuschlug, blieb unbehelligt --
-- in MegaCity gemessene 86 Studs reichten bereits. Ein Angriff auf ein Gebäude ist aber
-- genau der Anlass, auf den ein Wächter reagieren soll, unabhängig von der Entfernung.
_G.NotifyGuardianBuildingAttacked = function(house, attackerPlayer)
	if not house or not _G.ResolveCityName then
		return
	end
	local cityName = _G.ResolveCityName(house)
	local guardian = cityName and activeGuardians[cityName]
	if not guardian or guardian.defeated then
		return
	end

	-- Nur geschützte Gebäude alarmieren ihn. In einer Stadt, die noch auf dem
	-- MaxHealth-Rückfall läuft (siehe findProtectedBuildings), gibt es keine Tags --
	-- dort zählt jedes Gebäude der Stadt, sonst bliebe er dort weiterhin untätig.
	if not guardian.usesFallbackBuildings and not CollectionService:HasTag(house, GUARDIAN_PROTECT_TAG) then
		return
	end

	guardian.alertBuilding = house
	guardian.alertAt = os.clock()
	guardian.alertPlayer = attackerPlayer
end

-- ===== Update-Schleife =====
RunService.Heartbeat:Connect(function()
	for cityName, guardian in pairs(activeGuardians) do
		local config = CityAlertConfig.GetCityConfig(cityName)
		local ok, err = pcall(updateGuardian, cityName, guardian, config)
		if not ok then
			warn("[CityDefenderService] Fehler bei Guardian-Update:", err)
		end
	end
end)

-- ===== Auf Alert-Level-Wechsel reagieren =====
task.spawn(function()
	local attempts = 0
	while not _G.CityAlertLevelChanged and attempts < 100 do
		task.wait(0.1)
		attempts += 1
	end
	if not _G.CityAlertLevelChanged then
		warn("[CityDefenderService] _G.CityAlertLevelChanged nie gefunden (10s Timeout) -- Level 5 bleibt wirkungslos. Läuft CityAlertService.lua?")
		return
	end

	_G.CityAlertLevelChanged.Event:Connect(function(cityName, newLevel, oldLevel)
		if newLevel == 5 and oldLevel == 4 then
			_G.SpawnGuardianForCity(cityName)
		elseif newLevel < 5 and oldLevel >= 5 then
			-- ===== Eine von Hand gesteuerte Stadt raeumt hier NICHTS ab =====
			-- Im Prolog setzt der PrologueOrchestrator die Alarmstufen selbst, nach seinem
			-- Drehbuch. Faellt sie dabei unter 5 -- und sei es nur fuer einen Moment --
			-- verschwand der Guardian mitten in der Szene. Genau das ist Amancio am
			-- 21.09.2026 passiert.
			--
			-- Wer eine Stadt von Hand steuert, besitzt auch ihre Folgen: der Orchestrator
			-- raeumt seinen Guardian selbst ab, am Ende des Prologs, ueber
			-- _G.DespawnGuardianForCity. Diese Zeile hier ist die AUTOMATIK, und die hat
			-- sich herauszuhalten.
			if _G.IsCityManuallyDriven and _G.IsCityManuallyDriven(cityName) then
				print(string.format("[Kaiju-Debug] Guardian '%s' bleibt stehen -- die Stadt "
					.. "wird von Hand gesteuert (Stufe %d -> %d).", cityName, oldLevel, newLevel))
				return
			end

			-- WICHTIG: reagiert auf JEDEN Abfall unter Level 5, nicht nur den exakten
			-- 5->4-Schritt -- ein Sprung-Reset (z.B. CITY BROKEN: 5->0 in einem Schritt)
			-- hätte den alten, exakten Trigger sonst nie ausgelöst und activeGuardians
			-- wäre dauerhaft hängen geblieben (gleicher Bug wie kürzlich bei
			-- MilitaryService gefunden und behoben).
			despawnGuardianForCity(cityName)
		end
	end)
end)

-- ===== Der Guardian regeneriert langsam, solange nicht gekaempft wird =====
--
-- Bis hierher tat er das GAR NICHT: es gab im ganzen Dienst keine Stelle, die seine
-- Lebenspunkte je wieder erhoeht haette. Der Spieler respawnte voll geheilt, der Guardian
-- behielt jeden Treffer -- jeder Tod war fuer den einen ein kostenloser Neuanfang und fuer
-- den anderen keiner. Sterben war damit die guenstigste Art, den Kampf zu gewinnen.
--
-- IM SPIEL BESTAETIGT am 20.09.2026: "ich bin 2 mal durch Guardian gestorben. Aber er hat
-- sich weniger schnell erholt als ich, so dass ich jedes Mal mehr Vorteil hatte."
--
-- LANGSAM und nicht sprunghaft, ausdruecklich so gewuenscht. Ein Guardian, der beim Tod
-- des Spielers sofort wieder voll dasteht, macht jeden Fehlversuch wertlos -- die bis
-- dahin geleistete Arbeit waere weg. So bleibt ein Vorsprung bestehen, er schmilzt nur.
--
-- Dasselbe Muster wie beim Barrikadenschild (ShieldRegenDelay / ShieldRegenRate): erst
-- eine Pause nach dem letzten Treffer, dann ein stetiger Anteil je Sekunde. Die Pause
-- verhindert, dass er sich MITTEN im Kampf zwischen zwei Schlaegen erholt.
local GUARDIAN_REGEN_DELAY = 6 -- Sekunden ohne Treffer, bevor es losgeht
local GUARDIAN_REGEN_RATE = 0.02 -- Anteil der vollen Lebenspunkte je Sekunde -- 50s auf voll

RunService.Heartbeat:Connect(function(deltaTime)
	local jetzt = os.clock()
	for _, guardian in pairs(activeGuardians) do
		if not guardian.defeated
			and guardian.hp and guardian.maxHP
			and guardian.hp > 0 and guardian.hp < guardian.maxHP
			and jetzt - (guardian.lastDamageAt or 0) >= GUARDIAN_REGEN_DELAY then
			guardian.hp = math.min(
				guardian.hp + guardian.maxHP * GUARDIAN_REGEN_RATE * deltaTime,
				guardian.maxHP)
			updateHealthBar(guardian)
		end
	end
end)

print("[Kaiju] CityDefenderService bereit -- Level 5 (Guardian, vorerst nur City).")