-- VERSION: 2026-09-15 #1
-- LocalScript: TrainingAutoClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Ein Knopf, der das Training von selbst weiterlaufen lässt -- je Station das, was man dort
-- ohnehin tut:
--
--   Arm    -> schlägt fortlaufend zu (Titan Impact Gauntlet)
--   Bein   -> springt fortlaufend (Titan Seismic Reactor)
--   Körper -> läuft zur aktiven Energiequelle und saugt dort (Titan Assimilation Circuit)
--
-- ===== Warum das kein Betrug ist =====
-- Die drei Stationen sind Ausdauerübungen: dieselbe Eingabe, hundertmal. Der Fortschritt
-- kommt aus der ANZAHL, nicht aus dem Können -- und eine Taste hundertmal zu drücken ist
-- keine Fähigkeit, die dieses Spiel prüfen will. Draussen in der Stadt gibt es diesen Knopf
-- bewusst nicht; dort entscheidet, WO man zuschlägt.
--
-- ===== Warum nichts davon eine eigene Mechanik ist =====
-- Der Knopf löst genau die Wege aus, die auch eine echte Eingabe nimmt: das BindableEvent
-- des Schlags, das des Kaiju-Sprungs, das Absorbieren-Ereignis. Keine eigene
-- Fortschritts-Vergabe, keine abgekürzten Cooldowns. Läuft die Automatik, passiert
-- dasselbe wie beim Spielen von Hand -- nur ohne Finger.
--
-- Damit gilt jede Grenze weiter: der Klick-Cooldown des Arm-Trainings, der Sprung-Cooldown,
-- die Reichweite beim Absorbieren. Der Knopf drückt nur, er verhandelt nicht.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local SetAbsorbingEvent = RemoteEventUtils.GetOrCreate("SetAbsorbingEvent")

local player = Players.LocalPlayer

-- Wie oft die Automatik es überhaupt versucht. Bewusst häufiger als jeder Cooldown: die
-- Grenze setzt die jeweilige Aktion selbst, nicht dieser Takt. Zu selten zu versuchen
-- hiesse, nach jedem Cooldown eine Lücke stehen zu lassen.
local TICK = 0.1

-- Wie nah die Figur an der Energiequelle stehen muss, bevor gesaugt wird. Die Station
-- selbst prüft das ebenfalls (AbsorbRadius, standardmässig 32) -- hier etwas knapper, damit
-- die Figur wirklich hingeht und nicht auf halbem Weg stehen bleibt.
local ABSORB_DISTANZ = 24

local aktiv = false
local laufNummer = 0

-- ===== Welche Station gerade läuft =====
-- Arm und Bein melden sich über "TrainingStat", die Körper-Station über ein eigenes
-- Attribut -- sie wird komplett vom Skript im Modell gesteuert und taucht in der
-- generischen Stationsliste des TrainingHandler bewusst nicht auf.
local function aktiveStation()
	if player:GetAttribute("BodyTrainingActive") == true then
		return "Body"
	end
	local stat = player:GetAttribute("TrainingStat")
	if stat == "Arm" or stat == "Leg" then
		return stat
	end
	return nil
end

-- ===== Arm: schlagen =====
-- Über dasselbe BindableEvent, das auch der Schlag-Knopf des HUD benutzt. AttackClient
-- erkennt dort das Arm-Training und nimmt den Trainings-Weg samt eigenem Cooldown.
local function schlage()
	local knopf = player:FindFirstChild("TouchAttackButtonPressed")
	if knopf then
		knopf:Fire()
	end
end

-- ===== Bein: springen =====
-- Trägt der Spieler ein Kaiju-Modell, geht der Sprung über das Rig
-- (KaijuStageOneInputClient, RequestKaijuJump). Ohne Modell der gewöhnliche Weg.
local function springe()
	local kaijuJump = player:FindFirstChild("RequestKaijuJump")
	if kaijuJump then
		kaijuJump:Fire()
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Jump = true
	end
end

-- ===== Körper: die aktive Quelle finden =====
-- Die Station schaltet den aktiven Pylon sichtbar: sein "EnergyOrb" wird fast undurchsichtig
-- (0.03), die ruhenden stehen auf 0.7. Das ist der einzige Zustand, den sie nach aussen
-- gibt -- ein Attribut wäre schöner, aber das Skript liegt in Studio und nicht im Repo.
--
-- Deshalb hier die Transparenz, mit grosszügiger Schwelle: sie muss nur aktiv von ruhend
-- trennen, nicht einen genauen Wert treffen.
local function aktiveQuelle()
	local station = Workspace:FindFirstChild("BodyTrainingStation", true)
	local pylons = station and station:FindFirstChild("EnergyPylons")
	if not pylons then
		return nil
	end
	for _, pylon in ipairs(pylons:GetChildren()) do
		local orb = pylon:FindFirstChild("EnergyOrb")
		if orb and orb:IsA("BasePart") and orb.Transparency < 0.4 then
			return orb
		end
	end
	return nil
end

local function setzeAbsorbieren(wert)
	SetAbsorbingEvent:FireServer(wert)
end

