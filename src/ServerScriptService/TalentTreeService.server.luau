-- VERSION: 2026-08-19 #1
-- ServerScript: TalentTreeService
-- Ort in Studio: ServerScriptService
--
-- Verwaltet den Diablo-artigen Talentbaum: Vorstufen-Prüfung, Forschungs-Warteschlange
-- (nur EIN Talent gleichzeitig pro Spieler, läuft über echte Zeit weiter), duale Kosten
-- (Energie + Coins). Verdrahtet alle Kaiju-Effekte (inkl. Trade-off-Nachteile und
-- Synergie-Boni) tatsächlich in die bestehenden Systeme.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local TalentTreeConfig = require(ReplicatedStorage:WaitForChild("TalentTreeConfig"))

local ENERGY_ATTRIBUTE_NAME = {
	Heat = "EnergyHeat",
	Chemical = "EnergyChemical",
	Electric = "EnergyElectric",
	Radiation = "EnergyRadiation",
	Spirit = "EnergySpirit",
}

-- ===== RemoteEvents/Functions =====
local StartResearchEvent = Instance.new("RemoteEvent")
StartResearchEvent.Name = "StartResearchEvent"
StartResearchEvent.Parent = ReplicatedStorage

local CancelResearchEvent = Instance.new("RemoteEvent")
CancelResearchEvent.Name = "CancelResearchEvent"
CancelResearchEvent.Parent = ReplicatedStorage

local ResearchCompleteEvent = Instance.new("RemoteEvent")
ResearchCompleteEvent.Name = "ResearchCompleteEvent"
ResearchCompleteEvent.Parent = ReplicatedStorage

local GetTalentStateFunction = Instance.new("RemoteFunction")
GetTalentStateFunction.Name = "GetTalentStateFunction"
GetTalentStateFunction.Parent = ReplicatedStorage

-- [player] = { Kaiju = { [talentId] = level }, Jaeger = {...}, Ronin = {...} }
local talentLevels = {}
-- [player] = { faction=, talentId=, completesAt=, totalDuration= } oder nil
local activeResearch = {}

local function ensurePlayerTalentState(player)
	if not talentLevels[player] then
		talentLevels[player] = { Kaiju = {}, Jaeger = {}, Ronin = {} }
	end
	return talentLevels[player]
end

local function getTalentLevel(player, factionName, talentId)
	local state = talentLevels[player]
	if not state or not state[factionName] then
		return 0
	end
	return state[factionName][talentId] or 0
end
_G.GetTalentLevel = getTalentLevel

-- Prüft, ob ALLE Vorstufen eines Knotens erfüllt sind.
local function arePrerequisitesMet(player, factionName, talent)
	for _, prereq in ipairs(talent.prerequisites) do
		if getTalentLevel(player, factionName, prereq.id) < prereq.level then
			return false
		end
	end
	return true
end

-- ===== Kaiju-Effekte: summiert JEDEN Knoten, der einen bestimmten Effekt-Schlüssel
-- trägt (egal ob Haupteffekt oder Trade-off-Nachteil eines anderen Knotens). =====
local function getKaijuEffectBonus(player, effectKey)
	local state = talentLevels[player]
	if not state or not state.Kaiju then
		return 0
	end
	local total = 0
	for _, talent in ipairs(TalentTreeConfig.Kaiju) do
		local level = state.Kaiju[talent.id] or 0
		if level > 0 then
			if talent.effectKey == effectKey then
				total += level * talent.effectPerLevel
			end
			if talent.tradeoffEffectKey == effectKey then
				total += level * talent.tradeoffEffectPerLevel
			end
		end
	end
	return total
end

_G.GetTalentBerserkerDamageBonus = function(player)
	return getKaijuEffectBonus(player, "BerserkerDamageBonus") + getKaijuEffectBonus(player, "OverheatDamageBonus")
end
_G.GetTalentBerserkerThresholdPenalty = function(player)
	return getKaijuEffectBonus(player, "BerserkerThresholdPenalty")
