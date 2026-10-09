# Mega City Final Assembly

Quelle: Workshop-Branch `feat/mega-city-harbor-gate`, Commit `7e630a1cb12b60d55b75ab2e7bdc52c3ba239d0b`.

85 Gebaeude aus 21 Typen, Strassen, Eisspalte, Terrain-Hilfen und Terrain-Proxys. Die 89 nativen Modellpakete werden durch Rojo als Vorlage nach ServerStorage.MegaCityFinalAssembly synchronisiert.

## Import in Studio

Rojo fuer dieses Spiel auf Port 34873 synchronisieren. Im Bearbeitungsmodus in der Befehlsleiste ausfuehren:

```lua
require(game.ServerScriptService.TrenchbornInstallers.MegaCity.MegaCityFinalAssembly).Install()
```

Ergebnis: Workspace.MegaCity_FinalAssembly. Bestehende Staedte werden erhalten. Ein erneuter Import unter demselben Namen wird abgewiesen. Das gesamte Modell kann in Studio verschoben werden. Optional sind Parent, Name und Pivot als Optionen moeglich.

Die Ausgabe beginnt mit `[MegaCity] 85 Gebaeude / 21 Typen importiert`.

Die native Assembly enthaelt bereits KaijuHouse-Tags und die Workshop-Gebaeudeskripte. Die Abstimmung dieser Skripte mit den Spielsystemen, Gebaeudewerten, Stadtverteidigung und Respawn ist noch in Studio zu pruefen. Der Import allein bestaetigt keine fertige Gameplay-Integration. Vorlagen in ServerStorage laufen nicht.

TerrainGuides sind Konstruktionshilfen. TerrainProxy enthaelt vorlaeufige Landschaft und Brueckenunterbauten. Wasser, Fels, Eisdecke, Anschluss an LargeCity und die endgueltige Beleuchtung werden in Studio gestaltet. Nach dem Terrainbau die jeweiligen Hilfen ausblenden oder entfernen.

## Pruefung

Workshop-Validator: 85 Gebaeude, 62.837 Gebaeudeteile, 77.113 BaseParts insgesamt, 85 erhaltene Skripte und 25 Smoke-Emitter. Geometrie, Transformationen, Referenzen, PrimaryParts, Tags und Beschilderung geprueft. Spiel-Rojo-Build erfolgreich.

In Play insbesondere Gebaeudeschaden/Respawn, Effekte, Kamerafuehrung, Wege fuer den groessten Kaiju und Leistung der gesamten Stadt pruefen. Kein Guardian-Modell enthalten.

`layout.json` und `layout.svg` dokumentieren die Platzierung; `WORKSHOP-REVIEW.md` enthaelt die urspruengliche Workshop-Abnahme.
