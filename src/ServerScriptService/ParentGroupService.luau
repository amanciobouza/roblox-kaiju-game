print("Hello world!")
-- VERSION: 2026-08-25 #1
-- ModuleScript: ParentGroupService
-- Ort in Studio: ServerScriptService (gleiche Ebene wie HouseHandler.lua)
--
-- Ausgelagert aus HouseHandler.lua (war dort auf zwei getrennte Abschnitte verteilt:
-- "L3 ParentGroup Helpers" + "L3 ParentGroup Visual State").
--
-- Zuständig für Gebäude, die aus mehreren separat angreifbaren Teilen bestehen, aber
-- GEMEINSAM respawnen sollen (z.B. das Roadside Motel mit drei Trakten). Ohne dieses
-- System würde jeder Trakt unabhängig respawnen, sobald SEIN eigener Timer abläuft --
-- das würde bei einem als EIN Gebäude gedachten Asset unrealistisch aussehen (ein Trakt
-- kommt zurück, während die anderen noch in Trümmern liegen).
--
-- Ablauf:
--   1) Jeder Trakt bleibt einzeln angreifbar/zerstörbar (eigenes Leben, eigene
--      Zerstörungs-Animation über die normale HouseHandler-Logik).
--   2) Kein Trakt respawnt für sich allein -- stattdessen wird bei JEDER Zerstörung
--      geprüft, ob jetzt ALLE Trakte der Gruppe zerstört sind.
--   3) Erst wenn das der Fall ist, startet EIN gemeinsamer Respawn-Timer.
--   4) Nach Ablauf kommen ALLE Trakte gleichzeitig zurück.
--   5) Zusätzlich: visuelle Sonderbehandlung fürs gemeinsame Wahrzeichen (z.B. das
--      "MotelSign") -- hängt schief/flackert unregelmässig, sobald die GANZE Gruppe
--      zerstört ist, unabhängig von den einzelnen Trakten.
--
-- WICHTIG -- Dependency Injection: dieses Modul kennt bewusst NICHT die internen
-- Zerstörungs-/Respawn-Helfer aus HouseHandler.lua (extinguishHouseFire, hideRuin,
-- setHouseVisible, growHouseFromGround) -- die werden stattdessen einmalig über Init()
-- übergeben. Das hält die Abhängigkeit explizit sichtbar (statt über _G zu laufen) und
-- vermeidet einen Zirkelbezug zwischen den beiden Dateien.

local EnergyTypeSkin
do
	local energyTypeSkinModule = script.Parent:WaitForChild("EnergyTypeSkin", 5)
	if energyTypeSkinModule then
		EnergyTypeSkin = require(energyTypeSkinModule)
	else
		warn("[ParentGroupService] ModuleScript 'EnergyTypeSkin' nicht gefunden (Timeout) -- Energie-Typ-Optik beim Gruppen-Respawn bleibt wirkungslos.")
		EnergyTypeSkin = { Apply = function() end }
	end
end

local ParentGroupService = {}

-- ===== Zustand (ersetzt die vorher in HouseHandler.lua lokalen Tabellen) =====
local parentGroupByHouse = {} -- [sectionHouse] = parentGroupModel
local parentGroupMembers = {} -- [parentGroupModel] = { sectionHouse, ... }
local parentGroupRespawnScheduled = {} -- [parentGroupModel] = true/nil
local parentGroupVisualSnapshots = {} -- [group] = snapshot der Wahrzeichen-Teile (z.B. MotelSign)

-- ===== Injizierte Abhängigkeiten (siehe ParentGroupService.Init weiter unten) =====
local deps = {
	extinguishHouseFire = function() end,
	hideRuin = function() end,
	setHouseVisible = function() end,
	growHouseFromGround = function() end,
	DEFAULT_HEALTH = 100,
	RESPAWN_TIME = 30,
}

function ParentGroupService.Init(dependencies)
	for key, value in pairs(dependencies) do
		deps[key] = value
	end
end

-- ===== L3 ParentGroup Helpers =====================================================
-- Sucht für eine Sektion den gemeinsamen Asset-Root (z.B. RoadsideMotel_L3).
local function resolveParentGroup(house)
	if house:GetAttribute("RespawnMode") ~= "ParentGroup" then
		return nil
	end

	local node = house.Parent
	while node do
		if node:IsA("Model") and (node:GetAttribute("UsesSectionHealth") == true or node:GetAttribute("SpawnAsSingleAsset") == true) then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Registriert ein Haus als Mitglied seiner ParentGroup (falls vorhanden) -- aufzurufen
