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

local GUARDIAN_PROTECT_TAG = "GuardianProtect"
local RESPAWN_DELAY = 45 -- Sekunden, bis ein besiegter Guardian dieser Stadt wieder auftaucht

-- Platzhalter-Sound-IDs -- bitte bei Gelegenheit durch echte ersetzen.
local DEPLOY_SOUND_ID = "rbxassetid://9081625499" -- Sirenen/Dampf beim Aufstehen
local IMPACT_FIST_SOUND_ID = "" -- KCHUNK beim Fausthieb
local REPULSOR_SOUND_ID = "" -- Energie-Impuls
local SHIELD_ACTIVATE_SOUND_ID = "" -- CHUNK-CHUNK-WHOOM beim Schild-Ausfahren
local DEFEAT_SOUND_ID = "" -- beim Niedergehen

-- [cityName] = { model=, humanoid=, state=..., ... } -- nur EIN Guardian gleichzeitig pro Stadt.
local activeGuardians = {}

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

local GUARDIAN_LADDER = {
	{ asset = "WardenShepherd", label = "Warden-I Shepherd" },
	{ asset = "MarshalRoadblock", label = "Marshal-II Roadblock" },
	{ asset = "AegisInterceptor", label = "Aegis-III Interceptor" },
}

-- In Kapitel I steht der erste Guardian in City -- Position 3 der Staffel oben.
local FIRST_GUARDIAN_CITY_IN_CHAPTER_1 = 3

local cityLadderIndex = {}
for index, cityName in ipairs(CITY_SIZE_LADDER) do
	cityLadderIndex[cityName] = index
end

local function getGuardianPlan(cityName)
	local cityIndex = cityLadderIndex[cityName]
	if not cityIndex or #GUARDIAN_LADDER == 0 then
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

	-- Generation 4 und 5 gibt es als Asset noch nicht. Bis dahin bekommen die oberen
	-- Staedte die hoechste vorhandene -- besser ein zu schwacher Guardian als gar keiner,
	-- und der Platzhalter waere die schlechtere Alternative.
	return GUARDIAN_LADDER[math.min(rung, #GUARDIAN_LADDER)]
end

local WARDEN_GROUND_CLEARANCE = 0

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
		built.Parent = nil
		staging:Destroy()
		return built
	end)

	if not ok or not model then
		warn("[CityDefenderService] " .. plan.label .. " konnte nicht gebaut werden (" .. tostring(model) .. ") -- nutze Platzhalter.")
		return nil
	end

	-- Root auf Sohlenhöhe bringen (siehe Kommentar oben). Root ist ein eigenes,
	-- unsichtbares Teil -- es allein zu verschieben verändert die Geometrie nicht.
	local root = model.PrimaryPart
	if root then
		local boundsCFrame, boundsSize = model:GetBoundingBox()
		local soleY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
		root.Position = Vector3.new(
			root.Position.X,
			soleY - WARDEN_GROUND_CLEARANCE,
			root.Position.Z
		)
	end

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
	-- fireRepulsorPulse, setAegisShieldDeployed). Der Warden bringt eigene Namen mit.
	-- Was nicht zugeordnet wird, ist überall nil-geprüft und schaltet nur die jeweilige
	-- Optik ab -- keine Fehler.
	local visor = model:FindFirstChild("VisorSensor", true)
	if visor then
		visor.Name = "Visor"
	end

	-- ACHTUNG: "RightHand" ist beim Warden ein FOLDER. Der Dienst tweent .Position am
	-- gefundenen Objekt -- ein Folder würde dort abstürzen. Deshalb die Handfläche darin.
	local rightHand = model:FindFirstChild("RightHand", true)
	local palm = rightHand and rightHand:FindFirstChild("Palm")
	if palm then
		palm.Name = "ImpactFist"
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
local function setVisorActive(guardian, active)
	local visor = guardian.model:FindFirstChild("Visor", true)
	if not visor then
		return
	end
	local targetColor = active and Color3.fromRGB(255, 60, 50) or Color3.fromRGB(20, 20, 20)
	TweenService:Create(visor, TweenInfo.new(0.4), { Color = targetColor }):Play()
end

-- ===== Geschützte Gebäude finden: getaggt, sonst das Gebäude mit der höchsten
-- MaxHealth dieser Stadt. =====
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
		return tagged
	end

	-- Fallback: kein Gebäude getaggt -- nimm das mit der höchsten MaxHealth dieser Stadt.
	local best, bestHealth = nil, 0
	if _G.HOUSE_TAG and _G.ResolveCityName then
		for _, house in ipairs(CollectionService:GetTagged(_G.HOUSE_TAG)) do
			if not house:GetAttribute("Destroyed") and _G.ResolveCityName(house) == cityName then
				local maxHealth = house:GetAttribute("MaxHealth") or 0
				if maxHealth > bestHealth then
					best, bestHealth = house, maxHealth
				end
			end
		end
	end
	return best and { best } or {}
