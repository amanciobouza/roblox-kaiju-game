-- LocalScript: ArchiveClient
-- Ort in Studio: StarterPlayer.StarterPlayerScripts
--
-- Das Archiv: alle Feinde und Figuren als Raster. Verdeckte Einträge zeigen die echte
-- Silhouette mit einem Fragezeichen darüber; ein Klick öffnet den Steckbrief.
--
-- Registriert wird das Panel von NavigationClient über PlayerGui.ArchiveGui.ArchivePanel.
--
-- ===== Woher die Modelle kommen =====
-- Vier verschiedene Wege, weil die Modelle im Projekt an vier verschiedenen Orten liegen:
--   workshopAsset   der Client baut sie selbst aus dem TrenchbornAssetWorkshop
--   avatarScale     Standard-Avatar in Skin-Grösse (Skins haben keine eigenen Modelle)
--   replicatedStorage  liegt bereits beim Client
--   alles andere    liegt in ServerStorage -> ArchiveModelFunction holt es auf Anfrage
--
-- Geholt wird ERST beim Öffnen des Archivs und je Eintrag nur einmal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ArchiveConfig = require(ReplicatedStorage:WaitForChild("ArchiveConfig"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local ModelPreviewUtils = require(ReplicatedStorage:WaitForChild("ModelPreviewUtils"))
local UiTypography = require(ReplicatedStorage:WaitForChild("UiTypography"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))

local ArchiveRevealedEvent = ReplicatedStorage:WaitForChild("ArchiveRevealedEvent", 20)
local ArchiveModelFunction = ReplicatedStorage:WaitForChild("ArchiveModelFunction", 20)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Silhouettenfarbe: ein mittleres Grau, KEIN Schwarz. Der erste Entwurf hatte
-- RGB(16,16,20) -- der Rahmen dahinter ist RGB(18,18,22), also praktisch dieselbe Farbe,
-- und der Umriss war schwarz auf schwarz. Eine Silhouette braucht Kontrast zum Hintergrund,
-- nicht Dunkelheit an sich.
local HIDDEN_TINT = Color3.fromRGB(88, 92, 106)
-- Bewusst kompakt: das Ziel ist, moeglichst ALLE Karten auf einen Blick zu sehen. Bei
-- dieser Groesse passen auf einen ueblichen Bildschirm rund neun je Reihe, die 26
-- Eintraege also in drei Reihen ohne Scrollen.
-- Kartengroesse. Vorher 116x152 -- auf einem Vollbild-Raster wirkten die Figuren darin
-- wie Briefmarken, und die Silhouette, die den Eintrag ausmacht, war kaum zu erkennen.
local CARD_SIZE = UDim2.new(0, 168, 0, 216)

-- ===== Grundgerüst =====

local gui = Instance.new("ScreenGui")
gui.Name = "ArchiveGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- Ohne DisplayOrder stuende das Archiv auf 0 und damit UNTER dem HUD. Die uebrigen Panels
-- im Projekt liegen auf 100 (Talentbaum, StoryBeat), das Hauptmenue auf 90 -- 100 haelt
-- das Archiv in derselben Ebene wie seine Geschwister.
gui.DisplayOrder = 100
-- Ohne das beginnt das ScreenGui UNTERHALB der Roblox-Systemleiste, und oben bleibt ein
-- dünner Streifen mit Sicht auf die Welt stehen.
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Die Meldung braucht ein EIGENES ScreenGui mit hoher DisplayOrder. Innerhalb desselben
-- ScreenGui haette ein hoeherer ZIndex nichts genuetzt: die HUD-Elemente, die sie verdeckt
-- haben, liegen in ANDEREN ScreenGuis, und zwischen ScreenGuis entscheidet allein die
-- DisplayOrder. Deshalb auch nicht im Archiv-Gui, das darf ruhig unten bleiben.
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "ArchiveToastGui"
toastGui.ResetOnSpawn = false
-- Ueber HUD und Hauptmenue (90), aber UNTER den Panels und den Story-Einblendungen
-- (beide 100): waehrend eines geoeffneten Bildschirms oder einer Kinosequenz hat die
-- Meldung nichts im Vordergrund verloren.
toastGui.DisplayOrder = 95
toastGui.IgnoreGuiInset = true
toastGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "ArchivePanel"
-- Vollbild statt zentriertem Rahmen: das Raster lebt davon, moeglichst viele Karten auf
-- einmal zu zeigen. Bei 480 Pixeln Breite passten vier je Reihe, bei voller Breite das
-- Drei- bis Vierfache -- und die Gruppen bleiben als Ganzes sichtbar.
panel.Size = UDim2.new(1, 0, 1, 0)
panel.Position = UDim2.new(0, 0, 0, 0)
panel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
panel.Visible = false
panel.Parent = gui
ComicStyleUtils.Apply(panel, 0, 3)

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(panel)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 260, 0, 40)
title.Position = UDim2.new(0, 24, 0, 12)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "📔 Archive"
title.Parent = panel

local progressLabel = Instance.new("TextLabel")
progressLabel.Size = UDim2.new(0, 120, 0, 20)
progressLabel.Position = UDim2.new(0, 26, 0, 50)
progressLabel.BackgroundTransparency = 1
progressLabel.Font = Enum.Font.Gotham
progressLabel.TextScaled = true
progressLabel.TextXAlignment = Enum.TextXAlignment.Left
progressLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
progressLabel.Text = ""
progressLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 36, 0, 36)
closeButton.Position = UDim2.new(1, -54, 0, 14)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeButton.Font = Enum.Font.FredokaOne
closeButton.TextScaled = true
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Text = "X"
closeButton.Parent = panel
ComicStyleUtils.Apply(closeButton, 10, 3)

