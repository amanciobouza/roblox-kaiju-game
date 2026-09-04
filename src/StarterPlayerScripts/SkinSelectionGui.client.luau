-- VERSION: 2026-08-26 #3
-- FEATURE: ForceCloseShopEvent ergaenzt -- schliesst den Shop zwangsweise
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut: Level + Fortschrittsbalken (oben Mitte), Coins-Anzeige (oben links),
-- "Skin kaufen"-Button darunter mit Skin-Shop-Menü. Alles im knalligen Comic-Look:
-- dicke schwarze Outlines, runde Ecken, große verspielte Schrift.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local ModelPreviewUtils = require(ReplicatedStorage:WaitForChild("ModelPreviewUtils"))
local UiTypography = require(ReplicatedStorage:WaitForChild("UiTypography"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
local applyComicStyle = ComicStyleUtils.Apply
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))

-- Icon + Farbe pro Energie-Typ für die fliegende Zahl-Animation -- dieselben Farben wie
-- im Talentbaum/HUD (TalentTreeClient.lua, EnergyTypesClient.lua), konsistent im ganzen Spiel.
local ENERGY_TYPE_VISUALS = {
	Heat = { icon = "🔥", color = Color3.fromRGB(255, 140, 30) },
	Chemical = { icon = "🧪", color = Color3.fromRGB(255, 45, 190) },
	Electric = { icon = "⚡", color = Color3.fromRGB(57, 217, 255) },
	Radiation = { icon = "☢️", color = Color3.fromRGB(126, 255, 16) },
	Spirit = { icon = "✨", color = Color3.fromRGB(255, 205, 70) },
}
local DEFAULT_ENERGY_VISUAL = { icon = "⚡", color = Color3.fromRGB(255, 140, 40) }

-- Für die Kraft-Werte (Bein/Arm/Körper): bei kleinen Zahlen (<1000, der übliche Bereich)
-- zwei Nachkommastellen zeigen (z.B. "0.27"), da das Training jetzt SEHR fein variiert
-- (100x verlangsamt -> viele kleine Schritte). Bei großen Zahlen bleibt die k/M-Kurzform
-- von NumberFormat sinnvoller (Dezimalstellen wären da ohnehin nicht mehr relevant).
local function formatStatValue(value)
	if value < 1000 then
		local text = string.format("%.2f", value)
		text = text:gsub("0$", ""):gsub("%.$", "") -- "4.00" -> "4", "3.70" -> "3.7", "3.27" bleibt "3.27"
		return text
	end
	return NumberFormat.Format(value)
end
local SkinsConfig = require(ReplicatedStorage:WaitForChild("SkinsConfig"))
local PurchaseSkinEvent = RemoteEventUtils.GetOrCreate("PurchaseSkinEvent")
-- Das Anlegen eines bereits besessenen Skins. Der Server hat den Handler seit jeher, aber
-- kein Client hat ihn je gefeuert -- bisher kaufte und ruestete PurchaseSkinEvent in einem
-- Zug aus. Mit dem Steckbrief sind das zwei getrennte Handlungen.
local EquipSkinEvent = RemoteEventUtils.GetOrCreate("EquipSkinEvent")
local CoinsEarnedEvent = RemoteEventUtils.GetOrCreate("CoinsEarnedEvent")
local EnergyAbsorbEvent = RemoteEventUtils.GetOrCreate("EnergyAbsorbEvent")
local StopTrainingEvent = RemoteEventUtils.GetOrCreate("StopTrainingEvent")
local TrainPointEvent = RemoteEventUtils.GetOrCreate("TrainPointEvent")
local statCapPerLevelValue = ReplicatedStorage:WaitForChild("StatCapPerLevel")
local boostDurationValue = ReplicatedStorage:WaitForChild("BoostDuration")

-- WICHTIG: Trag hier deine eigene Sound-ID aus dem Creator Store ein (Format: "rbxassetid://12345678")
local TRAIN_POINT_SOUND_ID = "rbxassetid://86850632846358"

local trainPointSound = Instance.new("Sound")
trainPointSound.Name = "TrainPointSound"
trainPointSound.SoundId = TRAIN_POINT_SOUND_ID
trainPointSound.Volume = 0.6
trainPointSound.Parent = SoundService

-- WICHTIG: Trag hier deine eigene Sound-ID aus dem Creator Store ein (Format: "rbxassetid://12345678")
local CASH_SOUND_ID = "rbxassetid://135483737426662"

local cashSound = Instance.new("Sound")
cashSound.Name = "CashSound"
cashSound.SoundId = CASH_SOUND_ID
cashSound.Volume = 0.8
cashSound.Parent = SoundService

-- WICHTIG: Trag hier deine eigene Sound-ID aus dem Creator Store ein
local ENERGY_ARRIVE_SOUND_ID = "rbxassetid://0"

local energyArriveSound = Instance.new("Sound")
energyArriveSound.Name = "EnergyArriveSound"
energyArriveSound.SoundId = ENERGY_ARRIVE_SOUND_ID
energyArriveSound.Volume = 0.7
energyArriveSound.Parent = SoundService

-- Solange eine Münz-Flug-Animation läuft, soll der normale Coins-Changed-Handler
-- den Zähler NICHT sofort überschreiben (sonst springt die Zahl vor der Animation hoch).
local isAnimatingCoins = false

-- ===== Comic-Style Hilfsfunktion =====
-- (jetzt über ComicStyleUtils, siehe oben -- war hier zuvor dupliziert)

-- Lässt ein GUI-Element kurz hell aufblitzen (Hintergrundfarbe -> heller Blitz -> zurück
-- zur Originalfarbe) -- z.B. bei Level-Aufstieg oder Coins-Zuwachs, als kurzes visuelles
-- Feedback "hier hat sich gerade was erhöht".
local function flashElement(guiObject, flashColor)
	flashColor = flashColor or Color3.new(1, 1, 1)

	-- Die ECHTE Ursprungsfarbe/-transparenz nur EINMALIG sichern (als Attribut) --
	-- bei schnell aufeinanderfolgenden Aufrufen (z.B. während des Boosts) würde sonst
	-- jeder neue Aufruf die aktuelle, evtl. noch mitten im Übergang befindliche Farbe als
	-- "Original" übernehmen, wodurch die Farbe über mehrere Klicks hinweg Richtung Weiß
	-- driften und dort hängen bleiben könnte.
	if guiObject:GetAttribute("RestColor") == nil then
		guiObject:SetAttribute("RestColor", guiObject.BackgroundColor3)
		guiObject:SetAttribute("RestTransparency", guiObject.BackgroundTransparency)
	end
	local originalColor = guiObject:GetAttribute("RestColor")
	local originalTransparency = guiObject:GetAttribute("RestTransparency")

	-- Beim Aufblitzen NIE durchsichtiger machen als es ohnehin schon ist -- nur für
	-- normalerweise unsichtbare Elemente (z.B. der transparente Level-Rahmen) kurz auf
	-- 0.3 einblenden. Bereits voll sichtbare Elemente (z.B. die Balken, Transparency 0)
	-- bleiben bei ihrer eigenen (helleren) Transparenz -- sonst würde der "Blitz" sie
	-- unsichtbarer statt heller machen.
	local flashTransparency = math.min(originalTransparency, 0.3)

	local flashUp = TweenService:Create(guiObject, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = flashColor,
		BackgroundTransparency = flashTransparency,
	})
	flashUp.Completed:Connect(function()
		TweenService:Create(guiObject, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundColor3 = originalColor,
			BackgroundTransparency = originalTransparency,
		}):Play()
	end)
	flashUp:Play()
end

-- Echter LEUCHT-Effekt (nicht nur Farbwechsel): legt einen hellen, nach außen wachsenden
-- und verblassenden Rand um das Element -- simuliert ein kurzes "Überstrahlen"/Glühen,
-- da Roblox-UI kein echtes Bloom kennt.
local function glowFlashElement(guiObject, glowColor)
	glowColor = glowColor or Color3.fromRGB(255, 255, 200)

	local glowStroke = Instance.new("UIStroke")
	glowStroke.Name = "GlowFlash"
	glowStroke.Thickness = 0
	glowStroke.Color = glowColor
	glowStroke.Transparency = 0
	glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glowStroke.Parent = guiObject

	local growTween = TweenService:Create(
		glowStroke,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Thickness = 6 }
	)
	growTween.Completed:Connect(function()
		local fadeTween = TweenService:Create(
			glowStroke,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Thickness = 0, Transparency = 1 }
		)
		fadeTween.Completed:Connect(function()
			glowStroke:Destroy()
		end)
		fadeTween:Play()
	end)
	growTween:Play()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== Coins-Anzeige: oben rechts, klein (neue HUD-Spezifikation -- Geld ist
-- sekundäre Information, keine grosse gelbe Fläche mehr) =====
local coinsLabel = Instance.new("TextLabel")
coinsLabel.Name = "CoinsLabel"
coinsLabel.Size = UDim2.new(0, 92, 0, 30)
coinsLabel.AnchorPoint = Vector2.new(1, 0)
coinsLabel.Position = UDim2.new(1, -68, 0, 20)
coinsLabel.BackgroundColor3 = Color3.fromRGB(40, 35, 20)
coinsLabel.TextColor3 = Color3.fromRGB(255, 205, 60)
coinsLabel.Font = Enum.Font.FredokaOne
coinsLabel.TextScaled = true
coinsLabel.Text = "💰 0"
coinsLabel.Parent = screenGui
applyComicStyle(coinsLabel, 8, 2)

-- ===== Player-Status-Cluster: Health + Level + XP als EIN kompakter Block, oben Mitte
-- (neue HUD-Spezifikation) -- vorher zwei separate, deutlich grössere Frames (142px
-- Gesamthöhe), jetzt ein einziger, ~78px hoher Cluster. Priorität: Health > Level > XP.
local statusCluster = Instance.new("Frame")
statusCluster.Name = "PlayerStatusCluster"
statusCluster.Size = UDim2.new(0, 320, 0, 78)
statusCluster.AnchorPoint = Vector2.new(0.5, 0)
statusCluster.Position = UDim2.new(0.5, 0, 0, 8)
statusCluster.BackgroundTransparency = 1
statusCluster.Parent = screenGui

-- Level: klein, kompakt, ÜBER der Health-Bar (nicht mehr eigene grosse Fläche)
local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelLabel"
levelLabel.Size = UDim2.new(1, 0, 0, 18)
levelLabel.Position = UDim2.new(0, 0, 0, 0)
levelLabel.BackgroundTransparency = 1
levelLabel.TextColor3 = Color3.new(1, 1, 1)
levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
levelLabel.TextStrokeTransparency = 0.4
levelLabel.Font = Enum.Font.LuckiestGuy
levelLabel.TextScaled = true
levelLabel.Text = "⭐ Level 0"
levelLabel.Parent = statusCluster

-- Health-Bar: 22px hoch, "100/100"-Text direkt IN der Bar (spart eigene Zeile)
local healthFrame = Instance.new("Frame")
healthFrame.Name = "HealthFrame"
healthFrame.Size = UDim2.new(1, 0, 0, 22)
healthFrame.Position = UDim2.new(0, 0, 0, 22)
healthFrame.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
healthFrame.Parent = statusCluster
applyComicStyle(healthFrame, 8, 2)

local healthBarFill = Instance.new("Frame")
healthBarFill.Name = "Fill"
healthBarFill.Size = UDim2.new(1, 0, 1, 0)
healthBarFill.BackgroundColor3 = Color3.fromRGB(70, 220, 90)
healthBarFill.BorderSizePixel = 0
healthBarFill.Parent = healthFrame
applyComicStyle(healthBarFill, 6, 0)

local healthLabel = Instance.new("TextLabel")
healthLabel.Name = "HealthLabel"
healthLabel.Size = UDim2.new(1, 0, 1, 0)
healthLabel.BackgroundTransparency = 1
healthLabel.Font = Enum.Font.FredokaOne
healthLabel.TextScaled = true
healthLabel.TextColor3 = Color3.new(1, 1, 1)
healthLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
healthLabel.TextStrokeTransparency = 0.4
healthLabel.ZIndex = 2
healthLabel.Text = "❤️ 100 / 100"
healthLabel.Parent = healthFrame

local function updateHealthBar()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	healthBarFill.Size = UDim2.new(ratio, 0, 1, 0)
	healthLabel.Text = "❤️ " .. math.floor(humanoid.Health) .. " / " .. math.floor(humanoid.MaxHealth)

	-- Farbverlauf grün -> gelb -> rot, je niedriger desto dramatischer
	if ratio > 0.5 then
		healthBarFill.BackgroundColor3 = Color3.fromRGB(70, 220, 90)
	elseif ratio > 0.25 then
		healthBarFill.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
	else
		healthBarFill.BackgroundColor3 = Color3.fromRGB(230, 60, 50)
	end
end

-- Lebensanzeige in der Sanctuary-Zone ausblenden -- dort ist ohnehin kein Kampf/Schaden
-- möglich (analog zu den Angriffs-Buttons in SpecialAttackClient.lua). Blendet jetzt den
-- GESAMTEN Cluster aus (Health+Level+XP gehören zusammen), nicht mehr nur Health separat.
local function updateHealthFrameVisibility()
	local zone = player:GetAttribute("CurrentZone")
	statusCluster.Visible = zone ~= "Sanctuary"
end
updateHealthFrameVisibility()
player:GetAttributeChangedSignal("CurrentZone"):Connect(updateHealthFrameVisibility)

local function connectHealthBar(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	updateHealthBar()
	humanoid:GetPropertyChangedSignal("Health"):Connect(updateHealthBar)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealthBar)
end

player.CharacterAdded:Connect(connectHealthBar)
if player.Character then
	connectHealthBar(player.Character)
end

