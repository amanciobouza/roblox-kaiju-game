-- ModuleScript: BuildStamp
-- Ort in Studio: ReplicatedStorage
--
-- ERZEUGT -- nicht von Hand bearbeiten. Neu erzeugen mit: python tools/build_stamp.py
--
-- Fingerabdruck ueber alle .luau-Dateien unter src/. Der Server gibt ihn beim Start aus
-- (siehe SpecCheckService). Weicht die Ausgabe in Studio von dem Wert ab, der hier steht,
-- laeuft Studio auf einem alten Stand und Rojo hat nicht synchronisiert.
--
-- Genau dieser Fall hat schon einmal zwei Runden Fehlersuche gekostet, weil eine Aenderung
-- scheinbar wirkungslos blieb -- sie war schlicht nicht im laufenden Spiel.

return {
	Hash = "ad6c48dc52",
	FileCount = 102,
}
