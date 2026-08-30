-- VERSION: 2026-08-25 #1 (RemoteEventUtils-Umstellung)
-- LocalScript: DamagePopupClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt eine Schadenszahl über dem eigenen Charakter, wenn ein Treffer gelandet ist.
-- Die Zahl schwebt kurz nach oben und verblasst dann.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local ShowDamageEvent = RemoteEventUtils.GetOrCreate("ShowDamageEvent")
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))
local camera = workspace.CurrentCamera

-- Kurzes Kamerawackeln beim Finisher (dritter Combo-Schlag) -- macht den Treffer auch im
-- echten Kampf spürbar, nicht nur beim Training am Titan Impact Gauntlet.
local SHAKE_DURATION = 0.25
local SHAKE_AMPLITUDE = 0.35

local function shakeCamera()
	local startTime = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= SHAKE_DURATION then
			connection:Disconnect()
			return
		end
		local falloff = 1 - (elapsed / SHAKE_DURATION) -- klingt zum Ende hin ab
		local offset = Vector3.new(
			(math.random() - 0.5) * SHAKE_AMPLITUDE * falloff,
			(math.random() - 0.5) * SHAKE_AMPLITUDE * falloff,
			0
		)
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end)
end

local FLOAT_DURATION = 1 -- Sekunden, die die Zahl nach oben schwebt/verblasst
local FLOAT_DISTANCE = 12 -- Studs, um die die Zahl nach oben wandert

-- Muss zum Namens-Tag (PlayerNameTagClient.lua) passen: dort sitzt das Schild bei
-- (höchster Punkt des Charakters + NAME_TAG_MARGIN). Die Schadenszahlen sollen NOCH
-- WEITER oben starten, damit sie sich nie mit Name/Stärke überlappen -- deshalb hier
-- zusätzlich die geschätzte Höhe des Namens-Tags selbst draufrechnen.
local NAME_TAG_MARGIN = 2.5
local NAME_TAG_HEIGHT_ESTIMATE = 2 -- ungefähre World-Space-Höhe von Stärke+Name übereinander
local POPUP_BASE_CLEARANCE = NAME_TAG_MARGIN + NAME_TAG_HEIGHT_ESTIMATE + 0.5 -- zusätzlicher Puffer

-- Zählt, wie viele Schadenszahlen gerade GLEICHZEITIG sichtbar sind, damit neue Zahlen
-- sich sichtbar auffächern (horizontal + leicht versetzt in der Höhe), statt bei mehreren
-- gleichzeitigen Treffern (z.B. Flächenschaden trifft mehrere Häuser) exakt übereinander
-- zu liegen und wie eine einzelne, dickere Zahl auszusehen.
local activePopupSlots = 0

local function showDamagePopup(amount, isFinisher)
	local character = player.Character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	-- Höhe des Charakters selbst ermitteln (wie beim Namens-Tag), damit die Basis-Höhe
	-- der Schadenszahlen bei großen/kleinen Skins automatisch mitwächst/-schrumpft.
	local baseClearance = POPUP_BASE_CLEARANCE
	local ok, cframe, size = pcall(function()
		return character:GetBoundingBox()
	end)
	if ok then
		local topY = cframe.Position.Y + size.Y / 2
		baseClearance = (topY - head.Position.Y) + POPUP_BASE_CLEARANCE
	end

	local slot = activePopupSlots
	activePopupSlots += 1

	-- Fächert bis zu 5 gleichzeitige Zahlen sichtbar auseinander (horizontal + Höhe),
	-- darüber hinaus wiederholt sich das Muster mit kleiner Zufalls-Streuung obendrauf.
	local fanIndex = slot % 5
	local horizontalOffset = (fanIndex - 2) * 1.4 + (math.random(-15, 15) / 100)
	local verticalOffset = baseClearance + (fanIndex % 3) * 0.7
	local startOffset = Vector3.new(horizontalOffset, verticalOffset, 0)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamagePopup"
	-- Finisher-Treffer (dritter Combo-Schlag): deutlich größere Anzeige, wie im Training
	billboard.Size = isFinisher and UDim2.new(0, 150, 0, 60) or UDim2.new(0, 100, 0, 40)
	billboard.StudsOffset = startOffset
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	-- Finisher: warmes Orange statt Rot, passend zur PunchAll-Combo-Farbe
	label.TextColor3 = isFinisher and Color3.fromRGB(255, 140, 30) or Color3.fromRGB(255, 90, 90)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Text = "-" .. NumberFormat.Format(amount) .. (isFinisher and " 🔥" or "")
	label.Parent = billboard

	if isFinisher then
		shakeCamera()
	end

	local tweenInfo = TweenInfo.new(FLOAT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(billboard, tweenInfo, { StudsOffset = startOffset + Vector3.new(0, FLOAT_DISTANCE, 0) }):Play()
	TweenService:Create(label, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	task.delay(FLOAT_DURATION, function()
		billboard:Destroy()
		activePopupSlots = math.max(activePopupSlots - 1, 0)
	end)
end

ShowDamageEvent.OnClientEvent:Connect(showDamagePopup)