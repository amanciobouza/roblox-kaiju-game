-- VERSION: 2026-08-26 #2
-- FEATURE: despawnAllClustersForCity global exponiert (_G.DespawnAllBarricadeClustersForCity)
--
-- Aktiviert Stufe-3-Barrikaden-Cluster EINZELN (nicht alle auf einmal bei Level 3),
-- ausgelöst durch HouseHandler.lua, sobald ein Flankengebäude unter 50% HP fällt.
--
-- WICHTIG -- Architektur der Barrikade selbst: Das Barrikaden-Modell (aus
-- ServerStorage.BarricadeModels.Barricade) enthält BEREITS alles Nötige, inklusive
-- eines EIGENEN, eingebetteten Scripts, das auf folgende Struktur + Attribute reagiert:
--   Barricade
--   ├── (Script, reagiert auf die unten gesetzten Attribute)
--   ├── ShieldGenerators
--   │   ├── LeftGenerator   (Attribute: Health, Active)
--   │   └── RightGenerator  (Attribute: Health, Active)
--   ├── EnergyShieldPanels  (Parts, werden vom Barrikaden-Script an/aus geschaltet)
--   ├── ElectrifiedCables   (Beams + ElectricHitbox -- verlangsamt Spieler bei Berührung)
--   └── WarningTowers       (blinkende Alarm-Leuchten)
--
-- Unser Service kümmert sich NICHT mehr um diese Visuals -- das eingebettete Script
-- übernimmt das komplett, sobald wir die richtigen Attribute setzen:
--   - Barricade.ShieldEnabled (bool)      -- Schild grundsätzlich an/aus
--   - LeftGenerator/RightGenerator.Health (number) -- pro Generator
--   - LeftGenerator/RightGenerator.Active (bool)   -- pro Generator
--
-- Zusätzlich zum Generator-Zustand hat das Schild bei UNS einen eigenen, separat
-- beschiessbaren Health-Pool (ShieldHealth) -- der Cluster gilt als zerstört, sobald
-- ENTWEDER der Schild-Pool ODER einer der beiden Generatoren auf 0 fällt (das
-- eingebettete Script verlangt ohnehin BEIDE Generatoren aktiv, damit das Schild
-- überhaupt wirkt).
--
-- Für die FLANKENGEBÄUDE (bestehende Häuser andernorts in der Welt, nicht Teil des
-- Barrikaden-Modells) bauen wir weiterhin ein eigenes Kraftfeld-Visual + Beam-Verbindung
-- zur Barrikade -- das kann das eingebettete Script naturgemäss nicht abdecken, da es
-- nichts von den Flankengebäuden weiss.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")

local CityAlertConfig = require(ReplicatedStorage:WaitForChild("CityAlertConfig"))

local BARRICADE_SPAWNS_ROOT = "BarricadeSpawns"
local BARRICADE_ALARM_SOUND_ID = "rbxassetid://910988901"

-- ===== Alarm-Sound beim Aktivieren eines Clusters -- gleiches Muster wie
-- playDistantSirens bei der Feuerwehr (FireEngineController.lua). =====
local function playBarricadeAlarm(position)
	local sound = Instance.new("Sound")
	sound.Name = "BarricadeAlarm"
	sound.SoundId = BARRICADE_ALARM_SOUND_ID
	sound.Volume = 0.6
	sound.RollOffMaxDistance = 400
	sound.RollOffMinDistance = 40
	sound.Parent = Workspace

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	sound.Parent = anchor

	if sound.SoundId ~= "" and sound.SoundId ~= "rbxassetid://0" then
		sound:Play()
	end
	sound.Ended:Connect(function()
		anchor:Destroy()
	end)
	game:GetService("Debris"):AddItem(anchor, 15) -- Absicherung, falls Ended aus irgendeinem Grund nicht feuert
end

-- WICHTIG: Erwartet das Quell-Modell unter ServerStorage.BarricadeModels.Barricade --
-- bitte in Studio anlegen (je Tier ggf. unterschiedliche Modelle, siehe
-- ServerStorage.BarricadeModels.[TierName].Barricade für den optionalen Sonderfall
-- "andere Optik pro Tier").
local function getBarricadeTemplate(tierName)
	local folder = ServerStorage:FindFirstChild("BarricadeModels")
	if not folder then
		warn("[BarricadeClusterService] ServerStorage.BarricadeModels nicht gefunden -- lege dort ein 'Barricade'-Modell an.")
		return nil
	end
	local tierFolder = folder:FindFirstChild(tierName)
	local barricadeTemplate = (tierFolder and tierFolder:FindFirstChild("Barricade")) or folder:FindFirstChild("Barricade")
	if not barricadeTemplate then
		warn("[BarricadeClusterService] Kein 'Barricade'-Modell in ServerStorage.BarricadeModels gefunden (auch nicht in ServerStorage.BarricadeModels." .. tierName .. ").")
	end
	return barricadeTemplate
end

-- [cityName][clusterId] = Cluster-Datenstruktur
local activeClusters = {}

-- [cityName] = true, sobald IRGENDEIN Cluster dieser Stadt jemals aktiviert wurde --
-- fürs CITY-BROKEN-Task-System (CityBrokenService.lua): unterscheidet "noch nie
-- aktiviert" (Aufgabe noch nicht relevant) von "aktiviert und inzwischen besiegt"
-- (Aufgabe wirklich erledigt). Ohne das würde die Aufgabe direkt nach Erreichen von
-- Level 3 fälschlich als "erledigt" gelten, weil noch keine Barrikade existiert (die
-- erscheinen ja erst gestaffelt, sobald ein Flankengebäude unter 50% HP fällt).
local everActivatedForCity = {}
_G.HasAnyBarricadeEverActivated = function(cityName)
	return everActivatedForCity[cityName] == true
end

