local RunService = game:GetService("RunService")

local Portals = workspace:WaitForChild("Portals")

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local CYCLE = 5.6

--------------------------------------------------
-- AUDIO
--------------------------------------------------

local RUMBLE_SOUND_ID = "rbxassetid://9114492881"
local WHOOSH_SOUND_ID = "rbxassetid://9120703818"

local RUMBLE_VOLUME = 0.65
local WHOOSH_VOLUME = 1.0

local SOUND_MIN_DISTANCE = 150
local SOUND_MAX_DISTANCE = 220

local WHOOSH_START_SEC = 0.15
local BUILD_PEAK_SEC = 0.65
local BREAK_PEAK_SEC = 1.15

local AUDIO_ZONE_TIMEOUT = 10

--------------------------------------------------
-- STATE
--------------------------------------------------

local waves = {}
local portalAudio = {}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function findBone(model, name)
	local b = model:FindFirstChild(name, true)

	if b and b:IsA("Bone") then
		return b
	end

	return nil
end

local function pulse(t, center, width)
	local d = t - center
	return math.exp(-(d * d) / width)
end

local function rotZ(degrees)
	return CFrame.Angles(
		0,
		0,
		math.rad(degrees)
	)
end

--------------------------------------------------
-- WAIT FOR MANUAL AUDIO ZONE
--------------------------------------------------

local function waitForAudioZone(portal)

	local startTime = os.clock()

	while os.clock() - startTime < AUDIO_ZONE_TIMEOUT do

		local zone =
			portal:FindFirstChild(
				"KanagawaAudioZone"
			)

		if zone then

			if zone:IsA("BasePart") then
				return zone
			else
				warn(
					"[Kanagawa] KanagawaAudioZone exists but is not a BasePart:",
					zone:GetFullName()
				)

				return nil
			end

		end

		task.wait(0.1)
	end

	warn(
		"[Kanagawa] KanagawaAudioZone timeout in",
		portal:GetFullName()
	)

	return nil
end

--------------------------------------------------
-- PARTICLES
--------------------------------------------------

local function createEmitter(
	parent,
	name,
	texture,
	rate,
	speedMin,
	speedMax,
	lifeMin,
	lifeMax,
	spread
)

	if not parent then
		return nil
	end

	local old =
		parent:FindFirstChild(name)

	if old
		and old:IsA("ParticleEmitter")
	then
		old:Destroy()
	end

	local emitter =
		Instance.new("ParticleEmitter")

	emitter.Name =
		name

	emitter.Texture =
		texture

	emitter.Rate =
		rate

	emitter.Speed =
		NumberRange.new(
			speedMin,
			speedMax
		)

	emitter.Lifetime =
		NumberRange.new(
			lifeMin,
			lifeMax
		)

	emitter.SpreadAngle =
		Vector2.new(
			spread,
			spread
		)

	emitter.Drag =
		2

	emitter.LightInfluence =
		0.1

	emitter.Enabled =
		true

	emitter.Parent =
		parent

	return emitter
end

--------------------------------------------------
-- PORTAL AUDIO
--------------------------------------------------

