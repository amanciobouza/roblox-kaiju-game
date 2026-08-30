-- VERSION: 2026-08-26 #2
-- FEATURE: _G.DespawnGuardianForCity ergänzt
-- Ort in Studio: ServerScriptService
--
-- Alert-Level 5: Guardian-Jaeger-Boss ("Mk I" -- Konzept geändert: Village und
-- SmallTown haben KEINEN Guardian, erst ab City. Aktuell für City konfiguriert,
-- LargeCity/Megacity folgen später). Verhalten nach Konzept-Vorlage:
--   SCAN -> POSITIONIEREN -> BLOCKIEREN -> KONTERN
-- statt permanent hinter dem Spieler herzurennen. Beobachtet, wohin sich der Spieler
-- bewegt, und stellt sich VOR wichtige Gebäude (per "GuardianProtect"-Tag markiert,
-- Fallback: das Gebäude mit der höchsten MaxHealth der Stadt), sobald er sich nähert.
--
-- Drei Waffensysteme:
--   Aegis Shield (links)   -- solange der Guardian aktiv vor einem Gebäude blockiert,
--                             nimmt dieses Gebäude KEINEN Schaden (siehe
--                             HouseHandler.lua, _G.IsGuardianProtectingBuilding)
--   Impact Fist (rechts)   -- Nahkampf-Schlag mit Rückstoss, Cooldown
--   Repulsor Pulse (Brust) -- periodischer Flächen-Rückstoss um den Guardian herum
--
-- Visor dunkel in Ruhe, hell sobald der Spieler als Bedrohung erkannt wird (Zustand
-- wechselt von SCAN zu POSITION/BLOCK/COUNTER).
--
-- WICHTIG -- erwartetes Modell: ServerStorage.GuardianModels.City (falls vorhanden,
-- wird bevorzugt). Existiert keins, wird automatisch ein einfacher Block-Platzhalter
-- gebaut (analog zum Feuerwehrauto-Fallback in FireEngineController.lua).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local CityAlertConfig = require(ReplicatedStorage:WaitForChild("CityAlertConfig"))

local GUARDIAN_PROTECT_TAG = "GuardianProtect"
local RESPAWN_DELAY = 45 -- Sekunden, bis ein besiegter Guardian dieser Stadt wieder auftaucht

-- Platzhalter-Sound-IDs -- bitte bei Gelegenheit durch echte ersetzen.
local DEPLOY_SOUND_ID = "rbxassetid://9081625499" -- Sirenen/Dampf beim Aufstehen
local IMPACT_FIST_SOUND_ID = "" -- KCHUNK beim Fausthieb
local REPULSOR_SOUND_ID = "" -- Energie-Impuls
local SHIELD_ACTIVATE_SOUND_ID = "" -- CHUNK-CHUNK-WHOOM beim Schild-Ausfahren
local DEFEAT_SOUND_ID = "" -- beim Niedergehen

-- [cityName] = { model=, humanoid=, state=..., ... } -- nur EIN Guardian gleichzeitig pro Stadt.
local activeGuardians = {}

