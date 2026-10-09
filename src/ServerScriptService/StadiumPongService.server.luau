-- Script: StadiumPongService
--
-- Pong auf dem Spielfeld des Large-City-Stadions -- spielbar.
--
-- ===== Was aus dem Workshop kommt und was nicht =====
-- Das Paket (LargeCityStadiumPong) baut ein hübsches Pong, aber es ist ausdrücklich
-- `DecorativeOnly`: der Ball prallt an den Torlinien IMMER ab, es gibt kein Vorbei, keinen
-- Punkt und keinen Aufschlag, und beide Schläger folgen ihm automatisch. Ein
-- Bildschirmschoner, kein Spiel.
--
-- Hier steht deshalb ein eigenes, spielbares Pong. Es baut seine Teile selbst, im selben
-- Mass und Aussehen wie das Paket, und räumt dessen Ordner weg -- dessen Heartbeat-Schleife
-- beendet sich dann von allein (sie prüft `folder.Parent`). Das Paket bleibt unberührt: es
-- liegt im Submodul, Änderungen daran gehören in den Workshop, nicht hierher.
--
-- ===== Wie man spielt =====
-- An jedem Feldende steht ein ProximityPrompt. Wer ihn auslöst, übernimmt den Schläger
-- dieser Seite; der zweite Spieler nimmt die andere. Bleibt eine Seite frei, spielt dort
-- die Automatik weiter -- allein spielt man also gegen den Computer.
--
-- Gesteuert wird mit den Tasten (siehe StadiumPongClient), der Blick geht dabei von oben
-- aufs Feld. Der Server führt Ball UND Schläger; vom Client kommt nur eine Richtung
-- (-1/0/1). Anders wäre das Spiel von einem Client aus zu stellen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils", 10))
local PongInputEvent = RemoteEventUtils.GetOrCreate("StadionPongInput")
local PongStateEvent = RemoteEventUtils.GetOrCreate("StadionPongState")

-- Das Stadion heisst seit dem 04.10.2026 "LargeCityStadium" und ist das einzige. Der
-- frühere Name "LargeCity_Stadium_L3" kommt in der Welt nicht mehr vor -- ein Rückfall
-- darauf wäre ein zweiter Name, der nie greift und beim nächsten Lesen Fragen aufwirft.
local STADION = "LargeCityStadium"

-- ===== Masse =====
-- Übernommen aus dem Paket, damit das spielbare Feld dort liegt, wo das dekorative lag --
-- die Geometrie des Stadions ist darauf gebaut.
local WEISS = Color3.fromRGB(245, 248, 250)
local MITTE_Z = 4
local LINKS_X = -45
local RECHTS_X = 45
local BALL_X_GRENZE = 42.5
local Z_GRENZE = 25
local HOEHE = 1.35
local SCHLAEGER_LAENGE = 12
local BALL_GROESSE = 2.2

-- ===== Spielwerte =====
-- Der Ball ist etwas schneller als im Paket: dort muss er niemanden fordern.
local BALL_TEMPO_X = 30
local BALL_TEMPO_Z = 16
local SPIELER_TEMPO = 26 -- Studs je Sekunde, wie schnell ein Schläger folgt
-- Die Automatik ist bewusst LANGSAMER als ein Mensch. Ein Computergegner, der den Ball
-- immer erreicht, ist kein Gegner, sondern eine Wand -- man kann gegen ihn nicht gewinnen,
-- nur nicht verlieren.
local COMPUTER_TEMPO = 19
local AUFSCHLAG_PAUSE = 1.2

-- ===== Der Ballwechsel ist die Schwierigkeit =====
-- Feste Werte machen das Spiel gleichmaessig schwer -- auch im ersten Ballwechsel, wo noch
-- nichts geleistet wurde. Stattdessen waechst der Ball mit dem Ballwechsel, wie im
-- Original: der Anfang bleibt leicht, nach zehn Wechseln wird es ernst.
--
-- Die Automatik verliert dadurch VON SELBST, ohne dass man sie schlechter machen muesste:
-- ihre Grenze bleibt COMPUTER_TEMPO, der Ball nicht. Aus "schafft der Computer das?" wird
-- "wie lange halte ich durch?".
local TEMPO_ZUWACHS = 1.06 -- je Schlaegertreffer
local TEMPO_DECKEL = 2.0 -- darueber ist es kein Koennen mehr, sondern Raten

