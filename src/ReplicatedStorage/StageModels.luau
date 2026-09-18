-- VERSION: 2026-09-13 #3
-- ModuleScript: StageModels
-- Ort in Studio: ReplicatedStorage
--
-- Die einzige Stelle, die weiss, WELCHES Modell eine Figuren-Stufe darstellt, mit welchem
-- Installer es angezogen wird und in welcher Grösse.
--
-- ===== Warum zentral =====
-- Vier Stellen brauchen diese Auskunft: Skin-Auswahl, Fraktionswahl und Archiv zeigen eine
-- Vorschau, und der KaijuStageOneService zieht das Modell tatsächlich an. Stünde die
-- Zuordnung viermal da, wäre beim nächsten Modell eine davon vergessen worden.
--
-- ===== Alle fünf Stufen haben ihr eigenes Modell =====
-- Riftborn, Ironpulse, Epochbreaker, Chronovore und Aeon Tyrant tragen je ein eigenes.
-- Die Reihe ist damit vollständig; das Nachrücken der nächstniedrigeren Stufe greift nur
-- noch, wenn einmal ein Eintrag fehlt.
--
-- Der Mechanismus bleibt trotzdem stehen, und zwar mit Absicht: er ist die Antwort auf die
-- Frage, was passiert, wenn eine Fraktion ihre ersten Modelle bekommt. Jaeger und Ronin
-- haben heute gar keine -- wer dort mit Stufe 1 anfängt, soll nicht auf den nackten Avatar
-- zurückfallen, sondern das nehmen, was da ist.
--
-- Nicht alle fünf sind gleich weit: Stufe 4 ist ausdrücklich ein Integrationstest
-- (0.1.1-test), die Stufen 1 bis 3 und 5 sind abgenommene Fassungen. Siehe die Kommentare
-- an den jeweiligen Einträgen.
--
-- ===== Grösse ist eine BAU-Option, kein ScaleTo =====
-- Beide Pakete sagen es wörtlich: "Do not call ScaleTo on an attached rig, which caches
-- dimensions." Das Rig misst Gliedmassenlängen, Gelenk-Ruhelagen und den Skalierungsfaktor
-- einmal beim Bauen; wer danach skaliert, kugelt ihm die Gelenke aus. Die Grösse geht
-- deshalb in den Bau, und ein Stufenwechsel baut neu.
--
-- Die getragene Grösse ist immer die Skin-Grösse der Stufe (SkinsConfig.Scale). Sie muss
-- mit der Skalierung des Charakters übereinstimmen, sonst rechnet das Rig mit falschen
-- Abständen -- siehe GetWorn.
--
-- ===== Verwendung =====
--   local model = StageModels.BuildPreview("Kaiju", 2)  -- Vorschau, immer Grösse 1
--   local worn = StageModels.GetWorn("Kaiju", 2)        -- { installer = ..., scale = ... }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinsConfig = require(ReplicatedStorage:WaitForChild("SkinsConfig"))

local StageModels = {}

