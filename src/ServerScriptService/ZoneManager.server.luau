-- Script (kein LocalScript!): ZoneManager
-- Ort in Studio: ServerScriptService
-- Erwartet 3 Parts/Unions im Workspace: "SanctuaryZone", "CollectZone", "AttackZone".
-- Setzt am Spieler das Attribut "CurrentZone" ("Sanctuary" / "PvE" / "PvP" / "None"),
-- das andere Skripte (z.B. CombatHandler) auslesen können.
--
-- WICHTIG: Nutzt bewusst KEINE .Touched/.TouchEnded-Events mehr (frühere Version) --
-- bei komplexer Union-Geometrie (z.B. eine Donut-Form: äussere Scheibe minus innere
-- Scheibe) können diese Events unzuverlässig sein, je nach CollisionFidelity der Union
-- kann die tatsächliche Kollisionsform von der sichtbaren Form abweichen. Stattdessen
-- wird mehrmals pro Sekunde per GetPartsInPart aktiv geprüft, in welcher Zone sich jeder
-- Spieler GERADE befindet -- das funktioniert unabhängig von Touch-Zuverlässigkeit,
-- deckt automatisch auch den Spawn-Fall ab (Charakter startet direkt in einer Zone), und
-- braucht keine Sonderbehandlung für "von aussen betreten" vs. "steht schon drin".

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Part-Name im Workspace -> Zonen-Wert (wird als "CurrentZone"-Attribut gesetzt)
local ZONE_PARTS = {
	SanctuaryZone = "Sanctuary", -- friedliche Startzone, kein PvP/PvE möglich
	CollectZone = "PvE", -- Häuser zerstören
	AttackZone = "PvP", -- Spieler-gegen-Spieler
}

-- Priorität bei Überlappung mehrerer Zonen gleichzeitig (z.B. an einer Kante) -- Sanctuary
-- gewinnt immer (sicherste Zone), danach PvE, danach PvP. Ersetzt das vorherige
-- "irgendeine beliebige Zone" (next() auf einer Tabelle liefert keine feste Reihenfolge).
local ZONE_PRIORITY = { "Sanctuary", "PvE", "PvP" }

local POLL_INTERVAL = 0.3 -- Sekunden zwischen zwei Prüfungen

local function getZonePart(partName)
	return Workspace:FindFirstChild(partName)
end

local function determineCurrentZone(character)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return "None"
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { character }

	local foundZones = {}
	for partName, zoneName in pairs(ZONE_PARTS) do
		local zonePart = getZonePart(partName)
		if zonePart then
			local ok, overlapping = pcall(function()
				return Workspace:GetPartsInPart(zonePart, overlapParams)
			end)
			if ok and #overlapping > 0 then
				foundZones[zoneName] = true
			end
		end
	end

	for _, zoneName in ipairs(ZONE_PRIORITY) do
		if foundZones[zoneName] then
			return zoneName
		end
	end
	return "None"
end

local function pollPlayer(player)
	local character = player.Character
	if not character then
		return
	end
	local zone = determineCurrentZone(character)
	if player:GetAttribute("CurrentZone") ~= zone then
		player:SetAttribute("CurrentZone", zone)
	end
end

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			pollPlayer(player)
		end
		task.wait(POLL_INTERVAL)
	end
end)

-- Beim Spawnen: kein Warten auf den nächsten Poll-Durchlauf nötig, aber ein kurzer Delay,
-- damit der Charakter tatsächlich in der Welt positioniert ist (Skalierung etc. können
-- sonst noch nicht abgeschlossen sein).
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5)
		pollPlayer(player)
	end)
end)

for _, partName in pairs({ "SanctuaryZone", "CollectZone", "AttackZone" }) do
	if not getZonePart(partName) then
		warn("Zone-Part '" .. partName .. "' nicht im Workspace gefunden. Siehe LOCATIONS_ANLEITUNG.md")
	end
end