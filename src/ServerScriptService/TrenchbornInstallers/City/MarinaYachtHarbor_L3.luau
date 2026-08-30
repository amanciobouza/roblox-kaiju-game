--============================================================
-- TRENCHBORN FINAL INSTALLER
-- MARINA / YACHT HARBOR L3
--
-- VERSION: Marina_L3_Final_v01
--
-- Final approved contract:
--   Level: L3
--   EnergyType: Heat
--   7 independently destructible Sections
--   Total HP: 19,000
--   GroupRoot / ParentGroup shared respawn
--   NO special destruction signatures
--   NO additional destruction FX
--
-- Existing approved geometry + dressing are preserved.
--============================================================

local M = {}

M.VERSION = "Marina_L3_Final_v02"

------------------------------------------------------------
-- SERVICES
------------------------------------------------------------

local Workspace =
	game:GetService("Workspace")

local CollectionService =
	game:GetService("CollectionService")

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local ROOT_NAME =
	"TB_City_MarinaYachtHarbor_L3_GoldenMaster_v01"

local SECTION_CONFIG = {

	{
		name = "Section_01_Entrance",
		role = "Entrance",
		hp = 1500,
	},

	{
		name = "Section_02_HarborClub",
		role = "HarborClub",
		hp = 4000,
	},

	{
		name = "Section_03_MainQuay",
		role = "MainQuay",
		hp = 4000,
	},

	{
		name = "Section_04_DockA",
		role = "DockA",
		hp = 2000,
	},

	{
		name = "Section_05_DockB",
		role = "DockB",
		hp = 2500,
	},

	{
		name = "Section_06_DockC",
		role = "DockC",
		hp = 2000,
	},

	{
		name = "Section_07_ServiceDock",
		role = "ServiceDock",
		hp = 3000,
	},
}

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function getRoot()

	return Workspace:FindFirstChild(
		ROOT_NAME,
		true
	)
end

local function getSections(root)

	local sections = {}

	for index,cfg in ipairs(
		SECTION_CONFIG
		) do

		local section =
			root:FindFirstChild(
				cfg.name
			)

		assert(
			section
				and section:IsA("Model"),
			cfg.name.." missing"
		)

		sections[index] =
			section
	end

	return sections
end

------------------------------------------------------------
-- STATUS
------------------------------------------------------------

function M.Status()

	local root = getRoot()

	print("")
	print("====================================================")
	print("[TB STATUS] MARINA / YACHT HARBOR L3")
	print("Module:         ",M.VERSION)

	if not root then

		print("Asset:           NOT FOUND")
		print("====================================================")
		return
	end

	print(
		"InstallerStatus:",
		root:GetAttribute(
			"InstallerStatus"
		)
	)

	print(
		"Installed:      ",
		root:GetAttribute(
			"InstalledVersion"
		)
	)

	print(
		"EnergyType:     ",
		root:GetAttribute(
			"EnergyType"
		)
	)

	print(
		"Level:          ",
		root:GetAttribute(
			"AssetLevel"
		)
	)

	print(
		"Sections:       ",
		root:GetAttribute(
			"SectionCount"
		)
	)

	print(
		"RespawnMode:    ",
		root:GetAttribute(
			"RespawnMode"
		)
	)

	print(
		"SectionHealth:  ",
		root:GetAttribute(
			"UsesSectionHealth"
		)
	)

	print(
		"SingleAsset:    ",
		root:GetAttribute(
			"SpawnAsSingleAsset"
		)
	)

	print("====================================================")
end

------------------------------------------------------------
-- VALIDATE
------------------------------------------------------------

