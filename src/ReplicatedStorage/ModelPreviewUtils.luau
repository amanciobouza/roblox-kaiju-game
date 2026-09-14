-- ModuleScript: ModelPreviewUtils
-- Ort in Studio: ReplicatedStorage
--
-- Modellvorschauen in ViewportFrames: Rahmen anlegen, Modell einpassen, drehen.
--
-- ===== Warum zentral =====
-- Vier Bildschirme zeigen Modelle in einem Viewport (Skinauswahl, Fraktionen, Archiv-Raster
-- und Archiv-Steckbrief), und jeder hatte seine eigene Kamerarechnung. Sie unterschieden
-- sich in genau den Punkten, die man leicht übersieht -- Seitenverhältnis des Rahmens,
-- Drehung um den Pivot statt um die Mitte -- und entsprechend verschieden sahen sie aus.
--
-- ===== Die drei Fallen beim Einpassen =====
-- 1. Der Pivot eines Avatars sitzt im Rumpf, nicht in der Mitte des Hüllquaders. Wer um
--    ihn dreht, lässt die Figur im Rahmen KREISEN statt sich drehen. Deshalb wird das
--    Modell erst so verschoben, dass seine Mitte im Ursprung liegt, und die Drehung wird
--    vorn multipliziert (dreht um den Ursprung) statt hinten (dreht um den Pivot).
-- 2. Der Rahmen ist selten quadratisch. FieldOfView ist der SENKRECHTE Öffnungswinkel;
--    bei einem hohen, schmalen Rahmen ist der waagrechte enger. Wer das ignoriert,
--    schneidet die Schultern ab.
-- 3. Ein Modell in Ruhelage zeigt dem Betrachter den RÜCKEN. Vorderseite und Blickrichtung
--    der Kamera liegen beide auf -Z. Deshalb dreht Fit() das Modell um 180 Grad.
--
-- Gerahmt wird über die Diagonale der Grundfläche, nicht über die einzelne Kante: ein
-- drehendes Modell ist bei 45 Grad breiter als jede seiner Kanten.

local RunService = game:GetService("RunService")

local ModelPreviewUtils = {}

local FIELD_OF_VIEW = 50

-- ===== Zwei Blickwinkel, nicht einer =====
--
-- Bis hierher gab es genau eine Kameraeinstellung: geradeaus, mittig auf den Huellquader,
-- fuenfzig Grad Oeffnungswinkel. Fuer einen KATALOG ist das richtig -- das Archiv zeigt
-- sechsundzwanzig Eintraege nebeneinander, und dort soll keiner interessanter aussehen als
-- der andere. Gleiche Kamera, gleiche Bedingungen, vergleichbar.
--
-- Die Fraktionsauswahl ist kein Katalog. Dort stehen drei Figuren, zwischen denen man sich
-- entscheidet, und sie duerfen etwas darstellen. Drei Dinge unterscheiden die beiden Blicke:
--
--   BRENNWEITE. Fuenfzig Grad sind ein Weitwinkel: was naeher an der Kamera ist, wirkt
--   ueberproportional gross, und bei einer Figur, die auf den Betrachter zulaeuft, heisst
--   das Nase gross, Fuesse klein. Zweiunddreissig Grad entsprechen etwa einem
--   Portraitobjektiv -- die Kamera steht dafuer weiter weg, und die Figur bleibt gleich
--   gross im Bild, aber in ihren eigenen Proportionen.
--
--   ZIELPUNKT. Nicht die Mitte des Huellquaders, sondern ein Stueck darueber. Die Mitte
--   einer stehenden Figur liegt in der Huefte; wer dorthin zielt, macht ein Bild, dessen
--   Gegenstand der Bauch ist. Der Blick gehoert nach oben, wo Kopf und Schultern sind.
--
--   NEIGUNG. Leicht von UNTEN. Eine Kamera unter Augenhoehe laesst gross wirken, was sie
--   zeigt -- das ist der aelteste Trick der Filmsprache und hier genau der Punkt: man
--   waehlt zwischen drei Titanen, nicht zwischen drei Gegenstaenden.
local BLICK_KATALOG = {
	fov = FIELD_OF_VIEW,
	-- Etwas Luft zum Rand, sonst stossen Kopf und Fuesse an. Von 1.12 auf 1.25 angehoben,
	-- als die ersten echten Figurenmodelle dazukamen: bei einem schlanken Avatar reichten
	-- zwoelf Prozent, bei einer breiten, gebueckten Gestalt mit Schweif sassen Kopf und
	-- Fuesse am Rand.
	fill = 1.25,
	zielHoehe = 0, -- Anteil der Modellhoehe ueber der Mitte
	neigung = 0, -- Grad; negativ = Kamera unterhalb, blickt hinauf
}

