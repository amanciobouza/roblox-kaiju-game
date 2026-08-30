-- VERSION: 2026-08-26 #5
-- FEATURE: ResumeBackgroundMusic mit optionaler Start-Lautstaerke, FadeBackgroundMusicToNormalVolume ergaenzt
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Spielt eine Hintergrundmusik in Dauerschleife und zeigt eine kleine Stumm-Taste
-- (oben rechts, im Comic-Style passend zum restlichen HUD). Läuft während eines aktiven
-- Trainings-Boosts 25% schneller (spürbarer "Energie-Schub"-Effekt).

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- WICHTIG: Trag hier deine eigene Musik-ID aus dem Creator Store ein (Format: "rbxassetid://12345678")
local BACKGROUND_MUSIC_ID = "rbxassetid://88984808998362"
local MUSIC_VOLUME = 0.25
local BOOST_PLAYBACK_SPEED = 1.25 -- 25% schneller während des Trainings-Boosts
local PLAYBACK_SPEED_TWEEN_TIME = 0.3

local backgroundMusic = Instance.new("Sound")
backgroundMusic.Name = "BackgroundMusic"
backgroundMusic.SoundId = BACKGROUND_MUSIC_ID
backgroundMusic.Looped = true
backgroundMusic.Volume = MUSIC_VOLUME
backgroundMusic.Parent = SoundService

if backgroundMusic.SoundId ~= "" and backgroundMusic.SoundId ~= "rbxassetid://0" then
	backgroundMusic:Play()
end

-- ===== Wiedergabegeschwindigkeit an Trainings-Boost (schneller) UND Meltdown
-- (langsamer) koppeln -- Meltdown hat Vorrang, falls beide zufällig gleichzeitig aktiv
-- wären (kommt praktisch kaum vor, aber zur Sicherheit klar geregelt). =====
local MELTDOWN_PLAYBACK_SPEED = 0.75 -- 25% langsamer während Meltdown
local currentTargetSpeed = 1

local function getTargetPlaybackSpeed()
	local heat = player:GetAttribute("Heat") or 0
	if heat >= 100 then
		return MELTDOWN_PLAYBACK_SPEED
	end

	local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
	if Workspace:GetServerTimeNow() < boostEndsAt then
		return BOOST_PLAYBACK_SPEED
	end

	return 1
end

RunService.Heartbeat:Connect(function()
	local targetSpeed = getTargetPlaybackSpeed()
	if targetSpeed ~= currentTargetSpeed then
		currentTargetSpeed = targetSpeed
		TweenService:Create(backgroundMusic, TweenInfo.new(PLAYBACK_SPEED_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			PlaybackSpeed = targetSpeed,
		}):Play()
	end
end)

-- ===== Stumm-Taste: oben rechts, Comic-Style =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MusicControlGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local muteButton = Instance.new("TextButton")
muteButton.Name = "MuteButton"
-- Gleiche Grösse wie der Menü-Button (oben links, NavigationClient.lua) für ein
-- einheitliches Bild. Direkt unterhalb des Home-Buttons platziert (der reicht bis
-- y=16+42=58), mit Abstand statt der bisherigen Überlappung.
muteButton.Size = UDim2.new(0, 52, 0, 48)
muteButton.AnchorPoint = Vector2.new(1, 0)
muteButton.Position = UDim2.new(1, -16, 0, 66)
muteButton.BackgroundColor3 = Color3.fromRGB(255, 205, 30)
muteButton.Font = Enum.Font.LuckiestGuy
muteButton.TextScaled = true
muteButton.Text = "🔊"
muteButton.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 16)
corner.Parent = muteButton

local stroke = Instance.new("UIStroke")
stroke.Thickness = 5
stroke.Color = Color3.fromRGB(0, 0, 0)
stroke.Parent = muteButton

local isMuted = false

muteButton.MouseButton1Click:Connect(function()
	isMuted = not isMuted
	backgroundMusic.Volume = isMuted and 0 or MUSIC_VOLUME
	muteButton.Text = isMuted and "🔇" or "🔊"
end)

-- ===== Pause/Resume von aussen (z.B. StoryBeatClient.lua während des Prologs) =====
-- Getrennt vom Stumm-Status (isMuted) -- eine Pause hier merkt sich NICHT, ob der
-- Spieler manuell stummgeschaltet hatte, und stellt beim Fortsetzen den korrekten
-- vorherigen Zustand wieder her.
local wasPlayingBeforePause = false

_G.PauseBackgroundMusic = function()
	wasPlayingBeforePause = backgroundMusic.IsPlaying
	backgroundMusic:Pause()
end

_G.FadeOutBackgroundMusic = function(duration)
	if not backgroundMusic.IsPlaying then
		return
	end
	local tween = TweenService:Create(backgroundMusic, TweenInfo.new(duration or 2, Enum.EasingStyle.Sine), { Volume = 0 })
	tween:Play()
	tween.Completed:Connect(function()
		wasPlayingBeforePause = backgroundMusic.IsPlaying
		backgroundMusic:Pause()
		backgroundMusic.Volume = MUSIC_VOLUME -- für den nächsten Resume wiederherstellen
	end)
end

_G.ResumeBackgroundMusic = function(startVolume)
	-- WICHTIG (Bugfix): startet IMMER von vorne, unabhängig von wasPlayingBeforePause --
	-- diese Prüfung war für das alte "an der pausierten Stelle fortsetzen"-Verhalten
	-- gedacht. Für "von vorne starten" (siehe PrologueOrchestrator.lua -- synchron zur
	-- "WE ARE TRENCHBORN"-Titelkarte) ist sie falsch: bei einem echten Erstspieler, dessen
	-- Hintergrundmusik noch nie lief (IsPlaying=false) bevor der Prolog sie pausiert hat,
	-- wäre wasPlayingBeforePause=false gewesen -- die Musik wäre dann NIE gestartet.
	-- startVolume (optional): für dramatische Momente wie "WE ARE TRENCHBORN", bei denen
	-- die Musik SOFORT voll laut einsetzen soll, statt bei der normalen Gameplay-
	-- Lautstärke zu beginnen (siehe FadeBackgroundMusicToVolume weiter unten, um später
	-- sanft auf normal herunterzufahren).
	backgroundMusic.Volume = startVolume or MUSIC_VOLUME
	backgroundMusic.TimePosition = 0
	backgroundMusic:Play()
end

-- Fährt die Hintergrundmusik-Lautstärke sanft auf die normale Gameplay-Lautstärke
-- (MUSIC_VOLUME) herunter -- genutzt, um von einem lauten dramatischen Moment (siehe
-- ResumeBackgroundMusic mit startVolume) zurück zur normalen Lautstärke überzublenden,
-- sobald der Spieler die Kontrolle übernimmt.
_G.FadeBackgroundMusicToNormalVolume = function(duration)
	local tween = TweenService:Create(backgroundMusic, TweenInfo.new(duration or 2, Enum.EasingStyle.Sine), { Volume = MUSIC_VOLUME })
	tween:Play()
end