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

-- ===== Die Karte fuer das Naechste =====
local KARTE_BREITE = 420
local KARTE_HOEHE = 176

-- Die Karte IST der Knopf.
--
-- Vorher stand auf ihr gross "CLAIM", anfassen musste man aber den kleinen runden Punkt
-- unten auf der Achse. Eine Aufschrift, die etwas verspricht, was an ihr nicht geht, ist
-- schlimmer als gar keine -- man sucht dann den Fehler bei sich.
--
-- Die Punkte auf der Bahn bleiben zusaetzlich anklickbar. Sie sind jetzt nicht mehr der
-- Weg, sondern eine Abkuerzung, wenn mehrere Geschenke gleichzeitig bereitliegen.
local naechsteKarte = Instance.new("TextButton")
naechsteKarte.Name = "NextGiftCard"
naechsteKarte.Size = UDim2.new(0, KARTE_BREITE, 0, KARTE_HOEHE)
naechsteKarte.Position = UDim2.new(0, 32, 0, 20)
naechsteKarte.AutoButtonColor = false
naechsteKarte.Text = ""
naechsteKarte.ZIndex = 4
naechsteKarte.Parent = schirm.content
local _, karteRand = HudChrome.Panel(naechsteKarte, {
	radius = HudChrome.Radius.Panel,
	fill = HudChrome.Color.PanelRaised,
	transparency = 0,
})

local karteKaption = Instance.new("TextLabel")
karteKaption.Size = UDim2.new(1, -32, 0, 18)
karteKaption.Position = UDim2.new(0, 20, 0, 14)
karteKaption.BackgroundTransparency = 1
karteKaption.TextXAlignment = Enum.TextXAlignment.Left
karteKaption.Text = "NEXT"
karteKaption.ZIndex = 5
karteKaption.Parent = naechsteKarte
HudChrome.MenuCaption(karteKaption, 14)

local karteBild = Instance.new("ImageLabel")
karteBild.Size = UDim2.new(0, 84, 0, 84)
karteBild.Position = UDim2.new(0, 20, 0, 42)
karteBild.BackgroundTransparency = 1
karteBild.ScaleType = Enum.ScaleType.Fit
karteBild.Visible = false
karteBild.ZIndex = 5
karteBild.Parent = naechsteKarte

local karteZeichen = Instance.new("TextLabel")
karteZeichen.Size = UDim2.new(0, 84, 0, 84)
karteZeichen.Position = UDim2.new(0, 20, 0, 42)
karteZeichen.BackgroundTransparency = 1
karteZeichen.TextScaled = true
karteZeichen.Text = ""
karteZeichen.ZIndex = 5
karteZeichen.Parent = naechsteKarte

local karteTitel = Instance.new("TextLabel")
karteTitel.Size = UDim2.new(1, -140, 0, 30)
karteTitel.Position = UDim2.new(0, 120, 0, 44)
karteTitel.BackgroundTransparency = 1
karteTitel.TextXAlignment = Enum.TextXAlignment.Left
karteTitel.Text = ""
karteTitel.ZIndex = 5
karteTitel.Parent = naechsteKarte
HudChrome.Label(karteTitel, HudChrome.MenuTextSize.Section)

local karteZahl = Instance.new("TextLabel")
karteZahl.Size = UDim2.new(1, -140, 0, 46)
karteZahl.Position = UDim2.new(0, 120, 0, 74)
karteZahl.BackgroundTransparency = 1
karteZahl.TextXAlignment = Enum.TextXAlignment.Left
karteZahl.Text = "--:--"
karteZahl.ZIndex = 5
karteZahl.Parent = naechsteKarte
HudChrome.NumberBold(karteZahl, 40)

