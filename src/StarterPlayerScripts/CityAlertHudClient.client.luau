-- VERSION: 2026-09-12 #2
-- UMBAU: militaerisch/Sci-Fi ueber HudChrome; Druckanzeige entfernt
-- LocalScript: CityAlertHudClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt oben rechts, in welcher Stadt der Spieler steht, wie hoch die Alarmstufe ist,
-- welche Aufgaben offen sind -- und, sobald die Stadt gebrochen ist, den Countdown der
-- freien Zerstoerung. Attribut "CurrentCityName" wird serverseitig von
-- CityAlertService.lua gepflegt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

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

-- Jede Stadt hat eine Uhrzeit, und die Uhrzeit ist das Koordinatensystem der Welt: es
-- sind dieselben Indizes wie auf dem Zifferblatt im Sanctuary, wo jede Stunde eine
-- Portalbucht ist. Wer "04:00" liest, weiss danach, wo Small Town auf der Karte liegt --
-- das leistet kein Stadtname.
local CITY_HOURS = {
	Village = "02:00",
	SmallTown = "04:00",
	City = "06:00",
	LargeCity = "08:00",
	MegaCity = "10:00",
}

local MAX_ALERT_LEVEL = 5 -- so viele Segmente hat der Balken

local PANEL_BREITE = 236
local PANEL_HOEHE = 98
local PANEL_RAND = 10
local INNEN_BREITE = PANEL_BREITE - PANEL_RAND * 2

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CityAlertHudGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Das Feld sitzt UNTER der Reihe aus Geld, Home und Ton -- vorher lag es auf derselben
-- Hoehe wie der Ton-Knopf und damit teilweise unter ihm.
local alertFrame = Instance.new("Frame")
alertFrame.Name = "CityAlertFrame"
alertFrame.Size = UDim2.new(0, PANEL_BREITE, 0, PANEL_HOEHE)
alertFrame.AnchorPoint = Vector2.new(1, 0)
alertFrame.Position = UDim2.new(1, -16, 0, 118)
alertFrame.Visible = false
alertFrame.ZIndex = 20
alertFrame.Parent = screenGui
local _, alertStroke = HudChrome.Panel(alertFrame, { radius = HudChrome.Radius.Small })

-- ===== Kopfzeile: Stadt und Stunde =====
local cityNameLabel = Instance.new("TextLabel")
cityNameLabel.Name = "CityNameLabel"
cityNameLabel.Size = UDim2.new(0, INNEN_BREITE - 70, 0, 26)
cityNameLabel.Position = UDim2.new(0, PANEL_RAND, 0, 8)
cityNameLabel.BackgroundTransparency = 1
cityNameLabel.TextXAlignment = Enum.TextXAlignment.Left
cityNameLabel.ZIndex = 21
cityNameLabel.Text = ""
cityNameLabel.Parent = alertFrame
HudChrome.Label(cityNameLabel, 22)

local cityHourLabel = Instance.new("TextLabel")
cityHourLabel.Name = "CityHourLabel"
cityHourLabel.Size = UDim2.new(0, 66, 0, 26)
cityHourLabel.Position = UDim2.new(0, PANEL_RAND + INNEN_BREITE - 66, 0, 8)
cityHourLabel.BackgroundTransparency = 1
cityHourLabel.TextXAlignment = Enum.TextXAlignment.Right
cityHourLabel.ZIndex = 21
cityHourLabel.Text = ""
cityHourLabel.Parent = alertFrame
HudChrome.Number(cityHourLabel, 16)
cityHourLabel.TextColor3 = HudChrome.Color.TextDim

-- ===== Alarmstufe: Sterne =====
--
-- Der Fuenf-Segment-Balken war im Spiel schwaecher als die Sterne, die er ersetzt hat --
-- ein Balken ist eine Menge, ein Stern ist ein Ereignis. Wenn eine Stufe dazukommt, soll
-- etwas ERSCHEINEN, nicht ein Kaestchen die Farbe wechseln. Die Sterne sind zurueck, aber
-- ohne Comic-Umriss: Alarmfarbe, wenn erreicht, dunkles Grau, wenn noch nicht.
--
-- Es werden nur so viele Sterne gezeigt, wie diese Stadt Stufen hat. Drei Stufen, drei
-- Sterne. Platzhalter fuer Stufen, die es hier gar nicht gibt, machen die Anzeige nur
-- schwerer zu lesen und versprechen etwas, das nicht kommt.
local alertCaption = Instance.new("TextLabel")
alertCaption.Name = "AlertCaption"
alertCaption.Size = UDim2.new(0, 90, 0, 16)
alertCaption.Position = UDim2.new(0, PANEL_RAND, 0, 40)
alertCaption.BackgroundTransparency = 1
alertCaption.TextXAlignment = Enum.TextXAlignment.Left
alertCaption.ZIndex = 21
alertCaption.Text = "ALERT"
alertCaption.Parent = alertFrame
HudChrome.Label(alertCaption, 14)
alertCaption.TextColor3 = HudChrome.Color.TextSecondary