function M.Validate()

	local root = getRoot()

	print("")
	print("====================================================")
	print("[TB VALIDATE] MARINA / YACHT HARBOR L3")

	if not root then

		warn("✗ Marina asset not found")
		print("")
		print("RESULT: FAIL")
		print("====================================================")

		return false
	end

	local ok = true

	local function check(
		condition,
		text
	)

		if condition then

			print(
				"✓",
				text
			)

		else

			warn(
				"✗",
				text
			)

			ok = false
		end
	end

	--------------------------------------------------------
	-- ROOT
	--------------------------------------------------------

	check(
		root:GetAttribute(
			"AssetLevel"
		) == "L3",
		"AssetLevel = L3"
	)

	check(
		root:GetAttribute(
			"EnergyType"
		) == "Heat",
		"EnergyType = Heat"
	)

	check(
		root:GetAttribute(
			"SectionCount"
		) == 7,
		"SectionCount = 7"
	)

	check(
		root:GetAttribute(
			"UsesSectionHealth"
		) == true,
		"UsesSectionHealth = true"
	)

	check(
		root:GetAttribute(
			"SpawnAsSingleAsset"
		) == true,
		"SpawnAsSingleAsset = true"
	)

	check(
		root:GetAttribute(
			"RespawnMode"
		) == "GroupRoot",
		"Root RespawnMode = GroupRoot"
	)

	--------------------------------------------------------
	-- SECTIONS
	--------------------------------------------------------

	local totalHP = 0

	for index,cfg in ipairs(
		SECTION_CONFIG
		) do

		local section =
			root:FindFirstChild(
				cfg.name
			)

		check(
			section ~= nil,
			cfg.name.." exists"
		)

		if section then

			check(
				CollectionService:HasTag(
					section,
					"KaijuHouse"
				),
				cfg.name.." KaijuHouse"
			)

			check(
				CollectionService:HasTag(
					section,
					"KaijuL3"
				),
				cfg.name.." KaijuL3"
			)

			check(
				section:GetAttribute(
					"EnergyType"
				) == "Heat",
				cfg.name.." EnergyType=Heat"
			)

			check(
				section:GetAttribute(
					"MaxHealth"
				) == cfg.hp,
				cfg.name..
					" MaxHealth="..
					cfg.hp
			)

			check(
				section:GetAttribute(
					"RespawnMode"
				) == "ParentGroup",
				cfg.name..
					" RespawnMode=ParentGroup"
			)

			check(
				section:GetAttribute(
					"SpawnSeparately"
				) == false,
				cfg.name..
					" SpawnSeparately=false"
			)

			check(
				section:GetAttribute(
					"SuppressIndividualRespawn"
				) == true,
				cfg.name..
					" SuppressIndividualRespawn=true"
			)

			check(
				section:GetAttribute(
					"SectionIndex"
				) == index,
				cfg.name..
					" SectionIndex="..
					index
			)

			totalHP +=
				section:GetAttribute(
					"MaxHealth"
				) or 0
		end
	end

	check(
		totalHP == 19000,
		"Total MaxHealth = 19000"
	)

	--------------------------------------------------------
	-- DRESSING
	--------------------------------------------------------

	check(
		root:FindFirstChild(
			"Dressing_5_1_Signage"
		) ~= nil,
		"Signage dressing present"
	)

	check(
		root:FindFirstChild(
			"Dressing_5_2_LightingSafety"
		) ~= nil,
		"Lighting/Safety dressing present"
	)

	check(
		root:FindFirstChild(
			"Dressing_5_3_FinalDetails"
		) ~= nil,
		"Final detail dressing present"
	)

	--------------------------------------------------------
	-- BOATS
	--------------------------------------------------------

	local expectedBoats = {
		"SmallMotor_01",
		"SmallMotor_02",
		"SmallMotor_03",
		"ServiceBoat_01",
		"SportYacht_01",
		"SportYacht_02",
		"SportYacht_03",
		"CabinYacht_01",
		"CabinYacht_02",
	}

	local boatCount = 0

	for _,name in ipairs(
		expectedBoats
		) do

		local boat =
			root:FindFirstChild(
				name,
				true
			)

		check(
			boat ~= nil,
			name.." present"
		)

		if boat then
			boatCount += 1
		end
	end

	check(
		boatCount == 9,
		"9 Marina boats present"
	)

	--------------------------------------------------------
	-- LIGHTS
	--------------------------------------------------------

	local lightCount = 0

	for _,obj in ipairs(
		root:GetDescendants()
		) do

		if obj:IsA("Light") then
			lightCount += 1
		end
	end

	check(
		lightCount > 0,
		"Marina lighting present ("
			..lightCount..")"
	)

	--------------------------------------------------------
	-- VERSION
	--------------------------------------------------------

	check(
		root:GetAttribute(
			"InstalledVersion"
		) == M.VERSION,
		"InstalledVersion = "..M.VERSION
	)

	print("")
	print(
		ok
			and "RESULT: PASS"
			or "RESULT: FAIL"
	)

	print("====================================================")

	return ok
end

------------------------------------------------------------
-- FINAL APPROVED PHASE-5 DRESSING
------------------------------------------------------------

