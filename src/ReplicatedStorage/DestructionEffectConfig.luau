-- Gemeinsame Grenzen für rein optische Gebäudeeffekte. Keine Spielmechanik
-- hängt davon ab, ob ein Client einen Effekt tatsächlich zeichnet.
return {
	RemoteName = "HouseDestructionEffectEvent",
	TemplateFolder = "HouseDestructionTemplates",
	ViewDistance = 320,
	MaxTransientEffects = 8,
	MaxVisibleFires = 8,
	UpdateInterval = 0.25,
	MaxTemplateEmitters = 4,
	MaxExplosionParticles = 120,
	MaxDustParticles = 80,
	MaxFireParticleRate = 40,
	SmokeParticleRate = 12,
	ExplosionDuration = 1,
	DustDuration = 7,
	FireDieDuration = 3,
	SmokeReduceDuration = 2.5,
	SmokeFadeDuration = 3.5,
	ExplosionSoundId = "rbxassetid://138668273240081",
}
