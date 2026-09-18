-- VERSION: 2026-09-12 #1
-- LocalScript: LevelUpFeedbackClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Rueckmeldung beim Stufenaufstieg: ein Klang und eine kurze goldene Aura an der Figur.
-- Bis hierher war der Aufstieg nur am Zahlenfeld und am kurzen Aufblitzen des XP-Balkens
-- zu erkennen (SkinSelectionGui) -- also genau dort, wo man beim Zerstoeren gerade nicht
-- hinsieht. Die Aura setzt das Ereignis dorthin, wo der Blick ohnehin ist: auf die Figur.
--
-- Der Server schickt nur "Spieler X ist auf Stufe N" (LevelUpEvent, siehe PlayerSetup).
-- Alles Sichtbare entsteht hier lokal -- gleiche Aufteilung wie bei der Berserker-Aura.
-- Die Aura laeuft fuer JEDE Figur, der Klang nur fuer den eigenen Spieler: die Belohnung
-- gehoert dem, der aufgestiegen ist, die anderen sollen es nur sehen.
--
-- Vier Ebenen, alle einmalig (keine Dauerwirkung wie beim Berserk):
--   1. Stoss    -- goldene Funken schiessen an der Figur hoch, dichter Anfangsschub
--   2. Glut     -- Highlight um die ganze Figur, blendet ueber ~3s wieder aus
--   3. Licht    -- PointLight, faellt mit der Glut zusammen ab
--   4. Ring     -- ein flacher Ring am Boden, der einmal nach aussen laeuft
--
-- Der Groessen-Pop gehoert dazu, laeuft aber serverseitig -- siehe unten, "Ebene 5".
--
-- Dazu tritt die Hintergrundmusik kurz zurueck (_G.DuckBackgroundMusic), sonst geht die
-- Fanfare in ihr unter.
--
-- Alle Groessen haengen an character:GetScale(): die Figur waechst mit den Skins auf das
-- bis zu Sechsfache. Feste Studwerte waeren am Anfang eine Explosion und spaeter ein
-- Glimmen an den Fuessen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local LevelUpEvent = RemoteEventUtils.GetOrCreate("LevelUpEvent")
local localPlayer = Players.LocalPlayer

local LEVEL_UP_SOUND_ID = "rbxassetid://9095193253"
local SOUND_VOLUME = 0.7

local GOLD = Color3.fromRGB(255, 190, 60)
local GOLD_BRIGHT = Color3.fromRGB(255, 244, 190)

local BURST_PARTICLES = 26 -- Anfangsschub pro Emitter
local EMIT_SECONDS = 2.2 -- so lange steigen danach noch Funken nach
local GLOW_SECONDS = 3.0 -- Highlight + Licht blenden ueber diese Zeit aus
-- Der Bodenring bleibt kurz: er ist der EINSCHLAG, nicht die Aura. Zoege man ihn mit in
-- die Länge, liefe er nur langsamer und weiter nach aussen -- aus einem Schlag würde ein
-- Kreis, der davonschwimmt.
local RING_SECONDS = 0.7

local MUSIC_DUCK_SECONDS = 1.3 -- so lange bleibt die Musik zurueckgenommen


-- Koerperteile, an denen Funken entstehen. FindFirstChild pro Name, fehlende werden
-- uebersprungen -- deckt R15 (UpperTorso/Hand/Foot) und R6 (Torso) mit einer Liste ab.
local EMITTER_PARTS = {
	"HumanoidRootPart",
	"UpperTorso",
	"Torso",
	"LeftHand",
	"RightHand",
	"LeftFoot",
	"RightFoot",
}

local levelUpSound = Instance.new("Sound")
levelUpSound.Name = "LevelUpSound"
levelUpSound.SoundId = LEVEL_UP_SOUND_ID
levelUpSound.Volume = SOUND_VOLUME
levelUpSound.Parent = SoundService

-- Laeuft die Feier an dieser Figur gerade? Zwei Aufstiege kurz hintereinander (oder der
-- Debug-Regler, der beim Ziehen laufend feuert) sollen keine Auren stapeln.
local running = {}

local function getScale(character)
	local ok, scale = pcall(function()
		return character:GetScale()
	end)
	if ok and type(scale) == "number" and scale > 0 then
		return scale
	end
	return 1
end

-- ===== Ebene 1: Funken, die an der Figur hochsteigen =====
local function createSparkEmitter(part, scale)
	local attachment = Instance.new("Attachment")
	attachment.Name = "LevelUpAttachment"
	attachment.Parent = part

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "LevelUpSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(GOLD_BRIGHT, GOLD)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.6, 1.0)
	sparks.Rate = 22
	sparks.Speed = NumberRange.new(6 * scale, 11 * scale)
	-- Enger Kegel nach oben: die Energie STEIGT an der Figur hoch. Ein voller
	-- Streuwinkel wuerde nach allen Seiten wegspritzen und wie ein Treffer wirken.
	sparks.SpreadAngle = Vector2.new(22, 22)
	sparks.Acceleration = Vector3.new(0, 9 * scale, 0)
	sparks.LightEmission = 1
	sparks.Parent = attachment

	return { attachment = attachment, sparks = sparks }
