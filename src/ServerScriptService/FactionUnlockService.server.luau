-- ServerScript: FactionUnlockService
-- Ort in Studio: ServerScriptService
--
-- Prüft die Freischalt-Bedingungen für Jaeger/Ronin (Kaiju ist von Anfang an frei) und
-- liefert dem Client die Bedingung fürs Fraktions-Panel.
--
-- Eine Fraktion wird freigeschaltet, indem man das VORHERIGE Kapitel abschliesst: Jaeger
-- durch den Sieg über den MegaCity-Guardian mit Kaiju, Ronin durch denselben Sieg mit
-- Jaeger. Ronin ist damit vorerst unerreichbar, solange Jaeger kein eigenes Moveset hat --
-- das ist bewusst so und keine Luecke.
--
-- WICHTIG: Blockiert NICHT die eigentliche Fraktions-AUSWAHL selbst (das bleibt weiterhin
-- über SelectFactionEvent in EnergyTypesHandler.lua möglich -- Spieler dürfen ihre
-- Wunsch-Fraktion schon vorab markieren) -- sondern nur, ob "Faction" (die tatsächlich
-- AKTIVE, spielbare Fraktion) darauf wechseln darf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Die Kapitel bauen aufeinander auf: eine Fraktion verdient man sich, indem man die
-- vorherige zu Ende spielt. Genau ein Ereignis entscheidet, kein Sammeln.
--
-- Vorher standen hier drei UND-verknuepfte Kriterien je Fraktion -- Level-Schwelle,
-- Lifetime-Energie einer Sorte und ein Meilenstein-Zaehler. Die hatten mit den Kapiteln
-- nichts zu tun: beide Fraktionen waren unabhaengig voneinander freischaltbar, beide
-- Meilensteine waren Kaiju-Aktionen, und der Guardian kam ueberhaupt nicht vor. Faktisch
-- war es Grinding. Ein zweiter Weg bleibt bewusst NICHT bestehen -- er wuerde genau das
-- aushebeln, was die Regel aussagt.
local FACTION_REQUIREMENTS = {
	Jaeger = {
		requiredFaction = "Kaiju",
		label = "Defeat the MegaCity Guardian as Kaiju",
	},
	Ronin = {
		requiredFaction = "Jaeger",
		label = "Defeat the MegaCity Guardian as Jaeger",
	},
}

-- Gibt für eine Fraktion zurück: ist sie freigeschaltet (bool), plus die Bedingung für die
-- Anzeige im Fraktions-Panel. Das ist jetzt EIN Kriterium statt dreier -- ein einzelnes
-- Ereignis hat keinen Fortschritt, den man als Balken zeigen koennte.
local function getFactionUnlockStatus(player, factionName)
	if factionName == "Kaiju" then
		return true, nil -- von Anfang an frei, kein Fortschritt nötig
	end

	local requirements = FACTION_REQUIREMENTS[factionName]
	if not requirements then
		return false, nil
	end

	-- Gezaehlt wird in CityDefenderService beim toedlichen Treffer am MegaCity-Guardian,
	-- und zwar je Fraktion. Im Mehrspielerbetrieb zaehlt ausdruecklich nur der LETZTE
	-- Schlag, nicht die Beteiligung -- dieselbe Regel wie bei den Kapiteln.
	local completions = player:GetAttribute("Stat_ChaptersCompleted." .. requirements.requiredFaction) or 0
	local done = completions >= 1

	return done, {
		condition = {
			label = requirements.label,
			requiredFaction = requirements.requiredFaction,
			done = done,
		},
	}
end
_G.GetFactionUnlockStatus = getFactionUnlockStatus

-- ===== RemoteFunction: Client fragt den Fortschritt für ALLE Fraktionen gleichzeitig ab
-- (fürs Fraktions-Panel) =====
local GetFactionProgressFunction = Instance.new("RemoteFunction")
GetFactionProgressFunction.Name = "GetFactionProgressFunction"
GetFactionProgressFunction.Parent = ReplicatedStorage

GetFactionProgressFunction.OnServerInvoke = function(player)
	local result = {}
	for _, factionName in ipairs({ "Kaiju", "Jaeger", "Ronin" }) do
		local unlocked, progress = getFactionUnlockStatus(player, factionName)
		result[factionName] = { unlocked = unlocked, progress = progress }
	end
	return result
end

-- ===== Freischaltung tatsächlich DURCHSETZEN =====
-- Sobald Jaeger/Ronin ein eigenes Moveset bekommen und "Faction" für sie umgestellt
-- werden soll (aktuell macht EnergyTypesHandler.lua das nur für Kaiju), muss der DANN
-- geschriebene Aktivierungs-Code VORHER _G.GetFactionUnlockStatus(player, factionName)
-- prüfen -- dieser Dienst stellt dafür schon die zentrale, wiederverwendbare Prüf-
-- Funktion bereit, damit an dieser Stelle später nichts dupliziert werden muss.