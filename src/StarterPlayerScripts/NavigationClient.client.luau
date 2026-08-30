-- VERSION: 2026-08-26 #2
-- FEATURE: Diagnose-Print mit Stack-Trace in setPanelVisible ergaenzt
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut die 5 Buttons auf der linken Seite: Monster (Skins), Achievements (Platzhalter),
-- Evolution (Skillbaum), Companion (Platzhalter, siehe Companion-Feature-Konzept), Geschenk (Zeit-Belohnungen).
-- Immer nur EIN Panel gleichzeitig sichtbar -- Klick auf einen aktiven Button schließt ihn wieder.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local applyComicStyle = ComicStyleUtils.Apply
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Comic-Style Hilfsfunktion jetzt über ComicStyleUtils (siehe oben)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NavigationGui"
screenGui.ResetOnSpawn = false
-- WICHTIG: hoher DisplayOrder sorgt dafür, dass das Hauptmenü über anderen HUD-Elementen
-- liegt (z.B. dem Berserker-Bonus) -- unabhängig von der Skript-Ladereihenfolge.
screenGui.DisplayOrder = 90
screenGui.Parent = playerGui

-- ===== Einzelner Menü-Button links (ersetzt die vorher permanent sichtbare 5er-Leiste) =====
-- Hamburger-Icon aus 3 echten Balken gebaut (nicht als Unicode-Zeichen "☰") -- das
-- garantiert, dass es immer sichtbar ist, unabhängig davon ob die Schriftart dieses
-- Zeichen unterstützt. Plus "Menü"-Beschriftung darunter, damit sofort klar ist, dass es
-- sich um einen Button handelt.
local menuToggleButton = Instance.new("TextButton")
menuToggleButton.Name = "MenuToggleButton"
menuToggleButton.Size = UDim2.new(0, 52, 0, 48)
menuToggleButton.Position = UDim2.new(0, 16, 0, 24)
menuToggleButton.BackgroundColor3 = Color3.fromRGB(100, 90, 220)
menuToggleButton.AutoButtonColor = true
menuToggleButton.Text = ""
menuToggleButton.Parent = screenGui
applyComicStyle(menuToggleButton, 16, 4)

local hamburgerIconFrame = Instance.new("Frame")
hamburgerIconFrame.Name = "HamburgerIcon"
hamburgerIconFrame.Size = UDim2.new(0, 24, 0, 16)
hamburgerIconFrame.AnchorPoint = Vector2.new(0.5, 0)
hamburgerIconFrame.Position = UDim2.new(0.5, 0, 0, 6)
hamburgerIconFrame.BackgroundTransparency = 1
hamburgerIconFrame.Parent = menuToggleButton

for i = 0, 2 do
	local bar = Instance.new("Frame")
	bar.Name = "Bar" .. i
	bar.Size = UDim2.new(1, 0, 0, 3)
	bar.Position = UDim2.new(0, 0, 0, i * 6)
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = hamburgerIconFrame
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar
end

local menuToggleLabel = Instance.new("TextLabel")
menuToggleLabel.Size = UDim2.new(1, 0, 0, 13)
menuToggleLabel.Position = UDim2.new(0, 0, 1, -15)
menuToggleLabel.BackgroundTransparency = 1
menuToggleLabel.Font = Enum.Font.FredokaOne
menuToggleLabel.TextScaled = true
menuToggleLabel.TextColor3 = Color3.new(1, 1, 1)
menuToggleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
menuToggleLabel.TextStrokeTransparency = 0.4
menuToggleLabel.Text = "Menu"
menuToggleLabel.Parent = menuToggleButton

-- ===== Grosses, zentriertes Overlay mit den 5 Menü-Buttons =====
local menuOverlay = Instance.new("Frame")
menuOverlay.Name = "MenuOverlay"
menuOverlay.Size = UDim2.new(0, 540, 0, 420)
menuOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
menuOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
menuOverlay.BackgroundColor3 = Color3.fromRGB(35, 32, 45)
menuOverlay.Visible = false
menuOverlay.ZIndex = 80
menuOverlay.Parent = screenGui
applyComicStyle(menuOverlay, 22, 5)

