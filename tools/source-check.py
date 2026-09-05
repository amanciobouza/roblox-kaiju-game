# -*- coding: utf-8 -*-
"""Quelltext-Prüfer -- findet, was der Spec-Prüfer nicht sehen kann.

    python tools/source-check.py            # prüfen
    python tools/source-check.py --accept   # heutigen Stand als Rückstand erfassen

===== Warum es diesen Prüfer zusätzlich gibt =====
Der Spec-Prüfer (tools/spec-check.luau) prüft ABSICHTEN gegen Konfigurationen. Er kann
aber keinen Quelltext lesen: Luau hat kein io-Modul, das steht so in CLAUDE.md. Genau dort
liegt aber die häufigste Fehlerklasse dieses Projekts -- eine Absicht ist im Code
angelegt, aber nirgends angeschlossen, und niemand merkt es, weil nichts abstürzt.

Eine Regel wurde wieder ENTFERNT: source.client-getorcreate meldete 58 Aufrufstellen, an
denen der Client RemoteEvents über GetOrCreate holte -- was eine lokale, wirkungslose
Kopie erzeugen konnte. Behoben wurde das nicht an den 58 Stellen, sondern in
RemoteEventUtils selbst: auf dem Client wird jetzt gewartet statt erzeugt. Damit hat die
Regel keinen Gegenstand mehr. Eine Regel, die nur noch Erledigtes zählt, macht den
Rückstand unleserlich.

Belege aus dem Bestand, die dieser Prüfer beim ersten Lauf gefunden hat:
  * _G.IncrementAchievementCounter wird geschrieben, aber nie aufgerufen -- daran hängen
    30 Achievements, die nie vergeben werden.
  * _G.StopArmGauntletSession und _G.StopBodyCircuitSession werden gelesen, aber nie
    gesetzt -- die Lesestellen sind nil-geprüft und laufen still ins Leere.
Beide standen vorher von Hand in CLAUDE.md unter "von Amancio zu prüfen".

===== Präskriptiv mit erfasstem Rückstand =====
Gleiche Regel wie beim Spec-Prüfer: die heute bekannten Abweichungen stehen in
tools/source-check-known.txt und laufen bewusst durch. Nur ein NEUER Verstoss ist eine
Regression und hält den Stop-Hook an. Der Rückstand bleibt als Aufgabenliste sichtbar,
ohne das Signal zu ersticken.

Die Abschlusszeile kommt immer, auch bei null Verstössen -- sonst lässt sich "sauber"
nicht von "der Prüfer lief gar nicht" unterscheiden.
"""

import io
import os
import re
import sys
import collections

# Ausgabe fest auf UTF-8. Ohne das schreibt Python unter Windows in der Codepage der
# Konsole (cp1252), waehrend der Stop-Hook die Ausgabe als UTF-8 liest -- Umlaute kamen
# dort als Ersatzzeichen an.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SRC = "src"
KNOWN_FILE = os.path.join("tools", "source-check-known.txt")

# Diese Dateien werden nicht geprüft: Specs beschreiben Absichten und nennen _G-Namen als
# Text, nicht als Aufruf -- sie würden jede _G-Regel verfälschen.
SKIP_PARTS = (os.path.join("ReplicatedStorage", "Specs"),)


def source_files():
    for root, _dirs, files in os.walk(SRC):
        if any(part in root for part in SKIP_PARTS):
            continue
        for name in sorted(files):
            if name.endswith(".luau"):
                yield os.path.join(root, name).replace("\\", "/")


# Lange Klammern: Blockkommentare --[[ ]] und lange Zeichenketten [[ ]], auch mit
# Gleichheitszeichen ([==[ ]==]). BEIDES muss weg, bevor irgendeine Regel greift.
#
# Ohne das meldete die Vorwaerts-Referenz-Regel 72 Fundstellen, von denen die Mehrzahl in
# den Installer-Skripten lag: die schreiben ERZEUGTEN Quelltext in lange Zeichenketten,
# und darin steht naturgemaess alles Moegliche. Ein Rueckstand, der zu drei Vierteln aus
# Fehlalarmen besteht, wird nicht gelesen -- und dann faellt der echte Fund darin nicht auf.
LONG_BRACKET = re.compile(r"(?:--)?\[(=*)\[.*?\]\1\]", re.S)

