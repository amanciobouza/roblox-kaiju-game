-- ModuleScript: ShowdownSpec
--
-- Der Showdown: was gelten soll, wenn Spieler und Guardian sich gegenseitig angreifen und
-- das Spiel die Kamera übernimmt.
--
-- Warum diese Spec vor dem Code entstand: das Feature verbindet vier Systeme, die bisher
-- nichts voneinander wussten -- Guardian-Kampf, Spieler-Spezialangriffe, Kamera und HUD.
-- Genau in solchen Verbindungen ist im Bestand mehrfach eine dokumentierte Absicht
-- verlorengegangen, ohne dass es jemand merkte. Die Telegraph-Zeiten der Guardians sind
-- das jüngste Beispiel: sie standen konfiguriert da, wurden aber NACH dem Schaden
-- abgespielt und warnten damit vor nichts.
--
-- Importiert nichts, alles kommt über den ctx (siehe SpecRunner).

-- Welcher Shot zu welchem Guardian gehört. Steht hier und nicht in der Config, weil es
-- eine Aussage ÜBER die Config ist -- die Regel unten prüft damit deren Stimmigkeit.
local SHOT_TO_ASSET = {
	WarningPulse = "WardenShepherd",
	ContainmentNet = "MarshalRoadblock",
	ShoulderMissiles = "AegisInterceptor",
	GroundSlam = "BastionColossus",
	ApexLanceBeam = "SovereignApex",
}

