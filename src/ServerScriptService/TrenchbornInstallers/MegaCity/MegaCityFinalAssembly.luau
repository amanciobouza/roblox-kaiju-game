-- Finale Mega City: 85 Gebäude / 21 Typen. Import nach Rojo-Sync:
-- require(game.ServerScriptService.TrenchbornInstallers.MegaCity.MegaCityFinalAssembly).Install()
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Installer = {}

function Installer.Install(options)
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Mega City im Studio-Bearbeitungsmodus importieren")
	options = options or {}
	local parent = options.Parent or workspace
	local name = options.Name or "MegaCity_FinalAssembly"
	assert(not parent:FindFirstChild(name), "Die Zielstadt existiert bereits: " .. name)
	local template = ServerStorage:FindFirstChild("MegaCityFinalAssembly")
	assert(template, "MegaCityFinalAssembly fehlt; zuerst Rojo synchronisieren")
	local buildings = template:FindFirstChild("Buildings")
	assert(buildings and #buildings:GetChildren() == 85, "Das Paket muss genau 85 Gebäude enthalten")
	ChangeHistoryService:SetWaypoint("Vor Mega City Import")
	local city = Instance.new("Model")
	city.Name = name
	local ok, err = xpcall(function()
		for _, group in ipairs(template:GetChildren()) do
			group:Clone().Parent = city
		end
		city:SetAttribute("AssemblySourceCommit", "7e630a1cb12b60d55b75ab2e7bdc52c3ba239d0b")
		city:SetAttribute("City", "MegaCity")
		city:SetAttribute("AssemblyBuildingCount", 85)
		if options.Pivot then
			city:PivotTo(options.Pivot)
		end
		city.Parent = parent
	end, debug.traceback)
	if not ok then
		city:Destroy()
		error(err)
	end
	ChangeHistoryService:SetWaypoint("Mega City importiert")
	print("[MegaCity] 85 Gebäude / 21 Typen importiert: " .. city:GetFullName()
		.. ". Terrain, Stadtanschluss und Spielbetrieb in Studio prüfen.")
	return city
end

return Installer
