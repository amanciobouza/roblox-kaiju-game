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

local SmoothMotion = require(ReplicatedStorage:WaitForChild("SmoothMotion", 10))

-- Tag-Liste und Zielwerte werden bei Aenderungen gepflegt, nicht jedes Bild neu gesucht.
local models = {}
local POSITION_EPSILON = 0.001
local ANGLE_EPSILON = 0.0001

local function gleichePose(a, b)
	if a == b then return true end
	if (a.Position - b.Position).Magnitude > POSITION_EPSILON then
		return false
	end
	local _, angle = a:ToObjectSpace(b):ToAxisAngle()
	return math.abs(angle) <= ANGLE_EPSILON
end

local function vergiss(model)
	local state = models[model]
	if state then
		state.connection:Disconnect()
		models[model] = nil
	end
end

local function merke(model)
	if not model:IsA("Model") or models[model] then return end
	local state = {}
	local function liesZiel()
		local value = model:GetAttribute(SmoothMotion.TargetAttribute)
		state.target = typeof(value) == "CFrame" and value or nil
	end
	state.connection = model:GetAttributeChangedSignal(SmoothMotion.TargetAttribute):Connect(liesZiel)
	liesZiel()
	state.shown = state.target
	models[model] = state
end

CollectionService:GetInstanceAddedSignal(SmoothMotion.Tag):Connect(merke)
CollectionService:GetInstanceRemovedSignal(SmoothMotion.Tag):Connect(vergiss)
for _, model in ipairs(CollectionService:GetTagged(SmoothMotion.Tag)) do
	merke(model)
end

local function schritt(deltaTime)
	local alpha = 1 - math.exp(-deltaTime / SmoothMotion.TimeConstant)
	for model, state in pairs(models) do
		local ziel = state.target
		if ziel and model:IsDescendantOf(workspace) then
			local aktuell = state.shown
			if not aktuell or (ziel.Position - aktuell.Position).Magnitude > SmoothMotion.SnapDistance then
				aktuell = ziel
			elseif not gleichePose(aktuell, ziel) then
				aktuell = aktuell:Lerp(ziel, alpha)
				if gleichePose(aktuell, ziel) then aktuell = ziel end
			else
				aktuell = ziel
			end
			state.shown = aktuell
			-- Auch bei unveraendertem Ziel kann die Replikation unsere Zwischenpose
			-- ueberschrieben haben. Nur ueberspringen, wenn die sichtbare Pose stimmt.
			pcall(function()
				-- ===== Animierte Modelle NUR an der Wurzel =====
				-- PivotTo setzt jedes Teil einzeln und loescht damit die Pose, die eine
				-- Motor6D-Animation gerade herstellt. Bei den Guardians hiess das: sie
				-- standen starr da, ohne Lauf- und ohne Todesanimation (14.10.2026).
				--
				-- Die uebrigen Teile folgen der Wurzel von selbst -- das Rig schweisst sie
				-- als einen Koerper daran. Genau so bewegt der Server sie auch.
				local wurzel = model:GetAttribute(SmoothMotion.RootOnlyAttribute)
					and model.PrimaryPart
					or nil

				if wurzel then
					if not gleichePose(wurzel.CFrame, aktuell) then
						wurzel.CFrame = aktuell
					end
				elseif not gleichePose(model:GetPivot(), aktuell) then
					model:PivotTo(aktuell)
				end
			end)
		end
	end
end

RunService.RenderStepped:Connect(function(deltaTime)
	debug.profilebegin("Trenchborn.Bewegungsglaettung")
	schritt(deltaTime)
	debug.profileend()
end)

print("[Kaiju Debug] SmoothMotionClient bereit -- glaettet Modelle mit dem Tag '"
	.. SmoothMotion.Tag .. "'; Tag-Cache aktiv, ruhende Posen werden nicht neu gesetzt.")