local STERN_GROESSE = 30

local starsContainer = Instance.new("Frame")
starsContainer.Name = "StarsContainer"
starsContainer.Size = UDim2.new(0, INNEN_BREITE, 0, STERN_GROESSE)
starsContainer.Position = UDim2.new(0, PANEL_RAND, 0, 60)
starsContainer.BackgroundTransparency = 1
starsContainer.ZIndex = 21
starsContainer.Parent = alertFrame

local starsLayout = Instance.new("UIListLayout")
starsLayout.FillDirection = Enum.FillDirection.Horizontal
starsLayout.Padding = UDim.new(0, 4)
starsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
starsLayout.SortOrder = Enum.SortOrder.LayoutOrder
starsLayout.Parent = starsContainer

local STERN_AUS = Color3.fromRGB(58, 64, 74) -- erreichbar, aber noch nicht erreicht

-- Das Sternzeichen gibt es weder in Oswald noch in RobotoMono. Eine dritte Schrift nur
-- fuer ein Zeichen ist vertretbar -- es ist ein SYMBOL, kein Text, und die Alternative
-- waere ein Bild, das erst hochgeladen werden muesste.
local starLabels = {}
for i = 1, MAX_ALERT_LEVEL do
	local star = Instance.new("TextLabel")
	star.Name = "Star" .. i
	star.Size = UDim2.new(0, STERN_GROESSE, 0, STERN_GROESSE)
	star.BackgroundTransparency = 1
	star.Font = Enum.Font.GothamBold
	star.TextScaled = true
	star.TextColor3 = STERN_AUS
	star.TextStrokeTransparency = 1
	star.Text = "\u{2605}"
	star.Visible = false
	star.LayoutOrder = i
	star.ZIndex = 21
	star.Parent = starsContainer
	starLabels[i] = star
end

-- Laesst EINEN Stern einfliegen: dreht sich schnell, bremst ab, blitzt kurz weiss auf.
-- Das ist der Moment, den der Balken nicht hatte.
local function animateStarIn(star, farbe)
	star.Visible = true
	star.Rotation = 0
	star.TextColor3 = farbe

	local spinTween = TweenService:Create(
		star,
		TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Rotation = 720 }
	)
	spinTween:Play()
	spinTween.Completed:Connect(function()
		star.Rotation = 0
		local flashTween = TweenService:Create(star, TweenInfo.new(0.12), { TextColor3 = Color3.new(1, 1, 1) })
		flashTween:Play()
		flashTween.Completed:Connect(function()
			TweenService:Create(star, TweenInfo.new(0.3), { TextColor3 = farbe }):Play()
		end)
	end)
end

-- Mehrere neue Sterne laufen NACHEINANDER ein, nicht gleichzeitig.
local function animateNewStars(fromCount, toCount, farbe)
	task.spawn(function()
		for i = fromCount + 1, toCount do
			local star = starLabels[i]
			if star then
				animateStarIn(star, farbe)
				task.wait(0.25)
			end
		end
	end)
end

local currentStarCount = 0
local lastShownMaxLevel = nil

-- Eine Anzeige des Drucks zur naechsten Stufe gibt es bewusst NICHT.
--
-- Sie stand hier zweimal: erst als mitlaufender Balken, dann als drei grobe Bloecke. Auch
-- grob war sie noch zu viel -- die Eskalation kuendigt sich ohnehin selbst an, sobald sie
-- eintritt, und diese Ankuendigung sagt auch, was jetzt kommt. Eine zweite Anzeige davor
-- nimmt dem Moment genau das, was ihn ausmacht: dass er ueberrascht.

