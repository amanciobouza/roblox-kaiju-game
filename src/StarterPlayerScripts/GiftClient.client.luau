-- VERSION: 2026-08-25 #2 (RemoteEventUtils-Umstellung)
-- LocalScript: GiftClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut das Geschenk-Panel (aufgerufen über den "Geschenk"-Button links). Zeigt 12 Geschenke,
-- die über die Spielzeit nach und nach bereit werden -- bereite Geschenke sind anklickbar
-- und leuchten, gesperrte zeigen einen Countdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
local ResponsiveGridUtils = require(ReplicatedStorage:WaitForChild("ResponsiveGridUtils"))
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

-- Vollbild-Bildschirm aus HudChrome.Screen: Feld, Kopf, Titel, Unterzeile und
-- Schliessen-Knopf. Sie standen hier einzeln -- LuckiestGuy, ein rotes X, ein Titel mit
-- Emoji -- und in jedem anderen Menue noch einmal, jedes Mal etwas anders.
--
-- Die Unterzeile traegt jetzt, was vorher nirgends stand: wie viele Geschenke gerade
-- abholbar sind. Das war bisher nur am Laempchen in der Navigation zu sehen, und dort sagt
-- es nur DASS, nicht wie viele.
local schirm = HudChrome.Screen(screenGui, {
	name = "GiftPanel",
	title = "TIME GIFTS",
	subtitle = "",
})
local panel = schirm.panel
local statusLabel = schirm.subtitle
local giftCloseButton = schirm.close

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(panel)

giftCloseButton.MouseButton1Click:Connect(function()
	panel.Visible = false
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	end
end)

local grid = Instance.new("ScrollingFrame")
-- Im Inhaltsbereich: die Kopfhoehe ist dort schon abgezogen.
grid.Size = UDim2.new(1, -32, 1, -24)
grid.Position = UDim2.new(0, 16, 0, 12)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 8
grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.Parent = schirm.content

local gridLayout = Instance.new("UIGridLayout")
-- Vorher 135x110. Auf einem Vollbild-Bildschirm standen zwoelf Briefmarken in einer
-- Ecke; das Symbol war zu klein, um die Belohnung zu erkennen.
gridLayout.CellSize = UDim2.new(0, 210, 0, 180)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

-- Die 210 oben sind jetzt nur noch die MINDESTBREITE. Fest gesetzt liessen sie auf einem
-- Telefon rechts einen toten Streifen von rund 190 Pixeln stehen -- zwei Karten passten
-- hinein, fuer die dritte fehlten zwanzig Pixel. Die Karten fuellen die Breite nun aus,
-- und ihre Hoehe waechst im gleichen Verhaeltnis mit (180/210).
ResponsiveGridUtils.Bind(grid, gridLayout, 6, 210, 180 / 210)

local giftCells = {} -- [n] = { button=, overlay=, timeLabel=, iconLabel= }