-- XP-Bar: nur noch 8px hoch (dünner Streifen unter der Health-Bar), kein eigener
-- Hintergrund-Rahmen mehr -- soll im Kampf nicht mit Health konkurrieren.
local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.Size = UDim2.new(1, 0, 0, 8)
barBackground.Position = UDim2.new(0, 0, 0, 48)
barBackground.BackgroundColor3 = Color3.fromRGB(30, 60, 100)
barBackground.Parent = statusCluster
applyComicStyle(barBackground, 4, 1)

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
barFill.BorderSizePixel = 0
barFill.ZIndex = 2
barFill.Parent = barBackground
applyComicStyle(barFill, 3, 0)

-- ===== Heat/Berserker-Leiste -- VERTIKAL, unten zentriert zwischen den Angriffs-Buttons
-- (Standardangriffe links, Spezialangriffe rechts) -- gleicher Kampf-Kontext, gleiche
-- Bildschirmzeile. Aktiviert Berserk automatisch (siehe HeatHandler.lua). =====
local MeltdownExplosionEvent = RemoteEventUtils.GetOrCreate("MeltdownExplosionEvent")

local heatFrame = Instance.new("Frame")
heatFrame.Name = "HeatFrame"
heatFrame.Size = UDim2.new(0, 280, 0, 200) -- doppelt so gross wie zuvor
heatFrame.AnchorPoint = Vector2.new(0.5, 1)
heatFrame.Position = UDim2.new(0.5, 0, 1, -24) -- EXAKT dieselbe Grundlinie wie die Angriffs-Buttons
heatFrame.BackgroundTransparency = 1 -- kein rechteckiger Rahmen mehr -- nur die Halbscheibe (siehe unten) ist sichtbar
heatFrame.ZIndex = 10
heatFrame.Parent = screenGui

-- Titel oben -- macht auf den ersten Blick klar, worum es sich handelt.
local heatTitleLabel = Instance.new("TextLabel")
heatTitleLabel.Name = "HeatTitleLabel"
heatTitleLabel.Size = UDim2.new(1, -12, 0, 26)
heatTitleLabel.Position = UDim2.new(0, 6, 0, 0)
heatTitleLabel.BackgroundTransparency = 1
heatTitleLabel.Font = Enum.Font.LuckiestGuy
heatTitleLabel.TextScaled = true
heatTitleLabel.TextColor3 = Color3.fromRGB(255, 210, 80)
heatTitleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
heatTitleLabel.TextStrokeTransparency = 0
heatTitleLabel.ZIndex = 12
heatTitleLabel.Text = "BERSERKER"
heatTitleLabel.Parent = heatFrame

-- Bonus-Text direkt unter dem Titel (der Drehpunkt unten braucht den Platz fürs Zifferblatt).
local heatBonusLabel = Instance.new("TextLabel")
heatBonusLabel.Name = "HeatBonusLabel"
heatBonusLabel.Size = UDim2.new(1, -8, 0, 26)
heatBonusLabel.Position = UDim2.new(0, 4, 0, 26)
heatBonusLabel.BackgroundTransparency = 1
heatBonusLabel.Font = Enum.Font.FredokaOne
heatBonusLabel.TextScaled = true
heatBonusLabel.TextWrapped = true
heatBonusLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
heatBonusLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
heatBonusLabel.TextStrokeTransparency = 0.3
heatBonusLabel.ZIndex = 12
heatBonusLabel.Text = "No Bonus"
heatBonusLabel.Parent = heatFrame

-- ===== Tacho-Anzeige: farbig gefülltes Zifferblatt (Sektoren statt dünner schwarzer
-- Fläche) + Nadel, die WIRKLICH nur am unteren Ansatz fixiert ist. =====
-- WICHTIG: Roblox rotiert ein GuiObject immer um seinen EIGENEN Mittelpunkt, NICHT um
-- den AnchorPoint. Ein direkt rotiertes, langes Objekt würde sich deshalb wie eine
-- Kompassnadel um seine MITTE drehen (beide Enden bewegen sich). Der korrekte Trick:
-- ein winziger, unsichtbarer "Dreh-Anker" sitzt GENAU auf dem Drehpunkt, und die Nadel
-- ist ein KIND davon, das vom Anker aus nach oben ragt -- rotiert wird NUR der Anker,
-- die Nadel "erbt" die Drehung um genau diesen fixen Punkt.
local GAUGE_RADIUS = 92
local GAUGE_CENTER = Vector2.new(140, 200) -- Drehpunkt = EXAKT die Unterkante von heatFrame = Button-Grundlinie
local DISC_RADIUS = GAUGE_RADIUS + 24

-- ===== Halbscheibe als Hintergrund (echte Geigenzähler-Optik) =====
-- Roblox kennt keine native Halbkreis-Form -- daher: ein VOLLER Kreis (per UICorner mit
-- halbem Radius) wird in einem nur HALB so hohen Container mit ClipsDescendants=true
-- platziert. Der Container zeigt dadurch nur die obere Hälfte des Kreises.
local discClip = Instance.new("Frame")
discClip.Name = "GaugeDiscClip"
discClip.AnchorPoint = Vector2.new(0.5, 1)
discClip.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
discClip.Size = UDim2.new(0, DISC_RADIUS * 2, 0, DISC_RADIUS)
discClip.BackgroundTransparency = 1
discClip.ClipsDescendants = true
discClip.ZIndex = 7
discClip.Parent = heatFrame

local gaugeDisc = Instance.new("Frame")
gaugeDisc.Name = "GaugeDisc"
gaugeDisc.AnchorPoint = Vector2.new(0.5, 0.5)
gaugeDisc.Position = UDim2.new(0.5, 0, 1, 0) -- Kreismitte exakt auf der Unterkante des Clip-Containers (= Drehpunkt)
gaugeDisc.Size = UDim2.new(0, DISC_RADIUS * 2, 0, DISC_RADIUS * 2)
gaugeDisc.BackgroundColor3 = Color3.fromRGB(24, 22, 30)
gaugeDisc.BorderSizePixel = 0
gaugeDisc.ZIndex = 7
gaugeDisc.Parent = discClip

local gaugeDiscCorner = Instance.new("UICorner")
gaugeDiscCorner.CornerRadius = UDim.new(0.5, 0) -- bei gleicher Breite/Höhe ergibt das einen perfekten Kreis
gaugeDiscCorner.Parent = gaugeDisc

-- Goldener Rand um die Scheibe (gaugeDiscStroke) wurde entfernt -- störte visuell,
-- besonders zusammen mit dem neuen Special-Energy-Arc direkt aussen herum.

-- Sektor-Füllung: viele schmale, DURCHGEHENDE Keile vom Drehpunkt bis fast zum Rand
-- (nicht nur kurze Striche am Rand) -- dicht genug aneinandergereiht, dass sie wie eine
-- durchgehende Farbfläche wirken. Jeder Keil nutzt denselben Dreh-Anker-Trick wie die
-- Nadel (siehe oben), damit er wirklich am Drehpunkt ansetzt statt um die eigene Mitte
-- zu kippen.
-- Skala jetzt 0-110 (war 0-100) -- Zifferblatt zeigt mehr Headroom über Meltdown
-- hinaus. "percent" entspricht direkt dem echten Heat-Wert.
local GAUGE_MAX = 110
local SECTOR_COUNT = 90 -- sehr dicht, wirkt wie eine durchgehende Fläche statt einzelner Striche
local sectorWedges = {}
for i = 0, SECTOR_COUNT - 1 do
	local percent = (i / (SECTOR_COUNT - 1)) * GAUGE_MAX
	local angle = -90 + (percent / GAUGE_MAX) * 180

	local pivot = Instance.new("Frame")
	pivot.Name = "SectorPivot" .. i
	pivot.AnchorPoint = Vector2.new(0.5, 0.5)
	pivot.Size = UDim2.new(0, 1, 0, 1)
	pivot.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
	pivot.Rotation = angle
	pivot.BackgroundTransparency = 1
	pivot.ZIndex = 8
	pivot.Parent = heatFrame

	local wedge = Instance.new("Frame")
	wedge.Name = "Wedge"
	wedge.AnchorPoint = Vector2.new(0.5, 1)
	wedge.Size = UDim2.new(0, 10, 0, GAUGE_RADIUS - 8) -- reicht fast bis zum Rand, nicht nur ein kurzer Strich
	wedge.Position = UDim2.new(0.5, 0, 0, 0)
	wedge.BorderSizePixel = 0
	wedge.ZIndex = 8
	wedge.Parent = pivot

	-- Farbe wird NICHT mehr hier einmalig gesetzt, sondern laufend im Heartbeat-Loop
	-- (siehe unten) -- die Berserker/Meltdown-Grenze hängt vom talent-abhängigen
	-- EffectiveMeltdownThreshold-Attribut ab, das sich während des Spiels ändern kann.

	table.insert(sectorWedges, { frame = wedge, percent = percent })
end

-- Kleine Symbole über den beiden Sonder-Sektoren als zusätzliche, unmissverständliche
-- Markierung (nicht nur Farbe).
local function addSectorLabel(centerPercent, icon)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.new(0, 32, 0, 32)
	local labelAngle = math.rad(-90 + (centerPercent / 100) * 180)
	label.Position = UDim2.new(
		0,
		GAUGE_CENTER.X + math.sin(labelAngle) * (GAUGE_RADIUS + 26),
		0,
		GAUGE_CENTER.Y - math.cos(labelAngle) * (GAUGE_RADIUS + 26)
	)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = icon
	label.ZIndex = 10
	label.Parent = heatFrame
	return label
end
-- Sektor-Icons entfernt (störten das HUD, laut Rückmeldung).

-- ===== Nadel: eigener Dreh-Anker EXAKT am Drehpunkt -- nur der Anker wird rotiert, die
-- Nadel selbst bleibt an ihrer unteren Kante fix mit ihm verbunden (siehe Erklärung oben).
local needlePivot = Instance.new("Frame")
needlePivot.Name = "NeedlePivot"
needlePivot.AnchorPoint = Vector2.new(0.5, 0.5)
needlePivot.Size = UDim2.new(0, 1, 0, 1)
needlePivot.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
needlePivot.BackgroundTransparency = 1
needlePivot.ZIndex = 11
needlePivot.Parent = heatFrame

local needle = Instance.new("Frame")
needle.Name = "Needle"
needle.AnchorPoint = Vector2.new(0.5, 1)
needle.Size = UDim2.new(0, 10, 0, GAUGE_RADIUS - 4)
needle.Position = UDim2.new(0.5, 0, 0, 0)
needle.BackgroundColor3 = Color3.new(1, 1, 1)
needle.BorderSizePixel = 0
needle.ZIndex = 11
needle.Parent = needlePivot
applyComicStyle(needle, 4, 2)

-- Nabe in der Mitte, überdeckt den Nadel-Ansatz. Bleibt unrotiert (eigenes Objekt, kein
-- Kind des Nadel-Ankers), damit sie immer rund/aufrecht aussieht.
local needleHub = Instance.new("Frame")
needleHub.Name = "NeedleHub"
needleHub.AnchorPoint = Vector2.new(0.5, 0.5)
needleHub.Size = UDim2.new(0, 28, 0, 28)
needleHub.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
needleHub.BackgroundColor3 = Color3.fromRGB(255, 210, 80)
needleHub.BorderSizePixel = 0
needleHub.ZIndex = 12
needleHub.Parent = heatFrame
applyComicStyle(needleHub, 14, 2)

-- Prozentzahl + Stufen-Icon: im Zifferblatt selbst, knapp über dem Drehpunkt.
local heatLabel = Instance.new("TextLabel")
heatLabel.Name = "HeatLabel"
heatLabel.AnchorPoint = Vector2.new(0.5, 1)
heatLabel.Size = UDim2.new(0, 112, 0, 30)
heatLabel.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y - 32)
heatLabel.BackgroundTransparency = 1
heatLabel.Font = Enum.Font.FredokaOne
heatLabel.TextScaled = true
heatLabel.TextColor3 = Color3.new(1, 1, 1)
heatLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
heatLabel.TextStrokeTransparency = 0.5
heatLabel.ZIndex = 9 -- unter der Nadel, damit die Nadel sichtbar darüber wandert (wie bei einem echten Tacho)
heatLabel.Parent = heatFrame

-- Grosses Stage-Icon in der Mitte entfernt (heatStageLabel) -- störte das HUD, laut Rückmeldung.

-- Rauch-Glow für Meltdown -- sitzt über dem Zifferblatt.
local smokeEmitter = Instance.new("ImageLabel")
smokeEmitter.Name = "SmokeGlow"
smokeEmitter.AnchorPoint = Vector2.new(0.5, 1)
smokeEmitter.Size = UDim2.new(0, 140, 0, 140)
smokeEmitter.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y - GAUGE_RADIUS + 16)
smokeEmitter.BackgroundTransparency = 1
smokeEmitter.Image = "rbxasset://textures/particles/smoke_main.dds"
smokeEmitter.ImageColor3 = Color3.fromRGB(60, 30, 70)
smokeEmitter.ImageTransparency = 1
smokeEmitter.ZIndex = 13
smokeEmitter.Parent = heatFrame

-- Kein manueller Berserk-Button mehr -- aktiviert sich jetzt automatisch serverseitig,
-- sobald die Heat-Schwelle erreicht ist (siehe HeatHandler.lua).

local HEAT_STAGE_BONUS_TEXT = {
	Calm = "No Bonus",
	Aggressive = "⚔️+10%",
	Enraged = "⚔️+30% 🏃+10%",
	Berserk = "⚔️+60% 🏃+20%",
	Meltdown = "⚔️+30% 🏃-75%",
}

local HEAT_STAGE_COLORS = {
	Calm = Color3.fromRGB(80, 160, 255),
	Aggressive = Color3.fromRGB(255, 210, 60),
	Enraged = Color3.fromRGB(255, 140, 30),
	Berserk = Color3.fromRGB(255, 40, 30),
	Meltdown = Color3.fromRGB(180, 0, 220),
}
local HEAT_STAGE_ICONS = {
	Calm = "🌡️",
	Aggressive = "🌡️",
	Enraged = "🌡️",
	Berserk = "🔥",
	Meltdown = "☢️",
}

