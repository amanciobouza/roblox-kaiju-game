-- VERSION: 2026-08-26 #14
-- FEATURE: Debug-Panel schliesst + DebugMode deaktiviert sich bei Prolog-Start
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zentraler Debug-Modus-Schalter + alle Debug-Werkzeuge in EINEM Fenster:
-- Ein kleiner Auslöse-Button sitzt mittig rechts am Bildschirmrand. Klick darauf öffnet
-- ein zentrales Fenster (Debug-Modus-Umschalter, Level-Regler, Stadt-Alert-Regler,
-- Welt-Event-Würfel, Spielerdaten-Reset) mit einem Schliessen-Button. Andere Debug-
-- Scripts (z.B. RadiusDebugClient.lua) hören weiterhin einfach auf Änderungen des
-- "DebugMode"-Attributs.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local applyComicStyle = ComicStyleUtils.Apply

local player = Players.LocalPlayer
-- WICHTIG: CityAlertConfig NICHT mehr hier blockierend laden -- das hat bisher ALLES
-- Weitere im Script um bis zu 10 Sekunden verzögert, inklusive der Taste V selbst (das
-- Fenster wirkte dadurch komplett "verschwunden", bis der Timeout durch war). Wird jetzt
-- weiter unten asynchron nachgeladen, nachdem die Kernfunktionalität (Taste V, Panel)
-- bereits steht.
local CityAlertConfig = nil
local TOGGLE_KEY = Enum.KeyCode.V
local MAX_DEBUG_LEVEL = 50

-- WICHTIG: WaitForChild MIT Timeout statt ohne -- fehlt ein RemoteEvent serverseitig aus
-- irgendeinem Grund, würde ein Aufruf OHNE Timeout das gesamte Script an dieser Stelle
-- für immer blockieren, BEVOR auch nur ein einziges UI-Element gebaut wird (genau das
-- ist zuvor passiert: ein leeres Panel ohne jeden Inhalt). Mit Timeout + Warnung baut
-- das Fenster wenigstens die restlichen, funktionierenden Werkzeuge zuverlässig.
local function waitForRemote(name)
	local remote = ReplicatedStorage:WaitForChild(name, 5)
	if not remote then
		warn("[DebugPanelClient] RemoteEvent '" .. name .. "' wurde nicht gefunden (Timeout) -- das zugehörige Debug-Werkzeug bleibt wirkungslos.")
	end
	return remote
end

local DebugSetLevelEvent = waitForRemote("DebugSetLevelEvent")
local DebugRollWorldEventEvent = waitForRemote("DebugRollWorldEventEvent")
local SetDebugModeEvent = waitForRemote("SetDebugModeEvent")
local ResetPlayerDataEvent = waitForRemote("ResetPlayerDataEvent")
local DebugSetFactionEvent = waitForRemote("DebugSetFactionEvent")
local DebugSetCityAlertEvent = waitForRemote("DebugSetCityAlertEvent")
local DebugToggleSkipCollapseEvent = waitForRemote("DebugToggleSkipCollapseEvent")
local DebugStartPrologueEvent = waitForRemote("DebugStartPrologueEvent")
local DebugRunSpecCheckEvent = waitForRemote("DebugRunSpecCheckEvent")
local DebugStartPrologueResultEvent = waitForRemote("DebugStartPrologueResultEvent")

player:SetAttribute("DebugMode", false)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DebugPanelGui"
screenGui.ResetOnSpawn = false
-- WICHTIG: "Sibling" (Standard, aber explizit gesetzt zur Sicherheit) sorgt dafür, dass
-- ZIndex nur zwischen direkten Geschwister-Elementen verglichen wird -- bei "Global"
-- könnte ein Container mit hohem ZIndex sein eigenes Kind mit niedrigerem ZIndex
-- optisch verdecken, obwohl es normal verschachtelt ist.
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== Kleiner Auslöse-Button, mittig rechts am Bildschirmrand =====
local openButton = Instance.new("TextButton")
openButton.Name = "DebugOpenButton"
openButton.Size = UDim2.new(0, 48, 0, 48)
openButton.AnchorPoint = Vector2.new(1, 0.5)
openButton.Position = UDim2.new(1, -12, 0.5, 0)
openButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
openButton.Font = Enum.Font.LuckiestGuy
openButton.TextScaled = true
openButton.Text = "🛠️"
openButton.Parent = screenGui
applyComicStyle(openButton, 12, 3)

-- ===== Zentrales Debug-Fenster + abgedunkelter Hintergrund =====
local backdrop = Instance.new("TextButton")
backdrop.Name = "DebugBackdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.5
backdrop.AutoButtonColor = false
backdrop.Text = ""
backdrop.Visible = false
backdrop.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "DebugPanel"
-- Vorletzter Summand: Zeile für den Spec-Prüfer-Knopf.
-- Letzter Summand: drei Zeilen für den Showdown.
panel.Size = UDim2.new(0, 340, 0, 340 + 60 + 90 + 50 + 50 + 50 + 50 + 150 + 34)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(35, 32, 45)
panel.Visible = false
panel.Parent = screenGui
applyComicStyle(panel, 16, 3)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -70, 0, 32)
titleLabel.Position = UDim2.new(0, 16, 0, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.LuckiestGuy
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Text = "Debug"
titleLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 36, 0, 36)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
closeButton.Font = Enum.Font.FredokaOne
closeButton.TextScaled = true
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "X"
closeButton.Parent = panel
applyComicStyle(closeButton, 8, 2)

