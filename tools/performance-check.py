"""Gezielte kopflose Regressionen fuer Raster, HUD und lokale Effektgrenzen.

Fuehrt den echten Luau-Quelltext mit kleinen Roblox-Doubles aus. Darstellung,
Streaming-Reihenfolge und tatsaechliche Laufzeiten muessen in Studio geprueft werden.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def literal(text):
    return "[====[" + text + "]====]"


PRELUDE = r'''
local function signal()
 local handlers = {}
 return {
  Connect = function(self, fn)
   local token = { active = true }
   function token:Disconnect() self.active = false end
   table.insert(handlers, { token, fn })
   return token
  end,
  Fire = function(self, ...)
   for _, item in ipairs(handlers) do if item[1].active then item[2](...) end end
  end,
 }
end
local vectorMeta = {}
local function vector(x, y, z) return setmetatable({ X=x, Y=y, Z=z }, vectorMeta) end
vectorMeta.__sub = function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__mul = function(a,b) return vector(a.X*b.X,a.Y*b.Y,a.Z*b.Z) end
vectorMeta.__index = function(a,k) if k == "Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end end
local function run(text, env)
 local fn, err = loadstring(text)
 assert(fn, err)
 setmetatable(env, { __index = getfenv() })
 setfenv(fn, env)
 return fn()
end
local workspace = {}
local added, removed = signal(), signal()
local collection = { tagged = {} }
function collection:GetTagged() return self.tagged end
function collection:GetInstanceAddedSignal() return added end
function collection:GetInstanceRemovedSignal() return removed end
local function house(x,z,sx,sz,angle)
 local h = { attrs = {}, signals = {}, inWorld = true, calls = 0 }
 h.AncestryChanged, h.DescendantAdded, h.DescendantRemoving = signal(), signal(), signal()
 function h:IsA(t) return t == "Model" end
 function h:IsDescendantOf() return self.inWorld end
 function h:GetAttribute(k) return self.attrs[k] end
 function h:GetPropertyChangedSignal(k)
  self.signals[k] = self.signals[k] or signal()
  return self.signals[k]
 end
 h.GetAttributeChangedSignal = h.GetPropertyChangedSignal
 function h:SetAttribute(k,v) self.attrs[k]=v; self:GetAttributeChangedSignal(k):Fire() end
 function h:GetBoundingBox()
  self.calls += 1
  return { Position=vector(self.x,0,self.z), RightVector=vector(math.cos(self.angle),0,math.sin(self.angle)),
   UpVector=vector(0,1,0), LookVector=vector(-math.sin(self.angle),0,math.cos(self.angle)) }, vector(self.sx,30,self.sz)
 end
 h.x,h.z,h.sx,h.sz,h.angle = x,z,sx,sz,angle or 0
 return h
end
local function contains(list, value) return table.find(list,value) ~= nil end
'''

INDEX_TEST = r'''
local near, far = house(0,0,20,20), house(8000,0,20,20)
local wide, rotated = house(500,0,1000,30), house(-600,0,20,1000,math.pi/2)
local negative = house(-128,-128,10,10)
local huge = house(40000,40000,100000,100000)
collection.tagged = { near, far, wide, rotated, negative, huge }
local index = run(INDEX_SOURCE, { game = { GetService=function(_,name)
 return name == "CollectionService" and collection or workspace end },
 debug={profilebegin=function() end,profileend=function() end} })
assert(contains(index.Query(vector(0,0,0),8),near),"nahes Haus fehlt")
assert(not contains(index.Query(vector(0,0,0),8),far),"ferne Stadt wird durchsucht")
assert(contains(index.Query(vector(0,0,0),8),wide),"Rand eines grossen Hauses fehlt")
assert(contains(index.Query(vector(-1050,0,0),8),rotated),"gedrehte Grundflaeche fehlt")
assert(contains(index.Query(vector(-128,0,-128),8),negative),"negative Rastergrenze falsch")
assert(contains(index.Query(vector(0,0,0),8),huge),"uebergrosses Haus fehlt")
local calls = near.calls + far.calls + wide.calls
for i=1,100 do index.Query(vector(i,0,0),8) end
assert(calls == near.calls + far.calls + wide.calls,"statische Bounds werden erneut berechnet")
near:SetAttribute("Destroyed",true)
assert(not contains(index.Query(vector(0,0,0),8),near),"zerstoertes Haus weiterhin Ziel")
near.x = 2000
near:SetAttribute("Destroyed",false)
assert(contains(index.Query(vector(2000,0,0),8),near),"Respawnposition fehlt")
assert(not contains(index.Query(vector(0,0,0),8),near),"alte Rasterzelle bleibt belegt")
local new = house(0,0,20,20)
added:Fire(new)
assert(contains(index.Query(vector(0,0,0),8),new),"neues Haus fehlt")
new.x = -3000
new:GetPropertyChangedSignal("WorldPivot"):Fire()
assert(contains(index.Query(vector(-3000,0,0),8),new),"versetztes Haus fehlt")
removed:Fire(new)
assert(not contains(index.Query(vector(-3000,0,0),8),new),"entferntes Tag bleibt im Raster")
-- Jede zufaellig gedrehte Hauskante muss in der Vorauswahl liegen.
math.randomseed(41)
for i=1,150 do
 local h=house(math.random(-10000,10000),math.random(-10000,10000),math.random(10,1500),math.random(10,300),math.random()*math.pi)
 added:Fire(h)
 for _,side in ipairs({-1,1}) do
  local x=h.x+math.cos(h.angle)*h.sx/2*side
  local z=h.z+math.sin(h.angle)*h.sx/2*side
  assert(contains(index.Query(vector(x,0,z),8),h),"gedrehte Kante fehlt")
 end
 removed:Fire(h)
end
print("[Performance] Raster: Grenzen, grosse/gedrehte Haeuser, Bewegung, Respawn, Tags und Bounds-Cache OK")
'''

EFFECT_TEST = r'''
local now=100
function workspace:GetServerTimeNow() return now end
workspace.CurrentCamera={CFrame={Position=vector(0,0,0)}}
local config=run(CONFIG_SOURCE,{})
local remote={OnClientEvent=signal()}
local counts={dust=0,explosion=0,sound=0,fire=0,alive=0,maxAlive=0}
local visuals={}
function visuals.Dust() counts.dust+=1 end
function visuals.Explosion() counts.explosion+=1 end
function visuals.Sound() counts.sound+=1 end
function visuals.CreateFire()
 counts.fire+=1; counts.alive+=1; counts.maxAlive=math.max(counts.maxAlive,counts.alive)
 return {anchor={Destroy=function() counts.alive-=1 end}}
end
function visuals.UpdateFire() end
local deferred, delayed, loops = {}, {}, {}
local tasks={
 delay=function(_,fn) table.insert(delayed,fn) end,
 defer=function(fn) table.insert(deferred,fn) end,
 wait=function() coroutine.yield() end,
 spawn=function(fn) local co=coroutine.create(fn); table.insert(loops,co); assert(coroutine.resume(co)) end,
}
local storage={WaitForChild=function(_,name) return name==config.RemoteName and remote or name end}
local game={GetService=function(_,name) return name=="CollectionService" and collection or storage end}
local env={game=game,workspace=workspace,Vector3={new=vector},task=tasks,
 debug={profilebegin=function() end,profileend=function() end},require=function(name)
 return name=="DestructionEffectConfig" and config or visuals end}
collection.tagged={}
run(CLIENT_SOURCE,env)
for i=1,100 do
 remote.OnClientEvent:Fire("Collapse",vector(0,0,0),vector(20,20,20),100)
 remote.OnClientEvent:Fire("Explosion",vector(0,0,0),vector(20,20,20),100)
end
assert(counts.dust==4 and counts.explosion==4 and counts.sound==4,"Effektgrenze greift nicht")
for _,fn in ipairs(delayed) do fn() end
assert(counts.dust==4 and counts.explosion==4,"Effekte wurden in Warteschlange gelegt")
remote.OnClientEvent:Fire("Collapse",vector(10000,0,0),vector(20,20,20),100)
assert(counts.dust==4,"ferner Effekt erzeugt")
remote.OnClientEvent:Fire("Collapse",vector(0,0,0),vector(20,20,20),100)
assert(counts.dust==5,"Effektplaetze nicht freigegeben")
local fires={}
for i=1,20 do
 local h=house(i,0,20,20)
 h.attrs.FireVisualPosition=vector(i,0,0); h.attrs.FireVisualEndsAt=200
 table.insert(fires,h); added:Fire(h)
end
assert(coroutine.resume(loops[1]))
assert(counts.alive==8 and counts.maxAlive==8,"Feuergrenze greift nicht")
fires[1]:SetAttribute("FireVisualEndsAt",nil)
assert(counts.alive==7,"Loeschen entfernt Feuer nicht sofort")
assert(coroutine.resume(loops[1]))
assert(counts.alive==8,"naechstes nahes Feuer fehlt")
removed:Fire(fires[2])
assert(counts.alive==7,"Stream-Out entfernt Darstellung nicht")
added:Fire(fires[2])
assert(coroutine.resume(loops[1]))
assert(counts.alive==8,"Stream-In rekonstruiert Feuer nicht")
workspace.CurrentCamera.CFrame.Position=vector(10000,0,0)
assert(coroutine.resume(loops[1])); assert(counts.alive==0,"ferne Feuer bleiben sichtbar")
workspace.CurrentCamera.CFrame.Position=vector(0,0,0)
assert(coroutine.resume(loops[1])); assert(counts.alive==8,"Rueckkehr rekonstruiert Feuer nicht")
now=201
assert(coroutine.resume(loops[1])); assert(counts.alive==0,"abgelaufene Feuer bleiben sichtbar")
local actual=run(VISUAL_SOURCE,{game=game,require=function() return config end})
local emitter={Rate=40}
local state={fire={},smoke={},rates={[emitter]=40},size=10,heat=3}
actual.UpdateFire(state,20); assert(emitter.Rate==40 and state.smoke.Rate==12)
actual.UpdateFire(state,3.5); assert(emitter.Rate==0 and math.abs(state.smoke.Rate-4.8)<0.001)
actual.UpdateFire(state,0); assert(emitter.Rate==0 and state.smoke.Rate==0)
print("[Performance] Effekte: Burst-Limits, keine Warteschlange, Entfernung, Feuerlimit, Loeschen, Stream-In/Out und Ausklingen OK")

-- Der echte Serverpfad veroeffentlicht nur wenige Emittervorlagen, keine VFX-Modelle.
local instances={}
local function instance(class)
 local item={ClassName=class}
 table.insert(instances,item)
 function item:ClearAllChildren() end
 function item:FindFirstChild(name)
  for _,child in ipairs(instances) do if child.Parent==self and child.Name==name then return child end end
 end
 return item
end
local originals={}
for i=1,12 do
 local emitter={IsA=function(_,name) return name=="ParticleEmitter" end,
  Clone=function() return instance("ParticleEmitter") end}
 table.insert(originals,emitter)
end
local template={GetDescendants=function() return originals end}
local effectsFolder={FindFirstChild=function() return template end}
local serverStorage={FindFirstChild=function() return effectsFolder end}
local serverPlayers={GetPlayers=function() return {
 {Character={FindFirstChild=function() return {Position=vector(0,0,0)} end}},
 {Character={FindFirstChild=function() return {Position=vector(10000,0,0)} end}},
} end}
local sent=0
local serverRemote={FireClient=function() sent+=1 end}
local utils={GetOrCreate=function() return serverRemote end}
local serverEffects=run(SERVER_SOURCE,{
 game={GetService=function(_,name)
  if name=="Players" then return serverPlayers end
  if name=="ServerStorage" then return serverStorage end
  return storage
 end},
 workspace=workspace,Vector3={new=vector},Instance={new=instance},
 require=function(name) return name=="DestructionEffectConfig" and config or utils end,
})
local templateCount=0
for _,item in ipairs(instances) do
 assert(item.ClassName=="Folder" or item.ClassName=="ParticleEmitter","Server erzeugt VFX-Geometrie")
 if item.ClassName=="ParticleEmitter" then
  templateCount+=1;assert(item.Enabled==false,"Vorlage emittiert im ReplicatedStorage")
 end
end
assert(templateCount==config.MaxTemplateEmitters*2,"Vorlagenlimit greift nicht")
serverEffects.Emit("Collapse",vector(0,0,0),vector(20,20,20),100)
assert(sent==1,"ferner Spieler erhaelt Effektereignis")
local fireHouse=house(0,0,20,20)
serverEffects.StartFire(fireHouse,{Position=vector(0,0,0)},60)
assert(fireHouse.attrs.FireVisualEndsAt==now+60,"Brenndauer nicht synchronisiert")
serverEffects.StopFire(fireHouse)
assert(fireHouse.attrs.FireVisualEndsAt==nil and fireHouse.attrs.FireVisualPosition==nil,"Loeschen laesst Brennzustand zurueck")
print("[Performance] Servereffekte: begrenzte Emittervorlagen, nahe Empfaenger und replizierter Brennzustand OK")

-- Ereignisverdichtung und spaet replizierte Werte der echten HUD-Verdrahtung.
local changedCity, changedZone=signal(),signal()
local player={GetAttributeChangedSignal=function(_,name) return name=="CurrentCityName" and changedCity or changedZone end}
local children={}
local values={ChildAdded=signal(),ChildRemoved=signal(),GetChildren=function() return children end}
local visibleSignal=signal()
local warning={GetPropertyChangedSignal=function() return visibleSignal end}
local updates=0
local hudEnv={cityAlertValues=values,player=player,warnFrame=warning,screenGui={Parent=true},
 cityBrokenBanner={Visible=false},task=tasks,updateQuestList=function() updates+=1 end}
run(HUD_SOURCE,hudEnv)
local initial=updates
changedCity:Fire();changedZone:Fire();visibleSignal:Fire()
assert(updates==initial,"HUD aktualisiert ungepuffert")
local pending=deferred;deferred={};for _,fn in ipairs(pending) do fn() end
assert(updates==initial+1,"HUD-Ereignisse nicht zusammengefasst")
local value=house(0,0,1,1)
value.Name="MegaCityTask_Titan_Complete"
value.IsA=function(_,name) return name=="ValueBase" end
values.ChildAdded:Fire(value)
pending=deferred;deferred={};for _,fn in ipairs(pending) do fn() end
local before=updates
value:GetPropertyChangedSignal("Value"):Fire()
pending=deferred;deferred={};for _,fn in ipairs(pending) do fn() end
assert(updates==before+1,"spaeter Aufgabenwert nicht verbunden")
values.ChildRemoved:Fire(value)
pending=deferred;deferred={};for _,fn in ipairs(pending) do fn() end
before=updates
value:GetPropertyChangedSignal("Value"):Fire()
assert(#deferred==0 and updates==before,"Verbindung nach Entfernung bleibt bestehen")
assert(coroutine.resume(loops[2]));assert(updates==before,"Countdown baut Aufgabenliste neu")
print("[Performance] HUD: Ereignisverdichtung, Stadt-/Zonenwechsel, spaete Werte, Entfernen und getrennter Countdown OK")
'''


def main():
    files = [
        "src/ServerScriptService/CombatHandler.server.luau",
        "src/ServerScriptService/KaijuStageOneCombatAdapter.luau",
        "src/ServerScriptService/SpecialAttackHandler.server.luau",
        "src/ServerScriptService/HouseHandler.server.luau",
        "src/ServerScriptService/HouseSpatialIndex.luau",
        "src/ServerScriptService/HouseDestructionEffects.luau",
        "src/StarterPlayerScripts/HouseDestructionEffectsClient.client.luau",
        "src/StarterPlayerScripts/CityAlertHudClient.client.luau",
        "src/ReplicatedStorage/HouseDestructionVisuals.luau",
        "src/ReplicatedStorage/DestructionEffectConfig.luau",
        "src/ServerScriptService/AutoCombatService.server.luau",
    ]
    definitions = {
        "INDEX_SOURCE": files[4], "CLIENT_SOURCE": files[6],
        "VISUAL_SOURCE": files[8], "CONFIG_SOURCE": files[9],
        "SERVER_SOURCE": files[5],
    }
    chunks = [PRELUDE]
    for name, path in definitions.items():
        chunks.append(f"local {name} = {literal(source(path))}\n")
    hud = source(files[7])
    hud = hud[hud.index("local questUpdatePending"):hud.index("-- Wird von CityAlertAnnouncementClient")]
    chunks.append(f"local HUD_SOURCE = {literal(hud)}\n")
    for path in files:
        chunks.append(f"assert(loadstring({literal(source(path))}), {literal(path)})\n")
    chunks += [INDEX_TEST, EFFECT_TEST]
    # Direkte Installation bevorzugen: der Rokit-Shim braucht je nach Sandbox HOME.
    storage = Path(os.environ.get("USERPROFILE", str(Path.home()))) / ".rokit/tool-storage/luau-lang/luau"
    binaries = sorted(storage.glob("*/luau.exe"))
    binary = str(binaries[-1]) if binaries else shutil.which("luau")
    if not binary:
        raise SystemExit("Luau nicht gefunden")
    with tempfile.TemporaryDirectory(prefix="kaiju-performance-") as temporary:
        script = Path(temporary) / "checks.luau"
        script.write_text("\n".join(chunks), encoding="utf-8")
        result = subprocess.run([binary, str(script)], cwd=ROOT)
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
