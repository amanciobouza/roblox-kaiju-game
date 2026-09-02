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

-- Ein Zonenwechsel gilt erst, wenn er MEHRMALS HINTEREINANDER gemessen wurde.
--
-- Grund ist eine Rückkopplung, die sich selbst antreibt: PlayerSetup skaliert die Figur
-- je nach Zone (im Sanctuary 0.5 + Scale*0.1, sonst die volle Skin-Skalierung). Wie weit
-- eine Figur in ein Zonenvolumen hineinragt, hängt aber direkt an ihrer Grösse. Nahe der
-- Grenze entstand daraus ein Kreis: grosse Figur ragt in den Sanctuary-Part -> Zone
-- Sanctuary -> Figur schrumpft -> kleine Figur berührt den Part nicht mehr -> Zone None
-- -> Figur wächst -> ... Die Zone kippte damit im Takt dieses Pollings hin und her, und
-- mit ihr die Sprungkraft (siehe recalculateJumpPower in PlayerSetup) -- wer im falschen
-- Moment sprang, tat das als grosse Figur mit der Sprungkraft der kleinen und kam kaum
-- vom Boden.
--
-- Eine alternierende Messung erreicht nie zwei gleiche Werte in Folge und kann die Zone
-- deshalb nicht mehr umschalten: der Spieler behält an der Grenze die Zone, die er hatte.
-- Das ist auch das gewünschte Verhalten -- eine Grenze soll nicht mehrmals pro Sekunde
-- den Besitzer wechseln.
local ZONE_CHANGE_CONFIRMATIONS = 2

-- [player] = { zone = <gemessene Zone>, count = <wie oft in Folge> }
local pendingZone = {}

local function getZonePart(partName)
	return Workspace:FindFirstChild(partName)
end

-- ===== Prüfkörper =====
-- Gemessen wird NICHT mehr mit dem ganzen Charakter, sondern mit einem Quader fester
-- Grösse zu Füssen des Spielers.
--
-- Grund: PlayerSetup skaliert die Figur je nach Zone (Sanctuary 0.5 + Scale*0.1, sonst
-- die volle Skin-Skalierung, bis Scale 6). Wie weit ein Charakter in ein Zonenvolumen
-- hineinragt, hängt damit an seiner Grösse -- und die Grösse hängt am Messergebnis. Das
-- ergab an der Grenze einen sich selbst antreibenden Kreis: grosse Figur ragt hinein ->
-- Zone Sanctuary -> Figur schrumpft -> kleine Figur ragt nicht mehr hinein -> Zone None
-- -> Figur wächst -> ... Die Zone kippte im Takt dieses Pollings, und mit ihr die
-- Sprungkraft (recalculateJumpPower in PlayerSetup) -- wer im falschen Moment sprang, tat
-- das als grosse Figur mit der Sprungkraft der kleinen und kam kaum vom Boden.
--
-- Ein Prüfkörper fester Grösse an den Füssen kennt dieses Problem nicht: er beantwortet
-- die Frage "steht der Spieler drin?" unabhängig davon, wie gross der Spieler gerade ist.
-- Das ist auch inhaltlich die richtige Frage -- wer neben dem Sanctuary steht und nur mit
-- der Schulter hineinragt, steht nicht darin.
local PROBE_SIZE = Vector3.new(2, 4, 2)

-- BEWUSST NICHT im Charakter geparkt, sondern in einem eigenen Ordner im Workspace.
-- Zwei Gründe: character:ScaleTo() würde einen Prüfkörper im Modell mitskalieren (und
-- ihn damit wieder grössenabhängig machen), und character:GetBoundingBox() -- die
-- Grundlage der Sprungkraft-Berechnung in PlayerSetup -- würde ihn mitmessen. Da er nur
-- alle POLL_INTERVAL Sekunden nachgeführt wird, bliebe er bei einer schnellen grossen
-- Figur zurück und würde die Bounding Box aufblähen.
local probeFolder = Workspace:FindFirstChild("ZoneProbes")
if not probeFolder then
	probeFolder = Instance.new("Folder")
	probeFolder.Name = "ZoneProbes"
	probeFolder.Parent = Workspace
