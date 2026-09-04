-- ModuleScript: TopInsetUtils
-- Ort in Studio: ReplicatedStorage
--
-- Hält den Inhalt eines Vollbild-Panels unterhalb der Roblox-Systemleiste.
--
-- ===== Warum der Wert nicht einmal beim Aufbau geholt werden darf =====
-- Beim Start eines LocalScripts ist die Kern-Oberfläche von Roblox oft noch nicht
-- aufgebaut. GetGuiInset() liefert dann 0. Wer damit ein Polster berechnet, bekommt
-- keines -- und Titel und Schliessen-Knopf liegen weiter unter den Roblox-Symbolen.
-- Genau dieser Fehler war schon einmal da; deshalb steht die Begründung hier und nicht
-- in den sieben aufrufenden Skripten.
--
-- ===== Warum TopbarInset und nicht nur GetGuiInset =====
-- TopbarInset beschreibt die tatsächlich belegte Fläche der Leiste. In der neueren
-- Roblox-Oberfläche und auf Geräten mit Aussparung ist die Leiste höher, als der
-- klassische Inset angibt. Es wird der grössere der beiden Werte genommen.

local GuiService = game:GetService("GuiService")

local TopInsetUtils = {}

-- Untergrenze, falls beide Quellen 0 melden: die klassische Leistenhöhe. Lieber ein
-- unnötiges Polster als verdeckte Knöpfe.
local MIN_INSET = 36

-- Luft zwischen Systemleiste und Panel-Kopf.
local EXTRA = 12

function TopInsetUtils.GetInset()
	local inset = GuiService:GetGuiInset().Y
	-- pcall: TopbarInset gibt es nicht in jeder Client-Version.
	local ok, topbar = pcall(function()
		return GuiService.TopbarInset
	end)
	if ok and typeof(topbar) == "Rect" then
		inset = math.max(inset, topbar.Max.Y)
	end
	return math.max(inset, MIN_INSET) + EXTRA
end

-- Nur bei Änderung ausgeben, sonst käme die Zeile bei jedem der sieben Panels erneut.
local lastReported = nil

-- Legt ein UIPadding an `container` und zieht es nach, sobald sich die Leiste ändert.
function TopInsetUtils.Bind(container)
	local padding = Instance.new("UIPadding")
	padding.Name = "TopInsetPadding"
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = container

	local function apply()
		local inset = TopInsetUtils.GetInset()
		padding.PaddingTop = UDim.new(0, inset)
		if inset ~= lastReported then
			lastReported = inset
			print(string.format("[Kaiju-Debug] Systemleisten-Polster: %d px.", inset))
		end
	end

	apply()
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(apply)
	end)
	-- Nachschlag: der erste Aufbau der Kern-Oberfläche löst nicht auf allen Geräten ein
	-- Ereignis aus. Ohne das bliebe auf manchen Clients der Startwert stehen.
	task.delay(2, apply)

	return padding
end

return TopInsetUtils