ModelPreviewUtils.BLICK_HELD = {
	fov = 32,
	fill = 1.2,
	zielHoehe = 0.12,
	neigung = -9,
}

-- Stellt die Kamera so, dass `size` in den Rahmen passt. Ausgelagert, weil sie ZWEIMAL
-- gebraucht wird: einmal sofort und noch einmal, sobald der Rahmen seine echte Grösse
-- kennt (siehe Fit).
local function aimCamera(camera, container, size, blick)
	local frame = container.AbsoluteSize
	local aspect = (frame.X > 0 and frame.Y > 0) and (frame.X / frame.Y) or 1

	camera.FieldOfView = blick.fov

	local verticalFov = math.rad(blick.fov)
	local horizontalFov = 2 * math.atan(math.tan(verticalFov / 2) * aspect)
	local diagonal = math.sqrt(size.X * size.X + size.Z * size.Z)
	local distance = math.max(
		(size.Y / 2) / math.tan(verticalFov / 2),
		(diagonal / 2) / math.tan(horizontalFov / 2)
	) * blick.fill

	-- Der Zielpunkt liegt ueber der Mitte, nicht darin. Beim Katalogblick ist zielHoehe
	-- null, dann ist das hier rechnerisch dasselbe wie vorher.
	local ziel = Vector3.new(0, size.Y * blick.zielHoehe, 0)

	-- Die Kamera steht auf einer Kugel um den Zielpunkt. Negative Neigung heisst: unterhalb,
	-- und sie blickt hinauf.
	local rad = math.rad(blick.neigung)
	local position = ziel + Vector3.new(0, math.sin(rad), math.cos(rad)) * distance

	camera.CFrame = CFrame.new(position, ziel)
end

-- Legt einen beleuchteten ViewportFrame an, der den Behälter ausfüllt.
--
-- ViewportFrames übernehmen NICHT die Beleuchtung des Workspace -- ohne diese beiden
-- Werte rendern sie vollständig schwarz. Das ist der häufigste Fehler bei Viewports.
function ModelPreviewUtils.CreateViewport(container, zIndex)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, 0, 1, 0)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(150, 148, 140)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	if zIndex then
		viewport.ZIndex = zIndex
	end
	viewport.Parent = container
	return viewport
end

-- Richtet `model` mittig aus und stellt die Kamera so, dass es den Rahmen füllt.
-- `container` liefert das Seitenverhältnis; vor dem ersten Zeichnen ist es null, dann
-- wird 1:1 angenommen.
-- Hüllquader NUR über die sichtbaren Teile.
--
-- GetBoundingBox() zählt jedes BasePart mit, auch vollständig durchsichtige: Trefferzonen,
-- Rotorscheiben, Lichtkegel, durchsichtige Wurzelteile. Die verschieben den Mittelpunkt,
-- ohne dass man sie sieht -- das Modell steht dann sichtbar aus der Mitte gerückt, und die
-- Kamera steht zu weit weg, weil sie einen grösseren Körper rahmt als den, der gezeigt
-- wird. Genau so sah der Verkehrshelikopter aus: zur Seite und nach oben versetzt.
--
-- Eine Vorschau soll rahmen, was man SIEHT. Das Modell muss dafür bereits achsenparallel
-- stehen (der Aufrufer setzt es auf CFrame.new(0,0,0)), dann genügen die Eckpunkte.
local function visibleBounds(model)
	local minimum, maximum
	local skipped = 0

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Transparency >= 1 then
				skipped += 1
			else
				local half = part.Size / 2
				for _, signX in ipairs({ -1, 1 }) do
					for _, signY in ipairs({ -1, 1 }) do
						for _, signZ in ipairs({ -1, 1 }) do
							local corner = (part.CFrame * CFrame.new(
								half.X * signX,
								half.Y * signY,
								half.Z * signZ
							)).Position
							minimum = minimum and minimum:Min(corner) or corner
							maximum = maximum and maximum:Max(corner) or corner
						end
					end
				end
			end
		end
	end

	if not minimum then
		return nil, nil, skipped
	end
	return (minimum + maximum) / 2, maximum - minimum, skipped
