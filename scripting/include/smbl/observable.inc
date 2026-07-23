methodmap Observable {
	public static native bool Register(char[] sIdentifier, ObsInitFunc fnObsInit=INVALID_FUNCTION);
	public static native bool RegisterEvent(char[] sIdentifier, ObsInitFunc fnObsInit=INVALID_FUNCTION);
	public static native bool Deregister(char[] sIdentifier);

	public static native bool Watch(int iEntity, char[] sIdentifier, Observation fnObservation, any aData=0);
	public static native bool Unwatch(int iEntity, char[] sIdentifier, Observation fnObservation);

	public static native bool WatchEvent(int iEntity, char[] sIdentifier, EventObservation fnObservation, any aData=0);
// 	public static native bool WatchEventKey(int iEntity, char[] sIdentifier, char[] sKey, EventObservation fnObservation, any aData=0);
	public static native bool UnwatchEvent(int iEntity, char[] sIdentifier, EventObservation fnObservation);

	public static native Dispatcher Dispatch(int iEntity, char[] sIdentifier, KeyValues &hObsData=null);
	public static native Dispatcher DispatchEvent(int iEntity, const char[] sIdentifier, Event hEvent);
}

methodmap Dispatcher {
	public native void Send();
}

typedef ObsInitFunc = function void (int iEntity, any aData);

typedef Observation = function void (int iEntity, KeyValues hObsData, any aData);
typedef EventObservation = function void (int iEntity, Event hEvent, any aData);

#define NULL_DISPATCHER	view_as<Dispatcher>(0)
