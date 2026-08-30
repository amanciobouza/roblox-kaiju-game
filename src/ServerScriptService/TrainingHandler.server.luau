-- VERSION: 2026-08-25 #32
-- Script (kein LocalScript!): TrainingHandler
-- Ort in Studio: ServerScriptService
-- Verwaltet die 3 Trainingsstationen in der Start-Zone. Spieler gehen hin, drücken E
-- (ProximityPrompt) zum Aktivieren, klicken dann regelmäßig -> der jeweilige Kraft-Wert
-- (Bein/Arm/Körper) steigt schrittweise, bis zum Cap für das aktuelle Level.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local Workspace = game:GetService("Workspace")

local TrainClickEvent = RemoteEventUtils.GetOrCreate("TrainClickEvent")
local TrainPointEvent = RemoteEventUtils.GetOrCreate("TrainPointEvent")
local StopTrainingEvent = RemoteEventUtils.GetOrCreate("StopTrainingEvent")
local ShowDamageEvent = RemoteEventUtils.GetOrCreate("ShowDamageEvent")

-- Debug-Werkzeug: Schieberegler im Debug-Panel setzt Level + alle drei Skill-Werte auf
-- den jeweiligen Cap für dieses Level -- zum schnellen Testen später Spielphasen, ohne
-- stundenlang trainieren zu müssen.
local DebugSetLevelEvent = Instance.new("RemoteEvent")
DebugSetLevelEvent.Name = "DebugSetLevelEvent"
DebugSetLevelEvent.Parent = ReplicatedStorage

-- Server braucht eine EIGENE, autoritative Kopie von "DebugMode" -- player:SetAttribute()
-- vom Client aus repliziert NICHT zum Server (nur Server->Client repliziert automatisch).
-- Ohne dieses Event würde der Level-Schieberegler serverseitig immer "DebugMode = aus"
-- sehen und jede Anfrage stillschweigend ablehnen.
local SetDebugModeEvent = Instance.new("RemoteEvent")
SetDebugModeEvent.Name = "SetDebugModeEvent"
SetDebugModeEvent.Parent = ReplicatedStorage
SetDebugModeEvent.OnServerEvent:Connect(function(player, isOn)
	player:SetAttribute("DebugMode", isOn == true)
end)

-- Kraft-Cap pro Stat (Bein/Arm/Körper): exakt kalibriert, sodass am Ende jeder Zone
-- (max. Level, volles Training) das jeweils 2.stärkste Gebäude der Zone auf "Gelb"
-- steht (Verhältnis Gebäude-HP / Gesamtschaden ≈ 11, sorgt für ca. 8-13 Treffer inkl.
-- Combo/Berserker-Bonus pro Gebäude am Zonen-Einstieg). Zwischen den Ankerpunkten wird
-- exponentiell interpoliert (passend zur "immer mehr Zeit nötig"-Philosophie), da eine
-- einzelne Formel nicht alle 5 Zielwerte gleichzeitig treffen kann -- die Gebäude-HP-
-- Sprünge zwischen den Zonen sind dafür zu ungleichmäßig.
-- BALANCE-UPDATE 2: Nach der Geb.-HP-Flachung (Megacity-Spanne 640.000x -> 15.000x, siehe
-- Gebäude-Attribute in Studio) neu kalibriert auf die tatsächliche MEDIAN-Gebäudegrösse
-- jeder Zone (Village 100, SmallTown 500, City 2000, LargeCity 4000, Megacity 70000, Endboss
-- 1.500.000) -- weiterhin ~11 Treffer am Zonen-Einstieg, Level 49 bewusst etwas härter
-- (~18 Treffer) für den grössten Megacity-Boss. Der Sprung zwischen den letzten beiden
-- Ankerpunkten sank dadurch von ×154 auf ×13.
local STAT_CAP_BREAKPOINTS = {
	{ level = 0, cap = 9 },
	{ level = 9, cap = 45 },
	{ level = 19, cap = 182 },
	{ level = 29, cap = 364 },
	{ level = 39, cap = 6364 },
	{ level = 49, cap = 83333 },
}

local TRAIN_CLICK_COOLDOWN = 0.6 -- Sekunden zwischen zwei zählenden Klicks (doppelt so lang wie vorher)

-- ===== Trainings-Boost: wird durch viele erfolgreiche Klicks verdient, verdoppelt dann
-- den Klick-Cooldown für eine begrenzte Zeit -- NICHT den Wert pro Klick selbst.
-- Doppelte Klick-Geschwindigkeit bei gleichem Wert pro Klick = effektiv doppelte
-- Punktzahl pro Zeiteinheit, ohne dass ein einzelner Klick sich "größer" anfühlt. =====
local BOOST_CHARGE_PER_CLICK = 0.5 -- wie viel "Ladung" ein Klick bringt (kein Boost aktiv)
local BOOST_CHARGE_NEEDED = 15 -- Ladung nötig, bis der Boost startet (~30 Klicks)
local BOOST_DURATION = 10 -- Sekunden, die der Boost aktiv bleibt
local BOOST_MULTIPLIER = 2 -- Faktor, um den der Klick-COOLDOWN während des Boosts sinkt (Cooldown / BOOST_MULTIPLIER)

-- Für den Client sichtbar machen (fürs HUD)
local boostDurationValue = Instance.new("IntValue")
boostDurationValue.Name = "BoostDuration"
boostDurationValue.Value = BOOST_DURATION
boostDurationValue.Parent = ReplicatedStorage

local boostCharge = {} -- [player] = number

local function isBoostActive(player)
	return Workspace:GetServerTimeNow() < (player:GetAttribute("BoostEndsAt") or 0)
end

