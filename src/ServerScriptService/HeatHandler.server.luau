-- VERSION: 2026-08-26 #2
-- FEATURE: Meltdown während Prolog gesperrt (max. Berserker-Modus)
-- Ort in Studio: ServerScriptService
-- Ersetzt das alte, kill-streak-basierte BerserkerHandler.lua komplett. Zentrales
-- "Überhitzung ist Rage"-System: jeder Angriff erzeugt Hitze, hohe Hitze gibt Schadens-/
-- Geschwindigkeitsboni, bei 85% kann der Spieler bewusst "Berserk" aktivieren (deutlich
-- stärkerer Bonus, aber Hitze steigt weiter), bei 100% "Meltdown" (automatische
-- Explosionen, die dem Spieler selbst schaden). Einzige Möglichkeit zum Abkühlen:
-- Energie absorbieren (siehe EnergyCollectionHandler.lua).
--
-- Andere Scripts fragen den aktuellen Zustand über die _G-Funktionen unten ab. Die
-- Funktionsnamen (GetBerserkerDamageMultiplier / GetBerserkerCooldownMultiplier) wurden
-- bewusst vom alten System übernommen, damit CombatHandler.lua/HouseHandler.lua/
-- SpecialAttackHandler.lua nicht angepasst werden mussten -- dieselbe Schnittstelle, neue
-- Berechnung dahinter.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

-- ===== RemoteEvents =====
local ActivateBerserkEvent = Instance.new("RemoteEvent")
ActivateBerserkEvent.Name = "ActivateBerserkEvent"
ActivateBerserkEvent.Parent = ReplicatedStorage

local MeltdownExplosionEvent = Instance.new("RemoteEvent")
MeltdownExplosionEvent.Name = "MeltdownExplosionEvent"
MeltdownExplosionEvent.Parent = ReplicatedStorage

-- ===== Einstellungen: Hitze-Erzeugung pro Aktion =====
local PUNCH_HEAT_BY_COMBO_STEP = { [1] = 2, [2] = 3, [3] = 10 }
local JUMP_HEAT = 15
local FOCUS_HEAT = 25
local AREA_HEAT = 35

-- ===== Einstellungen: Abkühlung durchs Energie-Absorbieren =====
-- Heat sinkt proportional zur absorbierten Energiemenge -- größere/wertvollere
-- Feuerquellen kühlen dadurch automatisch schneller (sie geben ja auch mehr Energie pro
-- Tick), ohne dass wir jeden Gebäudetyp einzeln bepunkten müssen.
local HEAT_COOL_PER_ABSORPTION_TICK = 1 -- fester, kleiner Betrag pro Tick -- unabhängig davon, wie viel Energie dabei gewonnen wurde

-- ===== Einstellungen: 5 Hitzestufen (0-100%) =====
-- Bonus bei 85-100% gilt NUR, wenn Berserk manuell aktiviert wurde -- ohne Aktivierung
-- bleibt der Bonus in diesem Bereich beim "Enraged"-Wert stehen (siehe getHeatMultipliers).
local STAGE_CALM_MAX = 30
local STAGE_AGGRESSIVE_MAX = 60
local STAGE_ENRAGED_MAX = 85
local BERSERK_AVAILABLE_AT = 85

-- Talent "Overheat Specialist" (Kaiju-Talentbaum, Trade-off): erhöht diese Schwelle --
-- man kommt seltener in Berserk, dafür ist der Bonus stärker (siehe
-- GetTalentBerserkerDamageBonus weiter unten).
local function getEffectiveBerserkThreshold(player)
	local penalty = (_G.GetTalentBerserkerThresholdPenalty and _G.GetTalentBerserkerThresholdPenalty(player)) or 0
	return math.min(BERSERK_AVAILABLE_AT * (1 + penalty), 99) -- nie ganz auf 100, sonst wäre Berserk unerreichbar
end

