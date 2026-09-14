-- VERSION: 2026-08-25 #2 (RemoteEventUtils-Umstellung)
-- LocalScript: GiftClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut den Geschenk-Bildschirm (aufgerufen über das Menü). Die zwölf Geschenke werden über
-- die Spielzeit nach und nach bereit -- das erste nach gut einer Minute, das letzte nach
-- zwei Stunden, mit immer grösser werdenden Abständen.
--
-- Dargestellt als STRECKE, nicht als Raster: die Sitzung läuft von links nach rechts, die
-- Geschenke sitzen als Stationen an ihrer echten zeitlichen Stelle, und eine Marke zeigt,
-- wo man gerade steht. Die Begründung steht unten bei der Bahn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local ClaimGiftEvent = RemoteEventUtils.GetOrCreate("ClaimGiftEvent")
local giftCountValue = ReplicatedStorage:WaitForChild("GiftCount")
local giftUnlockTimesFolder = ReplicatedStorage:WaitForChild("GiftUnlockTimes")
local giftDescriptionsFolder = ReplicatedStorage:WaitForChild("GiftDescriptions")
-- Symbole liegen seit der Trennung in einem eigenen Ordner. Fehlt er (aelterer Server),
-- faellt die Karte auf das Geschenkpaket zurueck statt leer zu bleiben.
local giftIconsFolder = ReplicatedStorage:WaitForChild("GiftIcons", 10)
-- Die Sorte je Geschenk -- erst damit laesst sich das richtige Bild waehlen. Mit
-- Zeitgrenze, weil ein aelterer Server sie nicht anlegt; dann traegt das Emoji weiter.
local giftTypesFolder = ReplicatedStorage:WaitForChild("GiftTypes", 10)

-- Fuer die Meldung im Spiel, wenn ein Geschenk bereit wird.
local HudToast = require(ReplicatedStorage:WaitForChild("HudToast"))

local screenGui = Instance.new("ScreenGui")
screenGui.IgnoreGuiInset = true
-- In diesem Gui liegt NUR das Geschenk-Panel, kein HUD -- hier genuegt es, die Ebene
-- anzuheben, statt ein zweites ScreenGui anzulegen.
screenGui.DisplayOrder = 100
screenGui.Name = "GiftGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== Die Strecke =====
--
-- Hier stand ein Raster aus zwoelf gleich grossen Kacheln. Das war der Fehler, und zwar
-- kein gestalterischer, sondern ein inhaltlicher: die zwoelf Geschenke SIND keine
-- Geschwister. Zwischen dem ersten und dem letzten liegen zwei Stunden, die Abstaende
-- werden nach hinten immer groesser, und es gibt zu jedem Zeitpunkt genau EINES, das als
-- naechstes kommt. Ein Raster sagt "such dir was aus". Man kann sich hier nichts aussuchen.
--
-- Also eine Bahn statt eines Regals: die Sitzung von links nach rechts, die Geschenke als
-- Stationen darauf -- an ihrer ECHTEN zeitlichen Stelle. Vorne draengen sie sich, hinten
-- wird es weit. Dieses Auseinanderziehen ist selbst die Aussage: spaeter dauert laenger.
--
-- Dazu drei Dinge, die das Raster nicht konnte:
--   Eine Marke zeigt, wo man JETZT steht, und sie bewegt sich sichtbar.
--   Nur EIN Countdown laeuft -- der des naechsten. Elf gleichzeitig waren Laerm.
--   Die Sitzungsdauer steht gross da. Die ganze Sache handelt von Zeit; sie kam auf dem
--   Bildschirm bisher nicht vor.
local schirm = HudChrome.Screen(screenGui, {
	name = "GiftPanel",
	title = "TIME GIFTS",
	subtitle = "",
})
local panel = schirm.panel
local statusLabel = schirm.subtitle
local giftCloseButton = schirm.close

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(panel)

giftCloseButton.MouseButton1Click:Connect(function()
	panel.Visible = false
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	end
end)

local GIFT_COUNT = giftCountValue.Value

-- Die Gesamtdauer steht nicht extra im ReplicatedStorage -- sie IST die Freischaltzeit des
-- letzten Geschenks. Eine zweite Quelle dafuer waere die naechste Stelle, die auseinander
-- laeuft, wenn jemand am Server die Kurve aendert.
local function unlockTime(n)
	local value = giftUnlockTimesFolder:FindFirstChild("Gift" .. n)
	return value and value.Value or 0
end
local GESAMTDAUER = math.max(unlockTime(GIFT_COUNT), 1)