-- Name des Parts in Workspace -> welcher Kraft-Wert wird dort trainiert
-- WICHTIG: "BodyTrainingStation" ist NICHT mehr hier aufgeführt -- sie wird komplett
-- eigenständig vom TitanAssimilationCircuit-Script gesteuert (eigener Prompt, kein
-- WalkSpeed=0, da der Spieler dort ja aktiv zwischen Energiequellen laufen muss). Würde
-- sie hier zusätzlich aufgeführt, würde dieses generische System einen KONKURRIERENDEN
-- zweiten Prompt erstellen, der beim Aktivieren fälschlich die Bewegung einfriert.
-- WICHTIG: Weder "ArmTrainingStation" noch "BodyTrainingStation" sind hier aufgeführt --
-- beide werden komplett eigenständig von ihren jeweiligen Trainingsstations-Scripts
-- gesteuert (eigener Prompt, eigene Session-Verwaltung). Würden sie hier zusätzlich
-- aufgeführt, würde dieses generische System einen KONKURRIERENDEN zweiten Prompt
-- erstellen (das Problem, das wir bei Body schon hatten).
local STATIONS = {
	LegTrainingStation = "Leg",
}

local lastClickTime = {} -- [player] = os.clock()
local originalWalkSpeed = {} -- [player] = number, um sie beim Verlassen der Station wiederherzustellen
local lastTrainedStat = {} -- [player] = statType, um beim Verlassen zu wissen, welche Station zurückskaliert werden muss