-- Talent "Overheat Specialist" (Kaiju-Talentbaum): erweitert die Meltdown-Schwelle
-- Richtung 105% (bzw. weiter, je nach Fraktion/Ausbau) -- gedeckelt auf 109, nie ganz auf
-- die absolute Obergrenze 110, sonst gäbe es keinen Puffer mehr darüber.
local function getEffectiveMeltdownThreshold(player)
	local bonus = (_G.GetTalentMeltdownThresholdBonus and _G.GetTalentMeltdownThresholdBonus(player)) or 0
	return math.min(100 + bonus, 109)
end

local DAMAGE_MULT_CALM = 1.0
local DAMAGE_MULT_AGGRESSIVE = 1.1
local DAMAGE_MULT_ENRAGED = 1.3
local DAMAGE_MULT_BERSERK = 1.6 -- nur wenn aktiv per Button ausgelöst
local SPEED_MULT_ENRAGED = 1.1
local SPEED_MULT_BERSERK = 1.2

-- ===== Sprint: hält der Spieler die Sprint-Taste (siehe SprintClient.lua), läuft er
-- schneller -- unabhängig von Heat-Stufe/Berserk (multipliziert sich einfach mit deren
-- Effekt). Gedacht als Bewegungs-Komfortfunktion (z.B. schneller zum Portal im
-- Sanctuary), keine Kampf-Mechanik -- daher kein Stamina-/Cooldown-System, einfach
-- an/aus per gehaltener Taste.
local SPRINT_SPEED_MULTIPLIER = 1.6
local SetSprintingEvent = RemoteEventUtils.GetOrCreate("SetSprintingEvent")
SetSprintingEvent.OnServerEvent:Connect(function(player, isSprinting)
	player:SetAttribute("IsSprinting", isSprinting == true)
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("IsSprinting", nil)
end)

-- ===== Einstellungen: kontrollierter Berserk-Modus =====
local BERSERK_HEAT_DECAY_PER_SECOND = 3 -- sinkt von selbst, langsam
local LEG_TRAINING_HEAT_DECAY_PER_SECOND = 8 -- Bein-Training: deutlich schneller, unabhängig von der Stufe (siehe Heartbeat-Loop weiter unten)
local BERSERK_HEAT_PER_HIT = 4 -- jeder Treffer während Berserk lädt etwas nach
local BERSERK_MIN_HEAT_TO_STAY = 40 -- fällt Heat darunter, endet Berserk automatisch
local BERSERK_INACTIVITY_TIMEOUT = 4 -- Sekunden ohne Treffer -> Berserk endet

-- ===== Einstellungen: Meltdown (100% Heat) =====
local MELTDOWN_EXPLOSION_INTERVAL = 8 -- Sekunden zwischen automatischen Explosionen (nach der ersten, sofortigen)
local MELTDOWN_SELF_DAMAGE = 8 -- HP-Verlust pro Explosion
local MELTDOWN_HEAT_DECAY_PER_SECOND = 0.2 -- sinkt während Meltdown nur sehr langsam von selbst
local MELTDOWN_LOCK_DURATION = 10 -- Sekunden Mindestdauer in Meltdown, bevor überhaupt abgekühlt werden kann

local lastBerserkHitAt = {} -- [player] = os.clock()
local lastMeltdownExplosionAt = {} -- [player] = Workspace:GetServerTimeNow()
local wasInMeltdown = {} -- [player] = true/false, um den ÜBERGANG in Meltdown zu erkennen (sofortige erste Explosion)
local meltdownLockedUntil = {} -- [player] = os.clock(), bis wann Heat mindestens bei 100% gehalten wird

local function getHeat(player)
	return player:GetAttribute("Heat") or 0
end

