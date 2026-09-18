-- VERSION: 2026-08-25 #4
-- Ort in Studio: ReplicatedStorage
-- Definiert alle kaufbaren Kaiju-Stufen. Unterscheiden sich durch Werte (Leben verdoppelt
-- sich pro Stufe) -- KEINE feste Farbe mehr, der Avatar behält seine eigene (vom Spieler
-- gewählte) Farbe. Kein Mesh-Tausch -- einfach & zuverlässig.
--
-- ===== Steckbrief =====
-- Role und Strength werden im Skin-Auswahl-Bildschirm gezeigt UND vom Archiv gelesen
-- (siehe ArchiveConfig) -- deshalb stehen sie hier, neben den Zahlen, die sie beschreiben,
-- und nicht in einer Anzeige-Konfiguration. Zwei Felder statt der drei des Archivs: eine
-- "Schwäche" hat eine Kaufstufe nicht, sie ist schlicht besser als die vorherige.
--
-- Die Texte beschreiben, was TATSÄCHLICH passiert -- keine Absichten. Ein Steckbrief ist
-- die Grundlage einer Kaufentscheidung; was er zusagt, muss das Spiel einlösen. Die
-- Charakterzüge der drei Fraktionen (Power / Control / Purpose) stehen bewusst woanders,
-- auf den Karten im Fraktions-Panel.
--
-- ===== Keine Level-Obergrenze mehr =====
-- Früher deckelte jeder Skin das Level: ohne Kauf war bei 10 Schluss, jeder gekaufte Skin
-- hob die Grenze um weitere 10. Das machte den Kauf zur Pflicht und den Fortschritt zur
-- Sperre -- wer nicht kaufte, sammelte XP ins Leere.
--
-- Jetzt begrenzt kein Skin mehr das Level. Der Kaufgrund sind stattdessen die Werte
-- selbst: Leben UND Angriff. Ein Spieler kann mit dem Riftborn auf Stufe 50 kommen --
-- er schlägt dann nur halb so hart zu wie jemand im Aeon Tyrant.
--
-- ===== Die fünf Stufen der Kaiju-Reihe =====
-- Riftborn, Ironpulse, Epochbreaker, Chronovore, Aeon Tyrant -- vom Wesen aus dem Riss der
-- Tiefe bis zum Herrscher über die Ewigkeit. Der Uhrenbezug bleibt subtil: Ironpulse ist
-- Herzschlag und Uhrentakt zugleich, Chronovore verschlingt die Zeit selbst.
--
-- Fünf, nicht sechs: die Spec verlangt fünf Stufen je Figur (Specs/BalancingSpec), und die
-- sechste (Stufe 50) ist mit dieser Reihe entfallen. Speicherstände, die sie noch führen,
-- hebt die Migration 4 -> 5 in PlayerSetup auf die neue oberste Stufe.
--
-- ACHTUNG: Diese Namen haben NICHTS mit den Modellnamen des Workshops zu tun
-- ("Stage_1_Primal_Beast" und so weiter, siehe StageModels). Die kommen aus dem
-- Asset-Paket und bleiben, wie sie sind -- der Installer sucht seine Teile danach.
--
-- Damit endet die Reihe bei 1600 Leben statt bei 3200 und bei Stufe 40 statt 50 -- die
-- Werte der bisherigen Stufen sind unverändert, nur die Spitze fehlt.
--
-- ===== DamagePercent =====
-- Hier stand einmal ein Feld "Damage", das entfernt wurde, weil es NIRGENDS gelesen wurde:
-- ein Steckbrief hätte eine Zahl versprochen, die keine Wirkung hat. DamagePercent ist der
-- Ersatz, und er wird tatsächlich angewandt (PlayerSetup.recalculateStrength multipliziert
-- den aus ArmPower berechneten Schaden damit). 100 heisst unverändert, 225 heisst
-- zweieinviertelfacher Schaden.
--
-- Die Zahl steigt in Schritten von 25 statt sich wie das Leben zu verdoppeln. Der Schaden
-- wächst ohnehin schon über das Arm-Training; verdoppelte er sich zusätzlich je Stufe,
-- wäre die Kurve am Ende nicht mehr zu balancieren.

local SkinsConfig = {}

