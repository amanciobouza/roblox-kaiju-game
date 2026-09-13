-- VERSION: 2026-09-13 #2
-- ModuleScript: HudCenterNotice
-- Ort in Studio: ReplicatedStorage
--
-- ===== Die Mitte des Bildschirms =====
--
-- Die Bildmitte ist der teuerste Platz im HUD: dort steht die Spielfigur, dorthin schaut
-- man ohnehin. Was hier erscheint, unterbricht das Spiel fuer einen Moment.
--
-- Deshalb die Regel, die dieses Modul festhaelt:
--
--   Die Mitte gehoert dem, was EINGETRETEN ist -- nicht dem, was bevorsteht.
--
-- Ein Ereignis aendert die Lage und muss zur Kenntnis genommen werden; dafuer darf man
-- unterbrechen. Eine Warnung darf man ignorieren -- sie meldet sich, statt zu
-- unterbrechen, und gehoert deshalb in die rechte Spalte, zu den anderen Anzeigen, die
-- man im Vorbeigehen liest (siehe CityAlertHudClient und die Welt-Event-Info).
--
-- Der erste Entwurf hatte hier zwei Register, Warnung und Ereignis. Im Spiel war das
-- falsch: die Warnung kam zu frueh und zu oft in die Mitte und nahm dem Ereignis genau
-- das, was es ausmacht -- dass die Mitte sonst leer ist.
--
-- ===== Die Form =====
--
-- Ein durchlaessiges Band, das an beiden Enden ins Nichts auslaeuft. Bewusst KEIN Kasten
-- mit Rahmen: ein Kasten liest sich als weitere Anzeige, die man liest und abhakt; ein
-- Band ohne Kante liest sich als Stoerung im Bild.
--
-- Sie steht hier und nicht bei der Alarm-Ankuendigung, weil die naechste Meldung, die die
-- Mitte braucht (Mutation, Stadt gebrochen, Kapitelwechsel), dieselbe Sprache sprechen
-- soll, ohne sie ein zweites Mal zu bauen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

local HudCenterNotice = {}

-- Die Hoehe, auf der eine Meldung in der Mitte sitzt: leicht ueber der Bildmitte, damit
-- die Spielfigur frei bleibt. Wer sie aendert, verschiebt jede Meldung gemeinsam.
HudCenterNotice.Y_SCALE = 0.35

-- Setzt einem Rahmen die Bandform: deckend in der Mitte, an beiden Enden durchsichtig.
-- Der Verlauf MACHT die Form -- ohne ihn bliebe ein Rechteck, und ein Rechteck ist ein
-- Kasten.
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
-- Nur eine Meldung zur Zeit. Heute gibt es erst eine, die die Mitte benutzt -- die Sperre
-- steht trotzdem schon, weil die zweite (Mutation oder Stadt gebrochen) sonst genau am
-- falschen Moment daruebergeschrieben wuerde: waehrend die erste laeuft.
local belegt = false

function HudCenterNotice.IsBusy()
	return belegt
end

function HudCenterNotice.SetBusy(value)
	belegt = value and true or false
end

return HudCenterNotice
