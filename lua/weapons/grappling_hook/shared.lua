
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
local swingSpeed  = 15
local reloadSpeed = 1.7

local inAirGrappleStrength    = 15
local onGroundGrappleStrength = 50

local reelInSpeed = 4
local rappelSpeed = 3

function SWEP:SetupDataTables()
    self:NetworkVar("Entity", 0, "Hook")
end

function SWEP:Initialize()
    self:SetWeaponHoldType("crossbow")
    self:Cleanup()
end

function SWEP:CanPrimaryAttack()
    return not IsValid(self.hook)
end

function SWEP:PrimaryAttack()
    if not self:CanPrimaryAttack() then return end

    self:EmitSound(fireSound)
    self:ShootEffects()
    self.Owner:GetViewModel():SetPlaybackRate(1)

    if CLIENT then return end

    self:CreateHook()
end

function SWEP:CanSecondaryAttack()
    return IsValid(self.hook) and self.hookAttached
end

function SWEP:SecondaryAttack()
    if not self:CanSecondaryAttack() then return end

    self.targetRopeDistance = math.max(self.targetRopeDistance - reelInSpeed, 50)

    local ply = self.Owner
    local plyPos = ply:GetPos()

    local playerToHookDir = self.hook:GetPos() - plyPos
    if playerToHookDir.z > 0 and ply:IsOnGround() then -- Give player slight boost to get off ground, if they're ascending
        plyPos.z = plyPos.z + 1
        ply:SetPos(plyPos)
    end

    self:PullOwner()
end

function SWEP:Cleanup()
    self.hookAttached = false

    if IsValid(self.hook) then 
        self.hook:Remove() 
        self.hook = nil
    end

    if IsValid(self.rope) then 
        self.rope:Remove() 
        self.rope = nil
    end
end

function SWEP:Reload()
    if not IsValid(self:GetHook()) then return end

    self:EmitSound(hookReleaseSound)

    self.Owner:SetAnimation(PLAYER_RELOAD)
    self:SendWeaponAnim(ACT_VM_RELOAD)

    self.Owner:GetViewModel():SetPlaybackRate(reloadSpeed)
    local animTime = self.Owner:GetViewModel():SequenceDuration() / (reloadSpeed + 2)

    self.reloadingTime = CurTime() + animTime
    self:SetNextPrimaryFire(self.reloadingTime)

    if SERVER then self:Cleanup() end
end

function SWEP:OnRemove()
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

    self.hook = ent
    self:SetHook(self.hook)
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
    if self.hookAttached then return end

    sound.Play(table.Random(hookContactSounds), data.HitPos, 150, 100, 1)

    self.collideData = data

    self:AttachHook()
    self:CreateEffect()
end

function SWEP:AttachHook()
    local data = self.collideData

    self.hook:GetPhysicsObject():EnableMotion(false)
    self.hook:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

    self.Owner:ViewPunch(Angle(-2, 0, 0))
    
    -- Push in hook into surface
    local impactDir = data.OurOldVelocity
    impactDir:Normalize()

    local cosBetween = math.abs(impactDir:Dot(data.HitNormal))
    local pushAmount = 12 + 2 * (1 - cosBetween)

    local newPos = data.HitPos - impactDir * pushAmount
    self.hook:SetPos(newPos)

    if not data.HitEntity:IsWorld() then
        self.hook:SetMoveType(MOVETYPE_NONE)
        self.hook:SetParent(data.HitEntity)

        local hookPhys = self.hook:GetPhysicsObject()
        hookPhys:EnableMotion(true)
    end

    local initialTug = 20
    local upwardness = math.max(impactDir:Dot(Vector(0, 0, 1)), 0)
    local tug = initialTug + 10 * upwardness

    self.targetRopeDistance = self.hook:GetPos():Distance(self.Owner:GetPos()) - tug

    self.hookAttached = true
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
    self.targetRopeDistance = self.targetRopeDistance + rappelSpeed
end

function SWEP:Swing()
    local ply = self.Owner

    local multiplier = swingSpeed
    if ply:KeyDown(IN_BACK) then multiplier = -multiplier end

    local playerToHookDir = self.hook:GetPos() - ply:GetPos()
    playerToHookDir:Normalize()

    local swingDir = playerToHookDir:Cross(ply:GetRight())
    swingDir:Normalize()

    ply:SetVelocity(swingDir * multiplier)
end

function SWEP:PullOwner()
    if not IsValid(self.hook) then return end

    local ply = self.Owner
    local playerToHookDir = self.hook:GetPos() - ply:GetPos()

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

    ply:SetVelocity(vel)
end

function SWEP:Think()
    local ply = self.Owner

    if not IsValid(self.hook) then
        self.hookAttached = false
        return
    elseif self.hookAttached then
        if ply:KeyDown(IN_USE) then
            self:Rappel()
        end

        if not ply:IsOnGround() and (ply:KeyDown(IN_FORWARD) or ply:KeyDown(IN_BACK)) then
            self:Swing()
        end

        local curDistance = ply:GetPos():Distance(self.hook:GetPos())
        if curDistance > self.targetRopeDistance then
            self:PullOwner()
        else
            if curDistance < 100 and ply:KeyDown(IN_JUMP) and not ply:IsOnGround() then
                self:Reload()

                local zVel = math.max(boostPower - ply:GetVelocity().z * 0.5, 0)
                ply:SetVelocity(Vector(0, 0, zVel))
            end
        end
    end
end
