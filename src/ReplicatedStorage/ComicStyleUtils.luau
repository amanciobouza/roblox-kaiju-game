-- VERSION: 2026-08-25 #1
-- ModuleScript: ComicStyleUtils
-- Ort in Studio: ReplicatedStorage
--
-- Ausgelagert aus neun Client-Dateien (war dort jeweils identisch dupliziert):
-- LoadingScreen.lua, TalentTreeClient.lua, NavigationClient.lua, EnergyTypesClient.lua,
-- GiftClient.lua, SkinSelectionGui.lua, SpecialAttackClient.lua, TeleportHomeClient.lua,
-- DebugPanelClient.lua. Fügt einem GUI-Objekt runde Ecken + dicke schwarze Outline hinzu
-- (typischer Comic-Look, projektweit einheitlich verwendet).
--
-- WICHTIG: Jede Aufrufstelle im Projekt übergibt cornerRadius UND strokeThickness
-- explizit -- die "or"-Fallback-Defaults unten werden dadurch nie tatsächlich verwendet,
-- sind aber sicherheitshalber vorhanden, falls künftig doch mal ohne diese Parameter
-- aufgerufen wird.

local ComicStyleUtils = {}

function ComicStyleUtils.Apply(guiObject, cornerRadius, strokeThickness)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cornerRadius or 16)
	corner.Parent = guiObject

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = strokeThickness or 4
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = guiObject

	return corner, stroke
end

return ComicStyleUtils