local function setDebugWindowOpen(open)
	panel.Visible = open
	backdrop.Visible = open
end

openButton.MouseButton1Click:Connect(function()
	setDebugWindowOpen(true)
end)
closeButton.MouseButton1Click:Connect(function()
	setDebugWindowOpen(false)
end)
backdrop.MouseButton1Click:Connect(function()
	setDebugWindowOpen(false)
end)

-- ===== Debug-Modus-Umschalter (Checkbox + Beschriftung) =====
local checkboxRow = Instance.new("Frame")
checkboxRow.Size = UDim2.new(1, -32, 0, 34)
checkboxRow.Position = UDim2.new(0, 16, 0, 54)
checkboxRow.BackgroundTransparency = 1
checkboxRow.Parent = panel

local checkbox = Instance.new("TextButton")
checkbox.Name = "Checkbox"
checkbox.Size = UDim2.new(0, 30, 0, 30)
checkbox.Position = UDim2.new(0, 0, 0, 2)
checkbox.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
checkbox.Text = ""
checkbox.AutoButtonColor = false
checkbox.Parent = checkboxRow
applyComicStyle(checkbox, 6, 2)

local checkmark = Instance.new("TextLabel")
checkmark.Size = UDim2.new(1, 0, 1, 0)
checkmark.BackgroundTransparency = 1
checkmark.Font = Enum.Font.LuckiestGuy
checkmark.TextScaled = true
checkmark.TextColor3 = Color3.fromRGB(120, 255, 140)
checkmark.Text = ""
checkmark.Parent = checkbox

local label = Instance.new("TextLabel")
label.Name = "Label"
label.Size = UDim2.new(1, -44, 0, 34)
label.Position = UDim2.new(0, 44, 0, 0)
label.BackgroundTransparency = 1
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = "Debug Mode (Key V)"
label.Parent = checkboxRow

-- ===== Generische Schieberegler-Komponente -- wird für Level UND Stadt-Alert genutzt,
-- statt denselben Aufbau doppelt zu duplizieren. =====
local function createSlider(yPosition, initialLabelText, onRatioChanged)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -32, 0, 40)
	row.Position = UDim2.new(0, 16, 0, yPosition)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = panel

	local sliderLabel = Instance.new("TextLabel")
	sliderLabel.Name = "SliderLabel"
	sliderLabel.Size = UDim2.new(1, 0, 0, 16)
	sliderLabel.BackgroundTransparency = 1
	sliderLabel.Font = Enum.Font.FredokaOne
	sliderLabel.TextScaled = true
	sliderLabel.TextColor3 = Color3.new(1, 1, 1)
	sliderLabel.TextXAlignment = Enum.TextXAlignment.Left
	sliderLabel.Text = initialLabelText
	sliderLabel.Parent = row

	local sliderTrack = Instance.new("Frame")
	sliderTrack.Name = "SliderTrack"
	sliderTrack.Size = UDim2.new(1, 0, 0, 16)
	sliderTrack.Position = UDim2.new(0, 0, 0, 20)
	sliderTrack.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
	sliderTrack.Parent = row
	applyComicStyle(sliderTrack, 8, 2)

	local sliderFill = Instance.new("Frame")
	sliderFill.Name = "SliderFill"
	sliderFill.Size = UDim2.new(0, 0, 1, 0)
	sliderFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	sliderFill.BorderSizePixel = 0
	sliderFill.Parent = sliderTrack
	applyComicStyle(sliderFill, 6, 0)

	local sliderHandle = Instance.new("Frame")
	sliderHandle.Name = "SliderHandle"
	sliderHandle.Size = UDim2.new(0, 16, 0, 24)
	sliderHandle.AnchorPoint = Vector2.new(0.5, 0.5)
	sliderHandle.Position = UDim2.new(0, 0, 0.5, 0)
	sliderHandle.BackgroundColor3 = Color3.new(1, 1, 1)
	sliderHandle.ZIndex = 2
	sliderHandle.Parent = sliderTrack
	applyComicStyle(sliderHandle, 5, 2)

	local dragging = false

	local function updateVisual(ratio)
		sliderFill.Size = UDim2.new(ratio, 0, 1, 0)
		sliderHandle.Position = UDim2.new(ratio, 0, 0.5, 0)
	end

	local function ratioFromInputPosition(inputPosition)
		local trackAbsolutePosition = sliderTrack.AbsolutePosition.X
		local trackAbsoluteSize = sliderTrack.AbsoluteSize.X
		if trackAbsoluteSize <= 0 then
			return 0
		end
		return (inputPosition.X - trackAbsolutePosition) / trackAbsoluteSize
	end

	local function setFromRatio(ratio)
		ratio = math.clamp(ratio, 0, 1)
		updateVisual(ratio)
		onRatioChanged(ratio, sliderLabel)
	end

	local function beginDrag(input)
		dragging = true
		setFromRatio(ratioFromInputPosition(input.Position))
	end

	sliderTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
		end
	end)
	sliderHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			setFromRatio(ratioFromInputPosition(input.Position))
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- Setzt den Regler NUR visuell zurück (Füllung + Handle-Position), OHNE dabei
	-- onRatioChanged (und damit z.B. DebugSetLevelEvent) erneut auszulösen -- wichtig für
	-- den Reset-Fall, wo der Server-Wert ja schon auf 0 steht und nicht nochmal gesetzt
	-- werden muss.
	local function resetVisualOnly(ratio, labelText)
		updateVisual(ratio)
		sliderLabel.Text = labelText
	end

	return row, resetVisualOnly
