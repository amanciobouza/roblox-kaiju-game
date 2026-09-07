-- ModuleScript: VillageChapterOneSpec
--
-- Die erste Stadt, für die konkrete Zahlen festgelegt sind:
-- Kapitel I → Kaiju → Village → Eintritt mit Entwicklungsstufe I.
--
-- Diese Spec ist die Anwendung von BalancingSpec auf einen Einzelfall. Was dort als
-- Absicht steht ("verankert wird über Trefferzahlen"), steht hier als Zahl
-- ("Cottage = 100 HP = 6 Schläge").
--
-- ===== Warum die Zahlen hier zusammen stehen =====
-- Drei voneinander unabhängige Modelle -- Erfahrung, Geld und Alarmfortschritt -- müssen
-- dieselbe Aussage über den Spielverlauf ergeben, sonst widerspricht sich das Balancing
-- selbst. Beim Entwurf taten sie das auf 1,5 Prozent genau: alle drei sagen, dass der
-- Referenzspieler das Dorf rund viereinhalb Mal vollständig abräumt.
--
-- Das ist kein Zufall, sondern die Probe. Wer eine dieser Zahlen ändert, ohne die
-- anderen mitzuziehen, bricht die Übereinstimmung -- und genau das prüft die Regel
-- village.models-agree-on-clear-count.
--
-- Importiert nichts, alles kommt über den ctx (siehe SpecRunner).

-- ===== Der Bestand des Dorfes =====
-- 24 Gebäude. hits ist der Sollwert aus der Spezifikation, nicht die Rechnung -- die
-- Regel unten prüft, dass beides zusammenpasst.
local BUILDINGS = {
	{ name = "Cottage", class = "L1", count = 11, hp = 100, hits = 6, energy = 25, dv = 1.0 },
	{ name = "Farmhouse", class = "L1", count = 3, hp = 125, hits = 8, energy = 30, dv = 1.25 },
	{ name = "Barn", class = "L2", count = 3, hp = 200, hits = 12, energy = 40, dv = 2.0 },
	{ name = "Stable", class = "L2", count = 3, hp = 250, hits = 15, energy = 50, dv = 2.5 },
	{ name = "Workshop", class = "L2", count = 2, hp = 300, hits = 18, energy = 60, dv = 3.0 },
	{ name = "Mill", class = "L3", count = 1, hp = 500, hits = 30, energy = 100, dv = 5.0 },
	{ name = "SmallChapel", class = "L3", count = 1, hp = 1000, hits = 60, energy = 150, dv = 10.0 },
}

-- Der Anker der gesamten Spezifikation: ein Cottage fällt beim Eintritt nach sechs
-- Schlägen. Daraus folgt alles Weitere.
local BASE_DAMAGE = 17

-- Die Geldformel des Bestands bleibt: floor(MaxHealth^0.75 * 1.2).
local COINS_EXPONENT = 0.75
local COINS_SCALE = 1.2

-- Erfahrung je Stufe, 1 bis 10.
local XP_PER_LEVEL = { 200, 275, 350, 400, 450, 500, 575, 700, 900 }

local DEFENSE_XP = 100 + 250 -- Feuerwehr + Barrikaden/Schilde
local DEFENSE_COINS = 500 + 1000

-- Anteil der Gesamtenergie, den ein Referenzspieler tatsächlich erhält. Der Rest geht
-- an die Feuerwehr oder wird nicht eingesammelt.
local ABSORB_EFFICIENCY = 0.88

local ALARM_THRESHOLD_LEVEL3 = 225 -- Zerstörungswert bis Alarmstufe 3
local EVOLUTION_PRICE = 6000
local COINS_TARGET_AT_CITY_BROKEN = 8200

-- Wie weit die drei Modelle voneinander abweichen dürfen, bevor es ein Verstoss ist.
-- 15 % lässt Spielraum für gerundete Einzelwerte, schlägt aber an, sobald jemand eine
-- der drei Grössen verschiebt, ohne die anderen mitzuziehen.
local MODEL_TOLERANCE = 0.15

