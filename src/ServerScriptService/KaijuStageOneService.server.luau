-- VERSION: 2026-09-13 #1
-- Script: KaijuStageOneService
-- Ort in Studio: ServerScriptService
--
-- Zieht dem Spieler das Kaiju-Modell an, passend zu der Stufe, die er gerade trägt.
--
-- Gebaut sind erst drei Modelle; eine Stufe ohne eigenes nimmt das nächstniedrigere, nur
-- grösser. Vorher fiel der Spieler auf den alten Avatar zurück, sobald ein Modell fehlte --
-- der Aufstieg machte die Figur also hässlicher. Welche Stufe welches Modell in welcher
-- Grösse trägt, steht in StageModels.
--
-- ACHTUNG: die Modellnamen des Workshops (Stage_1_Primal_Beast und so weiter) haben nichts
-- mit den Stufennamen des Spiels zu tun (Riftborn, Ironpulse, ...). Die einen kommen aus
-- dem Asset-Paket, die anderen aus SkinsConfig.
--
-- Der Installer stammt aus dem Workshop-Submodul
-- (ReplicatedStorage.TrenchbornAssetWorkshop.KaijuStageOneInstaller). Er baut das Modell
-- aus Code, blendet den Avatar aus, hängt es an dessen HumanoidRootPart und übernimmt
-- Bewegung, Sprung und Angriff. Den Schaden macht er NICHT selbst: dafür verlangt er
-- einen Adapter, und den liefert KaijuStageOneCombatAdapter (siehe dort, warum).
--
-- ===== Wann installiert wird =====
-- Am Attribut "SkinId" der Figur, das PlayerSetup.applySkinToCharacter ganz am Ende setzt
-- -- nach dem Skalieren. Früher anzusetzen ginge schief: der Installer misst beim Bauen
-- die Bodenhöhe der Figur, und eine Figur, die gleich danach noch skaliert wird, stünde
-- mit dem Modell im Boden oder darüber.
--
-- Zusätzlich wird kurz gewartet, bis die Figur wirklich steht. PlayerSetup schiebt direkt
-- nach dem Skalieren noch eine Boden-Stabilisierung hinterher (task.defer), die die Figur
-- versetzt -- währenddessen zu messen hiesse, den falschen Boden zu treffen.
--
-- ===== Was beim Stufenwechsel passiert =====
-- Jede Änderung von SkinId wird geprüft. Hat die neue Stufe ein Modell, wird es in ihrer
-- Bau-Grösse NEU aufgebaut -- die Grösse ist eine Bau-Option, kein nachträgliches ScaleTo
-- (siehe RIG_ACTIVE_ATTRIBUTE weiter unten). Hat sie keines, wird abgenommen und die
-- normale Figur kommt zurück; der Installer stellt Sichtbarkeit, WalkSpeed und Sprungkraft
-- wieder her.
--
-- ===== Der Zonenwechsel, und warum er eine eigene Behandlung braucht =====
-- Beim ersten Spieltest ist der Spieler beim Portalwechsel weit neben der Karte im Leeren
-- gelandet und gefallen. Kein Tippfehler, sondern ein Widerspruch im Aufbau:
--
-- Der Installer misst beim Anziehen EINMAL die Bodenhöhe, baut das Modell darauf und
-- schweisst einen kollidierenden Körper (11x20x7 Studs mal Skalierung) an die
-- HumanoidRootPart. Das Spiel skaliert die Figur aber bei JEDEM Zonenwechsel neu
-- (PlayerSetup.applyZoneAwareScale, Sanctuary-Verkleinerung) -- also mitten in eine
-- fertige Installation hinein. Ein mitskalierter Kollisionskörper, der in die Welt ragt,
-- schleudert die Figur weg.
--
-- Mit einer Wartezeit ist dem nicht beizukommen. Deshalb wird bei jedem Zonenwechsel
-- ABGENOMMEN und danach neu angezogen: der Installer misst dann eine Figur, die bereits
-- ihre neue Grösse hat. Das entspricht auch dem, was das Paket vorsieht -- neu
-- installieren statt einmal anziehen und stehen lassen.
--
-- Falls dabei wieder etwas schiefgeht, ist ENABLED der Notschalter.
local ENABLED = true

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if not ENABLED then
	print("[Kaiju Debug] KaijuStageOneService ist abgeschaltet (ENABLED = false) -- es wird kein Kaiju-Modell angezogen.")
	return
