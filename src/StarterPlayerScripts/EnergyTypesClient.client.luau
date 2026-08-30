-- VERSION: 2026-08-25 #2 (RemoteEventUtils-Umstellung)
-- LocalScript: EnergyTypesClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt die 5 Energie-Typen (Wärme/Chemie/Elektrizität/Nuklear/Spirit) als kompakte
-- Icon-Leiste, ein Banner bei aktivem Welt-Event, und ein einfaches Fraktions-Panel
-- (Kaiju/Jaeger/Ronin -- letztere zwei aktuell nur als Vorschau/"Bald verfügbar",
-- da kein eigenes Moveset existiert).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local applyComicStyle = ComicStyleUtils.Apply
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local SelectFactionEvent = RemoteEventUtils.GetOrCreate("SelectFactionEvent")
local GetFactionProgressFunction = ReplicatedStorage:WaitForChild("GetFactionProgressFunction")
local WorldEventChangedEvent = RemoteEventUtils.GetOrCreate("WorldEventChangedEvent")
local WorldEventPreRollEvent = RemoteEventUtils.GetOrCreate("WorldEventPreRollEvent")
local EnergyGainedEvent = RemoteEventUtils.GetOrCreate("EnergyGainedEvent")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EnergyTypesGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== 5 Energie-Typen: Farbreferenz für den künftigen Talentbaum =====
-- Bewusst KEINE Anzeige mehr im Haupt-HUD -- diese Energien sind ausschliesslich zum
-- "Ausgeben" im Talentbaum gedacht (der noch nicht existiert). Bis es den Talentbaum
-- gibt, werden sie weiterhin im Hintergrund gesammelt/gezählt (siehe
-- EnergyTypesHandler.lua), nur eben nicht permanent im Kampf-HUD gezeigt. Diese Tabelle
-- bleibt als Farb-/Icon-Referenz erhalten, damit der Talentbaum später dieselben Farben
-- wiederverwenden kann.
local ENERGY_CONFIG = {
	{ key = "Heat", emoji = "🔥", color = Color3.fromRGB(255, 35, 25), attribute = "EnergyHeat" },
	{ key = "Chemical", emoji = "🧪", color = Color3.fromRGB(255, 45, 190), attribute = "EnergyChemical" },
	{ key = "Electric", emoji = "⚡", color = Color3.fromRGB(57, 217, 255), attribute = "EnergyElectric" },
	{ key = "Radiation", emoji = "☢️", color = Color3.fromRGB(126, 255, 16), attribute = "EnergyRadiation" },
	{ key = "Spirit", emoji = "✨", color = Color3.fromRGB(255, 205, 70), attribute = "EnergySpirit" },
}

-- ===== Welt-Event-Banner =====
local eventBanner = Instance.new("TextLabel")
eventBanner.Name = "WorldEventBanner"
eventBanner.Size = UDim2.new(0, 300, 0, 44)
eventBanner.AnchorPoint = Vector2.new(1, 1)
eventBanner.Position = UDim2.new(1, 340, 1, -70) -- startet ausserhalb rechts, fährt beim Event rein
eventBanner.BackgroundColor3 = Color3.fromRGB(255, 210, 40)
eventBanner.Font = Enum.Font.LuckiestGuy
eventBanner.TextScaled = true
eventBanner.TextColor3 = Color3.fromRGB(30, 20, 0)
eventBanner.Text = ""
eventBanner.Visible = false
eventBanner.ZIndex = 60
eventBanner.Parent = screenGui
applyComicStyle(eventBanner, 14, 3)

