-- LocalScript: SanctuaryDialClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Macht aus den zwölf Indizes des Sanctuary-Zifferblatts eine Landkarte der Kampagne.
--
-- ===== Was ein Index zeigt =====
-- Fünf der zwölf Indizes stehen für eine Stadt (siehe CITY_BY_INDEX). Jeder von ihnen hat
-- drei Zustände:
--
--   dunkel            noch nicht dran -- der Index bleibt so, wie er gebaut wurde. Das
--                     Skript rührt ihn nicht an.
--   ruhig leuchtend   diese Stadt hat der Spieler schon gebrochen. Eine Trophäe, die im
--                     Raum steht statt in einem Menü.
--   pulsierend        DEIN NÄCHSTES ZIEL. Genau ein Index trägt das -- die erste Stadt, die
--                     dieser Spieler noch nicht gebrochen hat.
--
-- ===== Das Blatt gehört dem Betrachter (27.09.2026) =====
-- Der Puls zeigte vorher die Alarmstufe der Stadt, also den Zustand der WELT. Auf diesem
-- Blatt war das fast nie zu gebrauchen: es hängt im Sanctuary, und wer davorsteht, ist per
-- Definition in keiner Stadt. Was dort pulste, war meist die Lage eines fremden Spielers --
-- die einzige Bewegung auf dem Blatt zog den Blick also auf etwas, das den Betrachter
-- nichts anging.
--
-- Jetzt beantwortet das Blatt drei Fragen ohne ein einziges Wort: wo war ich, wo stehe ich,
-- wohin als nächstes. Die Alarmstufe steht im HUD, sobald man in einer Stadt ist -- dort,
-- wo sie einen wirklich betrifft.
--
-- Die übrigen sieben Indizes werden NICHT angefasst. Sie bleiben dunkel, wie sie gebaut
-- sind -- Platz für Jaeger und Ronin. Ein halbvolles Zifferblatt liest sich als
-- Versprechen; sieben Indizes künstlich zu verdunkeln wäre nur Arbeit ohne Wirkung.
--
-- ===== Warum clientseitig =====
-- ALLE drei Zustände sind pro Spieler verschieden -- sie hängen daran, was DIESER Spieler
-- gebrochen hat, und das ist keine Eigenschaft der Welt. Ein Server-Skript müsste allen
-- dasselbe zeigen und damit das Falsche. Änderungen an Workspace-Teilen bleiben auf dem
-- Client ohnehin lokal -- genau das, was hier gebraucht wird.
--
-- Ein Index sperrt NICHTS. Jeder darf jederzeit in jede Stadt; das Zifferblatt empfiehlt,
-- es verbietet nicht.

local Players = game:GetService("Players")
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
-- Zwei Aussagen, zwei Farben -- und sie waren einmal dieselbe. TROPHY_COLOR und die frühere
-- ALERT_LOW_COLOR standen beide auf Gold (255, 210, 80): "das hast du geschafft" und "dort
-- ist etwas los" sahen identisch aus. Seit der Puls das nächste Ziel trägt, ist die Trennung
-- keine Kosmetik mehr, sondern der Unterschied zwischen erledigt und offen.
--
-- Gold bleibt die Trophäe -- diese Bedeutung ist am Blatt abgenommen und bleibt. Das Ziel
-- bekommt das tiefe Rot, das im Spiel schon "hier wird es ernst" heisst (City-Broken-Banner,
-- vormals Alarmstufe 5).
local TROPHY_COLOR = Color3.fromRGB(255, 210, 80) -- gebrochen, ruhig
local TARGET_COLOR = Color3.fromRGB(200, 40, 30) -- dein nächstes Ziel, pulsierend

-- Ein gleichmässiger, ruhiger Takt. Der Puls hing früher an der Alarmstufe und wurde mit ihr
-- schneller; ein Ziel hat keine Stufe. Es soll rufen, nicht drängen -- ein hektischer Index
-- an einer Wand, vor der man in Ruhe plant, wäre ein Fehlalarm.
local TARGET_PULSE_HZ = 0.7
local PULSE_DEPTH = 0.45 -- wie weit die Helligkeit dabei einbricht

