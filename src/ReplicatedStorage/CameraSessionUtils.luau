-- ModuleScript: CameraSessionUtils
-- Ort in Studio: ReplicatedStorage
--
-- EIN Session-Zähler für alle Kameraschleifen des Spiels.
--
-- ===== Warum das zentral sein muss =====
-- CLAUDE.md nennt konkurrierende Kameraschleifen ausdrücklich als Fehlerquelle: mehrere
-- gleichzeitig laufende Schleifen kämpfen um dieselbe Kamera, und es entstehen Flacker-
-- und Sprungfehler, die schwer zu reproduzieren sind. Die Abhilfe ist eine Session-ID:
-- jede Schleife merkt sich ihre Nummer und beendet sich, sobald eine neue Session beginnt.
--
-- Genau das gab es im Bestand schon -- aber als dateilokale Variable im Prolog-Client.
-- Die Trainingskamera kannte sie nicht, und eine dritte Kamera hätte sie ebenso wenig
-- gekannt. Zwei Zähler, die einander nicht kennen, sind aber genau der Fall, den die
-- Regel verhindern soll: beide Schleifen halten ihre eigene ID für aktuell und laufen
-- munter gegeneinander.
--
-- ===== Benutzung =====
--   local session = CameraSessionUtils.Start("Showdown")
--   RunService:BindToRenderStep(..., function()
--       if not CameraSessionUtils.IsCurrent(session) then
--           -- aufräumen und aussteigen
--           return
--       end
--       ...
--   end)
--
-- Jeder Aufruf von Start() macht ALLE älteren Sessions ungültig -- auch die anderer
-- Systeme. Das ist die Absicht: wer die Kamera übernimmt, übernimmt sie ganz.

local CameraSessionUtils = {}

local activeSessionId = 0
local activeOwner = nil

-- Beginnt eine neue Kamerasession und entwertet alle älteren.
-- `owner` ist nur für die Fehlersuche -- er beantwortet die Frage "wer hat mir die
-- Kamera weggenommen?", die sonst nur durch Lesen aller Kameraskripte zu klären wäre.
function CameraSessionUtils.Start(owner)
	activeSessionId += 1
	local previousOwner = activeOwner
	activeOwner = owner or "unbenannt"
	if previousOwner and previousOwner ~= activeOwner then
		print(string.format(
			"[Kaiju-Debug] Kamerasession %d: %s übernimmt von %s.",
			activeSessionId, activeOwner, previousOwner))
	end
	return activeSessionId
end

-- Läuft diese Session noch, oder hat jemand anderes übernommen?
function CameraSessionUtils.IsCurrent(sessionId)
	return activeSessionId == sessionId
end

-- Beendet die eigene Session, ohne eine neue zu beginnen. Nur wirksam, wenn sie noch die
-- aktuelle ist -- sonst würde ein spät aufräumendes System eine fremde Session abwürgen.
function CameraSessionUtils.Release(sessionId)
	if activeSessionId == sessionId then
		activeSessionId += 1
		activeOwner = nil
		return true
	end
	return false
end

-- Wer hält die Kamera gerade? Für Debug-Ausgaben.
function CameraSessionUtils.CurrentOwner()
	return activeOwner
end

return CameraSessionUtils
