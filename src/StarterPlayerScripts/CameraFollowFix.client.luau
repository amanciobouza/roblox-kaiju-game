-- VERSION: 2026-08-25 #3
-- LocalScript: CameraFollowFix
-- Ort in Studio: StarterPlayerScripts
--
-- Stellt sicher, dass die Kamera dem Charakter zuverlässig folgt (Robloxs Standard-
-- Kamera, CameraType = Custom) -- besonders wichtig nach dem Fraktions-Modell-Tausch
-- (Kaiju/Jaeger/Ronin), da player.Character dabei server-seitig ersetzt wird und
-- CameraSubject sonst am alten, nicht mehr existierenden Charakter hängen bleibt.
--
-- Setzt ausserdem Humanoid.CameraOffset: Robloxs Standard-Fokuspunkt liegt ungefähr auf
-- Rückenmitte -- CameraOffset verschiebt ihn nach oben Richtung Schulter/Hals, was sich
-- deutlich natürlicher anfühlt. Proportional zur tatsächlichen Charaktergrösse berechnet
-- (nicht fix), da die Charaktere hier zwischen Scale 1 und 6 variieren.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function updateCameraOffset(character, humanoid)
	local ok, characterSize = pcall(function()
		local _, size = character:GetBoundingBox()
		return size
	end)
	if ok then
		-- ~18% der Gesamthöhe über der Rückenmitte -- empirisch auf Schulter-/Halshöhe
		-- kalibriert, unabhängig von der tatsächlichen Charaktergrösse.
		humanoid.CameraOffset = Vector3.new(0, characterSize.Y * 0.18, 0)
	end
end

local function updateCameraSubject(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		camera.CameraSubject = humanoid
		-- Kurz warten, bis die server-seitige Skalierung (PlayerSetup.lua) sicher
		-- angewendet wurde -- sonst könnte die Grössen-Messung noch den alten,
		-- unskalierten Wert liefern.
		task.spawn(function()
			task.wait(0.5)
			if character.Parent then
				updateCameraOffset(character, humanoid)
			end
		end)
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