end

-- ===== Level-Schieberegler: setzt Level + alle drei Skill-Werte (auf deren Cap) =====
local levelSliderRow, resetLevelSliderVisual = createSlider(96, "Level: 0", function(ratio, sliderLabel)
	local currentLevel = math.floor(ratio * MAX_DEBUG_LEVEL + 0.5)
	sliderLabel.Text = "Level: " .. currentLevel
	if DebugSetLevelEvent then
		DebugSetLevelEvent:FireServer(currentLevel)
	end
end)

-- ===== Stadt-Alert-Schieberegler: setzt die Alert-STUFE der Stadt, in der man gerade
-- steht, direkt auf einen von 6 diskreten Werten (0-5) -- eine Stufe pro Sechstel des
-- Reglers, analog zum Spieler-Level-Regler-Muster oben (kontinuierliches Ziehen, aber
-- gerundeter diskreter Wert für Label + Server). Vorher: stufenloser Prozent-Regler, der
-- ausserdem bei Level 3 gedeckelt war -- Level 4/5 waren darüber gar nicht erreichbar.
local MAX_DEBUG_ALERT_LEVEL = 5
local cityAlertSliderRow = createSlider(148, "City Alert Level: 0", function(ratio, sliderLabel)
	local level = math.floor(ratio * MAX_DEBUG_ALERT_LEVEL + 0.5)
	sliderLabel.Text = "City Alert Level: " .. level
	if DebugSetCityAlertEvent then
		DebugSetCityAlertEvent:FireServer(level)
	end
end)


-- ===== Welt-Event-Reroll-Button: löst sofort einen neuen Würfelwurf aus (gleiche
-- Wahrscheinlichkeiten wie der reguläre 15-Minuten-Timer) =====
local rerollButton = Instance.new("TextButton")
rerollButton.Name = "RerollWorldEventButton"
rerollButton.Size = UDim2.new(1, -32, 0, 36)
rerollButton.Position = UDim2.new(0, 16, 0, 200)
rerollButton.BackgroundColor3 = Color3.fromRGB(90, 70, 140)
rerollButton.Font = Enum.Font.FredokaOne
rerollButton.TextScaled = true
rerollButton.TextColor3 = Color3.new(1, 1, 1)
rerollButton.Text = "🎲 Roll World Event"
rerollButton.Visible = false
rerollButton.Parent = panel
applyComicStyle(rerollButton, 10, 2)

rerollButton.MouseButton1Click:Connect(function()
	if DebugRollWorldEventEvent then
		DebugRollWorldEventEvent:FireServer()
	end
end)

-- ===== Fraktions-Umschalter: sofortiger Wechsel ohne Freischalt-Prüfung =====
local factionRow = Instance.new("Frame")
factionRow.Name = "FactionSwitchRow"
factionRow.Size = UDim2.new(1, -32, 0, 60)
factionRow.Position = UDim2.new(0, 16, 0, 246)
factionRow.BackgroundTransparency = 1
factionRow.Visible = false
factionRow.Parent = panel

local factionRowLabel = Instance.new("TextLabel")
factionRowLabel.Size = UDim2.new(1, 0, 0, 16)
factionRowLabel.BackgroundTransparency = 1
factionRowLabel.Font = Enum.Font.FredokaOne
factionRowLabel.TextScaled = true
factionRowLabel.TextColor3 = Color3.new(1, 1, 1)
factionRowLabel.TextXAlignment = Enum.TextXAlignment.Left
factionRowLabel.Text = "Faction"
factionRowLabel.Parent = factionRow

local factionButtonsFrame = Instance.new("Frame")
factionButtonsFrame.Size = UDim2.new(1, 0, 0, 36)
factionButtonsFrame.Position = UDim2.new(0, 0, 0, 20)
factionButtonsFrame.BackgroundTransparency = 1
factionButtonsFrame.Parent = factionRow

local factionButtonsLayout = Instance.new("UIListLayout")
factionButtonsLayout.FillDirection = Enum.FillDirection.Horizontal
factionButtonsLayout.Padding = UDim.new(0, 6)
factionButtonsLayout.Parent = factionButtonsFrame

local FACTION_DEBUG_BUTTONS = {
	{ key = "Kaiju", icon = "🦖", color = Color3.fromRGB(90, 170, 100) },
	{ key = "Jaeger", icon = "🤖", color = Color3.fromRGB(80, 130, 220) },
	{ key = "Ronin", icon = "🐯", color = Color3.fromRGB(220, 140, 60) },
}

for _, factionConfig in ipairs(FACTION_DEBUG_BUTTONS) do
	local factionButton = Instance.new("TextButton")
	factionButton.Name = factionConfig.key .. "DebugButton"
	factionButton.Size = UDim2.new(0, 96, 1, 0)
	factionButton.BackgroundColor3 = factionConfig.color
	factionButton.Font = Enum.Font.FredokaOne
	factionButton.TextScaled = true
	factionButton.TextColor3 = Color3.new(1, 1, 1)
	factionButton.Text = factionConfig.icon .. " " .. factionConfig.key
	factionButton.Parent = factionButtonsFrame
	applyComicStyle(factionButton, 8, 2)

	factionButton.MouseButton1Click:Connect(function()
		DebugSetFactionEvent:FireServer(factionConfig.key)
	end)
end

