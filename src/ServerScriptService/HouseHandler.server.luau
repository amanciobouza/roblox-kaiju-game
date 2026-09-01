-- VERSION: 2026-08-26 #73
-- BUGFIX: Zwei übersehene Prolog-Blockaden für Special Energy entfernt (Building Damage/Destroyed)
-- Script (kein LocalScript!): HouseHandler
-- Ort in Studio: ServerScriptService
-- Verwaltet zerstörbare Häuser (getaggt mit "KaijuHouse" über den Tag Editor).
-- Jedes Haus hat die Attribute Health, MaxHealth und CoinsReward. Setze pro Haus
-- einfach unterschiedliche MaxHealth-Werte in Studio (Properties -> Attributes) --
-- die Münz-Belohnung wird automatisch proportional dazu berechnet (mehr HP = mehr Coins).

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- WICHTIG: WaitForChild MIT Timeout statt ohne -- letzte verbliebene Stelle im
-- Kopfbereich, die das gesamte Script hätte blockieren können, falls NumberFormat aus
-- irgendeinem Grund fehlt/verzögert lädt. Fallback: simple tostring()-Formatierung ohne
-- Tausendertrennzeichen -- Zahlen bleiben lesbar, auch wenn NumberFormat fehlt.
local NumberFormat
do
	local numberFormatModule = ReplicatedStorage:WaitForChild("NumberFormat", 5)
	if numberFormatModule then
		NumberFormat = require(numberFormatModule)
	else
		warn("[HouseHandler] ModuleScript 'NumberFormat' nicht gefunden (Timeout) -- Zahlen werden ohne Tausendertrennzeichen angezeigt, der Rest von HouseHandler.lua läuft aber normal weiter.")
		NumberFormat = { Format = function(n) return tostring(n) end }
	end
end

-- WICHTIG: WaitForChild MIT Timeout statt ohne -- fehlt das ModuleScript in Studio aus
-- irgendeinem Grund (noch nicht angelegt, falsch benannt/platziert), würde ein Aufruf
-- OHNE Timeout dieses GESAMTE Script an dieser frühen Stelle für immer blockieren --
-- inklusive aller RemoteEvent-Erstellungen und der kompletten Haus-Initialisierung
-- weiter unten. Gleiches Muster wie in DebugPanelClient.lua (waitForRemote).
local EnergyTypeSkin
do
	local energyTypeSkinModule = script.Parent:WaitForChild("EnergyTypeSkin", 5)
	if energyTypeSkinModule then
		EnergyTypeSkin = require(energyTypeSkinModule)
	else
		warn("[HouseHandler] ModuleScript 'EnergyTypeSkin' nicht gefunden (Timeout) -- Energie-Typ-Optik (Einfärbung/Leuchten/Symbol) bleibt wirkungslos, der Rest von HouseHandler.lua läuft aber normal weiter.")
		EnergyTypeSkin = { Apply = function() end } -- No-Op-Fallback
	end
end

-- Gleiches sicheres Muster für ParentGroupService (Motel-artige Mehrteil-Gebäude, siehe
-- dort für Details). Init() wird weiter unten aufgerufen, sobald die benötigten lokalen
-- Funktionen (extinguishHouseFire etc.) definiert sind.
local ParentGroupService
do
	local parentGroupModule = script.Parent:WaitForChild("ParentGroupService", 5)
	if parentGroupModule then
		ParentGroupService = require(parentGroupModule)
	else
		warn("[HouseHandler] ModuleScript 'ParentGroupService' nicht gefunden (Timeout) -- Mehrteil-Gebäude (z.B. Motel) respawnen dann als Einzelhäuser statt als Gruppe.")
		ParentGroupService = {
			Init = function() end,
			Register = function() end,
			IsParentGroupHouse = function() return false end,
			GetGroup = function() return nil end,
			ScheduleRespawn = function() end,
		}
	end
end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- WICHTIG: erstellt dieses RemoteEvent selbst, falls es noch nicht existiert, statt nur
-- darauf zu warten -- reines WaitForChild hier hätte das Script (und alle darauf
-- wartenden Client-Scripts) für immer hängen lassen, falls keine andere Datei es erzeugt.
-- Gleiches Muster wie in SpecialAttackHandler.lua/TrenchbornPortalController.lua.
local function getOrCreateRemoteEvent(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local CoinsEarnedEvent = getOrCreateRemoteEvent("CoinsEarnedEvent")
-- WICHTIG: getOrCreateRemoteEvent statt WaitForChild ohne Timeout -- ShowDamageEvent
-- wurde bisher nur von SpecialAttackHandler.lua tatsächlich ERZEUGT, alle anderen
-- Dateien (u.a. diese hier) haben nur mit WaitForChild OHNE Timeout darauf gewartet.
-- Startet SpecialAttackHandler.lua aus irgendeinem Grund später (Roblox garantiert keine
-- feste Script-Reihenfolge), blieb dieses Script HIER für immer hängen -- noch bevor es
-- zu JumpAttackCooldown oder den RemoteEvents weiter unten kam. Jetzt kann JEDE der
-- beteiligten Dateien das Event notfalls selbst erzeugen, unabhängig von der Reihenfolge.
local ShowDamageEvent = getOrCreateRemoteEvent("ShowDamageEvent")

-- Debug-Schalter: überspringt die Einsturz-Animation (siehe collapseHouse weiter unten).
-- Globaler Schalter für ALLE Spieler (nicht nur den umschaltenden) -- praktisch fürs
-- schnellere Testen mehrerer Zerstörungs-Zyklen.
_G.DebugSkipCollapseAnimation = false
local DebugToggleSkipCollapseEvent = getOrCreateRemoteEvent("DebugToggleSkipCollapseEvent")
DebugToggleSkipCollapseEvent.OnServerEvent:Connect(function(player)
	if not player:GetAttribute("DebugMode") then
		return
	end
	_G.DebugSkipCollapseAnimation = not _G.DebugSkipCollapseAnimation
end)

local HOUSE_TAG = "KaijuHouse"
local RESPAWN_TIME = 30 -- Sekunden bis ein zerstörtes Haus wieder erscheint
local GROUP_SECTION_ENERGY_TIME = 12 -- L3: Feuer/Energy pro zerstörtem Trakt, unabhängig vom Gruppen-Respawn
local FIRE_DIE_DURATION = 3 -- Sekunden, über die das Feuer selbst langsam ausgeht
local SMOKE_REDUCE_DURATION = 2.5 -- Sekunden, über die der Rauch danach auf einen schwächeren Nachglimm-Rauch zurückgeht
local SMOKE_FADE_DURATION = 3.5 -- Sekunden, über die dieser Rest-Rauch danach komplett ausklingt

local DEFAULT_HEALTH = 100
-- Nicht-lineare Belohnungsformel: Belohnung = HP^EXPONENT * SCALE. Der Exponent < 1 sorgt
-- für abnehmende Erträge bei riesigen Gebäuden (Mega-City bis 64 Mio. HP) -- sonst würden
-- lineare Belohnungen absurd hohe Zahlen erzeugen (32 Mio. Coins auf einen Schlag).
local REWARD_HP_EXPONENT = 0.75
local COINS_SCALE = 1.2
local XP_SCALE = 15 -- ÷100 (war 1500) -- 900 Energie beim kleinsten Haus war zu viel, 9 wäre angemessen gewesen
local EVOLUTION_SCALE = 0.15

local function rewardFromHP(hp, scale)
	return math.floor((hp ^ REWARD_HP_EXPONENT) * scale)
end

-- Für EnergyCollectionHandler.lua: dieselbe Formel, die früher direkt die volle XP-Menge
-- instant vergeben hat, liefert jetzt die GESAMT-Energiemenge eines Hauses (wird dort in
-- Explosions-/Feuer-Anteil aufgeteilt).
_G.HouseEnergyReward = function(hp)
	return rewardFromHP(hp, XP_SCALE)
end

-- WICHTIG: Trag hier deine eigene Sound-ID aus dem Creator Store ein (Format: "rbxassetid://12345678")
local HOUSE_IMPACT_SOUND_ID = "rbxassetid://94204209674027"
local HOUSE_EXPLOSION_SOUND_ID = "rbxassetid://138668273240081"

-- Zerstörte Häuser werden hierhin verschoben (komplett aus der Welt entfernt --
-- garantiert unsichtbar, unabhängig von Texturen/Decals/Unions/etc.).
local hiddenHousesFolder = Instance.new("Folder")
hiddenHousesFolder.Name = "HiddenHouses"
hiddenHousesFolder.Parent = ServerStorage

-- Merkt sich, wo ein Haus ursprünglich stand (Workspace), damit es beim Respawn zurückkommt.
local originalParents = {}

-- L3 / ParentGroup: ein Asset (z.B. Motel) besteht aus mehreren separat angreifbaren
-- KaijuHouse-Sektionen, die NIE einzeln respawnen dürfen -- die komplette Logik dafür
-- (inkl. eigenem Zustand) lebt jetzt in ParentGroupService.lua.

-- Vorab deklariert, da initHouse (weiter oben in der Datei) sie referenziert, die
-- eigentliche Funktion aber erst weiter unten zugewiesen wird (braucht damageHouse).
local onHouseTouched

-- ===== Robuste Touch-Registrierung =================================================
-- Merkt sich pro Haus/Part die Touched-Verbindung. Wichtig für komplexe Assets:
-- Parts, die NACH initHouse() hinzukommen, werden über DescendantAdded ebenfalls
-- automatisch verdrahtet. Ohne das würden nachträglich erzeugte Gebäudeteile niemals
-- Anrenn-/Dach-/Sprungschaden auslösen.
local houseTouchConnections = {} -- [house] = { [part] = RBXScriptConnection }
local houseDescendantConnections = {} -- [house] = RBXScriptConnection

local function connectHouseTouchPart(house, part)
	if not part:IsA("BasePart") then
		return
	end
	if part:GetAttribute("IsTechnicalPart") then
		return
	end

	houseTouchConnections[house] = houseTouchConnections[house] or {}
	if houseTouchConnections[house][part] then
		return
	end

	houseTouchConnections[house][part] = part.Touched:Connect(function(hit)
		if onHouseTouched then
			-- WICHTIG:
			-- 'part' ist das tatsächlich berührte GEBÄUDETEIL.
			-- 'hit' ist das Character-/Spieler-Part, das dieses Gebäudeteil berührt.
			onHouseTouched(house, part, hit)
		end
	end)
end

-- Erstellt einen Lebensbalken, der über der GESAMTEN Bounding-Box des Hauses schwebt
-- (nicht nur über einem einzelnen Teil -- wichtig bei unregelmäßig gebauten Häusern).
local function createHealthBar(house)
	local anchorPart = house.PrimaryPart
	if not anchorPart then
		return nil
	end

	local ok, cframe, size = pcall(function()
		return house:GetBoundingBox()
	end)
	local topOffsetY = 3
	if ok then
		topOffsetY = (cframe.Position.Y + size.Y / 2) - anchorPart.Position.Y + 3
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HouseHealthBar"
	billboard.Size = UDim2.new(0, 80, 0, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500 -- großzügig, damit es auch bei riesigen Skins (Kamera weiter weg) sichtbar bleibt
	billboard.Parent = anchorPart

	-- Zahl oben, kein Hintergrund
	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.new(1, 0, 0, 14)
	hpLabel.Position = UDim2.new(0, 0, 0, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.LuckiestGuy
	hpLabel.TextScaled = true
	hpLabel.TextColor3 = Color3.new(1, 1, 1)
	hpLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	hpLabel.TextStrokeTransparency = 0
	hpLabel.Text = ""
	hpLabel.Parent = billboard

	-- Schlanker Balken darunter -- kein Kasten/Panel dahinter, nur eine dünne Umrisslinie
	-- als Orientierung, die Füllung selbst ist der sichtbare Balken.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 8)
	track.Position = UDim2.new(0, 0, 0, 16)
	track.BackgroundTransparency = 1
	track.Parent = billboard

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Thickness = 1.5
	trackStroke.Color = Color3.new(0, 0, 0)
	trackStroke.Transparency = 0.3
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = track

	return billboard
end

-- [house] = Generation-Zähler, um überlappende Ausblend-Timer bei schnell
-- aufeinanderfolgenden Treffern sauber zu handhaben (nur der NEUESTE Timer darf am Ende
-- wirklich ausblenden).
local healthBarHideGeneration = {}

local function updateHealthBar(house)
	local billboard = house.PrimaryPart and house.PrimaryPart:FindFirstChild("HouseHealthBar")
	if not billboard then
		return
	end

	local fill = billboard:FindFirstChild("Fill", true)
	local hpLabel = billboard:FindFirstChild("HPLabel", true)
	local track = billboard:FindFirstChild("Track")
	if not fill then
		return
	end

	local health = house:GetAttribute("Health") or 0
	local maxHealth = math.max(house:GetAttribute("MaxHealth") or 1, 1)
	local ratio = math.clamp(health / maxHealth, 0, 1)

	fill.Size = UDim2.new(ratio, 0, 1, 0)
	-- Grün bei viel Leben, über Gelb zu Rot bei wenig Leben (Balken = Restleben-Prozent)
	fill.BackgroundColor3 = Color3.fromRGB(255 - math.floor(165 * ratio), 90 + math.floor(130 * ratio), 90)

	if ratio >= 1 then
		-- Volles Leben (unberührtes Gebäude) -- komplett ausgeblendet, keine Zahl, kein Balken.
		billboard.Enabled = false
		return
	end

	-- Gebäude hat Schaden genommen: kurz aufblitzen lassen (Zahl + Balken), dann nach 2s
	-- automatisch wieder ausblenden -- nicht mehr dauerhaft sichtbar.
	billboard.Enabled = true
	if track then
		track.Visible = true
	end
	if hpLabel then
		hpLabel.Visible = true
		hpLabel.Text = NumberFormat.Format(health)
	end

	-- WICHTIG: Bei Health=0 (Haus ist zerstört, wartet aber evtl. noch in der Kollaps-
	-- Warteschlange auf seinen Slot) bleibt der Balken bewusst DAUERHAFT sichtbar (bei
	-- 0%, rot) -- kein Auto-Ausblenden nach 2s. So sieht man auch bei Häusern, die noch
	-- länger in der Warteschlange stehen, sofort "das hier ist bereits zerstört". Sobald
	-- die Kollaps-Sequenz tatsächlich beginnt, blendet setHouseVisible(house, false) den
	-- Balken explizit aus (das Haus wird dabei komplett unsichtbar gemacht).
	if health <= 0 then
		healthBarHideGeneration[house] = (healthBarHideGeneration[house] or 0) + 1 -- evtl. noch laufenden alten Ausblend-Timer ungültig machen
		return
	end

	healthBarHideGeneration[house] = (healthBarHideGeneration[house] or 0) + 1
	local myGeneration = healthBarHideGeneration[house]
	task.delay(2, function()
		if healthBarHideGeneration[house] == myGeneration and billboard.Parent then
			billboard.Enabled = false
		end
	end)
end

-- Verhindert, dass mehrere Zitter-Effekte gleichzeitig am selben Haus laufen
local shakingHouses = {}

-- Lässt das ganze Haus kurz wackeln (funktioniert unabhängig davon, ob die Teile
-- verschweißt sind, da PivotTo das komplette Model als starren Körper bewegt).
local function shakeHouse(house)
	if shakingHouses[house] then
		return
	end
	shakingHouses[house] = true

	local originalPivot = house:GetPivot()

	task.spawn(function()
		for _ = 1, 5 do
			local offset = Vector3.new(math.random(-20, 20) / 100, 0, math.random(-20, 20) / 100)
			local ok = pcall(function()
				house:PivotTo(originalPivot + offset)
			end)
			if not ok then
				break
			end
			task.wait(0.04)
		end
		pcall(function()
			house:PivotTo(originalPivot)
		end)
		shakingHouses[house] = nil
	end)
end

-- Spielt einen visuellen Explosions-Effekt + Sound an der Position des Hauses ab.
-- Nutzt ein separates, unsichtbares Anker-Teil, damit der Effekt unabhängig vom
-- Verstecken/Respawnen des Hauses zuverlässig zu Ende abspielt.
local EXPLOSION_GROWTH_DURATION = 0.3 -- schnell
local HOUSE_COLLAPSE_DURATION = 1.1 -- etwas langsamer -- die Kipp-/Sink-Bewegung soll sich Zeit lassen
local HOUSE_UNCOLLAPSE_DURATION = 1.1 -- Respawn: Teile "richten sich wieder auf" (Umkehrung des Einsturzes), ebenfalls langsamer
local EXPLOSION_HEIGHT_OFFSET = 8 -- Studs über der reinen Unterkante des Hauses
local EXPLOSION_TOTAL_DURATION = 1 -- die ganze Animation soll nicht länger als 1 Sekunde dauern

-- ===== Gedämpfte Grössen-Skalierung basierend auf Gebäude-MaxHealth =====
-- Gemeinsam für Explosion, Feuer UND Rauch genutzt -- bewusst NICHT linear (1:1 wäre bei
-- einer Spanne von 100 bis 64 Mio. HP absurd), sondern mit Exponent gedämpft plus
-- Obergrenze. Kleine Häuser wirken dadurch spürbar kleiner als grosse, aber selbst ein
-- Mega-City-Gebäude explodiert/brennt nicht ins Unermessliche.
local function getDestructionEffectScale(maxHealth)
	return math.clamp(1 + (maxHealth ^ 0.3) * 0.3, 1, 6)
end

-- Staubwolke beim Einsturz: emittiert über die GESAMTE Grundfläche des Gebäudes (nicht
-- nur einen einzelnen Punkt) -- dadurch skaliert die Wolke automatisch horizontal mit
-- der Gebäudegrösse (ein grosses Gebäude wirbelt über eine grosse Fläche Staub auf).
-- Vertikal bewusst NUR LEICHT grösser (Schwerkraft zieht den Staub so oder so schnell
-- wieder runter, unabhängig davon wie riesig das Gebäude war).
local function playDustCloudEffect(groundPosition, boundsSize)
	print("[Kaiju-Debug] playDustCloudEffect aufgerufen, groundPosition:", groundPosition, "boundsSize:", boundsSize)
	-- Wie bei einer kontrollierten Hochhaus-Sprengung: die Staubwolke breitet sich
	-- RADIAL/KREISFÖRMIG am Boden nach ALLEN SEITEN aus, statt wie Rauch nach oben zu
	-- steigen. Nutzt Robloxs EINGEBAUTE "Disk"-Emitter-Form -- die emittiert nativ radial
	-- von der Kreisfläche nach aussen, kein manuelles Rotieren einzelner Emitter nötig
	-- (der frühere Ansatz mit 28 rotierten Attachments hat aus unbekanntem Grund nicht
	-- gerendert -- dieser native Weg ist der von Roblox dafür vorgesehene).
	local footprintRadius = math.max(boundsSize.X, boundsSize.Z, 6) / 2
	local scale = math.clamp(1 + (footprintRadius ^ 0.35) * 0.5, 1.4, 5)

	local dustAnchor = Instance.new("Part")
	dustAnchor.Name = "DustCloudAnchor"
	dustAnchor.Anchored = true
	dustAnchor.CanCollide = false
	dustAnchor.CanQuery = false
	dustAnchor.Transparency = 1
	dustAnchor.Size = Vector3.new(footprintRadius * 2.2, 0.2, footprintRadius * 2.2)
	-- Um 90° gekippt, damit die Disk-Fläche FLACH/HORIZONTAL liegt (parallel zum Boden) --
	-- eine unrotierte Disk stünde sonst senkrecht wie ein Rad.
	dustAnchor.CFrame = CFrame.new(groundPosition)
	dustAnchor.Parent = workspace

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "DustCloud"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 198, 192)) -- hellgrau
	dust.Shape = Enum.ParticleEmitterShape.Cylinder
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	dust.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward -- WICHTIG: emittiert radial VOM Rand weg

	-- Partikel BLÄHEN SICH AUF (klein -> gross) und werden dann wieder kleiner/verblassen
	-- -- "aufblähen und langsam verschwinden", keine aufsteigende Rauchsäule.
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 5 * scale),
		NumberSequenceKeypoint.new(0.35, 15 * scale),
		NumberSequenceKeypoint.new(0.7, 19 * scale),
		NumberSequenceKeypoint.new(1, 16 * scale),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.25, 0),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	local lifetimeScale = math.clamp(scale * 0.6, 1, 1.8)
	dust.Lifetime = NumberRange.new(2.8 * lifetimeScale, 3.6 * lifetimeScale)

	local speedScale = math.clamp(scale * 0.5, 1, 2.5)
	dust.Speed = NumberRange.new(footprintRadius * 0.35 * speedScale, footprintRadius * 0.55 * speedScale)
	dust.SpreadAngle = Vector2.new(15, 15)
	dust.Acceleration = Vector3.new(0, -6, 0) -- bremst die Steighöhe zügig, bleibt bodennah
	dust.Drag = 1.2
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-25, 25)

	-- WICHTIG: Kontinuierliche Emission über "Rate" statt einmaligem Emit()-Ausstoss --
	-- das ist exakt die Technik, die beim Feuer-Rauch (SmokePlume) nachweislich
	-- funktioniert. Ein kurzer, hoher Rate-Stoss über 0.4s erzeugt denselben "Wumms"-
	-- Effekt wie ein einmaliger Ausstoss, aber zuverlässig sichtbar.
	local totalParticles = math.clamp(math.floor(55 * scale), 55, 160)
	dust.Rate = totalParticles / 0.4
	dust.Parent = dustAnchor
	print("[Kaiju-Debug] Dust-Cylinder-Emitter: Rate:", dust.Rate, "Speed:", dust.Speed, "footprintRadius:", footprintRadius, "scale:", scale)

	task.delay(0.4, function()
		if dust.Parent then
			dust.Rate = 0
		end
	end)

	task.delay(6, function()
		dustAnchor:Destroy()
	end)