end

-- `blick` ist entweder eine Tabelle (BLICK_HELD oder eine eigene) oder -- wie bisher --
-- eine Zahl, die nur den Fuellgrad meint. Die Zahl bleibt zulaessig, weil vier Aufrufer sie
-- so benutzen und ein Umbau dort nichts verbessern wuerde.
function ModelPreviewUtils.Fit(viewport, model, container, blick)
	-- Halbe Drehung, damit die Figur den Betrachter ANSIEHT.
	--
	-- In Roblox zeigt die Vorderseite eines Modells entlang der NEGATIVEN Z-Achse
	-- (CFrame.LookVector). Die Kamera steht weiter unten bei +Z und blickt Richtung -Z --
	-- sie schaut also in dieselbe Richtung, in die das Modell schaut, und sieht damit
	-- dessen Ruecken. Ohne diese Drehung stand der ganze Katalog mit dem Ruecken zum
	-- Spieler, und bei den drehenden Vorschauen begann die Drehung auf der falschen Seite.
	--
	-- Das setzt voraus, dass das Modell nach der Konvention gebaut ist. Sollte ein
	-- einzelnes Modell seitenverkehrt erscheinen, ist es in seiner Quelle falsch herum
	-- gebaut -- dann dort drehen, nicht hier eine Ausnahme einbauen.
	model:PivotTo(CFrame.Angles(0, math.pi, 0))

	local center, size, skipped = visibleBounds(model)
	if not center then
		-- Kein einziges sichtbares Teil -- dann bleibt nur der volle Hüllquader. Ein Modell
		-- ohne sichtbare Teile ist zwar unsinnig, aber eine Vorschau, die deshalb gar nichts
		-- anzeigt, wäre schlechter als eine schiefe.
		local boundingCFrame
		boundingCFrame, size = model:GetBoundingBox()
		center = boundingCFrame.Position
	elseif skipped > 0 then
		-- Nachweis, dass die Korrektur greift, und zugleich der Hinweis aufs Modell: um
		-- diesen Betrag stand die Vorschau vorher daneben.
		local _, fullSize = model:GetBoundingBox()
		local shift = (fullSize - size).Magnitude
		if shift > 0.5 then
			print(string.format(
				"[Kaiju Debug] Vorschau %s: %d durchsichtige Teile uebergangen, "
					.. "Huellquader dadurch um %.1f Studs kleiner.",
				model.Name, skipped, shift
			))
		end
	end

	model:PivotTo(model:GetPivot() - center)

	local einstellung = BLICK_KATALOG
	if type(blick) == "table" then
		einstellung = blick
	elseif type(blick) == "number" then
		einstellung = {
			fov = BLICK_KATALOG.fov,
			fill = blick,
			zielHoehe = BLICK_KATALOG.zielHoehe,
			neigung = BLICK_KATALOG.neigung,
		}
	end

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	aimCamera(camera, container, size, einstellung)

	-- ===== Nachmessen, sobald der Rahmen seine echte Grösse hat =====
	-- Beim ersten Aufruf steht die Grösse oft noch nicht fest: die Karte ist gerade erst
	-- entstanden, das UIGridLayout hat noch nicht gerechnet, oder das Panel ist unsichtbar.
	-- AbsoluteSize ist dann (0,0), und aimCamera muss auf ein quadratisches Verhältnis
	-- raten.
	--
	-- Das Raten geht in eine bestimmte Richtung schief: bei einem HOHEN, schmalen Rahmen
	-- (die Archivkarte ist 168 breit und 216 hoch) ist der waagrechte Öffnungswinkel in
	-- Wahrheit enger als angenommen. Die Kamera steht dann zu nah, und das Modell läuft
	-- über den Rand -- genau das war an den Figuren zu sehen, weil sie viel breiter sind
	-- als ein Avatar.
	--
	-- Statt das Messen zu verschieben und zu hoffen: bei jeder Änderung neu ausrichten. Das
	-- deckt auch das Drehen des Telefons und das Verkleinern des Fensters ab.
	local resizeConnection
	resizeConnection = container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if not (camera.Parent and model.Parent) then
			resizeConnection:Disconnect()
			return
		end
		aimCamera(camera, container, size, einstellung)
	end)

	return camera
end

