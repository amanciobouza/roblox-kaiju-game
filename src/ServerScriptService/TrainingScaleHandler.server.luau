-- VERSION: 2026-08-25 #1
-- FIX: TRAINING_SCALE aktualisiert auf neue 1-6-Skala (war 4, alte Skala)
-- Egal wie groß der Avatar aktuell ist (Skala 4 bis 14.85 je nach Skin-Stufe): an JEDER
-- der drei Trainingsstationen schrumpft er auf Level-0-Größe (Scale 4) runter -- sorgt für
-- konsistente Kamera-Framing/Dashboard-Sichtbarkeit unabhängig vom aktuellen Skin. Nach
-- Verlassen des Trainings wird die ursprüngliche Größe wiederhergestellt.
--
-- Nutzt dieselbe character:ScaleTo() + HipHeight-Neuberechnung wie PlayerSetup.lua (die
-- etablierte, funktionierende Methode in diesem Projekt -- NICHT die einzelnen
-- Humanoid-Scale-Properties einzeln setzen, das führte früher zu Proportions-Problemen).

local Players = game:GetService("Players")

local TRAINING_SCALE = 0.6 -- Level-0-Skala, siehe SkinsConfig.lua (aktualisiert von 4 auf 1 -- neue, vereinfachte 1-6-Skala)

local originalScale = {} -- [player] = number, um nach dem Training wiederherzustellen

local function applyScale(player, targetScale)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local currentScaleOk, currentScale = pcall(function()
		return character:GetScale()
	end)
	if currentScaleOk and math.abs(currentScale - targetScale) < 0.001 then
		return -- schon auf der Zielgröße, nichts zu tun
	end

	local ok = pcall(function()
		character:ScaleTo(targetScale)
	end)
	if not ok then
		warn("[TrainingScaleHandler] character:ScaleTo() fehlgeschlagen für " .. player.Name)
		return
	end

	-- Gleiche HipHeight-Korrektur wie in PlayerSetup.lua -- verhindert die
	-- hängengebliebene Freifall-Pose nach dem Skalieren.
	local root = character:FindFirstChild("HumanoidRootPart")
	local leftFoot = character:FindFirstChild("LeftFoot")
	local rightFoot = character:FindFirstChild("RightFoot")

	task.defer(function()
		if not humanoid.Parent then
			return
		end
		task.wait() -- ein Frame warten, bis Gelenke/Teile nach ScaleTo() aktualisiert sind

		if root and leftFoot and rightFoot then
			local soleY = math.min(
				leftFoot.Position.Y - leftFoot.Size.Y / 2,
				rightFoot.Position.Y - rightFoot.Size.Y / 2
			)
			humanoid.HipHeight = (root.Position.Y - root.Size.Y / 2) - soleY + 0.1
		end

		humanoid.PlatformStand = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end

		-- WICHTIG: Falls der Spieler GERADE schwimmt, NICHT gewaltsam auf "Running"
		-- umschalten -- siehe Kommentar in PlayerSetup.lua für die genaue Begründung
		-- (Auftriebs-Physik-Konflikt, verursacht Durchfallen/Hochschleudern im Wasser).
		if humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			task.wait()
			if humanoid.Parent and humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end
		end
	end)
end

local function isInAnyTraining(player)
	return player:GetAttribute("TrainingStat") ~= nil or player:GetAttribute("BodyTrainingActive") == true
end

local function updateTrainingScale(player)
	local inTraining = isInAnyTraining(player)
	local wasInTraining = originalScale[player] ~= nil

	if inTraining and not wasInTraining then
		-- Training beginnt: ursprüngliche Größe merken, auf Level-0-Größe schrumpfen.
		local character = player.Character
		local currentScaleOk, currentScale = pcall(function()
			return character and character:GetScale()
		end)
		originalScale[player] = (currentScaleOk and currentScale) or TRAINING_SCALE
		applyScale(player, TRAINING_SCALE)
	elseif not inTraining and wasInTraining then
		-- Training endet: ursprüngliche Größe wiederherstellen.
		local targetScale = originalScale[player]
		originalScale[player] = nil
		applyScale(player, targetScale)
	end
end

Players.PlayerAdded:Connect(function(player)
	player:GetAttributeChangedSignal("TrainingStat"):Connect(function()
		updateTrainingScale(player)
	end)
	player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(function()
		updateTrainingScale(player)
	end)

	-- Falls der Charakter mitten im Training respawnt: Skala erneut auf Level-0-Größe
	-- setzen, damit sie nicht durch den normalen Skin-Setup-Prozess überschrieben bleibt.
	player.CharacterAdded:Connect(function()
		if isInAnyTraining(player) then
			task.wait(0.5) -- kurz warten, bis PlayerSetup.lua die normale Skin-Größe gesetzt hat
			applyScale(player, TRAINING_SCALE)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	originalScale[player] = nil
end)