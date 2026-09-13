-- VERSION: 2026-08-26 #3
-- FEATURE: ForceCloseShopEvent ergaenzt -- schliesst den Shop zwangsweise
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
-- Baut: Level + Fortschrittsbalken (oben Mitte), Coins-Anzeige (oben links),
-- "Skin kaufen"-Button darunter mit Skin-Shop-Menü. Alles im knalligen Comic-Look:
-- dicke schwarze Outlines, runde Ecken, große verspielte Schrift.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local ComicStyleUtils = require(ReplicatedStorage:WaitForChild("ComicStyleUtils"))
local ModelPreviewUtils = require(ReplicatedStorage:WaitForChild("ModelPreviewUtils"))
-- Nur fuer die Scanfenster: es weiss als einzige Stelle, welches Modell eine Figuren-Stufe
-- darstellt. Der Zugriff ist abgesichert, weil das Modul noch entsteht -- fehlt es, fallen
-- die Scans auf die getragene Figur zurueck statt auszufallen.
local okStageModels, StageModels = pcall(function()
	return require(ReplicatedStorage:WaitForChild("StageModels", 5))
end)
if not okStageModels then
	StageModels = nil
	warn("[Kaiju Debug] StageModels nicht verfuegbar -- die Scans zeigen die getragene Figur.")
end
local UiTypography = require(ReplicatedStorage:WaitForChild("UiTypography"))
local TopInsetUtils = require(ReplicatedStorage:WaitForChild("TopInsetUtils"))
local applyComicStyle = ComicStyleUtils.Apply
local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))
print("[Kaiju Debug] SkinSelectionGui: Module geladen, baue HUD.")

-- Icon + Farbe pro Energie-Typ für die fliegende Zahl-Animation -- dieselben Farben wie
-- im Talentbaum/HUD (TalentTreeClient.lua, EnergyTypesClient.lua), konsistent im ganzen Spiel.
local ENERGY_TYPE_VISUALS = {
	Heat = { icon = "🔥", color = Color3.fromRGB(255, 140, 30) },
	Chemical = { icon = "🧪", color = Color3.fromRGB(255, 45, 190) },
	Electric = { icon = "⚡", color = Color3.fromRGB(57, 217, 255) },
	Radiation = { icon = "☢️", color = Color3.fromRGB(126, 255, 16) },
	Spirit = { icon = "✨", color = Color3.fromRGB(255, 205, 70) },
}
local DEFAULT_ENERGY_VISUAL = { icon = "⚡", color = Color3.fromRGB(255, 140, 40) }

-- Für die Kraft-Werte (Bein/Arm/Körper): bei kleinen Zahlen (<1000, der übliche Bereich)
-- zwei Nachkommastellen zeigen (z.B. "0.27"), da das Training jetzt SEHR fein variiert
-- (100x verlangsamt -> viele kleine Schritte). Bei großen Zahlen bleibt die k/M-Kurzform
-- von NumberFormat sinnvoller (Dezimalstellen wären da ohnehin nicht mehr relevant).
local function formatStatValue(value)
	if value < 1000 then
		local text = string.format("%.2f", value)
		text = text:gsub("0$", ""):gsub("%.$", "") -- "4.00" -> "4", "3.70" -> "3.7", "3.27" bleibt "3.27"
		return text
	end
	return NumberFormat.Format(value)
end
local SkinsConfig = require(ReplicatedStorage:WaitForChild("SkinsConfig"))
local PurchaseSkinEvent = RemoteEventUtils.GetOrCreate("PurchaseSkinEvent")
-- Das Anlegen eines bereits besessenen Skins. Der Server hat den Handler seit jeher, aber
-- kein Client hat ihn je gefeuert -- bisher kaufte und ruestete PurchaseSkinEvent in einem
-- Zug aus. Mit dem Steckbrief sind das zwei getrennte Handlungen.
local EquipSkinEvent = RemoteEventUtils.GetOrCreate("EquipSkinEvent")
local CoinsEarnedEvent = RemoteEventUtils.GetOrCreate("CoinsEarnedEvent")
local EnergyAbsorbEvent = RemoteEventUtils.GetOrCreate("EnergyAbsorbEvent")
local StopTrainingEvent = RemoteEventUtils.GetOrCreate("StopTrainingEvent")
local TrainPointEvent = RemoteEventUtils.GetOrCreate("TrainPointEvent")
local statCapPerLevelValue = ReplicatedStorage:WaitForChild("StatCapPerLevel")
local boostDurationValue = ReplicatedStorage:WaitForChild("BoostDuration")

-- WICHTIG: Trag hier deine eigene Sound-ID aus dem Creator Store ein (Format: "rbxassetid://12345678")
local TRAIN_POINT_SOUND_ID = "rbxassetid://86850632846358"

local trainPointSound = Instance.new("Sound")
trainPointSound.Name = "TrainPointSound"
trainPointSound.SoundId = TRAIN_POINT_SOUND_ID
trainPointSound.Volume = 0.6
trainPointSound.Parent = SoundService

-- WICHTIG: Trag hier deine eigene Sound-ID aus dem Creator Store ein (Format: "rbxassetid://12345678")
local CASH_SOUND_ID = "rbxassetid://135483737426662"

local cashSound = Instance.new("Sound")
cashSound.Name = "CashSound"
cashSound.SoundId = CASH_SOUND_ID
cashSound.Volume = 0.8
cashSound.Parent = SoundService

-- WICHTIG: Trag hier deine eigene Sound-ID aus dem Creator Store ein
local ENERGY_ARRIVE_SOUND_ID = "rbxassetid://0"

local energyArriveSound = Instance.new("Sound")
energyArriveSound.Name = "EnergyArriveSound"
energyArriveSound.SoundId = ENERGY_ARRIVE_SOUND_ID
energyArriveSound.Volume = 0.7
energyArriveSound.Parent = SoundService

-- Solange eine Münz-Flug-Animation läuft, soll der normale Coins-Changed-Handler
-- den Zähler NICHT sofort überschreiben (sonst springt die Zahl vor der Animation hoch).
local isAnimatingCoins = false

-- ===== Comic-Style Hilfsfunktion =====
-- (jetzt über ComicStyleUtils, siehe oben -- war hier zuvor dupliziert)

-- Lässt ein GUI-Element kurz hell aufblitzen (Hintergrundfarbe -> heller Blitz -> zurück
-- zur Originalfarbe) -- z.B. bei Level-Aufstieg oder Coins-Zuwachs, als kurzes visuelles
-- Feedback "hier hat sich gerade was erhöht".
local function flashElement(guiObject, flashColor)
	flashColor = flashColor or Color3.new(1, 1, 1)

	-- Die ECHTE Ursprungsfarbe/-transparenz nur EINMALIG sichern (als Attribut) --
	-- bei schnell aufeinanderfolgenden Aufrufen (z.B. während des Boosts) würde sonst
	-- jeder neue Aufruf die aktuelle, evtl. noch mitten im Übergang befindliche Farbe als
	-- "Original" übernehmen, wodurch die Farbe über mehrere Klicks hinweg Richtung Weiß
	-- driften und dort hängen bleiben könnte.
	--
	-- Die beiden Werte werden EINZELN geprueft, nicht gemeinsam in einem Block. Vorher
	-- hing die Transparenz mit an der Bedingung "RestColor ist noch nicht gesetzt" -- und
	-- der Lebensbalken setzt RestColor selbst, weil seine Ruhefarbe mit dem Stand wechselt.
	-- Damit war die Bedingung beim ersten Aufruf schon falsch, RestTransparency blieb nil,
	-- und math.min(nil, 0.3) brach die Funktion ab, bevor irgendein Uebergang startete:
	-- der Balken wurde kleiner, poppte aber nie auf.
	if guiObject:GetAttribute("RestColor") == nil then
		guiObject:SetAttribute("RestColor", guiObject.BackgroundColor3)
	end
	if guiObject:GetAttribute("RestTransparency") == nil then
		guiObject:SetAttribute("RestTransparency", guiObject.BackgroundTransparency)
	end
	local originalColor = guiObject:GetAttribute("RestColor")
	local originalTransparency = guiObject:GetAttribute("RestTransparency")

	-- Beim Aufblitzen NIE durchsichtiger machen als es ohnehin schon ist -- nur für
	-- normalerweise unsichtbare Elemente (z.B. der transparente Level-Rahmen) kurz auf
	-- 0.3 einblenden. Bereits voll sichtbare Elemente (z.B. die Balken, Transparency 0)
	-- bleiben bei ihrer eigenen (helleren) Transparenz -- sonst würde der "Blitz" sie
	-- unsichtbarer statt heller machen.
	local flashTransparency = math.min(originalTransparency, 0.3)

	local flashUp = TweenService:Create(guiObject, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = flashColor,
		BackgroundTransparency = flashTransparency,
	})
	flashUp.Completed:Connect(function()
		TweenService:Create(guiObject, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundColor3 = originalColor,
			BackgroundTransparency = originalTransparency,
		}):Play()
	end)
	flashUp:Play()
end

-- Echter LEUCHT-Effekt (nicht nur Farbwechsel): legt einen hellen, nach außen wachsenden
-- und verblassenden Rand um das Element -- simuliert ein kurzes "Überstrahlen"/Glühen,
-- da Roblox-UI kein echtes Bloom kennt.
local function glowFlashElement(guiObject, glowColor)
	glowColor = glowColor or Color3.fromRGB(255, 255, 200)

	local glowStroke = Instance.new("UIStroke")
	glowStroke.Name = "GlowFlash"
	glowStroke.Thickness = 0
	glowStroke.Color = glowColor
	glowStroke.Transparency = 0
	glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glowStroke.Parent = guiObject

	local growTween = TweenService:Create(
		glowStroke,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Thickness = 6 }
	)
	growTween.Completed:Connect(function()
		local fadeTween = TweenService:Create(
			glowStroke,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Thickness = 0, Transparency = 1 }
		)
		fadeTween.Completed:Connect(function()
			glowStroke:Destroy()
		end)
		fadeTween:Play()
	end)
	growTween:Play()
end

-- Laesst einen Balken auf seine neue Groesse GLEITEN statt zu springen. Ein Sprung von
-- 100 auf 80 sagt nur "es ist jetzt weniger". Eine Bewegung zeigt, wie viel weniger und in
-- welche Richtung -- das liest man, ohne die Zahl daneben anzusehen.
--
-- Ein laufender Uebergang wird vorher abgebrochen. Ohne das ueberlagern sich bei schnell
-- aufeinanderfolgenden Treffern mehrere Uebergaenge, und der Balken zappelt, statt einer
-- Bewegung zu folgen.
local laufendeBalken = {}

local function slideBar(fillFrame, ratio)
	local alt = laufendeBalken[fillFrame]
	if alt then
		alt:Cancel()
	end

	local uebergang = TweenService:Create(
		fillFrame,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0) }
	)
	laufendeBalken[fillFrame] = uebergang
	uebergang:Play()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== Coins-Anzeige: oben rechts, klein (neue HUD-Spezifikation -- Geld ist
-- sekundäre Information, keine grosse gelbe Fläche mehr) =====
-- Das Geld stand in Gold auf braunem Grund mit dem Emoji 💰. Jetzt: dunkles Panel wie
-- alles andere, das hochgeladene Muenz-Symbol links, die Zahl in der Ziffernschrift.
--
-- Die Zahl behaelt ihren Goldton -- sie IST eine Messung, und Farbe ist nach der Stilregel
-- genau dafuer da. Grund und Rahmen bleiben farblos.
-- Dieselbe Hoehe wie der Home-Knopf daneben (44), damit die obere rechte Ecke eine Reihe
-- ergibt. Vorher war das Feld mit 32 Pixeln niedriger als seine Nachbarn.
local coinsFrame = Instance.new("Frame")
coinsFrame.Name = "CoinsFrame"
coinsFrame.Size = UDim2.new(0, 168, 0, 44)
coinsFrame.AnchorPoint = Vector2.new(1, 0)
-- Die Reihe rechts, von aussen nach innen: Ton (-16), Home (-68), Geld (-120).
-- Der Ton-Knopf stand vorher eine Zeile tiefer und hat dort eine zweite Reihe
-- aufgemacht -- fuer einen einzigen Knopf.
coinsFrame.Position = UDim2.new(1, -120, 0, 16)
coinsFrame.Parent = screenGui
HudChrome.Panel(coinsFrame, { radius = HudChrome.Radius.Small })

-- Das Waehrungszeichen aus der Vorlage statt des hochgeladenen Muenzbildes. Das Bild ist
-- bunt und bricht damit die Regel, dass das Chrome farblos bleibt -- ein Zeichen nimmt
-- dagegen den Goldton des Betrags an und gehoert sichtbar zu ihm.
--
-- Das Muenzbild bleibt in HudChrome.Icon.Coin erhalten: die fliegenden Muenzen, die beim
-- Zerstoeren eines Gebaeudes zum Zaehler wandern, sind genau die Stelle, an der ein
-- buntes Bild richtig ist.
local coinsIcon = Instance.new("TextLabel")
coinsIcon.Name = "CoinsIcon"
coinsIcon.Size = UDim2.new(0, 30, 1, 0)
coinsIcon.Position = UDim2.new(0, 10, 0, 0)
coinsIcon.BackgroundTransparency = 1
coinsIcon.TextXAlignment = Enum.TextXAlignment.Left
coinsIcon.Text = "¥"
coinsIcon.Parent = coinsFrame
HudChrome.Number(coinsIcon, 26)
coinsIcon.TextColor3 = Color3.fromRGB(255, 205, 60)

-- Rechtsbuendig, wie Betraege in der Buchhaltung stehen: die Einerstelle bleibt an
-- derselben Stelle, egal wie lang die Zahl wird. Bei einem Zaehler, der von 9.999 auf
-- 10.000 springt, ist das der Unterschied zwischen ruhig und zappelig.
local coinsLabel = Instance.new("TextLabel")
coinsLabel.Name = "CoinsLabel"
coinsLabel.Size = UDim2.new(1, -56, 1, 0)
coinsLabel.Position = UDim2.new(0, 44, 0, 0)
coinsLabel.BackgroundTransparency = 1
coinsLabel.TextXAlignment = Enum.TextXAlignment.Right
coinsLabel.Text = "0"
coinsLabel.Parent = coinsFrame
HudChrome.Number(coinsLabel, 22)
coinsLabel.TextColor3 = Color3.fromRGB(255, 205, 60)

-- Laesst das GANZE Geldfeld aufblitzen: Grund und Rahmen. flashElement allein faerbt nur
-- den Hintergrund; bei einem Panel mit duennem Stahlrahmen ist der Rahmen aber die
-- sichtbarste Kante, und ein Blitz, der ihn auslaesst, wirkt wie ein Fehler.
local coinsStroke = coinsFrame:FindFirstChildOfClass("UIStroke")

local COINS_GOLD = Color3.fromRGB(255, 205, 60)
local COINS_BLITZ = Color3.fromRGB(255, 240, 190)

-- Der Text wird ueber seine SCHRIFTfarbe aufgehellt, nicht ueber seinen Hintergrund.
-- flashElement kann das nicht: es faerbt grundsaetzlich den Hintergrund und hebt ihn dabei
-- auf Transparenz 0.3 an. Bei einem durchsichtigen Label macht das ein Rechteck sichtbar,
-- das sonst niemand sieht -- das waren die "verschiedenen Felder mit schwarzen Raendern".
local function pulseCoinText(label)
	label.TextColor3 = COINS_BLITZ
	TweenService:Create(
		label,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextColor3 = COINS_GOLD }
	):Play()
end

-- Ein einziger Blitz ueber das ganze Feld: Grund, Rahmen, Zeichen und Betrag zusammen.
local function flashCoinsFrame()
	flashElement(coinsFrame, Color3.fromRGB(60, 52, 28))
	pulseCoinText(coinsIcon)
	pulseCoinText(coinsLabel)
	if not coinsStroke then
		return
	end
	if coinsStroke:GetAttribute("RestColor") == nil then
		coinsStroke:SetAttribute("RestColor", coinsStroke.Color)
	end
	local ruhe = coinsStroke:GetAttribute("RestColor")
	coinsStroke.Color = COINS_BLITZ
	TweenService:Create(
		coinsStroke,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Color = ruhe }
	):Play()
end

-- ===== Player-Status-Cluster: Health + Level + XP als EIN kompakter Block, oben Mitte
-- (neue HUD-Spezifikation) -- vorher zwei separate, deutlich grössere Frames (142px
-- Gesamthöhe), jetzt ein einziger, ~78px hoher Cluster. Priorität: Health > Level > XP.
-- ZWEI Felder, kein gemeinsames Gehaeuse: links die Stufe, rechts das Leben. Sie stehen
-- dicht beieinander und gehoeren erkennbar zusammen, sind aber getrennt lesbar -- so wie
-- in der Vorlage.
--
-- Die aeussere Kante jedes Feldes laeuft schraeg nach unten auf die Mitte zu. Beide
-- Schraegen zeigen damit auf denselben Punkt: die Spielfigur in der Bildschirmmitte.
-- Beide Felder sind GLEICH breit. Damit liegt die Trennfuge zwischen ihnen genau auf der
-- Bildschirmmitte -- also ueber der Spielfigur, auf die auch die beiden Schraegen zeigen.
-- Bei verschieden breiten Feldern sass die Fuge daneben, und die Symmetrie, die die
-- Schraegen aufbauen, war schon durch die Aufteilung gebrochen.
local STATUS_HOEHE = 62
local STATUS_SCHRAEGE = 16
local STATUS_LUECKE = 12
-- Breiter als frueher, weil der Zielwert es verlangt: "101.7k / 196.4k" sind bei 15 Punkt
-- Ziffernschrift rund 135 Pixel. Bei 240 Pixeln Feldbreite waere er der grossen Zahl in
-- die Quere gekommen -- eine Zahl, die man erst beim Lesen als zwei erkennt.
local FELD_BREITE = 280

-- Innenraender. Auf der SCHRAEGEN Seite braucht der Inhalt deutlich mehr Abstand als auf
-- der geraden: unten frisst die Schraege bis zu STATUS_SCHRAEGE Pixel weg, und was nur
-- knapp daneben sitzt, sieht aus, als laege es halb draussen. Der Wert ist deshalb die
-- volle Schraege plus zehn Pixel Luft, nicht ein knapp gerechneter Rest.
local RAND_SCHRAEG = STATUS_SCHRAEGE + 10
local RAND_GERADE = 14

local LEVEL_LINKS = RAND_SCHRAEG
local LEVEL_RECHTS = FELD_BREITE - RAND_GERADE
local HP_LINKS = RAND_GERADE
local HP_RECHTS = FELD_BREITE - RAND_SCHRAEG

-- Die Zeilen. Eine Textzeile oben, ein Balken darunter, darunter Luft -- als feste Werte
-- an einer Stelle, damit die vier Beschriftungen und die zwei Balken nicht einzeln
-- nachgerechnet werden muessen.
local ZEILE_Y = 7
local ZEILE_HOEHE = 28
local BALKEN_Y = 41
local BALKEN_HOEHE = 10

-- Die fette Zahl beginnt in beiden Feldern gleich weit hinter der Bezeichnung, damit die
-- zwei Felder denselben Takt haben -- auch wenn "LEVEL" laenger ist als "HP".
local ZAHL_VERSATZ = 56

-- ===== Warum oben KEINE Leiste steht =====
--
-- Es gab eine: eine durchgehende Blende ueber die ganze Breite, als Grund, auf dem
-- Statusfelder, Geld, Home und Ton sitzen. Auf dem Rechner sass sie gut.
--
-- Auf dem Telefon nicht. Sie musste dort zwei Dinge zugleich sein -- der Grund unter den
-- eigenen Anzeigen UND die Flaeche hinter Robloxs Systemleiste, die auf dem Telefon deutlich
-- hoeher ist als auf dem Rechner. Das Ergebnis war ein Band ueber fast ein Drittel der
-- Bildhoehe. Es sah aus, als bestuende der halbe Schirm aus Leiste.
--
-- Die Lehre ist allgemeiner: eine Flaeche, deren Hoehe von etwas Fremdem abhaengt, laesst
-- sich nicht gestalten. Die Anzeigen stehen deshalb wieder frei -- jede traegt ihren eigenen
-- dunklen Grund, und den Zusammenhang stiftet die gemeinsame Zeile, nicht ein Kasten
-- darunter. Die Reihe rechts (Ton, Home, Geld) bleibt, sie war der eigentliche Gewinn.

local statusCluster = Instance.new("Frame")
statusCluster.Name = "PlayerStatusCluster"
statusCluster.Size = UDim2.new(0, FELD_BREITE * 2 + STATUS_LUECKE, 0, STATUS_HOEHE)
statusCluster.AnchorPoint = Vector2.new(0.5, 0)
statusCluster.Position = UDim2.new(0.5, 0, 0, 8)
statusCluster.BackgroundTransparency = 1
statusCluster.Parent = screenGui

-- ===== Eigene, mildere Skalierung fuer den Statusblock =====
--
-- Die Messung im Spiel hat es entschieden: die Felder werden geometrisch RICHTIG gebaut,
-- kein Kind ragt hinaus. Zu klein sind sie, weil ResponsiveHudScale das ganze HUD auf bis
-- zu 0.55 verkleinert -- es ist fuer 1280 x 720 ausgelegt, und auf dem Testgeraet greift
-- genau dieser Boden. Aus 240 x 56 werden dann 132 x 30 Pixel, aus 19 Punkt Schrift werden
-- zehn, aus 13 werden sieben.
--
-- Deshalb half Vergroessern zweimal nicht: der Faktor multipliziert jeden neuen Wert mit.
-- 240 statt 224 sind auf dem Schirm 132 statt 123 Pixel -- neun Pixel, wo dreissig fehlen.
--
-- Der Statusblock ist die Anzeige, die man im Kampf am haeufigsten ansieht. Er bekommt
-- seine eigene Gegenskalierung, die die globale teilweise zurueckdreht, bis mindestens
-- STATUS_MINDESTSKALA erreicht ist. Vollstaendig zurueckdrehen waere falsch: auf einem
-- kleinen Schirm SOLL das HUD schrumpfen, nur nicht so weit, dass man es nicht mehr liest.
local STATUS_MINDESTSKALA = 0.82