-- ===== Platzhalter-Modell (falls kein eigenes vorbereitet ist) =====
local function buildFallbackGuardian()
	local model = Instance.new("Model")
	model.Name = "Guardian"

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(10, 12, 6)
	torso.Color = Color3.fromRGB(70, 75, 85)
	torso.Material = Enum.Material.Metal
	torso.TopSurface = Enum.SurfaceType.Smooth
	torso.BottomSurface = Enum.SurfaceType.Smooth
	torso.Parent = model
	model.PrimaryPart = torso

	-- Kopf: klein, tief zwischen den Schultern.
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(3.5, 2.5, 3.5)
	head.Color = Color3.fromRGB(50, 54, 60)
	head.Material = Enum.Material.Metal
	head.Parent = model
	head:PivotTo(torso.CFrame * CFrame.new(0, 6, -0.5))
	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.Parent = torso

	-- Visor: schmaler horizontaler Balken, dunkel in Ruhe.
	local visor = Instance.new("Part")
	visor.Name = "Visor"
	visor.Size = Vector3.new(2.6, 0.35, 0.2)
	visor.Color = Color3.fromRGB(20, 20, 20)
	visor.Material = Enum.Material.Neon
	visor.CanCollide = false
	visor.Parent = model
	visor:PivotTo(head.CFrame * CFrame.new(0, 0, -1.8))
	local visorWeld = Instance.new("WeldConstraint")
	visorWeld.Part0 = head
	visorWeld.Part1 = visor
	visorWeld.Parent = head

	-- Brust-Reaktor (Repulsor-Ursprung + visueller Fokuspunkt).
	local core = Instance.new("Part")
	core.Name = "ChestCore"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(1, 2.2, 2.2)
	core.Color = Color3.fromRGB(80, 180, 255)
	core.Material = Enum.Material.Neon
	core.CanCollide = false
	core.Parent = model
	core:PivotTo(torso.CFrame * CFrame.new(0, 1, -3.1) * CFrame.Angles(0, 0, math.rad(90)))
	local coreWeld = Instance.new("WeldConstraint")
	coreWeld.Part0 = torso
	coreWeld.Part1 = core
	coreWeld.Parent = torso

	local coreLight = Instance.new("PointLight")
	coreLight.Color = Color3.fromRGB(80, 180, 255)
	coreLight.Brightness = 2
	coreLight.Range = 14
	coreLight.Parent = core

	-- Linker Arm: Aegis Shield.
	local leftArm = Instance.new("Part")
	leftArm.Name = "LeftArm"
	leftArm.Size = Vector3.new(3, 9, 3)
	leftArm.Color = Color3.fromRGB(60, 65, 75)
	leftArm.Material = Enum.Material.Metal
	leftArm.Parent = model
	leftArm:PivotTo(torso.CFrame * CFrame.new(-6.5, 0, 0))
	local leftArmWeld = Instance.new("WeldConstraint")
	leftArmWeld.Part0 = torso
	leftArmWeld.Part1 = leftArm
	leftArmWeld.Parent = torso

	local shieldPanel = Instance.new("Part")
	shieldPanel.Name = "AegisShieldPanel"
	shieldPanel.Size = Vector3.new(0.5, 8, 6)
	shieldPanel.Color = Color3.fromRGB(90, 150, 220)
	shieldPanel.Material = Enum.Material.ForceField
	shieldPanel.Transparency = 1 -- unsichtbar, bis aktiviert
	shieldPanel.CanCollide = false
	shieldPanel.Parent = model
	shieldPanel:PivotTo(leftArm.CFrame * CFrame.new(-2.5, 0, 0))
	local shieldWeld = Instance.new("WeldConstraint")
	shieldWeld.Part0 = leftArm
	shieldWeld.Part1 = shieldPanel
	shieldWeld.Parent = leftArm

	-- Rechter Arm: Impact Fist.
	local rightArm = Instance.new("Part")
	rightArm.Name = "RightArm"
	rightArm.Size = Vector3.new(3, 9, 3)
	rightArm.Color = Color3.fromRGB(60, 65, 75)
	rightArm.Material = Enum.Material.Metal
	rightArm.Parent = model
	rightArm:PivotTo(torso.CFrame * CFrame.new(6.5, 0, 0))
	local rightArmWeld = Instance.new("WeldConstraint")
	rightArmWeld.Part0 = torso
	rightArmWeld.Part1 = rightArm
	rightArmWeld.Parent = torso

	local fist = Instance.new("Part")
	fist.Name = "ImpactFist"
	fist.Size = Vector3.new(4, 4, 4)
	fist.Color = Color3.fromRGB(50, 54, 60)
	fist.Material = Enum.Material.Metal
	fist.Parent = model
	fist:PivotTo(rightArm.CFrame * CFrame.new(0, -5.5, 0))
	local fistWeld = Instance.new("WeldConstraint")
	fistWeld.Part0 = rightArm
	fistWeld.Part1 = fist
	fistWeld.Parent = rightArm

	-- Beine + schwere Füsse.
	for _, offset in ipairs({ Vector3.new(-3, -9.5, 0), Vector3.new(3, -9.5, 0) }) do
		local leg = Instance.new("Part")
		leg.Name = "Leg"
		leg.Size = Vector3.new(3.5, 7, 3.5)
		leg.Color = Color3.fromRGB(55, 60, 68)
		leg.Material = Enum.Material.Metal
		leg.Parent = model
		leg:PivotTo(torso.CFrame * CFrame.new(offset))
		local legWeld = Instance.new("WeldConstraint")
		legWeld.Part0 = torso
		legWeld.Part1 = leg
		legWeld.Parent = torso

		local foot = Instance.new("Part")
		foot.Name = "Foot"
		foot.Size = Vector3.new(4.5, 2, 6)
		foot.Color = Color3.fromRGB(45, 48, 54)
		foot.Material = Enum.Material.Metal
		foot.Parent = model
		foot:PivotTo(leg.CFrame * CFrame.new(0, -4.5, -1))
		local footWeld = Instance.new("WeldConstraint")
		footWeld.Part0 = leg
		footWeld.Part1 = foot
		footWeld.Parent = leg
	end

	return model