end
_G.GetTalentMeltdownThresholdBonus = function(player)
	return getKaijuEffectBonus(player, "MeltdownThresholdBonus")
end
_G.GetTalentMeltdownAttackSpeedBonus = function(player)
	return getKaijuEffectBonus(player, "MeltdownAttackSpeedBonus")
end
-- Wurde vom HeatHandler an drei Stellen gelesen, aber nirgends gesetzt -- die
-- Abkuehlung lief dadurch immer mit Faktor 1.0, das Talent war wirkungslos.
_G.GetTalentHeatCoolingBonus = function(player)
	return getKaijuEffectBonus(player, "HeatCoolingBonus")
end
_G.GetTalentCooldownReduction = function(player)
	return getKaijuEffectBonus(player, "CooldownReduction")
end
_G.GetTalentFocusDamageBonus = function(player)
	return getKaijuEffectBonus(player, "FocusDamageBonus")
end
_G.GetTalentFocusRangePenalty = function(player)
	return getKaijuEffectBonus(player, "FocusRangePenalty")
end
_G.GetTalentComboChainEnabled = function(player)
	return getKaijuEffectBonus(player, "ComboChainEnabled") > 0
end
_G.GetTalentFocusRetargetEnabled = function(player)
	return getKaijuEffectBonus(player, "FocusRetargetEnabled") > 0
end
_G.GetTalentAreaRadiusBonus = function(player)
	return getKaijuEffectBonus(player, "AreaRadiusBonus") + getKaijuEffectBonus(player, "BlastRadiusBonus")
end
_G.GetTalentAreaDamagePenalty = function(player)
	return getKaijuEffectBonus(player, "AreaDamagePenalty")
end
_G.GetTalentCataclysmEnabled = function(player)
	return getKaijuEffectBonus(player, "CataclysmEnabled") > 0
end
_G.GetTalentHeatScaledAreaDamage = function(player)
	return getKaijuEffectBonus(player, "HeatScaledAreaDamage")
end
_G.GetTalentUltimateDamageBonus = function(player)
	return getKaijuEffectBonus(player, "UltimateDamageBonus") + getKaijuEffectBonus(player, "RootDamageBonus")
end

-- ===== Forschung starten =====
StartResearchEvent.OnServerEvent:Connect(function(player, factionName, talentId)
	if type(factionName) ~= "string" or type(talentId) ~= "string" then
		return
	end
	if activeResearch[player] then
		return -- schon etwas in Forschung -- nur eins gleichzeitig
	end

	local talent = TalentTreeConfig.FindTalent(factionName, talentId)
	if not talent then
		return
	end

	local state = ensurePlayerTalentState(player)
	local currentLevel = state[factionName][talentId] or 0
	if currentLevel >= talent.maxLevel then
		return -- schon voll ausgebaut
	end

	if not arePrerequisitesMet(player, factionName, talent) then
		return -- Vorstufen nicht erfüllt
	end

	local nextLevel = currentLevel + 1
	local cost = TalentTreeConfig.GetNodeCost(talent, nextLevel)
	local energyAttribute = ENERGY_ATTRIBUTE_NAME[talent.energyType]
	local currentEnergy = player:GetAttribute(energyAttribute) or 0
	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
	local currentCoins = coinsValue and coinsValue.Value or 0

	if currentEnergy < cost.energyAmount or currentCoins < cost.coinAmount then
		return -- nicht genug Ressourcen
	end

	player:SetAttribute(energyAttribute, currentEnergy - cost.energyAmount)
	if coinsValue and cost.coinAmount > 0 then
		coinsValue.Value = currentCoins - cost.coinAmount
	end

	local now = Workspace:GetServerTimeNow()
	activeResearch[player] = {
		faction = factionName,
		talentId = talentId,
		startedAt = now,
		completesAt = now + talent.researchSeconds,
		totalDuration = talent.researchSeconds,
	}

	StartResearchEvent:FireClient(player, factionName, talentId, now + talent.researchSeconds, talent.researchSeconds)
end)

