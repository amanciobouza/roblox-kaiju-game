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
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local UiTypography = require(ReplicatedStorage:WaitForChild("UiTypography"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
local applyComicStyle = ComicStyleUtils.Apply
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Comic-Style Hilfsfunktion jetzt über ComicStyleUtils (siehe oben)

-- ===== Lesbare Spaltenbreite =====
-- Seit die Menue-Bildschirme die ganze Flaeche nutzen, laufen Textzeilen ueber die volle
-- Monitorbreite. Das liest sich schlecht: beim Zeilenwechsel findet das Auge den Anfang
-- der naechsten Zeile nicht mehr. Statt den frei werdenden Rand leer zu lassen, wird er
-- mit weiteren Spalten gefuellt -- kurze Zeilen UND mehr Inhalt auf einen Blick.
local MIN_CARD_WIDTH = 460 -- darunter wird eine Achievement-Karte zu eng fuer Name + Balken
local MAX_ACHIEVEMENT_COLUMNS = 3

-- Breite des Behaelters ohne Rollbalken. AbsoluteSize enthaelt ihn mit; wer damit rechnet,
-- bekommt eine Spalte zu viel und dann waagrechtes Rollen.
local function usableWidth(container)
	if container:IsA("ScrollingFrame") then
		return container.AbsoluteWindowSize.X - container.ScrollBarThickness
	end
	return container.AbsoluteSize.X
end

-- Verteilt die Breite von `container` auf so viele Spalten, wie bei `minCardWidth`
-- hineinpassen (hoechstens `maxColumns`), und setzt die Zellenbreite des Rasters.
local function bindResponsiveGrid(container, grid, maxColumns, minCardWidth)
	local function apply()
		local width = usableWidth(container)
		if width <= 0 then
			return
		end
		local gap = grid.CellPadding.X.Offset
		local columns = math.clamp(math.floor((width + gap) / (minCardWidth + gap)), 1, maxColumns)
		local cellWidth = math.floor((width - (columns - 1) * gap) / columns)
		grid.CellSize = UDim2.new(0, cellWidth, 0, grid.CellSize.Y.Offset)
	end
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	apply()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NavigationGui"
screenGui.ResetOnSpawn = false
-- WICHTIG: hoher DisplayOrder sorgt dafür, dass das Hauptmenü über anderen HUD-Elementen
-- liegt (z.B. dem Berserker-Bonus) -- unabhängig von der Skript-Ladereihenfolge.
screenGui.DisplayOrder = 90
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ===== Menüleiste unten links =====
-- Ersetzt den früheren Hamburger-Knopf samt zentriertem Overlay. Die Punkte kleben jetzt
-- dauerhaft am Rand: ein Knopf, der eine ohnehin schmale Leiste versteckt, spart kaum
-- Fläche und kostet einen Handgriff.
--
-- Nur Symbole, keine Beschriftung -- die Symbole sind eingeführt und unterscheidbar, und
-- eine Beschriftung beim Darüberfahren würde ausgerechnet auf dem Handy versagen, wo der
-- Platz knapp ist.
local RAIL_ICON_SIZE = 44
local RAIL_PADDING = 8

-- Auf Touch-Geräten sitzt Robloxs EIGENER Steuerknüppel unten links, und der Daumen
-- wandert beim Laufen darüber hinaus. Die Leiste beginnt dort deutlich höher. Lieber
-- etwas zu hoch als ein Knopf, den man beim Laufen versehentlich trifft -- der Fehler
-- geht damit in die harmlose Richtung.
--
-- Um kleine Bildschirme muss sich das hier NICHT kümmern: ResponsiveHudScale hängt an
-- jedes ScreenGui eine UIScale (Referenz 1280x720, Minimum 0.55). Eigenes Verkleinern
-- würde doppelt skalieren.
local RAIL_BOTTOM_MARGIN = UserInputService.TouchEnabled and 300 or 24

local menuRail = Instance.new("Frame")
menuRail.Name = "MenuRail"
menuRail.AnchorPoint = Vector2.new(0, 1)
menuRail.Position = UDim2.new(0, 16, 1, -RAIL_BOTTOM_MARGIN)
menuRail.Size = UDim2.new(0, RAIL_ICON_SIZE, 0, 0)
menuRail.AutomaticSize = Enum.AutomaticSize.Y
menuRail.BackgroundTransparency = 1
menuRail.Parent = screenGui

local railLayout = Instance.new("UIListLayout")
railLayout.FillDirection = Enum.FillDirection.Vertical
railLayout.SortOrder = Enum.SortOrder.LayoutOrder
railLayout.Padding = UDim.new(0, RAIL_PADDING)
railLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
railLayout.Parent = menuRail


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
	end
end

local function togglePanel(key)
	if activePanelKey == key then
		closeActivePanel()
		return
	end

	closeActivePanel()
	setPanelVisible(key, true)
	activePanelKey = key

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
-- HINWEIS ZUM NAMEN: es gibt kein Menü mehr, zu dem zurückgekehrt werden könnte -- die
-- Funktion schliesst das Panel und gibt frei ins Spiel. Der Name bleibt trotzdem, weil ihn
-- fünf andere Dateien aufrufen (Archiv, Geschenke, Fraktion, Talente, Skin-Shop); sie
-- umzubenennen hiesse, fünf Systeme anzufassen, um einen Namen zu verbessern.
_G.NavReturnToMenu = function()
	local closingKey = activePanelKey
	closeActivePanel()
	if closingKey then
		flashNavButton(closingKey)
	end
end

-- Kurzer Hinweis ohne Panel -- fuer Punkte, hinter denen noch nichts steht.
local activeNavNotice = nil
local function showNavNotice(text)
	if activeNavNotice then
		activeNavNotice:Destroy()
	end
	local notice = Instance.new("TextLabel")
	notice.AnchorPoint = Vector2.new(0, 1)
	notice.Size = UDim2.new(0, 260, 0, 40)
	notice.Position = UDim2.new(0, 16 + RAIL_ICON_SIZE + 12, 1, -RAIL_BOTTOM_MARGIN)
	notice.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
	notice.Font = Enum.Font.FredokaOne
	notice.TextScaled = true
	notice.TextColor3 = Color3.fromRGB(230, 230, 240)
	notice.Text = text
	notice.Parent = screenGui
	applyComicStyle(notice, 10, 3)
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

for index, config in ipairs(NAV_BUTTONS) do
	local unbuilt = UNBUILT_KEYS[config.key] == true

	local button = Instance.new("TextButton")
	button.Name = config.key .. "NavButton"
	-- UMGEKEHRTE Reihenfolge: die Leiste waechst nach oben, der erste Punkt soll aber
	-- unten sitzen. Dort ist der Abstand zum Bildschirmrand fest -- er bleibt an
	-- derselben Stelle, egal wie viele Punkte es gibt.
	button.LayoutOrder = #NAV_BUTTONS - index + 1
	button.Size = UDim2.new(0, RAIL_ICON_SIZE, 0, RAIL_ICON_SIZE)
	button.BackgroundColor3 = unbuilt and Color3.fromRGB(58, 58, 66) or config.color
	button.AutoButtonColor = not unbuilt
	button.Text = ""
	button.Parent = menuRail
	applyComicStyle(button, 12, 3)

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(1, -8, 1, -8)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.LuckiestGuy
	icon.TextScaled = true
	icon.Text = config.icon
	icon.TextTransparency = unbuilt and 0.55 or 0
	icon.Parent = button

	-- Das Laempchen: klein, in der oberen rechten Ecke, standardmaessig aus.
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Size = UDim2.new(0, 12, 0, 12)
	badge.Position = UDim2.new(1, 1, 0, -1)
	badge.BackgroundColor3 = Color3.fromRGB(235, 45, 45)
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.ZIndex = 3
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
local function createPlaceholderPanel(key, title, message)
	local panel = Instance.new("Frame")
	panel.Name = key .. "Panel"
	panel.Size = UDim2.new(1, 0, 1, 0)
	panel.Position = UDim2.new(0, 0, 0, 0)
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	panel.Visible = false
	panel.Parent = screenGui
	applyComicStyle(panel, 20, 5)
	-- Auch der Platzhalter ist ein Vollbild-Panel und braucht das Polster.
	TopInsetUtils.Bind(panel)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -16, 0, 44)
	titleLabel.Position = UDim2.new(0, 8, 0, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
	titleLabel.Text = title
	titleLabel.Parent = panel

	local messageLabel = Instance.new("TextLabel")
	-- Mittig und gedeckelt: ueber die volle Vollbildbreite waere es eine einzige lange Zeile.
	messageLabel.AnchorPoint = Vector2.new(0.5, 0)
	messageLabel.Size = UDim2.new(1, -32, 1, -70)
	local messageWidthCap = Instance.new("UISizeConstraint")
	messageWidthCap.MaxSize = Vector2.new(620, math.huge)
	messageWidthCap.Parent = messageLabel
	messageLabel.Position = UDim2.new(0.5, 0, 0, 60)
	messageLabel.BackgroundTransparency = 1
	UiTypography.Body(messageLabel)
	messageLabel.TextWrapped = true
	messageLabel.TextColor3 = Color3.fromRGB(165, 165, 180)
	messageLabel.Text = message
	messageLabel.Parent = panel

	panels[key] = panel
	return panel
end

createPlaceholderPanel("Pets", "🐺 Companion", "Coming soon! A personal companion that fights alongside you, grows through your bond, and evolves as you play.")

-- ===== Echtes Achievement-Panel (ersetzt den bisherigen Platzhalter) =====
local AchievementsConfig = require(ReplicatedStorage:WaitForChild("AchievementsConfig"))
local achievementUnlockedEvent = RemoteEventUtils.GetOrCreate("AchievementUnlockedEvent")

local achievementsPanel = Instance.new("Frame")
achievementsPanel.Name = "AchievementsPanel"
-- Vollbild: alle Menü-Bildschirme nutzen die ganze Fläche.
achievementsPanel.Size = UDim2.new(1, 0, 1, 0)
achievementsPanel.Position = UDim2.new(0, 0, 0, 0)
achievementsPanel.AnchorPoint = Vector2.new(0, 0)
achievementsPanel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
achievementsPanel.Visible = false
achievementsPanel.Parent = screenGui
applyComicStyle(achievementsPanel, 20, 5)

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(achievementsPanel)
panels["Achievements"] = achievementsPanel

local achievementsTitleLabel = Instance.new("TextLabel")
achievementsTitleLabel.Size = UDim2.new(1, -70, 0, 40)
achievementsTitleLabel.Position = UDim2.new(0, 8, 0, 10)
achievementsTitleLabel.BackgroundTransparency = 1
achievementsTitleLabel.Font = Enum.Font.LuckiestGuy
achievementsTitleLabel.TextScaled = true
achievementsTitleLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
achievementsTitleLabel.Text = "🏆 Erfolge"
achievementsTitleLabel.Parent = achievementsPanel

local achievementsCloseButton = Instance.new("TextButton")
achievementsCloseButton.Name = "AchievementsCloseButton"
achievementsCloseButton.Size = UDim2.new(0, 44, 0, 44)
achievementsCloseButton.AnchorPoint = Vector2.new(1, 0)
achievementsCloseButton.Position = UDim2.new(1, -8, 0, 8)
achievementsCloseButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
achievementsCloseButton.Font = Enum.Font.FredokaOne
achievementsCloseButton.TextScaled = true
achievementsCloseButton.TextColor3 = Color3.new(1, 1, 1)
achievementsCloseButton.Text = "X"
achievementsCloseButton.Parent = achievementsPanel
applyComicStyle(achievementsCloseButton, 10, 2)
achievementsCloseButton.MouseButton1Click:Connect(function()
	_G.NavReturnToMenu()
end)

local achievementsScroll = Instance.new("ScrollingFrame")
achievementsScroll.Size = UDim2.new(1, -24, 1, -62)
achievementsScroll.Position = UDim2.new(0, 12, 0, 56)
achievementsScroll.BackgroundTransparency = 1
achievementsScroll.BorderSizePixel = 0
achievementsScroll.ScrollBarThickness = 8
achievementsScroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- wird von UIListLayout automatisch gesetzt
achievementsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
achievementsScroll.Parent = achievementsPanel

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
		categoryHeader.Size = UDim2.new(1, 0, 0, 26)
		categoryHeader.BackgroundTransparency = 1
		categoryHeader.Font = Enum.Font.LuckiestGuy
		categoryHeader.TextScaled = true
		categoryHeader.TextXAlignment = Enum.TextXAlignment.Left
		categoryHeader.TextColor3 = Color3.fromRGB(255, 205, 90)
		categoryHeader.Text = lastCategory
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
		bindResponsiveGrid(achievementsScroll, currentCategoryGrid, MAX_ACHIEVEMENT_COLUMNS, MIN_CARD_WIDTH)
	end

	layoutOrder += 1
	local row = Instance.new("Frame")
	row.Name = achievement.id .. "Row"
	-- Groesse setzt das Raster; der Wert hier ist nur der Ausgangszustand.
	row.Size = UDim2.new(0, MIN_CARD_WIDTH, 0, 52)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	row.LayoutOrder = layoutOrder
	row.Parent = currentCategoryGrid.Parent
	applyComicStyle(row, 10, 2)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 40, 0, 40)
	iconLabel.Position = UDim2.new(0, 6, 0, 6)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.FredokaOne
	iconLabel.TextScaled = true
	iconLabel.Text = achievement.icon
	iconLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -158, 0, 20)
	nameLabel.Position = UDim2.new(0, 52, 0, 4)
	nameLabel.BackgroundTransparency = 1
	UiTypography.Subhead(nameLabel, 16)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
	nameLabel.Text = achievement.name
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -158, 0, 16)
	descLabel.Position = UDim2.new(0, 52, 0, 24)
	descLabel.BackgroundTransparency = 1
	UiTypography.Body(descLabel, 14)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextColor3 = Color3.fromRGB(165, 165, 180)
	descLabel.Text = achievement.description
	descLabel.Parent = row

	local progressBarFrame, progressFill, progressLabel
	if achievement.type == "counter" then
		local track = Instance.new("Frame")
		track.Size = UDim2.new(0, 90, 0, 10)
		track.Position = UDim2.new(1, -98, 0, 8)
		track.BackgroundColor3 = Color3.fromRGB(210, 205, 190)
		track.Parent = row
		applyComicStyle(track, 5, 1)

		progressFill = Instance.new("Frame")
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		progressFill.BackgroundColor3 = Color3.fromRGB(90, 200, 110)
		progressFill.BorderSizePixel = 0
		progressFill.Parent = track

		progressLabel = Instance.new("TextLabel")
		progressLabel.Size = UDim2.new(0, 90, 0, 16)
		progressLabel.Position = UDim2.new(1, -98, 0, 20)
		progressLabel.BackgroundTransparency = 1
		progressLabel.Font = Enum.Font.FredokaOne
		progressLabel.TextScaled = true
		progressLabel.TextColor3 = Color3.fromRGB(165, 165, 180)
		progressLabel.Text = "0/" .. achievement.threshold
		progressLabel.Parent = row
		progressBarFrame = track
	end

	-- "NEU"-Fahne: zeigt beim Oeffnen, WELCHES Achievement das Laempchen ausgeloest hat.
	-- Bei einundvierzig Zeilen waere der Grund sonst nicht zu finden.
	local newFlag = Instance.new("TextLabel")
	newFlag.Name = "NewFlag"
	newFlag.AnchorPoint = Vector2.new(1, 0.5)
	newFlag.Size = UDim2.new(0, 42, 0, 18)
	newFlag.Position = UDim2.new(1, -8, 0.5, 0)
	newFlag.BackgroundColor3 = Color3.fromRGB(235, 45, 45)
	newFlag.Font = Enum.Font.FredokaOne
	newFlag.TextScaled = true
	newFlag.TextColor3 = Color3.fromRGB(255, 255, 255)
	newFlag.Text = "NEW"
	newFlag.Visible = false
	newFlag.ZIndex = 4
	newFlag.Parent = row
	applyComicStyle(newFlag, 6, 2)

	achievementRows[achievement.id] = {
		row = row,
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
	for achievementId, rowInfo in pairs(achievementRows) do
		local achievement = rowInfo.achievement
		local unlocked = player:GetAttribute("Achievement_" .. achievementId) == true
		rowInfo.newFlag.Visible = fresh[achievementId] == true

		if achievement.dormant and not unlocked then
			rowInfo.row.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
			rowInfo.nameLabel.Text = achievement.name .. "  🔒 Kommt später"
			rowInfo.nameLabel.TextColor3 = Color3.fromRGB(130, 130, 145)
		elseif unlocked then
			rowInfo.row.BackgroundColor3 = Color3.fromRGB(56, 50, 28)
			rowInfo.nameLabel.TextColor3 = Color3.fromRGB(120, 220, 130)
			rowInfo.nameLabel.Text = "✅ " .. achievement.name
		else
			rowInfo.row.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
			rowInfo.nameLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
			rowInfo.nameLabel.Text = achievement.name
		end

		if achievement.type == "counter" and rowInfo.progressFill then
			local current = player:GetAttribute("Counter_" .. (achievement.counterKey or achievementId)) or 0
			local ratio = math.clamp(current / achievement.threshold, 0, 1)
			rowInfo.progressFill.Size = UDim2.new(ratio, 0, 1, 0)
			rowInfo.progressLabel.Text = math.min(current, achievement.threshold) .. "/" .. achievement.threshold
		end
	end
end)

