-- VERSION: 2026-08-26 #83 -- TEMP DEBUG bleibt drin
-- FEATURE: Militaer-Einheiten, Feuerwehr-Fahrzeuge und Barrikaden werden beim Stadt-Reset jetzt ebenfalls despawnt
-- Ort in Studio: ServerScriptService
--
-- Steuert den Playable Prologue ("The Fall") -- siehe Design-Dokument. Aktuell umgesetzt:
--   Phase 1: Cold Open (Schwarzblende, Ticken, "THE CITY WILL SOON BE BROKEN.")
--   Phase 2: Prolog-Kaiju-Setup (Power-Fantasy-Stats) + Onboarding-Hinweise
--   Phase 3: Eskalation (Stufe 1 am ersten zerstörten Gebäude, danach eine Stufe je
--            ESCALATION_STEP_SECONDS -- siehe dort)
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
-- Der Prolog-Kaiju nutzt einen ECHTEN Skin der Reihe statt eigener,
-- willkürlicher Werte -- vermittelt so die tatsächliche Endgame-Power, die man sich im
-- normalen Spiel erarbeiten würde, statt einer künstlich überhöhten Fantasie-Zahl.
-- ===== Das Modell der zweiten Stufe, die Groesse der fuenften =====
-- Der Prolog ist die Vorschau auf das, was der Spieler wird. Er traegt deshalb den
-- IRONPULSE (Stufe 2 von fuenf, Id 1) -- aber in der Groesse des Aeon Tyrant (Stufe 5,
-- Id 4): 90 Studs statt 45.
--
-- Vorher stand hier der Epochbreaker (Id 2) in seiner eigenen Groesse, 60 Studs.
--
-- Die Leihe laeuft ueber das Spieler-Attribut "ScaleFromSkinId" und von dort durch
-- SkinsConfig.GetScale -- dieselbe Funktion, die Modell, Avatarhoehe und Zonenwechsel
-- bedient. Eine zweite Groessentabelle waere die sichere Art gewesen, dass die beiden
-- irgendwann auseinanderlaufen.
local PROLOGUE_SKIN_ID = 1 -- Ironpulse -- siehe SkinsConfig
local PROLOGUE_SCALE_SKIN_ID = 4 -- Aeon Tyrant: nur seine Groesse, nicht sein Modell
local PROLOGUE_LEVEL = 25
local PROLOGUE_DAMAGE = 2000 -- fester Schaden-Wert (statt Multiplikator auf Adult-Kaiju-Basis-Schaden)

-- Feste Lebenspunkte, nur im Prolog. Der Ironpulse haette von sich aus 200 -- das gehoert
-- zu einer Stufe, die der Spieler hier noch nicht erreicht hat. Der Prolog setzt Schaden
-- und Groesse ohnehin schon eigens; die Lebenspunkte gehoeren in dieselbe Reihe.
--
-- Laeuft ueber das Spieler-Attribut "ForcedMaxHealth", das applySkinToCharacter beachtet.
-- Nachtraeglich am Humanoid gesetzt waere der Wert beim ersten Wiederanziehen wieder weg,
-- und der Prolog zieht mehrfach neu an (Fall, Wiedergeburt, Zonenwechsel).
local PROLOGUE_HEALTH = 1000

-- Wie viel weiter der Flaechenschlag im Prolog reicht. Gilt ueber ein Attribut AM SPIELER,
-- trifft also niemanden sonst auf dem Server, und wird in Phase 7 wieder entfernt.
local PROLOGUE_AREA_RADIUS_FACTOR = 2

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

-- Wie lange der Sturz des Kaiju dauert, bevor die Kamera hinfährt.
--
-- Die Zahl ist nicht gegriffen, sondern aus der DefeatAnimation abgelesen
-- (KaijuPresentation.updateDefeat): Einknicken bis 0,45 s, Fallen von 0,25 bis 1,8 s,
-- Setzen von 1,8 bis 2,6 s. Bei 2,6 Sekunden liegt die Figur. Was danach noch läuft --
-- das Erlöschen der Neonflächen und das letzte Flackern der Augen bis 4,8 s -- braucht
-- nicht abgewartet zu werden, im Gegenteil: es soll während der Kamerafahrt geschehen.
--
-- Ändert sich die Animation im Workshop-Submodul, gehört diese Zahl nachgezogen. Zu kurz
-- heisst: die Kamera fährt los, während die Figur noch fällt.
local DEFEAT_ANIMATION_SECONDS = 2.8

-- ===== Phase 3: Zeitbasierte Eskalation =====
-- Der Alert-Level im Prolog steigt nach VERSTRICHENER ZEIT, nicht nach tatsächlich
-- angerichtetem Zerstörungs-Schaden. driveEscalationByTime setzt den Fortschritt aktiv auf
-- den zum jeweiligen Zeitpunkt passenden Wert -- so bleibt die Eskalation exakt nach Plan,
-- selbst wenn der Spieler nebenbei viele Gebäude zerstört (was normalerweise ebenfalls
-- Alert-Fortschritt geben würde).
--
-- ===== Woran die Uhr hängt (21.09.2026) =====
-- Vorher lief sie ab dem Ende der Tutorial-Checkliste und mit ungleichen Abständen
-- (0 / 18.75 / 27.5 / 37.5 / 50). Beides ist jetzt anders:
--
--   * Stufe 1 kommt, sobald das ERSTE Gebäude der Prologstadt fällt -- nicht vorher. Bis
--     dahin steht die Stadt auf Stufe 0. Damit hat der Spieler die Eskalation selbst
--     ausgelöst, statt dass sie ihm nebenher zuläuft.
--   * Danach eine Stufe je ESCALATION_STEP_SECONDS, gleichmässig. Gleiche Abstände sind
--     die Voraussetzung dafür, dass der Takt überhaupt als Takt wahrgenommen wird.
--
-- Das verlängert Phase 3 gegenüber vorher: Stufe 5 (und damit der Guardian) kommt nach
-- vier Schritten statt nach 50 Sekunden.
local ESCALATION_STEP_SECONDS = 20
local ESCALATION_MAX_LEVEL = 5

-- Notbremse: zerstört der Spieler nach dem DESTROY-Hinweis überhaupt nichts, gäbe es ohne
-- diese Frist keinen Auslöser für Stufe 1 -- der Prolog bliebe für immer auf Stufe 0
-- stehen, ohne Fehler und ohne Hinweis. Nach dieser Zeit läuft der Takt auch ohne das
-- erste Gebäude an.
local FIRST_BUILDING_GRACE_SECONDS = 60

local function findPrologueSpawn()
	local prologueFolder = Workspace:FindFirstChild("Prologue")
	local inFolder = prologueFolder and prologueFolder:FindFirstChild("PrologueSpawn")
	return inFolder or Workspace:FindFirstChild("PrologueSpawn")
end

