-- LocalScript: StadiumPongClient
--
-- Die Spielerseite des Stadion-Pongs: Tasten, Blick von oben, Hinweistafel.
--
-- ===== Was hier NICHT passiert =====
-- Der Client bewegt nichts. Er schickt eine Richtung (-1, 0 oder 1) an den Server, und der
-- führt Schläger und Ball. Anders liesse sich das Spiel von einem Client aus stellen -- und
-- der Ball gehört ohnehin beiden Seiten gemeinsam.
--
-- ===== Der Blick =====
-- Amancio wollte von oben zuschauen. Die Kamera geht deshalb beim Beitreten senkrecht über
-- die Feldmitte und bleibt dort stehen, bis man aufhört. Sie wird NICHT jedes Bild neu
-- gesetzt: ein Standbild von oben ist genau das, was Pong braucht, und eine Kamera, die
-- jeden Frame schreibt, kämpft mit anderen Kamerasystemen (siehe CLAUDE.md, Kamera-
-- Konflikte brauchen Session-IDs).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local PongInputEvent = ReplicatedStorage:WaitForChild("StadionPongInput", 60)
local PongStateEvent = ReplicatedStorage:WaitForChild("StadionPongState", 60)
if not PongInputEvent or not PongStateEvent then
	warn("[Kaiju Debug] Stadion-Pong: die Ereignisse fehlen -- der Dienst am Server laeuft nicht.")
	return
end

local AKTION = "StadionPong"
-- Wie weit die Kamera ueber dem Feld steht. Aus der Feldbreite gerechnet statt fest
-- gesetzt: kaeme das Feld je in einer anderen Groesse, stimmte eine feste Zahl nicht mehr.
local KAMERA_HOEHE_FAKTOR = 0.95

local spieltGerade = false
local gedrueckt = { Vor = false, Zurueck = false }
local vorherigerTyp

local hinweis = Instance.new("ScreenGui")
hinweis.Name = "StadionPongHinweis"
hinweis.ResetOnSpawn = false
hinweis.Enabled = false
hinweis.Parent = player:WaitForChild("PlayerGui", 30)

local hinweisText = Instance.new("TextLabel")
hinweisText.Size = UDim2.new(1, 0, 0, 34)
hinweisText.Position = UDim2.new(0, 0, 1, -76)
hinweisText.BackgroundTransparency = 1
hinweisText.Font = Enum.Font.Code
hinweisText.TextScaled = true
hinweisText.TextColor3 = Color3.fromRGB(245, 248, 250)
hinweisText.Text = ""
hinweisText.Parent = hinweis

-- ===== Warum das Vorzeichen gedreht ist =====
-- Der Server rechnet in der LOKALEN Achse des Stadions: +1 bewegt den Schlaeger in dessen
-- +Z-Richtung. Die Kamera in beginne() schaut senkrecht von oben darauf, mit der
-- Blickrichtung des Feldes als "oben im Bild" -- und dadurch zeigt +Z auf dem Bildschirm
-- nach UNTEN. Pfeil-hoch fuhr den Schlaeger also nach unten.
--
-- Gedreht wird hier und nicht am Server: nur der Client kennt die Kamera, und fuer den
-- Server soll +1 weiterhin schlicht +Z heissen.
local function sendeRichtung()
	local richtung = 0
	if gedrueckt.Vor then
		richtung -= 1
	end
	if gedrueckt.Zurueck then
		richtung += 1
	end
	PongInputEvent:FireServer(richtung)
end

local function taste(_, zustand, eingabe)
	local aktiv = zustand == Enum.UserInputState.Begin
	local code = eingabe.KeyCode
	if code == Enum.KeyCode.W or code == Enum.KeyCode.Up then
		gedrueckt.Vor = aktiv
	elseif code == Enum.KeyCode.S or code == Enum.KeyCode.Down then
		gedrueckt.Zurueck = aktiv
	else
		return Enum.ContextActionResult.Pass
	end
	sendeRichtung()
	return Enum.ContextActionResult.Sink
end

local function beende()
	if not spieltGerade then
		return
	end
	spieltGerade = false
	gedrueckt.Vor, gedrueckt.Zurueck = false, false

	ContextActionService:UnbindAction(AKTION)
	hinweis.Enabled = false

	-- Die Kamera zurueckgeben, statt sie selbst zu setzen: welcher Blick danach gilt,
	-- entscheiden CameraFramingClient und Roblox -- sie wissen mehr darueber als dieses
	-- Skript, das nur einen Sonderfall kennt.
	camera.CameraType = vorherigerTyp or Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function beginne(zustand)
	spieltGerade = true
	vorherigerTyp = camera.CameraType

	-- Senkrecht ueber die Feldmitte. Die Hoehe waechst mit der Feldbreite, damit das ganze
	-- Feld ins Bild passt.
	local mitte = zustand.Mitte
	local hoehe = (zustand.Breite or 90) * KAMERA_HOEHE_FAKTOR
	local oben = mitte.Position + Vector3.new(0, hoehe, 0)
	camera.CameraType = Enum.CameraType.Scriptable
	-- Blickrichtung nach unten, "oben im Bild" laengs des Feldes -- sonst steht Pong quer.
	camera.CFrame = CFrame.lookAt(oben, mitte.Position, mitte.LookVector)

	ContextActionService:BindAction(AKTION, taste, false,
		Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.Up, Enum.KeyCode.Down)

	hinweisText.Text = string.format("PONG -- %s Schlaeger | W/S oder Pfeile | nochmal E zum Aufhoeren",
		zustand.Seite == "Links" and "linker" or "rechter")
	hinweis.Enabled = true
end

PongStateEvent.OnClientEvent:Connect(function(zustand)
	if type(zustand) ~= "table" then
		return
	end
	if zustand.Beigetreten then
		beginne(zustand)
	else
		beende()
	end
end)

-- Beim Respawn aufhoeren: der Server gibt den Schlaeger ohnehin frei, und eine
-- Scriptable-Kamera, die niemand mehr zuruecksetzt, laesst den Spieler blind stehen.
player.CharacterAdded:Connect(beende)

print("[Kaiju Debug] Stadion-Pong bereit -- Prompt am Feldende, dann W/S.")
