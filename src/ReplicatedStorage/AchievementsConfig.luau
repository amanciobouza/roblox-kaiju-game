-- VERSION: 2026-08-21 #3
-- ModuleScript: AchievementsConfig
-- Ort in Studio: ReplicatedStorage
--
-- Zentrale Liste aller Achievements. Reine Daten -- Freischaltungs-Logik läuft in
-- AchievementService.lua (Server) + Anzeige in NavigationClient.lua (Client).
--
-- Jedes Achievement hat:
--   id          -- eindeutige ID (wird als Attribut-Name-Bestandteil genutzt)
--   category    -- Anzeige-Gruppe im Panel
--   icon        -- Emoji fürs Panel
--   name        -- Anzeige-Name
--   description -- Bedingung, für Spieler verständlich formuliert
--   type        -- "counter" (Fortschrittsbalken bis threshold) oder "flag" (nur an/aus)
--   threshold   -- nur bei type="counter": Zielwert
--   dormant     -- true = Bedingung kann aktuell NICHT erfüllt werden (fehlendes System,
--                  z.B. CITY BROKEN, Megacity-Guardian, Jaeger/Ronin-Spielbarkeit) --
--                  wird im Panel als "🔒 Kommt später" markiert statt normal gesperrt.

local AchievementsConfig = {}

AchievementsConfig.Categories = {
	"Zerstörung",
	"Alert-Eskalation",
	"Stadt-Kontrolle",
	"Berserker & Meltdown",
	"Fortschritt",
	"Spezialangriffe",
	"Charaktere",
}