-- ===== Special-Energy-Arc: dünner Ring knapp AUSSERHALB des Berserker-Zifferblatts --
-- eigene, klar unterscheidbare Farbsprache (Cyan/Elektrisch-Blau statt Heat-Rot/Orange),
-- überdeckt das Berserker-Element nicht, braucht kaum zusätzliche HUD-Höhe (dünn, folgt
-- exakt derselben Halbkreis-Kontur wie das Zifferblatt selbst).
local ENERGY_ARC_RADIUS = DISC_RADIUS + 12
local ENERGY_ARC_SECTOR_COUNT = 60
local ENERGY_ARC_COLOR = Color3.fromRGB(70, 210, 255)
local ENERGY_ARC_COLOR_DIM = Color3.fromRGB(50, 60, 70)

local specialEnergyMaxValue = ReplicatedStorage:FindFirstChild("SpecialEnergyMax")

local energyArcWedges = {}
for i = 0, ENERGY_ARC_SECTOR_COUNT - 1 do
	local percent = (i / (ENERGY_ARC_SECTOR_COUNT - 1)) * 100
	local angle = -90 + (percent / 100) * 180

	local pivot = Instance.new("Frame")
	pivot.Name = "EnergyArcPivot" .. i
	pivot.AnchorPoint = Vector2.new(0.5, 0.5)
	pivot.Size = UDim2.new(0, 1, 0, 1)
	pivot.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
	pivot.Rotation = angle
	pivot.BackgroundTransparency = 1
	pivot.ZIndex = 6 -- unter dem Zifferblatt (das startet bei ZIndex 7) -- Arc liegt sichtbar dahinter/aussen, überdeckt nichts
	pivot.Parent = heatFrame

	local wedge = Instance.new("Frame")
	wedge.Name = "EnergyWedge"
	wedge.AnchorPoint = Vector2.new(0.5, 1)
	wedge.Size = UDim2.new(0, 5, 0, ENERGY_ARC_RADIUS - DISC_RADIUS) -- dünn, nur der schmale Ring-Bereich ausserhalb des Zifferblatts
	wedge.Position = UDim2.new(0.5, 0, 0, -DISC_RADIUS) -- startet AM Rand des Zifferblatts, wächst nach aussen
	wedge.BackgroundColor3 = ENERGY_ARC_COLOR_DIM
	wedge.BorderSizePixel = 0
	wedge.ZIndex = 6
	wedge.Parent = pivot

	table.insert(energyArcWedges, { frame = wedge, percent = percent, flashUntil = 0 })
end

local lastHeatValue = nil -- merkt sich den letzten Wert, um bei ECHTEM Anstieg (nicht bei jeder Änderung, z.B. Abkühlung) aufzuleuchten
local lastEnergyPercent = nil -- gleiches Prinzip für den Special-Energy-Arc
local lastNeedleTargetRotation = nil -- letztes Rotations-Ziel der Nadel, um Tweens nicht bei jedem Heartbeat neu zu starten
local currentNeedleTween = nil -- aktuell laufender Nadel-Tween (falls vorhanden), zum sauberen Abbrechen bei neuem Ziel
local lastStageForShake = nil

RunService.Heartbeat:Connect(function()
	-- HINWEIS: Frühere Ausblendung des Tachos während Bein-Training wurde entfernt --
	-- der volle Berserker-Tacho (Scheibe, Nadel, Sektoren, Energy-Arc) soll jetzt sowohl
	-- bei Bein- als auch Körper-Training vollständig sichtbar bleiben (als Schwierigkeits-
	-- und Lern-Element).

	local heat = player:GetAttribute("Heat") or 0
	local berserkActive = player:GetAttribute("BerserkActive")
	local effectiveMeltdownThreshold = player:GetAttribute("EffectiveMeltdownThreshold") or 100
	local stage
	if heat >= effectiveMeltdownThreshold then
		stage = "Meltdown"
	elseif heat >= 85 then
		stage = berserkActive and "Berserk" or "Enraged"
	elseif heat >= 60 then
		stage = "Enraged"
	elseif heat >= 30 then
		stage = "Aggressive"
	else
		stage = "Calm"
	end

	local clampedHeat = math.clamp(heat, 0, GAUGE_MAX)
	local isAtMaxHeat = heat >= GAUGE_MAX
	-- Bei absolutem Maximum (110%) vibriert der Zeiger leicht um seine Zielposition,
	-- statt einfach nur still am Anschlag zu stehen -- macht "am Limit" spürbar.
	local vibrationOffset = isAtMaxHeat and (math.random() - 0.5) * 4 or 0
	local targetRotation = -90 + (clampedHeat / GAUGE_MAX) * 180 + vibrationOffset

	-- Wedge-Farben laufend aktualisieren -- Calm/Aggressive/Enraged-Grenzen (30/60/85)
	-- bleiben fix, die Berserker/Meltdown-Grenze nutzt aber effectiveMeltdownThreshold
	-- (talent-abhängig, siehe HeatHandler.lua), statt fest bei 100 zu bleiben.
	for _, wedgeInfo in ipairs(sectorWedges) do
		local wedgePercent = wedgeInfo.percent
		if wedgePercent < 30 then
			wedgeInfo.frame.BackgroundColor3 = Color3.fromRGB(70, 130, 210) -- Calm
		elseif wedgePercent < 60 then
			wedgeInfo.frame.BackgroundColor3 = Color3.fromRGB(210, 175, 50) -- Aggressive
		elseif wedgePercent < 85 then
			wedgeInfo.frame.BackgroundColor3 = Color3.fromRGB(210, 115, 25) -- Enraged
		elseif wedgePercent < effectiveMeltdownThreshold then
			wedgeInfo.frame.BackgroundColor3 = Color3.fromRGB(210, 25, 20) -- Berserker-Sektor
		else
			wedgeInfo.frame.BackgroundColor3 = Color3.fromRGB(170, 20, 190) -- Meltdown-Sektor -- eigene Farbe, deutlich abgesetzt
		end
	end

	-- Nadel bewegt sich mit Schwung (leichtes Überschwingen) zum neuen Wert, statt
	-- sofort zu springen -- neuer Tween wird nur gestartet, wenn sich das Ziel
	-- tatsächlich ändert (nicht bei jedem Heartbeat neu, sonst käme die Nadel nie zur Ruhe).
	if lastNeedleTargetRotation == nil or math.abs(targetRotation - lastNeedleTargetRotation) > 0.05 then
		lastNeedleTargetRotation = targetRotation
		if currentNeedleTween then
			currentNeedleTween:Cancel()
		end
		currentNeedleTween = TweenService:Create(
			needlePivot,
			TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Rotation = targetRotation }
		)
		currentNeedleTween:Play()
	end
	heatLabel.Text = math.floor(heat) .. "%"
	heatBonusLabel.Text = HEAT_STAGE_BONUS_TEXT[stage]
	needleHub.BackgroundColor3 = HEAT_STAGE_COLORS[stage]

	-- Aufleuchten bei ECHTEM Anstieg (z.B. durch einen Treffer) -- nicht bei Abkühlung
	-- oder unveränderten Werten.
	if lastHeatValue and heat > lastHeatValue then
		flashElement(needleHub, Color3.new(1, 1, 1))
		glowFlashElement(heatFrame, Color3.fromRGB(255, 200, 150))
	end
	lastHeatValue = heat

	if stage == "Meltdown" then
		-- Meltdown: Leiste "raucht"/"explodiert" -- Rauch-Glow einblenden, Rahmen pulsiert
		-- zwischen Gold und knalligem Lila-Rot, leichtes Zittern der ganzen Leiste.
		smokeEmitter.ImageTransparency = 0.35 + math.sin(os.clock() * 6) * 0.15
		local smokePulse = 140 + math.sin(os.clock() * 4) * 16
		smokeEmitter.Size = UDim2.new(0, smokePulse, 0, smokePulse)

		local pulse = (math.sin(os.clock() * 6) + 1) / 2

		-- Meltdown-Sektor des Zifferblatts pulsiert zusätzlich mit -- verstärkt die
		-- Dringlichkeit genau dort, wo es zählt. Nutzt die dynamische Schwelle statt fest 97.
		for _, wedgeInfo in ipairs(sectorWedges) do
			if wedgeInfo.percent >= effectiveMeltdownThreshold then
				wedgeInfo.frame.BackgroundColor3 = Color3.fromRGB(170, 20, 190):Lerp(Color3.fromRGB(255, 255, 255), pulse * 0.5)
			end
		end

		local shakeX = (math.random() - 0.5) * 4
		local shakeY = (math.random() - 0.5) * 4
		heatFrame.Position = UDim2.new(0.5, shakeX, 1, -24 + shakeY)
	else
		smokeEmitter.ImageTransparency = 1
		if lastStageForShake == "Meltdown" then
			heatFrame.Position = UDim2.new(0.5, 0, 1, -24) -- Zittern zurücksetzen, sobald Meltdown endet
			-- Kein manueller Wedge-Reset mehr nötig -- die laufende Einfärbung weiter oben
			-- im Loop übernimmt das automatisch jeden Frame.
		end
	end
	lastStageForShake = stage

	-- Special-Energy-Arc: Segmente bis zum aktuellen Füllstand einfärben, Rest bleibt
	-- gedimmt. Neu geladene Segmente leuchten kurz hell auf (weisser Blitz), bevor sie
	-- zur normalen Energy-Farbe übergehen -- macht sichtbar, WANN und WIEVIEL gerade
	-- aufgeladen wurde.
	local specialEnergy = player:GetAttribute("SpecialEnergy") or 0
	local specialEnergyMax = (specialEnergyMaxValue and specialEnergyMaxValue.Value) or 100
	local energyPercent = math.clamp((specialEnergy / math.max(specialEnergyMax, 1)) * 100, 0, 100)

	if lastEnergyPercent and energyPercent > lastEnergyPercent then
		local flashUntil = os.clock() + 0.35
		for _, wedgeInfo in ipairs(energyArcWedges) do
			if wedgeInfo.percent > lastEnergyPercent and wedgeInfo.percent <= energyPercent then
				wedgeInfo.flashUntil = flashUntil
			end
		end
	end
	lastEnergyPercent = energyPercent

	local now = os.clock()
	for _, wedgeInfo in ipairs(energyArcWedges) do
		if now < wedgeInfo.flashUntil then
			wedgeInfo.frame.BackgroundColor3 = Color3.new(1, 1, 1)
		elseif wedgeInfo.percent <= energyPercent then
			wedgeInfo.frame.BackgroundColor3 = ENERGY_ARC_COLOR
		else
			wedgeInfo.frame.BackgroundColor3 = ENERGY_ARC_COLOR_DIM
		end
	end
end)

-- Meltdown-Explosion: kurzer roter Bildschirm-Flash + Kamerawackeln
local meltdownFlash = Instance.new("Frame")
meltdownFlash.Name = "MeltdownFlash"
meltdownFlash.Size = UDim2.new(1, 0, 1, 0)
meltdownFlash.BackgroundColor3 = Color3.fromRGB(255, 40, 20)
meltdownFlash.BackgroundTransparency = 1
meltdownFlash.ZIndex = 100
meltdownFlash.Parent = screenGui