for n = 1, giftCountValue.Value do
	local cell = Instance.new("TextButton")
	cell.Name = "Gift" .. n
	cell.LayoutOrder = n
	cell.AutoButtonColor = false
	cell.Text = ""
	cell.Parent = grid
	-- Vorher pink. Nach Regel 2 bedeutet Farbe eine Messung, und "Geschenk" ist keine --
	-- zwoelf pinke Kacheln waren nur die lauteste Flaeche im ganzen Menue. Was hier
	-- wirklich zwei Zustaende hat, ist abholbar gegen gesperrt, und das traegt der Ueberzug.
	HudChrome.Panel(cell, { radius = HudChrome.Radius.Panel, fill = HudChrome.Color.PanelRaised })

	local numberLabel = Instance.new("TextLabel")
	numberLabel.Size = UDim2.new(1, -16, 0, 22)
	numberLabel.Position = UDim2.new(0, 8, 0, 8)
	numberLabel.BackgroundTransparency = 1
	numberLabel.TextXAlignment = Enum.TextXAlignment.Left
	numberLabel.Text = "#" .. n
	HudChrome.Number(numberLabel, 16)
	numberLabel.TextColor3 = HudChrome.Color.TextDim
	numberLabel.ZIndex = 2
	numberLabel.Parent = cell

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 0, 72)
	iconLabel.Position = UDim2.new(0, 0, 0, 30)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextScaled = true
	-- Das Symbol der TATSAECHLICHEN Belohnung. Vorher stand hier bei allen zwoelf
	-- Geschenken dasselbe Paket -- die Karte sagte damit nichts ueber ihren Inhalt.
	local iconValue = giftIconsFolder and giftIconsFolder:FindFirstChild("Gift" .. n)
	iconLabel.Text = iconValue and iconValue.Value or "🎁"
	iconLabel.ZIndex = 2
	iconLabel.Parent = cell

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -20, 0, 56)
	descLabel.Position = UDim2.new(0, 10, 0, 108)
	descLabel.BackgroundTransparency = 1
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	HudChrome.MenuBody(descLabel, HudChrome.MenuTextSize.Caption)
	local desc = giftDescriptionsFolder:FindFirstChild("Gift" .. n)
	descLabel.Text = desc and desc.Value or ""
	descLabel.ZIndex = 2
	descLabel.Parent = cell

	-- Heller, halbtransparenter Grau-Überzug für gesperrte Geschenke (Icon bleibt farbig
	-- sichtbar, wirkt nur "ausgegraut") + kleiner Countdown-Streifen unten
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	-- Gesperrtes wird ABGEDUNKELT, nicht aufgehellt. Der helle Grauschleier von vorher
	-- stammte aus dem Comic-Stil, wo der Grund hell war; auf dem dunklen Feld hier machte
	-- er die gesperrte Karte HELLER als die abholbare -- also genau falsch herum.
	overlay.BackgroundColor3 = HudChrome.Color.PanelSunken
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 3
	overlay.Parent = cell
	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, HudChrome.Radius.Panel)
	overlayCorner.Parent = overlay

	local timeLabel = Instance.new("TextLabel")
	-- Mittig statt am unteren Rand: der Countdown IST der Inhalt einer gesperrten Karte.
	-- Ein Streifen unten las sich wie eine Fussnote zu etwas, das man sowieso nicht anfassen
	-- kann.
	timeLabel.Size = UDim2.new(1, 0, 0, 30)
	timeLabel.Position = UDim2.new(0, 0, 0.5, -15)
	timeLabel.BackgroundTransparency = 1
	timeLabel.ZIndex = 4
	timeLabel.Text = "--:--"
	timeLabel.Parent = overlay
	HudChrome.NumberBold(timeLabel, 22)

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
	stroke.Color = HudChrome.Color.Ready
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
	local claimableCount = 0

	for n = 1, giftCountValue.Value do
		local ui = giftCells[n]
		local unlockTimeValue = giftUnlockTimesFolder:FindFirstChild("Gift" .. n)
		local marker = claimedFolder:FindFirstChild("Gift" .. n)
		if ui and unlockTimeValue and marker then
			local claimed = marker.Value
			local ready = elapsed >= unlockTimeValue.Value

			if claimed then
				ui.overlay.Visible = true
				ui.overlay.BackgroundTransparency = 0.35
				ui.timeLabel.Text = "CLAIMED"
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
				claimableCount += 1
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

	-- Die Unterzeile im Kopf sagt, WIE VIELE bereitliegen. Das Laempchen in der Navigation
	-- sagt nur, DASS etwas bereitliegt -- wer das Menue offen hat, will die Zahl.
	statusLabel.Text = claimableCount > 0
			and string.format("%d ready to claim", claimableCount)
		or "Nothing ready yet"
	statusLabel.TextColor3 = claimableCount > 0 and HudChrome.Color.Ready or HudChrome.Color.TextSecondary
end)