-- Der Puls läuft über eine eigene Schleife. HÖCHSTENS sechsmal je Sekunde -- Amancio hat
-- das am 25.09.2026 als Obergrenze gesetzt.
--
-- Das reicht auch aus: der Puls ist eine langsame Helligkeitswelle zwischen 0.5 und 2 Hz.
-- Selbst die schnellste davon bekommt bei sechs Schritten je Sekunde noch anderthalb
-- Stützstellen je Halbwelle -- mehr unterscheidet an einem glimmenden Index niemand.
local PULSE_UPDATE_INTERVAL = 1 / 6

-- ===== Zifferblatt finden =====
-- Der verabredete Pfad zuerst, danach eine Suche nach dem Namen. Der Modellname trug
-- einmal einen Tippfehler ("Trencborn" ohne h) und ist seit dem 20.09.2026 berichtigt;
-- genau diesen Fall hat der Notfallweg aufgefangen und gemeldet. Er bleibt stehen: ein
-- weiteres Umbenennen kostet dann wieder nur eine Zeile in der Ausgabe, keinen Ausfall.
local EXPECTED_PATH = { "Sanctuary", "Trenchborn_Sanctuary_V4", "Dial" }
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
		-- Nur schreiben, was sich wirklich ändert. Das Material war der teuerste Posten der
		-- Pulsschleife und zugleich der überflüssigste: nach dem ersten Schritt steht es auf
		-- Neon und bleibt es: trotzdem wurde es je Teil und je Schritt neu zugewiesen. Eine
		-- Zuweisung an eine Roblox-Eigenschaft ist kein blosses Setzen -- sie geht durch die
		-- Änderungsverfolgung der Engine, auch wenn der Wert derselbe ist.
		if part.Color ~= color then
			part.Color = color
		end
		if part.Material ~= Enum.Material.Neon then
			part.Material = Enum.Material.Neon
		end
	end
end

-- ===== Zustand je Stadt =====
-- Die Alarmstufe wird hier nicht mehr gelesen (siehe refreshAll): das Blatt erzaehlt den
-- Fortschritt DIESES Spielers, und der steht allein in seiner Statistik.
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
-- Dass ein Index beim ersten Blick fehlt, heisst nicht, dass er falsch gebaut ist: der
-- Client bekommt die Welt nach und nach, und bei eingeschaltetem Streaming liefert Roblox
-- ein Modell zuerst als leere Hülle aus. Genau das war am 20.09.2026 der Fall -- im
-- Explorer lagen alle zwölf Indizes, das Skript sah null Kinder. Deshalb wird hier nicht
-- einmal nachgesehen, sondern mit Frist gewartet.
local INDEX_TIMEOUT = 15

local entries = {} -- [n] = { object, parts, original, city }

-- Gibt nil zurück, wenn der Index übernommen wurde, sonst den Text der Beanstandung.
local function registerIndex(indexNumber)
	local indexName = string.format("%s%02d", INDEX_PREFIX, indexNumber)
	local indexObject = dial:FindFirstChild(indexName)
	if not indexObject then
		return indexName
	end

	local parts = collectParts(indexObject)
	if #parts == 0 then
		return indexName .. " (kein BasePart darin)"
	end

	entries[indexNumber] = {
		object = indexObject,
		parts = parts,
		original = rememberOriginal(parts),
		city = CITY_BY_INDEX[indexNumber],
	}
	return nil
end

-- Versucht alle noch offenen Indizes und liefert die Beanstandungen samt ihrer Nummern,
-- aufsteigend sortiert -- damit Ausgabe und Wartereihenfolge zwischen zwei Durchläufen
-- gleich bleiben. Über pairs wäre beides zufällig.
local function collectMissing()
	local numbers = {}
	for indexNumber in pairs(CITY_BY_INDEX) do
		table.insert(numbers, indexNumber)
	end
	table.sort(numbers)

	local problems, openNumbers = {}, {}
	for _, indexNumber in ipairs(numbers) do
		if not entries[indexNumber] then
			local problem = registerIndex(indexNumber)
			if problem then
				table.insert(problems, problem)
				table.insert(openNumbers, indexNumber)
			end
		end
	end
	return problems, openNumbers
end

local startedWaiting = os.clock()
local missing, missingNumbers = collectMissing()

if #missing > 0 then
	-- Eine gemeinsame Frist für alle, nicht je Index eine eigene: fehlen alle fünf, wartet
	-- das Skript zusammen INDEX_TIMEOUT und nicht das Fünffache davon.
	local deadline = startedWaiting + INDEX_TIMEOUT
	for _, indexNumber in ipairs(missingNumbers) do
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			break
		end
		dial:WaitForChild(string.format("%s%02d", INDEX_PREFIX, indexNumber), remaining)
	end
	missing = collectMissing()
