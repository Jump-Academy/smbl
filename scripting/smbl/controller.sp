#include <smbl/controller>
#include <smbl/monitor>

#define PROCESSOR_OPERATION		"Processor"
#define PROCESS_NOOP			"Process.NoOp"

#define CONTROLLER_TICK_INTERVAL	0.5
#define MSGBOX_CLEANUP_INTERVAL		5.0

enum struct ControllerTemplate {
	char sIdentifier[64];
	Handle hPlugin;
	Function fnInit;
	TFClassType iClassType;
}

enum struct _Controller {
	char sIdentifier[64];
	Handle hPlugin;
	Function fnInit;
	TFClassType iClassType;
	ArrayList hActions[ACTIONTYPE_LENGTH];
	OpRef mProcessorOpRef;
	OpRef mActiveProcessOpRef;
	Bot mBot;
	StringMap hMonitors;
	StringMap hMsgBoxes;
	Handle hMsgBoxCleanupTimer;
	bool bGCFlag;
}

enum struct ControllerAction {
	char sIdentifier[64];
	float fWeight;
	float fWeightCSum;
}

enum struct Process {
	Controller mContr;
	OpRef mProcessOpRef;
	OpRef mActionOpRef;
	ProcessPriority iPriority;
}

enum struct ContrMsg {
	ContrMsgData eContrMsgData;
	float fExpiry;
}

static StringMap m_hClientControllers[TFClassType];

static StringMap m_hControllerTemplates;
static ArrayList m_hControllers;

static StringMap m_hProcesses;

// Natives

void SetupControllerNatives() {
	m_hControllerTemplates = new StringMap();
	m_hControllers = new ArrayList(sizeof(_Controller));
	m_hProcesses = new StringMap();

	CreateNative("Controller.mActiveProcessOp.get",		Native_Controller_GetActiveProcessOp);
	CreateNative("Controller.mActiveProcessOp.set",		Native_Controller_SetActiveProcessOp);

	CreateNative("Controller.AddMonitor",				Native_Controller_AddMonitor);
	CreateNative("Controller.RemoveMonitor",			Native_Controller_RemoveMonitor);
	
	CreateNative("Controller.mBot.get",					Native_Controller_GetBot);

	CreateNative("Controller.AddAction",				Native_Controller_AddAction);
	CreateNative("Controller.RemoveAction",				Native_Controller_RemoveAction);
	CreateNative("Controller.GetAction",				Native_Controller_GetAction);
	CreateNative("Controller.GetRandomAction",			Native_Controller_GetRandomAction);
	CreateNative("Controller.GetActionsTotal",			Native_Controller_GetActionsTotal);

	CreateNative("Controller.AddProcess",				Native_Controller_AddProcess);
	CreateNative("Controller.KillProcess",				Native_Controller_KillProcess);
	CreateNative("Controller.RestartProcess",			Native_Controller_RestartProcess);
	CreateNative("Controller.FindProcess",				Native_Controller_FindProcess);

	CreateNative("Controller.GetMessageBox",			Native_Controller_GetMessageBox);

	CreateNative("Controller.Tick",						Native_Controller_Tick);

	CreateNative("Controller.IsValid",					Native_Controller_IsValid);

	CreateNative("ContrMsgBox.iSize.get",				Native_ContrMsgBox_GetInboxSize);
	CreateNative("ContrMsgBox.GetMessage",				Native_ContrMsgBox_GetMessage);
	CreateNative("ContrMsgBox.FindMessage",				Native_ContrMsgBox_FindMessage);
	CreateNative("ContrMsgBox.PublishMessage",			Native_ContrMsgBox_PublishMessage);
	CreateNative("ContrMsgBox.ReplaceMessage",			Native_ContrMsgBox_ReplaceMessage);
	CreateNative("ContrMsgBox.EraseMessage",			Native_ContrMsgBox_EraseMessage);

	// Static

	CreateNative("Controller.GetProcessController",		Native_Controller_GetProcessController);
	CreateNative("Controller.SetProcessAction",			Native_Controller_SetProcessAction);

	CreateNative("Controller.Register",					Native_Controller_Register);
	CreateNative("Controller.Deregister",				Native_Controller_Deregister);

	CreateNative("Controller.Instance",					Native_Controller_Instance);
	CreateNative("Controller.Destroy",					Native_Controller_Destroy);
}

public any Native_Controller_GetActiveProcessOp(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	OpRef mActiveProcessOpRef = m_hControllers.Get(iThis, _Controller::mActiveProcessOpRef);
	return mActiveProcessOpRef.ToOperation();
}

