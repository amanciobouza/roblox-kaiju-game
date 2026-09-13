-- VERSION: 2026-09-13 #1
-- ModuleScript: HudCenterNotice
-- Ort in Studio: ReplicatedStorage
--
-- ===== Die Mitte des Bildschirms =====
--
-- Die Bildmitte ist der teuerste Platz im HUD: dort steht die Spielfigur, dorthin schaut
-- man ohnehin. Was hier erscheint, unterbricht. Deshalb gibt es genau ZWEI Register, und
-- jedes hat einen festen Anlass:
--
--   WARNUNG   Etwas steht bevor und man kann noch handeln.
--             Kompaktes rotes Schild, pulsiert, kurzer Alarmton, haelt ein paar Sekunden
--             und geht von selbst wieder. Es sagt WAS kommt, nicht wann.
--
--   EREIGNIS  Etwas ist eingetreten und aendert die Lage.
--             Gross, animiert, mit eigener Choreografie und dem Ton des Ereignisses.
--             Kuerzer als die Warnung, dafuer lauter.
--
-- Die Regel dahinter: eine Warnung darf man ignorieren, ein Ereignis muss man zur
-- Kenntnis nehmen. Deshalb ist die Warnung leiser und laenger, das Ereignis lauter und
-- kuerzer -- nicht umgekehrt.
--
-- Beide teilen sich die Formsprache: ein durchlaessiges Band, das an beiden Enden ins
-- Nichts auslaeuft. Bewusst KEIN Kasten mit Rahmen -- ein Kasten liest sich als weitere
-- Anzeige, die man abhakt; ein Band liest sich als Stoerung im Bild.
--
-- Dieses Modul besitzt die Mitte. Es stellt die Warnung selbst dar und haelt die
-- gemeinsamen Teile bereit, damit ein Ereignis (heute: die Alarm-Eskalation) dieselbe
-- Sprache spricht, ohne sie ein zweites Mal zu bauen. Und es fuehrt Buch darueber, ob die
-- Mitte gerade belegt ist -- zwei Meldungen uebereinander waeren keine.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

local HudCenterNotice = {}

-- Beide Register sitzen auf derselben Hoehe: leicht ueber der Mitte, damit die Spielfigur
-- frei bleibt. Wer sie verschiebt, verschiebt beide -- das ist der Sinn der Konstante.
HudCenterNotice.Y_SCALE = 0.34

local BAND_BREITE = 640
local BAND_HOEHE = 96
local WARN_HALTEDAUER = 2.6

