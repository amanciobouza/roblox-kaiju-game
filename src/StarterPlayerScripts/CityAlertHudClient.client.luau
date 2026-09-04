-- VERSION: 2026-08-25 #1
-- FIX: Megacity -> MegaCity (Schreibweise an Studio-Attribut angeglichen)
-- VERSION: 2026-08-18 #9
-- LocalScript: CityAlertHudClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt oben rechts den Namen der Stadt, in der sich der Spieler gerade befindet, plus
-- den Alert-Level als Sterne-Anzeige darunter (Level 1 = kein Stern, Level 2 = 1 Stern,
-- künftige Level 3+ = entsprechend mehr Sterne). Attribut "CurrentCityName" wird
-- serverseitig von CityAlertService.lua gepflegt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local cityAlertValues = ReplicatedStorage:WaitForChild("CityAlertValues", 10)
local cityAlertConfigModule = ReplicatedStorage:WaitForChild("CityAlertConfig", 10)
if not cityAlertValues or not cityAlertConfigModule then
	warn("[CityAlertHudClient] CityAlertValues oder CityAlertConfig nicht gefunden (Timeout) -- Alert-HUD bleibt deaktiviert.")
	return
end
local CityAlertConfig = require(cityAlertConfigModule)

local CITY_DISPLAY_NAMES = {
	Village = "Village",
	SmallTown = "Small Town",
	City = "City",
	LargeCity = "Large City",
	MegaCity = "Megacity",
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CityAlertHudGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local alertFrame = Instance.new("Frame")
alertFrame.Name = "CityAlertFrame"
alertFrame.Size = UDim2.new(0, 200, 0, 92)
alertFrame.AnchorPoint = Vector2.new(1, 0)
alertFrame.Position = UDim2.new(1, -20, 0, 66) -- unter der Coins/Home-Reihe (neue HUD-Spezifikation, Top Right)
alertFrame.BackgroundTransparency = 1 -- kein Hintergrund/Rahmen mehr -- nur der Text/die Bar selbst ist sichtbar
alertFrame.Visible = false
alertFrame.ZIndex = 20
alertFrame.Parent = screenGui

-- Fortschritts-Balken zur NÄCHSTEN Alert-Stufe (0-100%) -- der Server berechnet den
-- zugrundeliegenden Wert (cityProgressValues) bereits, wurde bisher aber nirgends
-- angezeigt.
local progressBackground = Instance.new("Frame")
progressBackground.Name = "ProgressBackground"
progressBackground.Size = UDim2.new(1, -12, 0, 16)
progressBackground.Position = UDim2.new(0, 6, 0, 0)
progressBackground.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
progressBackground.BorderSizePixel = 0
progressBackground.Parent = alertFrame

local progressCorner = Instance.new("UICorner")
progressCorner.CornerRadius = UDim.new(1, 0)
progressCorner.Parent = progressBackground

local progressFill = Instance.new("Frame")
progressFill.Name = "Fill"
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = Color3.fromRGB(90, 220, 130)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressBackground

local progressFillCorner = Instance.new("UICorner")
progressFillCorner.CornerRadius = UDim.new(1, 0)
progressFillCorner.Parent = progressFill

local cityNameLabel = Instance.new("TextLabel")
cityNameLabel.Name = "CityNameLabel"
cityNameLabel.Size = UDim2.new(1, -12, 0, 30)
cityNameLabel.Position = UDim2.new(0, 6, 0, 22)
cityNameLabel.BackgroundTransparency = 1
cityNameLabel.Font = Enum.Font.LuckiestGuy
cityNameLabel.TextScaled = true
cityNameLabel.TextColor3 = Color3.new(1, 1, 1)
cityNameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
cityNameLabel.TextStrokeTransparency = 0.4
cityNameLabel.Text = ""
cityNameLabel.Parent = alertFrame

-- ===== Einzelne, animierbare Sterne statt einem Text-String -- jeder Stern ist ein
-- eigenes Label, das sich beim Erscheinen dreht, abbremst und mit einem Leuchteffekt
-- stehen bleibt. Bei mehreren neuen Sternen laufen die Animationen NACHEINANDER.
local MAX_STARS = 5 -- genug Puffer für künftige Alert-Level

local starsContainer = Instance.new("Frame")
starsContainer.Name = "StarsContainer"
starsContainer.Size = UDim2.new(1, -12, 0, 26)
starsContainer.Position = UDim2.new(0, 6, 0, 52)
starsContainer.BackgroundTransparency = 1
starsContainer.Parent = alertFrame

local starsLayout = Instance.new("UIListLayout")
starsLayout.FillDirection = Enum.FillDirection.Horizontal
starsLayout.Padding = UDim.new(0, 2)
starsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
starsLayout.Parent = starsContainer

local INACTIVE_STAR_COLOR = Color3.fromRGB(90, 88, 82) -- gedimmt, für "erreichbar, aber noch nicht aktiv"
local ACTIVE_STAR_COLOR = Color3.fromRGB(255, 210, 80)

local starLabels = {}
for i = 1, MAX_STARS do
	local star = Instance.new("TextLabel")
	star.Name = "Star" .. i
	star.Size = UDim2.new(0, 22, 1, 0)
	star.BackgroundTransparency = 1
	star.Font = Enum.Font.FredokaOne
	star.TextScaled = true
	star.TextColor3 = ACTIVE_STAR_COLOR
	star.TextStrokeColor3 = Color3.new(0, 0, 0)
	star.TextStrokeTransparency = 0.4
	star.Text = "★"
	star.Visible = false
	star.LayoutOrder = i
	star.Parent = starsContainer
	starLabels[i] = star
end

-- Lässt EINEN Stern einfliegen: dreht sich schnell, bremst ab, blitzt kurz golden auf.
local function animateStarIn(star)
	star.Visible = true
	star.Rotation = 0
	star.TextColor3 = ACTIVE_STAR_COLOR

	local spinTween = TweenService:Create(
		star,
		TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Rotation = 720 } -- zwei volle Umdrehungen, die sich sichtbar abbremsen
	)
	spinTween:Play()
	spinTween.Completed:Connect(function()
		star.Rotation = 0
		-- Leuchteffekt: kurz auf reines Weiss aufblitzen, dann zurück zu Gold.
		local flashTween = TweenService:Create(star, TweenInfo.new(0.12), { TextColor3 = Color3.new(1, 1, 1) })
		flashTween:Play()
		flashTween.Completed:Connect(function()
			TweenService:Create(star, TweenInfo.new(0.3), { TextColor3 = ACTIVE_STAR_COLOR }):Play()
		end)
	end)
