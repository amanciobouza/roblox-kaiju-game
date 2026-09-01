# We Are Trenchborn

Roblox-Spiel. Der Spieler steuert eine von drei Hauptfiguren einer Uhrenkollektion
und zerstört eine Stadt, die sich mit steigender Alarmstufe zunehmend wehrt.

| Figur | Steht für | Spielgefühl |
|---|---|---|
| Kaiju | Power | Brutal, Zerstörung im Vordergrund |
| Jaeger | Control | Trifft gezielt Schwachstellen der Stadtverteidigung, um länger Belohnungen sammeln zu können |
| Ronin | Purpose | Agil, nutzt Combos für maximalen Schaden |

Die drei Figuren bilden zugleich die drei Kapitel des Spiels.

Alle Kommunikation und alle Code-Kommentare auf **Deutsch**.

---

## Arbeitsweise

### Rojo-Workflow – wichtigste Regel

Skripte werden **ausschließlich im Dateisystem** bearbeitet, niemals in Roblox Studio.
Rojo synchronisiert in eine Richtung: Repo → Studio. Wer in Studio editiert, verliert
seine Änderungen beim nächsten Sync.

Studio bleibt zuständig für: Welt, Modelle, Terrain, Testen.

```
rojo serve          # Port 34873
```

Danach im Studio-Plugin verbinden. Die Änderungsvorschau vor dem Bestätigen lesen –
Löschungen an Modellen oder Workspace-Inhalten sind ein Warnsignal.

### Erwartungen an Änderungen

- **Selbst prüfen, was prüfbar ist.** Vor der Übergabe kontrollieren, ob eine
  Änderung überhaupt funktionieren kann: Syntax, Pfade, Namen, Modul-Rückgabewerte,
  ob referenzierte Instanzen und Events tatsächlich existieren, ob Aufrufsignaturen
  zusammenpassen. Nicht ungetesteten Code als fertig übergeben.
- **Übergeben, was nicht prüfbar ist.** Alles Laufzeit- oder Gefühlsabhängige –
  Kameraführung, Timing, Spielbalance, visuelle Wirkung – geht an Amancio.
  Dabei benennen, was genau er prüfen soll und worauf zu achten ist.
- **Kleine, geprüfte Schritte.** Amancio testet zwischen den Änderungen im Studio.
  Lieber eine Sache sauber als drei auf einmal.
- **Keine ungefragten Refactorings.** Auch nicht "nebenbei mitgemacht", während
  etwas anderes repariert wird.
- **Feedback ist oft qualitativ** ("wirkt zu zufällig", "zu rasch", "gestellt").
  Das sind Regie-Anmerkungen zum Gefühl, keine technischen Spezifikationen –
  entsprechend interpretieren statt wörtlich umsetzen.
- **Bei Unklarheit nachfragen**, statt eine Annahme zu treffen und weiterzubauen.

### Testablauf

Es gibt keine automatisierten Tests. Geprüft wird lokal in Roblox Studio, anhand
von Debug-Ausgaben und anhand von Amancios Spielerlebnis und Bericht.

Daraus folgt für Änderungen: Debug-Ausgaben an den Stellen einbauen, die den
Nachweis liefern, dass die Änderung greift. Bei der Übergabe benennen, was in der
Ausgabe erscheinen soll und was im Spiel zu sehen sein müsste – sonst kann
Amancio nicht unterscheiden, ob etwas nicht funktioniert oder er nur an der
falschen Stelle geschaut hat.

### Spec-getriebene Entwicklung

Wiederkehrender Fehler im Bestand: eine Absicht ist dokumentiert, aber im Code
nicht umgesetzt, und niemand merkt es. Dagegen stehen **Specs** – Module, die
festhalten, was gelten *soll*, zusammen mit Regeln, die es prüfen.

```
src/ReplicatedStorage/Specs/
├── SpecRunner.luau      Regel-Ausführung + Ausgabeformat (von beiden Prüfern geteilt)
└── <System>Spec.luau    je ein Modul pro System
tools/
├── spec-check.luau      kopfloser Prüfer (ohne Roblox)
└── spec_check_hook.py   Stop-Hook-Wrapper
```

