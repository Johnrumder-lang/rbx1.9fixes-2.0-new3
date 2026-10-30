"""Regenerate the CLI harness from current source files, with mocked Roblox service boundaries."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'src';CASES=ROOT/'tests/cases'
def source(name):
    matches=list(SRC.rglob(name+'.luau'));assert len(matches)==1,name
    return matches[0].read_text()
def module(name,text):return 'local '+name+'=(function()\n'+text+'\nend)()\n'
def case(name):return (CASES/(name+'.luau.in')).read_text()
s=case('head')+module('Chips',source('Chips'))+'shared.children.Chips=Chips\n'
s+=module('TimeScale',source('TimeScale'))+case('time')
s+=module('Sandy',source('SandevistanService').replace('return SandevistanService','SandevistanService._states=implants\nreturn SandevistanService'))+case('sandy')
s+=module('Chip',source('ChipService').replace('return ChipService\n','ChipService._states=states\nChipService._dodge=tryDodge\nChipService._public=publicAttrs\nChipService._setup=function(d,r) deps=d;Remote=r end\nreturn ChipService\n'))+case('chip')
s+='\nmodules.children.SaveGate={CanSave=function() return true end}\nmodules.children.ProgressEpoch={Key=function(id) return "p_"..id end}\nlocal previousService=game.GetService\ngame.GetService=function(self,name) if name=="RunService" then return {IsStudio=function() return false end} end return previousService(self,name) end\n'
s+=module('Persist',source('Persist').replace('return Persist\n','Persist._setup=function(p,prof,st) profiles[p]=prof;store=st end\nreturn Persist\n'))+case('transactions')
s+=case('freeze').replace('@SUPER@',source('SuperService'))
for name in ('epoch','jobs','defense','control','gifts','payload','dodge','psychosis'):
    text=case(name)
    import re
    for mod in re.findall(r'@MODULE:([A-Za-z]+)@',text):
        code=source(mod)
        if mod=='JobService':code=code.replace('return JobService\n','JobService._accept=accept;JobService._finish=finish;JobService._active=active;JobService._fail=fail;JobService._tick=tick;JobService._cooldown=cooldown\nreturn JobService\n')
        if mod=='ControlService':code=code.replace('return Service\n','Service._directives=directives\nreturn Service\n')
        text=text.replace('@MODULE:'+mod+'@',code)
    if name=='defense':
        bullet=source('DamageService');bullet=bullet[bullet.index('function DamageService.ApplyBullet'):bullet.index('-- a living player tore')]
        text=text.replace('@APPLYBULLET@',bullet)
        resolve=source('GunService');resolve=resolve[resolve.index('local function resolve('):resolve.index('function GunService.Fire')]
        text=text.replace('@RESOLVE@',resolve)
    if name=='payload':
        payload=source('ChipService');payload=payload[payload.index('function ChipService.FirePayload'):payload.index('------------------------------------------------------------------------',payload.index('function ChipService.FirePayload'))]
        text=text.replace('@PAYLOAD@',payload)
    if name=='psychosis':
        fn=source('CyberService');fn=fn[fn.index('function CyberService.AdminPsychosis'):fn.index('function CyberService.Init')]
        text=text.replace('@ADMINPSYCHOSIS@',fn)
    s+=text
s+='\nprint("PASS: "..total.." current-source assertions")\n'
(ROOT/'tests/gameplay_tests.luau').write_text(s)
