-- VERSION: 2026-09-15 #1
-- LocalScript: LoadingScreen
-- Ort in Studio: ReplicatedFirst (NICHT StarterPlayerScripts!)
--
-- Der Ladebildschirm ist eine Uhr, und sie geht richtig: sie zeigt die aktuelle Zeit in
-- Geroldswil. Das ist keine Dekoration -- die Uhrzeit ist das Koordinatensystem dieser Welt.
-- Jede Stadt sitzt auf einer Stunde (Dawnhollow 02:00 bis Aeon Prime 10:00, siehe
-- CityIdentity), und dieselben Indizes sind die Portalbuchten im Sanctuary. Die Stadt, auf
-- deren Stunde der Zeiger gerade steht, leuchtet auf: es ist jetzt ihre Stunde.
--
-- Der LADEFORTSCHRITT gehört deshalb nicht in den Zeiger -- eine Uhr, die schneller läuft,
-- weil ein Bild fertig wurde, wäre keine Uhr mehr. Er steht als Zahl in der Mitte und als
-- schmaler Balken unter dem Blatt.
--
-- ===== Was der Balken misst =====
-- Vorher waren es sechs Schritte, die auf GUI-Objekte warteten, und der Balken sprang in
-- Sechsteln. Er zeigte damit die Schrittzahl, nicht den Fortschritt.
--
-- Jetzt zählt er BILDER. Die Symbole des HUD werden hier über ContentProvider geladen, Datei
-- für Datei, und jede fertige rückt den Zeiger. Das behebt zugleich einen alten Fehler: die
-- Symbole wurden bisher erst im Spiel nachgeladen, und auf dem Telefon fehlten dadurch vier
-- von fünf. Der Ladebildschirm verschwindet jetzt erst, wenn sie da sind -- dafür ist er da.
--
-- ===== Warum hier trotzdem nichts blockiert =====
-- Dieses Skript liegt in ReplicatedFirst und läuft, bevor irgendetwas anderes existiert.
-- Es darf auf nichts unbegrenzt warten, sonst käme der Ladebildschirm zu spät oder nie.
-- Deshalb: der Bildschirm steht SOFORT, in eigenen Farben. HudChrome und CityIdentity
-- werden mit Zeitgrenze nachgeholt und nur DANN angewandt -- fehlen sie, sieht es schlichter
-- aus, aber es läuft.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer

-- ===== Rückfall-Farben =====
-- Nur für die Sekundenbruchteile, bis HudChrome da ist -- und für den Fall, dass es gar
-- nicht kommt. Bewusst dieselben Werte wie dort; sie stehen hier nicht, um eine zweite
-- Palette zu sein, sondern weil dieses Skript vor der ersten Replikation zeichnen muss.
local Farbe = {
	Grund = Color3.fromRGB(13, 15, 19),
	Vertieft = Color3.fromRGB(8, 9, 12),
	Rand = Color3.fromRGB(70, 80, 94),
	RandHell = Color3.fromRGB(132, 148, 168),
	RandMatt = Color3.fromRGB(40, 46, 55),
	Text = Color3.fromRGB(232, 238, 245),
	TextZweit = Color3.fromRGB(172, 184, 200),
	TextMatt = Color3.fromRGB(86, 96, 110),
	Akzent = Color3.fromRGB(70, 210, 255),
	-- Goldgelb: Zeiger und Stundenmarken. Es ist dieselbe Farbe, die das HUD fuer "bereit"
	-- benutzt (HudChrome.Color.Ready) -- Messing und Uhrwerk, und der Gegenpol zum cyanen
	-- Energie-Akzent, der hier nur noch am Ladebalken haengt.
	Gold = Color3.fromRGB(255, 176, 32),
}
local Schrift = { Titel = Enum.Font.GothamBold, Zahl = Enum.Font.Code }

