-- Script: BildzeitWacht (Server)
-- Ort in Studio: ServerScriptService
--
-- Startet die Bildzeit-Messung auf dem Server. Die Logik steht in
-- ReplicatedStorage.BildzeitWacht -- dieselbe Datei laeuft auf dem Client, damit die Zahlen
-- beider Seiten vergleichbar bleiben.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modul = ReplicatedStorage:WaitForChild("BildzeitWacht", 10)
if not modul then
	warn("[Bildzeit Server] ReplicatedStorage.BildzeitWacht fehlt -- keine Messung. "
		.. "Hat Rojo synchronisiert?")
	return
end

require(modul).Start()