MeltdownExplosionEvent.OnClientEvent:Connect(function()
	meltdownFlash.BackgroundTransparency = 0.6
	TweenService:Create(meltdownFlash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end)

-- ===== 3 Kraft-Balken NEBENEINANDER: Bein/Arm/Körper, Cap = Level x StatCapPerLevel =====
-- Eigener kleiner Frame, direkt unter dem kompakten Player-Status-Cluster -- im HUD-
-- Redesign nicht explizit erwähnt, bekommt aber trotzdem einen aufgeräumten Platz statt
-- im (jetzt nicht mehr vorhandenen) grossen alten levelFrame zu stecken.
local statsRowFrame = Instance.new("Frame")
statsRowFrame.Name = "StatsRowFrame"
statsRowFrame.Size = UDim2.new(0, 360, 0, 108) -- höher als vorher: Platz für Titel + Wirkungs-Zeile pro Stat
statsRowFrame.AnchorPoint = Vector2.new(0, 0)
statsRowFrame.Position = UDim2.new(0, 16, 0, 14) -- links oben, NICHT mehr oben mittig (Platz für den Trainings-Balken dort)
statsRowFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
statsRowFrame.BackgroundTransparency = 0.15 -- sichtbarer Rahmen statt "schwebender" nackter Balken
statsRowFrame.Parent = screenGui

local statsPanelCorner = Instance.new("UICorner")
statsPanelCorner.CornerRadius = UDim.new(0, 14)
statsPanelCorner.Parent = statsRowFrame

-- Titel-Header: macht auf einen Blick klar, WAS das ist (vorher: nackte Balken ohne
-- jeden Kontext, besonders auffällig in Sanctuary, wo sonst kein HUD drumherum steht).
local statsPanelTitle = Instance.new("TextLabel")
statsPanelTitle.Name = "PanelTitle"
statsPanelTitle.Size = UDim2.new(1, -16, 0, 22)
statsPanelTitle.Position = UDim2.new(0, 8, 0, 4)
statsPanelTitle.BackgroundTransparency = 1
statsPanelTitle.Font = Enum.Font.LuckiestGuy
statsPanelTitle.TextScaled = true
statsPanelTitle.TextColor3 = Color3.fromRGB(255, 210, 80)
statsPanelTitle.TextStrokeColor3 = Color3.new(0, 0, 0)
statsPanelTitle.TextStrokeTransparency = 0.3
statsPanelTitle.TextXAlignment = Enum.TextXAlignment.Center
statsPanelTitle.Text = "🏋️ TRAINING"


local statsRow = Instance.new("Frame")
statsRow.Name = "StatsRow"
statsRow.Size = UDim2.new(1, -16, 0, 68)
statsRow.Position = UDim2.new(0, 8, 0, 30)
statsRow.BackgroundTransparency = 1
statsRow.Parent = statsRowFrame

local statsRowLayout = Instance.new("UIListLayout")
statsRowLayout.FillDirection = Enum.FillDirection.Horizontal
statsRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statsRowLayout.Padding = UDim.new(0, 8)
statsRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
statsRowLayout.Parent = statsRow



-- Ordnet den Trainings-Stat-Typ (wie er in "TrainingStat" steht, z.B. "Arm") derselben
-- Farbe zu, die auch der kleine Skill-Balken oben hat -- damit der große Trainings-Balken
-- unten farblich konsistent zum jeweils trainierten Skill ist.
local STAT_COLOR_BY_TYPE = {
	Arm = Color3.fromRGB(220, 90, 220),
	Leg = Color3.fromRGB(255, 150, 60),
	Body = Color3.fromRGB(90, 220, 130),
}

local statBars = {} -- [key] = { label = TextLabel, fill = Frame, displayName = string }
local lastStatValues = {} -- [key] = number
local isAnimatingStat = {} -- [key] = true, während eine Flug-Animation für diesen Stat läuft
-- Vorwärtsdeklaration: wird von der Energie-Flug-Animation weiter oben im Script (im
-- onArrive-Callback) bereits referenziert, aber erst weiter unten definiert -- Lua macht
-- lokale Variablen erst AB ihrer Deklaration sichtbar, daher hier vorab anlegen.
local updateLevelBar
local advanceXPBar

local STAT_BAR_CONFIG = {
	{ key = "ArmPower", label = "💪 Arm", color = Color3.fromRGB(220, 90, 220), effect = "Base Damage" },
	{ key = "LegPower", label = "🦵 Bein", color = Color3.fromRGB(255, 150, 60), effect = "Bonus Damage" },
	{ key = "BodyPower", label = "💓 Körper", color = Color3.fromRGB(90, 220, 130), effect = "Energy Efficiency" },
}

for index, config in ipairs(STAT_BAR_CONFIG) do
	local column = Instance.new("Frame")
	column.Name = config.key .. "Column"
	column.Size = UDim2.new(0, 108, 1, 0)
	column.LayoutOrder = index
	column.BackgroundTransparency = 1
	column.Parent = statsRow

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = config.label .. ": 0/0"
	label.Parent = column

	local statBackground = Instance.new("Frame")
	statBackground.Name = "Background"
	statBackground.Size = UDim2.new(1, 0, 0, 16)
	statBackground.Position = UDim2.new(0, 0, 0, 22)
	statBackground.BackgroundColor3 = Color3.fromRGB(30, 60, 100)
	statBackground.Parent = column
	applyComicStyle(statBackground, 7, 2)

	local statFill = Instance.new("Frame")
	statFill.Name = "Fill"
	statFill.Size = UDim2.new(0, 0, 1, 0)
	statFill.BackgroundColor3 = config.color
	statFill.BorderSizePixel = 0
	statFill.ZIndex = 2
	statFill.Parent = statBackground
	applyComicStyle(statFill, 5, 0)

	-- Wirkungs-Zeile: macht konkret klar, wofür der Wert gut ist (vorher komplett
	-- unerklärt) -- z.B. "Schlag-Schaden" unter Arm.
	local effectLabel = Instance.new("TextLabel")
	effectLabel.Name = "EffectLabel"
	effectLabel.Size = UDim2.new(1, 0, 0, 14)
	effectLabel.Position = UDim2.new(0, 0, 0, 42)
	effectLabel.BackgroundTransparency = 1
	effectLabel.TextColor3 = Color3.fromRGB(180, 185, 195)
	effectLabel.Font = Enum.Font.FredokaOne
	effectLabel.TextScaled = true
	effectLabel.Text = "↑ " .. config.effect
	effectLabel.Parent = column

	statBars[config.key] = { label = label, fill = statFill, displayName = config.label }
end

-- ===== Zonenabhängige Umschaltung: Heat/Berserk-Leiste ist ausserhalb von Sanctuary
-- relevant (Kampf), die Skill-Balken (Arm/Bein/Körper) dagegen speziell IM Sanctuary
-- (friedliche Zone, guter Ort um den eigenen Fortschritt zu checken, kein Kampf-HUD
-- nötig). Reduziert dadurch die HUD-Dichte in beiden Situationen. =====
local function updateZoneBasedHudVisibility()
	local isSanctuary = player:GetAttribute("CurrentZone") == "Sanctuary"
	local isTraining = player:GetAttribute("TrainingStat") ~= nil or player:GetAttribute("BodyTrainingActive") == true
	statsRowFrame.Visible = isSanctuary
	-- Ausnahme: Heat/Berserker-Tacho bleibt auch in Sanctuary sichtbar, solange irgendeine
	-- Trainingsstation aktiv ist (Arm/Bein/Körper) -- Berserker (inkl. Bonus-Schaden) soll
	-- überall genauso nutzbar/sichtbar sein wie im echten Kampf, unabhängig davon, dass
	-- manche Stationen in Sanctuary stehen.
	heatFrame.Visible = (not isSanctuary) or isTraining
end

player:GetAttributeChangedSignal("TrainingStat"):Connect(updateZoneBasedHudVisibility)
player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(updateZoneBasedHudVisibility)

player:GetAttributeChangedSignal("CurrentZone"):Connect(updateZoneBasedHudVisibility)
updateZoneBasedHudVisibility()

-- ===== Skin-Shop-Menü: öffnet sich über den "Skin kaufen"-Button (Comic-Panel) =====
-- EIGENES ScreenGui fuer das Panel. Vorher lag es in GameHud -- zusammen mit
-- Statuszeile, Hitzeanzeige und zehn weiteren HUD-Teilen, also ohne DisplayOrder auf 0 und damit gleichauf mit dem uebrigen HUD.
-- Ein Vollbild-Panel auf derselben Ebene wie das HUD laesst dieses durchscheinen.
--
-- Getrennt statt die DisplayOrder des ganzen Guis anzuheben: das haette das HUD gleich
-- mit nach vorne geholt, also genau das Gegenteil bewirkt.
local shopGui = Instance.new("ScreenGui")
shopGui.Name = "SkinShopGui"
shopGui.ResetOnSpawn = false
shopGui.DisplayOrder = 100
shopGui.IgnoreGuiInset = true
shopGui.Parent = player:WaitForChild("PlayerGui")

local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
-- Vollbild: alle Menü-Bildschirme nutzen die ganze Fläche.
-- IgnoreGuiInset am ScreenGui gehört dazu -- ohne das beginnt jedes ScreenGui UNTERHALB
-- der Roblox-Systemleiste, und oben bliebe ein Streifen mit Sicht auf die Welt stehen.
shopFrame.Size = UDim2.new(1, 0, 1, 0)
shopFrame.Position = UDim2.new(0, 0, 0, 0)
shopFrame.AnchorPoint = Vector2.new(0, 0)
shopFrame.Visible = false
shopFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
shopFrame.Parent = shopGui

-- Schliesst den Shop zwangsweise -- unabhängig davon, was ihn geöffnet hat (auch falls es
-- NICHT über den normalen Navigations-Weg lief, siehe ForceCloseShopEvent). Genutzt vom
-- Prolog, um sicherzustellen, dass der Shop beim Verlassen des Prologs nicht offen steht.
local ForceCloseShopEvent = RemoteEventUtils.GetOrCreate("ForceCloseShopEvent")
ForceCloseShopEvent.OnClientEvent:Connect(function()
	shopFrame.Visible = false
end)
applyComicStyle(shopFrame, 20, 5)

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(shopFrame)

-- X-Schliessen-Button -- kehrt zum Hamburger-Menü zurück (dieses Panel hatte bisher
-- keinen eigenen, war nur über den jetzt entfernten "← Back"-Button schliessbar).
local shopCloseButton = Instance.new("TextButton")
shopCloseButton.Name = "CloseButton"
shopCloseButton.Size = UDim2.new(0, 34, 0, 34)
shopCloseButton.AnchorPoint = Vector2.new(1, 0)
shopCloseButton.Position = UDim2.new(1, -8, 0, 8)
shopCloseButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
shopCloseButton.Font = Enum.Font.FredokaOne
shopCloseButton.TextScaled = true
shopCloseButton.TextColor3 = Color3.new(1, 1, 1)
shopCloseButton.Text = "X"
shopCloseButton.ZIndex = 5
shopCloseButton.Parent = shopFrame
applyComicStyle(shopCloseButton, 8, 2)
shopCloseButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	end
end)

local shopTitle = Instance.new("TextLabel")
shopTitle.Name = "ShopTitle"
shopTitle.Size = UDim2.new(1, -16, 0, 40)
shopTitle.Position = UDim2.new(0, 8, 0, 8)
shopTitle.BackgroundTransparency = 1
shopTitle.TextColor3 = Color3.fromRGB(235, 235, 245)
shopTitle.Font = Enum.Font.LuckiestGuy
shopTitle.TextScaled = true
shopTitle.Text = "☯️ Skins"
shopTitle.Parent = shopFrame

-- Liste links, Steckbrief rechts. Die Liste braucht wenig -- sechs Eintraege mit Name und
-- Zustand --, der Steckbrief traegt Modell, Balken, Beschreibung und den Aktionsknopf.
local LIST_WIDTH = 0.3

local shopScroll = Instance.new("ScrollingFrame")
shopScroll.Name = "ShopScroll"
shopScroll.Size = UDim2.new(LIST_WIDTH, -16, 1, -60)
shopScroll.Position = UDim2.new(0, 12, 0, 54)
shopScroll.BackgroundTransparency = 1
shopScroll.BorderSizePixel = 0
shopScroll.ScrollBarThickness = 10
shopScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopScroll.Parent = shopFrame

local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 8)
-- Ausdruecklich nach LayoutOrder: seit die Liste nach Fraktionen gruppiert ist, haengt die
-- Reihenfolge an den vergebenen Nummern und nicht mehr an der Erzeugungsreihenfolge.
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = shopScroll

-- ===== Steckbrief =====
-- Kein Unterbildschirm: der Shop ist seit dem Vollbild-Umbau breit genug, beides
-- nebeneinander zu zeigen. Ein Klick in der Liste WAEHLT nur aus -- gekauft und angelegt
-- wird ueber den Knopf hier. Vorher kaufte ein Klick sofort, was bei 6000 Muenzen fuer den
-- Radiant Apex ein teures Versehen sein konnte.
local detailFrame = Instance.new("Frame")
detailFrame.Name = "SkinDetail"
detailFrame.Size = UDim2.new(1 - LIST_WIDTH, -24, 1, -60)
detailFrame.Position = UDim2.new(LIST_WIDTH, 4, 0, 54)

local SKIN_TEXT_MAX_WIDTH = 620 -- lesbare Zeilenlaenge, unabhaengig von der Bildschirmbreite
detailFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
detailFrame.Parent = shopFrame
applyComicStyle(detailFrame, 14, 3)

local detailViewport = Instance.new("Frame")
detailViewport.Name = "Preview"
detailViewport.Size = UDim2.new(0.42, -24, 0.52, 0)
detailViewport.Position = UDim2.new(0, 16, 0, 16)
detailViewport.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
detailViewport.Parent = detailFrame
applyComicStyle(detailViewport, 12, 2)

local detailName = Instance.new("TextLabel")
detailName.Size = UDim2.new(0.58, -32, 0, 40)
detailName.Position = UDim2.new(0.42, 0, 0, 16)
detailName.BackgroundTransparency = 1
detailName.Font = Enum.Font.LuckiestGuy
detailName.TextScaled = true
detailName.TextXAlignment = Enum.TextXAlignment.Left
detailName.TextColor3 = Color3.fromRGB(235, 235, 245)
detailName.Text = ""
detailName.Parent = detailFrame

-- Hoechstbreite der Textspalte. Ohne sie laeuft der Steckbrief auf einem breiten
-- Bildschirm ueber die halbe Monitorbreite -- so lange Zeilen liest niemand gern.
local detailNameWidthCap = Instance.new("UISizeConstraint")
detailNameWidthCap.MaxSize = Vector2.new(SKIN_TEXT_MAX_WIDTH, math.huge)
detailNameWidthCap.Parent = detailName

local detailRole = Instance.new("TextLabel")
detailRole.Size = UDim2.new(0.58, -32, 0, 44)
detailRole.Position = UDim2.new(0.42, 0, 0, 58)
detailRole.BackgroundTransparency = 1
detailRole.Font = Enum.Font.Gotham
detailRole.TextSize = 15
detailRole.TextWrapped = true
detailRole.TextXAlignment = Enum.TextXAlignment.Left
detailRole.TextYAlignment = Enum.TextYAlignment.Top
detailRole.TextColor3 = Color3.fromRGB(165, 165, 180)
detailRole.Text = ""
detailRole.Parent = detailFrame

-- Hoechstbreite der Textspalte. Ohne sie laeuft der Steckbrief auf einem breiten
-- Bildschirm ueber die halbe Monitorbreite -- so lange Zeilen liest niemand gern.
local detailRoleWidthCap = Instance.new("UISizeConstraint")
detailRoleWidthCap.MaxSize = Vector2.new(SKIN_TEXT_MAX_WIDTH, math.huge)
detailRoleWidthCap.Parent = detailRole

local detailStrength = Instance.new("TextLabel")
detailStrength.Size = UDim2.new(0.58, -32, 0, 90)
detailStrength.Position = UDim2.new(0.42, 0, 0, 106)
detailStrength.BackgroundTransparency = 1
UiTypography.Body(detailStrength)
detailStrength.TextXAlignment = Enum.TextXAlignment.Left
detailStrength.TextYAlignment = Enum.TextYAlignment.Top
detailStrength.TextColor3 = Color3.fromRGB(235, 235, 245)
detailStrength.Text = ""
detailStrength.Parent = detailFrame

