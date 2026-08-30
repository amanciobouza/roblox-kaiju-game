-- VERSION: 2026-08-26 #5
-- CHANGE: Prolog-Isolation für Special Energy entfernt (Spieler kann jetzt Energie sammeln)
-- Ort in Studio: ServerScriptService
--
-- "Special Energy": schnelle, taktische Combat-Ressource, GETRENNT von Berserker/Heat.
-- Wird durch aktives Kämpfen aufgebaut (Punch, Combo, Sprung-Landung, Gebäude-Schaden/
-- -Zerstörung, Absorb) und für Focus-/Area-Angriffe ausgegeben (siehe
-- SpecialAttackHandler.lua). Absorb ist dabei ein BOOSTER, keine Pflicht -- Energy
-- entsteht auch ganz normal durchs Kämpfen, damit der Rhythmus SMASH->SMASH->DESTROY->
-- SPECIAL->SMASH bleibt, statt ständig zwischen Angriff und Absorb wechseln zu müssen.
--
-- Alle Werte hier sind bewusst zentral gesammelt fürs spätere Balancing -- einfach
-- diese Datei anpassen, nichts anderes muss angefasst werden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== Zentrale Balance-Werte =====
local SPECIAL_ENERGY_MAX = 100

local SPECIAL_ENERGY_COSTS = {
	Focus = 25,
	Area = 40,
}

local SPECIAL_ENERGY_GAINS = {
	-- Zielwert: 25 Energy (Focus-Kosten) durch reines Kämpfen (Schläge) in ca. 20 Sekunden
	-- erreichbar -- genauso lang wie der frühere feste Focus-Cooldown, damit sich das
	-- Tempo vertraut anfühlt. Bei angenommenem Schlagtempo von ~0.8s/Treffer sind das
	-- ~25 Treffer in 20s -> ca. 1 Energy pro Treffer im Schnitt. Deutlich reduziert
	-- gegenüber den ursprünglichen Ausgangswerten, die sich beim Testen zu schnell
	-- anfühlten.
	PunchHit = 1,
	ComboHit = 1, -- normaler Combo-Treffer (Schritt 2)
	ThirdComboHit = 3, -- Finisher (Schritt 3) -- bewusst höher, motiviert den Combo abzuschliessen
	JumpLanding = 2,
	BuildingDamagePerHP = 0.008, -- kleine, proportionale Menge pro verursachtem Gebäude-Schaden
	BuildingDestroyed = 3,
	AbsorbMin = 6,
	AbsorbMax = 15,
	AbsorbPerEnergyUnit = 0.25, -- Absorb skaliert zusätzlich mit der tatsächlich absorbierten Menge, geclampt auf Min/Max -- bleibt bewusst effizienter als reines Kämpfen (siehe Design-Vorgabe: Absorb ist ein Booster)
}

-- Für den Client bereitstellen (HUD: Kosten-Anzeige auf Focus-/Area-Buttons, maximale
-- Füllung für den Energy-Arc ums Berserker-Zifferblatt).
local function publishConfigValue(name, value, className)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local valueObject = Instance.new(className)
	valueObject.Name = name
	valueObject.Value = value
	valueObject.Parent = ReplicatedStorage
end

publishConfigValue("SpecialEnergyMax", SPECIAL_ENERGY_MAX, "IntValue")
publishConfigValue("FocusEnergyCost", SPECIAL_ENERGY_COSTS.Focus, "IntValue")
publishConfigValue("AreaEnergyCost", SPECIAL_ENERGY_COSTS.Area, "IntValue")

-- ===== Speicher pro Spieler (Attribut, ähnlich wie Heat) =====
Players.PlayerAdded:Connect(function(player)
	if player:GetAttribute("SpecialEnergy") == nil then
		player:SetAttribute("SpecialEnergy", 0)
	end
end)
for _, player in ipairs(Players:GetPlayers()) do
	if player:GetAttribute("SpecialEnergy") == nil then
		player:SetAttribute("SpecialEnergy", 0)
	end
end

