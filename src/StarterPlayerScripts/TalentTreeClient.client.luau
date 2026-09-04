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
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local applyComicStyle = ComicStyleUtils.Apply

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TalentTreeConfig = require(ReplicatedStorage:WaitForChild("TalentTreeConfig"))
local StartResearchEvent = RemoteEventUtils.GetOrCreate("StartResearchEvent")
local CancelResearchEvent = RemoteEventUtils.GetOrCreate("CancelResearchEvent")
local ResearchCompleteEvent = RemoteEventUtils.GetOrCreate("ResearchCompleteEvent")
local GetTalentStateFunction = ReplicatedStorage:WaitForChild("GetTalentStateFunction")

local ENERGY_ICONS = { Heat = "🔥", Chemical = "🧪", Electric = "⚡", Radiation = "☢️", Spirit = "✨" }
local ENERGY_COLORS = {
	Heat = Color3.fromRGB(255, 140, 30),
	Chemical = Color3.fromRGB(255, 45, 190),
	Electric = Color3.fromRGB(57, 217, 255),
	Radiation = Color3.fromRGB(126, 255, 16),
	Spirit = Color3.fromRGB(255, 205, 70),
}

local FACTION_TABS = {
	{ key = "Kaiju", icon = "🦖", label = "Kaiju", color = Color3.fromRGB(90, 170, 100) },
	{ key = "Jaeger", icon = "🤖", label = "Jaeger", color = Color3.fromRGB(90, 130, 220) },
	{ key = "Ronin", icon = "🐯", label = "Ronin", color = Color3.fromRGB(220, 140, 60) },
}

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

local panel = Instance.new("Frame")
panel.Name = "TalentTreePanel"
-- Vollbild: alle Menü-Bildschirme nutzen die ganze Fläche.
-- IgnoreGuiInset am ScreenGui gehört dazu -- ohne das beginnt jedes ScreenGui UNTERHALB
-- der Roblox-Systemleiste, und oben bliebe ein Streifen mit Sicht auf die Welt stehen.
panel.Size = UDim2.new(1, 0, 1, 0)
panel.Position = UDim2.new(0, 0, 0, 0)
panel.AnchorPoint = Vector2.new(0, 0)
panel.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
panel.Visible = false
panel.Parent = screenGui
applyComicStyle(panel, 18, 4)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 300, 0, 32)
titleLabel.Position = UDim2.new(0, 12, 0, 8)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.LuckiestGuy
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Text = "🌟 Talent Tree"
titleLabel.Parent = panel

-- ===== Fraktions-Tabs =====
local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(0, 400, 0, 32)
tabRow.Position = UDim2.new(0, 320, 0, 8)
tabRow.BackgroundTransparency = 1
tabRow.Parent = panel

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabRow

-- ===== Ressourcen-Leiste (5 Energien + Coins) =====
local resourceRow = Instance.new("Frame")
resourceRow.Size = UDim2.new(1, -16, 0, 22)
resourceRow.Position = UDim2.new(0, 8, 0, 44)
resourceRow.BackgroundTransparency = 1
resourceRow.Parent = panel

local resourceLayout = Instance.new("UIListLayout")
resourceLayout.FillDirection = Enum.FillDirection.Horizontal
resourceLayout.Padding = UDim.new(0, 12)
resourceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
resourceLayout.Parent = resourceRow

local resourceLabels = {}
for _, energyType in ipairs(TalentTreeConfig.EnergyOrder) do
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 90, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = ENERGY_COLORS[energyType]
	label.Text = ENERGY_ICONS[energyType] .. " 0"
	label.Parent = resourceRow
	resourceLabels[energyType] = label
end
local coinsLabel = Instance.new("TextLabel")
coinsLabel.Size = UDim2.new(0, 90, 1, 0)
coinsLabel.BackgroundTransparency = 1
coinsLabel.Font = Enum.Font.FredokaOne
coinsLabel.TextScaled = true
coinsLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
coinsLabel.Text = "🪙 0"
coinsLabel.Parent = resourceRow