local statusScale = Instance.new("UIScale")
statusScale.Name = "StatusScaleCompensation"
statusScale.Scale = 1
statusScale.Parent = statusCluster

do
	local beobachtet = nil

	local function anwenden()
		local hudScale = screenGui:FindFirstChildOfClass("UIScale")
		local global = (hudScale and hudScale.Scale > 0) and hudScale.Scale or 1
		-- Nur nach OBEN ausgleichen: bei voller Groesse bleibt der Block unveraendert.
		statusScale.Scale = math.max(STATUS_MINDESTSKALA / global, 1)
	end

	-- Die globale UIScale entsteht moeglicherweise erst NACH diesem Skript -- die
	-- HUD-Skripte laufen parallel, ihre Reihenfolge ist nicht garantiert. Also sowohl
	-- jetzt pruefen als auch auf ihr Auftauchen und jede spaetere Aenderung hoeren.
	local function neuBinden()
		local hudScale = screenGui:FindFirstChildOfClass("UIScale")
		if hudScale ~= beobachtet then
			beobachtet = hudScale
			if hudScale then
				hudScale:GetPropertyChangedSignal("Scale"):Connect(anwenden)
			end
		end
		anwenden()
	end

	screenGui.ChildAdded:Connect(function(kind)
		if kind:IsA("UIScale") then
			neuBinden()
		end
	end)
	neuBinden()
end

local levelField = HudChrome.SlantPanel(statusCluster, {
	name = "LevelField",
	width = FELD_BREITE,
	height = STATUS_HOEHE,
	slant = STATUS_SCHRAEGE,
	side = "Left",
})
levelField.Position = UDim2.new(0, 0, 0, 0)

local healthField = HudChrome.SlantPanel(statusCluster, {
	name = "HealthField",
	width = FELD_BREITE,
	height = STATUS_HOEHE,
	slant = STATUS_SCHRAEGE,
	side = "Right",
})
healthField.Position = UDim2.new(0, FELD_BREITE + STATUS_LUECKE, 0, 0)

-- EINE Textzeile, nicht zwei: Bezeichnung, aktueller Wert und Zielwert stehen
-- nebeneinander. Zwei Zeilen machten aus einer Anzeige zwei und schoben den Balken nach
-- unten -- dabei ist der Balken die eigentliche Aussage, er zeigt das Verhaeltnis
-- schneller, als eine Zahl es je kann.
--
-- Die fette Zahl ist deshalb auch nur noch WENIG groesser als der Rest. Sie muss sich vom
-- Zielwert unterscheiden lassen, mehr nicht -- das erledigt der fette Schnitt, die Groesse
-- hilft nur nach.
local levelCaption = Instance.new("TextLabel")
levelCaption.Name = "LevelCaption"
levelCaption.Size = UDim2.new(0, ZAHL_VERSATZ - 4, 0, ZEILE_HOEHE)
levelCaption.Position = UDim2.new(0, LEVEL_LINKS, 0, ZEILE_Y)
levelCaption.BackgroundTransparency = 1
levelCaption.TextXAlignment = Enum.TextXAlignment.Left
levelCaption.Text = "LEVEL"
levelCaption.Parent = levelField
HudChrome.Label(levelCaption, 16)
levelCaption.TextColor3 = HudChrome.Color.TextSecondary

-- Die Zahl sitzt in einem Fenster mit ClipsDescendants. Das ist die Voraussetzung dafuer,
-- dass sie beim Aufstieg weiterruecken kann wie das Zaehlwerk einer Uhr: die alte Zahl
-- faehrt nach oben aus dem Fenster, die neue kommt von unten nach. Ohne das Fenster
-- wuerden beide sichtbar ueber die Feldkanten hinausrutschen.
local levelNumberClip = Instance.new("Frame")
levelNumberClip.Name = "LevelNumberClip"
levelNumberClip.Size = UDim2.new(0, 80, 0, ZEILE_HOEHE)
levelNumberClip.Position = UDim2.new(0, LEVEL_LINKS + ZAHL_VERSATZ, 0, ZEILE_Y)
levelNumberClip.BackgroundTransparency = 1
levelNumberClip.ClipsDescendants = true
levelNumberClip.Parent = levelField

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelLabel"
levelLabel.Size = UDim2.new(1, 0, 1, 0)
levelLabel.Position = UDim2.new(0, 0, 0, 0)
levelLabel.BackgroundTransparency = 1
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.Text = "0"
levelLabel.Parent = levelNumberClip
HudChrome.NumberBold(levelLabel, 24)

-- ===== Der Aufstieg als mechanisches Weiterruecken =====
-- Eine Zahl, die sich einfach austauscht, ist kein Ereignis. Eine, die weiterrueckt, ist
-- eines -- und die Uhrzeit ist in diesem Spiel ohnehin das Koordinatensystem (siehe
-- CityAlertHudClient). Deshalb: harte, kurze Bewegung mit Quart-Ausklang, kein Ueberblenden.
--
-- WICHTIG: Trag hier die Sound-ID fuer das Klacken ein (Format: "rbxassetid://12345678").
-- Solange sie leer ist, laeuft die Bewegung stumm -- eine geratene ID waere schlimmer als
-- gar keine, weil sie im Spiel als "kaputter Klang" auftaucht statt als fehlender.
local LEVEL_TICK_SOUND_ID = ""
local LEVEL_TICK_SECONDS = 0.22

local levelTickSound = Instance.new("Sound")
levelTickSound.Name = "LevelTickSound"
levelTickSound.SoundId = LEVEL_TICK_SOUND_ID
levelTickSound.Volume = 0.8
levelTickSound.Parent = screenGui

local function playLevelTick(previousText)
	-- Bewusst ZEILE_HOEHE statt AbsoluteSize: Positionen sind Offsets im unskalierten
	-- Raum, AbsoluteSize ist bereits durch die HUD-UIScale gegangen. Beides zu mischen
	-- verschoebe die Zahl auf dem Telefon um genau den Skalierungsfaktor.
	local hoehe = ZEILE_HOEHE

	local alteZahl = levelLabel:Clone()
	alteZahl.Name = "LevelLabelOutgoing"
	alteZahl.Text = previousText
	alteZahl.Parent = levelNumberClip

	-- Die neue Zahl wartet unterhalb des Fensters und faehrt herein.
	levelLabel.Position = UDim2.new(0, 0, 0, hoehe)

	local ablauf = TweenInfo.new(LEVEL_TICK_SECONDS, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(alteZahl, ablauf, { Position = UDim2.new(0, 0, 0, -hoehe) }):Play()

	local einfahren = TweenService:Create(levelLabel, ablauf, { Position = UDim2.new(0, 0, 0, 0) })
	einfahren:Play()
	einfahren.Completed:Connect(function()
		-- Exakt setzen: wird der Tween von einem zweiten Aufstieg ueberholt, bliebe die
		-- Zahl sonst um Bruchteile daneben stehen und das summierte sich auf.
		levelLabel.Position = UDim2.new(0, 0, 0, 0)
	end)

	task.delay(LEVEL_TICK_SECONDS, function()
		alteZahl:Destroy()
	end)

	if levelTickSound.SoundId ~= "" then
		levelTickSound:Play()
	end
end

-- Der Balken ist zum schmalen Streifen an der Unterkante geworden. Die Zahl darueber
-- traegt die Aussage; der Balken zeigt nur noch das Verhaeltnis. Vorher war es umgekehrt,
-- und die Zahl musste deshalb im Balken stehen -- wo sie auf gelber Fuellung unlesbar war.
local healthFrame = Instance.new("Frame")
healthFrame.Name = "HealthFrame"
healthFrame.Size = UDim2.new(0, HP_RECHTS - HP_LINKS, 0, BALKEN_HOEHE)
healthFrame.Position = UDim2.new(0, HP_LINKS, 0, BALKEN_Y)
healthFrame.Parent = healthField
HudChrome.Panel(healthFrame, {
	radius = 3,
	fill = HudChrome.Color.PanelSunken,
	transparency = 0,
})

local healthBarFill = Instance.new("Frame")
healthBarFill.Name = "Fill"
healthBarFill.Size = UDim2.new(1, 0, 1, 0)
healthBarFill.BackgroundColor3 = Color3.fromRGB(70, 220, 90)
healthBarFill.BorderSizePixel = 0
healthBarFill.Parent = healthFrame
HudChrome.Panel(healthBarFill, { radius = 3, fill = false, border = false })

local healthCaption = Instance.new("TextLabel")
healthCaption.Name = "HealthCaption"
healthCaption.Size = UDim2.new(0, ZAHL_VERSATZ - 4, 0, ZEILE_HOEHE)
healthCaption.Position = UDim2.new(0, HP_LINKS, 0, ZEILE_Y)
healthCaption.BackgroundTransparency = 1
healthCaption.TextXAlignment = Enum.TextXAlignment.Left
healthCaption.Text = "HP"
healthCaption.Parent = healthField
HudChrome.Label(healthCaption, 16)
healthCaption.TextColor3 = HudChrome.Color.TextSecondary

-- Der Hoechstwert gehoert in die kleine Zeile, nicht neben die grosse Zahl: er aendert
-- sich fast nie und darf den Blick nicht mit dem teilen, der sich staendig aendert.
local healthMaxLabel = Instance.new("TextLabel")
healthMaxLabel.Name = "HealthMaxLabel"
healthMaxLabel.Size = UDim2.new(0, 120, 0, ZEILE_HOEHE)
healthMaxLabel.Position = UDim2.new(0, HP_RECHTS - 120, 0, ZEILE_Y)
healthMaxLabel.BackgroundTransparency = 1
healthMaxLabel.TextXAlignment = Enum.TextXAlignment.Right
healthMaxLabel.Text = "/ 100"
healthMaxLabel.Parent = healthField
HudChrome.Number(healthMaxLabel, 15)
healthMaxLabel.TextColor3 = HudChrome.Color.TextDim

-- Der aktuelle Lebensstand, fett. Er steht NEBEN dem Balken, nicht darin: im Balken war
-- er unlesbar -- weisse Schrift auf gruener und vor allem gelber Fuellung. Eine dunkle
-- Schrift haette es nicht geloest, denn bei niedrigem Leben ist der Balken fast leer und
-- dieselbe Zahl stuende dann auf dunklem Grund.
local healthLabel = Instance.new("TextLabel")
healthLabel.Name = "HealthLabel"
healthLabel.Size = UDim2.new(0, 100, 0, ZEILE_HOEHE)
healthLabel.Position = UDim2.new(0, HP_LINKS + ZAHL_VERSATZ, 0, ZEILE_Y)
healthLabel.BackgroundTransparency = 1
healthLabel.TextXAlignment = Enum.TextXAlignment.Left
healthLabel.Text = "100"
healthLabel.Parent = healthField
HudChrome.NumberBold(healthLabel, 24)

-- Robloxs EIGENE Lebensanzeige abschalten. Sie blendet sich oben rechts von selbst ein,
-- sobald das Leben unter das Maximum faellt -- also genau dann, wenn unsere eigene Anzeige
-- gerade etwas zu sagen hat. Zwei Lebensbalken auf einem Bildschirm sind einer zu viel,
-- und der von Roblox gehoert nicht zu diesem HUD.
--
-- Der Aufruf steht in einer Schleife mit pcall: SetCoreGuiEnabled schlaegt fehl, solange
-- die CoreGui noch nicht geladen ist, und die Reihenfolge zwischen ihr und diesem Skript
-- ist nicht garantiert. Ein einzelner Versuch beim Start waere ein Gluecksspiel.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
	warn("[Kaiju Debug] Robloxs Standard-Lebensanzeige liess sich nicht abschalten.")
end)

-- Der zuletzt gezeigte Lebensstand. Braucht es, um zu wissen, OB und in welche Richtung
-- sich etwas geaendert hat -- die Anzeige wird auch dann aufgerufen, wenn nur das Maximum
-- gewachsen ist.
local letzterLebensstand = nil

local function updateHealthBar()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local maxLeben = math.max(humanoid.MaxHealth, 1)
	local ratio = math.clamp(humanoid.Health / maxLeben, 0, 1)
	slideBar(healthBarFill, ratio)
	healthLabel.Text = NumberFormat.Format(math.floor(humanoid.Health))
	healthMaxLabel.Text = "/ " .. NumberFormat.Format(math.floor(humanoid.MaxHealth))

	-- Farbverlauf grün -> gelb -> rot, je niedriger desto dramatischer. Die Zahl faerbt
	-- erst ab der Warnstufe mit: solange es gut steht, ist Weiss die ruhigere Aussage --
	-- und eine Farbe, die IMMER da ist, warnt vor nichts.
	local balkenFarbe, zahlFarbe
	if ratio > 0.5 then
		balkenFarbe, zahlFarbe = Color3.fromRGB(70, 220, 90), HudChrome.Color.TextPrimary
	elseif ratio > 0.25 then
		balkenFarbe, zahlFarbe = HudChrome.Color.Warning, HudChrome.Color.Warning
	else
		balkenFarbe, zahlFarbe = HudChrome.Color.Danger, HudChrome.Color.Danger
	end
	healthBarFill.BackgroundColor3 = balkenFarbe
	healthLabel.TextColor3 = zahlFarbe

	-- flashElement merkt sich die Ruhefarbe EINMALIG als Attribut. Beim Lebensbalken
	-- wechselt sie aber mit dem Stand -- ohne diese Zeile blitzte er einmal auf und kehrte
	-- danach fuer immer ins Gruen des ersten Aufrufs zurueck, auch bei zehn Prozent Leben.
	healthBarFill:SetAttribute("RestColor", balkenFarbe)

	-- NUR Schaden poppt auf. Heilung poppte anfangs mit und war im Spiel der lauteste
	-- Effekt ueberhaupt -- dabei ist Heilung die gute Nachricht und braucht kein
	-- Ausrufezeichen. Sie bewegt den Balken, und das genuegt.
	--
	-- Der Blitz nimmt die FARBE DES BALKENS und hellt sie nur auf. Eine eigene Signalfarbe
	-- war falsch: ein roter Rahmen um einen gruenen Balken las sich wie ein zweiter,
	-- widersprechender Zustand -- als wechselte der Balken gerade die Stufe. Die eigene,
	-- aufgehellte Farbe sagt "hier hat sich etwas bewegt", ohne eine zweite Aussage
	-- aufzumachen. Gruener Pop am gruenen Balken, roter am roten.
	--
	-- Winzige Aenderungen bleiben aussen vor: Roblox regeneriert im Hintergrund staendig,
	-- und ein Balken, der im Sekundentakt blitzt, meldet nichts mehr, er flackert nur.
	local aenderung = letzterLebensstand and (humanoid.Health - letzterLebensstand) or 0
	letzterLebensstand = humanoid.Health
	if aenderung <= -maxLeben * 0.005 then
		local popFarbe = balkenFarbe:Lerp(Color3.new(1, 1, 1), 0.45)
		flashElement(healthBarFill, popFarbe)
		glowFlashElement(healthBarFill, popFarbe)
	end
end

-- Die Statusfelder bleiben ueberall stehen, auch im Sanctuary.
--
-- Frueher verschwanden sie dort, weil "kein Kampf, keine Lebensanzeige". Das HUD wechselte
-- damit beim Betreten sein Gesicht, und wer zurueckkam, musste sich neu zurechtfinden. Ein
-- HUD, das seine Form behaelt und stattdessen zeigt, was gerade NICHT geht, ist ruhiger --
-- dieselbe Ueberlegung wie bei den Angriffsknoepfen, die dort jetzt gesperrt statt
-- unsichtbar sind.
statusCluster.Visible = true

local function connectHealthBar(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	letzterLebensstand = nil
	updateHealthBar()
	humanoid:GetPropertyChangedSignal("Health"):Connect(updateHealthBar)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealthBar)
end

player.CharacterAdded:Connect(connectHealthBar)
if player.Character then
	connectHealthBar(player.Character)
end

-- Der XP-Balken liegt an derselben Stelle im Stufen-Feld wie der Lebensbalken im
-- Leben-Feld: schmaler Streifen an der Unterkante. Gleiche Rolle, gleiche Form -- beide
-- Felder sind damit auf einen Blick als dasselbe Bauteil zu erkennen.
local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.Size = UDim2.new(0, LEVEL_RECHTS - LEVEL_LINKS, 0, BALKEN_HOEHE)
barBackground.Position = UDim2.new(0, LEVEL_LINKS, 0, BALKEN_Y)
barBackground.Parent = levelField
HudChrome.Panel(barBackground, {
	radius = 3,
	fill = HudChrome.Color.PanelSunken,
	transparency = 0,
})

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
barFill.BorderSizePixel = 0
barFill.ZIndex = 2
barFill.Parent = barBackground
HudChrome.Panel(barFill, { radius = 3, fill = false, border = false })

-- Der Fortschritt als Zahl, rechts in der kleinen Zeile -- genau dort, wo im Leben-Feld
-- der Hoechstwert steht. Im Gelb des Balkens darunter, damit die beiden ohne Beschriftung
-- zusammengehoeren; das Wort "XP" spart das ein.
local xpLabel = Instance.new("TextLabel")
xpLabel.Name = "XpLabel"
xpLabel.Size = UDim2.new(0, 120, 0, ZEILE_HOEHE)
xpLabel.Position = UDim2.new(0, LEVEL_RECHTS - 120, 0, ZEILE_Y)
xpLabel.BackgroundTransparency = 1
xpLabel.TextXAlignment = Enum.TextXAlignment.Right
xpLabel.Text = "0 / 0"
xpLabel.Parent = levelField
HudChrome.Number(xpLabel, 15)
xpLabel.TextColor3 = Color3.fromRGB(214, 186, 78)

-- ===== Heat/Berserker-Leiste -- VERTIKAL, unten zentriert zwischen den Angriffs-Buttons
-- (Standardangriffe links, Spezialangriffe rechts) -- gleicher Kampf-Kontext, gleiche
-- Bildschirmzeile. Aktiviert Berserk automatisch (siehe HeatHandler.lua). =====
local MeltdownExplosionEvent = RemoteEventUtils.GetOrCreate("MeltdownExplosionEvent")

local heatFrame = Instance.new("Frame")
heatFrame.Name = "HeatFrame"
heatFrame.Size = UDim2.new(0, 280, 0, 200) -- doppelt so gross wie zuvor
heatFrame.AnchorPoint = Vector2.new(0.5, 1)
heatFrame.Position = UDim2.new(0.5, 0, 1, -24) -- EXAKT dieselbe Grundlinie wie die Angriffs-Buttons
heatFrame.BackgroundTransparency = 1 -- kein rechteckiger Rahmen mehr -- nur die Halbscheibe (siehe unten) ist sichtbar
heatFrame.ZIndex = 10
heatFrame.Parent = screenGui

