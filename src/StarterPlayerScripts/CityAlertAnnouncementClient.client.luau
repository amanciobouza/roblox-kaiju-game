-- VERSION: 2026-08-25 #1
-- FIX: Megacity -> MegaCity (Schreibweise an Studio-Attribut angeglichen)
-- Ort in Studio: StarterPlayerScripts
--
-- Der Alarm-Strang bespielt beide Register der Bildmitte (siehe HudCenterNotice):
--
--   Bei 80 Prozent der Schwelle: die WARNUNG. Kurzer Alarmton, rotes Schild mit der
--   bevorstehenden Gefahr, pulsiert und geht von selbst wieder. Sie stellt das Modul dar;
--   hier steht nur, WANN sie faellt und WAS drinsteht.
--
--   Beim tatsaechlichen Stufenaufstieg: das EREIGNIS -- die grosse Sequenz unten in dieser
--   Datei, mit dem Stufen-Sound wie bisher.
--
-- Fester Zeitplan (~1.5-1.8s), damit das Ereignis wirkt, ohne den Spielfluss anzuhalten:
--
--   0.0s  Ausloeser: kompakte Anzeige zittert, aktueller Stern pulsiert 2x, Boom-Sound
--   0.15s Warnsignal: kurzer roter Rand-Flash, stufenspezifischer Sound startet
--   0.3s  Das Band faehrt auf: Titel der neuen Antwort + Sterne
--   0.55s Der neue Stern wird eingestanzt (Ueberschwung 140->100 Prozent, Screen-Shake,
--         Funken, Schockwelle), Text wechselt auf "ALERT LEVEL X"
--   0.9s  Konsequenz: was diese Antwort bedeutet ("FIRE RESPONSE DEPLOYED" etc.)
--   1.5s  Rueckkehr: schrumpft zur kompakten Anzeige oben rechts
--
-- Stufe 5 bricht bewusst das Muster: kurzer Hitstop, alle Sterne nacheinander,
-- "MAXIMUM ALERT" waechst kurz an.
--
-- Das Band ist ein durchlaessiges rotes Feld ohne Rahmen, das an beiden Enden ausblendet.
-- Bewusst KEIN Panel: ein Kasten mit Rand liest sich als weitere Anzeige, die man abhakt.
-- Das Band liest sich als Stoerung im Bild.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local HudCenterNotice = require(ReplicatedStorage:WaitForChild("HudCenterNotice"))

-- Fuer die Vorwarnung wird die Schwelle der Stadt gebraucht -- der Fortschrittswert ist
-- ein roher Punktestand und sagt ohne sie nichts.
local cityAlertConfigModule = ReplicatedStorage:WaitForChild("CityAlertConfig", 10)
local CityAlertConfig = cityAlertConfigModule and require(cityAlertConfigModule)

local cityAlertValues = ReplicatedStorage:WaitForChild("CityAlertValues", 10)
if not cityAlertValues or not CityAlertConfig then
	warn("[CityAlertAnnouncementClient] CityAlertValues oder CityAlertConfig nicht gefunden (Timeout) -- Ankuendigung bleibt deaktiviert.")
	return
end

local CITY_DISPLAY_NAMES = {
	Village = "Village",
	SmallTown = "Small Town",
	City = "City",
	LargeCity = "Large City",
	MegaCity = "Megacity",
}

-- ===== Pro-Level-Persönlichkeit ===== Sound-IDs sind teilweise Platzhalter (leer) --
-- bitte bei Gelegenheit mit echten Sound-IDs befüllen (Dispatch-Funk, Polizei-Alarm,
-- Militär-Funk, Kriegshorn). Level 4 nutzt bereits die vorhandene Militär-Alarm-ID.
local LEVEL_INFO = {
	[1] = { title = "CITY ALERT", consequence = "", soundId = "" },
	[2] = { title = "EMERGENCY RESPONSE", consequence = "FIRE RESPONSE DEPLOYED", soundId = "" },
	[3] = { title = "SECURITY RESPONSE", consequence = "DEFENSIVE BARRICADES DEPLOYED", soundId = "" },
	[4] = { title = "MILITARY RESPONSE", consequence = "MILITARY FORCES DEPLOYED", soundId = "rbxassetid://93574748731319" },
	[5] = { title = "MAXIMUM ALERT", consequence = "CITY DEFENDER AWAKENED", soundId = "" },
}

