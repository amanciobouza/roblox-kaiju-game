--============================================================
-- DURCHGANG-MESSUNG: was beim Spielen wirklich passiert
--
-- ===== Warum es das gibt =====
-- Der Gebaeudebericht zaehlt beim Serverstart, also eine unberuehrte Stadt. Er sagt, wie
-- viel Stadt DA ist -- nicht, wie lange sie haelt, wann die Eskalation kommt und wie oft
-- der Spieler dabei stirbt. Genau das sind aber die Fragen, an denen eine Balance haengt,
-- und bisher wurden sie aus Trefferzahlen HERGELEITET statt gemessen.
--
-- Diese Messung schreibt waehrend des Spielens mit. Sie ist reine Beobachtung: sie greift
-- nirgends ein, veraendert keinen Wert und kann nichts kaputtmachen ausser Zeilen im
-- Output.
--
-- ===== Was im Output erscheint =====
--   [Durchgang City] 00:47  Stufe 2  |  31 von 94 Teilen (33%)  |  18 900 Alarmpunkte
--   [Durchgang City] 01:00  Stand   |  38 von 94 (40%)  |  1 Tod  |  4 210 XP
--   [Durchgang City] 03:24  DURCHGANG VOLL  |  94 Teile  |  Dauer 3:24  |  2 Tode
--
-- Ein Lauf beginnt mit der ERSTEN Zerstoerung in einer Stadt und endet, wenn jedes
-- angreifbare Teil einmal gefallen ist -- oder wenn drei Minuten lang nichts mehr passiert.
-- Danach beginnt beim naechsten Treffer ein neuer Lauf. So misst ein Besuch einen
-- Durchgang, und zwei Besuche messen zwei.
--
-- Gezaehlt werden UNTERSCHIEDLICHE Teile. Wer ein Haus zerstoert, wartet bis es respawnt
-- und es nochmal umwirft, ist deshalb nicht schneller fertig.
--
-- ===== Abschalten =====
-- MESSUNG_AKTIV unten auf false setzen und Rojo synchronisieren lassen. Bewusst kein
-- Schalter im Debug-Panel: der braeuchte ein eigenes RemoteEvent, und das ist mehr Apparat
-- als die Sache wert -- konfiguriert wird in diesem Projekt ohnehin ueber Dateien.
--============================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local HOUSE_TAG = "KaijuHouse"

-- Alle 60 Sekunden eine Standszeile -- aber nur, wenn seither etwas zerstoert wurde.
-- Sonst schreibt eine Stadt, in der niemand ist, die ganze Nacht durch.
local STAND_INTERVALL = 60

-- Drei Minuten ohne Zerstoerung beenden den Lauf. Ohne das bliebe ein Lauf, den jemand
-- nach zwei Haeusern verlaesst, fuer immer offen und verfaelschte die naechste Messung.
local RUHE_ENDE = 180

local MESSUNG_AKTIV = true

if not MESSUNG_AKTIV then
	print("[Kaiju Debug] Durchgang-Messung ist abgeschaltet (MESSUNG_AKTIV = false).")
	return
end

local laeufe = {}

-- Seit Serverstart mitlaufende Summen. Ein Lauf merkt sich den Stand bei seinem Beginn und
-- bildet die Differenz -- das ist genauer, als am Ende die Spielerwerte abzufragen: XP
-- koennen beim Stufenaufstieg zurueckgesetzt werden, und wer mittendrin geht, nimmt seinen
-- Beitrag sonst mit.
local gesamtXp = 0
local gesamtMuenzen = 0
local gesamtTode = 0

local function zeit(sekunden)
	return string.format("%d:%02d", math.floor(sekunden / 60), math.floor(sekunden % 60))
end

-- Der Nenner: alle angreifbaren Teile dieser Stadt. Einmal je Lauf gezaehlt, denn
-- waehrend des Laufs aendert er sich nicht -- Gebaeude respawnen, sie verschwinden nicht.
local function teileDerStadt(stadt)
	local anzahl = 0
	for _, haus in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		if _G.ResolveCityName and _G.ResolveCityName(haus) == stadt then
			anzahl += 1
		end
	end
	return anzahl
end

local function schreibe(stadt, text)
	print(string.format("[Durchgang %s] %s", stadt, text))
end

local function bericht(stadt, lauf, ueberschrift)
	local dauer = os.clock() - lauf.start
	local anteil = lauf.gesamtTeile > 0 and (lauf.anzahl / lauf.gesamtTeile * 100) or 0
	schreibe(stadt, string.format(
		"%s  %s  |  %d von %d Teilen (%d%%)  |  %d Lebenspunkte  |  Dauer %s  |  %d Tode  |  %d XP  |  %d Muenzen",
		zeit(dauer), ueberschrift, lauf.anzahl, lauf.gesamtTeile, anteil, lauf.leben, zeit(dauer),
		gesamtTode - lauf.todeStart, gesamtXp - lauf.xpStart, gesamtMuenzen - lauf.muenzenStart))