# Zeichenketten in Anfuehrungszeichen. Ein Name, der nur als Text vorkommt, ist keine
# Benutzung -- "GuardianState" in einem SetAttribute-Aufruf etwa.
QUOTED = re.compile(r'"(?:[^"\\]|\\.)*"' + r"|'(?:[^'\\]|\\.)*'")


def sanitize(text, drop_strings):
    """Entfernt Kommentare, behaelt aber die Zeilenstruktur -- die Zeilennummern in den
    Meldungen muessen stimmen, sonst sucht man an der falschen Stelle.

    `drop_strings` unterscheidet zwei Lesarten, und die braucht es wirklich:

      True  -- fuer Regeln ueber BEZEICHNER (Vorwaerts-Referenz, _G-Paare). Ein Name, der
               nur als Text vorkommt, ist keine Benutzung.
      False -- fuer Regeln ueber AUFRUFMUSTER mit Zeichenkette als Argument
               (GetOrCreate("X"), WaitForChild("X")). Dort IST die Zeichenkette der Fund.

    Mit nur einer Lesart ging es schief: mit entfernten Zeichenketten meldeten die beiden
    Aufrufregeln null Fundstellen statt 58 und 191.
    """

    def blank(match):
        # Durch Leerzeilen ersetzen, damit die Nummerierung erhalten bleibt.
        return "\n" * match.group(0).count("\n")

    text = LONG_BRACKET.sub(blank, text)

    lines = []
    for line in text.split("\n"):
        if drop_strings:
            line = QUOTED.sub('""', line)
        if "--" in line:
            line = line.split("--", 1)[0]
        lines.append(line)
    return lines


def strip_comment(line):
    """Die Zeilen aus read_lines sind bereits bereinigt; die Funktion bleibt als
    Bezeichnung der Absicht an den Aufrufstellen stehen."""
    return line


_CACHE = {}


def _lines(path, drop_strings):
    key = (path, drop_strings)
    if key not in _CACHE:
        with io.open(path, encoding="utf-8", errors="replace") as handle:
            _CACHE[key] = sanitize(handle.read(), drop_strings)
    for number, line in enumerate(_CACHE[key], 1):
        yield number, line


def read_lines(path):
    """Ohne Zeichenketten -- fuer Regeln ueber Bezeichner."""
    return _lines(path, True)


def read_lines_with_strings(path):
    """Mit Zeichenketten -- fuer Regeln ueber Aufrufmuster."""
    return _lines(path, False)


# ===== Regeln =====================================================================
# Jede Regel: id, intent (die Absicht, nicht die Mechanik), check() -> Liste von Texten.


def rule_g_read_without_write(files):
    """_G.X wird gelesen, aber nirgends gesetzt."""
    writes, reads = set(), collections.defaultdict(list)
    for path in files:
        for number, raw in read_lines(path):
            line = strip_comment(raw)
            for match in re.finditer(r"_G\.(\w+)\s*=(?!=)", line):
                writes.add(match.group(1))
            for match in re.finditer(r"_G\.(\w+)", line):
                if not re.search(r"_G\.%s\s*=(?!=)" % match.group(1), line):
                    reads[match.group(1)].append((path, number))

    violations = []
    for name in sorted(set(reads) - writes):
        where = reads[name][0]
        violations.append("_G.%s: %d Lesestelle(n), keine Schreibstelle -- z.B. %s:%d"
                          % (name, len(reads[name]), where[0], where[1]))
    return violations


def rule_g_write_without_read(files):
    """_G.X wird gesetzt, aber nirgends aufgerufen."""
    writes, reads = {}, set()
    for path in files:
        for number, raw in read_lines(path):
            line = strip_comment(raw)
            for match in re.finditer(r"_G\.(\w+)\s*=(?!=)", line):
                writes.setdefault(match.group(1), (path, number))
            for match in re.finditer(r"_G\.(\w+)", line):
                if not re.search(r"_G\.%s\s*=(?!=)" % match.group(1), line):
                    reads.add(match.group(1))

    violations = []
    for name in sorted(set(writes) - reads):
        path, number = writes[name]
        violations.append("_G.%s: gesetzt in %s:%d, aber nirgends aufgerufen"
                          % (name, path, number))
    return violations


