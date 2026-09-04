-- ModuleScript: ShowdownConfig
-- Ort in Studio: ReplicatedStorage
--
-- Der Showdown: der Zweikampf zwischen Spieler und Guardian, den das Spiel filmisch
-- inszeniert, während der Spieler weiterkämpft.
--
-- Die Absicht hinter jedem Wert steht in Specs/ShowdownSpec.luau -- hier stehen nur die
-- Zahlen. Sie sind bewusst alle an EINER Stelle, weil fast jede davon eine Gefühlsfrage
-- ist, die im Studio gedreht werden muss und nicht am Schreibtisch entschieden werden kann.

local ShowdownConfig = {}

-- ===== Auslösen und Beenden =====

-- Beide müssen sich innerhalb dieser Spanne getroffen haben. "Gegenseitig" ist genau das,
-- was einen Kampf von einem Überfall unterscheidet: wer einmal draufhaut und wegläuft,
-- hat keinen angefangen.
ShowdownConfig.TriggerWindow = 6

-- Vor Ablauf dieser Zeit gibt es keinen Ausstieg. Ohne sie könnte der Filmstreifen für
-- zwei Sekunden aufblitzen und wieder verschwinden -- das Mittel verlöre seine Wirkung.
ShowdownConfig.MinimumDuration = 15

-- Der Aufgeben-Knopf muss gehalten werden. Im Eifer eines Bosskampfs trifft man Knöpfe,
-- die man nicht treffen wollte, und ein versehentliches Aufgeben nimmt dem Spieler genau
-- den Moment weg, auf den die ganze Eskalation hinauslief.
ShowdownConfig.GiveUpHoldTime = 0.7

-- Nach dem Aufgeben startet mit diesem Guardian eine Weile kein neuer Showdown. Ohne die
-- Sperre wäre der Knopf wirkungslos: der Spieler steht ja weiter vor dem Guardian, und
-- beim nächsten Schlagabtausch käme der Filmstreifen sofort zurück.
ShowdownConfig.ReentryLockAfterGiveUp = 45

-- ===== Kamera =====

ShowdownConfig.Camera = {
	-- Nicht exakt seitlich: 90 Grad wäre die reine Bühnenansicht, flach wie ein
	-- Bühnenbild. Etwas schräg gibt Tiefe und lässt den Guardian massiger wirken, ohne
	-- dass links und rechts ihren Sinn verlieren.
	ObliqueAngle = 20,

	-- Die Kamera bleibt stehen und stellt sich erst neu auf, wenn sich die Achse zwischen
	-- den beiden um mehr als diesen Winkel gedreht hat. Eine dauernd mitgleitende Kamera
	-- wirkt wie ein Karussell und nimmt dem Bild die Ruhe, aus der der einzelne
	-- Angriffs-Shot später seine Wirkung zieht.
	RestageThresholdDegrees = 35,
	RestageDuration = 0.6,

	-- Höhe und Abstand werden aus der Grösse des GRÖSSEREN Kämpfers abgeleitet, nicht fest
	-- gesetzt: zwischen Baby Kaiju und Radiant Apex liegt Faktor sechs, ein fester Wert
	-- kann nicht für beide stimmen.
	HeightFactor = 0.18, -- Anteil der Höhe des grösseren Kämpfers
	MinHeight = 6,
	DistanceFactor = 1.9, -- Vielfaches des Abstands der beiden, mindestens aber:
	MinDistance = 60,

	FieldOfView = 62,

	-- Einfahrt beim Start. Die Steuerung bleibt dabei aktiv -- eine erzwungene Pause in
	-- einem Kampf, den man gerade angefangen hat, fühlt sich nach Unterbrechung an.
	EntryDuration = 1.2,

	-- Rückgabe bei Aufgeben, Tod und gerissener Leine.
	ExitDuration = 0.8,

	-- Der Sieg über den Guardian ist der Höhepunkt der gesamten Alarmstufen-Eskalation.
	-- Ihn in denselben 0,8 Sekunden abzuräumen wie ein Weglaufen wäre eine vertane
	-- Gelegenheit.
	VictoryShotDuration = 2.5,
}

-- ===== Angriffs-Shots =====

-- Höchstens ein Shot in dieser Spanne. Der Guardian schlägt alle 3 Sekunden zu; bekäme
-- jeder Angriff einen Shot, würde die Kamera im Sekundentakt schneiden -- aus Regie
-- würde Zappeln.
ShowdownConfig.ShotMinimumGap = 6