-- Der gesamte Aufbau liegt in einem do-Block, und alles, was die Heartbeat-Schleife
-- spaeter braucht, wandert in EINE Tabelle.
--
-- Das ist keine Kosmetik: Luau erlaubt 200 gleichzeitig lebende lokale Variablen je
-- Funktion, und der Hauptteil dieser Datei ist eine einzige Funktion. Der Tacho-Umbau
-- hat sie auf 221 getrieben -- das Skript liess sich daraufhin gar nicht mehr
-- uebersetzen ("Out of local registers"), und damit fehlte schlagartig das GANZE HUD
-- aus dieser Datei: Geld, Statusfeld, Tacho, Trainingsbalken, Skin-Shop.
--
-- Ein do-Block gibt die Register seiner Locals am Ende wieder frei. Aus 64 Namen wird
-- so einer. Wer hier etwas ergaenzt, das die Schleife braucht, haengt es an `tacho` --
-- ein neuer Name auf oberster Ebene brauchte sonst wieder Platz, den es nicht gibt.
local tacho = {}
do
	-- ===== Der Tacho =====
	--
	-- Die Form bleibt, die Sprache aendert sich. Vorher fuellte das Zifferblatt eine
	-- durchgehende Farbflaeche vom Drehpunkt bis fast zum Rand -- viel Farbe, wenig Aussage,
	-- und der lauteste Comic-Rest im ganzen HUD. Jetzt traegt ein SCHMALES Band am Rand die
	-- Zonen, Teilstriche geben dem Blatt einen Massstab, und beschriftete Hauptwerte sagen,
	-- wo man steht. So liest sich ein Messgeraet: die Skala gehoert an den Rand, die Mitte
	-- bleibt ruhig.
	--
	-- WICHTIG (gilt fuer Nadel, Teilstriche und Bandsegmente gleichermassen): Roblox rotiert
	-- ein GuiObject um seinen EIGENEN Mittelpunkt, nicht um den AnchorPoint. Ein direkt
	-- rotiertes, langes Objekt draehte sich wie eine Kompassnadel um seine Mitte. Der Trick:
	-- ein winziger, unsichtbarer Dreh-Anker sitzt GENAU auf dem Drehpunkt, das eigentliche
	-- Teil ist sein Kind und ragt von ihm aus nach oben. Rotiert wird nur der Anker.
	local GAUGE_MAX = 110
	local GAUGE_CENTER = Vector2.new(140, 200) -- Drehpunkt = Unterkante von heatFrame = Grundlinie der Knoepfe

	-- Das Zifferblatt reicht bis an die INNENKANTE des Rings. Vorher endete es bei 104,
	-- der Ring begann bei 120 -- und der Energiebogen dazwischen lag auf nichts: er schwebte
	-- in einem durchsichtigen Spalt und sah aus, als gehoere er nicht dazu. Jetzt liegt er
	-- auf dem Blatt, wie jede andere Anzeige des Instruments auch.
	local FACE_RADIUS = 120 -- dunkles Zifferblatt, bis an den Ring
	local BAND_OUTER = 100 -- Farbband
	local BAND_INNER = 88
	local TICK_OUTER = 86 -- Teilstriche wachsen von hier nach innen
	local TICK_MINOR = 5
	local TICK_MAJOR = 11
	local LABEL_RADIUS = 62 -- Beschriftung der Hauptwerte
	-- Der Gehaeusering umschliesst jetzt BEIDES: Zifferblatt und Energiebogen. Vorher sass
	-- er zwischen ihnen, und der Bogen lag frei ausserhalb -- damit gehoerte er optisch
	-- nicht mehr zum Geraet. Ein Ring, der aussen herumlaeuft, macht aus zwei Anzeigen
	-- eine.
	local BEZEL_INNER = FACE_RADIUS -- der Ring sitzt genau auf der Kante des Blattes
	local BEZEL_THICK = 11
	local BEZEL_OUTER = BEZEL_INNER + BEZEL_THICK
	local NEEDLE_LENGTH = 84
	-- Der Energiebogen liegt zwischen Zifferblatt und Gehaeusering -- INNERHALB des Rings,
	-- nicht ausserhalb. Frei ausserhalb wirkte er losgeloest, wie ein zweites Geraet, das
	-- zufaellig dieselbe Kruemmung hat.
	local ENERGY_ARC_INNER = 106
	local ENERGY_ARC_THICK = 12

	-- Die Zonenfarben. Gedeckter als vorher: ein Messgeraet leuchtet nicht, es zeigt an.
	-- Die Grenzen 30/60/85 sind fest (siehe HeatHandler), die letzte haengt am Talent.
	local ZONE_CALM = Color3.fromRGB(58, 92, 130)
	local ZONE_AGGRESSIVE = Color3.fromRGB(186, 152, 46)
	local ZONE_ENRAGED = Color3.fromRGB(196, 104, 26)
	local ZONE_BERSERK = Color3.fromRGB(198, 42, 34)
	local ZONE_MELTDOWN = Color3.fromRGB(158, 34, 178)

	-- Hilfsfunktion: legt einen Dreh-Anker auf den Drehpunkt und gibt ihn zurueck.
	local function makePivot(name, angle, zIndex)
		local pivot = Instance.new("Frame")
		pivot.Name = name
		pivot.AnchorPoint = Vector2.new(0.5, 0.5)
		pivot.Size = UDim2.new(0, 1, 0, 1)
		pivot.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
		pivot.Rotation = angle
		pivot.BackgroundTransparency = 1
		pivot.ZIndex = zIndex
		pivot.Parent = heatFrame
		return pivot
	end

	-- Prozentwert -> Winkel. 0 liegt links (-90), GAUGE_MAX rechts (+90).
	local function percentToAngle(percent)
		return -90 + (math.clamp(percent, 0, GAUGE_MAX) / GAUGE_MAX) * 180
	end

	-- ===== Gehaeuse: ein Sockel, kein Hintergrund =====
	--
	-- Erster Versuch war eine grosse Platte hinter dem ganzen Instrument. Das sah falsch
	-- aus: ein Tacho braucht keine Rueckwand, er braucht etwas, WORAUF er sitzt. Eine
	-- Flaeche hinter allem macht aus dem Geraet ein Schild.
	--
	-- Jetzt ein flacher Sockel an der Unterkante. Er beginnt ein Stueck oberhalb der
	-- Drehachse -- so schneidet die flache Seite der Scheibe in ihn hinein, statt nur
	-- daraufzustehen -- und laeuft nach unten bis an den Bildschirmrand. Dass er dort
	-- ansetzt, ist der Punkt: ein Sockel, der in der Luft endet, ist kein Sockel.
	local SOCKEL_UEBERLAPP = 16 -- so weit reicht er ueber die Drehachse hinauf
	local SOCKEL_UEBERSTAND = 24 -- so weit steht heatFrame ueber dem unteren Bildrand

	local gehaeuse = Instance.new("Frame")
	gehaeuse.Name = "GaugeHousing"
	gehaeuse.Size = UDim2.new(1, 0, 0, SOCKEL_UEBERLAPP + SOCKEL_UEBERSTAND)
	gehaeuse.Position = UDim2.new(0, 0, 0, GAUGE_CENTER.Y - SOCKEL_UEBERLAPP)
	gehaeuse.ZIndex = 5
	gehaeuse.Parent = heatFrame
	HudChrome.Panel(gehaeuse, {
		radius = HudChrome.Radius.Small,
		fill = HudChrome.Color.PanelRaised,
		transparency = 0,
	})

	-- Derselbe Lichtverlauf wie am Ring: oben hell, unten dunkel. Ohne ihn war der Sockel
	-- eine flache Flaeche in einem Grauton und der Ring ein verlaufendes -- zwei
	-- verschiedene Schwarztoene, die an ihrer Nahtstelle aufeinandertrafen. Ein Werkstueck
	-- hat eine Lichtquelle, nicht zwei.
	local sockelVerlauf = Instance.new("UIGradient")
	sockelVerlauf.Rotation = 90
	sockelVerlauf.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HudChrome.Color.PanelRaised),
		ColorSequenceKeypoint.new(1, HudChrome.Color.Panel),
	})
	sockelVerlauf.Parent = gehaeuse

	-- Eine helle Linie auf der Oberkante: dort faellt das Licht auf eine waagerechte
	-- Metallkante. Ohne sie ist der Sockel ein graues Rechteck.
	local sockelKante = Instance.new("Frame")
	sockelKante.Name = "HousingEdge"
	sockelKante.Size = UDim2.new(1, 0, 0, 1)
	sockelKante.Position = UDim2.new(0, 0, 0, 0)
	sockelKante.BackgroundColor3 = HudChrome.Color.BorderBright
	sockelKante.BackgroundTransparency = 0.45
	sockelKante.BorderSizePixel = 0
	sockelKante.ZIndex = 6
	sockelKante.Parent = gehaeuse

	-- Die Nieten sitzen im Streifen UNTERHALB der Drehachse. Oberhalb reicht der Ring jetzt
	-- fast bis an die Kante des Sockels -- dort waeren sie verdeckt. Unterhalb ist die
	-- ganze Breite frei, und genau dort gehoeren sie hin: es ist die Stelle, an der das
	-- Instrument auf seiner Grundplatte verschraubt ist.
	for _, stelle in ipairs({
		{ x = 16, y = SOCKEL_UEBERLAPP + 12 },
		{ x = 64, y = SOCKEL_UEBERLAPP + 12 },
		{ x = -64, y = SOCKEL_UEBERLAPP + 12 },
		{ x = -16, y = SOCKEL_UEBERLAPP + 12 },
	}) do
		local niete = Instance.new("Frame")
		niete.Name = "HousingRivet"
		niete.AnchorPoint = Vector2.new(0.5, 0.5)
		niete.Size = UDim2.new(0, 6, 0, 6)
		niete.Position = UDim2.new(stelle.x > 0 and 0 or 1, stelle.x, 0, stelle.y)
		niete.BackgroundColor3 = HudChrome.Color.PanelSunken
		niete.BorderSizePixel = 0
		niete.ZIndex = 6
		niete.Parent = gehaeuse

		local nieteEcke = Instance.new("UICorner")
		nieteEcke.CornerRadius = UDim.new(0.5, 0)
		nieteEcke.Parent = niete

		local nieteRand = Instance.new("UIStroke")
		nieteRand.Thickness = 1
		nieteRand.Color = HudChrome.Color.BorderBright
		nieteRand.Transparency = 0.4
		nieteRand.Parent = niete
	end

	-- ===== Zifferblatt =====
	-- Roblox kennt keine Halbkreis-Form. Ein VOLLER Kreis (UICorner mit halbem Radius) sitzt
	-- in einem nur halb so hohen Container mit ClipsDescendants -- sichtbar bleibt die obere
	-- Haelfte. Das Kind ist dabei NICHT gedreht; auf gedrehte Kinder waere kein Verlass.
	local discClip = Instance.new("Frame")
	discClip.Name = "GaugeDiscClip"
	discClip.AnchorPoint = Vector2.new(0.5, 1)
	discClip.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
	discClip.Size = UDim2.new(0, FACE_RADIUS * 2, 0, FACE_RADIUS)
	discClip.BackgroundTransparency = 1
	discClip.ClipsDescendants = true
	discClip.ZIndex = 7
	discClip.Parent = heatFrame

	local gaugeDisc = Instance.new("Frame")
	gaugeDisc.Name = "GaugeDisc"
	gaugeDisc.AnchorPoint = Vector2.new(0.5, 0.5)
	gaugeDisc.Position = UDim2.new(0.5, 0, 1, 0)
	gaugeDisc.Size = UDim2.new(0, FACE_RADIUS * 2, 0, FACE_RADIUS * 2)
	gaugeDisc.BackgroundColor3 = HudChrome.Color.PanelSunken
	gaugeDisc.BackgroundTransparency = 0.08
	gaugeDisc.BorderSizePixel = 0
	gaugeDisc.ZIndex = 7
	gaugeDisc.Parent = discClip

	local gaugeDiscCorner = Instance.new("UICorner")
	gaugeDiscCorner.CornerRadius = UDim.new(0.5, 0)
	gaugeDiscCorner.Parent = gaugeDisc

	-- ===== Gehaeusering =====
	-- Derselbe Kniff, aber der Ring ist der STRICH eines Kreises statt seiner Flaeche: ein
	-- UIStroke der Dicke BEZEL_THICK auf einem durchsichtigen Kreis. Ein Ring aus gedrehten
	-- Segmenten haette hundert Rahmen gekostet und an den Fugen geflimmert.
	local bezelClip = Instance.new("Frame")
	bezelClip.Name = "GaugeBezelClip"
	bezelClip.AnchorPoint = Vector2.new(0.5, 1)
	bezelClip.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
	bezelClip.Size = UDim2.new(0, BEZEL_OUTER * 2, 0, BEZEL_OUTER)
	bezelClip.BackgroundTransparency = 1
	bezelClip.ClipsDescendants = true
	bezelClip.ZIndex = 6
	bezelClip.Parent = heatFrame

	local bezelCircle = Instance.new("Frame")
	bezelCircle.Name = "GaugeBezel"
	bezelCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	bezelCircle.Position = UDim2.new(0.5, 0, 1, 0)
	-- Der Kreis ist genau so gross wie die INNENkante des Rings. Ein UIStroke im Modus
	-- "Border" zeichnet nach AUSSEN, nicht mittig auf der Kante -- der Ring liegt damit von
	-- BEZEL_INNER bis BEZEL_OUTER, so wie gerechnet.
	bezelCircle.Size = UDim2.new(0, BEZEL_INNER * 2, 0, BEZEL_INNER * 2)
	bezelCircle.BackgroundTransparency = 1
	bezelCircle.BorderSizePixel = 0
	bezelCircle.ZIndex = 6
	bezelCircle.Parent = bezelClip

	local bezelCorner = Instance.new("UICorner")
	bezelCorner.CornerRadius = UDim.new(0.5, 0)
	bezelCorner.Parent = bezelCircle

	local bezelStroke = Instance.new("UIStroke")
	bezelStroke.Name = "BezelStroke"
	bezelStroke.Thickness = BEZEL_THICK
	bezelStroke.Color = HudChrome.Color.PanelRaised
	bezelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bezelStroke.Parent = bezelCircle

	-- Ein Lichtkante-Verlauf ueber den Ring: oben heller, unten dunkler. Das ist der
	-- Unterschied zwischen einem gezeichneten Kreis und einem Ring aus Metall.
	local bezelGradient = Instance.new("UIGradient")
	bezelGradient.Rotation = 90
	-- Der sichtbare Teil des Rings ist seine OBERE Haelfte, also der Verlauf von 0 bis 0.5.
	-- Der Wendepunkt liegt deshalb genau auf 0.5: dort, an der Waagerechten, trifft der Ring
	-- auf den Sockel, und beide haben an der Nahtstelle denselben Ton.
	bezelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HudChrome.Color.BorderBright),
		ColorSequenceKeypoint.new(0.5, HudChrome.Color.PanelRaised),
		ColorSequenceKeypoint.new(1, HudChrome.Color.Panel),
	})
	bezelGradient.Parent = bezelStroke

	-- Schrauben im Gehaeusering. Vier, dezent, an Stellen, an denen sie ein Geraet wirklich
	-- haette -- sie sagen "gebaut" statt "gezeichnet".
	for _, winkel in ipairs({ -74, -26, 26, 74 }) do
		local rad = math.rad(winkel)
		local bolt = Instance.new("Frame")
		bolt.Name = "BezelBolt"
		bolt.AnchorPoint = Vector2.new(0.5, 0.5)
		bolt.Size = UDim2.new(0, 5, 0, 5)
		bolt.Position = UDim2.new(
			0,
			GAUGE_CENTER.X + math.sin(rad) * (BEZEL_INNER + BEZEL_THICK / 2),
			0,
			GAUGE_CENTER.Y - math.cos(rad) * (BEZEL_INNER + BEZEL_THICK / 2)
		)
		bolt.BackgroundColor3 = HudChrome.Color.PanelSunken
		bolt.BorderSizePixel = 0
		bolt.ZIndex = 7
		bolt.Parent = heatFrame

		local boltCorner = Instance.new("UICorner")
		boltCorner.CornerRadius = UDim.new(0.5, 0)
		boltCorner.Parent = bolt

		local boltStroke = Instance.new("UIStroke")
		boltStroke.Thickness = 1
		boltStroke.Color = HudChrome.Color.BorderDim
		boltStroke.Parent = bolt
	end

	-- ===== Farbband =====
	-- Schmal und am Rand. Die Segmente ueberlappen sich um ein Grad, sonst stehen bei
	-- krummen Winkeln Haarfugen zwischen ihnen.
	local SECTOR_COUNT = 90
	local sectorWedges = {}
	for i = 0, SECTOR_COUNT - 1 do
		local percent = (i / (SECTOR_COUNT - 1)) * GAUGE_MAX
		local pivot = makePivot("SectorPivot" .. i, percentToAngle(percent), 8)

		local wedge = Instance.new("Frame")
		wedge.Name = "Wedge"
		wedge.AnchorPoint = Vector2.new(0.5, 1)
		wedge.Size = UDim2.new(0, 8, 0, BAND_OUTER - BAND_INNER)
		wedge.Position = UDim2.new(0.5, 0, 0, -BAND_INNER)
		wedge.BorderSizePixel = 0
		wedge.ZIndex = 8
		wedge.Parent = pivot

		-- Die Farbe setzt der Heartbeat: die Berserker/Meltdown-Grenze haengt am Talent
		-- (EffectiveMeltdownThreshold) und kann sich waehrend des Spiels verschieben.
		table.insert(sectorWedges, { frame = wedge, percent = percent })
	end

	-- ===== Teilstriche alle 5, Hauptstriche an den Zonengrenzen =====
	--
	-- Beschriftet werden 0 / 30 / 60 / 85 / 100 / 110. Im Grilling hatte ich 25 statt 30
	-- vorgeschlagen -- im Code liegt die Grenze zu "Aggressive" aber bei 30, und eine Skala,
	-- die andere Zahlen anschreibt als die, an denen etwas passiert, ist schlimmer als gar
	-- keine.
	local MAJOR_VALUES = { 0, 30, 60, 85, 100, 110 }
	local majorLookup = {}
	for _, value in ipairs(MAJOR_VALUES) do
		majorLookup[value] = true
	end

	for value = 0, GAUGE_MAX, 5 do
		local isMajor = majorLookup[value] or false
		local pivot = makePivot("TickPivot" .. value, percentToAngle(value), 9)

		local tick = Instance.new("Frame")
		tick.Name = "Tick"
		tick.AnchorPoint = Vector2.new(0.5, 1)
		tick.Size = UDim2.new(0, isMajor and 2 or 1, 0, isMajor and TICK_MAJOR or TICK_MINOR)
		tick.Position = UDim2.new(0.5, 0, 0, -(TICK_OUTER - (isMajor and TICK_MAJOR or TICK_MINOR)))
		tick.BackgroundColor3 = isMajor and HudChrome.Color.BorderBright or HudChrome.Color.Border
		tick.BorderSizePixel = 0
		tick.ZIndex = 9
		tick.Parent = pivot
	end

	-- Auch 100 und 110 bekommen einen Strich, aber 85 und 100 liegen nur 15 auseinander --
	-- die Beschriftung wandert deshalb nach innen, wo mehr Platz ist.
	for _, value in ipairs(MAJOR_VALUES) do
		local rad = math.rad(percentToAngle(value))
		local label = Instance.new("TextLabel")
		label.Name = "TickLabel" .. value
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.new(0, 30, 0, 14)
		label.Position = UDim2.new(
			0,
			GAUGE_CENTER.X + math.sin(rad) * LABEL_RADIUS,
			0,
			GAUGE_CENTER.Y - math.cos(rad) * LABEL_RADIUS
		)
		label.BackgroundTransparency = 1
		label.Text = tostring(value)
		label.ZIndex = 9
		label.Parent = heatFrame
		HudChrome.Number(label, 11)
		label.TextColor3 = HudChrome.Color.TextSecondary
	end

	-- ===== Rote Marke an der Meltdown-Schwelle =====
	-- Sie ist beweglich, weil die Schwelle am Talent haengt. Genau deshalb gehoert sie aufs
	-- Blatt: sie zeigt, dass ein Talent etwas bewirkt hat, ohne dass man es nachrechnen muss.
	local redlinePivot = makePivot("RedlinePivot", percentToAngle(100), 10)

	local redlineMark = Instance.new("Frame")
	redlineMark.Name = "RedlineMark"
	redlineMark.AnchorPoint = Vector2.new(0.5, 1)
	redlineMark.Size = UDim2.new(0, 3, 0, BAND_OUTER - BAND_INNER + 8)
	redlineMark.Position = UDim2.new(0.5, 0, 0, -(BAND_INNER - 4))
	redlineMark.BackgroundColor3 = Color3.fromRGB(255, 236, 236)
	redlineMark.BorderSizePixel = 0
	redlineMark.ZIndex = 10
	redlineMark.Parent = redlinePivot

	-- ===== Schriftzug auf dem Blatt =====
	-- Der Name des Herstellers, wie er auf einem Zifferblatt steht. Ohne kuenstliche
	-- Sperrung: ein Name ist eine Signatur, keine technische Beschriftung.
	local wordmark = Instance.new("TextLabel")
	wordmark.Name = "GaugeWordmark"
	wordmark.AnchorPoint = Vector2.new(0.5, 1)
	wordmark.Size = UDim2.new(0, 200, 0, 24)
	wordmark.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y - 13)
	wordmark.BackgroundTransparency = 1
	wordmark.Text = "Amaux Bozé"
	wordmark.ZIndex = 9
	wordmark.Parent = heatFrame
	-- Doppelt so gross wie vorher und eine Stufe heller. Bei 9 Punkt in TextDim war der
	-- Name da, aber nicht lesbar -- er sah aus wie eine Verschmutzung auf dem Blatt.
	--
	-- Groesser geht nicht ohne Umbau: darueber beginnt bei 42 Pixeln die Ablesung, und die
	-- Zahlen der Skala liegen auf Radius 62. Der freie Streifen ueber der Nabe ist genau
	-- so hoch, wie er ist.
	HudChrome.Label(wordmark, 18)
	wordmark.TextColor3 = HudChrome.Color.TextSecondary

	-- ===== Nadel =====
	local needlePivot = Instance.new("Frame")
	needlePivot.Name = "NeedlePivot"
	needlePivot.AnchorPoint = Vector2.new(0.5, 0.5)
	needlePivot.Size = UDim2.new(0, 1, 0, 1)
	needlePivot.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
	needlePivot.BackgroundTransparency = 1
	needlePivot.ZIndex = 11
	needlePivot.Parent = heatFrame

	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 1)
	needle.Size = UDim2.new(0, 4, 0, NEEDLE_LENGTH)
	needle.Position = UDim2.new(0.5, 0, 0, 0)
	needle.BackgroundColor3 = HudChrome.Color.TextPrimary
	needle.BorderSizePixel = 0
	needle.ZIndex = 11
	needle.Parent = needlePivot

	-- Gegengewicht hinter dem Drehpunkt -- der kurze Stummel, den jede echte Zeigernadel auf
	-- der anderen Seite der Achse hat. Kostet einen Rahmen und macht den Unterschied
	-- zwischen "Strich auf einer Scheibe" und "Instrument".
	local needleTail = Instance.new("Frame")
	needleTail.Name = "NeedleTail"
	needleTail.AnchorPoint = Vector2.new(0.5, 0)
	needleTail.Size = UDim2.new(0, 6, 0, 16)
	needleTail.Position = UDim2.new(0.5, 0, 0, 0)
	needleTail.BackgroundColor3 = HudChrome.Color.BorderBright
	needleTail.BorderSizePixel = 0
	needleTail.ZIndex = 11
	needleTail.Parent = needlePivot

	-- Nabe: aussen Stahl, innen ein farbiger Punkt. Die Stufe traegt damit der Punkt -- das
	-- Chrome drumherum bleibt farblos, so wie ueberall sonst im HUD.
	local needleHub = Instance.new("Frame")
	needleHub.Name = "NeedleHub"
	needleHub.AnchorPoint = Vector2.new(0.5, 0.5)
	needleHub.Size = UDim2.new(0, 22, 0, 22)
	needleHub.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y)
	needleHub.BackgroundColor3 = HudChrome.Color.PanelRaised
	needleHub.BorderSizePixel = 0
	needleHub.ZIndex = 12
	needleHub.Parent = heatFrame

	local hubCorner = Instance.new("UICorner")
	hubCorner.CornerRadius = UDim.new(0.5, 0)
	hubCorner.Parent = needleHub

	local hubStroke = Instance.new("UIStroke")
	hubStroke.Thickness = 1
	hubStroke.Color = HudChrome.Color.BorderBright
	hubStroke.Parent = needleHub

	local hubDot = Instance.new("Frame")
	hubDot.Name = "HubDot"
	hubDot.AnchorPoint = Vector2.new(0.5, 0.5)
	hubDot.Size = UDim2.new(0, 10, 0, 10)
	hubDot.Position = UDim2.new(0.5, 0, 0.5, 0)
	hubDot.BackgroundColor3 = ZONE_CALM
	hubDot.BorderSizePixel = 0
	hubDot.ZIndex = 13
	hubDot.Parent = needleHub

	local hubDotCorner = Instance.new("UICorner")
	hubDotCorner.CornerRadius = UDim.new(0.5, 0)
	hubDotCorner.Parent = hubDot

	-- ===== Ablesung im Blatt =====
	-- ZIndex 9: die Nadel wandert sichtbar DARUEBER, wie bei einem echten Tacho.
	local heatLabel = Instance.new("TextLabel")
	heatLabel.Name = "HeatLabel"
	heatLabel.AnchorPoint = Vector2.new(0.5, 1)
	heatLabel.Size = UDim2.new(0, 140, 0, 32)
	heatLabel.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y - 42)
	heatLabel.BackgroundTransparency = 1
	heatLabel.ZIndex = 9
	heatLabel.Text = "0"
	heatLabel.Parent = heatFrame
	HudChrome.NumberBold(heatLabel, 30)

	-- ===== Stufe gross, Bonus klein =====
	-- Die Stufe ist die Aussage, der Bonus ihre Begruendung. Vorher stand dort unveraenderlich
	-- "BERSERKER" -- ein Wort, das nur beschrieb, welches Geraet man ansieht, und nie, was es
	-- gerade anzeigt.
	-- Beide sitzen jetzt dicht ueber dem Energiebogen statt weit oben im Rahmen. Vorher
	-- klebte die Stufe an der Oberkante, mit einem Loch von zwanzig Pixeln zum Instrument
	-- darunter -- zwei Dinge, die zusammengehoeren, standen getrennt.
	--
	-- Und beide sind groesser: die Stufe ist die wichtigste Aussage des Tachos, sie war
	-- kleiner gesetzt als der Stadtname oben rechts.
	local BOGEN_OBERKANTE = GAUGE_CENTER.Y - BEZEL_OUTER

	local stageLabel = Instance.new("TextLabel")
	stageLabel.Name = "HeatStageLabel"
	stageLabel.Size = UDim2.new(1, -12, 0, 30)
	stageLabel.Position = UDim2.new(0, 6, 0, BOGEN_OBERKANTE - 54)
	stageLabel.BackgroundTransparency = 1
	stageLabel.ZIndex = 12
	stageLabel.Text = "CALM"
	stageLabel.Parent = heatFrame
	HudChrome.Label(stageLabel, 26)

	local heatBonusLabel = Instance.new("TextLabel")
	heatBonusLabel.Name = "HeatBonusLabel"
	heatBonusLabel.Size = UDim2.new(1, -12, 0, 20)
	heatBonusLabel.Position = UDim2.new(0, 6, 0, BOGEN_OBERKANTE - 24)
	heatBonusLabel.BackgroundTransparency = 1
	heatBonusLabel.ZIndex = 12
	heatBonusLabel.Text = ""
	heatBonusLabel.Parent = heatFrame
	HudChrome.Number(heatBonusLabel, 15)
	heatBonusLabel.TextColor3 = HudChrome.Color.TextSecondary

	-- Rauch-Glow fuer Meltdown -- sitzt ueber dem Zifferblatt.
	local smokeEmitter = Instance.new("ImageLabel")
	smokeEmitter.Name = "SmokeGlow"
	smokeEmitter.AnchorPoint = Vector2.new(0.5, 1)
	smokeEmitter.Size = UDim2.new(0, 140, 0, 140)
	smokeEmitter.Position = UDim2.new(0, GAUGE_CENTER.X, 0, GAUGE_CENTER.Y - FACE_RADIUS + 16)
	smokeEmitter.BackgroundTransparency = 1
	smokeEmitter.Image = "rbxasset://textures/particles/smoke_main.dds"
	smokeEmitter.ImageColor3 = Color3.fromRGB(60, 30, 70)
	smokeEmitter.ImageTransparency = 1
	smokeEmitter.ZIndex = 13
	smokeEmitter.Parent = heatFrame

	-- Kein manueller Berserk-Knopf -- er aktiviert sich serverseitig, sobald die Schwelle
	-- erreicht ist (siehe HeatHandler.lua).

	local HEAT_STAGE_NAMES = {
		Calm = "CALM",
		Aggressive = "AGGRESSIVE",
		Enraged = "ENRAGED",
		Berserk = "BERSERK",
		Meltdown = "MELTDOWN",
	}

	-- Die Emoji sind raus. Sie zeichnet das Betriebssystem in seinem eigenen Stil, und auf
	-- einem Messgeraet steht keine Bildsprache -- dort stehen Werte.
	local HEAT_STAGE_BONUS_TEXT = {
		Calm = "NO BONUS",
		Aggressive = "DMG +10%",
		Enraged = "DMG +30%   SPD +10%",
		Berserk = "DMG +60%   SPD +20%",
		Meltdown = "DMG +30%   SPD -75%",
	}

	local HEAT_STAGE_COLORS = {
		Calm = ZONE_CALM,
		Aggressive = ZONE_AGGRESSIVE,
		Enraged = ZONE_ENRAGED,
		Berserk = ZONE_BERSERK,
		Meltdown = ZONE_MELTDOWN,
	}

	-- ===== Special-Energy-Bogen =====
	-- Duenner Ring knapp AUSSERHALB des Gehaeuserings, in Cyan -- der Farbe, die im ganzen
	-- HUD allein der Special Energy gehoert. Er ueberdeckt den Tacho nicht und braucht kaum
	-- zusaetzliche Hoehe, weil er derselben Kontur folgt.
	-- Sechzig feine Sektoren, nicht vierundzwanzig breite.
	--
	-- Die Zahl folgt aus dem Spiel, nicht aus der Optik: ein Schlag gibt 1 Energie von 100.
	-- Bei vierundzwanzig Sektoren braucht es vier Schlaege, bis sich ueberhaupt etwas
	-- ruehrt -- der Bogen stand dann die meiste Zeit still, und das Aufblitzen beim Laden
	-- traf oft gar kein Segment. Bei sechzig ruecken zwei Schlaege ein Segment weiter, und
	-- man sieht beim Kaempfen, dass man vorankommt.
	--
	-- Der Abstand zwischen zwei Mitten betraegt am Innenrand 6.3 Pixel; bei 5 Pixeln
	-- Breite bleiben 1.3 Pixel Luft. Das ist wenig, aber es ist genau das Mass, das vorher
	-- als "klar aus Sektoren bestehend" gelesen wurde. Mehr Luft gaebe es nur mit weniger
	-- Sektoren oder groesserem Radius -- und der Radius ist durch die Angriffsknoepfe
	-- daneben gedeckelt.
	local ENERGY_ARC_SECTOR_COUNT = 60
	local ENERGY_ARC_SEGMENT_BREITE = 5
	local ENERGY_ARC_COLOR = HudChrome.Color.Accent
	local ENERGY_ARC_COLOR_DIM = Color3.fromRGB(28, 44, 54)

	local specialEnergyMaxValue = ReplicatedStorage:FindFirstChild("SpecialEnergyMax")

	local energyArcWedges = {}
	for i = 0, ENERGY_ARC_SECTOR_COUNT - 1 do
		local percent = (i / (ENERGY_ARC_SECTOR_COUNT - 1)) * 100
		-- ZIndex 8, nicht 6: das Zifferblatt liegt auf 7 und reicht seit dem Umbau bis an
		-- den Ring (Radius 120). Der Bogen liegt bei 106 bis 118 also MITTEN darauf und
		-- verschwand dahinter. Solange das Blatt nur bis 104 ging und der Bogen aussen
		-- lag, spielte die Reihenfolge keine Rolle -- deshalb fiel es erst jetzt auf.
		local pivot = makePivot("EnergyArcPivot" .. i, -90 + (percent / 100) * 180, 8)

		local wedge = Instance.new("Frame")
		wedge.Name = "EnergyWedge"
		wedge.AnchorPoint = Vector2.new(0.5, 1)
		wedge.Size = UDim2.new(0, ENERGY_ARC_SEGMENT_BREITE, 0, ENERGY_ARC_THICK)
		wedge.Position = UDim2.new(0.5, 0, 0, -ENERGY_ARC_INNER)
		wedge.BackgroundColor3 = ENERGY_ARC_COLOR_DIM
		wedge.BorderSizePixel = 0
		wedge.ZIndex = 8
		wedge.Parent = pivot

		table.insert(energyArcWedges, { frame = wedge, percent = percent, flashUntil = 0 })
	end


	-- Alles, was die Schleife weiter unten braucht. Der Rest bleibt im Block und gibt
	-- seinen Platz frei.
	tacho.max = GAUGE_MAX
	tacho.percentToAngle = percentToAngle
	tacho.sectorWedges = sectorWedges
	tacho.energyArcWedges = energyArcWedges
	tacho.needlePivot = needlePivot
	tacho.redlinePivot = redlinePivot
	tacho.bezelStroke = bezelStroke
	tacho.hubDot = hubDot
	tacho.heatLabel = heatLabel
	tacho.stageLabel = stageLabel
	tacho.bonusLabel = heatBonusLabel
	tacho.smoke = smokeEmitter
	tacho.specialEnergyMax = specialEnergyMaxValue
	tacho.zone = {
		calm = ZONE_CALM,
		aggressive = ZONE_AGGRESSIVE,
		enraged = ZONE_ENRAGED,
		berserk = ZONE_BERSERK,
		meltdown = ZONE_MELTDOWN,
	}
	tacho.stageNames = HEAT_STAGE_NAMES
	tacho.stageBonus = HEAT_STAGE_BONUS_TEXT
	tacho.stageColors = HEAT_STAGE_COLORS
	tacho.energyColor = ENERGY_ARC_COLOR
	tacho.energyColorDim = ENERGY_ARC_COLOR_DIM