end

-- ===== Ebene 4: Ring am Boden, laeuft einmal nach aussen =====
local function playGroundRing(character, scale)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Fusshoehe statt fester Abstand: die Figur haengt je nach Skin unterschiedlich hoch
	-- ueber dem Boden (HipHeight), ein fester Versatz laege mal im Boden, mal darueber.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local footY = rootPart.Position.Y - rootPart.Size.Y / 2 - (humanoid and humanoid.HipHeight or 0)

	local ring = Instance.new("Part")
	ring.Name = "LevelUpGroundRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 3 * scale, 3 * scale)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = GOLD
	ring.Transparency = 0.25
	-- Der Zylinder liegt in Roblox auf der X-Achse; die Drehung legt ihn flach auf den Boden.
	ring.CFrame = CFrame.new(rootPart.Position.X, footY + 0.1, rootPart.Position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	local expand = TweenService:Create(
		ring,
		TweenInfo.new(RING_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 26 * scale, 26 * scale), Transparency = 1 }
	)
	expand:Play()
	expand.Completed:Connect(function()
		ring:Destroy()
	end)
end

-- ===== Ebene 5: Der Pop laeuft NICHT hier =====
-- Die Figur waechst beim Aufstieg kurz auf 110% -- aber vom SERVER aus, in
-- PlayerSetup.playLevelUpScalePop. Nicht aus Bequemlichkeit: Model:ScaleTo schreibt
-- Part.Size, die C0/C1 der Motor6D-Gelenke UND die Groessenwerte des Humanoid. Vom Client
-- geschrieben driften die drei auseinander, weil die letzten beiden dem Server gehoeren
-- und von ihm zurueckgesetzt werden -- die Figur bleibt dann mit zu grossen Gliedern an
-- unveraenderten Gelenken stehen.
--
-- Die Groesse hat genau einen Schreiber, und der sitzt im PlayerSetup neben
-- applySkinToCharacter und applyZoneAwareScale. Hier bleibt nur, was rein oertlich ist.

local function playCelebration(player, newLevel)
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	if running[character] then
		return
	end
	running[character] = true

	local scale = getScale(character)
	print("[Kaiju Debug] Level-Up-Feier:", player.Name, "Stufe", newLevel, "Scale", scale)

	-- Ebene 1: Funken
	local emitters = {}
	for _, partName in ipairs(EMITTER_PARTS) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			local emitter = createSparkEmitter(part, scale)
			emitter.sparks:Emit(BURST_PARTICLES)
			table.insert(emitters, emitter)
		end
	end

	-- Ebene 2: Glut um die ganze Figur
	local highlight = Instance.new("Highlight")
	highlight.Name = "LevelUpHighlight"
	highlight.FillColor = GOLD
	highlight.OutlineColor = GOLD_BRIGHT
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character

	TweenService:Create(
		highlight,
		TweenInfo.new(GLOW_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	):Play()

	-- Ebene 3: Licht
	local light = Instance.new("PointLight")
	light.Name = "LevelUpLight"
	light.Color = GOLD
	light.Brightness = 4
	light.Range = 16 * scale
	light.Parent = rootPart

	TweenService:Create(
		light,
		TweenInfo.new(GLOW_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	):Play()

	-- Ebene 4: Ring
	playGroundRing(character, scale)

	-- Der Klang gehoert dem, der aufgestiegen ist -- und die Musik macht ihm Platz.
	if player == localPlayer then
		if _G.DuckBackgroundMusic then
			_G.DuckBackgroundMusic(MUSIC_DUCK_SECONDS)
		end
		if levelUpSound.SoundId ~= "" then
			levelUpSound:Play()
		end
	end

	-- Aufraeumen: erst die Emitter abschalten, dann warten, bis die letzten schon
	-- ausgestossenen Funken ausgelaufen sind -- sonst verschwinden sie mitten im Flug.
	task.delay(EMIT_SECONDS, function()
		for _, emitter in ipairs(emitters) do
			emitter.sparks.Enabled = false
		end
	end)

	task.delay(math.max(EMIT_SECONDS + 1.2, GLOW_SECONDS), function()
		for _, emitter in ipairs(emitters) do
			emitter.attachment:Destroy()
		end
		if highlight.Parent then
			highlight:Destroy()
		end
		if light.Parent then
			light:Destroy()
		end
		running[character] = nil
	end)
end

LevelUpEvent.OnClientEvent:Connect(function(player, newLevel)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	playCelebration(player, newLevel)
end)
