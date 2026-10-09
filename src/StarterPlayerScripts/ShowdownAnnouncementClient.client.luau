-- LocalScript: ShowdownAnnouncementClient
--
-- Der Auftritt beim Showdown: ein Schlag, eine Stimme, und in der Bildmitte
--
--     SHOWDOWN
--     KAIJU vs. WARDEN
--
-- ===== Warum ein eigenes Skript =====
-- Der ShowdownClient daneben fuehrt die Kamera durch die Einstellungen des Auftritts --
-- ein System, an dem Kamerakonflikte schon mehrfach wehgetan haben (siehe CLAUDE.md). Die
-- Ankuendigung braucht davon nichts: sie haengt am selben Ereignis, zeichnet aber nur eine
-- Flaeche und spielt zwei Toene. Getrennt zu halten heisst, dass ein Fehler hier die
-- Kamera nicht mitreisst.
--
-- ===== Die Bildmitte =====
-- Sie gehoert im HUD-Konzept nur dem, was EINGETRETEN ist -- keine Vorwarnung, keine
-- Daueranzeige. Der Beginn eines Showdowns ist genau so ein Moment, und er dauert drei
-- Sekunden, nicht laenger.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local ShowdownStateEvent = ReplicatedStorage:WaitForChild("ShowdownStateEvent", 60)
if not ShowdownStateEvent then
	warn("[Kaiju Debug] Showdown-Ankuendigung: 'ShowdownStateEvent' fehlt -- der Dienst laeuft nicht.")
	return
end

-- Der Schlag und die Stimme. Beide von Amancio geliefert; die Stimme setzt kurz nach dem
-- Schlag ein, damit sie auf dem stehenden Schriftzug landet statt im Getoese unterzugehen.
local KLANG_SCHLAG = "rbxassetid://9046717800"
local KLANG_STIMME = "rbxassetid://90236697706560"
local STIMME_VERZUG = 0.35

local STANDZEIT = 3.0
local EINBLENDEN = 0.28
local AUSBLENDEN = 0.45

-- Arcade-Gelb mit dunklem Rand, wie auf einem Automaten der Achtziger.
local GELB = Color3.fromRGB(255, 208, 48)
local ORANGE = Color3.fromRGB(240, 126, 24)
local RAND = Color3.fromRGB(28, 12, 6)
local WEISS = Color3.fromRGB(252, 250, 244)

local gui = Instance.new("ScreenGui")
gui.Name = "ShowdownAnkuendigung"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 30)

-- Ein drehbarer Halter. Die Neigung gehoert an den Rahmen, nicht an die Beschriftung:
-- Rotation dreht um den AnchorPoint, und eine Schrift, die selbst rotiert, wandert dabei
-- aus ihrer Zeile -- derselbe Grund, aus dem die Uhrzeiger im Ladebildschirm in
-- Behaeltern sitzen.
local halter = Instance.new("Frame")
halter.AnchorPoint = Vector2.new(0.5, 0.5)
halter.Position = UDim2.fromScale(0.5, 0.44)
halter.Size = UDim2.fromScale(0.9, 0.3)
halter.BackgroundTransparency = 1
halter.Rotation = -3
halter.Parent = gui

local function beschriftung(name, hoehe, y, schriftgroesse)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, y)
	text.Size = UDim2.fromScale(1, hoehe)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.LuckiestGuy
	text.TextScaled = true
	text.TextColor3 = WEISS
	text.Text = ""
	text.Parent = halter

	local rand = Instance.new("UIStroke")
	rand.Thickness = schriftgroesse
	rand.Color = RAND
	rand.LineJoinMode = Enum.LineJoinMode.Round
	rand.Parent = text

	return text
end

local titel = beschriftung("Titel", 0.55, 0.3, 6)
local paarung = beschriftung("Paarung", 0.38, 0.78, 4)

-- Der Farbverlauf nur im Titel: die Paarung soll lesbar bleiben, nicht glaenzen.
local verlauf = Instance.new("UIGradient")
verlauf.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, GELB),
	ColorSequenceKeypoint.new(0.55, GELB),
	ColorSequenceKeypoint.new(1, ORANGE),
})
verlauf.Rotation = 90
verlauf.Parent = titel

local function spiele(id, lautstaerke)
	local ton = Instance.new("Sound")
	ton.SoundId = id
	ton.Volume = lautstaerke
	ton.Parent = SoundService
	ton:Play()
	ton.Ended:Connect(function()
		ton:Destroy()
	end)
	-- Falls das Ereignis nie kommt (fehlende Kennung), nicht ewig liegen lassen.
	task.delay(12, function()
		if ton.Parent then
			ton:Destroy()
		end
	end)
	return ton
end

local laufNummer = 0

local function zeige(info)
	laufNummer += 1
	local meineNummer = laufNummer

	titel.Text = "SHOWDOWN"
	paarung.Text = string.format("%s  vs.  %s",
		string.upper(tostring(info.spieler or "Kaiju")),
		string.upper(tostring(info.gegner or "Guardian")))

	-- Von zu gross hereinfahren: der Schriftzug soll wirken, als schlage er ein.
	halter.Size = UDim2.fromScale(1.35, 0.45)
	titel.TextTransparency = 1
	paarung.TextTransparency = 1
	gui.Enabled = true

	TweenService:Create(halter, TweenInfo.new(EINBLENDEN, Enum.EasingStyle.Back,
		Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.9, 0.3) }):Play()
	TweenService:Create(titel, TweenInfo.new(EINBLENDEN), { TextTransparency = 0 }):Play()
	TweenService:Create(paarung, TweenInfo.new(EINBLENDEN), { TextTransparency = 0 }):Play()

	spiele(KLANG_SCHLAG, 0.9)
	task.delay(STIMME_VERZUG, function()
		if meineNummer == laufNummer then
			spiele(KLANG_STIMME, 1)
		end
	end)

	print(string.format("[Kaiju Debug] Showdown-Ankuendigung: %s vs. %s.",
		tostring(info.spieler), tostring(info.gegner)))

	task.delay(STANDZEIT, function()
		-- Ein zweiter Showdown waehrend des ersten Auftritts soll den alten nicht
		-- ausblenden: die Nummer sagt, ob dieser Lauf noch der aktuelle ist.
		if meineNummer ~= laufNummer then
			return
		end
		TweenService:Create(titel, TweenInfo.new(AUSBLENDEN), { TextTransparency = 1 }):Play()
		local aus = TweenService:Create(paarung, TweenInfo.new(AUSBLENDEN), { TextTransparency = 1 })
		aus.Completed:Connect(function()
			if meineNummer == laufNummer then
				gui.Enabled = false
			end
		end)
		aus:Play()
	end)
end

ShowdownStateEvent.OnClientEvent:Connect(function(isActive, info)
	if isActive then
		zeige(info or {})
	end
end)

print("[Kaiju Debug] Showdown-Ankuendigung bereit.")
