-- VERSION: 2026-08-25 #3
-- LocalScript: TalentTreeClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt den Diablo-artigen Talentbaum aller drei Fraktionen als verzweigte Baum-Ansicht
-- (Start-Knoten oben, drei Zweige darunter, Cross-Synergie + Ultimate am Ende). Nur
-- Kaijus Knoten haben echte Wirkung (siehe TalentTreeService.lua).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
-- Nur fuer das Forschungsfeld im HUD. Der Talentbaum selbst bleibt vorerst im
-- Comic-Stil -- Menues kommen nach dem HUD dran.
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TalentTreeConfig = require(ReplicatedStorage:WaitForChild("TalentTreeConfig"))
-- Dasselbe Kurzformat wie im ganzen Spiel -- Haeuser-HP, Coins, Schaden, Evolutionspunkte.
-- Eine zweite Rechnung fuer "1.1M" waere die Gelegenheit, dass sie irgendwann anders
-- rundet als die erste.
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))
local StartResearchEvent = RemoteEventUtils.GetOrCreate("StartResearchEvent")
local CancelResearchEvent = RemoteEventUtils.GetOrCreate("CancelResearchEvent")
local ResearchCompleteEvent = RemoteEventUtils.GetOrCreate("ResearchCompleteEvent")
local GetTalentStateFunction = ReplicatedStorage:WaitForChild("GetTalentStateFunction")

-- Farben und Symbole kommen aus HudChrome. Hier standen eigene Kopien -- bei Heat mit einer
-- anderen Farbe als im Rest des Spiels -- und drei Emoji fuer die Figuren.
local ENERGY_COLORS = HudChrome.EnergyColor

local FACTION_TABS = {
	{ key = "Kaiju", label = "Kaiju" },
	{ key = "Jaeger", label = "Jaeger" },
	{ key = "Ronin", label = "Ronin" },
}

-- Bild wenn hochgeladen, sonst das Zeichen aus dem Config.
--
-- Beide sitzen an derselben Stelle und in derselben Groesse, damit der Wechsel nichts
-- verschiebt -- dieselbe Ausweichregel wie bei den Energien und den Geschenken. Solange
-- Jaeger und Ronin nur Vorschau sind, tragen ihre Knoten weiterhin Zeichen; das ist kein
-- Zwischenzustand, sondern der ehrliche Stand.
-- Bild oder Schriftzeichen -- je nachdem, ob es fuer dieses Talent schon ein Symbol gibt.
--
-- WICHTIG: die beiden muessen GESCHWISTER sein. Die Funktion blendet das Textfeld aus,
-- wenn ein Bild da ist; liegt das Bild IM Textfeld, verschwindet es mit. Genau so war der
-- Kasten in der Detailtafel unsichtbar -- und zwar erst, seit alle dreizehn Talente ein
-- Bild haben: solange zwei davon noch auf das Schriftzeichen fielen, waren ausgerechnet
-- die beiden zu sehen.
local function zeigeTalentSymbol(bildLabel, textLabel, talent)
	local bildId = HudChrome.TalentIcon[talent.id] or ""
	if bildId ~= "" then
		bildLabel.Image = bildId
		bildLabel.Visible = true
		textLabel.Visible = false
	else
		bildLabel.Visible = false
		textLabel.Text = talent.icon
		textLabel.Visible = true
	end
end

-- Fuer RichText: darin steht Farbe als Hexzeichenkette, nicht als Color3. Damit laesst
-- sich EIN Textfeld zweifarbig setzen -- der bezahlbare Teil des Preises normal, der
-- fehlende rot.
local function alsHex(farbe)
	return string.format("%02X%02X%02X",
		math.floor(farbe.R * 255 + 0.5),
		math.floor(farbe.G * 255 + 0.5),
		math.floor(farbe.B * 255 + 0.5))
end

local function formatDuration(seconds)
	seconds = math.max(math.floor(seconds), 0)
	if seconds >= 3600 then
		return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
	elseif seconds >= 60 then
		return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
	end
	return seconds .. "s"
end

local screenGui = Instance.new("ScreenGui")
screenGui.IgnoreGuiInset = true
screenGui.Name = "TalentTreeGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- WICHTIG: hoher DisplayOrder sorgt dafür, dass dieses GUI immer ÜBER anderen ScreenGuis
-- liegt (z.B. den Angriffs-Buttons) -- unabhängig davon, welches Script zuerst lädt.
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

local schirm = HudChrome.Screen(screenGui, {
	name = "TalentTreePanel",
	title = "TALENTS",
	subtitle = "",
})
local panel = schirm.panel

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(panel)

-- ===== Fraktions-Tabs =====
-- In der Kopfzeile, mittig -- wie im Skin-Laden. Es sind dieselben drei Figuren, und sie
-- sollen dort dasselbe tun und gleich aussehen.
local tabRow = Instance.new("Frame")
tabRow.AnchorPoint = Vector2.new(0.5, 0.5)
tabRow.Position = UDim2.new(0.5, 0, 0.5, 0)
tabRow.Size = UDim2.new(0, 3 * 44 + 2 * 8, 0, 44)
tabRow.BackgroundTransparency = 1
tabRow.ZIndex = 4
tabRow.Parent = schirm.header

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabRow

-- ===== Ressourcen-Leiste (5 Energien + Coins) =====
local resourceRow = Instance.new("Frame")
resourceRow.Size = UDim2.new(1, -24, 0, 28)
resourceRow.Position = UDim2.new(0, 12, 0, 8)
resourceRow.BackgroundTransparency = 1
resourceRow.Parent = schirm.content

local resourceLayout = Instance.new("UIListLayout")
resourceLayout.FillDirection = Enum.FillDirection.Horizontal
resourceLayout.Padding = UDim.new(0, 8)
resourceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
resourceLayout.Parent = resourceRow

-- ===== Die Ressourcen sind Chips, keine Liste =====
--
-- Sechs Zahlen in festen 96-Pixel-Faechern, eine neben der anderen, alle in voller Laenge:
-- "1116075  13061  68080  0  86190  323589". Das las sich wie eine Debug-Ausgabe, und die
-- Faecher standen halb leer, wenn eine Energie bei null war.
--
-- Jetzt traegt jede Ressource ihren eigenen kleinen Kasten, der sich um seinen Inhalt legt
-- statt ihn auf eine feste Breite zu strecken. Und die Zahl steht kurz: was hier zaehlt,
-- ist die Groessenordnung -- reicht es fuer den naechsten Knoten? -- und nicht die
-- Einerstelle.
--
-- Bild und Zahl bleiben getrennte Felder, nicht beides in einer Zeichenkette. Ein Emoji im
-- Text sitzt auf der Grundlinie und ist je nach Geraet verschieden breit -- die Zahl sprang
-- dadurch von Energie zu Energie.
local resourceLabels = {}
local function baueRessource(bildId, farbe)
	local chip = Instance.new("Frame")
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.new(0, 0, 1, 0)
	chip.BackgroundTransparency = 1
	chip.Parent = resourceRow
	HudChrome.Panel(chip, {
		radius = HudChrome.Radius.Small,
		fill = HudChrome.Color.PanelSunken,
		transparency = 0.2,
	})

	local polster = Instance.new("UIPadding")
	polster.PaddingLeft = UDim.new(0, 8)
	polster.PaddingRight = UDim.new(0, 10)
	polster.Parent = chip

	local innen = Instance.new("UIListLayout")
	innen.FillDirection = Enum.FillDirection.Horizontal
	innen.VerticalAlignment = Enum.VerticalAlignment.Center
	innen.SortOrder = Enum.SortOrder.LayoutOrder
	innen.Padding = UDim.new(0, 6)
	innen.Parent = chip

	local bild = HudChrome.IconImage(chip, bildId or "")
	bild.Size = UDim2.new(0, 18, 0, 18)
	bild.LayoutOrder = 1
	bild.Visible = (bildId or "") ~= ""

	local zahl = Instance.new("TextLabel")
	zahl.AutomaticSize = Enum.AutomaticSize.X
	zahl.Size = UDim2.new(0, 0, 1, 0)
	zahl.LayoutOrder = 2
	zahl.BackgroundTransparency = 1
	zahl.TextXAlignment = Enum.TextXAlignment.Left
	zahl.Text = "0"
	zahl.Parent = chip
	HudChrome.Number(zahl, 16)
	zahl.TextColor3 = farbe
	return zahl, chip
end

-- Die Kaesten werden mitgemerkt: wenn eine Forschung an einer Ressource scheitert, faerbt
-- sich genau ihr Rand rot. Der Hinweis steht damit DORT, wo der Spieler den Vorrat sieht,
-- und nicht nur unten am Knopf.
local resourceChips = {}
for _, energyType in ipairs(TalentTreeConfig.EnergyOrder) do
	resourceLabels[energyType], resourceChips[energyType] = baueRessource(
		HudChrome.EnergyIcon[energyType],
		ENERGY_COLORS[energyType] or HudChrome.Color.TextPrimary
	)
end
local coinsLabel, coinsChip = baueRessource(HudChrome.Icon.Coin, Color3.fromRGB(255, 205, 60))

-- Rot heisst hier: DARAN liegt es. Kein Alarm, sondern eine Messung -- deshalb der Rand
-- und nicht die Flaeche, wie ueberall sonst in diesem Baukasten.
local function markiereFehlbetrag(chip, knapp)
	local strich = chip:FindFirstChildOfClass("UIStroke")
	if strich then
		strich.Color = knapp and HudChrome.Color.Danger or HudChrome.Color.Border
		strich.Thickness = knapp and 2 or HudChrome.BorderThickness
	end
end

local function zeigeFehlbetraege(fehlend)
	for energyType, chip in pairs(resourceChips) do
		markiereFehlbetrag(chip, fehlend ~= nil and fehlend[energyType] ~= nil)
	end
	markiereFehlbetrag(coinsChip, fehlend ~= nil and fehlend.Coins ~= nil)
end

-- ===== Aktive Forschung: Fortschrittsbalken + Abbrechen-Button =====
local researchBar = Instance.new("Frame")
researchBar.Size = UDim2.new(1, -24, 0, 34)
researchBar.Position = UDim2.new(0, 12, 0, 44)
researchBar.Visible = false
researchBar.Parent = schirm.content
HudChrome.Panel(researchBar, { radius = HudChrome.Radius.Small, fill = HudChrome.Color.PanelSunken })

-- Fortschritts-Füllung: wächst von links nach rechts, je näher die Forschung am Ende ist.
local researchProgressFill = Instance.new("Frame")
researchProgressFill.Size = UDim2.new(0, 0, 1, 0)
researchProgressFill.BackgroundColor3 = HudChrome.Color.Ready
researchProgressFill.BackgroundTransparency = 0.7
researchProgressFill.BorderSizePixel = 0
researchProgressFill.ZIndex = 1
researchProgressFill.Parent = researchBar
local researchProgressFillCorner = Instance.new("UICorner")
researchProgressFillCorner.CornerRadius = UDim.new(0, HudChrome.Radius.Small)
researchProgressFillCorner.Parent = researchProgressFill

local researchLabel = Instance.new("TextLabel")
researchLabel.Size = UDim2.new(1, -100, 1, 0)
researchLabel.Position = UDim2.new(0, 10, 0, 0)
researchLabel.BackgroundTransparency = 1
researchLabel.TextXAlignment = Enum.TextXAlignment.Left
researchLabel.Text = ""
researchLabel.ZIndex = 2
researchLabel.Parent = researchBar
HudChrome.Label(researchLabel, HudChrome.MenuTextSize.Caption)

local cancelResearchButton = Instance.new("TextButton")
cancelResearchButton.Size = UDim2.new(0, 80, 0, 22)
cancelResearchButton.AnchorPoint = Vector2.new(1, 0.5)
cancelResearchButton.Position = UDim2.new(1, -8, 0.5, 0)
cancelResearchButton.AutoButtonColor = false
cancelResearchButton.Text = "CANCEL"
cancelResearchButton.ZIndex = 2
cancelResearchButton.Parent = researchBar
-- Der Abbruch traegt seinen Rand in Danger und nicht die ganze Flaeche. Rot heisst hier
-- wirklich etwas -- eine laufende Forschung verwerfen --, aber es ist ein Rand, kein Alarm.
local _, cancelStroke = HudChrome.Panel(cancelResearchButton, {
	radius = HudChrome.Radius.Small,
	fill = HudChrome.Color.Panel,
})
cancelStroke.Color = HudChrome.Color.Danger
HudChrome.Label(cancelResearchButton, 14)
cancelResearchButton.TextColor3 = HudChrome.Color.Danger
cancelResearchButton.MouseButton1Click:Connect(function()
	CancelResearchEvent:FireServer()
end)

-- ===== Baum-Bereich (scrollbar, absolute Positionierung nach Tier/Zweig) =====
local treeScroll = Instance.new("ScrollingFrame")
-- Siehe Untergrund: ein Anfangsmass, das die Flaeche fuellt, statt eines festen Kastens.
treeScroll.Size = UDim2.new(1, -2 * 8, 1, -106 - 8)
treeScroll.Position = UDim2.new(0, 8, 0, 106)
-- Der Grund liegt jetzt eine Ebene tiefer (siehe Uhrwerk weiter unten) und scheint
-- durch. Der Rahmen bleibt hier, er gehoert zum Fenster und nicht zum Grund.
treeScroll.BackgroundTransparency = 1
treeScroll.BorderSizePixel = 0
treeScroll.ZIndex = 1
-- Rollen ausdruecklich einschalten und sichtbar machen. Beides sind zwar die Vorgaben --
-- aber wenn der Baum groesser ist als sein Fenster, ist der Balken das EINZIGE, woran man
-- sieht, dass es unten weitergeht. Auf dem Telefon ist das der Normalfall.
treeScroll.ScrollingEnabled = true
treeScroll.ScrollingDirection = Enum.ScrollingDirection.XY
treeScroll.ScrollBarThickness = 8
treeScroll.ScrollBarImageColor3 = HudChrome.Color.BorderBright
treeScroll.ScrollBarImageTransparency = 0.4
-- Die Groesse der Zeichenflaeche wird GEMESSEN, nicht gerechnet: sie ist die
-- AbsoluteSize der Leinwand. Warum das eindeutig ist, steht bei der Leinwand weiter unten.
treeScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
-- WICHTIG: ScrollingFrame clippt seinen Inhalt NICHT automatisch (anders als man
-- erwarten würde) -- ohne das hier explizit zu setzen, konnten Verbindungslinien über
-- den Fensterrand hinausragen und sogar das restliche HUD überlagern.
treeScroll.ClipsDescendants = true
treeScroll.Parent = schirm.content
-- Kein Rahmen mehr: der Rollbereich umschliesst seit der Zentrierung nur noch den Baum
-- selbst und ist nicht mehr das Fenster. Der Rahmen gehoert zum Fenster -- er sitzt
-- deshalb am Untergrund.
HudChrome.Panel(treeScroll, { radius = HudChrome.Radius.Panel, fill = false, border = false })

-- ===== Der Faecher: die Masse =====
--
-- BREITER ALS HOCH, und zwar bewusst. Die Zeichenflaeche war quadratisch; der Platz, den
-- sie bekommt, ist es nie: neben ihr steht immer die Detailspalte, und was uebrig bleibt,
-- ist breit und flach. Ein quadratischer Inhalt in einem breiten Platz wird von der HOEHE
-- begrenzt und laesst die Breite liegen -- auf einem grossen Monitor blieb links und
-- rechts fast ein Drittel ungenutzt.
--
-- 1180x820 ist das Ergebnis davon, die HOEHE zu straffen -- denn sie ist es, die bindet.
-- Der Platz neben der Detailspalte ist breit und flach; jede Zeile, die die Flaeche hoeher
-- macht, macht den ganzen Baum kleiner, waehrend Breite gratis ist.
--
-- Gestrafft wurde da, wo Hoehe fuer NAMEN reserviert war:
--   Der Name der Krone tritt zur SEITE, statt unter ihr zu stehen. Oben neben ihr ist die
--   Flaeche leer, und damit faellt der grosse Abstand zwischen Stufe 3 und Krone weg -- er
--   war nur da, weil dort zwei Namen uebereinander passen mussten (244 Einheiten, jetzt 186).
--   Die Stufen ruecken enger: 150/285/420 statt 180/340/500.
--
-- Der Faecher geht dafuer auf 66 Grad auf und nutzt die gewonnene Breite.
--
-- Die Kreise im Hintergrund bleiben trotzdem Kreise -- das Uhrwerk hat seine eigene,
-- quadratische Kantenlaenge und haengt nicht an der Flaeche.
local TREE_CANVAS_WIDTH = 1180
local TREE_CANVAS_HEIGHT = 820

