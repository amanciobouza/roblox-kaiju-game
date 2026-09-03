-- VERSION: 2026-08-19 #1
-- ModuleScript: TalentTreeConfig
-- Ort in Studio: ReplicatedStorage
--
-- Diablo-artiger Talentbaum, GETRENNT pro Fraktion (Kaiju/Jaeger/Ronin). Jeder Baum hat
-- dieselbe Grundform: ein Start-Knoten, drei divergierende Zweige (je 3 Stufen), ein
-- Cross-Zweig-Synergie-Knoten (braucht Punkte in ZWEI Zweigen) und ein gemeinsamer
-- Ultimate-Knoten, der alle drei Zweige voraussetzt.
--
-- Ersetzt sowohl das alte, einfache Talent-System (5 Talente, 1 pro Energie-Typ) ALS
-- AUCH das separate Evolution-Punkte-System (EvolutionHandler.lua) -- beide waren
-- strukturell dasselbe (Punkte gegen Stufen-Boni), jetzt an einer Stelle vereint.
--
-- WICHTIG: Aktuell ist nur Kaiju spielbar -- nur Kaijus Knoten haben echte, verdrahtete
-- Effekte (siehe TalentTreeService.lua). Jaeger/Ronin sind vollständig als Datenstruktur
-- vorbereitet (inkl. Kosten/Vorstufen/Forschungszeit), damit sie später ohne
-- Strukturumbau aktiviert werden können.

local TalentTreeConfig = {}

TalentTreeConfig.EnergyOrder = { "Heat", "Electric", "Chemical", "Radiation", "Spirit" }

-- Kosten-Formel für MEHRSTUFIGE Knoten (Tier-1-Knoten mit mehreren Leveln): Stufe N
-- kostet BASE_COST * (GROWTH ^ (N-1)) der jeweiligen Energie. Tier-2/3/Ultimate-Knoten
-- haben stattdessen FESTE Kosten (energyCost + coinCost), da sie nur 1 Stufe haben.
TalentTreeConfig.TIER1_BASE_COST = 400
TalentTreeConfig.TIER1_COST_GROWTH = 1.6

function TalentTreeConfig.GetTier1Cost(level)
	return math.floor(TalentTreeConfig.TIER1_BASE_COST * (TalentTreeConfig.TIER1_COST_GROWTH ^ (level - 1)))
end