end

local function getGuardianTemplate(cityName)
	local folder = ServerStorage:FindFirstChild("GuardianModels")
	local custom = folder and folder:FindFirstChild(cityName)
	if custom then
		if custom:IsA("Model") then
			return custom:Clone()
		else
			-- Häufiger Stolperstein: ein Folder statt Model unter GuardianModels.<Stadt>
			-- angelegt -- ein Folder hat kein PrimaryPart und würde weiter unten mit
			-- einem kryptischen Engine-Fehler abstürzen. Hier klar und früh warnen,
			-- stattdessen den Platzhalter nutzen.
			warn("[CityDefenderService] ServerStorage.GuardianModels." .. cityName .. " ist ein " .. custom.ClassName .. ", aber ein 'Model' wird erwartet (braucht PrimaryPart) -- nutze Platzhalter stattdessen.")
		end
	end
	return buildFallbackGuardian()
end

-- ===== Health-Bar (gleiches Muster wie an anderen Stellen im Projekt) =====
local function createHealthBar(guardian)
	local anchorPart = guardian.model.PrimaryPart
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GuardianHealthBar"
	billboard.Size = UDim2.new(0, 220, 0, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 600
	billboard.Parent = anchorPart

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.LuckiestGuy
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.Text = "GUARDIAN"
	nameLabel.Parent = billboard

	local shieldTrack = Instance.new("Frame")
	shieldTrack.Size = UDim2.new(1, 0, 0, 10)
	shieldTrack.Position = UDim2.new(0, 0, 0, 18)
	shieldTrack.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	shieldTrack.Parent = billboard
	local shieldFill = Instance.new("Frame")
	shieldFill.Name = "ShieldFill"
	shieldFill.Size = UDim2.new(1, 0, 1, 0)
	shieldFill.BackgroundColor3 = Color3.fromRGB(90, 160, 230)
	shieldFill.BorderSizePixel = 0
	shieldFill.Parent = shieldTrack

	local hpTrack = Instance.new("Frame")
	hpTrack.Size = UDim2.new(1, 0, 0, 10)
	hpTrack.Position = UDim2.new(0, 0, 0, 30)
	hpTrack.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	hpTrack.Parent = billboard
	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(220, 70, 60)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpTrack

	return { billboard = billboard, shieldFill = shieldFill, hpFill = hpFill }
end

local function updateHealthBar(guardian)
	if not guardian.healthBar then
		return
	end
	local shieldRatio = math.clamp(guardian.shield / math.max(guardian.maxShield, 1), 0, 1)
	local hpRatio = math.clamp(guardian.hp / math.max(guardian.maxHP, 1), 0, 1)
	guardian.healthBar.shieldFill.Size = UDim2.new(shieldRatio, 0, 1, 0)
	guardian.healthBar.hpFill.Size = UDim2.new(hpRatio, 0, 1, 0)
end

-- ===== Visor: dunkel in Ruhe, hell sobald der Spieler als Bedrohung erkannt wurde =====
local function setVisorActive(guardian, active)
	local visor = guardian.model:FindFirstChild("Visor", true)
	if not visor then
		return
	end
	local targetColor = active and Color3.fromRGB(255, 60, 50) or Color3.fromRGB(20, 20, 20)
	TweenService:Create(visor, TweenInfo.new(0.4), { Color = targetColor }):Play()
end

-- ===== Geschützte Gebäude finden: getaggt, sonst das Gebäude mit der höchsten
-- MaxHealth dieser Stadt. =====
local function findProtectedBuildings(cityName)
	local tagged = {}
	for _, house in ipairs(CollectionService:GetTagged(GUARDIAN_PROTECT_TAG)) do
		if not house:GetAttribute("Destroyed") and house:GetAttribute("CityNameResolved") ~= false then
			table.insert(tagged, house)
		end
	end
	if #tagged > 0 then
		return tagged
	end

	-- Fallback: kein Gebäude getaggt -- nimm das mit der höchsten MaxHealth dieser Stadt.
	local best, bestHealth = nil, 0
	if _G.HOUSE_TAG and _G.ResolveCityName then
		for _, house in ipairs(CollectionService:GetTagged(_G.HOUSE_TAG)) do
			if not house:GetAttribute("Destroyed") and _G.ResolveCityName(house) == cityName then
				local maxHealth = house:GetAttribute("MaxHealth") or 0
				if maxHealth > bestHealth then
					best, bestHealth = house, maxHealth
				end
			end
		end
	end
	return best and { best } or {}
end

-- ===== Schaden-API =====
local function damageGuardian(cityName, amount, attackerPlayer)
	local guardian = activeGuardians[cityName]
	if not guardian or guardian.defeated then
		return
	end

	if guardian.shield > 0 then
		guardian.shield = math.max(guardian.shield - amount, 0)
		guardian.lastHitAt = os.clock()
	else
		guardian.hp = math.max(guardian.hp - amount, 0)
	end
	updateHealthBar(guardian)

	if guardian.hp <= 0 then
		guardian.defeated = true
		guardian.state = "Defeated"

		-- Achievements: "Ersten Guardian besiegt".
		if attackerPlayer and _G.OnGuardianDefeatedForAchievements then
			_G.OnGuardianDefeatedForAchievements(attackerPlayer)
		end

		local primaryPart = guardian.model.PrimaryPart
		if primaryPart then
			local defeatSound = Instance.new("Sound")
			defeatSound.SoundId = DEFEAT_SOUND_ID
			defeatSound.Volume = 1
			defeatSound.Parent = primaryPart
			if defeatSound.SoundId ~= "" and defeatSound.SoundId ~= "rbxassetid://0" then
				defeatSound:Play()
			end
		end

		-- Langsam umkippen, dann verschwinden.
		local currentCFrame = guardian.model:GetPivot()
		local fallCFrame = currentCFrame * CFrame.Angles(math.rad(80), 0, 0)
		TweenService:Create(guardian.model.PrimaryPart, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {}):Play()
		local fallTween = TweenService:Create(guardian.humanoidRootAnchor or guardian.model.PrimaryPart, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {})
		fallTween:Play()
		task.spawn(function()
			pcall(function()
				guardian.model:PivotTo(fallCFrame)
			end)
		end)

		task.delay(2, function()
			if guardian.model and guardian.model.Parent then
				guardian.model:Destroy()
			end
		end)

		task.delay(RESPAWN_DELAY, function()
			-- Nur respawnen, falls die Stadt noch/wieder auf Level 5 ist.
			if _G.GetCityAlertLevel and _G.GetCityAlertLevel(cityName) == 5 then
				activeGuardians[cityName] = nil
				_G.SpawnGuardianForCity(cityName)
			else
				activeGuardians[cityName] = nil
			end
		end)
	end
end
_G.DamageGuardian = damageGuardian

_G.GetGuardianInfo = function(model)
	for cityName, guardian in pairs(activeGuardians) do
		if guardian.model == model then
			return cityName
		end
	end
	return nil
end

_G.IsGuardianProtectingBuilding = function(house)
	for _, guardian in pairs(activeGuardians) do
		if not guardian.defeated and guardian.state == "Block" and guardian.protectingBuilding == house then
			return true
		end
	end
	return false
end

-- Fürs CITY-BROKEN-Feature (siehe CityBrokenService.lua): true, solange diese Stadt
-- gerade einen aktiven, NICHT besiegten Guardian hat. Ein Guardian, der noch nicht
-- (re-)gespawnt ist (z.B. während der Respawn-Verzögerung nach einer Niederlage) zählt
-- als "kein aktiver Guardian" -- die Aufgabe "Titan Protocol" gilt in diesem Fenster als
-- erledigt, bis der nächste Guardian erscheint.
_G.HasActiveGuardian = function(cityName)
	local guardian = activeGuardians[cityName]
	return guardian ~= nil and not guardian.defeated
end

-- Liefert das tatsächliche Guardian-Modell einer Stadt (oder nil) -- für Szenen, die den
-- Guardian direkt manipulieren müssen (z.B. Prolog-Kinematik: Guardian dreht sich zum
-- Meer, siehe PrologueOrchestrator.lua).
_G.GetGuardianModel = function(cityName)
	local guardian = activeGuardians[cityName]
	return guardian and guardian.model
end

-- ===== Waffensysteme =====
local function fireImpactFist(guardian, target, config)
	if os.clock() - (guardian.lastFistAt or 0) < config.GuardianImpactFistCooldown then
		return
	end
	guardian.lastFistAt = os.clock()

	local fist = guardian.model:FindFirstChild("ImpactFist", true)
	local rootPart = guardian.model.PrimaryPart
	if fist then
		-- Kolben fahren kurz zurück (KCHUNK), dann Schlag nach vorne.
		local originalOffset = fist.Position - rootPart.Position
		local windupTween = TweenService:Create(fist, TweenInfo.new(0.15), {
			Position = fist.Position - rootPart.CFrame.LookVector * 1.5,
		})
		windupTween:Play()
		windupTween.Completed:Wait()

		local strikeTween = TweenService:Create(fist, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = rootPart.Position + originalOffset,
		})
		strikeTween:Play()
	end

	local fistSound = Instance.new("Sound")
	fistSound.SoundId = IMPACT_FIST_SOUND_ID
	fistSound.Volume = 0.9
	fistSound.Parent = rootPart
	if fistSound.SoundId ~= "" and fistSound.SoundId ~= "rbxassetid://0" then
		fistSound:Play()
	end
	Debris:AddItem(fistSound, 3)

	local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if targetHumanoid and targetRoot and targetHumanoid.Health > 0 then
		targetHumanoid:TakeDamage(config.GuardianImpactFistDamage)
		local pushDirection = (targetRoot.Position - rootPart.Position)
		pushDirection = Vector3.new(pushDirection.X, 0, pushDirection.Z)
		if pushDirection.Magnitude > 0.1 then
			pushDirection = pushDirection.Unit
			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			bodyVelocity.Velocity = pushDirection * config.GuardianImpactFistKnockback + Vector3.new(0, 15, 0)
			bodyVelocity.Parent = targetRoot
			Debris:AddItem(bodyVelocity, 0.2)
		end
	end