-- ===== Die drei Fraktionen =====
-- Die Skinliste unten enthält bislang NUR Kaiju-Stufen. Jaeger und Ronin sind trotzdem
-- hier aufgeführt: der Auswahl-Bildschirm zeigt ihre Plätze als gesperrte Fragezeichen,
-- damit die Lücke sichtbar ist statt verschwiegen. Das Archiv hält es genauso.
--
-- PendingStages sind die vorgesehenen Stufen, solange die echten Einträge fehlen -- mit
-- NAMEN, nicht nur als Anzahl. Vorher stand hier eine blosse Zahl, und die Plätze hiessen
-- im Spiel "Jaeger 1" bis "Jaeger 5"; jetzt stehen dort die geplanten Namen, auch wenn es
-- die Figuren noch nicht gibt.
--
-- Die Anzahl ergibt sich aus der Liste. Eine Zahl NEBEN der Liste zu führen hiesse, zwei
-- Dinge im Gleichschritt zu halten, die auseinanderlaufen, sobald jemand nur eines ändert.
--
-- Diese Liste liest AUCH das Archiv (ArchiveConfig.PendingFactionSkins) und der
-- Auswahl-Bildschirm. Sobald eine Fraktion echte Skins bekommt, verschwindet das Feld --
-- die Skinliste ist dann die Wahrheit.
--
-- Zeit bedeutet für jede Figur etwas anderes: der Kaiju überwältigt sie, der Jaeger
-- beherrscht ihren Takt, der Ronin erkennt den richtigen Moment. Stufe 3 zeigt das am
-- klarsten -- Epochbreaker zerstört eine Ära, Epochkeeper bewahrt sie, Fatecarver bestimmt
-- ihren weiteren Verlauf.
SkinsConfig.Factions = {
	{
		Key = "Kaiju",
		Label = "Kaiju",
		Icon = "🦖",
		Chapter = "Chapter I",
	},
	{
		Key = "Jaeger",
		Label = "Jaeger",
		Icon = "🤖",
		Chapter = "Chapter II",
		-- Vom ersten Funken zum ewigen Wächter.
		PendingStages = { "Sparkbound", "Steelpulse", "Epochkeeper", "Chronarch", "Aeon Sentinel" },
		UnlockHint = "The faction itself unlocks by defeating the MegaCity Guardian as Kaiju.",
	},
	{
		Key = "Ronin",
		Label = "Ronin",
		Icon = "🐯",
		Chapter = "Chapter III",
		-- Vom Suchenden zum unvergänglichen Beschützer.
		PendingStages = { "Dawnstrider", "Oathclaw", "Fatecarver", "Momentblade", "Eternal Ronin" },
		UnlockHint = "The faction itself unlocks by defeating the MegaCity Guardian as Jaeger.",
	},
}

SkinsConfig.Skins = {
	{
		Id = 0,
		Faction = "Kaiju",
		Name = "Riftborn",
		Role = "Where every Kaiju starts. Free, and never required to leave -- it simply hits the softest.",
		Strength = "None to speak of. Lowest health, slowest pace, shortest jump, and the baseline for attack power -- every later stage is strictly better.",
		RequiredLevel = 0,
		Cost = 0, -- Startskin, kostenlos
		Health = 100,
		DamagePercent = 100,
		WalkSpeed = 14,
		Scale = 1.00, -- 30 Studs. Siehe den Block bei GetScale.
		SanctuaryScale = 0.80, -- 24 Studs
		AttackAnimationId = "", -- z.B. "rbxassetid://123456789" nach dem Export aus dem Animation Editor
	},
	{
		Id = 1,
		Faction = "Kaiju",
		Name = "Ironpulse",
		Role = "The first real step up, from level 10.",
		Strength = "Twice the health of the starting form, a quarter more attack power and a third more speed. Half again as tall, and it jumps about a third higher.",
		RequiredLevel = 10,
		Cost = 150,
		Health = 200,
		DamagePercent = 125,
		WalkSpeed = 18,
		Scale = 1.35, -- 45 Studs
		SanctuaryScale = 0.80, -- 27 Studs
		AttackAnimationId = "",
	},
	{
		Id = 2,
		Faction = "Kaiju",
		Name = "Epochbreaker",
		Role = "The middle of the line, from level 20.",
		Strength = "400 health, half again the attack power of the starting form, and a stride two thirds longer. Twice the height of the starting form -- tall enough that walking through a street damages what stands along it.",
		RequiredLevel = 20,
		Cost = 400,
		Health = 400,
		DamagePercent = 150,
		WalkSpeed = 23,
		Scale = 1.60, -- 60 Studs
		SanctuaryScale = 0.79, -- 30 Studs
		AttackAnimationId = "",
	},
	{
		Id = 3,
		Faction = "Kaiju",
		Name = "Chronovore",
		Role = "The last form before the end stage, from level 30.",
		Strength = "800 health, three quarters more attack power, and two and a half times the height of the starting form -- enough to come down on most rooftops from above.",
		RequiredLevel = 30,
		Cost = 1000,
		Health = 800,
		DamagePercent = 175,
		WalkSpeed = 29,
		Scale = 1.75, -- 75 Studs
		SanctuaryScale = 0.77, -- 33 Studs
		AttackAnimationId = "",
	},
	{
		Id = 4,
		Faction = "Kaiju",
		Name = "Aeon Tyrant",
		Role = "The end stage, from level 40. Nothing follows it.",
		Strength = "1600 health -- sixteen times the starting form -- double its attack power, more than two and a half times its speed, and three times its height. At this size, buildings take damage from being brushed past.",
		RequiredLevel = 40,
		Cost = 2500,
		Health = 1600,
		DamagePercent = 200,
		WalkSpeed = 37,
		Scale = 1.85, -- 90 Studs
		SanctuaryScale = 0.74, -- 36 Studs
		AttackAnimationId = "",
	},
}

