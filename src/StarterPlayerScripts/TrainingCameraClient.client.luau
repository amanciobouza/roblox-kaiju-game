-- VERSION: 2026-08-25 #2 -- Rückbau des Follow-Kamera-Systems (zurück zu Custom)
-- LocalScript: TrainingCameraClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Vereinheitlichte Kamera-Mechanik für ALLE drei Trainingsstationen: die Kamera steht
-- immer FEST (berechnet aus dem "FrontAnchor"-Teil der jeweiligen Station, NICHT aus der
-- laufenden Spielerdrehung) -- dreht sich also nie mit, egal was der Spieler gerade tut.
-- Nur die STATIONS-SPEZIFISCHEN Werte (Abstand/Höhe/Blickpunkt) unterscheiden sich:
--   Arm:   über die Schulter, nah dran, schaut in dieselbe Richtung wie der Spieler
--   Bein:  weiter weg, damit ganzer Körper + Plattform sichtbar sind
--   Körper: hoch und weit weg, damit die ganze Trainingsstation sichtbar ist
-- Depth of Field sorgt dafür, dass alles bis und mit Station scharf ist, der Rest
-- dahinter unscharf. Rein clientseitig -- betrifft nur die eigene Sicht.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Namen der Stationen -- gleiche Namenskonvention wie in TrainingHandler.lua (STATIONS),
-- damit der Client sie eigenständig im Workspace finden kann.
local STATION_NAMES = {
	Leg = "LegTrainingStation",
	Arm = "TitanImpactGauntlet",
	Body = "BodyTrainingStation",
}

-- ===== Stations-spezifische Kamera-Konfiguration =====
-- "right"/"up"/"back" sind LOKALE Versätze relativ zu FrontAnchor (positiver "back"-Wert
-- = hinter FrontAnchor, in dessen lokaler +Z-Richtung). "focusMode" bestimmt, wohin die
-- Kamera schaut:
--   "ahead"         -- ein Stück vor FrontAnchor in dessen Blickrichtung (über die
--                      Schulter Richtung Ziel schauen, wie beim echten Schlagen)
--   "anchor"        -- direkt auf FrontAnchor (zeigt den ganzen Spieler + Umgebung)
--   "stationCenter" -- auf die Mitte der GESAMTEN Station (zeigt alles auf einmal)
local FIXED_CAMERA_CONFIG = {
	Arm = { right = 16, up = 22, back = 49, fov = 41, verticalFraming = 0, horizontalFraming = 0, focusMode = "ahead", forwardDistance = 14 },
	Leg = { right = 42, up = 19, back = 25, fov = 66, verticalFraming = 0.2, horizontalFraming = 0, focusMode = "anchor" },
	Body = { right = -19, up = 35, back = 61, fov = 41, verticalFraming = 0, horizontalFraming = 0, focusMode = "stationCenter" },
}

-- ===== Debug-Kamera-Steuerung =====
-- Überschreibt die obigen Werte NUR für die aktuelle Session (rein clientseitig,
-- rein zum Austesten) -- siehe Regler-Panel weiter unten. Wird pro Station separat
-- gemerkt, damit man zwischen den drei Stationen wechseln kann, ohne die Werte zu verlieren.
local debugOverrides = {} -- [statType] = { right, up, back, fov }

local function getConfigWithOverride(statType)
	local base = FIXED_CAMERA_CONFIG[statType]
	local override = debugOverrides[statType]
	if not override then
		return base
	end
	return {
		right = override.right,
		up = override.up,
		back = override.back,
		fov = override.fov,
		verticalFraming = override.verticalFraming,
		horizontalFraming = override.horizontalFraming,
		focusMode = base.focusMode,
		forwardDistance = base.forwardDistance,
	}
end

local isCameraActive = false
local currentStatType = nil
local renderConnection

local ownDoFEffect
local defaultFOV = camera.FieldOfView

-- ===== Cinematischer Look: engeres Sichtfeld (Tele-Objektiv-Gefühl), sanftes Schweben
-- (leichtes "Atmen" statt starrer Standbild-Kamera), Letterbox-Balken oben/unten =====
local CINEMATIC_FOV = 50 -- Standard ist meist 70 -- enger wirkt komprimierter/filmischer
local SWAY_ANGLE_DEGREES = 1.4 -- Oszillation des Orbit-Winkels (Grad) -- klar spürbar, aber nicht ablenkend
local SWAY_HEIGHT_AMPLITUDE = 0.6 -- Studs, vertikales "Atmen"
local SWAY_SPEED = 0.5 -- wie schnell das Schweben oszilliert
local cameraStartTime = 0