-- Läuft zur aktiven Quelle und saugt, sobald sie nah genug ist. Gibt zurück, ob gerade
-- gesaugt wird -- der Aufrufer schaltet beim Beenden sauber ab.
local function sammle()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return false
	end

	local orb = aktiveQuelle()
	if not orb then
		return false -- zwischen zwei Runden gibt es kurz keine Quelle
	end

	local abstand = (root.Position - orb.Position).Magnitude
	if abstand > ABSORB_DISTANZ then
		-- Ziel auf Bodenhöhe der Figur: MoveTo auf die Höhe des Orbs liesse den Humanoid
		-- gegen die Plattform laufen statt darauf.
		humanoid:MoveTo(Vector3.new(orb.Position.X, root.Position.Y, orb.Position.Z))
		return false
	end
	return true
end

-- ===== Die Schleife =====
local function starte()
	laufNummer += 1
	local meinLauf = laufNummer

	task.spawn(function()
		local saugt = false
		while aktiv and meinLauf == laufNummer do
			local station = aktiveStation()
			if not station then
				break -- Station verlassen: die Automatik endet mit ihr
			end

			if station == "Arm" then
				schlage()
			elseif station == "Leg" then
				springe()
			else
				local willSaugen = sammle()
				if willSaugen ~= saugt then
					saugt = willSaugen
					setzeAbsorbieren(saugt)
				end
			end

			task.wait(TICK)
		end

		if saugt then
			setzeAbsorbieren(false) -- nie im Saugen stehen bleiben
		end
		aktiv = false
	end)
end

-- ===== Der Knopf sitzt IM Trainingsfeld =====
-- In der Kopfzeile von GameHud.StatsRowFrame, links neben dem Abbruch-Knopf. Dort steht
-- ohnehin alles, was das Training betrifft: Titel, die drei Kraftzeilen, das X zum
-- Verlassen. Ein eigener Knopf irgendwo am Bildschirmrand waere ein zweiter Ort fuer
-- dieselbe Sache gewesen.
--
-- Das Feld gehoert einem anderen Skript. Deshalb wird es GESUCHT und nicht vorausgesetzt:
-- kommt es nicht, bleibt die Automatik eben ohne Knopf, statt dass dieses Skript haengt.
local kopfzeile = nil
do
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("GameHud", 20)
	kopfzeile = hud and hud:WaitForChild("StatsRowFrame", 10) or nil
end

if not kopfzeile then
	warn("[Kaiju] Auto-Training: GameHud.StatsRowFrame nicht gefunden -- kein Knopf.")
	return
end

local knopf = Instance.new("TextButton")
knopf.Name = "AutoTrainButton"
-- Links neben dem Abbruch-Knopf: der ist 30 breit und sitzt mit 10 Rand aussen.
knopf.Size = UDim2.new(0, 96, 0, 26)
knopf.AnchorPoint = Vector2.new(1, 0)
knopf.Position = UDim2.new(1, -10 - 34, 0, 6)
knopf.AutoButtonColor = false
knopf.Visible = false
knopf.Text = ""
knopf.Parent = kopfzeile
local _, knopfRand = HudChrome.Panel(knopf, {
	radius = HudChrome.Radius.Small,
	fill = HudChrome.Color.PanelRaised,
	transparency = 0,
})

local beschriftung = Instance.new("TextLabel")
beschriftung.Size = UDim2.new(1, 0, 1, 0)
beschriftung.BackgroundTransparency = 1
beschriftung.Parent = knopf
HudChrome.Label(beschriftung, 13)

-- Kurz halten: der Knopf ist 96 Pixel breit und teilt sich die Kopfzeile mit Titel und
-- Abbruch. "AUTO" sagt genug -- WAS automatisch laeuft, sagt die Station, in der man steht.
local TEXTE = {
	Arm = "AUTO PUNCH",
	Leg = "AUTO JUMP",
	Body = "AUTO GATHER",
}

local function zeichne()
	local station = aktiveStation()
	knopf.Visible = station ~= nil
	if not station then
		return
	end
	beschriftung.Text = aktiv and "STOP" or (TEXTE[station] or "AUTO")
	beschriftung.TextColor3 = aktiv and HudChrome.Color.Ready or HudChrome.Color.TextPrimary
	knopfRand.Color = aktiv and HudChrome.Color.Ready or HudChrome.Color.BorderDim
end

knopf.MouseButton1Click:Connect(function()
	if aktiv then
		aktiv = false
		laufNummer += 1 -- laufende Schleife abmelden
	elseif aktiveStation() then
		aktiv = true
		starte()
	end
	zeichne()
end)

-- Beim Verlassen der Station hört die Automatik auf -- sonst schlüge die Figur draussen
-- weiter zu, und zwar auf Häuser.
local function stationWechselte()
	if not aktiveStation() then
		aktiv = false
		laufNummer += 1
	end
	zeichne()
end

player:GetAttributeChangedSignal("TrainingStat"):Connect(stationWechselte)
player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(stationWechselte)
player.CharacterAdded:Connect(stationWechselte)

-- Die Automatik prüft ihren eigenen Zustand ohnehin je Durchlauf; dieser Takt hält nur die
-- Beschriftung aktuell, falls sie sich von selbst beendet hat.
task.spawn(function()
	while true do
		zeichne()
		task.wait(0.25)
	end
end)

print("[Kaiju Debug] Auto-Training bereit -- Knopf erscheint an Arm-, Bein- und Koerper-Station.")
