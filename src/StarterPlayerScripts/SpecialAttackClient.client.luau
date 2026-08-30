-- VERSION: 2026-08-26 #4
-- FEATURE: SimulatePrologueActionEvent -- simuliert echte Button-Drücke für den Prolog
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut 2 Buttons im HUD für die Spezialangriffe (Fokus-Laser, Flächenschaden), mit
-- Sanduhr-artiger Cooldown-Füllung (dunkler Überzug schrumpft, bis der Angriff wieder
-- bereit ist -- dann leuchtet der Button auf). Spielt außerdem die visuellen Effekte ab
-- (Laserstrahl vom Kopf, aufladende Explosion) -- für ALLE Spieler sichtbar, nicht nur den Angreifer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local applyComicStyle = ComicStyleUtils.Apply
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Sprung/Fokus/Fläche sind NUR während des Bein-Trainings erlaubt (dort werden sie ja
-- trainiert) -- während Arm-Training (TrainingStat) UND Körper-Training
-- (BodyTrainingActive, eigenes Attribut vom Kreisparcours-Script) gesperrt.
local function isSpecialAttacksBlocked()
	local trainingStat = player:GetAttribute("TrainingStat")
	if trainingStat and trainingStat ~= "Leg" then
		return true
	end
	if player:GetAttribute("BodyTrainingActive") then
		return true
	end
	return false
end

local AttackEvent = RemoteEventUtils.GetOrCreate("AttackEvent")
local attackCooldownValue = ReplicatedStorage:WaitForChild("AttackCooldown")
local PlayerJumpedEvent = RemoteEventUtils.GetOrCreate("PlayerJumpedEvent")
local jumpAttackCooldownValue = ReplicatedStorage:WaitForChild("JumpAttackCooldown")

local FocusAttackEvent = RemoteEventUtils.GetOrCreate("FocusAttackEvent")
local SimulatePrologueActionEvent = RemoteEventUtils.GetOrCreate("SimulatePrologueActionEvent")
local FocusChargeEvent = RemoteEventUtils.GetOrCreate("FocusChargeEvent")
local AreaAttackEvent = RemoteEventUtils.GetOrCreate("AreaAttackEvent")
local FocusAttackEffectEvent = RemoteEventUtils.GetOrCreate("FocusAttackEffectEvent")
local AreaAttackEffectEvent = RemoteEventUtils.GetOrCreate("AreaAttackEffectEvent")
local focusCooldownValue = ReplicatedStorage:WaitForChild("FocusAttackCooldown")
local areaCooldownValue = ReplicatedStorage:WaitForChild("AreaAttackCooldown")
local focusEnergyCostValue = ReplicatedStorage:WaitForChild("FocusEnergyCost")
local areaEnergyCostValue = ReplicatedStorage:WaitForChild("AreaEnergyCost")

-- WICHTIG: Trag hier deine eigenen Sound-IDs aus dem Creator Store ein
local FOCUS_CHARGE_SOUND_ID = "rbxassetid://1336756135" -- läuft WÄHREND der 2s Aufladephase
local FOCUS_SOUND_ID = "rbxassetid://139620337204036"
local AREA_CHARGE_SOUND_ID = "rbxassetid://139131445232833" -- läuft WÄHREND der Aufladephase
local AREA_SOUND_ID = "rbxassetid://114262262294281" -- der Knall bei der eigentlichen Explosion

local focusChargeSound = Instance.new("Sound")
focusChargeSound.Name = "FocusChargeSound"
focusChargeSound.SoundId = FOCUS_CHARGE_SOUND_ID
focusChargeSound.Volume = 0.8
focusChargeSound.Parent = SoundService

local focusSound = Instance.new("Sound")
focusSound.Name = "FocusAttackSound"
focusSound.SoundId = FOCUS_SOUND_ID
focusSound.Volume = 0.9
focusSound.Parent = SoundService

local areaChargeSound = Instance.new("Sound")
areaChargeSound.Name = "AreaAttackChargeSound"
areaChargeSound.SoundId = AREA_CHARGE_SOUND_ID
areaChargeSound.Volume = 0.8
areaChargeSound.Parent = SoundService