-- ===== Countdown: zeigt entweder "Event X endet in MM:SS" (falls eines läuft) oder
-- "Nächstes Event in MM:SS" (falls gerade keines aktiv ist) -- derselbe Zeitstempel
-- bestimmt beides, da der nächste Würfelwurf so oder so über das Ende/den Start
-- entscheidet.
local NextWorldEventRollTime = ReplicatedStorage:WaitForChild("NextWorldEventRollTime")
local activeEventLabel = nil -- z.B. "🔥 Heat Wave", nil wenn kein Event läuft

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Name = "WorldEventCountdown"
countdownLabel.Size = UDim2.new(0, 240, 0, 24)
countdownLabel.AnchorPoint = Vector2.new(1, 1)
countdownLabel.Position = UDim2.new(1, -20, 1, -20)
countdownLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
countdownLabel.BackgroundTransparency = 0.25
countdownLabel.Font = Enum.Font.FredokaOne
countdownLabel.TextScaled = true
countdownLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
countdownLabel.Text = ""
countdownLabel.ZIndex = 55
countdownLabel.Parent = screenGui
applyComicStyle(countdownLabel, 8, 2)

local function formatCountdown(seconds)
	seconds = math.max(math.floor(seconds), 0)
	local minutes = math.floor(seconds / 60)
	local remainderSeconds = seconds % 60
	return string.format("%d:%02d", minutes, remainderSeconds)
end

RunService.Heartbeat:Connect(function()
	local remaining = NextWorldEventRollTime.Value - Workspace:GetServerTimeNow()
	if activeEventLabel then
		countdownLabel.Text = activeEventLabel .. " ends in " .. formatCountdown(remaining)
	else
		countdownLabel.Text = "⏳ Next event in " .. formatCountdown(remaining)
	end
end)

-- ===== Musik pro Welt-Event =====
-- Sanftes Überblenden: die NORMALE Hintergrundmusik (aus BackgroundMusicClient.lua) wird
-- während eines aktiven Events ausgeblendet/pausiert, der Event-Song übernimmt komplett --
-- vorher liefen beide gleichzeitig, wodurch der "Songwechsel" kaum wahrnehmbar war.
local function getBackgroundMusicSound()
	return SoundService:FindFirstChild("BackgroundMusic")
end

local eventMusic = Instance.new("Sound")
eventMusic.Name = "WorldEventMusic"
eventMusic.Looped = true
eventMusic.Volume = 0
eventMusic.Parent = SoundService

local EVENT_MUSIC_VOLUME = 0.5
local EVENT_MUSIC_FADE_TIME = 1.5

local function stopEventMusic()
	local fadeOut = TweenService:Create(eventMusic, TweenInfo.new(EVENT_MUSIC_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 0,
	})
	fadeOut.Completed:Connect(function()
		eventMusic:Stop()
	end)
	fadeOut:Play()

	-- Normale Hintergrundmusik wieder einblenden, sobald das Event endet.
	local backgroundMusic = getBackgroundMusicSound()
	if backgroundMusic then
		if not backgroundMusic.Playing then
			backgroundMusic:Play()
		end
		TweenService:Create(backgroundMusic, TweenInfo.new(EVENT_MUSIC_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Volume = backgroundMusic:GetAttribute("BaseVolume") or backgroundMusic.Volume,
		}):Play()
	end
end

local function playEventMusic(musicId)
	if not musicId or musicId == "" or musicId == "rbxassetid://0" then
		stopEventMusic()
		return
	end

	-- Läuft dieser Song schon (von der Vorankündigung 10s vorher übernommen)? Dann nicht
	-- nochmal von 0 einblenden -- das würde bei der Enthüllung einen kurzen ungewollten
	-- Lautstärke-Einbruch verursachen.
	if eventMusic.SoundId == musicId and eventMusic.Playing then
		return
	end

	eventMusic.SoundId = musicId
	eventMusic.Volume = 0
	eventMusic:Play()
	TweenService:Create(eventMusic, TweenInfo.new(EVENT_MUSIC_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Volume = EVENT_MUSIC_VOLUME,
	}):Play()

	-- Normale Hintergrundmusik ausblenden, solange das Event läuft -- der Event-Song
	-- soll spürbar übernehmen, nicht nur zusätzlich dazu laufen.
	local backgroundMusic = getBackgroundMusicSound()
	if backgroundMusic then
		if backgroundMusic:GetAttribute("BaseVolume") == nil then
			backgroundMusic:SetAttribute("BaseVolume", backgroundMusic.Volume)
		end
		TweenService:Create(backgroundMusic, TweenInfo.new(EVENT_MUSIC_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = 0,
		}):Play()
	end
