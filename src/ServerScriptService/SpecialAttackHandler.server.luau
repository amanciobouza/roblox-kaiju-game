-- VERSION: 2026-08-26 #24
-- FEATURE: _G.PerformAreaDamage ergänzt (für Prolog-Intro-Kinematik)
-- Ort in Studio: ServerScriptService
-- Verwaltet die 2 Spezialangriffe: Fokus-Laser (hoher Einzelschaden, Strahl vom Kopf) und
-- Flächenschaden (auflandende Ladung, die nach kurzer Verzögerung alles in der Nähe trifft).
-- Beide haben einen Cooldown, damit sie nicht spammbar sind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- WICHTIG: erstellt diese RemoteEvents selbst, falls sie noch nicht existieren, statt nur
-- darauf zu warten -- reines WaitForChild hier hätte das Script (und alle darauf
-- wartenden Client-Scripts) für immer hängen lassen, falls keine andere Datei sie
-- erzeugt. Gleiches Muster wie an anderen Stellen im Projekt (z.B.
-- TrenchbornPortalController.lua für TrenchbornPortalRemote).
local function getOrCreateRemoteEvent(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local FocusAttackEvent = getOrCreateRemoteEvent("FocusAttackEvent")
local FocusChargeEvent = getOrCreateRemoteEvent("FocusChargeEvent")
local AreaAttackEvent = getOrCreateRemoteEvent("AreaAttackEvent")
local FocusAttackEffectEvent = getOrCreateRemoteEvent("FocusAttackEffectEvent")
local AreaAttackEffectEvent = getOrCreateRemoteEvent("AreaAttackEffectEvent")
local ShowDamageEvent = getOrCreateRemoteEvent("ShowDamageEvent")

local PVP_ZONE_NAME = "PvP"

-- Bein-Verhältnis: 0 (Bein=0) bis 1 (Bein voll trainiert, BeinWert/BeinCap). Nutzt
-- "LegStatCap" (der um Faktor 100 vergrößerte, Bein-spezifische Cap -- siehe
-- TrainingHandler.lua), NICHT den generischen "StatCap" (der ist unskaliert und würde das
-- Verhältnis verfälschen, da BeinWert selbst ja ebenfalls ×100 skaliert ist).
local function getLegRatio(player)
	local legPower = player:FindFirstChild("LegPower")
	local legValue = legPower and legPower.Value or 0
	local legCap = math.max(player:GetAttribute("LegStatCap") or 1, 1)
	return math.clamp(legValue / legCap, 0, 1)
end

-- Bein-Multiplikator: 1x bei Bein=0, bis 2x bei voll trainiertem Bein. Gleiche Formel wie
-- beim Sprungschaden in HouseHandler.lua -- gilt jetzt auch für beide Spezialangriffe,
-- damit Bein-Training universell wertvoll ist, nicht nur fürs Springen.
local function getLegMultiplier(player)
	return 1 + getLegRatio(player)
end

-- ===== Fokus-Angriff: Laserstrahl vom Kopf, Schaden über Zeit statt Einzeltreffer =====
-- WICHTIG: der lange Cooldown wurde durch Special Energy ersetzt (siehe
-- SpecialEnergyHandler.lua) -- das hier ist nur noch ein kurzer Anti-Spam-Schutz gegen
-- Doppelauslösung, bestimmt NICHT mehr den eigentlichen Combat-Rhythmus.
local FOCUS_ATTACK_COOLDOWN = 1 -- Sekunden -- kurzer Anti-Spam-Schutz, nicht mehr die eigentliche Wartezeit
local FOCUS_DAMAGE_PER_TICK_MULTIPLIER = 1.5 -- x-facher normaler Schaden, PRO Tick
local FOCUS_ATTACK_RANGE = 300 -- Studs, wie weit der Strahl reicht
local FOCUS_ATTACK_DURATION = 2.5 -- Sekunden, die der Strahl insgesamt aktiv bleibt
local FOCUS_TRAINING_MAX_DURATION = 6 -- Bein-Training: deutlich länger als im echten Kampf, damit mehrere Trainings-Ticks pro Auslösung gesammelt werden

local FOCUS_TICK_INTERVAL = 0.25 -- Sekunden zwischen zwei Schadens-Ticks (~10 Ticks über die Dauer)
local FOCUS_CHARGE_TIME = 2 -- Sekunden Aufladezeit, bevor der Strahl wirklich losgeht

-- ===== Flächenschaden: auflandende Ladung, explodiert nach kurzer Verzögerung =====
-- Gleiches Prinzip: kurzer Anti-Spam-Cooldown statt langer Wartezeit, Freischaltung läuft
-- über Special Energy.
local AREA_ATTACK_COOLDOWN = 1.5 -- Sekunden -- kurzer Anti-Spam-Schutz, nicht mehr die eigentliche Wartezeit
local AREA_DAMAGE_MULTIPLIER = 1.75 -- x-facher normaler Schaden -- war 3, aber in Kombination mit hohem Endgame-Schaden UND mehreren gleichzeitig getroffenen Zielen zu stark (ganze Stadtblöcke in Sekunden plattgemacht)
-- Radius wächst genau wie beim Energie-Sammeln (EnergyCollectionHandler.lua) mit dem
-- Körper-Wert -- unterproportional (Exponent < 1), automatisch durch den Level-Cap
-- gedeckelt -- nur etwas großzügiger als beim reinen Energie-Sammeln.
local AREA_ATTACK_RADIUS_BASE = 22 -- Studs bei Körper-Wert 0 -- angeglichen an EnergyCollectionHandler.lua
local AREA_ATTACK_RADIUS_SCALE = 4.5
local AREA_ATTACK_RADIUS_EXPONENT = 0.7
local AREA_CHARGE_TIME = 1.2 -- Sekunden Aufladezeit, bevor der Schaden passiert

local AREA_ATTACK_RADIUS_MAX = 170 -- Studs (verdoppelt von 85 zurück auf 170, auf Wunsch)

local function getAreaAttackRadius(player)
	-- Hängt vom BEIN-Wert ab (nicht vom Körper-Wert) -- gleiche Formel-Struktur wie der
	-- Energiesog-Radius (EnergyCollectionHandler.lua, getCollectionRadius). WICHTIG:
	-- KEINE Charaktergrößen-Skalierung mehr -- die hat das Verhältnis vorher verzerrt
	-- (der Energiesog-Radius bekommt diesen Faktor ja auch nicht).
	-- WICHTIG: Anders als getLegRatio() nutzt diese Formel den ROHEN Bein-Wert (keine
	-- Verhältnis-Rechnung) -- muss deshalb durch LEG_CAP_SCALE geteilt werden, da
	-- LegPower jetzt künstlich ×100 skaliert ist (siehe TrainingHandler.lua), sonst würde
	-- der Radius durch die Skalierung ~25x zu groß werden.
	local legPower = player:FindFirstChild("LegPower")
	local legCapScale = _G.LEG_CAP_SCALE or 1
	local legValue = (legPower and legPower.Value or 0) / legCapScale
	local radius = 1.2 * (AREA_ATTACK_RADIUS_BASE + AREA_ATTACK_RADIUS_SCALE * (legValue ^ AREA_ATTACK_RADIUS_EXPONENT))

	-- Talent "Chain Reaction" (Kaiju-Talentbaum): vergrössert den Radius. Der Deckel
	-- (AREA_ATTACK_RADIUS_MAX) wächst dabei nur zur HÄLFTE mit -- verhindert, dass das
	-- Talent den bewusst gesetzten Deckel (verhindert "ganze Stadt auf einen Schlag")
	-- komplett aushebelt.
	local talentRadiusBonus = (_G.GetTalentAreaRadiusBonus and _G.GetTalentAreaRadiusBonus(player)) or 0
	radius = radius * (1 + talentRadiusBonus)
	local effectiveMax = AREA_ATTACK_RADIUS_MAX * (1 + talentRadiusBonus * 0.5)

	return math.min(radius, effectiveMax)
end

-- Evolution-Bonus: Spezialangriffe können mit steigendem Cooldown-Skill-Level schneller
-- wieder eingesetzt werden (kürzere Wartezeit, mindestens 30% der Basis-Wartezeit bleiben).
-- Bein-Training nutzt die GLEICHEN Cooldowns wie im echten Spiel (20s/30s) -- außer
-- während eines aktiven Trainings-Boosts, dann werden sie halbiert (analog zum
-- halbierten Klick-Cooldown beim generischen Training, siehe TrainingHandler.lua).
local function getEffectiveCooldown(player, baseCooldown)
	if player:GetAttribute("TrainingStat") == "Leg" then
		local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
		local isBoosted = Workspace:GetServerTimeNow() < boostEndsAt
		return isBoosted and (baseCooldown / 2) or baseCooldown
	end

	-- Berserker-Modus: zusätzlicher Cooldown-Multiplikator (1.0 = normal, <1.0 = kürzer)
	local berserkerCooldownMultiplier = (_G.GetBerserkerCooldownMultiplier and _G.GetBerserkerCooldownMultiplier(player)) or 1.0
	baseCooldown = baseCooldown * berserkerCooldownMultiplier

	-- Talent "Rapid Strikes" (Kaiju-Talentbaum): zusätzliche Abklingzeit-Reduktion.
	local talentCooldownReduction = (_G.GetTalentCooldownReduction and _G.GetTalentCooldownReduction(player)) or 0
	baseCooldown = baseCooldown * math.max(1 - talentCooldownReduction, 0.4)

	-- Talent "Meltdown Mastery" (Kaiju-Talentbaum, Synergie): zusätzliches Angriffstempo
	-- WÄHREND Meltdown aktiv ist (heat >= 100).
	if (_G.GetHeatStage and _G.GetHeatStage(player) == "Meltdown") and _G.GetTalentMeltdownAttackSpeedBonus then
		local meltdownBonus = _G.GetTalentMeltdownAttackSpeedBonus(player)
		baseCooldown = baseCooldown * math.max(1 - meltdownBonus, 0.3)
	end

	return baseCooldown
end

-- Cooldown-Längen für den Client bereitstellen (fürs HUD)
local focusCooldownValue = Instance.new("IntValue")
focusCooldownValue.Name = "FocusAttackCooldown"
focusCooldownValue.Value = FOCUS_ATTACK_COOLDOWN
focusCooldownValue.Parent = ReplicatedStorage

local focusDurationValue = Instance.new("NumberValue")
focusDurationValue.Name = "FocusAttackDuration"
focusDurationValue.Value = FOCUS_ATTACK_DURATION
focusDurationValue.Parent = ReplicatedStorage

local areaCooldownValue = Instance.new("IntValue")
areaCooldownValue.Name = "AreaAttackCooldown"
areaCooldownValue.Value = AREA_ATTACK_COOLDOWN
areaCooldownValue.Parent = ReplicatedStorage

-- Sucht ausgehend von einem getroffenen Teil das übergeordnete Haus-Model (falls vorhanden).
local function findHouseFromPart(part)
	local current = part
	while current and current ~= Workspace do
		if current:IsA("Model") and _G.HOUSE_TAG and CollectionService:HasTag(current, _G.HOUSE_TAG) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local FOCUS_ATTACK_CONE_ANGLE = 25 -- Grad Toleranz zur Blickrichtung -- kein exaktes Zielen nötig

-- Berechnet den Winkel zwischen Blickrichtung und Ziel-Richtung NUR horizontal (Höhe
-- wird ignoriert) -- sonst fällt ein Ziel, das deutlich tiefer/höher liegt (oder bei
-- geringer Distanz, wo schon ein kleiner Höhenunterschied einen grossen 3D-Winkel
-- ergibt), fälschlich aus dem Ziel-Kegel, obwohl es horizontal genau vor einem liegt.
-- Zielpunkt am Guardian. Der PrimaryPart taugt dafür NICHT: je nach Modell sitzt er auf
-- Sohlenhöhe (Warden-I Shepherd) statt in der Körpermitte -- Umkreis- und Kegelprüfungen
-- lägen bei einem 42 Studs hohen Boss dann deutlich daneben, und der Fokusstrahl würde auf
-- die Füsse zeigen. "ChestCore" gibt es bei beiden Guardian-Modellen, auf Brusthöhe.
local function getGuardianAimPart(guardianModel)
	local chest = guardianModel:FindFirstChild("ChestCore", true)
	if chest and chest:IsA("BasePart") then
		return chest
	end
	return guardianModel.PrimaryPart
end

local function horizontalConeAngle(lookVector, toTarget)
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	local flatTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flatLook.Magnitude < 0.001 or flatTarget.Magnitude < 0.001 then
		return 0 -- praktisch direkt über/unter einem selbst -- als "im Kegel" werten
	end
	return math.deg(math.acos(math.clamp(flatLook.Unit:Dot(flatTarget.Unit), -1, 1)))
end

-- Sucht das NÄCHSTE Ziel (Haus oder Spieler in der Arena) innerhalb eines Kegels um die
-- Blickrichtung -- statt eines exakten Strahls, der Pixel-genaues Zielen erfordern würde.
local function findFocusTarget(player, rootPart)
	-- Bein-Training: Ziel ist immer das "LaserTarget"-Teil in der LegTrainingStation --
	-- rein visuelle Demo, kein echter Schaden (siehe Schadens-Anwendung weiter unten,
	-- die "trainingTarget" bewusst nicht behandelt).
	if player:GetAttribute("TrainingStat") == "Leg" then
		local station = Workspace:FindFirstChild("LegTrainingStation", true)
		local laserTarget = station and station:FindFirstChild("LaserTarget", true)
		if laserTarget and laserTarget:IsA("BasePart") then
			return { type = "trainingTarget", trackPart = laserTarget }
		end
		return nil
	end

	local lookVector = rootPart.CFrame.LookVector
	local originPosition = rootPart.Position

	local bestTarget = nil
	-- Talent "Focus Mastery" (Kaiju-Talentbaum, Trade-off): reduziert die Reichweite
	-- zugunsten von mehr Schaden (siehe Schadens-Anwendung weiter unten).
	local focusRangePenalty = (_G.GetTalentFocusRangePenalty and _G.GetTalentFocusRangePenalty(player)) or 0
	local bestDistance = FOCUS_ATTACK_RANGE * math.max(1 - focusRangePenalty, 0.5)

	if _G.HOUSE_TAG then
		for _, house in ipairs(CollectionService:GetTagged(_G.HOUSE_TAG)) do
			if not house:GetAttribute("Destroyed") then
				-- PrimaryPart gibt's nur bei Models -- bei direkt getaggten Parts/MeshParts
				-- (kein Model drumherum) das Objekt selbst als Position nutzen.
				local housePart = house:IsA("Model") and house.PrimaryPart or (house:IsA("BasePart") and house or nil)
				if housePart then
					local toTarget = housePart.Position - originPosition
					local distance = toTarget.Magnitude
					if distance > 0 and distance <= bestDistance then
						local angle = horizontalConeAngle(lookVector, toTarget)
						if angle <= FOCUS_ATTACK_CONE_ANGLE then
							bestDistance = distance
							bestTarget = { type = "house", instance = house, trackPart = housePart }
						end
					end
				end
			end
		end
	end

	if _G.FIRE_ENGINE_TAG then
		for _, engine in ipairs(CollectionService:GetTagged(_G.FIRE_ENGINE_TAG)) do
			if not engine:GetAttribute("Destroyed") then
				local enginePart = engine.PrimaryPart
				if enginePart then
					local toTarget = enginePart.Position - originPosition
					local distance = toTarget.Magnitude
					if distance > 0 and distance <= bestDistance then
						local angle = horizontalConeAngle(lookVector, toTarget)
						if angle <= FOCUS_ATTACK_CONE_ANGLE then
							bestDistance = distance
							bestTarget = { type = "fireEngine", instance = engine, trackPart = enginePart }
						end
					end
				end
			end
		end
	end

	-- Militär-Einheiten (Alert Level 4: Panzer, Raketenwerfer, Helikopter) als anvisierbare
	-- Fokus-Ziele, gleiches Muster wie Häuser/Feuerwehrautos.
	if _G.GetMilitaryUnitInfo then
		for _, unitModel in ipairs(CollectionService:GetTagged("MilitaryUnit")) do
			local unitPart = unitModel.PrimaryPart
			if unitPart then
				local toTarget = unitPart.Position - originPosition
				local distance = toTarget.Magnitude
				if distance > 0 and distance <= bestDistance then
					local angle = horizontalConeAngle(lookVector, toTarget)
					if angle <= FOCUS_ATTACK_CONE_ANGLE then
						bestDistance = distance
						bestTarget = { type = "militaryUnit", instance = unitModel, trackPart = unitPart }
					end
				end
			end
		end
	end

	-- Guardian-Boss (Alert Level 5) als anvisierbares Fokus-Ziel, gleiches Muster wie
	-- Militär-Einheiten.
	if _G.GetGuardianInfo then
		for _, guardianModel in ipairs(CollectionService:GetTagged("Guardian")) do
			local aimPart = getGuardianAimPart(guardianModel)
			if aimPart then
				local toTarget = aimPart.Position - originPosition
				local distance = toTarget.Magnitude
				if distance > 0 and distance <= bestDistance then
					local angle = horizontalConeAngle(lookVector, toTarget)
					if angle <= FOCUS_ATTACK_CONE_ANGLE then
						bestDistance = distance
						bestTarget = { type = "guardian", instance = guardianModel, trackPart = aimPart }
					end
				end
			end
		end
	end

	if player:GetAttribute("CurrentZone") == PVP_ZONE_NAME then
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player and otherPlayer.Character and otherPlayer:GetAttribute("CurrentZone") == PVP_ZONE_NAME then
				local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				local otherHumanoid = otherPlayer.Character:FindFirstChildOfClass("Humanoid")
				if otherRoot and otherHumanoid and otherHumanoid.Health > 0 then
					local toTarget = otherRoot.Position - originPosition
					local distance = toTarget.Magnitude
					if distance > 0 and distance <= bestDistance then
						local angle = horizontalConeAngle(lookVector, toTarget)
						if angle <= FOCUS_ATTACK_CONE_ANGLE then
							bestDistance = distance
							bestTarget = {
								type = "player",
								instance = otherPlayer,
								humanoid = otherHumanoid,
								trackPart = otherRoot,
							}
						end
					end
				end
			end
		end
	end

	return bestTarget
end

-- Vergibt Kill-XP/Kills, wenn ein Spielertreffer tödlich war (analog zu CombatHandler.lua).
local function handlePossiblePlayerKill(attacker, victimPlayer, victimHumanoid, wasAlive)
	if wasAlive and victimHumanoid.Health <= 0 then
		local leaderstats = attacker:FindFirstChild("leaderstats")
		if leaderstats then
			leaderstats.Kills.Value += 1
		end
		if _G.AwardXP then
			_G.AwardXP(attacker, 250) -- ÷100 (war 25000), analog zu CombatHandler.lua XP_PER_KILL
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("FocusAttackReadyAt", 0)
	player:SetAttribute("FocusCharging", false)
	player:SetAttribute("AreaAttackReadyAt", 0)
end)