end

local function fireRepulsorPulse(guardian, cityName, config)
	if os.clock() - (guardian.lastRepulsorAt or 0) < config.GuardianRepulsorCooldown then
		return
	end
	guardian.lastRepulsorAt = os.clock()

	local core = guardian.model:FindFirstChild("ChestCore", true)
	local rootPart = guardian.model.PrimaryPart
	local origin = core and core.Position or rootPart.Position

	if core then
		local pulseTween = TweenService:Create(core, TweenInfo.new(0.15), { Transparency = 0 })
		pulseTween:Play()
	end

	local repulsorSound = Instance.new("Sound")
	repulsorSound.SoundId = REPULSOR_SOUND_ID
	repulsorSound.Volume = 0.9
	repulsorSound.Parent = rootPart
	if repulsorSound.SoundId ~= "" and repulsorSound.SoundId ~= "rbxassetid://0" then
		repulsorSound:Play()
	end
	Debris:AddItem(repulsorSound, 3)

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName and player.Character then
			local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
				local distance = (targetRoot.Position - origin).Magnitude
				if distance <= config.GuardianRepulsorRadius then
					targetHumanoid:TakeDamage(config.GuardianRepulsorDamage)
					local pushDirection = (targetRoot.Position - origin)
					pushDirection = Vector3.new(pushDirection.X, 0, pushDirection.Z)
					if pushDirection.Magnitude > 0.1 then
						pushDirection = pushDirection.Unit
						local bodyVelocity = Instance.new("BodyVelocity")
						bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
						bodyVelocity.Velocity = pushDirection * config.GuardianRepulsorKnockback + Vector3.new(0, 20, 0)
						bodyVelocity.Parent = targetRoot
						Debris:AddItem(bodyVelocity, 0.2)
					end
				end
			end
		end
	end