end

-- Animiert mehrere neu hinzugekommene Sterne NACHEINANDER (nicht gleichzeitig).
local function animateNewStars(fromCount, toCount)
	task.spawn(function()
		for i = fromCount + 1, toCount do
			local star = starLabels[i]
			if star then
				animateStarIn(star)
				task.wait(0.25) -- kurzer Versatz, bevor der nächste Stern startet
			end
		end
	end)
end

local currentStarCount = 0
local lastShownCityName = nil
local lastShownMaxLevel = nil

local lastShownLevel = nil

local function updateAlertHud()
	-- Sanctuary-Sonderfall: zeigt "Sanctuary" als Ortsname an (konsistent mit den echten
	-- Städtenamen), statt die ganze Anzeige einfach auszublenden. Sterne/Fortschrittsbalken
	-- bleiben versteckt, da dort ohnehin kein Alert-System greift.
	if player:GetAttribute("CurrentZone") == "Sanctuary" then
		alertFrame.Visible = true
		cityNameLabel.Text = "Sanctuary"
		for _, star in ipairs(starLabels) do
			star.Visible = false
		end
		currentStarCount = 0
		lastShownCityName = nil
		lastShownMaxLevel = nil
		progressBackground.Visible = false
		lastShownLevel = nil
		return
	end
	progressBackground.Visible = true

	local cityName = player:GetAttribute("CurrentCityName")
	if not cityName or cityName == "None" or cityName == "" then
		alertFrame.Visible = false
		lastShownLevel = nil
		return
	end

	local levelValue = cityAlertValues:FindFirstChild(cityName .. "Level")
	if not levelValue then
		alertFrame.Visible = false
		return
	end

	local level = levelValue.Value
	local starCount = math.max(level, 0) -- Level 0 = 0 Sterne, Level 1 = 1 Stern, Level 2 = 2 Sterne, usw. -- entspricht direkt der Levelzahl

	local config = CityAlertConfig.GetCityConfig(cityName)
	-- Die Hoechststufe kommt VOM SERVER, nicht mehr aus dem Config: sie haengt am hoechsten
	-- Kapitel der Anwesenden (siehe CityAlertService, MaxAlertLevelByChapter), und im
	-- Config steht nur der Kapitel-I-Grundwert. Der Rueckfall auf das Config greift, solange
	-- der Wert noch nicht repliziert ist.
	local maxLevelValue = cityAlertValues and cityAlertValues:FindFirstChild(cityName .. "MaxLevel")
	local rawMaxLevel = (maxLevelValue and maxLevelValue.Value) or (config and config.MaxAlertLevel) or MAX_STARS
	local maxLevel = math.clamp(rawMaxLevel, 0, MAX_STARS)

	cityNameLabel.Text = CITY_DISPLAY_NAMES[cityName] or cityName

	-- Beim Städtewechsel (unterschiedliches MaxAlertLevel) die gedimmten "Deckel"-Sterne
	-- neu aufbauen: 1..maxLevel sichtbar (gedimmt, falls noch nicht aktiv), Rest
	-- ausgeblendet -- zeigt sofort, wie viele Stufen diese Stadt überhaupt kennt.
	-- Neu aufbauen beim Staedtewechsel UND wenn sich die Obergrenze derselben Stadt
	-- aendert -- letzteres passiert, sobald ein Spieler eines hoeheren Kapitels die Stadt
	-- betritt oder verlaesst. Ohne die zweite Bedingung blieben die gedimmten Sterne auf
	-- dem Stand des Kapitels, in dem man die Stadt betreten hat.
	if cityName ~= lastShownCityName or maxLevel ~= lastShownMaxLevel then
		lastShownCityName = cityName
		lastShownMaxLevel = maxLevel
		for i = 1, MAX_STARS do
			local star = starLabels[i]
			if i <= maxLevel then
				star.Visible = true
				star.Rotation = 0
				star.TextColor3 = i <= starCount and ACTIVE_STAR_COLOR or INACTIVE_STAR_COLOR
			else
				star.Visible = false
			end
		end
		currentStarCount = starCount
	end

	-- Sterne: neue animiert nacheinander einfliegen lassen, bei De-Eskalation überzählige
	-- auf gedimmt zurücksetzen (nicht mehr ausblenden, solange sie <= maxLevel sind --
	-- sie bleiben als "erreichbar, aber gerade nicht aktiv" sichtbar).
	if starCount > currentStarCount then
		animateNewStars(currentStarCount, starCount)
	elseif starCount < currentStarCount then
		for i = starCount + 1, currentStarCount do
			if starLabels[i] then
				if i <= maxLevel then
					starLabels[i].TextColor3 = INACTIVE_STAR_COLOR
				else
					starLabels[i].Visible = false
				end
			end
		end
	end
	currentStarCount = starCount

	-- Fortschritts-Balken: rohen Punktwert gegen die Schwelle DIESER Stadt normieren.
	local progressValue = cityAlertValues:FindFirstChild(cityName .. "Progress")
	local config = CityAlertConfig.GetCityConfig(cityName)
	if progressValue and config and config.AlertThresholdLevel2 and config.AlertThresholdLevel2 > 0 then
		local ratio = math.clamp(progressValue.Value / config.AlertThresholdLevel2, 0, 1)
		progressFill.Size = UDim2.new(ratio, 0, 1, 0)
	end

	alertFrame.Visible = true

	-- Kurzes Aufleuchten bei einem ECHTEN Level-Wechsel (nicht bei jedem Check).
	if lastShownLevel and lastShownLevel ~= level then
		local original = alertFrame.Size
		alertFrame.Size = UDim2.new(0, original.X.Offset * 1.12, 0, original.Y.Offset * 1.12)
		TweenService:Create(alertFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = original,
		}):Play()
	end
	lastShownLevel = level
