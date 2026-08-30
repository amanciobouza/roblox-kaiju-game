-- VERSION: 2026-08-25 #1 (RemoteEventUtils-Umstellung)
-- LocalScript: MutationClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt eine Benachrichtigung, sobald eine Strahlungs-Mutation ausgelöst wurde (siehe
-- EnergyTypesHandler.lua), und wendet den visuellen "Radiant Plates"-Effekt an (stärkeres
-- Glühen), falls diese Mutation gewählt wurde.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local MutationTriggeredEvent = RemoteEventUtils.GetOrCreate("MutationTriggeredEvent")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MutationGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local banner = Instance.new("TextLabel")
banner.Name = "MutationBanner"
banner.Size = UDim2.new(0, 480, 0, 70)
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, 0.35, 0)
banner.BackgroundColor3 = Color3.fromRGB(160, 255, 60)
banner.Font = Enum.Font.LuckiestGuy
banner.TextScaled = true
banner.TextColor3 = Color3.fromRGB(15, 40, 5)
banner.TextWrapped = true
banner.Text = ""
banner.BackgroundTransparency = 1
banner.TextTransparency = 1
banner.ZIndex = 80
banner.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 16)
corner.Parent = banner
local stroke = Instance.new("UIStroke")
stroke.Thickness = 3
stroke.Color = Color3.new(0, 0, 0)
stroke.Parent = banner

MutationTriggeredEvent.OnClientEvent:Connect(function(label)
	banner.Text = "☢️ MUTATION: " .. label
	banner.BackgroundTransparency = 0
	banner.TextTransparency = 0
	TweenService:Create(banner, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 500, 0, 76),
	}):Play()

	task.delay(4, function()
		local fadeOut = TweenService:Create(banner, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		fadeOut:Play()
	end)
end)

-- ===== Radiant-Plates-Effekt: stärkeres Glühen, falls diese Mutation aktiv ist =====
local function applyRadiantPlatesIfActive(character)
	if not player:GetAttribute("MutationRadiantPlates") then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	if rootPart:FindFirstChild("RadiantPlatesLight") then
		return -- schon vorhanden
	end

	local light = Instance.new("PointLight")
	light.Name = "RadiantPlatesLight"
	light.Color = Color3.fromRGB(160, 255, 60)
	light.Brightness = 4
	light.Range = 16
	light.Parent = rootPart
end

player.CharacterAdded:Connect(applyRadiantPlatesIfActive)
if player.Character then
	applyRadiantPlatesIfActive(player.Character)
end
player:GetAttributeChangedSignal("MutationRadiantPlates"):Connect(function()
	if player.Character then
		applyRadiantPlatesIfActive(player.Character)
	end
end)