-- Die Farbe der Alarmstufe: von Warnfarbe auf Gefahrfarbe, je naeher an der Hoechststufe
-- dieser Stadt. Sie ist eine MESSUNG und darf deshalb farbig sein -- das Chrome drumherum
-- bleibt farblos.
local function alarmFarbe(level, maxLevel)
	if maxLevel <= 1 then
		return HudChrome.Color.Danger
	end
	local anteil = math.clamp((level - 1) / (maxLevel - 1), 0, 1)
	return HudChrome.Color.Warning:Lerp(HudChrome.Color.Danger, anteil)
end

local lastShownLevel = nil

local function updateAlertHud()
	-- Sanctuary-Sonderfall: zeigt "Sanctuary" als Ortsname an (konsistent mit den echten
	-- Staedtenamen), statt die ganze Anzeige auszublenden. Alarmbalken und Fortschritt
	-- bleiben versteckt, da dort ohnehin kein Alert-System greift.
	if player:GetAttribute("CurrentZone") == "Sanctuary" then
		alertFrame.Visible = true
		cityNameLabel.Text = "Sanctuary"
		cityHourLabel.Text = "12:00"
		alertCaption.Visible = false
		for _, star in ipairs(starLabels) do
			star.Visible = false
		end
		currentStarCount = 0
		lastShownMaxLevel = nil
		lastShownLevel = nil
		return
	end

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

	alertCaption.Visible = true

	local level = math.max(levelValue.Value, 0)
	local config = CityAlertConfig.GetCityConfig(cityName)

	-- Die Hoechststufe kommt VOM SERVER, nicht aus dem Config: sie haengt am hoechsten
	-- Kapitel der Anwesenden (siehe CityAlertService, MaxAlertLevelByChapter), und im
	-- Config steht nur der Kapitel-I-Grundwert. Der Rueckfall auf das Config greift,
	-- solange der Wert noch nicht repliziert ist.
	local maxLevelValue = cityAlertValues:FindFirstChild(cityName .. "MaxLevel")
	local rawMaxLevel = (maxLevelValue and maxLevelValue.Value) or (config and config.MaxAlertLevel) or MAX_ALERT_LEVEL
	local maxLevel = math.clamp(rawMaxLevel, 0, MAX_ALERT_LEVEL)

	cityNameLabel.Text = CITY_DISPLAY_NAMES[cityName] or cityName
	cityHourLabel.Text = CITY_HOURS[cityName] or ""

	local farbe = alarmFarbe(math.max(level, 1), maxLevel)

	local starCount = math.clamp(level, 0, maxLevel)

	-- Neu aufbauen beim Staedtewechsel UND wenn sich die Obergrenze derselben Stadt
	-- aendert -- letzteres passiert, sobald ein Spieler eines hoeheren Kapitels die Stadt
	-- betritt oder verlaesst. Ohne die zweite Bedingung bliebe die Zahl der Sterne auf dem
	-- Stand des Kapitels, in dem man die Stadt betreten hat.
	if maxLevel ~= lastShownMaxLevel then
		lastShownMaxLevel = maxLevel
		for i = 1, MAX_ALERT_LEVEL do
			-- NUR so viele Sterne, wie diese Stadt Stufen hat. Ein Platzhalter fuer eine
			-- Stufe, die es hier nicht gibt, verspricht etwas, das nicht kommt.
			starLabels[i].Visible = i <= maxLevel
			starLabels[i].Rotation = 0
			starLabels[i].TextColor3 = i <= starCount and farbe or STERN_AUS
		end
		currentStarCount = starCount
	end

	if starCount > currentStarCount then
		animateNewStars(currentStarCount, starCount, farbe)
	elseif starCount < currentStarCount then
		for i = starCount + 1, currentStarCount do
			if starLabels[i] then
				starLabels[i].TextColor3 = STERN_AUS
			end
		end
	end
	-- Die bereits stehenden Sterne ziehen die Farbe der aktuellen Stufe nach: sie wandert
	-- mit jeder Eskalation weiter Richtung Gefahrfarbe.
	--
	-- Nur bei einem echten Stufenwechsel. Diese Funktion laeuft auch bei jeder Aenderung
	-- des Druckwerts, und der aendert sich im Kampf staendig -- ohne die Bedingung wuerde
	-- sie dem gerade einfliegenden Stern mitten in seinem Aufblitzen die Farbe wegnehmen.
	if lastShownLevel ~= level then
		for i = 1, math.min(starCount, MAX_ALERT_LEVEL) do
			if starLabels[i].Rotation == 0 then
				starLabels[i].TextColor3 = farbe
			end
		end
	end
	currentStarCount = starCount

	alertFrame.Visible = true

	-- Kurzes Aufleuchten bei einem ECHTEN Stufenwechsel (nicht bei jedem Durchlauf). Es
	-- laeuft ueber den Rahmen, nicht ueber die Groesse: ein Feld, das kurz waechst, schiebt
	-- alles darunter mit -- der Rahmen sagt dasselbe, ohne das Bild zu bewegen.
	if lastShownLevel and lastShownLevel ~= level and alertStroke then
		alertStroke.Color = farbe
		alertStroke.Thickness = 2
		TweenService:Create(alertStroke, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Color = HudChrome.Color.Border,
			Thickness = HudChrome.BorderThickness,
		}):Play()
	end
	lastShownLevel = level
