-- VERSION: 2026-08-25 #1 (RemoteEventUtils-Umstellung)
-- LocalScript: EnergyAbsorbClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Zeigt einen kleinen, glühenden Partikel, der von einer Energiequelle (Explosion/Feuer)
-- zum Spieler fliegt und dabei "aufgesogen" wird -- visuelles Feedback fürs kontinuierliche
-- Energie-Sammeln (EnergyCollectionHandler.lua).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local StageModels = require(ReplicatedStorage:WaitForChild("StageModels"))
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local EnergyAbsorbEvent = RemoteEventUtils.GetOrCreate("EnergyAbsorbEvent")

local ABSORB_DURATION = 0.5

-- Farben aus HudChrome. Hier stand eine eigene Kopie, und der Kommentar daneben behauptete,
-- es seien "dieselben Farben wie im Talentbaum/HUD" -- fuer Heat stimmte das nicht: dort
-- rot, hier orange. Genau so laufen zwei Listen auseinander, die niemand vergleicht.
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

-- Bremst zu häufige Effekt-Spawns aus (bei mehreren Feuerquellen in Reichweite könnten
-- sonst viele Partikel pro Sekunde entstehen -- reicht völlig, alle paar Ticks EINEN
-- sichtbaren Partikel zu zeigen statt für jeden einzelnen Energie-Tick).
local lastEffectTime = 0
local EFFECT_COOLDOWN = 0.3

local function showAbsorbParticle(sourcePosition, energyType)
	local now = os.clock()
	if now - lastEffectTime < EFFECT_COOLDOWN then
		return
	end
	lastEffectTime = now

	-- ===== Ziel ist die sichtbare Figur, nicht der Avatar =====
	-- Hier stand einmal der Kopf des Avatars. Traegt der Spieler ein Kaiju-Modell, ist der
	-- Avatar versteckt und gegenueber dem Modell winzig -- sein Kopf steht dann etwa auf
	-- Schienbeinhoehe, zwischen den Beinen. Die Baender liefen dorthin und endeten sichtbar
	-- VOR der Figur statt an ihr. StageModels.GetBodyPoint nennt den Brustkorb des Modells.
	local character = player.Character
	local ziel = StageModels.GetBodyPoint(character)
	if not ziel then
		return
	end

	local energyColor = HudChrome.EnergyColor[energyType] or HudChrome.EnergyColorDefault

	local part = Instance.new("Part")
	part.Name = "EnergyAbsorbParticle"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	part.Position = sourcePosition + Vector3.new(math.random(-2, 2), math.random(0, 2), math.random(-2, 2))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = energyColor
	part.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = energyColor
	light.Range = 6
	light.Brightness = 2
	light.Parent = part

	local tween = TweenService:Create(
		part,
		TweenInfo.new(ABSORB_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = ziel, Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 0.6 }
	)
	tween:Play()

	task.delay(ABSORB_DURATION, function()
		part:Destroy()
	end)
end

EnergyAbsorbEvent.OnClientEvent:Connect(showAbsorbParticle)