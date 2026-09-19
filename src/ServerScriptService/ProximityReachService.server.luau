-- Script: ProximityReachService
--
-- Die Reichweite aller ProximityPrompts wächst mit der Figur.
--
-- ===== Das Problem =====
-- Seit der Avatar auf die Höhe des Kaiju-Modells gebracht wird, sitzt sein Rumpf dreissig
-- bis fünfundvierzig Studs über dem Boden. Roblox misst die Entfernung zu einem Prompt
-- aber gegen genau diesen Rumpf. Wer also auf der Trainingsstation STEHT, ist für das
-- Prompt zwanzig bis vierzig Studs entfernt -- und die Vorgabe liegt bei zwanzig.
--
-- Die Station merkte deshalb nicht mehr, dass jemand auf ihr steht. Dasselbe gilt für
-- jedes andere Prompt der Welt; aufgefallen ist es nur dort zuerst.
--
-- ===== Warum es hier steht und nicht im TrainingHandler =====
-- Der TrainingHandler kennt nur die BEIN-Station. Arm und Körper werden von eigenen
-- Skripten gesteuert, die im Modell in Studio liegen (siehe CLAUDE.md) und ihre Prompts
-- selbst anlegen -- an die käme er nicht heran. Über die Prompts selbst schon.
--
-- Und es ist ohnehin kein Trainings-Problem: es betrifft Portale, den Lift und alles
-- Weitere gleichermassen.
--
-- ===== Die Rechnung =====
-- Der Abstand zwischen Boden und Rumpf wächst PROPORTIONAL zur Figur. Also wächst auch die
-- nötige Reichweite proportional, und der Faktor ist schlicht die Figurenhöhe geteilt durch
-- die eines gewöhnlichen Avatars.
--
-- Die ursprüngliche Reichweite jedes Prompts bleibt erhalten: sie wird beim ersten Sehen in
-- einem Attribut festgehalten und ist von da an die Grundlage. Ohne das würde jede Runde
-- auf das Ergebnis der vorigen multiplizieren und die Reichweite liefe davon.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Ein gewöhnlicher R15-Avatar ist knapp sechs Studs hoch -- der gemessene Wert aus
-- PlayerSetup ("natuerlich 5.9"). Bei dieser Höhe bleibt alles, wie es in Studio steht.
local NORMALE_FIGUR = 5.9

-- Obergrenze, damit ein Fehler in der Messung nicht ein Prompt über die halbe Karte
-- sichtbar macht.
local HOECHSTER_FAKTOR = 16

-- Die Prompts sind Weltmöbel und entstehen nicht ständig neu; alle zwei Sekunden reicht
-- völlig, und es sind eine Handvoll.
local TAKT = 2

local BASIS_ATTRIBUT = "BasisReichweite"

local prompts = {}

local function merke(instanz)
	if not instanz:IsA("ProximityPrompt") then
		return
	end
	if instanz:GetAttribute(BASIS_ATTRIBUT) == nil then
		instanz:SetAttribute(BASIS_ATTRIBUT, instanz.MaxActivationDistance)
	end
	prompts[instanz] = true
end

-- Die Höhe der SICHTBAREN Figur, nicht die des Avatars: das Kaiju-Modell hängt am
-- Charakter, und GetExtentsSize misst es mit. Genau das ist gewollt -- wer eine Figur von
-- sechzig Studs sieht, erwartet, dass sie aus entsprechender Entfernung etwas anfassen kann.
local function figurenHoehe()
	local hoechste = NORMALE_FIGUR
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character.PrimaryPart then
			local ok, groesse = pcall(function()
				return character:GetExtentsSize()
			end)
			if ok and groesse and groesse.Y > hoechste then
				hoechste = groesse.Y
			end
		end
	end
	return hoechste
end

local letzterFaktor = 0

local function passeAn()
	local hoehe = figurenHoehe()
	local faktor = math.clamp(hoehe / NORMALE_FIGUR, 1, HOECHSTER_FAKTOR)

	-- Nur bei spürbarer Änderung schreiben. Ein Prompt, das jede Sekunde neu gesetzt wird,
	-- repliziert jedes Mal an alle Spieler.
	if math.abs(faktor - letzterFaktor) < 0.05 then
		return
	end
	letzterFaktor = faktor

	local angepasst = 0
	for prompt in pairs(prompts) do
		if prompt.Parent then
			local basis = prompt:GetAttribute(BASIS_ATTRIBUT)
			if type(basis) == "number" and basis > 0 then
				prompt.MaxActivationDistance = basis * faktor
				angepasst += 1
			end
		else
			prompts[prompt] = nil
		end
	end

	print(string.format("[Kaiju Debug] Prompt-Reichweite: Faktor %.1f fuer eine Figur von "
		.. "%.0f Studs -- %d Prompts angepasst.", faktor, hoehe, angepasst))
end

for _, instanz in ipairs(Workspace:GetDescendants()) do
	merke(instanz)
end
Workspace.DescendantAdded:Connect(merke)

task.spawn(function()
	while true do
		task.wait(TAKT)
		passeAn()
	end
end)

print("[Kaiju Debug] ProximityReachService bereit -- Prompt-Reichweite waechst mit der Figur.")