-- ===== Alert-Debug-Anzeige: rohe Zahlen (nicht nur die Sterne/Balken im normalen HUD),
-- damit man exakt nachvollziehen kann, wann Level 1 bzw. Level 2 erreicht wird. =====
local alertDebugFrame = Instance.new("Frame")
alertDebugFrame.Name = "AlertDebugFrame"
alertDebugFrame.Size = UDim2.new(1, -32, 0, 84)
alertDebugFrame.Position = UDim2.new(0, 16, 0, 316)
alertDebugFrame.BackgroundColor3 = Color3.fromRGB(25, 22, 32)
alertDebugFrame.Parent = panel
applyComicStyle(alertDebugFrame, 10, 2)

local alertDebugLabel = Instance.new("TextLabel")
alertDebugLabel.Name = "AlertDebugLabel"
alertDebugLabel.Size = UDim2.new(1, -16, 1, -12)
alertDebugLabel.Position = UDim2.new(0, 8, 0, 6)
alertDebugLabel.BackgroundTransparency = 1
alertDebugLabel.Font = Enum.Font.Code
alertDebugLabel.TextScaled = true
alertDebugLabel.TextXAlignment = Enum.TextXAlignment.Left
alertDebugLabel.TextYAlignment = Enum.TextYAlignment.Top
alertDebugLabel.TextColor3 = Color3.fromRGB(150, 255, 170)
alertDebugLabel.Text = "Alert Debug: -- (keine Stadt)"
alertDebugLabel.Parent = alertDebugFrame

local cityAlertValuesFolder = nil

local function updateAlertDebugLabel()
	if not cityAlertValuesFolder then
		alertDebugLabel.Text = "Alert Debug: lädt... (CityAlertValues)"
		return
	end
	if not CityAlertConfig then
		alertDebugLabel.Text = "Alert Debug: lädt... (CityAlertConfig)"
		return
	end

	local cityName = player:GetAttribute("CurrentCityName")
	if not cityName or cityName == "None" or cityName == "" then
		alertDebugLabel.Text = "Alert Debug: nicht in einer Stadt"
		return
	end

	local levelValue = cityAlertValuesFolder:FindFirstChild(cityName .. "Level")
	local progressValue = cityAlertValuesFolder:FindFirstChild(cityName .. "Progress")
	local config = CityAlertConfig.GetCityConfig(cityName)
	if not levelValue or not progressValue or not config then
		alertDebugLabel.Text = "Alert Debug: Werte für '" .. tostring(cityName) .. "' nicht gefunden"
		return
	end

	local currentLevel = levelValue.Value
	local progress = progressValue.Value

	-- Zeigt den Fortschritt zur JEWEILS NÄCHSTEN Stufe, basierend auf dem aktuellen Level
	-- -- vorher stand hier immer fest die Level-2-Schwelle, auch wenn man schon bei
	-- Level 3 war (zeigte dann fälschlich "0 Punkte bis Level 2").
	local nextLevelLabel, threshold
	if currentLevel == 0 then
		nextLevelLabel, threshold = "Level 1", nil -- Level 0->1 ist event-basiert (erstes zerstörtes Gebäude), keine Punkte-Schwelle
	elseif currentLevel == 1 then
		nextLevelLabel, threshold = "Level 2", config.AlertThresholdLevel2
	elseif currentLevel == 2 then
		nextLevelLabel, threshold = "Level 3", config.AlertThresholdLevel3
	elseif currentLevel == 3 then
		nextLevelLabel, threshold = "Level 4", config.AlertThresholdLevel4
	else
		nextLevelLabel, threshold = nil, nil
	end

	local nextLevelText
	if currentLevel == 0 then
		nextLevelText = "Level 1 startet, sobald das erste Gebäude zerstört wird"
	elseif threshold then
		local remaining = math.max(threshold - progress, 0)
		nextLevelText = string.format("Noch %.0f Punkte bis %s", remaining, nextLevelLabel)
	else
		nextLevelText = "Höchste bekannte Stufe erreicht"
	end

	alertDebugLabel.Text = string.format(
		"%s | Level %d\n%.0f Punkte gesamt\n%s\nAbbau: %.0fs Wartezeit, %.0f Pkt/s danach",
		cityName, currentLevel, progress,
		nextLevelText,
		config.AlertDecayDelay or 0, config.AlertDecayRate or 0
	)
end

updateAlertDebugLabel()
player:GetAttributeChangedSignal("CurrentCityName"):Connect(updateAlertDebugLabel)

-- Beide Abhängigkeiten (CityAlertConfig-Modul + CityAlertValues-Ordner) asynchron
-- nachladen -- blockiert dadurch NICHTS anderes im Script mehr, auch nicht die Taste V.
task.spawn(function()
	local cityAlertConfigModule = ReplicatedStorage:WaitForChild("CityAlertConfig", 15)
	if cityAlertConfigModule then
		local ok, result = pcall(require, cityAlertConfigModule)
		if ok then
			CityAlertConfig = result
			updateAlertDebugLabel()
		else
			warn("[DebugPanelClient] CityAlertConfig konnte nicht geladen werden: " .. tostring(result))
		end
	else
		warn("[DebugPanelClient] CityAlertConfig nicht gefunden (Timeout) -- Alert-Debug-Anzeige bleibt leer.")
	end
end)

