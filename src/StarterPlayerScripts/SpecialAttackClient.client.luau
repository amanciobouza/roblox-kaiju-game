-- VERSION: 2026-08-26 #4
-- FEATURE: SimulatePrologueActionEvent -- simuliert echte Button-Drücke für den Prolog
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut 2 Buttons im HUD für die Spezialangriffe (Fokus-Laser, Flächenschaden), mit
-- Sanduhr-artiger Cooldown-Füllung (dunkler Überzug schrumpft, bis der Angriff wieder
-- bereit ist -- dann leuchtet der Button auf). Spielt außerdem die visuellen Effekte ab
-- (Laserstrahl vom Kopf, aufladende Explosion) -- für ALLE Spieler sichtbar, nicht nur den Angreifer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local StageModels = require(ReplicatedStorage:WaitForChild("StageModels"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local applyComicStyle = ComicStyleUtils.Apply
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Sprung/Fokus/Fläche sind NUR während des Bein-Trainings erlaubt (dort werden sie ja
-- trainiert) -- während Arm-Training (TrainingStat) UND Körper-Training
-- (BodyTrainingActive, eigenes Attribut vom Kreisparcours-Script) gesperrt.
local function isSpecialAttacksBlocked()
	local trainingStat = player:GetAttribute("TrainingStat")
	if trainingStat and trainingStat ~= "Leg" then
		return true
	end
	if player:GetAttribute("BodyTrainingActive") then
		return true
	end
	return false
end

-- Ist dieser Knopf gerade benutzbar? Die eine Wahrheit fuer Anzeige UND Eingabe -- sonst
-- sieht ein Knopf gesperrt aus und feuert trotzdem, oder umgekehrt.
--
-- Steht bewusst HIER OBEN und nicht bei der Sperrlogik weiter unten: die Klick- und
-- Tastenhandler kommen rund dreihundert Zeilen frueher, und ein Name, der erst danach
-- deklariert wird, loest in Lua auf eine globale nil auf -- lautlos.
local function istFrei(stat)
	if player:GetAttribute("CurrentZone") ~= "Sanctuary" then
		return true
	end
	return player:GetAttribute("TrainingStat") == stat
end

local AttackEvent = RemoteEventUtils.GetOrCreate("AttackEvent")
local attackCooldownValue = ReplicatedStorage:WaitForChild("AttackCooldown")
local PlayerJumpedEvent = RemoteEventUtils.GetOrCreate("PlayerJumpedEvent")
local jumpAttackCooldownValue = ReplicatedStorage:WaitForChild("JumpAttackCooldown")

local FocusAttackEvent = RemoteEventUtils.GetOrCreate("FocusAttackEvent")
local SimulatePrologueActionEvent = RemoteEventUtils.GetOrCreate("SimulatePrologueActionEvent")
local FocusChargeEvent = RemoteEventUtils.GetOrCreate("FocusChargeEvent")
local AreaAttackEvent = RemoteEventUtils.GetOrCreate("AreaAttackEvent")
local FocusAttackEffectEvent = RemoteEventUtils.GetOrCreate("FocusAttackEffectEvent")
local AreaAttackEffectEvent = RemoteEventUtils.GetOrCreate("AreaAttackEffectEvent")
local focusCooldownValue = ReplicatedStorage:WaitForChild("FocusAttackCooldown")
local areaCooldownValue = ReplicatedStorage:WaitForChild("AreaAttackCooldown")
local focusEnergyCostValue = ReplicatedStorage:WaitForChild("FocusEnergyCost")
local areaEnergyCostValue = ReplicatedStorage:WaitForChild("AreaEnergyCost")

-- WICHTIG: Trag hier deine eigenen Sound-IDs aus dem Creator Store ein
local FOCUS_CHARGE_SOUND_ID = "rbxassetid://1336756135" -- läuft WÄHREND der 2s Aufladephase
local FOCUS_SOUND_ID = "rbxassetid://139620337204036"
local AREA_CHARGE_SOUND_ID = "rbxassetid://139131445232833" -- läuft WÄHREND der Aufladephase
local AREA_SOUND_ID = "rbxassetid://114262262294281" -- der Knall bei der eigentlichen Explosion

local focusChargeSound = Instance.new("Sound")
focusChargeSound.Name = "FocusChargeSound"
focusChargeSound.SoundId = FOCUS_CHARGE_SOUND_ID
focusChargeSound.Volume = 0.8
focusChargeSound.Parent = SoundService

local focusSound = Instance.new("Sound")
focusSound.Name = "FocusAttackSound"
focusSound.SoundId = FOCUS_SOUND_ID
focusSound.Volume = 0.9
focusSound.Parent = SoundService

local areaChargeSound = Instance.new("Sound")
areaChargeSound.Name = "AreaAttackChargeSound"
areaChargeSound.SoundId = AREA_CHARGE_SOUND_ID
areaChargeSound.Volume = 0.8
areaChargeSound.Parent = SoundService

local areaSound = Instance.new("Sound")
areaSound.Name = "AreaAttackSound"
areaSound.SoundId = AREA_SOUND_ID
areaSound.Volume = 0.9
areaSound.Parent = SoundService

-- ===== Comic-Style Hilfsfunktion (wie im Haupt-HUD) =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SpecialAttackGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== Baut einen einzelnen Spezialangriffs-Button =====
-- Unterzeilen: sie sagen, WAS der Angriff tut, und tragen den militaerischen Ton. Die
-- Texte stammen aus Amancios Vorlage.
local ATTACK_SUBLABEL = {
	Attack = "BRUTAL FORCE",
	Jump = "VERTICAL POWER",
	Focus = "PRECISION MODE",
	Area = "DEVASTATION",
}

-- ===== Symbole =====
-- Hier standen nacheinander Emoji (👊 🦶 🔴 💥) und geometrische Zeichen (▶ ▲ ◎ ✹).
-- Beides war nur die beste Loesung mit Bordmitteln: Emoji zeichnet das Betriebssystem in
-- seinem eigenen bunten Stil, geometrische Zeichen haengen an der verfuegbaren Schrift.
-- Jetzt sind es hochgeladene Bilder aus HudChrome.Icon.
local ATTACK_ICON = {
	Attack = HudChrome.Icon.Punch,
	Jump = HudChrome.Icon.Jump,
	Focus = HudChrome.Icon.Focus,
	Area = HudChrome.Icon.Area,
}

-- Welche Ressource ein Knopf verbraucht -- und damit die Farbe seines Akzentstreifens.
-- Bernstein heisst frei, Cyan heisst Special Energy. Das ist die einzige Farbe am Knopf;
-- der Grund ist bei allen gleich dunkel (siehe HudChrome, Regel 2).
local ATTACK_ACCENT = {
	Attack = HudChrome.Color.Ready,
	Jump = HudChrome.Color.Ready,
	Focus = HudChrome.Color.Accent,
	Area = HudChrome.Color.Accent,
}

-- Zwei Parameter werden bewusst ignoriert. `_legacyIcon` war das Emoji, `_legacyColor`
-- die Grundfarbe des Knopfes -- beide sind durch die Stilregeln ersetzt: das Symbol kommt
-- aus HudChrome.Icon, und das Chrome traegt keine Farbe mehr, nur die Anzeige. Die
-- Aufrufzeilen uebergeben sie weiter, damit dort als Beleg stehen bleibt, was einmal war;
-- sie verschwinden, wenn die untere Zone in Scheibe 4 ohnehin umgebaut wird.
local function createAttackButton(name, _legacyIcon, labelText, _legacyColor, position, keyHint)
	-- 132 statt 100 Pixel breit. Die Vorlage zeigt Knoepfe, die deutlich breiter als hoch
	-- sind -- und genau die Breite fehlte der Unterzeile: "VERTICAL POWER" braucht sie.
	-- Platz ist da, die Gruppen stehen weit auseinander.
	local button = Instance.new("TextButton")
	button.Name = name .. "Button"
	button.Size = UDim2.new(0, HudChrome.Reihe.Breite, 0, HudChrome.Reihe.Hoehe)
	button.Position = position
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 10
	button.Parent = screenGui
	HudChrome.Panel(button, { radius = HudChrome.Radius.Panel, transparency = 0.08 })

	-- Das Symbol fuellt jetzt den GANZEN Knopf, statt sich die Hoehe mit der Beschriftung
	-- zu teilen. Die Beschriftung liegt darueber -- das ist ausdruecklich gewollt und der
	-- Grund, warum es unten einen Verlauf gibt.
	local iconLabel = HudChrome.IconImage(button, ATTACK_ICON[name])
	-- Etwas kleiner als der volle Knopf: 96 mal 76 statt 120 mal 96. Leicht nach oben
	-- gerueckt, damit unter dem Symbol Luft fuer die Beschriftung bleibt.
	iconLabel.Size = UDim2.new(1, -32, 1, -28)
	iconLabel.Position = UDim2.new(0, 16, 0, 6)
	iconLabel.ZIndex = 11

	-- Verlauf unter der Beschriftung: von durchsichtig oben nach dunkel unten. Ohne ihn
	-- steht heller Text auf hellen Stellen des Bildes und wird stellenweise unlesbar --
	-- und zwar unvorhersehbar, je nachdem was das Symbol dort gerade zeigt. Ein Verlauf
	-- loest das, ohne wie ein aufgeklebter Kasten zu wirken.
	local scrim = Instance.new("Frame")
	scrim.Name = "TextScrim"
	scrim.AnchorPoint = Vector2.new(0, 1)
	scrim.Position = UDim2.new(0, 0, 1, 0)
	scrim.Size = UDim2.new(1, 0, 0, 56)
	scrim.BackgroundColor3 = HudChrome.Color.Panel
	scrim.BorderSizePixel = 0
	scrim.ZIndex = 12
	scrim.Parent = button

	local scrimGradient = Instance.new("UIGradient")
	scrimGradient.Rotation = 90
	scrimGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 0.35),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	scrimGradient.Parent = scrim

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -10, 0, 22)
	nameLabel.Position = UDim2.new(0, 5, 1, -46)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = string.upper(labelText)
	nameLabel.ZIndex = 13
	nameLabel.Parent = button
	HudChrome.Label(nameLabel)

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.Size = UDim2.new(1, -10, 0, 15)
	subLabel.Position = UDim2.new(0, 5, 1, -25)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = ATTACK_SUBLABEL[name] or ""
	subLabel.ZIndex = 13
	subLabel.Parent = button
	HudChrome.Sublabel(subLabel)

	-- Akzentstreifen an der Unterkante. Was er anzeigt, haengt am Knopf: bei Focus und
	-- Area die Bereitschaft nach Special Energy, bei Punch und Jump die Abklingzeit --
	-- sie kosten keine Energie.
	local _, accentFill = HudChrome.AccentBar(button, ATTACK_ACCENT[name])

	if keyHint then
		local keyLabel = Instance.new("TextLabel")
		keyLabel.Name = "KeyHint"
		keyLabel.Size = UDim2.new(0, 18, 0, 18)
		keyLabel.AnchorPoint = Vector2.new(1, 0)
		keyLabel.Position = UDim2.new(1, -6, 0, 6)
		keyLabel.BackgroundTransparency = 1
		keyLabel.Text = keyHint
		keyLabel.ZIndex = 14
		keyLabel.Parent = button
		HudChrome.Number(keyLabel, 12)
		keyLabel.TextColor3 = HudChrome.Color.TextDim
		-- Auf Beruehrungsgeraeten gibt es keine Taste, die man druecken koennte.
		keyLabel.Visible = not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	end

	-- "Sanduhr"-Überzug: dunkler Bereich, der schrumpft, während der Cooldown abläuft.
	-- Oben verankert, damit es wie ablaufender Sand von oben nach unten wirkt.
	local cooldownOverlay = Instance.new("Frame")
	cooldownOverlay.Name = "CooldownOverlay"
	cooldownOverlay.AnchorPoint = Vector2.new(0, 0)
	cooldownOverlay.Position = UDim2.new(0, 0, 0, 0)
	cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
	cooldownOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	cooldownOverlay.BackgroundTransparency = 0.25
	cooldownOverlay.BorderSizePixel = 0
	cooldownOverlay.ZIndex = 12
	cooldownOverlay.Parent = button

	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "CooldownLabel"
	cooldownLabel.Size = UDim2.new(1, 0, 1, 0)
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.ZIndex = 13
	cooldownLabel.Text = ""
	cooldownLabel.Parent = button
	HudChrome.Number(cooldownLabel, HudChrome.TextSize.NumberLarge)

	-- Schleier fuer den GESPERRTEN Zustand. Er liegt ueber allem ausser der
	-- Abklingzeit-Zahl: ein gesperrter Knopf soll erkennbar da, aber erkennbar nicht
	-- benutzbar sein. Ihn auszublenden waere die einfachere Loesung und die schlechtere --
	-- ein Knopf, der verschwindet und wiederkommt, laesst einen jedes Mal neu suchen.
	local lockScrim = Instance.new("Frame")
	lockScrim.Name = "LockScrim"
	lockScrim.Size = UDim2.new(1, 0, 1, 0)
	lockScrim.BackgroundColor3 = HudChrome.Color.PanelSunken
	lockScrim.BackgroundTransparency = 0.35
	lockScrim.BorderSizePixel = 0
	lockScrim.Visible = false
	lockScrim.ZIndex = 14
	lockScrim.Parent = button

	local lockCorner = Instance.new("UICorner")
	lockCorner.CornerRadius = UDim.new(0, HudChrome.Radius.Panel)
	lockCorner.Parent = lockScrim

	return button, cooldownOverlay, cooldownLabel, accentFill
