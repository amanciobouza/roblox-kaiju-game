-- VERSION: 2026-08-25 #2 (RemoteEventUtils-Umstellung)
-- LocalScript: GiftClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut das Geschenk-Panel (aufgerufen über den "Geschenk"-Button links). Zeigt 12 Geschenke,
-- die über die Spielzeit nach und nach bereit werden -- bereite Geschenke sind anklickbar
-- und leuchten, gesperrte zeigen einen Countdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local UiTypography = require(ReplicatedStorage:WaitForChild("UiTypography"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
local applyComicStyle = ComicStyleUtils.Apply
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local ClaimGiftEvent = RemoteEventUtils.GetOrCreate("ClaimGiftEvent")
local giftCountValue = ReplicatedStorage:WaitForChild("GiftCount")
local giftUnlockTimesFolder = ReplicatedStorage:WaitForChild("GiftUnlockTimes")
local giftDescriptionsFolder = ReplicatedStorage:WaitForChild("GiftDescriptions")
-- Symbole liegen seit der Trennung in einem eigenen Ordner. Fehlt er (aelterer Server),
-- faellt die Karte auf das Geschenkpaket zurueck statt leer zu bleiben.
local giftIconsFolder = ReplicatedStorage:WaitForChild("GiftIcons", 10)

local function formatTime(seconds)
	seconds = math.max(math.floor(seconds), 0)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", minutes, secs)
end

local screenGui = Instance.new("ScreenGui")
screenGui.IgnoreGuiInset = true
-- In diesem Gui liegt NUR das Geschenk-Panel, kein HUD -- hier genuegt es, die Ebene
-- anzuheben, statt ein zweites ScreenGui anzulegen.
screenGui.DisplayOrder = 100
screenGui.Name = "GiftGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "GiftPanel"
-- Vollbild: alle Menü-Bildschirme nutzen die ganze Fläche.
panel.Size = UDim2.new(1, 0, 1, 0)
panel.Position = UDim2.new(0, 0, 0, 0)
panel.AnchorPoint = Vector2.new(0, 0)
panel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
panel.Visible = false
panel.Parent = screenGui
applyComicStyle(panel, 20, 5)

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(panel)

-- X-Schliessen-Button -- kehrt zum Hamburger-Menü zurück (dieses Panel hatte bisher
-- keinen eigenen, war nur über den jetzt entfernten "← Back"-Button schliessbar).
local giftCloseButton = Instance.new("TextButton")
giftCloseButton.Name = "CloseButton"
giftCloseButton.Size = UDim2.new(0, 34, 0, 34)
giftCloseButton.AnchorPoint = Vector2.new(1, 0)
giftCloseButton.Position = UDim2.new(1, -8, 0, 8)
giftCloseButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
giftCloseButton.Font = Enum.Font.FredokaOne
giftCloseButton.TextScaled = true
giftCloseButton.TextColor3 = Color3.new(1, 1, 1)
giftCloseButton.Text = "X"
giftCloseButton.ZIndex = 5
giftCloseButton.Parent = panel
applyComicStyle(giftCloseButton, 8, 2)
giftCloseButton.MouseButton1Click:Connect(function()
	panel.Visible = false
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	end
end)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -16, 0, 40)
titleLabel.Position = UDim2.new(0, 8, 0, 8)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.LuckiestGuy
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
titleLabel.Text = "🎁 Time Gifts"
titleLabel.Parent = panel

local grid = Instance.new("ScrollingFrame")
grid.Size = UDim2.new(1, -16, 1, -56)
grid.Position = UDim2.new(0, 8, 0, 48)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 8
grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.Parent = panel

local gridLayout = Instance.new("UIGridLayout")
-- Vorher 135x110. Auf einem Vollbild-Bildschirm standen zwoelf Briefmarken in einer
-- Ecke; das Symbol war zu klein, um die Belohnung zu erkennen.
gridLayout.CellSize = UDim2.new(0, 210, 0, 180)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

local giftCells = {} -- [n] = { button=, overlay=, timeLabel=, iconLabel= }

for n = 1, giftCountValue.Value do
	local cell = Instance.new("TextButton")
	cell.Name = "Gift" .. n
	cell.LayoutOrder = n
	cell.BackgroundColor3 = Color3.fromRGB(230, 80, 130)
	cell.AutoButtonColor = false
	cell.Text = ""
	cell.Parent = grid
	applyComicStyle(cell, 14, 3)

	local numberLabel = Instance.new("TextLabel")
	numberLabel.Size = UDim2.new(1, 0, 0, 18)
	numberLabel.Position = UDim2.new(0, 0, 0, 4)
	numberLabel.BackgroundTransparency = 1
	numberLabel.Font = Enum.Font.LuckiestGuy
	numberLabel.TextScaled = true
	numberLabel.TextColor3 = Color3.new(1, 1, 1)
	numberLabel.Text = "#" .. n
	numberLabel.ZIndex = 2
	numberLabel.Parent = cell

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 0, 76)
	iconLabel.Position = UDim2.new(0, 0, 0, 26)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.LuckiestGuy
	iconLabel.TextScaled = true
	-- Das Symbol der TATSAECHLICHEN Belohnung. Vorher stand hier bei allen zwoelf
	-- Geschenken dasselbe Paket -- die Karte sagte damit nichts ueber ihren Inhalt.
	local iconValue = giftIconsFolder and giftIconsFolder:FindFirstChild("Gift" .. n)
	iconLabel.Text = iconValue and iconValue.Value or "🎁"
	iconLabel.ZIndex = 2
	iconLabel.Parent = cell

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -16, 0, 52)
	descLabel.Position = UDim2.new(0, 8, 0, 106)
	descLabel.BackgroundTransparency = 1
	descLabel.TextColor3 = Color3.new(1, 1, 1)
	UiTypography.Body(descLabel, 15)
	local desc = giftDescriptionsFolder:FindFirstChild("Gift" .. n)
	descLabel.Text = desc and desc.Value or ""
	descLabel.ZIndex = 2
	descLabel.Parent = cell

	-- Heller, halbtransparenter Grau-Überzug für gesperrte Geschenke (Icon bleibt farbig
	-- sichtbar, wirkt nur "ausgegraut") + kleiner Countdown-Streifen unten
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(160, 160, 160)
	overlay.BackgroundTransparency = 0.55
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 3
	overlay.Parent = cell
	applyComicStyle(overlay, 14, 0)

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Size = UDim2.new(1, 0, 0, 18)
	timeLabel.Position = UDim2.new(0, 0, 1, -18)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.FredokaOne
	timeLabel.TextScaled = true
	timeLabel.TextColor3 = Color3.new(1, 1, 1)
	timeLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	timeLabel.TextStrokeTransparency = 0
	timeLabel.ZIndex = 4
	timeLabel.Text = "--:--"
	timeLabel.Parent = overlay

	cell.MouseButton1Click:Connect(function()
		local claimedFolder = player:FindFirstChild("ClaimedGifts")
		local marker = claimedFolder and claimedFolder:FindFirstChild("Gift" .. n)
		if marker and not marker.Value and overlay.Visible == false then
			ClaimGiftEvent:FireServer(n)
		end
	end)

	giftCells[n] = { cell = cell, overlay = overlay, timeLabel = timeLabel }