local letterboxGui = Instance.new("ScreenGui")
letterboxGui.Name = "TrainingLetterboxGui"
letterboxGui.ResetOnSpawn = false
letterboxGui.IgnoreGuiInset = true
letterboxGui.DisplayOrder = -10 -- weit hinten, damit HUD-Elemente (Coins, Level, Training-Panel etc.) immer davor liegen
letterboxGui.Enabled = false
letterboxGui.Parent = player:WaitForChild("PlayerGui")

local letterboxTop = Instance.new("Frame")
letterboxTop.Name = "Top"
letterboxTop.Size = UDim2.new(1, 0, 0, 0)
letterboxTop.Position = UDim2.new(0, 0, 0, 0)
letterboxTop.BackgroundColor3 = Color3.new(0, 0, 0)
letterboxTop.BorderSizePixel = 0
letterboxTop.ZIndex = 1
letterboxTop.Parent = letterboxGui

local letterboxBottom = Instance.new("Frame")
letterboxBottom.Name = "Bottom"
letterboxBottom.Size = UDim2.new(1, 0, 0, 0)
letterboxBottom.AnchorPoint = Vector2.new(0, 1)
letterboxBottom.Position = UDim2.new(0, 0, 1, 0)
letterboxBottom.BackgroundColor3 = Color3.new(0, 0, 0)
letterboxBottom.BorderSizePixel = 0
letterboxBottom.ZIndex = 1
letterboxBottom.Parent = letterboxGui

local LETTERBOX_HEIGHT = UDim.new(0, 48)

local function getOrCreateDoFEffect()
	if not ownDoFEffect or not ownDoFEffect.Parent then
		ownDoFEffect = Lighting:FindFirstChild("TrainingDepthOfField")
		if not ownDoFEffect then
			ownDoFEffect = Instance.new("DepthOfFieldEffect")
			ownDoFEffect.Name = "TrainingDepthOfField"
			ownDoFEffect.Parent = Lighting
		end
	end
	return ownDoFEffect
end

local function findStationPart(statType)
	local stationName = STATION_NAMES[statType]
	if not stationName then
		return nil
	end
	local instance = workspace:FindFirstChild(stationName, true)
	if not instance then
		return nil
	end
	if instance:IsA("Model") then
		return instance -- Model selbst zurückgeben, nicht ein zufälliges Einzelteil
	elseif instance:IsA("BasePart") then
		return instance
	end
	return nil
end

-- Ermittelt die tatsächliche Mitte der Station -- über die volle Bounding-Box (deckt alle
-- Teile ab, egal wie das Model intern aufgebaut ist), statt sich auf ein einzelnes,
-- möglicherweise zufällig gewähltes Teil zu verlassen.
local function getStationCenter(stationInstance)
	if stationInstance:IsA("Model") then
		local ok, center = pcall(function()
			local cframe, _size = stationInstance:GetBoundingBox()
			return cframe.Position
		end)
		if ok then
			return center
		end
	end
	return stationInstance.Position
end

-- Sucht das "FrontAnchor"-Teil in der Station -- die zentrale Referenz für Position UND
-- Blickrichtung, die auch TrainingHandler.lua/die Trainingsstations-Scripts selbst nutzen,
-- um den Spieler konsistent zu positionieren. Ohne FrontAnchor: Rückfallebene auf die
-- Stations-Mitte mit einer festen Weltrichtung als Blickachse.
local function getFrontAnchor(stationInstance)
	local frontAnchor = stationInstance:FindFirstChild("FrontAnchor", true)
	if frontAnchor and frontAnchor:IsA("BasePart") then
		return frontAnchor
	end
	return nil
end