end

player:GetAttributeChangedSignal("CurrentCityName"):Connect(updateAlertHud)
player:GetAttributeChangedSignal("CurrentZone"):Connect(updateAlertHud)

-- Nur noch auf die Stufen-Werte hoeren. Der Fortschrittswert aendert sich im Kampf
-- staendig; seit die Druckanzeige weg ist, zeigt die Anzeige davon nichts mehr, und jeder
-- dieser Aufrufe waere Arbeit ohne Wirkung.
--
-- Das Muster "Level$" erfasst auch "<Stadt>MaxLevel" (die kapitelabhaengige Obergrenze).
-- Das ist beabsichtigt und noetig: ohne dieses Abonnement bliebe die Zahl der Sterne
-- stehen, wenn ein Spieler eines hoeheren Kapitels die Stadt betritt. Wer das Muster
-- aendert, muss den Wert ausdruecklich mit aufnehmen.
for _, valueObject in ipairs(cityAlertValues:GetChildren()) do
	if valueObject.Name:match("Level$") then
		valueObject:GetPropertyChangedSignal("Value"):Connect(updateAlertHud)
	end
end

updateAlertHud() -- initialer Zustand beim Start

-- ===== Vorwarnung =====
--
-- Sie steht in der rechten Spalte, direkt unter dem Stadtfeld -- NICHT in der Bildmitte.
-- Die Mitte gehoert den Ereignissen (siehe HudCenterNotice); eine Warnung unterbricht
-- nicht, sie meldet sich. Deshalb dieselbe Anatomie wie die Welt-Event-Info unten rechts:
-- Symbol, Name, Unterzeile. Wer die eine lesen kann, kann auch die andere.
--
-- Sie sagt, DASS eine Eskalation naht und WELCHE Antwort sie bringt -- aber nicht, wann
-- genau. Die Spanne zwischen "sie erscheint" und "es passiert" bleibt unbestimmt.
--
-- Die Namen sind dieselben wie in der grossen Ankuendigung (CityAlertAnnouncementClient),
-- damit die Warnung und das, was dann kommt, erkennbar dasselbe meinen.
local ANTWORT_NAMEN = {
	[2] = "EMERGENCY RESPONSE",
	[3] = "SECURITY RESPONSE",
	[4] = "MILITARY RESPONSE",
	[5] = "MAXIMUM ALERT",
}

-- Kurzer Alarmton beim Einfahren.
local WARN_SOUND_ID = "rbxassetid://124157245478803"

local WARN_HOEHE = 66
local WARN_SYMBOL = 30

-- Sie faehrt von rechts herein, statt einfach da zu sein. Das Erscheinen IST die
-- Meldung -- ein Feld, das lautlos auftaucht, uebersieht man beim Kaempfen, weil der
-- Blick in der Bildmitte haengt. Eine Bewegung am Rand faengt ihn.
local WARN_Y = 118 + PANEL_HOEHE + 6
local WARN_RUHE_X = -16
local WARN_AUS_X = PANEL_BREITE + 40 -- so weit draussen, dass nichts hervorlugt
local WARN_AN = 0.80 -- ab hier erscheint sie
local WARN_AUS = 0.72 -- und verschwindet erst hier wieder: ohne diesen Abstand flackert
-- sie an der Schwelle, weil der Druckwert im Kampf staendig hin und her geht.

local warnFrame = Instance.new("Frame")
warnFrame.Name = "AlertWarningFrame"
warnFrame.Size = UDim2.new(0, PANEL_BREITE, 0, WARN_HOEHE)
warnFrame.AnchorPoint = Vector2.new(1, 0)
warnFrame.Position = UDim2.new(1, WARN_AUS_X, 0, WARN_Y)
warnFrame.Visible = false
warnFrame.ZIndex = 20
warnFrame.Parent = screenGui
local _, warnStroke = HudChrome.Panel(warnFrame, {
	radius = HudChrome.Radius.Small,
	fill = Color3.fromRGB(34, 26, 10),
	transparency = 0,
	border = HudChrome.Color.Warning,
})