end

if #missing > 0 then
	warn(string.format(
		"[Kaiju Debug] Zifferblatt: diese Indizes fehlen oder sind leer, auch nach %.1f s Warten -- %s",
		os.clock() - startedWaiting,
		table.concat(missing, ", ")
	))

	-- Ohne diesen Zusatz sagt die Meldung oben nur, was NICHT da ist. Dann bleibt offen,
	-- ob die Indizes anders heissen oder eine Ebene tiefer liegen -- und beides lässt sich
	-- nur in Studio nachsehen. Also gleich mitgeben, was tatsächlich unter Dial liegt.
	local actual = {}
	for _, child in ipairs(dial:GetChildren()) do
		table.insert(actual, string.format("%s (%s)", child.Name, child.ClassName))
		if #actual >= 20 then
			table.insert(actual, "...")
			break
		end
	end
	if #actual > 0 then
		warn("[Kaiju Debug] Zifferblatt: unter " .. dial:GetFullName() .. " liegt stattdessen -- "
			.. table.concat(actual, ", "))
	else
		warn("[Kaiju Debug] Zifferblatt: " .. dial:GetFullName() .. " hat gar keine Kinder.")
	end

	-- Streaming unterscheidet die beiden Fälle, die sonst gleich aussehen: ist es aus, ist
	-- am Modell etwas anders als erwartet. Ist es an, bekommt dieser Client die Teile erst,
	-- wenn er nah genug ist -- dann liegt es nicht am Bau, und Warten allein reicht nicht.
	warn(string.format(
		"[Kaiju Debug] Zifferblatt: Workspace.StreamingEnabled = %s, Dial.ModelStreamingMode = %s",
		tostring(Workspace.StreamingEnabled),
		dial:IsA("Model") and tostring(dial.ModelStreamingMode) or "(Dial ist kein Model)"
	))
end

-- ===== Zustände setzen =====
-- pulsing enthält die Indizes, die gerade blinken.
local pulsing = {}

-- ===== Der Puls hängt sich nur ein, wenn er etwas zu tun hat =====
-- Hier stand einmal, ohne Alarm koste dieses Skript nichts. Das stimmte nicht: die
-- Heartbeat-Verbindung wurde beim Start angelegt und lief danach dauerhaft rund sechzig
-- Mal je Sekunde -- sie sprang nur sofort wieder heraus. Ein Rücksprung je Einzelbild ist
-- wenig, aber er ist nicht nichts, und im Sanctuary steht er die ganze Zeit an.
--
-- Jetzt wird die Verbindung erst hergestellt, wenn der erste Index pulst, und wieder
-- getrennt, sobald keiner mehr pulst. Ohne Alarm läuft wirklich nichts.
local pulseConnection
local accumulator = 0

local function pulseSchritt(deltaTime)
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
end

-- Nach jeder Zustandsänderung aufrufen: sie entscheidet, ob die Schleife laufen muss.
local function pulsPruefen()
	local aktiv = next(pulsing) ~= nil
	if aktiv and not pulseConnection then
		accumulator = PULSE_UPDATE_INTERVAL -- der erste Schritt soll sofort kommen
		pulseConnection = RunService.Heartbeat:Connect(pulseSchritt)
	elseif not aktiv and pulseConnection then
		pulseConnection:Disconnect()
		pulseConnection = nil
	end
end

-- ===== Welche Stadt als naechste dran ist =====
-- Die erste, die dieser Spieler noch nicht gebrochen hat. Die Reihenfolge steckt in den
-- Indexnummern selbst: 2, 4, 6, 8, 10 laufen mit CityAlertConfig.CityOrder von Village bis
-- MegaCity. Deshalb wird aufsteigend gesucht -- wer CITY_BY_INDEX umstellt, stellt damit
-- auch die Kampagnenreihenfolge um und muss das wissen.
--
-- Hat er alles gebrochen, kommt nil zurueck: dann pulst nichts mehr, und das Blatt steht
-- vollstaendig in Gold da. Das ist der richtige Endzustand und kein Fehlerfall.
local function naechstesZiel()
	local numbers = {}
	for indexNumber in pairs(entries) do
		table.insert(numbers, indexNumber)
	end
	table.sort(numbers)

	for _, indexNumber in ipairs(numbers) do
		if not everBroken(entries[indexNumber].city) then
			return indexNumber
		end
	end
	return nil
