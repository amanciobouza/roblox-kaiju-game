-- Script: ChapterFinaleService
-- Ort in Studio: ServerScriptService
--
-- Das Finale eines Kapitels: der Augenblick, in dem die Geschichte das Spiel kurz
-- uebernimmt. Fuer Kapitel I ist das "POWER" -- der letzte Guardian faellt in Mega City,
-- und statt der Belohnung kommt die Falle.
--
-- ===== Wann es laeuft =====
-- Genau dann, wenn eine Stadt ihre hoechste Alarmstufe erreicht und ALLE ihre Aufgaben
-- erledigt sind -- also im selben Augenblick, in dem sonst CITY BROKEN beginnt. Und nur
-- beim ERSTEN Mal: danach ist das Kapitel abgeschlossen, und die Stadt verhaelt sich
-- wieder wie jede andere.
--
-- Das ist die ausdrueckliche Entscheidung (04.10.2026): "Beim ersten Mal das Finale
-- spielen. Danach wieder normal City Broken."
--
-- ===== Warum es ein eigener Dienst ist =====
-- CityBrokenService beantwortet eine Frage ueber eine STADT ("sind alle Aufgaben
-- erledigt?"). Ob ein Finale faellig ist, ist eine Frage ueber einen SPIELER ("hat er
-- dieses Kapitel schon abgeschlossen?"). Beides in einem Dienst zu fuehren, hiesse zwei
-- Begriffe von "fertig" in derselben Datei -- und der erste Fehler waere, den falschen zu
-- pruefen.
--
-- ===== Stand =====
-- Hier steht heute das GERUEST: Ausloeser, Zustaendigkeit, Abschluss. Die Inszenierung
-- selbst -- Falle, Jaeger, Niederlage, Textkarten, der Blick des Jaegers in die Kamera --
-- kommt als eigener Schritt. Bis dahin meldet der Dienst, was er tun WUERDE, und schliesst
-- das Kapitel trotzdem ab: so laesst sich der Ausloeser pruefen, ohne auf die Szene zu
-- warten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Mit Zeitgrenze und mit Behandlung des Fehlerfalls: fehlt eines der beiden, haengt der
-- Dienst sonst stumm, und das Finale bliebe beim Spielen einfach aus -- ohne Hinweis.
local function holen(eltern, name)
	local modul = eltern:WaitForChild(name, 10)
	if not modul then
		error(string.format("ChapterFinaleService: %q liegt nicht in %s. Hat Rojo synchronisiert?",
			name, eltern:GetFullName()), 0)
	end
	return require(modul)
end

local RemoteEventUtils = holen(ReplicatedStorage, "RemoteEventUtils")
local StoryBeatService = holen(ServerScriptService, "StoryBeatService")

-- Wiederverwendet aus dem Prolog. Die Namen tragen "Prologue", die Funktion ist aber
-- allgemein: Filmstreifen an, HUD aus; und eine Kamera, die einen Punkt umrundet und
-- danach auf den Spieler schwenkt. Zwei zweite Fassungen davon waeren zwei Orte, an denen
-- dasselbe kaputtgehen kann.
local SetPrologueLetterboxEvent = RemoteEventUtils.GetOrCreate("SetPrologueLetterboxEvent")
local TrenchOrbitCameraEvent = RemoteEventUtils.GetOrCreate("TrenchOrbitCameraEvent")
local RestorePrologueCameraEvent = RemoteEventUtils.GetOrCreate("RestorePrologueCameraEvent")

-- ===== Die drei Toene der Szene =====
-- Eine leere Zeichenkette hiesse "Schritt ueberspringen" -- so lief die Sequenz, solange
-- die Nummern fehlten. Eine ERFUNDENE Nummer waere dagegen schlimmer als Stille gewesen:
-- sie erzeugt bei jedem Durchlauf ein "Failed to load sound" und verdeckt die Tonfehler,
-- die echt sind.
--
-- Die Zeitabstaende zwischen den Toenen (siehe spieleSignal, spieleFalle, spieleRueckkehr)
-- sind auf KURZE Toene gerechnet. Was die drei wirklich dauern, sagt beim ersten Lauf die
-- Zeile "[Kaiju Debug] StoryBeat-Ton ...: Laenge x.xx s" -- passt es nicht, gehoeren die
-- Wartezeiten angepasst und nicht die Toene.
local TON_BEEP = "rbxassetid://9125937249" -- Signal des Guardians, zweimal
local TON_THOOM = "rbxassetid://123087173903285" -- die erwachenden Tuerme, dreimal
local TON_HERZSCHLAG = "rbxassetid://9116795681" -- Rueckkehr ins Sanctuary, zweimal

-- Welche Stadt welches Kapitel beendet. Mehr als ein Eintrag wird es erst geben, wenn
-- Kapitel II sein eigenes Finale bekommt -- die Form steht schon dafuer bereit.
local FINALE_JE_STADT = {
	MegaCity = {
		Kapitel = "Kaiju",
		Titel = "CHAPTER I — POWER",
	},
}

-- Die fuenf Guardian-Modelle vertreten die fuenf Jaeger, die den Kaiju stellen. Als
-- Jaeger, den man am Ende einzeln sieht, dient der fuenfte -- der groesste.
--
-- Entscheidung vom 04.10.2026: "Die 5 Guardians sind die 5 Jaeger, die den Kaiju-Spieler
-- angreifen", und "als Jaeger-Ersatz verwende aktuell den Guardian Nummer 5". Eigene
-- Jaeger-Modelle gibt es noch nicht; der Fraktionsbildschirm zeigt dort bis heute ein
-- Fragezeichen.
local JAEGER_MODELLE = {
	"Warden_I_Shepherd_GoldenMaster",
	"Marshal_II_Roadblock_GoldenMaster",
	"Aegis_III_Interceptor_GoldenMaster",
	"Bastion_IV_Colossus_GoldenMaster",
	"Sovereign_V_Apex_GoldenMaster",
}
local JAEGER_HAUPTFIGUR = JAEGER_MODELLE[5]

-- Laeuft das Finale gerade? Ein zweiter Durchlauf waehrend des ersten waere das Ende jeder
-- Inszenierung -- zwei Kameraskripte um dieselbe Kamera, genau die Sorte Fehler, vor der
-- CLAUDE.md warnt.
local laeuft = {}

------------------------------------------------------------
-- Bausteine
------------------------------------------------------------

-- Ein Tonschritt, aber nur wenn es den Ton gibt. Siehe die leeren Konstanten oben.
local function ton(soundId, lautstaerke)
	if soundId == "" then
		return nil
	end
	return { type = "sound", soundId = soundId, volume = lautstaerke or 0.8 }
end

-- Haengt nur an, was wirklich da ist -- so koennen fehlende Toene die Reihenfolge der
-- Schritte nicht durcheinanderbringen.
local function haenge(schritte, ...)
	for _, schritt in ipairs({ ... }) do
		if schritt then
			table.insert(schritte, schritt)
		end
	end
end

local function sperreSteuerung(player, gesperrt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if gesperrt then
		-- Die Ausgangswerte am SPIELER merken, nicht in einer lokalen Tabelle: stirbt der
		-- Charakter mitten in der Szene, waere die Tabelle an einer Leiche festgemacht.
		player:SetAttribute("FinaleWalkSpeed", humanoid.WalkSpeed)
		player:SetAttribute("FinaleJumpPower", humanoid.JumpPower)
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	else
		humanoid.WalkSpeed = player:GetAttribute("FinaleWalkSpeed") or 16
		humanoid.JumpPower = player:GetAttribute("FinaleJumpPower") or 50
		player:SetAttribute("FinaleWalkSpeed", nil)
		player:SetAttribute("FinaleJumpPower", nil)
	end
end

------------------------------------------------------------
-- Die Inszenierung
------------------------------------------------------------

-- 1. SILENCE -- keine Siegesmusik. Die Kamera umrundet den Kaiju, vor ihm kniet der
-- Guardian. Das Schweigen ist der Inhalt dieser Szene: der Spieler hat gewonnen, und es
-- fuehlt sich nicht nach Sieg an.
local function spieleStille(player)
	StoryBeatService.FadeOutAllSound(player, 1.5)

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local ok, groesse = pcall(function()
		local _, size = character:GetBoundingBox()
		return size
	end)
	local hoehe = (ok and groesse and groesse.Y) or 30

	TrenchOrbitCameraEvent:FireClient(player, {
		center = rootPart.Position,
		-- Abstand und Hoehe wachsen mit der Figur: in Mega City steht hier ein Kaiju von
		-- gut neunzig Studs, und eine feste Zahl haette ihn entweder angeschnitten oder
		-- zum Punkt gemacht.
		radius = hoehe * 2.2,
		height = hoehe * 0.9,
		orbitDuration = 7,
		playerFocusPosition = rootPart.Position,
	})
	task.wait(7)
end

-- 2. BEEP -- ein Licht im Kopf des Guardians. Er hebt den Kopf, nicht zum Kaiju, sondern
-- zum Himmel. Ein Signal schiesst nach oben.
local function spieleSignal(player)
	local schritte = {}
	haenge(schritte, ton(TON_BEEP, 0.6), { type = "wait", duration = 1.2 })
	haenge(schritte, ton(TON_BEEP, 0.8), { type = "wait", duration = 0.8 })
	StoryBeatService.Play(player, { steps = schritte, keepBlackScreen = false })
end

-- 3. THE TRAP -- ueber Mega City erwachen Systeme. Tuerme, Barrieren, Hangartore.
-- Auf dem HUD erscheinen zuerst Zeichen, dann Saetze.
local function spieleFalle(player)
	local schritte = {}
	haenge(schritte,
		ton(TON_THOOM, 0.9), { type = "wait", duration = 0.5 },
		ton(TON_THOOM, 0.9), { type = "wait", duration = 0.4 },
		ton(TON_THOOM, 0.9), { type = "wait", duration = 0.3 },
		{ type = "text", text = "CONTAINMENT PROTOCOL COMPLETE.", duration = 2.2 },
		{ type = "text", text = "KAIJU THREAT: ANALYZED.", duration = 2.2 }
	)
	StoryBeatService.Play(player, { steps = schritte, keepBlackScreen = false })
end

-- 4. POWER FAILS -- der Kaiju faellt. Die Aussage des Kapitels, zweizeilig und
-- zeitversetzt: die zweite Zeile kommt erst, wenn die erste gewirkt hat.
local function spieleNiederlage(player)
	StoryBeatService.Play(player, {
		steps = {
			{ type = "fadeIn", duration = 1.5 }, -- Bildschirm wird SCHWARZ
			{ type = "wait", duration = 1.0 },
			{
				type = "text",
				text = "POWER WITHOUT CONTROL\nIS PREDICTABLE.",
				duration = 4.5,
				lineDelay = 1.8,
			},
		},
		keepBlackScreen = true,
	})
end

-- 5. THE OTHER SIDE -- Dunkelheit, dann bootet etwas. Es ist nicht das Kaiju-HUD.
local function spieleAufwachen(player)
	StoryBeatService.Play(player, {
		steps = {
			{ type = "wait", duration = 2.0 },
			{ type = "text", text = "OPTICS ........ ONLINE", duration = 1.1 },
			{ type = "text", text = "POWER CORE .... ONLINE", duration = 1.1 },
			{ type = "text", text = "MOTOR CONTROL . ONLINE", duration = 1.4 },
		},
		keepBlackScreen = true,
		preserveTransparency = true,
	})
end

-- 6. Die Kapitelkarten. "COMPLETE" ist der Moment, auf den das ganze Kapitel zulaeuft --
-- und direkt danach die Ankuendigung, damit das Ende nicht wie ein Schluss wirkt.
local function spieleKapitelkarten(player)
	StoryBeatService.Play(player, {
		steps = {
			{ type = "chapterCard", number = "I", title = "POWER", subtitle = "COMPLETE", duration = 3.5 },
			{ type = "wait", duration = 0.6 },
			{ type = "text", text = "POWER WAS ONLY THE BEGINNING.", duration = 3.0 },
			{ type = "wait", duration = 0.4 },
			{ type = "chapterCard", number = "II", title = "CONTROL", subtitle = "COMING SOON", duration = 3.5 },
		},
		keepBlackScreen = true,
		preserveTransparency = true,
	})
end

-- 7. RETURN TO SANCTUARY -- Herzschlag, dann Augen auf. Der Spieler bekommt die Kontrolle
-- zurueck, seine Werte bleiben. Mega City bleibt spielbar.
local function spieleRueckkehr(player)
	local schritte = {}
	haenge(schritte,
		ton(TON_HERZSCHLAG, 0.7), { type = "wait", duration = 1.4 },
		ton(TON_HERZSCHLAG, 0.7), { type = "wait", duration = 1.2 },
		{ type = "fadeOut", duration = 2.0 }
	)
	StoryBeatService.Play(player, { steps = schritte, preserveTransparency = true })

	RestorePrologueCameraEvent:FireClient(player)
	SetPrologueLetterboxEvent:FireClient(player, false)
	sperreSteuerung(player, false)
	StoryBeatService.ResumeNormalMusic(player, 0.5)
end

-- Die Spieler, fuer die in dieser Stadt gerade ein Finale faellig waere.
-- erzwingenFuer: EIN Spieler, fuer den die beiden Bedingungen unten nicht gelten. Nur der
-- Debug-Knopf setzt das (siehe unten). Ohne diesen Weg waere der Knopf nach dem ersten
-- Druck wertlos: das Finale schliesst das Kapitel ab, und ein abgeschlossenes Kapitel ist
-- nie wieder faellig. Zum Pruefen einer Szene braucht man sie aber mehrmals.
local function faelligeSpieler(cityName, erzwingenFuer)
	local eintrag = FINALE_JE_STADT[cityName]
	if not eintrag then
		return nil
	end

	local offen = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player == erzwingenFuer then
			table.insert(offen, player)
		elseif player:GetAttribute("CurrentCityName") == cityName then
			-- Nur wer tatsaechlich DA ist. Wer das Kapitel noch offen hat, aber in einer
			-- anderen Stadt steht, hat den Kampf nicht gesehen -- ihm ein Finale zu zeigen,
			-- waere eine Belohnung fuer Abwesenheit.
			if not (_G.HasCompletedChapter and _G.HasCompletedChapter(player, eintrag.Kapitel)) then
				table.insert(offen, player)
			end
		end
	end

	if #offen == 0 then
		return nil
	end
	return offen, eintrag
end

-- Fragt CityBrokenService, bevor er die freie Zerstoerung startet.
_G.ChapterFinaleDue = function(cityName)
	if laeuft[cityName] then
		return true -- laeuft schon: CITY BROKEN bleibt trotzdem aussen vor
	end
	return faelligeSpieler(cityName) ~= nil
end

_G.RunChapterFinale = function(cityName, erzwingenFuer)
	if laeuft[cityName] then
		return false
	end

	local offen, eintrag = faelligeSpieler(cityName, erzwingenFuer)
	if not offen then
		return false
	end

	laeuft[cityName] = true

	local namen = {}
	for _, player in ipairs(offen) do
		table.insert(namen, player.Name)
	end

	print(string.format("[Kaiju] Kapitelfinale %q in %s -- fuer %s. Jaeger-Ersatz: %s "
		.. "(%d Modelle im Einsatz).", eintrag.Titel, cityName,
		table.concat(namen, ", "), JAEGER_HAUPTFIGUR, #JAEGER_MODELLE))

	-- Jeder Spieler bekommt seine eigene Vorstellung. Sie laufen nebeneinander, weil sie
	-- alle an dieselbe Stelle gehoeren -- und weil ein Spieler, der nachtraeglich dazukommt,
	-- die anderen nicht aufhalten soll.
	for _, player in ipairs(offen) do
		task.spawn(function()
			local ok, fehler = pcall(function()
				sperreSteuerung(player, true)
				-- Filmstreifen an, HUD aus -- aber die Lebensanzeige bleibt, wie im Fall
				-- des Prologs. Erst zu den Kapitelkarten verschwindet alles.
				SetPrologueLetterboxEvent:FireClient(player, true)

				spieleStille(player)
				spieleSignal(player)
				spieleFalle(player)

				-- ===== NOCH OHNE WELT: die drei Beats, die Inhalte brauchen =====
				-- POWER FAILS waere hier der Kampf gegen die fuenf Jaeger: kurze Kontrolle,
				-- jeder Angriff laeuft ins Leere, dann schliessen sich die Barrieren. Dafuer
				-- braucht es die fuenf Modelle am Platz, Barrieren und Hangartore in Mega
				-- City -- nichts davon steht heute in der Welt.
				--
				-- THE GATE braucht den Turm am Uebergang und eine Kamerafahrt aus dem
				-- Cockpit heraus bis zum Kopf des Jaegers, mit dem Ruck in die Kamera.
				--
				-- Beides ist bewusst ausgelassen statt halb gebaut: eine Szene, in der die
				-- Jaeger fehlen, erzaehlt das Gegenteil der Geschichte. Die Textdramaturgie
				-- darunter traegt den Ablauf schon jetzt von Anfang bis Ende.
				spieleNiederlage(player)

				-- Ab hier ist der Bildschirm schwarz: alles ausblenden, auch die
				-- Lebensanzeige.
				SetPrologueLetterboxEvent:FireClient(player, true, true)

				spieleAufwachen(player)
				spieleKapitelkarten(player)
				spieleRueckkehr(player)
			end)

			if not ok then
				-- Haengenbleiben in einer Cutscene ist schlimmer als eine haessliche
				-- Rueckkehr: ohne diesen Ausgang stuende der Spieler ohne Steuerung und
				-- mit schwarzem Bild da, bis er neu beitritt.
				warn(string.format("[Kaiju] Kapitelfinale fuer %s abgebrochen: %s -- "
					.. "Steuerung und Bild werden zurueckgegeben.", player.Name, tostring(fehler)))
				pcall(function()
					RestorePrologueCameraEvent:FireClient(player)
					SetPrologueLetterboxEvent:FireClient(player, false)
					sperreSteuerung(player, false)
				end)
			end

			-- Abschliessen in JEDEM Fall -- auch nach einem Abbruch. Ein Finale, das
			-- scheitert und deshalb beim naechsten Sieg erneut startet, scheitert dann
			-- vermutlich wieder, und der Spieler kaeme nie zu CITY BROKEN.
			if _G.MarkChapterComplete then
				_G.MarkChapterComplete(player, eintrag.Kapitel)
			end
		end)
	end

	-- Die Sperre faellt erst nach der laengsten Vorstellung. Grosszuegig gerechnet: die
	-- Summe der Schritte oben liegt bei rund vierzig Sekunden.
	task.delay(60, function()
		laeuft[cityName] = false
	end)
	return true
end

-- ===== Debug: das Finale von Hand starten =====
-- Der normale Ausloeser ist schwer herzustellen: Mega City auf Hoechststufe, alle Aufgaben
-- erledigt, Kapitel noch offen -- und das genau einmal je Speicherstand. Eine Szene, die
-- man nur so zu sehen bekommt, laesst sich nicht beurteilen.
--
-- Der Knopf umgeht deshalb beide Bedingungen (Standort und Kapitelabschluss) fuer den
-- Spieler, der ihn drueckt. Was er NICHT umgeht, ist die Sperre gegen einen zweiten
-- gleichzeitigen Durchlauf: zwei Vorstellungen uebereinander zeigen nur, dass sie sich
-- ueberlagern. Gleiche Form wie der Prolog-Knopf (PrologueOrchestrator).
local DebugStartChapterFinaleEvent = RemoteEventUtils.GetOrCreate("DebugStartChapterFinaleEvent")
local DebugStartChapterFinaleResultEvent =
	RemoteEventUtils.GetOrCreate("DebugStartChapterFinaleResultEvent")

-- Welche Stadt der Knopf startet. Kapitel I spielt in Mega City (FINALE_JE_STADT oben);
-- kommt Kapitel II dazu, braucht der Knopf eine Auswahl -- heute waere sie eine Liste mit
-- einem Eintrag.
local DEBUG_FINALE_CITY = "MegaCity"
local DEBUG_COOLDOWN_SECONDS = 5

DebugStartChapterFinaleEvent.OnServerEvent:Connect(function(player)
	if not player:GetAttribute("DebugMode") then
		DebugStartChapterFinaleResultEvent:FireClient(player, false, "Debug-Modus zuerst aktivieren!")
		return
	end

	-- Gegen Doppelklicks, zusaetzlich zur Sperre am Knopf selbst.
	local now = os.clock()
	local letzter = player:GetAttribute("ChapterFinaleDebugLastStartAt")
	if letzter and now - letzter < DEBUG_COOLDOWN_SECONDS then
		DebugStartChapterFinaleResultEvent:FireClient(player, false, "Bitte kurz warten.")
		return
	end
	player:SetAttribute("ChapterFinaleDebugLastStartAt", now)

	local gestartet = _G.RunChapterFinale(DEBUG_FINALE_CITY, player)
	if gestartet then
		print(string.format("[Kaiju-Debug] Kapitelfinale von Hand gestartet fuer %s (%s).",
			player.Name, DEBUG_FINALE_CITY))
		DebugStartChapterFinaleResultEvent:FireClient(player, true, nil)
	else
		-- Der einzige Grund, aus dem es jetzt noch scheitern kann: es laeuft schon.
		-- Standort und Kapitelabschluss sind oben ausdruecklich umgangen.
		DebugStartChapterFinaleResultEvent:FireClient(player, false, "Laeuft bereits.")
	end
end)

print("[Kaiju] ChapterFinaleService bereit -- Finale von Kapitel I in Mega City, einmalig. "
	.. "Von Hand startbar ueber das Debug-Panel.")
