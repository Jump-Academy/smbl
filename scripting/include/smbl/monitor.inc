enum struct MonData {
	any aData[32];
}

methodmap Monitor {
	public native void Start();

	public static native bool Register(char[] sIdentifier, MonInitFunc fnMonInit, MonThinkFunc fnMonThink=INVALID_FUNCTION, MonCleanupFunc fnMonCleanup=INVALID_FUNCTION);
	public static native bool Deregister(char[] sIdentifier);
}

typedef MonInitFunc = function void (Controller mContr, KeyValues hInitParams, MonData eMonData, float &fThinkInterval);
typedef MonThinkFunc = function void (Controller mContr, MonData eMonData, float &fThinkInterval);
typedef MonCleanupFunc = function void (Controller mContr, MonData eMonData);

#define NULL_MONITOR	view_as<Monitor>(0)