end

-- ===== Das Energie-Kosten-Label ist ENTFALLEN. =====
-- Es zeigte "⚡25" und bei zu wenig Energie die fehlende Menge. Diese Aufgabe hat jetzt
-- der Akzentstreifen an der Unterkante: er fuellt sich mit der Special Energy und leuchtet
-- voll, sobald der Angriff bezahlbar ist. Das beantwortet dieselbe Frage -- kann ich
-- jetzt? -- ohne dass man eine Zahl mit dem eigenen Energiestand vergleichen muss.
--
-- Die Funktion stand hier noch als leere Huelle und ist mit dem Umbau der unteren Zone
-- entfallen -- sie legte zwei unsichtbare Labels der Groesse null an, die niemand mehr
-- las.

-- ===== Die Reihe =====
--
-- Links vom Tacho steht, was nichts kostet und immer geht. Rechts, was die Spezialenergie
-- betrifft -- dieselbe, die der cyanfarbene Bogen am Tacho zeigt. Direkt neben dem Tacho
-- der Knopf, der sie FUELLT (Absorb, in EnergyAbsorbInputClient), dann die beiden, die sie
-- ausgeben, der teurere weiter aussen.
--
-- Die Lagen kommen aus HudChrome, weil der Absorb-Knopf aus einem anderen Skript kommt und
-- sich sonst nicht in dieselbe Reihe stellen laesst. Genau daran ist es vorher gescheitert:
-- er schwebte ueber der Reihe und lag auf dem Trainingsfeld.
local attackButton, attackOverlay, attackCooldownLabel, attackAccent =
	createAttackButton("Attack", "👊", "Punch", Color3.fromRGB(90, 140, 220), HudChrome.ReihePlatz(-2))