local warnIcon = HudChrome.IconImage(warnFrame, HudChrome.Icon.Alert, HudChrome.Color.Warning)
warnIcon.Size = UDim2.new(0, WARN_SYMBOL, 0, WARN_SYMBOL)
warnIcon.Position = UDim2.new(0, PANEL_RAND, 0.5, -WARN_SYMBOL / 2)
warnIcon.ZIndex = 21

local WARN_TEXT_X = PANEL_RAND + WARN_SYMBOL + 10

local warnLabel = Instance.new("TextLabel")
warnLabel.Name = "WarningLabel"
warnLabel.Size = UDim2.new(0, PANEL_BREITE - WARN_TEXT_X - PANEL_RAND, 0, 24)
warnLabel.Position = UDim2.new(0, WARN_TEXT_X, 0, 10)
warnLabel.BackgroundTransparency = 1
warnLabel.TextXAlignment = Enum.TextXAlignment.Left
warnLabel.ZIndex = 21
warnLabel.Text = ""
warnLabel.Parent = warnFrame
HudChrome.Label(warnLabel, 19)
warnLabel.TextColor3 = HudChrome.Color.Warning

local warnSubLabel = Instance.new("TextLabel")
warnSubLabel.Name = "WarningSubLabel"
warnSubLabel.Size = UDim2.new(0, PANEL_BREITE - WARN_TEXT_X - PANEL_RAND, 0, 20)
warnSubLabel.Position = UDim2.new(0, WARN_TEXT_X, 0, 36)
warnSubLabel.BackgroundTransparency = 1
warnSubLabel.TextXAlignment = Enum.TextXAlignment.Left
warnSubLabel.ZIndex = 21
warnSubLabel.Text = ""
warnSubLabel.Parent = warnFrame
HudChrome.Number(warnSubLabel, 14)
warnSubLabel.TextColor3 = HudChrome.Color.TextSecondary

local warnSound = Instance.new("Sound")
warnSound.Name = "AlertWarningSound"
warnSound.SoundId = WARN_SOUND_ID
warnSound.Volume = 0.6
warnSound.Parent = screenGui

-- Ein laufender Uebergang wird beim naechsten abgebrochen. Ohne das ueberlagern sich Ein-
-- und Ausfahrt, wenn der Druckwert nahe der Schwelle pendelt.
local warnTween = nil

local function zeigeWarnung(sichtbar)
	if warnTween then
		warnTween:Cancel()
	end

	if sichtbar then
		warnFrame.Position = UDim2.new(1, WARN_AUS_X, 0, WARN_Y)
		warnFrame.Visible = true
		warnTween = TweenService:Create(
			warnFrame,
			TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(1, WARN_RUHE_X, 0, WARN_Y) }
		)
		warnTween:Play()

		if warnSound.SoundId ~= "" and warnSound.SoundId ~= "rbxassetid://0" then
			warnSound.TimePosition = 0
			warnSound:Play()
		end
		return
	end

	warnTween = TweenService:Create(
		warnFrame,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(1, WARN_AUS_X, 0, WARN_Y) }
	)
	-- Erst ausblenden, wenn sie WIRKLICH draussen ist. Cancel meldet sich auf demselben
	-- Ereignis -- ohne die Zustandspruefung wuerde eine abgebrochene Ausfahrt das gerade
	-- eingefahrene Feld sofort wieder verstecken.
	warnTween.Completed:Connect(function(zustand)
		if zustand == Enum.PlaybackState.Completed then
			warnFrame.Visible = false
		end
	end)
	warnTween:Play()
end

-- Die Liste rueckt nach, wenn die Warnung da ist -- sonst laege sie darunter begraben.
local function listenY()
	return 118 + PANEL_HOEHE + 8 + (warnFrame.Visible and (WARN_HOEHE + 6) or 0)
end

