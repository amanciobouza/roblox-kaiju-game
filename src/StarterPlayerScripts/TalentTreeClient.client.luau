-- VERSION: 2026-08-25 #3
-- LocalScript: TalentTreeClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt den Diablo-artigen Talentbaum aller drei Fraktionen als verzweigte Baum-Ansicht
-- (Start-Knoten oben, drei Zweige darunter, Cross-Synergie + Ultimate am Ende). Nur
-- Kaijus Knoten haben echte Wirkung (siehe TalentTreeService.lua).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
-- Nur fuer das Forschungsfeld im HUD. Der Talentbaum selbst bleibt vorerst im
-- Comic-Stil -- Menues kommen nach dem HUD dran.
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TalentTreeConfig = require(ReplicatedStorage:WaitForChild("TalentTreeConfig"))
local StartResearchEvent = RemoteEventUtils.GetOrCreate("StartResearchEvent")
local CancelResearchEvent = RemoteEventUtils.GetOrCreate("CancelResearchEvent")
local ResearchCompleteEvent = RemoteEventUtils.GetOrCreate("ResearchCompleteEvent")
local GetTalentStateFunction = ReplicatedStorage:WaitForChild("GetTalentStateFunction")

-- Farben und Symbole kommen aus HudChrome. Hier standen eigene Kopien -- bei Heat mit einer
-- anderen Farbe als im Rest des Spiels -- und drei Emoji fuer die Figuren.
local ENERGY_COLORS = HudChrome.EnergyColor

local FACTION_TABS = {
	{ key = "Kaiju", label = "Kaiju" },
	{ key = "Jaeger", label = "Jaeger" },
	{ key = "Ronin", label = "Ronin" },
}

-- Bild wenn hochgeladen, sonst das Zeichen aus dem Config.
--
-- Beide sitzen an derselben Stelle und in derselben Groesse, damit der Wechsel nichts
-- verschiebt -- dieselbe Ausweichregel wie bei den Energien und den Geschenken. Solange
-- Jaeger und Ronin nur Vorschau sind, tragen ihre Knoten weiterhin Zeichen; das ist kein
-- Zwischenzustand, sondern der ehrliche Stand.
local function zeigeTalentSymbol(bildLabel, textLabel, talent)
	local bildId = HudChrome.TalentIcon[talent.id] or ""
	if bildId ~= "" then
		bildLabel.Image = bildId
		bildLabel.Visible = true
		textLabel.Visible = false
	else
		bildLabel.Visible = false
		textLabel.Text = talent.icon
		textLabel.Visible = true
	end
end

local function formatDuration(seconds)
	seconds = math.max(math.floor(seconds), 0)
	if seconds >= 3600 then
		return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
	elseif seconds >= 60 then
		return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
	end
	return seconds .. "s"
end

local screenGui = Instance.new("ScreenGui")
screenGui.IgnoreGuiInset = true
screenGui.Name = "TalentTreeGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- WICHTIG: hoher DisplayOrder sorgt dafür, dass dieses GUI immer ÜBER anderen ScreenGuis
-- liegt (z.B. den Angriffs-Buttons) -- unabhängig davon, welches Script zuerst lädt.
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

local schirm = HudChrome.Screen(screenGui, {
	name = "TalentTreePanel",
	title = "TALENTS",
	subtitle = "",
})
local panel = schirm.panel

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(panel)

-- ===== Fraktions-Tabs =====
-- In der Kopfzeile, mittig -- wie im Skin-Laden. Es sind dieselben drei Figuren, und sie
-- sollen dort dasselbe tun und gleich aussehen.
local tabRow = Instance.new("Frame")
tabRow.AnchorPoint = Vector2.new(0.5, 0.5)
tabRow.Position = UDim2.new(0.5, 0, 0.5, 0)
tabRow.Size = UDim2.new(0, 3 * 44 + 2 * 8, 0, 44)
tabRow.BackgroundTransparency = 1
tabRow.ZIndex = 4
tabRow.Parent = schirm.header

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabRow

-- ===== Ressourcen-Leiste (5 Energien + Coins) =====
local resourceRow = Instance.new("Frame")
resourceRow.Size = UDim2.new(1, -24, 0, 30)
resourceRow.Position = UDim2.new(0, 12, 0, 8)
resourceRow.BackgroundTransparency = 1
resourceRow.Parent = schirm.content

local resourceLayout = Instance.new("UIListLayout")
resourceLayout.FillDirection = Enum.FillDirection.Horizontal
resourceLayout.Padding = UDim.new(0, 12)
resourceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
resourceLayout.Parent = resourceRow

-- Bild und Zahl getrennt, nicht beides in einer Zeichenkette. Ein Emoji im Text sitzt auf
-- der Grundlinie und ist je nach Geraet verschieden breit -- die Zahl sprang dadurch von
-- Energie zu Energie.
local resourceLabels = {}
local function baueRessource(bildId, farbe)
	local halter = Instance.new("Frame")
	halter.Size = UDim2.new(0, 96, 1, 0)
	halter.BackgroundTransparency = 1
	halter.Parent = resourceRow

	local bild = HudChrome.IconImage(halter, bildId or "")
	bild.Size = UDim2.new(0, 24, 0, 24)
	bild.Position = UDim2.new(0, 0, 0.5, -12)
	bild.Visible = (bildId or "") ~= ""

	local zahl = Instance.new("TextLabel")
	zahl.Size = UDim2.new(1, -30, 1, 0)
	zahl.Position = UDim2.new(0, 30, 0, 0)
	zahl.BackgroundTransparency = 1
	zahl.TextXAlignment = Enum.TextXAlignment.Left
	zahl.Text = "0"
	zahl.Parent = halter
	HudChrome.Number(zahl, 17)
	zahl.TextColor3 = farbe
	return zahl
end

for _, energyType in ipairs(TalentTreeConfig.EnergyOrder) do
	resourceLabels[energyType] = baueRessource(
		HudChrome.EnergyIcon[energyType],
		ENERGY_COLORS[energyType] or HudChrome.Color.TextPrimary
	)
end
local coinsLabel = baueRessource(HudChrome.Icon.Coin, Color3.fromRGB(255, 205, 60))

-- ===== Aktive Forschung: Fortschrittsbalken + Abbrechen-Button =====
local researchBar = Instance.new("Frame")
researchBar.Size = UDim2.new(1, -24, 0, 34)
researchBar.Position = UDim2.new(0, 12, 0, 44)
researchBar.Visible = false
researchBar.Parent = schirm.content
HudChrome.Panel(researchBar, { radius = HudChrome.Radius.Small, fill = HudChrome.Color.PanelSunken })

-- Fortschritts-Füllung: wächst von links nach rechts, je näher die Forschung am Ende ist.
local researchProgressFill = Instance.new("Frame")
researchProgressFill.Size = UDim2.new(0, 0, 1, 0)
researchProgressFill.BackgroundColor3 = HudChrome.Color.Ready
researchProgressFill.BackgroundTransparency = 0.7
researchProgressFill.BorderSizePixel = 0
researchProgressFill.ZIndex = 1
researchProgressFill.Parent = researchBar
local researchProgressFillCorner = Instance.new("UICorner")
researchProgressFillCorner.CornerRadius = UDim.new(0, HudChrome.Radius.Small)
researchProgressFillCorner.Parent = researchProgressFill

local researchLabel = Instance.new("TextLabel")
researchLabel.Size = UDim2.new(1, -100, 1, 0)
researchLabel.Position = UDim2.new(0, 10, 0, 0)
researchLabel.BackgroundTransparency = 1
researchLabel.TextXAlignment = Enum.TextXAlignment.Left
researchLabel.Text = ""
researchLabel.ZIndex = 2
researchLabel.Parent = researchBar
HudChrome.Label(researchLabel, HudChrome.MenuTextSize.Caption)