-- Hoechstbreite der Textspalte. Ohne sie laeuft der Steckbrief auf einem breiten
-- Bildschirm ueber die halbe Monitorbreite -- so lange Zeilen liest niemand gern.
local detailStrengthWidthCap = Instance.new("UISizeConstraint")
detailStrengthWidthCap.MaxSize = Vector2.new(SKIN_TEXT_MAX_WIDTH, math.huge)
detailStrengthWidthCap.Parent = detailStrength

-- Level-Freischaltung: der staerkste Kaufgrund im Spiel und bis heute nirgends genannt.
-- Jeder GEKAUFTE Skin hebt die Obergrenze um 10 (PlayerSetup.getLevelCap).
local detailBonus = Instance.new("TextLabel")
detailBonus.Size = UDim2.new(0.58, -32, 0, 26)
detailBonus.Position = UDim2.new(0.42, 0, 0, 200)
detailBonus.BackgroundColor3 = Color3.fromRGB(255, 236, 180)
UiTypography.Body(detailBonus, 15)
detailBonus.TextColor3 = Color3.fromRGB(120, 80, 20)
detailBonus.Text = ""
detailBonus.Visible = false
detailBonus.Parent = detailFrame

-- Hoechstbreite der Textspalte. Ohne sie laeuft der Steckbrief auf einem breiten
-- Bildschirm ueber die halbe Monitorbreite -- so lange Zeilen liest niemand gern.
local detailBonusWidthCap = Instance.new("UISizeConstraint")
detailBonusWidthCap.MaxSize = Vector2.new(SKIN_TEXT_MAX_WIDTH, math.huge)
detailBonusWidthCap.Parent = detailBonus
applyComicStyle(detailBonus, 8, 2)

-- Drei Balken: Leben, Tempo, Groesse. "Damage" fehlt bewusst -- das Feld gab es zwar, es
-- wurde aber nirgends gelesen (Schaden kommt aus ArmPower) und ist deshalb entfernt.
local statRows = {}
local STAT_DEFS = {
	{ key = "Health", label = "Health" },
	{ key = "WalkSpeed", label = "Speed" },
	{ key = "Scale", label = "Size" },
}
for index, def in ipairs(STAT_DEFS) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -32, 0, 30)
	row.Position = UDim2.new(0, 16, 0.56, (index - 1) * 34)
	row.BackgroundTransparency = 1
	row.Parent = detailFrame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 70, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(165, 165, 180)
	label.Text = def.label
	label.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -230, 0, 14)
	track.Position = UDim2.new(0, 74, 0.5, -7)
	track.BackgroundColor3 = Color3.fromRGB(58, 58, 68)
	track.Parent = row
	applyComicStyle(track, 7, 2)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90, 175, 235)
	fill.BorderSizePixel = 0
	fill.Parent = track
	applyComicStyle(fill, 7, 0)

	-- Der Vergleich zum GETRAGENEN Skin -- das ist die Frage, wegen der man herschaut.
	local delta = Instance.new("TextLabel")
	delta.Size = UDim2.new(0, 150, 1, 0)
	delta.Position = UDim2.new(1, -150, 0, 0)
	delta.BackgroundTransparency = 1
	delta.Font = Enum.Font.Gotham
	delta.TextSize = 14
	delta.TextXAlignment = Enum.TextXAlignment.Right
	delta.TextColor3 = Color3.fromRGB(165, 165, 180)
	delta.Text = ""
	delta.Parent = row

	statRows[def.key] = { fill = fill, delta = delta, row = row }
end

local detailAction = Instance.new("TextButton")
detailAction.Name = "ActionButton"
detailAction.Size = UDim2.new(1, -32, 0, 52)
detailAction.Position = UDim2.new(0, 16, 1, -68)
detailAction.Font = Enum.Font.FredokaOne
detailAction.TextScaled = true
detailAction.TextColor3 = Color3.new(1, 1, 1)
detailAction.Text = ""
detailAction.Parent = detailFrame
applyComicStyle(detailAction, 12, 3)

-- ===== Trainings-Panel: unten Mitte, NUR sichtbar während aktivem Training an einer Station =====
local STAT_DISPLAY_NAMES = {
	Leg = "🦵 Bein",
	Arm = "💪 Arm",
	Body = "💓 Körper",
}

local trainingFrame = Instance.new("Frame")
trainingFrame.Name = "TrainingFrame"
trainingFrame.Size = UDim2.new(0, 440, 0, 100)
trainingFrame.AnchorPoint = Vector2.new(0.5, 0)
trainingFrame.Position = UDim2.new(0.5, 0, 0, 94) -- oben mittig, unterhalb des Player-Status-Clusters (der endet bei Y=8+78=86)
trainingFrame.BackgroundTransparency = 1
trainingFrame.Visible = false
trainingFrame.Parent = screenGui
local trainingFrameCorner, trainingFrameStroke = applyComicStyle(trainingFrame, 18, 5)
trainingFrameStroke.Transparency = 1

local trainingTitle = Instance.new("TextLabel")
trainingTitle.Name = "TrainingTitle"
trainingTitle.Size = UDim2.new(1, 0, 0, 28)
trainingTitle.Position = UDim2.new(0, 0, 0, 4)
trainingTitle.BackgroundTransparency = 1
trainingTitle.Font = Enum.Font.LuckiestGuy
trainingTitle.TextScaled = true
trainingTitle.TextColor3 = Color3.new(1, 1, 1)
trainingTitle.Text = "Training"
trainingTitle.Parent = trainingFrame

-- Große Stat-Fortschrittsanzeige (aktueller Wert / Cap für diese Station) -- etwas
-- schmaler, damit rechts daneben Platz für den kompakten X-Button bleibt.
local trainingBarBackground = Instance.new("Frame")
trainingBarBackground.Name = "TrainingBarBackground"
trainingBarBackground.Size = UDim2.new(1, -64, 0, 28)
trainingBarBackground.Position = UDim2.new(0, 8, 0, 36)
trainingBarBackground.BackgroundColor3 = Color3.fromRGB(30, 60, 100)
trainingBarBackground.Parent = trainingFrame
applyComicStyle(trainingBarBackground, 12, 3)

local trainingBarFill = Instance.new("Frame")
trainingBarFill.Name = "Fill"
trainingBarFill.Size = UDim2.new(0, 0, 1, 0)
trainingBarFill.BackgroundColor3 = Color3.fromRGB(90, 220, 130)
trainingBarFill.BorderSizePixel = 0
trainingBarFill.Parent = trainingBarBackground
applyComicStyle(trainingBarFill, 10, 0)

local trainingBarLabel = Instance.new("TextLabel")
trainingBarLabel.Name = "TrainingBarLabel"
trainingBarLabel.Size = UDim2.new(1, 0, 1, 0)
trainingBarLabel.BackgroundTransparency = 1
trainingBarLabel.Font = Enum.Font.FredokaOne
trainingBarLabel.TextScaled = true
trainingBarLabel.TextColor3 = Color3.new(1, 1, 1)
trainingBarLabel.ZIndex = 2
trainingBarLabel.Text = ""
trainingBarLabel.Parent = trainingBarBackground

-- Verlassen-Button: kompakter "X"-Button, direkt neben dem Trainings-Balken (innerhalb
-- des Panels, das jetzt weit genug oben sitzt, um nicht mehr mit den Angriffs-Buttons zu kollidieren).
local leaveTrainingButton = Instance.new("TextButton")
leaveTrainingButton.Name = "LeaveTrainingButton"
leaveTrainingButton.Size = UDim2.new(0, 40, 0, 28)
leaveTrainingButton.AnchorPoint = Vector2.new(1, 0)
leaveTrainingButton.Position = UDim2.new(1, -8, 0, 36)
leaveTrainingButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
leaveTrainingButton.Font = Enum.Font.FredokaOne
leaveTrainingButton.TextScaled = true
leaveTrainingButton.TextColor3 = Color3.new(1, 1, 1)
leaveTrainingButton.Text = "X"
leaveTrainingButton.Parent = trainingFrame
applyComicStyle(leaveTrainingButton, 10, 3)

leaveTrainingButton.MouseButton1Click:Connect(function()
	StopTrainingEvent:FireServer()
end)

-- ===== Boost-Anzeige: eigenes, DAUERHAFT sichtbares Panel (oben rechts) -- der Boost-
-- Fortschritt bleibt ja bestehen, auch wenn man gerade an keiner Station steht, deshalb
-- verschwindet diese Anzeige NICHT zusammen mit dem Stations-Trainings-Panel.
local boostFrame = Instance.new("Frame")
boostFrame.Name = "BoostFrame"
boostFrame.Size = UDim2.new(0, 440, 0, 50) -- gleiche Breite wie das Trainings-Panel darüber
boostFrame.AnchorPoint = Vector2.new(0.5, 0)
boostFrame.Position = UDim2.new(0.5, 0, 0, 198) -- direkt unterhalb des Trainings-Panels (dessen unterer Rand liegt jetzt bei Y=94+100=194)
boostFrame.BackgroundTransparency = 1 -- kein Hintergrund mehr
boostFrame.Parent = screenGui

local boostBarBackground = Instance.new("Frame")
boostBarBackground.Name = "BoostBarBackground"
boostBarBackground.Size = UDim2.new(1, -64, 0, 22) -- gleiche Breite wie der Trainings-Balken (dort -64 wegen dem X-Button daneben)
boostBarBackground.Position = UDim2.new(0, 8, 0, 0)
boostBarBackground.BackgroundColor3 = Color3.fromRGB(30, 60, 100)
boostBarBackground.Parent = boostFrame
applyComicStyle(boostBarBackground, 10, 3)

local boostBarFill = Instance.new("Frame")
boostBarFill.Name = "Fill"
boostBarFill.Size = UDim2.new(0, 0, 1, 0)
boostBarFill.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
boostBarFill.BorderSizePixel = 0
boostBarFill.Parent = boostBarBackground
applyComicStyle(boostBarFill, 8, 0)

local boostLabel = Instance.new("TextLabel")
boostLabel.Name = "BoostLabel"
boostLabel.Size = UDim2.new(1, -16, 0, 20)
boostLabel.Position = UDim2.new(0, 8, 0, 28)
boostLabel.BackgroundTransparency = 1
boostLabel.Font = Enum.Font.FredokaOne
boostLabel.TextScaled = true
boostLabel.TextColor3 = Color3.new(1, 1, 1)
boostLabel.Text = "⚡ Training Boost" -- statische Überschrift, ändert sich nicht mehr
boostLabel.Parent = boostFrame

boostFrame.Visible = false

-- ===== Berserker-Modus-Panel: rote Progressbar, zeigt verbleibende Dauer =====
-- Unten mittig, unter der normalen HUD-Zeile -- unabhängig vom Trainings-System sichtbar,
-- da der Berserker-Modus ja im normalen Kampf (Häuser zerstören) ausgelöst wird.
local berserkerFrame = Instance.new("Frame")
berserkerFrame.Name = "BerserkerFrame"
berserkerFrame.Size = UDim2.new(0, 320, 0, 58)
berserkerFrame.AnchorPoint = Vector2.new(0.5, 0)
berserkerFrame.Position = UDim2.new(0.5, 0, 0, 170)
berserkerFrame.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
berserkerFrame.Visible = false
berserkerFrame.Parent = screenGui
applyComicStyle(berserkerFrame, 16, 4)

local berserkerLabel = Instance.new("TextLabel")
berserkerLabel.Name = "BerserkerLabel"
berserkerLabel.Size = UDim2.new(1, -16, 0, 22)
berserkerLabel.Position = UDim2.new(0, 8, 0, 4)
berserkerLabel.BackgroundTransparency = 1
berserkerLabel.Font = Enum.Font.LuckiestGuy
berserkerLabel.TextScaled = true
berserkerLabel.TextColor3 = Color3.fromRGB(255, 70, 60)
berserkerLabel.Text = "BERSERKER-MODUS"
berserkerLabel.Parent = berserkerFrame

local berserkerBarBackground = Instance.new("Frame")
berserkerBarBackground.Name = "BerserkerBarBackground"
berserkerBarBackground.Size = UDim2.new(1, -16, 0, 22)
berserkerBarBackground.Position = UDim2.new(0, 8, 0, 28)
berserkerBarBackground.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
berserkerBarBackground.Parent = berserkerFrame
applyComicStyle(berserkerBarBackground, 10, 3)

local berserkerBarFill = Instance.new("Frame")
berserkerBarFill.Name = "Fill"
berserkerBarFill.Size = UDim2.new(1, 0, 1, 0)
berserkerBarFill.BackgroundColor3 = Color3.fromRGB(255, 45, 35)
berserkerBarFill.BorderSizePixel = 0
berserkerBarFill.Parent = berserkerBarBackground
applyComicStyle(berserkerBarFill, 8, 0)

RunService.Heartbeat:Connect(function()
	local endsAt = player:GetAttribute("BerserkerEndsAt") or 0
	local startedAt = player:GetAttribute("BerserkerStartedAt") or 0
	local now = Workspace:GetServerTimeNow()
	local isActive = now < endsAt

	berserkerFrame.Visible = isActive
	if isActive then
		local totalDuration = math.max(endsAt - startedAt, 0.1)
		local remaining = endsAt - now
		local ratio = math.clamp(remaining / totalDuration, 0, 1)
		berserkerBarFill.Size = UDim2.new(ratio, 0, 1, 0)

		-- Label + Farbe je nach tatsächlichem Heat-Zustand: "MELTDOWN" (lila) sobald die
		-- (talent-abhängige) Meltdown-Schwelle erreicht ist, sonst "BERSERKER-MODUS" (rot).
		local heat = player:GetAttribute("Heat") or 0
		local effectiveMeltdownThreshold = player:GetAttribute("EffectiveMeltdownThreshold") or 100
		if heat >= effectiveMeltdownThreshold then
			berserkerLabel.Text = "MELTDOWN"
			berserkerLabel.TextColor3 = Color3.fromRGB(180, 60, 220)
			berserkerBarFill.BackgroundColor3 = Color3.fromRGB(180, 60, 220)
		else
			berserkerLabel.Text = "BERSERKER-MODUS"
			berserkerLabel.TextColor3 = Color3.fromRGB(255, 70, 60)
			berserkerBarFill.BackgroundColor3 = Color3.fromRGB(255, 45, 35)
		end
	end
end)

