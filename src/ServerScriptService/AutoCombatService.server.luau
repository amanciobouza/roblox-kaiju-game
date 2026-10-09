-- Script: AutoCombatService
-- Ort in Studio: ServerScriptService
--
-- Der Auto-Kampf: die Figur sucht sich selbst ein Ziel, laeuft hin, schlaegt es kaputt und
-- geht zum naechsten. Ein Tastendruck schaltet ihn an und wieder aus.
--
-- ===== Warum auf dem SERVER =====
-- Naheliegend waere ein Client-Skript -- die Angriffe liegen dort, und das Zielsuchen koennte
-- es auch. Dagegen stehen zwei Dinge:
--
--   1. Es gibt den Weg schon. Der Prolog laesst seine Figur seit Monaten geskriptet kaempfen,
--      und zwar ueber SimulatePrologueActionEvent: der Server sagt "Punch", der Client ruft
--      genau die Funktion, die auch ein echter Tastendruck ruft. Cooldowns, Energiekosten,
--      Combo-Schritt, Animationen und Trefferermittlung laufen damit unveraendert durch den
--      normalen Weg. Ein zweiter, eigener Angriffsweg waere die Art Doppelung, an der im
--      Bestand schon mehrfach eine Absicht verlorengegangen ist.
--   2. Die Haeuser und ihr Zustand gehoeren dem Server. Er weiss ohne Umweg, was noch steht.
--
-- Der Name SimulatePrologueActionEvent passt damit nicht mehr ganz -- er kommt aus dem
-- Prolog, taugt aber genau fuer das hier. Umbenannt wird er bewusst NICHT: er haengt an
-- einer .model.json und an zwei Skripten, und ein Umbenennen waere eine Aenderung an
-- Funktionierendem ohne Anlass.
--
-- ===== Der Ablauf =====
-- Ziel suchen -> hinlaufen -> einen Angriffsblock spielen -> steht es noch, naechster Block;
-- ist es gefallen, naechstes Ziel. Die vier Bloecke stehen in ANGRIFFSBLOECKE.
--
-- ===== Was er NICHT tut =====
-- Er nimmt dem Spieler die Steuerung nicht ab. Wer waehrend des Auto-Kampfs selbst laeuft
-- oder schlaegt, tut das weiterhin -- die Figur wird nur gezogen und gedreht. Das ist
-- Absicht: ein Modus, aus dem man nicht einfach wieder herauslenken kann, faengt sich beim
-- ersten Missverstaendnis selbst ein.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils", 30))
-- Nur fuer FindEquipped: der Sprung wird am Zustand des Rigs abgewartet, und den fuehrt das
-- Modell an der Figur (JumpPhase).
local StageModels = require(ReplicatedStorage:WaitForChild("StageModels", 30))

local AutoCombatToggleEvent = RemoteEventUtils.GetOrCreate("AutoCombatToggleEvent")
local SimulatePrologueActionEvent = RemoteEventUtils.GetOrCreate("SimulatePrologueActionEvent")

-- ===== Die Angriffsbloecke =====
-- Amancio am 05.10.2026: "entweder 4xPunch machen, 2xJump, 1xFocus Angriff oder
-- 1x AreaDamage".
--
-- Die Pausen sind NICHT frei gewaehlt, sondern von den echten Wartezeiten abgeleitet -- ein
-- zu frueher Druck wird vom Spiel stillschweigend verworfen, wie ein zu schneller
-- Doppelklick (dieselbe Ueberlegung wie bei der Prolog-Sequenz):
--
--   Punch  ATTACK_COOLDOWN 0.8 s  -> 0.85 laesst Luft
--   Jump   die Figur muss landen, bevor der naechste Sprung zaehlt; Spezialangriffe sind
--          waehrend des Sprungs ohnehin gesperrt (SpecialAttackClient, blockiert())
--   Focus  FOCUS_CHARGE_TIME 2 s + FOCUS_ATTACK_DURATION 2.5 s -> der Strahl laeuft 4.5 s
--   Area   KAIJU_AREA_CHARGE_TIME 2.8 s bis der Schaden faellt
--
-- Die vier Bloecke dauern dadurch aehnlich lang -- keiner fuehlt sich wie eine Pause an.
-- ===== Warum der vierte Schlag eine eigene Nachlaufzeit hat =====
-- Amancio am 05.10.2026: "Wichtig beim 4. Punch. Diese Animation durchspielen lassen. Damit
-- es das Gebaeude zerreisst."
--
-- Der vierte Schlag ist der Finisher: das Rig greift das Gebaeude, hebt es zwischen die
-- Haende und reisst es in der Luft auseinander. Gemessen liegen zwischen Klick und Schaden
-- rund 1.4 Sekunden (siehe die Schlag-Zeiten im Log), und das Zerreissen laeuft danach noch
-- weiter -- der Griff darf bis LIFT_SECONDS_MAX 2.5 Sekunden halten.
--
-- Mit der Pause von 0.85 Sekunden waere der naechste Block mitten hineingefallen und haette
-- den Griff abgebrochen: die Figur haette neu angesetzt, das Gebaeude waere zurueckgefallen.
-- Deshalb trennt sich die Pause ZWISCHEN den Schlaegen von der Pause NACH dem Block.
local ANGRIFFSBLOECKE = {
	{ name = "4x Schlag", aktion = "Punch", wiederholungen = 4, pause = 0.85, pauseDanach = 3.2 },
	{ name = "2x Sprung", aktion = "Jump", wiederholungen = 2, springen = true },
	{ name = "1x Fokus", aktion = "Focus", wiederholungen = 1, pause = 4.8 },
	{ name = "1x Flaeche", aktion = "Area", wiederholungen = 1, pause = 3.2 },
}

