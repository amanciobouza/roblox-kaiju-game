-- Ort in Studio: ReplicatedStorage
--
-- Verteilt die Breite eines Behälters auf so viele Rasterspalten, wie bei einer
-- Mindest-Kartenbreite hineinpassen, und zieht die Zellen auf die volle Breite.
--
-- Warum es das gibt: die Menü-Bildschirme nutzen die ganze Fläche, ihre Raster hatten aber
-- feste Zellengrössen. Auf einem Telefon blieb dadurch rechts ein toter Streifen stehen --
-- 210 Pixel breite Geschenk-Karten passen bei 640 Pixeln Bildschirmbreite zweimal hinein
-- und lassen 190 Pixel leer. Auf einem breiten Monitor war es umgekehrt: die Karten
-- standen in einer Ecke zusammengedrängt.
--
-- Die Logik stand schon im NavigationClient, dort aber als lokale Funktion und nur für die
-- Achievements benutzt. Hier liegt sie einmal für alle.

local ResponsiveGridUtils = {}

-- Breite des Behälters OHNE Rollbalken. AbsoluteSize enthält ihn mit; wer damit rechnet,
-- bekommt eine Spalte zu viel und dadurch waagrechtes Rollen.
function ResponsiveGridUtils.UsableWidth(container)
	if container:IsA("ScrollingFrame") then
		return container.AbsoluteWindowSize.X - container.ScrollBarThickness
	end
	return container.AbsoluteSize.X
end
local usableWidth = ResponsiveGridUtils.UsableWidth

-- Bindet ein UIGridLayout an die Breite seines Behälters.
--
-- `minCardWidth`  kleinste Breite, bei der eine Karte noch lesbar ist
-- `maxColumns`    Obergrenze, damit auf sehr breiten Monitoren keine Briefmarken entstehen
-- `aspect`        optional: Höhe je Breite. Ohne den Wert bleibt die Zellenhöhe, wie sie
--                 gesetzt wurde -- mit ihm wachsen die Karten proportional mit.
function ResponsiveGridUtils.Bind(container, grid, maxColumns, minCardWidth, aspect)
	local function apply()
		local width = usableWidth(container)
		if width <= 0 then
			return
		end
		local gap = grid.CellPadding.X.Offset
		local columns = math.clamp(math.floor((width + gap) / (minCardWidth + gap)), 1, maxColumns)
		local cellWidth = math.floor((width - (columns - 1) * gap) / columns)
		local cellHeight = aspect and math.floor(cellWidth * aspect) or grid.CellSize.Y.Offset
		grid.CellSize = UDim2.new(0, cellWidth, 0, cellHeight)
	end

	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	apply()
	return apply
end

return ResponsiveGridUtils