-- Setzt den Charakter auf die Power-Fantasy-Werte -- überschreibt bewusst die normalen,
-- Setzt den Charakter auf den Prolog-Skin (Rift Stalker) + Prolog-Level -- läuft
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

	-- VOR ApplySkinToCharacter: die Leihe muss stehen, bevor Modell und Avatarhoehe
	-- berechnet werden -- danach gesetzt bliebe die Figur bis zum naechsten Anlass klein.
	player:SetAttribute("ScaleFromSkinId", PROLOGUE_SCALE_SKIN_ID)
	player:SetAttribute("ForcedMaxHealth", PROLOGUE_HEALTH)

	-- Das Modell bleibt beim Tod an der Figur. Der Fall im Prolog ist die Szene, nicht ein
	-- Unfall -- er wird eigens geskriptet (siehe "The Fall" weiter unten). Ohne das nimmt
	-- KaijuStageOneService beim Tod ab, und das gesamte Kippen liefe am blanken Avatar ab.
	player:SetAttribute("KeepModelOnDeath", true)

	-- Doppelter Flaechenradius -- nur fuer diesen Spieler, nur im Prolog. Der Prolog zeigt
	-- eine Figur auf einem Stand, den der Spieler noch nicht hat; der Flaechenschlag soll
	-- entsprechend weit reichen. Siehe getAreaAttackRadius im SpecialAttackHandler.
	player:SetAttribute("AreaRadiusFactor", PROLOGUE_AREA_RADIUS_FACTOR)

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

-- ===== Vor jedem Sprung das Ziel laden lassen =====
-- Mit StreamingEnabled kennt ein Client nur die Umgebung, in der er gerade steht. Ein
-- PivotTo in einen Bereich, der bei ihm noch nicht angekommen ist, lässt die Engine die
-- Simulation anhalten und blendet "Gameplay Paused" ein.
--
-- Diese Meldung gehört der CoreGui und liegt damit ÜBER unseren Oberflächen -- auch über
-- der Schwarzblende. Sie durch eine längere schwarze Strecke zu verdecken, geht deshalb
-- nicht; verhindert werden kann nur die Pause selbst.
--
-- RequestStreamAroundAsync bittet den Server, genau diesen Bereich vorab an den Client zu
-- schicken, und wartet darauf. Danach ist der Sprung für ihn kein Sprung ins Leere mehr.
local STREAM_VORLADE_TIMEOUT = 5

local function streameZielVor(player, position, anlass)
	local start = os.clock()
	local ok, err = pcall(function()
		player:RequestStreamAroundAsync(position, STREAM_VORLADE_TIMEOUT)
	end)
	if ok then
		print(string.format("[Kaiju-Debug] Prolog: Bereich um '%s' vorgeladen (%.2fs).",
			anlass, os.clock() - start))
	else
		-- Nicht abbrechen: ohne Vorladen springt er wie bisher, nur eben mit der Meldung.
		-- Die Warnung nennt den Grund, damit ein Fehlschlag nicht still bleibt.
		warn(string.format(
			"[PrologueOrchestrator] Vorladen für '%s' fehlgeschlagen (%s) -- der Sprung kann "
				.. "'Gameplay Paused' zeigen.", anlass, tostring(err)))
	end
end

local function teleportToPrologueArea(player, character)
	local spawnPart = findPrologueSpawn()
	if not spawnPart then
		warn("[PrologueOrchestrator] Workspace.PrologueSpawn nicht gefunden -- Prolog-Kaiju bleibt an der normalen Spawn-Position stehen.")
		return
	end
	local ziel = spawnPart.CFrame + Vector3.new(0, 5, 0)
	streameZielVor(player, ziel.Position, "PrologueSpawn")
	character:PivotTo(ziel)
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

