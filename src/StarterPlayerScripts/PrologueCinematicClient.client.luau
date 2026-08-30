-- VERSION: 2026-08-26 #47
-- BUGFIX: Kamera-Fokuspunkt von Bauch- auf Schulterhoehe angehoben (0.4 -> 0.8 der Charakterhoehe)
-- Ort in Studio: StarterPlayerScripts
--
-- Steuert die Kamera während der Guardian-Niederlage-Kinematik im Prolog (Kaiju am
-- Boden -> Kamera schwenkt zum Guardian -> Guardian dreht sich zum Meer -> Kanagawa-Welle
-- erscheint und bricht -> Schwarzblende). Komplett getrennt vom StoryBeat-System (das
-- steuert nur 2D-Overlays, keine Kamera).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local SimplePrologueFallCameraEvent = RemoteEventUtils.GetOrCreate("SimplePrologueFallCameraEvent")
local TrenchOrbitCameraEvent = RemoteEventUtils.GetOrCreate("TrenchOrbitCameraEvent")
local RestorePrologueCameraEvent = RemoteEventUtils.GetOrCreate("RestorePrologueCameraEvent")
local PlayIntroCinematicEvent = RemoteEventUtils.GetOrCreate("PlayIntroCinematicEvent")
local CinematicCompleteEvent = RemoteEventUtils.GetOrCreate("CinematicCompleteEvent")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Globaler Kamera-Session-Zähler: verhindert, dass MEHRERE Kamera-Kontroll-Schleifen
-- (aus verschiedenen Events -- Fall-Kinematik, Intro-Kinematik, Trench-Orbit, etc.)
-- gleichzeitig aktiv sind und sich jeden Frame gegenseitig überschreiben. Das erzeugt
-- sonst genau den Effekt "zwei verschiedene Kameras, die sich abwechseln" (Flackern
-- zwischen zwei Positionen). JEDE Kamera-Schleife in dieser Datei erhöht diesen Zähler
-- bei ihrem Start, merkt sich ihre eigene ID, und prüft vor jedem Frame, ob sie noch die
-- AKTUELLE ist -- falls nicht (eine neuere Sequenz hat übernommen), bricht sie sofort ab.
local activeCameraSessionId = 0
local function startNewCameraSession()
	activeCameraSessionId += 1
	return activeCameraSessionId
end
local function isCameraSessionCurrent(sessionId)
	return activeCameraSessionId == sessionId
end

-- Mindesthöhe über der Wasseroberfläche -- muss zwischen SnapCameraToSeaEvent (Landung
-- am Meer-Spawnpunkt) UND dem Start des Spline-Pfads (flyOverWaterToKaiju) IDENTISCH
-- sein, sonst entsteht beim Übergang zwischen beiden ein sichtbarer Höhen-Sprung.
local MIN_HEIGHT_ABOVE_WATER = 18

-- Tweent die Kamera-CFrame sanft von der aktuellen Position zur Ziel-CFrame über
-- "duration" Sekunden. Läuft über RenderStepped, damit es butterweich (jeden gerenderten
-- Frame) statt nur alle task.wait()-Intervalle aktualisiert wird.
local function tweenCameraTo(targetCFrame, duration, sessionId)
	local startCFrame = camera.CFrame
	local startTime = os.clock()
	while true do
		if sessionId and not isCameraSessionCurrent(sessionId) then
			return
		end
		local elapsed = os.clock() - startTime
		local alpha = math.clamp(elapsed / duration, 0, 1)
		-- Sanftes Ein-/Ausschwingen (Ease-In-Out) statt linearer Bewegung -- wirkt
		-- deutlich filmischer als eine gleichförmige Kamerafahrt.
		local easedAlpha = alpha < 0.5 and (2 * alpha * alpha) or (1 - ((-2 * alpha + 2) ^ 2) / 2)
		camera.CFrame = startCFrame:Lerp(targetCFrame, easedAlpha)
		if alpha >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