local cancelResearchButton = Instance.new("TextButton")
cancelResearchButton.Size = UDim2.new(0, 80, 0, 22)
cancelResearchButton.AnchorPoint = Vector2.new(1, 0.5)
cancelResearchButton.Position = UDim2.new(1, -8, 0.5, 0)
cancelResearchButton.AutoButtonColor = false
cancelResearchButton.Text = "CANCEL"
cancelResearchButton.ZIndex = 2
cancelResearchButton.Parent = researchBar
-- Der Abbruch traegt seinen Rand in Danger und nicht die ganze Flaeche. Rot heisst hier
-- wirklich etwas -- eine laufende Forschung verwerfen --, aber es ist ein Rand, kein Alarm.
local _, cancelStroke = HudChrome.Panel(cancelResearchButton, {
	radius = HudChrome.Radius.Small,
	fill = HudChrome.Color.Panel,
})
cancelStroke.Color = HudChrome.Color.Danger
HudChrome.Label(cancelResearchButton, 14)
cancelResearchButton.TextColor3 = HudChrome.Color.Danger
cancelResearchButton.MouseButton1Click:Connect(function()
	CancelResearchEvent:FireServer()
end)

-- ===== Baum-Bereich (scrollbar, absolute Positionierung nach Tier/Zweig) =====
local treeScroll = Instance.new("ScrollingFrame")
treeScroll.Size = UDim2.new(0, 960, 1, -104)
treeScroll.Position = UDim2.new(0, 12, 0, 88)
treeScroll.BackgroundColor3 = HudChrome.Color.PanelSunken
treeScroll.BorderSizePixel = 0
treeScroll.ScrollBarThickness = 6
treeScroll.CanvasSize = UDim2.new(0, 960, 0, 900)
-- WICHTIG: ScrollingFrame clippt seinen Inhalt NICHT automatisch (anders als man
-- erwarten würde) -- ohne das hier explizit zu setzen, konnten Verbindungslinien über
-- den Fensterrand hinausragen und sogar das restliche HUD überlagern.
treeScroll.ClipsDescendants = true
treeScroll.Parent = schirm.content
HudChrome.Panel(treeScroll, { radius = HudChrome.Radius.Panel, fill = false })

-- Skaliert ALLE Knoten und Verbindungslinien im Baum gemeinsam. Sie stehen auf festen
-- Koordinaten einer 960x900-Flaeche -- ohne diesen Faktor sah ein Telefon davon nur einen
-- Ausschnitt, und ein grosser Monitor liess den Rest der Flaeche leer.
local treeScale = Instance.new("UIScale")
treeScale.Scale = 1
treeScale.Parent = treeScroll

-- Baum und Detailspalte teilen sich die Breite. Beide standen vorher auf festen Werten
-- (960 und 268 Pixel ab Position 8 beziehungsweise 976). Auf einem Vollbild-Bildschirm
-- blieb dadurch rechts ein Drittel der Flaeche leer, waehrend die Textspalte auf 268 Pixel
-- eingeengt war -- der Text darin brach nach zwei, drei Woertern um.
--
-- Der Baum hatte danach eine Hoechstbreite von 960 Pixeln, mit der Begruendung, ihn zu
-- dehnen erzeuge nur Leerraum im Rollbereich -- er ist ja mit festen Koordinaten auf einer
-- 960x900-Flaeche aufgebaut. Das stimmte, solange er nicht skaliert wurde. Seit er das
-- wird (treeScale weiter unten), bekommt er den ganzen Rest der Breite, und der Block
-- steht nicht mehr mittig, sondern fuellt die Flaeche.
local DETAIL_MIN_WIDTH = 300
local DETAIL_MAX_WIDTH = 520
local COLUMN_GAP = 8

-- ===== Telefon im Querformat =====
-- Die Detailspalte bleibt IMMER rechts. Auf dem Telefon wird im Querformat gespielt: dort
-- ist die Breite reichlich und die HOEHE knapp -- Baum und Details uebereinander zu
-- stapeln wuerde genau die knappe Groesse verbrauchen.
--
-- Stattdessen zwei Stellschrauben. Erstens darf die Detailspalte auf schmalen Geraeten
-- schmaler werden als die 300 Pixel, die sie am Monitor mindestens bekommt -- feste 300
-- von 640 sind fast die halbe Flaeche. Zweitens wird der Baum SKALIERT statt
-- abgeschnitten: seine Knoten stehen auf festen Koordinaten einer 960x900-Flaeche, und
-- ohne Skalierung sah ein Telefon davon 316 mal 254 Pixel, also ein Achtel.
local DETAIL_WIDTH_FRACTION = 0.3
local DETAIL_MIN_FRACTION = 0.32 -- so viel darf die Detailspalte hoechstens vom Bildschirm nehmen

-- Grenzen der Baum-Skalierung. Nach unten, damit die Beschriftung lesbar bleibt -- lieber
-- rollen als eine unleserliche Uebersicht. Nach oben, damit auf einem grossen Monitor
-- keine handtellergrossen Knoten entstehen.
local TREE_MIN_SCALE = 0.55
local TREE_MAX_SCALE = 1.5
local TREE_CANVAS_WIDTH = 960
local TREE_CANVAS_HEIGHT = 900

-- Oberkante des Inhalts, unter Titelzeile und Ressourcenleiste.
local CONTENT_TOP = 106

-- ===== Detail-Panel: zeigt das AUSGEWÄHLTE Talent -- Icon/Name, Beschreibung, Kosten,
-- Forschungszeit, und einen "Vorher -> Nachher"-Wertevergleich. =====
local detailPanel = Instance.new("Frame")
detailPanel.Size = UDim2.new(0, 268, 1, -104)
detailPanel.Position = UDim2.new(0, 980, 0, 88)
detailPanel.Parent = schirm.content
HudChrome.Panel(detailPanel, {
	radius = HudChrome.Radius.Panel,
	fill = HudChrome.Color.PanelRaised,
	transparency = 0,
})

-- Flaeche, die den Kindern des Panels tatsaechlich zur Verfuegung steht.
--
-- AbsoluteSize ist die Groesse des Panels SELBST. TopInsetUtils legt darauf ein UIPadding
-- (48 Pixel oben fuer die Roblox-Systemleiste, 8 unten), und Kinder beginnen erst
-- darunter. Wer mit AbsoluteSize rechnet und Hoehen als festen Versatz setzt, baut ein
-- Kind, das 56 Pixel zu hoch ist -- es reicht unter den Bildschirmrand, und alles, was an
-- seiner Unterkante haengt, verschwindet.
--
-- Genau so ist der Research-Knopf verschwunden. Vorher waren die Hoehen skalenbasiert
-- (1, -110) und haben das Polster deshalb von selbst beruecksichtigt; beim Umbau auf feste
-- Hoehen -- die der Baum fuer seine Skalierung braucht -- ging das verloren.
local function contentSize()
	local width = panel.AbsoluteSize.X
	local height = panel.AbsoluteSize.Y
	local padding = panel:FindFirstChildOfClass("UIPadding")
	if padding then
		width -= padding.PaddingLeft.Offset + padding.PaddingLeft.Scale * width
		width -= padding.PaddingRight.Offset + padding.PaddingRight.Scale * panel.AbsoluteSize.X
		height -= padding.PaddingTop.Offset + padding.PaddingTop.Scale * height
		height -= padding.PaddingBottom.Offset + padding.PaddingBottom.Scale * panel.AbsoluteSize.Y
	end
	return width, height
end

