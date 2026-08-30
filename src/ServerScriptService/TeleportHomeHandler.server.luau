-- Script (kein LocalScript!): TeleportHomeHandler
-- Ort in Studio: ServerScriptService
-- Teleportiert den Spieler auf Knopfdruck zurück zum SpawnLocation (Startzone/Sanctuary).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TeleportHomeEvent = Instance.new("RemoteEvent")
TeleportHomeEvent.Name = "TeleportHomeEvent"
TeleportHomeEvent.Parent = ReplicatedStorage

local TELEPORT_COOLDOWN = 2 -- Sekunden, gegen Spam-Klicks
local lastTeleportTime = {}

local function findSpawnLocation()
	-- Bevorzugt ein echtes SpawnLocation-Objekt (dort, wo Spieler tatsächlich respawnen).
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation", true)
	if spawn then
		return spawn.Position + Vector3.new(0, 5, 0)
	end

	-- Fallback: die Sanctuary-Zone selbst, falls kein SpawnLocation gefunden wird.
	local sanctuary = Workspace:FindFirstChild("SanctuaryZone", true)
	if sanctuary and sanctuary:IsA("BasePart") then
		return sanctuary.Position + Vector3.new(0, 5, 0)
	end

	return nil
end

TeleportHomeEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastTeleportTime[player] and now - lastTeleportTime[player] < TELEPORT_COOLDOWN then
		return
	end
	lastTeleportTime[player] = now

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart then
		return
	end

	local targetPosition = findSpawnLocation()
	if not targetPosition then
		warn("[TeleportHome] Weder SpawnLocation noch SanctuaryZone im Workspace gefunden -- kann nicht teleportieren.")
		return
	end

	rootPart.CFrame = CFrame.new(targetPosition)
	rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	-- WICHTIG: Der abrupte CFrame-Sprung kann den Humanoid-Zustand durcheinanderbringen
	-- (z.B. den Jumping-Zustand deaktiviert lassen) -- ohne Stabilisierung bliebe der
	-- Spieler danach dauerhaft unfähig zu springen, da nichts anderes das nach einem
	-- Teleport automatisch zurücksetzt (nur beim Spawnen/Skin-Wechsel passiert das sonst).
	if humanoid then
		task.defer(function()
			if not humanoid.Parent then
				return
			end
			task.wait() -- ein Frame warten, bis die neue Position/CFrame vollständig übernommen ist
			humanoid.PlatformStand = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			if humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				task.wait()
				if humanoid.Parent and humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end
			end
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastTeleportTime[player] = nil
end)