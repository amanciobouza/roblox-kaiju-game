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
local ABSTAND = 14 -- Studs von der Figur, vor der Skalierung
local HOEHE = 5 -- Kamerahoehe ueber der Figurmitte, vor der Skalierung
-- Endwinkel: vorne SEITLICH, nicht frontal. Frontal sieht aus wie ein Passbild; ein
-- Viertel zur Seite gibt der Figur Tiefe und zeigt die Schulter.
local END_WINKEL = 35
local START_WINKEL = END_WINKEL + 300 -- knapp eine volle Runde von hinten herum

-- Der Klang, der sich auflaedt: derselbe, der beim Fokus-Angriff die Ladephase traegt.
-- Ein eigener waere eine zweite Nummer fuer dieselbe Aussage -- "gleich passiert etwas".
local LADE_SOUND = "rbxassetid://1336756135"

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

-- Der Schleier liegt UEBER der Welt und unter der Tafel. Er nimmt der Umgebung das Licht,
-- waehrend das Highlight an der Figur sie hell haelt -- so entsteht "dunkel ausser der
-- Spielfigur", ohne dass irgendetwas ausgeschnitten werden muesste.
local schleier = Instance.new("Frame")
schleier.Name = "Schleier"
schleier.Size = UDim2.new(1, 0, 1, 0)
schleier.BackgroundColor3 = Color3.new(0, 0, 0)
schleier.BackgroundTransparency = 1
schleier.BorderSizePixel = 0
schleier.ZIndex = 1
schleier.Parent = schirm

local tafel = Instance.new("Frame")
tafel.Name = "Tafel"
tafel.AnchorPoint = Vector2.new(1, 0.5)
tafel.Position = UDim2.new(1, -40, 0.5, 0)
tafel.Size = UDim2.new(0, 360, 0, 240)
tafel.BackgroundTransparency = 1
tafel.Visible = false
tafel.ZIndex = 2
tafel.Parent = schirm

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
	if glut then
		glut:Destroy()
		glut = nil
	end
	for _, verbindung in ipairs(eingaben) do
		verbindung:Disconnect()
	end
	eingaben = {}
	ladeSound:Stop()
	schirm.Enabled = false
	tafel.Visible = false
	weiterHinweis.Visible = false
	schleier.BackgroundTransparency = 1

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

		local skala = 1
		local ok, s = pcall(function()
			return character:GetScale()
		end)
		if ok and type(s) == "number" and s > 0 then
			skala = s
		end

		local mitte = root.Position + Vector3.new(0, 2 * skala, 0)
		local richtung = CFrame.Angles(0, math.rad(winkel), 0) * Vector3.new(0, 0, 1)
		local auge = mitte + richtung * (ABSTAND * skala) + Vector3.new(0, HOEHE * skala, 0)
		camera.CFrame = CFrame.lookAt(auge, mitte)

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
	farbfilter = Instance.new("ColorCorrectionEffect")
	farbfilter.Name = "TalentCeremonyDim"
	farbfilter.Brightness = 0
	farbfilter.Contrast = 0
	farbfilter.Saturation = 0
	farbfilter.Parent = Lighting
	TweenService:Create(farbfilter, TweenInfo.new(0.8), {
		Brightness = -0.35,
		Contrast = 0.15,
		Saturation = -0.6,
	}):Play()

	glut = Instance.new("Highlight")
	glut.Name = "TalentCeremonyGlow"
	glut.FillColor = farbe
	glut.OutlineColor = Color3.new(1, 1, 1)
	glut.FillTransparency = 1
	glut.OutlineTransparency = 0.4
	glut.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glut.Parent = character

	schirm.Enabled = true
	TweenService:Create(schleier, TweenInfo.new(0.8), { BackgroundTransparency = 0.45 }):Play()

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

		-- Das Aufleuchten: die Fuellung des Highlights faehrt kurz hoch und wieder zurueck.
		if glut then
			glut.FillTransparency = 0.25
			TweenService:Create(glut, TweenInfo.new(0.9), { FillTransparency = 0.85 }):Play()
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
