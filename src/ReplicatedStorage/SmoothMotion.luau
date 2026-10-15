-- ModuleScript: SmoothMotion
-- Ort in Studio: ReplicatedStorage
--
-- Die gemeinsame Verabredung zwischen Server und Client darüber, wie ein serverseitig
-- bewegtes Modell beim Betrachter flüssig wird. Hier stehen nur die Namen und der Setzer;
-- die Glättung selbst macht SmoothMotionClient.
--
-- ===== Warum es das braucht =====
-- Roblox interpoliert beim Betrachter nur, was der Physik unterliegt. Ein Teil, dessen
-- CFrame der Server fortlaufend SETZT -- und genau das tun Helikopter, Militär und Guardian
-- über PivotTo -- wird dagegen mit der Netzwerk-Replikationsrate übertragen und ohne
-- Zwischenschritte eingesetzt. Diese Rate liegt deutlich unter der Bildrate: der Server
-- rechnet butterweich, beim Betrachter kommt es gestückelt an. Gemeldet am 04.10.2026 für
-- den Verkehrshelikopter der Alarmstufe 1, der am auffälligsten ruckelte.
--
-- ===== Warum der Server die Bewegung behält =====
-- Naheliegend wäre, die Bewegung ganz auf den Client zu verlegen. Beim Helikopter ginge das
-- -- er ist reine Kulisse. Bei Guardian und Militär nicht: an ihrer Position hängt
-- Gameplay. Der Guardian misst in attackIfInRange den Abstand zur Spielerfigur, das Militär
-- prüft TankAttackRange und RocketLauncherAttackRange. Bestimmte der Client, wo sie stehen,
-- kennte der Server ihre Position nicht mehr -- Schaden und Reichweite liefen auseinander,
-- und der Bosskampf wäre von dort aus beeinflussbar.
--
-- Deshalb die Aufteilung: der Server entscheidet und bewegt weiter wie bisher, der Client
-- glättet nur, was er zu sehen bekommt.
--
-- ===== Warum ein Attribut und nicht der CFrame selbst =====
-- Weil der Client sonst gegen sich selbst messen würde. Er überschreibt den CFrame des
-- Modells lokal (das ist die Glättung) -- läse er sein Ziel von dort, läse er seinen eigenen
-- geglätteten Zwischenwert und käme nie an. Das Attribut schreibt nur der Server; es ist der
-- einzige Wert, der die Absicht des Servers unverfälscht trägt.
local SmoothMotion = {}

-- Modelle mit diesem Tag werden clientseitig geglättet.
SmoothMotion.Tag = "SmoothMotion"

-- Darin steht die Pose, die der Server MEINT. CFrame ist ein gültiger Attributtyp.
SmoothMotion.TargetAttribute = "MotionTarget"

-- ===== Nur die Wurzel bewegen, nicht das ganze Modell =====
-- Steht dieses Attribut, setzt der Client die PrimaryPart und sonst nichts.
--
-- Für ein Modell, dessen Gelenke animiert werden, ist das der EINZIGE richtige Weg.
-- Model:PivotTo setzt jedes Teil einzeln und überschreibt damit die Pose, die eine
-- Motor6D-Animation gerade herstellt -- die Figur steht dann starr da und bewegt beim
-- Laufen die Beine nicht.
--
-- Genau das ist passiert: der CityDefenderService bewegt animierte Guardians seit dem
-- 26.09.2026 bewusst nur über ihre Wurzel, und die Glättung hat daraus am 04.10.2026
-- wieder ein PivotTo auf das ganze Modell gemacht -- clientseitig und im RenderStepped,
-- also an der Stelle, an der es garantiert gewinnt. Gemeldet am 14.10.2026: "Ich sehe noch
-- keine Laufanimation der Wächter."
--
-- Die übrigen Teile folgen trotzdem: das Rig schweisst sie als einen Körper an die Wurzel.
SmoothMotion.RootOnlyAttribute = "MotionRootOnly"

-- Zeitkonstante der Glättung in Sekunden: nach dieser Zeit hat der Client rund zwei Drittel
-- des Weges zum Ziel zurückgelegt. Klein genug, dass nichts sichtbar nachschleppt, gross
-- genug, dass die Replikationsschritte verschwinden.
SmoothMotion.TimeConstant = 0.08

-- Ab diesem Sprung wird NICHT geglättet, sondern sofort gesetzt. Ein Spawn, ein Teleport
-- oder ein Stadtwechsel ist kein Bewegungsschritt -- wer ihn glättet, lässt das Modell
-- sichtbar durch die halbe Karte fliegen.
SmoothMotion.SnapDistance = 60

-- ===== Was der Server aufruft =====
-- Einmal beim Erzeugen des Modells (Track), danach bei jedem Bewegungsschritt (SetTarget).
--
-- SetTarget ersetzt den PivotTo-Aufruf NICHT, es tritt daneben: der Server braucht das
-- Modell weiter an seiner Stelle, sonst messen seine eigenen Reichweitenprüfungen ins Leere.
function SmoothMotion.Track(model)
	if not model then
		return
	end
	local CollectionService = game:GetService("CollectionService")
	if not CollectionService:HasTag(model, SmoothMotion.Tag) then
		CollectionService:AddTag(model, SmoothMotion.Tag)
	end
end

function SmoothMotion.SetTarget(model, cframe)
	if not model or not cframe then
		return
	end
	model:SetAttribute(SmoothMotion.TargetAttribute, cframe)
end

-- Sagt der Glättung, dass dieses Modell animierte Gelenke hat und deshalb nur an der
-- Wurzel bewegt werden darf (siehe RootOnlyAttribute). Mehrfach aufrufbar: SetAttribute mit
-- demselben Wert tut nichts.
function SmoothMotion.SetRootOnly(model, rootOnly)
	if not model then
		return
	end
	model:SetAttribute(SmoothMotion.RootOnlyAttribute, rootOnly and true or nil)
end

-- Bewegt das Modell UND meldet dem Client das Ziel -- der übliche Fall, in einer Zeile.
-- Wer beides getrennt braucht (etwa weil die Pose aus mehreren Schritten entsteht), nimmt
-- SetTarget einzeln.
function SmoothMotion.PivotTo(model, cframe)
	if not model or not cframe then
		return
	end
	model:PivotTo(cframe)
	SmoothMotion.SetTarget(model, cframe)
end

return SmoothMotion