local areaSound = Instance.new("Sound")
areaSound.Name = "AreaAttackSound"
areaSound.SoundId = AREA_SOUND_ID
areaSound.Volume = 0.9
areaSound.Parent = SoundService

-- ===== Comic-Style Hilfsfunktion (wie im Haupt-HUD) =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SpecialAttackGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== Baut einen einzelnen Spezialangriffs-Button =====
local function createAttackButton(name, icon, labelText, color, position, keyHint)
	local button = Instance.new("TextButton")
	button.Name = name .. "Button"
	button.Size = UDim2.new(0, 100, 0, 100)
	button.Position = position
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.Font = Enum.Font.LuckiestGuy
	button.TextScaled = true
	button.Text = ""
	button.ZIndex = 10
	button.Parent = screenGui
	applyComicStyle(button, 20, 5)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, 0, 0.55, 0)
	iconLabel.Position = UDim2.new(0, 0, 0, 4)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.LuckiestGuy
	iconLabel.TextScaled = true
	iconLabel.Text = icon
	iconLabel.ZIndex = 11
	iconLabel.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.25, 0)
	nameLabel.Position = UDim2.new(0, 0, 0.6, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Text = labelText
	nameLabel.ZIndex = 11
	nameLabel.Parent = button

	if keyHint then
		local keyLabel = Instance.new("TextLabel")
		keyLabel.Name = "KeyHint"
		keyLabel.Size = UDim2.new(0, 26, 0, 26)
		keyLabel.AnchorPoint = Vector2.new(1, 0)
		keyLabel.Position = UDim2.new(1, -4, 0, 4)
		keyLabel.BackgroundColor3 = Color3.new(0, 0, 0)
		keyLabel.BackgroundTransparency = 0.35
		keyLabel.Font = Enum.Font.FredokaOne
		keyLabel.TextScaled = true
		keyLabel.TextColor3 = Color3.new(1, 1, 1)
		keyLabel.Text = keyHint
		keyLabel.ZIndex = 14
		keyLabel.Parent = button
		applyComicStyle(keyLabel, 6, 2)
	end

	-- "Sanduhr"-Überzug: dunkler Bereich, der schrumpft, während der Cooldown abläuft.
	-- Oben verankert, damit es wie ablaufender Sand von oben nach unten wirkt.
	local cooldownOverlay = Instance.new("Frame")
	cooldownOverlay.Name = "CooldownOverlay"
	cooldownOverlay.AnchorPoint = Vector2.new(0, 0)
	cooldownOverlay.Position = UDim2.new(0, 0, 0, 0)
	cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
	cooldownOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	cooldownOverlay.BackgroundTransparency = 0.25
	cooldownOverlay.BorderSizePixel = 0
	cooldownOverlay.ZIndex = 12
	cooldownOverlay.Parent = button

	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "CooldownLabel"
	cooldownLabel.Size = UDim2.new(1, 0, 1, 0)
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Font = Enum.Font.LuckiestGuy
	cooldownLabel.TextScaled = true
	cooldownLabel.TextColor3 = Color3.new(1, 1, 1)
	cooldownLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	cooldownLabel.TextStrokeTransparency = 0
	cooldownLabel.ZIndex = 13
	cooldownLabel.Text = ""
	cooldownLabel.Parent = button

	return button, cooldownOverlay, cooldownLabel
end

-- ===== Kleines Energie-Kosten-Label, nur für Focus/Area (Attack/Jump kosten keine
-- Special Energy). Zeigt normal "⚡25", bei zu wenig Energie stattdessen die fehlende
-- Menge in Rot ("-12 fehlen"). =====
local function addEnergyCostLabel(button)
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "EnergyCostLabel"
	costLabel.Size = UDim2.new(1, 0, 0.22, 0)
	costLabel.Position = UDim2.new(0, 0, 0.82, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Enum.Font.FredokaOne
	costLabel.TextScaled = true
	costLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
	costLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	costLabel.TextStrokeTransparency = 0
	costLabel.ZIndex = 11
	costLabel.Text = ""
	costLabel.Parent = button
	return costLabel
end

local attackButton, attackOverlay, attackCooldownLabel =
	createAttackButton("Attack", "👊", "Punch", Color3.fromRGB(90, 140, 220), UDim2.new(0.5, -290, 1, -24))
local jumpButton, jumpOverlay, jumpCooldownLabel =
	createAttackButton("Jump", "🦶", "Jump", Color3.fromRGB(90, 190, 140), UDim2.new(0.5, -180, 1, -24))
local focusButton, focusOverlay, focusCooldownLabel =
	createAttackButton("Focus", "🔴", "Focus", Color3.fromRGB(220, 60, 60), UDim2.new(0.5, 180, 1, -24), "Q")
local areaButton, areaOverlay, areaCooldownLabel =
	createAttackButton("Area", "💥", "Area", Color3.fromRGB(255, 150, 30), UDim2.new(0.5, 290, 1, -24), "E")

local focusEnergyLabel = addEnergyCostLabel(focusButton)
local areaEnergyLabel = addEnergyCostLabel(areaButton)
local FOCUS_BUTTON_COLOR = focusButton.BackgroundColor3
local AREA_BUTTON_COLOR = areaButton.BackgroundColor3
local DESATURATED_COLOR = Color3.fromRGB(90, 90, 95)

-- ===== Sprung-Cooldown: gilt fürs SPRINGEN SELBST (Leertaste + Button gleichermaßen),
-- keine zusätzliche Aktion. Sobald ein Sprung beginnt, wird die Sprungfähigkeit für die
-- Cooldown-Dauer deaktiviert (JumpPower/JumpHeight auf 0), danach automatisch wiederhergestellt.
local jumpLocked = false

local function setupJumpLock(character)
	local humanoid = character:WaitForChild("Humanoid")

	humanoid.StateChanged:Connect(function(_, newState)
		if jumpLocked then
			return
		end
		if newState ~= Enum.HumanoidStateType.Jumping and newState ~= Enum.HumanoidStateType.Freefall then
			return
		end
		if isSpecialAttacksBlocked() then
			return -- Springen während Arm-/Körper-Training soll keinen echten Sprungangriff auslösen
		end

		jumpLocked = true
		PlayerJumpedEvent:FireServer()

		local usesJumpPower = humanoid.UseJumpPower
		local originalPower = usesJumpPower and humanoid.JumpPower or humanoid.JumpHeight

		-- WICHTIG: Mit einer kleinen echten Verzögerung (nicht nur task.defer) auf 0
		-- setzen, damit der Physik-Engine garantiert genug Zeit hat, den Sprung-Impuls
		-- mit dem VOLLEN JumpPower-Wert anzuwenden, bevor wir ihn sperren. Vorher wurde
		-- der Sprung dadurch selbst schon abgeschnitten -> nur ein kurzer Hüpfer.
		task.delay(0.2, function()
			if usesJumpPower then
				humanoid.JumpPower = 0
			else
				humanoid.JumpHeight = 0
			end
		end)

		local isLegTrainingBoosted = player:GetAttribute("TrainingStat") == "Leg"
			and Workspace:GetServerTimeNow() < (player:GetAttribute("BoostEndsAt") or 0)
		local jumpLockDuration = isLegTrainingBoosted and (jumpAttackCooldownValue.Value / 2) or jumpAttackCooldownValue.Value

		task.delay(jumpLockDuration, function()
			if humanoid.Parent then
				if usesJumpPower then
					humanoid.JumpPower = originalPower
				else
					humanoid.JumpHeight = originalPower
				end
			end
			jumpLocked = false
		end)
	end)
end

if player.Character then
	setupJumpLock(player.Character)
end
player.CharacterAdded:Connect(function(character)
	jumpLocked = false
	setupJumpLock(character)
end)
-- ===== Auslöse-Funktionen (von Buttons UND Tastatur/Gamepad gemeinsam genutzt) =====
local function triggerAttack()
	local readyAt = player:GetAttribute("AttackReadyAt") or 0
	if Workspace:GetServerTimeNow() >= readyAt then
		-- Feuert NICHT direkt AttackEvent -- das übernimmt AttackClient.lua zentral über
		-- dieses BindableEvent, damit der Combo-Schritt (für den Dritter-Schlag-Bonus)
		-- auch beim Tippen auf diesen Button korrekt mitgeschickt wird (wichtig für
		-- Touch-Geräte wie iPad, wo dies der einzige Weg zum Schlagen ist).
		local touchAttackButtonPressed = player:FindFirstChild("TouchAttackButtonPressed")
		if touchAttackButtonPressed then
			touchAttackButtonPressed:Fire()
		end
	end
end

local function triggerJump()
	-- Löst nur einen ganz normalen Sprung aus (wie die Leertaste) -- keine zusätzliche
	-- Aktion. Ob der Sprung tatsächlich passiert, entscheidet allein das Sprung-Sperr-
	-- System oben (JumpPower/JumpHeight ist während des Cooldowns auf 0 gesetzt).
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Jump = true
	end
end

local function triggerFocus()
	local readyAt = player:GetAttribute("FocusAttackReadyAt") or 0
	if Workspace:GetServerTimeNow() >= readyAt then
		FocusAttackEvent:FireServer()
	end
end

local function triggerArea()
	local readyAt = player:GetAttribute("AreaAttackReadyAt") or 0
	if Workspace:GetServerTimeNow() >= readyAt then
		AreaAttackEvent:FireServer()
	end
end

-- Für den Prolog: simuliert einen "echten" Button-Druck (inkl. Cooldown-Prüfung) --
-- nutzt exakt dieselben Funktionen wie ein tatsächlicher Klick auf den jeweiligen Button.
-- "Punch" läuft separat über AttackClient.lua (TouchAttackButtonPressed-BindableEvent).
SimulatePrologueActionEvent.OnClientEvent:Connect(function(actionType)
	if actionType == "Punch" then
		triggerAttack()
	elseif actionType == "Jump" then
		triggerJump()
	elseif actionType == "Focus" then
		triggerFocus()
	elseif actionType == "Area" then
		triggerArea()
	end
end)

-- ===== Klick-Handler =====
-- Schlag-Button bleibt unverändert (nie während irgendeines Trainings sichtbar/nutzbar).
-- Fokus/Fläche: während des BEIN-Trainings funktionieren sie tatsächlich (kürzerer
-- Cooldown, Fokus zielt aufs "LaserTarget"), aber OHNE echten Schaden -- siehe
-- SpecialAttackHandler.lua. Bei Arm/Körper-Training weiterhin komplett gesperrt.
attackButton.MouseButton1Click:Connect(triggerAttack)
jumpButton.MouseButton1Click:Connect(function()
	if isSpecialAttacksBlocked() then
		return
	end
	triggerJump()
end)
focusButton.MouseButton1Click:Connect(function()
	if isSpecialAttacksBlocked() then
		return
	end
	triggerFocus()
end)
areaButton.MouseButton1Click:Connect(function()
	if isSpecialAttacksBlocked() then
		return
	end
	triggerArea()
end)

-- ===== Tastatur- und Gamepad-Bindings für die beiden Spezialangriffe =====
-- Tastatur: Q = Fokus, E = Fläche | Gamepad: X-Button = Fokus, Y-Button = Fläche
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if isSpecialAttacksBlocked() then
		return -- gerade an Arm-/Körper-Station am Trainieren -- Tasten gehen ans Training, nicht an Spezialangriffe
	end

	if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonX then
		triggerFocus()
	elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonY then
		triggerArea()
	end
end)

-- ===== Leucht-Effekt, wenn ein Angriff bereit wird (einmaliger Puls) =====
local function playReadyGlow(button)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	local originalColor = stroke.Color
	stroke.Color = Color3.fromRGB(255, 255, 150)
	local tween = TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Color = originalColor,
	})
	tween:Play()
