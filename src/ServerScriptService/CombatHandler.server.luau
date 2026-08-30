-- VERSION: 2026-08-25 #14
-- FIX: distanceToHouse gegen degenerierte Bounding Box (negativ/NaN) abgesichert
-- Ort in Studio: ServerScriptService
-- Verarbeitet Angriffe: beschädigt Häuser in Reichweite (PvE-Zone) und
-- greift andere Spieler an, aber NUR wenn beide sich in der PvP-Zone (Attack Zone) befinden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local AttackEvent = RemoteEventUtils.GetOrCreate("AttackEvent")
local ShowDamageEvent = RemoteEventUtils.GetOrCreate("ShowDamageEvent")

local ATTACK_RANGE = 8
local ATTACK_COOLDOWN = 0.8
local XP_PER_KILL = 250 -- ÷100 (war 25000) -- konsistent zur Energie-Formel-Korrektur
local PVP_ZONE_NAME = "PvP"
-- Dritter Schlag der Punch-Kombo (siehe AttackClient.lua: PunchLeft -> PunchRight ->
-- PunchAll) macht spürbar mehr Schaden -- motiviert dazu, die Dreierfolge abzuschließen,
-- ohne die Kombo insgesamt zu stark zu machen. Global exponiert, da TrainingHandler.lua
-- (Arm-Training am Titan Impact Gauntlet) denselben Wert für Konsistenz nutzt.
local THIRD_PUNCH_DAMAGE_MULTIPLIER = 1.25
_G.THIRD_PUNCH_DAMAGE_MULTIPLIER = THIRD_PUNCH_DAMAGE_MULTIPLIER

-- Für den Client sichtbar machen (fürs HUD, Sanduhr-Anzeige beim Schlag-Button)
local attackCooldownValue = Instance.new("NumberValue")
attackCooldownValue.Name = "AttackCooldown"
attackCooldownValue.Value = ATTACK_COOLDOWN
attackCooldownValue.Parent = ReplicatedStorage

local lastAttackTime = {}

-- Berechnet die Distanz von "position" zum NÄCHSTEN Punkt der gesamten Bounding-Box
-- des Hauses (statt nur zu einem einzelnen Teil) -- so ist das ganze Haus angreifbar,
-- egal von welcher Seite man kommt, nicht nur eine Ecke.
local function distanceToHouse(house, position)
	local ok, cframe, size = pcall(function()
		return house:GetBoundingBox()
	end)
	if not ok then
		return math.huge
	end

	local halfSize = size / 2

	-- WICHTIG: Bei Häusern, deren Teile gerade während der Kollaps-Animation entfernt/
	-- verschoben werden (siehe HouseHandler.lua), kann GetBoundingBox() kurzzeitig eine
	-- degenerierte (negative oder NaN) Grösse liefern -- math.clamp() würde dabei sonst
	-- mit "max must be >= min" abstürzen. Statt abzustürzen wird das Haus in diesem
	-- kurzen Zeitfenster einfach als "unerreichbar weit weg" behandelt.
	if halfSize.X < 0 or halfSize.Y < 0 or halfSize.Z < 0
		or halfSize.X ~= halfSize.X or halfSize.Y ~= halfSize.Y or halfSize.Z ~= halfSize.Z then
		return math.huge
	end

	local localPos = cframe:PointToObjectSpace(position)
	local clamped = Vector3.new(
		math.clamp(localPos.X, -halfSize.X, halfSize.X),
		math.clamp(localPos.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPos.Z, -halfSize.Z, halfSize.Z)
	)
	local closestWorldPoint = cframe:PointToWorldSpace(clamped)
	return (position - closestWorldPoint).Magnitude
end

local function getHousesInRange(position)
	local housesInRange = {}
	if not _G.HOUSE_TAG then
		return housesInRange
	end
	for _, house in ipairs(CollectionService:GetTagged(_G.HOUSE_TAG)) do
		if distanceToHouse(house, position) <= ATTACK_RANGE then
			table.insert(housesInRange, house)
		end
	end
	return housesInRange
