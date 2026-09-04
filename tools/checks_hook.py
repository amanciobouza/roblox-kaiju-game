"""Stop-Hook-Wrapper um die kopflosen Pruefer.

Wird von .claude/settings.json als Stop-Hook aufgerufen: laeuft einmal, wenn Claude einen
Zug beendet -- nach der Arbeit, bevor Amancio das Ergebnis liest.

Frueher hiess diese Datei spec_check_hook.py und rief nur den Spec-Pruefer. Seit es zwei
Pruefer gibt, waere der Name falsch:

  * tools/spec-check.luau   -- Absichten gegen Konfigurationen (laeuft unter luau)
  * tools/source-check.py   -- Quelltextmuster, die der Spec-Pruefer nicht sehen KANN,
                               weil Luau kein io-Modul hat

Verhalten (siehe Entscheidung Q15 des Spec-Entwurfs):
  * Alle Pruefer mit Exit-Code 0 -> nichts ausgeben, Zug laeuft durch.
  * Sonst -> {"decision": "block", "reason": ...} auf stdout. Damit bekommt Claude die
    Verstoesse zurueck und muss sie beheben, bevor uebergeben wird.

Beide Pruefer brechen NUR bei NEUEN Verstoessen ab -- der erfasste Rueckstand laeuft
bewusst durch. Rueckstand darf passieren, Regression nicht.

Dieses Skript beendet sich immer mit 0: die Rueckmeldung laeuft ueber das JSON, nicht ueber
den Exit-Code. Ein Nicht-Null-Exit hier waere ein HOOK-Fehler, kein Pruefbefund.

Kein jq im Projekt, deshalb Python -- das uebernimmt zugleich das JSON-Escaping der Ausgabe.
"""

import json
import os
import subprocess
import sys

# Projektstamm aus dem eigenen Ort ableiten, nicht aus dem Arbeitsverzeichnis: der Hook
# koennte anderswo starten, und rokit findet luau nur ueber rokit.toml im Projektstamm.
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Obergrenze, damit eine ausufernde Verstossliste nicht den halben Kontext frisst.
MAX_REASON_CHARS = 8000

# (Anzeigename, Befehl, Hinweis fuer den Fall NEUER Verstoesse)
CHECKERS = [
    (
        "Spec",
        ["luau", "tools/spec-check.luau"],
        "Vor der Uebergabe beheben -- oder, falls es sich um eine bewusst hingenommene "
        "Altlast handelt, in der betroffenen Regel unter knownViolations erfassen.",
    ),
    (
        "Quelle",
        [sys.executable, "tools/source-check.py"],
        "Vor der Uebergabe beheben -- oder, falls bewusst hingenommen, erfassen mit "
        "'python tools/source-check.py --accept'.",
    ),
]


def run(command):
    """Fuehrt einen Pruefer aus. Rueckgabe: (exit_code, ausgabe) oder (None, meldung),
    wenn der Pruefer selbst nicht laufen konnte -- das ist ein Einrichtungsfehler und
    darf den Zug NICHT blockieren, sonst haengt jede Uebergabe."""
    try:
        completed = subprocess.run(
            command,
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        )
    except FileNotFoundError:
        return None, "%s nicht gefunden -- Pruefung uebersprungen. Fehlt 'rokit install'?" % command[0]
    except subprocess.TimeoutExpired:
        return None, "Pruefer nach 60s abgebrochen -- uebersprungen."

    return completed.returncode, ((completed.stdout or "") + (completed.stderr or "")).strip()


def main() -> int:
    problems = []
    notes = []

    # Den Fingerabdruck vor den Pruefungen nachziehen: er muss den Stand nach DIESEM Zug
    # beschreiben, nicht den davor. Schlaegt es fehl, ist das kein Grund zu blockieren --
    # der Stempel ist ein Hilfsmittel, kein Pruefkriterium.
    stamp_code, stamp_output = run([sys.executable, "tools/build_stamp.py"])
    if stamp_code not in (0, None) and stamp_output:
        notes.append("[Kaiju Stempel] konnte nicht erzeugt werden: " + stamp_output)

    for name, command, advice in CHECKERS:
        code, output = run(command)
        if code is None:
            notes.append("[Kaiju %s] %s" % (name, output))
        elif code != 0:
            problems.append("[Kaiju %s] %s\n\n%s" % (name, advice, output))

    if not problems:
        if notes:
            json.dump({"systemMessage": "\n".join(notes)}, sys.stdout)
        # Sauber. Bewusst KEINE weitere Ausgabe -- der Hook soll im Normalfall unsichtbar sein.
        return 0

    reason = "\n\n".join(problems + notes)
    if len(reason) > MAX_REASON_CHARS:
        reason = reason[:MAX_REASON_CHARS] + "\n... (gekuerzt)"

    json.dump({"decision": "block", "reason": reason}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