public int Native_Controller_SetActiveProcessOp(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	Operation mActiveProcessOp = GetNativeCell(2);

	if (mActiveProcessOp) {
		if (!mActiveProcessOp.IsValid()) {
			ThrowError("Invalid process Operation");
		}

		Operation mProcessorOp = view_as<OpRef>(m_hControllers.Get(iThis, _Controller::mProcessorOpRef)).ToOperation();
		if (!mProcessorOp.IsValid()) {
			ThrowError("Invalid processor Operation");
		}

		if (mProcessorOp.hSubOpRefs.FindValue(mActiveProcessOp.ToOpRef()) == -1) {
			ThrowError("Operation is not a process running under this Controller");
		}
	}

	OpRef mActiveProcessOpRef = mActiveProcessOp.ToOpRef();

	OpRef mPreviousActiveProcessOpRef = m_hControllers.Get(iThis, _Controller::mActiveProcessOpRef);
	if (mPreviousActiveProcessOpRef == mActiveProcessOpRef) {
		return 0;
	}

	Bot mBot = m_hControllers.Get(iThis, _Controller::mBot);

	// Note that unlike Operation.ClearSubOperations(), this does not destroy the suboperations,
	// which allows us to resume or restart previously suspended suboperations following a context switch.
	ArrayList hBotSubOpRefs = mBot.mMainOperation.hSubOpRefs;
	hBotSubOpRefs.Clear();

	if (mActiveProcessOp) {
		char sProcessKey[6];
		PackCellToStr(mActiveProcessOpRef, sProcessKey);

		Process eProcess;
		if (!m_hProcesses.GetArray(sProcessKey, eProcess, sizeof(Process))) {
			ThrowError("Process not found");
		}

		Operation mActionOp = eProcess.mActionOpRef.ToOperation();
		if (mActionOp) {
			if (!mActionOp.IsValid()) {
				ThrowError("Invalid Process bot Operation");
			}

			if (!mActionOp.Resume()) {
				PrintToServer("Bot op not resumable, restarting");
				mActionOp.Restart();
			}

			mBot.mMainOperation.AddSubOperation(mActionOp);
		}

		m_hControllers.Set(iThis, mActiveProcessOpRef, _Controller::mActiveProcessOpRef);
	} else {
		m_hControllers.Set(iThis, INVALID_OPERATION_REFERENCE, _Controller::mActiveProcessOpRef);
	}

	return 0;
}

public any Native_Controller_GetBot(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	return m_hControllers.Get(iThis, _Controller::mBot);
}


public any Native_Controller_AddMonitor(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	PrintToServer("Controller adding monitor: %s", sIdentifier);

	KeyValues hInitParams = new KeyValues(OP_INIT_PARAM);

	Monitor mMon = CreateMonitor(sIdentifier, mContr, hInitParams);
	if (mMon) {
		StringMap hMonitors = m_hControllers.Get(iThis, _Controller::hMonitors);
		hMonitors.SetValue(sIdentifier, mMon);

		SetNativeCellRef(3, hInitParams);

		return mMon;
	}

	delete hInitParams;

	return NULL_MONITOR;
}

public any Native_Controller_RemoveMonitor(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	StringMap hMonitors = m_hControllers.Get(iThis, _Controller::hMonitors);

	Monitor mMon;
	if (hMonitors.GetValue(sIdentifier, mMon)) {
		CleanupMonitor(mMon);
		hMonitors.Remove(sIdentifier);

		return true;
	}

	return false;
}

public any Native_Controller_AddAction(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	ActionType iActionType = GetNativeCell(3);
	if (!(0 <= view_as<int>(iActionType) < ACTIONTYPE_LENGTH)) {
		ThrowError("Invalid action type");
	}

	float fWeight = GetNativeCell(4);
	if (fWeight <= 0.0) {
		ThrowError("Weight must be positive");
	}

	ControllerAction eControllerAction;
	eControllerAction.sIdentifier = sIdentifier;
	eControllerAction.fWeight = fWeight;

	ArrayList hActions = m_hControllers.Get(iThis, _Controller::hActions+view_as<int>(iActionType));
	if (!hActions) {
		hActions = new ArrayList(sizeof(ControllerAction));
		m_hControllers.Set(iThis, hActions, _Controller::hActions+view_as<int>(iActionType));

		hActions.PushArray(eControllerAction);
	} else if (hActions.FindString(sIdentifier) == -1) {
		hActions.PushArray(eControllerAction);
	}

	RecalculateActionWeightCSum(mContr, iActionType);

	return 0;
}

public any Native_Controller_RemoveAction(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	ActionType iActionType = GetNativeCell(3);
	if (!(0 <= view_as<int>(iActionType) < ACTIONTYPE_LENGTH)) {
		ThrowError("Invalid action type");
	}

	ArrayList hActions = m_hControllers.Get(iThis, _Controller::hActions+view_as<int>(iActionType));
	if (!hActions) {
		return 0;
	}

	if (sIdentifier[0]) {
		int iIdx = hActions.FindString(sIdentifier);
		if (iIdx != -1) {
			hActions.Erase(iIdx);

			RecalculateActionWeightCSum(mContr, iActionType);
		}

		if (hActions.Length) {
			return 0;
		}
	}

	delete hActions;
	m_hControllers.Set(iThis, 0, _Controller::hActions+view_as<int>(iActionType));

	return 0;
}

public any Native_Controller_GetAction(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	ActionType iActionType = GetNativeCell(2);
	if (!(0 <= view_as<int>(iActionType) < ACTIONTYPE_LENGTH)) {
		ThrowError("Invalid action type");
	}

	ArrayList hActions = m_hControllers.Get(iThis, _Controller::hActions+view_as<int>(iActionType));
	if (!hActions) {
		return false;
	}

	int iIndex = GetNativeCell(3);

	if (!(0 <= iIndex < hActions.Length)) {
		return false;
	}

	int iMaxLength = GetNativeCell(5);

	ControllerAction eControllerAction;
	hActions.GetArray(iIndex, eControllerAction);

	SetNativeString(4, eControllerAction.sIdentifier, iMaxLength);
	SetNativeCellRef(6, eControllerAction.fWeight);

	return true;
}

