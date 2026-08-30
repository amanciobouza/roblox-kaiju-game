-- VERSION: 2026-08-25 #2 (RemoteEventUtils-Umstellung)
-- LocalScript: TeleportHomeClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt einen "🏠 Home"-Button im HUD, der den Spieler zurück zum Spawn-Punkt teleportiert.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local applyComicStyle = ComicStyleUtils.Apply

local player = Players.LocalPlayer
local TeleportHomeEvent = RemoteEventUtils.GetOrCreate("TeleportHomeEvent")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeleportHomeGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local homeButton = Instance.new("TextButton")
homeButton.Name = "HomeButton"
homeButton.Size = UDim2.new(0, 42, 0, 42)
homeButton.AnchorPoint = Vector2.new(1, 0)
homeButton.Position = UDim2.new(1, -16, 0, 16) -- oben rechts, neben der Coins-Anzeige (neue HUD-Spezifikation)
homeButton.BackgroundColor3 = Color3.fromRGB(90, 160, 230)
homeButton.ZIndex = 100
homeButton.Font = Enum.Font.LuckiestGuy
homeButton.TextScaled = true
homeButton.Text = "🏠"
homeButton.Parent = screenGui
applyComicStyle(homeButton, 14, 4)
print("[Kaiju-Debug] TeleportHomeClient: Home-Button erstellt, Parent = " .. homeButton.Parent:GetFullName())

local homeLabel = Instance.new("TextLabel")
homeLabel.Name = "HomeLabel"
homeLabel.Size = UDim2.new(0, 80, 0, 20)
homeLabel.AnchorPoint = Vector2.new(0.5, 0)
homeLabel.Position = UDim2.new(0.5, 0, 1, 2)
homeLabel.BackgroundTransparency = 1
homeLabel.Font = Enum.Font.FredokaOne
homeLabel.TextScaled = true
homeLabel.TextColor3 = Color3.new(1, 1, 1)
homeLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
homeLabel.TextStrokeTransparency = 0
homeLabel.Text = "Home"
homeLabel.Parent = homeButton

homeButton.MouseButton1Click:Connect(function()
	TeleportHomeEvent:FireServer()
end)