local function rawStatCapForLevel(level)
	level = math.clamp(level, 0, STAT_CAP_BREAKPOINTS[#STAT_CAP_BREAKPOINTS].level)

	for i = 1, #STAT_CAP_BREAKPOINTS - 1 do
		local a = STAT_CAP_BREAKPOINTS[i]
		local b = STAT_CAP_BREAKPOINTS[i + 1]
		if level >= a.level and level <= b.level then
			local t = (b.level > a.level) and (level - a.level) / (b.level - a.level) or 0
			-- Exponentielle (nicht lineare) Interpolation zwischen den beiden Ankerpunkten
			local logCap = math.log(a.cap) + t * (math.log(b.cap) - math.log(a.cap))
			return math.max(math.floor(math.exp(logCap)), 1)
		end
	end

	return STAT_CAP_BREAKPOINTS[#STAT_CAP_BREAKPOINTS].cap
end

-- WICHTIG: Die rohe Formel oben kann bei kleinen Level-Unterschieden (v.a. ganz am
-- Anfang, Level 0 -> 1) durch das Abrunden denselben Cap-Wert liefern -- ein Spieler, der
-- bei Level 0 komplett austrainiert war, könnte dann bei Level 1 fälschlich immer noch
-- "maximal" erscheinen, obwohl er ja eigentlich wieder trainieren können sollte. Deshalb
-- hier eine Garantie: der Cap wächst pro Level um MINDESTENS 1 (verglichen mit Level 0),
-- unabhängig davon, was die rohe Formel durchs Abrunden ergibt.
local function getStatCapForLevel(level)
	level = math.clamp(level, 0, STAT_CAP_BREAKPOINTS[#STAT_CAP_BREAKPOINTS].level)
	return math.max(rawStatCapForLevel(level), rawStatCapForLevel(0) + level)
end

-- Arm-Cap wird künstlich um Faktor 100 vergrößert -- die angezeigten Zahlen wirken dadurch
-- "normal" (z.B. 50 statt 0.05) und die Trainingsdauer bleibt 100x länger, OHNE dass die
-- Trainingsschritte selbst winzig-klein werden müssen (siehe getTrainIncrement). Damit der
-- Kampf-Schaden dadurch NICHT auch 100x größer wird, kompensiert PlayerSetup.lua das beim
-- Berechnen von "Damage" wieder (ArmPower / ARM_CAP_SCALE).
--
-- Bein-Cap wird aus demselben Grund (normale, nicht-winzige Zahlen in der Anzeige) EBENFALLS
-- um denselben Faktor vergrößert -- hier ist aber KEINE Kompensation nötig: Bein-Wert wird
-- überall (Sprung-/Fokus-/Flächenschaden-Multiplikator) nur als VERHÄLTNIS (Wert/Cap)
-- genutzt, das durch gleichmäßige Skalierung von Wert UND Cap unverändert bleibt.
local ARM_CAP_SCALE = 100
local LEG_CAP_SCALE = 100

local function getStatCap(player, statType)
	local leaderstats = player:FindFirstChild("leaderstats")
	local level = (leaderstats and leaderstats:FindFirstChild("Level")) and leaderstats.Level.Value or 0
	local cap = getStatCapForLevel(level)
	if statType == "Arm" then
		cap = cap * ARM_CAP_SCALE
	elseif statType == "Leg" then
		cap = cap * LEG_CAP_SCALE
	end
	return cap
end

-- Für PlayerSetup.lua zugänglich machen (Damage-Berechnung muss den Arm-Faktor kompensieren)
_G.ARM_CAP_SCALE = ARM_CAP_SCALE
_G.LEG_CAP_SCALE = LEG_CAP_SCALE

-- Für andere Scripts (z.B. das Energie-Sammelsystem) zugänglich machen -- die brauchen
-- den Cap für ein BELIEBIGES Level (z.B. das einem Gebäude implizit entspricht), nicht
-- nur für einen konkreten Spieler.
_G.GetStatCapForLevel = getStatCapForLevel

-- Box-Muller-Transformation: Lua hat keine eingebaute Normalverteilung, das ist der
-- Standard-Trick, um aus zwei gleichverteilten Zufallszahlen eine normalverteilte
-- (Gauß-glockenförmige) Zufallszahl mit Mittelwert 0 und Standardabweichung 1 zu erzeugen.
local function gaussianRandom()
	local u1 = math.max(math.random(), 1e-9) -- verhindert log(0)
	local u2 = math.random()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

-- Zielwert: ~2 Minuten Dauerklicken (bei TRAIN_CLICK_COOLDOWN), um von 0 auf den
-- AKTUELLEN Cap zu kommen -- bei JEDEM Level gleich lang, weil das Increment direkt
-- proportional zum jeweils aktuellen Cap berechnet wird. Die alte Formel (Increment
-- wächst nur alle 25 Level um +1) hatte NICHT mit den riesigen Cap-Sprüngen (bis ×250
-- zwischen zwei Ankerpunkten) mitgehalten -- bei Level 49 hätte das Füllen des Caps
-- rechnerisch 338 JAHRE gedauert. Ratio auf 1/200 gesetzt -- 200 Klicks × 0.6s
-- Cooldown = 120s = 2 Minuten Zielzeit pro Trainingsstation.
local TRAINING_PROGRESS_RATIO = 1 / 200

local function getTrainIncrement(player, statType)
	local currentCap = getStatCap(player, statType)
	local base = currentCap * TRAINING_PROGRESS_RATIO

	local evoTrainingLevel = player:FindFirstChild("EvoTrainingLevel")
	if evoTrainingLevel and _G.EVO_BONUS_PER_LEVEL then
		base = base * (1 + evoTrainingLevel.Value * _G.EVO_BONUS_PER_LEVEL)
	end

	base = math.max(base, 0.001)

	-- Normalverteilte Variation, gedeckelt auf ±25% des aktuellen Kampf-Schadens
	-- (character.Damage) -- Standardabweichung = ein Drittel des Deckels, damit ca. 99.7%
	-- der Werte (3-Sigma-Regel) natürlicherweise innerhalb der Range liegen; ein hartes
	-- Clamp fängt die seltenen Ausreißer trotzdem ab.
	local character = player.Character
	local damage = character and character:GetAttribute("Damage") or 10
	local rangeCap = damage * 0.25
	local stddev = rangeCap / 3
	local variation = math.clamp(gaussianRandom() * stddev, -rangeCap, rangeCap)

	-- Die Variation bezieht sich auf den aktuellen KAMPF-Schaden (relativ klein), das
	-- Increment selbst aber auf den vollen (100x skalierten) Cap -- die Variation wird
	-- deshalb im GLEICHEN Verhältnis wie das Increment selbst hochskaliert, sonst würde
	-- sie bei hohen Leveln komplett im Rauschen des riesigen Basiswerts untergehen.
	local scaledVariation = variation * TRAINING_PROGRESS_RATIO * 100
	local varied = base + scaledVariation

	if statType == "Arm" or statType == "Leg" then
		return math.max(math.floor(varied * 10 + 0.5) / 10, 0.1)
	end

	-- Körper nutzt keinen künstlich vergrösserten Cap -- Increment bleibt dadurch von
	-- selbst kleiner, keine zusätzliche Verlangsamung nötig.
	return math.max(math.floor(varied * 100 + 0.5) / 100, 0.001)
end

-- Findet ein geeignetes BasePart für das ProximityPrompt (das braucht zwingend einen Part
-- als Elternteil, kein Model). Falls "instance" ein Model ist, wird PrimaryPart oder das
-- erste gefundene BasePart darin genutzt. Heftet außerdem ALLE Teile an, damit die Station
-- nicht wegrutscht, wenn ein Spieler dagegen läuft.
-- Merkt sich pro Stat-Typ die Position der zugehörigen Station -- wird genutzt, um den
-- Spieler während des Trainings kontinuierlich dorthin auszurichten. Zusätzlich die
-- Instanz selbst + ihre Original-Skalierung, um die Station beim Trainingsstart auf die
-- aktuelle Avatar-Größe des Spielers zu skalieren (und beim Verlassen wieder zurück).
local stationPositions = {} -- [statType] = Vector3
local stationCFrames = {} -- [statType] = CFrame (für die Blickrichtung -> "davor" positionieren)
local stationFrontAnchors = {} -- [statType] = CFrame vom "FrontAnchor"-Teil, falls vorhanden (explizite, verlässliche Ausrichtung statt Raten)
local stationInstances = {} -- [statType] = Model (nur falls skalierbar, d.h. ein Model)
local stationPrompts = {} -- [statType] = ProximityPrompt -- zum Ein-/Ausblenden während des Trainings
local stationOriginalScale = {} -- [statType] = number
local stationOccupant = {} -- [statType] = Player, solange jemand dort gerade trainiert (nur EINER gleichzeitig)

-- Für Stationen, bei denen der Spieler MITTEN IN der Station steht (z.B. Bein-Training):
-- Kollision aller Teile während des Trainings deaktivieren, sonst drückt die Physik den
-- Spieler ständig raus (wirkt wie ein Wackeln/Wegstoßen der Kamera).
local stationOriginalCollide = {} -- [statType] = { [part] = boolean }

local function disableStationCollision(statType)
	local stationInstance = stationInstances[statType]
	if not stationInstance then
		return
	end
	local original = {}
	for _, part in ipairs(stationInstance:GetDescendants()) do
		if part:IsA("BasePart") then
			original[part] = part.CanCollide
			part.CanCollide = false
		end
	end
	stationOriginalCollide[statType] = original
end

local function restoreStationCollision(statType)
	local original = stationOriginalCollide[statType]
	if not original then
		return
	end
	for part, wasCollidable in pairs(original) do
		if part.Parent then
			part.CanCollide = wasCollidable
		end
	end
	stationOriginalCollide[statType] = nil
end

-- Läuft pro Station, um doppelte/überlappende Animationen zu verhindern (z.B. schnelles
-- E-Doppeltippen), falls gerade schon eine Größenänderung für dieselbe Station läuft.
local stationScaleAnimating = {} -- [statType] = true, solange eine Animation läuft

-- Animiert die Größe einer Station sanft von ihrer AKTUELLEN Größe zu "targetScale" --
-- wächst/schrumpft über Zeit, statt sofort zu springen.
-- Skalierung des Start-Skins (Level 0, siehe SkinsConfig.lua Skin_0.Scale) -- die
-- Stationen sind für DIESE Größe gebaut, daher muss relativ dazu skaliert werden.
local STARTING_AVATAR_SCALE = 4

local STATION_SCALE_ANIM_DURATION = 0.6
local STATION_SCALE_ANIM_STEPS = 20

local function animateStationScale(statType, stationInstance, targetScale)
	stationScaleAnimating[statType] = true

	local ok, startScale = pcall(function()
		return stationInstance:GetScale()
	end)
	startScale = ok and startScale or targetScale

	for step = 1, STATION_SCALE_ANIM_STEPS do
		if not stationInstance.Parent then
			break -- Station wurde inzwischen entfernt
		end
		local alpha = step / STATION_SCALE_ANIM_STEPS
		-- Sanfteres Ein-/Ausschwingen (Quad-artig) statt linear
		local eased = 1 - (1 - alpha) ^ 2
		local currentScale = startScale + (targetScale - startScale) * eased
		pcall(function()
			stationInstance:ScaleTo(currentScale)
		end)
		task.wait(STATION_SCALE_ANIM_DURATION / STATION_SCALE_ANIM_STEPS)
	end

	stationScaleAnimating[statType] = nil
end

-- Ermittelt per Raycast die echte Bodenhöhe an einer X/Z-Position (von hoch oben nach
-- unten geschossen) -- verhindert, dass der Spieler nach dem Teleport leicht im Boden
-- steckt (z.B. weil die Zielstelle auf einer erhöhten Plattform liegt, seine ALTE
-- Y-Position aber vom Erdboden stammt) -- das würde die Physik ständig hochdrücken lassen
-- und wie Zittern wirken. Fallback: die übergebene Standard-Y-Position, falls kein Boden
-- gefunden wird.
local function findGroundY(x, z, fallbackY)
	local rayOrigin = Vector3.new(x, fallbackY + 50, z)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {}

	local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -200, 0), raycastParams)
	if result then
		return result.Position.Y
	end
	return fallbackY
end

local function setupStation(instance, statType)
	local hostPart

	if instance:IsA("BasePart") then
		hostPart = instance
		instance.Anchored = true
	elseif instance:IsA("Model") then
		for _, part in ipairs(instance:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				if not hostPart then
					hostPart = instance.PrimaryPart or part
				end
			end
		end
	end

	if not hostPart then
		warn("[Training] Station '" .. instance.Name .. "' hat kein verwendbares Teil (BasePart) -- ProximityPrompt kann nicht gesetzt werden.")
		return
	end

	local prompt = hostPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = statType .. "-Kraft trainieren"
		prompt.ObjectText = "Trainingsstation"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 20
		prompt.RequiresLineOfSight = false
		prompt.Parent = hostPart
	end

	-- Positions-Referenz: NICHT das zufällig gewählte hostPart-Einzelteil nutzen (das
	-- könnte z.B. eine kleine Dekorations-Säule sein statt der eigentlichen
	-- Plattform-Mitte) -- stattdessen die echte Bounding-Box-Mitte des ganzen Models, bei
	-- einem einzelnen Part einfach dessen eigene Position/CFrame.
	local referenceCFrame = hostPart.CFrame
	if instance:IsA("Model") then
		local ok, boundingCFrame = pcall(function()
			local cframe, _size = instance:GetBoundingBox()
			return cframe
		end)
		if ok then
			-- Position von der Bounding-Box, Rotation vom hostPart (die Bounding-Box hat
			-- selbst keine sinnvolle Rotation, die ist immer achsen-ausgerichtet)
			referenceCFrame = CFrame.new(boundingCFrame.Position) * (hostPart.CFrame - hostPart.CFrame.Position)
		end
	end

	stationPositions[statType] = referenceCFrame.Position
	stationCFrames[statType] = referenceCFrame
	stationPrompts[statType] = prompt

	-- Explizite, vom Nutzer in Studio platzierte Ausrichtungs-Referenz -- zuverlässiger
	-- als jeder Rateversuch anhand der Model-eigenen Rotation.
	local frontAnchor = instance:FindFirstChild("FrontAnchor", true)
	if frontAnchor and frontAnchor:IsA("BasePart") then
		stationFrontAnchors[statType] = frontAnchor.CFrame
	end

	if instance:IsA("Model") then
		stationInstances[statType] = instance
		local ok, currentScale = pcall(function()
			return instance:GetScale()
		end)
		stationOriginalScale[statType] = ok and currentScale or 1
	end

	prompt.Triggered:Connect(function(player)
		local current = player:GetAttribute("TrainingStat")
		if current == statType then
			player:SetAttribute("TrainingStat", nil) -- nochmal E an derselben Station -> ausschalten
		elseif not current then
			-- Nur starten, wenn gerade keine ANDERE eigene Station aktiv ist UND diese
			-- Station nicht schon von einem ANDEREN Spieler belegt ist.
			if stationOccupant[statType] and stationOccupant[statType] ~= player then
				return -- Station gerade besetzt -- nichts tun
			end
			stationOccupant[statType] = player
			player:SetAttribute("TrainingStat", statType)
			local prompt = stationPrompts[statType]
			if prompt then
				prompt.Enabled = false
			end
		end
		-- Ist eine ANDERE Station aktiv: nichts tun -- erst per ESC oder erneutem E
		-- an der aktuellen Station verlassen, bevor eine neue gestartet werden kann.
	end)
end

for stationName, statType in pairs(STATIONS) do
	local instance = Workspace:FindFirstChild(stationName, true) -- rekursiv, findet auch verschachtelte Stationen
	if instance then
		setupStation(instance, statType)
	else
		warn("[Training] Station '" .. stationName .. "' nicht im Workspace gefunden. Siehe TRAINING_ANLEITUNG.md")
	end
end

-- Referenz zum neuen Titan Impact Gauntlet (ersetzt die alte "ArmTrainingStation"-
-- Schmiede) für die Sondereffekte beim Arm-Training (Ziel-Zurückstoß, Funken, Sound,
-- Combo-Anzeige) -- feuert bei jedem Arm-Trainings-Schlag zusätzlich.
local armGauntlet = Workspace:FindFirstChild("TitanImpactGauntlet", true)
local armGauntletRegisterHit = armGauntlet and armGauntlet:FindFirstChild("RegisterHit")
if armGauntlet and not armGauntletRegisterHit then
	warn("[Training] 'TitanImpactGauntlet' gefunden, aber kein 'RegisterHit'-BindableEvent darin -- Gauntlet-Effekte werden nicht ausgelöst.")
end

-- Referenz zum Leg-Reaktor (TitanSeismicReactor) für die Sondereffekte beim Bein-Training
-- (Landungs-/Laser-/Flächen-Animationen) -- feuert bei Sprung/Fokus/Fläche während des
-- Bein-Trainings zusätzlich. Über _G exponiert, da SpecialAttackHandler.lua (Fokus/
-- Fläche) und der Sprung-Lande-Detektor weiter unten in DIESER Datei darauf zugreifen müssen.
local legReactor = Workspace:FindFirstChild("LegTrainingStation", true)
local legReactorRegisterAttack = legReactor and legReactor:FindFirstChild("RegisterTrainingAttack")
if legReactor and not legReactorRegisterAttack then
	warn("[Training] 'LegTrainingStation' gefunden, aber kein 'RegisterTrainingAttack'-BindableEvent darin -- Reaktor-Effekte werden nicht ausgelöst.")
end
_G.LegReactorRegisterAttack = legReactorRegisterAttack

-- Vergibt den eigentlichen Trainingsfortschritt (Stat-Wert erhöhen, Boost-Ladung
-- aufbauen, Client benachrichtigen) -- wiederverwendbar sowohl für generische
-- Trainings-Klicks (TrainClickEvent) als auch für die neuen Bein-Trainings-Trigger
-- (Sprung-Landung, Fokus-Treffer, Flächenangriff), die ja nicht über Mausklicks laufen.
-- Gibt true zurück, falls tatsächlich Fortschritt vergeben wurde.
local function awardTrainingProgress(player, statType, weight)
	weight = weight or 1

	local statValue = player:FindFirstChild(statType .. "Power")
	if not statValue then
		return false
	end

	local cap = getStatCap(player, statType)
	if statValue.Value >= cap then
		return false -- schon am Cap für das aktuelle Level
	end

	local increment = getTrainIncrement(player, statType) * weight

	if not isBoostActive(player) then
		-- Boost-Ladung aufbauen -- muss man sich durch Reps verdienen, kein reines Warten
		boostCharge[player] = (boostCharge[player] or 0) + BOOST_CHARGE_PER_CLICK
		player:SetAttribute("BoostCharge", boostCharge[player])

		if boostCharge[player] >= BOOST_CHARGE_NEEDED then
			boostCharge[player] = 0
			player:SetAttribute("BoostCharge", 0)
			player:SetAttribute("BoostEndsAt", Workspace:GetServerTimeNow() + BOOST_DURATION)
		end
	end

	statValue.Value = math.min(statValue.Value + increment, cap)
	TrainPointEvent:FireClient(player, statType, increment)

	if _G.RecalculateStrength then
		_G.RecalculateStrength(player)
	end

	return true
end

-- Für SpecialAttackHandler.lua zugänglich machen (Fokus-/Flächenangriff während des
-- Bein-Trainings sollen ECHTEN Trainingsfortschritt geben, nicht nur die Reaktor-Optik).
_G.AwardTrainingProgress = awardTrainingProgress

-- Wird vom Client bei jedem Mausklick gefeuert, während eine Trainingsstation aktiv ist.
TrainClickEvent.OnServerEvent:Connect(function(player, comboStep)
	local statType = player:GetAttribute("TrainingStat")
	if not statType then
		return -- Spieler trainiert gerade gar nicht
	end

	local boosted = isBoostActive(player)
	-- Während des Boosts darf um den Boost-Faktor schneller geklickt werden
	local cooldown = boosted and (TRAIN_CLICK_COOLDOWN / BOOST_MULTIPLIER) or TRAIN_CLICK_COOLDOWN

	local now = os.clock()
	if lastClickTime[player] and now - lastClickTime[player] < cooldown then
		print("[Kaiju-Debug] TrainClickEvent von " .. player.Name .. " durch Server-Cooldown blockiert")
		return
	end
	lastClickTime[player] = now

	-- Arm-Training: Berserker-Schadens-Multiplikator VORAB berechnen -- fliesst sowohl in
	-- den angezeigten Schlag-Schaden als auch in die Trainings-Belohnung ein (der
	-- Schadensboost soll auch hier als zusätzliche, schnellere Skill-Belohnung spürbar
	-- sein, nicht nur als reiner Kampf-Bonus).
	local armBerserkerBonus = 1.0
	if statType == "Arm" then
		armBerserkerBonus = (_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0
	end

	if not awardTrainingProgress(player, statType, statType == "Arm" and armBerserkerBonus or nil) then
		print("[Kaiju-Debug] awardTrainingProgress fehlgeschlagen für " .. player.Name .. " (evtl. schon am Cap?)")
		return
	end

	-- Arm-Training am Titan Impact Gauntlet: löst Ziel-Zurückstoß/Funken/Sound aus. Der
	-- übergebene Schaden variiert -- gleiche normalverteilte Formel wie beim
	-- Trainingswert (±25% des Basis-Kampfschadens) -- damit sich nicht jeder Schlag exakt
	-- gleich anfühlt. Beim DRITTEN Combo-Schlag wird zusätzlich ×1.25 Schaden angewendet
	-- (wie im echten Kampf, siehe CombatHandler.lua) -- das Gauntlet-Script selbst
	-- multipliziert NICHT nochmal, es nutzt den übergebenen Schaden nur für Anzeige/XP.
	if statType == "Arm" and armGauntletRegisterHit then
		local character = player.Character
		local baseDamage = character and character:GetAttribute("Damage") or 10
		local damageRangeCap = baseDamage * 0.25
		local damageStddev = damageRangeCap / 3
		local damageVariation = math.clamp(gaussianRandom() * damageStddev, -damageRangeCap, damageRangeCap)
		local variedDamage = math.max(baseDamage + damageVariation, 0.1)

		local step = tonumber(comboStep)
		if step ~= 1 and step ~= 2 and step ~= 3 then
			step = 1
		end
		if step == 3 then
			-- Nutzt denselben Wert wie der echte Kampf (CombatHandler.lua), damit Training
			-- und Kampf konsistent bleiben, auch wenn der Wert dort mal angepasst wird.
			variedDamage = variedDamage * (_G.THIRD_PUNCH_DAMAGE_MULTIPLIER or 1.25)
		end

		-- Berserker-Schadens-Multiplikator jetzt AUCH im Arm-Training angewendet --
		-- gleiche Formel wie im echten Kampf.
		variedDamage = variedDamage * armBerserkerBonus

		-- Heat-System: Schläge erzeugen jetzt auch im Arm-Training Hitze -- vorher konnte
		-- Berserker hier nie ausgelöst werden, weil gar keine Heat entstand.
		if _G.AddPunchHeat then
			_G.AddPunchHeat(player, step)
		end

		print("[Kaiju-Debug] Gauntlet: feuere RegisterHit für " .. player.Name .. " mit Schaden " .. variedDamage .. " Schritt " .. step)
		armGauntletRegisterHit:Fire(player, variedDamage, "Punch", tostring(now), step)
		ShowDamageEvent:FireClient(player, variedDamage)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("BoostCharge", 0)
	player:SetAttribute("BoostChargeNeeded", BOOST_CHARGE_NEEDED)
	player:SetAttribute("BoostEndsAt", 0)

	-- StatCap fürs HUD bereitstellen (Client kann die Formel nicht selbst nachrechnen,
	-- da sie serverseitig lebt) -- initial setzen und bei jedem Level-Aufstieg aktualisieren.
	-- "StatCap" bleibt der NORMALE Cap (für Körper + andere Systeme wie den Energiesog,
	-- die sich auf den unskalierten Wert verlassen). "ArmStatCap"/"LegStatCap" sind die um
	-- Faktor 100 vergrößerten Caps NUR für die jeweilige Anzeige/Logik.
	local leaderstats = player:WaitForChild("leaderstats")
	player:SetAttribute("StatCap", getStatCap(player))
	player:SetAttribute("ArmStatCap", getStatCap(player, "Arm"))
	player:SetAttribute("LegStatCap", getStatCap(player, "Leg"))
	leaderstats:WaitForChild("Level"):GetPropertyChangedSignal("Value"):Connect(function()
		player:SetAttribute("StatCap", getStatCap(player))
		player:SetAttribute("ArmStatCap", getStatCap(player, "Arm"))
		player:SetAttribute("LegStatCap", getStatCap(player, "Leg"))
	end)

	-- Reagiert auf Start/Ende des Trainings: sperrt/entsperrt die Bewegung (nur Kamera drehen
	-- bleibt erlaubt) und setzt beim Verlassen die Boost-Ladung + einen laufenden Boost zurück.
	player:GetAttributeChangedSignal("TrainingStat"):Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local trainingStat = player:GetAttribute("TrainingStat")

		if trainingStat then
			if humanoid then
				originalWalkSpeed[player] = humanoid.WalkSpeed
				humanoid.WalkSpeed = 0
			end

			-- Positionierung: Bein-Training steht der Spieler GENAU IN DER MITTE der
			-- Station (kein Versatz davor) -- Arm/Körper weiterhin davor, entlang der
			-- Blickrichtung der Station.
			local stationCFrame = stationCFrames[trainingStat]
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if stationCFrame and rootPart then
				local hipHeight = humanoid and humanoid.HipHeight or 2
				if trainingStat == "Leg" then
					-- Bodenhöhe aus der Bounding-Box-OBERKANTE der Station selbst berechnen
					-- (rein geometrisch, unabhängig von CanQuery/Raycast-Zuverlässigkeit) --
					-- garantiert, dass der Spieler auf der Plattform steht statt einzusinken.
					local correctY = rootPart.Position.Y + hipHeight + rootPart.Size.Y / 2 -- Fallback
					local stationInstance = stationInstances["Leg"]
					if stationInstance then
						local ok, boundingCFrame, boundingSize = pcall(function()
							return stationInstance:GetBoundingBox()
						end)
						if ok then
							local topY = boundingCFrame.Position.Y + boundingSize.Y / 2
							correctY = topY + hipHeight + rootPart.Size.Y / 2
						end
					end

					local frontAnchor = stationFrontAnchors[trainingStat]
					if frontAnchor then
						-- Position UND Ausrichtung von FrontAnchor übernehmen -- die Kamera
						-- geht ja davon aus, dass der Spieler dort steht ("über die
						-- Schulter"), sonst zeigt sie ins Leere/in die Station hinein.
						local standPosition = Vector3.new(frontAnchor.Position.X, correctY, frontAnchor.Position.Z)
						local flatLook = Vector3.new(frontAnchor.LookVector.X, 0, frontAnchor.LookVector.Z)
						if flatLook.Magnitude < 0.01 then
							flatLook = Vector3.new(0, 0, -1)
						end
						rootPart.CFrame = CFrame.lookAt(standPosition, standPosition + flatLook)
					else
						-- Kein FrontAnchor gefunden: Rückfallebene -- eigene aktuelle
						-- Blickrichtung des Spielers beibehalten, nur Höhe korrigieren.
						local currentLookVector = rootPart.CFrame.LookVector
						local flatLookVector = Vector3.new(currentLookVector.X, 0, currentLookVector.Z)
						if flatLookVector.Magnitude < 0.01 then
							flatLookVector = Vector3.new(0, 0, -1)
						end
						local standPosition = Vector3.new(rootPart.Position.X, correctY, rootPart.Position.Z)
						rootPart.CFrame = CFrame.lookAt(standPosition, standPosition + flatLookVector)
					end
					-- HINWEIS: Kollision der Station wird für Bein NICHT mehr deaktiviert
					-- (anders als vorher) -- ohne Kollision hat auch die Plattform selbst
					-- keine mehr, wodurch die Schwerkraft den Spieler einfach durchfallen
					-- lässt ("versinkt im Modell"). Das ursprüngliche Zittern kam vermutlich
					-- vom inzwischen entfernten kontinuierlichen Ausrichtungs-Loop, nicht von
					-- der Kollision selbst.
				else
					local avatarScale = humanoid and humanoid:FindFirstChild("BodyHeightScale")
					local scaleMultiplier = avatarScale and avatarScale.Value or 1
					local standDistance = 4 * scaleMultiplier
					local standPosition = stationCFrame.Position + stationCFrame.LookVector * standDistance
					local groundY = findGroundY(standPosition.X, standPosition.Z, rootPart.Position.Y)
					local correctY = groundY + hipHeight + rootPart.Size.Y / 2
					standPosition = Vector3.new(standPosition.X, correctY, standPosition.Z)
					rootPart.CFrame = CFrame.lookAt(standPosition, stationCFrame.Position)
					disableStationCollision(trainingStat)
				end
			end

			-- Station sanft auf die aktuelle Avatar-Größe des Spielers wachsen lassen --
			-- WICHTIG: relativ zur Level-0-Startgröße (der Startskin ist selbst schon 4x
			-- skaliert), nicht absolut -- sonst wäre die Station bei einem frischen
			-- Level-0-Spieler schon 4x zu groß, obwohl sie ja genau für den gebaut wurde.
			local stationInstance = stationInstances[trainingStat]
			if stationInstance and humanoid then
				local avatarScale = humanoid:FindFirstChild("BodyHeightScale")
				local absoluteScale = avatarScale and avatarScale.Value or STARTING_AVATAR_SCALE
				local relativeScaleMultiplier = absoluteScale / STARTING_AVATAR_SCALE
				local baseScale = stationOriginalScale[trainingStat] or 1
				task.spawn(animateStationScale, trainingStat, stationInstance, baseScale * relativeScaleMultiplier)
			end
		else
			if humanoid and originalWalkSpeed[player] then
				humanoid.WalkSpeed = originalWalkSpeed[player]
			end

			-- Trainingsstation verlassen -> Boost-Ladung UND einen evtl. laufenden Boost zurücksetzen
			boostCharge[player] = 0
			player:SetAttribute("BoostCharge", 0)
			player:SetAttribute("BoostEndsAt", 0)

			-- Station sanft wieder auf Originalgröße zurückschrumpfen lassen -- nutzt den
			-- zuletzt trainierten Stat-Typ (der jetzt gerade auf nil gewechselt ist, daher
			-- vorher gespeichert).
			local lastStat = lastTrainedStat[player]
			local stationInstance = lastStat and stationInstances[lastStat]
			if stationInstance and stationOriginalScale[lastStat] then
				task.spawn(animateStationScale, lastStat, stationInstance, stationOriginalScale[lastStat])
			end

			-- Belegung der Station wieder freigeben, damit ein anderer Spieler sie nutzen kann
			if lastStat and stationOccupant[lastStat] == player then
				stationOccupant[lastStat] = nil
			end

			-- Prompt wieder einblenden, jetzt wo die Station wieder frei ist
			local lastPrompt = lastStat and stationPrompts[lastStat]
			if lastPrompt then
				lastPrompt.Enabled = true
			end

			-- Kollision der Station wiederherstellen, egal welcher Stat gerade trainiert wurde
			if lastStat then
				restoreStationCollision(lastStat)
			end
		end

		if trainingStat then
			lastTrainedStat[player] = trainingStat
		end
	end)
end)

-- Per ESC das aktuelle Training vorzeitig beenden (alternativ zu erneutem E an derselben Station)
StopTrainingEvent.OnServerEvent:Connect(function(player)
	local trainingStat = player:GetAttribute("TrainingStat")
	if trainingStat then
		-- Arm-Training am Gauntlet: dessen eigener interner Zustand (activePlayer,
		-- deaktivierter Prompt) muss separat zurückgesetzt werden, sonst bleibt die
		-- Station "besetzt" hängen und man kann nicht mehr neu starten.
		if trainingStat == "Arm" and _G.StopArmGauntletSession then
			_G.StopArmGauntletSession(player)
		end
		player:SetAttribute("TrainingStat", nil)
	end

	-- Körper-Training (Kreisparcours) nutzt ein EIGENES Attribut (BodyTrainingActive)
	-- statt TrainingStat -- ohne diesen Zweig hätte "Training verlassen" beim
	-- Körper-Training gar nichts bewirkt (Button sichtbar, aber wirkungslos).
	if player:GetAttribute("BodyTrainingActive") then
		if _G.StopBodyCircuitSession then
			_G.StopBodyCircuitSession(player)
		end
		player:SetAttribute("BodyTrainingActive", nil)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastClickTime[player] = nil
	boostCharge[player] = nil
	originalWalkSpeed[player] = nil

	-- Falls der Spieler mitten im Training das Spiel verlässt: Belegung der Station
	-- freigeben, sonst bliebe sie für immer gesperrt.
	local lastStat = lastTrainedStat[player]
	if lastStat and stationOccupant[lastStat] == player then
		stationOccupant[lastStat] = nil
		local prompt = stationPrompts[lastStat]
		if prompt then
			prompt.Enabled = true
		end
		restoreStationCollision(lastStat)
	end
	lastTrainedStat[player] = nil
end)

-- HINWEIS: Der frühere kontinuierliche Ausrichtungs-Loop (jeden Frame neu zur Station
-- ausgerichtet) wurde entfernt -- er hat vermutlich das gemeldete Zittern verursacht:
-- winzige Positions-Schwankungen (Physik-Rundung o.ä.) führten jeden Frame zu einer
-- leicht unterschiedlich berechneten LookAt-Richtung, was wie ein Vibrieren wirkte. Die
-- Ausrichtung wird bereits EINMALIG beim Trainingsstart korrekt gesetzt (siehe oben) --
-- das reicht, da der Spieler durch WalkSpeed=0 ohnehin eingefroren ist und sich nicht von
-- selbst wegdrehen kann.

-- ===== Sprung-Landung während Bein-Training -> löst den Leg-Reaktor aus =====
-- Da während des Trainings keine Häuser berührt werden (Stations-Kollision ist ja
-- deaktiviert), gibt es sonst keinen natürlichen "Landungs"-Moment -- hier wird er
-- eigens erkannt: Humanoid wechselt von Jumping/Freefall zu Landed/Running, während
-- TrainingStat == "Leg" aktiv ist.
local function setupJumpLandingDetector(player, character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	local wasFalling = false

	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping or newState == Enum.HumanoidStateType.Freefall then
			wasFalling = true
			return
		end

		if wasFalling and (newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running) then
			wasFalling = false

			if player:GetAttribute("TrainingStat") ~= "Leg" then
				return
			end

			local berserkerBonus = (_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0
			awardTrainingProgress(player, "Leg", 1 * berserkerBonus) -- Basis-Gewichtung (Sprung ist die "kleinste" der drei Aktionen im echten Kampf), skaliert mit Berserker-Bonus

			local baseDamage = character:GetAttribute("Damage") or 10
			local legPower = player:FindFirstChild("LegPower")
			local legValue = legPower and legPower.Value or 0
			local legCap = math.max(player:GetAttribute("LegStatCap") or 1, 1)
			local legRatio = math.clamp(legValue / legCap, 0, 1)
			local jumpMultiplier = 1 + legRatio -- gleiche Formel wie beim echten Sprungschaden (HouseHandler.lua)
			local displayedDamage = baseDamage * jumpMultiplier

			ShowDamageEvent:FireClient(player, displayedDamage)

			if _G.LegReactorRegisterAttack then
				_G.LegReactorRegisterAttack:Fire(player, displayedDamage, "JumpLanding", tostring(os.clock()))
			end

			-- Heat-System: Sprungschaden erzeugt jetzt auch während des Bein-Trainings
			-- Hitze -- gleiche Balance wie im echten Kampf.
			if _G.AddJumpHeat then
				_G.AddJumpHeat(player)
			end

			-- Special Energy: Sprungangriff lädt während des Bein-Trainings die Energy
			-- für Spezialangriffe (Fokus/Fläche) auf -- gleiche Quelle wie im echten Kampf.
			if _G.AwardSpecialEnergyForJumpLanding then
				_G.AwardSpecialEnergyForJumpLanding(player)
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupJumpLandingDetector(player, character)
	end)
	if player.Character then
		setupJumpLandingDetector(player, player.Character)
	end
end)

-- ===== Debug-Werkzeug: Level + alle drei Skill-Werte per Schieberegler setzen =====
-- Nur wirksam, wenn der Spieler seinen eigenen Debug-Modus aktiviert hat (Sicherheit
-- gegen versehentliches/missbräuchliches Auslösen durch andere Clients).
DebugSetLevelEvent.OnServerEvent:Connect(function(player, targetLevel)
	if not player:GetAttribute("DebugMode") then
		return
	end
	targetLevel = math.clamp(math.floor(tonumber(targetLevel) or 0), 0, STAT_CAP_BREAKPOINTS[#STAT_CAP_BREAKPOINTS].level)

	local leaderstats = player:FindFirstChild("leaderstats")
	local levelValue = leaderstats and leaderstats:FindFirstChild("Level")
	if not levelValue then
		return
	end
	levelValue.Value = targetLevel

	-- XP und XPNeeded auf das neue Level zurücksetzen -- fehlte bisher komplett. Ohne
	-- das blieben nach einem Sprung auf ein NIEDRIGERES Level (z.B. 30 -> 0 über diesen
	-- Regler) die riesigen XPNeeded-Werte des vorherigen, höheren Levels stehen -- kleine
	-- XP-Gewinne aus normalem Spielen wirkten dadurch auf dem Level-Balken praktisch
	-- unsichtbar, obwohl sie serverseitig korrekt vergeben wurden.
	local xpValue = player:FindFirstChild("XP")
	local xpNeededValue = player:FindFirstChild("XPNeeded")
	if xpValue then
		xpValue.Value = 0
	end
	if xpNeededValue and _G.XPNeededForLevel then
		xpNeededValue.Value = _G.XPNeededForLevel(targetLevel)
	end

	-- Alle drei Skill-Werte direkt auf den vollen Cap für dieses Level setzen (maxen),
	-- damit man sofort eine spätere Spielphase testen kann, statt zu trainieren.
	for _, statType in ipairs({ "Arm", "Leg", "Body" }) do
		local statValue = player:FindFirstChild(statType .. "Power")
		if statValue then
			statValue.Value = getStatCap(player, statType)
		end
	end

	-- Auch den zum neuen Level passenden Skin freischalten + ausrüsten (ohne Kosten) --
	-- sonst würde WalkSpeed/Aussehen auf dem alten Skin hängen bleiben, da Skins normal
	-- gekauft werden müssen und nicht automatisch mit dem Level mitziehen.
	if _G.DebugApplyHighestSkinForLevel then
		_G.DebugApplyHighestSkinForLevel(player)
	end

	if _G.RecalculateStrength then
		_G.RecalculateStrength(player)
	end
end)