-- Zaehler je Gruppe. Ohne Ueberschriften braucht die Aufteilung einen anderen Platz --
-- und die Information "wie viel fehlt wo" ist der halbe Sinn der Sammlung.
local counterStrip = Instance.new("TextLabel")
counterStrip.Size = UDim2.new(1, -300, 0, 26)
counterStrip.Position = UDim2.new(0, 290, 0, 22)
counterStrip.BackgroundTransparency = 1
counterStrip.Font = Enum.Font.Gotham
counterStrip.TextSize = 16
counterStrip.TextXAlignment = Enum.TextXAlignment.Left
counterStrip.TextColor3 = Color3.fromRGB(200, 200, 212)
counterStrip.Text = ""
counterStrip.Parent = panel

-- EIN durchgehendes Raster ueber alle Kategorien hinweg. Bewusst OHNE Gruppen-
-- ueberschriften: sie haetten jede Gruppe auf einer neuen Zeile beginnen lassen, und bei
-- Gruppen mit einem einzigen Eintrag waere die Zeile fast leer geblieben. So ruecken die
-- Karten der naechsten Gruppe nach, und man sieht moeglichst viele auf einmal.
--
-- Die Reihenfolge folgt trotzdem den Kategorien aus dem Config -- das Raster liest sich
-- weiter als Eskalation, vom Verkehrshelikopter bis zu den Figuren.
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -48, 1, -96)
scroll.Position = UDim2.new(0, 24, 0, 80)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = panel

local scrollLayout = Instance.new("UIGridLayout")
scrollLayout.CellSize = CARD_SIZE
scrollLayout.CellPadding = UDim2.new(0, 10, 0, 10)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scroll

-- ===== Steckbrief: eigener Vollbild-Bereich, Rückweg ins Raster =====

local detail = Instance.new("Frame")
detail.Name = "ArchiveDetail"
detail.Size = UDim2.new(1, 0, 1, 0)
detail.Position = UDim2.new(0, 0, 0, 0)
detail.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
detail.Visible = false
detail.Parent = gui
ComicStyleUtils.Apply(detail, 0, 3)

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(detail)

local detailBack = Instance.new("TextButton")
detailBack.Size = UDim2.new(0, 36, 0, 36)
detailBack.Position = UDim2.new(0, 24, 0, 14)
detailBack.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
detailBack.Font = Enum.Font.FredokaOne
detailBack.TextScaled = true
detailBack.TextColor3 = Color3.fromRGB(255, 255, 255)
detailBack.Text = "←"
detailBack.Parent = detail
ComicStyleUtils.Apply(detailBack, 10, 3)

local detailTitle = Instance.new("TextLabel")
detailTitle.Size = UDim2.new(0, 420, 0, 40)
detailTitle.Position = UDim2.new(0, 72, 0, 14)
detailTitle.BackgroundTransparency = 1
detailTitle.Font = Enum.Font.FredokaOne
detailTitle.TextScaled = true
detailTitle.TextXAlignment = Enum.TextXAlignment.Left
detailTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
detailTitle.Text = ""
detailTitle.Parent = detail