-- [cityName][clusterId] = true, sobald dieser SPEZIFISCHE Cluster im aktuellen
-- Eskalationszyklus (laufende Level-3-Phase) besiegt wurde -- verhindert, dass er
-- innerhalb DERSELBEN Alert-Stufe erneut respawnt, nur weil das zugehörige
-- Flankengebäude weiterhin unter 50% HP liegt und erneut Schaden nimmt. Wird erst beim
-- Rückfall unter Level 3 zurückgesetzt (siehe Level-Wechsel-Listener weiter unten).
local destroyedThisCycle = {}

-- Fürs Eskalations-Gate in CityAlertService.lua: Level 2->3 (Defense) soll erst
-- weitersteigen, sobald KEINE aktiven Barrikaden-Cluster dieser Stadt mehr existieren.
_G.HasActiveBarricades = function(cityName)
	local clusters = activeClusters[cityName]
	if not clusters then
		return false
	end
	for _ in pairs(clusters) do
		return true
	end
	return false
end

-- Gründlichere Prüfung fürs CITY-BROKEN-Task-System: prüft nicht nur "keine AKTUELL
-- aktiven Cluster", sondern zählt ALLE möglichen Cluster-Ordner dieser Stadt (unter
-- Workspace.BarricadeSpawns.<Stadt>) und verifiziert, dass JEDER EINZELNE bereits in
-- diesem Eskalationszyklus besiegt wurde. Ohne das könnte die Aufgabe fälschlich als
-- "erledigt" gelten, wenn z.B. nur 1 von 3 möglichen Clustern ausgelöst wurde (weil nur
-- ein Flankengebäude bisher unter 50% HP fiel) und dieser eine besiegt ist -- die
-- anderen 2 wurden dann nie ausgelöst, geschweige denn besiegt.
_G.AreAllBarricadesDefeated = function(cityName)
	if _G.HasActiveBarricades(cityName) then
		return false -- mindestens einer läuft gerade noch
	end

	local barricadeSpawnsRoot = Workspace:FindFirstChild(BARRICADE_SPAWNS_ROOT)
	local tierFolder = barricadeSpawnsRoot and barricadeSpawnsRoot:FindFirstChild(cityName)
	if not tierFolder then
		return false -- keine Konfiguration gefunden -- im Zweifel NICHT als erledigt werten
	end

	local defeated = destroyedThisCycle[cityName] or {}
	local totalClusterCount = 0
	for _, clusterFolder in ipairs(tierFolder:GetChildren()) do
		if clusterFolder:IsA("Folder") or clusterFolder:IsA("Model") then
			totalClusterCount += 1
			if not defeated[clusterFolder.Name] then
				return false -- dieser spezifische Cluster wurde noch nie besiegt (evtl. nie ausgelöst)
			end
		end
	end

	-- Mindestens ein Cluster muss überhaupt existieren -- eine Stadt ganz ohne
	-- konfigurierte Barrikaden-Ordner soll nicht fälschlich als "alle besiegt" gelten.
	return totalClusterCount > 0
end

-- Fürs CITY-BROKEN-Task-Panel: "wie viele von wie vielen sind besiegt" -- gleiches
-- Grundprinzip wie AreAllBarricadesDefeated, gibt aber Zähler statt Bool zurück.
_G.GetBarricadeCounts = function(cityName)
	local barricadeSpawnsRoot = Workspace:FindFirstChild(BARRICADE_SPAWNS_ROOT)
	local tierFolder = barricadeSpawnsRoot and barricadeSpawnsRoot:FindFirstChild(cityName)
	if not tierFolder then
		return { destroyed = 0, total = 0 }
	end

	local defeated = destroyedThisCycle[cityName] or {}
	local total = 0
	local destroyedCount = 0
	for _, clusterFolder in ipairs(tierFolder:GetChildren()) do
		if clusterFolder:IsA("Folder") or clusterFolder:IsA("Model") then
			total += 1
			if defeated[clusterFolder.Name] then
				destroyedCount += 1
			end
		end
	end
	return { destroyed = destroyedCount, total = total }
end

local function createForceFieldVisual(targetModel, baseTransparency)
	local center, size = targetModel:GetBoundingBox()
	local groundY = center.Position.Y - size.Y / 2

	-- Radius so wählen, dass die Halbkugel das Gebäude komplett umschliesst -- sowohl in
	-- der Höhe (>= Gebäudehöhe) als auch horizontal (>= halbe Diagonale der Grundfläche).
	-- Plus 30% Puffer, damit sie sichtbar grösser als das Gebäude ist (bewusst gewünscht).
	local horizontalHalfDiagonal = math.sqrt((size.X / 2) ^ 2 + (size.Z / 2) ^ 2)
	local domeRadius = math.max(size.Y, horizontalHalfDiagonal) * 1.3

	local domeCenter = Vector3.new(center.Position.X, groundY, center.Position.Z)

	local shieldPart = Instance.new("Part")
	shieldPart.Name = "FlankShieldVisual"
	shieldPart.Shape = Enum.PartType.Ball
	shieldPart.Size = Vector3.new(domeRadius, domeRadius, domeRadius) * 2 -- Size ist der Durchmesser, nicht der Radius
	shieldPart.CFrame = CFrame.new(domeCenter)
	shieldPart.Anchored = true
	shieldPart.CanCollide = true -- physisches Hindernis, kann nicht durchdrungen werden
	-- Niedrige Reibung -- ohne das könnte man die gewölbte Halbkugel wie eine Rampe
	-- hochlaufen. Rutschig macht sie zu einer echten Barriere statt einer Kletterhilfe.
	shieldPart.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0.1, 1, 1)
	shieldPart.CanTouch = false
	shieldPart.CanQuery = false
	shieldPart.Material = Enum.Material.ForceField
	shieldPart.Color = Color3.fromRGB(90, 200, 255)
	shieldPart.Transparency = baseTransparency
	shieldPart.Parent = Workspace

	-- Spitze der Halbkugel (für den Beam-Anschluss) -- direkt über dem Kugel-Zentrum, im
	-- Abstand des Radius.
	local apex = domeCenter + Vector3.new(0, domeRadius, 0)

	return shieldPart, apex
end