end

local lastHeatValue = nil -- merkt sich den letzten Wert, um bei ECHTEM Anstieg (nicht bei jeder Änderung, z.B. Abkühlung) aufzuleuchten
local lastEnergyPercent = nil -- gleiches Prinzip für den Special-Energy-Arc
local lastNeedleTargetRotation = nil -- letztes Rotations-Ziel der Nadel, um Tweens nicht bei jedem Heartbeat neu zu starten
local currentNeedleTween = nil -- aktuell laufender Nadel-Tween (falls vorhanden), zum sauberen Abbrechen bei neuem Ziel
local lastStageForShake = nil

RunService.Heartbeat:Connect(function()
	-- HINWEIS: Frühere Ausblendung des Tachos während Bein-Training wurde entfernt --
	-- der volle Berserker-Tacho (Scheibe, Nadel, Sektoren, Energy-Arc) soll jetzt sowohl
	-- bei Bein- als auch Körper-Training vollständig sichtbar bleiben (als Schwierigkeits-
	-- und Lern-Element).

	local heat = player:GetAttribute("Heat") or 0
	local berserkActive = player:GetAttribute("BerserkActive")
	local effectiveMeltdownThreshold = player:GetAttribute("EffectiveMeltdownThreshold") or 100
	local stage
	if heat >= effectiveMeltdownThreshold then
		stage = "Meltdown"
	elseif heat >= 85 then
		stage = berserkActive and "Berserk" or "Enraged"
	elseif heat >= 60 then
		stage = "Enraged"
	elseif heat >= 30 then
		stage = "Aggressive"
	else
		stage = "Calm"
	end

	local clampedHeat = math.clamp(heat, 0, tacho.max)
	local isAtMaxHeat = heat >= tacho.max
	-- Bei absolutem Maximum (110%) vibriert der Zeiger leicht um seine Zielposition,
	-- statt einfach nur still am Anschlag zu stehen -- macht "am Limit" spürbar.
	local vibrationOffset = isAtMaxHeat and (math.random() - 0.5) * 4 or 0
	local targetRotation = -90 + (clampedHeat / tacho.max) * 180 + vibrationOffset

	-- Wedge-Farben laufend aktualisieren -- Calm/Aggressive/Enraged-Grenzen (30/60/85)
	-- bleiben fix, die Berserker/Meltdown-Grenze nutzt aber effectiveMeltdownThreshold
	-- (talent-abhängig, siehe HeatHandler.lua), statt fest bei 100 zu bleiben.
	for _, wedgeInfo in ipairs(tacho.sectorWedges) do
		local wedgePercent = wedgeInfo.percent
		if wedgePercent < 30 then
			wedgeInfo.frame.BackgroundColor3 = tacho.zone.calm
		elseif wedgePercent < 60 then
			wedgeInfo.frame.BackgroundColor3 = tacho.zone.aggressive
		elseif wedgePercent < 85 then
			wedgeInfo.frame.BackgroundColor3 = tacho.zone.enraged
		elseif wedgePercent < effectiveMeltdownThreshold then
			wedgeInfo.frame.BackgroundColor3 = tacho.zone.berserk
		else
			wedgeInfo.frame.BackgroundColor3 = tacho.zone.meltdown
		end
	end

	-- Die rote Marke wandert auf die aktuelle Schwelle. Sie steht nicht fest bei 100:
	-- das Talent "Meltdown Mastery" verschiebt sie, und das soll man am Geraet sehen.
	tacho.redlinePivot.Rotation = tacho.percentToAngle(effectiveMeltdownThreshold)

	-- Nadel bewegt sich mit Schwung (leichtes Überschwingen) zum neuen Wert, statt
	-- sofort zu springen -- neuer Tween wird nur gestartet, wenn sich das Ziel
	-- tatsächlich ändert (nicht bei jedem Heartbeat neu, sonst käme die Nadel nie zur Ruhe).
	if lastNeedleTargetRotation == nil or math.abs(targetRotation - lastNeedleTargetRotation) > 0.05 then
		lastNeedleTargetRotation = targetRotation
		if currentNeedleTween then
			currentNeedleTween:Cancel()
		end
		currentNeedleTween = TweenService:Create(
			tacho.needlePivot,
			TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Rotation = targetRotation }
		)
		currentNeedleTween:Play()
	end
	tacho.heatLabel.Text = math.floor(heat) .. "%"
	tacho.bonusLabel.Text = tacho.stageBonus[stage]

	-- Stufe gross, Bonus klein: die Stufe ist die Aussage, der Bonus ihre Begruendung.
	local stageColor = tacho.stageColors[stage]
	tacho.stageLabel.Text = tacho.stageNames[stage]
	tacho.stageLabel.TextColor3 = stageColor
	tacho.hubDot.BackgroundColor3 = stageColor
	-- flashElement merkt sich die Ruhefarbe einmalig -- die des Punktes wechselt aber mit
	-- der Stufe. Ohne diese Zeile kehrte er nach dem ersten Blitz fuer immer ins Blau der
	-- ersten Stufe zurueck. (Derselbe Fall wie beim Lebensbalken.)
	tacho.hubDot:SetAttribute("RestColor", stageColor)

	-- Aufleuchten bei ECHTEM Anstieg (z.B. durch einen Treffer) -- nicht bei Abkühlung
	-- oder unveränderten Werten.
	if lastHeatValue and heat > lastHeatValue then
		flashElement(tacho.hubDot, Color3.new(1, 1, 1))
		-- Der Gehaeusering leuchtet kurz mit. Vorher lag der Effekt auf heatFrame -- und
		-- der ist ein durchsichtiges Rechteck, das den ganzen Tacho umschliesst: der
		-- "Glow" war in Wahrheit ein aufblitzender Kasten um eine runde Anzeige.
		tacho.bezelStroke.Color = Color3.fromRGB(255, 214, 170)
		TweenService:Create(tacho.bezelStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Color = HudChrome.Color.PanelRaised,
		}):Play()
	end
	lastHeatValue = heat

	if stage == "Meltdown" then
		-- Meltdown: Leiste "raucht"/"explodiert" -- Rauch-Glow einblenden, Rahmen pulsiert
		-- zwischen Gold und knalligem Lila-Rot, leichtes Zittern der ganzen Leiste.
		tacho.smoke.ImageTransparency = 0.35 + math.sin(os.clock() * 6) * 0.15
		local smokePulse = 140 + math.sin(os.clock() * 4) * 16
		tacho.smoke.Size = UDim2.new(0, smokePulse, 0, smokePulse)

		local pulse = (math.sin(os.clock() * 6) + 1) / 2

		-- Meltdown-Sektor des Zifferblatts pulsiert zusätzlich mit -- verstärkt die
		-- Dringlichkeit genau dort, wo es zählt. Nutzt die dynamische Schwelle statt fest 97.
		for _, wedgeInfo in ipairs(tacho.sectorWedges) do
			if wedgeInfo.percent >= effectiveMeltdownThreshold then
				wedgeInfo.frame.BackgroundColor3 = tacho.zone.meltdown:Lerp(Color3.new(1, 1, 1), pulse * 0.5)
			end
		end

		local shakeX = (math.random() - 0.5) * 4
		local shakeY = (math.random() - 0.5) * 4
		heatFrame.Position = UDim2.new(0.5, shakeX, 1, -24 + shakeY)
	else
		tacho.smoke.ImageTransparency = 1
		if lastStageForShake == "Meltdown" then
			heatFrame.Position = UDim2.new(0.5, 0, 1, -24) -- Zittern zurücksetzen, sobald Meltdown endet
			-- Kein manueller Wedge-Reset mehr nötig -- die laufende Einfärbung weiter oben
			-- im Loop übernimmt das automatisch jeden Frame.
		end
	end
	lastStageForShake = stage

	-- Special-Energy-Arc: Segmente bis zum aktuellen Füllstand einfärben, Rest bleibt
	-- gedimmt. Neu geladene Segmente leuchten kurz hell auf (weisser Blitz), bevor sie
	-- zur normalen Energy-Farbe übergehen -- macht sichtbar, WANN und WIEVIEL gerade
	-- aufgeladen wurde.
	local specialEnergy = player:GetAttribute("SpecialEnergy") or 0
	local specialEnergyMax = (tacho.specialEnergyMax and tacho.specialEnergyMax.Value) or 100
	local energyPercent = math.clamp((specialEnergy / math.max(specialEnergyMax, 1)) * 100, 0, 100)

	if lastEnergyPercent and energyPercent > lastEnergyPercent then
		local flashUntil = os.clock() + 0.35
		for _, wedgeInfo in ipairs(tacho.energyArcWedges) do
			if wedgeInfo.percent > lastEnergyPercent and wedgeInfo.percent <= energyPercent then
				wedgeInfo.flashUntil = flashUntil
			end
		end
	end
	lastEnergyPercent = energyPercent

	local now = os.clock()
	for _, wedgeInfo in ipairs(tacho.energyArcWedges) do
		if now < wedgeInfo.flashUntil then
			wedgeInfo.frame.BackgroundColor3 = Color3.new(1, 1, 1)
		elseif wedgeInfo.percent <= energyPercent then
			wedgeInfo.frame.BackgroundColor3 = tacho.energyColor
		else
			wedgeInfo.frame.BackgroundColor3 = tacho.energyColorDim
		end
	end
end)

-- Meltdown-Explosion: kurzer roter Bildschirm-Flash + Kamerawackeln
local meltdownFlash = Instance.new("Frame")
meltdownFlash.Name = "MeltdownFlash"
meltdownFlash.Size = UDim2.new(1, 0, 1, 0)
meltdownFlash.BackgroundColor3 = Color3.fromRGB(255, 40, 20)
meltdownFlash.BackgroundTransparency = 1
meltdownFlash.ZIndex = 100
meltdownFlash.Parent = screenGui

