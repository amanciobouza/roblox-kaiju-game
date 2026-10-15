-- ModuleScript: CinematicFormat
--
-- Das Format, in dem cinematische Sequenzen geschrieben werden -- und die Pruefung, dass
-- eine geschriebene Sequenz es einhaelt.
--
-- ===== Warum es dieses Modul gibt =====
-- Sequenzen sollen von Hand editierbar sein, von Amancio und von der KI. Genau deshalb
-- braucht es eine Stelle, die sagt, was gueltig ist -- sonst faellt ein Tippfehler erst im
-- Spiel auf, mitten in einer Szene, die einmal je Spieler laeuft.
--
-- Validate() wird an ZWEI Stellen gerufen: vom Spec-Pruefer (kopflos, beim Stop-Hook) und
-- vom Dienst beim Start einer Sequenz. Dieselbe Pruefung, ein Regelwerk.
--
-- ===== Englische Schluessel, deutsche Kommentare =====
-- Entschieden am 11.10.2026. Begruendung: StoryBeat und ShowdownConfig sind englisch
-- (steps, type, duration, source, style), und derselbe Laeufer liest beide Formate.
-- Deutsche Schluessel hiessen zwei Konventionen in einer Datei.
--
-- Importiert nichts. Reine Daten und reine Pruefung -- so laeuft es in Studio und im
-- kopflosen Pruefer gleich.

local CinematicFormat = {}

CinematicFormat.VERSION = "CinematicFormat_v01"

-- ===== Der Aufbau einer Sequenz =====
--
--   {
--     name = "ChapterOneFinale",        -- eindeutig; der Dienst findet sie darueber
--     trigger = { kind = "serverCall" }, -- wann sie laeuft (siehe TRIGGER_KINDS)
--     mode = "cutscene",                 -- "cutscene" sperrt die Eingabe, "overlay" nicht
--     interrupt = "immediate",           -- oder "finish" (siehe INTERRUPT_MODES)
--     emits = "ChapterOneFinished",      -- Ereignis am Ende; optional
--     steps = { ... },
--   }
--
-- ===== Ein Schritt =====
-- { type = "<einer aus STEP_TYPES>", ... je Typ eigene Schluessel }
-- Zusaetzlich bei JEDEM Schritt erlaubt:
--   parallel = true   -- laeuft mit, statt die Sequenz aufzuhalten (wie bei StoryBeat)

-- ===== Die Auslöser =====
-- Vier, bewusst nicht mehr. "naeheTeil" ist ausgelassen: dafuer gibt es ProximityPrompts,
-- und die haben in diesem Projekt ihre eigene Reichweiten-Geschichte.
CinematicFormat.TRIGGER_KINDS = {
	-- Ein Dienst ruft sie ausdruecklich auf. Der einzige Weg, den es vor diesem Format gab.
	serverCall = { fields = {} },
	-- Der Spieler betritt eine Zone (Attribut CurrentZone).
	zoneEntered = { fields = { zone = "string" } },
	-- Eine Stadt erreicht eine Alarmstufe.
	alertLevel = { fields = { city = "string", level = "number" } },
	-- Eine andere Sequenz ist fertig -- die Verkettung aus Q8.
	sequenceFinished = { fields = { event = "string" } },
}

-- ===== Die Schritt-Typen =====
-- Die ersten neun sind die von StoryBeat; sie werden dort ausgefuehrt und hier nur als
-- gueltig anerkannt. Die vier darunter sind neu.
CinematicFormat.STEP_TYPES = {
	fadeIn = { storyBeat = true },
	fadeOut = { storyBeat = true },
	wait = { storyBeat = true },
	text = { storyBeat = true },
	hint = { storyBeat = true },
	chapterCard = { storyBeat = true },
	presenterCard = { storyBeat = true },
	sound = { storyBeat = true },
	revealBackground = { storyBeat = true },

	-- Eine Kamerafahrt. Pflicht: duration und focus, dazu to ODER waypoints.
	camera = { required = { "duration", "focus" }, eitherOr = { "to", "waypoints" } },
	-- Loest etwas im Spiel aus -- NUR registrierte Namen (siehe Weissliste im Dienst).
	action = { required = { "name" } },
	-- Feuert ein benanntes Ereignis mitten in der Sequenz, nicht nur am Ende.
	event = { required = { "name" } },
	-- Haelt an, bis ein benanntes Ereignis kommt. timeout ist PFLICHT: eine Sequenz, die
	-- ewig wartet, haengt das Spiel -- und beim Finale waere das unwiederbringlich.
	waitFor = { required = { "name", "timeout" } },
}

