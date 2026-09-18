-- VERSION: 2026-09-18 #1
-- LocalScript: TalentCeremonyClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Die Zeremonie, wenn eine Forschung fertig wird. Vorbild ist die Entwicklung in Pokemon:
-- alles andere tritt zurueck, und die Figur bekommt den ganzen Bildschirm.
--
-- Ablauf:
--   1. Die Welt wird dunkel, die Figur bleibt hell.
--   2. Die Kamera umrundet sie langsam und kommt vorne seitlich zum Stehen.
--      Dabei laedt sich ein Klang auf.
--   3. Vorne angekommen: Licht, Belohnungsklang, und die Figur fuehrt die Aktion aus,
--      die gerade staerker geworden ist.
--   4. Daneben steht, was freigeschaltet wurde und was es bewirkt.
--   5. Der SPIELER geht weiter -- per Klick, Tastendruck oder Antippen.
--
-- Der Server haelt die Figur waehrenddessen an und schuetzt sie (TalentTreeService,
-- starteZeremonie). Hier steht nur, was man sieht und hoert.
--
-- ===== Zwei Regeln aus CLAUDE.md, die hier gelten =====
-- Kameraschleifen brauchen eine Session-ID und muessen sich beenden, sobald eine neue
-- Session beginnt -- sonst kaempfen zwei Schleifen um dieselbe Kamera. Deshalb
-- CameraSessionUtils und nicht ein eigener Zaehler.
-- Und: Moduswechsel der Kamera sind sichtbar. Der Wechsel auf Scriptable passiert deshalb
-- im selben Zug wie das erste Setzen der CFrame, nicht ein Bild vorher.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local CameraSessionUtils = require(ReplicatedStorage:WaitForChild("CameraSessionUtils"))
local TalentTreeConfig = require(ReplicatedStorage:WaitForChild("TalentTreeConfig"))

local TalentCeremonyEvent = RemoteEventUtils.GetOrCreate("TalentCeremonyEvent")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== Masse und Zeiten =====
local UMRUNDUNG_SEKUNDEN = 4.2 -- so lange dreht die Kamera

-- Die Kamera FAEHRT HERAN, waehrend sie umrundet. Weit und hoch beginnen, nah und auf
-- Augenhoehe enden -- die Drehung allein ist eine Umschau, erst das Herankommen macht
-- daraus ein Zugehen auf die Figur.
local ABSTAND_START = 34 -- Studs, vor der Skalierung
local ABSTAND_ENDE = 11
local HOEHE_START = 11 -- ueber der Figurmitte, vor der Skalierung
local HOEHE_ENDE = 1.5 -- fast auf Augenhoehe: so sieht man das Gesicht und nicht den Scheitel

-- Die Winkel zaehlen ab der BLICKRICHTUNG DER FIGUR, nicht ab einer Weltachse: 0 Grad ist
-- direkt vor ihr. Anders gaebe es kein "vorne" -- die Figur steht ja, wie sie gerade steht.
--
-- Am Ende 28 Grad: vor der Figur, ein Stueck zur Seite. Genau frontal saehe aus wie ein
-- Passbild; ein Viertel zur Seite gibt Tiefe und laesst das Gesicht trotzdem sehen.
local END_WINKEL = 28
local START_WINKEL = END_WINKEL + 340 -- fast eine volle Runde, von hinten herum

-- Der Klang, der sich auflaedt: derselbe, der beim Fokus-Angriff die Ladephase traegt.
-- Ein eigener waere eine zweite Nummer fuer dieselbe Aussage -- "gleich passiert etwas".
local LADE_SOUND = "rbxassetid://1336756135"

-- Wie tief der scharfe Bereich ist, in Studs vor der Skalierung. Die entscheidende Zahl
-- der ganzen Inszenierung: sie bestimmt, wie viel ausser der Figur noch mitkommt. Knapp
-- gehalten, damit wirklich nur sie scharf steht -- zu knapp, und ihr eigener Ruecken
-- verschwimmt schon.
local FOKUS_RADIUS = 6