-- Mit Zeitgrenze nachholen. Kommt es nicht, bleibt es beim Rückfall.
local function holeModul(name, sekunden)
	local modul = ReplicatedStorage:WaitForChild(name, sekunden)
	if not modul then
		return nil
	end
	local ok, geladen = pcall(require, modul)
	return ok and geladen or nil
end

local HudChrome = holeModul("HudChrome", 8)
if HudChrome then
	Farbe.Grund = HudChrome.Color.Panel
	Farbe.Vertieft = HudChrome.Color.PanelSunken
	Farbe.Rand = HudChrome.Color.Border
	Farbe.RandHell = HudChrome.Color.BorderBright
	Farbe.RandMatt = HudChrome.Color.BorderDim
	Farbe.Text = HudChrome.Color.TextPrimary
	Farbe.TextZweit = HudChrome.Color.TextSecondary
	Farbe.TextMatt = HudChrome.Color.TextDim
	Farbe.Akzent = HudChrome.Color.Accent
	Farbe.Gold = HudChrome.Color.Ready
	Schrift.Titel = HudChrome.Font.Label
	Schrift.Zahl = HudChrome.Font.Number
end

-- Der matte Goldton wird gerechnet statt gesetzt: so bleibt er an den Goldton gebunden,
-- auch wenn der sich einmal aendert. Zwei Zahlen, die zusammengehoeren, sollen nicht an
-- zwei Orten stehen.
Farbe.GoldMatt = Farbe.Gold:Lerp(Farbe.Vertieft, 0.62)

-- ===== Die Stationen auf dem Zifferblatt =====
-- Aus CityIdentity, damit Name und Stunde an EINER Stelle stehen. Fehlt das Modul, bleibt
-- das Zifferblatt leer beschriftet -- der Zeiger dreht trotzdem.
local stationen = {}
do
	local CityIdentity = holeModul("CityIdentity", 5)
	if CityIdentity and CityIdentity.Cities then
		for _, stadt in pairs(CityIdentity.Cities) do
			local stunde = tonumber(string.match(tostring(stadt.hour or ""), "^(%d+):"))
			if stunde and stadt.display then
				table.insert(stationen, { stunde = stunde, name = string.upper(stadt.display) })
			end
		end
		table.sort(stationen, function(a, b)
			return a.stunde < b.stunde
		end)
	end
end

-- ===== Die Zeit in Geroldswil =====
-- Nicht die Uhr des Spielers: wer aus einem anderen Land zusieht, soll dieselbe Zeit sehen
-- wie die Welt, in die er gleich einsteigt. Gerechnet wird deshalb aus UTC.
--
-- Die Schweiz folgt der EU-Regel: Sommerzeit vom letzten Sonntag im Maerz, 01:00 UTC, bis
-- zum letzten Sonntag im Oktober, 01:00 UTC. Beide Wechsel werden ausgerechnet statt
-- geschaetzt -- eine Uhr, die zweimal im Jahr fuer ein paar Stunden falsch geht, faellt
-- genau dann auf, wenn jemand hinsieht.
local function tageSeitEpoche(jahr, monat, tag)
	jahr = (monat <= 2) and (jahr - 1) or jahr
	local aera = math.floor(jahr / 400)
	local jahrInAera = jahr - aera * 400
	local tagImJahr = math.floor((153 * (monat + ((monat > 2) and -3 or 9)) + 2) / 5) + tag - 1
	local tagInAera = jahrInAera * 365 + math.floor(jahrInAera / 4)
		- math.floor(jahrInAera / 100) + tagImJahr
	return aera * 146097 + tagInAera - 719468
end

-- 1970-01-01 war ein Donnerstag, deshalb die vier. 0 ist Sonntag.
local function wochentag(epochenTag)
	return (epochenTag + 4) % 7
end

-- Der Umstellungszeitpunkt in Sekunden seit der Epoche: letzter Sonntag des Monats, 01:00 UTC.
local function letzterSonntag(jahr, monat, tageImMonat)
	local letzter = tageSeitEpoche(jahr, monat, tageImMonat)
	return (letzter - wochentag(letzter)) * 86400 + 3600