end

-- Spielt NUR den Knallsound, sofort beim Zerstören (zusammen mit dem Staubwirbel) --
-- getrennt von der verzögerten visuellen Explosion (playExplosionEffect weiter unten),
-- die weiterhin mit Feuer/Rauch nach der Pause erscheint.
local function playDestructionSound(groundPosition)
	if HOUSE_EXPLOSION_SOUND_ID == "" or HOUSE_EXPLOSION_SOUND_ID == "rbxassetid://0" then
		return
	end

	local soundAnchor = Instance.new("Part")
	soundAnchor.Name = "DestructionSoundAnchor"
	soundAnchor.Anchored = true
	soundAnchor.CanCollide = false
	soundAnchor.CanQuery = false
	soundAnchor.Transparency = 1
	soundAnchor.Size = Vector3.new(1, 1, 1)
	soundAnchor.CFrame = CFrame.new(groundPosition)
	soundAnchor.Parent = workspace

	local destructionSound = Instance.new("Sound")
	destructionSound.Name = "DestructionSound"
	destructionSound.SoundId = HOUSE_EXPLOSION_SOUND_ID
	destructionSound.Volume = 1
	destructionSound.Parent = soundAnchor
	destructionSound:Play()

	Debris:AddItem(soundAnchor, 5)
end

local function playExplosionEffect(house)
	local ok, cframe, size = pcall(function()
		return house:GetBoundingBox()
	end)
	if not ok then
		warn("[Kaiju-Debug] playExplosionEffect: GetBoundingBox fehlgeschlagen für '" .. house:GetFullName() .. "' -- keine Explosion erzeugt.")
		return
	end

	-- Boden-Position statt Mitte der Bounding-Box, mit etwas Höhen-Puffer nach oben
	local groundCFrame =
		CFrame.new(cframe.Position.X, cframe.Position.Y - size.Y / 2 + EXPLOSION_HEIGHT_OFFSET, cframe.Position.Z)

	local effectAnchor = Instance.new("Part")
	effectAnchor.Name = "ExplosionEffectAnchor"
	effectAnchor.Anchored = true
	effectAnchor.CanCollide = false
	effectAnchor.CanQuery = false
	effectAnchor.Transparency = 1
	effectAnchor.Size = Vector3.new(1, 1, 1)
	effectAnchor.CFrame = groundCFrame
	effectAnchor.Parent = workspace

	-- Eigenes Partikel-VFX (ServerStorage.Effects.HouseExplosionVFX) statt/zusätzlich
	-- zum generischen Roblox-Explosion-Effekt.
	local effectsFolder = ServerStorage:FindFirstChild("Effects")
	local vfxTemplate = effectsFolder and effectsFolder:FindFirstChild("HouseExplosionVFX")

	-- Skalierungsfaktor basierend auf der Gebäudegröße (MaxHealth) -- kleine Häuser (100 HP)
	-- bekommen jetzt spürbar größere Explosionen als vorher, riesige Mega-City-Gebäude einen
	-- gedeckelten Maximalwert (sonst würde die Explosion absurd riesig werden).
	local maxHealth = house:GetAttribute("MaxHealth") or 100
	local explosionScale = getDestructionEffectScale(maxHealth)

	if vfxTemplate then
		local vfxClone = vfxTemplate:Clone()

		-- WICHTIG: Statt uns auf PivotTo() zu verlassen (das bei manchen VFX-Assets
		-- verschachtelte Teile ohne echtes BasePart NICHT mitbewegt -- die blieben dann
		-- an ihrer Ursprungsposition, z.B. nahe (0,0,0), hängen), hängen wir JEDEN
		-- gefundenen ParticleEmitter direkt an unseren bereits korrekt positionierten
		-- effectAnchor um. So ist die Position garantiert richtig, unabhängig von der
		-- internen Struktur des VFX-Assets.
		local emitters = {}
		for _, descendant in ipairs(vfxClone:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				table.insert(emitters, descendant)
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.Transparency = 1
			end
		end

		for _, emitter in ipairs(emitters) do
			emitter.Parent = effectAnchor

			-- Partikel-Größe mit dem Skalierungsfaktor multiplizieren (jeder Keypoint
			-- der bestehenden Size-Kurve wird vergrößert, Form/Verlauf bleibt erhalten).
			local scaledKeypoints = {}
			for _, keypoint in ipairs(emitter.Size.Keypoints) do
				table.insert(
					scaledKeypoints,
					NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * explosionScale, keypoint.Envelope * explosionScale)
				)
			end
			emitter.Size = NumberSequence.new(scaledKeypoints)

			-- Mehr Partikel bei größeren Häusern, damit die Explosion auch "voller" wirkt
			local baseEmitCount = emitter:GetAttribute("EmitCount") or 30
			emitter:Emit(math.floor(baseEmitCount * explosionScale))
		end

		vfxClone:Destroy() -- die leere Hülle wird nicht mehr gebraucht, nur die Emitter selbst
	else
		-- Fallback: generischer Roblox-Explosion-Effekt, falls kein eigenes VFX vorbereitet ist
		local explosion = Instance.new("Explosion")
		explosion.Position = groundCFrame.Position
		explosion.BlastRadius = 12 * explosionScale
		explosion.BlastPressure = 0 -- rein visueller Effekt, keine Wucht/Umgebungsschaden
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = workspace
	end

	-- Sound wird jetzt SOFORT nach dem Zerstören abgespielt (siehe playDestructionSound
	-- weiter unten, aufgerufen direkt neben dem Staubwirbel) -- nicht mehr hier, verzögert
	-- zusammen mit der visuellen Explosion.

	task.delay(EXPLOSION_TOTAL_DURATION, function()
		effectAnchor:Destroy()
	end)