-- [Fraktion] = Liste der gebauten Modelle, aufsteigend nach der Skin-Id, FÜR die sie
-- gebaut wurden. Eine Stufe nimmt das letzte Modell, dessen skinId <= ihrer eigenen ist.
--
-- `build` bekommt das geladene Baumeister-Modul, den Ablage-Ordner und die Bau-Grösse und
-- gibt das fertige Modell zurück. Die Baumeister haben unterschiedliche Signaturen -- Stufe
-- 1 baut über BuildStage mit Stufennummer, die anderen über Build -- deshalb steht der
-- Aufruf hier und nicht als gemeinsame Annahme im Code.
local RECIPES = {
	Kaiju = {
		{
			skinId = 0,
			installer = "KaijuStageOneInstaller",
			module = "KaijuEvolutionBlockout",
			modelName = "Stage_1_Primal_Beast",
			build = function(builder, staging, scale)
				local collection = builder.BuildStage(staging, 1, CFrame.identity, { Scale = scale })
				return collection and collection:FindFirstChild("Stage_1_Primal_Beast")
			end,
		},
		{
			skinId = 1,
			installer = "KaijuStageTwoInstaller",
			module = "KaijuStageTwoGoldenMaster",
			modelName = "Stage_2_Storm_Hunter",
			build = function(builder, staging, scale)
				return builder.Build(staging, CFrame.identity, { Scale = scale })
			end,
		},
		{
			skinId = 2,
			installer = "KaijuStageThreeInstaller",
			module = "KaijuStageThreeGoldenMaster",
			modelName = "Stage_3_Rift_Stalker",
			build = function(builder, staging, scale)
				return builder.Build(staging, CFrame.identity, { Scale = scale })
			end,
		},
		-- ===== Stufe 4: noch ein Testpaket =====
		-- Der Installer heisst ausdrücklich "Test" und trägt die Version 0.1.0-test; der
		-- Workshop nennt ihn einen Integrationstest, nicht die endgültige Fassung. Er
		-- erfüllt aber denselben Vertrag wie die drei davor (CombatFactory, dieselben sechs
		-- Methoden), also hängt er hier wie jeder andere.
		--
		-- Als einziger braucht er einen zweiten Schritt: die Panzerung und die Energieadern
		-- kommen aus einem eigenen Modul, das nach dem Bau darübergelegt wird. Ohne das
		-- stünde in der Vorschau ein nacktes Grundmodell.
		{
			skinId = 3,
			installer = "KaijuStageFourTestInstaller",
			module = "KaijuStageFourGoldenMaster",
			dressing = "KaijuStageFourDressing",
			modelName = "Stage_4_Geometry_Review",
			build = function(builder, staging, scale)
				return builder.Build(staging, CFrame.identity, { Scale = scale })
			end,
		},
		-- ===== Stufe 5: die erste fertige Fassung der Reihe =====
		-- Anders als Stufe 4 ist dieser Installer kein Testpaket: Version 1.0.0, Phase 7,
		-- Geometrie, Ausstattung und Spielbarkeit vom Workshop abgenommen.
		--
		-- Die Ausstattung steckt hier im Baumeister selbst, es gibt also kein eigenes
		-- Ausstattungsmodul wie bei Stufe 4. Was der Installer zusätzlich anhängt, ist ein
		-- Verweis auf die Darstellung der Energiesegel (KaijuSailRenderer) -- der fehlt der
		-- Vorschau, und das ist richtig so: sie steht still, da gibt es keine Ladewelle zu
		-- animieren.
		{
			skinId = 4,
			installer = "KaijuStageFiveInstaller",
			module = "KaijuStageFiveGoldenMaster",
			modelName = "Stage_5_Geometry_Review",
			build = function(builder, staging, scale)
				return builder.Build(staging, CFrame.identity, { Scale = scale })
			end,
		},
	},
}

local prototypes = {} -- ["Kaiju:1"] = Model oder false (= schon versucht, geht nicht)

-- Das Modell, das diese Stufe trägt: der letzte Eintrag, dessen skinId nicht über der
-- gesuchten liegt.
local function recipeFor(factionKey, skinId)
	local list = RECIPES[factionKey]
	if not list or type(skinId) ~= "number" then
		return nil
	end

	local skin = SkinsConfig.GetSkinById(skinId)
	if not skin or (skin.Faction or "Kaiju") ~= factionKey then
		return nil -- Stufe gibt es nicht, oder sie gehört einer anderen Fraktion
	end

	local chosen = nil
	for _, recipe in ipairs(list) do
		if recipe.skinId <= skinId then
			chosen = recipe
		end
	end
	return chosen, skin
end

