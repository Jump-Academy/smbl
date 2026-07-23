#include <smbl/observable>

#define EVENT_IDENTIFIER_PREFIX	"Event."
#define EVENT_IDENTIFIER_OFFSET	6

enum struct _Observable {
	char sIdentifier[64];
	bool bEvent;
	Handle hPlugin;
	Function fnInit;
}

enum struct ObservationCallback {
	Handle hPlugin;
	Function fnObservation;
	any aData;
}

enum struct _Dispatcher {
	char sIdentifier[64];
	bool bEvent;
	Handle hPlugin;
	int iEntityRef;
	char sEntityKey[6];
	Handle hData;
	bool bGCFlag;
}

static StringMap m_hObservables;
static StringMap m_hObservedEntities;

static ArrayList m_hDispatchers;

// Natives

void SetupObservableNatives() {
	m_hObservables = new StringMap();
	m_hObservedEntities = new StringMap();

	m_hDispatchers = new ArrayList(sizeof(_Dispatcher));

	CreateNative("Dispatcher.Send",				Native_Dispatcher_Send);

	// Static

	CreateNative("Observable.Register",			Native_Observable_Register);
	CreateNative("Observable.Deregister",		Native_Observable_Deregister);

	CreateNative("Observable.RegisterEvent",	Native_Observable_RegisterEvent);
	CreateNative("Observable.DeregisterEvent",	Native_Observable_DeregisterEvent);

	CreateNative("Observable.Watch",			Native_Observable_Watch);
	CreateNative("Observable.Unwatch",			Native_Observable_Unwatch);

	CreateNative("Observable.WatchEvent",		Native_Observable_WatchEvent);
	CreateNative("Observable.UnwatchEvent",		Native_Observable_UnwatchEvent);

	CreateNative("Observable.Dispatch",			Native_Observable_Dispatch);
	CreateNative("Observable.DispatchEvent",	Native_Observable_DispatchEvent);
}

public any Native_Observable_Register(Handle hPlugin, int iArgC) {
	_Observable eObservable;
	eObservable.hPlugin = hPlugin;

	GetNativeString(1, eObservable.sIdentifier, sizeof(_Observable::sIdentifier));

	if (m_hObservables.ContainsKey(eObservable.sIdentifier)) {
		_Observable eExistingObservable;
		m_hObservables.GetArray(eObservable.sIdentifier, eExistingObservable, sizeof(_Observable));

		if (eExistingObservable.hPlugin != hPlugin) {
			ThrowError("Observable with this identifier is already registered: %s", eObservable.sIdentifier);
		}
	}

	// ObsInitFunc
	eObservable.fnInit = GetNativeFunction(2);

	if (m_hObservables.SetArray(eObservable.sIdentifier, eObservable, sizeof(_Observable))) {
		PrintToServer("[SMBL] Registered observable: %s", eObservable.sIdentifier);

		return true;
	}

	PrintToServer("[SMBL] Failed to register observable: %s", eObservable.sIdentifier);

	return false;
}

public any Native_Observable_Deregister(Handle hPlugin, int iArgC) {
	if (IsNativeParamNullString(1)) {
		DeregisterPluginObservables(hPlugin, true, false);
		return true;
	}

	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	_Observable eObservable;
	if (!m_hObservables.GetArray(eObservable.sIdentifier, eObservable, sizeof(_Observable))) {
		return false;
	}

	if (eObservable.hPlugin != hPlugin) {
		char sPluginName[64];
		GetPluginInfo(eObservable.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));

		ThrowError("Observable (%s) may only be deregistered from originating plugin: %s", sIdentifier, sPluginName);
	}

	StringMapSnapshot hObservedEntitiesSnapshot = m_hObservedEntities.Snapshot();

	char sEntityKey[6];
	for (int i=0; i<hObservedEntitiesSnapshot.Length; i++) {
		hObservedEntitiesSnapshot.GetKey(i, sEntityKey, sizeof(sEntityKey));

		StringMap hEntityObservables;
		m_hObservables.GetValue(sEntityKey, hEntityObservables);

		ArrayList hObservationCallbacks;
		if (hEntityObservables.GetValue(sIdentifier, hObservationCallbacks)) {
			delete hObservationCallbacks;
			hEntityObservables.Remove(sIdentifier);
		}
	}

	delete hObservedEntitiesSnapshot;

	m_hObservables.Remove(sIdentifier);

	return true;
}

