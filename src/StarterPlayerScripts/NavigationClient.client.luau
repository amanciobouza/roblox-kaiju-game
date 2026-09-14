-- VERSION: 2026-08-26 #2
-- FEATURE: Diagnose-Print mit Stack-Trace in setPanelVisible ergaenzt
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut die 5 Buttons auf der linken Seite: Skins, Achievements (Platzhalter),
-- Evolution (Skillbaum), Companion (Platzhalter, siehe Companion-Feature-Konzept), Geschenk (Zeit-Belohnungen).
-- Immer nur EIN Panel gleichzeitig sichtbar -- Klick auf einen aktiven Button schließt ihn wieder.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
local ResponsiveGridUtils = require(ReplicatedStorage:WaitForChild("ResponsiveGridUtils"))
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== Lesbare Spaltenbreite =====
-- Seit die Menue-Bildschirme die ganze Flaeche nutzen, laufen Textzeilen ueber die volle
-- Monitorbreite. Das liest sich schlecht: beim Zeilenwechsel findet das Auge den Anfang
-- der naechsten Zeile nicht mehr. Statt den frei werdenden Rand leer zu lassen, wird er
-- mit weiteren Spalten gefuellt -- kurze Zeilen UND mehr Inhalt auf einen Blick.
local MIN_CARD_WIDTH = 460 -- darunter wird eine Achievement-Karte zu eng fuer Name + Balken
local MAX_ACHIEVEMENT_COLUMNS = 3

-- Die Raster-Logik lag frueher hier als lokale Funktion. Seit Archiv und Geschenke sie
-- ebenfalls brauchen, steht sie in ReplicatedStorage.ResponsiveGridUtils -- einmal statt
-- dreimal.

local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local HudToast = require(ReplicatedStorage:WaitForChild("HudToast"))

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NavigationGui"
screenGui.ResetOnSpawn = false
-- AUSDRUECKLICH Sibling, nicht auf die Vorgabe verlassen: unter Global vergleicht Roblox
-- den ZIndex ueber das GANZE ScreenGui hinweg. Das rote Laempchen an einem Leistenknopf
-- (ZIndex 3) lag dadurch VOR einem geoeffneten Vollbild-Panel (ZIndex 1) -- man sah die
-- Punkte durch den Hilfe-Bildschirm hindurch, waehrend die Knoepfe selbst dahinter blieben.
--
-- Unter Sibling zaehlt der ZIndex nur unter Geschwistern, und ein Kind liegt immer ueber
-- seinem Eltern-Element. Ein Panel mit hoeherem ZIndex als die Leiste deckt damit ihren
-- ganzen Teilbaum ab, ohne dass jedes einzelne Kind angehoben werden muesste.
-- Drei andere Bildschirme im Projekt setzen es aus demselben Grund.
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- WICHTIG: hoher DisplayOrder sorgt dafür, dass das Hauptmenü über anderen HUD-Elementen
-- liegt (z.B. dem Berserker-Bonus) -- unabhängig von der Skript-Ladereihenfolge.
screenGui.DisplayOrder = 90
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ===== Ein Knopf statt acht =====
--
-- Hier stand eine Leiste aus acht Symbolen am linken Rand. Der Gedanke dahinter war
-- richtig: ein Knopf, der eine ohnehin schmale Leiste versteckt, spart kaum Flaeche und
-- kostet einen Handgriff.
--
-- Auf dem Telefon stimmte die Voraussetzung nicht. Acht Knoepfe brauchen 408 Pixel, und so
-- viel Hoehe gibt es dort zwischen Robloxs Systemleiste und dem Steuerknueppel nicht -- der
-- oberste lief aus dem Bild. Klemmen liess sich das beheben, aber dann war der linke Rand
-- zur Haelfte von Menuepunkten belegt: viel Platz fuer das Nebensaechlichste im ganzen HUD.
--
-- Also doch ein Knopf und ein Menue dahinter. Der Unterschied zur frueheren Fassung: das
-- Menue zeigt BESCHRIFTETE Kacheln. Die acht Symbole mussten sich vorher allein erklaeren,
-- weil in einer 44 Pixel breiten Leiste kein Text Platz hat -- im Menue ist er da.
local MENU_KNOPF = 52
local MENU_UNTEN = UserInputService.TouchEnabled and 150 or 24

local menuButton = Instance.new("TextButton")
menuButton.Name = "MenuButton"
menuButton.AnchorPoint = Vector2.new(0, 1)
menuButton.Position = UDim2.new(0, 16, 1, -MENU_UNTEN)
menuButton.Size = UDim2.new(0, MENU_KNOPF, 0, MENU_KNOPF)
menuButton.AutoButtonColor = false
menuButton.Text = ""
menuButton.ZIndex = 4
menuButton.Parent = screenGui
local _, menuStroke = HudChrome.Panel(menuButton, { radius = HudChrome.Radius.Small })

local menuIcon = HudChrome.IconImage(menuButton, HudChrome.Icon.Menu)
menuIcon.Size = UDim2.new(1, -16, 1, -16)
menuIcon.Position = UDim2.new(0, 8, 0, 8)
menuIcon.ZIndex = 5

-- Ein Laempchen fuer alle acht.
--
-- Ohne das waere das Verstecken ein echter Verlust: man saehe nicht mehr, dass irgendwo
-- etwas wartet, und muesste das Menue auf Verdacht oeffnen. So sagt der Knopf weiterhin
-- "da ist was", nur nicht mehr, wo -- das steht drin.
local menuBadge = Instance.new("Frame")
menuBadge.Name = "Badge"
menuBadge.AnchorPoint = Vector2.new(1, 0)
menuBadge.Size = UDim2.new(0, 14, 0, 14)
menuBadge.Position = UDim2.new(1, 2, 0, -2)
menuBadge.BackgroundColor3 = HudChrome.Color.Danger
menuBadge.BorderSizePixel = 0
menuBadge.Visible = false
menuBadge.ZIndex = 6
menuBadge.Parent = menuButton
local menuBadgeCorner = Instance.new("UICorner")
menuBadgeCorner.CornerRadius = UDim.new(1, 0)
menuBadgeCorner.Parent = menuBadge

-- ===== Der Puls =====
-- Ein ruhender Punkt uebersieht man neben allem anderen im Bild. Bewegung nicht.
--
-- Bewusst KEIN hartes Blinken: ein Aus-und-An liest sich als Stoerung -- als waere etwas
-- kaputt oder dringend falsch. Ein Laempchen, das sagt "hier wartet etwas", soll ruhig
-- atmen, nicht alarmieren. Deshalb ein weicher Sinus, hin und zurueck, ohne Pause.
--
-- Zwei Ebenen, weil eine allein zu wenig oder zu viel waere:
--   Der Punkt selbst atmet nur leicht (14 auf 17 Pixel) -- mehr liesse ihn wackeln.
--   Ein Ring dahinter geht nach aussen und verschwindet dabei, wie ein Radarsignal. Er
--   traegt die Aufmerksamkeit; der Punkt bleibt dabei ruhig lesbar.
local PULS_DAUER = 1.1

