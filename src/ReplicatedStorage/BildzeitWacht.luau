-- ModuleScript: BildzeitWacht
-- Ort in Studio: ReplicatedStorage
--
-- Misst, wie lange ein Bild dauert -- auf dem Server und auf dem Client, aus DERSELBEN
-- Quelle. Zwei getrennte Fassungen waeren zwei Messungen mit verschiedenen Schwellen, und
-- dann liesse sich nicht mehr sagen, welche Seite ringt.
--
-- ===== Warum es das gibt =====
-- Zur Frage "was frisst die Performance" gab es bisher nur Vermutungen, und ich habe in
-- einer Sitzung zweimal die falsche Haelfte verdaechtigt: erst die Zielsuche (die WAR zu
-- teuer, 19.4 ms je Schlag), dann die Replikation (die war es nicht -- die Schlagverzoegerung
-- steckte in den Animationszeiten des Rigs).
--
-- Diese Wacht beantwortet die ERSTE Frage: welche Maschine hat ueberhaupt zu wenig Zeit,
-- und in welchen Augenblicken. Erst danach lohnt es, mit debug.profilebegin einzelne
-- Systeme zu beschriften -- alle 37 Bild-Schleifen des Projekts auf Verdacht zu labeln
-- waere viel Arbeit fuer wenig.
--
-- ===== Was im Output erscheint =====
-- Sofort bei einem einzelnen langen Bild -- diese Zeile steht im Log NEBEN der Ursache:
--   [Bildzeit Server] SPITZE: ein Bild dauerte 143 ms (Budget 16.7).
--
-- Und alle 10 Sekunden eine Zusammenfassung, aber NUR wenn etwas ueber dem Budget lag:
--   [Bildzeit Client] 10 s: 412 Bilder, Mittel 24.3 ms, schlechtestes 143 ms,
--   37 ueber 25 ms (9 %).
--
-- Laeuft alles glatt, bleibt sie still -- ausser der einen Zeile beim Start, damit sich
-- "nichts zu melden" von "lief gar nicht" unterscheiden laesst.

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local BildzeitWacht = {}

-- 60 Bilder je Sekunde sind 16.7 ms. Das ist das Ziel, nicht die Schwelle.
local BUDGET_MS = 16.7

-- Ab hier gilt ein Bild als zu lang. 25 ms sind 40 Bilder je Sekunde -- darunter beginnt
-- man es zu sehen. Knapp ueber dem Budget zu warnen waere Laerm: einzelne 18er hat jedes
-- Spiel.
local SCHWELLE_MS = 25

-- Ab hier ist es keine Schwankung mehr, sondern ein Aussetzer, und die Zeile soll SOFORT
-- kommen -- dann steht sie im Log direkt bei dem, was sie verursacht hat (etwa neben
-- "buildFallbackRuin"). Genau diese Nachbarschaft ist der Zweck.
local SPITZE_MS = 100

-- Hoechstens eine Spitzenmeldung je Sekunde. Ohne das ueberschwemmt ein einbrechender
-- Server das Log mit sich selbst und verdeckt die Zeilen, die die Ursache nennen.
local SPITZE_ABSTAND = 1

local BERICHT_ABSTAND = 10

-- Einmal je Bericht eine Momentaufnahme der Engine-Werte. Kein Welt-Scan und
-- keine zusaetzliche Arbeit pro Bild. Die Zeiten sind einzelne Engine-Messungen,
-- keine Mittelwerte unseres Zehn-Sekunden-Fensters; sie duerfen nicht addiert
-- oder von der Bildzeit abgezogen werden (CPU und GPU arbeiten ueberlappend).
local function engineMomentaufnahme(seite)
	local function wert(name, faktor, format)
		local ok, value = pcall(function() return Stats[name] end)
		if not ok or type(value) ~= "number" then
			return "n/v"
		end
		return string.format(format, value * faktor)
	end
	local zeiten
	if RunService:IsServer() then
		zeiten = "Scheduler " .. wert("HeartbeatTime", 1000, "%.1f ms")
	else
		zeiten = "Render-CPU " .. wert("RenderCPUFrameTime", 1000, "%.1f ms")
			.. ", GPU " .. wert("RenderGPUFrameTime", 1000, "%.1f ms")
			.. ", Drawcalls " .. wert("SceneDrawcallCount", 1, "%.0f")
	end
	print("[Bildzeit " .. seite .. "] Engine-Momentaufnahme: " .. zeiten
		.. ", Physik " .. wert("PhysicsStepTime", 1000, "%.1f ms")
		.. ", bewegte Physikteile " .. wert("MovingPrimitivesCount", 1, "%.0f")
		.. ", Instanzen " .. wert("InstanceCount", 1, "%.0f") .. ".")
end

function BildzeitWacht.Start()
	local seite = RunService:IsServer() and "Server" or "Client"

	-- Auf dem Client der Abstand zwischen Bildern, NICHT die reine Renderarbeit.
	-- Skripte, Physik und Wartezeiten koennen darin enthalten sein. Auf dem Server
	-- ist Heartbeat der Takt; seine Frequenz allein misst keine CPU-Auslastung.
	local signal = RunService:IsServer() and RunService.Heartbeat or RunService.RenderStepped

	local bilder, summe, schlechtestes, ueberSchwelle = 0, 0, 0, 0
	local fensterBeginn = os.clock()
	local letzteSpitze = 0

	signal:Connect(function(deltaTime)
		local ms = deltaTime * 1000
		bilder += 1
		summe += ms
		if ms > schlechtestes then
			schlechtestes = ms
		end
		if ms >= SCHWELLE_MS then
			ueberSchwelle += 1
		end

		local jetzt = os.clock()

		if ms >= SPITZE_MS and jetzt - letzteSpitze >= SPITZE_ABSTAND then
			letzteSpitze = jetzt
			warn(string.format("[Bildzeit %s] SPITZE: ein Bild dauerte %.0f ms (Budget %.1f).",
				seite, ms, BUDGET_MS))
		end

		if jetzt - fensterBeginn >= BERICHT_ABSTAND then
			if ueberSchwelle > 0 and bilder > 0 then
				print(string.format("[Bildzeit %s] %.0f s: %d Bilder, Mittel %.1f ms, "
					.. "schlechtestes %.0f ms, %d ueber %d ms (%d %%).",
					seite, jetzt - fensterBeginn, bilder, summe / bilder, schlechtestes,
					ueberSchwelle, SCHWELLE_MS, math.floor(ueberSchwelle / bilder * 100 + 0.5)))
				engineMomentaufnahme(seite)
			end
			bilder, summe, schlechtestes, ueberSchwelle = 0, 0, 0, 0
			fensterBeginn = jetzt
		end
	end)

	print(string.format("[Bildzeit %s] Wacht bereit -- meldet Bilder ab %d ms, Spitzen ab "
		.. "%d ms, Zusammenfassung alle %d s (nur wenn es etwas zu melden gibt).",
		seite, SCHWELLE_MS, SPITZE_MS, BERICHT_ABSTAND))
end

return BildzeitWacht