-- Kopfbereich und beide Spalten neu setzen, sobald sich die Fenstergroesse aendert.
local function layoutColumns()
	local width, height = contentSize()
	if width <= 0 or height <= 0 then
		return
	end

	-- Kopfzeile: Titel und Tabs bleiben NEBENEINANDER, schrumpfen aber mit. Fest standen
	-- sie auf 300 plus 400 Pixeln, brauchten also 720 Mindestbreite -- auf einem Telefon
	-- mit 640 lief die Tab-Reihe rechts aus dem Bild. Sie untereinander zu setzen waere
	-- der naheliegende Ausweg, kostet im Querformat aber die knappe Hoehe.
	-- Den Titel setzt seit dem Umbau die Kopfzeile von HudChrome.Screen -- ein eigenes
	-- TextLabel gibt es hier nicht mehr. Die Breite bleibt trotzdem stehen: die Tab-Reihe
	-- richtet sich weiter danach aus, und ihre Position von Hand zu ändern wäre eine
	-- Layout-Entscheidung, keine Fehlerbehebung.
	local titleWidth = math.clamp(math.floor(width * 0.3), 140, 300)
	tabRow.Position = UDim2.new(0, titleWidth + 24, 0, 8)
	tabRow.Size = UDim2.new(0, math.max(width - titleWidth - 36, 120), 0, 32)
	resourceRow.Position = UDim2.new(0, 8, 0, 44)

	-- Die Detailspalte bleibt rechts, darf aber nie mehr als DETAIL_MIN_FRACTION des
	-- Bildschirms beanspruchen: feste 300 Pixel waeren auf einem 640er Telefon fast die
	-- halbe Flaeche.
	local detailFloor = math.min(DETAIL_MIN_WIDTH, math.floor(width * DETAIL_MIN_FRACTION))
	local detailWidth = math.clamp(
		math.floor(width * DETAIL_WIDTH_FRACTION),
		detailFloor,
		DETAIL_MAX_WIDTH
	)

	-- Der Baum bekommt den GANZEN Rest -- nicht mehr hoechstens 960 Pixel. Damit bleibt auf
	-- einem breiten Monitor rechts und links kein Rand mehr leer.
	local treeWidth = math.max(width - detailWidth - 3 * COLUMN_GAP, 160)
	local treeHeight = math.max(height - CONTENT_TOP - COLUMN_GAP, 120)

	treeScroll.Position = UDim2.new(0, COLUMN_GAP, 0, CONTENT_TOP)
	treeScroll.Size = UDim2.new(0, treeWidth, 0, treeHeight)
	detailPanel.Position = UDim2.new(0, COLUMN_GAP + treeWidth + COLUMN_GAP, 0, CONTENT_TOP)
	detailPanel.Size = UDim2.new(0, detailWidth, 0, treeHeight)

	-- Baum skalieren statt abschneiden. Die Knoten stehen auf festen Koordinaten einer
	-- 960x900-Flaeche; der Faktor passt sie an den vorhandenen Platz an. Die CanvasSize
	-- muss MITSKALIERT werden -- ein UIScale veraendert sie nicht von selbst, und ohne die
	-- Anpassung liefe der Rollbereich ins Leere oder schnitte ab.
	local scale = math.clamp(
		math.min(treeWidth / TREE_CANVAS_WIDTH, treeHeight / TREE_CANVAS_HEIGHT),
		TREE_MIN_SCALE,
		TREE_MAX_SCALE
	)
	treeScale.Scale = scale
	treeScroll.CanvasSize = UDim2.new(
		0, math.floor(TREE_CANVAS_WIDTH * scale),
		0, math.floor(TREE_CANVAS_HEIGHT * scale)
	)
end

panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutColumns)

-- Auch auf das Polster hören, nicht nur auf die Fenstergrösse. TopInsetUtils liest die
-- Höhe der Roblox-Systemleiste nicht nur einmal, sondern zieht sie nach -- bei jeder
-- Änderung der Leiste und zusätzlich zeitversetzt, weil sie beim Start noch null meldet.
-- Wenn sich dabei das Polster ändert, bleibt AbsoluteSize gleich; ohne diese Verbindung
-- rechnete die Anordnung weiter mit dem alten Wert und die Detailspalte stünde wieder ein
-- Stück zu tief.
local panelPadding = panel:FindFirstChildOfClass("UIPadding")
if panelPadding then
	panelPadding:GetPropertyChangedSignal("PaddingTop"):Connect(layoutColumns)
	panelPadding:GetPropertyChangedSignal("PaddingBottom"):Connect(layoutColumns)
end

layoutColumns()

local detailEmpty = Instance.new("TextLabel")
detailEmpty.Size = UDim2.new(1, -20, 0, 80)
detailEmpty.Position = UDim2.new(0, 10, 0, 20)
detailEmpty.BackgroundTransparency = 1
detailEmpty.TextColor3 = Color3.fromRGB(140, 140, 150)
detailEmpty.Text = "👆 Pick a talent to see its details."
HudChrome.MenuBody(detailEmpty)
detailEmpty.Parent = detailPanel

local detailIconBild = Instance.new("ImageLabel")

local detailIcon = Instance.new("TextLabel")
detailIcon.Size = UDim2.new(0, 60, 0, 60)
detailIcon.Position = UDim2.new(0, 10, 0, 10)
detailIcon.TextScaled = true
detailIcon.Text = ""
detailIcon.Visible = false
detailIcon.Parent = detailPanel
HudChrome.Panel(detailIcon, {
	radius = HudChrome.Radius.Panel,
	fill = HudChrome.Color.PanelSunken,
	transparency = 0,
})

-- Das Bild liegt IM Kaestchen, nicht daneben: das Kaestchen traegt Rahmen und Grund, und
-- die beiden Sorten Symbol teilen es sich.
detailIconBild.Name = "DetailIconImage"
detailIconBild.Size = UDim2.new(1, -14, 1, -14)
detailIconBild.Position = UDim2.new(0, 7, 0, 7)
detailIconBild.BackgroundTransparency = 1
detailIconBild.ScaleType = Enum.ScaleType.Fit
detailIconBild.Visible = false
detailIconBild.Parent = detailIcon

local detailName = Instance.new("TextLabel")
detailName.Size = UDim2.new(1, -84, 0, 30)
detailName.Position = UDim2.new(0, 78, 0, 10)
detailName.BackgroundTransparency = 1
HudChrome.Label(detailName, 18)
detailName.TextXAlignment = Enum.TextXAlignment.Left
detailName.TextColor3 = Color3.new(1, 1, 1)
detailName.TextWrapped = true
detailName.Text = ""
detailName.Visible = false
detailName.Parent = detailPanel

local detailLevel = Instance.new("TextLabel")
detailLevel.Size = UDim2.new(1, -84, 0, 20)
detailLevel.Position = UDim2.new(0, 78, 0, 42)
detailLevel.BackgroundTransparency = 1
HudChrome.MenuBody(detailLevel, 14)
detailLevel.TextXAlignment = Enum.TextXAlignment.Left
detailLevel.TextColor3 = Color3.fromRGB(180, 180, 190)
detailLevel.Text = ""
detailLevel.Visible = false
detailLevel.Parent = detailPanel

local detailDescription = Instance.new("TextLabel")
detailDescription.Size = UDim2.new(1, -20, 0, 90)
detailDescription.Position = UDim2.new(0, 10, 0, 78)
detailDescription.BackgroundTransparency = 1
HudChrome.MenuBody(detailDescription)
detailDescription.TextXAlignment = Enum.TextXAlignment.Left
detailDescription.TextYAlignment = Enum.TextYAlignment.Top
detailDescription.TextColor3 = Color3.fromRGB(210, 210, 220)
detailDescription.Text = ""
detailDescription.Visible = false
detailDescription.Parent = detailPanel

-- Vorher/Nachher-Wertevergleich
local detailStatsHeader = Instance.new("TextLabel")
detailStatsHeader.Size = UDim2.new(1, -20, 0, 18)
detailStatsHeader.Position = UDim2.new(0, 10, 0, 172)
detailStatsHeader.BackgroundTransparency = 1
HudChrome.Label(detailStatsHeader, 14)
detailStatsHeader.TextXAlignment = Enum.TextXAlignment.Left
detailStatsHeader.TextColor3 = Color3.fromRGB(255, 210, 80)
detailStatsHeader.Text = "STATS"
detailStatsHeader.Visible = false
detailStatsHeader.Parent = detailPanel