-- ===== Aktive Forschung: Fortschrittsbalken + Abbrechen-Button =====
local researchBar = Instance.new("Frame")
researchBar.Size = UDim2.new(1, -16, 0, 30)
researchBar.Position = UDim2.new(0, 8, 0, 70)
researchBar.BackgroundColor3 = Color3.fromRGB(40, 36, 55)
researchBar.Visible = false
researchBar.Parent = panel
applyComicStyle(researchBar, 8, 2)

-- Fortschritts-Füllung: wächst von links nach rechts, je näher die Forschung am Ende ist.
local researchProgressFill = Instance.new("Frame")
researchProgressFill.Size = UDim2.new(0, 0, 1, 0)
researchProgressFill.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
researchProgressFill.BackgroundTransparency = 0.6
researchProgressFill.BorderSizePixel = 0
researchProgressFill.ZIndex = 1
researchProgressFill.Parent = researchBar
local researchProgressFillCorner = Instance.new("UICorner")
researchProgressFillCorner.CornerRadius = UDim.new(0, 8)
researchProgressFillCorner.Parent = researchProgressFill

local researchLabel = Instance.new("TextLabel")
researchLabel.Size = UDim2.new(1, -100, 1, 0)
researchLabel.Position = UDim2.new(0, 10, 0, 0)
researchLabel.BackgroundTransparency = 1
researchLabel.Font = Enum.Font.FredokaOne
researchLabel.TextScaled = true
researchLabel.TextXAlignment = Enum.TextXAlignment.Left
researchLabel.TextColor3 = Color3.new(1, 1, 1)
researchLabel.Text = ""
researchLabel.ZIndex = 2
researchLabel.Parent = researchBar

local cancelResearchButton = Instance.new("TextButton")
cancelResearchButton.Size = UDim2.new(0, 80, 0, 22)
cancelResearchButton.AnchorPoint = Vector2.new(1, 0.5)
cancelResearchButton.Position = UDim2.new(1, -8, 0.5, 0)
cancelResearchButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
cancelResearchButton.Font = Enum.Font.FredokaOne
cancelResearchButton.TextScaled = true
cancelResearchButton.TextColor3 = Color3.new(1, 1, 1)
cancelResearchButton.Text = "Cancel"
cancelResearchButton.ZIndex = 2
cancelResearchButton.Parent = researchBar
applyComicStyle(cancelResearchButton, 6, 1)
cancelResearchButton.MouseButton1Click:Connect(function()
	CancelResearchEvent:FireServer()
end)

-- ===== Baum-Bereich (scrollbar, absolute Positionierung nach Tier/Zweig) =====
local treeScroll = Instance.new("ScrollingFrame")
treeScroll.Size = UDim2.new(0, 960, 1, -110)
treeScroll.Position = UDim2.new(0, 8, 0, 106)
treeScroll.BackgroundColor3 = Color3.fromRGB(12, 10, 18)
treeScroll.BorderSizePixel = 0
treeScroll.ScrollBarThickness = 6
treeScroll.CanvasSize = UDim2.new(0, 960, 0, 900)
-- WICHTIG: ScrollingFrame clippt seinen Inhalt NICHT automatisch (anders als man
-- erwarten würde) -- ohne das hier explizit zu setzen, konnten Verbindungslinien über
-- den Fensterrand hinausragen und sogar das restliche HUD überlagern.
treeScroll.ClipsDescendants = true
treeScroll.Parent = panel
applyComicStyle(treeScroll, 12, 2)

-- ===== Detail-Panel: zeigt das AUSGEWÄHLTE Talent -- Icon/Name, Beschreibung, Kosten,
-- Forschungszeit, und einen "Vorher -> Nachher"-Wertevergleich. =====
local detailPanel = Instance.new("Frame")
detailPanel.Size = UDim2.new(0, 268, 1, -110)
detailPanel.Position = UDim2.new(0, 976, 0, 106)
detailPanel.BackgroundColor3 = Color3.fromRGB(28, 25, 40)
detailPanel.Parent = panel
applyComicStyle(detailPanel, 12, 2)

local detailEmpty = Instance.new("TextLabel")
detailEmpty.Size = UDim2.new(1, -20, 0, 80)
detailEmpty.Position = UDim2.new(0, 10, 0, 20)
detailEmpty.BackgroundTransparency = 1
detailEmpty.Font = Enum.Font.FredokaOne
detailEmpty.TextScaled = true
detailEmpty.TextWrapped = true
detailEmpty.TextColor3 = Color3.fromRGB(140, 140, 150)
detailEmpty.Text = "👆 Wähle ein Talent aus, um Details zu sehen."
detailEmpty.Parent = detailPanel

