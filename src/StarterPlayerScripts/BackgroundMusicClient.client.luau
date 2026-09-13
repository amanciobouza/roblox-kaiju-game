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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

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
-- Gleiches Mass wie der Home-Knopf darueber, damit die obere rechte Ecke eine Reihe
-- ergibt statt einer Ansammlung. Vorher gelb mit schwarzem Umriss und Emoji.
muteButton.Size = UDim2.new(0, 44, 0, 44)
muteButton.AnchorPoint = Vector2.new(1, 0)
-- In der Kopfleiste ganz aussen, auf derselben Hoehe wie Home und Geld. Vorher stand
-- er eine Zeile tiefer und machte damit eine zweite Reihe auf -- fuer einen Knopf.
muteButton.Position = UDim2.new(1, -16, 0, 16)
muteButton.AutoButtonColor = false
muteButton.Text = ""
muteButton.Parent = screenGui
HudChrome.Panel(muteButton, { radius = HudChrome.Radius.Small })

local muteIcon = HudChrome.IconImage(muteButton, HudChrome.Icon.Music)
muteIcon.Size = UDim2.new(1, -14, 1, -14)
muteIcon.Position = UDim2.new(0, 7, 0, 7)

local isMuted = false

-- Die gerade laufende Lautstaerke-Bewegung des Absenkens (siehe DuckBackgroundMusic ganz
-- unten). Hier oben deklariert, weil die Stumm-Taste sie abbrechen muss: sonst zoege eine
-- laufende Rueckblende die Lautstaerke gleich wieder hoch, obwohl der Spieler eben erst
-- stumm geschaltet hat.
local activeDuckTween = nil

-- Stumm wird jetzt ueber die Deckkraft des Symbols gezeigt, nicht ueber einen Wechsel
-- des Zeichens: es gibt ein hochgeladenes Musik-Symbol, aber keines fuer "stumm", und
-- ein halbdurchsichtiges Symbol sagt dasselbe, ohne ein zweites Bild zu brauchen.
local function showMuteState()
	muteIcon.ImageTransparency = isMuted and 0.65 or 0
	muteIcon.ImageColor3 = isMuted and HudChrome.Color.TextDim or Color3.new(1, 1, 1)
end
showMuteState()

muteButton.MouseButton1Click:Connect(function()
	isMuted = not isMuted
	if activeDuckTween then
		activeDuckTween:Cancel()
		activeDuckTween = nil
	end
	backgroundMusic.Volume = isMuted and 0 or MUSIC_VOLUME
	showMuteState()
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

-- ===== Kurzes Absenken fuer einen Klang, der vorgehen soll =====
-- Ein Fanfaren-Klang geht in der laufenden Musik unter, wenn beide gleich laut bleiben.
-- Statt den Klang lauter zu machen -- was ihn nur schrill macht -- tritt hier die Musik
-- kurz zurueck: schnell runter, halten, langsam wieder hoch. Das Ohr hoert die Fanfare
-- dann klar, ohne dass die Lautstaerke insgesamt steigt.
--
-- Genutzt vom LevelUpFeedbackClient beim Stufenaufstieg.
local DUCK_FACTOR = 0.3 -- auf 30% der normalen Lautstaerke
local DUCK_FADE_DOWN = 0.15 -- schnell zurueckweichen, damit der Klang die Luecke trifft
local DUCK_HOLD_DEFAULT = 1.2
local DUCK_FADE_UP = 0.9 -- langsam zurueckkommen, sonst wirkt es wie ein Aussetzer

-- Sitzungsnummer nach dem Muster der Kameraschleifen: kommt waehrend einer laufenden
-- Absenkung eine zweite, gehoert die Rueckblende der NEUEREN. Ohne das wuerde die
-- Rueckblende der ersten mitten in die zweite Absenkung hineinfahren.
local duckSession = 0

_G.DuckBackgroundMusic = function(holdSeconds)
	if isMuted or not backgroundMusic.IsPlaying then
		return
	end

	duckSession += 1
	local session = duckSession

	if activeDuckTween then
		activeDuckTween:Cancel()
	end
	activeDuckTween = TweenService:Create(
		backgroundMusic,
		TweenInfo.new(DUCK_FADE_DOWN, Enum.EasingStyle.Sine),
		{ Volume = MUSIC_VOLUME * DUCK_FACTOR }
	)
	activeDuckTween:Play()

	task.delay(DUCK_FADE_DOWN + (holdSeconds or DUCK_HOLD_DEFAULT), function()
		if session ~= duckSession or isMuted then
			return
		end
		activeDuckTween = TweenService:Create(
			backgroundMusic,
			TweenInfo.new(DUCK_FADE_UP, Enum.EasingStyle.Sine),
			{ Volume = MUSIC_VOLUME }
		)
		activeDuckTween:Play()
	end)
end