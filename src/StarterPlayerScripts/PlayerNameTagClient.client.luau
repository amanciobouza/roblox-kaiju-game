-- LocalScript: PlayerNameTagClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt über JEDEM Charakter (auch anderen Spielern) ein Schild: oben die Stärke (gelb,
-- nur die Zahl), darunter der Spielername (weiß). Sitzt dynamisch über dem höchsten Punkt
-- des Charakters (nicht nur knapp über dem Kopf), damit es bei riesigen Skins nicht den
-- Kopf verdeckt. Blendet das Standard-Roblox-Namensschild aus, damit nichts doppelt erscheint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))
-- Nur fuer das Faust-Symbol neben der Staerke (siehe dort).
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

-- Das Gelb der Staerke. Es stand zweimal im Code, seit Symbol und Zahl es teilen -- und
-- zwei Stellen fuer eine Farbe sind eine Stelle zu viel.
local STRENGTH_COLOR = Color3.fromRGB(255, 220, 40)

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
--
-- Bezug ist die HumanoidRootPart und nicht der Kopf. Der Kopf WIPPT mit der Animation, und
-- das Schild wippte mit -- bei einer sechsfach skalierten Figur schwingt derselbe Ausschlag
-- eben sechsmal so weit, und aus einem Nicken wird ein Ruckeln. Die Wurzel bewegt sich
-- nicht: sie ist der Punkt, um den die Animation die Gliedmassen bewegt.
local function updateBillboardOffset(character, billboard, bezug)
	local ok, cframe, size = pcall(function()
		return character:GetBoundingBox()
	end)
	if ok and bezug.Parent then
		local topY = cframe.Position.Y + size.Y / 2
		local margin = math.max(NAME_TAG_MARGIN_MIN, size.Y * NAME_TAG_MARGIN_SHARE)
		local offsetY = (topY - bezug.Position.Y) + margin
		billboard.StudsOffset = Vector3.new(0, offsetY, 0)
	end
end

local function createNameTag(player, character)
	local head = character:WaitForChild("Head")
	-- Mit Zeitgrenze: fehlt die Wurzel, haengt dieses Skript sonst stumm und der Spieler
	-- haette gar kein Schild. Dann lieber am Kopf haengen -- wackelig ist besser als weg.
	local bezug = character:WaitForChild("HumanoidRootPart", 5) or head

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.NameDisplayDistance = 0 -- Standard-Namensschild ausblenden
	end

	-- Auch am Kopf nachsehen: dort hing das Schild frueher, und eine Figur, die den
	-- Wechsel ueberlebt hat, traegt sonst zwei.
	for _, ort in ipairs({ bezug, head }) do
		local existing = ort:FindFirstChild("PlayerNameTag")
		if existing then
			existing:Destroy()
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlayerNameTag"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 2000 -- großzügig, damit es unabhängig von Entfernung/Charaktergröße für alle sichtbar bleibt
	billboard.Parent = bezug

	updateBillboardOffset(character, billboard, bezug)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = billboard

	-- ===== Stärke: oben, gelb -- jetzt mit Faust davor =====
	-- Die blosse Zahl sagte nicht, WAS sie zählt (gemeldet am 15.10.2026). Davor steht
	-- deshalb die Faust -- dasselbe Symbol, das im HUD den Nahangriff trägt. Das ist keine
	-- Zierde, sondern genau die Aussage: die Zahl ist das Attribut "Damage", also der
	-- Schaden eines Schlags.
	--
	-- Ein Symbol und kein Emoji: ein Emoji zeichnet das Betriebssystem in seinem eigenen
	-- bunten Stil, und aus demselben Grund sind die Emoji im ganzen HUD schon durch Symbole
	-- ersetzt worden.
	--
	-- Die Zeile ist ein eigener Container, weil das Schild senkrecht gestapelt ist (Stärke
	-- über Name) und Symbol und Zahl waagrecht nebeneinander gehören.
	local strengthRow = Instance.new("Frame")
	strengthRow.Name = "StrengthRow"
	strengthRow.LayoutOrder = 1
	strengthRow.Size = UDim2.new(1, 0, 0, 22)
	strengthRow.BackgroundTransparency = 1
	strengthRow.Parent = billboard

	local strengthRowLayout = Instance.new("UIListLayout")
	strengthRowLayout.FillDirection = Enum.FillDirection.Horizontal
	strengthRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	strengthRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	strengthRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	strengthRowLayout.Padding = UDim.new(0, 4)
	strengthRowLayout.Parent = strengthRow

	-- Dieselbe Farbe wie die Zahl: die beiden sind EINE Aussage, nicht zwei nebeneinander.
	local strengthIcon = HudChrome.IconImage(strengthRow, HudChrome.Icon.Punch, STRENGTH_COLOR)
	strengthIcon.Name = "StrengthIcon"
	strengthIcon.LayoutOrder = 1
	strengthIcon.Size = UDim2.fromOffset(20, 20)

	local strengthLabel = Instance.new("TextLabel")
	strengthLabel.Name = "StrengthLabel"
	strengthLabel.LayoutOrder = 2
	-- AutomaticSize statt voller Breite: nur so steht die Zahl direkt neben dem Symbol
	-- statt mittig in einer Zeile, die das Symbol an den Rand drückt. Damit entfällt
	-- TextScaled -- es braucht eine feste Grösse, um die Breite berechnen zu können.
	strengthLabel.AutomaticSize = Enum.AutomaticSize.X
	strengthLabel.Size = UDim2.new(0, 0, 1, 0)
	strengthLabel.BackgroundTransparency = 1
	strengthLabel.Font = Enum.Font.LuckiestGuy
	strengthLabel.TextSize = 22
	strengthLabel.TextColor3 = STRENGTH_COLOR
	strengthLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	strengthLabel.TextStrokeTransparency = 0
	strengthLabel.Text = NumberFormat.Format(character:GetAttribute("Damage") or 0)
	strengthLabel.Parent = strengthRow

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
		updateBillboardOffset(character, billboard, bezug)
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
				updateBillboardOffset(character, billboard, bezug)
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