local function installApprovedDressing(root)

	local NAVY   = Color3.fromRGB(30,54,70)
	local WHITE  = Color3.fromRGB(238,239,234)
	local WARM   = Color3.fromRGB(255,226,165)
	local RED    = Color3.fromRGB(177,48,42)
	local METAL  = Color3.fromRGB(68,75,78)
	local RUBBER = Color3.fromRGB(34,37,38)
	local GREEN  = Color3.fromRGB(59,91,64)
	local SOIL   = Color3.fromRGB(76,57,42)

	--------------------------------------------------------
	-- HELPERS
	--------------------------------------------------------

	local function model(parent,name,sectionRole)

		local m = Instance.new("Model")
		m.Name = name
		m.Parent = parent

		if sectionRole then
			m:SetAttribute(
				"DestructionSection",
				sectionRole
			)
		end

		return m
	end

	local function part(
		parent,
		name,
		size,
		cf,
		color,
		material,
		sectionRole
	)

		local p = Instance.new("Part")

		p.Name = name
		p.Size = size
		p.CFrame = cf

		p.Color = color
		p.Material =
			material
			or Enum.Material.SmoothPlastic

		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = true

		p.TopSurface =
			Enum.SurfaceType.Smooth

		p.BottomSurface =
			Enum.SurfaceType.Smooth

		if sectionRole then
			p:SetAttribute(
				"DestructionSection",
				sectionRole
			)
		end

		p.Parent = parent

		return p
	end

	local function cylinder(
		parent,
		name,
		size,
		cf,
		color,
		material,
		sectionRole
	)

		local p = part(
			parent,
			name,
			size,
			cf,
			color,
			material,
			sectionRole
		)

		p.Shape =
			Enum.PartType.Cylinder

		return p
	end

	local function addText(
		target,
		face,
		text,
		color
	)

		local gui =
			Instance.new("SurfaceGui")

		gui.Name = "SignGui"
		gui.Face = face
		gui.AlwaysOnTop = false

		gui.SizingMode =
			Enum.SurfaceGuiSizingMode.PixelsPerStud

		gui.PixelsPerStud = 60
		gui.Parent = target

		local label =
			Instance.new("TextLabel")

		label.Name = "Text"

		label.Size =
			UDim2.fromScale(1,1)

		label.BackgroundTransparency = 1

		label.Text = text
		label.TextColor3 = color
		label.Font = Enum.Font.GothamBold

		-- mandatory Trenchborn rule
		label.TextScaled = true

		label.Parent = gui

		return label
	end

	local function addLight(
		target,
		brightness,
		range
	)

		local l =
			Instance.new("PointLight")

		l.Name = "MarinaLight"

		l.Color = WARM
		l.Brightness = brightness
		l.Range = range
		l.Shadows = false
		l.Enabled = true

		l.Parent = target

		return l
	end

	--------------------------------------------------------
	-- SECTIONS
	--------------------------------------------------------

	local entrance =
		root:FindFirstChild(
			"Section_01_Entrance"
		)

	local club =
		root:FindFirstChild(
			"Section_02_HarborClub"
		)

	local quay =
		root:FindFirstChild(
			"Section_03_MainQuay"
		)

	local dockA =
		root:FindFirstChild(
			"Section_04_DockA"
		)

	local dockB =
		root:FindFirstChild(
			"Section_05_DockB"
		)

	local dockC =
		root:FindFirstChild(
			"Section_06_DockC"
		)

	local service =
		root:FindFirstChild(
			"Section_07_ServiceDock"
		)

	assert(entrance,"Entrance missing")
	assert(club,"Harbor Club missing")
	assert(quay,"Main Quay missing")
	assert(dockA,"Dock A missing")
	assert(dockB,"Dock B missing")
	assert(dockC,"Dock C missing")
	assert(service,"Service Dock missing")

	--------------------------------------------------------
	-- REMOVE OLD DRESSING
	--
	-- Makes Install() idempotent.
	--------------------------------------------------------

	for _,name in ipairs({
		"Dressing_5_1_Signage",
		"Dressing_5_2_LightingSafety",
		"Dressing_5_3_FinalDetails",
		}) do

		local old =
			root:FindFirstChild(name)

		if old then
			old:Destroy()
		end
	end

	--======================================================
	-- 5.1 SIGNAGE
	--======================================================

	local signage =
		model(
			root,
			"Dressing_5_1_Signage"
		)

	--------------------------------------------------------
	-- COASTLINE MARINA
	--------------------------------------------------------

	local header =
		entrance:FindFirstChild(
			"Header"
		)

	assert(header,"Entrance Header missing")

	local marinaSign =
		part(
			signage,
			"CoastlineMarina_Sign",

			Vector3.new(
				header.Size.X - 0.5,
				1.55,
				0.16
			),

			header.CFrame
			* CFrame.new(
				0,
				0,
				-header.Size.Z/2 - 0.09
			),

			NAVY,
			nil,
			"Entrance"
		)

	addText(
		marinaSign,
		Enum.NormalId.Front,
		"COASTLINE MARINA",
		WHITE
	)

	--------------------------------------------------------
	-- HARBOR CLUB
	-- FINAL APPROVED POSITION: ON WATERFRONT CANOPY
	--------------------------------------------------------

	local canopy =
		club:FindFirstChild(
			"WaterfrontCanopy"
		)

	assert(canopy,"WaterfrontCanopy missing")

	local clubSign =
		part(
			signage,
			"HarborClub_Sign",

			Vector3.new(
				8.8,
				1.0,
				0.16
			),

			canopy.CFrame
			* CFrame.new(
				0,
				-0.20,
				canopy.Size.Z/2 + 0.09
			)
			* CFrame.Angles(
				0,
				math.rad(180),
				0
			),

			NAVY,
			nil,
			"HarborClub"
		)

	addText(
		clubSign,
		Enum.NormalId.Front,
		"HARBOR CLUB",
		WHITE
	)

	--------------------------------------------------------
	-- DOCK MARKERS
	-- approved smaller size
	--------------------------------------------------------

	local function dockMarker(
		section,
		dockName,
		letter,
		role
	)

		local dock =
			section:FindFirstChild(
				dockName
			)

		assert(dock,dockName.." missing")

		local deck =
			dock:FindFirstChild(
				"MainDeck"
			)

		assert(deck,dockName.." MainDeck missing")

		local base =
			deck.CFrame
			* CFrame.new(
				0,
				1.25,
				-deck.Size.Z/2 + 1.2
			)

		part(
			signage,
			"Dock"..letter.."_MarkerPost",

			Vector3.new(
				0.25,
				2.15,
				0.25
			),

			base,

			METAL,
			Enum.Material.Metal,
			role
		)

		local sign =
			part(
				signage,
				"Dock"..letter.."_Marker",

				Vector3.new(
					1.35,
					1.35,
					0.16
				),

				base
				* CFrame.new(
					0,
					1.25,
					0
				),

				NAVY,
				nil,
				role
			)

		addText(
			sign,
			Enum.NormalId.Front,
			letter,
			WHITE
		)

		addText(
			sign,
			Enum.NormalId.Back,
			letter,
			WHITE
		)
	end

	dockMarker(
		dockA,
		"DockA",
		"A",
		"DockA"
	)

	dockMarker(
		dockB,
		"DockB",
		"B",
		"DockB"
	)

	dockMarker(
		dockC,
		"DockC",
		"C",
		"DockC"
	)

	--------------------------------------------------------
	-- FUEL / SERVICE
	--------------------------------------------------------

	local fuelCanopy =
		service:FindFirstChild(
			"FuelCanopy"
		)

	assert(
		fuelCanopy,
		"FuelCanopy missing"
	)

	local fuelSign =
		part(
			signage,
			"FuelService_Sign",

			Vector3.new(
				6.6,
				1.1,
				0.16
			),

			fuelCanopy.CFrame
			* CFrame.new(
				0,
				-0.30,
				-fuelCanopy.Size.Z/2 - 0.09
			),

			NAVY,
			nil,
			"ServiceDock"
		)

	addText(
		fuelSign,
		Enum.NormalId.Front,
		"FUEL • SERVICE",
		WHITE
	)

	--------------------------------------------------------
	-- NO SMOKING
	--------------------------------------------------------

	local safety =
		service:FindFirstChild(
			"SafetyCabinet"
		)

	assert(
		safety,
		"SafetyCabinet missing"
	)

	local noSmoking =
		part(
			signage,
			"NoSmoking_Sign",

			Vector3.new(
				1.4,
				0.85,
				0.10
			),

			safety.CFrame
			* CFrame.new(
				0,
				0.15,
				-safety.Size.Z/2 - 0.06
			),

			WHITE,
			nil,
			"ServiceDock"
		)

	addText(
		noSmoking,
		Enum.NormalId.Front,
		"NO\nSMOKING",
		RED
	)

	--======================================================
	-- 5.2 LIGHTING / SAFETY
	--======================================================

	local lighting =
		model(
			root,
			"Dressing_5_2_LightingSafety"
		)

	--------------------------------------------------------
	-- ENTRANCE LIGHTS
	--------------------------------------------------------

	for i,name in ipairs({
		"LeftPillar",
		"RightPillar",
		}) do

		local pillar =
			entrance:FindFirstChild(name)

		assert(pillar,name.." missing")

		local lamp =
			part(
				lighting,
				"EntranceLamp_"..i,

				Vector3.new(
					0.55,
					0.65,
					0.45
				),

				pillar.CFrame
				* CFrame.new(
					0,
					0.8,
					-pillar.Size.Z/2 - 0.25
				),

				WARM,
				Enum.Material.Neon,
				"Entrance"
			)

		addLight(
			lamp,
			1.0,
			10
		)
	end

	--------------------------------------------------------
	-- CLUB CANOPY LIGHTS
	--------------------------------------------------------

	for i,x in ipairs({
		-6,-2,2,6
		}) do

		local lamp =
			part(
				lighting,
				"ClubCanopyLight_"..i,

				Vector3.new(
					0.7,
					0.22,
					0.7
				),

				canopy.CFrame
				* CFrame.new(
					x,
					-canopy.Size.Y/2 - 0.12,
					0
				),

				WARM,
				Enum.Material.Neon,
				"HarborClub"
			)

		addLight(
			lamp,
			0.75,
			8
		)
	end

	--------------------------------------------------------
	-- DOCK LIGHTS
	--
	-- Position as COMPLETE assemblies and avoid
	-- UtilityPedestals.
	--------------------------------------------------------

	local function addDockLights(
		section,
		dockName,
		role
	)

		local dock =
			section:FindFirstChild(
				dockName
			)

		assert(dock,dockName.." missing")

		local deck =
			dock:FindFirstChild(
				"MainDeck"
			)

		assert(deck,dockName.." MainDeck missing")

		local utilities = {}

		for _,obj in ipairs(
			dock:GetDescendants()
			) do

			if obj:IsA("Model")
				and obj.Name
				== "UtilityPedestal" then

				table.insert(
					utilities,
					obj
				)
			end
		end

		local function conflict(candidate)

			for _,utility in ipairs(
				utilities
				) do

				local uCF,uSize =
					utility:GetBoundingBox()

				local horizontal =
					(
						Vector3.new(
							candidate.X,
							0,
							candidate.Z
						)
						-
						Vector3.new(
							uCF.Position.X,
							0,
							uCF.Position.Z
						)
					).Magnitude

				if horizontal
					< math.max(
						uSize.X,
						uSize.Z
					)/2 + 1.25 then

					return true
				end
			end

			return false
		end

		local count =
			math.max(
				2,
				math.floor(
					deck.Size.Z / 12
				)
			)

		for i=1,count do

			local alpha =
				(i - 0.5) / count

			local z =
				-deck.Size.Z/2
				+ alpha
				* deck.Size.Z

			local side =
				(i % 2 == 0)
				and 1
				or -1

			local offsets = {
				0,
				1.5,
				-1.5,
				2.5,
				-2.5,
			}

			local baseCF

			for _,extraZ in ipairs(
				offsets
				) do

				local candidate =
					deck.CFrame
					* CFrame.new(
						side * 1.6,
						0.55,
						z + extraZ
					)

				if not conflict(
					candidate.Position
					) then

					baseCF =
						candidate

					break
				end
			end

			if baseCF then

				part(
					lighting,
					dockName..
						"_LightPost_"..i,

					Vector3.new(
						0.18,
						1.2,
						0.18
					),

					baseCF
						* CFrame.new(
							0,
							0.6,
							0
						),

					METAL,
					Enum.Material.Metal,
					role
				)

				local head =
					part(
						lighting,
						dockName..
						"_LightHead_"..i,

						Vector3.new(
							0.55,
							0.35,
							0.55
						),

						baseCF
						* CFrame.new(
							0,
							1.3,
							0
						),

						WARM,
						Enum.Material.Neon,
						role
					)

				addLight(
					head,
					0.65,
					7
				)
			end
		end
	end

	addDockLights(
		dockA,
		"DockA",
		"DockA"
	)

	addDockLights(
		dockB,
		"DockB",
		"DockB"
	)

	addDockLights(
		dockC,
		"DockC",
		"DockC"
	)

	--------------------------------------------------------
	-- FUEL WORK LIGHTS
	--------------------------------------------------------

	for i,x in ipairs({
		-2.2,0,2.2
		}) do

		local lamp =
			part(
				lighting,
				"FuelWorkLight_"..i,

				Vector3.new(
					0.75,
					0.22,
					0.75
				),

				fuelCanopy.CFrame
				* CFrame.new(
					x,
					-fuelCanopy.Size.Y/2 - 0.13,
					0
				),

				WARM,
				Enum.Material.Neon,
				"ServiceDock"
			)

		addLight(
			lamp,
			1.1,
			10
		)
	end

	--------------------------------------------------------
	-- RESCUE RINGS
	-- Correct wall-facing orientation
	--------------------------------------------------------

	local quayDeck =
		quay:FindFirstChild(
			"QuayDeck"
		)

	assert(
		quayDeck,
		"QuayDeck missing"
	)

	for i,x in ipairs({
		-20,0,20
		}) do

		local ring =
			model(
				lighting,
				"QuayRescueRing_"..i,
				"MainQuay"
			)

		local cf =
			quayDeck.CFrame
			* CFrame.new(
				x,
				1.25,
				quayDeck.Size.Z/2 + 0.20
			)
			* CFrame.Angles(
				0,
				math.rad(90),
				0
			)

		cylinder(
			ring,
			"Outer",

			Vector3.new(
				0.25,
				1.6,
				1.6
			),

			cf,
			RED,
			nil,
			"MainQuay"
		)

		cylinder(
			ring,
			"Inner",

			Vector3.new(
				0.28,
				0.82,
				0.82
			),

			cf,
			WHITE,
			nil,
			"MainQuay"
		)
	end

	--------------------------------------------------------
	-- QUAY LADDERS
	--------------------------------------------------------

	for index,x in ipairs({
		-15,15
		}) do

		local ladder =
			model(
				lighting,
				"QuayLadder_"..index,
				"MainQuay"
			)

		for sideIndex,dx in ipairs({
			-0.45,
			0.45
			}) do

			part(
				ladder,
				"Rail_"..sideIndex,

				Vector3.new(
					0.15,
					4.2,
					0.15
				),

				quayDeck.CFrame
					* CFrame.new(
						x + dx,
						-1.35,
						quayDeck.Size.Z/2 + 0.5
					),

				METAL,
				Enum.Material.Metal,
				"MainQuay"
			)
		end

		for r=0,5 do

			part(
				ladder,
				"Rung_"..r,

				Vector3.new(
					1.0,
					0.12,
					0.12
				),

				quayDeck.CFrame
					* CFrame.new(
						x,
						0.25-r*0.65,
						quayDeck.Size.Z/2 + 0.5
					),

				METAL,
				Enum.Material.Metal,
				"MainQuay"
			)
		end
	end

	--------------------------------------------------------
	-- SAFETY LIGHT
	--------------------------------------------------------

	local safetyLamp =
		part(
			lighting,
			"SafetyStationLight",

			Vector3.new(
				0.45,
				0.28,
				0.35
			),

			safety.CFrame
			* CFrame.new(
				0,
				safety.Size.Y/2 + 0.35,
				-safety.Size.Z/2 - 0.15
			),

			RED,
			Enum.Material.Neon,
			"ServiceDock"
		)

	local redLight =
		Instance.new("PointLight")

	redLight.Color = RED
	redLight.Brightness = 0.35
	redLight.Range = 4
	redLight.Shadows = false
	redLight.Parent = safetyLamp

	--======================================================
	-- 5.3 FINAL DETAILS
	--======================================================

	local details =
		model(
			root,
			"Dressing_5_3_FinalDetails"
		)

	--------------------------------------------------------
	-- PLANTERS
	-- Correctly seated on terrace
	--------------------------------------------------------

	local terrace =
		club:FindFirstChild(
			"Terrace"
		)

	assert(terrace,"Terrace missing")

	for i,x in ipairs({
		-5.4,5.4
		}) do

		local planter =
			model(
				details,
				"ClubPlanter_"..i,
				"HarborClub"
			)

		local baseCF =
			terrace.CFrame
			* CFrame.new(
				x,
				terrace.Size.Y/2 + 0.425,
				0
			)

		part(
			planter,
			"Pot",

			Vector3.new(
				1.25,
				0.85,
				1.25
			),

			baseCF,

			NAVY,
			nil,
			"HarborClub"
		)

		part(
			planter,
			"Soil",

			Vector3.new(
				1.05,
				0.12,
				1.05
			),

			baseCF
				* CFrame.new(
					0,
					0.48,
					0
				),

			SOIL,
			nil,
			"HarborClub"
		)

		for j,offset in ipairs({
			Vector3.new(0,1.05,0),
			Vector3.new(-0.30,0.85,0),
			Vector3.new(0.30,0.85,0),
			}) do

			local leaf =
				part(
					planter,
					"Shrub_"..j,

					Vector3.new(
						0.85,
						0.85,
						0.85
					),

					baseCF
					* CFrame.new(offset),

					GREEN,
					nil,
					"HarborClub"
				)

			leaf.Shape =
				Enum.PartType.Ball
		end
	end

	--------------------------------------------------------
	-- CLUB FLAG
	--------------------------------------------------------

	local mastCF =
		canopy.CFrame
		* CFrame.new(
			-7,
			4,
			-canopy.Size.Z/2 + 0.6
		)

	part(
		details,
		"ClubFlagPole",

		Vector3.new(
			0.18,
			8,
			0.18
		),

		mastCF,

		METAL,
		Enum.Material.Metal,
		"HarborClub"
	)

	part(
		details,
		"ClubFlag",

		Vector3.new(
			2.8,
			1.35,
			0.08
		),

		mastCF
			* CFrame.new(
				1.45,
				2.6,
				0
			),

		NAVY,
		nil,
		"HarborClub"
	)

	--------------------------------------------------------
	-- QUAY BOLLARDS / FENDERS
	--------------------------------------------------------

	for i,x in ipairs({
		-24,-8,8,24
		}) do

		local cf =
			quayDeck.CFrame
			* CFrame.new(
				x,
				quayDeck.Size.Y/2 + 0.55,
				quayDeck.Size.Z/2 - 0.75
			)

		cylinder(
			details,
			"QuayBollard_"..i,

			Vector3.new(
				1,
				1,
				1
			),

			cf
				* CFrame.Angles(
					0,
					0,
					math.rad(90)
				),

			METAL,
			Enum.Material.Metal,
			"MainQuay"
		)
	end

	for i,x in ipairs({
		-18,-6,6,18
		}) do

		part(
			details,
			"QuayFender_"..i,

			Vector3.new(
				1.2,
				3.8,
				0.55
			),

			quayDeck.CFrame
				* CFrame.new(
					x,
					-1.25,
					quayDeck.Size.Z/2 + 0.30
				),

			RUBBER,
			nil,
			"MainQuay"
		)
	end

	--------------------------------------------------------
	-- FUEL HOSE
	-- Correct vertical cylinder orientation
	--------------------------------------------------------

	local hose =
		model(
			details,
			"FuelHose",
			"ServiceDock"
		)

	local hoseBase =
		fuelCanopy.CFrame
		* CFrame.new(
			fuelCanopy.Size.X/2 - 0.8,
			-fuelCanopy.Size.Y/2 - 0.25,
			0
		)

	local SEGMENT =
		0.62

	for i=1,5 do

		local y =
			-(i-0.5)
			* SEGMENT

		local x =
			math.sin(
				i*0.65
			) * 0.12

		cylinder(
			hose,
			"Hose_"..i,

			Vector3.new(
				SEGMENT,
				0.16,
				0.16
			),

			hoseBase
				* CFrame.new(
					x,
					y,
					0
				)
				* CFrame.Angles(
					0,
					0,
					math.rad(90)
				),

			RUBBER,
			nil,
			"ServiceDock"
		)
	end

	part(
		hose,
		"FuelNozzle",

		Vector3.new(
			0.22,
			0.7,
			0.22
		),

		hoseBase
			* CFrame.new(
				0,
				-3.35,
				0
			),

		METAL,
		Enum.Material.Metal,
		"ServiceDock"
	)

	--------------------------------------------------------
	-- FIRE EXTINGUISHER
	--------------------------------------------------------

	local extinguisherCF =
		safety.CFrame
		* CFrame.new(
			safety.Size.X/2 + 0.45,
			-0.15,
			0
		)

	cylinder(
		details,
		"FireExtinguisher",

		Vector3.new(
			0.95,
			0.45,
			0.45
		),

		extinguisherCF
			* CFrame.Angles(
				0,
				0,
				math.rad(90)
			),

		RED,
		Enum.Material.Metal,
		"ServiceDock"
	)

	--------------------------------------------------------
	-- ENTRANCE FLAG
	--------------------------------------------------------

	local entrancePoleCF =
		header.CFrame
		* CFrame.new(
			header.Size.X/2 + 0.7,
			2.2,
			0
		)

	part(
		details,
		"EntranceFlagPole",

		Vector3.new(
			0.14,
			4.5,
			0.14
		),

		entrancePoleCF,

		METAL,
		Enum.Material.Metal,
		"Entrance"
	)

	part(
		details,
		"EntranceFlag",

		Vector3.new(
			2,
			0.95,
			0.07
		),

		entrancePoleCF
			* CFrame.new(
				1.05,
				1.4,
				0
			),

		NAVY,
		nil,
		"Entrance"
	)

	--------------------------------------------------------
	-- VALIDATE TEXT STANDARD
	--------------------------------------------------------

	for _,obj in ipairs(
		root:GetDescendants()
		) do

		if obj:IsA("TextLabel") then

			assert(
				obj.TextScaled == true,
				"TextScaled=false: "
					..obj:GetFullName()
			)
		end
	end

	print(
		"[TB MARINA] Approved Phase-5 dressing restored"
	)