local function giftType(n)
	local value = giftTypesFolder and giftTypesFolder:FindFirstChild("Gift" .. n)
	return value and value.Value or ""
end

local function giftDescription(n)
	local value = giftDescriptionsFolder:FindFirstChild("Gift" .. n)
	return value and value.Value or ""
end

-- Bild wenn hochgeladen, sonst das Emoji vom Server. Dieselbe Ausweichregel wie bei den
-- Energietypen: leer heisst nicht kaputt, es heisst "noch nicht da".
local function giftBild(n)
	return HudChrome.GiftIcon[giftType(n)] or ""
end

local function giftEmoji(n)
	local value = giftIconsFolder and giftIconsFolder:FindFirstChild("Gift" .. n)
	return value and value.Value or "\u{1F381}"
end

-- Setzt Bild ODER Zeichen auf einen vorbereiteten Platz.
local function zeigeSymbol(bildLabel, textLabel, n)
	local bild = giftBild(n)
	if bild ~= "" then
		bildLabel.Image = bild
		bildLabel.Visible = true
		textLabel.Visible = false
	else
		bildLabel.Visible = false
		textLabel.Text = giftEmoji(n)
		textLabel.Visible = true
	end
end

local function formatLang(seconds)
	seconds = math.max(math.floor(seconds), 0)
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local sec = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- ===== Kopfzeile rechts: die gespielte Zeit =====
--
-- Sie steht im Kopf und nicht auf der Bahn, weil sie nicht zu einem einzelnen Geschenk
-- gehoert, sondern zur ganzen Sitzung. Und sie steht ueberhaupt da, weil die zwoelf
-- Geschenke nichts anderes messen als sie.
local sessionLabel = Instance.new("TextLabel")
sessionLabel.Name = "SessionClock"
sessionLabel.AnchorPoint = Vector2.new(1, 0)
sessionLabel.Size = UDim2.new(0, 200, 0, 34)
sessionLabel.Position = UDim2.new(1, -88, 0, 12)
sessionLabel.BackgroundTransparency = 1
sessionLabel.TextXAlignment = Enum.TextXAlignment.Right
sessionLabel.Text = "0:00"
sessionLabel.ZIndex = 3
sessionLabel.Parent = schirm.header
HudChrome.NumberBold(sessionLabel, 28)

local sessionCaption = Instance.new("TextLabel")
sessionCaption.Name = "SessionCaption"
sessionCaption.AnchorPoint = Vector2.new(1, 0)
sessionCaption.Size = UDim2.new(0, 200, 0, 18)
sessionCaption.Position = UDim2.new(1, -88, 0, 46)
sessionCaption.BackgroundTransparency = 1
sessionCaption.TextXAlignment = Enum.TextXAlignment.Right
sessionCaption.Text = "THIS SESSION"
sessionCaption.ZIndex = 3
sessionCaption.Parent = schirm.header
HudChrome.MenuCaption(sessionCaption, 13)

-- ===== Der Belohnungston =====
--
-- Ein Geschenk abzuholen ist der einzige Augenblick in diesem Bildschirm, in dem etwas
-- PASSIERT -- alles andere ist Warten und Zusehen. Ohne Klang bleibt davon ein Rechteck,
-- das die Farbe wechselt.
local CLAIM_SOUND_ID = "rbxassetid://4612378364"

local claimSound = Instance.new("Sound")
claimSound.Name = "GiftClaimSound"
claimSound.SoundId = CLAIM_SOUND_ID
claimSound.Volume = 0.85
claimSound.Parent = SoundService

local function holeAb(n)
	local claimedFolder = player:FindFirstChild("ClaimedGifts")
	local marker = claimedFolder and claimedFolder:FindFirstChild("Gift" .. n)
	local sessionStart = player:GetAttribute("SessionStartTime")
	if not marker or marker.Value or not sessionStart then
		return false
	end
	if Workspace:GetServerTimeNow() - sessionStart < unlockTime(n) then
		return false
	end
	ClaimGiftEvent:FireServer(n)
	claimSound:Play()
	return true
end

