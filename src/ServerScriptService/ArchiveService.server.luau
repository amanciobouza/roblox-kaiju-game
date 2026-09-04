-- Script: ArchiveService
-- Ort in Studio: ServerScriptService
--
-- Das Archiv: hält fest, welchen Figuren ein Spieler schon BEGEGNET ist. Nähe genügt --
-- besiegen ist nicht nötig, sehen reicht.
--
-- ===== Warum ein einzelner Wächter =====
-- Die sechs Dienste, die Feinde erzeugen (Militär, Feuerwehr, Barrikaden, Helikopter,
-- Guardians), melden hier NICHTS. Das war eine bewusste Entscheidung: in sechs laufende
-- Systeme hineinzugreifen wäre der grössere Eingriff gewesen, und jedes künftige
-- Feindsystem müsste daran denken. Stattdessen sucht dieser Dienst die Feinde selbst.
--
-- Der Preis dafür steht in ArchiveConfig: er erkennt sie an Modellnamen und Attributen.
-- Benennt ein Dienst seine Modelle um, fällt ein Eintrag still aus.
--
-- ===== Was NICHT zählt =====
-- Der Prolog. Dort begegnet man einem Guardian in einer geskripteten Szene; das Archiv
-- soll das freie Spiel abbilden. Gleiche Regel wie in der Lebensstatistik (IsInPrologue).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArchiveConfig = require(ReplicatedStorage:WaitForChild("ArchiveConfig"))
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local ArchiveRevealedEvent = RemoteEventUtils.GetOrCreate("ArchiveRevealedEvent")

-- Aufgedeckte Einträge liegen als Attribute am Spieler -- dasselbe Muster wie bei den
-- Statistiken und Achievements, dadurch im Studio-Explorer nachvollziehbar.
local ARCHIVE_ATTRIBUTE_PREFIX = "Archive_"

local ENCOUNTER_RADIUS = 200
local SCAN_INTERVAL = 1

-- ===== Erkennungstabellen =====
-- Einmal aufgebaut, damit der Wächter je Durchgang nur nachschlägt statt zu suchen.
local byModelName = {}
local byPrefix = {}
local attributeNames = {} -- welche Attribute ueberhaupt gelesen werden muessen
local byAttribute = {} -- [attributName][wert] = eintrag

for _, entry in ipairs(ArchiveConfig.Detectable) do
	local detect = entry.detect
	if detect.modelName then
		byModelName[detect.modelName] = entry
	elseif detect.modelPrefix then
		table.insert(byPrefix, { prefix = detect.modelPrefix, entry = entry })
	elseif detect.attribute then
		local name = detect.attribute.name
		if not byAttribute[name] then
			byAttribute[name] = {}
			table.insert(attributeNames, name)
		end
		byAttribute[name][detect.attribute.value] = entry
	end
end