local jumpButton, jumpOverlay, jumpCooldownLabel, jumpAccent =
	createAttackButton("Jump", "🦶", "Jump", Color3.fromRGB(90, 190, 140), HudChrome.ReihePlatz(-1))
local focusButton, focusOverlay, focusCooldownLabel, focusAccent =
	createAttackButton("Focus", "🔴", "Focus", Color3.fromRGB(220, 60, 60), HudChrome.ReihePlatz(2), "Q")
local areaButton, areaOverlay, areaCooldownLabel, areaAccent =
	createAttackButton("Area", "💥", "Area", Color3.fromRGB(255, 150, 30), HudChrome.ReihePlatz(3), "E")

-- ENTFALLEN: FOCUS_BUTTON_COLOR, AREA_BUTTON_COLOR und DESATURATED_COLOR. Sie merkten
-- sich die Grundfarbe des Knopfes, um ihn bei zu wenig Energie zu entsaettigen. Nach der
-- neuen Stilregel traegt der Grund keine Farbe mehr -- sie waeren alle drei derselbe
-- dunkle Ton gewesen, und das Entsaettigen haette nichts mehr gezeigt. Die Aufgabe hat
-- der Akzentstreifen uebernommen.

-- ===== Sprung-Cooldown: gilt fürs SPRINGEN SELBST (Leertaste + Button gleichermaßen),
-- keine zusätzliche Aktion. Sobald ein Sprung beginnt, wird die Sprungfähigkeit für die
-- Cooldown-Dauer deaktiviert (JumpPower/JumpHeight auf 0), danach automatisch wiederhergestellt.
local jumpLocked = false

local function setupJumpLock(character)
	local humanoid = character:WaitForChild("Humanoid")

	humanoid.StateChanged:Connect(function(_, newState)
		if jumpLocked then
			return
		end
		if newState ~= Enum.HumanoidStateType.Jumping and newState ~= Enum.HumanoidStateType.Freefall then
			return
		end
		if isSpecialAttacksBlocked() then
			return -- Springen während Arm-/Körper-Training soll keinen echten Sprungangriff auslösen
		end

		-- ===== Traegt der Spieler ein Kaiju-Modell, meldet der Sprung sich selbst =====
		-- Dieser Weg haengt am Humanoid-Zustand, und Freefall kommt auch, wenn man nur eine
		-- Kante hinunterfaellt. Beim Avatar faellt das kaum auf; beim Kaiju lief der
		-- Sprung-Cooldown dadurch an, ohne dass jemand gesprungen waere -- die Sanduhr am
		-- Knopf war deshalb nie synchron mit dem, was die Figur konnte.
		--
		-- Der Sprung des Rigs wird direkt bei der Eingabe gemeldet
		-- (KaijuStageOneInputClient), also genau dann, wenn er wirklich beginnt. Hier wird
		-- er deshalb uebersprungen. Die JumpPower-Sperre darunter ebenfalls: der Installer
		-- setzt JumpPower ohnehin auf 0, der Sprung kommt vom Motor des Pakets.
		if StageModels.FindEquipped(character) then
			return
		end

		jumpLocked = true
		PlayerJumpedEvent:FireServer()

		local usesJumpPower = humanoid.UseJumpPower
		local originalPower = usesJumpPower and humanoid.JumpPower or humanoid.JumpHeight

		-- WICHTIG: Mit einer kleinen echten Verzögerung (nicht nur task.defer) auf 0
		-- setzen, damit der Physik-Engine garantiert genug Zeit hat, den Sprung-Impuls
		-- mit dem VOLLEN JumpPower-Wert anzuwenden, bevor wir ihn sperren. Vorher wurde
		-- der Sprung dadurch selbst schon abgeschnitten -> nur ein kurzer Hüpfer.
		task.delay(0.2, function()
			if usesJumpPower then
				humanoid.JumpPower = 0
			else
				humanoid.JumpHeight = 0
			end
		end)

		local isLegTrainingBoosted = player:GetAttribute("TrainingStat") == "Leg"
			and Workspace:GetServerTimeNow() < (player:GetAttribute("BoostEndsAt") or 0)
		local jumpLockDuration = isLegTrainingBoosted and (jumpAttackCooldownValue.Value / 2) or jumpAttackCooldownValue.Value

		task.delay(jumpLockDuration, function()
			if humanoid.Parent then
				if usesJumpPower then
					humanoid.JumpPower = originalPower
				else
					humanoid.JumpHeight = originalPower
				end
			end
			jumpLocked = false
		end)
	end)
end

if player.Character then
	setupJumpLock(player.Character)
