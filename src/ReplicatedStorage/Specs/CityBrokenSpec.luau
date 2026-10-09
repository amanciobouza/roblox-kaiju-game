-- ModuleScript: CityBrokenSpec
--
-- CITY BROKEN: warum der Spieler eine Stadt bricht, und was er dafuer bekommt.
--
-- ===== Warum diese Spec entstanden ist =====
-- Amancio am 06.10.2026, nach einem Durchlauf: "Fuehlt es sich gleich an, ob eine Stadt
-- gebrochen ist oder nicht. Es lohnt sich nicht, diese gebrochene Zeit zu nutzen."
--
-- Das war kein Balancing-Hinweis, sondern ein Befund ueber den Zweck. CITY BROKEN ist der
-- vierte Baustein des Alarm-Konzepts (siehe CLAUDE.md) und mechanisch fertig -- aber es
-- BEDEUTET dem Spieler nichts. Die Entscheidung vom 07.10.2026 gibt ihm eine Bedeutung,
-- und sie reicht ueber alle drei Kapitel.
--
-- Diese Spec haelt sie fest, weil genau das im Bestand mehrfach verlorengegangen ist: eine
-- Absicht war dokumentiert, der Code setzte sie nicht um, und niemand merkte es. Ein
-- Kommentar in einem Dienst haette den naechsten Umbau nicht ueberlebt.
--
-- ===== Was hier NOCH NICHT steht =====
-- Keine Zahl zur Fragment-Verteilung und keine Liste der Verstecke. Beides gehoert in eine
-- eigene Config, sobald das System gebaut wird -- hier steht, was gelten SOLL.
--
-- Importiert nichts, alles kommt über den ctx (siehe SpecRunner).

-- ===== Die vier Gegenmassnahmen =====
-- Die Reihenfolge ist die der Alarmstufen und damit auch die des Missionsziels. Sie steht
-- hier, damit die Anzeige sie nicht selbst erfinden muss -- und damit eine Stadt mit
-- niedrigerem MaxAlertLevel nur die Zeilen zeigt, die sie ueberhaupt hat.
local GEGENMASSNAHMEN = {
	{ stufe = 2, schluessel = "FireEngines", titel = "FIRE DEPT" },
	{ stufe = 3, schluessel = "Barricades", titel = "BARRICADES" },
	{ stufe = 4, schluessel = "Military", titel = "MILITARY" },
	{ stufe = 5, schluessel = "Guardian", titel = "GUARDIAN" },
}

-- ===== Was die Eltern dem Jungen mitgeben =====
-- Je Kapitel eine andere Art von Gabe, je Stadt ein Fragment. Die Reihenfolge der Staedte
-- ist die der Groessenstaffel.
--
-- Kapitel I steht fest, weil Kapitel I gebaut wird. Die beiden anderen sind als Absicht
-- festgehalten, nicht als Liste zum Abarbeiten -- sie werden sich beim Bauen praezisieren.
local GABEN = {
	Kaiju = {
		leitsatz = "Before you can become anything, you need the strength to grow.",
		art = "was das Junge zum Leben und Wachsen braucht",
		fragmente = {
			{ stadt = "Village", gabe = "Food" },
			{ stadt = "SmallTown", gabe = "Warmth" },
			{ stadt = "City", gabe = "Energy" },
			{ stadt = "LargeCity", gabe = "Shelter" },
			{ stadt = "MegaCity", gabe = "Strength" },
		},
	},
	Jaeger = {
		leitsatz = "Power gives you ability. Control teaches you how to use it.",
		art = "Werkzeuge, mit denen das Junge lernt, seine Kraefte einzusetzen",
		fragmente = {
			{ stadt = "Village", gabe = "Shoes -- learn to move" },
			{ stadt = "SmallTown", gabe = "Puzzle -- learn to think" },
			{ stadt = "City", gabe = "Tool -- learn to build" },
			{ stadt = "LargeCity", gabe = "Brush -- learn to create" },
			{ stadt = "MegaCity", gabe = "Watch -- learn patience" },
		},
	},
	Ronin = {
		leitsatz = "Show them what you believe in. Then let them choose.",
		art = "Beispiele, keine Gabe -- Werte werden vorgelebt, nicht uebergeben",
		fragmente = {
			{ stadt = "Village", gabe = "Courage" },
			{ stadt = "SmallTown", gabe = "Compassion" },
			{ stadt = "City", gabe = "Responsibility" },
			{ stadt = "LargeCity", gabe = "Curiosity" },
			{ stadt = "MegaCity", gabe = "Perseverance" },
		},
	},
}

