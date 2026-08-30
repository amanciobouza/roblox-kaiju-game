-- VERSION: 2026-08-21 #3
-- Ort in Studio: ServerScriptService
-- Fundament für das erweiterte Energie-/Fraktionssystem:
--   1) 5 permanente Energie-Ressourcen (Wärme/Chemie/Elektrizität/Strahlung/Spirit) --
--      SEPARAT von XP (das treibt weiterhin nur das Level, siehe PlayerSetup.lua) und
--      SEPARAT vom Heat-Überhitzungs-Meter (siehe HeatHandler.lua) -- Namenskollision
--      im Konzept ("Wärme"-Energie vs. "Heat"-Überhitzung) bewusst durch eigene
--      Attribut-Namen ("EnergyHeat" etc.) vermieden.
--   2) Fraktionswahl (Kaiju/Jaeger/Ronin) -- aktuell nur Kaiju spielbar, Jaeger/Ronin
--      sind als Datenmodell vorbereitet, aber ohne eigenes Moveset (kommt später).
--   3) Rotierende Welt-Events alle 15 Minuten, die einzelne Energie-Typen verstärken.
--   4) Strahlung (Radiation) ist bewusst ANDERS als die anderen 4 Energien: sehr selten
--      (Seltenheit steigt mit der Stadt-/Level-Stufe des Gebäudes), NICHT für normale
--      Talente gedacht, sondern für Evolution/Mutation -- siehe rundenbasiertes
--      Mutations-System weiter unten. "Nuklear" wurde bewusst zu "Strahlung" (Radiation)
--      umbenannt, um die begriffliche Überschneidung mit Kernenergie/Elektrizität zu
--      vermeiden (siehe Konzept-Dokument).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

-- ===== RemoteEvents =====
local SelectFactionEvent = Instance.new("RemoteEvent")
SelectFactionEvent.Name = "SelectFactionEvent"
SelectFactionEvent.Parent = ReplicatedStorage

local WorldEventChangedEvent = Instance.new("RemoteEvent")
WorldEventChangedEvent.Name = "WorldEventChangedEvent"
WorldEventChangedEvent.Parent = ReplicatedStorage

-- Vorankündigung: feuert 10s VOR der eigentlichen Enthüllung (Banner/Effekte) -- nur der
-- Musik-Wechsel, damit Spieler am Song schon erahnen können, was kommt, bevor es sichtbar
-- bestätigt wird.
local WorldEventPreRollEvent = Instance.new("RemoteEvent")
WorldEventPreRollEvent.Name = "WorldEventPreRollEvent"
WorldEventPreRollEvent.Parent = ReplicatedStorage

local EnergyGainedEvent = Instance.new("RemoteEvent") -- fürs HUD-Feedback (fliegende Icons)
EnergyGainedEvent.Name = "EnergyGainedEvent"
EnergyGainedEvent.Parent = ReplicatedStorage

local MutationTriggeredEvent = Instance.new("RemoteEvent") -- fürs HUD-Feedback (Mutation ausgelöst)
MutationTriggeredEvent.Name = "MutationTriggeredEvent"
MutationTriggeredEvent.Parent = ReplicatedStorage

-- ===== Energie-Typen =====
local ENERGY_TYPES = { "Heat", "Chemical", "Electric", "Radiation", "Spirit" }
local ENERGY_ATTRIBUTE_NAME = {
	Heat = "EnergyHeat",
	Chemical = "EnergyChemical",
	Electric = "EnergyElectric",
	Radiation = "EnergyRadiation",
	Spirit = "EnergySpirit",
}

-- ===== Fraktionen =====
local VALID_FACTIONS = { Kaiju = true, Jaeger = true, Ronin = true }
local DEFAULT_FACTION = "Kaiju" -- einzige aktuell spielbare Fraktion

SelectFactionEvent.OnServerEvent:Connect(function(player, faction)
	if not VALID_FACTIONS[faction] then
		return
	end
	player:SetAttribute("SelectedFaction", faction)

	-- Jaeger/Ronin sind jetzt spielbar (vorläufig mit Kaijus Moveset -- eigene
	-- Fähigkeiten kommen später) -- Voraussetzung: Freischalt-Bedingungen erfüllt
	-- (siehe FactionUnlockService.lua: Level + Energie + Meilenstein).
	if faction == "Kaiju" then
		player:SetAttribute("Faction", faction)
	elseif _G.GetFactionUnlockStatus then
		local unlocked = _G.GetFactionUnlockStatus(player, faction)
		if unlocked then
			player:SetAttribute("Faction", faction)
		end
	end
end)

