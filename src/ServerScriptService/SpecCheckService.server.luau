-- Spec-Prüfer für Studio.
--
-- Gegenstück zu tools/spec-check.luau: dieselben Regelmodule, dieselbe Ausgabe -- aber
-- hier mit Workspace und laufendem Zustand. Regeln mit needsWorkspace/needsRuntime, die
-- der kopflose Prüfer überspringen muss, laufen erst hier.
--
-- Läuft beim Serverstart und lässt sich über das Debug-Panel erneut auslösen. Er meldet
-- ausschliesslich per warn -- ein fehlgeschlagener Spec-Check darf NIEMALS das Spiel
-- anhalten, sonst schaltet ihn beim ersten Fehlalarm jemand ab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- WaitForChild MIT Timeout und geprüftem Ergebnis: ohne das hängt der Dienst stumm, falls
-- das Modul fehlt (siehe CLAUDE.md, "Bekannte Fallstricke"). require(nil) würde ausserdem
-- diesen ganzen Dienst abschiessen.
local remoteUtilsModule = ReplicatedStorage:WaitForChild("RemoteEventUtils", 10)
if not remoteUtilsModule then
	warn("[Kaiju Spec] RemoteEventUtils nicht gefunden (Timeout) -- Spec-Prüfung bleibt aus.")
	return
end
local RemoteEventUtils = require(remoteUtilsModule)

local SPEC_FOLDER_NAME = "Specs"
local RUNNER_NAME = "SpecRunner"
local PREFIX = "[Kaiju Spec]"

-- Verzögerung vor dem ersten Lauf: die anderen Dienste setzen ihre _G-Funktionen und
-- Tags beim Start, und der Workspace wird noch befüllt. Zu früh geprüft meldet der
-- Prüfer Verstösse, die es gar nicht gibt -- der klassische Weg, ein Warnsystem
-- unglaubwürdig zu machen.
local STARTUP_DELAY_SECONDS = 8

local specFolder = ReplicatedStorage:WaitForChild(SPEC_FOLDER_NAME, 20)
if not specFolder then
	warn(PREFIX .. " ReplicatedStorage." .. SPEC_FOLDER_NAME .. " nicht gefunden (Timeout) -- Spec-Prüfung bleibt aus.")
	return
end

local runnerModule = specFolder:FindFirstChild(RUNNER_NAME)
if not runnerModule then
	warn(PREFIX .. " " .. RUNNER_NAME .. " nicht gefunden -- Spec-Prüfung bleibt aus.")
	return
end
local SpecRunner = require(runnerModule)

-- ===== Spec-Module einsammeln =====
-- Anders als der kopflose Prüfer kann dieser hier den Ordner AUSZÄHLEN (Roblox hat
-- GetChildren, Luau hat kein io). Weicht die Zahl unten von der des kopflosen Prüfers ab,
-- fehlt dort ein Eintrag in seiner handgeführten Liste.
local function collectFrom(folder, specs)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		-- Nur Module, deren Name auf "Spec" endet: der Workshop-Ordner enthält daneben
		-- Builder, Dressing, Gameplay und Specification-DATEN -- die sind keine Specs und
		-- dürfen nicht versehentlich als solche geladen werden.
		if child:IsA("ModuleScript") and child.Name ~= RUNNER_NAME and string.sub(child.Name, -4) == "Spec" then
			local ok, spec = pcall(require, child)
			if ok and type(spec) == "table" and spec.Rules then
				table.insert(specs, spec)
			else
				warn(PREFIX .. " Spec-Modul '" .. child.Name .. "' konnte nicht geladen werden: " .. tostring(spec))
			end
		end
	end
end

local function collectSpecs()
	local specs = {}
	collectFrom(specFolder, specs)
	-- Asset-Specs bleiben bei ihrem Asset im Submodul, damit der Workshop in seinem
	-- eigenen Place für sich lauffähig bleibt -- deshalb ein zweiter Ort.
	collectFrom(ReplicatedStorage:FindFirstChild("TrenchbornAssetWorkshop"), specs)
	return specs
end

-- ===== Kontext bauen =====
-- Die Regeln fassen nichts Roblox-spezifisches selbst an (siehe SpecRunner) -- was sie
-- über die Welt wissen müssen, kommt über diese schmalen Hilfsfunktionen herein.
local function buildWorkspaceContext()
	return {
		CountTagged = function(tagName)
			return #CollectionService:GetTagged(tagName)
		end,
		GetTagged = function(tagName)
			return CollectionService:GetTagged(tagName)
		end,

		-- Zählt getaggte Instanzen JE STADT und liefert eine schlichte Tabelle
		-- { [Stadtname] = Anzahl }. Bewusst hier und nicht in der Regel: die Auflösung
		-- braucht _G.ResolveCityName und CollectionService, und eine Spec-Regel darf
		-- nichts Roblox-Spezifisches anfassen -- sonst läuft sie im kopflosen Prüfer
		-- nicht mehr.
		CountTaggedByCity = function(tagName)
			local counts = {}
			if not _G.ResolveCityName then
				return counts
			end
			for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
				local cityName = _G.ResolveCityName(instance)
				if cityName then
					counts[cityName] = (counts[cityName] or 0) + 1
				end
			end
			return counts
		end,
		FindByAttribute = function(attributeName, value)
			local found = {}
			for _, descendant in ipairs(Workspace:GetDescendants()) do
				if descendant:GetAttribute(attributeName) == value then
					table.insert(found, descendant)
				end
			end
			return found
		end,
	}