local detailViewportHolder = Instance.new("Frame")
detailViewportHolder.Size = UDim2.new(0.38, -32, 1, -140)
detailViewportHolder.Position = UDim2.new(0, 24, 0, 64)
detailViewportHolder.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
detailViewportHolder.Parent = detail
ComicStyleUtils.Apply(detailViewportHolder, 12, 3)

local detailHint = Instance.new("TextLabel")
detailHint.Size = UDim2.new(0.38, -32, 0, 28)
detailHint.Position = UDim2.new(0, 24, 1, -70)
detailHint.BackgroundTransparency = 1
UiTypography.Caption(detailHint, UiTypography.BodySize)
detailHint.TextColor3 = Color3.fromRGB(170, 170, 180)
detailHint.Text = ""
detailHint.Parent = detail

local detailText = Instance.new("ScrollingFrame")
detailText.Size = UDim2.new(0.62, -48, 1, -88)
detailText.Position = UDim2.new(0.38, 8, 0, 64)
detailText.BackgroundTransparency = 1
detailText.BorderSizePixel = 0
detailText.ScrollBarThickness = 5
detailText.AutomaticCanvasSize = Enum.AutomaticSize.Y
detailText.CanvasSize = UDim2.new(0, 0, 0, 0)
detailText.Parent = detail

local detailTextLayout = Instance.new("UIListLayout")
detailTextLayout.SortOrder = Enum.SortOrder.LayoutOrder
detailTextLayout.Padding = UDim.new(0, 8)
detailTextLayout.Parent = detailText

-- ===== Datenspalte rechts =====
-- Der Steckbrief fuellte vorher die ganze Bildschirmbreite; die Zeilen waren so lang, dass
-- das Auge beim Umbruch den Anfang der naechsten nicht mehr fand. Der Fliesstext bekommt
-- deshalb eine Hoechstbreite -- und der frei werdende Streifen rechts traegt die Angaben
-- zum Eintrag, statt leer zu bleiben.
local detailData = Instance.new("Frame")
detailData.Name = "DetailData"
detailData.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
detailData.Visible = false
detailData.Parent = detail
ComicStyleUtils.Apply(detailData, 12, 2)

local detailDataPadding = Instance.new("UIPadding")
detailDataPadding.PaddingTop = UDim.new(0, 12)
detailDataPadding.PaddingBottom = UDim.new(0, 12)
detailDataPadding.PaddingLeft = UDim.new(0, 12)
detailDataPadding.PaddingRight = UDim.new(0, 12)
detailDataPadding.Parent = detailData

local detailDataLayout = Instance.new("UIListLayout")
detailDataLayout.SortOrder = Enum.SortOrder.LayoutOrder
detailDataLayout.Padding = UDim.new(0, 4)
detailDataLayout.Parent = detailData

-- Erzeugt ein Wertepaar: kleine Ueberschrift, darunter der Wert.
local function buildDataField(labelText, order)
	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.BackgroundTransparency = 1
	UiTypography.Caption(caption, 11)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = Color3.fromRGB(120, 120, 132)
	caption.Text = string.upper(labelText)
	caption.LayoutOrder = order
	caption.Parent = detailData

	local value = Instance.new("TextLabel")
	value.Size = UDim2.new(1, 0, 0, 0)
	value.AutomaticSize = Enum.AutomaticSize.Y
	value.BackgroundTransparency = 1
	UiTypography.Body(value, 15)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextYAlignment = Enum.TextYAlignment.Top
	value.TextColor3 = Color3.fromRGB(230, 230, 240)
	value.Text = ""
	value.LayoutOrder = order + 1
	value.Parent = detailData

	-- Abstand zum naechsten Wertepaar, damit die Spalte nicht als ein Block wirkt.
	local spacer = Instance.new("Frame")
	spacer.Size = UDim2.new(1, 0, 0, 10)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = order + 2
	spacer.Parent = detailData

	return value
end

local detailDataCategory = buildDataField("Category", 10)
local detailDataFound = buildDataField("Found at", 20)
local detailDataProgress = buildDataField("Category progress", 30)

-- ===== Aufteilung Modell / Text / Daten =====
-- Der Block wird als Ganzes mittig gesetzt. Waechst der Bildschirm, wird das Modell
-- groesser -- es ist die Belohnung fuers Entdecken --, waehrend die Textspalte ihre
-- lesbare Breite behaelt.
local DETAIL_GAP = 24
local DETAIL_TEXT_MAX = 620
local DETAIL_TEXT_MIN = 320
local DETAIL_DATA_WIDTH = 250
local DETAIL_DATA_FROM = 1180 -- schmaler: die Datenspalte entfaellt, statt alles zu quetschen
local DETAIL_MODEL_MIN = 260
local DETAIL_MODEL_MAX = 560