local detailIcon = Instance.new("TextLabel")
detailIcon.Size = UDim2.new(0, 60, 0, 60)
detailIcon.Position = UDim2.new(0, 10, 0, 10)
detailIcon.BackgroundColor3 = Color3.fromRGB(45, 42, 60)
detailIcon.Font = Enum.Font.LuckiestGuy
detailIcon.TextScaled = true
detailIcon.Text = ""
detailIcon.Visible = false
detailIcon.Parent = detailPanel
applyComicStyle(detailIcon, 12, 2)

local detailName = Instance.new("TextLabel")
detailName.Size = UDim2.new(1, -84, 0, 30)
detailName.Position = UDim2.new(0, 78, 0, 10)
detailName.BackgroundTransparency = 1
detailName.Font = Enum.Font.LuckiestGuy
detailName.TextScaled = true
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
detailLevel.Font = Enum.Font.FredokaOne
detailLevel.TextScaled = true
detailLevel.TextXAlignment = Enum.TextXAlignment.Left
detailLevel.TextColor3 = Color3.fromRGB(180, 180, 190)
detailLevel.Text = ""
detailLevel.Visible = false
detailLevel.Parent = detailPanel

local detailDescription = Instance.new("TextLabel")
detailDescription.Size = UDim2.new(1, -20, 0, 90)
detailDescription.Position = UDim2.new(0, 10, 0, 78)
detailDescription.BackgroundTransparency = 1
detailDescription.Font = Enum.Font.FredokaOne
detailDescription.TextScaled = true
detailDescription.TextWrapped = true
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
detailStatsHeader.Font = Enum.Font.LuckiestGuy
detailStatsHeader.TextScaled = true
detailStatsHeader.TextXAlignment = Enum.TextXAlignment.Left
detailStatsHeader.TextColor3 = Color3.fromRGB(255, 210, 80)
detailStatsHeader.Text = "STATS"
detailStatsHeader.Visible = false
detailStatsHeader.Parent = detailPanel

local detailStatPrimary = Instance.new("TextLabel")
detailStatPrimary.Size = UDim2.new(1, -20, 0, 22)
detailStatPrimary.Position = UDim2.new(0, 10, 0, 192)
detailStatPrimary.BackgroundTransparency = 1
detailStatPrimary.Font = Enum.Font.FredokaOne
detailStatPrimary.TextScaled = true
detailStatPrimary.TextXAlignment = Enum.TextXAlignment.Left
detailStatPrimary.TextColor3 = Color3.fromRGB(120, 220, 140)
detailStatPrimary.Text = ""
detailStatPrimary.Visible = false
detailStatPrimary.Parent = detailPanel

local detailStatTradeoff = Instance.new("TextLabel")
detailStatTradeoff.Size = UDim2.new(1, -20, 0, 22)
detailStatTradeoff.Position = UDim2.new(0, 10, 0, 216)
detailStatTradeoff.BackgroundTransparency = 1
detailStatTradeoff.Font = Enum.Font.FredokaOne
detailStatTradeoff.TextScaled = true
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
detailCostHeader.Font = Enum.Font.LuckiestGuy
detailCostHeader.TextScaled = true
detailCostHeader.TextXAlignment = Enum.TextXAlignment.Left
detailCostHeader.TextColor3 = Color3.fromRGB(255, 210, 80)
detailCostHeader.Text = "COST"
detailCostHeader.Visible = false
detailCostHeader.Parent = detailPanel

local detailCostEnergy = Instance.new("TextLabel")
detailCostEnergy.Size = UDim2.new(1, -20, 0, 24)
detailCostEnergy.Position = UDim2.new(0, 10, 0, 270)
detailCostEnergy.BackgroundTransparency = 1
detailCostEnergy.Font = Enum.Font.FredokaOne
detailCostEnergy.TextScaled = true
detailCostEnergy.TextXAlignment = Enum.TextXAlignment.Left
detailCostEnergy.TextColor3 = Color3.new(1, 1, 1)
detailCostEnergy.Text = ""
detailCostEnergy.Visible = false
detailCostEnergy.Parent = detailPanel