end

-- [character] = Prüfkörper. Schwache Schlüssel: stirbt der Charakter, verschwindet der
-- Eintrag von selbst; den Part räumt characterRemoving weg.
local probes = setmetatable({}, { __mode = "k" })

local function getProbe(character)
	local probe = probes[character]
	if not probe or not probe.Parent then
		probe = Instance.new("Part")
		probe.Name = "ZoneProbe"
		probe.Size = PROBE_SIZE
		probe.Anchored = true
		probe.CanCollide = false
		probe.CanTouch = false
		-- Standardmässig für Abfragen UNSICHTBAR, damit dieser Hilfskörper keine fremden
		-- Raycasts stört (Boden-Erkennung des Guardians, Zielerfassung, ...). Nur für die
		-- Dauer der Zonenabfrage unten wird er kurz sichtbar geschaltet.
		probe.CanQuery = false
		probe.Transparency = 1
		probe.Parent = probeFolder
		probes[character] = probe
	end
	return probe
end

local function releaseProbe(character)
	local probe = probes[character]
	if probe then
		probe:Destroy()
		probes[character] = nil
	end
end

local function determineCurrentZone(character)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return "None"
	end

	-- Fusshöhe statt Rumpfhöhe: die Füsse stehen unabhängig von der Skalierung auf dem
	-- Boden, der Rumpf sitzt bei einer grossen Figur dagegen viel höher.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local footY = rootPart.Position.Y - rootPart.Size.Y / 2 - (humanoid and humanoid.HipHeight or 0)
	local probe = getProbe(character)
	probe.CFrame = CFrame.new(rootPart.Position.X, footY + PROBE_SIZE.Y / 2, rootPart.Position.Z)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { probe }

	-- Zwischen diesem Einschalten und dem Ausschalten unten darf NICHT nachgegeben werden
	-- (kein task.wait, kein Yield) -- sonst könnte in der Zwischenzeit ein fremder Raycast
	-- den Prüfkörper treffen.
	probe.CanQuery = true

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

	probe.CanQuery = false

	for _, zoneName in ipairs(ZONE_PRIORITY) do
		if foundZones[zoneName] then
			return zoneName
		end
	end
	return "None"
end

-- immediate = true umgeht die Bestätigungen (beim Spawnen gibt es keine Vorgeschichte,
-- die flattern könnte, und die Zone muss sofort stimmen).
local function pollPlayer(player, immediate)
	local character = player.Character
	if not character then
		return
	end
	local zone = determineCurrentZone(character)

	if zone == player:GetAttribute("CurrentZone") then
		pendingZone[player] = nil -- Messung bestätigt den Ist-Zustand
		return
	end

	if immediate then
		pendingZone[player] = nil
		player:SetAttribute("CurrentZone", zone)
		return
	end

	local pending = pendingZone[player]
	if pending and pending.zone == zone then
		pending.count += 1
	else
		pending = { zone = zone, count = 1 }
		pendingZone[player] = pending
	end

	if pending.count >= ZONE_CHANGE_CONFIRMATIONS then
		pendingZone[player] = nil
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
		pollPlayer(player, true)
	end)
	player.CharacterRemoving:Connect(releaseProbe)
end)

Players.PlayerRemoving:Connect(function(player)
	pendingZone[player] = nil
	if player.Character then
		releaseProbe(player.Character)
	end
end)

for _, partName in pairs({ "SanctuaryZone", "CollectZone", "AttackZone" }) do
	if not getZonePart(partName) then
		warn("Zone-Part '" .. partName .. "' nicht im Workspace gefunden. Siehe LOCATIONS_ANLEITUNG.md")
	end
end