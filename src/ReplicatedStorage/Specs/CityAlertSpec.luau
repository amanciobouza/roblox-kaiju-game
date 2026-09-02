-- ModuleScript: CityAlertSpec
--
-- Spezifikation der Alarmstufen-Leiter: was jede Stufe BEWIRKEN soll und welche Regeln
-- sich daraus prüfen lassen. Diese Datei ist die Quelle der Wahrheit für die Absicht --
-- die Tabelle, die früher in CLAUDE.md stand, steht jetzt hier bei den Regeln, die sie
-- durchsetzen.
--
-- WICHTIG: dieses Modul importiert NICHTS. Alles kommt über den ctx herein (siehe
-- SpecRunner). Nur so läuft dieselbe Datei in Studio und im kopflosen Prüfer.
--
-- Regelaufbau:
--   id              eindeutiger Bezeichner, taucht in der Ausgabe auf
--   intent          wofür die Stufe da ist -- die Absicht, nicht die Mechanik
--   check           optional. Gibt eine LISTE von Verstössen zurück (leer = in Ordnung).
--                   Fehlt sie, ist es eine weiche Aussage: nicht maschinell prüfbar,
--                   sondern beim Abgleich mitzulesen.
--   knownViolations optional. Heute bekannte Abweichungen, als PRÄFIX des Verstosstextes.
--                   Sie halten den Rückstand sichtbar, ohne das Signal zu ersticken --
--                   nur ein NEUER Verstoss ist eine Regression.
--   needsRuntime    Regel braucht laufenden Zustand -- läuft nur beim manuellen Nachprüfen
--   needsWorkspace  Regel braucht den Workspace -- läuft nicht im kopflosen Prüfer

-- Liefert alle zu prüfenden Stadt-Konfigurationen.
--
-- DefaultCity kommt mit: GetCityConfig() gibt sie für jede unbekannte Stadt zurück
-- ("return CityAlertConfig.Cities[cityName] or CityAlertConfig.DefaultCity"), sie ist
-- also eine echte, erreichbare Konfiguration -- und unterliegt denselben Regeln.
-- Die HÖCHSTE Stufe, die eine Stadt über alle Kapitel hinweg je erreichen kann.
-- MaxAlertLevel allein genügt seit der kapitelabhängigen Eskalation nicht mehr: es nennt
-- nur Kapitel I. Eine Stadt, die erst in Kapitel III Stufe 5 sieht, braucht die Schwelle
-- und den Guardian trotzdem -- die Regeln prüfen deshalb gegen das Maximum, sonst winken
-- sie eine Lücke durch, die erst im späteren Kapitel aufschlägt.
local function maxLevelOf(city)
	local highest = city.data.MaxAlertLevel or 0
	local byChapter = city.data.MaxAlertLevelByChapter
	if type(byChapter) == "table" then
		for _, level in ipairs(byChapter) do
			if type(level) == "number" and level > highest then
				highest = level
			end
		end
	end
	return highest
end

local function citiesOf(ctx)
	local config = ctx.config.CityAlert
	local list = {}
	for _, name in ipairs(config.CityOrder) do
		local city = config.Cities and config.Cities[name]
		if type(city) == "table" then
			table.insert(list, { name = name, data = city })
		else
			table.insert(list, { name = name, data = {}, missing = true })
		end
	end
	if type(config.DefaultCity) == "table" then
		table.insert(list, { name = "DefaultCity", data = config.DefaultCity })
	end
	return list
end