-- Wer sich so weit entfernt, spielt offensichtlich nicht mehr mit.
local AUFGABE_ENTFERNUNG = 400

-- Prompts messen gegen den RUMPF der Figur, und der sitzt bei einem Kaiju dreissig Studs
-- über dem Boden (siehe TrainingHandler, dieselbe Falle). Deshalb von vornherein grosszügig.
local PROMPT_REICHWEITE = 90

local SEITEN = { "Links", "Rechts" }
local SEITEN_X = { Links = LINKS_X, Rechts = RECHTS_X }

------------------------------------------------------------
-- Zustand
------------------------------------------------------------

local feld -- { Wurzel, LinksSchlaeger, RechtsSchlaeger, Ball, Anzeige, Ton }
local schlaegerZ = { Links = MITTE_Z, Rechts = MITTE_Z }
local punkte = { Links = 0, Rechts = 0 }
local spielerAufSeite = { Links = nil, Rechts = nil }
local richtungVon = {} -- [player] = -1 | 0 | 1
local seiteVon = {} -- [player] = "Links" | "Rechts"

local ballX, ballZ = 0, MITTE_Z
local ballVX, ballVZ = BALL_TEMPO_X, BALL_TEMPO_Z
local aufschlagBis = 0
local tempoFaktor = 1

------------------------------------------------------------
-- Bauen
------------------------------------------------------------

local function teil(eltern, name, groesse, ort, wurzelCFrame)
	local item = Instance.new("Part")
	item.Name = name
	item.Size = groesse
	item.CFrame = wurzelCFrame * CFrame.new(ort)
	item.Color = WEISS
	item.Material = Enum.Material.Neon
	item.Anchored = true
	item.CanCollide = false
	item.CanQuery = false
	item.CanTouch = false
	item.CastShadow = false
	item.Parent = eltern
	return item
end

local function baueAnzeige(eltern, wurzelCFrame)
	local halter = teil(eltern, "Punktetafel", Vector3.new(1, 1, 1),
		Vector3.new(0, HOEHE + 26, MITTE_Z), wurzelCFrame)
	halter.Transparency = 1

	local schild = Instance.new("BillboardGui")
	schild.Name = "Punkte"
	schild.Size = UDim2.fromScale(28, 10)
	schild.AlwaysOnTop = true
	schild.Parent = halter

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Code
	text.TextScaled = true
	text.TextColor3 = WEISS
	text.Text = "0 : 0"
	text.Parent = schild

	return text
end

