-- VERSION: 2026-08-25 #1
-- ModuleScript: RemoteEventUtils
-- Ort in Studio: ReplicatedStorage
--
-- Zentrale, sichere Alternative zu "ReplicatedStorage:WaitForChild(name)" für
-- RemoteEvents. WaitForChild OHNE Timeout hängt für immer, falls das erwartete Event
-- von einem ANDEREN Script erst später (oder nie) erzeugt wird -- Roblox garantiert
-- keine feste Skript-Startreihenfolge in ServerScriptService/StarterPlayerScripts.
--
-- ===== Server und Client verhalten sich UNTERSCHIEDLICH, und das ist der Kern =====
-- Auf dem SERVER wird das Ereignis notfalls selbst erzeugt (idempotent). Egal welches
-- Script zuerst läuft, das Ergebnis ist dieselbe, einzige RemoteEvent-Instanz.
--
-- Auf dem CLIENT wird gewartet, NICHT erzeugt. Ein clientseitig erzeugtes RemoteEvent ist
-- dem Server unbekannt: FireServer darauf verlässt den Client nie -- ohne Fehlermeldung,
-- ohne Wirkung. Genau diese Falle hat in einer einzigen Sitzung zweimal zugeschlagen, und
-- sie war jedes Mal nur daran zu erkennen, dass "nichts passiert".
--
-- Läuft die Wartezeit ab, wird doch erzeugt -- aber mit einer lauten Warnung. Der Grund
-- ist die Migration: 58 Aufrufstellen gehen davon aus, dass hier nie nil herauskommt. nil
-- zurückzugeben hiesse, sie alle gleichzeitig anzufassen und dabei neue Absturzwege zu
-- schaffen. Aus einem stillen Fehler wird so erst einmal ein lauter.
--
-- Verwendung (ersetzt die bisher in vielen Dateien einzeln duplizierte Funktion):
--   local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
--   local ShowDamageEvent = RemoteEventUtils.GetOrCreate("ShowDamageEvent")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteEventUtils = {}

-- Wie lange der Client auf das Ereignis des Servers wartet. Grosszügig: Server-Skripte
-- legen ihre Ereignisse beim Start an, WaitForChild kehrt zurück, sobald es da ist --
-- die Zeit wird also nur im Fehlerfall wirklich verbraucht.
local CLIENT_WAIT_SECONDS = 10

function RemoteEventUtils.GetOrCreate(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if RunService:IsClient() then
		local waited = ReplicatedStorage:WaitForChild(name, CLIENT_WAIT_SECONDS)
		if waited and waited:IsA("RemoteEvent") then
			return waited
		end
		warn(string.format(
			"[RemoteEventUtils] '%s' kam nach %ds nicht vom Server. Es wird lokal erzeugt, "
			.. "damit das Skript weiterläuft -- FireServer darauf bleibt aber WIRKUNGSLOS. "
			.. "Legt ein Server-Skript dieses Ereignis an?",
			name, CLIENT_WAIT_SECONDS))
	end

	if existing then
		-- Falscher Typ unter diesem Namen (sollte nicht vorkommen, aber sicherheitshalber
		-- abgefangen) -- ersetzen statt mit einem falschen Objekt weiterzuarbeiten.
		existing:Destroy()
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

return RemoteEventUtils