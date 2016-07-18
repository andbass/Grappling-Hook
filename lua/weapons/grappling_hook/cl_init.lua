
include "shared.lua"

local ropeMat        = Material("cable/rope")
local ropeWidth      = 1.5
local ropeBrightness = 200

local ropeColor = Color(ropeBrightness, ropeBrightness, ropeBrightness)

local function HookOffset(hook)
        local hookUp = hook:GetUp() * 10
        local hookRight = hook:GetRight() * 2.2

        return hook:GetPos() + hookUp - hookRight
end

function SWEP:PostDrawViewModel(vm, wep, ply)
    local hook = self:GetHook()

    if IsValid(hook) then
        cam.Start3D()
            render.SetMaterial(ropeMat)

            local boltId = vm:LookupAttachment("spark")
            local bolt = vm:GetAttachment(boltId)

            local hookPos = HookOffset(hook)
            render.DrawBeam(bolt.Pos, hookPos, ropeWidth, 0, 3, ropeColor)
        cam.End3D()
    end
end

function SWEP:DrawWorldModel()
    local hook = self:GetHook()

    if IsValid(hook) then
        local ply = self.Owner
        render.SetMaterial(ropeMat)

        local hookPos = HookOffset(hook)
        local wepPos = self.Weapon:GetPos() + ply:GetAimVector() * 29 + ply:GetRight() * 11

        render.DrawBeam(wepPos, hookPos, ropeWidth, 0, 3, ropeColor)
    end

    self.Weapon:DrawModel()
end

function SWEP:DrawHolsteredRope()
    local hook = self:GetHook()

    if IsValid(hook) then
        local ply = self.Owner
        render.SetMaterial(ropeMat)

        local hookPos = HookOffset(hook)
        local beltPos = ply:GetPos() + ply:GetForward() * 3 - ply:GetRight() * 6 + ply:GetUp() * 10

        render.DrawBeam(beltPos, hookPos, ropeWidth, 0, 2, ropeColor)
    end
end