local function baueFeld(stadion)
	-- Das dekorative Pong des Pakets weg: seine Heartbeat-Schleife prüft in jedem Bild, ob
	-- ihr Ordner noch hängt, und beendet sich von selbst. Ohne das liefen zwei Bälle.
	local dekorativ = stadion:FindFirstChild("PongEasterEgg")
	if dekorativ then
		dekorativ:Destroy()
	end
	local altes = stadion:FindFirstChild("PongSpielbar")
	if altes then
		altes:Destroy()
	end

	local wurzel = stadion.PrimaryPart
	if not wurzel then
		return nil
	end
	local wurzelCFrame = wurzel.CFrame

	local ordner = Instance.new("Folder")
	ordner.Name = "PongSpielbar"
	ordner.Parent = stadion

	local neu = {
		Wurzel = wurzelCFrame,
		Ordner = ordner,
		Links = teil(ordner, "LinksSchlaeger", Vector3.new(1.25, 0.32, SCHLAEGER_LAENGE),
			Vector3.new(LINKS_X, HOEHE, MITTE_Z), wurzelCFrame),
		Rechts = teil(ordner, "RechtsSchlaeger", Vector3.new(1.25, 0.32, SCHLAEGER_LAENGE),
			Vector3.new(RECHTS_X, HOEHE, MITTE_Z), wurzelCFrame),
		Ball = teil(ordner, "Ball", Vector3.new(BALL_GROESSE, 0.34, BALL_GROESSE),
			Vector3.new(0, HOEHE + 0.02, MITTE_Z), wurzelCFrame),
	}
	neu.Anzeige = baueAnzeige(ordner, wurzelCFrame)

	-- Ein Namensschild UEBER jedem Schlaeger. Von oben sieht man sonst zwei gleiche weisse
	-- Balken und weiss nicht, welcher der eigene ist -- erst recht nicht, wer der Gegner
	-- ist. Das Schild haengt am Schlaeger selbst und wandert deshalb mit.
	for _, seite in ipairs(SEITEN) do
		local schild = Instance.new("BillboardGui")
		schild.Name = "Name"
		schild.Size = UDim2.fromScale(16, 4)
		schild.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
		schild.AlwaysOnTop = true
		schild.Parent = neu[seite]

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Code
		text.TextScaled = true
		text.TextColor3 = WEISS
		text.Text = "Computer"
		text.Parent = schild
		neu[seite .. "Name"] = text
	end

	local ton = Instance.new("Sound")
	ton.Name = "PongBeep"
	ton.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	ton.Volume = 0.34
	ton.PlaybackSpeed = 0.86
	ton.RollOffMaxDistance = 260
	ton.RollOffMinDistance = 24
	ton.Parent = neu.Ball
	neu.Ton = ton

	-- Je Seite ein Anker für das Prompt. Nicht am Schläger selbst: der bewegt sich, und ein
	-- wanderndes Prompt ist schwer zu treffen.
	for _, seite in ipairs(SEITEN) do
		local anker = teil(ordner, "Anker" .. seite, Vector3.new(2, 2, 2),
			Vector3.new(SEITEN_X[seite] * 1.12, HOEHE + 2, MITTE_Z), wurzelCFrame)
		anker.Transparency = 1

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt" .. seite
		prompt.ActionText = "Pong spielen"
		prompt.ObjectText = seite == "Links" and "Linker Schläger" or "Rechter Schläger"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = PROMPT_REICHWEITE
		prompt.RequiresLineOfSight = false
		prompt.Parent = anker
		neu["Prompt" .. seite] = prompt
	end

	return neu
end

------------------------------------------------------------
-- Spiel
------------------------------------------------------------

local function piep(tonhoehe)
	if feld and feld.Ton then
		feld.Ton.PlaybackSpeed = tonhoehe
		feld.Ton.TimePosition = 0
		feld.Ton:Play()
	end
end

-- Wer spielt auf dieser Seite? Eine freie Seite fuehrt die Automatik.
local function namenFuer(seite)
	local player = spielerAufSeite[seite]
	return player and player.Name or "Computer"
end

local function zeigeStand()
	if not feld then
		return
	end
	for _, seite in ipairs(SEITEN) do
		local schild = feld[seite .. "Name"]
		if schild then
			schild.Text = namenFuer(seite)
		end
	end
	if feld.Anzeige then
		feld.Anzeige.Text = string.format("%s  %d : %d  %s",
			namenFuer("Links"), punkte.Links, punkte.Rechts, namenFuer("Rechts"))
	end
end

local function aufschlag(richtung)
	ballX, ballZ = 0, MITTE_Z
	tempoFaktor = 1
	ballVX = BALL_TEMPO_X * richtung
	ballVZ = BALL_TEMPO_Z * (math.random() < 0.5 and -1 or 1)
	aufschlagBis = os.clock() + AUFSCHLAG_PAUSE
end

local function aktualisierePrompt(seite)
	if not feld then
		return
	end
	local prompt = feld["Prompt" .. seite]
	if not prompt then
		return
	end
	local besetzt = spielerAufSeite[seite]
	prompt.ActionText = besetzt and "Aufhören" or "Pong spielen"
	prompt.ObjectText = besetzt and besetzt.Name or
		(seite == "Links" and "Linker Schläger" or "Rechter Schläger")
end