-- Einfache Fall-Kinematik: Kamera zoomt auf den Körper des gefallenen Kaiju. Die
-- anschliessende Schwarzblende übernimmt der Server über das bewährte
-- StoryBeatService-System (siehe playSimpleFallCinematic in PrologueOrchestrator.lua),
-- statt hier eine eigene Overlay-Logik zu duplizieren.
SimplePrologueFallCameraEvent.OnClientEvent:Connect(function(data)
	local sessionId = startNewCameraSession()
	task.spawn(function()
		camera.CameraType = Enum.CameraType.Scriptable

		-- 1) Schwenk zur Kopf-Ausgangsposition.
		tweenCameraTo(data.headFocusStart, data.panDuration or 3, sessionId)
		if not isCameraSessionCurrent(sessionId) then
			return
		end

		-- 2) Langsames, kontinuierliches Heranzoomen -- kein statisches Halten, sondern
		-- eine durchgehende, sehr sanfte Annäherung an den Kopf.
		if data.headFocusEnd then
			local zoomDuration = data.zoomDuration or 4
			local startCFrame = camera.CFrame
			local startTime = os.clock()
			while true do
				if not isCameraSessionCurrent(sessionId) then
					return
				end
				local elapsed = os.clock() - startTime
				local alpha = math.clamp(elapsed / zoomDuration, 0, 1)
				camera.CFrame = startCFrame:Lerp(data.headFocusEnd, alpha)
				if alpha >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
		end

		-- WICHTIG: fest auf Custom setzen, NICHT einen vorher "gemerkten" Wert
		-- zurückschreiben (siehe andere Kinematiken in dieser Datei) -- die nachfolgende
		-- Schwarzblende (Server, StoryBeatService) verdeckt diesen Wechsel ohnehin.
		camera.CameraType = Enum.CameraType.Custom
		CinematicCompleteEvent:FireServer()
	end)
end)

-- Intro-Kinematik: Kamera folgt einer Bezier-Kurve über die in Studio platzierten
-- Wegpunkte (Workspace.Prologue.PrologueCameraSpawn_N) für den Boden-Pfad (X/Z), Höhe
-- läuft separat linear von Start- zu End-Höhe. Berücksichtigt die tatsächliche
-- Charaktergrösse, damit die Endposition nicht zu nah an einem grossen Kaiju landet.
-- Nach der Kinematik erhält der Spieler die normale Kamera-Kontrolle zurück (drehen +
-- zoomen), da CameraType auf Custom zurückgesetzt wird. Spieler sieht dabei nur zu, wie
-- der (geskriptete) Kaiju bereits angreift, kann selbst aber noch nicht steuern (siehe
-- PrologueOrchestrator.lua, spielt parallel die Kampfaktionen ab).

-- Interpoliert einen Punkt auf einer Bezier-Kurve durch beliebig viele Kontrollpunkte
-- (De-Casteljau-Algorithmus) -- funktioniert mit 2, 3, 4 oder mehr Punkten. Nur X/Z
-- werden hier verwendet (reiner Boden-Pfad), Y wird separat behandelt.