-- ===== Hilfsfunktion: baut die "Standardform" eines Baums (Start + 3 Zweige + Synergie
-- + Ultimate) aus Fraktions-spezifischen Namen/Effekten -- vermeidet, dieselbe Struktur
-- dreimal von Hand zu wiederholen. =====
local function buildFactionTree(definition)
	local nodes = {}

	-- Start-Knoten: immer verfügbar, günstig, schaltet die drei Zweige frei.
	table.insert(nodes, {
		id = definition.root.id,
		tier = 0,
		branch = "Root",
		name = definition.root.name,
		icon = definition.root.icon,
		description = definition.root.description,
		energyType = definition.root.energyType,
		maxLevel = 1,
		prerequisites = {},
		effectKey = definition.root.effectKey,
		effectPerLevel = definition.root.effectPerLevel,
		researchSeconds = 15,
		coinCost = 0,
	})

	for _, branch in ipairs(definition.branches) do
		-- Tier 1: 3 Stufen, reiner Ausbau (kein Trade-off) -- Basis-Investition in den Zweig.
		-- Optionaler zweiter Effekt-Slot (branch.tier1.secondaryEffectKey) -- nutzt dieselben
		-- Felder wie der Tier-2-Trade-off (tradeoffEffectKey/-PerLevel), ist hier aber KEIN
		-- Nachteil, sondern ein zweiter, gleichzeitig aktiver positiver Effekt.
		table.insert(nodes, {
			id = branch.tier1.id,
			tier = 1,
			branch = branch.key,
			name = branch.tier1.name,
			icon = branch.tier1.icon,
			description = branch.tier1.description,
			energyType = branch.energyType,
			maxLevel = 3,
			prerequisites = { { id = definition.root.id, level = 1 } },
			effectKey = branch.tier1.effectKey,
			effectPerLevel = branch.tier1.effectPerLevel,
			tradeoffEffectKey = branch.tier1.secondaryEffectKey,
			tradeoffEffectPerLevel = branch.tier1.secondaryEffectPerLevel,
			researchSeconds = 45,
			coinCost = 0, -- Tier 1 nutzt die Level-Kosten-Formel (nur Energie), siehe GetTier1Cost
		})

		-- Tier 2: TRADE-OFF -- ein echter Vor-/Nachteil, keine reine Verbesserung.
		table.insert(nodes, {
			id = branch.tier2.id,
			tier = 2,
			branch = branch.key,
			name = branch.tier2.name,
			icon = branch.tier2.icon,
			description = branch.tier2.description,
			isTradeoff = true,
			energyType = branch.energyType,
			maxLevel = 1,
			prerequisites = { { id = branch.tier1.id, level = 3 } },
			effectKey = branch.tier2.effectKey,
			effectPerLevel = branch.tier2.effectPerLevel,
			tradeoffEffectKey = branch.tier2.tradeoffEffectKey,
			tradeoffEffectPerLevel = branch.tier2.tradeoffEffectPerLevel,
			researchSeconds = 600, -- 10 Minuten
			energyCost = 3000,
			coinCost = 2500,
		})

		-- Tier 3: SYNERGIE innerhalb des Zweigs -- braucht Tier 2 des GLEICHEN Zweigs.
		table.insert(nodes, {
			id = branch.tier3.id,
			tier = 3,
			branch = branch.key,
			name = branch.tier3.name,
			icon = branch.tier3.icon,
			description = branch.tier3.description,
			energyType = branch.energyType,
			maxLevel = 1,
			prerequisites = { { id = branch.tier2.id, level = 1 } },
			effectKey = branch.tier3.effectKey,
			effectPerLevel = branch.tier3.effectPerLevel,
			-- Zweiter Effekt-Slot, wie ihn Tier 1 schon hat. getKaijuEffectBonus summiert
			-- effectKey UND tradeoffEffectKey, ein Knoten kann also zwei Wirkungen tragen.
			tradeoffEffectKey = branch.tier3.secondaryEffectKey,
			tradeoffEffectPerLevel = branch.tier3.secondaryEffectPerLevel,
			researchSeconds = 1800, -- 30 Minuten
			energyCost = 5000,
			coinCost = 6000,
		})
	end

	-- Cross-Zweig-Synergie: braucht je 1 Punkt in ZWEI verschiedenen Zweigen (Tier 1
	-- reicht) -- belohnt eine "breite" statt rein "tiefe" Investition.
	-- Position: standardmässig zwischen Zweig 1&2 ("Gap1_2"), aber pro Fraktion über
	-- crossSynergy.branchOverride verschiebbar (z.B. "Gap2_3" für zwischen Zweig 2&3) --
	-- damit lassen sich Kollisionen mit anderen, zusätzlich angehängten Knoten vermeiden.
	table.insert(nodes, {
		id = definition.crossSynergy.id,
		tier = 2.5,
		branch = definition.crossSynergy.branchOverride or "Gap1_2",
		name = definition.crossSynergy.name,
		icon = definition.crossSynergy.icon,
		description = definition.crossSynergy.description,
		energyType = definition.crossSynergy.energyType,
		maxLevel = 1,
		prerequisites = definition.crossSynergy.prerequisites,
		effectKey = definition.crossSynergy.effectKey,
		effectPerLevel = definition.crossSynergy.effectPerLevel,
		researchSeconds = 900, -- 15 Minuten
		energyCost = 3500,
		coinCost = 4000,
	})

	-- Ultimate: braucht ALLE DREI Zweige komplett ausgebaut (Tier 3 jedes Zweigs).
	local ultimatePrereqs = {}
	for _, branch in ipairs(definition.branches) do
		table.insert(ultimatePrereqs, { id = branch.tier3.id, level = 1 })
	end
	table.insert(nodes, {
		id = definition.ultimate.id,
		tier = 4,
		branch = "Ultimate",
		name = definition.ultimate.name,
		icon = definition.ultimate.icon,
		description = definition.ultimate.description,
		energyType = definition.ultimate.energyType,
		maxLevel = 1,
		prerequisites = ultimatePrereqs,
		effectKey = definition.ultimate.effectKey,
		effectPerLevel = definition.ultimate.effectPerLevel,
		researchSeconds = 7200, -- 2 Stunden
		energyCost = 15000,
		coinCost = 30000,
	})

	return nodes
end