-- Die Wurzel sitzt UNTEN, auf 6 Uhr. Von dort faechert der Baum nach oben auf, und die
-- Krone ist die Spitze auf 12 Uhr. Alle Radien zaehlen ab der Wurzel, nicht ab der Mitte
-- der Flaeche -- der Faecher ist der Mittelpunkt, nicht das Bild.
--
-- Die Zahlen sind nachgerechnet, nicht geschaetzt: ein Pruefskript ueber der echten Config
-- stellt fuer alle drei Fraktionen sicher, dass kein Knoten aus der Flaeche laeuft und
-- zwischen zwei Raendern ueberall mindestens 16 Pixel Luft bleiben.
local FAECHER_WURZEL = Vector2.new(TREE_CANVAS_WIDTH / 2, 686)
local FAECHER_RADIUS = { [0] = 0, [1] = 150, [2] = 285, [3] = 420, [4] = 606 }
local FAECHER_RADIUS_BRUECKE = 352 -- zwischen Stufe 2 und 3
local FAECHER_WINKEL = 66 -- Grad, die ein Zweig neben der Senkrechten liegt

-- Alle diese Zahlen kommen aus dem Pruefskript ueber der echten Config und nicht aus dem
-- Gefuehl: kein Knoten und kein dauerhafter Name laeuft aus der Flaeche, keine zwei Raender
-- kommen sich naeher als 16 Pixel, und das in allen drei Fraktionen.

-- Grad ab der Senkrechten nach oben. Das Minus, weil Y auf dem Bildschirm nach unten
-- waechst, 12 Uhr aber nach oben zeigt.
local function faecherRichtung(grad)
	local bogen = math.rad(grad)
	return Vector2.new(math.sin(bogen), -math.cos(bogen))
end

-- ===== Die Leinwand =====
--
-- Alles, was gezeichnet wird, haengt hier drin und nicht direkt im Rollbereich. Sie loest
-- zwei Dinge, an denen ich mich nacheinander verrechnet habe.
--
-- Ob ein UIScale IM Rollbereich dessen CanvasSize mitskaliert oder nicht, habe ich zweimal
-- geraten und beide Male anders -- einmal war der Inhalt zu klein fuer seinen Rahmen,
-- einmal die Flaeche zu gross fuer das Fenster. Die Leinwand macht die Frage gegenstandslos:
-- der Massstab sitzt an IHR, der Rollbereich sieht nur noch ein Kind mit einer fertigen
-- Groesse, und die wird gemessen (leinwand.AbsoluteSize) statt gerechnet.
--
-- Sie schneidet dabei NICHTS ab. Das Uhrwerk ist mit Absicht groesser als sie -- ein
-- Mechanismus, der ueber den Rand hinauslaeuft -- und vor allem liegt sein Mittelpunkt auf
-- der Wurzel: die Wurzel IST die Mitte der Uhr. Wuerde die Leinwand an ihrer Unterkante
-- abschneiden, waere von der Uhr nur die obere Haelfte da, und die Wurzel saehe aus, als
-- saesse sie unten am Rand statt im Zentrum. Abgeschnitten wird erst am Fenster.
local leinwand = Instance.new("Frame")
leinwand.Name = "Leinwand"
leinwand.Size = UDim2.new(0, TREE_CANVAS_WIDTH, 0, TREE_CANVAS_HEIGHT)
leinwand.BackgroundTransparency = 1
leinwand.Parent = treeScroll

-- Skaliert ALLE Knoten, Linien und das Uhrwerk gemeinsam. Sie stehen auf festen
-- Koordinaten der Zeichenflaeche -- ohne diesen Faktor sah ein Telefon davon nur einen
-- Ausschnitt, und ein grosser Monitor liess den Rest der Flaeche leer.
local treeScale = Instance.new("UIScale")
treeScale.Scale = 1
treeScale.Parent = leinwand

-- ===== Der Grund: ein Uhrwerk =====
--
-- Der Baum stand auf Schwarz. Schwarz ist kein Ort: es gibt nichts, wogegen der dunkle
-- Grundpfad der Adern steht, und nichts, was den Rollbereich als Raum lesbar macht.
--
-- Was hier liegt, ist bewusst KEIN Dekor aus dem Fundus. Trenchborn ist eine
-- Uhrenkollektion -- ein Zifferblattkranz mit seiner Minuterie, konzentrische Ringe und
-- ein Zahnkranz sind die Bildsprache dieser Sammlung. Und sie passen zu dem, was der
-- Bildschirm tut: eine Forschung LAEUFT, sie dauert, sie ist ein Uhrwerk. Die organischen
-- Adern des Baums wachsen darueber hinweg.
--
-- Alles liegt dicht am Grundton (8,9,12). Es soll den Raum haben, nicht ihn einnehmen --
-- wer es beim Spielen bemerkt, hat es zu hell.
local WERK_RING = Color3.fromRGB(23, 27, 35)
local WERK_STRICH = Color3.fromRGB(31, 37, 47)
local WERK_HELL = Color3.fromRGB(44, 52, 64)

-- Der GRUND der Flaeche. Er bleibt eine Ebene ueber dem Panel und rollt nicht mit; das
-- Werk selbst liegt seit dem Faecher IM Baum (siehe unten).
local himmel = Instance.new("Frame")
himmel.Name = "Untergrund"
-- Anfangsmass, das die Flaeche schon FUELLT. layoutColumns setzt es gleich richtig -- aber
-- wenn dieser Durchlauf einmal nicht greift, ist der Unterschied zwischen "etwas zu breit"
-- und dem Vorgabewert eines Frames (100x100) der zwischen "sieht komisch aus" und "der
-- halbe Bildschirm fehlt".
himmel.Size = UDim2.new(1, -2 * 8, 1, -106 - 8)
himmel.Position = UDim2.new(0, 8, 0, 106)
himmel.BackgroundColor3 = HudChrome.Color.PanelSunken
himmel.BorderSizePixel = 0
himmel.ZIndex = 0
himmel.Parent = schirm.content
HudChrome.Panel(himmel, {
	radius = HudChrome.Radius.Panel,
	fill = HudChrome.Color.PanelSunken,
	transparency = 0,
})

-- ===== Das Werk sitzt auf der WURZEL =====
--
-- Zuerst lag es in der Bildmitte und ging beim Rollen langsamer mit -- Parallaxe, zwei
-- Ebenen mit Abstand. Das war huebsch und ging an der Sache vorbei: die Stufen des
-- Faechers sind Boegen um die Wurzel, und wenn die Ringe des Zifferblatts um einen ANDEREN
-- Punkt liegen, schneiden sie diese Boegen irgendwo schief. Dann ist die Uhr Tapete.
--
-- Jetzt teilen sie einen Mittelpunkt: das Werk liegt IM Baum, auf der Wurzel, und jede
-- Stufe des Faechers sitzt auf einem Ring des Zifferblatts. Damit skaliert und rollt es
-- mit dem Baum mit -- die Parallaxe ist dafuer weg. Ein Bild, das zusammenpasst, ist mehr
-- wert als zwei, die sich gegeneinander verschieben.
--
-- Die Kantenlaenge ist fest in Baum-Koordinaten: doppelter Kronenradius plus etwas Luft.
local WERK_SEITE = 2 * FAECHER_RADIUS[4] + 160

local werk = Instance.new("Frame")
werk.Name = "Werk"
werk.AnchorPoint = Vector2.new(0.5, 0.5)
werk.Position = UDim2.new(0, FAECHER_WURZEL.X, 0, FAECHER_WURZEL.Y)
werk.Size = UDim2.new(0, WERK_SEITE, 0, WERK_SEITE)
werk.BackgroundTransparency = 1
werk.ZIndex = 50 -- unter den Adern (58/59) und den Knoten (62)
werk.Parent = leinwand

-- Alle Masse hier stehen in BAUM-Koordinaten -- demselben Radius, mit dem auch die Knoten
-- gesetzt werden. Umgerechnet wird an genau einer Stelle.
local function anteil(radius)
	return (radius * 2) / WERK_SEITE
end

local function baueRing(radius, farbe, transparenz, dicke)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0.5, 0)
	ring.Size = UDim2.new(anteil(radius), 0, anteil(radius), 0)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 50
	ring.Parent = werk
	local ecke = Instance.new("UICorner")
	ecke.CornerRadius = UDim.new(0.5, 0)
	ecke.Parent = ring
	local strich = Instance.new("UIStroke")
	strich.Thickness = dicke
	strich.Color = farbe
	strich.Transparency = transparenz
	strich.Parent = ring
end

-- Striche auf einem Kreis. Minuterie, Zahnkranz und Teilung sind dieselbe Bewegung mit
-- anderen Zahlen -- deshalb EINE Funktion statt dreier.
--
-- Rotation = Winkel + 90: die lange Achse eines Frames ist seine Hoehe, also Y. Die
-- Vierteldrehung legt sie auf den Radius, und der Strich zeigt nach aussen statt quer.
local function baueKranz(radius, anzahl, laenge, breite, farbe, transparenz, jeder)
	local r = anteil(radius) / 2
	for i = 0, anzahl - 1 do
		local winkel = (i / anzahl) * math.pi * 2
		local betont = jeder ~= nil and (i % jeder == 0)
		local strich = Instance.new("Frame")
		strich.AnchorPoint = Vector2.new(0.5, 0.5)
		strich.Position = UDim2.new(
			0.5 + r * math.cos(winkel), 0,
			0.5 + r * math.sin(winkel), 0
		)
		strich.Size = UDim2.new(anteil(breite), 0, anteil(betont and laenge * 1.9 or laenge), 0)
		strich.Rotation = math.deg(winkel) + 90
		strich.BackgroundColor3 = betont and WERK_HELL or farbe
		strich.BackgroundTransparency = transparenz
		strich.BorderSizePixel = 0
		strich.ZIndex = 50
		strich.Parent = werk
	end
end

-- Jede Stufe des Faechers bekommt ihren Ring. Das ist der ganze Punkt: die Knoten stehen
-- nicht VOR einer Uhr, sie stehen AUF ihren Teilungen.
baueRing(FAECHER_RADIUS[1], WERK_RING, 0.55, 1)
baueRing(FAECHER_RADIUS[2], WERK_RING, 0.5, 1)
baueRing(FAECHER_RADIUS[3], WERK_RING, 0.45, 1)

-- Der Kronenring ist der aeussere Rand des Zifferblatts, mit seiner Minuterie dicht
-- darunter: jeder fuenfte Strich laenger und heller -- die Teilung einer Uhr, nicht die
-- eines Diagramms. Die Krone auf 12 Uhr sitzt genau darauf.
baueRing(FAECHER_RADIUS[4], WERK_RING, 0.25, 2)
baueKranz(FAECHER_RADIUS[4] - 34, 60, 28, 4, WERK_STRICH, 0.35, 5)

-- Das Getriebe sitzt auf dem Ring der zweiten Stufe.
baueKranz(FAECHER_RADIUS[2], 28, 44, 22, WERK_RING, 0.55)

-- Um die Wurzel die Lagerung: eine Teilung und zwei enge Ringe.
baueKranz(140, 12, 90, 5, WERK_STRICH, 0.6)
baueRing(96, WERK_RING, 0.5, 1)
baueRing(74, WERK_RING, 0.35, 2)

-- Baum und Detailspalte teilen sich die Breite. Beide standen vorher auf festen Werten
-- (960 und 268 Pixel ab Position 8 beziehungsweise 976). Auf einem Vollbild-Bildschirm
-- blieb dadurch rechts ein Drittel der Flaeche leer, waehrend die Textspalte auf 268 Pixel
-- eingeengt war -- der Text darin brach nach zwei, drei Woertern um.
--
-- Der Baum hatte danach eine Hoechstbreite von 960 Pixeln, mit der Begruendung, ihn zu
-- dehnen erzeuge nur Leerraum im Rollbereich -- er ist ja mit festen Koordinaten auf einer
-- 960x900-Flaeche aufgebaut. Das stimmte, solange er nicht skaliert wurde. Seit er das
-- wird (treeScale weiter unten), bekommt er den ganzen Rest der Breite, und der Block
-- steht nicht mehr mittig, sondern fuellt die Flaeche.
local DETAIL_MIN_WIDTH = 300
local DETAIL_MAX_WIDTH = 520
local COLUMN_GAP = 8

-- ===== Telefon im Querformat =====
-- Die Detailspalte bleibt IMMER rechts. Auf dem Telefon wird im Querformat gespielt: dort
-- ist die Breite reichlich und die HOEHE knapp -- Baum und Details uebereinander zu
-- stapeln wuerde genau die knappe Groesse verbrauchen.
--
-- Stattdessen zwei Stellschrauben. Erstens darf die Detailspalte auf schmalen Geraeten
-- schmaler werden als die 300 Pixel, die sie am Monitor mindestens bekommt -- feste 300
-- von 640 sind fast die halbe Flaeche. Zweitens wird der Baum SKALIERT statt
-- abgeschnitten: seine Knoten stehen auf festen Koordinaten einer 960x900-Flaeche, und
-- ohne Skalierung sah ein Telefon davon 316 mal 254 Pixel, also ein Achtel.
local DETAIL_WIDTH_FRACTION = 0.3
local DETAIL_MIN_FRACTION = 0.32 -- so viel darf die Detailspalte hoechstens vom Bildschirm nehmen

-- Grenzen der Baum-Skalierung. Nach unten, damit die Beschriftung lesbar bleibt -- lieber
-- rollen als eine unleserliche Uebersicht. Nach oben, damit auf einem grossen Monitor
-- keine handtellergrossen Knoten entstehen.
-- ===== Der Mindestmassstab haengt davon ab, WOMIT gezeigt wird =====
--
-- Er war eine feste Zahl, und das war der Fehler: 0.45, gewaehlt fuer den Finger, damit ein
-- gewoehnlicher Knoten 36 Pixel gross bleibt und noch zu treffen ist. Am Monitor hat diese
-- Untergrenze dann den Baum abgeschnitten, sobald das Fenster kleiner wurde -- unten fehlte
-- der Faecher, obwohl ringsum Platz war. Eine Grenze fuer den Finger, die dem Mauszeiger
-- etwas wegnimmt.
--
-- Mit der Maus darf er schrumpfen, bis er passt: ein 22 Pixel grosser Knoten ist mit einem
-- Zeiger muehelos zu treffen, und GANZ zu sehen ist mehr wert als gross. Mit dem Finger
-- bleibt es bei 0.45 -- dort passt der Faecher dann nicht ins Bild, und das ist in Ordnung,
-- solange der Blick an der richtigen Stelle anfaengt. Er faengt bei der Wurzel an (siehe
-- blickAufWurzel), und von dort schiebt man sich nach oben zur Krone. Die Reise von 6 nach
-- 12 wird so zu der Bewegung, die der Finger ohnehin macht.
local function mindestMassstab()
	local nurFinger = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return nurFinger and 0.45 or 0.22
end
local TREE_MAX_SCALE = 1.5

-- Oberkante des Inhalts, unter Titelzeile und Ressourcenleiste.
-- Oberkante des Inhalts. Zwei Werte, weil der Forschungsbalken nur dasteht, wenn wirklich
-- geforscht wird -- und das ist die Ausnahme. Ihm dauerhaft 58 Pixel freizuhalten, kostete
-- den Baum ein Fuenftel seiner Hoehe fuer eine leere Zeile.
local CONTENT_TOP_MIT_FORSCHUNG = 106
local CONTENT_TOP_OHNE = 48