local function totals()
	local energy, coins, dv, count = 0, 0, 0, 0
	for _, b in ipairs(BUILDINGS) do
		energy += b.energy * b.count
		coins += math.floor(b.hp ^ COINS_EXPONENT * COINS_SCALE) * b.count
		dv += b.dv * b.count
		count += b.count
	end
	return energy, coins, dv, count
end

local function totalXPToLevel10()
	local sum = 0
	for _, value in ipairs(XP_PER_LEVEL) do
		sum += value
	end
	return sum
end

return {
	System = "VillageChapterOne",

	Rules = {
		--------------------------------------------------------------------------
		-- Kopflos prüfbar: die Zahlen müssen zueinander passen
		--------------------------------------------------------------------------
		{
			id = "village.hit-ladder-matches-damage",
			intent = "Die Trefferzahl jedes Gebäudes ergibt sich aus seinen Lebenspunkten "
				.. "geteilt durch den Grundschaden beim Eintritt (17). Das ist der Anker "
				.. "der ganzen Spezifikation: wer die Lebenspunkte oder den Grundschaden "
				.. "ändert, verschiebt jede Zeitangabe im Dokument mit.",
			check = function()
				local violations = {}
				for _, b in ipairs(BUILDINGS) do
					local expected = math.ceil(b.hp / BASE_DAMAGE)
					-- Eine Abweichung von einem Treffer ist Rundung, mehr nicht.
					if math.abs(expected - b.hits) > 1 then
						table.insert(violations, string.format(
							"%s: %d HP bei %d Schaden ergibt %d Treffer, angegeben sind %d",
							b.name, b.hp, BASE_DAMAGE, expected, b.hits))
					end
				end
				return violations
			end,
		},

		{
			id = "village.models-agree-on-clear-count",
			intent = "Erfahrung, Geld und Alarmfortschritt müssen dieselbe Aussage darüber "
				.. "ergeben, wie oft der Referenzspieler das Dorf abräumt. Sonst "
				.. "widerspricht sich das Balancing selbst -- und man merkt es erst im "
				.. "Playtest, wo man es der falschen Ursache zuschreibt.\n"
				.. "Beim Entwurf stimmten die drei auf 1,5 Prozent überein: rund "
				.. "viereinhalb vollständige Durchgänge.",
			check = function()
				local energy, coins, dv = totals()
				local violations = {}

				local byXP = (totalXPToLevel10() - DEFENSE_XP) / (energy * ABSORB_EFFICIENCY)
				local byCoins = (COINS_TARGET_AT_CITY_BROKEN - DEFENSE_COINS) / coins
				local byDV = ALARM_THRESHOLD_LEVEL3 / dv

				local models = {
					{ name = "Erfahrung", value = byXP },
					{ name = "Geld", value = byCoins },
					{ name = "Zerstörungswert", value = byDV },
				}
				local lowest, highest = models[1], models[1]
				for _, model in ipairs(models) do
					if model.value < lowest.value then
						lowest = model
					end
					if model.value > highest.value then
						highest = model
					end
				end

				if lowest.value <= 0 then
					table.insert(violations, "Ein Modell ergibt keine positive Durchgangszahl")
					return violations
				end

				local spread = (highest.value - lowest.value) / lowest.value
				if spread > MODEL_TOLERANCE then
					table.insert(violations, string.format(
						"Modelle weichen um %.0f%% ab: %s %.2f Durchgaenge, %s %.2f",
						spread * 100, lowest.name, lowest.value, highest.name, highest.value))
				end
				return violations
			end,
		},

		{
			id = "village.money-covers-evolution",
			intent = "Bis CITY BROKEN soll der Referenzspieler die nächste "
				.. "Entwicklungsstufe bezahlen können und darüber hinaus Spielraum haben. "
				.. "Reicht es nicht, wird die Evolution zum Grind; ist zu viel übrig, "
				.. "verliert Geld seine Rolle als knappe Währung.",
			check = function()
				local violations = {}
				local headroom = COINS_TARGET_AT_CITY_BROKEN - EVOLUTION_PRICE
				if headroom < 0 then
					table.insert(violations, string.format(
						"Ziel %d Coins deckt den Preis von %d nicht",
						COINS_TARGET_AT_CITY_BROKEN, EVOLUTION_PRICE))
				elseif headroom > EVOLUTION_PRICE then
					table.insert(violations, string.format(
						"Nach der Evolution bleiben %d Coins -- mehr als der Preis selbst, Geld ist zu locker",
						headroom))
				end
				return violations
			end,
		},

		{
			id = "village.alert-cap-is-three",
			intent = "Das Village erreicht in Kapitel I höchstens Alarmstufe 3. Es hat "
				.. "damit weder Militär noch Guardian -- die Verteidigung endet bei "
				.. "Barrikaden und Schilden, und CITY BROKEN verlangt nur diese beiden.",
			check = function(ctx)
				local violations = {}
				local cities = ctx.config and ctx.config.CityAlert and ctx.config.CityAlert.Cities
				local village = cities and cities.Village
				if not village then
					return violations
				end
				local caps = village.MaxAlertLevelByChapter
				local chapterOne = caps and caps[1] or 5
				if chapterOne ~= 3 then
					table.insert(violations, string.format(
						"Village: Kapitel I erlaubt Alarm %d, erwartet 3", chapterOne))
				end
				return violations
			end,
		},

		{
			id = "village.buildings-declared-centrally",
			intent = "Die 24 Gebäude des Dorfes stehen mit Lebenspunkten, Energie, "
				.. "Zerstörungswert und Detailklasse in einer Gebäude-Config im Repo -- "
				.. "nicht als Attribute an einzelnen Instanzen in Studio.\n"
				.. "Solange es sie nicht gibt, sind die Zahlen dieser Spec eine Absicht "
				.. "ohne Ort: was in Studio kein Attribut trägt, bekommt stillschweigend "
				.. "100 Lebenspunkte, und keine Regel kann das bemerken.",
			knownViolations = { "Gebaeude-Config fehlt" },
			check = function(ctx)
				local violations = {}
				local buildings = ctx.config and ctx.config.Buildings
				if not buildings then
					table.insert(violations,
						"Gebaeude-Config fehlt -- die 24 Village-Gebaeude sind nirgends zentral erfasst")
					return violations
				end
				for _, b in ipairs(BUILDINGS) do
					local entry = buildings[b.name]
					if not entry then
						table.insert(violations, b.name .. ": kein Eintrag in der Gebaeude-Config")
					elseif entry.MaxHealth ~= b.hp then
						table.insert(violations, string.format(
							"%s: MaxHealth %s, erwartet %d", b.name, tostring(entry.MaxHealth), b.hp))
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Nur in Studio prüfbar
		--------------------------------------------------------------------------
		{
			id = "village.entry-damage-is-seventeen",
			intent = "Ein frisch angelegter Spieler macht 17 Schaden. Darauf steht die "
				.. "gesamte Trefferleiter.\n"
				.. "Heute sind es 8: der Grundschaden ist ArmPower/100, und ein Startspieler "
				.. "hat 800. Die Obergrenze je Level steigt dafür von 10 auf 21.",
			needsRuntime = true,
			knownViolations = { "Grundschaden" },
			check = function(ctx)
				local violations = {}
				local damage = ctx.runtime.GetStarterDamage and ctx.runtime.GetStarterDamage()
				if damage and math.abs(damage - BASE_DAMAGE) > 1 then
					table.insert(violations, string.format(
						"Grundschaden eines Startspielers ist %d, erwartet %d", damage, BASE_DAMAGE))
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Weiche Aussagen -- beim Abgleich mitzulesen
		--------------------------------------------------------------------------
		{
			id = "village.target-feeling",
			intent = "WEICH: Der Einstieg soll nicht vermitteln 'ich berühre Häuser und sie "
				.. "explodieren', sondern 'selbst das einfachste Gebäude ist streng -- aber "
				.. "ich schaffe es'.\n"
				.. "Gleichzeitig sieht der Spieler Ziele, für die er offensichtlich noch "
				.. "nicht bereit ist. Die Chapel ist das äusserste Beispiel: 60 Schläge, "
				.. "und ein frischer Spieler erhält von ihren 150 Spirit-Energie nur rund "
				.. "27 Prozent, weil der Absorb-Wirkungsgrad an der Gebäudegrösse hängt. "
				.. "Sie schreckt also bereits ab -- der Spieler erfährt es bloss nirgends.",
		},

		{
			id = "village.jump-is-a-strategy",
			intent = "WEICH: Der Sprung ist eine vollwertige Zerstörungsstrategie, kein "
				.. "Missbrauch. 50 Schaden je Landung, alle 1,2 Sekunden, ohne "
				.. "Ressourcenkosten -- die Chapel fällt damit in rund 20 Landungen.\n"
				.. "Sein Ausgleich ist nicht Heat und nicht Combat Energy, sondern die "
				.. "Fehlbarkeit: eine verfehlte Landung kostet den Cooldown und bringt "
				.. "nichts, ein Schlag trifft immer. Seine Flächenwirkung ist abgeschwächt "
				.. "und hat einen kleinen Radius, damit der Flächenangriff seine Rolle "
				.. "behält.\n"
				.. "OFFENE WETTE: ob der Schlag dadurch zur Karteileiche wird. Er ist der "
				.. "Anker dieser Spec -- wird er nicht mehr benutzt, ist 'sechs Treffer' "
				.. "nur noch eine Rechengrösse. Der Playtest misst es.",
		},

		{
			id = "village.heat-is-the-throttle",
			intent = "WEICH: Ungefähr 3 Heat je normaler Aktion, 10 bis 15 je Special. Der "
				.. "passive Abbau läuft IMMER, nicht nur im Berserker-Zustand; die "
				.. "Absorb-Kühlung wirkt additiv je Gebäude, aber gedeckelt.\n"
				.. "Ziel ist ein steuerbarer Kreislauf: zerstören bis kurz unter die "
				.. "Überhitzung, im Berserker-Bereich bleiben, durch Absorbieren kühlen, "
				.. "weiter. Steuerbar wird das nur, wenn Handlungen verschieden heiss sind "
				.. "-- bei durchgehend gleichem Wert gäbe es nichts zu entscheiden, nur zu "
				.. "zählen.",
		},

		{
			id = "village.specials-cost-ten-actions",
			intent = "WEICH: Fokus und Flächenangriff kosten beide so viel Combat Energy "
				.. "wie zehn normale Kampfaktionen. Gleich teuer, damit die Wahl zwischen "
				.. "ihnen an der Zahl der Ziele hängt und nicht am Preis: bis zwei Ziele "
				.. "gewinnt der Fokus, ab vier die Fläche, bei drei sind sie gleichauf.\n"
				.. "Absorbieren steuert weiterhin Combat Energy bei, aber gedeckelt -- "
				.. "sonst finanziert Danebenstehen die Specials schneller als Kämpfen.",
		},

		{
			id = "village.absorbing-runs-alongside-fighting",
			intent = "WEICH: Absorbieren und Angreifen laufen gleichzeitig. Nur so gehen "
				.. "drei Zahlen dieser Spec zusammen auf: 88 Prozent tatsächlich erhaltene "
				.. "Energie, 20 Minuten Referenzzeit, viereinhalb Durchgänge.\n"
				.. "Dafür braucht das Absorbieren eine eigene Eingabe -- am PC eine Taste, "
				.. "die der kleine Finger hält, auf Handy und Gamepad ein eigener Knopf. "
				.. "Heute teilt es sich die Taste mit dem Schlag; gleichzeitig ist damit "
				.. "technisch unmöglich.",
		},

		{
			id = "village.training-has-no-wall",
			intent = "WEICH: Es gibt keine harte Obergrenze mehr beim Training. Die frühere "
				.. "Kappe wird zur BEZUGSGRÖSSE: bis zum eigenen Charakterlevel trainiert "
				.. "man schnell, eine Stufe darüber mühsam, zwei darüber praktisch "
				.. "vergeblich.\n"
				.. "Arm, Bein und Körper haben eigene Level auf derselben Skala wie das "
				.. "Charakterlevel -- steht überall dieselbe Zahl, ist man auf der Höhe der "
				.. "Zeit. Jede neue Stufe meldet sich.\n"
				.. "Oberhalb der Bezugsgrösse bleibt die Absorption gedeckelt (mehr als "
				.. "vorhanden gibt es nicht), der Sprungmultiplikator nicht.",
		},

		{
			id = "village.four-and-a-half-clears",
			intent = "WEICH: Der Referenzspieler räumt das Dorf rund viereinhalb Mal "
				.. "vollständig ab -- etwa 108 Zerstörungen bei 24 Gebäuden, ermöglicht "
				.. "durch den Respawn nach 30 Sekunden.\n"
				.. "Das ist gewollt, aber es ist die riskanteste Annahme dieser Spec. Ob "
				.. "es sich als Wiederholung anfühlt, hängt daran, ob sich zwischendurch "
				.. "genug ändert: Alarmstufe, Feuerwehr, eigene Stärke. Der Playtest muss "
				.. "messen, AB WANN es kippt -- nicht ob.",
		},

		{
			id = "village.rare-energy-excludes-radiation",
			intent = "WEICH: Das Dorf ist ein Heat-Biom. Geeignete Gebäude haben je Spawn "
				.. "eine kleine Gesamtchance auf einen anderen Typ; die Chapel ist "
				.. "ausgenommen und immer Spirit.\n"
				.. "Radiation bleibt aus diesem Überraschungssystem HERAUS -- es hat sein "
				.. "eigenes, separates Seltenheitssystem, und beides zusammenzulegen wäre "
				.. "der schnellste Weg, eine funktionierende Mechanik still zu verlieren.",
		},

		{
			id = "village.time-is-a-metric",
			intent = "WEICH: Rund 20 Minuten bis CITY BROKEN sind eine MESSGRÖSSE, keine "
				.. "Vorgabe. Nichts im Spiel richtet sich danach.\n"
				.. "Stimmt sie nicht, wird NICHT reflexhaft an Erfahrung oder Geld gedreht. "
				.. "Zuerst wird der Parameter gesucht, der das Erlebnis tatsächlich "
				.. "verursacht: Trefferzahlen, Angriffseffizienz, Alarmschwellen, "
				.. "Verteidigungsdauer oder Absorb-Verhalten.",
		},

		{
			id = "village.numbers-to-validate",
			intent = "WEICH: Drei Zahlen dieser Spec sind ausdrücklich Hypothesen und "
				.. "stehen beim ersten Playtest zur Prüfung:\n"
				.. "  * 225 Zerstörungswert bis Alarm 3 -- unterstellt, dass ein "
				.. "Referenzspieler rund 30 Prozent effizienter zerstört als mit blossen "
				.. "Schlägen.\n"
				.. "  * 6000 Coins für die Evolution.\n"
				.. "  * 88 Prozent tatsächlich erhaltene Energie.\n"
				.. "Dazu die Deckel für die Absorb-Kühlung und den Combat-Energy-Gewinn, "
				.. "die Form der Trainingskurve und die genauen Heat-Werte -- alle noch "
				.. "nicht festgelegt.",
		},

		{
			id = "village.telemetry-answers-the-questions",
			intent = "WEICH: Der Playtest zeichnet einen EREIGNISSTROM mit Zeitstempeln "
				.. "auf, keine Endwerte -- Heat-Verlauf, Specials pro Minute und "
				.. "Wiederholungsgefühl lassen sich aus Endwerten nicht rekonstruieren.\n"
				.. "Ein Lauf beginnt beim ersten Schaden und endet bei CITY BROKEN; die Uhr "
				.. "pausiert beim Rückzug ins Sanctuary.\n"
				.. "Über §22 hinaus mitzuschreiben: ob der Schlag überhaupt benutzt wird, "
				.. "wie weit über das eigene Level hinaus trainiert wird, und wie oft "
				.. "jemand in den Meltdown gerät.",
		},
	},
}