local function pulseShieldVisual(shieldPart, baseTransparency, cycleSeconds)
	task.spawn(function()
		while shieldPart.Parent do
			local tweenUp = TweenService:Create(
				shieldPart,
				TweenInfo.new(cycleSeconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Transparency = baseTransparency + 0.2 }
			)
			tweenUp:Play()
			tweenUp.Completed:Wait()
			if not shieldPart.Parent then
				break
			end
			local tweenDown = TweenService:Create(
				shieldPart,
				TweenInfo.new(cycleSeconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Transparency = baseTransparency }
			)
			tweenDown:Play()
			tweenDown.Completed:Wait()
		end
	end)
end

local function createBeam(fromPart, toPosition)
	local attachment0 = Instance.new("Attachment")
	attachment0.Parent = fromPart
	-- WICHTIG: WorldCFrame NACH dem Parenting setzen, mit garantiert weltraum-aufrechter
	-- Rotation (keine Rotation relativ zur Welt) -- Axis/SecondaryAxis wären stattdessen
	-- relativ zur (evtl. nicht perfekt achsenausgerichteten) Barrikaden-Rotation gewesen,
	-- was den Bogen seitlich statt nach oben wölben liess.
	attachment0.WorldCFrame = CFrame.new(fromPart.Position)

	local targetAnchor = Instance.new("Part")
	targetAnchor.Name = "BeamTargetAnchor"
	targetAnchor.Anchored = true
	targetAnchor.CanCollide = false
	targetAnchor.CanTouch = false
	targetAnchor.CanQuery = false
	targetAnchor.Transparency = 1
	targetAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	targetAnchor.CFrame = CFrame.new(toPosition) -- bereits weltraum-aufrecht (keine Rotation)
	targetAnchor.Parent = Workspace

	local attachment1 = Instance.new("Attachment")
	attachment1.Parent = targetAnchor
	attachment1.WorldCFrame = CFrame.new(toPosition)

	-- Bogen-Höhe: proportional zum horizontalen Abstand, damit kurze und lange
	-- Verbindungen beide sinnvoll aussehen.
	local horizontalDistance = (Vector3.new(fromPart.Position.X, 0, fromPart.Position.Z) - Vector3.new(toPosition.X, 0, toPosition.Z)).Magnitude
	local curveHeight = math.max(8, horizontalDistance * 0.6)

	local beam = Instance.new("Beam")
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.CurveSize0 = curveHeight
	beam.CurveSize1 = curveHeight
	beam.Color = ColorSequence.new(Color3.fromRGB(90, 200, 255))
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.Transparency = NumberSequence.new(0.5)
	beam.LightEmission = 0.6
	beam.Segments = 30 -- glatter Bogen statt eckig
	beam.Parent = fromPart

	-- Puls-Animation für den Bogen selbst: Breite + Leuchtkraft schwellen periodisch an.
	task.spawn(function()
		while beam.Parent do
			local tweenUp = TweenService:Create(beam, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Width0 = 1.0,
				Width1 = 1.0,
				LightEmission = 1,
			})
			tweenUp:Play()
			tweenUp.Completed:Wait()
			if not beam.Parent then
				break
			end
			local tweenDown = TweenService:Create(beam, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Width0 = 0.6,
				Width1 = 0.6,
				LightEmission = 0.6,
			})
			tweenDown:Play()
			tweenDown.Completed:Wait()
		end
	end)

	-- Energie-Impuls: kleine, leuchtende Kugel, die regelmässig entlang des Bogens vom
	-- Barrikaden-Ende zur Schild-Spitze wandert -- simuliert den Bogen-Verlauf per
	-- quadratischer Bezier-Kurve (Kontrollpunkt = Bogen-Scheitel), da eine Kugel nicht
	-- einfach der Beam-eigenen Krümmung folgen kann.
	task.spawn(function()
		local pulseOrb = Instance.new("Part")
		pulseOrb.Name = "EnergyPulseOrb"
		pulseOrb.Shape = Enum.PartType.Ball
		pulseOrb.Size = Vector3.new(1, 1, 1)
		pulseOrb.Anchored = true
		pulseOrb.CanCollide = false
		pulseOrb.CanTouch = false
		pulseOrb.CanQuery = false
		pulseOrb.Material = Enum.Material.Neon
		pulseOrb.Color = Color3.fromRGB(150, 230, 255)
		pulseOrb.Transparency = 1 -- startet unsichtbar, erscheint erst beim ersten Impuls
		pulseOrb.Parent = Workspace

		local startPos = fromPart.Position
		-- Kontrollpunkt für die Bezier-Kurve: Mittelpunkt der Strecke, um curveHeight nach
		-- oben versetzt -- ergibt denselben "hoch und wieder runter"-Bogen wie der Beam.
		local midPoint = (startPos + toPosition) / 2 + Vector3.new(0, curveHeight, 0)

		while pulseOrb.Parent and beam.Parent do
			pulseOrb.Transparency = 0
			local duration = 1.2
			local startTime = os.clock()
			while os.clock() - startTime < duration and pulseOrb.Parent and beam.Parent do
				local t = (os.clock() - startTime) / duration
				-- Quadratische Bezier-Interpolation: P = (1-t)²·A + 2(1-t)t·M + t²·B
				local point = startPos * (1 - t) ^ 2 + midPoint * 2 * (1 - t) * t + toPosition * t ^ 2
				pulseOrb.CFrame = CFrame.new(point)
				task.wait()
			end
			if pulseOrb.Parent then
				pulseOrb.Transparency = 1
			end
			task.wait(0.6) -- kurze Pause zwischen zwei Impulsen
		end
		if pulseOrb.Parent then
			pulseOrb:Destroy() -- Beam wurde zerstört -- Kugel räumt sich selbst auf
		end
	end)

	return beam, targetAnchor, pulseOrb
end