return {
	System = "CityBroken",

	Gegenmassnahmen = GEGENMASSNAHMEN,
	Gaben = GABEN,

	Rules = {
		--------------------------------------------------------------------------
		-- Das Ziel muss als Ziel lesbar sein
		--------------------------------------------------------------------------
		{
			id = "citybroken.is-a-mission-not-a-statistic",
			intent = "WEICH: Die vier Gegenmassnahmen sind das ZIEL des Spielers in einer "
				.. "Stadt, nicht eine Statistik ueber Erledigtes.\n"
				.. "Amancio am 06.10.2026: 'Aktuell ist es nur eine kleine Infotafel, welche "
				.. "Gegenmassnahmen man bereits besiegt hat. Es wird fuer den Spieler nicht "
				.. "genau klar, dass genau das von ihm erwartet wird. Es sieht wie eine "
				.. "beilaeufige Statistik aus.'\n"
				.. "Der Unterschied liegt in der Aussage, nicht in der Groesse der Tafel. "
				.. "'Das hast du erledigt' ist eine Bilanz. 'Erst wenn du diese vier Linien "
				.. "brichst, hast du die Stadt besiegt' ist ein Auftrag.\n"
				.. "Daraus folgt fuer die Anzeige: beim ERSTEN Betreten einer Stadt steht das "
				.. "Ziel gross im Bild ('BREAK THE CITY -- defeat every defense'), darunter "
				.. "die vier Gegenmassnahmen dieser Stadt in der Reihenfolge ihrer "
				.. "Alarmstufen. Besiegte werden sichtbar DURCHGESTRICHEN, nicht nur "
				.. "abgehakt -- ein Haken liest sich als Buchhaltung, ein Strich als Sieg.\n"
				.. "Eine Stadt zeigt nur die Zeilen, die sie hat: Village kennt bis Stufe 3, "
				.. "also drei Zeilen, nicht vier mit zwei toten.",
		},

		{
			id = "citybroken.gates-the-next-city",
			intent = "WEICH: Die naechste Stadt ist gesperrt, solange die aktuelle nicht "
				.. "gebrochen ist -- und die Sperre ist SICHTBAR, nicht nur wirksam.\n"
				.. "Das ist der Unterschied zwischen einer Completionist-Aufgabe und "
				.. "Progression. Wer am Portal '🔒 BREAK THE CITY TO ADVANCE' liest, "
				.. "versteht in einer Sekunde, was das Spiel von ihm will -- jede Erklaerung "
				.. "im HUD kommt dagegen zu spaet.\n"
				.. "ZU PRUEFEN beim Bauen: das Zifferblatt im Sanctuary zeigt heute bereits "
				.. "je Stadt einen Index (SanctuaryDialClient). Die Sperre gehoert dorthin "
				.. "und ans Portal, nicht in eine neue Oberflaeche.",
		},

		{
			id = "citybroken.city-visibly-changes",
			intent = "WEICH: Nach dem Brechen veraendert sich die STADT, nicht nur der "
				.. "Spielstand. Sirenen verstummen, das Militaer zieht ab, die Musik "
				.. "wechselt.\n"
				.. "Die 75 Sekunden sind heute mechanisch eine Belohnungsphase, fuehlen sich "
				.. "aber wie normales Spiel ohne Gegenwehr an. Ein Sieg, den man nur am "
				.. "Zaehler erkennt, ist kein Sieg.\n"
				.. "Vorsicht bei der Umsetzung: die Belohnungen fliessen in dieser Phase "
				.. "bewusst WEITER (siehe CLAUDE.md, CITY BROKEN). Was sich aendert, ist die "
				.. "Gegenwehr und die Inszenierung -- nicht der Ertrag nach unten.",
		},

		--------------------------------------------------------------------------
		-- Der Grund: das Fragment
		--------------------------------------------------------------------------
		{
			id = "citybroken.reward-answers-why-not-just-how-much",
			intent = "WEICH: Der Hauptgrund, eine Stadt zu brechen, ist NICHT mehr Ertrag.\n"
				.. "Mehr XP und Geld beantworten nur 'warum soll ich weiterfarmen'. Die "
				.. "Frage, die CITY BROKEN beantworten muss, ist 'warum kaempfe ich "
				.. "ueberhaupt' -- und darauf antwortet die Geschichte, nicht eine Zahl.\n"
				.. "Ein Bonus auf XP und Geld ist trotzdem richtig, damit der Sieg sich auch "
				.. "mechanisch lohnt und der naechste Skin erreichbar wird. Er ist die "
				.. "Zugabe, nicht der Grund. Die Reihenfolge der Begruendung gehoert in "
				.. "dieser Richtung auch ins HUD: erst das Fragment, dann die Prozente.",
		},

		{
			id = "citybroken.fragment-is-found-not-farmed",
			intent = "WEICH: In jeder Stadt liegt EIN Fragment versteckt. Es ist erst "
				.. "auffindbar, wenn die Stadt gebrochen ist -- und es wird GESUCHT, nicht "
				.. "erarbeitet.\n"
				.. "Mechanik: waehrend die Stadt sich wehrt, ist das Versteck unsichtbar. "
				.. "Sobald sie bricht, senden drei bis fuenf Orte ein Signal; nur einer "
				.. "traegt das Fragment. Der Spieler muss waehlen -- das Huetchenspiel, das "
				.. "Amancio als Bild genannt hat.\n"
				.. "Der Sinn dieser Form: nach der Eskalation beginnt bewusst eine ANDERE "
				.. "Phase. Zerstoeren, besiegen, suchen, finden. Noch mehr Gebaeude "
				.. "umzulegen waere nur die vierte Wiederholung derselben Taetigkeit.\n"
				.. "Daraus folgt eine harte Bedingung: die Suche braucht Zeit. Reichen die "
				.. "75 Sekunden nicht, wird das Fenster verlaengert -- NICHT die Suche "
				.. "verkuerzt.",
		},

		{
			id = "citybroken.fragments-carry-the-trilogy",
			intent = "WEICH: Die Fragmente sind kein Sammelwerk, sondern das, was die Eltern "
				.. "dem Jungen mitgeben. Je Kapitel eine andere Art von Gabe (siehe Gaben "
				.. "oben).\n"
				.. "Kaiju gibt, was es zum Wachsen braucht: Nahrung, Waerme, Energie, "
				.. "Schutz, Kraft. Power ist hier NICHT Dominanz, sondern die Faehigkeit zu "
				.. "existieren und zu schuetzen -- das aendert rueckwirkend, was Kapitel I "
				.. "bedeutet. Der Kaiju zerstoert die Staedte nicht, weil er ein Monster "
				.. "ist. Er bringt etwas nach Hause.\n"
				.. "Jaeger gibt Werkzeuge zum Lernen und nimmt sie NICHT durch Zerstoerung -- "
				.. "er verdient sie durch Beherrschung. Das ist der mechanische Unterschied "
				.. "zwischen den Kapiteln, nicht bloss ein anderer Skin.\n"
				.. "Ronin sammelt KEINEN Purpose. Werte werden vorgelebt, nicht uebergeben: "
				.. "sie werden durch Entscheidungen sichtbar, und das Spiel zeigt die Folge, "
				.. "nicht '+1 Compassion'.",
		},

		{
			id = "citybroken.purpose-stays-empty",
			intent = "WEICH: Am Ende bleibt ein Platz leer, und er bleibt es.\n"
				.. "Nach drei Kapiteln stehen Kaiju, Jaeger und Ronin beim Jungen, um sie "
				.. "herum alles Gesammelte. Ein Sockel ist frei, darueber steht PURPOSE -- "
				.. "derselbe Sockel, den der Spieler das ganze Spiel ueber gesehen hat. Er "
				.. "kann ihn nicht fuellen. Keine Quest, kein Boss, kein Collectible.\n"
				.. "Geht er hin, bekommt er eine Antwort und keine Aufgabe: 'This one isn't "
				.. "ours to give.' Dann geht das Junge selbst los.\n"
				.. "WICHTIG fuer alle spaeteren Aenderungen: diesen Platz fuellbar zu machen "
				.. "-- auch gut gemeint, auch als Bonus -- nimmt der Trilogie ihre Aussage. "
				.. "Eltern koennen Kraft geben und Lernen beibringen. Den Purpose waehlt das "
				.. "Kind. Das ist der Grund, warum das Spiel drei Kapitel hat und nicht "
				.. "zwei.",
		},

		--------------------------------------------------------------------------
		-- Kopflos prüfbar: was die Spec über sich selbst sagen kann
		--------------------------------------------------------------------------
		{
			id = "citybroken.every-city-has-a-fragment",
			intent = "Jede Stadt der Groessenstaffel traegt in jedem Kapitel genau ein "
				.. "Fragment. Fehlt eines, haette eine Stadt kein Ziel ueber das Brechen "
				.. "hinaus -- und genau das ist der Zustand, den diese Spec behebt.",
			check = function(ctx)
				local violations = {}
				local alert = ctx.config and ctx.config.CityAlert
				if not alert or not alert.CityOrder then
					return violations
				end
				-- Die Prologstadt zaehlt nicht mit: sie ist Inszenierung, nicht Fortschritt.
				local staffel = {}
				for _, name in ipairs(alert.CityOrder) do
					if name ~= "PrologueCity" then
						staffel[name] = true
					end
				end
				for faktion, gabe in pairs(GABEN) do
					local gesehen = {}
					for _, eintrag in ipairs(gabe.fragmente) do
						gesehen[eintrag.stadt] = true
						if not staffel[eintrag.stadt] then
							table.insert(violations, string.format(
								"%s: Fragment fuer '%s', das es in CityOrder nicht gibt",
								faktion, eintrag.stadt))
						end
					end
					for name in pairs(staffel) do
						if not gesehen[name] then
							table.insert(violations, string.format(
								"%s: kein Fragment fuer '%s'", faktion, name))
						end
					end
				end
				return violations
			end,
		},

		{
			id = "citybroken.countermeasures-match-alert-levels",
			intent = "Die vier Gegenmassnahmen des Missionsziels entsprechen genau den "
				.. "Alarmstufen 2 bis 5. Weicht die Liste ab, zeigt das Ziel etwas anderes "
				.. "an, als die Stadt tatsaechlich aufbietet -- und der Spieler sucht eine "
				.. "Gegenmassnahme, die es nicht gibt.",
			check = function(ctx)
				local violations = {}
				local erwartet = { 2, 3, 4, 5 }
				if #GEGENMASSNAHMEN ~= #erwartet then
					table.insert(violations, string.format(
						"%d Gegenmassnahmen statt %d", #GEGENMASSNAHMEN, #erwartet))
					return violations
				end
				for index, eintrag in ipairs(GEGENMASSNAHMEN) do
					if eintrag.stufe ~= erwartet[index] then
						table.insert(violations, string.format(
							"Platz %d traegt Stufe %d, erwartet %d",
							index, eintrag.stufe, erwartet[index]))
					end
				end
				-- Keine Stadt darf eine Gegenmassnahme oberhalb ihres MaxAlertLevel zeigen.
				local alert = ctx.config and ctx.config.CityAlert
				for _, name in ipairs((alert and alert.CityOrder) or {}) do
					local stadt = alert.GetCityConfig and alert.GetCityConfig(name)
					local hoechste = stadt and stadt.MaxAlertLevel
					if hoechste and hoechste < 2 then
						table.insert(violations, string.format(
							"%s: Hoechststufe %d -- die Stadt hat keine einzige "
								.. "Gegenmassnahme und kann nicht gebrochen werden",
							name, hoechste))
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Nur in Studio prüfbar
		--------------------------------------------------------------------------
		{
			id = "citybroken.search-window-outlives-the-hunt",
			intent = "Das Zeitfenster nach dem Brechen ist lang genug, um das Fragment zu "
				.. "SUCHEN -- nicht nur, um es einzusammeln, wenn man weiss, wo es liegt.\n"
				.. "Heute sind es 75 Sekunden, gesetzt fuer freie Zerstoerung. Die Suche "
				.. "kommt neu dazu: drei bis fuenf Orte pruefen, in einer Stadt von der "
				.. "Groesse von LargeCity, mit Laufzeit zwischen den Orten. Wird es knapp, "
				.. "verlaengert das Fenster -- die Zahl der Verstecke zu senken waere der "
				.. "falsche Hebel, denn sie IST das Spiel.",
			needsRuntime = true,
		},
	},
}