local function setHeat(player, value)
	-- Obergrenze auf 110 angehoben (war 100) -- Meltdown triggert weiterhin bei genau 100,
	-- Heat kann aber jetzt darüber hinaus bis 110 weitersteigen (zeigt "wie tief" im
	-- Meltdown, statt bei 100 hart abzuschneiden).
	value = math.clamp(value, 0, 110)

	-- Während des Prologs: Heat darf maximal bis knapp UNTER die Meltdown-Schwelle
	-- steigen -- Berserker-Modus ist gewünscht/erlaubt, Meltdown (Verlangsamung,
	-- Explosionen) würde die geskriptete Kampfsequenz/Kamerafahrt stören.
	if player:GetAttribute("IsInPrologue") then
		value = math.min(value, getEffectiveMeltdownThreshold(player) - 1)
	end

	-- Meltdown-Mindestdauer: solange die Sperre aktiv ist, kann Heat NICHT unter 100%
	-- fallen -- weder durch Energie-Absorption noch durch den passiven Abbau. Ohne das
	-- konnte man Meltdown durch Absorbieren innerhalb einer Sekunde wieder verlassen,
	-- wodurch der Effekt (Verlangsamung, Explosionen) kaum spürbar war.
	local lockedUntil = meltdownLockedUntil[player]
	if lockedUntil and os.clock() < lockedUntil then
		-- Nur nach UNTEN klemmen (verhindert frühzeitiges Verlassen von Meltdown durch
		-- Absorbieren/Abbau) -- NICHT nach oben, sonst würde weiteres Kämpfen während der
		-- Sperre wirkungslos wirken, obwohl der Spieler sichtbar weiter Heat erzeugt.
		local threshold = getEffectiveMeltdownThreshold(player)
		if value < threshold then
			value = threshold
		end
	end
	player:SetAttribute("Heat", value)
end

-- Für andere Scripts: aktueller Hitze-Wert + Stufe (fürs HUD)
local function getHeatStage(player)
	local heat = getHeat(player)
	if heat >= getEffectiveMeltdownThreshold(player) then
		return "Meltdown"
	elseif heat >= getEffectiveBerserkThreshold(player) then
		return player:GetAttribute("BerserkActive") and "Berserk" or "Enraged"
	elseif heat >= STAGE_AGGRESSIVE_MAX then
		return "Enraged"
	elseif heat >= STAGE_CALM_MAX then
		return "Aggressive"
	else
		return "Calm"
	end
end
_G.GetHeatStage = getHeatStage

local function addHeat(player, amount)
	if amount <= 0 then
		return
	end
	-- Strahlungs-Mutation "Steady Core"/"Overheat Bruiser" (falls diese Runde ausgelöst):
	-- verändert dauerhaft, wie schnell Heat für den Rest der Session steigt.
	local mutationMultiplier = player:GetAttribute("MutationHeatGainMultiplier") or 1.0
	setHeat(player, getHeat(player) + amount * mutationMultiplier)

	-- Berserk aktiviert sich jetzt automatisch, sobald die Schwelle erreicht ist -- kein
	-- manueller Button-Klick mehr nötig (war bei laufendem Kampf mit Zerstören, Klicken
	-- und Spezialangriffen ohnehin schon zu viel gleichzeitig zu jonglieren).
	if not player:GetAttribute("BerserkActive") and getHeat(player) >= getEffectiveBerserkThreshold(player) then
		player:SetAttribute("BerserkActive", true)
		lastBerserkHitAt[player] = os.clock()
	end
end
_G.AddHeat = addHeat

-- Von EnergyCollectionHandler.lua bei jedem Absorptions-Tick aufgerufen.
_G.CoolHeatFromAbsorption = function(player, energyGained)
	if not energyGained or energyGained <= 0 then
		return
	end
	-- Fester, kleiner Betrag pro Tick -- unabhängig davon, ob dabei 1 oder 100 Energie
	-- gewonnen wurde. Vorher skalierte die Abkühlung proportional zur Energie-Menge,
	-- wodurch mehrere gleichzeitige Quellen (oder einfach hohe Beträge) die Heat-Leiste
	-- viel zu schnell komplett geleert haben.
	setHeat(player, getHeat(player) - HEAT_COOL_PER_ABSORPTION_TICK)
