-- Scheinwerfer sind Dekoration: keine laufenden Lichtaenderungen vom Server replizieren.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local VISUAL_TAG = "AlertHelicopterVisual"

local UPDATE_INTERVAL = 0.1
local EFFECT_DISTANCE = 250
local models = {}

local function settle(state)
	if not state.animated then return end
	for light in pairs(state.lights) do
		if light.Parent then light.Angle = 35 end
	end
	state.animated = false
end

local function forget(model)
	local state = models[model]
	if not state then return end
	settle(state)
	for _, connection in ipairs(state.connections) do connection:Disconnect() end
	models[model] = nil
end

local function remember(model)
	if models[model] or not model:IsA("Model") then return end
	local state = { lights = {}, connections = {}, animated = false }
	models[model] = state
	local function add(descendant)
		if descendant:IsA("SpotLight") then state.lights[descendant] = true end
	end
	for _, descendant in ipairs(model:GetDescendants()) do add(descendant) end
	table.insert(state.connections, model.DescendantAdded:Connect(add))
	table.insert(state.connections, model.DescendantRemoving:Connect(function(descendant)
		state.lights[descendant] = nil
	end))
end

CollectionService:GetInstanceAddedSignal(VISUAL_TAG):Connect(remember)
CollectionService:GetInstanceRemovedSignal(VISUAL_TAG):Connect(forget)
for _, model in ipairs(CollectionService:GetTagged(VISUAL_TAG)) do remember(model) end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < UPDATE_INTERVAL then return end
	elapsed = 0
	local camera = workspace.CurrentCamera
	local angle = 35 + math.sin(os.clock() * 0.6) * 8
	debug.profilebegin("Trenchborn.HelikopterLicht")
	for model, state in pairs(models) do
		if camera and model:IsDescendantOf(workspace)
			and (model:GetPivot().Position - camera.CFrame.Position).Magnitude <= EFFECT_DISTANCE then
			for light in pairs(state.lights) do light.Angle = angle end
			state.animated = true
		else
			settle(state)
		end
	end
	debug.profileend()
end)

print("[Kaiju Debug] Helikopter-Lichter bereit -- lokal mit maximal 10 Updates/s bis 250 Studs.")
