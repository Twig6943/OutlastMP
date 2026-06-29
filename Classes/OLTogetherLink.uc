class OLTogetherLink extends TcpLink;

var OLTogetherController ControllerOwner;
var bool bIsConnected;

event PostBeginPlay()
{
    super.PostBeginPlay();
    LinkMode = MODE_Line;
    ReceiveMode = RMODE_Event;
    Resolve("127.0.0.1");
}

event Resolved(IpAddr Addr)
{
    Addr.Port = 7777;
    BindPort();
    Open(Addr);
}

event Opened()
{
    bIsConnected = true;
    `log("OLTogetherLink Connected to Server!");
}

event Closed()
{
    bIsConnected = false;
    `log("OLTogetherLink Disconnected.");
}

event ReceivedLine(string Line)
{
    if (ControllerOwner != None)
    {
        ControllerOwner.OnReceiveData(Line);
    }
}