end
player.CharacterAdded:Connect(function(character)
	jumpLocked = false
	setupJumpLock(character)
end)
-- ===== Auslöse-Funktionen (von Buttons UND Tastatur/Gamepad gemeinsam genutzt) =====
local function triggerAttack()
	local readyAt = player:GetAttribute("AttackReadyAt") or 0
	if Workspace:GetServerTimeNow() >= readyAt then
		-- Feuert NICHT direkt AttackEvent -- das übernimmt AttackClient.lua zentral über
		-- dieses BindableEvent, damit der Combo-Schritt (für den Dritter-Schlag-Bonus)
		-- auch beim Tippen auf diesen Button korrekt mitgeschickt wird (wichtig für
		-- Touch-Geräte wie iPad, wo dies der einzige Weg zum Schlagen ist).
		local touchAttackButtonPressed = player:FindFirstChild("TouchAttackButtonPressed")
		if touchAttackButtonPressed then
			touchAttackButtonPressed:Fire()
		end
	end
end

local function triggerJump()
	-- ===== Traegt der Spieler ein Kaiju-Modell, geht der Sprung ueber das Rig =====
	-- `humanoid.Jump = true` half dort nicht: der Installer setzt die Sprungkraft des
	-- Avatars auf null, der Sprung kommt allein vom Rig -- und dessen Eingabe haengt an
	-- UserInputService.JumpRequest, das bei einem programmatisch gesetzten Jump NICHT
	-- feuert. Dieser Knopf lief also ins Leere, sobald ein Modell haengt.
	--
	-- KaijuStageOneInputClient bietet dafuer ein BindableEvent an, gleiches Muster wie
	-- TouchAttackButtonPressed beim Schlag.
	local kaijuJump = player:FindFirstChild("RequestKaijuJump")
	if kaijuJump and StageModels.FindEquipped(player.Character) then
		kaijuJump:Fire()
		return
	end

	-- Löst nur einen ganz normalen Sprung aus (wie die Leertaste) -- keine zusätzliche
	-- Aktion. Ob der Sprung tatsächlich passiert, entscheidet allein das Sprung-Sperr-
	-- System oben (JumpPower/JumpHeight ist während des Cooldowns auf 0 gesetzt).
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Jump = true
	end
end

-- ===== Die Spezialangriff-Animationen der Figur =====
-- Trägt der Spieler ein Kaiju-Modell, soll es seine EIGENE Bewegung für Fokus und Fläche
-- zeigen, statt reglos dazustehen, während der Effekt aus dem Nichts kommt.
--
-- Angestossen wird sie ZUSÄTZLICH, nicht anstelle: Energiekosten, Cooldown, Schaden,
-- Effekte, Talentboni und die Freischaltung bleiben komplett beim SpecialAttackHandler des
-- Spiels. Das Rig steuert nur das Bild bei.
--
-- Damit das aufgeht, macht der Kampf-Adapter für Fokus und Fläche KEINEN Schaden -- sonst
-- zählte jeder Spezialangriff doppelt (siehe KaijuStageOneCombatAdapter). Beim Nahkampf
-- ist es umgekehrt: dort gehört dem Rig auch die Trefferermittlung.
-- ===== Spielt das Rig seinen eigenen Effekt gerade AB? =====
-- Es führt "FocusPhase" und "AreaPhase" am Modell. Läuft dort etwas, gehört das Bild ihm
-- und der alte Effekt des Spiels bleibt aus. Läuft nichts, muss der alte her.
--
-- Diese Unterscheidung ist nötig, weil das Rig einen Angriff auch ABLEHNEN kann. Der Fokus
-- etwa verlangt ein Gebäude in Sicht -- im Sanctuary gibt es keines, er meldet "No target"
-- und spielt gar nichts. Vorher habe ich den alten Strahl schon dann abgeschaltet, wenn nur
-- ein Kaiju-Modell an der Figur hing. An der Trainingsstation blieb dadurch beides aus.
-- "No ground" kam mit Paket 1.3.2 dazu: das Rig lehnt den Flächenangriff ab, wenn der Boden
-- unter der Figur zu schräg oder zu weit weg ist, und sagt das jetzt ausdrücklich, statt
-- stumm auf "Idle" zu bleiben.
local RIG_PHASE_IDLE = { ["Idle"] = true, ["No target"] = true, ["No ground"] = true }

local function rigPhaseActive(attackerPlayer, attributeName)
	local model = StageModels.FindEquipped(attackerPlayer and attackerPlayer.Character)
	if not model then
		return nil -- kein Modell: die Frage stellt sich nicht
	end
	local phase = model:GetAttribute(attributeName)
	return phase ~= nil and not RIG_PHASE_IDLE[phase]
end

-- ===== Der Wettlauf, und wie er aufgeloest wird =====
-- Der Effekt des Spiels kommt SOFORT, sobald der Server den Angriff annimmt. Das Rig
-- braucht bis dahin einen Umweg: Client fragt an, Server leitet weiter, das Rig setzt seine
-- Phase, und die muss erst zurueckrepliziert werden. In diesem Moment ist die Phase noch
-- "Idle" -- also wurde der alte Effekt gezeichnet, und kurz darauf kam der neue dazu.
-- Genau das war die gelbe Kugel neben der Entladung.
--
-- Deshalb wird kurz GEWARTET, bevor entschieden wird. Ein Drittel einer Sekunde faellt bei
-- einer Aufladung von 2.8 Sekunden nicht auf; laeuft das Rig bis dahin nicht, hat es
-- abgelehnt und der alte Effekt ist richtig.
--
-- Die Entscheidung wird je Angreifer kurz gemerkt: der Fokus schickt alle 0.25 Sekunden
-- einen Tick, und jeder davon soll nicht erneut warten.
local RIG_DECISION_WAIT = 0.35
local RIG_DECISION_MEMORY = 1.2

local rigDecisions = setmetatable({}, { __mode = "k" }) -- [player] = { [attribut] = {at, playing} }

