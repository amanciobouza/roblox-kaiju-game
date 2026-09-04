-- ModuleScript: LetterboxUtils
-- Ort in Studio: ReplicatedStorage
--
-- Filmstreifen: die schwarzen Balken oben und unten, die aus einem Spielbild ein Filmbild
-- machen.
--
-- ===== Warum zentral =====
-- Es gab sie im Bestand zweimal, einmal im Prolog und einmal in der Trainingskamera --
-- mit unterschiedlicher Höhe, unterschiedlicher Blende (Transparenz gegen Grösse) und
-- unterschiedlichem DisplayOrder. Mit dem Showdown wären es drei geworden.
--
-- ===== Was dieses Modul NICHT tut =====
-- Es blendet KEIN HUD aus. Der Prolog-Letterbox tat das mit, und für den Prolog ist das
-- richtig -- dort schaut man nur zu. Im Showdown wird weitergekämpft; wer dort das HUD
-- mit ausblendet, nimmt dem Spieler die Lebensanzeige und die Angriffsknöpfe. Was
-- verschwinden soll, entscheidet deshalb der Aufrufer.
--
-- ===== Benutzung =====
--   local bars = LetterboxUtils.Create(playerGui, "ShowdownLetterboxGui", { heightFraction = 0.06 })
--   bars.SetVisible(true)   -- fährt auf
--   bars.SetVisible(false)  -- fährt zu
--   bars.Destroy()
--
-- ===== Zwei Blenden, mit Absicht =====
--   "slide" -- die Balken klappen auf. Sieht aus wie eine Blende und ist die Vorgabe.
--   "fade"  -- die Balken stehen in voller Höhe und werden durchsichtig ein- und
--              ausgeblendet. Der Prolog macht es seit jeher so; sein Aussehen ist
--              abgenommen und soll sich beim Vereinheitlichen nicht ändern.
-- Der Unterschied ist reine Optik -- deshalb ein Schalter und keine zweite Datei.

local TweenService = game:GetService("TweenService")

local LetterboxUtils = {}

local DEFAULT_HEIGHT_FRACTION = 0.06
local DEFAULT_FADE_DURATION = 0.4

-- Über allem ausser den Vollbild-Menüs (DisplayOrder 100): der Filmstreifen gehört über
-- das Spiel, aber nicht über einen geöffneten Bildschirm.
local DEFAULT_DISPLAY_ORDER = 40

function LetterboxUtils.Create(playerGui, guiName, options)
	options = options or {}
	local heightFraction = options.heightFraction or DEFAULT_HEIGHT_FRACTION
	local heightPixels = options.heightPixels -- gesetzt: schlägt den Anteil
	local fadeDuration = options.fadeDuration or DEFAULT_FADE_DURATION
	local style = options.style or "slide"
	-- Der Prolog blendet mit Sine/InOut. Das ist abgenommene Optik und wird hier
	-- durchgereicht statt vereinheitlicht -- eine andere Kurve waere eine stille
	-- Aenderung an einer Stelle, die niemand geprueft hat.
	local easingStyle = options.easingStyle or Enum.EasingStyle.Quad
	local easingDirection = options.easingDirection or Enum.EasingDirection.Out

	local function barSize(open)
		if heightPixels then
			return UDim2.new(1, 0, 0, open and heightPixels or 0)
		end
		return UDim2.new(1, 0, open and heightFraction or 0, 0)
	end

	-- Ein vorhandenes GUI gleichen Namens ablösen: sonst stapeln sich nach einem
	-- Neuladen des Charakters mehrere Balkenpaare übereinander.
	local existing = playerGui:FindFirstChild(guiName)
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = options.displayOrder or DEFAULT_DISPLAY_ORDER
	gui.Parent = playerGui

	local function createBar(anchorY)
		local bar = Instance.new("Frame")
		bar.Name = anchorY == 0 and "TopBar" or "BottomBar"
		bar.AnchorPoint = Vector2.new(0, anchorY)
		bar.Position = UDim2.new(0, 0, anchorY, 0)
		-- Bei "fade" stehen die Balken sofort in voller Höhe und sind nur unsichtbar.
		bar.Size = style == "fade" and barSize(true) or barSize(false)
		bar.BackgroundTransparency = style == "fade" and 1 or 0
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.ZIndex = 10
		bar.Parent = gui
		return bar
	end

	local topBar = createBar(0)
	local bottomBar = createBar(1)

	local visible = false

	local function setVisible(shouldShow)
		if shouldShow == visible then
			return
		end
		visible = shouldShow
		local info = TweenInfo.new(fadeDuration, easingStyle, easingDirection)
		local goal = style == "fade"
			and { BackgroundTransparency = shouldShow and 0 or 1 }
			or { Size = barSize(shouldShow) }
		TweenService:Create(topBar, info, goal):Play()
		TweenService:Create(bottomBar, info, goal):Play()
	end

	return {
		Gui = gui,
		SetVisible = setVisible,
		IsVisible = function()
			return visible
		end,
		Destroy = function()
			gui:Destroy()
		end,
	}
end

return LetterboxUtils