end

-- Vorbereitete Ruinen-Vorlagen pro Haus (nicht in der Welt geparkt, nur zum Klonen)
-- und die aktuell sichtbare Ruine (falls das Haus gerade zerstört ist).
local ruinTemplates = {}
local activeRuins = {}

-- Läuft aktives Feuer pro Haus, damit es beim erneuten Zerstören/Respawnen sauber
-- aufgeräumt werden kann.
local activeFires = {}

-- Entzündet ein Feuer an der Position des Hauses, das bis kurz vor dem Respawn brennt
-- und dann in drei Phasen (Feuer aus -> Rest-Rauch -> ausklingen) langsam verschwindet.
local FIRE_SIZE_BASE = 10 -- wird mit fireScale (siehe getDestructionEffectScale) multipliziert
local FIRE_HEAT_BASE = 3

local function startHouseFire(house, groundCFrame, lifetimeOverride)
	local fireLifetime = tonumber(lifetimeOverride) or RESPAWN_TIME
	local maxHealth = house:GetAttribute("MaxHealth") or 100
	-- Dieselbe gedämpfte Skalierung wie bei der Explosion (siehe getDestructionEffectScale)
	-- -- kleine Häuser brennen/rauchen spürbar kleiner als grosse, aber selbst ein
	-- Mega-City-Gebäude bekommt keine absurd riesige Feuersäule.
	local fireScale = getDestructionEffectScale(maxHealth)

	local fireAnchor = Instance.new("Part")
	fireAnchor.Name = "HouseFireAnchor"
	fireAnchor.Anchored = true
	fireAnchor.CanCollide = false
	fireAnchor.CanQuery = false
	fireAnchor.Transparency = 1
	fireAnchor.Size = Vector3.new(1, 1, 1)
	fireAnchor.CFrame = groundCFrame
	fireAnchor.Parent = workspace

	-- Eigenes Feuer-VFX (ServerStorage.Effects.HouseFireVFX), falls vorhanden -- sonst
	-- Fallback auf Robloxs eingebautes Fire-Objekt. Genau wie bei der Explosion: ALLE
	-- ParticleEmitter im VFX werden direkt an den Anker umgehängt (unabhängig von der
	-- internen Struktur des Assets), damit die Position garantiert stimmt.
	local effectsFolder = ServerStorage:FindFirstChild("Effects")
	local fireVfxTemplate = effectsFolder and effectsFolder:FindFirstChild("HouseFireVFX")

	local fire, customEmitters
	if fireVfxTemplate then
		local vfxClone = fireVfxTemplate:Clone()
		customEmitters = {}
		for _, descendant in ipairs(vfxClone:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				table.insert(customEmitters, descendant)
			end
		end
		for _, emitter in ipairs(customEmitters) do
			emitter.Parent = fireAnchor
			emitter.Enabled = true

			-- Grösse (jeder Keypoint der bestehenden Size-Kurve) und Rate mit dem
			-- Skalierungsfaktor multiplizieren -- Form/Verlauf der Kurve bleibt erhalten,
			-- nur die Grössenordnung passt sich dem Gebäude an.
			local scaledKeypoints = {}
			for _, keypoint in ipairs(emitter.Size.Keypoints) do
				table.insert(
					scaledKeypoints,
					NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * fireScale, keypoint.Envelope * fireScale)
				)
			end
			emitter.Size = NumberSequence.new(scaledKeypoints)
			emitter.Rate = emitter.Rate * fireScale
		end
		vfxClone:Destroy() -- leere Hülle, nicht mehr gebraucht
	else
		fire = Instance.new("Fire")
		fire.Size = FIRE_SIZE_BASE * fireScale
		fire.Heat = FIRE_HEAT_BASE * fireScale
		fire.Parent = fireAnchor
	end

	-- ParticleEmitter statt Smoke-Objekt: lässt sich als schmale, aufsteigende Rauchfahne
	-- gestalten (enger Streuwinkel, klare Aufwärtsrichtung) statt einer breiten Wolke.
	-- Grösse UND Aufsteigrate ebenfalls mit fireScale skaliert -- ein grosses Gebäude
	-- raucht spürbar mehr/breiter als ein kleines.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "SmokePlume"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 70, 75))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2 * fireScale),
		NumberSequenceKeypoint.new(0.5, 6 * fireScale),
		NumberSequenceKeypoint.new(1, 10 * fireScale),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Rate = 15 * fireScale
	smoke.Speed = NumberRange.new(6, 10)
	smoke.SpreadAngle = Vector2.new(5, 5) -- eng gehalten -> Fahne statt breiter Wolke
	smoke.Acceleration = Vector3.new(0, 2, 0) -- beschleunigt weiter nach oben, je höher sie steigt
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-20, 20)
	smoke.Parent = fireAnchor

	activeFires[house] = fireAnchor

	-- ===== Dreistufige Ausklingsequenz, bevor das Haus respawnbereit ist =====
	-- 1) Feuer geht langsam aus (Grösse/Hitze bzw. eigene Emitter-Rate -> 0), Rauch läuft
	--    dabei noch auf volle Stärke weiter (ein frisch erloschenes Feuer raucht ja auch
	--    im echten Leben zunächst normal weiter).
	-- 2) Rauch reduziert sich auf einen SCHWÄCHEREN Nachglimm-Rauch (deutlich weniger als
	--    vorher, aber noch sichtbar).
	-- 3) Auch dieser Rest-Rauch klingt langsam komplett aus. Erst DANACH ist das Haus
	--    respawnbereit.
	local fadeStartDelay = math.max(fireLifetime - FIRE_DIE_DURATION - SMOKE_REDUCE_DURATION - SMOKE_FADE_DURATION, 0)
	task.delay(fadeStartDelay, function()
		if not fireAnchor.Parent then
			return -- wurde schon vorher aufgeräumt (z.B. Haus erneut zerstört)
		end

		local startFireSize = fire and fire.Size
		local startFireHeat = fire and fire.Heat
		local startEmitterRates = {}
		if customEmitters then
			for _, emitter in ipairs(customEmitters) do
				startEmitterRates[emitter] = emitter.Rate
			end
		end

		-- Phase 1: Feuer geht aus, Rauch bleibt währenddessen auf voller Stärke.
		local fireSteps = 10
		for step = 1, fireSteps do
			if not fireAnchor.Parent then
				return
			end
			local alpha = step / fireSteps
			if fire then
				fire.Size = startFireSize * (1 - alpha)
				fire.Heat = startFireHeat * (1 - alpha)
			end
			if customEmitters then
				for _, emitter in ipairs(customEmitters) do
					emitter.Rate = startEmitterRates[emitter] * (1 - alpha)
				end
			end
			task.wait(FIRE_DIE_DURATION / fireSteps)
		end

		-- Phase 2: Rauch reduziert sich auf einen schwächeren Nachglimm-Rauch (40% der
		-- ursprünglichen Rate) -- deutlich weniger als vorher, aber noch klar sichtbar.
		local fullSmokeRate = smoke.Rate
		local reducedSmokeRate = fullSmokeRate * 0.4
		local reduceSteps = 8
		for step = 1, reduceSteps do
			if not fireAnchor.Parent then
				return
			end
			local alpha = step / reduceSteps
			smoke.Rate = fullSmokeRate + (reducedSmokeRate - fullSmokeRate) * alpha
			task.wait(SMOKE_REDUCE_DURATION / reduceSteps)
		end

		-- Phase 3: auch der Nachglimm-Rauch klingt jetzt komplett aus.
		local fadeSteps = 10
		for step = 1, fadeSteps do
			if not fireAnchor.Parent then
				return
			end
			local alpha = step / fadeSteps
			smoke.Rate = reducedSmokeRate * (1 - alpha)
			task.wait(SMOKE_FADE_DURATION / fadeSteps)
		end

		fireAnchor:Destroy()
		if activeFires[house] == fireAnchor then
			activeFires[house] = nil
		end
	end)
end

-- Entfernt ein evtl. noch brennendes Feuer sofort (z.B. wenn das Haus respawnt oder
-- erneut zerstört wird, bevor das alte Feuer von selbst ausgegangen ist).
local function extinguishHouseFire(house)
	local fireAnchor = activeFires[house]
	if fireAnchor then
		fireAnchor:Destroy()
		activeFires[house] = nil
	end
	if _G.UnregisterFireEnergySource then
		_G.UnregisterFireEnergySource(house)
	end
	-- Firefighter Extinguishing Feedback: evtl. noch hängende Löschanzeige aufräumen,
	-- falls das Haus respawnt/erneut zerstört wird, während der Löschvorgang unterbrochen
	-- (nicht durch playExtinguishSuccessSequence abgeschlossen) war.
	if _G.ClearExtinguishBillboard then
		_G.ClearExtinguishBillboard(house)
	end
end

-- Baut automatisch eine simple Schutt-Version aus den ECHTEN Haus-Teilen (nicht mehr
-- generische Blöcke): verkleinert, zufällig verdreht/verstreut, mit Mindestgröße (damit auch
-- winzige Deko-Teile bei riesigen Kaiju-Skins sichtbar bleiben). Wird genutzt, falls kein
-- eigenes "RuinModel" vorbereitet wurde.
local RUIN_DEBRIS_COUNT = 45 -- Ziel-Anzahl; falls das Original mehr Teile hat, wird eine zufällige Auswahl genutzt

