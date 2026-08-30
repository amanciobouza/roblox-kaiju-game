--============================================================
-- TRENCHBORN FINAL INSTALLER
-- CITY / PIER BOARDWALK L2
--
-- VERSION: Pier_L2_Final_v01
--
-- Existing geometry/dressing is preserved.
-- Installs/finalizes:
--   - 6 destructible sections
--   - Heat
--   - section HP
--   - ParentGroup shared respawn
--   - lighting
--   - section destruction controller
--   - validation/status
--
-- Requires HouseHandler v40+
--============================================================

local M = {}

M.VERSION = "Pier_L2_Final_v01"

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ROOT_NAME =
	"TB_City_PierBoardwalk_L2_GoldenMaster_v01"

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local SECTION_CONFIG = {

	[1] = {
		role = "Entrance",
		hp = 1000,
		collapse = "Gate",
	},

	[2] = {
		role = "BoardwalkA",
		hp = 800,
		collapse = "DeckSinkLeft",
	},

	[3] = {
		role = "BoardwalkB",
		hp = 800,
		collapse = "DeckSinkRight",
	},

	[4] = {
		role = "Pavilion",
		hp = 1400,
		collapse = "PavilionCollapse",
	},

	[5] = {
		role = "BoardwalkC",
		hp = 800,
		collapse = "DeckSinkLeft",
	},

	[6] = {
		role = "PierHead",
		hp = 1200,
		collapse = "PierHeadSink",
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

	for i = 1,6 do

		local name =
			string.format(
				"Section_%02d",
				i
			)

		local section =
			root:FindFirstChild(name)

		assert(
			section
				and section:IsA("Model"),
			name .. " missing"
		)

		sections[i] = section
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
	print("[TB STATUS] PIER / BOARDWALK L2")
	print("Module:       ", M.VERSION)

	if not root then

		print("Asset:         NOT FOUND")
		print("====================================================")
		return
	end

	print(
		"Status:        ",
		root:GetAttribute("InstallerStatus")
	)

	print(
		"Installed:     ",
		root:GetAttribute("InstalledVersion")
	)

	print(
		"Energy:        ",
		root:GetAttribute("EnergyType")
	)

	print(
		"Sections:      ",
		root:GetAttribute("SectionCount")
	)

	print(
		"RespawnMode:   ",
		root:GetAttribute("RespawnMode")
	)

	print(
		"GroupRoot:     ",
		root:GetAttribute("SpawnAsSingleAsset")
	)

	print(
		"SectionHealth: ",
		root:GetAttribute("UsesSectionHealth")
	)

	print(
		"Phase:         ",
		root:GetAttribute("AssetPhase")
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
	print("[TB VALIDATE] PIER / BOARDWALK L2")

	if not root then

		warn("✗ Asset not found")
		print("RESULT: FAIL")
		print("====================================================")

		return false
	end

	local ok = true

	local function check(condition,text)

		if condition then
			print("✓",text)
		else
			warn("✗",text)
			ok = false
		end
	end

	local sections = {}

	for i = 1,6 do

		sections[i] =
			root:FindFirstChild(
				string.format(
					"Section_%02d",
					i
				)
			)
	end

	check(
		#sections == 6,
		"6 section slots"
	)

	check(
		root:GetAttribute("EnergyType")
			== "Heat",
		"Root EnergyType = Heat"
	)

	check(
		root:GetAttribute("UsesSectionHealth")
			== true,
		"UsesSectionHealth = true"
	)

	check(
		root:GetAttribute("SpawnAsSingleAsset")
			== true,
		"SpawnAsSingleAsset = true"
	)

	check(
		root:GetAttribute("RespawnMode")
			== "GroupRoot",
		"Root RespawnMode = GroupRoot"
	)

	check(
		root:GetAttribute("SectionCount")
			== 6,
		"SectionCount = 6"
	)

	local totalHP = 0

	for i,section in ipairs(sections) do

		if section then

			local cfg =
				SECTION_CONFIG[i]

			check(
				CollectionService:HasTag(
					section,
					"KaijuHouse"
				),
				section.Name ..
					" KaijuHouse"
			)

			check(
				section:GetAttribute(
					"RespawnMode"
				) == "ParentGroup",
				section.Name ..
					" ParentGroup"
			)

			check(
				section:GetAttribute(
					"SpawnSeparately"
				) == false,
				section.Name ..
					" SpawnSeparately=false"
			)

			check(
				section:GetAttribute(
					"SuppressIndividualRespawn"
				) == true,
				section.Name ..
					" suppresses individual respawn"
			)

			check(
				section:GetAttribute(
					"EnergyType"
				) == "Heat",
				section.Name ..
					" Heat"
			)

			check(
				section:GetAttribute(
					"MaxHealth"
				) == cfg.hp,
				section.Name ..
					" HP=" .. cfg.hp
			)

			totalHP +=
				section:GetAttribute(
					"MaxHealth"
				) or 0
		else

			ok = false
		end
	end

	check(
		totalHP == 6000,
		"Total section HP = 6000"
	)

	check(
		root:FindFirstChild(
			"PierDestructionController"
		) ~= nil,
		"PierDestructionController"
	)

	check(
		root:GetAttribute(
			"InstalledVersion"
		) == M.VERSION,
		"Installed version matches"
	)

	local lightCount = 0

	for _,obj in ipairs(
		root:GetDescendants()
		) do

		if obj:IsA("PointLight") then
			lightCount += 1
		end
	end

	check(
		lightCount >= 14,
		"Pier lights >= 14 (found "
			.. lightCount .. ")"
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
-- INSTALL
------------------------------------------------------------

function M.Install()

	local root = getRoot()

	if not root then

		warn(
			"[TB INSTALL] FAILED - Pier asset not found"
		)

		return false
	end

	--------------------------------------------------------
	-- INSTALLING
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
	print("Asset:   Pier / Boardwalk L2")
	print("Version:",M.VERSION)
	print("====================================================")

	local success,err =
		xpcall(
			function()

				local sections =
				getSections(root)

				------------------------------------------------
				-- ROOT = GROUP ROOT
				--
				-- CRITICAL CONTRACT FOR HOUSEHANDLER
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

				root:SetAttribute(
					"AssetID",
					"TB_City_PierBoardwalk_L2"
				)

				root:SetAttribute(
					"AssetType",
					"PierBoardwalk"
				)

				root:SetAttribute(
					"AssetLevel",
					"L2"
				)

				root:SetAttribute(
					"EnergyType",
					"Heat"
				)

				root:SetAttribute(
					"SectionCount",
					6
				)

				------------------------------------------------
				-- FINAL WORKING GROUP-RESPAWN CONTRACT
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

				root:SetAttribute(
					"AssetPhase",
					7
				)

				root:SetAttribute(
					"PipelinePhase",
					"Final"
				)

				------------------------------------------------
				-- CONFIGURE 6 DAMAGE TARGETS
				------------------------------------------------

				for i,section in ipairs(
					sections
					) do

					local cfg =
					SECTION_CONFIG[i]

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
						"KaijuL2"
						) then

						CollectionService:AddTag(
							section,
							"KaijuL2"
						)
					end

					--------------------------------------------
					-- IDENTITY
					--------------------------------------------

					section:SetAttribute(
						"AssetID",
						"TB_City_PierBoardwalk_L2_"
						.. string.format(
							"%02d",
							i
						)
					)

					section:SetAttribute(
						"ParentAsset",
						"TB_City_PierBoardwalk_L2"
					)

					section:SetAttribute(
						"SectionIndex",
						i
					)

					section:SetAttribute(
						"SectionRole",
						cfg.role
					)

					section:SetAttribute(
						"DestructionSection",
						true
					)

					section:SetAttribute(
						"CollapseProfile",
						cfg.collapse
					)

					--------------------------------------------
					-- GAMEPLAY
					--------------------------------------------

					section:SetAttribute(
						"EnergyType",
						"Heat"
					)

					section:SetAttribute(
						"AssetLevel",
						"L2"
					)

					section:SetAttribute(
						"BuildingLevel",
						"L2"
					)

					section:SetAttribute(
						"Attackable",
						true
					)

					section:SetAttribute(
						"IsDamageTarget",
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

					--------------------------------------------
					-- HEALTH
					--------------------------------------------

					section:SetAttribute(
						"MaxHealth",
						cfg.hp
					)

					-- In Edit Mode installation we normalize
					-- the asset to fully intact.
					section:SetAttribute(
						"Health",
						cfg.hp
					)

					section:SetAttribute(
						"Destroyed",
						false
					)

					section:SetAttribute(
						"RespawnEligible",
						false
					)

					section:SetAttribute(
						"EnergyCollectionActive",
						false
					)

					--------------------------------------------
					-- HOUSEHANDLER v40 TOUCH CONTRACT
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

					local deck =
					section:FindFirstChild(
						"Deck"
					)

					local collision =
					deck
					and deck:FindFirstChild(
						"DeckCollision"
					)

					if collision
						and collision:IsA(
							"BasePart"
						) then

						section.PrimaryPart =
						collision

					elseif not section.PrimaryPart then

						section.PrimaryPart =
						section:
						FindFirstChildWhichIsA(
							"BasePart",
							true
						)
					end

					assert(
						section.PrimaryPart,
						section.Name
						.. " has no PrimaryPart"
					)
				end

				------------------------------------------------
				-- REMOVE OLD CONTROLLER
				------------------------------------------------

				local old =
				root:FindFirstChild(
					"PierDestructionController"
				)

				if old then
					old:Destroy()
				end

				------------------------------------------------
				-- FINAL SECTION DESTRUCTION CONTROLLER
				------------------------------------------------

				local controller =
				Instance.new("Script")

				controller.Name =
				"PierDestructionController"

				controller:SetAttribute(
					"InstallerVersion",
					M.VERSION
				)

				controller.Source = [=[

local TweenService =
	game:GetService("TweenService")

local root = script.Parent

local CONFIG = {

	[1] = {
		sink=0.8,
		tiltX=7,
		tiltZ=0,
		time=0.45
	},

	[2] = {
		sink=1.7,
		tiltX=-4,
		tiltZ=2,
		time=0.55
	},

	[3] = {
		sink=2.0,
		tiltX=5,
		tiltZ=-2,
		time=0.60
	},

	[4] = {
		sink=1.4,
		tiltX=-4,
		tiltZ=4,
		time=0.65
	},

	[5] = {
		sink=1.9,
		tiltX=5,
		tiltZ=2,
		time=0.58
	},

	[6] = {
		sink=2.3,
		tiltX=-4,
		tiltZ=3,
		time=0.70
	},
}

local sections = {}
local originals = {}
local collapsed = {}

------------------------------------------------------------
-- STORE APPROVED STATE
------------------------------------------------------------

for i=1,6 do

	local section =
		root:WaitForChild(
			string.format(
				"Section_%02d",
				i
			)
		)

	sections[i] = section
	originals[i] = {}

	for _,obj in ipairs(
		section:GetDescendants()
	) do

		if obj:IsA("BasePart") then

			originals[i][obj] = {

				CFrame =
					obj.CFrame,

				Material =
					obj.Material,

				Color =
					obj.Color,

				Transparency =
					obj.Transparency,
			}
		end
	end
end

------------------------------------------------------------
-- LIGHTS
------------------------------------------------------------

local function setLights(
	section,
	enabled
)

	for _,obj in ipairs(
		section:GetDescendants()
	) do

		if obj:IsA("Light") then

			obj.Enabled =
				enabled
		end

		if obj:IsA("BasePart") then

			local isLamp =
				obj.Name == "LampHead"

				or string.find(
					obj.Name,
					"GateLampHousing",
					1,
					true
				)

				or string.find(
					obj.Name,
					"PavilionLamp_",
					1,
					true
				)

			if isLamp then

				if enabled then

					obj.Material =
						Enum.Material.Neon

					obj.Color =
						Color3.fromRGB(
							255,
							226,
							163
						)

				else

					obj.Material =
						Enum.Material.Glass

					obj.Color =
						Color3.fromRGB(
							105,
							102,
							92
						)
				end
			end
		end
	end
end

------------------------------------------------------------
-- COLLAPSE
------------------------------------------------------------

local function collapse(index)

	if collapsed[index] then
		return
	end

	collapsed[index] = true

	local section =
		sections[index]

	local cfg =
		CONFIG[index]

	setLights(
		section,
		false
	)

	local pivot =
		section:GetPivot()

	local targetPivot =
		CFrame.new(
			0,
			-cfg.sink,
			0
		)
		* pivot
		* CFrame.Angles(
			math.rad(
				cfg.tiltX
			),
			0,
			math.rad(
				cfg.tiltZ
			)
		)

	local relative = {}

	for part,_ in pairs(
		originals[index]
	) do

		if part.Parent then

			relative[part] =
				pivot:ToObjectSpace(
					part.CFrame
				)
		end
	end

	for part,offset in pairs(relative) do

		if part.Parent then

			TweenService:Create(
				part,

				TweenInfo.new(
					cfg.time,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),

				{
					CFrame =
						targetPivot
						* offset
				}
			):Play()
		end
	end

	print(
		"[TB PIER]",
		section.Name,
		"COLLAPSED"
	)
end

------------------------------------------------------------
-- RESTORE
------------------------------------------------------------

local function restore(index)

	for part,data in pairs(
		originals[index]
	) do

		if part.Parent then

			part.CFrame =
				data.CFrame

			part.Material =
				data.Material

			part.Color =
				data.Color

			part.Transparency =
				data.Transparency
		end
	end

	setLights(
		sections[index],
		true
	)

	collapsed[index] =
		nil

	print(
		"[TB PIER]",
		sections[index].Name,
		"RESTORED"
	)
end

------------------------------------------------------------
-- WATCH HOUSEHANDLER
------------------------------------------------------------

for index,section in ipairs(
	sections
) do

	section:GetAttributeChangedSignal(
		"Destroyed"
	):Connect(function()

		if section:GetAttribute(
			"Destroyed"
		) == true then

			collapse(index)

		else

			restore(index)
		end
	end)
end

------------------------------------------------------------
-- INITIAL
------------------------------------------------------------

for i,section in ipairs(
	sections
) do

	if section:GetAttribute(
		"Destroyed"
	) == true then

		collapse(i)

	else

		setLights(
			section,
			true
		)
	end
end

print(
	"[TB PIER] FINAL Destruction Controller ACTIVE"
)

]=]

				controller.Parent =
				root

				------------------------------------------------
				-- FINAL LIGHTING
				------------------------------------------------

				for _,obj in ipairs(
					root:GetDescendants()
					) do

					if obj:IsA("PointLight") then

						local parent =
						obj.Parent

						if parent
							and string.find(
								parent.Name,
								"GateLampHousing",
								1,
								true
							) then

							obj.Brightness = 1.1
							obj.Range = 12

						elseif parent
							and string.find(
								parent.Name,
								"PavilionLamp_",
								1,
								true
							) then

							obj.Brightness = 0.65
							obj.Range = 7

						else

							obj.Brightness = 0.9
							obj.Range = 11
						end

						obj.Enabled = true
					end
				end

				------------------------------------------------
				-- FINAL METADATA
				------------------------------------------------

				root:SetAttribute(
					"GameplayVersion",
					"Final_v01"
				)

				root:SetAttribute(
					"DestructionVersion",
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
		warn("Asset: Pier / Boardwalk L2")
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
	print("Asset:       Pier / Boardwalk L2")
	print("Version:    ",M.VERSION)
	print("Level:       L2")
	print("Energy:      Heat")
	print("Sections:    6")
	print("Total HP:    6000")
	print("Respawn:     GroupRoot / ParentGroup")
	print("====================================================")

	return true
end

return M