local menuBadgeRing = Instance.new("Frame")
menuBadgeRing.Name = "BadgeRing"
menuBadgeRing.AnchorPoint = Vector2.new(0.5, 0.5)
menuBadgeRing.Position = UDim2.new(0.5, 0, 0.5, 0)
menuBadgeRing.Size = UDim2.new(0, 14, 0, 14)
menuBadgeRing.BackgroundColor3 = HudChrome.Color.Danger
menuBadgeRing.BackgroundTransparency = 0.4
menuBadgeRing.BorderSizePixel = 0
-- HINTER dem Punkt: gleicher Elternknopf, aber niedrigerer ZIndex.
menuBadgeRing.ZIndex = 5
menuBadgeRing.Parent = menuBadge
local menuBadgeRingCorner = Instance.new("UICorner")
menuBadgeRingCorner.CornerRadius = UDim.new(1, 0)
menuBadgeRingCorner.Parent = menuBadgeRing

-- Die beiden Tweens laufen endlos und kehren um (RepeatCount -1, Reverses). Das ist der
-- Grund, warum hier keine Schleife noetig ist: die Bewegung lebt in der Engine und kostet
-- kein Bild pro Sekunde.
local menuBadgePulse = TweenService:Create(
	menuBadge,
	TweenInfo.new(PULS_DAUER, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Size = UDim2.new(0, 17, 0, 17) }
)

-- Der Ring kehrt NICHT um -- er soll nach aussen verschwinden und wieder klein anfangen,
-- nicht zurueckschrumpfen. Deshalb laeuft er nur vorwaerts und wird beim Wiederholen
-- zurueckgesetzt.
local menuBadgeRingPulse = TweenService:Create(
	menuBadgeRing,
	TweenInfo.new(PULS_DAUER, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, false, 0),
	{ Size = UDim2.new(0, 30, 0, 30), BackgroundTransparency = 1 }
)

-- Sichtbarkeit und Puls gehoeren zusammen: ein unsichtbares Laempchen soll nicht animiert
-- werden, und ein sichtbares nicht stillstehen. Deshalb EINE Stelle fuer beides.
local function setMenuBadgeVisible(visible)
	if menuBadge.Visible == visible then
		return
	end
	menuBadge.Visible = visible
	if visible then
		menuBadge.Size = UDim2.new(0, 14, 0, 14)
		menuBadgeRing.Size = UDim2.new(0, 14, 0, 14)
		menuBadgeRing.BackgroundTransparency = 0.4
		menuBadgePulse:Play()
		menuBadgeRingPulse:Play()
	else
		menuBadgePulse:Cancel()
		menuBadgeRingPulse:Cancel()
	end
end

-- ===== Das Menue =====
local KACHEL_BREITE = 148
local KACHEL_HOEHE = 84
local KACHEL_LUECKE = 12
local MENU_SPALTEN = 4
local MENU_RAND = 20
local MENU_KOPF = 52

-- Der Schleier ist selbst ein Knopf: ein Klick daneben schliesst. Das ist auf dem Telefon
-- der natuerlichere Weg als das kleine X zu treffen -- und das X bleibt trotzdem, weil man
-- am Rechner nicht darauf kommt, ins Leere zu klicken.
local menuOverlay = Instance.new("TextButton")
menuOverlay.Name = "MenuOverlay"
menuOverlay.Size = UDim2.new(1, 0, 1, 0)
menuOverlay.BackgroundColor3 = HudChrome.Color.PanelSunken
menuOverlay.BackgroundTransparency = 0.3
menuOverlay.BorderSizePixel = 0
menuOverlay.AutoButtonColor = false
menuOverlay.Text = ""
menuOverlay.Visible = false
menuOverlay.ZIndex = 40
menuOverlay.Parent = screenGui
-- KEINE Gegenskalierung hier. Dieses ScreenGui wird seit dem Wegfall der
-- Navigationsleiste gar nicht mehr skaliert (siehe ResponsiveHudScale) -- eine
-- Gegenskalierung waere jetzt die Stelle, die etwas verschiebt, statt etwas
-- geradezuruecken. Aus demselben Grund ist unscalePanel ganz entfallen.

local menuPanel = Instance.new("Frame")
menuPanel.Name = "MenuPanel"
menuPanel.AnchorPoint = Vector2.new(0.5, 0.5)
menuPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
menuPanel.Size = UDim2.new(
	0, MENU_SPALTEN * KACHEL_BREITE + (MENU_SPALTEN - 1) * KACHEL_LUECKE + MENU_RAND * 2,
	0, MENU_KOPF + 2 * KACHEL_HOEHE + KACHEL_LUECKE + MENU_RAND
)
-- Active: sonst reicht ein Klick auf das Panel bis zum Schleier darunter durch und
-- schliesst das Menue, sobald man danebentrifft.
menuPanel.Active = true
menuPanel.ZIndex = 41
menuPanel.Parent = menuOverlay
HudChrome.Panel(menuPanel, { radius = HudChrome.Radius.Panel, transparency = 0 })

local menuTitle = Instance.new("TextLabel")
menuTitle.Name = "MenuTitle"
menuTitle.Size = UDim2.new(0, 200, 0, 24)
menuTitle.Position = UDim2.new(0, MENU_RAND, 0, 14)
menuTitle.BackgroundTransparency = 1
menuTitle.TextXAlignment = Enum.TextXAlignment.Left
menuTitle.Text = "SYSTEMS"
menuTitle.ZIndex = 42
menuTitle.Parent = menuPanel
HudChrome.Label(menuTitle, 20)

local menuClose = Instance.new("TextButton")
menuClose.Name = "CloseButton"
menuClose.AnchorPoint = Vector2.new(1, 0)
menuClose.Position = UDim2.new(1, -MENU_RAND, 0, 12)
menuClose.Size = UDim2.new(0, 28, 0, 28)
menuClose.AutoButtonColor = false
menuClose.Text = "\u{2715}"
menuClose.ZIndex = 42
menuClose.Parent = menuPanel
HudChrome.Panel(menuClose, { radius = HudChrome.Radius.Small, fill = HudChrome.Color.PanelRaised })
HudChrome.Label(menuClose, 16)
menuClose.TextColor3 = HudChrome.Color.TextSecondary

local menuGrid = Instance.new("Frame")
menuGrid.Name = "MenuGrid"
menuGrid.Position = UDim2.new(0, MENU_RAND, 0, MENU_KOPF)
menuGrid.Size = UDim2.new(1, -MENU_RAND * 2, 0, 2 * KACHEL_HOEHE + KACHEL_LUECKE)
menuGrid.BackgroundTransparency = 1
menuGrid.ZIndex = 42
menuGrid.Parent = menuPanel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, KACHEL_BREITE, 0, KACHEL_HOEHE)
gridLayout.CellPadding = UDim2.new(0, KACHEL_LUECKE, 0, KACHEL_LUECKE)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = menuGrid

-- Der offene Zustand steht am Rand des Knopfes, wie bei jedem anderen Knopf im HUD.
local function setMenuOpen(open)
	menuOverlay.Visible = open
	menuStroke.Color = open and HudChrome.Color.BorderBright or HudChrome.Color.Border
	menuStroke.Thickness = open and 2 or HudChrome.BorderThickness
end

menuButton.MouseButton1Click:Connect(function()
	setMenuOpen(not menuOverlay.Visible)
end)
menuOverlay.MouseButton1Click:Connect(function()
	setMenuOpen(false)
end)
menuClose.MouseButton1Click:Connect(function()
	setMenuOpen(false)
end)

