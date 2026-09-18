-- VERSION: 2026-09-18 #1
-- LocalScript: TalentUnlockFeedbackClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Rueckmeldung an der FIGUR, wenn eine Forschung fertig wird.
--
-- Der Talentbaum hat fuer den Moment schon eine eigene Inszenierung -- Licht laeuft durch
-- die Ader, der Ring blitzt auf. Nur sieht die niemand: eine Forschung dauert Minuten, und
-- wenn sie fertig wird, steht man in der Stadt und nicht in einem Menue. Deshalb gehoert
-- der Moment DORTHIN, wo der Blick ohnehin ist.
--
-- Die Farbe kommt vom ENERGIETYP des erforschten Talents. Damit haengt das, was draussen
-- passiert, sichtbar an dem, was drinnen angestossen wurde -- es ist dieselbe Farbe wie am
-- Ring des Knotens, an der Ader dorthin, an den Gebaeuden und an den Sammelstrahlen.
--
-- Das Sichtbare laeuft fuer JEDE Figur, der Klang nur fuer den eigenen Spieler: gesehen
-- werden soll es von allen, belohnt wird der, dem es passiert ist. Gleiche Aufteilung wie
-- beim Stufenaufstieg (LevelUpFeedbackClient) -- die beiden teilen sich die Technik, und
-- sobald jene Arbeit eingecheckt ist, lohnt es sich, sie in EIN Modul zu ziehen.
--
-- Alle Groessen haengen an character:GetScale(): die Figur waechst mit den Skins auf das
-- bis zu Sechsfache. Feste Studwerte waeren am Anfang eine Explosion und spaeter ein
-- Glimmen an den Fuessen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

local TalentUnlockedEvent = RemoteEventUtils.GetOrCreate("TalentUnlockedEvent")
local localPlayer = Players.LocalPlayer

-- ===== Das Bruellen =====
--
-- Noch leer: die Animation "Aufrichten und Bruellen" wird von Amancio nachgereicht. Bis
-- dahin laeuft alles andere -- eine fehlende Animation soll den Moment nicht verhindern,
-- sondern nur seine Mitte.
--
-- Sie liegt auf Priority "Action" und UEBERLAGERT damit das Laufen, statt die Steuerung zu
-- nehmen. Eine Forschung wird fertig, waehrend man spielt: mitten im Sprung, mitten im
-- Kampf. Ein Moment, der einen dort festhaelt, waere kein Hoehepunkt, sondern ein Treffer.
local BRUELL_ANIMATION = ""

-- Solange es kein Bruellen gibt, traegt der Belohnungston den Moment -- derselbe wie beim
-- abgeholten Geschenk (siehe HudChrome.Sound). Kommt das Bruellen dazu, entscheidet
-- Amancio, ob der Ton daneben bleibt oder darin aufgeht.
local BRUELL_SOUND = HudChrome.Sound.Belohnung

local GLUT_SEKUNDEN = 2.6 -- Glut und Licht blenden ueber diese Zeit aus
local FUNKEN_SEKUNDEN = 1.8 -- so lange steigen noch Funken nach
local RING_SEKUNDEN = 0.7 -- der Ring ist der EINSCHLAG, nicht die Aura
local MUSIK_DUCK_SEKUNDEN = 1.4
local FUNKEN_STOSS = 30 -- Anfangsschub je Emitter

-- Koerperteile, an denen Funken entstehen. FindFirstChild je Name, fehlende werden
-- uebersprungen -- deckt R15 (UpperTorso/Hand/Foot) und R6 (Torso) mit einer Liste ab.
local EMITTER_TEILE = {
	"HumanoidRootPart",
	"UpperTorso",
	"Torso",
	"LeftHand",
	"RightHand",
}

local bruellSound = Instance.new("Sound")
bruellSound.Name = "TalentUnlockSound"
bruellSound.SoundId = BRUELL_SOUND
bruellSound.Volume = 0.85
bruellSound.Parent = SoundService

-- Laeuft die Feier an dieser Figur gerade? Zwei Forschungen koennen zwar nicht gleichzeitig
-- fertig werden, aber ein Nachzuegler-Ereignis soll keine zweite Aura stapeln.
local laeuft = {}

local function holeSkalierung(character)
	local ok, scale = pcall(function()
		return character:GetScale()
	end)
	if ok and type(scale) == "number" and scale > 0 then
		return scale
	end
	return 1
end

-- ===== Funken =====
--
-- Enger Kegel nach oben: die Energie STEIGT an der Figur hoch. Ein voller Streuwinkel
-- spritzte nach allen Seiten weg und saehe aus wie ein Treffer.
local function baueFunken(part, scale, farbe)
	local halter = Instance.new("Attachment")
	halter.Name = "TalentUnlockAttachment"
	halter.Parent = part

	local funken = Instance.new("ParticleEmitter")
	funken.Name = "TalentUnlockSparks"
	funken.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	funken.Color = ColorSequence.new(Color3.new(1, 1, 1), farbe)
	funken.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	funken.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	funken.Lifetime = NumberRange.new(0.6, 1.1)
	funken.Rate = 24
	funken.Speed = NumberRange.new(7 * scale, 12 * scale)
	funken.SpreadAngle = Vector2.new(20, 20)
	funken.Acceleration = Vector3.new(0, 10 * scale, 0)
	funken.LightEmission = 1
	funken.Parent = halter

	return { halter = halter, funken = funken }
