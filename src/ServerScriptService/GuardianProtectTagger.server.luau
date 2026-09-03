-- Script: GuardianProtectTagger
-- Ort in Studio: ServerScriptService
--
-- Vergibt den 'GuardianProtect'-Tag automatisch, statt ihn in Studio von Hand zu setzen.
--
-- Regel: jede KaijuHouse-Sektion, deren Asset die Stufe L2 oder L3 hat, ist
-- schützenswert. Kleinere Gebäude (L1) sind Füllmaterial -- ein Guardian, der sich
-- davorstellt, bewacht Kulisse.
--
-- ===== Warum das nötig war =====
-- Ohne Tags greift in CityDefenderService.findProtectedBuildings ein Rückfall, der
-- GENAU EIN Gebäude je Stadt wählt (das mit der höchsten MaxHealth). Der Guardian
-- verteidigte damit eine einzelne Ecke der Stadt und blieb untätig, sobald der Spieler
-- irgendwo anders zerstörte -- der Hauptgrund, warum er passiv wirkte. Ausserdem wird
-- der Spawn-Punkt ersatzweise aus einem geschützten Gebäude abgeleitet.
--
-- ===== Woher die Stufe kommt =====
-- Die Installer unter TrenchbornInstallers setzen am Asset-Root das Attribut
-- 'BuildingLevel' (und gleichlautend 'AssetLevel') auf "L2"/"L3". Es hängt am ROOT des
-- Assets, nicht an der einzelnen Sektion -- deshalb wird von der Sektion aus nach oben
-- gesucht. Bis hierher las das Attribut niemand.

local CollectionService = game:GetService("CollectionService")

local HOUSE_TAG = "KaijuHouse"
local GUARDIAN_PROTECT_TAG = "GuardianProtect"

-- Welche Stufen gelten als schützenswert.
local PROTECTED_LEVELS = {
	L2 = true,
	L3 = true,
}

-- Wie weit von der Sektion aus nach oben gesucht wird. Begrenzt, damit eine Sektion ohne
-- Stufen-Attribut nicht bei jedem Durchlauf die halbe Instanzhierarchie bis zum
-- DataModel hochläuft.
local MAX_ANCESTOR_DEPTH = 8

-- Liest die Stufe eines Gebäudes: erst an der Sektion selbst, dann aufwärts bis zum
-- Asset-Root. 'BuildingLevel' hat Vorrang, 'AssetLevel' ist der ältere Zwilling --
-- beide werden von denselben Installern gesetzt.
local function resolveBuildingLevel(house)
	local node = house
	local depth = 0
	while node and depth < MAX_ANCESTOR_DEPTH do
		local level = node:GetAttribute("BuildingLevel") or node:GetAttribute("AssetLevel")
		if type(level) == "string" and level ~= "" then
			return level
		end
		node = node.Parent
		depth += 1
	end
	return nil
end

-- Gibt true zurück, wenn dabei NEU getaggt wurde -- nur für die Zählung unten.
local function applyTag(house)
	if CollectionService:HasTag(house, GUARDIAN_PROTECT_TAG) then
		return false
	end
	local level = resolveBuildingLevel(house)
	if not level or not PROTECTED_LEVELS[level] then
		return false
	end
	CollectionService:AddTag(house, GUARDIAN_PROTECT_TAG)
	return true
end

local tagged = 0

local function scanAll()
	for _, house in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		if applyTag(house) then
			tagged += 1
		end
	end
end

scanAll()

-- Nachzügler: Häuser, die erst später den KaijuHouse-Tag bekommen -- beim Respawn, bei
-- nachgeladenen Stadtteilen, und vor allem dann, wenn HouseHandler seine Tags erst NACH
-- diesem Skript setzt. Die Startreihenfolge der Skripte in ServerScriptService ist nicht
-- festgelegt, deshalb darf der einmalige Durchlauf oben nicht die einzige Quelle sein.
CollectionService:GetInstanceAddedSignal(HOUSE_TAG):Connect(function(house)
	if applyTag(house) then
		tagged += 1
	end
end)

-- Zusammenfassung bewusst VERZÖGERT: sofort gedruckt stünde dort je nach
-- Startreihenfolge eine Null, obwohl gleich darauf alles korrekt getaggt wird -- und man
-- würde den Fehler beim Tagger suchen statt bei den Attributen. Vor dem Spec-Prüfer
-- (8 Sekunden), damit beide Zahlen im Output zusammenpassen.
local SUMMARY_DELAY_SECONDS = 5

task.delay(SUMMARY_DELAY_SECONDS, function()
	-- Aufschlüsselung JE STADT. Eine Gesamtzahl reicht nicht: der Spec-Prüfer fragt pro
	-- Stadt, und die Städte sind unterschiedlich ausgestattet -- nur die City-Assets
	-- laufen bisher durch die TrenchbornInstallers, die 'BuildingLevel' setzen.
	--
	-- Bewusst wird auch "ohne Stadt" gezählt: der Prüfer UND der Guardian ordnen ein
	-- Gebäude über _G.ResolveCityName zu. Lässt sich die Stadt nicht auflösen, ist das
	-- Gebäude für beide unsichtbar -- auch wenn der Tag im Explorer sauber dransteht.
	-- Ohne diese Spalte sähen die beiden Fehlerbilder identisch aus.
	local perCity = {}
	local function bucket(cityName)
		local key = cityName or "ohne Stadt"
		local entry = perCity[key]
		if not entry then
			entry = { houses = 0, eligible = 0, tagged = 0 }
			perCity[key] = entry
		end
		return entry
	end

	for _, house in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		local cityName = _G.ResolveCityName and _G.ResolveCityName(house) or nil
		local entry = bucket(cityName)
		entry.houses += 1
		local level = resolveBuildingLevel(house)
		if level and PROTECTED_LEVELS[level] then
			entry.eligible += 1
		end
		if CollectionService:HasTag(house, GUARDIAN_PROTECT_TAG) then
			entry.tagged += 1
		end
	end

	local cityNames = {}
	for cityName in pairs(perCity) do
		table.insert(cityNames, cityName)
	end
	table.sort(cityNames)

	print(string.format(
		"[Kaiju-Debug] GuardianProtect automatisch vergeben -- %d Sektionen neu getaggt.",
		tagged
	))
	if #cityNames == 0 then
		warn("[Kaiju-Debug] GuardianProtect: keine KaijuHouse-Sektionen gefunden.")
		return
	end
	for _, cityName in ipairs(cityNames) do
		local entry = perCity[cityName]
		print(string.format(
			"[Kaiju-Debug]   %-14s Sektionen: %4d | L2/L3: %4d | getaggt: %4d",
			cityName, entry.houses, entry.eligible, entry.tagged
		))
	end
	if not _G.ResolveCityName then
		warn("[Kaiju-Debug] GuardianProtect: _G.ResolveCityName war nicht verfügbar -- "
			.. "alle Sektionen stehen unter 'ohne Stadt'.")
	end
end)
