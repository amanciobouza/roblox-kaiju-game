-- Script: KaijuStabilityWatch
--
-- Meldet, wenn eine Kaiju-Figur umkippt -- und sagt dazu, womit sie steht.
--
-- ===== Warum =====
-- Am 21.09.2026 kippte die Figur beim Prologstart in der Stadt dauernd um. Ein Humanoid
-- faellt nicht einfach so: er wechselt dafuer in einen Zustand (FallingDown, Ragdoll,
-- PlatformStanding), und welcher es ist, sagt die Ursache.
--
-- Der Verdacht: die Figur hat seit der Hoehenangleichung ZWEI Kollisionskoerper.
--   * die R15-Glieder des Avatars -- hideAvatar setzt nur die Durchsichtigkeit, nicht
--     CanCollide, und der Avatar ist jetzt so gross wie das Modell
--   * "KaijuBodyCollider" -- ein Quader, den das Rig an die Figur schweisst, bemessen nach
--     der Groesse des MODELLS und mehrere Studs ueber dem Boden schwebend
-- Zwei verschieden geformte Koerper an derselben Baugruppe kippen auf unebenem Grund.
--
-- Dieses Skript BEWEIST oder WIDERLEGT das nur. Es aendert nichts -- nach den letzten Tagen
-- wollte ich erst messen und dann eingreifen.
--
-- ===== Was es kostet =====
-- Eine Verbindung je Spielerfigur, und die feuert nur bei Zustandswechseln. Kippt nichts,
-- steht nichts im Log.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StageModels = require(ReplicatedStorage:WaitForChild("StageModels", 30))

-- Die Zustaende, in denen eine Figur die Haltung verliert. Alles andere (Running, Jumping,
-- Freefall, Landed) ist normaler Betrieb und gehoert nicht ins Log.
local KIPPZUSTAENDE = {
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

-- Nicht bei jedem Wackler eine Zeile: waehrend eines Sturzes wechselt der Zustand mehrfach.
local MELDEABSTAND = 3
local letzteMeldung = setmetatable({}, { __mode = "k" })

local function koerper(character)
	local avatarTeile, kollidierend = 0, 0
	local collider
	for _, teil in ipairs(character:GetDescendants()) do
		if teil:IsA("BasePart") then
			if teil.Name == "KaijuBodyCollider" then
				collider = teil
			else
				local inModell = false
				local knoten = teil.Parent
				while knoten and knoten ~= character do
					if knoten:IsA("Model") then
						inModell = true
						break
					end
					knoten = knoten.Parent
				end
				if not inModell then
					avatarTeile += 1
					if teil.CanCollide then
						kollidierend += 1
					end
				end
			end
		end
	end
	return avatarTeile, kollidierend, collider
end

local function beobachte(player, character)
	local humanoid = character:WaitForChild("Humanoid", 15)
	if not humanoid then
		return
	end

	humanoid.StateChanged:Connect(function(_, neu)
		if not KIPPZUSTAENDE[neu] then
			return
		end
		if not StageModels.FindEquipped(character) then
			return -- blosser Avatar: das ist normales Roblox-Verhalten, kein Fall fuer uns
		end
		local jetzt = os.clock()
		if jetzt - (letzteMeldung[character] or 0) < MELDEABSTAND then
			return
		end
		letzteMeldung[character] = jetzt

		local hoehe = 0
		local ok, groesse = pcall(function()
			return character:GetExtentsSize()
		end)
		if ok and groesse then
			hoehe = groesse.Y
		end

		local avatarTeile, kollidierend, collider = koerper(character)
		warn(string.format(
			"[Kaiju Debug] Figur kippt (%s) -- Zustand %s, Figur %.0f Studs, HipHeight %.1f. "
				.. "Avatar: %d Teile, davon %d mit Kollision. Rig-Quader: %s.",
			player.Name, tostring(neu), hoehe, humanoid.HipHeight,
			avatarTeile, kollidierend,
			collider and string.format("%.0f x %.0f x %.0f, Kollision %s",
				collider.Size.X, collider.Size.Y, collider.Size.Z, tostring(collider.CanCollide))
				or "keiner"))
	end)
end

local function begleite(player)
	player.CharacterAdded:Connect(function(character)
		beobachte(player, character)
	end)
	if player.Character then
		beobachte(player, player.Character)
	end
end

Players.PlayerAdded:Connect(begleite)
for _, player in ipairs(Players:GetPlayers()) do
	begleite(player)
end

print("[Kaiju Debug] Stabilitaets-Beobachtung bereit -- meldet sich nur, wenn eine "
	.. "Kaiju-Figur die Haltung verliert.")
