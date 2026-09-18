-- VERSION: 2026-09-13 #1
-- LocalScript: CameraFramingClient
-- Ort in Studio: StarterPlayer > StarterPlayerScripts
--
-- Stellt Kameraentfernung UND Fokuspunkt auf die Grösse der Figur ein.
--
-- Beides gehört zusammen: es ist eine Entscheidung darüber, wie die Figur im Bild steht.
-- Getrennt gepflegt liefen sie auseinander -- der Fokus wurde 0.5 Sekunden nach dem Spawn
-- einmal gesetzt, also bevor das Kaiju-Modell überhaupt hing, und blieb dann auf Avatarhöhe.
-- Er lag damit zwischen den Beinen der Figur.
--
-- ===== Warum =====
-- Roblox startet jede Sitzung mit derselben nahen Entfernung -- gedacht für einen Avatar
-- von rund fünf Studs. Eine Kaiju-Stufe ist bis zu hundert Studs hoch; man sah beim
-- Spielstart eine Wand aus Panzerung und musste jedes Mal von Hand herauszoomen, bevor
-- Figur und Umgebung überhaupt im Bild waren.
--
-- ===== Wann eingegriffen wird =====
-- Nur bei einem WECHSEL: beim Spawnen und wenn die Figur ihre Grösse ändert (Stufenwechsel,
-- Modell angezogen, Zonenwechsel). Dazwischen nie -- sonst risse es dem Spieler die Kamera
-- aus der Hand, sobald er selbst zoomt.
--
-- ===== Wie man die Entfernung überhaupt setzt =====
-- Es gibt keine Eigenschaft "aktuelle Entfernung". Die Kameraskripte von Roblox halten sie
-- aber immer innerhalb von CameraMinZoomDistance und CameraMaxZoomDistance. Klemmt man
-- beide für einen Moment auf denselben Wert, bleibt der Kamera nichts anderes übrig; danach
-- wird die Untergrenze wieder freigegeben, und der Spieler kann zoomen, wie er will.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StageModels = require(ReplicatedStorage:WaitForChild("StageModels"))

local player = Players.LocalPlayer

-- Wie weit die Kamera bei einer Figur dieser Höhe stehen soll. Das Vielfache ist so
-- gewählt, dass die Figur rund die Hälfte der Bildhöhe einnimmt und daneben noch Strasse
-- und Häuser zu sehen sind -- man spielt eine Figur IN einer Stadt, nicht ein Porträt.
local DISTANCE_PER_HEIGHT = 1.8
local DISTANCE_MIN = 18
local DISTANCE_MAX = 900

-- ===== Wo der Fokuspunkt sitzt =====
-- Auf 70 Prozent der Figurenhöhe -- also auf Brust-/Schulterhöhe.
--
-- Das ist der Wert, den Verfolgerkameras üblicherweise nehmen, und er hat zwei Gründe.
-- Tiefer (Hüfte oder Mitte) drückt die Figur ins untere Bild und man sieht vor allem Himmel.
-- Höher (Kopf) sieht man den Boden nicht mehr, auf dem man steht -- bei einer Figur, die
-- Häuser zertritt, ist genau das die wichtigste Auskunft.
--
-- Bewusst NICHT am Kopf festgemacht: der Kopf nickt und dreht sich mit der Gangart, und
-- ein Fokus, der mitwackelt, macht das Bild unruhig. Der Punkt hängt am Rumpf und bleibt
-- ruhig, während die Figur sich bewegt.
--
-- Und bewusst mittig statt über der Schulter: eine Schulterkamera hilft beim Zielen, stört
-- aber, sobald man sich viel dreht und rundum zuschlägt.
local FOCUS_HEIGHT_SHARE = 0.70

-- Waagrecht bleibt der Fokus auf dem Rumpf. Hier stand kurzzeitig eine Verschiebung nach
-- hinten, weil die Figur nach hinten versetzt wirkte -- das war aber ein echter Fehler in der
-- Platzierung des Modells und ist dort behoben (KaijuStageOneCombatAdapter, centreOverRoot).
-- Eine Kamera, die eine falsche Platzierung ausgleicht, verdeckt sie nur.

