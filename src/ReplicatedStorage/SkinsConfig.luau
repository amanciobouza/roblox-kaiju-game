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
-- Die Level-Freischaltung wird NICHT hier beschrieben: jeder gekaufte Skin hebt die
-- Obergrenze um 10 (siehe PlayerSetup.getLevelCap), und der Bildschirm rechnet sie aus.
--
-- ENTFERNT: das Feld "Damage". Es wurde im ganzen Projekt nirgends gelesen -- der Schaden
-- kommt aus ArmPower (siehe PlayerSetup.recalculateStrength). Ein Steckbrief hätte damit
-- eine Zahl versprochen, die keine Wirkung hat.

local SkinsConfig = {}

SkinsConfig.Skins = {
	{
		Id = 0,
		Name = "Baby Kaiju",
		Role = "Where every Kaiju starts. Free, and the only form below level 10.",
		Strength = "None to speak of. It has the lowest health, the slowest pace and the shortest jump of the six -- every later stage is strictly better.",
		RequiredLevel = 0,
		Cost = 0, -- Startskin, kostenlos
		Health = 100,
		WalkSpeed = 14,
		Scale = 1, -- weiter reduziert von 1.33 auf 1, war immer noch zu gross
		AttackAnimationId = "", -- z.B. "rbxassetid://123456789" nach dem Export aus dem Animation Editor
	},
	{
		Id = 1,
		Name = "Young Kaiju",
		Role = "The first real step up, from level 10.",
		Strength = "Twice the health of the starting form and a third more speed. Twice as tall, which roughly doubles how high a jump attack reaches.",
		RequiredLevel = 10,
		Cost = 150,
		Health = 200,
		WalkSpeed = 18,
		Scale = 2, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
	{
		Id = 2,
		Name = "Adult Kaiju",
		Role = "The middle of the line, from level 20.",
		Strength = "400 health and a stride half again as long as the Baby form's. Tall enough that walking through a street damages what stands along it.",
		RequiredLevel = 20,
		Cost = 400,
		Health = 400,
		WalkSpeed = 23,
		Scale = 3, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
	{
		Id = 3,
		Name = "Elder Kaiju",
		Role = "The last form before the two titans, from level 30.",
		Strength = "800 health, and a jump that carries about four times as high as the starting form's -- enough to come down on most rooftops from above.",
		RequiredLevel = 30,
		Cost = 1000,
		Health = 800,
		WalkSpeed = 29,
		Scale = 4, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
	{
		Id = 4,
		Name = "Atomic Titan",
		Role = "The first of the two end forms, from level 40.",
		Strength = "1600 health and more than two and a half times the starting speed. At this size, buildings take damage from being brushed past.",
		RequiredLevel = 40,
		Cost = 2500,
		Health = 1600,
		WalkSpeed = 37,
		Scale = 5, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
	{
		Id = 5,
		Name = "Radiant Apex",
		Role = "The final form, from level 50. Nothing follows it.",
		Strength = "3200 health -- thirty-two times the Baby form -- the longest stride and the highest jump in the game. Little in a city can stop it directly.",
		RequiredLevel = 50,
		Cost = 6000,
		Health = 3200,
		WalkSpeed = 47,
		Scale = 6, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
}

function SkinsConfig.GetSkinById(id)
	for _, skin in ipairs(SkinsConfig.Skins) do
		if skin.Id == id then
			return skin
		end
	end
	return nil
end

return SkinsConfig