CinematicFormat.MODES = { cutscene = true, overlay = true }
CinematicFormat.INTERRUPT_MODES = { immediate = true, finish = true }

-- ===== Verweise auf Orte in der Welt =====
-- Ein String mit Schema, entschieden am 11.10.2026. Ein Schluessel, ein Format -- und der
-- Spec-Pruefer kann in Studio nachsehen, ob jedes "part:"-Ziel wirklich existiert.
--
--   part:<Name>      ein Teil oder Modell in der Workspace, nach Namen gesucht
--   player:<Teil>    ein Teil der Spielerfigur, z.B. player:Head
--   tag:<Tag>        das erste Objekt mit diesem CollectionService-Tag
--   context:<Name>   etwas, das der Dienst beim Start mitgegeben hat (z.B. der Guardian)
CinematicFormat.REFERENCE_SCHEMES = { part = true, player = true, tag = true, context = true }

function CinematicFormat.ParseReference(verweis)
	if type(verweis) ~= "string" then
		return nil, "kein String"
	end
	local schema, rest = string.match(verweis, "^([%a]+):(.+)$")
	if not schema then
		return nil, "kein Schema -- erwartet 'part:Name', 'player:Head', 'tag:Guardian' oder 'context:Name'"
	end
	if not CinematicFormat.REFERENCE_SCHEMES[schema] then
		return nil, "unbekanntes Schema '" .. schema .. "'"
	end
	return { scheme = schema, value = rest }
end

-- ===== Die Prüfung =====
-- Gibt eine LISTE von Verstoessen zurueck, keinen Fehler -- so kann der Spec-Pruefer alle
-- Sequenzen durchgehen und am Ende alles auf einmal melden, statt beim ersten abzubrechen.
local function pruefeVerweis(verstoesse, wo, verweis)
	if verweis == nil then
		return
	end
	local _, fehler = CinematicFormat.ParseReference(verweis)
	if fehler then
		table.insert(verstoesse, string.format("%s: %s (%s)", wo, fehler, tostring(verweis)))
	end
end

local function pruefeSchritt(verstoesse, name, index, schritt)
	local wo = string.format("%s, Schritt %d", name, index)
	if type(schritt) ~= "table" then
		table.insert(verstoesse, wo .. ": ist kein Tisch")
		return
	end

	local regel = CinematicFormat.STEP_TYPES[schritt.type]
	if not regel then
		table.insert(verstoesse, wo .. ": unbekannter Typ " .. tostring(schritt.type))
		return
	end

	for _, feld in ipairs(regel.required or {}) do
		if schritt[feld] == nil then
			table.insert(verstoesse, string.format("%s (%s): %s fehlt", wo, schritt.type, feld))
		end
	end

	-- to ODER waypoints -- eines von beiden, nicht beides und nicht keines. Beides waere
	-- nicht aufloesbar: welcher Endpunkt gilt dann?
	if regel.eitherOr then
		local gesetzt = 0
		for _, feld in ipairs(regel.eitherOr) do
			if schritt[feld] ~= nil then
				gesetzt += 1
			end
		end
		if gesetzt ~= 1 then
			table.insert(verstoesse, string.format("%s (%s): genau eines von %s muss gesetzt sein, es sind %d",
				wo, schritt.type, table.concat(regel.eitherOr, "/"), gesetzt))
		end
	end

	if schritt.type == "camera" then
		pruefeVerweis(verstoesse, wo .. " (focus)", schritt.focus)
		pruefeVerweis(verstoesse, wo .. " (to)", schritt.to)
		pruefeVerweis(verstoesse, wo .. " (focusBlend)", schritt.focusBlend)
		if type(schritt.waypoints) == "table" then
			for i, verweis in ipairs(schritt.waypoints) do
				pruefeVerweis(verstoesse, string.format("%s (waypoint %d)", wo, i), verweis)
			end
		end
		if type(schritt.duration) == "number" and schritt.duration <= 0 then
			table.insert(verstoesse, wo .. ": duration muss groesser als 0 sein")
		end
	end

	if schritt.type == "waitFor" and type(schritt.timeout) == "number" and schritt.timeout <= 0 then
		table.insert(verstoesse, wo .. ": timeout muss groesser als 0 sein -- sonst wartet die Sequenz ewig")
	end