local function rigWillPlay(attackerPlayer, attributeName)
	if not attackerPlayer then
		return false
	end

	local perPlayer = rigDecisions[attackerPlayer]
	if not perPlayer then
		perPlayer = {}
		rigDecisions[attackerPlayer] = perPlayer
	end

	-- Solange die Ticks weiterlaufen, bleibt die einmal getroffene Entscheidung stehen --
	-- und der Zeitstempel wird dabei AUFGEFRISCHT. Ohne das lief das Gedächtnis mitten im
	-- Strahl ab, es wurde erneut ein Drittel einer Sekunde gewartet, und in dieser Zeit kam
	-- kein Strahl. Er blitzte deshalb nur kurz auf und verschwand wieder.
	local remembered = perPlayer[attributeName]
	if remembered and os.clock() - remembered.at < RIG_DECISION_MEMORY then
		remembered.at = os.clock()
		return remembered.playing
	end

	local active = rigPhaseActive(attackerPlayer, attributeName)
	if active == nil then
		perPlayer[attributeName] = { at = os.clock(), playing = false }
		return false
	end

	local deadline = os.clock() + RIG_DECISION_WAIT
	while not active and os.clock() < deadline do
		task.wait(0.05)
		active = rigPhaseActive(attackerPlayer, attributeName)
		if active == nil then
			active = false
			break
		end
	end

	perPlayer[attributeName] = { at = os.clock(), playing = active }

	-- ===== Warum hat das Rig abgelehnt? =====
	-- Seit Paket 1.3.4 sagt es das selbst -- auf unsere Meldung hin, und für BEIDE
	-- Spezialangriffe: "FocusRejectReason" und "AreaRejectReason" nennen die Bedingung, die
	-- gekippt ist ("Airborne", "Jump active", "Cooldown", "No target", "Too steep" ...).
	-- Dazu legt es den Zustand ab, in dem die Anfrage ankam.
	--
	-- Vorher stand hier eine eigene Zusammenstellung aus dem, was von aussen ablesbar war,
	-- und die konnte den Grund bestenfalls nahelegen. Jetzt wird er gelesen.
	if not active and attackerPlayer == player then
		local model = StageModels.FindEquipped(attackerPlayer.Character)
		if model then
			local grundAttribut = attributeName == "FocusPhase" and "FocusRejectReason" or "AreaRejectReason"
			print(string.format(
				"[Kaiju Debug] Rig lehnt %s ab -- Grund=%s Boden=%s Senkrecht=%.1f Zustand=%s Phase=%s",
				attributeName,
				tostring(model:GetAttribute(grundAttribut)),
				tostring(model:GetAttribute("SpecialFloorMaterial")),
				tonumber(model:GetAttribute("SpecialVerticalVelocity")) or 0,
				tostring(model:GetAttribute("SpecialHumanoidState")),
				tostring(model:GetAttribute(attributeName))))
		end
	end

	return active
end

local function playKaijuSpecial(remoteName)
	local model = StageModels.FindEquipped(player.Character)
	local remote = model and model:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer()
		return
	end
	-- Gemeldet statt verschwiegen: bleibt die Animation aus, soll man hier sehen koennen,
	-- ob die Anfrage ueberhaupt losging.
	print(string.format("[Kaiju Debug] %s nicht gesendet -- %s.", remoteName,
		model and "Modell ohne dieses Ereignis" or "kein Kaiju-Modell an der Figur"))
end

-- Reicht die Energie? Der Server prüft das ohnehin und lehnt sonst ab -- aber die Animation
-- läuft lokal los und wüsste nichts davon. Ohne diese Prüfung holte die Figur sichtbar aus,
-- und es passierte nichts.
--
-- ACHTUNG: dieselbe Prüfung war beim FLÄCHENangriff die Ursache dafür, dass auf dem
-- langsameren Rechner Schaden ohne Animation ankam -- das replizierte Attribut hinkte dem
-- Server hinterher. Die Fläche wartet deshalb auf die Bestätigung des Servers (siehe
-- AreaAttackEffectEvent). Beim Fokus bleibt es vorerst bei der lokalen Prüfung, weil er
-- seine Effekte tickweise schickt und damit keinen einzelnen Startpunkt hat; zeigt sich
-- dort derselbe Aussetzer, gehört er auf denselben Weg.
local function hasEnergyFor(cost)
	return (player:GetAttribute("SpecialEnergy") or 0) >= cost
end

local function triggerFocus()
	local readyAt = player:GetAttribute("FocusAttackReadyAt") or 0
	if Workspace:GetServerTimeNow() >= readyAt then
		FocusAttackEvent:FireServer()
		if hasEnergyFor(focusEnergyCostValue.Value) then
			playKaijuSpecial("RequestFocus")
		end
	end
end

-- Die Fläche wird NICHT hier ausgeloest, sondern erst, wenn der Server den Angriff
-- angenommen hat -- siehe den Handler von AreaAttackEffectEvent weiter unten.
--
-- Hier stand einmal dieselbe Energiepruefung wie beim Fokus. Sie hat im Mehrspielertest
-- genau das kaputt gemacht, was sie verhindern sollte: auf dem langsameren Rechner war das
-- replizierte Attribut "SpecialEnergy" nicht auf dem Stand des Servers, die Pruefung schlug
-- fehl -- und der Spieler bekam den Schaden, aber keine Animation.
--
-- Der Server weiss als Einziger sicher, ob der Angriff zustande kommt. Also fragt der
-- Client nicht mehr, sondern wartet auf dessen Meldung. Nebenbei sitzt die Bewegung damit
-- exakt auf dem Beginn der Aufladung statt ein paar Zehntel daneben.
local function triggerArea()
	local readyAt = player:GetAttribute("AreaAttackReadyAt") or 0
	if Workspace:GetServerTimeNow() >= readyAt then
		AreaAttackEvent:FireServer()
	end
end

-- Für den Prolog: simuliert einen "echten" Button-Druck (inkl. Cooldown-Prüfung) --
-- nutzt exakt dieselben Funktionen wie ein tatsächlicher Klick auf den jeweiligen Button.
-- "Punch" läuft separat über AttackClient.lua (TouchAttackButtonPressed-BindableEvent).
SimulatePrologueActionEvent.OnClientEvent:Connect(function(actionType)
	if actionType == "Punch" then
		triggerAttack()
	elseif actionType == "Jump" then
		triggerJump()
	elseif actionType == "Focus" then
		triggerFocus()
	elseif actionType == "Area" then
		triggerArea()
	end
end)

-- ===== Klick-Handler =====
-- Schlag-Button bleibt unverändert (nie während irgendeines Trainings sichtbar/nutzbar).
-- Fokus/Fläche: während des BEIN-Trainings funktionieren sie tatsächlich (kürzerer
-- Cooldown, Fokus zielt aufs "LaserTarget"), aber OHNE echten Schaden -- siehe
-- SpecialAttackHandler.lua. Bei Arm/Körper-Training weiterhin komplett gesperrt.
attackButton.MouseButton1Click:Connect(function()
	if not istFrei("Arm") then
		return
	end
	triggerAttack()
end)
jumpButton.MouseButton1Click:Connect(function()
	if isSpecialAttacksBlocked() or not istFrei("Leg") then
		return
	end
	triggerJump()
end)
focusButton.MouseButton1Click:Connect(function()
	if isSpecialAttacksBlocked() or not istFrei("Leg") then
		return
	end
	triggerFocus()
end)
areaButton.MouseButton1Click:Connect(function()
	if isSpecialAttacksBlocked() or not istFrei("Leg") then
		return
	end
	triggerArea()
end)