-- Was zum Anziehen gebraucht wird: der Name des Installers und die Bau-Grösse. nil, wenn
-- es für diese Stufe (noch) kein Modell gibt -- dann bleibt es beim normalen Avatar.
--
-- ===== Die Bau-Grösse ist die Skin-Grösse. Punkt. =====
-- Sie MUSS mit der Skalierung des Charakters übereinstimmen, auf dem das Modell sitzt.
--
-- Das Rig misst die Welt gegen die HumanoidRootPart des (versteckten) Avatars, skaliert
-- seine Toleranzen aber mit der Grösse des MODELLS. Laufen die beiden auseinander, stimmen
-- sämtliche Abstände nicht mehr.
--
-- Genau daran ist der Flächenangriff ab Stufe 3 gescheitert: der Avatar stand auf
-- Skin-Grösse 3, das Modell war auf 1.5 gebaut. Der Bodenstrahl des Rigs verlangt einen
-- Treffer innerhalb von 20 mal Modellgrösse -- also 30 Studs. Der Boden lag aber 26.4
-- Studs unter dem dreifach skalierten Rumpf und damit ausserhalb; es lehnte wortlos ab.
--
-- Hier stand vorher ein Verhältnis zu der Stufe, FÜR die ein Modell gebaut wurde. Das war
-- von vornherein überflüssig: der Storm Hunter entsteht im Workshop AUS der
-- Primal-Beast-Geometrie bei Grösse 1 und wird danach nur umgeformt, der Rift Stalker
-- wiederum aus dem Storm Hunter. Alle Modelle haben dieselbe Grundgrösse, es gibt keinen
-- Umrechnungsfaktor zwischen ihnen.
function StageModels.GetWorn(factionKey, skinId, isSanctuary)
	local recipe, skin = recipeFor(factionKey, skinId)
	if not recipe then
		return nil
	end

	-- Dieselbe Rechnung wie für den Avatar (PlayerSetup) -- und zwar wörtlich dieselbe
	-- Funktion, nicht eine zweite Fassung davon. Im Sanctuary sind beide kleiner.
	local scale = SkinsConfig.GetScale(skin, isSanctuary)

	return {
		installer = recipe.installer,
		scale = scale,
		modelName = recipe.modelName,
		-- Erkennungszeichen für "hängt schon genau das Richtige". Modell UND Grösse, denn
		-- mehrere Stufen teilen sich ein Modell in verschiedenen Grössen.
		signature = string.format("%s@%.4f", recipe.installer, scale),
	}
end

-- Das Modell, das GERADE an dieser Figur hängt -- oder nil, wenn keines hängt.
--
-- Gesucht wird NICHT nach dem Namen. Der ist je Stufe ein anderer (Stage_1_Primal_Beast,
-- Stage_2_Storm_Hunter, Stage_3_Rift_Stalker ...), und eine Liste von Namen muss bei jedem
-- neuen Modell an jeder Fundstelle nachgezogen werden. Im Workshop-Paket selbst stehen
-- inzwischen zwei solcher Listen, und beide mussten schon zweimal wachsen; bei uns hatte
-- genau das den Sprung ab Stufe 2 stillgelegt.
--
-- Gesucht wird stattdessen nach dem, wofür man das Modell braucht: nach den
-- Anfrage-Ereignissen, die der Installer daran hängt. Kommt eine Stufe dazu, findet dieser
-- Code sie ohne Änderung.
function StageModels.FindEquipped(character)
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Model") then
			local remote = child:FindFirstChild("RequestJump")
			if remote and remote:IsA("RemoteEvent") then
				return child
			end
		end
	end
	return nil
end

