-- VERSION: 2026-08-26 #18
-- FEATURE: FadeMusicToNormalVolumeEvent-Handler, Zweizeiler-Beat verlaengert
-- Ort in Studio: StarterPlayerScripts
--
-- Rendert die vom Server über StoryBeatService.Play() geschickten Erzähl-Sequenzen.
-- Siehe StoryBeatService.lua für die Datenstruktur und unterstützten Schritt-Typen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local PlayStoryBeatEvent = RemoteEventUtils.GetOrCreate("PlayStoryBeatEvent")
local StoryBeatCompleteEvent = RemoteEventUtils.GetOrCreate("StoryBeatCompleteEvent")
local PlayBackgroundMusicEvent = RemoteEventUtils.GetOrCreate("PlayBackgroundMusicEvent")
local StopBackgroundMusicEvent = RemoteEventUtils.GetOrCreate("StopBackgroundMusicEvent")
local PlaySirenSoundEvent = RemoteEventUtils.GetOrCreate("PlaySirenSoundEvent")
local StopSirenSoundEvent = RemoteEventUtils.GetOrCreate("StopSirenSoundEvent")
local SetSirenVolumeEvent = RemoteEventUtils.GetOrCreate("SetSirenVolumeEvent")
local FadeOutAllSoundEvent = RemoteEventUtils.GetOrCreate("FadeOutAllSoundEvent")
local ResumeNormalMusicEvent = RemoteEventUtils.GetOrCreate("ResumeNormalMusicEvent")
local FadeMusicToNormalVolumeEvent = RemoteEventUtils.GetOrCreate("FadeMusicToNormalVolumeEvent")
local PauseNormalMusicEvent = RemoteEventUtils.GetOrCreate("PauseNormalMusicEvent")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== GUI-Aufbau (einmalig beim Start) =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StoryBeatGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100 -- über allem anderen HUD
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local blackScreen = Instance.new("Frame")
blackScreen.Name = "BlackScreen"
blackScreen.Size = UDim2.new(1, 0, 1, 0)
blackScreen.BackgroundColor3 = Color3.new(0, 0, 0)
blackScreen.BackgroundTransparency = 0 -- startet schwarz
blackScreen.BorderSizePixel = 0
blackScreen.ZIndex = 1
blackScreen.Parent = screenGui

-- Einzelne Textzeile (für "text"-Schritte, z.B. "THE CITY IS ALREADY LOST.")
local textLabel = Instance.new("TextLabel")
textLabel.Name = "StoryText"
textLabel.Size = UDim2.new(0.82, 0, 0.3, 0)
textLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
textLabel.BackgroundTransparency = 1
textLabel.Font = Enum.Font.LuckiestGuy
textLabel.TextScaled = true
textLabel.TextColor3 = Color3.new(1, 1, 1)
textLabel.TextTransparency = 1
textLabel.TextStrokeTransparency = 1
textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
textLabel.TextWrapped = true
textLabel.Text = ""
textLabel.ZIndex = 2
textLabel.Parent = screenGui

