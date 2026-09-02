-- VERSION: 2026-08-25 #11
-- FIX: PrologueCity Alert-Zerfall deaktiviert (verhinderte Absturz von Level 5 auf 0)
-- Ort in Studio: ReplicatedStorage
--
-- Zentrale, konfigurierbare Werte für das City-Alert-System. JEDE Stadt hat ihren
-- eigenen unabhängigen Alert-Level + Alert-Fortschritt (siehe CityAlertService.lua).
-- Diese Datei enthält ALLE einstellbaren Zahlen -- keine Werte sind in den einzelnen
-- Scripts hartcodiert, damit spätere Alert-Level (3+) und Balance-Anpassungen an EINER
-- zentralen Stelle passieren.

local CityAlertConfig = {}

-- ===== Reihenfolge der Städte (für Debug-Ausgaben, Anzeige etc.) =====
CityAlertConfig.CityOrder = { "Village", "SmallTown", "City", "LargeCity", "MegaCity", "PrologueCity" }

-- ===== Pro-Stadt-Konfiguration =====
-- WICHTIG: "CityName"-Attribut muss am Container/Ordner jeder Stadt in Studio gesetzt
-- werden (z.B. workspace.Cities.Village bekommt CityName="Village") -- alle Häuser,
-- Feuerwehrautos etc. darunter werden dieser Stadt automatisch zugeordnet (siehe
-- CityAlertService.lua, resolveCityName). Die Namen hier MÜSSEN exakt mit den
-- CityName-Attributen in Studio übereinstimmen.
CityAlertConfig.Cities = {
	Village = {
		-- Alert Level 1 -> 2: wie viel Alert-Fortschritt nötig ist, bis die Feuerwehr anrückt
		AlertThresholdLevel2 = 100,
		-- Alert Level 2 -> 3: Barrikaden-Schild-Cluster (siehe BarricadeClusterService.lua)
		AlertThresholdLevel3 = 400,
		-- Alert-Wert pro HP eines zerstörten Gebäudes (AlertValue = MaxHealth * AlertPerHP),
		-- falls das Gebäude kein eigenes "AlertValue"-Attribut in Studio gesetzt hat.
		AlertPerHP = 0.5,

		FireEngineHP = 300,
		FireEngineCount = 1, -- 1-3 laut Vorgabe, Village bekommt die untere Grenze
		FireEngineSpeed = 14, -- Studs/Sekunde
		FirefightingRate = 8, -- Energie/Sekunde, die ein Feuerwehrauto einer Feuerquelle entzieht
		FirefightingRange = 45, -- Studs -- muss so nah dran sein, um zu löschen
		FireEngineDestroyAlertValue = 15, -- deutlich mehr Alert als ein normales Haus

		WaterTowerEfficiencyBonus = 0.5, -- +50% Löschrate, solange der Wasserturm intakt ist

		AlertDecayDelay = 20, -- Sekunden ohne neue Zerstörung, bevor der Abbau beginnt
		AlertDecayRate = 4, -- Alert-Punkte/Sekunde, die danach abgebaut werden

		-- ===== Stufe 3: Barrikaden-Schild-Cluster =====
		BarricadeScale = 1.0,
		ShieldMaxHealth = 3000,
		ShieldRegenDelay = 8,
		ShieldRegenRate = 0.05,
		GeneratorMaxHealth = 400,
		ElectricDamage = 10, -- Schaden pro Stromschlag am Elektrozaun (skaliert mit Stadtgrösse)
		EscalationStepSize = 5,
		MaxActiveReactiveBarricades = 3,
		ReactiveSpawnSearchRadius = 150,
		FlankAutoDetectRadius = 40,

		-- ===== Stufe 4: Militär (Panzer, Raketenwerfer, Militär-Helikopter) =====
		AlertThresholdLevel4 = 1600,
		MaxAlertLevel = 3, -- Konzept-Vorgabe: nicht jede Stadt kennt alle Alert-Stufen
		-- Kapitel I / II / III. Dieselbe Karte härtet sich über die Kapitel: das Village
		-- lernt in Kapitel II das Militär kennen und bekommt in Kapitel III einen Guardian.
		-- Stufe 5 bleibt hier vorerst folgenlos -- ohne AlertThresholdLevel5 steigt
		-- CityAlertService gar nicht erst dorthin auf (siehe checkLevelThresholds). Das ist
		-- Absicht: der Mechanismus steht, die Inhalte (Schwelle, Guardian-Werte, Modell)
		-- kommen nach.
		MaxAlertLevelByChapter = { 3, 4, 5 },
		MilitaryTankCount = 1,
		MilitaryRocketLauncherCount = 1,
		MilitaryHelicopterCount = 1,
		TankHP = 5000,
		TankDamage = 12,
		TankAttackRange = 60,
		TankSpeed = 12,
		RocketLauncherHP = 3000,
		RocketLauncherDamage = 14,
		RocketLauncherAttackRange = 100,
		HelicopterHP = 2500,
		HelicopterDamage = 10,
		HelicopterAttackRange = 80,
		HelicopterSpeed = 18,


		-- ===== Stufe 5: Guardian =====
		-- Erreichbar erst ab Kapitel III (siehe MaxAlertLevelByChapter oben) -- in Kapitel I
		-- bleibt diese Stadt darunter, die Werte liegen dann brach.
		AlertThresholdLevel5 = 6400, -- setzt das 4x-Muster der Stufen 2-4 fort
		GuardianHP = 20000,
		GuardianShieldHP = 8000, -- 40% der HP, wie bei LargeCity und MegaCity
		GuardianShieldRegenDelay = 10,
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 26,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 13,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	SmallTown = {
		AlertThresholdLevel2 = 400,
		AlertThresholdLevel3 = 1600,
		AlertPerHP = 0.35,

		FireEngineHP = 1500,
		FireEngineCount = 2,
		FireEngineSpeed = 16,
		FirefightingRate = 30,
		FirefightingRange = 50,
		FireEngineDestroyAlertValue = 50,

		WaterTowerEfficiencyBonus = 0, -- SmallTown hat (aktuell) keinen eigenen Wasserturm

		AlertDecayDelay = 20,
		AlertDecayRate = 12,

		BarricadeScale = 1.5,
		ShieldMaxHealth = 7000,
		ShieldRegenDelay = 8,
		ShieldRegenRate = 0.05,
		GeneratorMaxHealth = 1000,
		ElectricDamage = 30, -- Schaden pro Stromschlag am Elektrozaun (skaliert mit Stadtgrösse)
		EscalationStepSize = 5,
		MaxActiveReactiveBarricades = 3,
		ReactiveSpawnSearchRadius = 150,
		FlankAutoDetectRadius = 40,

		-- ===== Stufe 4: Militär (Panzer, Raketenwerfer, Militär-Helikopter) =====
		AlertThresholdLevel4 = 6400,
		MaxAlertLevel = 4, -- Konzept-Vorgabe: nicht jede Stadt kennt alle Alert-Stufen
		-- Ab Kapitel II erreicht SmallTown Stufe 5 samt Guardian. Wie beim Village gilt:
		-- ohne AlertThresholdLevel5 bleibt es faktisch bei 4, bis die Schwelle gesetzt ist.
		MaxAlertLevelByChapter = { 4, 5, 5 },
		MilitaryTankCount = 2,
		MilitaryRocketLauncherCount = 1,
		MilitaryHelicopterCount = 1,
		TankHP = 15000,
		TankDamage = 30,
		TankAttackRange = 65,
		TankSpeed = 13,
		RocketLauncherHP = 9000,
		RocketLauncherDamage = 35,
		RocketLauncherAttackRange = 110,
		HelicopterHP = 7500,
		HelicopterDamage = 25,
		HelicopterAttackRange = 85,
		HelicopterSpeed = 19,

		-- ===== Stufe 5: Guardian =====
		-- Erreichbar erst ab Kapitel II (siehe MaxAlertLevelByChapter oben) -- in Kapitel I
		-- bleibt diese Stadt darunter, die Werte liegen dann brach.
		AlertThresholdLevel5 = 25600, -- setzt das 4x-Muster der Stufen 2-4 fort
		GuardianHP = 60000,
		GuardianShieldHP = 24000, -- 40% der HP, wie bei LargeCity und MegaCity
		GuardianShieldRegenDelay = 10,
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 70,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 35,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	City = {
		AlertThresholdLevel2 = 1600,
		AlertThresholdLevel3 = 6400,
		AlertPerHP = 0.25,

		FireEngineHP = 8000,
		FireEngineCount = 2,
		FireEngineSpeed = 18,
		FirefightingRate = 140,
		FirefightingRange = 55,
		FireEngineDestroyAlertValue = 180,

		WaterTowerEfficiencyBonus = 0,

		AlertDecayDelay = 25,
		AlertDecayRate = 45,

		BarricadeScale = 2.0,
		ShieldMaxHealth = 13000,
		ShieldRegenDelay = 8,
		ShieldRegenRate = 0.04,
		GeneratorMaxHealth = 1750,
		ElectricDamage = 87, -- Schaden pro Stromschlag am Elektrozaun (skaliert mit Stadtgrösse)
		EscalationStepSize = 5,
		MaxActiveReactiveBarricades = 3,
		ReactiveSpawnSearchRadius = 150,
		FlankAutoDetectRadius = 40,

		-- ===== Stufe 4: Militär (Panzer, Raketenwerfer, Militär-Helikopter) =====
		AlertThresholdLevel4 = 25600,
		MaxAlertLevel = 5, -- Konzept-Vorgabe: nicht jede Stadt kennt alle Alert-Stufen
		MilitaryTankCount = 2,
		MilitaryRocketLauncherCount = 2,
		MilitaryHelicopterCount = 2,
		TankHP = 45000,
		TankDamage = 75,
		TankAttackRange = 70,
		TankSpeed = 14,
		RocketLauncherHP = 27000,
		RocketLauncherDamage = 88,
		RocketLauncherAttackRange = 120,
		HelicopterHP = 22000,
		HelicopterDamage = 62,
		HelicopterAttackRange = 90,
		HelicopterSpeed = 20,

		-- ===== Stufe 5: Guardian (erste Stadt mit Guardian -- Village/SmallTown haben
		-- laut Konzept keinen) =====
		AlertThresholdLevel5 = 102400, -- konsistent zum bestehenden 4x-Muster (1600 -> 6400 -> 25600 -> 102400)
		GuardianHP = 180000,
		GuardianShieldHP = 72000,
		GuardianShieldRegenDelay = 10,
		-- Anteil des MAXIMALSCHILDS pro Sekunde. War 0.04 und damit staerker als der
		-- Spielerschaden: bei 2200 Schaden je Schlag regenerierte der Schild mit rund
		-- 105 % des DPS. Elf Sekunden Pause kosteten dadurch den gesamten
		-- Schildfortschritt, und der Kampf war nach einer Unterbrechung praktisch
		-- zurueckgesetzt. Jetzt 0.005 -- eine Achtelung.
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 188,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 94,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	LargeCity = {
		AlertThresholdLevel2 = 6400,
		AlertThresholdLevel3 = 25600,
		AlertPerHP = 0.18,

		FireEngineHP = 50000,
		FireEngineCount = 3,
		FireEngineSpeed = 20,
		FirefightingRate = 700,
		FirefightingRange = 60,
		FireEngineDestroyAlertValue = 650,

		WaterTowerEfficiencyBonus = 0,

		AlertDecayDelay = 25,
		AlertDecayRate = 160,

		BarricadeScale = 2.5,
		ShieldMaxHealth = 21000,
		ShieldRegenDelay = 8,
		ShieldRegenRate = 0.04,
		GeneratorMaxHealth = 2750,
		ElectricDamage = 225, -- Schaden pro Stromschlag am Elektrozaun (skaliert mit Stadtgrösse)
		EscalationStepSize = 5,
		MaxActiveReactiveBarricades = 4,
		ReactiveSpawnSearchRadius = 150,
		FlankAutoDetectRadius = 40,

		-- ===== Stufe 4: Militär (Panzer, Raketenwerfer, Militär-Helikopter) =====
		AlertThresholdLevel4 = 102400,
		MaxAlertLevel = 5, -- Konzept-Vorgabe: nicht jede Stadt kennt alle Alert-Stufen
		MilitaryTankCount = 3,
		MilitaryRocketLauncherCount = 2,
		MilitaryHelicopterCount = 2,
		TankHP = 140000,
		TankDamage = 200,
		TankAttackRange = 75,
		TankSpeed = 15,
		RocketLauncherHP = 85000,
		RocketLauncherDamage = 227,
		RocketLauncherAttackRange = 130,
		HelicopterHP = 70000,
		HelicopterDamage = 165,
		HelicopterAttackRange = 95,
		HelicopterSpeed = 21,

		-- ===== Stufe 5: Guardian =====
		-- Werte folgen der Skalierung, die im Bestand durchgehend gilt: Alarmschwellen
		-- x4 je Stadtstufe, Trefferpunkte ~x3, Schaden ~x2.7 (siehe Tank/Raketenwerfer
		-- eine Zeile hoeher). Ausgehend von City als erster Stadt mit Guardian.
		--
		-- Ohne AlertThresholdLevel5 war Stufe 5 hier UNERREICHBAR, obwohl MaxAlertLevel
		-- sie versprach -- die Stadt liess sich damit nicht abschliessen, denn die
		-- CITY-BROKEN-Aufgabe "Guardian eliminated" setzt einen Guardian voraus.
		AlertThresholdLevel5 = 409600, -- Level4: 102400 x4
		GuardianHP = 540000,
		GuardianShieldHP = 216000,
		GuardianShieldRegenDelay = 10,
		-- Anteil des MAXIMALSCHILDS pro Sekunde. War 0.04 und damit staerker als der
		-- Spielerschaden: bei 2200 Schaden je Schlag regenerierte der Schild mit rund
		-- 105 % des DPS. Elf Sekunden Pause kosteten dadurch den gesamten
		-- Schildfortschritt, und der Kampf war nach einer Unterbrechung praktisch
		-- zurueckgesetzt. Jetzt 0.005 -- eine Achtelung.
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 500,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 250,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	MegaCity = {
		AlertThresholdLevel2 = 25600,
		AlertThresholdLevel3 = 102400,
		AlertPerHP = 0.12,

		FireEngineHP = 300000,
		FireEngineCount = 3,
		FireEngineSpeed = 22,
		FirefightingRate = 3200,
		FirefightingRange = 65,
		FireEngineDestroyAlertValue = 2400,

		WaterTowerEfficiencyBonus = 0, -- Megacity hat einen Reaktor statt Wasserturm -- kein Bonus hier

		AlertDecayDelay = 30,
		AlertDecayRate = 700,

		BarricadeScale = 3.0,
		ShieldMaxHealth = 30000,
		ShieldRegenDelay = 8,
		ShieldRegenRate = 0.03,
		GeneratorMaxHealth = 4000,
		ElectricDamage = 625, -- Schaden pro Stromschlag am Elektrozaun (skaliert mit Stadtgrösse)
		EscalationStepSize = 5,
		MaxActiveReactiveBarricades = 4,
		ReactiveSpawnSearchRadius = 150,
		FlankAutoDetectRadius = 40,

		-- ===== Stufe 4: Militär (Panzer, Raketenwerfer, Militär-Helikopter) =====
		AlertThresholdLevel4 = 409600,
		MaxAlertLevel = 5, -- Konzept-Vorgabe: nicht jede Stadt kennt alle Alert-Stufen
		MilitaryTankCount = 4,
		MilitaryRocketLauncherCount = 3,
		MilitaryHelicopterCount = 3,
		TankHP = 450000,
		TankDamage = 550,
		TankAttackRange = 80,
		TankSpeed = 16,
		RocketLauncherHP = 270000,
		RocketLauncherDamage = 630,
		RocketLauncherAttackRange = 140,
		HelicopterHP = 220000,
		HelicopterDamage = 450,
		HelicopterAttackRange = 100,
		HelicopterSpeed = 22,

		-- ===== Stufe 5: Guardian =====
		-- Werte folgen der Skalierung, die im Bestand durchgehend gilt: Alarmschwellen
		-- x4 je Stadtstufe, Trefferpunkte ~x3, Schaden ~x2.7 (siehe Tank/Raketenwerfer
		-- eine Zeile hoeher). Ausgehend von City als erster Stadt mit Guardian.
		--
		-- Ohne AlertThresholdLevel5 war Stufe 5 hier UNERREICHBAR, obwohl MaxAlertLevel
		-- sie versprach -- die Stadt liess sich damit nicht abschliessen, denn die
		-- CITY-BROKEN-Aufgabe "Guardian eliminated" setzt einen Guardian voraus.
		AlertThresholdLevel5 = 1638400, -- Level4: 409600 x4
		GuardianHP = 1620000,
		GuardianShieldHP = 648000,
		GuardianShieldRegenDelay = 10,
		-- Anteil des MAXIMALSCHILDS pro Sekunde. War 0.04 und damit staerker als der
		-- Spielerschaden: bei 2200 Schaden je Schlag regenerierte der Schild mit rund
		-- 105 % des DPS. Elf Sekunden Pause kosteten dadurch den gesamten
		-- Schildfortschritt, und der Kampf war nach einer Unterbrechung praktisch
		-- zurueckgesetzt. Jetzt 0.005 -- eine Achtelung.
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 1375,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 690,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	-- ===== Playable Prologue ("The Fall") =====
	-- Eigene, dedizierte Stadt für den Prolog -- deutlich niedrigere Schwellenwerte als
	-- alle regulären Städte, damit die komplette Eskalationskette (Alert 1-5) innerhalb
	-- weniger Minuten durchlaufen wird (der Prolog-Kaiju hat ausserdem sehr hohen Schaden,
	-- siehe PrologueOrchestrator.lua PROLOGUE_DAMAGE -- Gebäude fallen entsprechend schnell).
	PrologueCity = {
		AlertThresholdLevel2 = 30,
		AlertThresholdLevel3 = 100,
		AlertPerHP = 0.5,

		FireEngineHP = 20000,
		FireEngineCount = 2,
		FireEngineSpeed = 14,
		FirefightingRate = 60,
		FirefightingRange = 30,
		FireEngineDestroyAlertValue = 20,

		WaterTowerEfficiencyBonus = 0,

		-- Zerfall komplett deaktiviert -- die Eskalation ist rein zeitgesteuert (siehe
		-- PrologueOrchestrator.lua, driveEscalationByTime), ein automatischer Zerfall
		-- würde ihr entgegenwirken, sobald der Zeit-Treiber nach Erreichen von Level 5
		-- aufhört, den Fortschritt zu berühren.
		AlertDecayDelay = 999999,
		AlertDecayRate = 0,

		BarricadeScale = 1.0,
		ShieldMaxHealth = 100000,
		ShieldRegenDelay = 8,
		ShieldRegenRate = 0.04,
		GeneratorMaxHealth = 400,
		ElectricDamage = 12,
		EscalationStepSize = 3,
		MaxActiveReactiveBarricades = 2,
		ReactiveSpawnSearchRadius = 100,
		FlankAutoDetectRadius = 30,

		-- ===== Stufe 4: Militär -- die Prolog-Nachschub-Welle (siehe
		-- PrologueReinforcementService.lua) ergänzt ab hier fortlaufend WEITERE
		-- Einheiten, zusätzlich zu diesem einmaligen Basis-Schub. =====
		AlertThresholdLevel4 = 300,
		MaxAlertLevel = 5,
		MilitaryTankCount = 5,
		MilitaryRocketLauncherCount = 4,
		MilitaryHelicopterCount = 2,
		TankHP = 40000,
		TankDamage = 12,
		TankAttackRange = 60,
		TankSpeed = 12,
		RocketLauncherHP = 30000,
		RocketLauncherDamage = 14,
		RocketLauncherAttackRange = 100,
		HelicopterHP = 2000,
		HelicopterDamage = 10,
		HelicopterAttackRange = 80,
		HelicopterSpeed = 18,

		-- ===== Stufe 5: Guardian -- der eigentliche Boss-Kampf des Prologs. HP bewusst
		-- moderat (nicht Städte-Massstab), da der Kampf ohnehin TIMER-basiert geskriptet
		-- endet (siehe PrologueOrchestrator.lua) -- der Spieler soll sichtbar Schaden
		-- machen können, auch wenn der Ausgang feststeht. =====
		AlertThresholdLevel5 = 900,
		GuardianHP = 60000,
		GuardianShieldHP = 10000,
		GuardianShieldRegenDelay = 10,
		-- Anteil des MAXIMALSCHILDS pro Sekunde. War 0.04 und damit staerker als der
		-- Spielerschaden: bei 2200 Schaden je Schlag regenerierte der Schild mit rund
		-- 105 % des DPS. Elf Sekunden Pause kosteten dadurch den gesamten
		-- Schildfortschritt, und der Kampf war nach einer Unterbrechung praktisch
		-- zurueckgesetzt. Jetzt 0.005 -- eine Achtelung.
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 60,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 30,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},
}

-- Fallback-Werte, falls eine Stadt mal ohne eigenen Eintrag verwendet wird (sollte nicht
-- passieren, ist aber eine sichere Rückfalloption statt eines harten Fehlers).
CityAlertConfig.DefaultCity = {
	AlertThresholdLevel2 = 500,
	AlertThresholdLevel3 = 2000,
	AlertPerHP = 0.3,
	FireEngineHP = 2000,
	FireEngineCount = 1,
	FireEngineSpeed = 16,
	FirefightingRate = 40,
	FirefightingRange = 48,
	FireEngineDestroyAlertValue = 60,
	WaterTowerEfficiencyBonus = 0,
	AlertDecayDelay = 20,
	AlertDecayRate = 15,
	BarricadeScale = 1.0,
	ShieldMaxHealth = 3000,
	ShieldRegenDelay = 8,
	ShieldRegenRate = 0.05,
	GeneratorMaxHealth = 400,
	ElectricDamage = 10, -- Schaden pro Stromschlag am Elektrozaun (skaliert mit Stadtgrösse)
	EscalationStepSize = 5,
	MaxActiveReactiveBarricades = 3,
	ReactiveSpawnSearchRadius = 150,
	FlankAutoDetectRadius = 40,

	-- ===== Stufe 4: Militär (Panzer, Raketenwerfer, Militär-Helikopter) =====
	-- War 2000 und damit IDENTISCH mit AlertThresholdLevel3 -- Stufe 3 und 4 haetten in
	-- einer unbekannten Stadt gleichzeitig ausgeloest und die Eskalation uebersprungen.
	-- Jetzt dem 4x-Muster folgend.
	AlertThresholdLevel4 = 8000,
	-- War 5, obwohl hier weder eine Stufe-5-Schwelle noch Guardian-Werte stehen: die
	-- Rueckfall-Konfiguration versprach eine Stufe, die sie nicht liefern kann. Eine
	-- unbekannte Stadt eskaliert deshalb bis 4. Wer eine neue Stadt aufnimmt, gibt ihr
	-- einen eigenen Eintrag in Cities -- der Rueckfall ist ein Notnagel, kein Vorbild.
	MaxAlertLevel = 4,
	MilitaryTankCount = 1,
	MilitaryRocketLauncherCount = 1,
	MilitaryHelicopterCount = 1,
	TankHP = 5000,
	TankDamage = 12,
	TankAttackRange = 60,
	TankSpeed = 12,
	RocketLauncherHP = 3000,
	RocketLauncherDamage = 14,
	RocketLauncherAttackRange = 100,
	HelicopterHP = 2500,
	HelicopterDamage = 10,
	HelicopterAttackRange = 80,
	HelicopterSpeed = 18,
}

function CityAlertConfig.GetCityConfig(cityName)
	return CityAlertConfig.Cities[cityName] or CityAlertConfig.DefaultCity
end

return CityAlertConfig