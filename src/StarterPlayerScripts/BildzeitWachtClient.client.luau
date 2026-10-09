-- LocalScript: BildzeitWachtClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Startet die Bildzeit-Messung auf dem Client. Dieselbe Logik wie auf dem Server (siehe
-- ReplicatedStorage.BildzeitWacht), nur misst sie hier die RENDER-Zeit -- das ist, was der
-- Spieler als Ruckeln sieht.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modul = ReplicatedStorage:WaitForChild("BildzeitWacht", 10)
if not modul then
	warn("[Bildzeit Client] ReplicatedStorage.BildzeitWacht fehlt -- keine Messung. "
		.. "Hat Rojo synchronisiert?")
	return
end

require(modul).Start()
