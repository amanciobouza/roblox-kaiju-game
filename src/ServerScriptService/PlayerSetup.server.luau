-- VERSION: 2026-08-26 #24
-- TUNING: Sanctuary-Grundgrösse von 1 auf 0.5 reduziert (Formel 0.5 + Scale*0.1)
-- Ort in Studio: ServerScriptService
-- Erstellt Leaderstats, lädt/speichert Spielerdaten, wendet Skins auf den Charakter an
-- (Farbe + Werte), verwaltet Level-Aufstieg (mit Cap alle 5 Level, freigeschaltet per
-- Skin-Kauf), die 3 Kraft-Werte (Bein/Arm/Körper), die zusammen die Gesamtstärke bilden,
-- sowie die Evolution-Skillwerte (Speed/Money/Damage/Training/Cooldown/Luck).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local DataStoreService = game:GetService("DataStoreService")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")

local SkinsConfig = require(ReplicatedStorage:WaitForChild("SkinsConfig"))
local PlayerDataStore = DataStoreService:GetDataStore("KaijuGame_PlayerData_v1")

local EquipSkinEvent = RemoteEventUtils.GetOrCreate("EquipSkinEvent")
local PurchaseSkinEvent = RemoteEventUtils.GetOrCreate("PurchaseSkinEvent")

local XP_PER_LEVEL_BASE = 12000 -- ÷100 (war 1.200.000) -- konsistent zur XP_SCALE-Korrektur in HouseHandler.lua
local XP_PER_LEVEL_GROWTH = 1.18
local LEVELS_PER_SKIN_TIER = 10 -- alle 10 Level braucht es den nächsten Skin, um weiterzuleveln (1 Tier pro Stadtzone)
local STAT_CAP_PER_LEVEL = 10 -- max. Wert pro Kraft-Stat (Bein/Arm/Körper) = Level * 10

-- Evolution-Skills: jeder Level gibt +BONUS_PRO_LEVEL auf den jeweiligen Effekt
local EVO_BONUS_PER_LEVEL = 0.02 -- Speed: +2% pro Level
local EVO_MAX_LEVEL = 5

-- Auch für den Client sichtbar machen (fürs HUD)
local statCapPerLevelValue = Instance.new("IntValue")
statCapPerLevelValue.Name = "StatCapPerLevel"
statCapPerLevelValue.Value = STAT_CAP_PER_LEVEL
statCapPerLevelValue.Parent = ReplicatedStorage

local function xpNeededForLevel(level)
	return math.floor(XP_PER_LEVEL_BASE * (XP_PER_LEVEL_GROWTH ^ level))
end
_G.XPNeededForLevel = xpNeededForLevel

-- Level-Obergrenze: Ohne gekaufte Skins kommt man bis Level 5 (kostenloser Skin_0 zählt
-- nicht mit). Jeder zusätzlich gekaufte Skin hebt die Grenze um weitere 5 Level an.
local function getLevelCap(player)
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	if not unlockedFolder then
		return LEVELS_PER_SKIN_TIER
	end

	local paidSkinsOwned = 0
	for _, marker in ipairs(unlockedFolder:GetChildren()) do
		if marker.Value > 0 then
			paidSkinsOwned += 1
		end
	end

	return LEVELS_PER_SKIN_TIER * (1 + paidSkinsOwned)
end

-- Berechnet die Gesamtstärke (Bein + Arm + Körper), wendet den Evolution-Schaden-Bonus an,
-- berücksichtigt einen evtl. aktiven temporären Schaden-Boost (z.B. aus einem Geschenk) und
-- schreibt das Ergebnis als "Damage"-Attribut auf den Charakter -- das ist der Wert, der
-- Häuser beschädigt UND im Namensschild über dem Spieler angezeigt wird.
local function recalculateStrength(player)
	local character = player.Character
	if not character then
		return
	end

	-- Playable Prologue ("The Fall"): der Prolog-Kaiju hat einen manuell gesetzten,
	-- extrem hohen Damage-Wert (Power Fantasy) -- die normale, auf den (niedrigen)
	-- Starter-Stats basierende Berechnung würde diesen sonst sofort wieder überschreiben,
	-- sobald sie aus irgendeinem Grund erneut läuft.
	if player:GetAttribute("IsInPrologue") == true then
		return
	end

	-- NEUE Mechanik: Nur noch der ARM-Wert bestimmt den Basisschaden. Bein-Wert wirkt
	-- separat als Sprung-Multiplikator (siehe HouseHandler.lua, onHouseTouched) und
	-- fließt hier NICHT mit ein. Körper-Wert ist für ein späteres, eigenes Feature
	-- reserviert -- ebenfalls nicht Teil des Basisschadens.
	-- WICHTIG: Der Arm-Cap ist in TrainingHandler.lua künstlich um Faktor 100 vergrößert
	-- (ARM_CAP_SCALE), damit die angezeigten Zahlen "normal" aussehen (z.B. 50 statt 0.05).
	-- Hier wird das wieder kompensiert, damit der tatsächliche Kampf-Schaden dadurch NICHT
	-- auch 100x größer wird.
	local armPower = player:FindFirstChild("ArmPower")
	local armCapScale = _G.ARM_CAP_SCALE or 1

	local total = (armPower and armPower.Value or 0) / armCapScale

	-- Talent "Apex Predator" (Kaiju-Talentbaum, Ultimate) + "Apex Instinct" (Start-Knoten):
	-- dauerhafter Gesamtschadensbonus.
	local talentUltimateBonus = (_G.GetTalentUltimateDamageBonus and _G.GetTalentUltimateDamageBonus(player)) or 0
	total = total * (1 + talentUltimateBonus)

	-- Temporärer Schaden-Boost (z.B. aus einem Geschenk) -- läuft nach Ablauf automatisch aus
	local boostEndsAt = player:GetAttribute("DamageBoostEndsAt") or 0
	if Workspace:GetServerTimeNow() < boostEndsAt then
		total = total * (player:GetAttribute("DamageBoostMultiplier") or 1)
	end

	character:SetAttribute("Damage", math.floor(total))
end