local NAV_BUTTONS = {
	-- Beschriftung "Skins", Schluessel weiterhin "Monster": der Schluessel steht so im
	-- Speicherstand (NavBadge_Monster) und in der Whitelist des NavBadgeService. Ihn
	-- umzubenennen wuerde bei jedem Spieler das gemerkte Laempchen verwerfen -- fuer nichts,
	-- denn sichtbar ist nur das Label.
	{ key = "Monster", icon = "🐲", label = "Skins", color = Color3.fromRGB(80, 200, 90) },
	{ key = "Achievements", icon = "🏆", label = "Achievements", color = Color3.fromRGB(255, 205, 30) },
	{ key = "Talents", icon = "🌟", label = "Talents", color = Color3.fromRGB(60, 170, 220) },
	{ key = "Pets", icon = "🐺", label = "Companion", color = Color3.fromRGB(255, 150, 90) },
	{ key = "Gifts", icon = "🎁", label = "Gift", color = Color3.fromRGB(230, 80, 130) },
	{ key = "Faction", icon = "🦖", label = "Faction", color = Color3.fromRGB(90, 80, 200) },
	{ key = "Archive", icon = "📔", label = "Archive", color = Color3.fromRGB(180, 140, 80) },
	{ key = "Help", icon = "❓", label = "Help", color = Color3.fromRGB(120, 130, 140) },
}

local navButtons = {} -- [key] = TextButton
local navStrokes = {} -- [key] = UIStroke des Knopfes, fuer die Hervorhebung des offenen Punktes

-- Der offene Punkt traegt einen hellen Rand. Das ersetzt, was vorher die Flaechenfarbe
-- geleistet hat -- nur zeigt es jetzt etwas, das sich tatsaechlich aendert, statt acht
-- feste Farben.
local function markiereOffenenPunkt(offenerKey)
	for key, stroke in pairs(navStrokes) do
		if stroke then
			stroke.Color = (key == offenerKey) and HudChrome.Color.BorderBright or HudChrome.Color.Border
			stroke.Thickness = (key == offenerKey) and 2 or HudChrome.BorderThickness
		end
	end
end
local panels = {} -- [key] = GuiObject (das zugehörige Panel, extern gesetzt via registerPanel)
local activePanelKey = nil

-- ===== Gemeinsamer "Zurück"-Button: erscheint bei JEDEM offenen Panel an derselben
-- festen Stelle (unabhängig davon, welches der 6 Panels gerade offen ist), und führt
-- zurück zum Menü-Overlay mit den 6 Buttons, statt alles komplett zu schliessen. =====
local function setPanelVisible(key, visible)
	local panel = panels[key]
	if panel then
		panel.Visible = visible
	end
end

local function closeActivePanel()
	if activePanelKey then
		setPanelVisible(activePanelKey, false)
		activePanelKey = nil
		markiereOffenenPunkt(nil)
	end
end

local function togglePanel(key)
	if activePanelKey == key then
		closeActivePanel()
		return
	end

	closeActivePanel()
	setMenuOpen(false) -- das Menue hat seine Aufgabe erfuellt, sobald ein Punkt offen ist
	setPanelVisible(key, true)
	activePanelKey = key
	markiereOffenenPunkt(key)

	-- Ein Blick genuegt: das Laempchen ist mit dem Oeffnen quittiert. Ausnahme sind die
	-- Geschenke -- was ABHOLBAR ist, soll leuchten, bis es abgeholt wurde; sonst oeffnet
	-- man, wird abgelenkt, und das Geschenk liegt weiter da.
	if key ~= "Gifts" and _G.SetNavBadge then
		_G.SetNavBadge(key, false)
	end
end

-- Kurzes Aufleuchten des Rahmens in der Farbe des Punktes -- zeigt beim Schliessen, wo
-- man herkam. Bewusst ein Farbpuls und kein Groessenpuls: in einer engen Leiste wuerde ein
-- wachsender Knopf seine Nachbarn verschieben. Dieselbe Bewegungssprache nutzen bereits
-- die Geschenke (playReadyGlow) und die Alarmsterne.
local function flashNavButton(key)
	local button = navButtons[key]
	local stroke = button and button:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	local original = stroke.Color
	stroke.Color = Color3.fromRGB(255, 255, 255)
	TweenService:Create(stroke, TweenInfo.new(0.5), { Color = original }):Play()
end

-- Geteilte Funktion, die JEDES Panel bei seinem eigenen "X"-Schliessen-Button aufrufen
-- kann, um zum Menü zurückzukehren -- ersetzt den früheren separaten "← Back"-Button.
-- Panels rufen dies zusätzlich zu ihrem eigenen "panel.Visible = false" auf.
-- Der Name stimmt wieder: seit es ein Menue gibt, fuehrt das Schliessen eines Panels
-- dorthin zurueck -- und nicht ins Spiel. Wer ins Spiel will, schliesst das Menue mit
-- einem zweiten Griff; wer den naechsten Punkt ansehen will, ist schon da. Solange die
-- Punkte am Rand klebten, ging das nicht, und der Name war eine Zeit lang gelogen.
_G.NavReturnToMenu = function()
	local closingKey = activePanelKey
	closeActivePanel()
	if closingKey then
		flashNavButton(closingKey)
	end
	setMenuOpen(true)
end

-- Kurzer Hinweis ohne Panel -- fuer Punkte, hinter denen noch nichts steht.
local activeNavNotice = nil
local function showNavNotice(text)
	if activeNavNotice then
		activeNavNotice:Destroy()
	end
	local notice = Instance.new("TextLabel")
	notice.Size = UDim2.new(0, 260, 0, 40)
	-- Unten in der Mitte und ueber dem Schleier: der Zettel erscheint, waehrend das Menue
	-- offen ist, und laege sonst dahinter.
	notice.AnchorPoint = Vector2.new(0.5, 1)
	notice.Position = UDim2.new(0.5, 0, 1, -MENU_UNTEN)
	notice.ZIndex = 60
	notice.Text = text
	notice.Parent = screenGui
	HudChrome.Panel(notice, { radius = HudChrome.Radius.Small })
	HudChrome.Label(notice, 16)
	notice.TextColor3 = HudChrome.Color.TextSecondary
	activeNavNotice = notice
	task.delay(2, function()
		if notice.Parent then
			notice:Destroy()
		end
		if activeNavNotice == notice then
			activeNavNotice = nil
		end
	end)
end

-- Punkte ohne eigenes System. Companion ist bis heute ein leerer Platzhalter -- kein
-- einziger Treffer im ganzen Projekt ausserhalb dieser Datei. Er bleibt sichtbar, aber
-- ausgegraut: ein Knopf, der auf Druck gar nichts tut, wirkt kaputt, deshalb sagt er kurz,
-- woran es liegt.
local UNBUILT_KEYS = { Pets = true }

local navBadges = {}