-- Der Balken laeuft von der VORIGEN Station zur naechsten, nicht von null. Von null aus
-- staende er bei Geschenk elf fast am Ende und bewegte sich kaum -- er misst aber die
-- aktuelle Strecke, nicht die ganze Sitzung.
local karteBalkenSchacht = Instance.new("Frame")
karteBalkenSchacht.Size = UDim2.new(1, -40, 0, 6)
karteBalkenSchacht.Position = UDim2.new(0, 20, 1, -26)
karteBalkenSchacht.BackgroundColor3 = HudChrome.Color.PanelSunken
karteBalkenSchacht.BorderSizePixel = 0
karteBalkenSchacht.ZIndex = 5
karteBalkenSchacht.Parent = naechsteKarte

local karteBalken = Instance.new("Frame")
karteBalken.Size = UDim2.new(0, 0, 1, 0)
karteBalken.BackgroundColor3 = HudChrome.Color.Ready
karteBalken.BorderSizePixel = 0
karteBalken.ZIndex = 6
karteBalken.Parent = karteBalkenSchacht

-- ===== Der Belohnungston =====
--
-- Ein Geschenk abzuholen ist der einzige Augenblick in diesem Bildschirm, in dem etwas
-- PASSIERT -- alles andere ist Warten und Zusehen. Ohne Klang bleibt davon ein Rechteck,
-- das die Farbe wechselt.
--
-- Ein eigener Klang, nicht mehr der geliehene vom Stufenaufstieg. Das war die ganze
-- Ueberlegung hinter dem Wechsel: zwei verschiedene Ereignisse duerfen nicht gleich
-- klingen, sonst verlieren beide ihre Bedeutung.
local CLAIM_SOUND_ID = "rbxassetid://4612378364"

local claimSound = Instance.new("Sound")
claimSound.Name = "GiftClaimSound"
claimSound.SoundId = CLAIM_SOUND_ID
claimSound.Volume = 0.85
claimSound.Parent = SoundService

-- Was die Karte gerade zeigt. Der Klick-Handler braucht es, und er kann nicht in der
-- Heartbeat-Schleife stehen -- dort wuerde er je Bild neu verbunden.
local karteN = nil
local karteBereit = false

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

naechsteKarte.MouseButton1Click:Connect(function()
	if not karteBereit or not karteN then
		return
	end
	if not holeAb(karteN) then
		return
	end
	-- Kurzer Stoss am Rahmen. Bewusst KEIN Groessenpuls: die Karte steht neben der Bahn,
	-- und was waechst, schiebt hier nichts weg -- aber ein Rahmen, der aufblitzt, ist
	-- dieselbe Bewegungssprache wie bei den Alarmsternen und der Navigation.
	karteRand.Color = Color3.new(1, 1, 1)
	karteRand.Thickness = 3
	TweenService:Create(karteRand, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
		Color = HudChrome.Color.Border,
		Thickness = HudChrome.BorderThickness,
	}):Play()
end)

-- ===== Die Bahn =====
local BAHN_Y = 0.72 -- Anteil der Inhaltshoehe
local BAHN_RAND = 48
local PUNKT = 18
local PUNKT_NAECHST = 28

local bahn = Instance.new("Frame")
bahn.Name = "Track"
bahn.AnchorPoint = Vector2.new(0, 0.5)
bahn.Size = UDim2.new(1, -BAHN_RAND * 2, 0, 3)
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

-- Die Jetzt-Marke.
local marke = Instance.new("Frame")
marke.Name = "NowMarker"
marke.AnchorPoint = Vector2.new(0.5, 0.5)
marke.Size = UDim2.new(0, 2, 0, 54)
marke.Position = UDim2.new(0, 0, 0.5, 0)
marke.BackgroundColor3 = HudChrome.Color.BorderBright
marke.BorderSizePixel = 0
marke.ZIndex = 6
marke.Parent = bahn

local giftCells = {} -- [n] = { knopf=, ring=, bild=, zeichen=, zeitLabel= }