end

local wasAttackReady = true
local wasJumpReady = true
local wasFocusReady = true
local wasAreaReady = true
local wasFocusEnergyEnough = true
local wasAreaEnergyEnough = true

-- ===== Läuft jeden Frame: aktualisiert die Sanduhr-Füllung + Cooldown-Text =====
local function updateCooldownDisplay(overlay, label, readyAt, cooldownDuration)
	local now = Workspace:GetServerTimeNow()
	local remaining = readyAt - now

	if remaining <= 0 then
		overlay.Size = UDim2.new(1, 0, 0, 0)
		label.Text = ""
		return true
	end

	local ratio = math.clamp(remaining / math.max(cooldownDuration, 0.1), 0, 1)
	overlay.Size = UDim2.new(1, 0, ratio, 0)
	return false
end

RunService.Heartbeat:Connect(function()
	local attackReadyAt = player:GetAttribute("AttackReadyAt") or 0
	local jumpReadyAt = player:GetAttribute("JumpAttackReadyAt") or 0
	local focusReadyAt = player:GetAttribute("FocusAttackReadyAt") or 0
	local areaReadyAt = player:GetAttribute("AreaAttackReadyAt") or 0

	-- Bein-Training nutzt die GLEICHEN Cooldowns wie im echten Spiel (siehe
	-- SpecialAttackHandler.lua) -- außer während eines aktiven Trainings-Boosts, dann
	-- werden sie halbiert. Anzeige muss DENSELBEN Wert kennen, sonst füllt sich der
	-- Balken relativ zum falschen Bezugswert.
	local isLegTraining = player:GetAttribute("TrainingStat") == "Leg"
	local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
	local isBoosted = isLegTraining and Workspace:GetServerTimeNow() < boostEndsAt
	local focusCooldownDuration = isBoosted and (focusCooldownValue.Value / 2) or focusCooldownValue.Value
	local areaCooldownDuration = isBoosted and (areaCooldownValue.Value / 2) or areaCooldownValue.Value
	local jumpCooldownDuration = isBoosted and (jumpAttackCooldownValue.Value / 2) or jumpAttackCooldownValue.Value

	local attackReady = updateCooldownDisplay(attackOverlay, attackCooldownLabel, attackReadyAt, attackCooldownValue.Value)
	local jumpReady = updateCooldownDisplay(jumpOverlay, jumpCooldownLabel, jumpReadyAt, jumpCooldownDuration)
	local focusReady = updateCooldownDisplay(focusOverlay, focusCooldownLabel, focusReadyAt, focusCooldownDuration)
	local areaReady = updateCooldownDisplay(areaOverlay, areaCooldownLabel, areaReadyAt, areaCooldownDuration)

	if attackReady and not wasAttackReady then
		playReadyGlow(attackButton)
	end
	if jumpReady and not wasJumpReady then
		playReadyGlow(jumpButton)
	end
	if focusReady and not wasFocusReady then
		playReadyGlow(focusButton)
	end
	if areaReady and not wasAreaReady then
		playReadyGlow(areaButton)
	end

	wasAttackReady = attackReady
	wasJumpReady = jumpReady
	wasFocusReady = focusReady
	wasAreaReady = areaReady

	-- ===== Energie-Feedback: Kosten anzeigen, Button entsättigen wenn zu wenig Energie
	-- vorhanden ist, fehlende Menge anzeigen, kurzer Puls beim Erreichen genug Energie. =====
	local currentEnergy = player:GetAttribute("SpecialEnergy") or 0
	local focusCost = focusEnergyCostValue.Value
	local areaCost = areaEnergyCostValue.Value
	local hasEnoughFocusEnergy = currentEnergy >= focusCost
	local hasEnoughAreaEnergy = currentEnergy >= areaCost

	if hasEnoughFocusEnergy then
		focusButton.BackgroundColor3 = FOCUS_BUTTON_COLOR
		focusEnergyLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
		focusEnergyLabel.Text = "⚡" .. focusCost
	else
		focusButton.BackgroundColor3 = FOCUS_BUTTON_COLOR:Lerp(DESATURATED_COLOR, 0.6)
		focusEnergyLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
		focusEnergyLabel.Text = "-" .. math.ceil(focusCost - currentEnergy) .. " fehlen"
	end

	if hasEnoughAreaEnergy then
		areaButton.BackgroundColor3 = AREA_BUTTON_COLOR
		areaEnergyLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
		areaEnergyLabel.Text = "⚡" .. areaCost
	else
		areaButton.BackgroundColor3 = AREA_BUTTON_COLOR:Lerp(DESATURATED_COLOR, 0.6)
		areaEnergyLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
		areaEnergyLabel.Text = "-" .. math.ceil(areaCost - currentEnergy) .. " fehlen"
	end

	if hasEnoughFocusEnergy and not wasFocusEnergyEnough then
		playReadyGlow(focusButton)
	end
	if hasEnoughAreaEnergy and not wasAreaEnergyEnough then
		playReadyGlow(areaButton)
	end
	wasFocusEnergyEnough = hasEnoughFocusEnergy
	wasAreaEnergyEnough = hasEnoughAreaEnergy
end)