public any Native_Observable_RegisterEvent(Handle hPlugin, int iArgC) {
	_Observable eObservable;
	eObservable.hPlugin = hPlugin;
	eObservable.sIdentifier = EVENT_IDENTIFIER_PREFIX;
	eObservable.bEvent = true;

	GetNativeString(1, eObservable.sIdentifier[EVENT_IDENTIFIER_OFFSET], sizeof(_Observable::sIdentifier)-EVENT_IDENTIFIER_OFFSET);

	if (m_hObservables.ContainsKey(eObservable.sIdentifier)) {
		_Observable eExistingObservable;
		m_hObservables.GetArray(eObservable.sIdentifier, eExistingObservable, sizeof(_Observable));

		if (eExistingObservable.hPlugin != hPlugin) {
			ThrowError("Observable event with this identifier is already registered: %s", eObservable.sIdentifier[EVENT_IDENTIFIER_OFFSET]);
		}
	}

	// ObsInitFunc
	eObservable.fnInit = GetNativeFunction(2);

	if (m_hObservables.SetArray(eObservable.sIdentifier, eObservable, sizeof(_Observable))) {
		PrintToServer("[SMBL] Registered observable event: %s", eObservable.sIdentifier[EVENT_IDENTIFIER_OFFSET]);

		return true;
	}

	PrintToServer("[SMBL] Failed to register observable event: %s", eObservable.sIdentifier[EVENT_IDENTIFIER_OFFSET]);

	return false;
}

public any Native_Observable_DeregisterEvent(Handle hPlugin, int iArgC) {
	if (IsNativeParamNullString(1)) {
		DeregisterPluginObservables(hPlugin, false, true);
		return true;
	}

	char sIdentifier[64] = EVENT_IDENTIFIER_PREFIX;
	GetNativeString(1, sIdentifier[EVENT_IDENTIFIER_OFFSET], sizeof(_Observable::sIdentifier)-EVENT_IDENTIFIER_OFFSET);

	Observable.Deregister(sIdentifier);
	_Observable eObservable;
	if (!m_hObservables.GetArray(eObservable.sIdentifier, eObservable, sizeof(_Observable))) {
		return false;
	}

	if (eObservable.hPlugin != hPlugin) {
		char sPluginName[64];
		GetPluginInfo(eObservable.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));

		ThrowError("Observable event (%s) may only be deregistered from originating plugin: %s", sIdentifier[EVENT_IDENTIFIER_OFFSET], sPluginName);
	}

	StringMapSnapshot hObservedEntitiesSnapshot = m_hObservedEntities.Snapshot();

	char sEntityKey[6];
	for (int i=0; i<hObservedEntitiesSnapshot.Length; i++) {
		hObservedEntitiesSnapshot.GetKey(i, sEntityKey, sizeof(sEntityKey));

		StringMap hEntityObservables;
		m_hObservables.GetValue(sEntityKey, hEntityObservables);

		ArrayList hObservationCallbacks;
		if (hEntityObservables.GetValue(sIdentifier, hObservationCallbacks)) {
			delete hObservationCallbacks;
			hEntityObservables.Remove(sIdentifier);
		}
	}

	delete hObservedEntitiesSnapshot;

	m_hObservables.Remove(sIdentifier);

	return true;
}