MeltdownExplosionEvent.OnClientEvent:Connect(function()
	meltdownFlash.BackgroundTransparency = 0.6
	TweenService:Create(meltdownFlash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end)

-- ===== Die drei Kraftwerte als Roentgenscans =====
--
-- Statt Titel und Farbbalken bekommt jeder Wert ein SCANFENSTER: ein kleines Sichtfeld mit
-- Raster, Eckwinkeln und einer wandernden Abtastlinie, und darin die echten Gliedmassen der
-- eigenen Figur -- Arm, Bein, Rumpf -- in Neon, halb durchsichtig.
--
-- Die Teile werden aus dem laufenden Charakter GEKLONT, nicht aus einer Bibliothek geladen.
-- Damit zeigt der Scan immer genau die Figur, die man gerade traegt, samt Skin, und es
-- braucht kein einziges neues Modell. Stirbt oder wechselt die Figur, wird neu gescannt.
--
-- Die Farbe ist die des jeweiligen Wertes, nicht Cyan: Cyan gehoert im ganzen HUD allein
-- der Special Energy. So bleiben die drei ausserdem auf einen Blick auseinanderzuhalten.
-- Das Feld ist breiter als die uebrige rechte Spalte und deutlich hoeher. Das ist
-- Absicht: im Sanctuary IST das Training die Hauptsache, und es soll dort dasselbe Gewicht
-- haben wie sonst die Angriffsreihe unten. Ein Streifen am Rand machte eine Nebensache
-- daraus.
--
-- Die Scanfenster sind entsprechend gross -- bei 44 Pixeln war das Glied ein Farbfleck.
-- Erst ab dieser Groesse ist zu erkennen, WAS da gescannt wird.
local SPALTE_BREITE = 300
local SPALTE_X = -16
local SPALTE_RAND = 10
-- Direkt unter der Kopfleiste. Vorher stand hier 192 -- Platz fuer das Ortsfeld darueber.
-- Das faellt im Sanctuary jetzt weg (siehe CityAlertHudClient): es zeigte dort nur
-- "Sanctuary / 12:00" ohne Sterne, also einen leeren Kasten. Die 106 Pixel fehlten unten,
-- wo der Block sonst in die Angriffsknoepfe und das Weltevent-Feld lief.
local KRAFT_Y = 86
local KRAFT_ZEILE = 108
local SCAN_GROESSE = 100

-- Kameraabstand im Scanfenster: ein Faktor auf den Abstand, nicht auf die Groesse --
-- KLEINER heisst also NAEHER.
--
-- 1.5 rahmt nicht nur das Glied, sondern laesst den Koerper drumherum mit ins Bild. Genau
-- das soll man sehen: WO am Koerper der gescannte Teil sitzt. Ein Arm ohne Schulter ist
-- ein Gegenstand, ein Arm am Rumpf ist ein Arm.
local SCAN_ZOOM = 1.8

-- Alles, was nicht zum gescannten Bereich gehoert, steht in gedaempftem Grau da. Der
-- farbige Teil ist damit ohne Beschriftung erkennbar -- die Farbe sagt "das hier ist
-- gemeint", und der graue Rest gibt ihm seinen Ort.
local SCAN_GRAU = Color3.fromRGB(72, 78, 88)

-- Wie weit die Farbe des Wertes in Richtung Stahl gezogen wird.
--
-- Dichter UND weniger bunt sind zwei verschiedene Schrauben, und sie ziehen gegeneinander:
-- ein deckenderes Neonteil ist zwangslaeufig farbiger. Die Deckkraft steigt deshalb wie
-- gewuenscht, und die Saettigung faellt zum Ausgleich um die Haelfte. Was bleibt, ist die
-- Zuordnung -- man erkennt weiter, welcher Wert gemeint ist -- ohne das Grelle.
local SCAN_ENTSAETTIGUNG = 0.5

local statsRowFrame = Instance.new("Frame")
statsRowFrame.Name = "StatsRowFrame"
statsRowFrame.Size = UDim2.new(0, SPALTE_BREITE, 0, 34 + KRAFT_ZEILE * 3 - 8 + 12)
statsRowFrame.AnchorPoint = Vector2.new(1, 0)
statsRowFrame.Position = UDim2.new(1, SPALTE_X, 0, KRAFT_Y)
statsRowFrame.Parent = screenGui
HudChrome.Panel(statsRowFrame, { radius = HudChrome.Radius.Small })

-- Der Titel war vorher da, aber unsichtbar: er wurde gebaut und nie eingehaengt.
local statsPanelTitle = Instance.new("TextLabel")
statsPanelTitle.Name = "PanelTitle"
statsPanelTitle.Size = UDim2.new(0, 160, 0, 20)
statsPanelTitle.Position = UDim2.new(0, SPALTE_RAND, 0, 8)
statsPanelTitle.BackgroundTransparency = 1
statsPanelTitle.TextXAlignment = Enum.TextXAlignment.Left
statsPanelTitle.Text = "TRAINING"
statsPanelTitle.Parent = statsRowFrame
HudChrome.Label(statsPanelTitle, 16)
statsPanelTitle.TextColor3 = HudChrome.Color.TextSecondary

-- Der Abbruch-Knopf sitzt in der Kopfzeile dieses Feldes, nicht mehr in einem eigenen
-- Panel. Er war das Einzige, was jenes Panel noch beitrug: seine Fortschrittsleiste zeigte
-- denselben Wert wie die Zeile darueber, nur ein zweites Mal.
local leaveTrainingButton = Instance.new("TextButton")
leaveTrainingButton.Name = "LeaveTrainingButton"
leaveTrainingButton.Size = UDim2.new(0, 30, 0, 26)
leaveTrainingButton.AnchorPoint = Vector2.new(1, 0)
leaveTrainingButton.Position = UDim2.new(1, -SPALTE_RAND, 0, 6)
leaveTrainingButton.AutoButtonColor = false
leaveTrainingButton.Visible = false
leaveTrainingButton.Text = "X"
leaveTrainingButton.Parent = statsRowFrame
HudChrome.Panel(leaveTrainingButton, {
	radius = HudChrome.Radius.Small,
	fill = HudChrome.Color.PanelRaised,
	transparency = 0,
	border = HudChrome.Color.Danger,
})
HudChrome.Label(leaveTrainingButton, 15)
leaveTrainingButton.TextColor3 = HudChrome.Color.Danger

leaveTrainingButton.MouseButton1Click:Connect(function()
	StopTrainingEvent:FireServer()
end)

local STAT_COLOR_BY_TYPE = {
	Arm = Color3.fromRGB(220, 90, 220),
	Leg = Color3.fromRGB(255, 150, 60),
	Body = Color3.fromRGB(90, 220, 130),
}

-- Welche Teile zu welchem Wert gehoeren.
--
-- Es sind KANDIDATENLISTEN, keine Pflichtlisten: gefunden wird, was da ist, und aus allen
-- Treffern zusammen entsteht der Bereich. Fehlende Namen werden stillschweigend
-- uebergangen.
--
-- Das ist noetig, weil hier ZWEI Welten aufeinandertreffen, und das habe ich zweimal
-- falsch geraten, bevor ich im Bauplan nachgesehen habe:
--
--   Der Standard-Avatar ist nach R15 benannt: UpperTorso, RightUpperArm.
--   Das Kaiju-Modell aus der Werkstatt hat eine eigene ANATOMIE: UpperRibcage,
--   DorsalLumbarMass, RightBicepsMass, RightOuterQuadriceps.
--
-- Die anatomischen Namen stehen zuerst, weil sie dem Modell gehoeren, das hier tatsaechlich
-- gezeigt wird (KaijuEvolutionBlockout baut sie, der Storm Hunter uebernimmt sie). Die
-- R15-Namen bleiben als Rueckfall, falls doch einmal der Standard-Avatar gezeigt wird.
local SCAN_TEILE = {
	ArmPower = {
		"RightBicepsMass", "RightForearmMass", "RightPalm", "RightHandBack", "RightDeltoid",
		"RightUpperArm", "RightLowerArm", "RightHand",
	},
	LegPower = {
		"RightOuterQuadriceps", "RightCalfMass", "RightForefoot", "RightHeelMass",
		"RightUpperLeg", "RightLowerLeg", "RightFoot",
	},
	BodyPower = {
		"UpperRibcage", "UpperAbdomen", "LowerAbdomen", "DorsalLumbarMass", "SacralMass", "BellyShield",
		"Torso", "UpperTorso", "LowerTorso",
	},
}

local statBars = {} -- [key] = { label, fill, displayName, scanStroke, scanViewport, scanLine }
local lastStatValues = {}
local isAnimatingStat = {}
-- Vorwaertsdeklaration: wird von der Energie-Flug-Animation weiter oben im Skript
-- referenziert, aber erst weiter unten definiert.
local updateLevelBar
local advanceXPBar

local STAT_BAR_CONFIG = {
	{ key = "ArmPower", label = "ARM", short = "Arm", color = Color3.fromRGB(220, 90, 220), effect = "BASE DAMAGE" },
	{ key = "LegPower", label = "BEIN", short = "Bein", color = Color3.fromRGB(255, 150, 60), effect = "BONUS DAMAGE" },
	{ key = "BodyPower", label = "KOERPER", short = "Koerper", color = Color3.fromRGB(90, 220, 130), effect = "ENERGY EFFICIENCY" },
}

for index, config in ipairs(STAT_BAR_CONFIG) do
	local oben = 34 + (index - 1) * KRAFT_ZEILE
	local textX = SPALTE_RAND + SCAN_GROESSE + 8
	local textBreite = SPALTE_BREITE - textX - SPALTE_RAND

	-- --- Das Scanfenster ---
	local scanFrame = Instance.new("Frame")
	scanFrame.Name = config.key .. "Scan"
	scanFrame.Size = UDim2.new(0, SCAN_GROESSE, 0, SCAN_GROESSE)
	scanFrame.Position = UDim2.new(0, SPALTE_RAND, 0, oben)
	scanFrame.BackgroundColor3 = HudChrome.Color.PanelSunken
	scanFrame.BorderSizePixel = 0
	scanFrame.ClipsDescendants = true
	scanFrame.Parent = statsRowFrame

	local scanCorner = Instance.new("UICorner")
	scanCorner.CornerRadius = UDim.new(0, 3)
	scanCorner.Parent = scanFrame

	local scanStroke = Instance.new("UIStroke")
	scanStroke.Thickness = 1
	scanStroke.Color = HudChrome.Color.BorderDim
	scanStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	scanStroke.Parent = scanFrame

	-- Raster: zwei Linien quer, zwei laengs. Mehr braucht es nicht -- sie sollen sagen
	-- "hier wird gemessen", nicht selbst gelesen werden.
	for _, lage in ipairs({ { true, 0.33 }, { true, 0.66 }, { false, 0.33 }, { false, 0.66 } }) do
		local waagerecht, anteil = lage[1], lage[2]
		local linie = Instance.new("Frame")
		linie.Name = "Grid"
		linie.BackgroundColor3 = config.color
		linie.BackgroundTransparency = 0.85
		linie.BorderSizePixel = 0
		linie.ZIndex = 2
		if waagerecht then
			linie.Size = UDim2.new(1, 0, 0, 1)
			linie.Position = UDim2.new(0, 0, anteil, 0)
		else
			linie.Size = UDim2.new(0, 1, 1, 0)
			linie.Position = UDim2.new(anteil, 0, 0, 0)
		end
		linie.Parent = scanFrame
	end

	local scanViewport = ModelPreviewUtils.CreateViewport(scanFrame, 3)
	scanViewport.Name = "ScanViewport"

	-- Die Abtastlinie wandert von oben nach unten. Sie ist der Grund, warum das Fenster
	-- nach Geraet aussieht und nicht nach Bild: ein Scan laeuft.
	local scanLine = Instance.new("Frame")
	scanLine.Name = "ScanLine"
	scanLine.Size = UDim2.new(1, 0, 0, 2)
	scanLine.Position = UDim2.new(0, 0, 0, 0)
	scanLine.BackgroundColor3 = config.color
	scanLine.BackgroundTransparency = 0.4
	scanLine.BorderSizePixel = 0
	scanLine.ZIndex = 4
	scanLine.Parent = scanFrame

	-- Vier Eckwinkel. Sie kosten vier Rahmen und machen aus einem Kaestchen ein Sichtfeld.
	for _, ecke in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local ex, ey = ecke[1], ecke[2]
		for _, richtung in ipairs({ "waagerecht", "senkrecht" }) do
			local winkel = Instance.new("Frame")
			winkel.Name = "Bracket"
			winkel.AnchorPoint = Vector2.new(ex, ey)
			winkel.BackgroundColor3 = config.color
			winkel.BackgroundTransparency = 0.25
			winkel.BorderSizePixel = 0
			winkel.ZIndex = 5
			if richtung == "waagerecht" then
				winkel.Size = UDim2.new(0, 16, 0, 2)
			else
				winkel.Size = UDim2.new(0, 2, 0, 16)
			end
			winkel.Position = UDim2.new(ex, ex == 0 and 4 or -4, ey, ey == 0 and 4 or -4)
			winkel.Parent = scanFrame
		end
	end

	-- --- Die Ablesung daneben ---
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = config.key .. "Name"
	nameLabel.Size = UDim2.new(0, 110, 0, 24)
	nameLabel.Position = UDim2.new(0, textX, 0, oben + 14)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = config.label
	nameLabel.Parent = statsRowFrame
	HudChrome.Label(nameLabel, 20)
	nameLabel.TextColor3 = config.color

	local label = Instance.new("TextLabel")
	label.Name = config.key .. "Value"
	label.Size = UDim2.new(0, textBreite, 0, 24)
	label.Position = UDim2.new(0, textX, 0, oben + 40)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "0 / 0"
	label.Parent = statsRowFrame
	HudChrome.NumberBold(label, 19)

	local statBackground = Instance.new("Frame")
	statBackground.Name = config.key .. "Track"
	statBackground.Size = UDim2.new(0, textBreite, 0, 10)
	statBackground.Position = UDim2.new(0, textX, 0, oben + 68)
	statBackground.BackgroundColor3 = HudChrome.Color.PanelSunken
	statBackground.BorderSizePixel = 0
	statBackground.Parent = statsRowFrame

	local statBackgroundCorner = Instance.new("UICorner")
	statBackgroundCorner.CornerRadius = UDim.new(0, 4)
	statBackgroundCorner.Parent = statBackground

	local statFill = Instance.new("Frame")
	statFill.Name = "Fill"
	statFill.Size = UDim2.new(0, 0, 1, 0)
	statFill.BackgroundColor3 = config.color
	statFill.BorderSizePixel = 0
	statFill.ZIndex = 2
	statFill.Parent = statBackground

	local statFillCorner = Instance.new("UICorner")
	statFillCorner.CornerRadius = UDim.new(0, 4)
	statFillCorner.Parent = statFill

	local effectLabel = Instance.new("TextLabel")
	effectLabel.Name = config.key .. "Effect"
	effectLabel.Size = UDim2.new(0, textBreite, 0, 16)
	effectLabel.Position = UDim2.new(0, textX, 0, oben + 82)
	effectLabel.BackgroundTransparency = 1
	effectLabel.TextXAlignment = Enum.TextXAlignment.Left
	effectLabel.Text = config.effect
	effectLabel.Parent = statsRowFrame
	HudChrome.Number(effectLabel, 13)
	effectLabel.TextColor3 = HudChrome.Color.TextDim

	statBars[config.key] = {
		label = label,
		fill = statFill,
		displayName = config.short,
		color = config.color,
		scanFrame = scanFrame,
		scanStroke = scanStroke,
		scanViewport = scanViewport,
		scanLine = scanLine,
	}
end

-- ===== Den Scan mit der eigenen Figur fuellen =====
--
-- Erster Versuch: die R15-Teile (RightUpperArm usw.) klonen. Das ging schief, und die
-- Messung sagt genau warum -- die Figur hat KEIN einziges sichtbares Teil im Charakter.
-- Sie traegt ein eigenes Modell, das erst nach dem Spawn angehaengt wird, und die
-- R15-Teile darunter sind nur unsichtbare Knochen.
--
-- Daraus folgt der Aufbau hier:
--
--   SICHTBAR ist, was im Charakter an sichtbaren Teilen haengt, wo auch immer. Das wird
--   geklont -- vollstaendig, ohne Namen zu raten. Die Namen des getragenen Modells kennt
--   dieses Skript nicht und soll es auch nicht kennen muessen.
--
--   WOHIN geschaut wird, sagen die unsichtbaren R15-Knochen. Sie sitzen genau dort, wo das
--   sichtbare Glied ist -- dafuer sind sie da. Sie liefern also den Zielpunkt und den
--   Bildausschnitt, ohne selbst gezeigt zu werden.
--
-- Das ist der Grund, warum hier nicht ModelPreviewUtils.Fit steht: das rahmt ein GANZES
-- Modell. Hier soll ein Ausschnitt daraus gerahmt werden.
local SCAN_FOV = 40

local function knochenBereich(character, teileNamen)
	local minimum, maximum
	for _, name in ipairs(teileNamen) do
		local teil = character:FindFirstChild(name, true)
		if teil and teil:IsA("BasePart") then
			local halb = teil.Size * 0.5
			local mitte = teil.Position
			local von, bis = mitte - halb, mitte + halb
			minimum = minimum and Vector3.new(math.min(minimum.X, von.X), math.min(minimum.Y, von.Y), math.min(minimum.Z, von.Z)) or von
			maximum = maximum and Vector3.new(math.max(maximum.X, bis.X), math.max(maximum.Y, bis.Y), math.max(maximum.Z, bis.Z)) or bis
		end
	end
	if not minimum then
		return nil
	end
	return (minimum + maximum) * 0.5, maximum - minimum
end

-- Woher der Scan seine Gestalt nimmt.
--
-- NICHT aus der getragenen Figur: die ist noch der alte Avatar, solange der Umbau auf die
-- Stufenmodelle laeuft. Der Scan soll zeigen, was die Stufe WIRKLICH ist -- und das weiss
-- StageModels.
--
-- Gebaut wird einmal und dann geklont. Ein Modell kann nur in EINEM ViewportFrame haengen,
-- drei Fenster brauchen also drei Kopien -- aber nur einen Bau.
local scanVorlage = nil
local scanVorlageSkin = nil

local function holeVorlage()
	local ausgeruestet = player:FindFirstChild("EquippedSkin")
	local skinId = (ausgeruestet and ausgeruestet.Value) or 0

	if scanVorlage and scanVorlage.Parent and scanVorlageSkin == skinId then
		return scanVorlage
	end

	if scanVorlage then
		scanVorlage:Destroy()
		scanVorlage = nil
	end

	if StageModels and StageModels.BuildPreview then
		local ok, modell = pcall(StageModels.BuildPreview, "Kaiju", skinId)
		if ok and modell then
			modell.Parent = script -- irgendwo ausserhalb des Bildes ablegen, nur als Vorlage
			scanVorlage = modell
			scanVorlageSkin = skinId
			return scanVorlage
		end
	end

	-- Rueckfall: die getragene Figur. Besser ein alter Scan als gar keiner.
	return player.Character
end

local function baueScan(key, vorlage)
	local eintrag = statBars[key]
	local teileNamen = SCAN_TEILE[key]
	if not eintrag or not teileNamen or not vorlage then
		return false, "keine Vorlage"
	end

	local altes = eintrag.scanViewport:FindFirstChildOfClass("Model")
	if altes then
		altes:Destroy()
	end

	local mitte, groesse = knochenBereich(vorlage, teileNamen)
	if not mitte then
		return false, "keine Knochen dieses Namens im Modell"
	end

	-- Gehoert dieses Teil zum gescannten Bereich?
	--
	-- Geprueft wird die LAGE, nicht der Name: wie das getragene Modell seine Teile nennt,
	-- weiss dieses Skript nicht. Der Knochenbereich sagt, wo der Arm ist -- was dort liegt,
	-- ist der Arm. Der Zuschlag faengt auf, dass das sichtbare Mesh ueber seinen Knochen
	-- hinausragt.
	--
	-- Der Rand ist in ALLEN Richtungen gleich gross und richtet sich nach der LAENGSTEN
	-- Kante des Bereichs. Vorher war er je Achse anteilig -- und genau daran scheiterte der
	-- Rumpf: sein Knochen ist eine duenne Scheibe, in der Tiefe also nur ein bis zwei
	-- Studs. Fuenfunddreissig Prozent davon sind ein paar Zentimeter, und die Rueckenplatten
	-- sitzen weiter hinten. Sie fielen aus dem Bereich, obwohl sie offensichtlich zum Rumpf
	-- gehoeren.
	local randweite = math.max(groesse.X, groesse.Y, groesse.Z) * 0.3
	local rand = Vector3.new(randweite, randweite, randweite)
	local von = mitte - groesse * 0.5 - rand
	local bis = mitte + groesse * 0.5 + rand
	local function imBereich(punkt)
		return punkt.X >= von.X and punkt.X <= bis.X
			and punkt.Y >= von.Y and punkt.Y <= bis.Y
			and punkt.Z >= von.Z and punkt.Z <= bis.Z
	end

	-- Alles Sichtbare klonen, ohne Namen zu raten.
	local modell = Instance.new("Model")
	modell.Name = "ScanModel"
	local gefunden = 0
	for _, nachfahre in ipairs(vorlage:GetDescendants()) do
		if nachfahre:IsA("BasePart") and nachfahre.Transparency < 1 then
			local gehoertDazu = imBereich(nachfahre.Position)
			local klon = nachfahre:Clone()
			for _, kind in ipairs(klon:GetChildren()) do
				if not kind:IsA("SpecialMesh") then
					kind:Destroy()
				end
			end
			if klon:IsA("MeshPart") then
				klon.TextureID = "" -- ein Roentgenbild zeigt Form, nicht Farbe
			end
			klon.Anchored = true
			klon.CanCollide = false
			klon.CastShadow = false
			klon.Material = Enum.Material.Neon
			-- Deutlich durchsichtig: ein Roentgenbild zeigt das Innere MIT, nicht die
			-- Oberflaeche davor. Ueberlappende Teile summieren sich zu den dichteren
			-- Stellen auf, genau wie bei einer echten Durchleuchtung.
			--
			-- Der gescannte Bereich leuchtet in der Farbe seines Wertes, der Rest bleibt
			-- grau und tritt noch weiter zurueck.
			klon.Color = gehoertDazu
				and eintrag.color:Lerp(HudChrome.Color.BorderBright, SCAN_ENTSAETTIGUNG)
				or SCAN_GRAU
			klon.Transparency = gehoertDazu and 0.15 or 0.3
			klon.Parent = modell
			if gehoertDazu then
				gefunden += 1
			end
		end
	end

	if gefunden == 0 then
		modell:Destroy()
		return false, "Knochen da, aber nichts Sichtbares in ihrem Bereich"
	end

	modell.Parent = eintrag.scanViewport

	-- Kamera auf den Knochenbereich richten, von der SEITE.
	--
	-- Von vorn ueberdeckt der Rumpf die Arme und die Ruecken-Platten sind gar nicht zu
	-- sehen. Von der Seite steht jedes der drei Teile frei: der Arm neben dem Koerper, das
	-- Bein darunter, und der Ruecken im Profil. Das ist auch die Ansicht, in der ein
	-- Roentgenbild ueblicherweise gemacht wird.
	--
	-- Die Richtung kommt aus der Wurzel der Vorlage, wenn es eine gibt. Sonst gilt die
	-- Roblox-Konvention: die Vorderseite zeigt entlang -Z, rechts ist damit +X -- dieselbe
	-- Annahme, auf der auch ModelPreviewUtils.Fit beruht.
	local wurzel = vorlage:FindFirstChild("HumanoidRootPart", true)
	local zurSeite = wurzel and wurzel.CFrame.RightVector or Vector3.new(1, 0, 0)

	local kamera = eintrag.scanViewport.CurrentCamera
	if not kamera then
		kamera = Instance.new("Camera")
		kamera.Parent = eintrag.scanViewport
		eintrag.scanViewport.CurrentCamera = kamera
	end
	kamera.FieldOfView = SCAN_FOV

	local spanne = math.max(groesse.X, groesse.Y, groesse.Z)
	local abstand = (spanne * 0.5) / math.tan(math.rad(SCAN_FOV) * 0.5) * SCAN_ZOOM
	kamera.CFrame = CFrame.new(mitte + zurSeite * abstand, mitte)

	return true
end

-- Der Scan braucht eine Figur, die schon SICHTBAR ist. Beim Spawn ist sie das nicht: die
-- R15-Teile stehen sofort, das getragene Modell haengt sich erst danach an. Deshalb wird
-- so lange erneut versucht, bis es klappt -- und nicht einmalig geraten.
local scanVersuch = 0
local function baueAlleScans()
	scanVersuch += 1
	local meinVersuch = scanVersuch

	task.spawn(function()
		-- Teilerfolge werden BEHALTEN. Vorher wurde bei jedem Durchgang alles neu gebaut,
		-- und ein einziger Bereich, der nie gelingt, haette die beiden anderen zwanzigmal
		-- neu erzeugt -- und die Erfolgsmeldung waere nie gekommen, obwohl zwei Fenster
		-- laengst standen.
		local steht = {}
		for durchgang = 1, 20 do -- hoechstens zehn Sekunden
			if scanVersuch ~= meinVersuch then
				return -- ein neuer Charakter hat uebernommen
			end

			local vorlage = holeVorlage()
			local gruende = {}
			if vorlage then
				for key in pairs(SCAN_TEILE) do
					if not steht[key] then
						local ok, grund = baueScan(key, vorlage)
						if ok then
							steht[key] = true
						else
							gruende[key] = grund
						end
					end
				end
			end

			local fehlend = {}
			for key in pairs(SCAN_TEILE) do
				if not steht[key] then
					table.insert(fehlend, key .. " (" .. (gruende[key] or "unbekannt") .. ")")
				end
			end

			if #fehlend == 0 then
				print(string.format(
					"[Kaiju Debug] Scan: alle drei stehen nach %d Versuch(en) -- Vorlage: %s.",
					durchgang,
					(scanVorlage and scanVorlage.Name) or "getragene Figur"
				))
				return
			end

			if durchgang == 20 then
				-- Benennen, WELCHER Bereich fehlt. "Es geht nicht" hilft niemandem; der
				-- Name sagt, ob die Knochen des Bereichs im Modell fehlen oder ob dort
				-- nichts Sichtbares liegt.
				warn(string.format(
					"[Kaiju Debug] Scan: nach zehn Sekunden fehlen noch %s (Vorlage: %s).",
					table.concat(fehlend, ", "),
					(scanVorlage and scanVorlage.Name) or "getragene Figur"
				))
			end
			task.wait(0.5)
		end
	end)
end

-- Der Charakter existiert beim Start des Skripts moeglicherweise noch nicht, und er wird
-- bei jedem Tod und bei jedem Skin-Wechsel ersetzt. Einen Verzug braucht es hier nicht
-- mehr -- die Wiederholung oben wartet selbst, bis die Figur sichtbar ist.
player.CharacterAdded:Connect(baueAlleScans)
if player.Character then
	baueAlleScans()
end
player:GetAttributeChangedSignal("EquippedSkin"):Connect(baueAlleScans)

-- Die Abtastlinien wandern. Eine Schleife fuer alle drei -- drei eigene waeren dieselbe
-- Rechnung dreimal.
RunService.Heartbeat:Connect(function()
	if not statsRowFrame.Visible then
		return
	end
	local lauf = (os.clock() * 0.45) % 1
	for _, eintrag in pairs(statBars) do
		if eintrag.scanLine then
			eintrag.scanLine.Position = UDim2.new(0, 0, lauf, 0)
			-- An den Raendern ausblenden, damit die Linie nicht springt, sondern durchlaeuft.
			eintrag.scanLine.BackgroundTransparency = 0.4 + math.abs(lauf - 0.5) * 0.8
		end
	end
end)

-- ===== Zonenabhängige Umschaltung: Heat/Berserk-Leiste ist ausserhalb von Sanctuary
-- relevant (Kampf), die Skill-Balken (Arm/Bein/Körper) dagegen speziell IM Sanctuary
-- (friedliche Zone, guter Ort um den eigenen Fortschritt zu checken, kein Kampf-HUD
-- nötig). Reduziert dadurch die HUD-Dichte in beiden Situationen. =====
local function updateZoneBasedHudVisibility()
	local isSanctuary = player:GetAttribute("CurrentZone") == "Sanctuary"
	local isTraining = player:GetAttribute("TrainingStat") ~= nil or player:GetAttribute("BodyTrainingActive") == true
	statsRowFrame.Visible = isSanctuary
	-- Der Tacho steht ueberall. Hitze entsteht auch beim Training, und der Berserker wirkt
	-- dort genauso -- ein Instrument, das je nach Ort verschwindet, waere ein Instrument,
	-- dem man nicht traut.
	heatFrame.Visible = true
end

player:GetAttributeChangedSignal("TrainingStat"):Connect(updateZoneBasedHudVisibility)
player:GetAttributeChangedSignal("BodyTrainingActive"):Connect(updateZoneBasedHudVisibility)

player:GetAttributeChangedSignal("CurrentZone"):Connect(updateZoneBasedHudVisibility)
updateZoneBasedHudVisibility()

-- ===== Skin-Shop-Menü: öffnet sich über den "Skin kaufen"-Button (Comic-Panel) =====
-- EIGENES ScreenGui fuer das Panel. Vorher lag es in GameHud -- zusammen mit
-- Statuszeile, Hitzeanzeige und zehn weiteren HUD-Teilen, also ohne DisplayOrder auf 0 und damit gleichauf mit dem uebrigen HUD.
-- Ein Vollbild-Panel auf derselben Ebene wie das HUD laesst dieses durchscheinen.
--
-- Getrennt statt die DisplayOrder des ganzen Guis anzuheben: das haette das HUD gleich
-- mit nach vorne geholt, also genau das Gegenteil bewirkt.
local shopGui = Instance.new("ScreenGui")
shopGui.Name = "SkinShopGui"
shopGui.ResetOnSpawn = false
shopGui.DisplayOrder = 100
shopGui.IgnoreGuiInset = true
shopGui.Parent = player:WaitForChild("PlayerGui")

local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
-- Vollbild: alle Menü-Bildschirme nutzen die ganze Fläche.
-- IgnoreGuiInset am ScreenGui gehört dazu -- ohne das beginnt jedes ScreenGui UNTERHALB
-- der Roblox-Systemleiste, und oben bliebe ein Streifen mit Sicht auf die Welt stehen.
shopFrame.Size = UDim2.new(1, 0, 1, 0)
shopFrame.Position = UDim2.new(0, 0, 0, 0)
shopFrame.AnchorPoint = Vector2.new(0, 0)
shopFrame.Visible = false
shopFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
shopFrame.Parent = shopGui

-- Schliesst den Shop zwangsweise -- unabhängig davon, was ihn geöffnet hat (auch falls es
-- NICHT über den normalen Navigations-Weg lief, siehe ForceCloseShopEvent). Genutzt vom
-- Prolog, um sicherzustellen, dass der Shop beim Verlassen des Prologs nicht offen steht.
local ForceCloseShopEvent = RemoteEventUtils.GetOrCreate("ForceCloseShopEvent")
ForceCloseShopEvent.OnClientEvent:Connect(function()
	shopFrame.Visible = false
end)
applyComicStyle(shopFrame, 20, 5)

-- Inhalt unter der Roblox-Systemleiste hervorholen. IgnoreGuiInset zieht die
-- Zeichenflaeche bewusst DARUNTER, damit oben kein Streifen mit Sicht auf die Welt bleibt --
-- das gilt aber nur fuer den Hintergrund. Das Polster wird nachgezogen, siehe TopInsetUtils.
TopInsetUtils.Bind(shopFrame)

-- X-Schliessen-Button -- kehrt zum Hamburger-Menü zurück (dieses Panel hatte bisher
-- keinen eigenen, war nur über den jetzt entfernten "← Back"-Button schliessbar).
local shopCloseButton = Instance.new("TextButton")
shopCloseButton.Name = "CloseButton"
shopCloseButton.Size = UDim2.new(0, 34, 0, 34)
shopCloseButton.AnchorPoint = Vector2.new(1, 0)
shopCloseButton.Position = UDim2.new(1, -8, 0, 8)
shopCloseButton.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
shopCloseButton.Font = Enum.Font.FredokaOne
shopCloseButton.TextScaled = true
shopCloseButton.TextColor3 = Color3.new(1, 1, 1)
shopCloseButton.Text = "X"
shopCloseButton.ZIndex = 5
shopCloseButton.Parent = shopFrame
applyComicStyle(shopCloseButton, 8, 2)
shopCloseButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
	if _G.NavReturnToMenu then
		_G.NavReturnToMenu()
	end
end)

