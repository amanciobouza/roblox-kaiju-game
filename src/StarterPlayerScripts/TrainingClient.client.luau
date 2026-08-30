-- VERSION: 2026-08-25 #1 (RemoteEventUtils-Umstellung)
-- LocalScript: TrainingClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Solange eine Trainingsstation aktiv ist (Attribut "TrainingStat" gesetzt), sendet jeder
-- Mausklick ein Trainings-Signal an den Server und spielt die passende Animation ab.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local TrainClickEvent = RemoteEventUtils.GetOrCreate("TrainClickEvent")
local StopTrainingEvent = RemoteEventUtils.GetOrCreate("StopTrainingEvent")

-- WICHTIG: Trag hier deine eigenen Animation-IDs ein, sobald du sie im Animation Editor
-- erstellt hast (Format: "rbxassetid://123456789"). Ohne ID wird einfach keine Animation
-- abgespielt, das Training funktioniert trotzdem.
local TRAINING_ANIMATIONS = {
	Leg = "rbxassetid://0",
	Arm = "rbxassetid://0",
	Body = "rbxassetid://0",
}

local currentTrack = nil

local function playTrainAnimation(statType)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animId = TRAINING_ANIMATIONS[statType]
	if not animId or animId == "" or animId == "rbxassetid://0" then
		return
	end

	if currentTrack then
		currentTrack:Stop()
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	currentTrack = humanoid:LoadAnimation(animation)
	currentTrack:Play()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		if player:GetAttribute("TrainingStat") then
			StopTrainingEvent:FireServer()
		end
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local statType = player:GetAttribute("TrainingStat")
	if not statType then
		return -- keine Station aktiv -> normaler Klick macht hier nichts
	end

	if statType == "Arm" then
		return -- Arm-Training: AttackClient.lua feuert TrainClickEvent selbst (kennt den exakten Combo-Schritt aus demselben Klick, kein Timing-Risiko zwischen zwei separaten Scripts)
	end

	TrainClickEvent:FireServer()
	playTrainAnimation(statType)
end)

-- Während des Trainings soll sich der Spieler nur aufs Training konzentrieren -- Bewegung
-- ist schon serverseitig gesperrt (WalkSpeed=0), zusätzlich hier den Kamera-Zoom sperren
-- (weder rein- noch rauszoomen möglich).
local originalMinZoom, originalMaxZoom

player:GetAttributeChangedSignal("TrainingStat"):Connect(function()
	local isTraining = player:GetAttribute("TrainingStat") ~= nil

	if isTraining then
		originalMinZoom = player.CameraMinZoomDistance
		originalMaxZoom = player.CameraMaxZoomDistance
		-- Zoom auf der AKTUELLEN Distanz einfrieren (Min = Max = aktueller Wert), statt
		-- eine willkürliche feste Distanz zu erzwingen -- fühlt sich natürlicher an.
		local currentZoom = (workspace.CurrentCamera and workspace.CurrentCamera.Focus.Position - workspace.CurrentCamera.CFrame.Position).Magnitude
			or player.CameraMinZoomDistance
		player.CameraMinZoomDistance = currentZoom
		player.CameraMaxZoomDistance = currentZoom
	else
		if not player:GetAttribute("TrainingStat") and currentTrack then
			currentTrack:Stop()
			currentTrack = nil
		end
		if originalMinZoom and originalMaxZoom then
			player.CameraMinZoomDistance = originalMinZoom
			player.CameraMaxZoomDistance = originalMaxZoom
		end
	end
end)