end

-- ===== Ring am Boden =====
local function baueBodenring(character, scale, farbe)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Fusshoehe statt festem Abstand: die Figur haengt je nach Skin unterschiedlich hoch
	-- ueber dem Boden (HipHeight), ein fester Versatz laege mal im Boden, mal darueber.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local fussY = rootPart.Position.Y - rootPart.Size.Y / 2 - (humanoid and humanoid.HipHeight or 0)

	local ring = Instance.new("Part")
	ring.Name = "TalentUnlockGroundRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 3 * scale, 3 * scale)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = farbe
	ring.Transparency = 0.2
	-- Der Zylinder liegt in Roblox auf der X-Achse; die Drehung legt ihn flach auf den Boden.
	ring.CFrame = CFrame.new(rootPart.Position.X, fussY + 0.1, rootPart.Position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	local lauf = TweenService:Create(
		ring,
		TweenInfo.new(RING_SEKUNDEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 28 * scale, 28 * scale), Transparency = 1 }
	)
	lauf:Play()
	lauf.Completed:Connect(function()
		ring:Destroy()
	end)
end

local function spieleBruellen(character)
	if BRUELL_ANIMATION == "" then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = BRUELL_ANIMATION
	-- pcall: eine Animation, die dem falschen Konto gehoert oder noch nicht freigegeben
	-- ist, wirft beim Laden -- und risse sonst das ganze Skript mit.
	local ok, spur = pcall(function()
		return humanoid:LoadAnimation(animation)
	end)
	if not ok or not spur then
		warn("[Kaiju Debug] TalentUnlock: Bruell-Animation liess sich nicht laden.")
		return
	end
	spur.Priority = Enum.AnimationPriority.Action
	spur:Play(0.15)
end

local function feiere(player, energyType)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or laeuft[character] then
		return
	end
	laeuft[character] = true

	local farbe = HudChrome.EnergyColor[energyType] or HudChrome.Color.Accent
	local scale = holeSkalierung(character)

	spieleBruellen(character)

	local emitter = {}
	for _, teilName in ipairs(EMITTER_TEILE) do
		local teil = character:FindFirstChild(teilName)
		if teil and teil:IsA("BasePart") then
			local e = baueFunken(teil, scale, farbe)
			e.funken:Emit(FUNKEN_STOSS)
			table.insert(emitter, e)
		end
	end

	local glut = Instance.new("Highlight")
	glut.Name = "TalentUnlockHighlight"
	glut.FillColor = farbe
	glut.OutlineColor = Color3.new(1, 1, 1)
	glut.FillTransparency = 0.55
	glut.OutlineTransparency = 0
	glut.DepthMode = Enum.HighlightDepthMode.Occluded
	glut.Parent = character
	TweenService:Create(
		glut,
		TweenInfo.new(GLUT_SEKUNDEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	):Play()

	local licht = Instance.new("PointLight")
	licht.Name = "TalentUnlockLight"
	licht.Color = farbe
	licht.Brightness = 4
	licht.Range = 18 * scale
	licht.Parent = rootPart
	TweenService:Create(
		licht,
		TweenInfo.new(GLUT_SEKUNDEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	):Play()

	baueBodenring(character, scale, farbe)

	if player == localPlayer then
		if _G.DuckBackgroundMusic then
			_G.DuckBackgroundMusic(MUSIK_DUCK_SEKUNDEN)
		end
		if bruellSound.SoundId ~= "" then
			bruellSound:Play()
		end
	end

	-- Aufraeumen: erst die Emitter abschalten, dann warten, bis die zuletzt ausgestossenen
	-- Funken ausgelaufen sind -- sonst verschwinden sie mitten im Flug.
	task.delay(FUNKEN_SEKUNDEN, function()
		for _, e in ipairs(emitter) do
			e.funken.Enabled = false
		end
	end)

	task.delay(math.max(FUNKEN_SEKUNDEN + 1.2, GLUT_SEKUNDEN), function()
		for _, e in ipairs(emitter) do
			e.halter:Destroy()
		end
		if glut.Parent then
			glut:Destroy()
		end
		if licht.Parent then
			licht:Destroy()
		end
		laeuft[character] = nil
	end)
end

TalentUnlockedEvent.OnClientEvent:Connect(function(player, factionName, talentId, energyType)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	print(string.format(
		"[Kaiju Debug] TalentUnlock: %s hat %s (%s) freigeschaltet -- Farbe %s",
		player.Name,
		tostring(talentId),
		tostring(factionName),
		tostring(energyType)
	))
	feiere(player, energyType)
end)

print("[Kaiju Debug] TalentUnlockFeedbackClient bereit.")
