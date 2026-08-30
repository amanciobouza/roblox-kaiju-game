-- VERSION: 2026-08-25 #1
-- ModuleScript: EnergyTypeSkin
-- Ort in Studio: ServerScriptService (gleiche Ebene wie HouseHandler.lua)
--
-- Ausgelagert aus HouseHandler.lua (war dort direkt eingebettet) -- rein visuelle Logik,
-- komplett unabhängig vom Rest der Zerstörungs-/Respawn-Kernlogik. Erster Schritt des
-- geplanten schrittweisen HouseHandler.lua-Refactorings (grösste Datei im Projekt).
--
-- Gebäude mit einem "EnergyType"-Attribut ungleich "Heat" (dem Standard) bekommen
-- automatisch eine passende Einfärbung + Leucht-Effekt + Symbol -- macht auf einen Blick
-- erkennbar, welche Energie ein Gebäude gibt, ohne dass jedes Gebäude von Hand
-- umgestaltet werden muss. Dieselben Farben wie im HUD (EnergyTypesClient.lua), damit es
-- konsistent wirkt.

local TweenService = game:GetService("TweenService")

local EnergyTypeSkin = {}

local ENERGY_TYPE_VISUALS = {
	Chemical = { color = Color3.fromRGB(255, 45, 190), icon = "⚗️" },
	Electric = { color = Color3.fromRGB(57, 217, 255), icon = "⚡" },
	Radiation = { color = Color3.fromRGB(126, 255, 16), icon = "☢️" },
	Spirit = { color = Color3.fromRGB(255, 205, 70), icon = "✨" },
	-- "Heat" bewusst NICHT hier -- das ist der Standard-Look, unverändert.
}

