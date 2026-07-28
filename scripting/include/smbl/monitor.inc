enum struct MonData {
	any aData[32];
}

methodmap Monitor {
	public native void Start();

	public static native bool Register(char[] sIdentifier, Function fnMonInit, Function fnMonThink=INVALID_FUNCTION, Function fnMonCleanup=INVALID_FUNCTION); // MonInitFunc, MonThinkFunc, MonCleanupFunc
	public static native bool Deregister(char[] sIdentifier);
}

typedef MonInitFunc = function void (Controller mContr, KeyValues hInitParams, MonData eMonData, float &fThinkInterval);
typedef MonThinkFunc = function void (Controller mContr, MonData eMonData, float &fThinkInterval);
typedef MonCleanupFunc = function void (Controller mContr, MonData eMonData);

#define NULL_MONITOR	view_as<Monitor>(0)