public any Native_Observable_Watch(Handle hPlugin, int iArgC) {
	int iEntity = GetNativeCell(1);
	if (iEntity < 0 || !IsValidEntity(iEntity)) {
		return false;
	}

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	Function fnObservation = GetNativeFunction(3);

	any aData = GetNativeCell(4);

	_Observable eObservable;
	if (!m_hObservables.GetArray(sIdentifier, eObservable, sizeof(_Observable))) {
		ThrowError("No Observable found with identifier: %s", sIdentifier);
	}

	int iEntityRef = EntIndexToEntRef(iEntity);

	char sEntityKey[6];
	PackCellToStr(iEntityRef, sEntityKey);

	StringMap hEntityObservables;
	if (!m_hObservables.GetValue(sEntityKey, hEntityObservables)) {
		hEntityObservables = new StringMap();
		m_hObservables.SetValue(sEntityKey, hEntityObservables);
	}

	ArrayList hObservationCallbacks;
	if (!hEntityObservables.GetValue(sIdentifier, hObservationCallbacks)) {
		hObservationCallbacks = new ArrayList(sizeof(ObservationCallback));
		hEntityObservables.SetValue(sIdentifier, hObservationCallbacks);
	}

	for (int i=0; i<hObservationCallbacks.Length; i++) {
		ObservationCallback eExistingObservationCallback;
		hObservationCallbacks.GetArray(i, eExistingObservationCallback);

		// Already watching
		if (eExistingObservationCallback.hPlugin == hPlugin && eExistingObservationCallback.fnObservation == fnObservation) {
			return true;
		}
	}

	ObservationCallback eObservationCallback;
	eObservationCallback.hPlugin = hPlugin;
	eObservationCallback.fnObservation = fnObservation;
	eObservationCallback.aData = aData;

	hObservationCallbacks.PushArray(eObservationCallback);

	if (eObservable.fnInit != INVALID_FUNCTION) {
		Call_StartFunction(hPlugin, eObservable.fnInit);
		Call_PushCell(iEntity);
		Call_PushCell(aData);
		Call_Finish();
	}

	return true;
}

public any Native_Observable_Unwatch(Handle hPlugin, int iArgC) {
	int iEntity = GetNativeCell(1);
	if (iEntity < 0 || !IsValidEntity(iEntity)) {
		return false;
	}

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	Function fnObservation = GetNativeFunction(3);

	if (!m_hObservables.ContainsKey(sIdentifier)) {
		ThrowError("No Observable found with identifier: %s", sIdentifier);
	}

	int iEntityRef = EntIndexToEntRef(iEntity);

	char sEntityKey[6];
	PackCellToStr(iEntityRef, sEntityKey);

	StringMap hEntityObservables;
	if (!m_hObservables.GetValue(sEntityKey, hEntityObservables)) {
		return false;
	}

	ArrayList hObservationCallbacks;
	if (!hEntityObservables.GetValue(sIdentifier, hObservationCallbacks)) {
		return false;
	}

	ObservationCallback eObservationCallback;
	for (int i=0; i<hObservationCallbacks.Length; i++) {
		hObservationCallbacks.GetArray(i, eObservationCallback);

		if (eObservationCallback.hPlugin == hPlugin && eObservationCallback.fnObservation == fnObservation) {
			hObservationCallbacks.Erase(i);
			return true;
		}
	}

	return false;
}