end

local function beende(stadt, lauf, grund)
	bericht(stadt, lauf, grund)
	laeufe[stadt] = nil
end

-- Von HouseHandler bei jeder tatsaechlichen Zerstoerung gerufen.
_G.RecordDurchgangDestruction = function(haus)
	if not _G.ResolveCityName then
		return
	end
	local stadt = _G.ResolveCityName(haus)
	if not stadt then
		return
	end

	local lauf = laeufe[stadt]
	if not lauf then
		lauf = {
			start = os.clock(),
			zerstoert = {},
			anzahl = 0,
			leben = 0,
			gesamtTeile = teileDerStadt(stadt),
			stufe = _G.GetCityAlertLevel and _G.GetCityAlertLevel(stadt) or 1,
			letzterStand = os.clock(),
			standAnzahl = 0,
			letzteZerstoerung = os.clock(),
			xpStart = gesamtXp,
			muenzenStart = gesamtMuenzen,
			todeStart = gesamtTode,
		}
		laeufe[stadt] = lauf
		schreibe(stadt, string.format("0:00  Lauf beginnt  |  %d angreifbare Teile", lauf.gesamtTeile))
	end

	-- Dasselbe Teil zweimal zu faellen macht den Durchgang nicht voller.
	if lauf.zerstoert[haus] then
		lauf.letzteZerstoerung = os.clock()
		return
	end
	lauf.zerstoert[haus] = true
	lauf.anzahl += 1
	lauf.leben += haus:GetAttribute("MaxHealth") or 0
	lauf.letzteZerstoerung = os.clock()

	if lauf.gesamtTeile > 0 and lauf.anzahl >= lauf.gesamtTeile then
		beende(stadt, lauf, "DURCHGANG VOLL")
	end
end

-- ===== Spielerwerte mitzaehlen =====
-- Nur Zuwaechse. Ein Rueckgang (Stufenaufstieg setzt XP zurueck, Muenzen werden
-- ausgegeben) darf die Messung nicht ins Minus ziehen -- gemessen wird, was VERDIENT
-- wurde, nicht was am Ende uebrig ist.
local function beobachteWert(wert, zuweisen)
	if not wert then
		return
	end
	local vorher = wert.Value
	wert.Changed:Connect(function(neu)
		if neu > vorher then
			zuweisen(neu - vorher)
		end
		vorher = neu
	end)
end

local function beobachteSpieler(player)
	beobachteWert(player:WaitForChild("XP", 10), function(zuwachs)
		gesamtXp += zuwachs
	end)
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if leaderstats then
		beobachteWert(leaderstats:WaitForChild("Coins", 10), function(zuwachs)
			gesamtMuenzen += zuwachs
		end)
	end

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				gesamtTode += 1
			end)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(beobachteSpieler, player)
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(beobachteSpieler, player)
end)

-- ===== Die Schleife: Alarmstufen und Standszeilen =====
task.spawn(function()
	while true do
		task.wait(1)
		do
			local jetzt = os.clock()
			for stadt, lauf in pairs(laeufe) do
				-- Alarmstufe: der Sprung ist der interessante Augenblick, weil er sagt, wie
				-- viel Stadt es bis dahin gebraucht hat.
				local stufe = _G.GetCityAlertLevel and _G.GetCityAlertLevel(stadt) or lauf.stufe
				if stufe ~= lauf.stufe then
					local anteil = lauf.gesamtTeile > 0 and (lauf.anzahl / lauf.gesamtTeile * 100) or 0
					schreibe(stadt, string.format(
						"%s  Stufe %d  |  %d von %d Teilen (%d%%)  |  %d Alarmpunkte",
						zeit(jetzt - lauf.start), stufe, lauf.anzahl, lauf.gesamtTeile, anteil,
						_G.GetCityAlertProgress and _G.GetCityAlertProgress(stadt) or 0))
					lauf.stufe = stufe
				end

				if jetzt - lauf.letzteZerstoerung >= RUHE_ENDE then
					beende(stadt, lauf, "Lauf beendet (drei Minuten Ruhe)")
				elseif jetzt - lauf.letzterStand >= STAND_INTERVALL
					and lauf.anzahl > lauf.standAnzahl then
					local anteil = lauf.gesamtTeile > 0 and (lauf.anzahl / lauf.gesamtTeile * 100) or 0
					schreibe(stadt, string.format(
						"%s  Stand   |  %d von %d (%d%%)  |  %d Tode  |  %d XP",
						zeit(jetzt - lauf.start), lauf.anzahl, lauf.gesamtTeile, anteil,
						gesamtTode - lauf.todeStart, gesamtXp - lauf.xpStart))
					lauf.letzterStand = jetzt
					lauf.standAnzahl = lauf.anzahl
				end
			end
		end
	end
end)

print("[Kaiju Debug] Durchgang-Messung bereit. Abschalten mit _G.SetDurchgangMessung(false).")
