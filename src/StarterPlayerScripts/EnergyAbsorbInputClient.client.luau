-- LocalScript: EnergyAbsorbInputClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Meldet dem Server, ob der Spieler gerade aktiv Energie "saugt" -- ein eigener,
-- gehaltener Bildschirm-Button (PC UND Mobile). Bewusst KEINE Maustaste mehr -- rechte
-- Maustaste wird für die Kameraperspektive gebraucht. Ohne gehaltenen Button fliesst
-- keine Energie, egal wie nah man an einer Feuerquelle steht (siehe
-- EnergyCollectionHandler.lua).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SetAbsorbingEvent = ReplicatedStorage:WaitForChild("SetAbsorbingEvent")

local isAbsorbing = false

local function setAbsorbing(value)
	if isAbsorbing == value then
		return
	end
	isAbsorbing = value
	SetAbsorbingEvent:FireServer(value)
end

-- Sicherheitsnetz: falls der Fokus verloren geht (z.B. Alt-Tab, Menü öffnen) während der
-- Button gehalten wird, bleibt sonst evtl. "IsAbsorbing" fälschlich hängen.
UserInputService.WindowFocusReleased:Connect(function()
	setAbsorbing(false)
end)

-- ===== Eigener Bildschirm-Button, immer sichtbar (PC + Mobile) =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EnergyAbsorbGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Aufbau wie die vier Angriffsknoepfe: gleicher dunkler Grund, gleiche Stahllinie,
-- Symbol, Bezeichnung, Unterzeile. Der Knopf war bisher rund und cyan gefuellt -- die
-- Farbe traegt nach der neuen Stilregel nur noch das Symbol, nicht der Grund.
--
-- Er bleibt vorerst an seinem Platz unten rechts. In Scheibe 4 rueckt er in die rechte
-- Gruppe neben Focus und Area, wo er hingehoert.
local absorbButton = Instance.new("TextButton")
absorbButton.Name = "AbsorbButton"
absorbButton.Size = UDim2.new(0, 128, 0, 104)
absorbButton.AnchorPoint = Vector2.new(1, 1)
absorbButton.Position = UDim2.new(1, -20, 1, -140)
absorbButton.AutoButtonColor = false
absorbButton.Text = ""
absorbButton.Parent = screenGui
HudChrome.Panel(absorbButton, { radius = HudChrome.Radius.Panel, transparency = 0.08 })

local iconLabel = Instance.new("TextLabel")
iconLabel.Name = "Icon"
iconLabel.Size = UDim2.new(1, 0, 0, 42)
iconLabel.Position = UDim2.new(0, 0, 0, 4)
iconLabel.BackgroundTransparency = 1
iconLabel.Font = HudChrome.Font.Label
iconLabel.TextScaled = true
-- Geometrisches Zeichen statt des Emoji 🌀 -- dieselbe Begruendung wie bei den
-- Angriffsknoepfen: ein Emoji zeichnet das Betriebssystem in seinem eigenen Stil und
-- laesst sich nicht einfaerben.
iconLabel.Text = "◉"
iconLabel.TextColor3 = HudChrome.Color.Accent
iconLabel.Parent = absorbButton

local label = Instance.new("TextLabel")
label.Name = "NameLabel"
label.Size = UDim2.new(1, -10, 0, 22)
label.Position = UDim2.new(0, 5, 0, 48)
label.BackgroundTransparency = 1
label.Text = "ABSORB"
label.Parent = absorbButton
HudChrome.Label(label)

local subLabel = Instance.new("TextLabel")
subLabel.Name = "SubLabel"
subLabel.Size = UDim2.new(1, -10, 0, 15)
subLabel.Position = UDim2.new(0, 5, 0, 71)
subLabel.BackgroundTransparency = 1
subLabel.Text = "DRAW MATTER"
subLabel.Parent = absorbButton
HudChrome.Sublabel(subLabel)

-- Der Akzentstreifen zeigt hier keinen Vorrat -- Absorbieren kostet nichts. Er leuchtet,
-- solange gesaugt wird, und ist sonst gedaempft. Damit sagt er dasselbe wie bei den
-- anderen Knoepfen: laeuft gerade, oder nicht.
local _, absorbAccent = HudChrome.AccentBar(absorbButton, HudChrome.Color.Accent)
absorbAccent.BackgroundTransparency = 0.55