local function buildFallbackRuin(house)
	local ruin = Instance.new("Model")
	ruin.Name = "AutoRuin"

	local ok, boundsCFrame, boundsSize = pcall(function()
		return house:GetBoundingBox()
	end)
	if not ok then
		print("[Kaiju-Debug] buildFallbackRuin: GetBoundingBox fehlgeschlagen für '" .. house.Name .. "'")
		return ruin
	end

	local groundY = boundsCFrame.Position.Y - boundsSize.Y / 2

	-- Alle echten Teile des Hauses sammeln
	local sourceParts = {}
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") and not part:GetAttribute("IsTechnicalPart") then
			table.insert(sourceParts, part)
		end
	end

	-- Falls das Original mehr Teile hat als RUIN_DEBRIS_COUNT: zufällige Auswahl treffen,
	-- damit nicht hunderte winzige Krümel entstehen. Falls weniger: einfach alle nehmen.
	local selectedParts = sourceParts
	if #sourceParts > RUIN_DEBRIS_COUNT then
		selectedParts = {}
		local pool = table.clone(sourceParts)
		for _ = 1, RUIN_DEBRIS_COUNT do
			local index = math.random(1, #pool)
			table.insert(selectedParts, pool[index])
			table.remove(pool, index)
		end
	end

	-- Mindestgröße, damit auch sehr kleine Original-Teile (Nägel, Trimm, etc.) als
	-- Trümmer noch sichtbar bleiben, egal wie riesig der Charakter gerade ist.
	local minChunk = 2 + math.min(boundsSize.X, boundsSize.Z) * 0.05

	for _, part in ipairs(selectedParts) do
		local debris = part:Clone()
		debris:ClearAllChildren()
		debris.Name = "DebrisChunk"
		debris.Size = Vector3.new(
			math.max(part.Size.X * 0.8, minChunk),
			math.max(part.Size.Y * 0.5, minChunk * 0.6),
			math.max(part.Size.Z * 0.8, minChunk)
		)
		debris.Transparency = 0
		debris.CanCollide = false
		debris.CanQuery = false
		debris.Anchored = true

		local offsetX = (math.random() - 0.5) * boundsSize.X * 0.7
		local offsetZ = (math.random() - 0.5) * boundsSize.Z * 0.7
		debris.CFrame = CFrame.new(
			boundsCFrame.Position.X + offsetX,
			groundY + debris.Size.Y * 0.7,
			boundsCFrame.Position.Z + offsetZ
		) * CFrame.Angles(math.rad(math.random(-15, 15)), math.rad(math.random(0, 360)), math.rad(math.random(-15, 15)))
		debris.Parent = ruin
	end

	print(
		"[Kaiju-Debug] buildFallbackRuin: "
			.. #selectedParts
			.. " Original-Teile als Trümmer genutzt (von "
			.. #sourceParts
			.. " insgesamt) für '"
			.. house.Name
			.. "'"
	)

	return ruin
end

-- Bereitet die Ruinen-Vorlage für ein Haus vor (einmalig). Falls das Haus ein Kind-Model
-- namens "RuinModel" hat (von dir selbst gebaut, an derselben Stelle wie das Haus),
-- wird DAS als Vorlage genutzt -- sonst automatisch Schutt aus den Haus-Teilen generiert.
local function prepareRuinTemplate(house)
	if ruinTemplates[house] then
		print("[Kaiju-Debug] prepareRuinTemplate: Vorlage für '" .. house.Name .. "' existiert schon, überspringe")
		return
	end

	local customRuin = house:FindFirstChild("RuinModel")
	if customRuin then
		print("[Kaiju-Debug] prepareRuinTemplate: eigenes RuinModel gefunden, nutze das")
		for _, part in ipairs(customRuin:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
			end
		end
		local template = customRuin:Clone()
		customRuin:Destroy() -- war nur die Bauvorlage im echten Haus, jetzt nicht mehr gebraucht
		ruinTemplates[house] = template
	else
		print("[Kaiju-Debug] prepareRuinTemplate: kein RuinModel, baue automatischen Schutt")
		ruinTemplates[house] = buildFallbackRuin(house)
	end
end

-- Zeigt die Ruine an (Klon der Vorlage, an derselben Position wie das echte Haus).
local function showRuin(house)
	local template = ruinTemplates[house]
	if not template then
		print("[Kaiju-Debug] showRuin: keine Vorlage vorhanden für '" .. house.Name .. "'")
		return
	end
	if activeRuins[house] then
		print("[Kaiju-Debug] showRuin: schon eine aktive Ruine vorhanden, überspringe")
		return
	end

	local ruinClone = template:Clone()
	print("[Kaiju-Debug] showRuin: zeige Ruine mit " .. #ruinClone:GetDescendants() .. " Descendants")
	ruinClone.Parent = workspace
	activeRuins[house] = ruinClone
end

-- Entfernt die Ruine wieder (wenn das echte Haus respawnt).
local function hideRuin(house)
	local ruin = activeRuins[house]
	if ruin then
		ruin:Destroy()
		activeRuins[house] = nil
	end
end

-- Energie-Typ-Skin: ausgelagert nach EnergyTypeSkin.lua (siehe dort für Details) --
-- applyEnergyTypeSkin(house) unten ist nur noch ein dünner Wrapper für Kompatibilität
-- mit den bestehenden Aufrufstellen in dieser Datei.
local function applyEnergyTypeSkin(house)
	EnergyTypeSkin.Apply(house)
end

-- L3-ParentGroup-System (Häuser, die aus mehreren Teilen bestehen, aber gemeinsam
-- respawnen -- z.B. das Roadside Motel) ist jetzt in ParentGroupService.lua ausgelagert.
-- Siehe dort für Details. Wird über die schmale API (Register/IsParentGroupHouse/
-- GetGroup/ScheduleRespawn) genutzt.

local function initHouse(house)
	if not house:IsA("Model") then
		warn("'" .. house.Name .. "' hat den Tag '" .. HOUSE_TAG .. "', ist aber kein Model. Bitte gruppieren.")
		return
	end

	-- L3-Sektionen registrieren, solange sie noch unter ihrem gemeinsamen Asset-Root liegen.
	-- Der Bezug bleibt danach in ParentGroupService erhalten, auch wenn setHouseVisible()
	-- die zerstörte Sektion temporär nach ServerStorage.HiddenHouses verschiebt.
	ParentGroupService.Register(house)

	-- CanCollide für ALLE Haus-Teile erzwingen (true), egal was in Studio konfiguriert
	-- war -- manche importierten/gebauten Modelle hatten einzelne Teile mit CanCollide =
	-- false, wodurch man an genau diesen Stellen durch das (noch nie zerstörte!) Haus
	-- laufen konnte. Häuser sollen in diesem Spiel immer komplett solide sein.
	-- Zusätzlich wird die ursprüngliche CFrame jedes Teils gesichert -- die Einsturz-
	-- Animation beim Zerstören verschiebt/verdreht die Teile einzeln, und beim Respawn
	-- muss jedes Teil wieder an seinen korrekten Platz zurück (nicht nur das ganze Model).
	local fixedCollisionCount = 0
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") and not part:GetAttribute("IsTechnicalPart") then
			if not part.CanCollide then
				fixedCollisionCount += 1
			end
			part.CanCollide = true
			part.CanTouch = true
			part:SetAttribute("OriginalCanCollide", true)
			part:SetAttribute("OriginalCanTouch", true)
			if part:GetAttribute("OriginalCFrame") == nil then
				part:SetAttribute("OriginalCFrame", part.CFrame)
			end
		end
	end
	if fixedCollisionCount > 0 then
		warn("[Kaiju] " .. fixedCollisionCount .. " Teil(e) von '" .. house:GetFullName() .. "' hatten CanCollide=false in Studio -- automatisch auf true korrigiert.")
	end

	if not house.PrimaryPart then
		-- Sucht ein Teil, das NICHT innerhalb eines "RuinModel"-Kindes liegt (falls vorhanden) --
		-- sonst könnte der Anker versehentlich auf ein Ruinen-Teil zeigen, das später
		-- beim Vorbereiten der Ruinen-Vorlage gelöscht wird (und der Lebensbalken verschwindet mit).
		for _, descendant in ipairs(house:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local isInsideRuin = false
				local ancestor = descendant.Parent
				while ancestor and ancestor ~= house do
					if ancestor.Name == "RuinModel" then
						isInsideRuin = true
						break
					end
					ancestor = ancestor.Parent
				end

				if not isInsideRuin then
					house.PrimaryPart = descendant
					break
				end
			end
		end
	end

	-- Energie-Typ-Skin (Einfärbung + Leuchten + Symbol), falls das Haus ein
	-- "EnergyType"-Attribut ungleich "Heat" trägt -- braucht PrimaryPart, daher erst
	-- jetzt, nachdem es feststeht.
	applyEnergyTypeSkin(house)

	-- Ursprünglichen Scale EINMALIG merken (z.B. 1.5, falls das Haus manuell größer
	-- gebaut wurde) -- sonst würde die Wachstums-Animation beim Respawn fälschlich auf
	-- 1.0 zurücksetzen, statt die eigentliche Zielgröße zu behalten. Mit pcall abgesichert
	-- als zusätzliches Sicherheitsnetz.
	if not house:GetAttribute("OriginalScale") then
		local scaleOk, currentScale = pcall(function()
			return house:GetScale()
		end)
		house:SetAttribute("OriginalScale", scaleOk and currentScale or 1)
		if not scaleOk then
			warn("[Kaiju] Konnte Scale von '" .. house:GetFullName() .. "' nicht lesen, nutze 1 als Standard.")
		end
	end

	if not house:GetAttribute("MaxHealth") then
		house:SetAttribute("MaxHealth", DEFAULT_HEALTH)
	end
	if house:GetAttribute("Health") == nil then
		house:SetAttribute("Health", house:GetAttribute("MaxHealth"))
	end
	-- CoinsReward nur automatisch setzen, falls nicht schon manuell in Studio vorgegeben
	if not house:GetAttribute("CoinsReward") then
		house:SetAttribute("CoinsReward", rewardFromHP(house:GetAttribute("MaxHealth"), COINS_SCALE))
	end
	house:SetAttribute("Destroyed", false)

	-- City-Alert-System: Stadt-Zugehörigkeit EINMALIG jetzt auflösen (während das Haus
	-- noch an seinem echten Platz unter Workspace.Cities.* steht) und DIREKT am Haus
	-- als Attribut sichern. Ohne das würde die Ahnenketten-Suche fehlschlagen, sobald
	-- das Haus beim Zerstören nach ServerStorage.HiddenHouses verschoben wird (siehe
	-- setHouseVisible weiter unten) -- das eigene Attribut überlebt jedes Verschieben.
	-- Läuft async mit kurzem Retry, falls CityAlertService.lua noch nicht geladen ist
	-- (Script-Reihenfolge in ServerScriptService ist nicht garantiert).
	if not house:GetAttribute("CityName") then
		task.spawn(function()
			local attempts = 0
			while not _G.ResolveCityName and attempts < 50 do
				task.wait(0.1)
				attempts += 1
			end
			if _G.ResolveCityName and not house:GetAttribute("CityName") then
				local resolvedCity = _G.ResolveCityName(house)
				if resolvedCity then
					house:SetAttribute("CityName", resolvedCity)
				end
			end
		end)
	end

	-- Räumt evtl. angesammelte doppelte Balken auf (z.B. von früheren Sessions, die
	-- zwischendurch gespeichert wurden) -- danach existiert garantiert nur noch einer.
	for _, existingBar in ipairs(house:GetDescendants()) do
		if existingBar.Name == "HouseHealthBar" then
			existingBar:Destroy()
		end
	end

	if house.PrimaryPart then
		createHealthBar(house)
	end
	updateHealthBar(house)

	if house.PrimaryPart and not house.PrimaryPart:FindFirstChild("ImpactSound") then
		local impactSound = Instance.new("Sound")
		impactSound.Name = "ImpactSound"
		impactSound.SoundId = HOUSE_IMPACT_SOUND_ID
		impactSound.Volume = 0.8
		impactSound.Parent = house.PrimaryPart
	end

	house:GetAttributeChangedSignal("Health"):Connect(function()
		updateHealthBar(house)
	end)

	-- Für das Anrenn-/Dach-/Sprung-Schaden-System:
	-- 1) alle bereits vorhandenen Teile verbinden
	-- 2) auch später hinzukommende Parts via DescendantAdded verbinden.
	for _, part in ipairs(house:GetDescendants()) do
		connectHouseTouchPart(house, part)
	end

	if not houseDescendantConnections[house] then
		houseDescendantConnections[house] = house.DescendantAdded:Connect(function(descendant)
			if not descendant:IsA("BasePart") then
				return
			end

			if not descendant:GetAttribute("IsTechnicalPart") then
				-- Neue echte Gebäudeteile genauso behandeln wie Teile, die beim initHouse()
				-- bereits vorhanden waren.
				descendant.CanCollide = true
				descendant.CanTouch = true
				descendant:SetAttribute("OriginalCanCollide", true)
				descendant:SetAttribute("OriginalCanTouch", true)
				if descendant:GetAttribute("OriginalCFrame") == nil then
					descendant:SetAttribute("OriginalCFrame", descendant.CFrame)
				end
			end

			connectHouseTouchPart(house, descendant)
		end)
	end
end

-- Blendet das Haus komplett aus (visible=false) bzw. wieder ein (visible=true), indem
-- es aus/in die Workspace-Hierarchie verschoben wird. Das ist zuverlässiger als nur
-- Transparency zu setzen, weil dabei WIRKLICH alles verschwindet (auch Decals, SurfaceGuis,
-- Unions mit Sonderfällen, etc.) und nichts sichtbar hängen bleiben kann.
local function setHouseVisible(house, visible)
	local billboard = house.PrimaryPart and house.PrimaryPart:FindFirstChild("HouseHealthBar")

	if visible then
		house.Parent = originalParents[house] or house.Parent
		originalParents[house] = nil
	else
		originalParents[house] = house.Parent
		house.Parent = hiddenHousesFolder
	end

	if billboard then
		billboard.Enabled = visible
	end
end

-- Lässt das Haus beim Respawn wieder erscheinen: kehrt die Einsturz-Bewegung jedes
-- einzelnen Teils um (Tween zurück zur Original-CFrame), statt aus dem Boden zu wachsen.
-- Erst wenn alle Teile wieder korrekt sitzen, wird die Kollision reaktiviert.
local function growHouseFromGround(house)
	-- Transparenz sofort zurücksetzen (sonst wäre die folgende Animation unsichtbar) und
	-- Kollision während der Animation deaktivieren, damit niemand an den zurückkippenden
	-- Teilen "kleben" bleibt.
	local partsToRestore = {}
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") and not part:GetAttribute("IsTechnicalPart") then
			part.Transparency = 0
			part.CanCollide = false
			table.insert(partsToRestore, part)
		end
	end

	-- Einsturz-Bewegung umkehren: jedes Teil tweent von seiner aktuellen (eingestürzten,
	-- gekippten) CFrame zurück zur ursprünglichen -- sieht wie ein "Wiederaufrichten" aus,
	-- quasi die Einsturz-Animation rückwärts. Ersetzt die frühere Skalier-Wachstums-
	-- Animation komplett.
	local uncollapseTweens = {}
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") then
			local originalCFrame = part:GetAttribute("OriginalCFrame")
			if originalCFrame then
				local tween = TweenService:Create(
					part,
					TweenInfo.new(HOUSE_UNCOLLAPSE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = originalCFrame }
				)
				table.insert(uncollapseTweens, tween)
			end
		end
	end
	for _, tween in ipairs(uncollapseTweens) do
		tween:Play()
	end
	task.wait(HOUSE_UNCOLLAPSE_DURATION)

	-- Nach der Animation JEDES Teil explizit auf die exakte gespeicherte Original-CFrame
	-- setzen (nicht nur auf das Tween-Ergebnis verlassen) -- garantiert, dass am Ende
	-- wirklich die Original-Attribute gelten, ganz ohne Rundungs-/Interpolations-Abweichung.
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") then
			local originalCFrame = part:GetAttribute("OriginalCFrame")
			if originalCFrame then
				part.CFrame = originalCFrame
			end
		end
	end

	-- Kollision wiederherstellen (vom Attribut, das initHouse() dauerhaft gesichert hat).
	for _, part in ipairs(partsToRestore) do
		if part.Parent then
			local original = part:GetAttribute("OriginalCanCollide")
			part.CanCollide = (original == nil) or original

			local originalCanTouch = part:GetAttribute("OriginalCanTouch")
			part.CanTouch = (originalCanTouch == nil) or originalCanTouch
		end
	end
end

-- ParentGroupService braucht Zugriff auf diese vier lokalen Funktionen + zwei Konstanten
-- -- jetzt injizieren, da alle vier ab hier garantiert definiert sind.
ParentGroupService.Init({
	extinguishHouseFire = extinguishHouseFire,
	hideRuin = hideRuin,
	setHouseVisible = setHouseVisible,
	growHouseFromGround = growHouseFromGround,
	DEFAULT_HEALTH = DEFAULT_HEALTH,
	RESPAWN_TIME = RESPAWN_TIME,
})

-- Lässt die einzelnen Hausteile in sich zusammenstürzen (kippen + nach unten sinken),
-- während sie gleichzeitig verblassen -- statt einfach nur transparent zu werden. Nutzt
-- Tweens statt echter Physik, damit nichts unkontrolliert durch die Karte fliegt/fällt.
local function collapseHouse(house, duration)
	-- Debug-Schalter: überspringt die komplette Einsturz-Animation, alle Teile werden
	-- sofort in ihren Endzustand versetzt (unsichtbar, keine Kollision) -- praktisch, um
	-- beim Testen schneller durch mehrere Zerstörungs-Zyklen zu kommen.
	if _G.DebugSkipCollapseAnimation then
		for _, part in ipairs(house:GetDescendants()) do
			if part:IsA("BasePart") and not part:GetAttribute("IsTechnicalPart") then
				part.CanCollide = false
				part.Transparency = 1
			end
		end
		return
	end

	local ok, boundsCFrame, boundsSize = pcall(function()
		return house:GetBoundingBox()
	end)
	local groundY = ok and (boundsCFrame.Position.Y - boundsSize.Y / 2) or nil

	local parts = {}
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") and not part:GetAttribute("IsTechnicalPart") then
			part.CanCollide = false
			table.insert(parts, part)
		end
	end

	for _, part in ipairs(parts) do
		local startCFrame = part.CFrame
		local targetY = groundY or (startCFrame.Position.Y - 3)

		-- Zufällige Kipp-Rotation + seitlicher Versatz + Absinken auf Bodenhöhe
		local tilt = CFrame.Angles(math.rad(math.random(-70, 70)), math.rad(math.random(-180, 180)), math.rad(math.random(-70, 70)))
		local horizontalOffset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
		local targetPosition = Vector3.new(startCFrame.Position.X, targetY, startCFrame.Position.Z) + horizontalOffset
		local targetCFrame = CFrame.new(targetPosition) * tilt

		-- Kleine zufällige Verzögerung pro Teil, damit der Einsturz nicht wie ein starres
		-- Ganzes wirkt, sondern Stück für Stück passiert.
		local partDelay = math.random(0, 40) / 100

		task.delay(partDelay, function()
			if not part.Parent then
				return
			end
			local remainingDuration = math.max(duration - partDelay, 0.1)
			local tween = TweenService:Create(
				part,
				TweenInfo.new(remainingDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = targetCFrame, Transparency = 1 }
			)
			tween:Play()
		end)
	end

	task.wait(duration)
end

-- ===== Respawn-Warteschlange: verhindert, dass mehrere gleichzeitig zerstörte Häuser
-- exakt gleichzeitig respawnen (wirkt sonst wie ein unrealistischer "Pop" aller auf
-- einmal). Häuser, deren RESPAWN_TIME abgelaufen ist, reihen sich hier ein -- ein
-- separater Prozessor arbeitet sie mit kleinem Abstand nacheinander ab.
local RESPAWN_STAGGER_DELAY = 0.35 -- Sekunden zwischen zwei aufeinanderfolgenden Respawns
local respawnQueue = {}

local function performRespawn(house)
	extinguishHouseFire(house)

	local maxHealthAtRespawn = house:GetAttribute("MaxHealth")
	if maxHealthAtRespawn == nil then
		warn("[Kaiju-Debug] Respawn von '" .. house:GetFullName() .. "': MaxHealth war nil! Setze auf " .. DEFAULT_HEALTH)
		maxHealthAtRespawn = DEFAULT_HEALTH
		house:SetAttribute("MaxHealth", maxHealthAtRespawn)
	end

	house:SetAttribute("Health", maxHealthAtRespawn)
	house:SetAttribute("Destroyed", false)
	hideRuin(house)
	setHouseVisible(house, true)

	-- Energie-Typ-Überraschung neu würfeln (nur Heat-Gebäude betroffen, siehe
	-- EnergyCollectionHandler.lua) -- jeder Respawn ist eine neue Gelegenheit für einen
	-- anderen Typ, Optik wird entsprechend aktualisiert (inkl. Zurücksetzen, falls die
	-- vorherige Überraschung nicht erneut zutrifft).
	applyEnergyTypeSkin(house)

	-- Alert-Level-1-Helikopter (siehe AlertHelicopterService.lua): Gebäude ist wieder
	-- intakt, fällt also als möglicher Brennpunkt weg. Der nächststärkste noch zerstörte
	-- Gebäude übernimmt automatisch, falls dieses hier gerade der Brennpunkt war.
	local cityName = house:GetAttribute("CityName")
	if cityName and _G.UnregisterDestroyedBuildingForHelicopter then
		_G.UnregisterDestroyedBuildingForHelicopter(cityName, house)
	end

	-- Wasserturm ist wieder intakt -- Feuerwehr-Bonus für diese Stadt wiederherstellen.
	if house:GetAttribute("HeatEffect") == "WaterTower" and _G.RestoreWaterTowerBonus then
		_G.RestoreWaterTowerBonus(house)
	end

	task.spawn(function()
		growHouseFromGround(house)
	end)
end

local respawnQueueRunning = false
local function processRespawnQueue()
	if respawnQueueRunning then
		return -- läuft schon -- kein zweiter Prozessor nötig
	end
	respawnQueueRunning = true

	task.spawn(function()
		while #respawnQueue > 0 do
			local house = table.remove(respawnQueue, 1)
			if house then
				performRespawn(house)
			end
			task.wait(RESPAWN_STAGGER_DELAY)
		end
		respawnQueueRunning = false
	end)
end

-- L3-ParentGroup-Wahrzeichen-Optik + Respawn-Logik ebenfalls in ParentGroupService.lua
-- ausgelagert (siehe Kommentar weiter oben).
-- ===== Kollaps-Warteschlange (Performance) =========================================
-- Jedes einstürzende Haus tweent JEDES seiner Teile einzeln (Position + Rotation +
-- Transparenz) -- bei vielen gleichzeitig zerstörten Gebäuden (z.B. Flächenangriff, der
-- ein Dutzend Häuser auf einmal trifft) entstehen dadurch hunderte gleichzeitige
-- Server-Tweens, deren Positionsänderungen JEDEN FRAME an alle Clients repliziert werden
-- müssen -- das kann zu spürbarem Ruckeln/Einfrieren führen.
--
-- Diese Warteschlange begrenzt, wie viele Häuser GLEICHZEITIG die volle, teure
-- Animation abspielen (MAX_SIMULTANEOUS_COLLAPSES). Weitere Häuser warten, bis ein Slot
-- frei wird. WICHTIG: die Warteschlange ist nach Distanz zum Epizentrum sortiert (nicht
-- FIFO) -- bei einem Flächenangriff bekommt das NÄCHSTGELEGENE Haus zum Explosionspunkt
-- immer den nächsten freien Slot zuerst. Das erzeugt den gewünschten "Schockwellen"-
-- Effekt: die Zerstörung breitet sich sichtbar vom Epizentrum nach aussen aus, statt in
-- zufälliger Reihenfolge zu passieren.
local MAX_SIMULTANEOUS_COLLAPSES = 8
local activeCollapseCount = 0
local pendingCollapseQueue = {} -- { { distance = number, runFullSequence = function }, ... }

-- Kleiner zufälliger Zeitversatz (Sekunden) vor dem tatsächlichen Start jeder einzelnen
-- Kollaps-Sequenz -- bricht die Synchronität auf: OHNE diesen Versatz werden mehrere
-- gleichzeitig gestartete Häuser (feste Dauer) auch alle gleichzeitig fertig, wodurch die
-- nächste Gruppe wieder synchron nachrückt ("3, dann 3, dann 3"-Stufen-Effekt). MIT dem
-- Versatz überlappen sich die Sequenzen kontinuierlich, neue Häuser rücken einzeln/in
-- kleinen, zeitlich versetzten Gruppen nach, statt in starren Batches.
local COLLAPSE_START_JITTER_MIN = 0.1
local COLLAPSE_START_JITTER_MAX = 0.6

local tryStartNextQueuedCollapse -- vorab deklariert (rekursiver Selbstaufruf weiter unten)

local function startCollapseSequence(runFullSequence)
	activeCollapseCount += 1
	-- WICHTIG: task.defer statt task.spawn -- task.spawn führt die übergebene Funktion
	-- SYNCHRON aus, bis zum ERSTEN Yield-Punkt (z.B. task.wait()), und kehrt ERST DANN
	-- zum Aufrufer zurück. Da collapseHouse() ganz am Ende ein task.wait(duration) (1.1s)
	-- hat, blockierte JEDER Start einer neuen Kollaps-Animation die AUFRUFENDE Schleife
	-- (z.B. die Flächenschaden-Schleife in SpecialAttackHandler.lua) für über eine
	-- Sekunde -- bei MAX_SIMULTANEOUS_COLLAPSES=3 also bis zu ~3.3s Blockade, wodurch
	-- weiter entfernte Häuser scheinbar nie mehr an die Reihe kamen. task.defer plant die
	-- Ausführung stattdessen für den nächsten Fortsetzungszyklus ein -- der Aufrufer läuft
	-- garantiert sofort weiter, unabhängig davon, was runFullSequence() intern tut.
	task.defer(function()
		task.wait(math.random() * (COLLAPSE_START_JITTER_MAX - COLLAPSE_START_JITTER_MIN) + COLLAPSE_START_JITTER_MIN)
		runFullSequence()
		activeCollapseCount -= 1
		tryStartNextQueuedCollapse()
	end)
end

tryStartNextQueuedCollapse = function()
	if activeCollapseCount >= MAX_SIMULTANEOUS_COLLAPSES or #pendingCollapseQueue == 0 then
		return
	end

	-- Nächstgelegenes wartendes Haus zum jeweiligen Epizentrum finden (lineare Suche --
	-- die Warteschlange bleibt auch bei grossen Flächenangriffen klein genug, das lohnt
	-- keine komplexere Datenstruktur).
	local bestIndex = 1
	local bestDistance = pendingCollapseQueue[1].distance
	for i = 2, #pendingCollapseQueue do
		if pendingCollapseQueue[i].distance < bestDistance then
			bestDistance = pendingCollapseQueue[i].distance
			bestIndex = i
		end
	end

	local entry = table.remove(pendingCollapseQueue, bestIndex)
	startCollapseSequence(entry.runFullSequence)
end

-- house: das betroffene Haus-Model (nur für die Distanzberechnung zum Epizentrum nötig)
-- originPosition: Vector3 des Angriffs-Epizentrums, oder nil falls nicht bekannt (z.B.
-- normaler Einzelschaden ohne Flächeneffekt -- bekommt Distanz 0, also höchste Priorität)
-- runFullSequence: Funktion, die die KOMPLETTE visuelle Zerstörungs-Sequenz synchron
-- ausführt (Einsturz-Animation, Explosion, Feuer, Ruine) -- wird entweder sofort
-- gestartet oder in die Warteschlange eingereiht, je nachdem ob noch ein Slot frei ist.
local function requestHouseCollapse(house, originPosition, runFullSequence)
	local distance = 0
	if originPosition then
		local ok, cframe = pcall(function()
			return house:GetPivot()
		end)
		if ok then
			distance = (cframe.Position - originPosition).Magnitude
		end
	end

	if activeCollapseCount < MAX_SIMULTANEOUS_COLLAPSES then
		startCollapseSequence(runFullSequence)
	else
		table.insert(pendingCollapseQueue, { distance = distance, runFullSequence = runFullSequence })
	end
end

local function destroyHouse(house, destroyerPlayer, originPosition)
	house:SetAttribute("Destroyed", true)
	local isGroupSection = ParentGroupService.IsParentGroupHouse(house)
	local parentGroup = ParentGroupService.GetGroup(house)
	if isGroupSection then
		house:SetAttribute("SectionDestroyed", true)
		house:SetAttribute("RespawnEligible", false)
	end
	extinguishHouseFire(house) -- falls von einer vorherigen Zerstörung noch was brennt

	-- Prolog-Isolation: Spieler im Prolog (siehe StoryBeatService/Prolog-Handler) bekommen
	-- KEINE echten Belohnungen (Coins, XP, Evolution, Achievements, Special Energy) --
	-- der Prolog-Kaiju ist ein temporärer, vom echten Fortschritt komplett getrennter
	-- Zustand. Alert-System/Eskalation bleibt davon unberührt (soll ja gerade im Prolog
	-- erlebt werden), nur die PROGRESSION wird blockiert.
	local isProloguePlayer = destroyerPlayer and destroyerPlayer:GetAttribute("IsInPrologue") == true

	-- Achievements: Zähler für "X Gebäude zerstört".
	-- Lebensstatistik: gezaehlt werden die getaggten SEKTIONEN, nicht ganze Bauwerke --
	-- ein Asset wie die Marina traegt 7 KaijuHouse-Tags und zaehlt als 7. Entspricht dem,
	-- was die Achievement-Schwellen schon tun.
	if destroyerPlayer and not isProloguePlayer and _G.RecordStat then
		_G.RecordStat(destroyerPlayer, "BuildingsDestroyed")
		local statCity = _G.ResolveCityName and _G.ResolveCityName(house)
		if statCity then
			_G.RecordStat(destroyerPlayer, "BuildingsDestroyed." .. statCity)
		end
	end

	if destroyerPlayer and not isProloguePlayer and _G.OnBuildingDestroyedForAchievements then
		_G.OnBuildingDestroyedForAchievements(destroyerPlayer)
	end

	-- Special Energy: fester Bonus bei tatsächlicher Zerstörung. Läuft auch im Prolog
	-- (Spieler soll dort Energie für Spezialangriffe sammeln können) -- nur Achievements
	-- oben bleiben blockiert.
	if destroyerPlayer and _G.AwardSpecialEnergyForBuildingDestroyed then
		_G.AwardSpecialEnergyForBuildingDestroyed(destroyerPlayer)
	end

	-- Heat-System: manche besondere Gebäude (Kirche, Wasserturm, Spital, ...) haben einen
	-- eigenen Heat-Effekt beim Einsturz -- per Attribut "HeatEffect" am Model markiert
	-- (siehe HeatHandler.lua, _G.ApplyBuildingHeatEffect für die möglichen Werte).
	if destroyerPlayer and _G.ApplyBuildingHeatEffect then
		local heatEffect = house:GetAttribute("HeatEffect")
		if heatEffect then
			_G.ApplyBuildingHeatEffect(destroyerPlayer, heatEffect)
		end
	end

	-- City-Alert-System: jede Zerstörung erhöht den Alert-Fortschritt DIESER Stadt (siehe
	-- CityAlertService.lua -- löst die Stadt automatisch über ein "CityName"-Attribut an
	-- einem Vorfahren auf). Alert-Wert kommt aus einem optionalen "AlertValue"-Attribut
	-- am Haus, sonst automatisch aus MaxHealth berechnet.
	if _G.AddCityAlertForBuilding then
		_G.AddCityAlertForBuilding(house)
	end

	-- Eskalations-System (Stufe 3/4, siehe EscalationService.lua): Zerstörung zählt für
	-- den weiterlaufenden Chaos-Wert, unabhängig vom Alert-Fortschritt selbst. cityName
	-- wird über dasselbe "CityName"-Attribut an einem Vorfahren aufgelöst wie beim
	-- normalen Alert-System.
	if _G.RegisterEscalationEvent then
		local cityNamePart = house
		local cityName = nil
		while cityNamePart do
			cityName = cityNamePart:GetAttribute("CityName")
			if cityName then
				break
			end
			cityNamePart = cityNamePart.Parent
		end
		if cityName then
			local destroyPosition = house.PrimaryPart and house.PrimaryPart.Position or house:GetPivot().Position
			_G.RegisterEscalationEvent(cityName, destroyPosition, "destroy")
		end
	end

	-- Alert-Level-1-Helikopter (siehe AlertHelicopterService.lua): trackt das GRÖSSTE
	-- (nach MaxHealth) bisher zerstörte Gebäude + den letzten Angreifer pro Stadt -- beide
	-- sind die zwei Brennpunkte der Ellipsen-Flugbahn. WICHTIG: bewusst UNABHÄNGIG von
	-- _G.RegisterEscalationEvent -- war vorher fälschlich darin verschachtelt, wodurch der
	-- Helikopter-Hook nie liefe, falls EscalationService.lua aus irgendeinem Grund nicht
	-- verfügbar ist (hat mit dem Helikopter inhaltlich nichts zu tun).
	if _G.RegisterDestroyedBuildingForHelicopter then
		local cityNamePart = house
		local cityName = nil
		while cityNamePart do
			cityName = cityNamePart:GetAttribute("CityName")
			if cityName then
				break
			end
			cityNamePart = cityNamePart.Parent
		end
		if cityName then
			local destroyPosition = house.PrimaryPart and house.PrimaryPart.Position or house:GetPivot().Position
			local ok, _, houseSize = pcall(function()
				return house:GetBoundingBox()
			end)
			local buildingHeight = (ok and houseSize and houseSize.Y) or 0
			_G.RegisterDestroyedBuildingForHelicopter(cityName, house, destroyPosition, house:GetAttribute("MaxHealth") or 0, destroyerPlayer, buildingHeight)
		end
	end

	-- Wasserturm-Sonderfall: entfernt beim Zerstören den Feuerwehr-Löschbonus für die
	-- Stadt, in der er steht (siehe FireEngineController.lua, WaterTowerBonusActive).
	-- Der bestehende Kühleffekt oben (HeatEffect="WaterTower") bleibt davon unberührt --
	-- das ist ein bewusster strategischer Trade-off: kühlt den Spieler, schwächt aber
	-- gleichzeitig die Feuerwehr dieser Stadt.
	if house:GetAttribute("HeatEffect") == "WaterTower" and _G.RemoveWaterTowerBonus then
		_G.RemoveWaterTowerBonus(house)
	end

	-- WICHTIG: Vorlage JETZT bauen (Geometrie ist garantiert vorhanden/geladen, da der
	-- Spieler das Haus gerade angegriffen hat) und BEVOR das Ausblenden unten die
	-- Transparenz der echten Teile verändert -- sonst würde der Schutt das unsichtbar
	-- gewordene Aussehen erben.
	prepareRuinTemplate(house)

	local ok, cframe, size = pcall(function()
		return house:GetBoundingBox()
	end)
	local groundCFrame = ok
		and CFrame.new(cframe.Position.X, cframe.Position.Y - size.Y / 2 + EXPLOSION_HEIGHT_OFFSET, cframe.Position.Z)
		or house:GetPivot()
	-- Eigene Position fürs Feuer, OHNE den Höhenversatz der Explosion -- das Feuer soll
	-- direkt auf dem Boden/der Ruine sitzen, nicht angehoben in der Luft schweben.
	local fireGroundCFrame = ok
		and CFrame.new(cframe.Position.X, cframe.Position.Y - size.Y / 2, cframe.Position.Z)
		or house:GetPivot()

	if _G.GrantExplosionEnergy then
		_G.GrantExplosionEnergy(house, groundCFrame.Position)
	end

	requestHouseCollapse(house, originPosition, function()
		-- WICHTIG: Staubwolke + Einschlag-Sound laufen jetzt HIER (innerhalb der ggf.
		-- verzögerten Warteschlangen-Sequenz), NICHT mehr sofort beim Zerstören selbst --
		-- sonst hätte man bei vielen gleichzeitig zerstörten Häusern (z.B. Flächenangriff)
		-- den Staub/Sound sofort gesehen, während das Gebäude optisch noch länger stand
		-- und erst viel später (wenn die Warteschlange dran kam) tatsächlich einstürzte.
		-- Jetzt startet alles synchron zusammen, egal ob sofort oder verzögert.
		if ok then
			local groundPosition = Vector3.new(cframe.Position.X, cframe.Position.Y - size.Y / 2, cframe.Position.Z)
			playDustCloudEffect(groundPosition, size)
			playDestructionSound(groundPosition)
		end

		collapseHouse(house, HOUSE_COLLAPSE_DURATION)
		setHouseVisible(house, false)
		showRuin(house)
		-- Explizite Reihenfolge: erst der Staubwirbel (oben), dann -- mit spürbarem
		-- Abstand -- die Explosion und das Feuer mit Rauch. Ohne diese Pause würden
		-- Staub und Feuer praktisch gleichzeitig erscheinen.
		task.wait(0.9)
		playExplosionEffect(house)

		-- "PermanentlyDestroyed"-Attribut hat drei mögliche Zustände (String):
		--   nil/fehlt        -- normales Spiel, unverändertes Verhalten
		--   "Burning"        -- dauerhaft zerstört, brennt/raucht unendlich lange, ABER
		--                       ganz normal von Feuerwehr-Fahrzeugen löschbar (keine
		--                       Ausnahme -- einmal gelöscht, bleibt es gelöscht)
		--   "Clean"          -- dauerhaft zerstört, nur Ruine, GAR KEIN Feuer
		local ruinType = house:GetAttribute("PermanentlyDestroyed")
		if ruinType == "Clean" then
			-- Nur Ruine -- kein Feuer, kein Rauch, keine Registrierung nötig.
		else
			local fireEnergyDuration = isGroupSection and GROUP_SECTION_ENERGY_TIME or RESPAWN_TIME
			if ruinType == "Burning" then
				fireEnergyDuration = 315360000 -- ~10 Jahre in Sekunden -- praktisch "brennt für immer" (task.delay akzeptiert kein math.huge, würde sonst fälschlich sofort statt nie auslösen)
			end
			startHouseFire(house, fireGroundCFrame, fireEnergyDuration)
			-- WICHTIG: ganz normal registriert -- Feuerwehr-Fahrzeuge können und sollen
			-- auch "Burning"-Ruinen wie jedes andere brennende Haus finden und löschen,
			-- keine Ausnahme.
			if _G.RegisterFireEnergySource then
				_G.RegisterFireEnergySource(house, fireGroundCFrame.Position, fireEnergyDuration)
			end
		end
		-- Firefighter Extinguishing Feedback: Anzeige sofort bei 0% zeigen, sobald das
		-- Gebäude zu brennen beginnt -- nicht erst, wenn tatsächlich ein Fahrzeug mit dem
		-- Löschen beginnt. Bei "Clean"-Ruinen (kein Feuer) ergibt eine Lösch-Anzeige
		-- keinen Sinn -- übersprungen.
		if ruinType ~= "Clean" and _G.ShowExtinguishBillboard then
			_G.ShowExtinguishBillboard(house)
		end

		-- Individueller Respawn-Timer (nur für NICHT-Gruppen-Häuser -- ParentGroup-
		-- Sektionen respawnen gemeinsam über ParentGroupService.ScheduleRespawn, siehe unten).
		-- WICHTIG: startet jetzt HIER, synchron mit dem tatsächlichen Beginn DIESER
		-- Kollaps-Sequenz -- nicht mehr beim ursprünglichen Zerstören. Bei einem
		-- Flächenangriff respawnen dadurch die Häuser, die zuerst eingestürzt sind
		-- (näher am Epizentrum), auch zuerst -- konsistent zur sichtbaren Reihenfolge.
		-- "PermanentlyDestroyed": dauerhaft als Ruine markierte Häuser (z.B. Prolog-
		-- Kulisse, siehe PrologueOrchestrator.lua) bekommen NIE einen Respawn-Timer.
		if not isGroupSection and not house:GetAttribute("PermanentlyDestroyed") then
			task.delay(RESPAWN_TIME, function()
				if house then
					table.insert(respawnQueue, house)
					processRespawnQueue()
				end
			end)
		end
	end)

	if destroyerPlayer and not isProloguePlayer then
		local leaderstats = destroyerPlayer:FindFirstChild("leaderstats")
		if leaderstats and leaderstats:FindFirstChild("Coins") then
			local reward = house:GetAttribute("CoinsReward")

			-- Evolution-Money-Bonus anwenden
			local evoMoneyLevel = destroyerPlayer:FindFirstChild("EvoMoneyLevel")
			if evoMoneyLevel and _G.EVO_BONUS_PER_LEVEL then
				reward = math.floor(reward * (1 + evoMoneyLevel.Value * _G.EVO_BONUS_PER_LEVEL))
			end

			-- Temporären Coins-Boost anwenden (z.B. aus einem Geschenk), falls aktiv
			local coinsBoostEndsAt = destroyerPlayer:GetAttribute("CoinsBoostEndsAt") or 0
			if workspace:GetServerTimeNow() < coinsBoostEndsAt then
				reward = math.floor(reward * (destroyerPlayer:GetAttribute("CoinsBoostMultiplier") or 1))
			end

			leaderstats.Coins.Value += reward
			if _G.RecordStat then
				_G.RecordStat(destroyerPlayer, "CoinsCollected", reward)
			end

			local originPosition = house.PrimaryPart and house.PrimaryPart.Position or house:GetPivot().Position
			CoinsEarnedEvent:FireClient(destroyerPlayer, reward, originPosition)
		end

		-- Energie (vormals: XP) gibt es NICHT mehr instant -- siehe EnergyCollectionHandler.lua:
		-- Ein Teil kommt sofort über die Explosion (an alle Spieler in der Nähe), der Rest
		-- kontinuierlich übers Feuer. Ausgelöst weiter unten bei playExplosionEffect/startHouseFire.

		-- Evolution-Punkte vergeben
		local evolutionPoints = destroyerPlayer:FindFirstChild("EvolutionPoints")
		if evolutionPoints then
			evolutionPoints.Value += rewardFromHP(house:GetAttribute("MaxHealth"), EVOLUTION_SCALE)
		end
	end

	if isGroupSection then
		-- WICHTIG: KEIN individueller Timer für diesen Trakt. Erst wenn der letzte
		-- Trakt zerstört wurde, startet ParentGroupService.ScheduleRespawn() EINEN Gruppentimer.
		if parentGroup then
			ParentGroupService.ScheduleRespawn(parentGroup)
		else
			warn("[HouseHandler] ParentGroup-Sektion '" .. house:GetFullName() .. "' hat keinen registrierten Gruppen-Root -- kein Einzelrespawn gestartet.")
		end
	end
	-- WICHTIG: Der individuelle Respawn-Timer für NICHT-Gruppen-Häuser startet jetzt
	-- INNERHALB der Kollaps-Warteschlangen-Sequenz weiter oben (siehe requestHouseCollapse-
	-- Aufruf), NICHT mehr hier -- sonst würde der Respawn-Countdown schon beim ursprünglichen
	-- Zerstören starten, unabhängig davon, wann die Kollaps-Animation tatsächlich beginnt.
	-- Bei einem Flächenangriff, der viele Häuser gleichzeitig zerstört, respawnen dadurch
	-- jetzt die Häuser, die ZUERST eingestürzt sind (näher am Epizentrum), auch ZUERST.
end

-- Wird von CombatHandler.lua aufgerufen, wenn ein Spieler ein Haus in Reichweite trifft.
local function damageHouse(house, amount, attackerPlayer, originPosition)
	if house:GetAttribute("Destroyed") then
		return
	end

	-- Barrikaden-Schild-Schutz (Alert-Stufe 3): solange das Schild aktiv ist, nimmt das
	-- Gebäude KEINEN Schaden -- die Halbkugel ist ausserdem physisch kollidierbar
	-- (kann nicht durchdrungen werden), diese Prüfung fängt zusätzlich Angriffe ab,
	-- die trotzdem irgendwie durchkommen (z.B. Flächenschaden über die Kollision hinweg).
	if _G.IsFlankBuildingProtected and _G.IsFlankBuildingProtected(house) then
		return
	end

	-- Guardian-Schutz (Alert-Stufe 5): solange der Guardian aktiv VOR diesem Gebäude
	-- steht und blockiert (siehe CityDefenderService.lua), nimmt das Gebäude keinen
	-- Schaden -- der Spieler muss erst durch den Guardian.
	if _G.IsGuardianProtectingBuilding and _G.IsGuardianProtectingBuilding(house) then
		return
	end

	-- Absicherung: falls dieses Haus aus irgendeinem Grund nie richtig initialisiert wurde
	-- (z.B. Tag erst nachträglich/während eines laufenden Tests gesetzt), hier nachholen,
	-- statt mit "arithmetic on nil" abzustürzen.
	if house:GetAttribute("Health") == nil then
		warn(
			"[Kaiju] Haus '"
				.. house:GetFullName()
				.. "' hatte keine Health (MaxHealth war "
				.. tostring(house:GetAttribute("MaxHealth"))
				.. ", Destroyed war "
				.. tostring(house:GetAttribute("Destroyed"))
				.. ") -- initialisiere jetzt nachträglich."
		)
		if not house:GetAttribute("MaxHealth") then
			house:SetAttribute("MaxHealth", DEFAULT_HEALTH)
		end
		house:SetAttribute("Health", house:GetAttribute("MaxHealth"))
		if not house:GetAttribute("CoinsReward") then
			house:SetAttribute("CoinsReward", rewardFromHP(house:GetAttribute("MaxHealth"), COINS_SCALE))
		end
		if house.PrimaryPart and not house.PrimaryPart:FindFirstChild("HouseHealthBar") then
			createHealthBar(house)
		end
	end

	local newHealth = house:GetAttribute("Health") - amount
	house:SetAttribute("Health", math.max(newHealth, 0))

	-- Special Energy: kleine, proportionale Menge pro verursachtem Schaden, plus fester
	-- Bonus bei tatsächlicher Zerstörung (siehe unten bei destroyHouse-Aufruf ist der
	-- Bonus NICHT hier, da destroyHouse selbst den Angreifer kennt und dort sauberer
	-- anzusetzen ist).
	if attackerPlayer and _G.AwardSpecialEnergyForBuildingDamage then
		_G.AwardSpecialEnergyForBuildingDamage(attackerPlayer, amount)
	end

	-- Stufe-3-Cluster-Aktivierung: Barrikaden sollen NICHT alle gleichzeitig bei Level 3
	-- erscheinen, sondern erst, sobald eines ihrer Flankengebäude (per ShieldClusterId-
	-- Attribut markiert) unter 50% HP fällt -- macht das Eskalieren spannender/gestaffelt,
	-- statt alles auf einmal zu zeigen.
	local shieldClusterId = house:GetAttribute("ShieldClusterId")
	if shieldClusterId and _G.TryActivateBarricadeCluster then
		-- WICHTIG: KEINE "newHealth > 0"-Bedingung mehr -- ein Gebäude, das durch einen
		-- einzigen, sehr starken Treffer direkt von voller HP auf 0 fällt (newHealth==0),
		-- hat die 50%-Schwelle logisch ebenfalls unterschritten (und sogar deutlich mehr),
		-- löste die Cluster-Aktivierung bisher aber NIE aus, weil dieser Fall explizit
		-- ausgeschlossen war.
		local maxHealth = house:GetAttribute("MaxHealth") or 1
		local healthRatio = newHealth / maxHealth
		if healthRatio < 0.5 then
			local cityNamePart = house
			local cityName = nil
			while cityNamePart do
				cityName = cityNamePart:GetAttribute("CityName")
				if cityName then
					break
				end
				cityNamePart = cityNamePart.Parent
			end
			if cityName then
				print("[HouseHandler] '" .. house.Name .. "' (ShieldClusterId='" .. shieldClusterId .. "') unter 50% HP (" .. math.floor(healthRatio * 100) .. "%) -- löse Cluster-Aktivierung aus.")
				_G.TryActivateBarricadeCluster(cityName, shieldClusterId)
			else
				warn("[HouseHandler] '" .. house.Name .. "' hat ShieldClusterId='" .. shieldClusterId .. "', aber KEIN Vorfahre mit 'CityName'-Attribut gefunden -- Cluster-Aktivierung übersprungen.")
			end
		end
	end

	local impactSound = house.PrimaryPart and house.PrimaryPart:FindFirstChild("ImpactSound")
	if impactSound and impactSound.SoundId ~= "" and impactSound.SoundId ~= "rbxassetid://0" then
		impactSound.TimePosition = 0
		impactSound:Play()
	end

	if newHealth <= 0 then
		destroyHouse(house, attackerPlayer, originPosition)
	else
		shakeHouse(house)
	end
end

-- "Draufspringen" fügt Schaden zu (z.B. wenn man viel größer ist als das Haus und
-- "Anrennen"/"Drüberlaufen"/"Draufspringen" fügt automatisch Schaden zu, gestaffelt nach
-- Situation -- einfaches, direktes Touched-System (keine Geschwindigkeits-Verfolgung mehr,
-- das fühlte sich im Gameplay zu kompliziert/unzuverlässig an):
--   1) Seitlich gegen das Haus rennen (Wand berühren)        -> kleiner Teil vom Schaden
--   2) Auf dem Dach herumlaufen (oben berühren, kein Sprung) -> etwas mehr Schaden
--   3) Auf dem Dach springen (oben berühren, während Sprung) -> doppelter Schlagschaden
local TRAMPLE_COOLDOWN = 0.5 -- Sekunden zwischen zwei zählenden Berührungen pro Spieler+Haus
local BUMP_DAMAGE_RATIO = 0.15 -- 15% des Schlagschadens beim seitlichen Anrennen
local ROOF_WALK_DAMAGE_RATIO = 0.4 -- 40% des Schlagschadens beim Dach-Herumlaufen
-- ROOF_JUMP_DAMAGE_MULTIPLIER entfällt -- der Sprung-Multiplikator wird jetzt dynamisch
-- aus dem Bein-Verhältnis berechnet (siehe onHouseTouched weiter unten).
local ROOF_TOLERANCE = 3 -- Studs Toleranz, um "steht auf dem Dach" zu erkennen

