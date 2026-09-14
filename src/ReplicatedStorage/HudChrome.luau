-- ModuleScript: HudChrome
-- Ort in Studio: ReplicatedStorage
--
-- Der Baukasten für das HUD im Spiel: militärisch, nüchtern, instrumentenhaft.
--
-- ===== Was sich gegenüber ComicStyleUtils ändert =====
-- ComicStyleUtils macht genau zwei Dinge: eine runde Ecke und einen HARTEN SCHWARZEN
-- Rahmen. Das ist die ganze Comic-Anmutung, und sie steckt in zwei Zeilen. Hier tritt an
-- ihre Stelle: dunkler Grund, dünne Stahllinie, knappe Ecke.
--
-- Der zweite Unterschied ist wichtiger. ComicStyleUtils DEKORIERT ein fertiges Objekt und
-- überlässt jedem Aufrufer, welchen Radius und welche Rahmendicke er nimmt -- über 101
-- Aufrufe sind so Radien von 3 bis 44 und Dicken von 0 bis 5 entstanden, ohne jede Skala.
-- Dieses Modul liefert stattdessen FERTIGE REZEPTE. Wer ein Panel will, bekommt ein Panel;
-- die Zahlen dahinter stehen an einer Stelle.
--
-- Die Menüs behalten vorerst ComicStyleUtils. Sie kommen als eigener Schritt, und bis
-- dahin laufen beide Stile nebeneinander -- das ist ein Zwischenzustand, kein Ziel.
--
-- ===== Die drei Regeln =====
-- 1. Das Chrome ist FARBLOS. Grund, Rahmen und Beschriftung sind Stahl, Weiss und Grau.
-- 2. Farbe bedeutet eine MESSUNG: Hitze, Leben, Alarm, Energie. Nichts ist bunt, weil es
--    hübsch wäre.
-- 3. Alles ist ZWEIZEILIG beschriftet: grosse Bezeichnung, kleine graue Unterzeile. Das
--    ist das militärische Signal -- nicht die Schrift, sondern dass alles eingeordnet wird.

local HudChrome = {}

-- ===== Farben =====
--
-- Accent ist Cyan und gehört EXKLUSIV der Special Energy. Der Energiebogen über dem
-- Tacho trägt diesen Ton schon heute (70,210,255); er bekommt ihn damit zur alleinigen
-- Bedeutung. Die Energiesorte "Electric" ist ebenfalls cyan, erscheint aber nur in den
-- Menüs -- im HUD ist Cyan eindeutig.
HudChrome.Color = {
	Panel = Color3.fromRGB(13, 15, 19), -- fast schwarz, leicht blaustichig
	PanelRaised = Color3.fromRGB(22, 25, 31), -- für Elemente, die auf einem Panel liegen
	PanelSunken = Color3.fromRGB(8, 9, 12), -- für Vertiefungen: Balkenhintergründe, Schächte

	Border = Color3.fromRGB(70, 80, 94), -- Stahl, der Normalfall
	BorderBright = Color3.fromRGB(132, 148, 168), -- für das, was gerade wichtig ist
	BorderDim = Color3.fromRGB(40, 46, 55), -- für Gesperrtes und Ruhendes

	TextPrimary = Color3.fromRGB(232, 238, 245),
	TextSecondary = Color3.fromRGB(172, 184, 200), -- die Unterzeilen; heller als zuerst (140,152,168), das war auf dunklem Grund zu schwach
	TextDim = Color3.fromRGB(86, 96, 110), -- Gesperrtes

	Accent = Color3.fromRGB(70, 210, 255), -- Special Energy, sonst nichts
	Ready = Color3.fromRGB(255, 176, 32), -- Bernstein: bereit, ohne Kosten
	Warning = Color3.fromRGB(255, 176, 32),
	Danger = Color3.fromRGB(232, 58, 44),
}

-- ===== Masse =====
-- Eine Skala statt freier Wahl je Aufrufstelle.
HudChrome.Radius = {
	Panel = 6,
	Small = 4,
	Pill = 999, -- wird als voller Halbkreis gesetzt
}
HudChrome.BorderThickness = 1

-- ===== Schriften =====
--
-- Oswald ist schmal und hoch -- der Schilder- und Formularton, den das Vorbild trägt.
-- RobotoMono für Zahlen: Lebenspunkte, Countdown und Tachowert zappeln sonst beim
-- Hochzählen, weil Ziffern unterschiedlich breit sind. Gotham bleibt Fliesstext.
--
-- Defensiv aufgelöst: fehlt eine Schrift in dieser Roblox-Version, würde der direkte
-- Zugriff das ganze Skript abbrechen -- und zwar jedes, das dieses Modul lädt. Lieber
-- eine Ersatzschrift und eine laute Warnung.
local function resolveFont(preferred, fallback)
	local ok, font = pcall(function()
		return Enum.Font[preferred]
	end)
	if ok and font then
		return font
	end
	warn(string.format(
		"[Kaiju Debug] HudChrome: Schrift '%s' gibt es in dieser Roblox-Version nicht -- "
			.. "es wird '%s' benutzt. Das HUD sieht dadurch anders aus als vorgesehen.",
		preferred,
		fallback
	))
	return Enum.Font[fallback]
end

HudChrome.Font = {
	Label = resolveFont("Oswald", "GothamBold"), -- Bezeichnungen, Knöpfe, Titel
	Number = resolveFont("RobotoMono", "Code"), -- alles, was sich ändert und zählt
	Body = Enum.Font.Gotham, -- Fliesstext, unverändert
}

-- Nachweis beim Laden: welche Schriften tatsächlich benutzt werden. Ohne diese Zeile wäre
-- im Spiel nicht zu unterscheiden, ob das HUD anders aussieht als gedacht, weil der Stil
-- nicht greift -- oder weil eine Schrift fehlte und still ersetzt wurde.
print(string.format(
	"[Kaiju Debug] HudChrome bereit -- Beschriftung %s, Zahlen %s, Fliesstext %s.",
	HudChrome.Font.Label.Name,
	HudChrome.Font.Number.Name,
	HudChrome.Font.Body.Name
))

