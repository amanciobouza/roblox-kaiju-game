-- LocalScript: CollectibleClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Zwei Dinge rund um die Fundstücke von Kapitel I, beide reine Darstellung:
--
--   1. Das Stück in der Welt schwebt und dreht sich, solange es liegt.
--   2. Berührt der Kaiju es, erklingt die Erfolgsmeldung.
--
-- ===== Was hier NICHT mehr steht (11.10.2026) =====
-- Die Kamerafahrt. Der Fund lief vorher als Zeremonie ab: die Kamera umrundete die Figur
-- fast einmal und fuhr heran, wie beim Abschluss einer Forschung. Das ist auf Amancios
-- Entscheidung entfallen -- der Fund soll im Spiel bleiben, nicht es anhalten.
--
-- OrbitCeremonyUtils bleibt bestehen: die Talentfeier nutzt es weiter, und dort ist es auch
-- gebaut worden. Nur dieser Anlass greift nicht mehr darauf zu.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CollectibleConfig = require(ReplicatedStorage:WaitForChild("CollectibleConfig"))
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local CollectibleFoundEvent = RemoteEventUtils.GetOrCreate("CollectibleFoundEvent")

-- ===== Das Schweben =====
-- Wie weit es auf und ab wiegt, in Studs, und wie oft. Klein gehalten: es soll leben, nicht
-- schaukeln. Die Ruhehöhe steht als Attribut am Stück -- der Server setzt sie, wenn sein
-- Aufstieg fertig ist, und erst dann trägt das Stück den Tag.
local WIEGE_STUDS = 1.6
local WIEGE_HZ = 0.4

local gedreht = {} -- [model] = true, nur damit GetTagged nicht je Bild neu gelesen wird

CollectionService:GetInstanceAddedSignal(CollectibleConfig.WorldTag):Connect(function(model)
	gedreht[model] = true
end)
CollectionService:GetInstanceRemovedSignal(CollectibleConfig.WorldTag):Connect(function(model)
	gedreht[model] = nil
end)
for _, model in ipairs(CollectionService:GetTagged(CollectibleConfig.WorldTag)) do
	gedreht[model] = true
end

RunService.RenderStepped:Connect(function()
	-- Aus der Serverzeit gerechnet, damit alle Betrachter dasselbe sehen -- und weil
	-- dieselbe Rechnung auch die einfachere ist.
	local jetzt = Workspace:GetServerTimeNow()
	for model in pairs(gedreht) do
		if model.Parent then
			local ruheY = model:GetAttribute("CollectibleRestY")
			if ruheY then
				local pose = model:GetPivot()
				local hub = math.sin(jetzt * WIEGE_HZ * math.pi * 2) * WIEGE_STUDS
				local winkel = jetzt * CollectibleConfig.SpinSpeed * math.pi * 2
				model:PivotTo(
					CFrame.new(pose.Position.X, ruheY + hub, pose.Position.Z)
						* CFrame.Angles(0, winkel, 0)
				)
			end
		end
	end
end)

-- ===== Die Erfolgsmeldung =====
-- Ton und eine kurze Karte in der Bildmitte. Die Mitte gehört dem, was eingetreten ist --
-- und ein gefundenes Fragment ist genau das. Sie geht von selbst wieder weg; es gibt nichts
-- zu bestätigen, der Spieler steht ja mitten in der freien Zerstörung.
local ERFOLG_SOUND = "rbxassetid://1336756135" -- derselbe, den die Talentfeier auflädt
local KARTE_SEKUNDEN = 2.8

local schirm = Instance.new("ScreenGui")
schirm.Name = "CollectibleFoundGui"
schirm.ResetOnSpawn = false
schirm.IgnoreGuiInset = true
schirm.DisplayOrder = 45
schirm.Enabled = false
schirm.Parent = player:WaitForChild("PlayerGui")

local karte = Instance.new("Frame")
karte.Name = "Karte"
karte.AnchorPoint = Vector2.new(0.5, 0.5)
karte.Position = UDim2.fromScale(0.5, 0.42)
karte.Size = UDim2.fromOffset(420, 104)
karte.Parent = schirm
HudChrome.Panel(karte)

local titel = Instance.new("TextLabel")
titel.Name = "Titel"
titel.BackgroundTransparency = 1
titel.Position = UDim2.fromOffset(0, 16)
titel.Size = UDim2.new(1, 0, 0, 34)
titel.Text = "FRAGMENT GEFUNDEN"
titel.Parent = karte
HudChrome.Label(titel, 26)

local name = Instance.new("TextLabel")
name.Name = "Name"
name.BackgroundTransparency = 1
name.Position = UDim2.fromOffset(0, 52)
name.Size = UDim2.new(1, 0, 0, 36)
name.Text = ""
name.Parent = karte
HudChrome.Number(name, 30)
-- Bernstein, nicht Cyan: Cyan gehoert im HUD ausschliesslich der Special Energy. Bernstein
-- traegt im Spiel schon "geschafft" -- es ist dieselbe Farbe, in der am Zifferblatt im
-- Sanctuary eine gebrochene Stadt leuchtet.
name.TextColor3 = HudChrome.Color.Ready

local offenBis = 0

local function zeigeMeldung(daten)
	name.Text = string.upper(tostring(daten and daten.Title or "Fragment"))

	schirm.Enabled = true
	karte.BackgroundTransparency = 1
	titel.TextTransparency = 1
	name.TextTransparency = 1

	-- 0.12 ist der Wert, den HudChrome.Panel setzt -- das Einblenden endet dort, wo der
	-- Ruhezustand des Panels liegt, und nicht bei einer eigenen Zahl daneben.
	local ein = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(karte, ein, { BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(titel, ein, { TextTransparency = 0 }):Play()
	TweenService:Create(name, ein, { TextTransparency = 0 }):Play()

	local sound = Instance.new("Sound")
	sound.SoundId = ERFOLG_SOUND
	sound.Volume = 0.6
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)

	-- Die Frist wird gemerkt statt in einem task.delay eingeschlossen: findet der Spieler
	-- in dieser Zeit ein zweites Fragment, soll die zweite Karte die Anzeige verlängern und
	-- nicht die erste sie mitten im Zeigen abräumen.
	offenBis = os.clock() + KARTE_SEKUNDEN
	task.delay(KARTE_SEKUNDEN, function()
		if os.clock() < offenBis - 0.05 then
			return -- eine neuere Meldung hat übernommen
		end
		local aus = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(karte, aus, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(titel, aus, { TextTransparency = 1 }):Play()
		TweenService:Create(name, aus, { TextTransparency = 1 }):Play()
		task.delay(0.4, function()
			if os.clock() >= offenBis - 0.05 then
				schirm.Enabled = false
			end
		end)
	end)
end

CollectibleFoundEvent.OnClientEvent:Connect(function(daten)
	local ok, fehler = pcall(zeigeMeldung, daten)
	if not ok then
		warn("[Kaiju Debug] Fundstueck-Meldung fehlgeschlagen: " .. tostring(fehler))
	end
	print(string.format("[Kaiju Debug] Fragment gefunden: %s (%s).",
		tostring(daten and daten.Title), tostring(daten and daten.City)))
end)

print("[Kaiju Debug] CollectibleClient bereit -- Schweben, Drehen und Erfolgsmeldung.")