-- ===== Fokus-Angriff =====
-- Wiederverwendbare Kern-Logik für Flächenschaden -- wird sowohl vom regulären
-- Flächenangriff ALS AUCH vom "Combo Chain"-Talent (kostenloser Bonus-Flächenangriff
-- nach 3 Fokus-Treffern in Folge) genutzt.
local function performAreaDamage(player, chargePosition, radius, damage)
	if _G.HOUSE_TAG and _G.DamageHouse then
		for _, house in ipairs(CollectionService:GetTagged(_G.HOUSE_TAG)) do
			local housePart = house:IsA("Model") and house.PrimaryPart or (house:IsA("BasePart") and house or nil)
			if housePart and (housePart.Position - chargePosition).Magnitude <= radius then
				-- WICHTIG: pcall -- ein Fehler bei EINEM Haus darf nicht die gesamte
				-- Schleife für alle NACHFOLGENDEN Häuser abbrechen (CollectionService
				-- liefert die Reihenfolge nicht nach Entfernung sortiert -- ohne pcall
				-- könnten dadurch scheinbar "nur nahe Häuser" beschädigt werden, je
				-- nachdem an welcher Stelle der Fehler auftritt).
				local ok, err = pcall(function()
					_G.DamageHouse(house, damage, player, chargePosition)
				end)
				if not ok then
					warn("[SpecialAttackHandler] Fehler beim Flächenschaden an '" .. house:GetFullName() .. "': " .. tostring(err))
				end
			end
		end
	end

	if _G.FIRE_ENGINE_TAG and _G.DamageFireEngine then
		for _, engine in ipairs(CollectionService:GetTagged(_G.FIRE_ENGINE_TAG)) do
			local enginePart = engine.PrimaryPart
			if enginePart and not engine:GetAttribute("Destroyed") and (enginePart.Position - chargePosition).Magnitude <= radius then
				_G.DamageFireEngine(engine, damage, player)
			end
		end
	end

	-- Barrikaden-Schilde + Generatoren im Radius beschädigen (Alert-Stufe 3).
	if _G.DamageBarricadeShield and _G.GetClusterIdForModel then
		for _, barricade in ipairs(CollectionService:GetTagged("Barricade")) do
			local part = barricade.PrimaryPart
			if part and (part.Position - chargePosition).Magnitude <= radius then
				local clusterId, cityName = _G.GetClusterIdForModel(barricade)
				if clusterId and cityName then
					_G.DamageBarricadeShield(cityName, clusterId, damage, player)
				end
			end
		end
	end
	if _G.DamageGenerator and _G.GetGeneratorsInRange then
		for _, hit in ipairs(_G.GetGeneratorsInRange(chargePosition, radius)) do
			_G.DamageGenerator(hit.cityName, hit.clusterId, hit.side, damage, player)
		end
	end

	-- Militär-Einheiten (Alert Level 4: Panzer, Raketenwerfer, Helikopter) im Radius
	-- beschädigen -- gleiches Muster wie Barrikaden/Generatoren/Feuerwehrautos.
	if _G.DamageMilitaryUnit and _G.GetMilitaryUnitInfo then
		for _, unitModel in ipairs(CollectionService:GetTagged("MilitaryUnit")) do
			local unitPart = unitModel.PrimaryPart
			if unitPart and (unitPart.Position - chargePosition).Magnitude <= radius then
				local cityName, unitType, unitId = _G.GetMilitaryUnitInfo(unitModel)
				if cityName and unitType and unitId then
					_G.DamageMilitaryUnit(cityName, unitType, unitId, damage, player)
				end
			end
		end
	end

	-- Guardian-Boss (Alert Level 5) im Radius beschädigen -- gleiches Muster.
	if _G.DamageGuardian and _G.GetGuardianInfo then
		for _, guardianModel in ipairs(CollectionService:GetTagged("Guardian")) do
			local aimPart = getGuardianAimPart(guardianModel)
			if aimPart and (aimPart.Position - chargePosition).Magnitude <= radius then
				local cityName = _G.GetGuardianInfo(guardianModel)
				if cityName then
					_G.DamageGuardian(cityName, damage, player)
				end
			end
		end
	end

	if player:GetAttribute("CurrentZone") == PVP_ZONE_NAME then
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player and otherPlayer.Character and otherPlayer:GetAttribute("CurrentZone") == PVP_ZONE_NAME then
				local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				local otherHumanoid = otherPlayer.Character:FindFirstChildOfClass("Humanoid")
				if otherRoot and otherHumanoid and otherHumanoid.Health > 0 then
					if (otherRoot.Position - chargePosition).Magnitude <= radius then
						local wasAlive = otherHumanoid.Health > 0
						otherHumanoid:TakeDamage(damage)
						handlePossiblePlayerKill(player, otherPlayer, otherHumanoid, wasAlive)
					end
				end
			end
		end
	end

	ShowDamageEvent:FireClient(player, damage)

	-- Lebensstatistik: EINMAL pro Auslösung, nicht pro getroffenem Ziel -- sonst erschiene
	-- eine Ladung, die zehn Häuser erwischt, als zehn Angriffe.
	if _G.RecordStat then
		_G.RecordStat(player, "Attacks.Area")
		_G.RecordStat(player, "DamageDealt", damage)
		_G.RecordStatMax(player, "MaxDamage.Area", damage)
	end