local function updateWarnung()
	local cityName = player:GetAttribute("CurrentCityName")
	local zone = player:GetAttribute("CurrentZone")
	if not cityName or cityName == "None" or zone == "Sanctuary" then
		if warnFrame.Visible then
			zeigeWarnung(false)
		end
		return
	end

	local levelValue = cityAlertValues:FindFirstChild(cityName .. "Level")
	local progressValue = cityAlertValues:FindFirstChild(cityName .. "Progress")
	local config = CityAlertConfig.GetCityConfig(cityName)
	if not levelValue or not progressValue or not config then
		if warnFrame.Visible then
			zeigeWarnung(false)
		end
		return
	end

	local maxLevelValue = cityAlertValues:FindFirstChild(cityName .. "MaxLevel")
	local rawMaxLevel = (maxLevelValue and maxLevelValue.Value) or config.MaxAlertLevel or MAX_ALERT_LEVEL
	local maxLevel = math.clamp(rawMaxLevel, 0, MAX_ALERT_LEVEL)
	local level = math.max(levelValue.Value, 0)

	-- Auf der Hoechststufe dieser Stadt kommt nichts mehr -- dann gibt es auch nichts
	-- anzukuendigen.
	if level >= maxLevel then
		if warnFrame.Visible then
			zeigeWarnung(false)
		end
		return
	end

	local schwelle = config.AlertThresholdLevel2
	if not schwelle or schwelle <= 0 then
		if warnFrame.Visible then
			zeigeWarnung(false)
		end
		return
	end
	local ratio = math.clamp(progressValue.Value / schwelle, 0, 1)

	local warSichtbar = warnFrame.Visible
	local sichtbar
	if warSichtbar then
		sichtbar = ratio >= WARN_AUS
	else
		sichtbar = ratio >= WARN_AN
	end

	if sichtbar then
		local naechste = math.min(level + 1, maxLevel)
		warnLabel.Text = ANTWORT_NAMEN[naechste] or "ALERT"
		warnSubLabel.Text = "ALERT LEVEL " .. naechste .. " INBOUND"
	end

	-- Nur beim WECHSEL faehrt sie -- die Funktion laeuft bei jeder Aenderung des
	-- Druckwerts, und der aendert sich im Kampf staendig.
	if sichtbar ~= warSichtbar then
		zeigeWarnung(sichtbar)
	end
end

player:GetAttributeChangedSignal("CurrentCityName"):Connect(updateWarnung)
player:GetAttributeChangedSignal("CurrentZone"):Connect(updateWarnung)

-- Hier wird der Fortschrittswert wieder gebraucht -- aber nur noch fuer diese eine Frage:
-- ist die Schwelle nah? Was er genau sagt, erfaehrt der Spieler nicht mehr.
for _, valueObject in ipairs(cityAlertValues:GetChildren()) do
	if valueObject.Name:match("Progress$") or valueObject.Name:match("Level$") then
		valueObject:GetPropertyChangedSignal("Value"):Connect(updateWarnung)
	end
end

updateWarnung()

-- Das Pulsieren laeuft nur, solange die Warnung steht. Ein Rahmen, der ruhig daliegt,
-- waere eine Feststellung; einer, der atmet, ist eine Warnung.
RunService.Heartbeat:Connect(function()
	if not warnFrame.Visible then
		return
	end
	local puls = (math.sin(os.clock() * 4) + 1) / 2
	warnStroke.Transparency = 0.15 + puls * 0.45
	warnIcon.ImageTransparency = puls * 0.35
end)

-- ===== Aufgabenliste =====
--
-- Zeigt pro Stadt die anwendbaren Aufgaben (Emergency/Defense/Military/Titan Protocol).
-- Sobald alle erledigt sind (siehe CityBrokenService.lua), bricht die Stadt -- eigener
-- Banner mit Countdown.
--
-- Die Emoji-Symbole sind weg. Fuer zwei der vier Aufgaben gibt es ein hochgeladenes
-- Symbol und fuer zwei nicht -- eine halb bebilderte Liste sieht nach Versehen aus. Den
-- Zustand traegt jetzt ein Kaestchen am Zeilenanfang: leer mit Rahmen heisst offen,
-- gefuellt heisst erledigt. Das ist ohnehin die einzige Frage an so eine Liste.
local TASK_LIST = {
	{ id = "Emergency", label = "Emergency Response" },
	{ id = "Defense", label = "Defense Barricades" },
	{ id = "Military", label = "Military" },
	{ id = "Titan", label = "Guardian" },
}

local ERLEDIGT_FARBE = Color3.fromRGB(70, 220, 90)