-- ===== Regie-Ziele für den Fokusstrahl =====
-- Im Prolog bestimmt die Regie, worauf der Kaiju den Strahl richtet und in welcher
-- Reihenfolge. Dafür trägt jedes Ziel in Studio das Attribut "PrologueTarget" mit einer
-- Zahl: 1 zuerst, dann 2, dann 3. Die Zahlen müssen nicht lückenlos sein -- sortiert wird
-- nach ihrem Wert, nicht nach ihrem Abstand.
--
-- Gesucht wird über die ganze Workspace statt nur in der Prolog-Stadt: das Attribut ist
-- eine Regie-Anweisung und soll dort gesetzt werden können, wo das Ziel eben steht, ohne
-- dass jemand die Ordnerstruktur kennen muss. Ein Durchlauf beim Prologstart.
local function findPrologueFocusTargets()
	local houseTag = _G.HOUSE_TAG or "KaijuHouse"
	local funde = {}
	for _, instance in ipairs(Workspace:GetDescendants()) do
		local nummer = instance:GetAttribute("PrologueTarget")
		if typeof(nummer) == "number" then
			table.insert(funde, { nummer = nummer, instance = instance })
		end
	end
	table.sort(funde, function(a, b)
		return a.nummer < b.nummer
	end)

	local ziele = {}
	for _, fund in ipairs(funde) do
		-- Der Strahl richtet echten Schaden an, und der läuft über _G.DamageHouse. Ohne
		-- den Haus-Tag bekäme das Ziel den Strahl zu sehen, aber keinen Schaden -- ein
		-- Fehler, der im Spiel aussieht wie "der Laser tut nichts". Deshalb hier melden,
		-- statt ihn still zu schlucken.
		if CollectionService:HasTag(fund.instance, houseTag) then
			table.insert(ziele, fund.instance)
			print(string.format("[Kaiju-Debug] Prolog-Fokusziel %d: %s",
				fund.nummer, fund.instance:GetFullName()))
		else
			warn(string.format(
				"[PrologueOrchestrator] PrologueTarget %d an '%s' wird übersprungen -- die Instanz "
					.. "trägt den Tag '%s' nicht und könnte deshalb keinen Fokusschaden nehmen.",
				fund.nummer, fund.instance:GetFullName(), houseTag))
		end
	end
	if #ziele == 0 then
		print("[Kaiju-Debug] Prolog: kein Ziel mit Attribut 'PrologueTarget' gefunden "
			.. "-- der Fokusstrahl nimmt wie bisher den Leuchtturm.")
	end
	return ziele
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

	-- Die Regie-Ziele bestimmen, wie lang die Kampfsequenz wird -- deshalb VOR der
	-- Flugdauer der Kamera, die sich daran ausrichtet.
	local focusTargets = findPrologueFocusTargets()

	-- WICHTIG zum Timing: die echten Cooldowns sind ATTACK_COOLDOWN=0.8s (Punch),
	-- FOCUS_ATTACK_COOLDOWN=1s, AREA_ATTACK_COOLDOWN=1.5s (siehe CombatHandler.lua/
	-- SpecialAttackHandler.lua) -- ein zu kurzer Abstand zwischen zwei Aktionen würde vom
	-- echten System stillschweigend ignoriert (wie ein zu schneller Doppelklick). Die
	-- Pause zwischen Aktionen ist daher auf mindestens 0.85s festgelegt (knapp über dem
	-- strengsten Cooldown zwischen zwei AUFEINANDERFOLGENDEN Aktionen DESSELBEN Typs).
	local ACTION_GAP = 0.85

	-- Die Sequenz besteht aus Blöcken "3x Punch + 1 Spezialaktion". Die Spezialaktionen
	-- sind der Reihe nach: Sprung, EIN FOKUSSTRAHL JE REGIE-ZIEL, Sprung, Flächenschaden.
	-- Bei einem Ziel ergibt das genau die 16 Aktionen, die hier vorher fest standen.
	-- Ohne Regie-Ziel bleibt es bei einem Strahl auf den Leuchtturm, also ebenfalls 16.
	local focusCount = math.max(#focusTargets, 1)
	local TOTAL_ACTIONS = 4 * (3 + focusCount)
	local combatDuration = (TOTAL_ACTIONS - 1) * ACTION_GAP

	local CAMERA_ALIGN_DURATION = 0.8 -- dient nur noch als Mindest-Puffer für combatStartDelay unten (die eigentliche Align-Phase im Client gibt es nicht mehr)
	-- 13 Sekunden sind der eingestellte Wert für EIN Fokusziel. Jedes weitere Ziel hängt
	-- einen Block von vier Aktionen an die Sequenz; wüchse die Kamera nicht mit, käme sie
	-- an, während der Kaiju noch geskriptet weiterschlägt -- der Spieler bekäme die
	-- Kontrolle mitten in die Inszenierung zurück.
	local CAMERA_FLY_DURATION = 13 + (focusCount - 1) * 4 * ACTION_GAP

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
	-- Cooldown-Prüfung. Der Aufbau der Sequenz steht oben bei TOTAL_ACTIONS. Der Charakter
	-- läuft dabei kontinuierlich auf ein selbst gewähltes Ziel (den Leuchtturm) zu.
	local combatStartDelay = math.max(CAMERA_FLY_DURATION - combatDuration, CAMERA_ALIGN_DURATION)
	print(string.format(
		"[Kaiju-Debug] Kampfsequenz-Timing: %d Fokusziele, %d Aktionen, combatDuration=%.2f "
			.. "combatStartDelay=%.2f Kameraflug=%.2f",
		#focusTargets, TOTAL_ACTIONS, combatDuration, combatStartDelay, CAMERA_FLY_DURATION))

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
			-- WAAGERECHT ausrichten -- wie faceTowards darüber, nur Gieren, kein Nicken.
			--
			-- Hier stand als Blickziel targetPosition SELBST. Die Richtung des Schritts war
			-- zwar flach gerechnet, das Blickziel aber nicht: die Figur neigte sich um den
			-- Höhenunterschied zum Ziel. Solange sie Spielergrösse hatte, lagen Rumpf und
			-- Gebäudemitte ungefähr gleich hoch und es fiel nicht auf. Seit die Figur die
			-- Höhe ihres Modells hat, schwebt HumanoidRootPart auf Hüfthöhe -- beim
			-- Prolog-Kaiju rund 45 Studs -- und sie schaute steil nach UNTEN auf den
			-- Leuchtturm. Je näher sie kam, desto steiler, bis fast in die Waagerechte.
			-- Und weil doPunch nach JEDEM Schlag hierher zurückkommt, richtete sie sich
			-- dazwischen nie wieder auf.
			--
			-- Das Blickziel ist deshalb die neue Position plus die FLACHE Richtung.
			local newPosition = rootPart.Position + direction * WALK_STEP_DISTANCE
			character:PivotTo(CFrame.lookAt(newPosition, newPosition + direction))
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

		local function doFocusDamage(ziel)
			if ziel then
				local zielTeil = ziel:IsA("Model") and ziel.PrimaryPart
					or (ziel:IsA("BasePart") and ziel or nil)
				if zielTeil then
					faceTowards(zielTeil.Position)
				end
				-- Drehen allein genügt NICHT: die Kegelsuche in findFocusTarget nimmt das
				-- nächste Haus im Kegel und begrenzt auf FOCUS_ATTACK_RANGE. Steht ein
				-- anderes Gebäude davor oder ist das Ziel weiter weg, ginge der Strahl
				-- woandershin. Deshalb wird das Ziel für genau diesen einen Strahl gesetzt.
				if _G.SetForcedFocusTarget then
					_G.SetForcedFocusTarget(player, ziel)
				end
				print("[Kaiju-Debug] Kampfsequenz: Fokusstrahl auf " .. ziel:GetFullName())
			elseif leuchtturm then
				-- Rückfall ohne Regie-Ziel: wie bisher zum Leuchtturm drehen und die
				-- normale Zielsuche entscheiden lassen.
				faceTowards(leuchtturm.Position)
			else
				faceNearestHouse()
			end
			SimulatePrologueActionEvent:FireClient(player, "Focus")
		end

		task.wait(combatStartDelay)

		-- Sequenz: Blöcke aus 3x Punch + 1 Spezialaktion. Die Spezialaktionen der Reihe
		-- nach: Sprung, ein Fokusstrahl je Regie-Ziel (PrologueTarget), Sprung,
		-- Flächenschaden. Endet, wenn die Kamera bei der letzten PrologueCameraSpawn-
		-- Station ankommt -- combatStartDelay und CAMERA_FLY_DURATION weiter oben rechnen
		-- mit derselben Zahl von Aktionen (TOTAL_ACTIONS).
		local function dreiSchlaege()
			for _ = 1, 3 do
				doPunch()
				task.wait(ACTION_GAP)
			end
		end

		dreiSchlaege()
		doJump()
		task.wait(ACTION_GAP)

		-- Ein Strahl je Ziel, in der Reihenfolge der PrologueTarget-Nummern. Ohne Ziele
		-- bleibt focusCount bei 1, focusTargets[1] ist nil -- doFocusDamage fällt dann auf
		-- den Leuchtturm zurück, also genau das bisherige Verhalten.
		for index = 1, focusCount do
			dreiSchlaege()
			doFocusDamage(focusTargets[index])
			task.wait(ACTION_GAP)
		end

		dreiSchlaege()
		doJump()
		task.wait(ACTION_GAP)

		dreiSchlaege()
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

-- ===== Der Vorspann =====
-- Er steht ganz vorn, auf der Schwarzblende, bevor das Ticken einsetzt und lange vor
-- "THE CITY WILL SOON BE BROKEN." -- also in dem Fenster, in dem man bisher nur die
-- Explosionen der Stadt hörte und nichts sah.
--
-- Der Klang läuft dabei weiter: der Vorspann steht auf einem schwarzen Bild, unter dem
-- die Stadt schon brennt. Genau das macht ihn -- eine ruhige Zeile über einem Geräusch,
-- das nichts Ruhiges hat.
--
-- Die Sperrung des Untertitels steht als Leerzeichen im Text. Roblox kennt keine
-- Laufweite, und "PRESENTS" ohne Sperrung sieht neben dem grossen Namen gedrungen aus.
local PRESENTER_NAME = "Amaux Bozé"
local PRESENTER_SUB = "P R E S E N T S"

local function playColdOpen(player)
	local partOneSteps = { { type = "fadeIn", duration = 0.1 } } -- startet bereits schwarz, minimal für sauberen Übergang

	-- ===== Der Vorspann LIEGT über dem Ticken, er kommt nicht davor =====
	-- Die Karte dauert 4.4 Sekunden (1.4 einblenden, 1.8 halten, 1.2 ausblenden) und hielt
	-- die Sequenz so lange an. Danach folgten 7.5 weitere Sekunden, in denen der Bildschirm
	-- schwarz war und nur die Uhr tickte und die Sirene lief -- der Vorspann verlängerte den
	-- Start also um Zeit, von der reichlich ungenutzt danebenlag.
	--
	-- Mit "parallel" läuft er mit, statt aufzuhalten: der Start ist 4.4 Sekunden kürzer, und
	-- die schwarze Strecke zeigt jetzt etwas. Das Ticken unter dem Namen ist dabei kein
	-- Zufall, sondern passt: eine Uhrenmarke, zu der eine Uhr schlägt.
	table.insert(partOneSteps, {
		type = "presenterCard",
		name = PRESENTER_NAME,
		sub = PRESENTER_SUB,
		parallel = true,
	})
	-- Ein Atemzug, bevor das Ticken einsetzt -- jetzt liegt er im Einblenden der Karte und
	-- kostet nichts extra. Der Name steht damit einen Moment allein, bevor die Uhr einsetzt.
	table.insert(partOneSteps, { type = "wait", duration = 0.6 })

	for _, step in ipairs(buildTickSteps(3, 0.7)) do
		table.insert(partOneSteps, step)
	end

	-- ===== Der Abschluss-Atemzug liegt HINTER dem Sirenenstart =====
	-- Er stand als letzter Schritt IN der Sequenz, und die Sirene begann erst danach. Jetzt
	-- wandert er heraus (siehe unten): die Sirene setzt an seinem Anfang ein statt an
	-- seinem Ende und laeuft damit genau SIRENE_VORLAUF Sekunden frueher.
	--
	-- Diese Konstruktion statt eines Countdowns ab Sequenzbeginn: die Laenge des Vorspanns
	-- haengt an den Tick-Toenen, und deren Dauer kennt der Server nicht. Ein gezaehlter
	-- Vorlauf waere geraten gewesen und beim naechsten Ton falsch.
	local SIRENE_VORLAUF = 0.8

	StoryBeatService.Play(player, { steps = partOneSteps, keepBlackScreen = true })

	-- Sirene läuft über den eigenständigen Sound-Kanal (siehe StoryBeatService.PlaySiren)
	-- -- NICHT als "sound"-Schritt innerhalb der Sequenz, da diese sonst beim
	-- Sequenz-Ende automatisch gestoppt würde (stopAllSounds) und beim erneuten Start in
	-- Teil 2 hörbar doppelt gestartet hätte. So läuft sie nahtlos über beide Teile.
	--
	-- Sie beginnt SIRENE_VORLAUF frueher als frueher: der Atemzug, der bis zum 22.09.2026
	-- der letzte Schritt der Sequenz war, liegt jetzt dahinter. Ein erster Versuch hatte
	-- sie viereinhalb Sekunden vorgezogen, mitten ins Uhrticken -- das war zu viel
	-- ("Der Sound mit den Alarmsirenen ist nun zu lange").
	StoryBeatService.PlaySiren(player, SIREN_SOUND_ID, 0.5)

	task.wait(SIRENE_VORLAUF)

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

-- ===== Das erste zerstörte Gebäude =====
-- Es ist der Auslöser für Alarmstufe 1 (siehe ESCALATION_STEP_SECONDS). Gehorcht wird
-- demselben Muster wie beim Absorb-Tracker weiter unten: ein dauerhafter, idempotenter
-- Hook, davor eine Anmeldung je Durchlauf.
--
-- Warum ein Hook und nicht das Alert-System selbst: PrologueCity läuft als "manuell
-- gesteuerte" Stadt (siehe _G.SetCityManuallyDriven), und genau deshalb verwirft
-- CityAlertService organische Beiträge dort. Die Zerstörung kommt also im Alert-System gar
-- nicht mehr an -- wohl aber an dieser Funktion, die HouseHandler bei JEDER Zerstörung
-- ruft, bevor die Stadt geprüft wird.
--
-- Angemeldet wird schon VOR der Tutorial-Checkliste: wer dabei ein Gebäude umlegt, hat es
-- umgelegt, und die Eskalation gehört ab diesem Augenblick in Gang -- auch wenn das
-- Tutorial noch läuft.
local firstBuildingWatchers = {} -- [player] = true, solange auf das erste Gebäude gewartet wird
local firstBuildingDestroyedAt = {} -- [player] = os.clock() des ersten Gebäudes
local buildingHookInstalled = false

local function installBuildingHookOnce()
	if buildingHookInstalled then
		return
	end
	buildingHookInstalled = true
	local originalAddCityAlertForBuilding = _G.AddCityAlertForBuilding
	_G.AddCityAlertForBuilding = function(house)
		-- Zuerst weiterreichen, unverändert: für jede andere Stadt ist dieser Aufruf der
		-- normale Weg, auf dem Zerstörung zu Alarm wird.
		if originalAddCityAlertForBuilding then
			originalAddCityAlertForBuilding(house)
		end

		if not _G.ResolveCityName or _G.ResolveCityName(house) ~= PROLOGUE_CITY_NAME then
			return
		end
		for watchingPlayer in pairs(firstBuildingWatchers) do
			if not firstBuildingDestroyedAt[watchingPlayer] then
				firstBuildingDestroyedAt[watchingPlayer] = os.clock()
				print(string.format(
					"[Kaiju-Debug] Prolog: erstes Gebaeude gefallen (%s) -- Alarmstufe 1, der %d-Sekunden-Takt laeuft.",
					house:GetFullName(), ESCALATION_STEP_SECONDS))
			end
		end
	end
end

-- Meldet diesen Durchlauf an. Ab jetzt zählt das nächste zerstörte Gebäude.
local function armFirstBuildingWatch(player)
	installBuildingHookOnce()
	firstBuildingDestroyedAt[player] = nil
	firstBuildingWatchers[player] = true
end

local function disarmFirstBuildingWatch(player)
	firstBuildingWatchers[player] = nil
	firstBuildingDestroyedAt[player] = nil
end

-- ===== Phase 2: Power Fantasy + Onboarding =====
-- Tutorial-Checkliste: PUNCH x2, JUMP x2, ABSORB (Mengen-Schwelle) -- zeigt ein Panel
-- beim Spieler, verfolgt die Aktionen server-seitig (zuverlässiger als rein client-
-- seitiges Tracking, da der Server die entsprechenden Events ohnehin bereits empfängt),
-- aktualisiert die Anzeige live.
local TUTORIAL_TARGETS = { Punch = 2, Jump = 2, AbsorbAmount = 5000 }

-- Wie lange der Spieler höchstens für die Checkliste bekommt. Wer früher fertig ist, geht
-- früher weiter -- das hier ist die Obergrenze, kein Mindestaufenthalt.
--
-- Vorher standen hier 120 Sekunden, gedacht als reine Notbremse gegen ein Hängenbleiben.
-- Als Frist gelesen war das keine: zwei Minuten setzen niemanden unter Druck. Der Prolog
-- soll aber von der ersten Minute an drängen, deshalb dieselbe Länge wie eine Alarmstufe.
local TUTORIAL_TIME_LIMIT_SECONDS = 20

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

	-- ===== Punch =====
	--
	-- Es gibt inzwischen ZWEI Wege, auf denen ein Schlag beim Server ankommt:
	--
	--   AttackEvent            der bisherige Weg
	--   <Modell>.RequestAttack der Weg der Buehnenmodelle -- AttackClient schickt den
	--                          Schlag dorthin, SOBALD das getragene Modell diesen Remote
	--                          mitbringt, und feuert AttackEvent dann gar nicht mehr
	--
	-- Das Tutorial hing nur am ersten. Sobald ein Modell mit eigenem Remote getragen wird,
	-- zaehlte kein einziger Schlag mehr -- die Checkliste blieb bei 0 stehen und der Prolog
	-- lief in seine 120-Sekunden-Notbremse.
	--
	-- Deshalb hier BEIDE Quellen. Der Remote wird im Charakter gesucht statt ueber das
	-- Buehnenmodell-Modul: so haengt der Prolog nicht daran, wie jenes Modul gerade heisst
	-- oder aufgebaut ist.
	local function zaehlePunch(attackingPlayer)
		if attackingPlayer == player and progress.Punch < TUTORIAL_TARGETS.Punch then
			progress.Punch += 1
			sendUpdate()
			checkComplete()
		end
	end

	table.insert(connections, TutorialAttackEvent.OnServerEvent:Connect(zaehlePunch))

	-- Die Anfrage-Ereignisse des Kaiju-Modells. Sie entstehen ERST, wenn der
	-- KaijuStageOneService das Modell angezogen hat -- das geschieht nach dem Charakter und
	-- bei jedem Stufenwechsel erneut.
	--
	-- Deshalb wird nicht nur einmal gesucht, sondern auch auf spaeter Hinzukommendes
	-- gehoert. Vorher stand hier eine halbe Sekunde Wartezeit und eine einmalige Suche --
	-- ein Rennen, das man verliert, sobald das Modell etwas laenger braucht.
	local function lauscheAufModellAnfrage(aktuellerCharakter, remoteName, handler)
		if not aktuellerCharakter then
			return
		end
		local function pruefe(nachfahre)
			if nachfahre:IsA("RemoteEvent") and nachfahre.Name == remoteName then
				table.insert(connections, nachfahre.OnServerEvent:Connect(handler))
			end
		end
		for _, nachfahre in ipairs(aktuellerCharakter:GetDescendants()) do
			pruefe(nachfahre)
		end
		table.insert(connections, aktuellerCharakter.DescendantAdded:Connect(pruefe))
	end

	-- ===== Sprung =====
	--
	-- ZWEI Wege, weil es zwei Arten zu springen gibt.
	--
	-- Ohne Kaiju-Modell springt die Figur normal, und der Humanoid wechselt in den Zustand
	-- "Jumping". Mit Modell nicht: der Installer setzt JumpPower auf 0 und schaltet
	-- AutoJumpEnabled ab, weil das Rig einen eigenen Sprung mitbringt. Der Humanoid meldet
	-- dann gar nichts mehr, und der Sprung im Prolog wurde nie gezaehlt.
	--
	-- Der zweite Weg ist deshalb das RequestJump-Ereignis des Modells -- dieselbe Loesung
	-- wie beim Schlag, der ueber AttackEvent UND RequestAttack zaehlt.
	--
	-- Die Sperre von 0.2 Sekunden faengt den Fall ab, dass beide Wege denselben Sprung
	-- melden. Sonst waere das Tutorial nach einem einzigen Tastendruck erfuellt.
	local letzterSprungAt = 0

	local function zaehleSprung()
		local jetzt = os.clock()
		if jetzt - letzterSprungAt < 0.2 then
			return
		end
		letzterSprungAt = jetzt
		if progress.Jump >= TUTORIAL_TARGETS.Jump then
			return
		end
		progress.Jump += 1
		sendUpdate()
		checkComplete()
	end

	-- Die Humanoid-Verbindung haengt an GENAU DIESEM Humanoid. Wird der Charakter waehrend
	-- des Tutorials ersetzt -- und das tun Skin- und Modellwechsel -- zeigt sie auf eine
	-- Leiche und zaehlt nie wieder. Deshalb wird sie bei jedem neuen Charakter neu gelegt.
	local function lauscheAufSprung(aktuellerHumanoid)
		if not aktuellerHumanoid then
			return
		end
		table.insert(connections, aktuellerHumanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Jumping then
				zaehleSprung()
			end
		end))
	end

	local function lauscheAufCharakter(aktuellerCharakter, aktuellerHumanoid)
		lauscheAufSprung(aktuellerHumanoid)
		lauscheAufModellAnfrage(aktuellerCharakter, "RequestAttack", zaehlePunch)
		lauscheAufModellAnfrage(aktuellerCharakter, "RequestJump", zaehleSprung)
	end

	lauscheAufCharakter(character, humanoid)

	table.insert(connections, player.CharacterAdded:Connect(function(neuerCharakter)
		local neuerHumanoid = neuerCharakter:WaitForChild("Humanoid", 5)
		lauscheAufCharakter(neuerCharakter, neuerHumanoid)
	end))

	print("[Kaiju Debug] Tutorial-Checkliste scharf: Punch ueber AttackEvent und RequestAttack, "
		.. "Sprung ueber den Humanoid und RequestJump.")

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

	-- Blockiert, bis alle Ziele erreicht sind -- längstens aber TUTORIAL_TIME_LIMIT_SECONDS.
	-- Danach geht es weiter, erledigt oder nicht: die Checkliste ist eine Einführung, keine
	-- Prüfung, und ein Prolog, der auf eine nie ausgeführte Aktion wartet, bleibt stehen.
	local waited = 0
	while not completed and player.Parent and waited < TUTORIAL_TIME_LIMIT_SECONDS do
		task.wait(0.2)
		waited += 0.2
	end

	activeAbsorbTrackers[player] = nil
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	if completed then
		print(string.format("[Kaiju-Debug] Prolog: Tutorial-Checkliste erledigt nach %.1f s.", waited))
	else
		print(string.format(
			"[Kaiju-Debug] Prolog: Tutorial-Zeit (%d s) abgelaufen -- offen: Punch %d/%d, Sprung %d/%d, Absorb %d/%d. Es geht trotzdem weiter.",
			TUTORIAL_TIME_LIMIT_SECONDS,
			progress.Punch, TUTORIAL_TARGETS.Punch,
			progress.Jump, TUTORIAL_TARGETS.Jump,
			progress.AbsorbAmount, TUTORIAL_TARGETS.AbsorbAmount))
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

	-- ===== Wohin die Kamera schaut =====
	-- Hier stand die Position des "Head"-Teils. Das traf, solange der Prolog den ganzen
	-- Charakter selbst um 80 Grad kippte: der versteckte Avatar kippte mit, sein Kopf landete
	-- ungefähr dort, wo man den Kaiju-Kopf sah.
	--
	-- Seit die DefeatAnimation des Rigs den Fall macht (siehe triggerTheFall), stimmt das
	-- nicht mehr. Die Animation setzt die Gelenke in der DARSTELLUNG; der Avatar darunter
	-- bleibt aufrecht stehen, wo er stand. Sein Kopf zeigt also auf die Stelle, an der die
	-- Figur VOR dem Fall stand -- die Kamera würde ins Leere zoomen.
	--
	-- Geschätzt wird stattdessen, wo der Kopf zu liegen kommt: der Kaiju fällt nach vorn, der
	-- Kopf landet rund eine halbe Körperlänge vor ihm. Der Boden wird dafür gemessen und
	-- nicht angenommen -- dieselbe Vorsicht, mit der das Rig seine eigene Fallhöhe bestimmt.
	local lookDirection = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	lookDirection = lookDirection.Magnitude > 0.01 and lookDirection.Unit or Vector3.new(0, 0, -1)

	local _, characterSize = character:GetBoundingBox()
	local aheadPosition = rootPart.Position + lookDirection * (characterSize.Y * 0.5)

	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { character }
	local groundHit = Workspace:Raycast(
		aheadPosition + Vector3.new(0, characterSize.Y, 0),
		Vector3.new(0, -characterSize.Y * 4, 0),
		groundParams
	)
	local groundY = groundHit and groundHit.Position.Y or (rootPart.Position.Y - characterSize.Y * 0.5)

	-- Etwas über dem Boden: der liegende Kopf hat ja selbst noch Höhe.
	local headPos = Vector3.new(aheadPosition.X, groundY + characterSize.Y * 0.12, aheadPosition.Z)
	print(string.format("[Kaiju-Debug] The Fall: Kamera zielt auf %s (Boden %.1f, Figurenhoehe %.1f).",
		tostring(headPos), groundY, characterSize.Y))
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

	-- Ab hier führt der Prolog die Kamera. Seit der Showdown im Prolog erlaubt ist, kann
	-- beim Guardian-Auftritt einer laufen -- der hätte seine eigene Kamera. Zwei
	-- Kamerasysteme gegeneinander sind genau der Fehler, vor dem CLAUDE.md warnt, deshalb
	-- wird er beendet, BEVOR die erste Einstellung von "The Fall" steht. Das Attribut oben
	-- verhindert zugleich, dass währenddessen ein neuer beginnt (ShowdownService.isBlocked).
	if _G.EndShowdown then
		_G.EndShowdown(player, "Prolog-Sturz beginnt")
	end

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

	-- ===== Letzter Treffer -- der Kaiju fällt =====
	--
	-- BreakJointsOnDeath bleibt deaktiviert: Roblox würde bei Health=0 sonst ein Ragdoll
	-- auslösen (Gelenke lösen sich, einzelne Körperteile werden physikalisch simuliert), und
	-- bei einem so grossen, skalierten Rig endete das im Boden.
	--
	-- ===== Den Fall macht das Rig, nicht dieses Skript (21.09.2026) =====
	-- Hier stand bis dahin eine Eigenkonstruktion: PlatformStand, alle Teile verankern, und
	-- dann 1,2 Sekunden lang jeden Frame ein PivotTo, das den ganzen Charakter um 80 Grad
	-- nach vorn kippte. Das hatte zwei Fehler, die dieselbe Wurzel haben.
	--
	-- Erstens lief die DefeatAnimation des Rigs die ganze Zeit MIT -- sie hängt an
	-- HealthChanged mit Health <= 0, also an der Zeile direkt darunter, und wurde von dem
	-- Kipp-Loop nur überlagert. Zwei Fassungen desselben Sturzes übereinander.
	--
	-- Zweitens rechnete der Kipp-Loop rein relativ zur Ausgangspose und fragte den Boden nie
	-- ab -- der Kaiju blieb in der Luft liegen, wo immer er gerade stand. Die Animation des
	-- Rigs misst ihn dagegen (KaijuStageOneRig: Raycast nach defeat.Ground) und zieht ihre
	-- tiefste Stelle darauf.
	--
	-- Also beides raus. Was hier bleibt, ist der Auslöser und das Warten.
	humanoid.BreakJointsOnDeath = false
	humanoid.Health = 0

	-- Das Rig übernimmt ab hier selbst: es hält den Humanoid an, verankert die
	-- HumanoidRootPart und meldet den Fall an die Darstellung. Hier ist nichts mehr zu tun,
	-- ausser ihn zu Ende laufen zu lassen, bevor die Kamera hinfährt.
	print("[Kaiju-Debug] The Fall: Health=0 gesetzt -- die DefeatAnimation des Rigs laeuft jetzt.")
	task.wait(DEFEAT_ANIMATION_SECONDS)

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
		equippedSkin.Value = 0 -- kleinster Skin ("Primal Beast", Id 0 in SkinsConfig.lua)
	end

	-- Die geliehene Groesse des Prologs endet HIER. Bliebe sie stehen, liefe der Spieler
	-- den Rest des Spiels als 90 Studs hoher Riftborn herum -- und zwar lautlos, weil
	-- Modell und Avatar beide derselben Leihe folgen und deshalb zueinander passen wuerden.
	-- Genau das macht es gefaehrlich: es saehe nicht kaputt aus, nur falsch.
	player:SetAttribute("ScaleFromSkinId", nil)

	-- Ebenso die festen Lebenspunkte: ab hier gilt wieder, was zur Stufe gehoert -- beim
	-- Riftborn also 100. Bliebe der Wert stehen, startete der Spieler das eigentliche
	-- Spiel mit dem Zehnfachen und merkte es nie, weil nichts daran falsch aussieht.
	player:SetAttribute("ForcedMaxHealth", nil)

	-- Und die Ausnahme beim Tod. Ab hier gilt wieder die Regel: ein toter Kaiju, dessen
	-- Modell haengenbliebe, laege sonst im Boden, bis die Leiche verschwindet.
	player:SetAttribute("KeepModelOnDeath", nil)

	-- Und der Flaechenradius zurueck auf normal. Ohne das nimmt der Spieler die doppelte
	-- Reichweite ins ganze Spiel mit -- und zwar unsichtbar, weil der Schlag damit nicht
	-- anders AUSSIEHT, nur weiter trifft.
	player:SetAttribute("AreaRadiusFactor", nil)

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

	-- ===== Ab hier zeigt der Bildschirm nur noch Text =====
	-- Bis hierher blieb die Lebensanzeige stehen -- im Fall ist sie der Inhalt der Szene.
	-- Die Abschlusssequenz im Sanctuary braucht sie nicht mehr: dort laufen der Text und
	-- die Kapitel-Karte, und das HUD gehoert erst danach wieder her.
	--
	-- VOR MarkPrologueComplete, weil darin player:LoadCharacter() steckt -- der Spieler
	-- steht sonst einen Augenblick im Sanctuary, waehrend die Anzeige noch dasteht.
	SetPrologueLetterboxEvent:FireClient(player, true, true)

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
		equippedSkin.Value = 0 -- kleinster Skin ("Primal Beast", Id 0 in SkinsConfig.lua)
	end
	resetPowerStats()

	-- Server-globale Einstellung so früh wie möglich wieder aktivieren (siehe
	-- ausführlicher Kommentar bei der Deaktivierung weiter oben) -- der eigene Charakter
	-- wurde soeben bereits explizit erzeugt, andere Spieler auf dem Server respawnen ab
	-- jetzt wieder normal automatisch.
	Players.CharacterAutoLoads = true

	player:SetAttribute("IsInPrologue", false)
	disarmFirstBuildingWatch(player) -- der Auslöser für Stufe 1 gehört zu DIESEM Durchlauf
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
		-- Derselbe Fall wie beim Sprung in die Prologstadt: der Graben liegt weit weg und
		-- ist beim Client noch nicht angekommen. Dass der Bildschirm hier schwarz ist,
		-- hilft nicht -- "Gameplay Paused" gehört der CoreGui und liegt darüber.
		streameZielVor(player, trenchSpawn.Position, "TrenchSpawn")
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
	--
	-- Das Uhrticken schlaegt zu JEDER der beiden Zeilen -- einmal bei "POWER CAN BE
	-- BROKEN.", einmal bei "PURPOSE CANNOT.". Die Karte blendet die zweite Zeile ohnehin
	-- zeitversetzt ein; der Ton haengt an genau diesen zwei Zeitpunkten und nicht an
	-- eigenen Schritten davor, die ihn nur ungefaehr treffen wuerden.
	local trenchSteps = {
		{
			type = "text",
			text = "POWER CAN BE BROKEN.\nPURPOSE CANNOT.",
			duration = 3.5,
			lineSoundId = TICK_SOUND_ID,
		},
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
	--
	-- ===== Der Mindestabstand war ein Mittelpunktabstand (26.09.2026) =====
	-- 18 Studs -- gemessen von Wurzel zu Wurzel, und beide Figuren haben selbst eine Breite.
	-- Der Kollisionskörper des Kaiju allein hat bei hohen Stufen über 20 Studs Halbmesser,
	-- der Guardian kommt mit seinem eigenen dazu. Der Guardian lief also bis IN die
	-- Spielerfigur und stand ihr danach im Bild, statt ihr gegenüber.
	--
	-- Deshalb sind es jetzt beide Halbmesser plus ein Zuschlag, der die Lücke ausmacht.
	-- Gemessen wird der Kollisionskörper, nicht die Bounding Box: die misst beim Kaiju die
	-- Spannweite der Arme (rund 142 Studs) und hätte den Guardian am anderen Ende der Stadt
	-- stehen lassen.
	local GUARDIAN_APPROACH_GAP_STUDS = 18

	-- Der Halbmesser einer Figur, so wie der CityDefenderService ihn auch bestimmt.
	--
	-- Die Obergrenze ist kein Schmuck: greift der Rückfall auf die Bounding Box beim Kaiju,
	-- kämen 71 Studs heraus, und der Guardian bliebe ausser Sichtweite stehen. Lieber ein
	-- gedeckelter Wert als eine Annäherung, die gar nicht stattfindet.
	local HALBMESSER_MAX = 40

	local function koerperHalbmesser(instanz, colliderName)
		if not instanz then
			return 0
		end
		local collider = colliderName and instanz:FindFirstChild(colliderName)
		if collider and collider:IsA("BasePart") then
			return math.min(math.max(collider.Size.X, collider.Size.Z) * 0.5, HALBMESSER_MAX)
		end
		local ok, size = pcall(function()
			local _, extents = instanz:GetBoundingBox()
			return extents
		end)
		if ok and size then
			return math.min(math.max(size.X, size.Z) * 0.5, HALBMESSER_MAX)
		end
		return 0
	end

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

			-- Je Durchlauf neu gemessen: die Figur wächst im Prolog (Skin- und Zonenwechsel
			-- skalieren sie), ein einmal gemerkter Halbmesser wäre kurz darauf falsch.
			local minDistance = GUARDIAN_APPROACH_GAP_STUDS
				+ koerperHalbmesser(guardianModel, nil)
				+ koerperHalbmesser(character, "KaijuBodyCollider")

			if distance > minDistance then
				local direction = toPlayer.Unit
				local moveDistance = math.min(distance - minDistance, 6 * dt)
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

-- Setzt die Prologstadt auf genau diese Alarmstufe.
--
-- Stufe 1 braucht einen eigenen Weg. _G.SetCityAlertLevel(stadt, 1) setzt den Fortschritt
-- auf 0 -- und ein Fortschritt von 0 IST Stufe 0, nicht 1: der Übergang 0 -> 1 hängt im
-- CityAlertService allein daran, dass überhaupt etwas zerstört wurde (dort "event-basiert,
-- NICHT schwellenwert-basiert"). Für Stufe 1 braucht es also irgendeinen Wert über 0 und
-- unter AlertThresholdLevel2, das für PrologueCity bei 30 liegt. Die 1 hier ist genau das
-- und sonst nichts -- sie steht für "es hat angefangen", nicht für eine Menge Zerstörung.
local function setPrologueAlertLevel(targetLevel)
	if targetLevel <= 1 then
		if _G.SetCityAlertProgress then
			_G.SetCityAlertProgress(PROLOGUE_CITY_NAME, targetLevel <= 0 and 0 or 1)
		end
		return
	end
	if _G.SetCityAlertLevel then
		_G.SetCityAlertLevel(PROLOGUE_CITY_NAME, targetLevel)
	end
end

-- Läuft periodisch, solange der Spieler im Prolog ist -- setzt den Alert-Fortschritt aktiv
-- auf den zum aktuellen Zeitpunkt passenden Wert. Dadurch bleibt die Eskalation exakt nach
-- Zeitplan, auch wenn parallel Zerstörung (normalerweise ebenfalls Alert-Fortschritt
-- gebend) passiert.
--
-- Zwei Abschnitte: erst warten, bis das erste Gebäude fällt (Stadt steht auf Stufe 0),
-- danach eine Stufe je ESCALATION_STEP_SECONDS.
local function driveEscalationByTime(player)
	-- WICHTIG: Generation-Absicherung gegen mehrere gleichzeitig laufende Schleifen (z.B.
	-- Reste aus einem vorherigen, nicht sauber beendeten Testlauf). Jeder Aufruf erhöht
	-- die Generation-Nummer -- eine ÄLTERE, noch laufende Schleife erkennt daran, dass sie
	-- überholt wurde, und beendet sich sofort selbst, statt mit einem falschen (alten)
	-- Zeit-Ursprung gegen die neue Schleife zu konkurrieren (das verursachte sichtbar
	-- hin- und herspringende Alert-Level).
	local myGeneration = (player:GetAttribute("PrologueEscalationGeneration") or 0) + 1
	player:SetAttribute("PrologueEscalationGeneration", myGeneration)

	local function stillMine()
		return player.Parent
			and player:GetAttribute("IsInPrologue")
			and player:GetAttribute("PrologueEscalationGeneration") == myGeneration
	end

	-- ===== Abschnitt 1: Stufe 0, bis das erste Gebäude fällt =====
	-- armFirstBuildingWatch lief schon vor der Tutorial-Checkliste; fiel dort bereits ein
	-- Gebäude, steht der Zeitpunkt längst und diese Schleife läuft gar nicht erst.
	setPrologueAlertLevel(0)

	local waitingSince = os.clock()
	while not firstBuildingDestroyedAt[player] do
		if not stillMine() then
			disarmFirstBuildingWatch(player)
			return
		end
		if os.clock() - waitingSince >= FIRST_BUILDING_GRACE_SECONDS then
			firstBuildingDestroyedAt[player] = os.clock()
			warn(string.format(
				"[PrologueOrchestrator] Nach %d s ist in %s kein Gebaeude gefallen -- die Eskalation laeuft "
					.. "jetzt trotzdem an, sonst bliebe der Prolog auf Stufe 0 stehen.",
				FIRST_BUILDING_GRACE_SECONDS, PROLOGUE_CITY_NAME))
			break
		end
		task.wait(0.2)
	end

	local startTime = firstBuildingDestroyedAt[player] or os.clock()
	firstBuildingWatchers[player] = nil -- der Auslöser hat seine Aufgabe erfüllt

	-- ===== Abschnitt 2: eine Stufe je ESCALATION_STEP_SECONDS =====
	local lastAnnouncedLevel = nil

	while stillMine() do
		local elapsed = os.clock() - startTime
		local targetLevel = math.min(
			ESCALATION_MAX_LEVEL,
			1 + math.floor(elapsed / ESCALATION_STEP_SECONDS)
		)

		setPrologueAlertLevel(targetLevel)

		if targetLevel ~= lastAnnouncedLevel then
			lastAnnouncedLevel = targetLevel
			print(string.format(
				"[Kaiju-Debug] Prolog: Alarmstufe %d nach %.1f s seit dem ersten Gebaeude.",
				targetLevel, elapsed))
		end

		-- Guardian-Stufe (5) einmal erreicht: Zeitplan ist durchgelaufen, weiteres
		-- periodisches Nachsetzen nicht mehr nötig (Guardian-Phase übernimmt ab hier).
		if targetLevel >= ESCALATION_MAX_LEVEL then
			return
		end

		-- Eine Sekunde Auflösung bei zwanzig Sekunden Schrittweite: die Stufe kommt damit
		-- höchstens eine Sekunde nach ihrem Zeitpunkt. Die vorherigen zwei Sekunden waren
		-- bei ungleichen Abständen unauffällig, bei einem gleichmässigen Takt fällt ein
		-- Versatz eher auf.
		task.wait(1)
	end

	disarmFirstBuildingWatch(player)
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

	-- Ausdrücklich auf Stufe 0, nicht auf 1: der nächste Durchlauf soll seine Stufe 1 wieder
	-- selbst auslösen, indem der Spieler das erste Gebäude umlegt. Hier stand
	-- _G.SetCityAlertLevel(.., 1), was heute dasselbe bewirkt (es setzt den Fortschritt auf
	-- 0, und das IST Stufe 0) -- aber nur zufällig. Würde jemand diesen Setzer einmal so
	-- berichtigen, dass er wirklich Stufe 1 setzt, stünde die Prologstadt beim Start des
	-- nächsten Spielers schon auf 1 und der Auslöser liefe ins Leere.
	setPrologueAlertLevel(0)

	print("[PrologueOrchestrator] " .. PROLOGUE_CITY_NAME .. " auf Alarmstufe 0 zurückgesetzt.")
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
	teleportToPrologueArea(player, character)
	local rootPartForDebug = character:FindFirstChild("HumanoidRootPart")
	print("[Kaiju-Debug] Prolog: Start #5 -- teleportiert (nach Skin-Wechsel), tatsächliche Position=" .. tostring(rootPartForDebug and rootPartForDebug.Position))

	PrologueReinforcementService.ProtectPlayer(player, PROLOGUE_CITY_NAME)
	print("[Kaiju-Debug] Prolog: Start #6 -- ProtectPlayer aufgerufen, vor playColdOpen (BLOCKIEREND)")

	playColdOpen(player)
	rootPartForDebug = character:FindFirstChild("HumanoidRootPart")
	print("[Kaiju-Debug] Prolog: Start #7 -- playColdOpen fertig, Position jetzt=" .. tostring(rootPartForDebug and rootPartForDebug.Position))

	playIntroCinematic(player, character)
	print("[Kaiju-Debug] Prolog: Start #7b -- Intro-Kinematik fertig")

	-- ===== Die Eskalation läuft ab HIER mit, nicht erst nach dem Tutorial =====
	-- "Nach dem ersten zerstörten Gebäude kommt sofort Alarmstufe 1" heisst sofort. Stünde
	-- der Treiber wie früher erst hinter der Checkliste, könnte der Spieler während des
	-- Tutorials ein Gebäude umlegen -- die Stadt bliebe trotzdem still, und beim Start des
	-- Treibers wäre die erste Stufe je nach verstrichener Zeit schon übersprungen.
	--
	-- Solange nichts fällt, kostet das nichts: der Treiber steht bei Alarmstufe 0 und wartet.
	--
	-- armFirstBuildingWatch läuft SYNCHRON vor dem task.spawn. Innerhalb des Treibers wäre
	-- es ein Rennen -- und es setzt den gemerkten Zeitpunkt zurück, dürfte also ohnehin nur
	-- genau einmal je Durchlauf laufen.
	armFirstBuildingWatch(player)
	task.spawn(function()
		driveEscalationByTime(player)
	end)

	-- Tutorial-Checkliste (PUNCH/JUMP/ABSORB) -- blockiert, bis der Spieler alle drei
	-- Aktionen ausgeführt hat, längstens aber TUTORIAL_TIME_LIMIT_SECONDS.
	playTutorialChecklist(player, character)
	print("[Kaiju-Debug] Prolog: Start #7c -- Tutorial-Checkliste fertig")

	StoryBeatService.PlayAsync(player, { steps = { { type = "hint", text = "DESTROY.", duration = 2.5 } } })
	print("[Kaiju-Debug] Prolog: Start #8 -- DESTROY-Hint gefeuert")

	-- Der Guardian-Auslöser (Stufe 5) kommt frühestens vier Schritte nach dem ersten
	-- Gebäude -- die Checkliste davor ist auf TUTORIAL_TIME_LIMIT_SECONDS begrenzt und kann
	-- ihn deshalb nicht verpassen lassen.
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
	-- Auch für einen Spieler, der mitten im Prolog geht: sonst bliebe sein Eintrag als
	-- Schlüssel in den beiden Tabellen stehen und hielte das Player-Objekt fest.
	disarmFirstBuildingWatch(player)

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