end

-- Welche Stufe welches Modell in welcher Grösse trägt, steht in StageModels -- einmal für
-- Vorschauen und fürs Anziehen. Hier wird nur gefragt.

-- ===== Merkmal an der Figur: hier hängt ein Rig, das seine eigene Grösse verwaltet =====
-- Das Rig misst BEIM ANZIEHEN einmal die Länge jedes Gliedes, die Ruhelage jedes Gelenks
-- und den Skalierungsfaktor des Modells (KaijuStageOneRig: `scale`, `legs[side].upper`,
-- `rest[...]`). Danach rechnet es für immer mit diesen Werten.
--
-- Wer die Figur später über Model:ScaleTo skaliert, schreibt die tatsächlichen Part-Grössen
-- und Gelenk-C0 neu -- das Rig aber setzt weiter seine alten, unskalierten Werte darüber.
-- Ergebnis: ausgekugelte Gelenke (Arme in der Höhe, verdrehte Handgelenke), und weil die
-- gespeicherte Beinlänge nicht mehr zur echten passt, bricht die Beinrechnung an
-- Steigungen zusammen -- der waagrechte Rest der Reichweite geht auf null, der Fuss kann
-- nicht mehr nach vorn, die Figur läuft auf der Stelle.
--
-- Dieses Attribut ist die Warnung dafür: solange es gesetzt ist, darf niemand die Figur
-- skalieren. PlayerSetup.playLevelUpScalePop hält sich daran.
local RIG_ACTIVE_ATTRIBUTE = "KaijuRigActive"

-- ===== Kollisionsgruppe: zwei Kaiju schieben einander nicht =====
-- Der Installer schweisst jedem Spieler einen unsichtbaren Klotz an die Figur
-- ("KaijuBodyCollider", 8x14x6 Studs mal Bau-Grösse, kollidierend, schwebt neun Studs über
-- dem Boden). Er hat einen guten Grund: ohne ihn liefe eine zwanzig Studs hohe Gestalt mit
-- der winzigen Hülle des versteckten Avatars durch die Häuser.
--
-- Im Mehrspielerbetrieb wird daraus ein Problem. Stehen zwei Spieler nebeneinander,
-- überlappen sich ihre Klötze, und die Physik drückt sie auseinander. Der Stoss geht auf
-- die ganze Figur, und weil der Klotz über dem Boden schwebt, kann er den anderen dabei
-- ANHEBEN -- der Humanoid verliert den Boden, damit die Bodenreibung, und gleitet ohne
-- Eingabe weiter. Genau das war zu zweit zu sehen.
--
-- Deshalb: Klötze UND die (versteckten) Avatar-Teile kommen in eine eigene Gruppe, die
-- nicht mit sich selbst kollidiert. Gegen die WELT kollidieren beide weiter -- der Klotz
-- hält die Figur aus den Häusern, der Avatar steht weiter auf dem Boden. Nur untereinander
-- lassen sie sich in Ruhe.
local KAIJU_COLLISION_GROUP = "KaijuBody"

do
	local ok, err = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(KAIJU_COLLISION_GROUP) then
			PhysicsService:RegisterCollisionGroup(KAIJU_COLLISION_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(KAIJU_COLLISION_GROUP, KAIJU_COLLISION_GROUP, false)
	end)
	if not ok then
		warn("[Kaiju] Kollisionsgruppe '" .. KAIJU_COLLISION_GROUP .. "' liess sich nicht einrichten: "
			.. tostring(err) .. " -- zwei Kaiju koennen sich dann gegenseitig wegschieben.")
	end
