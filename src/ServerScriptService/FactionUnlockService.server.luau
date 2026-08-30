-- ServerScript: FactionUnlockService
-- Ort in Studio: ServerScriptService
--
-- Prüft die Freischalt-Bedingungen für Jaeger/Ronin (Kaiju ist von Anfang an frei) und
-- liefert dem Client den aktuellen Fortschritt fürs Fraktions-Panel. Kombination aus drei
-- Kriterien pro Fraktion: Level-Schwelle + Energie-Meisterschaft (lifetime) + Meilenstein.
--
-- WICHTIG: Blockiert NICHT die eigentliche Fraktions-AUSWAHL selbst (das bleibt weiterhin
-- über SelectFactionEvent in EnergyTypesHandler.lua möglich -- Spieler dürfen ihre
-- Wunsch-Fraktion schon vorab markieren) -- sondern nur, ob "Faction" (die tatsächlich
-- AKTIVE, spielbare Fraktion) darauf wechseln darf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FACTION_REQUIREMENTS = {
	Jaeger = {
		level = 20,
		energyType = "Electric",
		energyAmount = 500,
		milestoneAttribute = "FireEnginesDestroyed",
		milestoneTarget = 1,
		milestoneLabel = "Feuerwehrauto zerstört (beweist: Alert Level 2 erlebt)",
	},
	Ronin = {
		level = 30,
		energyType = "Spirit",
		energyAmount = 300,
		milestoneAttribute = "JumpKills",
		milestoneTarget = 30,
		milestoneLabel = "Gebäude per Sprungangriff zerstört",
	},
}

local ENERGY_ATTRIBUTE_NAME = {
	Heat = "EnergyHeat",
	Chemical = "EnergyChemical",
	Electric = "EnergyElectric",
	Radiation = "EnergyRadiation",
	Spirit = "EnergySpirit",
}

-- Gibt für eine Fraktion zurück: ist sie freigeschaltet (bool), plus einen Fortschritts-
-- Tisch mit den drei Einzelkriterien (für die Anzeige im Fraktions-Panel).
local function getFactionUnlockStatus(player, factionName)
	if factionName == "Kaiju" then
		return true, nil -- von Anfang an frei, kein Fortschritt nötig
	end

	local requirements = FACTION_REQUIREMENTS[factionName]
	if not requirements then
		return false, nil
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local currentLevel = (leaderstats and leaderstats:FindFirstChild("Level") and leaderstats.Level.Value) or 0

	local lifetimeAttributeName = "Lifetime" .. ENERGY_ATTRIBUTE_NAME[requirements.energyType]
	local currentEnergy = player:GetAttribute(lifetimeAttributeName) or 0

	local currentMilestone = player:GetAttribute(requirements.milestoneAttribute) or 0

	local levelDone = currentLevel >= requirements.level
	local energyDone = currentEnergy >= requirements.energyAmount
	local milestoneDone = currentMilestone >= requirements.milestoneTarget

	local progress = {
		level = { current = currentLevel, target = requirements.level, done = levelDone },
		energy = { energyType = requirements.energyType, current = math.floor(currentEnergy), target = requirements.energyAmount, done = energyDone },
		milestone = { current = currentMilestone, target = requirements.milestoneTarget, done = milestoneDone, label = requirements.milestoneLabel },
	}

	return levelDone and energyDone and milestoneDone, progress
end
_G.GetFactionUnlockStatus = getFactionUnlockStatus

-- ===== RemoteFunction: Client fragt den Fortschritt für ALLE Fraktionen gleichzeitig ab
-- (fürs Fraktions-Panel) =====
local GetFactionProgressFunction = Instance.new("RemoteFunction")
GetFactionProgressFunction.Name = "GetFactionProgressFunction"
GetFactionProgressFunction.Parent = ReplicatedStorage

GetFactionProgressFunction.OnServerInvoke = function(player)
	local result = {}
	for _, factionName in ipairs({ "Kaiju", "Jaeger", "Ronin" }) do
		local unlocked, progress = getFactionUnlockStatus(player, factionName)
		result[factionName] = { unlocked = unlocked, progress = progress }
	end
	return result
end

-- ===== Freischaltung tatsächlich DURCHSETZEN =====
-- Sobald Jaeger/Ronin ein eigenes Moveset bekommen und "Faction" für sie umgestellt
-- werden soll (aktuell macht EnergyTypesHandler.lua das nur für Kaiju), muss der DANN
-- geschriebene Aktivierungs-Code VORHER _G.GetFactionUnlockStatus(player, factionName)
-- prüfen -- dieser Dienst stellt dafür schon die zentrale, wiederverwendbare Prüf-
-- Funktion bereit, damit an dieser Stelle später nichts dupliziert werden muss.