end

local function geroldswilZeit()
	local jetzt = os.time()
	local jahr = os.date("!*t", jetzt).year
	local sommerBeginn = letzterSonntag(jahr, 3, 31)
	local sommerEnde = letzterSonntag(jahr, 10, 31)
	local versatz = (jetzt >= sommerBeginn and jetzt < sommerEnde) and 7200 or 3600
	return os.date("!*t", jetzt + versatz)
end

-- ===== Der Bildschirm =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreenGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
-- Bis an die physische Kante: sonst blitzt auf dem Telefon am Rand die Szene durch.
pcall(function()
	screenGui.ScreenInsets = Enum.ScreenInsets.None
end)
screenGui.DisplayOrder = 1000
screenGui.Parent = player:WaitForChild("PlayerGui")

local grund = Instance.new("Frame")
grund.Name = "Background"
grund.Size = UDim2.new(1, 0, 1, 0)
grund.BackgroundColor3 = Farbe.Grund
grund.BorderSizePixel = 0
grund.Parent = screenGui

local titel = Instance.new("TextLabel")
titel.Name = "Title"
titel.AnchorPoint = Vector2.new(0.5, 0)
titel.Position = UDim2.new(0.5, 0, 0.08, 0)
titel.Size = UDim2.new(0.9, 0, 0, 38)
titel.BackgroundTransparency = 1
titel.Font = Schrift.Titel
titel.TextScaled = true
titel.TextColor3 = Farbe.Text
titel.Text = "WE ARE TRENCHBORN"
titel.Parent = grund

local untertitel = Instance.new("TextLabel")
untertitel.Name = "Subtitle"
untertitel.AnchorPoint = Vector2.new(0.5, 0)
untertitel.Position = UDim2.new(0.5, 0, 0.08, 42)
untertitel.Size = UDim2.new(0.9, 0, 0, 18)
untertitel.BackgroundTransparency = 1
untertitel.Font = Schrift.Zahl
untertitel.TextScaled = true
untertitel.TextColor3 = Farbe.TextMatt
untertitel.Text = "THE HOURS ARE TURNING"
untertitel.Parent = grund

-- ===== Das Zifferblatt =====
local blatt = Instance.new("Frame")
blatt.Name = "Dial"
blatt.AnchorPoint = Vector2.new(0.5, 0.5)
blatt.Position = UDim2.new(0.5, 0, 0.5, 0)
blatt.BackgroundColor3 = Farbe.Vertieft
blatt.BorderSizePixel = 0
blatt.Parent = grund

local blattEcke = Instance.new("UICorner")
blattEcke.CornerRadius = UDim.new(0.5, 0)
blattEcke.Parent = blatt

local blattRand = Instance.new("UIStroke")
blattRand.Thickness = 2
blattRand.Color = Farbe.RandMatt
blattRand.Parent = blatt

-- Zwölf Striche, die fünf Stadt-Stunden kräftiger. Die Lage wird gerechnet, nicht gesetzt:
-- das Blatt wächst mit dem Bildschirm, feste Pixel liefen auf dem Telefon aus dem Rund.
local striche, marken = {}, {}
for stunde = 1, 12 do
	local istStation = false
	for _, station in ipairs(stationen) do
		if station.stunde == stunde then
			istStation = true
		end
	end

	local strich = Instance.new("Frame")
	strich.Name = "Tick_" .. stunde
	strich.AnchorPoint = Vector2.new(0.5, 0.5)
	strich.BackgroundColor3 = istStation and Farbe.Gold or Farbe.GoldMatt
	strich.BorderSizePixel = 0
	strich.Rotation = stunde * 30
	strich.Parent = blatt
	striche[stunde] = { rahmen = strich, station = istStation }
end

