-- VERSION: 2026-08-25 #1 (RemoteEventUtils-Umstellung)
-- LocalScript: EnergyAbsorbClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt einen kleinen, glühenden Partikel, der von einer Energiequelle (Explosion/Feuer)
-- zum Spieler fliegt und dabei "aufgesogen" wird -- visuelles Feedback fürs kontinuierliche
-- Energie-Sammeln (EnergyCollectionHandler.lua).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local EnergyAbsorbEvent = RemoteEventUtils.GetOrCreate("EnergyAbsorbEvent")

local ABSORB_DURATION = 0.5

-- Jeder der 5 Energie-Typen bekommt seine eigene, wiedererkennbare Farbe -- dieselben
-- Farben wie im Talentbaum/HUD (ENERGY_COLORS in TalentTreeClient.lua, EnergyTypesClient.lua).
local ENERGY_COLORS = {
	Heat = Color3.fromRGB(255, 140, 30),
	Chemical = Color3.fromRGB(255, 45, 190),
	Electric = Color3.fromRGB(57, 217, 255),
	Radiation = Color3.fromRGB(126, 255, 16),
	Spirit = Color3.fromRGB(255, 205, 70),
}
local DEFAULT_ENERGY_COLOR = Color3.fromRGB(255, 140, 40)

-- Bremst zu häufige Effekt-Spawns aus (bei mehreren Feuerquellen in Reichweite könnten
-- sonst viele Partikel pro Sekunde entstehen -- reicht völlig, alle paar Ticks EINEN
-- sichtbaren Partikel zu zeigen statt für jeden einzelnen Energie-Tick).
local lastEffectTime = 0
local EFFECT_COOLDOWN = 0.3

local function showAbsorbParticle(sourcePosition, energyType)
	local now = os.clock()
	if now - lastEffectTime < EFFECT_COOLDOWN then
		return
	end
	lastEffectTime = now

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end

	local energyColor = ENERGY_COLORS[energyType] or DEFAULT_ENERGY_COLOR

	local part = Instance.new("Part")
	part.Name = "EnergyAbsorbParticle"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	part.Position = sourcePosition + Vector3.new(math.random(-2, 2), math.random(0, 2), math.random(-2, 2))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = energyColor
	part.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = energyColor
	light.Range = 6
	light.Brightness = 2
	light.Parent = part

	local tween = TweenService:Create(
		part,
		TweenInfo.new(ABSORB_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = head.Position, Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 0.6 }
	)
	tween:Play()

	task.delay(ABSORB_DURATION, function()
		part:Destroy()
	end)
end

EnergyAbsorbEvent.OnClientEvent:Connect(showAbsorbParticle)