-- Catmull-Rom-Spline: verläuft EXAKT durch jeden Kontrollpunkt (anders als die vorherige
-- Bezier-Lösung, die sich bei vielen Punkten Richtung der direkten Start-Ende-Linie
-- "mittelte" und die mittleren Punkte dadurch zu schwach berücksichtigte). Standard-
-- Technik für flüssige Kamerapfade durch mehrere Wegpunkte.
local function catmullRomSegment(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * (
		(2 * p1)
			+ (p2 - p0) * t
			+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
			+ (3 * p1 - p0 - 3 * p2 + p3) * t3
	)
end

-- points: Liste von Vector3 (Boden-Wegpunkte), alpha: 0..1 Gesamt-Fortschritt über den
-- KOMPLETTEN Pfad (nicht nur ein einzelnes Segment).
local function catmullRomPoint(points, alpha)
	local n = #points
	if n == 1 then
		return points[1]
	end
	if n == 2 then
		return points[1]:Lerp(points[2], alpha)
	end

	local numSegments = n - 1
	local scaledT = alpha * numSegments
	local segmentIndex = math.floor(scaledT)
	if segmentIndex >= numSegments then
		segmentIndex = numSegments - 1
	end
	local localT = scaledT - segmentIndex

	local i = segmentIndex + 1 -- 1-indexiert: Segment zwischen points[i] und points[i+1]
	-- An den Rändern (kein p0 vor dem ersten bzw. kein p3 nach dem letzten Punkt) wird
	-- der jeweilige Endpunkt einfach dupliziert -- Standard-Lösung für offene Catmull-
	-- Rom-Splines.
	local p0 = points[i - 1] or points[i]
	local p1 = points[i]
	local p2 = points[i + 1]
	local p3 = points[i + 2] or points[i + 1]

	return catmullRomSegment(p0, p1, p2, p3, localT)
end

-- Arc-Length-Reparametrisierung: catmullRomPoint(points, t) mit gleichmässig verteiltem t
-- bewegt sich UNGLEICHMÄSSIG schnell entlang der Kurve, falls die Wegpunkte
-- unterschiedlich weit auseinander liegen (schnell durch kurze Segmente, langsam durch
-- lange) -- das wirkt ruckelig/uneben. Diese Tabelle bildet "zurückgelegte Distanz" auf
-- den passenden t-Wert ab, damit eine GLEICHMÄSSIGE Kamera-Geschwindigkeit über die
-- gesamte Fahrt entsteht, unabhängig von der genauen Wegpunkt-Verteilung in Studio.
local function buildArcLengthTable(points, samples)
	local entries = { { distance = 0, t = 0 } }
	local totalDistance = 0
	local prevPoint = catmullRomPoint(points, 0)
	for i = 1, samples do
		local t = i / samples
		local point = catmullRomPoint(points, t)
		totalDistance = totalDistance + (point - prevPoint).Magnitude
		table.insert(entries, { distance = totalDistance, t = t })
		prevPoint = point
	end
	return entries, totalDistance
end

-- Wandelt einen gleichmässigen Zeit-Alpha (0-1) in den passenden Kurven-Parameter t um,
-- basierend auf der vorab berechneten Distanz-Tabelle -- ergibt konstante Geschwindigkeit.
local function arcLengthAlphaToT(arcTable, totalDistance, alpha)
	if totalDistance <= 0 then
		return alpha
	end
	local targetDistance = alpha * totalDistance
	for i = 1, #arcTable - 1 do
		local a, b = arcTable[i], arcTable[i + 1]
		if targetDistance >= a.distance and targetDistance <= b.distance then
			local segLen = b.distance - a.distance
			local segAlpha = segLen > 0 and (targetDistance - a.distance) / segLen or 0
			return a.t + (b.t - a.t) * segAlpha
		end
	end
	return 1
end

local function flyOverWaterToKaiju(seaStartPosition, waypoints, duration, zoomDuration, finalCameraCFrame, sessionId)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Charaktergrösse ermitteln, um die End-Höhe sinnvoll zu skalieren -- ein grosser
	-- Kaiju braucht mehr Abstand für eine gute Nahaufnahme als ein kleiner.
	local ok, boundsSize = pcall(function()
		local _, size = character:GetBoundingBox()
		return size
	end)
	local characterHeight = (ok and boundsSize.Y) or 20

	local kaijuCenter = rootPart.Position + Vector3.new(0, characterHeight * 0.8, 0)
	local startHeight = seaStartPosition.Y
	local endHeight = kaijuCenter.Y + characterHeight * 0.12

	local function easeInOut(alpha)
		return alpha < 0.5 and (2 * alpha * alpha) or (1 - ((-2 * alpha + 2) ^ 2) / 2)
	end

	-- Regie-Timing: statt die GESAMTE Fahrt mit gleichmässiger Geschwindigkeit
	-- zurückzulegen, verbringt die Kamera bewusst UNGLEICH viel Zeit auf den beiden
	-- Streckenabschnitten -- die ersten DISTANCE_SPLIT der Distanz (offene Meer-
	-- Überquerung) zügig in nur TIME_SPLIT der Gesamtzeit, der Rest (der dramatische
	-- Kletter-und-Sinkflug zum Kaiju -- der eigentliche "Reveal") deutlich langsamer in
	-- der verbleibenden Zeit. Jeder Abschnitt wird intern zusätzlich sanft ein-/
	-- ausgeblendet (kein hartes Tempo-Umschalten am Übergang).
	local DISTANCE_SPLIT = 0.70
	local TIME_SPLIT = 0.55
	local function timeToDistanceFraction(rawAlpha)
		if rawAlpha <= TIME_SPLIT then
			local localAlpha = rawAlpha / TIME_SPLIT
			return easeInOut(localAlpha) * DISTANCE_SPLIT
		else
			local localAlpha = (rawAlpha - TIME_SPLIT) / (1 - TIME_SPLIT)
			return DISTANCE_SPLIT + easeInOut(localAlpha) * (1 - DISTANCE_SPLIT)
		end
	end

	-- WICHTIG: keine separate "Align"-Phase mehr -- die sorgte für einen sichtbaren
	-- Positions-Sprung, wenn ihre Endposition nicht exakt mit dem Start des Spline-Pfads
	-- übereinstimmte. Die Kamera startet jetzt DIREKT bei der Spline-Pfad-Phase; deren
	-- erster Frame richtet sich über CFrame.lookAt() ohnehin sofort auf den Kaiju aus --
	-- SnapCameraToSeaEvent setzt die Startposition bereits korrekt (inkl. derselben
	-- MIN_HEIGHT_ABOVE_WATER-Anhebung), daher kein Sprung mehr zwischen beiden Phasen.
	print("[Kaiju-Debug] PHASE 1/3 'SPLINE-PFAD' startet -- tick=" .. tostring(os.clock()) .. " duration=" .. tostring(duration) .. " Wegpunkte=" .. tostring(waypoints and #waypoints))
	if waypoints and #waypoints >= 2 then
		-- ===== Catmull-Rom-Pfad über die in Studio platzierten Wegpunkte =====
		-- WICHTIG: nutzt jetzt die VOLLEN 3D-Positionen (inkl. der tatsächlichen
		-- Höhenwerte aus Studio) statt einer eigenen, simplen linearen Höhen-Rampe -- die
		-- Wegpunkte haben bewusst gesetzte Höhen (z.B. steigt der Pfad an und sinkt zum
		-- Schluss wieder dramatisch ab), die vorher komplett ignoriert wurden.
		-- seaStartPosition wird als zusätzlicher erster Punkt vorangestellt, damit die
		-- Fahrt exakt dort beginnt, wo die Kamera durch SnapCameraToSeaEvent bereits
		-- steht -- kein Sprung, falls dieser Punkt nicht exakt mit Wegpunkt #1
		-- übereinstimmt.
		-- WICHTIG: die rohen Wegpunkt-Höhen liegen teils nur bei ~0-0.5 Studs (praktisch auf
		-- Wasserhöhe) -- das führte zu starkem Flackern (Z-Fighting mit der
		-- Wasseroberfläche), da die Kamera direkt AN/AUF dem Wasser statt darüber flog.
		-- Hebt jetzt alle Punkte um einen Mindestabstand an, behält dabei aber die
		-- RELATIVE Form (den Steig-und-Sinkflug) der Wegpunkte bei -- die Dramaturgie
		-- bleibt erhalten, die Kamera fliegt aber klar über der Wasseroberfläche.
		-- WICHTIG: seaStartPosition wird nur vorangestellt, falls sie sich MEANINGFULLY vom
		-- ersten Wegpunkt unterscheidet -- ansonsten (der Normalfall: PrologueCameraSpawn_1
		-- ist sowohl der Meer-Startpunkt ALS AUCH der erste Wegpunkt) wären beide praktisch
		-- identisch, was zwei nahezu deckungsgleiche Punkte am Kurvenanfang erzeugt. Das
		-- verzerrt die von Catmull-Rom berechnete Anfangstangente und liess die Kamera
		-- kurz zurückschwingen, bevor sie vorwärts fährt.
		local elevatedSeaStart = seaStartPosition + Vector3.new(0, MIN_HEIGHT_ABOVE_WATER, 0)
		local elevatedFirstWaypoint = waypoints[1] + Vector3.new(0, MIN_HEIGHT_ABOVE_WATER, 0)
		local pathPoints = {}
		if (elevatedSeaStart - elevatedFirstWaypoint).Magnitude > 5 then
			table.insert(pathPoints, elevatedSeaStart)
		end
		for index, waypoint in ipairs(waypoints) do
			if index < #waypoints then
				table.insert(pathPoints, waypoint + Vector3.new(0, MIN_HEIGHT_ABOVE_WATER, 0))
			end
		end
		if #pathPoints < 2 then
			-- Sicherheitsnetz: falls nur 1 Wegpunkt übrig bleibt (sehr wenige Wegpunkte
			-- insgesamt), den letzten doch mit aufnehmen, damit der Pfad gültig bleibt.
			table.insert(pathPoints, waypoints[#waypoints] + Vector3.new(0, MIN_HEIGHT_ABOVE_WATER, 0))
		end

		-- Arc-Length-Tabelle einmalig vorab berechnen -- macht die Fahrt unabhängig von
		-- der genauen Wegpunkt-Verteilung gleichmässig schnell (siehe buildArcLengthTable).
		local arcTable, totalArcDistance = buildArcLengthTable(pathPoints, 60)

		local BANK_MAX_ANGLE = math.rad(2.5) -- noch dezenter als zuvor
		local BANK_LOOKAHEAD = 0.01 -- kleiner Zeit-Schritt nach vorne, um die aktuelle Kurven-Richtung zu ermitteln
		local BANK_SMOOTHING = 3 -- wie schnell sich der Bankwinkel dem Ziel annähert (kleiner = sanfter/träger)
		local currentBankAngle = 0
		local lastFrameTime = os.clock()

		local startTime = os.clock()
		while true do
			if sessionId and not isCameraSessionCurrent(sessionId) then
				return
			end
			local elapsed = os.clock() - startTime
			local alpha = math.clamp(elapsed / duration, 0, 1)
			-- weiter oben: erste 70% der Distanz zügig, letzte 30% (der Kletter-und-
			-- Sinkflug zum Kaiju) spürbar langsamer.
			local easedAlpha = timeToDistanceFraction(alpha)

			-- Gleichmässige Geschwindigkeit INNERHALB der beiden Abschnitte: easedAlpha
			-- bestimmt weiterhin das Tempo (siehe oben), die Arc-Length-Tabelle sorgt
			-- zusätzlich dafür, dass die tatsächliche Distanz pro Zeiteinheit innerhalb
			-- jedes Abschnitts konstant bleibt.
			local curveT = arcLengthAlphaToT(arcTable, totalArcDistance, easedAlpha)
			local camPos = catmullRomPoint(pathPoints, curveT)

			-- Leichtes Banking: vergleicht die aktuelle Position mit einer knapp
			-- voraus liegenden, um die momentane Kurven-Richtung zu ermitteln, und neigt
			-- die Kamera dezent in diese Richtung -- wirkt lebendiger/cinematischer als
			-- eine starr aufrechte Kamera. GEGLÄTTET: der Bankwinkel springt nicht sofort
			-- auf den Zielwert, sondern nähert sich ihm sanft an (verhindert schnelle,
			-- ruckartige Neigungswechsel in engen Kurven).
			local now = os.clock()
			local dt = math.max(now - lastFrameTime, 0.001)
			lastFrameTime = now

			local lookAheadT = arcLengthAlphaToT(arcTable, totalArcDistance, math.clamp(easedAlpha + BANK_LOOKAHEAD, 0, 1))
			local lookAheadPos = catmullRomPoint(pathPoints, lookAheadT)
			local moveDirection = lookAheadPos - camPos
			local targetBankAngle = 0
			if moveDirection.Magnitude > 0.01 then
				-- Vorzeichen der Kurven-Krümmung grob über die Änderung der Bewegungs-
				-- richtung relativ zur Blickrichtung zum Kaiju abschätzen.
				local toKaiju = (kaijuCenter - camPos)
				local turnSign = (moveDirection.Unit:Cross(toKaiju.Unit)).Y
				targetBankAngle = math.clamp(turnSign, -1, 1) * BANK_MAX_ANGLE
			end
			-- Exponentielle Glättung: nähert sich pro Frame nur einen Bruchteil des Wegs
			-- zum Zielwinkel an, statt ihn sofort zu übernehmen.
			local smoothFactor = 1 - math.exp(-BANK_SMOOTHING * dt)
			currentBankAngle = currentBankAngle + (targetBankAngle - currentBankAngle) * smoothFactor
			local upVector = Vector3.new(math.sin(currentBankAngle), math.cos(currentBankAngle), 0)

			camera.CFrame = CFrame.lookAt(camPos, kaijuCenter, upVector)

			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	else
		-- ===== Fallback: altes 4-Phasen-System, falls keine/zu wenige Wegpunkte in
		-- Studio gefunden wurden (siehe Workspace.Prologue.PrologueCameraSpawn_N). =====
		warn("[PrologueCinematicClient] Weniger als 2 Wegpunkte übergeben -- nutze Fallback-Kamerapfad.")
		local startOffset = seaStartPosition - kaijuCenter
		local startRadius = Vector3.new(startOffset.X, 0, startOffset.Z).Magnitude
		local startAngle = math.atan(startOffset.Z, startOffset.X)
		local endRadius = math.max(characterHeight * 0.75, 9)
		local lookDirection = rootPart.CFrame.LookVector
		local behindAngle = math.atan(-lookDirection.Z, -lookDirection.X)
		local angleDelta = behindAngle - startAngle
		angleDelta = angleDelta % (2 * math.pi)
		angleDelta = angleDelta - 2 * math.pi
		if angleDelta > math.rad(-220) then
			angleDelta = angleDelta - 2 * math.pi
		end

		local startTime = os.clock()
		while true do
			if sessionId and not isCameraSessionCurrent(sessionId) then
				return
			end
			local elapsed = os.clock() - startTime
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local easedAlpha = easeInOut(alpha)

			local angle = startAngle + easedAlpha * angleDelta
			local radius = startRadius + (endRadius - startRadius) * easedAlpha
			local height = startHeight + (endHeight - startHeight) * easedAlpha

			local camPos = Vector3.new(
				kaijuCenter.X + math.cos(angle) * radius,
				height,
				kaijuCenter.Z + math.sin(angle) * radius
			)
			camera.CFrame = CFrame.lookAt(camPos, kaijuCenter)

			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end

	-- ===== Umrundung: zeigt den Kaiju mit seiner Umgebung, endet in einer normalen
	-- Third-Person-Position hinter der Figur -- WIRD die Start-Kameraperspektive für den
	-- Spieler, kein zusätzlicher Sprung mehr danach nötig. Läuft als EIN durchgehender
	-- Bogen (Winkel, Radius UND Höhe verändern sich gemeinsam), damit es keinen Schnitt
	-- zwischen "breite Umrundung" und "nahe Spielposition" gibt. =====
	print("[Kaiju-Debug] PHASE 2/3 'UMRUNDUNG' startet -- tick=" .. tostring(os.clock()) .. " camPos=" .. tostring(camera.CFrame.Position))
	do
		-- Startwinkel/-radius aus der TATSÄCHLICHEN aktuellen Kamera-Position relativ zum
		-- Kaiju berechnen -- damit die Umrundung nahtlos an die vorherige Pfad-Animation
		-- anschliesst, ohne Sprung. WICHTIG: kein erzwungener Mindest-Radius mehr -- das
		-- verursachte genau den abrupten Sprung, den wir vermeiden wollen (falls der
		-- letzte Wegpunkt näher am Kaiju lag als ein künstlicher Mindestwert, "sprang"
		-- die Kamera beim Start der Umrundung sofort nach aussen, um ihn einzuhalten).
		local currentOffset = camera.CFrame.Position - kaijuCenter
		local startAngle = math.atan2(currentOffset.Z, currentOffset.X)
		local startRadius = Vector3.new(currentOffset.X, 0, currentOffset.Z).Magnitude
		local startOrbitHeight = camera.CFrame.Position.Y

		-- Zielposition: normale Third-Person-Position HINTER der Figur (entgegen ihrer
		-- Blickrichtung), in typischem Gameplay-Abstand -- das wird nahtlos zur
		-- Spieler-Kamera, kein Sprung beim Kontrollübergang.
		local lookDirection = rootPart.CFrame.LookVector
		local endAngle = math.atan2(-lookDirection.Z, -lookDirection.X)
		-- Proportional zur Charaktergrösse -- ein fester Wert (z.B. 13 Studs) ist für einen
		-- kleinen Charakter treffend, aber bei einem so grossen Kaiju deutlich zu nah:
		-- Roblox' eigene Third-Person-Kamera hält für grosse Charaktere automatisch mehr
		-- Abstand, ein zu naher Wert hier verursacht sonst genau den spürbaren Sprung
		-- beim Übergang von Scriptable zu Custom.
		local endRadius = math.max(characterHeight * 0.85, 13)
		local endOrbitHeight = kaijuCenter.Y + characterHeight * 0.35

		-- Kürzesten Drehweg zum Ziel-Winkel wählen (kein unnötiger Umweg-Dreher).
		local angleDelta = endAngle - startAngle
		angleDelta = (angleDelta + math.pi) % (2 * math.pi) - math.pi

		print(string.format(
			"[Kaiju-Debug] Umrundungs-Parameter: startRadius=%.1f endRadius=%.1f startHeight=%.1f endHeight=%.1f angleDelta=%.1f°",
			startRadius, endRadius, startOrbitHeight, endOrbitHeight, math.deg(angleDelta)
			))

		local orbitDuration = 5
		local orbitStartTime = os.clock()
		while true do
			if sessionId and not isCameraSessionCurrent(sessionId) then
				return
			end
			local elapsed = os.clock() - orbitStartTime
			local alpha = math.clamp(elapsed / orbitDuration, 0, 1)
			local easedAlpha = easeInOut(alpha)

			local angle = startAngle + angleDelta * easedAlpha
			local radius = startRadius + (endRadius - startRadius) * easedAlpha
			local orbitHeight = startOrbitHeight + (endOrbitHeight - startOrbitHeight) * easedAlpha

			local camPos = Vector3.new(
				kaijuCenter.X + math.cos(angle) * radius,
				orbitHeight,
				kaijuCenter.Z + math.sin(angle) * radius
			)
			camera.CFrame = CFrame.lookAt(camPos, kaijuCenter)

			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end

	return characterHeight
end

PlayIntroCinematicEvent.OnClientEvent:Connect(function(data)
	local sessionId = startNewCameraSession()
	task.spawn(function()
		camera.CameraType = Enum.CameraType.Scriptable
		-- WICHTIG: Kamera wurde bereits vorher (während "THE CITY IS ALREADY LOST", siehe
		-- SnapCameraToSeaEvent) zum Meer-Spawnpunkt gesprungen -- hier NICHT nochmal
		-- hart auf data.seaView setzen, sonst gäbe es einen sichtbaren zweiten Sprung.
		-- Falls die Kamera aus irgendeinem Grund noch nicht dort ist (Sicherheitsnetz),
		-- wird sie trotzdem gesetzt.
		if (camera.CFrame.Position - data.seaView.Position).Magnitude > 5 then
			camera.CFrame = data.seaView
		end

		local characterHeight = flyOverWaterToKaiju(data.seaView.Position, data.cameraPathWaypoints, data.flyDuration or 10, data.zoomDuration or 0.5, data.finalCameraCFrame, sessionId)

		if not isCameraSessionCurrent(sessionId) then
			return -- von einer neueren Kamera-Sequenz überholt -- Kontrolle NICHT übernehmen
		end

		-- WICHTIG: Robloxs Standard-Zoom-Distanz (CameraMinZoomDistance/
		-- CameraMaxZoomDistance) ist für normal grosse Charaktere gedacht -- bei einem so
		-- riesigen Kaiju würde die Standard-Distanz die Kamera viel zu nah an den
		-- Charakter setzen. Proportional zur tatsächlichen Charaktergrösse angepasst --
		-- dadurch landet Robloxs eigene Kamera von selbst nah an der Position, wo unsere
		-- Umrundung endet.
		if characterHeight then
			local desiredZoom = math.max(characterHeight * 0.85, 12)
			-- WICHTIG: MaxZoom zuerst setzen -- verhindert, dass MinZoom kurzzeitig
			-- grösser als der (noch alte, evtl. kleinere) MaxZoom-Wert ist.
			player.CameraMaxZoomDistance = desiredZoom * 3 -- Spieler darf danach trotzdem noch weiter rauszoomen
			player.CameraMinZoomDistance = desiredZoom
		end

		-- WICHTIG: fest auf Custom setzen (NICHT einen vorher "gemerkten" Wert
		-- zurückschreiben) -- camera.CameraType stand an dieser Stelle durch das vorher
		-- gefeuerte SnapCameraToSeaEvent bereits auf Scriptable, ein gemerkter Wert hätte
		-- die Kamera-Kontrolle nach der Kinematik fälschlich für immer gesperrt gehalten.
		-- KEIN "Peek-and-Blend" mehr -- das kurze Umschalten auf Custom (auch nur für 1-2
		-- Frames) war selbst sichtbar und wirkte wie ein unruhiger Kurz-Zoom. Stattdessen
		-- einfacher, direkter Wechsel -- die Umrundung endet bereits an einer sinnvollen
		-- Third-Person-Position, kombiniert mit der angepassten Zoom-Distanz oben sollte
		-- der Übergang jetzt unauffällig sein.
		camera.CameraType = Enum.CameraType.Custom
		print("[Kaiju-Debug] PHASE 3/3 'KONTROLLÜBERGABE' -- Intro-Kinematik KOMPLETT FERTIG -- tick=" .. tostring(os.clock()) .. " finale camPos=" .. tostring(camera.CFrame.Position))
		CinematicCompleteEvent:FireServer()
	end)
end)

-- Springt die Kamera HART (ohne Animation) zum Meer-Spawnpunkt -- ausgelöst genau während
-- "THE CITY IS ALREADY LOST." (nicht früher), damit der Spieler die Zerstörungs-
-- Explosionen in der Stadt beim Ticken/den Sirenen noch aus der "richtigen" Perspektive
-- hört, bevor die Kamera (audio-mässig) ans Meer wechselt. Der Bildschirm ist zu diesem
-- Zeitpunkt ohnehin schwarz (StoryBeat-Text), der Sprung selbst ist also nicht sichtbar.
local SnapCameraToSeaEvent = RemoteEventUtils.GetOrCreate("SnapCameraToSeaEvent")
SnapCameraToSeaEvent.OnClientEvent:Connect(function(seaCFrame)
	startNewCameraSession() -- bricht jede noch laufende Kamera-Sequenz ab
	camera.CameraType = Enum.CameraType.Scriptable

	-- WICHTIG: dieselbe Höhen-Anhebung wie beim Start des Spline-Pfads (siehe
	-- MIN_HEIGHT_ABOVE_WATER weiter oben) -- sonst landet die Kamera hier auf
	-- Wasserhöhe, während der Spline-Pfad direkt danach 18 Studs höher startet, was
	-- einen sichtbaren Sprung beim Übergang zwischen beiden verursacht.
	local elevatedPosition = seaCFrame.Position + Vector3.new(0, MIN_HEIGHT_ABOVE_WATER, 0)

	-- Zielt direkt beim Sprung auf den Kaiju, statt die rohe Studio-Rotation von
	-- PrologueCameraSpawn zu übernehmen (die nicht zwingend exakt auf den Kaiju zeigt).
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		camera.CFrame = CFrame.new(elevatedPosition, rootPart.Position)
	else
		camera.CFrame = CFrame.new(elevatedPosition, seaCFrame.Position)
	end
end)

-- Trench-Orbit-Kamera: schaut von oben schräg auf den Trench, umrundet ihn langsam,
-- schwenkt dann zum Spieler und hält dort -- läuft NICHT-BLOCKIEREND (eigene Coroutine),
-- unabhängig von den parallel laufenden Text-Sequenzen (siehe StoryBeatClient.lua).
-- Endet nicht von selbst -- die Kamera bleibt auf dem Spieler stehen, bis
-- RestorePrologueCameraEvent (siehe unten) die Kontrolle zurückgibt.
TrenchOrbitCameraEvent.OnClientEvent:Connect(function(data)
	local sessionId = startNewCameraSession()
	task.spawn(function()
		camera.CameraType = Enum.CameraType.Scriptable

		local center = data.center
		local radius = data.radius or 45
		local height = data.height or 35
		local orbitDuration = data.orbitDuration or 6

		local startAngle = 0
		local orbitAngleRadians = math.rad(90) -- langsame, ruhige Umrundung -- kein voller Kreis

		local startTime = os.clock()
		while os.clock() - startTime < orbitDuration do
			if not isCameraSessionCurrent(sessionId) then
				return -- überholt von einer neueren Kamera-Sequenz
			end
			local alpha = math.clamp((os.clock() - startTime) / orbitDuration, 0, 1)
			local angle = startAngle + orbitAngleRadians * alpha
			local camPos = Vector3.new(
				center.X + math.cos(angle) * radius,
				center.Y + height,
				center.Z + math.sin(angle) * radius
			)
			camera.CFrame = CFrame.lookAt(camPos, center)
			RunService.RenderStepped:Wait()
		end

		if not isCameraSessionCurrent(sessionId) then
			return
		end

		-- Schwenk zum Spieler, dann halten -- bleibt danach einfach an dieser Position
		-- stehen (kein weiterer Zyklus), bis die Kontrolle zurückgegeben wird. WICHTIG:
		-- nutzt jetzt dieselbe "hinter dem Rücken"-Technik wie am Prolog-Beginn (siehe
		-- flyOverWaterToKaiju weiter oben) -- berechnet basierend auf der TATSÄCHLICHEN
		-- Blickrichtung und Grösse der Figur, statt eines festen, willkürlichen Versatzes.
		if data.playerFocusPosition then
			local startCFrame = camera.CFrame
			local focusPos = data.playerFocusPosition
			local endCFrame

			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local ok, boundsSize = pcall(function()
					local _, size = character:GetBoundingBox()
					return size
				end)
				local characterHeight = (ok and boundsSize.Y) or 20
				local kaijuFocusCenter = focusPos + Vector3.new(0, characterHeight * 0.8, 0)
				local lookDirection = rootPart.CFrame.LookVector
				local behindRadius = math.max(characterHeight * 0.85, 13)
				local behindHeight = kaijuFocusCenter.Y + characterHeight * 0.35
				local endPos = Vector3.new(
					kaijuFocusCenter.X - lookDirection.X * behindRadius,
					behindHeight,
					kaijuFocusCenter.Z - lookDirection.Z * behindRadius
				)
				endCFrame = CFrame.lookAt(endPos, kaijuFocusCenter)
			else
				-- Sicherheitsnetz, falls der Charakter (noch) nicht existiert.
				endCFrame = CFrame.lookAt(focusPos + Vector3.new(10, 8, 10), focusPos)
			end

			local panDuration = data.panToPlayerDuration or 1.5
			local panStartTime = os.clock()
			while true do
				if not isCameraSessionCurrent(sessionId) then
					return
				end
				local elapsed = os.clock() - panStartTime
				local alpha = math.clamp(elapsed / panDuration, 0, 1)
				camera.CFrame = startCFrame:Lerp(endCFrame, alpha)
				if alpha >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
		end
	end)
end)

-- Gibt die Kamera-Kontrolle an den Spieler zurück (Custom statt Scriptable) -- feuert eine
-- evtl. noch laufende Kamera-Sequenz ab (gemeinsamer Session-Mechanismus, siehe oben).
RestorePrologueCameraEvent.OnClientEvent:Connect(function()
	startNewCameraSession()
	camera.CameraType = Enum.CameraType.Custom

	-- WICHTIG: setzt die Zoom-Distanz-Beschränkung zurück auf Robloxs Standardwerte --
	-- die Intro-Kinematik (siehe PlayIntroCinematicEvent-Handler oben) hatte sie
	-- proportional zur GROSSEN Prolog-Kaiju-Grösse gesetzt, aber nie wieder
	-- zurückgesetzt. Der Charakter ist nach dem Prolog-Ende (MarkPrologueComplete,
	-- Level 0) deutlich kleiner -- die alte, zu grosse Mindest-Distanz verhinderte
	-- fälschlich das Heranzoomen.
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 400
end)