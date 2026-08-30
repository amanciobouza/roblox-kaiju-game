--============================================================
-- TRENCHBORN INSTALLER MODULE
-- Pier / Boardwalk L2
-- Phase 6 - Section Destruction
--
-- VERSION: Pier_L2_Phase6_v03
--
-- Install location:
-- ServerScriptService
--   > TrenchbornInstallers
--     > City
--       > PierBoardwalk_L2
--============================================================

local Installer = {}

Installer.VERSION = "Pier_L2_Phase6_v03"

------------------------------------------------------------
-- SERVICES
------------------------------------------------------------

local Workspace = game:GetService("Workspace")

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local ROOT_NAME =
	"TB_City_PierBoardwalk_L2_GoldenMaster_v01"

------------------------------------------------------------
-- INSTALL
------------------------------------------------------------

function Installer.Install()

	--------------------------------------------------------
	-- FIND ASSET
	--------------------------------------------------------

	local root =
		Workspace:FindFirstChild(
			ROOT_NAME,
			true
		)

	assert(
		root,
		ROOT_NAME .. " not found"
	)

	--------------------------------------------------------
	-- START STATUS
	--------------------------------------------------------

	root:SetAttribute(
		"InstallerStatus",
		"INSTALLING"
	)

	root:SetAttribute(
		"InstallingVersion",
		Installer.VERSION
	)

	print("")
	print("====================================================")
	print("[TB INSTALL] START")
	print("Asset:   Pier / Boardwalk L2")
	print("Version:", Installer.VERSION)
	print("====================================================")

	--------------------------------------------------------
	-- SAFE INSTALL WRAPPER
	--------------------------------------------------------

	local success, err =
		xpcall(
			function()

				------------------------------------------------
				-- VALIDATE SECTIONS
				------------------------------------------------

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
						section,
						name .. " missing"
					)

					sections[i] =
					section
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
				-- INSTALL NEW CONTROLLER
				------------------------------------------------

				local controller =
				Instance.new("Script")

				controller.Name =
				"PierDestructionController"

				controller:SetAttribute(
					"InstallerVersion",
					Installer.VERSION
				)

				controller.Source = [=[

--============================================================
-- TRENCHBORN
-- PIER / BOARDWALK L2
-- SECTION DESTRUCTION CONTROLLER
--
-- Separately destructible:
--   Section 01-06
--
-- Shared respawn remains owned by HouseHandler.
--============================================================

local TweenService =
	game:GetService("TweenService")

local root =
	script.Parent

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local CONFIG = {

	[1] = {
		tiltX = 7,
		tiltZ = 0,
		sink = 0.8,
		duration = 0.45,
	},

	[2] = {
		tiltX = -4,
		tiltZ = 2,
		sink = 1.7,
		duration = 0.55,
	},

	[3] = {
		tiltX = 5,
		tiltZ = -2,
		sink = 2.0,
		duration = 0.60,
	},

	[4] = {
		tiltX = -4,
		tiltZ = 4,
		sink = 1.4,
		duration = 0.65,
	},

	[5] = {
		tiltX = 5,
		tiltZ = 2,
		sink = 1.9,
		duration = 0.58,
	},

	[6] = {
		tiltX = -4,
		tiltZ = 3,
		sink = 2.3,
		duration = 0.70,
	},
}

------------------------------------------------------------
-- SECTIONS
------------------------------------------------------------

local sections = {}

for i = 1,6 do

	sections[i] =
		root:WaitForChild(
			string.format(
				"Section_%02d",
				i
			)
		)
end

------------------------------------------------------------
-- ORIGINAL GEOMETRY
--
-- Exact WORLD CFrames are stored.
-- This means the Pier may be moved/rotated freely before Play.
------------------------------------------------------------

local originals = {}

for index,section in ipairs(sections) do

	originals[index] = {}

	for _,obj in ipairs(
		section:GetDescendants()
	) do

		if obj:IsA("BasePart") then

			originals[index][obj] = {

				CFrame =
					obj.CFrame,

				Transparency =
					obj.Transparency,

				Material =
					obj.Material,

				Color =
					obj.Color,
			}
		end
	end
end

------------------------------------------------------------
-- LIGHT STATE
------------------------------------------------------------

local function setLights(
	section,
	enabled
)

	for _,obj in ipairs(
		section:GetDescendants()
	) do

		if obj:IsA("Light") then

			obj.Enabled = enabled

		elseif obj:IsA("BasePart")
			and (
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
			) then

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

------------------------------------------------------------
-- COHERENT SECTION TRANSFORM
------------------------------------------------------------

local function transformSection(
	index,
	targetPivot,
	duration
)

	local section =
		sections[index]

	local currentPivot =
		section:GetPivot()

	local offsets = {}

	for part,_ in pairs(
		originals[index]
	) do

		if part.Parent then

			offsets[part] =
				currentPivot:ToObjectSpace(
					part.CFrame
				)
		end
	end

	for part,offset in pairs(offsets) do

		if part.Parent then

			TweenService:Create(
				part,

				TweenInfo.new(
					duration,
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
end

------------------------------------------------------------
-- STANDARD SECTION COLLAPSE
------------------------------------------------------------

local function collapseSection(index)

	local section =
		sections[index]

	local cfg =
		CONFIG[index]

	local pivot =
		section:GetPivot()

	local target =
		pivot

		* CFrame.new(
			0,
			-cfg.sink,
			0
		)

		* CFrame.Angles(
			math.rad(
				cfg.tiltX
			),

			0,

			math.rad(
				cfg.tiltZ
			)
		)

	transformSection(
		index,
		target,
		cfg.duration
	)
end

------------------------------------------------------------
-- ENTRANCE GATE
------------------------------------------------------------

local function collapseEntrance()

	collapseSection(1)

	local gate =
		sections[1]:FindFirstChild(
			"EntranceGate"
		)

	if not gate then
		return
	end

	task.delay(
		0.08,
		function()

			if not gate.Parent then
				return
			end

			local pivot =
				gate:GetPivot()

			local target =
				pivot
				* CFrame.new(
					0,
					-0.35,
					0.7
				)
				* CFrame.Angles(
					math.rad(11),
					0,
					math.rad(2)
				)

			local offsets = {}

			for _,part in ipairs(
				gate:GetDescendants()
			) do

				if part:IsA("BasePart") then

					offsets[part] =
						pivot:ToObjectSpace(
							part.CFrame
						)
				end
			end

			for part,offset in pairs(offsets) do

				if part.Parent then

					TweenService:Create(
						part,

						TweenInfo.new(
							0.38,
							Enum.EasingStyle.Quad,
							Enum.EasingDirection.In
						),

						{
							CFrame =
								target
								* offset
						}
					):Play()
				end
			end
		end
	)
end

------------------------------------------------------------
-- PAVILION COLLAPSE
------------------------------------------------------------

local function collapsePavilion()

	collapseSection(4)

	local pavilion =
		sections[4]:FindFirstChild(
			"Pavilion"
		)

	if not pavilion then
		return
	end

	task.delay(
		0.10,
		function()

			if not pavilion.Parent then
				return
			end

			local pivot =
				pavilion:GetPivot()

			local target =
				pivot
				* CFrame.new(
					0.8,
					-0.8,
					0
				)
				* CFrame.Angles(
					0,
					0,
					math.rad(-14)
				)

			local offsets = {}

			for _,part in ipairs(
				pavilion:GetDescendants()
			) do

				if part:IsA("BasePart") then

					offsets[part] =
						pivot:ToObjectSpace(
							part.CFrame
						)
				end
			end

			for part,offset in pairs(offsets) do

				if part.Parent then

					TweenService:Create(
						part,

						TweenInfo.new(
							0.45,
							Enum.EasingStyle.Quad,
							Enum.EasingDirection.In
						),

						{
							CFrame =
								target
								* offset
						}
					):Play()
				end
			end
		end
	)
end

------------------------------------------------------------
-- DESTROY STATE
------------------------------------------------------------

local destroyed = {}

local function destroySection(index)

	if destroyed[index] then
		return
	end

	destroyed[index] = true

	local section =
		sections[index]

	--------------------------------------------------------
	-- LIGHTS OUT IMMEDIATELY
	--------------------------------------------------------

	setLights(
		section,
		false
	)

	--------------------------------------------------------
	-- COLLAPSE PROFILE
	--------------------------------------------------------

	if index == 1 then

		collapseEntrance()

	elseif index == 4 then

		collapsePavilion()

	else

		collapseSection(index)
	end

	print(
		"[Pier]",
		section.Name,
		"DESTROYED"
	)
end

------------------------------------------------------------
-- RESTORE SECTION
------------------------------------------------------------

local function restoreSection(index)

	local section =
		sections[index]

	for part,data in pairs(
		originals[index]
	) do

		if part.Parent then

			part.CFrame =
				data.CFrame

			part.Transparency =
				data.Transparency

			part.Material =
				data.Material

			part.Color =
				data.Color
		end
	end

	setLights(
		section,
		true
	)

	destroyed[index] =
		nil

	print(
		"[Pier]",
		section.Name,
		"RESTORED"
	)
end

------------------------------------------------------------
-- WATCH HOUSEHANDLER DESTROYED ATTRIBUTE
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

			destroySection(index)

		else

			restoreSection(index)
		end
	end)
end

------------------------------------------------------------
-- INITIAL STATE
------------------------------------------------------------

for index,section in ipairs(
	sections
) do

	if section:GetAttribute(
		"Destroyed"
	) == true then

		destroySection(index)

	else

		setLights(
			section,
			true
		)
	end
end

print(
	"[Trenchborn] Pier Destruction Controller v03 ACTIVE"
)

]=]

				controller.Parent =
				root

				------------------------------------------------
				-- STRONGER APPROVED LIGHTING
				------------------------------------------------

				local lightCount = 0

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

						lightCount += 1
					end
				end

				------------------------------------------------
				-- MAKE LAMP GLASS VISIBLY LIT
				------------------------------------------------

				for _,obj in ipairs(
					root:GetDescendants()
					) do

					if obj:IsA("BasePart")
						and (
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
						) then

						obj.Material =
						Enum.Material.Neon

						obj.Color =
						Color3.fromRGB(
							255,
							226,
							163
						)

						obj.Transparency =
						math.min(
							obj.Transparency,
							0.12
						)
					end
				end

				------------------------------------------------
				-- VALIDATION
				------------------------------------------------

				assert(
					root:FindFirstChild(
						"PierDestructionController"
					),
					"PierDestructionController missing"
				)

				for i = 1,6 do

					local section =
					sections[i]

					assert(
						section:GetAttribute(
							"RespawnMode"
						) == "ParentGroup",
						section.Name
						.. " must use ParentGroup"
					)

					assert(
						section:GetAttribute(
							"EnergyType"
						) == "Heat",
						section.Name
						.. " must use Heat"
					)
				end

				------------------------------------------------
				-- FINAL METADATA
				------------------------------------------------

				root:SetAttribute(
					"DestructionVersion",
					"v03"
				)

				root:SetAttribute(
					"LightingVersion",
					"v02_Stronger"
				)

				root:SetAttribute(
					"InstalledVersion",
					Installer.VERSION
				)

				root:SetAttribute(
					"InstallingVersion",
					nil
				)

				root:SetAttribute(
					"InstalledAt",
					os.time()
				)

				root:SetAttribute(
					"InstallerStatus",
					"SUCCESS"
				)

				print("")
				print("====================================================")
				print("[TB INSTALL] SUCCESS")
				print("Asset:   Pier / Boardwalk L2")
				print("Version:", Installer.VERSION)
				print("Lights: ", lightCount)
				print("")
				print("6 section destruction controller installed.")
				print("Shared ParentGroup respawn preserved.")
				print("====================================================")
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
		warn("Asset:   Pier / Boardwalk L2")
		warn("Version:", Installer.VERSION)
		warn("ERROR:")
		warn(err)
		warn("====================================================")

		return false, err
	end

	root:SetAttribute(
		"InstallerError",
		nil
	)

	return true
end

------------------------------------------------------------
-- STATUS
------------------------------------------------------------

function Installer.Status()

	local root =
		Workspace:FindFirstChild(
			ROOT_NAME,
			true
		)

	if not root then

		warn(
			"[TB STATUS] Pier not found"
		)

		return
	end

	print("")
	print("====================================================")
	print("[TB STATUS] Pier / Boardwalk L2")
	print("")
	print(
		"Status:",
		root:GetAttribute(
			"InstallerStatus"
		)
	)

	print(
		"Installed:",
		root:GetAttribute(
			"InstalledVersion"
		)
	)

	print(
		"Destruction:",
		root:GetAttribute(
			"DestructionVersion"
		)
	)

	print(
		"Lighting:",
		root:GetAttribute(
			"LightingVersion"
		)
	)

	print("====================================================")
end

return Installer