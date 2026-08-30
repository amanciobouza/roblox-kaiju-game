-- VERSION: 2026-08-26 #3
-- LocalScript: PrologueLetterboxClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Zeigt schwarze, kinoartige Filmstreifen (oben/unten) UND blendet das komplette HUD aus
-- -- AUSSER der Lebensanzeige, die sichtbar bleibt -- beides synchron ausgelöst, sobald
-- der Kaiju beginnt, kontinuierlich Leben zu verlieren ("The Fall", siehe
-- PrologueOrchestrator.lua -- SetPrologueLetterboxEvent), nicht schon beim Prolog-Start.
-- Beides wird wieder eingeblendet/entfernt, sobald der Spieler am Ende die volle
-- Kontrolle zurückerhält.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local SetPrologueLetterboxEvent = RemoteEventUtils.GetOrCreate("SetPrologueLetterboxEvent")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BAR_HEIGHT_FRACTION = 0.09 -- Anteil der Bildschirmhöhe pro Balken (oben/unten je gleich)
local FADE_DURATION = 0.6

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PrologueLetterboxGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40 -- unter der Warteschlangen-Anzeige (50), über dem normalen HUD
screenGui.Parent = playerGui

local function createBar(name, anchorTop)
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.Size = UDim2.new(1, 0, BAR_HEIGHT_FRACTION, 0)
	bar.Position = anchorTop and UDim2.new(0, 0, 0, 0) or UDim2.new(0, 0, 1, 0)
	bar.AnchorPoint = anchorTop and Vector2.new(0, 0) or Vector2.new(0, 1)
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BackgroundTransparency = 1 -- startet unsichtbar, wird erst bei "The Fall" eingeblendet
	bar.BorderSizePixel = 0
	bar.ZIndex = 5
	bar.Parent = screenGui
	return bar
end

local topBar = createBar("TopBar", true)
local bottomBar = createBar("BottomBar", false)

-- Andere HUD-ScreenGuis (nicht Health-bezogen), die komplett aus-/eingeblendet werden --
-- siehe die jeweiligen LocalScripts für die genauen Namen.
local OTHER_HUD_GUI_NAMES = {
	"SpecialAttackGui", -- Punch/Sprung/Fokus/Area-Buttons
	"CityAlertHudGui", -- Alert-Level-Anzeige
	"EnergyTypesGui", -- Energie-Typ-Legende
	"NavigationGui", -- Kompass/Karte
	"EnergyAbsorbGui", -- Absorptions-Eingabe-Hinweis
}

-- Namen der Kind-Elemente von "GameHud", die zusammen mit Health im selben Cluster
-- liegen (siehe SkinSelectionGui.lua -- "PlayerStatusCluster" enthält Level + Health +
-- XP-Bar zusammen) -- nur diese beiden werden versteckt, "HealthFrame" bleibt sichtbar.
local STATUS_CLUSTER_HIDE_NAMES = { "LevelLabel", "BarBackground" }

local activeTweens = {}
local function setVisible(visible)
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end
	activeTweens = {}

	local targetTransparency = visible and 0 or 1
	for _, bar in ipairs({ topBar, bottomBar }) do
		local tween = TweenService:Create(
			bar,
			TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ BackgroundTransparency = targetTransparency }
		)
		tween:Play()
		table.insert(activeTweens, tween)
	end

	local hudShouldBeVisible = not visible

	-- Haupt-HUD (GameHud): alle direkten Kind-Elemente ausblenden AUSSER dem Status-
	-- Cluster -- dort wiederum nur Level/XP verstecken, die Health-Bar bleibt immer
	-- sichtbar.
	local gameHud = playerGui:FindFirstChild("GameHud") or playerGui:WaitForChild("GameHud", 3)
	if gameHud then
		for _, child in ipairs(gameHud:GetChildren()) do
			if child.Name == "PlayerStatusCluster" then
				for _, subName in ipairs(STATUS_CLUSTER_HIDE_NAMES) do
					local subChild = child:FindFirstChild(subName)
					if subChild then
						subChild.Visible = hudShouldBeVisible
					end
				end
			elseif child:IsA("GuiObject") then
				child.Visible = hudShouldBeVisible
			end
		end
	end

	-- Andere HUD-ScreenGuis komplett aus-/einblenden.
	for _, guiName in ipairs(OTHER_HUD_GUI_NAMES) do
		local gui = playerGui:FindFirstChild(guiName)
		if gui then
			gui.Enabled = hudShouldBeVisible
		end
	end
end

SetPrologueLetterboxEvent.OnClientEvent:Connect(function(visible)
	setVisible(visible)
end)