-- ===== Visuelle Effekte: für ALLE Spieler sichtbar, nicht nur den Angreifer =====

-- Laserstrahl vom Kopf zum Trefferpunkt -- EINE durchgehende Instanz pro Angriff, die bei
-- jedem Server-Tick nachgeführt wird (nicht mehr neu erzeugt), damit er als echter Dauerstrahl
-- wirkt statt als Reihe einzelner Blitze. Verblasst automatisch, wenn 0.4s lang kein neuer
-- Tick mehr ankommt (Angriff ist zu Ende).
local activeFocusBeams = {} -- [attackerPlayer] = { beam=, glow=, light=, lastUpdate= }
local FOCUS_BEAM_TIMEOUT = 0.4

local function updateFocusBeam(attackerPlayer, startPos, endPos)
	local distance = (endPos - startPos).Magnitude
	local beamCFrame = CFrame.new(startPos, endPos) * CFrame.new(0, 0, -distance / 2)

	local entry = activeFocusBeams[attackerPlayer]
	if not entry then
		local beam = Instance.new("Part")
		beam.Name = "FocusLaser"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Material = Enum.Material.Neon
		beam.Color = Color3.fromRGB(255, 90, 90)
		beam.Parent = Workspace

		local glow = Instance.new("Part")
		glow.Name = "FocusLaserGlow"
		glow.Anchored = true
		glow.CanCollide = false
		glow.CanQuery = false
		glow.Material = Enum.Material.Neon
		glow.Color = Color3.fromRGB(255, 150, 150)
		glow.Transparency = 0.55
		glow.Parent = Workspace

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 80, 80)
		light.Range = 20
		light.Brightness = 5
		light.Parent = beam

		entry = { beam = beam, glow = glow, light = light }
		activeFocusBeams[attackerPlayer] = entry

		if attackerPlayer == player and focusSound.SoundId ~= "" and focusSound.SoundId ~= "rbxassetid://0" then
			focusSound.TimePosition = 0
			focusSound.Looped = true
			focusSound:Play()
		end
	end

	entry.beam.Size = Vector3.new(2, 2, distance)
	entry.beam.CFrame = beamCFrame
	entry.beam.Transparency = 0
	entry.glow.Size = Vector3.new(5, 5, distance)
	entry.glow.CFrame = beamCFrame
	entry.glow.Transparency = 0.55
	entry.light.Brightness = 5
	entry.lastUpdate = os.clock()
