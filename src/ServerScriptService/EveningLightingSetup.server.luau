-- Script (kein LocalScript!): EveningLightingSetup
-- Ort in Studio: ServerScriptService
-- Setzt eine dezent dunklere, warme "Abendsonne"-Beleuchtung (nicht Nacht) -- macht
-- leuchtende Effekte (Energie-Beam, Explosionen, Neon-Teile) sichtbarer.
--
-- WICHTIG: Rührt KEINE bereits bestehenden Lighting-Objekte an (z.B. ein schon
-- vorhandenes Bloom/ColorCorrection/DepthOfField/SunRays) -- erstellt/verändert nur
-- eigene, eindeutig benannte Objekte ("Evening..."). Falls du das Feature wieder
-- rückgängig machen willst: einfach die beiden "Evening..."-Objekte unter Lighting
-- löschen und dieses Script deaktivieren.

local Lighting = game:GetService("Lighting")

-- Tageszeit: 15 = später Nachmittag
Lighting.ClockTime = 15

-- Nur leicht reduziert (Roblox-Standard ist meist 2)
Lighting.Brightness = 1.8

-- Umgebungslicht nur dezent dunkler/wärmer getönt
Lighting.Ambient = Color3.fromRGB(90, 85, 95)
Lighting.OutdoorAmbient = Color3.fromRGB(110, 100, 110)
Lighting.ExposureCompensation = 0

-- Warmer Farbstich am Himmel/Horizont, passend zur Abendsonne
Lighting.ColorShift_Top = Color3.fromRGB(255, 170, 120)
Lighting.ColorShift_Bottom = Color3.fromRGB(130, 100, 120)

Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.2

-- Eigenes, eindeutig benanntes Atmosphere-Objekt -- NICHT irgendein bestehendes
local atmosphere = Lighting:FindFirstChild("EveningAtmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "EveningAtmosphere"
	atmosphere.Parent = Lighting
end
atmosphere.Density = 0.1
atmosphere.Offset = 0.1
atmosphere.Color = Color3.fromRGB(220, 170, 140)
atmosphere.Decay = Color3.fromRGB(150, 120, 130)
atmosphere.Glare = 0.15
atmosphere.Haze = 0.4

-- Eigenes, eindeutig benanntes ColorCorrection-Objekt -- NICHT ein evtl. schon
-- bestehendes (z.B. eins, das du selbst für den Grundlook des Spiels eingerichtet hast)
local colorCorrection = Lighting:FindFirstChild("EveningColorCorrection")
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "EveningColorCorrection"
	colorCorrection.Parent = Lighting
end
colorCorrection.Contrast = 0.08
colorCorrection.Saturation = 0.05
colorCorrection.TintColor = Color3.fromRGB(255, 245, 235)
