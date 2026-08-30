-- VERSION: 2026-08-21 #10
-- Script: StatueService
-- Ort in Studio: ServerScriptService
--
-- Zeigt zwei feste Steinstatuen in Sanctuary, die den ECHTEN ROBLOX-STANDARD-AVATAR
-- der beiden genannten Spieler nachbilden (nicht den In-Game-Kaiju-Skin) --
-- unabhängig davon, ob diese Person gerade online ist (Robloxs Avatar-API liefert die
-- öffentlich sichtbare Erscheinung für jede UserId, ganz ohne dass die Person online
-- sein muss).
--
-- SETUP IN STUDIO (zwingend nötig, sonst passiert nichts):
-- 1. In Workspace.Sanctuary zwei Teile (Parts) platzieren, die die STANDORTE markieren.
--    Namen müssen exakt "StatueSpawn_cPOEt78" und "StatueSpawn_YellAshow" lauten.
--    Die Statue erscheint an der CFrame-Position dieses Teils (Blickrichtung = die
--    Ausrichtung des Markers). Der Marker selbst bleibt sichtbar (wird nicht entfernt) --
--    am besten also Transparency=1, CanCollide=false setzen.
-- 2. Dieses Script muss ein normales SCRIPT sein (kein ModuleScript) -- sonst läuft es
--    nie von selbst.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Die beiden Ziel-Benutzernamen -- Usernamen statt fester UserIds, damit das Script auch
-- bei einer eventuellen Namensänderung ohne Anpassung weiterläuft (Roblox löst das zur
-- Laufzeit auf).
local TARGET_USERNAMES = { "cPOEt78", "YellAshow" }

-- Skalierungsfaktor gegenüber der normalen Avatar-Grösse.
local STATUE_SCALE = 3

local activeStatues = {} -- [username] = Model

local function findSpawnMarker(username)
	local sanctuary = Workspace:FindFirstChild("Sanctuary")
	if not sanctuary then
		warn("[StatueService] Workspace.Sanctuary nicht gefunden -- Statuen können nicht platziert werden.")
		return nil
	end
	local marker = sanctuary:FindFirstChild("StatueSpawn_" .. username)
	if not marker then
		warn("[StatueService] Kein Marker 'StatueSpawn_" .. username .. "' in Workspace.Sanctuary gefunden -- Statue übersprungen.")
	end
	return marker
end

-- Macht das Modell komplett statisch (verankert, keine Kollision, keine Scripts) --
-- Farbe/Material/Texturen bleiben unverändert, zeigt also den echten Original-Avatar.
local function makeStatic(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
		elseif descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.RequiresNeck = false
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			descendant.NameDisplayDistance = 0
		end
	end
end

-- Baut (oder ersetzt) die Statue für einen Zielnamen anhand des ECHTEN Roblox-Avatars
-- dieser UserId.
local function buildStatue(username, userId)
	local marker = findSpawnMarker(username)
	if not marker then
		return
	end

	local descriptionOk, humanoidDescription = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if not descriptionOk or not humanoidDescription then
		warn("[StatueService] Konnte Roblox-Avatar-Beschreibung für '" .. username .. "' nicht laden -- Statue übersprungen.")
		return
	end

	local modelOk, avatarModel = pcall(function()
		return Players:CreateHumanoidModelFromDescription(humanoidDescription, Enum.HumanoidRigType.R15)
	end)
	if not modelOk or not avatarModel then
		warn("[StatueService] Konnte Avatar-Modell für '" .. username .. "' nicht erstellen -- Statue übersprungen.")
		return
	end

	-- Alte Statue (falls vorhanden) zuerst entfernen.
	if activeStatues[username] then
		activeStatues[username]:Destroy()
		activeStatues[username] = nil
	end

	avatarModel.Name = "Statue_" .. username
	avatarModel.Parent = Workspace
	avatarModel:PivotTo(marker.CFrame)

	-- WICHTIG: Direkte Humanoid-Scale-Properties statt Model:ScaleTo() -- ScaleTo()
	-- führte bei echten Avataren (mit ihren jeweils EIGENEN, individuellen Körper-
	-- Proportionen) zu einem "zusammengestauchten" Ergebnis. Stattdessen werden die vier
	-- Skalierungs-Werte einzeln mit demselben Faktor multipliziert -- bewahrt dadurch die
	-- individuellen Proportionen jeder Person exakt, nur insgesamt grösser.
	local humanoid = avatarModel:FindFirstChildOfClass("Humanoid")
	local scaleOk = pcall(function()
		if humanoid then
			local bodyHeightScale = humanoid:FindFirstChild("BodyHeightScale")
			local bodyWidthScale = humanoid:FindFirstChild("BodyWidthScale")
			local bodyDepthScale = humanoid:FindFirstChild("BodyDepthScale")
			local headScale = humanoid:FindFirstChild("HeadScale")
			if bodyHeightScale then
				bodyHeightScale.Value = bodyHeightScale.Value * STATUE_SCALE
			end
			if bodyWidthScale then
				bodyWidthScale.Value = bodyWidthScale.Value * STATUE_SCALE
			end
			if bodyDepthScale then
				bodyDepthScale.Value = bodyDepthScale.Value * STATUE_SCALE
			end
			if headScale then
				headScale.Value = headScale.Value * STATUE_SCALE
			end
		end
	end)
	if not scaleOk then
		warn("[StatueService] Skalierung für Statue '" .. username .. "' fehlgeschlagen -- Statue bleibt in Standardgrösse.")
	end

	-- Kurze Wartezeit -- die Humanoid-Skalierung braucht einen Moment, um sich
	-- vollständig auf das Rig (Gelenke, Grösse) auszuwirken. Ohne diese Wartezeit kann
	-- die Statue trotz PivotTo() direkt danach wieder vom Marker wegdriften, weil die
	-- Skalierung erst NACH der Positionierung vollständig durchschlägt.
	task.wait()

	-- Wieder einfach direkt auf den Marker setzen (Bounding-Box-Korrektur entfernt).
	avatarModel:PivotTo(marker.CFrame)

	makeStatic(avatarModel)

	activeStatues[username] = avatarModel
	local partCount = 0
	for _, descendant in ipairs(avatarModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partCount += 1
		end
	end
	print("[StatueService] Statue für '" .. username .. "' gebaut (echter Roblox-Avatar) -- Position:", avatarModel:GetPivot().Position, "-- Teile-Anzahl:", partCount)
end

local function setupStatueForUsername(username)
	local userIdOk, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)
	if not userIdOk or not userId then
		warn("[StatueService] Konnte UserId für '" .. username .. "' nicht auflösen -- Statue übersprungen.")
		return
	end

	buildStatue(username, userId)
end

for _, username in ipairs(TARGET_USERNAMES) do
	task.spawn(setupStatueForUsername, username)
end

print("[StatueService] bereit -- Statuen für: " .. table.concat(TARGET_USERNAMES, ", "))