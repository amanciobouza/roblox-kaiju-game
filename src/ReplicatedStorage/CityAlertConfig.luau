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
		ExpectedSkinStage = 1, -- Riftborn; die Spec verlangt die Angabe je Stadt
		-- Alert Level 1 -> 2: wie viel Alert-Fortschritt nötig ist, bis die Feuerwehr anrückt
		--
		-- Die Zahlen kommen aus der Village-Spezifikation und sind dort in Durchgängen
		-- gedacht: das ganze Dorf einmal abzuräumen ergibt rund 49 Punkte. Stufe 2 nach
		-- einem Durchgang, Stufe 3 nach viereinhalb -- und danach City Broken, was zusammen
		-- die zwanzig Minuten Referenzzeit ergibt.
		--
		-- Vorher standen hier 100 und 400, also zwei und acht Durchgänge. Im Testlauf war
		-- die Folge, dass Stufe 3 nach dreizehn Minuten aktiven Spiels noch nicht erreicht
		-- war und City Broken damit unerreichbar blieb. Der Fortschritt zerfällt übrigens
		-- nur, solange KEIN Spieler in der Stadt ist -- Aussitzen hilft also nicht, die
		-- Schwellen sind das Einzige, was zählt.
		-- ===== Die Schwellen zaehlen in DURCHGAENGEN (18.09.2026) =====
		-- Ein Durchgang ist das einmalige Abraeumen aller Gebaeude der Stadt. Brasshaven ist
		-- darauf ausgelegt und bestaetigt sich selbst: 0.39 / 0.90 / 1.42 / 2.26. Daran sind
		-- jetzt alle Staedte gemessen.
		--
		-- Das Village ergibt gemessene 48 Alarmpunkte je Durchgang (23 Gebaeude, alle mit
		-- eigenem AlertValue-Attribut aus Studio -- AlertPerHP unten ist hier nur Rueckfall
		-- und ohne Wirkung). Vorher standen die Schwellen bei 50 / 225 / 1600 / 6400, also
		-- 1.0 / 4.7 / 33 / 133 Durchgaengen: Stufe 4 haette 33 vollstaendige Dorfrunden
		-- verlangt und war damit unerreichbar.
		AlertThresholdLevel2 = 19, -- 0.40 Durchgaenge
		-- Alert Level 2 -> 3: Barrikaden-Schild-Cluster (siehe BarricadeClusterService.lua)
		AlertThresholdLevel3 = 43, -- 0.90 Durchgaenge
		-- Alert-Wert pro HP eines zerstörten Gebäudes (AlertValue = MaxHealth * AlertPerHP),
		-- falls das Gebäude kein eigenes "AlertValue"-Attribut in Studio gesetzt hat.
		AlertPerHP = 0.5,

		-- Die Spezifikation setzt fuer die Feuerwehr eine Referenz-Aufraeumzeit von rund
		-- einer Minute an, Verfolgung eingerechnet. Mit 300 Lebenspunkten waren das
		-- gegen den Eintrittsschaden von 17 nur 18 Schlaege oder nicht einmal zwei
		-- Fokus-Angriffe -- ein Fokus allein macht 255. Das war kein Auftrag, das war ein
		-- Zwischenfall.
		--
		-- Der Wert stammt aus der Zeit vor der Massstabs-Korrektur, als der Grundschaden
		-- noch bei 8 lag und die Flaeche beim 1,75-fachen. Er ist mitgewachsen: 900
		-- ergeben 53 Schlaege oder dreieinhalb Fokus-Angriffe.
		FireEngineHP = 900,
		-- Zwei statt einem. Nicht wegen der Lebenspunkte, sondern wegen der WIRKUNG: ein
		-- einzelnes Fahrzeug loescht bei 24 Gebaeuden zu wenig, um den Ertrag spuerbar zu
		-- druecken -- und genau das ist laut Spezifikation seine Aufgabe. Die Vorgabe
		-- nennt 1 bis 3; das Village bleibt damit im Rahmen.
		FireEngineCount = 2,
		FireEngineSpeed = 14, -- Studs/Sekunde
		FirefightingRate = 8, -- Energie/Sekunde, die ein Feuerwehrauto einer Feuerquelle entzieht
		FirefightingRange = 45, -- Studs -- muss so nah dran sein, um zu löschen
		-- FireEngineDestroyAlertValue ist ENTFALLEN (war 15), wie in SmallTown: besiegte
		-- Verteidigung darf die Lage nicht verschärfen (Specs/BalancingSpec,
		-- balancing.defense-does-not-escalate). Sonst bestraft das Spiel genau das, wozu es
		-- auffordert -- und die Feuerwehr stehen zu lassen wird zur vernünftigen Spielweise.

		WaterTowerEfficiencyBonus = 0.5, -- +50% Löschrate, solange der Wasserturm intakt ist

		AlertDecayDelay = 20, -- Sekunden NACH dem Verlassen der Stadt, bevor der Abbau beginnt
		-- Alert-Punkte/Sekunde, die danach abgebaut werden. Der Abbau läuft NUR, solange
		-- kein Spieler in der Stadt ist (siehe CityAlertService, cityEmptySince) --
		-- Aussitzen innerhalb der Stadt bringt nichts.
		--
		-- Vorher 4/s, und das machte Alarmstufe 3 praktisch unerreichbar: bei einer
		-- Schwelle von 225 war nach 76 Sekunden Abwesenheit ALLES weg. Im Testlauf gab es
		-- zwei Trainingsausflüge von gut zwei Minuten, und beide Male fiel der Alarm von
		-- Stufe 2 auf 0 zurück -- viereinhalb Dorf-Durchgänge Fortschritt, gelöscht.
		--
		-- Die Spezifikation will, dass ein Rückzug den Lauf VERLÄNGERT, nicht dass er ihn
		-- zurücksetzt. Bei 0.5/s kostet ein zweiminütiger Ausflug rund 50 Punkte, also
		-- genau einen Dorf-Durchgang. Spürbar, aber aufholbar.
		AlertDecayRate = 0.5,

		-- ===== Stufe 3: Barrikaden-Schild-Cluster =====
		-- ===== Auf denselben Massstab gebracht wie Brasshaven (18.09.2026) =====
		-- Das Village ist fuer den Spieler ausgelegt, der es mit dem Riftborn BETRITT: 18
		-- Schaden je Schlag, 270 ueber einen Fokusstrahl, 100 Lebenspunkte.
		--
		-- Gemessen an den Trefferzahlen Brasshavens war hier alles zugleich zu zaeh UND zu
		-- toedlich: der Panzer hielt 277 Schlaege (Brasshaven: 74) und toetete in acht
		-- Treffern (Brasshaven: 33). Wer die erste Stadt des Spiels betritt, traf damit auf
		-- den haertesten Gegner, den das Spiel ueberhaupt kennt.
		--
		-- Feuerwehr (50 Schlaege) und Elektrozaun (33 Treffer) standen bereits richtig.
		--
		-- Die Schadenswerte sind grob gestuft, weil der Riftborn nur 100 Leben hat: ein
		-- ganzzahliger Schritt ist hier gleich ein Sprung von acht Treffern. Die Reihenfolge
		-- Brasshavens bleibt erhalten -- Helikopter am mildesten, Raketenwerfer am haertesten.
		BarricadeScale = 1.0,
		ShieldMaxHealth = 1050,
		ShieldRegenDelay = 8,
		ShieldRegenRate = 0.05,
		GeneratorMaxHealth = 250,
		-- Dasselbe Grundmass wie in Brasshaven: rund 32 Treffer, bis die Figur fällt. Der
		-- Riftborn hat 100 Leben, also 3 Schaden je Stromschlag.
		--
		-- Vorher 10, und das waren zehn Treffer. Der Zaun ist die einzige Verteidigung, die
		-- das Village in Kapitel I überhaupt einsetzt -- Militär und Guardian kommen dort
		-- erst in den späteren Kapiteln --, und damit war er die härteste Bedrohung des
		-- ganzen ersten Kapitels. Die übrigen Village-Werte bleiben unangetastet, solange
		-- sie nicht gespielt werden.
		ElectricDamage = 3, -- Stromschlag am Elektrozaun -- 33 Treffer
		EscalationStepSize = 5,
		MaxActiveReactiveBarricades = 3,
		ReactiveSpawnSearchRadius = 150,
		FlankAutoDetectRadius = 40,

		-- ===== Stufe 4: Militär (Panzer, Raketenwerfer, Militär-Helikopter) =====
		AlertThresholdLevel4 = 68, -- 1.42 Durchgaenge
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
		TankHP = 1350,
		TankDamage = 3, -- 33 Treffer,
		TankAttackRange = 60,
		TankSpeed = 12,
		RocketLauncherHP = 1000,
		RocketLauncherDamage = 4, -- 25 Treffer -- der haerteste des Militaers,
		RocketLauncherAttackRange = 100,
		HelicopterHP = 800,
		HelicopterDamage = 2, -- 50 Treffer,
		HelicopterAttackRange = 80,
		HelicopterSpeed = 18,


		-- ===== Stufe 5: Guardian =====
		-- Erreichbar erst ab Kapitel III (siehe MaxAlertLevelByChapter oben) -- in Kapitel I
		-- bleibt diese Stadt darunter, die Werte liegen dann brach.
		AlertThresholdLevel5 = 110, -- 2.29 Durchgaenge
		-- ===== Was der Guardian einbringt =====
		-- FEST, nicht zur Laufzeit gerechnet -- so verlangt es die Spec
		-- (balancing.every-defeat-pays). Bis hierher gab dieser Guardian GAR NICHTS: ein
		-- Kampf ohne Ertrag, den zu umgehen die vernuenftige Spielweise war.
		--
		-- Hergeleitet aus dem einzigen durchgerechneten Fall, Brasshaven: dort sind 30 000
		-- Lebenspunkte 80 000 Erfahrung wert, also 35 mal HP^0.75 -- dieselbe gedaempfte
		-- Kurve wie bei Gebaeuden und Verteidigung, nur hoeher angesetzt. Der Village-Guardian erscheint erst in Kapitel III.
		--
		-- VORLAEUFIG: diese Stadt ist noch nicht durchgespielt. Die Zahl ist eine
		-- begruendete Ausgangsgroesse, keine gemessene -- sie gehoert nachgeschaerft, sobald
		-- die Stadt tatsaechlich gespielt wird.
		-- ===== Der Guardian muss eine Herausforderung bleiben =====
		-- Massstab ist Brasshaven, die einzige durchgerechnete Stadt: 310 Schlaege (rund 21
		-- Fokusstrahlen) bis der Guardian faellt, und 16 Fausttreffer bis der Spieler faellt
		-- -- doppelt so gefaehrlich wie alles andere in der Stadt.
		--
		-- Der Eintrittsschaden hier ist 18 je Schlag (Trainingskappe auf Level 0 mal
		-- DamagePercent). Vorher: 1 556 Schlaege -- fuenfmal Brasshaven, und die Faust toetete in vier Treffern.
		--
		-- Die alten Werte hingen an nichts: in allen drei oberen Staedten stand derselbe
		-- kopierte Satz "bei 2200 Schaden je Schlag".
		GuardianXPReward = 18000,
		GuardianCoinsReward = 270,
		GuardianHP = 4000,
		GuardianShieldHP = 1600, -- 40% der HP, wie bei LargeCity und MegaCity
		GuardianShieldRegenDelay = 10,
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 6,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 3,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	-- ===== Brasshaven, durchgerechnet =====
	-- Ausgelegt für den Spieler, der die Stadt mit Level 10 und dem Ironpulse BETRITT. Sein
	-- Schaden ist dann 135 je Schlag, 2025 über einen vollen Fokusstrahl, 675 je Fläche
	-- (Arm auf der Obergrenze, keine Talente, allein). Zum Vergleich: im Village sind es 18,
	-- 270 und 90 -- der Spieler schlägt hier also siebeneinhalbmal so hart zu.
	--
	-- GENAU DAS war der Fehler in den alten Zahlen: sie waren gegenüber dem Village mal drei
	-- gerechnet, nicht mal siebeneinhalb. Das Feuerwehrauto fiel dadurch in elf Schlägen
	-- statt in fünfzig, der Generator in sieben. Brasshaven war in Trefferzahlen LEICHTER
	-- als das Dorf davor.
	--
	-- Die Stadt trägt den Spieler von Level 10 auf 20. Das kostet 561 138 XP -- das
	-- 8,4-fache der gesamten Village-Strecke, weil die XP-Kurve ab Level 10 geometrisch mit
	-- 1.25 wächst.
	--
	-- GEMESSEN am 18.09.2026 (Serverbericht "Durchgang SmallTown", siehe CityAlertService):
	-- ein voller Durchgang gibt 319 274 XP. Die Strecke sind also 1,8 Durchgänge. Das ist
	-- der kürzeste Wert aller Städte und damit die Vorlage -- im Village sind es gemessen
	-- 3,3, in City 9,6.
	--
	-- Die Gebäude-Lebenspunkte dazu stehen NICHT hier, sondern in Studio an den Modellen
	-- (siehe balancing.building-values-live-in-config im Rückstand). Die Rechnung geht von
	-- Stufen aus -- L1 2 000, L2 6 000, L3 12 000 --, das sind 15, 45 und 89 Schläge beim
	-- Eintritt. Wer die Werte dort ändert, muss die Schwellen hier nachziehen.
	--
	-- ACHTUNG bei den mehrteiligen Bauwerken: Supermarkt, Schule, Motel und die zwei
	-- Brücken bestehen aus je DREI angreifbaren Abschnitten. In Studio stehen sie auf
	-- 3 500 je Flügel und 5 000 für den Kern -- zusammen also die 12 000 der Stufe L3, und
	-- damit bleibt die Trefferzahl fürs ganze Bauwerk bei 89. Der Kern hält mit 38 Schlägen
	-- am längsten, die Flügel fallen in 26.
	--
	-- Der Ertrag steigt durch die Aufteilung, und das ist kein Fehler: die Belohnung wächst
	-- mit HP^0.75, drei Teile geben also mehr als ein Ganzes derselben Grösse. Ein
	-- zerlegbares Bauwerk lohnt sich mehr als ein massives -- 59 angreifbare Teile statt 49.
	--
	-- Die Alarmpunkte folgen der Gesamt-HP. Ob die Brücken auf L2 oder wie die drei anderen
	-- auf L3 stehen, verschiebt einen Durchgang nur zwischen 1 560 und 1 680 Punkten -- die
	-- Schwellen unten liegen in beiden Fällen im Zielband.
	SmallTown = {
		ExpectedSkinStage = 2, -- Ironpulse; die Spec verlangt die Angabe je Stadt

		-- ===== Die Alarmschwellen in Durchgängen =====
		-- GEMESSEN am 18.09.2026: ein Durchgang sind 59 angreifbare Teile, 155 200
		-- Lebenspunkte und 1 552 Alarmpunkte (AlertPerHP 0.01, kein Gebäude trägt ein
		-- eigenes AlertValue). Die Schwellen unten liegen damit bei 0.39, 0.90, 1.42 und
		-- 2.26 Durchgängen. City Broken fällt so mit dem Ende der Level-Strecke zusammen,
		-- statt weit dahinter.
		--
		-- Diese vier Verhältnisse sind der Massstab, an dem inzwischen ALLE Städte gemessen
		-- werden (siehe die Schwellen-Kommentare dort).
		--
		-- Vorher: 400 / 1 600 / 6 400 bei AlertPerHP 0.35. Ein einziges L1-Haus gab damit
		-- 700 Punkte -- Alarmstufe 2 nach EINEM Haus, Stufe 4 nach neun. Die Eskalation war
		-- vorbei, bevor der Spieler die Stadt gesehen hatte.
		AlertThresholdLevel2 = 600,
		AlertThresholdLevel3 = 1400,
		AlertPerHP = 0.01,

		-- Fünfzig Schläge oder dreieinhalb Fokusstrahlen, also rund eine Minute mit
		-- Verfolgung -- dieselbe Referenz, die im Village ausdrücklich gesetzt wurde.
		FireEngineHP = 6800,
		FireEngineCount = 2,
		FireEngineSpeed = 16,
		-- ===== So viel, dass Ignorieren etwas kostet =====
		-- Ein brennendes Gebäude gibt 60 Prozent seiner Energie über die Brenndauer ab: bei
		-- 2 000 Lebenspunkten sind das 2 692 Energie über 30 Sekunden, also rund 90 je
		-- Sekunde. Zwei Fahrzeuge zu je 30 schafften davon zwei Drittel.
		--
		-- Im Village ist es genau austariert: zwei Fahrzeuge zu je 8 gegen 15.9 je Sekunde --
		-- sie neutralisieren ein Feuer vollständig. Genau das ist laut Spezifikation ihre
		-- Aufgabe, den Ertrag spürbar zu drücken. 45 stellt dasselbe Verhältnis her.
		--
		-- Damit war die Feuerwehr doppelt folgenlos: sie fiel in elf Schlägen (siehe
		-- FireEngineHP darüber, inzwischen korrigiert), UND sie zu ignorieren kostete kaum
		-- etwas. Das eine ohne das andere zu beheben hätte die Hälfte stehen gelassen.
		FirefightingRate = 45,
		FirefightingRange = 50,
		-- FireEngineDestroyAlertValue ist ENTFALLEN: besiegte Verteidigung darf die Lage
		-- nicht verschärfen (Specs/BalancingSpec, balancing.defense-does-not-escalate). Der
		-- Aufrufer in FireEngineController verträgt das Fehlen -- addCityAlert steigt bei
		-- fehlendem Betrag aus.

		-- Brasshaven HAT einen Wasserturm (SmallTown_WaterTower_L1), aber er ist Kulisse:
		-- bewusst ohne Wirkung auf die Löschrate der Feuerwehr. Hier stand vorher "hat
		-- aktuell keinen eigenen Wasserturm" -- das war schlicht falsch und hätte beim
		-- nächsten Durchgang zu der Frage geführt, warum das Ding dort steht.
		--
		-- Soll er wirken wie im Village, braucht es zweierlei: diesen Wert über null UND das
		-- Attribut HeatEffect = "WaterTower" am Modell in Studio. Eines allein tut nichts.
		WaterTowerEfficiencyBonus = 0,

		AlertDecayDelay = 20,
		-- Von 12 auf 3: bei den neuen Schwellen hätte 12/s den Fortschritt bis Stufe 3 in
		-- zwei Minuten Abwesenheit gelöscht. Genau dieser Fehler ist im Village schon
		-- einmal aufgefallen -- ein Trainingsausflug darf eine Stadt nicht zurücksetzen.
		AlertDecayRate = 3,

		BarricadeScale = 1.5,
		-- Sechzig Schläge, vier Fokusstrahlen. Der Generator ist der Schwachpunkt und fällt
		-- in fünfzehn -- wer ihn findet, spart sich die Wand.
		--
		-- IM SPIEL BESTÄTIGT am 18.09.2026: "Ich musste Zeit investieren, lange. Es hat
		-- sich aber nicht unnötig blöd angefühlt." Das ist die einzige Art Nachweis, die es
		-- für diese Länge gibt -- sie steht hier, damit die 8 000 nicht bei der nächsten
		-- Runde als "zu zäh" gekürzt werden. Wer sie ändert, verwirft ein Spielurteil, kein
		-- Rechenergebnis.
		ShieldMaxHealth = 8000,
		ShieldRegenDelay = 8,
		ShieldRegenRate = 0.05,
		GeneratorMaxHealth = 2000,
		-- ===== Wie hart die Stadt zurückschlägt =====
		-- Das Grundmass: der Ironpulse hat 200 Leben und soll rund 32 Treffer des
		-- gewöhnlichen Verteidigers aushalten -- also gut 6 Schaden je Treffer. Die Werte
		-- unten behalten die bisherigen Verhältnisse zwischen den Systemen und sind nur auf
		-- dieses Mass heruntergerechnet; vorher lagen sie bei 25 bis 35, was sieben Treffer
		-- bedeutet hätte.
		--
		-- Der Guardian ist die Ausnahme und soll es sein: seine Faust nimmt in sechzehn
		-- Treffern alles, ist also doppelt so gefährlich wie der Rest.
		--
		-- Schaden wird ungemindert über Humanoid:TakeDamage angewandt -- es gibt keine
		-- Rüstung und keine Abschwächung, die Rechnung ist also direkt.
		ElectricDamage = 6, -- Stromschlag am Elektrozaun -- 33 Treffer
		EscalationStepSize = 5,
		MaxActiveReactiveBarricades = 3,
		ReactiveSpawnSearchRadius = 150,
		FlankAutoDetectRadius = 40,

		-- ===== Stufe 4: Militär (Panzer, Raketenwerfer, Militär-Helikopter) =====
		-- 1.4 Durchgänge. Danach ist alles Besiegbare besiegt und City Broken fällt mit dem
		-- Ende der Level-Strecke zusammen.
		AlertThresholdLevel4 = 2200,
		MaxAlertLevel = 4, -- Konzept-Vorgabe: nicht jede Stadt kennt alle Alert-Stufen
		-- Ab Kapitel II erreicht SmallTown Stufe 5 samt Guardian. Wie beim Village gilt:
		-- ohne AlertThresholdLevel5 bleibt es faktisch bei 4, bis die Schwelle gesetzt ist.
		MaxAlertLevelByChapter = { 4, 5, 5 },
		MilitaryTankCount = 2,
		MilitaryRocketLauncherCount = 1,
		MilitaryHelicopterCount = 1,
		-- 75 / 55 / 45 Schläge beim Eintritt, also 5 / 3.7 / 3 Fokusstrahlen. Bewusst NICHT
		-- aus den Village-Zahlen fortgeschrieben: dessen Militär ist nie gespielt worden,
		-- das Village endet in Kapitel I bei Alarmstufe 3. 278 Schläge für einen Panzer,
		-- wie sie sich dort ergäben, wären ein Ausdauertest und kein Kampf.
		TankHP = 10000,
		TankDamage = 6, -- 33 Treffer
		TankAttackRange = 65,
		TankSpeed = 13,
		RocketLauncherHP = 7500,
		RocketLauncherDamage = 7, -- 28 Treffer -- der härteste des Militärs
		RocketLauncherAttackRange = 110,
		HelicopterHP = 6000,
		HelicopterDamage = 5, -- 40 Treffer -- er stört mehr, als er wehtut
		HelicopterAttackRange = 85,
		HelicopterSpeed = 19,

		-- ===== Stufe 5: Guardian =====
		-- Erreichbar erst ab Kapitel II (siehe MaxAlertLevelByChapter oben) -- in Kapitel I
		-- bleibt diese Stadt darunter, die Werte liegen dann brach.
		AlertThresholdLevel5 = 3500, -- 2.2 Durchgänge, knapp hinter Stufe 4
		-- ===== Was der Guardian einbringt =====
		-- FEST, nicht aus seinen Lebenspunkten gerechnet -- so verlangt es die Spec
		-- (balancing.every-defeat-pays): sein Wert soll für eine zügige Entwicklung fast
		-- notwendig erscheinen, ohne sie hart zu blockieren, und er darf NICHT dynamisch bis
		-- zum nächsten Level auffüllen. Nur so bleiben andere Spielweisen möglich.
		--
		-- 80 000 sind rund 14 Prozent der Strecke von Level 10 auf 20, oder knapp zwei
		-- Drittel eines Levelaufstiegs am oberen Ende. Gemessen an der Arbeit: ein voller
		-- Durchgang durch alle 59 Teile gibt gemessen 319 274 -- der Guardian ist also ein
		-- Viertel davon, für einen einzigen Kampf. Das ist deutlich, ohne alles andere
		-- überflüssig zu machen.
		--
		-- Die Münzen sind bewusst kein gleicher Anteil: der Preis der nächsten Stufe
		-- (Epochbreaker, 400) ist ohnehin schnell zusammen. Geld ist hier eine Zugabe, die
		-- Erfahrung ist der Grund.
		GuardianXPReward = 80000,
		GuardianCoinsReward = 1200,
		-- 220 Schläge plus 90 auf den Schild, zusammen rund 21 Fokusstrahlen. Der Guardian
		-- ist der längste Kampf der Stadt und soll es sein -- aber ein Kampf, kein Belagern.
		GuardianHP = 30000,
		GuardianShieldHP = 12000, -- 40% der HP, wie bei LargeCity und MegaCity
		GuardianShieldRegenDelay = 10,
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 12, -- 16 Treffer -- doppelt so gefährlich wie der Rest
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 6, -- 33 Treffer, dafür im Umkreis und mit Rückstoss
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	City = {
		ExpectedSkinStage = 3, -- Epochbreaker; die Spec verlangt die Angabe je Stadt
		AlertThresholdLevel2 = 28000, -- 0.39 Durchgaenge
		AlertThresholdLevel3 = 65000, -- 0.90 Durchgaenge
		AlertPerHP = 0.25,

		FireEngineHP = 8000,
		FireEngineCount = 2,
		FireEngineSpeed = 18,
		FirefightingRate = 140,
		FirefightingRange = 55,
		-- FireEngineDestroyAlertValue ist ENTFALLEN (war 180), wie in SmallTown: besiegte
		-- Verteidigung darf die Lage nicht verschärfen (Specs/BalancingSpec,
		-- balancing.defense-does-not-escalate).

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
		AlertThresholdLevel4 = 100000, -- 1.38 Durchgaenge
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
		AlertThresholdLevel5 = 160000, -- 2.20 Durchgaenge
		-- ===== Was der Guardian einbringt =====
		-- FEST, nicht zur Laufzeit gerechnet -- so verlangt es die Spec
		-- (balancing.every-defeat-pays). Bis hierher gab dieser Guardian GAR NICHTS: ein
		-- Kampf ohne Ertrag, den zu umgehen die vernuenftige Spielweise war.
		--
		-- Hergeleitet aus dem einzigen durchgerechneten Fall, Brasshaven: dort sind 30 000
		-- Lebenspunkte 80 000 Erfahrung wert, also 35 mal HP^0.75 -- dieselbe gedaempfte
		-- Kurve wie bei Gebaeuden und Verteidigung, nur hoeher angesetzt. Gut anderthalb Levelaufstiege auf dieser Hoehe der Kurve.
		--
		-- VORLAEUFIG: diese Stadt ist noch nicht durchgespielt. Die Zahl ist eine
		-- begruendete Ausgangsgroesse, keine gemessene -- sie gehoert nachgeschaerft, sobald
		-- die Stadt tatsaechlich gespielt wird.
		-- ===== Der Guardian muss eine Herausforderung bleiben =====
		-- Massstab ist Brasshaven, die einzige durchgerechnete Stadt: 310 Schlaege (rund 21
		-- Fokusstrahlen) bis der Guardian faellt, und 16 Fausttreffer bis der Spieler faellt
		-- -- doppelt so gefaehrlich wie alles andere in der Stadt.
		--
		-- Der Eintrittsschaden hier ist 614 je Schlag (Trainingskappe auf Level 20 mal
		-- DamagePercent). Vorher: 411 Schlaege, aber die Faust toetete in ZWEI Treffern.
		--
		-- Die alten Werte hingen an nichts: in allen drei oberen Staedten stand derselbe
		-- kopierte Satz "bei 2200 Schaden je Schlag".
		GuardianXPReward = 254000,
		GuardianCoinsReward = 3800,
		GuardianHP = 140000,
		GuardianShieldHP = 56000,
		GuardianShieldRegenDelay = 10,
		-- Anteil des MAXIMALSCHILDS pro Sekunde. War 0.04 und damit staerker als der
		-- Spielerschaden: bei 2200 Schaden je Schlag regenerierte der Schild mit rund
		-- 105 % des DPS. Elf Sekunden Pause kosteten dadurch den gesamten
		-- Schildfortschritt, und der Kampf war nach einer Unterbrechung praktisch
		-- zurueckgesetzt. Jetzt 0.005 -- eine Achtelung.
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 25,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 12,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	LargeCity = {
		ExpectedSkinStage = 4, -- Chronovore; die Spec verlangt die Angabe je Stadt
		AlertThresholdLevel2 = 19000, -- 0.38 Durchgaenge
		AlertThresholdLevel3 = 45000, -- 0.91 Durchgaenge
		AlertPerHP = 0.18,

		FireEngineHP = 50000,
		FireEngineCount = 3,
		FireEngineSpeed = 20,
		FirefightingRate = 700,
		FirefightingRange = 60,
		-- FireEngineDestroyAlertValue ist ENTFALLEN (war 650), wie in SmallTown: besiegte
		-- Verteidigung darf die Lage nicht verschärfen (Specs/BalancingSpec,
		-- balancing.defense-does-not-escalate).

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
		AlertThresholdLevel4 = 70000, -- 1.42 Durchgaenge
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
		AlertThresholdLevel5 = 110000, -- 2.22 Durchgaenge
		-- ===== Was der Guardian einbringt =====
		-- FEST, nicht zur Laufzeit gerechnet -- so verlangt es die Spec
		-- (balancing.every-defeat-pays). Bis hierher gab dieser Guardian GAR NICHTS: ein
		-- Kampf ohne Ertrag, den zu umgehen die vernuenftige Spielweise war.
		--
		-- Hergeleitet aus dem einzigen durchgerechneten Fall, Brasshaven: dort sind 30 000
		-- Lebenspunkte 80 000 Erfahrung wert, also 35 mal HP^0.75 -- dieselbe gedaempfte
		-- Kurve wie bei Gebaeuden und Verteidigung, nur hoeher angesetzt. Die Daempfung laesst den Guardian hier hinter die Levelkurve zuruecktreten -- bewusst: er soll die Entwicklung nicht ersetzen.
		--
		-- VORLAEUFIG: diese Stadt ist noch nicht durchgespielt. Die Zahl ist eine
		-- begruendete Ausgangsgroesse, keine gemessene -- sie gehoert nachgeschaerft, sobald
		-- die Stadt tatsaechlich gespielt wird.
		-- ===== Der Guardian muss eine Herausforderung bleiben =====
		-- Massstab ist Brasshaven, die einzige durchgerechnete Stadt: 310 Schlaege (rund 21
		-- Fokusstrahlen) bis der Guardian faellt, und 16 Fausttreffer bis der Spieler faellt
		-- -- doppelt so gefaehrlich wie alles andere in der Stadt.
		--
		-- Der Eintrittsschaden hier ist 1 780 je Schlag (Trainingskappe auf Level 30 mal
		-- DamagePercent). Vorher: 425 Schlaege, und die Faust toetete in eineinhalb Treffern.
		--
		-- Die alten Werte hingen an nichts: in allen drei oberen Staedten stand derselbe
		-- kopierte Satz "bei 2200 Schaden je Schlag".
		GuardianXPReward = 550000,
		GuardianCoinsReward = 8200,
		GuardianHP = 390000,
		GuardianShieldHP = 160000,
		GuardianShieldRegenDelay = 10,
		-- Anteil des MAXIMALSCHILDS pro Sekunde. War 0.04 und damit staerker als der
		-- Spielerschaden: bei 2200 Schaden je Schlag regenerierte der Schild mit rund
		-- 105 % des DPS. Elf Sekunden Pause kosteten dadurch den gesamten
		-- Schildfortschritt, und der Kampf war nach einer Unterbrechung praktisch
		-- zurueckgesetzt. Jetzt 0.005 -- eine Achtelung.
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 50,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 25,
		GuardianRepulsorCooldown = 6,
		GuardianRepulsorRadius = 22,
		GuardianRepulsorKnockback = 150,
		GuardianMoveSpeed = 15,
		GuardianProtectRadius = 30,
	},

	MegaCity = {
		ExpectedSkinStage = 5, -- Aeon Tyrant; die Spec verlangt die Angabe je Stadt
		AlertThresholdLevel2 = 5400000, -- 0.39 Durchgaenge
		AlertThresholdLevel3 = 12000000, -- 0.87 Durchgaenge
		AlertPerHP = 0.12,

		FireEngineHP = 300000,
		FireEngineCount = 3,
		FireEngineSpeed = 22,
		FirefightingRate = 3200,
		FirefightingRange = 65,
		-- FireEngineDestroyAlertValue ist ENTFALLEN (war 2400), wie in SmallTown: besiegte
		-- Verteidigung darf die Lage nicht verschärfen (Specs/BalancingSpec,
		-- balancing.defense-does-not-escalate).

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
		AlertThresholdLevel4 = 20000000, -- 1.45 Durchgaenge
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
		AlertThresholdLevel5 = 31000000, -- 2.25 Durchgaenge
		-- ===== Was der Guardian einbringt =====
		-- FEST, nicht zur Laufzeit gerechnet -- so verlangt es die Spec
		-- (balancing.every-defeat-pays). Bis hierher gab dieser Guardian GAR NICHTS: ein
		-- Kampf ohne Ertrag, den zu umgehen die vernuenftige Spielweise war.
		--
		-- Hergeleitet aus dem einzigen durchgerechneten Fall, Brasshaven: dort sind 30 000
		-- Lebenspunkte 80 000 Erfahrung wert, also 35 mal HP^0.75 -- dieselbe gedaempfte
		-- Kurve wie bei Gebaeuden und Verteidigung, nur hoeher angesetzt. Wie bei LargeCity traegt der Guardian hier nur noch einen Bruchteil eines Levels bei.
		--
		-- VORLAEUFIG: diese Stadt ist noch nicht durchgespielt. Die Zahl ist eine
		-- begruendete Ausgangsgroesse, keine gemessene -- sie gehoert nachgeschaerft, sobald
		-- die Stadt tatsaechlich gespielt wird.
		-- ===== Der Guardian muss eine Herausforderung bleiben =====
		-- Massstab ist Brasshaven, die einzige durchgerechnete Stadt: 310 Schlaege (rund 21
		-- Fokusstrahlen) bis der Guardian faellt, und 16 Fausttreffer bis der Spieler faellt
		-- -- doppelt so gefaehrlich wie alles andere in der Stadt.
		--
		-- Der Eintrittsschaden hier ist 34 568 je Schlag (Trainingskappe auf Level 40 mal
		-- DamagePercent). Vorher: nur 66 Schlaege -- der letzte Guardian des Spiels war der leichteste.
		--
		-- Die alten Werte hingen an nichts: in allen drei oberen Staedten stand derselbe
		-- kopierte Satz "bei 2200 Schaden je Schlag".
		GuardianXPReward = 5100000,
		GuardianCoinsReward = 77000,
		GuardianHP = 7700000,
		GuardianShieldHP = 3100000,
		GuardianShieldRegenDelay = 10,
		-- Anteil des MAXIMALSCHILDS pro Sekunde. War 0.04 und damit staerker als der
		-- Spielerschaden: bei 2200 Schaden je Schlag regenerierte der Schild mit rund
		-- 105 % des DPS. Elf Sekunden Pause kosteten dadurch den gesamten
		-- Schildfortschritt, und der Kampf war nach einer Unterbrechung praktisch
		-- zurueckgesetzt. Jetzt 0.005 -- eine Achtelung.
		GuardianShieldRegenRate = 0.005,
		GuardianImpactFistDamage = 100,
		GuardianImpactFistCooldown = 3,
		GuardianImpactFistRange = 14,
		GuardianImpactFistKnockback = 112,
		GuardianRepulsorDamage = 50,
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
		-- FireEngineDestroyAlertValue ist ENTFALLEN (war 20), wie in SmallTown: besiegte
		-- Verteidigung darf die Lage nicht verschärfen (Specs/BalancingSpec,
		-- balancing.defense-does-not-escalate).

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

-- ===== Was ein besiegtes Verteidigungssystem einbringt =====
-- Die Spec verlangt, dass JEDES besiegbare System mit Erfahrung UND Geld belohnt: Feuerwehr,
-- Barrikaden, Militär, Guardian (Specs/BalancingSpec, balancing.every-defeat-pays). Der
-- Grund steht dort: jede Stufe kostet Zeit und Risiko, und keine davon zu belohnen macht das
-- Ausschalten zur reinen Pflichtübung.
--
-- ===== Warum gerechnet und nicht je Stadt gesetzt =====
-- Vier Systeme mal sechs Städte wären vierundzwanzig Zahlenpaare, die jemand im Gleichschritt
-- halten müsste -- und sie hingen ohnehin alle an denselben Lebenspunkten, die weiter oben
-- schon stehen. Also aus den Lebenspunkten abgeleitet: wer die HP einer Stadt neu setzt,
-- bekommt die passende Belohnung geschenkt.
--
-- Die Formel ist DIESELBE wie bei den Gebäuden (HouseHandler, rewardFromHP): die Belohnung
-- wächst mit HP^0.75. Der Exponent unter eins bremst die Erträge bei riesigen Zielen -- ohne
-- ihn gäbe der MegaCity-Panzer absurde Zahlen.
--
-- Der Aufschlag von einem halben ist die einzige eigene Entscheidung hier: ein
-- Verteidigungssystem zu besiegen kostet mehr als ein Gebäude derselben Grösse einzureissen,
-- weil es sich wehrt. Das soll man sehen.
--
-- NICHT hierüber läuft der Guardian: sein Wert ist laut Spec FEST und steht je Stadt
-- (GuardianXPReward / GuardianCoinsReward). Er soll für eine zügige Entwicklung fast
-- notwendig erscheinen, und das lässt sich nicht aus seinen Lebenspunkten ableiten.
local DEFEAT_REWARD_EXPONENT = 0.75
local DEFEAT_XP_SCALE = 15 -- wie HouseHandler.XP_SCALE
local DEFEAT_COINS_SCALE = 1.2 -- wie HouseHandler.COINS_SCALE
local DEFEAT_RISK_BONUS = 1.5

function CityAlertConfig.DefeatReward(maxHealth)
	local hp = tonumber(maxHealth) or 0
	if hp <= 0 then
		return 0, 0
	end
	local basis = (hp ^ DEFEAT_REWARD_EXPONENT) * DEFEAT_RISK_BONUS
	return math.floor(basis * DEFEAT_XP_SCALE), math.floor(basis * DEFEAT_COINS_SCALE)
end

return CityAlertConfig