local shopTitle = Instance.new("TextLabel")
shopTitle.Name = "ShopTitle"
shopTitle.Size = UDim2.new(1, -16, 0, 40)
shopTitle.Position = UDim2.new(0, 8, 0, 8)
shopTitle.BackgroundTransparency = 1
shopTitle.TextColor3 = Color3.fromRGB(235, 235, 245)
shopTitle.Font = Enum.Font.LuckiestGuy
shopTitle.TextScaled = true
shopTitle.Text = "☯️ Skins"
shopTitle.Parent = shopFrame

-- Liste links, Steckbrief rechts. Die Liste braucht wenig -- sechs Eintraege mit Name und
-- Zustand --, der Steckbrief traegt Modell, Balken, Beschreibung und den Aktionsknopf.
local LIST_WIDTH = 0.3

local shopScroll = Instance.new("ScrollingFrame")
shopScroll.Name = "ShopScroll"
shopScroll.Size = UDim2.new(LIST_WIDTH, -16, 1, -60)
shopScroll.Position = UDim2.new(0, 12, 0, 54)
shopScroll.BackgroundTransparency = 1
shopScroll.BorderSizePixel = 0
shopScroll.ScrollBarThickness = 10
shopScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopScroll.Parent = shopFrame

local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 8)
-- Ausdruecklich nach LayoutOrder: seit die Liste nach Fraktionen gruppiert ist, haengt die
-- Reihenfolge an den vergebenen Nummern und nicht mehr an der Erzeugungsreihenfolge.
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = shopScroll

-- ===== Steckbrief =====
-- Kein Unterbildschirm: der Shop ist seit dem Vollbild-Umbau breit genug, beides
-- nebeneinander zu zeigen. Ein Klick in der Liste WAEHLT nur aus -- gekauft und angelegt
-- wird ueber den Knopf hier. Vorher kaufte ein Klick sofort, was bei 6000 Muenzen fuer den
-- die oberste Stufe ein teures Versehen sein konnte.
local detailFrame = Instance.new("Frame")
detailFrame.Name = "SkinDetail"
detailFrame.Size = UDim2.new(1 - LIST_WIDTH, -24, 1, -60)
detailFrame.Position = UDim2.new(LIST_WIDTH, 4, 0, 54)

local SKIN_TEXT_MAX_WIDTH = 620 -- lesbare Zeilenlaenge, unabhaengig von der Bildschirmbreite
detailFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
detailFrame.Parent = shopFrame
applyComicStyle(detailFrame, 14, 3)

local detailViewport = Instance.new("Frame")
detailViewport.Name = "Preview"
detailViewport.Size = UDim2.new(0.42, -24, 0.52, 0)
detailViewport.Position = UDim2.new(0, 16, 0, 16)
detailViewport.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
detailViewport.Parent = detailFrame
applyComicStyle(detailViewport, 12, 2)

local detailName = Instance.new("TextLabel")
detailName.Size = UDim2.new(0.58, -32, 0, 40)
detailName.Position = UDim2.new(0.42, 0, 0, 16)
detailName.BackgroundTransparency = 1
detailName.Font = Enum.Font.LuckiestGuy
detailName.TextScaled = true
detailName.TextXAlignment = Enum.TextXAlignment.Left
detailName.TextColor3 = Color3.fromRGB(235, 235, 245)
detailName.Text = ""
detailName.Parent = detailFrame

-- Hoechstbreite der Textspalte. Ohne sie laeuft der Steckbrief auf einem breiten
-- Bildschirm ueber die halbe Monitorbreite -- so lange Zeilen liest niemand gern.
local detailNameWidthCap = Instance.new("UISizeConstraint")
detailNameWidthCap.MaxSize = Vector2.new(SKIN_TEXT_MAX_WIDTH, math.huge)
detailNameWidthCap.Parent = detailName

local detailRole = Instance.new("TextLabel")
detailRole.Size = UDim2.new(0.58, -32, 0, 44)
detailRole.Position = UDim2.new(0.42, 0, 0, 58)
detailRole.BackgroundTransparency = 1
detailRole.Font = Enum.Font.Gotham
detailRole.TextSize = 15
detailRole.TextWrapped = true
detailRole.TextXAlignment = Enum.TextXAlignment.Left
detailRole.TextYAlignment = Enum.TextYAlignment.Top
detailRole.TextColor3 = Color3.fromRGB(165, 165, 180)
detailRole.Text = ""
detailRole.Parent = detailFrame

-- Hoechstbreite der Textspalte. Ohne sie laeuft der Steckbrief auf einem breiten
-- Bildschirm ueber die halbe Monitorbreite -- so lange Zeilen liest niemand gern.
local detailRoleWidthCap = Instance.new("UISizeConstraint")
detailRoleWidthCap.MaxSize = Vector2.new(SKIN_TEXT_MAX_WIDTH, math.huge)
detailRoleWidthCap.Parent = detailRole

local detailStrength = Instance.new("TextLabel")
detailStrength.Size = UDim2.new(0.58, -32, 0, 90)
detailStrength.Position = UDim2.new(0.42, 0, 0, 106)
detailStrength.BackgroundTransparency = 1
UiTypography.Body(detailStrength)
detailStrength.TextXAlignment = Enum.TextXAlignment.Left
detailStrength.TextYAlignment = Enum.TextYAlignment.Top
detailStrength.TextColor3 = Color3.fromRGB(235, 235, 245)
detailStrength.Text = ""
detailStrength.Parent = detailFrame

-- Hoechstbreite der Textspalte. Ohne sie laeuft der Steckbrief auf einem breiten
-- Bildschirm ueber die halbe Monitorbreite -- so lange Zeilen liest niemand gern.
local detailStrengthWidthCap = Instance.new("UISizeConstraint")
detailStrengthWidthCap.MaxSize = Vector2.new(SKIN_TEXT_MAX_WIDTH, math.huge)
detailStrengthWidthCap.Parent = detailStrength

-- Der Kaufgrund in einer Zeile. Frueher stand hier die Level-Freischaltung -- jeder
-- gekaufte Skin hob die Obergrenze um 10. Die Deckelung ist entfallen; an ihre Stelle
-- tritt der Angriffsbonus, der die Stufen weiterhin unterscheidet, ohne den Fortschritt
-- zu sperren.
local detailBonus = Instance.new("TextLabel")
detailBonus.Size = UDim2.new(0.58, -32, 0, 26)
detailBonus.Position = UDim2.new(0.42, 0, 0, 200)
detailBonus.BackgroundColor3 = Color3.fromRGB(255, 236, 180)
UiTypography.Body(detailBonus, 15)
detailBonus.TextColor3 = Color3.fromRGB(120, 80, 20)
detailBonus.Text = ""
detailBonus.Visible = false
detailBonus.Parent = detailFrame

-- Hoechstbreite der Textspalte. Ohne sie laeuft der Steckbrief auf einem breiten
-- Bildschirm ueber die halbe Monitorbreite -- so lange Zeilen liest niemand gern.
local detailBonusWidthCap = Instance.new("UISizeConstraint")
detailBonusWidthCap.MaxSize = Vector2.new(SKIN_TEXT_MAX_WIDTH, math.huge)
detailBonusWidthCap.Parent = detailBonus
applyComicStyle(detailBonus, 8, 2)

-- Vier Balken: Leben, Angriff, Tempo, Groesse. Der Angriffsbalken ist neu und hat eine
-- Vorgeschichte: hier stand einmal ein Feld "Damage", das entfernt wurde, weil es nirgends
-- gelesen wurde. DamagePercent ist der Ersatz und wird tatsaechlich angewandt (siehe
-- PlayerSetup.recalculateStrength) -- deshalb darf er jetzt im Steckbrief stehen.
local statRows = {}
local STAT_DEFS = {
	{ key = "Health", label = "Health" },
	{ key = "DamagePercent", label = "Attack %" },
	{ key = "WalkSpeed", label = "Speed" },
	{ key = "Scale", label = "Size" },
}
for index, def in ipairs(STAT_DEFS) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -32, 0, 30)
	row.Position = UDim2.new(0, 16, 0.52, (index - 1) * 34) -- 0.52 statt 0.56: der vierte Balken braucht den Platz
	row.BackgroundTransparency = 1
	row.Parent = detailFrame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 70, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(165, 165, 180)
	label.Text = def.label
	label.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -230, 0, 14)
	track.Position = UDim2.new(0, 74, 0.5, -7)
	track.BackgroundColor3 = Color3.fromRGB(58, 58, 68)
	track.Parent = row
	applyComicStyle(track, 7, 2)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90, 175, 235)
	fill.BorderSizePixel = 0
	fill.Parent = track
	applyComicStyle(fill, 7, 0)

	-- Der Vergleich zum GETRAGENEN Skin -- das ist die Frage, wegen der man herschaut.
	local delta = Instance.new("TextLabel")
	delta.Size = UDim2.new(0, 150, 1, 0)
	delta.Position = UDim2.new(1, -150, 0, 0)
	delta.BackgroundTransparency = 1
	delta.Font = Enum.Font.Gotham
	delta.TextSize = 14
	delta.TextXAlignment = Enum.TextXAlignment.Right
	delta.TextColor3 = Color3.fromRGB(165, 165, 180)
	delta.Text = ""
	delta.Parent = row

	statRows[def.key] = { fill = fill, delta = delta, row = row }
end

local detailAction = Instance.new("TextButton")
detailAction.Name = "ActionButton"
detailAction.Size = UDim2.new(1, -32, 0, 52)
detailAction.Position = UDim2.new(0, 16, 1, -68)
detailAction.Font = Enum.Font.FredokaOne
detailAction.TextScaled = true
detailAction.TextColor3 = Color3.new(1, 1, 1)
detailAction.Text = ""
detailAction.Parent = detailFrame
applyComicStyle(detailAction, 12, 3)

-- ===== Das Stations-Panel ist entfernt =====
--
-- Es zeigte Titel, Fortschrittsbalken und Zahl des gerade trainierten Wertes -- also genau
-- das, was die Zeile desselben Wertes in der Uebersicht darueber ohnehin schon zeigt. Zwei
-- Balken fuer dieselbe Zahl, uebereinander.
--
-- Das Einzige, was es beitrug, war der Abbruch-Knopf. Der sitzt jetzt in der Kopfzeile der
-- Uebersicht. Welcher Wert gerade trainiert wird, sagt dort das aufleuchtende Scanfenster.
local STAT_DISPLAY_NAMES = {
	Leg = "BEIN",
	Arm = "ARM",
	Body = "KOERPER",
}

local TRAIN_BREITE = SPALTE_BREITE
local TRAIN_RAND = SPALTE_RAND
local BOOST_Y = KRAFT_Y + 34 + KRAFT_ZEILE * 3 - 8 + 12 + 8

-- ===== Boost-Anzeige =====
-- Eigenes Feld, weil der Boost-Fortschritt bestehen bleibt, auch wenn man gerade an keiner
-- Station steht -- es verschwindet also NICHT zusammen mit dem Stations-Panel.
local boostFrame = Instance.new("Frame")
boostFrame.Name = "BoostFrame"
boostFrame.Size = UDim2.new(0, TRAIN_BREITE, 0, 52)
boostFrame.AnchorPoint = Vector2.new(1, 0)
boostFrame.Position = UDim2.new(1, SPALTE_X, 0, BOOST_Y)
boostFrame.Visible = false
boostFrame.Parent = screenGui
HudChrome.Panel(boostFrame, { radius = HudChrome.Radius.Small })

local boostLabel = Instance.new("TextLabel")
boostLabel.Name = "BoostLabel"
boostLabel.Size = UDim2.new(0, 240, 0, 20)
boostLabel.Position = UDim2.new(0, TRAIN_RAND, 0, 7)
boostLabel.BackgroundTransparency = 1
boostLabel.TextXAlignment = Enum.TextXAlignment.Left
boostLabel.Text = "TRAINING BOOST"
boostLabel.Parent = boostFrame
HudChrome.Label(boostLabel, 16)
boostLabel.TextColor3 = HudChrome.Color.Ready

local boostBarBackground = Instance.new("Frame")
boostBarBackground.Name = "BoostBarBackground"
boostBarBackground.Size = UDim2.new(1, -TRAIN_RAND * 2, 0, 10)
boostBarBackground.Position = UDim2.new(0, TRAIN_RAND, 0, 32)
boostBarBackground.BackgroundColor3 = HudChrome.Color.PanelSunken
boostBarBackground.BorderSizePixel = 0
boostBarBackground.Parent = boostFrame

local boostBarCorner = Instance.new("UICorner")
boostBarCorner.CornerRadius = UDim.new(0, 5)
boostBarCorner.Parent = boostBarBackground

local boostBarFill = Instance.new("Frame")
boostBarFill.Name = "Fill"
boostBarFill.Size = UDim2.new(0, 0, 1, 0)
boostBarFill.BackgroundColor3 = HudChrome.Color.Ready
boostBarFill.BorderSizePixel = 0
boostBarFill.ZIndex = 2
boostBarFill.Parent = boostBarBackground

local boostBarFillCorner = Instance.new("UICorner")
boostBarFillCorner.CornerRadius = UDim.new(0, 5)
boostBarFillCorner.Parent = boostBarFill

-- ===== Das Berserker-Panel ist entfernt =====
--
-- Es konnte nie erscheinen. Seine Sichtbarkeit haengt an
--
--     local endsAt = player:GetAttribute("BerserkerEndsAt") or 0
--     local isActive = now < endsAt
--
-- und "BerserkerEndsAt" wird von KEINER Stelle im Projekt gesetzt. Der Ausdruck war also
-- immer now < 0, immer falsch. Panel, Balken, Beschriftung und eine Heartbeat-Schleife
-- liefen als toter Code mit.
--
-- Der Grund steht in BerserkerAuraClient: die Eskalation laeuft nach HITZE, nicht nach
-- Zeit -- ein fester Timer wurde bewusst verworfen. Das Panel ist ein Rest aus dem
-- verworfenen Entwurf.
--
-- Was es zeigen sollte, zeigt der Tacho inzwischen ohnehin besser: die Stufe steht dort
-- gross ueber dem Instrument, die Hitze traegt der Zeiger, und der Meltdown-Bereich ist
-- am Farbband markiert. So war es im Grilling auch entschieden (Q22).

-- Laeuft jeden Frame: Boost-Anzeige und Abbruch-Knopf, beide nur waehrend aktivem
-- Training sichtbar.

-- Kein eigener Boost-Sound mehr -- die Tempo-Erhöhung der Hintergrundmusik (siehe
-- BackgroundMusicClient.lua) übernimmt die Rolle als hörbares Boost-Feedback komplett.