public any Native_Controller_GetRandomAction(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	ActionType iActionType = GetNativeCell(2);
	if (!(0 <= view_as<int>(iActionType) < ACTIONTYPE_LENGTH)) {
		ThrowError("Invalid action type");
	}

	ArrayList hActions = m_hControllers.Get(iThis, _Controller::hActions+view_as<int>(iActionType));
	if (!hActions || !hActions.Length) {
		return false;
	}

	int iMaxLength = GetNativeCell(4);

	float fMaxCSum = hActions.Get(hActions.Length-1, ControllerAction::fWeightCSum);
	float fSample = GetURandomFloat()*fMaxCSum;

	ControllerAction eControllerAction;
	for (int i=0; i<hActions.Length; i++) {
		hActions.GetArray(i, eControllerAction);

		if (fSample < eControllerAction.fWeightCSum) {
			SetNativeString(3, eControllerAction.sIdentifier, iMaxLength);
			SetNativeCellRef(5, eControllerAction.fWeight);

			return true;
		}
	}

	return false;
}

public int Native_Controller_GetActionsTotal(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	ActionType iActionType = GetNativeCell(2);
	if (!(0 <= view_as<int>(iActionType) < ACTIONTYPE_LENGTH)) {
		ThrowError("Invalid action type");
	}

	ArrayList hActions = m_hControllers.Get(iThis, _Controller::hActions+view_as<int>(iActionType));
	if (!hActions) {
		return 0;
	}

	return hActions.Length;
}


public any Native_Controller_AddProcess(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	ProcessPriority iPriority = GetNativeCell(3);
	if (!(ProcessPriority_Low <= iPriority <= ProcessPriority_Critical)) {
		ThrowError("Invalid process priority level");
	}

	Operation mProcessorOp = view_as<OpRef>(m_hControllers.Get(iThis, _Controller::mProcessorOpRef)).ToOperation();
	if (!mProcessorOp.IsValid()) {
		ThrowError("Invalid processor Operation");
	}

	ArrayList hSubOpRefs = mProcessorOp.hSubOpRefs;

	KeyValues hInitParams;
	Operation mProcessOp = Operation.Instance(sIdentifier, hInitParams);
	if (!mProcessOp.IsValid()) {
		ThrowError("Failed to instantiate process %s", sIdentifier);
	}

	mProcessOp.AddValidatedForward(OpValidatedFwd_ProcessContextSwitch);
	mProcessOp.AddAbortForward(OpAbortFwd_ProcessUnexpectedAbort);

	SetNativeCellRef(4, hInitParams);

	OpRef mProcessOpRef = mProcessOp.ToOpRef();

	char sProcessKey[6];
	PackCellToStr(mProcessOpRef, sProcessKey);

	Process eProcess;
	eProcess.mContr = mContr;
	eProcess.mProcessOpRef = mProcessOpRef;
	eProcess.mActionOpRef = INVALID_OPERATION_REFERENCE;
	eProcess.iPriority = iPriority;

	m_hProcesses.SetArray(sProcessKey, eProcess, sizeof(Process));

	hSubOpRefs.Push(mProcessOpRef);
	hSubOpRefs.SortCustom(SortFuncADTArray_ProcessPriority, _);

	return mProcessOp;
}

public any Native_Controller_KillProcess(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	Operation mProcessOp = GetNativeCell(2);
	if (!mProcessOp.IsValid()) {
		ThrowError("Invalid process Operation");
	}

	Operation mProcessorOp = view_as<OpRef>(m_hControllers.Get(iThis, _Controller::mProcessorOpRef)).ToOperation();
	if (!mProcessorOp.IsValid()) {
		ThrowError("Processor Operation is invalid");
	}

	char sProcessKey[6];
	OpRef mProcessOpRef = mProcessOp.ToOpRef();
	PackCellToStr(mProcessOpRef, sProcessKey);

	Process eProcess;
	if (!m_hProcesses.GetArray(sProcessKey, eProcess, sizeof(Process))) {
		ThrowError("Process Operation not found");
	}

	Operation mActionOp = eProcess.mActionOpRef.ToOperation();
	Operation.Destroy(mActionOp);
	Operation.Destroy(mProcessOp);

	m_hProcesses.Remove(sProcessKey);

	ArrayList hSubOpRefs = mProcessorOp.hSubOpRefs;

	int iIdx = hSubOpRefs.FindValue(mProcessOpRef);
	if (iIdx != -1) {
		hSubOpRefs.Erase(iIdx);
		return true;
	}

	return false;
}