-- Tastenhinweis in der Ecke, wie bei Focus und Area. Er stand vorher IN der Bezeichnung
-- ("Absorb (X)") -- damit war die Bezeichnung je nach Eingabegeraet verschieden lang und
-- passte nicht mehr zu den anderen Knoepfen.
local keyLabel = Instance.new("TextLabel")
keyLabel.Name = "KeyHint"
keyLabel.Size = UDim2.new(0, 22, 0, 18)
keyLabel.AnchorPoint = Vector2.new(1, 0)
keyLabel.Position = UDim2.new(1, -6, 0, 6)
keyLabel.BackgroundTransparency = 1
keyLabel.Text = "X"
keyLabel.Parent = absorbButton
HudChrome.Number(keyLabel, 12)
keyLabel.TextColor3 = HudChrome.Color.TextDim

-- Rueckmeldung beim Druecken ueber den Akzentstreifen statt ueber den Grund. Der Grund
-- ist nach der neuen Stilregel bei allen Knoepfen derselbe dunkle Ton -- ihn umzufaerben
-- wuerde die Regel brechen und faende ausserdem auf dem Knopf statt an der Anzeige statt.
local function onPressStart()
	setAbsorbing(true)
	absorbAccent.BackgroundTransparency = 0
end

local function onPressEnd()
	setAbsorbing(false)
	absorbAccent.BackgroundTransparency = 0.55
end

-- Reagiert auf Maus (PC) UND Touch (Mobile) gleichermassen -- ein Button für beide
-- Plattformen, statt getrennter Maustasten-/Touch-Logik.
absorbButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		onPressStart()
	end
end)

absorbButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		onPressEnd()
	end
end)

-- Falls die Maus den Button verlässt, WÄHREND sie gedrückt gehalten wird (z.B. schnell
-- wegbewegt), soll das Saugen trotzdem enden -- sonst könnte es fälschlich aktiv bleiben.
absorbButton.MouseLeave:Connect(function()
	if isAbsorbing then
		onPressEnd()
	end
end)

-- ===== Eigene Eingabe, getrennt vom Schlag =====
-- Das Absorbieren lag frueher ebenfalls auf F -- derselben Taste wie der Schlag. Damit
-- war die Absicht der Balancing-Spezifikation technisch unmoeglich: Absorbieren und
-- Angreifen sollen GLEICHZEITIG gehen, denn nur dann gehen drei ihrer Zahlen zusammen
-- auf (88 % erhaltene Energie, 20 Minuten Referenzzeit, viereinhalb Durchgaenge).
--
-- X, weil es neben den WASD-Tasten liegt: der Ringfinger haelt es, waehrend Zeige- und
-- Mittelfinger weiter laufen und angreifen.
--
-- Zuerst lag es auf Strg -- fuer den kleinen Finger noch bequemer, aber Strg loest im
-- Roblox Studio eigene Befehle aus und ist deshalb im Test unbrauchbar.
--
-- Am Gamepad bleibt es die linke Schultertaste: dort liegt der Zeigefinger ohnehin und die
-- Daumen bleiben frei.
local ABSORB_KEYS = {
	[Enum.KeyCode.X] = true,
	[Enum.KeyCode.ButtonL1] = true,
}

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if ABSORB_KEYS[input.KeyCode] then
		onPressStart()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if ABSORB_KEYS[input.KeyCode] then
		onPressEnd()
	end
end)

-- Der Tastenhinweis nennt die Taste des Geraets, an dem gerade gespielt wird. Auf einem
-- Beruehrungsbildschirm gibt es keine, dort verschwindet er ganz -- die Bezeichnung
-- "ABSORB" bleibt in jedem Fall dieselbe.
local function refreshAbsorbLabel()
	local lastInput = UserInputService:GetLastInputType()
	if lastInput == Enum.UserInputType.Touch then
		keyLabel.Visible = false
	elseif string.find(tostring(lastInput), "Gamepad") then
		keyLabel.Visible = true
		keyLabel.Text = "L1"
	else
		keyLabel.Visible = true
		keyLabel.Text = "X"
	end
end

UserInputService.LastInputTypeChanged:Connect(refreshAbsorbLabel)
refreshAbsorbLabel()