-- Zusätzlicher GLOBALER Cooldown fürs Sprung-Schaden (nicht nur pro Haus) -- etwas länger
-- als der normale Schlag-Cooldown (0.8s), damit man nicht durch Springen zwischen
-- verschiedenen Häusern den Pro-Haus-Cooldown umgehen kann. Für den Client bereitgestellt,
-- damit das HUD einen "Sprung"-Button mit Cooldown-Anzeige zeigen kann.
local JUMP_ATTACK_COOLDOWN = 1.2

local jumpAttackCooldownValue = Instance.new("NumberValue")
jumpAttackCooldownValue.Name = "JumpAttackCooldown"
jumpAttackCooldownValue.Value = JUMP_ATTACK_COOLDOWN
jumpAttackCooldownValue.Parent = ReplicatedStorage

-- Der Sprung-Cooldown gilt jetzt fürs SPRINGEN SELBST (jede Art zu springen, nicht nur
-- Dach-Treffer) -- der Client meldet hierüber, sobald ein echter Sprung beginnt, damit der
-- Server den Cooldown serverseitig autoritativ setzt (fürs HUD + gegen Manipulation).
local PlayerJumpedEvent = getOrCreateRemoteEvent("PlayerJumpedEvent")
PlayerJumpedEvent.OnServerEvent:Connect(function(player)
	local now = workspace:GetServerTimeNow()
	if now < (player:GetAttribute("JumpAttackReadyAt") or 0) then
		return -- Cooldown läuft noch -> ignorieren (Client sollte das eigentlich schon verhindern)
	end

	-- Bein-Training-Boost halbiert auch den Sprung-Cooldown, konsistent zu Fokus/Fläche
	-- (siehe SpecialAttackHandler.lua, getEffectiveCooldown).
	local effectiveCooldown = JUMP_ATTACK_COOLDOWN
	if player:GetAttribute("TrainingStat") == "Leg" then
		local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
		if now < boostEndsAt then
			effectiveCooldown = JUMP_ATTACK_COOLDOWN / 2
		end
	end

	-- Talent "Rapid Strikes" (Kaiju-Talentbaum): zusätzliche Abklingzeit-Reduktion,
	-- gleiche Wirkung wie bei Fokus/Fläche.
	local talentCooldownReduction = (_G.GetTalentCooldownReduction and _G.GetTalentCooldownReduction(player)) or 0
	effectiveCooldown = effectiveCooldown * math.max(1 - talentCooldownReduction, 0.4)

	player:SetAttribute("JumpAttackReadyAt", now + effectiveCooldown)
end)