-- Zwei gestapelte Zeilen für den ZEITVERSETZTEN Zweizeiler (z.B. "POWER CAN BE
-- BROKEN." / "PURPOSE CANNOT.") -- erste Zeile erscheint, kurzer Beat, dann die zweite
-- hinterher, statt beide gleichzeitig einzublenden. Separat von textLabel oben, damit
-- normale einzeilige Texte unverändert bleiben.
local twoLineContainer = Instance.new("Frame")
twoLineContainer.Name = "TwoLineContainer"
twoLineContainer.Size = UDim2.new(0.82, 0, 0.3, 0)
twoLineContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
twoLineContainer.AnchorPoint = Vector2.new(0.5, 0.5)
twoLineContainer.BackgroundTransparency = 1
twoLineContainer.ZIndex = 2
twoLineContainer.Parent = screenGui

local function createStackedLineLabel(verticalPosition)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.48, 0)
	label.Position = UDim2.new(0.5, 0, verticalPosition, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextWrapped = true
	label.Text = ""
	label.Parent = twoLineContainer
	return label
end

local lineLabel1 = createStackedLineLabel(0.26)
local lineLabel2 = createStackedLineLabel(0.74)

-- Kapitel-Titelkarte: Nummer + Titel + Untertitel (z.B. "CHAPTER I / KAIJU / POWER")
-- Bewusst deutlich "epischer"/prunkvoller als der normale Story-Text gestaltet: Gold-
-- Farbschema mit Verlauf, dekorative Trennlinien, skalierte Einblend-Animation statt
-- reinem Fade -- damit klar erkennbar ist "das hier ist ein KAPITEL-Übergang", nicht nur
-- eine weitere Textzeile.
local chapterFrame = Instance.new("Frame")
chapterFrame.Name = "ChapterCard"
chapterFrame.Size = UDim2.new(1, 0, 1, 0)
chapterFrame.BackgroundTransparency = 1
chapterFrame.ZIndex = 2
chapterFrame.Visible = false
chapterFrame.Parent = screenGui

local chapterNumberLabel = Instance.new("TextLabel")
chapterNumberLabel.Name = "Number"
chapterNumberLabel.Size = UDim2.new(1, 0, 0, 30)
chapterNumberLabel.Position = UDim2.new(0.5, 0, 0.32, 0)
chapterNumberLabel.AnchorPoint = Vector2.new(0.5, 0.5)
chapterNumberLabel.BackgroundTransparency = 1
chapterNumberLabel.Font = Enum.Font.FredokaOne
chapterNumberLabel.TextScaled = true
chapterNumberLabel.TextColor3 = Color3.fromRGB(230, 195, 120) -- warmes Gold, klar anders als der weisse Story-Text
chapterNumberLabel.TextTransparency = 1
chapterNumberLabel.Text = ""
chapterNumberLabel.Parent = chapterFrame

-- Dekorative Trennlinie unter der Nummer -- unterstreicht den "offiziellen Titelkarte"-
-- Charakter, fehlt beim normalen Story-Text komplett.
local chapterDividerTop = Instance.new("Frame")
chapterDividerTop.Name = "DividerTop"
chapterDividerTop.Size = UDim2.new(0, 140, 0, 3)
chapterDividerTop.Position = UDim2.new(0.5, 0, 0.375, 0)
chapterDividerTop.AnchorPoint = Vector2.new(0.5, 0.5)
chapterDividerTop.BackgroundColor3 = Color3.fromRGB(230, 195, 120)
chapterDividerTop.BackgroundTransparency = 1
chapterDividerTop.BorderSizePixel = 0
chapterDividerTop.Parent = chapterFrame

local chapterTitleLabel = Instance.new("TextLabel")
chapterTitleLabel.Name = "Title"
chapterTitleLabel.Size = UDim2.new(1, 0, 0, 120)
chapterTitleLabel.Position = UDim2.new(0.5, 0, 0.49, 0)
chapterTitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
chapterTitleLabel.BackgroundTransparency = 1
chapterTitleLabel.Font = Enum.Font.LuckiestGuy
chapterTitleLabel.TextScaled = true
chapterTitleLabel.TextColor3 = Color3.fromRGB(255, 240, 210)
chapterTitleLabel.TextTransparency = 1
chapterTitleLabel.TextStrokeTransparency = 1
chapterTitleLabel.TextStrokeColor3 = Color3.fromRGB(40, 25, 5)
chapterTitleLabel.Text = ""
chapterTitleLabel.Parent = chapterFrame

-- Gold-Verlauf über dem Titeltext -- verstärkt den "episch/prunkvoll"-Eindruck zusätzlich
-- zur reinen Farbe.
local chapterTitleGradient = Instance.new("UIGradient")
chapterTitleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 150)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 250, 235)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 180, 100)),
})
chapterTitleGradient.Rotation = 90
chapterTitleGradient.Parent = chapterTitleLabel

-- Skalierung für die "Pop-In"-Einblend-Animation (startet grösser, schrumpft auf normale
-- Grösse während des Einblendens -- deutlich dynamischer als ein reines Fade).
local chapterTitleScale = Instance.new("UIScale")
chapterTitleScale.Scale = 1.3
chapterTitleScale.Parent = chapterTitleLabel

