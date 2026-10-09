-- LocalScript: SmoothMotionClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Macht serverseitig bewegte Modelle beim Betrachter flüssig. Die Begründung, warum es das
-- braucht und warum die Bewegung trotzdem beim Server bleibt, steht in SmoothMotion --
-- hier steht nur, WIE geglättet wird.
--
-- Zuständig für alles mit dem Tag SmoothMotion: Verkehrshelikopter, Militäreinheiten,
-- Guardian, und die Aufbau-Animation der Barrikaden.
--
-- ===== Warum RenderStepped und nicht Heartbeat =====
-- Weil der Server denselben CFrame weiter setzt und seine Replikation den geglätteten Wert
-- sonst überschreibt. RenderStepped läuft unmittelbar VOR dem Zeichnen -- was dort gesetzt
-- wird, ist das, was der Betrachter im selben Bild sieht. Im Heartbeat gesetzt könnte eine
-- Replikation noch dazwischenkommen, und genau dann zeigte sich der Ruck wieder.
--
-- Die Änderungen bleiben rein örtlich: ein Client, der ein Workspace-Teil setzt, ändert es
-- nur für sich. Der Server merkt davon nichts, und die Position, mit der er rechnet, bleibt
-- unberührt.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SmoothMotion = require(ReplicatedStorage:WaitForChild("SmoothMotion"))

-- [model] = die aktuell GEZEIGTE Pose. Nicht am Modell ablesbar: dort steht gerade entweder
-- unsere eigene letzte Setzung oder ein frisch replizierter Serverwert -- der eine wäre ein
-- Zwischenwert, der andere der Ruck, den wir gerade verstecken wollen. Deshalb eigene
-- Buchführung.
--
-- Schwache Schlüssel: ein entferntes Modell soll nicht durch diesen Eintrag am Leben
-- gehalten werden.
local shown = setmetatable({}, { __mode = "k" })

local function zielPose(model)
	local value = model:GetAttribute(SmoothMotion.TargetAttribute)
	if typeof(value) == "CFrame" then
		return value
	end
	return nil
end

local function vergiss(model)
	shown[model] = nil
end

CollectionService:GetInstanceAddedSignal(SmoothMotion.Tag):Connect(function(model)
	-- Beim ersten Mal nichts glätten: wo das Modell erscheint, ist es auch richtig.
	local ziel = zielPose(model)
	if ziel then
		shown[model] = ziel
	end
end)

CollectionService:GetInstanceRemovedSignal(SmoothMotion.Tag):Connect(vergiss)

local function schritt(deltaTime)
	-- Exponentielle Glättung: der zurückgelegte Anteil hängt an der verstrichenen Zeit, nicht
	-- an der Bildrate. Ein festes Alpha je Bild würde bei 30 fps halb so schnell folgen wie
	-- bei 60 -- die Glättung sähe auf jedem Gerät anders aus.
	local alpha = 1 - math.exp(-deltaTime / SmoothMotion.TimeConstant)

	for _, model in ipairs(CollectionService:GetTagged(SmoothMotion.Tag)) do
		if model:IsA("Model") and model.Parent then
			local ziel = zielPose(model)
			if ziel then
				local aktuell = shown[model]

				-- Grosse Sprünge nicht glätten, sondern übernehmen: Spawn, Teleport oder ein
				-- Wechsel der Stadt sind kein Bewegungsschritt. Geglättet flöge das Modell
				-- sichtbar durch die halbe Karte.
				if not aktuell
					or (ziel.Position - aktuell.Position).Magnitude > SmoothMotion.SnapDistance
				then
					aktuell = ziel
				else
					aktuell = aktuell:Lerp(ziel, alpha)
				end

				shown[model] = aktuell
				-- pcall, weil zwischen der Tag-Abfrage und hier ein Teil verschwinden kann
				-- (despawn mitten im Bild) -- PivotTo wirft dann.
				pcall(function()
					model:PivotTo(aktuell)
				end)
			end
		end
	end
end

RunService.RenderStepped:Connect(function(deltaTime)
	debug.profilebegin("Trenchborn.Bewegungsglaettung")
	schritt(deltaTime)
	debug.profileend()
end)

print("[Kaiju Debug] SmoothMotionClient bereit -- glaettet Modelle mit dem Tag '"
	.. SmoothMotion.Tag .. "'.")