public any Native_Observable_WatchEvent(Handle hPlugin, int iArgC) {
	int iEntity = GetNativeCell(1);
	if (iEntity < 0 || !IsValidEntity(iEntity)) {
		return false;
	}

	char sIdentifier[64] = EVENT_IDENTIFIER_PREFIX;
	GetNativeString(2, sIdentifier[EVENT_IDENTIFIER_OFFSET], sizeof(_Observable::sIdentifier)-EVENT_IDENTIFIER_OFFSET);

	Function fnObservation = GetNativeFunction(3);

	any aData = GetNativeCell(4);

	_Observable eObservable;
	if (!m_hObservables.GetArray(sIdentifier, eObservable, sizeof(_Observable))) {
		ThrowError("No Observable events found with identifier: %s", sIdentifier[EVENT_IDENTIFIER_OFFSET]);
	}

	int iEntityRef = EntIndexToEntRef(iEntity);

	char sEntityKey[6];
	PackCellToStr(iEntityRef, sEntityKey);

	StringMap hEntityObservables;
	if (!m_hObservables.GetValue(sEntityKey, hEntityObservables)) {
		hEntityObservables = new StringMap();
		m_hObservables.SetValue(sEntityKey, hEntityObservables);
	}

	ArrayList hObservationCallbacks;
	if (!hEntityObservables.GetValue(sIdentifier, hObservationCallbacks)) {
		hObservationCallbacks = new ArrayList(sizeof(ObservationCallback));
		hEntityObservables.SetValue(sIdentifier, hObservationCallbacks);
	}

	for (int i=0; i<hObservationCallbacks.Length; i++) {
		ObservationCallback eExistingObservationCallback;
		hObservationCallbacks.GetArray(i, eExistingObservationCallback);

		// Already watching
		if (eExistingObservationCallback.hPlugin == hPlugin && eExistingObservationCallback.fnObservation == fnObservation) {
			return true;
		}
	}

	ObservationCallback eObservationCallback;
	eObservationCallback.hPlugin = hPlugin;
	eObservationCallback.fnObservation = fnObservation;
	eObservationCallback.aData = aData;

	hObservationCallbacks.PushArray(eObservationCallback);

	if (eObservable.fnInit != INVALID_FUNCTION) {
		Call_StartFunction(hPlugin, eObservable.fnInit);
		Call_PushCell(iEntity);
		Call_PushCell(aData);
		Call_Finish();
	}

	return true;
}

public any Native_Observable_UnwatchEvent(Handle hPlugin, int iArgC) {
	int iEntity = GetNativeCell(1);
	if (iEntity < 0 || !IsValidEntity(iEntity)) {
		return false;
	}

	char sIdentifier[64] = EVENT_IDENTIFIER_PREFIX;
	GetNativeString(2, sIdentifier[EVENT_IDENTIFIER_OFFSET], sizeof(_Observable::sIdentifier)-EVENT_IDENTIFIER_OFFSET);

	Function fnObservation = GetNativeFunction(3);

	if (!m_hObservables.ContainsKey(sIdentifier)) {
		ThrowError("No Observable event found with identifier: %s", sIdentifier[EVENT_IDENTIFIER_OFFSET]);
	}

	int iEntityRef = EntIndexToEntRef(iEntity);

	char sEntityKey[6];
	PackCellToStr(iEntityRef, sEntityKey);

	StringMap hEntityObservables;
	if (!m_hObservables.GetValue(sEntityKey, hEntityObservables)) {
		return false;
	}

	ArrayList hObservationCallbacks;
	if (!hEntityObservables.GetValue(sIdentifier, hObservationCallbacks)) {
		return false;
	}

	ObservationCallback eObservationCallback;
	for (int i=0; i<hObservationCallbacks.Length; i++) {
		hObservationCallbacks.GetArray(i, eObservationCallback);

		if (eObservationCallback.hPlugin == hPlugin && eObservationCallback.fnObservation == fnObservation) {
			hObservationCallbacks.Erase(i);
			return true;
		}
	}

	return false;
}

public any Native_Observable_Dispatch(Handle hPlugin, int iArgC) {
	int iEntity = GetNativeCell(1);
	if (!IsValidEntity(iEntity)) {
		return NULL_DISPATCHER;
	}

	int iEntityRef = EntIndexToEntRef(iEntity);

	char sEntityKey[6];
	PackCellToStr(iEntityRef, sEntityKey);

	StringMap hEntityObservables;
	if (!m_hObservables.GetValue(sEntityKey, hEntityObservables)) {
		return NULL_DISPATCHER;
	}

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	if (!hEntityObservables.ContainsKey(sIdentifier)) {
		return NULL_DISPATCHER;
	}

	_Dispatcher eDispatcher;
	eDispatcher.sIdentifier = sIdentifier;
	eDispatcher.iEntityRef = iEntityRef;
	eDispatcher.sEntityKey = sEntityKey;
	eDispatcher.hData = new KeyValues(sIdentifier);

	Dispatcher mDispatcher;
	int iFreeIdx = m_hDispatchers.FindValue(true, _Dispatcher::bGCFlag);
	if (iFreeIdx != -1) {
		m_hDispatchers.SetArray(iFreeIdx, eDispatcher);

		mDispatcher = view_as<Dispatcher>(iFreeIdx+1);
	} else {
		mDispatcher = view_as<Dispatcher>(m_hDispatchers.PushArray(eDispatcher)+1);
	}

	SetNativeCellRef(3, eDispatcher.hData);

	return mDispatcher;
}