-- ===== Die Reihe der Karten =====
--
-- Hier stand EINE Karte, die immer nur das naechste Geschenk zeigte. Das war falsch, sobald
-- mehrere gleichzeitig bereitliegen -- und das ist der Normalfall: wer eine Stunde spielt,
-- ohne das Menue zu oeffnen, hat sechs offene Geschenke. Eine Karte nach der anderen
-- abzuarbeiten sah aus wie eine Warteschlange, und man wusste nie, wie viele noch kommen.
--
-- Jetzt eine Reihe: je eine Karte fuer JEDES abholbare Geschenk, und ganz rechts die Karte
-- fuer das naechste, das noch dauert. Die Reihenfolge ist die der Bahn darunter -- was
-- frueher dran war, steht links.
--
-- Ein Schiebefeld, kein Raster: bei zwoelf offenen Geschenken passt die Reihe auf kein
-- Geraet. Waagerecht schieben bleibt dieselbe Bewegung wie die Bahn darunter; ein Raster
-- haette eine zweite Leserichtung eingefuehrt.
local KARTE_BREITE = 208
local KARTE_NAECHST_BREITE = 300
local KARTE_HOEHE = 168

local kartenBereich = Instance.new("ScrollingFrame")
kartenBereich.Name = "GiftCards"
kartenBereich.Position = UDim2.new(0, 32, 0, 16)
kartenBereich.Size = UDim2.new(1, -64, 0, KARTE_HOEHE + 14)
kartenBereich.BackgroundTransparency = 1
kartenBereich.BorderSizePixel = 0
kartenBereich.ScrollBarThickness = 5
kartenBereich.ScrollingDirection = Enum.ScrollingDirection.X
kartenBereich.CanvasSize = UDim2.new(0, 0, 0, 0)
kartenBereich.AutomaticCanvasSize = Enum.AutomaticSize.X
kartenBereich.ZIndex = 4
kartenBereich.Parent = schirm.content

local kartenLayout = Instance.new("UIListLayout")
kartenLayout.FillDirection = Enum.FillDirection.Horizontal
kartenLayout.SortOrder = Enum.SortOrder.LayoutOrder
kartenLayout.Padding = UDim.new(0, 12)
kartenLayout.Parent = kartenBereich

-- Baut eine Karte. Beide Sorten teilen sich den Aufbau -- Symbol links, Beschriftung
-- rechts, grosse Zahl darunter --, sie unterscheiden sich nur in Breite und darin, was in
-- der grossen Zeile steht: CLAIM oder ein Countdown.
local function baueKarte(name, breite, anklickbar)
	local karte = anklickbar and Instance.new("TextButton") or Instance.new("Frame")
	karte.Name = name
	karte.Size = UDim2.new(0, breite, 0, KARTE_HOEHE)
	karte.Visible = false
	karte.ZIndex = 5
	if anklickbar then
		karte.AutoButtonColor = false
		karte.Text = ""
	end
	karte.Parent = kartenBereich
	local _, rand = HudChrome.Panel(karte, {
		radius = HudChrome.Radius.Panel,
		fill = HudChrome.Color.PanelRaised,
		transparency = 0,
	})

	local kaption = Instance.new("TextLabel")
	kaption.Size = UDim2.new(1, -28, 0, 18)
	kaption.Position = UDim2.new(0, 16, 0, 12)
	kaption.BackgroundTransparency = 1
	kaption.TextXAlignment = Enum.TextXAlignment.Left
	kaption.Text = ""
	kaption.ZIndex = 6
	kaption.Parent = karte
	HudChrome.MenuCaption(kaption, 13)

	local bild = Instance.new("ImageLabel")
	bild.Size = UDim2.new(0, 52, 0, 52)
	bild.Position = UDim2.new(0, 16, 0, 38)
	bild.BackgroundTransparency = 1
	bild.ScaleType = Enum.ScaleType.Fit
	bild.Visible = false
	bild.ZIndex = 6
	bild.Parent = karte

	local zeichen = Instance.new("TextLabel")
	zeichen.Size = UDim2.new(0, 52, 0, 52)
	zeichen.Position = UDim2.new(0, 16, 0, 38)
	zeichen.BackgroundTransparency = 1
	zeichen.TextScaled = true
	zeichen.Text = ""
	zeichen.ZIndex = 6
	zeichen.Parent = karte

	local titel = Instance.new("TextLabel")
	titel.Size = UDim2.new(1, -84, 0, 52)
	titel.Position = UDim2.new(0, 76, 0, 38)
	titel.BackgroundTransparency = 1
	titel.TextXAlignment = Enum.TextXAlignment.Left
	titel.TextYAlignment = Enum.TextYAlignment.Center
	titel.Text = ""
	titel.ZIndex = 6
	titel.Parent = karte
	HudChrome.MenuBody(titel, HudChrome.MenuTextSize.Caption)

	local zahl = Instance.new("TextLabel")
	zahl.Size = UDim2.new(1, -32, 0, 40)
	zahl.Position = UDim2.new(0, 16, 0, 100)
	zahl.BackgroundTransparency = 1
	zahl.TextXAlignment = Enum.TextXAlignment.Left
	zahl.Text = ""
	zahl.ZIndex = 6
	zahl.Parent = karte
	HudChrome.NumberBold(zahl, 32)

	local schacht = Instance.new("Frame")
	schacht.Size = UDim2.new(1, -32, 0, 5)
	schacht.Position = UDim2.new(0, 16, 1, -18)
	schacht.BackgroundColor3 = HudChrome.Color.PanelSunken
	schacht.BorderSizePixel = 0
	schacht.ZIndex = 6
	schacht.Parent = karte

	local balken = Instance.new("Frame")
	balken.Size = UDim2.new(0, 0, 1, 0)
	balken.BackgroundColor3 = HudChrome.Color.Ready
	balken.BorderSizePixel = 0
	balken.ZIndex = 7
	balken.Parent = schacht

	return {
		karte = karte,
		rand = rand,
		kaption = kaption,
		bild = bild,
		zeichen = zeichen,
		titel = titel,
		zahl = zahl,
		balken = balken,
	}
