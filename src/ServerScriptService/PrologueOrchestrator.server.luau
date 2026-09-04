-- VERSION: 2026-08-26 #83 -- TEMP DEBUG bleibt drin
-- FEATURE: Militaer-Einheiten, Feuerwehr-Fahrzeuge und Barrikaden werden beim Stadt-Reset jetzt ebenfalls despawnt
-- Ort in Studio: ServerScriptService
--
-- Steuert den Playable Prologue ("The Fall") -- siehe Design-Dokument. Aktuell umgesetzt:
--   Phase 1: Cold Open (Schwarzblende, Ticken, "THE CITY WILL SOON BE BROKEN.")
--   Phase 2: Prolog-Kaiju-Setup (Power-Fantasy-Stats) + Onboarding-Hinweise
--   Phase 3: Eskalation (zeitbasiert, siehe ESCALATION_SCHEDULE)
--   Phase 4: Guardian-Auftritt (Alert 5)
--   Phase 5: The Fall (geskripteter, timer-basierter Niederlage-Ablauf)
--   Phase 6: "The Trench Remembers" (Titelkarten-Sequenz)
--   Phase 7: Awakening (Übergang zu Level 0, echtes Sanctuary)
--
-- WICHTIG -- diese Objekte müssen in Studio vorbereitet sein, bevor der Prolog getestet
-- werden kann:
--   Workspace.PrologueSpawn        -- Part, an dem der Prolog-Kaiju spawnt
--   Eine Stadt mit CityName="PrologueCity" (siehe CityAlertConfig.lua) -- Gebäude darunter
--   mit dem "KaijuHouse"-Tag, ein Guardian-Modell analog zu den anderen Städten (optional,
--   sonst nutzt CityDefenderService automatisch den einfachen Platzhalter).
--
-- WICHTIG -- bekannte Einschränkung: _G.CityAlertLevelChanged ist PRO STADT, nicht pro
-- Spieler. Bei mehreren GLEICHZEITIGEN Prolog-Spielern würden sie sich aktuell dieselbe
-- PrologueCity-Instanz teilen. Für Tests/niedrige Gleichzeitigkeit ausreichend -- für
-- produktiven Mehrspieler-Betrieb müsste das auf pro-Spieler-Instanzen erweitert werden.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local SkinsConfig = require(ReplicatedStorage:WaitForChild("SkinsConfig"))
local StoryBeatService = require(ServerScriptService:WaitForChild("StoryBeatService"))
local PrologueReinforcementService = require(ServerScriptService:WaitForChild("PrologueReinforcementService"))

local SimplePrologueFallCameraEvent = RemoteEventUtils.GetOrCreate("SimplePrologueFallCameraEvent")
local SetPrologueLetterboxEvent = RemoteEventUtils.GetOrCreate("SetPrologueLetterboxEvent")
local ShowTutorialChecklistEvent = RemoteEventUtils.GetOrCreate("ShowTutorialChecklistEvent")
local UpdateTutorialChecklistEvent = RemoteEventUtils.GetOrCreate("UpdateTutorialChecklistEvent")
local HideTutorialChecklistEvent = RemoteEventUtils.GetOrCreate("HideTutorialChecklistEvent")
-- Referenzen auf die BESTEHENDEN Aktions-Events (AttackClient.lua/CombatHandler.lua bzw.
-- EnergyAbsorbInputClient.lua/EnergyCollectionHandler.lua) -- RemoteEvents erlauben
-- mehrere Zuhörer gleichzeitig, das Mithören hier stört die bestehende Kampf-/
-- Energiesog-Logik also nicht.
local TutorialAttackEvent = RemoteEventUtils.GetOrCreate("AttackEvent")
local ForceCloseShopEvent = RemoteEventUtils.GetOrCreate("ForceCloseShopEvent")
local TrenchOrbitCameraEvent = RemoteEventUtils.GetOrCreate("TrenchOrbitCameraEvent")
local RestorePrologueCameraEvent = RemoteEventUtils.GetOrCreate("RestorePrologueCameraEvent")
local PlayIntroCinematicEvent = RemoteEventUtils.GetOrCreate("PlayIntroCinematicEvent")
local CinematicCompleteEvent = RemoteEventUtils.GetOrCreate("CinematicCompleteEvent")

local PrologueOrchestrator = {}

-- ===== Vorwaertsdeklaration der Warteschlangen-Zustaende =====
-- Diese vier Namen werden in triggerTheFall (rund 400 Zeilen weiter unten) benutzt,
-- ihre eigentliche Definition steht aber erst ab Zeile 1300. In Lua loest ein Name, dessen
-- `local` noch nicht deklariert ist, still auf ein GLOBAL auf -- der Wert ist nil.
--
-- Die Folge war ein echter Fehler und kein Schoenheitsproblem:
--   * `prologueOccupiedBy = nil` am Ende eines Durchlaufs schrieb eine GLOBALE Variable,
--     waehrend die lokale weiter auf dem Spieler stand. Der Platz wurde nie frei.
--   * `resetPrologueCity()` und `tryStartNextInQueue()` riefen nil auf.
--   * `startPrologueInternal()` in tryStartNextInQueue ebenso.
-- Im Einzelspielerbetrieb faellt davon nichts auf. Sobald zwei Leute gleichzeitig spielen,
-- haengt der zweite dauerhaft in der Warteschlange fest.
--
-- Gefunden hat das tools/source-check.py (Regel source.forward-reference).
local prologueOccupiedBy = nil -- Player, der gerade PrologueCity durchlaeuft (oder nil)
local resetPrologueCity
local tryStartNextInQueue
local startPrologueInternal

local PROLOGUE_CITY_NAME = "PrologueCity"

-- ===== Power-Fantasy-Stats (Phase 2) =====
-- Der Prolog-Kaiju nutzt den ECHTEN grössten Skin (Radiant Apex, Level 50) statt eigener,
-- willkürlicher Werte -- vermittelt so die tatsächliche Endgame-Power, die man sich im
-- normalen Spiel erarbeiten würde, statt einer künstlich überhöhten Fantasie-Zahl.
local PROLOGUE_SKIN_ID = 2 -- Adult Kaiju (ab Level 20 freigeschaltet, passt zu PROLOGUE_LEVEL=25) -- siehe SkinsConfig.lua
local PROLOGUE_LEVEL = 25
local PROLOGUE_DAMAGE = 2000 -- fester Schaden-Wert (statt Multiplikator auf Adult-Kaiju-Basis-Schaden)

-- Das Ticken des Sanctuary-Uhrwerks -- zieht sich als wiederkehrendes Motiv durch den
-- gesamten Prolog (Cold Open, Guardian-Auftritt, The Fall, "The Trench Remembers").
local TICK_SOUND_ID = "rbxassetid://128707491647978"
local SIREN_SOUND_ID = "rbxassetid://18980441222"
local POWER_FANTASY_MUSIC_ID = "rbxassetid://122412242639201" -- gleicher Song wie beim Spirit-Weltevent


-- Baut "count" einzelne Tick-Schritte (mit kurzer Pause dazwischen) für eine StoryBeat-
-- Sequenz -- entspricht dem "Tick. Tick. Tick."-Motiv aus dem Konzept-Dokument.
local function buildTickSteps(count, pauseBetween)
	local steps = {}
	for i = 1, count do
		table.insert(steps, { type = "sound", soundId = TICK_SOUND_ID, volume = 0.7, wait = true })
		if i < count then
			table.insert(steps, { type = "wait", duration = pauseBetween or 0.6 })
		end
	end
	return steps
end

-- ===== Phase 4/5: Guardian + The Fall (Timing) =====
local GUARDIAN_PHASE_DURATION_SECONDS = 25 -- "gefühlter Kampf", bevor The Fall automatisch beginnt
local FALL_STAGGER_DURATION_SECONDS = 6 -- wie lange die Health-Abnahme sichtbar/spürbar dauert, bevor der finale Treffer kommt

-- ===== Phase 3: Zeitbasierte Eskalation =====
-- PLANÄNDERUNG: der Alert-Level im Prolog steigt jetzt rein nach VERSTRICHENER ZEIT,
-- nicht mehr nach tatsächlich angerichtetem Zerstörungs-Schaden. Sekunden seit Prolog-
-- Start -> Ziel-Alert-Level. Läuft periodisch (siehe driveEscalationByTime) und setzt
-- den Fortschritt aktiv auf den zum jeweiligen Zeitpunkt passenden Wert -- so bleibt die
-- Eskalation exakt nach Plan, selbst wenn der Spieler nebenbei viele Gebäude zerstört
-- (was normalerweise ebenfalls Alert-Fortschritt geben würde).
local ESCALATION_SCHEDULE = {
	{ atSeconds = 0, level = 1 },
	{ atSeconds = 18.75, level = 2 },
	{ atSeconds = 27.5, level = 3 },
	{ atSeconds = 37.5, level = 4 },
	{ atSeconds = 50, level = 5 },
}

local function findPrologueSpawn()
	local prologueFolder = Workspace:FindFirstChild("Prologue")
	local inFolder = prologueFolder and prologueFolder:FindFirstChild("PrologueSpawn")
	return inFolder or Workspace:FindFirstChild("PrologueSpawn")
end

-- Setzt den Charakter auf die Power-Fantasy-Werte -- überschreibt bewusst die normalen,
-- Setzt den Charakter auf den ECHTEN grössten Skin (Radiant Apex) + Level 50 -- läuft
-- über den normalen applySkinToCharacter()-Mechanismus (Scale, Health, BaseWalkSpeed,
-- Boden-Stabilisierung, Sprungkraft -- alles automatisch dabei, keine Duplikation nötig).
-- Nur "Damage" wird hier zusätzlich manuell gesetzt, da das normalerweise aus
-- ArmPower/recalculateStrength kommt (im Prolog bewusst blockiert, siehe PlayerSetup.lua).
local function applyProloguePowerStats(player, character)
	local leaderstats = player:FindFirstChild("leaderstats")
	local equippedSkin = player:FindFirstChild("EquippedSkin")

	-- Ursprüngliche Werte merken (als Attribut, übersteht den Charakter-Wechsel) -- damit
	-- Phase 7 sie später korrekt wiederherstellen kann, statt hart auf 0 zu setzen. Wichtig
	-- fürs Debug-Testen auf einem bestehenden Charakter (siehe DebugStartPrologueEvent) --
	-- ein echter Erstspieler hat ohnehin bereits 0/0, verhält sich also identisch.
	if leaderstats and leaderstats:FindFirstChild("Level") then
		player:SetAttribute("PrologueOriginalLevel", leaderstats.Level.Value)
		leaderstats.Level.Value = PROLOGUE_LEVEL
	end
	if equippedSkin then
		player:SetAttribute("PrologueOriginalSkin", equippedSkin.Value)
		equippedSkin.Value = PROLOGUE_SKIN_ID
	end

	if _G.ApplySkinToCharacter then
		_G.ApplySkinToCharacter(player, character, PROLOGUE_SKIN_ID)
	else
		warn("[PrologueOrchestrator] _G.ApplySkinToCharacter nicht gefunden -- Prolog-Kaiju bleibt beim Standard-Charakter.")
	end

	local skin = SkinsConfig.GetSkinById(PROLOGUE_SKIN_ID)
	if skin then
		character:SetAttribute("Damage", PROLOGUE_DAMAGE)
	end

	-- Special Energy (Focus Attack, Area Damage etc.) sofort voll aufgeladen -- der
	-- Spieler soll im Prolog direkt auf alle Spezialangriffe zugreifen können, ohne sie
	-- sich erst durch normale Treffer/Combos erarbeiten zu müssen. Ursprünglicher Wert
	-- wird gemerkt (siehe Phase 7), damit ein Debug-Test auf einem bestehenden Charakter
	-- dessen echten Stand nicht verliert.
	player:SetAttribute("PrologueOriginalSpecialEnergy", player:GetAttribute("SpecialEnergy") or 0)
	local specialEnergyMax = ReplicatedStorage:FindFirstChild("SpecialEnergyMax")
	player:SetAttribute("SpecialEnergy", specialEnergyMax and specialEnergyMax.Value or 100)
