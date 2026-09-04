-- ModuleScript: ArchiveConfig
-- Ort in Studio: ReplicatedStorage
--
-- Das Archiv: alle Feinde und alle Spielerfiguren, anfangs verdeckt. Aufgedeckt wird ein
-- Eintrag, sobald der Spieler der Figur im Spiel BEGEGNET ist -- Nähe genügt, besiegen
-- ist nicht nötig.
--
-- ===== Aufbau eines Eintrags =====
--   id          stabile Kennung. Geht so in den Speicherstand -- NIEMALS ändern, sonst
--               verlieren Spieler ihren Fortschritt. Der Anzeigename darf sich ändern.
--   category    Schlüssel aus Categories weiter unten.
--   name        Anzeigename.
--   hint        Fundort-Hinweis. Steht AUCH auf der verdeckten Karte -- er soll neugierig
--               machen, nicht auflösen. Bei der Stadtverteidigung die Alarmstufe, bei
--               Guardians und Figuren das Kapitel.
--   profile     Steckbrief: role / strength / weakness. Feindtexte stehen hier;
--               Figurentexte kommen von Amancio und sind bis dahin leer.
--   detect      Woran der ArchiveWatcher die Figur in der Welt erkennt (siehe unten).
--   model       Woher das Modell für die Vorschau kommt (siehe unten).
--   pending     true = existiert noch nicht. Solche Einträge zeigen NUR ein Fragezeichen,
--               ohne Silhouette: ein Umriss hiesse "such danach", und das wäre gelogen.
--
-- ===== detect =====
-- Der Wächter kennt die Feinde nicht von sich aus -- die Dienste melden ihm nichts (das
-- war eine bewusste Entscheidung: sechs laufende Systeme anzufassen wäre der grössere
-- Eingriff gewesen). Er erkennt sie deshalb an dem, was am Modell steht:
--   attribute = { name, value }   Attribut am Modell, z.B. UnitType = "Tank"
--   modelName = "..."             exakter Modellname
--   modelPrefix = "..."           Modellname beginnt damit (z.B. "Barricade_17")
-- ACHTUNG: das ist eine Kopplung an Namen. Benennt ein Dienst seine Modelle um, fällt der
-- Eintrag still aus -- deshalb gibt es dazu eine Spec-Regel.
--
-- ===== model =====
-- Für die Vorschau im ViewportFrame. Die meisten Feindmodelle liegen in ServerStorage und
-- sind für den Client unsichtbar; sie werden auf Anfrage geklont, wenn jemand das Archiv
-- öffnet (siehe ArchiveService).
--   serverStorage = "Name"                    direkt unter ServerStorage
--   serverStorageFolder = "Ordner", child = "Name"
--   workshopAsset = "WardenShepherd"          baut der Client selbst aus dem Workshop
--   avatarScale = 3.2                         Standard-Avatar in dieser Grösse (Skins
--                                             haben KEINE eigenen Modelle, siehe unten)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkinsConfig = require(ReplicatedStorage:WaitForChild("SkinsConfig"))

local ArchiveConfig = {}

-- Reihenfolge der Gruppen im Raster. Die vier Alarmstufen erzählen von oben nach unten
-- die Eskalation, wie der Spieler sie erlebt.
ArchiveConfig.Categories = {
	{ key = "Level1", label = "Level 1 — Surveillance", icon = "🚁" },
	{ key = "Level2", label = "Level 2 — Fire Brigade", icon = "🚒" },
	{ key = "Level3", label = "Level 3 — Barricades", icon = "🚧" },
	{ key = "Level4", label = "Level 4 — Military", icon = "🪖" },
	{ key = "Guardians", label = "Guardians", icon = "🤖" },
	{ key = "Figures", label = "Characters", icon = "☯️" },
}

-- Wie viele Skins je Fraktion vorgesehen sind, solange die echten Listen fehlen. Kaiju
-- kommt NICHT aus dieser Tabelle -- dort gibt es bereits sechs echte Einträge, die unten
-- aus SkinsConfig erzeugt werden.
ArchiveConfig.PendingFactionSkins = {}
for _, faction in ipairs(SkinsConfig.Factions) do
	if (faction.PendingCount or 0) > 0 then
		table.insert(ArchiveConfig.PendingFactionSkins, {
			faction = faction.Key,
			count = faction.PendingCount,
			chapter = faction.Chapter,
		})
	end
end