-- ===== Kaiju -- POWER: Berserker / Assault / Devastation =====
TalentTreeConfig.Kaiju = buildFactionTree({
	root = {
		id = "ApexInstinct",
		name = "Apex Instinct",
		icon = "🦖",
		description = "Erwacht den Urinstinkt -- schaltet alle drei Kaiju-Pfade frei. +2% Gesamtschaden.",
		energyType = "Spirit",
		effectKey = "RootDamageBonus",
		effectPerLevel = 0.02,
	},
	branches = {
		{
			key = "Berserker",
			energyType = "Heat",
			tier1 = {
				id = "BerserkerFury",
				name = "Berserker Fury",
				icon = "🔥",
				description = "+6% Schaden im Berserker-/Meltdown-Zustand pro Stufe.",
				effectKey = "BerserkerDamageBonus",
				effectPerLevel = 0.06,
			},
			tier2 = {
				id = "OverheatSpecialist",
				name = "Overheat Specialist",
				icon = "🌋",
				description = "+20% Berserker-Schaden UND erweitert die Meltdown-Schwelle leicht Richtung 105% -- du bleibst länger im starken Berserker-Bereich, bevor Meltdown einsetzt.",
				effectKey = "OverheatDamageBonus",
				effectPerLevel = 0.20,
				tradeoffEffectKey = "MeltdownThresholdBonus",
				tradeoffEffectPerLevel = 5,
			},
			tier3 = {
				id = "MeltdownMastery",
				name = "Meltdown Mastery",
				icon = "☄️",
				description = "SYNERGIE: Meltdown gewährt zusätzlich +20% Angriffstempo, solange es "
					.. "aktiv ist. Zusätzlich kühlt deine Hitze 50% schneller ab -- du kommst schneller "
					.. "aus dem Meltdown heraus, verlierst den Berserker-Zustand aber auch früher.",
				effectKey = "MeltdownAttackSpeedBonus",
				effectPerLevel = 0.20,
				-- Zweischneidig, und das ist Absicht: die Abkühlrate wirkt auf BEIDE Enden.
				-- Sie holt dich schneller aus dem Meltdown, laesst die Hitze aber auch eher
				-- unter BERSERK_MIN_HEAT_TO_STAY (40) fallen, wo Berserk automatisch endet.
				-- Ein reiner Zugewinn waere hier langweilig; so ist es eine Entscheidung.
				secondaryEffectKey = "HeatCoolingBonus",
				secondaryEffectPerLevel = 0.5,
			},
		},
		{
			key = "Assault",
			energyType = "Electric",
			tier1 = {
				id = "RapidStrikes",
				name = "Rapid Strikes",
				icon = "⚡",
				description = "-5% Abklingzeit (Sprung/Fokus/Fläche) pro Stufe.",
				effectKey = "CooldownReduction",
				effectPerLevel = 0.05,
			},
			tier2 = {
				id = "FocusMastery",
				name = "Focus Mastery",
				icon = "🎯",
				description = "TRADE-OFF: +20% Fokus-Schaden, aber -15% Fokus-Reichweite (näher ran, dafür härter).",
				effectKey = "FocusDamageBonus",
				effectPerLevel = 0.20,
				tradeoffEffectKey = "FocusRangePenalty",
				tradeoffEffectPerLevel = 0.15,
			},
			tier3 = {
				id = "ComboChain",
				name = "Combo Chain",
				icon = "🔗",
				description = "SYNERGIE: 3 Fokus-Treffer in Folge lösen automatisch einen kostenlosen Flächenangriff aus.",
				effectKey = "ComboChainEnabled",
				effectPerLevel = 1,
			},
		},
		{
			key = "Devastation",
			energyType = "Chemical",
			tier1 = {
				id = "ChainReaction",
				name = "Chain Reaction",
				icon = "🧪",
				description = "+6% Flächenschaden-Radius pro Stufe.",
				effectKey = "AreaRadiusBonus",
				effectPerLevel = 0.06,
			},
			tier2 = {
				id = "BlastRadius",
				name = "Blast Radius",
				icon = "💥",
				description = "TRADE-OFF: +25% Flächenschaden-Radius, aber -10% Schaden pro Treffer (grösser, aber dünner verteilt).",
				effectKey = "BlastRadiusBonus",
				effectPerLevel = 0.25,
				tradeoffEffectKey = "AreaDamagePenalty",
				tradeoffEffectPerLevel = 0.10,
			},
			tier3 = {
				id = "Cataclysm",
				name = "Cataclysm",
				icon = "🌊",
				description = "SYNERGIE: jeder 4. Flächenangriff verursacht doppelten Schaden.",
				effectKey = "CataclysmEnabled",
				effectPerLevel = 1,
			},
		},
	},
	crossSynergy = {
		id = "OverheatBlast",
		name = "Overheat Blast",
		icon = "🔴",
		description = "Braucht Berserker Fury UND Chain Reaction (je 1 Punkt): Flächenschaden skaliert zusätzlich mit deinem aktuellen Heat-Wert.",
		energyType = "Radiation",
		effectKey = "HeatScaledAreaDamage",
		effectPerLevel = 0.30, -- bis zu +30% bei 100% Heat
		prerequisites = { { id = "BerserkerFury", level = 1 }, { id = "ChainReaction", level = 1 } },
		-- Verschoben auf "zwischen Zweig 2&3" -- gibt Focus Retarget (zwischen Zweig 1&2)
		-- genug Abstand, sonst würden sich beide Knoten überlappen.
		branchOverride = "Gap2_3",
	},
	ultimate = {
		id = "ApexPredator",
		name = "Apex Predator",
		icon = "✨",
		description = "ULTIMATE: dauerhaft +15% Gesamtschaden. Braucht alle drei Zweige voll ausgebaut.",
		energyType = "Spirit",
		effectKey = "UltimateDamageBonus",
		effectPerLevel = 0.15,
	},
})

