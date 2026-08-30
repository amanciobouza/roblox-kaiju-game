-- VERSION: 2026-08-25 #1
-- FIX: Megacity -> MegaCity (Schreibweise an Studio-Attribut angeglichen)
-- Ort in Studio: StarterPlayerScripts
--
-- "ALERT ESCALATION"-Sequenz bei einem ECHTEN Alert-Level-Aufstieg der Stadt, in der
-- sich der Spieler gerade befindet. Läuft nach einem festen Zeitplan (~1.5-1.8s
-- Gesamtdauer), damit sie spektakulär wirkt, ohne den Spielfluss zu unterbrechen:
--
--   0.0s  Trigger: kompakte Anzeige zittert, aktueller Stern pulsiert 2x, Boom-Sound
--   0.15s Warnsignal: kurzer roter/oranger Rand-Flash, stufenspezifischer Sound startet
--   0.3s  HUD fliegt vergrössert ins Zentrum: "CITY ALERT" + Sterne (neuer Stern zunächst
--         als dunkler Umriss)
--   0.55s Eskalation: neuer Stern wird "eingestanzt" (Overshoot 140%->100%, Screen-Shake,
--         Partikel, Shockwave-Ring), Text wechselt zu "ALERT LEVEL X"
--   0.9s  Konsequenz: kurzer Text erscheint ("FIRE RESPONSE DEPLOYED" etc.)
--   1.5s  Rückkehr: schrumpft zurück zur kompakten Anzeige oben rechts
--
-- Level 5 bricht bewusst das Muster: kurzer Hitstop-artiger Break, alle Sterne schlagen
-- fast nacheinander ein, "MAXIMUM ALERT" füllt kurz die Bildschirmbreite.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local cityAlertValues = ReplicatedStorage:WaitForChild("CityAlertValues", 10)
if not cityAlertValues then
	warn("[CityAlertAnnouncementClient] CityAlertValues nicht gefunden (Timeout) -- Ankündigung bleibt deaktiviert.")
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
	[2] = { title = "EMERGENCY RESPONSE", consequence = "🚒 FIRE RESPONSE DEPLOYED", soundId = "" },
	[3] = { title = "SECURITY RESPONSE", consequence = "🛡️ DEFENSIVE BARRICADES DEPLOYED", soundId = "" },
	[4] = { title = "MILITARY RESPONSE", consequence = "⚔️ MILITARY FORCES DEPLOYED", soundId = "rbxassetid://93574748731319" },
	[5] = { title = "MAXIMUM ALERT", consequence = "👹 CITY DEFENDER AWAKENED", soundId = "" },
}

local IMPACT_SOUND_ID = "" -- tiefer Boom/Impact beim Trigger (0.0s) -- Platzhalter, bitte befüllen
local STAMP_SOUND_ID = "" -- CLANG/THOOM beim Einstanzen des neuen Sterns (0.55s) -- Platzhalter

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
edgeFlashStroke.Color = Color3.fromRGB(230, 60, 40)
edgeFlashStroke.Parent = edgeFlash

-- Zentrale Ankündigung.
local banner = Instance.new("Frame")
banner.Name = "AnnouncementBanner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, 0.35, 0)
banner.Size = UDim2.new(0, 560, 0, 175)
banner.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
banner.BackgroundTransparency = 1
banner.Visible = false
banner.ZIndex = 41
banner.Parent = screenGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 18)
bannerCorner.Parent = banner

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, -24, 0, 34)
titleLabel.Position = UDim2.new(0, 12, 0, 10)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.LuckiestGuy
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
titleLabel.TextStrokeTransparency = 0.3
titleLabel.ZIndex = 42
titleLabel.Text = ""
titleLabel.Parent = banner

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
	star.Font = Enum.Font.FredokaOne
	star.TextScaled = true
	star.TextColor3 = Color3.fromRGB(255, 210, 80)
	star.TextStrokeColor3 = Color3.new(0, 0, 0)
	star.TextStrokeTransparency = 0.3
	star.ZIndex = 42
	star.Text = "★"
	star.Visible = false
	star.LayoutOrder = i
	star.Parent = starsContainer
	starLabels[i] = star
end

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelLabel"
levelLabel.Size = UDim2.new(1, -24, 0, 22)
levelLabel.Position = UDim2.new(0, 12, 0, 110)
levelLabel.BackgroundTransparency = 1
levelLabel.Font = Enum.Font.FredokaOne
levelLabel.TextScaled = true
levelLabel.TextColor3 = Color3.fromRGB(230, 70, 60)
levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
levelLabel.TextStrokeTransparency = 0.3
levelLabel.ZIndex = 42
levelLabel.Text = ""
levelLabel.Parent = banner

local consequenceLabel = Instance.new("TextLabel")
consequenceLabel.Name = "ConsequenceLabel"
consequenceLabel.Size = UDim2.new(1, -24, 0, 30)
consequenceLabel.Position = UDim2.new(0, 12, 0, 136)
consequenceLabel.BackgroundTransparency = 1
consequenceLabel.Font = Enum.Font.FredokaOne
consequenceLabel.TextScaled = true
consequenceLabel.TextColor3 = Color3.fromRGB(255, 220, 150)
consequenceLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
consequenceLabel.TextStrokeTransparency = 0.3
consequenceLabel.TextTransparency = 1
consequenceLabel.ZIndex = 42
consequenceLabel.Text = ""
consequenceLabel.Parent = banner

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
shockwaveStroke.Color = Color3.fromRGB(255, 210, 80)
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

local function showAnnouncement(cityName, newLevel, oldLevel)
	if isAnimating then
		return
	end
	isAnimating = true

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
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	levelLabel.Text = "ALERT " .. (oldLevel > 0 and ("⭐" .. string.rep("", 0)) or "") -- Platzhalter, wird gleich überschrieben
	levelLabel.Text = "Level " .. oldLevel .. " → " .. newLevel
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
		BackgroundTransparency = 0.1,
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
			newStar.TextColor3 = Color3.fromRGB(255, 210, 80)
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
	levelLabel.TextColor3 = Color3.fromRGB(230, 70, 60)

	if isMaxLevel then
		-- MAXIMUM ALERT füllt kurz die Bildschirmbreite.
		TweenService:Create(titleLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, -24, 0, 50),
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
	titleLabel.Size = UDim2.new(1, -24, 0, 34) -- zurücksetzen, falls Level-5-Verbreiterung aktiv war

	if _G.FlashCityAlertIndicator then
		_G.FlashCityAlertIndicator(Color3.fromRGB(230, 70, 60))
	end

	isAnimating = false
end

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

	if player:GetAttribute("CurrentCityName") ~= cityName then
		return
	end

	local now = os.clock()
	if lastAnnouncedAt[cityName] and now - lastAnnouncedAt[cityName] < COOLDOWN_SECONDS then
		return
	end
	lastAnnouncedAt[cityName] = now

	if newLevel > oldLevel then
		showAnnouncement(cityName, newLevel, oldLevel)
	else
		-- De-Eskalation: keine grosse Ankündigung, nur die kompakte Anzeige leuchtet grün auf.
		if _G.FlashCityAlertIndicator then
			_G.FlashCityAlertIndicator(Color3.fromRGB(90, 220, 130))
		end
	end
end