class OLTogetherGame extends OLGame;

static event class<GameInfo> SetGameType(string MapName, string Options, string Portal) 
{
    return Default.class;
}

DefaultProperties
{
    PlayerControllerClass=Class'Multiplayer.OLTogetherController'
    DefaultPawnClass=Class'Multiplayer.OLTogetherHero'
    HUDType=Class'Multiplayer.OLTogetherHUD'
}