**Aufbau einer Regel**: `id`, `intent` (die Absicht, nicht die Mechanik),
optional `check(ctx)` → **Liste** von Verstößen. Eine Regel *ohne* `check` ist
eine weiche Aussage – nicht maschinell prüfbar, beim Abgleich mitzulesen.
`knownViolations` führt die heute bekannten Abweichungen als Präfix des
Verstoßtextes; `needsRuntime` / `needsWorkspace` markieren, was der kopflose
Prüfer nicht sehen kann.

**Spec-Module importieren nichts.** Alles kommt über den `ctx`. Nur so läuft
dieselbe Datei in Studio und außerhalb. Eine Regel holt sich nichts selbst.

**Zwei Prüfer über denselben Regeln:**

| | kopflos (`luau tools/spec-check.luau`) | Studio |
|---|---|---|
| Läuft | am Ende jedes Claude-Zuges, per Stop-Hook | beim Serverstart + Knopf im Debug-Panel |
| Sieht | nur die Config-Module | zusätzlich Workspace und laufenden Zustand |

**Präskriptiv mit erfasstem Rückstand**: die Spec sagt, was gelten soll. Bekannte
Abweichungen laufen als `knownViolations` bewusst durch – nur ein **neuer**
Verstoß ist eine Regression und hält den Stop-Hook an. Der Rückstand bleibt als
Aufgabenliste sichtbar, ohne das Signal zu ersticken.

Die Abschlusszeile kommt immer, auch bei null Verstößen – sonst lässt sich
„sauber" nicht von „der Prüfer lief gar nicht" unterscheiden.

Zwei Einschränkungen: Luau hat **kein `io`-Modul**, der kopflose Prüfer kann also
keine Verzeichnisse durchsuchen (die Spec-Liste in `tools/spec-check.luau` ist von
Hand geführt) und keine Quelltexte lesen. Und Regeln über gebaute Modelle sind
zwangsläufig `needsRuntime` – die laufen nur in Studio.

---

## Verzeichnisstruktur

```
src/
├── ReplicatedStorage/       → ReplicatedStorage (Configs, Utils, RemoteEvents)
├── ReplicatedFirst/         → ReplicatedFirst (LoadingScreen)
├── ServerScriptService/     → ServerScriptService (Kernlogik)
├── StarterPlayerScripts/    → StarterPlayer.StarterPlayerScripts (Client)
└── StarterGui/              → StarterGui (leer – UI wird zur Laufzeit erzeugt)

packages/
└── trenchborn-asset-workshop/   Git-Submodul → ReplicatedStorage.TrenchbornAssetWorkshop
```

Nicht im Repo, bleibt in Studio: Workspace (Stadt, Terrain), ServerStorage
(BarricadeModels, GuardianModels, KaijuModels, MilitaryModels, Effects).

### Dateiendungen bestimmen die Skriptklasse

| Endung | Instanz |
|---|---|
| `.luau` | ModuleScript |
| `.server.luau` | Script |
| `.client.luau` | LocalScript |

Beim Anlegen neuer Dateien bewusst wählen. Eine falsche Endung erzeugt Fehler,
die in Studio schwer zu finden sind.

`.meta.json` neben einer Datei setzt Zusatzeigenschaften, etwa `Disabled`.

---

## Architektur

### RemoteEvents

Werden zur Laufzeit über `RemoteEventUtils.GetOrCreate()` angelegt, nicht von Hand
in Studio. Die `.model.json`-Dateien in `src/ReplicatedStorage` sind die
versionierten Gegenstücke.

### Alert-System

Eskalation der Stadtverteidigung von Stufe 0 bis 5. Konfiguration in
`CityAlertConfig.luau`.

Jede Stufe hat eine Absicht, nicht nur eine Mechanik. Bei Änderungen ist die
Absicht der Maßstab.

