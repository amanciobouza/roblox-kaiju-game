-- LocalScript: SanctuaryDialClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Macht aus den zwölf Indizes des Sanctuary-Zifferblatts eine Landkarte der Kampagne.
--
-- ===== Was ein Index zeigt =====
-- Fünf der zwölf Indizes stehen für eine Stadt (siehe CITY_BY_INDEX). Jeder von ihnen hat
-- drei Zustände:
--
--   dunkel            noch nie gebrochen und gerade kein Alarm -- der Index bleibt so, wie
--                     er gebaut wurde. Das Skript rührt ihn nicht an.
--   ruhig leuchtend   diese Stadt hat der Spieler schon einmal gebrochen. Eine Trophäe,
--                     die im Raum steht statt in einem Menü.
--   pulsierend        dort läuft GERADE etwas: die Farbe wandert mit der Alarmstufe von
--                     Gold nach Rot, der Puls wird schneller.
--
-- Die übrigen sieben Indizes werden NICHT angefasst. Sie bleiben dunkel, wie sie gebaut
-- sind -- Platz für Jaeger und Ronin. Ein halbvolles Zifferblatt liest sich als
-- Versprechen; sieben Indizes künstlich zu verdunkeln wäre nur Arbeit ohne Wirkung.
--
-- ===== Warum clientseitig =====
-- Zwei der drei Zustände sind pro Spieler verschieden: ob JEMAND die Stadt gebrochen hat,
-- ist keine Eigenschaft der Welt. Ein Server-Skript müsste also allen dasselbe zeigen und
-- damit das Falsche. Änderungen an Workspace-Teilen bleiben auf dem Client ohnehin lokal --
-- genau das, was hier gebraucht wird.
--
-- Ein Index sperrt NICHTS. Jeder darf jederzeit in jede Stadt; das Zifferblatt erzählt nur,
-- wo man schon war und wo es gerade brennt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ===== Welcher Index welche Stadt trägt =====
-- Auf den geraden Stunden, gleichmässig über das Blatt verteilt. Die Namen müssen exakt
-- denen in CityAlertConfig.CityOrder entsprechen -- daraus werden die Namen der Werte in
-- CityAlertValues und der Statistik gebildet.
local CITY_BY_INDEX = {
	[2] = "Village",
	[4] = "SmallTown",
	[6] = "City",
	[8] = "LargeCity",
	[10] = "MegaCity",
}

local INDEX_PREFIX = "Index_"

-- ===== Farben =====
-- Dieselbe Sprache wie das Alarm-HUD: Gold heisst "aktiv", das tiefe Rot des
-- City-Broken-Banners heisst "ganz oben".
local TROPHY_COLOR = Color3.fromRGB(255, 210, 80) -- schon gebrochen, ruhig
local ALERT_LOW_COLOR = Color3.fromRGB(255, 210, 80) -- Alarmstufe 1
local ALERT_HIGH_COLOR = Color3.fromRGB(200, 40, 30) -- Alarmstufe 5

-- Puls: bei Stufe 1 gemächlich, bei Stufe 5 hektisch.
local PULSE_SLOW_HZ = 0.5
local PULSE_FAST_HZ = 2.0
local PULSE_DEPTH = 0.45 -- wie weit die Helligkeit dabei einbricht

-- Der Puls läuft über eine eigene Schleife. Zehnmal je Sekunde reicht dafür vollkommen --
-- eine Farbänderung je Einzelbild wäre bei fünf Indizes mit je mehreren Teilen unnötiger
-- Aufwand für einen Effekt, den niemand unterscheiden kann.
local PULSE_UPDATE_INTERVAL = 0.1

-- ===== Zifferblatt finden =====
-- Der verabredete Pfad zuerst, danach eine Suche nach dem Namen. Der Modellname enthält
-- heute einen Tippfehler ("Trencborn" ohne h); wird er irgendwann berichtigt, findet die
-- Suche das Zifferblatt trotzdem -- und sagt in der Ausgabe, auf welchem Weg.
local EXPECTED_PATH = { "Sanctuary", "Trencborn_Sanctuary_V4", "Dial" }
local FIND_TIMEOUT = 20

local function findDial()
	local node = Workspace:WaitForChild(EXPECTED_PATH[1], FIND_TIMEOUT)
	if not node then
		warn("[Kaiju Debug] Zifferblatt: Workspace.Sanctuary nicht gefunden -- die Indizes bleiben, wie sie gebaut sind.")
		return nil
	end

	local exact = node
	for i = 2, #EXPECTED_PATH do
		exact = exact and exact:FindFirstChild(EXPECTED_PATH[i])
	end
	if exact then
		return exact
	end

	local found = node:FindFirstChild("Dial", true)
	if found then
		warn(string.format(
			"[Kaiju Debug] Zifferblatt nicht unter %s gefunden, aber als %s. "
				.. "Wurde das Modell umbenannt? Dann bitte EXPECTED_PATH nachziehen.",
			table.concat(EXPECTED_PATH, "."),
			found:GetFullName()
		))
		return found
	end

	warn("[Kaiju Debug] Zifferblatt: kein 'Dial' unter Workspace.Sanctuary -- die Indizes bleiben unberührt.")
	return nil
end