-- ===== Sprungwerte =====
-- Hoechstzeit je Sprung, bevor aufgegeben wird. Der Sprung wird NICHT nach Zeit, sondern am
-- gemeldeten Zustand des Rigs abgewartet (JumpPhase) -- eine feste Dauer waere beim
-- naechsten Modell falsch. Die Grenze ist nur das Netz, falls die Meldung ausbleibt.
local SPRUNG_ZEITGRENZE = 4
-- So lange gilt die Figur nach dem Druck als "noch nicht gesprungen": das Rig braucht einen
-- Moment, bis JumpPhase ueberhaupt von "Idle" weggeht. Ohne diese Sperre waere der Sprung
-- im ersten Takt sofort "gelandet".
local SPRUNG_ANLAUF = 0.35
local SPRUNG_TAKT = 0.1

-- Wie weit die Figur nach einem Ziel sucht. Grosszuegig: lieber zum naechsten Viertel
-- laufen, als mitten im Feld stehen zu bleiben und nichts zu tun.
local SUCHRADIUS = 600
-- Wie lange sie hoechstens zu einem Ziel laeuft, bevor sie es aufgibt und neu sucht. Ohne
-- das koennte sie sich an einem Haus festlaufen, das hinter Wasser oder einer Barrikade
-- liegt.
local ANLAUF_ZEITGRENZE = 20
local ANLAUF_TAKT = 0.25

-- [Spieler] = true, solange sein Auto-Kampf laeuft. Die Schleife liest das in jedem Schritt
-- und beendet sich selbst -- so braucht es kein Abbrechen von aussen.
local laeuft = {}