end

local function showWorldEventBanner(event)
	if not event then
		-- Event endet -- Banner nach kurzer Zeit ausblenden lassen (nach rechts raus)
		activeEventLabel = nil
		stopEventMusic()
		TweenService:Create(eventBanner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(1, 340, 1, -70),
		}):Play()
		task.delay(0.4, function()
			eventBanner.Visible = false
		end)
		return
	end

	activeEventLabel = event.emoji .. " " .. event.name
	eventBanner.Text = event.emoji .. " " .. event.name:upper() .. " -- " .. event.emoji .. " x" .. event.multiplier
	eventBanner.Visible = true
	eventBanner.Position = UDim2.new(1, 340, 1, -70)
	TweenService:Create(eventBanner, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -20, 1, -70),
	}):Play()

	playEventMusic(event.musicId)
end

WorldEventChangedEvent.OnClientEvent:Connect(showWorldEventBanner)

-- ===== Vorankündigung (10s vor der eigentlichen Enthüllung): Musik wechselt SOFORT und
-- LAUT, ohne Einblenden -- damit der Songwechsel selbst als deutliches Signal ankommt,
-- bevor Banner/Effekte überhaupt sichtbar werden. Kein activeEventLabel-Update hier (das
-- passiert erst bei der echten Enthüllung über showWorldEventBanner), Countdown-Text
-- bleibt bis dahin unverändert "Nächstes Event in...".
local PREROLL_FADE_OUT_TIME = 2 -- Sekunden, um den vorherigen Song auszublenden, bevor der neue einsetzt

WorldEventPreRollEvent.OnClientEvent:Connect(function(musicId)
	-- Bei "kein Event" gewürfelt (musicId ist nil): Musik bleibt komplett unangetastet --
	-- kein Ausblenden, kein Stille-Moment. Nur bei einem ECHTEN Event wird die aktuelle
	-- Musik ausgeblendet, um Platz für den neuen Song zu machen.
	if not musicId or musicId == "" or musicId == "rbxassetid://0" then
		return
	end

	-- Herausfinden, was gerade aktiv ist (Hintergrundmusik oder ein vorheriger Event-Song),
	-- um es über 2 Sekunden auszublenden -- statt hart abzuschneiden.
	local backgroundMusic = getBackgroundMusicSound()
	-- WICHTIG: ursprüngliche Lautstärke JETZT sichern, BEVOR sie gleich ausgeblendet wird
	-- -- sonst würde sie später (nach dem Event) fälschlich auf 0 statt den echten
	-- Ausgangswert zurückgesetzt.
	if backgroundMusic and backgroundMusic:GetAttribute("BaseVolume") == nil then
		backgroundMusic:SetAttribute("BaseVolume", backgroundMusic.Volume)
	end

	local currentlyPlaying = eventMusic.Playing and eventMusic or (backgroundMusic and backgroundMusic.Playing and backgroundMusic or nil)

	local function startNewSong()
		eventMusic.SoundId = musicId
		eventMusic.Volume = EVENT_MUSIC_VOLUME -- sofort in voller Lautstärke, kein Einblenden
		eventMusic:Play()
	end

	if currentlyPlaying then
		local fadeOut = TweenService:Create(currentlyPlaying, TweenInfo.new(PREROLL_FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = 0,
		})
		fadeOut.Completed:Connect(function()
			currentlyPlaying:Stop()
			startNewSong()
		end)
		fadeOut:Play()
	else
		startNewSong()
	end
end)

