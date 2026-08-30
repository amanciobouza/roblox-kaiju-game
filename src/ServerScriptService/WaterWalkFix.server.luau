-- Script (kein LocalScript!): WaterWalkFix
-- Ort in Studio: ServerScriptService
--
-- Behebt das Hochschleudern beim Schwimmen -- WICHTIG: Dies ist ein ANDERES Problem als
-- das "im Boden stecken beim Spawnen"-Problem, das der SpawnStabilizer (eingebaut in
-- KaijuR15/JaegerR15/RoninR15) behebt. Der SpawnStabilizer läuft nur 3x kurz nach dem
-- Spawn und tut bei Wasser explizit NICHTS (siehe dessen eigener Code: "if
-- result.Material == Water then return end") -- er kümmert sich nicht um das
-- Katapultieren, das später beim Schwimmen auftritt. Dieses Script läuft dagegen
-- KONTINUIERLICH (jeden Frame) und unterdrückt aktiv die vertikale Geschwindigkeit,
-- SOBALD der Humanoid im Schwimm-Zustand ist -- horizontale Bewegung (Laufen) bleibt
-- komplett unangetastet.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local function setupCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not rootPart then
		return
	end

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not humanoid.Parent or not rootPart.Parent then
			connection:Disconnect()
			return
		end

		if humanoid:GetState() == Enum.HumanoidStateType.Swimming then
			local velocity = rootPart.AssemblyLinearVelocity
			if math.abs(velocity.Y) > 0.5 then
				rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	if player.Character then
		setupCharacter(player.Character)
	end
	player.CharacterAdded:Connect(setupCharacter)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		setupCharacter(player.Character)
	end
end