-- ===== Hollywood-Feinschliff =====
local DUTCH_ANGLE_DEGREES = 4 -- leichte Neigung, dezent aber spürbar
-- Horizontaler + vertikaler Bildkomposition-Versatz sind PRO STATION in
-- FIXED_CAMERA_CONFIG gesetzt ("horizontalFraming"/"verticalFraming") -- Arm/Bein wollen
-- das Motiv tiefer im Bild (positiver vertikaler Wert), Körper braucht das Gegenteil
-- (negativer Wert, Motiv höher im Bild).
local FLY_IN_DURATION = 0.9 -- Sekunden für den Kamera-Einflug beim Trainingsstart
local FLY_IN_PULLBACK = 2.3 -- wie weit die Kamera beim Einflug-Start zusätzlich zurück/hoch steht (Multiplikator)

local function easeOutCubic(t)
	return 1 - (1 - t) ^ 3
end

local function updateFixedStationCamera(stationPart, statType)
	local config = getConfigWithOverride(statType)
	if not config then
		return
	end

	local frontAnchor = getFrontAnchor(stationPart)
	local anchorCFrame = frontAnchor and frontAnchor.CFrame or CFrame.new(getStationCenter(stationPart))

	-- Charaktergrösse berücksichtigen (unser Kaiju skaliert stark, 4x bis 14.85x je nach
	-- Skin-Stufe) -- ohne das würde die Kamera bei einem grossen, spät freigeschalteten
	-- Skin viel zu niedrig sitzen (z.B. unterhalb von Deko-Objekten wie einem Dashboard),
	-- da die Offsets sonst für die KLEINSTE Grösse berechnet blieben. Gilt nur für
	-- Arm/Bein (Charakter-relativ) -- bei Körper ist die Kamera Stations-relativ und soll
	-- unabhängig von der Charaktergrösse gleich bleiben.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local avatarScale = humanoid and humanoid:FindFirstChild("BodyHeightScale")
	local scaleMultiplier = (statType ~= "Body" and avatarScale) and avatarScale.Value or 1

	-- Sanftes, aber klar spürbares Schweben -- wirkt wie eine stabilisierte Handkamera
	-- statt eines starren Standbilds, ohne dabei hektisch/wackelig zu wirken.
	local elapsed = os.clock() - cameraStartTime
	local swayAngle = math.sin(elapsed * SWAY_SPEED) * SWAY_ANGLE_DEGREES
	local swayHeight = math.sin(elapsed * SWAY_SPEED * 0.7 + 1) * SWAY_HEIGHT_AMPLITUDE

	local function computeCameraAndFocus(pullbackMultiplier)
		local focusPosition
		local baseBackDirection -- Welt-Richtung "hinter" dem Motiv, BEVOR der Orbit-Winkel angewendet wird

		if statType == "Body" then
			focusPosition = getStationCenter(stationPart)
			baseBackDirection = Vector3.new(0, 0, 1)
			if frontAnchor then
				local flatBack = Vector3.new(-anchorCFrame.LookVector.X, 0, -anchorCFrame.LookVector.Z)
				if flatBack.Magnitude > 0.01 then
					baseBackDirection = flatBack.Unit
				end
			end
		elseif config.focusMode == "ahead" then
			focusPosition = anchorCFrame.Position + anchorCFrame.LookVector * ((config.forwardDistance or 12) * scaleMultiplier)
			-- "Hinter" dem Fokuspunkt aus Sicht des Spielers = zurück zur eigenen Position.
			local flatBack = Vector3.new(-anchorCFrame.LookVector.X, 0, -anchorCFrame.LookVector.Z)
			baseBackDirection = flatBack.Magnitude > 0.01 and flatBack.Unit or Vector3.new(0, 0, 1)
		else
			focusPosition = anchorCFrame.Position
			local flatBack = Vector3.new(-anchorCFrame.LookVector.X, 0, -anchorCFrame.LookVector.Z)
			baseBackDirection = flatBack.Magnitude > 0.01 and flatBack.Unit or Vector3.new(0, 0, 1)
		end

		-- Orbit: "right" ist ein WINKEL (Grad) um den Fokuspunkt, nicht eine lineare
		-- Seitwärts-Verschiebung -- die Kamera bewegt sich dadurch auf einem Kreis mit
		-- festem Radius ("back") um den Fokuspunkt und schaut IMMER auf ihn. Das Schweben
		-- wird hier als kleine, kontinuierliche Winkel-Oszillation obendrauf addiert --
		-- klar spürbar, aber verzerrt nie Distanz oder Blickwinkel zum Fokus.
		local orbitAngle = math.rad(config.right + swayAngle)
		local orbitRotation = CFrame.Angles(0, orbitAngle, 0)
		local orbitedBackDirection = orbitRotation:VectorToWorldSpace(baseBackDirection)

		local radius = config.back * pullbackMultiplier * scaleMultiplier
		local height = config.up * pullbackMultiplier * scaleMultiplier + swayHeight

		local cameraPosition = focusPosition + orbitedBackDirection * radius + Vector3.new(0, height, 0)

		return cameraPosition, focusPosition
	end

	local cameraPosition, focusPosition = computeCameraAndFocus(1)

	-- Rule of Thirds: Fokuspunkt nicht exakt mittig anpeilen, sondern leicht seitlich +
	-- nach oben versetzt -- verschiebt dadurch das eigentliche Motiv (Spieler/Station) im
	-- Bild von der Mitte weg (bzw. nach unten im Bild), klassische Bildkomposition statt
	-- zentriertem "Passfoto"-Look. Der vertikale Versatz verschiebt NUR die Bild-
	-- komposition (Motiv erscheint tiefer im Bild), nicht den eigentlichen Blickwinkel/
	-- die Kamera-Position.
	local baseLookCFrame = CFrame.new(cameraPosition, focusPosition)
	local distance = (focusPosition - cameraPosition).Magnitude
	local thirdsShift = baseLookCFrame.RightVector * (distance * (config.horizontalFraming or 0))
	local verticalShift = baseLookCFrame.UpVector * (distance * (config.verticalFraming or 0))
	local shiftedFocus = focusPosition + thirdsShift + verticalShift

	local targetCFrame = CFrame.new(cameraPosition, shiftedFocus)
		* CFrame.Angles(0, 0, math.rad(DUTCH_ANGLE_DEGREES)) -- leichter Dutch Angle

	-- Kamera-Einflug: in den ersten Sekunden von einer weiter zurückgezogenen Position
	-- sanft in die finale Position hineinfahren, statt sofort starr dazustehen.
	if elapsed < FLY_IN_DURATION then
		local flyInAlpha = easeOutCubic(math.clamp(elapsed / FLY_IN_DURATION, 0, 1))
		local startPosition, startFocus = computeCameraAndFocus(FLY_IN_PULLBACK)
		local startCFrame = CFrame.new(startPosition, startFocus)
		camera.CFrame = startCFrame:Lerp(targetCFrame, flyInAlpha)
	else
		camera.CFrame = targetCFrame
	end

	-- Depth of Field: alles bis und mit Fokuspunkt scharf, dahinter unscharf.
	local dof = getOrCreateDoFEffect()
	dof.FocusDistance = distance
	dof.InFocusRadius = distance
	dof.NearIntensity = 0
	dof.FarIntensity = statType == "Body" and 0.35 or 0.45

	-- FOV kontinuierlich setzen (nicht nur einmalig beim Start), damit der Debug-
	-- Kamera-Regler (Zoom) live wirkt, ohne die Kamera neu starten zu müssen. Nutzt den
	-- Stations-eigenen FOV-Wert (jede Station kann ihr eigenes Zoom-Niveau haben).
	local override = debugOverrides[statType]
	camera.FieldOfView = (override and override.fov) or config.fov or CINEMATIC_FOV