-- Entfernt Zubehör/Kleidung vom Charakter (Hüte, Haare, Shirts, etc.)
local function stripAccessories(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Clothing") then
			child:Destroy()
		end
	end
end

-- Wendet einen Skin auf den Charakter an: Leben/Speed/Größe + Einfärbung. Der Schaden
-- kommt NICHT vom Skin, sondern aus den trainierten Kraft-Werten (recalculateStrength).

-- ===== GRÖSSERER DIAGNOSE-SCHALTER: auf true setzen, um die KOMPLETTE
-- Charakter-Anpassung zu überspringen -- betrifft SOWOHL applySkinToCharacter
-- (Skalierung/HipHeight/Sprunghöhe/Zustand) ALS AUCH den Fraktions-Modell-Tausch
-- (Jaeger/Ronin) weiter unten. Der Charakter bleibt dann garantiert der 100%
-- unberührte Standard-Roblox-Avatar, als saubere Baseline zum Testen -- unabhängig
-- davon, welche Fraktion der Spieler gerade eingestellt hat. =====
local DISABLE_ALL_CHARACTER_CUSTOMIZATION_FOR_TESTING = false

-- ===== Fraktions-Modell-Wechsel: Jaeger/Ronin nutzen komplett andere, vorgefertigte
-- Modelle (kein Skalieren des eigenen Avatars wie bei den Kaiju-Skin-Stufen) -- der
-- gesamte Charakter wird durch das Fraktions-Modell ERSETZT. Setzt man player.Character
-- neu, feuert Roblox CharacterAdded erneut -- der Marker "FactionModelName" verhindert,
-- dass sich das endlos wiederholt (beim zweiten Durchlauf ist das Modell schon korrekt).
local FACTION_MODEL_NAMES = {
	Jaeger = "JaegerR15",
	Ronin = "RoninR15",
	-- Kaiju bewusst NICHT hier: KaijuR15 ist bereits als StarterPlayer.StarterCharacter
	-- gesetzt -- Roblox spawnt Kaiju-Spieler damit schon automatisch korrekt (inkl.
	-- automatischem Kopieren von StarterCharacterScripts und normaler Kamera-
	-- Verfolgung). Ein ZUSÄTZLICHER Tausch hier würde den bereits korrekt gespawnten
	-- Charakter durch eine eigene, unvollständige Kopie ersetzen (ohne die Extras, die
	-- Roblox beim normalen Spawn automatisch erledigt) -- das war die Ursache für
	-- fehlende Laufanimationen und eine falsch fokussierte Kamera.
}

local function applyFactionModel(player, character)
	if DISABLE_ALL_CHARACTER_CUSTOMIZATION_FOR_TESTING then
		return character -- Diagnose-Modus: kein Modell-Tausch, egal welche Fraktion eingestellt ist
	end

	local faction = player:GetAttribute("Faction") or "Kaiju"
	local currentModelName = character:GetAttribute("FactionModelName")
	local modelName = FACTION_MODEL_NAMES[faction]

	-- Sonderfall Kaiju: normalerweise kein Tausch nötig (StarterCharacter ist schon
	-- KaijuR15) -- ABER falls der Charakter GERADE ein anderes Fraktions-Modell ist
	-- (Jaeger/Ronin, erkennbar am gesetzten FactionModelName-Attribut), muss auch der
	-- Rückwechsel zu Kaiju funktionieren, sonst bleibt man im Debug-Fenster nach einem
	-- Jaeger/Ronin-Test für immer in deren Modell stecken.
	if faction == "Kaiju" and currentModelName then
		modelName = "KaijuR15"
	end

	if not modelName then
		return character -- Kaiju beim frischen Spawn (StarterCharacter) -- kein Tausch nötig
	end

	if currentModelName == modelName then
		return character -- schon das richtige Modell -- kein erneuter Tausch
	end

	local avatarPack = Workspace:FindFirstChild("R15AvatarPack")
	local template = avatarPack and avatarPack:FindFirstChild(modelName)
	if not template then
		warn("[Kaiju] Fraktions-Modell '" .. modelName .. "' nicht gefunden unter Workspace.R15AvatarPack -- Fraktion '" .. faction .. "' bleibt beim Standard-Avatar.")
		return character
	end

	local newCharacter = template:Clone()
	newCharacter.Name = player.Name
	newCharacter:SetAttribute("FactionModelName", modelName)

	-- WICHTIG: Roblox kopiert StarterCharacterScripts (u.a. das Standard-"Animate"-Script
	-- für Lauf-/Sprung-/Idle-Animationen) normalerweise automatisch bei JEDEM Spawn --
	-- das passiert aber NUR über Robloxs eigenen Spawn-Prozess, nicht wenn wir hier
	-- manuell klonen und player.Character direkt setzen. Ohne das nachgeholt wird, hat
	-- das Modell zwar einen Animator, aber niemanden, der ihm sagt, welche Animation
	-- wann abgespielt werden soll -- Ergebnis: Charakter bewegt sich, aber ohne jede
	-- Animation. Hier wird der Inhalt manuell nachkopiert.
	local starterCharacterScripts = StarterPlayer:FindFirstChild("StarterCharacterScripts")
	if starterCharacterScripts then
		for _, child in ipairs(starterCharacterScripts:GetChildren()) do
			if not newCharacter:FindFirstChild(child.Name) then
				child:Clone().Parent = newCharacter
			end
		end
	end

	-- WICHTIG: PrimaryPart explizit auf HumanoidRootPart setzen, BEVOR PivotTo
	-- aufgerufen wird. Ohne sauber gesetzten PrimaryPart nutzt PivotTo stattdessen den
	-- (bei importierten/gebauten Modellen oft falsch sitzenden) WorldPivot -- das kann
	-- den Charakter leicht versetzt spawnen lassen, sodass er teilweise im Terrain steckt.
	-- Roblox' "Freikämpf"-Physik reagiert darauf oft mit genau dem gemeldeten Muster:
	-- durchfallen oder gewaltsam nach oben katapultiert werden (v.a. im Wasser spürbar).
	local newHumanoidRootPart = newCharacter:FindFirstChild("HumanoidRootPart")
	if newHumanoidRootPart then
		newCharacter.PrimaryPart = newHumanoidRootPart
	end

	-- Position/Ausrichtung vom bisherigen Charakter übernehmen, damit der Spieler nicht
	-- an einer anderen Stelle "aufwacht".
	local oldRoot = character:FindFirstChild("HumanoidRootPart")
	local spawnCFrame = oldRoot and oldRoot.CFrame or CFrame.new(0, 10, 0)

	newCharacter.Parent = Workspace
	newCharacter:PivotTo(spawnCFrame)

	character:Destroy()
	player.Character = newCharacter -- feuert CharacterAdded erneut -- alle anderen Systeme (Nametag, HeatHandler, etc.) richten sich dadurch automatisch neu ein

	return newCharacter
end

-- ===== DIAGNOSE-SCHALTER: auf true setzen, um character:ScaleTo() komplett zu
-- überspringen -- der Charakter bleibt dann beim normalen, unskalierten Roblox-Avatar
-- (Scale 1). Dient dazu, herauszufinden, ob das Wasser-Hochschleudern spezifisch mit der
-- Skalierung zusammenhängt (falls es mit einem normalen Avatar NICHT auftritt, ist die
-- Skalierung bestätigt die Ursache -- falls es TROTZDEM auftritt, liegt es woanders,
-- z.B. am Terrain selbst). Danach einfach wieder auf false setzen. =====
local DISABLE_SCALING_FOR_TESTING = false

-- Sprungkraft anhand der TATSÄCHLICHEN (aktuellen) Charaktergrösse berechnen -- rückwärts
-- angewendete Roblox-Sprungphysik-Formel: JumpHeight = JumpPower² / (2*Gravity)
-- => JumpPower = sqrt(2*Gravity*JumpHeight). Eigenständige Funktion (nicht mehr nur
-- lokal in applySkinToCharacter), damit sie auch nach einer Sanctuary-bedingten
-- Nachskalierung (siehe applyZoneAwareScale weiter unten) erneut aufgerufen werden kann.
local function recalculateJumpPower(character, humanoid)
	if not humanoid.Parent then
		return
	end
	local _, characterSize = character:GetBoundingBox()
	local characterHeight = characterSize.Y
	local desiredJumpHeight = characterHeight * 0.5
	local gravity = Workspace.Gravity
	humanoid.UseJumpPower = true
	humanoid.JumpPower = math.sqrt(2 * gravity * desiredJumpHeight)
end

-- Boden-Stabilisierung nach einer Skalierungsänderung: HipHeight neu berechnen (verhindert
-- Schweben/Einsinken) + eine Boden-Kollisionsprüfung per Raycast, die den Charakter bei
-- Bedarf sanft anhebt. Eigenständige Funktion (siehe recalculateJumpPower oben) -- wird
-- sowohl beim normalen Spawn/Skin-Wechsel als auch bei einer Sanctuary-bedingten
-- Nachskalierung aufgerufen.
local function stabilizeCharacterOnGround(character, humanoid)
	if not humanoid.Parent then
		return
	end
	task.wait() -- ein Frame warten, bis Skalierung/SpawnStabilizer sich gesetzt haben

	do
		local root = character:FindFirstChild("HumanoidRootPart")
		local leftFoot = character:FindFirstChild("LeftFoot")
		local rightFoot = character:FindFirstChild("RightFoot")
		if root and leftFoot and rightFoot then
			local soleY = math.min(
				leftFoot.Position.Y - leftFoot.Size.Y / 2,
				rightFoot.Position.Y - rightFoot.Size.Y / 2
			)
			local measured = (root.Position.Y - root.Size.Y / 2) - soleY + math.max(0.05, root.Size.Y * 0.03)
			if measured > 0 then
				humanoid.HipHeight = measured
			end
		elseif root then
			-- WICHTIG: Fallback für Modelle, die keine exakt "LeftFoot"/"RightFoot"
			-- benannten Teile haben (z.B. neue, individuell gebaute Charaktermodelle
			-- mit anderer Teile-Benennung oder einem einzelnen "BodyCollider" statt
			-- einzelner Gliedmassen). Nutzt stattdessen die GESAMTE Bounding Box des
			-- Charakters -- funktioniert unabhängig von der internen Struktur/
			-- Benennung. Ohne diesen Fallback blieb HipHeight bei 0, wodurch der
			-- Charakter beim Stehen auf erhöhten Flächen (z.B. Dächern) mehrere Studs
			-- über der tatsächlichen Oberfläche schwebte -- die eigentliche
			-- Kollisions-Hülle berührte dadurch nie, was u.a. Dach-/Sprungschaden
			-- komplett verhinderte.
			local ok, boundsCFrame, boundsSize = pcall(function()
				return character:GetBoundingBox()
			end)
			if ok then
				local lowestY = boundsCFrame.Position.Y - boundsSize.Y / 2
				local measured = (root.Position.Y - root.Size.Y / 2) - lowestY + math.max(0.05, root.Size.Y * 0.03)
				if measured > 0 then
					humanoid.HipHeight = measured
				end
			end
		end

		-- Boden-Kollisionsprüfung analog zum SpawnStabilizer: nur anheben, falls
		-- tatsächlich eingebettet -- Wasser wird dabei bewusst ignoriert (kein
		-- Konflikt mit der normal funktionierenden Schwimm-Physik).
		if root then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			local castHeight = math.max(8, humanoid.HipHeight + root.Size.Y * 2)
			local result = Workspace:Raycast(
				root.Position + Vector3.new(0, castHeight, 0),
				Vector3.new(0, -(castHeight * 2 + humanoid.HipHeight + root.Size.Y + 4), 0),
				params
			)
			if result and result.Material ~= Enum.Material.Water then
				local desiredRootY = result.Position.Y + humanoid.HipHeight + root.Size.Y / 2
				local correction = desiredRootY - root.Position.Y
				if correction > 0.05 then
					character:PivotTo(character:GetPivot() + Vector3.new(0, correction + 0.05, 0))
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end
	end

	recalculateJumpPower(character, humanoid)
end

local function applySkinToCharacter(player, character, skinId)
	if DISABLE_ALL_CHARACTER_CUSTOMIZATION_FOR_TESTING then
		return -- Charakter bleibt zu 100% unberührter Standard-Roblox-Avatar
	end

	local skin = SkinsConfig.GetSkinById(skinId)
	if not skin then
		return
	end

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.MaxHealth = skin.Health
	humanoid.Health = skin.Health

	-- ENTFERNT: Massless=true + CustomPhysicalProperties mit Dichte nahe Null (frühere
	-- Versuche gegen das Wasser-Hochschleudern). Das hat den Charakter praktisch
	-- gewichtslos gemacht -- ein gewichtsloser Körper reagiert auf JEDE angewandte Kraft
	-- (auch den ganz normalen Sprung-Impuls) massiv übertrieben, was die beobachteten
	-- absurd hohen Sprünge erklärt und wahrscheinlich auch zum Wasser-Problem
	-- beigetragen hat. Das Wasser-Problem wird jetzt stattdessen in WaterWalkFix.lua
	-- über eine aktive Frame-für-Frame-Geschwindigkeitskorrektur gelöst, die Masse/
	-- Dichte gar nicht erst anrührt.

	local evoSpeedLevel = player:FindFirstChild("EvoSpeedLevel")
	local speedMultiplier = 1 + (evoSpeedLevel and evoSpeedLevel.Value or 0) * EVO_BONUS_PER_LEVEL
	local baseWalkSpeed = skin.WalkSpeed * speedMultiplier
	humanoid.WalkSpeed = baseWalkSpeed
	-- Für HeatHandler.lua: Basis-Lauftempo OHNE Heat-Bonus, damit der Heat-Multiplikator
	-- draufmultipliziert werden kann, ohne diese Grundlage (Skin + Evolution) zu verlieren.
	player:SetAttribute("BaseWalkSpeed", baseWalkSpeed)

	-- Größe skalieren: Model:ScaleTo() (bevorzugt wegen korrekter Körperform/Proportionen
	-- gegenüber einzelnen Humanoid-Scale-Properties). WICHTIG: applySkinToCharacter kann
	-- mehrfach pro Spieler aufgerufen werden (Level-Up, Skin-Wechsel, etc.) -- ScaleTo()
	-- deshalb NUR aufrufen, wenn sich die Zielgröße tatsächlich von der aktuellen
	-- unterscheidet, sonst kann sich das über mehrere Aufrufe aufschaukeln/verstärken.
	-- Sprunghöhe: soll IMMER etwa der HALBEN tatsächlichen Charaktergrösse entsprechen,
	-- unabhängig von Skin/Skala. Dafür die reale Höhe per Bounding Box messen (genauer als
	-- eine angenommene Basis-Höhe, da unsere Comic-Skins unterschiedliche Proportionen
	-- haben können) und die ECHTE Roblox-Sprungphysik-Formel rückwärts anwenden:
	-- JumpHeight = JumpPower² / (2 * Gravity)  =>  JumpPower = sqrt(2 * Gravity * JumpHeight)
	-- WICHTIG: Muss NACH vollständig angewendeter Skalierung berechnet werden -- sonst
	-- Sprunghöhe: soll IMMER etwa der HALBEN tatsächlichen Charaktergrösse entsprechen,
	-- unabhängig von Skin/Skala. Dafür die reale Höhe per Bounding Box messen (genauer als
	-- eine angenommene Basis-Höhe, da unterschiedliche Avatare/Skins unterschiedliche
	-- Proportionen haben) und die ECHTE Roblox-Sprungphysik-Formel rückwärts anwenden:
	-- JumpHeight = JumpPower² / (2 * Gravity)  =>  JumpPower = sqrt(2 * Gravity * JumpHeight)
	-- WICHTIG: Läuft im bereits vorhandenen, gewarteten Block weiter unten (NICHT sofort)
	-- -- die Bounding Box muss NACH vollständig angewendeter Skalierung UND nach der Pose-
	-- Stabilisierung gemessen werden, sonst ergibt sie einen falschen (mal zu kleinen, mal
	-- zu großen) Wert.
	local currentScaleOk, currentScale = pcall(function()
		return character:GetScale()
	end)

	-- Sanctuary-Verkleinerung: statt der vollen Basis-Scale (1-6) gilt im Sanctuary
	-- 1 + Scale*0.1 (also nur noch 1.1-1.6) -- macht die friedliche Startzone spürbar
	-- "menschlicher"/ruhiger als die Kampfzonen ausserhalb, wo die volle Grösse gilt.
	local targetScale = skin.Scale
	if player:GetAttribute("CurrentZone") == "Sanctuary" then
		targetScale = 0.5 + skin.Scale * 0.1
	end

	local actualAvatarScale = targetScale
	local scalingWasApplied = false

	if DISABLE_SCALING_FOR_TESTING then
		-- Diagnose-Modus: Skalierung komplett übersprungen, Charakter bleibt beim
		-- normalen Roblox-Avatar (Scale 1).
		actualAvatarScale = currentScaleOk and currentScale or 1
	elseif not currentScaleOk or math.abs((currentScale or 0) - targetScale) > 0.001 then
		local ok = pcall(function()
			character:ScaleTo(targetScale)
		end)
		if ok then
			local scaleOk, newScale = pcall(function()
				return character:GetScale()
			end)
			if scaleOk then
				actualAvatarScale = newScale
			end
			scalingWasApplied = true
		else
			warn("[Kaiju] character:ScaleTo() fehlgeschlagen für " .. player.Name .. " -- Skalierung übersprungen.")
		end
	else
		actualAvatarScale = currentScale
	end

	-- Boden-Stabilisierung + Sprungkraft-Neuberechnung läuft jetzt IMMER (nicht mehr nur
	-- bei scalingWasApplied) über die extrahierte, wiederverwendbare Funktion (siehe oben
	-- vor applySkinToCharacter) -- rein defensiv, schadet nicht falls ein Modell
	-- zusätzlich einen eigenen SpawnStabilizer mitbringt.
	task.defer(function()
		stabilizeCharacterOnGround(character, humanoid)
	end)

	stripAccessories(character)

	-- Keine Einfärbung mehr: der Avatar behält seine eigene (vom Spieler gewählte) Farbe,
	-- statt mit einer festen Skin-Tier-Farbe überschrieben zu werden.

	character:SetAttribute("SkinId", skinId)
	recalculateStrength(player)
end

-- Start-/Reset-Geschenk für Arm/Bein/Körper: 80% des jeweiligen Level-1-Caps -- damit
-- macht ein neuer Spieler von Anfang an spürbar Schaden/kann sammeln, falls er nicht
-- sofort merkt, dass er trainieren soll. Nutzt dieselbe Cap-Formel wie
-- TrainingHandler.lua (inkl. der dortigen Arm-/Bein-spezifischen 100x-Skalierung), mit
-- sicherem Fallback, falls die Werte (Timing zwischen Scripts) noch nicht bereitstehen.
-- WICHTIG: auf Modul-Ebene definiert (nicht innerhalb von loadPlayerData) -- die
-- Funktion muss auch für BESTEHENDE Spieler verfügbar sein (fürs Debug-Reset), nicht nur
-- für brandneue Spieler ohne gespeicherte Daten. War vorher fälschlich innerhalb des
-- "kein gespeicherter Datensatz gefunden"-Zweigs definiert, wodurch _G.ComputeStarterStats
-- bei jedem Spieler mit bereits vorhandenen Daten nie gesetzt wurde -- der Debug-Reset
-- griff dadurch auf den 1/1/1-Fallback zurück, der bei einem entsprechend niedrigen
-- Level-1-Cap fälschlich wie "100%" aussehen konnte.
local function computeStarterStats()
	local getCapForLevel = _G.GetStatCapForLevel
	if not getCapForLevel then
		return { LegPower = 1, ArmPower = 1, BodyPower = 1 }
	end
	local armCapScale = _G.ARM_CAP_SCALE or 1
	local legCapScale = _G.LEG_CAP_SCALE or 1
	local capAtLevel1 = getCapForLevel(1)
	local STARTER_RATIO = 0.8

	local function roundedGift(cap)
		return math.max(math.floor(cap * STARTER_RATIO * 10 + 0.5) / 10, 1)
	end

	return {
		LegPower = roundedGift(capAtLevel1 * legCapScale),
		ArmPower = roundedGift(capAtLevel1 * armCapScale),
		BodyPower = roundedGift(capAtLevel1),
	}
end
_G.ComputeStarterStats = computeStarterStats

local function loadPlayerData(player)
	local success, data = pcall(function()
		return PlayerDataStore:GetAsync("Player_" .. player.UserId)
	end)

	if success and data then
		-- Bestehender Spieler (Speicherdaten vorhanden). Fehlt das Feld (Speicher von
		-- VOR der Prolog-Einführung), gilt der Prolog automatisch als bereits
		-- absolviert -- kein rückwirkendes Erzwingen bei bereits bestehenden Spielern.
		if data.HasCompletedPrologue == nil then
			data.HasCompletedPrologue = true
		end
		return data
	end

	local starterStats = computeStarterStats()

	return {
		Level = 0,
		XP = 0,
		Kills = 0,
		Coins = 0,
		LegPower = starterStats.LegPower,
		ArmPower = starterStats.ArmPower,
		BodyPower = starterStats.BodyPower,
		EquippedSkin = 0,
		UnlockedSkins = { 0 }, -- Skin 0 hat RequiredLevel 0, also von Anfang an freigeschaltet
		EvolutionPoints = 0,
		EvoSpeedLevel = 0,
		EvoMoneyLevel = 0,
		EvoDamageLevel = 0,
		EvoTrainingLevel = 0,
		EvoCooldownLevel = 0,
		EvoLuckLevel = 0,
		-- Die 5 Energie-Typen -- sollen genau wie Coins über Sessions hinweg erhalten
		-- bleiben, statt bei jedem Rejoin auf 0 zurückzufallen.
		EnergyHeat = 0,
		EnergyChemical = 0,
		EnergyElectric = 0,
		EnergyRadiation = 0,
		EnergySpirit = 0,
		-- Lifetime-Zähler (für Jaeger/Ronin-Freischaltung, siehe FactionUnlockService.lua)
		-- -- sinken NIE, auch wenn die normale Energie ausgegeben wird.
		LifetimeEnergyHeat = 0,
		LifetimeEnergyChemical = 0,
		LifetimeEnergyElectric = 0,
		LifetimeEnergyRadiation = 0,
		LifetimeEnergySpirit = 0,
		-- Talentbaum-Fortschritt (Stufen + evtl. laufende Forschung) -- läuft auch
		-- offline weiter, da completesAt ein absoluter Zeitstempel ist (siehe
		-- TalentTreeService.lua, LoadTalentSaveData).
		TalentData = { levels = { Kaiju = {}, Jaeger = {}, Ronin = {} }, research = nil },
		-- Playable Prologue ("The Fall"): false bedeutet, dieser Spieler hat NOCH KEINEN
		-- Speicher (echter Erstspieler) -- der Prolog soll einmalig laufen, siehe
		-- Players.PlayerAdded weiter unten.
		HasCompletedPrologue = false,
	}
end

local function savePlayerData(player, data)
	print("[Kaiju-Debug] savePlayerData für", player.Name, "-- TalentData:", data.TalentData and game:GetService("HttpService"):JSONEncode(data.TalentData) or "nil")
	local ok, err = pcall(function()
		PlayerDataStore:SetAsync("Player_" .. player.UserId, data)
	end)
	if ok then
		print("[Kaiju-Debug] savePlayerData: SetAsync erfolgreich für", player.Name)
	else
		warn("[Kaiju-Debug] savePlayerData: SetAsync FEHLGESCHLAGEN für", player.Name, "-- Fehler:", tostring(err))
	end
end

Players.PlayerAdded:Connect(function(player)
	local data = loadPlayerData(player)
	player:SetAttribute("HasCompletedPrologue", data.HasCompletedPrologue)

	-- Playable Prologue ("The Fall"): bei einem echten Erstspieler soll NICHT der normale
	-- automatische Charakter-Spawn passieren -- stattdessen übernimmt die (separate)
	-- Prolog-Orchestrierung das manuelle Spawnen (erst in die Prolog-Zone, am Ende ins
	-- echte Sanctuary). AutoLoadCharacter MUSS früh (vor jedem Yield) deaktiviert werden,
	-- sonst hat Roblox den Charakter evtl. schon automatisch gespawnt.
	if not data.HasCompletedPrologue then
		player.AutoLoadCharacter = false
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = data.Level
	level.Parent = leaderstats

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Value = data.Kills
	kills.Parent = leaderstats

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = data.Coins
	coins.Parent = leaderstats

	local xpValue = Instance.new("IntValue")
	xpValue.Name = "XP"
	xpValue.Value = data.XP
	xpValue.Parent = player

	local xpNeededValue = Instance.new("IntValue")
	xpNeededValue.Name = "XPNeeded"
	xpNeededValue.Value = xpNeededForLevel(data.Level)
	xpNeededValue.Parent = player

	-- Die 3 Kraft-Werte, die zusammen die Gesamtstärke bilden
	local legPower = Instance.new("NumberValue")
	legPower.Name = "LegPower"
	legPower.Value = data.LegPower
	legPower.Parent = player

	local armPower = Instance.new("NumberValue")
	armPower.Name = "ArmPower"
	armPower.Value = data.ArmPower
	armPower.Parent = player

	local bodyPower = Instance.new("NumberValue")
	bodyPower.Name = "BodyPower"
	bodyPower.Value = data.BodyPower
	bodyPower.Parent = player

	local unlockedFolder = Instance.new("Folder")
	unlockedFolder.Name = "UnlockedSkins"
	unlockedFolder.Parent = player
	for _, skinId in ipairs(data.UnlockedSkins) do
		local marker = Instance.new("IntValue")
		marker.Name = "Skin_" .. skinId
		marker.Value = skinId
		marker.Parent = unlockedFolder
	end

	local equippedSkin = Instance.new("IntValue")
	equippedSkin.Name = "EquippedSkin"
	equippedSkin.Value = data.EquippedSkin
	equippedSkin.Parent = player

	-- Evolution: Punkte + die 6 Skill-Level
	local evolutionPoints = Instance.new("IntValue")
	evolutionPoints.Name = "EvolutionPoints"
	evolutionPoints.Value = data.EvolutionPoints
	evolutionPoints.Parent = player

	local evoKeys = { "EvoSpeedLevel", "EvoMoneyLevel", "EvoDamageLevel", "EvoTrainingLevel", "EvoCooldownLevel", "EvoLuckLevel" }
	for _, key in ipairs(evoKeys) do
		local evoValue = Instance.new("IntValue")
		evoValue.Name = key
		evoValue.Value = data[key] or 0
		evoValue.Parent = player
	end

	-- Session-Start für das Geschenk-System (Spielzeit-Tracking) -- siehe GiftHandler.lua
	player:SetAttribute("SessionStartTime", Workspace:GetServerTimeNow())

	-- Die 5 Energie-Typen (+ Lifetime-Zähler) genau wie Coins aus den gespeicherten Daten
	-- wiederherstellen, statt bei jedem Rejoin auf 0 zurückzufallen.
	for _, energyKey in ipairs({
		"EnergyHeat", "EnergyChemical", "EnergyElectric", "EnergyRadiation", "EnergySpirit",
		"LifetimeEnergyHeat", "LifetimeEnergyChemical", "LifetimeEnergyElectric", "LifetimeEnergyRadiation", "LifetimeEnergySpirit",
		}) do
		player:SetAttribute(energyKey, data[energyKey] or 0)
	end

	-- Talentbaum-Fortschritt wiederherstellen (Stufen + evtl. laufende Forschung, die
	-- auch während der Abwesenheit weitergezählt hat). TalentTreeService.lua läuft als
	-- separates Script -- defensiv prüfen, falls es beim Server-Start noch nicht ganz
	-- fertig initialisiert ist.
	print("[Kaiju-Debug] loadPlayerData für", player.Name, "-- data.TalentData aus DataStore:", data.TalentData and game:GetService("HttpService"):JSONEncode(data.TalentData) or "nil", "-- _G.LoadTalentSaveData vorhanden:", _G.LoadTalentSaveData ~= nil)
	if _G.LoadTalentSaveData then
		_G.LoadTalentSaveData(player, data.TalentData)
	else
		task.defer(function()
			if _G.LoadTalentSaveData then
				print("[Kaiju-Debug] loadPlayerData: LoadTalentSaveData verzögert (task.defer) für", player.Name)
				_G.LoadTalentSaveData(player, data.TalentData)
			end
		end)
	end

	-- Achievements wiederherstellen (freigeschaltete IDs + Zähler-Fortschritt) --
	-- gleiches defensives Muster wie beim Talentbaum.
	if _G.LoadAchievementSaveData then
		_G.LoadAchievementSaveData(player, data.Achievements)
	else
		task.defer(function()
			if _G.LoadAchievementSaveData then
				_G.LoadAchievementSaveData(player, data.Achievements)
			end
		end)
	end

	player.CharacterAdded:Connect(function(character)
		local finalCharacter = applyFactionModel(player, character)
		if finalCharacter == character then
			-- Kein Modell-Tausch passiert (Kaiju, oder Charakter ist schon das richtige
			-- Fraktions-Modell) -- direkt weiter mit Skalierung/Health/Speed.
			applySkinToCharacter(player, finalCharacter, equippedSkin.Value)
		end
		-- Falls getauscht wurde: player.Character neu setzen löst CharacterAdded erneut
		-- aus -- applySkinToCharacter läuft dann in DIESEM zweiten Durchlauf auf dem
		-- neuen Modell (finalCharacter == character wäre dann true, s.o.).
	end)

	-- Absicherung: falls der Charakter beim Beitreten schon existiert, direkt anwenden.
	if player.Character then
		local finalCharacter = applyFactionModel(player, player.Character)
		if finalCharacter == player.Character then
			applySkinToCharacter(player, finalCharacter, equippedSkin.Value)
		end
	end

	-- Reagiert auf einen Fraktions-Wechsel WÄHREND des Spiels (kein Respawn nötig) --
	-- tauscht das Charakter-Modell sofort passend zur neuen Fraktion.
	player:GetAttributeChangedSignal("Faction"):Connect(function()
		if player.Character then
			local finalCharacter = applyFactionModel(player, player.Character)
			if finalCharacter == player.Character then
				applySkinToCharacter(player, finalCharacter, equippedSkin.Value)
			end
		end
	end)

	-- Playable Prologue ("The Fall"): AutoLoadCharacter wurde weiter oben für echte
	-- Erstspieler bereits deaktiviert -- hier jetzt tatsächlich auslösen. _G.StartPrologue
	-- wird vom künftigen Prolog-Orchestrierungs-Script bereitgestellt; bis es existiert,
	-- fällt dies defensiv auf einen normalen Spawn zurück (Spiel bleibt so lange
	-- durchgehend spielbar, auch während der Prolog noch gebaut wird).
	if not data.HasCompletedPrologue then
		task.spawn(function()
			if _G.StartPrologue then
				_G.StartPrologue(player)
			else
				warn("[PlayerSetup] _G.StartPrologue nicht gefunden -- Prolog wird übersprungen (noch nicht gebaut), Spieler spawnt normal.")
				player:LoadCharacter()
			end
		end)
	end
end)

-- In eine eigene, wiederverwendbare Funktion ausgelagert (statt nur inline im
-- PlayerRemoving-Handler) -- wird jetzt AUCH von game:BindToClose() genutzt (siehe
-- unten). Grund: in Studio Play-Mode beendet der "Stop"-Button die Session oft abrupt,
-- BEVOR der asynchrone DataStore-Speichervorgang (SetAsync, ein Netzwerk-Call) im
-- PlayerRemoving-Handler überhaupt fertig wird -- ohne game:BindToClose() gehen
-- Talente/Achievements/Fortschritt dadurch beim Beenden der Session verloren, obwohl der
-- Code an sich korrekt ist.
local function buildPlayerSaveData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	local unlockedIds = {}
	if unlockedFolder then
		for _, marker in ipairs(unlockedFolder:GetChildren()) do
			table.insert(unlockedIds, marker.Value)
		end
	end

	local function getVal(name, default)
		local obj = player:FindFirstChild(name)
		return obj and obj.Value or default
	end

	return {
		Level = leaderstats and leaderstats.Level.Value or 0,
		XP = getVal("XP", 0),
		Kills = leaderstats and leaderstats.Kills.Value or 0,
		Coins = leaderstats and leaderstats.Coins.Value or 0,
		LegPower = getVal("LegPower", 0),
		ArmPower = getVal("ArmPower", 0),
		BodyPower = getVal("BodyPower", 0),
		EquippedSkin = getVal("EquippedSkin", 0),
		UnlockedSkins = unlockedIds,
		HasCompletedPrologue = player:GetAttribute("HasCompletedPrologue") ~= false, -- true als sicherer Default (nil zählt als "ja")
		EvolutionPoints = getVal("EvolutionPoints", 0),
		EvoSpeedLevel = getVal("EvoSpeedLevel", 0),
		EvoMoneyLevel = getVal("EvoMoneyLevel", 0),
		EvoDamageLevel = getVal("EvoDamageLevel", 0),
		EvoTrainingLevel = getVal("EvoTrainingLevel", 0),
		EvoCooldownLevel = getVal("EvoCooldownLevel", 0),
		EvoLuckLevel = getVal("EvoLuckLevel", 0),
		-- Die 5 Energie-Typen (+ Lifetime-Zähler) genau wie Coins speichern -- Attribute,
		-- daher player:GetAttribute() statt getVal() (das sucht nur nach Kind-Objekten).
		EnergyHeat = player:GetAttribute("EnergyHeat") or 0,
		EnergyChemical = player:GetAttribute("EnergyChemical") or 0,
		EnergyElectric = player:GetAttribute("EnergyElectric") or 0,
		EnergyRadiation = player:GetAttribute("EnergyRadiation") or 0,
		EnergySpirit = player:GetAttribute("EnergySpirit") or 0,
		LifetimeEnergyHeat = player:GetAttribute("LifetimeEnergyHeat") or 0,
		LifetimeEnergyChemical = player:GetAttribute("LifetimeEnergyChemical") or 0,
		LifetimeEnergyElectric = player:GetAttribute("LifetimeEnergyElectric") or 0,
		LifetimeEnergyRadiation = player:GetAttribute("LifetimeEnergyRadiation") or 0,
		LifetimeEnergySpirit = player:GetAttribute("LifetimeEnergySpirit") or 0,
		-- Talentbaum-Fortschritt (Stufen + evtl. laufende Forschung) -- läuft auch
		-- offline weiter (completesAt ist ein absoluter Zeitstempel).
		TalentData = _G.GetTalentSaveData and _G.GetTalentSaveData(player) or nil,
		-- Achievements: freigeschaltete IDs + Zähler-Fortschritt.
		Achievements = _G.GetAchievementSaveData and _G.GetAchievementSaveData(player) or nil,
	}
end

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player, buildPlayerSaveData(player))
end)