-- ===== Wo "die Figur" für einen Effekt ist =====
-- Alles, was das Spiel auf den Spieler richtet, zielte bisher auf den Avatar: auf dessen
-- Kopf oder Rumpf. Bei einem angezogenen Kaiju ist der Avatar aber versteckt UND winzig
-- gegen das Modell -- sein Kopf steht dann ungefähr auf Schienbeinhöhe der sichtbaren
-- Figur, zwischen den Beinen. Effekte liefen dorthin und endeten sichtbar neben der Figur
-- statt an ihr.
--
-- Diese Funktion nennt den Punkt, den ein Zuschauer als "die Figur" liest: die Brust.
--
-- ===== Warum über die Höhe und nicht über einen Teilenamen =====
-- Hier stand zuerst eine Suche nach "UpperRibcage" und Geschwistern. Sie ging ins Leere:
-- nach dem Aufbau des Rigs liegen diese Teile nicht mehr als direkte Kinder am Modell,
-- und FindFirstChild sucht nicht in die Tiefe. Die Kette fiel deshalb bis auf die Hüfte
-- durch, und die Bänder liefen sichtbar zwischen die Beine.
--
-- Eine rekursive Suche hätte das geflickt, aber die Abhängigkeit von Teilenamen bliebe --
-- und die Namen gehören dem Asset-Paket, nicht uns. Deshalb geometrisch: ein Anteil der
-- Figurenhöhe über den Füssen. Das gilt für jede Stufe, überlebt jede Umbenennung und ist
-- eine Zahl, an der sich drehen lässt.
--
-- Waagrecht ist es der Standpunkt der Figur. Dass der mit dem Rumpf des Avatars
-- zusammenfällt, stellt der Adapter beim Anziehen sicher (KaijuStageOneCombatAdapter,
-- centreOverRoot) -- der Schwanz zöge einen Hüllquadermittelpunkt sonst nach hinten.
--
-- Der Anteil ist derselbe Gedanke wie der Kamerafokus in CameraFramingClient: Brusthöhe,
-- nicht Hüfte und nicht Kopf.
local BODY_POINT_HEIGHT_SHARE = 0.65