-- ===== Detail-Panel: zeigt das AUSGEWÄHLTE Talent -- Icon/Name, Beschreibung, Kosten,
-- Forschungszeit, und einen "Vorher -> Nachher"-Wertevergleich. =====
local detailPanel = Instance.new("Frame")
detailPanel.Size = UDim2.new(0, 268, 1, -104)
detailPanel.Position = UDim2.new(0, 980, 0, 88)
detailPanel.Parent = schirm.content
HudChrome.Panel(detailPanel, {
	radius = HudChrome.Radius.Panel,
	fill = HudChrome.Color.PanelRaised,
	transparency = 0,
})

-- Flaeche, die den Kindern des Panels tatsaechlich zur Verfuegung steht.
--
-- AbsoluteSize ist die Groesse des Panels SELBST. TopInsetUtils legt darauf ein UIPadding
-- (48 Pixel oben fuer die Roblox-Systemleiste, 8 unten), und Kinder beginnen erst
-- darunter. Wer mit AbsoluteSize rechnet und Hoehen als festen Versatz setzt, baut ein
-- Kind, das 56 Pixel zu hoch ist -- es reicht unter den Bildschirmrand, und alles, was an
-- seiner Unterkante haengt, verschwindet.
--
-- Genau so ist der Research-Knopf verschwunden. Vorher waren die Hoehen skalenbasiert
-- (1, -110) und haben das Polster deshalb von selbst beruecksichtigt; beim Umbau auf feste
-- Hoehen -- die der Baum fuer seine Skalierung braucht -- ging das verloren.
local function contentSize()
	-- MESSEN, nicht rechnen -- und zwar an der Flaeche, in der die Kinder tatsaechlich
	-- haengen. Beide Spalten liegen in schirm.content, und dessen AbsoluteSize hat das
	-- Polster von TopInsetUtils UND die Kopfzeile schon abgezogen; Roblox rechnet das von
	-- selbst, weil content ein Kind des gepolsterten Panels ist.
	--
	-- Vorher stand hier die Groesse des PANELS, das Polster von Hand nachgerechnet -- die
	-- Kopfhoehe aber nicht. Beide Spalten waren dadurch 72 Pixel zu hoch und ragten unten
	-- aus dem Bild; der Research-Knopf haengt an ihrer Unterkante und stand damit
	-- ausserhalb des Bildschirms. Dass eine Hoehe aus zwei Quellen zusammengerechnet wird,
	-- war hier schon einmal der Fehler (siehe Kommentar oben am Detail-Panel).
	return schirm.content.AbsoluteSize.X, schirm.content.AbsoluteSize.Y
end

-- Damit ein Durchlauf, der NICHT greift, sichtbar wird statt still zu bleiben. Genau das
-- war der Fall, in dem der Bildschirm nur einen Bruchteil des Platzes einnahm: die
-- Anordnung stieg wegen einer Groesse von null oben aus, und danach meldete AbsoluteSize
-- nichts mehr, weil sich nichts mehr aenderte.
local letzteMassmeldung = ""

local function meldeMass(breite, hoehe)
	local meldung = string.format("%dx%d", breite, hoehe)
	if meldung == letzteMassmeldung then
		return
	end
	letzteMassmeldung = meldung
	if breite <= 0 or hoehe <= 0 then
		warn("[Kaiju Debug] Talentbaum: Inhaltsflaeche misst " .. meldung
			.. " -- die Anordnung laeuft nicht. Sie wird beim Oeffnen wiederholt.")
	else
		print("[Kaiju Debug] Talentbaum: Inhaltsflaeche " .. meldung)
	end
end

-- Vorwaerts deklariert: layoutColumns ruft passeFensterAn, das ruft blickAufWurzel -- und
-- ein Name, der erst danach entsteht, loest in Lua still auf eine globale nil auf.
local blickAufWurzel
local passeFensterAn

-- ===== Der Blick faengt bei der Wurzel an =====
--
-- Und zwar ERST IM NAECHSTEN BILD. Roblox begrenzt CanvasPosition sofort auf das, was der
-- Rollbereich GERADE noch hergibt -- setzt man sie im selben Durchlauf, in dem auch Size
-- und CanvasSize neu gesetzt wurden, wird sie gegen die ALTEN Masse beschnitten. Beim
-- Wechsel der Bildschirmgroesse landete der Baum dadurch irgendwo: mal beim Endknoten, mal
-- dazwischen, und der Wurzelknoten war nicht mehr zu sehen.
--
-- Gemessen wird deshalb an AbsoluteWindowSize -- der Flaeche, die der Rollbereich
-- tatsaechlich zeigt, ohne den Rollbalken. Gerechnet mit fensterHoehe waere wieder eine
-- Zahl aus zweiter Hand.
local letzteBlickmeldung = ""

-- Was die Anordnung im ersten Durchgang ausgerechnet hat. Der zweite braucht es wieder.
local letzterPlatz = nil

function passeFensterAn()
	task.defer(function()
		local platz = letzterPlatz
		if not platz then
			return
		end

		-- DIE Messung. Die Leinwand traegt den Massstab; ihre AbsoluteSize ist damit die
		-- fertige Groesse in Pixeln, von Roblox gerechnet. Der Rollbereich bekommt genau
		-- diese Zahl als Flaeche. Alles, was ich hier selbst gerechnet haette, waere wieder
		-- eine Annahme darueber, wie UIScale und CanvasSize zusammenwirken -- und genau die
		-- war zweimal falsch.
		local flaeche = leinwand.AbsoluteSize
		if flaeche.X <= 0 or flaeche.Y <= 0 then
			return
		end
		local fensterBreite = math.min(platz.platzBreite, math.ceil(flaeche.X))
		local fensterHoehe = math.min(platz.platzHoehe, math.ceil(flaeche.Y))

		-- ===== Auslauf, damit die Wurzel in die Mitte kann =====
		--
		-- Die Wurzel ist der MITTELPUNKT DER UHR, und der Ausschnitt soll sie zeigen -- man
		-- faengt dort an und schiebt sich von da in jede Richtung zu der Stelle, an der man
		-- forschen will. Sie liegt auf der Zeichenflaeche aber weit unten, und Roblox
		-- begrenzt den Rollweg auf die Flaeche: ohne Weg unter ihr laesst sie sich gar
		-- nicht bis in die Mitte schieben, sie bliebe an der Unterkante haengen.
		--
		-- Also ein halbes Fenster Auslauf -- aber NUR, wenn ohnehin gerollt wird. Passt
		-- alles ins Bild, gaebe der Auslauf einen Rollbereich, wo es nichts zu rollen gibt.
		local auslaufY = (math.ceil(flaeche.Y) > fensterHoehe) and math.floor(fensterHoehe / 2) or 0
		treeScroll.CanvasSize = UDim2.new(
			0, math.ceil(flaeche.X),
			0, math.ceil(flaeche.Y) + auslaufY
		)

		-- Fenster und Detailspalte werden als EIN Block zentriert. Der uebrige Platz liegt
		-- damit aussen als Rand und nicht innen als Loch.
		local blockBreite = fensterBreite + COLUMN_GAP + platz.detailWidth
		local blockX = math.max(COLUMN_GAP, math.floor((platz.breite - blockBreite) / 2))
		local baumY = platz.oben + math.floor((platz.platzHoehe - fensterHoehe) / 2)

		himmel.Position = UDim2.new(0, blockX, 0, baumY)
		himmel.Size = UDim2.new(0, fensterBreite, 0, fensterHoehe)
		treeScroll.Position = UDim2.new(0, blockX, 0, baumY)
		treeScroll.Size = UDim2.new(0, fensterBreite, 0, fensterHoehe)

		-- Die Detailspalte behaelt die VOLLE Hoehe. Sie ist eine Textspalte -- sie mit dem
		-- Baumfenster mitschrumpfen zu lassen, verschenkte genau den Platz, den die
		-- Beschreibung und der Forschungsknopf brauchen.
		detailPanel.Position = UDim2.new(0, blockX + fensterBreite + COLUMN_GAP, 0, platz.oben)
		detailPanel.Size = UDim2.new(0, platz.detailWidth, 0, platz.platzHoehe)

		blickAufWurzel()
	end)
end

function blickAufWurzel()
	task.defer(function()
		local fenster = treeScroll.AbsoluteWindowSize
		if fenster.X <= 0 or fenster.Y <= 0 then
			return
		end
		-- Gerechnet wird in ANTEILEN der Zeichenflaeche und umgelegt auf die Flaeche, die
		-- der Rollbereich wirklich hat (AbsoluteCanvasSize). Damit ist es gleichgueltig, ob
		-- und wie oft ein Massstab dazwischensteht -- genau der Punkt, an dem es vorher
		-- schiefging.
		local flaeche = treeScroll.AbsoluteCanvasSize
		-- Die Wurzel in die MITTE des Ausschnitts, waagerecht wie senkrecht. Vorher sass
		-- sie an der Unterkante -- da, wo sie auch auf der Zeichenflaeche steht. Von einem
		-- unteren Rand aus kann man aber nur in eine Richtung weiter, und genau das ist
		-- beim Suchen falsch: man faengt bei der Wurzel an und will von dort in JEDE
		-- Richtung an die Stelle, an der man forschen moechte.
		local anteilX = FAECHER_WURZEL.X / TREE_CANVAS_WIDTH
		local anteilY = FAECHER_WURZEL.Y / TREE_CANVAS_HEIGHT
		treeScroll.CanvasPosition = Vector2.new(
			math.max(0, flaeche.X * anteilX - fenster.X / 2),
			math.max(0, flaeche.Y * anteilY - fenster.Y / 2)
		)

		local meldung = string.format(
			"[Kaiju Debug] Talentbaum: Massstab %.2f, Fenster %dx%d, Flaeche %dx%d, Blick %d/%d",
			treeScale.Scale, fenster.X, fenster.Y, flaeche.X, flaeche.Y,
			treeScroll.CanvasPosition.X, treeScroll.CanvasPosition.Y)
		-- Nur bei Aenderung ausgeben: waehrend man ein Fenster zieht, laeuft die Anordnung
		-- in jedem Bild, und eine Zeile je Bild macht die Ausgabe unlesbar.
		if meldung ~= letzteBlickmeldung then
			letzteBlickmeldung = meldung
			print(meldung)
		end
	end)
end

-- Kopfbereich und beide Spalten neu setzen, sobald sich die Fenstergroesse aendert.
local function layoutColumns()
	local width, height = contentSize()
	meldeMass(width, height)
	if width <= 0 or height <= 0 then
		return
	end

	-- Die Tab-Reihe wird hier NICHT mehr angefasst. Sie stand einmal rechts neben einem
	-- Titel, der im Inhalt lag, und richtete sich an dessen Breite aus. Seit dem Umbau auf
	-- HudChrome.Screen steht der Titel in der Kopfzeile -- die Rechnung zog die Reihe
	-- seither an den linken Rand und ueber den Titel, auf dem Telefon besonders deutlich.
	--
	-- Sie ist bei ihrer Erzeugung mittig in der Kopfzeile verankert, und genau da gehoert
	-- sie hin: drei gleich grosse Symbolknoepfe, die fuer die drei Figuren stehen. Ihre
	-- Breite ist fest (3 mal 44 plus zwei Luecken) und braucht keine Anpassung.
	-- Die Ressourcenzeile gehoert nach GANZ oben, nicht auf 44: dort sitzt der
	-- Forschungsbalken, und beide lagen uebereinander -- die Zahlen ueber dem Balken, der
	-- CANCEL-Knopf unter den Zahlen. Die 44 stammen aus der Zeit, als der Titel noch hier
	-- im Inhalt stand; seit HudChrome.Screen steht er in der Kopfzeile, und die Zeile
	-- darunter ist frei geworden. Die drei Hoehen gehen jetzt sauber auf:
	-- Ressourcen 8..38, Forschung 44..78, Inhalt ab 106.
	resourceRow.Position = UDim2.new(0, 12, 0, 8)

	-- Die Detailspalte bleibt rechts, darf aber nie mehr als DETAIL_MIN_FRACTION des
	-- Bildschirms beanspruchen: feste 300 Pixel waeren auf einem 640er Telefon fast die
	-- halbe Flaeche.
	local detailFloor = math.min(DETAIL_MIN_WIDTH, math.floor(width * DETAIL_MIN_FRACTION))
	local detailWidth = math.clamp(
		math.floor(width * DETAIL_WIDTH_FRACTION),
		detailFloor,
		DETAIL_MAX_WIDTH
	)

	-- Der PLATZ, der zur Verfuegung steht -- nicht schon die Groesse des Fensters. Wie
	-- gross das Fenster wirklich wird, entscheidet sich weiter unten, wenn der Massstab
	-- feststeht.
	local platzBreite = math.max(width - detailWidth - 3 * COLUMN_GAP, 160)
	local oben = researchBar.Visible and CONTENT_TOP_MIT_FORSCHUNG or CONTENT_TOP_OHNE
	local platzHoehe = math.max(height - oben - COLUMN_GAP, 120)

	-- ===== Der Massstab kommt aus der BREITE =====
	--
	-- Er kam bisher aus beidem, und die Hoehe gewann immer: der Platz neben der
	-- Detailspalte ist breit und flach. Das hatte zwei Folgen, die beide stoerten. Der Baum
	-- blieb kleiner, als er haette sein koennen -- und weil damit alles ins Bild passte,
	-- gab es nichts zu rollen, und die Wurzel konnte gar nicht in die Mitte des
	-- Ausschnitts wandern: sie sass da, wo sie auf der Zeichenflaeche sitzt, also weit
	-- unten.
	--
	-- Jetzt gibt die Breite den Massstab, und senkrecht wird gerollt. Der Baum wird dadurch
	-- deutlich groesser, das Fenster fuellt den Platz in beide Richtungen aus, und die
	-- Wurzel steht beim Oeffnen in der Mitte -- von dort schiebt man sich nach oben zur
	-- Krone.
	--
	-- Die zweite Zahl ist keine Anpassung an die Hoehe, sondern eine Grenze fuer den
	-- Rollweg: hoechstens anderthalb Bildhoehen. Ohne sie koennte der Baum auf einem sehr
	-- breiten, flachen Fenster so gross werden, dass man ihn nur noch abfaehrt.
	local ROLL_SPIELRAUM = 1.5
	local scale = math.clamp(
		math.min(
			platzBreite / TREE_CANVAS_WIDTH,
			(platzHoehe * ROLL_SPIELRAUM) / TREE_CANVAS_HEIGHT
		),
		mindestMassstab(),
		TREE_MAX_SCALE
	)
	treeScale.Scale = scale
	leinwand.Size = UDim2.new(0, TREE_CANVAS_WIDTH, 0, TREE_CANVAS_HEIGHT)

	-- Vorlaeufige Lage: das Fenster bekommt erst einmal den ganzen Platz. Die endgueltige
	-- Groesse setzt passeFensterAn, sobald Roblox die Flaeche gerechnet hat -- der Aufruf
	-- steht unten.
	himmel.Position = UDim2.new(0, COLUMN_GAP, 0, oben)
	himmel.Size = UDim2.new(0, platzBreite, 0, platzHoehe)
	treeScroll.Position = UDim2.new(0, COLUMN_GAP, 0, oben)
	treeScroll.Size = UDim2.new(0, platzBreite, 0, platzHoehe)

	letzterPlatz = {
		breite = width,
		platzBreite = platzBreite,
		platzHoehe = platzHoehe,
		detailWidth = detailWidth,
		oben = oben,
	}

	passeFensterAn()
end

