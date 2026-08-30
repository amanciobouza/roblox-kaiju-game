-- VERSION: 2026-08-26 #1 (V21 CLIENT) -- FEATURE: LiftReleasePlayerEvent ergaenzt
-- Sanctuary Lift V21 CLIENT
--
-- Location:
-- StarterPlayer
--   > StarterPlayerScripts
--     > SanctuaryLiftRider
--
-- Behaviour:
--
-- 1) Standing on lift:
--    Player follows the platform.
--
--    WASD movement is relative to the moving platform.
--
-- 3) Stop walking:
--    Player stops relative movement but continues riding.
--
-- 4) Walk off edge:
--    Player is released and falls.
--
-- 5) Jump:
--    Player is released normally.
--
-- IMPORTANT CHANGE FROM V20:
--
-- If we were already riding, we FIRST apply the platform
-- movement and ONLY AFTER THAT check whether the player
-- is still standing on the platform.
--
-- Otherwise the moving platform escapes from underneath
-- the player before the contact check succeeds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Meldet dem Server SOFORT, wenn der Spieler den Lift verlässt (Sprung o.ä.) -- Bugfix:
-- die reguläre server-seitige Erkennung (Raycast + CONTACT_GRACE-Verzögerung) erzeugte
-- ein Zeitfenster, in dem der Charakter noch in der Rider-Kollisionsgruppe feststeckte
-- und dadurch durch normale Parts fallen/stecken bleiben konnte.
local LiftReleasePlayerEvent = ReplicatedStorage:WaitForChild("LiftReleasePlayerEvent", 10)
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

-- WICHTIG (Bugfix): muss KLEINER sein als das server-seitige EDGE_PADDING (1.0, siehe
-- Sanctuary Lift V20 SERVER) -- der Client soll die Fahrt IMMER etwas FRÜHER beenden als
-- der Server die Kollisionsfreigabe zurücknimmt. War vorher 0.35 (deutlich kleiner als
-- der Server), wodurch ein Zeitfenster entstand, in dem der Client den Spieler noch per
-- CFrame durch den (laut Server bereits wieder kollidierenden) Mechanismus bewegt hat --
-- das direkte CFrame-Setzen überspringt dabei die normale Kollisionserkennung, was zum
-- Durchschweben/Steckenbleiben führen konnte.
local EDGE_PADDING = 0.8

-- Only compensates for tiny physics/raycast gaps.
local CONTACT_GRACE = 0.12

------------------------------------------------------------
-- FIND LIFT PARTS
------------------------------------------------------------

local function findLiftPart(name)

	while true do

		for _, obj in ipairs(workspace:GetDescendants()) do

			if obj:IsA("BasePart")
				and obj.Name == name then

				return obj
			end
		end

		task.wait(0.25)
	end
end

local platform =
	findLiftPart("LiftPlatform")

local inlay =
	findLiftPart("LiftPlatform_Inlay")

if not platform or not inlay then

	warn(
		"[Lift V21 CLIENT] LiftPlatform or LiftPlatform_Inlay not found."
	)

	return
end

------------------------------------------------------------
-- CHARACTER REFERENCES
------------------------------------------------------------

local character = nil
local humanoid = nil
local root = nil

local riding = false
local lastContact = 0

------------------------------------------------------------
-- PLATFORM HISTORY
------------------------------------------------------------

local previousPlatformCF =
	platform.CFrame

------------------------------------------------------------
-- CHARACTER SETUP
------------------------------------------------------------

local function setupCharacter(char)

	character = char

	humanoid =
		char:WaitForChild("Humanoid")

	root =
		char:WaitForChild("HumanoidRootPart")

	riding = false
	lastContact = 0

	previousPlatformCF =
		platform.CFrame
end

if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(
	setupCharacter
)

------------------------------------------------------------
-- RAYCAST
------------------------------------------------------------

local rayParams =
	RaycastParams.new()

rayParams.FilterType =
	Enum.RaycastFilterType.Include

rayParams.FilterDescendantsInstances = {
	platform,
	inlay
}

rayParams.IgnoreWater = true

------------------------------------------------------------
-- CHECK PLATFORM FOOTPRINT
------------------------------------------------------------

local function withinLiftFootprint()

	if not root
		or not root.Parent then

		return false
	end

	local lp =
		inlay.CFrame:PointToObjectSpace(
			root.Position
		)

	local halfX =
		inlay.Size.X * 0.5
		+ EDGE_PADDING

	local halfZ =
		inlay.Size.Z * 0.5
		+ EDGE_PADDING

	return
		math.abs(lp.X) <= halfX
		and
		math.abs(lp.Z) <= halfZ
end

------------------------------------------------------------
-- CHECK IF PLAYER WANTS TO LEAVE
------------------------------------------------------------

local function playerIsLeavingLift()

	if not humanoid
		or humanoid.Health <= 0 then

		return true
	end

	local state =
		humanoid:GetState()

	--------------------------------------------------------
	-- JUMP
	--------------------------------------------------------

	if humanoid.Jump
		or state == Enum.HumanoidStateType.Jumping then

		return true
	end

	--------------------------------------------------------
	-- We deliberately do NOT release just because the
	-- Humanoid briefly enters Freefall.
	--
	-- Moving CFrame platforms can cause tiny Freefall
	-- transitions even while the player is still standing
	-- on them.
	--------------------------------------------------------

	return false