-- Abgedunkelter Hintergrund hinter dem Overlay -- Klick darauf schliesst das Menü ebenfalls
-- WICHTIG: Roblox reserviert oben automatisch einen Streifen für die eigene Menüleiste
-- (Chat/Einstellungen-Icons) und schiebt GUI-Inhalte standardmässig darunter -- ohne
-- Anpassung bliebe dieser Streifen beim Verdunkeln hell. GuiService:GetGuiInset() liefert
-- die genaue Höhe dieses Streifens; der Backdrop wird exakt um diesen Betrag nach oben
-- erweitert (NUR der Backdrop, nicht das ganze ScreenGui -- sonst würden auch Hamburger-
-- Button & Co. mitverschoben).
local topInset = GuiService:GetGuiInset().Y
local menuBackdrop = Instance.new("TextButton")
menuBackdrop.Name = "MenuBackdrop"
menuBackdrop.Size = UDim2.new(1, 0, 1, topInset)
menuBackdrop.Position = UDim2.new(0, 0, 0, -topInset)
menuBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
menuBackdrop.BackgroundTransparency = 0.5
menuBackdrop.AutoButtonColor = false
menuBackdrop.Text = ""
menuBackdrop.Visible = false
menuBackdrop.ZIndex = 79
menuBackdrop.Parent = screenGui

local menuTitle = Instance.new("TextLabel")
menuTitle.Size = UDim2.new(1, -70, 0, 40)
menuTitle.Position = UDim2.new(0, 16, 0, 14)
menuTitle.BackgroundTransparency = 1
menuTitle.Font = Enum.Font.LuckiestGuy
menuTitle.TextScaled = true
menuTitle.TextXAlignment = Enum.TextXAlignment.Left
menuTitle.TextColor3 = Color3.new(1, 1, 1)
menuTitle.Text = "Menu"
menuTitle.ZIndex = 81
menuTitle.Parent = menuOverlay

local menuCloseButton = Instance.new("TextButton")
menuCloseButton.Name = "MenuCloseButton"
menuCloseButton.Size = UDim2.new(0, 44, 0, 44)
menuCloseButton.AnchorPoint = Vector2.new(1, 0)
menuCloseButton.Position = UDim2.new(1, -14, 0, 14)
menuCloseButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
menuCloseButton.Font = Enum.Font.FredokaOne
menuCloseButton.TextScaled = true
menuCloseButton.TextColor3 = Color3.new(1, 1, 1)
menuCloseButton.Text = "X"
menuCloseButton.ZIndex = 81
menuCloseButton.Parent = menuOverlay
applyComicStyle(menuCloseButton, 10, 3)

local menuButtonsRow = Instance.new("Frame")
menuButtonsRow.Name = "MenuButtonsRow"
menuButtonsRow.Size = UDim2.new(1, -32, 1, -80)
menuButtonsRow.Position = UDim2.new(0, 16, 0, 68)
menuButtonsRow.BackgroundTransparency = 1
menuButtonsRow.ZIndex = 81
menuButtonsRow.Parent = menuOverlay

local menuButtonsLayout = Instance.new("UIGridLayout")
menuButtonsLayout.CellSize = UDim2.new(0, 150, 0, 150)
menuButtonsLayout.CellPadding = UDim2.new(0, 14, 0, 14)
menuButtonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
menuButtonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuButtonsLayout.Parent = menuButtonsRow

local isMenuOpen = false

local function setMenuOpen(open)
	isMenuOpen = open
	menuOverlay.Visible = open
	menuBackdrop.Visible = open
end

menuToggleButton.MouseButton1Click:Connect(function()
	setMenuOpen(not isMenuOpen)
end)
menuCloseButton.MouseButton1Click:Connect(function()
	setMenuOpen(false)
end)
menuBackdrop.MouseButton1Click:Connect(function()
	setMenuOpen(false)
end)

local NAV_BUTTONS = {
	{ key = "Monster", icon = "🐲", label = "Monster", color = Color3.fromRGB(80, 200, 90) },
	{ key = "Achievements", icon = "🏆", label = "Achievements", color = Color3.fromRGB(255, 205, 30) },
	{ key = "Talents", icon = "🌟", label = "Talents", color = Color3.fromRGB(60, 170, 220) },
	{ key = "Pets", icon = "🐺", label = "Companion", color = Color3.fromRGB(255, 150, 90) },
	{ key = "Gifts", icon = "🎁", label = "Gift", color = Color3.fromRGB(230, 80, 130) },
	{ key = "Faction", icon = "🦖", label = "Faction", color = Color3.fromRGB(90, 80, 200) },
	{ key = "Help", icon = "❓", label = "Help", color = Color3.fromRGB(120, 130, 140) },
}