end

function CinematicFormat.Validate(sequenz)
	local verstoesse = {}
	if type(sequenz) ~= "table" then
		return { "Sequenz ist kein Tisch" }
	end

	local name = tostring(sequenz.name or "<ohne Namen>")
	if type(sequenz.name) ~= "string" or sequenz.name == "" then
		table.insert(verstoesse, name .. ": name fehlt oder ist kein String")
	end

	if sequenz.mode ~= nil and not CinematicFormat.MODES[sequenz.mode] then
		table.insert(verstoesse, name .. ": unbekannter mode " .. tostring(sequenz.mode))
	end
	if sequenz.interrupt ~= nil and not CinematicFormat.INTERRUPT_MODES[sequenz.interrupt] then
		table.insert(verstoesse, name .. ": unbekanntes interrupt " .. tostring(sequenz.interrupt))
	end

	local trigger = sequenz.trigger
	if type(trigger) ~= "table" then
		table.insert(verstoesse, name .. ": trigger fehlt")
	else
		local regel = CinematicFormat.TRIGGER_KINDS[trigger.kind]
		if not regel then
			table.insert(verstoesse, name .. ": unbekannter trigger.kind " .. tostring(trigger.kind))
		else
			for feld, art in pairs(regel.fields) do
				if type(trigger[feld]) ~= art then
					table.insert(verstoesse, string.format("%s: trigger.%s fehlt oder ist kein %s",
						name, feld, art))
				end
			end
		end
	end

	if type(sequenz.steps) ~= "table" or #sequenz.steps == 0 then
		table.insert(verstoesse, name .. ": steps fehlt oder ist leer")
	else
		for index, schritt in ipairs(sequenz.steps) do
			pruefeSchritt(verstoesse, name, index, schritt)
		end
	end

	return verstoesse
end

-- Welche Ereignisse eine Sequenz FEUERT (emits plus alle "event"-Schritte) und auf welche
-- sie HOERT (trigger.kind == "sequenceFinished" plus alle "waitFor"-Schritte).
--
-- Dafuer gibt es die Spec-Regel aus Q8: jedes gefeuerte Ereignis braucht mindestens einen
-- Hoerer. Ohne sie faellt ein umbenannter Hoerer nicht auf -- das Ereignis feuert ins Leere
-- und die Verkettung bricht still.
function CinematicFormat.EventsOf(sequenz)
	local feuert, hoert = {}, {}
	if type(sequenz) ~= "table" then
		return feuert, hoert
	end
	if type(sequenz.emits) == "string" then
		table.insert(feuert, sequenz.emits)
	end
	if type(sequenz.trigger) == "table" and sequenz.trigger.kind == "sequenceFinished"
		and type(sequenz.trigger.event) == "string" then
		table.insert(hoert, sequenz.trigger.event)
	end
	for _, schritt in ipairs(sequenz.steps or {}) do
		if type(schritt) == "table" and type(schritt.name) == "string" then
			if schritt.type == "event" then
				table.insert(feuert, schritt.name)
			elseif schritt.type == "waitFor" then
				table.insert(hoert, schritt.name)
			end
		end
	end
	return feuert, hoert
end

return CinematicFormat