-- Bei Gleichzeitigkeit gewinnt der Guardian: SEINEN Angriff muss der Spieler kommen
-- sehen. Den eigenen kennt er schon, er hat ihn ausgelöst.
ShowdownConfig.ShotPriority = { Guardian = 2, Player = 1 }

-- Jeder Shot schneidet HART hinein und fährt WEICH zurück. Der Schnitt gibt dem Angriff
-- den Schlag, die Rückfahrt nimmt dem Ganzen das Hektische -- und nach der Rückfahrt
-- steht die Kamera garantiert wieder richtig zur Achse, auch wenn die beiden sich
-- während des Shots gedreht haben.
--
--   source     Wer angreift -- entscheidet über den Vorrang.
--   style      Welche Kamerafahrt der Client spielt.
--   duration   Wie lange der Shot steht, bevor zurückgefahren wird.
--   originPart Teil, an dem der Shot ansetzt. Nil = Wurzelteil des Angreifers.
ShowdownConfig.Shots = {
	FocusLaser = {
		source = "Player",
		style = "BeamTravel", -- fährt am Strahl entlang zum Ziel
		duration = 2.2,
		originPart = "Head", -- der Fokusstrahl tritt am Kopf aus
	},
	AreaAttack = {
		source = "Player",
		style = "LowRise", -- tief am Boden, während die Ladung wächst
		duration = 1.2,
	},
	WarningPulse = {
		source = "Guardian",
		style = "ChestLow", -- von unten auf den Brustkern
		duration = 0.6,
		originPart = "ChestCore",
	},
	ContainmentNet = {
		source = "Guardian",
		style = "MuzzleClose", -- dicht an die Austrittsöffnung
		duration = 1.35,
		originPart = "LaunchMouth",
	},
	ShoulderMissiles = {
		source = "Guardian",
		style = "LaunchLow", -- vom Boden schräg hoch an die Startschächte
		duration = 1.4,
		originPart = "LauncherFace",
	},
}

-- ===== Ansatzphase der Guardian-Flächenangriffe =====
--
-- Diese drei Angriffe teilen ihren Schaden erst NACH der Ansatzphase aus. Vorher traf der
-- Schaden sofort und der Effekt lief hinterher -- die Telegraph-Zeiten in den
-- Workshop-Konfigurationen beschrieben eine Absicht, die nie eingelöst wurde.
--
-- Die Kanonen (TwinIonCannons, PulseCannonFire) und der Schockstab bleiben bewusst sofort:
-- ein Nahkampfschlag SOLL schnell sein, sonst wird der Guardian im Nahbereich zahnlos.
--
-- Die Werte sind an die Effekte gebunden, nicht frei gewählt -- Effekt und Schaden müssen
-- zusammenfallen, sonst schlägt etwas ein, das man noch fliegen sieht:
--   Warden  0.60 -- entspricht WARNING_PULSE_TELEGRAPH in CityDefenderService
--   Marshal 1.35 -- der Wert ist in GuardianCombatVFX fest verdrahtet und weicht von der
--                   MarshalRoadblockGameplayConfig (1.2) ab; hier gilt der Code, weil der
--                   die sichtbare Wirkung bestimmt.
--   Aegis   1.40 -- überschreibt die LockDuration (2.0) der Workshop-Konfiguration. Zwei
--                   Sekunden wären so lang, dass man aus dem Wirkradius spazieren kann.
ShowdownConfig.GuardianTelegraph = {
	WardenShepherd = 0.6,
	MarshalRoadblock = 1.35,
	AegisInterceptor = 1.4,
}

-- ===== Filmstreifen =====

ShowdownConfig.Letterbox = {
	-- Schmaler als im Prolog (9 %): hier bleiben Lebensbalken und Angriffsknöpfe
	-- sichtbar und brauchen den Platz.
	BarHeightFraction = 0.06,
	FadeDuration = 0.4,
}

-- ===== HUD =====
--
-- Was während des Showdowns verschwindet. Lebensanzeige, Guardian-Lebensbalken,
-- Angriffsknöpfe und die Berserker-Anzeige bleiben -- ohne sie kann man nicht kämpfen.
ShowdownConfig.HiddenGuis = { "NavigationGui", "TeleportHomeGui", "DebugPanelGui" }

-- Einzelne Kinder von GameHud, die verschwinden. Der Rest des HUD bleibt stehen.
ShowdownConfig.HiddenHudChildren = { "CoinsLabel" }

-- ===== Debug =====

-- Verkürzte Mindestdauer für den Debug-Schalter: die Ausstiege durchzuspielen, ohne
-- jedes Mal fünfzehn Sekunden zu warten.
ShowdownConfig.DebugMinimumDuration = 3

return ShowdownConfig