local function setupPortalAudio(portal)

	if portalAudio[portal] then
		return portalAudio[portal]
	end

	--------------------------------------------------
	-- WAIT FOR YOUR MANUAL ZONE
	--------------------------------------------------

	local zone =
		waitForAudioZone(portal)

	if not zone then
		return nil
	end

	--------------------------------------------------
	-- REMOVE OLD LOCAL SOUNDS
	--------------------------------------------------

	local oldRumble =
		zone:FindFirstChild(
			"KanagawaRumble"
		)

	if oldRumble
		and oldRumble:IsA("Sound")
	then
		oldRumble:Destroy()
	end

	local oldWhoosh =
		zone:FindFirstChild(
			"KanagawaWhoosh"
		)

	if oldWhoosh
		and oldWhoosh:IsA("Sound")
	then
		oldWhoosh:Destroy()
	end

	--------------------------------------------------
	-- RUMBLE
	--------------------------------------------------

	local rumble =
		Instance.new("Sound")

	rumble.Name =
		"KanagawaRumble"

	rumble.SoundId =
		RUMBLE_SOUND_ID

	rumble.Volume =
		RUMBLE_VOLUME

	rumble.Looped =
		true

	rumble.RollOffMode =
		Enum.RollOffMode.Linear

	rumble.RollOffMinDistance =
		SOUND_MIN_DISTANCE

	rumble.RollOffMaxDistance =
		SOUND_MAX_DISTANCE

	rumble.Parent =
		zone

	--------------------------------------------------
	-- WHOOSH
	--------------------------------------------------

	local whoosh =
		Instance.new("Sound")

	whoosh.Name =
		"KanagawaWhoosh"

	whoosh.SoundId =
		WHOOSH_SOUND_ID

	whoosh.Volume =
		WHOOSH_VOLUME

	whoosh.Looped =
		false

	whoosh.RollOffMode =
		Enum.RollOffMode.Linear

	whoosh.RollOffMinDistance =
		SOUND_MIN_DISTANCE

	whoosh.RollOffMaxDistance =
		SOUND_MAX_DISTANCE

	whoosh.Parent =
		zone

	--------------------------------------------------
	-- LOAD + START RUMBLE
	--------------------------------------------------

	task.spawn(function()

		if not rumble.IsLoaded then
			rumble.Loaded:Wait()
		end

		if not rumble.IsPlaying then
			rumble:Play()
		end

	end)

	--------------------------------------------------
	-- PRELOAD WHOOSH
	--------------------------------------------------

	task.spawn(function()

		if not whoosh.IsLoaded then
			whoosh.Loaded:Wait()
		end

	end)

	local data = {
		portal = portal,
		zone = zone,
		rumble = rumble,
		whoosh = whoosh,
		lastWhooshCycle = -1,
	}

	portalAudio[portal] = data

	print(
		"[Kanagawa] Audio ready:",
		zone:GetFullName(),
		"Size:",
		zone.Size,
		"Min:",
		SOUND_MIN_DISTANCE,
		"Max:",
		SOUND_MAX_DISTANCE
	)

	return data
end

--------------------------------------------------
-- REGISTER WAVE
--------------------------------------------------

