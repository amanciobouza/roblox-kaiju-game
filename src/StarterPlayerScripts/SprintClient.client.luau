-- VERSION: 2026-08-25 #2
-- CHANGE: Touch-Sprint über Steuerknüppel-Auslenkung statt eigenem Button
-- Ort in Studio: StarterPlayerScripts
--
-- Sprint-Steuerung: Linke Shift-Taste halten (oder auf Touch-Geräten ein eigener Button)
-- lässt den Charakter schneller laufen (siehe SPRINT_SPEED_MULTIPLIER in
-- HeatHandler.lua, wo der eigentliche Geschwindigkeits-Effekt server-seitig angewendet
-- wird -- rein clientseitig würde WalkSpeed sich nicht zuverlässig für andere Spieler
-- oder gegen Manipulation absichern lassen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local SetSprintingEvent = RemoteEventUtils.GetOrCreate("SetSprintingEvent")

local player = Players.LocalPlayer

local function setSprinting(sprinting)
	SetSprintingEvent:FireServer(sprinting)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprinting(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprinting(false)
	end
end)

-- Sicherheitsnetz: falls der Charakter stirbt/respawnt während die Taste gehalten wird,
-- serverseitig auf "nicht sprintend" zurücksetzen -- verhindert, dass ein alter,
-- "hängen gebliebener" Sprint-Zustand den neuen Charakter beeinflusst.
player.CharacterAdded:Connect(function()
	setSprinting(false)
end)

-- ===== Touch-Steuerung: kein eigener Button mehr -- nutzt stattdessen die Auslenkung
-- von Robloxs eingebautem Bewegungs-Steuerknüppel (DynamicThumbstick). Nah am
-- Ausgangspunkt der Berührung = normales Gehen, deutlich weiter weg = Sprinten. Fühlt
-- sich dadurch wie ein analoger Steuerknüppel an, statt eines separaten Schalters. =====
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	-- Ab dieser Auslenkung (in Pixeln, als Anteil der Bildschirmhöhe berechnet -- damit es
	-- auf jedem Gerät/jeder Auflösung gleich weit "draussen" liegt) gilt es als Sprinten.
	local SPRINT_THRESHOLD_FRACTION = 0.05

	local activeTouch = nil -- das InputObject des aktuell verfolgten Bewegungs-Touches
	local touchStartPosition = nil
	local isCurrentlySprinting = false

	local function getThresholdPixels()
		local viewportSize = workspace.CurrentCamera.ViewportSize
		return viewportSize.Y * SPRINT_THRESHOLD_FRACTION
	end

	local function updateSprintState(shouldSprint)
		if shouldSprint ~= isCurrentlySprinting then
			isCurrentlySprinting = shouldSprint
			setSprinting(shouldSprint)
		end
	end

	UserInputService.TouchStarted:Connect(function(touch, processed)
		if processed then
			return -- Berührung ging an ein UI-Element (Buttons etc.), nicht an die Bewegungssteuerung
		end
		-- Nur Berührungen auf der LINKEN Bildschirmhälfte verfolgen -- dort erscheint
		-- Robloxs Standard-Bewegungs-Steuerknüppel. Die rechte Seite ist für Kamera/
		-- Kampf-Eingaben reserviert und soll Sprint nicht versehentlich auslösen.
		local viewportSize = workspace.CurrentCamera.ViewportSize
		if touch.Position.X > viewportSize.X * 0.5 then
			return
		end
		if activeTouch then
			return -- schon ein Bewegungs-Touch in Verfolgung (z.B. Multitouch)
		end
		activeTouch = touch
		touchStartPosition = touch.Position
	end)

	UserInputService.TouchMoved:Connect(function(touch, processed)
		if touch ~= activeTouch or not touchStartPosition then
			return
		end
		local displacement =
			Vector2.new(touch.Position.X - touchStartPosition.X, touch.Position.Y - touchStartPosition.Y).Magnitude
		updateSprintState(displacement >= getThresholdPixels())
	end)

	UserInputService.TouchEnded:Connect(function(touch)
		if touch == activeTouch then
			activeTouch = nil
			touchStartPosition = nil
			updateSprintState(false)
		end
	end)
end