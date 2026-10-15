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

-- ===== Kampf-Abstand =====
-- Im Gefecht sollen die Fahrzeuge zusammenrücken -- diese beiden Zahlen sind am 25.08.2026
-- bewusst eingemessen worden (von 6/12 verdoppelt) und bleiben unangetastet.
local GROUND_VEHICLE_MIN_DISTANCE_DIFFERENT_TYPE = 12
local GROUND_VEHICLE_MIN_DISTANCE_SAME_TYPE = 24

-- ===== Spawn-Abstand =====
-- Beim Spawnen gilt ein GRÖSSERER Abstand als im Gefecht, und das ist Absicht: Amancio am
-- 14.10.2026 -- "Die Feuerwehr und Militär sollen weiter auseinander spawnen."
--
-- Warum zwei Zahlenpaare und nicht einfach die Kampfwerte erhöht: das sind zwei
-- verschiedene Augenblicke. Beim Auftauchen sollen die Fahrzeuge sich AUFFÄCHERN, damit man
-- sie als mehrere erkennt; im Gefecht dürfen sie zusammenrücken. Die Kampfwerte zu erhöhen
-- hätte den eingemessenen Gefechtsabstand mitverschoben, um ein Spawn-Problem zu lösen.
GroundVehicleSeparation.SPAWN_MIN_DISTANCE_SAME_TYPE = 36
GroundVehicleSeparation.SPAWN_MIN_DISTANCE_DIFFERENT_TYPE = 20

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

-- Der gemeinsame Kern. Die beiden Abstände kommen von aussen, damit Gefecht und Spawn
-- dieselbe Rechnung benutzen und nicht zwei Fassungen davon auseinanderlaufen.
local function drueckeAuseinander(instance, vehicleType, intendedPosition, gleicherTyp, andererTyp)
	local pushVector = Vector3.new(0, 0, 0)
	for otherInstance, data in pairs(groundVehicleRegistry) do
		if otherInstance ~= instance then
			local minDistance = (data.vehicleType == vehicleType) and gleicherTyp or andererTyp
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

-- Berechnet eine sanft nach aussen gedrückte Zielposition, falls sie zu nah an einem
-- ANDEREN registrierten Bodenfahrzeug liegt (horizontale Distanz, Höhe bleibt
-- unangetastet). Wird von jedem System VOR dem eigentlichen PivotTo aufgerufen.
function GroundVehicleSeparation.ApplySeparation(instance, vehicleType, intendedPosition)
	return drueckeAuseinander(instance, vehicleType, intendedPosition,
		GROUND_VEHICLE_MIN_DISTANCE_SAME_TYPE, GROUND_VEHICLE_MIN_DISTANCE_DIFFERENT_TYPE)
end

-- Dasselbe, aber mit den grösseren Spawn-Abständen.
--
-- ===== Warum das gefehlt hat =====
-- Beide Systeme riefen beim Spawnen nur RegisterPosition -- ApplySeparation lief
-- AUSSCHLIESSLICH während der Fahrt. Zwei Fahrzeuge konnten damit ineinander auftauchen und
-- schoben sich erst beim Losfahren auseinander. Ein Raketenwerfer fährt gar nicht und löste
-- sich deshalb NIE.
function GroundVehicleSeparation.ApplySpawnSeparation(instance, vehicleType, intendedPosition)
	return drueckeAuseinander(instance, vehicleType, intendedPosition,
		GroundVehicleSeparation.SPAWN_MIN_DISTANCE_SAME_TYPE,
		GroundVehicleSeparation.SPAWN_MIN_DISTANCE_DIFFERENT_TYPE)
end

return GroundVehicleSeparation