local Portals = workspace:WaitForChild("Portals")
local portal = Portals:WaitForChild("Portal_1")

for _, waveName in ipairs({
	"Wave_Left",
	"Wave_Center",
	"Wave_Right"
	}) do

	local wave = portal:WaitForChild(waveName)

	print("")
	print("===== " .. waveName .. " =====")

	local count = 0

	for _, obj in ipairs(wave:GetDescendants()) do
		if obj:IsA("Bone") then
			count += 1
			print(obj.Name)
		end
	end

	print("TOTAL BONES:", count)
end