local lastTrampleTime = {} -- [house] = { [player] = os.clock() }

-- Zeichnet laufend die vertikale Geschwindigkeit jedes Spielers auf. Wichtig: Bis das
-- Touched-Event feuert, hat sich der Humanoid-Zustand (Jumping/Freefall) bei kurzen
-- Landungen (z.B. auf einem kleinen Giebeldach) oft schon wieder auf "Landed"/"Running"
-- geändert -- der GetState()-Check allein reicht dann nicht. Der zuletzt AUFGEZEICHNETE
-- Wert (kurz VOR dem Aufprall) ist zuverlässiger.
local JUMP_FALL_VELOCITY_THRESHOLD = -15 -- ab dieser Abwärtsgeschwindigkeit gilt es als Sprung/Fall
local recentFallVelocity = {} -- [player] = letzte relevante schnelle Abwärtsgeschwindigkeit
local recentFallVelocityAt = {} -- [player] = os.clock() des letzten relevanten Fall-Samples
local FALL_MEMORY_SECONDS = 0.35 -- Landung kann Touched erst auslösen, nachdem Roblox schon "Landed" meldet

RunService.Heartbeat:Connect(function()
	local now = os.clock()

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local rp = char and char:FindFirstChild("HumanoidRootPart")
		if rp then
			local vy = rp.AssemblyLinearVelocity.Y

			-- Nur echte schnelle Abwärtsbewegung merken. Der Wert bleibt kurz erhalten,
			-- damit ein Touched-Ereignis unmittelbar NACH dem physikalischen Aufprall
			-- trotzdem noch als Sprunglandung erkannt wird.
			if vy < JUMP_FALL_VELOCITY_THRESHOLD then
				recentFallVelocity[plr] = vy
				recentFallVelocityAt[plr] = now
			elseif recentFallVelocityAt[plr]
				and now - recentFallVelocityAt[plr] > FALL_MEMORY_SECONDS then
				recentFallVelocity[plr] = 0
				recentFallVelocityAt[plr] = nil
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	recentFallVelocity[plr] = nil
	recentFallVelocityAt[plr] = nil
end)

