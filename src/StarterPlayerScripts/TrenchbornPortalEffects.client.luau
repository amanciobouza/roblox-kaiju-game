-- Trenchborn Portal Client FX v3.1
-- Restores portal particle attraction + oscillating energy grab bands
-- and upgrades the teleport transit sequence.
-- Install as StarterPlayer > StarterPlayerScripts > TrenchbornPortalEffects
-- Expects ReplicatedStorage.TrenchbornPortalRemote and portal models under Workspace.TrenchbornPortals

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("TrenchbornPortalRemote")
local portalsFolder = workspace:WaitForChild("TrenchbornPortals")

local camera = workspace.CurrentCamera

-- =========================================================
-- CONFIG
-- =========================================================
local DEFAULT_ATTRACTION_DISTANCE = 44
local DEFAULT_CINEMATIC_DISTANCE = 30
local DEFAULT_MAX_BANDS = 7
local MIN_BAND_DISTANCE = 6
local PARTICLE_COUNT_PER_PORTAL = 34
local PARTICLE_RESPAWN_RADIUS = 18
local PARTICLE_DEPTH = 8
local PARTICLE_SPEED = 7.5
local BAND_SEGMENTS = 14

-- AUDIO
local PORTAL_AMBIENT_SOUND_ID = "rbxassetid://1838788947"
local PORTAL_TENSION_SOUND_ID = "rbxassetid://131375585708151"
local PORTAL_WOOSH_SOUND_ID = "rbxassetid://139430502777741"

local AMBIENT_VOLUME = 1
local TENSION_MAX_VOLUME = 0.75
local TENSION_MIN_SPEED = 0.90
local TENSION_MAX_SPEED = 1.12

-- =========================================================
-- UI / CINEMATIC
-- =========================================================
local gui = Instance.new("ScreenGui")
gui.Name = "TrenchbornPortalFXGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = player:WaitForChild("PlayerGui")

local topBar = Instance.new("Frame")
topBar.BackgroundColor3 = Color3.new(0,0,0)
topBar.BorderSizePixel = 0
topBar.Size = UDim2.new(1,0,0,0)
topBar.Position = UDim2.fromScale(0,0)
topBar.ZIndex = 100
topBar.Parent = gui

local bottomBar = topBar:Clone()
bottomBar.AnchorPoint = Vector2.new(0,1)
bottomBar.Position = UDim2.fromScale(0,1)
bottomBar.Parent = gui

local veil = Instance.new("Frame")
veil.BackgroundColor3 = Color3.fromRGB(6,8,18)
veil.BackgroundTransparency = 1
veil.BorderSizePixel = 0
veil.Size = UDim2.fromScale(1,1)
veil.ZIndex = 80
veil.Parent = gui

