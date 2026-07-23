#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <sourcemod>
#include <sdkhooks>

#include <smlib/entities>
#include <smlib/math>

#include <smbl>

#define DAMAGE_PROCESS_IDENTIFIER	"Process.Investigate.Damage"
#define TOUCH_PROCESS_IDENTIFIER	"Process.Investigate.Touch"

#define LOOK_INTERVAL 0.2

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

// Library forwards

public void SMBL_OnStart() {
	Operation.Register(DAMAGE_PROCESS_IDENTIFIER, Investigate_Damage_Init, Investigate_Damage_Validate, _, _, _, _, Investigate_Damage_Cleanup, true);
	Operation.Register(TOUCH_PROCESS_IDENTIFIER, Investigate_Touch_Init, Investigate_Touch_Validate, _, _, _, _, Investigate_Touch_Cleanup, true);
}

// Investigate Damage

enum struct OpData_Investigate_Damage {
	OpRef mLookOpRef;
	float fLookEndTime;
	float aPadding[14];
}

OpRet Investigate_Damage_Init(any aIgnore, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData) {
	Controller mContr = Controller.GetProcessController(mOp);
	SDKHook(mContr.mBot.iEntity, SDKHook_OnTakeDamagePost, SDKHookCB_Bot_OnTakeDamagePost);

	return OpRet_Continue;
}

void Investigate_Damage_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData) {
	Controller mContr = Controller.GetProcessController(mOp);
	SDKUnhook(mContr.mBot.iEntity, SDKHook_OnTakeDamagePost, SDKHookCB_Bot_OnTakeDamagePost);
}

OpRet Investigate_Damage_Validate(any aIgnore, Operation mOp, ArrayList hSequences, OpData_Investigate_Damage eOpData, float fStartTime) {
	Operation mLookOp = eOpData.mLookOpRef.ToOperation();

	if (mLookOp.IsValid()) {
		if (GetGameTime() < eOpData.fLookEndTime) {
			return OpRet_Continue;
		}

		Operation.Destroy(mLookOp);
		eOpData.mLookOpRef = INVALID_OPERATION_REFERENCE;
	}

	return OpRet_Passthrough;
}

// Investigate Touch

enum struct OpData_Investigate_Touch {
	OpRef mLookOpRef;
	float fLookEndTime;
	float aPadding[14];
}

OpRet Investigate_Touch_Init(any aIgnore, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData) {
	Controller mContr = Controller.GetProcessController(mOp);
	SDKHook(mContr.mBot.iEntity, SDKHook_StartTouchPost, SDKHookCB_Bot_OnStartTouchPost);

	return OpRet_Continue;
}

void Investigate_Touch_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData) {
	Controller mContr = Controller.GetProcessController(mOp);
	SDKUnhook(mContr.mBot.iEntity, SDKHook_StartTouchPost, SDKHookCB_Bot_OnStartTouchPost);
}

OpRet Investigate_Touch_Validate(any aIgnore, Operation mOp, ArrayList hSequences, OpData_Investigate_Touch eOpData, float fStartTime) {
	Operation mLookOp = eOpData.mLookOpRef.ToOperation();

	if (mLookOp.IsValid()) {
		if (GetGameTime() < eOpData.fLookEndTime) {
			return OpRet_Continue;
		}

		Operation.Destroy(mLookOp);
		eOpData.mLookOpRef = INVALID_OPERATION_REFERENCE;
	}

	return OpRet_Passthrough;
}

// Custom callbacks

public void SDKHookCB_Bot_OnTakeDamagePost(int iVictim, int iAttacker, int iInflictor, float fDamage, int iDamageType, int iWeapon, const float vecDamageForce[3], const float vecDamagePosition[3]) {
	if (iVictim == iAttacker || !iAttacker || !(GetEntityFlags(iVictim) & FL_ONGROUND)) {
		return;
	}

	Bot mBot = SMBL_GetEntityBot(iVictim);
	Controller mContr = mBot.GetController();

	Operation mProcessOp = mContr.FindProcess(DAMAGE_PROCESS_IDENTIFIER);

	OpData_Investigate_Touch eOpData;
	mProcessOp.GetData(eOpData);

	Operation mLookOp = eOpData.mLookOpRef.ToOperation();
	if (mLookOp.IsValid()) {
		Operation.Destroy(mLookOp);
	}

	KeyValues hLookInitParams;
	mLookOp = Operation.Instance("Common.Idle.LookAt", hLookInitParams);

	Controller.SetProcessAction(mProcessOp, mLookOp);

	eOpData.mLookOpRef = mLookOp.ToOpRef();
	eOpData.fLookEndTime = GetGameTime() + LOOK_INTERVAL;
	mProcessOp.SetData(eOpData);

	hLookInitParams.SetVector("target_origin", vecDamagePosition);

	mContr.Tick();
}

public void SDKHookCB_Bot_OnStartTouchPost(int iEntity, int iOther) {
	if (!iOther) {
		return;
	}

	Bot mBot = SMBL_GetEntityBot(iEntity);

	Controller mContr = mBot.GetController();

	Operation mProcessOp = mContr.FindProcess(TOUCH_PROCESS_IDENTIFIER);

	OpData_Investigate_Damage eOpData;
	mProcessOp.GetData(eOpData);

	Operation mLookOp = eOpData.mLookOpRef.ToOperation();
	if (GetGameTime() >= eOpData.fLookEndTime && mLookOp.IsValid()) {
		return;
	}

	KeyValues hLookInitParams;
	mLookOp = Operation.Instance("Common.Idle.LookAt", hLookInitParams);

	Controller.SetProcessAction(mProcessOp, mLookOp);

	eOpData.mLookOpRef = mLookOp.ToOpRef();
	eOpData.fLookEndTime = GetGameTime() + LOOK_INTERVAL;
	mProcessOp.SetData(eOpData);

	float vecOtherOrigin[3];
	Entity_GetAbsOrigin(iOther, vecOtherOrigin);

	hLookInitParams.SetVector("target_origin", vecOtherOrigin);

	mContr.Tick();
}