def rule_forward_reference(files):
    """Ein Name wird benutzt, bevor sein `local` deklariert ist.

    Die häufigste echte Fehlerquelle dieses Projekts. Lua löst so einen Namen still auf
    ein nicht existierendes Global auf -- der Wert ist nil, es gibt keine Fehlermeldung,
    und der betroffene Zweig tut einfach nichts. In einer einzigen Sitzung ist das fünfmal
    passiert (Players, requireWorkshopModule, ein Visible-Handler, PUSH_OUT_DISTANCE).

    Geprüft werden nur Deklarationen auf oberster Ebene -- eingerückte Namen gehören zu
    einem Gültigkeitsbereich, den diese einfache Betrachtung nicht nachbilden kann.
    """
    violations = []
    for path in files:
        lines = list(read_lines(path))
        declared = {}
        shadowed = set()
        for number, raw in lines:
            match = re.match(r"(\s*)local (?:function )?(\w+)", raw)
            if not match:
                continue
            indent, name = match.group(1), match.group(2)
            if indent:
                # Derselbe Name auch als eingerueckte lokale Variable: dann ist nicht mehr
                # zu entscheiden, welche Deklaration eine Fundstelle meint. Solche Namen
                # bleiben aussen vor -- lieber ein uebersehener Fund als vier Fehlalarme,
                # denn ein Rueckstand voller Fehlalarme wird nicht gelesen.
                shadowed.add(name)
            elif name not in declared:
                declared[name] = number

        for name in shadowed:
            declared.pop(name, None)

        for number, raw in lines:
            line = strip_comment(raw)
            # Bei einer Deklaration nur die RECHTE Seite betrachten. Die ganze Zeile zu
            # ueberspringen war zu grob: `local x = spaeterDeklarierterName` ist selbst
            # eine Vorwaerts-Referenz und blieb dadurch unsichtbar.
            declaration = re.match(r"\s*local (?:function )?\w+\s*(?:\(|=)?", line)
            if declaration:
                line = line[declaration.end():]
            for name, declaration_line in declared.items():
                if number >= declaration_line:
                    continue
                if re.search(r"\b%s\b" % re.escape(name), line):
                    violations.append(
                        "%s:%d benutzt %s, deklariert erst in Zeile %d -- löst still auf nil auf"
                        % (path, number, name, declaration_line))
    return violations


# Namen, die es immer gibt: Roblox-Umgebung, Luau-Standardbibliothek, Schluesselwoerter.
KNOWN_GLOBALS = set("""game workspace Workspace script shared _G plugin
Instance Enum Vector2 Vector3 Vector3int16 CFrame Color3 BrickColor UDim UDim2 Rect
NumberRange NumberSequence NumberSequenceKeypoint ColorSequence ColorSequenceKeypoint
TweenInfo Ray Region3 Random Faces Axes PhysicalProperties DateTime Font OverlapParams
RaycastParams CatalogSearchParams PathWaypoint
math string table task os coroutine utf8 bit32 buffer debug
print warn error assert pcall xpcall select type typeof tostring tonumber
ipairs pairs next unpack require setmetatable getmetatable rawget rawset rawequal rawlen
tick time wait spawn delay elapsedTime newproxy gcinfo collectgarbage
self true false nil and or not if then else elseif end for while do repeat until return
local function in break continue""".split())

# Deklarationen. Ueber den GANZEN Dateitext gesucht, nicht zeilenweise: Parameterlisten
# stehen im Bestand mehrfach ueber mehrere Zeilen, und zeilenweise gelesen galten ihre
# Parameter faelschlich als undeklariert -- fuenf Fehlalarme bei der ersten Fassung.
DECLARATIONS = [
    re.compile(r"\blocal\s+([\w\s,]+?)\s*(?:=|$)", re.M),
    re.compile(r"\blocal\s+function\s+(\w+)"),
    re.compile(r"\bfunction\s+[\w.:]*?(\w+)\s*\("),
    re.compile(r"\bfor\s+([\w\s,]+?)\s*(?:=|\bin\b)"),
]
PARAMETERS = re.compile(r"\bfunction\s*[\w.:]*\s*\(([^)]*)\)", re.S)

# Geprueft wird ein Name nur, wenn er als Tabelle, Objekt oder Aufruf auftritt -- also
# X.feld, X:methode() oder X(). Damit fallen Tabellen-SCHLUESSEL von vornherein raus
# ("asset = ..." in einem Konstruktor ist keine Benutzung), und genau die waeren sonst
# die groesste Fehlalarmquelle.
NAME_USE = re.compile(r"(?<![\w.:])(\w+)\s*[.:(]")