task.spawn(function()
	cityAlertValuesFolder = ReplicatedStorage:WaitForChild("CityAlertValues", 15)
	if cityAlertValuesFolder then
		updateAlertDebugLabel()
		for _, valueObject in ipairs(cityAlertValuesFolder:GetChildren()) do
			if valueObject.Name:match("Level$") or valueObject.Name:match("Progress$") then
				valueObject:GetPropertyChangedSignal("Value"):Connect(updateAlertDebugLabel)
			end
		end
	else
		warn("[DebugPanelClient] CityAlertValues nicht gefunden (Timeout) -- Alert-Debug-Anzeige bleibt leer.")
	end
end)

-- ===== Spielerdaten-Reset: zweiter Klick (innert 3s) löst den echten Reset aus =====
local resetButton = Instance.new("TextButton")
resetButton.Name = "DebugResetButton"
resetButton.Size = UDim2.new(1, -32, 0, 40)
resetButton.Position = UDim2.new(0, 16, 0, 316 + 90)
resetButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
resetButton.Font = Enum.Font.FredokaOne
resetButton.TextScaled = true
resetButton.TextColor3 = Color3.new(1, 1, 1)
resetButton.Text = "🔄 Debug Reset"
resetButton.AutoButtonColor = true
resetButton.Parent = panel
applyComicStyle(resetButton, 10, 2)

local awaitingConfirm = false
local confirmTimer = nil

resetButton.MouseButton1Click:Connect(function()
	if not awaitingConfirm then
		awaitingConfirm = true
		resetButton.Text = "⚠️ Sure? Click again!"
		resetButton.BackgroundColor3 = Color3.fromRGB(230, 160, 40)

		if confirmTimer then
			task.cancel(confirmTimer)
		end
		confirmTimer = task.delay(3, function()
			awaitingConfirm = false
			resetButton.Text = "🔄 Debug Reset"
			resetButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
		end)
		return
	end

	if confirmTimer then
		task.cancel(confirmTimer)
		confirmTimer = nil
	end
	awaitingConfirm = false

	if ResetPlayerDataEvent then
		-- false = Prolog NICHT mit zuruecksetzen. Der zweite Knopf weiter unten feuert
		-- dasselbe Ereignis mit true.
		ResetPlayerDataEvent:FireServer(false)
	end

	-- Level-Regler im Debug-Fenster visuell mit zurücksetzen -- sonst würde er weiterhin
	-- den alten Level-Wert anzeigen, obwohl der Spieler serverseitig schon auf Level 0
	-- zurückgesetzt wurde.
	if resetLevelSliderVisual then
		resetLevelSliderVisual(0, "Level: 0")
	end

	resetButton.Text = "✅ Reset!"
	resetButton.BackgroundColor3 = Color3.fromRGB(90, 200, 100)
	task.delay(1.5, function()
		resetButton.Text = "🔄 Debug Reset"
		resetButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	end)
end)

-- ===== Zweiter Knopf: auch den Prolog zuruecksetzen =====
-- Bewusst getrennt und kleiner. Den Fortschritt setzt man beim Testen staendig zurueck,
-- den Prolog selten -- beides auf denselben Knopf zu legen hiesse, entweder jedes Mal
-- den mehrminuetigen Prolog mitzuspielen oder ihn nie testen zu koennen.
local resetPrologueButton = Instance.new("TextButton")
resetPrologueButton.Name = "DebugResetPrologueButton"
resetPrologueButton.Size = UDim2.new(1, -32, 0, 26)
-- ANS ENDE, nicht unter den Reset-Knopf: dort sitzt bereits die naechste Zeile (456).
-- Der Abstand ist hier sogar erwuenscht -- der Prolog-Reset kostet mehrere Minuten
-- Wiederholung und soll nicht neben dem Knopf liegen, den man staendig antippt.
resetPrologueButton.Position = UDim2.new(0, 16, 0, 806)
resetPrologueButton.BackgroundColor3 = Color3.fromRGB(120, 60, 90)
resetPrologueButton.Font = Enum.Font.FredokaOne
resetPrologueButton.TextScaled = true
resetPrologueButton.TextColor3 = Color3.new(1, 1, 1)
resetPrologueButton.Text = "⏮ Auch Prolog zuruecksetzen"
resetPrologueButton.Parent = panel
applyComicStyle(resetPrologueButton, 8, 2)

local prologueAwaitingConfirm = false
local prologueConfirmTimer = nil

local function resetPrologueButtonIdle()
	prologueAwaitingConfirm = false
	resetPrologueButton.Text = "⏮ Auch Prolog zuruecksetzen"
	resetPrologueButton.BackgroundColor3 = Color3.fromRGB(120, 60, 90)
end

resetPrologueButton.MouseButton1Click:Connect(function()
	if not prologueAwaitingConfirm then
		prologueAwaitingConfirm = true
		resetPrologueButton.Text = "⚠️ Sure? Click again!"
		resetPrologueButton.BackgroundColor3 = Color3.fromRGB(230, 160, 40)
		if prologueConfirmTimer then
			task.cancel(prologueConfirmTimer)
		end
		prologueConfirmTimer = task.delay(3, resetPrologueButtonIdle)
		return
	end
	if prologueConfirmTimer then
		task.cancel(prologueConfirmTimer)
		prologueConfirmTimer = nil
	end
	prologueAwaitingConfirm = false

	if ResetPlayerDataEvent then
		ResetPlayerDataEvent:FireServer(true)
	end
	if resetLevelSliderVisual then
		resetLevelSliderVisual(0, "Level: 0")
	end
	task.delay(1.5, resetPrologueButtonIdle)
end)