local detailStatPrimary = Instance.new("TextLabel")
detailStatPrimary.Size = UDim2.new(1, -20, 0, 22)
detailStatPrimary.Position = UDim2.new(0, 10, 0, 192)
detailStatPrimary.BackgroundTransparency = 1
HudChrome.MenuBody(detailStatPrimary, 14)
detailStatPrimary.TextXAlignment = Enum.TextXAlignment.Left
detailStatPrimary.TextColor3 = Color3.fromRGB(120, 220, 140)
detailStatPrimary.Text = ""
detailStatPrimary.Visible = false
detailStatPrimary.Parent = detailPanel

local detailStatTradeoff = Instance.new("TextLabel")
detailStatTradeoff.Size = UDim2.new(1, -20, 0, 22)
detailStatTradeoff.Position = UDim2.new(0, 10, 0, 216)
detailStatTradeoff.BackgroundTransparency = 1
HudChrome.MenuBody(detailStatTradeoff, 14)
detailStatTradeoff.TextXAlignment = Enum.TextXAlignment.Left
detailStatTradeoff.TextColor3 = Color3.fromRGB(230, 140, 40)
detailStatTradeoff.Text = ""
detailStatTradeoff.Visible = false
detailStatTradeoff.Parent = detailPanel

-- Kosten + Forschungszeit
local detailCostHeader = Instance.new("TextLabel")
detailCostHeader.Size = UDim2.new(1, -20, 0, 18)
detailCostHeader.Position = UDim2.new(0, 10, 0, 250)
detailCostHeader.BackgroundTransparency = 1
HudChrome.Label(detailCostHeader, 14)
detailCostHeader.TextXAlignment = Enum.TextXAlignment.Left
detailCostHeader.TextColor3 = Color3.fromRGB(255, 210, 80)
detailCostHeader.Text = "COST"
detailCostHeader.Visible = false
detailCostHeader.Parent = detailPanel

local detailCostEnergy = Instance.new("TextLabel")
detailCostEnergy.Size = UDim2.new(1, -20, 0, 24)
detailCostEnergy.Position = UDim2.new(0, 10, 0, 270)
detailCostEnergy.BackgroundTransparency = 1
HudChrome.MenuBody(detailCostEnergy, 14)
detailCostEnergy.TextXAlignment = Enum.TextXAlignment.Left
detailCostEnergy.TextColor3 = Color3.new(1, 1, 1)
detailCostEnergy.Text = ""
detailCostEnergy.Visible = false
detailCostEnergy.Parent = detailPanel

local detailCostCoins = Instance.new("TextLabel")
detailCostCoins.Size = UDim2.new(1, -20, 0, 24)
detailCostCoins.Position = UDim2.new(0, 10, 0, 296)
detailCostCoins.BackgroundTransparency = 1
HudChrome.MenuBody(detailCostCoins, 14)
detailCostCoins.TextXAlignment = Enum.TextXAlignment.Left
detailCostCoins.TextColor3 = Color3.fromRGB(255, 220, 80)
detailCostCoins.Text = ""
detailCostCoins.Visible = false
detailCostCoins.Parent = detailPanel

local detailResearchTime = Instance.new("TextLabel")
detailResearchTime.Size = UDim2.new(1, -20, 0, 24)
detailResearchTime.Position = UDim2.new(0, 10, 0, 322)
detailResearchTime.BackgroundTransparency = 1
HudChrome.MenuBody(detailResearchTime, 14)
detailResearchTime.TextXAlignment = Enum.TextXAlignment.Left
detailResearchTime.TextColor3 = Color3.fromRGB(180, 180, 220)
detailResearchTime.Text = ""
detailResearchTime.Visible = false
detailResearchTime.Parent = detailPanel

local detailPrereqLabel = Instance.new("TextLabel")
detailPrereqLabel.Size = UDim2.new(1, -20, 0, 40)
detailPrereqLabel.Position = UDim2.new(0, 10, 0, 352)
detailPrereqLabel.BackgroundTransparency = 1
HudChrome.MenuBody(detailPrereqLabel, 14)
detailPrereqLabel.TextWrapped = true
detailPrereqLabel.TextXAlignment = Enum.TextXAlignment.Left
detailPrereqLabel.TextColor3 = Color3.fromRGB(230, 100, 100)
detailPrereqLabel.Text = ""
detailPrereqLabel.Visible = false
detailPrereqLabel.Parent = detailPanel

local detailResearchButton = Instance.new("TextButton")
detailResearchButton.Size = UDim2.new(1, -20, 0, 40)
detailResearchButton.Position = UDim2.new(0, 10, 1, -50)
detailResearchButton.BackgroundColor3 = Color3.fromRGB(90, 170, 100)

detailResearchButton.TextScaled = true
detailResearchButton.TextColor3 = Color3.new(1, 1, 1)
detailResearchButton.Text = "🔬 RESEARCH"
detailResearchButton.Visible = false
detailResearchButton.Parent = detailPanel
HudChrome.Panel(detailResearchButton, { radius = HudChrome.Radius.Small })
HudChrome.Label(detailResearchButton, HudChrome.MenuTextSize.Caption)

local closeButton = schirm.close
closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
	-- Kehrt zum Hamburger-Menü zurück (ersetzt den früheren separaten "← Back"-Button).
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	end
end)

-- ===== Zustand =====
local talentState = { levels = { Kaiju = {}, Jaeger = {}, Ronin = {} }, energy = {}, coins = 0, research = nil }

-- ===== Lesbare Namen + Formatierung für die Effekt-Schlüssel aus der Config =====
local STAT_LABELS = {
	RootDamageBonus = "Total Damage",
	UltimateDamageBonus = "Total Damage",
	BerserkerDamageBonus = "Berserker Damage Bonus",
	OverheatDamageBonus = "Berserker Damage Bonus",
	BerserkerThresholdPenalty = "Berserker Threshold (higher = harder to trigger)",
	MeltdownAttackSpeedBonus = "Meltdown Attack Speed",
	CooldownReduction = "Ability Cooldown Reduction",
	FocusDamageBonus = "Focus Attack Damage",
	FocusRangePenalty = "Focus Attack Range (lower = shorter)",
	ComboChainEnabled = "Combo Chain",
	AreaRadiusBonus = "Area Attack Radius",
	BlastRadiusBonus = "Area Attack Radius",
	AreaDamagePenalty = "Area Damage per Hit (lower = weaker)",
	CataclysmEnabled = "Cataclysm (every 4th hit)",
	HeatScaledAreaDamage = "Area Damage (scales with Heat, max)",
}

local function formatStatValue(effectKey, value)
	if effectKey == "ComboChainEnabled" or effectKey == "CataclysmEnabled" then
		return value > 0 and "Enabled" or "Disabled"
	end
	return string.format("%+.0f%%", value * 100)
end

-- Summiert den aktuellen Gesamtwert eines Effekt-Schlüssels über ALLE Knoten einer
-- Fraktion (optional mit einem simulierten "was wäre, wenn ich noch 1 Stufe hätte"-Stand).
local function getEffectTotal(factionName, effectKey, levelsOverride)
	local levels = levelsOverride or talentState.levels[factionName] or {}
	local total = 0
	for _, t in ipairs(TalentTreeConfig.GetTalentsForFaction(factionName)) do
		local level = levels[t.id] or 0
		if level > 0 then
			if t.effectKey == effectKey then
				total += level * t.effectPerLevel
			end
			if t.tradeoffEffectKey == effectKey then
				total += level * t.tradeoffEffectPerLevel
			end
		end
	end
	return total
end

local selectedTalentId = nil
local currentFaction = "Kaiju"
local nodeRefs = {}

local function requestState()
	local ok, result = pcall(function()
		return GetTalentStateFunction:InvokeServer()
	end)
	if ok and result then
		talentState = result
	end
end