local questFrame = Instance.new("Frame")
questFrame.Name = "CityQuestFrame"
questFrame.AnchorPoint = Vector2.new(1, 0)
questFrame.Position = UDim2.new(1, -16, 0, listenY())
questFrame.Size = UDim2.new(0, PANEL_BREITE, 0, 0)
questFrame.AutomaticSize = Enum.AutomaticSize.Y
questFrame.Visible = false
questFrame.ZIndex = 20
questFrame.Parent = screenGui
HudChrome.Panel(questFrame, { radius = HudChrome.Radius.Small })

local questPadding = Instance.new("UIPadding")
questPadding.PaddingLeft = UDim.new(0, PANEL_RAND)
questPadding.PaddingRight = UDim.new(0, PANEL_RAND)
questPadding.PaddingTop = UDim.new(0, 8)
questPadding.PaddingBottom = UDim.new(0, 8)
questPadding.Parent = questFrame

local questListLayout = Instance.new("UIListLayout")
questListLayout.Padding = UDim.new(0, 4)
questListLayout.SortOrder = Enum.SortOrder.LayoutOrder
questListLayout.Parent = questFrame

local questHeader = Instance.new("TextLabel")
questHeader.Name = "QuestHeader"
questHeader.Size = UDim2.new(1, 0, 0, 18)
questHeader.BackgroundTransparency = 1
questHeader.TextXAlignment = Enum.TextXAlignment.Left
questHeader.LayoutOrder = 0
questHeader.ZIndex = 21
questHeader.Text = "OBJECTIVES"
questHeader.Parent = questFrame
HudChrome.Label(questHeader, 14)
questHeader.TextColor3 = HudChrome.Color.TextSecondary