for _, station in ipairs(stationen) do
	local marke = Instance.new("TextLabel")
	marke.Name = "City_" .. station.stunde
	marke.AnchorPoint = Vector2.new(0.5, 0.5)
	marke.Size = UDim2.new(0, 120, 0, 16)
	marke.BackgroundTransparency = 1
	marke.Font = Schrift.Zahl
	marke.TextScaled = true
	marke.TextColor3 = Farbe.TextMatt
	marke.Text = station.name
	marke.Parent = blatt
	marken[station.stunde] = marke
end

-- ===== Die Zeiger =====
-- Jeder Zeiger sitzt in einem eigenen Traeger, der das GANZE Blatt ausfuellt und um dessen
-- Mitte gedreht wird. Der Zeiger selbst haengt darin nach oben.
--
-- Warum der Umweg: gedreht wird ein Traeger, dessen Mittelpunkt garantiert der
-- Blattmittelpunkt ist. Beim ersten Versuch drehte der Zeiger um seinen eigenen Ankerpunkt
-- -- das haengt davon ab, wie Roblox Ankerpunkt und Rotation verrechnet, und das Ergebnis
-- sass sichtbar neben der Mitte. Ein Traeger nimmt diese Frage ganz aus dem Spiel.
local function baueZeiger(name, laengeAnteil, dickeAnteil, farbe, zIndex)
	local traeger = Instance.new("Frame")
	traeger.Name = name .. "Pivot"
	traeger.AnchorPoint = Vector2.new(0.5, 0.5)
	traeger.Position = UDim2.new(0.5, 0, 0.5, 0)
	traeger.Size = UDim2.new(1, 0, 1, 0)
	traeger.BackgroundTransparency = 1
	traeger.ZIndex = zIndex
	traeger.Parent = blatt

	local zeiger = Instance.new("Frame")
	zeiger.Name = name
	zeiger.AnchorPoint = Vector2.new(0.5, 1)
	zeiger.Position = UDim2.new(0.5, 0, 0.5, 0)
	zeiger.BackgroundColor3 = farbe
	zeiger.BorderSizePixel = 0
	zeiger.ZIndex = zIndex
	zeiger.Parent = traeger

	local ecke = Instance.new("UICorner")
	ecke.CornerRadius = UDim.new(0.5, 0)
	ecke.Parent = zeiger

	return { traeger = traeger, zeiger = zeiger, laenge = laengeAnteil, dicke = dickeAnteil }
end

local stundenZeiger = baueZeiger("HourHand", 0.52, 0.026, Farbe.Gold, 4)
local minutenZeiger = baueZeiger("MinuteHand", 0.78, 0.015, Farbe.Gold, 5)

local nabe = Instance.new("Frame")
nabe.Name = "Hub"
nabe.AnchorPoint = Vector2.new(0.5, 0.5)
nabe.Position = UDim2.new(0.5, 0, 0.5, 0)
nabe.BackgroundColor3 = Farbe.Gold
nabe.BorderSizePixel = 0
nabe.ZIndex = 6
nabe.Parent = blatt
local nabeEcke = Instance.new("UICorner")
nabeEcke.CornerRadius = UDim.new(0.5, 0)
nabeEcke.Parent = nabe

-- Die Prozentzahl steht IN der Mitte des Blattes, nicht daneben: dort schaut man ohnehin
-- hin, und das Blatt bleibt ein Kreis statt eines Kreises mit Anhängseln.
local prozent = Instance.new("TextLabel")
prozent.Name = "Percent"
prozent.AnchorPoint = Vector2.new(0.5, 0.5)
prozent.Position = UDim2.new(0.5, 0, 0.68, 0)
prozent.Size = UDim2.new(0.5, 0, 0, 28)
prozent.BackgroundTransparency = 1
prozent.Font = Schrift.Zahl
prozent.TextScaled = true
prozent.TextColor3 = Farbe.Text
prozent.Text = "0%"
prozent.Parent = blatt

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 0.92, 0)
status.Size = UDim2.new(0.9, 0, 0, 18)
status.BackgroundTransparency = 1
status.Font = Schrift.Zahl
status.TextScaled = true
status.TextColor3 = Farbe.TextZweit
status.Text = "CONNECTING"
status.Parent = grund