end

-- Eine Abhol-Karte je Geschenk, im Voraus gebaut und dann nur noch ein- und ausgeblendet.
-- Karten bei jedem Bild neu anzulegen waere zwoelf Instanzen pro Bild.
local claimKarten = {}
for n = 1, GIFT_COUNT do
	local eintrag = baueKarte("ClaimCard" .. n, KARTE_BREITE, true)
	eintrag.kaption.Text = "READY"
	eintrag.zahl.Text = "CLAIM"
	eintrag.zahl.TextColor3 = HudChrome.Color.Ready
	eintrag.rand.Color = HudChrome.Color.Ready
	eintrag.balken.Size = UDim2.new(1, 0, 1, 0)
	zeigeSymbol(eintrag.bild, eintrag.zeichen, n)
	eintrag.titel.Text = giftDescription(n)

	eintrag.karte.MouseButton1Click:Connect(function()
		if not holeAb(n) then
			return
		end
		-- Kurzer Stoss am Rahmen, dieselbe Bewegungssprache wie bei den Alarmsternen.
		eintrag.rand.Color = Color3.new(1, 1, 1)
		eintrag.rand.Thickness = 3
		TweenService:Create(eintrag.rand, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			Color = HudChrome.Color.Ready,
			Thickness = HudChrome.BorderThickness,
		}):Play()
	end)

	claimKarten[n] = eintrag
end

-- Und eine fuer das, was noch dauert. Sie ist breiter: sie traegt einen Countdown, der
-- laeuft, und der soll nicht neben "CLAIM" untergehen.
local naechsteKarte = baueKarte("NextGiftCard", KARTE_NAECHST_BREITE, false)

-- ===== Die Bahn =====
--
-- Sie ist das Hauptstueck dieses Bildschirms, nicht seine Fusszeile -- also ist sie gross.
-- Die erste Fassung hatte 18 Pixel grosse Punkte und 34 Pixel grosse Symbole; man sah, DASS
-- da etwas liegt, aber nicht WAS. Ein Symbol, das man nicht erkennt, kann man auch weglassen.
--
-- ===== Warum die Stationen abwechselnd oben und unten stehen =====
--
-- Grosse Symbole vertragen sich schlecht mit den echten Abstaenden: die ersten drei
-- Geschenke liegen auf den ersten acht Prozent der Bahn, auf tausend Pixeln also rund
-- vierzig auseinander. Ein 68 Pixel breites Symbol passt da nicht zweimal nebeneinander.
--
-- Die Stationen zu VERSCHIEBEN kam nicht in Frage -- der Abstand ist die Aussage dieses
-- Bildschirms. Also stehen sie abwechselnd ueber und unter der Bahn. Der waagerechte
-- Abstand zwischen zwei Symbolen DERSELBEN Seite ist damit doppelt so gross, und die
-- Punkte bleiben, wo sie hingehoeren.
local BAHN_Y = 0.66 -- Anteil der Inhaltshoehe; darueber liegt die Kartenreihe
local BAHN_RAND = 56
local PUNKT = 26
local PUNKT_BEREIT = 40
local STATION_BREITE = 92
local STATION_HOEHE = 260 -- Platz fuer Symbol und Zeit auf BEIDEN Seiten der Bahn
local SYMBOL = 68

