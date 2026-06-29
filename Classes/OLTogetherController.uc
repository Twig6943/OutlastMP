class OLTogetherController extends OLPlayerController;

var OLTogetherLink NetworkLink;
var Pawn DummyPlayer;
var int MyRole;
var float LastSendTime;

// --- Dead Reckoning & Interpolation state ---
var vector LastReceivedLoc;
var vector LastReceivedVel;
var rotator LastReceivedRot;
var bool bHasReceivedData;

// --- Last known remote states (for change detection) ---
var bool bLastRemoteCrouched;
var bool bLastRemoteCamcorder;
var int LastRemoteCamcorderState;
var bool bDummyCrouched;

// How fast the dummy smoothly slides toward the target position.
var float InterpSpeed;

event PostBeginPlay()
{
    super.PostBeginPlay();
    MyRole = int(WorldInfo.Game.ParseOption(WorldInfo.GetLocalURL(), "Role"));
    NetworkLink = Spawn(class'OLTogetherLink', self);
    if (NetworkLink != None)
        NetworkLink.ControllerOwner = self;
}

event PlayerTick(float DeltaTime)
{
    local string Payload;
    local vector ExtrapolatedLoc, SmoothedLoc, AnimVel;
    local rotator SmoothedRot;
    local AIController AIC;

    super.PlayerTick(DeltaTime);

    // --- Send local player state ---
    if (NetworkLink != None && NetworkLink.bIsConnected && Pawn != None)
    {
        if (WorldInfo.TimeSeconds - LastSendTime > 0.05)
        {
            LastSendTime = WorldInfo.TimeSeconds;
            Payload = "LOC,"
                $ Pawn.Location.X $ "," $ Pawn.Location.Y $ "," $ Pawn.Location.Z $ ","
                $ Pawn.Rotation.Pitch $ "," $ Pawn.Rotation.Yaw $ ","
                $ Pawn.Velocity.X $ "," $ Pawn.Velocity.Y $ "," $ Pawn.Velocity.Z $ ","
                $ int(Pawn.bIsCrouched) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).bCamcorderDesired) : 0) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).CamcorderState) : 0);
            NetworkLink.SendText(Payload $ "\n");
        }
    }

    // --- Spawn dummy once ---
    if (DummyPlayer == None && Pawn != None)
    {
        DummyPlayer = Spawn(class'OLTogetherHero',,, Pawn.Location, Pawn.Rotation,, true);
        if (DummyPlayer != None)
        {
            DummyPlayer.SetPhysics(PHYS_Walking);
            DummyPlayer.SetCollision(true, true);
            DummyPlayer.bCollideWorld = false;

            // Use a plain AIController — safe, no crash, drives AnimTree locomotion
            AIC = Spawn(class'AIController');
            if (AIC != None)
                AIC.Possess(DummyPlayer, false);

            if (OLHero(DummyPlayer) != None)
            {
                // Hide the 1st-person mesh to prevent Z-fighting with the ShadowProxy.
                // We still keep it ticking invisibly so it drives the ShadowProxy AnimTree.
                if (OLHero(DummyPlayer).Mesh != None)
                {
                    OLHero(DummyPlayer).Mesh.SetHidden(true);
                    OLHero(DummyPlayer).Mesh.SetOwnerNoSee(true);
                    OLHero(DummyPlayer).Mesh.bUpdateSkelWhenNotRendered = true;
                    OLHero(DummyPlayer).Mesh.bTickAnimNodesWhenNotRendered = true;
                }
                // Make the 3rd-person shadow proxy visible
                if (OLHero(DummyPlayer).ShadowProxy != None)
                {
                    OLHero(DummyPlayer).ShadowProxy.SetOwnerNoSee(false);
                    OLHero(DummyPlayer).ShadowProxy.SetHidden(false);
                    OLHero(DummyPlayer).ShadowProxy.bUpdateSkelWhenNotRendered = true;
                    OLHero(DummyPlayer).ShadowProxy.bTickAnimNodesWhenNotRendered = true;
                }
                // Show the head on the other player.
                // ShadowProxy uses Miles_beheaded (no head) so HeadMeshComp attaches
                // cleanly to the neck bone with zero Z-fighting risk.
                if (OLHero(DummyPlayer).HeadMesh != None)
                {
                    OLHero(DummyPlayer).HeadMesh.SetHidden(false);
                    OLHero(DummyPlayer).HeadMesh.SetOwnerNoSee(false);
                }
                // Keep camcorder prop hidden until we receive the camcorder state
                if (OLHero(DummyPlayer).CameraMeshShadowProxy != None)
                    OLHero(DummyPlayer).CameraMeshShadowProxy.SetHidden(true);
            }
        }
    }

    // --- Dead Reckoning + Interpolation ---
    if (DummyPlayer != None && bHasReceivedData)
    {
        // Extrapolate position using last known velocity
        ExtrapolatedLoc = LastReceivedLoc;
        ExtrapolatedLoc.X += LastReceivedVel.X * DeltaTime;
        ExtrapolatedLoc.Y += LastReceivedVel.Y * DeltaTime;
        ExtrapolatedLoc.Z += LastReceivedVel.Z * DeltaTime;
        LastReceivedLoc = ExtrapolatedLoc;

        // Smoothly slide dummy toward extrapolated position
        SmoothedLoc = VInterpTo(DummyPlayer.Location, ExtrapolatedLoc, DeltaTime, InterpSpeed);
        DummyPlayer.SetLocation(SmoothedLoc);

        // Smooth rotation
        SmoothedRot = RInterpTo(DummyPlayer.Rotation, LastReceivedRot, DeltaTime, InterpSpeed);
        DummyPlayer.SetRotation(SmoothedRot);

        // Feed horizontal velocity to the AnimTree so locomotion plays correctly
        AnimVel = LastReceivedVel;
        AnimVel.Z = 0;
        DummyPlayer.Velocity = AnimVel;
        DummyPlayer.Acceleration = AnimVel;
    }
}

