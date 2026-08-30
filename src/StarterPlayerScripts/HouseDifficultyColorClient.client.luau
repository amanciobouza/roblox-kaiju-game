-- LocalScript: HouseDifficultyColorClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Färbt die Healthbar jedes Hauses individuell für DIESEN Spieler ein, basierend auf dem
-- Verhältnis Haus-MaxHealth zur eigenen aktuellen Stärke (Damage). Dasselbe Haus kann für
-- unterschiedliche Spieler unterschiedliche Farben haben (bzw. für denselben Spieler im
-- Laufe der Zeit die Farbe wechseln, sobald er stärker wird).
--
-- 🟢 Grün    = sehr leicht
-- 🟡 Gelb    = lohnendes Ziel
-- 🟠 Orange  = stark
-- 🔴 Rot     = aktuell sehr schwierig
-- 🟣 Violett = Landmark / besonders hohe Belohnung (Attribut "IsLandmark" = true am Haus)

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local HOUSE_TAG = "KaijuHouse"

local COLOR_GREEN = Color3.fromRGB(90, 220, 90)
local COLOR_YELLOW = Color3.fromRGB(230, 200, 60)
local COLOR_ORANGE = Color3.fromRGB(230, 140, 50)
local COLOR_RED = Color3.fromRGB(220, 70, 70)
local COLOR_PURPLE = Color3.fromRGB(170, 90, 220)

-- Verhältnis = Haus-MaxHealth / eigene Stärke -- grob "wie viele Treffer bräuchte ich".
-- Anpassbar, falls sich die Einteilung falsch anfühlt.
local RATIO_EASY = 3 -- darunter: Grün
local RATIO_WORTHWHILE = 10 -- darunter: Gelb
local RATIO_STRONG = 30 -- darunter: Orange, darüber: Rot

local function getDifficultyColor(house, playerDamage)
	if house:GetAttribute("IsLandmark") then
		return COLOR_PURPLE
	end

	local maxHealth = house:GetAttribute("MaxHealth") or 100
	local ratio = maxHealth / math.max(playerDamage, 1)

	if ratio < RATIO_EASY then
		return COLOR_GREEN
	elseif ratio < RATIO_WORTHWHILE then
		return COLOR_YELLOW
	elseif ratio < RATIO_STRONG then
		return COLOR_ORANGE
	else
		return COLOR_RED
	end
end

-- Findet das Anker-Teil eines Hauses (PrimaryPart bei Models, das Teil selbst bei direkt
-- getaggten Parts/MeshParts ohne Model drumherum).
local function getAnchorPart(house)
	if house:IsA("Model") then
		return house.PrimaryPart
	elseif house:IsA("BasePart") then
		return house
	end
	return nil
end

local UPDATE_INTERVAL = 0.5 -- nicht jeden Frame, spart Performance bei vielen Häusern
local accumulator = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < UPDATE_INTERVAL then
		return
	end
	accumulator = 0

	local character = player.Character
	local playerDamage = (character and character:GetAttribute("Damage")) or 10

	for _, house in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		local anchorPart = getAnchorPart(house)
		local billboard = anchorPart and anchorPart:FindFirstChild("HouseHealthBar")
		local hpLabel = billboard and billboard:FindFirstChild("HPLabel", true)
		if hpLabel then
			hpLabel.TextColor3 = getDifficultyColor(house, playerDamage)
		end
	end
end)