end

-- Von CombatHandler.lua nach jedem Schlag aufgerufen (mit dem Combo-Schritt 1/2/3).
_G.AddPunchHeat = function(player, comboStep)
	addHeat(player, PUNCH_HEAT_BY_COMBO_STEP[tonumber(comboStep)] or PUNCH_HEAT_BY_COMBO_STEP[1])
	if player:GetAttribute("BerserkActive") then
		lastBerserkHitAt[player] = os.clock()
		addHeat(player, BERSERK_HEAT_PER_HIT)
	end
end

-- Von HouseHandler.lua bei echtem Sprungschaden aufgerufen.
_G.AddJumpHeat = function(player)
	addHeat(player, JUMP_HEAT)
	if player:GetAttribute("BerserkActive") then
		lastBerserkHitAt[player] = os.clock()
		addHeat(player, BERSERK_HEAT_PER_HIT)
	end
end

-- Von SpecialAttackHandler.lua bei Fokus-/Flächenangriff aufgerufen.
_G.AddFocusHeat = function(player)
	addHeat(player, FOCUS_HEAT)
	if player:GetAttribute("BerserkActive") then
		lastBerserkHitAt[player] = os.clock()
		addHeat(player, BERSERK_HEAT_PER_HIT)
	end
end
_G.AddAreaHeat = function(player)
	addHeat(player, AREA_HEAT)
	if player:GetAttribute("BerserkActive") then
		lastBerserkHitAt[player] = os.clock()
		addHeat(player, BERSERK_HEAT_PER_HIT)
	end
end

-- ===== Gebäude-spezifische Heat-Effekte =====
-- Von HouseHandler.lua beim Einsturz eines Hauses aufgerufen, falls das Model ein
-- "HeatEffect"-Attribut (String) gesetzt hat -- so lassen sich beliebige, besondere
-- Gebäude (Kirche, Wasserturm, Spital, ...) mit einem eigenen Heat-Verhalten versehen,
-- ohne dass dieses Script konkrete Gebäudenamen kennen muss. Setup in Studio: am
-- jeweiligen Haus-Model ein Attribut "HeatEffect" mit einem der unten stehenden Werte.
local HOSPITAL_STABILITY_DURATION = 20 -- Sekunden verlangsamter Heat-Abbau nach Spital-Einsturz
local HOSPITAL_DECAY_SLOWDOWN = 0.5 -- Heat sinkt während der Stabilität nur halb so schnell (betrifft Berserk-/Meltdown-Abbau)

local hospitalStabilityUntil = {} -- [player] = os.clock()

_G.ApplyBuildingHeatEffect = function(player, effectName)
	if not effectName then
		return
	end

	if effectName == "Church" then
		-- Kirche: leichte Erwärmung, aber eine "friedliche Aura" -- symbolisch als
		-- moderater, kontrollierbarer Anstieg statt einer harten Strafe umgesetzt.
		addHeat(player, 15)
	elseif effectName == "WaterTower" then
		-- Wasserturm: sofortige, starke Abkühlung -- kaltes Wasser verdampft.
		setHeat(player, getHeat(player) - 40)
	elseif effectName == "Hospital" then
		-- Spital: Heat sinkt für eine Weile langsamer (mehr Kontrolle über die
		-- eigene Hitze-Kurve, nicht sofort spürbar, dafür anhaltend nützlich).
		hospitalStabilityUntil[player] = os.clock() + HOSPITAL_STABILITY_DURATION
	elseif effectName == "GasStation" then
		-- Tankstelle: Explosion -- deutlicher Hitze-Schub.
		addHeat(player, 25)
	elseif effectName == "Skyscraper" then
		-- Hochhaus: Staubwolke, viel Masse -- der stärkste reguläre Heat-Schub.
		addHeat(player, 40)
	elseif effectName == "Landmark" then
		-- Landmarke: sofortiger, großer Sprung Richtung Berserk-Schwelle.
		addHeat(player, 50)
	end