-- ===== Debug-Werkzeug: Fraktion sofort wechseln, OHNE Freischalt-Bedingungen zu prüfen
-- -- nur wirksam mit aktivem Debug-Modus (siehe DebugPanelClient.lua). =====
local DebugSetFactionEvent = Instance.new("RemoteEvent")
DebugSetFactionEvent.Name = "DebugSetFactionEvent"
DebugSetFactionEvent.Parent = ReplicatedStorage

DebugSetFactionEvent.OnServerEvent:Connect(function(player, faction)
	if not player:GetAttribute("DebugMode") then
		return
	end
	if not VALID_FACTIONS[faction] then
		return
	end
	player:SetAttribute("SelectedFaction", faction)
	player:SetAttribute("Faction", faction)
end)

-- ===== Welt-Events =====
-- Alle 15 Minuten wechselt zufällig ein Event, das einen Energie-Typ verstärkt.
local WORLD_EVENT_INTERVAL = 15 * 60
local WORLD_EVENTS = {
	{ name = "Thunderstorm", emoji = "⚡", energyType = "Electric", multiplier = 3, tintColor = Color3.fromRGB(150, 180, 255), brightness = -0.15, musicId = "rbxassetid://81829814932927" },
	{ name = "Reactor Meltdown", emoji = "☢️", energyType = "Radiation", multiplier = 5, radiationChanceMultiplier = 8, tintColor = Color3.fromRGB(120, 255, 140), brightness = -0.05, musicId = "rbxassetid://106359235292657" },
	{ name = "Heat Wave", emoji = "🔥", energyType = "Heat", multiplier = 2, tintColor = Color3.fromRGB(255, 170, 110), brightness = 0.05, musicId = "rbxassetid://109249341898497" },
	{ name = "Chemical Accident", emoji = "🧪", energyType = "Chemical", multiplier = 2, tintColor = Color3.fromRGB(255, 140, 220), brightness = -0.05, musicId = "rbxassetid://84081855470885" },
	{ name = "Ancient Shrine", emoji = "🌿", energyType = "Spirit", multiplier = 4, tintColor = Color3.fromRGB(255, 220, 130), brightness = 0.08, musicId = "rbxassetid://122412242639201" },
}

local currentWorldEvent = nil -- nil = kein aktives Event, normale Werte

-- ===== Atmosphäre/Licht passend zum aktiven Event =====
-- Serverseitig auf Lighting angewendet (Lighting ist ein geteilter Service -- Änderungen
-- replizieren automatisch zu allen Clients, kein eigenes Remote nötig). Sanfter
-- Farbstich per ColorCorrectionEffect statt harter Umfärbung, damit die Spielwelt noch
-- gut erkennbar bleibt.
local ATMOSPHERE_TWEEN_TIME = 2.5

local function getOrCreateAtmosphereEffect()
	local effect = Lighting:FindFirstChild("WorldEventColorCorrection")
	if not effect then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "WorldEventColorCorrection"
		effect.Parent = Lighting
	end
	return effect
end

local function applyAtmosphereForEvent(event)
	local effect = getOrCreateAtmosphereEffect()
	local targetTint = (event and event.tintColor) or Color3.new(1, 1, 1)
	local targetBrightness = (event and event.brightness) or 0

	TweenService:Create(effect, TweenInfo.new(ATMOSPHERE_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		TintColor = targetTint,
		Brightness = targetBrightness,
	}):Play()
end

-- Für den HUD-Countdown: Zeitpunkt (Workspace:GetServerTimeNow()-Basis) des NÄCHSTEN
-- Würfelwurfs -- ob gerade ein Event läuft oder nicht, der nächste Wurf entscheidet so
-- oder so, ob/wann das aktuelle Event endet UND was als Nächstes kommt. Deshalb reicht
-- EIN Zeitstempel für beide Anzeigen ("Event endet in..." / "Nächstes Event in...").
local NextWorldEventRollTime = Instance.new("NumberValue")
NextWorldEventRollTime.Name = "NextWorldEventRollTime"
NextWorldEventRollTime.Parent = ReplicatedStorage

local WORLD_EVENT_PREROLL_LEAD = 10 -- Sekunden Vorlauf: Musik wechselt schon, bevor das Event sichtbar bestätigt wird

