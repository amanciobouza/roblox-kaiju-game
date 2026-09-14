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
-- ===== Warum die Bahn NICHT auf einem Anteil der Hoehe sitzt =====
--
-- Sie sass auf 0,66 der Inhaltshoehe. Am Rechner ging das auf; auf dem Telefon nicht,
-- und zwar nicht knapp: dort bleiben vom Bildschirm nach Kopfzeile und
-- Systemleisten-Polster noch rund 377 Pixel Inhalt. Kartenreihe und Achse brauchen
-- zusammen 442. Ein Anteil verteilt einen Platz, den es nicht gibt -- und die Stationen
-- lagen dann in den Karten.
--
-- Ein Anteil war ohnehin die falsche Groesse. Die Bahn gehoert UNTER die Kartenreihe, und
-- das ist eine Beziehung zwischen zwei Dingen, kein Prozentwert vom Ganzen. Sie sitzt
-- deshalb auf einem gerechneten Versatz -- und wenn der Platz nicht reicht, schrumpft die
-- Achse mit, statt sich zu ueberlagern.
local BAHN_RAND = 56
local PUNKT = 26
local PUNKT_BEREIT = 40
local STATION_BREITE = 92

-- Die Wunschmasse. Sie gelten, solange der Platz reicht.
local STATION_HOEHE_VOLL = 300 -- Symbol, Zeit UND Beschreibung auf beiden Seiten der Bahn
local SYMBOL_VOLL = 68
local STATION_HOEHE_MIN = 150 -- darunter ist das Symbol kein Symbol mehr, sondern ein Fleck

-- Was am Ende gilt. Wird unten aus der gemessenen Inhaltshoehe bestimmt und bei jeder
-- Aenderung nachgezogen -- Drehen des Telefons aendert beides.
local STATION_HOEHE = STATION_HOEHE_VOLL
local SYMBOL = SYMBOL_VOLL

local bahn = Instance.new("Frame")
bahn.Name = "Track"
bahn.AnchorPoint = Vector2.new(0, 0.5)
bahn.Size = UDim2.new(1, -BAHN_RAND * 2, 0, 5)
bahn.Position = UDim2.new(0, BAHN_RAND, 0, 0) -- die Hoehe setzt layoutAnwenden unten
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
	--   oben:   Text 4..24, Zeit 26..46, Symbol 52..120, Stiel, Punkt um 150
	--   unten:  Punkt um 150, Stiel, Symbol 180..248, Zeit 254..274, Text 276..296
	local symbolY = oben and (STATION_HOEHE / 2 - 30 - SYMBOL) or (STATION_HOEHE / 2 + 30)
	local zeitY = oben and (symbolY - 26) or (symbolY + SYMBOL + 6)
	local detailY = oben and (zeitY - 22) or (zeitY + 22)

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

	-- Was das Geschenk IST, im Klartext. Steht nur an den zwei Stationen, die gerade etwas
	-- von einem wollen: der abholbaren und der naechsten. An allen zwoelf gleichzeitig waere
	-- es eine Textwand, und an keiner waere das Symbol allein genau genug -- eine Muenze
	-- sagt nicht, ob es fuenfzig oder achthundert sind.
	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.AnchorPoint = Vector2.new(0.5, 0)
	detailLabel.Size = UDim2.new(0, STATION_BREITE + 60, 0, 20)
	detailLabel.Position = UDim2.new(0.5, 0, 0, detailY)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Text = giftDescription(n)
	detailLabel.Visible = false
	detailLabel.ZIndex = 6
	detailLabel.Parent = knopf
	HudChrome.MenuCaption(detailLabel, 14)

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
		punktGroesse = PUNKT,
		punktGroesseBereit = PUNKT_BEREIT,
		ring = ring,
		bild = bild,
		zeichen = zeichen,
		zeitLabel = zeitLabel,
		detailLabel = detailLabel,
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
		-- Zwei Zeilen sind unantastbar: CLAIM an einer bereiten Station und der laufende
		-- Countdown an der naechsten. Sie sind der Grund, warum man ueberhaupt hinsieht --
		-- sie dem Platz zu opfern hiesse, die Anzeige gegen das Layout zu tauschen.
		-- Die letzte Station bekommt ihre Zeit ebenfalls immer: sie ist das Ziel der Strecke.
		if eintrag.wichtig or n == GIFT_COUNT or x - letzteRechts[seite] >= 76 then
			eintrag.zeitLabel.Visible = true
			letzteRechts[seite] = x
		else
			eintrag.zeitLabel.Visible = false
		end
	end
