-- ModuleScript: SpecRunner
--
-- Führt Spec-Regeln aus und fasst das Ergebnis zusammen. Wird von ZWEI Runnern benutzt:
--   * tools/spec-check.luau        -- ausserhalb von Roblox, kennt nur die Configs
--   * SpecCheckService.server.luau -- in Studio, kennt zusätzlich Workspace und Laufzeit
--
-- Dieses Modul selbst fasst NICHTS an, was Roblox-spezifisch ist -- kein game:GetService,
-- kein require auf andere Module. Alles kommt über die Argumente herein. Nur so läuft
-- dieselbe Datei in beiden Umgebungen identisch.

local SpecRunner = {}

-- Ein Verstoss gilt als BEKANNT, wenn sein Text mit einem der in der Regel hinterlegten
-- Einträge beginnt. Präfix statt exaktem Vergleich, weil der Verstosstext Details trägt
-- ("LargeCity: MaxAlertLevel=5, aber GuardianHP fehlt"), die sich beim Umformulieren
-- ändern -- der Schlüssel davor ("LargeCity") bleibt.
local function isKnown(rule, violationText)
	if not rule.knownViolations then
		return false
	end
	for _, known in ipairs(rule.knownViolations) do
		if string.sub(violationText, 1, #known) == known then
			return true
		end
	end
	return false
end

-- specs: Liste von Spec-Modulen (je { System = "...", Rules = { ... } })
-- ctx:   { config = {...}, workspace = ... oder nil, runtime = ... oder nil }
--
-- Rückgabe:
--   {
--     checked = number,       -- Regeln mit check(), die tatsächlich gelaufen sind
--     soft = number,          -- Regeln ohne check() -- nur zur Begutachtung
--     skipped = number,       -- übersprungen, weil ihre Voraussetzung fehlte
--     failed = number,        -- Regeln, deren check() selbst einen Fehler warf
--     new = { { rule=, system=, text= }, ... },
--     known = { { rule=, system=, text= }, ... },
--     errors = { { rule=, system=, text= }, ... },
--   }
function SpecRunner.Run(specs, ctx)
	local result = {
		checked = 0,
		soft = 0,
		skipped = 0,
		failed = 0,
		new = {},
		known = {},
		errors = {},
	}

	for _, spec in ipairs(specs) do
		local system = spec.System or "?"

		for _, rule in ipairs(spec.Rules or {}) do
			if not rule.check then
				-- Weiche Aussage: steht bewusst in derselben Liste (siehe Q9), wird aber
				-- von keiner Maschine geprüft, sondern beim Abgleich mitgelesen.
				result.soft += 1
			elseif rule.needsRuntime and not ctx.runtime then
				result.skipped += 1
			elseif rule.needsWorkspace and not ctx.workspace then
				result.skipped += 1
			else
				-- pcall, damit eine kaputte Regel den ganzen Lauf nicht mitreisst -- sonst
				-- verliert man alle übrigen Ergebnisse wegen eines Tippfehlers.
				local ok, violations = pcall(rule.check, ctx)

				if not ok then
					result.failed += 1
					table.insert(result.errors, {
						rule = rule.id or "?",
						system = system,
						text = tostring(violations),
					})
				else
					result.checked += 1
					for _, text in ipairs(violations or {}) do
						local entry = { rule = rule.id or "?", system = system, text = text }
						if isKnown(rule, text) then
							table.insert(result.known, entry)
						else
							table.insert(result.new, entry)
						end
					end
				end
			end
		end
	end

	return result
end

-- Baut die Ausgabezeilen. Bewusst hier und nicht im jeweiligen Runner, damit die Ausgabe
-- in Studio und ausserhalb wortgleich ist -- man soll die zwei Läufe vergleichen können.
--
-- Die Abschlusszeile kommt IMMER, auch bei null Verstössen: ohne sie lässt sich "sauber"
-- nicht von "der Prüfer lief gar nicht" unterscheiden.
function SpecRunner.Format(result, prefix)
	prefix = prefix or "[Kaiju Spec]"
	local lines = {}

	for _, entry in ipairs(result.errors) do
		table.insert(lines, prefix .. " REGEL DEFEKT  " .. entry.system .. "/" .. entry.rule .. ": " .. entry.text)
	end
	for _, entry in ipairs(result.new) do
		table.insert(lines, prefix .. " NEU  " .. entry.system .. "/" .. entry.rule .. ": " .. entry.text)
	end
	for _, entry in ipairs(result.known) do
		table.insert(lines, prefix .. " bekannt  " .. entry.system .. "/" .. entry.rule .. ": " .. entry.text)
	end

	table.insert(
		lines,
		string.format(
			"%s %d Regeln geprüft, %d neue Verstösse, %d bekannte Abweichungen, %d zur Begutachtung, %d übersprungen, %d Regeln defekt",
			prefix,
			result.checked,
			#result.new,
			#result.known,
			result.soft,
			result.skipped,
			result.failed
		)
	)

	return lines
end

return SpecRunner