end

-- ===== Aegis Shield sichtbar aus-/einfahren =====
local function setAegisShieldDeployed(guardian, deployed)
	local shieldPanel = guardian.model:FindFirstChild("AegisShieldPanel", true)
	if not shieldPanel then
		return
	end
	if deployed and not guardian.shieldDeployed then
		guardian.shieldDeployed = true
		local shieldSound = Instance.new("Sound")
		shieldSound.SoundId = SHIELD_ACTIVATE_SOUND_ID
		shieldSound.Volume = 0.8
		shieldSound.Parent = guardian.model.PrimaryPart
		if shieldSound.SoundId ~= "" and shieldSound.SoundId ~= "rbxassetid://0" then
			shieldSound:Play()
		end
		Debris:AddItem(shieldSound, 3)
		TweenService:Create(shieldPanel, TweenInfo.new(0.3), { Transparency = 0.35 }):Play()
	elseif not deployed and guardian.shieldDeployed then
		guardian.shieldDeployed = false
		TweenService:Create(shieldPanel, TweenInfo.new(0.3), { Transparency = 1 }):Play()
	end
end

-- ===== Haupt-Verhalten: SCAN -> POSITIONIEREN -> BLOCKIEREN -> KONTERN =====
local ARRIVAL_THRESHOLD = 4