-- Läuft jeden Frame: Boost-Anzeige + Stations-Balken, beide NUR während aktivem Training
-- an einer Station sichtbar (verschwinden zusammen, sobald die Station verlassen wird).
local lastTrainingBarValue = nil

-- Kein eigener Boost-Sound mehr -- die Tempo-Erhöhung der Hintergrundmusik (siehe
-- BackgroundMusicClient.lua) übernimmt die Rolle als hörbares Boost-Feedback komplett.

RunService.Heartbeat:Connect(function()
	local statType = player:GetAttribute("TrainingStat")
	-- Body-Training nutzt ein eigenes Attribut (BodyTrainingActive) statt TrainingStat,
	-- da die Station komplett eigenständig läuft -- hier trotzdem denselben Balken zeigen.
	if not statType and player:GetAttribute("BodyTrainingActive") then
		statType = "Body"
	end
	local isTraining = statType ~= nil
	trainingFrame.Visible = isTraining
	boostFrame.Visible = isTraining
	if not isTraining then
		lastTrainingBarValue = nil -- zurücksetzen, damit beim nächsten Start keine falsche Erhöhung erkannt wird
		return
	end

	local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
	local now = Workspace:GetServerTimeNow()

	if now < boostEndsAt then
		local remaining = boostEndsAt - now
		local boostRatio = math.clamp(remaining / math.max(boostDurationValue.Value, 1), 0, 1)
		boostBarFill.Size = UDim2.new(boostRatio, 0, 1, 0)

		-- Rotes Pulsieren während der AKTIVEN Boost-Phase -- Sinus-Welle zwischen
		-- dunklerem und hellerem Rot.
		local pulse = (math.sin(os.clock() * 6) + 1) / 2 -- 0..1
		local dimRed = Color3.fromRGB(150, 25, 25)
		local brightRed = Color3.fromRGB(255, 60, 60)
		boostBarFill.BackgroundColor3 = dimRed:Lerp(brightRed, pulse)
	else
		local charge = player:GetAttribute("BoostCharge") or 0
		local chargeNeeded = math.max(player:GetAttribute("BoostChargeNeeded") or 1, 1)
		local chargeRatio = math.clamp(charge / chargeNeeded, 0, 1)
		boostBarFill.Size = UDim2.new(chargeRatio, 0, 1, 0)
		boostBarFill.BackgroundColor3 = Color3.fromRGB(255, 220, 60) -- statisches Gelb während des Aufladens
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local statValue = player:FindFirstChild(statType .. "Power")
	if not leaderstats or not statValue then
		return
	end

	local capAttribute = "StatCap"
	if statType == "Arm" then
		capAttribute = "ArmStatCap"
	elseif statType == "Leg" then
		capAttribute = "LegStatCap"
	end
	local cap = math.max(player:GetAttribute(capAttribute) or 1, 1)
	local ratio = math.clamp(statValue.Value / cap, 0, 1)

	trainingTitle.Text = (STAT_DISPLAY_NAMES[statType] or statType) .. "-Training"

	-- Wie beim Kraft-Balken: während eine Flug-Animation für diesen Stat läuft, hier
	-- nicht eingreifen -- der Balken springt erst bei Ankunft der Zahl auf den neuen Wert
	-- (siehe spawnFlyingTrainPoint).
	if not isAnimatingStat[statType .. "Power"] then
		trainingBarFill.Size = UDim2.new(ratio, 0, 1, 0)
		local skillColor = STAT_COLOR_BY_TYPE[statType]
		if skillColor then
			trainingBarFill.BackgroundColor3 = skillColor
			-- Attribut zurücksetzen, damit flashElement (aus früheren Aufrufen mit der alten
			-- Farbe gecacht) beim nächsten Aufleuchten wieder zur RICHTIGEN Ruhefarbe zurückkehrt.
			trainingBarFill:SetAttribute("RestColor", nil)
		end
		lastTrainingBarValue = statValue.Value
	end
end)

-- Lässt eine "+X"-Anzeige vom Charakter zum großen Trainings-Balken unten fliegen,
-- spielt bei Ankunft einen Sound ab.
local function spawnFlyingTrainPoint(amount, statType)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local camera = Workspace.CurrentCamera
	if not head or not camera then
		return
	end

	local key = statType .. "Power" -- "Arm" -> "ArmPower" usw., passend zu statBars
	local ui = statBars[key]
	if not ui then
		return
	end

	-- Nur für die ANZEIGE: Körper-Increments sind serverseitig absichtlich sehr klein
	-- (siehe TRAINING_SLOWDOWN in TrainingHandler.lua), damit "+0.0" nicht wie ein Fehler
	-- aussieht wird hier rein kosmetisch hochskaliert -- der tatsächliche, im Hintergrund
	-- verrechnete Fortschritt bleibt davon komplett unberührt.
	local displayAmount = amount
	if statType == "Body" then
		displayAmount = amount * 100
	end

	-- Ab jetzt läuft eine Animation für diesen Stat -- das automatische Live-Update in
	-- updateLevelBar() lässt diesen Balken bis zur Ankunft in Ruhe.
	isAnimatingStat[key] = true

	local jitter = Vector3.new(math.random(-15, 15) / 10, math.random(0, 15) / 10, math.random(-15, 15) / 10)
	local screenPoint = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 3, 0) + jitter)

	-- Phase 1: seitlicher Sprungversatz (mal links, mal rechts), gleiches Prinzip wie
	-- bei spawnFlyingEnergy.
	local sideJump = (math.random(0, 1) == 0 and -1 or 1) * math.random(100, 180)
	local poppedPosition = UDim2.new(0, screenPoint.X + sideJump, 0, screenPoint.Y - 48)

	local pointLabel = Instance.new("TextLabel")
	pointLabel.Name = "FlyingTrainPoint"
	pointLabel.Size = UDim2.new(0, 0, 0, 0) -- startet unsichtbar klein, für den Pop-Effekt
	pointLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	pointLabel.Position = UDim2.new(0, screenPoint.X + sideJump * 0.3, 0, screenPoint.Y - 18)
	pointLabel.BackgroundTransparency = 1
	pointLabel.Font = Enum.Font.LuckiestGuy
	pointLabel.TextScaled = true
	pointLabel.Text = "+" .. string.format("%.1f", displayAmount)
	pointLabel.TextColor3 = Color3.fromRGB(90, 220, 130)
	pointLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	pointLabel.TextStrokeTransparency = 0
	pointLabel.ZIndex = 51
	pointLabel.Parent = screenGui

	-- Phase 1: seitlich hüpfen + auf volle Größe aufpoppen (Überschwung-Easing)
	local popTween = TweenService:Create(
		pointLabel,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 84, 0, 40), Position = poppedPosition }
	)

	popTween.Completed:Connect(function()
		-- Phase 2: kurz verweilen, damit man die Zahl lesen kann
		task.delay(0.35, function()
			if not pointLabel.Parent then
				return
			end

			-- Phase 3: erst jetzt nach unten zur Trainings-Progressbar fliegen (die im
			-- Trainings-Panel während der aktiven Session sichtbare Leiste), statt zum
			-- Kraft-Balken oben unter dem Level.
			local targetPosition = UDim2.new(
				0,
				trainingBarBackground.AbsolutePosition.X + trainingBarBackground.AbsoluteSize.X / 2,
				0,
				trainingBarBackground.AbsolutePosition.Y + trainingBarBackground.AbsoluteSize.Y / 2
			)

			local flightTween = TweenService:Create(
				pointLabel,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = targetPosition, TextTransparency = 0.4, TextStrokeTransparency = 0.4 }
			)

			flightTween.Completed:Connect(function()
				pointLabel:Destroy()
				if trainPointSound.SoundId ~= "" and trainPointSound.SoundId ~= "rbxassetid://0" then
					trainPointSound.TimePosition = 0
					trainPointSound:Play()
				end

				-- Erst JETZT die Balken tatsächlich aktualisieren + aufleuchten lassen.
				local capAttribute = "StatCap"
				if key == "ArmPower" then
					capAttribute = "ArmStatCap"
				elseif key == "LegPower" then
					capAttribute = "LegStatCap"
				end
				local cap = math.max(player:GetAttribute(capAttribute) or 1, 1)
				local statValue = player:FindFirstChild(key)
				local value = statValue and statValue.Value or 0
				local statRatio = math.clamp(value / cap, 0, 1)
				ui.fill.Size = UDim2.new(statRatio, 0, 1, 0)

				flashElement(ui.fill, Color3.new(1, 1, 1))
				glowFlashElement(ui.fill, Color3.fromRGB(255, 255, 200))

				-- Trainings-Panel-Leiste (falls gerade dieses Training aktiv ist) ebenfalls
				-- erst jetzt aktualisieren + aufleuchten lassen, statt live jeden Frame.
				if trainingBarFill then
					trainingBarFill.Size = UDim2.new(statRatio, 0, 1, 0)
					flashElement(trainingBarFill, Color3.new(1, 1, 1))
					glowFlashElement(trainingBarFill, Color3.fromRGB(255, 255, 150))
					lastTrainingBarValue = value
				end

				isAnimatingStat[key] = false
				lastStatValues[key] = value
			end)

			flightTween:Play()
		end)
	end)

	popTween:Play()
end

TrainPointEvent.OnClientEvent:Connect(function(statType, amount)
	spawnFlyingTrainPoint(amount, statType)
end)

-- ===== Update-Funktionen =====
local function updateCoinsLabel()
	if isAnimatingCoins then
		return -- Zähler wird gerade von der Flug-Animation gesteuert
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats and leaderstats:FindFirstChild("Coins") then
		coinsLabel.Text = "💰 " .. NumberFormat.Format(leaderstats.Coins.Value)
	end
end

-- Zählt den Coins-Text weich von "fromValue" zu "toValue" hoch.
local function animateCoinCount(fromValue, toValue)
	isAnimatingCoins = true
	local duration = 0.5
	local startTime = os.clock()

	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
		local current = math.floor(fromValue + (toValue - fromValue) * alpha)
		coinsLabel.Text = "💰 " .. NumberFormat.Format(current)

		if alpha >= 1 then
			connection:Disconnect()
			isAnimatingCoins = false
			coinsLabel.Text = "💰 " .. NumberFormat.Format(toValue)
		end
	end)
end

-- Lässt EINE Münze vom Ort des zerstörten Hauses zum Coins-Zähler fliegen.
-- Ruft onArrive() auf, sobald sie angekommen ist (Cash-Sound + Zähler übernimmt der Aufrufer).
local function spawnFlyingCoin(worldPosition, onArrive)
	local camera = workspace.CurrentCamera
	if not camera then
		onArrive()
		return
	end

	-- kleiner zufälliger Versatz, damit mehrere Münzen nicht exakt übereinanderliegen
	local jitter = Vector3.new(math.random(-15, 15) / 10, math.random(0, 15) / 10, math.random(-15, 15) / 10)
	local screenPoint = camera:WorldToViewportPoint(worldPosition + Vector3.new(0, 3, 0) + jitter)

	-- Seitlicher Sprungversatz (mal links, mal rechts) -- gleiches Prinzip wie bei der
	-- fliegenden Energie: erst hüpfen + aufpoppen, dann verweilen, dann erst losfliegen.
	local sideJump = (math.random(0, 1) == 0 and -1 or 1) * math.random(100, 180)
	local poppedPosition = UDim2.new(0, screenPoint.X + sideJump - 20, 0, screenPoint.Y - 48)

	-- Gezeichnete Münze statt Emoji-Text, damit sie unabhängig von Schriftart-Emoji-Support
	-- immer sichtbar ist (runder gelber Kreis mit schwarzem Comic-Rand, wie die Coins-Anzeige).
	local coinIcon = Instance.new("Frame")
	coinIcon.Name = "FlyingCoin"
	coinIcon.Size = UDim2.new(0, 0, 0, 0) -- startet unsichtbar klein, für den Pop-Effekt
	coinIcon.Position = UDim2.new(0, screenPoint.X + sideJump * 0.3, 0, screenPoint.Y - 20)
	coinIcon.BackgroundColor3 = Color3.fromRGB(255, 205, 30)
	coinIcon.ZIndex = 50
	coinIcon.Parent = screenGui

	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(1, 0) -- 1,0 = perfekter Kreis
	coinCorner.Parent = coinIcon

	local coinStroke = Instance.new("UIStroke")
	coinStroke.Thickness = 3
	coinStroke.Color = Color3.fromRGB(0, 0, 0)
	coinStroke.Parent = coinIcon

	local coinSymbol = Instance.new("TextLabel")
	coinSymbol.Size = UDim2.new(1, 0, 1, 0)
	coinSymbol.BackgroundTransparency = 1
	coinSymbol.Font = Enum.Font.LuckiestGuy
	coinSymbol.TextScaled = true
	coinSymbol.Text = "$"
	coinSymbol.TextColor3 = Color3.fromRGB(90, 55, 0)
	coinSymbol.ZIndex = 51
	coinSymbol.Parent = coinIcon

	-- Phase 1: seitlich hüpfen + auf volle Größe aufpoppen (Überschwung-Easing)
	local popTween = TweenService:Create(
		coinIcon,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 40, 0, 40), Position = poppedPosition }
	)

	popTween.Completed:Connect(function()
		-- Phase 2: kurz verweilen
		task.delay(0.3, function()
			if not coinIcon.Parent then
				return
			end

			-- Phase 3: erst jetzt Richtung Coins-Anzeige fliegen
			local targetPosition = UDim2.new(
				0,
				coinsLabel.AbsolutePosition.X + coinsLabel.AbsoluteSize.X / 2 - 20,
				0,
				coinsLabel.AbsolutePosition.Y + coinsLabel.AbsoluteSize.Y / 2 - 20
			)

			local flightTween = TweenService:Create(
				coinIcon,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = targetPosition, Rotation = 360 }
			)

			flightTween.Completed:Connect(function()
				coinIcon:Destroy()
				onArrive()
			end)

			flightTween:Play()
		end)
	end)

	popTween:Play()
