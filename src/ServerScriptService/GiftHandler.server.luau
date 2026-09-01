-- VERSION: 2026-08-25 #6
-- Ort in Studio: ServerScriptService
-- Verwaltet die 12 Zeit-Geschenke. Freischalt-Zeitpunkte werden immer weiter auseinander
-- gezogen (erste Geschenke schnell, letzte brauchen lange) -- Gesamtdauer 2 Stunden.
-- Das Session-Start-Timing kommt von PlayerSetup.lua (Attribut "SessionStartTime").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local Workspace = game:GetService("Workspace")

local ClaimGiftEvent = RemoteEventUtils.GetOrCreate("ClaimGiftEvent")

local TOTAL_DURATION = 7200 -- 2 Stunden in Sekunden
local GIFT_COUNT = 12
local SPACING_EXPONENT = 1.8 -- >1 = Abstände werden immer größer (erste Geschenke schnell)

-- Berechnet den Freischalt-Zeitpunkt (Sekunden nach Sessionstart) für Geschenk Nummer n (1-12)
local function unlockTimeForGift(n)
	return math.floor(TOTAL_DURATION * (n / GIFT_COUNT) ^ SPACING_EXPONENT)
end

-- Die 12 Geschenke: Typ + Wert. "Coins"/"XP"/"Evolution" sind Sofort-Belohnungen,
-- "CoinsBoost"/"DamageBoost"/"MegaBoost" sind temporäre Multiplikatoren.
local GIFTS = {
	{ type = "Coins", amount = 50 },
	{ type = "XP", amount = 1000 }, -- ÷100 (war 100000) -- konsistent zur Energie-Formel-Korrektur
	{ type = "Coins", amount = 150 },
	{ type = "Evolution", amount = 5 },
	{ type = "CoinsBoost", multiplier = 2, duration = 300 }, -- 5 Min. 2x Coins
	{ type = "XP", amount = 3000 }, -- ÷100 (war 300000) -- konsistent zur Energie-Formel-Korrektur
	{ type = "Coins", amount = 400 },
	{ type = "Evolution", amount = 10 },
	{ type = "DamageBoost", multiplier = 2, duration = 600 }, -- 10 Min. 2x Schaden
	{ type = "Coins", amount = 800 },
	{ type = "Evolution", amount = 15 },
	{ type = "MegaBoost", coinsMultiplier = 3, damageMultiplier = 3, duration = 600 }, -- Hauptpreis
}

-- Für den Client bereitstellen (fürs HUD)
local giftCountValue = Instance.new("IntValue")
giftCountValue.Name = "GiftCount"
giftCountValue.Value = GIFT_COUNT
giftCountValue.Parent = ReplicatedStorage

local giftUnlockTimesFolder = Instance.new("Folder")
giftUnlockTimesFolder.Name = "GiftUnlockTimes"
giftUnlockTimesFolder.Parent = ReplicatedStorage
for n = 1, GIFT_COUNT do
	local value = Instance.new("IntValue")
	value.Name = "Gift" .. n
	value.Value = unlockTimeForGift(n)
	value.Parent = giftUnlockTimesFolder
end

local giftDescriptionsFolder = Instance.new("Folder")
giftDescriptionsFolder.Name = "GiftDescriptions"
giftDescriptionsFolder.Parent = ReplicatedStorage
local function describeGift(gift)
	if gift.type == "Coins" then
		return "🪙 " .. gift.amount .. " Coins"
	elseif gift.type == "XP" then
		return "⭐ " .. gift.amount .. " XP"
	elseif gift.type == "Evolution" then
		return "🧬 " .. gift.amount .. " Evolution-Punkte"
	elseif gift.type == "CoinsBoost" then
		return "🪙 " .. gift.multiplier .. "x Coins (" .. math.floor(gift.duration / 60) .. " Min.)"
	elseif gift.type == "DamageBoost" then
		return "💥 " .. gift.multiplier .. "x Schaden (" .. math.floor(gift.duration / 60) .. " Min.)"
	elseif gift.type == "MegaBoost" then
		return "🎉 " .. gift.coinsMultiplier .. "x Coins + " .. gift.damageMultiplier .. "x Schaden (" .. math.floor(gift.duration / 60) .. " Min.)"
	end
	return "?"
