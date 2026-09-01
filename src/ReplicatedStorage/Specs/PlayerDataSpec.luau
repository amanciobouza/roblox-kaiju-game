-- ModuleScript: PlayerDataSpec
--
-- Spezifikation der Datenhaltung: was beim Speichern und Laden von Spielerfortschritt
-- gelten soll. Entstanden aus einer Fehlersuche, bei der vier voneinander unabhängige
-- Fehler übereinander lagen und der Talentfortschritt still verschwand -- ohne eine
-- einzige Fehlermeldung.
--
-- Die weichen Aussagen hier sind keine Theorie. Jede beschreibt einen Fehler, der
-- tatsächlich passiert ist.
--
-- Importiert nichts, alles kommt über den ctx (siehe SpecRunner).

return {
	System = "PlayerData",

	Rules = {
		--------------------------------------------------------------------------
		-- Prüfbar zur Laufzeit
		--------------------------------------------------------------------------
		{
			id = "playerdata.savedata-api-paired",
			intent = "Jedes Untersystem, das eigenen Fortschritt in den Speicherstand legt, "
				.. "meldet sich mit einem PAAR an: _G.Get<X>SaveData zum Sammeln und "
				.. "_G.Load<X>SaveData zum Wiederherstellen. Fehlt eine Hälfte, wird "
				.. "entweder nichts gespeichert oder nichts geladen -- beides fällt im "
				.. "Spiel erst auf, wenn der Fortschritt schon weg ist.",
			needsRuntime = true,
			check = function(ctx)
				local violations = {}
				for _, subsystem in ipairs({ "Talent", "Achievement", "Stats" }) do
					local getter = "Get" .. subsystem .. "SaveData"
					local loader = "Load" .. subsystem .. "SaveData"
					local hasGetter = ctx.runtime.HasGlobal(getter)
					local hasLoader = ctx.runtime.HasGlobal(loader)
					if hasGetter and not hasLoader then
						table.insert(violations, subsystem .. ": _G." .. getter .. " vorhanden, _G." .. loader .. " fehlt -- wird gespeichert, aber nie geladen")
					elseif hasLoader and not hasGetter then
						table.insert(violations, subsystem .. ": _G." .. loader .. " vorhanden, _G." .. getter .. " fehlt -- wird geladen, aber nie gespeichert")
					elseif not hasGetter and not hasLoader then
						table.insert(violations, subsystem .. ": weder _G." .. getter .. " noch _G." .. loader .. " vorhanden")
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Weiche Aussagen -- beim Abgleich mitzulesen
		--------------------------------------------------------------------------
		{
			id = "playerdata.no-cleanup-before-save",
			intent = "WEICH: Kein Dienst darf seinen spielerbezogenen Zustand in "
				.. "PlayerRemoving SOFORT leeren. PlayerSetup speichert im selben "
				.. "Ereignis, und Roblox ruft die Handler in der Reihenfolge ihrer "
				.. "Verbindung auf -- Scripts in ServerScriptService starten aber in "
				.. "unbestimmter Reihenfolge. Läuft das Aufräumen zuerst, speichert "
				.. "PlayerSetup einen leeren Zustand.\n"
				.. "Genau so ging der Talentfortschritt verloren: mal ja, mal nein, je "
				.. "nach Startreihenfolge zweier Scripts. Aufräumen gehört in ein "
				.. "task.defer (siehe TalentTreeService und StatsService).",
		},

		{
			id = "playerdata.one-write-per-save",
			intent = "WEICH: Ein Speichervorgang ist EIN Schreibvorgang. Zwei Schreibzugriffe "
				.. "hintereinander auf denselben Schlüssel sind gefährlich, weil ein "
				.. "Lesevorgang unmittelbar nach einem Schreibvorgang häufig noch den alten "
				.. "Wert liefert -- der zweite Zugriff schreibt dann den Stand von VOR dem "
				.. "Speichern zurück und macht es rückgängig.\n"
				.. "Genau daran ging Fortschritt verloren, als das Freigeben der "
				.. "Sitzungssperre ein eigener Schreibvorgang nach dem Speichern war. "
				.. "Beide meldeten Erfolg.",
		},

		{
			id = "playerdata.save-outcome-must-be-visible",
			intent = "WEICH: Jeder Speichervorgang meldet seinen AUSGANG, nicht nur seinen "
				.. "Beginn. Ohne Abschlussmeldung lässt sich 'gespeichert' nicht von "
				.. "'unterwegs abgebrochen' unterscheiden -- dieselbe Regel wie beim "
				.. "Spec-Prüfer.\n"
				.. "Das gilt auch für das PRÄFIX: alle Meldungen eines Ablaufs gehören unter "
				.. "dasselbe, sonst verschluckt ein Filter im Ausgabefenster genau die "
				.. "Zeilen, die den Fehler zeigen.",
		},

		{
			id = "playerdata.shutdown-must-wait",
			intent = "WEICH: game:BindToClose hat genau einen Zweck -- den Server offen zu "
				.. "halten, bis die laufenden Schreibvorgänge durch sind. Es darf deshalb "
				.. "NICHT sofort zurückkehren, auch dann nicht, wenn es selbst nichts mehr "
				.. "zu speichern hat. Kehrt es früh zurück, beendet Roblox den Prozess "
				.. "mitten im DataStore-Aufruf, und der Spielstand kommt nie an.",
		},

		{
			id = "playerdata.research-counts-online-time",
			intent = "WEICH: Laufende Talentforschung schreitet NUR voran, solange der Spieler "
				.. "online ist. Gespeichert wird die investierte Zeit, nicht der "
				.. "Fertigstellungszeitpunkt -- der Spieler macht dort weiter, wo er "
				.. "aufgehört hat. Eine mehrstündige Forschung bedeutet damit mehrere "
				.. "Stunden SPIELZEIT; das ist die Absicht, aber es macht lange Forschungen "
				.. "spürbar teurer als eine Wanduhr-Rechnung.",
		},

		{
			id = "playerdata.migration-never-forces-retroactively",
			intent = "WEICH: Eine Migration darf Bestandsspielern nichts rückwirkend "
				.. "aufzwingen. Wer den Prolog gespielt hat, gilt nach der Migration als "
				.. "Absolvent der AKTUELLEN Fassung; wer eine Alarmstufe oder Statistik nie "
				.. "hatte, startet bei null statt bei einer geschätzten Zahl. Im Zweifel "
				.. "zugunsten des Spielers -- der Speicherstand ist das Einzige, was er "
				.. "nicht wiederherstellen kann.",
		},

		{
			id = "playerdata.newer-save-is-untouchable",
			intent = "WEICH: Trägt ein Speicherstand eine höhere Schema-Version als der "
				.. "laufende Server kennt, wird er weder migriert noch überschrieben. Die "
				.. "Sitzung geht dann verloren, der Spielstand nicht. Dasselbe gilt für "
				.. "eine fremde Sitzungssperre: lieber nicht speichern als eine gültige "
				.. "andere Sitzung zerschreiben.",
		},
	},
}
