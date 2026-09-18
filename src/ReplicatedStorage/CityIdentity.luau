-- VERSION: 2026-09-13 #1
-- ModuleScript: CityIdentity
-- Ort in Studio: ReplicatedStorage
--
-- Wie eine Stadt dem Spieler gegenübertritt: ihr Name, ihre Stunde, ihr Kapitel.
--
-- ===== Innen und aussen sind getrennt =====
-- Die Schlüssel hier -- Village, SmallTown, City, LargeCity, MegaCity -- sind die INTERNEN
-- Namen und bleiben es. An ihnen hängen die Attribute im Workspace, die Werte in
-- CityAlertValues, die Statistik-Schlüssel, die Speicherstände und die Modellordner in
-- ServerStorage. Sie umzubenennen hiesse, all das gleichzeitig anzufassen, und ein
-- Speicherstand, der auf einen alten Schlüssel zeigt, wäre still verloren.
--
-- Was der Spieler LIEST, steht daneben und ist frei änderbar. Deshalb diese Datei.
--
-- ===== Warum zentral =====
-- Die Anzeigenamen standen zweimal da: einmal im Alarm-HUD, einmal in der Alarm-Ansage.
-- Zwei Kopien derselben Liste laufen genau dann auseinander, wenn jemand nur eine davon
-- findet -- und beim Umbenennen aller fünf Städte wäre das sicher passiert.
--
-- ===== Die Stunde =====
-- Jede Stadt hat eine Uhrzeit, und die Uhrzeit ist das Koordinatensystem der Welt: es sind
-- dieselben Indizes wie auf dem Zifferblatt im Sanctuary, wo jede Stunde eine Portalbucht
-- ist (siehe SanctuaryDialClient). Wer "04:00" liest, weiss danach, wo Brasshaven liegt --
-- das leistet kein Stadtname.
--
-- ===== Die Kapitel =====
-- Die fünf Städte sind zugleich die fünf Kapitel, und ein Kapitel gehört ALLEN drei
-- Figuren: eine gemeinsame Herausforderung, auf die Power, Control und Purpose
-- verschieden antworten.
--
-- ACHTUNG: Die Kapitelfelder liest heute noch nichts. Sie stehen hier, weil sie zur
-- Identität der Stadt gehören und nicht in einer zweiten Liste landen sollen -- wo sie im
-- Spiel auftauchen, ist noch nicht entschieden.

local CityIdentity = {}

-- [interner Name] = wie die Stadt dem Spieler erscheint.
--   display       Anzeigename
--   hour          Position auf dem Zifferblatt
--   chapter       Kapitelnummer als römische Ziffer, wie in den Titelkarten des Prologs
--   chapterTitle  Kapitelname
--   character     Charakter der Stadt -- Notiz für den Bau, keine Anzeige
CityIdentity.Cities = {
	Village = {
		display = "Dawnhollow",
		hour = "02:00",
		chapter = "I",
		chapterTitle = "The Awakening", -- Das Erwachen
		character = "Kleine Siedlung in einem geschützten Tal. Hier beginnt etwas, das "
			.. "niemand versteht.",
	},
	SmallTown = {
		display = "Brasshaven",
		hour = "04:00",
		chapter = "II",
		chapterTitle = "The Rising", -- Der Aufstieg
		character = "Industrielle Kleinstadt mit Messing, Werkstätten und alten Uhrtürmen.",
	},
	City = {
		display = "Meridian",
		hour = "06:00",
		chapter = "III",
		chapterTitle = "The Reckoning", -- Die Bewährungsprobe
		character = "Moderne Stadt, deren klare Achsen und zentraler Turm an ein Zifferblatt "
			.. "erinnern.",
	},
	LargeCity = {
		display = "Ironspire",
		hour = "08:00",
		chapter = "IV",
		chapterTitle = "The Breaking Point", -- Der Wendepunkt
		character = "Dichte Grossstadt mit gewaltigen Türmen, Stahl und schwerer Verteidigung.",
	},
	MegaCity = {
		display = "Aeon Prime",
		hour = "10:00",
		chapter = "V",
		chapterTitle = "The Eternal Hour", -- Die ewige Stunde
		character = "Monumentale Megacity -- das Herz einer Zivilisation, die ihre Zeit für "
			.. "unbegrenzt hielt.",
	},
	-- Die Stadt, die im Prolog fällt. Sie steht ausserhalb der Reihe, und zwar in beidem:
	--
	-- Keine STUNDE -- sie liegt nicht auf dem Zifferblatt im Sanctuary. Dort tragen nur die
	-- fünf spielbaren Städte eine Portalbucht (siehe SanctuaryDialClient); eine Stunde für
	-- den Prolog verspräche ein Portal, das es nicht gibt.
	--
	-- Kein KAPITEL -- der Prolog kommt vor Kapitel I. Ihm eine Nummer zu geben hiesse, die
	-- Zählung der fünf Kapitel zu verschieben.
	PrologueCity = {
		display = "Firstlight City",
		character = "Die Stadt des Prologs -- das erste Licht, und der erste Fall. Sie geht "
			.. "unter, bevor die Reihe beginnt.",
	},
}

-- Alles, was über eine Stadt bekannt ist -- oder nil, wenn sie hier nicht geführt wird.
function CityIdentity.Get(internalName)
	return internalName and CityIdentity.Cities[internalName] or nil
end

-- Der Name für die Anzeige. Fällt auf den internen Namen zurück, statt leer zu bleiben:
-- eine Stadt ohne Eintrag soll erkennbar sein, nicht unsichtbar.
function CityIdentity.DisplayName(internalName)
	local entry = CityIdentity.Get(internalName)
	return (entry and entry.display) or internalName or ""
end

-- Die Stunde auf dem Zifferblatt. Leer, wenn die Stadt keine hat -- Firstlight City liegt
-- nicht darauf.
function CityIdentity.Hour(internalName)
	local entry = CityIdentity.Get(internalName)
	return (entry and entry.hour) or ""
end

return CityIdentity
