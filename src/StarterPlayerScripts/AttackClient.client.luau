-- VERSION: 2026-08-25 #1 (RemoteEventUtils-Umstellung)
-- LocalScript: AttackClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Sendet ein Angriffs-Signal an den Server, spielt lokal die zum aktuellen Skin
-- passende Kampf-Animation ab und lässt bei jedem Schlag einen Sound ertönen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local AttackEvent = RemoteEventUtils.GetOrCreate("AttackEvent")
local AttackCooldownValue = ReplicatedStorage:WaitForChild("AttackCooldown")
local TrainClickEvent = RemoteEventUtils.GetOrCreate("TrainClickEvent")

local currentAttackTrack = nil
local lastTrainingSwingAt = 0 -- eigene Cooldown-Verfolgung fürs Arm-Training (kein Server-Roundtrip)

-- ===== Schlag-Kombo: PunchLeft -> PunchRight -> PunchAll =====
-- Bricht ab (springt zurück zu PunchLeft), wenn zu lange zwischen zwei Schlägen gewartet
-- wird. COMBO_WINDOW ist bewusst etwas größer als der Angriffs-Cooldown (0.8s), damit man
-- bei normalem Klick-Tempo bequem in der Kombo bleibt, aber eine echte Pause sie abbricht.
local COMBO_ANIMATIONS = {
	"rbxassetid://96237359714095", -- PunchLeft
	"rbxassetid://124162188616993", -- PunchRight
	"rbxassetid://81933564767019", -- PunchAll
}
local COMBO_WINDOW = 1.5

local comboStep = 1 -- 1-indexiert, zeigt auf die NÄCHSTE zu spielende Animation
local lastComboHitAt = 0

local function getNextComboAnimation()
	local now = Workspace:GetServerTimeNow()
	if now - lastComboHitAt > COMBO_WINDOW then
		comboStep = 1 -- zu lange gewartet -- Kombo bricht ab, von vorne mit PunchLeft
	end
	lastComboHitAt = now

	local usedStep = comboStep
	local animationId = COMBO_ANIMATIONS[comboStep]
	comboStep = comboStep + 1
	if comboStep > #COMBO_ANIMATIONS then
		comboStep = 1 -- nach PunchAll wieder von vorne
	end
	return animationId, usedStep
end

-- ===== Schlag-Sound (bei JEDEM Angriff, egal ob getroffen wird) =====
-- WICHTIG: Trag hier deine eigene Sound-ID aus dem Creator Store ein (Format: "rbxassetid://12345678")
local SWING_SOUND_ID = "rbxassetid://140192907374090"

local swingSound = Instance.new("Sound")
swingSound.Name = "SwingSound"
swingSound.SoundId = SWING_SOUND_ID
swingSound.Volume = 0.6
swingSound.Parent = SoundService

local function playSwingSound()
	if swingSound.SoundId == "" or swingSound.SoundId == "rbxassetid://0" then
		return -- noch keine Sound-ID hinterlegt
	end
	swingSound.TimePosition = 0
	swingSound:Play()
end

local function playAttackAnimation()
	local character = player.Character
	if not character then
		return 1
	end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return 1
	end

	local animationId, usedStep = getNextComboAnimation()
	-- Lokal gespeichert (nicht repliziert), damit TrainingClient.lua beim Feuern von
	-- TrainClickEvent weiß, welcher Combo-Schritt gerade genutzt wurde -- beide Scripts
	-- reagieren ja auf denselben Klick, brauchen aber eine gemeinsame Quelle der Wahrheit.
	player:SetAttribute("CurrentComboStep", usedStep)

	if currentAttackTrack then
		currentAttackTrack:Stop()
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	currentAttackTrack = humanoid:LoadAnimation(animation)

	-- Während eines aktiven Trainings-Boosts (halbierter Klick-Cooldown) doppelt so
	-- schnell abspielen, damit die Animation zur schnelleren Klick-Kadenz passt.
	local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
	local isBoosted = Workspace:GetServerTimeNow() < boostEndsAt
	currentAttackTrack:Play()
	currentAttackTrack:AdjustSpeed(isBoosted and 2 or 1)
	return usedStep
end