end

-- Gleiches Prinzip wie getHousesInRange, aber für Stufe-3-Barrikaden/Generatoren (siehe
-- BarricadeClusterService.lua). Nutzt dieselbe distanceToHouse-Funktion, da sie generisch
-- auf jedes Model mit Bounding-Box funktioniert, nicht nur auf Häuser.
local function getTaggedModelsInRange(tagName, position)
	local modelsInRange = {}
	for _, model in ipairs(CollectionService:GetTagged(tagName)) do
		if distanceToHouse(model, position) <= ATTACK_RANGE then
			table.insert(modelsInRange, model)
		end
	end
	return modelsInRange
end

AttackEvent.OnServerEvent:Connect(function(player, comboStep)
	local now = os.clock()
	-- Berserker-Modus: Cooldown-Multiplikator anwenden (1.0 = normal, <1.0 = kürzer) --
	-- gilt sowohl für die tatsächliche Sperre hier als auch für die Anzeige unten.
	local cooldownMultiplier = (_G.GetBerserkerCooldownMultiplier and _G.GetBerserkerCooldownMultiplier(player)) or 1.0
	local effectiveCooldown = ATTACK_COOLDOWN * cooldownMultiplier

	if lastAttackTime[player] and now - lastAttackTime[player] < effectiveCooldown then
		return
	end
	lastAttackTime[player] = now
	player:SetAttribute("AttackReadyAt", Workspace:GetServerTimeNow() + effectiveCooldown)

	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	local damage = character:GetAttribute("Damage") or 10
	local berserkerMultiplier = (_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0
	damage = damage * berserkerMultiplier

	-- Dritter Combo-Schlag (PunchAll-Animation): ×1.25 Schaden -- motiviert dazu, die
	-- Dreierfolge abzuschließen statt nur einzelne Schläge zu spammen.
	if tonumber(comboStep) == 3 then
		damage = damage * THIRD_PUNCH_DAMAGE_MULTIPLIER
	end

	-- Heat-System: wird jetzt erst NACH der Trefferermittlung unten ausgelöst -- nur ein
	-- TATSÄCHLICHER Treffer (Haus oder Spieler) soll Hitze erzeugen, nicht schon der
	-- blosse Tastendruck ins Leere.
	local didHit = false

	-- Häuser in Reichweite beschädigen (funktioniert überall, wo Häuser stehen -> Sammel-Zone)
	local isFinisher = tonumber(comboStep) == 3
	if _G.DamageHouse then
		for _, house in ipairs(getHousesInRange(root.Position)) do
			if not house:GetAttribute("Destroyed") then
				_G.DamageHouse(house, damage, player)
				ShowDamageEvent:FireClient(player, damage, isFinisher)
				didHit = true
			end
		end
	end

	-- Feuerwehrautos in Reichweite beschädigen (City-Alert-System, Alert Level 2) --
	-- gleicher Angriff, gleiche Reichweite wie bei Häusern.
	if _G.DamageFireEngine and _G.GetFireEnginesInRange then
		for _, engine in ipairs(_G.GetFireEnginesInRange(root.Position, ATTACK_RANGE)) do
			_G.DamageFireEngine(engine, damage, player)
			ShowDamageEvent:FireClient(player, damage, isFinisher)
			didHit = true
		end
	end

	-- Barrikaden-Schilde in Reichweite beschädigen (City-Alert-System, Alert Level 3) --
	-- gleicher Angriff, gleiche Reichweite. Generatoren sind bewusst NICHT hier
	-- getroffen -- die sind gemäss Design als Jaeger-Ziel gedacht, nicht Teil des
	-- normalen Kaiju-Punch-Schadens (siehe SpecialAttackHandler.lua für Generatoren).
	if _G.DamageBarricadeShield and _G.GetClusterIdForModel then
		for _, barricade in ipairs(getTaggedModelsInRange("Barricade", root.Position)) do
			local clusterId, cityName = _G.GetClusterIdForModel(barricade)
			if clusterId and cityName then
				_G.DamageBarricadeShield(cityName, clusterId, damage, player)
				ShowDamageEvent:FireClient(player, damage, isFinisher)
				didHit = true
			end
		end
	end

	-- Generatoren in Reichweite beschädigen. Laut Design als Jaeger-Ziel gedacht --
	-- vorerst mit jeder Fraktion nutzbar (Jaeger hat noch kein eigenes Kampfsystem),
	-- Fraktions-Beschränkung kann ergänzt werden, sobald das existiert.
	if _G.DamageGenerator and _G.GetGeneratorsInRange then
		for _, hit in ipairs(_G.GetGeneratorsInRange(root.Position, ATTACK_RANGE)) do
			_G.DamageGenerator(hit.cityName, hit.clusterId, hit.side, damage)
			ShowDamageEvent:FireClient(player, damage, isFinisher)
			didHit = true
		end
	end

	-- Militär-Einheiten (Alert Level 4: Panzer, Raketenwerfer, Helikopter) in Reichweite
	-- beschädigen -- gleiches Muster wie Barrikaden.
	if _G.DamageMilitaryUnit and _G.GetMilitaryUnitInfo then
		for _, unit in ipairs(getTaggedModelsInRange("MilitaryUnit", root.Position)) do
			local cityName, unitType, unitId = _G.GetMilitaryUnitInfo(unit)
			if cityName and unitType and unitId then
				_G.DamageMilitaryUnit(cityName, unitType, unitId, damage, player)
				ShowDamageEvent:FireClient(player, damage, isFinisher)
				didHit = true
			end
		end
	end

	-- Guardian-Boss (Alert Level 5) in Reichweite beschädigen -- gleiches Muster.
	if _G.DamageGuardian and _G.GetGuardianInfo then
		for _, guardianModel in ipairs(getTaggedModelsInRange("Guardian", root.Position)) do
			local cityName = _G.GetGuardianInfo(guardianModel)
			if cityName then
				_G.DamageGuardian(cityName, damage, player)
				ShowDamageEvent:FireClient(player, damage, isFinisher)
				didHit = true
			end
		end
	end

	-- Andere Spieler angreifen -- NUR erlaubt, wenn BEIDE in der PvP-Zone sind
	if player:GetAttribute("CurrentZone") == PVP_ZONE_NAME then
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if
				otherPlayer ~= player
				and otherPlayer.Character
				and otherPlayer:GetAttribute("CurrentZone") == PVP_ZONE_NAME
			then
				local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				local otherHumanoid = otherPlayer.Character:FindFirstChild("Humanoid")
				if otherRoot and otherHumanoid and otherHumanoid.Health > 0 then
					local distance = (otherRoot.Position - root.Position).Magnitude
					if distance <= ATTACK_RANGE then
						local wasAlive = otherHumanoid.Health > 0
						otherHumanoid:TakeDamage(damage)
						ShowDamageEvent:FireClient(player, damage, isFinisher)
						didHit = true

						if wasAlive and otherHumanoid.Health <= 0 then
							local leaderstats = player:FindFirstChild("leaderstats")
							if leaderstats then
								leaderstats.Kills.Value += 1
							end
							if _G.AwardXP then
								_G.AwardXP(player, XP_PER_KILL)
							end
						end
					end
				end
			end
		end
	end

	-- Heat-System: nur bei einem TATSÄCHLICHEN Treffer (Haus oder Spieler) auslösen --
	-- ins Leere geschlagen erzeugt keine Hitze mehr.
	if didHit and _G.AddPunchHeat then
		_G.AddPunchHeat(player, comboStep)
	end

	-- Special Energy: gleiche Bedingung wie Heat -- nur ein tatsächlicher Treffer gibt
	-- Energy, kein Schlag ins Leere. Skaliert mit dem Combo-Schritt (Finisher gibt mehr).
	if didHit and _G.AwardSpecialEnergyForComboHit then
		_G.AwardSpecialEnergyForComboHit(player, tonumber(comboStep))
	end
end)