local function verlasse(player)
	local seite = seiteVon[player]
	if not seite then
		return
	end
	seiteVon[player] = nil
	richtungVon[player] = nil
	if spielerAufSeite[seite] == player then
		spielerAufSeite[seite] = nil
	end
	aktualisierePrompt(seite)
	zeigeStand()
	PongStateEvent:FireClient(player, { Beigetreten = false })
	print(string.format("[Kaiju Debug] Stadion-Pong: %s verlaesst den %s Schlaeger.",
		player.Name, string.lower(seite)))
end

local function betrete(player, seite)
	if seiteVon[player] then
		verlasse(player) -- Seitenwechsel ist erlaubt, doppelt spielen nicht
	end
	if spielerAufSeite[seite] then
		return
	end
	spielerAufSeite[seite] = player
	seiteVon[player] = seite
	richtungVon[player] = 0
	aktualisierePrompt(seite)
	zeigeStand()

	-- Der Client braucht die Lage des Feldes, um von oben darauf zu schauen. Er kann sie
	-- nicht selbst herleiten: die Teile stehen im lokalen Mass des Stadions.
	PongStateEvent:FireClient(player, {
		Beigetreten = true,
		Seite = seite,
		Mitte = feld.Wurzel * CFrame.new(0, HOEHE, MITTE_Z),
		Breite = (RECHTS_X - LINKS_X),
		Tiefe = Z_GRENZE * 2,
	})
	print(string.format("[Kaiju Debug] Stadion-Pong: %s uebernimmt den %s Schlaeger.",
		player.Name, string.lower(seite)))
end

local function zielFuer(seite, dt)
	local player = spielerAufSeite[seite]
	if player then
		local richtung = richtungVon[player] or 0
		return schlaegerZ[seite] + richtung * SPIELER_TEMPO * dt
	end
	-- Automatik: dem Ball folgen, aber gedeckelt -- siehe COMPUTER_TEMPO.
	local abstand = ballZ - schlaegerZ[seite]
	local schritt = math.clamp(abstand, -COMPUTER_TEMPO * dt, COMPUTER_TEMPO * dt)
	return schlaegerZ[seite] + schritt
end

local function trifftSchlaeger(seite)
	local halb = SCHLAEGER_LAENGE / 2 + BALL_GROESSE / 2
	return math.abs(ballZ - schlaegerZ[seite]) <= halb
end

local function schritt(dt)
	if not feld or not feld.Ordner.Parent then
		return
	end
	dt = math.min(dt, 1 / 20)

	local grenzeOben = MITTE_Z + Z_GRENZE - SCHLAEGER_LAENGE / 2
	local grenzeUnten = MITTE_Z - Z_GRENZE + SCHLAEGER_LAENGE / 2
	for _, seite in ipairs(SEITEN) do
		schlaegerZ[seite] = math.clamp(zielFuer(seite, dt), grenzeUnten, grenzeOben)
		feld[seite].CFrame = feld.Wurzel * CFrame.new(SEITEN_X[seite], HOEHE, schlaegerZ[seite])
	end

	if os.clock() < aufschlagBis then
		feld.Ball.CFrame = feld.Wurzel * CFrame.new(0, HOEHE + 0.02, MITTE_Z)
		return
	end

	ballX += ballVX * dt
	ballZ += ballVZ * dt

	local obenZ = MITTE_Z + Z_GRENZE
	local untenZ = MITTE_Z - Z_GRENZE
	if ballZ >= obenZ then
		ballZ = obenZ
		ballVZ = -math.abs(ballVZ)
		piep(0.84)
	elseif ballZ <= untenZ then
		ballZ = untenZ
		ballVZ = math.abs(ballVZ)
		piep(1.06)
	end

	-- Die Torlinien. HIER liegt der Unterschied zum dekorativen Pong: der Ball prallt nur
	-- ab, wenn der Schläger auch dort ist. Sonst gibt es einen Punkt.
	if ballX >= BALL_X_GRENZE then
		if trifftSchlaeger("Rechts") then
			tempoFaktor = math.min(tempoFaktor * TEMPO_ZUWACHS, TEMPO_DECKEL)
			ballX = BALL_X_GRENZE
			ballVX = -BALL_TEMPO_X * tempoFaktor
			-- Wo der Ball den Schläger trifft, bestimmt den Winkel -- sonst wäre jeder
			-- Ballwechsel derselbe.
			ballVZ = math.clamp(ballVZ + (ballZ - schlaegerZ.Rechts) * 1.6, -26, 26)
			-- Der Ton steigt mit. Man hoert den Ballwechsel schneller werden, bevor man es
			-- sieht -- und das ist der Moment, in dem man sich zusammenreisst.
			piep(1.02 * tempoFaktor)
		else
			punkte.Links += 1
			zeigeStand()
			piep(0.6)
			aufschlag(-1)
		end
	elseif ballX <= -BALL_X_GRENZE then
		if trifftSchlaeger("Links") then
			tempoFaktor = math.min(tempoFaktor * TEMPO_ZUWACHS, TEMPO_DECKEL)
			ballX = -BALL_X_GRENZE
			ballVX = BALL_TEMPO_X * tempoFaktor
			ballVZ = math.clamp(ballVZ + (ballZ - schlaegerZ.Links) * 1.6, -26, 26)
			piep(1.02 * tempoFaktor)
		else
			punkte.Rechts += 1
			zeigeStand()
			piep(0.6)
			aufschlag(1)
		end
	end

	feld.Ball.CFrame = feld.Wurzel * CFrame.new(ballX, HOEHE + 0.02, ballZ)