end

local function teleportToPrologueArea(character)
	local spawnPart = findPrologueSpawn()
	if not spawnPart then
		warn("[PrologueOrchestrator] Workspace.PrologueSpawn nicht gefunden -- Prolog-Kaiju bleibt an der normalen Spawn-Position stehen.")
		return
	end
	character:PivotTo(spawnPart.CFrame + Vector3.new(0, 5, 0))
end

-- ===== Phase 1: Cold Open =====
-- ===== Intro-Kinematik (nach Cold Open, vor Spielerkontrolle) =====
-- Kamera zieht vom Meer her langsam zum Kaiju, dann vom Boden langsam zur Figur -- der
-- Spieler sieht dabei zu, wie der (geskriptete) Kaiju bereits angreift, kann selbst aber
-- noch nicht steuern. Findet die nächsten Häuser in PrologueCity und lässt den Kaiju
-- Punch, "Laser" (Focus-Attack-Strahl-Optik) und Area Damage darauf anwenden -- echter
-- Schaden, über dieselben Funktionen wie beim normalen, spielerausgelösten Angriff.
local FocusAttackEffectEvent = RemoteEventUtils.GetOrCreate("FocusAttackEffectEvent")
local SimulatePrologueActionEvent = RemoteEventUtils.GetOrCreate("SimulatePrologueActionEvent")