-- ===== Tastatur- und Gamepad-Bindings für die beiden Spezialangriffe =====
-- Tastatur: Q = Fokus, E = Fläche | Gamepad: X-Button = Fokus, Y-Button = Fläche
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if isSpecialAttacksBlocked() or not istFrei("Leg") then
		return -- an einer Arm-/Koerper-Station oder im Sanctuary ohne Bein-Training:
		-- die Tasten gehoeren dort dem Training, nicht den Spezialangriffen
	end

	if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonX then
		triggerFocus()
	elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonY then
		triggerArea()
	end
end)

-- ===== Leucht-Effekt, wenn ein Angriff bereit wird (einmaliger Puls) =====
local function playReadyGlow(button)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	local originalColor = stroke.Color
	stroke.Color = Color3.fromRGB(255, 255, 150)
	local tween = TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Color = originalColor,
	})
	tween:Play()
end

local wasAttackReady = true
local wasJumpReady = true
local wasFocusReady = true
local wasAreaReady = true
local wasFocusEnergyEnough = true
local wasAreaEnergyEnough = true

-- ===== Läuft jeden Frame: aktualisiert die Sanduhr-Füllung + Cooldown-Text =====
-- Fuellt den Akzentstreifen eines Special-Knopfes nach dem Energiestand. Voll und hell,
-- sobald bezahlbar; sonst anteilig und gedaempft. Damit beantwortet der Streifen die Frage
-- "kann ich jetzt?" schneller als eine Zahl es koennte.
local function updateEnergyAccent(accent, currentEnergy, cost)
	if not accent then
		return
	end
	local ratio = math.clamp(currentEnergy / math.max(cost, 1), 0, 1)
	accent.Size = UDim2.new(ratio, 0, 1, 0)
	accent.BackgroundTransparency = ratio >= 1 and 0 or 0.5
end

-- `accent` ist der Akzentstreifen an der Unterkante und optional: bei Punch und Jump
-- zeigt er die Abklingzeit (leer, waehrend sie laeuft, voll sobald wieder bereit). Bei
-- Focus und Area steuert ihn stattdessen der Energiestand weiter unten -- sie kosten
-- Energie, und das ist dort die knappere Ressource.
local function updateCooldownDisplay(overlay, label, readyAt, cooldownDuration, accent)
	local now = Workspace:GetServerTimeNow()
	local remaining = readyAt - now

	if remaining <= 0 then
		overlay.Size = UDim2.new(1, 0, 0, 0)
		label.Text = ""
		if accent then
			accent.Size = UDim2.new(1, 0, 1, 0)
			accent.BackgroundTransparency = 0
		end
		return true
	end

	local ratio = math.clamp(remaining / math.max(cooldownDuration, 0.1), 0, 1)
	overlay.Size = UDim2.new(1, 0, ratio, 0)
	if accent then
		-- Der Streifen waechst, waehrend die Abklingzeit ablaeuft -- er ist voll, wenn
		-- der Angriff wieder bereit ist.
		accent.Size = UDim2.new(1 - ratio, 0, 1, 0)
		accent.BackgroundTransparency = 0.45
	end
	return false
end

RunService.Heartbeat:Connect(function()
	local attackReadyAt = player:GetAttribute("AttackReadyAt") or 0
	local jumpReadyAt = player:GetAttribute("JumpAttackReadyAt") or 0
	local focusReadyAt = player:GetAttribute("FocusAttackReadyAt") or 0
	local areaReadyAt = player:GetAttribute("AreaAttackReadyAt") or 0

	-- Bein-Training nutzt die GLEICHEN Cooldowns wie im echten Spiel (siehe
	-- SpecialAttackHandler.lua) -- außer während eines aktiven Trainings-Boosts, dann
	-- werden sie halbiert. Anzeige muss DENSELBEN Wert kennen, sonst füllt sich der
	-- Balken relativ zum falschen Bezugswert.
	local isLegTraining = player:GetAttribute("TrainingStat") == "Leg"
	local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
	local isBoosted = isLegTraining and Workspace:GetServerTimeNow() < boostEndsAt
	local focusCooldownDuration = isBoosted and (focusCooldownValue.Value / 2) or focusCooldownValue.Value
	local areaCooldownDuration = isBoosted and (areaCooldownValue.Value / 2) or areaCooldownValue.Value
	local jumpCooldownDuration = isBoosted and (jumpAttackCooldownValue.Value / 2) or jumpAttackCooldownValue.Value

	local attackReady = updateCooldownDisplay(attackOverlay, attackCooldownLabel, attackReadyAt, attackCooldownValue.Value, attackAccent)
	local jumpReady = updateCooldownDisplay(jumpOverlay, jumpCooldownLabel, jumpReadyAt, jumpCooldownDuration, jumpAccent)
	local focusReady = updateCooldownDisplay(focusOverlay, focusCooldownLabel, focusReadyAt, focusCooldownDuration)
	local areaReady = updateCooldownDisplay(areaOverlay, areaCooldownLabel, areaReadyAt, areaCooldownDuration)

	if attackReady and not wasAttackReady then
		playReadyGlow(attackButton)
	end
	if jumpReady and not wasJumpReady then
		playReadyGlow(jumpButton)
	end
	if focusReady and not wasFocusReady then
		playReadyGlow(focusButton)
	end
	if areaReady and not wasAreaReady then
		playReadyGlow(areaButton)
	end

	wasAttackReady = attackReady
	wasJumpReady = jumpReady
	wasFocusReady = focusReady
	wasAreaReady = areaReady

	-- ===== Energie-Feedback: Kosten anzeigen, Button entsättigen wenn zu wenig Energie
	-- vorhanden ist, fehlende Menge anzeigen, kurzer Puls beim Erreichen genug Energie. =====
	local currentEnergy = player:GetAttribute("SpecialEnergy") or 0
	local focusCost = focusEnergyCostValue.Value
	local areaCost = areaEnergyCostValue.Value
	local hasEnoughFocusEnergy = currentEnergy >= focusCost
	local hasEnoughAreaEnergy = currentEnergy >= areaCost

	-- Der Akzentstreifen IST die Bereitschaftsanzeige: er fuellt sich mit der gesammelten
	-- Energie und leuchtet voll, sobald der Angriff bezahlbar ist. Vorher stand hier eine
	-- Zahl ("⚡25"), die man mit dem eigenen Energiestand vergleichen musste, und der
	-- ganze Knopf wurde entsaettigt -- Letzteres geht nicht mehr, weil der Grund nach der
	-- neuen Stilregel bei allen Knoepfen gleich dunkel ist.
	updateEnergyAccent(focusAccent, currentEnergy, focusCost)
	updateEnergyAccent(areaAccent, currentEnergy, areaCost)

	if hasEnoughFocusEnergy and not wasFocusEnergyEnough then
		playReadyGlow(focusButton)
	end
	if hasEnoughAreaEnergy and not wasAreaEnergyEnough then
		playReadyGlow(areaButton)
	end
	wasFocusEnergyEnough = hasEnoughFocusEnergy
	wasAreaEnergyEnough = hasEnoughAreaEnergy
end)

