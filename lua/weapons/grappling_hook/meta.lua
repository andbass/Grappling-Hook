
AddCSLuaFile()

SWEP.PrintName             = "Grappling Hook"
SWEP.Author                = "Glenie"
SWEP.Instructions          = [[
    Left Click to launch the grapple hook.

    Press Reload to bring it back in.

    When the hook latches onto a surface, Right Click to pull yourself towards the hook.  Use to extend the rope and rappel.
    If you pulled yourself all the way to the attached hook, press Jump to give yourself a boost up a surface and onto a ledge.
]]

SWEP.Spawnable             = true
SWEP.AdminOnly             = false

SWEP.Primary.ClipSize      = -1
SWEP.Primary.DefaultClip   = -1
SWEP.Primary.Automatic     = false
SWEP.Primary.Ammo          = "none"

SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = true
SWEP.Secondary.Ammo        = "none"

SWEP.Weight                = 5
SWEP.AutoSwitchTo          = false
SWEP.AutoSwitchFrom        = false

SWEP.Slot                  = 1
SWEP.SlotPos               = 5
SWEP.DrawAmmo              = false
SWEP.DrawCrosshair         = true

SWEP.UseHands              = true
SWEP.ViewModel             = "models/weapons/c_crossbow.mdl"
SWEP.WorldModel            = "models/weapons/w_crossbow.mdl"