end

-- Laufender Zustand: nur beim manuellen Nachprüfen mitgegeben. Beim Serverstart ist
-- nichts davon sinnvoll gefüllt -- kein Spieler da, kein Guardian gespawnt.
local function buildRuntimeContext()
	return {
		HasGlobal = function(name)
			return _G[name] ~= nil
		end,
		GetCityAlertLevel = function(cityName)
			return _G.GetCityAlertLevel and _G.GetCityAlertLevel(cityName) or nil
		end,
		HasActiveGuardian = function(cityName)
			return _G.HasActiveGuardian ~= nil and _G.HasActiveGuardian(cityName)
		end,

		-- Gebaute Workshop-Modelle: erkennbar am Attribut VisiblePartCount, das die
		-- GoldenMaster beim Bauen setzen. Bewusst als schlichte Tabellen zurückgegeben und
		-- NICHT als Instances -- eine Spec-Regel darf keine Roblox-Typen anfassen, sonst
		-- läuft sie im kopflosen Prüfer nicht mehr.
		GetWorkshopModels = function()
			local found = {}
			for _, descendant in ipairs(Workspace:GetDescendants()) do
				if descendant:IsA("Model") and descendant:GetAttribute("VisiblePartCount") ~= nil then
					table.insert(found, {
						Name = descendant.Name,
						VisiblePartCount = descendant:GetAttribute("VisiblePartCount"),
						VisiblePartBudget = descendant:GetAttribute("VisiblePartBudget"),
						GameplayHitboxCount = descendant:GetAttribute("GameplayHitboxCount"),
						GameplayHitboxBudget = descendant:GetAttribute("GameplayHitboxBudget"),
					})
				end
			end
			return found
		end,
	}
end

local function buildConfigContext()
	local function tryRequire(name)
		local module = ReplicatedStorage:FindFirstChild(name)
		if not module then
			warn(PREFIX .. " Config '" .. name .. "' nicht gefunden -- Regeln darüber schlagen fehl.")
			return nil
		end
		local ok, value = pcall(require, module)
		return ok and value or nil
	end

	-- Asset-Spezifikationen liegen im Workshop-Ordner, nicht direkt in ReplicatedStorage.
	local workshopAssets = nil
	local workshopFolder = ReplicatedStorage:FindFirstChild("TrenchbornAssetWorkshop")
	if workshopFolder then
		workshopAssets = {}
		for key, moduleName in pairs({
			WardenIShepherd = "AssetSpecification",
			MarshalIIRoadblock = "MarshalRoadblockSpecification",
		}) do
			local module = workshopFolder:FindFirstChild(moduleName)
			if module then
				local ok, value = pcall(require, module)
				if ok then
					workshopAssets[key] = value
				end
			end
		end
	end

	return {
		CityAlert = tryRequire("CityAlertConfig"),
		TalentTree = tryRequire("TalentTreeConfig"),
		Achievements = tryRequire("AchievementsConfig"),
		WorkshopAssets = workshopAssets,
	}
end

-- ===== Lauf =====
local function runCheck(includeRuntime)
	local specs = collectSpecs()
	local ctx = {
		config = buildConfigContext(),
		workspace = buildWorkspaceContext(),
		runtime = includeRuntime and buildRuntimeContext() or nil,
	}

	local ok, result = pcall(SpecRunner.Run, specs, ctx)
	if not ok then
		warn(PREFIX .. " Prüfer selbst abgestürzt: " .. tostring(result))
		return
	end

	for _, line in ipairs(SpecRunner.Format(result, PREFIX)) do
		-- Verstösse als warn (fallen in der Ausgabe auf), die Abschlusszeile als print.
		if string.find(line, "Regeln geprüft", 1, true) then
			print(line)
		else
			warn(line)
		end
	end
	print(string.format("%s %d Spec-Module geprüft (Studio%s)", PREFIX, #specs, includeRuntime and ", mit Laufzeit" or ""))
end

-- ===== Debug-Panel-Anbindung =====
local DebugRunSpecCheckEvent = RemoteEventUtils.GetOrCreate("DebugRunSpecCheckEvent")
DebugRunSpecCheckEvent.OnServerEvent:Connect(function(player)
	print(string.format("%s Erneute Prüfung angefordert von %s", PREFIX, player.Name))
	-- Von Hand ausgelöst heisst: das Spiel läuft, also auch die Laufzeit-Regeln prüfen.
	runCheck(true)
end)

task.spawn(function()
	task.wait(STARTUP_DELAY_SECONDS)
	runCheck(false)
end)

print(PREFIX .. " SpecCheckService bereit -- erste Prüfung in " .. STARTUP_DELAY_SECONDS .. "s.")