end

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

	if guardian.shield > 0 then
		guardian.shield = math.max(guardian.shield - amount, 0)
	else
		guardian.hp = math.max(guardian.hp - amount, 0)
	end
	updateHealthBar(guardian)

	if guardian.hp <= 0 then
		guardian.defeated = true
		guardian.state = "Defeated"

		-- Achievements: "Ersten Guardian besiegt".
		-- Lebensstatistik. Im Mehrspielerbetrieb zaehlt der LETZTE Treffer: attackerPlayer
		-- ist der, dessen Schaden den Guardian auf 0 gebracht hat.
		if attackerPlayer and _G.RecordStat then
			_G.RecordStat(attackerPlayer, "GuardianDefeated")
			_G.RecordStat(attackerPlayer, "GuardianDefeated." .. cityName)

			-- Kapitelabschluss: wer dem MegaCity-Guardian den TÖDLICHEN Treffer versetzt,
			-- hat das Kapitel durchgespielt. Im Mehrspielerbetrieb zählt ausdrücklich nur
			-- der letzte Schlag, nicht die Beteiligung.
			if cityName == "MegaCity" then
				_G.RecordStat(attackerPlayer, "ChaptersCompleted")
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

		-- Langsam umkippen, dann verschwinden.
		local currentCFrame = guardian.model:GetPivot()
		local fallCFrame = currentCFrame * CFrame.Angles(math.rad(80), 0, 0)
		TweenService:Create(guardian.model.PrimaryPart, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {}):Play()
		local fallTween = TweenService:Create(guardian.humanoidRootAnchor or guardian.model.PrimaryPart, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {})
		fallTween:Play()
		task.spawn(function()
			pcall(function()
				guardian.model:PivotTo(fallCFrame)
			end)
		end)

		task.delay(2, function()
			if guardian.model and guardian.model.Parent then
				guardian.model:Destroy()
			end
		end)

		task.delay(RESPAWN_DELAY, function()
			-- Nur respawnen, falls die Stadt noch/wieder auf Level 5 ist.
			if _G.GetCityAlertLevel and _G.GetCityAlertLevel(cityName) == 5 then
				activeGuardians[cityName] = nil
				_G.SpawnGuardianForCity(cityName)
			else
				activeGuardians[cityName] = nil
			end
		end)
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
local function fireImpactFist(guardian, target, config)
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