-- ===== Der Ladebalken =====
-- Schmal und unter dem Blatt: er soll die Uhr nicht überstimmen. Was gerade passiert, sagt
-- die Zeile darunter; wie weit es ist, die Zahl in der Mitte des Blattes.
local balken = Instance.new("Frame")
balken.Name = "ProgressTrack"
balken.AnchorPoint = Vector2.new(0.5, 1)
balken.Position = UDim2.new(0.5, 0, 0.92, -26)
balken.BackgroundColor3 = Farbe.Vertieft
balken.BorderSizePixel = 0
balken.Parent = grund

local balkenEcke = Instance.new("UICorner")
balkenEcke.CornerRadius = UDim.new(0.5, 0)
balkenEcke.Parent = balken

local balkenRand = Instance.new("UIStroke")
balkenRand.Thickness = 1
balkenRand.Color = Farbe.RandMatt
balkenRand.Parent = balken

local balkenFuellung = Instance.new("Frame")
balkenFuellung.Name = "ProgressFill"
balkenFuellung.Size = UDim2.new(0, 0, 1, 0)
balkenFuellung.BackgroundColor3 = Farbe.Akzent
balkenFuellung.BorderSizePixel = 0
balkenFuellung.Parent = balken

local fuellEcke = Instance.new("UICorner")
fuellEcke.CornerRadius = UDim.new(0.5, 0)
fuellEcke.Parent = balkenFuellung

-- ===== Masse aus der Bildschirmgrösse =====
-- Alles relativ: auf dem Telefon im Hochformat bestimmt die Breite, am Rechner die Höhe.
-- Vorher standen hier feste 500 Pixel, und das lief auf einem 400er Bildschirm über.
local function masseSetzen()
	local flaeche = screenGui.AbsoluteSize
	if flaeche.X <= 0 or flaeche.Y <= 0 then
		return
	end
	local durchmesser = math.clamp(math.min(flaeche.X * 0.78, flaeche.Y * 0.52), 180, 420)
	blatt.Size = UDim2.new(0, durchmesser, 0, durchmesser)

	local radius = durchmesser / 2
	local strichLaenge = math.max(8, durchmesser * 0.05)

	for stunde, eintrag in pairs(striche) do
		local dicke = eintrag.station and 3 or 2
		eintrag.rahmen.Size = UDim2.new(0, dicke, 0, strichLaenge)
		-- Zwölf Uhr ist oben, im Uhrzeigersinn weiter. Der Winkel wird deshalb von der
		-- Senkrechten aus gerechnet, nicht von der Waagrechten.
		local winkel = math.rad(stunde * 30)
		local abstand = radius - strichLaenge * 0.9
		eintrag.rahmen.Position = UDim2.new(
			0.5, math.sin(winkel) * abstand,
			0.5, -math.cos(winkel) * abstand)
	end

	for stunde, marke in pairs(marken) do
		local winkel = math.rad(stunde * 30)
		local abstand = radius - strichLaenge * 2.6
		marke.Size = UDim2.new(0, durchmesser * 0.34, 0, math.max(11, durchmesser * 0.045))
		marke.Position = UDim2.new(
			0.5, math.sin(winkel) * abstand,
			0.5, -math.cos(winkel) * abstand)
	end

	for _, eintrag in ipairs({ stundenZeiger, minutenZeiger }) do
		eintrag.zeiger.Size = UDim2.new(
			0, math.max(2, durchmesser * eintrag.dicke),
			0, radius * eintrag.laenge)
	end
	nabe.Size = UDim2.new(0, math.max(8, durchmesser * 0.035), 0, math.max(8, durchmesser * 0.035))

	balken.Size = UDim2.new(0, durchmesser, 0, 6)
end

masseSetzen()
screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(masseSetzen)