local bahn = Instance.new("Frame")
bahn.Name = "Track"
bahn.AnchorPoint = Vector2.new(0, 0.5)
bahn.Size = UDim2.new(1, -BAHN_RAND * 2, 0, 5)
bahn.Position = UDim2.new(0, BAHN_RAND, BAHN_Y, 0)
bahn.BackgroundColor3 = HudChrome.Color.BorderDim
bahn.BorderSizePixel = 0
bahn.ZIndex = 2
bahn.Parent = schirm.content

-- Der zurueckgelegte Teil der Bahn ist hell. Damit ist die Bahn selbst schon die Antwort
-- auf "wie weit bin ich" -- ohne dass man eine Zahl lesen muesste.
local bahnGelaufen = Instance.new("Frame")
bahnGelaufen.Name = "TrackWalked"
bahnGelaufen.Size = UDim2.new(0, 0, 1, 0)
bahnGelaufen.BackgroundColor3 = HudChrome.Color.Border
bahnGelaufen.BorderSizePixel = 0
bahnGelaufen.ZIndex = 3
bahnGelaufen.Parent = bahn

-- Die Jetzt-Marke. Sie reicht jetzt ueber die ganze Hoehe der Stationen -- eine kurze
-- Linie zwischen zwei grossen Symbolen faende man nicht wieder.
local marke = Instance.new("Frame")
marke.Name = "NowMarker"
marke.AnchorPoint = Vector2.new(0.5, 0.5)
marke.Size = UDim2.new(0, 2, 0, STATION_HOEHE - 40)
marke.Position = UDim2.new(0, 0, 0.5, 0)
marke.BackgroundColor3 = HudChrome.Color.BorderBright
marke.BorderSizePixel = 0
marke.ZIndex = 6
marke.Parent = bahn

-- Eine Beschriftung fuer die Marke: ohne sie ist ein senkrechter Strich nur ein Strich.
local markeLabel = Instance.new("TextLabel")
markeLabel.Name = "NowLabel"
markeLabel.AnchorPoint = Vector2.new(0.5, 1)
markeLabel.Size = UDim2.new(0, 90, 0, 18)
markeLabel.Position = UDim2.new(0.5, 0, 0, -4)
markeLabel.BackgroundTransparency = 1
markeLabel.Text = "NOW"
markeLabel.ZIndex = 7
markeLabel.Parent = marke
HudChrome.Label(markeLabel, 14)
markeLabel.TextColor3 = HudChrome.Color.BorderBright

local giftCells = {} -- [n] = { knopf=, punkt=, ring=, bild=, zeichen=, zeitLabel=, oben= }