end

-- Lässt mehrere Münzen fliegen (eine pro 10 Coins, mindestens eine), leicht zeitversetzt.
-- Jede Münze spielt bei Ankunft den Cash-Sound; der Zähler zählt einmal am Ende komplett hoch.
local COINS_PER_FLYING_COIN = 100
local COIN_LAUNCH_DELAY = 0.08 -- Sekunden zwischen den einzelnen Münzen

local function flyCoinsToHud(worldPosition, amount)
	local coinCount = math.max(1, math.floor(amount / COINS_PER_FLYING_COIN))
	local arrivedCount = 0

	local leaderstats = player:FindFirstChild("leaderstats")
	local newValue = (leaderstats and leaderstats:FindFirstChild("Coins")) and leaderstats.Coins.Value or amount
	local oldValue = math.max(newValue - amount, 0)

	for i = 1, coinCount do
		task.delay((i - 1) * COIN_LAUNCH_DELAY, function()
			spawnFlyingCoin(worldPosition, function()
				if cashSound.SoundId ~= "" and cashSound.SoundId ~= "rbxassetid://0" then
					cashSound.TimePosition = 0
					cashSound:Play()
				end

				arrivedCount += 1
				if arrivedCount == coinCount then
					animateCoinCount(oldValue, newValue)
					flashElement(coinsLabel, Color3.fromRGB(255, 255, 180))
				end
			end)
		end)
	end
end

CoinsEarnedEvent.OnClientEvent:Connect(function(amount, worldPosition)
	flyCoinsToHud(worldPosition, amount)
end)

-- ===== Energie fliegt zum Levelbalken (analog zu den fliegenden Münzen) =====
-- Drei Phasen für bessere Lesbarkeit: 1) seitlich hüpfen + aufpoppen (klein -> groß mit
-- Überschwung), 2) kurz verweilen, damit man die Zahl auch wirklich lesen kann, 3) erst
-- danach Richtung Levelbalken fliegen.
local function spawnFlyingEnergy(worldPosition, amount, energyType, onArrive)
	local camera = workspace.CurrentCamera
	if not camera then
		onArrive()
		return
	end

	local visual = ENERGY_TYPE_VISUALS[energyType] or DEFAULT_ENERGY_VISUAL

	local jitter = Vector3.new(math.random(-15, 15) / 10, math.random(0, 15) / 10, math.random(-15, 15) / 10)
	local screenPoint = camera:WorldToViewportPoint(worldPosition + Vector3.new(0, 3, 0) + jitter)

	-- Seitlicher Sprungversatz (mal links, mal rechts) -- weg vom direkten Ursprungspunkt,
	-- damit die Zahl nicht mitten im Getümmel der Quelle/anderer Effekte hängt.
	local sideJump = (math.random(0, 1) == 0 and -1 or 1) * math.random(100, 180)
	local poppedPosition = UDim2.new(0, screenPoint.X + sideJump, 0, screenPoint.Y - 48)

	-- Kein Hintergrund/Kreis mehr -- nur der Text selbst (Icon + Energiewert), mit
	-- schwarzem Textumriss für Lesbarkeit, Farbe passend zum tatsächlichen Energie-Typ.
	local energySymbol = Instance.new("TextLabel")
	energySymbol.Name = "FlyingEnergy"
	energySymbol.Size = UDim2.new(0, 0, 0, 0) -- startet unsichtbar klein, für den Pop-Effekt
	energySymbol.AnchorPoint = Vector2.new(0.5, 0.5)
	energySymbol.Position = UDim2.new(0, screenPoint.X + sideJump * 0.3, 0, screenPoint.Y - 18)
	energySymbol.BackgroundTransparency = 1
	energySymbol.Font = Enum.Font.LuckiestGuy
	energySymbol.TextScaled = true
	energySymbol.Text = visual.icon .. NumberFormat.Format(amount)
	energySymbol.TextColor3 = visual.color
	energySymbol.TextStrokeColor3 = Color3.new(0, 0, 0)
	energySymbol.TextStrokeTransparency = 0
	energySymbol.ZIndex = 51
	energySymbol.Parent = screenGui

	-- Phase 1: seitlich hüpfen + auf volle Größe aufpoppen (Überschwung-Easing)
	local popTween = TweenService:Create(
		energySymbol,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 84, 0, 44), Position = poppedPosition }
	)

	popTween.Completed:Connect(function()
		-- Phase 2: kurz verweilen, damit man die Zahl lesen kann
		task.delay(0.35, function()
			if not energySymbol.Parent then
				return
			end

			-- Phase 3: erst jetzt Richtung Levelbalken fliegen -- Ziel ist NICHT die Mitte
			-- des Levelrahmens, sondern der aktuelle Füllstand des Fortschrittsbalkens
			-- (rechter Rand von barFill), so sieht man genau, wo die Energie einfließt.
			local targetPosition = UDim2.new(
				0,
				barFill.AbsolutePosition.X + barFill.AbsoluteSize.X,
				0,
				barFill.AbsolutePosition.Y + barFill.AbsoluteSize.Y / 2
			)

			local flightTween = TweenService:Create(
				energySymbol,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = targetPosition }
			)

			flightTween.Completed:Connect(function()
				energySymbol:Destroy()
				if energyArriveSound.SoundId ~= "" and energyArriveSound.SoundId ~= "rbxassetid://0" then
					energyArriveSound.TimePosition = 0
					energyArriveSound:Play()
				end
				onArrive()
			end)

			flightTween:Play()
		end)
	end)

	popTween:Play()
end

-- Statt schnell aufeinanderfolgende Events zu VERWERFEN (das hat bei vielen gleichzeitig
-- beitragenden Energiequellen dazu geführt, dass man nur EINE von z.B. 16 Animationen
-- gesehen hat, obwohl alle Punkte korrekt gezählt wurden): jetzt werden sie in eine
-- Warteschlange gestellt und leicht zeitversetzt nacheinander abgespielt, damit wirklich
-- jeder einzelne Wert sichtbar wird, ohne dass alle exakt gleichzeitig übereinander liegen.
local ENERGY_FLIGHT_STAGGER = 0.08 -- Sekunden Abstand zwischen zwei Animationen
local energyQueue = {} -- { {sourcePosition, amount}, ... }
local isProcessingEnergyQueue = false

local function processEnergyQueue()
	if isProcessingEnergyQueue then
		return
	end
	isProcessingEnergyQueue = true

	task.spawn(function()
		while #energyQueue > 0 do
			local entry = table.remove(energyQueue, 1)
			-- WICHTIG: onArrive löst jetzt tatsächlich das Aufleuchten + Hochzählen der
			-- Level-Anzeige aus -- vorher war das leer, und die Anzeige hat stattdessen
			-- sofort (unabhängig von der Flug-Animation) auf die Server-Werteänderung
			-- reagiert, was sich unsynchronisiert anfühlte.
			spawnFlyingEnergy(entry.sourcePosition, entry.amount, entry.energyType, function()
				advanceXPBar(entry.amount)
			end)
			task.wait(ENERGY_FLIGHT_STAGGER)
		end
		isProcessingEnergyQueue = false
	end)
end

local MAX_ENERGY_QUEUE_LENGTH = 20 -- Sicherheitsgrenze, falls extrem viele Quellen gleichzeitig feuern

EnergyAbsorbEvent.OnClientEvent:Connect(function(sourcePosition, energyType, amount)
	if #energyQueue >= MAX_ENERGY_QUEUE_LENGTH then
		return -- Sicherheitsnetz gegen unrealistisch lange Nachlauf-Animationen
	end
	table.insert(energyQueue, { sourcePosition = sourcePosition, amount = amount, energyType = energyType })
	processEnergyQueue()
end)

-- displayedXP ist der Wert, den der Balken TATSÄCHLICH anzeigt -- bewusst getrennt vom
-- echten Server-Wert (player.XP), damit der Balken erst beim EINTREFFEN der fliegenden
-- Energie-Animation hochzählt (siehe advanceXPBar), statt sofort bei der
-- Server-Werteänderung zu springen.
local displayedXP = nil

-- Zählt den Balken um genau "amount" hoch (mit Aufleucht-Effekt) -- wird NUR vom
-- onArrive-Callback der Flug-Animation aufgerufen, nie direkt bei Server-Änderungen.
function advanceXPBar(amount)
	local xpNeededValue = player:FindFirstChild("XPNeeded")
	local xpValue = player:FindFirstChild("XP")
	if not xpNeededValue or not xpValue then
		return
	end
	if displayedXP == nil then
		displayedXP = xpValue.Value
	end
	-- Nie über den tatsächlichen Server-Wert hinaus zählen (Sicherheitsnetz, falls die
	-- Animation aus irgendeinem Grund öfter ankommt als erwartet).
	displayedXP = math.min(displayedXP + amount, xpValue.Value)

	local needed = math.max(xpNeededValue.Value, 1)
	barFill.Size = UDim2.new(math.clamp(displayedXP / needed, 0, 1), 0, 1, 0)
	flashElement(barFill, Color3.fromRGB(255, 255, 200))
	glowFlashElement(barFill, Color3.fromRGB(255, 255, 150))
end

function updateLevelBar()
	local leaderstats = player:FindFirstChild("leaderstats")
	local xpValue = player:FindFirstChild("XP")
	local xpNeededValue = player:FindFirstChild("XPNeeded")
	if not leaderstats or not xpValue or not xpNeededValue then
		return
	end

	levelLabel.Text = "⭐ Level " .. leaderstats.Level.Value

	-- Bei einem ECHTEN Sprung (Level-Up, bei dem XP zurückgesetzt/übertragen wird, oder
	-- Debug-Reset) sofort synchronisieren, ohne Aufleucht-Animation -- eine ausstehende
	-- Flug-Animation würde sonst versuchen, über den neuen (kleineren) Zielwert
	-- hinauszuzählen. Im Normalfall (Energie fliegt gerade noch) NICHT eingreifen, das
	-- übernimmt advanceXPBar() beim Eintreffen.
	if displayedXP == nil or xpValue.Value < displayedXP then
		displayedXP = xpValue.Value
		local needed = math.max(xpNeededValue.Value, 1)
		barFill.Size = UDim2.new(math.clamp(displayedXP / needed, 0, 1), 0, 1, 0)
		print("[Kaiju-Debug-Client] updateLevelBar SYNC: Level=", leaderstats.Level.Value, "XP=", xpValue.Value, "XPNeeded=", xpNeededValue.Value, "ratio=", displayedXP / needed)
	end

	-- Cap für die 3 Kraft-Werte -- Arm/Bein nutzen den (um Faktor 100 größeren)
	-- ArmStatCap/LegStatCap, Körper den normalen StatCap.
	for key, ui in pairs(statBars) do
		if not isAnimatingStat[key] then -- läuft gerade eine Flug-Animation, hier nicht eingreifen
			local capAttribute = "StatCap"
			if key == "ArmPower" then
				capAttribute = "ArmStatCap"
			elseif key == "LegPower" then
				capAttribute = "LegStatCap"
			end
			local cap = math.max(player:GetAttribute(capAttribute) or 1, 1)
			local statValue = player:FindFirstChild(key)
			local value = statValue and statValue.Value or 0
			local statRatio = math.clamp(value / cap, 0, 1)
			ui.fill.Size = UDim2.new(statRatio, 0, 1, 0)

			-- Körper-Wert bekommt dieselbe x100-Anzeige-Skalierung wie die Flug-Animation
			-- (spawnFlyingTrainPoint) -- sonst würden Balken-Label und Flug-Zahlen nicht
			-- zusammenpassen (Körper wächst serverseitig absichtlich sehr langsam).
			local displayValue, displayCap = value, cap
			if key == "BodyPower" then
				displayValue, displayCap = value * 100, cap * 100
			end
			ui.label.Text = ui.displayName .. ": " .. math.floor(displayValue) .. "/" .. math.floor(displayCap)
			lastStatValues[key] = value
		end
	end
end

-- Vorschau des Skins. Rahmen, Einpassen und Drehen macht ModelPreviewUtils -- dort steht
-- auch, warum die Figur erst mittig ausgerichtet werden muss.
--
-- ===== Warum nicht mehr die feste Kameradistanz =====
-- Frueher stand die Kamera fuer alle sechs Stufen gleich weit weg. Das war Absicht: alle
-- sechs sind derselbe Avatar in sechs Groessen (SkinsConfig tauscht kein Mesh), und die
-- feste Kamera machte diesen Unterschied sichtbar. Der Preis war, dass der Baby Kaiju als
-- Punkt in einem leeren Rahmen stand -- ein Steckbrief, der nichts zeigt. Die Groesse geht
-- nicht verloren: der Scale-Balken im Steckbrief nennt sie als Zahl UND als Vergleich zum
-- getragenen Skin.
local function buildSkinPreview(container, skin, revealed)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("ViewportFrame") or child:IsA("TextLabel") or child.Name == "PreviewGlow" then
			child:Destroy()
		end
	end

	-- Auch fuer Platzhalter aufgerufen, dann ist `skin` nil -- dieser Zweig braucht ihn nicht.
	if not revealed then
		ModelPreviewUtils.ShowPlaceholder(container)
		return
	end

	local pack = Workspace:FindFirstChild("R15AvatarPack")
	local template = pack and pack:FindFirstChildWhichIsA("Model")
	if not template then
		local missing = Instance.new("TextLabel")
		missing.Size = UDim2.new(1, 0, 1, 0)
		missing.BackgroundTransparency = 1
		missing.TextColor3 = Color3.fromRGB(170, 160, 145)
		missing.Text = "no preview"
		missing.Parent = container
		UiTypography.Body(missing)
		return
	end

	local viewport = ModelPreviewUtils.CreateViewport(container, 2)

	local preview
	local ok = pcall(function()
		local model = template:Clone()
		model:ScaleTo(skin.Scale or 1)
		model.Parent = viewport
		ModelPreviewUtils.Fit(viewport, model, container)
		-- Nachgebautes Leuchten aus den Neon-Teilen des Modells. Bei den heutigen
		-- Kaiju-Stufen -- schlichte Avatare ohne Neon -- findet sich keine Farbe, und es
		-- erscheint bewusst kein Schein. Erst echte Modelle bringen einen mit.
		ModelPreviewUtils.AddGlow(container, ModelPreviewUtils.FindGlowColor(model), 1)
		preview = model
	end)
	if not ok then
		viewport:Destroy()
		return
	end

	ModelPreviewUtils.Spin(preview)