-- Welchem Archiv-Eintrag entspricht dieses Modell (oder nil)?
local function matchEntry(instance)
	local direct = byModelName[instance.Name]
	if direct then
		return direct
	end
	for _, candidate in ipairs(byPrefix) do
		if string.sub(instance.Name, 1, #candidate.prefix) == candidate.prefix then
			return candidate.entry
		end
	end
	for _, attributeName in ipairs(attributeNames) do
		local value = instance:GetAttribute(attributeName)
		if value ~= nil then
			local entry = byAttribute[attributeName][value]
			if entry then
				return entry
			end
		end
	end
	return nil
end

-- ===== Aufdecken =====

local function isRevealed(player, entryId)
	return player:GetAttribute(ARCHIVE_ATTRIBUTE_PREFIX .. entryId) == true
end

-- silent = true beim Laden des Speicherstands: dort wird der Zustand wiederhergestellt,
-- nicht neu entdeckt -- keine Einblendung, keine Statistik.
local function revealEntry(player, entryId, silent)
	local entry = ArchiveConfig.ById[entryId]
	if not entry or isRevealed(player, entryId) then
		return false
	end
	player:SetAttribute(ARCHIVE_ATTRIBUTE_PREFIX .. entryId, true)
	if silent then
		return true
	end

	-- Fortschritt als STATISTIK führen, nicht als eigener Zähler. Die Achievements hängen
	-- über statKey daran (siehe AchievementService) -- so gibt es die Vergabe geschenkt,
	-- statt einen zweiten Mechanismus daneben zu bauen.
	if _G.RecordStat then
		_G.RecordStat(player, "ArchiveEntries")
		_G.RecordStat(player, "ArchiveCategory." .. entry.category)
	end

	ArchiveRevealedEvent:FireClient(player, entryId)
	print(string.format("[Kaiju-Debug] Archiv: '%s' für %s aufgedeckt.", entryId, player.Name))
	return true
end

_G.RevealArchiveEntry = function(player, entryId)
	return revealEntry(player, entryId, false)
end

_G.IsArchiveEntryRevealed = isRevealed

-- ===== Speicherstand =====
-- Gleiches Muster wie Talente, Achievements und Statistiken: PlayerSetup ruft diese beiden
-- Funktionen auf und muss die einzelnen Einträge nicht kennen.

_G.GetArchiveSaveData = function(player)
	local revealed = {}
	for name, value in pairs(player:GetAttributes()) do
		if value == true and string.sub(name, 1, #ARCHIVE_ATTRIBUTE_PREFIX) == ARCHIVE_ATTRIBUTE_PREFIX then
			table.insert(revealed, string.sub(name, #ARCHIVE_ATTRIBUTE_PREFIX + 1))
		end
	end
	return revealed
end

_G.LoadArchiveSaveData = function(player, saveData)
	if type(saveData) ~= "table" then
		return
	end
	local count = 0
	for _, entryId in ipairs(saveData) do
		-- Unbekannte Ids stillschweigend überspringen: ein Eintrag kann umbenannt oder
		-- entfernt worden sein, und ein alter Speicherstand darf daran nicht scheitern.
		if type(entryId) == "string" and ArchiveConfig.ById[entryId] then
			if revealEntry(player, entryId, true) then
				count += 1
			end
		end
	end
	print(string.format("[Kaiju-Debug] Archiv geladen für %s -- %d Einträge.", player.Name, count))
end

-- ===== Debug =====
-- Ohne das müsste man für jede Prüfung fünf Alarmstufen hochspielen. Deckt alles auf und
-- verbirgt auch wieder -- beide Richtungen, damit sich der Ausgangszustand herstellen
-- lässt.
_G.SetArchiveRevealAll = function(player, revealed)
	local changed = 0
	for _, entry in ipairs(ArchiveConfig.Entries) do
		if revealed then
			if revealEntry(player, entry.id, false) then
				changed += 1
			end
		elseif isRevealed(player, entry.id) then
			player:SetAttribute(ARCHIVE_ATTRIBUTE_PREFIX .. entry.id, nil)
			changed += 1
		end
	end
	if not revealed then
		-- Die Statistik mit zurücksetzen, sonst behielten die Achievements einen Stand,
		-- den das Archiv nicht mehr deckt.
		if _G.RecordStat then
			for _, category in ipairs(ArchiveConfig.Categories) do
				player:SetAttribute("Stat_ArchiveCategory." .. category.key, 0)
			end
			player:SetAttribute("Stat_ArchiveEntries", 0)
		end
		ArchiveRevealedEvent:FireClient(player, nil) -- Client baut neu auf
	end
	print(string.format(
		"[Kaiju-Debug] Archiv: alles %s für %s (%d Einträge geändert).",
		revealed and "aufgedeckt" or "verborgen", player.Name, changed
	))
end

-- ===== Modell-Auslieferung fuer die Vorschau =====
-- Die meisten Feindmodelle liegen in ServerStorage und sind fuer den Client unsichtbar.
-- Sie werden auf ANFRAGE geklont -- erst wenn jemand das Archiv oeffnet, nicht beim
-- Beitritt: die Mehrheit der Spieler oeffnet es selten, und alle dauerhaft dafuer zahlen
-- zu lassen waere der schlechtere Tausch.
--
-- Der Klon bleibt danach im Zwischenspeicher, statt nach jeder Anfrage wieder zu
-- verschwinden. Eine Instanz erreicht den Client nur, wenn sie fuer ihn sichtbar ist --
-- ein Modell mit kurzer Lebensdauer waere ein Wettlauf zwischen Aufraeumen und
-- Uebertragung. Einmal geladen, einmal bezahlt, fuer alle.
local ServerStorage = game:GetService("ServerStorage")

local previewFolder = ReplicatedStorage:FindFirstChild("ArchivePreviews")
if not previewFolder then
	previewFolder = Instance.new("Folder")
	previewFolder.Name = "ArchivePreviews"
	previewFolder.Parent = ReplicatedStorage
end

local ArchiveModelFunction = ReplicatedStorage:FindFirstChild("ArchiveModelFunction")
if not ArchiveModelFunction or not ArchiveModelFunction:IsA("RemoteFunction") then
	if ArchiveModelFunction then
		ArchiveModelFunction:Destroy()
	end
	ArchiveModelFunction = Instance.new("RemoteFunction")
	ArchiveModelFunction.Name = "ArchiveModelFunction"
	ArchiveModelFunction.Parent = ReplicatedStorage
end

-- Quelle in ServerStorage aufloesen. Alles andere (Workshop-Bau, Standard-Avatar,
-- ReplicatedStorage) baut der Client selbst -- er kommt ohne den Server daran.
local function findServerSource(model)
	if model.serverStorage then
		return ServerStorage:FindFirstChild(model.serverStorage)
	end
	if model.serverStorageFolder and model.child then
		local folder = ServerStorage:FindFirstChild(model.serverStorageFolder)
		return folder and folder:FindFirstChild(model.child)
	end
	return nil
end

ArchiveModelFunction.OnServerInvoke = function(player, entryId)
	if type(entryId) ~= "string" then
		return nil
	end
	-- BEWUSST ohne Pruefung auf "schon aufgedeckt". Der erste Entwurf hatte sie, als
	-- Schutz gegen neugierige Clients -- er machte aber genau das unmoeglich, wofuer das
	-- Modell da ist: die SILHOUETTE einer verdeckten Karte. Die Umrisse sind der Koeder,
	-- und sie ohne Modell zu zeichnen geht nicht.
	--
	-- Der Schutz haette ohnehin wenig getragen: die Silhouette zeigt die Form bereits, und
	-- ein Client, der das Modell auslesen will, sieht dieselben Gegner ohnehin im Spiel.
	local existing = previewFolder:FindFirstChild(entryId)
	if existing then
		return existing
	end
	local entry = ArchiveConfig.ById[entryId]
	if not entry or not entry.model then
		return nil
	end
	local source = findServerSource(entry.model)
	if not source then
		return nil
	end
	local ok, clone = pcall(function()
		return source:Clone()
	end)
	if not ok or not clone then
		warn("[ArchiveService] Vorschau-Modell fuer '" .. entryId .. "' liess sich nicht klonen.")
		return nil
	end
	clone.Name = entryId
	clone.Parent = previewFolder
	print("[Kaiju-Debug] Archiv: Vorschau-Modell '" .. entryId .. "' bereitgestellt.")
	return clone
end

-- DIAGNOSE: einmal beim Start berichten, welche Vorschau-Modelle tatsaechlich auffindbar
-- sind. Ohne das sieht "die Karte bleibt leer" identisch aus zu "das Modell liegt woanders"
-- und zu "der Name stimmt nicht" -- und ServerStorage ist von aussen nicht einsehbar.
task.delay(6, function()
	local found, missing = {}, {}
	for _, entry in ipairs(ArchiveConfig.Entries) do
		local model = entry.model
		if model and (model.serverStorage or model.serverStorageFolder) then
			local where = model.serverStorage
				or (model.serverStorageFolder .. "." .. tostring(model.child))
			if findServerSource(model) then
				table.insert(found, entry.id .. " (" .. where .. ")")
			else
				table.insert(missing, entry.id .. " -> ServerStorage." .. where)
			end
		end
	end
	print(string.format(
		"[Kaiju-Debug] Archiv-Vorschau: %d von %d ServerStorage-Modellen gefunden.",
		#found, #found + #missing
	))
	for _, line in ipairs(missing) do
		warn("[Kaiju-Debug] Archiv-Vorschau FEHLT: " .. line)
	end

	-- Was liegt stattdessen dort? Die Namen sind die haeufigste Fehlerquelle.
	local names = {}
	for _, child in ipairs(ServerStorage:GetChildren()) do
		table.insert(names, child.Name .. " [" .. child.ClassName .. "]")
	end
	table.sort(names)
	print("[Kaiju-Debug] Archiv-Vorschau: ServerStorage enthaelt -- "
		.. (#names > 0 and table.concat(names, ", ") or "NICHTS"))
end)

-- ===== Figuren =====
-- Nicht durch Begegnung, sondern durchs SPIELEN aufgedeckt: wer einen Skin trägt, kennt
-- ihn. Das Attribut sitzt am Charakter, nicht am Spieler (PlayerSetup.applySkinToCharacter).
local function watchSkin(player, character)
	local function check()
		local skinId = character:GetAttribute("SkinId")
		if type(skinId) == "number" and player:GetAttribute("IsInPrologue") ~= true then
			revealEntry(player, "SkinKaiju" .. skinId, false)
		end
	end
	character:GetAttributeChangedSignal("SkinId"):Connect(check)
	check()
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		watchSkin(player, character)
	end)
	if player.Character then
		watchSkin(player, player.Character)
	end
end)

-- ===== Der Wächter =====
task.spawn(function()
	while true do
		task.wait(SCAN_INTERVAL)

		-- Erst die Spieler sammeln, die überhaupt in Frage kommen. Ohne sie muss die
		-- Modellsuche gar nicht erst laufen.
		local watchers = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("IsInPrologue") ~= true then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if root and humanoid and humanoid.Health > 0 then
					table.insert(watchers, { player = player, position = root.Position })
				end
			end
		end
		if #watchers > 0 then
			-- Nur die oberste Workspace-Ebene: alle sechs Dienste parenten ihre Modelle
			-- direkt dorthin. Ein rekursiver Durchlauf waere um Groessenordnungen teurer,
			-- ohne mehr zu finden.
			for _, instance in ipairs(Workspace:GetChildren()) do
				local entry = matchEntry(instance)
				if entry then
					local ok, pivot = pcall(function()
						return instance:GetPivot().Position
					end)
					if ok then
						for _, watcher in ipairs(watchers) do
							if not isRevealed(watcher.player, entry.id) then
								if (pivot - watcher.position).Magnitude <= ENCOUNTER_RADIUS then
									revealEntry(watcher.player, entry.id, false)
								end
							end
						end
					end
				end
			end
		end
	end
end)

print(string.format(
	"[Kaiju] ArchiveService bereit -- %d Einträge, davon %d auffindbar.",
	#ArchiveConfig.Entries, #ArchiveConfig.Detectable
))