public any Native_Controller_RestartProcess(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	Operation mProcessOp = GetNativeCell(2);
	if (!mProcessOp.IsValid()) {
		ThrowError("Invalid process Operation");
	}

	Operation mProcessorOp = view_as<OpRef>(m_hControllers.Get(iThis, _Controller::mProcessorOpRef)).ToOperation();
	if (!mProcessorOp.IsValid()) {
		ThrowError("Processor Operation is invalid");
	}

	char sProcessKey[6];
	OpRef mProcessOpRef = mProcessOp.ToOpRef();
	PackCellToStr(mProcessOpRef, sProcessKey);

	Process eProcess;
	if (!m_hProcesses.GetArray(sProcessKey, eProcess, sizeof(Process))) {
		ThrowError("Process Operation not found");
	}

	char sIdentifier[64];
	mProcessOp.GetIdentifier(sIdentifier, sizeof(sIdentifier));

	KeyValues hNewProcessInitParams;
	Operation mNewProcessOp = Operation.Instance(sIdentifier, hNewProcessInitParams);

	hNewProcessInitParams.Import(mProcessOp.hInitParams);

	mNewProcessOp.AddValidatedForward(OpValidatedFwd_ProcessContextSwitch);
	mNewProcessOp.AddAbortForward(OpAbortFwd_ProcessUnexpectedAbort);

	Operation mActionOp = eProcess.mActionOpRef.ToOperation();
	Operation.Destroy(mActionOp);

	bool bProcessAborted = mProcessOp.iOpState == OpState_Abort;

	// Processor operation will clean up the aborted process operation automatically
	if (!bProcessAborted) {
		Operation.Destroy(mProcessOp);
	}

	m_hProcesses.Remove(sProcessKey);

	OpRef mNewProcessOpRef = mNewProcessOp.ToOpRef();
	PackCellToStr(mNewProcessOpRef, sProcessKey);

	eProcess.mProcessOpRef = mNewProcessOpRef;
	eProcess.mActionOpRef = INVALID_OPERATION_REFERENCE;

	m_hProcesses.SetArray(sProcessKey, eProcess, sizeof(Process));

	ArrayList hSubOpRefs = mProcessorOp.hSubOpRefs;

	int iIdx = hSubOpRefs.FindValue(mProcessOpRef);
	if (iIdx != -1) {
		/*
		 * Do not interfere by removing the subop entirely since the processor operation
		 * will find and remove the aborted subop automatically.  Instead, keep its place
		 * in the subops array order so after cleanup its order will be replaced by the
		 * new operation, thus preserving its original process priority order.
		 */

		if (bProcessAborted) {
			hSubOpRefs.ShiftUp(iIdx);
			hSubOpRefs.Set(iIdx, mProcessOpRef);
		}

		hSubOpRefs.Set(iIdx+1, mNewProcessOpRef);
	} else {
		hSubOpRefs.Push(mNewProcessOpRef);
		hSubOpRefs.SortCustom(SortFuncADTArray_ProcessPriority, _);
	}

	return mNewProcessOp;
}

public any Native_Controller_FindProcess(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	Operation mProcessorOp = view_as<OpRef>(m_hControllers.Get(iThis, _Controller::mProcessorOpRef)).ToOperation();
	if (!mProcessorOp.IsValid()) {
		ThrowError("Processor Operation is invalid");
	}

	char sIdentifier[64];
	GetNativeString(2, sIdentifier, sizeof(sIdentifier));

	ArrayList hSubOpRefs = mProcessorOp.hSubOpRefs;
	for (int i=0; i<hSubOpRefs.Length; i++) {
		Operation mSubOp = view_as<OpRef>(hSubOpRefs.Get(i)).ToOperation();
		if (mSubOp) {
			char sProcessIdentifier[64];
			mSubOp.GetIdentifier(sProcessIdentifier, sizeof(sProcessIdentifier));

			if (StrEqual(sIdentifier, sProcessIdentifier)) {
				return mSubOp;
			}
		}
	}

	return NULL_OPERATION;
}

public int Native_Controller_Tick(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	Operation mProcessorOp = view_as<OpRef>(m_hControllers.Get(iThis, _Controller::mProcessorOpRef)).ToOperation();
	if (!mProcessorOp.IsValid()) {
		ThrowError("Processor Operation is invalid");
	}

	mProcessorOp.RunOnce();

	return 0;
}

public any Native_Controller_IsValid(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);

	int iThis = view_as<int>(mContr)-1;
	if (iThis < 0 || iThis >= m_hControllers.Length) {
		ThrowError("Invalid Controller");
	}

	return !m_hControllers.Get(iThis, _Controller::bGCFlag);
}

public any Native_Controller_GetMessageBox(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCell(1);
	if (!mContr.IsValid()) {
		ThrowError("Invalid Controller");
	}

	int iThis = view_as<int>(mContr)-1;

	char sMsgBox[64];
	GetNativeString(2, sMsgBox, sizeof(sMsgBox));

	StringMap hMsgBoxes = m_hControllers.Get(iThis, _Controller::hMsgBoxes);

	ContrMsgBox mContrMsgBox;
	if (!hMsgBoxes.GetValue(sMsgBox, mContrMsgBox)) {
		mContrMsgBox = view_as<ContrMsgBox>(new ArrayList(sizeof(ContrMsg)));
		hMsgBoxes.SetValue(sMsgBox, mContrMsgBox);
	}

	return mContrMsgBox;
}

public int Native_ContrMsgBox_GetInboxSize(Handle hPlugin, int iArgC) {
	ArrayList hContrMsgBox = GetNativeCell(1);
	return hContrMsgBox.Length;
}

public any Native_ContrMsgBox_GetMessage(Handle hPlugin, int iArgC) {
	ArrayList hContrMsgBox = GetNativeCell(1);
	int iIndex = GetNativeCell(2);

	if (!(0 <= iIndex <= hContrMsgBox.Length)) {
		ThrowError("Index out of bounds (size: %d)", hContrMsgBox.Length);
	}

	ContrMsg eContrMsg;
	hContrMsgBox.GetArray(iIndex, eContrMsg);

	SetNativeArray(3, eContrMsg.eContrMsgData, sizeof(ContrMsg::eContrMsgData));

	SetNativeCellRef(4, eContrMsg.fExpiry);

	return true;
}

public int Native_ContrMsgBox_FindMessage(Handle hPlugin, int iArgC) {
	ArrayList hContrMsgBox = GetNativeCell(1);
	any aData = GetNativeCell(2);
	int iBlock = GetNativeCell(3);

	if (!(0 <= iBlock < sizeof(ContrMsg::eContrMsgData))) {
		ThrowError("Invalid block size");
	}

	return hContrMsgBox.FindValue(aData, iBlock)
}