ArchiveConfig.Entries = {
	-- ===== Stufe 1 =====
	{
		id = "AlertHelicopter",
		category = "Level1",
		name = "Traffic Helicopter",
		hint = "Alert Level 1",
		detect = { modelPrefix = "AlertHelicopter_" },
		model = { serverStorage = "AlertHelicopterModel" },
		profile = {
			role = "The first sign that the city has noticed you. It circles the damage "
				.. "and follows whoever caused it.",
			strength = "Out of reach up there, and impossible to shake off -- while it "
				.. "circles, the city knows where you are.",
			weakness = "It deals no damage at all. Ignoring it costs you nothing but "
				.. "your peace of mind.",
		},
	},

	-- ===== Stufe 2 =====
	{
		id = "FireEngine",
		category = "Level2",
		name = "Fire Engine",
		hint = "Alert Level 2",
		detect = { modelName = "FireEngine" },
		model = { replicatedStorage = "FireEngine" },
		profile = {
			role = "Rolls out to burning buildings and puts the fires out.",
			strength = "It never hits you directly -- it hits your income. Extinguished "
				.. "fires yield no energy, so the longer it works, the less is left of "
				.. "what you destroyed.",
			weakness = "Unarmoured and slow. Taking it out first costs little time and "
				.. "pays off across the whole escalation.",
		},
	},

	-- ===== Stufe 3 =====
	{
		id = "Barricade",
		category = "Level3",
		name = "Barricade",
		hint = "Alert Level 3",
		detect = { modelPrefix = "Barricade_" },
		model = { serverStorageFolder = "BarricadeModels", child = "Barricade" },
		profile = {
			role = "Seals off streets and reroutes you. It does not attack -- it takes "
				.. "away the shortest path.",
			strength = "An electric fence between the generators hurts anyone who walks "
				.. "through. As long as the generators stand, the fence holds.",
			weakness = "The generators on the flanks are the real task. Once they fall, "
				.. "the barricade is nothing but an obstacle.",
		},
	},

	-- ===== Stufe 4 =====
	{
		id = "Tank",
		category = "Level4",
		name = "Tank",
		hint = "Alert Level 4",
		detect = { attribute = { name = "UnitType", value = "Tank" } },
		model = { serverStorageFolder = "MilitaryModels", child = "Tank" },
		profile = {
			role = "The heaviest ground unit. It hunts you down and stays until one of "
				.. "you is left standing.",
			strength = "The most hit points of any military unit and heavy single-target "
				.. "damage -- up close it is the most dangerous thing below a Guardian.",
			weakness = "Slow and bound to the ground. Keep moving and use height, and "
				.. "its strength counts for nothing.",
		},
	},
	{
		id = "RocketLauncher",
		category = "Level4",
		name = "Rocket Launcher",
		hint = "Alert Level 4",
		detect = { attribute = { name = "UnitType", value = "RocketLauncher" } },
		model = { serverStorageFolder = "MilitaryModels", child = "RocketLauncher" },
		profile = {
			role = "Keeps its distance and shells you from far away.",
			strength = "Long range. It hits you while you are busy with something else "
				.. "and forces you to carry the fight to it.",
			weakness = "Thinly armoured. Close the gap and it goes down fast.",
		},
	},
	{
		id = "Helicopter",
		category = "Level4",
		name = "Attack Helicopter",
		hint = "Alert Level 4",
		detect = { attribute = { name = "UnitType", value = "Helicopter" } },
		model = { serverStorageFolder = "MilitaryModels", child = "Helicopter" },
		profile = {
			role = "Attack from the air -- unlike the traffic helicopter, this one "
				.. "shoots back.",
			strength = "It uses the one plane that suits you least and stays outside "
				.. "your reach.",
			weakness = "Little armour. A jump attack that connects usually ends it "
				.. "outright.",
		},
	},

	-- ===== Guardians =====
	-- Erkannt am Attribut AssetName. GuardianGeneration taugt NICHT: der Warden setzt es
	-- als einziger nicht (nur Marshal und Aegis tun es).
	{
		id = "GuardianWardenShepherd",
		category = "Guardians",
		name = "Warden-I Shepherd",
		hint = "Chapter I",
		detect = { attribute = { name = "AssetName", value = "Warden-I Shepherd" } },
		model = { workshopAsset = "WardenShepherd" },
		profile = {
			role = "The first generation of Guardians. A sentry that covers a building "
				.. "and pushes you away from it rather than hunting you.",
			strength = "A shock baton up close and a warning pulse with area effect. "
				.. "Strike it, and it will chase you until you leave the city.",
			weakness = "It is tied to what it protects and never strays far. Lure it "
				.. "away and you buy yourself time elsewhere.",
		},
	},
	{
		id = "GuardianMarshalRoadblock",
		category = "Guardians",
		name = "Marshal-II Roadblock",
		hint = "Chapter I",
		detect = { attribute = { name = "AssetName", value = "Marshal-II Roadblock" } },
		model = { workshopAsset = "MarshalRoadblock" },
		profile = {
			role = "Second generation, built on the Warden. Instead of a baton it "
				.. "carries a shield, a pulse cannon and a containment net.",
			strength = "The shield absorbs almost all frontal damage. The cannon keeps "
				.. "you at range, the net keeps you in place.",
			weakness = "The shield covers one direction only. Get around it and you "
				.. "face an opponent with no cover at all.",
		},
	},
	{
		id = "GuardianAegisInterceptor",
		category = "Guardians",
		name = "Aegis-III Interceptor",
		hint = "Chapter I",
		detect = { attribute = { name = "AssetName", value = "Aegis-III Interceptor" } },
		model = { workshopAsset = "AegisInterceptor" },
		profile = {
			role = "Third generation, and the final opponent of the first chapter. It "
				.. "keeps its distance and fights you with ranged weapons.",
			strength = "Twin ion cannons and a missile salvo, behind a shield field it "
				.. "projects in front of itself.",
			weakness = "The shield field covers the front only and collapses once it is "
				.. "depleted. At range it has the advantage -- up close it does not.",
		},
	},
	{
		id = "GuardianGeneration4",
		category = "Guardians",
		name = "Fourth Generation",
		hint = "Chapter II",
		pending = true,
	},
	{
		id = "GuardianGeneration5",
		category = "Guardians",
		name = "Fifth Generation",
		hint = "Chapter III",
		pending = true,
	},
}