end

local wasReady = {} -- [n] = bool, für den Leucht-Puls beim Bereitwerden

local function playReadyGlow(cell)
	local stroke = cell:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	local originalColor = stroke.Color
	stroke.Color = Color3.fromRGB(255, 255, 150)
	TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Color = originalColor,
	}):Play()
end

RunService.Heartbeat:Connect(function()
	local sessionStart = player:GetAttribute("SessionStartTime")
	local claimedFolder = player:FindFirstChild("ClaimedGifts")
	if not sessionStart or not claimedFolder then
		return
	end

	local elapsed = Workspace:GetServerTimeNow() - sessionStart
	local anyClaimable = false

	for n = 1, giftCountValue.Value do
		local ui = giftCells[n]
		local unlockTimeValue = giftUnlockTimesFolder:FindFirstChild("Gift" .. n)
		local marker = claimedFolder:FindFirstChild("Gift" .. n)
		if ui and unlockTimeValue and marker then
			local claimed = marker.Value
			local ready = elapsed >= unlockTimeValue.Value

			if claimed then
				ui.overlay.Visible = true
				ui.overlay.BackgroundTransparency = 0.6
				ui.timeLabel.Text = "✅"
			elseif ready then
				ui.overlay.Visible = false
				if not wasReady[n] then
					playReadyGlow(ui.cell)
				end
			else
				ui.overlay.Visible = true
				ui.overlay.BackgroundTransparency = 0.55
				ui.timeLabel.Text = formatTime(unlockTimeValue.Value - elapsed)
			end

			wasReady[n] = ready
			if ready and not claimed then
				anyClaimable = true
			end
		end
	end

	-- Das Geschenk-Laempchen geht NICHT beim Oeffnen aus, sondern erst beim Abholen --
	-- sonst oeffnet man, wird abgelenkt, und das Geschenk liegt weiter da. Deshalb wird es
	-- hier bei jedem Durchlauf neu gesetzt statt nur beim Uebergang.
	--
	-- Gesammelt ueber ALLE Geschenke: die Auswertung innerhalb der Schleife haette das
	-- Laempchen vom LETZTEN Eintrag abhaengig gemacht -- ist Geschenk 1 abholbar und
	-- Geschenk 3 nicht, waere es aus geblieben.
	if _G.SetNavBadge then
		_G.SetNavBadge("Gifts", anyClaimable)
	end
end)