end
for n, gift in ipairs(GIFTS) do
	local desc = Instance.new("StringValue")
	desc.Name = "Gift" .. n
	desc.Value = describeGift(gift)
	desc.Parent = giftDescriptionsFolder
end

-- Aktiviert die Belohnung von Geschenk n für den Spieler.
local function grantGift(player, n)
	local gift = GIFTS[n]
	if not gift then
		return
	end

	-- Lebensstatistik: hier oben, damit JEDES vergebene Geschenk zählt -- nicht nur die
	-- Coins-Geschenke. Darunter folgt eine if/elseif-Kette über die Geschenktypen; ein
	-- Zähler in einem der Zweige würde die anderen Typen stillschweigend übergehen.
	if _G.RecordStat then
		_G.RecordStat(player, "GiftsReceived")
		if gift.type then
			_G.RecordStat(player, "GiftsReceived." .. tostring(gift.type))
		end
	end

	if gift.type == "Coins" then
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats and leaderstats:FindFirstChild("Coins") then
			leaderstats.Coins.Value += gift.amount
			if _G.RecordStat then
				_G.RecordStat(player, "CoinsCollected", gift.amount)
			end
		end
	elseif gift.type == "XP" then
		if _G.AwardXP then
			_G.AwardXP(player, gift.amount)
		end
	elseif gift.type == "Evolution" then
		local evolutionPoints = player:FindFirstChild("EvolutionPoints")
		if evolutionPoints then
			evolutionPoints.Value += gift.amount
		end
	elseif gift.type == "CoinsBoost" then
		player:SetAttribute("CoinsBoostMultiplier", gift.multiplier)
		player:SetAttribute("CoinsBoostEndsAt", Workspace:GetServerTimeNow() + gift.duration)
	elseif gift.type == "DamageBoost" then
		player:SetAttribute("DamageBoostMultiplier", gift.multiplier)
		player:SetAttribute("DamageBoostEndsAt", Workspace:GetServerTimeNow() + gift.duration)
		if _G.RecalculateStrength then
			_G.RecalculateStrength(player)
		end
	elseif gift.type == "MegaBoost" then
		player:SetAttribute("CoinsBoostMultiplier", gift.coinsMultiplier)
		player:SetAttribute("CoinsBoostEndsAt", Workspace:GetServerTimeNow() + gift.duration)
		player:SetAttribute("DamageBoostMultiplier", gift.damageMultiplier)
		player:SetAttribute("DamageBoostEndsAt", Workspace:GetServerTimeNow() + gift.duration)
		if _G.RecalculateStrength then
			_G.RecalculateStrength(player)
		end
	end
end

ClaimGiftEvent.OnServerEvent:Connect(function(player, giftNumber)
	if type(giftNumber) ~= "number" or giftNumber < 1 or giftNumber > GIFT_COUNT then
		return
	end

	local claimedFolder = player:FindFirstChild("ClaimedGifts")
	if not claimedFolder then
		return
	end

	local marker = claimedFolder:FindFirstChild("Gift" .. giftNumber)
	if marker and marker.Value then
		return -- schon abgeholt
	end

	local sessionStart = player:GetAttribute("SessionStartTime") or Workspace:GetServerTimeNow()
	local elapsed = Workspace:GetServerTimeNow() - sessionStart
	if elapsed < unlockTimeForGift(giftNumber) then
		return -- noch nicht bereit
	end

	if marker then
		marker.Value = true
	end

	grantGift(player, giftNumber)
end)

Players.PlayerAdded:Connect(function(player)
	local claimedFolder = Instance.new("Folder")
	claimedFolder.Name = "ClaimedGifts"
	claimedFolder.Parent = player

	for n = 1, GIFT_COUNT do
		local marker = Instance.new("BoolValue")
		marker.Name = "Gift" .. n
		marker.Value = false
		marker.Parent = claimedFolder
	end
end)