local function lebendigeFigur(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and rootPart and humanoid.Health > 0 then
		return character, humanoid, rootPart
	end
	return nil
end

-- Die Hoehe der Figur bestimmt, wie nah sie heran muss: die Schlagreichweite des Rigs
-- skaliert mit ihr (KaijuStageOneCombatAdapter, MELEE_REACH_FROM_HEIGHT -- gemessen rund die
-- halbe Figurenhoehe). Eine feste Studzahl war im Bestand schon mehrfach der Fehler, sobald
-- die Figur mitwuchs.
local function figurenHoehe(character)
	local ok, groesse = pcall(function()
		return character:GetExtentsSize()
	end)
	return (ok and groesse and groesse.Y) or 6
end

local function istZerstoert(haus)
	return haus:GetAttribute("Destroyed") == true
end

local function zielTeil(haus)
	if haus:IsA("Model") then
		return haus.PrimaryPart
	end
	return haus:IsA("BasePart") and haus or nil
end

-- Halbmesser des Hauses in der Waagerechten -- damit die Figur vor dem Haus stehen bleibt
-- und nicht in seine Mitte laeuft.
local function hausHalbmesser(haus)
	local ok, _, groesse = pcall(function()
		return haus:GetBoundingBox()
	end)
	if ok and groesse then
		return math.max(groesse.X, groesse.Z) * 0.5
	end
	return 0
end

local function sucheZiel(rootPart)
	local tag = _G.HOUSE_TAG or "KaijuHouse"
	local bestes, besterAbstand = nil, SUCHRADIUS
	for _, haus in ipairs(CollectionService:GetTagged(tag)) do
		if not istZerstoert(haus) then
			local teil = zielTeil(haus)
			if teil then
				local abstand = (teil.Position - rootPart.Position).Magnitude
				if abstand < besterAbstand then
					bestes, besterAbstand = haus, abstand
				end
			end
		end
	end
	return bestes, besterAbstand
end

-- Dreht die Figur waagerecht zum Ziel. Nur Gieren, kein Nicken -- dieselbe Lehre wie im
-- Prolog, wo ein nicht flach gerechnetes Blickziel die Figur auf die Seite legte.
local function dreheZu(character, rootPart, zielPosition)
	local richtung = (zielPosition - rootPart.Position) * Vector3.new(1, 0, 1)
	if richtung.Magnitude > 0.1 then
		character:PivotTo(CFrame.lookAt(rootPart.Position, rootPart.Position + richtung))
	end
end

-- Laeuft zum Ziel, bis es in Reichweite ist. Gibt true zurueck, wenn sie angekommen ist.
local function laufeHin(player, haus)
	local start = os.clock()
	while laeuft[player] and os.clock() - start < ANLAUF_ZEITGRENZE do
		if istZerstoert(haus) or not haus.Parent then
			return false
		end
		local character, humanoid, rootPart = lebendigeFigur(player)
		if not character then
			return false
		end
		local teil = zielTeil(haus)
		if not teil then
			return false
		end

		local reichweite = figurenHoehe(character) * 0.45 + hausHalbmesser(haus)
		local flach = (teil.Position - rootPart.Position) * Vector3.new(1, 0, 1)
		if flach.Magnitude <= reichweite then
			dreheZu(character, rootPart, teil.Position)
			return true
		end

		-- MoveTo und nicht PivotTo: die Figur soll LAUFEN, mit ihrem eigenen Tempo und ihrer
		-- eigenen Laufanimation. Ein Versetzen per PivotTo saehe aus wie Gleiten und wuerde
		-- ausserdem gegen die Spielereingabe arbeiten.
		humanoid:MoveTo(teil.Position)
		task.wait(ANLAUF_TAKT)
	end
	return false
end

-- Steht die Figur am Boden? Gefragt wird das RIG, nicht die Uhr: es fuehrt JumpPhase am
-- Modell und meldet dort "Idle", sobald sie steht. Traegt der Spieler kein Modell, bleibt
-- der Humanoid-Zustand.
local function stehtAmBoden(character)
	local modell = StageModels.FindEquipped(character)
	if modell then
		local phase = modell:GetAttribute("JumpPhase")
		-- Kein Wert heisst: das Rig fuehrt die Angabe (noch) nicht -- dann lieber als
		-- "steht" lesen, als bis zur Zeitgrenze zu warten.
		return phase == nil or phase == "Idle"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return true
	end
	local zustand = humanoid:GetState()
	return zustand ~= Enum.HumanoidStateType.Freefall
		and zustand ~= Enum.HumanoidStateType.Jumping
end

-- ===== Auf das Ziel springen, dann noch einmal =====
-- Amancio am 05.10.2026: "Beim Springen soll die Figur versuchen auf das Ziel zu springen
-- und dann nochmals zu springen."
--
-- Ein blosser Sprungbefehl springt dorthin, wohin die Figur gerade laeuft -- im Stand also
-- senkrecht nach oben und zurueck. Damit sie AUF dem Gebaeude landet, muss sie waehrend des
-- Flugs weiter darauf zugezogen werden; deshalb wird MoveTo in jedem Takt erneuert, nicht
-- nur einmal vor dem Absprung.
--
-- Die Landung ist dabei der eigentliche Angriff: das Rig meldet sie als "Land", und der
-- Adapter rechnet darauf den Sprungschaden (LANDING_FACTOR, doppelter Schaden) auf das, WAS
-- unter der Figur liegt. Landet sie auf dem Dach, trifft sie das Gebaeude.
local function springeAufZiel(player, haus, block)
	for sprung = 1, block.wiederholungen do
		if not laeuft[player] then
			return false
		end
		local character, humanoid, rootPart = lebendigeFigur(player)
		if not character then
			return false
		end
		local teil = zielTeil(haus)
		if not teil or istZerstoert(haus) then
			return true -- Ziel ist weg: der Block ist nicht gescheitert, er ist erledigt
		end

		dreheZu(character, rootPart, teil.Position)
		humanoid:MoveTo(teil.Position)
		SimulatePrologueActionEvent:FireClient(player, "Jump")

		local start = os.clock()
		while os.clock() - start < SPRUNG_ZEITGRENZE do
			if not laeuft[player] then
				return false
			end
			local figur, lauf = lebendigeFigur(player)
			if not figur or not lauf then
				return false
			end
			-- Waehrend des Flugs weiter ziehen -- das ist der Unterschied zwischen einem
			-- Sprung auf das Gebaeude und einem Sprung auf der Stelle. MoveTo verfaellt nach
			-- dem Erreichen des Punktes, deshalb in jedem Takt neu.
			local jetzigesTeil = zielTeil(haus)
			if jetzigesTeil then
				lauf:MoveTo(jetzigesTeil.Position)
			end
			if os.clock() - start >= SPRUNG_ANLAUF and stehtAmBoden(figur) then
				break
			end
			task.wait(SPRUNG_TAKT)
		end
		print(string.format("[Kaiju Debug] Auto-Kampf: Sprung %d von %d auf '%s' -- %.1fs.",
			sprung, block.wiederholungen, haus.Name, os.clock() - start))
	end
	return true
end

local function spieleBlock(player, block, haus)
	if block.springen then
		return springeAufZiel(player, haus, block)
	end

	for schritt = 1, block.wiederholungen do
		if not laeuft[player] or not lebendigeFigur(player) then
			return false
		end
		SimulatePrologueActionEvent:FireClient(player, block.aktion)
		if schritt < block.wiederholungen then
			task.wait(block.pause)
		else
			-- Nach dem letzten Schritt: beim Schlagblock ist das der Finisher, der ausspielen
			-- muss (siehe pauseDanach oben). Sonst genuegt die normale Pause -- der Angriff
			-- braucht seine Zeit, und der naechste Block soll nicht hineinfallen.
			task.wait(block.pauseDanach or block.pause)
		end
	end
	return true
end

local function autoKampf(player)
	print("[Kaiju Debug] Auto-Kampf an fuer " .. player.Name .. ".")

	while laeuft[player] do
		local character, _, rootPart = lebendigeFigur(player)
		if not character then
			task.wait(1) -- gestorben oder noch kein Charakter: warten, nicht abbrechen
		else
			local haus, abstand = sucheZiel(rootPart)
			if not haus then
				print(string.format(
					"[Kaiju Debug] Auto-Kampf: kein Ziel innerhalb von %d Studs -- warte.",
					SUCHRADIUS))
				task.wait(2)
			else
				print(string.format("[Kaiju Debug] Auto-Kampf: Ziel '%s' in %.0f Studs.",
					haus.Name, abstand))
				if laufeHin(player, haus) then
					-- Angreifen, bis es faellt. Jeder Durchgang waehlt neu -- so entsteht die
					-- Abwechslung, die Amancio mit "eines dieser Angriffselemente anwenden und
					-- wiederholen" gemeint hat.
					while laeuft[player] and not istZerstoert(haus) and haus.Parent do
						local figur, _, wurzel = lebendigeFigur(player)
						if not figur then
							break
						end
						local teil = zielTeil(haus)
						if not teil then
							break
						end
						-- Vor jedem Block neu ausrichten: das Haus steht still, die Figur nicht
						-- (Sprung, Rueckstoss, Spielereingabe).
						dreheZu(figur, wurzel, teil.Position)

						local block = ANGRIFFSBLOECKE[math.random(#ANGRIFFSBLOECKE)]
						print(string.format("[Kaiju Debug] Auto-Kampf: %s gegen '%s' (%s HP).",
							block.name, haus.Name, tostring(haus:GetAttribute("Health"))))
						if not spieleBlock(player, block, haus) then
							break
						end

						-- Zu weit abgekommen? Dann wieder heranlaufen, statt ins Leere zu
						-- schlagen. Der Flaechenangriff und der Sprung versetzen die Figur.
						local reichweite = figurenHoehe(figur) * 0.45 + hausHalbmesser(haus)
						local flach = (teil.Position - wurzel.Position) * Vector3.new(1, 0, 1)
						if flach.Magnitude > reichweite * 1.5 then
							if not laufeHin(player, haus) then
								break
							end
						end
					end
					if istZerstoert(haus) then
						print("[Kaiju Debug] Auto-Kampf: '" .. haus.Name .. "' gefallen.")
					end
				end
			end
		end
	end

	print("[Kaiju Debug] Auto-Kampf aus fuer " .. player.Name .. ".")
end

AutoCombatToggleEvent.OnServerEvent:Connect(function(player)
	if laeuft[player] then
		laeuft[player] = nil
		player:SetAttribute("AutoCombatActive", false)
		return
	end

	-- Nicht im Prolog: der fuehrt dort seine eigene geskriptete Sequenz ueber denselben Weg,
	-- und zwei Treiber auf einem Ereignis wuerden sich die Aktionen gegenseitig verwerfen.
	if player:GetAttribute("IsInPrologue") == true then
		print("[Kaiju Debug] Auto-Kampf abgelehnt -- waehrend des Prologs kaempft die Figur "
			.. "ohnehin geskriptet.")
		return
	end

	laeuft[player] = true
	player:SetAttribute("AutoCombatActive", true)
	task.spawn(function()
		autoKampf(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	laeuft[player] = nil
end)

print("[Kaiju] AutoCombatService bereit -- Taste schaltet den Auto-Kampf um "
	.. "(vier Angriffsbloecke, Ziel nach Naehe).")