RunService.Heartbeat:Connect(function()
	local statType = player:GetAttribute("TrainingStat")
	-- Body-Training nutzt ein eigenes Attribut (BodyTrainingActive) statt TrainingStat,
	-- da die Station komplett eigenständig läuft -- hier trotzdem denselben Balken zeigen.
	if not statType and player:GetAttribute("BodyTrainingActive") then
		statType = "Body"
	end
	local isTraining = statType ~= nil
	boostFrame.Visible = isTraining
	leaveTrainingButton.Visible = isTraining

	-- Welcher Wert gerade trainiert wird, sagt das Scanfenster: seine Umrandung nimmt die
	-- Farbe des Wertes an, die anderen beiden bleiben grau. Das ersetzt den Titel des
	-- entfernten Panels -- und sagt dasselbe an der Stelle, an der man ohnehin hinsieht.
	for key, eintrag in pairs(statBars) do
		local aktiv = isTraining and key == (statType .. "Power")
		if eintrag.scanStroke then
			eintrag.scanStroke.Color = aktiv and eintrag.color or HudChrome.Color.BorderDim
			eintrag.scanStroke.Thickness = aktiv and 2 or 1
		end
	end

	if not isTraining then
		return
	end

	local boostEndsAt = player:GetAttribute("BoostEndsAt") or 0
	local now = Workspace:GetServerTimeNow()

	if now < boostEndsAt then
		local remaining = boostEndsAt - now
		local boostRatio = math.clamp(remaining / math.max(boostDurationValue.Value, 1), 0, 1)
		boostBarFill.Size = UDim2.new(boostRatio, 0, 1, 0)

		-- Rotes Pulsieren während der AKTIVEN Boost-Phase -- Sinus-Welle zwischen
		-- dunklerem und hellerem Rot.
		local pulse = (math.sin(os.clock() * 6) + 1) / 2 -- 0..1
		local dimRed = Color3.fromRGB(150, 25, 25)
		local brightRed = Color3.fromRGB(255, 60, 60)
		boostBarFill.BackgroundColor3 = dimRed:Lerp(brightRed, pulse)
	else
		local charge = player:GetAttribute("BoostCharge") or 0
		local chargeNeeded = math.max(player:GetAttribute("BoostChargeNeeded") or 1, 1)
		local chargeRatio = math.clamp(charge / chargeNeeded, 0, 1)
		boostBarFill.Size = UDim2.new(chargeRatio, 0, 1, 0)
		boostBarFill.BackgroundColor3 = Color3.fromRGB(255, 220, 60) -- statisches Gelb während des Aufladens
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local statValue = player:FindFirstChild(statType .. "Power")
	if not leaderstats or not statValue then
		return
	end

	local capAttribute = "StatCap"
	if statType == "Arm" then
		capAttribute = "ArmStatCap"
	elseif statType == "Leg" then
		capAttribute = "LegStatCap"
	end
	local cap = math.max(player:GetAttribute(capAttribute) or 1, 1)
	local ratio = math.clamp(statValue.Value / cap, 0, 1)

	-- Anzeige und Balken pflegt die Uebersicht selbst (siehe statBars weiter oben). Hier
	-- bleibt nichts zu tun: die Zeile des trainierten Wertes IST die Anzeige.
end)

-- Lässt eine "+X"-Anzeige vom Charakter zum großen Trainings-Balken unten fliegen,
-- spielt bei Ankunft einen Sound ab.
local function spawnFlyingTrainPoint(amount, statType)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local camera = Workspace.CurrentCamera
	if not head or not camera then
		return
	end

	local key = statType .. "Power" -- "Arm" -> "ArmPower" usw., passend zu statBars
	local ui = statBars[key]
	if not ui then
		return
	end

	-- Nur für die ANZEIGE: Körper-Increments sind serverseitig absichtlich sehr klein
	-- (siehe TRAINING_SLOWDOWN in TrainingHandler.lua), damit "+0.0" nicht wie ein Fehler
	-- aussieht wird hier rein kosmetisch hochskaliert -- der tatsächliche, im Hintergrund
	-- verrechnete Fortschritt bleibt davon komplett unberührt.
	local displayAmount = amount
	if statType == "Body" then
		displayAmount = amount * 100
	end

	-- Ab jetzt läuft eine Animation für diesen Stat -- das automatische Live-Update in
	-- updateLevelBar() lässt diesen Balken bis zur Ankunft in Ruhe.
	isAnimatingStat[key] = true

	local jitter = Vector3.new(math.random(-15, 15) / 10, math.random(0, 15) / 10, math.random(-15, 15) / 10)
	local screenPoint = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 3, 0) + jitter)

	-- Phase 1: seitlicher Sprungversatz (mal links, mal rechts), gleiches Prinzip wie
	-- bei spawnFlyingEnergy.
	local sideJump = (math.random(0, 1) == 0 and -1 or 1) * math.random(100, 180)
	local poppedPosition = UDim2.new(0, screenPoint.X + sideJump, 0, screenPoint.Y - 48)

	local pointLabel = Instance.new("TextLabel")
	pointLabel.Name = "FlyingTrainPoint"
	pointLabel.Size = UDim2.new(0, 0, 0, 0) -- startet unsichtbar klein, für den Pop-Effekt
	pointLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	pointLabel.Position = UDim2.new(0, screenPoint.X + sideJump * 0.3, 0, screenPoint.Y - 18)
	pointLabel.BackgroundTransparency = 1
	pointLabel.Font = Enum.Font.LuckiestGuy
	pointLabel.TextScaled = true
	pointLabel.Text = "+" .. string.format("%.1f", displayAmount)
	pointLabel.TextColor3 = Color3.fromRGB(90, 220, 130)
	pointLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	pointLabel.TextStrokeTransparency = 0
	pointLabel.ZIndex = 51
	pointLabel.Parent = screenGui

	-- Phase 1: seitlich hüpfen + auf volle Größe aufpoppen (Überschwung-Easing)
	local popTween = TweenService:Create(
		pointLabel,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 84, 0, 40), Position = poppedPosition }
	)

	popTween.Completed:Connect(function()
		-- Phase 2: kurz verweilen, damit man die Zahl lesen kann
		task.delay(0.35, function()
			if not pointLabel.Parent then
				return
			end

			-- Phase 3: zum Balken DIESES Wertes in der Uebersicht fliegen. Frueher ging der
			-- Flug zur Leiste des Stations-Panels -- die gibt es nicht mehr, weil sie
			-- denselben Wert ein zweites Mal zeigte. Jetzt landet die Zahl dort, wo sie
			-- auch wirkt.
			local zielBalken = ui.fill.Parent
			local targetPosition = UDim2.new(
				0,
				zielBalken.AbsolutePosition.X + zielBalken.AbsoluteSize.X / 2,
				0,
				zielBalken.AbsolutePosition.Y + zielBalken.AbsoluteSize.Y / 2
			)

			local flightTween = TweenService:Create(
				pointLabel,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = targetPosition, TextTransparency = 0.4, TextStrokeTransparency = 0.4 }
			)

			flightTween.Completed:Connect(function()
				pointLabel:Destroy()
				if trainPointSound.SoundId ~= "" and trainPointSound.SoundId ~= "rbxassetid://0" then
					trainPointSound.TimePosition = 0
					trainPointSound:Play()
				end

				-- Erst JETZT die Balken tatsächlich aktualisieren + aufleuchten lassen.
				local capAttribute = "StatCap"
				if key == "ArmPower" then
					capAttribute = "ArmStatCap"
				elseif key == "LegPower" then
					capAttribute = "LegStatCap"
				end
				local cap = math.max(player:GetAttribute(capAttribute) or 1, 1)
				local statValue = player:FindFirstChild(key)
				local value = statValue and statValue.Value or 0
				local statRatio = math.clamp(value / cap, 0, 1)
				ui.fill.Size = UDim2.new(statRatio, 0, 1, 0)

				flashElement(ui.fill, Color3.new(1, 1, 1))
				glowFlashElement(ui.fill, Color3.fromRGB(255, 255, 200))

				isAnimatingStat[key] = false
				lastStatValues[key] = value
			end)

			flightTween:Play()
		end)
	end)

	popTween:Play()
end

TrainPointEvent.OnClientEvent:Connect(function(statType, amount)
	spawnFlyingTrainPoint(amount, statType)
end)

-- ===== Update-Funktionen =====
local function updateCoinsLabel()
	if isAnimatingCoins then
		return -- Zähler wird gerade von der Flug-Animation gesteuert
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats and leaderstats:FindFirstChild("Coins") then
		coinsLabel.Text = NumberFormat.Format(leaderstats.Coins.Value)
	end
end

-- Zählt den Coins-Text weich von "fromValue" zu "toValue" hoch.
local function animateCoinCount(fromValue, toValue)
	isAnimatingCoins = true
	local duration = 0.5
	local startTime = os.clock()

	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
		local current = math.floor(fromValue + (toValue - fromValue) * alpha)
		coinsLabel.Text = NumberFormat.Format(current)

		if alpha >= 1 then
			connection:Disconnect()
			isAnimatingCoins = false
			coinsLabel.Text = NumberFormat.Format(toValue)
		end
	end)
end

-- Lässt EINE Münze vom Ort des zerstörten Hauses zum Coins-Zähler fliegen.
-- Ruft onArrive() auf, sobald sie angekommen ist (Cash-Sound + Zähler übernimmt der Aufrufer).
local function spawnFlyingCoin(worldPosition, onArrive)
	local camera = workspace.CurrentCamera
	if not camera then
		onArrive()
		return
	end

	-- kleiner zufälliger Versatz, damit mehrere Münzen nicht exakt übereinanderliegen
	local jitter = Vector3.new(math.random(-15, 15) / 10, math.random(0, 15) / 10, math.random(-15, 15) / 10)
	local screenPoint = camera:WorldToViewportPoint(worldPosition + Vector3.new(0, 3, 0) + jitter)

	-- Seitlicher Sprungversatz (mal links, mal rechts) -- gleiches Prinzip wie bei der
	-- fliegenden Energie: erst hüpfen + aufpoppen, dann verweilen, dann erst losfliegen.
	local sideJump = (math.random(0, 1) == 0 and -1 or 1) * math.random(100, 180)
	local poppedPosition = UDim2.new(0, screenPoint.X + sideJump - 20, 0, screenPoint.Y - 48)

	-- Das hochgeladene Muenzbild statt des gezeichneten Kreises mit schwarzem Comic-Rand.
	-- Hier ist ein buntes Bild richtig: die fliegende Muenze ist Belohnung, kein Chrome --
	-- sie darf aus dem farblosen HUD herausfallen, das ist gerade ihre Aufgabe.
	local coinIcon = HudChrome.IconImage(screenGui, HudChrome.Icon.Coin)
	coinIcon.Name = "FlyingCoin"
	coinIcon.Size = UDim2.new(0, 0, 0, 0) -- startet unsichtbar klein, für den Pop-Effekt
	coinIcon.Position = UDim2.new(0, screenPoint.X + sideJump * 0.3, 0, screenPoint.Y - 20)
	coinIcon.ZIndex = 50

	-- Phase 1: seitlich hüpfen + auf volle Größe aufpoppen (Überschwung-Easing)
	local popTween = TweenService:Create(
		coinIcon,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 40, 0, 40), Position = poppedPosition }
	)

	popTween.Completed:Connect(function()
		-- Phase 2: kurz verweilen
		task.delay(0.3, function()
			if not coinIcon.Parent then
				return
			end

			-- Phase 3: erst jetzt Richtung Coins-Anzeige fliegen
			local targetPosition = UDim2.new(
				0,
				coinsFrame.AbsolutePosition.X + coinsFrame.AbsoluteSize.X / 2 - 20,
				0,
				coinsFrame.AbsolutePosition.Y + coinsFrame.AbsoluteSize.Y / 2 - 20
			)

			local flightTween = TweenService:Create(
				coinIcon,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = targetPosition, Rotation = 360 }
			)

			flightTween.Completed:Connect(function()
				coinIcon:Destroy()
				onArrive()
			end)

			flightTween:Play()
		end)
	end)

	popTween:Play()
end

-- Lässt mehrere Münzen fliegen (eine pro 10 Coins, mindestens eine), leicht zeitversetzt.
-- Jede Münze spielt bei Ankunft den Cash-Sound; der Zähler zählt einmal am Ende komplett hoch.
local COINS_PER_FLYING_COIN = 100
local COIN_LAUNCH_DELAY = 0.08 -- Sekunden zwischen den einzelnen Münzen

local function flyCoinsToHud(worldPosition, amount)
	local coinCount = math.max(1, math.floor(amount / COINS_PER_FLYING_COIN))
	local arrivedCount = 0

	local leaderstats = player:FindFirstChild("leaderstats")
	local newValue = (leaderstats and leaderstats:FindFirstChild("Coins")) and leaderstats.Coins.Value or amount
	local oldValue = math.max(newValue - amount, 0)

	for i = 1, coinCount do
		task.delay((i - 1) * COIN_LAUNCH_DELAY, function()
			spawnFlyingCoin(worldPosition, function()
				if cashSound.SoundId ~= "" and cashSound.SoundId ~= "rbxassetid://0" then
					cashSound.TimePosition = 0
					cashSound:Play()
				end

				arrivedCount += 1
				if arrivedCount == coinCount then
					animateCoinCount(oldValue, newValue)
					-- Ein Aufruf fuer das ganze Feld -- Grund, Rahmen und beide Texte.
					flashCoinsFrame()
				end
			end)
		end)
	end
end

CoinsEarnedEvent.OnClientEvent:Connect(function(amount, worldPosition)
	flyCoinsToHud(worldPosition, amount)
end)

-- ===== Energie fliegt zum Levelbalken (analog zu den fliegenden Münzen) =====
-- Drei Phasen für bessere Lesbarkeit: 1) seitlich hüpfen + aufpoppen (klein -> groß mit
-- Überschwung), 2) kurz verweilen, damit man die Zahl auch wirklich lesen kann, 3) erst
-- danach Richtung Levelbalken fliegen.
local function spawnFlyingEnergy(worldPosition, amount, energyType, onArrive)
	local camera = workspace.CurrentCamera
	if not camera then
		onArrive()
		return
	end

	local visual = ENERGY_TYPE_VISUALS[energyType] or DEFAULT_ENERGY_VISUAL

	local jitter = Vector3.new(math.random(-15, 15) / 10, math.random(0, 15) / 10, math.random(-15, 15) / 10)
	local screenPoint = camera:WorldToViewportPoint(worldPosition + Vector3.new(0, 3, 0) + jitter)

	-- Seitlicher Sprungversatz (mal links, mal rechts) -- weg vom direkten Ursprungspunkt,
	-- damit die Zahl nicht mitten im Getümmel der Quelle/anderer Effekte hängt.
	local sideJump = (math.random(0, 1) == 0 and -1 or 1) * math.random(100, 180)
	local poppedPosition = UDim2.new(0, screenPoint.X + sideJump, 0, screenPoint.Y - 48)

	-- Kein Hintergrund/Kreis mehr -- nur der Text selbst (Icon + Energiewert), mit
	-- schwarzem Textumriss für Lesbarkeit, Farbe passend zum tatsächlichen Energie-Typ.
	local energySymbol = Instance.new("TextLabel")
	energySymbol.Name = "FlyingEnergy"
	energySymbol.Size = UDim2.new(0, 0, 0, 0) -- startet unsichtbar klein, für den Pop-Effekt
	energySymbol.AnchorPoint = Vector2.new(0.5, 0.5)
	energySymbol.Position = UDim2.new(0, screenPoint.X + sideJump * 0.3, 0, screenPoint.Y - 18)
	energySymbol.BackgroundTransparency = 1
	energySymbol.Font = Enum.Font.LuckiestGuy
	energySymbol.TextScaled = true
	energySymbol.Text = visual.icon .. NumberFormat.Format(amount)
	energySymbol.TextColor3 = visual.color
	energySymbol.TextStrokeColor3 = Color3.new(0, 0, 0)
	energySymbol.TextStrokeTransparency = 0
	energySymbol.ZIndex = 51
	energySymbol.Parent = screenGui

	-- Phase 1: seitlich hüpfen + auf volle Größe aufpoppen (Überschwung-Easing)
	local popTween = TweenService:Create(
		energySymbol,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 84, 0, 44), Position = poppedPosition }
	)

	popTween.Completed:Connect(function()
		-- Phase 2: kurz verweilen, damit man die Zahl lesen kann
		task.delay(0.35, function()
			if not energySymbol.Parent then
				return
			end

			-- Phase 3: erst jetzt Richtung Levelbalken fliegen -- Ziel ist NICHT die Mitte
			-- des Levelrahmens, sondern der aktuelle Füllstand des Fortschrittsbalkens
			-- (rechter Rand von barFill), so sieht man genau, wo die Energie einfließt.
			local targetPosition = UDim2.new(
				0,
				barFill.AbsolutePosition.X + barFill.AbsoluteSize.X,
				0,
				barFill.AbsolutePosition.Y + barFill.AbsoluteSize.Y / 2
			)

			local flightTween = TweenService:Create(
				energySymbol,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = targetPosition }
			)

			flightTween.Completed:Connect(function()
				energySymbol:Destroy()
				if energyArriveSound.SoundId ~= "" and energyArriveSound.SoundId ~= "rbxassetid://0" then
					energyArriveSound.TimePosition = 0
					energyArriveSound:Play()
				end
				onArrive()
			end)

			flightTween:Play()
		end)
	end)

	popTween:Play()
end

-- Statt schnell aufeinanderfolgende Events zu VERWERFEN (das hat bei vielen gleichzeitig
-- beitragenden Energiequellen dazu geführt, dass man nur EINE von z.B. 16 Animationen
-- gesehen hat, obwohl alle Punkte korrekt gezählt wurden): jetzt werden sie in eine
-- Warteschlange gestellt und leicht zeitversetzt nacheinander abgespielt, damit wirklich
-- jeder einzelne Wert sichtbar wird, ohne dass alle exakt gleichzeitig übereinander liegen.
local ENERGY_FLIGHT_STAGGER = 0.08 -- Sekunden Abstand zwischen zwei Animationen
local energyQueue = {} -- { {sourcePosition, amount}, ... }
local isProcessingEnergyQueue = false

local function processEnergyQueue()
	if isProcessingEnergyQueue then
		return
	end
	isProcessingEnergyQueue = true

	task.spawn(function()
		while #energyQueue > 0 do
			local entry = table.remove(energyQueue, 1)
			-- WICHTIG: onArrive löst jetzt tatsächlich das Aufleuchten + Hochzählen der
			-- Level-Anzeige aus -- vorher war das leer, und die Anzeige hat stattdessen
			-- sofort (unabhängig von der Flug-Animation) auf die Server-Werteänderung
			-- reagiert, was sich unsynchronisiert anfühlte.
			spawnFlyingEnergy(entry.sourcePosition, entry.amount, entry.energyType, function()
				advanceXPBar(entry.amount)
			end)
			task.wait(ENERGY_FLIGHT_STAGGER)
		end
		isProcessingEnergyQueue = false
	end)
end

local MAX_ENERGY_QUEUE_LENGTH = 20 -- Sicherheitsgrenze, falls extrem viele Quellen gleichzeitig feuern

EnergyAbsorbEvent.OnClientEvent:Connect(function(sourcePosition, energyType, amount)
	if #energyQueue >= MAX_ENERGY_QUEUE_LENGTH then
		return -- Sicherheitsnetz gegen unrealistisch lange Nachlauf-Animationen
	end
	table.insert(energyQueue, { sourcePosition = sourcePosition, amount = amount, energyType = energyType })
	processEnergyQueue()
end)

-- displayedXP ist der Wert, den der Balken TATSÄCHLICH anzeigt -- bewusst getrennt vom
-- echten Server-Wert (player.XP), damit der Balken erst beim EINTREFFEN der fliegenden
-- Energie-Animation hochzählt (siehe advanceXPBar), statt sofort bei der
-- Server-Werteänderung zu springen.
local displayedXP = nil

-- Zählt den Balken um genau "amount" hoch (mit Aufleucht-Effekt) -- wird NUR vom
-- onArrive-Callback der Flug-Animation aufgerufen, nie direkt bei Server-Änderungen.
function advanceXPBar(amount)
	local xpNeededValue = player:FindFirstChild("XPNeeded")
	local xpValue = player:FindFirstChild("XP")
	if not xpNeededValue or not xpValue then
		return
	end
	if displayedXP == nil then
		displayedXP = xpValue.Value
	end
	-- Nie über den tatsächlichen Server-Wert hinaus zählen (Sicherheitsnetz, falls die
	-- Animation aus irgendeinem Grund öfter ankommt als erwartet).
	displayedXP = math.min(displayedXP + amount, xpValue.Value)

	local needed = math.max(xpNeededValue.Value, 1)
	slideBar(barFill, displayedXP / needed)
	xpLabel.Text = NumberFormat.Format(math.floor(displayedXP)) .. " / " .. NumberFormat.Format(needed)
	flashElement(barFill, Color3.fromRGB(255, 255, 200))
	glowFlashElement(barFill, Color3.fromRGB(255, 255, 150))
end

