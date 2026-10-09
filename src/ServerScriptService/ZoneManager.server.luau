-- Script (kein LocalScript!): ZoneManager
-- Ort in Studio: ServerScriptService
-- Erwartet GENAU EINEN Part/Union im Workspace: "SanctuaryZone".
-- Setzt am Spieler das Attribut "CurrentZone" ("Sanctuary" oder "PvE"), das andere
-- Skripte auslesen können.
--
-- ===== Eine Zone statt drei (02.10.2026) =====
-- Hier standen drei Zonenkörper: SanctuaryZone, CollectZone, AttackZone. Zwei davon
-- mussten in Studio gepflegt werden, ohne je eine eigene Aussage zu treffen -- im ganzen
-- Projekt wurde NIE auf "PvE" geprüft, sondern immer nur auf "Sanctuary" oder dessen
-- Gegenteil. Ein Zonenkörper, der nur beantwortet, wo er NICHT ist, ist Arbeit ohne
-- Ergebnis.
--
-- Jetzt gilt die einfache Regel: innerhalb des Sanctuary ist Sanctuary, alles andere ist
-- Sammelgebiet. Dafür braucht es keinen zweiten Körper -- und keine Lücke mehr zwischen
-- den Zonen, in der ein Spieler in keiner von ihnen stand ("None" gibt es nicht mehr).
--
-- ACHTUNG: "PvP" wird damit NIE mehr gesetzt. Die Spieler-gegen-Spieler-Zweige in
-- CombatHandler und SpecialAttackHandler sind seither unerreichbar. Sie stehen noch da;
-- ob sie bleiben, ist eine Entscheidung über das Spiel und keine über dieses Skript.
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

-- Der einzige Zonenkörper. Alles ausserhalb davon ist Sammelgebiet.
local SANCTUARY_PART_NAME = "SanctuaryZone"
local ZONE_INNEN = "Sanctuary" -- friedliche Startzone: keine Angriffe ausser beim Training
local ZONE_AUSSEN = "PvE" -- Sammelgebiet: Häuser zerstören

-- Eine Prioritätenliste braucht es nicht mehr: es gibt nur noch drinnen und draussen, und
-- zwischen beiden kann man nicht gleichzeitig stehen.

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
		-- Noch kein Rumpf -- also nicht messbar. Draussen ist auch hier die sichere
		-- Annahme, und sie aendert nichts: alle Pruefungen im Projekt fragen "ist es
		-- Sanctuary?", und das war beim frueheren "None" ebenso wenig der Fall.
		return ZONE_AUSSEN
	end

	-- Fusshöhe statt Rumpfhöhe: die Füsse stehen unabhängig von der Skalierung auf dem
	-- Boden, der Rumpf sitzt bei einer grossen Figur dagegen viel höher.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local footY = rootPart.Position.Y - rootPart.Size.Y / 2 - (humanoid and humanoid.HipHeight or 0)
	local probe = getProbe(character)
	probe.CFrame = CFrame.new(rootPart.Position.X, footY + PROBE_SIZE.Y / 2, rootPart.Position.Z)

	-- ===== Die Abfrage laeuft seit dem 02.10.2026 ANDERSHERUM =====
	-- Hier stand dreimal GetPartsInPart(zonePart, ...) -- einmal je Zone, und jedes Mal
	-- lautete die Frage: "welche Teile liegen in diesem riesigen Zonenvolumen?", gefiltert
	-- auf den einen Pruefkoerper. Der Filter verkleinert das ERGEBNIS, nicht die Suche: die
	-- Physik muss das ganze Volumen durchgehen, und die Zonen sind Unions ueber ganze
	-- Landstriche.
	--
	-- GEMESSEN: der ZoneManager stand mit 18.01 % Skriptzeit auf Platz eins der
	-- Server-Liste -- das Naechste lag bei 0.83 %. Er allein machte rund 85 % aller
	-- Lua-Zeit, bei 3 Durchlaeufen je Sekunde. Das erklaert die 24 ms Mittel und die
	-- Spitzen bis 152 ms im Leerlauf.
	--
	-- Jetzt die umgekehrte Frage: "beruehrt dieser kleine Quader das Sanctuary?" Ein Aufruf
	-- statt dreier, und das durchsuchte Volumen ist 2x4x2 Studs statt eines Landstrichs.
	-- Die Antwort ist dieselbe -- Ueberlappung ist symmetrisch.
	local sanctuary = getZonePart(SANCTUARY_PART_NAME)
	if not sanctuary then
		-- Ohne den Koerper gibt es kein Drinnen. Draussen ist die sichere Annahme: der
		-- Spieler kann dann spielen, statt in einer Friedenszone festzustecken, die es
		-- gar nicht gibt. Gewarnt wird beim Start (siehe unten).
		return ZONE_AUSSEN
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { sanctuary }
	overlapParams.MaxParts = 1

	-- Der Pruefkoerper bleibt dabei fuer Abfragen UNSICHTBAR (CanQuery = false). Er ist
	-- jetzt der Fragende und nicht mehr der Gesuchte -- das kurzzeitige Sichtbarschalten
	-- von frueher entfaellt ersatzlos, und damit auch die Gefahr, dass er in dieser
	-- Spanne einen fremden Raycast stoert.
	local ok, overlapping = pcall(function()
		return Workspace:GetPartsInPart(probe, overlapParams)
	end)

	if ok and #overlapping > 0 then
		return ZONE_INNEN
	end
	return ZONE_AUSSEN
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

do
	local partName = SANCTUARY_PART_NAME
	local zonePart = getZonePart(partName)
	if not zonePart then
		warn("Zone-Part '" .. partName .. "' nicht im Workspace gefunden -- OHNE ihn ist "
			.. "die ganze Welt Sammelgebiet, auch das Sanctuary. Siehe LOCATIONS_ANLEITUNG.md")
	elseif zonePart:IsA("BasePart") and not zonePart.CanQuery then
		-- ===== Seit der umgekehrten Abfrage zaehlt das =====
		-- Frueher war das Zonen-Teil der Fragende, da spielte sein CanQuery keine Rolle.
		-- Jetzt ist es das Gesuchte: steht CanQuery auf false, findet der Pruefkoerper es
		-- NIE -- und die ganze Welt waere Sammelgebiet, ohne dass irgendetwas abstuerzt.
		-- Genau die Sorte Fehler, die man im Spiel erst nach einer Stunde bemerkt.
		warn(string.format("[ZoneManager] Zone-Part %q hat CanQuery = false und kann damit "
			.. "nicht gefunden werden -- diese Zone bliebe wirkungslos. In Studio auf true "
			.. "setzen.", partName))
	end
end