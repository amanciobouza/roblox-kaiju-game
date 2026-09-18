-- VERSION: 2026-09-13 #1
-- ModuleScript: KaijuStageOneCombatAdapter
-- Ort in Studio: ServerScriptService
--
-- Die Brücke zwischen dem Primal-Beast-Rig aus dem Workshop und dem Schadenssystem des
-- Spiels. Der Workshop liefert diesen Adapter bewusst NICHT mit: sein eigener
-- (KaijuStageOneCombat) beschädigt nur eigens registrierte Übungsgebäude und würde, ins
-- Spiel gehängt, an allem vorbeilaufen, was eine Zerstörung hier ausmacht.
--
-- ===== Die Leitentscheidung: alles läuft durch _G.DamageHouse =====
-- Der Adapter rechnet KEINEN Schaden selbst auf Gebäude an. Jeder Treffer geht durch
-- dieselbe Funktion, die auch der normale Angriff benutzt (HouseHandler.damageHouse).
-- Daran hängen: Coins, Energie, Erfahrung, Alarmfortschritt, Hitze, Achievements,
-- Helikopter-Meldung, Einsturz-Animation und Respawn. Ein eigener Schadensweg hätte all
-- das umgangen -- ein Gebäude wäre gefallen, ohne dass die Stadt es bemerkt.
--
-- Aus demselben Grund kommt auch die Schadenshöhe aus dem Spiel und nicht aus dem
-- Workshop: Grundlage ist das Attribut "Damage" der Figur, das PlayerSetup aus Arm-Kraft
-- und Stufe berechnet. Die Werte unten sind Faktoren darauf, keine absoluten Zahlen.
--
-- ===== Was dieser Adapter NICHT tut: Fokus und Fläche =====
-- Für diese beiden macht er KEINEN Schaden. Sie gehören dem SpecialAttackHandler des
-- Spiels, mit Energiekosten, Cooldown, Talentboni, Freischaltung, Schaden und eigenen
-- Effekten. Das Rig spielt dazu nur seine Bewegung (siehe SpecialAttackClient).
--
-- Rechnete dieser Adapter zusätzlich Schaden, träfe jeder Spezialangriff doppelt. Beim
-- NAHKAMPF ist es umgekehrt: dort ersetzt das Rig den alten Weg vollständig, also gehört
-- ihm auch die Trefferermittlung.
--
-- ===== Der Finisher: anheben und in der Luft zerreissen =====
-- Das Rig kann ein Gebäude greifen, hochheben und auseinanderreissen. Damit das im Spiel
-- funktioniert und nichts zurücklässt, stützt es sich auf drei Dinge, die HouseHandler
-- ohnehin schon führt:
--
--   1. JEDES Hausteil trägt seine `OriginalCFrame` als Attribut, und der Respawn setzt
--      jedes Teil exakt darauf zurück. Ein angehobenes Gebäude ist deshalb IMMER
--      rückholbar -- auch wenn der Griff abbricht, der Spieler stirbt oder der Server
--      mitten in der Bewegung neu lädt.
--   2. `OriginalCanCollide` steht ebenso am Teil. Während des Hebens wird die Kollision
--      abgeschaltet, danach aus diesem Attribut wiederhergestellt -- nicht geraten.
--   3. `ParentGroupService.IsParentGroupHouse` sagt, ob ein Haus nur EIN Abschnitt eines
--      grösseren Bauwerks ist (die Marina trägt sieben Tags). Solche Abschnitte werden
--      NICHT angehoben: ein einzelnes Stück aus einem Hotel zu reissen sähe aus wie ein
--      Fehler, und ihr Respawn hat eigenen Gruppenzustand.
--
-- Das Zerreissen selbst läuft über KOPIEN, nicht über das echte Gebäude. Das echte geht
-- den normalen Zerstörungsweg (Belohnungen, Alarm, Einsturz, Respawn) und wird sofort
-- unsichtbar; zu sehen sind zwei auseinanderfliegende Hälften, die nach kurzer Zeit
-- verschwinden. Würde man das echte Gebäude zerlegen, geriete man mit genau der
-- Einsturz-Animation in Streit, die danach ohnehin läuft.
--
-- ===== Vertrag =====
-- Aufrufe kommen vom Rig (KaijuStageOneRig), immer als Punkt-Aufrufe. Die sechs
-- Pflichtmethoden stehen unten in der Rückgabe von Attach; ihre Bedeutung steht im
-- Workshop-Repo unter docs/KAIJU_STAGE_1_RELEASE.md.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Die aufsteigende Schadenszahl. Dasselbe Ereignis, das auch CombatHandler, HouseHandler
-- und SpecialAttackHandler benutzen -- eine Zahl, ein Weg.
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils", 10))
local ShowDamageEvent = RemoteEventUtils.GetOrCreate("ShowDamageEvent")

-- Nur für die Frage, ob ein Haus Abschnitt eines grösseren Bauwerks ist. Mit Zeitgrenze und
-- pcall: fehlt das Modul, wird eben nicht angehoben -- das ist die sichere Seite.
local ParentGroupService = nil
do
	local module = ServerScriptService:WaitForChild("ParentGroupService", 10)
	if module then
		local ok, loaded = pcall(require, module)
		ParentGroupService = ok and loaded or nil
	end
	if not ParentGroupService then
		warn("[KaijuStageOneCombatAdapter] ParentGroupService nicht ladbar -- der Finisher hebt "
			.. "vorsichtshalber gar keine Gebaeude an.")
	end
end

local KaijuStageOneCombatAdapter = {}

-- ===== Schadensfaktoren auf das Damage-Attribut der Figur =====
-- Die Dreierkombo entspricht bewusst dem, was der normale Angriff heute leistet: Schritt 3
-- trägt denselben Aufschlag wie der dritte Schlag im AttackClient. Sonst wäre allein der
-- Wechsel auf das neue Modell eine Balance-Änderung, ohne dass jemand daran gedreht hätte.
local COMBO_FACTORS = { 1.0, 1.0, nil } -- Schritt 3 wird unten aus _G gefüllt
local FINISHER_FACTOR = 3.0 -- Schritt 4: der Abschluss der Kombo
local LANDING_FACTOR = 2.0 -- Sprungangriff auf ein Gebäude
-- Für Fokus und Fläche stehen hier bewusst KEINE Faktoren: die beiden gehören dem
-- SpecialAttackHandler des Spiels, dieser Adapter steuert dort nur die Bewegung bei.

-- Reichweiten. Beide skalieren mit der tatsächlichen Grösse des Modells statt mit einer
-- festen Studzahl -- die Figur wächst über die Stufen mit.
-- Zuschlag auf die gemessene Armlänge: die Faust sitzt hinter dem Handgelenk, und ein
-- Schlag, der exakt an der Fingerspitze endet, fühlt sich unfair an. Ein Viertel mehr.
local MELEE_REACH_FACTOR = 1.25
-- Nur der Notnagel, falls die Armgelenke im Modell nicht zu finden sind: Anteil der
-- Figurenhöhe. Grob an der gemessenen Armlänge der ersten Stufe ausgerichtet.
local MELEE_REACH_FROM_HEIGHT = 0.4
local FOCUS_RANGE_FACTOR = 8.0 -- nur fürs Zielen des Strahls, nicht für Schaden

-- Wie weit der Strahl seitlich vom Blick abweichen darf (Punktprodukt).
local FOCUS_AIM_DOT = 0.5