end

-- Setzt die ganze Figur (inkl. Klotz) in die Gruppe -- oder zurueck auf Default.
--
-- "Default" als Rueckweg ist bewusst dieselbe Annahme, die der PrologueOrchestrator schon
-- trifft, wenn er nach der Kinematik alle Figurenteile zuruecksetzt. Im Projekt vergibt
-- sonst niemand Kollisionsgruppen.
local function setCharacterCollisionGroup(character, groupName)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part.CollisionGroup = groupName
			end)
		end
	end
end

-- ===== Der Avatar wird verdeckt, bis das Modell steht =====
-- Zwischen Spawn und angezogenem Modell liegen ein paar Zehntelsekunden: erst muss die
-- Groesse stehen, dann wird das Modell aus Code GEBAUT -- mehrere hundert Teile. In dieser
-- Zeit war der blanke Avatar zu sehen, und er sieht aus wie die alte Kaiju-Figur.
--
-- Wichtig ist die REIHENFOLGE. Der Installer merkt sich beim Anziehen die Transparenz, die
-- er vorfindet, und stellt sie beim Abnehmen wieder her. Haetten wir den Avatar vorher auf
-- unsichtbar gesetzt und es so gelassen, merkte er sich "unsichtbar" als Urzustand -- der
-- Spieler bliebe nach dem Abnehmen fuer immer durchsichtig.
--
-- Deshalb: verdecken, warten, ZURUECKSETZEN, und erst dann installieren. Der Installer
-- findet die echten Werte vor und verdeckt selbst weiter. Schlaegt etwas dazwischen fehl,
-- ist der Avatar wieder sichtbar statt unsichtbar -- der harmlosere von beiden Fehlern.
local hiddenParts = setmetatable({}, { __mode = "k" }) -- [character] = { [part] = Transparenz }

local function hideAvatar(character)
	if hiddenParts[character] then
		return
	end
	local saved = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			saved[part] = part.Transparency
			part.Transparency = 1
		elseif part:IsA("Decal") then
			saved[part] = part.Transparency
			part.Transparency = 1
		end
	end
	hiddenParts[character] = saved
end

local function revealAvatar(character)
	local saved = hiddenParts[character]
	if not saved then
		return
	end
	hiddenParts[character] = nil
	for item, transparency in pairs(saved) do
		if item.Parent then
			item.Transparency = transparency
		end
	end
end

-- So viele Bilder muss die Groesse unveraendert bleiben, bevor gebaut wird -- und so
-- lange wird hoechstens darauf gewartet.
local STABLE_FRAMES = 3
local STABLE_TIMEOUT_SECONDS = 1.5

local workshop = ReplicatedStorage:WaitForChild("TrenchbornAssetWorkshop", 20)
if not workshop then
	warn("[Kaiju] TrenchbornAssetWorkshop nicht gefunden (Timeout) -- die Kaiju-Modelle bleiben aus. "
		.. "Ist das Submodul synchronisiert?")
	return
end

local CombatAdapter = require(ServerScriptService:WaitForChild("KaijuStageOneCombatAdapter", 10))
local StageModels = require(ReplicatedStorage:WaitForChild("StageModels"))
local SkinsConfig = require(ReplicatedStorage:WaitForChild("SkinsConfig"))

-- ===== Ein Installer je Modell =====
-- Jedes Modell bringt seinen eigenen mit (KaijuStageOneInstaller, KaijuStageTwoInstaller).
-- Sie sind nicht austauschbar: der Stufe-2-Installer weigert sich sogar ausdrücklich,
-- wenn schon ein Stufe-1-Modell an der Figur hängt.
--
-- Deshalb wird der Installer erst geholt, wenn er gebraucht wird, und je Figur gemerkt --
-- ABGENOMMEN werden muss mit demselben, mit dem angezogen wurde. Nähme man den falschen,
-- fände er seine Installation nicht und liesse Modell, Kollisionskörper und
-- Sichtbarkeitsänderungen stehen.
local installerCache = {}

