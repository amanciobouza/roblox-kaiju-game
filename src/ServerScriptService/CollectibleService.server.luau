-- Script: CollectibleService
-- Ort in Studio: ServerScriptService
--
-- Die Fundstücke von Kapitel I. Bricht eine Stadt, werden fünf ihrer Gebäude markiert; in
-- einem davon liegt ihr Gegenstand. Der Spieler hat das Fenster der freien Zerstörung, um
-- ihn zu finden -- danach ist er weg.
--
-- Welcher Gegenstand zu welcher Stadt gehört und alle Zahlen stehen in CollectibleConfig.
--
-- ===== Warum der Träger VORHER feststeht =====
-- Die Alternative wäre, beim Zerstören zu würfeln. Das wäre dasselbe Erlebnis und wäre
-- trotzdem falsch: ein Würfel beim Öffnen kann dem Spieler das Fundstück im letzten
-- Gebäude geben, nachdem er vier leere abgeräumt hat -- oder im ersten. Steht der Träger
-- vorher fest, ist die Verteilung über viele Durchläufe dieselbe, aber ein einzelner
-- Durchlauf ist nicht mehr manipulierbar: niemand kann die Reihenfolge so wählen, dass das
-- Fundstück wandert. Und das Attribut am Gebäude lässt sich in Studio nachsehen.
--
-- ===== Was hier NICHT passiert =====
-- Die Zeremonie beim Fund. Dieser Dienst meldet den Fund an den Client und ist damit
-- fertig; die Kamerafahrt und das schwebende Stück gehören zur Darstellung.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local function holen(eltern, name)
	local modul = eltern:WaitForChild(name, 20)
	if not modul then
		error(string.format("CollectibleService: %q liegt nicht in %s. Hat Rojo synchronisiert?",
			name, eltern:GetFullName()), 0)
	end
	return modul
end

local CollectibleConfig = require(holen(ReplicatedStorage, "CollectibleConfig"))
local RemoteEventUtils = require(holen(ReplicatedStorage, "RemoteEventUtils"))
local StageModels = require(holen(ReplicatedStorage, "StageModels"))

local CollectibleFoundEvent = RemoteEventUtils.GetOrCreate("CollectibleFoundEvent")

-- Die gemounteten Workshop-Modelle. Mit Zeitgrenze und mit Meldung: fehlt der Ordner, weil
-- das Submodul nicht synchronisiert ist, soll das EINMAL deutlich dastehen -- und nicht
-- fünf Mal still scheitern, wenn jemand eine Stadt bricht.
local modellOrdner = ReplicatedStorage:WaitForChild(CollectibleConfig.FolderName, 30)
if not modellOrdner then
	warn(string.format("[Kaiju] CollectibleService: %q fehlt in ReplicatedStorage -- es wird kein "
		.. "Fundstueck erscheinen. Ist das Workshop-Submodul synchronisiert (collectibles-package "
		.. "in default.project.json)?", CollectibleConfig.FolderName))
end

local HOUSE_TAG = _G.HOUSE_TAG or "KaijuHouse"

-- [cityName] = { kandidaten = {house,...}, traeger = house, stueck = Model|nil, bis = os.clock() }
local laufende = {}

-- ===== Welche Gebäude in Frage kommen =====
-- Nur STEHENDE: ein Fundstück in einem Haus, das schon in Trümmern liegt, wäre für den
-- Spieler unerreichbar -- er kann es nicht noch einmal zerstören.
local function kandidatenFinden(cityName)
	local offen = {}
	for _, house in ipairs(CollectionService:GetTagged(HOUSE_TAG)) do
		if house:IsA("Model")
			and _G.ResolveCityName
			and _G.ResolveCityName(house) == cityName
			and not house:GetAttribute("Destroyed")
			and not house:GetAttribute("PermanentlyDestroyed")
		then
			table.insert(offen, house)
		end
	end
	return offen
end

-- ===== Die Markierung, die man sieht =====
-- Ein Highlight am Gebäude, wie beim Finisher-Rahmen und bei der Hitze-Anzeige. Bewusst nur
-- ein Umriss und keine Füllung: fünf ausgefüllte Häuser in einer brennenden Stadt wären
-- Lärm, ein Umriss liest sich auch durch Rauch.
--
-- Serverseitig gesetzt, damit es ohne eigenes Client-Skript bei allen ankommt -- die Frage
-- "welche Gebäude sind markiert" ist ohnehin für alle dieselbe.
local MARKER_NAME = "CollectibleMarker"
local MARKER_COLOR = Color3.fromRGB(255, 225, 120)

