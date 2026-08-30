-- VERSION: 2026-08-25 #2
-- TUNING: Kampf-Abstand zwischen Fahrzeugen verdoppelt (6->12, 12->24)
-- Ort in Studio: ServerScriptService
--
-- Systemübergreifender Bodenfahrzeug-Mindestabstand: gilt für ALLE Bodenfahrzeuge
-- (Panzer, Raketenwerfer, Feuerwehrautos) über MilitaryService.lua UND
-- FireEngineController.lua hinweg -- NICHT für Helikopter (die fliegen). Fahrzeuge
-- desselben Typs brauchen mehr Abstand zueinander als Fahrzeuge unterschiedlichen Typs.
--
-- Vorher als _G-Funktionen direkt in MilitaryService.lua definiert, obwohl es
-- konzeptionell nicht nur zum Militär-System gehört (die Feuerwehr nutzte es über _G
-- ebenfalls mit) -- jetzt als eigenständiges Modul, von beiden Systemen per require()
-- genutzt.

local GroundVehicleSeparation = {}

local GROUND_VEHICLE_MIN_DISTANCE_DIFFERENT_TYPE = 12
local GROUND_VEHICLE_MIN_DISTANCE_SAME_TYPE = 24

-- [instance] = { position = Vector3, vehicleType = "Tank"/"RocketLauncher"/"FireEngine" }
local groundVehicleRegistry = {}

-- Meldet/aktualisiert die aktuelle Position eines Bodenfahrzeugs -- von JEDEM System bei
-- jedem Bewegungs-Update aufgerufen (auch für stationäre Fahrzeuge wie den
-- Raketenwerfer, einmalig beim Spawnen, damit andere ihn als Hindernis kennen).
function GroundVehicleSeparation.RegisterPosition(instance, vehicleType, position)
	groundVehicleRegistry[instance] = { position = position, vehicleType = vehicleType }
end

-- Entfernt ein Fahrzeug aus der Registry -- beim Despawnen/Zerstören aufrufen, sonst
-- würden andere Fahrzeuge ewig um eine "Geister"-Position herumweichen.
function GroundVehicleSeparation.Unregister(instance)
	groundVehicleRegistry[instance] = nil
end

-- Berechnet eine sanft nach aussen gedrückte Zielposition, falls sie zu nah an einem
-- ANDEREN registrierten Bodenfahrzeug liegt (horizontale Distanz, Höhe bleibt
-- unangetastet). Wird von jedem System VOR dem eigentlichen PivotTo aufgerufen.
function GroundVehicleSeparation.ApplySeparation(instance, vehicleType, intendedPosition)
	local pushVector = Vector3.new(0, 0, 0)
	for otherInstance, data in pairs(groundVehicleRegistry) do
		if otherInstance ~= instance then
			local minDistance = (data.vehicleType == vehicleType)
				and GROUND_VEHICLE_MIN_DISTANCE_SAME_TYPE
				or GROUND_VEHICLE_MIN_DISTANCE_DIFFERENT_TYPE
			local delta = intendedPosition - data.position
			local horizontalDelta = Vector3.new(delta.X, 0, delta.Z)
			local dist = horizontalDelta.Magnitude
			if dist > 0 and dist < minDistance then
				local pushStrength = minDistance - dist
				pushVector = pushVector + horizontalDelta.Unit * pushStrength
			end
		end
	end
	if pushVector.Magnitude > 0 then
		return intendedPosition + pushVector
	end
	return intendedPosition
end

return GroundVehicleSeparation