**Die Absicht jeder Stufe steht in `ReplicatedStorage/Specs/CityAlertSpec.luau`** –
dort, wo auch die Regeln stehen, die sie durchsetzen. Das ist die maßgebliche
Quelle; hier steht bewusst keine zweite Fassung, sonst laufen die beiden
auseinander (siehe „Spec-getriebene Entwicklung").

Die Eskalation verlagert den Spieler schrittweise: erst Beobachtung, dann
geringerer Ertrag, dann räumliche Umlenkung, dann Kampf, dann Vertreibung.

Beteiligte Dienste: `CityAlertService`, `EscalationService`, `CityDefenderService`,
`MilitaryService`, `BarricadeClusterService`, `AlertHelicopterService`.

**Aufgabenlisten verwenden feste Zielwerte aus der Config**, keine mitlaufenden
Nenner. Live aktualisierte Ziele wirken unberechenbar; feste Ziele wirken
erreichbar und planbar.

### Prolog

`PrologueOrchestrator.server.luau` steuert die Sequenz und lädt `StoryBeatService`
sowie `PrologueReinforcementService` als Module.

Clientseitig: `PrologueCinematicClient`, `PrologueLetterboxClient`,
`PrologueQueueClient`, `PrologueTutorialClient`.

### CollectionService-Tags

`KaijuHouse` – jedes vom Spieler zerstörbare Gebäude. Daran hängen unter anderem
Belohnungen, Zerstörung und Respawn. Zentraler Tag des Spiels; Änderungen daran
wirken breit.

### Die zwei „Trenchborn"-Quellen

Der gemeinsame Name täuscht – die beiden Quellen machen Verschiedenes und stehen
nicht in Konkurrenz zueinander.

| | `src/ServerScriptService/TrenchbornInstallers/` | `packages/trenchborn-asset-workshop/` |
|---|---|---|
| Inhalt | Stadtviertel (Marina L3, Pier L2) | Gegner-Assets (Warden-I Shepherd, Marshal Roadblock) |
| Arbeitsweise | findet ein **bestehendes** Modell im Workspace und stattet es aus | **erzeugt** Geometrie aus Code (`GoldenMaster.Build`) |
| Ergebnis | HP pro Sektion, `KaijuHouse`-Tags, EnergyType, Respawn-Gruppen | Modell + Dressing + Gameplay + Reactions |

**Beide laufen im Spiel nicht mit.** Kein Skript unter `src/` requiret sie.

Die Installer sind **einmalige Studio-Werkzeuge**: `M.Install()` aus der Command Bar
aufrufen, danach ist das Modell ausgestattet. Sie liegen im Repo, damit die
Ausstattungsregeln versioniert sind – nicht, weil sie zur Laufzeit gebraucht werden.
Erkennbar auch daran, dass die älteren Fassungen `Script.Source` schreiben, was aus
einem laufenden Spiel-Skript gar nicht erlaubt ist. Der neueste Installer
(`MarinaYachtHarbor_L3`, Final_v02) verzichtet darauf und arbeitet nur noch über
Attribute und Tags – das ist die Bauweise, an der sich neue Installer orientieren
sollten.

Vom Submodul wird nur die Hälfte eingebunden: `default.project.json` mountet
`package.project.json`, und das enthält ausschließlich `src/ReplicatedStorage/`.
Der `WorkshopBootstrap`, der die Demo-Szene aufbaut, bleibt im eigenen Workshop-Place
(Port 34872).

### Debug-Ausgaben

Präfix `[Kaiju Debug]` für alle Debug-Ausgaben.

`DebugPanelClient` ist ein Gamemaster-Werkzeug: eine Oberfläche im laufenden
Spiel, um Events auszulösen, Level und Stärke des Spielers zu ändern und
Ähnliches. Wer neue Systeme baut, sollte prüfen, ob sie dort zugänglich gemacht
werden sollten – das Panel ist der Hauptweg, mit dem Amancio testet.

### Namensgebung

Interne Systemnamen werden bewusst von spielbaren Inhalten getrennt, damit es
keine Kollisionen gibt – etwa `CityDefender` (internes System) gegenüber der
spielbaren Jaeger-Fraktion.

Der Name `Kaiju` steckt aus der Entstehungsgeschichte in vielen internen Namen
(`KaijuHouse`, `[Kaiju Debug]`, Repo-Name), obwohl das Spiel „We Are Trenchborn"
heißt und Kaiju nur eine der drei Figuren ist. Das bleibt so – nicht umbenennen.

---

## Bekannte Fallstricke

### `WaitForChild` ohne Timeout

Verbreitetes Muster im Bestand:

```lua
local X = require(ServerScriptService:WaitForChild("StoryBeatService"))
```

Ohne zweites Argument wartet das unbegrenzt. Existiert das Objekt nie, hängt das
Skript stumm – kein Fehler, kein Hinweis. Bei neuem Code Timeout setzen und den
Fehlerfall behandeln.

### Kamera-Konflikte brauchen Session-IDs

Mehrere gleichzeitig laufende Kameraschleifen kämpfen gegeneinander. Jede Schleife
braucht eine Session-ID und muss sich beenden, sobald eine neue Session beginnt.
Ohne das entstehen Flacker- und Sprungfehler, die schwer zu reproduzieren sind.

### Kamera-Moduswechsel sind sichtbar

Selbst ein bis zwei Einzelbilder im Custom-Modus fallen auf. Übergaben zwischen
Kamerasystemen müssen sauber sein; Zwischenzustände sind keine Option.
(Die "Peek-and-Blend"-Technik wurde aus genau diesem Grund verworfen.)

### Regressionen

Änderungen an einem System haben mehrfach Fehler an anderer Stelle ausgelöst.
Vor größeren Eingriffen committen, damit `git bisect` möglich bleibt.

---

## Werkzeuge

- **Rojo 7.7** über Rokit (`rokit.toml` im Repo)
- **Rojo Studio-Plugin** – muss zur CLI-Hauptversion passen
- **Luau 0.736** über Rokit – für den kopflosen Spec-Prüfer. Muss aus dem
  Projektstamm aufgerufen werden, sonst findet Rokit die `rokit.toml` nicht.
- Suche im Terminal: `Select-String -Path src -Pattern "…" -Recurse`
  (`findstr` liefert bei UTF-8 unvollständige Ergebnisse)

### Submodul aktualisieren

```
git submodule update --remote packages/trenchborn-asset-workshop
git commit -am "Workshop-Submodul aktualisiert"
```

---

## Von Amancio zu prüfen und zu ergänzen

Diese Punkte sind teils erschlossen und teils noch offen:

- [ ] **`_G`-Globals**: Werden im Bestand verwendet, aber Herkunft und Zweck sind
      nicht dokumentiert. Bei Gelegenheit erfassen – oder ablösen.
- [ ] **Workshop und Spiel zusammenführen?** Der Warden-I Shepherd ist laut seiner
      Spezifikation eine „Guardian Defense Platform" – inhaltlich ein Kandidat für
      `CityDefenderService`. Der lädt seine Guardians aber als fertiges Model aus
      `ServerStorage.GuardianModels.<Stadt>`, während der Workshop Geometrie aus Code
      erzeugt. Diese Brücke fehlt. Solange sie fehlt, liegen 15 Module ungenutzt in
      `ReplicatedStorage`.
- [ ] **`TB_TrenchbornBeast_GoldenMaster`** in ServerStorage – kommt im Repo nirgends
      vor, nur hier. Was ist das, und wird es noch gebraucht?
- [ ] **Fraktionswechsel**: Wählt der Spieler eine Figur dauerhaft, oder wechselt
      er zwischen den Kapiteln? Was schaltet `FactionUnlockService` frei?
- [ ] **Datenhaltung**: Wie wird Spielerfortschritt gespeichert (DataStore-Struktur)?
- [ ] **Bezug zur Uhrenkollektion**: Soll sich Bildsprache oder Mechanik an den
      Uhren orientieren, oder ist es reine Namensgebung?