-- ===== Visuelle Effekte: für ALLE Spieler sichtbar, nicht nur den Angreifer =====

-- Laserstrahl vom Kopf zum Trefferpunkt -- EINE durchgehende Instanz pro Angriff, die bei
-- jedem Server-Tick nachgeführt wird (nicht mehr neu erzeugt), damit er als echter Dauerstrahl
-- wirkt statt als Reihe einzelner Blitze. Verblasst automatisch, wenn 0.4s lang kein neuer
-- Tick mehr ankommt (Angriff ist zu Ende).
local activeFocusBeams = {} -- [attackerPlayer] = { beam=, glow=, light=, lastUpdate= }
local FOCUS_BEAM_TIMEOUT = 0.4

-- ===== Die Farbe des Strahls richtet sich nach der Figur =====
-- Trägt der Angreifer ein Kaiju-Modell, zeichnet dieser Strahl nur noch den FEHLSCHUSS:
-- findet das Spiel kein Ziel, erstattet es die Energie und zeigt einen kurzen Strahl ins
-- Leere als Rückmeldung. Das Rig spielt dabei nichts, denn ohne Ziel gibt es für es nichts
-- zu tun.
--
-- Rot passte dazu nicht mehr. Der Kaiju lädt cyan auf, und ein roter Fehlschuss sah aus wie
-- ein zweiter, fremder Angriff statt wie derselbe, der ins Leere ging. Es ist die Farbe der
-- Darstellung des Pakets (KaijuPresentation, focusColor).
local FOCUS_COLOR_DEFAULT = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 150, 150), Color3.fromRGB(255, 80, 80) }
local FOCUS_COLOR_KAIJU = { Color3.fromRGB(65, 225, 255), Color3.fromRGB(170, 240, 255), Color3.fromRGB(65, 225, 255) }

local function updateFocusBeam(attackerPlayer, startPos, endPos)
	local distance = (endPos - startPos).Magnitude
	local beamCFrame = CFrame.new(startPos, endPos) * CFrame.new(0, 0, -distance / 2)

	local entry = activeFocusBeams[attackerPlayer]
	if not entry then
		local farben = StageModels.FindEquipped(attackerPlayer and attackerPlayer.Character)
			and FOCUS_COLOR_KAIJU or FOCUS_COLOR_DEFAULT

		local beam = Instance.new("Part")
		beam.Name = "FocusLaser"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Material = Enum.Material.Neon
		beam.Color = farben[1]
		beam.Parent = Workspace

		local glow = Instance.new("Part")
		glow.Name = "FocusLaserGlow"
		glow.Anchored = true
		glow.CanCollide = false
		glow.CanQuery = false
		glow.Material = Enum.Material.Neon
		glow.Color = farben[2]
		glow.Transparency = 0.55
		glow.Parent = Workspace

		local light = Instance.new("PointLight")
		light.Color = farben[3]
		light.Range = 20
		light.Brightness = 5
		light.Parent = beam

		entry = { beam = beam, glow = glow, light = light }
		activeFocusBeams[attackerPlayer] = entry

		if attackerPlayer == player and focusSound.SoundId ~= "" and focusSound.SoundId ~= "rbxassetid://0" then
			focusSound.TimePosition = 0
			focusSound.Looped = true
			focusSound:Play()
		end
	end

	entry.beam.Size = Vector3.new(2, 2, distance)
	entry.beam.CFrame = beamCFrame
	entry.beam.Transparency = 0
	entry.glow.Size = Vector3.new(5, 5, distance)
	entry.glow.CFrame = beamCFrame
	entry.glow.Transparency = 0.55
	entry.light.Brightness = 5
	entry.lastUpdate = os.clock()
end

-- Feuert einmalig zu Beginn der 2s Aufladephase (nur für den Angreifer selbst)
FocusChargeEvent.OnClientEvent:Connect(function()
	if focusChargeSound.SoundId ~= "" and focusChargeSound.SoundId ~= "rbxassetid://0" then
		focusChargeSound.TimePosition = 0
		focusChargeSound:Play()
	end
end)

FocusAttackEffectEvent.OnClientEvent:Connect(function(attackerPlayer, startPos, endPos)
	if attackerPlayer == player and focusChargeSound.Playing then
		focusChargeSound:Stop()
	end

	-- ===== Trägt der Angreifer ein Kaiju-Modell, gehört ihm der Strahl allein =====
	-- Dieselbe Aufteilung wie beim Flächenangriff: das Rig lädt am Maul auf und schickt
	-- seinen eigenen Strahl los. Der alte rote daneben wären zwei Strahlen aus derselben
	-- Figur, mit verschiedenen Ansatzpunkten und verschiedenen Farben.
	--
	-- Der Schaden bleibt davon unberührt -- den führt weiter der SpecialAttackHandler,
	-- hier wird nur nicht gezeichnet.
	--
	-- Geprüft wird am ANGREIFER, nicht am eigenen Spieler: das Ereignis geht an alle, und
	-- Zuschauer sollen dasselbe sehen wie er.
	--
	-- Und geprüft wird, ob das Rig gerade WIRKLICH etwas spielt -- nicht bloss, ob ein
	-- Modell hängt. Lehnt es den Fokus ab (kein Gebäude in Sicht, etwa an der
	-- Trainingsstation), soll der alte Strahl einspringen statt beides ausfallen zu lassen.
	if rigWillPlay(attackerPlayer, "FocusPhase") then
		return
	end

	-- ===== Und den Fehlschuss zeichnet der Adapter selbst =====
	-- Findet auch das Spiel kein Ziel, sammelt die Figur Energie über den Rückenplatten, zieht
	-- sie ans Maul und feuert kurz ins Leere (KaijuStageOneCombatAdapter, playFocusMiss). Der
	-- Adapter vermerkt das am Modell; hier wird deshalb nicht noch ein zweiter Strahl
	-- darübergelegt.
	--
	-- Der Zeitstempel steht in Serverzeit, damit ihn jeder Zuschauer gleich liest. Das
	-- Fenster deckt die Aufladung samt Strahl ab.
	local model = StageModels.FindEquipped(attackerPlayer and attackerPlayer.Character)
	local missAt = model and model:GetAttribute("AdapterFocusMissAt")
	if typeof(missAt) == "number" and Workspace:GetServerTimeNow() - missAt < 3 then
		return
	end

	updateFocusBeam(attackerPlayer, startPos, endPos)
end)

