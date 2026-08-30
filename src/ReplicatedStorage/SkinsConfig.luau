-- VERSION: 2026-08-25 #4
-- Ort in Studio: ReplicatedStorage
-- Definiert alle kaufbaren Kaiju-Stufen. Unterscheiden sich durch Werte (Schaden & Leben
-- verdoppeln sich pro Stufe) -- KEINE feste Farbe mehr, der Avatar behält seine eigene
-- (vom Spieler gewählte) Farbe. Kein Mesh-Tausch -- einfach & zuverlässig.

local SkinsConfig = {}

SkinsConfig.Skins = {
	{
		Id = 0,
		Name = "Baby Kaiju",
		RequiredLevel = 0,
		Cost = 0, -- Startskin, kostenlos
		Health = 100,
		Damage = 8,
		WalkSpeed = 14,
		Scale = 1, -- weiter reduziert von 1.33 auf 1, war immer noch zu gross
		AttackAnimationId = "", -- z.B. "rbxassetid://123456789" nach dem Export aus dem Animation Editor
	},
	{
		Id = 1,
		Name = "Young Kaiju",
		RequiredLevel = 10,
		Cost = 150,
		Health = 200,
		Damage = 16,
		WalkSpeed = 18,
		Scale = 2, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
	{
		Id = 2,
		Name = "Adult Kaiju",
		RequiredLevel = 20,
		Cost = 400,
		Health = 400,
		Damage = 32,
		WalkSpeed = 23,
		Scale = 3, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
	{
		Id = 3,
		Name = "Elder Kaiju",
		RequiredLevel = 30,
		Cost = 1000,
		Health = 800,
		Damage = 64,
		WalkSpeed = 29,
		Scale = 4, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
	{
		Id = 4,
		Name = "Atomic Titan",
		RequiredLevel = 40,
		Cost = 2500,
		Health = 1600,
		Damage = 128,
		WalkSpeed = 37,
		Scale = 5, -- vereinfacht auf lineare 1-6-Skala
		AttackAnimationId = "",
	},
	{
		Id = 5,
		Name = "Radiant Apex",
		RequiredLevel = 50,
		Cost = 6000,
		Health = 3200,
		Damage = 256,
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