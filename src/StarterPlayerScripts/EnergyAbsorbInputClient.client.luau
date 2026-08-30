-- LocalScript: EnergyAbsorbInputClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Meldet dem Server, ob der Spieler gerade aktiv Energie "saugt" -- ein eigener,
-- gehaltener Bildschirm-Button (PC UND Mobile). Bewusst KEINE Maustaste mehr -- rechte
-- Maustaste wird für die Kameraperspektive gebraucht. Ohne gehaltenen Button fliesst
-- keine Energie, egal wie nah man an einer Feuerquelle steht (siehe
-- EnergyCollectionHandler.lua).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SetAbsorbingEvent = ReplicatedStorage:WaitForChild("SetAbsorbingEvent")

local isAbsorbing = false

local function setAbsorbing(value)
	if isAbsorbing == value then
		return
	end
	isAbsorbing = value
	SetAbsorbingEvent:FireServer(value)
end

-- Sicherheitsnetz: falls der Fokus verloren geht (z.B. Alt-Tab, Menü öffnen) während der
-- Button gehalten wird, bleibt sonst evtl. "IsAbsorbing" fälschlich hängen.
UserInputService.WindowFocusReleased:Connect(function()
	setAbsorbing(false)
end)

-- ===== Eigener Bildschirm-Button, immer sichtbar (PC + Mobile) =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EnergyAbsorbGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local absorbButton = Instance.new("TextButton")
absorbButton.Name = "AbsorbButton"
absorbButton.Size = UDim2.new(0, 90, 0, 90)
absorbButton.AnchorPoint = Vector2.new(1, 1)
absorbButton.Position = UDim2.new(1, -20, 1, -140)
absorbButton.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
absorbButton.AutoButtonColor = false
absorbButton.Font = Enum.Font.LuckiestGuy
absorbButton.TextScaled = true
absorbButton.Text = "🌀"
absorbButton.TextColor3 = Color3.new(1, 1, 1)
absorbButton.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = absorbButton
local stroke = Instance.new("UIStroke")
stroke.Thickness = 3
stroke.Color = Color3.new(0, 0, 0)
stroke.Parent = absorbButton

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0, 18)
label.Position = UDim2.new(0, 0, 1, 4)
label.BackgroundTransparency = 1
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeColor3 = Color3.new(0, 0, 0)
label.TextStrokeTransparency = 0.4
label.Text = "Absorb (F)"
label.Parent = absorbButton

local function onPressStart()
	setAbsorbing(true)
	absorbButton.BackgroundColor3 = Color3.fromRGB(50, 140, 220)
end

local function onPressEnd()
	setAbsorbing(false)
	absorbButton.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
end

-- Reagiert auf Maus (PC) UND Touch (Mobile) gleichermassen -- ein Button für beide
-- Plattformen, statt getrennter Maustasten-/Touch-Logik.
absorbButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		onPressStart()
	end
end)

absorbButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		onPressEnd()
	end
end)

-- Falls die Maus den Button verlässt, WÄHREND sie gedrückt gehalten wird (z.B. schnell
-- wegbewegt), soll das Saugen trotzdem enden -- sonst könnte es fälschlich aktiv bleiben.
absorbButton.MouseLeave:Connect(function()
	if isAbsorbing then
		onPressEnd()
	end
end)

-- ===== Tastenkürzel: F gehalten macht dasselbe wie der Button =====
local ABSORB_KEY = Enum.KeyCode.F

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == ABSORB_KEY then
		onPressStart()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == ABSORB_KEY then
		onPressEnd()
	end
end)