end

player:GetAttributeChangedSignal("CurrentCityName"):Connect(updateAlertHud)
player:GetAttributeChangedSignal("CurrentZone"):Connect(updateAlertHud)

-- Auf Änderungen JEDES Stadt-Level-Werts UND JEDES Stadt-Progress-Werts reagieren --
-- Level-Wechsel sind selten (Sterne), Progress-Änderungen häufig (Balken).
--
-- Das Muster "Level$" erfasst auch "<Stadt>MaxLevel" (die kapitelabhängige Obergrenze).
-- Das ist beabsichtigt und nötig: ohne dieses Abonnement bliebe die Sterne-Anzeige
-- stehen, wenn ein Spieler eines höheren Kapitels die Stadt betritt. Wer das Muster
-- ändert, muss den Wert ausdrücklich mit aufnehmen.
for _, valueObject in ipairs(cityAlertValues:GetChildren()) do
	if valueObject.Name:match("Level$") or valueObject.Name:match("Progress$") then
		valueObject:GetPropertyChangedSignal("Value"):Connect(updateAlertHud)
	end
end

updateAlertHud() -- initialer Zustand beim Start

-- ===== Quest-Liste: zeigt pro Stadt die anwendbaren Aufgaben (Emergency/Defense/
-- Military/Titan Protocol) mit Häkchen, sobald besiegt. Sobald alle erledigt sind (siehe
-- CityBrokenService.lua), startet CITY BROKEN -- eigener Banner mit Countdown. =====
local TASK_LIST = {
	{ id = "Emergency", icon = "🚒", label = "Emergency Response eliminated" },
	{ id = "Defense", icon = "🛡️", label = "Defense Barricades eliminated" },
	{ id = "Military", icon = "🎖️", label = "Military eliminated" },
	{ id = "Titan", icon = "🤖", label = "Guardian eliminated" },
}

