-- VERSION: 2026-09-13 #1
-- LocalScript: KaijuStageOneInputClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Sprung und Laufen für das getragene Kaiju-Modell (Primal Beast, Storm Hunter, ...).
--
-- ===== Warum das nötig ist =====
-- Der Installer aus dem Workshop setzt Humanoid.JumpPower auf 0 und AutoJumpEnabled auf
-- false: das Rig bringt einen eigenen Sprung mit (Anlauf, Flugphase, Landung mit
-- Aufschlag), und der Standardsprung von Roblox würde mitten hineinfahren. Ohne dieses
-- Skript könnte die Figur also gar nicht mehr springen -- die Leertaste liefe ins Leere.
--
-- Der Angriff läuft NICHT hier, sondern im AttackClient: dort sitzt die Eingabe bereits,
-- und sie muss vom alten Weg WEGgeleitet werden, statt zusätzlich zu laufen.
--
-- ===== Warum hier nicht die Eingabe des Pakets läuft =====
-- Das Paket bringt eine eigene mit (InstallInput), die aber den Fokus auf E legt -- dort
-- liegt in diesem Spiel schon der Flächenangriff. Deshalb bleibt sie aus, und hier steht
-- nur das Nötigste: Sprung und Laufen. Beides kollidiert mit keiner Taste des Spiels.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local StageModels = require(ReplicatedStorage:WaitForChild("StageModels"))
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

-- Meldet dem Server den Beginn eines Sprungs, damit er den Sprung-Cooldown setzt
-- (HouseHandler). Dasselbe Ereignis, das auch der Avatar-Sprung benutzt.
local PlayerJumpedEvent = RemoteEventUtils.GetOrCreate("PlayerJumpedEvent")

local player = Players.LocalPlayer

-- Das Modell wird bei jedem Zugriff frisch gesucht: es entsteht und verschwindet mit dem
-- Stufenwechsel, eine gemerkte Referenz zeigte danach auf etwas Zerstörtes.
--
-- Gesucht wird über StageModels, NICHT über einen festen Namen. Hier stand einmal
-- "Stage_1_Primal_Beast" -- und als der Storm Hunter ab Stufe 2 dazukam, fand dieses
-- Skript gar nichts mehr und der Sprung fiel still aus.
local function kaijuModel()
	return StageModels.FindEquipped(player.Character)
end

local function remoteOf(model, name)
	local remote = model and model:FindFirstChild(name)
	return (remote and remote:IsA("RemoteEvent")) and remote or nil
end

-- Die flache Laufrichtung der Figur, wie das Rig sie erwartet: Länge höchstens 1, Y
-- praktisch null. Beides prüft der Server nach; ein Vektor daneben wird verworfen.
local function moveDirection()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return Vector3.zero
	end
	local direction = humanoid.MoveDirection
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.05 then
		return Vector3.zero
	end
	return flat.Unit
end

-- ===== Springen =====
-- Über die Sprung-Aktion statt über eine feste Taste: so gilt sie auch für den
-- Sprung-Knopf auf dem Telefon, den Roblox selbst einblendet.
--
-- ===== Der Cooldown des Spiels gilt =====
-- Das Rig lässt einen Sprung alle 0.25 Sekunden zu, das Spiel hat einen deutlich längeren
-- Sprung-Cooldown und zeigt ihn am Knopf an. Ohne diese Prüfung liefen beide nebeneinander:
-- die Sanduhr lief, während man längst wieder springen konnte -- und sie lief ausserdem
-- los, wenn man nur eine Kante hinunterfiel, weil die Meldung am Freefall-Zustand hing.
--
-- Jetzt entscheidet die Sperre des Spiels, und gemeldet wird der Sprung genau dann, wenn er
-- wirklich angestossen wird. Dieselbe Meldung wie beim Avatar-Sprung: PlayerJumpedEvent in
-- SpecialAttackClient, gesetzt wird der Wert im HouseHandler.
local function requestJump()
	local model = kaijuModel()
	local remote = remoteOf(model, "RequestJump")
	if not remote then
		return false
	end
	if Workspace:GetServerTimeNow() < (player:GetAttribute("JumpAttackReadyAt") or 0) then
		return false
	end
	PlayerJumpedEvent:FireServer()
	remote:FireServer(moveDirection())
	return true
end

UserInputService.JumpRequest:Connect(requestJump)

-- ===== Derselbe Sprung fuer alle, die keine Taste sind =====
-- JumpRequest feuert NUR bei echter Eingabe -- Leertaste oder der Sprungknopf, den Roblox
-- auf dem Telefon einblendet. `humanoid.Jump = true` loest es NICHT aus, und genau das tut
-- der Sprungknopf des HUD. Bei einem Kaiju ist die Sprungkraft des Avatars zudem auf null
-- gesetzt (der Installer macht das), der Sprung kommt allein vom Rig -- der Knopf lief also
-- ins Leere, sobald ein Modell haengt.
--
-- Deshalb hier ein Kanal fuer alles, was keine Taste ist: HUD-Knopf, Auto-Training, Prolog.
-- Gleiches Muster wie TouchAttackButtonPressed in AttackClient.
local requestJumpEvent = Instance.new("BindableEvent")
requestJumpEvent.Name = "RequestKaijuJump"
requestJumpEvent.Parent = player
requestJumpEvent.Event:Connect(requestJump)

-- ===== Keine Luftsteuerung mehr =====
-- Bis Paketversion 1.1.0 musste der Client waehrend Windup und Air alle 0.08 Sekunden
-- SteerJump schicken, sonst liess sich der Sprung nicht lenken. Seit 1.1.1 bleibt die
-- native Robloxsteuerung im Flug aktiv; SteerJump wird nur noch aus Vertraeglichkeit
-- angenommen und ueberschreibt nichts mehr. Ein Dauerstrom von zwoelf Ereignissen je
-- Sekunde ohne Wirkung ist deshalb ersatzlos entfallen.

-- ===== Laufen =====
-- Gesendet wird nur bei einem WECHSEL, nicht in jedem Bild: das Ereignis hat serverseitig
-- keine Ratenbegrenzung (siehe Installer, SetRunning mit Abstand 0), ein Dauerstrom wäre
-- also ungebremst.
--
-- Der Zustand wird zurückgesetzt, sobald die Figur wechselt oder das Fenster den Fokus
-- verliert -- sonst liefe der Kaiju weiter, weil das Loslassen der Taste nie ankam.
local running = false

local function setRunning(value)
	if value == running then
		return
	end
	local model = kaijuModel()
	local remote = remoteOf(model, "SetRunning")
	if not remote then
		running = false
		return
	end
	running = value
	remote:FireServer(value)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setRunning(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setRunning(false)
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	setRunning(false)
end)

player.CharacterAdded:Connect(function()
	running = false
end)
