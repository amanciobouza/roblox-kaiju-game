-- ModuleScript: NumberFormat
-- Ort in Studio: ReplicatedStorage
-- Formatiert große Zahlen kurz: 100000 -> "100k", 1000000 -> "1M", 1000000000 -> "1B",
-- 1000000000000 -> "1T". Wird von Server- und Client-Scripts gemeinsam genutzt, damit
-- überall (Häuser-HP, Coins, Schaden, Kraft-Werte, Evolution-Punkte) dasselbe Format gilt.

local NumberFormat = {}

local UNITS = {
	{ value = 1e12, suffix = "T" },
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "k" },
}

function NumberFormat.Format(number)
	number = number or 0
	local sign = number < 0 and "-" or ""
	number = math.abs(number)

	for _, unit in ipairs(UNITS) do
		if number >= unit.value then
			local shortValue = number / unit.value
			local text = string.format("%.1f", shortValue)
			text = text:gsub("%.0$", "") -- "5.0k" -> "5k", aber "5.3k" bleibt "5.3k"
			return sign .. text .. unit.suffix
		end
	end

	return sign .. tostring(math.floor(number))
end

return NumberFormat