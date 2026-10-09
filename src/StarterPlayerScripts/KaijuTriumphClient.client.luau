-- LocalScript: KaijuTriumphClient
--
-- Der Siegesbrüller, sobald eine Stadt CITY BROKEN ist.
--
-- Die Animation kommt aus dem Asset-Workshop (KaijuCityBreakTriumph, gilt für alle fünf
-- Stufen): 5,1 Sekunden, die Figur richtet sich auf, öffnet die Brust, brüllt nach oben und
-- hält eine beherrschende Pose. Ihre Spezifikation nennt als Anlass ausdrücklich
-- "CityBroken" -- sie ist genau dafür gebaut und für nichts anderes.
--
-- ===== Warum das hier auf dem CLIENT steht und nicht im CityBrokenService =====
-- Die Spezifikation des Pakets nennt als Server-Schnittstelle "controller.RequestVictory()".
-- Die gibt es so nicht: der Installer reicht nur sieben Methoden nach aussen
-- (RequestAttack, RequestJump, SetAirDirection, RequestFocus, RequestArea, SetRunning,
-- GetCombatFrame) -- RequestVictory fehlt in dieser Liste, obwohl das Rig sie hat. Auch das
-- Rig-Modul selbst gibt seine Registry nicht heraus.
--
-- Erreichbar ist der Brüller deshalb nur über das RemoteEvent, das sich das Rig selbst ans
-- Modell hängt. Das ist ein Client-zu-Server-Ereignis; der Server kann es nicht an sich
-- selbst senden. Also meldet der Client. Sicher ist das trotzdem: das Rig nimmt die Anfrage
-- nur vom Besitzer der Figur an, und ob die Stadt wirklich gebrochen ist, steht in einem
-- Wert, den ausschliesslich der Server setzt.
--
-- (Die Lücke im Paket ist dem Workshop gemeldet. Taucht RequestVictory später in der
-- Installer-Liste auf, gehört das hier in den CityBrokenService -- dann ohne Umweg.)
--
-- ===== Warum es wiederholt versucht =====
-- Das Rig lehnt den Brüller ab, solange die Figur springt, schwimmt, keinen Boden unter
-- sich hat oder gerade ein Special läuft. Genau das ist im Moment von CITY BROKEN
-- wahrscheinlich: die Stadt bricht, weil der Spieler eben etwas zerstört hat, und das tut
-- er oft aus dem Sprung. Ein einzelner Versuch ginge deshalb häufig ins Leere.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local StageModels = require(ReplicatedStorage:WaitForChild("StageModels", 30))

-- Wie lange nach dem Bruch noch versucht wird, und wie oft. Vier Sekunden decken eine
-- Sprunglandung und das Auslaufen eines Specials ab; das Fenster der freien Zerstörung
-- dauert 75 Sekunden, es bleibt danach also reichlich Zeit übrig.
local VERSUCHSDAUER = 4
local VERSUCHSABSTAND = 0.25
-- Nach dem Melden kurz warten, bevor geprüft wird, ob es angenommen wurde: die Antwort
-- kommt als Attribut vom Server zurück und braucht einen Netzwerk-Umlauf.
local ANTWORTFRIST = 0.2

local laeuft = false

local function versucheTriumph(cityName)
	if laeuft then
		return
	end
	laeuft = true

	local ende = os.clock() + VERSUCHSDAUER
	local versuche = 0

	repeat
		local model = StageModels.FindEquipped(player.Character)
		local remote = model and model:FindFirstChild("RequestVictory")

		if model and model:GetAttribute("VictoryState") == "Playing" then
			print(string.format("[Kaiju Debug] Triumph laeuft (%s, nach %d Versuch(en)).",
				cityName, versuche))
			laeuft = false
			return
		end

		if remote then
			versuche += 1
			remote:FireServer()
			task.wait(ANTWORTFRIST)
		else
			-- Kein Modell: blosser Avatar (Debug-Schalter) oder noch nicht angezogen.
			task.wait(VERSUCHSABSTAND)
		end
	until os.clock() >= ende

	laeuft = false
	if versuche == 0 then
		print("[Kaiju Debug] Triumph uebersprungen: kein Kaiju-Modell an der Figur.")
	else
		warn(string.format("[Kaiju Debug] Triumph (%s) nach %d Versuchen nicht angenommen -- "
			.. "das Rig lehnt ab, solange gesprungen, geschwommen oder ein Special gespielt wird.",
			cityName, versuche))
	end
