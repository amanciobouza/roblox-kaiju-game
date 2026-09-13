-- VERSION: 2026-09-13 #1
-- ModuleScript: HudToast
-- Ort in Studio: ReplicatedStorage
--
-- ===== Die dritte Stelle: Belohnungen =====
--
-- Das HUD hat inzwischen zwei feste Plaetze mit klarer Bedeutung:
--
--   Bildmitte       was EINGETRETEN ist und die Lage aendert (siehe HudCenterNotice)
--   rechte Spalte   was GERADE GILT -- Stadt, Alarm, Aufgaben, Welt-Event
--
-- Es fehlte ein dritter fuer das, was WEDER dringend noch dauerhaft ist: ein
-- freigeschalteter Erfolg, ein aufgedeckter Guardian. Das sind Belohnungen. Sie sind
-- schoen, aber sie aendern nichts an dem, was man gerade tut -- man soll sie mitnehmen
-- koennen, ohne den Blick vom Kampf zu loesen.
--
-- Deshalb: OBEN LINKS, hereinfahrend von links, nacheinander.
--
-- Der Platz ist nicht beliebig gewaehlt, sondern der letzte freie. Vorher lagen beide
-- Meldungen falsch, und beide nachweislich:
--
--   Der Erfolgs-Toast stand oben mittig bei y 20 -- also GENAU auf den Level- und
--   HP-Feldern, die dort von y 8 bis 70 liegen. Er verdeckte im Moment des Erfolgs die
--   Lebensanzeige.
--
--   Der Archiv-Toast stand bei 0.34 der Bildhoehe -- also genau dort, wo die
--   Alarmmeldung auffaehrt. Zwei Meldungen uebereinander, und ausgerechnet die
--   wichtigere darunter.
--
-- Sie warten aufeinander, statt sich zu stapeln: wer zwei Erfolge auf einmal
-- freischaltet, sieht sie nacheinander.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

local HudToast = {}

local BREITE = 300
local HOEHE = 64
local RAND = 12
local SYMBOL = 32
local RUHE_X = 16
local STANDZEIT = 2.8

local screenGui = nil
local frame, iconLabel, iconImage, titleLabel, detailLabel

local warteschlange = {}
local laeuft = false

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
		warn("[Kaiju Debug] HudToast: PlayerGui nicht gefunden -- Meldungen bleiben aus.")
		return nil
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HudToastGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 60
	screenGui.Parent = playerGui

	frame = Instance.new("Frame")
	frame.Name = "Toast"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Size = UDim2.new(0, BREITE, 0, HOEHE)
	frame.Position = UDim2.new(0, -BREITE - 20, 0, 16)
	frame.Visible = false
	frame.ZIndex = 60
	frame.Parent = screenGui
	HudChrome.Panel(frame, { radius = HudChrome.Radius.Small })

	-- Zwei Traeger fuer das Symbol: ein Bild, wenn eine Asset-ID kommt, sonst ein Zeichen.
	-- Die Erfolge fuehren heute Emoji in ihrer Config, das Archiv gar nichts -- beides soll
	-- funktionieren, ohne dass der Aufrufer wissen muss, welcher Fall gerade gilt.
	iconImage = HudChrome.IconImage(frame, "")
	iconImage.Name = "ToastIconImage"
	iconImage.Size = UDim2.new(0, SYMBOL, 0, SYMBOL)
	iconImage.Position = UDim2.new(0, RAND, 0.5, -SYMBOL / 2)
	iconImage.ZIndex = 61
	iconImage.Visible = false

	iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "ToastIconText"
	iconLabel.Size = UDim2.new(0, SYMBOL, 0, SYMBOL)
	iconLabel.Position = UDim2.new(0, RAND, 0.5, -SYMBOL / 2)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextScaled = true
	iconLabel.ZIndex = 61
	iconLabel.Text = ""
	iconLabel.Visible = false
	iconLabel.Parent = frame

	local textX = RAND + SYMBOL + 10

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "ToastTitle"
	titleLabel.Size = UDim2.new(0, BREITE - textX - RAND, 0, 22)
	titleLabel.Position = UDim2.new(0, textX, 0, 9)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 61
	titleLabel.Text = ""
	titleLabel.Parent = frame
	HudChrome.Label(titleLabel, 17)

	detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "ToastDetail"
	detailLabel.Size = UDim2.new(0, BREITE - textX - RAND, 0, 18)
	detailLabel.Position = UDim2.new(0, textX, 0, 33)
	detailLabel.BackgroundTransparency = 1
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel.ZIndex = 61
	detailLabel.Text = ""
	detailLabel.Parent = frame
	HudChrome.Number(detailLabel, 13)
	detailLabel.TextColor3 = HudChrome.Color.TextSecondary

	return screenGui
end

local function zeige(eintrag)
	titleLabel.Text = eintrag.title or ""
	detailLabel.Text = eintrag.detail or ""
	titleLabel.TextColor3 = eintrag.color or HudChrome.Color.TextPrimary

	if eintrag.image and eintrag.image ~= "" then
		iconImage.Image = eintrag.image
		iconImage.Visible = true
		iconLabel.Visible = false
	else
		iconLabel.Text = eintrag.glyph or ""
		iconLabel.TextColor3 = eintrag.color or HudChrome.Color.Ready
		iconLabel.Visible = iconLabel.Text ~= ""
		iconImage.Visible = false
	end

	frame.Position = UDim2.new(0, -BREITE - 20, 0, 16)
	frame.Visible = true

	local herein = TweenService:Create(
		frame,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, RUHE_X, 0, 16) }
	)
	herein:Play()
	herein.Completed:Wait()

	task.wait(STANDZEIT)

	local hinaus = TweenService:Create(
		frame,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0, -BREITE - 20, 0, 16) }
	)
	hinaus:Play()
	hinaus.Completed:Wait()
	frame.Visible = false
end

-- Meldet eine Belohnung.
--
--   title   Was es ist ("ERFOLG FREIGESCHALTET", "ARCHIV")
--   detail  Welches ("Erster Abriss", "Warden-I Shepherd")
--   glyph   Ein Zeichen als Symbol (die Erfolge fuehren Emoji in ihrer Config)
--   image   Eine Asset-ID -- hat Vorrang vor glyph
--   color   Farbe von Titel und Zeichen; ohne Angabe die uebliche
function HudToast.Show(options)
	if not baueOberflaeche() then
		return
	end

	table.insert(warteschlange, options or {})
	if laeuft then
		return
	end

	laeuft = true
	task.spawn(function()
		while #warteschlange > 0 do
			zeige(table.remove(warteschlange, 1))
		end
		laeuft = false
	end)
end

return HudToast