local function layoutDetail()
	local width = detail.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local dataWidth = width >= DETAIL_DATA_FROM and DETAIL_DATA_WIDTH or 0
	detailData.Visible = dataWidth > 0

	local free = width - 2 * DETAIL_GAP - DETAIL_GAP
	if dataWidth > 0 then
		free -= dataWidth + DETAIL_GAP
	end
	local textWidth = math.clamp(free - DETAIL_MODEL_MIN, DETAIL_TEXT_MIN, DETAIL_TEXT_MAX)
	local modelWidth = math.clamp(free - textWidth, DETAIL_MODEL_MIN, DETAIL_MODEL_MAX)

	local total = modelWidth + DETAIL_GAP + textWidth
	if dataWidth > 0 then
		total += DETAIL_GAP + dataWidth
	end
	local x = math.max(DETAIL_GAP, math.floor((width - total) / 2))

	detailViewportHolder.Position = UDim2.new(0, x, 0, 64)
	detailViewportHolder.Size = UDim2.new(0, modelWidth, 1, -140)
	detailHint.Position = UDim2.new(0, x, 1, -70)
	detailHint.Size = UDim2.new(0, modelWidth, 0, 28)

	x += modelWidth + DETAIL_GAP
	detailText.Position = UDim2.new(0, x, 0, 64)
	detailText.Size = UDim2.new(0, textWidth, 1, -88)

	if dataWidth > 0 then
		x += textWidth + DETAIL_GAP
		detailData.Position = UDim2.new(0, x, 0, 64)
		detailData.Size = UDim2.new(0, dataWidth, 0, 0)
		detailData.AutomaticSize = Enum.AutomaticSize.Y
	end
end

detail:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutDetail)
layoutDetail()

-- ===== Modelle beschaffen =====
-- Ergebnisse werden gemerkt: je Eintrag einmal holen, egal wie oft das Archiv geöffnet
-- wird. false = "schon versucht, nichts gefunden" -- verhindert Dauerabfragen.
local modelCache = {}

local function buildWorkshopModel(assetName)
	local workshop = ReplicatedStorage:FindFirstChild("TrenchbornAssetWorkshop")
	if not workshop then
		return nil
	end
	local builderModule = workshop:FindFirstChild(assetName .. "GoldenMaster")
	local dressingModule = workshop:FindFirstChild(assetName .. "Dressing")
	if not builderModule then
		return nil
	end
	local ok, model = pcall(function()
		-- Build() setzt den Parent selbst, deshalb ein Ablage-Ordner, aus dem das fertige
		-- Modell wieder herausgelöst wird.
		local staging = Instance.new("Folder")
		staging.Parent = ReplicatedStorage
		local built = require(builderModule).Build(staging)
		if dressingModule then
			pcall(function()
				require(dressingModule).Apply(built)
			end)
		end
		built.Parent = nil
		staging:Destroy()
		return built
	end)
	return ok and model or nil
end

local function buildAvatarModel(scale)
	local pack = Workspace:FindFirstChild("R15AvatarPack")
	local template = pack and pack:FindFirstChildWhichIsA("Model")
	if not template then
		return nil
	end
	local ok, model = pcall(function()
		local clone = template:Clone()
		clone:ScaleTo(scale or 1)
		return clone
	end)
	return ok and model or nil
end

local function resolveModel(entry)
	if modelCache[entry.id] ~= nil then
		return modelCache[entry.id] or nil
	end
	local source = entry.model
	if not source then
		modelCache[entry.id] = false
		return nil
	end

	local model = nil
	if source.workshopAsset then
		model = buildWorkshopModel(source.workshopAsset)
	elseif source.avatarScale then
		model = buildAvatarModel(source.avatarScale)
	elseif source.replicatedStorage then
		local found = ReplicatedStorage:FindFirstChild(source.replicatedStorage)
		model = found and found:Clone() or nil
	elseif ArchiveModelFunction then
		-- ServerStorage: nur der Server kommt daran. Er klont auf Anfrage nach
		-- ReplicatedStorage und liefert die Instanz zurück.
		local ok, delivered = pcall(function()
			return ArchiveModelFunction:InvokeServer(entry.id)
		end)
		if ok and delivered then
			model = delivered:Clone()
		end
	end

	modelCache[entry.id] = model or false
	return model
