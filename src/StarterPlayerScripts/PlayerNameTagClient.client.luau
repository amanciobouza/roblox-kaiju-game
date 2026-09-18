-- LocalScript: PlayerNameTagClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt über JEDEM Charakter (auch anderen Spielern) ein Schild: oben die Stärke (gelb,
-- nur die Zahl), darunter der Spielername (weiß). Sitzt dynamisch über dem höchsten Punkt
-- des Charakters (nicht nur knapp über dem Kopf), damit es bei riesigen Skins nicht den
-- Kopf verdeckt. Blendet das Standard-Roblox-Namensschild aus, damit nichts doppelt erscheint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))

-- Abstand über dem höchsten Punkt der Figur.
--
-- Nicht fest, sondern ein Anteil ihrer Höhe: 2.5 Studs sind über einem normalen Avatar ein
-- deutlicher Abstand und über einem hundert Studs hohen Kaiju ein Hauch. Das Schild klebte
-- dadurch auf den Hörnern.
local NAME_TAG_MARGIN_MIN = 2.5
local NAME_TAG_MARGIN_SHARE = 0.10 -- Anteil der Figurenhöhe

-- Positioniert das Schild dynamisch über dem tatsächlich höchsten Punkt des Charakters
-- (nicht fest über dem Kopf-Teil) -- wichtig, weil die Charaktergröße sich durch Training,
-- Stufenwechsel UND das angezogene Kaiju-Modell laufend ändert.
local function updateBillboardOffset(character, billboard, head)
	local ok, cframe, size = pcall(function()
		return character:GetBoundingBox()
	end)
	if ok and head.Parent then
		local topY = cframe.Position.Y + size.Y / 2
		local margin = math.max(NAME_TAG_MARGIN_MIN, size.Y * NAME_TAG_MARGIN_SHARE)
		local offsetY = (topY - head.Position.Y) + margin
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

	-- ===== Und wenn die Figur ein Modell dazubekommt =====
	-- Das Kaiju-Modell wird erst nach dem Charakter angezogen (siehe KaijuStageOneService)
	-- und ist um ein Vielfaches höher als der Avatar darunter. Bis hierhin wurde die Höhe
	-- NUR bei einer Änderung von "Damage" neu gemessen -- das Anziehen ändert die aber
	-- nicht, und das Schild blieb auf Avatarhöhe stehen, also mitten im Körper.
	--
	-- Ein Modell kommt als direktes Kind der Figur dazu und verschwindet genauso wieder.
	-- Gemessen wird erst im nächsten Durchlauf: beim Auslösen ist das Modell zwar da, seine
	-- Teile sind aber noch nicht alle eingehängt, und der Hüllquader wäre zu klein.
	local ausstehend = false
	local function spaeterMessen()
		if ausstehend then
			return
		end
		ausstehend = true
		task.defer(function()
			ausstehend = false
			if character.Parent then
				updateBillboardOffset(character, billboard, head)
			end
		end)
	end

	character.ChildAdded:Connect(spaeterMessen)
	character.ChildRemoved:Connect(spaeterMessen)
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