-- ===== Textgrössen =====
-- Feste Werte, KEIN TextScaled. Im Bestand steht fast jeder Text auf TextScaled, die
-- Schriftgrösse folgt dort also der Kästchenhöhe -- zwei gleichrangige Beschriftungen
-- sehen dadurch verschieden gross aus, je nachdem wie gross ihr Kästchen zufällig ist.
--
-- Die ersten Werte (Label 15, Sublabel 11) waren zu knapp: auf einem 100 Pixel breiten
-- Knopf musste man genau hinsehen, und die Unterzeile war gar nicht zu lesen. Oswald ist
-- zusaetzlich schmal -- schmale Schrift braucht mehr Groesse als eine breite, um bei
-- gleichem Eindruck lesbar zu bleiben. Beide Werte sind deshalb deutlich angehoben.
HudChrome.TextSize = {
	Title = 22,
	Label = 19,
	Sublabel = 13,
	Number = 17,
	NumberLarge = 24,
}

-- ===== Symbole =====
--
-- Von Amancio hochgeladene Bilder. Sie loesen die geometrischen Zeichen ab, die
-- ihrerseits die Emoji abgeloest hatten -- Emoji zeichnet das Betriebssystem in seinem
-- eigenen Stil, geometrische Zeichen haengen an der Schrift, und beides war nur die beste
-- Loesung mit Bordmitteln.
--
-- Alle dreizehn stehen hier, obwohl das HUD erst fuenf davon benutzt. Die uebrigen
-- gehoeren zu Kopfleiste, Objective-Liste und Menue und kommen in den naechsten Scheiben
-- dazu -- eine zweite Liste an einer zweiten Stelle waere genau die Art Doppelung, die
-- irgendwann auseinanderlaeuft.
HudChrome.Icon = {
	-- Angriffe
	Punch = "rbxassetid://123083985565838",
	Jump = "rbxassetid://134576136586426",
	Focus = "rbxassetid://109063571686310",
	Area = "rbxassetid://124403954068217",
	Absorb = "rbxassetid://119396827761528",

	-- Kopfleiste
	Menu = "rbxassetid://82349353662422",
	Home = "rbxassetid://129438474298071",
	Music = "rbxassetid://72188447540073",
	Coin = "rbxassetid://120384779936685",
	Alert = "rbxassetid://98663897996847",

	-- Objective-Liste
	Objective = "rbxassetid://137194925165755",
	BuildingDestruction = "rbxassetid://116647769762689",
	Guardian = "rbxassetid://103770979890545",

	-- Die acht Menuepunkte. Sie loesen die Emoji ab, die bisher auf den Kacheln standen --
	-- dasselbe Argument wie bei den Angriffen: ein Emoji zeichnet das Betriebssystem in
	-- seinem eigenen bunten Stil, und acht davon nebeneinander waren die lauteste Flaeche
	-- im ganzen Menue.
	--
	-- Der Schluessel "Skins" heisst so, obwohl der Menuepunkt intern "Monster" ist: der
	-- interne Name steht im Speicherstand und darf nicht wandern, der sichtbare ist Skins.
	Skins = "rbxassetid://89192509867933",
	Achievements = "rbxassetid://126073634057511",
	Talents = "rbxassetid://124483432242014",
	Companion = "rbxassetid://105165530758812",
	Gift = "rbxassetid://93207170168404",
	Faction = "rbxassetid://74313387395312",
	Archive = "rbxassetid://90336087936743",
	Help = "rbxassetid://119487776863498",
}

-- Legt ein Symbol an.
--
-- ScaleType.Fit statt des Standards: gestreckte Symbole fallen sofort auf, und ein Bild
-- in einem Kaestchen anderer Seitenverhaeltnisse ist der Normalfall, nicht die Ausnahme.
--
-- `tint` bleibt bewusst optional und ist standardmaessig AUS. Faerben lohnt nur bei
-- einfarbigen Symbolen; traegt das Bild eigene Farben, macht ein Farbton es kaputt. Die
-- Unterscheidung "frei gegen Energie" traegt ohnehin schon der Akzentstreifen.
-- ===== Symbole der Energietypen =====
--
-- Noch nicht hochgeladen. Sie stehen hier und nicht beim Welt-Event-Banner, weil ausser
-- ihm auch der Talentbaum und die Energie-Anzeigen dieselben fuenf Typen zeigen -- eine
-- zweite Liste anderswo waere die naechste Stelle, die auseinanderlaeuft.
--
-- Die Schluessel sind die Typnamen aus EnergyTypesClient und den Gebaeude-Attributen. Wer
-- hier umbenennt, bricht die Zuordnung still -- der Aufrufer faellt dann wortlos auf den
-- Farbstreifen zurueck.
HudChrome.EnergyIcon = {
	Heat = "rbxassetid://131883487619340",
	Chemical = "rbxassetid://88519091287608",
	Electric = "rbxassetid://98858508361600",
	Radiation = "rbxassetid://90519732597438",
	Spirit = "rbxassetid://111068377126240",
}

-- ===== Farben der fuenf Energien =====
--
-- Sie standen in FUENF Dateien: EnergyTypesClient (als "Farbreferenz" deklariert),
-- SkinSelectionGui, EnergyAbsorbClient, EnergyTypeSkin und EnergyCollectionHandler. Vier
-- davon waren gleich, eine nicht -- Heat war beim fliegenden Symbol und beim Partikel
-- orange (255,140,30), beim Gebaeude und beim Strom rot (255,35,25). Dieselbe Energie sah
-- also verschieden aus, je nachdem, wo man sie gerade ansah.
--
-- Massgeblich ist die Reihe aus EnergyTypesClient: sie war ausdruecklich als Referenz
-- angelegt, nur hat sich niemand daran gehalten, weil sie in einem Client-Skript stand und
-- der Server nicht hineinsehen kann. Hier koennen es beide.
HudChrome.EnergyColor = {
	Heat = Color3.fromRGB(255, 35, 25),
	Chemical = Color3.fromRGB(255, 45, 190),
	Electric = Color3.fromRGB(57, 217, 255),
	Radiation = Color3.fromRGB(126, 255, 16),
	Spirit = Color3.fromRGB(255, 205, 70),
}

