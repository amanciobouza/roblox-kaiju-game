-- VERSION: 2026-08-19 #2
-- ModuleScript: HelpConfig
-- Ort in Studio: ReplicatedStorage
--
-- Zentrale Inhalte für die Hilfeseite (siehe NavigationClient.lua, HelpPanel). Auf
-- Englisch, wie vom Team gewünscht.
--
-- Jeder Abschnitt hat:
--   id          -- eindeutige ID (zum direkten Anspringen von einem Kontext-Button aus)
--   icon        -- Emoji fürs Abschnitt-Icon
--   title       -- Überschrift
--   summary     -- 1-2 Sätze Kurzerklärung
--   points      -- Liste kurzer, konkreter Fakten/Bullet-Points
--   diagramType -- welches gebaute Diagramm gerendert wird (siehe buildDiagram in
--                  NavigationClient.lua) -- Platzhalter statt echter Screenshots, bis
--                  Bild-Assets vorhanden sind.

local HelpConfig = {}

HelpConfig.Sections = {
	{
		id = "training",
		icon = "🏋️",
		title = "Training",
		summary = "Three body stats you train at the Training Stations, located at the bottom of the Trench, below the Sanctuary. Each one boosts a different part of your combat style.",
		points = {
			"💪 Arm -> Base Damage: increases your regular punch damage.",
			"🦵 Leg -> Bonus Damage: increases jump/trample damage, and also boosts your Special Attack bonus damage.",
			"🫀 Body -> Energy Efficiency: bigger absorb radius and more energy per absorb.",
			"Each stat has a cap that grows with your player level.",
		},
		diagramType = "training",
	},
	{
		id = "alert",
		icon = "🚨",
		title = "Alert System",
		summary = "Every city has a threat level that rises as you destroy buildings. The higher the Alert Level, the harder the city fights back.",
		points = {
			"⭐ Level 1 -- Warning: sirens go off, the city has noticed you.",
			"⭐⭐ Level 2 -- Emergency: fire trucks respond and put out fires -- good for the city, but it also means less energy for you to absorb from burning buildings.",
			"⭐⭐⭐ Level 3 -- Defense: energy-shield barricades protect buildings.",
			"⭐⭐⭐⭐ Level 4 -- Military: tanks, rocket launchers, and helicopters attack YOU directly -- stay alert and be careful.",
			"⭐⭐⭐⭐⭐ Level 5 -- Titan Protocol: a Guardian boss defends the city.",
			"Alert only goes down once you fully leave the city -- waiting around inside does nothing.",
			"Not every city has all five stages -- smaller cities cap out earlier.",
			"Master every Alert stage of a city, and it gives up for a while -- free reign to destroy buildings and collect energy with no resistance.",
		},
		diagramType = "alert",
	},
	{
		id = "heat",
		icon = "🔥",
		title = "Berserker & Meltdown",
		summary = "Your Heat value (0-110%) rises as you fight and drives your combat state. It's not a button you activate -- it's a zone you want to stay in.",
		points = {
			"Calm -> Aggressive -> Enraged -> Berserker -> Meltdown, with rising damage and speed.",
			"Berserker (the red zone): try to stay here for maximum damage and power -- nothing to activate, just keep your Heat up.",
			"Meltdown (Heat 100+): you're overheating -- you take damage and slow down heavily. Risky, don't linger.",
			"Some talents slightly extend how far the Meltdown threshold reaches.",
			"Heat cools down over time on its own, and cools down faster while you're absorbing energy.",
		},
		diagramType = "heat",
	},
	{
		id = "energy",
		icon = "⚡",
		title = "Special Energy",
		summary = "A fast, tactical resource (separate from Heat/Berserker) that pays for Focus and Area attacks -- and also earns you level points as you build it up.",
		points = {
			"Fills up through normal fighting: hits, combos, jump landings, destroying buildings.",
			"Absorbing energy fills the bar noticeably faster -- optional, but worth it.",
			"Focus attack costs 25 Energy, Area attack costs 40 Energy.",
			"The cyan ring around your Berserker dial shows your current Energy level.",
		},
		diagramType = "energy",
	},
	{
		id = "factions",
		icon = "🎭",
		title = "Factions",
		summary = "Three completely different playstyles, all within the same Trenchborn universe.",
		points = {
			"🦖 Kaiju -- Power: raw destruction, escalation is the goal. Currently playable.",
			"🤖 Jaeger -- Control: manipulates the Alert system directly, weakens defense systems. Preview.",
			"🐯 Ronin -- Purpose: focused routes instead of long fights. Preview.",
			"Each faction has its own talent tree with three branches.",
		},
		diagramType = "factions",
	},
}

return HelpConfig