-- Findet alle Flankengebäude, die per Attribut zu diesem Cluster gehören. Kein
-- separater Tag nötig -- durchsucht die bereits vorhandenen KaijuHouse-Gebäude nach dem
-- ShieldClusterId-Attribut.
local function findFlankBuildings(clusterId)
	local flanks = {}
	local houseTag = _G.HOUSE_TAG or "KaijuHouse"
	for _, instance in ipairs(CollectionService:GetTagged(houseTag)) do
		if instance:GetAttribute("ShieldClusterId") == clusterId then
			flanks[instance] = true
		end
	end
	return flanks
end

local function shatterVisual(part)
	if not part or not part.Parent then
		return
	end
	local tween = TweenService:Create(part, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
		Transparency = 1,
		Size = part.Size * 1.4,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

-- Entfernt NUR den Flankengebäude-Schutz (Halbkugeln + Beams verschwinden) -- die
-- Barrikade selbst bleibt bestehen und wird weiterhin angreifbar. Wird aufgerufen,
-- sobald BEIDE Generatoren zerstört sind.
local function dropFlankProtection(cluster)
	cluster.FlankProtectionActive = false

	for _, flankPart in pairs(cluster.Visuals.Flanks) do
		shatterVisual(flankPart)
	end
	for _, beamData in pairs(cluster.Visuals.Beams) do
		if beamData.beam then
			beamData.beam:Destroy()
		end
		if beamData.anchor then
			beamData.anchor:Destroy()
		end
		if beamData.pulseOrb then
			beamData.pulseOrb:Destroy()
		end
	end
	cluster.Visuals.Flanks = {}
	cluster.Visuals.Beams = {}
end

-- Lässt die Barrikade wie ein Haus einstürzen -- Teile lösen sich, kippen zufällig,
-- sinken zu Boden. Im Unterschied zu Häusern OHNE Ausblenden am Ende: die Teile bleiben
-- als Ruine sichtbar liegen, statt zu verschwinden (Barrikaden respawnen ja nicht wie
-- Häuser, es gibt also keinen "Neubau", auf den man das Verschwinden vorbereiten müsste).
-- Die komplette Ruine wird erst nach RUIN_LIFETIME Sekunden entfernt, damit sie nicht für
-- immer im Weg liegen bleibt.
local RUIN_COLLAPSE_DURATION = 1.4
local RUIN_LIFETIME = 45

local function collapseBarricadeToRuin(barricadeModel)
	local ok, boundsCFrame, boundsSize = pcall(function()
		return barricadeModel:GetBoundingBox()
	end)
	local groundY = ok and (boundsCFrame.Position.Y - boundsSize.Y / 2) or nil

	local parts = {}
	for _, part in ipairs(barricadeModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false -- Ruine soll nicht begehbar/blockierend im Weg stehen
			table.insert(parts, part)
		elseif part:IsA("Script") then
			part:Destroy() -- eingebettetes Verhalten (Schild-Logik etc.) soll an der Ruine nicht mehr laufen
		end
	end

	for _, part in ipairs(parts) do
		local startCFrame = part.CFrame
		local targetY = groundY or (startCFrame.Position.Y - 3)

		local tilt = CFrame.Angles(math.rad(math.random(-70, 70)), math.rad(math.random(-180, 180)), math.rad(math.random(-70, 70)))
		local horizontalOffset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
		local targetPosition = Vector3.new(startCFrame.Position.X, targetY, startCFrame.Position.Z) + horizontalOffset
		local targetCFrame = CFrame.new(targetPosition) * tilt

		local partDelay = math.random(0, 40) / 100
		task.delay(partDelay, function()
			if not part.Parent then
				return
			end
			local remainingDuration = math.max(RUIN_COLLAPSE_DURATION - partDelay, 0.1)
			local tween = TweenService:Create(
				part,
				TweenInfo.new(remainingDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = targetCFrame } -- KEIN Transparency=1 -- Teile bleiben als Ruine sichtbar
			)
			tween:Play()
		end)
	end

	-- Ruine nach einer Weile komplett entfernen, damit sie nicht dauerhaft im Weg liegt.
	task.delay(RUIN_LIFETIME, function()
		if barricadeModel.Parent then
			barricadeModel:Destroy()
		end
	end)
end

-- Gemeinsame Aufräum-Logik für BEIDE Wege, wie ein Cluster verschwindet (Kampf-Zerstörung
-- ODER sauberer Despawn bei Level-Rückgang) -- kümmert sich um Flanken-Visuals, Beams und
-- Spawn-Point, OHNE die Barrikade selbst anzufassen (das übernehmen die beiden
-- aufrufenden Funktionen unterschiedlich: Ruinen-Kollaps vs. Versinken).
local function cleanupClusterVisuals(cluster)
	cluster.ShieldActive = false

	for _, flankPart in pairs(cluster.Visuals.Flanks) do
		shatterVisual(flankPart)
	end
	for _, beamData in pairs(cluster.Visuals.Beams) do
		if beamData.beam then
			beamData.beam:Destroy()
		end
		if beamData.anchor then
			beamData.anchor:Destroy()
		end
		if beamData.pulseOrb then
			beamData.pulseOrb:Destroy() -- Absicherung -- der Selbst-Cleanup in createBeam greift zwar bereits über die beam.Parent-Prüfung, aber explizit ist robuster
		end
	end

	if cluster.SpawnPoint then
		if _G.ReleaseSpawnPoint then
			_G.ReleaseSpawnPoint(cluster.SpawnPoint)
		end
	end
end

-- Kampf-Zerstörung (Schild oder Generatoren auf 0): Barrikade stürzt ein und bleibt als
-- Ruine liegen.
local function destroyCluster(cluster)
	cleanupClusterVisuals(cluster)
	if cluster.Barricade then
		collapseBarricadeToRuin(cluster.Barricade) -- stürzt ein, statt sofort komplett zu verschwinden
	end
end

-- Sauberer Despawn (Alert-Level sinkt wieder auf 2, keine Kampf-Zerstörung): Barrikade
-- versinkt im Boden und verpufft, statt einzustürzen.
local function despawnClusterCleanly(cluster)
	cleanupClusterVisuals(cluster)
	if cluster.Barricade then
		task.spawn(function()
			sinkBarricadeAndVanish(cluster.Barricade)
		end)
	end
end

-- Setzt die Health/Active-Attribute EINES Generators -- löst dadurch automatisch die
-- Reaktion des im Barrikaden-Modell eingebetteten Scripts aus (das genau diese
-- Attribute abhört).
local function applyGeneratorHealth(generatorPart, health)
	if not generatorPart then
		return
	end
	generatorPart:SetAttribute("Health", math.max(0, health))
	generatorPart:SetAttribute("Active", health > 0)
end

-- ===== Billboard-Health-Bars für Schild + Generatoren -- gleiches Muster wie bei
-- normalen Häusern (HouseHandler.lua): bei vollem Leben ausgeblendet, blitzt bei Treffer
-- kurz auf (Zahl + Balken), blendet nach 2s automatisch wieder aus. =====
local barBillboardHideGeneration = {}

local function createBarBillboard(anchorPart, label)
	-- WICHTIG: GetBoundingBox() gibt es nur auf Model/PVInstance-Containern, NICHT auf
	-- einzelnen Parts (z.B. die Generatoren oder das Barrikaden-PrimaryPart sind oft
	-- einfache Parts) -- der Aufruf hat bisher mit einem Fehler abgebrochen, was die
	-- KOMPLETTE Cluster-Erstellung stoppte, inklusive der danach folgenden
	-- Flanken-Halbkugeln.
	local size
	if anchorPart:IsA("Model") then
		local _, modelSize = anchorPart:GetBoundingBox()
		size = modelSize
	elseif anchorPart:IsA("BasePart") then
		size = anchorPart.Size
	else
		size = Vector3.new(4, 4, 4)
	end
	local topOffsetY = size.Y / 2 + 3

	local billboard = Instance.new("BillboardGui")
	billboard.Name = label .. "HealthBar"
	billboard.Size = UDim2.new(0, 90, 0, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500
	billboard.Enabled = false
	billboard.Parent = anchorPart

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.new(1, 0, 0, 14)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.LuckiestGuy
	hpLabel.TextScaled = true
	hpLabel.TextColor3 = Color3.new(1, 1, 1)
	hpLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	hpLabel.TextStrokeTransparency = 0
	hpLabel.Text = label
	hpLabel.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 8)
	track.Position = UDim2.new(0, 0, 0, 16)
	track.BackgroundTransparency = 1
	track.Parent = billboard

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Thickness = 1.5
	trackStroke.Color = Color3.new(0, 0, 0)
	trackStroke.Transparency = 0.3
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90, 200, 255) -- bläulich, statt grün wie bei Häusern -- deutlich als "Schild", nicht als normales Gebäude erkennbar
	fill.BorderSizePixel = 0
	fill.Parent = track

	return billboard
end

local function updateBarBillboard(billboard, health, maxHealth, label)
	if not billboard then
		return
	end
	local fill = billboard:FindFirstChild("Fill", true)
	local hpLabel = billboard:FindFirstChild("HPLabel", true)
	if not fill then
		return
	end

	local ratio = math.clamp(health / math.max(maxHealth, 1), 0, 1)
	fill.Size = UDim2.new(ratio, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255 - math.floor(165 * ratio), 90 + math.floor(130 * ratio), 90 + math.floor(165 * ratio))

	if ratio >= 1 then
		billboard.Enabled = false
		return
	end

	billboard.Enabled = true
	if hpLabel then
		hpLabel.Text = label .. ": " .. math.floor(health)
	end

	barBillboardHideGeneration[billboard] = (barBillboardHideGeneration[billboard] or 0) + 1
	local myGeneration = barBillboardHideGeneration[billboard]
	task.delay(2, function()
		if barBillboardHideGeneration[billboard] == myGeneration and billboard.Parent then
			billboard.Enabled = false
		end
	end)
end

-- Lässt die Barrikade wie ein respawnendes Haus aus Einzelteilen zusammensetzen: jedes
-- Teil startet verstreut/gekippt und tweent zu seiner korrekten Zielposition -- gleiches
-- Grundprinzip wie growHouseFromGround() in HouseHandler.lua, nur mit generierten (statt
-- gespeicherten) Streu-Startpositionen, da die Barrikade frisch geklont wird und keine
-- vorherige "eingestürzte" Ausgangslage hat.
local ASSEMBLE_DURATION = 1.1

local function assembleBarricadeFromPieces(barricadeModel)
	local partsToRestore = {}
	local tweens = {}

	for _, part in ipairs(barricadeModel:GetDescendants()) do
		if part:IsA("BasePart") then
			local targetCFrame = part.CFrame
			local originalCanCollide = part.CanCollide
			table.insert(partsToRestore, { part = part, canCollide = originalCanCollide, targetCFrame = targetCFrame })

			-- Verstreute Startposition generieren: leicht abgesenkt, zufällig gekippt und
			-- horizontal versetzt -- sieht wie "aus dem Boden gefallene Einzelteile" aus.
			local tilt = CFrame.Angles(math.rad(math.random(-60, 60)), math.rad(math.random(-180, 180)), math.rad(math.random(-60, 60)))
			local horizontalOffset = Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
			local startPosition = targetCFrame.Position + horizontalOffset - Vector3.new(0, 3, 0)
			part.CFrame = CFrame.new(startPosition) * tilt
			part.CanCollide = false

			local tween = TweenService:Create(
				part,
				TweenInfo.new(ASSEMBLE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ CFrame = targetCFrame }
			)
			table.insert(tweens, tween)
		end
	end

	for _, tween in ipairs(tweens) do
		tween:Play()
	end
	task.wait(ASSEMBLE_DURATION)

	-- Exakte Ziel-CFrame + ursprüngliche Kollision wiederherstellen (nicht nur auf das
	-- Tween-Ergebnis verlassen, gleiches Prinzip wie bei growHouseFromGround()).
	for _, entry in ipairs(partsToRestore) do
		if entry.part.Parent then
			entry.part.CFrame = entry.targetCFrame
			entry.part.CanCollide = entry.canCollide
		end
	end
end

-- Lässt die Barrikade beim normalen Despawn (Level-Rückgang, NICHT Zerstörung im Kampf)
-- im Boden versinken und verpuffen -- anderer Effekt als der Ruinen-Kollaps bei
-- destroyCluster() weiter oben.
local SINK_DURATION = 0.9

local function sinkBarricadeAndVanish(barricadeModel)
	local tweens = {}
	for _, part in ipairs(barricadeModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			local tween = TweenService:Create(
				part,
				TweenInfo.new(SINK_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					CFrame = part.CFrame - Vector3.new(0, 6, 0),
					Transparency = 1,
				}
			)
			table.insert(tweens, tween)
		end
	end
	for _, tween in ipairs(tweens) do
		tween:Play()
	end
	task.wait(SINK_DURATION)
	if barricadeModel.Parent then
		barricadeModel:Destroy()
	end
end

local function spawnCluster(cityName, tierName, clusterId, barricadeSpawnPart, config)
	local barricadeTemplate = getBarricadeTemplate(tierName)
	if not barricadeTemplate then
		return nil
	end

	local scale = barricadeSpawnPart:GetAttribute("ScaleOverride") or config.BarricadeScale or 1

	local barricade = barricadeTemplate:Clone()
	barricade.Name = "Barricade_" .. clusterId
	barricade:PivotTo(barricadeSpawnPart.CFrame)
	local barricadeOk, barricadeScaleErr = pcall(function()
		barricade:ScaleTo(scale)
	end)
	if not barricadeOk then
		warn("[BarricadeClusterService] ScaleTo fehlgeschlagen für Barrikade '" .. clusterId .. "': " .. tostring(barricadeScaleErr))
	end
	barricade.Parent = Workspace
	task.spawn(function()
		assembleBarricadeFromPieces(barricade)
	end)
	CollectionService:AddTag(barricade, "Barricade")
	barricade:SetAttribute("ClusterId", clusterId)
	barricade:SetAttribute("CityName", cityName)
	barricade:SetAttribute("ShieldEnabled", true)
	barricade:SetAttribute("ElectricDamage", config.ElectricDamage or 40)

	local generatorsFolder = barricade:FindFirstChild("ShieldGenerators")
	local leftGenerator = generatorsFolder and generatorsFolder:FindFirstChild("LeftGenerator")
	local rightGenerator = generatorsFolder and generatorsFolder:FindFirstChild("RightGenerator")
	if not generatorsFolder or not leftGenerator or not rightGenerator then
		warn("[BarricadeClusterService] Barrikade '" .. clusterId .. "' hat keine vollständige ShieldGenerators-Struktur (LeftGenerator/RightGenerator) -- Generator-Schaden bleibt wirkungslos.")
	end

	local maxGeneratorHealth = config.GeneratorMaxHealth or 150
	applyGeneratorHealth(leftGenerator, maxGeneratorHealth)
	applyGeneratorHealth(rightGenerator, maxGeneratorHealth)

	local flanks = findFlankBuildings(clusterId)

	-- Billboard-Health-Bars: Schild am Barrikaden-PrimaryPart, je einer pro Generator.
	local barricadePrimaryPartForBars = barricade.PrimaryPart or barricade:FindFirstChildWhichIsA("BasePart", true)
	local shieldBillboard = barricadePrimaryPartForBars and createBarBillboard(barricadePrimaryPartForBars, "Schild")
	local leftGeneratorBillboard = leftGenerator and createBarBillboard(leftGenerator, "Generator L")
	local rightGeneratorBillboard = rightGenerator and createBarBillboard(rightGenerator, "Generator R")

	local cluster = {
		Id = clusterId,
		CityName = cityName,
		Tier = tierName,
		Barricade = barricade,
		LeftGenerator = leftGenerator,
		RightGenerator = rightGenerator,
		ShieldHealth = config.ShieldMaxHealth,
		MaxShieldHealth = config.ShieldMaxHealth,
		LeftGeneratorHealth = maxGeneratorHealth,
		RightGeneratorHealth = maxGeneratorHealth,
		MaxGeneratorHealth = maxGeneratorHealth,
		LastDamageTime = os.clock(),
		FlankBuildings = flanks,
		Visuals = { Flanks = {}, Beams = {} },
		ShieldActive = true,
		-- Getrennt von ShieldActive: FlankProtectionActive wird erst false, wenn BEIDE
		-- Generatoren zerstört sind -- ein einzelner zerstörter Generator lässt den
		-- Cluster/die Barrikade weiterbestehen, entfernt aber noch NICHT den
		-- Flankengebäude-Schutz.
		FlankProtectionActive = true,
		ShieldBillboard = shieldBillboard,
		LeftGeneratorBillboard = leftGeneratorBillboard,
		RightGeneratorBillboard = rightGeneratorBillboard,
	}

	-- Kraftfeld-Visuals NUR für die Flankengebäude -- die Barrikade selbst (Schild-
	-- Panels, Elektrozaun, Türme) übernimmt das eingebettete Script.
	local barricadePrimaryPart = barricade.PrimaryPart or barricade:FindFirstChildWhichIsA("BasePart", true)
	for flankModel in pairs(flanks) do
		local flankVisual, apex = createForceFieldVisual(flankModel, 0.65)
		pulseShieldVisual(flankVisual, 0.65, 2)
		cluster.Visuals.Flanks[flankModel] = flankVisual

		if barricadePrimaryPart then
			local beam, anchor, pulseOrb = createBeam(barricadePrimaryPart, apex)
			cluster.Visuals.Beams[flankModel] = { beam = beam, anchor = anchor, pulseOrb = pulseOrb }
		end
	end

	return cluster
end

-- ===== Einzelnen Cluster gezielt aktivieren (statt alle auf einmal bei Level 3) =====
-- Wird von HouseHandler.lua aufgerufen, sobald ein Flankengebäude unter 50% HP fällt.
_G.TryActivateBarricadeCluster = function(cityName, clusterId)
	print("[BarricadeClusterService] TryActivateBarricadeCluster aufgerufen: Stadt='" .. tostring(cityName) .. "', Cluster='" .. tostring(clusterId) .. "'")

	local cityAlertValues = ReplicatedStorage:FindFirstChild("CityAlertValues")
	local levelValue = cityAlertValues and cityAlertValues:FindFirstChild(cityName .. "Level")
	if not levelValue then
		warn("[BarricadeClusterService] Kein Level-Wert 'CityAlertValues." .. tostring(cityName) .. "Level' gefunden -- Aktivierung abgebrochen.")
		return
	end
	if levelValue.Value < 3 then
		print("[BarricadeClusterService] '" .. cityName .. "' ist noch nicht auf Level 3 (aktuell: " .. levelValue.Value .. ") -- Aktivierung abgebrochen.")
		return
	end

	activeClusters[cityName] = activeClusters[cityName] or {}
	if activeClusters[cityName][clusterId] then
		print("[BarricadeClusterService] Cluster '" .. clusterId .. "' ist bereits aktiv -- kein erneuter Spawn.")
		return
	end
	if destroyedThisCycle[cityName] and destroyedThisCycle[cityName][clusterId] then
		print("[BarricadeClusterService] Cluster '" .. clusterId .. "' wurde in diesem Eskalationszyklus bereits besiegt -- kein Respawn innerhalb derselben Alert-Stufe.")
		return
	end

	local config = CityAlertConfig.GetCityConfig(cityName)
	local tierName = cityName

	local barricadeSpawnsRoot = Workspace:FindFirstChild(BARRICADE_SPAWNS_ROOT)
	local tierFolder = barricadeSpawnsRoot and barricadeSpawnsRoot:FindFirstChild(tierName)
	local clusterFolder = tierFolder and tierFolder:FindFirstChild(clusterId)
	if not clusterFolder then
		warn("[BarricadeClusterService] Cluster-Ordner '" .. tostring(clusterId) .. "' nicht unter Workspace.BarricadeSpawns." .. tierName .. " gefunden.")
		return
	end

	local barricadeSpawnPart = clusterFolder:FindFirstChild("BarricadeSpawn")
	if not barricadeSpawnPart then
		warn("[BarricadeClusterService] Cluster-Ordner '" .. clusterId .. "' hat keinen 'BarricadeSpawn'-Part.")
		return
	end

	print("[BarricadeClusterService] Flankengebäude unter 50% HP -- aktiviere Cluster '" .. clusterId .. "' in '" .. cityName .. "'...")
	local cluster = spawnCluster(cityName, tierName, clusterId, barricadeSpawnPart, config)
	if cluster then
		activeClusters[cityName][clusterId] = cluster
		everActivatedForCity[cityName] = true
		playBarricadeAlarm(barricadeSpawnPart.Position)
		print("[BarricadeClusterService] Cluster '" .. clusterId .. "' aktiviert.")
	end
end

local function despawnAllClustersForCity(cityName)
	local clusters = activeClusters[cityName]
	if not clusters then
		return
	end
	for _, cluster in pairs(clusters) do
		despawnClusterCleanly(cluster)
	end
	activeClusters[cityName] = nil
end
_G.DespawnAllBarricadeClustersForCity = despawnAllClustersForCity

-- ===== Schild-Regeneration (nur der Schild-Pool -- Generatoren regenerieren NICHT, ein
-- zerstörter Generator bleibt permanent zerstört, passend zur Jaeger-Ziel-Fantasie) =====
task.spawn(function()
	while true do
		task.wait(1)
		for cityName, clusters in pairs(activeClusters) do
			local config = CityAlertConfig.GetCityConfig(cityName)
			for _, cluster in pairs(clusters) do
				if cluster.ShieldActive and cluster.ShieldHealth < cluster.MaxShieldHealth then
					if os.clock() - cluster.LastDamageTime >= (config.ShieldRegenDelay or 8) then
						local regenAmount = cluster.MaxShieldHealth * (config.ShieldRegenRate or 0.05)
						cluster.ShieldHealth = math.min(cluster.MaxShieldHealth, cluster.ShieldHealth + regenAmount)
					end
				end
			end
		end
	end
end)

-- ===== Öffentliche Damage-API für Kampf-Scripts =====
_G.DamageBarricadeShield = function(cityName, clusterId, amount, attackerPlayer)
	local clusters = activeClusters[cityName]
	local cluster = clusters and clusters[clusterId]
	if not cluster or not cluster.ShieldActive then
		return false
	end

	cluster.LastDamageTime = os.clock()
	cluster.ShieldHealth = math.max(0, cluster.ShieldHealth - amount)
	updateBarBillboard(cluster.ShieldBillboard, cluster.ShieldHealth, cluster.MaxShieldHealth, "Schild")

	if cluster.ShieldHealth <= 0 then
		destroyCluster(cluster)
		activeClusters[cityName][clusterId] = nil
		destroyedThisCycle[cityName] = destroyedThisCycle[cityName] or {}
		destroyedThisCycle[cityName][clusterId] = true

		-- Achievements: "Erste Barrikade durchbrochen".
		if attackerPlayer and _G.OnBarricadeDestroyedForAchievements then
			_G.OnBarricadeDestroyedForAchievements(attackerPlayer)
		end

		-- Eskalation SOFORT prüfen, sobald die letzte Barrikade dieser Stadt fällt.
		if _G.HasActiveBarricades and not _G.HasActiveBarricades(cityName) and _G.CheckCityAlertLevelThresholds then
			_G.CheckCityAlertLevelThresholds(cityName)
		end
		return true
	end
	return false
end

-- side muss "Left" oder "Right" sein.
_G.DamageGenerator = function(cityName, clusterId, side, amount)
	local clusters = activeClusters[cityName]
	local cluster = clusters and clusters[clusterId]
	if not cluster or not cluster.ShieldActive then
		return false
	end

	local generatorPart, healthKey, billboardKey, label
	if side == "Left" then
		generatorPart, healthKey, billboardKey, label = cluster.LeftGenerator, "LeftGeneratorHealth", "LeftGeneratorBillboard", "Generator L"
	elseif side == "Right" then
		generatorPart, healthKey, billboardKey, label = cluster.RightGenerator, "RightGeneratorHealth", "RightGeneratorBillboard", "Generator R"
	else
		return false
	end
	if not generatorPart then
		return false
	end

	cluster[healthKey] = math.max(0, cluster[healthKey] - amount)
	applyGeneratorHealth(generatorPart, cluster[healthKey])
	updateBarBillboard(cluster[billboardKey], cluster[healthKey], cluster.MaxGeneratorHealth, label)

	if cluster.LeftGeneratorHealth <= 0 and cluster.RightGeneratorHealth <= 0 then
		-- BEIDE Generatoren sind jetzt tot -- Flankengebäude verlieren den Schutz. Die
		-- Barrikade selbst bleibt bestehen und wird ab jetzt regulär angreifbar
		-- (das eingebettete Barrikaden-Script lässt die Schild-Panels ohnehin schon
		-- automatisch nicht-kollidierbar werden, sobald beide Generatoren inaktiv sind).
		if cluster.FlankProtectionActive then
			print("[BarricadeClusterService] Beide Generatoren von Cluster '" .. clusterId .. "' zerstört -- Flankenschutz fällt.")
			dropFlankProtection(cluster)
		end
	end
	return false
end

-- Für HUD/Debug: aktuellen Zustand eines Clusters abfragen.
-- Prüft, ob ein Gebäude GERADE durch ein aktives Schild geschützt ist (für
-- HouseHandler.lua -- blockiert dann jeglichen Schaden an diesem Gebäude).
_G.IsFlankBuildingProtected = function(house)
	local clusterId = house:GetAttribute("ShieldClusterId")
	if not clusterId then
		return false
	end
	local cityNamePart = house
	local cityName = nil
	while cityNamePart do
		cityName = cityNamePart:GetAttribute("CityName")
		if cityName then
			break
		end
		cityNamePart = cityNamePart.Parent
	end
	if not cityName then
		return false
	end
	local clusters = activeClusters[cityName]
	local cluster = clusters and clusters[clusterId]
	return cluster ~= nil and cluster.FlankProtectionActive == true
end

_G.GetBarricadeClusterState = function(cityName, clusterId)
	local clusters = activeClusters[cityName]
	local cluster = clusters and clusters[clusterId]
	if not cluster then
		return nil
	end
	return {
		ShieldHealth = cluster.ShieldHealth,
		MaxShieldHealth = cluster.MaxShieldHealth,
		LeftGeneratorHealth = cluster.LeftGeneratorHealth,
		RightGeneratorHealth = cluster.RightGeneratorHealth,
		MaxGeneratorHealth = cluster.MaxGeneratorHealth,
		ShieldActive = cluster.ShieldActive,
	}
end

_G.GetClusterIdForModel = function(model)
	local clusterId = model:GetAttribute("ClusterId")
	local cityName = model:GetAttribute("CityName")
	return clusterId, cityName
end

-- Für Kampf-Scripts: leitet "Left"/"Right" aus dem Namen des getroffenen Generator-Teils ab.
_G.GetGeneratorSide = function(generatorPart)
	if generatorPart.Name == "LeftGenerator" then
		return "Left"
	elseif generatorPart.Name == "RightGenerator" then
		return "Right"
	end
	return nil
end

-- Findet alle Generatoren (beider Seiten, über alle aktiven Cluster) in Reichweite einer
-- Position -- für Kampf-Scripts, da Generatoren keine eigenständig getaggten Models mehr
-- sind, sondern Teil der Barrikaden-Struktur (ShieldGenerators.LeftGenerator/RightGenerator).
-- Gibt eine Liste von { part=, side=, clusterId=, cityName= } zurück.
_G.GetGeneratorsInRange = function(position, range)
	local results = {}
	for cityName, clusters in pairs(activeClusters) do
		for clusterId, cluster in pairs(clusters) do
			if cluster.ShieldActive then
				for _, side in ipairs({ "Left", "Right" }) do
					local generatorPart = side == "Left" and cluster.LeftGenerator or cluster.RightGenerator
					if generatorPart and generatorPart.Parent then
						local ok, pivot = pcall(function()
							return generatorPart:GetPivot()
						end)
						if ok and (pivot.Position - position).Magnitude <= range then
							table.insert(results, { part = generatorPart, side = side, clusterId = clusterId, cityName = cityName })
						end
					end
				end
			end
		end
	end
	return results
end

-- ===== Level-Wechsel abonnieren: Cluster aktivieren sich EINZELN über
-- _G.TryActivateBarricadeCluster. Beim Rückfall unter Level 3 werden ALLE aktiven
-- Cluster despawnt. =====
if _G.CityAlertLevelChanged then
	_G.CityAlertLevelChanged.Event:Connect(function(cityName, newLevel, oldLevel)
		-- "< 3 und vorher >= 3" statt nur des exakten 3->2-Schritts -- deckt auch grössere
		-- Sprünge ab (z.B. der direkte Rücksprung von Level 5 auf 0 nach CITY BROKEN, siehe
		-- CityBrokenService.lua/_G.ResetCityAlert).
		if newLevel < 3 and oldLevel >= 3 then
			despawnAllClustersForCity(cityName)
			destroyedThisCycle[cityName] = nil
		end
		-- Markierung "jemals aktiviert" ebenfalls zurücksetzen, sobald die Stadt sich
		-- komplett beruhigt -- ein neuer Eskalationszyklus soll die CITY-BROKEN-Aufgabe
		-- wieder von vorne (nicht abgehakt) zeigen.
		if newLevel == 0 then
			everActivatedForCity[cityName] = nil
		end
	end)
end

print("[Kaiju] BarricadeClusterService bereit -- Stufe 3 (gestaffelte Aktivierung, 2 Generatoren pro Cluster).")