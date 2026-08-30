-- LocalScript: LoadingScreen
-- Ort in Studio: ReplicatedFirst (NICHT StarterPlayerScripts!)
-- Zeigt einen eigenen Ladebildschirm (Bild + Fortschrittsbalken mit Status-Text), solange
-- die wichtigsten Spiel-Elemente noch laden. Ersetzt Robloxs Standard-Ladebildschirm.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Robloxs Standard-Ladebildschirm sofort entfernen, damit unserer stattdessen läuft
ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer

local function applyComicStyle(guiObject, cornerRadius, strokeThickness)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cornerRadius or 16)
	corner.Parent = guiObject

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = strokeThickness or 4
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = guiObject

	return corner, stroke
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreenGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000 -- ganz oben, über allem anderen
screenGui.Parent = player:WaitForChild("PlayerGui")

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
background.BorderSizePixel = 0
background.ZIndex = 1
background.Parent = screenGui

-- WICHTIG: Trag hier dein eigenes Spielbild ein (Asset-ID aus dem Creator Store, oder ein
-- selbst hochgeladenes Bild -- Rechtsklick auf ein Bild im Explorer -> Copy Asset ID, oder
-- über "Bilder" beim Veröffentlichen hochladen).
local GAME_IMAGE_ID = "rbxassetid://93529420608088"

local gameImage = Instance.new("ImageLabel")
gameImage.Name = "GameImage"
gameImage.Size = UDim2.new(0, 500, 0, 500)
gameImage.AnchorPoint = Vector2.new(0.5, 0.5)
gameImage.Position = UDim2.new(0.5, 0, 0.42, 0)
gameImage.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
gameImage.Image = GAME_IMAGE_ID
gameImage.ScaleType = Enum.ScaleType.Crop
gameImage.ZIndex = 2
gameImage.Parent = background
applyComicStyle(gameImage, 24, 6)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(0, 500, 0, 60)
titleLabel.AnchorPoint = Vector2.new(0.5, 1)
titleLabel.Position = UDim2.new(0.5, 0, 0.42, -260)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.LuckiestGuy
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
titleLabel.TextStrokeTransparency = 0
titleLabel.Text = "🦖 KAIJU GAME"
titleLabel.ZIndex = 2
titleLabel.Parent = background

-- ===== Fortschrittsbalken =====
local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.Size = UDim2.new(0, 500, 0, 34)
barBackground.AnchorPoint = Vector2.new(0.5, 0)
barBackground.Position = UDim2.new(0.5, 0, 0.72, 0)
barBackground.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
barBackground.ZIndex = 2
barBackground.Parent = background
applyComicStyle(barBackground, 16, 4)

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
barFill.BorderSizePixel = 0
barFill.ZIndex = 3
barFill.Parent = barBackground
applyComicStyle(barFill, 14, 0)

local percentLabel = Instance.new("TextLabel")
percentLabel.Size = UDim2.new(1, 0, 1, 0)
percentLabel.BackgroundTransparency = 1
percentLabel.Font = Enum.Font.LuckiestGuy
percentLabel.TextScaled = true
percentLabel.TextColor3 = Color3.new(1, 1, 1)
percentLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
percentLabel.TextStrokeTransparency = 0
percentLabel.Text = "0%"
percentLabel.ZIndex = 4
percentLabel.Parent = barBackground

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(0, 500, 0, 30)
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.Position = UDim2.new(0.5, 0, 0.72, 42)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.FredokaOne
statusLabel.TextScaled = true
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
statusLabel.Text = "Verbinde..."
statusLabel.ZIndex = 2
statusLabel.Parent = background

-- ===== Ladeschritte =====
-- Jeder Schritt hat einen Anzeige-Text und eine Funktion, die wartet, bis dieser Schritt
-- fertig ist. Reihenfolge = Reihenfolge der Fortschrittsanzeige.
local function waitForGui(name, timeout)
	local playerGui = player:WaitForChild("PlayerGui")
	local startTime = os.clock()
	while not playerGui:FindFirstChild(name) do
		if os.clock() - startTime > (timeout or 15) then
			break -- nicht ewig hängen bleiben, falls z.B. ein Script fehlt
		end
		task.wait(0.1)
	end
end

local LOADING_STEPS = {
	{
		text = "Verbinde mit Server...",
		action = function()
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end
		end,
	},
	{
		text = "Erschaffe deinen Kaiju...",
		action = function()
			if not player.Character then
				player.CharacterAdded:Wait()
			end
		end,
	},
	{
		text = "Baue die Spiel-Oberfläche...",
		action = function()
			waitForGui("GameHud")
		end,
	},
	{
		text = "Richte Navigation ein...",
		action = function()
			waitForGui("NavigationGui")
		end,
	},
	{
		text = "Lade Spezialangriffe...",
		action = function()
			waitForGui("SpecialAttackGui")
		end,
	},
	{
		text = "Fast fertig...",
		action = function()
			task.wait(0.3)
		end,
	},
}

local function setProgress(ratio, text)
	ratio = math.clamp(ratio, 0, 1)
	TweenService:Create(barFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()
	percentLabel.Text = math.floor(ratio * 100) .. "%"
	if text then
		statusLabel.Text = text
	end
end

task.spawn(function()
	local stepCount = #LOADING_STEPS
	for index, step in ipairs(LOADING_STEPS) do
		setProgress((index - 1) / stepCount, step.text)
		local ok = pcall(step.action)
		if not ok then
			warn("[LoadingScreen] Schritt '" .. step.text .. "' fehlgeschlagen, mache trotzdem weiter.")
		end
		setProgress(index / stepCount)
	end

	setProgress(1, "Los geht's!")
	task.wait(0.5)

	local fadeTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(background, fadeTweenInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(gameImage, fadeTweenInfo, { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
	TweenService:Create(titleLabel, fadeTweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(barBackground, fadeTweenInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(barFill, fadeTweenInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(percentLabel, fadeTweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(statusLabel, fadeTweenInfo, { TextTransparency = 1 }):Play()

	task.wait(0.6)
	screenGui:Destroy()
end)