-- ===== Wer die beiden Knoepfe sieht =====
-- Der Server entscheidet und setzt das Attribut; hier wird es nur befolgt. Ausblenden
-- statt sperren: ein sichtbarer Knopf, der nichts tut, sieht aus wie ein Fehler.
local function refreshResetVisibility()
	local allowed = player:GetAttribute("MayResetData") == true
	resetButton.Visible = allowed
	resetPrologueButton.Visible = allowed
end
player:GetAttributeChangedSignal("MayResetData"):Connect(refreshResetVisibility)
refreshResetVisibility()

-- ===== Rueckmeldung des Servers =====
-- Wichtigster Fall: zurueckgesetzt, aber NICHT gespeichert. Ohne diese Meldung wirkt der
-- Reset und ist beim naechsten Beitritt wieder weg.
if ResetPlayerDataEvent then
	ResetPlayerDataEvent.OnClientEvent:Connect(function(saved, problem)
		if saved then
			resetButton.Text = "✅ Reset!"
			resetButton.BackgroundColor3 = Color3.fromRGB(90, 200, 100)
		else
			resetButton.Text = "⚠️ " .. tostring(problem)
			resetButton.BackgroundColor3 = Color3.fromRGB(200, 120, 40)
			warn("[DebugPanelClient] Reset nicht gespeichert: " .. tostring(problem))
		end
		task.delay(4, function()
			resetButton.Text = "🔄 Debug Reset"
			resetButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
		end)
	end)
end

-- ===== Partikel-An/Aus-Umschalter: reines Performance-Diagnose-Werkzeug (rein
-- clientseitig -- betrifft nur die eigene Sicht, nicht andere Spieler). Deaktiviert ALLE
-- aktuell existierenden ParticleEmitter im Workspace und fängt über DescendantAdded auch
-- künftig neu erzeugte automatisch ab, solange der Schalter aus ist -- sonst würden neue
-- Effekte (Explosionen, Feuer, etc.) den Ausschalt-Zustand sofort wieder durchbrechen. =====
local particlesEnabled = true
local particleWatcherConnection = nil

local function setAllParticlesEnabled(enabled)
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = enabled
		end
	end
end

local particleToggleButton = Instance.new("TextButton")
particleToggleButton.Name = "ParticleToggleButton"
particleToggleButton.Size = UDim2.new(1, -32, 0, 40)
particleToggleButton.Position = UDim2.new(0, 16, 0, 316 + 90 + 50)
particleToggleButton.BackgroundColor3 = Color3.fromRGB(60, 140, 90)
particleToggleButton.Font = Enum.Font.FredokaOne
particleToggleButton.TextScaled = true
particleToggleButton.TextColor3 = Color3.new(1, 1, 1)
particleToggleButton.Text = "✨ Particles: ON"
particleToggleButton.AutoButtonColor = true
particleToggleButton.Parent = panel
applyComicStyle(particleToggleButton, 10, 2)

particleToggleButton.MouseButton1Click:Connect(function()
	particlesEnabled = not particlesEnabled
	setAllParticlesEnabled(particlesEnabled)

	if particlesEnabled then
		particleToggleButton.Text = "✨ Particles: ON"
		particleToggleButton.BackgroundColor3 = Color3.fromRGB(60, 140, 90)
		if particleWatcherConnection then
			particleWatcherConnection:Disconnect()
			particleWatcherConnection = nil
		end
	else
		particleToggleButton.Text = "🚫 Particles: OFF"
		particleToggleButton.BackgroundColor3 = Color3.fromRGB(140, 60, 60)
		if not particleWatcherConnection then
			particleWatcherConnection = workspace.DescendantAdded:Connect(function(descendant)
				if not particlesEnabled and descendant:IsA("ParticleEmitter") then
					descendant.Enabled = false
				end
			end)
		end
	end
end)

-- ===== Zerstörungs-Animation-Überspringen: globaler Schalter (gilt für ALLE Spieler,
-- nicht nur den umschaltenden) -- praktisch, um beim Testen schneller durch mehrere
-- Zerstörungs-Zyklen zu kommen, ohne jedes Mal die ~1 Sekunde lange Einsturz-Animation
-- abwarten zu müssen. =====
local skipCollapseEnabled = false

local skipCollapseButton = Instance.new("TextButton")
skipCollapseButton.Name = "SkipCollapseAnimationButton"
skipCollapseButton.Size = UDim2.new(1, -32, 0, 40)
skipCollapseButton.Position = UDim2.new(0, 16, 0, 316 + 90 + 50 + 50)
skipCollapseButton.BackgroundColor3 = Color3.fromRGB(90, 90, 140)
skipCollapseButton.Font = Enum.Font.FredokaOne
skipCollapseButton.TextScaled = true
skipCollapseButton.TextColor3 = Color3.new(1, 1, 1)
skipCollapseButton.Text = "🏚️ Skip Collapse Anim: OFF"
skipCollapseButton.AutoButtonColor = true
skipCollapseButton.Parent = panel
applyComicStyle(skipCollapseButton, 10, 2)

skipCollapseButton.MouseButton1Click:Connect(function()
	skipCollapseEnabled = not skipCollapseEnabled
	if DebugToggleSkipCollapseEvent then
		DebugToggleSkipCollapseEvent:FireServer()
	end

	if skipCollapseEnabled then
		skipCollapseButton.Text = "🏚️ Skip Collapse Anim: ON"
		skipCollapseButton.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
	else
		skipCollapseButton.Text = "🏚️ Skip Collapse Anim: OFF"
		skipCollapseButton.BackgroundColor3 = Color3.fromRGB(90, 90, 140)
	end
end)