end

-- Berechnet den Flächenschaden pro Treffer inkl. aller Talent-Effekte: Trade-off-Malus
-- (Blast Radius), Heat-Skalierung (Overheat Blast, Cross-Zweig-Synergie), Cataclysm
-- (jeder 4. Flächenangriff verursacht doppelten Schaden).
local function getAreaDamagePerHit(player, baseDamage)
	local damage = baseDamage

	local areaDamagePenalty = (_G.GetTalentAreaDamagePenalty and _G.GetTalentAreaDamagePenalty(player)) or 0
	damage = damage * math.max(1 - areaDamagePenalty, 0.5)

	local heatScaling = (_G.GetTalentHeatScaledAreaDamage and _G.GetTalentHeatScaledAreaDamage(player)) or 0
	if heatScaling > 0 and _G.GetHeatStage then
		local heat = player:GetAttribute("Heat") or 0
		damage = damage * (1 + heatScaling * (heat / 100))
	end

	if _G.GetTalentCataclysmEnabled and _G.GetTalentCataclysmEnabled(player) then
		local count = (player:GetAttribute("AreaAttackCount") or 0) + 1
		player:SetAttribute("AreaAttackCount", count)
		if count % 4 == 0 then
			damage = damage * 2
		end
	end

	return damage
end