-- Eine Kachel je Punkt: Symbol oben, Beschriftung darunter. Genau das, was in der Leiste
-- nicht ging -- dort war Platz fuer 44 Pixel und sonst nichts.
for index, config in ipairs(NAV_BUTTONS) do
	local unbuilt = UNBUILT_KEYS[config.key] == true

	local button = Instance.new("TextButton")
	button.Name = config.key .. "NavButton"
	-- Natuerliche Reihenfolge: das Raster laeuft von links oben nach rechts unten. Die
	-- Leiste musste sie umdrehen, weil sie nach oben wuchs.
	button.LayoutOrder = index
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 43
	button.Parent = menuGrid

	-- Alle Kacheln sehen gleich aus: dunkles Feld, Stahlrand, Symbol, Beschriftung.
	--
	-- Nach der Stilregel bedeutet Farbe im HUD eine MESSUNG. Acht verschiedene Farben, die
	-- nur Menuepunkte auseinanderhalten, sind genau das nicht. Farbe bleibt dem Laempchen
	-- und dem offenen Punkt vorbehalten.
	local _, buttonStroke = HudChrome.Panel(button, {
		radius = HudChrome.Radius.Small,
		fill = HudChrome.Color.PanelRaised,
	})
	navStrokes[config.key] = buttonStroke

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 0, 38)
	icon.Position = UDim2.new(0, 0, 0, 10)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.TextScaled = true
	icon.Text = config.icon
	icon.TextTransparency = unbuilt and 0.6 or 0
	icon.ZIndex = 44
	icon.Parent = button

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.new(1, -12, 0, 22)
	caption.Position = UDim2.new(0, 6, 0, 54)
	caption.BackgroundTransparency = 1
	caption.Text = config.label
	caption.ZIndex = 44
	caption.Parent = button
	HudChrome.Label(caption, 15)
	caption.TextColor3 = unbuilt and HudChrome.Color.TextDim or HudChrome.Color.TextPrimary

	-- Das Laempchen: klein, in der oberen rechten Ecke, standardmaessig aus.
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Size = UDim2.new(0, 12, 0, 12)
	badge.Position = UDim2.new(1, -6, 0, 6)
	badge.BackgroundColor3 = HudChrome.Color.Danger
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.ZIndex = 45
	badge.Parent = button
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge
	navBadges[config.key] = badge

	button.MouseButton1Click:Connect(function()
		if unbuilt then
			showNavNotice(config.label .. " — coming soon")
			return
		end
		togglePanel(config.key)
	end)

	navButtons[config.key] = button
end

-- ===== Lämpchen =====
-- Andere Client-Skripte melden hierüber, dass bei ihrem Punkt etwas wartet -- so muss
-- diese Datei nicht jedes fremde System kennen.
--
-- Bewusst NICHT an Geld oder Energie gekoppelt: ein Lämpchen, das mit dem Kontostand an-
-- und ausgeht, ist kein Hinweis mehr, sondern Flackern, und nach dem dritten Mal sieht
-- niemand mehr hin. Es steht für einmalige Ereignisse -- etwas aufgedeckt, freigeschaltet,
-- fertig erforscht, abholbar.
-- BEWUSST WaitForChild statt RemoteEventUtils.GetOrCreate. Dessen Hilfsfunktion legt das
-- Ereignis notfalls SELBST an -- serverseitig genau richtig, clientseitig eine Falle: der
-- Client erzeugt dann eine rein LOKALE Kopie, und FireServer darauf verpufft lautlos. Die
-- Laempchen wuerden nie gespeichert, ohne jede Fehlermeldung.
--
-- Mit Timeout, damit ein fehlender Dienst nicht das ganze Skript aufhaengt. Ohne den
-- Server funktionieren die Laempchen weiterhin -- nur eben nur fuer diese Sitzung.
local NavBadgeEvent = ReplicatedStorage:WaitForChild("NavBadgeEvent", 20)
if not NavBadgeEvent then
	warn("[NavigationClient] NavBadgeEvent nicht gefunden -- Menue-Laempchen ueberleben "
		.. "den Neustart nicht. Laeuft NavBadgeService?")
end
local NAV_BADGE_PREFIX = "NavBadge_"

-- Nur die Anzeige setzen, ohne den Server zu benachrichtigen. Wird sowohl von
-- _G.SetNavBadge als auch vom Attribut-Horcher benutzt -- letzterer darf NICHT
-- zurueckmelden, sonst liefe die Meldung im Kreis.
local function applyBadge(key, on)
	local badge = navBadges[key]
	if badge then
		badge.Visible = on == true
	end

	-- Das Laempchen am Menue-Knopf leuchtet, sobald IRGENDEINES der acht leuchtet. Ohne das
	-- waere das Verstecken ein echter Verlust: die Laempchen sind der einzige Hinweis, dass
	-- irgendwo etwas wartet, und hinter einem geschlossenen Menue saehe man sie nie.
	local irgendeines = false
	for _, anderes in pairs(navBadges) do
		if anderes.Visible then
			irgendeines = true
			break
		end
	end
	setMenuBadgeVisible(irgendeines)
end

-- [key] = { [itemId] = true } -- WELCHE Eintraege ungesehen sind. Das Laempchen sagt nur,
-- DASS etwas neu ist; die Panels fragen hier nach, um es auch zu zeigen.
local navBadgeItems = {}

_G.SetNavBadge = function(key, on, itemId)
	if navBadges[key] == nil then
		return
	end
	applyBadge(key, on)
	if on then
		if itemId then
			navBadgeItems[key] = navBadgeItems[key] or {}
			navBadgeItems[key][itemId] = true
		end
	else
		navBadgeItems[key] = nil
	end
	if NavBadgeEvent then
		NavBadgeEvent:FireServer(key, on == true, itemId)
	end
end

-- Von den Panels beim Oeffnen abgefragt, um die neuen Eintraege hervorzuheben. Gibt eine
-- Menge zurueck; ein leeres Ergebnis heisst "nichts Einzelnes bekannt", nicht "nichts neu"
-- -- bei den Geschenken etwa leuchtet das Laempchen ohne Einzelangabe.
_G.GetNavBadgeItems = function(key)
	return navBadgeItems[key] or {}
end

_G.HasNavBadge = function(key)
	local badge = navBadges[key]
	return badge ~= nil and badge.Visible
end

-- Wiederherstellen aus dem Speicherstand. Der Server setzt die Attribute erst, wenn er den
-- Speicherstand geladen hat -- das ist nach dem Aufbau dieser Leiste. Deshalb nicht einmal
-- abfragen, sondern auf Aenderungen horchen: dann ist es gleichgueltig, was zuerst fertig
-- ist.
local NAV_ITEMS_PREFIX = "NavBadgeItems_"

for key in pairs(navBadges) do
	local attributeName = NAV_BADGE_PREFIX .. key
	local itemsAttributeName = NAV_ITEMS_PREFIX .. key
	local function sync()
		applyBadge(key, player:GetAttribute(attributeName) == true)
		-- Die Einzeleintraege ebenfalls wiederherstellen, sonst wuesste das Panel nach
		-- einem Neustart zwar, DASS etwas neu ist, aber nicht mehr was.
		local packed = player:GetAttribute(itemsAttributeName)
		if type(packed) == "string" and packed ~= "" then
			local set = {}
			for id in string.gmatch(packed, "[^,]+") do
				set[id] = true
			end
			navBadgeItems[key] = set
		end
	end
	player:GetAttributeChangedSignal(attributeName):Connect(sync)
	player:GetAttributeChangedSignal(itemsAttributeName):Connect(sync)
	sync()
end