local navButtons = {} -- [key] = TextButton
local panels = {} -- [key] = GuiObject (das zugehörige Panel, extern gesetzt via registerPanel)
local activePanelKey = nil

-- ===== Gemeinsamer "Zurück"-Button: erscheint bei JEDEM offenen Panel an derselben
-- festen Stelle (unabhängig davon, welches der 6 Panels gerade offen ist), und führt
-- zurück zum Menü-Overlay mit den 6 Buttons, statt alles komplett zu schliessen. =====
local function setPanelVisible(key, visible)
	local panel = panels[key]
	if panel then
		if visible then
			print("[Kaiju-Debug] NavigationClient: Panel '" .. tostring(key) .. "' wird SICHTBAR gemacht -- tick=" .. tostring(os.clock()))
			print(debug.traceback("[Kaiju-Debug] Aufruf-Stack:"))
		end
		panel.Visible = visible
	end
end

local function closeActivePanel()
	if activePanelKey then
		setPanelVisible(activePanelKey, false)
		activePanelKey = nil
	end
end

local function togglePanel(key)
	if activePanelKey == key then
		closeActivePanel()
		return
	end

	closeActivePanel()
	setPanelVisible(key, true)
	activePanelKey = key
end

-- Geteilte Funktion, die JEDES Panel bei seinem eigenen "X"-Schliessen-Button aufrufen
-- kann, um zum Menü zurückzukehren -- ersetzt den früheren separaten "← Back"-Button.
-- Panels rufen dies zusätzlich zu ihrem eigenen "panel.Visible = false" auf.
_G.NavReturnToMenu = function()
	closeActivePanel()
	setMenuOpen(true)
end