local pendingTimerThread = nil
local applyWorldEvent -- Vorwärtsdeklarationen, da sich die Funktionen gegenseitig referenzieren
local preRollWorldEvent
local scheduleNextRoll

scheduleNextRoll = function()
	if pendingTimerThread then
		task.cancel(pendingTimerThread)
	end
	NextWorldEventRollTime.Value = Workspace:GetServerTimeNow() + WORLD_EVENT_INTERVAL
	pendingTimerThread = task.delay(WORLD_EVENT_INTERVAL - WORLD_EVENT_PREROLL_LEAD, function()
		preRollWorldEvent()
	end)
end

-- Phase 1 (T-10s): Würfelergebnis steht schon fest, aber nur die MUSIK wird verraten --
-- Banner/Multiplikator/Atmosphäre kommen erst 10s später in Phase 2. Kein Fade-In: der
-- Song setzt sofort in voller Lautstärke ein, damit der Wechsel klar wahrnehmbar ist.
preRollWorldEvent = function()
	local rolledEvent
	if math.random() < 0.6 then
		rolledEvent = nil
	else
		rolledEvent = WORLD_EVENTS[math.random(1, #WORLD_EVENTS)]
	end
	WorldEventPreRollEvent:FireAllClients(rolledEvent and rolledEvent.musicId or nil)
	task.delay(WORLD_EVENT_PREROLL_LEAD, function()
		applyWorldEvent(rolledEvent)
	end)
end

-- Phase 2 (T=0): das vorher gewürfelte Event wird sichtbar/spielerisch wirksam -- Banner,
-- Multiplikator, Atmosphäre-Tönung.
applyWorldEvent = function(rolledEvent)
	-- Falls bereits ein anderes Event lief: das wird hier einfach durch das neue ersetzt
	-- (currentWorldEvent wird überschrieben) -- kein separates "Stoppen" nötig, die
	-- Atmosphäre blendet direkt von der alten zur neuen Tönung über.
	currentWorldEvent = rolledEvent
	applyAtmosphereForEvent(currentWorldEvent)
	WorldEventChangedEvent:FireAllClients(currentWorldEvent)
	scheduleNextRoll() -- setzt auch den Countdown-Zeitpunkt für den HUD neu
end

-- Debug-Werkzeug: löst sofort einen neuen Würfelwurf aus (gleiche Wahrscheinlichkeiten
-- wie der reguläre 15-Minuten-Timer, inklusive 60%-Chance auf "kein Event"). Nur wirksam,
-- wenn der Spieler seinen eigenen Debug-Modus aktiviert hat. Bewusst OHNE die 10s-
-- Vorankündigungsphase (Debug soll sofort das Ergebnis zeigen, nicht erst warten).
-- Setzt den regulären Timer korrekt zurück (nächster Wurf dann wieder volle 15 Minuten
-- später, nicht zum alten geplanten Zeitpunkt).
local DebugRollWorldEventEvent = Instance.new("RemoteEvent")
DebugRollWorldEventEvent.Name = "DebugRollWorldEventEvent"
DebugRollWorldEventEvent.Parent = ReplicatedStorage
DebugRollWorldEventEvent.OnServerEvent:Connect(function(player)
	if not player:GetAttribute("DebugMode") then
		return
	end
	-- Laufenden regulären Timer abbrechen, damit er nicht kurz nach dem Debug-Wurf
	-- nochmal parallel feuert -- preRollWorldEvent() plant über applyWorldEvent() am Ende
	-- automatisch wieder einen neuen regulären Zyklus.
	if pendingTimerThread then
		task.cancel(pendingTimerThread)
		pendingTimerThread = nil
	end
	NextWorldEventRollTime.Value = Workspace:GetServerTimeNow() + WORLD_EVENT_PREROLL_LEAD
	preRollWorldEvent() -- exakt derselbe Ablauf (10s Vorlauf, Musik zuerst, dann Enthüllung) wie beim echten Timer
end)

scheduleNextRoll() -- erster Timer-Start

-- Für später beitretende Spieler: aktuelles Event direkt mitteilen
Players.PlayerAdded:Connect(function(player)
	if currentWorldEvent then
		WorldEventChangedEvent:FireClient(player, currentWorldEvent)
	end
end)

local function getWorldEventMultiplier(energyType)
	if currentWorldEvent and currentWorldEvent.energyType == energyType then
		return currentWorldEvent.multiplier
	end
	return 1
end
_G.GetWorldEventMultiplier = getWorldEventMultiplier

-- "Heavy Rain"-artiger Spezialfall (Wassertürme kühlen stärker) würde hier andocken,
-- aktuell nicht als eigenes Event geführt, um die Logik einfach zu halten -- kann bei
-- Bedarf ergänzt werden.

-- ===== Strahlung: Seltenheits-Gate nach Stadt-/Level-Stufe =====
-- Selbst wenn ein Gebäude mit "EnergyType"="Radiation" markiert ist, wird Strahlung nur
-- MANCHMAL tatsächlich vergeben -- je nach Stufe des Gebäudes (grob an dessen MaxHealth
-- abgeleitet, dieselbe Logik wie die Sammel-Effizienz in EnergyCollectionHandler.lua).
-- Ohne Erfolg im Wurf gibt's stattdessen normale Wärme-Energie, damit der Spieler trotzdem
-- etwas bekommt. Während "Reactor Meltdown" wird die Chance zusätzlich vervielfacht.
local RADIATION_CHANCE_BY_TIER = {
	[1] = 0, -- Village (Level 0-9)
	[2] = 0.001, -- SmallTown (Level 10-19)
	[3] = 0.005, -- City (Level 20-29)
	[4] = 0.02, -- Metropolis (Level 30-39)
	[5] = 0.05, -- Megacity (Level 40-49)
}

local function getTierFromMaxHealth(maxHealth)
	local impliedLevel = (_G.GetImpliedLevelFromHP and _G.GetImpliedLevelFromHP(maxHealth)) or 0
	if impliedLevel < 10 then
		return 1
	elseif impliedLevel < 20 then
		return 2
	elseif impliedLevel < 30 then
		return 3
	elseif impliedLevel < 40 then
		return 4
	end
	return 5
end

-- Von EnergyCollectionHandler.lua aufgerufen, um VOR der eigentlichen Vergabe zu
-- entscheiden, ob diesmal Strahlung tatsächlich durchkommt.
_G.RollForRadiation = function(maxHealth)
	local tier = getTierFromMaxHealth(maxHealth)
	local chance = RADIATION_CHANCE_BY_TIER[tier] or 0
	if currentWorldEvent and currentWorldEvent.energyType == "Radiation" and currentWorldEvent.radiationChanceMultiplier then
		chance = chance * currentWorldEvent.radiationChanceMultiplier
	end
	return math.random() < chance
end

-- ===== Rundenbasiertes Mutations-System =====
-- Sammelt der Spieler innerhalb EINER Session genug Strahlung, wird eine zufällige
-- Mutation ausgelöst -- gilt nur für die aktuelle Session (setzt sich beim nächsten
-- Betreten zurück). Aktuell nur für Kaiju ausimplementiert.
local MUTATION_THRESHOLD = 100 -- Strahlung in dieser Session nötig, bis eine Mutation ausgelöst wird
local KAIJU_MUTATIONS = {
	{
		key = "SteadyCore",
		label = "Steady Core -- Heat steigt 30% langsamer",
		apply = function(player)
			player:SetAttribute("MutationHeatGainMultiplier", 0.7)
		end,
	},
	{
		key = "OverheatBruiser",
		label = "Overheat Bruiser -- Heat steigt 30% schneller, +20% Schaden",
		apply = function(player)
			player:SetAttribute("MutationHeatGainMultiplier", 1.3)
			player:SetAttribute("MutationDamageMultiplier", 1.2)
		end,
	},
	{
		key = "ShockwaveJump",
		label = "Shockwave Jump -- Sprünge erzeugen zusätzliche Flächenwellen",
		apply = function(player)
			player:SetAttribute("MutationShockwaveJump", true)
		end,
	},
	{
		key = "RadiantPlates",
		label = "Radiant Plates -- Rückenplatten glühen deutlich stärker",
		apply = function(player)
			player:SetAttribute("MutationRadiantPlates", true)
		end,
	},
	{
		key = "WideBreath",
		label = "Wide Breath -- Fokus-Schaden +15%",
		apply = function(player)
			player:SetAttribute("MutationFocusDamageMultiplier", 1.15)
		end,
	},
}

local radiationThisSession = {} -- [player] = number

local function tryTriggerMutation(player)
	if player:GetAttribute("MutationActive") and player:GetAttribute("MutationActive") ~= "" then
		return -- pro Session nur eine Mutation
	end
	local faction = player:GetAttribute("Faction") or DEFAULT_FACTION
	if faction ~= "Kaiju" then
		return -- Jaeger/Ronin-Mutationen noch nicht implementiert
	end

	local mutation = KAIJU_MUTATIONS[math.random(1, #KAIJU_MUTATIONS)]
	mutation.apply(player)
	player:SetAttribute("MutationActive", mutation.key)
	MutationTriggeredEvent:FireClient(player, mutation.label)
end

-- ===== Energie vergeben =====
-- Von EnergyCollectionHandler.lua (Feuer-Absorption) und HouseHandler.lua (besondere
-- Gebäude) aufgerufen. Wendet automatisch den Welt-Event-Multiplikator an.
local function grantTypedEnergy(player, energyType, amount)
	if not ENERGY_ATTRIBUTE_NAME[energyType] or not amount or amount <= 0 then
		return
	end
	local multiplier = getWorldEventMultiplier(energyType)
	local finalAmount = amount * multiplier
	local attributeName = ENERGY_ATTRIBUTE_NAME[energyType]
	player:SetAttribute(attributeName, (player:GetAttribute(attributeName) or 0) + finalAmount)

	-- Lifetime-Gesamtmenge (unabhängig vom aktuellen, ausgebbaren Bestand -- sinkt NICHT,
	-- wenn Energie z.B. im Talentbaum ausgegeben wird) -- wird für die Fraktions-
	-- Freischaltung gebraucht (siehe FactionUnlockService.lua).
	local lifetimeAttributeName = "Lifetime" .. attributeName
	player:SetAttribute(lifetimeAttributeName, (player:GetAttribute(lifetimeAttributeName) or 0) + finalAmount)

	-- Kein EnergyGainedEvent:FireClient() mehr -- die Energie-Icon-Leiste wurde aus dem
	-- HUD entfernt (siehe EnergyTypesClient.lua), kein Client hört diesem Event mehr zu.
	-- Ohne diese Zeile würde Roblox nach genug Aufrufen "Remote event invocation queue
	-- exhausted" warnen, da die Events nirgends ankommen und sich stauen.

	if energyType == "Radiation" then
		radiationThisSession[player] = (radiationThisSession[player] or 0) + finalAmount
		if radiationThisSession[player] >= MUTATION_THRESHOLD then
			tryTriggerMutation(player)
		end
	end

	-- Fraktions-Effekte: aktuell nur für Kaiju ausimplementiert (einzige spielbare
	-- Fraktion). Jaeger/Ronin-Zweige sind vorbereitet, greifen aber erst, sobald diese
	-- Fraktionen ein eigenes Moveset/eigene Systeme haben.
	local faction = player:GetAttribute("Faction") or DEFAULT_FACTION
	if faction == "Kaiju" then
		if energyType == "Chemical" then
			-- Chemie verlängert den Berserk-Modus (Heat-System, siehe HeatHandler.lua)
			if _G.ExtendBerserk then
				_G.ExtendBerserk(player, finalAmount * 0.05) -- grobe Umrechnung: 20 Chemie ≈ 1s Verlängerung
			end
		elseif energyType == "Electric" then
			-- Elektrizität: kurzzeitig schnellere Angriffe/Cooldowns
			if _G.GrantElectricBoost then
				_G.GrantElectricBoost(player, finalAmount)
			end
		end
		-- Radiation läuft NICHT mehr über einen sofortigen Kampf-Boost -- ihre Wirkung ist
		-- ausschließlich das Mutations-System oben. Spirit hat für Kaiju laut Konzept
		-- "kaum Nutzen" -- bewusst kein Effekt.
	end
end
_G.GrantTypedEnergy = grantTypedEnergy

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("Faction", DEFAULT_FACTION)
	player:SetAttribute("SelectedFaction", DEFAULT_FACTION)
	for _, energyType in ipairs(ENERGY_TYPES) do
		player:SetAttribute(ENERGY_ATTRIBUTE_NAME[energyType], 0)
	end
	radiationThisSession[player] = 0
	player:SetAttribute("MutationActive", "")
	player:SetAttribute("MutationHeatGainMultiplier", 1.0)
	player:SetAttribute("MutationDamageMultiplier", 1.0)
	player:SetAttribute("MutationFocusDamageMultiplier", 1.0)
	player:SetAttribute("MutationShockwaveJump", false)
	player:SetAttribute("MutationRadiantPlates", false)
end)

Players.PlayerRemoving:Connect(function(player)
	radiationThisSession[player] = nil
end)