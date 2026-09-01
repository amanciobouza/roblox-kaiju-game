-- ModuleScript: PrologueConfig
-- Ort in Studio: ReplicatedStorage
--
-- Version des Playable Prologue ("The Fall"). Liegt hier und nicht im
-- PrologueOrchestrator, weil BEIDE Seiten sie brauchen -- der Prolog beim Abschliessen,
-- PlayerSetup beim Laden -- und Scripts in ServerScriptService in unbestimmter
-- Reihenfolge starten. Ein _G-Wert wäre bei einem ungünstigen Start noch nicht gesetzt.
--
-- ===== Bedeutung der beiden Zahlen =====
--
--   Major  Der Prolog hat sich INHALTLICH geändert: neue Szenen, andere Reihenfolge,
--          verändertes Ende. Wer eine ältere Major-Version gespielt hat, soll ihn
--          KOMPLETT NEU spielen -- sonst kennt er die Geschichte nicht, auf der alles
--          Weitere aufbaut.
--
--   Minor  Korrekturen ohne inhaltliche Folgen: Timing, Kameraführung, Textfehler,
--          Fehlerbehebungen. Wer den Prolog schon gespielt hat, muss NICHT erneut ran.
--          Die Zahl wird trotzdem mitgespeichert -- daran lässt sich später ablesen,
--          welche Fassung jemand tatsächlich gesehen hat.
--
-- Beim Erhöhen von Major auf einem LIVE-Server: jeder bestehende Spieler bekommt beim
-- nächsten Beitritt den Prolog erneut. Das ist die Absicht, aber es trifft alle auf
-- einmal -- also bewusst setzen, nicht nebenbei.

return {
	Major = 1,
	Minor = 0,
}