for index, config in ipairs(NAV_BUTTONS) do
	local button = Instance.new("TextButton")
	button.Name = config.key .. "NavButton"
	button.LayoutOrder = index
	button.BackgroundColor3 = config.color
	button.AutoButtonColor = true
	button.Text = ""
	button.ZIndex = 81
	button.Parent = menuButtonsRow
	applyComicStyle(button, 16, 4)

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(1, 0, 0.6, 0)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.LuckiestGuy
	icon.TextScaled = true
	icon.Text = config.icon
	icon.ZIndex = 81
	icon.Parent = button

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.35, 0)
	label.Position = UDim2.new(0, 0, 0.62, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.Text = config.label
	label.ZIndex = 81
	label.Parent = button

	button.MouseButton1Click:Connect(function()
		togglePanel(config.key)
		setMenuOpen(false) -- Menü-Overlay schliesst sich, sobald ein Unterbereich geöffnet wird
	end)

	navButtons[config.key] = button
end

-- ===== Platzhalter-Panel-Baukasten (für Achievements & Haustiere) =====
local function createPlaceholderPanel(key, title, message)
	local panel = Instance.new("Frame")
	panel.Name = key .. "Panel"
	panel.Size = UDim2.new(0, 340, 0, 260)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(250, 245, 230)
	panel.Visible = false
	panel.Parent = screenGui
	applyComicStyle(panel, 20, 5)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -16, 0, 44)
	titleLabel.Position = UDim2.new(0, 8, 0, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(60, 40, 20)
	titleLabel.Text = title
	titleLabel.Parent = panel

	local messageLabel = Instance.new("TextLabel")
	messageLabel.Size = UDim2.new(1, -32, 1, -70)
	messageLabel.Position = UDim2.new(0, 16, 0, 60)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Font = Enum.Font.FredokaOne
	messageLabel.TextScaled = true
	messageLabel.TextWrapped = true
	messageLabel.TextColor3 = Color3.fromRGB(90, 80, 70)
	messageLabel.Text = message
	messageLabel.Parent = panel

	panels[key] = panel
	return panel
end

createPlaceholderPanel("Pets", "🐺 Companion", "Coming soon! A personal companion that fights alongside you, grows through your bond, and evolves as you play.")

-- ===== Echtes Achievement-Panel (ersetzt den bisherigen Platzhalter) =====
local AchievementsConfig = require(ReplicatedStorage:WaitForChild("AchievementsConfig"))
local achievementUnlockedEvent = RemoteEventUtils.GetOrCreate("AchievementUnlockedEvent")

local achievementsPanel = Instance.new("Frame")
achievementsPanel.Name = "AchievementsPanel"
achievementsPanel.Size = UDim2.new(0, 480, 0, 460)
achievementsPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
achievementsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
achievementsPanel.BackgroundColor3 = Color3.fromRGB(250, 245, 230)
achievementsPanel.Visible = false
achievementsPanel.Parent = screenGui
applyComicStyle(achievementsPanel, 20, 5)
panels["Achievements"] = achievementsPanel

local achievementsTitleLabel = Instance.new("TextLabel")
achievementsTitleLabel.Size = UDim2.new(1, -70, 0, 40)
achievementsTitleLabel.Position = UDim2.new(0, 8, 0, 10)
achievementsTitleLabel.BackgroundTransparency = 1
achievementsTitleLabel.Font = Enum.Font.LuckiestGuy
achievementsTitleLabel.TextScaled = true
achievementsTitleLabel.TextColor3 = Color3.fromRGB(60, 40, 20)
achievementsTitleLabel.Text = "🏆 Erfolge"
achievementsTitleLabel.Parent = achievementsPanel

local achievementsCloseButton = Instance.new("TextButton")
achievementsCloseButton.Name = "AchievementsCloseButton"
achievementsCloseButton.Size = UDim2.new(0, 44, 0, 44)
achievementsCloseButton.AnchorPoint = Vector2.new(1, 0)
achievementsCloseButton.Position = UDim2.new(1, -8, 0, 8)
achievementsCloseButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
achievementsCloseButton.Font = Enum.Font.FredokaOne
achievementsCloseButton.TextScaled = true
achievementsCloseButton.TextColor3 = Color3.new(1, 1, 1)
achievementsCloseButton.Text = "X"
achievementsCloseButton.Parent = achievementsPanel
applyComicStyle(achievementsCloseButton, 10, 2)
achievementsCloseButton.MouseButton1Click:Connect(function()
	_G.NavReturnToMenu()
end)

local achievementsScroll = Instance.new("ScrollingFrame")
achievementsScroll.Size = UDim2.new(1, -24, 1, -62)
achievementsScroll.Position = UDim2.new(0, 12, 0, 56)
achievementsScroll.BackgroundTransparency = 1
achievementsScroll.BorderSizePixel = 0
achievementsScroll.ScrollBarThickness = 8
achievementsScroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- wird von UIListLayout automatisch gesetzt
achievementsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
achievementsScroll.Parent = achievementsPanel

local achievementsListLayout = Instance.new("UIListLayout")
achievementsListLayout.Padding = UDim.new(0, 6)
achievementsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
achievementsListLayout.Parent = achievementsScroll

-- [achievementId] = { row=, fillBar=, progressLabel= } -- für die laufende Aktualisierung.
local achievementRows = {}

local layoutOrder = 0
local lastCategory = nil
for _, achievement in ipairs(AchievementsConfig.List) do
	if achievement.category ~= lastCategory then
		lastCategory = achievement.category
		layoutOrder += 1

		local categoryHeader = Instance.new("TextLabel")
		categoryHeader.Size = UDim2.new(1, 0, 0, 26)
		categoryHeader.BackgroundTransparency = 1
		categoryHeader.Font = Enum.Font.LuckiestGuy
		categoryHeader.TextScaled = true
		categoryHeader.TextXAlignment = Enum.TextXAlignment.Left
		categoryHeader.TextColor3 = Color3.fromRGB(150, 100, 40)
		categoryHeader.Text = lastCategory
		categoryHeader.LayoutOrder = layoutOrder
		categoryHeader.Parent = achievementsScroll
	end

	layoutOrder += 1
	local row = Instance.new("Frame")
	row.Name = achievement.id .. "Row"
	row.Size = UDim2.new(1, 0, 0, 52)
	row.BackgroundColor3 = Color3.fromRGB(255, 253, 245)
	row.LayoutOrder = layoutOrder
	row.Parent = achievementsScroll
	applyComicStyle(row, 10, 2)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 40, 0, 40)
	iconLabel.Position = UDim2.new(0, 6, 0, 6)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.FredokaOne
	iconLabel.TextScaled = true
	iconLabel.Text = achievement.icon
	iconLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -56, 0, 20)
	nameLabel.Position = UDim2.new(0, 52, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(60, 40, 20)
	nameLabel.Text = achievement.name
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -56, 0, 16)
	descLabel.Position = UDim2.new(0, 52, 0, 24)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.FredokaOne
	descLabel.TextScaled = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextColor3 = Color3.fromRGB(120, 110, 95)
	descLabel.Text = achievement.description
	descLabel.Parent = row

	local progressBarFrame, progressFill, progressLabel
	if achievement.type == "counter" then
		local track = Instance.new("Frame")
		track.Size = UDim2.new(0, 90, 0, 10)
		track.Position = UDim2.new(1, -98, 0, 8)
		track.BackgroundColor3 = Color3.fromRGB(210, 205, 190)
		track.Parent = row
		applyComicStyle(track, 5, 1)

		progressFill = Instance.new("Frame")
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		progressFill.BackgroundColor3 = Color3.fromRGB(90, 200, 110)
		progressFill.BorderSizePixel = 0
		progressFill.Parent = track

		progressLabel = Instance.new("TextLabel")
		progressLabel.Size = UDim2.new(0, 90, 0, 16)
		progressLabel.Position = UDim2.new(1, -98, 0, 20)
		progressLabel.BackgroundTransparency = 1
		progressLabel.Font = Enum.Font.FredokaOne
		progressLabel.TextScaled = true
		progressLabel.TextColor3 = Color3.fromRGB(120, 110, 95)
		progressLabel.Text = "0/" .. achievement.threshold
		progressLabel.Parent = row
		progressBarFrame = track
	end

	achievementRows[achievement.id] = {
		row = row,
		nameLabel = nameLabel,
		progressFill = progressFill,
		progressLabel = progressLabel,
		achievement = achievement,
	}