local flash = Instance.new("Frame")
flash.BackgroundColor3 = Color3.new(1,1,1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Size = UDim2.fromScale(1,1)
flash.ZIndex = 120
flash.Parent = gui

local streakLayer = Instance.new("Frame")
streakLayer.BackgroundTransparency = 1
streakLayer.Size = UDim2.fromScale(1,1)
streakLayer.ZIndex = 90
streakLayer.Parent = gui

local blur = Lighting:FindFirstChild("TrenchbornPortalBlur") or Instance.new("BlurEffect")
blur.Name = "TrenchbornPortalBlur"
blur.Size = 0
blur.Parent = Lighting

local colorFx = Lighting:FindFirstChild("TrenchbornPortalColor") or Instance.new("ColorCorrectionEffect")
colorFx.Name = "TrenchbornPortalColor"
colorFx.Saturation = 0
colorFx.Contrast = 0
colorFx.Brightness = 0
colorFx.Parent = Lighting

local cinematicShown = false
local inTransit = false
local baseFov = camera.FieldOfView

local function tween(obj, duration, props, style, direction)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function showBars(show)
	if show == cinematicShown then return end
	cinematicShown = show
	local h = show and 0.075 or 0
	tween(topBar, 0.25, {Size = UDim2.new(1,0,h,0)})
	tween(bottomBar, 0.25, {Size = UDim2.new(1,0,h,0)})
end

-- =========================================================
-- PORTAL HELPERS
-- =========================================================
local function getField(portal)
	return portal:FindFirstChild("EnergyField", true)
		or portal:FindFirstChild("PortalField", true)
		or portal:FindFirstChild("Field", true)
end

local function getPortalColor(portal)
	local attr = portal:GetAttribute("EnergyColor")
	if typeof(attr) == "Color3" then
		return attr
	end
	local field = getField(portal)
	if field and field:IsA("BasePart") then
		return field.Color
	end
	return Color3.fromRGB(70, 170, 255)
end

local function getPortalCenter(portal)
	local field = getField(portal)
	if field and field:IsA("BasePart") then
		return field.Position, field.CFrame
	end
	if portal.PrimaryPart then
		return portal.PrimaryPart.Position, portal.PrimaryPart.CFrame
	end
	local p = portal:FindFirstChildWhichIsA("BasePart", true)
	if p then
		return p.Position, p.CFrame
	end
end

local function portalActive(portal)
	local a = portal:GetAttribute("Active")
	return a == nil or a == true
end

-- =========================================================
-- PORTAL AUDIO
-- =========================================================
local portalAudio = {}

local function getOrCreateSound(parent, name, soundId, looped, volume)
	local s = parent:FindFirstChild(name)
	if not s then
		s = Instance.new("Sound")
		s.Name = name
		s.Parent = parent
	end
	s.SoundId = soundId
	s.Looped = looped
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 18
	s.RollOffMaxDistance = 120
	return s
end

local function ensurePortalAudio(portal)
	if portalAudio[portal] then
		return portalAudio[portal]
	end

	local field = getField(portal)
	if not field or not field:IsA("BasePart") then
		return nil
	end

	local ambient = getOrCreateSound(field, "PortalAmbient", PORTAL_AMBIENT_SOUND_ID, true, AMBIENT_VOLUME)
	ambient.PlaybackSpeed = 1.0
	if not ambient.IsPlaying then ambient:Play() end

	local tension = getOrCreateSound(field, "PortalTension", PORTAL_TENSION_SOUND_ID, true, 0)
	tension.PlaybackSpeed = TENSION_MIN_SPEED
	if not tension.IsPlaying then tension:Play() end

	local woosh = getOrCreateSound(field, "PortalWoosh", PORTAL_WOOSH_SOUND_ID, false, 1.35)
	woosh.PlaybackSpeed = 0.92

	-- Same source layered lower and slightly delayed: adds weight without another asset.
	local wooshImpact = getOrCreateSound(field, "PortalWooshImpact", PORTAL_WOOSH_SOUND_ID, false, 0.85)
	wooshImpact.PlaybackSpeed = 0.72

	local eq = woosh:FindFirstChild("PortalWooshEQ") or Instance.new("EqualizerSoundEffect")
	eq.Name = "PortalWooshEQ"
	eq.LowGain = 5
	eq.MidGain = 1
	eq.HighGain = 2
	eq.Parent = woosh

	local impactEq = wooshImpact:FindFirstChild("PortalWooshImpactEQ") or Instance.new("EqualizerSoundEffect")
	impactEq.Name = "PortalWooshImpactEQ"
	impactEq.LowGain = 8
	impactEq.MidGain = 2
	impactEq.HighGain = -2
	impactEq.Parent = wooshImpact

	portalAudio[portal] = {
		ambient = ambient,
		tension = tension,
		woosh = woosh,
		wooshImpact = wooshImpact,
	}
	return portalAudio[portal]
end

local function updatePortalAudio(portal, distance)
	local audio = ensurePortalAudio(portal)
	if not audio then return end

	local attractDist = portal:GetAttribute("AttractionDistance") or DEFAULT_ATTRACTION_DISTANCE
	local alpha = 0
	if distance and distance <= attractDist then
		alpha = 1 - math.clamp(
			(distance - MIN_BAND_DISTANCE) / math.max(attractDist - MIN_BAND_DISTANCE, 1),
			0, 1
		)
	end

	-- Very subtle at range, much more dramatic near the field.
	local intensity = alpha * alpha
	audio.tension.Volume = TENSION_MAX_VOLUME * intensity
	audio.tension.PlaybackSpeed =
		TENSION_MIN_SPEED + (TENSION_MAX_SPEED - TENSION_MIN_SPEED) * intensity
end

local function playTeleportWoosh(portal)
	local audio = ensurePortalAudio(portal)
	if not audio then return end

	tween(audio.tension, 0.12, {Volume = 0})
	audio.woosh.TimePosition = 0
	audio.woosh.Volume = 1.35
	audio.woosh:Play()

	-- A lower second layer lands shortly after the initial whoosh.
	task.delay(0.10, function()
		if audio.wooshImpact and audio.wooshImpact.Parent then
			audio.wooshImpact.TimePosition = 0
			audio.wooshImpact.Volume = 0.85
			audio.wooshImpact:Play()
		end
	end)
end

-- =========================================================
-- 3D PARTICLE SUCTION
-- =========================================================
local particleFolder = workspace:FindFirstChild("TrenchbornPortalClientParticles")
if not particleFolder then
	particleFolder = Instance.new("Folder")
	particleFolder.Name = "TrenchbornPortalClientParticles"
	particleFolder.Parent = workspace
end

local portalParticles = {}

local function makeParticle(portal)
	local color = getPortalColor(portal)
	local p = Instance.new("Part")
	p.Name = "PortalParticle"
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.14,0.14,0.14)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = math.random() * 0.35
	p.Parent = particleFolder

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0.6
	light.Range = 2
	light.Parent = p

	return {
		part = p,
		phase = math.random() * math.pi * 2,
		radius = 5 + math.random() * PARTICLE_RESPAWN_RADIUS,
		angle = math.random() * math.pi * 2,
		y = (math.random() - 0.5) * 16,
		speed = PARTICLE_SPEED * (0.75 + math.random() * 0.8),
	}