-- ===== Monster: ein Skin wird durch das LEVEL erreichbar =====
-- Bewusst nicht an Geld gekoppelt. Ob man sich etwas leisten kann, aendert sich mit jedem
-- Kauf und jeder Zerstoerung -- ein Laempchen, das damit an- und ausgeht, ist Flackern.
-- Das Level dagegen steigt einmal und bleibt.
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 30)
	local levelValue = leaderstats and leaderstats:WaitForChild("Level", 10)
	if not levelValue then
		return
	end
	local SkinsConfig = require(ReplicatedStorage:WaitForChild("SkinsConfig"))
	local lastLevel = levelValue.Value

	levelValue.Changed:Connect(function(newLevel)
		if newLevel <= lastLevel then
			lastLevel = newLevel
			return
		end
		-- Nur Skins, die durch DIESEN Aufstieg neu erreichbar wurden.
		for _, skin in ipairs(SkinsConfig.Skins) do
			local required = skin.RequiredLevel or 0
			if required > lastLevel and required <= newLevel then
				if activePanelKey ~= "Monster" then
					_G.SetNavBadge("Monster", true)
				end
				break
			end
		end
		lastLevel = newLevel
	end)
end)

-- ===== Platzhalter-Panel-Baukasten (für Achievements & Haustiere) =====
local function createPlaceholderPanel(key, title, subtitle, message)
	local schirm = HudChrome.Screen(screenGui, {
		name = key .. "Panel",
		title = title,
		subtitle = subtitle,
	})
	local panel = schirm.panel
	-- Ueber dem Menue-Knopf: siehe ZIndexBehavior oben.
	panel.ZIndex = 5
	-- Auch der Platzhalter ist ein Vollbild-Panel und braucht das Polster.
	TopInsetUtils.Bind(panel)
	schirm.close.MouseButton1Click:Connect(function()
		_G.NavReturnToMenu()
	end)

	local messageLabel = Instance.new("TextLabel")
	-- Mittig und gedeckelt: ueber die volle Vollbildbreite waere es eine einzige lange Zeile.
	messageLabel.AnchorPoint = Vector2.new(0.5, 0)
	messageLabel.Size = UDim2.new(1, -32, 1, -48)
	local messageWidthCap = Instance.new("UISizeConstraint")
	messageWidthCap.MaxSize = Vector2.new(620, math.huge)
	messageWidthCap.Parent = messageLabel
	messageLabel.Position = UDim2.new(0.5, 0, 0, 32)
	messageLabel.BackgroundTransparency = 1
	messageLabel.TextYAlignment = Enum.TextYAlignment.Top
	messageLabel.Text = message
	messageLabel.Parent = schirm.content
	HudChrome.MenuBody(messageLabel)
	messageLabel.TextColor3 = HudChrome.Color.TextSecondary

	panels[key] = panel
	return panel
end

createPlaceholderPanel(
	"Pets",
	"COMPANION",
	"NOT YET BUILT",
	"Coming soon! A personal companion that fights alongside you, grows through your bond, and evolves as you play."
)

-- ===== Echtes Achievement-Panel (ersetzt den bisherigen Platzhalter) =====
local AchievementsConfig = require(ReplicatedStorage:WaitForChild("AchievementsConfig"))
local achievementUnlockedEvent = RemoteEventUtils.GetOrCreate("AchievementUnlockedEvent")

-- "Erfolge" war die letzte deutsche Zeichenkette in diesem Bildschirm; alles andere darin
-- ist englisch. Die Unterzeile zaehlt, wie viele davon erreicht sind -- das war bisher nur
-- zu sehen, wenn man die ganze Liste durchgesehen hat.
local achievementsSchirm = HudChrome.Screen(screenGui, {
	name = "AchievementsPanel",
	title = "ACHIEVEMENTS",
	subtitle = "",
})
local achievementsPanel = achievementsSchirm.panel
local achievementsProgressLabel = achievementsSchirm.subtitle
-- Ueber dem Menue-Knopf: siehe ZIndexBehavior oben.
achievementsPanel.ZIndex = 5

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(achievementsPanel)
panels["Achievements"] = achievementsPanel

achievementsSchirm.close.MouseButton1Click:Connect(function()
	_G.NavReturnToMenu()
end)

local achievementsScroll = Instance.new("ScrollingFrame")
achievementsScroll.Size = UDim2.new(1, -24, 1, -24)
achievementsScroll.Position = UDim2.new(0, 12, 0, 12)
achievementsScroll.BackgroundTransparency = 1
achievementsScroll.BorderSizePixel = 0
achievementsScroll.ScrollBarThickness = 8
achievementsScroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- wird von UIListLayout automatisch gesetzt
achievementsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
achievementsScroll.Parent = achievementsSchirm.content

local achievementsListLayout = Instance.new("UIListLayout")
achievementsListLayout.Padding = UDim.new(0, 6)
achievementsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
achievementsListLayout.Parent = achievementsScroll

-- [achievementId] = { row=, fillBar=, progressLabel= } -- für die laufende Aktualisierung.
local achievementRows = {}