end

-- Läuft nur, solange das Panel sichtbar ist -- aktualisiert Fortschritt + Freischaltungs-
-- Optik (gedimmt/normal/dormant).
RunService.Heartbeat:Connect(function()
	if not achievementsPanel.Visible then
		return
	end
	for achievementId, rowInfo in pairs(achievementRows) do
		local achievement = rowInfo.achievement
		local unlocked = player:GetAttribute("Achievement_" .. achievementId) == true

		if achievement.dormant and not unlocked then
			rowInfo.row.BackgroundColor3 = Color3.fromRGB(235, 230, 220)
			rowInfo.nameLabel.Text = achievement.name .. "  🔒 Kommt später"
			rowInfo.nameLabel.TextColor3 = Color3.fromRGB(150, 145, 135)
		elseif unlocked then
			rowInfo.row.BackgroundColor3 = Color3.fromRGB(255, 250, 210)
			rowInfo.nameLabel.TextColor3 = Color3.fromRGB(40, 130, 40)
			rowInfo.nameLabel.Text = "✅ " .. achievement.name
		else
			rowInfo.row.BackgroundColor3 = Color3.fromRGB(255, 253, 245)
			rowInfo.nameLabel.TextColor3 = Color3.fromRGB(60, 40, 20)
			rowInfo.nameLabel.Text = achievement.name
		end

		if achievement.type == "counter" and rowInfo.progressFill then
			local current = player:GetAttribute("Counter_" .. (achievement.counterKey or achievementId)) or 0
			local ratio = math.clamp(current / achievement.threshold, 0, 1)
			rowInfo.progressFill.Size = UDim2.new(ratio, 0, 1, 0)
			rowInfo.progressLabel.Text = math.min(current, achievement.threshold) .. "/" .. achievement.threshold
		end
	end
end)

-- ===== Freischaltungs-Toast: kurze Benachrichtigung, sobald ein Achievement live
-- freigeschaltet wird (auch wenn das Panel gerade nicht offen ist). =====
local achievementToast = Instance.new("Frame")
achievementToast.Name = "AchievementToast"
achievementToast.AnchorPoint = Vector2.new(0.5, 0)
achievementToast.Position = UDim2.new(0.5, 0, 0, -70)
achievementToast.Size = UDim2.new(0, 320, 0, 60)
achievementToast.BackgroundColor3 = Color3.fromRGB(255, 250, 210)
achievementToast.Visible = false
achievementToast.ZIndex = 50
achievementToast.Parent = screenGui
applyComicStyle(achievementToast, 14, 3)