-- Kurzer Alarmton fuer die WARNUNG (nicht fuer das Ereignis -- das hat den Ton seiner
-- Stufe). Geborgt vom Barrikaden-Alarm, damit die Warnung ueberhaupt klingt; sie haette
-- sonst keinen eigenen Ton. Wenn es einen eigenen gibt, hier eintragen.
local WARN_SOUND_ID = "rbxassetid://910988901"

local IMPACT_SOUND_ID = "" -- tiefer Boom/Impact beim Trigger (0.0s) -- Platzhalter, bitte befüllen
local STAMP_SOUND_ID = "" -- CLANG/THOOM beim Einstanzen des neuen Sterns (0.55s) -- Platzhalter

-- Feste Schriftgroessen statt TextScaled, wie im ganzen HUD. Die Hoechststufe hebt den
-- Titel nicht mehr ueber die Kaestchenhoehe, sondern ueber die Schriftgroesse selbst an --
-- dasselbe Bild, aber ohne dass die Groesse davon abhaengt, wie hoch gerade ein Kasten ist.
local TITEL_GROESSE = 30
local TITEL_GROESSE_MAX = 42

local COOLDOWN_SECONDS = 5 -- verhindert Spam, falls der Fortschritt durch Zerfall/Eskalation hin- und herpendelt

-- ===== ScreenGui-Grundgerüst =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CityAlertAnnouncementGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

-- Rand-Flash (0.15s): volle Bildschirmgrösse, radialer Farbverlauf von den Rändern her.
local edgeFlash = Instance.new("Frame")
edgeFlash.Name = "EdgeFlash"
edgeFlash.Size = UDim2.new(1, 0, 1, 0)
edgeFlash.BackgroundTransparency = 1
edgeFlash.BorderSizePixel = 0
edgeFlash.ZIndex = 40
edgeFlash.Parent = screenGui

local edgeFlashStroke = Instance.new("UIStroke")
edgeFlashStroke.Thickness = 60
edgeFlashStroke.Transparency = 1
edgeFlashStroke.Color = HudChrome.Color.Danger
edgeFlashStroke.Parent = edgeFlash

-- Zentrale Ankündigung.
local banner = Instance.new("Frame")
banner.Name = "AnnouncementBanner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, 0.35, 0)
banner.Size = UDim2.new(0, 720, 0, 182)
banner.BackgroundColor3 = HudChrome.Color.Danger
banner.BackgroundTransparency = 1
banner.BorderSizePixel = 0
banner.Visible = false
banner.ZIndex = 41
banner.Parent = screenGui

-- KEIN Feld mit Rahmen. Das war der erste Versuch, und er machte aus der Ankuendigung
-- "noch eine Anzeige mit Bedeutung" -- etwas, das man liest und abhakt.
--
-- Stattdessen ein durchlaessiges rotes Band, das an beiden Enden ins Nichts auslaeuft.
-- Ohne Kante gibt es nichts, was als Kasten gelesen werden koennte; was bleibt, ist eine
-- Stoerung im Bild. Der Verlauf macht genau das: deckend in der Mitte, an den Raendern
-- durchsichtig.
local bannerVerlauf = Instance.new("UIGradient")
bannerVerlauf.Rotation = 0
bannerVerlauf.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.22, 0),
	NumberSequenceKeypoint.new(0.78, 0),
	NumberSequenceKeypoint.new(1, 1),
})
bannerVerlauf.Parent = banner

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, -24, 0, 40)
titleLabel.Position = UDim2.new(0, 12, 0, 10)
titleLabel.BackgroundTransparency = 1
titleLabel.ZIndex = 42
titleLabel.Text = ""
titleLabel.Parent = banner
HudChrome.Label(titleLabel, TITEL_GROESSE)

-- Sterne-Reihe.
local MAX_BANNER_STARS = 5
local starsContainer = Instance.new("Frame")
starsContainer.Name = "StarsContainer"
starsContainer.Size = UDim2.new(1, -24, 0, 56)
starsContainer.Position = UDim2.new(0, 12, 0, 50)
starsContainer.BackgroundTransparency = 1
starsContainer.ZIndex = 42
starsContainer.Parent = banner