def rule_undefined_name(files):
    """Ein Name wird benutzt, den es in dieser Datei gar nicht gibt.

    Lua loest ihn still auf ein GLOBAL auf -- Wert nil. Bei einem Feldzugriff gibt es
    dann "attempt to index nil with '...'", bei einem Aufruf "attempt to call a nil
    value", und beides erst DANN, wenn die Zeile tatsaechlich laeuft.

    Genau so ist es passiert: in TalentTreeClient stand `talentTreePanel.Visible`, obwohl
    die Variable `panel` heisst. Die Zeile laeuft nur, wenn eine Forschung fertig wird --
    der Fehler lag lange im Code, bevor ihn jemand ausgeloest hat.

    Die Vorwaerts-Referenz-Regel findet das NICHT: sie prueft Namen, die zu frueh benutzt
    werden, nicht solche, die es nirgends gibt.
    """
    violations = []
    for path in files:
        text = "\n".join(line for _n, line in read_lines(path))

        declared = set()
        for pattern in DECLARATIONS:
            for hit in pattern.findall(text):
                for name in re.split(r"[,\s]+", hit.strip()):
                    if name:
                        declared.add(name)
        for params in PARAMETERS.findall(text):
            for name in re.split(r"[,\s]+", params.strip()):
                if name:
                    declared.add(name.replace("...", ""))

        previous = ""
        for number, line in read_lines(path):
            # Ein Methodenaufruf, dessen Doppelpunkt am Zeilenende steht und dessen Name
            # die naechste Zeile beginnt ("section:" / "FindFirstChildWhichIsA("), sieht
            # zeilenweise wie ein freier Name aus. Kommt in den erzeugten
            # Installer-Skripten vor -- beide verbliebenen Fehlalarme waren von dieser Art.
            continues_call = previous.rstrip().endswith((":", "."))
            if line.strip():
                previous = line
            if continues_call:
                continue

            for name in NAME_USE.findall(line):
                if name in declared or name in KNOWN_GLOBALS or name.isdigit():
                    continue
                violations.append(
                    "%s:%d %s ist nirgends deklariert -- loest still auf nil auf"
                    % (path, number, name))
    return violations


def rule_waitforchild_timeout(files):
    """WaitForChild ohne zweites Argument wartet unbegrenzt.

    Existiert das Objekt nie, hängt das Skript stumm -- kein Fehler, kein Hinweis. Steht
    so in CLAUDE.md unter "Bekannte Fallstricke".

    ===== Nicht jedes WaitForChild kann hängen =====
    Von 191 Fundstellen des ersten Laufs betrafen ueber siebzig ModuleScripts aus
    ReplicatedStorage -- RemoteEventUtils, ComicStyleUtils, die Config-Module. Die liefert
    Rojo mit dem Place aus, sie existieren ab dem ersten Bild und werden von keinem Skript
    zur Laufzeit erzeugt. Dort eine Zeitgrenze zu setzen waere nicht nur Zierrat, sondern
    schaedlich: fehlt das Modul wirklich, verwandelt die Zeitgrenze ein klares Haengen in
    einen spaeteren Absturz an unklarer Stelle.

    Erkannt werden sie an den DATEIEN, nicht an einer gepflegten Liste: wer im Repo unter
    src/ReplicatedStorage liegt, ist beim Start da. Wird ein Modul geloescht, meldet sich
    die Regel von selbst wieder.

    Uebrig bleibt, was ein anderes Skript zur Laufzeit erzeugt -- leaderstats und seine
    Kinder, die Spieler-Ordner -- und genau das kann tatsaechlich stumm haengen.
    """
    # Namen aller Skripte und Module, die Rojo aus dem Repo mitliefert -- gleich in
    # welchem Dienst. Auch ein Modul unter ServerScriptService ist beim Start da.
    shipped = set()
    for path in files:
        shipped.add(os.path.basename(path).split(".")[0])

    violations = []
    for path in files:
        for number, raw in read_lines_with_strings(path):
            line = strip_comment(raw)
            for match in re.finditer(r"WaitForChild\(\s*(\"[\w\s]+\"|\w+)\s*\)", line):
                argument = match.group(1)
                name = argument.strip('"')
                if name in shipped:
                    continue
                # PlayerGui liefert die Engine mit dem Spieler-Objekt; das ist die
                # kanonische Schreibweise in jedem Roblox-Client und kann nicht haengen.
                if name == "PlayerGui":
                    continue
                violations.append("%s:%d WaitForChild(%s) ohne Zeitgrenze"
                                  % (path, number, argument))
    return violations