-- Auf BEIDE hoeren. Gemessen wird an schirm.content -- und dessen Groesse aendert sich
-- nicht nur mit dem Panel, sondern auch, wenn TopInsetUtils das Polster nachzieht. Am
-- Panel allein waere die Meldung dann ausgeblieben.
panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutColumns)
schirm.content:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutColumns)
-- Der Forschungsbalken bestimmt die Oberkante des Inhalts mit. Erscheint oder verschwindet
-- er, muss der Baum darunter neu gesetzt werden -- sonst behaelt er die Hoehe des anderen
-- Zustands und ragt entweder in den Balken oder laesst dessen Zeile leer stehen.
researchBar:GetPropertyChangedSignal("Visible"):Connect(layoutColumns)

-- Auch auf das Polster hören, nicht nur auf die Fenstergrösse. TopInsetUtils liest die
-- Höhe der Roblox-Systemleiste nicht nur einmal, sondern zieht sie nach -- bei jeder
-- Änderung der Leiste und zusätzlich zeitversetzt, weil sie beim Start noch null meldet.
-- Wenn sich dabei das Polster ändert, bleibt AbsoluteSize gleich; ohne diese Verbindung
-- rechnete die Anordnung weiter mit dem alten Wert und die Detailspalte stünde wieder ein
-- Stück zu tief.
local panelPadding = panel:FindFirstChildOfClass("UIPadding")
if panelPadding then
	panelPadding:GetPropertyChangedSignal("PaddingTop"):Connect(layoutColumns)
	panelPadding:GetPropertyChangedSignal("PaddingBottom"):Connect(layoutColumns)
end

layoutColumns()
-- Und gleich nochmal im naechsten Bild. Beim Laden kann schirm.content noch keine Groesse
-- haben -- dann steigt layoutColumns oben aus, und AbsoluteSize meldet spaeter NICHTS
-- mehr, weil sich danach nichts mehr aendert. Der Baum bliebe dann fuer immer in seinem
-- Anfangszustand stehen: Massstab 1 auf einer Flaeche, die dafuer zu klein ist -- man saehe
-- die obere linke Ecke, also die Krone, und kaeme nicht an die Wurzel.
task.defer(layoutColumns)

-- ===== Die Detailtafel rollt =====
--
-- Auf dem Telefon ist die Spalte so niedrig, dass Beschreibung, Werte, Kosten und
-- Forschungszeit nicht mehr uebereinander passen -- sie liefen in den Forschungsknopf
-- hinein und ueberlagerten ihn. Der Knopf ist aber das, was man hier TUT; er darf nie
-- verdeckt sein und nie weggescrollt werden koennen.
--
-- Also die Teilung: der Text rollt, der Knopf steht fest an der Unterkante. Das ist auch
-- auf einem grossen Bildschirm richtig -- dort gibt es einfach nichts zu rollen.
-- Unten steht, was man TUT, und darueber eine Zeile, wie lange es dauert. Beides rollt
-- nicht mit -- der Knopf ist das Ziel dieses Bildschirms.
local DETAIL_KNOPF_ZONE = 88
local DETAIL_RAND = 12
-- Wie hoch der Inhalt ist, rechnet Roblox aus -- dieselbe Lehre wie beim Baum. Und es
-- rechnet dabei nur mit dem, was SICHTBAR ist: solange kein Talent gewaehlt ist, steht dort
-- ein einziger Satz, und dann gibt es auch nichts zu rollen.

local detailScroll = Instance.new("ScrollingFrame")
detailScroll.Name = "DetailInhalt"
detailScroll.Position = UDim2.new(0, 0, 0, 0)
detailScroll.Size = UDim2.new(1, 0, 1, -DETAIL_KNOPF_ZONE)
detailScroll.BackgroundTransparency = 1
detailScroll.BorderSizePixel = 0
detailScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
detailScroll.ScrollingDirection = Enum.ScrollingDirection.Y
detailScroll.ScrollBarThickness = 6
detailScroll.ScrollBarImageColor3 = HudChrome.Color.BorderBright
detailScroll.ScrollBarImageTransparency = 0.4
detailScroll.ClipsDescendants = true
detailScroll.Parent = detailPanel

local detailEmpty = Instance.new("TextLabel")
detailEmpty.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, 80)
detailEmpty.Position = UDim2.new(0, DETAIL_RAND, 0, 20)
detailEmpty.BackgroundTransparency = 1
detailEmpty.TextColor3 = Color3.fromRGB(140, 140, 150)
detailEmpty.Text = "👆 Pick a talent to see its details."
HudChrome.MenuBody(detailEmpty)
detailEmpty.TextXAlignment = Enum.TextXAlignment.Left
detailEmpty.TextYAlignment = Enum.TextYAlignment.Top
detailEmpty.TextWrapped = true
detailEmpty.Parent = detailScroll

-- ===== Die Detailtafel =====
--
-- Sie war eine Liste aus acht Zeilen Text mit zwei gelben Ueberschriften -- die Werte als
-- "Total Damage: 120 -> 150" mitten im Fliesstext, die Kosten als eigener Abschnitt
-- darunter. Das liest sich wie eine Ausgabe, nicht wie ein Angebot.
--
-- Jetzt drei Teile mit klarer Rangfolge:
--   OBEN    wer es ist -- grosses Symbol, Name, Stufe
--   MITTE   was es tut -- der Wert VORHER und NACHHER, gross, mit einem Pfeil dazwischen
--   UNTEN   was es kostet -- im Knopf selbst, denn dort wird es bezahlt
--
-- Die Beschreibung rutscht dabei nach unten. Sie erklaert, der Zahlenvergleich ueberzeugt
-- -- und ueberzeugen ist die Aufgabe dieses Bildschirms.
local detailIconBild = Instance.new("ImageLabel")

local detailIcon = Instance.new("TextLabel")
detailIcon.Size = UDim2.new(0, 88, 0, 88)
detailIcon.Position = UDim2.new(0, DETAIL_RAND, 0, DETAIL_RAND)
-- Der Kasten traegt nur noch Rahmen und Grund. Sein eigener Text bleibt leer -- das
-- Schriftzeichen steht in detailIconText darin.
detailIcon.Text = ""
detailIcon.Visible = false
detailIcon.Parent = detailScroll
HudChrome.Panel(detailIcon, {
	radius = HudChrome.Radius.Panel,
	fill = HudChrome.Color.PanelSunken,
	transparency = 0,
})

-- Das Bild liegt IM Kaestchen, nicht daneben: das Kaestchen traegt Rahmen und Grund, und
-- die beiden Sorten Symbol teilen es sich.
detailIconBild.Name = "DetailIconImage"
detailIconBild.Size = UDim2.new(1, -10, 1, -10)
detailIconBild.Position = UDim2.new(0, 5, 0, 5)
detailIconBild.BackgroundTransparency = 1
detailIconBild.ScaleType = Enum.ScaleType.Fit
detailIconBild.Visible = false
detailIconBild.Parent = detailIcon

-- Das Schriftzeichen bekommt ein EIGENES Feld im Kasten, neben dem Bild. Vorher trug der
-- Kasten selbst den Text -- und wurde damit zu dem Feld, das zeigeTalentSymbol ausblendet.
local detailIconText = Instance.new("TextLabel")
detailIconText.Name = "DetailIconText"
detailIconText.Size = UDim2.new(1, -10, 1, -10)
detailIconText.Position = UDim2.new(0, 5, 0, 5)
detailIconText.BackgroundTransparency = 1
detailIconText.TextScaled = true
detailIconText.Text = ""
detailIconText.Visible = false
detailIconText.Parent = detailIcon

-- ===== Name und Stufe stehen NEBEN dem Symbol =====
--
-- Sie standen schon einmal hier und sind zwischendurch darunter gewandert, weil sie
-- "verschoben" wirkten: eingerueckt auf x112, waehrend alles darunter bei x12 beginnt.
--
-- Der Grund war ein anderer. Der Symbolkasten war unsichtbar (siehe zeigeTalentSymbol) --
-- neben NICHTS eingerueckt zu stehen sieht aus wie ein Fehler, neben einem 88 Pixel
-- grossen Symbol wie eine Zeile. Sichtbar ist der Kasten die linke Kante dieser beiden
-- Zeilen, und sie fluchten mit ihm statt mit der Spalte darunter.
--
-- Der Name bekommt dafuer zwei Zeilen und eine Stufe kleiner als die Ueberschrift: neben
-- dem Symbol bleiben auf dem Telefon nur rund 160 Pixel, und "BATTLEFIELD CONTROL"
-- braucht sie beide. Abgeschnitten waere schlimmer als kleiner.
local detailName = Instance.new("TextLabel")
detailName.Size = UDim2.new(1, -112 - DETAIL_RAND, 0, 48)
detailName.Position = UDim2.new(0, 112, 0, 16)
detailName.BackgroundTransparency = 1
HudChrome.Label(detailName, HudChrome.MenuTextSize.Section)
detailName.TextYAlignment = Enum.TextYAlignment.Top
detailName.TextXAlignment = Enum.TextXAlignment.Left
detailName.TextColor3 = Color3.new(1, 1, 1)
detailName.TextWrapped = true
detailName.Text = ""
detailName.Visible = false
detailName.Parent = detailScroll

local detailLevel = Instance.new("TextLabel")
detailLevel.Size = UDim2.new(1, -112 - DETAIL_RAND, 0, 20)
detailLevel.Position = UDim2.new(0, 112, 0, 66)
detailLevel.BackgroundTransparency = 1
HudChrome.Sublabel(detailLevel, 14)
detailLevel.TextXAlignment = Enum.TextXAlignment.Left
detailLevel.Text = ""
detailLevel.Visible = false
detailLevel.Parent = detailScroll

-- Eine Trennlinie statt einer Ueberschrift. Eine Ueberschrift wie "STATS" benennt nur,
-- was ohnehin dasteht; ein Strich sagt dasselbe ohne ein Wort.
local function baueTrenner()
	local strich = Instance.new("Frame")
	strich.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, 1)
	strich.BackgroundColor3 = HudChrome.Color.BorderDim
	strich.BorderSizePixel = 0
	strich.Visible = false
	strich.Parent = detailScroll
	return strich
end

local detailTrennerEins = baueTrenner()
detailTrennerEins.Position = UDim2.new(0, DETAIL_RAND, 0, 114)

-- ===== Vorher -> Nachher =====
--
-- Der Kern der Tafel: der Wert von heute, ein Pfeil, der Wert danach.
--
-- Die drei stehen nicht in festen Spalten, sondern FLIESSEN von links -- wie alles andere
-- in dieser Tafel. In Spalten mit einem Pfeil in der Mitte richtete sich der Vergleich an
-- einer eingebildeten Mittellinie aus, die sonst nirgends vorkommt; jetzt beginnt er an
-- derselben Kante wie Name, Ueberschrift und Beschreibung. Dass die Zahlen dabei
-- unterschiedlich lang sind, stoert nicht -- sie haben eine gemeinsame linke Kante.
local function baueVergleich(zahlGroesse)
	local reihe = Instance.new("Frame")
	reihe.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, zahlGroesse + 14)
	reihe.BackgroundTransparency = 1
	reihe.Visible = false
	reihe.Parent = detailScroll

	local fluss = Instance.new("UIListLayout")
	fluss.FillDirection = Enum.FillDirection.Horizontal
	fluss.HorizontalAlignment = Enum.HorizontalAlignment.Left
	fluss.VerticalAlignment = Enum.VerticalAlignment.Center
	fluss.SortOrder = Enum.SortOrder.LayoutOrder
	fluss.Padding = UDim.new(0, 10)
	fluss.Parent = reihe

	local function baueZahl(ordnung, groesse, farbe, text)
		local feld = Instance.new("TextLabel")
		feld.AutomaticSize = Enum.AutomaticSize.X
		feld.Size = UDim2.new(0, 0, 1, 0)
		feld.LayoutOrder = ordnung
		feld.BackgroundTransparency = 1
		HudChrome.Number(feld, groesse)
		feld.TextXAlignment = Enum.TextXAlignment.Left
		feld.TextColor3 = farbe
		feld.Text = text
		feld.Parent = reihe
		return feld
	end

	local vorher = baueZahl(1, zahlGroesse, HudChrome.Color.TextDim, "")
	local pfeil = baueZahl(2, zahlGroesse - 4, HudChrome.Color.TextDim, "→")
	local nachher = baueZahl(3, zahlGroesse, HudChrome.Color.TextPrimary, "")

	return reihe, vorher, pfeil, nachher
end

local detailWirkungKopf = Instance.new("TextLabel")
detailWirkungKopf.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, 18)
detailWirkungKopf.Position = UDim2.new(0, DETAIL_RAND, 0, 126)
detailWirkungKopf.BackgroundTransparency = 1
HudChrome.Sublabel(detailWirkungKopf, 13)
detailWirkungKopf.TextXAlignment = Enum.TextXAlignment.Left
detailWirkungKopf.Text = ""
detailWirkungKopf.Visible = false
detailWirkungKopf.Parent = detailScroll

local detailWirkungReihe, detailWirkungVorher, detailWirkungPfeil, detailWirkungNachher =
	baueVergleich(HudChrome.TextSize.NumberLarge)
detailWirkungReihe.Position = UDim2.new(0, DETAIL_RAND, 0, 146)

local detailTradeoffKopf = Instance.new("TextLabel")
detailTradeoffKopf.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, 18)
detailTradeoffKopf.BackgroundTransparency = 1
HudChrome.Sublabel(detailTradeoffKopf, 13)
detailTradeoffKopf.TextXAlignment = Enum.TextXAlignment.Left
detailTradeoffKopf.TextColor3 = Color3.fromRGB(230, 140, 40)
detailTradeoffKopf.Text = ""
detailTradeoffKopf.Visible = false
detailTradeoffKopf.Parent = detailScroll

local detailTradeoffReihe, detailTradeoffVorher, _detailTradeoffPfeil, detailTradeoffNachher =
	baueVergleich(HudChrome.TextSize.Number)
detailTradeoffNachher.TextColor3 = Color3.fromRGB(230, 140, 40)

local detailTrennerZwei = baueTrenner()

local detailDescription = Instance.new("TextLabel")
detailDescription.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, 104)
detailDescription.BackgroundTransparency = 1
HudChrome.MenuBody(detailDescription)
detailDescription.TextXAlignment = Enum.TextXAlignment.Left
detailDescription.TextYAlignment = Enum.TextYAlignment.Top
detailDescription.TextWrapped = true
detailDescription.TextColor3 = HudChrome.Color.TextSecondary
detailDescription.Text = ""
detailDescription.Visible = false
detailDescription.Parent = detailScroll

local detailPrereqLabel = Instance.new("TextLabel")
detailPrereqLabel.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, 44)
detailPrereqLabel.BackgroundTransparency = 1
HudChrome.MenuBody(detailPrereqLabel, 16)
detailPrereqLabel.TextWrapped = true
detailPrereqLabel.TextXAlignment = Enum.TextXAlignment.Left
detailPrereqLabel.TextYAlignment = Enum.TextYAlignment.Top
detailPrereqLabel.TextColor3 = HudChrome.Color.Danger
detailPrereqLabel.Text = ""
detailPrereqLabel.Visible = false
detailPrereqLabel.Parent = detailScroll

-- Der untere Teil steht nicht fest: ohne Trade-off faellt ein ganzer Block weg, und die
-- Beschreibung darf dann nachruecken. Ein Loch, wo nichts steht, sieht aus wie ein Fehler.
local function ordneDetailInhalt(mitTradeoff)
	local y = 196
	if mitTradeoff then
		detailTradeoffKopf.Position = UDim2.new(0, DETAIL_RAND, 0, y)
		detailTradeoffReihe.Position = UDim2.new(0, DETAIL_RAND, 0, y + 20)
		y += 62
	end
	detailTrennerZwei.Position = UDim2.new(0, DETAIL_RAND, 0, y + 6)
	detailDescription.Position = UDim2.new(0, DETAIL_RAND, 0, y + 18)
	detailPrereqLabel.Position = UDim2.new(0, DETAIL_RAND, 0, y + 18 + 104 + 8)
end

