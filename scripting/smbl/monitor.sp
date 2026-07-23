#include <smbl/monitor>

enum struct MonitorTemplate {
	char sIdentifier[64];
	Handle hPlugin;
	Function fnInit;
	Function fnThink;
	Function fnCleanup;
}

enum struct _Monitor {
	char sIdentifier[64];
	Handle hPlugin;
	KeyValues hInitParams;
	Controller mContr;

	Handle hTimer;
	float fTimerInterval;

	MonData eMonData;

	Function fnInit;
	Function fnThink;
	Function fnCleanup;

	bool bGCFlag;
}

static StringMap m_hMonitorTemplates;
static ArrayList m_hMonitors;

void SetupMonitorNatives() {
	m_hMonitorTemplates = new StringMap();
	m_hMonitors = new ArrayList(sizeof(_Monitor));

	CreateNative("Monitor.Start",			Native_Monitor_Start);

	// Static

	CreateNative("Monitor.Register",		Native_Monitor_Register);
	CreateNative("Monitor.Deregister",		Native_Monitor_Deregister);
}

public int Native_Monitor_Start(Handle hPlugin, int iArgC) {
	Monitor mMon = GetNativeCell(1);

	int iThis = view_as<int>(mMon)-1;
	if (iThis < 0 || iThis >= m_hMonitors.Length) {
		return 0;
	}

	_Monitor eMon;
	m_hMonitors.GetArray(iThis, eMon);

	if (eMon.bGCFlag) {
		return 0;
	}

	eMon.hInitParams.Rewind();

	Call_StartFunction(eMon.hPlugin, eMon.fnInit);
	Call_PushCell(eMon.mContr);
	Call_PushCell(eMon.hInitParams);
	Call_PushArrayEx(eMon.eMonData, sizeof(MonData), SM_PARAM_COPYBACK);
	Call_PushCellRef(eMon.fTimerInterval);

	int iCallError = Call_Finish();
	if (iCallError == SP_ERROR_NONE) {
		eMon.fTimerInterval = eMon.fTimerInterval < 0 ? 0.0 : eMon.fTimerInterval;

		if (eMon.fnThink != INVALID_FUNCTION && eMon.fTimerInterval > 0) {
			eMon.hTimer = CreateTimer(eMon.fTimerInterval, Timer_MonThink, mMon, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}

		m_hMonitors.SetArray(iThis, eMon);
	}

	return 0;
}

public int Native_Monitor_Register(Handle hPlugin, int iArgC) {
	MonitorTemplate eMonitorTemplate;
	eMonitorTemplate.hPlugin = hPlugin;

	GetNativeString(1, eMonitorTemplate.sIdentifier, sizeof(MonitorTemplate::sIdentifier));

	if (m_hMonitorTemplates.ContainsKey(eMonitorTemplate.sIdentifier)) {
		MonitorTemplate eExistingMonitorTemplate;
		m_hMonitorTemplates.GetArray(eMonitorTemplate.sIdentifier, eExistingMonitorTemplate, sizeof(MonitorTemplate));

		if (eExistingMonitorTemplate.hPlugin != hPlugin) {
			ThrowError("Monitor with this identifier is already registered: %s", eExistingMonitorTemplate.sIdentifier);
		}
	}

	eMonitorTemplate.fnInit = GetNativeFunction(2);
	eMonitorTemplate.fnThink = GetNativeFunction(3);
	eMonitorTemplate.fnCleanup = GetNativeFunction(4);

	if (m_hMonitorTemplates.SetArray(eMonitorTemplate.sIdentifier, eMonitorTemplate, sizeof(MonitorTemplate), false)) {
		PrintToServer("[SMBL] Registered monitor: %s", eMonitorTemplate.sIdentifier);

		return 0;
	}

	PrintToServer("[SMBL] Failed to register monitor (duplicate?): %s", eMonitorTemplate.sIdentifier);

	return 0;
}

public any Native_Monitor_Deregister(Handle hPlugin, int iArgC) {
	if (IsNativeParamNullString(1)) {
		DeregisterPluginMonitors(hPlugin);
		return true;
	}

	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	MonitorTemplate eMonitorTemplate;
	if (m_hMonitorTemplates.GetArray(sIdentifier, eMonitorTemplate, sizeof(MonitorTemplate))) {
		if (eMonitorTemplate.hPlugin != hPlugin) {
			char sPluginName[64];
			GetPluginInfo(eMonitorTemplate.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
			ThrowError("Monitor (%s) may only be deregistered from originating plugin: %s", sIdentifier, sPluginName);
		}

		DestroyDeregisteredMonitors(sIdentifier);

		m_hMonitorTemplates.Remove(sIdentifier);

		return true;
	}

	return false;
}

// Timers

public Action Timer_MonThink(Handle hTimer, Monitor mMon) {
	int iThis = view_as<int>(mMon)-1;
	if (iThis < 0 || iThis >= m_hMonitors.Length) {
		return Plugin_Stop;
	}

	_Monitor eMon;
	m_hMonitors.GetArray(iThis, eMon);

	if (eMon.bGCFlag) {
		return Plugin_Stop;
	}

	float fTimerInterval = eMon.fTimerInterval;

	Call_StartFunction(eMon.hPlugin, eMon.fnThink);
	Call_PushCell(eMon.mContr);
	Call_PushArray(eMon.eMonData, sizeof(MonData));
	Call_PushCellRef(fTimerInterval);
	
	int iCallError = Call_Finish();
	if (iCallError == SP_ERROR_NONE) {
		// Flag to self-remove monitor
		if (fTimerInterval <= 0) {
			eMon.hTimer = null;
			m_hMonitors.SetArray(iThis, eMon);

			eMon.mContr.RemoveMonitor(eMon.sIdentifier);

			return Plugin_Stop;
		}

		// Recreate timer to change interval between MonThinkFunc calls
		if (fTimerInterval != eMon.fTimerInterval) {
			eMon.hTimer = CreateTimer(fTimerInterval, Timer_MonThink, mMon, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			eMon.fTimerInterval = fTimerInterval;
			m_hMonitors.SetArray(iThis, eMon);

			return Plugin_Stop;
		}

		m_hMonitors.SetArray(iThis, eMon);
	}

	return Plugin_Continue;
}

// Helpers

void DeregisterPluginMonitors(Handle hPlugin) {
	StringMapSnapshot hMonitorTemplatesSnapshot = m_hMonitorTemplates.Snapshot();

	char sIdentifier[64];
	MonitorTemplate eMonitorTemplate;

	for (int i=0; i<hMonitorTemplatesSnapshot.Length; i++) {
		hMonitorTemplatesSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));

		if (m_hMonitorTemplates.GetArray(sIdentifier, eMonitorTemplate, sizeof(MonitorTemplate)) && eMonitorTemplate.hPlugin == hPlugin) {
			DestroyDeregisteredMonitors(sIdentifier);

			m_hMonitorTemplates.Remove(sIdentifier);

			PrintToServer("[SMBL] Deregistered monitor: %s", eMonitorTemplate.sIdentifier);
		}
	}

	delete hMonitorTemplatesSnapshot;
}

void DestroyDeregisteredMonitors(char[] sTemplateIdentifier) {
	char sIdentifier[64];
	for (int i=0; i<m_hMonitors.Length; i++) {
		if (m_hMonitors.Get(i, _Monitor::bGCFlag)) {
			continue;
		}

		m_hMonitors.GetString(i, sIdentifier, sizeof(sIdentifier));
		if (StrEqual(sIdentifier, sTemplateIdentifier)) {
			CleanupMonitor(view_as<Monitor>(i+1));
		}
	}
}

Monitor CreateMonitor(char sIdentifier[64], Controller mContr, KeyValues hInitParams) {
	MonitorTemplate eMonitorTemplate;
	if (m_hMonitorTemplates.GetArray(sIdentifier, eMonitorTemplate, sizeof(MonitorTemplate))) {
		_Monitor eMon;
		eMon.sIdentifier = sIdentifier;
		eMon.hPlugin = eMonitorTemplate.hPlugin;
		eMon.hInitParams = hInitParams;
		eMon.mContr = mContr;
		eMon.fnInit = eMonitorTemplate.fnInit;
		eMon.fnThink = eMonitorTemplate.fnThink;
		eMon.fnCleanup = eMonitorTemplate.fnCleanup;

		Monitor mMon;
		int iFreeIdx = m_hMonitors.FindValue(true, _Monitor::bGCFlag);
		if (iFreeIdx != -1) {
			m_hMonitors.SetArray(iFreeIdx, eMon);

			mMon = view_as<Monitor>(iFreeIdx+1);
		} else {
			mMon = view_as<Monitor>(m_hMonitors.PushArray(eMon)+1);
		}

		return mMon;
	}

	LogError("No Monitor templates found with identifier: %s", sIdentifier);

	return NULL_MONITOR;
}

void CleanupMonitor(Monitor mMon) {
	int iThis = view_as<int>(mMon)-1;
	if (iThis < 0 || iThis >= m_hMonitors.Length) {
		return;
	}

	_Monitor eMon;
	m_hMonitors.GetArray(iThis, eMon);

	if (eMon.bGCFlag) {
		return;
	}

	Call_StartFunction(eMon.hPlugin, eMon.fnCleanup);
	Call_PushCell(eMon.mContr);
	Call_PushArray(eMon.eMonData, sizeof(MonData));
	Call_Finish();

	delete eMon.hTimer;
	delete eMon.hInitParams;

	if (iThis == m_hMonitors.Length-1) {
		for (int i=iThis; i>0; i--) {
			if (!m_hMonitors.Get(i-1, _Monitor::bGCFlag)) {
				m_hMonitors.Resize(i);
				return;
			}
		}

		m_hMonitors.Clear();
	}
}