end

local function startTrainingCamera(statType)
	local stationPart = findStationPart(statType)
	if not stationPart or not FIXED_CAMERA_CONFIG[statType] then
		return
	end

	isCameraActive = true
	currentStatType = statType
	cameraStartTime = os.clock()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FIXED_CAMERA_CONFIG[statType].fov or CINEMATIC_FOV

	letterboxGui.Enabled = true
	TweenService:Create(letterboxTop, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 0, LETTERBOX_HEIGHT.Offset),
	}):Play()
	TweenService:Create(letterboxBottom, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 0, LETTERBOX_HEIGHT.Offset),
	}):Play()

	if renderConnection then
		renderConnection:Disconnect()
	end
	renderConnection = RunService.RenderStepped:Connect(function()
		updateFixedStationCamera(stationPart, statType)
	end)
end

local function stopTrainingCamera()
	isCameraActive = false
	currentStatType = nil
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = defaultFOV

	local topTween = TweenService:Create(letterboxTop, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(1, 0, 0, 0),
	})
	local bottomTween = TweenService:Create(letterboxBottom, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(1, 0, 0, 0),
	})
	topTween.Completed:Connect(function()
		letterboxGui.Enabled = false
	end)
	topTween:Play()
	bottomTween:Play()

	local dof = getOrCreateDoFEffect()
	dof.FarIntensity = 0
	dof.NearIntensity = 0