-- ===== Prolog manuell starten (Debug) =====
-- Praktisch zum Testen/Iterieren am Playable Prologue, ohne jedes Mal einen komplett
-- neuen Account/Speicher zu brauchen.
local startPrologueButton = Instance.new("TextButton")
startPrologueButton.Name = "StartPrologueButton"
startPrologueButton.Size = UDim2.new(1, -32, 0, 40)
startPrologueButton.Position = UDim2.new(0, 16, 0, 316 + 90 + 50 + 50 + 50)
startPrologueButton.BackgroundColor3 = Color3.fromRGB(140, 90, 60)
startPrologueButton.Font = Enum.Font.FredokaOne
startPrologueButton.TextScaled = true
startPrologueButton.TextColor3 = Color3.new(1, 1, 1)
startPrologueButton.Text = "🎬 Start Prologue"
startPrologueButton.AutoButtonColor = true
startPrologueButton.Parent = panel
applyComicStyle(startPrologueButton, 10, 2)

local startPrologueButtonLocked = false

local function unlockStartPrologueButton()
	startPrologueButtonLocked = false
	startPrologueButton.AutoButtonColor = true
	startPrologueButton.BackgroundColor3 = Color3.fromRGB(140, 90, 60)
	startPrologueButton.Text = "🎬 Start Prologue"
end

if DebugStartPrologueResultEvent then
	DebugStartPrologueResultEvent.OnClientEvent:Connect(function(success, errorMessage)
		if success then
			startPrologueButton.Text = "🎬 Gestartet!"
			task.delay(10, unlockStartPrologueButton)
		else
			-- Abgelehnt (z.B. Debug-Modus noch nicht aktiv) -- SOFORT wieder freigeben,
			-- statt 10s zu sperren, damit direkt erneut geklickt werden kann.
			startPrologueButton.Text = "⚠️ " .. tostring(errorMessage or "Fehlgeschlagen")
			task.delay(2.5, unlockStartPrologueButton)
		end
	end)
end

startPrologueButton.MouseButton1Click:Connect(function()
	if startPrologueButtonLocked then
		return -- Sperre aktiv -- ignoriert weitere Klicks, bis der Server geantwortet hat
	end
	if DebugStartPrologueEvent then
		startPrologueButtonLocked = true
		startPrologueButton.AutoButtonColor = false
		startPrologueButton.BackgroundColor3 = Color3.fromRGB(90, 60, 40)
		startPrologueButton.Text = "🎬 Sende..."
		DebugStartPrologueEvent:FireServer()
		-- Sicherheitsnetz: falls der Server aus irgendeinem Grund NIE antwortet (z.B.
		-- DebugStartPrologueResultEvent-Event fehlt), spätestens hier wieder freigeben.
		task.delay(10, unlockStartPrologueButton)
	end
end)

-- ===== Modus-Umschaltung (Checkbox + Taste V) =====
local function updateCheckboxVisual()
	local isOn = player:GetAttribute("DebugMode")
	checkmark.Text = isOn and "✓" or ""
	checkbox.BackgroundColor3 = isOn and Color3.fromRGB(60, 140, 70) or Color3.fromRGB(80, 80, 90)
	levelSliderRow.Visible = isOn
	cityAlertSliderRow.Visible = isOn
	rerollButton.Visible = isOn
	factionRow.Visible = isOn
end

local function toggleDebugMode()
	local newValue = not player:GetAttribute("DebugMode")
	player:SetAttribute("DebugMode", newValue)
	-- WICHTIG: player:SetAttribute() vom Client aus repliziert NICHT zum Server --
	-- der Server braucht eine eigene, autoritative Kopie (z.B. für die Schieberegler,
	-- die serverseitig prüfen, ob Debug-Modus aktiv ist).
	if SetDebugModeEvent then
		SetDebugModeEvent:FireServer(newValue)
	end
end

-- Sobald der Prolog startet: Debug-Panel schliessen und Debug-Modus deaktivieren -- ein
-- offenes Debug-Panel wäre während der Kinematik/Cutscene störend und unpassend.
player:GetAttributeChangedSignal("IsInPrologue"):Connect(function()
	if player:GetAttribute("IsInPrologue") then
		setDebugWindowOpen(false)
		if player:GetAttribute("DebugMode") then
			toggleDebugMode()
		end
	end
end)

checkbox.MouseButton1Click:Connect(toggleDebugMode)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == TOGGLE_KEY then
		toggleDebugMode()
	end
end)

-- ===== Spec-Prüfung erneut auslösen =====
-- Der SpecCheckService prüft beim Serverstart automatisch, aber nur die Regeln, die ohne
-- laufendes Spiel auskommen. Von HIER ausgelöst laufen zusätzlich die Laufzeit-Regeln
-- (needsRuntime) -- also nach dem Spawnen eines Guardians, nach einer Alarmstufe, nach
-- allem, was den Zustand ändert. Die Ausgabe erscheint mit Präfix [Kaiju Spec] im Server-
-- Log, nicht hier im Panel.
local specCheckButton = Instance.new("TextButton")
specCheckButton.Name = "RunSpecCheckButton"
specCheckButton.Size = UDim2.new(1, -32, 0, 40)
specCheckButton.Position = UDim2.new(0, 16, 0, 316 + 90 + 50 + 50 + 50 + 50)
specCheckButton.BackgroundColor3 = Color3.fromRGB(70, 110, 100)
specCheckButton.Font = Enum.Font.FredokaOne
specCheckButton.TextScaled = true
specCheckButton.TextColor3 = Color3.new(1, 1, 1)
specCheckButton.Text = "📋 Spec-Prüfung"
specCheckButton.AutoButtonColor = true
specCheckButton.Parent = panel
applyComicStyle(specCheckButton, 10, 2)