-- ===== Energy hinzufügen (von CombatHandler/HouseHandler/EnergyCollectionHandler
-- aufgerufen) -- clamped auf SPECIAL_ENERGY_MAX. =====
local function awardSpecialEnergy(player, amount)
	if not player or not player.Parent or not amount or amount <= 0 then
		return
	end
	local current = player:GetAttribute("SpecialEnergy") or 0
	player:SetAttribute("SpecialEnergy", math.min(current + amount, SPECIAL_ENERGY_MAX))

	-- Achievements: Lifetime-Zähler zählt den VOLLEN Gewinn, auch falls ein Teil durch
	-- den Cap "verloren" geht -- ein Spieler, der ständig am Cap hängt, hat trotzdem
	-- kontinuierlich Energy generiert.
	if _G.OnSpecialEnergyGainedForAchievements then
		_G.OnSpecialEnergyGainedForAchievements(player, amount)
	end
end
_G.AwardSpecialEnergy = awardSpecialEnergy

-- Bequeme, vorkonfigurierte Varianten für die häufigsten Quellen -- vermeidet, dass jede
-- Aufrufstelle die Balance-Zahlen selbst kennen muss (zentral hier in
-- SPECIAL_ENERGY_GAINS gepflegt).
_G.AwardSpecialEnergyForPunchHit = function(player)
	awardSpecialEnergy(player, SPECIAL_ENERGY_GAINS.PunchHit)
end
_G.AwardSpecialEnergyForComboHit = function(player, comboStep)
	if comboStep == 3 then
		awardSpecialEnergy(player, SPECIAL_ENERGY_GAINS.ThirdComboHit)
	elseif comboStep == 2 then
		awardSpecialEnergy(player, SPECIAL_ENERGY_GAINS.ComboHit)
	else
		awardSpecialEnergy(player, SPECIAL_ENERGY_GAINS.PunchHit)
	end
end
_G.AwardSpecialEnergyForJumpLanding = function(player)
	awardSpecialEnergy(player, SPECIAL_ENERGY_GAINS.JumpLanding)
end
_G.AwardSpecialEnergyForBuildingDamage = function(player, damageAmount)
	awardSpecialEnergy(player, (damageAmount or 0) * SPECIAL_ENERGY_GAINS.BuildingDamagePerHP)
end
_G.AwardSpecialEnergyForBuildingDestroyed = function(player)
	awardSpecialEnergy(player, SPECIAL_ENERGY_GAINS.BuildingDestroyed)
end
-- Absorb ist ein BOOSTER: skaliert mit der tatsächlich absorbierten Menge, aber immer
-- innerhalb von AbsorbMin/AbsorbMax geclampt (auch ein winziger Absorb-Tick gibt spürbar
-- etwas, ein riesiger nicht unbegrenzt viel).
_G.AwardSpecialEnergyForAbsorb = function(player, absorbedAmount)
	local scaled = (absorbedAmount or 0) * SPECIAL_ENERGY_GAINS.AbsorbPerEnergyUnit
	local clamped = math.clamp(scaled, SPECIAL_ENERGY_GAINS.AbsorbMin, SPECIAL_ENERGY_GAINS.AbsorbMax)
	awardSpecialEnergy(player, clamped)
end

-- ===== Energy ausgeben (von SpecialAttackHandler.lua aufgerufen) -- gibt true zurück,
-- falls genug vorhanden war und tatsächlich abgezogen wurde, sonst false (unverändert). =====
local function trySpendSpecialEnergy(player, amount)
	if not player or not player.Parent or not amount then
		return false
	end
	local current = player:GetAttribute("SpecialEnergy") or 0
	if current < amount then
		return false
	end
	player:SetAttribute("SpecialEnergy", current - amount)
	return true
end
_G.TrySpendSpecialEnergy = trySpendSpecialEnergy
_G.GetSpecialEnergyCost = function(attackType)
	return SPECIAL_ENERGY_COSTS[attackType] or 0
end
_G.GetSpecialEnergyMax = function()
	return SPECIAL_ENERGY_MAX
end

print("[Kaiju] SpecialEnergyHandler bereit -- Focus/Area nutzen jetzt Energy statt langer Cooldowns.")