-- Die Forschungszeit ist Nebensache und steht deshalb klein ueber dem Knopf -- nicht als
-- eigene Zeile mitten im Text, wo sie mit den Werten um Aufmerksamkeit konkurrierte.
local detailResearchTime = Instance.new("TextLabel")
detailResearchTime.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, 18)
detailResearchTime.Position = UDim2.new(0, DETAIL_RAND, 1, -84)
detailResearchTime.BackgroundTransparency = 1
HudChrome.Sublabel(detailResearchTime, 13)
detailResearchTime.TextXAlignment = Enum.TextXAlignment.Left
detailResearchTime.Text = ""
detailResearchTime.Visible = false
detailResearchTime.Parent = detailPanel

local detailResearchButton = Instance.new("TextButton")
detailResearchButton.Size = UDim2.new(1, -2 * DETAIL_RAND, 0, 54)
detailResearchButton.Position = UDim2.new(0, DETAIL_RAND, 1, -62)
detailResearchButton.AutoButtonColor = false
detailResearchButton.Text = ""
detailResearchButton.Visible = false
detailResearchButton.Parent = detailPanel
HudChrome.Panel(detailResearchButton, { radius = HudChrome.Radius.Small })

-- Zwei Zeilen im Knopf: WAS passiert, und WAS es kostet. Die Kosten gehoeren hierher und
-- nicht in einen eigenen Abschnitt weiter oben -- bezahlt wird beim Druecken, und wer
-- drueckt, schaut auf den Knopf.
-- Auch im Knopf linksbuendig, und zwar auf DERSELBEN Kante wie Name, Ueberschrift und
-- Beschreibung darueber. Ein zentrierter Knopftext waere fuer sich genommen richtig -- in
-- einer Spalte, in der jede andere Zeile links beginnt, ist er die einzige Ausnahme, und
-- Ausnahmen sieht man.
local KNOPF_RAND = 16

local knopfHaupt = Instance.new("TextLabel")
knopfHaupt.Size = UDim2.new(1, -2 * KNOPF_RAND, 0, 26)
knopfHaupt.Position = UDim2.new(0, KNOPF_RAND, 0, 7)
knopfHaupt.BackgroundTransparency = 1
HudChrome.Label(knopfHaupt, 20)
knopfHaupt.TextXAlignment = Enum.TextXAlignment.Left
knopfHaupt.TextColor3 = Color3.new(1, 1, 1)
knopfHaupt.Text = ""
knopfHaupt.Parent = detailResearchButton

local knopfKosten = Instance.new("TextLabel")
knopfKosten.Size = UDim2.new(1, -2 * KNOPF_RAND, 0, 18)
knopfKosten.Position = UDim2.new(0, KNOPF_RAND, 0, 32)
knopfKosten.BackgroundTransparency = 1
HudChrome.Number(knopfKosten, 15)
knopfKosten.TextXAlignment = Enum.TextXAlignment.Left
knopfKosten.Text = ""
knopfKosten.Parent = detailResearchButton

local closeButton = schirm.close
closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
	-- Kehrt zum Hamburger-Menü zurück (ersetzt den früheren separaten "← Back"-Button).
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	end
end)

-- ===== Zustand =====
local talentState = { levels = { Kaiju = {}, Jaeger = {}, Ronin = {} }, energy = {}, coins = 0, research = nil }

-- ===== Lesbare Namen + Formatierung für die Effekt-Schlüssel aus der Config =====
local STAT_LABELS = {
	RootDamageBonus = "Total Damage",
	UltimateDamageBonus = "Total Damage",
	BerserkerDamageBonus = "Berserker Damage Bonus",
	OverheatDamageBonus = "Berserker Damage Bonus",
	BerserkerThresholdPenalty = "Berserker Threshold (higher = harder to trigger)",
	MeltdownAttackSpeedBonus = "Meltdown Attack Speed",
	CooldownReduction = "Ability Cooldown Reduction",
	FocusDamageBonus = "Focus Attack Damage",
	FocusRangePenalty = "Focus Attack Range (lower = shorter)",
	ComboChainEnabled = "Combo Chain",
	AreaRadiusBonus = "Area Attack Radius",
	BlastRadiusBonus = "Area Attack Radius",
	AreaDamagePenalty = "Area Damage per Hit (lower = weaker)",
	CataclysmEnabled = "Cataclysm (every 4th hit)",
	HeatScaledAreaDamage = "Area Damage (scales with Heat, max)",
}

local function formatStatValue(effectKey, value)
	if effectKey == "ComboChainEnabled" or effectKey == "CataclysmEnabled" then
		return value > 0 and "Enabled" or "Disabled"
	end
	return string.format("%+.0f%%", value * 100)
end

-- Summiert den aktuellen Gesamtwert eines Effekt-Schlüssels über ALLE Knoten einer
-- Fraktion (optional mit einem simulierten "was wäre, wenn ich noch 1 Stufe hätte"-Stand).
local function getEffectTotal(factionName, effectKey, levelsOverride)
	local levels = levelsOverride or talentState.levels[factionName] or {}
	local total = 0
	for _, t in ipairs(TalentTreeConfig.GetTalentsForFaction(factionName)) do
		local level = levels[t.id] or 0
		if level > 0 then
			if t.effectKey == effectKey then
				total += level * t.effectPerLevel
			end
			if t.tradeoffEffectKey == effectKey then
				total += level * t.tradeoffEffectPerLevel
			end
		end
	end
	return total
end

local selectedTalentId = nil
local currentFaction = "Kaiju"
local nodeRefs = {}

local function requestState()
	local ok, result = pcall(function()
		return GetTalentStateFunction:InvokeServer()
	end)
	if ok and result then
		talentState = result
	end
end

local function updateResourceDisplay()
	for _, energyType in ipairs(TalentTreeConfig.EnergyOrder) do
		resourceLabels[energyType].Text = NumberFormat.Format(math.floor(talentState.energy[energyType] or 0))
	end
	coinsLabel.Text = NumberFormat.Format(math.floor(talentState.coins or 0))
end

-- ===== Der Baum ist ein Faecher von 6 nach 12 =====
--
-- Zuerst standen die Knoten in drei Spalten untereinander -- ein Talentbaum, wie ihn jedes
-- Rollenspiel hat. Dann lag die Wurzel im Zentrum der Scheibe und die Zweige zeigten auf
-- 3, 6 und 9 Uhr; das nutzte zwar die Form, aber der Bogen von 6 Uhr zur Krone lief quer
-- durch die Mitte und sah nach Versehen aus.
--
-- Jetzt:
--   die WURZEL sitzt unten auf 6 Uhr
--   drei Strahlen FAECHERN nach oben auf   (36 Grad neben der Senkrechten)
--   der RADIUS sagt, wie tief man ist      (Stufe 1 innen, Stufe 3 aussen)
--   die KRONE ist die Spitze auf 12 Uhr
--
-- Damit ist jede Stufe ein Bogen um die Wurzel -- und weil das Zifferblatt seinen
-- Mittelpunkt ebenfalls auf der Wurzel hat, ist jeder dieser Boegen einer seiner Ringe.
-- Nichts kreuzt, und die Richtung ist auf einen Blick lesbar: von unten nach oben.

-- ===== Zweig-Reihenfolge wird DYNAMISCH aus den Knoten abgeleitet (funktioniert für jede
-- Fraktion, unabhängig von den Zweig-Namen). =====
local function getBranchAngles(nodes)
	local order = {}
	local seen = {}
	local EXCLUDED_BRANCHES = { Root = true, Synergy = true, Ultimate = true, Gap1_2 = true, Gap2_3 = true }
	for _, node in ipairs(nodes) do
		if not EXCLUDED_BRANCHES[node.branch] and not seen[node.branch] then
			seen[node.branch] = true
			table.insert(order, node.branch)
		end
	end
	-- Der mittlere Zweig steht senkrecht, die beiden anderen 36 Grad daneben. Der Faecher
	-- ist damit 72 Grad weit -- breiter laufen die aeusseren Stufe-3-Knoten seitlich aus
	-- der Flaeche, schmaler draengt sich der Faecher zu einer Saeule zusammen.
	local winkel = {}
	for i, branchKey in ipairs(order) do
		winkel[branchKey] = (i - 2) * FAECHER_WINKEL
	end
	return winkel, order
end

local GAP_BRANCHES = { Gap1_2 = true, Gap2_3 = true, Synergy = true } -- "Synergy" bleibt als Alias erhalten, falls irgendwo noch verwendet

local function getNodePosition(node, branchAngles, branchOrder)
	-- Die Wurzel IST der Ursprung des Faechers. Kein Radius, kein Winkel.
	if node.branch == "Root" then
		return FAECHER_WURZEL
	end

	-- Die Krone senkrecht ueber der Wurzel, am weitesten aussen -- 12 Uhr. Sie gehoert
	-- allen drei Zweigen und darf deshalb an keinem von ihnen haengen.
	if node.branch == "Ultimate" then
		return FAECHER_WURZEL + faecherRichtung(0) * FAECHER_RADIUS[4]
	end

	-- Die Bruecken liegen ZWISCHEN zwei Zweigen -- also auf dem halben Winkel dazwischen,
	-- und auf halbem Radius zwischen Stufe 2 und 3. Genau da, wo sie im Baum stehen.
	if GAP_BRANCHES[node.branch] then
		local ersterZweig, zweiterZweig
		if node.branch == "Gap2_3" then
			ersterZweig, zweiterZweig = branchOrder[2], branchOrder[3]
		else
			ersterZweig, zweiterZweig = branchOrder[1], branchOrder[2]
		end
		local a = branchAngles[ersterZweig]
		local b = branchAngles[zweiterZweig]
		local grad = (a and b) and (a + b) / 2 or 0
		return FAECHER_WURZEL + faecherRichtung(grad) * FAECHER_RADIUS_BRUECKE
	end

	local grad = branchAngles[node.branch] or 0
	local radius = FAECHER_RADIUS[node.tier] or FAECHER_RADIUS[1]
	return FAECHER_WURZEL + faecherRichtung(grad) * radius
end

-- ===== Rang: nicht jeder Knoten wiegt gleich viel =====
--
-- Dreizehn gleich grosse Kreise sind eine Liste, kein Baum -- man sieht nicht, wo er
-- anfaengt, wo er hinfuehrt und was unterwegs ein Meilenstein ist.
--
-- Der Rang steht nirgends in der Config, und er muss es auch nicht: er STECKT schon in der
-- Stufe. Abgeleitet statt eingetragen gilt er fuer Jaeger und Ronin ohne Zutun mit, denn
-- deren Baeume sind nach demselben Muster gebaut.
--
--   Stufe 0 und 4   Wurzel und Ultimate -- Anfang und Ende des GANZEN Baums
--   Stufe 3         das Ende eines Zweigs, die Synergie, auf die er hinauslaeuft
--   dazwischen      die Arbeitstiere: Einstieg, Trade-off, die beiden Bruecken
--
-- Das Symbol behaelt dabei sein Verhaeltnis zum Kreis (0.77). Mehr geht nicht: ein Quadrat
-- ueber Durchmesser/Wurzel(2) steht mit den Ecken ueber den Ring hinaus -- 0.77 traegt sich
-- nur, weil die Symbole selbst einen Rand mitbringen.
local RANG_NORMAL = { durchmesser = 80, namenHoehe = 30, namenBreite = 150, namenFarbe = Color3.fromRGB(148, 158, 174), namenImmer = false }
local RANG_GROSS = { durchmesser = 108, namenHoehe = 40, namenBreite = 176, namenFarbe = Color3.fromRGB(214, 222, 234), namenImmer = true }
local RANG_KEYSTONE = { durchmesser = 140, namenHoehe = 48, namenBreite = 210, namenFarbe = Color3.fromRGB(255, 255, 255), namenImmer = true }

local function knotenRang(talent)
	if talent.tier == 0 or talent.tier >= 4 then
		return RANG_KEYSTONE
	elseif talent.tier == 3 then
		return RANG_GROSS
	end
	return RANG_NORMAL
end

-- Zeichnet ein einzelnes gerades Segment zwischen zwei Punkten -- Baustein für die
-- gebogene Kurve unten (viele kurze Segmente ergeben zusammen einen glatten Bogen).
local function drawLineSegment(fromPos, toPos, dicke, farbe, transparenz, zIndex)
	local delta = toPos - fromPos
	local distance = delta.Magnitude
	if distance < 0.5 then
		return nil
	end
	local angle = math.deg(math.atan2(delta.Y, delta.X))

	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Size = UDim2.new(0, distance + 1, 0, dicke) -- +1 Überlappung, damit keine Mini-Lücken zwischen Segmenten entstehen
	line.Position = UDim2.new(0, fromPos.X, 0, fromPos.Y)
	line.Rotation = angle
	line.BackgroundColor3 = farbe
	line.BackgroundTransparency = transparenz
	line.BorderSizePixel = 0
	line.ZIndex = zIndex
	line.Parent = leinwand
	return line
end

-- ===== Verbindungen: Grundpfad und Ader =====
--
-- Vorher war eine Verbindung ein graues Kabel, gleich fuer alle -- und damit sagte sie
-- nichts ausser "hier ist eine Linie".
--
-- Jetzt sind es ZWEI Linien uebereinander. Der dunkle Grundpfad liegt immer da: es gibt
-- hier einen Weg. Die duennere Ader darin traegt die Energiefarbe des ZIELS und sagt, ob
-- der Weg schon lebt. Die Farbe ist damit weiter eine Messung und kein Schmuck -- es ist
-- dieselbe Energiefarbe wie am Ring des Knotens, an den Gebaeuden und an den Sammelstrahlen.
--
-- Drei Zustaende:
--   erfuellt   das Ziel ist erforscht -- die Ader steht voll da
--   offen      die Vorstufe sitzt, das Ziel noch nicht -- die Ader pulsiert langsam
--   gesperrt   die Vorstufe fehlt -- nur der Grundpfad, fast unsichtbar
local PFAD_GRUND = Color3.fromRGB(16, 19, 25)

-- Die Adern, die gerade pulsieren. Wird bei jedem Neuaufbau des Baums geleert.
local pulsAdern = {}

-- Die Adersegmente, geordnet nach ZIEL. Beim Freischalten laeuft das Licht sie der Reihe
-- nach ab -- vom Elternknoten zum neuen Knoten. Ohne diese Zuordnung waeren es nur ein
-- paar hundert Frames ohne Zusammenhang.
local adernNachZiel = {}

-- Der Ring des Knotens, an dem gerade geforscht wird. Er atmet, solange die Uhr laeuft --
-- das ist die einzige Stelle im Baum, an der wirklich etwas VORGEHT, und bisher sah man
-- davon nur eine andere Farbe.
local forschungsRing = nil

-- EINE Schleife fuer alle pulsierenden Adern, nicht eine je Ader: bei dreizehn Knoten
-- waeren das bis zu einem Dutzend Tweens, die alle dasselbe tun. Steht der Baum zu, kostet
-- die Schleife einen Vergleich.
RunService.Heartbeat:Connect(function()
	if not panel.Visible then
		return
	end
	local welle = (math.sin(os.clock() * 2.2) + 1) / 2

	if #pulsAdern > 0 then
		local transparenz = 0.30 + welle * 0.45
		for _, ader in ipairs(pulsAdern) do
			ader.BackgroundTransparency = transparenz
		end
	end

	-- Dieselbe Welle fuer den forschenden Knoten: sein Ring und die Adern, die zu ihm
	-- fuehren, atmen damit im Gleichtakt. Zwei Takte nebeneinander saehen aus wie ein
	-- Fehler.
	if forschungsRing and forschungsRing.Parent then
		forschungsRing.Transparency = 0.5 - welle * 0.45
	end
end)

