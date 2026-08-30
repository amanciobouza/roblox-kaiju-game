-- LocalScript: BodyTrainingControlsClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Während des Körper-Trainings (TitanAssimilationCircuit) steht die Kamera fest, damit
-- man den Spieler von außen beim Laufen beobachten kann (siehe TrainingCameraClient.lua).
-- Roblox berechnet "vorwärts" bei WASD/Touch-Steuerknüppel aber normalerweise relativ zur
-- AKTUELLEN Kamera-Blickrichtung -- bei einer festen Außenkamera + kreisförmigem Laufpfad
-- führt das dazu, dass man ständig die Richtung wechseln muss, um der Kurve zu folgen
-- ("im Kreis laufen"-Gefühl). Dieses Script ersetzt die Steuerung währenddessen durch
-- eine WELTFESTE Variante: eine Richtung bewegt immer in dieselbe, konstante
-- Weltrichtung -- funktioniert für Tastatur (WASD/Pfeiltasten) UND Touch (eigener
-- Steuerknüppel, da der Standard-Touch-Knüppel über dasselbe kamera-relative System läuft
-- und beim Deaktivieren der Standardsteuerung mit abgeschaltet würde).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
local controls = playerModule:GetControls()

-- Referenz-Ausrichtung: "W" soll in dieselbe Richtung laufen, in die auch die (feste)
-- Kamera schaut -- also die Ausrichtung von "FrontAnchor" in der Station, nicht eine
-- starre, willkürliche Weltrichtung. Wird beim Start des Trainings einmalig gesucht.
local stationForwardCFrame = CFrame.new() -- Rückfallebene: Standard-Weltachsen, falls FrontAnchor fehlt

local function findStationForwardCFrame()
	local station = workspace:FindFirstChild("BodyTrainingStation", true)
	local frontAnchor = station and station:FindFirstChild("FrontAnchor", true)
	if frontAnchor and frontAnchor:IsA("BasePart") then
		return CFrame.new(Vector3.new(), frontAnchor.CFrame.LookVector) -- nur Rotation, keine Position
	end
	return CFrame.new()
end

local keysDown = {
	[Enum.KeyCode.W] = false,
	[Enum.KeyCode.A] = false,
	[Enum.KeyCode.S] = false,
	[Enum.KeyCode.D] = false,
	[Enum.KeyCode.Up] = false,
	[Enum.KeyCode.Left] = false,
	[Enum.KeyCode.Down] = false,
	[Enum.KeyCode.Right] = false,
}

local touchDirection = Vector3.new(0, 0, 0) -- vom eigenen Touch-Steuerknüppel gesetzt

local isActive = false
local moveConnection = nil

local function getKeyboardDirection()
	local localDirection = Vector3.new(0, 0, 0)
	if keysDown[Enum.KeyCode.W] or keysDown[Enum.KeyCode.Up] then
		localDirection += Vector3.new(0, 0, -1)
	end
	if keysDown[Enum.KeyCode.S] or keysDown[Enum.KeyCode.Down] then
		localDirection += Vector3.new(0, 0, 1)
	end
	if keysDown[Enum.KeyCode.A] or keysDown[Enum.KeyCode.Left] then
		localDirection += Vector3.new(-1, 0, 0)
	end
	if keysDown[Enum.KeyCode.D] or keysDown[Enum.KeyCode.Right] then
		localDirection += Vector3.new(1, 0, 0)
	end
	if localDirection.Magnitude > 0 then
		localDirection = localDirection.Unit
	end
	-- Lokale Richtung (W=vorwärts usw.) in Weltraum umrechnen, ausgerichtet an der
	-- Stations-Blickrichtung (FrontAnchor) statt an starren Weltachsen.
	local direction = stationForwardCFrame:VectorToWorldSpace(localDirection)
	return direction
end

local function getFixedDirection()
	local keyboardDirection = getKeyboardDirection()
	if keyboardDirection.Magnitude > 0 then
		return keyboardDirection
	end
	return touchDirection -- fällt auf den Touch-Steuerknüppel zurück, falls keine Taste gedrückt ist
end

-- ===== Eigener Touch-Steuerknüppel (iPad/Mobile) =====
-- Nur sichtbar/aktiv auf Touch-Geräten UND während des Körper-Trainings. Erzeugt
-- KONTINUIERLICHE weltfeste Richtungen (nicht nur 8 diskrete Richtungen wie Tasten),
-- indem der Zieh-Versatz vom Berührungsstart direkt auf Welt-X/Welt-Z abgebildet wird.
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BodyTrainingJoystickGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local JOYSTICK_RADIUS = 60

local joystickBase = Instance.new("Frame")
joystickBase.Name = "JoystickBase"
joystickBase.Size = UDim2.new(0, JOYSTICK_RADIUS * 2, 0, JOYSTICK_RADIUS * 2)
joystickBase.AnchorPoint = Vector2.new(0, 1)
joystickBase.Position = UDim2.new(0, 60, 1, -100)
joystickBase.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
joystickBase.BackgroundTransparency = 0.7
joystickBase.Parent = screenGui