public any Native_Observable_DispatchEvent(Handle hPlugin, int iArgC) {
	int iEntity = GetNativeCell(1);
	if (!IsValidEntity(iEntity)) {
		return NULL_DISPATCHER;
	}

	int iEntityRef = EntIndexToEntRef(iEntity);

	char sEntityKey[6];
	PackCellToStr(iEntityRef, sEntityKey);

	StringMap hEntityObservables;
	if (!m_hObservables.GetValue(sEntityKey, hEntityObservables)) {
		return NULL_DISPATCHER;
	}

	char sIdentifier[64] = EVENT_IDENTIFIER_PREFIX;
	GetNativeString(2, sIdentifier[EVENT_IDENTIFIER_OFFSET], sizeof(_Observable::sIdentifier)-EVENT_IDENTIFIER_OFFSET);

	if (!hEntityObservables.ContainsKey(sIdentifier)) {
		return NULL_DISPATCHER;
	}

	_Dispatcher eDispatcher;
	eDispatcher.sIdentifier = sIdentifier;
	eDispatcher.bEvent = true;
	eDispatcher.iEntityRef = iEntityRef;
	eDispatcher.sEntityKey = sEntityKey;
	eDispatcher.hData = new KeyValues(sIdentifier);

	Dispatcher mDispatcher;
	int iFreeIdx = m_hDispatchers.FindValue(true, _Dispatcher::bGCFlag);
	if (iFreeIdx != -1) {
		m_hDispatchers.SetArray(iFreeIdx, eDispatcher);

		mDispatcher = view_as<Dispatcher>(iFreeIdx+1);
	} else {
		mDispatcher = view_as<Dispatcher>(m_hDispatchers.PushArray(eDispatcher)+1);
	}

	return mDispatcher;
}

public int Native_Dispatcher_Send(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	if (iThis < 0 || iThis >= m_hDispatchers.Length) {
		return 0;
	}

	_Dispatcher eDispatcher;
	m_hDispatchers.GetArray(iThis, eDispatcher);

	if (eDispatcher.bGCFlag) {
		return 0;
	}

	int iEntity = EntRefToEntIndex(eDispatcher.iEntityRef);
	if (iEntity == INVALID_ENT_REFERENCE) {
		delete eDispatcher.hData;
		return 0;
	}

	StringMap hEntityObservables;
	if (!m_hObservables.GetValue(eDispatcher.sEntityKey, hEntityObservables)) {
		delete eDispatcher.hData;
		return 0;
	}

	ArrayList hObservationCallbacks;
	if (!hEntityObservables.GetValue(eDispatcher.sIdentifier, hObservationCallbacks)) {
		delete eDispatcher.hData;
		return 0;
	}

	ObservationCallback eObservationCallback;
	for (int i=0; i<hObservationCallbacks.Length; i++) {
		hObservationCallbacks.GetArray(i, eObservationCallback);

		Call_StartFunction(eObservationCallback.hPlugin, eObservationCallback.fnObservation);
		Call_PushCell(iEntity);
		Call_PushCell(eDispatcher.hData);
		Call_PushCell(eObservationCallback.aData);
		Call_Finish();
	}

	if (!eDispatcher.bEvent) {
		delete eDispatcher.hData;
	}

	m_hDispatchers.Set(iThis, true, _Dispatcher::bGCFlag);

	if (iThis == m_hDispatchers.Length-1) {
		for (int i=iThis; i>0; i--) {
			if (!m_hDispatchers.Get(i-1, _Dispatcher::bGCFlag)) {
				m_hDispatchers.Resize(i);
				return 0;
			}
		}

		m_hDispatchers.Clear();
	}

	return 0;
}