local detailCostCoins = Instance.new("TextLabel")
detailCostCoins.Size = UDim2.new(1, -20, 0, 24)
detailCostCoins.Position = UDim2.new(0, 10, 0, 296)
detailCostCoins.BackgroundTransparency = 1
detailCostCoins.Font = Enum.Font.FredokaOne
detailCostCoins.TextScaled = true
detailCostCoins.TextXAlignment = Enum.TextXAlignment.Left
detailCostCoins.TextColor3 = Color3.fromRGB(255, 220, 80)
detailCostCoins.Text = ""
detailCostCoins.Visible = false
detailCostCoins.Parent = detailPanel

local detailResearchTime = Instance.new("TextLabel")
detailResearchTime.Size = UDim2.new(1, -20, 0, 24)
detailResearchTime.Position = UDim2.new(0, 10, 0, 322)
detailResearchTime.BackgroundTransparency = 1
detailResearchTime.Font = Enum.Font.FredokaOne
detailResearchTime.TextScaled = true
detailResearchTime.TextXAlignment = Enum.TextXAlignment.Left
detailResearchTime.TextColor3 = Color3.fromRGB(180, 180, 220)
detailResearchTime.Text = ""
detailResearchTime.Visible = false
detailResearchTime.Parent = detailPanel

local detailPrereqLabel = Instance.new("TextLabel")
detailPrereqLabel.Size = UDim2.new(1, -20, 0, 40)
detailPrereqLabel.Position = UDim2.new(0, 10, 0, 352)
detailPrereqLabel.BackgroundTransparency = 1
detailPrereqLabel.Font = Enum.Font.FredokaOne
detailPrereqLabel.TextScaled = true
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
detailResearchButton.Font = Enum.Font.LuckiestGuy
detailResearchButton.TextScaled = true
detailResearchButton.TextColor3 = Color3.new(1, 1, 1)
detailResearchButton.Text = "🔬 RESEARCH"
detailResearchButton.Visible = false
detailResearchButton.Parent = detailPanel
applyComicStyle(detailResearchButton, 10, 2)

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -8, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
closeButton.Font = Enum.Font.FredokaOne
closeButton.TextScaled = true
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "X"
closeButton.Parent = panel
applyComicStyle(closeButton, 8, 2)
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
		resourceLabels[energyType].Text = ENERGY_ICONS[energyType] .. " " .. math.floor(talentState.energy[energyType] or 0)
	end
	coinsLabel.Text = "🪙 " .. math.floor(talentState.coins or 0)
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

	detailIcon.Text = talent.icon
	detailIcon.BackgroundColor3 = ENERGY_COLORS[talent.energyType] or Color3.fromRGB(45, 42, 60)
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
		detailCostEnergy.Text = ENERGY_ICONS[talent.energyType] .. " " .. cost.energyAmount
		if cost.coinAmount > 0 then
			detailCostCoins.Visible = true
			detailCostCoins.Text = "🪙 " .. cost.coinAmount
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
	local nodeCorner, nodeStroke = applyComicStyle(button, 44, 3)
	if talent.isTradeoff then
		nodeStroke.Color = Color3.fromRGB(230, 140, 40)
	elseif ENERGY_COLORS[talent.energyType] then
		nodeStroke.Color = ENERGY_COLORS[talent.energyType]
	end

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 0, 38)
	iconLabel.Position = UDim2.new(0, 0, 0, 4)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.LuckiestGuy
	iconLabel.TextScaled = true
	iconLabel.Text = talent.icon
	iconLabel.ZIndex = 63
	iconLabel.Parent = button

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.new(1, 0, 0, 16)
	levelLabel.Position = UDim2.new(0, 0, 0, 66)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font = Enum.Font.FredokaOne
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
	infoLabel.Font = Enum.Font.FredokaOne
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
	newFlag.Font = Enum.Font.FredokaOne
	newFlag.TextScaled = true
	newFlag.TextColor3 = Color3.fromRGB(255, 255, 255)
	newFlag.Text = "NEW"
	newFlag.ZIndex = 64
	newFlag.Visible = (_G.GetNavBadgeItems and _G.GetNavBadgeItems("Talents")[talent.id]) == true
	newFlag.Parent = button
	applyComicStyle(newFlag, 6, 2)

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
for _, tabConfig in ipairs(FACTION_TABS) do
	local tabButton = Instance.new("TextButton")
	tabButton.Size = UDim2.new(0, 126, 1, 0)
	tabButton.BackgroundColor3 = tabConfig.color
	tabButton.Font = Enum.Font.LuckiestGuy
	tabButton.TextScaled = true
	tabButton.TextColor3 = Color3.new(1, 1, 1)
	tabButton.Text = tabConfig.icon .. " " .. tabConfig.label
	tabButton.Parent = tabRow
	applyComicStyle(tabButton, 8, 2)

	tabButton.MouseButton1Click:Connect(function()
		renderTree(tabConfig.key)
	end)