end

-- Feuert einmalig zu Beginn der 2s Aufladephase (nur für den Angreifer selbst)
FocusChargeEvent.OnClientEvent:Connect(function()
	if focusChargeSound.SoundId ~= "" and focusChargeSound.SoundId ~= "rbxassetid://0" then
		focusChargeSound.TimePosition = 0
		focusChargeSound:Play()
	end
end)

FocusAttackEffectEvent.OnClientEvent:Connect(function(attackerPlayer, startPos, endPos)
	if attackerPlayer == player and focusChargeSound.Playing then
		focusChargeSound:Stop()
	end
	updateFocusBeam(attackerPlayer, startPos, endPos)
end)

-- Räumt Strahlen auf, für die längere Zeit kein neuer Tick mehr kam (Angriff beendet).
RunService.Heartbeat:Connect(function()
	for attackerPlayer, entry in pairs(activeFocusBeams) do
		if os.clock() - entry.lastUpdate > FOCUS_BEAM_TIMEOUT then
			activeFocusBeams[attackerPlayer] = nil

			if attackerPlayer == player and focusSound.Playing then
				focusSound.Looped = false
				focusSound:Stop()
			end

			local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(entry.beam, tweenInfo, { Transparency = 1 }):Play()
			TweenService:Create(entry.glow, tweenInfo, { Transparency = 1 }):Play()
			local lightTween = TweenService:Create(entry.light, tweenInfo, { Brightness = 0 })
			lightTween:Play()
			lightTween.Completed:Connect(function()
				entry.beam:Destroy()
				entry.glow:Destroy()
			end)
		end
	end
end)

