
AddCSLuaFile()

include "meta.lua"

local fireSound = Sound("weapons/crossbow/fire1.wav")
local hookContactSounds = {
    Sound("physics/metal/sawblade_stick1.wav"),
    Sound("physics/metal/sawblade_stick2.wav"),
    Sound("physics/metal/sawblade_stick3.wav"),
}
local hookReleaseSound = Sound("buttons/weapon_confirm.wav")

local hookMdl      = "models/props_junk/meathook001a.mdl"
local hookMdlScale = 0.7

local hookMass   = 10
local hookSpeed  = 25000

local boostPower  = 285
local swingSpeed  = 10
local reloadSpeed = 1.7

local inAirGrappleStrength    = 15
local onGroundGrappleStrength = 50

local reelInSpeed = 4
local rappelSpeed = 3

local AttachState = {
    Nothing = 0,
    World   = 1,
    Prop    = 2,
}

function SWEP:SetupDataTables()
    self:NetworkVar("Entity", 0, "Hook")
    self:NetworkVar("Int", 0, "AttachState")
    self:NetworkVar("Float", 0, "TargetRopeDist")
end

function SWEP:Initialize()
    self:SetWeaponHoldType("crossbow")
    self:Cleanup()
end

function SWEP:CanPrimaryAttack()
    return not IsValid(self:GetHook())
end

function SWEP:PrimaryAttack()
    if not self:CanPrimaryAttack() then return end

    self:EmitSound(fireSound)
    self:ShootEffects()
    self.Owner:GetViewModel():SetPlaybackRate(1)

    if CLIENT then return end

    self:CreateHook()
end

-- Unused, as any functionality involving velocity changes must be handled specially
function SWEP:SecondaryAttack() end

function SWEP:CanReelIn()
    local hook = self:GetHook()

    return IsValid(hook) and self:IsHookAttached()
end

function SWEP:ReelIn()
    if not self:CanReelIn() then return end
    local hook = self:GetHook()

    self:SetTargetRopeDist(math.max(self:GetTargetRopeDist() - reelInSpeed, 50))

    local ply = self.Owner
    local plyPos = ply:GetPos()

    local playerToHookDir = hook:GetPos() - plyPos
    if playerToHookDir.z > 0 and ply:IsOnGround() then -- Give player slight boost to get off ground, if they're ascending
        plyPos.z = plyPos.z + 1
        ply:SetPos(plyPos)
    end

    return self:PullOwner()
end

function SWEP:Cleanup()
    self:SetAttachState(AttachState.Nothing)

    local hook = self:GetHook()
    if IsValid(hook) then 
        hook:Remove()
        self:SetHook(nil)
    end
end

function SWEP:Reload()
    if not IsValid(self:GetHook()) and not self:IsHookAttached() then return end

    self:EmitSound(hookReleaseSound)

    self.Owner:SetAnimation(PLAYER_RELOAD)
    self:SendWeaponAnim(ACT_VM_RELOAD)

    self.Owner:GetViewModel():SetPlaybackRate(reloadSpeed)
    local animTime = self.Owner:GetViewModel():SequenceDuration() / (reloadSpeed + 2)

    self.reloadingTime = CurTime() + animTime
    self:SetNextPrimaryFire(self.reloadingTime)

    if SERVER then self:Cleanup() end
end

function SWEP:HolsterReload()
    self:EmitSound(hookReleaseSound)
    if SERVER then self:Cleanup() end
end

function SWEP:Holster()
    if CLIENT then
        hook.Add("PostDrawOpaqueRenderables", "grapple_Render", function()
            self:DrawHolsteredRope()
        end)
    elseif SERVER then
        hook.Add("Think", "grapple_Think", function()
            self:Think()
        end)
    end

    return true
end

function SWEP:Deploy()
    self:CallOnClient("Deploy")

    if SERVER then hook.Remove("Think", "grapple_Think") end
    if CLIENT then hook.Remove("PostDrawOpaqueRenderables", "grapple_Render") end

    return true
end

function SWEP:OnRemove()
    self:Deploy()
    self:Cleanup()
end

function SWEP:CreateHook()
    local ply = self.Owner
    local ent = ents.Create("prop_physics")
    if not IsValid(ent) then return end

    ent:SetModel(hookMdl)
    ent:SetModelScale(hookMdlScale)

    ent:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    ent:SetPos(ply:EyePos() + ply:GetAimVector())

    local aimVec = ply:GetAimVector()
    local hookAng = aimVec:Angle()

    hookAng:RotateAroundAxis(hookAng:Up(), -90)
    hookAng:RotateAroundAxis(hookAng:Forward(), 90)

    ent:SetAngles(hookAng)
    ent:Spawn()
    ent:Activate()

    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then ent:Remove() return end

    phys:SetMass(hookMass)
    ent:AddCallback("PhysicsCollide", function(phys, data) 
        self:HookCollide(phys, data)
    end)

    local vel = aimVec * hookSpeed
    phys:ApplyForceCenter(vel)

    self:SetHook(ent)
end

function SWEP:CreateRope()
    local ply = self.Owner

    local rope = constraint.CreateKeyframeRope(
        Vector(), ropeWidth, ropeMat, nil,      -- Pos, width, material, constraint
        ply, Vector(), 0,                       -- Player ent, offset, bone
        self.hook, Vector(0, 3, 12), 0          -- Hook ent, offset, bone
    )

    self.rope = rope