local starsLayout = Instance.new("UIListLayout")
starsLayout.FillDirection = Enum.FillDirection.Horizontal
starsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
starsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
starsLayout.Padding = UDim.new(0, 6)
starsLayout.Parent = starsContainer

local starLabels = {}
for i = 1, MAX_BANNER_STARS do
	local star = Instance.new("TextLabel")
	star.Name = "Star" .. i
	star.Size = UDim2.new(0, 48, 1, 0)
	star.BackgroundTransparency = 1
	star.Font = Enum.Font.GothamBold
	star.TextScaled = true
	star.TextColor3 = HudChrome.Color.Ready
	star.TextStrokeTransparency = 1
	star.ZIndex = 42
	star.Text = "\u{2605}"
	star.Visible = false
	star.LayoutOrder = i
	star.Parent = starsContainer
	starLabels[i] = star
end

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelLabel"
levelLabel.Size = UDim2.new(1, -24, 0, 24)
levelLabel.Position = UDim2.new(0, 12, 0, 112)
levelLabel.BackgroundTransparency = 1
levelLabel.ZIndex = 42
levelLabel.Text = ""
levelLabel.Parent = banner
HudChrome.Number(levelLabel, 18)
levelLabel.TextColor3 = HudChrome.Color.Danger

local consequenceLabel = Instance.new("TextLabel")
consequenceLabel.Name = "ConsequenceLabel"
consequenceLabel.Size = UDim2.new(1, -24, 0, 26)
consequenceLabel.Position = UDim2.new(0, 12, 0, 142)
consequenceLabel.BackgroundTransparency = 1
consequenceLabel.TextTransparency = 1
consequenceLabel.ZIndex = 42
consequenceLabel.Text = ""
consequenceLabel.Parent = banner
HudChrome.Label(consequenceLabel, 17)
consequenceLabel.TextColor3 = HudChrome.Color.Ready

-- Shockwave-Ring (0.55s) -- ein sich ausdehnender, ausblendender Kreis-Rand.
local shockwaveRing = Instance.new("Frame")
shockwaveRing.Name = "ShockwaveRing"
shockwaveRing.AnchorPoint = Vector2.new(0.5, 0.5)
shockwaveRing.Position = UDim2.new(0.5, 0, 0, 78)
shockwaveRing.Size = UDim2.new(0, 10, 0, 10)
shockwaveRing.BackgroundTransparency = 1
shockwaveRing.ZIndex = 41
shockwaveRing.Parent = banner

local shockwaveStroke = Instance.new("UIStroke")
shockwaveStroke.Thickness = 4
shockwaveStroke.Color = HudChrome.Color.Ready
shockwaveStroke.Transparency = 1
shockwaveStroke.Parent = shockwaveRing

local shockwaveCorner = Instance.new("UICorner")
shockwaveCorner.CornerRadius = UDim.new(1, 0)
shockwaveCorner.Parent = shockwaveRing

-- Funken-Partikel für den Stanz-Moment.
local sparkContainer = Instance.new("Frame")
sparkContainer.Name = "SparkContainer"
sparkContainer.Size = UDim2.new(1, 0, 1, 0)
sparkContainer.BackgroundTransparency = 1
sparkContainer.ZIndex = 43
sparkContainer.Parent = banner

local sounds = {}
local function playSound(soundId, volume)
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then
		return
	end
	local sound = sounds[soundId]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Parent = screenGui
		sounds[soundId] = sound
	end
	sound.Volume = volume or 0.8
	sound:Play()
end

-- [cityName] = Zeitpunkt (os.clock()) der letzten Ankündigung -- für den Cooldown.
local lastAnnouncedAt = {}
local lastKnownLevel = {}
local isAnimating = false

-- Erzeugt einen kurzen radialen Funken-Ausstoss am Stanz-Punkt.
local function emitStampSparks(fromPosition)
	for _ = 1, 14 do
		local spark = Instance.new("Frame")
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = fromPosition
		spark.Size = UDim2.new(0, 6, 0, 6)
		spark.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
		spark.BorderSizePixel = 0
		spark.ZIndex = 43
		spark.Parent = sparkContainer
		local sparkCorner = Instance.new("UICorner")
		sparkCorner.CornerRadius = UDim.new(1, 0)
		sparkCorner.Parent = spark

		local angle = math.random() * math.pi * 2
		local distance = math.random(40, 90)
		local offset = Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance)
		local tween = TweenService:Create(spark, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(fromPosition.X.Scale, fromPosition.X.Offset + offset.X, fromPosition.Y.Scale, fromPosition.Y.Offset + offset.Y),
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 1, 0, 1),
		})
		tween:Play()
		tween.Completed:Connect(function()
			spark:Destroy()
		end)
	end