local function findNearestPrologueHouses(fromPosition, maxCount)
	local houseTag = _G.HOUSE_TAG or "KaijuHouse"
	local candidates = {}
	for _, house in ipairs(CollectionService:GetTagged(houseTag)) do
		if not house:GetAttribute("Destroyed") and _G.ResolveCityName and _G.ResolveCityName(house) == PROLOGUE_CITY_NAME then
			local housePart = house:IsA("Model") and house.PrimaryPart or (house:IsA("BasePart") and house or nil)
			if housePart then
				table.insert(candidates, { house = house, distance = (housePart.Position - fromPosition).Magnitude })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local result = {}
	for i = 1, math.min(maxCount, #candidates) do
		table.insert(result, candidates[i].house)
	end
	return result
end

-- Findet alle "PrologueCameraSpawn_N"-Parts in Workspace.Prologue und sortiert sie
-- numerisch nach ihrer Endziffer (N) -- ergibt die Reihenfolge des Kamera-Bodenpfads für
-- die Intro-Kinematik (siehe flyOverWaterToKaiju im Client, Bezier-Interpolation).
local function findCameraPathWaypoints()
	local prologueFolder = Workspace:FindFirstChild("Prologue")
	if not prologueFolder then
		return {}, nil
	end
	local candidates = {}
	for _, part in ipairs(prologueFolder:GetChildren()) do
		if part:IsA("BasePart") then
			local numberSuffix = part.Name:match("^PrologueCameraSpawn_(%d+)$")
			if numberSuffix then
				table.insert(candidates, { index = tonumber(numberSuffix), position = part.Position, cframe = part.CFrame })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.index < b.index
	end)
	local waypoints = {}
	for _, entry in ipairs(candidates) do
		table.insert(waypoints, entry.position)
	end
	-- CFrame (inkl. tatsächlicher Studio-Rotation) des LETZTEN Wegpunkts separat
	-- zurückgeben -- der Spieler soll beim Erhalt der Kontrolle exakt diese Perspektive
	-- bekommen, nicht nur eine berechnete "schaut auf den Kaiju"-Ausrichtung.
	local finalCFrame = candidates[#candidates] and candidates[#candidates].cframe
	return waypoints, finalCFrame
end

-- Der Start-Punkt der Kamera-Kinematik ("PrologueCameraSpawn") wurde zu
-- "PrologueCameraSpawn_1" umbenannt und liegt jetzt in Workspace.Prologue, zusammen mit
-- den übrigen Wegpunkten (siehe findCameraPathWaypoints).
local function findSeaSpawn()
	local prologueFolder = Workspace:FindFirstChild("Prologue")
	return prologueFolder and prologueFolder:FindFirstChild("PrologueCameraSpawn_1")
end

local function playIntroCinematic(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local seaSpawn = findSeaSpawn()
	if not humanoid or not rootPart or not seaSpawn then
		warn("[PrologueOrchestrator] Intro-Kinematik übersprungen -- Humanoid/RootPart/PrologueCameraSpawn_1 nicht gefunden.")
		return
	end

	-- Spieler einfrieren -- kann während der Kinematik noch nicht selbst steuern.
	local savedWalkSpeed = humanoid.WalkSpeed
	local savedJumpPower = humanoid.JumpPower
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	local cameraPathWaypoints, finalCameraCFrame = findCameraPathWaypoints()
	if #cameraPathWaypoints < 2 then
		warn("[PrologueOrchestrator] Weniger als 2 'PrologueCameraSpawn_N'-Wegpunkte in Workspace.Prologue gefunden (" .. #cameraPathWaypoints .. ") -- Kamera nutzt Fallback-Pfad.")
	end

	local CAMERA_ALIGN_DURATION = 0.8 -- dient nur noch als Mindest-Puffer für combatStartDelay unten (die eigentliche Align-Phase im Client gibt es nicht mehr)
	local CAMERA_FLY_DURATION = 13

	PlayIntroCinematicEvent:FireClient(player, {
		seaView = seaSpawn.CFrame,
		cameraPathWaypoints = cameraPathWaypoints,
		flyDuration = CAMERA_FLY_DURATION,
		zoomDuration = 1,
		-- Letzter Wegpunkt MIT seiner tatsächlichen Studio-Rotation (nicht nur Position)
		-- -- der Spieler soll beim Erhalt der Kontrolle exakt diese Perspektive bekommen.
		finalCameraCFrame = finalCameraCFrame,
	})

	-- WICHTIG: fadeOut läuft NICHT-BLOCKIEREND, zeitgleich mit dem Start der Kamerafahrt
	-- (siehe PlayIntroCinematicEvent oben) -- die Kamera soll bereits sichtbar in
	-- Bewegung sein, WÄHREND sich der schwarze Bildschirm auflöst, statt dass der
	-- Bildschirm erst komplett aufhellt und die Kamera DANACH erst zu fahren beginnt
	-- (wirkte "gestellt"/unnatürlich).
	StoryBeatService.PlayAsync(player, { steps = { { type = "fadeOut", duration = 1.2 } } })

	-- Geskriptete Angriffe laufen parallel zur Kamerafahrt, nicht blockierend -- feuert
	-- jetzt die ECHTEN Button-Events (dieselben Funktionen wie ein tatsächlicher
	-- Tasten-/Button-Druck, siehe SpecialAttackClient.lua/AttackClient.lua), inklusive
	-- Cooldown-Prüfung. Sequenz: 3x Punch, 1x Sprung, 3x Punch, 1x Fokusschaden, 3x Punch,
	-- 1x Sprung, 3x Punch, 1x Area Damage -- 16 Aktionen insgesamt. Der Charakter läuft
	-- dabei kontinuierlich auf ein selbst gewähltes Ziel (den Leuchtturm) zu.
	--
	-- WICHTIG zum Timing: die echten Cooldowns sind ATTACK_COOLDOWN=0.8s (Punch),
	-- FOCUS_ATTACK_COOLDOWN=1s, AREA_ATTACK_COOLDOWN=1.5s (siehe CombatHandler.lua/
	-- SpecialAttackHandler.lua) -- ein zu kurzer Abstand zwischen zwei Aktionen würde vom
	-- echten System stillschweigend ignoriert (wie ein zu schneller Doppelklick). Die
	-- Pause zwischen Aktionen ist daher auf mindestens 0.85s festgelegt (knapp über dem
	-- strengsten Cooldown zwischen zwei AUFEINANDERFOLGENDEN Aktionen DESSELBEN Typs --
	-- Area/Focus kommen hier je nur einmal vor, ihr eigener, längerer Cooldown spielt
	-- daher gegenüber sich selbst keine Rolle).
	local ACTION_GAP = 0.85
	local TOTAL_ACTIONS = 16
	local combatDuration = (TOTAL_ACTIONS - 1) * ACTION_GAP
	local combatStartDelay = math.max(CAMERA_FLY_DURATION - combatDuration, CAMERA_ALIGN_DURATION)
	print("[Kaiju-Debug] Kampfsequenz-Timing: combatDuration=" .. combatDuration .. " combatStartDelay=" .. combatStartDelay)

	print("[Kaiju-Debug] playIntroCinematic: starte task.spawn für Kampfsequenz")
	task.spawn(function()
		-- Ziel für Fokusstrahl UND Anlauf-Bewegung: der Leuchtturm, falls vorhanden --
		-- sonst Fallback auf das nächste gefundene Gebäude.
		local nearbyHouses = findNearestPrologueHouses(rootPart.Position, 10)
		local leuchtturm = Workspace:FindFirstChild("Leuchtturm", true)
		local walkTarget = leuchtturm or (nearbyHouses[1] and (nearbyHouses[1]:IsA("Model") and nearbyHouses[1].PrimaryPart or nearbyHouses[1]))
		print("[Kaiju-Debug] Kampfsequenz: Leuchtturm=" .. tostring(leuchtturm) .. " walkTarget=" .. tostring(walkTarget))

		-- Dreht den Charakter horizontal zu einer Zielposition (nur Gieren, kein
		-- Nicken/Rollen).
		local function faceTowards(targetPosition)
			if not rootPart.Parent then
				return
			end
			local direction = (targetPosition - rootPart.Position) * Vector3.new(1, 0, 1)
			if direction.Magnitude > 0.1 then
				character:PivotTo(CFrame.lookAt(rootPart.Position, rootPart.Position + direction))
			end
		end

		local function faceNearestHouse()
			local nearest = nearbyHouses[1]
			if not nearest then
				return
			end
			local targetPart = nearest:IsA("Model") and nearest.PrimaryPart or nearest
			if targetPart then
				faceTowards(targetPart.Position)
			end
		end

		-- Läuft ein kurzes Stück (geskriptet, kein echtes WalkSpeed) Richtung walkTarget
		-- -- wird zwischen den Aktionen aufgerufen, damit der Charakter sich sichtbar auf
		-- sein gewähltes Ziel zubewegt, während er gleichzeitig kämpft.
		local WALK_STEP_DISTANCE = 4
		local function stepTowardTarget()
			if not walkTarget or not rootPart.Parent then
				return
			end
			local targetPosition = walkTarget.Position
			local toTarget = (targetPosition - rootPart.Position) * Vector3.new(1, 0, 1)
			local distance = toTarget.Magnitude
			if distance < WALK_STEP_DISTANCE * 1.5 then
				return -- schon nah genug dran -- nicht weiter reinlaufen
			end
			local direction = toTarget.Unit
			local newCFrame = CFrame.lookAt(rootPart.Position + direction * WALK_STEP_DISTANCE, targetPosition)
			character:PivotTo(newCFrame)
		end

		local function doPunch()
			faceNearestHouse()
			SimulatePrologueActionEvent:FireClient(player, "Punch")
			stepTowardTarget()
		end

		local function doJump()
			-- Sprungkraft war für die gesamte Kinematik eingefroren (siehe
			-- Bewegungssperre weiter oben) -- kurz wiederherstellen, damit der echte
			-- Sprung (triggerJump() -> humanoid.Jump=true) tatsächlich wirkt, danach
			-- wieder einfrieren.
			if humanoid.Parent then
				humanoid.JumpPower = savedJumpPower
			end
			SimulatePrologueActionEvent:FireClient(player, "Jump")
			task.wait(0.6) -- kurz Zeit lassen, bis der Sprung tatsächlich ausgelöst wurde
			if humanoid.Parent then
				humanoid.JumpPower = 0
			end
			stepTowardTarget()
		end

		local function doAreaDamage()
			faceNearestHouse()
			SimulatePrologueActionEvent:FireClient(player, "Area")
			stepTowardTarget()
		end

		local function doFocusDamage()
			-- Zielt gezielt auf den Leuchtturm (falls vorhanden) -- die echte
			-- Ziel-Findung (findFocusTarget in SpecialAttackHandler.lua) wählt automatisch
			-- das nächste Gebäude in Blickrichtung, daher genügt es, den Charakter exakt
			-- zum Leuchtturm auszurichten.
			if leuchtturm then
				faceTowards(leuchtturm.Position)
			else
				faceNearestHouse()
			end
			SimulatePrologueActionEvent:FireClient(player, "Focus")
		end

		task.wait(combatStartDelay)

		-- Sequenz: 3x Punch, 1x Sprung, 3x Punch, 1x Fokusschaden, 3x Punch, 1x Sprung,
		-- 3x Punch, 1x Area Damage -- 16 Aktionen, endet exakt wenn die Kamera bei der
		-- letzten PrologueCameraSpawn-Station ankommt (siehe combatStartDelay-Berechnung
		-- weiter oben).
		doPunch()
		task.wait(ACTION_GAP)
		doPunch()
		task.wait(ACTION_GAP)
		doPunch()
		task.wait(ACTION_GAP)

		doJump()
		task.wait(ACTION_GAP)

		doPunch()
		task.wait(ACTION_GAP)
		doPunch()
		task.wait(ACTION_GAP)
		doPunch()
		task.wait(ACTION_GAP)

		doFocusDamage()
		task.wait(ACTION_GAP)

		doPunch()
		task.wait(ACTION_GAP)
		doPunch()
		task.wait(ACTION_GAP)
		doPunch()
		task.wait(ACTION_GAP)

		doJump()
		task.wait(ACTION_GAP)

		doPunch()
		task.wait(ACTION_GAP)
		doPunch()
		task.wait(ACTION_GAP)
		doPunch()
		task.wait(ACTION_GAP)

		doAreaDamage()
	end)



	-- Blockiert, bis der Client mit der Kamera-Kinematik fertig ist.
	local completed = false
	local connection
	connection = CinematicCompleteEvent.OnServerEvent:Connect(function(completedPlayer)
		if completedPlayer == player then
			completed = true
		end
	end)
	local elapsed = 0
	while not completed and player.Parent and elapsed < 20 do
		elapsed += task.wait()
	end
	connection:Disconnect()

	-- Kontrolle zurückgeben.
	if humanoid.Parent then
		humanoid.WalkSpeed = savedWalkSpeed
		humanoid.JumpPower = savedJumpPower
	end
end

local SnapCameraToSeaEvent = RemoteEventUtils.GetOrCreate("SnapCameraToSeaEvent")

local function playColdOpen(player)
	local partOneSteps = { { type = "fadeIn", duration = 0.1 } } -- startet bereits schwarz, minimal für sauberen Übergang

	for _, step in ipairs(buildTickSteps(3, 0.7)) do
		table.insert(partOneSteps, step)
	end

	table.insert(partOneSteps, { type = "wait", duration = 0.8 })

	StoryBeatService.Play(player, { steps = partOneSteps, keepBlackScreen = true })

	-- Sirene läuft über den eigenständigen Sound-Kanal (siehe StoryBeatService.PlaySiren)
	-- -- NICHT als "sound"-Schritt innerhalb der Sequenz, da diese sonst beim
	-- Sequenz-Ende automatisch gestoppt würde (stopAllSounds) und beim erneuten Start in
	-- Teil 2 hörbar doppelt gestartet hätte. So läuft sie nahtlos über beide Teile.
	StoryBeatService.PlaySiren(player, SIREN_SOUND_ID, 0.5)

	task.wait(1)

	-- WICHTIG: Kamera-Sprung ans Meer passiert GENAU HIER -- also während "THE CITY IS
	-- ALREADY LOST." (nicht früher, beim Ticken/den Sirenen) -- damit der Spieler die
	-- Zerstörungs-Explosionen in der Stadt beim Ticken/den Sirenen noch aus der
	-- "richtigen" (3D-Audio-)Perspektive hört. Der Bildschirm ist ohnehin schwarz, der
	-- Sprung selbst also nicht sichtbar.
	local seaSpawn = findSeaSpawn()
	if seaSpawn then
		SnapCameraToSeaEvent:FireClient(player, seaSpawn.CFrame)
	end

	StoryBeatService.Play(player, {
		steps = {
			{ type = "text", text = "THE CITY WILL SOON BE BROKEN.", duration = 3 },
		},
	})
	-- WICHTIG: fadeOut passiert HIER NICHT mehr -- wird stattdessen zeitgleich mit dem
	-- Start der Kamerafahrt (playIntroCinematic) nicht-blockierend ausgelöst, damit die
	-- Kamera bereits in Bewegung ist, WÄHREND sich der Bildschirm auflöst, statt erst
	-- statisch zu stehen und dann zu starten (wirkte "gestellt").

	StoryBeatService.StopSiren(player)
end

-- ===== Phase 2: Power Fantasy + Onboarding =====
-- Tutorial-Checkliste: PUNCH x2, JUMP x2, ABSORB (Mengen-Schwelle) -- zeigt ein Panel
-- beim Spieler, verfolgt die Aktionen server-seitig (zuverlässiger als rein client-
-- seitiges Tracking, da der Server die entsprechenden Events ohnehin bereits empfängt),
-- aktualisiert die Anzeige live, und blockiert, bis alle Ziele erreicht sind.
local TUTORIAL_TARGETS = { Punch = 2, Jump = 2, AbsorbAmount = 5000 }

-- Dauerhafter, sicherer Hook auf _G.AwardSpecialEnergyForAbsorb -- trackt die
-- TATSÄCHLICH ABSORBIERTE MENGE (nicht nur wie oft der Button gedrückt wurde), damit der
-- Spieler lernt, die Taste GEDRÜCKT ZU HALTEN statt nur kurz zu tippen. Bleibt permanent
-- installiert (idempotent) -- funktioniert dadurch korrekt auch bei mehreren
-- gleichzeitigen Spielern im Prolog, jeder hat seinen eigenen Tracker-Eintrag.
local activeAbsorbTrackers = {} -- player -> function(amount)
local absorbHookInstalled = false
local function installAbsorbHookOnce()
	if absorbHookInstalled then
		return
	end
	absorbHookInstalled = true
	local originalAwardSpecialEnergyForAbsorb = _G.AwardSpecialEnergyForAbsorb
	_G.AwardSpecialEnergyForAbsorb = function(awardedPlayer, amount)
		local tracker = activeAbsorbTrackers[awardedPlayer]
		if tracker then
			tracker(amount)
		end
		if originalAwardSpecialEnergyForAbsorb then
			originalAwardSpecialEnergyForAbsorb(awardedPlayer, amount)
		end
	end
end

local function playTutorialChecklist(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	installAbsorbHookOnce()

	local progress = { Punch = 0, Jump = 0, AbsorbAmount = 0 }
	local completed = false
	local connections = {}

	local function sendUpdate()
		UpdateTutorialChecklistEvent:FireClient(player, progress)
	end

	local function checkComplete()
		if completed then
			return
		end
		if progress.Punch >= TUTORIAL_TARGETS.Punch
			and progress.Jump >= TUTORIAL_TARGETS.Jump
			and progress.AbsorbAmount >= TUTORIAL_TARGETS.AbsorbAmount then
			completed = true
		end
	end

	ShowTutorialChecklistEvent:FireClient(player, TUTORIAL_TARGETS)
	sendUpdate()

	-- Punch: jeder Angriffs-Aufruf DIESES Spielers zählt (deckelt bei TUTORIAL_TARGETS,
	-- weitere Angriffe erhöhen nicht mehr sinnlos weiter).
	table.insert(connections, TutorialAttackEvent.OnServerEvent:Connect(function(attackingPlayer)
		if attackingPlayer == player and progress.Punch < TUTORIAL_TARGETS.Punch then
			progress.Punch += 1
			sendUpdate()
			checkComplete()
		end
	end))

	-- Sprung: über den Humanoid-Zustandswechsel zu "Jumping" -- funktioniert
	-- unabhängig davon, ob der Sprung über Tastatur/Button/Touch ausgelöst wurde.
	table.insert(connections, humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping and progress.Jump < TUTORIAL_TARGETS.Jump then
			progress.Jump += 1
			sendUpdate()
			checkComplete()
		end
	end))

	-- Absorb: summiert die tatsächlich absorbierte Menge auf, statt nur zu zählen, wie
	-- oft aktiviert wurde -- der Spieler muss die Taste GEDRÜCKT HALTEN, um die Schwelle
	-- zu erreichen (einzelnes kurzes Antippen absorbiert kaum etwas).
	activeAbsorbTrackers[player] = function(amount)
		if progress.AbsorbAmount < TUTORIAL_TARGETS.AbsorbAmount then
			progress.AbsorbAmount = math.min(progress.AbsorbAmount + (amount or 0), TUTORIAL_TARGETS.AbsorbAmount)
			sendUpdate()
			checkComplete()
		end
	end

	-- Blockiert, bis alle Ziele erreicht sind -- Sicherheitsnetz: nach 120s ungeduldig
	-- abbrechen (z.B. falls ein Spieler die Aktionen aus irgendeinem Grund nie
	-- ausführt), damit der Prolog nicht für immer hängen bleibt.
	local waited = 0
	while not completed and player.Parent and waited < 120 do
		task.wait(0.2)
		waited += 0.2
	end

	activeAbsorbTrackers[player] = nil
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	HideTutorialChecklistEvent:FireClient(player, completed)
end

-- ===== Phase 5: The Fall (geskripteter Niederlage-Ablauf) =====
-- ===== Einfache Fall-Kinematik (nach dem Fall, vor "The Trench Remembers") =====
-- Kamera zoomt auf den Körper des gefallenen Kaiju, danach Schwarzblende -- bewusst
-- deutlich einfacher als die vorherige Wellen-Kinematik. WICHTIG: läuft VOR
-- MarkPrologueComplete (die den Charakter über LoadCharacter neu erstellt/skaliert) --
-- der Kaiju ist an dieser Stelle also noch in seiner vollen Prolog-Grösse zu sehen.
local function playSimpleFallCinematic(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local headPart = character:FindFirstChild("Head")
	-- WICHTIG: der Kaiju liegt zu diesem Zeitpunkt bereits gekippt (~80°, siehe
	-- triggerTheFall) -- ein fester Versatz von rootPart.Position würde daher NICHT mehr
	-- den Kopf treffen (der ist nach dem Kippen deutlich tiefer und versetzt). Deshalb
	-- die tatsächliche Position des "Head"-Teils nutzen, das die richtige Stelle
	-- unabhängig von der Körperhaltung kennt.
	local headPos = headPart and headPart.Position or (rootPart.Position + Vector3.new(0, 4, 0))
	-- Fokus auf den KOPF -- näher und höher als die vorherige Körper-Einstellung.
	local headFocusStart = CFrame.lookAt(headPos + Vector3.new(7, 3, 7), headPos)
	local headFocusEnd = CFrame.lookAt(headPos + Vector3.new(2.5, 1.2, 2.5), headPos) -- näher heran

	SimplePrologueFallCameraEvent:FireClient(player, {
		headFocusStart = headFocusStart,
		headFocusEnd = headFocusEnd,
		panDuration = 3,
		zoomDuration = 4, -- langsames, kontinuierliches Heranzoomen während des Haltens
	})

	-- Jeglicher Sound (Prolog-Musik, Sirene, etc.) wird synchron zum Kamera-Zoom langsam
	-- bis zur Stille ausgeblendet.
	StoryBeatService.FadeOutAllSound(player, 6)

	-- Blockiert, bis der Client mit der Kamera-Kinematik fertig ist (analog zu
	-- StoryBeatService.Play).
	local completed = false
	local connection
	connection = CinematicCompleteEvent.OnServerEvent:Connect(function(completedPlayer)
		if completedPlayer == player then
			completed = true
		end
	end)
	local elapsed = 0
	while not completed and player.Parent and elapsed < 15 do
		elapsed += task.wait()
	end
	connection:Disconnect()

	-- Schwarzblende -- nutzt das bewährte StoryBeatService-System (bleibt danach schwarz,
	-- für die nachfolgende Tick-Sequenz). WICHTIG: "fadeIn" ist hier korrekt (nicht
	-- "fadeOut") -- siehe StoryBeatClient.lua: fadeIn = Bildschirm wird SCHWARZ,
	-- fadeOut = Schwarzblende wird AUFGELÖST (Welt wird sichtbar).
	if player.Parent then
		StoryBeatService.Play(player, { steps = { { type = "fadeIn", duration = 1.5 } } })
	end

	-- Kurzer, bewusster Moment von reinem Schwarz -- bevor im Hintergrund gespawnt wird
	-- (siehe triggerTheFall direkt nach dem Aufruf dieser Funktion).
	if player.Parent then
		task.wait(1)
	end
end


local function triggerTheFall(player)
	if not player.Parent then
		return
	end

	-- WICHTIG: verhindert doppelte, parallel laufende "The Fall"-Durchläufe (z.B. durch
	-- einen Rest-Aufruf aus einem früheren, nicht sauber beendeten Testlauf) -- ohne diese
	-- Sperre könnten zwei Durchläufe gleichzeitig laufen und sich ihre Texte/Titelkarten
	-- gegenseitig überlagern (z.B. "WE ARE TRENCHBORN" und "EARN IT BACK" gleichzeitig
	-- sichtbar, da beide dieselbe Bildschirmmitte nutzen).
	if player:GetAttribute("PrologueFallInProgress") then
		warn("[PrologueOrchestrator] The Fall läuft für " .. player.Name .. " bereits -- ignoriere doppelten Aufruf.")
		return
	end
	player:SetAttribute("PrologueFallInProgress", true)

	StoryBeatService.StopMusic(player) -- Sicherheitsnetz, falls noch aktiv

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		player:SetAttribute("PrologueFallInProgress", false)
		return
	end

	print("[PrologueOrchestrator] The Fall beginnt für " .. player.Name)

	-- WICHTIG: hebt den Health-Untergrenze-Schutz (siehe PrologueReinforcementService.lua)
	-- explizit und sofort auf -- sonst hätte dieser Schutz die geskriptete Health-Abnahme
	-- unten direkt wieder rückgängig gemacht (jede Reduktion hätte sofort den
	-- HealthChanged-Listener ausgelöst, der die Health zurück auf die Untergrenze gesetzt
	-- hätte, solange der interne Alert-Level-Check nicht bereits gegriffen hat).
	if PrologueReinforcementService.ReleaseHealthFloor then
		PrologueReinforcementService.ReleaseHealthFloor(player)
	end

	-- Filmstreifen erscheinen genau jetzt -- wenn der Kaiju beginnt, kontinuierlich Leben
	-- zu verlieren (nicht schon beim Prolog-Start).
	SetPrologueLetterboxEvent:FireClient(player, true)

	-- Sichtbare Verschlechterung: Bewegung wird zunehmend schwerer, Health sinkt
	-- kontrolliert über einige Sekunden -- kein einzelner harter Cut, sondern ein
	-- spürbares "Zurückgedrängt werden".
	local steps = 12
	local startHealth = humanoid.Health
	local startWalkSpeed = humanoid.WalkSpeed
	print("[Kaiju-Debug] The Fall: startHealth=" .. tostring(startHealth) .. " startWalkSpeed=" .. tostring(startWalkSpeed) .. " humanoid.Parent=" .. tostring(humanoid.Parent))
	for i = 1, steps do
		if not humanoid.Parent then
			print("[Kaiju-Debug] The Fall: Schleife abgebrochen bei i=" .. i .. " -- humanoid.Parent ist nil!")
			player:SetAttribute("PrologueFallInProgress", false)
			return
		end
		local fraction = i / steps
		humanoid.Health = math.max(startHealth * (1 - fraction), 1)
		humanoid.WalkSpeed = startWalkSpeed * (1 - fraction * 0.7) -- wird zunehmend langsamer/schwerfälliger
		print("[Kaiju-Debug] The Fall: Schritt " .. i .. "/" .. steps .. " -- Health jetzt=" .. tostring(humanoid.Health))
		task.wait(FALL_STAGGER_DURATION_SECONDS / steps)
	end
	print("[Kaiju-Debug] The Fall: Health-Verlust-Schleife fertig, gehe weiter zum finalen Treffer")

	-- WICHTIG: Players.CharacterAutoLoads ist eine EIGENSCHAFT DES SERVICE (server-global,
	-- betrifft ALLE Spieler), NICHT von Player -- verhindert, dass Roblox' eingebautes
	-- automatisches Respawn-System dazwischenfunkt, sobald Health gleich 0 erreicht
	-- (Humanoid.Died feuert trotz BreakJointsOnDeath=false weiterhin). Bewusst so spät wie
	-- möglich (direkt vor dem tatsächlichen Todeszeitpunkt) gesetzt und weiter unten so
	-- früh wie möglich (direkt nach dem eigenen player:LoadCharacter() in
	-- MarkPrologueComplete) wieder aktiviert -- hält das Zeitfenster, in dem ANDERE
	-- Spieler auf dem Server nicht automatisch respawnen würden, so kurz wie möglich.
	Players.CharacterAutoLoads = false

	-- Letzter Treffer -- Charakter "fällt". WICHTIG: BreakJointsOnDeath deaktiviert --
	-- Roblox würde bei Health=0 sonst standardmässig ein Ragdoll auslösen (Gelenke lösen
	-- sich, einzelne Körperteile werden physikalisch simuliert). Bei einem so grossen,
	-- skalierten Kaiju-Rig führte das zum Einsinken in den Boden, bevor sich die Physik
	-- "eingependelt" hat. Stattdessen: PlatformStand (Charakter bleibt als EIN Rig
	-- zusammenhängend, reagiert nicht mehr auf normale Humanoid-Physik) + ein sanftes,
	-- geskriptetes Kippen nach vorne über CFrame -- kontrolliert statt Physik-abhängig.
	humanoid.BreakJointsOnDeath = false
	humanoid.Health = 0
	humanoid.PlatformStand = true

	if character.Parent then
		-- WICHTIG: SOFORT verankern, VOR dem Kippen -- nicht erst danach. Ohne das bleibt
		-- der Charakter zwischen den einzelnen PivotTo-Aufrufen im Kipp-Loop (jeder
		-- task.wait() ist ein Physik-Schritt) weiterhin normal physikalisch simuliert,
		-- Schwerkraft wirkt bereits WÄHREND der Animation -- konnte dazu führen, dass er
		-- schon beim Kippen durch den Boden "tunnelt" und unsichtbar wird, bevor die
		-- Verankerung überhaupt greift.
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end

		local startCFrame = character:GetPivot()
		-- Kippt um die eigene Achse nach vorne (in Blickrichtung) um ca. 80 Grad --
		-- wirkt wie ein kontrolliertes Umfallen, bleibt aber fest über dem Boden statt
		-- einzusinken. Leicht angehoben, damit er nicht durch den Boden clippt, während er
		-- kippt.
		local tiltPivot = startCFrame * CFrame.new(0, -2, 0) -- Dreh-Achse nahe den "Füssen", nicht im Zentrum
		local targetCFrame = tiltPivot * CFrame.Angles(math.rad(80), 0, 0) * CFrame.new(0, 2, 0)

		local tiltDuration = 1.2
		local tiltStartTime = os.clock()
		while os.clock() - tiltStartTime < tiltDuration and character.Parent do
			local alpha = (os.clock() - tiltStartTime) / tiltDuration
			local easedAlpha = 1 - (1 - alpha) * (1 - alpha) -- Ease-Out, wird sanft langsamer
			character:PivotTo(startCFrame:Lerp(targetCFrame, easedAlpha))
			task.wait()
		end
		if character.Parent then
			character:PivotTo(targetCFrame)
		end
	end

	-- ===== Einfache Fall-Kinematik (Kamera-Zoom + Sound-Ausblendung + Schwarzblende) =====
	playSimpleFallCinematic(player)

	-- ===== Phase 7: Awakening -- läuft jetzt DIREKT nach der Schwarzblende, im
	-- Hintergrund, während der Bildschirm bereits schwarz ist (nicht erst nach den
	-- Text-Sequenzen unten). WICHTIG: player:LoadCharacter() (in MarkPrologueComplete)
	-- setzt NUR den Charakter neu, NICHT die Leaderstats/Attribute selbst zurück -- Level
	-- UND Skin werden deshalb HIER explizit und UNCONDITIONAL auf 0 gesetzt (nicht auf
	-- den vorher gemerkten Original-Wert) -- der Prolog stellt Tod+Wiedergeburt dar,
	-- beide sollen danach IMMER beim kleinsten/niedrigsten Wert starten, auch falls sie
	-- vor dem Prolog z.B. übers Debug-Panel manuell auf einen höheren Wert gesetzt
	-- wurden. =====
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats and leaderstats:FindFirstChild("Level") then
		leaderstats.Level.Value = 0
	end
	local equippedSkin = player:FindFirstChild("EquippedSkin")
	if equippedSkin then
		equippedSkin.Value = 0 -- kleinster Skin ("Baby Kaiju", Id 0 in SkinsConfig.lua)
	end

	-- ArmPower/LegPower/BodyPower ebenfalls auf die Starter-Werte zurücksetzen -- diese
	-- wurden vom Prolog-Code bisher NICHT angefasst und blieben z.B. beim Debug-Testen
	-- (Debug-Panel setzt diese Werte oft mit hoch) fälschlich auf den hohen Werten stehen.
	-- Nutzt dieselbe Berechnung wie für einen echten Erstspieler (siehe
	-- ComputeStarterStats in PlayerSetup.lua), statt hart auf 0 zu setzen -- 0 würde bei
	-- manchen Level-1-Cap-Formeln zu Divisionen/Anzeigen führen, die nicht als "frisch"
	-- erkannt werden.
	-- WICHTIG: nutzt bewusst NICHT ComputeStarterStats() (die für einen normalen
	-- Neuling 80% des Level-1-Caps vergibt) -- der Prolog-Reset soll stattdessen auf
	-- 50% starten. Gleiche zugrundeliegenden Werte (GetStatCapForLevel, ARM_CAP_SCALE,
	-- LEG_CAP_SCALE) wie ComputeStarterStats in PlayerSetup.lua, nur mit anderem Anteil.
	local PROLOGUE_RESET_RATIO = 0.5
	local function computePrologueResetStats()
		local getCapForLevel = _G.GetStatCapForLevel
		if not getCapForLevel then
			return { LegPower = 1, ArmPower = 1, BodyPower = 1 }
		end
		local armCapScale = _G.ARM_CAP_SCALE or 1
		local legCapScale = _G.LEG_CAP_SCALE or 1
		local capAtLevel1 = getCapForLevel(1)

		local function roundedGift(cap)
			return math.max(math.floor(cap * PROLOGUE_RESET_RATIO * 10 + 0.5) / 10, 1)
		end

		return {
			LegPower = roundedGift(capAtLevel1 * legCapScale),
			ArmPower = roundedGift(capAtLevel1 * armCapScale),
			BodyPower = roundedGift(capAtLevel1),
		}
	end

	local function resetPowerStats()
		local starterStats = computePrologueResetStats()
		local legPower = player:FindFirstChild("LegPower")
		local armPower = player:FindFirstChild("ArmPower")
		local bodyPower = player:FindFirstChild("BodyPower")
		if legPower then
			legPower.Value = starterStats.LegPower
		end
		if armPower then
			armPower.Value = starterStats.ArmPower
		end
		if bodyPower then
			bodyPower.Value = starterStats.BodyPower
		end
	end
	resetPowerStats()
	player:SetAttribute("SpecialEnergy", player:GetAttribute("PrologueOriginalSpecialEnergy") or 0)

	if _G.MarkPrologueComplete then
		_G.MarkPrologueComplete(player) -- setzt HasCompletedPrologue, speichert, spawnt normal (Level 0, Sanctuary)
	end

	-- Sicherheitsnetz: Level/Skin/Power-Stats NOCH EINMAL zurücksetzen, direkt NACH
	-- MarkPrologueComplete -- player:LoadCharacter() darin könnte über einen
	-- CharacterAdded-Handler (an anderer Stelle im Projekt) diese Werte erneut anfassen.
	-- So ist garantiert, dass der Spieler den Prolog wirklich bei Level 0, dem
	-- kleinsten Skin und den Starter-Power-Werten verlässt -- IMMER, unabhängig vom
	-- Stand vor dem Prolog.
	if leaderstats and leaderstats:FindFirstChild("Level") then
		leaderstats.Level.Value = 0
	end
	if equippedSkin then
		equippedSkin.Value = 0 -- kleinster Skin ("Baby Kaiju", Id 0 in SkinsConfig.lua)
	end
	resetPowerStats()

	-- Server-globale Einstellung so früh wie möglich wieder aktivieren (siehe
	-- ausführlicher Kommentar bei der Deaktivierung weiter oben) -- der eigene Charakter
	-- wurde soeben bereits explizit erzeugt, andere Spieler auf dem Server respawnen ab
	-- jetzt wieder normal automatisch.
	Players.CharacterAutoLoads = true

	player:SetAttribute("IsInPrologue", false)
	if _G.SetCityManuallyDriven then
		_G.SetCityManuallyDriven(PROLOGUE_CITY_NAME, false)
	end

	-- Sobald der Spieler im Sanctuary gespawnt ist: PrologueCity für den nächsten Spieler
	-- zurücksetzen und die Warteschlange freigeben -- läuft in einem eigenen task.spawn,
	-- damit es die Lift-Sequenz des AKTUELLEN Spielers (unten) nicht blockiert.
	task.spawn(function()
		resetPrologueCity()
		prologueOccupiedBy = nil
		tryStartNextInQueue()
	end)

	task.wait(1) -- kurz warten, bis der normale Spawn (in Sanctuary) sicher abgeschlossen ist

	-- ===== Trench-Teleport (still, Bildschirm bleibt schwarz) -- passiert jetzt direkt
	-- "mit" der Schwarzblende, im Hintergrund, lange bevor die Text-Sequenzen unten
	-- überhaupt beginnen. =====
	local prologueFolderForTrench = Workspace:FindFirstChild("Prologue")
	local trenchSpawn = (prologueFolderForTrench and prologueFolderForTrench:FindFirstChild("TrenchSpawn")) or Workspace:FindFirstChild("TrenchSpawn")
	local trenchTopMarker = (prologueFolderForTrench and prologueFolderForTrench:FindFirstChild("TrenchTopMarker")) or Workspace:FindFirstChild("TrenchTopMarker")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if trenchSpawn and trenchTopMarker and humanoid and rootPart then
		character:PivotTo(trenchSpawn.CFrame)
	end

	-- Kein fadeIn hier nötig -- Bildschirm ist bereits schwarz (Ende von
	-- playSimpleFallCinematic), bleibt für die Tick-Sequenz einfach schwarz.
	local fallSteps = {}
	for _, step in ipairs(buildTickSteps(3, 0.7)) do
		table.insert(fallSteps, step)
	end
	StoryBeatService.Play(player, { steps = fallSteps })

	-- ===== Phase 6: Tod-Aussage =====
	-- WICHTIG (Regie-Überarbeitung): "POWER CAN BE BROKEN." + "PURPOSE CANNOT." zu EINER
	-- zweizeiligen Karte zusammengefasst (statt zwei einzelner Text-Beats) -- "THE TRENCH
	-- REMEMBERS." komplett gestrichen, da inhaltlich redundant zur direkt folgenden
	-- "WE ARE TRENCHBORN"-Kapitel-Karte. Reduziert die Anzahl aufeinanderfolgender
	-- Text-Momente in dieser Sequenz insgesamt von sechs auf drei -- weniger "Lese-
	-- Ermüdung", mehr Gewicht pro Moment.
	local trenchSteps = {
		{ type = "text", text = "POWER CAN BE BROKEN.\nPURPOSE CANNOT.", duration = 3.5 },
	}

	print("[Kaiju-Debug] Server: feuere Trench-Remembers-Sequenz für " .. player.Name .. " -- tick=" .. tostring(os.clock()))
	StoryBeatService.Play(player, {
		steps = trenchSteps,
		keepBlackScreen = true, -- nahtloser Übergang zur Titelkarte unten, Bildschirm bleibt schwarz
	})

	-- Starter-Musik beginnt exakt mit dem Erscheinen der "WE ARE TRENCHBORN"-Titelkarte,
	-- bei VOLLER Lautstärke (dramatischer Moment) -- fährt erst später, bei der
	-- Kontrollübergabe an den Spieler, sanft auf die normale Gameplay-Lautstärke herunter
	-- (siehe FadeMusicToNormalVolume weiter unten, bei "Übergang zur freien Kontrolle").
	local TRENCHBORN_MUSIC_FULL_VOLUME = 0.8
	StoryBeatService.ResumeNormalMusic(player, TRENCHBORN_MUSIC_FULL_VOLUME)

	-- Trench-Orbit-Kamera: schaut von oben schräg auf den Trench und umrundet ihn langsam
	-- -- läuft NICHT-BLOCKIEREND (Fire-and-forget) parallel zu "WE ARE TRENCHBORN" und
	-- "YOUR POWER IS GONE" (zusammen 6s), schwenkt dann zum Spieler und hält dort, sobald
	-- "EARN IT BACK" erscheint.
	local trenchOrbitCenter = (trenchTopMarker and trenchTopMarker.Position) or trenchSpawn.Position
	local WE_ARE_TRENCHBORN_DURATION = 3.5
	local YOUR_POWER_IS_GONE_DURATION = 2.5
	TrenchOrbitCameraEvent:FireClient(player, {
		center = trenchOrbitCenter,
		radius = 45,
		height = 60,
		orbitDuration = WE_ARE_TRENCHBORN_DURATION + YOUR_POWER_IS_GONE_DURATION,
		panToPlayerDuration = 3,
		playerFocusPosition = trenchSpawn.Position,
	})

	-- Cinematischer Reveal: der Trench schält sich langsam (auf ~50% Transparenz) aus dem
	-- Schwarz, WÄHREND die Titelkarte steht -- "revealBackground" läuft dabei NICHT-
	-- blockierend parallel zur Titelkarten-Anzeige (siehe StoryBeatClient.lua). Bleibt auf
	-- diesem gedämpften Niveau durch die folgenden Texte (siehe preserveTransparency
	-- unten), bis die Lift-Sequenz ganz am Ende vollständig aufhellt.
	local TRENCH_DIM_REVEAL_TRANSPARENCY = 0.5
	StoryBeatService.Play(player, {
		steps = {
			{ type = "revealBackground", targetTransparency = TRENCH_DIM_REVEAL_TRANSPARENCY, duration = 3.5 },
			{ type = "chapterCard", title = "WE ARE TRENCHBORN", duration = WE_ARE_TRENCHBORN_DURATION },
		},
		keepBlackScreen = true, -- nahtloser Übergang zum Text unten, Bildschirm bleibt (gedämpft) sichtbar
	})

	-- WICHTIG (Regie-Überarbeitung): "YOUR POWER IS GONE." + "EARN IT BACK." zu EINER
	-- zweizeiligen Karte zusammengefasst -- die Kamera umrundet während der ersten ~2.5s
	-- weiter (siehe orbitDuration oben) und schwenkt danach zum Spieler, während diese
	-- Karte noch angezeigt wird -- der Teleport zu TrenchSpawn ist bereits (weiter oben,
	-- still, im Hintergrund) erfolgt. preserveTransparency: Bildschirm bleibt auf dem
	-- gedämpften Trench-Niveau von oben, statt auf Voll-Schwarz zurückgesetzt zu werden.
	StoryBeatService.Play(player, {
		steps = { { type = "text", text = "YOUR POWER IS GONE.\nEARN IT BACK.", duration = 4 } },
		keepBlackScreen = true,
		preserveTransparency = true,
	})


	-- ===== Übergang zur freien Kontrolle =====
	-- Nach "EARN IT BACK" bekommt der Spieler SOFORT die volle, freie Kontrolle -- kein
	-- Einfrieren/Warten auf den Lift mehr. Der Spieler kann sich frei bewegen und den
	-- normalen Sanctuary-Lift danach wie jeder andere Spieler auch ganz regulär selbst
	-- benutzen (siehe SanctuaryLiftRider.lua), statt in einer geskripteten Fahrt
	-- mitgetragen zu werden.

	-- Kamera-Kontrolle zurückgeben -- die Trench-Orbit-Kinematik (oben ausgelöst) hält die
	-- Kamera bis hierhin auf Scriptable, geschwenkt zum Spieler. Erst jetzt (Übergang zur
	-- freien Kontrolle) wechselt sie zurück auf normale, spielergesteuerte Kamera.
	RestorePrologueCameraEvent:FireClient(player)

	-- Musik jetzt sanft von der vollen "WE ARE TRENCHBORN"-Lautstärke auf die normale
	-- Gameplay-Lautstärke herunterfahren -- genau bei der Kontrollübergabe.
	StoryBeatService.FadeMusicToNormalVolume(player, 2.5)

	-- Schliesst den Shop zwangsweise -- unabhängig von der (noch ungeklärten) Ursache,
	-- die ihn während des Prologs öffnet.
	ForceCloseShopEvent:FireClient(player)

	-- Sicherheitsnetz: da TrenchSpawn im Fahrbereich des echten Sanctuary-Lifts liegt,
	-- könnte der frisch gespawnte Charakter vom Lift-Server-Skript fälschlich als
	-- "auf dem Lift stehend" erkannt und in die "SanctuaryRider"-Kollisionsgruppe versetzt
	-- worden sein (siehe Sanctuary Lift V20 SERVER), OHNE dass die reguläre
	-- Freigabe-Logik (restoreCharacter) je greift, da der Spieler ja gar nicht bewusst
	-- mitfahren wollte. Setzt hier explizit auf "Default" zurück, um ein Stecken-
	-- bleiben/Durchfallen durch normale Parts zu verhindern.
	do
		local freshCharacter = player.Character
		if freshCharacter then
			for _, part in ipairs(freshCharacter:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CollisionGroup = "Default"
				end
			end
		end
	end

	-- WICHTIG (Regie-Überarbeitung): KEINE separate Schwarzblenden-Auflösung mehr hier --
	-- vorher wurde die Welt schon VOLL sichtbar, BEVOR die Kapitel-Karte kam, wodurch die
	-- Karte wie ein Nachklapp wirkte (Spieler hatte ja schon freie Sicht+Kontrolle). Die
	-- Kapitel-Karte unten übernimmt jetzt selbst die Auflösung -- erscheint auf dem noch
	-- gedämpften Hintergrund, ihre eigene fadeOut markiert den eigentlichen Übergang zum
	-- Gameplay (klassische "Kapitel-Karte markiert den Beginn der Szene"-Dramaturgie).
	print("[Kaiju-Debug] Übergang: Spieler erhält freie Kontrolle, Kapitel-Karte folgt gleich")

	-- Nochmalige Absicherung direkt vor der Kapitel-Karte -- genau hier wurde der Shop
	-- bisher fälschlich sichtbar.
	ForceCloseShopEvent:FireClient(player)

	StoryBeatService.Play(player, {
		steps = {
			{ type = "chapterCard", number = "I", title = "KAIJU", subtitle = "POWER", duration = 3.5 },
			{ type = "fadeOut", duration = 1.5 },
		},
		preserveTransparency = true, -- setzt beim gedämpften Trench-Niveau an, kein erneutes Voll-Schwarz
	})

	-- Prolog vorbei -- schwarze Filmstreifen JETZT wieder ausblenden -- nach der
	-- Kapitel-Karte, nicht mehr davor (die Karte ist selbst noch Teil des
	-- cinematischen Moments, die Balken sollen währenddessen bestehen bleiben).
	SetPrologueLetterboxEvent:FireClient(player, false)

	-- Dritte Absicherung ganz am Ende -- der Ablauf hat sich durch die Regie-
	-- Überarbeitung verschoben, evtl. öffnet sich der Shop jetzt an einem späteren
	-- Zeitpunkt als zuvor beobachtet.
	ForceCloseShopEvent:FireClient(player)

	player:SetAttribute("PrologueFallInProgress", false)
end

-- ===== Phase 4: Guardian-Auftritt =====
local function triggerGuardianPhase(player)
	print("[PrologueOrchestrator] Guardian-Phase beginnt für " .. player.Name)

	StoryBeatService.StopMusic(player) -- "Die Musik bricht kurz ab" -- danach nur noch das Ticken

	local steps = buildTickSteps(3, 0.7)
	table.insert(steps, { type = "wait", duration = 0.4 })
	table.insert(steps, { type = "hint", text = "GUARDIAN DEPLOYED", duration = 3.5 })

	StoryBeatService.Play(player, { steps = steps })

	-- TEMPORÄR: Prolog-Guardian doppelt so gross, bis ein neues, für den Prolog
	-- passenderes Guardian-Modell existiert. NUR für den Prolog -- betrifft keine
	-- anderen Guardians im Spiel. Wartet mit Wiederholungsversuchen auf das Modell,
	-- falls es beim Alert-Level-5-Wechsel noch nicht sofort existiert.
	task.spawn(function()
		local guardianModel = nil
		for _ = 1, 25 do
			guardianModel = _G.GetGuardianModel and _G.GetGuardianModel(PROLOGUE_CITY_NAME)
			if guardianModel then
				break
			end
			task.wait(0.2)
		end
		if guardianModel then
			local ok = pcall(function()
				guardianModel:ScaleTo(2)
			end)
			if not ok then
				warn("[PrologueOrchestrator] Guardian-Skalierung (2x) fehlgeschlagen -- Modell unterstützt ScaleTo() evtl. nicht.")
			end
		else
			warn("[PrologueOrchestrator] Guardian-Modell für 2x-Skalierung nicht gefunden.")
		end
	end)

	-- Guardian läuft während der gesamten Phase kontinuierlich näher zum Spieler heran,
	-- bleibt aber in einem Mindestabstand stehen (kein Reinlaufen in den Charakter).
	local GUARDIAN_APPROACH_MIN_DISTANCE = 18
	task.spawn(function()
		local guardianModel = _G.GetGuardianModel and _G.GetGuardianModel(PROLOGUE_CITY_NAME)
		local guardianRoot = guardianModel and (guardianModel.PrimaryPart or guardianModel:FindFirstChild("HumanoidRootPart"))
		if not guardianRoot then
			return
		end
		local approachDuration = GUARDIAN_PHASE_DURATION_SECONDS - 3 -- endet kurz vor dem Fokus/Area-Angriff unten
		local startTime = os.clock()
		while os.clock() - startTime < approachDuration and guardianModel.Parent and player:GetAttribute("IsInPrologue") do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart then
				break
			end
			local toPlayer = (rootPart.Position - guardianRoot.Position) * Vector3.new(1, 0, 1)
			local distance = toPlayer.Magnitude
			local dt = task.wait()
			if distance > GUARDIAN_APPROACH_MIN_DISTANCE then
				local direction = toPlayer.Unit
				local moveDistance = math.min(distance - GUARDIAN_APPROACH_MIN_DISTANCE, 6 * dt)
				local step = direction * moveDistance
				guardianModel:PivotTo(CFrame.lookAt(guardianRoot.Position + step, guardianRoot.Position + step + direction))
			end
		end
	end)

	-- Kurz vor dem Sturz: geskripteter Fokusstrahl + Area Damage gegen den Guardian --
	-- nutzt _G.DamageGuardian direkt (die reguläre Fokus/Area-Zielfindung würde
	-- Gebäude anvisieren, nicht den Guardian).
	task.spawn(function()
		task.wait(GUARDIAN_PHASE_DURATION_SECONDS - 3)
		local guardianModel = _G.GetGuardianModel and _G.GetGuardianModel(PROLOGUE_CITY_NAME)
		local guardianRoot = guardianModel and (guardianModel.PrimaryPart or guardianModel:FindFirstChild("HumanoidRootPart"))
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not guardianRoot or not rootPart then
			return
		end

		local damage = character:GetAttribute("Damage") or 500

		-- Fokusstrahl auf den Guardian.
		local direction = (guardianRoot.Position - rootPart.Position) * Vector3.new(1, 0, 1)
		if direction.Magnitude > 0.1 then
			character:PivotTo(CFrame.lookAt(rootPart.Position, rootPart.Position + direction))
		end
		FocusAttackEffectEvent:FireAllClients(player, rootPart.Position + Vector3.new(0, 8, 0), guardianRoot.Position)
		if _G.DamageGuardian then
			_G.DamageGuardian(PROLOGUE_CITY_NAME, damage, player)
		end

		task.wait(1.2)

		-- Area Damage in Richtung Guardian.
		if _G.PerformAreaDamage then
			_G.PerformAreaDamage(player, rootPart.Position, 180, damage * 0.5)
		end
		if _G.DamageGuardian then
			_G.DamageGuardian(PROLOGUE_CITY_NAME, damage * 0.5, player)
		end
	end)

	task.spawn(function()
		task.wait(GUARDIAN_PHASE_DURATION_SECONDS)
		triggerTheFall(player)
	end)
end

-- Läuft periodisch, solange der Spieler im Prolog ist -- setzt den Alert-Fortschritt
-- aktiv auf den zum aktuellen Zeitpunkt passenden Wert (siehe ESCALATION_SCHEDULE).
-- Dadurch bleibt die Eskalation exakt nach Zeitplan, auch wenn parallel Zerstörung
-- (normalerweise ebenfalls Alert-Fortschritt gebend) passiert.
local function driveEscalationByTime(player)
	-- WICHTIG: Generation-Absicherung gegen mehrere gleichzeitig laufende Schleifen (z.B.
	-- Reste aus einem vorherigen, nicht sauber beendeten Testlauf). Jeder Aufruf erhöht
	-- die Generation-Nummer -- eine ÄLTERE, noch laufende Schleife erkennt daran, dass sie
	-- überholt wurde, und beendet sich sofort selbst, statt mit einem falschen (alten)
	-- Zeit-Ursprung gegen die neue Schleife zu konkurrieren (das verursachte sichtbar
	-- hin- und herspringende Alert-Level).
	local myGeneration = (player:GetAttribute("PrologueEscalationGeneration") or 0) + 1
	player:SetAttribute("PrologueEscalationGeneration", myGeneration)

	local startTime = os.clock()

	while player.Parent and player:GetAttribute("IsInPrologue") do
		if player:GetAttribute("PrologueEscalationGeneration") ~= myGeneration then
			return -- eine neuere Schleife hat übernommen -- sofort beenden
		end

		local elapsed = os.clock() - startTime

		local targetLevel = ESCALATION_SCHEDULE[1].level
		for _, entry in ipairs(ESCALATION_SCHEDULE) do
			if elapsed >= entry.atSeconds then
				targetLevel = entry.level
			end
		end

		if _G.SetCityAlertLevel then
			_G.SetCityAlertLevel(PROLOGUE_CITY_NAME, targetLevel)
		end

		-- Guardian-Stufe (5) einmal erreicht: Zeitplan ist durchgelaufen, weiteres
		-- periodisches Nachsetzen nicht mehr nötig (Guardian-Phase übernimmt ab hier).
		if targetLevel >= 5 then
			return
		end

		task.wait(2)
	end
end

-- ===== Phase 3: Eskalations-Listener =====
local function watchEscalation(player)
	-- WICHTIG: dieselbe Generation wie driveEscalationByTime (dort erhöht) -- verhindert,
	-- dass ein alter, evtl. noch hängender Listener aus einem früheren Testlauf die
	-- Guardian-Phase MEHRFACH auslöst (führte sonst zu mehreren parallel abgespielten
	-- StoryBeat-Sequenzen für dieselbe Guardian-Ankündigung).
	local myGeneration = player:GetAttribute("PrologueEscalationGeneration") or 0

	local attempts = 0
	while not _G.CityAlertLevelChanged and attempts < 100 do
		task.wait(0.1)
		attempts += 1
	end
	if not _G.CityAlertLevelChanged then
		warn("[PrologueOrchestrator] _G.CityAlertLevelChanged nie gefunden -- Eskalation im Prolog bleibt wirkungslos.")
		return
	end

	_G.CityAlertLevelChanged.Event:Connect(function(cityName, newLevel, oldLevel)
		if cityName ~= PROLOGUE_CITY_NAME then
			return
		end
		if not player:GetAttribute("IsInPrologue") then
			return -- dieser Spieler ist nicht (mehr) im Prolog -- ignorieren
		end
		if player:GetAttribute("PrologueEscalationGeneration") ~= myGeneration then
			return -- eine neuere Generation hat übernommen -- dieser Listener ist überholt
		end

		if newLevel == 5 and oldLevel < 5 then
			triggerGuardianPhase(player)
		end
	end)
end

-- ===== Haupt-Einstiegspunkt =====
-- ===== Vorab zerstörte Kulisse (PrologueCity soll von Anfang an teilweise in Trümmern
-- liegen) =====
-- In Studio: Häuser, die von Anfang an zerstört sein sollen, mit dem STRING-Attribut
-- "PrologueStartRuin" markieren -- Wert entweder "Burning" (brennt/raucht unendlich
-- lange, aber ganz normal von Feuerwehr löschbar) oder "Clean" (nur Ruine, kein Feuer).
-- Werden dann bei jedem Prolog-Start automatisch dauerhaft zerstört -- kein Respawn,
-- siehe HouseHandler.lua "PermanentlyDestroyed"-Attribut-Prüfungen.
-- Setzt PrologueCity für den nächsten Spieler zurück -- respawnt alle vom AKTUELLEN
-- Spieler zerstörten Häuser (die "PrologueStartRuin"-Baseline-Ruinen bleiben bewusst
-- zerstört, das ist ihr dauerhafter Ausgangszustand), entfernt einen evtl. noch aktiven
-- Guardian und setzt den Alert-Level zurück.
function resetPrologueCity()
	print("[PrologueOrchestrator] Setze " .. PROLOGUE_CITY_NAME .. " für den nächsten Spieler zurück...")

	local houseTag = _G.HOUSE_TAG or "KaijuHouse"
	local respawnedCount = 0
	if _G.ResolveCityName and _G.ForceRespawnHouse then
		for _, house in ipairs(CollectionService:GetTagged(houseTag)) do
			if _G.ResolveCityName(house) == PROLOGUE_CITY_NAME then
				if not house:GetAttribute("PrologueStartRuin") and house:GetAttribute("Destroyed") then
					_G.ForceRespawnHouse(house)
					respawnedCount += 1
				end
			end
		end
	end
	print("[PrologueOrchestrator] " .. respawnedCount .. " vom Spieler zerstörte Häuser respawnt.")

	if _G.DespawnGuardianForCity then
		_G.DespawnGuardianForCity(PROLOGUE_CITY_NAME)
	end

	-- Militär-Einheiten (Panzer, Raketenwerfer, Helikopter), Feuerwehr-Fahrzeuge und
	-- Barrikaden-Cluster despawnen -- nutzt dieselben Funktionen, die auch bei einer
	-- normalen Alert-Level-Deeskalation greifen (siehe MilitaryService.lua/
	-- FireEngineController.lua/BarricadeClusterService.lua), räumen also auch die
	-- internen Tracking-Tabellen korrekt mit auf, nicht nur die sichtbaren Modelle.
	if _G.DespawnMilitaryForCity then
		_G.DespawnMilitaryForCity(PROLOGUE_CITY_NAME)
	end
	if _G.DespawnFireEnginesForCity then
		_G.DespawnFireEnginesForCity(PROLOGUE_CITY_NAME)
	end
	if _G.DespawnAllBarricadeClustersForCity then
		_G.DespawnAllBarricadeClustersForCity(PROLOGUE_CITY_NAME)
	end
	print("[PrologueOrchestrator] Militär-Einheiten, Feuerwehr-Fahrzeuge und Barrikaden-Cluster für " .. PROLOGUE_CITY_NAME .. " despawnt.")

	if _G.SetCityAlertLevel then
		_G.SetCityAlertLevel(PROLOGUE_CITY_NAME, 1)
	end

	print("[PrologueOrchestrator] " .. PROLOGUE_CITY_NAME .. " zurückgesetzt.")
end

-- ===== Warteschlange: PrologueCity ist ein geteilter Bereich -- nur EIN Spieler kann sie
-- gleichzeitig durchlaufen. Weitere Spieler, die währenddessen starten wollen (echter
-- Erstspieler-Trigger oder Debug-Button), werden in eine Warteschlange gestellt und
-- automatisch gestartet, sobald der aktuelle Durchlauf fertig ist. Echte Erstspieler
-- (noch nie HasCompletedPrologue) haben PRIORITÄT vor Spielern, die den Prolog nur
-- nochmal spielen wollen (Debug-Button o.ä.) -- werden also vor allen Wiederholern
-- eingereiht, aber hinter bereits wartenden anderen Erstspielern (fair untereinander). =====
local PrologueQueueStatusEvent = RemoteEventUtils.GetOrCreate("PrologueQueueStatusEvent")

-- prologueOccupiedBy steht weiter oben (Vorwaertsdeklaration).
local prologueQueue = {} -- Liste von { player = Player, isFirstTime = bool }, in Warte-Reihenfolge

-- Schickt allen aktuell Wartenden ihre (ggf. neue) Position -- wird bei jeder Änderung
-- der Warteschlange (Ein-/Austritt, Start des nächsten) für alle neu berechnet und
-- verschickt, damit die Anzeige immer korrekt bleibt.
local function broadcastQueuePositions()
	for index, entry in ipairs(prologueQueue) do
		if entry.player.Parent then
			PrologueQueueStatusEvent:FireClient(entry.player, index, #prologueQueue)
		end
	end
end

function tryStartNextInQueue()
	if prologueOccupiedBy then
		return -- noch belegt
	end
	local nextEntry = table.remove(prologueQueue, 1)
	while nextEntry and not nextEntry.player.Parent do
		-- Spieler hat den Server währenddessen verlassen -- überspringen, nächsten
		-- prüfen.
		nextEntry = table.remove(prologueQueue, 1)
	end
	broadcastQueuePositions() -- alle übrigen rücken eine Position vor
	if not nextEntry then
		return
	end
	PrologueQueueStatusEvent:FireClient(nextEntry.player, nil) -- Anzeige ausblenden -- startet jetzt
	prologueOccupiedBy = nextEntry.player
	task.spawn(function()
		startPrologueInternal(nextEntry.player)
	end)
end


-- In Studio: Häuser, die von Anfang an zerstört sein sollen, mit dem STRING-Attribut
-- "PrologueStartRuin" markieren -- Wert entweder "Burning" (brennt/raucht unendlich
-- lange, aber ganz normal von Feuerwehr löschbar) oder "Clean" (nur Ruine, kein Feuer).
-- Werden dann bei jedem Prolog-Start automatisch dauerhaft zerstört -- kein Respawn,
-- siehe HouseHandler.lua "PermanentlyDestroyed"-Attribut-Prüfungen.
local function destroyStartingRuins()
	if not _G.PermanentlyDestroyHouse or not _G.ResolveCityName then
		warn("[PrologueOrchestrator] _G.PermanentlyDestroyHouse/_G.ResolveCityName nicht gefunden -- vorab zerstörte Kulisse übersprungen.")
		return
	end
	local houseTag = _G.HOUSE_TAG or "KaijuHouse"
	local count = 0
	for _, house in ipairs(CollectionService:GetTagged(houseTag)) do
		local ruinType = house:GetAttribute("PrologueStartRuin")
		if ruinType and _G.ResolveCityName(house) == PROLOGUE_CITY_NAME then
			_G.PermanentlyDestroyHouse(house, ruinType)
			count += 1
		end
	end
	print("[PrologueOrchestrator] " .. count .. " Häuser als vorab zerstörte Kulisse markiert.")
end

function startPrologueInternal(player)
	-- WICHTIG: verhindert überlappende Durchläufe (z.B. durch Mehrfachklick auf den
	-- Debug-Button, siehe DebugStartPrologueEvent) -- ohne diese Sperre würden mehrere
	-- gleichzeitig laufende driveEscalationByTime-Schleifen + watchEscalation-Listener
	-- entstehen, die sich gegenseitig überlagern (spürbar z.B. als doppelt/dreifach
	-- abspielende Sirenen oder wiederholt spawnende Feuerwehr/Militär-Einheiten).
	if player:GetAttribute("IsInPrologue") then
		warn("[PrologueOrchestrator] Prolog läuft für " .. player.Name .. " bereits -- ignoriere doppelten Start-Aufruf.")
		return
	end

	player:SetAttribute("IsInPrologue", true)
	StoryBeatService.PauseNormalMusic(player) -- ganz am Anfang stoppen, nicht erst bei "DESTROY."
	StoryBeatService.PlayMusic(player, POWER_FANTASY_MUSIC_ID, 0.4) -- Prolog-Musik startet direkt mit dem Prolog, nicht erst bei "DESTROY."
	if _G.SetCityManuallyDriven then
		_G.SetCityManuallyDriven(PROLOGUE_CITY_NAME, true) -- organische Zerstörungs-Beiträge ab jetzt ignorieren, nur noch der Zeit-Treiber bestimmt den Alert-Level
	end
	destroyStartingRuins()
	print("[Kaiju-Debug] Prolog: Start #1 -- IsInPrologue gesetzt, Musik pausiert+gestartet")

	player:LoadCharacter()
	-- WICHTIG: NICHT player.CharacterAdded:Wait() hier -- LoadCharacter() kann das Event
	-- SYNCHRON, noch während des eigenen Aufrufs, feuern. Wait() direkt danach würde das
	-- Event dann bereits verpasst haben und für immer hängen bleiben (klassische Roblox-
	-- Falle). Nach LoadCharacter() ist player.Character bereits gesetzt -- direkter
	-- Zugriff, mit kurzer defensiver Wartezeit als Absicherung für den seltenen Fall,
	-- dass die Zuweisung minimal verzögert ist.
	local character = player.Character
	if not character then
		character = player:WaitForChild("Character", 5)
	end
	print("[Kaiju-Debug] Prolog: Start #2 -- Charakter geladen:", character and character:GetFullName())

	if not character then
		warn("[PrologueOrchestrator] Charakter für " .. player.Name .. " nicht rechtzeitig verfügbar -- Prolog abgebrochen.")
		player:SetAttribute("IsInPrologue", false)
		return
	end

	applyProloguePowerStats(player, character)
	print("[Kaiju-Debug] Prolog: Start #4 -- Power-Stats angewendet")

	-- WICHTIG: applyProloguePowerStats (Skin-Wechsel) kann das Charakter-Modell
	-- austauschen -- dabei wird typischerweise auf die normale Spawn-Position
	-- zurückgesetzt. Deshalb NEU abfragen und ERST DANACH teleportieren, sonst würde der
	-- Teleport durch den Skin-Wechsel wieder rückgängig gemacht.
	character = player.Character or character
	local spawnPartForDebug = findPrologueSpawn()
	print("[Kaiju-Debug] Prolog: PrologueSpawn-Position=" .. tostring(spawnPartForDebug and spawnPartForDebug.Position))
	teleportToPrologueArea(character)
	local rootPartForDebug = character:FindFirstChild("HumanoidRootPart")
	print("[Kaiju-Debug] Prolog: Start #5 -- teleportiert (nach Skin-Wechsel), tatsächliche Position=" .. tostring(rootPartForDebug and rootPartForDebug.Position))

	PrologueReinforcementService.ProtectPlayer(player, PROLOGUE_CITY_NAME)
	print("[Kaiju-Debug] Prolog: Start #6 -- ProtectPlayer aufgerufen, vor playColdOpen (BLOCKIEREND)")

	playColdOpen(player)
	rootPartForDebug = character:FindFirstChild("HumanoidRootPart")
	print("[Kaiju-Debug] Prolog: Start #7 -- playColdOpen fertig, Position jetzt=" .. tostring(rootPartForDebug and rootPartForDebug.Position))

	playIntroCinematic(player, character)
	print("[Kaiju-Debug] Prolog: Start #7b -- Intro-Kinematik fertig")

	-- Tutorial-Checkliste (PUNCH/JUMP/ABSORB je 2x) -- blockiert, bis der Spieler alle
	-- drei Aktionen ausgeführt hat. Löst DANACH erst den nächsten Story-Schritt aus
	-- (DESTROY-Hint + Eskalation).
	playTutorialChecklist(player, character)
	print("[Kaiju-Debug] Prolog: Start #7c -- Tutorial-Checkliste fertig")

	StoryBeatService.PlayAsync(player, { steps = { { type = "hint", text = "DESTROY.", duration = 2.5 } } })
	print("[Kaiju-Debug] Prolog: Start #8 -- DESTROY-Hint gefeuert")

	task.spawn(function()
		driveEscalationByTime(player)
	end)

	watchEscalation(player)
	print("[Kaiju-Debug] Prolog: Start #8 -- watchEscalation fertig (Ende von Start)")
end

-- Öffentlicher Einstiegspunkt: PrologueCity ist ein geteilter Bereich, daher hier die
-- Warteschlangen-Prüfung -- startet sofort, falls frei, sonst wird der Spieler
-- eingereiht und automatisch gestartet, sobald der aktuelle Durchlauf fertig ist (siehe
-- resetPrologueCity/tryStartNextInQueue).
function PrologueOrchestrator.Start(player)
	if prologueOccupiedBy and prologueOccupiedBy.Parent and prologueOccupiedBy ~= player then
		-- Bereits in der Warteschlange? Nicht doppelt einreihen.
		for _, entry in ipairs(prologueQueue) do
			if entry.player == player then
				return
			end
		end

		-- Erstspieler (noch nie HasCompletedPrologue) haben Priorität -- werden VOR allen
		-- Wiederholern eingereiht, aber HINTER bereits wartenden anderen Erstspielern
		-- (fair untereinander, kein Vordrängeln vor Gleichrangige).
		local isFirstTime = player:GetAttribute("HasCompletedPrologue") ~= true
		local insertIndex = #prologueQueue + 1
		if isFirstTime then
			for index, entry in ipairs(prologueQueue) do
				if not entry.isFirstTime then
					insertIndex = index
					break
				end
			end
		end
		table.insert(prologueQueue, insertIndex, { player = player, isFirstTime = isFirstTime })

		print("[PrologueOrchestrator] " .. PROLOGUE_CITY_NAME .. " ist belegt (" .. prologueOccupiedBy.Name .. ") -- " .. player.Name .. " (Erstspieler=" .. tostring(isFirstTime) .. ") in Warteschlange eingereiht (Position " .. insertIndex .. " von " .. #prologueQueue .. ").")
		broadcastQueuePositions()
		return
	end

	prologueOccupiedBy = player
	startPrologueInternal(player)
end

-- Wartender Spieler verlässt den Server: aus der Warteschlange entfernen und die
-- Positionen der übrigen Wartenden neu verschicken.
Players.PlayerRemoving:Connect(function(player)
	for index, entry in ipairs(prologueQueue) do
		if entry.player == player then
			table.remove(prologueQueue, index)
			broadcastQueuePositions()
			break
		end
	end
end)

_G.StartPrologue = PrologueOrchestrator.Start

-- ===== Debug: Prolog manuell starten (unabhängig vom echten Erstspieler-Status) =====
-- Praktisch zum Testen/Iterieren, ohne jedes Mal einen komplett neuen Account/Speicher
-- zu brauchen. Gleiche Berechtigungsprüfung (DebugMode-Attribut) wie die anderen
-- Debug-Werkzeuge im Debug-Panel.
local DebugStartPrologueEvent = RemoteEventUtils.GetOrCreate("DebugStartPrologueEvent")
local DebugStartPrologueResultEvent = RemoteEventUtils.GetOrCreate("DebugStartPrologueResultEvent")
local DEBUG_START_COOLDOWN_SECONDS = 8
DebugStartPrologueEvent.OnServerEvent:Connect(function(player)
	if not player:GetAttribute("DebugMode") then
		DebugStartPrologueResultEvent:FireClient(player, false, "Debug-Modus zuerst aktivieren (Checkbox/Taste V)!")
		return
	end

	-- WICHTIG: Cooldown gegen schnelle Doppel-/Mehrfachklicks (Verteidigung in der Tiefe,
	-- zusätzlich zur Client-seitigen Button-Sperre in DebugPanelClient.lua) -- ein
	-- zweiter Klick kurz nach dem ersten würde sonst den GERADE ERST gestarteten
	-- Durchlauf zurücksetzen und einen ZWEITEN, parallel laufenden Durchlauf starten
	-- (spürbar z.B. als mehrfach abspielendes Ticken).
	local now = os.clock()
	local lastStart = player:GetAttribute("PrologueDebugLastStartAt")
	if lastStart and now - lastStart < DEBUG_START_COOLDOWN_SECONDS then
		DebugStartPrologueResultEvent:FireClient(player, false, "Bitte kurz warten -- läuft schon.")
		return
	end
	player:SetAttribute("PrologueDebugLastStartAt", now)
	DebugStartPrologueResultEvent:FireClient(player, true, nil)

	-- Erzwingt einen frischen Start, selbst wenn IsInPrologue durch einen vorherigen,
	-- unterbrochenen Testlauf noch auf "true" hängen geblieben ist (z.B. weil Play-Test
	-- mitten in der Sequenz gestoppt wurde) -- der Cooldown oben stellt sicher, dass das
	-- NICHT bei einem gerade erst laufenden, echten Durchlauf passiert.
	player:SetAttribute("IsInPrologue", false)
	task.spawn(function()
		PrologueOrchestrator.Start(player)
	end)
end)

return PrologueOrchestrator