-- ===== Freischaltungs-Toast: kurze Benachrichtigung, sobald ein Achievement live
-- freigeschaltet wird (auch wenn das Panel gerade nicht offen ist). =====
local achievementToast = Instance.new("Frame")
achievementToast.Name = "AchievementToast"
achievementToast.AnchorPoint = Vector2.new(0.5, 0)
achievementToast.Position = UDim2.new(0.5, 0, 0, -70)
achievementToast.Size = UDim2.new(0, 320, 0, 60)
achievementToast.BackgroundColor3 = Color3.fromRGB(255, 250, 210)
achievementToast.Visible = false
achievementToast.ZIndex = 50
achievementToast.Parent = screenGui
applyComicStyle(achievementToast, 14, 3)

local toastIcon = Instance.new("TextLabel")
toastIcon.Size = UDim2.new(0, 44, 0, 44)
toastIcon.Position = UDim2.new(0, 8, 0, 8)
toastIcon.BackgroundTransparency = 1
toastIcon.Font = Enum.Font.FredokaOne
toastIcon.TextScaled = true
toastIcon.ZIndex = 51
toastIcon.Parent = achievementToast

local toastText = Instance.new("TextLabel")
toastText.Size = UDim2.new(1, -60, 1, -12)
toastText.Position = UDim2.new(0, 56, 0, 6)
toastText.BackgroundTransparency = 1
toastText.Font = Enum.Font.FredokaOne
toastText.TextScaled = true
toastText.TextXAlignment = Enum.TextXAlignment.Left
toastText.TextColor3 = Color3.fromRGB(235, 235, 245)
toastText.ZIndex = 51
toastText.Parent = achievementToast

