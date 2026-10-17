-- Kurze Effekte werden bei Überlast ausgelassen, niemals nachträglich abgespielt.
-- Dauerfeuer wird aus repliziertem Zustand rekonstruiert, auch nach Stream-In.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage:WaitForChild("DestructionEffectConfig", 10))
local Visuals = require(ReplicatedStorage:WaitForChild("HouseDestructionVisuals", 10))
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName, 10)
if not remote then
	warn("[HouseDestructionEffectsClient] Ereignis fehlt; lokale Effekte deaktiviert.")
	return
end

local activeTransient = 0
local byKind = { Collapse = 0, Explosion = 0 }
local tracked, burning, visible = {}, {}, {}
local TAG = "KaijuHouse"

local function distance(position)
	local camera = workspace.CurrentCamera
	if not camera then return math.huge end
	return ((camera.CFrame.Position - position) * Vector3.new(1, 0, 1)).Magnitude
end

remote.OnClientEvent:Connect(function(kind, position, size, maxHealth)
	if byKind[kind] == nil or distance(position) > Config.ViewDistance + math.max(size.X, size.Z) / 2 then return end
	-- Die Hälfte der Plätze bleibt für die andere Phase verfügbar: eine Staubwolke
	-- lebt länger als der Abstand bis zur Explosion desselben Gebäudes.
	if activeTransient >= Config.MaxTransientEffects or byKind[kind] >= Config.MaxTransientEffects / 2 then return end
	activeTransient += 1
	byKind[kind] += 1
	local duration = kind == "Collapse" and Config.DustDuration or Config.ExplosionDuration
	local ok, err = pcall(function()
		if kind == "Collapse" then
			Visuals.Dust(position, size)
			Visuals.Sound(position)
		else
			Visuals.Explosion(position, maxHealth)
		end
	end)
	if not ok then warn("[HouseDestructionEffectsClient] Effekt fehlgeschlagen: " .. tostring(err)) end
	task.delay(duration, function()
		activeTransient -= 1
		byKind[kind] -= 1
	end)
end)

local function hideFire(house)
	local state = visible[house]
	if state then
		state.anchor:Destroy()
		visible[house] = nil
	end
end

local function forget(house)
	if tracked[house] then tracked[house]:Disconnect() end
	tracked[house], burning[house] = nil, nil
	hideFire(house)
end

local function remember(house)
	if tracked[house] then return end
	local function changed()
		local endsAt = house:GetAttribute("FireVisualEndsAt")
		burning[house] = endsAt and true or nil
		-- Löschen und Respawn verschwinden sofort, unabhängig vom Darstellungstakt.
		if not endsAt then hideFire(house) end
	end
	tracked[house] = house:GetAttributeChangedSignal("FireVisualEndsAt"):Connect(changed)
	changed()
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(remember)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(forget)
for _, house in ipairs(CollectionService:GetTagged(TAG)) do remember(house) end

task.spawn(function()
	while true do
		debug.profilebegin("HouseDestructionEffects.Fires")
		local now = workspace:GetServerTimeNow()
		local nearby = {}
		for house in pairs(burning) do
			local position = house:GetAttribute("FireVisualPosition")
			local endsAt = house:GetAttribute("FireVisualEndsAt") or 0
			local away = position and distance(position) or math.huge
			if endsAt <= now then
				burning[house] = nil
			elseif house:IsDescendantOf(workspace) and away <= Config.ViewDistance then
				table.insert(nearby, { house = house, position = position, endsAt = endsAt, away = away })
			end
		end
		table.sort(nearby, function(a, b) return a.away < b.away end)
		local selected = {}
		for i = 1, math.min(#nearby, Config.MaxVisibleFires) do selected[nearby[i].house] = nearby[i] end
		-- Erst alte Darstellung entfernen, dann neue erzeugen: auch beim Ortswechsel
		-- wird die Obergrenze zu keinem Zeitpunkt überschritten.
		for house in pairs(visible) do if not selected[house] then hideFire(house) end end
		for house, item in pairs(selected) do
			local state = visible[house]
			if not state then
				state = Visuals.CreateFire(item.position, house:GetAttribute("MaxHealth") or 100)
				visible[house] = state
			end
			Visuals.UpdateFire(state, item.endsAt - now)
		end
		debug.profileend()
		task.wait(Config.UpdateInterval)
	end
end)
print("[Kaiju Debug] Lokale Zerstoerung: maximal 8 kurze Effekte und 8 nahe Feuer, keine Effekt-Warteschlange.")