-- Welche Aktion zeigt die Figur? Nach dem Effekt-Schluessel des Talents: was staerker
-- geworden ist, soll man sehen. Faellt ein Schluessel durch, schlaegt sie zu -- der Schlag
-- ist die Aktion, die JEDE Figur kann.
local SCHLAG = "rbxassetid://96237359714095"
local AKTION_ANIMATION = {
	BerserkerDamageBonus = SCHLAG,
	OverheatDamageBonus = SCHLAG,
	RootDamageBonus = SCHLAG,
	UltimateDamageBonus = SCHLAG,
	CooldownReduction = "rbxassetid://124162188616993",
	FocusDamageBonus = "rbxassetid://81933564767019",
	AreaRadiusBonus = "rbxassetid://81933564767019",
	BlastRadiusBonus = "rbxassetid://81933564767019",
}

local ladeSound = Instance.new("Sound")
ladeSound.Name = "TalentCeremonyCharge"
ladeSound.SoundId = LADE_SOUND
ladeSound.Volume = 0.6
ladeSound.Parent = SoundService

local belohnungSound = Instance.new("Sound")
belohnungSound.Name = "TalentCeremonyReward"
belohnungSound.SoundId = HudChrome.Sound.Belohnung
belohnungSound.Volume = 0.9
belohnungSound.Parent = SoundService

-- Eingabe der Standardsteuerung. Fehlt das PlayerModule, bleibt die Steuerung eben an --
-- der Server haelt die Figur ohnehin auf Tempo null.
-- Mit ZEITGRENZE: ohne zweites Argument wartet WaitForChild unbegrenzt, und fehlt das
-- Modul einmal, haengt dieses Skript stumm -- kein Fehler, kein Hinweis, und die Zeremonie
-- bliebe fuer immer aus. Lieber eine Warnung und eine Steuerung, die eben anbleibt.
local controls = nil
do
	local scripts = player:WaitForChild("PlayerScripts", 10)
	local modul = scripts and scripts:WaitForChild("PlayerModule", 10)
	if modul then
		local ok, playerModule = pcall(require, modul)
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
		warn("[Kaiju Debug] TalentCeremonyClient: PlayerModule nicht erreichbar -- die "
			.. "Steuerung bleibt waehrend der Zeremonie an. Der Server haelt die Figur "
			.. "trotzdem auf Tempo null.")
	end
end

-- ===== Die Tafel neben der Figur =====
local schirm = Instance.new("ScreenGui")
schirm.Name = "TalentCeremonyGui"
schirm.ResetOnSpawn = false
schirm.IgnoreGuiInset = true
schirm.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
schirm.DisplayOrder = 200
schirm.Enabled = false
schirm.Parent = playerGui

-- ===== Die Vignette =====
--
-- Hier lag einmal eine schwarze Flaeche ueber dem ganzen Bild. Das konnte nicht
-- funktionieren: eine GUI-Flaeche liegt ueber ALLEM, also auch ueber der Figur -- je
-- dunkler die Umgebung wurde, desto dunkler wurde die Figur mit.
--
-- Eine Vignette hat genau diesen Fehler nicht. Sie trifft nur den RAND und laesst die
-- Mitte frei, und die Figur steht in der Mitte. Sie nimmt dem Bild die Ecken, ohne ihm
-- die Aufmerksamkeit zu nehmen.
--
-- Gebaut aus vier Baendern mit Verlauf statt aus einem Bild: ein UIGradient ist linear,
-- einen runden Verlauf gibt es in Roblox nur als Textur. Vier Baender, die sich an den
-- Ecken ueberlagern, ergeben aber genau dort das Dunkelste -- und das ist eine Vignette.
local VIGNETTE_TIEFE = 0.36 -- Anteil der Bildkante, ueber den das Band ausblendet
local VIGNETTE_STAERKE = 0.15 -- Transparenz ganz aussen: 0 waere schwarz, 0.15 fast

