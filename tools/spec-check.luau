--!nolint
-- Kopfloser Spec-Prüfer -- läuft OHNE Roblox, direkt über den Luau-Interpreter.
--
--   luau tools/spec-check.luau
--
-- Muss aus dem Projektstamm aufgerufen werden (Rokit sucht dort rokit.toml). Wird vom
-- Stop-Hook automatisch ausgeführt, siehe .claude/settings.json.
--
-- Er kennt NUR die Config-Module -- kein Workspace, kein laufendes Spiel. Regeln mit
-- needsWorkspace oder needsRuntime werden übersprungen und in der Abschlusszeile gezählt.
-- Für die läuft der Prüfer in Studio (SpecCheckService).
--
-- ACHTUNG, bekannte Schwäche: Luau hat kein io-Modul, dieser Prüfer kann also keine
-- Verzeichnisse durchsuchen. Die Spec-Liste unten ist deshalb von Hand geführt. Der
-- Studio-Prüfer zählt seine Specs dagegen selbst aus dem Ordner -- weichen die beiden
-- Zahlen voneinander ab, fehlt hier ein Eintrag.

local SpecRunner = require("../src/ReplicatedStorage/Specs/SpecRunner")

-- Beim Ergänzen einer Spec: HIER eintragen.
--
-- Die Workshop-Spec liegt im Submodul, nicht unter src/Specs -- Asset-Specs bleiben bei
-- ihrem Asset, damit der Workshop in seinem eigenen Place für sich lauffähig bleibt.
local WORKSHOP = "../packages/trenchborn-asset-workshop/src/ReplicatedStorage/TrenchbornAssetWorkshop/"

local specs = {
	require("../src/ReplicatedStorage/Specs/CityAlertSpec"),
	require("../src/ReplicatedStorage/Specs/PlayerDataSpec"),
	require("../src/ReplicatedStorage/Specs/ShowdownSpec"),
	require("../src/ReplicatedStorage/Specs/BalancingSpec"),
	require(WORKSHOP .. "WorkshopAssetSpec"),
}

local ctx = {
	config = {
		CityAlert = require("../src/ReplicatedStorage/CityAlertConfig"),
		TalentTree = require("../src/ReplicatedStorage/TalentTreeConfig"),
		Achievements = require("../src/ReplicatedStorage/AchievementsConfig"),
		Showdown = require("../src/ReplicatedStorage/ShowdownConfig"),
		Skins = require("../src/ReplicatedStorage/SkinsConfig"),
		-- Die Asset-Spezifikationen sind für die Regeln DATEN, keine Specs -- deshalb
		-- stehen sie hier im config-Teil, nicht in der Spec-Liste oben.
		WorkshopAssets = {
			WardenIShepherd = require(WORKSHOP .. "AssetSpecification"),
			MarshalIIRoadblock = require(WORKSHOP .. "MarshalRoadblockSpecification"),
		},
	},
	-- workspace/runtime bleiben nil -- die entsprechenden Regeln werden übersprungen.
	workspace = nil,
	runtime = nil,
}

local result = SpecRunner.Run(specs, ctx)

for _, line in ipairs(SpecRunner.Format(result, "[Kaiju Spec]")) do
	print(line)
end
print(string.format("[Kaiju Spec] %d Spec-Module geprüft (kopflos)", #specs))

-- Rückgabewert für den Stop-Hook: nur NEUE Verstösse und defekte Regeln halten an.
-- Bekannte Abweichungen laufen bewusst durch -- der Rückstand darf passieren, die
-- Regression nicht (siehe Q15).
if #result.new > 0 or result.failed > 0 then
	error(
		string.format(
			"[Kaiju Spec] ABBRUCH: %d neue Verstösse, %d defekte Regeln -- bitte beheben oder als knownViolations erfassen.",
			#result.new,
			result.failed
		),
		0
	)
end
