-- Räumliche Vorauswahl für alle Gebäudeangriffe. Das Raster umfasst die GESAMTE
-- Grundfläche inklusive Drehung; auch die Ecke eines riesigen Hauses bleibt erreichbar.
-- Die Aufrufer behalten ihre bisherigen genauen Reichweiten- und Sichtprüfungen.
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Index = {}
local CELL_SIZE = 128
local TAG = "KaijuHouse"
local cells, entries, dirty, oversized = {}, {}, {}, {}

local function key(x, z)
	return x .. ":" .. z
end

local function clearCells(house, entry)
	for _, cellKey in ipairs(entry.keys) do
		local cell = cells[cellKey]
		if cell then
			cell[house] = nil
			if next(cell) == nil then cells[cellKey] = nil end
		end
	end
	entry.keys = {}
	oversized[house] = nil
end

local function refresh(house)
	dirty[house] = nil
	local entry = entries[house]
	if not entry then return end
	clearCells(house, entry)
	if not house:IsDescendantOf(Workspace) or house:GetAttribute("Destroyed") then return end
	local ok, cf, size = pcall(function()
		if house:IsA("BasePart") then return house.CFrame, house.Size end
		return house:GetBoundingBox()
	end)
	if not ok then return end
	for _, value in ipairs({ cf.Position.X, cf.Position.Z, size.X, size.Y, size.Z }) do
		if value ~= value or math.abs(value) == math.huge then return end
	end
	if size.X < 0 or size.Y < 0 or size.Z < 0 then return end
	local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
	local halfX = (math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z) / 2 + 2
	local halfZ = (math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z) / 2 + 2
	local minX, maxX = math.floor((cf.Position.X - halfX) / CELL_SIZE), math.floor((cf.Position.X + halfX) / CELL_SIZE)
	local minZ, maxZ = math.floor((cf.Position.Z - halfZ) / CELL_SIZE), math.floor((cf.Position.Z + halfZ) / CELL_SIZE)
	if minX ~= minX or maxX ~= maxX or minZ ~= minZ or maxZ ~= maxZ
		or halfX == math.huge or halfZ == math.huge then return end
	-- Extreme Bauwerke dürfen das Raster nicht mit Millionen Zellen füllen.
	if (maxX - minX + 1) * (maxZ - minZ + 1) > 256 then
		oversized[house] = true
		return
	end
	for x = minX, maxX do
		for z = minZ, maxZ do
			local cellKey = key(x, z)
			cells[cellKey] = cells[cellKey] or {}
			cells[cellKey][house] = true
			table.insert(entry.keys, cellKey)
		end
	end
end

local function forget(house)
	local entry = entries[house]
	if not entry then return end
	clearCells(house, entry)
	for _, connection in ipairs(entry.connections) do connection:Disconnect() end
	if entry.rootConnection then entry.rootConnection:Disconnect() end
	entries[house], dirty[house] = nil, nil
end

local function remember(house)
	if entries[house] or not (house:IsA("Model") or house:IsA("BasePart")) then return end
	local entry = { keys = {}, connections = {} }
	entries[house] = entry
	local function markDirty() dirty[house] = true end
	local function watchRoot()
		if entry.rootConnection then entry.rootConnection:Disconnect() end
		local root = house:IsA("Model") and house.PrimaryPart or house
		if root and root:IsA("BasePart") then
			entry.rootConnection = root:GetPropertyChangedSignal("CFrame"):Connect(markDirty)
		end
		markDirty()
	end
	for _, signal in ipairs({ house.AncestryChanged, house.DescendantAdded, house.DescendantRemoving,
		house:GetAttributeChangedSignal("Destroyed") }) do
		table.insert(entry.connections, signal:Connect(markDirty))
	end
	if house:IsA("Model") then
		table.insert(entry.connections, house:GetPropertyChangedSignal("PrimaryPart"):Connect(watchRoot))
		table.insert(entry.connections, house:GetPropertyChangedSignal("WorldPivot"):Connect(markDirty))
	else
		table.insert(entry.connections, house:GetPropertyChangedSignal("Size"):Connect(markDirty))
	end
	watchRoot()
	refresh(house)
end

function Index.Query(position, radius)
	debug.profilebegin("HouseSpatialIndex.Query")
	for house in pairs(dirty) do refresh(house) end
	local result, seen = {}, {}
	local function add(house)
		if not seen[house] and house:IsDescendantOf(Workspace) and not house:GetAttribute("Destroyed") then
			seen[house] = true
			table.insert(result, house)
		end
	end
	for x = math.floor((position.X - radius) / CELL_SIZE), math.floor((position.X + radius) / CELL_SIZE) do
		for z = math.floor((position.Z - radius) / CELL_SIZE), math.floor((position.Z + radius) / CELL_SIZE) do
			for house in pairs(cells[key(x, z)] or {}) do add(house) end
		end
	end
	for house in pairs(oversized) do add(house) end
	debug.profileend()
	return result
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(remember)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(forget)
for _, house in ipairs(CollectionService:GetTagged(TAG)) do remember(house) end
print("[Kaiju Debug] Gebaeudesuche: raeumliches 128-Stud-Raster aktiv; genaue Trefferpruefung bleibt erhalten.")
return Index
