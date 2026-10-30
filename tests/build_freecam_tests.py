from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
head='''local total=0
local function check(ok,msg) assert(ok,msg);total+=1 end
local function signal() local s={};function s:Connect(fn) self.fn=fn end;return s end
local player={UserId=2,attrs={},signals={}}
function player:GetAttribute(k) return self.attrs[k] end
function player:GetAttributeChangedSignal(k) self.signals[k]=self.signals[k] or signal();return self.signals[k] end
function player:SetAttribute(k,v) self.attrs[k]=v;local s=self.signals[k];if s and s.fn then s.fn() end end
function player:FindFirstChildOfClass() return {GetChildren=function() return {} end} end
function player:WaitForChild() return {} end
local Enum={CreatorType={User=1},TextXAlignment={Right=1},TextTruncate={AtEnd=1},UserInputType={Keyboard=1},KeyCode={U=1,H=2,T=3}}
local game={CreatorType=1,CreatorId=1,GetService=function() return {IsStudio=function() return false end} end}
local Items=(function()
'''
body=(ROOT/'src/ReplicatedStorage/Shared/Items.luau').read_text()
tests='''
end)()
check(table.find(Items.POWERS,"freecam")~=nil,"freecam included in persistent gift catalog")
check(not Items.Has(player,"freecam"),"ordinary player has no freecam")
player:SetAttribute("Gift_freecam",true)
check(Items.Has(player,"freecam"),"freecam gift grants camera")
check(not Items.IsOwner(player),"freecam gift does not grant admin")
check(not Items.Has(player,"nuke"),"freecam gift does not grant other powers")
local Input={TakeWheel=function() return 0 end,IsControlled=function() return false end}
local Cam={override=nil,fovOffset=0}
local UI={C={},FONT_TITLE=1,FONT_NUM=1}
function UI.make(_,p) p.FindFirstChild=function() return nil end;return p end
function UI.panel(p) return p end
function UI.label(p) return p end
function UI.button(p,fn) return p end
local sounds={Play=function() end}
local function folder(t) t.WaitForChild=function(self,k) return self[k] end;return t end
local shared=folder({Items=Items,SoundLibrary=sounds})
local modules=folder({Input=Input,CameraController=Cam,UI=UI})
local uis={InputBegan=signal()}
local rs={Heartbeat=signal(),IsStudio=function() return false end}
local services={Players={LocalPlayer=player},ReplicatedStorage=folder({Shared=shared}),UserInputService=uis,RunService=rs}
game.GetService=function(_,n) return services[n] end
local require=function(v) assert(v,"unexpected dependency");return v end
local script={Parent=modules}
local Vector3={zero={}}
local Vector2={new=function() return {} end}
local UDim2={new=function() return {} end,fromOffset=function() return {} end}
local workspace={CurrentCamera={CFrame={Position={}},ViewportSize={X=1200}}}
local FreeCam=(function()
'''
freecam=(ROOT/'src/StarterPlayer/StarterPlayerScripts/RagdollClient/Client/FreeCam.luau').read_text()
tail='''
end)()
FreeCam.Init()
player:SetAttribute("Gift_freecam",nil)
FreeCam.Set(true)
check(not FreeCam.Active(),"camera refuses access without gift")
player:SetAttribute("Gift_freecam",true)
FreeCam.Set(true)
check(FreeCam.Active() and Input.freeCam and Input.wheelCapture,"gift enables camera and captures wheel")
check(Cam.override~=nil,"gift installs camera override")
-- Non-admin T must not load VehicleClient or move the body.
FreeCam.SetController({dead=false,torso={},_teleportTo=function() error("gift teleported body") end})
uis.InputBegan.fn({UserInputType=1,KeyCode=3},false)
check(true,"gift freecam cannot teleport body")
player:SetAttribute("Gift_freecam",nil)
check(not FreeCam.Active(),"revocation exits camera immediately")
check(not Input.freeCam and not Input.wheelCapture and Cam.override==nil,"revocation restores input and camera")
player:SetAttribute("Admin",true)
FreeCam.Set(true)
check(FreeCam.Active(),"admin retains freecam")
player:SetAttribute("Admin",nil)
check(not FreeCam.Active(),"admin revocation exits freecam")
print("PASS: "..total.." freecam gift assertions")
'''
(ROOT/'tests/freecam_tests.luau').write_text(head+body+tests+freecam+tail)