for n = 1, GIFT_COUNT do
	local anteil = math.clamp(unlockTime(n) / GESAMTDAUER, 0, 1)

	local knopf = Instance.new("TextButton")
	knopf.Name = "Gift" .. n
	knopf.AnchorPoint = Vector2.new(0.5, 0.5)
	knopf.Size = UDim2.new(0, PUNKT, 0, PUNKT)
	knopf.Position = UDim2.new(anteil, 0, 0.5, 0)
	knopf.AutoButtonColor = false
	knopf.Text = ""
	knopf.ZIndex = 5
	knopf.Parent = bahn
	-- Rund, nicht eckig: eine Station auf einer Strecke ist ein Punkt. HudChrome.Pill
	-- setzt dafuer einen echten Halbkreis-Radius -- Radius.Pill allein waere nur eine Zahl,
	-- die bei kleinen Kaestchen wieder auf die Kantenlaenge gedeckelt wird.
	local _, ring = HudChrome.Pill(knopf, { fill = HudChrome.Color.PanelSunken, transparency = 0 })

	-- Das Symbol steht UEBER der Station, die Zeit darunter. Beide gehoeren zur Station und
	-- haengen deshalb an ihr statt an der Bahn -- so verschiebt sich nichts gegeneinander,
	-- wenn die Bahn ihre Breite aendert.
	local bild = Instance.new("ImageLabel")
	bild.AnchorPoint = Vector2.new(0.5, 1)
	bild.Size = UDim2.new(0, 34, 0, 34)
	bild.Position = UDim2.new(0.5, 0, 0, -12)
	bild.BackgroundTransparency = 1
	bild.ScaleType = Enum.ScaleType.Fit
	bild.Visible = false
	bild.ZIndex = 5
	bild.Parent = knopf

	local zeichen = Instance.new("TextLabel")
	zeichen.AnchorPoint = Vector2.new(0.5, 1)
	zeichen.Size = UDim2.new(0, 34, 0, 34)
	zeichen.Position = UDim2.new(0.5, 0, 0, -12)
	zeichen.BackgroundTransparency = 1
	zeichen.TextScaled = true
	zeichen.Text = ""
	zeichen.ZIndex = 5
	zeichen.Parent = knopf
	zeigeSymbol(bild, zeichen, n)

	local zeitLabel = Instance.new("TextLabel")
	zeitLabel.AnchorPoint = Vector2.new(0.5, 0)
	zeitLabel.Size = UDim2.new(0, 70, 0, 18)
	zeitLabel.Position = UDim2.new(0.5, 0, 1, 10)
	zeitLabel.BackgroundTransparency = 1
	zeitLabel.Text = formatLang(unlockTime(n))
	zeitLabel.ZIndex = 5
	zeitLabel.Parent = knopf
	HudChrome.Number(zeitLabel, 13)
	zeitLabel.TextColor3 = HudChrome.Color.TextDim

	knopf.MouseButton1Click:Connect(function()
		holeAb(n)
	end)

	giftCells[n] = { knopf = knopf, ring = ring, bild = bild, zeichen = zeichen, zeitLabel = zeitLabel }
end

