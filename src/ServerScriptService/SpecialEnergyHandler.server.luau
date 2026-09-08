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

-- WICHTIG (Village-Spezifikation, "Combat Energy"): Energie entsteht durch KAMPFAKTIONEN,
-- nicht pro getroffenem Ziel. Ein Sprung, der fünf Gebäude trifft, zählt als EINE Aktion.
-- Deshalb gibt es hier keinen Posten mehr, der mit dem verursachten Schaden oder der Zahl
-- der Ziele mitwächst -- der frühere BuildingDamagePerHP tat genau das (er hing an
-- DamageHouse und feuerte damit einmal je Gebäude UND einmal je Fokus-Tick).
local SPECIAL_ENERGY_GAINS = {
	PunchHit = 1,
	ComboHit = 1, -- normaler Combo-Treffer (Schritt 2)
	ThirdComboHit = 3, -- Finisher (Schritt 3) -- bewusst höher, motiviert den Combo abzuschliessen
	JumpLanding = 2,
	BuildingDestroyed = 3,
}

-- Eine "normale Kampfaktion" im Sinne der Spezifikation ist ein Schlag. Über einen
-- vollständigen Dreier-Combo gemittelt sind das (1 + 1 + 3) / 3 Energy.
local AVERAGE_GAIN_PER_COMBAT_ACTION = (SPECIAL_ENERGY_GAINS.PunchHit
	+ SPECIAL_ENERGY_GAINS.ComboHit
	+ SPECIAL_ENERGY_GAINS.ThirdComboHit) / 3

-- Die Spezifikation setzt den Preis eines Specials auf zehn normale Kampfaktionen -- und
-- zwar für BEIDE gleich. Nur so hängt die Wahl zwischen Fokus und Fläche an der Zahl der
-- Ziele (Schnittpunkt bei drei, siehe AREA_DAMAGE_MULTIPLIER in SpecialAttackHandler)
-- statt am Preis.
local COMBAT_ACTIONS_PER_SPECIAL = 10
local SPECIAL_COST = math.floor(COMBAT_ACTIONS_PER_SPECIAL * AVERAGE_GAIN_PER_COMBAT_ACTION + 0.5)

local SPECIAL_ENERGY_COSTS = {
	Focus = SPECIAL_COST,
	Area = SPECIAL_COST,
}

-- ===== Deckel für den Absorb-Beitrag =====
-- Absorbieren steuert weiterhin Combat Energy bei, aber gedeckelt -- sonst finanziert
-- Danebenstehen die Specials schneller als Kämpfen.
--
-- Genau das war der Fall: die Vergabe hängt am Absorb-Takt JE BRENNENDEM GEBÄUDE. Bei
-- sieben gleichzeitig brennenden Gebäuden zahlte ein einziger Takt 7 x AbsorbMin = 42
-- Energy, also mehr als zwei ganze Specials, fürs Stehenbleiben.
--
-- Der Deckel wirkt deshalb über ALLE gleichzeitig absorbierten Gebäude ZUSAMMEN, als
-- Rate: höchstens ABSORB_ENERGY_PER_SECOND pro Sekunde. Zum Vergleich -- Kämpfen liefert
-- bei 0,8 s je Schlag rund 2,1 Energy pro Sekunde. Der Absorb-Beitrag liegt damit bei
-- etwa einem Viertel davon: spürbar, aber nie die schnellere Art, ein Special zu bezahlen.
local ABSORB_ENERGY_PER_SECOND = 0.5
local ABSORB_PER_ENERGY_UNIT = 0.25 -- so viel WÜRDE ein Absorb-Tick geben; der Deckel oben schneidet ab
local ABSORB_BURST_SECONDS = 4 -- so viele Sekunden Rate darf sich ansparen, damit kurze Absorb-Stösse nicht leer ausgehen

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

-- Nachweis beim Serverstart, dass die Herleitung oben tatsächlich greift: beide Specials
-- müssen denselben Preis tragen, und der muss zehn Kampfaktionen entsprechen.
print(string.format(
	"[Kaiju Debug] Special Energy: Fokus %d, Flaeche %d -- %d Kampfaktionen a %.2f. Absorb gedeckelt auf %.2f/s (Kaempfen liefert ca. 2.1/s).",
	SPECIAL_ENERGY_COSTS.Focus,
	SPECIAL_ENERGY_COSTS.Area,
	COMBAT_ACTIONS_PER_SPECIAL,
	AVERAGE_GAIN_PER_COMBAT_ACTION,
	ABSORB_ENERGY_PER_SECOND
))

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
-- ENTFÄLLT: _G.AwardSpecialEnergyForBuildingDamage. Die Funktion hing an DamageHouse und
-- vergab damit Energie je Gebäude und je Fokus-Tick -- also genau die Vervielfachung pro
-- Ziel, die die Spezifikation ausschliesst. Der Aufruf in HouseHandler ist mit entfernt.
_G.AwardSpecialEnergyForBuildingDestroyed = function(player)
	awardSpecialEnergy(player, SPECIAL_ENERGY_GAINS.BuildingDestroyed)
end

-- Absorb-Beitrag mit gemeinsamem Deckel über alle Gebäude (siehe die Herleitung oben bei
-- ABSORB_ENERGY_PER_SECOND). Umgesetzt als Eimer, der mit der erlaubten Rate nachläuft:
-- was mehrere Gebäude im selben Takt zusammen anfordern, wird an dem gemessen, was seit
-- dem letzten Mal nachgelaufen ist -- und der Rest fällt weg.
local absorbBudget = {} -- [player] = { amount, lastRefillAt }

Players.PlayerRemoving:Connect(function(player)
	absorbBudget[player] = nil
end)

_G.AwardSpecialEnergyForAbsorb = function(player, absorbedAmount)
	if not player or not player.Parent then
		return
	end

	local now = os.clock()
	local bucket = absorbBudget[player]
	if not bucket then
		bucket = { amount = ABSORB_ENERGY_PER_SECOND * ABSORB_BURST_SECONDS, lastRefillAt = now }
		absorbBudget[player] = bucket
	end

	bucket.amount = math.min(
		bucket.amount + (now - bucket.lastRefillAt) * ABSORB_ENERGY_PER_SECOND,
		ABSORB_ENERGY_PER_SECOND * ABSORB_BURST_SECONDS
	)
	bucket.lastRefillAt = now

	local wanted = (absorbedAmount or 0) * ABSORB_PER_ENERGY_UNIT
	local granted = math.min(wanted, bucket.amount)
	if granted <= 0 then
		return
	end

	bucket.amount -= granted
	awardSpecialEnergy(player, granted)
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