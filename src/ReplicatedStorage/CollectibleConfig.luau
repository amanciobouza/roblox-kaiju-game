-- ModuleScript: CollectibleConfig
-- Ort in Studio: ReplicatedStorage
--
-- Die Fundstücke von Kapitel I: je Stadt ein Gegenstand, versteckt in einem von fünf
-- markierten Gebäuden, zu finden im Fenster von CITY BROKEN.
--
-- ===== Woher die Modelle kommen =====
-- Aus dem Asset-Workshop, als fertige Roblox-Modelle (keine Code-Baumeister wie die
-- Kaiju-Stufen). Sie liegen im Submodul unter collectibles/models und werden über
-- collectibles-package.project.json nach ReplicatedStorage.TrenchbornCollectibles
-- gemountet -- siehe default.project.json.
--
-- Die Namen tragen ihre Nummer mit ("01_GoldenFruit"). Das ist die Reihenfolge des
-- Workshops, und sie bleibt: ein Umbenennen im Spiel würde beim nächsten Workshop-Update
-- wieder auseinanderlaufen.
local CollectibleConfig = {}

CollectibleConfig.FolderName = "TrenchbornCollectibles"

-- ===== Welche Stadt welches Fundstück trägt =====
-- Eine Stadt, ein Gegenstand. Die Reihenfolge folgt der Kampagne (Village zuerst), und
-- damit auch der Nummerierung des Workshops -- das ist kein Zufall, sondern dieselbe
-- Erzählung von früh nach spät.
CollectibleConfig.ByCity = {
	Village = { Model = "01_GoldenFruit", Title = "Golden Fruit" },
	SmallTown = { Model = "02_Emberstone", Title = "Emberstone" },
	City = { Model = "03_EnergyCell", Title = "Energy Cell" },
	LargeCity = { Model = "04_AncientEggshell", Title = "Ancient Eggshell" },
	MegaCity = { Model = "05_AncestorFang", Title = "Ancestor Fang" },
}

-- Wie viele Gebäude markiert werden. In genau einem davon liegt das Fundstück -- welches,
-- steht schon beim Markieren fest (siehe CollectibleService). Fünf Kandidaten heissen: der
-- Spieler muss im Schnitt drei abräumen, und er kann Glück haben.
CollectibleConfig.MarkedBuildings = 5

-- ===== Aufsammeln durch Nähe =====
-- Kein Tastendruck: wer in der freien Zerstörung steht, hat die Hände voll. Der Radius ist
-- gegen die SICHTBARE Figur gemessen, nicht gegen den versteckten Avatar -- bei einer
-- neunzig Studs hohen Gestalt wäre "nah" sonst eine Frage der Skalierung.
CollectibleConfig.PickupRadius = 28
CollectibleConfig.PickupCheckInterval = 0.2

-- ===== Grösse im Spiel =====
-- Entscheidung vom 11.10.2026: das Stück wird NICHT mehr skaliert. Es erscheint in der
-- Grösse, in der der Workshop es gebaut hat.
--
-- Hier standen vorher Vielfache seiner eigenen Ausdehnung (zuerst 6, dann 3), weil die
-- Modelle in Ansichtsgrösse gebaut sind und vor einer neunzig Studs hohen Figur wie
-- Kieselsteine wirken. Der Weg darüber ist jetzt ein anderer: nicht das Stück wird grösser,
-- sondern es schwebt sichtbar hoch über dem gefallenen Haus und trägt einen Effekt.
--
-- Der Wert bleibt als Zahl stehen und wird angewendet -- so ist eine Korrektur eine Zahl
-- und kein Eingriff.
--
-- Verdoppelt am 15.10.2026 (vorher 1): bei Scale 1 war das Stueck ueber dem Truemmerfeld
-- zu klein, um aufzufallen.
CollectibleConfig.WorldScale = 2

-- ===== Wie hoch es über dem Trümmerfeld schwebt, in STUDS =====
-- Absolut und nicht als Vielfaches der Stückhöhe: bei Scale 1 ist das Stück klein, ein
-- relatives Mass hätte es knapp über dem Schutt schweben lassen -- also genau dort, wo man
-- es nicht findet. Diese Höhe ist am Kaiju gemessen, nicht am Stück: sie soll ihm etwa in
-- Kopfhöhe entgegenkommen.
CollectibleConfig.HoverHeight = 26

-- Wie schnell es sich dreht, in Umdrehungen je Sekunde. Die Drehung macht der Client
-- (siehe CollectibleClient) -- sie ist Zierde und hat auf dem Server nichts zu suchen.
CollectibleConfig.SpinSpeed = 0.35

-- Tag am Stück in der Welt. Daran erkennt der Client, was er drehen und schweben lassen
-- soll, ohne dass der Server ihm je ein Ereignis dafür schicken muss.
CollectibleConfig.WorldTag = "CollectibleInWorld"

-- ===== Der Auftritt =====
-- Es fährt beim Erscheinen aus dem Schutt nach oben. Kurz, aber nicht sofort: ein Stück,
-- das einfach dasteht, hat niemand erscheinen SEHEN -- und genau darum geht es.
CollectibleConfig.RiseSeconds = 0.8
CollectibleConfig.RiseFromBelow = 10 -- so viele Studs unter der Schwebehöhe beginnt es

-- Attribut am Gebäude: trägt es ein Fundstück? Steht am Gebäude und nicht in einer Tabelle
-- im Dienst, damit ein Blick in Studio die Antwort zeigt -- bei fünf Kandidaten in einer
-- grossen Stadt ist das der Unterschied zwischen Prüfen und Raten.
CollectibleConfig.MarkerAttribute = "CollectibleCandidate"
CollectibleConfig.CarrierAttribute = "CollectibleCarrier"

function CollectibleConfig.ForCity(cityName)
	return cityName and CollectibleConfig.ByCity[cityName] or nil
end

return CollectibleConfig