def rule_remote_without_creator(files):
    """Ein RemoteEvent wird im Repo gesucht, aber von keinem Repo-Skript angelegt.

    Dann existiert es nur, weil es in Studio von Hand angelegt wurde oder von einem
    Skript stammt, das im Modell liegt und nicht versioniert ist. Das ist nicht
    grundsaetzlich falsch -- aber es ist eine unsichtbare Abhaengigkeit: geht das Objekt
    im Place verloren, faellt es nur im Spiel auf, und der Quelltext gibt keinen Hinweis
    darauf, wo es herkommen soll.

    CLAUDE.md haelt dazu fest: RemoteEvents werden zur Laufzeit ueber GetOrCreate
    angelegt, die .model.json-Dateien sind die versionierten Gegenstuecke. Diese Regel
    prueft genau das.

    Wer so eine Abhaengigkeit bewusst eingeht, holt das Objekt mit Zeitgrenze und prueft
    auf nil -- so macht es SanctuaryLiftRider mit LiftReleasePlayerEvent.
    """
    created = set()
    referenced = collections.defaultdict(list)

    for path in files:
        for number, raw in read_lines_with_strings(path):
            line = strip_comment(raw)
            # Angelegt: per Hilfsfunktion oder durch Benennen einer neuen Instanz.
            for match in re.finditer(
                r'(?:RemoteEventUtils\.GetOrCreate|getOrCreateRemoteEvent)\(\s*"(\w+)"', line):
                created.add(match.group(1))
            for match in re.finditer(r'\.Name\s*=\s*"(\w+)"', line):
                created.add(match.group(1))
            # Gesucht: nur Namen, die nach einem Remote aussehen -- sonst faenge die Regel
            # jeden Ordner und jedes Wertobjekt mit ein.
            for match in re.finditer(
                r'(?:WaitForChild|FindFirstChild)\(\s*"(\w+(?:Event|Function|Remote))"', line):
                referenced[match.group(1)].append((path, number))

    # Versionierte Gegenstuecke zaehlen als angelegt: sie liegen im Repo und kommen mit
    # dem Place mit.
    for root, _dirs, names in os.walk(SRC):
        for name in names:
            if name.endswith(".model.json"):
                created.add(name.split(".")[0])

    violations = []
    for name in sorted(set(referenced) - created):
        path, number = referenced[name][0]
        violations.append(
            "%s: gesucht in %s:%d, aber von keinem Repo-Skript angelegt und ohne "
            ".model.json -- existiert nur in Studio" % (name, path, number))
    return violations


RULES = [
    {
        "id": "source.remote-without-creator",
        "intent": "Jedes RemoteEvent, auf das der Quelltext sich verlaesst, wird auch im "
                  "Repo angelegt -- per GetOrCreate oder als .model.json. Sonst haengt "
                  "der Code an einem Objekt, das nur im Place existiert: geht es verloren, "
                  "faellt das erst im Spiel auf, und der Quelltext sagt nicht, woher es "
                  "kommen sollte.",
        "check": rule_remote_without_creator,
    },
    {
        "id": "source.g-read-without-write",
        "intent": "Jede _G-Funktion, die gelesen wird, ist auch irgendwo gesetzt. "
                  "Lesestellen sind durchweg nil-geprueft -- eine fehlende Schreibstelle "
                  "faellt deshalb nie als Fehler auf, sondern nur als Wirkung, die ausbleibt.",
        "check": rule_g_read_without_write,
    },
    {
        "id": "source.g-write-without-read",
        "intent": "Jede _G-Funktion, die gesetzt wird, wird auch aufgerufen. Eine, die "
                  "niemand ruft, ist entweder unfertig angeschlossen oder Altbestand -- "
                  "beides sieht im Code aus wie ein fertiges System.",
        "check": rule_g_write_without_read,
    },
    {
        "id": "source.undefined-name",
        "intent": "Jeder benutzte Name ist in seiner Datei auch deklariert. Ein Name, den "
                  "es nicht gibt, loest in Lua still auf ein Global auf und ist nil -- der "
                  "Fehler faellt erst auf, wenn die betroffene Zeile zufaellig laeuft.",
        "check": rule_undefined_name,
    },
    {
        "id": "source.forward-reference",
        "intent": "Kein Name wird benutzt, bevor sein local deklariert ist. Lua loest so "
                  "einen Namen still auf ein nicht existierendes Global auf: der Wert ist "
                  "nil, es gibt keine Fehlermeldung, der Zweig tut nichts.",
        "check": rule_forward_reference,
    },
    {
        "id": "source.waitforchild-timeout",
        "intent": "WaitForChild bekommt eine Zeitgrenze und der Fehlerfall wird behandelt. "
                  "Ohne zweites Argument haengt das Skript stumm, wenn das Objekt nie kommt.",
        "check": rule_waitforchild_timeout,
    },
]