local toastShowing = false
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
	toastIcon.Text = achievement.icon
	toastText.Text = "🏆 Erfolg freigeschaltet!\n" .. achievement.name

	if toastShowing then
		return
	end
	toastShowing = true
	achievementToast.Visible = true
	TweenService:Create(achievementToast, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 20),
	}):Play()
	task.delay(3, function()
		local slideOut = TweenService:Create(achievementToast, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -70),
		})
		slideOut:Play()
		slideOut.Completed:Connect(function()
			achievementToast.Visible = false
			toastShowing = false
		end)
	end)
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

local helpPanel = Instance.new("Frame")
helpPanel.Name = "HelpPanel"
-- Vollbild: alle Menü-Bildschirme nutzen die ganze Fläche.
helpPanel.Size = UDim2.new(1, 0, 1, 0)
helpPanel.Position = UDim2.new(0, 0, 0, 0)
helpPanel.AnchorPoint = Vector2.new(0, 0)
helpPanel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
helpPanel.Visible = false
helpPanel.Parent = screenGui
applyComicStyle(helpPanel, 20, 5)

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(helpPanel)
panels["Help"] = helpPanel

local helpTitleLabel = Instance.new("TextLabel")
helpTitleLabel.Size = UDim2.new(1, -70, 0, 40)
helpTitleLabel.Position = UDim2.new(0, 8, 0, 10)
helpTitleLabel.BackgroundTransparency = 1
helpTitleLabel.Font = Enum.Font.LuckiestGuy
helpTitleLabel.TextScaled = true
helpTitleLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
helpTitleLabel.Text = "❓ Help"
helpTitleLabel.Parent = helpPanel

