-- VERSION: 2026-08-24 #3
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local portals = Workspace:WaitForChild("TrenchbornPortals")
local remote = ReplicatedStorage:FindFirstChild("TrenchbornPortalRemote")
if not remote or not remote:IsA("RemoteEvent") then
	if remote then remote:Destroy() end
	remote = Instance.new("RemoteEvent")
	remote.Name = "TrenchbornPortalRemote"
	remote.Parent = ReplicatedStorage
end
local busy = {}
local connected = setmetatable({}, {__mode="k"})
local function destinationFor(portal)
	local name = portal:GetAttribute("DestinationSpawnName")
	local folder = Workspace:FindFirstChild("PortalDestinations")
	if typeof(name) ~= "string" or name == "" or not folder then return nil end
	local d = folder:FindFirstChild(name)
	return (d and d:IsA("BasePart")) and d or nil
end

local function teleport(player, character, humanoid, root, portal)
	-- WICHTIG: busy[player] wird jetzt bereits VOM AUFRUFER (Touched-Handler) gesetzt,
	-- BEVOR diese Funktion überhaupt gestartet wird -- keine erneute Prüfung/Zuweisung
	-- hier nötig (und keine falsch, da busy[player] an dieser Stelle immer schon true ist).
	local destination = destinationFor(portal)
	if not destination then
		warn("[TrenchbornPortal] No destination for", portal:GetFullName(), portal:GetAttribute("DestinationSpawnName"))
		busy[player] = nil
		return
	end

	local ws, jp, ar = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	print("[TrenchbornPortal] BeginTeleport ->", player.Name, portal.Name)
	remote:FireClient(player, "BeginTeleport", portal)
	local delayTime = portal:GetAttribute("TeleportDelay")
	if typeof(delayTime) ~= "number" then delayTime = 1.35 end
	task.wait(math.max(0.8, delayTime))
	if character.Parent and humanoid.Parent and humanoid.Health > 0 and root.Parent then
		destination = destinationFor(portal)
		if destination then
			character:PivotTo(destination.CFrame * CFrame.new(0, 4, 0))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			print("[TrenchbornPortal] Arrive ->", player.Name, portal.Name)
			remote:FireClient(player, "Arrive", portal)
		end
	end
	task.wait(0.55)
	if humanoid.Parent then
		humanoid.WalkSpeed = ws
		humanoid.JumpPower = jp
		humanoid.AutoRotate = ar
	end
	task.wait(1.0)
	busy[player] = nil
end
local function connectPortal(portal)
	if not portal:IsA("Model") or portal:GetAttribute("TrenchbornPortal") ~= true or connected[portal] then return end
	local field = portal:FindFirstChild("EnergyField", true)
	if not field or not field:IsA("BasePart") then
		warn("[TrenchbornPortal] Missing EnergyField:", portal:GetFullName())
		return
	end
	connected[portal] = true
	field.Touched:Connect(function(hit)
		if portal:GetAttribute("Active") ~= true then return end
		local character = hit and hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or busy[player] then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			-- WICHTIG: busy[player] SOFORT (synchron, noch im selben Frame) setzen --
			-- nicht erst innerhalb von teleport() selbst. Touched kann bei einem grossen
			-- Charakter mehrfach kurz hintereinander feuern (mehrere Körperteile
			-- berühren das Feld über mehrere Frames) -- ohne dieses sofortige Sperren
			-- konnten mehrere teleport()-Läufe gleichzeitig für denselben Spieler
			-- starten, deren WalkSpeed/JumpPower-Sicherung sich gegenseitig überschrieb
			-- und JumpPower dauerhaft auf 0 stehen liess.
			busy[player] = true
			task.spawn(teleport, player, character, humanoid, root, portal)
		end
	end)
end
for _,p in ipairs(portals:GetChildren()) do connectPortal(p) end
portals.ChildAdded:Connect(function(p) task.defer(connectPortal,p) end)
Players.PlayerRemoving:Connect(function(p) busy[p]=nil end)
print("[TrenchbornPortal] Server v4 active")