-- Sucht ausgehend von einem berührten Teil das übergeordnete Haus-Model (falls vorhanden).
local function findHouseFromPart(part)
	local current = part
	while current and current ~= workspace do
		if current:IsA("Model") and CollectionService:HasTag(current, HOUSE_TAG) then
			return current
		end
		current = current.Parent
	end
	return nil
end

onHouseTouched = function(house, housePart, hit)
	if house:GetAttribute("Destroyed") then
		return
	end

	-- Ohne echtes Gebäudeteil keine verlässliche Seiten-/Dach-Erkennung.
	if not housePart or not housePart:IsA("BasePart") then
		return
	end

	-- Während das Haus gerade erschüttert (nach einem Treffer), bewegt sich seine Geometrie
	-- kurz hin und her -- das kann bei einem Spieler, der IM Modell drinsteckt, mehrfach
	-- "Touched" auslösen, obwohl er sich gar nicht bewegt. Solche Berührungen ignorieren.
	if shakingHouses[house] then
		return
	end

	-- Robuster als nur hit.Parent: Touched kann auch von Parts in verschachtelten
	-- Character-Untermodellen/Accessoires kommen. Deshalb bis zum Character-Model
	-- nach oben laufen und dort den Player auflösen.
	local character = nil
	local player = nil
	local node = hit

	while node and node ~= workspace do
		if node:IsA("Model") then
			local candidate = Players:GetPlayerFromCharacter(node)
			if candidate then
				character = node
				player = candidate
				break
			end
		end
		node = node.Parent
	end

	if not player or not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then
		return
	end

	lastTrampleTime[house] = lastTrampleTime[house] or {}
	local now = os.clock()
	local last = lastTrampleTime[house][player]
	if last and now - last < TRAMPLE_COOLDOWN then
		return
	end

	local baseDamage = character:GetAttribute("Damage") or 10
	local berserkerMultiplier = (_G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0
	baseDamage = baseDamage * berserkerMultiplier

	-- Steht der Spieler ungefähr auf Höhe der Oberkante des TATSÄCHLICH BERÜHRTEN
	-- GEBÄUDETEILS -> "auf dem Dach", sonst zählt es als seitliches Anrennen gegen die Wand.
	--
	-- WICHTIGER BUGFIX #39:
	-- Früher wurde hier 'hit' verwendet. Bei BasePart.Touched ist 'hit' aber das ANDERE
	-- Part (also z.B. Fuß/Bein des Characters), NICHT das Gebäudeteil. Dadurch war
	-- isOnRoof praktisch zufällig und Seiten-/Sprungschaden unzuverlässig.
	--
	-- WICHTIGER BUGFIX #49:
	-- "Position.Y + Size.Y/2" geht von einem NICHT ROTIERTEN Teil aus -- bei geneigten
	-- Teilen (z.B. Giebeldach-Schrägen) ergibt das eine falsche Höhe, wodurch dort gar
	-- kein Dach-Schaden ausgelöst werden konnte. Stattdessen jetzt: alle 8 Ecken der
	-- Bounding Box korrekt in Welt-Koordinaten transformieren (berücksichtigt jede
	-- Rotation) und die höchste tatsächliche Y-Koordinate davon nehmen.
	local halfSize = housePart.Size / 2
	local housePartTopY = -math.huge
	for _, signX in ipairs({ -1, 1 }) do
		for _, signY in ipairs({ -1, 1 }) do
			for _, signZ in ipairs({ -1, 1 }) do
				local corner = housePart.CFrame * CFrame.new(halfSize.X * signX, halfSize.Y * signY, halfSize.Z * signZ)
				if corner.Position.Y > housePartTopY then
					housePartTopY = corner.Position.Y
				end
			end
		end
	end
	local isOnRoof = rootPart.Position.Y >= housePartTopY - ROOF_TOLERANCE

	local state = humanoid:GetState()

	-- Der Fall-Sample darf kurz vor dem eigentlichen Touched-Ereignis entstanden sein.
	-- Das ist bei Landungen häufig der Fall: beim Touched steht der Humanoid bereits auf
	-- "Landed"/"Running" und die aktuelle Y-Velocity ist schon nahe 0.
	local currentTime = os.clock()
	local fallIsRecent = recentFallVelocityAt[player]
		and (currentTime - recentFallVelocityAt[player]) <= FALL_MEMORY_SECONDS

	local recentVelocityY = fallIsRecent
		and (recentFallVelocity[player] or 0)
		or rootPart.AssemblyLinearVelocity.Y

	local isJumping = state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or recentVelocityY < JUMP_FALL_VELOCITY_THRESHOLD

	local isMoving = humanoid.MoveDirection.Magnitude > 0.1

	local damage

	-- Optionales Diagnose-Logging für einzelne problematische Assets:
	-- Setze am Haus DebugTouchDamage=true, dann zeigt Output exakt, wie der Kontakt
	-- klassifiziert wurde.
	if house:GetAttribute("DebugTouchDamage") == true then
		print(
			"[HouseTouchDebug]",
			house.Name,
			"surface=", housePart.Name,
			"surfaceTopY=", math.floor(housePartTopY * 100) / 100,
			"rootY=", math.floor(rootPart.Position.Y * 100) / 100,
			"isOnRoof=", isOnRoof,
			"isJumping=", isJumping,
			"isMoving=", isMoving,
			"vy=", math.floor(recentVelocityY * 100) / 100
		)
	end

	if isOnRoof and isJumping then
		-- Springen zählt immer, unabhängig von aktiver Bewegung. Der Multiplikator
		-- kommt jetzt vom BEIN-Verhältnis (aktueller Wert / aktueller Cap): 1x bei
		-- Bein=0, bis zu 2x bei voll trainiertem Bein. Basisschaden selbst kommt
		-- weiterhin nur vom Arm-Wert (siehe PlayerSetup.lua, recalculateStrength).
		local legPower = player:FindFirstChild("LegPower")
		local legValue = legPower and legPower.Value or 0
		-- "LegStatCap" (Bein-spezifischer, ×100 skalierter Cap) statt dem generischen
		-- "StatCap" -- sonst wäre das Verhältnis durch die Skalierung verfälscht.
		local legCap = math.max(player:GetAttribute("LegStatCap") or 1, 1)
		local legRatio = math.clamp(legValue / legCap, 0, 1)
		local jumpMultiplier = 1 + legRatio -- 1x bis 2x

		damage = baseDamage * jumpMultiplier

		-- Der gespeicherte Fall wurde durch diesen Sprungtreffer konsumiert. So kann
		-- derselbe Landungsimpuls nicht über mehrere kurz nacheinander ausgelöste
		-- Touched-Events mehrfach als Sprungschaden zählen.
		recentFallVelocity[player] = 0
		recentFallVelocityAt[player] = nil

		-- Heat-System: Sprungschaden erzeugt Hitze.
		if _G.AddJumpHeat then
			_G.AddJumpHeat(player)
		end

		-- Lebensstatistik: gezählt wird der SPRUNGANGRIFF (ein Treffer), nicht jeder Sprung.
		if _G.RecordStat then
			_G.RecordStat(player, "Attacks.Jump")
		end

		-- Special Energy: Sprung-Landung gibt einen festen Bonus.
		if _G.AwardSpecialEnergyForJumpLanding then
			_G.AwardSpecialEnergyForJumpLanding(player)
		end

		-- Strahlungs-Mutation "Shockwave Jump" (falls diese Runde ausgelöst): Sprünge
		-- verursachen zusätzlich einen kleinen Flächenschaden an anderen Häusern in der Nähe.
		if player:GetAttribute("MutationShockwaveJump") and _G.DamageHouse then
			local SHOCKWAVE_RADIUS = 20
			local SHOCKWAVE_DAMAGE_RATIO = 0.25 -- 25% des Sprungschadens an jedes Haus im Radius
			for _, otherHouse in ipairs(CollectionService:GetTagged(_G.HOUSE_TAG or "KaijuHouse")) do
				if otherHouse ~= house and not otherHouse:GetAttribute("Destroyed") then
					local otherPart = otherHouse:IsA("Model") and (otherHouse.PrimaryPart or otherHouse:FindFirstChildWhichIsA("BasePart"))
					if otherPart and (otherPart.Position - rootPart.Position).Magnitude <= SHOCKWAVE_RADIUS then
						_G.DamageHouse(otherHouse, damage * SHOCKWAVE_DAMAGE_RATIO, player)
					end
				end
			end
		end
	elseif not isMoving then
		-- Steht nur still (egal ob auf dem Dach, innen im Modell oder daneben) und
		-- springt nicht -> kein Schaden. Verhindert v.a. Dauerschaden, wenn man im
		-- Modell drinsteckt und irgendein Innenteil fälschlich als "Dach" gilt.
		return
	elseif isOnRoof then
		damage = baseDamage * ROOF_WALK_DAMAGE_RATIO
	else
		damage = baseDamage * BUMP_DAMAGE_RATIO
	end

	-- Erst JETZT den Cooldown verbrauchen, da wirklich Schaden entsteht.
	lastTrampleTime[house][player] = now

	-- Zähler für Ronin-Fraktions-Freischaltung (siehe FactionUnlockService.lua): zählt
	-- Häuser, die per SPRUNGANGRIFF (nicht Anrennen/Dach-Laufen) den Todesstoss bekommen.
	-- Health VOR dem Treffer merken, da damageHouse() selbst keinen "wurde zerstört"-
	-- Rückgabewert liefert.
	local wasAliveBeforeHit = (tonumber(house:GetAttribute("Health")) or 0) > 0

	damageHouse(house, damage, player)
	ShowDamageEvent:FireClient(player, damage)

	if isOnRoof and isJumping and wasAliveBeforeHit and house:GetAttribute("Destroyed") then
		player:SetAttribute("JumpKills", (player:GetAttribute("JumpKills") or 0) + 1)
	end
end

-- ===== Periodischer Dach-Schadens-Check ===========================================
-- WICHTIG: Roblox' "Touched"-Ereignis feuert nur bei einem NEUEN Kontakt (Wechsel von
-- "nicht berührt" zu "berührt") -- NICHT kontinuierlich, solange man einfach auf einer
-- Fläche steht/läuft, ohne den Kontakt wirklich zu verlieren. Auf einem Dach (v.a. bei
-- geneigten Giebeldach-Flächen) bleibt der Kontakt oft durchgehend bestehen, wodurch
-- "Touched" nach der ersten Berührung nie wieder feuert -- Dach-Lauf-Schaden blieb
-- dadurch faktisch aus, sobald man sich stabil auf dem Dach befand. Dieser periodische
-- Check kompensiert das: prüft alle PERIODIC_ROOF_CHECK_INTERVAL Sekunden per Raycast,
-- ob ein Spieler gerade auf dem Dach EINES KaijuHouse steht, und wendet bei Bedarf
-- denselben Roof-Walk-Schaden an wie die reguläre Touched-basierte Erkennung --
-- unabhängig davon, ob "Touched" gerade feuert oder nicht.
-- WICHTIG: kurzes Intervall (0.25s statt z.B. 0.6s) -- reduziert die spürbare
-- Verzögerung zwischen dem tatsächlichen Landen und dem erkannten Schaden deutlich.
-- TRAMPLE_COOLDOWN (0.5s, siehe onHouseTouched) verhindert weiterhin, dass dadurch zu
-- oft Schaden ausgelöst wird -- das Intervall bestimmt nur, wie GENAU der Moment der
-- Landung erkannt wird, nicht wie OFT insgesamt Schaden möglich ist.
local PERIODIC_ROOF_CHECK_INTERVAL = 0.25

