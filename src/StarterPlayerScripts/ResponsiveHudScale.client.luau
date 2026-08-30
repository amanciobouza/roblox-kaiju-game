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

-- Namen von ScreenGuis, die NICHT mitskaliert werden sollen (z.B. reine Vollbild-Effekte
-- ohne Text/Buttons, wo Skalierung nichts bringt oder störend wäre).
local EXCLUDED_GUI_NAMES = {}

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