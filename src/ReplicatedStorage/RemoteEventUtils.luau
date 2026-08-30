-- VERSION: 2026-08-25 #1
-- ModuleScript: RemoteEventUtils
-- Ort in Studio: ReplicatedStorage
--
-- Zentrale, sichere Alternative zu "ReplicatedStorage:WaitForChild(name)" für
-- RemoteEvents. WaitForChild OHNE Timeout hängt für immer, falls das erwartete Event
-- von einem ANDEREN Script erst später (oder nie) erzeugt wird -- Roblox garantiert
-- keine feste Skript-Startreihenfolge in ServerScriptService/StarterPlayerScripts.
-- getOrCreateRemoteEvent() umgeht das komplett: statt zu WARTEN, erzeugt es das Event
-- notfalls SELBST (idempotent -- prüft zuerst, ob es schon existiert). Egal welches
-- Script zuerst läuft, das Ergebnis ist immer dasselbe, einzige RemoteEvent-Instanz.
--
-- Verwendung (ersetzt die bisher in vielen Dateien einzeln duplizierte Funktion):
--   local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
--   local ShowDamageEvent = RemoteEventUtils.GetOrCreate("ShowDamageEvent")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEventUtils = {}

function RemoteEventUtils.GetOrCreate(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
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