FocusAttackEvent.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not head or not rootPart or humanoid.Health <= 0 then
		return
	end

	local now = Workspace:GetServerTimeNow()
	if now < (player:GetAttribute("FocusAttackReadyAt") or 0) then
		return -- kurzer Anti-Spam-Schutz
	end
	if player:GetAttribute("FocusCharging") then
		return -- lädt gerade schon auf, nicht erneut auslösen
	end

	-- Special Energy: das ist jetzt die eigentliche Freischaltung (ersetzt den früheren
	-- langen Cooldown) -- ohne genug Energy kein Angriff, egal wie lange der letzte
	-- Fokus-Angriff her ist.
	local focusCost = _G.GetSpecialEnergyCost and _G.GetSpecialEnergyCost("Focus") or 25
	if not (_G.TrySpendSpecialEnergy and _G.TrySpendSpecialEnergy(player, focusCost)) then
		return -- nicht genug Energy
	end
	if _G.OnFocusAttackUsedForAchievements then
		_G.OnFocusAttackUsedForAchievements(player)
	end

	-- Aufladephase: Sound/Signal an den Client, dann kurz warten, bevor der Strahl
	-- wirklich losgeht (Ziel wird erst DANACH gesucht, damit man während des Aufladens
	-- noch nachzielen kann).
	player:SetAttribute("FocusCharging", true)
	FocusChargeEvent:FireClient(player)

	-- Showdown: die Aufladung ist der Aufhaenger fuer die Kamera. Sie faehrt waehrend der
	-- zwei Sekunden am Strahl entlang zum Ziel -- deshalb hier und nicht beim Einschlag.
	if _G.NotifyShowdownAttack then
		_G.NotifyShowdownAttack("FocusLaser", player, player:GetAttribute("CurrentCityName"))
	end

	-- Heat-System: Fokus erzeugt deutlich Hitze -- jetzt AUCH während des Bein-Trainings,
	-- damit der Spieler dort dieselbe Heat-Balance wie im echten Kampf üben kann.
	if _G.AddFocusHeat then
		_G.AddFocusHeat(player)
	end

	task.wait(FOCUS_CHARGE_TIME)
	player:SetAttribute("FocusCharging", false)

	if not character.Parent or humanoid.Health <= 0 then
		return -- z.B. gestorben während der Aufladung
	end

	-- Ziel EINMAL nach der Aufladung festlegen (Kegel-Suche) -- der Strahl bleibt dann für
	-- die gesamte Dauer darauf "kleben", verfolgt es aber (Position wird jeden Tick neu gelesen).
	local target = findFocusTarget(player, rootPart)

	if not target then
		-- Kein Ziel getroffen -> KEIN Cooldown verbrauchen, Energy zurückerstatten,
		-- sofort wieder einsetzbar. Trotzdem kurzen Fehlschlag-Strahl zeigen, als Rückmeldung.
		if _G.AwardSpecialEnergy then
			_G.AwardSpecialEnergy(player, focusCost)
		end
		local missPosition = head.Position + rootPart.CFrame.LookVector * FOCUS_ATTACK_RANGE
		FocusAttackEffectEvent:FireAllClients(player, head.Position, missPosition)
		return
	end

	player:SetAttribute("FocusAttackReadyAt", Workspace:GetServerTimeNow() + getEffectiveCooldown(player, FOCUS_ATTACK_COOLDOWN))

	task.spawn(function()
		local elapsed = 0
		-- Bein-Training: maximale Länge statt der normalen Kampf-Dauer -- sammelt dadurch
		-- gleich mehrere Trainings-Ticks pro Auslösung (~24 statt ~10 Ticks).
		local effectiveDuration = player:GetAttribute("TrainingStat") == "Leg" and FOCUS_TRAINING_MAX_DURATION or FOCUS_ATTACK_DURATION

		while elapsed < effectiveDuration do
			if not character.Parent or humanoid.Health <= 0 then
				break
			end
			if not head.Parent then
				break
			end

			local hitPosition = head.Position + rootPart.CFrame.LookVector * FOCUS_ATTACK_RANGE
			local targetStillValid = false

			if target then
				if target.type == "house" then
					if target.instance.Parent and not target.instance:GetAttribute("Destroyed") and target.trackPart and target.trackPart.Parent then
						hitPosition = target.trackPart.Position
						targetStillValid = true
					end
				elseif target.type == "militaryUnit" then
					if target.instance.Parent and target.trackPart and target.trackPart.Parent then
						hitPosition = target.trackPart.Position
						targetStillValid = true
					end
				elseif target.type == "guardian" then
					-- Zusätzlich zur Existenz auch prüfen, ob der Guardian noch aktiv ist:
					-- ein besiegter Guardian bleibt für seine Sturz-Animation kurz im
					-- Workspace stehen und soll in dieser Zeit kein Ziel mehr sein.
					if
						target.instance.Parent
						and target.trackPart
						and target.trackPart.Parent
						and _G.GetGuardianInfo
						and _G.GetGuardianInfo(target.instance)
					then
						hitPosition = target.trackPart.Position
						targetStillValid = true
					end
				elseif target.type == "player" then
					if target.humanoid.Health > 0 and target.trackPart and target.trackPart.Parent then
						hitPosition = target.trackPart.Position
						targetStillValid = true
					end
				elseif target.type == "trainingTarget" then
					-- Bein-Training: Strahl folgt visuell dem LaserTarget. Kein echter
					-- Schaden (targetStillValid bleibt false) -- ABER der Schwebe-Popup
					-- über dem Kopf (wie im echten Kampf) wird trotzdem gezeigt, rein zur
					-- Rückmeldung ans Auge.
					if target.trackPart and target.trackPart.Parent then
						hitPosition = target.trackPart.Position
					end
					local trainingDamage = character:GetAttribute("Damage") or 10
					local displayedDamage = trainingDamage * FOCUS_DAMAGE_PER_TICK_MULTIPLIER * getLegMultiplier(player)
					ShowDamageEvent:FireClient(player, displayedDamage)
					-- Leg-Reaktor auslösen (Laser-Absorptions-Animation) -- eigener Cooldown
					-- lebt im Reaktor-Script selbst (LaserCooldown, Standard 0.8s), daher
					-- hier einfach bei jedem Tick versuchen, überflüssige Aufrufe werden
					-- dort automatisch verworfen.
					if _G.LegReactorRegisterAttack then
						_G.LegReactorRegisterAttack:Fire(player, trainingDamage, "LaserBeam", tostring(os.clock()))
					end
					-- Echten Trainingsfortschritt geben (nicht nur die Reaktor-eigene LegXP, die
					-- separat/rein kosmetisch ist). Gewichtung skaliert zusätzlich mit dem aktuellen
					-- Berserker-Schadens-Multiplikator -- der Schadensboost soll auch als zusätzliche
					-- Trainings-Belohnung spürbar sein, nicht nur als reiner Kampf-Bonus.
					if _G.AwardTrainingProgress then
						local berserkerBonus = (_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0
						_G.AwardTrainingProgress(player, "Leg", FOCUS_DAMAGE_PER_TICK_MULTIPLIER * berserkerBonus)
					end
				end
			end

			FocusAttackEffectEvent:FireAllClients(player, head.Position, hitPosition)

			if targetStillValid then
				local damagePerTick = (character:GetAttribute("Damage") or 10)
					* FOCUS_DAMAGE_PER_TICK_MULTIPLIER
					* getLegMultiplier(player)
					* ((_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0)
					* (player:GetAttribute("MutationFocusDamageMultiplier") or 1.0) -- "Wide Breath"-Mutation
					* (1 + ((_G.GetTalentFocusDamageBonus and _G.GetTalentFocusDamageBonus(player)) or 0)) -- Talent "Focus Mastery"

				if target.type == "house" and _G.DamageHouse then
					_G.DamageHouse(target.instance, damagePerTick, player)
				elseif target.type == "fireEngine" and _G.DamageFireEngine then
					_G.DamageFireEngine(target.instance, damagePerTick, player)
				elseif target.type == "militaryUnit" and _G.DamageMilitaryUnit and _G.GetMilitaryUnitInfo then
					local cityName, unitType, unitId = _G.GetMilitaryUnitInfo(target.instance)
					if cityName and unitType and unitId then
						_G.DamageMilitaryUnit(cityName, unitType, unitId, damagePerTick, player)
					end
				elseif target.type == "guardian" and _G.DamageGuardian and _G.GetGuardianInfo then
					local cityName = _G.GetGuardianInfo(target.instance)
					if cityName then
						_G.DamageGuardian(cityName, damagePerTick, player)
					end
				elseif target.type == "player" then
					local wasAlive = target.humanoid.Health > 0
					target.humanoid:TakeDamage(damagePerTick)
					handlePossiblePlayerKill(player, target.instance, target.humanoid, wasAlive)
				end

				ShowDamageEvent:FireClient(player, damagePerTick)

				-- Lebensstatistik. Der Fokusstrahl trifft in TICKS -- gezaehlt wird jeder
				-- Tick als Treffer, der Hoechstwert bezieht sich entsprechend auf einen
				-- einzelnen Tick, nicht auf den ganzen Strahl.
				if _G.RecordStat then
					_G.RecordStat(player, "Attacks.Focus")
					_G.RecordStat(player, "DamageDealt", damagePerTick)
					_G.RecordStatMax(player, "MaxDamage.Focus", damagePerTick)
				end

				-- Talent "Combo Chain" (Kaiju-Talentbaum, Synergie): 3 Fokus-TREFFER in
				-- Folge lösen automatisch einen kostenlosen Flächenangriff aus (kein
				-- Cooldown-Verbrauch, kein eigener Energie-/Aufladeaufwand).
				if _G.GetTalentComboChainEnabled and _G.GetTalentComboChainEnabled(player) then
					local comboCount = (player:GetAttribute("FocusComboCount") or 0) + 1
					if comboCount >= 3 then
						player:SetAttribute("FocusComboCount", 0)
						local comboRadius = getAreaAttackRadius(player) * 0.6 -- kleiner als ein regulärer Flächenangriff, bleibt ein Bonus, kein Ersatz
						local comboDamage = getAreaDamagePerHit(player, (character:GetAttribute("Damage") or 10) * AREA_DAMAGE_MULTIPLIER * 0.5)
						performAreaDamage(player, rootPart.Position, comboRadius, comboDamage)
					else
						player:SetAttribute("FocusComboCount", comboCount)
					end
				end
			elseif target then
				-- Ziel wurde zerstört/besiegt. Talent "Focus Retarget" (Kaiju-Talentbaum):
				-- OHNE dieses Talent endet der Strahl hier einfach -- MIT Talent sucht er
				-- sich automatisch ein neues Ziel, statt den Rest der Zeit zu verschwenden.
				if _G.GetTalentFocusRetargetEnabled and _G.GetTalentFocusRetargetEnabled(player) then
					target = findFocusTarget(player, rootPart)
					if not target then
						break -- kein weiteres Ziel in Sichtrichtung -> Strahl endet
					end
				else
					break
				end
			end

			task.wait(FOCUS_TICK_INTERVAL)
			elapsed += FOCUS_TICK_INTERVAL
		end
	end)
end)

-- ===== Flächenschaden =====
AreaAttackEvent.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	local now = Workspace:GetServerTimeNow()
	if now < (player:GetAttribute("AreaAttackReadyAt") or 0) then
		return -- kurzer Anti-Spam-Schutz
	end

	-- Special Energy: das ist jetzt die eigentliche Freischaltung (ersetzt den früheren
	-- langen Cooldown).
	local areaCost = _G.GetSpecialEnergyCost and _G.GetSpecialEnergyCost("Area") or 40
	if not (_G.TrySpendSpecialEnergy and _G.TrySpendSpecialEnergy(player, areaCost)) then
		return -- nicht genug Energy
	end
	if _G.OnAreaAttackUsedForAchievements then
		_G.OnAreaAttackUsedForAchievements(player)
	end

	player:SetAttribute("AreaAttackReadyAt", now + getEffectiveCooldown(player, AREA_ATTACK_COOLDOWN))

	-- Heat-System: Fläche erzeugt am meisten Hitze -- jetzt AUCH während des
	-- Bein-Trainings.
	if _G.AddAreaHeat then
		_G.AddAreaHeat(player)
	end

	local radius = getAreaAttackRadius(player)
	local chargePosition = rootPart.Position
	AreaAttackEffectEvent:FireAllClients(player, chargePosition, AREA_CHARGE_TIME, radius)

	-- Gleiche Ueberlegung wie beim Fokus: waehrend die Ladung waechst, nicht beim Knall.
	if _G.NotifyShowdownAttack then
		_G.NotifyShowdownAttack("AreaAttack", player, player:GetAttribute("CurrentCityName"))
	end

	task.delay(AREA_CHARGE_TIME, function()
		if not character.Parent then
			return
		end

		local damage = (character:GetAttribute("Damage") or 10)
			* AREA_DAMAGE_MULTIPLIER
			* getLegMultiplier(player)
			* ((_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0)
		damage = getAreaDamagePerHit(player, damage)

		-- Bein-Training: Leg-Reaktor auslösen statt echten Schaden anzuwenden. Sanctuary
		-- hat ohnehin keine Häuser und der PvP-Zonen-Check unten schlägt fehl, daher ist
		-- unten stehender Code für echten Schaden während des Trainings bereits von Natur
		-- aus wirkungslos -- hier trotzdem früh rausspringen für Klarheit + den Reaktor-Aufruf.
		if player:GetAttribute("TrainingStat") == "Leg" then
			ShowDamageEvent:FireClient(player, damage)
			if _G.LegReactorRegisterAttack then
				_G.LegReactorRegisterAttack:Fire(player, damage, "AreaAttack", tostring(now))
			end

			return
		end

		performAreaDamage(player, chargePosition, radius, damage)
	end)
end)

-- Für geskriptete Sequenzen ohne echte Spieler-Eingabe (z.B. Prolog-Intro-Kinematik,
-- siehe PrologueOrchestrator.lua) -- ruft dieselbe Flächenschaden-Logik wie der normale,
-- spielerausgelöste Angriff auf.
_G.PerformAreaDamage = performAreaDamage