-- Derselbe Punkt, aber als Versatz IM RUMPFSYSTEM statt als Weltpunkt.
--
-- Den braucht alles, was sich an die Figur HÄNGT statt einmal auf sie zu zielen: ein
-- Attachment, ein Beam-Endpunkt, ein Schild. Die folgen dem Rumpf von selbst, wollen aber
-- wissen, wie weit über ihm sie sitzen sollen.
--
-- Ohne diesen Weg landete jedes solche Ding am Rumpf des versteckten Avatars -- und der
-- steht bei einer grossen Stufe auf Schienbeinhöhe. Genau das waren die Absorb-Bänder, die
-- bei den Füssen endeten.
function StageModels.GetBodyOffset(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local point = StageModels.GetBodyPoint(character)
	if not root or not point then
		return Vector3.zero
	end
	return root.CFrame:PointToObjectSpace(point)
end

function StageModels.GetBodyPoint(character)
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local model = StageModels.FindEquipped(character)
	if model and root then
		local ok, cframe, size = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and size and size.Y > 0 then
			local bottomY = cframe.Position.Y - size.Y / 2
			return Vector3.new(
				root.Position.X,
				bottomY + size.Y * BODY_POINT_HEIGHT_SHARE,
				root.Position.Z
			)
		end
	end

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return root and root.Position or nil
end

local function buildPrototype(recipe, scale)
	local workshop = ReplicatedStorage:FindFirstChild("TrenchbornAssetWorkshop")
	if not workshop then
		return nil
	end
	local builderModule = workshop:FindFirstChild(recipe.module)
	if not builderModule then
		return nil
	end

	local ok, model = pcall(function()
		-- Eigener Ablage-Ordner: die Baumeister ersetzen Sammlungen INNERHALB ihres Ziels.
		-- Baute man direkt in den Workshop-Ordner, träfen sie dort Fremdes.
		local staging = Instance.new("Folder")
		staging.Name = "StageModelsBuild"
		staging.Parent = ReplicatedStorage

		local built = recipe.build(require(builderModule), staging, scale)

		-- Zweiter Schritt für Stufen, die ihre Ausstattung aus einem eigenen Modul holen
		-- (Stufe 4). Schlägt er fehl, fällt der ganze Bau durch -- ein halb ausgestattetes
		-- Modell in der Vorschau wäre schlechter als gar keines.
		if built and recipe.dressing then
			local dressingModule = workshop:FindFirstChild(recipe.dressing)
			assert(dressingModule, "Ausstattungsmodul '" .. recipe.dressing .. "' fehlt")
			require(dressingModule).Apply(built)
		end

		if built then
			built.Parent = nil -- herauslösen, bevor der Ablage-Ordner fällt
		end
		staging:Destroy()
		return built
	end)

	if not ok then
		warn("[StageModels] Modell '" .. recipe.modelName .. "' liess sich nicht bauen: " .. tostring(model))
		return nil
	end
	return model
end

-- Ein frisches Modell für eine Vorschau. Der Aufrufer setzt den Parent selbst.
--
-- IMMER in Grösse 1, unabhängig von der Stufe -- und das ist Absicht: die Vorschau passt
-- jedes Modell in ihren Rahmen ein (ModelPreviewUtils.Fit), verschieden grosse Kopien
-- desselben Modells ergäben also identische Bilder. Der Grössenunterschied steht im
-- Steckbrief als Zahl. So wird je Modell einmal gebaut statt je Stufe.
function StageModels.BuildPreview(factionKey, skinId)
	local recipe = recipeFor(factionKey, skinId)
	if not recipe then
		return nil
	end

	local key = factionKey .. ":" .. tostring(recipe.skinId)
	if prototypes[key] == nil then
		prototypes[key] = buildPrototype(recipe, 1) or false
		if prototypes[key] then
			print(string.format("[Kaiju Debug] StageModels: Vorschau-Vorlage '%s' gebaut.", recipe.modelName))
		end
	end

	local prototype = prototypes[key]
	if not prototype then
		return nil
	end

	local ok, clone = pcall(function()
		return prototype:Clone()
	end)
	return ok and clone or nil
end

-- ===== Wie hoch die Figur in dieser Stufe TATSAECHLICH ist =====
-- Gemessen an der Vorschau-Vorlage, die ohnehin gebaut und gemerkt wird, mal der Grösse,
-- in der die Stufe getragen wird. Also dieselbe Zahl, die im Spiel an der Figur hängt --
-- nur ohne dass jemand sie anziehen müsste.
--
-- Gebraucht wird das vom Debug-Schalter "blanker Avatar": der nimmt nur das Modell ab, und
-- damit der Vergleich taugt, muss der Avatar danach GENAUSO HOCH dastehen. Dieselbe
-- Skalierungszahl an beiden reicht dafür nicht -- ein Avatar ist bei Grösse 1 rund fünf
-- Studs hoch, das Modell dreissig, und das Verhältnis wächst über die Stufen von knapp
-- sechs auf gut neun.
--
-- Warum gemessen und nicht gerechnet: eine Formel müsste die Eigenhöhe jeder Stufe kennen
-- (KaijuEvolutionBlockout, `height`), und die gehört dem Asset-Paket. Sie hier zu
-- wiederholen wäre die nächste Liste, die auseinanderläuft.
local prototypeHeights = {} -- ["Kaiju:2"] = Höhe bei Grösse 1

function StageModels.GetWornHeight(factionKey, skinId, isSanctuary)
	local recipe, skin = recipeFor(factionKey, skinId)
	if not recipe or not skin then
		return nil
	end

	local key = factionKey .. ":" .. tostring(recipe.skinId)
	if prototypeHeights[key] == nil then
		-- Baut die Vorlage, falls es sie noch nicht gibt -- und merkt NUR die Höhe. Das
		-- Modell selbst bleibt im Vorlagen-Speicher und wird nicht kopiert.
		local vorschau = StageModels.BuildPreview(factionKey, skinId)
		local hoehe = false
		if vorschau then
			local ok, _, size = pcall(function()
				return vorschau:GetBoundingBox()
			end)
			if ok and size and size.Y > 0 then
				hoehe = size.Y
			end
			vorschau:Destroy() -- die Kopie wird nur zum Messen gebraucht
		end
		prototypeHeights[key] = hoehe
	end

	local basis = prototypeHeights[key]
	if not basis then
		return nil
	end
	return basis * SkinsConfig.GetScale(skin, isSanctuary)
end

return StageModels
