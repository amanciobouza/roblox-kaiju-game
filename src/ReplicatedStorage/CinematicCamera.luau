-- ModuleScript: CinematicCamera
--
-- Fuehrt einen "camera"-Schritt einer cinematischen Sequenz aus. Laeuft auf dem CLIENT --
-- die Kamera gehoert dort hin, und CLAUDE.mds Kameraregeln sind Clientregeln.
--
-- ===== Bausteine und Vorlagen =====
-- Entschieden am 11.10.2026: Bausteine als Grundlage, benannte Vorlagen darueber, und eine
-- Vorlage ist nie etwas anderes als vorgefertigte Bausteine. So bleibt ein reaktiver Shot
-- eine Zeile, waehrend eine Anflugfahrt ihren Langschwanz behaelt -- und es entsteht nicht
-- die Lage von heute, in der die Haelfte aller Fahrten nur im Code existiert ("style").
--
-- Pflicht an einem Schritt: duration, focus, und to ODER waypoints. Alles andere optional
-- mit dokumentiertem Standard (siehe STANDARD unten).
--
-- ===== Die fünf Vorlagen =====
-- Sie kommen aus dem Bestand, nicht vom Entwurfstisch: orbit (Finale/Trench), beamTravel,
-- lowRise, chestLow (Showdown) und waypointFlight (Prolog). Sie sind eingemessen und sie
-- laufen. Neue zu erfinden hiesse, getunte Arbeit wegzuwerfen.
--
-- ===== Die Sitzung ist nicht verhandelbar =====
-- Jede Fahrt laeuft gegen eine Sitzungs-Kennung (CameraSessionUtils). Eine ueberholte Fahrt
-- darf NIE weiter in die Kamera schreiben -- genau davor warnt CLAUDE.md, und genau daran
-- ist die "Peek-and-Blend"-Technik einmal gescheitert.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraSessionUtils = require(ReplicatedStorage:WaitForChild("CameraSessionUtils", 30))
local CinematicFormat = require(ReplicatedStorage:WaitForChild("CinematicFormat", 30))

local CinematicCamera = {}

CinematicCamera.VERSION = "CinematicCamera_v01"

local player = Players.LocalPlayer

-- Wie lange auf ein benanntes Teil gewartet wird. Kurz: die Sequenz laeuft schon, und ein
-- fehlendes Teil soll sie nicht aufhalten, sondern melden.
local VERWEIS_WARTEZEIT = 2

-- ===== Die Standardwerte =====
-- Sie stehen hier EINMAL und nirgends sonst. Wer einen Schritt ohne 'bank' schreibt, bekommt
-- 2.5 Grad -- denselben Wert, den die Prolog-Fahrt gemessen hat.
local STANDARD = {
	easing = "easeInOut",
	bank = 2.5, -- Grad, dezent; bei 0 wird gar nicht geneigt
	fov = nil, -- nil heisst: FOV nicht anfassen
	minHeight = 0, -- Mindesthoehe ueber dem Zielpunkt; beim Wasser des Prologs 18
	timeSplit = nil, -- nil heisst gleichmaessig; sonst Anteil der ZEIT fuer distanceSplit
	distanceSplit = nil, -- Anteil der STRECKE, der in timeSplit der Zeit zurueckgelegt wird
}

-- ===== Verweise auflösen =====
-- Das Schema steht in CinematicFormat; hier wird es zu einer Position.
local function teilSuchen(name)
	local direkt = Workspace:FindFirstChild(name)
	if direkt then
		return direkt
	end
	-- Tiefensuche nur als Rueckfall: in einer Workspace mit 600 000 Instanzen ist sie teuer,
	-- aber eine Sequenz, die wegen eines verschachtelten Teils gar nicht laeuft, ist teurer.
	return Workspace:FindFirstChild(name, true)
end