end

-- ===== Eigener Avatar leicht transparent während Arm-Training =====
-- Bei der Arm-Station steht man oft sehr nah dran, wodurch der eigene Charakter das Ziel
-- verdecken kann. Rein clientseitig (nur die eigene Sicht) -- andere Spieler sehen den
-- Avatar weiterhin normal.
local SELF_TRANSPARENCY = 0.55
local originalPartTransparency = {} -- [part] = number

local function setSelfTransparent(isTransparent)
	local character = player.Character
	if not character then
		return
	end

	if isTransparent then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				if originalPartTransparency[part] == nil then
					originalPartTransparency[part] = part.LocalTransparencyModifier
				end
				part.LocalTransparencyModifier = SELF_TRANSPARENCY
			end
		end
	else
		for part, original in pairs(originalPartTransparency) do
			if part.Parent then
				part.LocalTransparencyModifier = original
			end
		end
		originalPartTransparency = {}
	end
end

player:GetAttributeChangedSignal("TrainingStat"):Connect(function()
	local statType = player:GetAttribute("TrainingStat")
	setSelfTransparent(statType == "Arm")
	if statType then
		startTrainingCamera(statType)
	elseif isCameraActive then
		stopTrainingCamera()
	end
end)

player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(function()
	local active = player:GetAttribute("BodyTrainingActive")
	if active then
		startTrainingCamera("Body")
	elseif isCameraActive then
		stopTrainingCamera()
	end
end)

-- Falls der Charakter mitten im Training stirbt/respawnt: Kamera sauber zurückgeben,
-- Transparenz-Tracking aufräumen (neuer Charakter hat frische Teile).
player.CharacterRemoving:Connect(function()
	if isCameraActive then
		stopTrainingCamera()
	end
	originalPartTransparency = {}
end)

-- ===== Debug-Kamera-Regler =====
-- Nur sichtbar, wenn Debug-Modus aktiv UND gerade eine Trainingskamera läuft. Erlaubt
-- Position (right/up/back relativ zu FrontAnchor bzw. Stations-Mitte) und Zoom (FOV) live
-- per Regler einzustellen -- die aktuellen Werte werden dabei laufend ins Output-Fenster
-- geschrieben, zum Kopieren.
local debugCameraGui = Instance.new("ScreenGui")
debugCameraGui.Name = "DebugCameraGui"
debugCameraGui.ResetOnSpawn = false
debugCameraGui.Enabled = false
debugCameraGui.Parent = player:WaitForChild("PlayerGui")

local debugPanel = Instance.new("Frame")
debugPanel.Name = "DebugCameraPanel"
debugPanel.Size = UDim2.new(0, 300, 0, 308)
debugPanel.AnchorPoint = Vector2.new(1, 1)
debugPanel.Position = UDim2.new(1, -20, 1, -20)
debugPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
debugPanel.BackgroundTransparency = 0.1
debugPanel.Parent = debugCameraGui

local debugPanelCorner = Instance.new("UICorner")
debugPanelCorner.CornerRadius = UDim.new(0, 10)
debugPanelCorner.Parent = debugPanel

local debugTitle = Instance.new("TextLabel")
debugTitle.Size = UDim2.new(1, -8, 0, 20)
debugTitle.Position = UDim2.new(0, 4, 0, 2)
debugTitle.BackgroundTransparency = 1
debugTitle.Font = Enum.Font.FredokaOne
debugTitle.TextScaled = true
debugTitle.TextColor3 = Color3.new(1, 1, 1)
debugTitle.Text = "🎥 Debug-Kamera"
debugTitle.Parent = debugPanel