-- Dreht das Modell langsam um die eigene Achse. Die Schleife endet von selbst, sobald das
-- Modell weggeräumt wird -- Aufrufer müssen nichts abmelden.
function ModelPreviewUtils.Spin(model, degreesPerFrame)
	local step = math.rad(degreesPerFrame or 0.5)
	task.spawn(function()
		while model.Parent do
			local ok = pcall(function()
				-- VORN multipliziert: dreht um den Ursprung, in dem das Modell nach Fit()
				-- mittig steht. Hinten multipliziert wäre es der Pivot -- siehe oben.
				model:PivotTo(CFrame.Angles(0, step, 0) * model:GetPivot())
			end)
			if not ok then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- ===== Leuchten =====
-- ViewportFrames rendern KEINE Effekte: Partikel, Beams, Trails, PointLights, Highlights
-- und die Nachbearbeitung (Bloom) fallen dort ersatzlos weg. Nur Neon-Material kommt
-- durch -- hell, aber ohne den Schein drumherum, und der macht das Leuchten aus.
-- Das ist eine Grenze der Plattform und nicht zu umgehen; der Schein wird deshalb
-- nachgebaut: farbige Kreise HINTER dem Modell, von innen nach aussen durchsichtiger.
--
-- Ein einzelner Kreis hat eine harte Kante und sieht nach Aufkleber aus. Mehrere
-- ineinander ergeben eine Abstufung, die als weicher Schein durchgeht. Ein echter
-- Radialverlauf ginge nur ueber ein Bild-Asset -- UIGradient kann nur linear.

-- Sucht die auffaelligste Leuchtfarbe im Modell. Bewertet werden Neon-Teile nach
-- Farbkraft, Helligkeit und Groesse: ein kraeftiger blauer Visor schlaegt eine grosse
-- weissliche Flaeche, denn er ist es, den man als "das Leuchten" wahrnimmt.
function ModelPreviewUtils.FindGlowColor(model)
	local best, bestScore = nil, 0
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Material == Enum.Material.Neon then
			local color = part.Color
			local brightest = math.max(color.R, color.G, color.B)
			local darkest = math.min(color.R, color.G, color.B)
			local saturation = brightest - darkest
			local score = saturation * brightest * math.max(part.Size.Magnitude, 0.1)
			if score > bestScore then
				best, bestScore = color, score
			end
		end
	end
	return best
end

-- Legt den nachgebauten Schein an. Muss VOR dem Viewport eingehaengt werden, sonst liegt
-- er darueber -- der ZIndex allein genuegt nicht, wenn beide denselben haben.
local GLOW_RINGS = {
	{ scale = 0.55, transparency = 0.62 },
	{ scale = 0.75, transparency = 0.80 },
	{ scale = 0.95, transparency = 0.90 },
}

function ModelPreviewUtils.AddGlow(container, color, zIndex)
	if not color then
		return nil
	end
	local holder = Instance.new("Frame")
	holder.Name = "PreviewGlow"
	holder.Size = UDim2.new(1, 0, 1, 0)
	holder.BackgroundTransparency = 1
	holder.ZIndex = zIndex or 1
	holder.Parent = container

	for index, ring in ipairs(GLOW_RINGS) do
		local circle = Instance.new("Frame")
		circle.Name = "Ring" .. index
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = UDim2.new(0.5, 0, 0.5, 0)
		-- Am kleineren Rand ausgerichtet, damit der Schein in einem breiten Rahmen nicht
		-- zur Ellipse wird.
		circle.Size = UDim2.new(ring.scale, 0, ring.scale, 0)
		circle.SizeConstraint = Enum.SizeConstraint.RelativeYY
		circle.BackgroundColor3 = color
		circle.BackgroundTransparency = ring.transparency
		circle.BorderSizePixel = 0
		circle.ZIndex = holder.ZIndex
		circle.Parent = holder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = circle
	end
	return holder
end

-- Fragezeichen statt Modell: für Einträge, die es noch nicht gibt oder die der Spieler
-- noch nicht kennt.
function ModelPreviewUtils.ShowPlaceholder(container, zIndex)
	local label = Instance.new("TextLabel")
	label.Name = "PreviewPlaceholder"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(170, 160, 145)
	label.Text = "?"
	if zIndex then
		label.ZIndex = zIndex
	end
	label.Parent = container
	return label
end

return ModelPreviewUtils