local function updateResourceDisplay()
	for _, energyType in ipairs(TalentTreeConfig.EnergyOrder) do
		resourceLabels[energyType].Text = tostring(math.floor(talentState.energy[energyType] or 0))
	end
	coinsLabel.Text = tostring(math.floor(talentState.coins or 0))
end

-- ===== Positions-Berechnung: Zweig-Reihenfolge wird DYNAMISCH aus den Knoten
-- abgeleitet (funktioniert für jede Fraktion, unabhängig von den Zweig-Namen). =====
local function getBranchXPositions(nodes)
	local order = {}
	local seen = {}
	local EXCLUDED_BRANCHES = { Root = true, Synergy = true, Ultimate = true, Gap1_2 = true, Gap2_3 = true }
	for _, node in ipairs(nodes) do
		if not EXCLUDED_BRANCHES[node.branch] and not seen[node.branch] then
			seen[node.branch] = true
			table.insert(order, node.branch)
		end
	end
	local positions = {}
	for i, branchKey in ipairs(order) do
		positions[branchKey] = 160 + (i - 1) * 320
	end
	return positions, order
end

local GAP_BRANCHES = { Gap1_2 = true, Gap2_3 = true, Synergy = true } -- "Synergy" bleibt als Alias erhalten, falls irgendwo noch verwendet

local function getNodePosition(node, branchXPositions, branchOrder)
	local y
	if GAP_BRANCHES[node.branch] then
		-- Extra Puffer nach oben UND unten -- sonst kollidiert der Knoten mit den direkt
		-- benachbarten Zweig-Stufen (Tier 2 und Tier 3).
		y = 60 + node.tier * 165 + 40
	else
		y = 60 + node.tier * 165
	end
	local x
	if node.branch == "Root" or node.branch == "Ultimate" then
		x = 480 -- Start und Ultimate bleiben mittig -- betreffen ja alle Zweige gleichermassen
	elseif node.branch == "Gap1_2" or node.branch == "Synergy" then
		-- Zwischen dem ERSTEN und ZWEITEN Strang platziert.
		if branchOrder and branchXPositions[branchOrder[1]] and branchXPositions[branchOrder[2]] then
			x = (branchXPositions[branchOrder[1]] + branchXPositions[branchOrder[2]]) / 2
		else
			x = 320
		end
	elseif node.branch == "Gap2_3" then
		-- Zwischen dem ZWEITEN und DRITTEN Strang platziert.
		if branchOrder and branchXPositions[branchOrder[2]] and branchXPositions[branchOrder[3]] then
			x = (branchXPositions[branchOrder[2]] + branchXPositions[branchOrder[3]]) / 2
		else
			x = 640
		end
	else
		x = branchXPositions[node.branch] or 480
	end
	return Vector2.new(x, y)
end

-- Zeichnet ein einzelnes gerades Segment zwischen zwei Punkten -- Baustein für die
-- gebogene Kurve unten (viele kurze Segmente ergeben zusammen einen glatten Bogen).
local function drawLineSegment(fromPos, toPos, thickness)
	local delta = toPos - fromPos
	local distance = delta.Magnitude
	if distance < 0.5 then
		return
	end
	local angle = math.deg(math.atan2(delta.Y, delta.X))

	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Size = UDim2.new(0, distance + 1, 0, thickness) -- +1 Überlappung, damit keine Mini-Lücken zwischen Segmenten entstehen
	line.Position = UDim2.new(0, fromPos.X, 0, fromPos.Y)
	line.Rotation = angle
	line.BackgroundColor3 = Color3.fromRGB(80, 76, 98)
	line.BorderSizePixel = 0
	line.ZIndex = 60
	line.Parent = treeScroll
end

-- Gebogene Verbindungslinie: quadratische Bezier-Kurve (EIN Kontrollpunkt, wölbt sich
-- gleichmässig in EINE Richtung -- explizit KEINE S-Kurve, die bräuchte zwei
-- gegenläufige Kontrollpunkte). Wird aus vielen kurzen geraden Segmenten
-- zusammengesetzt, da Roblox-UI keine nativen Kurven kennt.
local function drawConnector(fromPos, toPos)
	local delta = toPos - fromPos
	local distance = delta.Magnitude
	if distance < 1 then
		return
	end

	-- Kontrollpunkt: Mittelpunkt der direkten Linie, senkrecht dazu leicht versetzt --
	-- ergibt eine gleichmässige Wölbung. Richtung des Versatzes hängt davon ab, ob das
	-- Ziel links oder rechts vom Start liegt, damit sich Zweig-Linien nicht gegenseitig
	-- durchkreuzen, sondern sauber auseinander wölben.
	local midpoint = (fromPos + toPos) / 2
	local perpendicular = Vector2.new(-delta.Y, delta.X)
	if perpendicular.Magnitude > 0.01 then
		perpendicular = perpendicular.Unit
	end
	local bowAmount = math.clamp(distance * 0.18, 10, 60)
	local bowDirection = (toPos.X >= fromPos.X) and 1 or -1
	local controlPoint = midpoint + perpendicular * bowAmount * bowDirection

	local segments = 14
	local previousPoint = fromPos
	for i = 1, segments do
		local t = i / segments
		local oneMinusT = 1 - t
		-- Quadratische Bezier-Formel: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
		local point = fromPos * (oneMinusT * oneMinusT) + controlPoint * (2 * oneMinusT * t) + toPos * (t * t)
		drawLineSegment(previousPoint, point, 5) -- breiter als vorher (war 3)
		previousPoint = point
	end
end

-- ===== Knoten-Status: gesperrt / erforschbar / in Forschung / voll ausgebaut =====
local function getNodeState(talent, level, isActiveFaction)
	if level >= talent.maxLevel then
		return "maxed"
	end
	if not isActiveFaction then
		return "preview"
	end
	local prereqsMet = true
	for _, prereq in ipairs(talent.prerequisites) do
		local prereqLevel = (talentState.levels[currentFaction] and talentState.levels[currentFaction][prereq.id]) or 0
		if prereqLevel < prereq.level then
			prereqsMet = false
			break
		end
	end
	if not prereqsMet then
		return "locked"
	end
	if talentState.research and talentState.research.talentId == talent.id and talentState.research.faction == currentFaction then
		return "researching"
	end
	if talentState.research then
		return "blocked"
	end
	return "available"
end

local STATE_COLORS = {
	maxed = Color3.fromRGB(90, 200, 110),
	preview = Color3.fromRGB(50, 48, 60),
	locked = Color3.fromRGB(35, 33, 42),
	researching = Color3.fromRGB(220, 180, 60),
	blocked = Color3.fromRGB(45, 42, 55),
	available = Color3.fromRGB(60, 56, 90),
}

