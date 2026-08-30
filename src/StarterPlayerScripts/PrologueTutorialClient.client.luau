-- VERSION: 2026-08-26 #3
-- CHANGE: Absorb-Schwelle auf 5000 erhoeht
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Zeigt die Tutorial-Checkliste nach der Intro-Kinematik im Prolog: PUNCH/JUMP/ABSORB je
-- 2x. Zentrales Panel, wird server-seitig befüllt/aktualisiert (siehe
-- PrologueOrchestrator.lua, playTutorialChecklist -- der Server verfolgt den Fortschritt,
-- dieses Script zeigt ihn nur an).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local ShowTutorialChecklistEvent = RemoteEventUtils.GetOrCreate("ShowTutorialChecklistEvent")
local UpdateTutorialChecklistEvent = RemoteEventUtils.GetOrCreate("UpdateTutorialChecklistEvent")
local HideTutorialChecklistEvent = RemoteEventUtils.GetOrCreate("HideTutorialChecklistEvent")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== GUI-Aufbau =====

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PrologueTutorialGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Fügt einem TextLabel eine schwarze Umrandung hinzu -- nötig für Lesbarkeit, da das
-- Panel KEINEN Hintergrund mehr hat (steht direkt vor der Spielwelt/dem Charakter).
local function applyTextOutline(textLabel)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = textLabel
end

local panel = Instance.new("Frame")
panel.Name = "TutorialPanel"
panel.Size = UDim2.new(0, 260, 0, 220)
panel.AnchorPoint = Vector2.new(0, 0.5)
-- Am linken Bildschirmrand statt mittig -- verdeckt dadurch nicht mehr die Sicht auf
-- den Charakter.
panel.Position = UDim2.new(0, 24, 0.5, 0)
panel.BackgroundTransparency = 1 -- kein Panel-Hintergrund mehr, nur die Texte selbst
panel.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -20, 0, 40)
title.Position = UDim2.new(0, 10, 0, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.Text = "LEARN YOUR POWER"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Parent = panel
applyTextOutline(title)

local rowsFrame = Instance.new("Frame")
rowsFrame.Name = "Rows"
rowsFrame.Size = UDim2.new(1, -20, 1, -60)
rowsFrame.Position = UDim2.new(0, 10, 0, 55)
rowsFrame.BackgroundTransparency = 1
rowsFrame.Parent = panel

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.FillDirection = Enum.FillDirection.Vertical
rowsLayout.Padding = UDim.new(0, 10)
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Parent = rowsFrame

-- Reihenfolge + Anzeige-Namen der Aktionen -- muss mit den Schlüsseln in
-- PrologueOrchestrator.lua (TUTORIAL_TARGETS: Punch/Jump/AbsorbAmount) übereinstimmen.
local ACTION_DISPLAY_NAMES = {
	{ key = "Punch", label = "PUNCH" },
	{ key = "Jump", label = "JUMP" },
	{ key = "AbsorbAmount", label = "HOLD TO ABSORB" },
}

local rowLabels = {} -- key -> TextLabel (für die Fortschrittsanzeige "0/2" etc.)
local rowChecks = {} -- key -> TextLabel (Häkchen-Symbol)

for layoutIndex, actionInfo in ipairs(ACTION_DISPLAY_NAMES) do
	local row = Instance.new("Frame")
	row.Name = actionInfo.key .. "Row"
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutIndex
	row.Parent = rowsFrame

	local checkLabel = Instance.new("TextLabel")
	checkLabel.Name = "Check"
	checkLabel.Size = UDim2.new(0, 36, 1, 0)
	checkLabel.Position = UDim2.new(0, 0, 0, 0)
	checkLabel.BackgroundTransparency = 1
	checkLabel.Font = Enum.Font.FredokaOne
	checkLabel.Text = "☐"
	checkLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	checkLabel.TextScaled = true
	checkLabel.Parent = row
	applyTextOutline(checkLabel)
	rowChecks[actionInfo.key] = checkLabel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(0.62, 0, 1, 0)
	nameLabel.Position = UDim2.new(0, 42, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Text = actionInfo.label
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row
	applyTextOutline(nameLabel)

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "Progress"
	progressLabel.Size = UDim2.new(0.28, 0, 1, 0)
	progressLabel.Position = UDim2.new(0.72, 0, 0, 0)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.FredokaOne
	progressLabel.Text = "0/2"
	progressLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	progressLabel.TextScaled = true
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Parent = row
	applyTextOutline(progressLabel)
	rowLabels[actionInfo.key] = progressLabel
end

local completionLabel = Instance.new("TextLabel")
completionLabel.Name = "Completion"
completionLabel.Size = UDim2.new(1, -20, 0, 40)
completionLabel.Position = UDim2.new(0, 10, 1, -45)
completionLabel.BackgroundTransparency = 1
completionLabel.Font = Enum.Font.FredokaOne
completionLabel.Text = "WELL DONE!"
completionLabel.TextColor3 = Color3.fromRGB(90, 220, 120)
completionLabel.TextScaled = true
completionLabel.TextTransparency = 1
completionLabel.Visible = false
completionLabel.Parent = panel
applyTextOutline(completionLabel)

local currentTargets = { Punch = 2, Jump = 2, AbsorbAmount = 5000 }

local function updateRow(key, value)
	local target = currentTargets[key] or 2
	if rowLabels[key] then
		rowLabels[key].Text = tostring(math.floor(value)) .. "/" .. tostring(target)
	end
	if rowChecks[key] then
		if value >= target then
			rowChecks[key].Text = "☑"
			rowChecks[key].TextColor3 = Color3.fromRGB(90, 220, 120)
		else
			rowChecks[key].Text = "☐"
			rowChecks[key].TextColor3 = Color3.fromRGB(220, 220, 220)
		end
	end
end

-- ===== Event-Handler =====


ShowTutorialChecklistEvent.OnClientEvent:Connect(function(targets)
	currentTargets = targets or currentTargets
	completionLabel.Visible = false
	completionLabel.TextTransparency = 1
	for _, actionInfo in ipairs(ACTION_DISPLAY_NAMES) do
		updateRow(actionInfo.key, 0)
	end
	screenGui.Enabled = true
	panel.Size = UDim2.new(0, 0, 0, 0)
	local openTween = TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 260, 0, 220),
	})
	openTween:Play()
end)

UpdateTutorialChecklistEvent.OnClientEvent:Connect(function(progress)
	if not progress then
		return
	end
	for _, actionInfo in ipairs(ACTION_DISPLAY_NAMES) do
		updateRow(actionInfo.key, progress[actionInfo.key] or 0)
	end
end)

HideTutorialChecklistEvent.OnClientEvent:Connect(function(wasCompleted)
	if wasCompleted then
		completionLabel.Visible = true
		local fadeIn = TweenService:Create(completionLabel, TweenInfo.new(0.3), { TextTransparency = 0 })
		fadeIn:Play()
		task.wait(1.5)
	end

	local closeTween = TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0),
	})
	closeTween:Play()
	closeTween.Completed:Wait()
	screenGui.Enabled = false
end)