local layoutOrder = 0
local lastCategory = nil
-- Karten der laufenden Kategorie. Die Ueberschrift bleibt eine volle Zeile, die Karten
-- darunter stehen im Raster -- sonst waere jede Karte so breit wie der Bildschirm.
local currentCategoryGrid = nil
for _, achievement in ipairs(AchievementsConfig.List) do
	if achievement.category ~= lastCategory then
		lastCategory = achievement.category
		layoutOrder += 1

		local categoryHeader = Instance.new("TextLabel")
		categoryHeader.Size = UDim2.new(1, 0, 0, 34)
		categoryHeader.BackgroundTransparency = 1
		categoryHeader.TextXAlignment = Enum.TextXAlignment.Left
		categoryHeader.TextYAlignment = Enum.TextYAlignment.Bottom
		categoryHeader.Text = string.upper(lastCategory)
		HudChrome.Label(categoryHeader, HudChrome.MenuTextSize.Section)
		categoryHeader.TextColor3 = HudChrome.Color.TextSecondary
		categoryHeader.LayoutOrder = layoutOrder
		categoryHeader.Parent = achievementsScroll

		layoutOrder += 1
		local categoryFrame = Instance.new("Frame")
		categoryFrame.Name = lastCategory .. "Grid"
		categoryFrame.Size = UDim2.new(1, 0, 0, 0)
		categoryFrame.AutomaticSize = Enum.AutomaticSize.Y
		categoryFrame.BackgroundTransparency = 1
		categoryFrame.LayoutOrder = layoutOrder
		categoryFrame.Parent = achievementsScroll

		currentCategoryGrid = Instance.new("UIGridLayout")
		currentCategoryGrid.CellSize = UDim2.new(0, MIN_CARD_WIDTH, 0, 52)
		currentCategoryGrid.CellPadding = UDim2.new(0, 8, 0, 8)
		currentCategoryGrid.SortOrder = Enum.SortOrder.LayoutOrder
		currentCategoryGrid.Parent = categoryFrame
		ResponsiveGridUtils.Bind(achievementsScroll, currentCategoryGrid, MAX_ACHIEVEMENT_COLUMNS, MIN_CARD_WIDTH)
	end

	layoutOrder += 1
	local row = Instance.new("Frame")
	row.Name = achievement.id .. "Row"
	-- Groesse setzt das Raster; der Wert hier ist nur der Ausgangszustand.
	row.Size = UDim2.new(0, MIN_CARD_WIDTH, 0, 60)
	row.LayoutOrder = layoutOrder
	row.Parent = currentCategoryGrid.Parent
	local _, rowStroke = HudChrome.Panel(row, {
		radius = HudChrome.Radius.Panel,
		fill = HudChrome.Color.PanelRaised,
		transparency = 0,
	})

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 40, 0, 40)
	iconLabel.Position = UDim2.new(0, 10, 0.5, -20)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextScaled = true
	iconLabel.Text = achievement.icon
	iconLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -162, 0, 24)
	nameLabel.Position = UDim2.new(0, 58, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = achievement.name
	HudChrome.Label(nameLabel, HudChrome.MenuTextSize.Caption + 2)
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -162, 0, 20)
	descLabel.Position = UDim2.new(0, 58, 0, 32)
	descLabel.BackgroundTransparency = 1
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Text = achievement.description
	HudChrome.MenuCaption(descLabel, 14)
	descLabel.Parent = row

	local progressBarFrame, progressFill, progressLabel
	if achievement.type == "counter" then
		-- Schacht dunkel, Fuellung bernstein: dieselbe Sprache wie jeder andere Balken im
		-- Spiel. Vorher war der Schacht heller als der Grund und die Fuellung gruen -- gruen
		-- heisst dort ueberall "Leben", und hier hiess es "Fortschritt".
		local track = Instance.new("Frame")
		track.Size = UDim2.new(0, 90, 0, 8)
		track.Position = UDim2.new(1, -102, 0, 12)
		track.BackgroundColor3 = HudChrome.Color.PanelSunken
		track.BorderSizePixel = 0
		track.Parent = row

		progressFill = Instance.new("Frame")
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		progressFill.BackgroundColor3 = HudChrome.Color.Ready
		progressFill.BorderSizePixel = 0
		progressFill.Parent = track

		progressLabel = Instance.new("TextLabel")
		progressLabel.Size = UDim2.new(0, 90, 0, 20)
		progressLabel.Position = UDim2.new(1, -102, 0, 26)
		progressLabel.BackgroundTransparency = 1
		progressLabel.TextXAlignment = Enum.TextXAlignment.Right
		progressLabel.Text = "0/" .. achievement.threshold
		progressLabel.Parent = row
		HudChrome.Number(progressLabel, 14)
		progressLabel.TextColor3 = HudChrome.Color.TextSecondary
		progressBarFrame = track
	end

	-- "NEU"-Fahne: zeigt beim Oeffnen, WELCHES Achievement das Laempchen ausgeloest hat.
	-- Bei einundvierzig Zeilen waere der Grund sonst nicht zu finden.
	local newFlag = Instance.new("TextLabel")
	newFlag.Name = "NewFlag"
	newFlag.AnchorPoint = Vector2.new(1, 0.5)
	newFlag.Size = UDim2.new(0, 42, 0, 18)
	newFlag.Position = UDim2.new(1, -8, 0.5, 0)
	newFlag.Text = "NEW"
	newFlag.Visible = false
	newFlag.ZIndex = 4
	newFlag.Parent = row
	HudChrome.Panel(newFlag, { radius = HudChrome.Radius.Small, fill = HudChrome.Color.Danger })
	HudChrome.Label(newFlag, 12)
	newFlag.TextColor3 = Color3.new(1, 1, 1)

	achievementRows[achievement.id] = {
		row = row,
		rowStroke = rowStroke,
		nameLabel = nameLabel,
		progressFill = progressFill,
		progressLabel = progressLabel,
		newFlag = newFlag,
		achievement = achievement,
	}
end

-- Läuft nur, solange das Panel sichtbar ist -- aktualisiert Fortschritt + Freischaltungs-
-- Optik (gedimmt/normal/dormant).
RunService.Heartbeat:Connect(function()
	if not achievementsPanel.Visible then
		return
	end
	-- Welche Achievements seit dem letzten Oeffnen dazugekommen sind. Kommt aus der
	-- Menueleiste, die es ueber den Neustart hinweg mitfuehrt.
	local fresh = _G.GetNavBadgeItems and _G.GetNavBadgeItems("Achievements") or {}
	local erreicht, gesamt = 0, 0
	for achievementId, rowInfo in pairs(achievementRows) do
		gesamt += 1
		local achievement = rowInfo.achievement
		local unlocked = player:GetAttribute("Achievement_" .. achievementId) == true
		rowInfo.newFlag.Visible = fresh[achievementId] == true

		-- Drei Zustaende, und sie stehen im RAHMEN statt in der Flaeche. Nach der Stilregel
		-- ist der Grund bei allen Feldern derselbe dunkle Ton; wer ihn faerbt, baut ein
		-- zweites Farbsystem neben dem, das schon da ist.
		if achievement.dormant and not unlocked then
			rowInfo.rowStroke.Color = HudChrome.Color.BorderDim
			rowInfo.nameLabel.Text = achievement.name .. "  —  not yet"
			rowInfo.nameLabel.TextColor3 = HudChrome.Color.TextDim
		elseif unlocked then
			rowInfo.rowStroke.Color = HudChrome.Color.Ready
			rowInfo.nameLabel.TextColor3 = HudChrome.Color.Ready
			rowInfo.nameLabel.Text = achievement.name
		else
			rowInfo.rowStroke.Color = HudChrome.Color.Border
			rowInfo.nameLabel.TextColor3 = HudChrome.Color.TextPrimary
			rowInfo.nameLabel.Text = achievement.name
		end

		if achievement.type == "counter" and rowInfo.progressFill then
			local current = player:GetAttribute("Counter_" .. (achievement.counterKey or achievementId)) or 0
			local ratio = math.clamp(current / achievement.threshold, 0, 1)
			rowInfo.progressFill.Size = UDim2.new(ratio, 0, 1, 0)
			rowInfo.progressLabel.Text = math.min(current, achievement.threshold) .. "/" .. achievement.threshold
		end

		if unlocked then
			erreicht += 1
		end
	end

	-- Wie viele von wie vielen -- die Antwort auf die erste Frage an so eine Liste. Sie war
	-- bisher nur zu bekommen, indem man alle einundvierzig Zeilen durchgesehen hat.
	achievementsProgressLabel.Text = string.format("%d of %d unlocked", erreicht, gesamt)
end)

-- ===== Freischaltungs-Meldung =====
--
-- Sie stand oben mittig bei y 20 -- also genau auf den Level- und HP-Feldern, die dort von
-- y 8 bis 70 liegen. Im Moment des Erfolgs verdeckte sie die Lebensanzeige.
--
-- Jetzt uebernimmt HudToast: oben links, hereinfahrend, nacheinander. Dort steht sie
-- niemandem im Weg, und sie sieht aus wie die Archiv-Meldung, weil sie dasselbe ist -- eine
-- Belohnung, kein Ereignis im Kampf.
achievementUnlockedEvent.OnClientEvent:Connect(function(achievementId)
	-- Laempchen am Menuepunkt. Nicht setzen, waehrend das Panel offen ist -- wer gerade
	-- hinsieht, braucht keinen Hinweis darauf, hinzusehen.
	if activePanelKey ~= "Achievements" and _G.SetNavBadge then
		_G.SetNavBadge("Achievements", true, achievementId)
	end
	-- Fraktions-Achievements sind zugleich das einzige Signal fuer eine neu
	-- freigeschaltete Fraktion: einen eigenen Freischalt-Push gibt es nicht, der
	-- AchievementService pollt dafuer.
	if achievementId == "JaegerUnlocked" or achievementId == "RoninUnlocked" then
		if activePanelKey ~= "Faction" and _G.SetNavBadge then
			_G.SetNavBadge("Faction", true)
		end
	end

	local achievement = AchievementsConfig.ById[achievementId]
	if not achievement then
		return
	end

	HudToast.Show({
		title = "ACHIEVEMENT UNLOCKED",
		detail = achievement.name,
		glyph = achievement.icon,
		color = HudChrome.Color.Ready,
	})
end)

