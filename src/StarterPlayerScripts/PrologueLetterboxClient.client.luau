-- VERSION: 2026-08-26 #3
-- LocalScript: PrologueLetterboxClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Zeigt schwarze, kinoartige Filmstreifen (oben/unten) UND blendet das komplette HUD aus
-- -- AUSSER der Lebensanzeige, die sichtbar bleibt -- beides synchron ausgelöst, sobald
-- der Kaiju beginnt, kontinuierlich Leben zu verlieren ("The Fall", siehe
-- PrologueOrchestrator.lua -- SetPrologueLetterboxEvent), nicht schon beim Prolog-Start.
-- Beides wird wieder eingeblendet/entfernt, sobald der Spieler am Ende die volle
-- Kontrolle zurückerhält.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))
local LetterboxUtils = require(ReplicatedStorage:WaitForChild("LetterboxUtils"))
local SetPrologueLetterboxEvent = RemoteEventUtils.GetOrCreate("SetPrologueLetterboxEvent")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Die Balken selbst kommen aus LetterboxUtils. Sie lagen frueher hier, ein zweites Mal in
-- der Trainingskamera und mit dem Showdown waeren es drei geworden -- jedes Mal mit
-- anderer Hoehe, anderer Blende und anderem DisplayOrder.
--
-- Die Werte bleiben unveraendert: 9 % Balkenhoehe, 0,6 s Blende, und "fade" -- die Balken
-- stehen in voller Hoehe und werden durchsichtig ein- und ausgeblendet. Das Aussehen des
-- Prologs ist abgenommen und aendert sich hier nicht.
--
-- Das HUD-Ausblenden bleibt DAGEGEN hier: es ist prologspezifisch. Der Showdown blendet
-- bewusst fast nichts aus, weil dort weitergekaempft wird.
local letterbox = LetterboxUtils.Create(playerGui, "PrologueLetterboxGui", {
	heightFraction = 0.09,
	fadeDuration = 0.6,
	style = "fade",
	easingStyle = Enum.EasingStyle.Sine,
	easingDirection = Enum.EasingDirection.InOut,
	displayOrder = 40, -- unter der Warteschlangen-Anzeige (50), ueber dem normalen HUD
})

-- Andere HUD-ScreenGuis (nicht Health-bezogen), die komplett aus-/eingeblendet werden --
-- siehe die jeweiligen LocalScripts für die genauen Namen.
local OTHER_HUD_GUI_NAMES = {
	"SpecialAttackGui", -- Punch/Sprung/Fokus/Area-Buttons
	"CityAlertHudGui", -- Alert-Level-Anzeige
	"EnergyTypesGui", -- Energie-Typ-Legende
	"NavigationGui", -- Kompass/Karte
	"EnergyAbsorbGui", -- Absorptions-Eingabe-Hinweis
}

-- Namen der Kind-Elemente von "GameHud", die zusammen mit Health im selben Cluster
-- liegen (siehe SkinSelectionGui.lua -- "PlayerStatusCluster" enthält Level + Health +
-- XP-Bar zusammen) -- nur diese beiden werden versteckt, "HealthFrame" bleibt sichtbar.
local STATUS_CLUSTER_HIDE_NAMES = { "LevelLabel", "BarBackground" }

local function setVisible(visible)
	letterbox.SetVisible(visible)

	local hudShouldBeVisible = not visible

	-- Haupt-HUD (GameHud): alle direkten Kind-Elemente ausblenden AUSSER dem Status-
	-- Cluster -- dort wiederum nur Level/XP verstecken, die Health-Bar bleibt immer
	-- sichtbar.
	local gameHud = playerGui:FindFirstChild("GameHud") or playerGui:WaitForChild("GameHud", 3)
	if gameHud then
		for _, child in ipairs(gameHud:GetChildren()) do
			if child.Name == "PlayerStatusCluster" then
				for _, subName in ipairs(STATUS_CLUSTER_HIDE_NAMES) do
					local subChild = child:FindFirstChild(subName)
					if subChild then
						subChild.Visible = hudShouldBeVisible
					end
				end
			elseif child:IsA("GuiObject") then
				child.Visible = hudShouldBeVisible
			end
		end
	end

	-- Andere HUD-ScreenGuis komplett aus-/einblenden.
	for _, guiName in ipairs(OTHER_HUD_GUI_NAMES) do
		local gui = playerGui:FindFirstChild(guiName)
		if gui then
			gui.Enabled = hudShouldBeVisible
		end
	end
end

SetPrologueLetterboxEvent.OnClientEvent:Connect(function(visible)
	setVisible(visible)
end)