-- ===== Fraktions-Panel: episches Auswahl-Erlebnis mit rotierenden 3D-Vorschauen =====
-- Wird über den zentralen Menü-Button geöffnet (siehe NavigationClient.lua).

local factionPanel = Instance.new("Frame")
factionPanel.Name = "FactionPanel"
factionPanel.Size = UDim2.new(0, 900, 0, 580)
factionPanel.AnchorPoint = Vector2.new(0.5, 0.5)
factionPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
factionPanel.BackgroundColor3 = Color3.fromRGB(8, 6, 16)
factionPanel.Visible = false
factionPanel.ZIndex = 70
factionPanel.ClipsDescendants = true
factionPanel.Parent = screenGui
applyComicStyle(factionPanel, 20, 5)

-- Dramatischer Verlaufs-Hintergrund (dunkles Violett -> fast Schwarz) statt einer
-- einfarbigen Fläche -- macht die Szene sofort "epischer".
local backgroundGradient = Instance.new("UIGradient")
backgroundGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 15, 55)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12, 8, 24)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 3, 10)),
})
backgroundGradient.Rotation = 90
backgroundGradient.Parent = factionPanel

-- Feiner, langsam wandernder Lichtschein über den ganzen Hintergrund -- rein
-- atmosphärisch, kein Gameplay-Bezug.
local glowStreak = Instance.new("Frame")
glowStreak.Size = UDim2.new(0.5, 0, 2, 0)
glowStreak.Position = UDim2.new(-0.3, 0, -0.5, 0)
glowStreak.Rotation = 25
glowStreak.BackgroundColor3 = Color3.fromRGB(120, 80, 220)
glowStreak.BackgroundTransparency = 0.92
glowStreak.BorderSizePixel = 0
glowStreak.ZIndex = 70
glowStreak.Parent = factionPanel

local factionTitle = Instance.new("TextLabel")
factionTitle.Size = UDim2.new(1, 0, 0, 46)
factionTitle.Position = UDim2.new(0, 0, 0, 12)
factionTitle.BackgroundTransparency = 1
factionTitle.Font = Enum.Font.LuckiestGuy
factionTitle.TextScaled = true
factionTitle.TextColor3 = Color3.new(1, 1, 1)
factionTitle.TextStrokeColor3 = Color3.fromRGB(120, 60, 200)
factionTitle.TextStrokeTransparency = 0.5
factionTitle.Text = "⚔️ CHOOSE YOUR FACTION ⚔️"
factionTitle.ZIndex = 71
factionTitle.Parent = factionPanel

local FACTIONS = {
	{ key = "Kaiju", modelName = "KaijuR15", emoji = "🦖", label = "KAIJU", subtitle = "POWER", color = Color3.fromRGB(90, 220, 110), desc = "Raw destructive power" },
	{ key = "Jaeger", modelName = "JaegerR15", emoji = "🤖", label = "JAEGER", subtitle = "CONTROL", color = Color3.fromRGB(80, 170, 255), desc = "Master the battlefield" },
	{ key = "Ronin", modelName = "RoninR15", emoji = "🐯", label = "RONIN", subtitle = "PURPOSE", color = Color3.fromRGB(255, 150, 60), desc = "Strike with precision" },
}

local cardRow = Instance.new("Frame")
cardRow.Size = UDim2.new(1, -32, 1, -70)
cardRow.Position = UDim2.new(0, 16, 0, 64)
cardRow.BackgroundTransparency = 1
cardRow.ZIndex = 71
cardRow.Parent = factionPanel

local cardRowLayout = Instance.new("UIListLayout")
cardRowLayout.FillDirection = Enum.FillDirection.Horizontal
cardRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardRowLayout.Padding = UDim.new(0, 14)
cardRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardRowLayout.Parent = cardRow