end

local function beobachte(wert)
	if not wert:IsA("BoolValue") then
		return
	end
	local cityName = wert.Name:match("^(.-)CityBroken$")
	if not cityName then
		return
	end

	wert.Changed:Connect(function(gebrochen)
		-- Nur für den Spieler, der auch dort steht. Wer gerade im Sanctuary trainiert,
		-- soll nicht grundlos brüllen.
		if gebrochen and player:GetAttribute("CurrentCityName") == cityName then
			task.spawn(versucheTriumph, cityName)
		end
	end)
end

-- ===== Auf Tastendruck, nicht nur bei CITY BROKEN (05.10.2026) =====
-- Der Brüller hatte eine Taste, aber an der falschen Stelle: in den Client-Dateien des
-- Asset-Pakets. Beide gingen ins Leere.
--
-- KaijuStageOneControls hätte die richtige Belegung, läuft im Spiel aber überhaupt nicht --
-- sie wird von niemandem installiert. Der Installer klont nur KaijuStageOneInput, und auch
-- das bloss bei InstallInput; der KaijuStageOneService setzt es ausdrücklich auf false, weil
-- die Eingabe des Pakets mit der des Spiels kollidiert.
--
-- Der Weg, der tatsächlich lief, war der Vorschau-Zweig in KaijuPresentationClient -- und
-- der hängt hinter "if RunService:IsStudio()". Die Taste gab es also nur in Studio; auf
-- einem echten Server hat sie nie funktioniert.
--
-- Deshalb steht sie jetzt hier: im Repo, neben dem Anlass, der denselben Brüller auslöst,
-- über dasselbe Remote. Das übersteht auch ein Workshop-Update, das die Paketdateien
-- ersetzt.
local UserInputService = game:GetService("UserInputService")

local BRUELL_TASTE = Enum.KeyCode.Y

-- Gegen Dauerfeuer: der Brüller läuft 5,1 Sekunden, und versucheTriumph sperrt sich zwar
-- selbst über "laeuft" -- aber erst nachdem es seine vier Sekunden lang versucht hat. Ohne
-- eigene Sperre liesse ein gehaltener Finger die Versuche aneinanderreihen.
local TASTEN_SPERRE = 6
local letzterBruellerAt = -math.huge

UserInputService.InputBegan:Connect(function(input, verarbeitet)
	if verarbeitet or input.KeyCode ~= BRUELL_TASTE then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if os.clock() - letzterBruellerAt < TASTEN_SPERRE then
		return
	end
	letzterBruellerAt = os.clock()
	-- "auf Tastendruck" als Anlass: derselbe Weg wie bei CITY BROKEN, nur ohne Stadt.
	task.spawn(versucheTriumph, "auf Tastendruck")
end)

local cityAlertValues = ReplicatedStorage:WaitForChild("CityAlertValues", 60)
if not cityAlertValues then
	warn("[Kaiju Debug] Triumph: 'CityAlertValues' nicht gefunden -- der Siegesbrueller bleibt "
		.. "bei CITY BROKEN aus. Die Taste " .. BRUELL_TASTE.Name .. " funktioniert trotzdem.")
	return
end

for _, wert in ipairs(cityAlertValues:GetChildren()) do
	beobachte(wert)
end
cityAlertValues.ChildAdded:Connect(beobachte)

print("[Kaiju Debug] Triumph bereit -- Siegesbrueller bei CITY BROKEN und auf Taste "
	.. BRUELL_TASTE.Name .. ".")