task.spawn(function()
	while true do
		task.wait(PERIODIC_ROOF_CHECK_INTERVAL)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local rp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if rp and hum and hum.Health > 0 then
				-- WICHTIG: Mehrere Strahlen statt nur einem zentrierten -- bei sehr
				-- grossen Charakteren (Füsse/Kollisionsbereich ähnlich gross wie ein
				-- kleines Dach) kann ein einzelner, zentrierter Strahl das Dach komplett
				-- verfehlen, sobald man nicht perfekt exakt zentriert steht. Radius wird
				-- aus der tatsächlichen Charaktergrösse abgeleitet, damit das bei jeder
				-- Grösse passend mitskaliert.
				local ok, boundsSize = pcall(function()
					local _, size = char:GetBoundingBox()
					return size
				end)
				local footprintRadius = ok and math.max(boundsSize.X, boundsSize.Z) * 0.3 or 3
				local offsets = {
					Vector3.new(0, 0, 0),
					Vector3.new(footprintRadius, 0, 0),
					Vector3.new(-footprintRadius, 0, 0),
					Vector3.new(0, 0, footprintRadius),
					Vector3.new(0, 0, -footprintRadius),
				}

				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { char }

				for _, offset in ipairs(offsets) do
					local origin = rp.Position + offset
					local result = Workspace:Raycast(origin, Vector3.new(0, -50, 0), params)
					if result then
						local house = findHouseFromPart(result.Instance)
						-- Nur auslösen, wenn WIRKLICH auf dem Dach gestanden wird -- nutzt HipHeight
						-- (die tatsächliche, individuelle Distanz zwischen Root und Boden
						-- dieses Charakters) statt eines festen Werts, der bei sehr grossen
						-- Charakteren viel zu klein gewesen wäre und den Check immer
						-- stillschweigend verworfen hätte.
						local expectedGroundDistance = hum.HipHeight + rp.Size.Y / 2
						local isCloseEnough = (origin - result.Position).Magnitude <= expectedGroundDistance + 3
						if house
							and isCloseEnough
							and not house:GetAttribute("Destroyed")
							and result.Instance:IsA("BasePart")
							and houseTouchConnections[house]
							and houseTouchConnections[house][result.Instance]
							and onHouseTouched
						then
							onHouseTouched(house, result.Instance, rp)
							break -- ein Treffer pro Spieler pro Durchlauf reicht
						end
					end
				end
			end
		end
	end
end)

for _, house in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
	initHouse(house)
end
CollectionService:GetInstanceAddedSignal(HOUSE_TAG):Connect(initHouse)

-- Einfache, projektweite Schnittstelle für CombatHandler.lua (analog zu _G.AwardXP)
_G.DamageHouse = damageHouse

-- Zerstört ein Haus SOFORT und DAUERHAFT (kein Respawn) -- gedacht für vorab zerstörte
-- Kulisse (z.B. Prolog-Stadt, die von Anfang an teilweise in Trümmern liegen soll).
-- ruinType: "Burning" (brennt/raucht unendlich lange, aber ganz normal von Feuerwehr
-- löschbar) oder "Clean" (nur Ruine, kein Feuer). Siehe "PermanentlyDestroyed"-Attribut-
-- Prüfungen weiter oben in diesem File.
_G.PermanentlyDestroyHouse = function(house, ruinType)
	house:SetAttribute("PermanentlyDestroyed", ruinType or "Burning")
	damageHouse(house, math.huge, nil)
end
-- Für FireEngineController.lua: räumt Feuer+Rauch sofort weg UND stoppt die
-- Energie-Absorption -- wird aufgerufen, sobald ein Feuerwehrauto ein Feuer fertig
-- gelöscht hat (statt bis zum natürlichen Ausgehen zu warten).
_G.ExtinguishHouseFire = extinguishHouseFire
_G.HOUSE_TAG = HOUSE_TAG

-- Respawnt ein Haus SOFORT, ohne auf den normalen Respawn-Timer zu warten -- für den
-- Prolog-Stadt-Reset gedacht (siehe PrologueOrchestrator.lua), wenn ein Spieler
-- durchgespielt hat und die Stadt für den nächsten Spieler zurückgesetzt werden muss.
_G.ForceRespawnHouse = performRespawn