-- Gebogene Verbindungslinie: quadratische Bezier-Kurve (EIN Kontrollpunkt, wölbt sich
-- gleichmässig in EINE Richtung -- explizit KEINE S-Kurve, die bräuchte zwei
-- gegenläufige Kontrollpunkte). Wird aus vielen kurzen geraden Segmenten
-- zusammengesetzt, da Roblox-UI keine nativen Kurven kennt.
local function drawConnector(fromPos, toPos, zielTalent, zustand)
	local sammlung = adernNachZiel[zielTalent.id]
	if not sammlung then
		sammlung = {}
		adernNachZiel[zielTalent.id] = sammlung
	end
	local delta = toPos - fromPos
	local distance = delta.Magnitude
	if distance < 1 then
		return
	end

	-- Kontrollpunkt: Mittelpunkt der direkten Linie, senkrecht dazu leicht versetzt --
	-- ergibt eine gleichmässige Wölbung. Richtung des Versatzes hängt davon ab, ob das
	-- Ziel links oder rechts vom Start liegt, damit sich Zweig-Linien nicht gegenseitig
	-- durchkreuzen, sondern sauber auseinander wölben.
	local midpoint = (fromPos + toPos) / 2
	local perpendicular = Vector2.new(-delta.Y, delta.X)
	if perpendicular.Magnitude > 0.01 then
		perpendicular = perpendicular.Unit
	end
	local bowAmount = math.clamp(distance * 0.18, 10, 60)
	local bowDirection = (toPos.X >= fromPos.X) and 1 or -1
	local controlPoint = midpoint + perpendicular * bowAmount * bowDirection

	-- Erst die Punkte der Kurve sammeln, dann zeichnen. Grundpfad und Ader muessen exakt
	-- denselben Bogen nehmen -- die Kurve zweimal zu rechnen waere die Gelegenheit, dass
	-- sie es irgendwann nicht mehr tun.
	local segments = 14
	local punkte = { fromPos }
	for i = 1, segments do
		local t = i / segments
		local oneMinusT = 1 - t
		-- Quadratische Bezier-Formel: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
		table.insert(punkte, fromPos * (oneMinusT * oneMinusT) + controlPoint * (2 * oneMinusT * t) + toPos * (t * t))
	end

	-- Die Dicke richtet sich nach dem Rang des ZIELS: der Weg zu einem Meilenstein ist
	-- breiter als der zum naechsten Arbeitstier.
	local rang = knotenRang(zielTalent)
	local grundDicke = math.max(4, math.floor(rang.durchmesser * 0.075))
	local aderDicke = math.max(2, math.floor(rang.durchmesser * 0.032))
	local aderFarbe = ENERGY_COLORS[zielTalent.energyType] or HudChrome.Color.BorderBright
	local grundTransparenz = (zustand == "gesperrt") and 0.5 or 0.05

	for i = 1, #punkte - 1 do
		drawLineSegment(punkte[i], punkte[i + 1], grundDicke, PFAD_GRUND, grundTransparenz, 58)
	end

	if zustand == "gesperrt" then
		return
	end

	local aderTransparenz = (zustand == "erfuellt") and 0 or 0.5
	for i = 1, #punkte - 1 do
		local ader = drawLineSegment(punkte[i], punkte[i + 1], aderDicke, aderFarbe, aderTransparenz, 59)
		if ader then
			table.insert(sammlung, ader)
			if zustand == "offen" then
				table.insert(pulsAdern, ader)
			end
		end
	end
end

-- ===== Knoten-Status: gesperrt / erforschbar / in Forschung / voll ausgebaut =====
local function getNodeState(talent, level, isActiveFaction)
	if level >= talent.maxLevel then
		return "maxed"
	end
	if not isActiveFaction then
		return "preview"
	end
	local prereqsMet = true
	for _, prereq in ipairs(talent.prerequisites) do
		local prereqLevel = (talentState.levels[currentFaction] and talentState.levels[currentFaction][prereq.id]) or 0
		if prereqLevel < prereq.level then
			prereqsMet = false
			break
		end
	end
	if not prereqsMet then
		return "locked"
	end
	if talentState.research and talentState.research.talentId == talent.id and talentState.research.faction == currentFaction then
		return "researching"
	end
	if talentState.research then
		return "blocked"
	end

	-- Reicht der Vorrat? Das war bisher keine Frage des Zustands: der Knopf lud ein, und
	-- der Server lehnte ab. Wer nicht selbst nachrechnete, erfuhr nie, woran es lag.
	local cost = TalentTreeConfig.GetNodeCost(talent, level + 1)
	local genugEnergie = (talentState.energy[talent.energyType] or 0) >= cost.energyAmount
	local genugCoins = (talentState.coins or 0) >= (cost.coinAmount or 0)
	if not (genugEnergie and genugCoins) then
		return "poor"
	end

	return "available"
end

-- Was am Preis fehlt, als Tabelle: Schluessel ist der Energietyp oder "Coins", Wert der
-- Fehlbetrag. Leer heisst bezahlbar. EINE Stelle, die das rechnet -- der Knopf, die
-- Kostenzeile und die Chips oben fragen alle dieselbe.
local function fehlendeMittel(talent, level)
	if level >= talent.maxLevel then
		return nil
	end
	local cost = TalentTreeConfig.GetNodeCost(talent, level + 1)
	local fehlend = nil
	local energieLuecke = cost.energyAmount - (talentState.energy[talent.energyType] or 0)
	if energieLuecke > 0 then
		fehlend = fehlend or {}
		fehlend[talent.energyType] = energieLuecke
	end
	local coinLuecke = (cost.coinAmount or 0) - (talentState.coins or 0)
	if coinLuecke > 0 then
		fehlend = fehlend or {}
		fehlend.Coins = coinLuecke
	end
	return fehlend
end

local STATE_COLORS = {
	maxed = Color3.fromRGB(90, 200, 110),
	preview = Color3.fromRGB(50, 48, 60),
	locked = Color3.fromRGB(35, 33, 42),
	researching = Color3.fromRGB(220, 180, 60),
	blocked = Color3.fromRGB(45, 42, 55),
	available = Color3.fromRGB(60, 56, 90),
	-- Erreichbar, aber noch nicht bezahlbar: dunkler als "available", heller als
	-- "locked" -- es ist ein Zwischenzustand, und der soll auch einer sein.
	poor = Color3.fromRGB(46, 43, 62),
}

-- ===== Zeigt die Details eines Talents im rechten Panel: Beschreibung, Vorher/Nachher-
-- Werte, Kosten (Energie + Coins), Forschungszeit, Vorstufen-Hinweis falls gesperrt. =====
local function selectTalent(talent, state, level)
	-- Ein ANDERES Talent faengt oben an. Die Tafel wird auch dann neu gefuellt, wenn sich
	-- nur der Zustand desselben Talents aendert -- waehrend einer laufenden Forschung etwa,
	-- im Sekundentakt. Dort zurueckzuspringen waere kein Dienst, sondern ein Ruck unter dem
	-- Finger: wer gerade liest, verliert die Stelle.
	local anderesTalent = (selectedTalentId ~= talent.id)
	selectedTalentId = talent.id
	if anderesTalent then
		detailScroll.CanvasPosition = Vector2.new(0, 0)
	end

	-- Der Name des gewaehlten Knotens erscheint, der des vorher gewaehlten verschwindet
	-- wieder. Die Meilensteine behalten ihren in jedem Fall -- sie sind die Orientierung,
	-- an der man sich im Baum zurechtfindet, und die darf nicht von der Auswahl abhaengen.
	-- Der gewaehlte Name wird zusaetzlich hell: er gehoert zu dem, was rechts steht.
	for id, ref in pairs(nodeRefs) do
		local gewaehlt = (id == talent.id)
		ref.infoLabel.Visible = ref.rang.namenImmer or gewaehlt
		ref.infoLabel.TextColor3 = gewaehlt and Color3.fromRGB(255, 255, 255) or ref.rang.namenFarbe
	end

	detailEmpty.Visible = false
	detailIcon.Visible = true
	detailName.Visible = true
	detailLevel.Visible = true
	detailDescription.Visible = true
	detailTrennerEins.Visible = true
	detailTrennerZwei.Visible = true
	detailWirkungKopf.Visible = true
	detailWirkungReihe.Visible = true
	detailResearchTime.Visible = true

	zeigeTalentSymbol(detailIconBild, detailIconText, talent)
	-- Der Rahmen traegt die Energiefarbe, nicht die Flaeche: sonst kaempft ein farbiger
	-- Grund mit dem Bild darauf.
	local detailIconStroke = detailIcon:FindFirstChildOfClass("UIStroke")
	if detailIconStroke then
		detailIconStroke.Color = ENERGY_COLORS[talent.energyType] or HudChrome.Color.Border
	end
	detailName.Text = talent.name
	detailLevel.Text = string.format("LEVEL %d / %d", level, talent.maxLevel)
	detailDescription.Text = talent.description

	-- Vorher -> Nachher: simuliert den Zustand MIT einer Stufe mehr auf diesem Talent,
	-- vergleicht den Gesamtwert des betroffenen Effekt-Schlüssels davor/danach.
	local currentLevels = talentState.levels[currentFaction] or {}
	local simulatedLevels = table.clone(currentLevels)
	simulatedLevels[talent.id] = math.min(level + 1, talent.maxLevel)
	local vollAusgebaut = (level >= talent.maxLevel)

	local energieFarbe = ENERGY_COLORS[talent.energyType] or HudChrome.Color.Accent

	local primaryLabel = STAT_LABELS[talent.effectKey] or talent.effectKey
	local currentPrimary = getEffectTotal(currentFaction, talent.effectKey, currentLevels)
	local newPrimary = getEffectTotal(currentFaction, talent.effectKey, simulatedLevels)
	detailWirkungKopf.Text = string.upper(primaryLabel)
	detailWirkungKopf.TextColor3 = energieFarbe
	detailWirkungVorher.Text = formatStatValue(talent.effectKey, currentPrimary)
	detailWirkungNachher.Text = formatStatValue(talent.effectKey, newPrimary)
	detailWirkungNachher.TextColor3 = energieFarbe

	-- Voll ausgebaut gibt es kein Nachher. Pfeil und Zielwert fallen weg, und der
	-- erreichte Wert steht allein da -- in der Energiefarbe, weil er jetzt das Ergebnis
	-- ist und nicht mehr der Ausgangspunkt. Verschieben muss man dafuer nichts: die Reihe
	-- flieszt von links, und was fehlt, hinterlaesst keine Luecke.
	detailWirkungPfeil.Visible = not vollAusgebaut
	detailWirkungNachher.Visible = not vollAusgebaut
	detailWirkungVorher.TextColor3 = vollAusgebaut and energieFarbe or HudChrome.Color.TextDim

	local mitTradeoff = (talent.tradeoffEffectKey ~= nil)
	detailTradeoffKopf.Visible = mitTradeoff
	detailTradeoffReihe.Visible = mitTradeoff
	if mitTradeoff then
		local tradeoffLabel = STAT_LABELS[talent.tradeoffEffectKey] or talent.tradeoffEffectKey
		local currentTradeoff = getEffectTotal(currentFaction, talent.tradeoffEffectKey, currentLevels)
		local newTradeoff = getEffectTotal(currentFaction, talent.tradeoffEffectKey, simulatedLevels)
		detailTradeoffKopf.Text = "TRADE-OFF · " .. string.upper(tradeoffLabel)
		detailTradeoffVorher.Text = formatStatValue(talent.tradeoffEffectKey, currentTradeoff)
		detailTradeoffNachher.Text = formatStatValue(talent.tradeoffEffectKey, newTradeoff)
	end
	ordneDetailInhalt(mitTradeoff)

	-- Die Kosten stehen im KNOPF, nicht in einem eigenen Abschnitt: bezahlt wird beim
	-- Druecken, und wer drueckt, schaut auf den Knopf.
	-- ===== Der Preis sagt, woran es liegt =====
	--
	-- Er stand als eine Zeile da, und ob er bezahlbar war, musste man selbst nachrechnen:
	-- Zahl im Knopf gegen Zahl in der Leiste oben. Jetzt ist der Teil, der nicht gedeckt
	-- ist, rot und traegt den FEHLBETRAG -- nicht nur "zu wenig", sondern wie viel.
	local fehlend = fehlendeMittel(talent, level)
	zeigeFehlbetraege(fehlend)

	if vollAusgebaut then
		knopfKosten.Text = ""
		detailResearchTime.Text = ""
	else
		local cost = TalentTreeConfig.GetNodeCost(talent, level + 1)
		local rot = alsHex(HudChrome.Color.Danger)
		local function stueck(betrag, name, luecke)
			local text = string.format("%d %s", betrag, name)
			if luecke then
				return string.format('<font color="#%s">%s  (−%d)</font>', rot, text, luecke)
			end
			return text
		end

		local teile = {
			stueck(cost.energyAmount, string.upper(talent.energyType), fehlend and fehlend[talent.energyType]),
		}
		if cost.coinAmount > 0 then
			table.insert(teile, stueck(cost.coinAmount, "COINS", fehlend and fehlend.Coins))
		end
		knopfKosten.RichText = true
		knopfKosten.Text = table.concat(teile, "   ")
		detailResearchTime.Text = "RESEARCH TIME " .. string.upper(formatDuration(talent.researchSeconds))
	end

	-- Vorstufen-Hinweis, falls gesperrt
	if state == "locked" then
		local missing = {}
		for _, prereq in ipairs(talent.prerequisites) do
			local prereqLevel = (currentLevels[prereq.id]) or 0
			if prereqLevel < prereq.level then
				local prereqTalent = TalentTreeConfig.FindTalent(currentFaction, prereq.id)
				table.insert(missing, (prereqTalent and prereqTalent.name or prereq.id) .. " Lv." .. prereq.level)
			end
		end
		detailPrereqLabel.Visible = true
		detailPrereqLabel.Text = "🔒 Requires: " .. table.concat(missing, ", ")
	else
		detailPrereqLabel.Visible = false
	end

	-- Der Knopf sagt, WAS passiert; die Kostenzeile darunter, was es kostet. Ist nichts zu
	-- holen, verschwindet sie -- ein Preis an einem Knopf, den man nicht druecken kann, ist
	-- eine Einladung ins Leere.
	detailResearchButton.Visible = true
	local knopfGrund = HudChrome.Color.PanelRaised
	if state == "available" then
		knopfHaupt.Text = "RESEARCH"
		knopfGrund = Color3.fromRGB(46, 128, 74)
		detailResearchButton.Active = true
	elseif state == "researching" then
		knopfHaupt.Text = "RESEARCHING…"
		knopfGrund = Color3.fromRGB(120, 86, 24)
		detailResearchButton.Active = false
	elseif state == "maxed" then
		knopfHaupt.Text = "MAXED"
		detailResearchButton.Active = false
	elseif state == "poor" then
		-- Fehlt genau eine Sache, steht sie im Knopf -- das ist die Antwort auf "warum
		-- nicht?", ohne dass man dafuer irgendwo hinschauen muss. Fehlen zwei, waere die
		-- Zeile zu lang; dann zeigt die Kostenzeile darunter beide rot.
		local fehltHier = fehlendeMittel(talent, level)
		local eintraege = {}
		if fehltHier then
			for schluessel, betrag in pairs(fehltHier) do
				table.insert(eintraege, { schluessel = schluessel, betrag = betrag })
			end
		end
		if #eintraege == 1 then
			local e = eintraege[1]
			local name = (e.schluessel == "Coins") and "COINS" or string.upper(e.schluessel)
			knopfHaupt.Text = string.format("NEED %d MORE %s", e.betrag, name)
		else
			knopfHaupt.Text = "NOT ENOUGH RESOURCES"
		end
		detailResearchButton.Active = false
	elseif state == "blocked" then
		knopfHaupt.Text = "OTHER RESEARCH ACTIVE"
		detailResearchButton.Active = false
	else
		knopfHaupt.Text = "LOCKED"
		detailResearchButton.Active = false
	end
	detailResearchButton.BackgroundColor3 = knopfGrund
	-- Die Kostenzeile bleibt auch dann stehen, wenn das Geld fehlt -- gerade dann: sie ist
	-- die Stelle, an der steht, WIE VIEL fehlt.
	knopfKosten.Visible = (state == "available" or state == "poor") and knopfKosten.Text ~= ""
	knopfKosten.TextColor3 = HudChrome.Color.TextSecondary
	-- Ohne Kostenzeile steht die Beschriftung mittig statt oben.
	if knopfKosten.Visible then
		knopfHaupt.Size = UDim2.new(1, -2 * KNOPF_RAND, 0, 26)
		knopfHaupt.Position = UDim2.new(0, KNOPF_RAND, 0, 7)
	else
		knopfHaupt.Size = UDim2.new(1, -2 * KNOPF_RAND, 1, 0)
		knopfHaupt.Position = UDim2.new(0, KNOPF_RAND, 0, 0)
	end
	detailResearchTime.Visible = (state == "available" or state == "poor")