-- ===== Zeigt die Details eines Talents im rechten Panel: Beschreibung, Vorher/Nachher-
-- Werte, Kosten (Energie + Coins), Forschungszeit, Vorstufen-Hinweis falls gesperrt. =====
local function selectTalent(talent, state, level)
	selectedTalentId = talent.id

	detailEmpty.Visible = false
	detailIcon.Visible = true
	detailName.Visible = true
	detailLevel.Visible = true
	detailDescription.Visible = true
	detailStatsHeader.Visible = true
	detailStatPrimary.Visible = true
	detailCostHeader.Visible = true
	detailCostEnergy.Visible = true
	detailResearchTime.Visible = true

	zeigeTalentSymbol(detailIconBild, detailIcon, talent)
	-- Der Rahmen traegt die Energiefarbe, nicht die Flaeche: sonst kaempft ein farbiger
	-- Grund mit dem Bild darauf.
	local detailIconStroke = detailIcon:FindFirstChildOfClass("UIStroke")
	if detailIconStroke then
		detailIconStroke.Color = ENERGY_COLORS[talent.energyType] or HudChrome.Color.Border
	end
	detailName.Text = talent.name
	detailLevel.Text = "Level " .. level .. " / " .. talent.maxLevel
	detailDescription.Text = talent.description

	-- Vorher -> Nachher: simuliert den Zustand MIT einer Stufe mehr auf diesem Talent,
	-- vergleicht den Gesamtwert des betroffenen Effekt-Schlüssels davor/danach.
	local currentLevels = talentState.levels[currentFaction] or {}
	local simulatedLevels = table.clone(currentLevels)
	simulatedLevels[talent.id] = math.min(level + 1, talent.maxLevel)

	local primaryLabel = STAT_LABELS[talent.effectKey] or talent.effectKey
	local currentPrimary = getEffectTotal(currentFaction, talent.effectKey, currentLevels)
	local newPrimary = getEffectTotal(currentFaction, talent.effectKey, simulatedLevels)
	detailStatPrimary.Text = string.format("%s: %s -> %s", primaryLabel, formatStatValue(talent.effectKey, currentPrimary), formatStatValue(talent.effectKey, newPrimary))

	if talent.tradeoffEffectKey then
		detailStatTradeoff.Visible = true
		local tradeoffLabel = STAT_LABELS[talent.tradeoffEffectKey] or talent.tradeoffEffectKey
		local currentTradeoff = getEffectTotal(currentFaction, talent.tradeoffEffectKey, currentLevels)
		local newTradeoff = getEffectTotal(currentFaction, talent.tradeoffEffectKey, simulatedLevels)
		detailStatTradeoff.Text = string.format("⚠️ %s: %s -> %s", tradeoffLabel, formatStatValue(talent.tradeoffEffectKey, currentTradeoff), formatStatValue(talent.tradeoffEffectKey, newTradeoff))
	else
		detailStatTradeoff.Visible = false
	end

	-- Kosten
	if level >= talent.maxLevel then
		detailCostEnergy.Text = "✅ Fully researched"
		detailCostCoins.Visible = false
		detailResearchTime.Text = ""
	else
		local cost = TalentTreeConfig.GetNodeCost(talent, level + 1)
		detailCostEnergy.Text = string.format("%s  %d", talent.energyType, cost.energyAmount)
		if cost.coinAmount > 0 then
			detailCostCoins.Visible = true
			detailCostCoins.Text = "💰 " .. cost.coinAmount
		else
			detailCostCoins.Visible = false
		end
		detailResearchTime.Text = "⏱️ Research time: " .. formatDuration(talent.researchSeconds)
	end

	-- Vorstufen-Hinweis, falls gesperrt
	if state == "locked" then
		local missing = {}
		for _, prereq in ipairs(talent.prerequisites) do
			local prereqLevel = (currentLevels[prereq.id]) or 0
			if prereqLevel < prereq.level then
				local prereqTalent = TalentTreeConfig.FindTalent(currentFaction, prereq.id)
				table.insert(missing, (prereqTalent and prereqTalent.name or prereq.id) .. " Lv." .. prereq.level)
			end
		end
		detailPrereqLabel.Visible = true
		detailPrereqLabel.Text = "🔒 Requires: " .. table.concat(missing, ", ")
	else
		detailPrereqLabel.Visible = false
	end

	-- Research-Button: nur aktiv, wenn wirklich verfügbar.
	if state == "available" then
		detailResearchButton.Visible = true
		detailResearchButton.Text = "🔬 RESEARCH"
		detailResearchButton.BackgroundColor3 = Color3.fromRGB(90, 170, 100)
		detailResearchButton.Active = true
	elseif state == "researching" then
		detailResearchButton.Visible = true
		detailResearchButton.Text = "🔬 Researching..."
		detailResearchButton.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
		detailResearchButton.Active = false
	elseif state == "maxed" then
		detailResearchButton.Visible = true
		detailResearchButton.Text = "✅ MAXED"
		detailResearchButton.BackgroundColor3 = Color3.fromRGB(70, 68, 80)
		detailResearchButton.Active = false
	else
		detailResearchButton.Visible = true
		detailResearchButton.Text = state == "blocked" and "⏳ Other research active" or "🔒 LOCKED"
		detailResearchButton.BackgroundColor3 = Color3.fromRGB(70, 68, 80)
		detailResearchButton.Active = false
	end
end

detailResearchButton.MouseButton1Click:Connect(function()
	if selectedTalentId and detailResearchButton.Active then
		StartResearchEvent:FireServer(currentFaction, selectedTalentId)
	end
end)

-- Aktualisiert die Detail-Ansicht für das aktuell ausgewählte Talent mit frischen Daten
-- (z.B. nachdem eine Forschung gestartet/abgeschlossen wurde).
local function refreshSelectedTalentDetails()
	if not selectedTalentId then
		return
	end
	local talent = TalentTreeConfig.FindTalent(currentFaction, selectedTalentId)
	if not talent then
		return
	end
	local level = (talentState.levels[currentFaction] and talentState.levels[currentFaction][selectedTalentId]) or 0
	local isActiveFaction = (talentState.activeFaction == currentFaction)
	local state = getNodeState(talent, level, isActiveFaction)
	selectTalent(talent, state, level)
end

local function buildNode(talent, position, isActiveFaction)
	local level = (talentState.levels[currentFaction] and talentState.levels[currentFaction][talent.id]) or 0
	local state = getNodeState(talent, level, isActiveFaction)

	local button = Instance.new("TextButton")
	button.Name = talent.id
	button.Size = UDim2.new(0, 88, 0, 88)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(0, position.X, 0, position.Y)
	button.BackgroundColor3 = STATE_COLORS[state]
	button.Text = ""
	button.ZIndex = 62
	button.Parent = treeScroll
	-- Rund: ein Knoten in einem Baum ist ein Punkt, keine Kachel. HudChrome.Pill setzt
	-- dafuer einen echten Halbkreis-Radius.
	local nodeCorner, nodeStroke = HudChrome.Pill(button, { fill = false })
	if talent.isTradeoff then
		nodeStroke.Color = Color3.fromRGB(230, 140, 40)
	elseif ENERGY_COLORS[talent.energyType] then
		nodeStroke.Color = ENERGY_COLORS[talent.energyType]
	end

	local iconBild = HudChrome.IconImage(button, "")
	iconBild.Size = UDim2.new(0, 34, 0, 34)
	iconBild.Position = UDim2.new(0.5, -17, 0, 6)
	iconBild.Visible = false
	iconBild.ZIndex = 63

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 0, 38)
	iconLabel.Position = UDim2.new(0, 0, 0, 4)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextScaled = true
	iconLabel.ZIndex = 63
	iconLabel.Parent = button

	zeigeTalentSymbol(iconBild, iconLabel, talent)

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.new(1, 0, 0, 16)
	levelLabel.Position = UDim2.new(0, 0, 0, 66)
	levelLabel.BackgroundTransparency = 1

	levelLabel.TextScaled = true
	levelLabel.TextColor3 = Color3.new(1, 1, 1)
	levelLabel.Text = level .. "/" .. talent.maxLevel
	levelLabel.ZIndex = 63
	levelLabel.Parent = button

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(0, 140, 0, 50)
	infoLabel.AnchorPoint = Vector2.new(0.5, 0)
	infoLabel.Position = UDim2.new(0, position.X, 0, position.Y + 48)
	infoLabel.BackgroundTransparency = 1

	infoLabel.TextScaled = true
	infoLabel.TextWrapped = true
	infoLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	infoLabel.Text = talent.name
	infoLabel.ZIndex = 61
	infoLabel.Parent = treeScroll

	button.MouseButton1Click:Connect(function()
		selectTalent(talent, state, level)
	end)

	-- "NEU"-Fahne: zeigt beim Oeffnen, WELCHE Forschung fertig geworden ist. Der Baum hat
	-- dreizehn Knoten je Fraktion -- ohne Markierung muesste man sie absuchen.
	local newFlag = Instance.new("TextLabel")
	newFlag.Name = "NewFlag"
	newFlag.AnchorPoint = Vector2.new(0.5, 0)
	newFlag.Size = UDim2.new(0, 44, 0, 18)
	newFlag.Position = UDim2.new(0.5, 0, 0, -8)
	newFlag.BackgroundColor3 = Color3.fromRGB(235, 45, 45)

	newFlag.TextScaled = true
	newFlag.TextColor3 = Color3.fromRGB(255, 255, 255)
	newFlag.Text = "NEW"
	newFlag.ZIndex = 64
	newFlag.Visible = (_G.GetNavBadgeItems and _G.GetNavBadgeItems("Talents")[talent.id]) == true
	newFlag.Parent = button
	HudChrome.Panel(newFlag, { radius = HudChrome.Radius.Small, fill = HudChrome.Color.Danger })
	HudChrome.Label(newFlag, 11)
	newFlag.TextColor3 = Color3.new(1, 1, 1)

	nodeRefs[talent.id] = { button = button, levelLabel = levelLabel, infoLabel = infoLabel, position = position, newFlag = newFlag }