-- Alle Skins einer Fraktion, in Listenreihenfolge. Leer, solange es keine gibt.
function SkinsConfig.GetSkinsByFaction(factionKey)
	local result = {}
	for _, skin in ipairs(SkinsConfig.Skins) do
		if (skin.Faction or "Kaiju") == factionKey then
			table.insert(result, skin)
		end
	end
	return result
end

-- ===== Wie gross eine Stufe IN EINER ZONE ist =====
-- Die eine Quelle für beides: die Skalierung des Avatars (PlayerSetup) UND die Bau-Grösse
-- des Kaiju-Modells (StageModels). Die zwei MÜSSEN übereinstimmen.
--
-- Warum so nachdrücklich: das Rig misst die Welt gegen den Rumpf des Avatars, skaliert
-- seine Toleranzen aber mit der Grösse des Modells. Liefen die beiden auseinander, stimmte
-- keine seiner Entfernungen mehr -- der Flächenangriff wurde wortlos verweigert, weil der
-- Boden angeblich zu weit weg war. Die Regel stand damals an zwei Orten.
--
-- ===== Draussen: die Leiter der Skalierungen =====
-- Die Werte sehen krumm aus, und das hat einen Grund: DAS MODELL WÄCHST SCHON VON SELBST.
-- Der Bauplan des Workshops gibt jeder Stufe eine eigene Eigenhöhe (KaijuEvolutionBlockout,
-- `height`): 1.00 / 1.12 / 1.26 / 1.43 / 1.62 mal 30 Studs. Er lässt die Figur vor allem
-- MASSIGER werden -- das Volumen steigt dabei auf das 3.6-fache, die Höhe nur auf das
-- 1.6-fache.
--
-- Hier stand einmal die glatte Reihe 1/2/3/4/5. Die multiplizierte ein zweites Mal auf die
-- Eigenhöhe und ergab 30 / 67 / 113 / 172 / 243 Studs -- das ACHTFACHE der ersten Stufe.
-- Bei 243 Studs steht die Kamera nach unserer eigenen Regel (Höhe mal 1.8) über vierhundert
-- Studs zurück, und die Stadt darunter ist Bodentextur.
--
-- Die Zahlen unten rechnen die Eigenhöhe heraus. Das Ergebnis ist die gerade Leiter, um die
-- es eigentlich geht:
--
--   Stufe 1   1.00  ->  30 Studs
--   Stufe 2   1.35  ->  45 Studs
--   Stufe 3   1.60  ->  60 Studs
--   Stufe 4   1.75  ->  75 Studs
--   Stufe 5   1.85  ->  90 Studs
--
-- Plus fünfzehn Studs je Stufe, dreifache Endhöhe. Der Machtzuwachs kommt weiterhin an, nur
-- über die Masse statt über die Höhe -- so ist die Reihe entworfen.
--
-- WER HIER ÄNDERT, ändert auch die Steckbriefe oben mit: sie nennen die Vielfachen beim
-- Namen, und ein Steckbrief muss einlösen, was er zusagt.
--
-- ===== Im Sanctuary: alle klein und fast gleich gross =====
-- Die friedliche Startzone -- dort soll niemand über die Häuser ragen, und der Unterschied
-- zwischen Anfänger und Endausbau soll die Zone NICHT sprengen.
--
-- Hier wurde derselbe Fehler zweimal gemacht: eine gleichmässig steigende Zahl (erst
-- 0.5/0.6/0.7/0.8/0.9, dann 0.80/0.85/0.90/0.95/1.00), die die Eigenhöhe des Modells
-- übersah. Weil die von 1.00 auf 1.62 wächst, stand am Ende trotzdem eine doppelt so hohe
-- Figur da -- 24 gegen 48.6 Studs, und genau das war zu sehen.
--
-- Deshalb steht die Sanctuary-Grösse jetzt als EIGENE Zahl je Stufe, genau wie die Grösse
-- für draussen und aus derselben Rechnung: Zielhöhe geteilt durch die Eigenhöhe. Ergibt
-- 24 / 27 / 30 / 33 / 36 Studs -- die Hälfte Unterschied über die ganze Reihe, statt des
-- Doppelten. Zwei Zahlen je Stufe sind es wert, wenn die eine sonst still lügt.
--
-- Fehlt das Feld, bleibt es bei der Grösse von draussen: lieber sichtbar zu gross als eine
-- Figur, die aus einer stillen Null verschwindet.

function SkinsConfig.GetScale(skin, isSanctuary)
	local scale = skin and skin.Scale or 1
	if isSanctuary and skin and skin.SanctuaryScale then
		scale = skin.SanctuaryScale
	end
	if scale ~= scale or scale <= 0 then
		return 1 -- NaN oder Unsinn: lieber Originalgrösse als eine Figur, die verschwindet
	end
	return scale
end

function SkinsConfig.GetSkinById(id)
	for _, skin in ipairs(SkinsConfig.Skins) do
		if skin.Id == id then
			return skin
		end
	end
	return nil
end

return SkinsConfig