end

------------------------------------------------------------
-- INSTALL
------------------------------------------------------------

function M.Install()

	local root = getRoot()

	if not root then

		warn(
			"[TB INSTALL] FAILED - Marina not found"
		)

		return false
	end

	--------------------------------------------------------
	-- INSTALL START
	--------------------------------------------------------

	root:SetAttribute(
		"InstallerStatus",
		"INSTALLING"
	)

	root:SetAttribute(
		"InstallingVersion",
		M.VERSION
	)

	root:SetAttribute(
		"InstallerError",
		nil
	)

	print("")
	print("====================================================")
	print("[TB INSTALL] START")
	print("Asset:   Marina / Yacht Harbor L3")
	print("Version:",M.VERSION)
	print("====================================================")

	local success,err =
		xpcall(
			function()

				local sections =
				getSections(root)
				installApprovedDressing(root)

				------------------------------------------------
				-- REMOVE ROOT KaijuHouse TAG IF PRESENT
				--
				-- Sections are the actual damage targets.
				------------------------------------------------

				if CollectionService:HasTag(
					root,
					"KaijuHouse"
					) then

					CollectionService:RemoveTag(
						root,
						"KaijuHouse"
					)
				end

				------------------------------------------------
				-- ROOT METADATA
				------------------------------------------------

				root:SetAttribute(
					"AssetID",
					"TB_City_MarinaYachtHarbor_L3"
				)

				root:SetAttribute(
					"AssetType",
					"MarinaYachtHarbor"
				)

				root:SetAttribute(
					"AssetLevel",
					"L3"
				)

				root:SetAttribute(
					"BuildingLevel",
					"L3"
				)

				root:SetAttribute(
					"EnergyType",
					"Heat"
				)

				root:SetAttribute(
					"TotalMaxHealth",
					19000
				)

				root:SetAttribute(
					"SectionCount",
					7
				)

				------------------------------------------------
				-- CRITICAL WORKING GROUP RESPAWN CONTRACT
				------------------------------------------------

				root:SetAttribute(
					"UsesSectionHealth",
					true
				)

				root:SetAttribute(
					"SpawnAsSingleAsset",
					true
				)

				root:SetAttribute(
					"RespawnMode",
					"GroupRoot"
				)

				root:SetAttribute(
					"AllSectionsDestroyed",
					false
				)

				root:SetAttribute(
					"GroupRespawnReady",
					false
				)

				root:SetAttribute(
					"RespawnTimerArmed",
					false
				)

				------------------------------------------------
				-- PIPELINE
				------------------------------------------------

				root:SetAttribute(
					"AssetPhase",
					7
				)

				root:SetAttribute(
					"PipelinePhase",
					"Final"
				)

				------------------------------------------------
				-- SECTIONS
				------------------------------------------------

				for index,section in ipairs(
					sections
					) do

					local cfg =
					SECTION_CONFIG[index]

					--------------------------------------------
					-- TAGS
					--------------------------------------------

					if not CollectionService:HasTag(
						section,
						"KaijuHouse"
						) then

						CollectionService:AddTag(
							section,
							"KaijuHouse"
						)
					end

					if not CollectionService:HasTag(
						section,
						"KaijuL3"
						) then

						CollectionService:AddTag(
							section,
							"KaijuL3"
						)
					end

					--------------------------------------------
					-- IDENTITY
					--------------------------------------------

					section:SetAttribute(
						"AssetID",
						"TB_City_MarinaYachtHarbor_L3_"
						..string.format(
							"%02d",
							index
						)
					)

					section:SetAttribute(
						"ParentAsset",
						"TB_City_MarinaYachtHarbor_L3"
					)

					section:SetAttribute(
						"SectionIndex",
						index
					)

					section:SetAttribute(
						"SectionRole",
						cfg.role
					)

					section:SetAttribute(
						"DestructionSection",
						cfg.role
					)

					--------------------------------------------
					-- LEVEL / ENERGY
					--------------------------------------------

					section:SetAttribute(
						"AssetLevel",
						"L3"
					)

					section:SetAttribute(
						"BuildingLevel",
						"L3"
					)

					section:SetAttribute(
						"EnergyType",
						"Heat"
					)

					--------------------------------------------
					-- HEALTH
					--------------------------------------------

					section:SetAttribute(
						"MaxHealth",
						cfg.hp
					)

					section:SetAttribute(
						"Health",
						cfg.hp
					)

					section:SetAttribute(
						"Destroyed",
						false
					)

					--------------------------------------------
					-- DAMAGE TARGET
					--------------------------------------------

					section:SetAttribute(
						"Attackable",
						true
					)

					section:SetAttribute(
						"IsDamageTarget",
						true
					)

					section:SetAttribute(
						"Destructible",
						true
					)

					--------------------------------------------
					-- GROUP RESPAWN
					--------------------------------------------

					section:SetAttribute(
						"RespawnMode",
						"ParentGroup"
					)

					section:SetAttribute(
						"SpawnSeparately",
						false
					)

					section:SetAttribute(
						"SuppressIndividualRespawn",
						true
					)

					section:SetAttribute(
						"RespawnEligible",
						false
					)

					--------------------------------------------
					-- TOUCH SUPPORT
					--------------------------------------------

					for _,obj in ipairs(
						section:GetDescendants()
						) do

						if obj:IsA("BasePart") then

							if obj:GetAttribute(
								"IsTechnicalPart"
								) then

								obj.CanCollide = false
								obj.CanTouch = false
								obj.CanQuery = false

							else

								obj.CanTouch = true
							end
						end
					end

					--------------------------------------------
					-- PRIMARY PART
					--------------------------------------------

					if not section.PrimaryPart then

						section.PrimaryPart =
						section:
						FindFirstChildWhichIsA(
							"BasePart",
							true
						)
					end

					assert(
						section.PrimaryPart,
						section.Name..
						" has no PrimaryPart"
					)
				end

				------------------------------------------------
				-- REMOVE PREVIOUS SPECIAL FX/SIGNATURE
				--
				-- User explicitly approved NO extra signatures
				-- and NO special FX for Marina.
				------------------------------------------------

				for _,name in ipairs({
					"MarinaSignatureController",
					"MarinaFXController",
					"MarinaSpecialEffects",
					}) do

					local old =
					root:FindFirstChild(
						name
					)

					if old then
						old:Destroy()
					end
				end

				------------------------------------------------
				-- KEEP EXISTING SIMPLE DESTRUCTION CONTROLLER
				--
				-- We DO NOT rebuild geometry here.
				-- Existing approved behavior remains.
				------------------------------------------------

				root:SetAttribute(
					"UsesSpecialDestructionSignature",
					false
				)

				root:SetAttribute(
					"UsesSpecialDestructionFX",
					false
				)

				------------------------------------------------
				-- FINAL METADATA
				------------------------------------------------

				root:SetAttribute(
					"GameplayVersion",
					"Final_v01"
				)

				root:SetAttribute(
					"HouseHandlerMinimumVersion",
					"v40"
				)

				root:SetAttribute(
					"InstalledVersion",
					M.VERSION
				)

				root:SetAttribute(
					"InstalledAt",
					os.time()
				)

				root:SetAttribute(
					"InstallingVersion",
					nil
				)

				root:SetAttribute(
					"InstallerStatus",
					"SUCCESS"
				)

			end,

			debug.traceback
		)

	--------------------------------------------------------
	-- FAILURE
	--------------------------------------------------------

	if not success then

		root:SetAttribute(
			"InstallerStatus",
			"FAILED"
		)

		root:SetAttribute(
			"InstallerError",
			tostring(err)
		)

		warn("")
		warn("====================================================")
		warn("[TB INSTALL] FAILED")
		warn("Asset: Marina / Yacht Harbor L3")
		warn("Version:",M.VERSION)
		warn(err)
		warn("====================================================")

		return false,err
	end

	root:SetAttribute(
		"InstallerError",
		nil
	)

	print("")
	print("====================================================")
	print("[TB INSTALL] SUCCESS")
	print("Asset:       Marina / Yacht Harbor L3")
	print("Version:    ",M.VERSION)
	print("Level:       L3")
	print("Energy:      Heat")
	print("Sections:    7")
	print("Total HP:    19000")
	print("Respawn:     GroupRoot / ParentGroup")
	print("Special FX:  NONE")
	print("Signatures:  NONE")
	print("====================================================")

	return true
end

return M