local toastIcon = Instance.new("TextLabel")
toastIcon.Size = UDim2.new(0, 44, 0, 44)
toastIcon.Position = UDim2.new(0, 8, 0, 8)
toastIcon.BackgroundTransparency = 1
toastIcon.Font = Enum.Font.FredokaOne
toastIcon.TextScaled = true
toastIcon.ZIndex = 51
toastIcon.Parent = achievementToast

local toastText = Instance.new("TextLabel")
toastText.Size = UDim2.new(1, -60, 1, -12)
toastText.Position = UDim2.new(0, 56, 0, 6)
toastText.BackgroundTransparency = 1
toastText.Font = Enum.Font.FredokaOne
toastText.TextScaled = true
toastText.TextXAlignment = Enum.TextXAlignment.Left
toastText.TextColor3 = Color3.fromRGB(60, 40, 20)
toastText.ZIndex = 51
toastText.Parent = achievementToast

local toastShowing = false
achievementUnlockedEvent.OnClientEvent:Connect(function(achievementId)
	local achievement = AchievementsConfig.ById[achievementId]
	if not achievement then
		return
	end
	toastIcon.Text = achievement.icon
	toastText.Text = "🏆 Erfolg freigeschaltet!\n" .. achievement.name

	if toastShowing then
		return
	end
	toastShowing = true
	achievementToast.Visible = true
	TweenService:Create(achievementToast, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 20),
	}):Play()
	task.delay(3, function()
		local slideOut = TweenService:Create(achievementToast, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -70),
		})
		slideOut:Play()
		slideOut.Completed:Connect(function()
			achievementToast.Visible = false
			toastShowing = false
		end)
	end)
end)

-- ===== Anbindung an bestehende/andere Panels =====
-- Monster-Panel = der schon vorhandene Skin-Shop (aus SkinSelectionGui.lua)
task.spawn(function()
	local gameHud = playerGui:WaitForChild("GameHud")
	local shopFrame = gameHud:WaitForChild("ShopFrame")
	panels["Monster"] = shopFrame
end)

-- Geschenk-Panel (aus GiftClient.lua)
task.spawn(function()
	local giftGui = playerGui:WaitForChild("GiftGui")
	local giftPanel = giftGui:WaitForChild("GiftPanel")
	panels["Gifts"] = giftPanel
end)

-- Fraktions-Panel (aus EnergyTypesClient.lua)
task.spawn(function()
	local energyTypesGui = playerGui:WaitForChild("EnergyTypesGui")
	local factionPanel = energyTypesGui:WaitForChild("FactionPanel")
	panels["Faction"] = factionPanel
end)

-- Talentbaum-Panel (aus TalentTreeClient.lua)
task.spawn(function()
	local talentTreeGui = playerGui:WaitForChild("TalentTreeGui")
	local talentTreePanel = talentTreeGui:WaitForChild("TalentTreePanel")
	panels["Talents"] = talentTreePanel
end)

-- ===== Hilfeseite =====
local HelpConfig = require(ReplicatedStorage:WaitForChild("HelpConfig"))

local helpPanel = Instance.new("Frame")
helpPanel.Name = "HelpPanel"
helpPanel.Size = UDim2.new(0, 500, 0, 480)
helpPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
helpPanel.AnchorPoint = Vector2.new(0.5, 0.5)
helpPanel.BackgroundColor3 = Color3.fromRGB(250, 245, 230)
helpPanel.Visible = false
helpPanel.Parent = screenGui
applyComicStyle(helpPanel, 20, 5)
panels["Help"] = helpPanel

local helpTitleLabel = Instance.new("TextLabel")
helpTitleLabel.Size = UDim2.new(1, -70, 0, 40)
helpTitleLabel.Position = UDim2.new(0, 8, 0, 10)
helpTitleLabel.BackgroundTransparency = 1
helpTitleLabel.Font = Enum.Font.LuckiestGuy
helpTitleLabel.TextScaled = true
helpTitleLabel.TextColor3 = Color3.fromRGB(60, 40, 20)
helpTitleLabel.Text = "❓ Help"
helpTitleLabel.Parent = helpPanel

local helpCloseButton = Instance.new("TextButton")
helpCloseButton.Name = "HelpCloseButton"
helpCloseButton.Size = UDim2.new(0, 44, 0, 44)
helpCloseButton.AnchorPoint = Vector2.new(1, 0)
helpCloseButton.Position = UDim2.new(1, -8, 0, 8)
helpCloseButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
helpCloseButton.Font = Enum.Font.FredokaOne
helpCloseButton.TextScaled = true
helpCloseButton.TextColor3 = Color3.new(1, 1, 1)
helpCloseButton.Text = "X"
helpCloseButton.Parent = helpPanel
applyComicStyle(helpCloseButton, 10, 2)
helpCloseButton.MouseButton1Click:Connect(function()
	_G.NavReturnToMenu()
end)

