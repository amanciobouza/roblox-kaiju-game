-- LocalScript: BoostStatusClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Zeigt laufende Boosts im HUD: wie lange noch, und wie stark.
--
-- ===== Warum es das bisher nicht gab =====
-- Die Boosts kommen aus den Zeitgeschenken (GiftHandler) und sind reine Attribute am
-- Spieler: CoinsBoostMultiplier/EndsAt und DamageBoostMultiplier/EndsAt. Sie wirkten
-- serverseitig -- doppelte Münzen beim Zerstören (HouseHandler), doppelter Schaden bei der
-- Stärkeberechnung (PlayerSetup) -- aber im Bild kam davon nichts vor.
--
-- Das ist der schlechteste Zustand für eine zeitlich begrenzte Belohnung: sie läuft ab,
-- während man nicht weiß, dass sie läuft. Wer nicht weiß, dass er gerade doppelt
-- verdient, spielt nicht anders -- und der Boost hat dann nichts bewirkt außer einer Zahl,
-- die er sowieso nicht nachrechnet.
--
-- ===== Warum ein eigenes Skript =====
-- Der Platz gehört zum HUD, und der wäre in SkinSelectionGui. Diese Datei steht aber dicht
-- an Luaus Grenze von 200 gleichzeitig lebenden lokalen Variablen (siehe den do-Block um
-- den Tacho dort) -- ein weiterer Block hätte sie wieder darüber gedrückt. Ein eigenes
-- Skript kostet ein ScreenGui und hat dafür seinen eigenen Registersatz.
--
-- ===== Warum oben mittig =====
-- Nach der Zonenregel gehört die Mitte oben dem eigenen Zustand: Level und Leben stehen
-- dort. Ein laufender Boost IST eigener Zustand -- er sagt, was man selbst gerade kann,
-- nicht was in der Welt gilt. Deshalb direkt unter die Statusfelder und nicht in die
-- rechte Spalte, wo steht, was die Welt gerade tut.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HudChrome = require(ReplicatedStorage:WaitForChild("HudChrome"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Unterkante der Statusfelder (8 + 62) plus vier Pixel Luft. Die Felder stehen in
-- SkinSelectionGui; die Zahl hier ist bewusst eine Kopie und keine geteilte Konstante --
-- geteilt würde sie dieses Skript an das größte des Projekts binden, und sie ändert sich
-- seltener als einmal pro Umbau.
local REIHE_Y = 74
local CHIP_HOEHE = 34
local CHIP_LUECKE = 8
local SYMBOL = 22

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BoostStatusGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- AutomaticSize statt fester Breite: wie viele Chips stehen, hängt davon ab, was gerade
-- läuft -- beim MegaBoost sind es zwei, sonst einer oder keiner. Mit fester Breite stünde
-- die Reihe bei einem einzelnen Chip außermittig.
local reihe = Instance.new("Frame")
reihe.Name = "BoostRow"
reihe.AnchorPoint = Vector2.new(0.5, 0)
reihe.Position = UDim2.new(0.5, 0, 0, REIHE_Y)
reihe.Size = UDim2.new(0, 0, 0, CHIP_HOEHE)
reihe.AutomaticSize = Enum.AutomaticSize.X
reihe.BackgroundTransparency = 1
reihe.Parent = screenGui

local reiheLayout = Instance.new("UIListLayout")
reiheLayout.FillDirection = Enum.FillDirection.Horizontal
reiheLayout.SortOrder = Enum.SortOrder.LayoutOrder
reiheLayout.Padding = UDim.new(0, CHIP_LUECKE)
reiheLayout.Parent = reihe

-- Baut einen Chip. Er bleibt stehen und wird nur ein- und ausgeblendet -- ein Chip, der
-- bei jedem Bild neu entsteht, flackert und kostet Instanzen im Sekundentakt.
local function baueChip(order, iconKey, kuerzel)
	local chip = Instance.new("Frame")
	chip.Name = kuerzel .. "Boost"
	chip.Size = UDim2.new(0, 138, 0, CHIP_HOEHE)
	chip.LayoutOrder = order
	chip.Visible = false
	chip.Parent = reihe
	local _, rand = HudChrome.Panel(chip, {
		radius = HudChrome.Radius.Small,
		fill = HudChrome.Color.PanelRaised,
		transparency = 0.1,
	})
	rand.Color = HudChrome.Color.Ready

	-- Das Bild aus HudChrome.GiftIcon: dasselbe, das auf der Zeitachse an dieser Station
	-- steht. So ist ohne Text zu erkennen, WELCHES Geschenk gerade läuft.
	local bild = Instance.new("ImageLabel")
	bild.Size = UDim2.new(0, SYMBOL, 0, SYMBOL)
	bild.Position = UDim2.new(0, 8, 0.5, -SYMBOL / 2)
	bild.BackgroundTransparency = 1
	bild.ScaleType = Enum.ScaleType.Fit
	bild.Image = HudChrome.GiftIcon[iconKey] or ""
	bild.Visible = bild.Image ~= ""
	bild.Parent = chip

	local faktor = Instance.new("TextLabel")
	faktor.Name = "Factor"
	faktor.Size = UDim2.new(0, 56, 1, 0)
	faktor.Position = UDim2.new(0, 36, 0, 0)
	faktor.BackgroundTransparency = 1
	faktor.TextXAlignment = Enum.TextXAlignment.Left
	faktor.Text = ""
	faktor.Parent = chip
	HudChrome.NumberBold(faktor, 17)
	faktor.TextColor3 = HudChrome.Color.Ready

	-- Rechtsbündig, damit die Sekundenstelle beim Herunterzählen stehen bleibt. Bei einem
	-- Wert, der jede Sekunde springt, ist das der Unterschied zwischen ruhig und zappelig.
	local rest = Instance.new("TextLabel")
	rest.Name = "Remaining"
	rest.Size = UDim2.new(0, 52, 1, 0)
	rest.Position = UDim2.new(1, -60, 0, 0)
	rest.BackgroundTransparency = 1
	rest.TextXAlignment = Enum.TextXAlignment.Right
	rest.Text = ""
	rest.Parent = chip
	HudChrome.Number(rest, 16)
	rest.TextColor3 = HudChrome.Color.TextSecondary

	return { chip = chip, rand = rand, faktor = faktor, rest = rest }
end

local coinsChip = baueChip(1, "CoinsBoost", "Coins")
local damageChip = baueChip(2, "DamageBoost", "Damage")

local function formatRest(seconds)
	seconds = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Die letzten zehn Sekunden pulsiert der Rand.
--
-- Ein Boost, der ausläuft, ist eine Information mit einer Frist -- und eine Zahl, die
-- kleiner wird, übersieht man neben allem anderen im Bild. Bewusst kein hartes Blinken:
-- das läse sich als Störung. Ein weicher Sinus sagt "gleich vorbei", ohne zu alarmieren.
local ABLAUF_WARNUNG = 10

local function zeigeChip(eintrag, faktorWert, endetBei, jetzt)
	local rest = (endetBei or 0) - jetzt
	if not faktorWert or faktorWert <= 1 or rest <= 0 then
		eintrag.chip.Visible = false
		return false
	end

	eintrag.chip.Visible = true
	eintrag.faktor.Text = string.format("%dx", faktorWert)
	eintrag.rest.Text = formatRest(rest)

	if rest <= ABLAUF_WARNUNG then
		local puls = 0.5 + 0.5 * math.sin(jetzt * 6)
		eintrag.rand.Color = HudChrome.Color.Ready:Lerp(HudChrome.Color.Danger, puls)
		eintrag.rest.TextColor3 = HudChrome.Color.Danger
	else
		eintrag.rand.Color = HudChrome.Color.Ready
		eintrag.rest.TextColor3 = HudChrome.Color.TextSecondary
	end
	return true
end

RunService.Heartbeat:Connect(function()
	local jetzt = Workspace:GetServerTimeNow()
	local coinsAktiv = zeigeChip(
		coinsChip,
		player:GetAttribute("CoinsBoostMultiplier"),
		player:GetAttribute("CoinsBoostEndsAt"),
		jetzt
	)
	local damageAktiv = zeigeChip(
		damageChip,
		player:GetAttribute("DamageBoostMultiplier"),
		player:GetAttribute("DamageBoostEndsAt"),
		jetzt
	)
	-- Die ganze Reihe verschwindet, wenn nichts läuft. Ohne das bliebe ein leerer Rahmen
	-- mittig über dem Bild stehen -- ein Element, das nichts anzeigt, ist schlimmer als
	-- keines, weil man es trotzdem ansieht.
	reihe.Visible = coinsAktiv or damageAktiv
end)