end

-- ===== Vorschau zeichnen =====

local function darkenModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = HIDDEN_TINT
			descendant.Material = Enum.Material.SmoothPlastic
			descendant.Reflectance = 0
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant:Destroy()
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
end

-- Gibt den ViewportFrame zurück, oder nil wenn es kein Modell gibt.
local function fillViewport(container, entry, silhouette)
	local model = resolveModel(entry)
	if not model then
		return nil
	end
	-- Schein des vorherigen Eintrags entfernen. Wird er vergessen, sammeln sich im
	-- Steckbrief die Farben aller nacheinander angesehenen Eintraege uebereinander.
	local previousGlow = container:FindFirstChild("PreviewGlow")
	if previousGlow then
		previousGlow:Destroy()
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, 0, 1, 0)
	viewport.BackgroundTransparency = 1
	-- WICHTIG: ViewportFrames übernehmen NICHT die Workspace-Beleuchtung -- ohne diese
	-- Werte rendern sie komplett schwarz. Bei der Silhouette ist genau das erwünscht,
	-- deshalb dort deutlich dunkler.
	-- Auch die Beleuchtung war zu dunkel: bei Ambient 30 blieb selbst ein graues Teil
	-- fast schwarz. Flach und gleichmaessig ausleuchten -- eine Silhouette soll eine
	-- Flaeche sein, keine modellierte Form.
	viewport.Ambient = silhouette and Color3.fromRGB(120, 124, 140) or Color3.fromRGB(140, 140, 150)
	viewport.LightColor = silhouette and Color3.fromRGB(90, 94, 108) or Color3.fromRGB(255, 255, 255)
	-- Ueber dem nachgebauten Schein, der gleich darunter eingehaengt wird.
	viewport.ZIndex = 2
	viewport.Parent = container

	local preview = model:Clone()
	if silhouette then
		darkenModel(preview)
	else
		-- Nachgebautes Leuchten: ViewportFrames rendern weder Partikel noch Lichter noch
		-- Bloom (siehe ModelPreviewUtils). Die Farbe kommt aus dem Modell selbst, damit
		-- der Schein zum Eintrag passt statt geraten zu sein.
		--
		-- Bei Silhouetten bewusst NICHT: ein unentdeckter Eintrag soll ein Umriss bleiben.
		-- Ein leuchtender Umriss verriete Farbe und Bauart, und genau das ist der Fund.
		ModelPreviewUtils.AddGlow(container, ModelPreviewUtils.FindGlowColor(preview), 1)
	end
	preview.Parent = viewport

	-- Einpassen ueber ModelPreviewUtils: das Modell fuellt den Rahmen, statt mit einem
	-- festen Faktor irgendwo darin zu stehen. Der alte Faktor 1.7 auf die groesste Kante
	-- liess flache Modelle (Barrikade, Rakete) als Strich in viel Leere zurueck.
	local camera
	local fitted = pcall(function()
		camera = ModelPreviewUtils.Fit(viewport, preview, container)
	end)
	if not fitted then
		-- Sicherheitsnetz: lieber eine grob gesetzte Kamera als gar keine.
		camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		camera.CFrame = CFrame.new(Vector3.new(0, 3, 15), Vector3.new(0, 3, 0))
	end
	return viewport, preview, camera
end

-- ===== Raster =====

local cards = {}

local function isRevealed(entry)
	return player:GetAttribute("Archive_" .. entry.id) == true
end

-- true, solange der Steckbrief absichtlich offen ist (siehe Handler weiter unten).
local detailOpen = false