-- beim initHouse() JEDES Hauses (auch solcher ohne ParentGroup, resolveParentGroup gibt
-- dann einfach nil zurück und es passiert nichts).
function ParentGroupService.Register(house)
	local group = resolveParentGroup(house)
	if not group then
		return
	end

	parentGroupByHouse[house] = group
	parentGroupMembers[group] = parentGroupMembers[group] or {}

	for _, existing in ipairs(parentGroupMembers[group]) do
		if existing == house then
			return
		end
	end
	table.insert(parentGroupMembers[group], house)
end

function ParentGroupService.IsParentGroupHouse(house)
	return house:GetAttribute("RespawnMode") == "ParentGroup"
end

-- Liefert die ParentGroup eines Hauses (oder nil, falls es keiner Gruppe angehört) --
-- ersetzt den früher direkten Tabellen-Zugriff parentGroupByHouse[house] von ausserhalb.
function ParentGroupService.GetGroup(house)
	return parentGroupByHouse[house]
end

local function allParentGroupMembersDestroyed(group)
	local members = parentGroupMembers[group]
	if not members or #members == 0 then
		return false
	end

	-- Optional erwartete Sektionszahl vom Asset. Motel = 3. Falls nicht gesetzt,
	-- reicht die Zahl der registrierten Mitglieder.
	local expected = tonumber(group:GetAttribute("WingCount") or group:GetAttribute("SectionCount")) or #members
	if #members < expected then
		return false
	end

	for _, member in ipairs(members) do
		if not member:GetAttribute("Destroyed") then
			return false
		end
	end
	return true
end

-- ===== L3 ParentGroup Visual State ===============================================
-- Group-level landmarks (e.g. the Roadside Motel sign) are NOT combat sections.
-- They react only when the entire ParentGroup has been destroyed.

local function findGroupMotelSign(group)
	if not group then
		return nil
	end
	local sign = group:FindFirstChild("MotelSign")
	if sign and (sign:IsA("Folder") or sign:IsA("Model")) then
		return sign
	end
	return nil
end

local function snapshotParentGroupVisuals(group)
	if parentGroupVisualSnapshots[group] then
		return parentGroupVisualSnapshots[group]
	end

	local sign = findGroupMotelSign(group)
	if not sign then
		parentGroupVisualSnapshots[group] = { sign = nil }
		return parentGroupVisualSnapshots[group]
	end

	local snapshot = {
		sign = sign,
		parts = {},
		lights = {},
		scripts = {},
	}

	local minY = math.huge
	local sumX, sumZ, count = 0, 0, 0

	for _, obj in ipairs(sign:GetDescendants()) do
		if obj:IsA("BasePart") then
			snapshot.parts[obj] = {
				cframe = obj.CFrame,
				size = obj.Size,
			}
			sumX += obj.Position.X
			sumZ += obj.Position.Z
			count += 1

			local bottomY = obj.Position.Y - obj.Size.Y / 2
			if bottomY < minY then
				minY = bottomY
			end
		elseif obj:IsA("Light") then
			snapshot.lights[obj] = obj.Enabled
		elseif obj:IsA("TextLabel") then
			snapshot.textLabels = snapshot.textLabels or {}
			snapshot.textLabels[obj] = {
				textColor3 = obj.TextColor3,
				textTransparency = obj.TextTransparency,
				textStrokeTransparency = obj.TextStrokeTransparency,
				visible = obj.Visible,
			}
		elseif obj:IsA("Script") or obj:IsA("LocalScript") then
			snapshot.scripts[obj] = obj.Enabled
		end
	end

	if count > 0 then
		snapshot.pivot = Vector3.new(sumX / count, minY + 0.15, sumZ / count)
	end

	parentGroupVisualSnapshots[group] = snapshot
	return snapshot
end