local function markierungSetzen(house)
	if house:FindFirstChild(MARKER_NAME) then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = MARKER_NAME
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = MARKER_COLOR
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = house
end

-- Eine einzelne Markierung loeschen. Zwei Anlaesse gehen denselben Weg: das Gebaeude faellt
-- (dann hat es seine Frage beantwortet) und das Fenster schliesst sich.
local function markierungLoeschen(house)
	if not house or not house.Parent then
		return
	end
	house:SetAttribute(CollectibleConfig.MarkerAttribute, nil)
	house:SetAttribute(CollectibleConfig.CarrierAttribute, nil)
	local marker = house:FindFirstChild(MARKER_NAME)
	if marker then
		marker:Destroy()
	end
end

local function markierungenEntfernen(cityName)
	local lauf = laufende[cityName]
	if not lauf then
		return
	end
	for _, house in ipairs(lauf.kandidaten) do
		markierungLoeschen(house)
	end
	if lauf.stueck and lauf.stueck.Parent then
		lauf.stueck:Destroy()
	end
	laufende[cityName] = nil
end

-- ===== Das Stück in die Welt setzen =====
-- Es schwebt über den Trümmern des Gebäudes, in dem es lag -- nicht darin: wer gerade ein
-- Haus eingestürzt hat, soll den Fund SEHEN, nicht in Schutt suchen.
local function stueckSetzen(cityName, position)
	local eintrag = CollectibleConfig.ForCity(cityName)
	if not eintrag or not modellOrdner then
		return nil
	end

	local vorlage = modellOrdner:FindFirstChild(eintrag.Model)
	if not vorlage then
		warn(string.format("[Kaiju] CollectibleService: Modell %q fehlt in %s -- %s bleibt ohne "
			.. "Fundstueck.", eintrag.Model, CollectibleConfig.FolderName, cityName))
		return nil
	end

	local stueck = vorlage:Clone()
	stueck.Name = "Collectible_" .. cityName

	pcall(function()
		stueck:ScaleTo(CollectibleConfig.WorldScale)
	end)

	for _, part in ipairs(stueck:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false -- soll keine fremden Raycasts stoeren (Bodensuche, Zielerfassung)
			part.CanTouch = false
		end
	end

	-- ===== Die Effekte, die das Modell mitbringt =====
	-- Der Workshop legt sie in einen Ordner "Effects" im Modell und liefert dazu einen
	-- eigenen Controller (collectibles/runtime/CollectibleEffects.client.lua). Den binden wir
	-- NICHT ein: er schaltet die Effekte für die Ansichtsszene des Workshops zyklisch um und
	-- verlangt ein Attribut, das zu seiner Bauphase gehört. Was hier gebraucht wird, ist das
	-- Gegenteil -- einmal an und an bleiben.
	local effekte = stueck:FindFirstChild("Effects")
	if effekte then
		for _, objekt in ipairs(effekte:GetDescendants()) do
			if objekt:IsA("ParticleEmitter") then
				objekt.Enabled = true
			end
		end
	else
		warn(string.format("[Kaiju Debug] Fundstueck %s hat keinen 'Effects'-Ordner -- es "
			.. "erscheint ohne Partikel.", eintrag.Model))
	end

	-- ===== Der Auftritt: aus dem Schutt nach oben =====
	-- Es beginnt unter seiner Schwebehöhe und fährt hoch. Ein Stück, das einfach dasteht,
	-- hat niemand erscheinen sehen -- und das Erscheinen ist der Hinweis, dass man im
	-- richtigen Haus war.
	local zielPose = CFrame.new(position + Vector3.new(0, CollectibleConfig.HoverHeight, 0))
	local startPose = zielPose - Vector3.new(0, CollectibleConfig.RiseFromBelow, 0)
	stueck:PivotTo(startPose)
	stueck.Parent = Workspace

	-- Das Schweben und Drehen danach macht der Client (siehe CollectibleClient) -- der Tag
	-- ist seine ganze Verabredung. Er wird ERST nach dem Aufstieg gesetzt, sonst griffen
	-- beide gleichzeitig nach derselben Pose.
	task.spawn(function()
		local begonnen = os.clock()
		while stueck.Parent do
			local t = (os.clock() - begonnen) / CollectibleConfig.RiseSeconds
			if t >= 1 then
				break
			end
			-- Weich auslaufen: es kommt hoch und bleibt stehen, es schiesst nicht heraus.
			local weich = 1 - (1 - t) * (1 - t)
			stueck:PivotTo(startPose:Lerp(zielPose, weich))
			task.wait()
		end
		if stueck.Parent then
			stueck:PivotTo(zielPose)
			stueck:SetAttribute("CollectibleRestY", zielPose.Position.Y)
			CollectionService:AddTag(stueck, CollectibleConfig.WorldTag)
		end
	end)

	return stueck
end

-- ===== Markieren, sobald die Stadt bricht =====
local function starten(cityName)
	if laufende[cityName] then
		return
	end

	local eintrag = CollectibleConfig.ForCity(cityName)
	if not eintrag then
		return -- diese Stadt hat kein Fundstück (etwa PrologueCity)
	end

	local offen = kandidatenFinden(cityName)
	if #offen == 0 then
		warn(string.format("[Kaiju] CollectibleService: in %s steht kein unzerstoertes Gebaeude "
			.. "-- kein Fundstueck in diesem Durchlauf.", cityName))
		return
	end

	-- Mischen und die ersten nehmen. Fisher-Yates auf einer Kopie: die Reihenfolge von
	-- GetTagged ist nicht zugesichert, aber auch nicht zufällig -- ohne Mischen bekäme
	-- derselbe Winkel der Stadt jedes Mal die Markierungen.
	for i = #offen, 2, -1 do
		local j = math.random(i)
		offen[i], offen[j] = offen[j], offen[i]
	end

	local kandidaten = {}
	for i = 1, math.min(CollectibleConfig.MarkedBuildings, #offen) do
		table.insert(kandidaten, offen[i])
	end

	local traeger = kandidaten[math.random(#kandidaten)]
	for _, house in ipairs(kandidaten) do
		house:SetAttribute(CollectibleConfig.MarkerAttribute, true)
		markierungSetzen(house)
	end
	-- Das Attribut am Träger ist NICHT an der Markierung zu erkennen -- alle fünf sehen
	-- gleich aus. Es steht nur für den Blick in Studio und für diesen Dienst.
	traeger:SetAttribute(CollectibleConfig.CarrierAttribute, true)

	laufende[cityName] = {
		kandidaten = kandidaten,
		traeger = traeger,
		stueck = nil,
		gefunden = false,
	}

	print(string.format("[Kaiju Debug] Fundstueck %s in %s: %d Gebaeude markiert, es liegt in %q.",
		eintrag.Title, cityName, #kandidaten, traeger:GetFullName()))
end

-- ===== Ein markiertes Gebäude ist gefallen =====
-- Gerufen vom HouseHandler, auf demselben Weg wie die Meldung an den Helikopter.
_G.RegisterDestroyedBuildingForCollectible = function(cityName, house, position)
	local lauf = laufende[cityName]
	if not lauf then
		return
	end

	-- ===== Ein gefallenes Gebaeude traegt keine Markierung mehr =====
	-- Zuerst und unabhaengig von allem anderen: ob es das richtige war, hat sich mit seinem
	-- Einsturz entschieden. Eine Markierung, die ueber Truemmern stehen bleibt, laedt dazu
	-- ein, dort weiterzusuchen -- und sie laesst die vier leeren Kandidaten bis zum Ende des
	-- Fensters stehen, auch wenn der Spieler sie laengst abgearbeitet hat.
	--
	-- Das gilt fuer JEDES markierte Gebaeude, nicht nur fuer den Traeger: der Sinn der fuenf
	-- ist, dass vier davon leer sind, und eine abgeraeumte Spur ist genau das, was dem
	-- Spieler sagt, wo er schon war.
	markierungLoeschen(house)

	if lauf.gefunden or lauf.stueck then
		return
	end
	if house ~= lauf.traeger then
		return -- markiert, aber leer: genau das ist der Sinn der fünf Kandidaten
	end

	lauf.stueck = stueckSetzen(cityName, position)
	if lauf.stueck then
		local eintrag = CollectibleConfig.ForCity(cityName)
		print(string.format("[Kaiju Debug] %s erschienen in %s -- aufsammeln durch Naehe (%d Studs).",
			eintrag.Title, cityName, CollectibleConfig.PickupRadius))
	end
end

-- ===== Aufsammeln durch Nähe =====
-- Gemessen gegen die SICHTBARE Figur (StageModels.GetFigurePoint), nicht gegen den
-- versteckten Avatar: dessen Wurzel sitzt bei einer grossen Stufe weit über dem Boden, und
-- "nah" wäre dann eine Frage der Skalierung statt eine des Abstands.
local function naeheprueefen()
	for cityName, lauf in pairs(laufende) do
		if lauf.stueck and lauf.stueck.Parent and not lauf.gefunden then
			local mitte = lauf.stueck:GetPivot().Position
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character and player:GetAttribute("CurrentCityName") == cityName then
					local punkt = StageModels.GetFigurePoint(character, 0.5)
					if punkt and (punkt - mitte).Magnitude <= CollectibleConfig.PickupRadius then
						lauf.gefunden = true
						local eintrag = CollectibleConfig.ForCity(cityName)

						if lauf.stueck.Parent then
							lauf.stueck:Destroy()
						end
						lauf.stueck = nil

						if _G.RecordStat then
							_G.RecordStat(player, "CollectibleFound")
							_G.RecordStat(player, "CollectibleFound." .. cityName)
						end

						print(string.format("[Kaiju Debug] %s aufgesammelt von %s in %s.",
							eintrag.Title, player.Name, cityName))

						-- Ab hier gehört es der Darstellung: Kamerafahrt und das Stück vor
						-- dem Spieler. Welches Modell gezeigt wird, sagt der Server mit --
						-- der Client soll die Stadt-Zuordnung nicht zweitfassen.
						CollectibleFoundEvent:FireClient(player, {
							City = cityName,
							Model = eintrag.Model,
							Title = eintrag.Title,
						})
						break
					end
				end
			end
		end
	end
end

task.spawn(function()
	while true do
		local ok, fehler = pcall(naeheprueefen)
		if not ok then
			warn("[Kaiju] CollectibleService: Naehepruefung fehlgeschlagen: " .. tostring(fehler))
		end
		task.wait(CollectibleConfig.PickupCheckInterval)
	end
end)

-- ===== An CITY BROKEN hängen =====
-- Die Werte legt CityBrokenService in CityAlertValues an, je Stadt "<Stadt>CityBroken".
-- Beobachtet wird der Ordner und nicht ein fester Satz Namen: die Werte entstehen erst,
-- wenn der Dienst seine Städte durchläuft, und in welcher Reihenfolge die beiden Skripte
-- starten, ist nicht zugesichert.
local function beobachte(wert)
	if not wert:IsA("BoolValue") then
		return
	end
	local cityName = wert.Name:match("^(.-)CityBroken$")
	if not cityName then
		return
	end

	wert.Changed:Connect(function(gebrochen)
		if gebrochen then
			starten(cityName)
		else
			-- Fenster zu: Markierungen weg, ein nicht gefundenes Stück verschwindet. Es
			-- liegen zu lassen hiesse, es beim nächsten Bruch doppelt zu haben.
			local lauf = laufende[cityName]
			if lauf and not lauf.gefunden then
				local eintrag = CollectibleConfig.ForCity(cityName)
				print(string.format("[Kaiju Debug] %s in %s nicht gefunden -- Fenster zu.",
					eintrag and eintrag.Title or "Fundstueck", cityName))
			end
			markierungenEntfernen(cityName)
		end
	end)
end

local cityAlertValues = ReplicatedStorage:WaitForChild("CityAlertValues", 60)
if not cityAlertValues then
	warn("[Kaiju] CollectibleService: 'CityAlertValues' nicht gefunden -- es wird kein Fundstueck "
		.. "erscheinen.")
	return
end

for _, wert in ipairs(cityAlertValues:GetChildren()) do
	beobachte(wert)
end
cityAlertValues.ChildAdded:Connect(beobachte)

print("[Kaiju] CollectibleService bereit -- Fundstuecke in "
	.. tostring(CollectibleConfig.MarkedBuildings) .. " markierten Gebaeuden je gebrochener Stadt.")