-- Zusätzlicher Ableger-Knoten im Assault-Zweig (nicht Teil der buildFactionTree-
-- Standardform, daher manuell angehängt): schaltet automatisches Zielwechseln beim
-- Fokusstrahl frei. Ohne dieses Talent hört der Strahl nach dem Zerstören seines Ziels
-- einfach auf, statt automatisch weiterzusuchen.
table.insert(TalentTreeConfig.Kaiju, {
	id = "FocusRetarget",
	tier = 2.35,
	branch = "Gap1_2", -- zwischen Zweig 1&2, statt in der Assault-Spalte (kollidierte dort mit Focus Mastery)
	name = "Focus Retarget",
	icon = "🔄",
	description = "Der Fokusstrahl wechselt automatisch zum nächsten Ziel, falls das aktuelle zerstört wird und noch Zeit übrig ist. Ohne dieses Talent hört der Strahl nach dem Ziel einfach auf.",
	energyType = "Electric",
	maxLevel = 1,
	prerequisites = { { id = "FocusMastery", level = 1 } },
	effectKey = "FocusRetargetEnabled",
	effectPerLevel = 1,
	researchSeconds = 300,
	energyCost = 1500,
	coinCost = 1000,
})

-- ===== Jaeger -- CONTROL: Systems / Suppression / Tactics (Vorschau, noch nicht
-- spielbar) =====
TalentTreeConfig.Jaeger = buildFactionTree({
	root = {
		id = "TacticalAwakening",
		name = "Tactical Awakening",
		icon = "🤖",
		description = "(Vorschau) Aktiviert die Kernsysteme -- schaltet alle drei Jaeger-Pfade frei.",
		energyType = "Spirit",
		effectKey = "JaegerRootBonus",
		effectPerLevel = 0.02,
	},
	branches = {
		{
			key = "Systems",
			energyType = "Electric",
			tier1 = { id = "SystemOverride", name = "System Override", icon = "⚡", description = "(Vorschau) Fähigkeiten werden effizienter.", effectKey = "SystemEfficiency", effectPerLevel = 0.04 },
			tier2 = { id = "Overclock", name = "Overclock", icon = "🌀", description = "(Vorschau) TRADE-OFF: mehr Systemleistung, höherer Energieverbrauch.", effectKey = "OverclockPower", effectPerLevel = 0.15, tradeoffEffectKey = "OverclockCostPenalty", tradeoffEffectPerLevel = 0.10 },
			tier3 = { id = "NetworkSync", name = "Network Sync", icon = "🔗", description = "(Vorschau) SYNERGIE: Systeme verstärken sich gegenseitig.", effectKey = "NetworkSyncEnabled", effectPerLevel = 1 },
		},
		{
			key = "Suppression",
			energyType = "Heat",
			tier1 = { id = "Overcharge", name = "Overcharge", icon = "🔥", description = "(Vorschau) +1.5% Berserker-Schaden UND erweitert die Meltdown-Schwelle deutlich (+3% pro Stufe, bis 109%) -- Jaeger bleibt lange im Berserker-Bereich, Meltdown wird selten erreicht.", effectKey = "JaegerBerserkDamageBonus", effectPerLevel = 0.015, secondaryEffectKey = "MeltdownThresholdBonus", secondaryEffectPerLevel = 3 },
			tier2 = { id = "SuppressionField", name = "Suppression Field", icon = "🧪", description = "(Vorschau) TRADE-OFF: stärkere Unterdrückung, kürzere Reichweite.", effectKey = "SuppressionStrength", effectPerLevel = 0.20, tradeoffEffectKey = "SuppressionRangePenalty", tradeoffEffectPerLevel = 0.15 },
			tier3 = { id = "LockdownProtocol", name = "Lockdown Protocol", icon = "🔒", description = "(Vorschau) SYNERGIE: unterdrückte Ziele nehmen zusätzlichen Schaden.", effectKey = "LockdownEnabled", effectPerLevel = 1 },
		},
		{
			key = "Tactics",
			energyType = "Radiation",
			tier1 = { id = "TacticalScan", name = "Tactical Scan", icon = "☢️", description = "(Vorschau) Zeigt strategische Ziele/Schwachstellen an.", effectKey = "ScanRange", effectPerLevel = 0.06 },
			tier2 = { id = "PredictiveTargeting", name = "Predictive Targeting", icon = "🎯", description = "(Vorschau) TRADE-OFF: präzisere Ziele, langsamere Erfassung.", effectKey = "TargetingBonus", effectPerLevel = 0.25, tradeoffEffectKey = "TargetingSpeedPenalty", tradeoffEffectPerLevel = 0.10 },
			tier3 = { id = "BattlefieldControl", name = "Battlefield Control", icon = "🌊", description = "(Vorschau) SYNERGIE: volle taktische Übersicht.", effectKey = "BattlefieldControlEnabled", effectPerLevel = 1 },
		},
	},
	crossSynergy = {
		id = "SystemLockdown",
		name = "System Lockdown",
		icon = "🔴",
		description = "(Vorschau) Braucht System Override UND Overcharge.",
		energyType = "Radiation",
		effectKey = "SystemLockdownBonus",
		effectPerLevel = 0.30,
		prerequisites = { { id = "SystemOverride", level = 1 }, { id = "Overcharge", level = 1 } },
	},
	ultimate = {
		id = "TotalControl",
		name = "Total Control",
		icon = "✨",
		description = "(Vorschau) ULTIMATE: vollständige taktische Kontrolle über das Schlachtfeld.",
		energyType = "Spirit",
		effectKey = "UltimateControlBonus",
		effectPerLevel = 0.15,
	},
})