end

local function ensureParticles(portal)
	if portalParticles[portal] then return end
	portalParticles[portal] = {}
	for _ = 1, PARTICLE_COUNT_PER_PORTAL do
		table.insert(portalParticles[portal], makeParticle(portal))
	end
end

local function resetParticle(data)
	data.radius = 8 + math.random() * PARTICLE_RESPAWN_RADIUS
	data.angle = math.random() * math.pi * 2
	data.y = (math.random() - 0.5) * 15
	data.phase = math.random() * math.pi * 2
end

-- =========================================================
-- ENERGY GRAB BANDS
-- =========================================================
local bandFolder = workspace:FindFirstChild("TrenchbornPortalClientBands")
if not bandFolder then
	bandFolder = Instance.new("Folder")
	bandFolder.Name = "TrenchbornPortalClientBands"
	bandFolder.Parent = workspace
end

local activeBands = {}

local function makeBandSegment(color)
	local p = Instance.new("Part")
	p.Name = "EnergyBandSegment"
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.new(0.14,0.14,1)
	p.Transparency = 0.08
	p.Parent = bandFolder
	return p
end

local function clearBands()
	for _, b in ipairs(activeBands) do
		for _, s in ipairs(b.segments) do
			s:Destroy()
		end
	end
	table.clear(activeBands)
end

local function createBand(portal, index)
	local color = getPortalColor(portal)
	local band = {
		portal = portal,
		index = index,
		phase = index * 1.37 + math.random(),
		segments = {},
		seed = math.random() * 100,
	}
	for _ = 1, BAND_SEGMENTS do
		table.insert(band.segments, makeBandSegment(color))
	end
	table.insert(activeBands, band)
	return band
end