local joystickBaseCorner = Instance.new("UICorner")
joystickBaseCorner.CornerRadius = UDim.new(1, 0)
joystickBaseCorner.Parent = joystickBase

local joystickBaseStroke = Instance.new("UIStroke")
joystickBaseStroke.Thickness = 2
joystickBaseStroke.Color = Color3.new(1, 1, 1)
joystickBaseStroke.Transparency = 0.4
joystickBaseStroke.Parent = joystickBase

local joystickKnob = Instance.new("Frame")
joystickKnob.Name = "JoystickKnob"
joystickKnob.Size = UDim2.new(0, 50, 0, 50)
joystickKnob.AnchorPoint = Vector2.new(0.5, 0.5)
joystickKnob.Position = UDim2.new(0.5, 0, 0.5, 0)
joystickKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
joystickKnob.BackgroundTransparency = 0.15
joystickKnob.Parent = joystickBase

local joystickKnobCorner = Instance.new("UICorner")
joystickKnobCorner.CornerRadius = UDim.new(1, 0)
joystickKnobCorner.Parent = joystickKnob

local activeTouchId = nil

local function updateJoystickFromInput(inputPosition)
	local basePosition = joystickBase.AbsolutePosition + joystickBase.AbsoluteSize / 2
	local offset = Vector2.new(inputPosition.X, inputPosition.Y) - basePosition
	local magnitude = math.min(offset.Magnitude, JOYSTICK_RADIUS)
	local clampedOffset = offset.Magnitude > 0 and (offset.Unit * magnitude) or Vector2.new(0, 0)

	joystickKnob.Position = UDim2.new(0.5, clampedOffset.X, 0.5, clampedOffset.Y)

	-- Bildschirm-X/Y in eine LOKALE Richtung (rechts/vorwärts) umrechnen, dann genauso wie
	-- bei WASD an der Stations-Blickrichtung (FrontAnchor) ausrichten -- konsistent zur
	-- Tastatursteuerung oben, statt an starren Weltachsen.
	local ratio = magnitude / JOYSTICK_RADIUS
	if ratio > 0.05 then
		local localDirection = Vector3.new(clampedOffset.X, 0, clampedOffset.Y).Unit
		touchDirection = stationForwardCFrame:VectorToWorldSpace(localDirection) * math.min(ratio * 1.4, 1)
	else
		touchDirection = Vector3.new(0, 0, 0)
	end
end

local function resetJoystick()
	activeTouchId = nil
	touchDirection = Vector3.new(0, 0, 0)
	joystickKnob.Position = UDim2.new(0.5, 0, 0.5, 0)
end

joystickBase.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	activeTouchId = input
	updateJoystickFromInput(input.Position)
end)

UserInputService.InputChanged:Connect(function(input)
	if input ~= activeTouchId then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
		updateJoystickFromInput(input.Position)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input == activeTouchId then
		resetJoystick()
	end
end)

local function startWorldFixedControls()
	if isActive then
		return
	end
	isActive = true
	stationForwardCFrame = findStationForwardCFrame()
	controls:Disable() -- Roblox-Standardsteuerung (kamera-relativ) abschalten

	-- Eigenen Touch-Steuerknüppel nur auf Touch-Geräten einblenden (Desktop/Maus hat ja
	-- schon WASD, iPad/Mobile brauchen den Ersatz für den abgeschalteten Standard-Knüppel).
	if UserInputService.TouchEnabled then
		screenGui.Enabled = true
	end

	moveConnection = RunService.Heartbeat:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Move(getFixedDirection(), false)
		end
	end)
end

local function stopWorldFixedControls()
	if not isActive then
		return
	end
	isActive = false
	if moveConnection then
		moveConnection:Disconnect()
		moveConnection = nil
	end
	for key in pairs(keysDown) do
		keysDown[key] = false
	end
	resetJoystick()
	screenGui.Enabled = false

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.new(0, 0, 0), false) -- Restbewegung stoppen
	end
	controls:Enable() -- normale, kamera-relative Steuerung wiederherstellen
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not isActive or gameProcessed then
		return
	end
	if keysDown[input.KeyCode] ~= nil then
		keysDown[input.KeyCode] = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if keysDown[input.KeyCode] ~= nil then
		keysDown[input.KeyCode] = false
	end
end)

player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(function()
	if player:GetAttribute("BodyTrainingActive") then
		startWorldFixedControls()
	else
		stopWorldFixedControls()
	end
end)

-- Absicherung: falls der Charakter mitten im Training stirbt/respawnt, Steuerung sauber
-- zurückgeben, damit man draußen nicht versehentlich mit deaktivierten Standard-Controls
-- dasteht.
player.CharacterRemoving:Connect(function()
	if isActive then
		stopWorldFixedControls()
	end
end)