-- WICHTIG: ohne dies geht Fortschritt (v.a. Talente/Achievements) beim Beenden des
-- Servers verloren, wenn PlayerRemoving nicht rechtzeitig durchläuft (siehe Kommentar
-- oben bei buildPlayerSaveData). game:BindToClose() gibt dem Server explizit Zeit, alle
-- noch verbundenen Spieler synchron zu speichern, BEVOR der Prozess komplett beendet
-- wird -- funktioniert sowohl live als auch beim Beenden einer Studio-Play-Session
-- (Team-Test/Server-Modus; bei reinem "Play Solo" ist das Verhalten je nach
-- Studio-Version leider nicht immer garantiert, das liegt ausserhalb unserer Kontrolle).
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, err = pcall(function()
			savePlayerData(player, buildPlayerSaveData(player))
		end)
		if not ok then
			warn("[PlayerSetup] BindToClose: Speichern für " .. player.Name .. " fehlgeschlagen: " .. tostring(err))
		end
	end
end)

-- ===== Periodisches Auto-Save ========================================================
-- Zusätzliches Sicherheitsnetz UNABHÄNGIG vom sauberen Beenden (PlayerRemoving/
-- BindToClose) -- deckt gerade Play-Solo-Tests in Studio ab, wo BindToClose nicht immer
-- zuverlässig durchläuft. Speichert jeden verbundenen Spieler im Hintergrund, selbst
-- wenn die Session danach abrupt beendet wird, geht so höchstens der Fortschritt der
-- letzten AUTO_SAVE_INTERVAL_SECONDS verloren, nicht die ganze Session.
local AUTO_SAVE_INTERVAL_SECONDS = 120