end

-- Welcher Skin steht gerade im Steckbrief. Beim Oeffnen der getragene.
local selectedSkinId = nil

-- Ist statt eines echten Skins ein Platzhalter gewaehlt, steht er hier:
-- { faction = <Eintrag aus SkinsConfig.Factions>, index = <Nummer innerhalb der Fraktion> }.
-- Jaeger und Ronin haben noch keine Skins; ihre Plaetze sind trotzdem sichtbar, damit der
-- Bildschirm die Luecke zeigt statt sie zu verschweigen -- so haelt es das Archiv auch.
local selectedPending = nil

-- Hoechstwerte ueber alle Skins -- die Balken zeigen jeden Wert im Verhaeltnis zum
-- staerksten. Einmal berechnet, die Liste aendert sich zur Laufzeit nicht.
local STAT_MAX = { Health = 0, WalkSpeed = 0, Scale = 0 }
for _, skin in ipairs(SkinsConfig.Skins) do
	for key in pairs(STAT_MAX) do
		STAT_MAX[key] = math.max(STAT_MAX[key], skin[key] or 0)
	end
end

-- Die Level-Obergrenze steigt je GEKAUFTEM Skin um 10 (PlayerSetup.getLevelCap,
-- LEVELS_PER_SKIN_TIER). Der Startskin ist kostenlos und zaehlt nicht mit -- deshalb
-- ergibt sich die Grenze aus der Position in der Liste, nicht aus der Id.
local function levelRangeFor(skin)
	if (skin.Cost or 0) <= 0 then
		return nil
	end
	local paidIndex = 0
	for _, other in ipairs(SkinsConfig.Skins) do
		if (other.Cost or 0) > 0 then
			paidIndex += 1
			if other.Id == skin.Id then
				break
			end
		end
	end
	local cap = 10 * (1 + paidIndex)
	return (cap - 9) .. " to " .. cap
end

local function refreshDetail()
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	local leaderstats = player:FindFirstChild("leaderstats")
	local equippedValue = player:FindFirstChild("EquippedSkin")
	if not unlockedFolder or not leaderstats or not equippedValue then
		return
	end
	if selectedPending then
		local faction = selectedPending.faction
		detailName.Text = string.format("%s %s %d", faction.Icon, faction.Label, selectedPending.index)
		detailRole.Text = "Not built yet."
		detailStrength.Text = string.format(
			"%s skins arrive with %s. %s",
			faction.Label, faction.Chapter, faction.UnlockHint or "")
		detailBonus.Visible = false
		-- Balken ausblenden statt auf null setzen: leere Balken haetten "dieser Skin hat
		-- keine Kraft" behauptet, richtig ist "es gibt ihn noch nicht".
		for _, row in pairs(statRows) do
			row.row.Visible = false
		end
		buildSkinPreview(detailViewport, nil, false)
		detailAction.Text = "🔒 " .. faction.Chapter
		detailAction.BackgroundColor3 = Color3.fromRGB(120, 120, 132)
		detailAction.AutoButtonColor = false
		return
	end
	for _, row in pairs(statRows) do
		row.row.Visible = true
	end

	if selectedSkinId == nil then
		selectedSkinId = equippedValue.Value
	end

	local skin = SkinsConfig.GetSkinById(selectedSkinId)
	local equipped = SkinsConfig.GetSkinById(equippedValue.Value)
	if not skin then
		return
	end

	local isUnlocked = unlockedFolder:FindFirstChild("Skin_" .. skin.Id) ~= nil
	local isEquipped = equippedValue.Value == skin.Id
	local meetsLevel = leaderstats.Level.Value >= skin.RequiredLevel
	local canAfford = leaderstats.Coins.Value >= skin.Cost

	detailName.Text = skin.Name
	detailRole.Text = skin.Role or ""
	detailStrength.Text = skin.Strength or ""

	local range = levelRangeFor(skin)
	detailBonus.Visible = range ~= nil and not isUnlocked
	if range then
		detailBonus.Text = "  ⬆  Unlocks levels " .. range
	end

	for key, row in pairs(statRows) do
		local value = skin[key] or 0
		local maximum = STAT_MAX[key]
		row.fill.Size = UDim2.new(maximum > 0 and (value / maximum) or 0, 0, 1, 0)
		if equipped and equipped.Id ~= skin.Id then
			local diff = value - (equipped[key] or 0)
			row.delta.Text = string.format("%s  (%s%s)", tostring(value), diff >= 0 and "+" or "", tostring(diff))
			row.delta.TextColor3 = diff >= 0 and Color3.fromRGB(40, 140, 60) or Color3.fromRGB(180, 60, 60)
		else
			row.delta.Text = tostring(value)
			row.delta.TextColor3 = Color3.fromRGB(165, 165, 180)
		end
	end

	-- Vorschau: gesperrte Skins zeigen ein Fragezeichen, sonst das Modell.
	buildSkinPreview(detailViewport, skin, isUnlocked or (meetsLevel and canAfford))

	-- EIN Knopf, der sich anpasst. Kaufen und Anlegen sind fuer einen noch nicht
	-- besessenen Skin ohnehin ein Vorgang -- der Server ruestet nach dem Kauf sofort aus.
	if isEquipped then
		detailAction.Text = "✅ Equipped"
		detailAction.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
		detailAction.AutoButtonColor = false
	elseif isUnlocked then
		detailAction.Text = "👕 Wear"
		detailAction.BackgroundColor3 = Color3.fromRGB(70, 150, 235)
		detailAction.AutoButtonColor = true
	elseif not meetsLevel then
		detailAction.Text = "🔒 Level " .. skin.RequiredLevel .. " required"
		detailAction.BackgroundColor3 = Color3.fromRGB(150, 90, 90)
		detailAction.AutoButtonColor = false
	elseif not canAfford then
		detailAction.Text = "🔒 " .. skin.Cost .. " coins needed"
		detailAction.BackgroundColor3 = Color3.fromRGB(160, 160, 160)
		detailAction.AutoButtonColor = false
	else
		detailAction.Text = "💰 Buy for " .. skin.Cost
		detailAction.BackgroundColor3 = Color3.fromRGB(255, 180, 40)
		detailAction.AutoButtonColor = true
	end
end

detailAction.MouseButton1Click:Connect(function()
	if selectedPending then
		return -- ein Platzhalter ist nicht kaufbar
	end
	local skin = SkinsConfig.GetSkinById(selectedSkinId)
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	if not skin or not unlockedFolder then
		return
	end
	if unlockedFolder:FindFirstChild("Skin_" .. skin.Id) then
		-- EquipSkinEvent liegt seit jeher vollstaendig im Server und wurde vom Client NIE
		-- gefeuert -- ein getrenntes Anlegen gab es bisher nicht.
		EquipSkinEvent:FireServer(skin.Id)
	else
		PurchaseSkinEvent:FireServer(skin.Id)
	end
end)

local function refreshShop()
	-- AUCH die Ueberschriften wegraeumen, nicht nur die Knoepfe: sie kamen mit der
	-- Gruppierung nach Fraktion dazu und wuerden sich sonst bei jedem Auffrischen doppeln.
	for _, child in ipairs(shopScroll:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local unlockedFolder = player:WaitForChild("UnlockedSkins")
	local leaderstats = player:WaitForChild("leaderstats")
	local equippedSkin = player:WaitForChild("EquippedSkin")

	local order = 0
	for _, faction in ipairs(SkinsConfig.Factions) do
		local skins = SkinsConfig.GetSkinsByFaction(faction.Key)
		local pendingCount = faction.PendingCount or 0
		if #skins == 0 and pendingCount == 0 then
			continue -- eine Fraktion ohne Skins und ohne vorgesehene Plaetze zeigt nichts
		end

		order += 1
		local header = Instance.new("TextLabel")
		header.Name = faction.Key .. "Header"
		header.Size = UDim2.new(1, -4, 0, 26)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.LuckiestGuy
		header.TextScaled = true
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = Color3.fromRGB(255, 205, 90)
		header.Text = faction.Icon .. " " .. faction.Label
		header.LayoutOrder = order
		header.Parent = shopScroll

		for _, skin in ipairs(skins) do
			local isUnlocked = unlockedFolder:FindFirstChild("Skin_" .. skin.Id) ~= nil
			local isEquipped = equippedSkin.Value == skin.Id
			local meetsLevel = leaderstats.Level.Value >= skin.RequiredLevel
			local canAfford = leaderstats.Coins.Value >= skin.Cost

			order += 1
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, -4, 0, 52)
			button.Font = Enum.Font.FredokaOne
			button.TextScaled = true
			button.TextColor3 = Color3.new(1, 1, 1)
			button.LayoutOrder = order
			button.Parent = shopScroll
			applyComicStyle(button, 14, 3)

			if isEquipped then
				button.Text = "✅ " .. skin.Name
				button.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
			elseif isUnlocked then
				button.Text = "👕 Wear " .. skin.Name
				button.BackgroundColor3 = Color3.fromRGB(70, 150, 235)
			elseif not meetsLevel then
				button.Text = "🔒 " .. skin.Name .. " - Level " .. skin.RequiredLevel .. " required"
				button.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
			elseif canAfford then
				button.Text = "💰 " .. skin.Name .. " (" .. skin.Cost .. ")"
				button.BackgroundColor3 = Color3.fromRGB(255, 180, 40)
			else
				button.Text = "🔒 " .. skin.Name .. " (" .. skin.Cost .. ")"
				button.BackgroundColor3 = Color3.fromRGB(160, 160, 160)
			end

			-- Ein Klick WAEHLT nur aus. Gekauft und angelegt wird im Steckbrief.
			button.MouseButton1Click:Connect(function()
				selectedPending = nil
				selectedSkinId = skin.Id
				refreshDetail()
			end)
		end

		-- Vorgesehene, aber noch nicht gebaute Plaetze. Anwaehlbar, damit der Steckbrief
		-- erklaeren kann, woran es haengt -- kaufbar sind sie nicht.
		for index = 1, pendingCount do
			order += 1
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, -4, 0, 52)
			button.Font = Enum.Font.FredokaOne
			button.TextScaled = true
			button.TextColor3 = Color3.fromRGB(200, 200, 210)
			button.BackgroundColor3 = Color3.fromRGB(52, 52, 62)
			button.Text = string.format("? %s %d - %s", faction.Label, index, faction.Chapter)
			button.LayoutOrder = order
			button.Parent = shopScroll
			applyComicStyle(button, 14, 3)

			button.MouseButton1Click:Connect(function()
				selectedPending = { faction = faction, index = index }
				refreshDetail()
			end)
		end
	end

	refreshDetail()
end

-- Erst auf ALLE benötigten Werte warten (blockierend), damit die erste Anzeige garantiert
-- die echten, geladenen Werte zeigt -- statt kurz "Level 0"/"0 Coins" anzuzeigen und erst
-- beim nächsten Ereignis (z.B. erster Schaden) zu korrigieren.
player:WaitForChild("leaderstats")
player:WaitForChild("leaderstats"):WaitForChild("Coins")
player:WaitForChild("leaderstats"):WaitForChild("Level")
player:WaitForChild("XP")
player:WaitForChild("XPNeeded")
player:WaitForChild("LegPower")
player:WaitForChild("ArmPower")
player:WaitForChild("BodyPower")
player:WaitForChild("UnlockedSkins")
player:WaitForChild("EquippedSkin")

updateCoinsLabel()
updateLevelBar()
refreshShop()

player:WaitForChild("leaderstats"):WaitForChild("Coins"):GetPropertyChangedSignal("Value"):Connect(function()
	updateCoinsLabel()
	refreshShop()
end)
player:WaitForChild("leaderstats").Level:GetPropertyChangedSignal("Value"):Connect(function()
	updateLevelBar()
	refreshShop()

-- Beim Oeffnen steht der GETRAGENE Skin im Steckbrief, nicht der zuletzt angetippte.
--
-- MUSS hier unten stehen: selectedSkinId und refreshShop werden erst weiter oben in dieser
-- Datei deklariert. Weiter vorne haetten die Namen auf nicht existierende globale
-- Variablen aufgeloest -- die Zuweisung waere ins Leere gelaufen, ohne Fehlermeldung.
shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if shopFrame.Visible then
		local equippedValue = player:FindFirstChild("EquippedSkin")
		if equippedValue then
			selectedSkinId = equippedValue.Value
		end
		-- Beim Oeffnen immer beim getragenen Skin beginnen. Ohne das haette ein zuletzt
		-- angeklickter Platzhalter die naechste Sitzung des Bildschirms eroeffnet.
		selectedPending = nil
		refreshShop()
	end
end)
	flashElement(statusCluster, Color3.fromRGB(255, 255, 150))
end)
local leaderstatsFolder = player:WaitForChild("leaderstats")
leaderstatsFolder:WaitForChild("Level"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("XP"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("XPNeeded"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("LegPower"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("ArmPower"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("BodyPower"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:GetAttributeChangedSignal("StatCap"):Connect(updateLevelBar)
player:WaitForChild("UnlockedSkins").ChildAdded:Connect(refreshShop)
player:WaitForChild("EquippedSkin"):GetPropertyChangedSignal("Value"):Connect(refreshShop)