-- Script: CityStreamingService
-- Ort in Studio: ServerScriptService
-- Aeussere Stadtmodelle streamen in Teilen. Innere, absichtlich atomare
-- Teilmodelle bleiben erhalten. MegaCity nutzt City statt CityName und einen
-- Buildings-Ordner; beide Containerformen muessen erfasst werden.
local Workspace = game:GetService("Workspace")
local eingerichtet = setmetatable({}, { __mode = "k" })
local ordnerVerbunden = setmetatable({}, { __mode = "k" })

local function stadtName(instanz)
	if not instanz:IsA("Model") and not instanz:IsA("Folder") then return nil end
	local name = instanz:GetAttribute("CityName") or instanz:GetAttribute("City")
	return type(name) == "string" and name ~= "" and name or nil
end

-- Durch Organisationsordner gehen, am ersten Model aufhoeren. Ein Atomic
-- innerhalb eines Gebaeudes darf weiter eine zusammenhaengende Einheit sein.
local function normalesStreaming(instanz)
	if instanz:IsA("Model") then
		instanz.ModelStreamingMode = Enum.ModelStreamingMode.Default
	elseif instanz:IsA("Folder") then
		if ordnerVerbunden[instanz] then return end
		ordnerVerbunden[instanz] = true
		instanz.ChildAdded:Connect(normalesStreaming)
		for _, kind in ipairs(instanz:GetChildren()) do normalesStreaming(kind) end
	end
end

local function richteStadtEin(container)
	local name = stadtName(container)
	if not name or eingerichtet[container] then return end
	-- Nur den Stadtcontainer behandeln, keine Einheiten oder Gebaeudeteile,
	-- die dasselbe Attribut innerhalb einer bereits zugeordneten Stadt tragen.
	local vorfahr = container.Parent
	while vorfahr and vorfahr ~= Workspace do
		if stadtName(vorfahr) then return end
		vorfahr = vorfahr.Parent
	end
	eingerichtet[container] = true
	if container:IsA("Model") then
		container.ModelStreamingMode = Enum.ModelStreamingMode.Default
	end
	container.ChildAdded:Connect(normalesStreaming)
	for _, kind in ipairs(container:GetChildren()) do normalesStreaming(kind) end
	print("[Kaiju Debug] Stadt-Streaming: " .. name .. " (" .. container:GetFullName()
		.. ") nutzt normales Streaming -- keine ganze Stadt dauerhaft geladen.")
end

local function verbindeStaedte(cities)
	if ordnerVerbunden[cities] then return end
	ordnerVerbunden[cities] = true
	cities.ChildAdded:Connect(richteStadtEin)
	for _, container in ipairs(cities:GetChildren()) do richteStadtEin(container) end
end

if not Workspace.StreamingEnabled then
	warn("[CityStreamingService] StreamingEnabled ist AUS -- alle Staedte werden geladen.")
	return
end
-- NUR StreamingTargetRadius. "StreamingMinRadius" gibt es in dieser Roblox-Fassung nicht
-- mehr -- das Lesen warf "is not a valid member of Workspace", und weil der Fehler
-- ungefangen war, brach das Skript HIER ab: alles darunter, also die ganze Einrichtung der
-- Staedte, lief nie. Im Log vom 06.10.2026 stand der Fehler bei jedem Serverstart.
print(string.format("[Kaiju Debug] Streaming-Zielradius: %d Studs.",
	Workspace.StreamingTargetRadius))
Workspace.ChildAdded:Connect(function(instanz)
	if instanz.Name == "Cities" then verbindeStaedte(instanz) end
	richteStadtEin(instanz)
end)
local citiesOrdner = Workspace:FindFirstChild("Cities")
if citiesOrdner then verbindeStaedte(citiesOrdner) end
-- Sofort auch externe Stadtcontainer erfassen; kein Warten auf einen optionalen
-- Cities-Ordner, waehrenddessen die komplette Stadt schon repliziert wuerde.
for _, instanz in ipairs(Workspace:GetDescendants()) do richteStadtEin(instanz) end