for n = 1, GIFT_COUNT do
	local anteil = math.clamp(unlockTime(n) / GESAMTDAUER, 0, 1)
	local oben = (n % 2 == 1) -- ungerade oberhalb, gerade unterhalb

	-- Der ganze Bereich ist der Knopf, nicht nur der Punkt.
	--
	-- Vorher war der Punkt selbst der Knopf, und das Symbol darueber ein Kind AUSSERHALB
	-- seines Rechtecks -- ein Klick darauf ging ins Leere, weil Roblox je Objekt trifft und
	-- ein ImageLabel keine Eingabe annimmt. Man musste also ausgerechnet das kleinste Stueck
	-- der Station treffen.
	local knopf = Instance.new("TextButton")
	knopf.Name = "Gift" .. n
	knopf.AnchorPoint = Vector2.new(0.5, 0.5)
	knopf.Size = UDim2.new(0, STATION_BREITE, 0, STATION_HOEHE)
	knopf.Position = UDim2.new(anteil, 0, 0.5, 0)
	knopf.BackgroundTransparency = 1
	knopf.AutoButtonColor = false
	knopf.Text = ""
	knopf.ZIndex = 4
	knopf.Parent = bahn

	local punkt = Instance.new("Frame")
	punkt.Name = "Dot"
	punkt.AnchorPoint = Vector2.new(0.5, 0.5)
	punkt.Size = UDim2.new(0, PUNKT, 0, PUNKT)
	punkt.Position = UDim2.new(0.5, 0, 0.5, 0)
	punkt.ZIndex = 5
	punkt.Parent = knopf
	local _, ring = HudChrome.Pill(punkt, { fill = HudChrome.Color.PanelSunken, transparency = 0 })

	-- Symbol und Zeit sitzen auf der Seite, die dieser Station zugeteilt ist. Beide sind
	-- Kinder des Knopfes, damit ein Klick ueberall in der Station zaehlt.
	--   oben:   Zeit 6..26, Symbol 32..100, Stiel 100..117, Punkt um 130
	--   unten:  Punkt um 130, Stiel 143..160, Symbol 160..228, Zeit 234..254
	local symbolY = oben and (STATION_HOEHE / 2 - 30 - SYMBOL) or (STATION_HOEHE / 2 + 30)
	local zeitY = oben and (symbolY - 26) or (symbolY + SYMBOL + 6)

	local bild = Instance.new("ImageLabel")
	bild.AnchorPoint = Vector2.new(0.5, 0)
	bild.Size = UDim2.new(0, SYMBOL, 0, SYMBOL)
	bild.Position = UDim2.new(0.5, 0, 0, symbolY)
	bild.BackgroundTransparency = 1
	bild.ScaleType = Enum.ScaleType.Fit
	bild.Visible = false
	bild.ZIndex = 5
	bild.Parent = knopf

	local zeichen = Instance.new("TextLabel")
	zeichen.AnchorPoint = Vector2.new(0.5, 0)
	zeichen.Size = UDim2.new(0, SYMBOL, 0, SYMBOL)
	zeichen.Position = UDim2.new(0.5, 0, 0, symbolY)
	zeichen.BackgroundTransparency = 1
	zeichen.TextScaled = true
	zeichen.Text = ""
	zeichen.ZIndex = 5
	zeichen.Parent = knopf
	zeigeSymbol(bild, zeichen, n)

	local zeitLabel = Instance.new("TextLabel")
	zeitLabel.AnchorPoint = Vector2.new(0.5, 0)
	zeitLabel.Size = UDim2.new(0, STATION_BREITE, 0, 20)
	zeitLabel.Position = UDim2.new(0.5, 0, 0, zeitY)
	zeitLabel.BackgroundTransparency = 1
	zeitLabel.Text = formatLang(unlockTime(n))
	zeitLabel.ZIndex = 5
	zeitLabel.Parent = knopf
	HudChrome.Number(zeitLabel, 16)
	zeitLabel.TextColor3 = HudChrome.Color.TextDim

	-- Der Strich zwischen Punkt und Symbol. Ohne ihn schweben die Symbole ueber und unter
	-- der Bahn, ohne dass zu sehen waere, zu welchem Punkt sie gehoeren -- bei
	-- abwechselnden Seiten ist das nicht mehr selbstverstaendlich.
	local stiel = Instance.new("Frame")
	stiel.Name = "Stem"
	stiel.AnchorPoint = Vector2.new(0.5, oben and 1 or 0)
	stiel.Size = UDim2.new(0, 1, 0, 30 - PUNKT / 2)
	stiel.Position = UDim2.new(0.5, 0, 0.5, oben and -PUNKT / 2 or PUNKT / 2)
	stiel.BackgroundColor3 = HudChrome.Color.BorderDim
	stiel.BorderSizePixel = 0
	stiel.ZIndex = 4
	stiel.Parent = knopf

	knopf.MouseButton1Click:Connect(function()
		holeAb(n)
	end)

	giftCells[n] = {
		knopf = knopf,
		punkt = punkt,
		ring = ring,
		bild = bild,
		zeichen = zeichen,
		zeitLabel = zeitLabel,
		stiel = stiel,
		oben = oben,
	}
end

-- Auch mit zwei Seiten kann es vorne noch eng werden: zwischen Geschenk 1 und 3 liegen auf
-- tausend Pixeln rund fuenfundachtzig. Das reicht fuer die Symbole, nicht immer fuer die
-- Zeitangaben darueber.
--
-- Statt die Stationen zu verschieben (das waere gelogen, der Abstand IST die Aussage),
-- werden ueberlappende BESCHRIFTUNGEN weggelassen -- getrennt je Seite, weil die beiden
-- Reihen sich nicht ins Gehege kommen. Gerechnet wird in Pixeln und deshalb neu, sobald
-- sich die Breite aendert: auf dem Telefon faellt mehr weg als am Rechner.
local function beschriftungenAusduennen()
	local breite = bahn.AbsoluteSize.X
	if breite <= 0 then
		return
	end
	local letzteRechts = { [true] = -math.huge, [false] = -math.huge }
	for n = 1, GIFT_COUNT do
		local eintrag = giftCells[n]
		local x = math.clamp(unlockTime(n) / GESAMTDAUER, 0, 1) * breite
		local seite = eintrag.oben
		-- Die letzte Station bekommt ihre Zeit immer: sie ist das Ziel der ganzen Strecke.
		if n == GIFT_COUNT or x - letzteRechts[seite] >= 76 then
			eintrag.zeitLabel.Visible = true
			letzteRechts[seite] = x
		else
			eintrag.zeitLabel.Visible = false
		end
	end
end