local function setBandCount(portal, count)
	local currentForPortal = {}
	for _, b in ipairs(activeBands) do
		if b.portal == portal then
			table.insert(currentForPortal, b)
		end
	end

	while #currentForPortal < count do
		table.insert(currentForPortal, createBand(portal, #currentForPortal + 1))
	end

	while #currentForPortal > count do
		local b = table.remove(currentForPortal)
		for _, s in ipairs(b.segments) do s:Destroy() end
		for i = #activeBands, 1, -1 do
			if activeBands[i] == b then
				table.remove(activeBands, i)
				break
			end
		end
	end
end

local function positionSegment(part, a, b, thickness, transparency)
	local delta = b - a
	local len = delta.Magnitude
	if len < 0.02 then
		part.Transparency = 1
		return
	end
	part.Transparency = transparency
	part.Size = Vector3.new(thickness, thickness, len)
	part.CFrame = CFrame.lookAt((a+b)*0.5, b)
end

local function updateBand(band, t, root)
	local center, cf = getPortalCenter(band.portal)
	if not center or not cf or not root then return end

	local start = center
	local endPos = root.Position + Vector3.new(0, math.sin(t*2 + band.phase)*1.2, 0)

	local right = cf.RightVector
	local up = cf.UpVector
	local forward = cf.LookVector

	for i, seg in ipairs(band.segments) do
		local u0 = (i-1)/BAND_SEGMENTS
		local u1 = i/BAND_SEGMENTS

		local function curve(u)
			local linear = start:Lerp(endPos, u)
			local envelope = math.sin(math.pi * u)
			local amp = (1.6 + band.index * 0.17) * envelope
			local sway =
				right * math.sin(t*4.2 + u*9 + band.phase) * amp +
				up * math.cos(t*3.4 + u*7 + band.phase*1.7) * amp * 0.7 +
				forward * math.sin(t*2.7 + u*11 + band.seed) * amp * 0.22
			return linear + sway
		end

		local a = curve(u0)
		local b = curve(u1)
		local pulse = 0.11 + 0.05 * math.sin(t*8 + i + band.phase)
		positionSegment(seg, a, b, math.max(0.06, pulse), 0.08)
	end
end

-- =========================================================
-- TRANSIT SCREEN FX
-- =========================================================
local function clearStreaks()
	for _, c in ipairs(streakLayer:GetChildren()) do c:Destroy() end
end

local function spawnStreaks(color)
	clearStreaks()
	local cx, cy = 0.5, 0.5
	for i = 1, 52 do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0,0.5)
		line.BackgroundColor3 = color:Lerp(Color3.new(1,1,1), math.random()*0.45)
		line.BorderSizePixel = 0
		line.ZIndex = 91
		local angle = math.random() * math.pi * 2
		local radius = 0.03 + math.random()*0.12
		local x = cx + math.cos(angle)*radius
		local y = cy + math.sin(angle)*radius
		line.Position = UDim2.fromScale(x,y)
		line.Rotation = math.deg(angle)
		line.Size = UDim2.fromScale(0.01 + math.random()*0.025, 0.002 + math.random()*0.004)
		line.BackgroundTransparency = 0.08 + math.random()*0.3
		line.Parent = streakLayer

		task.spawn(function()
			local targetLen = 0.45 + math.random()*0.5
			local targetX = cx + math.cos(angle)*(0.5 + math.random()*0.5)
			local targetY = cy + math.sin(angle)*(0.5 + math.random()*0.5)
			tween(line, 0.55 + math.random()*0.45, {
				Position = UDim2.fromScale(targetX,targetY),
				Size = UDim2.fromScale(targetLen, line.Size.Y.Scale),
				BackgroundTransparency = 0.35
			}, Enum.EasingStyle.Exponential, Enum.EasingDirection.In)
		end)
	end
end

local function beginTransit(portal)
	if inTransit then return end
	inTransit = true
	local color = portal and getPortalColor(portal) or Color3.fromRGB(80,160,255)

	if portal then
		playTeleportWoosh(portal)
	end

	showBars(true)
	baseFov = camera.FieldOfView

	tween(veil, 0.18, {BackgroundTransparency = 0.25})
	tween(blur, 0.25, {Size = 24})
	tween(colorFx, 0.25, {Saturation = -0.35, Contrast = 0.25, Brightness = -0.04})
	tween(camera, 0.32, {FieldOfView = math.min(baseFov + 22, 100)}, Enum.EasingStyle.Quart)

	spawnStreaks(color)

	task.delay(0.65, function()
		if not inTransit then return end
		tween(flash, 0.20, {BackgroundTransparency = 0})
		tween(blur, 0.18, {Size = 38})
	end)
end

local function arrive()
	tween(flash, 0.28, {BackgroundTransparency = 1})
	tween(veil, 0.35, {BackgroundTransparency = 1})
	tween(blur, 0.38, {Size = 0})
	tween(colorFx, 0.38, {Saturation = 0, Contrast = 0, Brightness = 0})
	tween(camera, 0.38, {FieldOfView = baseFov}, Enum.EasingStyle.Quart)
	clearStreaks()

	task.delay(0.35, function()
		inTransit = false
		showBars(false)
	end)
end

-- =========================================================
-- MAIN UPDATE
-- =========================================================
local currentPortal = nil

local function nearestPortal(root)
	local best, bestDist
	for _, portal in ipairs(portalsFolder:GetChildren()) do
		if portal:IsA("Model") and portalActive(portal) then
			local center = getPortalCenter(portal)
			if center then
				local d = (root.Position - center).Magnitude
				if not bestDist or d < bestDist then
					best = portal
					bestDist = d
				end
			end
		end
	end
	return best, bestDist
end

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		clearBands()
		return
	end

	local portal, dist = nearestPortal(root)
	currentPortal = portal

	-- Ambient is always attached to every active portal.
	-- Tension is dynamically driven only by the nearest portal.
	for _, p in ipairs(portalsFolder:GetChildren()) do
		if p:IsA("Model") and portalActive(p) then
			ensurePortalAudio(p)
			if p == portal then
				updatePortalAudio(p, dist)
			else
				updatePortalAudio(p, nil)
			end
		end
	end

	-- persistent portal particles
	for _, p in ipairs(portalsFolder:GetChildren()) do
		if p:IsA("Model") and portalActive(p) then
			ensureParticles(p)
			local center, cf = getPortalCenter(p)
			if center and cf then
				for _, data in ipairs(portalParticles[p]) do
					data.radius -= data.speed * dt
					data.angle += dt * (0.75 + 8/math.max(data.radius,2))
					if data.radius <= 0.6 then
						resetParticle(data)
					end
					local wobble = math.sin(time()*3 + data.phase) * 0.7
					local pos =
						center
						+ cf.RightVector * math.cos(data.angle) * data.radius
						+ cf.UpVector * (data.y * (data.radius/(PARTICLE_RESPAWN_RADIUS+8)) + wobble)
					- cf.LookVector * (PARTICLE_DEPTH * (1 - math.clamp(data.radius/25,0,1)))
					data.part.Position = pos
					data.part.Color = getPortalColor(p)
				end
			end
		end
	end

	if portal and dist then
		local attractDist = portal:GetAttribute("AttractionDistance") or DEFAULT_ATTRACTION_DISTANCE
		local cineDist = portal:GetAttribute("CinematicDistance") or DEFAULT_CINEMATIC_DISTANCE
		local maxBands = portal:GetAttribute("MaxBands") or DEFAULT_MAX_BANDS

		if not inTransit then
			showBars(dist <= cineDist)
		end

		if dist <= attractDist then
			local alpha = 1 - math.clamp((dist - MIN_BAND_DISTANCE) / math.max(attractDist - MIN_BAND_DISTANCE, 1), 0, 1)
			local bandCount = math.clamp(math.ceil(alpha * maxBands), 1, maxBands)
			setBandCount(portal, bandCount)
		else
			setBandCount(portal, 0)
		end
	else
		if not inTransit then showBars(false) end
		clearBands()
	end

	local now = time()
	for _, band in ipairs(activeBands) do
		updateBand(band, now, root)
	end
end)

-- =========================================================
-- SERVER EVENTS
-- =========================================================
remote.OnClientEvent:Connect(function(action, portal)
	if action == "BeginTeleport" then
		beginTransit(portal)
	elseif action == "Arrive" then
		arrive()
	end
end)

print("[TrenchbornPortalFX] CLIENT v3.3 ACTIVE - particles + grab bands + dynamic portal audio + upgraded transit")