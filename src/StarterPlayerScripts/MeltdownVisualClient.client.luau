-- VERSION: 2026-08-19 #1
-- LocalScript: MeltdownVisualClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Teilweise Entsättigung der Umgebung, sobald der kontrollierte Berserk-Modus startet
-- (nicht erst bei Meltdown -- Heat=100 vertieft die Entsättigung zusätzlich, siehe
-- unten). NUR für den betroffenen Spieler selbst sichtbar -- ein ColorCorrectionEffect,
-- der an der eigenen Kamera (statt an Lighting) hängt, bleibt rein lokal und beeinflusst
-- nicht, was andere Spieler sehen. Das kräftige Rot-Leuchten des Avatars selbst
-- (Highlight + PointLight, siehe BerserkerAuraClient.lua) läuft dagegen für ALLE sichtbar.
--
-- Zusätzlich: kurzer Kamera-FOV-Puls beim Berserk-START (BOOM-Gefühl) -- relativ zur
-- AKTUELLEN FOV des Spielers (nicht auf einen festen Wert gesetzt), damit eine vom
-- Spieler selbst gewählte FOV-Einstellung nicht überschrieben wird.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local BERSERK_SATURATION = -0.65 -- Startwert beim Berserk-Beginn
local MELTDOWN_SATURATION = -0.7 -- vertieft sich zusätzlich, sobald Heat=100 (Meltdown) erreicht ist -- teilweise, nicht volle -1, sonst würde auch das Rot-Leuchten mit ausgegraut
local FADE_TIME = 1.2
local DEPTH_CHANGE_TIME = 0.6 -- schnellerer Übergang für den Meltdown-Vertiefungs-Schritt (Berserk läuft ja schon)

local FOV_PULSE_UP = 6 -- Studs über die aktuelle FOV beim ersten Ausschlag
local FOV_PULSE_SETTLE = 2 -- bleibt kurz leicht erhöht, bevor es auf die ursprüngliche FOV zurückgeht
local FOV_PULSE_STEP_TIME = 0.1 -- 3 Schritte à 0.1s = 0.3s Gesamtdauer, wie im Konzept

local meltdownEffect = Instance.new("ColorCorrectionEffect")
meltdownEffect.Name = "MeltdownDesaturation"
meltdownEffect.Saturation = 0
meltdownEffect.Parent = camera

local isBerserkActive = false

-- ===== Kamera-FOV-Puls beim Berserk-Start: base -> +6 -> +2 -> zurück auf base, relativ
-- zur AKTUELLEN FOV (nicht fest auf 70/76/72, falls der Spieler eine andere FOV gewählt
-- hat). =====
local function playFovPulse()
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		return
	end
	-- Waehrend eines Showdowns nicht: der Puls veraendert die Brennweite und unterlaeuft
	-- damit jede Bildkomposition der Kampfkamera. Und weil der Spieler dort oft im
	-- Berserker-Zustand ist -- er macht ja gerade viel Schaden --, waere das nicht die
	-- Ausnahme, sondern der Normalfall. Die Bildschirm-Ruckler bleiben dagegen aktiv:
	-- ein kurzer Stoss vertraegt sich mit jeder Kamera, eine wandernde Brennweite nicht.
	if player:GetAttribute("ShowdownActive") == true then
		return
	end
	local baseFov = currentCamera.FieldOfView

	local step1 = TweenService:Create(currentCamera, TweenInfo.new(FOV_PULSE_STEP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = baseFov + FOV_PULSE_UP,
	})
	step1:Play()
	step1.Completed:Connect(function()
		local step2 = TweenService:Create(currentCamera, TweenInfo.new(FOV_PULSE_STEP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			FieldOfView = baseFov + FOV_PULSE_SETTLE,
		})
		step2:Play()
		step2.Completed:Connect(function()
			TweenService:Create(currentCamera, TweenInfo.new(FOV_PULSE_STEP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				FieldOfView = baseFov,
			}):Play()
		end)
	end)
end

-- ===== Entsättigungs-Tiefe: Berserk-Start = BERSERK_SATURATION, zusätzlich vertieft
-- Richtung MELTDOWN_SATURATION sobald Heat=100 erreicht ist, wieder etwas flacher sobald
-- Heat wieder unter 100 fällt (aber Berserk selbst noch läuft). =====
local function updateSaturationDepth()
	if not isBerserkActive then
		return
	end
	local heat = player:GetAttribute("Heat") or 0
	local target = heat >= 100 and MELTDOWN_SATURATION or BERSERK_SATURATION
	TweenService:Create(meltdownEffect, TweenInfo.new(DEPTH_CHANGE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Saturation = target,
	}):Play()
end

local function updateBerserkVisual()
	local shouldBeActive = player:GetAttribute("BerserkActive") == true

	if shouldBeActive and not isBerserkActive then
		isBerserkActive = true
		TweenService:Create(meltdownEffect, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Saturation = BERSERK_SATURATION,
		}):Play()
		playFovPulse()
	elseif not shouldBeActive and isBerserkActive then
		isBerserkActive = false
		TweenService:Create(meltdownEffect, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Saturation = 0,
		}):Play()
	end
end

player:GetAttributeChangedSignal("BerserkActive"):Connect(updateBerserkVisual)
player:GetAttributeChangedSignal("Heat"):Connect(updateSaturationDepth)

-- Falls sich die eigene Kamera mal ändert (z.B. durch ein anderes Script neu erstellt),
-- den Effekt am aktuellen CurrentCamera neu verankern.
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local newCamera = Workspace.CurrentCamera
	if newCamera and meltdownEffect.Parent ~= newCamera then
		meltdownEffect.Parent = newCamera
	end
end)