-- ===== Die Uhr geht =====
-- Einmal je Sekunde reicht: der Minutenzeiger bewegt sich mit den Sekunden weiter, der
-- Stundenzeiger mit den Minuten -- beides gleitend, sonst sähe die Uhr aus wie ein Bild.
--
-- Aufgeleuchtet wird die Stadt, auf deren Stunde der Stundenzeiger gerade steht. Nur eine,
-- und sie wechselt mit der Zeit: es ist dann IHRE Stunde.
local function stelleUhr()
	local zeit = geroldswilZeit()
	local minuteGleitend = zeit.min + zeit.sec / 60
	local stundeGleitend = (zeit.hour % 12) + minuteGleitend / 60

	minutenZeiger.traeger.Rotation = minuteGleitend * 6
	stundenZeiger.traeger.Rotation = stundeGleitend * 30

	local aktuelleStunde = zeit.hour % 12
	if aktuelleStunde == 0 then
		aktuelleStunde = 12
	end
	for stunde, marke in pairs(marken) do
		local dran = (stunde == aktuelleStunde)
		marke.TextColor3 = dran and Farbe.Gold or Farbe.TextMatt
		local eintrag = striche[stunde]
		if eintrag then
			-- Die Stunde, die gerade dran ist, steht in vollem Gold; die uebrigen
			-- Stadtstunden ebenfalls in Gold, aber ohne Beschriftung in Farbe -- so hebt
			-- sich der Moment ab, ohne dass das Blatt zerfaellt.
			eintrag.rahmen.BackgroundColor3 = dran and Farbe.Gold
				or (eintrag.station and Farbe.Gold or Farbe.GoldMatt)
		end
	end
end

-- ===== Fortschritt =====
-- Er steht in der Zahl und im schmalen Balken unter dem Blatt -- NICHT im Zeiger. Eine Uhr,
-- die schneller läuft, weil ein Bild fertig wurde, wäre keine Uhr mehr.
local letzterAnteil = 0

local function setzeFortschritt(anteil, text)
	anteil = math.clamp(anteil, 0, 1)
	letzterAnteil = math.max(letzterAnteil, anteil) -- nie rückwärts, das sähe nach Fehler aus

	TweenService:Create(balkenFuellung, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(letzterAnteil, 0, 1, 0),
	}):Play()
	prozent.Text = math.floor(letzterAnteil * 100) .. "%"
	if text then
		status.Text = string.upper(text)
	end
end

-- ===== Die Bilder =====
-- Alle Symbolsammlungen von HudChrome plus das Titelbild. Genau die Dateien, die im Spiel
-- sofort gebraucht werden -- Angriffsknöpfe, Energietypen, Fraktionen, Geschenke.
local GAME_IMAGE_ID = "rbxassetid://93529420608088"

local function bilderListe()
	local liste = { GAME_IMAGE_ID }
	if not HudChrome then
		return liste
	end
	for _, sammlung in ipairs({
		HudChrome.Icon, HudChrome.GiftIcon, HudChrome.EnergyIcon, HudChrome.FactionIcon,
	}) do
		if type(sammlung) == "table" then
			for _, assetId in pairs(sammlung) do
				if type(assetId) == "string" and assetId ~= "" then
					table.insert(liste, assetId)
				end
			end
		end
	end
	return liste
end

-- ===== Die Tore =====
-- Was fertig sein MUSS, bevor der Bildschirm verschwindet. Bilder zuerst und mit dem
-- grössten Anteil: sie sind der Grund, warum es diesen Bildschirm gibt.
local function warteAufGui(name, sekunden)
	local playerGui = player:WaitForChild("PlayerGui")
	local ende = os.clock() + (sekunden or 15)
	while not playerGui:FindFirstChild(name) do
		if os.clock() > ende then
			return false
		end
		task.wait(0.1)
	end
	return true
end

