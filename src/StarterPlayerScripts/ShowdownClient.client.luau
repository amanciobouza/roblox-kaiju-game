-- LocalScript: ShowdownClient
-- Ort in Studio: StarterPlayer.StarterPlayerScripts
--
-- Die Anzeigeseite des Showdowns: Kamera, Filmstreifen, Steuerungsumstellung,
-- Aufgeben-Knopf. Ob ein Showdown läuft, entscheidet allein der Server (ShowdownService).
--
-- ===== Die Kameragrammatik =====
-- Die Kamera steht seitlich zur Verbindungslinie zwischen Spieler und Guardian, tief am
-- Boden -- man schaut den Riesen zu wie ein kleiner Mensch. Sie ist um 20 Grad schräg
-- gestellt: exakt seitlich wäre eine flache Bühnenansicht, schräg gibt Tiefe.
--
-- Sie überschreitet die Achse NIE. Das ist keine Geschmacksfrage: die Steuerung ist an
-- diese Achse gebunden, und ein Seitenwechsel würde links und rechts unter den Fingern
-- des Spielers vertauschen. Der Guardian steht deshalb IMMER rechts im Bild -- daraus
-- folgt die Kameraseite, und sie folgt der Achse, wenn die beiden umeinander laufen.
--
-- ===== Die Steuerung =====
-- Wie in einem Kampfspiel: links und rechts gehen auf den Guardian zu und von ihm weg,
-- vor und zurück bewegen in die Bildtiefe. Damit hängt die Bewegung nicht mehr an der
-- Blickrichtung der Kamera -- genau das macht die freie Kameraführung überhaupt möglich.
--
-- Umgesetzt wird das NICHT durch Abschalten der Standardsteuerung: die bringt auf
-- Mobilgeräten den Daumenstick mit, und ohne sie stünde dort gar keine Steuerung mehr da.
-- Stattdessen wird ihr Eingabevektor gelesen und die Bewegung danach neu gesetzt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ShowdownConfig = require(ReplicatedStorage:WaitForChild("ShowdownConfig"))
local CameraSessionUtils = require(ReplicatedStorage:WaitForChild("CameraSessionUtils"))
local LetterboxUtils = require(ReplicatedStorage:WaitForChild("LetterboxUtils"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local UiTypography = require(ReplicatedStorage:WaitForChild("UiTypography"))

-- WaitForChild statt GetOrCreate: GetOrCreate würde auf dem Client eine LOKALE Kopie
-- anlegen, wenn das Ereignis des Servers noch nicht repliziert ist -- FireServer ginge
-- dann ins Leere, ohne Fehlermeldung.
local ShowdownStateEvent = ReplicatedStorage:WaitForChild("ShowdownStateEvent", 30)
local ShowdownShotEvent = ReplicatedStorage:WaitForChild("ShowdownShotEvent", 30)
local ShowdownGiveUpEvent = ReplicatedStorage:WaitForChild("ShowdownGiveUpEvent", 30)

if not ShowdownStateEvent or not ShowdownShotEvent or not ShowdownGiveUpEvent then
	warn("[Kaiju-Debug] ShowdownClient: RemoteEvents nicht gefunden -- Showdown bleibt aus.")
	return
end

local camera = Workspace.CurrentCamera

-- ===== Zustand =====

local active = false
local cameraSessionId = nil
local guardianModel = nil
local startedAt = 0
local minimumDuration = ShowdownConfig.MinimumDuration

-- Die Kamera bleibt stehen, bis sich die Achse weit genug gedreht hat -- eine dauernd
-- mitgleitende Kamera wirkt wie ein Karussell.
local stagedPosition = nil
local stagedAxis = nil

-- Läuft gerade ein Angriffs-Shot? Dann führt er die Kamera statt der Ruhelage.
local activeShot = nil

local savedFieldOfView = nil
local hiddenGuis = {}
local letterbox = nil

-- Eingabe der Standardsteuerung. Über das PlayerModule erreichbar; wenn es fehlt, bleibt
-- die Steuerung eben normal -- besser als gar keine.
local controls = nil
do
	local ok, playerModule = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and playerModule then
		local gotControls, result = pcall(function()
			return playerModule:GetControls()
		end)
		if gotControls then
			controls = result
		end
	end
end
if not controls then
	warn("[Kaiju-Debug] ShowdownClient: PlayerModule nicht erreichbar -- Steuerung bleibt kameraralativ.")
end

-- ===== Hilfsgrössen =====

local function flatUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.001 then
		return Vector3.new(0, 0, 1)
	end
	return flat.Unit
end

local function characterParts()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character, root, humanoid
end

-- Höhe eines Modells aus seinem Hüllquader. Für die Kamerahöhe: zwischen Baby Kaiju und
-- Radiant Apex liegt Faktor sechs, ein fester Wert kann nicht für beide stimmen.
local function modelHeight(model)
	if not model then
		return 10
	end
	local ok, _, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and size then
		return size.Y
	end
	return 10
end

-- Die Kameraseite: der Guardian soll IMMER rechts im Bild stehen. Aus dieser Forderung
-- folgt die Blickrichtung eindeutig -- und damit, dass die Achse nie überschritten wird.
--
-- Rechtsvektor einer Kamera ist blick × oben. Soll der Rechtsvektor die Achse sein, ergibt
-- sich der Blick als die um 90 Grad gedrehte Achse.
local function lookDirectionFor(axis)
	return Vector3.new(axis.Z, 0, -axis.X)
end

local function obliqueRotation()
	return CFrame.Angles(0, math.rad(ShowdownConfig.Camera.ObliqueAngle), 0)
end

-- Wo die Ruhekamera stehen soll, gemessen an der aktuellen Lage der beiden.
local function restingPosition(playerPosition, guardianPosition)
	local axis = flatUnit(guardianPosition - playerPosition)
	local midpoint = (playerPosition + guardianPosition) / 2
	local separation = (guardianPosition - playerPosition).Magnitude

	local tallest = math.max(modelHeight(player.Character), modelHeight(guardianModel))
	local height = math.max(tallest * ShowdownConfig.Camera.HeightFactor, ShowdownConfig.Camera.MinHeight)
	local distance = math.max(separation * ShowdownConfig.Camera.DistanceFactor, ShowdownConfig.Camera.MinDistance)

	local look = obliqueRotation():VectorToWorldSpace(lookDirectionFor(axis))
	local position = midpoint - look * distance + Vector3.new(0, height, 0)
	return position, midpoint, axis
end

-- ===== HUD =====

local function setHudHidden(hidden)
	if hidden then
		for _, guiName in ipairs(ShowdownConfig.HiddenGuis) do
			local gui = playerGui:FindFirstChild(guiName)
			if gui and gui.Enabled then
				gui.Enabled = false
				table.insert(hiddenGuis, gui)
			end
		end
		local gameHud = playerGui:FindFirstChild("GameHud")
		if gameHud then
			for _, childName in ipairs(ShowdownConfig.HiddenHudChildren) do
				local child = gameHud:FindFirstChild(childName)
				if child and child.Visible then
					child.Visible = false
					table.insert(hiddenGuis, child)
				end
			end
		end
	else
		for _, instance in ipairs(hiddenGuis) do
			if instance and instance.Parent then
				if instance:IsA("ScreenGui") then
					instance.Enabled = true
				else
					instance.Visible = true
				end
			end
		end
		hiddenGuis = {}
	end
end

-- ===== Aufgeben-Knopf =====
-- Oben am Bildrand, weit weg von den Angriffsknöpfen: im Eifer eines Bosskampfs trifft
-- man Knöpfe, die man nicht treffen wollte, und ein versehentliches Aufgeben nimmt dem
-- Spieler genau den Moment weg, auf den alles hinauslief. Deshalb auch: gedrückt halten.

local giveUpGui = Instance.new("ScreenGui")
giveUpGui.Name = "ShowdownGiveUpGui"
giveUpGui.ResetOnSpawn = false
giveUpGui.IgnoreGuiInset = true
giveUpGui.DisplayOrder = 45
giveUpGui.Enabled = false
giveUpGui.Parent = playerGui

local giveUpButton = Instance.new("TextButton")
giveUpButton.Name = "GiveUpButton"
giveUpButton.AnchorPoint = Vector2.new(0.5, 0)
giveUpButton.Size = UDim2.new(0, 200, 0, 40)
giveUpButton.BackgroundColor3 = Color3.fromRGB(52, 52, 62)
giveUpButton.AutoButtonColor = false
giveUpButton.TextColor3 = Color3.fromRGB(235, 235, 245)
giveUpButton.Text = "Hold to retreat"
giveUpButton.Visible = false
giveUpButton.Parent = giveUpGui
ComicStyleUtils.Apply(giveUpButton, 10, 2)
UiTypography.Body(giveUpButton, 15)

-- Der Fortschrittsbalken des Haltens. Ohne ihn wüsste niemand, dass gehalten werden muss.
local giveUpFill = Instance.new("Frame")
giveUpFill.Name = "HoldFill"
giveUpFill.Size = UDim2.new(0, 0, 1, 0)
giveUpFill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
giveUpFill.BackgroundTransparency = 0.4
giveUpFill.BorderSizePixel = 0
giveUpFill.ZIndex = 0
giveUpFill.Parent = giveUpButton

local giveUpHoldStart = nil

local function positionGiveUpButton()
	-- Unterhalb der oberen Filmstreifen-Kante, sonst läge er halb darunter.
	local barHeight = camera.ViewportSize.Y * ShowdownConfig.Letterbox.BarHeightFraction
	giveUpButton.Position = UDim2.new(0.5, 0, 0, math.floor(barHeight) + 12)
end

giveUpButton.MouseButton1Down:Connect(function()
	giveUpHoldStart = os.clock()
end)

local function cancelHold()
	giveUpHoldStart = nil
	giveUpFill.Size = UDim2.new(0, 0, 1, 0)
end

giveUpButton.MouseButton1Up:Connect(cancelHold)
giveUpButton.MouseLeave:Connect(cancelHold)

-- ===== Kamerafahrten der Angriffs-Shots =====
-- Jeder Shot schneidet HART hinein und fährt WEICH zurück: der Schnitt gibt dem Angriff
-- den Schlag, die Rückfahrt nimmt dem Ganzen das Hektische.
--
-- Alle Shots werden aus der Kameraseite heraus gebaut (seitwärts = Achse um 90 Grad
-- gedreht), damit auch sie die Achse nicht überschreiten.

local function partPosition(model, partName, fallback)
	if model and partName then
		local part = model:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			return part.Position
		end
	end
	return fallback
end

local function shotCFrame(shotName, shot)
	local _, root = characterParts()
	local guardianRoot = guardianModel and guardianModel.PrimaryPart
	if not root or not guardianRoot then
		return nil
	end

	local axis = flatUnit(guardianRoot.Position - root.Position)
	local sideways = lookDirectionFor(axis) -- zeigt von der Kameraseite zur Achse

	if shot.source == "Player" then
		local origin = partPosition(player.Character, shot.originPart, root.Position)
		if shot.style == "BeamTravel" then
			-- Am Strahl entlang: die Kamera startet dicht am Austritt und fährt bis kurz
			-- vor das Ziel. Sie bleibt dabei seitlich versetzt, sonst schaute sie in den
			-- Strahl statt an ihm entlang.
			local target = partPosition(guardianModel, "ChestCore", guardianRoot.Position)
			local startPos = origin - axis * 12 - sideways * 14 + Vector3.new(0, 4, 0)
			local endPos = target - axis * 26 - sideways * 18 + Vector3.new(0, 6, 0)
			return CFrame.lookAt(startPos, origin + axis * 20), CFrame.lookAt(endPos, target)
		end
		-- LowRise: tief am Boden neben dem Spieler, während die Ladung wächst.
		local low = origin - sideways * 22 - axis * 8 + Vector3.new(0, 3, 0)
		return CFrame.lookAt(low, origin + Vector3.new(0, 6, 0))
	end

	-- Guardian-Shots: von unten an die Mündung. Der Blick nach oben ist das, was den
	-- Guardian gross macht -- von Augenhöhe wirkt er wie eine Statue.
	local origin = partPosition(guardianModel, shot.originPart, guardianRoot.Position)
	if shot.style == "LaunchLow" then
		local low = origin - sideways * 30 + axis * 10 - Vector3.new(0, math.max(modelHeight(guardianModel) * 0.4, 12), 0)
		return CFrame.lookAt(low, origin + Vector3.new(0, 18, 0))
	elseif shot.style == "MuzzleClose" then
		local close = origin - sideways * 16 + axis * 6 + Vector3.new(0, -2, 0)
		return CFrame.lookAt(close, origin - axis * 12)
	end
	-- ChestLow
	local below = origin - sideways * 20 - Vector3.new(0, math.max(modelHeight(guardianModel) * 0.35, 10), 0)
	return CFrame.lookAt(below, origin)
end

-- ===== Kameraschleife =====

local RENDER_NAME = "ShowdownCamera"

local function stopCameraLoop()
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
end

local function startCameraLoop()
	local sessionId = cameraSessionId
	local entryStarted = os.clock()
	local entryFrom = camera.CFrame

	stopCameraLoop()
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		-- Session-Prüfung: übernimmt ein anderes Kamerasystem, steigt diese Schleife
		-- sofort aus. Ohne das entstehen die Flacker- und Sprungfehler, vor denen
		-- CLAUDE.md warnt.
		if not CameraSessionUtils.IsCurrent(sessionId) or not active then
			stopCameraLoop()
			return
		end

		local _, root = characterParts()
		local guardianRoot = guardianModel and guardianModel.PrimaryPart
		if not root or not guardianRoot then
			return
		end

		local position, midpoint, axis = restingPosition(root.Position, guardianRoot.Position)

		-- Neu aufstellen erst ab der Schwelle: bis dahin bleibt die Kamera stehen und
		-- schwenkt nur mit -- wie ein Kameramann, der ein paar Schritte zur Seite geht,
		-- statt dauernd mitzulaufen.
		if not stagedPosition or not stagedAxis then
			stagedPosition, stagedAxis = position, axis
		else
			local dot = math.clamp(stagedAxis:Dot(axis), -1, 1)
			if math.deg(math.acos(dot)) > ShowdownConfig.Camera.RestageThresholdDegrees then
				stagedPosition, stagedAxis = position, axis
			end
		end

		local restingCFrame = CFrame.lookAt(stagedPosition, midpoint)

		if activeShot then
			local elapsed = os.clock() - activeShot.startedAt
			if elapsed >= activeShot.duration then
				-- Weiche Rückfahrt in die Ruhelage.
				local returnAlpha = math.clamp(
					(elapsed - activeShot.duration) / ShowdownConfig.Camera.RestageDuration, 0, 1)
				camera.CFrame = activeShot.finish:Lerp(restingCFrame, returnAlpha)
				if returnAlpha >= 1 then
					activeShot = nil
				end
				return
			end
			local alpha = activeShot.duration > 0 and math.clamp(elapsed / activeShot.duration, 0, 1) or 1
			camera.CFrame = activeShot.start:Lerp(activeShot.finish, alpha)
			return
		end

		-- Einfahrt beim Start: die Steuerung ist dabei schon aktiv, damit sich der
		-- Übergang nicht nach Unterbrechung anfühlt.
		local entryAlpha = math.clamp(
			(os.clock() - entryStarted) / ShowdownConfig.Camera.EntryDuration, 0, 1)
		if entryAlpha < 1 then
			-- Weich beginnen und weich enden, sonst ruckt die Fahrt an.
			local eased = TweenService:GetValue(entryAlpha, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			camera.CFrame = entryFrom:Lerp(restingCFrame, eased)
		else
			camera.CFrame = restingCFrame
		end
	end)
end

-- ===== Steuerung =====

local MOVE_NAME = "ShowdownMove"

local function stopMoveLoop()
	pcall(function()
		RunService:UnbindFromRenderStep(MOVE_NAME)
	end)
end

local function startMoveLoop()
	local sessionId = cameraSessionId
	stopMoveLoop()
	-- NACH der Standardsteuerung: beide setzen die Bewegungsrichtung, und der letzte
	-- Schreiber gewinnt. Deshalb eine Stufe hinter der Kamera.
	RunService:BindToRenderStep(MOVE_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		if not CameraSessionUtils.IsCurrent(sessionId) or not active or not controls then
			stopMoveLoop()
			return
		end
		local _, root, humanoid = characterParts()
		local guardianRoot = guardianModel and guardianModel.PrimaryPart
		if not root or not humanoid or not guardianRoot then
			return
		end

		local input = controls:GetMoveVector()
		if input.Magnitude < 0.05 then
			return -- nichts überschreiben, wenn nichts gedrückt wird
		end

		-- Bildschirm-waagerecht ist die Achse: rechts geht auf den Guardian zu (er steht
		-- immer rechts im Bild), links davon weg.
		local towardGuardian = flatUnit(guardianRoot.Position - root.Position)
		-- Bildschirm-tiefe: vorwärts geht ins Bild hinein, rückwärts zur Kamera.
		local intoScreen = flatUnit(camera.CFrame.LookVector)

		local direction = towardGuardian * input.X + intoScreen * (-input.Z)
		if direction.Magnitude > 1 then
			direction = direction.Unit
		end
		humanoid:Move(direction, false)
	end)
end

-- ===== Start und Ende =====

local function beginShowdown(info)
	active = true
	guardianModel = info.guardian
	startedAt = os.clock()
	minimumDuration = info.minimumDuration or ShowdownConfig.MinimumDuration
	stagedPosition, stagedAxis, activeShot = nil, nil, nil

	cameraSessionId = CameraSessionUtils.Start("Showdown")
	camera.CameraType = Enum.CameraType.Scriptable
	savedFieldOfView = camera.FieldOfView
	camera.FieldOfView = ShowdownConfig.Camera.FieldOfView

	-- Der Berserker-FOV-Puls würde jede Bildkomposition unterlaufen -- und im Showdown ist
	-- der Spieler oft im Berserker-Zustand, weil er gerade viel Schaden macht. Das wäre
	-- also nicht die Ausnahme, sondern der Normalfall.
	player:SetAttribute("ShowdownActive", true)

	if not letterbox then
		letterbox = LetterboxUtils.Create(playerGui, "ShowdownLetterboxGui", {
			heightFraction = ShowdownConfig.Letterbox.BarHeightFraction,
			fadeDuration = ShowdownConfig.Letterbox.FadeDuration,
		})
	end
	letterbox.SetVisible(true)

	setHudHidden(true)
	positionGiveUpButton()
	giveUpGui.Enabled = true
	giveUpButton.Visible = false
	cancelHold()

	startCameraLoop()
	startMoveLoop()

	print(string.format("[Kaiju-Debug] Showdown-Kamera übernommen (Mindestdauer %.0fs).", minimumDuration))
end

local function finishShowdown(info)
	if not active then
		return
	end
	active = false
	stopMoveLoop()

	local victory = info and info.victory == true
	local holdDuration = victory
		and ShowdownConfig.Camera.VictoryShotDuration
		or ShowdownConfig.Camera.ExitDuration

	giveUpGui.Enabled = false
	cancelHold()

	-- Beim Sieg bleibt die Kamera stehen und schaut zu, wie der Guardian fällt -- er ist
	-- der Höhepunkt der gesamten Alarmstufen-Eskalation. Bei den anderen Ausgängen wird
	-- gleich zurückgegeben.
	task.delay(holdDuration, function()
		stopCameraLoop()
		if letterbox then
			letterbox.SetVisible(false)
		end
		setHudHidden(false)
		player:SetAttribute("ShowdownActive", nil)

		if savedFieldOfView then
			camera.FieldOfView = savedFieldOfView
			savedFieldOfView = nil
		end
		camera.CameraType = Enum.CameraType.Custom
		local _, _, humanoid = characterParts()
		if humanoid then
			camera.CameraSubject = humanoid
		end
		if cameraSessionId then
			CameraSessionUtils.Release(cameraSessionId)
			cameraSessionId = nil
		end
		guardianModel = nil
	end)

	print(string.format(
		"[Kaiju-Debug] Showdown beendet (%s) -- Kamera kehrt in %.1fs zurück.",
		info and info.reason or "?", holdDuration))
end

ShowdownStateEvent.OnClientEvent:Connect(function(isActive, info)
	if isActive then
		beginShowdown(info or {})
	else
		finishShowdown(info)
	end
end)

ShowdownShotEvent.OnClientEvent:Connect(function(shotName, model)
	if not active then
		return
	end
	local shot = ShowdownConfig.Shots[shotName]
	if not shot then
		return
	end
	if model then
		guardianModel = model
	end
	local startCFrame, endCFrame = shotCFrame(shotName, shot)
	if not startCFrame then
		return
	end
	activeShot = {
		startedAt = os.clock(),
		duration = shot.duration,
		start = startCFrame,
		-- Ohne zweite Lage steht der Shot still. Das ist für die kurzen Guardian-Shots
		-- gewollt; nur der Strahl fährt tatsächlich.
		finish = endCFrame or startCFrame,
	}
end)

-- ===== Laufende Kleinarbeit: Knopf einblenden und Halten auswerten =====

RunService.Heartbeat:Connect(function()
	if not active then
		return
	end

	-- Der Knopf erscheint still bei Ablauf der Mindestdauer. Kein Countdown: der sagt dem
	-- Spieler "warte auf den Ausgang", und das ist die falsche Aufmerksamkeit in einem
	-- Bosskampf.
	if not giveUpButton.Visible and os.clock() - startedAt >= minimumDuration then
		giveUpButton.Visible = true
		positionGiveUpButton()
	end

	if giveUpHoldStart then
		local held = os.clock() - giveUpHoldStart
		giveUpFill.Size = UDim2.new(math.clamp(held / ShowdownConfig.GiveUpHoldTime, 0, 1), 0, 1, 0)
		if held >= ShowdownConfig.GiveUpHoldTime then
			cancelHold()
			ShowdownGiveUpEvent:FireServer()
		end
	end
end)

-- Berührung auf Mobilgeräten löst MouseButton1Up nicht immer aus, wenn der Finger den
-- Knopf verlässt -- ohne das bliebe der Haltezähler stehen und löste später versehentlich aus.
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		cancelHold()
	end
end)

-- ===== Debug: Shot per Taste =====
-- Das Debug-Panel ist waehrend eines Showdowns ausgeblendet -- so gewuenscht, aber damit
-- waere ausgerechnet der Schalter unerreichbar, den man am haeufigsten braucht. F8 blaettert
-- deshalb durch die Shots und loest sie aus, solange ein Showdown laeuft.
local DEBUG_SHOT_NAMES = { "FocusLaser", "AreaAttack", "WarningPulse", "ContainmentNet", "ShoulderMissiles" }
local debugShotIndex = 0
local DebugShowdownEvent = ReplicatedStorage:WaitForChild("DebugShowdownEvent", 30)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.F8 or not active or not DebugShowdownEvent then
		return
	end
	debugShotIndex = debugShotIndex % #DEBUG_SHOT_NAMES + 1
	local shotName = DEBUG_SHOT_NAMES[debugShotIndex]
	print("[Kaiju-Debug] F8: Showdown-Shot " .. shotName .. " angefordert.")
	DebugShowdownEvent:FireServer("Shot", shotName)
end)

print("[Kaiju] ShowdownClient bereit.")
