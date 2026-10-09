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

-- ScreenGuis, die NUR in der Abschlusssequenz verschwinden, nicht schon bei "The Fall".
--
-- Das Debug-Panel ist Amancios Hauptwerkzeug; waehrend des Prologs soll der Knopf
-- erreichbar bleiben, damit ein Durchlauf jederzeit zu steuern ist. In der Schlusssequenz
-- steht er dagegen mitten im Bild, waehrend nur noch Text laufen soll.
local FINALE_ONLY_GUI_NAMES = {
	"DebugPanelGui", -- Debug-Knopf und Panel
}

-- Namen der Kind-Elemente von "GameHud", die zusammen mit Health im selben Cluster
-- liegen (siehe SkinSelectionGui.lua -- "PlayerStatusCluster" enthält Level + Health +
-- XP-Bar zusammen) -- nur diese beiden werden versteckt, "HealthFrame" bleibt sichtbar.
local STATUS_CLUSTER_HIDE_NAMES = { "LevelLabel", "BarBackground" }

-- ===== Warum das Verstecken nicht von allein haelt =====
-- Dieses Skript setzt die Sichtbarkeit EINMAL, beim Umschalten. Andere HUD-Skripte setzen
-- sie dagegen fortlaufend nach, wenn sich etwas an der Lage aendert -- SkinSelectionGui
-- etwa haengt an "CurrentZone" und macht den Tacho bei jedem Zonenwechsel wieder sichtbar.
--
-- Genau das geschah in der Abschlusssequenz: kaum war alles verborgen, spawnte der Spieler
-- im Sanctuary, die Zone sprang um, und der Tacho stand wieder im schwarzen Bild
-- (beobachtet am 22.09.2026). "IsInPrologue" taugt dort nicht als Gegenmittel -- der Prolog
-- setzt es auf false, bevor die Textkarten ueberhaupt anfangen.
--
-- Deshalb dieses Merkmal am GameHud: solange es steht, darf kein HUD-Skript etwas
-- einblenden. Es haengt am GameHud und nicht am Spieler, weil es rein oertlich ist -- der
-- Server hat damit nichts zu tun und soll auch nichts davon mitbekommen.
local HUD_HIDDEN_ATTRIBUTE = "HudHiddenByPrologue"

-- ===== Zwei Stufen des Ausblendens =====
-- "The Fall" versteckt das HUD, laesst aber die Lebensanzeige stehen -- der Spieler soll
-- sein Leben schwinden SEHEN, das ist der Inhalt der Szene.
--
-- Die Abschlusssequenz im Sanctuary will dagegen gar nichts: dort laufen nur Text und
-- Kapitel-Karte, und das HUD gehoert erst danach wieder her. Dafuer "allesVerstecken".
--
-- IM SPIEL BESTAETIGT am 21.09.2026: "Bei der Abschlusssequenz, wo der Spieler im Prolog
-- wieder im Sanctuary ist, darf noch keine HUD gezeigt werden. Nur der Text."
local function setVisible(visible, allesVerstecken)
	letterbox.SetVisible(visible)

	local hudShouldBeVisible = not visible

	-- Haupt-HUD (GameHud): alle direkten Kind-Elemente ausblenden AUSSER dem Status-
	-- Cluster -- dort wiederum nur Level/XP verstecken, die Health-Bar bleibt immer
	-- sichtbar.
	local gameHud = playerGui:FindFirstChild("GameHud") or playerGui:WaitForChild("GameHud", 3)
	if gameHud then
		for _, child in ipairs(gameHud:GetChildren()) do
			if child.Name == "PlayerStatusCluster" then
				if allesVerstecken or hudShouldBeVisible then
					-- Der ganze Block auf einmal. Beim Wiedereinblenden ebenfalls, sonst
					-- bliebe er nach einem "allesVerstecken" fuer immer weg.
					child.Visible = hudShouldBeVisible
				else
					for _, subName in ipairs(STATUS_CLUSTER_HIDE_NAMES) do
						local subChild = child:FindFirstChild(subName)
						if subChild then
							subChild.Visible = hudShouldBeVisible
						end
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

	-- Die nur in der Abschlusssequenz: bei "The Fall" bleiben sie stehen.
	for _, guiName in ipairs(FINALE_ONLY_GUI_NAMES) do
		local gui = playerGui:FindFirstChild(guiName)
		if gui then
			gui.Enabled = hudShouldBeVisible or not allesVerstecken
		end
	end

	-- ZULETZT, nicht zuerst: andere Skripte haengen an diesem Merkmal und stellen ihre
	-- eigene Sichtbarkeit her, sobald es faellt. Stuende es am Anfang, liefe das gegen die
	-- Schleifen darueber -- und beim Einblenden gewaenne die falsche Seite.
	if gameHud then
		gameHud:SetAttribute(HUD_HIDDEN_ATTRIBUTE, not hudShouldBeVisible or nil)
	end
end

SetPrologueLetterboxEvent.OnClientEvent:Connect(function(visible, allesVerstecken)
	setVisible(visible, allesVerstecken)
end)