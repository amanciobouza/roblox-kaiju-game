-- VERSION: 2026-08-25 #3
-- LocalScript: CameraFollowFix
-- Ort in Studio: StarterPlayerScripts
--
-- Stellt sicher, dass die Kamera dem Charakter zuverlässig folgt (Robloxs Standard-
-- Kamera, CameraType = Custom) -- besonders wichtig nach dem Fraktions-Modell-Tausch
-- (Kaiju/Jaeger/Ronin), da player.Character dabei server-seitig ersetzt wird und
-- CameraSubject sonst am alten, nicht mehr existierenden Charakter hängen bleibt.
--
-- Den FOKUSPUNKT setzt dieses Skript nicht mehr. Er stand hier als Anteil der
-- Figurenhöhe, einmalig eine halbe Sekunde nach dem Spawn gemessen -- also bevor ein
-- Kaiju-Modell überhaupt hing. Er blieb dadurch auf Avatarhöhe und lag bei angezogenem
-- Modell zwischen den Beinen der Figur.
--
-- Fokus und Entfernung gehören ohnehin zusammen: beides ist eine Entscheidung darüber, wie
-- die Figur im Bild steht. Sie liegen jetzt gemeinsam im CameraFramingClient, der auch
-- mitbekommt, wenn sich die Figur ändert.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function updateCameraSubject(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

camera.CameraType = Enum.CameraType.Custom

if player.Character then
	updateCameraSubject(player.Character)
end

player.CharacterAdded:Connect(updateCameraSubject)

player:GetPropertyChangedSignal("Character"):Connect(function()
	if player.Character then
		updateCameraSubject(player.Character)
	end
end)