end

local function renderTree(factionName)
	if factionName ~= currentFaction then
		-- Fraktion gewechselt -- Auswahl gehört zum alten Baum, macht hier keinen Sinn mehr.
		selectedTalentId = nil
		detailEmpty.Visible = true
		detailIcon.Visible = false
		detailName.Visible = false
		detailLevel.Visible = false
		detailDescription.Visible = false
		detailStatsHeader.Visible = false
		detailStatPrimary.Visible = false
		detailStatTradeoff.Visible = false
		detailCostHeader.Visible = false
		detailCostEnergy.Visible = false
		detailCostCoins.Visible = false
		detailResearchTime.Visible = false
		detailPrereqLabel.Visible = false
		detailResearchButton.Visible = false
	end
	currentFaction = factionName
	nodeRefs = {}
	-- WICHTIG: erst ALLE zu löschenden Kinder sammeln, DANN erst löschen -- wer während
	-- einer ipairs()-Schleife Kinder zerstört, überspringt dabei manche Elemente (Lua-
	-- Klassiker), wodurch alte Verbindungslinien von früheren Aufrufen liegen bleiben und
	-- sich mit den neuen kreuzen.
	local toDestroy = {}
	for _, child in ipairs(treeScroll:GetChildren()) do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then
			table.insert(toDestroy, child)
		end
	end
	for _, child in ipairs(toDestroy) do
		child:Destroy()
	end

	local nodes = TalentTreeConfig.GetTalentsForFaction(factionName)
	local branchXPositions, branchOrder = getBranchXPositions(nodes)
	local isActiveFaction = (talentState.activeFaction == factionName)

	local positionsById = {}
	local talentsById = {}
	for _, talent in ipairs(nodes) do
		positionsById[talent.id] = getNodePosition(talent, branchXPositions, branchOrder)
		talentsById[talent.id] = talent
	end
	for _, talent in ipairs(nodes) do
		for _, prereq in ipairs(talent.prerequisites) do
			local prereqTalent = talentsById[prereq.id]
			-- Root->Zweig-Linien bewusst NICHT zeichnen -- durch die Spalten-Ausrichtung
			-- (Zweig-Knoten stehen exakt unter dem Start-Knoten) ohnehin klar erkennbar,
			-- und genau diese Linien haben sich am stärksten mit den Synergie-Linien
			-- gekreuzt und die Ansicht unübersichtlich gemacht.
			if positionsById[prereq.id] and prereqTalent and prereqTalent.tier ~= 0 then
				drawConnector(positionsById[prereq.id], positionsById[talent.id])
			end
		end
	end

	for _, talent in ipairs(nodes) do
		buildNode(talent, positionsById[talent.id], isActiveFaction)
	end
end

-- ===== Tabs bauen =====
-- Dieselben Symbolknoepfe wie im Skin-Laden. Drei Figuren, zwei Bildschirme, ein Aussehen.
local tabButtons = {}
for index, tabConfig in ipairs(FACTION_TABS) do
	local tabButton = Instance.new("TextButton")
	tabButton.Name = tabConfig.key .. "Tab"
	tabButton.Size = UDim2.new(0, 44, 0, 44)
	tabButton.LayoutOrder = index
	tabButton.AutoButtonColor = false
	tabButton.Text = ""
	tabButton.ZIndex = 5
	tabButton.Parent = tabRow
	local _, tabStroke = HudChrome.Panel(tabButton, {
		radius = HudChrome.Radius.Small,
		fill = HudChrome.Color.Panel,
	})
	local tabBild = HudChrome.IconImage(tabButton, HudChrome.FactionIcon[tabConfig.key] or "")
	tabBild.Size = UDim2.new(1, -12, 1, -12)
	tabBild.Position = UDim2.new(0, 6, 0, 6)
	tabBild.ZIndex = 6

	tabButtons[tabConfig.key] = { rand = tabStroke, bild = tabBild }

	tabButton.MouseButton1Click:Connect(function()
		renderTree(tabConfig.key)
		for key, eintrag in pairs(tabButtons) do
			local gewaehlt = (key == tabConfig.key)
			eintrag.rand.Color = gewaehlt and HudChrome.Color.BorderBright or HudChrome.Color.Border
			eintrag.rand.Thickness = gewaehlt and 2 or HudChrome.BorderThickness
			eintrag.bild.ImageTransparency = gewaehlt and 0 or 0.45
		end
		schirm.subtitle.Text = string.upper(tabConfig.label)
	end)
end

-- ===== Forschungs-Statusanzeige aktualisieren =====
-- ===== Eigenstaendiges HUD-Feld: zeigt den Forschungs-Fortschritt AUCH wenn das
-- Talent-Fenster geschlossen ist. =====
--
-- Es steht in der linken Spalte, unter der Bahn der Belohnungs-Meldungen (HudToast, oben
-- links bis y 80). Die Forschung ist ein DAUERZUSTAND -- sie laeuft, waehrend man kaempft,
-- und man will nur wissen, wie lange noch. Deshalb dieselbe Anatomie wie die anderen
-- Dauer-Anzeigen: Symbol, Name, Unterzeile, und ein schmaler Balken an der Unterkante.
--
-- Vorher fuellte der Fortschritt das ganze Feld als durchscheinende Flaeche hinter dem
-- Text. Das las sich als "Feld halb markiert", nicht als Fortschritt -- und der Text stand
-- zur Haelfte auf Gelb, zur Haelfte auf Dunkel.
local HUD_BREITE = 260
local HUD_HOEHE = 66
local HUD_RAND = 12
local HUD_SYMBOL = 26

local hudScreenGui = Instance.new("ScreenGui")
hudScreenGui.Name = "ResearchHudGui"
hudScreenGui.ResetOnSpawn = false
hudScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudScreenGui.Parent = playerGui

local hudResearchFrame = Instance.new("Frame")
hudResearchFrame.Name = "ResearchHudFrame"
hudResearchFrame.Size = UDim2.new(0, HUD_BREITE, 0, HUD_HOEHE)
hudResearchFrame.Position = UDim2.new(0, 16, 0, 96)
hudResearchFrame.Visible = false
hudResearchFrame.Parent = hudScreenGui
HudChrome.Panel(hudResearchFrame, { radius = HudChrome.Radius.Small })

local hudResearchIcon = Instance.new("TextLabel")
hudResearchIcon.Name = "ResearchIcon"
hudResearchIcon.Size = UDim2.new(0, HUD_SYMBOL, 0, HUD_SYMBOL)
hudResearchIcon.Position = UDim2.new(0, HUD_RAND, 0, 9)
hudResearchIcon.BackgroundTransparency = 1
hudResearchIcon.TextScaled = true
hudResearchIcon.Text = ""
hudResearchIcon.ZIndex = 2
hudResearchIcon.Parent = hudResearchFrame

local HUD_TEXT_X = HUD_RAND + HUD_SYMBOL + 8