-- Rueckfallebene fuer einen Typ, den niemand kennt -- ein Gebaeude mit vertipptem Attribut
-- soll sichtbar Energie geben und nicht unsichtbar bleiben.
HudChrome.EnergyColorDefault = Color3.fromRGB(255, 140, 40)

-- ===== Symbole der drei Figuren =====
--
-- Kaiju, Jaeger, Ronin -- die drei Kapitel des Spiels. Sie erscheinen in der
-- Fraktionsauswahl, im Achievement-Bildschirm und in der Hilfe; bisher standen dort drei
-- Emoji, und zwar in jeder Datei ein anderes Trio.
HudChrome.FactionIcon = {
	Kaiju = "rbxassetid://100425603487710",
	Jaeger = "rbxassetid://78662648045793",
	Ronin = "rbxassetid://104693164949285",
}

-- ===== Symbole der Zeitgeschenke =====
--
-- Sechs Sorten, nicht zwoelf Geschenke: die zwoelf Stationen verteilen sich auf diese
-- sechs, und mehrere davon kommen mehrfach vor. Wer zwoelf Bilder anlegte, malte dasselbe
-- Ding sechsmal doppelt.
--
-- Die Schluessel sind die TYPEN aus GiftHandler, nicht die Beschriftungen: "XP" heisst
-- dort so, auch wenn das Bild "XP Boost" gezeichnet ist. Wer hier umbenennt, bricht die
-- Zuordnung still -- der Bildschirm faellt dann wortlos auf das Emoji zurueck.
HudChrome.GiftIcon = {
	Coins = "rbxassetid://90818354899235",
	XP = "rbxassetid://110300343896143",
	Evolution = "rbxassetid://135223583855951",
	CoinsBoost = "rbxassetid://98720807266046",
	DamageBoost = "rbxassetid://97430318788181",
	MegaBoost = "rbxassetid://73202136279847",
}

function HudChrome.IconImage(parent, assetId, tint)
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.Image = assetId
	image.ScaleType = Enum.ScaleType.Fit
	if tint then
		image.ImageColor3 = tint
	end
	image.Parent = parent
	return image
end