local vignetteBaender = {}
local function baueVignetteBand(groesse, lage, drehung)
	local band = Instance.new("Frame")
	band.Name = "VignetteBand"
	band.Size = groesse
	band.Position = lage
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.ZIndex = 1
	band.Parent = schirm

	-- Der Verlauf faengt AUSSEN an (Keypoint 0 liegt in Richtung der Drehung zuerst) und
	-- endet innen durchsichtig.
	local verlauf = Instance.new("UIGradient")
	verlauf.Rotation = drehung
	verlauf.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, VIGNETTE_STAERKE),
		NumberSequenceKeypoint.new(0.55, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	verlauf.Parent = band

	table.insert(vignetteBaender, band)
	return band
end

baueVignetteBand(UDim2.new(1, 0, VIGNETTE_TIEFE, 0), UDim2.new(0, 0, 0, 0), 90) -- oben
baueVignetteBand(UDim2.new(1, 0, VIGNETTE_TIEFE, 0), UDim2.new(0, 0, 1 - VIGNETTE_TIEFE, 0), 270) -- unten
baueVignetteBand(UDim2.new(VIGNETTE_TIEFE, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0) -- links
baueVignetteBand(UDim2.new(VIGNETTE_TIEFE, 0, 1, 0), UDim2.new(1 - VIGNETTE_TIEFE, 0, 0, 0), 180) -- rechts

local function zeigeVignette(sichtbar)
	for _, band in ipairs(vignetteBaender) do
		TweenService:Create(band, TweenInfo.new(sichtbar and 0.9 or 0.4), {
			BackgroundTransparency = sichtbar and 0 or 1,
		}):Play()
	end
end

local tafel = Instance.new("Frame")
tafel.Name = "Tafel"
tafel.AnchorPoint = Vector2.new(1, 0.5)
tafel.Position = UDim2.new(1, -40, 0.5, 0)
tafel.Size = UDim2.new(0, 360, 0, 240)
tafel.Visible = false
tafel.ZIndex = 2
tafel.Parent = schirm
-- Eigener Grund, seit der Schleier weg ist: Text ohne Flaeche darunter steht sonst direkt
-- auf der Stadt, und die ist zwar unscharf, aber nicht ruhig.
HudChrome.Panel(tafel, { radius = HudChrome.Radius.Panel, transparency = 0.12 })
local tafelPolster = Instance.new("UIPadding")
tafelPolster.PaddingTop = UDim.new(0, 18)
tafelPolster.PaddingLeft = UDim.new(0, 18)
tafelPolster.PaddingRight = UDim.new(0, 18)
tafelPolster.Parent = tafel

local tafelKopf = Instance.new("TextLabel")
tafelKopf.Size = UDim2.new(1, 0, 0, 22)
tafelKopf.BackgroundTransparency = 1
HudChrome.Sublabel(tafelKopf, 14)
tafelKopf.TextXAlignment = Enum.TextXAlignment.Left
tafelKopf.Text = "RESEARCH COMPLETE"
tafelKopf.ZIndex = 3
tafelKopf.Parent = tafel

local tafelSymbol = Instance.new("ImageLabel")
tafelSymbol.Size = UDim2.new(0, 84, 0, 84)
tafelSymbol.Position = UDim2.new(0, 0, 0, 34)
tafelSymbol.BackgroundTransparency = 1
tafelSymbol.ScaleType = Enum.ScaleType.Fit
tafelSymbol.ZIndex = 3
tafelSymbol.Parent = tafel

local tafelName = Instance.new("TextLabel")
tafelName.Size = UDim2.new(1, -100, 0, 40)
tafelName.Position = UDim2.new(0, 100, 0, 44)
tafelName.BackgroundTransparency = 1
HudChrome.Label(tafelName, HudChrome.MenuTextSize.Heading)
tafelName.TextXAlignment = Enum.TextXAlignment.Left
tafelName.TextWrapped = true
tafelName.TextColor3 = Color3.new(1, 1, 1)
tafelName.ZIndex = 3
tafelName.Parent = tafel

local tafelWirkung = Instance.new("TextLabel")
tafelWirkung.Size = UDim2.new(1, 0, 0, 84)
tafelWirkung.Position = UDim2.new(0, 0, 0, 132)
tafelWirkung.BackgroundTransparency = 1
HudChrome.MenuBody(tafelWirkung, 17)
tafelWirkung.TextXAlignment = Enum.TextXAlignment.Left
tafelWirkung.TextYAlignment = Enum.TextYAlignment.Top
tafelWirkung.TextWrapped = true
tafelWirkung.TextColor3 = HudChrome.Color.TextSecondary
tafelWirkung.ZIndex = 3
tafelWirkung.Parent = tafel

-- Der Hinweis steht unten in der Mitte und erscheint ERST, wenn die Zeremonie fertig ist.
-- Frueher gezeigt waere er eine Aufforderung, sie zu ueberspringen.
local weiterHinweis = Instance.new("TextLabel")
weiterHinweis.Name = "Weiter"
weiterHinweis.AnchorPoint = Vector2.new(0.5, 1)
weiterHinweis.Position = UDim2.new(0.5, 0, 1, -40)
weiterHinweis.Size = UDim2.new(0, 400, 0, 24)
weiterHinweis.BackgroundTransparency = 1
HudChrome.Sublabel(weiterHinweis, 14)
weiterHinweis.Text = ""
weiterHinweis.Visible = false
weiterHinweis.ZIndex = 3
weiterHinweis.Parent = schirm

-- ===== Zustand =====
local laeuft = false
local session = nil
local farbfilter = nil
local tiefenschaerfe = nil
local glut = nil
local eingaben = {}

local function figurTeile()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return character, root
end

local function raeumeAuf()
	if farbfilter then
		farbfilter:Destroy()
		farbfilter = nil
	end
	if tiefenschaerfe then
		tiefenschaerfe:Destroy()
		tiefenschaerfe = nil
	end
	if glut then
		glut:Destroy()
		glut = nil
	end
	for _, verbindung in ipairs(eingaben) do
		verbindung:Disconnect()
	end
	eingaben = {}
	ladeSound:Stop()
	for _, band in ipairs(vignetteBaender) do
		band.BackgroundTransparency = 1
	end
	schirm.Enabled = false
	tafel.Visible = false
	weiterHinweis.Visible = false

	local camera = Workspace.CurrentCamera
	if camera then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.CameraType = Enum.CameraType.Custom
	end
	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
end

local function beende()
	if not laeuft then
		return
	end
	laeuft = false
	session = nil
	raeumeAuf()
	TalentCeremonyEvent:FireServer()
end

-- ===== Die Kamera umrundet die Figur =====
--
-- Gerechnet wird je Bild aus dem aktuellen Standort der Figur, nicht einmal vorweg: die
-- Figur steht zwar still, aber sie kann auf einem Fahrzeug oder einer fallenden Truemmerlage
-- stehen -- eine einmal gemerkte Mitte laege dann daneben.
local function umrunde(sessionId, dauer)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local begonnen = os.clock()
	local verbindung
	verbindung = RunService.RenderStepped:Connect(function()
		if not CameraSessionUtils.IsCurrent(sessionId) then
			verbindung:Disconnect()
			return
		end
		local character, root = figurTeile()
		if not root then
			verbindung:Disconnect()
			return
		end

		local fortschritt = math.clamp((os.clock() - begonnen) / dauer, 0, 1)
		-- Weich anlaufen und weich stehenbleiben: eine Drehung mit gleichmaessigem Tempo
		-- wirkt wie ein Messgeraet, nicht wie eine Inszenierung.
		local weich = fortschritt * fortschritt * (3 - 2 * fortschritt)
		local winkel = START_WINKEL + (END_WINKEL - START_WINKEL) * weich
		local abstand = ABSTAND_START + (ABSTAND_ENDE - ABSTAND_START) * weich
		local hoehe = HOEHE_START + (HOEHE_ENDE - HOEHE_START) * weich

		local skala = 1
		local ok, s = pcall(function()
			return character:GetScale()
		end)
		if ok and type(s) == "number" and s > 0 then
			skala = s
		end

		-- Gezielt wird auf den KOPF, nicht auf die Mitte der Figur. Am Ende steht die
		-- Kamera nah und tief -- auf die Mitte gerichtet saehe man von dort den Brustkorb
		-- und das Kinn.
		local kopf = character:FindFirstChild("Head")
		local ziel = kopf and kopf.Position or (root.Position + Vector3.new(0, 2 * skala, 0))

		-- Die Blickrichtung der Figur ist die Null. Flach gelegt, damit eine Figur an einem
		-- Hang die Kamera nicht mit in die Schraege zieht.
		local vorne = root.CFrame.LookVector
		vorne = Vector3.new(vorne.X, 0, vorne.Z)
		if vorne.Magnitude < 0.001 then
			vorne = Vector3.new(0, 0, 1)
		else
			vorne = vorne.Unit
		end

		local richtung = CFrame.Angles(0, math.rad(winkel), 0) * vorne
		local auge = ziel + richtung * (abstand * skala) + Vector3.new(0, hoehe * skala, 0)
		camera.CFrame = CFrame.lookAt(auge, ziel)

		-- Die Schaerfe folgt der Kamera. Gemessen wird der echte Abstand Auge zu Kopf --
		-- nicht der Radius der Umrundung, denn die Kamera steht auch ueber der Figur.
		if tiefenschaerfe then
			tiefenschaerfe.FocusDistance = (auge - ziel).Magnitude
			tiefenschaerfe.InFocusRadius = FOKUS_RADIUS * skala
		end

		if fortschritt >= 1 then
			verbindung:Disconnect()
		end
	end)
	table.insert(eingaben, verbindung)
end

local function spieleAktion(effectKey)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = AKTION_ANIMATION[effectKey] or SCHLAG
	local ok, spur = pcall(function()
		return humanoid:LoadAnimation(animation)
	end)
	if ok and spur then
		spur.Priority = Enum.AnimationPriority.Action
		spur:Play(0.1)
	end
end

local function starte(factionName, talentId, energyType, effectKey)
	if laeuft then
		return
	end
	local character, root = figurTeile()
	if not root then
		-- Ohne Figur gibt es nichts zu zeigen. Dem Server sofort Bescheid geben, sonst
		-- bliebe er auf seiner Sperre sitzen, bis die Obergrenze greift.
		TalentCeremonyEvent:FireServer()
		return
	end
	laeuft = true
	session = CameraSessionUtils.Start("TalentZeremonie")

	local talent = TalentTreeConfig.FindTalent(factionName, talentId)
	local farbe = HudChrome.EnergyColor[energyType] or HudChrome.Color.Accent

	-- Die Welt wird dunkel -- ueber das Licht der Szene, nicht ueber eine schwarze Flaeche
	-- davor. Eine Flaeche wuerde die Figur mit verdecken; der Farbfilter nimmt der ganzen
	-- Welt die Helligkeit, und das Highlight holt die Figur wieder heraus.
	-- ===== Alles ausser der Figur wird WEICH =====
	--
	-- Tiefenschaerfe: was auf der Entfernung der Figur liegt, bleibt scharf, alles davor
	-- und dahinter verschwimmt. Der Radius ist klein gehalten -- er bestimmt, wie viel
	-- ausser der Figur noch mitkommt.
	--
	-- Die Entfernung wird in jedem Bild nachgezogen (siehe umrunde), denn die Kamera faehrt
	-- ja heran. Ein fester Wert waere am Anfang scharf und am Ende daneben.
	tiefenschaerfe = Instance.new("DepthOfFieldEffect")
	tiefenschaerfe.Name = "TalentCeremonyFocus"
	tiefenschaerfe.FocusDistance = 30
	tiefenschaerfe.InFocusRadius = FOKUS_RADIUS
	tiefenschaerfe.FarIntensity = 0
	tiefenschaerfe.NearIntensity = 0
	tiefenschaerfe.Parent = Lighting
	-- Beide auf Anschlag: alles, was nicht auf der Entfernung der Figur liegt, verschwimmt
	-- so weit, wie Roblox es hergibt. Das ist die ganze Trennung -- deshalb darf sie nicht
	-- zurueckhaltend sein.
	TweenService:Create(tiefenschaerfe, TweenInfo.new(0.9), {
		FarIntensity = 1,
		NearIntensity = 1,
	}):Play()

	farbfilter = Instance.new("ColorCorrectionEffect")
	farbfilter.Name = "TalentCeremonyGrade"
	farbfilter.Brightness = 0
	farbfilter.Contrast = 0
	farbfilter.Saturation = 0
	farbfilter.Parent = Lighting
	-- Nur Farbe, keine Helligkeit: das Freistellen macht die Schaerfe. Ein abgedunkeltes
	-- Bild kam dazu und war ein Umweg -- es nahm auch der Figur etwas, die dafuer heller
	-- leuchten musste, und am Ende kaempften zwei Mittel um dieselbe Wirkung.
	TweenService:Create(farbfilter, TweenInfo.new(0.9), {
		Contrast = 0.12,
		Saturation = -0.3,
	}):Play()

	-- ===== Waehrend der Umrundung wird die Figur NICHT beleuchtet =====
	--
	-- Hier standen zwei Lampen an ihr, damit sie sich vom Grund abhebt. Sie stoerten: die
	-- Figur ist keine Vitrine, und eine, die vier Sekunden lang angestrahlt wird, sieht
	-- ausgestellt aus statt eindrucksvoll.
	--
	-- Sie braucht das Licht auch nicht. Freigestellt wird sie ueber die SCHAERFE und den
	-- Rand (Tiefenschaerfe und Vignette) -- beides trifft die Umgebung, nicht sie. Was
	-- bleibt, ist ihr eigenes Aussehen in der Beleuchtung der Welt, und das ist der Punkt.
	--
	-- Ein Leuchten gibt es weiter, aber nur EINMAL: in dem Augenblick, in dem die Kamera
	-- vorne ankommt. Bis dahin ist die Glut unsichtbar.
	glut = Instance.new("Highlight")
	glut.Name = "TalentCeremonyGlow"
	glut.FillColor = farbe
	glut.OutlineColor = Color3.new(1, 1, 1)
	glut.FillTransparency = 1
	glut.OutlineTransparency = 1
	glut.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glut.Parent = character

	schirm.Enabled = true
	zeigeVignette(true)

	if controls then
		pcall(function()
			controls:Disable()
		end)
	end

	ladeSound:Play()
	umrunde(session, UMRUNDUNG_SEKUNDEN)

	-- Der Augenblick, in dem die Kamera vorne ankommt.
	task.delay(UMRUNDUNG_SEKUNDEN, function()
		if not laeuft then
			return
		end
		ladeSound:Stop()
		belohnungSound:Play()
		spieleAktion(effectKey)

		-- Das Aufleuchten -- das einzige Licht der ganzen Sequenz, und deshalb traegt es
		-- den Augenblick. Fuellung und Umriss fahren zusammen hoch und blenden wieder aus.
		if glut then
			glut.FillTransparency = 0.25
			glut.OutlineTransparency = 0
			TweenService:Create(glut, TweenInfo.new(0.9), {
				FillTransparency = 0.9,
				OutlineTransparency = 0.6,
			}):Play()
		end

		tafelSymbol.Image = HudChrome.TalentIcon[talentId] or ""
		tafelSymbol.Visible = tafelSymbol.Image ~= ""
		tafelName.Text = talent and talent.name or talentId
		tafelKopf.TextColor3 = farbe
		tafelWirkung.Text = talent and talent.description or ""
		tafel.Visible = true

		weiterHinweis.Text = UserInputService.TouchEnabled and "TAP TO CONTINUE" or "CLICK OR PRESS ANY KEY TO CONTINUE"
		weiterHinweis.Visible = true

		-- Erst JETZT auf Eingaben hoeren. Wer vorher klickt, soll die Zeremonie nicht
		-- abbrechen -- sie dauert vier Sekunden, und in dieser Zeit klickt man im Spiel
		-- ohnehin dauernd.
		table.insert(eingaben, UserInputService.InputBegan:Connect(function(input, verarbeitet)
			if verarbeitet then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.Keyboard
				or input.UserInputType == Enum.UserInputType.Gamepad1
			then
				beende()
			end
		end))
	end)
end

TalentCeremonyEvent.OnClientEvent:Connect(function(factionName, talentId, energyType, effectKey)
	print("[Kaiju Debug] Zeremonie:", factionName, talentId, energyType, effectKey)
	starte(factionName, talentId, energyType, effectKey)
end)

-- Stirbt die Figur mittendrin, ist die Zeremonie vorbei -- und der Server muss es erfahren.
player.CharacterRemoving:Connect(beende)

print("[Kaiju Debug] TalentCeremonyClient bereit.")