function updateLevelBar()
	local leaderstats = player:FindFirstChild("leaderstats")
	local xpValue = player:FindFirstChild("XP")
	local xpNeededValue = player:FindFirstChild("XPNeeded")
	if not leaderstats or not xpValue or not xpNeededValue then
		return
	end

	levelLabel.Text = tostring(leaderstats.Level.Value)

	-- Bei einem ECHTEN Sprung (Level-Up, bei dem XP zurückgesetzt/übertragen wird, oder
	-- Debug-Reset) sofort synchronisieren, ohne Aufleucht-Animation -- eine ausstehende
	-- Flug-Animation würde sonst versuchen, über den neuen (kleineren) Zielwert
	-- hinauszuzählen. Im Normalfall (Energie fliegt gerade noch) NICHT eingreifen, das
	-- übernimmt advanceXPBar() beim Eintreffen.
	if displayedXP == nil or xpValue.Value < displayedXP then
		displayedXP = xpValue.Value
		local needed = math.max(xpNeededValue.Value, 1)
		slideBar(barFill, displayedXP / needed)
		xpLabel.Text = NumberFormat.Format(math.floor(displayedXP)) .. " / " .. NumberFormat.Format(needed)
		print("[Kaiju-Debug-Client] updateLevelBar SYNC: Level=", leaderstats.Level.Value, "XP=", xpValue.Value, "XPNeeded=", xpNeededValue.Value, "ratio=", displayedXP / needed)
	end

	-- Cap für die 3 Kraft-Werte -- Arm/Bein nutzen den (um Faktor 100 größeren)
	-- ArmStatCap/LegStatCap, Körper den normalen StatCap.
	for key, ui in pairs(statBars) do
		if not isAnimatingStat[key] then -- läuft gerade eine Flug-Animation, hier nicht eingreifen
			local capAttribute = "StatCap"
			if key == "ArmPower" then
				capAttribute = "ArmStatCap"
			elseif key == "LegPower" then
				capAttribute = "LegStatCap"
			end
			local cap = math.max(player:GetAttribute(capAttribute) or 1, 1)
			local statValue = player:FindFirstChild(key)
			local value = statValue and statValue.Value or 0
			local statRatio = math.clamp(value / cap, 0, 1)
			ui.fill.Size = UDim2.new(statRatio, 0, 1, 0)

			-- Körper-Wert bekommt dieselbe x100-Anzeige-Skalierung wie die Flug-Animation
			-- (spawnFlyingTrainPoint) -- sonst würden Balken-Label und Flug-Zahlen nicht
			-- zusammenpassen (Körper wächst serverseitig absichtlich sehr langsam).
			local displayValue, displayCap = value, cap
			if key == "BodyPower" then
				displayValue, displayCap = value * 100, cap * 100
			end
			-- Nur noch die Zahl: der Name steht jetzt links daneben in einer eigenen
			-- Beschriftung, so wie in den Level- und HP-Feldern.
			ui.label.Text = math.floor(displayValue) .. " / " .. math.floor(displayCap)
			lastStatValues[key] = value
		end
	end
end

-- Vorschau des Skins. Rahmen, Einpassen und Drehen macht ModelPreviewUtils -- dort steht
-- auch, warum die Figur erst mittig ausgerichtet werden muss.
--
-- ===== Warum nicht mehr die feste Kameradistanz =====
-- Frueher stand die Kamera fuer alle sechs Stufen gleich weit weg. Das war Absicht: alle
-- sechs sind derselbe Avatar in sechs Groessen (SkinsConfig tauscht kein Mesh), und die
-- feste Kamera machte diesen Unterschied sichtbar. Der Preis war, dass der Primal Beast als
-- Punkt in einem leeren Rahmen stand -- ein Steckbrief, der nichts zeigt. Die Groesse geht
-- nicht verloren: der Scale-Balken im Steckbrief nennt sie als Zahl UND als Vergleich zum
-- getragenen Skin.
local function buildSkinPreview(container, skin, revealed)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("ViewportFrame") or child:IsA("TextLabel") or child.Name == "PreviewGlow" then
			child:Destroy()
		end
	end

	-- Auch fuer Platzhalter aufgerufen, dann ist `skin` nil -- dieser Zweig braucht ihn nicht.
	if not revealed then
		ModelPreviewUtils.ShowPlaceholder(container)
		return
	end

	-- Erst nach einem ECHTEN Modell fragen. Der Primal Beast hat eines; die übrigen Stufen
	-- noch nicht, dort bleibt es beim Avatar in Skin-Grösse (siehe StageModels).
	-- Abgesichert wie an der anderen Fundstelle: das Modul wird oben per pcall geholt und
	-- kann nil sein. Ohne die Pruefung faellt die ganze Vorschau aus, statt auf den Avatar
	-- zurueckzugehen.
	local realModel = StageModels and StageModels.BuildPreview
		and StageModels.BuildPreview(skin.Faction or "Kaiju", skin.Id) or nil
	if realModel then
		local viewport = ModelPreviewUtils.CreateViewport(container, 2)
		local okReal = pcall(function()
			realModel.Parent = viewport
			ModelPreviewUtils.Fit(viewport, realModel, container)
			ModelPreviewUtils.AddGlow(container, ModelPreviewUtils.FindGlowColor(realModel), 1)
		end)
		if okReal then
			ModelPreviewUtils.Spin(realModel)
			return
		end
		-- Fehlgeschlagen: aufräumen und den Avatar-Weg unten nehmen, statt einen leeren
		-- Rahmen stehen zu lassen.
		viewport:Destroy()
	end

	local pack = Workspace:FindFirstChild("R15AvatarPack")
	local template = pack and pack:FindFirstChildWhichIsA("Model")
	if not template then
		local missing = Instance.new("TextLabel")
		missing.Size = UDim2.new(1, 0, 1, 0)
		missing.BackgroundTransparency = 1
		missing.TextColor3 = Color3.fromRGB(170, 160, 145)
		missing.Text = "no preview"
		missing.Parent = container
		UiTypography.Body(missing)
		return
	end

	local viewport = ModelPreviewUtils.CreateViewport(container, 2)

	local preview
	local ok = pcall(function()
		local model = template:Clone()
		model:ScaleTo(skin.Scale or 1)
		model.Parent = viewport
		ModelPreviewUtils.Fit(viewport, model, container)
		-- Nachgebautes Leuchten aus den Neon-Teilen des Modells. Bei den heutigen
		-- Kaiju-Stufen -- schlichte Avatare ohne Neon -- findet sich keine Farbe, und es
		-- erscheint bewusst kein Schein. Erst echte Modelle bringen einen mit.
		ModelPreviewUtils.AddGlow(container, ModelPreviewUtils.FindGlowColor(model), 1)
		preview = model
	end)
	if not ok then
		viewport:Destroy()
		return
	end

	ModelPreviewUtils.Spin(preview)
end

-- Welcher Skin steht gerade im Steckbrief. Beim Oeffnen der getragene.
local selectedSkinId = nil

-- Ist statt eines echten Skins ein Platzhalter gewaehlt, steht er hier:
-- { faction = <Eintrag aus SkinsConfig.Factions>, index = <Nummer innerhalb der Fraktion> }.
-- Jaeger und Ronin haben noch keine Skins; ihre Plaetze sind trotzdem sichtbar, damit der
-- Bildschirm die Luecke zeigt statt sie zu verschweigen -- so haelt es das Archiv auch.
local selectedPending = nil

-- Hoechstwerte ueber alle Skins -- die Balken zeigen jeden Wert im Verhaeltnis zum
-- staerksten. Einmal berechnet, die Liste aendert sich zur Laufzeit nicht.
local STAT_MAX = { Health = 0, DamagePercent = 0, WalkSpeed = 0, Scale = 0 }
for _, skin in ipairs(SkinsConfig.Skins) do
	for key in pairs(STAT_MAX) do
		STAT_MAX[key] = math.max(STAT_MAX[key], skin[key] or 0)
	end
end

-- Der Kaufgrund als ein Satz: um wie viel diese Stufe haerter zuschlaegt als die
-- Grundform. Frueher stand hier die Level-Obergrenze, die es nicht mehr gibt.
local function attackBonusFor(skin)
	local percent = skin.DamagePercent or 100
	if percent <= 100 then
		return nil
	end
	return "+" .. (percent - 100) .. "% attack power"
end

local function refreshDetail()
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	local leaderstats = player:FindFirstChild("leaderstats")
	local equippedValue = player:FindFirstChild("EquippedSkin")
	if not unlockedFolder or not leaderstats or not equippedValue then
		return
	end
	if selectedPending then
		local faction = selectedPending.faction
		detailName.Text = string.format("%s %s %d", faction.Icon, faction.Label, selectedPending.index)
		detailRole.Text = "Not built yet."
		detailStrength.Text = string.format(
			"%s skins arrive with %s. %s",
			faction.Label, faction.Chapter, faction.UnlockHint or "")
		detailBonus.Visible = false
		-- Balken ausblenden statt auf null setzen: leere Balken haetten "dieser Skin hat
		-- keine Kraft" behauptet, richtig ist "es gibt ihn noch nicht".
		for _, row in pairs(statRows) do
			row.row.Visible = false
		end
		buildSkinPreview(detailViewport, nil, false)
		detailAction.Text = "🔒 " .. faction.Chapter
		detailAction.BackgroundColor3 = Color3.fromRGB(120, 120, 132)
		detailAction.AutoButtonColor = false
		return
	end
	for _, row in pairs(statRows) do
		row.row.Visible = true
	end

	if selectedSkinId == nil then
		selectedSkinId = equippedValue.Value
	end

	local skin = SkinsConfig.GetSkinById(selectedSkinId)
	local equipped = SkinsConfig.GetSkinById(equippedValue.Value)
	if not skin then
		return
	end

	local isUnlocked = unlockedFolder:FindFirstChild("Skin_" .. skin.Id) ~= nil
	local isEquipped = equippedValue.Value == skin.Id
	local meetsLevel = leaderstats.Level.Value >= skin.RequiredLevel
	local canAfford = leaderstats.Coins.Value >= skin.Cost

	detailName.Text = skin.Name
	detailRole.Text = skin.Role or ""
	detailStrength.Text = skin.Strength or ""

	local bonus = attackBonusFor(skin)
	detailBonus.Visible = bonus ~= nil and not isUnlocked
	if bonus then
		detailBonus.Text = "  ⬆  " .. bonus
	end

	for key, row in pairs(statRows) do
		local value = skin[key] or 0
		local maximum = STAT_MAX[key]
		row.fill.Size = UDim2.new(maximum > 0 and (value / maximum) or 0, 0, 1, 0)
		if equipped and equipped.Id ~= skin.Id then
			local diff = value - (equipped[key] or 0)
			row.delta.Text = string.format("%s  (%s%s)", tostring(value), diff >= 0 and "+" or "", tostring(diff))
			row.delta.TextColor3 = diff >= 0 and Color3.fromRGB(40, 140, 60) or Color3.fromRGB(180, 60, 60)
		else
			row.delta.Text = tostring(value)
			row.delta.TextColor3 = Color3.fromRGB(165, 165, 180)
		end
	end

	-- Vorschau: gesperrte Skins zeigen ein Fragezeichen, sonst das Modell.
	buildSkinPreview(detailViewport, skin, isUnlocked or (meetsLevel and canAfford))

	-- EIN Knopf, der sich anpasst. Kaufen und Anlegen sind fuer einen noch nicht
	-- besessenen Skin ohnehin ein Vorgang -- der Server ruestet nach dem Kauf sofort aus.
	if isEquipped then
		detailAction.Text = "✅ Equipped"
		detailAction.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
		detailAction.AutoButtonColor = false
	elseif isUnlocked then
		detailAction.Text = "👕 Wear"
		detailAction.BackgroundColor3 = Color3.fromRGB(70, 150, 235)
		detailAction.AutoButtonColor = true
	elseif not meetsLevel then
		detailAction.Text = "🔒 Level " .. skin.RequiredLevel .. " required"
		detailAction.BackgroundColor3 = Color3.fromRGB(150, 90, 90)
		detailAction.AutoButtonColor = false
	elseif not canAfford then
		detailAction.Text = "🔒 " .. skin.Cost .. " coins needed"
		detailAction.BackgroundColor3 = Color3.fromRGB(160, 160, 160)
		detailAction.AutoButtonColor = false
	else
		detailAction.Text = "💰 Buy for " .. skin.Cost
		detailAction.BackgroundColor3 = Color3.fromRGB(255, 180, 40)
		detailAction.AutoButtonColor = true
	end
end

detailAction.MouseButton1Click:Connect(function()
	if selectedPending then
		return -- ein Platzhalter ist nicht kaufbar
	end
	local skin = SkinsConfig.GetSkinById(selectedSkinId)
	local unlockedFolder = player:FindFirstChild("UnlockedSkins")
	if not skin or not unlockedFolder then
		return
	end
	if unlockedFolder:FindFirstChild("Skin_" .. skin.Id) then
		-- EquipSkinEvent liegt seit jeher vollstaendig im Server und wurde vom Client NIE
		-- gefeuert -- ein getrenntes Anlegen gab es bisher nicht.
		EquipSkinEvent:FireServer(skin.Id)
	else
		PurchaseSkinEvent:FireServer(skin.Id)
	end
end)

local function refreshShop()
	-- AUCH die Ueberschriften wegraeumen, nicht nur die Knoepfe: sie kamen mit der
	-- Gruppierung nach Fraktion dazu und wuerden sich sonst bei jedem Auffrischen doppeln.
	for _, child in ipairs(shopScroll:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local unlockedFolder = player:WaitForChild("UnlockedSkins")
	local leaderstats = player:WaitForChild("leaderstats")
	local equippedSkin = player:WaitForChild("EquippedSkin")

	local order = 0
	for _, faction in ipairs(SkinsConfig.Factions) do
		local skins = SkinsConfig.GetSkinsByFaction(faction.Key)
		local pendingStages = faction.PendingStages or {}
		local pendingCount = #pendingStages
		if #skins == 0 and pendingCount == 0 then
			continue -- eine Fraktion ohne Skins und ohne vorgesehene Plaetze zeigt nichts
		end

		order += 1
		local header = Instance.new("TextLabel")
		header.Name = faction.Key .. "Header"
		header.Size = UDim2.new(1, -4, 0, 26)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.LuckiestGuy
		header.TextScaled = true
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = Color3.fromRGB(255, 205, 90)
		header.Text = faction.Icon .. " " .. faction.Label
		header.LayoutOrder = order
		header.Parent = shopScroll

		for _, skin in ipairs(skins) do
			local isUnlocked = unlockedFolder:FindFirstChild("Skin_" .. skin.Id) ~= nil
			local isEquipped = equippedSkin.Value == skin.Id
			local meetsLevel = leaderstats.Level.Value >= skin.RequiredLevel
			local canAfford = leaderstats.Coins.Value >= skin.Cost

			order += 1
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, -4, 0, 52)
			button.Font = Enum.Font.FredokaOne
			button.TextScaled = true
			button.TextColor3 = Color3.new(1, 1, 1)
			button.LayoutOrder = order
			button.Parent = shopScroll
			applyComicStyle(button, 14, 3)

			if isEquipped then
				button.Text = "✅ " .. skin.Name
				button.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
			elseif isUnlocked then
				button.Text = "👕 Wear " .. skin.Name
				button.BackgroundColor3 = Color3.fromRGB(70, 150, 235)
			elseif not meetsLevel then
				button.Text = "🔒 " .. skin.Name .. " - Level " .. skin.RequiredLevel .. " required"
				button.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
			elseif canAfford then
				button.Text = "💰 " .. skin.Name .. " (" .. skin.Cost .. ")"
				button.BackgroundColor3 = Color3.fromRGB(255, 180, 40)
			else
				button.Text = "🔒 " .. skin.Name .. " (" .. skin.Cost .. ")"
				button.BackgroundColor3 = Color3.fromRGB(160, 160, 160)
			end

			-- Ein Klick WAEHLT nur aus. Gekauft und angelegt wird im Steckbrief.
			button.MouseButton1Click:Connect(function()
				selectedPending = nil
				selectedSkinId = skin.Id
				refreshDetail()
			end)
		end

		-- Vorgesehene, aber noch nicht gebaute Plaetze. Anwaehlbar, damit der Steckbrief
		-- erklaeren kann, woran es haengt -- kaufbar sind sie nicht.
		for index = 1, pendingCount do
			order += 1
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, -4, 0, 52)
			button.Font = Enum.Font.FredokaOne
			button.TextScaled = true
			button.TextColor3 = Color3.fromRGB(200, 200, 210)
			button.BackgroundColor3 = Color3.fromRGB(52, 52, 62)
			-- Der geplante Name statt "Jaeger 3". Das Fragezeichen bleibt davor: der Platz ist
			-- weiterhin leer, er hat nur schon einen Namen.
			button.Text = string.format("? %s - %s", pendingStages[index] or faction.Label, faction.Chapter)
			button.LayoutOrder = order
			button.Parent = shopScroll
			applyComicStyle(button, 14, 3)

			button.MouseButton1Click:Connect(function()
				selectedPending = { faction = faction, index = index }
				refreshDetail()
			end)
		end
	end

	refreshDetail()
end

-- Erst auf ALLE benötigten Werte warten (blockierend), damit die erste Anzeige garantiert
-- die echten, geladenen Werte zeigt -- statt kurz "Level 0"/"0 Coins" anzuzeigen und erst
-- beim nächsten Ereignis (z.B. erster Schaden) zu korrigieren.
player:WaitForChild("leaderstats")
player:WaitForChild("leaderstats"):WaitForChild("Coins")
player:WaitForChild("leaderstats"):WaitForChild("Level")
player:WaitForChild("XP")
player:WaitForChild("XPNeeded")
player:WaitForChild("LegPower")
player:WaitForChild("ArmPower")
player:WaitForChild("BodyPower")
player:WaitForChild("UnlockedSkins")
player:WaitForChild("EquippedSkin")

updateCoinsLabel()
updateLevelBar()
refreshShop()

player:WaitForChild("leaderstats"):WaitForChild("Coins"):GetPropertyChangedSignal("Value"):Connect(function()
	updateCoinsLabel()
	refreshShop()
end)
-- Der zuletzt ANGEZEIGTE Stand. Ohne ihn liesse sich ein Aufstieg nicht von einem
-- Rueckfall unterscheiden -- und das Zaehlwerk soll nur nach oben ruecken, nicht beim
-- Debug-Reset auf 0 oder beim Prolog-Ende rueckwaerts durchlaufen.
-- Ohne WaitForChild: auf leaderstats.Level wurde weiter oben bereits blockierend
-- gewartet, hier ist es also garantiert da.
local zuletztGezeigtesLevel = player.leaderstats.Level.Value

player:WaitForChild("leaderstats").Level:GetPropertyChangedSignal("Value"):Connect(function()
	local vorher = zuletztGezeigtesLevel
	zuletztGezeigtesLevel = player.leaderstats.Level.Value

	updateLevelBar()
	refreshShop()

	-- Waehrend des Prologs laeuft eine eigene, kuenstliche Levelfuehrung (siehe
	-- PrologueOrchestrator) -- die soll das Zaehlwerk nicht ausloesen.
	if zuletztGezeigtesLevel > vorher and player:GetAttribute("IsInPrologue") ~= true then
		playLevelTick(tostring(vorher))
	end

-- Beim Oeffnen steht der GETRAGENE Skin im Steckbrief, nicht der zuletzt angetippte.
--
-- MUSS hier unten stehen: selectedSkinId und refreshShop werden erst weiter oben in dieser
-- Datei deklariert. Weiter vorne haetten die Namen auf nicht existierende globale
-- Variablen aufgeloest -- die Zuweisung waere ins Leere gelaufen, ohne Fehlermeldung.
shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if shopFrame.Visible then
		local equippedValue = player:FindFirstChild("EquippedSkin")
		if equippedValue then
			selectedSkinId = equippedValue.Value
		end
		-- Beim Oeffnen immer beim getragenen Skin beginnen. Ohne das haette ein zuletzt
		-- angeklickter Platzhalter die naechste Sitzung des Bildschirms eroeffnet.
		selectedPending = nil
		refreshShop()
	end
end)
	-- Der Blitz sitzt auf dem XP-Balken und der Stufenzahl, nicht auf dem Feld: dessen
	-- Flaeche besteht seit dem Umbau aus einzelnen Streifen, und der Rahmen darum ist
	-- durchsichtig. flashElement faerbt Hintergruende -- auf dem Feld wuerde es also eine
	-- sonst unsichtbare Flaeche sichtbar machen, statt etwas aufleuchten zu lassen.
	flashElement(barBackground, Color3.fromRGB(92, 82, 40))
	glowFlashElement(barFill, Color3.fromRGB(255, 235, 150))
end)
local leaderstatsFolder = player:WaitForChild("leaderstats")
leaderstatsFolder:WaitForChild("Level"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("XP"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("XPNeeded"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("LegPower"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("ArmPower"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:WaitForChild("BodyPower"):GetPropertyChangedSignal("Value"):Connect(updateLevelBar)
player:GetAttributeChangedSignal("StatCap"):Connect(updateLevelBar)
player:WaitForChild("UnlockedSkins").ChildAdded:Connect(refreshShop)
player:WaitForChild("EquippedSkin"):GetPropertyChangedSignal("Value"):Connect(refreshShop)

-- ===== Selbstauskunft: warum ist etwas nicht zu sehen? =====
--
-- Gemeldet: Level-/HP-Feld und Tacho fehlen beide. Beide entstehen in DIESER Datei, also
-- kommen nur drei Ursachen in Frage: das Skript ist vorher abgebrochen, die Elemente sind
-- auf unsichtbar gesetzt, oder sie sind da und werden mit Groesse null gezeichnet.
--
-- Der Block unterscheidet alle drei auf einmal. Erscheint er gar nicht, ist das Skript
-- vorher gestorben -- dann steht der Grund als roter Fehler darueber.
--
-- WICHTIG dabei: beide Anzeigen sind in der Sanctuary-Zone ABSICHTLICH ausgeblendet
-- (statusCluster ganz, der Tacho ausser beim Training). Das ist kein Fehler, sondern eine
-- alte Entscheidung -- die Zeile "Zone" unten sagt, ob sie gerade greift.
task.delay(3, function()
	local zone = player:GetAttribute("CurrentZone")
	print(string.format(
		"[Kaiju Debug] HUD-Auskunft -- Zone %s, Stadt %s, Training %s.",
		tostring(zone),
		tostring(player:GetAttribute("CurrentCityName")),
		tostring(player:GetAttribute("TrainingStat"))
	))

	local function melde(name, gui)
		if not gui or not gui.Parent then
			warn("[Kaiju Debug]   " .. name .. ": NICHT VORHANDEN")
			return
		end
		print(string.format(
			"[Kaiju Debug]   %s: sichtbar=%s, %d x %d Pixel bei (%d, %d)",
			name,
			tostring(gui.Visible),
			gui.AbsoluteSize.X,
			gui.AbsoluteSize.Y,
			gui.AbsolutePosition.X,
			gui.AbsolutePosition.Y
		))
	end

	print("[Kaiju Debug]   GameHud aktiv: " .. tostring(screenGui.Enabled))
	melde("PlayerStatusCluster", statusCluster)
	melde("LevelField", levelField)
	melde("HealthField", healthField)
	melde("HeatFrame", heatFrame)
	melde("Needle", tacho.needlePivot)
end)