function CinematicCamera.Resolve(verweis, context)
	local teile, fehler = CinematicFormat.ParseReference(verweis)
	if not teile then
		return nil, fehler
	end

	if teile.scheme == "part" then
		local instanz = teilSuchen(teile.value)
		if not instanz then
			return nil, "kein Teil namens '" .. teile.value .. "' in der Workspace"
		end
		if instanz:IsA("BasePart") then
			return instanz.Position, nil, instanz
		end
		if instanz:IsA("Model") then
			local ok, pivot = pcall(function()
				return instanz:GetPivot().Position
			end)
			if ok then
				return pivot, nil, instanz
			end
		end
		return nil, "'" .. teile.value .. "' ist weder BasePart noch Model"
	end

	if teile.scheme == "player" then
		local character = player.Character
		local instanz = character and character:WaitForChild(teile.value, VERWEIS_WARTEZEIT)
		if not instanz or not instanz:IsA("BasePart") then
			return nil, "kein Teil '" .. teile.value .. "' an der Figur"
		end
		return instanz.Position, nil, instanz
	end

	if teile.scheme == "tag" then
		for _, instanz in ipairs(CollectionService:GetTagged(teile.value)) do
			if instanz:IsA("BasePart") then
				return instanz.Position, nil, instanz
			end
			if instanz:IsA("Model") and instanz.PrimaryPart then
				return instanz.PrimaryPart.Position, nil, instanz
			end
		end
		return nil, "nichts mit dem Tag '" .. teile.value .. "' gefunden"
	end

	-- context: der Dienst hat es beim Start mitgegeben, etwa den Guardian dieser Stadt.
	local aus = context and context[teile.value]
	if typeof(aus) == "Vector3" then
		return aus
	end
	if typeof(aus) == "Instance" then
		if aus:IsA("BasePart") then
			return aus.Position, nil, aus
		end
		if aus:IsA("Model") and aus.PrimaryPart then
			return aus.PrimaryPart.Position, nil, aus
		end
	end
	return nil, "context hat keinen brauchbaren Eintrag '" .. teile.value .. "'"
end

-- ===== Beschleunigungskurven =====
local KURVEN = {
	linear = function(a)
		return a
	end,
	easeIn = function(a)
		return a * a
	end,
	easeOut = function(a)
		return 1 - (1 - a) ^ 2
	end,
	easeInOut = function(a)
		return a < 0.5 and (2 * a * a) or (1 - ((-2 * a + 2) ^ 2) / 2)
	end,
}