end

-- Kurzer Screen-Shake (Kamera-Wackeln).
local function screenShake(intensity, duration)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	task.spawn(function()
		local elapsed = 0
		local step = 0.02
		while elapsed < duration do
			local offset = Vector3.new(math.random(-100, 100), math.random(-100, 100), 0) / 100 * intensity
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			task.wait(step)
			elapsed += step
		end
	end)
end

-- Angekuendigt wird, was KOMMT -- nicht, was passiert ist. newLevel ist deshalb die
-- Stufe, auf die es zulaeuft, und oldLevel die, auf der die Stadt noch steht.
local function showAnnouncement(cityName, newLevel, oldLevel)
	if isAnimating then
		return
	end
	isAnimating = true

	-- Die Mitte gehoert jetzt dem Ereignis. Eine noch stehende Warnung weicht -- sie hat
	-- dasselbe Thema, und zwei Meldungen dazu uebereinander waeren keine.
	HudCenterNotice.SetBusy(true)
	HudCenterNotice.ClearWarning()

	local info = LEVEL_INFO[newLevel] or { title = "ALERT LEVEL " .. newLevel, consequence = "", soundId = "" }
	local isMaxLevel = newLevel >= 5

	-- ===== 0.0s -- Trigger: kompakte Anzeige zittert, aktueller Stern pulsiert 2x, Boom. =====
	if _G.ShakeCityAlertIndicator then
		_G.ShakeCityAlertIndicator()
	end
	if _G.PulseCityAlertStar then
		_G.PulseCityAlertStar(oldLevel)
	end
	playSound(IMPACT_SOUND_ID, 0.9)

	task.wait(0.15)

	-- ===== 0.15s -- Warnsignal: Rand-Flash + stufenspezifischer Sound startet. =====
	edgeFlashStroke.Transparency = 0.3
	local edgeFadeOut = TweenService:Create(edgeFlashStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Transparency = 1 })
	edgeFadeOut:Play()
	playSound(info.soundId, 0.85)

	task.wait(0.15)

	-- ===== 0.3s -- HUD fliegt vergrössert ins Zentrum. Neuer Stern zunächst als dunkler
	-- Umriss (niedrige Deckkraft), alte Sterne bereits normal sichtbar. =====
	local starCount = math.max(newLevel, 0)
	local oldStarCount = math.max(oldLevel, 0)
	for i = 1, MAX_BANNER_STARS do
		local star = starLabels[i]
		if i <= oldStarCount then
			star.Visible = true
			star.TextTransparency = 0
			star.TextColor3 = Color3.fromRGB(255, 210, 80)
			star.Rotation = 0
			star.Size = UDim2.new(0, 48, 1, 0)
		elseif i == starCount and starCount > oldStarCount then
			-- Der NEUE Stern: als dunkler Umriss zeigen.
			star.Visible = true
			star.TextTransparency = 0.3
			star.TextColor3 = Color3.fromRGB(60, 55, 45)
			star.Rotation = 0
			star.Size = UDim2.new(0, 48, 1, 0)
		else
			star.Visible = false
		end
	end

	titleLabel.Text = info.title
	titleLabel.TextColor3 = HudChrome.Color.TextPrimary
	levelLabel.Text = "LEVEL " .. oldLevel .. "  \u{2192}  " .. newLevel
	consequenceLabel.Text = ""
	consequenceLabel.TextTransparency = 1

	local originalSize = banner.Size
	local originalPosition = banner.Position
	banner.Size = UDim2.new(0, 0, 0, 0)
	banner.BackgroundTransparency = 1
	titleLabel.TextTransparency = 1
	levelLabel.TextTransparency = 1
	banner.Position = originalPosition
	banner.Visible = true

	TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = originalSize,
		BackgroundTransparency = 0.45,
	}):Play()
	TweenService:Create(titleLabel, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	TweenService:Create(levelLabel, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()

	task.wait(0.25)

	-- ===== 0.55s -- Eskalation: neuer Stern wird eingestanzt (Overshoot 140%->100%,
	-- Screen-Shake, Funken, Shockwave-Ring), Text wechselt zu "ALERT LEVEL X". =====
	if isMaxLevel then
		-- Level 5 bricht das Muster: kurzer Hitstop-artiger Break vor dem grossen Schlag.
		task.wait(0.1)
	end

	local newStar = starLabels[starCount]
	if newStar and starCount > oldStarCount then
		if isMaxLevel then
			-- Alle Sterne schlagen fast nacheinander ein, statt nur der eine neue.
			for i = 1, starCount do
				local star = starLabels[i]
				star.Visible = true
				star.TextColor3 = Color3.fromRGB(255, 210, 80)
				star.TextTransparency = 0
				star.Size = UDim2.new(0, 68, 1, 0)
				TweenService:Create(star, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = UDim2.new(0, 48, 1, 0),
				}):Play()
				playSound(STAMP_SOUND_ID, 0.6)
				task.wait(0.08)
			end
		else
			-- Eingestanzt, mit Ueberschwung: der Stern ist jetzt verdient. Genau dieser
			-- Moment war es, fuer den die Sequenz gebaut wurde.
			newStar.TextColor3 = HudChrome.Color.Ready
			newStar.TextTransparency = 0
			newStar.Size = UDim2.new(0, 67, 1, 0) -- ~140% von 48
			TweenService:Create(newStar, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 48, 1, 0),
			}):Play()
		end

		playSound(STAMP_SOUND_ID, 0.9)
		screenShake(isMaxLevel and 1.6 or 0.9, isMaxLevel and 0.35 or 0.2)
		emitStampSparks(newStar.Position + UDim2.new(0, 24, 0, 0))

		-- Shockwave-Ring vom Stern aus ausdehnen.
		shockwaveRing.Position = UDim2.new(0.5, 0, 0, 78)
		shockwaveRing.Size = UDim2.new(0, 10, 0, 10)
		shockwaveStroke.Transparency = 0
		TweenService:Create(shockwaveRing, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 220, 0, 220),
		}):Play()
		TweenService:Create(shockwaveStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
			Transparency = 1,
		}):Play()
	end

	levelLabel.Text = "ALERT LEVEL " .. newLevel
	levelLabel.TextColor3 = HudChrome.Color.TextPrimary

	if isMaxLevel then
		-- Die Hoechststufe laesst den Titel kurz anwachsen.
		TweenService:Create(titleLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextSize = TITEL_GROESSE_MAX,
		}):Play()
	end

	task.wait(0.35)

	-- ===== 0.9s -- Konsequenz: kurzer Text erscheint. =====
	if info.consequence ~= "" then
		consequenceLabel.Text = info.consequence
		TweenService:Create(consequenceLabel, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	end

	task.wait(0.6)

	-- ===== 1.5s -- Rückkehr: schrumpft zurück zur kompakten Anzeige oben rechts. =====
	local flyTarget = UDim2.new(1, -110, 0, 100)
	local flyTween = TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = flyTarget,
		Size = UDim2.new(0, 40, 0, 20),
		BackgroundTransparency = 1,
	})
	TweenService:Create(titleLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	TweenService:Create(levelLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	TweenService:Create(consequenceLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	for i = 1, starCount do
		if starLabels[i] then
			TweenService:Create(starLabels[i], TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end
	flyTween:Play()
	flyTween.Completed:Wait()

	banner.Visible = false
	banner.Size = originalSize
	banner.Position = originalPosition
	titleLabel.TextSize = TITEL_GROESSE -- zuruecksetzen, falls die Hoechststufe ihn angehoben hat

	if _G.FlashCityAlertIndicator then
		_G.FlashCityAlertIndicator(HudChrome.Color.Danger)
	end

	isAnimating = false
	HudCenterNotice.SetBusy(false)
end

-- ===== Ausloeser =====
--
-- Zwei Beobachtungen, zwei Register der Bildmitte.
--
-- Der DRUCK loest die WARNUNG aus, sobald er 80 Prozent der Schwelle erreicht: kurzer
-- Alarmton, rotes Schild, und darauf steht, was gleich kommt. Einmal je Stufe.
--
-- Der STUFENWECHSEL loest das EREIGNIS aus -- die grosse Sequenz. Sie meldet, was
-- eingetreten ist, und spielt den Ton dieser Stufe.
--
-- (Nebenbei: die alte Fassung war ueberhaupt nie verdrahtet. checkCityLevel stand als
-- Funktion da und wurde von nirgends aufgerufen -- die grosse Sequenz hat nie gespielt.
-- Deshalb hier auch die Abonnements, die vorher fehlten.)
local WARN_ANTEIL = 0.8 -- ab diesem Anteil der Schwelle wird gewarnt
local warnedForLevel = {} -- [cityName] = Stufe, fuer die schon gewarnt wurde

local function checkCityLevel(cityName)
	local levelValue = cityAlertValues:FindFirstChild(cityName .. "Level")
	if not levelValue then
		return
	end
	local newLevel = levelValue.Value
	local oldLevel = lastKnownLevel[cityName]

	if oldLevel == nil then
		lastKnownLevel[cityName] = newLevel
		return
	end
	if newLevel == oldLevel then
		return
	end
	lastKnownLevel[cityName] = newLevel
	warnedForLevel[cityName] = nil -- fuer die neue Stufe darf wieder gewarnt werden

	if player:GetAttribute("CurrentCityName") ~= cityName then
		return
	end

	if newLevel > oldLevel then
		local now = os.clock()
		if lastAnnouncedAt[cityName] and now - lastAnnouncedAt[cityName] < COOLDOWN_SECONDS then
			return
		end
		lastAnnouncedAt[cityName] = now
		showAnnouncement(cityName, newLevel, oldLevel)
	else
		-- Entspannung: kein Ereignis, nur die kompakte Anzeige leuchtet gruen.
		if _G.FlashCityAlertIndicator then
			_G.FlashCityAlertIndicator(Color3.fromRGB(90, 220, 130))
		end
	end
end

local function checkCityPressure(cityName)
	if player:GetAttribute("CurrentCityName") ~= cityName then
		return
	end

	local levelValue = cityAlertValues:FindFirstChild(cityName .. "Level")
	local progressValue = cityAlertValues:FindFirstChild(cityName .. "Progress")
	local config = CityAlertConfig.GetCityConfig(cityName)
	if not levelValue or not progressValue or not config then
		return
	end

	local schwelle = config.AlertThresholdLevel2
	if not schwelle or schwelle <= 0 then
		return
	end

	local level = math.max(levelValue.Value, 0)
	if warnedForLevel[cityName] == level then
		return
	end

	local maxLevelValue = cityAlertValues:FindFirstChild(cityName .. "MaxLevel")
	local maxLevel = (maxLevelValue and maxLevelValue.Value) or config.MaxAlertLevel or 5
	if level >= maxLevel then
		return -- auf der Hoechststufe kommt nichts mehr, also gibt es nichts zu warnen
	end

	if progressValue.Value / schwelle < WARN_ANTEIL then
		return
	end

	local kommend = LEVEL_INFO[level + 1]
	if not kommend then
		return
	end

	warnedForLevel[cityName] = level
	HudCenterNotice.Warn({
		title = kommend.title,
		detail = kommend.consequence ~= "" and kommend.consequence or "ALERT LEVEL " .. (level + 1) .. " INBOUND",
		soundId = WARN_SOUND_ID,
		volume = 0.6,
	})
end

local function beobachte(valueObject)
	local name = valueObject.Name
	local stadt = name:match("^(.-)Level$")
	if stadt and not name:match("MaxLevel$") then
		valueObject:GetPropertyChangedSignal("Value"):Connect(function()
			checkCityLevel(stadt)
		end)
		lastKnownLevel[stadt] = valueObject.Value
		return
	end
	local druckStadt = name:match("^(.-)Progress$")
	if druckStadt then
		valueObject:GetPropertyChangedSignal("Value"):Connect(function()
			checkCityPressure(druckStadt)
		end)
	end
end

for _, valueObject in ipairs(cityAlertValues:GetChildren()) do
	beobachte(valueObject)
end
cityAlertValues.ChildAdded:Connect(beobachte)

print("[Kaiju Debug] CityAlertAnnouncement: Warnung ab "
	.. math.floor(WARN_ANTEIL * 100)
	.. " Prozent, grosse Meldung beim Stufenaufstieg.")