local helpCloseButton = Instance.new("TextButton")
helpCloseButton.Name = "HelpCloseButton"
helpCloseButton.Size = UDim2.new(0, 44, 0, 44)
helpCloseButton.AnchorPoint = Vector2.new(1, 0)
helpCloseButton.Position = UDim2.new(1, -8, 0, 8)
helpCloseButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
helpCloseButton.Font = Enum.Font.FredokaOne
helpCloseButton.TextScaled = true
helpCloseButton.TextColor3 = Color3.new(1, 1, 1)
helpCloseButton.Text = "X"
helpCloseButton.Parent = helpPanel
applyComicStyle(helpCloseButton, 10, 2)
helpCloseButton.MouseButton1Click:Connect(function()
	_G.NavReturnToMenu()
end)

local helpScroll = Instance.new("ScrollingFrame")
helpScroll.Size = UDim2.new(1, -24, 1, -62)
helpScroll.Position = UDim2.new(0, 12, 0, 56)
helpScroll.BackgroundTransparency = 1
helpScroll.BorderSizePixel = 0
helpScroll.ScrollBarThickness = 8
helpScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
helpScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
helpScroll.Parent = helpPanel

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
		local labels = { { "💪", Color3.fromRGB(220, 90, 220) }, { "🦵", Color3.fromRGB(255, 150, 60) }, { "🫀", Color3.fromRGB(90, 220, 130) } }
		for i, entry in ipairs(labels) do
			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 100, 0, 14)
			bar.Position = UDim2.new(0, (i - 1) * 140, 0, 18)
			bar.BackgroundColor3 = entry[2]
			bar.Parent = diagramFrame
			applyComicStyle(bar, 6, 1)
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(0, 24, 0, 24)
			icon.Position = UDim2.new(0, (i - 1) * 140, 0, -6)
			icon.BackgroundTransparency = 1
			icon.Font = Enum.Font.FredokaOne
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
			star.Font = Enum.Font.FredokaOne
			star.TextScaled = true
			star.TextColor3 = Color3.fromRGB(255, 210, 80)
			star.Text = "★"
			star.Parent = diagramFrame
		end
	elseif diagramType == "heat" then
		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, 0, 0, 20)
		track.Position = UDim2.new(0, 0, 0, 16)
		track.BackgroundColor3 = Color3.fromRGB(58, 58, 68)
		track.Parent = diagramFrame
		applyComicStyle(track, 8, 1)
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
			icon.Font = Enum.Font.FredokaOne
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
	sectionFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	sectionFrame.LayoutOrder = index
	sectionFrame.Parent = helpColumns[1]
	helpSectionOrder[index] = sectionFrame
	applyComicStyle(sectionFrame, 12, 2)
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
	sectionTitle.Size = UDim2.new(1, 0, 0, 26)
	sectionTitle.BackgroundTransparency = 1
	sectionTitle.Font = Enum.Font.LuckiestGuy
	sectionTitle.TextScaled = true
	sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
	sectionTitle.TextColor3 = Color3.fromRGB(235, 235, 245)
	sectionTitle.Text = section.icon .. " " .. section.title
	sectionTitle.LayoutOrder = 1
	sectionTitle.Parent = sectionFrame

	local sectionSummary = Instance.new("TextLabel")
	sectionSummary.Size = UDim2.new(1, 0, 0, 32)
	sectionSummary.BackgroundTransparency = 1
	UiTypography.Body(sectionSummary)
	sectionSummary.TextXAlignment = Enum.TextXAlignment.Left
	sectionSummary.TextColor3 = Color3.fromRGB(165, 165, 180)
	sectionSummary.Text = section.summary
	sectionSummary.LayoutOrder = 2
	sectionSummary.Parent = sectionFrame

	local diagram = buildDiagram(section.diagramType, sectionFrame)
	diagram.LayoutOrder = 3

	for pointIndex, pointText in ipairs(section.points) do
		local pointLabel = Instance.new("TextLabel")
		pointLabel.Size = UDim2.new(1, 0, 0, 20)
		pointLabel.BackgroundTransparency = 1
		UiTypography.Body(pointLabel)
		pointLabel.TextXAlignment = Enum.TextXAlignment.Left
		pointLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
		pointLabel.Text = "• " .. pointText
		pointLabel.LayoutOrder = 3 + pointIndex
		pointLabel.Parent = sectionFrame
	end
end

-- Verteilt die Abschnitte auf eine oder zwei Spalten, je nach Bildschirmbreite. Bei zwei
-- Spalten abwechselnd -- so liest sich die Reihenfolge zeilenweise von links nach rechts,
-- wie man es von einer Seite erwartet.
local helpColumnCount = 0
local function layoutHelpColumns()
	local width = usableWidth(helpScroll)
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