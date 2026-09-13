-- VERSION: 2026-09-13 #1
-- LocalScript: MutationClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Meldet eine ausgelöste Strahlungs-Mutation (siehe EnergyTypesHandler.lua) und wendet den
-- "Radiant Plates"-Effekt an (stärkeres Glühen), falls diese Mutation gewählt wurde.
--
-- Die Meldung steht in der BILDMITTE und folgt damit der Regel aus HudCenterNotice: die
-- Mitte gehört dem, was eingetreten ist. Eine Mutation ist genau das -- sie ändert die
-- Lage, und man kann nichts dagegen tun, man kann es nur zur Kenntnis nehmen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local HudCenterNotice = require(ReplicatedStorage:WaitForChild("HudCenterNotice"))
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local MutationTriggeredEvent = RemoteEventUtils.GetOrCreate("MutationTriggeredEvent")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MutationGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Die Farbe der Strahlung, wie ueberall sonst im Spiel. Das Band traegt sie gedunkelt --
-- ein Band aus dem hellen Gruen waere bei 45 Prozent Deckkraft ein Schleier, auf dem keine
-- Schrift mehr steht. Der Titel bekommt den hellen Ton.
local MUTATION_BAND = Color3.fromRGB(46, 92, 18)
local MUTATION_HELL = Color3.fromRGB(160, 255, 60)

local BAND_BREITE = 640
local BAND_HOEHE = 88
local STANDZEIT = 3.0 -- dieselbe wie bei der Alarmmeldung: die Mitte hat einen Takt

local banner = Instance.new("Frame")
banner.Name = "MutationBanner"
banner.Size = UDim2.new(0, BAND_BREITE, 0, BAND_HOEHE)
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, HudCenterNotice.Y_SCALE, 0)
banner.Visible = false
banner.ZIndex = 80
banner.Parent = screenGui
HudCenterNotice.ApplyBandLook(banner, MUTATION_BAND, 0.35)
banner.BackgroundTransparency = 1

local caption = Instance.new("TextLabel")
caption.Name = "Caption"
caption.Size = UDim2.new(1, -40, 0, 18)
caption.Position = UDim2.new(0, 20, 0, 14)
caption.BackgroundTransparency = 1
caption.ZIndex = 81
caption.Text = "MUTATION"
caption.Parent = banner
HudChrome.Label(caption, 15)
caption.TextColor3 = HudChrome.Color.TextSecondary

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "MutationTitle"
titleLabel.Size = UDim2.new(1, -40, 0, 36)
titleLabel.Position = UDim2.new(0, 20, 0, 36)
titleLabel.BackgroundTransparency = 1
titleLabel.ZIndex = 81
titleLabel.Text = ""
titleLabel.Parent = banner
HudChrome.Label(titleLabel, 30)
titleLabel.TextColor3 = MUTATION_HELL

MutationTriggeredEvent.OnClientEvent:Connect(function(label)
	task.spawn(function()
		-- Warten, falls die Mitte gerade einer Alarmmeldung gehoert. Eine Mutation ist
		-- nicht dringend -- sie kann die paar Sekunden warten, statt sich darueber zu
		-- legen. Nach acht Sekunden erscheint sie trotzdem: lieber spaet als gar nicht.
		local gewartet = 0
		while HudCenterNotice.IsBusy() and gewartet < 8 do
			task.wait(0.25)
			gewartet += 0.25
		end
		HudCenterNotice.SetBusy(true)

		titleLabel.Text = string.upper(label)
		banner.Visible = true
		banner.BackgroundTransparency = 1
		banner.Size = UDim2.new(0, BAND_BREITE * 0.75, 0, BAND_HOEHE)
		caption.TextTransparency = 1
		titleLabel.TextTransparency = 1

		TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, BAND_BREITE, 0, BAND_HOEHE),
			BackgroundTransparency = 0.35,
		}):Play()
		TweenService:Create(caption, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		TweenService:Create(titleLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()

		task.wait(0.35 + STANDZEIT)

		TweenService:Create(banner, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(caption, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(titleLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()

		task.wait(0.45)
		banner.Visible = false
		HudCenterNotice.SetBusy(false)
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