task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(function()
				savePlayerData(player, buildPlayerSaveData(player))
			end)
			if not ok then
				warn("[PlayerSetup] Auto-Save: Speichern für " .. player.Name .. " fehlgeschlagen: " .. tostring(err))
			end
		end
	end
end)

EquipSkinEvent.OnServerEvent:Connect(function(player, skinId)
	local skin = SkinsConfig.GetSkinById(skinId)
	if not skin then
		return
	end

	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	if not unlockedFolder or not unlockedFolder:FindFirstChild("Skin_" .. skinId) then
		return -- Skin noch nicht freigeschaltet -> ignorieren
	end

	local equippedSkin = player:FindFirstChild("EquippedSkin")
	if equippedSkin then
		equippedSkin.Value = skinId
	end

	if player.Character then
		applySkinToCharacter(player, player.Character, skinId)
	end
end)

-- Vergibt XP und verwaltet den Level-Aufstieg, bis zur aktuellen Level-Obergrenze
-- (siehe getLevelCap). Überschüssige XP bleiben gespeichert und werden automatisch
-- eingelöst, sobald die Grenze durch einen neuen Skin-Kauf angehoben wird.
-- Wird global über _G bereitgestellt, damit andere Skripte sie aufrufen können.
local function awardXP(player, amount)
	-- Prolog-Isolation: der Prolog-Kaiju ist ein temporärer, vom echten Fortschritt
	-- komplett getrennter Zustand -- keine echte XP/Level-Progression während des Prologs.
	if player:GetAttribute("IsInPrologue") == true then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local xpValue = player:FindFirstChild("XP")
	local xpNeededValue = player:FindFirstChild("XPNeeded")
	if not leaderstats or not xpValue or not xpNeededValue then
		return
	end

	xpValue.Value += amount

	local levelCap = getLevelCap(player)
	while xpValue.Value >= xpNeededValue.Value and leaderstats.Level.Value < levelCap do
		xpValue.Value -= xpNeededValue.Value
		leaderstats.Level.Value += 1
		xpNeededValue.Value = xpNeededForLevel(leaderstats.Level.Value)
	end