end

------------------------------------------------------------
-- Anschluss
------------------------------------------------------------

PongInputEvent.OnServerEvent:Connect(function(player, richtung)
	if type(richtung) ~= "number" or richtung ~= richtung then
		return
	end
	if not seiteVon[player] then
		return -- spielt gar nicht mit; eine Richtung von aussen bewegt nichts
	end
	richtungVon[player] = math.clamp(richtung, -1, 1)
end)

Players.PlayerRemoving:Connect(verlasse)

-- Wer stirbt oder weit weg ist, gibt den Schläger frei -- sonst bliebe er für alle anderen
-- besetzt, ohne dass jemand spielt.
task.spawn(function()
	while true do
		task.wait(2)
		if feld then
			for _, seite in ipairs(SEITEN) do
				local player = spielerAufSeite[seite]
				local character = player and player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if player and not root then
					verlasse(player)
				elseif root then
					local mitte = feld.Wurzel * CFrame.new(0, HOEHE, MITTE_Z)
					if (root.Position - mitte.Position).Magnitude > AUFGABE_ENTFERNUNG then
						verlasse(player)
					end
				end
			end
		end
	end
end)

------------------------------------------------------------
-- Start
------------------------------------------------------------

local ANLAEUFE = 6
local ABSTAND = 5

task.spawn(function()
	local stadion
	for _ = 1, ANLAEUFE do
		stadion = Workspace:FindFirstChild(STADION, true)
		if stadion then
			break
		end
		task.wait(ABSTAND)
	end

	if not stadion then
		-- Kein Fehler, sondern der Normalfall, solange die vier Large-City-Bauwerke nicht
		-- gesetzt sind. Deshalb eine ruhige Meldung statt einer Warnung bei jedem Start.
		print("[Kaiju Debug] Stadion-Pong: kein '" .. STADION .. "' in der Welt -- uebersprungen. "
			.. "Das Stadion setzt TrenchbornInstallers.LargeCity.LargeCityNewBuildings.")
		return
	end

	feld = baueFeld(stadion)
	if not feld then
		warn("[Kaiju Debug] Stadion-Pong: '" .. STADION .. "' hat keine PrimaryPart -- "
			.. "ohne sie ist die Lage des Feldes nicht bestimmbar.")
		return
	end

	zeigeStand()
	aufschlag(math.random() < 0.5 and -1 or 1)

	for _, seite in ipairs(SEITEN) do
		local gemerkt = seite
		feld["Prompt" .. seite].Triggered:Connect(function(player)
			if spielerAufSeite[gemerkt] == player then
				verlasse(player)
			else
				betrete(player, gemerkt)
			end
		end)
	end

	RunService.Heartbeat:Connect(schritt)

	print("[Kaiju Debug] Stadion-Pong bereit -- an beiden Feldenden steht ein Prompt. "
		.. "Eine freie Seite spielt die Automatik.")
end)