end

bahn:GetPropertyChangedSignal("AbsoluteSize"):Connect(beschriftungenAusduennen)

-- ===== Hoehe aufteilen, statt sie zu verteilen =====
--
-- Gemessen statt gerechnet: die Inhaltshoehe haengt an der Bildhoehe, an der Kopfzeile und
-- am Polster fuer Robloxs Systemleiste -- und dieses Polster wird selbst erst nachgezogen,
-- wenn die Kern-Oberflaeche steht. Sie vorherzusagen hiesse, drei Dinge nachzurechnen, von
-- denen sich zwei spaeter noch aendern.
--
-- Die Aufteilung: die Kartenreihe bekommt oben, was sie braucht, die Achse den Rest. Bleibt
-- fuer die Achse zu wenig, schrumpft sie -- Symbol, Abstaende und Schrift gemeinsam, damit
-- sie ihr Verhaeltnis behaelt. Unter STATION_HOEHE_MIN hoert das auf: dann ist das Symbol
-- kein Symbol mehr, und lieber steht die Achse etwas zu tief, als dass man nichts erkennt.
local function layoutAnwenden()
	local hoehe = schirm.content.AbsoluteSize.Y
	if hoehe <= 0 then
		return
	end

	-- Die Achse bekommt die ganze Hoehe. Sie teilt sie mit nichts mehr -- das war die
	-- Entscheidung hinter diesem Umbau, und sie loest die Enge auf dem Telefon an der
	-- Wurzel statt sie zu verteilen.
	STATION_HOEHE = math.clamp(hoehe - 16, 1, STATION_HOEHE_VOLL)

	-- Alles andere folgt dem Verhaeltnis. Ein einzeln gesetzter Wert waere die naechste
	-- Stelle, die beim naechsten Umbau nicht mitkommt.
	local q = STATION_HOEHE / STATION_HOEHE_VOLL
	SYMBOL = math.floor(SYMBOL_VOLL * q)
	local abstand = math.floor(30 * q)
	local punkt = math.max(math.floor(PUNKT * q), 12)
	local zeitGroesse = math.max(math.floor(16 * q), 11)

	-- Mittig in der Inhaltsflaeche.
	bahn.Position = UDim2.new(0, BAHN_RAND, 0, math.floor(hoehe / 2))
	marke.Size = UDim2.new(0, 2, 0, STATION_HOEHE - 40)

	for n = 1, GIFT_COUNT do
		local eintrag = giftCells[n]
		local oben = eintrag.oben
		local symbolY = oben and (STATION_HOEHE / 2 - abstand - SYMBOL) or (STATION_HOEHE / 2 + abstand)
		local zeitY = oben and (symbolY - 26 * q) or (symbolY + SYMBOL + 6)
		local detailY = oben and (zeitY - 22 * q) or (zeitY + 22 * q)

		eintrag.knopf.Size = UDim2.new(0, STATION_BREITE, 0, STATION_HOEHE)
		eintrag.bild.Size = UDim2.new(0, SYMBOL, 0, SYMBOL)
		eintrag.bild.Position = UDim2.new(0.5, 0, 0, symbolY)
		eintrag.zeichen.Size = UDim2.new(0, SYMBOL, 0, SYMBOL)
		eintrag.zeichen.Position = UDim2.new(0.5, 0, 0, symbolY)
		eintrag.zeitLabel.Position = UDim2.new(0.5, 0, 0, zeitY)
		eintrag.zeitLabel.TextSize = zeitGroesse
		eintrag.detailLabel.Position = UDim2.new(0.5, 0, 0, detailY)
		eintrag.detailLabel.TextSize = math.max(math.floor(14 * q), 10)
		eintrag.stiel.Size = UDim2.new(0, 1, 0, math.max(abstand - punkt / 2, 4))
		eintrag.stiel.Position = UDim2.new(0.5, 0, 0.5, oben and -punkt / 2 or punkt / 2)
		-- Die RUHENDE Groesse des Punktes. Die Schleife unten setzt sie je Zustand neu und
		-- muss denselben Wert kennen -- deshalb liegt er im Eintrag und nicht als Konstante.
		eintrag.punktGroesse = punkt
		eintrag.punktGroesseBereit = math.max(math.floor(PUNKT_BEREIT * q), 18)
	end

	beschriftungenAusduennen()