local function getInstaller(name)
	if installerCache[name] ~= nil then
		return installerCache[name] or nil
	end
	local module = workshop:FindFirstChild(name)
	if not module then
		warn("[Kaiju] " .. name .. " fehlt im Workshop-Submodul -- diese Stufe bleibt beim Avatar. "
			.. "Ist das Submodul synchronisiert?")
		installerCache[name] = false
		return nil
	end
	local ok, loaded = pcall(require, module)
	if not ok then
		warn("[Kaiju] " .. name .. " liess sich nicht laden: " .. tostring(loaded))
		installerCache[name] = false
		return nil
	end
	installerCache[name] = loaded
	print(string.format("[Kaiju Debug] %s geladen -- Version %s", name, tostring(loaded.Version)))
	return loaded
end

print("[Kaiju Debug] KaijuStageOneService bereit.")

-- [character] = { installer = <Modul>, signature = "<Installer>@<Grösse>" }.
--
-- Die Signatur enthält AUCH die Grösse, nicht nur den Installer: die Stufen 3 bis 5 tragen
-- alle denselben Storm Hunter, nur unterschiedlich gross. Verglichen man nur den
-- Installer, bliebe beim Aufstieg von 3 auf 4 das Modell in der alten Grösse stehen.
--
-- Schwache Schlüssel: eine entfernte Figur soll nicht durch diesen Eintrag am Leben
-- gehalten werden.
local installed = setmetatable({}, { __mode = "k" })

local function uninstall(character)
	local current = installed[character]
	if not current then
		return
	end
	installed[character] = nil
	character:SetAttribute(RIG_ACTIVE_ATTRIBUTE, nil)
	setCharacterCollisionGroup(character, "Default")
	local ok, err = pcall(function()
		current.installer.Uninstall(character)
	end)
	if not ok then
		warn("[Kaiju] Kaiju-Modell liess sich nicht abnehmen: " .. tostring(err))
	end
end

local function install(player, character, worn)
	if installed[character] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local installer = getInstaller(worn.installer)
	if not installer then
		revealAvatar(character)
		return
	end

	-- Die echten Werte zurueck, BEVOR der Installer sie sich merkt (siehe oben).
	revealAvatar(character)

	local ok, err = pcall(function()
		installer.Install(character, {
			CombatFactory = function(kaiju, root, kaijuHumanoid, rootHeight)
				return CombatAdapter.Attach(kaiju, root, kaijuHumanoid, rootHeight)
			end,
			-- Die Eingabe des Pakets bleibt AUS. Sie legt den Fokus auf E -- dort liegt in
			-- diesem Spiel schon der Flächenangriff (SpecialAttackClient: Q Fokus,
			-- E Fläche). Ein Tastendruck löste beides gleichzeitig aus. Sprung und Laufen
			-- übernimmt stattdessen KaijuStageOneInputClient, Schlagen der AttackClient.
			--
			-- Der Sprung-Motor wird davon NICHT berührt: den installiert das Paket immer
			-- selbst, er ist für den Sprung zwingend.
			InstallInput = false,

			-- Die Grösse geht in den BAU, nicht nachträglich per ScaleTo. Die Anleitung
			-- des Pakets ist da eindeutig: "Do not call ScaleTo on an attached rig, which
			-- caches dimensions." Ein Stufenwechsel baut deshalb neu.
			--
			-- ACHTUNG, hier stand lange `buildScale` -- ein Name, den es seit der Umstellung
			-- auf zwei Installer nicht mehr gibt; der Parameter heisst `worn`. In Luau ist
			-- ein unbekannter Name kein Fehler, sondern eine globale mit dem Wert nil. Der
			-- Installer las also nie eine Grösse und baute JEDE Stufe auf 1 -- lautlos, über
			-- Wochen. Aufgefallen ist es erst, als das Rig auf Stufe 3 den Flächenangriff
			-- verweigerte, weil der Avatar dreifach skaliert war und das Modell einfach.
			Scale = worn.scale,
		})
	end)

	if not ok then
		-- Der Installer räumt bei einem Fehler selbst auf (er ruft intern api.Destroy),
		-- die Figur bleibt also sichtbar und steuerbar. Gemeldet wird trotzdem: ein
		-- stiller Fehlschlag sähe im Spiel aus wie "das Modell gibt es gar nicht".
		warn("[Kaiju] Kaiju-Modell liess sich nicht anziehen fuer " .. player.Name .. ": " .. tostring(err))
		return
	end

	installed[character] = { installer = installer, signature = worn.signature }
	character:SetAttribute(RIG_ACTIVE_ATTRIBUTE, true)

	-- NACH der Installation: erst jetzt existiert der Kollisionsklotz.
	setCharacterCollisionGroup(character, KAIJU_COLLISION_GROUP)
	print(string.format("[Kaiju Debug] %s angezogen fuer %s -- Stufe %s, Bau-Groesse %.2f",
		worn.modelName, player.Name, tostring(character:GetAttribute("SkinId")), worn.scale))
