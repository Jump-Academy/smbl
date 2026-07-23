#include <smbl/monitor>

methodmap Controller {
	property Operation mActiveProcessOp {
		public native set(Operation mActiveProcessOp);
		public native get();
	}

	property Bot mBot {
		public native get();
	}

	public native Monitor AddMonitor(char[] sIdentifier, KeyValues &hInitParams=null);
	public native void RemoveMonitor(char[] sIdentifier);

	public native void AddAction(char[] sIdentifier, ActionType iActionType, float fWeight=1.0);
	public native void RemoveAction(char[] sIdentifier, ActionType iActionType);
	public native bool GetAction(ActionType iActionType, int iIndex, char[] sIdentifier, int iMaxLength, float &fWeight=0.0);
	public native bool GetRandomAction(ActionType iActionType, char[] sIdentifier, int iMaxLength, float &fWeight=0.0);
	public native int GetActionsTotal(ActionType iActionType);

	public native Operation AddProcess(char[] sIdentifier, ProcessPriority iPriority=ProcessPriority_Normal, KeyValues &hInitParams=null);
	public native bool KillProcess(Operation mProcessOp);
	public native Operation RestartProcess(Operation mProcessOp);
	public native Operation FindProcess(char[] sIdentifier);

	public native ContrMsgBox GetMessageBox(char[] sMsgBox);

	public native void Tick();

	public native bool IsValid();

	public static native Controller GetProcessController(Operation mProcessOp);
	public static native bool SetProcessAction(Operation mProcessOp, Operation mActionOp);

	/**
	 * Registers a controller
	 *
	 * @param sIdentifier Unique identifier for this controller.
	 * @param iClassType TF2 class this controller works with, or TFClass_Unknown if the controller is not for a TF2 class bot.
	 */
	public static native void Register(char[] sIdentifier, ContrInitFunc fnControllerInit, TFClassType iClassType=TFClass_Unknown);

	/**
	 * Deregisters a controller
	 *
	 * Controllers can only be deregistered from its originating plugin.
	 *
	 * @param sIdentifier Unique identifier for the controller to deregister or NULL_STRING for all controllers in under the plugin.
	 */
	public static native bool Deregister(char[] sIdentifier=NULL_STRING);

	public static native Controller Instance(char[] sIdentifier, Bot mBot);
	public static native void Destroy(Controller &mContr);
}

methodmap ContrMsgBox {
	property int iSize {
		public native get();
	}

	public native bool GetMessage(int iIndex, any aData[32], float &fExpiry=0.0);
	public native int FindMessage(any aData, int iBlock);
	public native int PublishMessage(any aData[32], float fExpiry=0.0, int iIndex=-1);
	public native void ReplaceMessage(int iIndex, any aData[32], float fExpiry=0.0);
	public native void EraseMessage(int iIndex);
}

enum struct ContrMsgData {
	any aData[32];
}

typedef ContrInitFunc = function void (Controller mContr);

#define NULL_CONTROLLER	view_as<Controller>(0)

enum ProcessPriority {
	ProcessPriority_Low,
	ProcessPriority_BelowNormal,
	ProcessPriority_Normal,
	ProcessPriority_AboveNormal,
	ProcessPriority_High,
	ProcessPriority_Critical
}

enum ActionType {
	ActionType_Move,
	ActionType_Attack,
	ActionType_Proximity
}

#define ACTIONTYPE_LENGTH	2