end

schirm.content:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutAnwenden)
-- Das Polster fuer die Systemleiste wird erst spaeter nachgezogen (TopInsetUtils), und mit
-- ihm aendert sich die Inhaltshoehe. Ohne diesen Nachschlag bliebe das Layout auf dem
-- Stand von vor dem Aufbau der Kern-Oberflaeche stehen.
task.defer(layoutAnwenden)
task.delay(2.5, layoutAnwenden)

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

-- ===== Zustand je Geschenk, einmal je Bild =====
--
-- In zwei Durchgaengen, und das hat einen Grund: welche Station die NAECHSTE ist, weiss man
-- erst, wenn alle durchgesehen sind. Frueher stand die Vorschau in einer eigenen Karte und
-- konnte hinterher gesetzt werden; jetzt gehoert sie einer Station, und die muss sich beim
-- Zeichnen schon anders verhalten als ihre Nachbarn.
local zustand = {} -- [n] = "claimed" | "ready" | "next" | "later"; einmal angelegt, nicht je Bild

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

	-- ===== Erster Durchgang: einsortieren =====
	local claimableCount = 0
	local naechstesGefunden = false

	for n = 1, GIFT_COUNT do
		local marker = claimedFolder:FindFirstChild("Gift" .. n)
		if not marker then
			zustand[n] = "later"
		elseif marker.Value then
			zustand[n] = "claimed"
		elseif elapsed >= unlockTime(n) then
			zustand[n] = "ready"
			claimableCount += 1
		elseif not naechstesGefunden then
			zustand[n] = "next"
			naechstesGefunden = true
		else
			zustand[n] = "later"
		end
	end

	-- ===== Zweiter Durchgang: zeichnen =====
	--
	-- Die eine Zeile unter dem Symbol traegt drei Bedeutungen, je nach Zustand: die
	-- Uhrzeit, zu der das Geschenk faellig ist -- oder CLAIM, wenn es bereitliegt -- oder
	-- den laufenden Countdown, wenn es das naechste ist. Ein zweites Feld dafuer haette
	-- immer zwei Drittel leer dagestanden.
	for n = 1, GIFT_COUNT do
		local eintrag = giftCells[n]
		local art = zustand[n]
		eintrag.wichtig = (art == "ready" or art == "next")

		if art == "claimed" then
			-- Erledigt: die Station tritt zurueck. Sie bleibt sichtbar, damit die Strecke
			-- vollstaendig bleibt, verlangt aber keine Aufmerksamkeit mehr.
			eintrag.ring.Color = HudChrome.Color.Border
			eintrag.ring.Thickness = HudChrome.BorderThickness
			eintrag.punkt.BackgroundColor3 = HudChrome.Color.Border
			eintrag.punkt.Size = UDim2.new(0, eintrag.punktGroesse, 0, eintrag.punktGroesse)
			eintrag.stiel.BackgroundColor3 = HudChrome.Color.BorderDim
			eintrag.bild.ImageTransparency = 0.55
			eintrag.zeichen.TextTransparency = 0.55
			eintrag.zeitLabel.Text = formatLang(unlockTime(n))
			eintrag.zeitLabel.TextColor3 = HudChrome.Color.TextDim
		elseif art == "ready" then
			eintrag.ring.Color = HudChrome.Color.Ready
			eintrag.ring.Thickness = 3
			eintrag.punkt.BackgroundColor3 = HudChrome.Color.PanelRaised
			eintrag.punkt.Size = UDim2.new(0, eintrag.punktGroesseBereit, 0, eintrag.punktGroesseBereit)
			eintrag.stiel.BackgroundColor3 = HudChrome.Color.Ready
			eintrag.bild.ImageTransparency = 0
			eintrag.zeichen.TextTransparency = 0
			eintrag.zeitLabel.Text = "CLAIM"
			eintrag.zeitLabel.TextColor3 = HudChrome.Color.Ready
		elseif art == "next" then
			eintrag.ring.Color = HudChrome.Color.BorderBright
			eintrag.ring.Thickness = 2
			eintrag.punkt.BackgroundColor3 = HudChrome.Color.PanelRaised
			eintrag.punkt.Size = UDim2.new(0, eintrag.punktGroesse, 0, eintrag.punktGroesse)
			eintrag.stiel.BackgroundColor3 = HudChrome.Color.Border
			eintrag.bild.ImageTransparency = 0.2
			eintrag.zeichen.TextTransparency = 0.2
			eintrag.zeitLabel.Text = formatLang(unlockTime(n) - elapsed)
			eintrag.zeitLabel.TextColor3 = HudChrome.Color.TextPrimary
		else
			eintrag.ring.Color = HudChrome.Color.BorderDim
			eintrag.ring.Thickness = HudChrome.BorderThickness
			eintrag.punkt.BackgroundColor3 = HudChrome.Color.PanelSunken
			eintrag.punkt.Size = UDim2.new(0, eintrag.punktGroesse, 0, eintrag.punktGroesse)
			eintrag.stiel.BackgroundColor3 = HudChrome.Color.BorderDim
			eintrag.bild.ImageTransparency = 0.65
			eintrag.zeichen.TextTransparency = 0.65
			eintrag.zeitLabel.Text = formatLang(unlockTime(n))
			eintrag.zeitLabel.TextColor3 = HudChrome.Color.TextDim
		end

		-- Der Klartext steht nur, wo er gebraucht wird. An allen zwoelf gleichzeitig waere
		-- er eine Textwand.
		eintrag.detailLabel.Visible = eintrag.wichtig
		eintrag.detailLabel.TextColor3 = (art == "ready") and HudChrome.Color.Ready
			or HudChrome.Color.TextSecondary

		-- Die Meldung kommt IM SPIEL, nicht nur hier.
		--
		-- Das war der groesste verschenkte Moment: das Geschenk wurde bereit, waehrend man
		-- draussen eine Stadt zertruemmert, und niemand sagte es. Wer das Menue nicht
		-- zufaellig offen hatte, erfuhr davon nur ueber ein kleines Laempchen.
		--
		-- Beim ERSTEN Durchlauf bewusst nicht: dort ist alles, was schon bereit ist, eine
		-- Neuigkeit, und man bekaeme beim Oeffnen des Spiels fuenf Meldungen auf einmal.
		local istBereit = (art == "ready")
		if wasReadyInitialisiert and istBereit and not wasReady[n] then
			playReadyGlow(eintrag)
			HudToast.Show({
				title = "Gift ready",
				detail = giftDescription(n),
				glyph = giftEmoji(n),
				image = giftBild(n),
				color = HudChrome.Color.Ready,
			})
		end
		wasReady[n] = istBereit
	end

	wasReadyInitialisiert = true
	beschriftungenAusduennen()

	-- Das Geschenk-Laempchen geht NICHT beim Oeffnen aus, sondern erst beim Abholen --
	-- sonst oeffnet man, wird abgelenkt, und das Geschenk liegt weiter da. Deshalb wird es
	-- hier bei jedem Durchlauf neu gesetzt statt nur beim Uebergang.
	if _G.SetNavBadge then
		_G.SetNavBadge("Gifts", claimableCount > 0)
	end

	if claimableCount > 0 then
		statusLabel.Text = string.format("%d ready to claim", claimableCount)
		statusLabel.TextColor3 = HudChrome.Color.Ready
	elseif naechstesGefunden then
		statusLabel.Text = "Nothing ready yet"
		statusLabel.TextColor3 = HudChrome.Color.TextSecondary
	else
		statusLabel.Text = "All gifts collected"
		statusLabel.TextColor3 = HudChrome.Color.TextSecondary
	end
end)