-- ===== Aussehen eines Index =====
-- Ein Index kann ein einzelnes Teil oder ein Modell aus mehreren sein. Beides wird auf
-- dieselbe Liste von BaseParts heruntergebrochen, und ihr Urzustand wird gemerkt: der ist
-- der Zustand "dunkel". So wird nichts erfunden, was der Bau nicht schon hergibt.
local function collectParts(indexObject)
	local parts = {}
	if indexObject:IsA("BasePart") then
		table.insert(parts, indexObject)
	end
	for _, descendant in ipairs(indexObject:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function rememberOriginal(parts)
	local original = {}
	for _, part in ipairs(parts) do
		original[part] = { color = part.Color, material = part.Material }
	end
	return original
end

local function applyDark(entry)
	for _, part in ipairs(entry.parts) do
		local origin = entry.original[part]
		if origin then
			part.Color = origin.color
			part.Material = origin.material
		end
	end
end

local function applyGlow(entry, color)
	for _, part in ipairs(entry.parts) do
		part.Color = color
		part.Material = Enum.Material.Neon
	end
end

-- ===== Zustand je Stadt =====
local function alertLevelOf(cityName)
	local folder = ReplicatedStorage:FindFirstChild("CityAlertValues")
	local value = folder and folder:FindFirstChild(cityName .. "Level")
	return (value and value.Value) or 0
end

local function everBroken(cityName)
	-- Statistiken liegen als Attribute am Spieler (StatsService, Präfix "Stat_") und
	-- replizieren damit von selbst zum Client. CityBrokenService zählt sie je Stadt hoch.
	return (player:GetAttribute("Stat_CityBroken." .. cityName) or 0) > 0
end

local dial = findDial()
if not dial then
	return
end

-- ===== Indizes einsammeln =====
local entries = {} -- [n] = { object, parts, original, city }
local missing = {}

for indexNumber, cityName in pairs(CITY_BY_INDEX) do
	local indexName = string.format("%s%02d", INDEX_PREFIX, indexNumber)
	local indexObject = dial:FindFirstChild(indexName)
	if indexObject then
		local parts = collectParts(indexObject)
		if #parts > 0 then
			entries[indexNumber] = {
				object = indexObject,
				parts = parts,
				original = rememberOriginal(parts),
				city = cityName,
			}
		else
			table.insert(missing, indexName .. " (kein BasePart darin)")
		end
	else
		table.insert(missing, indexName)
	end
end

if #missing > 0 then
	warn("[Kaiju Debug] Zifferblatt: diese Indizes fehlen oder sind leer -- " .. table.concat(missing, ", "))
end

-- ===== Zustände setzen =====
-- pulsing enthält die Indizes, die gerade blinken. Ist sie leer, läuft die Schleife unten
-- gar nicht erst -- im Normalfall, also ohne Alarm irgendwo, kostet dieses Skript nichts.
local pulsing = {}

local function refreshIndex(indexNumber)
	local entry = entries[indexNumber]
	if not entry then
		return
	end

	local level = alertLevelOf(entry.city)
	if level > 0 then
		-- Farbe wandert mit der Stufe von Gold nach Rot. Stufe 5 ist die Höchststufe im
		-- Spiel, deshalb teilt die Rechnung durch 4 (Stufe 1 = 0, Stufe 5 = 1).
		local t = math.clamp((level - 1) / 4, 0, 1)
		pulsing[indexNumber] = {
			base = ALERT_LOW_COLOR:Lerp(ALERT_HIGH_COLOR, t),
			hz = PULSE_SLOW_HZ + (PULSE_FAST_HZ - PULSE_SLOW_HZ) * t,
		}
		return
	end

	pulsing[indexNumber] = nil
	if everBroken(entry.city) then
		applyGlow(entry, TROPHY_COLOR)
	else
		applyDark(entry)
	end
end

local function refreshAll()
	for indexNumber in pairs(entries) do
		refreshIndex(indexNumber)
	end
end

-- ===== Auf Änderungen hören =====
-- Alarmstufen ändern sich selten; ein eigenes Signal je Stadt ist billiger als Nachfragen.
local alertFolder = ReplicatedStorage:WaitForChild("CityAlertValues", FIND_TIMEOUT)
if alertFolder then
	for indexNumber, cityName in pairs(CITY_BY_INDEX) do
		local levelValue = alertFolder:FindFirstChild(cityName .. "Level")
		if levelValue then
			levelValue:GetPropertyChangedSignal("Value"):Connect(function()
				refreshIndex(indexNumber)
			end)
		end
	end
else
	warn("[Kaiju Debug] Zifferblatt: CityAlertValues nicht gefunden -- die Indizes zeigen keinen Alarm an.")
end

for indexNumber, cityName in pairs(CITY_BY_INDEX) do
	player:GetAttributeChangedSignal("Stat_CityBroken." .. cityName):Connect(function()
		refreshIndex(indexNumber)
	end)
end

refreshAll()

-- ===== Puls =====
local accumulator = 0
RunService.Heartbeat:Connect(function(deltaTime)
	if next(pulsing) == nil then
		return
	end
	accumulator += deltaTime
	if accumulator < PULSE_UPDATE_INTERVAL then
		return
	end
	accumulator = 0

	local now = Workspace:GetServerTimeNow()
	for indexNumber, pulse in pairs(pulsing) do
		local entry = entries[indexNumber]
		if entry then
			-- Sinus zwischen 0 und 1, daraus ein Helligkeitsfaktor. Alle Spieler rechnen
			-- aus derselben Serverzeit -- die Indizes pulsen damit im Gleichtakt, auch wenn
			-- jeder Client für sich rechnet.
			local wave = (math.sin(now * pulse.hz * math.pi * 2) + 1) / 2
			local brightness = 1 - PULSE_DEPTH * (1 - wave)
			applyGlow(entry, Color3.new(
				pulse.base.R * brightness,
				pulse.base.G * brightness,
				pulse.base.B * brightness
			))
		end
	end
end)

print(string.format(
	"[Kaiju Debug] Zifferblatt bereit: %d von %d Indizes tragen eine Stadt (%s).",
	(function()
		local n = 0
		for _ in pairs(entries) do
			n += 1
		end
		return n
	end)(),
	12,
	dial:GetFullName()
))