return {
	System = "Showdown",

	Rules = {
		--------------------------------------------------------------------------
		-- Kopflos prüfbar: die Zahlen müssen zueinander passen
		--------------------------------------------------------------------------
		{
			id = "showdown.guardian-shot-matches-telegraph",
			intent = "Ein Angriffs-Shot eines Guardians dauert GENAU so lange wie die "
				.. "Ansatzphase des Angriffs, den er zeigt. Die Kamera soll in dem "
				.. "Moment zurückfahren, in dem der Schaden eintritt -- fährt sie früher "
				.. "zurück, sieht man den Einschlag nicht; fährt sie später zurück, "
				.. "schaut man auf eine Mündung, aus der längst nichts mehr kommt.",
			check = function(ctx)
				local violations = {}
				local showdown = ctx.config and ctx.config.Showdown
				if not showdown then
					return violations
				end
				for shotName, asset in pairs(SHOT_TO_ASSET) do
					local shot = showdown.Shots[shotName]
					local telegraph = showdown.GuardianTelegraph[asset]
					if not shot then
						table.insert(violations, shotName .. ": kein Shot in ShowdownConfig.Shots")
					elseif not telegraph then
						table.insert(violations, shotName .. ": keine Ansatzphase für " .. asset)
					elseif math.abs(shot.duration - telegraph) > 0.001 then
						table.insert(violations, string.format(
							"%s: Shot dauert %.2fs, Ansatzphase %.2fs -- Kamera und Einschlag fallen auseinander",
							shotName, shot.duration, telegraph))
					end
				end
				return violations
			end,
		},

		{
			id = "showdown.shots-fit-in-gap",
			intent = "Kein Shot dauert länger als der Mindestabstand zwischen zwei Shots. "
				.. "Sonst kann ein zweiter Shot beginnen, während der erste noch läuft -- "
				.. "die Kamera bekäme zwei Anweisungen gleichzeitig, und welche gewinnt, "
				.. "hinge an der Reihenfolge zweier Ereignisse.",
			check = function(ctx)
				local violations = {}
				local showdown = ctx.config and ctx.config.Showdown
				if not showdown then
					return violations
				end
				for shotName, shot in pairs(showdown.Shots) do
					if shot.duration >= showdown.ShotMinimumGap then
						table.insert(violations, string.format(
							"%s: dauert %.2fs, Mindestabstand ist aber nur %.2fs",
							shotName, shot.duration, showdown.ShotMinimumGap))
					end
				end
				return violations
			end,
		},

		{
			id = "showdown.shot-sources-known",
			intent = "Jeder Shot nennt als Quelle entweder Player oder Guardian. Die Quelle "
				.. "entscheidet den Vorrang, wenn beide gleichzeitig angreifen -- ein "
				.. "unbekannter Wert liesse den Vergleich still auf nil laufen und der "
				.. "Vorrang wäre zufällig.",
			check = function(ctx)
				local violations = {}
				local showdown = ctx.config and ctx.config.Showdown
				if not showdown then
					return violations
				end
				for shotName, shot in pairs(showdown.Shots) do
					if showdown.ShotPriority[shot.source] == nil then
						table.insert(violations, string.format(
							"%s: Quelle %q hat keinen Vorrangwert", shotName, tostring(shot.source)))
					end
					if not shot.style or shot.style == "" then
						table.insert(violations, shotName .. ": keine Kamerafahrt (style) angegeben")
					end
					if not shot.duration or shot.duration <= 0 then
						table.insert(violations, shotName .. ": Dauer fehlt oder ist nicht positiv")
					end
				end
				return violations
			end,
		},

		{
			id = "showdown.giveup-lock-outlasts-minimum",
			intent = "Die Sperre nach dem Aufgeben ist länger als die Mindestdauer eines "
				.. "Showdowns. Wäre sie kürzer, könnte der nächste Showdown starten, bevor "
				.. "der Spieler den Guardian überhaupt verlassen kann -- der Aufgeben-Knopf "
				.. "wäre dann nur eine Verzögerung und kein Ausweg.",
			check = function(ctx)
				local violations = {}
				local showdown = ctx.config and ctx.config.Showdown
				if not showdown then
					return violations
				end
				if showdown.ReentryLockAfterGiveUp <= showdown.MinimumDuration then
					table.insert(violations, string.format(
						"Sperre %.0fs ist nicht länger als die Mindestdauer %.0fs",
						showdown.ReentryLockAfterGiveUp, showdown.MinimumDuration))
				end
				return violations
			end,
		},

		{
			id = "showdown.letterbox-leaves-room-for-hud",
			intent = "Die Filmstreifen sind schmaler als die des Prologs (9 % je Balken). "
				.. "Der Prolog blendet das HUD aus, der Showdown NICHT -- dort wird "
				.. "weitergekämpft, also brauchen Lebensbalken und Angriffsknöpfe den Platz.",
			check = function(ctx)
				local violations = {}
				local showdown = ctx.config and ctx.config.Showdown
				if not showdown then
					return violations
				end
				local fraction = showdown.Letterbox.BarHeightFraction
				if fraction >= 0.09 then
					table.insert(violations, string.format(
						"Balkenhöhe %.3f -- nicht schmaler als der Prolog (0.09)", fraction))
				end
				return violations
			end,
		},

		{
			id = "showdown.hud-keeps-what-is-needed",
			intent = "Was während des Showdowns ausgeblendet wird, darf nichts enthalten, "
				.. "was zum Kämpfen gebraucht wird. Angriffsknöpfe, Lebensanzeige, "
				.. "Berserker-Anzeige und der Lebensbalken des Guardians bleiben stehen.",
			check = function(ctx)
				local violations = {}
				local showdown = ctx.config and ctx.config.Showdown
				if not showdown then
					return violations
				end
				local mustStay = {
					SpecialAttackGui = true,
					CityAlertHudGui = true,
					GameHud = true,
				}
				for _, guiName in ipairs(showdown.HiddenGuis) do
					if mustStay[guiName] then
						table.insert(violations, guiName .. ": wird zum Kämpfen gebraucht, darf nicht ausgeblendet werden")
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Nur in Studio prüfbar
		--------------------------------------------------------------------------
		{
			id = "showdown.server-api-complete",
			intent = "Der Showdown-Dienst meldet sich mit seiner vollständigen "
				.. "Schnittstelle an. Fehlt eine Hälfte, laufen die Meldestellen in "
				.. "CityDefenderService und SpecialAttackHandler still ins Leere -- sie "
				.. "sind alle nil-geprüft, es gäbe also keine Fehlermeldung, nur einen "
				.. "Showdown, der nie startet oder nie einen Shot zeigt.",
			needsRuntime = true,
			check = function(ctx)
				local violations = {}
				for _, name in ipairs({
					"NotifyShowdownDamage",
					"NotifyShowdownAttack",
					"IsShowdownActive",
					"EndShowdown",
				}) do
					if not ctx.runtime.HasGlobal(name) then
						table.insert(violations, "_G." .. name .. " fehlt")
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Weiche Aussagen -- beim Abgleich mitzulesen
		--------------------------------------------------------------------------
		{
			id = "showdown.never-cross-the-axis",
			intent = "WEICH: Die Kamera überschreitet nie die Verbindungslinie zwischen "
				.. "Spieler und Guardian -- weder in der Ruhelage noch in einem Shot.\n"
				.. "Das ist keine Geschmacksfrage. Die Steuerung ist im Showdown an diese "
				.. "Achse gebunden: links und rechts gehen auf den Guardian zu und von ihm "
				.. "weg. Wechselt die Kamera die Seite, tauschen die beiden auf dem "
				.. "Bildschirm die Plätze und die Steuerung dreht sich unter den Fingern "
				.. "des Spielers um. Kampfspiele halten diese Regel seit dreissig Jahren "
				.. "ein, aus genau diesem Grund.",
		},

		{
			id = "showdown.telegraph-precedes-damage",
			intent = "WEICH: Bei den drei Flächenangriffen der Guardians (Warnimpuls, "
				.. "Fangnetz, Raketensalve) läuft die Ansatzphase VOR dem Schaden.\n"
				.. "Vorher war es umgekehrt: der Schaden traf sofort, der Effekt lief "
				.. "verzögert hinterher. Die Telegraph-Zeiten standen konfiguriert da und "
				.. "warnten vor nichts -- eine dokumentierte Absicht, die nie eingelöst "
				.. "wurde. Wer diese Reihenfolge wieder umdreht, nimmt der Kamera ihre "
				.. "Grundlage: ein Angriff ohne Ansatz ist nicht zeigbar, nur bestätigbar.\n"
				.. "Die Kanonen und der Schockstab bleiben bewusst sofort -- ein "
				.. "Nahkampfschlag SOLL schnell sein.",
		},

		{
			id = "showdown.one-session-per-player",
			intent = "WEICH: Jeder Spieler hat seinen eigenen Showdown mit eigener "
				.. "Mindestdauer, eigener Kamera und eigenem Aufgeben-Knopf. Der Guardian "
				.. "führt einen Kampf, aber jeder Beteiligte sieht seinen eigenen Film.\n"
				.. "Wer als Zweiter dazustösst, soll seine vollen fünfzehn Sekunden "
				.. "bekommen und nicht in eine Sequenz fallen, die drei Sekunden später "
				.. "endet. Und eine Kamera, die vier Kämpfer gleichzeitig im Bild halten "
				.. "muss, fährt zwangsläufig weit weg -- weg von der Bodenperspektive, um "
				.. "die es hier geht.",
		},

		{
			id = "showdown.camera-sessions-are-shared",
			intent = "WEICH: Die Showdown-Kamera nutzt denselben Session-Zähler wie alle "
				.. "anderen Kameraschleifen (CameraSessionUtils).\n"
				.. "CLAUDE.md nennt konkurrierende Kameraschleifen ausdrücklich als "
				.. "Fehlerquelle: jede Schleife braucht eine Session-ID und muss sich "
				.. "beenden, sobald eine neue Session beginnt. Zwei Zähler, die einander "
				.. "nicht kennen, sind genau der Fall, den diese Regel verhindern soll -- "
				.. "und der Bestand hatte ihn, weil der Zähler dateilokal im Prolog-Client "
				.. "lag.",
		},

		{
			id = "showdown.excluded-situations",
			intent = "WEICH: Kein Showdown im Prolog, keiner gegen einen bereits besiegten "
				.. "Guardian, keiner während CITY BROKEN.\n"
				.. "Der Prolog führt eigene Kamerafahrten und fügt dem Guardian selbst "
				.. "Schaden zu -- ein Showdown darin liesse zwei Kamerasysteme "
				.. "gegeneinander laufen. Der besiegte Guardian bleibt liegen, bis die "
				.. "Stadt bricht; Schaden auf einen Liegenden soll nichts auslösen. Und "
				.. "die 75 Sekunden CITY BROKEN sind ausdrücklich die Belohnungsphase ohne "
				.. "Eskalation.",
		},

		{
			id = "showdown.guardian-becomes-easier",
			intent = "WEICH: Mit der Ansatzphase kann man den Flächenangriffen des "
				.. "Guardians erstmals ausweichen -- er wird dadurch spürbar leichter. "
				.. "Das ist der bewusst bezahlte Preis für Lesbarkeit und Regie. Wird "
				.. "nachgeschärft, dann über Schaden oder Häufigkeit, NICHT durch "
				.. "Zurücknehmen der Ansatzphase.",
		},
	},
}