local function updateGuardian(cityName, guardian, config)
	if guardian.defeated or not guardian.model or not guardian.model.Parent then
		return
	end
	local rootPart = guardian.model.PrimaryPart
	if not rootPart then
		return
	end

	-- Schild-Regeneration, falls eine Weile kein Treffer kam.
	if guardian.shield < guardian.maxShield and os.clock() - (guardian.lastHitAt or 0) >= config.GuardianShieldRegenDelay then
		guardian.shield = math.min(guardian.shield + guardian.maxShield * config.GuardianShieldRegenRate * (1 / 60), guardian.maxShield)
		updateHealthBar(guardian)
	end

	local target = nil
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName and player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				target = player
				break
			end
		end
	end

	if not target then
		guardian.state = "Scan"
		guardian.protectingBuilding = nil
		setVisorActive(guardian, false)
		setAegisShieldDeployed(guardian, false)
		return
	end

	local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return
	end

	-- Nächstes geschütztes Gebäude zum Spieler finden -- der Guardian positioniert sich
	-- davor, sobald der Spieler in dessen Nähe kommt.
	local buildings = findProtectedBuildings(cityName)
	local nearestBuilding, nearestDistance = nil, math.huge
	for _, house in ipairs(buildings) do
		local housePart = house.PrimaryPart or house:FindFirstChildWhichIsA("BasePart")
		if housePart then
			local distance = (housePart.Position - targetRoot.Position).Magnitude
			if distance < nearestDistance then
				nearestBuilding, nearestDistance = house, distance
			end
		end
	end

	local SCAN_ALERT_RADIUS = 60 -- ab hier gilt der Spieler als Bedrohung für ein Gebäude

	print("[Kaiju-Debug] Guardian '" .. cityName .. "' Update -- target:", target.Name, "nearestBuilding:", nearestBuilding and nearestBuilding.Name or "keins gefunden", "nearestDistance:", nearestDistance, "SCAN_ALERT_RADIUS:", SCAN_ALERT_RADIUS, "geschützte Gebäude insgesamt:", #buildings)

	if nearestBuilding and nearestDistance <= SCAN_ALERT_RADIUS then
		guardian.protectingBuilding = nearestBuilding
		setVisorActive(guardian, true)

		local housePart = nearestBuilding.PrimaryPart or nearestBuilding:FindFirstChildWhichIsA("BasePart")
		local toPlayerDirection = (targetRoot.Position - housePart.Position)
		toPlayerDirection = Vector3.new(toPlayerDirection.X, 0, toPlayerDirection.Z)
		if toPlayerDirection.Magnitude < 0.1 then
			toPlayerDirection = Vector3.new(0, 0, 1)
		end
		toPlayerDirection = toPlayerDirection.Unit
		local blockPosition = housePart.Position + toPlayerDirection * config.GuardianProtectRadius

		local currentPosition = rootPart.Position
		local toBlockPosition = blockPosition - currentPosition
		local horizontalDistance = Vector3.new(toBlockPosition.X, 0, toBlockPosition.Z).Magnitude

		if horizontalDistance > ARRIVAL_THRESHOLD then
			guardian.state = "Position"
			setAegisShieldDeployed(guardian, false)
			local direction = Vector3.new(toBlockPosition.X, 0, toBlockPosition.Z).Unit
			local step = direction * config.GuardianMoveSpeed * RunService.Heartbeat:Wait()
			if step.Magnitude > horizontalDistance then
				step = Vector3.new(toBlockPosition.X, 0, toBlockPosition.Z)
			end
			local newPosition = currentPosition + step
			local facingCFrame = CFrame.lookAt(newPosition, newPosition - toPlayerDirection)
			guardian.model:PivotTo(facingCFrame)
		else
			-- Angekommen -- blockieren + ggf. kontern.
			guardian.state = "Block"
			setAegisShieldDeployed(guardian, true)
			local facingCFrame = CFrame.lookAt(currentPosition, currentPosition + (targetRoot.Position - currentPosition) * Vector3.new(1, 0, 1))
			guardian.model:PivotTo(facingCFrame)

			local distanceToPlayer = (targetRoot.Position - currentPosition).Magnitude
			if distanceToPlayer <= config.GuardianImpactFistRange then
				guardian.state = "Counter"
				fireImpactFist(guardian, target, config)
			elseif distanceToPlayer <= config.GuardianRepulsorRadius * 1.3 then
				fireRepulsorPulse(guardian, cityName, config)
			end
		end
	else
		guardian.protectingBuilding = nil
		guardian.state = "Scan"
		setVisorActive(guardian, false)
		setAegisShieldDeployed(guardian, false)
	end

	updateHealthBar(guardian)
end

-- ===== Spawn-Zeremonie: Bodenplatten, Sirenen, Dampf, langsames Aufrichten, dann
-- "GUARDIAN DEPLOYED". =====
local function playDeploySequence(cityName, spawnPosition)
	local deploySound = Instance.new("Sound")
	deploySound.SoundId = DEPLOY_SOUND_ID
	deploySound.Volume = 0.9
	deploySound.Parent = Workspace
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(spawnPosition)
	anchor.Parent = Workspace
	deploySound.Parent = anchor
	if deploySound.SoundId ~= "" and deploySound.SoundId ~= "rbxassetid://0" then
		deploySound:Play()
	end

	-- Dampf-Ausstoss am Boden.
	local steamAttachment = Instance.new("Attachment")
	steamAttachment.Parent = anchor
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Color3.fromRGB(210, 210, 215))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(1, 1.5)
	steam.Speed = NumberRange.new(3, 6)
	steam.Rate = 0
	steam.Parent = steamAttachment
	steam:Emit(24)

	Debris:AddItem(anchor, 15)

	-- "GUARDIAN DEPLOYED" an alle Spieler dieser Stadt.
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentCityName") == cityName then
			if _G.FlashCityAlertIndicator then
				_G.FlashCityAlertIndicator(Color3.fromRGB(90, 160, 230))
			end
		end
	end