end

-- Für getEffectiveCooldown/GetHeatSpeedMultiplier o.ä. NICHT relevant -- wird nur von der
-- Heartbeat-Schleife unten gelesen, um den verlangsamten Heat-Abbau während der
-- Spital-Stabilität anzuwenden.
local function getHospitalDecayMultiplier(player)
	local until_ = hospitalStabilityUntil[player]
	if until_ and os.clock() < until_ then
		return HOSPITAL_DECAY_SLOWDOWN
	end
	return 1.0
end

-- ===== Meltdown-Rot-Leuchten (Option A: teilweise Entsättigung + kräftiges Rot) =====
-- Server setzt das sichtbare Leuchten (für ALLE Spieler sichtbar, da echte Instanzen am
-- Charakter) -- die Entsättigung der Umgebung passiert separat CLIENT-seitig, nur für den
-- betroffenen Spieler selbst (siehe MeltdownVisualClient.lua, ColorCorrectionEffect an der
-- eigenen Kamera bleibt lokal).
local function applyMeltdownGlow(character)
	if not character or character:FindFirstChild("MeltdownGlow") then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "MeltdownGlow"
	highlight.FillColor = Color3.fromRGB(255, 20, 10)
	highlight.FillTransparency = 0.35
	highlight.OutlineColor = Color3.fromRGB(255, 60, 30)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local light = Instance.new("PointLight")
		light.Name = "MeltdownLight"
		light.Color = Color3.fromRGB(255, 30, 20)
		light.Brightness = 6
		light.Range = 20
		light.Parent = root
	end
end

local function removeMeltdownGlow(character)
	if not character then
		return
	end
	local highlight = character:FindFirstChild("MeltdownGlow")
	if highlight then
		highlight:Destroy()
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local light = root and root:FindFirstChild("MeltdownLight")
	if light then
		light:Destroy()
	end
end

-- ===== Fraktions-Energie-Effekte für Kaiju (von EnergyTypesHandler.lua aufgerufen) =====
local ELECTRIC_BOOST_DURATION = 8 -- Sekunden pro "Ladung", stapelt nicht in der Dauer, nur der Menge
local ELECTRIC_COOLDOWN_MULT = 0.7 -- 30% kürzere Cooldowns während des Boosts

_G.ExtendBerserk = function(player, extraSeconds)
	if not player:GetAttribute("BerserkActive") then
		return -- kein aktiver Berserk zum Verlängern
	end
	lastBerserkHitAt[player] = os.clock() + math.max(extraSeconds, 0)
end

_G.GrantElectricBoost = function(player, amount)
	local now = Workspace:GetServerTimeNow()
	local currentEnd = player:GetAttribute("ElectricBoostEndsAt") or 0
	player:SetAttribute("ElectricBoostEndsAt", math.max(currentEnd, now) + ELECTRIC_BOOST_DURATION)
end

local function isElectricBoostActive(player)
	return Workspace:GetServerTimeNow() < (player:GetAttribute("ElectricBoostEndsAt") or 0)
end