local questFrame = Instance.new("Frame")
questFrame.Name = "CityQuestFrame"
questFrame.AnchorPoint = Vector2.new(1, 0)
questFrame.Position = UDim2.new(1, -20, 0, 164) -- direkt unter alertFrame (92px hoch, startet bei y=66)
questFrame.Size = UDim2.new(0, 220, 0, 0)
questFrame.AutomaticSize = Enum.AutomaticSize.Y
questFrame.BackgroundTransparency = 1
questFrame.Visible = false
questFrame.ZIndex = 20
questFrame.Parent = screenGui

local questListLayout = Instance.new("UIListLayout")
questListLayout.Padding = UDim.new(0, 3)
questListLayout.SortOrder = Enum.SortOrder.LayoutOrder
questListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
questListLayout.Parent = questFrame

local questRows = {} -- [taskId] = { row=, checkLabel=, textLabel= }
for index, task in ipairs(TASK_LIST) do
	local row = Instance.new("Frame")
	row.Name = task.id .. "Row"
	row.Size = UDim2.new(0, 220, 0, 20)
	row.BackgroundTransparency = 1
	row.LayoutOrder = index
	row.Parent = questFrame

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, -26, 1, 0)
	textLabel.Position = UDim2.new(0, 0, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Right
	textLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
	textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	textLabel.TextStrokeTransparency = 0.4
	textLabel.Text = task.icon .. " " .. task.label
	textLabel.Parent = row

	local checkLabel = Instance.new("TextLabel")
	checkLabel.Size = UDim2.new(0, 22, 1, 0)
	checkLabel.Position = UDim2.new(1, -22, 0, 0)
	checkLabel.BackgroundTransparency = 1
	checkLabel.Font = Enum.Font.FredokaOne
	checkLabel.TextScaled = true
	checkLabel.TextColor3 = Color3.fromRGB(90, 220, 90)
	checkLabel.Text = ""
	checkLabel.Parent = row

	questRows[task.id] = { row = row, checkLabel = checkLabel, textLabel = textLabel }
end

local cityBrokenBanner = Instance.new("Frame")
cityBrokenBanner.Name = "CityBrokenBanner"
cityBrokenBanner.AnchorPoint = Vector2.new(1, 0)
cityBrokenBanner.Position = UDim2.new(1, -20, 0, 164)
cityBrokenBanner.Size = UDim2.new(0, 220, 0, 46)
cityBrokenBanner.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
cityBrokenBanner.Visible = false
cityBrokenBanner.ZIndex = 21
cityBrokenBanner.Parent = screenGui

local cityBrokenCorner = Instance.new("UICorner")
cityBrokenCorner.CornerRadius = UDim.new(0, 10)
cityBrokenCorner.Parent = cityBrokenBanner

local cityBrokenTitle = Instance.new("TextLabel")
cityBrokenTitle.Size = UDim2.new(1, -8, 0, 22)
cityBrokenTitle.Position = UDim2.new(0, 4, 0, 2)
cityBrokenTitle.BackgroundTransparency = 1
cityBrokenTitle.Font = Enum.Font.LuckiestGuy
cityBrokenTitle.TextScaled = true
cityBrokenTitle.TextColor3 = Color3.fromRGB(255, 210, 80)
cityBrokenTitle.TextStrokeColor3 = Color3.new(0, 0, 0)
cityBrokenTitle.TextStrokeTransparency = 0
cityBrokenTitle.ZIndex = 22
cityBrokenTitle.Text = "💀 CITY BROKEN"
cityBrokenTitle.Parent = cityBrokenBanner

local cityBrokenSubtitle = Instance.new("TextLabel")
cityBrokenSubtitle.Size = UDim2.new(1, -8, 0, 18)
cityBrokenSubtitle.Position = UDim2.new(0, 4, 0, 24)
cityBrokenSubtitle.BackgroundTransparency = 1
cityBrokenSubtitle.Font = Enum.Font.FredokaOne
cityBrokenSubtitle.TextScaled = true
cityBrokenSubtitle.TextColor3 = Color3.new(1, 1, 1)
cityBrokenSubtitle.TextStrokeColor3 = Color3.new(0, 0, 0)
cityBrokenSubtitle.TextStrokeTransparency = 0.3
cityBrokenSubtitle.ZIndex = 22
cityBrokenSubtitle.Text = "🔥 FREE DESTRUCTION -- 75s"
cityBrokenSubtitle.Parent = cityBrokenBanner

local function updateQuestList()
	local cityName = player:GetAttribute("CurrentCityName")
	local zone = player:GetAttribute("CurrentZone")
	if not cityName or cityName == "None" or zone == "Sanctuary" then
		questFrame.Visible = false
		cityBrokenBanner.Visible = false
		return
	end

	local brokenValue = cityAlertValues:FindFirstChild(cityName .. "CityBroken")
	local isBroken = brokenValue and brokenValue.Value

	if isBroken then
		questFrame.Visible = false
		cityBrokenBanner.Visible = true
		local endsAtValue = cityAlertValues:FindFirstChild(cityName .. "CityBrokenEndsAt")
		local remaining = endsAtValue and math.max(math.floor(endsAtValue.Value - os.clock()), 0) or 0
		cityBrokenSubtitle.Text = "🔥 FREE DESTRUCTION -- " .. remaining .. "s"
		return
	end

	cityBrokenBanner.Visible = false

	-- Nur Aufgaben zeigen, die diese Stadt bereits TATSÄCHLICH erreicht hat -- "applicable"
	-- bedeutet jetzt schon genau das (serverseitig dynamisch berechnet, siehe
	-- CityBrokenService.lua), keine zusätzliche Level-Prüfung hier mehr nötig.
	local anyTaskVisible = false

	for _, task in ipairs(TASK_LIST) do
		local applicableValue = cityAlertValues:FindFirstChild(cityName .. "Task_" .. task.id .. "_Applicable")
		local isApplicable = applicableValue and applicableValue.Value
		local rowInfo = questRows[task.id]

		if isApplicable then
			anyTaskVisible = true
			rowInfo.row.Visible = true
			local completeValue = cityAlertValues:FindFirstChild(cityName .. "Task_" .. task.id .. "_Complete")
			local isComplete = completeValue and completeValue.Value
			rowInfo.checkLabel.Text = isComplete and "✅" or "⬜"
			rowInfo.textLabel.TextColor3 = isComplete and Color3.fromRGB(120, 230, 120) or Color3.fromRGB(210, 210, 210)

			-- Fortschritts-Anzeige ("1/2") anhängen, sofern der Server einen liefert
			-- (Guardian-Aufgabe hat keinen -- einzelner Boss).
			local progressValue = cityAlertValues:FindFirstChild(cityName .. "Task_" .. task.id .. "_Progress")
			local progressText = progressValue and progressValue.Value or ""
			if progressText ~= "" then
				rowInfo.textLabel.Text = task.icon .. " " .. task.label .. " (" .. progressText .. ")"
			else
				rowInfo.textLabel.Text = task.icon .. " " .. task.label
			end
		else
			rowInfo.row.Visible = false
		end
	end

	questFrame.Visible = anyTaskVisible
end

RunService.Heartbeat:Connect(updateQuestList)

for _, valueObject in ipairs(cityAlertValues:GetChildren()) do
	if valueObject.Name:match("Task_") or valueObject.Name:match("CityBroken$") then
		valueObject:GetPropertyChangedSignal("Value"):Connect(updateQuestList)
	end
end
updateQuestList()

-- Wird von CityAlertAnnouncementClient.lua aufgerufen, sobald die grosse zentrale
-- Ankündigung in die Ecke geflogen ist -- zusätzlicher Glow-Effekt, um den Blick genau
-- hierhin zu lenken.
_G.FlashCityAlertIndicator = function(color)
	local glow = Instance.new("UIStroke")
	glow.Color = color or Color3.fromRGB(255, 230, 120)
	glow.Thickness = 4
	glow.Transparency = 0
	glow.Parent = alertFrame

	TweenService:Create(glow, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
		Transparency = 1,
	}):Play()
	task.delay(0.6, function()
		glow:Destroy()
	end)