-- Räumt Strahlen auf, für die längere Zeit kein neuer Tick mehr kam (Angriff beendet).
RunService.Heartbeat:Connect(function()
	for attackerPlayer, entry in pairs(activeFocusBeams) do
		if os.clock() - entry.lastUpdate > FOCUS_BEAM_TIMEOUT then
			activeFocusBeams[attackerPlayer] = nil

			if attackerPlayer == player and focusSound.Playing then
				focusSound.Looped = false
				focusSound:Stop()
			end

			local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(entry.beam, tweenInfo, { Transparency = 1 }):Play()
			TweenService:Create(entry.glow, tweenInfo, { Transparency = 1 }):Play()
			local lightTween = TweenService:Create(entry.light, tweenInfo, { Brightness = 0 })
			lightTween:Play()
			lightTween.Completed:Connect(function()
				entry.beam:Destroy()
				entry.glow:Destroy()
			end)
		end
	end
end)

-- Aufladende Ladung, die nach kurzer Zeit explodiert
AreaAttackEffectEvent.OnClientEvent:Connect(function(attackerPlayer, position, chargeTime, radius)
	radius = radius or 50

	-- ===== Trägt der Angreifer ein Kaiju-Modell, gehört ihm das Bild allein =====
	-- Das Rig bäumt sich auf, stützt sich ab und entlädt über die Rückenplatten eine cyane
	-- Druckwelle (KaijuStageOneCombatAdapter.areaImpact). Liefe die alte gelbe Ladekugel
	-- daneben weiter, wären es zwei Angriffe an einer Stelle -- verschiedene Farben,
	-- verschiedene Zeitpunkte, dieselbe Taste.
	--
	-- Geprüft wird am ANGREIFER, nicht am eigenen Spieler: das Ereignis geht an alle, und
	-- Zuschauer sollen dasselbe sehen wie er.
	-- Die Bewegung des Rigs anstossen -- jetzt, wo feststeht, dass der Server den Angriff
	-- angenommen hat. Nur der Angreifer selbst darf sein Ereignis ausloesen; es ist
	-- besitzergeprueft, ein fremder Aufruf liefe ohnehin ins Leere.
	if attackerPlayer == player and StageModels.FindEquipped(player.Character) then
		playKaijuSpecial("RequestArea")
	end

	-- ===== Trägt der Angreifer ein Kaiju-Modell, bleibt die alte Kugel IMMER aus =====
	-- Hier wurde einmal abgewartet, ob das Rig seine Phase wirklich startet, und sonst die
	-- alte Kugel gezeichnet. Das Rig lehnt den Angriff aber ab, sobald der Boden schräg ist
	-- -- auf einem Dach sah derselbe Tastendruck deshalb völlig anders aus als auf der
	-- Strasse.
	--
	-- Den Ersatz stellt jetzt der Server: lehnt das Rig ab, spielt er zur Einschlagzeit
	-- dieselbe cyane Entladung ohne das Rig (SpecialAttackHandler, Ersatz-Entladung). Der
	-- Client muss deshalb gar nicht mehr wissen, wie das Rig entschieden hat.
	--
	-- Beim FOKUS bleibt die Abwägung nötig und steht weiter unten: der verlangt ein Gebäude
	-- in Sicht, und an der Trainingsstation gäbe es sonst überhaupt kein Bild.
	if StageModels.FindEquipped(attackerPlayer and attackerPlayer.Character) then
		return
	end

	local chargePart = Instance.new("Part")
	chargePart.Name = "AreaAttackCharge"
	chargePart.Shape = Enum.PartType.Ball
	chargePart.Anchored = true
	chargePart.CanCollide = false
	chargePart.CanQuery = false
	chargePart.Material = Enum.Material.Neon
	chargePart.Color = Color3.fromRGB(255, 150, 30)
	chargePart.Size = Vector3.new(2, 2, 2)
	chargePart.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
	chargePart.Parent = Workspace

	-- Die sichtbare Ladung wächst proportional zum tatsächlichen Wirkungsradius,
	-- damit optisch klar wird, wie groß der Angriff wirklich ist.
	local chargeVisualSize = math.clamp(radius * 0.3, 8, 60)
	local growTween = TweenService:Create(
		chargePart,
		TweenInfo.new(chargeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ Size = Vector3.new(chargeVisualSize, chargeVisualSize, chargeVisualSize) }
	)
	growTween:Play()

	if attackerPlayer == player and areaChargeSound.SoundId ~= "" and areaChargeSound.SoundId ~= "rbxassetid://0" then
		areaChargeSound.TimePosition = 0
		areaChargeSound:Play()
	end

	task.delay(chargeTime, function()
		chargePart:Destroy()

		if areaChargeSound.Playing then
			areaChargeSound:Stop()
		end

		if attackerPlayer == player and areaSound.SoundId ~= "" and areaSound.SoundId ~= "rbxassetid://0" then
			areaSound.TimePosition = 0
			areaSound:Play()
		end

		local explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastRadius = radius
		explosion.BlastPressure = 0
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = Workspace
	end)
end)

-- ===== Gesperrt statt ausgeblendet =====
--
-- Frueher verschwanden die Knoepfe im Sanctuary. Das HUD wechselte damit beim Betreten
-- sein Gesicht -- und wer aus dem Training zurueckkam, musste sich neu zurechtfinden.
--
-- Jetzt bleiben alle vier stehen, und im Sanctuary sind sie GESPERRT: ein Schleier
-- darueber, kein Akzentstreifen, kein Klick. Freigeschaltet wird nur, was die Station
-- gerade braucht -- Arm-Training den Schlag, Bein-Training Sprung, Fokus und Flaeche.
-- So zeigt das HUD im Sanctuary genau das, was dort moeglich ist, ohne seine Form zu
-- aendern.
local KNOEPFE = {
	{ button = attackButton, accent = attackAccent, stat = "Arm" },
	{ button = jumpButton, accent = jumpAccent, stat = "Leg" },
	{ button = focusButton, accent = focusAccent, stat = "Leg" },
	{ button = areaButton, accent = areaAccent, stat = "Leg" },
}

local function updateHudLock()
	for _, eintrag in ipairs(KNOEPFE) do
		local frei = istFrei(eintrag.stat)
		local scrim = eintrag.button:FindFirstChild("LockScrim")
		if scrim then
			scrim.Visible = not frei
		end
		if eintrag.accent then
			eintrag.accent.Parent.Visible = frei
		end
		eintrag.button.AutoButtonColor = false
	end
end

updateHudLock()
player:GetAttributeChangedSignal("CurrentZone"):Connect(updateHudLock)
player:GetAttributeChangedSignal("TrainingStat"):Connect(updateHudLock)
player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(updateHudLock)