return {
	System = "CityAlert",

	Rules = {
		--------------------------------------------------------------------------
		-- Stufe 1
		--------------------------------------------------------------------------
		{
			id = "alert.level1.observation-only",
			intent = "Stufe 1 zeigt dem Spieler, dass die Stadt ihn beobachtet -- ein "
				.. "kreisender Traffic-Helikopter. Sie darf ihn NICHT bedrohen: keine Waffen, "
				.. "kein Schaden, kein Ertragsverlust. Wird das verletzt, verliert die Leiter "
				.. "ihren ruhigen Anfang.",
		},

		--------------------------------------------------------------------------
		-- Stufe 2
		--------------------------------------------------------------------------
		{
			id = "alert.level2.firefighting-configured",
			intent = "Stufe 2 ist der erste spürbare Verlust: die Feuerwehr löscht brennende "
				.. "Gebäude, gelöschte geben weniger Energie. Jede Stadt braucht dafür "
				.. "vollständige Feuerwehrwerte, sonst eskaliert sie in eine wirkungslose Stufe.",
			check = function(ctx)
				local violations = {}
				for _, city in ipairs(citiesOf(ctx)) do
					if maxLevelOf(city) >= 2 then
						for _, field in ipairs({ "FireEngineHP", "FireEngineCount", "FirefightingRate" }) do
							if city.data[field] == nil then
								table.insert(violations, city.name .. ": Stufe 2 erreichbar, aber " .. field .. " fehlt")
							end
						end
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Stufe 3
		--------------------------------------------------------------------------
		{
			id = "alert.level3.barricades-configured",
			intent = "Stufe 3 schützt nahe Gebäude mit Barrikaden, die schwer zu besiegen sind. "
				.. "Zweck ist räumliche Umlenkung -- der Spieler soll auf andere Gebäude "
				.. "ausweichen, nicht sich festbeissen.",
			check = function(ctx)
				local violations = {}
				for _, city in ipairs(citiesOf(ctx)) do
					if maxLevelOf(city) >= 3 then
						for _, field in ipairs({ "ShieldMaxHealth", "GeneratorMaxHealth" }) do
							if city.data[field] == nil then
								table.insert(violations, city.name .. ": Stufe 3 erreichbar, aber " .. field .. " fehlt")
							end
						end
					end
				end
				return violations
			end,
		},
		{
			id = "alert.level3.redirects-spatially",
			intent = "WEICH: Barrikaden sollen den Spieler räumlich UMLENKEN, nicht nur seinen "
				.. "Schaden abfangen. Wenn er sich stattdessen durch die Barrikade beisst und "
				.. "danach weitermacht wie vorher, verfehlt die Stufe ihren Zweck -- dann sind "
				.. "die Barrikaden zu schwach oder decken zu wenig ab.",
		},

		--------------------------------------------------------------------------
		-- Stufe 4
		--------------------------------------------------------------------------
		{
			id = "alert.level4.military-configured",
			intent = "Stufe 4 ist die erste echte Gefahr: Militär greift an, der Spieler muss "
				.. "fliehen oder systematisch dezimieren. Ohne vollständige Einheitenwerte "
				.. "greift niemand an.",
			check = function(ctx)
				local violations = {}
				for _, city in ipairs(citiesOf(ctx)) do
					if maxLevelOf(city) >= 4 then
						for _, field in ipairs({ "TankHP", "MilitaryTankCount", "RocketLauncherHP", "HelicopterHP" }) do
							if city.data[field] == nil then
								table.insert(violations, city.name .. ": Stufe 4 erreichbar, aber " .. field .. " fehlt")
							end
						end
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Stufe 5
		--------------------------------------------------------------------------
		{
			id = "alert.level5.guardian-configured",
			intent = "Stufe 5 ist der City Defender. Eine Stadt, die Stufe 5 erreichen kann, "
				.. "MUSS ihn haben -- sonst eskaliert sie in eine Stufe, in der nichts "
				.. "passiert ausser einer Warnung im Log.",
			-- Ehemals bekannte Abweichungen (LargeCity, MegaCity, DefaultCity) sind
			-- behoben, ebenso die von Village und SmallTown, die mit der
			-- kapitelabhaengigen Eskalation dazukamen. Bewusst KEIN knownViolations mehr:
			-- der Eintrag wuerde einen kuenftigen echten Verstoss stillschweigend
			-- durchwinken.
			check = function(ctx)
				local violations = {}
				for _, city in ipairs(citiesOf(ctx)) do
					if maxLevelOf(city) >= 5 then
						for _, field in ipairs({ "GuardianHP", "GuardianShieldHP", "GuardianMoveSpeed" }) do
							if city.data[field] == nil then
								table.insert(violations, city.name .. ": Stufe 5 erreichbar, aber " .. field .. " fehlt")
							end
						end
					end
				end
				return violations
			end,
		},
		{
			id = "alert.level5.is-the-test-before-the-payoff",
			intent = "WEICH: Stufe 5 ist die PRÜFUNG vor der Belohnung, nicht das Ende der "
				.. "Leiter. Wer alle Aufgaben der Stadt erfüllt -- zuletzt den Guardian --, "
				.. "löst CITY BROKEN aus: 75 Sekunden freie Zerstörung ohne Eskalation, "
				.. "danach fällt der Alarm auf 0 und der Kreislauf beginnt von vorn. "
				.. "Der Druck auf Stufe 5 kommt aus der GEFAHR, nicht aus dem Ertrag. "
				.. "Belohnungen fliessen bewusst weiter.\n"
				.. "KORRIGIERT am 01.09.2026: Diese Stufe war früher als 'drängt den Spieler "
				.. "aus der Stadt -- keine Belohnungen mehr' beschrieben. Das stammt aus "
				.. "einer Zeit, in der Stufe 5 der Endzustand war; CITY BROKEN ist laut "
				.. "eigenem Kopfkommentar der 'vierte und letzte Baustein' und kam später "
				.. "dazu. Eine Belohnungssperre wäre heute schädlich: sie bestraft kurz vor "
				.. "der Auszahlung, macht das Vermeiden von Stufe 5 zur vernünftigen "
				.. "Spielweise -- und damit den ganzen Bosskampf zu etwas, das man umgeht.",
		},
		{
			id = "alert.level5.guardian-animation-is-provisional",
			intent = "WEICH und VORLÄUFIG: Die Guardian-Animation läuft zunächst "
				.. "CLIENTSEITIG -- ein LocalScript registriert die KeyframeSequence aus "
				.. "GuardianAnimationLibrary.BuildIdle() und spielt sie über den Animator "
				.. "des gerigten Modells ab. "
				.. "Das ist ausdrücklich ein Zwischenstand, kein Endzustand. Der Guardian "
				.. "gehört dem SERVER; clientseitig registrierte Sequenzen replizieren "
				.. "nicht, zwei Spieler sehen ihn also in unterschiedlicher Phase des "
				.. "Zyklus. Bewusst in Kauf genommen, solange die Wardens noch gebaut "
				.. "werden -- clientseitig lässt sich ohne Upload iterieren. "
				.. "SPÄTER: Animation hochladen, Asset-ID wie SkinsConfig.AttackAnimationId "
				.. "an einen benannten Ort legen, Server abspielen lassen. Beide Wege enden "
				.. "bei Animator:LoadAnimation -- es unterscheidet sich nur, woher die ID "
				.. "kommt und wer abspielt.",
		},
		{
			id = "alert.level5.has-protected-buildings",
			intent = "Der Guardian stellt sich vor wichtige Gebäude, markiert per "
				.. "'GuardianProtect'-Tag. JEDE Stadt mit Guardian braucht mindestens eines. "
				.. "Ohne Markierung greift ein Rückfall, der EIN einziges Gebäude wählt (das "
				.. "mit der höchsten MaxHealth) -- der Guardian bewacht dann eine Ecke der "
				.. "Stadt statt sie zu verteidigen. Seit der Spawn-Punkt ersatzweise aus "
				.. "diesem Gebäude abgeleitet wird (für Städte ohne 'GuardianSpawn'-Part), "
				.. "entscheidet die Markierung zusätzlich darüber, WO der Guardian erscheint.",
			needsWorkspace = true,
			-- Geprüft wird JE STADT. Die frühere Fassung fragte nur, ob IRGENDWO auf der
			-- Welt etwas markiert ist -- das sagt nichts darüber, ob diese eine Stadt
			-- versorgt ist, und hätte eine vergessene Stadt durchgewinkt.
			check = function(ctx)
				local violations = {}
				local byCity = ctx.workspace.CountTaggedByCity and ctx.workspace.CountTaggedByCity("GuardianProtect")
				if not byCity then
					return { "CountTaggedByCity fehlt im Prüfer-Kontext -- Regel nicht auswertbar" }
				end
				for _, city in ipairs(citiesOf(ctx)) do
					if maxLevelOf(city) >= 5 and city.data.GuardianHP then
						if (byCity[city.name] or 0) == 0 then
							table.insert(
								violations,
								city.name .. ": kein Gebäude mit 'GuardianProtect' getaggt -- Guardian nutzt den Ein-Gebäude-Rückfall"
							)
						end
					end
				end
				return violations
			end,
		},

		--------------------------------------------------------------------------
		-- Leiter als Ganzes
		--------------------------------------------------------------------------
		{
			id = "alert.thresholds.complete",
			intent = "Zu jeder erreichbaren Stufe gehört eine Schwelle, ab der sie greift. "
				.. "Fehlt sie, ist die Stufe unerreichbar und MaxAlertLevel eine Lüge.",
			-- Ehemals bekannte Abweichungen behoben -- siehe oben, kein knownViolations.
			check = function(ctx)
				local violations = {}
				for _, city in ipairs(citiesOf(ctx)) do
					local maxLevel = maxLevelOf(city)
					for level = 2, maxLevel do
						if city.data["AlertThresholdLevel" .. level] == nil then
							table.insert(
								violations,
								city.name .. ": MaxAlertLevel=" .. maxLevel .. ", aber AlertThresholdLevel" .. level .. " fehlt"
							)
						end
					end
				end
				return violations
			end,
		},
		{
			id = "alert.thresholds.ascending",
			intent = "Die Schwellen müssen mit der Stufe steigen. Eine niedrigere Schwelle für "
				.. "eine höhere Stufe würde zwei Stufen gleichzeitig auslösen und die "
				.. "Eskalation überspringen.",
			check = function(ctx)
				local violations = {}
				for _, city in ipairs(citiesOf(ctx)) do
					local previous, previousLevel = nil, nil
					for level = 2, maxLevelOf(city) do
						local threshold = city.data["AlertThresholdLevel" .. level]
						if threshold then
							if previous and threshold <= previous then
								table.insert(
									violations,
									city.name
										.. ": AlertThresholdLevel"
										.. level
										.. " ("
										.. threshold
										.. ") ist nicht grösser als Level"
										.. previousLevel
										.. " ("
										.. previous
										.. ")"
								)
							end
							previous, previousLevel = threshold, level
						end
					end
				end
				return violations
			end,
		},
	},
}
