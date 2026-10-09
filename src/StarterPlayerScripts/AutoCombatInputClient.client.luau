-- LocalScript: AutoCombatInputClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Die Taste fuer den Auto-Kampf. Mehr tut dieses Skript nicht -- der Ablauf selbst liegt im
-- AutoCombatService auf dem Server (Begruendung steht dort).
--
-- ===== Zur Taste =====
-- Amancio wollte 'X'. Die ist aber schon belegt: X haelt das Energie-Absorbieren
-- (EnergyAbsorbInputClient), und zwar mit Begruendung -- sie liegt neben WASD, der
-- Ringfinger haelt sie, waehrend Zeige- und Mittelfinger weiter angreifen. Ein zweiter
-- Hoerer auf X haette beim Druck beides ausgeloest.
--
-- Deshalb vorlaeufig 'C': direkt neben X, frei, und im selben Griff zu erreichen. Die Taste
-- steht als EINE Konstante -- auf X umzustellen ist eine Zeile hier, kostet dann aber eine
-- neue Taste fuer das Absorbieren.
local AUTO_KAMPF_TASTE = Enum.KeyCode.C
-- Am Gamepad: ButtonB ist frei (ButtonX und ButtonY sind belegt).
local AUTO_KAMPF_GAMEPAD = Enum.KeyCode.ButtonB

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils", 30))
local AutoCombatToggleEvent = RemoteEventUtils.GetOrCreate("AutoCombatToggleEvent")

local player = Players.LocalPlayer

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	-- gameProcessedEvent: der Druck ging schon an eine Oberflaeche (Chat, Textfeld). Ihn
	-- trotzdem zu nehmen, startet den Auto-Kampf beim Tippen einer Nachricht.
	if gameProcessedEvent then
		return
	end
	if input.KeyCode ~= AUTO_KAMPF_TASTE and input.KeyCode ~= AUTO_KAMPF_GAMEPAD then
		return
	end
	AutoCombatToggleEvent:FireServer()
end)

-- Rueckmeldung, dass der Modus laeuft. Bewusst nur eine Zeile in der Ausgabe und ein
-- Attribut: ein Anzeiger im HUD gehoert dorthin, wo das HUD gebaut wird, und der war nicht
-- Teil der Bitte. Das Attribut liegt am Spieler, das HUD kann es jederzeit lesen.
player:GetAttributeChangedSignal("AutoCombatActive"):Connect(function()
	print("[Kaiju Debug] Auto-Kampf ist jetzt "
		.. (player:GetAttribute("AutoCombatActive") and "AN" or "AUS") .. ".")
end)

print("[Kaiju Debug] Auto-Kampf bereit -- Taste '"
	.. AUTO_KAMPF_TASTE.Name .. "' schaltet ihn um.")