local function openDetail(entry)
	-- Nur aufgedeckte Einträge haben einen Steckbrief -- sonst wäre das Rätsel umgehbar.
	if not isRevealed(entry) then
		return
	end
	detailTitle.Text = entry.name
	detailHint.Text = entry.hint or ""
	local categoryInfo
	for _, category in ipairs(ArchiveConfig.Categories) do
		if category.key == entry.category then
			categoryInfo = category
		end
	end
	detailDataCategory.Text = categoryInfo and (categoryInfo.icon .. " " .. categoryInfo.label) or entry.category
	detailDataFound.Text = entry.hint or "--"
	-- Wie viel dieser Gruppe schon aufgedeckt ist. Das ist die einzige Angabe hier, die
	-- nicht schon auf der Karte stand -- sie beantwortet "wie viel fehlt mir noch?".
	local siblings = ArchiveConfig.ByCategory[entry.category] or {}
	local revealedCount = 0
	for _, sibling in ipairs(siblings) do
		if isRevealed(sibling) then
			revealedCount += 1
		end
	end
	detailDataProgress.Text = string.format("%d of %d discovered", revealedCount, #siblings)
	layoutDetail()
	-- NUR den alten Viewport entfernen, nicht alle Kinder: ComicStyleUtils hat dem Rahmen
	-- eine UICorner und eine UIStroke gegeben, und ClearAllChildren haette die mit
	-- weggeraeumt -- ab dem zweiten Steckbrief waere der Rahmen unformatiert gewesen.
	for _, child in ipairs(detailViewportHolder:GetChildren()) do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end
	for _, child in ipairs(detailText:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local _, preview = fillViewport(detailViewportHolder, entry, false)
	if preview then
		-- Langsame Drehung: zeigt die Figur von allen Seiten, ohne dass es eine echte
		-- Animation braeuchte. Seit fillViewport ueber ModelPreviewUtils einpasst, steht
		-- das Modell mittig im Ursprung -- die Drehung dort dreht entsprechend um die
		-- Mitte statt um den Pivot, der bei manchen Modellen weit daneben liegt.
		ModelPreviewUtils.Spin(preview)
	end

	local sections = {
		{ heading = "Role", body = entry.profile and entry.profile.role },
		{ heading = "Strength", body = entry.profile and entry.profile.strength },
		{ heading = "Weakness", body = entry.profile and entry.profile.weakness },
	}
	local order = 0
	local shown = 0
	for _, section in ipairs(sections) do
		-- Abschnitte OHNE Text ganz weglassen statt einen Platzhalter zu zeigen. Bei
		-- Spielerfiguren gibt es keine "Weakness" -- eine Kaufstufe ist schlicht besser als
		-- die vorherige --, und "Weakness: noch nicht beschrieben" wäre dort schlicht falsch.
		if section.body and section.body ~= "" then
		shown += 1
		order += 1
		local heading = Instance.new("TextLabel")
		heading.Size = UDim2.new(1, -8, 0, 20)
		heading.BackgroundTransparency = 1
		UiTypography.Subhead(heading)
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.TextColor3 = Color3.fromRGB(255, 205, 90)
		heading.Text = section.heading
		heading.LayoutOrder = order
		heading.Parent = detailText

		order += 1
		local body = Instance.new("TextLabel")
		body.Size = UDim2.new(1, -8, 0, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.BackgroundTransparency = 1
		UiTypography.Body(body)
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextColor3 = Color3.fromRGB(220, 220, 230)
		body.Text = section.body
		body.LayoutOrder = order
		body.Parent = detailText
		end
	end

	-- Gar nichts beschrieben: das sagen, statt eine leere Fläche zu zeigen.
	if shown == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -8, 0, 40)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 14
		empty.TextWrapped = true
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.TextColor3 = Color3.fromRGB(150, 150, 162)
		empty.Text = "— not described yet —"
		empty.Parent = detailText
	end

	-- Merker VOR dem Verstecken setzen: das Verstecken loest den Handler unten aus, und
	-- der wuerde den gerade geoeffneten Steckbrief sonst umgehend wieder schliessen.
	detailOpen = true
	panel.Visible = false
	detail.Visible = true
end

local function refreshCard(card)
	local entry = card.entry
	local revealed = isRevealed(entry)
	card.nameLabel.Text = revealed and entry.name or "???"
	card.hintLabel.Text = entry.hint or ""
	card.question.Visible = not revealed

	-- Neu zeichnen, wenn sich der Zustand geändert hat -- oder wenn noch nie gezeichnet
	-- wurde. Ein Eintrag ohne Modell (noch nicht gebaut) behält das Fragezeichen.
	if card.drawnAs ~= (revealed and "open" or "hidden") then
		card.drawnAs = revealed and "open" or "hidden"
		for _, child in ipairs(card.viewportHolder:GetChildren()) do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end
		if not entry.pending then
			task.spawn(function()
				fillViewport(card.viewportHolder, entry, not revealed)
			end)
		end
	end
end

local function buildCard(parent, entry)
	local card = Instance.new("TextButton")
	card.Size = CARD_SIZE
	card.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	card.Text = ""
	card.AutoButtonColor = true
	card.Parent = parent
	ComicStyleUtils.Apply(card, 10, 3)

	local viewportHolder = Instance.new("Frame")
	viewportHolder.Size = UDim2.new(1, -12, 0, 148)
	viewportHolder.Position = UDim2.new(0, 6, 0, 6)
	viewportHolder.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	viewportHolder.Parent = card
	ComicStyleUtils.Apply(viewportHolder, 8, 2)

	-- Klein und zurueckhaltend: es soll die Silhouette KENNZEICHNEN, nicht verdecken.
	-- Formatfuellend und deckend war es der Hauptgrund, warum vom Umriss nichts zu sehen
	-- war.
	local question = Instance.new("TextLabel")
	question.AnchorPoint = Vector2.new(1, 1)
	question.Size = UDim2.new(0, 38, 0, 38)
	question.Position = UDim2.new(1, -4, 1, -2)
	question.BackgroundTransparency = 1
	question.Font = Enum.Font.FredokaOne
	question.TextScaled = true
	question.TextColor3 = Color3.fromRGB(255, 255, 255)
	question.TextTransparency = 0.45
	question.TextStrokeTransparency = 0.75
	question.Text = "?"
	question.ZIndex = 5
	question.Parent = viewportHolder

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -12, 0, 26)
	nameLabel.Position = UDim2.new(0, 6, 0, 158)
	nameLabel.BackgroundTransparency = 1
	UiTypography.Subhead(nameLabel, 15)
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Text = "???"
	nameLabel.Parent = card

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Size = UDim2.new(1, -12, 0, 18)
	hintLabel.Position = UDim2.new(0, 6, 0, 186)
	hintLabel.BackgroundTransparency = 1
	UiTypography.Caption(hintLabel)
	hintLabel.TextColor3 = Color3.fromRGB(160, 160, 172)
	hintLabel.Text = ""
	hintLabel.Parent = card

	-- "NEW"-Fahne: zeigt beim Öffnen, WELCHE Karte das Lämpchen am Menüpunkt ausgelöst
	-- hat. Ohne sie müsste man 27 Karten absuchen, um den Grund zu finden.
	local newFlag = Instance.new("TextLabel")
	newFlag.Name = "NewFlag"
	newFlag.AnchorPoint = Vector2.new(0, 0)
	newFlag.Size = UDim2.new(0, 40, 0, 16)
	newFlag.Position = UDim2.new(0, 4, 0, 4)
	newFlag.BackgroundColor3 = Color3.fromRGB(235, 45, 45)
	newFlag.Font = Enum.Font.FredokaOne
	newFlag.TextScaled = true
	newFlag.TextColor3 = Color3.fromRGB(255, 255, 255)
	newFlag.Text = "NEW"
	newFlag.Visible = false
	newFlag.ZIndex = 6
	newFlag.Parent = card
	ComicStyleUtils.Apply(newFlag, 6, 2)

	local record = {
		entry = entry,
		viewportHolder = viewportHolder,
		question = question,
		nameLabel = nameLabel,
		hintLabel = hintLabel,
		newFlag = newFlag,
	}
	card.Activated:Connect(function()
		openDetail(entry)
	end)
	table.insert(cards, record)
	return record
end

-- Ein Durchlauf ueber alle Kategorien in ihrer Reihenfolge -- die Karten landen
-- nacheinander im selben Deck, ohne Trennung.
local function buildDeck()
	for _, category in ipairs(ArchiveConfig.Categories) do
		local entries = ArchiveConfig.ByCategory[category.key]
		if entries then
			for _, entry in ipairs(entries) do
				buildCard(scroll, entry)
			end
		end
	end
end

local function refreshAll()
	local total, found = 0, 0
	local perCategory = {}
	-- Was seit dem letzten Öffnen dazugekommen ist. Kommt aus der Menüleiste, die es
	-- über den Neustart hinweg mitführt.
	local fresh = _G.GetNavBadgeItems and _G.GetNavBadgeItems("Archive") or {}
	for _, card in ipairs(cards) do
		refreshCard(card)
		card.newFlag.Visible = fresh[card.entry.id] == true
		total += 1
		local key = card.entry.category
		perCategory[key] = perCategory[key] or { found = 0, total = 0 }
		perCategory[key].total += 1
		if isRevealed(card.entry) then
			found += 1
			perCategory[key].found += 1
		end
	end
	progressLabel.Text = string.format("%d of %d discovered", found, total)

	-- Kompakte Zeile statt Ueberschriften: Symbol und Stand je Gruppe.
	local parts = {}
	for _, category in ipairs(ArchiveConfig.Categories) do
		local counts = perCategory[category.key]
		if counts then
			table.insert(parts, string.format("%s %d/%d", category.icon, counts.found, counts.total))
		end
	end
	counterStrip.Text = table.concat(parts, "   ")
end

buildDeck()
refreshAll()

closeButton.Activated:Connect(function()
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	else
		panel.Visible = false
	end
end)

detailBack.Activated:Connect(function()
	detailOpen = false
	detail.Visible = false
	panel.Visible = true
end)

-- Schliesst die Navigation das Panel, muss der Steckbrief mit verschwinden -- sonst
-- bliebe er über dem Hauptmenü stehen.
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible then
		-- Ueber die Navigation geoeffnet: der Steckbrief gehoert dann zu.
		detailOpen = false
		detail.Visible = false
		refreshAll()
	elseif detail.Visible and not detailOpen then
		-- Die Navigation hat das Panel geschlossen, nicht der Steckbrief -- dann muss er
		-- mit verschwinden, sonst bliebe er ueber dem Hauptmenue stehen.
		detail.Visible = false
	end
end)

