--!nonstrict
-- Pockets (mixin for CharacterController, v1.9.1): HOLD Q / E (L1 / R1 on a controller) while a hand holds an item and
-- it goes into your pocket (two pockets: left and right; small things at the hip, long things on the back).
-- Hold it with an empty hand and the item comes out again. A quick tap does what it always did (let go / throw).
-- On a phone the STOW L / STOW R buttons do the same. Stowed items stay on you when you fall over.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local HOLD = 0.4 -- s you hold the key

return function(Controller)
	local GripRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Grip") :: RemoteEvent
	local me = Players.LocalPlayer

	local function keyHeld(side: string): boolean
		if UserInputService:IsKeyDown(side == "Left" and Enum.KeyCode.Q or Enum.KeyCode.E) then
			return true
		end
		local pad = side == "Left" and Enum.KeyCode.ButtonL1 or Enum.KeyCode.ButtonR1
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, pad)
	end

	-- my stowed items: { [slot] = item }
	function Controller:_pockets(): { [number]: Model }
		local out = {}
		for _, item in CollectionService:GetTagged("Stowed") do
			if item:IsA("Model") and item:GetAttribute("StowedBy") == me.UserId then
				local slot = item:GetAttribute("StowSlot")
				-- (v2.8) STILLWATER in its sheath shares the sheath's pocket: taking out draws the sword
				if typeof(slot) == "number" and (not out[slot] or item:GetAttribute("InSheath")) then
					out[slot] = item
				end
			end
		end
		return out
	end

	function Controller:_stow(side: string)
		local hand = self.hands and self.hands[side]
		local g = hand and hand.grip
		local item = g and g.item
		if not item or not item.Parent or not item.PrimaryPart then
			return
		end
		GripRemote:FireServer("stow", item.PrimaryPart, side)
		self:_release(side, false)
	end

	function Controller:_unstow(side: string)
		local mine = self:_pockets()
		local item = mine[side == "Left" and 1 or 2] or mine[side == "Left" and 2 or 1]
		if not item or not item.PrimaryPart then
			return
		end
		local handle = item.PrimaryPart
		GripRemote:FireServer("unstow", handle, side)
		-- when the server has taken it out of the pocket, the hand takes it
		task.spawn(function()
			local t0 = os.clock()
			while item.Parent and item:GetAttribute("StowedBy") ~= nil and os.clock() - t0 < 1.2 do
				task.wait(0.03)
			end
			if item.Parent and item:GetAttribute("StowedBy") == nil then
				local hand = self.hands and self.hands[side]
				if hand and not hand.grip then
					self:_gripItem(side, item)
				end
			end
		end)
	end

	-- phone buttons: one button, "put away" or "take out"
	function Controller:_pocketToggle(side: string)
		local hand = self.hands and self.hands[side]
		if hand and hand.grip and hand.grip.item then
			self:_stow(side)
		elseif hand and not hand.grip then
			self:_unstow(side)
		end
	end

	-- the grab key: a tap behaves as before, a long press stows / takes out
	local plainToggle = Controller._toggleHand
	function Controller:_toggleHand(side: string)
		local hand = self.hands and self.hands[side]
		local g = hand and hand.grip
		self.pocketBusy = self.pocketBusy or {}
		if self.pocketBusy[side] then
			return
		end
		if g and g.item and g.item.Parent and not g.static then
			-- an item in the hand: wait to see if it is a tap or a hold
			self.pocketBusy[side] = true
			local t0 = os.clock()
			task.spawn(function()
				while keyHeld(side) and os.clock() - t0 < HOLD do
					task.wait()
				end
				self.pocketBusy[side] = nil
				if keyHeld(side) then
					self:_stow(side)
				else
					plainToggle(self, side)
				end
			end)
			return
		end
		plainToggle(self, side)
		-- an empty hand that stays on the key: take something out of the pocket
		if not (hand and hand.grip) then
			self.pocketBusy[side] = true
			local t0 = os.clock()
			task.spawn(function()
				while keyHeld(side) and os.clock() - t0 < HOLD do
					task.wait()
				end
				self.pocketBusy[side] = nil
				if keyHeld(side) and hand and not hand.grip then
					self:_unstow(side)
				end
			end)
		end
	end
end