end

-- Gleicht den Ist- mit dem Soll-Zustand ab. Wird bei jedem SkinId-Wechsel aufgerufen und
-- ist absichtlich idempotent -- mehrfaches Aufrufen ändert nichts.
local function reconcile(player, character)
	if character.Parent == nil then
		return
	end
	local skinId = character:GetAttribute("SkinId")
	-- Gibt es für diese Stufe ein Modell, liefert StageModels die Grösse, in der sie es
	-- trägt. Gibt es keines, kommt nil -- dann bleibt es beim normalen Avatar.
	local skin = skinId and SkinsConfig.GetSkinById(skinId) or nil
	-- Die Zone geht mit ein: im Sanctuary sind alle Figuren kleiner, und das gilt fuer das
	-- Modell genauso wie fuer den Avatar darunter. Weil die Grösse in die Signatur
	-- einfliesst, erkennt der Abgleich einen Zonenwechsel von selbst als "muss neu gebaut
	-- werden" -- ohne dass es hier eine eigene Fallunterscheidung braucht.
	local imSanctuary = player:GetAttribute("CurrentZone") == "Sanctuary"
	local worn = skin and StageModels.GetWorn(skin.Faction or "Kaiju", skin.Id, imSanctuary) or nil

	-- ===== Der Notausgang fuer Vergleiche =====
	-- Das Debug-Panel kann diesen Spieler auf den blanken Roblox-Avatar zuruecksetzen: kein
	-- Modell, keine Skalierung. Gedacht fuer die Frage "liegt es am Rig oder am Spiel?" --
	-- die sonst nur zu beantworten waere, indem man ENABLED im Quelltext umlegt und alle
	-- Spieler mitnimmt.
	--
	-- Es laeuft ueber denselben Weg wie eine Stufe ohne Modell: worn auf nil, und der
	-- Abgleich darunter nimmt ab und zeigt den Avatar. Kein zweiter Ausstieg, der
	-- auseinanderlaufen koennte.
	if player:GetAttribute("DebugPlainAvatar") == true then
		worn = nil
	end

	if not worn then
		uninstall(character)
		revealAvatar(character) -- diese Stufe hat kein Modell: der Avatar ist die Figur
		return
	end

	-- Hängt schon genau das Richtige, ist nichts zu tun. Sonst erst abnehmen: install()
	-- steigt aus, solange etwas hängt, und der Stufe-2-Installer weigert sich ausdrücklich,
	-- wenn noch ein Stufe-1-Modell an der Figur ist.
	local current = installed[character]
	if current and current.signature == worn.signature then
		return
	end
	if current then
		uninstall(character)
	end
	install(player, character, worn)
end