local helpScroll = Instance.new("ScrollingFrame")
helpScroll.Size = UDim2.new(1, -24, 1, -62)
helpScroll.Position = UDim2.new(0, 12, 0, 56)
helpScroll.BackgroundTransparency = 1
helpScroll.BorderSizePixel = 0
helpScroll.ScrollBarThickness = 8
helpScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
helpScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
helpScroll.Parent = helpPanel

local helpListLayout = Instance.new("UIListLayout")
helpListLayout.Padding = UDim.new(0, 14)
helpListLayout.SortOrder = Enum.SortOrder.LayoutOrder
helpListLayout.Parent = helpScroll

-- [sectionId] = Frame -- fürs direkte Anspringen von einem Kontext-Hilfe-Button aus.
local helpSectionFrames = {}

-- ===== Einfache gebaute Diagramme (Platzhalter statt echter Screenshots) =====
local function buildDiagram(diagramType, parent)
	local diagramFrame = Instance.new("Frame")
	diagramFrame.Name = "Diagram"
	diagramFrame.Size = UDim2.new(1, 0, 0, 50)
	diagramFrame.BackgroundTransparency = 1
	diagramFrame.Parent = parent

	if diagramType == "training" then
		local labels = { { "💪", Color3.fromRGB(220, 90, 220) }, { "🦵", Color3.fromRGB(255, 150, 60) }, { "🫀", Color3.fromRGB(90, 220, 130) } }
		for i, entry in ipairs(labels) do
			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 100, 0, 14)
			bar.Position = UDim2.new(0, (i - 1) * 140, 0, 18)
			bar.BackgroundColor3 = entry[2]
			bar.Parent = diagramFrame
			applyComicStyle(bar, 6, 1)
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(0, 24, 0, 24)
			icon.Position = UDim2.new(0, (i - 1) * 140, 0, -6)
			icon.BackgroundTransparency = 1
			icon.Font = Enum.Font.FredokaOne
			icon.TextScaled = true
			icon.Text = entry[1]
			icon.Parent = diagramFrame
		end
	elseif diagramType == "alert" then
		for i = 1, 5 do
			local star = Instance.new("TextLabel")
			star.Size = UDim2.new(0, 36, 0, 36)
			star.Position = UDim2.new(0, (i - 1) * 44, 0, 6)
			star.BackgroundTransparency = 1
			star.Font = Enum.Font.FredokaOne
			star.TextScaled = true
			star.TextColor3 = Color3.fromRGB(255, 210, 80)
			star.Text = "★"
			star.Parent = diagramFrame
		end
	elseif diagramType == "heat" then
		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, 0, 0, 20)
		track.Position = UDim2.new(0, 0, 0, 16)
		track.BackgroundColor3 = Color3.fromRGB(230, 225, 210)
		track.Parent = diagramFrame
		applyComicStyle(track, 8, 1)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 130, 210)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(210, 175, 50)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(210, 115, 25)),
			ColorSequenceKeypoint.new(0.85, Color3.fromRGB(210, 25, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 20, 190)),
		})
		gradient.Parent = track
	elseif diagramType == "energy" then
		local ring = Instance.new("Frame")
		ring.Size = UDim2.new(0, 50, 0, 50)
		ring.Position = UDim2.new(0, 4, 0, 4)
		ring.BackgroundColor3 = Color3.fromRGB(70, 210, 255)
		ring.Parent = diagramFrame
		local ringCorner = Instance.new("UICorner")
		ringCorner.CornerRadius = UDim.new(0.5, 0)
		ringCorner.Parent = ring
		local ringInner = Instance.new("Frame")
		ringInner.Size = UDim2.new(0, 34, 0, 34)
		ringInner.AnchorPoint = Vector2.new(0.5, 0.5)
		ringInner.Position = UDim2.new(0.5, 0, 0.5, 0)
		ringInner.BackgroundColor3 = Color3.fromRGB(250, 245, 230)
		ringInner.Parent = ring
		local ringInnerCorner = Instance.new("UICorner")
		ringInnerCorner.CornerRadius = UDim.new(0.5, 0)
		ringInnerCorner.Parent = ringInner
	elseif diagramType == "factions" then
		local icons = { "🦖", "🤖", "🐯" }
		for i, iconText in ipairs(icons) do
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(0, 44, 0, 44)
			icon.Position = UDim2.new(0, (i - 1) * 60, 0, 3)
			icon.BackgroundTransparency = 1
			icon.Font = Enum.Font.FredokaOne
			icon.TextScaled = true
			icon.Text = iconText
			icon.Parent = diagramFrame
		end
	end

	return diagramFrame
