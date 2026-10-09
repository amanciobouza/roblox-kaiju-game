-- Complete 54-building layout from asset-workshop largecity-city-plan-assembly.
-- Source: b728d89f9ae5e3909e8add88f083362ee76afce3 (additive import).
-- Studio Command Bar, after Rojo sync:
-- require(game.ServerScriptService.TrenchbornInstallers.LargeCity.LargeCityPlanAssembly).Install()
-- Builds Workspace.LargeCity_AssembledPreview; existing cities remain untouched.
-- This is the branch's architectural layout: combat tags and stadium Pong are disabled.
-- Move the resulting model in Studio to align it with the game's terrain.
-- Optional: .Install({Parent = workspace, GroundY = 12, EnableReviewSpawn = true})

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Installer = {}

function Installer.Install(options)
	assert(RunService:IsStudio(), "Install the city layout in Roblox Studio")
	options = options or {}
	local modules = ReplicatedStorage:FindFirstChild("TrenchbornAssetWorkshop")
	assert(modules, "TrenchbornAssetWorkshop is missing; complete the Rojo sync first")
	local assemblyModule = modules:FindFirstChild("LargeCityAssembly")
	assert(assemblyModule, "LargeCityAssembly is missing; complete the Rojo sync first")
	local assembly = require(assemblyModule)
	local parent = options.Parent or workspace
	assert(not parent:FindFirstChild(assembly.ModelName), "The assembled city already exists")
	local editing = not RunService:IsRunning()
	if editing then
		ChangeHistoryService:SetWaypoint("Before LargeCity plan assembly")
	end
	local staging = Instance.new("Folder")
	local ok, result = xpcall(function()
		local city = assembly.Build(staging, {
			GroundY = options.GroundY or 12,
			YieldBetweenPlots = true,
		})
		local spawn = city:FindFirstChild("CityReviewSpawn")
		if spawn then
			spawn.Enabled = options.EnableReviewSpawn == true
		end
		city:SetAttribute("AssemblySourceCommit", "b728d89f9ae5e3909e8add88f083362ee76afce3")
		city.Parent = parent
		return city
	end, debug.traceback)
	staging:Destroy()
	if not ok then
		error(result)
	end
	if editing then
		ChangeHistoryService:SetWaypoint("LargeCity plan assembly")
	end
	print("[LargeCity] Installed 54 buildings / 21 types. Architectural layout; gameplay integration pending.")
	return result
end

return Installer