-- ===== Warten, bis die Groesse steht -- statt einer festen Wartezeit =====
-- Das Rig misst beim Anziehen einmal und rechnet danach mit diesen Werten (siehe
-- RIG_ACTIVE_ATTRIBUTE). Gebaut werden darf also erst, wenn niemand mehr an der Groesse
-- dreht: applySkinToCharacter und applyZoneAwareScale skalieren, und PlayerSetup schiebt
-- danach noch eine Boden-Stabilisierung hinterher.
--
-- Vorher stand hier eine feste Drittelsekunde. Die war zugleich zu lang und unsicher: zu
-- lang, weil man in dieser Zeit nach dem Portalwechsel den blanken Avatar sah, und
-- unsicher, weil eine feste Zahl nichts darueber weiss, ob das Skalieren wirklich durch
-- ist. Jetzt wird gewartet, bis die Groesse drei Bilder lang gleich bleibt -- im
-- Normalfall sind das wenige Hundertstel.
local function waitForStableScale(character)
	local deadline = os.clock() + STABLE_TIMEOUT_SECONDS
	local last, steady = nil, 0
	while character.Parent and os.clock() < deadline do
		local ok, current = pcall(function()
			return character:GetScale()
		end)
		if not ok then
			return false
		end
		if last and math.abs(current - last) < 0.0001 then
			steady += 1
			if steady >= STABLE_FRAMES then
				return true
			end
		else
			steady = 0
		end
		last = current
		RunService.Heartbeat:Wait()
	end
	return character.Parent ~= nil
end

-- Baut ab, sobald sich etwas aendert, und danach neu auf -- sobald die Groesse steht.
local function scheduleReconcile(player, character)
	task.spawn(function()
		if waitForStableScale(character) and player.Character == character then
			reconcile(player, character)
		end

		-- Sicherheitsnetz: haengt nach allem KEIN Modell an der Figur, muss der Avatar
		-- wieder sichtbar sein. Ohne das bliebe ein Spieler unsichtbar, wenn der Bau
		-- irgendwo stehenbleibt -- der schlimmste denkbare Ausgang dieser Verdeckung.
		task.delay(2, function()
			if character.Parent and not installed[character] then
				revealAvatar(character)
			end
		end)
	end)
end

local function watchCharacter(player, character)
	-- Sofort verdecken, noch bevor irgendetwas gemessen oder gebaut wird. Alles Weitere
	-- laeuft erst in den naechsten Zehntelsekunden -- und genau in dieser Zeit war bisher
	-- der blanke Avatar zu sehen.
	hideAvatar(character)

	character:GetAttributeChangedSignal("SkinId"):Connect(function()
		scheduleReconcile(player, character)
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Beim Tod abnehmen. Ohne das bliebe das Modell an der Leiche hängen, bis sie
		-- entfernt wird -- sichtbar als ein Kaiju, der im Boden liegt.
		humanoid.Died:Connect(function()
			uninstall(character)
		end)
	end

	-- Falls SkinId schon gesetzt war, bevor dieses Skript zuhören konnte.
	if character:GetAttribute("SkinId") ~= nil then
		scheduleReconcile(player, character)
	end
end

local function watchPlayer(player)
	-- Zonenwechsel: erst abnehmen, dann neu anziehen (siehe Kopf der Datei). Das Abnehmen
	-- läuft SOFORT -- der Kollisionskörper muss weg sein, bevor applyZoneAwareScale die
	-- Figur skaliert. Beide hängen am selben Attribut, und in welcher Reihenfolge Roblox
	-- sie aufruft, ist nicht zugesichert.
	player:GetAttributeChangedSignal("CurrentZone"):Connect(function()
		local character = player.Character
		if not character then
			return
		end
		uninstall(character)
		-- Waehrend des Neuaufbaus nach dem Zonenwechsel ebenfalls verdecken, sonst blitzt
		-- dort der Avatar auf.
		hideAvatar(character)
		scheduleReconcile(player, character)
	end)

	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		uninstall(character)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