end

for index, section in ipairs(HelpConfig.Sections) do
	local sectionFrame = Instance.new("Frame")
	sectionFrame.Name = section.id .. "Section"
	sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
	sectionFrame.Size = UDim2.new(1, 0, 0, 0)
	sectionFrame.BackgroundColor3 = Color3.fromRGB(255, 253, 245)
	sectionFrame.LayoutOrder = index
	sectionFrame.Parent = helpScroll
	applyComicStyle(sectionFrame, 12, 2)
	helpSectionFrames[section.id] = sectionFrame

	local sectionPadding = Instance.new("UIPadding")
	sectionPadding.PaddingTop = UDim.new(0, 10)
	sectionPadding.PaddingBottom = UDim.new(0, 10)
	sectionPadding.PaddingLeft = UDim.new(0, 12)
	sectionPadding.PaddingRight = UDim.new(0, 12)
	sectionPadding.Parent = sectionFrame

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.Padding = UDim.new(0, 4)
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Parent = sectionFrame

	local sectionTitle = Instance.new("TextLabel")
	sectionTitle.Size = UDim2.new(1, 0, 0, 26)
	sectionTitle.BackgroundTransparency = 1
	sectionTitle.Font = Enum.Font.LuckiestGuy
	sectionTitle.TextScaled = true
	sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
	sectionTitle.TextColor3 = Color3.fromRGB(60, 40, 20)
	sectionTitle.Text = section.icon .. " " .. section.title
	sectionTitle.LayoutOrder = 1
	sectionTitle.Parent = sectionFrame

	local sectionSummary = Instance.new("TextLabel")
	sectionSummary.Size = UDim2.new(1, 0, 0, 32)
	sectionSummary.BackgroundTransparency = 1
	sectionSummary.Font = Enum.Font.FredokaOne
	sectionSummary.TextWrapped = true
	sectionSummary.TextScaled = true
	sectionSummary.TextXAlignment = Enum.TextXAlignment.Left
	sectionSummary.TextColor3 = Color3.fromRGB(90, 80, 65)
	sectionSummary.Text = section.summary
	sectionSummary.LayoutOrder = 2
	sectionSummary.Parent = sectionFrame

	local diagram = buildDiagram(section.diagramType, sectionFrame)
	diagram.LayoutOrder = 3

	for pointIndex, pointText in ipairs(section.points) do
		local pointLabel = Instance.new("TextLabel")
		pointLabel.Size = UDim2.new(1, 0, 0, 20)
		pointLabel.BackgroundTransparency = 1
		pointLabel.Font = Enum.Font.FredokaOne
		pointLabel.TextWrapped = true
		pointLabel.TextScaled = true
		pointLabel.TextXAlignment = Enum.TextXAlignment.Left
		pointLabel.TextColor3 = Color3.fromRGB(60, 40, 20)
		pointLabel.Text = "• " .. pointText
		pointLabel.LayoutOrder = 3 + pointIndex
		pointLabel.Parent = sectionFrame
	end
end

-- Öffnet die Hilfeseite und springt optional direkt zu einem Abschnitt (z.B. vom
-- Trainingspanel-Hilfe-Button aus). sectionId ist optional -- ohne Angabe öffnet sich
-- einfach die Seite ganz oben.
_G.OpenHelpPanel = function(sectionId)
	closeActivePanel()
	setPanelVisible("Help", true)
	activePanelKey = "Help"
	if sectionId and helpSectionFrames[sectionId] then
		task.defer(function()
			helpScroll.CanvasPosition = Vector2.new(0, helpSectionFrames[sectionId].Position.Y.Offset)
		end)
	end
end

_G.CloseNavPanels = function()
	closeActivePanel()
	setMenuOpen(false)
end