local hudResearchLabel = Instance.new("TextLabel")
hudResearchLabel.Name = "ResearchLabel"
hudResearchLabel.Size = UDim2.new(0, HUD_BREITE - HUD_TEXT_X - HUD_RAND, 0, 22)
hudResearchLabel.Position = UDim2.new(0, HUD_TEXT_X, 0, 7)
hudResearchLabel.BackgroundTransparency = 1
hudResearchLabel.TextXAlignment = Enum.TextXAlignment.Left
hudResearchLabel.TextTruncate = Enum.TextTruncate.AtEnd
hudResearchLabel.Text = ""
hudResearchLabel.ZIndex = 2
hudResearchLabel.Parent = hudResearchFrame
HudChrome.Label(hudResearchLabel, 17)

local hudResearchCountdown = Instance.new("TextLabel")
hudResearchCountdown.Name = "ResearchCountdown"
hudResearchCountdown.Size = UDim2.new(0, HUD_BREITE - HUD_TEXT_X - HUD_RAND, 0, 18)
hudResearchCountdown.Position = UDim2.new(0, HUD_TEXT_X, 0, 29)
hudResearchCountdown.BackgroundTransparency = 1
hudResearchCountdown.TextXAlignment = Enum.TextXAlignment.Left
hudResearchCountdown.Text = ""
hudResearchCountdown.ZIndex = 2
hudResearchCountdown.Parent = hudResearchFrame
HudChrome.Number(hudResearchCountdown, 13)
hudResearchCountdown.TextColor3 = HudChrome.Color.TextSecondary

local hudResearchTrack = Instance.new("Frame")
hudResearchTrack.Name = "ResearchTrack"
hudResearchTrack.Size = UDim2.new(0, HUD_BREITE - HUD_RAND * 2, 0, 6)
hudResearchTrack.Position = UDim2.new(0, HUD_RAND, 0, 52)
hudResearchTrack.BackgroundColor3 = HudChrome.Color.PanelSunken
hudResearchTrack.BorderSizePixel = 0
hudResearchTrack.ZIndex = 2
hudResearchTrack.Parent = hudResearchFrame

local hudResearchTrackCorner = Instance.new("UICorner")
hudResearchTrackCorner.CornerRadius = UDim.new(0, 3)
hudResearchTrackCorner.Parent = hudResearchTrack

local hudResearchFill = Instance.new("Frame")
hudResearchFill.Name = "Fill"
hudResearchFill.Size = UDim2.new(0, 0, 1, 0)
hudResearchFill.BackgroundColor3 = HudChrome.Color.Ready
hudResearchFill.BorderSizePixel = 0
hudResearchFill.ZIndex = 3
hudResearchFill.Parent = hudResearchTrack

local hudResearchFillCorner = Instance.new("UICorner")
hudResearchFillCorner.CornerRadius = UDim.new(0, 3)
hudResearchFillCorner.Parent = hudResearchFill

-- Klick auf das HUD-Widget öffnet direkt das Talent-Fenster (bequemer Rücksprung).
local hudResearchButton = Instance.new("TextButton")
hudResearchButton.Size = UDim2.new(1, 0, 1, 0)
hudResearchButton.BackgroundTransparency = 1
hudResearchButton.Text = ""
hudResearchButton.ZIndex = 4
hudResearchButton.Parent = hudResearchFrame
hudResearchButton.MouseButton1Click:Connect(function()
	panel.Visible = true
end)

local function updateResearchHud()
	if not talentState.research then
		hudResearchFrame.Visible = false
		return
	end
	local talent = TalentTreeConfig.FindTalent(talentState.research.faction, talentState.research.talentId)
	if not talent then
		hudResearchFrame.Visible = false
		return
	end

	hudResearchFrame.Visible = true
	local remaining = talentState.research.completesAt - workspace:GetServerTimeNow()
	hudResearchIcon.Text = talent.icon
	hudResearchLabel.Text = talent.name
	hudResearchCountdown.Text = string.upper(formatDuration(remaining)) .. " LEFT"

	local elapsed = talentState.research.totalDuration - remaining
	local ratio = math.clamp(elapsed / math.max(talentState.research.totalDuration, 0.01), 0, 1)
	hudResearchFill.Size = UDim2.new(ratio, 0, 1, 0)
end

local function updateResearchBar()
	if not talentState.research then
		researchBar.Visible = false
		return
	end
	local talent = TalentTreeConfig.FindTalent(talentState.research.faction, talentState.research.talentId)
	if not talent then
		researchBar.Visible = false
		return
	end
	researchBar.Visible = true
	local remaining = talentState.research.completesAt - workspace:GetServerTimeNow()
	researchLabel.Text = "🔬 Researching: " .. talent.name .. " -- " .. formatDuration(remaining) .. " left"

	local elapsed = talentState.research.totalDuration - remaining
	local ratio = math.clamp(elapsed / math.max(talentState.research.totalDuration, 0.01), 0, 1)
	researchProgressFill.Size = UDim2.new(ratio, 0, 1, 0)
end

-- Pro-Frame-Update (statt einmal pro Sekunde) -- die Fortschrittsbalken füllen sich
-- dadurch flüssig, statt sichtbar in Sekunden-Sprüngen zu springen. Die Textanzeige
-- (MM:SS) ändert sich zwar ohnehin nur einmal pro Sekunde sichtbar, wird aber trotzdem
-- mit aktualisiert -- die eigentlichen Berechnungen hier sind günstig genug dafür.
RunService.Heartbeat:Connect(function()
	if talentState.research then
		updateResearchHud() -- läuft IMMER, auch bei geschlossenem Talent-Fenster
		if panel.Visible then
			updateResearchBar()
		end
	else
		hudResearchFrame.Visible = false
	end
end)

-- ===== Server-Events =====
StartResearchEvent.OnClientEvent:Connect(function(factionName, talentId, completesAt, totalDuration)
	talentState.research = { faction = factionName, talentId = talentId, completesAt = completesAt, totalDuration = totalDuration }
	requestState()
	updateResourceDisplay()
	updateResearchBar()
	updateResearchHud()
	if factionName == currentFaction then
		renderTree(currentFaction)
		refreshSelectedTalentDetails()
	end
end)

ResearchCompleteEvent.OnClientEvent:Connect(function(factionName, talentId, newLevel)
	-- Laempchen am Menuepunkt: eine fertige Forschung ist ein einmaliges Ereignis und
	-- damit ein echter Hinweis -- anders als "genug Energie fuer einen Knoten", das mit
	-- der Energie staendig an- und ausginge.
	if _G.SetNavBadge and not panel.Visible then
		_G.SetNavBadge("Talents", true, talentId)
	end
	if not talentState.levels[factionName] then
		talentState.levels[factionName] = {}
	end
	talentState.levels[factionName][talentId] = newLevel
	talentState.research = nil
	updateResearchBar()
	updateResearchHud()
	if factionName == currentFaction then
		renderTree(currentFaction)
		refreshSelectedTalentDetails()
	end
end)

panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible then
		requestState()
		updateResourceDisplay()
		updateResearchBar()
		renderTree(currentFaction)
	end
end)

requestState()
updateResourceDisplay()
updateResearchHud()
renderTree("Kaiju")

-- Nachzügler-Refresh: der allererste requestState()-Aufruf oben kann theoretisch VOR dem
-- serverseitigen Laden der Spielerdaten passieren (DataStore-Ladezeit ist nicht
-- garantiert synchron mit dem Start dieses LocalScripts) -- dann käme "keine laufende
-- Forschung" zurück, obwohl tatsächlich eine läuft, und das HUD-Widget bliebe bis zum
-- manuellen Öffnen des Talent-Fensters unsichtbar. Dieser zweite Aufruf nach kurzer
-- Verzögerung holt den korrekten Zustand zuverlässig nach.
task.delay(3, function()
	requestState()
	updateResourceDisplay()
	updateResearchHud()
end)