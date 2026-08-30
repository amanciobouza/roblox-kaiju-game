-- VERSION: 2026-08-25 #1 (RemoteEventUtils-Umstellung)
-- LocalScript: RadiusDebugClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- NUR FÜRS DEBUGGING: Zeigt zwei halbtransparente Scheiben am Boden -- eine für den
-- Flächenschaden-Radius (rot), eine für den Energie-Sog-Radius (orange). Reagiert auf
-- das zentrale "DebugMode"-Attribut (siehe DebugPanelClient.lua -- Checkbox im HUD oder
-- Taste V). Nur für den lokalen Spieler sichtbar (rein clientseitig, keine Replikation).
--
-- WICHTIG: Die Formeln hier müssen manuell synchron zu den echten Formeln in
-- SpecialAttackHandler.lua (getAreaAttackRadius) und EnergyCollectionHandler.lua
-- (getCollectionRadius) gehalten werden -- falls die dort geändert werden, hier bitte
-- nachziehen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local player = Players.LocalPlayer
local AreaAttackEffectEvent = RemoteEventUtils.GetOrCreate("AreaAttackEffectEvent")

local ENERGY_RADIUS_BASE = 88
local ENERGY_RADIUS_SCALE = 18
local ENERGY_RADIUS_EXPONENT = 0.7

-- Wie lange die Area-Radius-Scheibe nach der Explosion noch sichtbar bleibt
local AREA_RADIUS_LINGER_AFTER_EXPLOSION = 3

local function getEnergyRadius()
	local bodyPower = player:FindFirstChild("BodyPower")
	local bodyValue = bodyPower and bodyPower.Value or 0
	return ENERGY_RADIUS_BASE + ENERGY_RADIUS_SCALE * (bodyValue ^ ENERGY_RADIUS_EXPONENT)
end

local function createDebugDisc(name, color)
	local disc = Instance.new("Part")
	disc.Name = name
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CastShadow = false
	disc.Material = Enum.Material.ForceField
	disc.Color = color
	disc.Transparency = 0.25
	disc.Parent = workspace
	return disc
end

local energyDisc = nil
local heartbeatConnection = nil
local enabled = false

-- Area-Radius-Scheibe: eigener Zustand, unabhängig vom generellen enabled/disabled --
-- lebt nur während einer laufenden Area-Angriff-Sequenz (Laden + ein paar Sekunden danach).
local areaDisc = nil
local areaDiscPosition = nil
local areaDiscRadius = 0
local areaDiscHideTime = 0 -- os.clock()-Zeitpunkt, ab dem die Scheibe wieder verschwinden soll

local function updateDiscs()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and energyDisc then
		local groundY = rootPart.Position.Y - (rootPart.Size.Y / 2) - 1
		local energyRadius = getEnergyRadius()
		energyDisc.Size = Vector3.new(0.2, energyRadius * 2, energyRadius * 2)
		energyDisc.CFrame = CFrame.new(rootPart.Position.X, groundY + 0.3, rootPart.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	end

	if areaDisc then
		if os.clock() >= areaDiscHideTime then
			areaDisc:Destroy()
			areaDisc = nil
		else
			local groundY = areaDiscPosition.Y - 2
			areaDisc.Size = Vector3.new(0.2, areaDiscRadius * 2, areaDiscRadius * 2)
			areaDisc.CFrame = CFrame.new(areaDiscPosition.X, groundY, areaDiscPosition.Z) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

-- Zeigt den Area-Radius NUR während der eigenen Angriffs-Sequenz: ab dem Start des
-- Ladens (chargeTime Sekunden) bis ein paar Sekunden nach der Explosion.
AreaAttackEffectEvent.OnClientEvent:Connect(function(attackerPlayer, position, chargeTime, radius)
	if attackerPlayer ~= player or not player:GetAttribute("DebugMode") then
		return
	end

	if not areaDisc then
		areaDisc = createDebugDisc("DebugAreaRadius", Color3.fromRGB(255, 80, 40))
	end
	areaDiscPosition = position
	areaDiscRadius = radius
	areaDiscHideTime = os.clock() + chargeTime + AREA_RADIUS_LINGER_AFTER_EXPLOSION
end)

local function enableDebug()
	if enabled then
		return
	end
	enabled = true
	energyDisc = createDebugDisc("DebugEnergyRadius", Color3.fromRGB(255, 170, 60))
	-- areaDisc wird NICHT hier erstellt -- entsteht erst, wenn tatsächlich ein
	-- Flächenangriff gestartet wird (siehe AreaAttackEffectEvent weiter oben).
	updateDiscs()
	heartbeatConnection = RunService.Heartbeat:Connect(updateDiscs)
end

local function disableDebug()
	if not enabled then
		return
	end
	enabled = false
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if areaDisc then
		areaDisc:Destroy()
		areaDisc = nil
	end
	if energyDisc then
		energyDisc:Destroy()
		energyDisc = nil
	end
end

player:GetAttributeChangedSignal("DebugMode"):Connect(function()
	if player:GetAttribute("DebugMode") then
		enableDebug()
	else
		disableDebug()
	end
end)

if player:GetAttribute("DebugMode") then
	enableDebug()
end