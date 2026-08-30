-- Script (kein LocalScript!): EscalationService
-- Ort in Studio: ServerScriptService
--
-- Fundament für das Eskalations-System aus "Alert-Stufe 3: Barrikaden-Schild-Cluster –
-- Studio Setup" (Abschnitte 8-10): ein genereller Chaos-Zähler pro Stadt, der WEITERLÄUFT
-- (nicht bei Stufenwechsel zurückgesetzt), und in konfigurierbaren Schritten ein
-- Eskalations-Event feuert. Ausserdem: Verwaltung der "ReactiveSpawnPoints" (dichtes
-- Raster an einfachen Marker-Parts pro Zone/Tier), aus denen der jeweils nächstgelegene,
-- freie Punkt zur letzten Schadensposition gewählt wird.
--
-- WICHTIG: Dieses Script selbst spawnt NICHTS -- es ist bewusst generisch gehalten und
-- wird von den jeweiligen Konsumenten (Barrikaden-System für Stufe 3, Feuerwehr-
-- Eskalation für Stufe 2, Militär für Stufe 4) über ein Event abonniert. Jeder Konsument
-- entscheidet selbst, WAS er beim Eskalations-Trigger tatsächlich spawnt.

local Workspace = game:GetService("Workspace")

local BARRICADE_SPAWNS_ROOT = "BarricadeSpawns"

-- ===== Chaos-Zähler pro Stadt =====
-- WICHTIG: Läuft NUR innerhalb eines aktiven Alert-Zeitraums (ab Stufe 2) und wird bei
-- Rückgang auf Stufe 1 zurückgesetzt (siehe resetEscalation weiter unten) -- passend zur
-- Entscheidung "Barrikaden despawnen bei Alert-Rückgang".
local escalationCounts = {} -- [cityName] = Zahl der seit Alert-Beginn zerstörten/beschädigten Gebäude
local lastDamagePosition = {} -- [cityName] = Vector3
local escalationSteps = {} -- [cityName][stepKey] = zuletzt ausgelöster Eskalations-Schritt (verhindert Mehrfachauslösung)

-- Event, auf das die jeweiligen Konsumenten (Barrikaden/Feuerwehr/Militär) hören.
-- Feuert mit: (cityName, stepKey, escalationCount, lastPosition)
-- stepKey unterscheidet die drei parallel laufenden Eskalations-Reihen (Stufe 2/3/4),
-- da sie unterschiedliche EscalationStepSize-Werte haben und unabhängig zählen sollen.
local EscalationTriggered = Instance.new("BindableEvent")
EscalationTriggered.Name = "EscalationTriggered"
EscalationTriggered.Parent = script
_G.EscalationTriggered = EscalationTriggered

-- Registriert Schaden/Zerstörung an einem Gebäude -- von HouseHandler.lua bei JEDEM
-- Treffer bzw. jeder Zerstörung aufgerufen (je nachdem, was der jeweilige Konsument als
-- Trigger nutzen will -- Stufe 2 zählt z.B. Beschädigungen, Stufe 3/4 Zerstörungen).
_G.RegisterEscalationEvent = function(cityName, position, stepKey)
	if not cityName or cityName == "None" then
		return
	end

	lastDamagePosition[cityName] = position

	escalationCounts[cityName] = escalationCounts[cityName] or {}
	escalationCounts[cityName][stepKey] = (escalationCounts[cityName][stepKey] or 0) + 1

	escalationSteps[cityName] = escalationSteps[cityName] or {}
	local currentCount = escalationCounts[cityName][stepKey]

	return currentCount -- Konsument entscheidet selbst, ob das ein Trigger-Vielfaches ist
end

-- Prüft, ob currentCount ein Vielfaches von stepSize ist UND noch nicht für dieses
-- Vielfache ausgelöst wurde (verhindert Doppelauslösung bei gleichzeitigen Treffern).
_G.CheckEscalationStep = function(cityName, stepKey, stepSize)
	if not cityName or stepSize <= 0 then
		return false
	end
	local count = escalationCounts[cityName] and escalationCounts[cityName][stepKey] or 0
	local stepNumber = math.floor(count / stepSize)
	if stepNumber < 1 then
		return false
	end

	escalationSteps[cityName] = escalationSteps[cityName] or {}
	local lastTriggeredStep = escalationSteps[cityName][stepKey] or 0
	if stepNumber > lastTriggeredStep then
		escalationSteps[cityName][stepKey] = stepNumber
		return true
	end
	return false
end

-- Setzt den Chaos-Zähler + zuletzt ausgelöste Schritte einer Stadt zurück -- wird beim
-- Rückgang auf Alert-Level 1 aufgerufen (siehe CityAlertService.lua).
_G.ResetEscalation = function(cityName)
	escalationCounts[cityName] = nil
	escalationSteps[cityName] = nil
	lastDamagePosition[cityName] = nil
end

_G.GetLastDamagePosition = function(cityName)
	return lastDamagePosition[cityName]
end

-- ===== ReactiveSpawnPoints-Verwaltung =====
-- Punkte werden als "belegt" markiert (occupiedBy = z.B. ein Cluster-Model), damit
-- verschiedene Eskalations-Konsumenten sich nicht denselben Punkt gleichzeitig
-- schnappen. Ein Punkt gilt als frei, sobald der Belegende ihn wieder freigibt
-- (z.B. Cluster despawnt) oder das Model zerstört wird.
local occupiedPoints = {} -- [pointPart] = true

_G.ReleaseSpawnPoint = function(pointPart)
	occupiedPoints[pointPart] = nil
end

-- Findet den nächstgelegenen, freien ReactiveSpawnPoint zu einer Position, innerhalb
-- eines Radius, für eine bestimmte Zone (Tier-Ordnername, z.B. "Tier3_Stadt").
-- Gibt den Part zurück (bereits als belegt markiert) oder nil, falls keiner in
-- Reichweite frei ist.
_G.FindNearestReactiveSpawnPoint = function(tierName, position, maxRadius)
	local barricadeSpawns = Workspace:FindFirstChild(BARRICADE_SPAWNS_ROOT)
	if not barricadeSpawns then
		return nil
	end
	local tierFolder = barricadeSpawns:FindFirstChild(tierName)
	if not tierFolder then
		return nil
	end
	local pointsFolder = tierFolder:FindFirstChild("ReactiveSpawnPoints")
	if not pointsFolder then
		return nil
	end

	local nearestPart = nil
	local nearestDistance = maxRadius

	for _, point in ipairs(pointsFolder:GetChildren()) do
		if point:IsA("BasePart") and not occupiedPoints[point] then
			local distance = (point.Position - position).Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestPart = point
			end
		end
	end

	if nearestPart then
		occupiedPoints[nearestPart] = true
	end
	return nearestPart
end

-- Hilfsfunktion für die Militär-/Barrikaden-Systeme: findet alle Gebäude (per Tag) in
-- einem Radius um eine Position -- für automatische Flanken-/Ziel-Erkennung.
local CollectionService = game:GetService("CollectionService")

_G.FindBuildingsInRadius = function(position, radius, tagName)
	local results = {}
	for _, instance in ipairs(CollectionService:GetTagged(tagName or "Building")) do
		local pivot = instance.GetPivot and instance:GetPivot()
		if pivot and (pivot.Position - position).Magnitude <= radius then
			table.insert(results, instance)
		end
	end
	return results
end

print("[Kaiju] EscalationService bereit -- Fundament für Stufe 2/3/4 Eskalation.")