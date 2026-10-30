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
s+=module('Persist',source('Persist').replace('return Persist\n','Persist._save=save\nPersist._setup=function(p,prof,st) profiles[p]=prof;store=st end\nreturn Persist\n'))+case('transactions')
s+=case('freeze').replace('@SUPER@',source('SuperService'))
for name in ('epoch','jobs','defense','control','gifts','payload','dodge','psychosis','community','clans','daily','navigation','ground','video','camera','psycho_state','chip_updates','chip_ui','mobile_chips','ripper'):
    text=case(name)
    import re
    for mod in re.findall(r'@MODULE:([A-Za-z]+)@',text):
        code=source(mod)
        if mod=='JobService':code=code.replace('return JobService\n','JobService._accept=accept;JobService._finish=finish;JobService._active=active;JobService._fail=fail;JobService._tick=tick;JobService._cooldown=cooldown\nreturn JobService\n')
        if mod=='CameraService':code=code.replace('return CameraService\n','CameraService._recording=recording\nreturn CameraService\n')
        if mod=='ClanService':code=code.replace('return Service\n','Service._create=create;Service._invite=invite;Service._accept=accept;Service._remove=remove;Service._refresh=refresh\nreturn Service\n')
        if mod=='DailyRewardService':code=code.replace('return Service\n','Service._schedule=schedule;Service._claim=claim;Service._roll=roll;Service._take=takeCase\nreturn Service\n')
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
    if name=='chip_ui':
        ui=source('ChipClient');text=text.replace('@SLOT_BUILD@',ui[ui.index('\t-- NECK SLOTS'):ui.index('\t-- CHIPS (the bag)')])
        start=ui.index('\t\t-- slots',ui.index('local function buildDeck'))
        text=text.replace('@SLOT_REFRESH@',ui[start:ui.index('\t\t-- the bag',start)])
    if name=='mobile_chips':
        ui=source('ChipClient');start=ui.index('local function storeHeldChip()')
        text=text.replace('@MOBILE_BUILD@',ui[start:ui.index('\tpanel = UI.make("Frame",',start)]+'end\n')
        start=ui.index('\tInput.Action:Connect(function(action)')
        text=text.replace('@MOBILE_ACTION@',ui[start:ui.index('\tUserInputService.InputBegan:',start)])
    if name=='chip_updates':
        config=source('Config');lines=[line for line in config.splitlines() if line.startswith(('Config.ChipSlots =','Config.QuickhackDelay ='))]
        text=text.replace('@CHIPCONFIG@','\n'.join(lines))
        codes=source('RewardService');text=text.replace('@CODES@',codes[codes.index('RewardService.CODES ='):codes.index('type Profile =')])
    if name=='ripper':
        code=source('RipperdocService');text=text.replace('@RIPPER_CHECK@',code[code.index('local function check('):code.index('local function enqueue(')].replace('local function check(', 'local function validateRemoval('))
        text=text.replace('=check(p,','=validateRemoval(p,').replace('eq(check(p,','eq(validateRemoval(p,')
    if name=='video':
        video=source('ChipClient');video=video[video.index('local videoToken = 0'):video.index('local targetPicker')]
        text=text.replace('@VIDEO@',video)
    if name=='psychosis':
        fn=source('CyberService');fn=fn[fn.index('function CyberService.AdminPsychosis'):fn.index('function CyberService.Init')]
        text=text.replace('@ADMINPSYCHOSIS@',fn)
    s+=text
s+='\nprint("PASS: "..total.." current-source assertions")\n'
(ROOT/'tests/gameplay_tests.luau').write_text(s)