-- Ab welcher Änderung der Figurenhöhe neu eingestellt wird. Kleine Schwankungen (Atmung
-- des Rigs, ein abgelegtes Teil) sollen die Kamera nicht anfassen.
local HEIGHT_CHANGE_THRESHOLD = 2

-- Untergrenze nach dem Einstellen. Bewusst klein: der Spieler soll bis nah heranfahren
-- können, er soll nur nicht dort ANFANGEN.
local FREE_MIN_DISTANCE = 4

-- ===== Das Ruckeln bei schweren Momenten =====
-- Das Rig meldet drei Ereignisse ueber sein RemoteEvent "KaijuFeedback": Land, Discharge
-- und FocusFire. Das Paket nennt sie ausdruecklich "camera/UI cues" und ueberlaesst es dem
-- Spiel, was daraus wird.
--
-- Bis hierhin wurde gar nichts daraus. Roblox staut Ereignisse ohne Empfaenger und verwirft
-- sie irgendwann mit einer Warnung im Log ("Remote event invocation queue exhausted ...
-- did you forget to implement OnClientEvent?"). Genau die stand in der Ausgabe.
--
-- Ein Aufschlag von etwas, das zwanzig bis hundert Studs hoch ist, muss man SPUEREN. Der
-- Ausschlag waechst deshalb mit der Figur -- gedeckelt, denn eine Kamera, die zu weit
-- ausschlaegt, macht den Spieler seekrank statt beeindruckt.
local CUE_STRENGTH = { Land = 1.0, Discharge = 0.7, FocusFire = 0.3 }
local SHAKE_SECONDS = 0.35
local SHAKE_PER_HEIGHT = 0.012 -- Studs Ausschlag je Stud Figurenhoehe
local SHAKE_MIN, SHAKE_MAX = 0.15, 2.5

-- Der ruhende Fokuspunkt. Das Ruckeln wird DARAUF addiert, nie hineingeschrieben -- sonst
-- bliebe die Kamera nach dem letzten Ausschlag schief stehen.
local baseOffset = Vector3.zero
local shakeAmplitude, shakeStartedAt = 0, 0

local function currentHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

RunService.Heartbeat:Connect(function()
	if shakeAmplitude <= 0 then
		return
	end
	local humanoid = currentHumanoid()
	if not humanoid then
		shakeAmplitude = 0
		return
	end

	local elapsed = os.clock() - shakeStartedAt
	if elapsed >= SHAKE_SECONDS then
		shakeAmplitude = 0
		humanoid.CameraOffset = baseOffset
		return
	end

	-- Linear abklingend: der erste Schlag ist der harte, danach beruhigt es sich.
	local strength = shakeAmplitude * (1 - elapsed / SHAKE_SECONDS)
	humanoid.CameraOffset = baseOffset
		+ Vector3.new(
			(math.random() - 0.5) * 2 * strength,
			(math.random() - 0.5) * 2 * strength,
			(math.random() - 0.5) * 2 * strength
		)
end)

local function shake(kind, height)
	local strength = CUE_STRENGTH[kind]
	if not strength then
		return
	end
	shakeAmplitude = strength * math.clamp(height * SHAKE_PER_HEIGHT, SHAKE_MIN, SHAKE_MAX)
	shakeStartedAt = os.clock()
end

local function applyDistance(distance)
	-- Reihenfolge zählt: erst die Obergrenze anheben, sonst klemmt die Untergrenze gegen
	-- eine Obergrenze, die noch zu klein ist.
	player.CameraMaxZoomDistance = math.max(distance, player.CameraMaxZoomDistance)
	player.CameraMinZoomDistance = distance

	-- Ein Bild lang stehen lassen, damit die Kameraskripte die Klemmung übernehmen, dann
	-- die Untergrenze wieder freigeben.
	task.defer(function()
		RunService.Heartbeat:Wait()
		player.CameraMinZoomDistance = FREE_MIN_DISTANCE
		player.CameraMaxZoomDistance = math.max(distance, DISTANCE_MAX)
	end)
end

local function watchCharacter(character)
	local lastHeight = nil

	local function reconsider()
		if player.Character ~= character or not character.Parent then
			return
		end
		-- Gemessen wird das MODELL, wenn eines hängt -- nicht die Figur samt verstecktem
		-- Avatar. Der Avatar fällt gegen das Modell zwar kaum ins Gewicht, aber der Hüllquader
		-- der Figur enthält ihn mit, und gemeint ist das, was man sieht.
		local worn = StageModels.FindEquipped(character)
		local gemessen = worn or character
		local ok, cframe, size = pcall(function()
			return gemessen:GetBoundingBox()
		end)
		if not ok or not size or size.Y <= 0 then
			return
		end
		local height = size.Y
		if lastHeight and math.abs(height - lastHeight) < HEIGHT_CHANGE_THRESHOLD then
			return
		end
		lastHeight = height

		local distance = math.clamp(height * DISTANCE_PER_HEIGHT, DISTANCE_MIN, DISTANCE_MAX)
		applyDistance(distance)

		-- ===== Der Fokuspunkt =====
		-- CameraOffset zählt vom Rumpf des (versteckten) Avatars aus, nicht von der Mitte
		-- der sichtbaren Figur. Deshalb wird die Differenz ausgerechnet, statt einen Anteil
		-- der Höhe zu nehmen: bei einem angezogenen Modell steht der Avatar-Rumpf fast am
		-- Boden, während die Figur zwanzigmal so hoch ist. Ein blosser Anteil landete
		-- zwischen den Beinen -- genau das war zu sehen.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if humanoid and root then
			local bottomY = cframe.Position.Y - height / 2
			local focusY = bottomY + height * FOCUS_HEIGHT_SHARE

			baseOffset = Vector3.new(0, focusY - root.Position.Y, 0)
			humanoid.CameraOffset = baseOffset
		end

		print(string.format("[Kaiju Debug] Kamera: Entfernung %.0f, Fokus %.0f ueber dem Rumpf "
			.. "(Figurenhoehe %.0f).", distance, baseOffset.Y, height))
	end

	-- Erst im nächsten Durchlauf messen: beim Spawnen sind noch nicht alle Teile da, und ein
	-- angezogenes Modell hängt sich erst Sekundenbruchteile später ein.
	local ausstehend = false
	local function spaeterMessen()
		if ausstehend then
			return
		end
		ausstehend = true
		task.defer(function()
			ausstehend = false
			reconsider()
		end)
	end

	-- ===== Die Rueckmeldungen des Rigs abonnieren =====
	-- Das RemoteEvent entsteht erst mit dem Modell und verschwindet mit ihm. Deshalb wird
	-- bei jedem Kind gesucht -- dieselbe Gelegenheit, bei der ohnehin neu gemessen wird.
	--
	-- Ohne Empfaenger staut Roblox die Ereignisse und verwirft sie mit einer Warnung. Das
	-- allein waere Grund genug, sie zu abonnieren; die Kamera bekommt dadurch noch etwas.
	local abonniert = nil

	local function abonniereFeedback()
		local model = StageModels.FindEquipped(character)
		local remote = model and model:FindFirstChild("KaijuFeedback")
		if not remote or not remote:IsA("RemoteEvent") or abonniert == remote then
			return
		end
		abonniert = remote
		remote.OnClientEvent:Connect(function(kind)
			if player.Character ~= character then
				return
			end
			shake(kind, lastHeight or 20)
		end)
	end

	character.ChildAdded:Connect(function()
		spaeterMessen()
		abonniereFeedback()
	end)
	character.ChildRemoved:Connect(spaeterMessen)
	spaeterMessen()
	abonniereFeedback()
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end