end

detailResearchButton.MouseButton1Click:Connect(function()
	if selectedTalentId and detailResearchButton.Active then
		StartResearchEvent:FireServer(currentFaction, selectedTalentId)
	end
end)

-- Aktualisiert die Detail-Ansicht für das aktuell ausgewählte Talent mit frischen Daten
-- (z.B. nachdem eine Forschung gestartet/abgeschlossen wurde).
local function refreshSelectedTalentDetails()
	if not selectedTalentId then
		return
	end
	local talent = TalentTreeConfig.FindTalent(currentFaction, selectedTalentId)
	if not talent then
		return
	end
	local level = (talentState.levels[currentFaction] and talentState.levels[currentFaction][selectedTalentId]) or 0
	local isActiveFaction = (talentState.activeFaction == currentFaction)
	local state = getNodeState(talent, level, isActiveFaction)
	selectTalent(talent, state, level)
end

local function buildNode(talent, position, isActiveFaction)
	local rang = knotenRang(talent)
	local D = rang.durchmesser
	local symbol = math.floor(D * 0.77)
	-- Etwas oberhalb der Mitte, damit unten Platz fuer die Stufenzahl bleibt.
	local symbolY = math.floor((D - symbol) * 0.35)
	-- Die Stufenzahl sitzt auf 86% der Hoehe. Weiter unten wuerde die Unterlage im runden
	-- Knoten seitlich anstossen -- dort ist die Sehne schon schmaler als das Schild.
	local schildHoehe = math.clamp(math.floor(D * 0.25), 18, 26)
	local schildBreite = math.floor(D * 0.55)
	local schildY = math.floor(D * 0.86) - schildHoehe
	local level = (talentState.levels[currentFaction] and talentState.levels[currentFaction][talent.id]) or 0
	local state = getNodeState(talent, level, isActiveFaction)

	local button = Instance.new("TextButton")
	button.Name = talent.id
	button.Size = UDim2.new(0, D, 0, D)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(0, position.X, 0, position.Y)
	button.BackgroundColor3 = STATE_COLORS[state]
	button.Text = ""
	button.ZIndex = 62
	button.Parent = leinwand
	-- Rund: ein Knoten in einem Baum ist ein Punkt, keine Kachel. HudChrome.Pill setzt
	-- dafuer einen echten Halbkreis-Radius.
	local nodeCorner, nodeStroke = HudChrome.Pill(button, { fill = false })
	if state == "researching" then
		forschungsRing = nodeStroke
	end
	if talent.isTradeoff then
		nodeStroke.Color = Color3.fromRGB(230, 140, 40)
	elseif ENERGY_COLORS[talent.energyType] then
		nodeStroke.Color = ENERGY_COLORS[talent.energyType]
	end

	local iconBild = HudChrome.IconImage(button, "")
	iconBild.Size = UDim2.new(0, symbol, 0, symbol)
	iconBild.Position = UDim2.new(0.5, -symbol / 2, 0, symbolY)
	iconBild.Visible = false
	iconBild.ZIndex = 63

	-- Der Notbehelf sitzt auf demselben Platz wie das Bild: wer ein Symbol nachreicht,
	-- soll nichts verrutschen sehen.
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, symbol, 0, symbol)
	iconLabel.Position = UDim2.new(0.5, -symbol / 2, 0, symbolY)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextScaled = true
	iconLabel.ZIndex = 63
	iconLabel.Parent = button

	zeigeTalentSymbol(iconBild, iconLabel, talent)

	local levelUnterlage = Instance.new("Frame")
	levelUnterlage.Name = "LevelBacking"
	levelUnterlage.Size = UDim2.new(0, schildBreite, 0, schildHoehe)
	levelUnterlage.Position = UDim2.new(0.5, -schildBreite / 2, 0, schildY)
	levelUnterlage.BackgroundColor3 = Color3.fromRGB(6, 8, 11)
	levelUnterlage.BackgroundTransparency = 0.25
	levelUnterlage.BorderSizePixel = 0
	levelUnterlage.ZIndex = 63
	levelUnterlage.Parent = button
	HudChrome.Pill(levelUnterlage, { fill = false, border = false })

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.new(0, schildBreite, 0, schildHoehe - 6)
	levelLabel.Position = UDim2.new(0.5, -schildBreite / 2, 0, schildY + 3)
	levelLabel.BackgroundTransparency = 1

	levelLabel.TextScaled = true
	levelLabel.TextColor3 = Color3.new(1, 1, 1)
	levelLabel.Text = level .. "/" .. talent.maxLevel
	levelLabel.ZIndex = 64
	levelLabel.Parent = button

	-- Der Name haengt unter dem Knoten und waechst mit seinem Rang. Vorher stand er bei
	-- allen dreizehn gleich gross da und machte das Bild unruhig -- am dichtesten
	-- ausgerechnet dort, wo die kleinen Knoten eng beieinander stehen.
	--
	-- Dauerhaft tragen ihn nur die Meilensteine. Der kleine Knoten zeigt ihn, sobald er
	-- AUSGEWAEHLT ist. Das ist auf dem Telefon das Gegenstueck zum Hover, das es dort
	-- nicht gibt, und es kostet keinen zweiten Griff: antippen waehlt ohnehin schon aus.
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(0, rang.namenBreite, 0, rang.namenHoehe)
	infoLabel.AnchorPoint = Vector2.new(0.5, 0)
	-- Der Name zeigt nach AUSSEN, die Speiche entlang -- nicht stur nach unten.
	--
	-- Auf einem Faecher, der nach oben waechst, zeigt "unter dem Knoten" zurueck in die
	-- eigene Speiche: der Name von Stufe 3 landete auf dem Knoten von Stufe 2. Nach aussen
	-- versetzt setzt er die Speiche fort, und dort ist per Bauart Platz -- der naechste
	-- Knoten kommt erst eine Stufe weiter.
	--
	-- Zwei Ausnahmen, beide an den Enden des Faechers.
	--
	-- Die Wurzel hat keine Richtung (Radius null) und nimmt gerade nach unten -- unter ihr
	-- ist ohnehin nichts mehr.
	--
	-- Bei der Krone waere aussen der Rand der Flaeche. Ihr Name tritt deshalb zur SEITE.
	-- Das ist nicht nur eine Notloesung: oben neben der Krone ist die Flaeche leer, und
	-- weil der Name dort keine Hoehe mehr braucht, darf die Krone viel naeher an Stufe 3
	-- ruecken. Der ganze Baum wird dadurch auf jedem Bildschirm groesser -- die Hoehe der
	-- Flaeche ist es, die den Massstab begrenzt.
	infoLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	if talent.tier >= 4 then
		infoLabel.Position = UDim2.new(
			0, position.X + D / 2 + rang.namenBreite / 2 + 14,
			0, position.Y
		)
		infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	else
		local hinaus = position - FAECHER_WURZEL
		if talent.tier == 0 or hinaus.Magnitude < 1 then
			hinaus = Vector2.new(0, 1)
		else
			hinaus = hinaus.Unit
		end
		local namenAbstand = D / 2 + rang.namenHoehe / 2 + 6
		infoLabel.Position = UDim2.new(
			0, position.X + hinaus.X * namenAbstand,
			0, position.Y + hinaus.Y * namenAbstand
		)
	end
	infoLabel.BackgroundTransparency = 1

	infoLabel.TextScaled = true
	infoLabel.TextWrapped = true
	infoLabel.TextColor3 = rang.namenFarbe
	infoLabel.Text = talent.name
	infoLabel.Visible = rang.namenImmer or (talent.id == selectedTalentId)
	infoLabel.ZIndex = 61
	infoLabel.Parent = leinwand

	button.MouseButton1Click:Connect(function()
		selectTalent(talent, state, level)
	end)

	-- "NEU"-Fahne: zeigt beim Oeffnen, WELCHE Forschung fertig geworden ist. Der Baum hat
	-- dreizehn Knoten je Fraktion -- ohne Markierung muesste man sie absuchen.
	local newFlag = Instance.new("TextLabel")
	newFlag.Name = "NewFlag"
	newFlag.AnchorPoint = Vector2.new(0.5, 0)
	newFlag.Size = UDim2.new(0, 44, 0, 18)
	newFlag.Position = UDim2.new(0.5, 0, 0, -8)
	newFlag.BackgroundColor3 = Color3.fromRGB(235, 45, 45)

	newFlag.TextScaled = true
	newFlag.TextColor3 = Color3.fromRGB(255, 255, 255)
	newFlag.Text = "NEW"
	newFlag.ZIndex = 64
	newFlag.Visible = (_G.GetNavBadgeItems and _G.GetNavBadgeItems("Talents")[talent.id]) == true
	newFlag.Parent = button
	HudChrome.Panel(newFlag, { radius = HudChrome.Radius.Small, fill = HudChrome.Color.Danger })
	HudChrome.Label(newFlag, 11)
	newFlag.TextColor3 = Color3.new(1, 1, 1)

	nodeRefs[talent.id] = {
		button = button,
		stroke = nodeStroke,
		levelLabel = levelLabel,
		infoLabel = infoLabel,
		position = position,
		newFlag = newFlag,
		rang = rang,
	}
end

