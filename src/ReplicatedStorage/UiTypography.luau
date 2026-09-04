-- ModuleScript: UiTypography
-- Ort in Studio: ReplicatedStorage
--
-- Eine Quelle für Schriftart und Schriftgrösse der Menü-Bildschirme.
--
-- ===== Warum die Grössen vorher so stark schwankten =====
-- Fast jeder Text stand auf `TextScaled = true`. Das skaliert die Schrift auf die Höhe
-- ihres Kästchens -- ein 40 Pixel hohes Kästchen ergab riesige, ein 16 Pixel hohes winzige
-- Schrift. Zwei Beschreibungen mit demselben Rang sahen deshalb völlig verschieden aus,
-- je nachdem, wie gross ihr Kästchen zufällig war. Beschreibungstexte bekommen deshalb
-- eine FESTE Grösse und `TextScaled = false`.
--
-- ===== Comic nur noch für Titel =====
-- Die Comic-Schriften (LuckiestGuy, FredokaOne) tragen den Ton des Spiels, sind aber für
-- Fliesstext schlecht lesbar: enge Punzen, wenig Unterschied zwischen ähnlichen Zeichen.
-- Titel und Knöpfe behalten sie, Beschreibungen bekommen eine Werkschrift.
--
-- ===== Warum feste Pixelgrössen und keine Skalierung =====
-- Eine Beschreibung soll auf jedem Bildschirm gleich gross sein; ihre Lesbarkeit hängt an
-- der absoluten Grösse, nicht an der Fenstergrösse. Wo ein Bildschirm insgesamt zu klein
-- wird, gehört ein UIScale auf das ganze Panel -- nicht eine andere Schriftgrösse je Text.

local UiTypography = {}

-- Titel und Zwischenüberschriften: der Ton des Spiels.
UiTypography.TitleFont = Enum.Font.LuckiestGuy

-- Knöpfe und kurze Bezeichner: ebenfalls Comic, aber ruhiger als der Titel.
UiTypography.LabelFont = Enum.Font.FredokaOne

-- Fliesstext. Bewusst eine Werkschrift.
UiTypography.BodyFont = Enum.Font.Gotham

UiTypography.BodySize = 16 -- Beschreibungen
UiTypography.CaptionSize = 13 -- Hinweise, Einheiten, Fusszeilen
UiTypography.SubheadSize = 18 -- Zwischenüberschrift über einem Beschreibungsblock

-- Setzt einen TextLabel auf Fliesstext. `label.Size` bleibt unberührt -- wer die Höhe
-- mitwachsen lassen will, setzt zusätzlich AutomaticSize.
function UiTypography.Body(label, size)
	label.Font = UiTypography.BodyFont
	label.TextScaled = false
	label.TextSize = size or UiTypography.BodySize
	label.TextWrapped = true
	return label
end

-- Kleiner als Fliesstext, für Nebenangaben.
function UiTypography.Caption(label, size)
	return UiTypography.Body(label, size or UiTypography.CaptionSize)
end

-- Zwischenüberschrift über einem Beschreibungsblock: Comic, aber feste Grösse -- sonst
-- schwankt sie mit der Kästchenhöhe genauso wie vorher der Fliesstext.
function UiTypography.Subhead(label, size)
	label.Font = UiTypography.LabelFont
	label.TextScaled = false
	label.TextSize = size or UiTypography.SubheadSize
	label.TextWrapped = true
	return label
end

return UiTypography