local function applyParentGroupDestroyedVisual(group)
	if not group or group:GetAttribute("GroupDestroyedVisualApplied") then
		return
	end

	local snapshot = snapshotParentGroupVisuals(group)
	local sign = snapshot and snapshot.sign
	local pivot = snapshot and snapshot.pivot
	if not sign or not pivot then
		-- Not every ParentGroup needs a special landmark.
		group:SetAttribute("GroupDestroyedVisualApplied", true)
		return
	end

	group:SetAttribute("GroupDestroyedVisualApplied", true)
	group:SetAttribute("MotelSignVisualState", "Damaged")

	-- Stop illumination/flicker once the entire motel is destroyed.
	for light, _ in pairs(snapshot.lights) do
		if light and light.Parent then
			light.Enabled = false
		end
	end
	for scriptObj, _ in pairs(snapshot.scripts) do
		if scriptObj and scriptObj.Parent and scriptObj ~= script then
			scriptObj.Enabled = false
		end
	end

	local pivotCF = CFrame.new(pivot)
	local damagedCF =
		CFrame.new(pivot + Vector3.new(0, -0.95, 0))
		* CFrame.Angles(math.rad(7), math.rad(-3), math.rad(-28))

	for part, state in pairs(snapshot.parts) do
		if part and part.Parent then
			local relative = pivotCF:ToObjectSpace(state.cframe)
			part.CFrame = damagedCF * relative
		end
	end

	-- The actual MOTEL panel hangs even more crooked than the support frame:
	-- extra side tilt, extra pitch, and a small downward slide.
	local mainPanel = sign:FindFirstChild("MotelSignMain", true)
	if mainPanel and mainPanel:IsA("BasePart") then
		mainPanel.CFrame =
			mainPanel.CFrame
			* CFrame.new(0, -0.75, 0)
			* CFrame.Angles(math.rad(8), math.rad(-2), math.rad(-16))
	end

	-- If a separate visual marquee/panel part exists, damage it together with the main panel.
	for _, candidateName in ipairs({
		"RoadBrandPanel",
		"MotelBrandPanel",
		"MotelSignPanel",
		"SignFace",
		}) do
		local panel = sign:FindFirstChild(candidateName, true)
		if panel and panel:IsA("BasePart") and panel ~= mainPanel then
			panel.CFrame =
				panel.CFrame
				* CFrame.new(0, -0.55, 0)
				* CFrame.Angles(math.rad(6), 0, math.rad(-12))
		end
	end

	-- One support visibly fails while the other still carries the hanging sign.
	local post1 = sign:FindFirstChild("SignPost_1", true)
	if post1 and post1:IsA("BasePart") then
		local state = snapshot.parts[post1]
		if state then
			local oldHeight = state.size.Y
			local newHeight = oldHeight * 0.58
			post1.Size = Vector3.new(state.size.X, newHeight, state.size.Z)
			post1.CFrame =
				post1.CFrame
				* CFrame.new(0, -(oldHeight - newHeight) * 0.18, 0)
				* CFrame.Angles(0, 0, math.rad(-7))
		end
	end

	local post2 = sign:FindFirstChild("SignPost_2", true)
	if post2 and post2:IsA("BasePart") then
		post2.CFrame = post2.CFrame * CFrame.Angles(math.rad(2), 0, math.rad(5))
	end

	-- Damaged marquee behavior:
	-- M and T fail completely.
	-- O and E flicker irregularly.
	-- L remains steadily lit so the sign still feels electrically alive.
	local marqueeLetters = {}
	for _, obj in ipairs(sign:GetDescendants()) do
		if obj:IsA("TextLabel") and string.sub(obj.Name, 1, 7) == "Letter_" then
			local ch = string.sub(obj.Name, 8)
			marqueeLetters[ch] = marqueeLetters[ch] or {}
			table.insert(marqueeLetters[ch], obj)
		end
	end

	local function setLetterState(letter, on)
		for _, label in ipairs(marqueeLetters[letter] or {}) do
			if label and label.Parent then
				if on then
					label.Visible = true
					label.TextTransparency = 0
					label.TextStrokeTransparency = 0.42
					label.TextColor3 = Color3.fromRGB(255, 214, 145)
				else
					label.Visible = true
					label.TextTransparency = 0.88
					label.TextStrokeTransparency = 1
					label.TextColor3 = Color3.fromRGB(80, 58, 52)
				end
			end
		end
	end

	setLetterState("M", false)
	setLetterState("T", false)
	setLetterState("L", true)

	-- One shared generation value ensures old flicker loops die after respawn/re-damage.
	local generation = (group:GetAttribute("MotelDamagedFlickerGeneration") or 0) + 1
	group:SetAttribute("MotelDamagedFlickerGeneration", generation)

	local function startDamagedFlicker(letter, minDelay, maxDelay)
		task.spawn(function()
			local rng = Random.new()
			while group.Parent
				and group:GetAttribute("GroupDestroyedVisualApplied") == true
				and group:GetAttribute("MotelDamagedFlickerGeneration") == generation do

				setLetterState(letter, true)
				task.wait(rng:NextNumber(minDelay, maxDelay))

				-- Rapid loose-contact flutter.
				for _ = 1, rng:NextInteger(2, 5) do
					if group:GetAttribute("GroupDestroyedVisualApplied") ~= true
						or group:GetAttribute("MotelDamagedFlickerGeneration") ~= generation then
						return
					end
					setLetterState(letter, false)
					task.wait(rng:NextNumber(0.035, 0.14))
					setLetterState(letter, true)
					task.wait(rng:NextNumber(0.04, 0.20))
				end

				if rng:NextNumber() < 0.35 then
					setLetterState(letter, false)
					task.wait(rng:NextNumber(0.25, 0.8))
				end
			end
		end)
	end

	startDamagedFlicker("O", 1.8, 4.6)
	startDamagedFlicker("E", 2.8, 6.5)

	print("[ParentGroupService] Finale Wahrzeichen-Optik angewendet für '" .. group:GetFullName() .. "'")
end

