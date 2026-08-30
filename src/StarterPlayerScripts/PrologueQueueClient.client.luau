-- VERSION: 2026-08-26 #1
-- LocalScript: PrologueQueueClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Zeigt an, an welcher Position ein Spieler in der Prolog-Warteschlange steht (siehe
-- PrologueOrchestrator.lua -- PrologueCity ist ein geteilter Bereich, nur ein Spieler
-- kann sie gleichzeitig durchlaufen). Blendet sich automatisch aus, sobald der Spieler
-- an der Reihe ist oder die Warteschlange verlässt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local PrologueQueueStatusEvent = RemoteEventUtils.GetOrCreate("PrologueQueueStatusEvent")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PrologueQueueGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Enabled = false
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Container"
container.Size = UDim2.new(0.5, 0, 0, 90)
container.Position = UDim2.new(0.5, 0, 0.12, 0)
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
container.BackgroundTransparency = 0.3
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = container

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, -20, 0, 30)
titleLabel.Position = UDim2.new(0.5, 0, 0, 10)
titleLabel.AnchorPoint = Vector2.new(0.5, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.LuckiestGuy
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.fromRGB(255, 240, 150)
titleLabel.TextStrokeTransparency = 0.5
titleLabel.Text = "WARTESCHLANGE"
titleLabel.Parent = container

local positionLabel = Instance.new("TextLabel")
positionLabel.Name = "PositionLabel"
positionLabel.Size = UDim2.new(1, -20, 0, 36)
positionLabel.Position = UDim2.new(0.5, 0, 0, 44)
positionLabel.AnchorPoint = Vector2.new(0.5, 0)
positionLabel.BackgroundTransparency = 1
positionLabel.Font = Enum.Font.GothamBold
positionLabel.TextScaled = true
positionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
positionLabel.TextStrokeTransparency = 0.5
positionLabel.Text = ""
positionLabel.Parent = container

PrologueQueueStatusEvent.OnClientEvent:Connect(function(position, total)
	if position == nil then
		screenGui.Enabled = false
		return
	end
	positionLabel.Text = "Position " .. tostring(position) .. " von " .. tostring(total)
	screenGui.Enabled = true
end)