end

function SWEP:HookCollide(phys, data)
    if self:IsHookAttached() then return end

    sound.Play(table.Random(hookContactSounds), data.HitPos, 150, 100, 1)

    self.collideData = data

    self:AttachHook()
    self:CreateEffect()
end

function SWEP:AttachHook()
    local hook = self:GetHook()
    local data = self.collideData

    hook:GetPhysicsObject():EnableMotion(false)
    hook:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

    self.Owner:ViewPunch(Angle(-2, 0, 0))
    
    -- Push in hook into surface
    local impactDir = data.OurOldVelocity
    impactDir:Normalize()

    local cosBetween = math.abs(impactDir:Dot(data.HitNormal))
    local pushAmount = 12 + 2 * (1 - cosBetween)

    local newPos = data.HitPos - impactDir * pushAmount
    hook:SetPos(newPos)

    local attachState = AttachState.World
    if not data.HitEntity:IsWorld() then
        hook:SetMoveType(MOVETYPE_NONE)
        hook:SetParent(data.HitEntity)

        local hookPhys = hook:GetPhysicsObject()
        hookPhys:EnableMotion(true)

        attachState = AttachState.Prop
    end

    local initialTug = 20
    local upwardness = math.max(impactDir:Dot(Vector(0, 0, 1)), 0)
    local tug = initialTug + 10 * upwardness

    self:SetTargetRopeDist(hook:GetPos():Distance(self.Owner:GetPos()) - tug)
    self:SetAttachState(attachState)
end

function SWEP:IsHookAttached()
    return self:GetAttachState() ~= AttachState.Nothing
end

function SWEP:CreateEffect()
    local data = self.collideData

    local traceResult = util.TraceEntity({
        mask = MASK_ALL,
        start = data.HitPos - data.HitNormal,
        endpos = data.HitPos + data.HitNormal,
    }, data.HitEntity)

    local effectData = EffectData()

    effectData:SetOrigin(data.HitPos + data.HitNormal * 10)
    effectData:SetNormal(data.HitNormal)

    util.Effect("ManhackSparks", effectData)
end

function SWEP:Rappel()
    if CLIENT then return end

    self:SetTargetRopeDist(self:GetTargetRopeDist() + rappelSpeed)
end

function SWEP:Swing()
    local ply = self.Owner
    local hook = self:GetHook()

    if not IsValid(hook) then return Vector() end

    local multiplier = swingSpeed
    if ply:KeyDown(IN_BACK) then multiplier = -multiplier end

    local playerToHookDir = hook:GetPos() - ply:GetPos()
    playerToHookDir:Normalize()

    local swingDir = playerToHookDir:Cross(ply:GetRight())
    swingDir:Normalize()

    return swingDir * multiplier
end

function SWEP:PullOwner()
    local hook = self:GetHook()
    if not IsValid(hook) then return Vector() end

    local ply = self.Owner
    local playerToHookDir = hook:GetPos() - ply:GetPos()

    playerToHookDir:Normalize()
    playerToHookDir.z = math.max(playerToHookDir.z, 0)

    local speedMultiplier = inAirGrappleStrength
    if ply:IsOnGround() then
        speedMultiplier = onGroundGrappleStrength
    end

    local vel = playerToHookDir * speedMultiplier

    -- Cancels out vertical oscillations
    if vel.z * ply:GetVelocity().z < 0 then -- if Z velocities have different signs
        vel.z = vel.z - ply:GetVelocity().z * 0.5
    end

    return vel
end

function SWEP:IsOwnerVaulting(curDistToHook)
    local ply = self.Owner
    return curDistToHook < 100 and not ply:IsOnGround() and ply:KeyDown(IN_JUMP)
end

function SWEP:Think()
    local ply = self.Owner
    local hook = self:GetHook()

    if not IsValid(hook) and self:IsHookAttached() then -- Cleanup if the hook's parent gets destroyed
        self:Reload()
    elseif self:IsHookAttached() then
        local newVel = Vector()
        local curDistance = ply:GetPos():Distance(hook:GetPos())
        local reeledIn = false

        if ply:GetActiveWeapon() ~= self then
            if ply:KeyDown(IN_SPEED) then
                self:SecondaryAttack()
            elseif ply:KeyDown(IN_DUCK) then
                self:HolsterReload()
            end
        elseif ply:KeyDown(IN_ATTACK2) then
            newVel = newVel + self:ReelIn()
            reeledIn = true
        end

        if not reeledIn and ply:KeyDown(IN_USE) then
            self:Rappel()
        end

        if not ply:IsOnGround() and (ply:KeyDown(IN_FORWARD) or ply:KeyDown(IN_BACK)) then
            newVel = newVel + self:Swing()
        end

        if not reeledIn and curDistance > self:GetTargetRopeDist() then
            newVel = newVel + self:PullOwner()
        elseif self:IsOwnerVaulting(curDistance) then
            if ply:GetActiveWeapon() == self then
                self:Reload()
            else
                self:HolsterReload()
            end

            local zVel = math.max(boostPower - ply:GetVelocity().z * 0.5, 0)
            newVel = newVel + Vector(0, 0, zVel)
        end

        ply:SetVelocity(newVel)
    end
end