-- ===== Hüllquader-Abstand =====
-- Dieselbe Rechnung wie in CombatHandler.distanceToHouse, inklusive der Absicherung gegen
-- entartete Hüllquader: waehrend der Einsturz-Animation entfernt HouseHandler Teile, und
-- GetBoundingBox liefert dann kurzzeitig negative oder NaN-Grössen. math.clamp stürzt
-- damit ab ("max must be >= min"), deshalb gilt das Haus in diesem Fenster als unerreichbar.
local function closestPointOn(model, position)
	local ok, cframe, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return nil, math.huge
	end

	local half = size / 2
	if half.X < 0 or half.Y < 0 or half.Z < 0
		or half.X ~= half.X or half.Y ~= half.Y or half.Z ~= half.Z then
		return nil, math.huge
	end

	local localPosition = cframe:PointToObjectSpace(position)
	local clamped = Vector3.new(
		math.clamp(localPosition.X, -half.X, half.X),
		math.clamp(localPosition.Y, -half.Y, half.Y),
		math.clamp(localPosition.Z, -half.Z, half.Z)
	)
	local point = cframe:PointToWorldSpace(clamped)
	return point, (position - point).Magnitude
end

-- ===== Heben und Zurücklegen =====
-- Beides arbeitet ausschliesslich über die Attribute, die HouseHandler.initHouse an jedem
-- Teil hinterlegt hat. Nichts wird gemerkt, was nicht ohnehin am Haus steht -- deshalb ist
-- das Zurücklegen auch dann noch richtig, wenn zwischendurch etwas schiefgegangen ist.
local function setHouseLifted(house, lifted)
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") then
			if lifted then
				part.CanCollide = false
				part.CanQuery = false
			else
				local originalCollide = part:GetAttribute("OriginalCanCollide")
				part.CanCollide = (originalCollide == nil) or originalCollide
				part.CanQuery = true
			end
		end
	end
end

-- Setzt jedes Teil auf seine gespeicherte Ausgangslage. Dieselbe Rechnung wie am Ende von
-- HouseHandler.growHouseFromGround -- dort nach dem Einsturz, hier nach dem Heben.
local function returnHouseHome(house)
	if not house or not house.Parent then
		return
	end
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") then
			local originalCFrame = part:GetAttribute("OriginalCFrame")
			if originalCFrame then
				part.CFrame = originalCFrame
			end
		end
	end
	setHouseLifted(house, false)
end

-- Der Mittelpunkt eines Ziels -- egal ob Modell oder einzelnes Teil.
--
-- Gebäude sind Models und haben GetBoundingBox. Das Trainingsziel an der Bein-Station ist
-- ein einzelner Part und hat das NICHT -- ein Aufruf darauf schlägt fehl. Genau daran
-- scheitert auch der Versuch, dem Teil einfach den KaijuHouse-Tag zu geben.
local function targetCenter(target)
	if target:IsA("BasePart") then
		return target.Position
	end
	local ok, cframe = pcall(function()
		return target:GetBoundingBox()
	end)
	return ok and cframe and cframe.Position or nil
end

-- Das Ziel der Bein-Trainingsstation. Dieselbe Suche wie in
-- SpecialAttackHandler.findFocusTarget -- dort ist sie die Wahrheit, hier wird nur
-- dasselbe Teil gefunden, damit das Rig etwas zum Anvisieren hat.
--
-- Es nimmt KEINEN Schaden: der Fokus dieses Adapters richtet grundsätzlich keinen an (das
-- macht der SpecialAttackHandler). Das Ziel dient hier ausschliesslich dazu, dass das Rig
-- den Fokus überhaupt beginnt -- ohne Ziel verweigert es ihn wortlos, und an der Station
-- stand die Figur deshalb still.
local function trainingFocusTarget(player)
	if not player or player:GetAttribute("TrainingStat") ~= "Leg" then
		return nil
	end
	local station = Workspace:FindFirstChild("LegTrainingStation", true)
	local laserTarget = station and station:FindFirstChild("LaserTarget", true)
	if laserTarget and laserTarget:IsA("BasePart") then
		return laserTarget
	end
	return nil
end

local function isDamageable(house)
	return house
		and house.Parent
		and house:IsDescendantOf(Workspace)
		and house:GetAttribute("Destroyed") ~= true
		and (house:GetAttribute("Health") or 0) > 0
end

local function taggedHouses()
	local tag = _G.HOUSE_TAG or "KaijuHouse"
	return CollectionService:GetTagged(tag)
end

-- Die Energiefarbe der Figur. Dieselbe, die auch die Darstellung des Pakets benutzt
-- (KaijuPresentation, focusColor) -- Entladung und Fokus sollen aus derselben Quelle
-- stammen und nicht wie zwei verschiedene Kräfte aussehen.
local ENTLADUNG_FARBE = Color3.fromRGB(65, 225, 255)