local function renderTree(factionName)
	if factionName ~= currentFaction then
		-- Fraktion gewechselt -- Auswahl gehört zum alten Baum, macht hier keinen Sinn mehr.
		selectedTalentId = nil
		detailEmpty.Visible = true
		detailIcon.Visible = false
		detailName.Visible = false
		detailLevel.Visible = false
		detailDescription.Visible = false
		detailTrennerEins.Visible = false
		detailTrennerZwei.Visible = false
		detailWirkungKopf.Visible = false
		detailWirkungReihe.Visible = false
		detailTradeoffKopf.Visible = false
		detailTradeoffReihe.Visible = false
		detailResearchTime.Visible = false
		detailPrereqLabel.Visible = false
		-- Ohne Auswahl gibt es keinen Preis -- und damit auch nichts, das rot sein duerfte.
		zeigeFehlbetraege(nil)
		detailResearchButton.Visible = false
	end
	currentFaction = factionName
	nodeRefs = {}
	-- Die alten Adern sind mit den Segmenten zerstoert worden; die Listen zeigen sonst auf
	-- Instanzen, die es nicht mehr gibt, und die Puls-Schleife liefe ins Leere.
	pulsAdern = {}
	adernNachZiel = {}
	forschungsRing = nil
	-- WICHTIG: erst ALLE zu löschenden Kinder sammeln, DANN erst löschen -- wer während
	-- einer ipairs()-Schleife Kinder zerstört, überspringt dabei manche Elemente (Lua-
	-- Klassiker), wodurch alte Verbindungslinien von früheren Aufrufen liegen bleiben und
	-- sich mit den neuen kreuzen.
	-- Nur die gezeichneten Sachen. Was hier NICHT wegdarf: das Uhrwerk (es gehoert zur
	-- Flaeche, nicht zum Baum) und alles, was kein GuiObject ist.
	--
	-- Letzteres war ein stiller Fehler: die Bedingung nahm frueher jedes Kind ausser
	-- UICorner und UIStroke -- also auch das UIScale, mit dem der Baum an den Bildschirm
	-- angepasst wird. Es verschwand beim ersten Neuaufbau, und jede spaetere Zuweisung an
	-- treeScale.Scale lief ins Leere, ohne zu murren.
	local toDestroy = {}
	for _, child in ipairs(leinwand:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Werk" then
			table.insert(toDestroy, child)
		end
	end
	for _, child in ipairs(toDestroy) do
		child:Destroy()
	end

	local nodes = TalentTreeConfig.GetTalentsForFaction(factionName)
	local branchAngles, branchOrder = getBranchAngles(nodes)
	local isActiveFaction = (talentState.activeFaction == factionName)

	local positionsById = {}
	local talentsById = {}
	for _, talent in ipairs(nodes) do
		positionsById[talent.id] = getNodePosition(talent, branchAngles, branchOrder)
		talentsById[talent.id] = talent
	end
	for _, talent in ipairs(nodes) do
		for _, prereq in ipairs(talent.prerequisites) do
			local prereqTalent = talentsById[prereq.id]
			-- Die Linien von der Wurzel zu den Zweigen waren frueher ausgenommen: in der
			-- Spaltenansicht kreuzten sie sich mit den Synergie-Linien und machten das Bild
			-- unuebersichtlich. Auf dem Zifferblatt ist genau das Gegenteil der Fall --
			-- sie laufen radial nach aussen und sind die Speichen, die die Scheibe
			-- ueberhaupt als Scheibe lesbar machen. Also wieder dabei.
			if positionsById[prereq.id] and prereqTalent then
				-- Der Zustand gehoert der VERBINDUNG, nicht einem der beiden Knoten: sie
				-- lebt erst, wenn das Ziel erforscht ist, und sie ruft, wenn die Vorstufe
				-- sitzt und das Ziel noch offen steht.
				local stufen = talentState.levels[factionName] or {}
				local zustand
				if (stufen[talent.id] or 0) > 0 then
					zustand = "erfuellt"
				elseif (stufen[prereq.id] or 0) >= prereq.level then
					zustand = "offen"
				else
					zustand = "gesperrt"
				end
				drawConnector(positionsById[prereq.id], positionsById[talent.id], talent, zustand)
			end
		end
	end

	for _, talent in ipairs(nodes) do
		buildNode(talent, positionsById[talent.id], isActiveFaction)
	end
end

-- ===== Tabs bauen =====
-- Dieselben Symbolknoepfe wie im Skin-Laden. Drei Figuren, zwei Bildschirme, ein Aussehen.
local tabButtons = {}
for index, tabConfig in ipairs(FACTION_TABS) do
	local tabButton = Instance.new("TextButton")
	tabButton.Name = tabConfig.key .. "Tab"
	tabButton.Size = UDim2.new(0, 44, 0, 44)
	tabButton.LayoutOrder = index
	tabButton.AutoButtonColor = false
	tabButton.Text = ""
	tabButton.ZIndex = 5
	tabButton.Parent = tabRow
	local _, tabStroke = HudChrome.Panel(tabButton, {
		radius = HudChrome.Radius.Small,
		fill = HudChrome.Color.Panel,
	})
	local tabBild = HudChrome.IconImage(tabButton, HudChrome.FactionIcon[tabConfig.key] or "")
	tabBild.Size = UDim2.new(1, -12, 1, -12)
	tabBild.Position = UDim2.new(0, 6, 0, 6)
	tabBild.ZIndex = 6

	tabButtons[tabConfig.key] = { rand = tabStroke, bild = tabBild }

	tabButton.MouseButton1Click:Connect(function()
		renderTree(tabConfig.key)
		for key, eintrag in pairs(tabButtons) do
			local gewaehlt = (key == tabConfig.key)
			eintrag.rand.Color = gewaehlt and HudChrome.Color.BorderBright or HudChrome.Color.Border
			eintrag.rand.Thickness = gewaehlt and 2 or HudChrome.BorderThickness
			eintrag.bild.ImageTransparency = gewaehlt and 0 or 0.45
		end
		schirm.subtitle.Text = string.upper(tabConfig.label)
	end)
end

-- ===== Forschungs-Statusanzeige aktualisieren =====
-- ===== Eigenstaendiges HUD-Feld: zeigt den Forschungs-Fortschritt AUCH wenn das
-- Talent-Fenster geschlossen ist. =====
--
-- Es steht in der linken Spalte, unter der Bahn der Belohnungs-Meldungen (HudToast, oben
-- links bis y 80). Die Forschung ist ein DAUERZUSTAND -- sie laeuft, waehrend man kaempft,
-- und man will nur wissen, wie lange noch. Deshalb dieselbe Anatomie wie die anderen
-- Dauer-Anzeigen: Symbol, Name, Unterzeile, und ein schmaler Balken an der Unterkante.
--
-- Vorher fuellte der Fortschritt das ganze Feld als durchscheinende Flaeche hinter dem
-- Text. Das las sich als "Feld halb markiert", nicht als Fortschritt -- und der Text stand
-- zur Haelfte auf Gelb, zur Haelfte auf Dunkel.
local HUD_BREITE = 260
local HUD_HOEHE = 66
local HUD_RAND = 12
local HUD_SYMBOL = 26

local hudScreenGui = Instance.new("ScreenGui")
hudScreenGui.Name = "ResearchHudGui"
hudScreenGui.ResetOnSpawn = false
hudScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudScreenGui.Parent = playerGui

local hudResearchFrame = Instance.new("Frame")
hudResearchFrame.Name = "ResearchHudFrame"
hudResearchFrame.Size = UDim2.new(0, HUD_BREITE, 0, HUD_HOEHE)
hudResearchFrame.Position = UDim2.new(0, 16, 0, 96)
hudResearchFrame.Visible = false
hudResearchFrame.Parent = hudScreenGui
HudChrome.Panel(hudResearchFrame, { radius = HudChrome.Radius.Small })

local hudResearchIcon = Instance.new("TextLabel")
hudResearchIcon.Name = "ResearchIcon"
hudResearchIcon.Size = UDim2.new(0, HUD_SYMBOL, 0, HUD_SYMBOL)
hudResearchIcon.Position = UDim2.new(0, HUD_RAND, 0, 9)
hudResearchIcon.BackgroundTransparency = 1
hudResearchIcon.TextScaled = true
hudResearchIcon.Text = ""
hudResearchIcon.ZIndex = 2
hudResearchIcon.Parent = hudResearchFrame

local HUD_TEXT_X = HUD_RAND + HUD_SYMBOL + 8

local hudResearchLabel = Instance.new("TextLabel")
hudResearchLabel.Name = "ResearchLabel"
hudResearchLabel.Size = UDim2.new(0, HUD_BREITE - HUD_TEXT_X - HUD_RAND, 0, 22)
hudResearchLabel.Position = UDim2.new(0, HUD_TEXT_X, 0, 7)
hudResearchLabel.BackgroundTransparency = 1
hudResearchLabel.TextXAlignment = Enum.TextXAlignment.Left
hudResearchLabel.TextTruncate = Enum.TextTruncate.AtEnd
hudResearchLabel.Text = ""
hudResearchLabel.ZIndex = 2
hudResearchLabel.Parent = hudResearchFrame
HudChrome.Label(hudResearchLabel, 17)

local hudResearchCountdown = Instance.new("TextLabel")
hudResearchCountdown.Name = "ResearchCountdown"
hudResearchCountdown.Size = UDim2.new(0, HUD_BREITE - HUD_TEXT_X - HUD_RAND, 0, 18)
hudResearchCountdown.Position = UDim2.new(0, HUD_TEXT_X, 0, 29)
hudResearchCountdown.BackgroundTransparency = 1
hudResearchCountdown.TextXAlignment = Enum.TextXAlignment.Left
hudResearchCountdown.Text = ""
hudResearchCountdown.ZIndex = 2
hudResearchCountdown.Parent = hudResearchFrame
HudChrome.Number(hudResearchCountdown, 13)
hudResearchCountdown.TextColor3 = HudChrome.Color.TextSecondary

local hudResearchTrack = Instance.new("Frame")
hudResearchTrack.Name = "ResearchTrack"
hudResearchTrack.Size = UDim2.new(0, HUD_BREITE - HUD_RAND * 2, 0, 6)
hudResearchTrack.Position = UDim2.new(0, HUD_RAND, 0, 52)
hudResearchTrack.BackgroundColor3 = HudChrome.Color.PanelSunken
hudResearchTrack.BorderSizePixel = 0
hudResearchTrack.ZIndex = 2
hudResearchTrack.Parent = hudResearchFrame

local hudResearchTrackCorner = Instance.new("UICorner")
hudResearchTrackCorner.CornerRadius = UDim.new(0, 3)
hudResearchTrackCorner.Parent = hudResearchTrack

local hudResearchFill = Instance.new("Frame")
hudResearchFill.Name = "Fill"
hudResearchFill.Size = UDim2.new(0, 0, 1, 0)
hudResearchFill.BackgroundColor3 = HudChrome.Color.Ready
hudResearchFill.BorderSizePixel = 0
hudResearchFill.ZIndex = 3
hudResearchFill.Parent = hudResearchTrack

local hudResearchFillCorner = Instance.new("UICorner")
hudResearchFillCorner.CornerRadius = UDim.new(0, 3)
hudResearchFillCorner.Parent = hudResearchFill

-- Klick auf das HUD-Widget öffnet direkt das Talent-Fenster (bequemer Rücksprung).
local hudResearchButton = Instance.new("TextButton")
hudResearchButton.Size = UDim2.new(1, 0, 1, 0)
hudResearchButton.BackgroundTransparency = 1
hudResearchButton.Text = ""
hudResearchButton.ZIndex = 4
hudResearchButton.Parent = hudResearchFrame
hudResearchButton.MouseButton1Click:Connect(function()
	panel.Visible = true
end)

local function updateResearchHud()
	if not talentState.research then
		hudResearchFrame.Visible = false
		return
	end
	local talent = TalentTreeConfig.FindTalent(talentState.research.faction, talentState.research.talentId)
	if not talent then
		hudResearchFrame.Visible = false
		return
	end

	hudResearchFrame.Visible = true
	local remaining = talentState.research.completesAt - workspace:GetServerTimeNow()
	hudResearchIcon.Text = talent.icon
	hudResearchLabel.Text = talent.name
	hudResearchCountdown.Text = string.upper(formatDuration(remaining)) .. " LEFT"

	local elapsed = talentState.research.totalDuration - remaining
	local ratio = math.clamp(elapsed / math.max(talentState.research.totalDuration, 0.01), 0, 1)
	hudResearchFill.Size = UDim2.new(ratio, 0, 1, 0)
end

local function updateResearchBar()
	if not talentState.research then
		researchBar.Visible = false
		return
	end
	local talent = TalentTreeConfig.FindTalent(talentState.research.faction, talentState.research.talentId)
	if not talent then
		researchBar.Visible = false
		return
	end
	researchBar.Visible = true
	local remaining = talentState.research.completesAt - workspace:GetServerTimeNow()
	researchLabel.Text = "🔬 Researching: " .. talent.name .. " -- " .. formatDuration(remaining) .. " left"

	local elapsed = talentState.research.totalDuration - remaining
	local ratio = math.clamp(elapsed / math.max(talentState.research.totalDuration, 0.01), 0, 1)
	researchProgressFill.Size = UDim2.new(ratio, 0, 1, 0)
end

-- Pro-Frame-Update (statt einmal pro Sekunde) -- die Fortschrittsbalken füllen sich
-- dadurch flüssig, statt sichtbar in Sekunden-Sprüngen zu springen. Die Textanzeige
-- (MM:SS) ändert sich zwar ohnehin nur einmal pro Sekunde sichtbar, wird aber trotzdem
-- mit aktualisiert -- die eigentlichen Berechnungen hier sind günstig genug dafür.
RunService.Heartbeat:Connect(function()
	if talentState.research then
		updateResearchHud() -- läuft IMMER, auch bei geschlossenem Talent-Fenster
		if panel.Visible then
			updateResearchBar()
		end
	else
		hudResearchFrame.Visible = false
	end
end)

-- ===== Server-Events =====
StartResearchEvent.OnClientEvent:Connect(function(factionName, talentId, completesAt, totalDuration)
	talentState.research = { faction = factionName, talentId = talentId, completesAt = completesAt, totalDuration = totalDuration }
	requestState()
	updateResourceDisplay()
	updateResearchBar()
	updateResearchHud()
	if factionName == currentFaction then
		renderTree(currentFaction)
		refreshSelectedTalentDetails()
	end
end)

-- ===== Der Moment, in dem eine Forschung fertig wird =====
--
-- Bis hierher war das Ergebnis einer Forschung: eine Zahl aendert sich, und der Knoten hat
-- eine andere Farbe. Nach Minuten Wartezeit ist das keine Belohnung, sondern eine
-- Buchung.
--
-- Drei Dinge passieren jetzt, und alle drei erzaehlen dasselbe -- die Energie ist
-- angekommen:
--   das LICHT laeuft die Ader entlang, vom Elternknoten zum neuen Knoten
--   der RING des Knotens blitzt auf und legt sich wieder
--   eine WELLE geht von ihm aus und verklingt
--
-- Der Ton ist DERSELBE wie beim abgeholten Geschenk. Das ist kein Sparen: beide Male ist
-- etwas gutgeschrieben worden, auf das man gewartet hat -- ein eigener Klang fuer denselben
-- Vorgang waere eine Unterscheidung ohne Unterschied. Er steht in HudChrome, damit die
-- Nummer nur an einer Stelle liegt.

local forschungFertigSound = Instance.new("Sound")
forschungFertigSound.Name = "TalentUnlockSound"
forschungFertigSound.SoundId = HudChrome.Sound.Belohnung
forschungFertigSound.Volume = 0.8
forschungFertigSound.Parent = SoundService

-- Das Licht laeuft die Ader entlang. Segment fuer Segment hell, jedes einzelne faellt
-- danach von selbst zurueck -- deshalb ueberlagert sich nichts, und es sieht aus wie eine
-- Welle und nicht wie ein Schalter.
local function lichtDurchDieAder(talentId)
	local segmente = adernNachZiel[talentId]
	if not segmente or #segmente == 0 then
		return
	end
	task.spawn(function()
		for _, ader in ipairs(segmente) do
			if not ader.Parent then
				break
			end
			local ruhe = ader.BackgroundColor3
			local ruheTransparenz = ader.BackgroundTransparency
			ader.BackgroundColor3 = Color3.new(1, 1, 1)
			ader.BackgroundTransparency = 0
			TweenService:Create(ader, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
				BackgroundColor3 = ruhe,
				BackgroundTransparency = ruheTransparenz,
			}):Play()
			task.wait(0.018)
		end
	end)
end

-- Die Welle: ein Ring, der aus dem Knoten herauswaechst und dabei verschwindet. Er liegt
-- UNTER dem Knoten, damit das Symbol darin nicht ueberdeckt wird.
local function welleAmKnoten(ref, farbe)
	local welle = Instance.new("Frame")
	welle.Name = "Welle"
	welle.AnchorPoint = Vector2.new(0.5, 0.5)
	welle.Position = UDim2.new(0, ref.position.X, 0, ref.position.Y)
	welle.Size = ref.button.Size
	welle.BackgroundTransparency = 1
	welle.ZIndex = 61
	welle.Parent = ref.button.Parent

	local ecke = Instance.new("UICorner")
	ecke.CornerRadius = UDim.new(0.5, 0)
	ecke.Parent = welle

	local rand = Instance.new("UIStroke")
	rand.Thickness = 3
	rand.Color = farbe
	rand.Transparency = 0.1
	rand.Parent = welle

	local ziel = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local gross = ref.button.Size.X.Offset * 2.4
	TweenService:Create(welle, ziel, { Size = UDim2.new(0, gross, 0, gross) }):Play()
	TweenService:Create(rand, ziel, { Transparency = 1 }):Play()
	task.delay(0.6, function()
		welle:Destroy()
	end)
end

local function feiereFreischaltung(talentId)
	local ref = nodeRefs[talentId]
	if not ref or not ref.button.Parent then
		return
	end

	local farbe = ref.stroke and ref.stroke.Color or HudChrome.Color.Accent
	lichtDurchDieAder(talentId)
	welleAmKnoten(ref, farbe)

	-- Der Ring blitzt auf und legt sich wieder. Dicke statt Farbe: die Farbe des Rings ist
	-- die Energie des Talents und bedeutet etwas -- die darf ein Effekt nicht ueberschreiben.
	if ref.stroke then
		local ruhe = ref.stroke.Thickness
		ref.stroke.Thickness = ruhe + 4
		ref.stroke.Transparency = 0
		TweenService:Create(ref.stroke, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			Thickness = ruhe,
		}):Play()
	end

end

ResearchCompleteEvent.OnClientEvent:Connect(function(factionName, talentId, newLevel)
	-- Laempchen am Menuepunkt: eine fertige Forschung ist ein einmaliges Ereignis und
	-- damit ein echter Hinweis -- anders als "genug Energie fuer einen Knoten", das mit
	-- der Energie staendig an- und ausginge.
	if _G.SetNavBadge and not panel.Visible then
		_G.SetNavBadge("Talents", true, talentId)
	end
	if not talentState.levels[factionName] then
		talentState.levels[factionName] = {}
	end
	talentState.levels[factionName][talentId] = newLevel
	talentState.research = nil
	updateResearchBar()
	updateResearchHud()
	if factionName == currentFaction then
		renderTree(currentFaction)
		refreshSelectedTalentDetails()
	end
end)

-- Bestaetigung des Abbruchs. Erst hier faellt talentState.research weg -- nicht schon beim
-- Druck auf den Knopf: was der Server nicht ausgefuehrt hat, darf der Bildschirm nicht
-- behaupten. Der Weg ist derselbe wie bei der fertigen Forschung, nur ohne neue Stufe.
CancelResearchEvent.OnClientEvent:Connect(function(factionName, _talentId)
	talentState.research = nil
	requestState()
	updateResourceDisplay()
	updateResearchBar()
	updateResearchHud()
	-- Der Ton IMMER, und zwar zuerst.
	--
	-- Er stand einmal IM Effekt, und der laeuft nur bei offenem Panel -- mit der
	-- Begruendung, niemand solle einen Ton aus einem Bildschirm hoeren, den er nicht sieht.
	-- Das war verkehrt herum gedacht: eine Forschung dauert Minuten, man steht in aller
	-- Regel in der Stadt und nicht im Talentbaum, wenn sie fertig wird. Genau dann ist der
	-- Klang das Einzige, was den Moment ueberhaupt meldet -- und dafuer ist er da. Bei
	-- geschlossenem Panel waere er nie erklungen.
	forschungFertigSound:Play()

	if factionName == currentFaction then
		renderTree(currentFaction)
		refreshSelectedTalentDetails()
		-- Das SICHTBARE erst nach dem Neuaufbau, und nur wenn jemand hinsieht. renderTree
		-- zerstoert alle Knoten und Adern und baut sie neu -- ein Effekt auf den alten
		-- Instanzen liefe ins Leere.
		if panel.Visible then
			feiereFreischaltung(talentId)
		end
	end
end)

panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible then
		requestState()
		updateResourceDisplay()
		updateResearchBar()
		renderTree(currentFaction)
		-- Beim Oeffnen neu anordnen: solange das Panel zu war, kann sich die
		-- Bildschirmgroesse geaendert haben, ohne dass AbsoluteSize etwas gemeldet hat.
		-- Und der Blick gehoert beim Oeffnen wieder auf die Wurzel.
		layoutColumns()
	end
end)

requestState()
updateResourceDisplay()
updateResearchHud()
renderTree("Kaiju")

-- Nachzügler-Refresh: der allererste requestState()-Aufruf oben kann theoretisch VOR dem
-- serverseitigen Laden der Spielerdaten passieren (DataStore-Ladezeit ist nicht
-- garantiert synchron mit dem Start dieses LocalScripts) -- dann käme "keine laufende
-- Forschung" zurück, obwohl tatsächlich eine läuft, und das HUD-Widget bliebe bis zum
-- manuellen Öffnen des Talent-Fensters unsichtbar. Dieser zweite Aufruf nach kurzer
-- Verzögerung holt den korrekten Zustand zuverlässig nach.
task.delay(3, function()
	requestState()
	updateResourceDisplay()
	updateResearchHud()
end)