-- ===== Forschung abbrechen: Ressourcen werden NICHT erstattet =====
CancelResearchEvent.OnServerEvent:Connect(function(player)
	activeResearch[player] = nil
end)

-- ===== Läuft im Hintergrund: prüft, ob eine Forschung fertig ist =====
task.spawn(function()
	while true do
		local now = Workspace:GetServerTimeNow()
		for player, research in pairs(activeResearch) do
			if now >= research.completesAt then
				local state = ensurePlayerTalentState(player)
				state[research.faction][research.talentId] = (state[research.faction][research.talentId] or 0) + 1
				activeResearch[player] = nil

				print(string.format("[Kaiju-Debug] Forschung FERTIG: %s / %s / %s -- neue Stufe %d",
					player.Name, research.faction, research.talentId, state[research.faction][research.talentId]))

				ResearchCompleteEvent:FireClient(player, research.faction, research.talentId, state[research.faction][research.talentId])

				if research.faction == "Kaiju" and _G.RecalculateStrength then
					_G.RecalculateStrength(player)
				end
			end
		end
		task.wait(1)
	end
end)

-- ===== Persistenz: Talent-Stufen + eine evtl. laufende Forschung werden zusammen mit
-- Coins/Energie gespeichert (siehe PlayerSetup.lua, savePlayerData/loadPlayerData) --
-- vorher lagen sie NUR im Arbeitsspeicher und gingen bei jedem Rejoin verloren. =====

-- Liefert den kompletten, speicherbaren Zustand eines Spielers (nur einfache
-- Zahlen/Strings/verschachtelte Tabellen -- DataStore-kompatibel).
_G.GetTalentSaveData = function(player)
	local state = talentLevels[player] or { Kaiju = {}, Jaeger = {}, Ronin = {} }
	local research = activeResearch[player]

	local researchData = nil
	if research then
		-- Gespeichert wird die INVESTIERTE Zeit, nicht der Fertigstellungszeitpunkt.
		-- Vorher stand hier completesAt, ein absoluter Zeitstempel -- damit lief die
		-- Forschung auch waehrend der Abwesenheit weiter. Jetzt zaehlt ausschliesslich
		-- Online-Zeit: der Spieler macht dort weiter, wo er aufgehoert hat.
		local now = Workspace:GetServerTimeNow()
		local remaining = math.max(research.completesAt - now, 0)
		local invested = math.clamp(research.totalDuration - remaining, 0, research.totalDuration)
		researchData = {
			faction = research.faction,
			talentId = research.talentId,
			investedSeconds = invested,
			totalDuration = research.totalDuration,
		}
	end
	return {
		levels = state,
		research = researchData,
	}
end

