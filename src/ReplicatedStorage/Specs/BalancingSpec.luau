-- ModuleScript: BalancingSpec
--
-- Die Designabsicht des Balancings von "We Are Trenchborn".
--
-- Sie beschreibt, welches Spielerlebnis entstehen soll und wie Zerstörung, Alarm,
-- Verteidigung und Fortschritt zusammenwirken. Sie legt bewusst noch KEINE Zahlen fest:
-- die werden aus den Zielgrössen hier abgeleitet, modelliert und dann im Spiel geprüft.
--
-- ===== Warum diese Spec besonders wichtig ist =====
-- Beim Abgleich der Absicht gegen den Code waren VIER tragende Aussagen nicht eingelöst:
-- der Respawn-Stopp bei CITY BROKEN, jede Belohnung für den Guardian, XP für besiegte
-- Verteidigung, und ein Ort für Gebäudewerte. Eine fünfte -- der Gebäudeschutz des
-- Guardians -- war gebaut, greift aber wegen eines nie gesetzten Zustands nie.
--
-- Genau dafür gibt es dieses Format: die Absicht steht neben den Regeln, die sie
-- durchsetzen, und ein neuer Verstoss hält den Prüfer an. Der heutige Rückstand läuft
-- als knownViolations bewusst durch und bleibt dabei als Aufgabenliste sichtbar.
--
-- Importiert nichts, alles kommt über den ctx (siehe SpecRunner).

-- Für welche Entwicklungsstufe eine Stadt ausgelegt ist -- gemessen am ZUSTAND BEIM
-- EINTRITT. Dass sie sich gegen Ende leichter anfühlt, ist kein Balancing-Fehler,
-- sondern der ausdrücklich gewollte Vorher-Nachher-Effekt.
local EXPECTED_STAGE_BY_CITY = {
	Village = 1,
	SmallTown = 2,
	City = 3,
	LargeCity = 4,
	MegaCity = 5,
}

-- Die Höchst-Alarmstufe je Stadt und Kapitel. Kapitel I steht in der Spezifikation;
-- II und III ergeben sich daraus, dass der Guardian je Kapitel eine Stadt früher
-- einsetzt (Kapitel I ab City, II ab Small Town, III ab Village).
local MAX_ALERT_BY_CITY_AND_CHAPTER = {
	Village = { 3, 4, 5 },
	SmallTown = { 4, 5, 5 },
	City = { 5, 5, 5 },
	LargeCity = { 5, 5, 5 },
	MegaCity = { 5, 5, 5 },
}

-- Die Meilensteine der fünf Entwicklungsstufen je Figur. Die Startform ist Stufe I;
-- Level 40 schaltet die fünfte frei, die Level-Obergrenze liegt damit bei 50.
local STAGE_LEVEL_MILESTONES = { 0, 10, 20, 30, 40 }

local function cityConfig(ctx, cityName)
	local cities = ctx.config and ctx.config.CityAlert and ctx.config.CityAlert.Cities
	return cities and cities[cityName]
end