AchievementsConfig.List = {
	-- ===== 1. Zerstörung =====
	{ id = "FirstCracks", category = "Zerstörung", icon = "🧱", name = "Erste Risse", description = "10 Gebäude zerstört", type = "counter", threshold = 10, counterKey = "BuildingsDestroyed" },
	{ id = "WreckingBall", category = "Zerstörung", icon = "🏚️", name = "Abrissbirne", description = "100 Gebäude zerstört", type = "counter", threshold = 100, counterKey = "BuildingsDestroyed" },
	{ id = "Ravager", category = "Zerstörung", icon = "💥", name = "Verwüster", description = "500 Gebäude zerstört", type = "counter", threshold = 500, counterKey = "BuildingsDestroyed" },
	{ id = "Apocalypse", category = "Zerstörung", icon = "☄️", name = "Apokalypse", description = "2'000 Gebäude zerstört", type = "counter", threshold = 2000, counterKey = "BuildingsDestroyed" },

	-- ===== 2. Alert-Eskalation =====
	{ id = "Noticed", category = "Alert-Eskalation", icon = "🚨", name = "Bemerkt", description = "Zum ersten Mal Alert-Level 1 ausgelöst", type = "flag" },
	{ id = "EmergencyDefeated", category = "Alert-Eskalation", icon = "🚒", name = "Notfall", description = "Erste Feuerwehr besiegt (Level 2)", type = "flag" },
	{ id = "BreakthroughAchieved", category = "Alert-Eskalation", icon = "🚧", name = "Durchbruch", description = "Erste Barrikade durchbrochen (Level 3)", type = "flag" },
	{ id = "WarZone", category = "Alert-Eskalation", icon = "🪖", name = "Kriegsgebiet", description = "Erste Militär-Einheit besiegt (Level 4)", type = "flag" },
	{ id = "GuardianSlayer", category = "Alert-Eskalation", icon = "🤖", name = "Guardian-Bezwinger", description = "Ersten Guardian besiegt (Level 5)", type = "flag" },
	{ id = "SerialOffender", category = "Alert-Eskalation", icon = "🔁", name = "Serientäter", description = "Level 5 in 3 verschiedenen Städten erreicht", type = "counter", threshold = 3 },

	-- ===== 3. Stadt-Kontrolle (CITY BROKEN -- noch nicht gebaut) =====
	{ id = "FirstCityBroken", category = "Stadt-Kontrolle", icon = "💀", name = "Erste Stadt gebrochen", description = "1 Stadt komplett zu Fall gebracht", type = "flag", dormant = true },
	{ id = "NoPlaceSafe", category = "Stadt-Kontrolle", icon = "🌍", name = "Kein Ort ist sicher", description = "Alle freigeschalteten Städte mindestens einmal gebrochen", type = "flag", dormant = true },

	-- ===== 4. Berserker & Meltdown =====
	{ id = "LossOfControl", category = "Berserker & Meltdown", icon = "🔥", name = "Kontrollverlust", description = "Zum ersten Mal Berserk aktiviert", type = "flag" },
	{ id = "CoreMeltdown", category = "Berserker & Meltdown", icon = "☢️", name = "Kernschmelze", description = "Zum ersten Mal Meltdown erreicht (Heat 100+)", type = "flag" },
	{ id = "AtTheLimit", category = "Berserker & Meltdown", icon = "🌡️", name = "Am Limit", description = "Heat auf 110 gebracht", type = "flag" },
	{ id = "TrialByFire", category = "Berserker & Meltdown", icon = "🛡️", name = "Feuerprobe", description = "Meltdown überlebt, ohne zu sterben (10×)", type = "counter", threshold = 10 },

	-- ===== 5. Fortschritt =====
	{ id = "FirstSteps", category = "Fortschritt", icon = "👣", name = "Erste Schritte", description = "Spieler-Level 10 erreicht", type = "flag" },
	{ id = "TitanLevel", category = "Fortschritt", icon = "🗿", name = "Titan", description = "Spieler-Level 25 erreicht", type = "flag" },
	{ id = "FullyTrained", category = "Fortschritt", icon = "💯", name = "Vollständig trainiert", description = "Arm, Bein UND Körper gleichzeitig auf Cap", type = "flag" },

	-- ===== 6. Spezialangriffe =====
	{ id = "Focused", category = "Spezialangriffe", icon = "🎯", name = "Fokussiert", description = "50× Fokus-Angriff genutzt", type = "counter", threshold = 50 },
	{ id = "FieldOfFire", category = "Spezialangriffe", icon = "🌋", name = "Flächenbrand", description = "50× Flächenangriff genutzt", type = "counter", threshold = 50 },
	{ id = "EnergyMaster", category = "Spezialangriffe", icon = "⚡", name = "Energiemeister", description = "10'000 Special Energy insgesamt gesammelt", type = "counter", threshold = 10000 },

	-- ===== 7. Charaktere (Trenchborn) =====
	{ id = "KaijuAwakens", category = "Charaktere", icon = "🦖", name = "Kaiju erwacht", description = "Kaiju zum ersten Mal gespielt", type = "flag" },
	{ id = "KaijuCompleted", category = "Charaktere", icon = "🏆", name = "Kaiju durchgespielt", description = "Mit Kaiju den Guardian in Megacity besiegt", type = "flag", dormant = true },
	{ id = "JaegerUnlocked", category = "Charaktere", icon = "🤖", name = "Jaeger freigeschaltet", description = "Jaeger zum ersten Mal freigeschaltet", type = "flag" },
	{ id = "JaegerCompleted", category = "Charaktere", icon = "🏆", name = "Jaeger durchgespielt", description = "Mit Jaeger den Guardian in Megacity besiegt", type = "flag", dormant = true },
	{ id = "RoninUnlocked", category = "Charaktere", icon = "🐯", name = "Ronin freigeschaltet", description = "Ronin zum ersten Mal freigeschaltet", type = "flag" },
	{ id = "RoninCompleted", category = "Charaktere", icon = "🏆", name = "Ronin durchgespielt", description = "Mit Ronin den Guardian in Megacity besiegt", type = "flag", dormant = true },
	{ id = "Trinity", category = "Charaktere", icon = "☯️", name = "Trinität", description = "Alle drei Fraktionen freigeschaltet", type = "flag" },
	{ id = "MasterOfAllBlades", category = "Charaktere", icon = "👑", name = "Meister aller Klingen", description = "Mit allen drei Fraktionen den Megacity-Guardian besiegt", type = "flag", dormant = true },
}

-- Schneller Zugriff per ID.
AchievementsConfig.ById = {}
for _, achievement in ipairs(AchievementsConfig.List) do
	AchievementsConfig.ById[achievement.id] = achievement
end

return AchievementsConfig