local chapterDividerBottom = Instance.new("Frame")
chapterDividerBottom.Name = "DividerBottom"
chapterDividerBottom.Size = UDim2.new(0, 140, 0, 3)
chapterDividerBottom.Position = UDim2.new(0.5, 0, 0.575, 0)
chapterDividerBottom.AnchorPoint = Vector2.new(0.5, 0.5)
chapterDividerBottom.BackgroundColor3 = Color3.fromRGB(230, 195, 120)
chapterDividerBottom.BackgroundTransparency = 1
chapterDividerBottom.BorderSizePixel = 0
chapterDividerBottom.Parent = chapterFrame

local chapterSubtitleLabel = Instance.new("TextLabel")
chapterSubtitleLabel.Name = "Subtitle"
chapterSubtitleLabel.Size = UDim2.new(1, 0, 0, 32)
chapterSubtitleLabel.Position = UDim2.new(0.5, 0, 0.625, 0)
chapterSubtitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
chapterSubtitleLabel.BackgroundTransparency = 1
chapterSubtitleLabel.Font = Enum.Font.FredokaOne
chapterSubtitleLabel.TextScaled = true
chapterSubtitleLabel.TextColor3 = Color3.fromRGB(230, 195, 120)
chapterSubtitleLabel.TextTransparency = 1
chapterSubtitleLabel.Text = ""
chapterSubtitleLabel.Parent = chapterFrame

-- ===== Schritt-Ausführer =====
-- Laufende Sounds werden gesammelt, damit sie am Ende der GESAMTEN Sequenz sicher
-- gestoppt werden -- auch solche, die im Hintergrund weiterliefen (z.B. Ticken).
local activeSounds = {}

local function stopAllSounds()
	for _, sound in ipairs(activeSounds) do
		if sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end
	activeSounds = {}
end

local function runFadeStep(targetTransparency, step)
	local tween = TweenService:Create(
		blackScreen,
		TweenInfo.new(step.duration or 1, Enum.EasingStyle.Sine),
		{ BackgroundTransparency = targetTransparency }
	)
	tween:Play()
	tween.Completed:Wait()
end

local function runWaitStep(step)
	task.wait(step.duration or 1)
end

local function runSoundStep(step)
	local sound = Instance.new("Sound")
	sound.SoundId = step.soundId or ""
	sound.Volume = step.volume or 1
	sound.Looped = step.looped or false
	sound.Parent = screenGui
	sound:Play()
	table.insert(activeSounds, sound)
	if step.wait then
		sound.Ended:Wait()
	end
end