public any Native_ContrMsgBox_PublishMessage(Handle hPlugin, int iArgC) {
	ArrayList hContrMsgBox = GetNativeCell(1);
	int iIndex = GetNativeCell(4);

	if (iIndex < -1 || iIndex > hContrMsgBox.Length) {
		ThrowError("Index out of bounds (size: %d)", hContrMsgBox.Length);
	}

	bool bPushEnd = iIndex == -1 || iIndex == hContrMsgBox.Length;

	ContrMsg eContrMsg;
	GetNativeArray(2, eContrMsg.eContrMsgData, sizeof(ContrMsg::eContrMsgData));
	eContrMsg.fExpiry = GetNativeCell(3);

	if (bPushEnd) {
		return hContrMsgBox.PushArray(eContrMsg);
	}

	hContrMsgBox.ShiftUp(iIndex);
	hContrMsgBox.SetArray(iIndex, eContrMsg);

	return iIndex;
}

public int Native_ContrMsgBox_ReplaceMessage(Handle hPlugin, int iArgC) {
	ArrayList hContrMsgBox = GetNativeCell(1);
	int iIndex = GetNativeCell(2);

	if (iIndex < -1 || iIndex > hContrMsgBox.Length) {
		ThrowError("Index out of bounds (size: %d)", hContrMsgBox.Length);
	}

	ContrMsg eContrMsg;
	GetNativeArray(3, eContrMsg.eContrMsgData, sizeof(ContrMsg::eContrMsgData));
	eContrMsg.fExpiry = GetNativeCell(4);

	hContrMsgBox.SetArray(iIndex, eContrMsg);

	return 0;
}

public any Native_ContrMsgBox_EraseMessage(Handle hPlugin, int iArgC) {
	ArrayList hContrMsgBox = GetNativeCell(1);
	int iIndex = GetNativeCell(2);

	if (iIndex < -1 || iIndex > hContrMsgBox.Length) {
		ThrowError("Index out of bounds (size: %d)", hContrMsgBox.Length);
	}

	hContrMsgBox.Erase(iIndex);

	return 0;
}

public any Native_Controller_GetProcessController(Handle hPlugin, int iArgC) {
	Operation mProcessOp = GetNativeCell(1);
	if (!mProcessOp.IsValid()) {
		ThrowError("Invalid process Operation");
	}

	OpRef mProcessOpRef = mProcessOp.ToOpRef();

	char sProcessKey[6];
	PackCellToStr(mProcessOpRef, sProcessKey);

	Process eProcess;
	if (!m_hProcesses.GetArray(sProcessKey, eProcess, sizeof(Process))) {
		ThrowError("Process Operation not found");
	}

	return eProcess.mContr;
}

public any Native_Controller_SetProcessAction(Handle hPlugin, int iArgC) {
	Operation mProcessOp = GetNativeCell(1);
	if (!mProcessOp.IsValid()) {
		ThrowError("Invalid process Operation");
	}

	OpRef mProcessOpRef = mProcessOp.ToOpRef();

	char sProcessKey[6];
	PackCellToStr(mProcessOpRef, sProcessKey);

	Process eProcess;
	if (!m_hProcesses.GetArray(sProcessKey, eProcess, sizeof(Process))) {
		ThrowError("Process Operation not found");
	}

	Operation mProcessorOp = view_as<OpRef>(m_hControllers.Get(view_as<int>(eProcess.mContr)-1, _Controller::mProcessorOpRef)).ToOperation();
	if (!mProcessorOp.IsValid()) {
		ThrowError("Processor Operation is invalid");
	}

	Operation mActionOp = GetNativeCell(2);
	if (!mActionOp.IsValid()) {
		ThrowError("Invalid action Operation");
	}

	ArrayList hSubOpRefs = mProcessorOp.hSubOpRefs;

	int iIdx = hSubOpRefs.FindValue(mProcessOpRef);
	if (iIdx == -1) {
		ThrowError("Process Operation not running");
	}

	OpRef mActionOpRef = mActionOp.ToOpRef();

// 	PrintToServer("SetProcessAction mActiveProcessOp=%d, mProcessOp=%d", eProcess.mContr.mActiveProcessOp.iUID, mProcessOp.iUID);
	PrintToServer("SetProcessAction");

	if (eProcess.mContr.mActiveProcessOp == mProcessOp) {
		Operation mBotMainOp = eProcess.mContr.mBot.mMainOperation;
		mBotMainOp.ClearSubOperations();
		mBotMainOp.AddSubOperation(mActionOp);

	} else {
		Operation mPreviousActionOp = eProcess.mActionOpRef.ToOperation();
		if (mPreviousActionOp.IsValid()) {
			Operation.Destroy(mPreviousActionOp);
		}
	}

	eProcess.mActionOpRef = mActionOpRef;

	m_hProcesses.SetArray(sProcessKey, eProcess, sizeof(Process));

	return true;
}

// Static