local avatarPack = Workspace:FindFirstChild("R15AvatarPack")

-- Dreht das geklonte Vorschau-Modell in einem Viewport dauerhaft langsam um sich selbst
-- ("Turntable"-Effekt) -- macht aus einer starren Pose eine lebendige Präsentation.
local function startTurntable(viewportModel)
	task.spawn(function()
		while viewportModel.Parent do
			local ok = pcall(function()
				viewportModel:PivotTo(viewportModel:GetPivot() * CFrame.Angles(0, math.rad(0.6), 0))
			end)
			if not ok then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function buildViewport(container, modelName)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, 0, 1, 0)
	viewport.BackgroundTransparency = 1
	viewport.ZIndex = 71
	-- WICHTIG: ViewportFrames übernehmen NICHT automatisch die normale
	-- Workspace-Beleuchtung -- ohne explizite Werte hier rendern sie komplett schwarz.
	viewport.Ambient = Color3.fromRGB(140, 140, 150)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Parent = container
	print("[Kaiju-Debug] ViewportFrame erstellt für", modelName)

	local template = avatarPack and avatarPack:FindFirstChild(modelName)
	if not template then
		local missingLabel = Instance.new("TextLabel")
		missingLabel.Size = UDim2.new(1, 0, 1, 0)
		missingLabel.BackgroundTransparency = 1
		missingLabel.Font = Enum.Font.FredokaOne
		missingLabel.TextScaled = true
		missingLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		missingLabel.Text = "?"
		missingLabel.Parent = viewport
		return
	end

	local previewModel = template:Clone()
	previewModel.Parent = viewport
	print("[Kaiju-Debug]", modelName, "-- Klon hat", #previewModel:GetChildren(), "direkte Kinder,", #previewModel:GetDescendants(), "Nachfahren insgesamt, PrimaryPart:", previewModel.PrimaryPart)

	-- WICHTIG: Modell zuerst zu einer BEKANNTEN Position verschieben (Ursprung) --
	-- sonst behält der Klon seine ursprüngliche Position irgendwo im Workspace, während
	-- die Kamera bei (0,0,0) startet und das Modell dadurch nie ins Bild bekommt.
	local pivotOk = pcall(function()
		previewModel:PivotTo(CFrame.new(0, 0, 0))
	end)

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Kamera so positionieren, dass das ganze Modell mittig ins Bild passt (aus der
	-- tatsächlichen Bounding-Box berechnet, unabhängig von der Modellgrösse).
	local ok, cframe, size = pcall(function()
		return previewModel:GetBoundingBox()
	end)
	if ok then
		local distance = math.max(size.X, size.Y, size.Z) * 1.6
		local center = cframe.Position
		camera.CFrame = CFrame.new(center + Vector3.new(0, size.Y * 0.05, distance), center)
		print("[Kaiju-Debug] Viewport für", modelName, "-- pivotOk:", pivotOk, "size:", size, "distance:", distance)
	else
		-- Sicherheits-Fallback, falls GetBoundingBox() aus irgendeinem Grund scheitert --
		-- Kamera schaut trotzdem in Richtung des (bekannten) Ursprungs, statt komplett
		-- ins Leere.
		camera.CFrame = CFrame.new(Vector3.new(0, 3, 15), Vector3.new(0, 3, 0))
		print("[Kaiju-Debug] Viewport für", modelName, "-- GetBoundingBox fehlgeschlagen, pivotOk:", pivotOk)
	end

	startTurntable(previewModel)
end

local factionCards = {} -- [key] = { card, descLabel, progressContainer, levelLabel/Fill, energyLabel/Fill, milestoneLabel/Fill, selectButton }

for index, faction in ipairs(FACTIONS) do
	local card = Instance.new("Frame")
	card.Name = faction.key .. "Card"
	card.Size = UDim2.new(0, 270, 1, 0)
	card.LayoutOrder = index
	card.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
	card.ZIndex = 71
	card.Parent = cardRow
	applyComicStyle(card, 14, 3)

	local cardStroke = card:FindFirstChildOfClass("UIStroke")
	if cardStroke then
		cardStroke.Color = faction.color
		cardStroke.Thickness = 3
	end

	-- Farbiger Glow-Schein hinter dem Charakter, passend zur Fraktions-Farbe.
	local glow = Instance.new("Frame")
	glow.Size = UDim2.new(0.85, 0, 0.85, 0)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0.36, 0)
	glow.BackgroundColor3 = faction.color
	glow.BackgroundTransparency = 0.82
	glow.ZIndex = 70
	glow.Parent = card
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow

	-- 3D-Vorschau (rotierendes Modell)
	local viewportContainer = Instance.new("Frame")
	viewportContainer.Size = UDim2.new(1, -16, 0, 210)
	viewportContainer.Position = UDim2.new(0, 8, 0, 8)
	viewportContainer.BackgroundTransparency = 1
	viewportContainer.ZIndex = 71
	viewportContainer.Parent = card
	buildViewport(viewportContainer, faction.modelName)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -8, 0, 30)
	nameLabel.Position = UDim2.new(0, 4, 0, 222)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.LuckiestGuy
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = faction.color
	nameLabel.Text = faction.emoji .. " " .. faction.label
	nameLabel.ZIndex = 71
	nameLabel.Parent = card

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.new(1, -8, 0, 16)
	subtitleLabel.Position = UDim2.new(0, 4, 0, 252)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.FredokaOne
	subtitleLabel.TextScaled = true
	subtitleLabel.TextColor3 = Color3.fromRGB(210, 210, 220)
	subtitleLabel.Text = faction.subtitle .. " -- " .. faction.desc
	subtitleLabel.ZIndex = 71
	subtitleLabel.Parent = card

	-- Fortschritts-Container: nur für gesperrte Fraktionen sichtbar/befüllt.
	local progressContainer = Instance.new("Frame")
	progressContainer.Size = UDim2.new(1, -16, 0, 108)
	progressContainer.Position = UDim2.new(0, 8, 0, 272)
	progressContainer.BackgroundTransparency = 1
	progressContainer.ZIndex = 71
	progressContainer.Visible = (faction.key ~= "Kaiju")
	progressContainer.Parent = card

	local progressLayout = Instance.new("UIListLayout")
	progressLayout.Padding = UDim.new(0, 5)
	progressLayout.Parent = progressContainer

	local function makeProgressBar(labelText)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundTransparency = 1
		row.Parent = progressContainer

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 15)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(210, 210, 220)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = labelText
		label.ZIndex = 71
		label.Parent = row

		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, 0, 0, 11)
		track.Position = UDim2.new(0, 0, 0, 17)
		track.BackgroundColor3 = Color3.fromRGB(50, 48, 60)
		track.ZIndex = 71
		track.Parent = row
		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(120, 220, 140)
		fill.BorderSizePixel = 0
		fill.ZIndex = 72
		fill.Parent = track
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		return label, fill
	end

	local levelLabel, levelFill = makeProgressBar("Level 0/0")
	local energyLabel, energyFill = makeProgressBar("Energy 0/0")
	local milestoneLabel, milestoneFill = makeProgressBar("Goal 0/0")

	local selectButton = Instance.new("TextButton")
	selectButton.Size = UDim2.new(1, -16, 0, 34)
	selectButton.Position = UDim2.new(0, 8, 1, -42)
	selectButton.BackgroundColor3 = faction.color
	selectButton.Font = Enum.Font.LuckiestGuy
	selectButton.TextScaled = true
	selectButton.TextColor3 = Color3.new(1, 1, 1)
	selectButton.Text = faction.key == "Kaiju" and "SELECT" or "🔒 LOCKED"
	selectButton.ZIndex = 71
	selectButton.Parent = card
	applyComicStyle(selectButton, 10, 2)

	selectButton.MouseButton1Click:Connect(function()
		SelectFactionEvent:FireServer(faction.key)
		factionPanel.Visible = false
	end)

	factionCards[faction.key] = {
		card = card,
		levelLabel = levelLabel,
		levelFill = levelFill,
		energyLabel = energyLabel,
		energyFill = energyFill,
		milestoneLabel = milestoneLabel,
		milestoneFill = milestoneFill,
		selectButton = selectButton,
		progressContainer = progressContainer,
		color = faction.color,
	}