end

------------------------------------------------------------
-- CHECK DIRECT CONTACT
------------------------------------------------------------

local function directContact()

	if not character
		or not humanoid
		or not root
		or not root.Parent
		or humanoid.Health <= 0 then

		return false
	end

	--------------------------------------------------------
	-- MUST STILL BE OVER PLATFORM
	--------------------------------------------------------

	if not withinLiftFootprint() then
		return false
	end

	--------------------------------------------------------
	-- RAYCAST DOWN
	--------------------------------------------------------

	local rayLength =
		math.max(
			12,

			humanoid.HipHeight
			+ root.Size.Y * 0.5
			+ 6
		)

	local result =
		workspace:Raycast(
			root.Position,

			Vector3.new(
				0,
				-rayLength,
				0
			),

			rayParams
		)

	return result ~= nil
end

------------------------------------------------------------
-- APPLY PLATFORM MOVEMENT
------------------------------------------------------------

local function carryWithPlatform(
	oldPlatformCF,
	newPlatformCF
)

	if not root
		or not root.Parent then

		return
	end

	--------------------------------------------------------
	-- Find player's CURRENT position relative to the OLD
	-- platform.
	--
	-- This is crucial:
	--
	-- The player's own WASD movement is already represented
	-- in root.Position.
	--
	-- So we do NOT store a fixed boarding position.
	--------------------------------------------------------

	local localPosition =
		oldPlatformCF:PointToObjectSpace(
			root.Position
		)

	--------------------------------------------------------
	-- Find where that relative point is now located on the
	-- NEW platform transform.
	--------------------------------------------------------

	local newWorldPosition =
		newPlatformCF:PointToWorldSpace(
			localPosition
		)

	--------------------------------------------------------
	-- Calculate ONLY the platform contribution.
	--------------------------------------------------------

	local displacement =
		newWorldPosition
	- root.Position

	--------------------------------------------------------
	-- Apply translation only.
	--
	-- We do NOT modify:
	--
	--   Humanoid.MoveDirection
	--   WalkSpeed
	--   AssemblyLinearVelocity
	--   Humanoid state
	--   character orientation
	--   camera
	--
	-- Therefore the player's own movement remains normal.
	--------------------------------------------------------

	root.CFrame =
		root.CFrame
		+ displacement
end

------------------------------------------------------------
-- MAIN LOOP
--
-- PreSimulation is intentional:
--
-- 1) Read how far platform moved.
-- 2) Carry the existing rider.
-- 3) Roblox physics/Humanoid then performs its own movement.
--
-- This gives us:
--
-- world movement =
--     lift movement
--     +
--     normal Humanoid movement
------------------------------------------------------------

RunService.PreSimulation:Connect(function()

	--------------------------------------------------------
	-- VALID CHARACTER?
	--------------------------------------------------------

	if not character
		or not character.Parent
		or not humanoid
		or not root
		or not root.Parent
		or humanoid.Health <= 0 then

		riding = false

		previousPlatformCF =
			platform.CFrame

		return
	end

	--------------------------------------------------------
	-- CURRENT PLATFORM TRANSFORM
	--------------------------------------------------------

	local currentPlatformCF =
		platform.CFrame

	--------------------------------------------------------
	-- IMPORTANT:
	--
	-- IF WE WERE ALREADY RIDING:
	-- MOVE PLAYER FIRST.
	--
	-- This fixes V20.
	--------------------------------------------------------

	if riding then

		----------------------------------------------------
		-- Jumping means immediate release.
		----------------------------------------------------

		if playerIsLeavingLift() then

			riding = false

			-- SOFORT dem Server melden -- nicht auf die reguläre, verzögerte
			-- Raycast-Erkennung warten (siehe LiftReleasePlayerEvent, Bugfix gegen
			-- Stecken-Bleiben in der Rider-Kollisionsgruppe).
			if LiftReleasePlayerEvent then
				LiftReleasePlayerEvent:FireServer()
			end

		else

			carryWithPlatform(
				previousPlatformCF,
				currentPlatformCF
			)
		end
	end

	--------------------------------------------------------
	-- NOW CHECK CONTACT
	--
	-- At this point an existing rider has already moved
	-- together with the new platform position.
	--------------------------------------------------------

	if not playerIsLeavingLift() then

		local contact =
			directContact()

		if contact then

			riding = true

			lastContact =
				os.clock()

		else

			------------------------------------------------
			-- If we're still over the platform, tolerate
			-- tiny raycast gaps.
			------------------------------------------------

			if riding
				and withinLiftFootprint()
				and (
					os.clock()
					- lastContact
				) <= CONTACT_GRACE then

				-- Stay riding.

			else

				if riding and LiftReleasePlayerEvent then
					LiftReleasePlayerEvent:FireServer()
				end

				riding = false
			end
		end

	else

		if riding and LiftReleasePlayerEvent then
			LiftReleasePlayerEvent:FireServer()
		end

		riding = false
	end

	--------------------------------------------------------
	-- SAVE PLATFORM TRANSFORM
	--------------------------------------------------------

	previousPlatformCF =
		currentPlatformCF
end)

------------------------------------------------------------
-- DEBUG
------------------------------------------------------------

print(
	"[SanctuaryLift] V21 CLIENT ACTIVE - carry first, contact second"
)