public int Native_Controller_Register(Handle hPlugin, int iArgC) {
	TFClassType iClass = GetNativeCell(3);
	if (!(TFClass_Unknown <= iClass <= TFClass_Engineer)) {
		ThrowError("Invalid TFClassType: %d", iClass);
	}

	ControllerTemplate eControllerTemplate;
	GetNativeString(1, eControllerTemplate.sIdentifier, sizeof(ControllerTemplate::sIdentifier));

	eControllerTemplate.hPlugin = hPlugin;
	eControllerTemplate.fnInit = GetNativeFunction(2);

	if (m_hControllerTemplates.ContainsKey(eControllerTemplate.sIdentifier)) {
		ControllerTemplate eExistingControllerTemplate;
		m_hControllerTemplates.GetArray(eControllerTemplate.sIdentifier, eExistingControllerTemplate, sizeof(ControllerTemplate))

		if (eExistingControllerTemplate.hPlugin != hPlugin) {
			ThrowError("Controller with this identifier is already registered: %s", eControllerTemplate.sIdentifier);
		}
	}

	m_hControllerTemplates.SetArray(eControllerTemplate.sIdentifier, eControllerTemplate, sizeof(ControllerTemplate));

	if (iClass) {
		StringMap hClientControllers = m_hClientControllers[view_as<int>(iClass)];
		if (!hClientControllers) {
			m_hClientControllers[view_as<int>(iClass)] = hClientControllers = new StringMap();
		}

		hClientControllers.SetValue(eControllerTemplate.sIdentifier, 1);

		char sClassName[32];
		TF2_GetClassName(iClass, sClassName, sizeof(sClassName));

		PrintToServer("[SMBL] Registered controller: %s (%s)", eControllerTemplate.sIdentifier, sClassName);
	} else {
		PrintToServer("[SMBL] Registered controller: %s", eControllerTemplate.sIdentifier);
	}


	return 0;
}

public any Native_Controller_Deregister(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	if (!sIdentifier[0]) {
		return DeregisterPluginControllers(hPlugin);
	}

	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	ControllerTemplate eControllerTemplate;
	if (m_hControllerTemplates.GetArray(sIdentifier, eControllerTemplate, sizeof(ControllerTemplate))) {
		if (eControllerTemplate.hPlugin != hPlugin) {
			char sPluginName[64];
			GetPluginInfo(eControllerTemplate.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
			ThrowError("Controller (%s) may only be deregistered from originating plugin: %s", sIdentifier, sPluginName);
		}

		int iClassTypeIdx = view_as<int>(eControllerTemplate.iClassType);
		if (iClassTypeIdx) {
			m_hClientControllers[iClassTypeIdx].Remove(sIdentifier);

			if (!m_hClientControllers[iClassTypeIdx].Size) {
				delete m_hClientControllers[iClassTypeIdx];
			}

			char sClassName[32];
			TF2_GetClassName(eControllerTemplate.iClassType, sClassName, sizeof(sClassName));

			PrintToServer("[SMBL] Deregistered controller: %s (%s)", eControllerTemplate.sIdentifier, sClassName);
		} else {
			PrintToServer("[SMBL] Deregistered controller: %s", eControllerTemplate.sIdentifier);
		}

		DestroyDeregisteredControllers(sIdentifier);

		m_hControllerTemplates.Remove(sIdentifier);

		PrintToServer("[SMBL] Deregistered controller: %s", eControllerTemplate.sIdentifier);

		return true;
	}

	return false;
}

public any Native_Controller_Instance(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	Bot mBot = GetNativeCell(2);

	ControllerTemplate eControllerTemplate;
	if (m_hControllerTemplates.GetArray(sIdentifier, eControllerTemplate, sizeof(ControllerTemplate))) {
		Operation mProcessorOp = Operation.Instance(PROCESSOR_OPERATION);

		_Controller eContr;
		eContr.sIdentifier = sIdentifier;
		eContr.hPlugin = eControllerTemplate.hPlugin;
		eContr.fnInit = eControllerTemplate.fnInit;
		eContr.iClassType = eControllerTemplate.iClassType;
		eContr.mProcessorOpRef = mProcessorOp.ToOpRef();
		eContr.mBot = mBot;
		eContr.hMonitors = new StringMap();
		eContr.hMsgBoxes = new StringMap();
		eContr.hMsgBoxCleanupTimer = CreateTimer(MSGBOX_CLEANUP_INTERVAL, Timer_CleanupMsgBox, eContr.hMsgBoxes, TIMER_REPEAT);

		Controller mContr;
		int iFreeIdx = m_hControllers.FindValue(true, _Controller::bGCFlag);
		if (iFreeIdx != -1) {
			m_hControllers.SetArray(iFreeIdx, eContr);

			mContr = view_as<Controller>(iFreeIdx+1);
		} else {
			mContr = view_as<Controller>(m_hControllers.PushArray(eContr)+1);
		}

		SetBotController(mBot, mContr);

		Call_StartFunction(eContr.hPlugin, eContr.fnInit);
		Call_PushCell(mContr);
		Call_Finish();

		if (1 <= mBot.iEntity <= MaxClients) {
			mContr.AddProcess(PROCESS_NOOP, ProcessPriority_Critical);
		}

		mProcessorOp.Init(NULL_BOT);
		mProcessorOp.Run(CONTROLLER_TICK_INTERVAL, TIMER_REPEAT);

		return mContr;
	}

	LogError("No Controller templates found with identifier: %s", sIdentifier);

	return NULL_CONTROLLER;
}

public any Native_Controller_Destroy(Handle hPlugin, int iArgC) {
	Controller mContr = GetNativeCellRef(1);

	int iThis = view_as<int>(mContr)-1;
	if (iThis < 0 || iThis >= m_hControllers.Length) {
		return 0;
	}

	_Controller eContr;
	m_hControllers.GetArray(iThis, eContr);

	Operation mProcessorOp = eContr.mProcessorOpRef.ToOperation();
	Operation.Destroy(mProcessorOp);

	StringMapSnapshot hMonitorsSnapshot = eContr.hMonitors.Snapshot();

	char sMonitorIdentifier[64];
	for (int i=0; i<hMonitorsSnapshot.Length; i++) {
		hMonitorsSnapshot.GetKey(i, sMonitorIdentifier, sizeof(sMonitorIdentifier));

		Monitor mMon;
		eContr.hMonitors.GetValue(sMonitorIdentifier, mMon);

		CleanupMonitor(mMon);
	}

	delete hMonitorsSnapshot;

	delete eContr.hMonitors;

	StringMapSnapshot hMsgBoxesSnapshot = eContr.hMsgBoxes.Snapshot();

	char sMsgBox[64];
	for (int i=0; i<hMsgBoxesSnapshot.Length; i++) {
		hMsgBoxesSnapshot.GetKey(i, sMsgBox, sizeof(sMsgBox));

		ArrayList hContrMsgBox;
		eContr.hMsgBoxes.GetValue(sMsgBox, hContrMsgBox);

		delete hContrMsgBox;
	}

	delete hMsgBoxesSnapshot;

	delete eContr.hMsgBoxes;

	delete eContr.hMsgBoxCleanupTimer;

	StringMapSnapshot hProcessesSnapshot = m_hProcesses.Snapshot();

	char sProcessKey[6];
	for  (int i=0; i<hProcessesSnapshot.Length; i++) {
		hProcessesSnapshot.GetKey(i, sProcessKey, sizeof(sProcessKey));

		Process eProcess;
		m_hProcesses.GetArray(sProcessKey, eProcess, sizeof(Process));

		if (eProcess.mContr == mContr) {
			Operation mProcessOp = eProcess.mProcessOpRef.ToOperation();
			if (mProcessOp) {
				Operation.Destroy(mProcessOp);
			}

			m_hProcesses.Remove(sProcessKey);
		}
	}

	delete hProcessesSnapshot;

	m_hControllers.Set(iThis, true, _Controller::bGCFlag);

	SetNativeCellRef(1, NULL_CONTROLLER);

	if (iThis == m_hControllers.Length-1) {
		for (int i=iThis; i>0; i--) {
			if (!m_hControllers.Get(i-1, _Controller::bGCFlag)) {
				m_hControllers.Resize(i);
				return 0;
			}
		}

		m_hControllers.Clear();
	}

	return 0;
}

// Operation callbacks

OpRet Process_NoOp_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData, float fStartTime) {
	Controller mContr = Controller.GetProcessController(mOp);
	return IsPlayerAlive(mContr.mBot.iEntity) ? OpRet_Passthrough : OpRet_Continue;
}