local DEBUG_SLIDER_DEFS = {
	{ key = "right", label = "Orbit-Winkel (°)", min = -90, max = 90 },
	{ key = "up", label = "Up", min = 0, max = 100 },
	{ key = "back", label = "Back (Radius)", min = 0, max = 100 },
	{ key = "fov", label = "Zoom (FOV)", min = 20, max = 90 },
	{ key = "verticalFraming", label = "Bildausschnitt Höhe", min = -0.4, max = 0.4 },
	{ key = "horizontalFraming", label = "Bildausschnitt Breite", min = -0.4, max = 0.4 },
}

local debugSliderSetters = {} -- [key] = function(value) -- zum Initialisieren beim Stationswechsel

local function printCurrentDebugValues()
	if not currentStatType then
		return
	end
	local override = debugOverrides[currentStatType]
	if not override then
		return
	end
	print(string.format(
		"[Kaiju-Debug-Kamera] %s = { right = %.1f, up = %.1f, back = %.1f, verticalFraming = %.2f, horizontalFraming = %.2f }, FOV = %.0f",
		currentStatType, override.right, override.up, override.back, override.verticalFraming, override.horizontalFraming, override.fov
		))
end

local function ensureOverrideForCurrentStation()
	if not currentStatType then
		return
	end
	if not debugOverrides[currentStatType] then
		local base = FIXED_CAMERA_CONFIG[currentStatType]
		debugOverrides[currentStatType] = {
			right = base.right,
			up = base.up,
			back = base.back,
			fov = base.fov or CINEMATIC_FOV,
			verticalFraming = base.verticalFraming or 0,
			horizontalFraming = base.horizontalFraming or 0,
		}
	end
end

for index, def in ipairs(DEBUG_SLIDER_DEFS) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -16, 0, 40)
	row.Position = UDim2.new(0, 8, 0, 24 + (index - 1) * 44)
	row.BackgroundTransparency = 1
	row.Parent = debugPanel

	local rowLabel = Instance.new("TextLabel")
	rowLabel.Size = UDim2.new(1, 0, 0, 16)
	rowLabel.BackgroundTransparency = 1
	rowLabel.Font = Enum.Font.FredokaOne
	rowLabel.TextScaled = true
	rowLabel.TextColor3 = Color3.new(1, 1, 1)
	rowLabel.TextXAlignment = Enum.TextXAlignment.Left
	rowLabel.Text = def.label .. ": 0"
	rowLabel.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 16)
	track.Position = UDim2.new(0, 0, 0, 20)
	track.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local handle = Instance.new("Frame")
	handle.Size = UDim2.new(0, 14, 0, 22)
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Position = UDim2.new(0, 0, 0.5, 0)
	handle.BackgroundColor3 = Color3.new(1, 1, 1)
	handle.ZIndex = 2
	handle.Parent = track

	local handleCorner = Instance.new("UICorner")
	handleCorner.CornerRadius = UDim.new(0, 4)
	handleCorner.Parent = handle

	local function setFromRatio(ratio, shouldPrint)
		ratio = math.clamp(ratio, 0, 1)
		local value = def.min + ratio * (def.max - def.min)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		handle.Position = UDim2.new(ratio, 0, 0.5, 0)
		rowLabel.Text = def.label .. ": " .. string.format("%.1f", value)

		ensureOverrideForCurrentStation()
		if currentStatType and debugOverrides[currentStatType] then
			debugOverrides[currentStatType][def.key] = value
			if shouldPrint then
				printCurrentDebugValues()
			end
		end
	end

	debugSliderSetters[def.key] = function(value)
		local ratio = (value - def.min) / (def.max - def.min)
		setFromRatio(ratio, false)
	end

	local dragging = false
	local function beginDrag(input)
		dragging = true
		local ratio = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
		setFromRatio(ratio, true)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
		end
	end)
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local ratio = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
			setFromRatio(ratio, true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local function refreshDebugCameraPanel()
	local shouldShow = player:GetAttribute("DebugMode") and isCameraActive and currentStatType ~= nil
	debugCameraGui.Enabled = shouldShow
	if shouldShow then
		ensureOverrideForCurrentStation()
		local override = debugOverrides[currentStatType]
		for key, setter in pairs(debugSliderSetters) do
			setter(override[key])
		end
	end
end

player:GetAttributeChangedSignal("DebugMode"):Connect(refreshDebugCameraPanel)
player:GetAttributeChangedSignal("TrainingStat"):Connect(refreshDebugCameraPanel)
player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(refreshDebugCameraPanel)