local function registerWave(model)

	if waves[model] then
		return
	end

	if model.Name ~= "Wave_Left"
		and model.Name ~= "Wave_Center"
		and model.Name ~= "Wave_Right"
	then
		return
	end

	--------------------------------------------------
	-- WAIT FOR RIG
	--------------------------------------------------

	local timeout =
		os.clock() + 10

	local bodyLower

	repeat

		bodyLower =
			findBone(
				model,
				"BodyLower"
			)

		if bodyLower then
			break
		end

		task.wait(0.1)

	until os.clock() > timeout

	if not bodyLower then

		warn(
			"[Kanagawa] BodyLower missing in",
			model:GetFullName()
		)

		return
	end

	--------------------------------------------------
	-- PORTAL AUDIO
	--------------------------------------------------

	local portal =
		model.Parent

	if portal then
		task.spawn(
			function()
				setupPortalAudio(portal)
			end
		)
	end

	--------------------------------------------------
	-- WAVE DATA
	--------------------------------------------------

	local wave = {

		model = model,
		portal = portal,

		bodyLower = bodyLower,

		bodyMid =
			findBone(
				model,
				"BodyMid"
			),

		bodyUpper =
			findBone(
				model,
				"BodyUpper"
			),

		roof =
			findBone(
				model,
				"Roof"
			),

		fingers = {},
		thumb = {},
		level2 = {},

		fx = {
			spray = {},
			mist = {},
			foam = {},
		},
	}

	--------------------------------------------------
	-- FOUR MAIN FINGERS
	--------------------------------------------------

	for i = 1, 4 do

		wave.fingers[i] = {

			root =
				findBone(
					model,
					"Finger"
					.. i
					.. "_Root"
				),

			curl =
				findBone(
					model,
					"Finger"
					.. i
					.. "_Curl"
				),

			tip =
				findBone(
					model,
					"Finger"
					.. i
					.. "_Tip"
				),
		}

	end

	--------------------------------------------------
	-- THUMB
	--------------------------------------------------

	wave.thumb = {

		root =
			findBone(
				model,
				"Thumb_Root"
			),

		curl =
			findBone(
				model,
				"Thumb_Curl"
			),

		tip =
			findBone(
				model,
				"Thumb_Tip"
			),
	}

	--------------------------------------------------
	-- LEVEL 2
	--------------------------------------------------

	for group = 1, 5 do

		wave.level2[group] = {}

		for i = 1, 4 do

			wave.level2[group][i] =
				findBone(
					model,
					"L2_"
					.. group
					.. "_"
					.. i
				)

		end

		wave.level2[group].thumb =
			findBone(
				model,
				"L2_"
				.. group
				.. "_Thumb"
			)

	end

	--------------------------------------------------
	-- PHASE
	--------------------------------------------------

	if model.Name == "Wave_Left" then

		wave.phase =
			-0.18

	elseif model.Name == "Wave_Right" then

		wave.phase =
			0.18

	else

		wave.phase =
			0

	end

	--------------------------------------------------
	-- ROOF MIST
	--------------------------------------------------

	if wave.roof then

		local roofMist =
			createEmitter(
				wave.roof,
				"RoofMist",
				"rbxasset://textures/particles/smoke_main.dds",
				6,
				2,
				7,
				1.0,
				2.0,
				55
			)

		roofMist.Size =
			NumberSequence.new({

				NumberSequenceKeypoint.new(
					0,
					6
				),

				NumberSequenceKeypoint.new(
					0.4,
					12
				),

				NumberSequenceKeypoint.new(
					1,
					18
				),
			})

		roofMist.Transparency =
			NumberSequence.new({

				NumberSequenceKeypoint.new(
					0,
					0.18
				),

				NumberSequenceKeypoint.new(
					0.45,
					0.45
				),

				NumberSequenceKeypoint.new(
					1,
					1
				),
			})

		roofMist.Rotation =
			NumberRange.new(
				0,
				360
			)

		roofMist.RotSpeed =
			NumberRange.new(
				-20,
				20
			)

		roofMist.Drag =
			3

		wave.fx.roofMist =
			roofMist
	end

	--------------------------------------------------
	-- LARGE FINGER FX
	--------------------------------------------------

	for i = 1, 4 do

		local tip =
			wave.fingers[i].tip

		if tip then

			------------------------------------------
			-- SPRAY
			------------------------------------------

			local spray =
				createEmitter(
					tip,
					"WaveSpray",
					"rbxasset://textures/particles/sparkles_main.dds",
					12,
					9,
					20,
					0.35,
					0.95,
					48
				)

			spray.Size =
				NumberSequence.new({

					NumberSequenceKeypoint.new(
						0,
						5
					),

					NumberSequenceKeypoint.new(
						0.2,
						8
					),

					NumberSequenceKeypoint.new(
						0.55,
						6
					),

					NumberSequenceKeypoint.new(
						1,
						0
					),
				})

			spray.Rotation =
				NumberRange.new(
					0,
					360
				)

			spray.RotSpeed =
				NumberRange.new(
					-110,
					110
				)

			spray.Acceleration =
				Vector3.new(
					0,
					-6,
					0
				)

			spray.Drag =
				1.5

			wave.fx.spray[i] =
				spray

			------------------------------------------
			-- MIST
			------------------------------------------

			local mist =
				createEmitter(
					tip,
					"WaveMist",
					"rbxasset://textures/particles/smoke_main.dds",
					10,
					3,
					11,
					0.9,
					2.1,
					65
				)

			mist.Size =
				NumberSequence.new({

					NumberSequenceKeypoint.new(
						0,
						6
					),

					NumberSequenceKeypoint.new(
						0.35,
						12
					),

					NumberSequenceKeypoint.new(
						1,
						18
					),
				})

			mist.Transparency =
				NumberSequence.new({

					NumberSequenceKeypoint.new(
						0,
						0.18
					),

					NumberSequenceKeypoint.new(
						0.5,
						0.5
					),

					NumberSequenceKeypoint.new(
						1,
						1
					),
				})

			mist.Rotation =
				NumberRange.new(
					0,
					360
				)

			mist.RotSpeed =
				NumberRange.new(
					-25,
					25
				)

			mist.Drag =
				3

			wave.fx.mist[i] =
				mist

			------------------------------------------
			-- FOAM
			------------------------------------------

			local foam =
				createEmitter(
					tip,
					"FoamFlecks",
					"rbxasset://textures/particles/sparkles_main.dds",
					10,
					4,
					11,
					0.45,
					1.15,
					42
				)

			foam.Size =
				NumberSequence.new({

					NumberSequenceKeypoint.new(
						0,
						4
					),

					NumberSequenceKeypoint.new(
						0.25,
						7
					),

					NumberSequenceKeypoint.new(
						0.65,
						5
					),

					NumberSequenceKeypoint.new(
						1,
						0
					),
				})

			foam.Rotation =
				NumberRange.new(
					0,
					360
				)

			foam.RotSpeed =
				NumberRange.new(
					-150,
					150
				)

			foam.Acceleration =
				Vector3.new(
					0,
					-8,
					0
				)

			foam.Drag =
				2

			wave.fx.foam[i] =
				foam
		end
	end

	--------------------------------------------------
	-- REGISTER
	--------------------------------------------------

	waves[model] =
		wave

	print(
		"[Kanagawa] REGISTERED:",
		model:GetFullName()
	)