-- ===== Gemeinsame Formsprache =====
--
-- Ein Band ohne Kante: deckend in der Mitte, an beiden Enden durchsichtig. Der Verlauf
-- macht die Form -- ohne ihn waere es ein Rechteck, und ein Rechteck ist ein Kasten.
function HudCenterNotice.ApplyBandLook(frame, color, transparency)
	frame.BackgroundColor3 = color or HudChrome.Color.Danger
	frame.BackgroundTransparency = transparency or 0.45
	frame.BorderSizePixel = 0

	local verlauf = Instance.new("UIGradient")
	verlauf.Name = "BandFade"
	verlauf.Rotation = 0
	verlauf.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, 0),
		NumberSequenceKeypoint.new(0.78, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	verlauf.Parent = frame

	return verlauf
end

-- ===== Belegung =====
--
-- Nur eine Meldung zur Zeit. Ohne diese Sperre koennte eine Warnung mitten in eine
-- Eskalation platzen -- und beide meinen dasselbe Thema, was den Widerspruch besonders
-- unangenehm machte.
local belegt = false

function HudCenterNotice.IsBusy()
	return belegt
end

function HudCenterNotice.SetBusy(value)
	belegt = value and true or false
end

-- ===== Aufbau (nur auf dem Client) =====
local screenGui = nil
local warnFrame, warnIcon, warnTitle, warnDetail, warnPuls
local warnSound = nil
local warnToken = 0

local function baueOberflaeche()
	if screenGui or not RunService:IsClient() then
		return screenGui
	end

	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("[Kaiju Debug] HudCenterNotice: PlayerGui nicht gefunden -- Mitte bleibt leer.")
		return nil
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HudCenterNoticeGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 49 -- knapp unter der grossen Ankuendigung (50)
	screenGui.Parent = playerGui

	warnFrame = Instance.new("Frame")
	warnFrame.Name = "WarningSign"
	warnFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	warnFrame.Position = UDim2.new(0.5, 0, HudCenterNotice.Y_SCALE, 0)
	warnFrame.Size = UDim2.new(0, BAND_BREITE, 0, BAND_HOEHE)
	warnFrame.Visible = false
	warnFrame.ZIndex = 30
	warnFrame.Parent = screenGui
	HudCenterNotice.ApplyBandLook(warnFrame)

	-- Zwei helle Kanten oben und unten. Sie machen aus dem Band ein SCHILD: etwas, das
	-- angebracht wurde, statt nur da zu sein. Sie laufen an den Enden genauso aus wie das
	-- Band selbst -- sonst haetten sie eine Kante, wo das Band keine hat.
	for _, oben in ipairs({ true, false }) do
		local kante = Instance.new("Frame")
		kante.Name = oben and "EdgeTop" or "EdgeBottom"
		kante.Size = UDim2.new(1, 0, 0, 2)
		kante.Position = UDim2.new(0, 0, oben and 0 or 1, oben and 0 or -2)
		kante.BackgroundColor3 = HudChrome.Color.Danger
		kante.BackgroundTransparency = 0.1
		kante.BorderSizePixel = 0
		kante.ZIndex = 31
		kante.Parent = warnFrame
		HudCenterNotice.ApplyBandLook(kante, HudChrome.Color.Danger, 0.1)
	end

	warnIcon = HudChrome.IconImage(warnFrame, HudChrome.Icon.Alert)
	warnIcon.Name = "WarningIcon"
	warnIcon.Size = UDim2.new(0, 40, 0, 40)
	warnIcon.Position = UDim2.new(0.5, -260, 0.5, -20)
	warnIcon.ZIndex = 32

	warnTitle = Instance.new("TextLabel")
	warnTitle.Name = "WarningTitle"
	warnTitle.Size = UDim2.new(0, 460, 0, 34)
	warnTitle.Position = UDim2.new(0.5, -206, 0.5, -30)
	warnTitle.BackgroundTransparency = 1
	warnTitle.TextXAlignment = Enum.TextXAlignment.Left
	warnTitle.ZIndex = 32
	warnTitle.Text = ""
	warnTitle.Parent = warnFrame
	HudChrome.Label(warnTitle, 30)

	warnDetail = Instance.new("TextLabel")
	warnDetail.Name = "WarningDetail"
	warnDetail.Size = UDim2.new(0, 460, 0, 22)
	warnDetail.Position = UDim2.new(0.5, -206, 0.5, 4)
	warnDetail.BackgroundTransparency = 1
	warnDetail.TextXAlignment = Enum.TextXAlignment.Left
	warnDetail.ZIndex = 32
	warnDetail.Text = ""
	warnDetail.Parent = warnFrame
	HudChrome.Number(warnDetail, 17)
	warnDetail.TextColor3 = HudChrome.Color.TextSecondary

	warnSound = Instance.new("Sound")
	warnSound.Name = "WarningSound"
	warnSound.Parent = screenGui

	return screenGui
end

-- ===== Register 1: die Warnung =====
--
-- options:
--   title   Die bevorstehende Gefahr, in Grossbuchstaben.
--   detail  Eine Zeile darunter -- was sie bedeutet.
--   soundId Kurzer Alarmton. Leer = still.
--   hold    Wie lange das Schild steht (Sekunden). Ohne Angabe WARN_HALTEDAUER.
function HudCenterNotice.Warn(options)
	options = options or {}
	if not baueOberflaeche() then
		return false
	end
	if belegt then
		-- Ein Ereignis laeuft. Eine Warnung darueber waere Laerm; sie faellt aus.
		return false
	end

	warnToken += 1
	local meinToken = warnToken

	warnTitle.Text = options.title or "WARNING"
	warnDetail.Text = options.detail or ""

	if options.soundId and options.soundId ~= "" and options.soundId ~= "rbxassetid://0" then
		warnSound.SoundId = options.soundId
		warnSound.Volume = options.volume or 0.7
		warnSound.TimePosition = 0
		warnSound:Play()
	end

	-- Auffahren: kurz breiter als die Ruhelage, dann einrasten.
	warnFrame.Visible = true
	warnFrame.BackgroundTransparency = 1
	warnFrame.Size = UDim2.new(0, BAND_BREITE * 0.7, 0, BAND_HOEHE)
	warnTitle.TextTransparency = 1
	warnDetail.TextTransparency = 1
	warnIcon.ImageTransparency = 1

	TweenService:Create(warnFrame, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, BAND_BREITE, 0, BAND_HOEHE),
		BackgroundTransparency = 0.45,
	}):Play()
	TweenService:Create(warnTitle, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	TweenService:Create(warnDetail, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	TweenService:Create(warnIcon, TweenInfo.new(0.2), { ImageTransparency = 0 }):Play()

	-- Aufleuchten: das Schild atmet, solange es steht. Ein Schild, das ruhig daliegt, ist
	-- eine Feststellung; eines, das pulsiert, ist eine Warnung.
	if warnPuls then
		warnPuls:Cancel()
	end
	warnPuls = TweenService:Create(
		warnFrame,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, math.huge, true),
		{ BackgroundTransparency = 0.22 }
	)
	task.delay(0.22, function()
		if warnToken == meinToken and warnFrame.Visible then
			warnPuls:Play()
		end
	end)

	local haltedauer = options.hold or WARN_HALTEDAUER
	task.delay(0.22 + haltedauer, function()
		if warnToken ~= meinToken then
			return -- inzwischen hat eine neue Warnung uebernommen
		end
		if warnPuls then
			warnPuls:Cancel()
		end
		TweenService:Create(warnFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(warnTitle, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(warnDetail, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(warnIcon, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
		task.delay(0.36, function()
			if warnToken == meinToken then
				warnFrame.Visible = false
			end
		end)
	end)

	return true
end

-- Bricht eine stehende Warnung sofort ab -- wird gebraucht, wenn ein Ereignis die Mitte
-- uebernimmt, waehrend die Warnung dazu noch steht.
function HudCenterNotice.ClearWarning()
	if not warnFrame then
		return
	end
	warnToken += 1
	if warnPuls then
		warnPuls:Cancel()
	end
	warnFrame.Visible = false
end

return HudCenterNotice