// Called via SetTimer to hide the camcorder prop after the lower animation finishes.
function HideCamcorderProp()
{
    local OLHero DummyHero;
    DummyHero = OLHero(DummyPlayer);
    if (DummyHero != None && DummyHero.CameraMeshShadowProxy != None)
        DummyHero.CameraMeshShadowProxy.SetHidden(true);
}

// Called via SetTimer after the raise animation finishes (0.6667s).
// Plays the camcorder hold-idle loop until the player lowers it.
function PlayCamcorderIdleAnim()
{
    local OLHero DummyHero;
    DummyHero = OLHero(DummyPlayer);
    if (DummyHero != None && DummyHero.ShadowProxyRightArmAnimSlot != None)
        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
            'player_camcorder_idle', 1.0, 0.05, -1.0, true, true);
}

// Called via SetTimer after the inactive reload animation finishes.
// Hides the camcorder prop and stops arm animations.
function FinishInactiveReload()
{
    local OLHero DummyHero;
    DummyHero = OLHero(DummyPlayer);
    if (DummyHero != None)
    {
        if (DummyHero.CameraMeshShadowProxy != None)
            DummyHero.CameraMeshShadowProxy.SetHidden(true);
        if (DummyHero.ShadowProxyRightArmAnimSlot != None)
            DummyHero.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
        if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
            DummyHero.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
    }
}