function EnergyTypeSkin.Apply(house)
	-- Spawn-Zeit-Würfelung: bei jedem Spawnen/Respawnen neu entschieden (siehe
	-- EnergyCollectionHandler.lua, rollSpawnEnergyType) -- betrifft nur Heat-Gebäude,
	-- alles andere bleibt fix beim deklarierten Typ. Ergebnis wird gespeichert, damit
	-- Optik UND tatsächlicher Sammel-Ertrag garantiert übereinstimmen.
	local declaredType = house:GetAttribute("EnergyType")
	local effectiveType = (_G.RollSpawnEnergyType and _G.RollSpawnEnergyType(declaredType)) or declaredType or "Heat"
	house:SetAttribute("EffectiveEnergyType", effectiveType)

	local visual = ENERGY_TYPE_VISUALS[effectiveType]
	local anchorPart = house.PrimaryPart
	local existingGlowAnchor = house:FindFirstChild("EnergyTypeGlowAnchor")
	local existingIcon = anchorPart and anchorPart:FindFirstChild("EnergyTypeIcon")

	if not visual then
		-- Kein besonderer Typ (mehr) -- z.B. beim Respawn zurück auf normales Heat
		-- gewürfelt. Evtl. vorhandene Dekoration von einem FRÜHEREN Spawn entfernen und
		-- die Original-Farbe wiederherstellen.
		if existingGlowAnchor then
			existingGlowAnchor:Destroy()
		end
		if existingIcon then
			existingIcon:Destroy()
		end
		for _, part in ipairs(house:GetDescendants()) do
			if part:IsA("BasePart") and part:GetAttribute("OriginalColor") then
				part.Color = part:GetAttribute("OriginalColor")
			end
		end
		return
	end

	-- Jedes Teil nur LEICHT in Richtung der Energie-Farbe einfärben (Original-Look bleibt
	-- klar dominant, nur ein dezenter Farbstich) -- kein Neon-Material mehr (das leuchtet
	-- inhärent stark nach, unabhängig von der Farbe selbst). Die Färbung pulsiert weiterhin
	-- leicht, aber zwischen zwei deutlich näher beieinanderliegenden Werten statt bis zur
	-- vollen Sättigung -- macht Gebäude mit untypischer Energie erkennbar, ohne zu blinken.
	for _, part in ipairs(house:GetDescendants()) do
		if part:IsA("BasePart") and not part:GetAttribute("IsTechnicalPart") then
			if part:GetAttribute("OriginalColor") == nil then
				part:SetAttribute("OriginalColor", part.Color) -- einmalig sichern, falls später mal zurückgesetzt werden soll
			end
			local originalColor = part:GetAttribute("OriginalColor")
			local dimColor = originalColor:Lerp(visual.color, 0.06)
			local brightColor = originalColor:Lerp(visual.color, 0.12)
			part.Color = dimColor

			-- Jedes Teil pulsiert leicht zeitversetzt (kleine zufällige Verzögerung),
			-- damit es nicht wie ein starres, künstliches Ganzes wirkt.
			task.delay(math.random() * 0.6, function()
				if not part.Parent then
					return
				end
				local pulseTween = TweenService:Create(
					part,
					TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Color = brightColor }
				)
				pulseTween:Play()
			end)
		end
	end

	-- Leucht-Effekt: kräftiges farbiges Licht knapp ÜBER DEM BODEN (nicht am PrimaryPart --
	-- das kann bei hohen Gebäuden weit oben im Gebäude sitzen, wodurch das Licht
	-- unrealistisch hoch im Himmel erscheinen würde). Eigener, unsichtbarer Anker an der
	-- tatsächlichen Boden-Position des Gebäudes (aus der Bounding-Box berechnet).
	if anchorPart then
		if existingGlowAnchor then
			-- Von einem früheren Spawn übrig -- nur die Farbe aktualisieren (Typ könnte
			-- sich zwischen zwei Respawns geändert haben), nicht komplett neu bauen.
			local light = existingGlowAnchor:FindFirstChild("EnergyTypeGlow")
			if light then
				light.Color = visual.color
			end
		else
			local ok, cframe, size = pcall(function()
				return house:GetBoundingBox()
			end)
			local groundPosition
			if ok then
				groundPosition = Vector3.new(cframe.Position.X, cframe.Position.Y - size.Y / 2 + 2, cframe.Position.Z)
			else
				groundPosition = anchorPart.Position
			end

			local glowAnchor = Instance.new("Part")
			glowAnchor.Name = "EnergyTypeGlowAnchor"
			glowAnchor.Anchored = true
			glowAnchor.CanCollide = false
			glowAnchor.CanQuery = false
			glowAnchor.Transparency = 1
			glowAnchor.Size = Vector3.new(1, 1, 1)
			glowAnchor.CFrame = CFrame.new(groundPosition)
			glowAnchor.Parent = house

			local light = Instance.new("PointLight")
			light.Name = "EnergyTypeGlow"
			light.Color = visual.color
			light.Brightness = 0.8
			light.Range = 24
			light.Parent = glowAnchor

			local lightPulseTween = TweenService:Create(
				light,
				TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Brightness = 1.6 }
			)
			lightPulseTween:Play()
		end
	end

	-- Symbol über dem Gebäude -- gut aus der Distanz erkennbar, auch wenn die Einfärbung
	-- selbst evtl. nicht sofort auffällt (z.B. bei ungünstigem Blickwinkel/Beleuchtung).
	if anchorPart then
		if existingIcon then
			-- Von einem früheren Spawn übrig -- nur das Icon aktualisieren.
			local iconLabel = existingIcon:FindFirstChildWhichIsA("TextLabel")
			if iconLabel then
				iconLabel.Text = visual.icon
			end
		else
			local ok, cframe, size = pcall(function()
				return house:GetBoundingBox()
			end)
			local topOffsetY = ok and ((cframe.Position.Y + size.Y / 2) - anchorPart.Position.Y + 8) or 6

			local billboard = Instance.new("BillboardGui")
			billboard.Name = "EnergyTypeIcon"
			billboard.Size = UDim2.new(0, 36, 0, 36)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffsetY, 0)
			billboard.AlwaysOnTop = true
			billboard.MaxDistance = 400
			billboard.Parent = anchorPart

			local iconLabel = Instance.new("TextLabel")
			iconLabel.Size = UDim2.new(1, 0, 1, 0)
			iconLabel.BackgroundTransparency = 1
			iconLabel.Font = Enum.Font.LuckiestGuy
			iconLabel.TextScaled = true
			iconLabel.Text = visual.icon
			iconLabel.Parent = billboard

			-- Schwebe-Effekt: pendelt sanft nach oben/unten, wie ein Symbol das in der Luft
			-- schwebt statt starr zu stehen.
			local floatTween = TweenService:Create(
				billboard,
				TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ StudsOffsetWorldSpace = Vector3.new(0, topOffsetY + 1.5, 0) }
			)
			floatTween:Play()
		end
	end
end

return EnergyTypeSkin