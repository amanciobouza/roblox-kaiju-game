-- LocalScript: FootstepSoundClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Ersetzt den eingebauten Roblox-Schritt-Sound ("Running", automatisch unter
-- HumanoidRootPart vorhanden) durch eine eigene Sound-ID -- bei jedem Charakter-Spawn neu,
-- da Roblox den Sound jedes Mal frisch mit der Standard-ID anlegt. Passt außerdem die
-- Abspielgeschwindigkeit laufend an die TATSÄCHLICHE Bewegungsgeschwindigkeit an -- unser
-- WalkSpeed variiert stark (8 bei Level 0 bis 30+ bei hohem Level/Heat-Boost), der
-- Standard-Sound würde sonst immer im selben, oft zu schnellen Takt abspielen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local CUSTOM_FOOTSTEP_SOUND_ID = "rbxassetid://104215208968170"

-- Referenz-Geschwindigkeit, bei der der Sound in "normalem" Takt (PlaybackSpeed = 1)
-- abgespielt werden soll -- Robloxs eigener Standard-WalkSpeed.
local REFERENCE_WALK_SPEED = 16
local MIN_PLAYBACK_SPEED = 0.6
local MAX_PLAYBACK_SPEED = 2.2

local function applyCustomFootstepSound(character)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not rootPart then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	-- Roblox legt den Schritt-Sound meist erst an, sobald der Charakter sich das erste Mal
	-- bewegt/der Humanoid vollständig initialisiert ist -- deshalb kurz mit WaitForChild
	-- abwarten statt sofort mit FindFirstChild aufzugeben.
	local runningSound = rootPart:WaitForChild("Running", 5)
	if not runningSound then
		return
	end

	runningSound.SoundId = CUSTOM_FOOTSTEP_SOUND_ID

	-- Laufend die Abspielgeschwindigkeit an die tatsächliche horizontale
	-- Bewegungsgeschwindigkeit anpassen, statt den festen Standard-Takt zu übernehmen.
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not runningSound.Parent or not rootPart.Parent then
			connection:Disconnect()
			return
		end
		local horizontalVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
		local speedRatio = horizontalVelocity.Magnitude / REFERENCE_WALK_SPEED
		runningSound.PlaybackSpeed = math.clamp(speedRatio, MIN_PLAYBACK_SPEED, MAX_PLAYBACK_SPEED)
	end)

	humanoid.Died:Connect(function()
		connection:Disconnect()
	end)
end

player.CharacterAdded:Connect(applyCustomFootstepSound)
if player.Character then
	applyCustomFootstepSound(player.Character)
end