-- ===== Der Pfad =====
-- Catmull-Rom durch die Wegpunkte, damit die Fahrt nicht an jedem Punkt knickt. Bei nur
-- zwei Punkten ist es eine Gerade -- dieselbe Rechnung, kein Sonderfall.
local function catmullRom(punkte, alpha)
	local anzahl = #punkte
	if anzahl == 1 then
		return punkte[1]
	end
	if anzahl == 2 then
		return punkte[1]:Lerp(punkte[2], alpha)
	end

	local abschnitte = anzahl - 1
	local skaliert = math.clamp(alpha, 0, 1) * abschnitte
	local index = math.min(math.floor(skaliert) + 1, abschnitte)
	local t = skaliert - (index - 1)

	local p0 = punkte[math.max(index - 1, 1)]
	local p1 = punkte[index]
	local p2 = punkte[math.min(index + 1, anzahl)]
	local p3 = punkte[math.min(index + 2, anzahl)]

	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
		+ (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- Bogenlaengen-Tabelle: ohne sie haengt das Tempo an der Verteilung der Wegpunkte, und zwei
-- dicht beieinander liegende Punkte bremsen die Fahrt grundlos ab.
local function bogenlaengen(punkte, schritte)
	local tabelle, gesamt = { { s = 0, a = 0 } }, 0
	local vorher = catmullRom(punkte, 0)
	for i = 1, schritte do
		local a = i / schritte
		local jetzt = catmullRom(punkte, a)
		gesamt += (jetzt - vorher).Magnitude
		table.insert(tabelle, { s = gesamt, a = a })
		vorher = jetzt
	end
	return tabelle, gesamt
end

local function alphaBeiStrecke(tabelle, gesamt, anteil)
	if gesamt <= 0 then
		return anteil
	end
	local ziel = anteil * gesamt
	for i = 2, #tabelle do
		if tabelle[i].s >= ziel then
			local vor, nach = tabelle[i - 1], tabelle[i]
			local spanne = nach.s - vor.s
			local t = spanne > 0 and (ziel - vor.s) / spanne or 0
			return vor.a + (nach.a - vor.a) * t
		end
	end
	return 1
end

-- ===== Die Vorlagen =====
-- Eine Vorlage liefert Standardwerte und darf einen eigenen Pfad mitbringen (orbit ist
-- parametrisch, nicht aus Wegpunkten). Alles, was der Schritt selbst setzt, gewinnt.
CinematicCamera.PRESETS = {
	-- Umrundet den Fokuspunkt. Aus dem Finale: der Kaiju steht, der Guardian kniet, und die
	-- Kamera kreist -- das Schweigen ist der Inhalt der Szene.
	orbit = {
		defaults = { easing = "linear", radius = 60, height = 20, turns = 0.5, bank = 0 },
		path = function(alpha, p)
			local winkel = p.startAngle + alpha * p.turns * math.pi * 2
			return p.focusPosition
				+ Vector3.new(math.cos(winkel) * p.radius, p.height, math.sin(winkel) * p.radius)
		end,
	},
	-- Faehrt am Strahl entlang zum Ziel. Aus dem Showdown (FocusLaser).
	beamTravel = { defaults = { easing = "easeIn", bank = 0 } },
	-- Tief am Boden, waehrend die Ladung waechst. Aus dem Showdown (AreaAttack).
	lowRise = { defaults = { easing = "easeOut", bank = 0, minHeight = 3 } },
	-- Von unten auf den Brustkern. Aus dem Showdown (WarningPulse).
	chestLow = { defaults = { easing = "easeInOut", bank = 0 } },
	-- Die Anflugfahrt des Prologs: Wegpunkte, ungleiche Zeitaufteilung, Neigung, Mindesthoehe.
	-- Die Zahlen sind die gemessenen -- "soll langsam vorwaerts gehen und schneller werden"
	-- (22.09.2026), und 18 Studs ueber Wasser gegen das Flackern.
	waypointFlight = {
		defaults = { easing = "linear", bank = 2.5, minHeight = 18, timeSplit = 0.55, distanceSplit = 0.3 },
	},
}

-- Schritt + Vorlage + Standard zu einem vollstaendigen Parametersatz. Reihenfolge: was der
-- Schritt sagt, gewinnt; dann die Vorlage; dann der Standard.
local function parameter(schritt)
	local vorlage = schritt.preset and CinematicCamera.PRESETS[schritt.preset]
	local p = {}
	for schluessel, wert in pairs(STANDARD) do
		p[schluessel] = wert
	end
	if vorlage then
		for schluessel, wert in pairs(vorlage.defaults or {}) do
			p[schluessel] = wert
		end
	end
	for schluessel, wert in pairs(schritt) do
		if wert ~= nil then
			p[schluessel] = wert
		end
	end
	return p, vorlage
end

-- ===== Eine Fahrt ausführen =====
-- Blockiert bis zum Ende der Fahrt. Gibt false zurueck, wenn sie abgebrochen wurde -- der
-- Laeufer entscheidet dann, ob die Sequenz weiterlaeuft.
function CinematicCamera.Play(schritt, context, sessionId)
	local camera = Workspace.CurrentCamera
	if not camera then
		return false, "keine Kamera"
	end

	local p, vorlage = parameter(schritt)

	local fokusPosition, fokusFehler = CinematicCamera.Resolve(p.focus, context)
	if not fokusPosition then
		return false, "focus: " .. tostring(fokusFehler)
	end

	-- Das zweite Blickziel, falls der Blick wandern soll. Optional -- ohne bleibt er beim
	-- ersten, so wie die Prolog-Fahrt es seit dem 05.10. wieder tut.
	local fokusZiel = nil
	if p.focusBlend then
		fokusZiel = CinematicCamera.Resolve(p.focusBlend, context)
	end

	-- Der Pfad: entweder Wegpunkte oder ein einzelnes Ziel -- genau eines, das prueft das
	-- Format. Eine Vorlage mit eigenem Pfad braucht beides nicht.
	local punkte, tabelle, gesamtStrecke
	if not (vorlage and vorlage.path) then
		local roh = {}
		if p.waypoints then
			for index, verweis in ipairs(p.waypoints) do
				local position, fehler = CinematicCamera.Resolve(verweis, context)
				if not position then
					return false, string.format("waypoint %d: %s", index, tostring(fehler))
				end
				table.insert(roh, position + Vector3.new(0, p.minHeight, 0))
			end
		else
			table.insert(roh, camera.CFrame.Position)
			local position, fehler = CinematicCamera.Resolve(p.to, context)
			if not position then
				return false, "to: " .. tostring(fehler)
			end
			table.insert(roh, position + Vector3.new(0, p.minHeight, 0))
		end
		punkte = roh
		tabelle, gesamtStrecke = bogenlaengen(punkte, 60)
	end

	local kurve = KURVEN[p.easing] or KURVEN.easeInOut
	local startAngle = 0
	if vorlage and vorlage.path then
		local hin = camera.CFrame.Position - fokusPosition
		startAngle = math.atan2(hin.Z, hin.X)
	end

	local start = os.clock()
	local neigung = 0
	local vorigePosition = camera.CFrame.Position

	while true do
		if not CameraSessionUtils.IsCurrent(sessionId) then
			return false, "von einer neueren Sequenz ueberholt"
		end

		local verstrichen = os.clock() - start
		local zeitAnteil = math.clamp(verstrichen / p.duration, 0, 1)

		-- ===== Ungleiche Zeit-/Streckenaufteilung =====
		-- Regie-Entscheidung vom 22.09.2026: die Fahrt soll langsam beginnen und schneller
		-- werden. Ohne diese beiden Zahlen waere sie gleichmaessig -- und genau das war
		-- vorher der Fall, in die falsche Richtung.
		local streckenAnteil
		if p.timeSplit and p.distanceSplit then
			if zeitAnteil <= p.timeSplit then
				streckenAnteil = (zeitAnteil / p.timeSplit) * p.distanceSplit
			else
				local rest = (zeitAnteil - p.timeSplit) / (1 - p.timeSplit)
				streckenAnteil = p.distanceSplit + rest * (1 - p.distanceSplit)
			end
		else
			streckenAnteil = kurve(zeitAnteil)
		end

		local position
		if vorlage and vorlage.path then
			position = vorlage.path(kurve(zeitAnteil), {
				focusPosition = fokusPosition,
				radius = p.radius,
				height = p.height,
				turns = p.turns,
				startAngle = startAngle,
			})
		else
			position = catmullRom(punkte, alphaBeiStrecke(tabelle, gesamtStrecke, streckenAnteil))
		end

		-- Neigung in Kurven, exponentiell geglaettet. Bei bank = 0 bleibt sie bei null, und
		-- die Rechnung entfaellt -- reaktive Shots sollen nicht kippeln.
		local aufwaerts = Vector3.yAxis
		if p.bank and p.bank > 0 then
			local richtung = position - vorigePosition
			local zielNeigung = 0
			if richtung.Magnitude > 0.01 then
				local zumFokus = fokusPosition - position
				if zumFokus.Magnitude > 0.01 then
					local vorzeichen = richtung.Unit:Cross(zumFokus.Unit).Y
					zielNeigung = math.clamp(vorzeichen, -1, 1) * math.rad(p.bank)
				end
			end
			neigung += (zielNeigung - neigung) * 0.08
			aufwaerts = Vector3.new(math.sin(neigung), math.cos(neigung), 0)
		end

		local blick = fokusPosition
		if fokusZiel then
			blick = fokusPosition:Lerp(fokusZiel, kurve(zeitAnteil))
		end

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(position, blick, aufwaerts)
		if p.fov then
			camera.FieldOfView = p.fov
		end

		vorigePosition = position
		if zeitAnteil >= 1 then
			return true
		end
		RunService.RenderStepped:Wait()
	end
end

return CinematicCamera