return {
	System = "Balancing",

	Rules = {
		--------------------------------------------------------------------------
		-- Kopflos prüfbar
		--------------------------------------------------------------------------
		{
			id = "balancing.five-stages-per-character",
			intent = "Jede Figur hat FÜNF Entwicklungsstufen, mit Meilensteinen bei Level "
				.. "0, 10, 20, 30 und 40. Die Startform ist Stufe I. Daraus folgt eine "
				.. "Level-Obergrenze von 50.\n"
				.. "Der Kaiju hat heute sechs Formen, die sechste bei Level 50. Alle "
				.. "Kaiju-Modelle werden ohnehin ersetzt; die neue Reihe hat fünf.",
			knownViolations = { "Kaiju:" },
			check = function(ctx)
				local violations = {}
				local skins = ctx.config and ctx.config.Skins
				if not skins or not skins.Skins then
					return violations
				end
				local byFaction = {}
				for _, skin in ipairs(skins.Skins) do
					local faction = skin.Faction or "Kaiju"
					byFaction[faction] = byFaction[faction] or {}
					table.insert(byFaction[faction], skin)
				end
				for faction, list in pairs(byFaction) do
					if #list ~= #STAGE_LEVEL_MILESTONES then
						table.insert(violations, string.format(
							"%s: %d Stufen, erwartet %d", faction, #list, #STAGE_LEVEL_MILESTONES))
					else
						for index, skin in ipairs(list) do
							local expected = STAGE_LEVEL_MILESTONES[index]
							if skin.RequiredLevel ~= expected then
								table.insert(violations, string.format(
									"%s: Stufe %d verlangt Level %s, erwartet %d",
									faction, index, tostring(skin.RequiredLevel), expected))
							end
						end
					end
				end
				return violations
			end,
		},

		{
			id = "balancing.city-declares-expected-stage",
			intent = "Jede Stadt sagt, für welche Entwicklungsstufe sie ausgelegt ist "
				.. "(ExpectedSkinStage): Village I, Small Town II, City III, Large City IV, "
				.. "Megacity V.\n"
				.. "Ohne diese Angabe ist keine einzige Zahl der Stadt herleitbar -- "
				.. "zwischen der ersten und der fünften Stufe liegt ein Vielfaches an "
				.. "Schadensleistung, und ein Wert, der für die eine stimmt, kann für die "
				.. "andere nicht stimmen.",
			knownViolations = { "Village:", "SmallTown:", "City:", "LargeCity:", "MegaCity:" },
			check = function(ctx)
				local violations = {}
				for cityName, expected in pairs(EXPECTED_STAGE_BY_CITY) do
					local city = cityConfig(ctx, cityName)
					if city and city.ExpectedSkinStage ~= expected then
						table.insert(violations, string.format(
							"%s: ExpectedSkinStage = %s, erwartet %d",
							cityName, tostring(city.ExpectedSkinStage), expected))
					end
				end
				return violations
			end,
		},

		{
			id = "balancing.alert-caps-match-chapters",
			intent = "Nicht jede Stadt erreicht jede Alarmstufe. Die Höchststufe hängt an "
				.. "Stadt UND Kapitel, weil der Guardian je Kapitel eine Stadt früher "
				.. "einsetzt: Kapitel I ab City, Kapitel II ab Small Town, Kapitel III "
				.. "bereits ab Village.\n"
				.. "Fehlt der Eintrag, gilt die Höchststufe 5 -- eine Stadt bekäme dann "
				.. "einen Guardian, den das Kapitel gar nicht vorsieht.",
			check = function(ctx)
				local violations = {}
				for cityName, expected in pairs(MAX_ALERT_BY_CITY_AND_CHAPTER) do
					local city = cityConfig(ctx, cityName)
					if city then
						local actual = city.MaxAlertLevelByChapter
						for chapter, expectedLevel in ipairs(expected) do
							-- Fehlt die Tabelle ganz, gilt die Vorgabe 5. Das ist für die
							-- drei oberen Städte richtig und nur dort zulässig.
							local actualLevel = actual and actual[chapter] or 5
							if actualLevel ~= expectedLevel then
								table.insert(violations, string.format(
									"%s: Kapitel %d erlaubt Alarm %d, erwartet %d",
									cityName, chapter, actualLevel, expectedLevel))
							end
						end
					end
				end
				return violations
			end,
		},

		{
			id = "balancing.defense-does-not-escalate",
			intent = "Verteidigung zu besiegen macht den Weg frei -- es verschärft die Lage "
				.. "NICHT. Kein besiegtes Verteidigungssystem erzeugt Alarmfortschritt.\n"
				.. "Heute erzeugt genau eines welchen: ein zerstörtes Feuerwehrauto, über "
				.. "FireEngineDestroyAlertValue. Eine Ausnahme, die nur für ein System gilt "
				.. "und nirgends begründet ist, wird beim nächsten Balancing-Durchgang zur "
				.. "Stolperstelle -- der Wert entfällt.",
			knownViolations = {
				"Village:", "SmallTown:", "City:", "LargeCity:", "MegaCity:", "PrologueCity:",
			},
			check = function(ctx)
				local violations = {}
				local cityAlert = ctx.config and ctx.config.CityAlert
				if not cityAlert or not cityAlert.Cities then
					return violations
				end
				for _, cityName in ipairs(cityAlert.CityOrder or {}) do
					local city = cityAlert.Cities[cityName]
					if city and city.FireEngineDestroyAlertValue ~= nil then
						table.insert(violations, string.format(
							"%s: FireEngineDestroyAlertValue = %s -- besiegte Verteidigung darf nicht eskalieren",
							cityName, tostring(city.FireEngineDestroyAlertValue)))
					end
				end
				return violations
			end,
		},

		{
			id = "balancing.every-defeat-pays",
			intent = "Jedes besiegbare Verteidigungssystem belohnt mit XP UND Geld -- "
				.. "Feuerwehr, Barrikaden, Militär, Guardian. Jede Stufe kostet den Spieler "
				.. "Zeit und Risiko; keine davon zu belohnen macht das Ausschalten zur "
				.. "reinen Pflichtübung.\n"
				.. "Evolutionspunkte bleiben ausdrücklich an der Zerstörung: sie sind die "
				.. "Währung der Stadt, nicht des Kampfes.\n"
				.. "Der Guardian trägt dabei den mit Abstand höchsten XP-Wert -- er soll für "
				.. "effiziente Progression fast notwendig erscheinen, ohne sie hart zu "
				.. "blockieren. Sein Wert ist FEST und füllt nicht dynamisch bis zum "
				.. "nächsten Level auf; nur so bleiben andere Spielweisen möglich.\n"
				.. "Heute gibt der Guardian gar nichts, Militär und Barrikaden geben nichts, "
				.. "die Feuerwehr nur Geld.",
			knownViolations = { "Village:", "SmallTown:", "City:", "LargeCity:", "MegaCity:" },
			check = function(ctx)
				local violations = {}
				for cityName in pairs(EXPECTED_STAGE_BY_CITY) do
					local city = cityConfig(ctx, cityName)
					if city and city.GuardianHP ~= nil then
						-- Nur Städte mit Guardian müssen seine Belohnung nennen.
						if city.GuardianXPReward == nil or city.GuardianCoinsReward == nil then
							table.insert(violations, string.format(
								"%s: Guardian ohne Belohnung -- GuardianXPReward=%s, GuardianCoinsReward=%s",
								cityName, tostring(city.GuardianXPReward), tostring(city.GuardianCoinsReward)))
						end
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Nur in Studio prüfbar
		--------------------------------------------------------------------------
		{
			id = "balancing.city-broken-stops-respawn",
			intent = "Während CITY BROKEN respawnen keine Gebäude. Genau daran ist der "
				.. "Wechsel sichtbar: aus einer Stadt, die sich wehrt und nachwächst, wird "
				.. "eine, die sich nicht mehr erholt.\n"
				.. "Heute läuft der Respawn-Zeitgeber während des Fensters unverändert "
				.. "weiter -- die Stadt baut sich mitten in der Siegesphase wieder auf. Das "
				.. "Kennzeichen <Stadt>CityBroken lesen nur das HUD und der Showdown.",
			needsRuntime = true,
			check = function(ctx)
				local violations = {}
				if not ctx.runtime.HasGlobal("IsCityBroken") then
					table.insert(violations,
						"_G.IsCityBroken fehlt -- der Haus-Respawn kann den Zustand nicht abfragen")
				end
				return violations
			end,
		},

		{
			id = "balancing.building-values-live-in-config",
			intent = "Die Werte eines Gebäudes stehen zentral je GEBÄUDETYP im Repo, nicht "
				.. "als Attribut an jeder einzelnen Instanz in Studio. Eine Instanz wird "
				.. "ihrem Typ über das Attribut BuildingType zugeordnet -- am Namen wäre die "
				.. "Zuordnung nach jeder Umbenennung still kaputt.\n"
				.. "Die Config trägt Lebenspunkte, Energiemenge, Energietyp, Geldwert, "
				.. "Evolutionspunkte, Alarmbeitrag und die Detailklasse.\n"
				.. "Heute gibt es sie nicht: alle Werte hängen an den Instanzen, und was "
				.. "kein Attribut trägt, bekommt stillschweigend 100 Lebenspunkte. Eine aus "
				.. "Trefferzahlen abgeleitete Progression hätte keinen Ort, an dem sie "
				.. "landen könnte.",
			needsWorkspace = true,
			check = function(ctx)
				local violations = {}
				local untyped = ctx.workspace.CountBuildingsWithoutType and
					ctx.workspace.CountBuildingsWithoutType() or 0
				if untyped > 0 then
					table.insert(violations, string.format(
						"%d Gebäude ohne BuildingType-Attribut -- sie fallen auf den Vorgabewert zurück",
						untyped))
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Weiche Aussagen -- beim Abgleich mitzulesen
		--------------------------------------------------------------------------
		{
			id = "balancing.player-drives-escalation",
			intent = "WEICH: Der Alarm steigt durch die Zerstörung, die der Spieler "
				.. "verursacht, nicht durch Zeit. Er erzeugt seine Gegner also selbst.\n"
				.. "Der ABBAU ist zeitbasiert und läuft nur, solange kein Spieler in der "
				.. "Stadt ist -- wer bleibt, kann die Lage nicht aussitzen.",
		},

		{
			id = "balancing.player-controls-risk",
			intent = "WEICH: Der Spieler entscheidet, welche Folgen seiner Eskalation er "
				.. "bekämpft und welche er ignoriert. Alarmstufen sind kumulativ, nicht "
				.. "gegated: eine Stufe muss nicht beseitigt sein, um die nächste zu "
				.. "erreichen. Feuerwehr, Barrikaden, Militär und Guardian dürfen "
				.. "gleichzeitig aktiv sein -- ignorierte Verteidigung sammelt sich an und "
				.. "erzeugt die Schwierigkeit systemisch statt über Zahlen.\n"
				.. "Rückzug ins Sanctuary ist eine taktische Entscheidung, kein Scheitern; "
				.. "der Stadtfortschritt bleibt erhalten.",
		},

		{
			id = "balancing.each-level-attacks-another-dimension",
			intent = "WEICH: Keine Alarmstufe ist einfach die vorherige mit mehr Schaden. "
				.. "Jede greift eine andere Dimension an:\n"
				.. "  1 Helikopter -- Aufmerksamkeit. Nicht zerstörbar, zählt deshalb nicht "
				.. "für CITY BROKEN und bleibt auch danach und berichtet.\n"
				.. "  2 Feuerwehr -- Wirtschaft. Sie löscht Feuer und vernichtet damit "
				.. "Energie, bevor der Spieler sie einsammeln kann.\n"
				.. "  3 Barrikaden und Schilde -- Zugang und Bewegung. Geschützte Gebäude "
				.. "sind VOLLSTÄNDIG unverwundbar, nicht nur widerstandsfähiger.\n"
				.. "  4 Militär -- Überleben. Ab hier geht es erstmals nicht mehr um "
				.. "Effizienz, sondern darum, am Leben zu bleiben.\n"
				.. "  5 Guardian -- Fortschritt. Bosskampf, Gebäudeschutz und Tor zur "
				.. "nächsten Entwicklungsstufe in einem.\n"
				.. "Wer eine Stufe umbaut, prüft zuerst, ob ihre Dimension erhalten bleibt.",
		},

		{
			id = "balancing.guardian-blocks-buildings",
			intent = "WEICH: Der Guardian schützt die wertvollsten Gebäude seiner Stadt "
				.. "vollständig vor Zerstörung, solange er lebt. Das ist der Punkt, der ihn "
				.. "von einem Gegner mit vielen Lebenspunkten unterscheidet: der Spieler "
				.. "MUSS durch ihn hindurch, statt ihn umgehen zu können.\n"
				.. "Die Mechanik ist gebaut, greift aber nie -- die Prüfung fragt nach dem "
				.. "Zustand \"Block\", den niemand setzt; gesetzt werden nur Idle, Patrol, "
				.. "Defend, Engage, Return und Defeated. Ausserdem schützt sie bisher nur "
				.. "EIN Gebäude gleichzeitig.",
		},

		{
			id = "balancing.destruction-pays-immediately",
			intent = "WEICH: Zerstörung lohnt sich sofort, das Aufräumen lohnt sich mehr. "
				.. "Ein kleiner Teil der Energie (etwa 10 bis 15 Prozent) fällt beim "
				.. "Zerstören sofort an, der grosse Rest brennt und muss eingesammelt "
				.. "werden.\n"
				.. "Nur so kann die Feuerwehr den Löwenanteil bedrohen -- heute sind es 40 "
				.. "Prozent sofort, und ihr Wirtschaftsdruck ist damit von vornherein auf "
				.. "gut die Hälfte gedeckelt.",
		},

		{
			id = "balancing.rewards-decoupled-with-fallback",
			intent = "WEICH: Alarmbeitrag, Energiemenge, Geldwert und Evolutionspunkte sind "
				.. "je Gebäudetyp frei setzbar und NICHT zwingend an die Lebenspunkte "
				.. "gekoppelt. Ein strategisch bedeutendes Gebäude darf viel Alarm erzeugen, "
				.. "ohne mehr Lebenspunkte zu haben.\n"
				.. "Wer keinen Wert setzt, bekommt weiterhin die Ableitung aus den "
				.. "Lebenspunkten. Der Rückfall ist Absicht: ohne ihn erzeugte ein neues "
				.. "Gebäude ohne Eintrag still null Alarm und null Belohnung.",
		},

		{
			id = "balancing.hits-to-kill-is-the-anchor",
			intent = "WEICH: Die Zahlen werden aus TREFFERZAHLEN abgeleitet, nicht aus "
				.. "Minuten. Zuerst steht fest, nach wie vielen Schlägen das schwächste und "
				.. "das stärkste Gebäude fallen sollen; daraus folgen Lebenspunkte, daraus "
				.. "die Zeit -- die danach nur noch geprüft wird.\n"
				.. "Grund: die Trefferzahl ist das Einzige, was der Spieler unmittelbar "
				.. "spürt. Minuten und XP-Kurven spürt er nie.\n"
				.. "Gegenprobe ist der Fortschritt: bis CITY BROKEN sollte ein normal "
				.. "spielender Spieler den nächsten Level-Meilenstein und den Preis der "
				.. "nächsten Entwicklungsstufe erreicht haben -- ein Ziel, kein Zwang.",
		},

		{
			id = "balancing.reference-player",
			intent = "WEICH: Balanciert wird für einen genau beschriebenen Spieler.\n"
				.. "  * Er spielt KONTROLLIERT: er räumt jede Verteidigungsstufe weg, bevor "
				.. "er weiter eskaliert. Der aggressive Weg ist dann bewusst schneller und "
				.. "härter -- und nicht modellierbar, weil er davon abhängt, wie viel "
				.. "Schaden man unterwegs frisst.\n"
				.. "  * Er hat KAUM Talente. Wer investiert, hat es merklich leichter; wer "
				.. "sie ignoriert, kommt trotzdem durch.\n"
				.. "  * Er ist ALLEIN. Zu zweit ist es leichter, und das ist in Ordnung -- "
				.. "aber Messwerte aus einer Sitzung zu zweit sind keine Referenzwerte.\n"
				.. "  * Zeitliche Verstärkungen zählen NICHT mit. Das Basisspiel muss sich "
				.. "ohne sie gut anfühlen.",
		},

		{
			id = "balancing.city-tuned-for-entry",
			intent = "WEICH: Eine Stadt wird für den Zustand ausgelegt, mit dem der Spieler "
				.. "sie BETRITT. Dass sie sich gegen Ende leichter anfühlt, ist kein "
				.. "Balancing-Fehler, sondern das Ziel: ein Gebäude, das anfangs mehrere "
				.. "Angriffe brauchte, soll später deutlich schneller fallen.\n"
				.. "Eine Spanne zu balancieren würde genau diesen Effekt wegmitteln.\n"
				.. "Evolutionen sollen dabei grössere Sprünge sein als Level-Ups -- "
				.. "idealerweise nicht nur mehr Schaden, sondern eine andere Spielweise.",
		},

		{
			id = "balancing.city-broken-is-the-switch",
			intent = "WEICH: CITY BROKEN wird nicht über eine Zahl zerstörter Gebäude "
				.. "erreicht, sondern dadurch, dass ALLE besiegbaren Verteidigungssysteme "
				.. "der Stadt überwunden sind -- der Guardian eingeschlossen, wo es einen "
				.. "gibt. Der Helikopter zählt nicht, er ist nicht zerstörbar.\n"
				.. "Danach folgt ein Zeitfenster freier Zerstörung: kein Respawn, keine "
				.. "Verteidigung (es ist per Definition keine mehr da), volle Belohnung. "
				.. "Nach dem Fenster beruhigt sich die Stadt und der Kreislauf beginnt von "
				.. "vorn -- dieselbe Stadt wird in Kapitel II und III erneut gespielt.",
		},

		{
			id = "balancing.no-preemptive-anti-farming",
			intent = "WEICH: Mehrfach zerstörte Gebäude dürfen erneut Belohnung und "
				.. "Alarmfortschritt erzeugen. Gegen Farming wird NICHT vorsorglich gebaut.\n"
				.. "Erst wenn ein Playtest zeigt, dass daraus ein Problem entsteht, wird "
				.. "etwas dagegen unternommen -- und dann gezielt gegen das beobachtete "
				.. "Verhalten, nicht gegen ein vermutetes.",
		},

		{
			id = "balancing.numbers-come-last",
			intent = "WEICH: Diese Spec enthält bewusst keine finalen Zahlen. Offen sind "
				.. "unter anderem: die Trefferzahl für das schwächste Gebäude (der erste zu "
				.. "setzende Wert, alles andere folgt daraus), die HP-Kurve, die Zielzeit je "
				.. "Stadt, XP- und Geldraten, der XP-Wert des Guardians, die Alarmschwellen "
				.. "und die Alarmbeiträge je Gebäudetyp.\n"
				.. "Ziel ist nicht, möglichst grosse Zahlen zu erreichen, sondern ein gutes "
				.. "Zerstörungsgefühl. Jede Zahl wird erst modelliert und dann im Spiel "
				.. "geprüft -- nie umgekehrt.",
		},
	},
}
