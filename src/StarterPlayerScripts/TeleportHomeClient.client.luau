-- VERSION: 2026-08-25 #2 (RemoteEventUtils-Umstellung)
-- LocalScript: TeleportHomeClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt einen "🏠 Home"-Button im HUD, der den Spieler zurück zum Spawn-Punkt teleportiert.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local player = Players.LocalPlayer
local TeleportHomeEvent = RemoteEventUtils.GetOrCreate("TeleportHomeEvent")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeleportHomeGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Der Knopf stand auf Blau mit schwarzem Umriss und trug das Emoji 🏠, darunter eine
-- Beschriftung mit Textumriss. Jetzt derselbe dunkle Grund wie alles andere im HUD, das
-- hochgeladene Symbol darin -- die Beschriftung darunter entfaellt: ein Haus-Symbol in
-- der oberen Ecke braucht kein Wort, und in Scheibe 3 zieht der Knopf ohnehin in die
-- Kopfleiste, wo neben ihm kein Platz fuer eine Zeile ist.
local homeButton = Instance.new("TextButton")
homeButton.Name = "HomeButton"
homeButton.Size = UDim2.new(0, 44, 0, 44)
homeButton.AnchorPoint = Vector2.new(1, 0)
homeButton.Position = UDim2.new(1, -16, 0, 16)
homeButton.AutoButtonColor = false
homeButton.Text = ""
homeButton.ZIndex = 100
homeButton.Parent = screenGui
HudChrome.Panel(homeButton, { radius = HudChrome.Radius.Small })

local homeIcon = HudChrome.IconImage(homeButton, HudChrome.Icon.Home)
homeIcon.Size = UDim2.new(1, -14, 1, -14)
homeIcon.Position = UDim2.new(0, 7, 0, 7)
homeIcon.ZIndex = 101

homeButton.MouseButton1Click:Connect(function()
	TeleportHomeEvent:FireServer()
end)