-- ===== Einblendung beim Aufdecken =====

local toastQueue = {}
local toastRunning = false

-- Mittig statt am oberen Rand: dort lag sie unter den uebrigen HUD-Elementen. Etwas
-- oberhalb der Bildmitte, damit sie die Figur nicht verdeckt, der man gerade begegnet.
local function showToast(text)
	local toast = Instance.new("TextLabel")
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Size = UDim2.new(0, 380, 0, 56)
	toast.Position = UDim2.new(0.5, 0, 0.34, 0)
	toast.BackgroundColor3 = Color3.fromRGB(180, 140, 80)
	toast.Font = Enum.Font.FredokaOne
	toast.TextScaled = true
	toast.TextColor3 = Color3.fromRGB(255, 255, 255)
	toast.TextStrokeTransparency = 0.5
	toast.Text = text
	toast.Parent = toastGui
	ComicStyleUtils.Apply(toast, 14, 4)

	-- Aus der Mitte heraus aufziehen statt von oben hereinfahren -- ein Einflug haette
	-- wieder durch den Bereich gefuehrt, in dem die anderen HUD-Elemente liegen.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = toast
	toast.TextTransparency = 1
	toast.BackgroundTransparency = 1

	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	TweenService:Create(toast, TweenInfo.new(0.25), {
		TextTransparency = 0,
		BackgroundTransparency = 0,
	}):Play()

	task.wait(2.4)
	TweenService:Create(toast, TweenInfo.new(0.35), {
		TextTransparency = 1,
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.35), { Scale = 0.85 }):Play()
	task.wait(0.4)
	toast:Destroy()