end

--------------------------------------------------
-- EXISTING WAVES
--------------------------------------------------

for _, obj in ipairs(
	Portals:GetDescendants()
	) do

	if obj:IsA("Model") then
		task.spawn(
			function()
				registerWave(obj)
			end
		)
	end
end

--------------------------------------------------
-- FUTURE WAVES
--------------------------------------------------

Portals.DescendantAdded:Connect(
	function(obj)

		if not obj:IsA("Model") then
			return
		end

		if obj.Name == "Wave_Left"
			or obj.Name == "Wave_Center"
			or obj.Name == "Wave_Right"
		then

			task.delay(
				0.25,
				function()

					registerWave(obj)

				end
			)
		end
	end
)

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

local start =
	os.clock()

RunService.PreSimulation:Connect(
	function()

		local elapsed =
			os.clock()
		- start

		local cycleIndex =
			math.floor(
				elapsed / CYCLE
			)

		local elapsedInCycle =
			elapsed % CYCLE

		--------------------------------------------------
		-- AUDIO
		--------------------------------------------------

		for portal, audio in pairs(
			portalAudio
			) do

			if not portal.Parent then

				portalAudio[portal] =
					nil

				continue
			end

			------------------------------------------
			-- KEEP RUMBLE PLAYING
			------------------------------------------

			if audio.rumble
				and audio.rumble.IsLoaded
				and not audio.rumble.IsPlaying
			then

				audio.rumble:Play()
			end

			------------------------------------------
			-- WHOOSH
			------------------------------------------

			if elapsedInCycle >= WHOOSH_START_SEC
				and audio.lastWhooshCycle ~= cycleIndex
			then

				audio.lastWhooshCycle =
					cycleIndex

				if audio.whoosh then

					task.spawn(
						function()

							if not audio.whoosh.IsLoaded then
								audio.whoosh.Loaded:Wait()
							end

							audio.whoosh.TimePosition =
								0

							audio.whoosh:Play()

						end
					)
				end
			end
		end

		--------------------------------------------------
		-- WAVES
		--------------------------------------------------

		for model, wave in pairs(
			waves
			) do

			if not model.Parent then

				waves[model] =
					nil

				continue
			end

			local phase =
				wave.phase

			local sway =
				math.sin(
					elapsed * 0.85
					+ phase
				)

			local build =
				pulse(
					elapsedInCycle,
					BUILD_PEAK_SEC,
					0.12
				)

			local breaking =
				pulse(
					elapsedInCycle,
					BREAK_PEAK_SEC,
					0.055
				)

			--------------------------------------------------
			-- BODY
			--------------------------------------------------

			if wave.bodyLower then

				wave.bodyLower.Transform =
					rotZ(
						sway * 1.2
					)
			end

			if wave.bodyMid then

				wave.bodyMid.Transform =
					rotZ(
						sway * 2
						+ build
					)
			end

			if wave.bodyUpper then

				wave.bodyUpper.Transform =
					rotZ(
						sway * 3
						+ build * 2
						+ breaking * 3
					)
			end

			if wave.roof then

				wave.roof.Transform =
					rotZ(
						sway * 4
						+ build * 4
						+ breaking * 8
					)
			end

			--------------------------------------------------
			-- FINGERS
			--------------------------------------------------

			for i = 1, 4 do

				local finger =
					wave.fingers[i]

				local fingerPhase =
					phase
					+ (i - 1) * 0.16

				local fingerSway =
					math.sin(
						elapsed * 0.95
						+ fingerPhase
					)

				local fingerBreak =
					pulse(
						elapsedInCycle,
						BREAK_PEAK_SEC
						+ (i - 1) * 0.035,
						0.065
					)

				if finger.root then

					finger.root.Transform =
						rotZ(
							fingerSway * 2.5
							+ fingerBreak * 3
						)
				end

				if finger.curl then

					finger.curl.Transform =
						rotZ(
							fingerSway * 5
							+ build * 3
							+ fingerBreak * 10
						)
				end

				if finger.tip then

					finger.tip.Transform =
						rotZ(
							fingerSway * 7
							+ build * 5
							+ fingerBreak * 16
						)
				end

				--------------------------------------------------
				-- LEVEL 2
				--------------------------------------------------

				local l2Break =
					pulse(
						elapsedInCycle,
						BREAK_PEAK_SEC
						+ 0.07
						+ (i - 1) * 0.035,
						0.075
					)

				for j = 1, 4 do

					local b =
						wave.level2[i][j]

					if b then

						local miniSway =
							math.sin(
								elapsed * 1.15
								+ j * 0.30
								+ fingerPhase
							)

						b.Transform =
							rotZ(
								miniSway * 5
								+ l2Break * 18
							)
					end
				end

				local miniThumb =
					wave.level2[i].thumb

				if miniThumb then

					miniThumb.Transform =
						rotZ(
							-fingerSway * 2
							- l2Break * 5
						)
				end
			end

			--------------------------------------------------
			-- MAIN THUMB
			--------------------------------------------------

			local thumbBreak =
				pulse(
					elapsedInCycle,
					BREAK_PEAK_SEC + 0.12,
					0.08
				)

			if wave.thumb.root then

				wave.thumb.root.Transform =
					rotZ(
						-sway * 1.2
					)
			end

			if wave.thumb.curl then

				wave.thumb.curl.Transform =
					rotZ(
						-sway * 2
						- thumbBreak * 3
					)
			end

			if wave.thumb.tip then

				wave.thumb.tip.Transform =
					rotZ(
						-sway * 3
						- thumbBreak * 5
					)
			end

			--------------------------------------------------
			-- LEVEL 2 ON THUMB
			--------------------------------------------------

			for j = 1, 4 do

				local b =
					wave.level2[5][j]

				if b then

					local mini =
						math.sin(
							elapsed * 1.1
							+ j * 0.25
						)

					b.Transform =
						rotZ(
							mini * 4
							+ thumbBreak * 8
						)
				end
			end

			--------------------------------------------------
			-- DYNAMIC GISCHT / SCHAUM
			--------------------------------------------------

			if wave.fx then

				if wave.fx.roofMist then

					wave.fx.roofMist.Rate =
						6
						+ build * 30
						+ breaking * 65

					wave.fx.roofMist.Speed =
						NumberRange.new(
							2 + breaking * 4,
							8 + breaking * 8
						)
				end

				for i = 1, 4 do

					local spray =
						wave.fx.spray[i]

					local mist =
						wave.fx.mist[i]

					local foam =
						wave.fx.foam[i]

					if spray then

						spray.Rate =
							12
							+ build * 40
							+ breaking * 150

						spray.Speed =
							NumberRange.new(
								9 + breaking * 12,
								20 + breaking * 26
							)
					end

					if mist then

						mist.Rate =
							10
							+ build * 32
							+ breaking * 85

						mist.Speed =
							NumberRange.new(
								3 + breaking * 5,
								11 + breaking * 10
							)
					end

					if foam then

						foam.Rate =
							10
							+ build * 30
							+ breaking * 100

						foam.Speed =
							NumberRange.new(
								4 + breaking * 6,
								11 + breaking * 14
							)
					end
				end
			end
		end
	end
)