end

-- ===== Forschungs-Statusanzeige aktualisieren =====
-- ===== Eigenständiges HUD-Widget: zeigt den Forschungs-Fortschritt AUCH wenn das
-- Talent-Fenster geschlossen ist (unten links, unter den restlichen linken HUD-
-- Elementen). =====
local hudScreenGui = Instance.new("ScreenGui")
hudScreenGui.Name = "ResearchHudGui"
hudScreenGui.ResetOnSpawn = false
hudScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudScreenGui.Parent = playerGui

local hudResearchFrame = Instance.new("Frame")
hudResearchFrame.Name = "ResearchHudFrame"
hudResearchFrame.Size = UDim2.new(0, 230, 0, 50)
hudResearchFrame.Position = UDim2.new(0, 12, 0, 160)
hudResearchFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
hudResearchFrame.Visible = false
hudResearchFrame.Parent = hudScreenGui
applyComicStyle(hudResearchFrame, 10, 2)

local hudResearchFill = Instance.new("Frame")
hudResearchFill.Size = UDim2.new(0, 0, 1, 0)
hudResearchFill.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
hudResearchFill.BackgroundTransparency = 0.65
hudResearchFill.BorderSizePixel = 0
hudResearchFill.Parent = hudResearchFrame
local hudResearchFillCorner = Instance.new("UICorner")
hudResearchFillCorner.CornerRadius = UDim.new(0, 10)
hudResearchFillCorner.Parent = hudResearchFill

local hudResearchLabel = Instance.new("TextLabel")
hudResearchLabel.Size = UDim2.new(1, -12, 0, 20)
hudResearchLabel.Position = UDim2.new(0, 6, 0, 4)
hudResearchLabel.BackgroundTransparency = 1
hudResearchLabel.Font = Enum.Font.FredokaOne
hudResearchLabel.TextScaled = true
hudResearchLabel.TextXAlignment = Enum.TextXAlignment.Left
hudResearchLabel.TextColor3 = Color3.new(1, 1, 1)
hudResearchLabel.Text = "🔬 Researching..."
hudResearchLabel.ZIndex = 2
hudResearchLabel.Parent = hudResearchFrame

local hudResearchCountdown = Instance.new("TextLabel")
hudResearchCountdown.Size = UDim2.new(1, -12, 0, 20)
hudResearchCountdown.Position = UDim2.new(0, 6, 0, 24)
hudResearchCountdown.BackgroundTransparency = 1
hudResearchCountdown.Font = Enum.Font.FredokaOne
hudResearchCountdown.TextScaled = true
hudResearchCountdown.TextXAlignment = Enum.TextXAlignment.Left
hudResearchCountdown.TextColor3 = Color3.fromRGB(220, 200, 140)
hudResearchCountdown.Text = ""
hudResearchCountdown.ZIndex = 2
hudResearchCountdown.Parent = hudResearchFrame

-- Klick auf das HUD-Widget öffnet direkt das Talent-Fenster (bequemer Rücksprung).
local hudResearchButton = Instance.new("TextButton")
hudResearchButton.Size = UDim2.new(1, 0, 1, 0)
hudResearchButton.BackgroundTransparency = 1
hudResearchButton.Text = ""
hudResearchButton.ZIndex = 3
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
	hudResearchLabel.Text = talent.icon .. " " .. talent.name
	hudResearchCountdown.Text = formatDuration(remaining) .. " left"

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
	if _G.SetNavBadge and not talentTreePanel.Visible then
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