-- Arm-Training an der Schmiede: fühlt sich wie ein echter Schlag an (Animation +
-- Sound), aber OHNE AttackEvent -- kein echter Kampfschaden während des Trainings.
-- Wiederverwendbar, da sowohl Tastatur/Maus (InputBegan unten) als auch Touch-Geräte
-- (über den HUD-Button, siehe touchAttackButtonPressed weiter unten) dieselbe Logik
-- brauchen -- vorher hatte NUR der Tastatur/Maus-Weg das, wodurch Touch-Spieler beim
-- Arm-Training gar keinen Treffer auslösen konnten.
local function performArmTrainingSwing()
	-- WICHTIG: Da kein AttackEvent gefeuert wird, aktualisiert der Server auch nie
	-- "AttackReadyAt" -- deshalb hier eine EIGENE, rein clientseitige Cooldown-
	-- Verfolgung mit derselben Cooldown-Dauer wie beim normalen Schlag. Während
	-- eines aktiven Trainings-Boosts wird dieser Cooldown halbiert, analog zum
	-- Bein-Training (Fokus/Fläche/Sprung, siehe SpecialAttackHandler.lua/HouseHandler.lua).
	local now = Workspace:GetServerTimeNow()
	local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
	local isBoosted = now < boostEndsAt
	local effectiveCooldown = isBoosted and (AttackCooldownValue.Value / 2) or AttackCooldownValue.Value

	if now - lastTrainingSwingAt < effectiveCooldown then
		return
	end
	lastTrainingSwingAt = now

	-- Lokal (rein clientseitig, nicht zum Server repliziert) setzen, damit die
	-- Sanduhr-Anzeige am Schlag-Button (die dieses Attribut ausliest) auch während
	-- des Arm-Trainings korrekt befüllt wird -- sonst bliebe der Button visuell
	-- immer auf "bereit", obwohl gerade ein Cooldown läuft.
	player:SetAttribute("AttackReadyAt", now + effectiveCooldown)

	-- Der eigentliche Trainings-Fortschritt + die Schmiede-Effekte (Funken, Platte,
	-- Sound am Amboss) laufen weiterhin über TrainClickEvent -- hier direkt gefeuert,
	-- damit der Combo-Schritt garantiert exakt zu der Animation passt, die JETZT
	-- gerade gespielt wird (kein Timing-Risiko zwischen zwei separaten Scripts).
	local usedStep = playAttackAnimation()
	playSwingSound()
	TrainClickEvent:FireServer(usedStep)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local trainingStat = player:GetAttribute("TrainingStat")
	if trainingStat and trainingStat ~= "Arm" then
		return -- Bein/Körper-Training: Klicks gehen komplett an TrainingClient.lua, keine Schlag-Optik
	end
	if player:GetAttribute("BodyTrainingActive") then
		return -- Körper-Training (Kreisparcours) nutzt ein eigenes Attribut -- soll nur Laufen erlauben, kein Schlagen
	end

	if input.KeyCode == Enum.KeyCode.F or input.UserInputType == Enum.UserInputType.MouseButton1 then
		if trainingStat == "Arm" then
			performArmTrainingSwing()
			return
		end

		-- Während des Cooldowns komplett ignorieren -- kein Sound, keine Animation, kein
		-- Server-Event. Vorher hörte man den Schwung-Sound schon während der Cooldown
		-- noch lief, obwohl der Server den Schaden ohnehin abgelehnt hätte.
		local readyAt = player:GetAttribute("AttackReadyAt") or 0
		if Workspace:GetServerTimeNow() < readyAt then
			return
		end

		AttackEvent:FireServer(playAttackAnimation())
		playSwingSound()
	end
end)

-- ===== Für Touch-Geräte (iPad etc.): der HUD-Schlag-Button (SpecialAttackClient.lua)
-- feuert ECHTEN Schaden via triggerAttack(), aber OHNE diese BindableEvent-Verbindung
-- würde dabei keine Animation/Sound abgespielt (die läuft normalerweise nur über
-- Tastatur/Maus-Klick hier oben). Rein clientseitig, keine Server-Kommunikation nötig.
local touchAttackButtonPressed = Instance.new("BindableEvent")
touchAttackButtonPressed.Name = "TouchAttackButtonPressed"
touchAttackButtonPressed.Parent = player

touchAttackButtonPressed.Event:Connect(function()
	local trainingStat = player:GetAttribute("TrainingStat")
	if trainingStat and trainingStat ~= "Arm" then
		return
	end
	if player:GetAttribute("BodyTrainingActive") then
		return
	end

	if trainingStat == "Arm" then
		-- BUG-FIX: Vorher wurde hier einfach "return" gemacht, mit dem Kommentar "Arm-
		-- Training hat seinen eigenen Button-Weg" -- der aber nur für Tastatur/Maus
		-- existierte (InputBegan oben reagiert NICHT auf Touch-Taps, nur auf MouseButton1/
		-- F-Taste). Touch-Spieler konnten dadurch beim Arm-Training NIE einen Treffer
		-- auslösen. Jetzt wird dieselbe Funktion wie beim Tastatur/Maus-Weg genutzt.
		performArmTrainingSwing()
		return
	end

	local readyAt = player:GetAttribute("AttackReadyAt") or 0
	if Workspace:GetServerTimeNow() < readyAt then
		return -- Cooldown läuft noch
	end

	AttackEvent:FireServer(playAttackAnimation())
	playSwingSound()
end)