-- ===== Schadens-/Geschwindigkeits-Multiplikator (Namen bewusst vom alten
-- Berserker-System übernommen -- gleiche Schnittstelle, neue Berechnung). =====
_G.GetBerserkerDamageMultiplier = function(player)
	local heat = getHeat(player)
	local berserkActive = player:GetAttribute("BerserkActive")
	local multiplier
	local inBerserkTier = false

	if heat >= getEffectiveMeltdownThreshold(player) then
		multiplier = DAMAGE_MULT_ENRAGED -- Meltdown: weiterhin erhöhter Schaden, aber nicht der volle Berserk-Bonus
		inBerserkTier = true
	elseif heat >= getEffectiveBerserkThreshold(player) then
		multiplier = berserkActive and DAMAGE_MULT_BERSERK or DAMAGE_MULT_ENRAGED
		inBerserkTier = true
	elseif heat >= STAGE_AGGRESSIVE_MAX then
		multiplier = DAMAGE_MULT_ENRAGED
	elseif heat >= STAGE_CALM_MAX then
		multiplier = DAMAGE_MULT_AGGRESSIVE
	else
		multiplier = DAMAGE_MULT_CALM
	end

	-- Talent "Berserker Fury" (Kaiju-Talentbaum): zusätzlicher Schadensbonus, NUR
	-- innerhalb des Berserker-/Meltdown-Zustands (nicht in den früheren Stufen).
	if inBerserkTier and _G.GetTalentBerserkerDamageBonus then
		multiplier = multiplier + _G.GetTalentBerserkerDamageBonus(player)
	end

	-- Strahlungs-Mutation "Overheat Bruiser" (falls diese Runde ausgelöst): dauerhafter
	-- Schadensbonus für den Rest der Session (siehe EnergyTypesHandler.lua).
	multiplier = multiplier * (player:GetAttribute("MutationDamageMultiplier") or 1.0)
	return multiplier
end

-- Cooldown-Multiplikator: höhere Hitzestufen = etwas kürzere Cooldowns (fühlt sich
-- aggressiver/schneller an), gleiche Grundidee wie der alte Berserker-Bonus.
_G.GetBerserkerCooldownMultiplier = function(player)
	local heat = getHeat(player)
	local berserkActive = player:GetAttribute("BerserkActive")
	local multiplier

	if heat >= getEffectiveBerserkThreshold(player) and berserkActive then
		multiplier = 1 / SPEED_MULT_BERSERK
	elseif heat >= STAGE_AGGRESSIVE_MAX then
		multiplier = 1 / SPEED_MULT_ENRAGED
	else
		multiplier = 1.0
	end

	-- Elektro-Boost: zusätzlich kürzere Cooldowns.
	if isElectricBoostActive(player) then
		multiplier = multiplier * ELECTRIC_COOLDOWN_MULT
	end
	return multiplier
end

-- WalkSpeed-Multiplikator fürs Bewegungstempo (Enraged/Berserk = schneller).
_G.GetHeatSpeedMultiplier = function(player)
	local heat = getHeat(player)
	local berserkActive = player:GetAttribute("BerserkActive")

	if heat >= getEffectiveMeltdownThreshold(player) then
		return 0.25 -- Meltdown: stark verlangsamt, deutlicher Kontrollverlust
	elseif heat >= getEffectiveBerserkThreshold(player) and berserkActive then
		return SPEED_MULT_BERSERK
	elseif heat >= STAGE_AGGRESSIVE_MAX then
		return SPEED_MULT_ENRAGED
	end
	return 1.0
end

-- ===== Kontrollierte Berserk-Aktivierung =====
ActivateBerserkEvent.OnServerEvent:Connect(function(player)
	if player:GetAttribute("BerserkActive") then
		return -- schon aktiv
	end
	if getHeat(player) < BERSERK_AVAILABLE_AT then
		return -- noch nicht heiß genug
	end
	player:SetAttribute("BerserkActive", true)
	lastBerserkHitAt[player] = os.clock()
end)