-- ===== Anbindung an bestehende/andere Panels =====
-- Monster-Panel = der schon vorhandene Skin-Shop (aus SkinSelectionGui.lua)
-- Liegt seit dem Vollbild-Umbau in einem EIGENEN ScreenGui, nicht mehr in GameHud: dort
-- teilte es sich die Ebene mit dem HUD, das dadurch durchschien.
task.spawn(function()
	local shopGui = playerGui:WaitForChild("SkinShopGui")
	local shopFrame = shopGui:WaitForChild("ShopFrame")
	panels["Monster"] = shopFrame
end)

-- Geschenk-Panel (aus GiftClient.lua)
task.spawn(function()
	local giftGui = playerGui:WaitForChild("GiftGui")
	local giftPanel = giftGui:WaitForChild("GiftPanel")
	panels["Gifts"] = giftPanel
end)

-- Fraktions-Panel (aus EnergyTypesClient.lua) -- ebenfalls in ein eigenes ScreenGui
-- umgezogen, es lag zuvor neben dem Ereignis-Banner und dem Countdown.
task.spawn(function()
	local factionGui = playerGui:WaitForChild("FactionGui")
	local factionPanel = factionGui:WaitForChild("FactionPanel")
	panels["Faction"] = factionPanel
end)

-- Talentbaum-Panel (aus TalentTreeClient.lua)
task.spawn(function()
	local talentTreeGui = playerGui:WaitForChild("TalentTreeGui")
	local talentTreePanel = talentTreeGui:WaitForChild("TalentTreePanel")
	panels["Talents"] = talentTreePanel
end)

-- Archiv-Panel (aus ArchiveClient.lua)
task.spawn(function()
	local archiveGui = playerGui:WaitForChild("ArchiveGui")
	local archivePanel = archiveGui:WaitForChild("ArchivePanel")
	panels["Archive"] = archivePanel
end)

-- ===== Hilfeseite =====
local HelpConfig = require(ReplicatedStorage:WaitForChild("HelpConfig"))

local helpSchirm = HudChrome.Screen(screenGui, {
	name = "HelpPanel",
	title = "HELP",
	subtitle = "HOW THIS WORKS",
})
local helpPanel = helpSchirm.panel
-- Ueber dem Menue-Knopf: siehe ZIndexBehavior oben.
helpPanel.ZIndex = 5

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(helpPanel)
panels["Help"] = helpPanel

helpSchirm.close.MouseButton1Click:Connect(function()
	_G.NavReturnToMenu()
end)

local helpScroll = Instance.new("ScrollingFrame")
helpScroll.Size = UDim2.new(1, -24, 1, -24)
helpScroll.Position = UDim2.new(0, 12, 0, 12)
helpScroll.BackgroundTransparency = 1
helpScroll.BorderSizePixel = 0
helpScroll.ScrollBarThickness = 8
helpScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
helpScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
helpScroll.Parent = helpSchirm.content

local helpListLayout = Instance.new("UIListLayout")
helpListLayout.Padding = UDim.new(0, 14)
helpListLayout.SortOrder = Enum.SortOrder.LayoutOrder
helpListLayout.Parent = helpScroll

-- ===== Zwei Spalten fuer die Hilfe =====
-- Die Abschnitte sind unterschiedlich hoch (verschieden viele Stichpunkte), deshalb kein
-- Raster: ein Raster erzwingt gleiche Zellenhoehe und wuerde die langen Abschnitte
-- abschneiden. Zwei Spalten mit je eigener Liste wachsen unabhaengig voneinander.
helpListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local HELP_COLUMN_GAP = 16
local HELP_MAX_SINGLE_WIDTH = 760 -- eine Spalte darf nicht bildschirmbreit werden
local HELP_TWO_COLUMN_FROM = 1160 -- ab hier passen zwei lesbare Spalten nebeneinander

local helpColumnRow = Instance.new("Frame")
helpColumnRow.Name = "HelpColumns"
helpColumnRow.Size = UDim2.new(1, 0, 0, 0)
helpColumnRow.AutomaticSize = Enum.AutomaticSize.Y
helpColumnRow.BackgroundTransparency = 1
helpColumnRow.Parent = helpScroll

local helpColumnRowLayout = Instance.new("UIListLayout")
helpColumnRowLayout.FillDirection = Enum.FillDirection.Horizontal
helpColumnRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
helpColumnRowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
helpColumnRowLayout.Padding = UDim.new(0, HELP_COLUMN_GAP)
helpColumnRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
helpColumnRowLayout.Parent = helpColumnRow

local helpColumns = {}
for columnIndex = 1, 2 do
	local column = Instance.new("Frame")
	column.Name = "HelpColumn" .. columnIndex
	column.Size = UDim2.new(0, HELP_MAX_SINGLE_WIDTH, 0, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.BackgroundTransparency = 1
	column.LayoutOrder = columnIndex
	column.Parent = helpColumnRow

	local columnLayout = Instance.new("UIListLayout")
	columnLayout.Padding = UDim.new(0, 14)
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.Parent = column

	helpColumns[columnIndex] = column
end

-- In Aufbaureihenfolge, damit beim Umverteilen die Reihenfolge erhalten bleibt.
local helpSectionOrder = {}

-- [sectionId] = Frame -- fürs direkte Anspringen von einem Kontext-Hilfe-Button aus.
local helpSectionFrames = {}

-- ===== Einfache gebaute Diagramme (Platzhalter statt echter Screenshots) =====
local function buildDiagram(diagramType, parent)
	local diagramFrame = Instance.new("Frame")
	diagramFrame.Name = "Diagram"
	diagramFrame.Size = UDim2.new(1, 0, 0, 50)
	diagramFrame.BackgroundTransparency = 1
	diagramFrame.Parent = parent

	if diagramType == "training" then
		local labels = { { "💪", Color3.fromRGB(220, 90, 220) }, { "🦵", Color3.fromRGB(255, 150, 60) }, { "💓", Color3.fromRGB(90, 220, 130) } }
		for i, entry in ipairs(labels) do
			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 100, 0, 14)
			bar.Position = UDim2.new(0, (i - 1) * 140, 0, 18)
			bar.BackgroundColor3 = entry[2]
			bar.BorderSizePixel = 0
			bar.Parent = diagramFrame
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(0, 24, 0, 24)
			icon.Position = UDim2.new(0, (i - 1) * 140, 0, -6)
			icon.BackgroundTransparency = 1
			icon.TextScaled = true
			icon.Text = entry[1]
			icon.Parent = diagramFrame
		end
	elseif diagramType == "alert" then
		for i = 1, 5 do
			local star = Instance.new("TextLabel")
			star.Size = UDim2.new(0, 36, 0, 36)
			star.Position = UDim2.new(0, (i - 1) * 44, 0, 6)
			star.BackgroundTransparency = 1
			star.TextScaled = true
			star.TextColor3 = HudChrome.Color.Ready
			star.Text = "★"
			star.Parent = diagramFrame
		end
	elseif diagramType == "heat" then
		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, 0, 0, 20)
		track.Position = UDim2.new(0, 0, 0, 16)
		track.BackgroundColor3 = HudChrome.Color.PanelSunken
		track.BorderSizePixel = 0
		track.Parent = diagramFrame
		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, HudChrome.Radius.Small)
		trackCorner.Parent = track
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 130, 210)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(210, 175, 50)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(210, 115, 25)),
			ColorSequenceKeypoint.new(0.85, Color3.fromRGB(210, 25, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 20, 190)),
		})
		gradient.Parent = track
	elseif diagramType == "energy" then
		local ring = Instance.new("Frame")
		ring.Size = UDim2.new(0, 50, 0, 50)
		ring.Position = UDim2.new(0, 4, 0, 4)
		ring.BackgroundColor3 = Color3.fromRGB(70, 210, 255)
		ring.Parent = diagramFrame
		local ringCorner = Instance.new("UICorner")
		ringCorner.CornerRadius = UDim.new(0.5, 0)
		ringCorner.Parent = ring
		local ringInner = Instance.new("Frame")
		ringInner.Size = UDim2.new(0, 34, 0, 34)
		ringInner.AnchorPoint = Vector2.new(0.5, 0.5)
		ringInner.Position = UDim2.new(0.5, 0, 0.5, 0)
		ringInner.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
		ringInner.Parent = ring
		local ringInnerCorner = Instance.new("UICorner")
		ringInnerCorner.CornerRadius = UDim.new(0.5, 0)
		ringInnerCorner.Parent = ringInner
	elseif diagramType == "factions" then
		local icons = { "🦖", "🤖", "🐯" }
		for i, iconText in ipairs(icons) do
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(0, 44, 0, 44)
			icon.Position = UDim2.new(0, (i - 1) * 60, 0, 3)
			icon.BackgroundTransparency = 1
			icon.TextScaled = true
			icon.Text = iconText
			icon.Parent = diagramFrame
		end
	end

	return diagramFrame