// Custom callbacks

public int SortFuncADTArray_ProcessPriority(int iIdx1, int iIdx2, ArrayList hArray, Handle hHandle) {
	OpRef mOpRef1 = hArray.Get(iIdx1);
	OpRef mOpRef2 = hArray.Get(iIdx2);

	char sKey1[6], sKey2[6];
	PackCellToStr(mOpRef1, sKey1);
	PackCellToStr(mOpRef2, sKey2);

	Process eProcess1, eProcess2;
	m_hProcesses.GetArray(sKey1, eProcess1, sizeof(Process));
	m_hProcesses.GetArray(sKey2, eProcess2, sizeof(Process));

	// Descending order (higher priorities first)
	return view_as<int>(eProcess2.iPriority) - view_as<int>(eProcess1.iPriority);
}

void OpValidatedFwd_ProcessContextSwitch(Bot mBot, Operation mProcessOp, OpRet iOpRet) {
	char sIdentifier[64];
	mProcessOp.GetIdentifier(sIdentifier, sizeof(sIdentifier));
// 	PrintToServer("OpValidatedFwd_ProcessContextSwitch Operation.%s(%d), iOpRet=%d", sIdentifier, mProcessOp.iUID, iOpRet);
	switch (iOpRet) {
		case OpRet_Passthrough: {
			OpRef mProcessOpRef = mProcessOp.ToOpRef();

			char sProcessKey[6];
			PackCellToStr(mProcessOpRef, sProcessKey);

			Process eProcess;
			m_hProcesses.GetArray(sProcessKey, eProcess, sizeof(Process));

			Controller mContr = eProcess.mContr;
			if (mContr.mActiveProcessOp == mProcessOp) {
				Operation mActionOp = eProcess.mActionOpRef.ToOperation();
				if (mActionOp.IsValid()) {
					mActionOp.Suspend();
				}
			}
		}
		case OpRet_Continue: {
			OpRef mProcessOpRef = mProcessOp.ToOpRef();

			char sProcessKey[6];
			PackCellToStr(mProcessOpRef, sProcessKey);

			Process eProcess;
			m_hProcesses.GetArray(sProcessKey, eProcess, sizeof(Process));

			Controller mContr = eProcess.mContr;
			mContr.mActiveProcessOp = mProcessOp;
		}
	}
}

void OpAbortFwd_ProcessUnexpectedAbort(Bot mBot, Operation mOp, char[] sError) {
	char sIdentifier[64];
	mOp.GetIdentifier(sIdentifier, sizeof(sIdentifier));
	PrintToServer("[SMBL] Process Operation %s(%d) terminated unexpectedly.  Restarting.", sIdentifier, mOp.iUID);

	Controller mContr = Controller.GetProcessController(mOp);
	mContr.RestartProcess(mOp);
}

