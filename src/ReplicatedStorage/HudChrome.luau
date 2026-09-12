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
}

-- Legt ein Symbol an.
--
-- ScaleType.Fit statt des Standards: gestreckte Symbole fallen sofort auf, und ein Bild
-- in einem Kaestchen anderer Seitenverhaeltnisse ist der Normalfall, nicht die Ausnahme.
--
-- `tint` bleibt bewusst optional und ist standardmaessig AUS. Faerben lohnt nur bei
-- einfarbigen Symbolen; traegt das Bild eigene Farben, macht ein Farbton es kaputt. Die
-- Unterscheidung "frei gegen Energie" traegt ohnehin schon der Akzentstreifen.
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
	for name, assetId in pairs(HudChrome.Icon) do
		table.insert(liste, assetId)
		namen[assetId] = name
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
-- Roblox zeichnet keine Vielecke. Der Weg dahin fuehrt ueber einen Farbverlauf: ein
-- UIGradient bildet seine Werte entlang einer gedrehten Achse ab, und ein harter Sprung in
-- der Durchsichtigkeit erzeugt dadurch eine gerade Schnittkante quer durch das Rechteck.
-- Gedreht ist diese Kante schraeg.
--
-- Die Alternative -- ein gedrehtes Rechteck in einem beschneidenden Rahmen -- waere
-- naheliegender gewesen, haengt aber daran, ob ClipsDescendants gedrehte Kinder sauber
-- beschneidet. Der Farbverlauf braucht diese Annahme nicht.
--
-- Wo genau der Schnitt sitzt, folgt aus der Geometrie. Die Achse zeigt in Richtung
-- `winkel`, der Verlauf spannt sich ueber die Projektion des Rechtecks auf diese Achse,
-- und daraus kuerzt sich der Schnittpunkt zu slant / (Breite + slant) -- unabhaengig von
-- der Hoehe, weil der Winkel selbst schon aus Hoehe und Versatz stammt.
--
-- side = "Left": die linke Kante laeuft von oben links nach unten rechts ("\").
-- side = "Right": die rechte Kante laeuft von oben rechts nach unten links ("/").
--
-- Gibt (frame, stroke) zurueck. Achtung beim Fuellen: die abgeschnittene Ecke ist unten
-- aussen, Inhalt braucht dort mindestens `slant` Abstand zum Rand.
function HudChrome.SlantPanel(parent, options)
	options = options or {}
	local width = options.width or 220
	local height = options.height or 62
	local slant = options.slant or 16
	local side = options.side or "Left"

	local frame = Instance.new("Frame")
	frame.Name = options.name or "SlantPanel"
	frame.Size = UDim2.new(0, width, 0, height)
	frame.Parent = parent

	local _, stroke = HudChrome.Panel(frame, {
		radius = options.radius or HudChrome.Radius.Small,
		fill = options.fill,
		transparency = options.transparency,
		border = options.border,
	})

	local winkel = math.deg(math.atan(slant / height))
	local schnitt = math.clamp(slant / (width + slant), 0.01, 0.5)
	-- Bei "Right" zeigt die Achse nach links: dieselbe Neigung, um 180 Grad gedreht.
	local richtung = (side == "Right") and (180 + winkel) or -winkel

	-- Der Sprung von durchsichtig auf deckend ist absichtlich nur einen Tausendstel breit
	-- -- schmal genug, dass er als Kante wirkt, breit genug, dass Roblox ihn glaettet
	-- statt ihn als Treppe zu zeichnen.
	local folge = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(schnitt, 1),
		NumberSequenceKeypoint.new(schnitt + 0.001, 0),
		NumberSequenceKeypoint.new(1, 0),
	})

	local verlauf = Instance.new("UIGradient")
	verlauf.Rotation = richtung
	verlauf.Transparency = folge
	verlauf.Parent = frame

	-- Der Rahmenstrich muss denselben Schnitt bekommen. Sonst zoege er weiter das volle
	-- Rechteck nach -- eine Linie quer durch die Luft neben der schraegen Kante.
	if stroke then
		local strichVerlauf = Instance.new("UIGradient")
		strichVerlauf.Rotation = richtung
		strichVerlauf.Transparency = folge
		strichVerlauf.Parent = stroke
	end

	return frame, stroke
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

return HudChrome