-- ===== Symbole vorladen =====
--
-- Roblox laedt Bilder einzeln und still nach, sobald sie zum ersten Mal gezeigt werden.
-- Scheitert eines -- falsche Kennung, noch nicht freigegeben, zu gross fuer den Speicher
-- des Geraets -- bleibt das Feld einfach leer. Es gibt keinen Fehler, keine Warnung, und
-- auf dem Telefon sieht man ein anderes Ergebnis als am PC, ohne zu wissen warum.
--
-- Deshalb hier: alle Symbole aktiv vorladen und dabei je Datei BERICHTEN, ob sie
-- angekommen ist. Das ist der Unterschied zwischen "das Symbol fehlt" und "ich habe an der
-- falschen Stelle geschaut".
local function preloadIcons()
	local ContentProvider = game:GetService("ContentProvider")

	local liste = {}
	local namen = {}
	-- Alle Sammlungen, nicht nur HudChrome.Icon. Die Geschenksymbole erscheinen genau
	-- einmal je Sitzung und ausgerechnet in dem Moment, in dem etwas bereit wird -- dort
	-- ein leeres Feld zu sehen waere die schlechteste Stelle dafuer. Die Energietypen sind
	-- noch leer und fallen von selbst heraus.
	for _, sammlung in ipairs({
		HudChrome.Icon,
		HudChrome.GiftIcon,
		HudChrome.EnergyIcon,
		HudChrome.FactionIcon,
	}) do
		for name, assetId in pairs(sammlung) do
			if assetId ~= "" then
				table.insert(liste, assetId)
				namen[assetId] = name
			end
		end
	end

	-- PreloadAsync meldet je Datei zurueck, OB sie geladen wurde -- genau das wird hier
	-- gebraucht.
	--
	-- Der erste Versuch pruefte stattdessen IsLoaded an einem frisch angelegten
	-- ImageLabel. Das war falsch: ein ImageLabel, das nirgends eingehaengt ist, wird nie
	-- gezeichnet, also laedt Roblox sein Bild gar nicht erst. IsLoaded blieb dadurch bei
	-- ALLEN auf false -- auch bei denen, die im Spiel einwandfrei zu sehen waren. Eine
	-- Pruefung, die immer dasselbe sagt, ist keine Pruefung.
	local fehlend = {}
	local ok = pcall(function()
		ContentProvider:PreloadAsync(liste, function(contentId, status)
			if status ~= Enum.AssetFetchStatus.Success then
				local name = namen[contentId] or "?"
				table.insert(fehlend, string.format("%s (%s, %s)", name, contentId, status.Name))
			end
		end)
	end)
	if not ok then
		warn("[Kaiju Debug] HudChrome: Vorladen der Symbole fehlgeschlagen.")
		return
	end

	if #fehlend > 0 then
		warn(string.format(
			"[Kaiju Debug] HudChrome: %d von %d Symbolen sind NICHT geladen -- %s. "
				.. "Moegliche Gruende: Kennung falsch, Bild von Roblox noch nicht freigegeben, "
				.. "oder es gehoert einem anderen Konto als dem, dem dieses Spiel gehoert.",
			#fehlend,
			#liste,
			table.concat(fehlend, ", ")
		))
	else
		print(string.format("[Kaiju Debug] HudChrome: alle %d Symbole geladen.", #liste))
	end
end

if game:GetService("RunService"):IsClient() then
	task.spawn(preloadIcons)
end

-- ===== Panel =====
--
-- `options` (alle optional):
--   radius        Eckenradius in Pixeln, sonst HudChrome.Radius.Panel
--   fill          Hintergrundfarbe, sonst HudChrome.Color.Panel. `false` = durchsichtig
--   transparency  Durchsichtigkeit des Grundes, sonst 0.12
--   border        Rahmenfarbe, sonst HudChrome.Color.Border. `false` = kein Rahmen
--   thickness     Rahmendicke, sonst 1
--
-- Gibt (corner, stroke) zurück -- dieselbe Form wie ComicStyleUtils.Apply, damit die
-- wenigen Aufrufstellen, die den Rückgabewert nutzen, unverändert weiterlaufen.
function HudChrome.Panel(guiObject, options)
	options = options or {}

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, options.radius or HudChrome.Radius.Panel)
	corner.Parent = guiObject

	if options.fill ~= false then
		guiObject.BackgroundColor3 = options.fill or HudChrome.Color.Panel
		guiObject.BackgroundTransparency = options.transparency or 0.12
	end
	if guiObject:IsA("GuiObject") then
		guiObject.BorderSizePixel = 0
	end

	local stroke
	if options.border ~= false then
		stroke = Instance.new("UIStroke")
		stroke.Thickness = options.thickness or HudChrome.BorderThickness
		stroke.Color = options.border or HudChrome.Color.Border
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = guiObject
	end

	return corner, stroke
end

-- Runde Form für alles, was wie ein Knopf oder eine Plakette aussehen soll.
function HudChrome.Pill(guiObject, options)
	options = options or {}
	local corner, stroke = HudChrome.Panel(guiObject, options)
	corner.CornerRadius = UDim.new(0.5, 0)
	return corner, stroke
end

-- ===== Text =====

-- Bezeichnung: die grosse Zeile. Gesperrt, weil die Vorlage es so hält -- das ist der
-- Unterschied zwischen einem Etikett und einer Überschrift.
function HudChrome.Label(textLabel, size)
	textLabel.Font = HudChrome.Font.Label
	textLabel.TextScaled = false
	textLabel.TextSize = size or HudChrome.TextSize.Label
	textLabel.TextColor3 = HudChrome.Color.TextPrimary
	textLabel.TextStrokeTransparency = 1
	return textLabel
end

-- Unterzeile: klein, grau. Sie sagt, WAS das Element tut.
--
-- Sie benutzt bewusst die ZIFFERNSCHRIFT und nicht die Beschriftungsschrift. Oswald ist
-- schmal, und schmale Schrift mit duennem Strich wird bei 13 Punkten auf dunklem Grund
-- unleserlich -- genau das war sie im ersten Versuch. Eine Schrift mit gleicher
-- Zeichenbreite ist an dieser Stelle doppelt richtig: sie ist breiter und damit lesbarer,
-- und sie klingt nach Beschriftung auf einem Geraet statt nach Ueberschrift.
--
-- Eine vierte Schrift waere die Alternative gewesen. Drei sind genug.
function HudChrome.Sublabel(textLabel, size)
	textLabel.Font = HudChrome.Font.Number
	textLabel.TextScaled = false
	textLabel.TextSize = size or HudChrome.TextSize.Sublabel
	textLabel.TextColor3 = HudChrome.Color.TextSecondary
	textLabel.TextStrokeTransparency = 1
	return textLabel
end

-- Zahlen: alles, was sich ändert und gezählt wird.
function HudChrome.Number(textLabel, size)
	textLabel.Font = HudChrome.Font.Number
	textLabel.TextScaled = false
	textLabel.TextSize = size or HudChrome.TextSize.Number
	textLabel.TextColor3 = HudChrome.Color.TextPrimary
	textLabel.TextStrokeTransparency = 1
	return textLabel
end

-- ===== Akzentstreifen =====
--
-- Der dünne Balken an der Unterkante eines Knopfes. In der Vorlage ist er Zierde; hier
-- ist er die BEREITSCHAFTSANZEIGE und beantwortet damit die einzige Frage, die man beim
-- Blick auf einen Angriffsknopf hat: kann ich jetzt? Schneller als eine Zahl, die man
-- erst mit dem Energiestand vergleichen muss.
--
-- Gibt (track, fill) zurück. Die Füllung setzt der Aufrufer über fill.Size.
function HudChrome.AccentBar(parent, color, height)
	local track = Instance.new("Frame")
	track.Name = "AccentBar"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -5)
	track.Size = UDim2.new(1, -12, 0, height or 3)
	track.BackgroundColor3 = HudChrome.Color.PanelSunken
	track.BackgroundTransparency = 0.3
	track.BorderSizePixel = 0
	track.ZIndex = (parent.ZIndex or 1) + 2
	track.Parent = parent

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = color or HudChrome.Color.Accent
	fill.BorderSizePixel = 0
	fill.ZIndex = track.ZIndex
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	return track, fill
end