end

-- Kauft einen Skin mit Coins (+ Level-Anforderung). Bereits freigeschaltete Skins werden
-- stattdessen einfach nur ausgerüstet (kein erneuter Abzug). Nach dem Kauf wird sofort
-- geprüft, ob gespeicherte XP jetzt für weitere Level reichen (neue Obergrenze).
-- Debug-Werkzeug (siehe TrainingHandler.lua, Level-Schieberegler): schaltet den höchsten
-- Skin frei, der zum aktuellen Level passt, OHNE Coins-Kosten, und rüstet ihn direkt aus.
-- Ohne das würde der Debug-Regler zwar Level/Skills setzen, aber WalkSpeed/Aussehen
-- blieben auf dem alten Skin hängen, da Skins normalerweise gekauft werden müssen.
_G.DebugApplyHighestSkinForLevel = function(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	local equippedSkin = player:FindFirstChild("EquippedSkin")
	if not leaderstats or not unlockedFolder or not equippedSkin then
		return
	end

	local currentLevel = leaderstats.Level.Value
	local bestSkin = nil
	for _, skin in ipairs(SkinsConfig.Skins) do
		if skin.RequiredLevel <= currentLevel and (not bestSkin or skin.RequiredLevel > bestSkin.RequiredLevel) then
			bestSkin = skin
		end
	end
	if not bestSkin then
		return
	end

	if not unlockedFolder:FindFirstChild("Skin_" .. bestSkin.Id) then
		local marker = Instance.new("IntValue")
		marker.Name = "Skin_" .. bestSkin.Id
		marker.Value = bestSkin.Id
		marker.Parent = unlockedFolder
	end

	equippedSkin.Value = bestSkin.Id
	if player.Character then
		applySkinToCharacter(player, player.Character, bestSkin.Id)
	end
end

PurchaseSkinEvent.OnServerEvent:Connect(function(player, skinId)
	local skin = SkinsConfig.GetSkinById(skinId)
	if not skin then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	local equippedSkin = player:FindFirstChild("EquippedSkin")
	if not leaderstats or not unlockedFolder or not equippedSkin then
		return
	end

	local alreadyUnlocked = unlockedFolder:FindFirstChild("Skin_" .. skinId) ~= nil

	if not alreadyUnlocked then
		if leaderstats.Level.Value < skin.RequiredLevel then
			return -- Level zu niedrig -> ignorieren
		end
		if leaderstats.Coins.Value < skin.Cost then
			return -- nicht genug Coins -> ignorieren
		end

		leaderstats.Coins.Value -= skin.Cost

		local marker = Instance.new("IntValue")
		marker.Name = "Skin_" .. skinId
		marker.Value = skinId
		marker.Parent = unlockedFolder

		awardXP(player, 0) -- gespeicherte XP gegen die neue (höhere) Level-Obergrenze prüfen
	end

	-- Direkt nach dem Kauf (bzw. bei erneutem Klick auf einen bereits gekauften Skin) ausrüsten
	equippedSkin.Value = skinId
	if player.Character then
		applySkinToCharacter(player, player.Character, skinId)
	end
end)

-- ===== Debug: Alle Werte auf den Ausgangszustand zurücksetzen =====
local ResetPlayerDataEvent = Instance.new("RemoteEvent")
ResetPlayerDataEvent.Name = "ResetPlayerDataEvent"
ResetPlayerDataEvent.Parent = ReplicatedStorage

ResetPlayerDataEvent.OnServerEvent:Connect(function(player)
	print("[Kaiju-Debug] ResetPlayerDataEvent empfangen von:", player.Name, "um", os.clock())
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	leaderstats.Level.Value = 0
	leaderstats.Kills.Value = 0
	leaderstats.Coins.Value = 0

	local xpValue = player:FindFirstChild("XP")
	local xpNeededValue = player:FindFirstChild("XPNeeded")
	if xpValue then
		xpValue.Value = 0
	end
	if xpNeededValue then
		xpNeededValue.Value = xpNeededForLevel(0)
	end
	print("[Kaiju-Debug] Reset: Level=", leaderstats.Level.Value, "XP=", xpValue and xpValue.Value, "XPNeeded=", xpNeededValue and xpNeededValue.Value)

	local resetStatValues = (_G.ComputeStarterStats and _G.ComputeStarterStats()) or { LegPower = 1, ArmPower = 1, BodyPower = 1 }
	print("[Kaiju-Debug] Reset: berechnete Werte -- Arm:", resetStatValues.ArmPower, "Leg:", resetStatValues.LegPower, "Body:", resetStatValues.BodyPower)
	for key, value in pairs(resetStatValues) do
		local statValue = player:FindFirstChild(key)
		print("[Kaiju-Debug] Reset:", key, "-- vorher:", statValue and statValue.Value, "-> nachher:", value)
		if statValue then
			statValue.Value = value
		end
	end

	-- Alle Skins außer dem kostenlosen Skin_0 wieder sperren
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	if unlockedFolder then
		for _, marker in ipairs(unlockedFolder:GetChildren()) do
			if marker.Name ~= "Skin_0" then
				marker:Destroy()
			end
		end
	end

	local equippedSkin = player:FindFirstChild("EquippedSkin")
	if equippedSkin then
		equippedSkin.Value = 0
	end

	-- Evolution: Punkte + alle 6 Skills zurücksetzen
	local evolutionPoints = player:FindFirstChild("EvolutionPoints")
	if evolutionPoints then
		evolutionPoints.Value = 0
	end
	for _, key in ipairs({ "EvoSpeedLevel", "EvoMoneyLevel", "EvoDamageLevel", "EvoTrainingLevel", "EvoCooldownLevel", "EvoLuckLevel" }) do
		local evoValue = player:FindFirstChild(key)
		if evoValue then
			evoValue.Value = 0
		end
	end

	-- Geschenke: alle wieder als nicht abgeholt markieren, Session-Timer neu starten
	local claimedFolder = player:FindFirstChild("ClaimedGifts")
	if claimedFolder then
		for _, marker in ipairs(claimedFolder:GetChildren()) do
			marker.Value = false
		end
	end
	player:SetAttribute("SessionStartTime", Workspace:GetServerTimeNow())

	-- Alle temporären Boosts löschen
	player:SetAttribute("CoinsBoostEndsAt", 0)
	player:SetAttribute("DamageBoostEndsAt", 0)
	player:SetAttribute("BoostEndsAt", 0)
	player:SetAttribute("BoostCharge", 0)

	-- Die 5 Energie-Typen + Lifetime-Zähler zurücksetzen -- fehlten hier bisher komplett,
	-- obwohl sie inzwischen (wie Coins) über Sessions hinweg gespeichert werden.
	for _, energyKey in ipairs({
		"EnergyHeat", "EnergyChemical", "EnergyElectric", "EnergyRadiation", "EnergySpirit",
		"LifetimeEnergyHeat", "LifetimeEnergyChemical", "LifetimeEnergyElectric", "LifetimeEnergyRadiation", "LifetimeEnergySpirit",
		}) do
		player:SetAttribute(energyKey, 0)
	end

	-- Fraktions-Freischalt-Fortschritt (Feuerwehrautos zerstört, Sprung-Kills) zurücksetzen.
	player:SetAttribute("FireEnginesDestroyed", 0)
	player:SetAttribute("JumpKills", 0)

	-- Fraktion zurück auf Kaiju -- setzt auch das Charakter-Modell zurück, falls der
	-- Spieler gerade Jaeger/Ronin war (sonst bliebe das fremde Modell nach dem Reset
	-- bestehen, was wie ein "kaputtes" Skalierungs-/Grössenproblem aussehen kann).
	-- WICHTIG: Falls sich die Fraktion hier tatsächlich ändert, löst das automatisch den
	-- bereits bestehenden Fraktions-Wechsel-Listener aus (siehe applyFactionModel weiter
	-- oben), der den Charakter tauscht UND applySkinToCharacter auf dem NEUEN Charakter
	-- erneut aufruft -- der manuelle Aufruf unten würde in diesem Fall auf ein bereits
	-- veraltetes Charakter-Objekt zeigen und wird deshalb nur ausgeführt, wenn KEIN
	-- Wechsel nötig war (Spieler war schon Kaiju).
	local wasAlreadyKaiju = player:GetAttribute("Faction") == "Kaiju"
	player:SetAttribute("SelectedFaction", "Kaiju")
	player:SetAttribute("Faction", "Kaiju")

	-- Talentbaum-Fortschritt (Forschungs-Stufen + evtl. laufende Forschung) zurücksetzen.
	if _G.ResetPlayerTalents then
		_G.ResetPlayerTalents(player)
	end

	-- Achievements (freigeschaltete + Zähler-Fortschritt) zurücksetzen.
	if _G.ResetPlayerAchievements then
		_G.ResetPlayerAchievements(player)
	end

	-- Skin neu anwenden (setzt auch Leben/Speed/Größe/Farbe zurück auf Skin_0) -- nur
	-- hier nötig, wenn oben KEIN Fraktions-Modell-Tausch ausgelöst wurde.
	if wasAlreadyKaiju and player.Character then
		applySkinToCharacter(player, player.Character, 0)
	end

	-- WICHTIG: recalculateStrength() wird sonst NUR einmal beim Charakter-Start
	-- aufgerufen -- ohne diesen expliziten Aufruf hier bliebe die "Stärke" (Damage-
	-- Attribut) nach dem Reset auf dem alten, hohen Wert stehen, obwohl ArmPower
	-- bereits zurückgesetzt wurde.
	recalculateStrength(player)

	local finalArmPower = player:FindFirstChild("ArmPower")
	print("[Kaiju-Debug] Reset ENDE: ArmPower jetzt:", finalArmPower and finalArmPower.Value, "-- Damage-Attribut:", player.Character and player.Character:GetAttribute("Damage"))

	print("[Kaiju] Alle Werte von " .. player.Name .. " wurden zurückgesetzt.")
end)

_G.AwardXP = awardXP
_G.RecalculateStrength = recalculateStrength
_G.GetLevelCap = getLevelCap
_G.STAT_CAP_PER_LEVEL = STAT_CAP_PER_LEVEL
_G.EVO_BONUS_PER_LEVEL = EVO_BONUS_PER_LEVEL
_G.EVO_MAX_LEVEL = EVO_MAX_LEVEL
_G.ApplySkinToCharacter = applySkinToCharacter

-- Playable Prologue ("The Fall"): vom künftigen Prolog-Orchestrierungs-Script aufzurufen,
-- sobald die komplette Sequenz (Cold Open bis Awakening) fertig durchlaufen wurde.
-- Markiert den Prolog als abgeschlossen, speichert SOFORT (nicht erst beim nächsten
-- periodischen Auto-Save -- ein Server-Absturz kurz danach soll dieses einmalige Flag
-- nicht verlieren können) und spawnt den Spieler danach normal (ins echte Sanctuary).
_G.MarkPrologueComplete = function(player)
	player:SetAttribute("HasCompletedPrologue", true)
	savePlayerData(player, buildPlayerSaveData(player))
	player:LoadCharacter()
end

-- ===== Sanctuary-Verkleinerung: Skalierung in Echtzeit neu anwenden, sobald sich die
-- Zone ändert (siehe ZoneManager.lua, "CurrentZone"-Attribut) -- nicht nur beim Spawn.
-- WICHTIG: nutzt bewusst NICHT die volle applySkinToCharacter() -- die setzt auch Health
-- auf das Maximum zurück, was bei jedem Sanctuary-Grenzübertritt zu einer ungewollten
-- Vollheilung führen würde. Stattdessen nur Skalierung + Boden-Stabilisierung (über die
-- weiter oben extrahierten, gemeinsam genutzten Funktionen).
local function applyZoneAwareScale(player, character)
	local equippedSkin = player:FindFirstChild("EquippedSkin")
	local skinId = equippedSkin and equippedSkin.Value or 0
	local skin = SkinsConfig.GetSkinById(skinId)
	if not skin then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if DISABLE_SCALING_FOR_TESTING or DISABLE_ALL_CHARACTER_CUSTOMIZATION_FOR_TESTING then
		return
	end

	local targetScale = skin.Scale
	if player:GetAttribute("CurrentZone") == "Sanctuary" then
		targetScale = 0.5 + skin.Scale * 0.1
	end

	local currentScaleOk, currentScale = pcall(function()
		return character:GetScale()
	end)
	if currentScaleOk and math.abs((currentScale or 0) - targetScale) <= 0.001 then
		return -- schon korrekt skaliert, nichts zu tun
	end

	local ok = pcall(function()
		character:ScaleTo(targetScale)
	end)
	if not ok then
		warn("[Kaiju] character:ScaleTo() fehlgeschlagen für " .. player.Name .. " (Zonenwechsel) -- Skalierung übersprungen.")
		return
	end

	task.defer(function()
		stabilizeCharacterOnGround(character, humanoid)
	end)
end

local function onZoneChanged(player)
	local character = player.Character
	if character then
		applyZoneAwareScale(player, character)
	end
end

Players.PlayerAdded:Connect(function(player)
	player:GetAttributeChangedSignal("CurrentZone"):Connect(function()
		onZoneChanged(player)
	end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player:GetAttributeChangedSignal("CurrentZone"):Connect(function()
		onZoneChanged(player)
	end)
end