-- Aufladende Ladung, die nach kurzer Zeit explodiert
AreaAttackEffectEvent.OnClientEvent:Connect(function(attackerPlayer, position, chargeTime, radius)
	radius = radius or 50

	local chargePart = Instance.new("Part")
	chargePart.Name = "AreaAttackCharge"
	chargePart.Shape = Enum.PartType.Ball
	chargePart.Anchored = true
	chargePart.CanCollide = false
	chargePart.CanQuery = false
	chargePart.Material = Enum.Material.Neon
	chargePart.Color = Color3.fromRGB(255, 150, 30)
	chargePart.Size = Vector3.new(2, 2, 2)
	chargePart.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
	chargePart.Parent = Workspace

	-- Die sichtbare Ladung wächst proportional zum tatsächlichen Wirkungsradius,
	-- damit optisch klar wird, wie groß der Angriff wirklich ist.
	local chargeVisualSize = math.clamp(radius * 0.3, 8, 60)
	local growTween = TweenService:Create(
		chargePart,
		TweenInfo.new(chargeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ Size = Vector3.new(chargeVisualSize, chargeVisualSize, chargeVisualSize) }
	)
	growTween:Play()

	if attackerPlayer == player and areaChargeSound.SoundId ~= "" and areaChargeSound.SoundId ~= "rbxassetid://0" then
		areaChargeSound.TimePosition = 0
		areaChargeSound:Play()
	end

	task.delay(chargeTime, function()
		chargePart:Destroy()

		if areaChargeSound.Playing then
			areaChargeSound:Stop()
		end

		if attackerPlayer == player and areaSound.SoundId ~= "" and areaSound.SoundId ~= "rbxassetid://0" then
			areaSound.TimePosition = 0
			areaSound:Play()
		end

		local explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastRadius = radius
		explosion.BlastPressure = 0
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = Workspace
	end)
end)

-- ===== HUD in der Sanctuary-Zone ausblenden (dort ist ohnehin kein Kampf möglich) --
-- AUSNAHME: Während des Arm-Trainings soll der Schlag-Button sichtbar bleiben (Cooldown-
-- Anzeige), während des Bein-Trainings sollen Sprung/Fokus/Fläche trotzdem sichtbar sein
-- -- so sieht der Spieler direkt, was er gerade trainiert/einsetzt.
local function updateHudVisibility()
	local zone = player:GetAttribute("CurrentZone")
	local trainingStat = player:GetAttribute("TrainingStat")
	local visible = zone ~= "Sanctuary"
	local armTrainingVisible = visible or trainingStat == "Arm"
	local legTrainingVisible = visible or trainingStat == "Leg"

	attackButton.Visible = armTrainingVisible
	jumpButton.Visible = legTrainingVisible
	focusButton.Visible = legTrainingVisible
	areaButton.Visible = legTrainingVisible
end

updateHudVisibility()
player:GetAttributeChangedSignal("CurrentZone"):Connect(updateHudVisibility)
player:GetAttributeChangedSignal("TrainingStat"):Connect(updateHudVisibility)
player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(updateHudVisibility)