local function runTextStep(step)
	local text = step.text or ""
	local newlineIndex = text:find("\n")

	if newlineIndex then
		-- ===== Zeitversetzter Zweizeiler: erste Zeile, kurzer Beat, dann die zweite
		-- hinterher -- wirkt pointierter als beide gleichzeitig einzublenden. Automatisch
		-- erkannt, sobald der Text ein \n enthält (z.B. "POWER CAN BE BROKEN.\nPURPOSE
		-- CANNOT.").
		local line1 = text:sub(1, newlineIndex - 1)
		local line2 = text:sub(newlineIndex + 1)

		lineLabel1.Text = line1
		lineLabel2.Text = line2

		local fadeInDuration = step.fadeIn or 0.4
		local fadeOutDuration = step.fadeOut or 0.4
		local holdDuration = step.duration or 3.5
		local lineDelay = step.lineDelay or 1.4 -- Beat zwischen den beiden Zeilen

		local fadeInLine1 = TweenService:Create(
			lineLabel1,
			TweenInfo.new(fadeInDuration),
			{ TextTransparency = 0, TextStrokeTransparency = 0.3 }
		)
		fadeInLine1:Play()
		fadeInLine1.Completed:Wait()

		task.wait(lineDelay)

		local fadeInLine2 = TweenService:Create(
			lineLabel2,
			TweenInfo.new(fadeInDuration),
			{ TextTransparency = 0, TextStrokeTransparency = 0.3 }
		)
		fadeInLine2:Play()
		fadeInLine2.Completed:Wait()

		-- Restliche Haltezeit, abzüglich der bereits durch den Zeilen-Beat verstrichenen
		-- Zeit -- damit "duration" weiterhin die GESAMTE sichtbare Dauer der Karte meint.
		local remainingHold = math.max(holdDuration - lineDelay - fadeInDuration, 0)
		task.wait(remainingHold)

		local fadeOutBoth = TweenService:Create(
			lineLabel1,
			TweenInfo.new(fadeOutDuration),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		local fadeOutBoth2 = TweenService:Create(
			lineLabel2,
			TweenInfo.new(fadeOutDuration),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fadeOutBoth:Play()
		fadeOutBoth2:Play()
		fadeOutBoth.Completed:Wait()
		return
	end

	textLabel.Text = text
	local fadeInDuration = step.fadeIn or 0.4
	local fadeOutDuration = step.fadeOut or 0.4
	local holdDuration = step.duration or 2

	local fadeInTween = TweenService:Create(
		textLabel,
		TweenInfo.new(fadeInDuration),
		{ TextTransparency = 0, TextStrokeTransparency = 0.3 }
	)
	fadeInTween:Play()
	fadeInTween.Completed:Wait()

	task.wait(holdDuration)

	local fadeOutTween = TweenService:Create(
		textLabel,
		TweenInfo.new(fadeOutDuration),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	fadeOutTween:Play()
	fadeOutTween.Completed:Wait()
end

-- "hint": leichter Onboarding-Hinweis (z.B. "PUNCH", "JUMP + LAND") -- läuft WÄHREND des
-- laufenden Gameplays, OHNE die Schwarzblende/den restlichen Sequenz-Ablauf zu berühren.
-- Bewusst GROSS und weit oben positioniert (nicht am unteren Bildschirmrand, wo es neben
-- HUD-Elementen/während aktivem Kampf leicht übersehen wird).
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintLabel"
hintLabel.Size = UDim2.new(0.7, 0, 0, 90)
hintLabel.Position = UDim2.new(0.5, 0, 0.38, 0) -- Bildschirmmitte-oberhalb -- bewusst NICHT im Bereich der oberen HUD-Cluster (Health/Level/XP, Stats), die dort überlappen würden
hintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
hintLabel.BackgroundTransparency = 1
hintLabel.Font = Enum.Font.LuckiestGuy
hintLabel.TextScaled = true
hintLabel.TextColor3 = Color3.fromRGB(255, 240, 150)
hintLabel.TextStrokeTransparency = 1
hintLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
hintLabel.TextTransparency = 1
hintLabel.Text = ""
hintLabel.ZIndex = 2
hintLabel.Parent = screenGui

local hintLabelScale = Instance.new("UIScale")
hintLabelScale.Scale = 1.25
hintLabelScale.Parent = hintLabel

local hintGeneration = 0

local function runHintStep(step)
	hintGeneration += 1
	local myGeneration = hintGeneration

	screenGui.Enabled = true -- "hint" braucht die GUI, OHNE die Schwarzblende zu berühren
	hintLabel.Text = step.text or ""
	hintLabelScale.Scale = 1.25 -- vor jedem Einblenden zurücksetzen (Pop-In-Ausgangszustand)

	local fadeInTween = TweenService:Create(
		hintLabel,
		TweenInfo.new(step.fadeIn or 0.35),
		{ TextTransparency = 0, TextStrokeTransparency = 0.15 }
	)
	fadeInTween:Play()
	TweenService:Create(
		hintLabelScale,
		TweenInfo.new(step.fadeIn or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	task.spawn(function()
		task.wait(step.duration or 3)
		if hintGeneration ~= myGeneration then
			return -- ein neuerer Hint hat diesen bereits ersetzt
		end
		local fadeOutTween = TweenService:Create(
			hintLabel,
			TweenInfo.new(step.fadeOut or 0.5),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fadeOutTween:Play()
	end)
	-- WICHTIG: kein :Wait() hier -- "hint" blockiert die aufrufende Sequenz NICHT,
	-- läuft im Hintergrund weiter aus (relevant nur, falls "hint" je als Teil einer
	-- vollständigen Play()-Sequenz statt PlayAsync() genutzt wird).
end

local function runChapterCardStep(step)
	print("[Kaiju-Debug] runChapterCardStep AUFGERUFEN: title='" .. tostring(step.title) .. "' number='" .. tostring(step.number) .. "' tick=" .. tostring(os.clock()))
	chapterNumberLabel.Text = step.number and ("CHAPTER " .. step.number) or ""
	chapterTitleLabel.Text = step.title or ""
	chapterSubtitleLabel.Text = step.subtitle or ""
	chapterFrame.Visible = true
	chapterTitleScale.Scale = 1.3 -- vor jedem Einblenden zurücksetzen (Pop-In-Ausgangszustand)

	local fadeInDuration = step.fadeIn or 1.0
	local fadeOutDuration = step.fadeOut or 0.8
	local holdDuration = step.duration or 3.5

	local fadeInTweens = {
		TweenService:Create(chapterNumberLabel, TweenInfo.new(fadeInDuration), { TextTransparency = 0 }),
		TweenService:Create(chapterDividerTop, TweenInfo.new(fadeInDuration), { BackgroundTransparency = 0.15 }),
		TweenService:Create(chapterTitleLabel, TweenInfo.new(fadeInDuration), { TextTransparency = 0, TextStrokeTransparency = 0.15 }),
		TweenService:Create(chapterTitleScale, TweenInfo.new(fadeInDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }),
		TweenService:Create(chapterDividerBottom, TweenInfo.new(fadeInDuration), { BackgroundTransparency = 0.15 }),
		TweenService:Create(chapterSubtitleLabel, TweenInfo.new(fadeInDuration), { TextTransparency = 0 }),
	}
	for _, tween in ipairs(fadeInTweens) do
		tween:Play()
	end
	fadeInTweens[1].Completed:Wait()

	task.wait(holdDuration)

	local fadeOutTweens = {
		TweenService:Create(chapterNumberLabel, TweenInfo.new(fadeOutDuration), { TextTransparency = 1 }),
		TweenService:Create(chapterDividerTop, TweenInfo.new(fadeOutDuration), { BackgroundTransparency = 1 }),
		TweenService:Create(chapterTitleLabel, TweenInfo.new(fadeOutDuration), { TextTransparency = 1, TextStrokeTransparency = 1 }),
		TweenService:Create(chapterDividerBottom, TweenInfo.new(fadeOutDuration), { BackgroundTransparency = 1 }),
		TweenService:Create(chapterSubtitleLabel, TweenInfo.new(fadeOutDuration), { TextTransparency = 1 }),
	}
	for _, tween in ipairs(fadeOutTweens) do
		tween:Play()
	end
	fadeOutTweens[1].Completed:Wait()

	chapterFrame.Visible = false
end

-- "revealBackground": startet eine LANGSAME, NICHT-blockierende Aufhellung des
-- schwarzen Overlays auf eine Ziel-Transparenz -- läuft im Hintergrund WÄHREND die
-- nachfolgenden Schritte (z.B. eine Titelkarte) normal weiterlaufen, blockiert die
-- Sequenz also NICHT wie die anderen Schritt-Typen. Für Momente wie "der Trench schält
-- sich langsam aus dem Schwarz, während der Titel steht".
local function runRevealBackgroundStep(step)
	local targetTransparency = step.targetTransparency or 0.5
	local tween = TweenService:Create(
		blackScreen,
		TweenInfo.new(step.duration or 3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ BackgroundTransparency = targetTransparency }
	)
	tween:Play()
	-- WICHTIG: kein :Wait() hier -- dieser Schritt-Typ ist bewusst nicht-blockierend.
end

local STEP_HANDLERS = {
	fadeIn = function(step) runFadeStep(0, step) end,
	fadeOut = function(step) runFadeStep(1, step) end,
	wait = runWaitStep,
	text = runTextStep,
	hint = runHintStep,
	chapterCard = runChapterCardStep,
	sound = runSoundStep,
	revealBackground = runRevealBackgroundStep,
}

local sequenceCounter = 0
local currentSequenceId = 0 -- die zuletzt gestartete Sequenz -- ältere Coroutinen erkennen daran, dass sie überholt wurden

local function playSequence(sequence)
	sequenceCounter += 1
	local sequenceId = sequenceCounter
	currentSequenceId = sequenceId
	print("[Kaiju-Debug] StoryBeatClient: playSequence #" .. sequenceId .. " STARTET -- tick=" .. tostring(os.clock()) .. " Schritte=" .. #(sequence.steps or {}) .. " keepBlackScreen=" .. tostring(sequence.keepBlackScreen))

	-- Reine Hint-Sequenzen (nur "hint"-Schritte, z.B. Onboarding-Prompts während des
	-- laufenden Gameplays) sollen NICHT die Schwarzblende auslösen -- der Spieler soll
	-- währenddessen weiterspielen können. Nur "echte" Cutscene-Schritte (fadeIn/fadeOut/
	-- text/chapterCard/sound) rechtfertigen die Vollbild-Initialisierung.
	-- Nur "echte" Vollbild-Schritte (fadeIn/fadeOut/text/chapterCard) rechtfertigen die
	-- Schwarzblende. "hint"/"sound"/"wait" sind bewusst NEUTRAL -- eine Sequenz, die z.B.
	-- nur einen Ticken-Sound + einen "hint" kombiniert (Guardian-Auftritt: Spieler soll
	-- dabei weiterspielen können), soll NICHT die Schwarzblende auslösen.
	local FULLSCREEN_STEP_TYPES = { fadeIn = true, fadeOut = true, text = true, chapterCard = true }
	local requiresFullscreen = false
	for _, step in ipairs(sequence.steps or {}) do
		if FULLSCREEN_STEP_TYPES[step.type] then
			requiresFullscreen = true
			break
		end
	end

	screenGui.Enabled = true
	if requiresFullscreen then
		if not sequence.preserveTransparency then
			blackScreen.BackgroundTransparency = 0 -- jede "echte" Sequenz startet mit schwarzem Screen -- übersprungen, falls preserveTransparency (Fortsetzung einer bereits aufgehellten Sequenz)
		end
		textLabel.Text = ""
		textLabel.TextTransparency = 1
		textLabel.TextStrokeTransparency = 1
		lineLabel1.Text = ""
		lineLabel1.TextTransparency = 1
		lineLabel1.TextStrokeTransparency = 1
		lineLabel2.Text = ""
		lineLabel2.TextTransparency = 1
		lineLabel2.TextStrokeTransparency = 1
	end

	for _, step in ipairs(sequence.steps or {}) do
		-- Sicherung gegen Überlappung: falls währenddessen eine NEUERE Sequenz gestartet
		-- wurde (z.B. durch einen doppelten/zu frühen Server-Aufruf), bricht diese ältere
		-- Coroutine hier sofort ab, statt mit der neuen um dieselben UI-Elemente zu
		-- konkurrieren.
		if currentSequenceId ~= sequenceId then
			warn("[StoryBeatClient] playSequence #" .. sequenceId .. " abgebrochen -- überholt von #" .. currentSequenceId .. " -- tick=" .. tostring(os.clock()))
			return
		end

		local handler = STEP_HANDLERS[step.type]
		if handler then
			print("[Kaiju-Debug] StoryBeatClient: #" .. sequenceId .. " starte Schritt '" .. tostring(step.type) .. "' -- tick=" .. tostring(os.clock()))
			local ok, err = pcall(handler, step)
			if not ok then
				warn("[StoryBeatClient] Fehler bei Schritt-Typ '" .. tostring(step.type) .. "': " .. tostring(err))
			else
				print("[Kaiju-Debug] StoryBeatClient: #" .. sequenceId .. " Schritt '" .. tostring(step.type) .. "' fertig -- tick=" .. tostring(os.clock()))
			end
		else
			warn("[StoryBeatClient] Unbekannter Schritt-Typ: " .. tostring(step.type))
		end
	end

	if currentSequenceId ~= sequenceId then
		-- Wurde ganz am Ende noch überholt -- nicht mehr aufräumen/Completion feuern,
		-- das übernimmt die neuere Sequenz.
		return
	end

	stopAllSounds()

	-- "keepBlackScreen": Sequenz endet bewusst mit schwarzem Screen, der GUI-Container
	-- bleibt aktiv (z.B. wenn direkt danach noch ein Teleport/Szenenwechsel folgt und
	-- der schwarze Screen nahtlos bestehen bleiben soll, statt kurz das Spiel zu zeigen).
	-- Bei reinen Hint-Sequenzen bleibt der Container ebenfalls aktiv -- das Ausblenden des
	-- Hints läuft asynchron (siehe runHintStep) und würde sonst mitten im Fade abgeschnitten.
	if not sequence.keepBlackScreen and not requiresFullscreen then
		screenGui.Enabled = false
	end

	print("[Kaiju-Debug] StoryBeatClient: playSequence #" .. sequenceId .. " FERTIG -- tick=" .. tostring(os.clock()))
	StoryBeatCompleteEvent:FireServer()
end

PlayStoryBeatEvent.OnClientEvent:Connect(function(sequence)
	print("[Kaiju-Debug] StoryBeatClient: PlayStoryBeatEvent empfangen -- tick=" .. tostring(os.clock()))
	task.spawn(playSequence, sequence)
end)

-- ===== Langlebige Hintergrundmusik =====
-- Anders als Sounds innerhalb einer normalen Sequenz (werden bei Sequenz-Ende automatisch
-- gestoppt, siehe stopAllSounds) läuft diese Musik unabhängig weiter, bis StopMusic()
-- explizit aufgerufen wird -- gedacht für durchgehende Hintergrundmusik über mehrere
-- Cutscene-Aufrufe/Gameplay-Phasen hinweg (z.B. während der Prolog-Power-Fantasy-Phase).
local backgroundMusicSound = Instance.new("Sound")
backgroundMusicSound.Name = "StoryBeatBackgroundMusic"
backgroundMusicSound.Looped = true
backgroundMusicSound.Parent = screenGui

PlayBackgroundMusicEvent.OnClientEvent:Connect(function(musicId, volume)
	if _G.PauseBackgroundMusic then
		_G.PauseBackgroundMusic() -- normale Hintergrundmusik (BackgroundMusicClient.lua) stumm, während die Prolog-Musik läuft
	end
	backgroundMusicSound.SoundId = musicId or ""
	backgroundMusicSound.Volume = volume or 0.5
	backgroundMusicSound:Play()
end)

StopBackgroundMusicEvent.OnClientEvent:Connect(function()
	backgroundMusicSound:Stop()
end)

-- Eigenständiger Sirenen-Sound-Kanal -- getrennt vom Musik-Kanal (oben, bereits für die
-- Prolog-Musik genutzt) UND vom sequenz-gebundenen "sound"-Schritt (der bei jedem
-- Play()-Sequenz-Ende automatisch alle Sounds stoppt, siehe stopAllSounds). Ohne diese
-- Trennung würde die Sirene beim Übergang zwischen zwei Play()-Aufrufen (z.B. im
-- gesplitteten Cold Open) entweder abrupt abbrechen oder hörbar doppelt starten.
local sirenSound = Instance.new("Sound")
sirenSound.Name = "StoryBeatSiren"
sirenSound.Looped = true
sirenSound.Parent = screenGui

PlaySirenSoundEvent.OnClientEvent:Connect(function(soundId, volume)
	sirenSound.SoundId = soundId or ""
	sirenSound.Volume = volume or 0.5
	sirenSound:Play()
end)

StopSirenSoundEvent.OnClientEvent:Connect(function()
	sirenSound:Stop()
end)

SetSirenVolumeEvent.OnClientEvent:Connect(function(volume)
	sirenSound.Volume = volume or sirenSound.Volume
end)

ResumeNormalMusicEvent.OnClientEvent:Connect(function(startVolume)
	if _G.ResumeBackgroundMusic then
		_G.ResumeBackgroundMusic(startVolume)
	end
end)

FadeMusicToNormalVolumeEvent.OnClientEvent:Connect(function(duration)
	if _G.FadeBackgroundMusicToNormalVolume then
		_G.FadeBackgroundMusicToNormalVolume(duration)
	end
end)

PauseNormalMusicEvent.OnClientEvent:Connect(function()
	if _G.PauseBackgroundMusic then
		_G.PauseBackgroundMusic()
	end
end)

FadeOutAllSoundEvent.OnClientEvent:Connect(function(duration)
	local fadeDuration = duration or 2
	for _, sound in ipairs({ sirenSound, backgroundMusicSound }) do
		if sound.IsPlaying then
			local tween = TweenService:Create(sound, TweenInfo.new(fadeDuration, Enum.EasingStyle.Sine), { Volume = 0 })
			tween:Play()
		end
	end
	-- Normale Hintergrundmusik (BackgroundMusicClient.lua) ebenfalls ausblenden, falls sie
	-- aus irgendeinem Grund noch läuft (z.B. beim Debug-Testen).
	if _G.FadeOutBackgroundMusic then
		_G.FadeOutBackgroundMusic(fadeDuration)
	end
end)