// Timers

public Action Timer_CleanupMsgBox(Handle hTimer, StringMap hMsgBoxes) {
	float fTime = GetGameTime();

	StringMapSnapshot hMsgBoxesSnapshot = hMsgBoxes.Snapshot();

	char sMsgBox[64];
	for (int i=0; i<hMsgBoxesSnapshot.Length; i++) {
		hMsgBoxesSnapshot.GetKey(i, sMsgBox, sizeof(sMsgBox));

		ArrayList hContrMsgBox;
		hMsgBoxes.GetValue(sMsgBox, hContrMsgBox);

		for (int j=0; j<hContrMsgBox.Length; j++) {
			if (hContrMsgBox.Get(j, ContrMsg::fExpiry) <= fTime) {
				hContrMsgBox.Erase(j--);
			}
		}
	}

	delete hMsgBoxesSnapshot;

	return Plugin_Continue;
}

// Helpers

void RegisterControllerOperations() {
	Operation.Register(PROCESSOR_OPERATION, _, _, _, _, _, _, _, true, true, false, false);
	Operation.Register(PROCESS_NOOP, _, Process_NoOp_Validate, _, _, _, _, _, true);
}

void DeregisterPluginControllers(Handle hPlugin) {
	char sIdentifier[64];

	StringMapSnapshot hControllerTemplatesSnapshot = m_hControllerTemplates.Snapshot();

	ControllerTemplate eControllerTemplate;
	for (int i=0; i<hControllerTemplatesSnapshot.Length; i++) {
		hControllerTemplatesSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));
		m_hControllerTemplates.GetArray(sIdentifier, eControllerTemplate, sizeof(ControllerTemplate));

		if (eControllerTemplate.hPlugin == hPlugin) {
			int iClassTypeIdx = view_as<int>(eControllerTemplate.iClassType);
			if (iClassTypeIdx) {
				m_hClientControllers[iClassTypeIdx].Remove(sIdentifier);

				if (!m_hClientControllers[iClassTypeIdx].Size) {
					delete m_hClientControllers[iClassTypeIdx];
				}

				char sClassName[32];
				TF2_GetClassName(eControllerTemplate.iClassType, sClassName, sizeof(sClassName));

				PrintToServer("[SMBL] Deregistered controller: %s (%s)", eControllerTemplate.sIdentifier, sClassName);
			} else {
				PrintToServer("[SMBL] Deregistered controller: %s", eControllerTemplate.sIdentifier);
			}

			DestroyDeregisteredControllers(sIdentifier);

			m_hControllerTemplates.Remove(sIdentifier);
		}
	}
}

void DestroyDeregisteredControllers(char[] sTemplateIdentifier) {
	char sIdentifier[64];
	for (int i=0; i<m_hControllers.Length; i++) {
		if (m_hControllers.Get(i, _Controller::bGCFlag)) {
			continue;
		}

		m_hControllers.GetString(i, sIdentifier, sizeof(sIdentifier));
		if (StrEqual(sIdentifier, sTemplateIdentifier)) {
			Controller mContr = view_as<Controller>(i+1);
			Controller.Destroy(mContr);
		}
	}
}

bool AreClientControllersAvailable(TFClassType iClassType) {
	if (!(TFClass_Scout <= iClassType <= TFClass_Engineer)) {
		ThrowError("Invalid TFClassType");
	}

	StringMap hClientControllers = m_hClientControllers[view_as<int>(iClassType)];
	if (!hClientControllers || !hClientControllers.Size) {
		return false;
	}

	return true;
}

Controller GetClientController(TFClassType iClassType, char sIdentifier[64], Bot mBot) {
	if (!(TFClass_Scout <= iClassType <= TFClass_Engineer)) {
		ThrowError("Invalid TFClassType");
	}

	StringMap hClientControllers = m_hClientControllers[view_as<int>(iClassType)];
	if (!hClientControllers || !hClientControllers.Size) {
		return NULL_CONTROLLER;
	}

	if (!sIdentifier[0]) {
		StringMapSnapshot hClientControllersSnapshot = hClientControllers.Snapshot();
		int iRandomIdx = GetURandomInt() % hClientControllersSnapshot.Length;

		hClientControllersSnapshot.GetKey(iRandomIdx, sIdentifier, sizeof(sIdentifier));
	} else if (!hClientControllers.ContainsKey(sIdentifier)) {
		char sClassName[32];
		TF2_GetClassName(iClassType, sClassName, sizeof(sClassName));

		ThrowError("No controllers for %s found with identifier: %s", sClassName, sIdentifier);
	}

	return Controller.Instance(sIdentifier, mBot);
}

Controller GetEntityController(char[] sIdentifier, Bot mBot) {
	if (!m_hControllerTemplates.ContainsKey(sIdentifier)) {
		ThrowError("No controllers found with identifier: %s", sIdentifier);
	}

	return Controller.Instance(sIdentifier, mBot);
}

void RecalculateActionWeightCSum(Controller mContr, ActionType iActionType) {
	int iThis = view_as<int>(mContr)-1;

	ArrayList hActions = m_hControllers.Get(iThis, _Controller::hActions+view_as<int>(iActionType));

	float fCSum;
	for (int i=0; i<hActions.Length; i++) {
		fCSum += view_as<float>(hActions.Get(i, ControllerAction::fWeight));
		hActions.Set(i, fCSum, ControllerAction::fWeightCSum);
	}
}