-- ===== Schraege Felder =====
--
-- Ein Feld, dessen AEUSSERE Kante schraeg laeuft. Zwei davon nebeneinander ergeben das
-- Bild aus der Vorlage: beide Schraegen laufen nach unten aufeinander zu und zeigen damit
-- auf die Mitte des Bildschirms, wo die Spielfigur steht. Das ist der Grund fuer die Form
-- -- sie ist keine Zierde, sie richtet den Blick.
--
-- Roblox zeichnet keine Vielecke. Der erste Versuch lief ueber einen Farbverlauf mit
-- hartem Sprung in der Durchsichtigkeit: gedrehte Achse, also schraege Schnittkante. Im
-- Spiel sass dieser Schnitt aber weit neben der Stelle, an der er nach meiner Rechnung
-- sitzen musste -- die Flaeche endete lange vor der schraegen Linie, und ein Stueck des
-- Hintergrunds fehlte. Wie UIGradient seine Werte auf ein GEDREHTES Rechteck abbildet,
-- liess sich von aussen nicht zuverlaessig bestimmen.
--
-- Deshalb jetzt aus reiner Geometrie: die Flaeche besteht aus waagerechten Streifen, die
-- auf der schraegen Seite von Streifen zu Streifen weiter einruecken. Der Einzug ist
-- schlichte Dreisatzrechnung, jeder Streifen sitzt dort, wo er nachrechenbar hingehoert,
-- und es bleibt keine Annahme ueber das Verhalten der Engine uebrig.
--
-- Die Streifen ueberlappen sich um einen Pixel und sind deckend. Beides gehoert zusammen:
-- ohne Ueberlappung entstehen beim Skalieren Haarfugen, und bei durchscheinender Farbe
-- wuerden ueberlappende Streifen an den Fugen doppelt dunkeln.
--
-- side = "Left": die linke Kante laeuft von oben links nach unten rechts ("\").
-- side = "Right": die rechte Kante laeuft von oben rechts nach unten links ("/").
--
-- Gibt (frame) zurueck. Achtung beim Fuellen: die abgeschnittene Ecke ist unten aussen,
-- Inhalt braucht dort mindestens `slant` Abstand zum Rand.
local STREIFEN_HOEHE = 2

function HudChrome.SlantPanel(parent, options)
	options = options or {}
	local width = options.width or 220
	local height = options.height or 62
	local slant = options.slant or 16
	local side = options.side or "Left"
	local fill = options.fill or HudChrome.Color.Panel
	local randFarbe = options.border or HudChrome.Color.Border
	local dicke = options.thickness or HudChrome.BorderThickness

	local frame = Instance.new("Frame")
	frame.Name = options.name or "SlantPanel"
	frame.Size = UDim2.new(0, width, 0, height)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local koerper = Instance.new("Frame")
	koerper.Name = "Body"
	koerper.Size = UDim2.new(1, 0, 1, 0)
	koerper.BackgroundTransparency = 1
	koerper.BorderSizePixel = 0
	koerper.Parent = frame

	local anzahl = math.ceil(height / STREIFEN_HOEHE)
	for i = 0, anzahl - 1 do
		local y = i * STREIFEN_HOEHE
		-- Ein Pixel Ueberlappung nach unten, aber nie ueber die Unterkante des Feldes
		-- hinaus -- sonst schaut der letzte Streifen unter der Randlinie hervor.
		local hoehe = math.min(STREIFEN_HOEHE + 1, height - y)
		-- Der Einzug folgt der Mitte des Streifens, nicht seiner Oberkante: so liegt die
		-- Treppe symmetrisch auf der gedachten Linie statt durchgaengig daneben.
		local einzug = slant * math.clamp((y + STREIFEN_HOEHE * 0.5) / height, 0, 1)

		local streifen = Instance.new("Frame")
		streifen.Name = "Strip"
		streifen.Size = UDim2.new(0, width - einzug, 0, hoehe)
		streifen.Position = UDim2.new(0, side == "Left" and einzug or 0, 0, y)
		streifen.BackgroundColor3 = fill
		streifen.BackgroundTransparency = options.transparency or 0
		streifen.BorderSizePixel = 0
		streifen.Parent = koerper
	end

	-- Die drei GERADEN Kanten als eigene Haarlinien. Ein UIStroke kann es nicht: er wuerde
	-- entweder das ganze Rechteck nachziehen -- also auch dort, wo gar keine Flaeche ist --
	-- oder, auf die Streifen gelegt, jede Treppenstufe einzeln umranden.
	local function linie(name, groesse, position)
		local l = Instance.new("Frame")
		l.Name = name
		l.Size = groesse
		l.Position = position
		l.BackgroundColor3 = randFarbe
		l.BorderSizePixel = 0
		l.ZIndex = 2
		l.Parent = frame
		return l
	end

	linie("EdgeTop", UDim2.new(1, 0, 0, dicke), UDim2.new(0, 0, 0, 0))
	if side == "Left" then
		linie("EdgeBottom", UDim2.new(1, -slant, 0, dicke), UDim2.new(0, slant, 1, -dicke))
		linie("EdgeInner", UDim2.new(0, dicke, 1, 0), UDim2.new(1, -dicke, 0, 0))
	else
		linie("EdgeBottom", UDim2.new(1, -slant, 0, dicke), UDim2.new(0, 0, 1, -dicke))
		linie("EdgeInner", UDim2.new(0, dicke, 1, 0), UDim2.new(0, 0, 0, 0))
	end

	-- Die schraege Kante als gedrehtes Rechteck, so lang wie die Diagonale, mit der Mitte
	-- auf der Mitte der Schraegen.
	local winkel = math.deg(math.atan(slant / height))
	local laenge = math.sqrt(slant * slant + height * height) + 1

	local kante = Instance.new("Frame")
	kante.Name = "SlantEdge"
	kante.AnchorPoint = Vector2.new(0.5, 0.5)
	kante.Size = UDim2.new(0, dicke, 0, laenge)
	kante.BackgroundColor3 = randFarbe
	kante.BorderSizePixel = 0
	kante.ZIndex = 2
	if side == "Right" then
		kante.Position = UDim2.new(1, -slant / 2, 0.5, 0)
		kante.Rotation = winkel
	else
		kante.Position = UDim2.new(0, slant / 2, 0.5, 0)
		kante.Rotation = -winkel
	end
	kante.Parent = frame

	return frame
end


-- ===== Fette Zahlen =====
--
-- Fuer die zwei Werte, die im Kampf zaehlen: Stufe und aktuelles Leben. Sie sind gross
-- und fett, alles andere im selben Feld ist klein und grau -- so entscheidet die Form,
-- was man zuerst sieht, und nicht die Farbe.
--
-- Enum.Font kennt keine Schnitte, nur Familien. Der fette Schnitt kommt deshalb ueber
-- FontFace. Fehlt er in der Familie, ersetzt Roblox ihn still durch den normalen -- die
-- Warnung unten ist der einzige Weg, das ueberhaupt zu bemerken.
function HudChrome.NumberBold(textLabel, size)
	HudChrome.Number(textLabel, size)

	local ok, gesicht = pcall(function()
		local basis = Font.fromEnum(HudChrome.Font.Number)
		return Font.new(basis.Family, Enum.FontWeight.Bold)
	end)
	if ok and gesicht then
		textLabel.FontFace = gesicht
	else
		warn("[Kaiju Debug] HudChrome: fetter Zahlenschnitt nicht verfuegbar, nehme den normalen.")
	end

	return textLabel
end

-- ===== Die rechte Spalte =====
--
-- Drei Skripte schreiben in dieselbe Spalte: das Ortsfeld mit Alarmsternen und Vorwarnung
-- (CityAlertHudClient), das Weltevent-Feld (EnergyTypesClient) und der Trainingsblock
-- (SkinSelectionGui). Solange jedes seine eigene Zahl fuehrte, verschob ein Umbau an einer
-- Stelle stillschweigend die anderen -- beim Hochruecken der Spalte stand die 118 dreimal
-- da, und ich hatte zuerst zwei von drei erwischt.
--
-- Deshalb stehen die Masse, ueber die sich die drei einig sein muessen, hier. Die Reihenfolge
-- von oben nach unten: Ort, Weltevent, Vorwarnung, Aufgabenliste. Der Trainingsblock ersetzt
-- im Sanctuary die ganze Spalte, dort ist alles andere ausgeblendet.
HudChrome.Spalte = {
	Oben = 86, -- unter der Kopfleiste
	Rand = -16, -- Abstand zum rechten Bildrand
	Luft = 8, -- zwischen zwei Feldern
	OrtHoehe = 98, -- Ortsfeld mit Alarmsternen
	EventHoehe = 70, -- Weltevent-Feld
}

-- Oberkante des Weltevent-Felds.
function HudChrome.SpalteEventY()
	local s = HudChrome.Spalte
	return s.Oben + s.OrtHoehe + s.Luft
end

-- Oberkante von allem, was UNTER dem Weltevent-Feld folgt.
function HudChrome.SpalteNachEventY()
	local s = HudChrome.Spalte
	return HudChrome.SpalteEventY() + s.EventHoehe + s.Luft
end

-- ===== Menue-Bildschirme =====
--
-- Die Menues -- Archiv, Talente, Geschenke, Skins, Fraktion, Achievements, Hilfe -- bauen
-- alle dasselbe: ein Vollbild-Feld, ein Titel oben links, ein Schliessen-Knopf oben rechts,
-- darunter der Inhalt. Und jedes hat es einzeln erfunden: FredokaOne hier, LuckiestGuy
-- dort, Titel mal bei 12 mal bei 14 Pixeln, der Schliessen-Knopf mal 36 mal 40 Pixel.
--
-- Genau dieselbe Streuung war der Grund fuer HudChrome im HUD, und dort war der Ausweg
-- nicht "die richtige Zahl aufschreiben", sondern ein FERTIGES REZEPT. Also auch hier:
-- wer einen Menue-Bildschirm will, bekommt einen; die Zahlen dahinter stehen an einer
-- Stelle.
--
-- Zwei Abweichungen vom Comic-Bestand sind Absicht:
--
-- Der Schliessen-Knopf ist NICHT mehr rot. Rot ist Danger und bedeutet nach Regel 2 eine
-- Messung -- Schaden, Alarm. Ein Fenster zu schliessen ist keine Gefahr, und ein roter
-- Knopf an dieser Stelle sagt in dieser Sprache etwas Falsches.
--
-- Der Kopf traegt eine Lichtkante nach unten statt eines Rahmens rundherum. Ein Vollbild
-- braucht keine Umrandung -- es gibt nichts, wogegen es sich abgrenzen muesste. Was es
-- braucht, ist eine Trennung zwischen Kopf und Inhalt. Dieselbe Ueberlegung wie beim
-- Sockel des Tachos.
-- ===== Menues haben eine eigene, groessere Schriftskala =====
--
-- Die Groessen des HUDs sind fuer den Blick WAEHREND des Spielens gemacht: kurz hinsehen,
-- ablesen, weiterkaempfen. Dort ist jeder Punkt Schrift auch verlorener Platz, und die
-- Zahlen sind entsprechend knapp.
--
-- Im Menue gilt das Gegenteil. Man steht still, liest ganze Saetze, und Platz ist da --
-- der Bildschirm gehoert dem Menue allein. Dieselben Groessen wirken dort zu klein, und
-- das ist kein Widerspruch, sondern derselbe Massstab auf eine andere Lage angewandt.
HudChrome.MenuTextSize = {
	Title = 30, -- Ueberschrift eines Bildschirms
	Heading = 26, -- Ueberschrift ueber einem Textabschnitt: Role, Strength, Weakness
	Section = 21, -- Zwischenueberschrift, Kartenname
	Body = 18, -- Fliesstext
	Caption = 16, -- Nebenangaben, Unterzeilen
}

-- Fliesstext im Menue: GOTHAM, nicht RobotoMono.
--
-- Im HUD tragen die Unterzeilen RobotoMono, weil Oswald bei 13 Punkt zu schmal wird und
-- eine Schreibmaschinenschrift dort instrumentenhaft wirkt. Im Menue steht kein Instrument,
-- sondern Text, den man Zeile fuer Zeile liest -- und dafuer ist eine proportionale Schrift
-- schlicht besser zu lesen. Die Stilregel sagt das auch so: Gotham fuer Fliesstext.
function HudChrome.MenuBody(textLabel, size)
	textLabel.Font = HudChrome.Font.Body
	textLabel.TextScaled = false
	textLabel.TextSize = size or HudChrome.MenuTextSize.Body
	textLabel.TextWrapped = true
	textLabel.TextColor3 = HudChrome.Color.TextPrimary
	textLabel.TextStrokeTransparency = 1
	return textLabel
end

-- Nebenangabe im Menue: dieselbe Schrift, kleiner und zurueckgenommen.
function HudChrome.MenuCaption(textLabel, size)
	HudChrome.MenuBody(textLabel, size or HudChrome.MenuTextSize.Caption)
	textLabel.TextColor3 = HudChrome.Color.TextSecondary
	return textLabel
end

HudChrome.ScreenHeader = 72

function HudChrome.Screen(parent, options)
	options = options or {}

	local panel = Instance.new("Frame")
	panel.Name = options.name or "MenuScreen"
	panel.Size = UDim2.new(1, 0, 1, 0)
	panel.Position = UDim2.new(0, 0, 0, 0)
	panel.BackgroundColor3 = HudChrome.Color.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent

	local kopf = Instance.new("Frame")
	kopf.Name = "Header"
	kopf.Size = UDim2.new(1, 0, 0, HudChrome.ScreenHeader)
	kopf.BackgroundColor3 = HudChrome.Color.PanelRaised
	kopf.BorderSizePixel = 0
	kopf.ZIndex = 2
	kopf.Parent = panel

	local kante = Instance.new("Frame")
	kante.Name = "HeaderEdge"
	kante.Size = UDim2.new(1, 0, 0, 1)
	kante.Position = UDim2.new(0, 0, 1, -1)
	kante.BackgroundColor3 = HudChrome.Color.BorderBright
	kante.BackgroundTransparency = 0.5
	kante.BorderSizePixel = 0
	kante.ZIndex = 3
	kante.Parent = kopf

	local titel = Instance.new("TextLabel")
	titel.Name = "ScreenTitle"
	titel.Size = UDim2.new(1, -180, 0, 32)
	titel.Position = UDim2.new(0, 24, 0, 10)
	titel.BackgroundTransparency = 1
	titel.TextXAlignment = Enum.TextXAlignment.Left
	titel.Text = options.title or ""
	titel.ZIndex = 3
	titel.Parent = kopf
	HudChrome.Label(titel, HudChrome.MenuTextSize.Title)

	-- Die Unterzeile gehoert zur Stilregel: alles ist zweizeilig beschriftet. Sie steht
	-- auch dann da, wenn der Aufrufer nichts uebergibt -- dann traegt sie spaeter den
	-- Fortschritt oder die Zaehlung, wie im Archiv.
	local unterzeile = Instance.new("TextLabel")
	unterzeile.Name = "ScreenSubtitle"
	unterzeile.Size = UDim2.new(1, -180, 0, 22)
	unterzeile.Position = UDim2.new(0, 24, 0, 44)
	unterzeile.BackgroundTransparency = 1
	unterzeile.TextXAlignment = Enum.TextXAlignment.Left
	unterzeile.Text = options.subtitle or ""
	unterzeile.ZIndex = 3
	unterzeile.Parent = kopf
	HudChrome.MenuCaption(unterzeile)

	local schliessen = Instance.new("TextButton")
	schliessen.Name = "CloseButton"
	schliessen.AnchorPoint = Vector2.new(1, 0.5)
	schliessen.Position = UDim2.new(1, -24, 0.5, 0)
	schliessen.Size = UDim2.new(0, 40, 0, 40)
	schliessen.AutoButtonColor = false
	schliessen.Text = "\u{2715}"
	schliessen.ZIndex = 3
	schliessen.Parent = kopf
	HudChrome.Panel(schliessen, { radius = HudChrome.Radius.Small, fill = HudChrome.Color.Panel })
	HudChrome.Label(schliessen, 22)
	schliessen.TextColor3 = HudChrome.Color.TextSecondary

	-- Der Inhalt liegt UNTER dem Kopf. Dass jeder Aufrufer dafuer die Kopfhoehe von Hand
	-- abzieht, war die haeufigste Abweichung im Bestand -- mal 60, mal 70, mal 80.
	local inhalt = Instance.new("Frame")
	inhalt.Name = "Content"
	inhalt.Position = UDim2.new(0, 0, 0, HudChrome.ScreenHeader)
	inhalt.Size = UDim2.new(1, 0, 1, -HudChrome.ScreenHeader)
	inhalt.BackgroundTransparency = 1
	inhalt.Parent = panel

	return {
		panel = panel,
		header = kopf,
		content = inhalt,
		title = titel,
		subtitle = unterzeile,
		close = schliessen,
	}
end

-- ===== Die untere Reihe =====
--
-- Unten steht der Tacho in der Bildmitte, links und rechts davon die Knoepfe. Sie kommen
-- aus ZWEI Skripten -- die vier Angriffe aus SpecialAttackClient, das Absorbieren aus
-- EnergyAbsorbInputClient -- und standen deshalb nicht in einer Reihe: der Absorb-Knopf
-- schwebte darueber und lag auf dem Trainingsfeld.
--
-- Die Reihenfolge nach aussen hin ist nicht beliebig. Rechts vom Tacho stehen die drei
-- Knoepfe, die die Spezialenergie betreffen -- dieselbe Energie, die der cyanfarbene Bogen
-- am Tacho zeigt: erst der, der sie FUELLT, dann die beiden, die sie ausgeben, der
-- teurere weiter aussen. Links die beiden, die nichts kosten und immer gehen.
HudChrome.Reihe = {
	Breite = 128,
	Hoehe = 104,
	Innen = 210, -- Mitte des innersten Knopfes, Abstand zur Bildmitte
	Abstand = 140, -- Mitte zu Mitte
	Grundlinie = -24, -- Unterkante ueber dem unteren Bildrand
}

-- Mitte des n-ten Knopfes, von der Bildmitte aus gezaehlt. n = 1 steht direkt neben dem
-- Tacho, n = 2 daneben; negatives n ist die linke Seite.
function HudChrome.ReiheX(n)
	local r = HudChrome.Reihe
	local betrag = r.Innen + (math.abs(n) - 1) * r.Abstand
	return n < 0 and -betrag or betrag
end

-- Fertige Lage fuer einen Knopf der Reihe.
function HudChrome.ReihePlatz(n)
	return UDim2.new(0.5, HudChrome.ReiheX(n), 1, HudChrome.Reihe.Grundlinie)
end

-- ===== Der Rand des Geraets =====
--
-- Zwei verschiedene Raender schneiden in ein ScreenGui, und sie werden staendig
-- verwechselt. Auf dem Telefon sind beide sichtbar geworden:
--
--   1. Der SICHERE BEREICH des Geraets -- Aussparung, runde Ecken, Wischbalken. Roblox
--      zieht ihn links und rechts ein. Darum brach die Kopfleiste am Rand ab, und darum
--      endeten die schwarzen Kinobalken vor der Kante.
--   2. Die SYSTEMLEISTE von Roblox oben -- Menue, Chat, Aufnahme. Sie schiebt jedes
--      ScreenGui nach unten.
--
-- `IgnoreGuiInset = true` schaltet nur den zweiten ab, nicht den ersten: es entspricht
-- ScreenInsets = DeviceSafeInsets. Deshalb hilft es einer Flaeche nicht, die bis an die
-- physische Kante reichen soll.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

-- Bis an die physische Kante, ohne jeden Einzug.
--
-- Nur fuer FLAECHEN: Blenden, Balken, Abdunklungen. Nicht fuer Knoepfe und Schrift -- die
-- laegen dann unter der Aussparung. Die Aufteilung ist genau die zwischen dem Grund und
-- dem, was darauf sitzt: der Grund blutet aus, der Inhalt haelt Abstand.
function HudChrome.FullBleed(screenGui)
	-- pcall: ScreenInsets gibt es nicht in jeder Client-Version. Faellt es aus, bleibt es
	-- beim bisherigen Verhalten -- ein Rand ist haesslich, ein Fehler waere schlimmer.
	local ok = pcall(function()
		screenGui.ScreenInsets = Enum.ScreenInsets.None
	end)
	if not ok then
		screenGui.IgnoreGuiInset = true
		warn("[Kaiju Debug] HudChrome: ScreenInsets nicht verfuegbar, die Flaeche haelt am sicheren Bereich.")
	end
	return screenGui
end

-- Der Versatz, den Roblox jedem GEWOEHNLICHEN ScreenGui oben gibt.
--
-- Genau dieser Wert, nicht der gepolsterte aus TopInsetUtils: hier geht es nicht darum,
-- Abstand zur Systemleiste zu halten, sondern darum, sich mit Geschwistern zu decken, die
-- den Versatz bereits bekommen haben.
--
-- ===== Warum GetGuiInset dafuer nicht genuegt =====
-- Es kennt nur die Systemleiste von Roblox. Oben schneidet aber auch der sichere Bereich
-- des Geraets ein, und auf dem Telefon war die Differenz gross genug, dass alles, was
-- damit gerechnet wurde, danebenlag.
--
-- Deshalb wird gemessen. Zwei leere ScreenGuis, eines randlos und eines gewoehnlich: die
-- Differenz ihrer Oberkanten IST der Versatz, ohne jede Annahme darueber, woraus er sich
-- zusammensetzt. Sie kosten nichts -- sie haben keinen Inhalt und zeichnen nichts.
local sondeRandlos, sondeGewoehnlich

local function sondenAnlegen()
	if sondeRandlos then
		return true
	end
	local spieler = Players.LocalPlayer
	local gui = spieler and spieler:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return false -- auf dem Server, oder die PlayerGui steht noch nicht
	end

	sondeRandlos = Instance.new("ScreenGui")
	sondeRandlos.Name = "HudChromeSondeRandlos"
	sondeRandlos.ResetOnSpawn = false
	HudChrome.FullBleed(sondeRandlos)
	sondeRandlos.Parent = gui

	sondeGewoehnlich = Instance.new("ScreenGui")
	sondeGewoehnlich.Name = "HudChromeSondeGewoehnlich"
	sondeGewoehnlich.ResetOnSpawn = false
	sondeGewoehnlich.Parent = gui
	return true
end

function HudChrome.TopInset()
	local gerechnet = GuiService:GetGuiInset().Y
	if not sondenAnlegen() then
		return gerechnet
	end
	local gemessen = sondeGewoehnlich.AbsolutePosition.Y - sondeRandlos.AbsolutePosition.Y
	-- Die Messung kann zu frueh kommen und null melden; dann traegt die Rechnung.
	return math.max(gemessen, gerechnet, 0)
end

-- Ruft `fn(inset)` sofort und bei jeder Aenderung.
--
-- Sofort allein genuegt nicht: beim Start eines LocalScripts steht die Kern-Oberflaeche
-- oft noch nicht, GetGuiInset liefert dann 0, und der Wert bliebe fuer immer falsch. Denselben
-- Fehler gab es im Projekt schon einmal, siehe TopInsetUtils.
function HudChrome.BindTopInset(fn)
	local function anwenden()
		fn(HudChrome.TopInset())
	end

	anwenden()
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(anwenden)
	end)
	if sondeGewoehnlich then
		-- Das Drehen des Telefons aendert den sicheren Bereich, ohne die Systemleiste
		-- anzufassen. Die Sonde merkt das, TopbarInset nicht.
		sondeGewoehnlich:GetPropertyChangedSignal("AbsolutePosition"):Connect(anwenden)
		sondeGewoehnlich:GetPropertyChangedSignal("AbsoluteSize"):Connect(anwenden)
	end
	-- Nachschlag: der erste Aufbau der Kern-Oberflaeche loest nicht auf allen Geraeten ein
	-- Ereignis aus.
	task.delay(2, anwenden)
end

return HudChrome
