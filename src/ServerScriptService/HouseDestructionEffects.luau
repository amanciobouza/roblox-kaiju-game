-- Der Server meldet nur kurze Ereignisse und den dauerhaften Brennzustand.
-- Partikel, Sound-Anker und deren Animation entstehen ausschließlich lokal.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage:WaitForChild("DestructionEffectConfig", 10))
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils", 10))
local remote = RemoteEventUtils.GetOrCreate(Config.RemoteName)
local Effects = {}
local templates = Instance.new("Folder")
templates.Name = Config.TemplateFolder
templates.Parent = ReplicatedStorage

local function publishTemplates()
	local source = ServerStorage:FindFirstChild("Effects")
	if not source then return end
	for _, name in ipairs({ "HouseExplosionVFX", "HouseFireVFX" }) do
		if not templates:FindFirstChild(name) then
			local original = source:FindFirstChild(name)
			if original then
				local folder = Instance.new("Folder")
				folder.Name = name
				local count = 0
				for _, item in ipairs(original:GetDescendants()) do
					if item:IsA("ParticleEmitter") and count < Config.MaxTemplateEmitters then
						local copy = item:Clone()
						copy:ClearAllChildren()
						copy.Enabled = false
						copy.Parent = folder
						count += 1
					end
				end
				folder.Parent = templates
			end
		end
	end
end

function Effects.Emit(kind, position, size, maxHealth)
	publishTemplates()
	-- Auch Zuschauer sehen die Effekte. Ferne Spieler erhalten keine Ereignisse;
	-- große Grundflächen werden dabei vom Rand aus berücksichtigt.
	local radius = Config.ViewDistance + math.max(size.X, size.Z) / 2
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and ((root.Position - position) * Vector3.new(1, 0, 1)).Magnitude <= radius then
			remote:FireClient(player, kind, position, size, maxHealth)
		end
	end
end

function Effects.StartFire(house, groundCFrame, lifetime)
	publishTemplates()
	house:SetAttribute("FireVisualPosition", groundCFrame.Position)
	house:SetAttribute("FireVisualEndsAt", workspace:GetServerTimeNow() + lifetime)
end

function Effects.StopFire(house)
	house:SetAttribute("FireVisualEndsAt", nil)
	house:SetAttribute("FireVisualPosition", nil)
end

publishTemplates()
print("[Kaiju Debug] Zerstoerungseffekte: lokal, entfernungsbegrenzt; Brennmechanik bleibt auf dem Server.")
return Effects