end

-- ===== Spawnen/Despawnen =====
local function findCitySpawnPoint(cityName)
	local cityContainer
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:GetAttribute("CityName") == cityName then
			cityContainer = descendant
			break
		end
	end
	if not cityContainer then
		return nil
	end
	local spawnPart = cityContainer:FindFirstChild("GuardianSpawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.Position
	end
	if cityContainer:IsA("Model") then
		local ok, cframe = pcall(function()
			return cityContainer:GetPivot()
		end)
		if ok then
			return cframe.Position
		end
	end
	return nil
end

_G.SpawnGuardianForCity = function(cityName)
	local existing = activeGuardians[cityName]
	if existing then
		-- Zusätzliches Sicherheitsnetz (gleiches Muster wie kürzlich bei
		-- MilitaryService): nur abbrechen, wenn dort auch WIRKLICH noch ein lebendiges
		-- Modell steht -- ein Rest-Eintrag nach einem Sprung-Reset soll einen
		-- Neuaufbau nicht mehr dauerhaft blockieren können.
		if existing.model and existing.model.Parent then
			return
		end
		activeGuardians[cityName] = nil
	end
	local config = CityAlertConfig.GetCityConfig(cityName)
	if not config.GuardianHP then
		warn("[CityDefenderService] Keine Guardian-Werte für '" .. cityName .. "' konfiguriert -- übersprungen (bisher nur City vorbereitet).")
		return
	end

	local spawnPosition = findCitySpawnPoint(cityName)
	if not spawnPosition then
		warn("[CityDefenderService] Kein Spawn-Punkt für '" .. cityName .. "' gefunden (fehlt ein 'GuardianSpawn'-Part?).")
		return
	end

	local model = getGuardianTemplate(cityName)
	model.Name = "Guardian_" .. cityName
	if not model.PrimaryPart then
		-- Häufiger Stolperstein: PrimaryPart in Studio schlicht vergessen zu setzen.
		-- Automatisch das GRÖSSTE BasePart im Modell als PrimaryPart nutzen (meist der
		-- Torso/Körper-Kern -- sinnvoller als irgendein zufälliges kleines Teil), statt
		-- den Spawn komplett zu verweigern.
		local largestPart = nil
		local largestVolume = 0
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
				if volume > largestVolume then
					largestVolume = volume
					largestPart = descendant
				end
			end
		end
		if largestPart then
			model.PrimaryPart = largestPart
			warn("[CityDefenderService] Guardian-Modell '" .. cityName .. "' hatte keinen PrimaryPart gesetzt -- '" .. largestPart.Name .. "' automatisch als PrimaryPart übernommen. Empfehlung: in Studio manuell setzen (Model -> PrimaryPart-Property).")
		else
			warn("[CityDefenderService] Guardian-Modell hat keinen PrimaryPart UND kein einziges BasePart gefunden -- Spawn abgebrochen.")
			model:Destroy()
			return
		end
	end
	model:PivotTo(CFrame.new(spawnPosition))
	model.Parent = Workspace
	CollectionService:AddTag(model, "Guardian")

	local guardian = {
		model = model,
		hp = config.GuardianHP,
		maxHP = config.GuardianHP,
		shield = config.GuardianShieldHP,
		maxShield = config.GuardianShieldHP,
		state = "Scan",
		defeated = false,
		lastHitAt = 0,
		lastFistAt = 0,
		lastRepulsorAt = 0,
		shieldDeployed = false,
	}
	guardian.healthBar = createHealthBar(guardian)
	activeGuardians[cityName] = guardian

	playDeploySequence(cityName, spawnPosition)
end

local function despawnGuardianForCity(cityName)
	local guardian = activeGuardians[cityName]
	if not guardian then
		return
	end
	if guardian.model and guardian.model.Parent then
		guardian.model:Destroy()
	end
	activeGuardians[cityName] = nil
end
_G.DespawnGuardianForCity = despawnGuardianForCity

-- ===== Update-Schleife =====
RunService.Heartbeat:Connect(function()
	for cityName, guardian in pairs(activeGuardians) do
		local config = CityAlertConfig.GetCityConfig(cityName)
		local ok, err = pcall(updateGuardian, cityName, guardian, config)
		if not ok then
			warn("[CityDefenderService] Fehler bei Guardian-Update:", err)
		end
	end
end)

-- ===== Auf Alert-Level-Wechsel reagieren =====
task.spawn(function()
	local attempts = 0
	while not _G.CityAlertLevelChanged and attempts < 100 do
		task.wait(0.1)
		attempts += 1
	end
	if not _G.CityAlertLevelChanged then
		warn("[CityDefenderService] _G.CityAlertLevelChanged nie gefunden (10s Timeout) -- Level 5 bleibt wirkungslos. Läuft CityAlertService.lua?")
		return
	end

	_G.CityAlertLevelChanged.Event:Connect(function(cityName, newLevel, oldLevel)
		if newLevel == 5 and oldLevel == 4 then
			_G.SpawnGuardianForCity(cityName)
		elseif newLevel < 5 and oldLevel >= 5 then
			-- WICHTIG: reagiert auf JEDEN Abfall unter Level 5, nicht nur den exakten
			-- 5->4-Schritt -- ein Sprung-Reset (z.B. CITY BROKEN: 5->0 in einem Schritt)
			-- hätte den alten, exakten Trigger sonst nie ausgelöst und activeGuardians
			-- wäre dauerhaft hängen geblieben (gleicher Bug wie kürzlich bei
			-- MilitaryService gefunden und behoben).
			despawnGuardianForCity(cityName)
		end
	end)
end)

print("[Kaiju] CityDefenderService bereit -- Level 5 (Guardian, vorerst nur City).")