local function neonPart(name, size, cframe, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = Workspace
	return part
end

-- ===== Die Entladung, auch ohne das Rig =====
-- Das Rig VERWEIGERT den Flächenangriff, wenn der Boden unter der Figur steiler als etwa
-- 45 Grad ist oder zu weit weg (KaijuStageOneRig: `hit.Normal.Y < 0.7`). Auf einem
-- Schrägdach oder einem Hang ruft es deshalb nie AreaImpact -- die Bewegung bleibt aus.
--
-- Der Schaden des Spiels fällt trotzdem, er hängt nicht am Rig. Übrig blieb ein Angriff
-- ohne Bild, und das Spiel sprang mit seiner alten gelben Ladekugel ein: dieselbe Taste,
-- zwei völlig verschiedene Erscheinungen, je nachdem, wie schräg der Boden gerade war.
--
-- Deshalb ist die Entladung von hier aus AUCH ohne das Rig auslösbar. Der
-- SpecialAttackHandler ruft sie, wenn zur Einschlagzeit keine Rig-Phase läuft. Was dann
-- fehlt, ist allein die Körperbewegung -- der Einschlag sieht aus wie immer.
local areaDischargeByModel = setmetatable({}, { __mode = "k" })

-- Dieselbe Überlegung fürs Maul: der SpecialAttackHandler setzt den Strahl des Spiels dort
-- an, statt am Kopf des versteckten Avatars.
local mouthByModel = setmetatable({}, { __mode = "k" })

function KaijuStageOneCombatAdapter.GetMouthPosition(kaiju)
	local finder = kaiju and mouthByModel[kaiju]
	if not finder then
		return nil
	end
	local ok, position = pcall(finder)
	if not ok or typeof(position) ~= "Vector3" then
		return nil
	end
	return position
end

function KaijuStageOneCombatAdapter.PlayAreaDischarge(kaiju, origin)
	local discharge = kaiju and areaDischargeByModel[kaiju]
	if not discharge then
		return false
	end
	local ok, err = pcall(discharge, origin)
	if not ok then
		warn(string.format("[Kaiju Debug] Ersatz-Entladung fehlgeschlagen: %s", tostring(err)))
		return false
	end
	return true
end

-- ===== Das Modell über den Rumpf rücken =====
-- Der Bauplan setzt die Figur mittig auf ihren Ursprung, und der Installer bildet diesen
-- Ursprung auf den Punkt unter dem Rumpf ab. Dazwischen liegt aber eine Zeile, die alles
-- verschiebt (KaijuEvolutionBlockout, Ende von buildStage):
--
--   model:ScaleTo(model:GetScale() * (targetHeight / unscaledSize.Y))
--   model:PivotTo(model:GetPivot() + Vector3.new(0, origin.Position.Y - bottomY, 0))
--
-- `ScaleTo` skaliert um den Pivot, und das ist hier die Mitte des Hüllquaders -- die wegen
-- des langen Schwanzes weit HINTER dem Ursprung liegt. Ein Punkt wandert dabei nach
-- `mitte + s * (punkt - mitte)`, der Ursprung also nach `mitte * (1 - s)`. Die Zeile darunter
-- holt nur die HÖHE zurück; die waagrechte Verschiebung bleibt stehen.
--
-- Draussen ist der Baumassstab 1, `s` also fast 1 und die Verschiebung fast null. Im
-- Sanctuary ist er 0.5 -- dort landet die Figur mehrere Studs hinter ihrem eigenen
-- Standpunkt. Man steuert dann sichtbar etwas Unsichtbares vor sich her: der Spawnpunkt,
-- die Unverwundbarkeitskugel und die Kollision sitzen am Rumpf, die Figur dahinter.
--
-- Hier wird das gerade gezogen, und zwar GENAU an dieser Stelle: der Installer ruft diese
-- Fabrik, nachdem er das Modell gebaut und gesetzt hat, aber BEVOR Rig.Attach die Lage von
-- Rumpf und Becken zueinander einfriert. Später korrigiert wäre zu spät -- dann stünde die
-- alte Verschiebung schon in den Ruhelagen und im Motor6D der Darstellung.
--
-- Gemessen wird an den Fußsohlen, nicht am Hüllquader: wo die Figur steht, ist die Frage,
-- und der Schwanz zieht jeden Hüllquader nach hinten.
local function centreOverRoot(kaiju, root)
	local left = kaiju:FindFirstChild("LeftForefootCoreY")
	local right = kaiju:FindFirstChild("RightForefootCoreY")
	if not (left and right and left:IsA("BasePart") and right:IsA("BasePart")) then
		return
	end

	local stand = (left.Position + right.Position) * 0.5
	local lokal = root.CFrame:PointToObjectSpace(stand)
	if math.abs(lokal.X) < 0.05 and math.abs(lokal.Z) < 0.05 then
		return -- steht schon richtig; nichts anfassen
	end

	local delta = -root.CFrame:VectorToWorldSpace(Vector3.new(lokal.X, 0, lokal.Z))
	kaiju:PivotTo(CFrame.new(delta) * kaiju:GetPivot())

	print(string.format(
		"[Kaiju Debug] Modell waagrecht ausgerichtet -- war %.2f seitlich / %.2f hinter dem Rumpf.",
		lokal.X, lokal.Z))
end

function KaijuStageOneCombatAdapter.Attach(kaiju, root, humanoid, rootHeight)
	local player = Players:GetPlayerFromCharacter(kaiju.Parent)

	centreOverRoot(kaiju, root)

	-- Die eigene Grösse EINMAL beim Anhängen messen. Sie ändert sich nicht mehr: der
	-- Installer baut das Modell auf die zum Zeitpunkt der Installation gültige Skalierung,
	-- und ein Stufenwechsel baut es ohnehin neu auf.
	-- ===== Wie weit der Schlag reicht =====
	-- Hier stand die Grundfläche des Hüllquaders, `max(size.X, size.Z)`. Beim Kaiju ist
	-- size.Z der SCHWANZ: er reicht im Bauplan bis Z = 19.7, der Kopf bis etwa -9. Die
	-- Reichweite lag damit bei rund dem Vierfachen der Armlänge -- die Faust ging sichtbar
	-- ins Leere, und trotzdem fiel Schaden samt Schadenszahl.
	--
	-- Gemessen wird deshalb der Arm selbst: Schulter zu Ellbogen zu Handgelenk, plus der
	-- Abstand der Schulter vom Rumpf, plus ein Zuschlag für Faust und etwas Nachsicht. Das
	-- stimmt für jede Stufe von selbst, weil es dieselbe Geometrie misst, die man sieht.
	--
	-- Die Gelenkteile sind Namen aus dem Asset-Paket. Fehlen sie, wird aus der Höhe
	-- geschätzt -- lieber ein grober Wert als eine Reichweite von null.
	local meleeReach, focusRange, bodySpan
	do
		local ok, _, size = pcall(function()
			return kaiju:GetBoundingBox()
		end)
		local height = (ok and size) and size.Y or 30

		-- Für Effektgrössen (Entladung, Licht): dort ist die Ausdehnung der Figur gemeint,
		-- nicht die Schlagweite. Die beiden liefen vorher über dieselbe Zahl.
		bodySpan = (ok and size) and math.max(size.X, size.Z) or 12
		focusRange = bodySpan * FOCUS_RANGE_FACTOR

		meleeReach = height * MELEE_REACH_FROM_HEIGHT

		local function jointPosition(name)
			local part = kaiju:FindFirstChild(name, true)
			return part and part:IsA("BasePart") and part.Position or nil
		end
		local shoulder = jointPosition("RightShoulderJoint")
		local elbow = jointPosition("RightElbowJoint")
		local wrist = jointPosition("RightWristJoint")
		if shoulder and elbow and wrist then
			local armLength = (shoulder - elbow).Magnitude + (elbow - wrist).Magnitude
			local shoulderOffset = math.abs(root.CFrame:PointToObjectSpace(shoulder).Z)
			meleeReach = shoulderOffset + armLength * MELEE_REACH_FACTOR
		end

		print(string.format("[Kaiju Debug] Schlagreichweite %.1f (Figurenhoehe %.1f, "
			.. "Ausdehnung %.1f).", meleeReach, height, bodySpan))
	end

	-- Das für den Finisher vorgemerkte Gebäude. Nur EIN Eintrag: das Rig fragt genau ein
	-- Ziel an, und zwei gleichzeitig vorgemerkte Gebäude wären nicht mehr auflösbar.
	local reserved = nil
	local finisherCue = nil

	local function baseDamage()
		local character = kaiju.Parent
		local damage = (character and character:GetAttribute("Damage")) or 10
		-- Berserk gilt hier genauso wie beim normalen Angriff -- sonst wäre der Modus mit
		-- dem neuen Modell wirkungslos.
		local multiplier = (player and _G.GetBerserkerDamageMultiplier and _G.GetBerserkerDamageMultiplier(player)) or 1.0
		return damage * multiplier
	end

	local function clearCue()
		if finisherCue then
			finisherCue:Destroy()
			finisherCue = nil
		end
		kaiju:SetAttribute("FinisherAvailable", false)
	end

	-- Das Gebäude, das GERADE in den Händen liegt, samt der Schleife, die es dort hält.
	local held = nil
	local holdConnection = nil

	local function releaseHold(restore)
		if holdConnection then
			holdConnection:Disconnect()
			holdConnection = nil
		end
		local house = held
		held = nil
		if house and restore then
			returnHouseHome(house)
		end
	end

	local function cancel()
		releaseHold(true)
		reserved = nil
		clearCue()
	end

	-- ===== Die Handstellung während eines Angriffs =====
	-- Zwei Wege, weil das Paket seinen gerade wechselt -- und dieser Adapter soll an beiden
	-- Ständen funktionieren, statt bei jedem Auf und Ab mitgeändert zu werden.
	--
	-- Bis einschliesslich 1.2.x animiert der SERVER die Figur. Die Handteile im
	-- "Articulation"-Ordner stehen dann tatsächlich dort, wo man sie sieht.
	--
	-- Ab 1.3.0 wird auf den CLIENTS animiert; die Gelenke auf dem Server bleiben in
	-- Ruhelage. Dieselben Teile auszulesen lieferte dann die Grundhaltung statt der
	-- Angriffsstellung, und ein gehobenes Gebäude hinge an der falschen Stelle. Für diesen
	-- Fall benennt das Modell einen PoseProvider, den man stattdessen fragen muss.
	--
	-- Der PoseProvider gewinnt, wenn es ihn gibt. Sonst die Teile. Damit ist der Wechsel
	-- zwischen den Paketständen für diesen Adapter kein Ereignis mehr.
	local function combatFrame(boneName)
		local providerValue = kaiju:FindFirstChild("KaijuPoseProvider")
		if providerValue and providerValue.Value then
			local ok, frame = pcall(function()
				return require(providerValue.Value).GetCombatFrame(kaiju, boneName)
			end)
			if ok and frame then
				return frame
			end
			return nil
		end

		local joints = kaiju:FindFirstChild("Articulation")
		local bone = joints and joints:FindFirstChild(boneName)
		return bone and bone.CFrame or nil
	end

	-- Hebt das vorgemerkte Gebäude zwischen die Hände des Rigs. Fehlen die Handstellungen,
	-- wird nicht gehoben; ein Gebäude, das im Nichts schwebt, wäre schlimmer als keines.
	--
	-- Die Schleife bricht von selbst ab, sobald etwas nicht mehr stimmt: Figur tot, Haus
	-- weg, Spieler zu weit gelaufen, zu lange her. Ohne diese Abbrüche bliebe ein Gebäude
	-- am Himmel hängen, wenn der Finisher aus irgendeinem Grund nie einschlägt.
	local LIFT_SECONDS_MAX = 2.5
	local LIFT_DRIFT_MAX = 12

	local function liftHouse(house)
		if not combatFrame("LeftHand") or not combatFrame("RightHand") or not isDamageable(house) then
			return false
		end

		held = house
		setHouseLifted(house, true)

		local startedAt = os.clock()
		local startPosition = root.Position
		local initialPivot = house:GetPivot()

		holdConnection = RunService.Heartbeat:Connect(function()
			if held ~= house
				or not house.Parent
				or humanoid.Health <= 0
				or os.clock() - startedAt > LIFT_SECONDS_MAX
				or (root.Position - startPosition).Magnitude > LIFT_DRIFT_MAX
			then
				cancel()
				return
			end

			-- Weich in die Hände gleiten statt zu springen: der erste Moment des Griffs ist
			-- der, in dem man sieht, ob es echt aussieht.
			local t = math.clamp((os.clock() - startedAt) / 0.3, 0, 1)
			t = t * t * (3 - 2 * t)
			local leftFrame = combatFrame("LeftHand")
			local rightFrame = combatFrame("RightHand")
			if not leftFrame or not rightFrame then
				cancel()
				return
			end
			local grip = (leftFrame.Position + rightFrame.Position) / 2
			local ziel = CFrame.new(grip) * root.CFrame.Rotation
			house:PivotTo(initialPivot:Lerp(ziel, t))
		end)

		return true
	end

	-- Zwei auseinanderfliegende Hälften -- aus KOPIEN der sichtbaren Teile, nicht aus dem
	-- Gebäude selbst. Das echte geht gleichzeitig den normalen Zerstörungsweg.
	--
	-- Geteilt wird an der Mitte, quer zur Blickrichtung: was rechts von der Mitte liegt,
	-- fliegt nach rechts. Ein Schnitt entlang einer Achse ist grob, aber er liest sich als
	-- "auseinandergerissen" -- und anders als eine Teilchen-Wolke behält jede Hälfte ihre
	-- Form.
	local function tearApart(house)
		local ok, center = pcall(function()
			return (house:GetBoundingBox())
		end)
		if not ok or not center then
			return
		end

		local right = root.CFrame.RightVector
		local stuecke = 0
		for _, part in ipairs(house:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 1 and stuecke < 60 then
				stuecke += 1
				local kopie = part:Clone()
				kopie.Name = "TornBuildingHalf"
				kopie:ClearAllChildren()
				kopie.Anchored = true
				kopie.CanCollide = false
				kopie.CanQuery = false
				kopie.CanTouch = false
				kopie.CastShadow = false
				kopie.Parent = Workspace

				-- Die Seite entscheidet die Richtung. Genau in der Mitte liegende Teile
				-- werden willkürlich nach rechts geschoben -- besser als stehenzubleiben.
				local seite = (part.Position - center.Position):Dot(right) >= 0 and 1 or -1
				local ziel = CFrame.new(right * (seite * 16) + Vector3.new(0, 4, 0))
					* kopie.CFrame
					* CFrame.Angles(0, 0, -seite * 0.5)

				TweenService:Create(kopie, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = ziel }):Play()
				task.delay(0.45, function()
					if kopie.Parent then
						TweenService:Create(kopie, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{ CFrame = CFrame.new(0, -30, 0) * ziel, Transparency = 1 }):Play()
					end
				end)
				Debris:AddItem(kopie, 1.4)
			end
		end
	end

	-- Ein Gebäude ist erreichbar, wenn es VOR der Figur steht (lokales Z negativ) und der
	-- nächste Punkt seines Hüllquaders innerhalb der Schlagweite liegt.
	local function reachable(house)
		if not isDamageable(house) then
			return nil
		end
		local point, distance = closestPointOn(house, root.Position)
		if not point or distance > meleeReach then
			return nil
		end
		local relative = root.CFrame:PointToObjectSpace(point)
		if relative.Z > 0 then
			return nil -- steht hinter der Figur
		end
		return point, distance
	end

	-- ===== Die Verteidigung ist auch ein Ziel =====
	-- Dieser Adapter kannte nur Gebäude. Alles andere -- Feuerwehr, Barrikadenschild,
	-- Generator -- war für den Nahkampf unsichtbar, und da mit einem Kaiju JEDER Schlag über
	-- diesen Adapter läuft, machten Schlag und Sprung dort schlicht keinen Schaden. Übrig
	-- blieb der Flächenangriff, der seinen eigenen Weg geht (SpecialAttackHandler) und die
	-- drei Systeme kennt.
	--
	-- Eine Verteidigungsstufe, gegen die nur ein einziger Angriff hilft, ist keine
	-- Entscheidung mehr. Deshalb hier dieselben drei Eingänge, die auch der alte
	-- Kampfweg (CombatHandler) benutzt.
	--
	-- Zurück kommt Punkt, Entfernung und eine Funktion, die den Schaden anwendet -- so bleibt
	-- die Auswahl von der Anwendung getrennt und der Aufrufer muss nicht wissen, WAS er
	-- gerade trifft.
	local function nearestDefence()
		local bestPoint, bestDistance, bestApply = nil, math.huge, nil

		local function betrachte(model, apply)
			local point, distance = closestPointOn(model, root.Position)
			if not point or distance > meleeReach or distance >= bestDistance then
				return
			end
			if root.CFrame:PointToObjectSpace(point).Z > 0 then
				return -- steht hinter der Figur, wie bei den Gebäuden
			end
			bestPoint, bestDistance, bestApply = point, distance, apply
		end

		if _G.FIRE_ENGINE_TAG and _G.DamageFireEngine then
			for _, engine in ipairs(CollectionService:GetTagged(_G.FIRE_ENGINE_TAG)) do
				if not engine:GetAttribute("Destroyed") then
					betrachte(engine, function(amount)
						_G.DamageFireEngine(engine, amount, player)
					end)
				end
			end
		end

		-- Das Schild nur, solange es steht: ist es unten, wird die Barrikade regulär
		-- angreifbar und zählt dann als gewöhnliches Hindernis.
		if _G.DamageBarricadeShield and _G.GetClusterIdForModel then
			for _, barricade in ipairs(CollectionService:GetTagged("Barricade")) do
				if barricade:GetAttribute("ShieldEnabled") ~= false then
					local clusterId, cityName = _G.GetClusterIdForModel(barricade)
					if clusterId and cityName then
						betrachte(barricade, function(amount)
							_G.DamageBarricadeShield(cityName, clusterId, amount, player)
						end)
					end
				end
			end
		end

		if _G.DamageGenerator and _G.GetGeneratorsInRange then
			for _, treffer in ipairs(_G.GetGeneratorsInRange(root.Position, meleeReach)) do
				local teil = treffer.part or treffer.instance
				if teil then
					local abstand = (teil.Position - root.Position).Magnitude
					if abstand < bestDistance
						and root.CFrame:PointToObjectSpace(teil.Position).Z <= 0 then
						bestPoint, bestDistance = teil.Position, abstand
						bestApply = function(amount)
							_G.DamageGenerator(treffer.cityName, treffer.clusterId, treffer.side, amount, player)
						end
					end
				end
			end
		end

		return bestPoint, bestDistance, bestApply
	end

	local function nearestReachable()
		local bestHouse, bestPoint, bestDistance = nil, nil, math.huge
		for _, house in ipairs(taggedHouses()) do
			local point, distance = reachable(house)
			if point and distance < bestDistance then
				bestHouse, bestPoint, bestDistance = house, point, distance
			end
		end
		return bestHouse, bestPoint
	end

	-- Das Gebäude, auf dem die Figur gerade steht -- für den Landeschaden. Bewusst ein
	-- Strahl nach UNTEN und nicht der Schlagkegel nach vorn: gelandet wird auf dem Dach,
	-- auf dem man steht, nicht auf dem Haus davor.
	local function landingTarget()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { kaiju.Parent }
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -(rootHeight + 6), 0), params)
		if not hit then
			return nil
		end
		local instance = hit.Instance
		local tag = _G.HOUSE_TAG or "KaijuHouse"
		while instance and instance ~= Workspace do
			if instance:IsA("Model") and CollectionService:HasTag(instance, tag) then
				return isDamageable(instance) and instance or nil, hit.Position
			end
			instance = instance.Parent
		end
		return nil
	end

	-- Der einzige Weg, auf dem dieser Adapter Schaden macht. Der Rückgabewert sagt, ob
	-- TATSÄCHLICH Schaden angekommen ist: _G.DamageHouse steigt still aus, wenn ein
	-- Barrikaden-Schild oder ein Guardian das Gebäude deckt. Ohne diesen Vergleich meldete
	-- der Adapter einen Treffer, obwohl der Schlag abgeprallt ist.
	-- ===== Die Schadenszahl gehört zum Treffer =====
	-- `_G.DamageHouse` zeigt selbst nichts an: es rechnet den Schaden an und löst alles
	-- daran Hängende aus (Coins, Energie, Erfahrung, Alarm, Einsturz, Respawn). Die
	-- aufsteigende Zahl über dem Treffer ist Sache des Aufrufers -- CombatHandler,
	-- HouseHandler und SpecialAttackHandler feuern sie jeweils selbst.
	--
	-- Dieser Adapter tat das nicht, und damit war der Nahkampf der einzige Angriff im Spiel
	-- ohne Rückmeldung: es fiel Schaden, aber man sah keine Zahl.
	local function applyDamage(house, amount, point)
		if not _G.DamageHouse or not isDamageable(house) then
			return false
		end
		local before = house:GetAttribute("Health") or 0
		_G.DamageHouse(house, amount, player, point)
		local after = house:GetAttribute("Health") or 0

		local hit = after < before
		if hit and player then
			ShowDamageEvent:FireClient(player, math.floor(before - after + 0.5))
		end
		return hit
	end

	local function markHit(hit)
		kaiju:SetAttribute("LastAttackResult", hit and "Hit" or "Miss")
		return hit
	end

	-- Bietet den Finisher an, sobald ein Gebäude in Schlagweite mit dem nächsten Schlag
	-- fallen würde. Der Leuchtrahmen verschwindet mit der Frist, die das Rig mitgibt --
	-- kein zweiter Zeitgeber, sonst laufen Anzeige und Fenster auseinander.
	local function offerFinisher(house, deadline)
		if type(deadline) ~= "number" or deadline <= os.clock() then
			return
		end
		if (house:GetAttribute("Health") or 0) > baseDamage() * FINISHER_FACTOR then
			return
		end

		clearCue()
		local highlight = Instance.new("Highlight")
		highlight.Name = "KaijuFinisherCue"
		highlight.FillColor = Color3.fromRGB(255, 225, 60)
		highlight.OutlineColor = Color3.fromRGB(255, 235, 100)
		highlight.FillTransparency = 0.4
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = house
		highlight.Parent = house
		finisherCue = highlight
		reserved = house
		kaiju:SetAttribute("FinisherAvailable", true)

		task.delay(math.max(0, deadline - os.clock()), function()
			if finisherCue == highlight then
				clearCue()
				reserved = nil
			end
		end)
	end

	-- ===== Gezielt wird auf die MITTE, nicht auf die Oberfläche =====
	-- Hier lag der Fehler, wegen dem der Fokus nie startete.
	--
	-- Vorher ging der Strahl vom Maul zum nächstgelegenen Punkt des Hüllquaders -- also
	-- exakt auf dessen Oberfläche. Ein Strahl, der genau dort endet, wo er treffen soll,
	-- trifft in der Gleitkomma-Arithmetik oft nicht mehr: er endet einen Hauch davor.
	-- Workspace:Raycast gab nil zurück, das Haus galt als nicht sichtbar, und weil das für
	-- JEDES Haus galt, lieferte die Zielsuche nie ein Ziel. Das Rig verweigert den Fokus
	-- ohne Ziel vollständig -- deshalb blieb es bei der alten Optik.
	--
	-- Jetzt geht der Strahl bis zur Mitte des Hüllquaders. Er muss die Oberfläche dabei
	-- durchstossen, der Treffer ist also eindeutig. Das macht der Adapter des Workshops
	-- genauso: er zielt auf die Position des Gebäudekörpers, nicht auf dessen Rand.
	local function focusAim(house, from)
		if not house or not house.Parent then
			return nil, false
		end
		-- Das Trainingsziel ist ein einzelnes Teil und hat keine Lebenspunkte -- die
		-- Zerstörbarkeit wird deshalb nur bei Gebäuden geprüft.
		if not house:IsA("BasePart") and not isDamageable(house) then
			return nil, false
		end

		local center = targetCenter(house)
		if not center then
			return nil, false
		end

		local delta = center - from
		if delta.Magnitude > focusRange then
			return nil, false
		end
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude < 0.01 or flat.Unit:Dot(root.CFrame.LookVector) < FOCUS_AIM_DOT then
			return nil, false
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { kaiju.Parent }
		local hit = Workspace:Raycast(from, delta, params)

		-- Der zurückgegebene Punkt ist der Einschlag, nicht die Mitte: dort soll der Strahl
		-- aufschlagen, also an der Aussenwand, die man sieht.
		--
		-- Und die Treffer-Prüfung muss den Fall mitnehmen, dass das Ziel SELBST getroffen
		-- wird. IsDescendantOf ist bei einem Objekt auf sich selbst FALSCH -- bei einem
		-- Gebäude (Model) trifft der Strahl ein Kindteil und alles passt, beim Trainingsziel
		-- (ein einzelner Part) trifft er das Ziel selbst, und die Prüfung sagte "nicht
		-- sichtbar". Genau daran ist der Fokus an der Bein-Station gescheitert.
		local getroffen = hit ~= nil and (hit.Instance == house or hit.Instance:IsDescendantOf(house))
		return hit and hit.Position or center, getroffen
	end

	-- ===== Wo das Maul gerade ist =====
	-- Dieselbe Rechnung wie im Rig (KaijuStageOneRig, mouth()): die Kopfstellung, darauf die
	-- Ruhelage des Oberkiefers, und von dort an die Schnauzenspitze. Sie muss hier stehen,
	-- weil das Rig sie nur dann verrät, wenn es den Fokus auch wirklich spielt -- und genau
	-- dann, wenn es das NICHT tut, wird sie hier gebraucht.
	--
	-- Fehlt eines der Teile, kommt der Kopf zurück statt eines geratenen Punktes. Ein Effekt
	-- am Kopf sitzt etwas zu weit hinten; ein Effekt am Rumpf sah aus, als käme der Strahl
	-- aus dem Knie.
	local function mouthPosition()
		local head = combatFrame("Head")
		if not head then
			return root.Position
		end
		local upper = kaiju:FindFirstChild("UpperMuzzleCoreY")
		local upperLocal = upper and upper:GetAttribute("RigLocalFrame")
		local muzzleZ = kaiju:FindFirstChild("UpperMuzzleCoreZ")
		if not upper or not muzzleZ or typeof(upperLocal) ~= "CFrame" then
			return head.Position
		end
		local scale = kaiju:GetScale()
		return (head * upperLocal
			* CFrame.new(0, -upper.Size.Y / 2 - 0.2 * scale, muzzleZ.Size.Z * 0.25)).Position
	end

	-- ===== Der Fehlschuss =====
	-- Findet auch das Spiel kein Ziel, spielt das Rig nichts: es fragt seinen Adapter, worauf
	-- es zielen soll, und eine leere Antwort ist für es das Ende der Angelegenheit.
	--
	-- Es liesse sich überlisten -- ein unsichtbarer Markierungspunkt im Leeren, und die volle
	-- Fokus-Darstellung des Pakets läuft. Das war der erste Versuch, und er war zu viel: das
	-- Rig feuert immer 2.85 Sekunden lang und immer mit voller Strahlbreite. Beides steht
	-- fest im Paket (KaijuStageOneRig: `age>=4.85`, KaijuPresentation: `focusOuterWidth`),
	-- ist kein Attribut und von hier aus nicht erreichbar. Ein Fehlschuss, der so lange und
	-- so breit brennt wie ein Treffer, sieht nicht nach Fehlschuss aus.
	--
	-- Deshalb hier eine eigene, kurze Fassung. Sie behält das Wesentliche -- die Energie
	-- sammelt sich über den Rückenplatten und wandert ans Maul -- und bricht dann rasch mit
	-- einem dünnen Strahl ab. Was ihr fehlt, ist die Körperbewegung; die kann nur das Rig.
	-- Sobald der Workshop einen Trockenschuss anbietet, fliegt das hier wieder raus.
	local MISS_LADEZEIT = 2 -- gleich der Aufladezeit des Spiels, damit der Ladeklang passt
	local MISS_STRAHLZEIT = 0.5
	local MISS_STRAHLDICKE = 0.35 -- gegen 3.10 des Rigs: bewusst ein Faden, kein Balken

	local missLauf = 0

	local function playFocusMiss()
		missLauf += 1
		local meinLauf = missLauf

		-- Der Client erfährt hierüber, dass er seinen eigenen Ersatzstrahl weglassen soll.
		-- Ein Zeitstempel statt eines Schalters: bricht hier etwas ab, verfällt er von selbst.
		kaiju:SetAttribute("AdapterFocusMissAt", Workspace:GetServerTimeNow())

		task.spawn(function()
			local scale = kaiju:GetScale()

			-- Die Maulkugel wächst über die Aufladung und folgt dabei dem Maul -- die Figur
			-- läuft und dreht sich ja weiter.
			local orb = neonPart("FocusMissCharge", Vector3.new(0.1, 0.1, 0.1),
				CFrame.new(mouthPosition()), ENTLADUNG_FARBE)
			orb.Shape = Enum.PartType.Ball
			orb.Transparency = 0.15

			local licht = Instance.new("PointLight")
			licht.Color = ENTLADUNG_FARBE
			licht.Brightness = 3
			licht.Range = math.max(24, bodySpan * 0.5)
			licht.Parent = orb

			-- Eine Welle Funken von den Rückenplatten zum Maul. Dreimal während der
			-- Aufladung, damit es strömt statt einmal zu blinken.
			local function ruckenWelle()
				local ziel = mouthPosition()
				for index = 1, 3 do
					local plate = kaiju:FindFirstChild(string.format("DorsalShield_%02d", index))
					if plate and plate:IsA("BasePart") then
						local funke = neonPart("FocusMissIntake", Vector3.new(1, 1, 1) * (0.5 * scale),
							CFrame.new(plate.Position), ENTLADUNG_FARBE)
						funke.Shape = Enum.PartType.Ball
						funke.Transparency = 0.2
						TweenService:Create(funke, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							CFrame = CFrame.new(ziel),
							Size = Vector3.new(1, 1, 1) * (0.12 * scale),
							Transparency = 0.6,
						}):Play()
						Debris:AddItem(funke, 0.6)
					end
				end
			end

			local zielGroesse = 1.6 * scale
			local start = os.clock()
			local naechsteWelle = 0
			while os.clock() - start < MISS_LADEZEIT do
				if meinLauf ~= missLauf or humanoid.Health <= 0 or not orb.Parent
					or not root:IsDescendantOf(Workspace) then
					orb:Destroy()
					return
				end
				local fortschritt = (os.clock() - start) / MISS_LADEZEIT
				if fortschritt >= naechsteWelle then
					naechsteWelle += 0.33
					ruckenWelle()
				end
				local durchmesser = 0.2 + zielGroesse * fortschritt
				orb.Size = Vector3.new(durchmesser, durchmesser, durchmesser)
				orb.CFrame = CFrame.new(mouthPosition())
				licht.Brightness = 3 + 5 * fortschritt
				RunService.Heartbeat:Wait()
			end

			-- Und dann ein dünner Faden nach vorn, der sofort wieder ausgeht. Die Länge ist
			-- bewusst klein gegen die Reichweite eines echten Strahls: es soll nach einem
			-- Verpuffen aussehen, nicht nach einem Treffer, den man nur nicht sieht.
			local von = mouthPosition()
			local nach = von + root.CFrame.LookVector * math.max(bodySpan * 0.8, 20)
			local laenge = (nach - von).Magnitude
			local dicke = MISS_STRAHLDICKE * scale
			local strahl = neonPart("FocusMissBeam", Vector3.new(dicke, dicke, laenge),
				CFrame.new(von, nach) * CFrame.new(0, 0, -laenge / 2), ENTLADUNG_FARBE)

			TweenService:Create(orb, TweenInfo.new(MISS_STRAHLZEIT), {
				Size = Vector3.new(0.1, 0.1, 0.1),
				Transparency = 1,
			}):Play()
			TweenService:Create(licht, TweenInfo.new(MISS_STRAHLZEIT), { Brightness = 0 }):Play()
			TweenService:Create(strahl, TweenInfo.new(MISS_STRAHLZEIT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = Vector3.new(0.05, 0.05, laenge),
				Transparency = 1,
			}):Play()

			Debris:AddItem(orb, MISS_STRAHLZEIT + 0.1)
			Debris:AddItem(strahl, MISS_STRAHLZEIT + 0.1)
		end)
	end

	local function selectFocusTarget(from)
		-- ===== Das Spiel entscheidet, worauf gezielt wird =====
		-- Es ist dieselbe Suche, die gleich darauf den Schaden austeilt (SpecialAttackHandler,
		-- findFocusTarget). Damit kann das Rig gar nicht mehr zu einem anderen Schluss kommen
		-- als das Spiel -- und genau das war der Grund, warum bei entfernten Zielen, bei
		-- Zielen hinter einer Ecke und bei allem, was kein Gebäude ist (Feuerwehr, Militär,
		-- Guardian, Spieler in der Arena), der alte rote Strahl einsprang.
		--
		-- Die Bein-Trainingsstation ist darin enthalten: die Suche behandelt sie zuerst.
		--
		-- Zurück kommt ein Beschreibungssatz, kein Objekt. Das Rig will das Objekt: bei einem
		-- Gebäude das Modell, beim Trainingsziel den Part -- deshalb beides in dieser
		-- Reihenfolge.
		if _G.FindFocusTarget then
			local beschreibung = _G.FindFocusTarget(player, root)
			local ziel = beschreibung and (beschreibung.instance or beschreibung.trackPart)
			-- Ein Spieler ist kein Instanz-Ziel, sondern ein Player-Objekt. Für das Zielen
			-- zählt sein Rumpf.
			if ziel and ziel:IsA("Player") then
				ziel = beschreibung.trackPart
			end
			if ziel then
				return ziel
			end
			-- Kein Ziel: trotzdem aufladen und kurz ins Leere feuern (siehe playFocusMiss).
			playFocusMiss()
			return nil
		end

		-- ===== Ersatzweg, falls der Handler noch nicht geladen ist =====
		-- Nur für den Moment beim Serverstart, in dem SpecialAttackHandler seine Funktion
		-- noch nicht gesetzt hat. Die Regeln hier sind enger (siehe oben) -- besser eng als
		-- gar nicht.
		local training = trainingFocusTarget(player)
		if training then
			local _, visible = focusAim(training, from)
			if visible then
				return training
			end
		end

		local best, bestDistance = nil, math.huge
		local geprueft = 0
		for _, house in ipairs(taggedHouses()) do
			local point, visible = focusAim(house, from)
			geprueft += 1
			if visible then
				local distance = (point - from).Magnitude
				if distance < bestDistance then
					best, bestDistance = house, distance
				end
			end
		end

		-- Findet sich kein Ziel, verweigert das Rig den Fokus vollständig und setzt
		-- FocusPhase auf "No target" -- die Figur spielt dann gar keine Animation, während
		-- der Fokus des Spiels trotzdem auslöst. Von aussen sieht das aus, als sei die neue
		-- Animation nicht angeschlossen. Deshalb wird es hier gemeldet statt verschwiegen.
		if not best then
			print(string.format(
				"[Kaiju Debug] Fokus: kein Ziel in Sicht (%d Gebaeude geprueft, Reichweite %.0f, "
					.. "Blickwinkel-Schwelle %.2f). Das Rig spielt deshalb keine Fokus-Animation.",
				geprueft, focusRange, FOCUS_AIM_DOT))
		end
		return best
	end

	local function handle(kind, index, targetOrDeadline, from)
		if humanoid.Health <= 0 or not root:IsDescendantOf(Workspace) then
			cancel()
			return false
		end

		-- Greifen: das vorgemerkte Gebäude wandert in die Hände. Steht es nicht mehr in
		-- Reichweite, wird abgebrochen -- dann schlägt der Finisher ins Leere, statt ein
		-- Gebäude quer durch die Strasse zu ziehen.
		if kind == "Grab" then
			if reserved and reachable(reserved) and liftHouse(reserved) then
				return false
			end
			cancel()
			return false
		end

		if kind == "Land" then
			local house, point = landingTarget()
			if house then
				return markHit(applyDamage(house, baseDamage() * LANDING_FACTOR, point))
			end

			-- Auf etwas gelandet, das kein Gebäude ist -- die Verteidigung zählt auch hier.
			-- Ohne das war der Sprungangriff gegen Feuerwehr und Barrikade wirkungslos, und
			-- zwar unsichtbar: die Figur schlug ein, es passierte nichts.
			local _, _, abwehrSchaden = nearestDefence()
			if abwehrSchaden then
				local betrag = baseDamage() * LANDING_FACTOR
				abwehrSchaden(betrag)
				if player then
					ShowDamageEvent:FireClient(player, math.floor(betrag + 0.5))
				end
				return markHit(true)
			end
			return markHit(false)
		end

		-- ===== Fokus macht hier KEINEN Schaden =====
		-- Fokus und Fläche gehören dem Spiel, nicht dem Rig: der SpecialAttackHandler führt
		-- Energiekosten, Cooldown, Talentboni, Freischaltung, Schaden und Effekte. Das Rig
		-- steuert nur die Bewegung bei (siehe SpecialAttackClient.playKaijuSpecial).
		--
		-- Würde hier zusätzlich Schaden gerechnet, träfe jeder Spezialangriff doppelt --
		-- einmal über den Handler und einmal über diesen Adapter.
		--
		-- Gezielt wird trotzdem richtig: focusAim bleibt in Kraft, damit der Strahl auf ein
		-- echtes Gebäude zeigt und die Rückmeldung des Rigs (Treffer/Fehlschlag, Ton)
		-- stimmt.
		if kind == "Focus" then
			local house = targetOrDeadline
			local _, visible = focusAim(house, from or root.Position)
			return markHit(visible)
		end

		if kind ~= "Hit" then
			return false
		end

		-- Schritt 4 ist der Finisher: er trifft NUR das vorgemerkte Gebäude. Ohne diese
		-- Bindung könnte man sich während der Finisher-Animation wegdrehen und ein
		-- beliebiges anderes Haus mit dem starken Schlag treffen.
		local house, point
		if index == 4 then
			-- Liegt das Gebäude bereits in den Händen, gilt es als getroffen -- Reichweite
			-- neu zu prüfen wäre falsch, es ist ja mitgekommen.
			house = held or reserved
			if held then
				point = held:GetPivot().Position
			elseif house then
				point = reachable(house)
			end
			reserved = nil
			clearCue()
		else
			house, point = nearestReachable()
		end

		-- ===== An der Schmiede trifft jeder Schlag =====
		-- Dort steht der Amboss, nicht ein Gebäude -- der Adapter findet also nie ein Ziel
		-- und meldete jedes Mal einen Fehlschlag. Das Rig spielt daraufhin nur das
		-- Durchschneiden der Luft und keinen Aufschlag.
		--
		-- Schaden entsteht dabei keiner: hier wird nur der Treffer GEMELDET, damit Ton und
		-- Rückstoss des Rigs stimmen. Der Trainingsfortschritt läuft wie immer über
		-- TrainClickEvent.
		if not house and player and player:GetAttribute("TrainingStat") == "Arm" then
			return markHit(true)
		end

		-- ===== Kein Gebäude in Reichweite? Dann die Verteidigung =====
		-- Der Finisher (Schritt 4) bleibt aussen vor: er ist an ein vorgemerktes Gebäude
		-- gebunden, das er anhebt und zerreisst -- ein Feuerwehrauto in der Luft
		-- auseinanderzunehmen wäre eine eigene Animation und keine Kleinigkeit.
		--
		-- Vorrang hat das Nähere. Steht man vor einer Barrikade und schräg dahinter ein
		-- Haus, soll der Schlag die Barrikade treffen -- sonst schlüge die Figur durch die
		-- Wand, die sie gerade einreissen will.
		if index ~= 4 then
			local _, abwehrAbstand, abwehrSchaden = nearestDefence()
			if abwehrSchaden then
				local hausAbstand = point and (point - root.Position).Magnitude or math.huge
				if abwehrAbstand < hausAbstand then
					local faktor = (index == 3) and (_G.THIRD_PUNCH_DAMAGE_MULTIPLIER or 1.25)
						or (COMBO_FACTORS[index] or 1.0)
					local betrag = baseDamage() * faktor
					abwehrSchaden(betrag)
					if player then
						ShowDamageEvent:FireClient(player, math.floor(betrag + 0.5))
					end
					clearCue()
					return markHit(true)
				end
			end
		end

		if not house or not point then
			return markHit(false)
		end

		local factor
		if index == 4 then
			factor = FINISHER_FACTOR
		elseif index == 3 then
			factor = _G.THIRD_PUNCH_DAMAGE_MULTIPLIER or 1.25
		else
			factor = COMBO_FACTORS[index] or 1.0
		end

		-- ===== Reihenfolge beim gehobenen Gebäude =====
		-- Erst die Hälften aus der LUFT kopieren, dann das Gebäude zurücklegen, und erst
		-- danach den Schaden anwenden.
		--
		-- Andersherum ginge es nicht: _G.DamageHouse startet bei einem tödlichen Treffer
		-- sofort die Einsturz-Animation. Die tweent die echten Teile -- und das täte sie
		-- dann am Himmel, dort, wo das Gebäude gerade hängt. Legt man es hinterher zurück,
		-- kämpfen Tween und Zurücklegen um dieselben Teile.
		--
		-- So läuft der Einsturz dort ab, wo das Gebäude hingehört, und was man fliegen
		-- sieht, sind die Kopien.
		local warGehoben = (held == house)
		if warGehoben then
			local gesundheit = house:GetAttribute("Health") or 0
			if gesundheit <= baseDamage() * factor then
				tearApart(house)
			end
			returnHouseHome(house)
			releaseHold(false)
			-- Der Trefferpunkt muss mitwandern: er bestimmt, WO Einschlag-Effekte und die
			-- Meldung an den Helikopter entstehen. Der Punkt aus der Luft läge daneben.
			point = closestPointOn(house, root.Position) or point
		end

		local hit = applyDamage(house, baseDamage() * factor, point)

		-- Nach dem dritten Schlag entscheidet sich, ob der Finisher angeboten wird. Die
		-- Frist kommt aus der Animation des Rigs, nicht aus einer eigenen Zeitmessung.
		if hit and index == 3 and isDamageable(house) then
			offerFinisher(house, targetOrDeadline)
		end

		return markHit(hit)
	end

	-- ===== Der Flächenschlag: alle Effekte, kein Schaden =====
	-- Den Schaden führt der SpecialAttackHandler des Spiels (mit Kosten, Cooldown und
	-- Talentboni), hier wird deshalb keiner gerechnet -- sonst träfe ein Tastendruck
	-- doppelt.
	--
	-- Der SICHTBARE Einschlag gehört aber hierher, und das war ein Fehler von mir: beim
	-- Herausnehmen des Schadens ist der Effekt mit verschwunden. Das Rig spielt nur die
	-- Bewegung -- das Aufbäumen und das Aufstützen -- und ruft am Ende AreaImpact. Was
	-- dann zu sehen ist, liefert laut Vertrag der Adapter. Ohne ihn beugt sich die Figur
	-- zum Boden, und dann passiert nichts.
	local function areaImpact(origin)
		if humanoid.Health <= 0 or not root:IsDescendantOf(Workspace) then
			return
		end
		kaiju:SetAttribute("AreaHitCount", 0)

		-- Der Radius bestimmt nur, wie weit der Effekt reicht -- er entscheidet nichts über
		-- Schaden. Aus der Figurengrösse abgeleitet, damit die Entladung bei einer grossen
		-- Stufe nicht wie ein Funke wirkt.
		local radius = math.max(bodySpan * 1.2, 18)
		local durchmesser = radius * 2

		-- Die Entladung beginnt sichtbar an den Rückenplatten und schlägt erst dann auf dem
		-- Boden ein. Ohne diesen ersten Teil käme die Kugel aus dem Nichts.
		for index = 1, 3 do
			local plate = kaiju:FindFirstChild(string.format("DorsalShield_%02d", index))
			if plate and plate:IsA("BasePart") then
				local funke = neonPart("DorsalDischarge", Vector3.new(1, 1, 1) * (radius * 0.08),
					CFrame.new(plate.Position), ENTLADUNG_FARBE)
				funke.Shape = Enum.PartType.Ball
				funke.Transparency = 0.3

				local licht = Instance.new("PointLight")
				licht.Color = ENTLADUNG_FARBE
				licht.Brightness = 4
				licht.Range = math.min(60, radius * 1.25)
				licht.Parent = funke

				local dauer = 0.45 + index * 0.04
				TweenService:Create(funke, TweenInfo.new(dauer, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(durchmesser, durchmesser, durchmesser),
					CFrame = CFrame.new(origin + Vector3.new(0, radius * 0.2, 0)),
					Transparency = 0.65,
				}):Play()
				TweenService:Create(licht, TweenInfo.new(dauer + 0.25), { Brightness = 0 }):Play()
				task.delay(dauer, function()
					if funke.Parent then
						TweenService:Create(funke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
					end
				end)
				Debris:AddItem(funke, dauer + 0.3)
			end
		end

		-- Der flache Blitz am Boden -- er setzt den Aufschlagpunkt.
		local blitz = neonPart("AreaGroundFlash", Vector3.new(3, 0.25, 3), CFrame.new(origin), ENTLADUNG_FARBE)
		blitz.Shape = Enum.PartType.Ball
		TweenService:Create(blitz, TweenInfo.new(0.35), {
			Size = Vector3.new(durchmesser, 0.3, durchmesser),
			Transparency = 1,
		}):Play()
		Debris:AddItem(blitz, 0.4)
	end

	-- Nur wenn der Finisher das Gebäude auch WIRKLICH umlegt, wird er angeboten -- so
	-- schreibt es der Vertrag vor. Ein angebotener Finisher, nach dem das Haus noch steht,
	-- wäre ein gebrochenes Versprechen.
	local function prepareFinisher()
		if not reserved or not reachable(reserved) then
			cancel()
			return false
		end
		-- Abschnitte eines grösseren Bauwerks werden nicht gerissen (siehe Kopf der Datei).
		if ParentGroupService and ParentGroupService.IsParentGroupHouse
			and ParentGroupService.IsParentGroupHouse(reserved) then
			cancel()
			return false
		end
		if (reserved:GetAttribute("Health") or 0) > baseDamage() * FINISHER_FACTOR then
			cancel()
			return false
		end
		return true
	end

	-- Damit der SpecialAttackHandler dieselbe Entladung auch dann zeigen kann, wenn das Rig
	-- den Angriff abgelehnt hat (siehe PlayAreaDischarge oben).
	areaDischargeByModel[kaiju] = areaImpact
	mouthByModel[kaiju] = mouthPosition

	kaiju.Destroying:Once(cancel)

	return {
		Handle = handle,
		Cancel = cancel,
		PrepareFinisher = prepareFinisher,
		FocusAim = focusAim,
		SelectFocusTarget = selectFocusTarget,
		AreaImpact = areaImpact,
		Destroy = cancel,
	}
end

return KaijuStageOneCombatAdapter