local function fireRepulsorPulse(guardian, cityName, config)
	if os.clock() - (guardian.lastRepulsorAt or 0) < config.GuardianRepulsorCooldown then
		return
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

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName and player.Character then
			local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
				local distance = (targetRoot.Position - origin).Magnitude
				if distance <= config.GuardianRepulsorRadius then
					targetHumanoid:TakeDamage(config.GuardianRepulsorDamage)
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
local function setAegisShieldDeployed(guardian, deployed)
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

	local target = nil
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName and player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				target = player
				break
			end
		end
	end

	if not target then
		guardian.state = "Scan"
		guardian.protectingBuilding = nil
		setVisorActive(guardian, false)
		setAegisShieldDeployed(guardian, false)
		relaxWalkPose(guardian)
		return
	end

	local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return
	end

	-- Nächstes geschütztes Gebäude zum Spieler finden -- der Guardian positioniert sich
	-- davor, sobald der Spieler in dessen Nähe kommt.
	local buildings = findProtectedBuildings(cityName)
	local nearestBuilding, nearestDistance = nil, math.huge
	for _, house in ipairs(buildings) do
		local housePart = house.PrimaryPart or house:FindFirstChildWhichIsA("BasePart")
		if housePart then
			local distance = (housePart.Position - targetRoot.Position).Magnitude
			if distance < nearestDistance then
				nearestBuilding, nearestDistance = house, distance
			end
		end
	end

	local SCAN_ALERT_RADIUS = 60 -- ab hier gilt der Spieler als Bedrohung für ein Gebäude

	print("[Kaiju-Debug] Guardian '" .. cityName .. "' Update -- target:", target.Name, "nearestBuilding:", nearestBuilding and nearestBuilding.Name or "keins gefunden", "nearestDistance:", nearestDistance, "SCAN_ALERT_RADIUS:", SCAN_ALERT_RADIUS, "geschützte Gebäude insgesamt:", #buildings)

	if nearestBuilding and nearestDistance <= SCAN_ALERT_RADIUS then
		guardian.protectingBuilding = nearestBuilding
		setVisorActive(guardian, true)

		local housePart = nearestBuilding.PrimaryPart or nearestBuilding:FindFirstChildWhichIsA("BasePart")
		local toPlayerDirection = (targetRoot.Position - housePart.Position)
		toPlayerDirection = Vector3.new(toPlayerDirection.X, 0, toPlayerDirection.Z)
		if toPlayerDirection.Magnitude < 0.1 then
			toPlayerDirection = Vector3.new(0, 0, 1)
		end
		toPlayerDirection = toPlayerDirection.Unit
		local blockPosition = housePart.Position + toPlayerDirection * config.GuardianProtectRadius

		local currentPosition = rootPart.Position
		local toBlockPosition = blockPosition - currentPosition
		local horizontalDistance = Vector3.new(toBlockPosition.X, 0, toBlockPosition.Z).Magnitude

		if horizontalDistance > ARRIVAL_THRESHOLD then
			guardian.state = "Position"
			setAegisShieldDeployed(guardian, false)
			local direction = Vector3.new(toBlockPosition.X, 0, toBlockPosition.Z).Unit
			local deltaTime = RunService.Heartbeat:Wait()
			local step = direction * config.GuardianMoveSpeed * deltaTime
			if step.Magnitude > horizontalDistance then
				step = Vector3.new(toBlockPosition.X, 0, toBlockPosition.Z)
			end
			-- Auf Bodenhöhe setzen, statt auf der Spawn-Höhe weiterzuschweben.
			local newPosition = groundedPosition(guardian, currentPosition + step)

			-- Laufanimation: Phase weiterdrehen und einblenden.
			guardian.walkPhase = (guardian.walkPhase or 0) + deltaTime * WALK_CYCLE_SPEED * math.pi * 2
			guardian.walkBlend = math.min((guardian.walkBlend or 0) + deltaTime * WALK_BLEND_PER_SECOND, 1)

			-- Körper wiegt im Schritttakt. Zweimal pro Zyklus -- einmal je aufsetzendem
			-- Fuss -- deshalb der Betrag des Sinus.
			local bob = math.abs(math.sin(guardian.walkPhase)) * WALK_BODY_BOB_STUDS * guardian.walkBlend
			newPosition = newPosition + Vector3.new(0, bob, 0)

			-- In LAUFRICHTUNG schauen. Vorher wurde "newPosition - toPlayerDirection"
			-- anvisiert -- das ist die Richtung VOM Spieler WEG, der Guardian lief also
			-- rückwärts bzw. seitlich auf den Spieler zu.
			local facingCFrame = CFrame.lookAt(newPosition, newPosition + direction)
			guardian.model:PivotTo(facingCFrame)
			applyWalkPose(guardian)
		else
			-- Angekommen -- blockieren + ggf. kontern.
			guardian.state = "Block"
			setAegisShieldDeployed(guardian, true)
			local standPosition = groundedPosition(guardian, currentPosition)
			local facingCFrame = CFrame.lookAt(standPosition, standPosition + (targetRoot.Position - standPosition) * Vector3.new(1, 0, 1))
			guardian.model:PivotTo(facingCFrame)
			relaxWalkPose(guardian)

			local distanceToPlayer = (targetRoot.Position - standPosition).Magnitude
			if distanceToPlayer <= config.GuardianImpactFistRange then
				guardian.state = "Counter"
				fireImpactFist(guardian, target, config)
			elseif distanceToPlayer <= config.GuardianRepulsorRadius * 1.3 then
				fireRepulsorPulse(guardian, cityName, config)
			end
		end
	else
		guardian.protectingBuilding = nil
		guardian.state = "Scan"
		setVisorActive(guardian, false)
		setAegisShieldDeployed(guardian, false)
		relaxWalkPose(guardian)
	end

	updateHealthBar(guardian)
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
	}
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
	end

	-- Ruhelage der Beine erfassen. MUSS nach dem PivotTo auf den Spawn-Punkt passieren --
	-- die Posen werden relativ zum Modell-Pivot gespeichert, das Modell muss dafür fertig
	-- platziert sein.
	local walkRig = captureWalkRig(guardian)
	print("[Kaiju-Debug] Guardian '" .. cityName .. "' Laufanimation -- Beine erfasst:", #walkRig)

	guardian.healthBar = createHealthBar(guardian)
	activeGuardians[cityName] = guardian

	playDeploySequence(cityName, spawnPosition)
end

local function despawnGuardianForCity(cityName)
	local guardian = activeGuardians[cityName]
	if not guardian then
		return
	end
	if guardian.model and guardian.model.Parent then
		guardian.model:Destroy()
	end
	activeGuardians[cityName] = nil
end
_G.DespawnGuardianForCity = despawnGuardianForCity

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
			-- WICHTIG: reagiert auf JEDEN Abfall unter Level 5, nicht nur den exakten
			-- 5->4-Schritt -- ein Sprung-Reset (z.B. CITY BROKEN: 5->0 in einem Schritt)
			-- hätte den alten, exakten Trigger sonst nie ausgelöst und activeGuardians
			-- wäre dauerhaft hängen geblieben (gleicher Bug wie kürzlich bei
			-- MilitaryService gefunden und behoben).
			despawnGuardianForCity(cityName)
		end
	end)
end)

print("[Kaiju] CityDefenderService bereit -- Level 5 (Guardian, vorerst nur City).")