local TORE = {
	{ text = "Connecting", tun = function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
	end },
	{ text = "Waking the Trenchborn", tun = function()
		if not player.Character then
			player.CharacterAdded:Wait()
		end
	end },
	{ text = "Winding the clock", tun = function()
		warteAufGui("GameHud")
	end },
	{ text = "Opening the bays", tun = function()
		warteAufGui("NavigationGui")
	end },
}

task.spawn(function()
	-- Anteil: drei Viertel für die Bilder, ein Viertel für die Tore. Der Bildanteil ist
	-- der einzige, der wirklich Zeit kostet, und der einzige, den wir Datei für Datei
	-- messen können.
	local BILD_ANTEIL = 0.75

	local bilder = bilderListe()
	local gesamt = math.max(#bilder, 1)
	local fertig = 0
	setzeFortschritt(0, "Loading artwork")

	-- PreloadAsync meldet je Datei zurück. Der Rückkanal ist der Grund, warum hier nicht
	-- einfach die ganze Liste auf einmal übergeben und gewartet wird: ohne ihn stünde der
	-- Zeiger die ganze Zeit still und spränge am Ende auf drei Viertel.
	local ok, fehler = pcall(function()
		ContentProvider:PreloadAsync(bilder, function(_, status)
			fertig += 1
			setzeFortschritt((fertig / gesamt) * BILD_ANTEIL)
			if status == Enum.AssetFetchStatus.Failure then
				warn("[LoadingScreen] Ein Bild liess sich nicht laden -- es fehlt im Spiel.")
			end
		end)
	end)
	if not ok then
		warn("[LoadingScreen] Vorladen fehlgeschlagen: " .. tostring(fehler))
	end
	print(string.format("[Kaiju Debug] Ladebildschirm: %d Bilder vorgeladen.", gesamt))

	for index, tor in ipairs(TORE) do
		setzeFortschritt(BILD_ANTEIL + ((index - 1) / #TORE) * (1 - BILD_ANTEIL), tor.text)
		local torOk = pcall(tor.tun)
		if not torOk then
			warn("[LoadingScreen] Schritt '" .. tor.text .. "' fehlgeschlagen, weiter.")
		end
		setzeFortschritt(BILD_ANTEIL + (index / #TORE) * (1 - BILD_ANTEIL))
	end

	setzeFortschritt(1, "The hour has come")

	-- Kurz stehen lassen: der Zeiger soll seine Runde sichtbar zu Ende drehen, nicht im
	-- Sprung verschwinden.
	task.wait(0.6)

	local ausblenden = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, objekt in ipairs(grund:GetDescendants()) do
		if objekt:IsA("TextLabel") then
			TweenService:Create(objekt, ausblenden, { TextTransparency = 1 }):Play()
		elseif objekt:IsA("Frame") then
			TweenService:Create(objekt, ausblenden, { BackgroundTransparency = 1 }):Play()
		elseif objekt:IsA("UIStroke") then
			TweenService:Create(objekt, ausblenden, { Transparency = 1 }):Play()
		end
	end
	TweenService:Create(grund, ausblenden, { BackgroundTransparency = 1 }):Play()

	task.wait(0.75)
	screenGui:Destroy()
end)

-- Die Uhr läuft, solange der Bildschirm steht. Einmal je Viertelsekunde genügt: der
-- Sekundenzeiger fehlt, und feiner als das sieht niemand.
task.spawn(function()
	while screenGui.Parent do
		pcall(stelleUhr)
		task.wait(0.25)
	end
end)

-- Der Rand des Blattes atmet leicht -- ein völlig stehendes Bild wirkt schnell wie ein
-- hängendes Spiel, und die Zeiger allein bewegen sich dafür zu langsam.
task.spawn(function()
	local start = os.clock()
	while screenGui.Parent do
		blattRand.Color = Farbe.RandMatt:Lerp(Farbe.Rand, 0.5 + 0.5 * math.sin((os.clock() - start) * 2))
		RunService.Heartbeat:Wait()
	end
end)