function OnReceiveData(string Data)
{
    local array<string> Parts;
    local vector NewLoc, NewVel;
    local rotator NewRot;
    local bool bNewCrouched, bNewCamcorder;
    local int NewCamcorderState;
    local OLHero DummyHero;

    Parts = SplitString(Data, ",", true);
    if (Parts.Length >= 12 && Parts[0] == "LOC")
    {
        NewLoc.X = float(Parts[1]);
        NewLoc.Y = float(Parts[2]);
        NewLoc.Z = float(Parts[3]);
        NewRot.Pitch = int(Parts[4]);
        NewRot.Yaw = int(Parts[5]);
        NewRot.Roll = 0;
        NewVel.X = float(Parts[6]);
        NewVel.Y = float(Parts[7]);
        NewVel.Z = float(Parts[8]);
        bNewCrouched = int(Parts[9]) != 0;
        bNewCamcorder = int(Parts[10]) != 0;
        NewCamcorderState = int(Parts[11]);

        LastReceivedLoc = NewLoc;
        LastReceivedVel = NewVel;
        LastReceivedRot = NewRot;
        bHasReceivedData = true;

        if (DummyPlayer != None)
        {
            DummyHero = OLHero(DummyPlayer);

            // --- Sync Crouch ---
            if (bNewCrouched != bLastRemoteCrouched)
            {
                bLastRemoteCrouched = bNewCrouched;
                bDummyCrouched = bNewCrouched;
                if (bNewCrouched)
                    DummyPlayer.ForceCrouch();
                else
                    DummyPlayer.UnCrouch();

                if (DummyHero != None)
                    DummyHero.ShadowProxy.PlayAnim(
                        bNewCrouched ? 'player_stand_to_crouch' : 'player_crouch_to_stand', 1.0, false, true);
            }

            // --- Sync Camcorder ---
            if (bNewCamcorder != bLastRemoteCamcorder)
            {
                bLastRemoteCamcorder = bNewCamcorder;
                DummyHero.bCamcorderDesired = bNewCamcorder;

                if (DummyHero.ShadowProxyRightArmAnimSlot != None)
                {
                    if (bNewCamcorder)
                    {
                        ClearTimer('HideCamcorderProp');
                        if (DummyHero.CameraMeshShadowProxy != None)
                            DummyHero.CameraMeshShadowProxy.SetHidden(false);
                        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_raise' : 'player_camcorder_raise', 1.0, 0.15, 0.15, false, true);
                        SetTimer(0.50, false, 'PlayCamcorderIdleAnim');
                    }
                    else
                    {
                        ClearTimer('PlayCamcorderIdleAnim');
                        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_lower' : 'player_camcorder_lower', 1.0, 0.15, 0.15, false, true);
                        SetTimer(0.55, false, 'HideCamcorderProp');
                    }
                }
            }

            // --- Sync Reloading ---
            if (NewCamcorderState != LastRemoteCamcorderState)
            {
                if (NewCamcorderState == 4)
                {
                    ClearTimer('PlayCamcorderIdleAnim');
                    ClearTimer('FinishInactiveReload');
                    if (DummyHero.ShadowProxyRightArmAnimSlot != None)
                        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload', 1.0, 0.15, 0.05, false, true);
                    if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
                        DummyHero.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload', 1.0, 0.15, 0.4, false, true);
                    SetTimer(2.85, false, 'PlayCamcorderIdleAnim');
                }
                else if (NewCamcorderState == 5)
                {
                    ClearTimer('PlayCamcorderIdleAnim');
                    ClearTimer('FinishInactiveReload');
                    if (DummyHero.CameraMeshShadowProxy != None)
                        DummyHero.CameraMeshShadowProxy.SetHidden(false);
                    if (DummyHero.ShadowProxyRightArmAnimSlot != None)
                        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_reload_inactive' : 'player_camcorder_reload_inactive', 1.0, 0.15, 0.05, false, true);
                    if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
                        DummyHero.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_reload_inactive' : 'player_camcorder_reload_inactive', 1.0, 0.15, 0.4, false, true);
                    SetTimer(2.85, false, 'FinishInactiveReload');
                }
                else if (LastRemoteCamcorderState == 4 || LastRemoteCamcorderState == 5)
                {
                    ClearTimer('PlayCamcorderIdleAnim');
                    ClearTimer('FinishInactiveReload');
                    if (NewCamcorderState == 1 && bNewCamcorder)
                    {
                        PlayCamcorderIdleAnim();
                        if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
                            DummyHero.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.2);
                    }
                    else
                    {
                        if (DummyHero.CameraMeshShadowProxy != None)
                            DummyHero.CameraMeshShadowProxy.SetHidden(true);
                        if (DummyHero.ShadowProxyRightArmAnimSlot != None)
                            DummyHero.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
                        if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
                            DummyHero.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
                    }
                }
                LastRemoteCamcorderState = NewCamcorderState;
            }
        }
    }
}

DefaultProperties
{
    bHasReceivedData=false
    InterpSpeed=12.0
    bLastRemoteCamcorder=false
    bLastRemoteCrouched=false
    LastRemoteCamcorderState=0
}
