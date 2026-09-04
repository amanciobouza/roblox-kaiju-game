# -*- coding: utf-8 -*-
"""Erzeugt src/ReplicatedStorage/BuildStamp.luau -- einen Fingerabdruck des Quelltextes.

    python tools/build_stamp.py

===== Wogegen das hilft =====
Der teuerste Fehler einer ganzen Arbeitssitzung war keiner: Studio lief auf einer ALTEN
Dateifassung, und es wurde zwei Runden lang eine Ursache gesucht, die es nicht gab.
Aufgefallen ist es nur zufaellig, weil Zeilennummern in der Ausgabe nicht zu den Dateien
im Repo passten.

Der Stempel macht das sofort sichtbar: das Repo kennt seinen Wert (diese Datei), und der
Server gibt beim Start seinen aus. Stimmen sie nicht ueberein, hat Rojo nicht synchronisiert.

===== Warum ein Inhalts-Hash und kein Zeitstempel =====
Ein Zeitstempel aenderte sich bei jedem Lauf und wuerde in jedem Commit auftauchen, ohne
etwas zu bedeuten. Der Inhalts-Hash aendert sich GENAU DANN, wenn sich Code geaendert hat
-- also genau dann, wenn eine veraltete Synchronisation ueberhaupt schaden kann.

Die Datei wird nur geschrieben, wenn sich der Wert geaendert hat -- sonst wuerde ihr
Zeitstempel bei jedem Zug wackeln und Rojo unnoetig synchronisieren.
"""

import hashlib
import io
import os
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(PROJECT_ROOT, "src")
STAMP_PATH = os.path.join(SRC, "ReplicatedStorage", "BuildStamp.luau")

TEMPLATE = '''-- ModuleScript: BuildStamp
-- Ort in Studio: ReplicatedStorage
--
-- ERZEUGT -- nicht von Hand bearbeiten. Neu erzeugen mit: python tools/build_stamp.py
--
-- Fingerabdruck ueber alle .luau-Dateien unter src/. Der Server gibt ihn beim Start aus
-- (siehe SpecCheckService). Weicht die Ausgabe in Studio von dem Wert ab, der hier steht,
-- laeuft Studio auf einem alten Stand und Rojo hat nicht synchronisiert.
--
-- Genau dieser Fall hat schon einmal zwei Runden Fehlersuche gekostet, weil eine Aenderung
-- scheinbar wirkungslos blieb -- sie war schlicht nicht im laufenden Spiel.

return {
\tHash = "%s",
\tFileCount = %d,
}
'''


def main():
    digest = hashlib.sha256()
    count = 0

    # Sortiert einlesen, damit derselbe Baum immer denselben Hash ergibt -- os.walk
    # garantiert keine Reihenfolge.
    for root, dirs, files in os.walk(SRC):
        dirs.sort()
        for name in sorted(files):
            if not name.endswith(".luau"):
                continue
            path = os.path.join(root, name)
            if os.path.abspath(path) == os.path.abspath(STAMP_PATH):
                continue  # sich selbst nicht mitzaehlen, sonst waere der Hash zirkulaer
            relative = os.path.relpath(path, PROJECT_ROOT).replace("\\", "/")
            with io.open(path, "rb") as handle:
                content = handle.read()
            # Auch den PFAD mit einrechnen: eine umbenannte Datei mit gleichem Inhalt ist
            # ein anderer Stand.
            digest.update(relative.encode("utf-8"))
            digest.update(content)
            count += 1

    stamp = digest.hexdigest()[:10]
    new_text = TEMPLATE % (stamp, count)

    old_text = None
    if os.path.exists(STAMP_PATH):
        with io.open(STAMP_PATH, encoding="utf-8") as handle:
            old_text = handle.read()

    if old_text == new_text:
        return 0

    with io.open(STAMP_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(new_text)
    print("[Kaiju Stempel] %s (%d Dateien)" % (stamp, count))
    return 0


if __name__ == "__main__":
    sys.exit(main())