-- ===== Figuren =====
-- Die Kaiju-Stufen kommen aus SkinsConfig, damit die Anzahl nicht an zwei Orten steht --
-- kommt ein Skin dazu, wächst das Archiv von selbst mit.
--
-- WICHTIG: Skins haben KEINE eigenen Modelle. SkinsConfig sagt es wörtlich ("Kein
-- Mesh-Tausch"): ein Skin ist Scale, Health, Damage und WalkSpeed, sonst nichts. Die
-- Vorschau zeigt deshalb den Standard-Avatar in der jeweiligen Grösse -- sechs Karten,
-- die sich nur in der Grösse unterscheiden. Sobald es echte Modelle gibt, wird hier aus
-- avatarScale ein Modellverweis.
for _, skin in ipairs(SkinsConfig.Skins) do
	table.insert(ArchiveConfig.Entries, {
		id = "SkinKaiju" .. skin.Id, -- Id statt Name: der Anzeigename darf sich ändern
		category = "Figures",
		name = skin.Name,
		hint = "Chapter I",
		model = { avatarScale = skin.Scale },
		-- Beschreibung aus SkinsConfig, nicht hier: derselbe Text steht auch im
		-- Skin-Auswahl-Bildschirm, und zweimal gepflegt liefe er auseinander. "weakness"
		-- bleibt bei Figuren leer -- eine Kaufstufe hat keine, sie ist schlicht besser als
		-- die vorherige. Der Steckbrief zeigt nur Abschnitte, für die Text da ist.
		profile = (skin.Role or skin.Strength) and {
			role = skin.Role,
			strength = skin.Strength,
		} or nil,
	})
end

-- Jaeger und Ronin haben heute weder Skins noch ein eigenes Moveset. Die Plätze stehen
-- trotzdem schon da, weil sie fest geplant sind -- als Fragezeichen ohne Silhouette.
for _, faction in ipairs(ArchiveConfig.PendingFactionSkins) do
	for index = 1, faction.count do
		table.insert(ArchiveConfig.Entries, {
			id = "Skin" .. faction.faction .. index,
			category = "Figures",
			name = faction.faction .. " " .. index,
			hint = faction.chapter,
			pending = true,
		})
	end
end

-- Schneller Zugriff per Id, und die Einträge je Kategorie in Reihenfolge.
ArchiveConfig.ById = {}
ArchiveConfig.ByCategory = {}
for _, category in ipairs(ArchiveConfig.Categories) do
	ArchiveConfig.ByCategory[category.key] = {}
end
for _, entry in ipairs(ArchiveConfig.Entries) do
	ArchiveConfig.ById[entry.id] = entry
	local bucket = ArchiveConfig.ByCategory[entry.category]
	if bucket then
		table.insert(bucket, entry)
	else
		warn("[ArchiveConfig] Eintrag '" .. entry.id .. "' nennt die unbekannte Kategorie '"
			.. tostring(entry.category) .. "' -- er erscheint im Archiv nicht.")
	end
end

-- Nur die Einträge, die der Wächter überhaupt finden kann. Alles ohne 'detect' ist
-- entweder noch nicht gebaut oder eine Figur (die wird beim Ausrüsten aufgedeckt, nicht
-- durch Begegnung).
ArchiveConfig.Detectable = {}
for _, entry in ipairs(ArchiveConfig.Entries) do
	if entry.detect then
		table.insert(ArchiveConfig.Detectable, entry)
	end
end

return ArchiveConfig