end

-- ===== Fortschritt vom Server abrufen und in die Karten eintragen =====
local ENERGY_ICONS_FOR_PROGRESS = {
	Heat = "🔥",
	Chemical = "🧪",
	Electric = "⚡",
	Radiation = "☢️",
	Spirit = "✨",
}

local function refreshFactionProgress()
	local ok, result = pcall(function()
		return GetFactionProgressFunction:InvokeServer()
	end)
	if not ok or not result then
		return
	end

	for factionKey, info in pairs(result) do
		local refs = factionCards[factionKey]
		if refs then
			if info.unlocked then
				refs.progressContainer.Visible = false
				refs.selectButton.Text = "SELECT"
				refs.selectButton.BackgroundColor3 = refs.color
			elseif info.progress then
				local p = info.progress
				refs.progressContainer.Visible = true
				refs.selectButton.Text = "🔒 LOCKED"
				refs.selectButton.BackgroundColor3 = Color3.fromRGB(60, 58, 68)

				refs.levelLabel.Text = "⭐ Level " .. p.level.current .. "/" .. p.level.target
				refs.levelFill.Size = UDim2.new(math.clamp(p.level.current / p.level.target, 0, 1), 0, 1, 0)
				refs.levelFill.BackgroundColor3 = p.level.done and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(220, 180, 80)

				local energyIcon = ENERGY_ICONS_FOR_PROGRESS[p.energy.energyType] or ""
				refs.energyLabel.Text = energyIcon .. " " .. p.energy.current .. "/" .. p.energy.target
				refs.energyFill.Size = UDim2.new(math.clamp(p.energy.current / p.energy.target, 0, 1), 0, 1, 0)
				refs.energyFill.BackgroundColor3 = p.energy.done and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(220, 180, 80)

				refs.milestoneLabel.Text = "🎯 " .. p.milestone.current .. "/" .. p.milestone.target
				refs.milestoneFill.Size = UDim2.new(math.clamp(p.milestone.current / p.milestone.target, 0, 1), 0, 1, 0)
				refs.milestoneFill.BackgroundColor3 = p.milestone.done and Color3.fromRGB(120, 220, 140) or Color3.fromRGB(220, 180, 80)
			end
		end
	end
end

-- Fortschritt aktualisieren, sobald das Panel geöffnet wird (nicht dauerhaft pollen).
factionPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if factionPanel.Visible then
		refreshFactionProgress()
	end
end)

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 34, 0, 34)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -8, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
closeButton.Font = Enum.Font.FredokaOne
closeButton.TextScaled = true
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "X"
closeButton.ZIndex = 72
closeButton.Parent = factionPanel
applyComicStyle(closeButton, 8, 2)
closeButton.MouseButton1Click:Connect(function()
	factionPanel.Visible = false
	-- Kehrt zum Hamburger-Menü zurück (ersetzt den früheren separaten "← Back"-Button).
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	end
end)

-- Kein Aufblitz-Feedback mehr hier -- die Energie-Icon-Leiste wurde aus dem Haupt-HUD
-- entfernt (siehe Kommentar oben bei ENERGY_CONFIG). EnergyGainedEvent wird aktuell nicht
-- mehr für eine sichtbare Reaktion genutzt; das Sammeln selbst läuft serverseitig
-- unverändert weiter.