-- Stellt einen gespeicherten Zustand wieder her. WICHTIG: Die Forschungszeit läuft auf
-- Basis der INVESTIERTEN Zeit: Forschung schreitet nur voran, solange der Spieler
-- online ist. Beim Beitritt wird aus der investierten Zeit die Restzeit gebildet und neu
-- abgezaehlt -- er macht also dort weiter, wo er aufgehoert hat. Alte Staende mit
-- completesAt werden dabei umgerechnet, nicht verworfen.
_G.LoadTalentSaveData = function(player, data)
	if not data then
		return
	end

	talentLevels[player] = data.levels or { Kaiju = {}, Jaeger = {}, Ronin = {} }
	-- Fehlende Fraktions-Einträge (z.B. durch ein späteres Update neu hinzugekommen)
	-- defensiv auffüllen, damit spätere Zugriffe nicht mit nil-Fehlern abbrechen.
	for _, factionName in ipairs({ "Kaiju", "Jaeger", "Ronin" }) do
		if not talentLevels[player][factionName] then
			talentLevels[player][factionName] = {}
		end
	end

	if data.research then
		local now = Workspace:GetServerTimeNow()
		local totalDuration = data.research.totalDuration or 0

		-- investedSeconds ist das neue Feld. Alte Staende tragen stattdessen completesAt
		-- (absoluter Zeitstempel) -- daraus laesst sich die investierte Zeit herleiten,
		-- damit niemand seinen Fortschritt verliert.
		local invested = data.research.investedSeconds
		if type(invested) ~= "number" then
			local remaining = math.max((data.research.completesAt or now) - now, 0)
			invested = math.clamp(totalDuration - remaining, 0, totalDuration)
		end
		invested = math.clamp(invested, 0, totalDuration)

		if invested >= totalDuration and totalDuration > 0 then
			-- Fertig geforscht -- Stufe gutschreiben statt erneut warten zu lassen.
			local state = talentLevels[player]
			state[data.research.faction][data.research.talentId] =
				(state[data.research.faction][data.research.talentId] or 0) + 1
		else
			-- Weiterlaufen lassen: die RESTZEIT wird ab jetzt neu abgezaehlt. Der intern
			-- gefuehrte completesAt bleibt damit die guenstige Form fuer die Tick-Schleife
			-- und den Client, waehrend gespeichert weiterhin die investierte Zeit wird.
			activeResearch[player] = {
				faction = data.research.faction,
				talentId = data.research.talentId,
				startedAt = now,
				completesAt = now + (totalDuration - invested),
				totalDuration = totalDuration,
			}
		end
	end
end

GetTalentStateFunction.OnServerInvoke = function(player)
	local state = ensurePlayerTalentState(player)
	local energyValues = {}
	for energyType, attributeName in pairs(ENERGY_ATTRIBUTE_NAME) do
		energyValues[energyType] = player:GetAttribute(attributeName) or 0
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = (leaderstats and leaderstats:FindFirstChild("Coins") and leaderstats.Coins.Value) or 0

	local research = activeResearch[player]
	local researchInfo = nil
	if research then
		researchInfo = {
			faction = research.faction,
			talentId = research.talentId,
			completesAt = research.completesAt,
			totalDuration = research.totalDuration,
		}
	end

	return {
		levels = state,
		energy = energyValues,
		coins = coins,
		activeFaction = player:GetAttribute("Faction") or "Kaiju",
		research = researchInfo,
	}
end

-- ===== Debug-Reset: löscht alle Talent-Stufen + eine evtl. laufende Forschung. Vom
-- normalen Spielerdaten-Reset (PlayerSetup.lua, ResetPlayerDataEvent) aufgerufen. =====
_G.ResetPlayerTalents = function(player)
	talentLevels[player] = { Kaiju = {}, Jaeger = {}, Ronin = {} }
	activeResearch[player] = nil
	-- Client informieren, damit die Forschungs-Anzeige (Panel + HUD-Widget) sofort
	-- verschwindet, statt bis zur ursprünglich geplanten Fertigstellungszeit weiterzulaufen.
	ResearchCompleteEvent:FireClient(player, "Kaiju", "", 0)
end

Players.PlayerRemoving:Connect(function(player)
	-- WICHTIG -- task.defer, NICHT sofort aufräumen: PlayerSetup speichert ebenfalls in
	-- PlayerRemoving und holt sich den Talentstand dort über _G.GetTalentSaveData.
	-- Roblox ruft die Handler in der Reihenfolge ihrer VERBINDUNG auf, und Scripts in
	-- ServerScriptService starten in unbestimmter Reihenfolge -- lief dieses Aufräumen
	-- zuerst, las das Speichern eine bereits geleerte Tabelle und der komplette
	-- Talentfortschritt ging verloren. Ohne Fehlermeldung, und je nach Startreihenfolge
	-- mal so und mal so.
	--
	-- task.defer schiebt das Aufräumen hinter alle unmittelbar laufenden Handler. Der
	-- Speicherstand wird dort synchron eingesammelt, bevor der DataStore-Aufruf
	-- überhaupt beginnt -- danach darf geleert werden.
	task.defer(function()
		talentLevels[player] = nil
		activeResearch[player] = nil
	end)
end)