local function restoreParentGroupVisual(group)
	local snapshot = parentGroupVisualSnapshots[group]
	if not snapshot then
		return
	end

	for part, state in pairs(snapshot.parts or {}) do
		if part and part.Parent then
			part.Size = state.size
			part.CFrame = state.cframe
		end
	end

	for light, enabled in pairs(snapshot.lights or {}) do
		if light and light.Parent then
			light.Enabled = enabled
		end
	end

	for scriptObj, enabled in pairs(snapshot.scripts or {}) do
		if scriptObj and scriptObj.Parent and scriptObj ~= script then
			scriptObj.Enabled = enabled
		end
	end

	for label, state in pairs(snapshot.textLabels or {}) do
		if label and label.Parent then
			label.TextColor3 = state.textColor3
			label.TextTransparency = state.textTransparency
			label.TextStrokeTransparency = state.textStrokeTransparency
			label.Visible = state.visible
		end
	end

	-- Kill all old damaged-state flicker loops.
	group:SetAttribute(
		"MotelDamagedFlickerGeneration",
		(group:GetAttribute("MotelDamagedFlickerGeneration") or 0) + 1
	)

	group:SetAttribute("GroupDestroyedVisualApplied", false)
	group:SetAttribute("MotelSignVisualState", "Intact")
end

local function performParentGroupRespawn(group)
	local members = parentGroupMembers[group]
	if not members then
		return
	end

	-- Restore group-level landmark visual together with the complete asset.
	restoreParentGroupVisual(group)

	-- ZUERST alle Sektionen logisch/sichtbar gemeinsam zurücksetzen. Kein Staggering.
	for _, house in ipairs(members) do
		deps.extinguishHouseFire(house)
		local maxHealth = house:GetAttribute("MaxHealth") or deps.DEFAULT_HEALTH
		house:SetAttribute("Health", maxHealth)
		house:SetAttribute("Destroyed", false)
		house:SetAttribute("SectionDestroyed", false)
		house:SetAttribute("EnergyCollectionActive", false)
		house:SetAttribute("RespawnEligible", false)
		deps.hideRuin(house)
		deps.setHouseVisible(house, true)
		-- Energie-Typ-Überraschung auch hier neu würfeln (nur Heat-Sektionen betroffen).
		EnergyTypeSkin.Apply(house)
	end

	-- Danach die Wiederaufricht-Animation aller Trakte gleichzeitig starten.
	for _, house in ipairs(members) do
		task.spawn(function()
			deps.growHouseFromGround(house)
		end)
	end

	group:SetAttribute("GroupRespawnReady", false)
	group:SetAttribute("RespawnTimerArmed", false)
	group:SetAttribute("AggregateDestroyed", false)
	group:SetAttribute("AggregateDamageState", "Intact")
	group:SetAttribute("AllSectionsDestroyed", false)
	group:SetAttribute("GroupRespawnAt", 0)
	parentGroupRespawnScheduled[group] = nil
end

-- Aufzurufen, sobald ein Trakt der Gruppe zerstört wurde -- prüft intern, ob JETZT alle
-- Trakte zerstört sind, und startet den gemeinsamen Respawn-Timer nur dann. Mehrfache
-- Aufrufe sind sicher (parentGroupRespawnScheduled verhindert doppelte Timer).
function ParentGroupService.ScheduleRespawn(group)
	if not group or parentGroupRespawnScheduled[group] then
		return
	end
	if not allParentGroupMembersDestroyed(group) then
		return
	end

	parentGroupRespawnScheduled[group] = true
	local now = workspace:GetServerTimeNow()
	group:SetAttribute("GroupRespawnReady", true)
	group:SetAttribute("RespawnTimerArmed", true)
	group:SetAttribute("AggregateDestroyed", true)
	group:SetAttribute("AggregateDamageState", "Destroyed")
	group:SetAttribute("AllSectionsDestroyed", true)
	group:SetAttribute("AllWingsDestroyedAt", now)
	group:SetAttribute("GroupRespawnAt", now + deps.RESPAWN_TIME)

	-- Group landmark visual is applied DIRECTLY here. No second observer script,
	-- no attribute race, and works with MotelSign being a Folder.
	applyParentGroupDestroyedVisual(group)

	-- Das Asset kann zusätzlich auf AllSectionsDestroyed hören, muss es aber nicht.
	print("[ParentGroupService] Gruppe vollständig zerstört: '" .. group:GetFullName() .. "' -- gemeinsamer Respawn in " .. deps.RESPAWN_TIME .. "s")

	task.delay(deps.RESPAWN_TIME, function()
		if group and group.Parent and allParentGroupMembersDestroyed(group) then
			performParentGroupRespawn(group)
		else
			parentGroupRespawnScheduled[group] = nil
		end
	end)
end

return ParentGroupService