# ===== Rückstand ==================================================================


# Zeilennummern beim VERGLEICHEN ausblenden, beim ANZEIGEN behalten.
#
# Ohne das galt jede bekannte Abweichung als neu, sobald irgendwo darueber Zeilen
# eingefuegt wurden -- neun eingefuegte Zeilen liessen zwei unveraenderte Fundstellen
# als Regression erscheinen. Eine Rueckstandsliste, die nach jeder Aenderung Fehlalarme
# wirft, wird abgeschaltet.
LINE_NUMBER = re.compile(r":\d+")


def normalize(text):
    return LINE_NUMBER.sub(":<n>", text)


def load_known():
    """Rueckgabe: {regel-id: Counter(normalisierter Text -> Anzahl)}.

    Gezaehlt wird, nicht nur nachgeschlagen: sonst wuerde eine ZWEITE Fundstelle
    derselben Art in derselben Datei durchrutschen, weil die erste schon bekannt ist.
    Der Rueckstand darf nicht wachsen -- nur umziehen.
    """
    known = collections.defaultdict(collections.Counter)
    if not os.path.exists(KNOWN_FILE):
        return known
    with io.open(KNOWN_FILE, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if "|" not in line:
                continue
            rule_id, text = line.split("|", 1)
            known[rule_id.strip()][normalize(text.strip())] += 1
    return known


def save_known(results):
    header = [
        "# Bekannter Rueckstand des Quelltext-Pruefers.",
        "#",
        "# Diese Abweichungen laufen bewusst durch -- nur ein NEUER Verstoss haelt den",
        "# Stop-Hook an. Die Liste ist zugleich die Aufgabenliste: wer eine Zeile hier",
        "# erledigt, loescht sie.",
        "#",
        "# Neu erzeugen mit: python tools/source-check.py --accept",
        "# Format: <regel-id>|<verstosstext>",
        "",
    ]
    lines = []
    for rule_id, violations in results:
        for text in violations:
            lines.append("%s|%s" % (rule_id, text))
    with io.open(KNOWN_FILE, "w", encoding="utf-8") as handle:
        handle.write("\n".join(header + sorted(lines)) + "\n")
    return len(lines)


def main():
    accept = "--accept" in sys.argv
    verbose = "--list" in sys.argv

    files = list(source_files())
    known = load_known()

    results = []
    new_violations = []
    known_count = 0

    for rule in RULES:
        violations = rule["check"](files)
        results.append((rule["id"], violations))

        # Je Regel abzaehlen: so viele Fundstellen einer Art, wie im Rueckstand stehen,
        # gelten als bekannt -- jede weitere ist neu, auch wenn sie gleich aussieht.
        budget = collections.Counter(known.get(rule["id"], {}))
        for text in violations:
            key = normalize(text)
            if budget[key] > 0:
                budget[key] -= 1
                known_count += 1
            else:
                new_violations.append((rule["id"], text))

    if accept:
        total = save_known(results)
        print("[Kaiju Quelle] %d Abweichungen als Rueckstand erfasst (%s)." % (total, KNOWN_FILE))
        return 0

    for rule_id, text in new_violations:
        print("[Kaiju Quelle] NEU  %s: %s" % (rule_id, text))

    if verbose:
        for rule_id, violations in results:
            print("[Kaiju Quelle] %-32s %d Fundstelle(n)" % (rule_id, len(violations)))

    print("[Kaiju Quelle] %d Regeln geprueft, %d neue Verstoesse, %d bekannte Abweichungen, %d Dateien."
          % (len(RULES), len(new_violations), known_count, len(files)))

    if new_violations:
        print("[Kaiju Quelle] ABBRUCH: bitte beheben -- oder bewusst erfassen mit "
              "'python tools/source-check.py --accept'.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