local questRows = {} -- [taskId] = { row=, box=, boxStroke=, textLabel= }
for index, task in ipairs(TASK_LIST) do
	local row = Instance.new("Frame")
	row.Name = task.id .. "Row"
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.LayoutOrder = index
	row.ZIndex = 21
	row.Parent = questFrame

	local box = Instance.new("Frame")
	box.Name = "StatusBox"
	box.Size = UDim2.new(0, 12, 0, 12)
	box.Position = UDim2.new(0, 0, 0.5, -6)
	box.BackgroundColor3 = HudChrome.Color.PanelSunken
	box.BorderSizePixel = 0
	box.ZIndex = 22
	box.Parent = row

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 2)
	boxCorner.Parent = box

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Thickness = HudChrome.BorderThickness
	boxStroke.Color = HudChrome.Color.BorderDim
	boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	boxStroke.Parent = box

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.Size = UDim2.new(1, -22, 1, 0)
	textLabel.Position = UDim2.new(0, 22, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.ZIndex = 22
	textLabel.Text = task.label
	textLabel.Parent = row
	HudChrome.Number(textLabel, 15)
	textLabel.TextColor3 = HudChrome.Color.TextSecondary

	questRows[task.id] = { row = row, box = box, boxStroke = boxStroke, textLabel = textLabel }
end

-- ===== CITY BROKEN =====
local cityBrokenBanner = Instance.new("Frame")
cityBrokenBanner.Name = "CityBrokenBanner"
cityBrokenBanner.AnchorPoint = Vector2.new(1, 0)
cityBrokenBanner.Position = UDim2.new(1, -16, 0, listenY())
cityBrokenBanner.Size = UDim2.new(0, PANEL_BREITE, 0, 62)
cityBrokenBanner.Visible = false
cityBrokenBanner.ZIndex = 21
cityBrokenBanner.Parent = screenGui
HudChrome.Panel(cityBrokenBanner, {
	radius = HudChrome.Radius.Small,
	fill = Color3.fromRGB(38, 14, 12),
	transparency = 0,
	border = HudChrome.Color.Danger,
	thickness = 2,
})

local cityBrokenTitle = Instance.new("TextLabel")
cityBrokenTitle.Name = "Title"
cityBrokenTitle.Size = UDim2.new(1, -20, 0, 26)
cityBrokenTitle.Position = UDim2.new(0, PANEL_RAND, 0, 8)
cityBrokenTitle.BackgroundTransparency = 1
cityBrokenTitle.TextXAlignment = Enum.TextXAlignment.Left
cityBrokenTitle.ZIndex = 22
cityBrokenTitle.Text = "CITY BROKEN"
cityBrokenTitle.Parent = cityBrokenBanner
HudChrome.Label(cityBrokenTitle, 24)
cityBrokenTitle.TextColor3 = HudChrome.Color.Ready

local cityBrokenSubtitle = Instance.new("TextLabel")
cityBrokenSubtitle.Name = "Subtitle"
cityBrokenSubtitle.Size = UDim2.new(1, -20, 0, 20)
cityBrokenSubtitle.Position = UDim2.new(0, PANEL_RAND, 0, 36)
cityBrokenSubtitle.BackgroundTransparency = 1
cityBrokenSubtitle.TextXAlignment = Enum.TextXAlignment.Left
cityBrokenSubtitle.ZIndex = 22
cityBrokenSubtitle.Text = "FREE DESTRUCTION 75s"
cityBrokenSubtitle.Parent = cityBrokenBanner
HudChrome.Number(cityBrokenSubtitle, 16)
cityBrokenSubtitle.TextColor3 = HudChrome.Color.TextSecondary

local function updateQuestList()
	-- Die Warnung kann jederzeit erscheinen oder gehen; beide Felder darunter folgen ihr.
	local y = listenY()
	questFrame.Position = UDim2.new(1, -16, 0, y)
	cityBrokenBanner.Position = UDim2.new(1, -16, 0, y)

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
		cityBrokenSubtitle.Text = "FREE DESTRUCTION " .. remaining .. "s"
		return
	end

	cityBrokenBanner.Visible = false

	-- Nur Aufgaben zeigen, die diese Stadt bereits TATSAECHLICH erreicht hat --
	-- "applicable" bedeutet schon genau das (serverseitig dynamisch berechnet, siehe
	-- CityBrokenService.lua), keine zusaetzliche Stufenpruefung hier noetig.
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

			rowInfo.box.BackgroundColor3 = isComplete and ERLEDIGT_FARBE or HudChrome.Color.PanelSunken
			rowInfo.boxStroke.Color = isComplete and ERLEDIGT_FARBE or HudChrome.Color.BorderDim
			-- Erledigtes tritt zurueck: es ist noch da, damit man den Fortschritt sieht,
			-- aber es braucht keine Aufmerksamkeit mehr. Die offene Zeile ist die, die
			-- etwas von einem will.
			rowInfo.textLabel.TextColor3 = isComplete and HudChrome.Color.TextDim or HudChrome.Color.TextPrimary

			-- Fortschritts-Anzeige ("1/2") anhaengen, sofern der Server einen liefert
			-- (die Guardian-Aufgabe hat keinen -- einzelner Gegner).
			local progressValue = cityAlertValues:FindFirstChild(cityName .. "Task_" .. task.id .. "_Progress")
			local progressText = progressValue and progressValue.Value or ""
			if progressText ~= "" then
				rowInfo.textLabel.Text = task.label .. "  " .. progressText
			else
				rowInfo.textLabel.Text = task.label
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
-- Ankuendigung in die Ecke geflogen ist -- zusaetzlicher Leuchteffekt, um den Blick genau
-- hierhin zu lenken.
--
-- Der Effekt laeuft ueber den VORHANDENEN Rahmen. Ein zweiter UIStroke am selben Objekt
-- waere die naheliegende Loesung gewesen, aber Roblox zeichnet pro Objekt nur einen --
-- der neue haette den bestehenden ersetzt und ihn nach dem Ausblenden mitgenommen.
_G.FlashCityAlertIndicator = function(color)
	if not alertStroke then
		return
	end
	alertStroke.Color = color or HudChrome.Color.Ready
	alertStroke.Thickness = 3
	TweenService:Create(alertStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
		Color = HudChrome.Color.Border,
		Thickness = HudChrome.BorderThickness,
	}):Play()
end

-- Laesst die kompakte Anzeige kurz zittern -- Trigger-Moment (0.0s) der "ALERT
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

-- Laesst einen bestimmten Stern (1-basiert) kurz zweimal pulsieren -- Trigger-Moment
-- (0.0s) der "ALERT ESCALATION"-Sequenz in CityAlertAnnouncementClient.lua.
_G.PulseCityAlertStar = function(starIndex)
	local star = starLabels[starIndex]
	if not star or not star.Visible then
		return
	end
	task.spawn(function()
		for _ = 1, 2 do
			local hoch = TweenService:Create(star, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
				Size = UDim2.new(0, STERN_GROESSE + 6, 0, STERN_GROESSE + 6),
			})
			hoch:Play()
			hoch.Completed:Wait()
			local runter = TweenService:Create(star, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
				Size = UDim2.new(0, STERN_GROESSE, 0, STERN_GROESSE),
			})
			runter:Play()
			runter.Completed:Wait()
		end
	end)
end