end

-- Lässt die kompakte Anzeige kurz zittern -- Trigger-Moment (0.0s) der "ALERT
-- ESCALATION"-Sequenz in CityAlertAnnouncementClient.lua.
_G.ShakeCityAlertIndicator = function()
	local originalPosition = alertFrame.Position
	task.spawn(function()
		for _ = 1, 6 do
			local offset = Vector2.new(math.random(-3, 3), math.random(-3, 3))
			alertFrame.Position = UDim2.new(
				originalPosition.X.Scale, originalPosition.X.Offset + offset.X,
				originalPosition.Y.Scale, originalPosition.Y.Offset + offset.Y
			)
			task.wait(0.02)
		end
		alertFrame.Position = originalPosition
	end)
end

-- Lässt einen bestimmten Stern (1-basiert) kurz 2x pulsieren -- Trigger-Moment (0.0s) der
-- "ALERT ESCALATION"-Sequenz.
_G.PulseCityAlertStar = function(starIndex)
	local star = starLabels[starIndex]
	if not star or not star.Visible then
		return
	end
	task.spawn(function()
		for _ = 1, 2 do
			local pulseUp = TweenService:Create(star, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
				Size = UDim2.new(0, 26, 1, 0),
			})
			pulseUp:Play()
			pulseUp.Completed:Wait()
			local pulseDown = TweenService:Create(star, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
				Size = UDim2.new(0, 22, 1, 0),
			})
			pulseDown:Play()
			pulseDown.Completed:Wait()
		end
	end)
end