end

local function queueToast(text)
	table.insert(toastQueue, text)
	if toastRunning then
		return
	end
	toastRunning = true
	task.spawn(function()
		while #toastQueue > 0 do
			local message = table.remove(toastQueue, 1)
			showToast(message)
		end
		toastRunning = false
	end)
end

if ArchiveRevealedEvent then
	ArchiveRevealedEvent.OnClientEvent:Connect(function(entryId)
		if entryId == nil then
			refreshAll() -- Debug-Schalter hat alles verborgen
			return
		end
		-- Lämpchen am Menüpunkt setzen, solange das Archiv nicht offen ist -- wer gerade
		-- hinsieht, braucht keinen Hinweis darauf, dass er hinsehen soll.
		if _G.SetNavBadge and not panel.Visible then
			-- Die Id mitgeben, damit sich beim Öffnen zeigen lässt, WELCHE Karte neu ist.
			_G.SetNavBadge("Archive", true, entryId)
		end
		local entry = ArchiveConfig.ById[entryId]
		if entry then
			-- Aufgereiht statt gestapelt: bei Alarmstufe 4 begegnet man drei Einheiten
			-- fast gleichzeitig, mitten im Kampf.
			queueToast("📔  New archive entry: " .. entry.name)
		end
		if panel.Visible then
			refreshAll()
		end
	end)
end

print("[Kaiju-Debug] ArchiveClient bereit -- " .. #cards .. " Karten aufgebaut.")