-- ===== Haupt-Loop: Berserk-Timeout, Meltdown-Explosionen, passive Abkühlung während
-- Meltdown =====
RunService.Heartbeat:Connect(function(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local heat = getHeat(player)

		-- Fürs Client-Zifferblatt (SkinSelectionGui.lua): effektive Meltdown-Schwelle
		-- als Attribut bereitstellen, damit die Sektor-Farbgrenze talent-abhängig
		-- mitwandert, statt fest bei 100 zu bleiben.
		player:SetAttribute("EffectiveMeltdownThreshold", getEffectiveMeltdownThreshold(player))

		-- WalkSpeed an die aktuelle Hitzestufe UND den Sprint-Status anpassen -- NICHT
		-- während des Trainings (das setzt WalkSpeed bewusst auf 0, das dürfen wir nicht
		-- überschreiben).
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local isTraining = player:GetAttribute("TrainingStat") or player:GetAttribute("BodyTrainingActive")
		if humanoid and not isTraining then
			local baseWalkSpeed = player:GetAttribute("BaseWalkSpeed")
			if baseWalkSpeed then
				local sprintMultiplier = player:GetAttribute("IsSprinting") and SPRINT_SPEED_MULTIPLIER or 1
				humanoid.WalkSpeed = baseWalkSpeed * _G.GetHeatSpeedMultiplier(player) * sprintMultiplier
			end
		end

		-- Bein-Training: Heat sinkt durchgehend und deutlich schneller als im echten
		-- Kampf, UNABHÄNGIG von der aktuellen Stufe (normalerweise gibt es unterhalb der
		-- Berserker-Schwelle gar keinen Abbau) -- damit bleibt Sprung/Spezialangriffe
		-- trotz der zusätzlichen Heat-Erzeugung durchgehend nutzbar, statt in einer
		-- Meltdown-Sackgasse zu enden.
		if player:GetAttribute("TrainingStat") == "Leg" and heat > 0 then
			setHeat(player, heat - LEG_TRAINING_HEAT_DECAY_PER_SECOND * dt)
		end

		-- Berserk automatisch beenden: zu lange kein Treffer, oder Heat zu weit gesunken
		if player:GetAttribute("BerserkActive") then
			local lastHit = lastBerserkHitAt[player] or 0
			if heat < BERSERK_MIN_HEAT_TO_STAY or os.clock() - lastHit > BERSERK_INACTIVITY_TIMEOUT then
				player:SetAttribute("BerserkActive", false)
			else
				-- Spital-Effekt: Heat sinkt langsamer -- Berserk hält dadurch länger an
				-- (positiver Effekt, mehr Kontrolle über die eigene Hitze-Kurve). Talent
				-- "Titan Regeneration" (Kaiju-Talentbaum) beschleunigt das Abklingen
				-- zusätzlich, damit man schneller aus Berserk/Meltdown rauskommt.
				local coolingBonus = 1 + ((_G.GetTalentHeatCoolingBonus and _G.GetTalentHeatCoolingBonus(player)) or 0)
				setHeat(player, heat - BERSERK_HEAT_DECAY_PER_SECOND * getHospitalDecayMultiplier(player) * coolingBonus * dt)
			end
		end

		-- Meltdown: sofortige Explosion beim Eintritt, danach alle 8s eine weitere --
		-- schadet NUR dem Spieler selbst, Häuser bleiben unberührt. Heat sinkt
		-- währenddessen nur sehr langsam von selbst (Absorbieren bleibt der Hauptweg,
		-- um schneller rauszukommen).
		if heat >= getEffectiveMeltdownThreshold(player) then
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local now = Workspace:GetServerTimeNow()

			if not wasInMeltdown[player] then
				-- Gerade erst in Meltdown eingetreten -- sofortige erste Explosion, nicht
				-- erst nach den vollen 8 Sekunden warten. Zusätzlich die Mindestdauer-
				-- Sperre setzen, damit Heat für die nächsten 10s nicht unter 100% fallen
				-- kann (sonst wäre Meltdown durch Absorbieren fast sofort wieder vorbei).
				wasInMeltdown[player] = true
				lastMeltdownExplosionAt[player] = now
				meltdownLockedUntil[player] = os.clock() + MELTDOWN_LOCK_DURATION
				applyMeltdownGlow(character)
				if humanoid and root then
					humanoid:TakeDamage(MELTDOWN_SELF_DAMAGE)
					MeltdownExplosionEvent:FireClient(player, root.Position)
				end
			else
				-- Absicherung: falls der Charakter zwischenzeitlich respawnt ist (z.B.
				-- durch Tod), fehlt dem neuen Charakter der Glow -- hier erneut anwenden.
				applyMeltdownGlow(character)

				local lastExplosion = lastMeltdownExplosionAt[player] or 0
				if now - lastExplosion >= MELTDOWN_EXPLOSION_INTERVAL and humanoid and root then
					lastMeltdownExplosionAt[player] = now
					humanoid:TakeDamage(MELTDOWN_SELF_DAMAGE)
					MeltdownExplosionEvent:FireClient(player, root.Position)
				end
			end

			-- Talent "Titan Regeneration" (Kaiju-Talentbaum) beschleunigt auch das
			-- Abklingen aus Meltdown.
			local meltdownCoolingBonus = 1 + ((_G.GetTalentHeatCoolingBonus and _G.GetTalentHeatCoolingBonus(player)) or 0)

			-- WICHTIG: die sehr langsame MELTDOWN_HEAT_DECAY_PER_SECOND gilt nur, SOLANGE
			-- die Mindestdauer-Sperre noch aktiv ist (Heat wird da ohnehin auf 100
			-- geklemmt, die genaue Abbaurate spielt in dem Fenster keine Rolle). Sobald die
			-- Sperre abgelaufen ist, gilt wieder die normale Berserk-Abbaurate -- vorher
			-- blieb Heat nach der Sperre fälschlich weiterhin extrem langsam bei ~100%
			-- hängen (0.2/Sekunde -- ca. 500 Sekunden bis 0).
			local lockedUntil = meltdownLockedUntil[player]
			local isStillLocked = lockedUntil and os.clock() < lockedUntil
			local decayRate = isStillLocked and MELTDOWN_HEAT_DECAY_PER_SECOND or BERSERK_HEAT_DECAY_PER_SECOND
			setHeat(player, heat - decayRate * meltdownCoolingBonus * dt)
		else
			if wasInMeltdown[player] then
				removeMeltdownGlow(character)
			end
			wasInMeltdown[player] = false

			-- Allgemeiner, durchgehender Abbau -- greift IMMER, sobald Heat unter der
			-- Meltdown-Schwelle liegt, unabhängig vom BerserkActive-Status. Vorher gab es
			-- eine Lücke: war BerserkActive gerade false (z.B. durch Inaktivitäts-Timeout),
			-- aber Heat noch knapp unter der Meltdown-Schwelle (z.B. 99%), griff GAR KEIN
			-- Abbau-Pfad -- Heat blieb für immer stehen, statt wie dokumentiert "von selbst
			-- über Zeit abzukühlen".
			if not player:GetAttribute("BerserkActive") and heat > 0 then
				local coolingBonus = 1 + ((_G.GetTalentHeatCoolingBonus and _G.GetTalentHeatCoolingBonus(player)) or 0)
				setHeat(player, heat - BERSERK_HEAT_DECAY_PER_SECOND * getHospitalDecayMultiplier(player) * coolingBonus * dt)
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("Heat", 0)
	player:SetAttribute("BerserkActive", false)

	-- WICHTIG: auch bei JEDEM Respawn zurücksetzen, nicht nur beim erstmaligen
	-- Beitreten -- vorher konnte BerserkActive dauerhaft auf true hängen bleiben, wenn
	-- ein Spieler während aktivem Berserk starb (z.B. spürbar als dauerhaft entsättigte/
	-- dunklere Umgebung, siehe MeltdownVisualClient.lua, das genau auf dieses Attribut
	-- reagiert).
	player.CharacterAdded:Connect(function()
		player:SetAttribute("Heat", 0)
		player:SetAttribute("BerserkActive", false)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastBerserkHitAt[player] = nil
	lastMeltdownExplosionAt[player] = nil
	hospitalStabilityUntil[player] = nil
	wasInMeltdown[player] = nil
	meltdownLockedUntil[player] = nil
end)