// Helpers

void DeregisterPluginObservables(Handle hPlugin, bool bNormal=true, bool bEvents=true) {
	ArrayList hObservableIdentifiers = new ArrayList(ByteCountToCells(64));

	StringMapSnapshot hObservablesSnapshot = m_hObservables.Snapshot();

	_Observable eObservable;

	char sIdentifier[64];
	for (int i=0; i<hObservablesSnapshot.Length; i++) {
		hObservablesSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));

		if (m_hObservables.GetArray(sIdentifier, eObservable, sizeof(_Observable)) && eObservable.hPlugin == hPlugin) {
			if (eObservable.bEvent && bEvents || !eObservable.bEvent && bNormal) {
				hObservableIdentifiers.PushString(sIdentifier);
				m_hObservables.Remove(sIdentifier);
			}
		}
	}

	delete hObservablesSnapshot;

	if (!hObservableIdentifiers.Length) {
		delete hObservableIdentifiers;
		return;
	}

	for (int i=0; i<m_hDispatchers.Length; i++) {
		_Dispatcher eDispatcher;
		m_hDispatchers.GetArray(i, eDispatcher);

		if (eDispatcher.hPlugin == hPlugin && hObservableIdentifiers.FindString(eDispatcher.sIdentifier) != -1) {
			if (!eDispatcher.bEvent) {
				delete eDispatcher.hData;
			}

			m_hDispatchers.Erase(i--);
		}
	}

	StringMapSnapshot hObservedEntitiesSnapshot = m_hObservedEntities.Snapshot();

	char sEntityKey[6];
	for (int i=0; i<hObservedEntitiesSnapshot.Length; i++) {
		hObservedEntitiesSnapshot.GetKey(i, sEntityKey, sizeof(sEntityKey));

		StringMap hEntityObservables;
		m_hObservables.GetValue(sEntityKey, hEntityObservables);

		for (int j=0; j<hObservableIdentifiers.Length; j++) {
			hObservableIdentifiers.GetString(j, sIdentifier, sizeof(sIdentifier));

			ArrayList hObservationCallbacks;
			if (hEntityObservables.GetValue(sIdentifier, hObservationCallbacks)) {
				delete hObservationCallbacks;
				hEntityObservables.Remove(sIdentifier);
			}
		}

		StringMapSnapshot hEntityObservablesSnapshot = hEntityObservables.Snapshot();

		for (int j=0; j<hEntityObservablesSnapshot.Length; j++) {
			hEntityObservablesSnapshot.GetKey(j, sIdentifier, sizeof(sIdentifier));

			ArrayList hObservationCallbacks;
			hEntityObservables.GetValue(sIdentifier, hObservationCallbacks);

			for (int k=0; k<hObservationCallbacks.Length; k++) {
				if (hObservationCallbacks.Get(k, ObservationCallback::hPlugin) == hPlugin) {
					hObservationCallbacks.Erase(k--);
				}
			}

			delete hObservationCallbacks;
		}

		delete hEntityObservablesSnapshot;
	}

	delete hObservedEntitiesSnapshot;

	delete hObservableIdentifiers;
}

void UnwatchObservableEntity(int iEntity) {
	int iEntityRef = EntIndexToEntRef(iEntity);

	char sEntityKey[6];
	PackCellToStr(iEntityRef, sEntityKey);

	char sIdentifier[64];

	StringMap hEntityObservables;
	if (m_hObservables.GetValue(sEntityKey, hEntityObservables)) {
		StringMapSnapshot hEntityObservablesSnapshot = hEntityObservables.Snapshot();

		for (int i=0; i<hEntityObservablesSnapshot.Length; i++) {
			hEntityObservablesSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));

			ArrayList hObservationCallbacks;
			hEntityObservables.GetValue(sIdentifier, hObservationCallbacks);

			delete hObservationCallbacks;
		}

		delete hEntityObservablesSnapshot;

		delete hEntityObservables;

		m_hObservables.Remove(sEntityKey);
	}
}
