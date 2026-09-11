-- VERSION: 2026-08-19 #1
-- LocalScript: ResponsiveHudScale
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Unser HUD wurde mit festen Pixel-Werten für breitere Bildschirme (Desktop/iPad) gebaut.
-- Auf schmalen Handy-Bildschirmen (iPhone) führt das zu Überlappungen, da die Panels
-- absolut positioniert sind und nicht mitschrumpfen. Statt jedes einzelne Panel neu zu
-- bauen: dieses Script fügt jedem ScreenGui (aktuelle UND später erstellte) eine UIScale
-- hinzu, die proportional verkleinert, sobald der Bildschirm schmaler als die
-- Referenzbreite ist -- alle Panels bleiben damit im richtigen Verhältnis zueinander,
-- nur insgesamt kleiner, wodurch sie wieder nebeneinander statt übereinander passen.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Bildschirmbreite/-höhe, für die das HUD ursprünglich ausgelegt wurde (Desktop/iPad-Querformat).
local REFERENCE_WIDTH = 1280
local REFERENCE_HEIGHT = 720 -- NEU: bisher wurde nur die Breite geprüft -- auf breiten,
-- aber NIEDRIGEN Bildschirmen (z.B. iPhone im Querformat) konnte das Panel trotz
-- Breiten-Skalierung immer noch höher als der Bildschirm sein, wodurch Buttons am
-- unteren Rand (z.B. der Research-Button im Talentbaum) ausserhalb des erreichbaren
-- Bereichs landeten.
local MIN_SCALE = 0.55 -- nie kleiner als das, sonst wird Text unlesbar

-- Namen von ScreenGuis, die NICHT mitskaliert werden sollen.
--
-- ===== Warum die Menue-Bildschirme hier stehen =====
-- Eine UIScale auf dem ScreenGui verkleinert ALLES darin -- auch ein Panel, das mit
-- Size = (1,0,1,0) ausdruecklich die ganze Flaeche beansprucht. Bei Faktor 0.55 nimmt so
-- ein Vollbild-Panel noch 55 Prozent des Bildschirms ein, und 45 Prozent bleiben leer.
-- Genau das war auf dem Telefon zu sehen: Bildschirme, die "nicht auf die ganze
-- Screenflaeche" gehen, und Text, der bei 0.55 aus 14 Punkten sieben macht.
--
-- Die Skalierung war die richtige Antwort, solange die Panels mit festen Pixelwerten
-- gebaut waren -- dann passten sie verkleinert wenigstens nebeneinander. Inzwischen
-- rechnen sie ihre Anordnung selbst aus der verfuegbaren Flaeche: die Raster fuellen die
-- Breite (ResponsiveGridUtils), der Talentbaum skaliert seinen Inhalt selbst und teilt die
-- Spalten anteilig auf. Sie brauchen die Verkleinerung nicht mehr -- sie schadet ihnen.
--
-- Das HUD im Spiel bleibt skaliert: dort sitzen Knoepfe und Anzeigen an festen Positionen
-- und muessen weiterhin gemeinsam schrumpfen, damit sie sich nicht ueberlappen.
--
-- NavigationGui steht bewusst NICHT hier: darin sitzt die Navigationsleiste, eine Spalte
-- aus 44-Pixel-Knoepfen ueber dem unteren Rand. Bei voller Groesse waere sie auf einem 360
-- Pixel hohen Telefon hoeher als der Bildschirm. Die Vollbild-Panels in diesem ScreenGui
-- heben die Skalierung stattdessen einzeln wieder auf, siehe NavigationClient.
local EXCLUDED_GUI_NAMES = {
	TalentTreeGui = true,
	ArchiveGui = true,
	GiftGui = true,
	SkinShopGui = true,
	FactionGui = true,
}

local function getCurrentScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local viewportWidth = camera.ViewportSize.X
	local viewportHeight = camera.ViewportSize.Y
	if viewportWidth <= 0 or viewportHeight <= 0 then
		return 1
	end
	-- Der KLEINERE der beiden Faktoren gewinnt -- garantiert, dass das HUD weder in der
	-- Breite noch in der Höhe über den Bildschirm hinausragt.
	local widthScale = viewportWidth / REFERENCE_WIDTH
	local heightScale = viewportHeight / REFERENCE_HEIGHT
	return math.clamp(math.min(widthScale, heightScale), MIN_SCALE, 1)
end

local trackedScales = {} -- [screenGui] = UIScale

local function applyScaleToGui(screenGui)
	if not screenGui:IsA("ScreenGui") then
		return
	end
	if EXCLUDED_GUI_NAMES[screenGui.Name] then
		-- Eine frueher gesetzte Skalierung zuruecknehmen. Ohne das bliebe sie stehen, wenn
		-- ein Bildschirm nachtraeglich in die Ausschlussliste wandert -- und der Fehler
		-- waere dann nur noch in Studio zu sehen, nicht mehr im Quelltext.
		local existing = screenGui:FindFirstChildOfClass("UIScale")
		if existing then
			existing.Scale = 1
		end
		return
	end
	if trackedScales[screenGui] then
		return -- schon versehen
	end

	local uiScale = screenGui:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = screenGui
	end
	uiScale.Scale = getCurrentScale()
	trackedScales[screenGui] = uiScale
end

local function updateAllScales()
	local scale = getCurrentScale()
	for screenGui, uiScale in pairs(trackedScales) do
		if screenGui.Parent then
			uiScale.Scale = scale
		else
			trackedScales[screenGui] = nil
		end
	end
end

-- Bestehende ScreenGuis erfassen
for _, child in ipairs(playerGui:GetChildren()) do
	applyScaleToGui(child)
end

-- Später erstellte ScreenGuis (die meisten unserer HUD-Scripts laufen parallel, die
-- Reihenfolge ist nicht garantiert) automatisch mit erfassen
playerGui.ChildAdded:Connect(applyScaleToGui)

-- Bei Fenstergrößen-/Bildschirmänderung (z.B. Gerätedrehung) alle Skalierungen aktualisieren
local camera = Workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAllScales)
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local newCamera = Workspace.CurrentCamera
	if newCamera then
		newCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAllScales)
		updateAllScales()
	end
end)