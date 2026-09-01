"""Stop-Hook-Wrapper um den kopflosen Spec-Pruefer.

Wird von .claude/settings.json als Stop-Hook aufgerufen: laeuft einmal, wenn Claude einen
Zug beendet -- nach der Arbeit, bevor Amancio das Ergebnis liest.

Verhalten (siehe Entscheidung Q15 des Spec-Entwurfs):
  * Exit-Code 0 des Pruefers  -> nichts ausgeben, Zug laeuft durch.
  * Exit-Code != 0            -> {"decision": "block", "reason": ...} auf stdout.
    Damit bekommt Claude die Verstoesse zurueck und muss sie beheben, bevor uebergeben wird.

Der Pruefer selbst bricht NUR bei NEUEN Verstoessen ab -- die erfassten bekannten
Abweichungen laufen bewusst durch. Rueckstand darf passieren, Regression nicht.

Dieses Skript beendet sich immer mit 0: die Rueckmeldung laeuft ueber das JSON, nicht ueber
den Exit-Code. Ein Nicht-Null-Exit hier waere ein HOOK-Fehler, kein Spec-Befund.

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


def main() -> int:
    try:
        completed = subprocess.run(
            ["luau", "tools/spec-check.luau"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        )
    except FileNotFoundError:
        # luau fehlt im Werkzeugkasten -- das ist ein Einrichtungsfehler, kein Spec-Befund.
        # Als systemMessage melden statt zu blockieren: sonst haengt jeder Zug.
        json.dump(
            {
                "systemMessage": (
                    "[Kaiju Spec] luau nicht gefunden -- Spec-Pruefung uebersprungen. "
                    "Fehlt 'rokit install'?"
                )
            },
            sys.stdout,
        )
        return 0
    except subprocess.TimeoutExpired:
        json.dump(
            {"systemMessage": "[Kaiju Spec] Pruefer nach 60s abgebrochen -- uebersprungen."},
            sys.stdout,
        )
        return 0

    if completed.returncode == 0:
        # Sauber. Bewusst KEINE Ausgabe -- der Hook soll im Normalfall unsichtbar sein.
        return 0

    output = (completed.stdout or "") + (completed.stderr or "")
    output = output.strip()
    if len(output) > MAX_REASON_CHARS:
        output = output[:MAX_REASON_CHARS] + "\n... (gekuerzt)"

    json.dump(
        {
            "decision": "block",
            "reason": (
                "Die Spec-Pruefung meldet NEUE Verstoesse. Vor der Uebergabe beheben -- "
                "oder, falls es sich um eine bewusst hingenommene Altlast handelt, in der "
                "betroffenen Regel unter knownViolations erfassen.\n\n" + output
            ),
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
