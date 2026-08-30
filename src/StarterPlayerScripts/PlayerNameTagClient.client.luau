-- LocalScript: PlayerNameTagClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt über JEDEM Charakter (auch anderen Spielern) ein Schild: oben die Stärke (gelb,
-- nur die Zahl), darunter der Spielername (weiß). Sitzt dynamisch über dem höchsten Punkt
-- des Charakters (nicht nur knapp über dem Kopf), damit es bei riesigen Skins nicht den
-- Kopf verdeckt. Blendet das Standard-Roblox-Namensschild aus, damit nichts doppelt erscheint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))

local NAME_TAG_MARGIN = 2.5 -- Studs Puffer über dem höchsten Punkt des Charakters

-- Positioniert das Schild dynamisch über dem tatsächlich höchsten Punkt des Charakters
-- (nicht fest über dem Kopf-Teil) -- wichtig, weil die Charaktergröße sich durch Training
-- laufend ändert.
local function updateBillboardOffset(character, billboard, head)
	local ok, cframe, size = pcall(function()
		return character:GetBoundingBox()
	end)
	if ok then
		local topY = cframe.Position.Y + size.Y / 2
		local offsetY = (topY - head.Position.Y) + NAME_TAG_MARGIN
		billboard.StudsOffset = Vector3.new(0, offsetY, 0)
	end
end

local function createNameTag(player, character)
	local head = character:WaitForChild("Head")

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.NameDisplayDistance = 0 -- Standard-Namensschild ausblenden
	end

	local existing = head:FindFirstChild("PlayerNameTag")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlayerNameTag"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 2000 -- großzügig, damit es unabhängig von Entfernung/Charaktergröße für alle sichtbar bleibt
	billboard.Parent = head

	updateBillboardOffset(character, billboard, head)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = billboard

	-- Stärke: oben, gelb -- nur die Zahl, ohne "Stärke:"-Präfix
	local strengthLabel = Instance.new("TextLabel")
	strengthLabel.Name = "StrengthLabel"
	strengthLabel.LayoutOrder = 1
	strengthLabel.Size = UDim2.new(1, 0, 0, 22)
	strengthLabel.BackgroundTransparency = 1
	strengthLabel.Font = Enum.Font.LuckiestGuy
	strengthLabel.TextScaled = true
	strengthLabel.TextColor3 = Color3.fromRGB(255, 220, 40)
	strengthLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	strengthLabel.TextStrokeTransparency = 0
	strengthLabel.Text = NumberFormat.Format(character:GetAttribute("Damage") or 0)
	strengthLabel.Parent = billboard

	-- Name: darunter (aber immer noch über dem Charakter), weiß
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.LayoutOrder = 2
	nameLabel.Size = UDim2.new(1, 0, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.Text = player.Name
	nameLabel.Parent = billboard

	character:GetAttributeChangedSignal("Damage"):Connect(function()
		strengthLabel.Text = NumberFormat.Format(character:GetAttribute("Damage") or 0)
		-- Stärke ändert sich oft zusammen mit der Charaktergröße (Training/Skin) ->
		-- Position gleich mit aktualisieren, damit es nicht in den Kopf hineinrutscht.
		updateBillboardOffset(character, billboard, head)
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		createNameTag(player, character)
	end)
	if player.Character then
		createNameTag(player, player.Character)
	end
end

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	onPlayerAdded(existingPlayer)
end
Players.PlayerAdded:Connect(onPlayerAdded)