-- Die fruehen Stationen liegen dicht beieinander -- bei zwei Stunden Gesamtdauer sitzt das
-- erste Geschenk auf einem Prozent der Bahn. Ihre Zeitangaben wuerden sich ueberlappen.
--
-- Statt die Stationen zu verschieben (das waere gelogen, der Abstand IST die Aussage),
-- werden ueberlappende BESCHRIFTUNGEN weggelassen. Gerechnet wird in Pixeln und deshalb
-- neu, sobald sich die Breite aendert -- auf dem Telefon faellt mehr weg als am Rechner.
local function beschriftungenAusduennen()
	local breite = bahn.AbsoluteSize.X
	if breite <= 0 then
		return
	end
	local letzteRechts = -math.huge
	for n = 1, GIFT_COUNT do
		local eintrag = giftCells[n]
		local x = math.clamp(unlockTime(n) / GESAMTDAUER, 0, 1) * breite
		-- Die letzte Station bekommt ihre Zeit immer: sie ist das Ziel der ganzen Strecke.
		local mussStehen = (n == GIFT_COUNT)
		if mussStehen or x - letzteRechts >= 62 then
			eintrag.zeitLabel.Visible = true
			letzteRechts = x
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
	local zeigeN, zeigeBereit = nil, false

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
				eintrag.knopf.BackgroundColor3 = HudChrome.Color.Border
				eintrag.knopf.Size = UDim2.new(0, PUNKT, 0, PUNKT)
				eintrag.bild.ImageTransparency = 0.55
				eintrag.zeichen.TextTransparency = 0.55
				eintrag.zeitLabel.TextColor3 = HudChrome.Color.TextDim
			elseif ready then
				eintrag.ring.Color = HudChrome.Color.Ready
				eintrag.ring.Thickness = 2
				eintrag.knopf.BackgroundColor3 = HudChrome.Color.PanelRaised
				eintrag.knopf.Size = UDim2.new(0, PUNKT_NAECHST, 0, PUNKT_NAECHST)
				eintrag.bild.ImageTransparency = 0
				eintrag.zeichen.TextTransparency = 0
				eintrag.zeitLabel.TextColor3 = HudChrome.Color.Ready
				anyClaimable = true
				claimableCount += 1
				if not zeigeBereit then
					zeigeN, zeigeBereit = n, true
				end
			else
				eintrag.ring.Color = HudChrome.Color.BorderDim
				eintrag.ring.Thickness = HudChrome.BorderThickness
				eintrag.knopf.BackgroundColor3 = HudChrome.Color.PanelSunken
				eintrag.knopf.Size = UDim2.new(0, PUNKT, 0, PUNKT)
				eintrag.bild.ImageTransparency = 0.6
				eintrag.zeichen.TextTransparency = 0.6
				eintrag.zeitLabel.TextColor3 = HudChrome.Color.TextDim
				if not zeigeN then
					zeigeN = n
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

	-- ===== Die Karte fuer das Naechste =====
	karteN, karteBereit = zeigeN, zeigeBereit

	if zeigeN then
		zeigeSymbol(karteBild, karteZeichen, zeigeN)
		karteTitel.Text = giftDescription(zeigeN)
		karteZahl.TextColor3 = zeigeBereit and HudChrome.Color.Ready or HudChrome.Color.TextPrimary
		karteKaption.Text = zeigeBereit and "READY TO CLAIM" or "NEXT"
		karteRand.Color = zeigeBereit and HudChrome.Color.Ready or HudChrome.Color.Border

		if zeigeBereit then
			karteZahl.Text = "CLAIM"
			karteBalken.Size = UDim2.new(1, 0, 1, 0)
		else
			karteZahl.Text = formatLang(unlockTime(zeigeN) - elapsed)
			-- Von der VORIGEN Station aus, nicht von null: von null aus staende der Balken
			-- bei Geschenk elf fast am Ende und bewegte sich kaum. Er misst die aktuelle
			-- Strecke, nicht die ganze Sitzung.
			local von = zeigeN > 1 and unlockTime(zeigeN - 1) or 0
			local bis = unlockTime(zeigeN)
			local anteil = bis > von and math.clamp((elapsed - von) / (bis - von), 0, 1) or 0
			karteBalken.Size = UDim2.new(anteil, 0, 1, 0)
		end
	else
		-- Alles abgeholt. Das ist ein Zustand und kein Fehler -- er verdient einen Satz.
		karteKaption.Text = "COMPLETE"
		karteTitel.Text = "All gifts collected"
		karteZahl.Text = formatLang(elapsed)
		karteZahl.TextColor3 = HudChrome.Color.TextPrimary
		karteBalken.Size = UDim2.new(1, 0, 1, 0)
		karteRand.Color = HudChrome.Color.Border
		karteBild.Visible = false
		karteZeichen.Visible = false
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