end

-- ===== Ein Index, drei Zustaende =====
-- Der Puls hat eine neue Bedeutung. Er zeigte bis zum 27.09.2026 die Alarmstufe der Stadt,
-- also den Zustand der WELT -- und war damit auf diesem Blatt fast nie zu gebrauchen: das
-- Zifferblatt haengt im Sanctuary, und wer davorsteht, ist per Definition in keiner Stadt.
-- Was dort pulste, war deshalb meist die Lage eines fremden Spielers.
--
-- Jetzt zeigt er, wohin es fuer DICH weitergeht. Damit gehoert jede Bewegung auf dem Blatt
-- dem Betrachter, und die Frage "wo muss ich hin" ist ohne Rechnen beantwortet:
--
--   pulsierend       dein naechstes Ziel -- genau EIN Index traegt das
--   ruhig leuchtend  gebrochen, abgehakt
--   dunkel           noch nicht dran
--
-- Die Alarmstufe selbst ist damit vom Blatt verschwunden. Sie steht im HUD, sobald man in
-- einer Stadt ist -- dort, wo sie den Spieler wirklich betrifft.
local function refreshAll()
	local zielIndex = naechstesZiel()

	for indexNumber, entry in pairs(entries) do
		if indexNumber == zielIndex then
			pulsing[indexNumber] = { base = TARGET_COLOR, hz = TARGET_PULSE_HZ }
		else
			pulsing[indexNumber] = nil
			if everBroken(entry.city) then
				applyGlow(entry, TROPHY_COLOR)
			else
				applyDark(entry)
			end
		end
	end

	pulsPruefen()

	-- ===== Die Ausgabe muss die Faelle auseinanderhalten =====
	-- Hier stand nur "naechstes Ziel ist X", und bei nil "alle Staedte gebrochen". Das war
	-- falsch, sobald GAR KEIN Index gefunden wurde: naechstesZiel liefert dann ebenfalls nil,
	-- und die Zeile behauptete einen Endzustand, wo in Wahrheit nichts vorlag. Genau in
	-- diesen Fall lief die Fehlersuche am 27.09.2026.
	--
	-- Deshalb steht jetzt der ganze Zustand da: wie viele Indizes ueberhaupt getragen werden,
	-- welche Stadt als gebrochen gilt, und was daraus folgt. Eine Zeile, die drei Fragen
	-- beantwortet, statt einer, die eine falsch beantwortet.
	local anzahl, stand = 0, {}
	for _, indexNumber in ipairs((function()
		local list = {}
		for n in pairs(entries) do
			table.insert(list, n)
		end
		table.sort(list)
		return list
	end)()) do
		anzahl += 1
		local city = entries[indexNumber].city
		local zeichen = "dunkel"
		if indexNumber == zielIndex then
			zeichen = "ZIEL (pulst)"
		elseif everBroken(city) then
			zeichen = "gebrochen (leuchtet)"
		end
		table.insert(stand, string.format("%s=%s", city, zeichen))
	end

	if anzahl == 0 then
		warn("[Kaiju Debug] Zifferblatt: kein einziger Index getragen -- es kann nichts leuchten. "
			.. "Siehe die Meldungen oben, welche Indizes fehlen.")
		return
	end

	print(string.format("[Kaiju Debug] Zifferblatt (%d Indizes): %s", anzahl, table.concat(stand, ", ")))
	if not zielIndex then
		print("[Kaiju Debug] Zifferblatt: kein Ziel mehr -- alle getragenen Staedte gelten als gebrochen.")
	end
end

-- ===== Auf Aenderungen hoeren =====
-- Eine gebrochene Stadt aendert ZWEI Indizes: der alte hoert auf zu pulsen, der naechste
-- beginnt. Deshalb refreshAll und nicht ein einzelner Index -- das Ziel ist eine Aussage
-- ueber das ganze Blatt, nicht ueber einen Strich.
for _, cityName in pairs(CITY_BY_INDEX) do
	player:GetAttributeChangedSignal("Stat_CityBroken." .. cityName):Connect(refreshAll)
end

refreshAll()

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