bahn:GetPropertyChangedSignal("AbsoluteSize"):Connect(beschriftungenAusduennen)
task.defer(beschriftungenAusduennen)

local wasReady = {} -- [n] = bool, fuer den Leucht-Puls beim Bereitwerden
local wasReadyInitialisiert = false

-- Kurzes Aufleuchten des Rings, wenn eine Station bereit wird.
local function playReadyGlow(eintrag)
	local ring = eintrag.ring
	if not ring then
		return
	end
	ring.Color = Color3.new(1, 1, 1)
	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Color = HudChrome.Color.Ready,
	}):Play()
end

RunService.Heartbeat:Connect(function()
	local sessionStart = player:GetAttribute("SessionStartTime")
	local claimedFolder = player:FindFirstChild("ClaimedGifts")
	if not sessionStart or not claimedFolder then
		return
	end

	local elapsed = Workspace:GetServerTimeNow() - sessionStart
	local anteilJetzt = math.clamp(elapsed / GESAMTDAUER, 0, 1)

	sessionLabel.Text = formatLang(elapsed)
	marke.Position = UDim2.new(anteilJetzt, 0, 0.5, 0)
	bahnGelaufen.Size = UDim2.new(anteilJetzt, 0, 1, 0)

	local anyClaimable = false
	local claimableCount = 0
	-- Das erste ABHOLBARE, sonst das erste noch kommende. Die Karte zeigt genau eines von
	-- beiden -- was bereitliegt, geht vor dem, was noch dauert.
	-- Das erste Geschenk, das noch NICHT bereit ist -- unabhaengig davon, ob nebenher schon
	-- welche bereitliegen. Das war der Fehler der einen Karte: solange irgendetwas abholbar
	-- war, verschwand die Vorschau auf das Naechste, obwohl beides gleichzeitig gilt.
	local naechstesN = nil

	for n = 1, GIFT_COUNT do
		local eintrag = giftCells[n]
		local marker = claimedFolder:FindFirstChild("Gift" .. n)
		if eintrag and marker then
			local claimed = marker.Value
			local ready = elapsed >= unlockTime(n)

			if claimed then
				-- Erledigt: die Station tritt zurueck. Sie bleibt sichtbar, damit die
				-- Strecke vollstaendig bleibt, verlangt aber keine Aufmerksamkeit mehr.
				eintrag.ring.Color = HudChrome.Color.Border
				eintrag.ring.Thickness = HudChrome.BorderThickness
				eintrag.punkt.BackgroundColor3 = HudChrome.Color.Border
				eintrag.punkt.Size = UDim2.new(0, PUNKT, 0, PUNKT)
				eintrag.stiel.BackgroundColor3 = HudChrome.Color.BorderDim
				eintrag.bild.ImageTransparency = 0.55
				eintrag.zeichen.TextTransparency = 0.55
				eintrag.zeitLabel.TextColor3 = HudChrome.Color.TextDim
			elseif ready then
				eintrag.ring.Color = HudChrome.Color.Ready
				eintrag.ring.Thickness = 3
				eintrag.punkt.BackgroundColor3 = HudChrome.Color.PanelRaised
				eintrag.punkt.Size = UDim2.new(0, PUNKT_BEREIT, 0, PUNKT_BEREIT)
				eintrag.stiel.BackgroundColor3 = HudChrome.Color.Ready
				eintrag.bild.ImageTransparency = 0
				eintrag.zeichen.TextTransparency = 0
				eintrag.zeitLabel.TextColor3 = HudChrome.Color.Ready
				anyClaimable = true
				claimableCount += 1
			else
				eintrag.ring.Color = HudChrome.Color.BorderDim
				eintrag.ring.Thickness = HudChrome.BorderThickness
				eintrag.punkt.BackgroundColor3 = HudChrome.Color.PanelSunken
				eintrag.punkt.Size = UDim2.new(0, PUNKT, 0, PUNKT)
				eintrag.stiel.BackgroundColor3 = HudChrome.Color.BorderDim
				eintrag.bild.ImageTransparency = 0.65
				eintrag.zeichen.TextTransparency = 0.65
				eintrag.zeitLabel.TextColor3 = HudChrome.Color.TextDim
				if not naechstesN then
					naechstesN = n
				end
			end

			-- Die Meldung kommt IM SPIEL, nicht nur hier.
			--
			-- Das war der groesste verschenkte Moment: das Geschenk wurde bereit, waehrend
			-- man draussen eine Stadt zertruemmert, und niemand sagte es. Wer das Menue nicht
			-- zufaellig offen hatte, erfuhr davon nur ueber ein kleines Laempchen.
			--
			-- Beim ERSTEN Durchlauf bewusst nicht: dort ist alles, was schon bereit ist, eine
			-- Neuigkeit, und man bekaeme beim Oeffnen des Spiels fuenf Meldungen auf einmal.
			if wasReadyInitialisiert and ready and not wasReady[n] and not claimed then
				playReadyGlow(eintrag)
				HudToast.Show({
					title = "Gift ready",
					detail = giftDescription(n),
					glyph = giftEmoji(n),
					image = giftBild(n),
					color = HudChrome.Color.Ready,
				})
			end
			wasReady[n] = ready
		end
	end

	wasReadyInitialisiert = true

	-- ===== Die Reihe fuellen =====
	--
	-- Sichtbar ist eine Abhol-Karte genau dann, wenn ihr Geschenk bereit UND nicht abgeholt
	-- ist. Die LayoutOrder ist die Geschenknummer -- damit steht die Reihe in derselben
	-- Ordnung wie die Bahn darunter, ohne dass hier sortiert werden muesste.
	for n = 1, GIFT_COUNT do
		local eintrag = claimKarten[n]
		local marker = claimedFolder:FindFirstChild("Gift" .. n)
		local sichtbar = marker and not marker.Value and elapsed >= unlockTime(n)
		eintrag.karte.Visible = sichtbar == true
		eintrag.karte.LayoutOrder = n
	end

	-- Die Karte fuer das Naechste steht ganz rechts -- was noch dauert, kommt nach dem, was
	-- schon da ist.
	naechsteKarte.karte.LayoutOrder = GIFT_COUNT + 1
	if naechstesN then
		naechsteKarte.karte.Visible = true
		naechsteKarte.kaption.Text = "NEXT"
		zeigeSymbol(naechsteKarte.bild, naechsteKarte.zeichen, naechstesN)
		naechsteKarte.titel.Text = giftDescription(naechstesN)
		naechsteKarte.zahl.Text = formatLang(unlockTime(naechstesN) - elapsed)
		naechsteKarte.zahl.TextColor3 = HudChrome.Color.TextPrimary
		naechsteKarte.rand.Color = HudChrome.Color.Border
		-- Von der VORIGEN Station aus, nicht von null: von null aus staende der Balken bei
		-- Geschenk elf fast am Ende und bewegte sich kaum. Er misst die aktuelle Strecke,
		-- nicht die ganze Sitzung.
		local von = naechstesN > 1 and unlockTime(naechstesN - 1) or 0
		local bis = unlockTime(naechstesN)
		local anteil = bis > von and math.clamp((elapsed - von) / (bis - von), 0, 1) or 0
		naechsteKarte.balken.Size = UDim2.new(anteil, 0, 1, 0)
	elseif claimableCount == 0 then
		-- Nichts offen und nichts mehr unterwegs: alles abgeholt. Das ist ein Zustand und
		-- kein Fehler -- er verdient einen Satz statt einer leeren Flaeche.
		naechsteKarte.karte.Visible = true
		naechsteKarte.kaption.Text = "COMPLETE"
		naechsteKarte.titel.Text = "All gifts collected"
		naechsteKarte.zahl.Text = formatLang(elapsed)
		naechsteKarte.zahl.TextColor3 = HudChrome.Color.TextPrimary
		naechsteKarte.rand.Color = HudChrome.Color.Border
		naechsteKarte.balken.Size = UDim2.new(1, 0, 1, 0)
		naechsteKarte.bild.Visible = false
		naechsteKarte.zeichen.Visible = false
	else
		-- Es liegt etwas bereit und es kommt nichts mehr: die Reihe besteht dann nur aus
		-- Abhol-Karten, und eine leere "NEXT"-Karte daneben waere eine Luege.
		naechsteKarte.karte.Visible = false
	end

	-- Das Geschenk-Laempchen geht NICHT beim Oeffnen aus, sondern erst beim Abholen --
	-- sonst oeffnet man, wird abgelenkt, und das Geschenk liegt weiter da. Deshalb wird es
	-- hier bei jedem Durchlauf neu gesetzt statt nur beim Uebergang.
	if _G.SetNavBadge then
		_G.SetNavBadge("Gifts", anyClaimable)
	end

	statusLabel.Text = claimableCount > 0
			and string.format("%d ready to claim", claimableCount)
		or "Nothing ready yet"
	statusLabel.TextColor3 = claimableCount > 0 and HudChrome.Color.Ready or HudChrome.Color.TextSecondary
end)
