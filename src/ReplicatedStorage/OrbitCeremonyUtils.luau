-- ModuleScript: OrbitCeremonyUtils
-- Ort in Studio: ReplicatedStorage
--
-- Die Kamerafahrt, die einen Augenblick feiert: sie umrundet die Spielerfigur fast einmal
-- und fährt dabei heran -- weit und hoch beginnen, nah und auf Augenhöhe enden. Die Drehung
-- allein ist eine Umschau, erst das Herankommen macht daraus ein Zugehen auf die Figur.
--
-- ===== Warum sie hier liegt und nicht in der Talentfeier =====
-- Gebaut wurde sie für den Abschluss einer Forschung (TalentCeremonyClient). Die Fundstücke
-- von Kapitel I wollen dieselbe Bewegung -- ausdrücklich dieselbe, nicht eine ähnliche.
-- Nachgebaut stünde sie an zwei Orten, und der zweite würde beim ersten Feinschliff
-- zurückfallen. Also einmal, hier, wie schon CameraSessionUtils und LetterboxUtils.
--
-- Die Werte sind unverändert aus der Talentfeier übernommen: ihr Aussehen ist abgenommen
-- und ändert sich dadurch nicht.
--
-- ===== Was sie NICHT macht =====
-- Blende, Ton, Vignette, Texttafel, Steuerungssperre. Das ist der Rahmen des jeweiligen
-- Anlasses, und der ist bei einer Forschung ein anderer als bei einem Fund. Dieses Modul
-- führt die Kamera und sonst nichts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraSessionUtils = require(ReplicatedStorage:WaitForChild("CameraSessionUtils"))
local StageModels = require(ReplicatedStorage:WaitForChild("StageModels"))

local OrbitCeremonyUtils = {}

OrbitCeremonyUtils.Defaults = {
	Dauer = 4.2,

	-- Abstand und Höhe in Studs VOR der Skalierung -- sie werden mit der Figurengrösse
	-- multipliziert, sonst stünde die Kamera bei einem Aeon Tyrant in seinem Knie.
	AbstandStart = 34,
	AbstandEnde = 11,
	HoeheStart = 11,
	HoeheEnde = 1.5,

	-- Die Winkel zählen ab der BLICKRICHTUNG DER FIGUR, nicht ab einer Weltachse: 0 Grad
	-- ist direkt vor ihr. Anders gäbe es kein "vorne" -- die Figur steht, wie sie steht.
	--
	-- Am Ende 28 Grad: vor der Figur, ein Stück zur Seite. Genau frontal sähe aus wie ein
	-- Passbild; ein Viertel zur Seite gibt Tiefe und lässt das Gesicht trotzdem sehen.
	EndWinkel = 28,
	StartWinkelPlus = 340, -- fast eine volle Runde, von hinten herum

	-- Auf welcher Höhe der Figur die Kamera zielt. 0.9 ist Kopfhöhe -- gemessen am
	-- SICHTBAREN Modell, nicht am versteckten Avatar: dessen Kopf wackelt mit der
	-- Laufanimation, und bei grossen Stufen wird daraus ein Ausschlag von mehreren Studs.
	ZielHoehenAnteil = 0.9,

	-- Wie tief der scharfe Bereich ist, in Studs vor der Skalierung. Knapp gehalten, damit
	-- wirklich nur die Figur scharf steht -- zu knapp, und ihr eigener Rücken verschwimmt.
	FokusRadius = 6,
}

-- Blockiert NICHT. Gibt die RenderStepped-Verbindung zurück -- der Aufrufer legt sie in
-- seine Aufräumliste, damit ein Abbruch der Zeremonie die Schleife wirklich beendet und
-- nicht bloss auf den Sitzungswechsel wartet.
--
-- sessionId kommt von CameraSessionUtils. Ohne sie kämpfen zwei Kameraschleifen
-- gegeneinander, und das ergibt Flackern, das sich schwer reproduzieren lässt.
--
-- tiefenschaerfe ist optional und wird je Bild nachgezogen, weil die Kamera ja heranfährt.
-- Sie kommt als Parameter und nicht aus diesem Modul: ob eine Zeremonie überhaupt
-- Tiefenschärfe will, entscheidet ihr Anlass.
function OrbitCeremonyUtils.Umrunde(player, sessionId, einstellungen, tiefenschaerfe, onFertig)
	local camera = Workspace.CurrentCamera
	if not camera then
		if onFertig then
			onFertig()
		end
		return nil
	end

	local w = {}
	for name, wert in pairs(OrbitCeremonyUtils.Defaults) do
		w[name] = (einstellungen and einstellungen[name]) or wert
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local startWinkel = w.EndWinkel + w.StartWinkelPlus
	local begonnen = os.clock()
	local verbindung

	verbindung = RunService.RenderStepped:Connect(function()
		if not CameraSessionUtils.IsCurrent(sessionId) then
			verbindung:Disconnect()
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			verbindung:Disconnect()
			if onFertig then
				onFertig()
			end
			return
		end

		local fortschritt = math.clamp((os.clock() - begonnen) / w.Dauer, 0, 1)
		-- Weich anlaufen und weich stehenbleiben: eine Drehung mit gleichmässigem Tempo
		-- wirkt wie ein Messgerät, nicht wie eine Inszenierung.
		local weich = fortschritt * fortschritt * (3 - 2 * fortschritt)
		local winkel = startWinkel + (w.EndWinkel - startWinkel) * weich
		local abstand = w.AbstandStart + (w.AbstandEnde - w.AbstandStart) * weich
		local hoehe = w.HoeheStart + (w.HoeheEnde - w.HoeheStart) * weich

		local skala = 1
		local ok, s = pcall(function()
			return character:GetScale()
		end)
		if ok and type(s) == "number" and s > 0 then
			skala = s
		end

		local ziel = StageModels.GetFigurePoint(character, w.ZielHoehenAnteil)
			or (root.Position + Vector3.new(0, 2 * skala, 0))

		-- Die Blickrichtung der Figur ist die Null. Flach gelegt, damit eine Figur an einem
		-- Hang die Kamera nicht mit in die Schräge zieht.
		local vorne = root.CFrame.LookVector
		vorne = Vector3.new(vorne.X, 0, vorne.Z)
		if vorne.Magnitude < 0.001 then
			vorne = Vector3.new(0, 0, 1)
		else
			vorne = vorne.Unit
		end

		local richtung = CFrame.Angles(0, math.rad(winkel), 0) * vorne
		local auge = ziel + richtung * (abstand * skala) + Vector3.new(0, hoehe * skala, 0)
		camera.CFrame = CFrame.lookAt(auge, ziel)

		-- Die Schärfe folgt der Kamera. Gemessen wird der echte Abstand Auge zu Ziel --
		-- nicht der Radius der Umrundung, denn die Kamera steht auch über der Figur.
		if tiefenschaerfe then
			tiefenschaerfe.FocusDistance = (auge - ziel).Magnitude
			tiefenschaerfe.InFocusRadius = w.FokusRadius * skala
		end

		if fortschritt >= 1 then
			verbindung:Disconnect()
			if onFertig then
				onFertig()
			end
		end
	end)

	return verbindung
end

return OrbitCeremonyUtils
