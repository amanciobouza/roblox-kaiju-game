-- LocalScript: EnergyTypeVisualClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Die Energie-Dekoration ist rein visuell. Der Server setzt Typ, Farbe und
-- Ruheposition einmal; nur nahe, geladene Gebaeude werden hier animiert.
-- Keine endlosen Server-Tweens und keine fortlaufende Replikation der Effekte.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HOUSE_TAG = "KaijuHouse"
local UPDATE_INTERVAL = 0.1
local DISCOVERY_INTERVAL = 0.5
local EFFECT_DISTANCE = 200
local tracked = {}

local function track(house)
	if house:IsA("Model") and not tracked[house] then
		tracked[house] = { active = false }
	end
end

local function discover(house, entry)
	local glowAnchor = house:FindFirstChild("EnergyTypeGlowAnchor")
	local light = glowAnchor and glowAnchor:FindFirstChild("EnergyTypeGlow")
	entry.light = light and light:IsA("PointLight") and light or nil
	local anchor = house.PrimaryPart
	local icon = anchor and anchor:FindFirstChild("EnergyTypeIcon")
	local billboard = icon and icon:IsA("BillboardGui") and icon or nil
	if billboard ~= entry.billboard then
		entry.billboard = billboard
		entry.baseOffset = nil
	end
	if billboard then
		local base = billboard:GetAttribute("EnergyTypeBaseOffset")
		-- Fuer bestehende Studio-Objekte ohne das neue Attribut einmal merken.
		entry.baseOffset = typeof(base) == "Vector3" and base
			or entry.baseOffset or billboard.StudsOffsetWorldSpace
	end
end

local function settle(entry)
	if entry.light and entry.light.Parent then entry.light.Brightness = 1.2 end
	if entry.billboard and entry.billboard.Parent and entry.baseOffset then
		entry.billboard.StudsOffsetWorldSpace = entry.baseOffset
	end
	entry.active = false
end

local function forget(house)
	local entry = tracked[house]
	if entry then settle(entry) end
	tracked[house] = nil
end

CollectionService:GetInstanceAddedSignal(HOUSE_TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(HOUSE_TAG):Connect(forget)
for _, house in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do track(house) end

local elapsed, discoveryElapsed = 0, 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	discoveryElapsed += dt
	if elapsed < UPDATE_INTERVAL then return end
	elapsed = elapsed % UPDATE_INTERVAL
	local refresh = discoveryElapsed >= DISCOVERY_INTERVAL
	if refresh then discoveryElapsed = discoveryElapsed % DISCOVERY_INTERVAL end
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local origin = camera.CFrame.Position
	local now = os.clock()
	-- Dieselben Sine-InOut-Zyklen wie vorher, mit nur zehn Aktualisierungen
	-- pro Sekunde und ohne Tween-Objekt pro Gebaeude.
	local lightPulse = (1 - math.cos(now * math.pi / 1.1)) / 2
	local iconFloat = (1 - math.cos(now * math.pi / 1.8)) / 2

	debug.profilebegin("Trenchborn.EnergieDekoration")
	for house, entry in pairs(tracked) do
		local anchor = house.PrimaryPart
		local near = anchor and house:IsDescendantOf(Workspace)
			and house:GetAttribute("Destroyed") ~= true
			and (anchor.Position - origin).Magnitude <= EFFECT_DISTANCE
		if near then
			if refresh or not entry.active then discover(house, entry) end
			entry.active = true
			if entry.light and entry.light.Parent then
				entry.light.Brightness = 0.8 + 0.8 * lightPulse
			end
			if entry.billboard and entry.billboard.Parent and entry.baseOffset then
				entry.billboard.StudsOffsetWorldSpace = entry.baseOffset
					+ Vector3.new(0, 1.5 * iconFloat, 0)
			end
		elseif entry.active then
			settle(entry)
		end
	end
	debug.profileend()
end)

print("[Kaiju Debug] Energie-Dekoration: lokal, 10 Updates/s, nur innerhalb von 200 Studs.")