-- ===== Ronin -- PURPOSE: Momentum / Precision / Technique (Vorschau, noch nicht
-- spielbar) =====
TalentTreeConfig.Ronin = buildFactionTree({
	root = {
		id = "WayOfTheBlade",
		name = "Way of the Blade",
		icon = "🐯",
		description = "(Vorschau) Findet den eigenen Weg -- schaltet alle drei Ronin-Pfade frei.",
		energyType = "Spirit",
		effectKey = "RoninRootBonus",
		effectPerLevel = 0.02,
	},
	branches = {
		{
			key = "Momentum",
			energyType = "Electric",
			tier1 = { id = "DashStrike", name = "Dash Strike", icon = "⚡", description = "(Vorschau) Schneller Dash, kombiniert mit einem Treffer.", effectKey = "DashPower", effectPerLevel = 0.04 },
			tier2 = { id = "Windrunner", name = "Windrunner", icon = "🌀", description = "(Vorschau) TRADE-OFF: mehr Tempo, weniger Kontrolle in der Luft.", effectKey = "SpeedBonus", effectPerLevel = 0.15, tradeoffEffectKey = "AirControlPenalty", tradeoffEffectPerLevel = 0.10 },
			tier3 = { id = "PerpetualMotion", name = "Perpetual Motion", icon = "🔗", description = "(Vorschau) SYNERGIE: ununterbrochene Bewegung baut stetig Tempo auf.", effectKey = "MomentumEnabled", effectPerLevel = 1 },
		},
		{
			key = "Precision",
			energyType = "Heat",
			tier1 = { id = "RoninMomentum", name = "Momentum", icon = "🔥", description = "(Vorschau) +5% Berserker-Schaden UND erweitert die Meltdown-Schwelle spürbar (+2.5% pro Stufe) -- Ronin verbindet beides, ohne bei einem der beiden ganz an die Spitze zu kommen.", effectKey = "RoninBerserkDamageBonus", effectPerLevel = 0.05, secondaryEffectKey = "MeltdownThresholdBonus", secondaryEffectPerLevel = 2.5 },
			tier2 = { id = "TrickShot", name = "Trick Shot", icon = "🧪", description = "(Vorschau) TRADE-OFF: mehr Spezialeffekte, seltener auslösbar.", effectKey = "TrickShotChance", effectPerLevel = 0.20, tradeoffEffectKey = "TrickShotCooldownPenalty", tradeoffEffectPerLevel = 0.15 },
			tier3 = { id = "FlawlessStrike", name = "Flawless Strike", icon = "🔒", description = "(Vorschau) SYNERGIE: präzise Treffer verstärken den nächsten Treffer.", effectKey = "FlawlessStrikeEnabled", effectPerLevel = 1 },
		},
		{
			key = "Technique",
			energyType = "Radiation",
			tier1 = { id = "FocusStrike", name = "Focus Strike", icon = "☢️", description = "(Vorschau) Erhöhte kritische Trefferchance auf fokussierte Ziele.", effectKey = "CritChance", effectPerLevel = 0.03 },
			tier2 = { id = "CriticalEye", name = "Critical Eye", icon = "🎯", description = "(Vorschau) +12% zusätzlicher Berserker-Schaden UND +2% weitere Meltdown-Schwellen-Erweiterung -- bringt Ronin insgesamt fast auf Kaiju-Schaden-Niveau bei fast Jaeger-Erweiterung.", effectKey = "RoninBerserkDamageBonus", effectPerLevel = 0.12, tradeoffEffectKey = "MeltdownThresholdBonus", tradeoffEffectPerLevel = 2 },
			tier3 = { id = "PerfectForm", name = "Perfect Form", icon = "🌊", description = "(Vorschau) SYNERGIE: kritische Treffer kosten keine Abklingzeit.", effectKey = "PerfectFormEnabled", effectPerLevel = 1 },
		},
	},
	crossSynergy = {
		id = "SwiftPrecision",
		name = "Swift Precision",
		icon = "🔴",
		description = "(Vorschau) Braucht Dash Strike UND Focus Strike.",
		energyType = "Radiation",
		effectKey = "SwiftPrecisionBonus",
		effectPerLevel = 0.30,
		prerequisites = { { id = "DashStrike", level = 1 }, { id = "FocusStrike", level = 1 } },
	},
	ultimate = {
		id = "PerfectTechnique",
		name = "Perfect Technique",
		icon = "✨",
		description = "(Vorschau) ULTIMATE: makellose Ausführung jeder Bewegung.",
		energyType = "Spirit",
		effectKey = "UltimateTechniqueBonus",
		effectPerLevel = 0.15,
	},
})

TalentTreeConfig.Factions = {
	Kaiju = TalentTreeConfig.Kaiju,
	Jaeger = TalentTreeConfig.Jaeger,
	Ronin = TalentTreeConfig.Ronin,
}

function TalentTreeConfig.GetTalentsForFaction(factionName)
	return TalentTreeConfig.Factions[factionName] or {}
end

function TalentTreeConfig.FindTalent(factionName, talentId)
	for _, talent in ipairs(TalentTreeConfig.GetTalentsForFaction(factionName)) do
		if talent.id == talentId then
			return talent
		end
	end
	return nil
end

-- Kosten für eine bestimmte Stufe eines Knotens (berücksichtigt Tier-1-Formel vs. feste
-- Kosten bei Tier 2/3/Synergie/Ultimate).
function TalentTreeConfig.GetNodeCost(talent, targetLevel)
	if talent.tier == 1 then
		return { energyAmount = TalentTreeConfig.GetTier1Cost(targetLevel), coinAmount = 0 }
	end
	return { energyAmount = talent.energyCost or 0, coinAmount = talent.coinCost or 0 }
end

return TalentTreeConfig