-- VERSION: 2026-08-26 #10
-- FEATURE: FadeMusicToNormalVolume + ResumeNormalMusic mit optionaler Start-Lautstaerke
-- Ort in Studio: ServerScriptService
--
-- Generisches, datengetriebenes System für Erzähl-Sequenzen (Schwarzblenden, Text,
-- Kapitel-Titelkarten, Sounds) -- wiederverwendbar für: Prolog (Cold Open, "The Trench
-- Remembers"), Kapitel-I/II/III-Übergänge, und das Spielende. Siehe StoryBeatClient.lua
-- für die eigentliche Darstellung.
--
-- Verwendung (blockiert den aufrufenden Code, bis die Sequenz beim Client fertig
-- abgespielt wurde -- macht das Skripten mehrteiliger Cutscenes sehr natürlich, einfach
-- nacheinander aufrufen):
--
--   local StoryBeatService = require(ServerScriptService.StoryBeatService)
--   StoryBeatService.Play(player, {
--       steps = {
--           { type = "fadeIn", duration = 1 },
--           { type = "sound", soundId = "rbxassetid://...", volume = 0.6, looped = true },
--           { type = "wait", duration = 1.5 },
--           { type = "text", text = "THE CITY IS ALREADY LOST.", duration = 3 },
--           { type = "fadeOut", duration = 1 },
--       },
--   })
--
-- Unterstützte Schritt-Typen (siehe StoryBeatClient.lua für die genaue Umsetzung):
--   fadeIn / fadeOut  -- Schwarzblende ein-/ausblenden, { duration }
--   wait              -- reine Pause, { duration }
--   text              -- Textzeile mittig einblenden, { text, duration, fadeIn, fadeOut }
--   chapterCard       -- grosse Kapitel-Karte, { number, title, subtitle, duration, fadeIn, fadeOut }
--   sound             -- Sound abspielen, { soundId, volume, looped, wait } -- "wait=true"
--                         lässt die Sequenz auf das Sound-Ende warten, sonst läuft er im
--                         Hintergrund weiter (z.B. für ein durchgehendes Ticken)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEventUtils = require(ReplicatedStorage:WaitForChild("RemoteEventUtils"))

local PlayStoryBeatEvent = RemoteEventUtils.GetOrCreate("PlayStoryBeatEvent")
local StoryBeatCompleteEvent = RemoteEventUtils.GetOrCreate("StoryBeatCompleteEvent")
local PlayBackgroundMusicEvent = RemoteEventUtils.GetOrCreate("PlayBackgroundMusicEvent")
local StopBackgroundMusicEvent = RemoteEventUtils.GetOrCreate("StopBackgroundMusicEvent")
local PlaySirenSoundEvent = RemoteEventUtils.GetOrCreate("PlaySirenSoundEvent")
local StopSirenSoundEvent = RemoteEventUtils.GetOrCreate("StopSirenSoundEvent")
local SetSirenVolumeEvent = RemoteEventUtils.GetOrCreate("SetSirenVolumeEvent")
local FadeOutAllSoundEvent = RemoteEventUtils.GetOrCreate("FadeOutAllSoundEvent")
local ResumeNormalMusicEvent = RemoteEventUtils.GetOrCreate("ResumeNormalMusicEvent")
local FadeMusicToNormalVolumeEvent = RemoteEventUtils.GetOrCreate("FadeMusicToNormalVolumeEvent")
local PauseNormalMusicEvent = RemoteEventUtils.GetOrCreate("PauseNormalMusicEvent")

local StoryBeatService = {}

-- Sicherheitsnetz, falls der Client aus irgendeinem Grund nie antwortet (z.B. Verbindung
-- verloren) -- verhindert, dass der aufrufende Server-Code für immer hängen bleibt.
local COMPLETION_TIMEOUT_SECONDS = 120

-- Spielt eine Sequenz beim angegebenen Spieler ab und WARTET, bis sie fertig ist (oder
-- der Spieler das Spiel verlässt / der Timeout abläuft). Dadurch lassen sich mehrteilige
-- Cutscenes einfach als Abfolge mehrerer Play()-Aufrufe skripten.
function StoryBeatService.Play(player, sequence)
	if not player or not player.Parent then
		return
	end

	local completed = false
	local connection
	connection = StoryBeatCompleteEvent.OnServerEvent:Connect(function(completedPlayer)
		if completedPlayer == player then
			completed = true
			print("[Kaiju-Debug] StoryBeatService.Play: StoryBeatCompleteEvent empfangen für " .. player.Name .. " -- tick=" .. tostring(os.clock()))
		end
	end)

	print("[Kaiju-Debug] StoryBeatService.Play: feuere PlayStoryBeatEvent für " .. player.Name .. " mit " .. #(sequence.steps or {}) .. " Schritten -- tick=" .. tostring(os.clock()) .. " keepBlackScreen=" .. tostring(sequence.keepBlackScreen))
	PlayStoryBeatEvent:FireClient(player, sequence)

	local elapsed = 0
	while not completed and player.Parent and elapsed < COMPLETION_TIMEOUT_SECONDS do
		elapsed += task.wait()
	end
	print("[Kaiju-Debug] StoryBeatService.Play: Schleife beendet nach " .. elapsed .. "s -- completed=" .. tostring(completed) .. " -- tick=" .. tostring(os.clock()))

	connection:Disconnect()

	if elapsed >= COMPLETION_TIMEOUT_SECONDS and player.Parent then
		warn("[StoryBeatService] Timeout beim Warten auf Sequenz-Ende für " .. player.Name .. " -- Client hat nie geantwortet.")
	end
end

-- Nicht-blockierende Variante -- feuert die Sequenz ab, wartet aber NICHT auf das Ende.
-- Praktisch für Sequenzen, die parallel zu anderer Server-Logik laufen sollen (z.B.
-- Hintergrundmusik-Wechsel während gleichzeitig schon Gameplay weiterläuft).
function StoryBeatService.PlayAsync(player, sequence)
	if not player or not player.Parent then
		return
	end
	PlayStoryBeatEvent:FireClient(player, sequence)
end

-- Startet eine langlebige Hintergrundmusik, die -- anders als der "sound"-Schritt
-- innerhalb einer normalen Sequenz -- NICHT automatisch stoppt, wenn eine Play()/
-- PlayAsync()-Sequenz endet. Läuft weiter, bis StopMusic() explizit aufgerufen wird.
function StoryBeatService.PlayMusic(player, musicId, volume)
	if not player or not player.Parent then
		return
	end
	PlayBackgroundMusicEvent:FireClient(player, musicId, volume)
end

function StoryBeatService.StopMusic(player)
	if not player or not player.Parent then
		return
	end
	StopBackgroundMusicEvent:FireClient(player)
end

-- Eigenständiger Sirenen-Sound-Kanal -- getrennt vom Musik-Kanal (oben, wird bereits für
-- die Prolog-Musik genutzt) UND vom sequenz-gebundenen "sound"-Schritt (der bei jedem
-- Play()-Sequenz-Ende automatisch alle Sounds stoppt). Ohne diese Trennung würde die
-- Sirene beim Übergang zwischen zwei Play()-Aufrufen entweder abrupt abbrechen oder
-- (bei erneutem Start in der zweiten Sequenz) hörbar doppelt starten.
function StoryBeatService.PlaySiren(player, soundId, volume)
	if not player or not player.Parent then
		return
	end
	PlaySirenSoundEvent:FireClient(player, soundId, volume)
end

-- Ändert NUR die Lautstärke des bereits laufenden Sirenen-Sounds, ohne ihn neu zu
-- starten -- für ein langsames Anschwellen (Crescendo) während z.B. einer heranrollenden
-- Bedrohung, statt einer konstanten Lautstärke.
function StoryBeatService.SetSirenVolume(player, volume)
	if not player or not player.Parent then
		return
	end
	SetSirenVolumeEvent:FireClient(player, volume)
end

function StoryBeatService.StopSiren(player)
	if not player or not player.Parent then
		return
	end
	StopSirenSoundEvent:FireClient(player)
end

-- Blendet ALLE aktuell laufenden Sounds (Prolog-Musik, Sirene, normale Hintergrundmusik
-- falls sie noch läuft) gemeinsam langsam bis zur Stille aus -- für dramatische Momente
-- wie den Tod im Prolog, bei denen jegliches Geräusch verstummen soll.
function StoryBeatService.FadeOutAllSound(player, duration)
	if not player or not player.Parent then
		return
	end
	FadeOutAllSoundEvent:FireClient(player, duration)
end

-- Weckt die NORMALE Hintergrundmusik (BackgroundMusicClient.lua) wieder auf -- bewusst
-- getrennt von StopMusic() oben: nach dem Guardian-Stopp soll bewusst Stille (+ Ticken)
-- herrschen, nicht die alte Musik zurückkehren. Erst am ECHTEN Ende des Prologs (Phase 7,
-- Awakening) soll die normale Musik wieder einsetzen.
function StoryBeatService.ResumeNormalMusic(player, startVolume)
	if not player or not player.Parent then
		return
	end
	ResumeNormalMusicEvent:FireClient(player, startVolume)
end

-- Fährt die Hintergrundmusik-Lautstärke sanft auf die normale Gameplay-Lautstärke
-- herunter -- für dramatische Momente, die LAUT beginnen (siehe ResumeNormalMusic mit
-- startVolume), aber später zur normalen Lautstärke zurückkehren sollen, sobald der
-- Spieler die Kontrolle übernimmt.
function StoryBeatService.FadeMusicToNormalVolume(player, duration)
	if not player or not player.Parent then
		return
	end
	FadeMusicToNormalVolumeEvent:FireClient(player, duration)
end

-- Pausiert die NORMALE Hintergrundmusik (BackgroundMusicClient.lua), OHNE gleichzeitig
-- die Prolog-Musik zu starten -- praktisch für den Beginn des Prologs (Cold Open), wo
-- noch keine Musik läuft, aber die normale Musik trotzdem schon weg sein soll.
function StoryBeatService.PauseNormalMusic(player)
	if not player or not player.Parent then
		return
	end
	PauseNormalMusicEvent:FireClient(player)
end

return StoryBeatService