end

for index, section in ipairs(HelpConfig.Sections) do
	local sectionFrame = Instance.new("Frame")
	sectionFrame.Name = section.id .. "Section"
	sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
	sectionFrame.Size = UDim2.new(1, 0, 0, 0)
	sectionFrame.LayoutOrder = index
	sectionFrame.Parent = helpColumns[1]
	helpSectionOrder[index] = sectionFrame
	HudChrome.Panel(sectionFrame, {
		radius = HudChrome.Radius.Panel,
		fill = HudChrome.Color.PanelRaised,
		transparency = 0,
	})
	helpSectionFrames[section.id] = sectionFrame

	local sectionPadding = Instance.new("UIPadding")
	sectionPadding.PaddingTop = UDim.new(0, 10)
	sectionPadding.PaddingBottom = UDim.new(0, 10)
	sectionPadding.PaddingLeft = UDim.new(0, 12)
	sectionPadding.PaddingRight = UDim.new(0, 12)
	sectionPadding.Parent = sectionFrame

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.Padding = UDim.new(0, 4)
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Parent = sectionFrame

	local sectionTitle = Instance.new("TextLabel")
	sectionTitle.Size = UDim2.new(1, 0, 0, 32)
	sectionTitle.BackgroundTransparency = 1
	sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
	sectionTitle.TextYAlignment = Enum.TextYAlignment.Bottom
	sectionTitle.Text = section.icon .. "  " .. section.title
	HudChrome.Label(sectionTitle, HudChrome.MenuTextSize.Section)
	sectionTitle.LayoutOrder = 1
	sectionTitle.Parent = sectionFrame

	local sectionSummary = Instance.new("TextLabel")
	sectionSummary.Size = UDim2.new(1, 0, 0, 36)
	sectionSummary.BackgroundTransparency = 1
	sectionSummary.TextXAlignment = Enum.TextXAlignment.Left
	sectionSummary.TextYAlignment = Enum.TextYAlignment.Top
	sectionSummary.Text = section.summary
	HudChrome.MenuCaption(sectionSummary)
	sectionSummary.LayoutOrder = 2
	sectionSummary.Parent = sectionFrame

	local diagram = buildDiagram(section.diagramType, sectionFrame)
	diagram.LayoutOrder = 3

	for pointIndex, pointText in ipairs(section.points) do
		local pointLabel = Instance.new("TextLabel")
		pointLabel.Size = UDim2.new(1, 0, 0, 24)
		pointLabel.BackgroundTransparency = 1
		pointLabel.TextXAlignment = Enum.TextXAlignment.Left
		pointLabel.TextYAlignment = Enum.TextYAlignment.Top
		pointLabel.Text = "— " .. pointText
		HudChrome.MenuBody(pointLabel, HudChrome.MenuTextSize.Caption)
		pointLabel.LayoutOrder = 3 + pointIndex
		pointLabel.Parent = sectionFrame
	end
end

-- Verteilt die Abschnitte auf eine oder zwei Spalten, je nach Bildschirmbreite. Bei zwei
-- Spalten abwechselnd -- so liest sich die Reihenfolge zeilenweise von links nach rechts,
-- wie man es von einer Seite erwartet.
local helpColumnCount = 0
local function layoutHelpColumns()
	local width = ResponsiveGridUtils.UsableWidth(helpScroll)
	if width <= 0 then
		return
	end
	local columns = width >= HELP_TWO_COLUMN_FROM and 2 or 1
	local columnWidth
	if columns == 2 then
		columnWidth = math.floor((width - HELP_COLUMN_GAP) / 2)
	else
		columnWidth = math.min(width, HELP_MAX_SINGLE_WIDTH)
	end
	helpColumns[1].Size = UDim2.new(0, columnWidth, 0, 0)
	helpColumns[2].Size = UDim2.new(0, columnWidth, 0, 0)
	helpColumns[2].Visible = columns == 2

	if columns == helpColumnCount then
		return -- nur die Breite hat sich geaendert, das Umhaengen waere umsonst
	end
	helpColumnCount = columns
	for index, sectionFrame in ipairs(helpSectionOrder) do
		sectionFrame.Parent = helpColumns[columns == 2 and ((index - 1) % 2) + 1 or 1]
	end
end

helpScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHelpColumns)
layoutHelpColumns()

-- Öffnet die Hilfeseite und springt optional direkt zu einem Abschnitt (z.B. vom
-- Trainingspanel-Hilfe-Button aus). sectionId ist optional -- ohne Angabe öffnet sich
-- einfach die Seite ganz oben.
_G.OpenHelpPanel = function(sectionId)
	closeActivePanel()
	setPanelVisible("Help", true)
	activePanelKey = "Help"
	markiereOffenenPunkt("Help")
	if sectionId and helpSectionFrames[sectionId] then
		task.defer(function()
			helpScroll.CanvasPosition = Vector2.new(0, helpSectionFrames[sectionId].Position.Y.Offset)
		end)
	end
end

-- Wird im ganzen Projekt von NIEMANDEM aufgerufen -- nur definiert. Bleibt als Notausgang
-- stehen (etwa fuer eine Kinosequenz, die alles schliessen muss), aber ohne das Overlay,
-- das es frueher mitschloss.
_G.CloseNavPanels = function()
	closeActivePanel()
end