specCheckButton.MouseButton1Click:Connect(function()
	if not DebugRunSpecCheckEvent then
		specCheckButton.Text = "⚠️ Event fehlt"
		task.delay(2.5, function()
			specCheckButton.Text = "📋 Spec-Prüfung"
		end)
		return
	end
	DebugRunSpecCheckEvent:FireServer()
	-- Kurze Rückmeldung am Knopf: das Ergebnis steht im Server-Log, nicht hier -- ohne
	-- diesen Hinweis klickt man sonst mehrfach und glaubt, es passiere nichts.
	specCheckButton.Text = "📋 läuft -- siehe Output"
	task.delay(3, function()
		specCheckButton.Text = "📋 Spec-Prüfung"
	end)
end)

player:GetAttributeChangedSignal("DebugMode"):Connect(updateCheckboxVisual)
updateCheckboxVisual()

-- ===== Showdown =====
-- Ein Showdown, den man nur durch echtes Kaempfen ausloesen kann, ist muehsam zu pruefen
-- -- besonders die Shots, die hoechstens alle sechs Sekunden kommen. Der wichtigste
-- Schalter ist deshalb "Shot ausloesen": ohne ihn muesste man fuer jede Korrektur an
-- einer Kamerafahrt einen echten Kampf provozieren und sechs Sekunden warten.
--
-- ACHTUNG: das Debug-Panel ist waehrend eines Showdowns ausgeblendet (so gewuenscht).
-- Der Shot laesst sich dort mit F8 ausloesen -- siehe ShowdownClient.
-- waitForRemote wie bei allen anderen Debug-Ereignissen: GetOrCreate wuerde auf dem
-- Client eine LOKALE Kopie anlegen, falls das Ereignis des Servers noch nicht repliziert
-- ist -- FireServer ginge dann ins Leere, ohne Fehlermeldung.
local DebugShowdownEvent = waitForRemote("DebugShowdownEvent")

local SHOWDOWN_ROW_Y = 656

local function makeShowdownButton(name, text, xScale, xOffset, widthScale, widthOffset, rowOffset, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(widthScale, widthOffset, 0, 40)
	button.Position = UDim2.new(xScale, xOffset, 0, SHOWDOWN_ROW_Y + rowOffset)
	button.BackgroundColor3 = color
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.Parent = panel
	applyComicStyle(button, 10, 2)
	return button
end

local forceShowdownButton = makeShowdownButton(
	"ForceShowdownButton", "⚔️ Showdown erzwingen", 0, 16, 1, -32, 0, Color3.fromRGB(150, 70, 70))
forceShowdownButton.MouseButton1Click:Connect(function()
	if DebugShowdownEvent then
		DebugShowdownEvent:FireServer("Force")
	end
end)

-- Die Shot-Namen stehen in der Config; hier nur die Reihenfolge zum Durchblaettern.
local SHOWDOWN_SHOT_NAMES = { "FocusLaser", "AreaAttack", "WarningPulse", "ContainmentNet", "ShoulderMissiles" }
local shotIndex = 1

local shotPickButton = makeShowdownButton(
	"ShowdownShotPickButton", "🎬 " .. SHOWDOWN_SHOT_NAMES[1], 0, 16, 0.6, -20, 50, Color3.fromRGB(80, 80, 120))
shotPickButton.MouseButton1Click:Connect(function()
	shotIndex = shotIndex % #SHOWDOWN_SHOT_NAMES + 1
	shotPickButton.Text = "🎬 " .. SHOWDOWN_SHOT_NAMES[shotIndex]
end)

local shotFireButton = makeShowdownButton(
	"ShowdownShotFireButton", "▶ Shot", 0.6, 4, 0.4, -20, 50, Color3.fromRGB(70, 130, 90))
shotFireButton.MouseButton1Click:Connect(function()
	if DebugShowdownEvent then
		DebugShowdownEvent:FireServer("Shot", SHOWDOWN_SHOT_NAMES[shotIndex])
	end
end)

local showdownEndButton = makeShowdownButton(
	"ShowdownEndButton", "⏹ Showdown beenden", 0, 16, 0.6, -20, 100, Color3.fromRGB(90, 90, 140))
showdownEndButton.MouseButton1Click:Connect(function()
	if DebugShowdownEvent then
		DebugShowdownEvent:FireServer("End")
	end
end)

local shortDurationEnabled = false
local shortDurationButton = makeShowdownButton(
	"ShowdownShortDurationButton", "⏱️ 3s: OFF", 0.6, 4, 0.4, -20, 100, Color3.fromRGB(90, 90, 140))
shortDurationButton.MouseButton1Click:Connect(function()
	shortDurationEnabled = not shortDurationEnabled
	if DebugShowdownEvent then
		DebugShowdownEvent:FireServer("ShortDuration", shortDurationEnabled)
	end
	shortDurationButton.Text = shortDurationEnabled and "⏱️ 3s: ON" or "⏱️ 3s: OFF"
	shortDurationButton.BackgroundColor3 = shortDurationEnabled
		and Color3.fromRGB(60, 90, 140)
		or Color3.fromRGB(90, 90, 140)
end)
