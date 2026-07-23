#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smlib/entities>
#include <smlib/math>

#include <smbl>
#include <smbl/nav_mesh>

#define ATTACK_INTERVAL	1.0

#define MIN_COMBAT_CHASE_DISTANCE 500.0

enum struct ContrMsgData_Target {
	int iEntityRef;
	Bot mBot;
	TFTeam iTeam;
	TFClassType iClass;
	float vecOrigin[3];
	any aPadding[25];
}

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

// Library forwards

public void SMBL_OnStart() {
	Operation.Register("Process.Combat.Attack", Combat_Attack_Init, Combat_Attack_Validate, _, _, _, _, _, true);
	Operation.Register("Process.Combat.Chase", Combat_Chase_Init, Combat_Chase_Validate, _, _, _, _, _, true);
}

// Attack

enum struct OpData_Combat_Attack {
	OpRef mAttackOpRef;
	float fNextAttackTime;
	float aPadding[14];
}

OpRet Combat_Attack_Init(any aIgnore, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData) {
// 	Operation mActionOp = Operation.Instance("Common.Idle.LookAround");
// 	Controller.SetProcessAction(mOp, mActionOp);

	return OpRet_Continue;
}

OpRet Combat_Attack_Validate(any aIgnore, Operation mOp, ArrayList hSequences, OpData_Combat_Attack eOpData, float fStartTime) {
	Operation mAttackOp = eOpData.mAttackOpRef.ToOperation();

	if (mAttackOp.IsValid() && mAttackOp.iOpState == OpState_Run) {
		return OpRet_Continue;
	}

	float fTime = GetGameTime();
	if (fTime < eOpData.fNextAttackTime) {
		return OpRet_Passthrough;
	}

	Controller mContr = Controller.GetProcessController(mOp);

	ContrMsgBox mContrMsgBox = mContr.GetMessageBox("targets");
	int iMsgBoxSize = mContrMsgBox.iSize;

	if (!iMsgBoxSize) {
		return OpRet_Passthrough;
	}

	char sIdentifier[64];
	if (!mContr.GetRandomAction(ActionType_Attack, sIdentifier, sizeof(sIdentifier))) {
		return OpRet_Passthrough;
	}

	eOpData.fNextAttackTime = fTime + ATTACK_INTERVAL;

	float vecOrigin[3];
	Entity_GetAbsOrigin(mContr.mBot.iEntity, vecOrigin);

	ContrMsgData_Target eContrMsgData;
	for (int i=0; i<iMsgBoxSize; i++) {
		mContrMsgBox.GetMessage(i, eContrMsgData);
		int iTarget = EntRefToEntIndex(eContrMsgData.iEntityRef);
		if (iTarget == INVALID_ENT_REFERENCE) {
			continue;
		}

		KeyValues hInitParams = new KeyValues(OP_INIT_PARAM);
		hInitParams.SetVector("origin", vecOrigin);
		hInitParams.SetNum("target", iTarget);

		if (Operation.Configure(sIdentifier, hInitParams)) {
			KeyValues hAttackInitParams;
			Operation mActionOp = Operation.Instance(sIdentifier, hAttackInitParams);
			Controller.SetProcessAction(mOp, mActionOp);

			eOpData.mAttackOpRef = mActionOp.ToOpRef();

			hAttackInitParams.Import(hInitParams);

			delete hInitParams;

			return OpRet_Continue;
		}

		delete hInitParams;
	}

	return OpRet_Passthrough;
}

// Chase

enum struct OpData_Combat_Chase {
	NavMesh mNavMesh;
	int iEntityRef;
	OpRef mMoveOpRef;
	float fNextChaseTime;
	float aPadding[12];
}

OpRet Combat_Chase_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Combat_Chase eOpData) {
	eOpData.mNavMesh = view_as<NavMesh>(hInitParams.GetNum("nav_mesh"));

	return OpRet_Continue;
}

OpRet Combat_Chase_Validate(any aIgnore, Operation mOp, ArrayList hSequences, OpData_Combat_Chase eOpData, float fStartTime) {
	Operation mMoveOp = eOpData.mMoveOpRef.ToOperation();

	if (mMoveOp.IsValid() && mMoveOp.iOpState == OpState_Run) {
		return OpRet_Continue;
	}

	Controller mContr = Controller.GetProcessController(mOp);

	char sIdentifier[64];
	if (!mContr.GetRandomAction(ActionType_Locomotion, sIdentifier, sizeof(sIdentifier))) {
		return OpRet_Passthrough;
	}

	ContrMsgBox mContrMsgBox = mContr.GetMessageBox("targets");
	int iMsgBoxSize = mContrMsgBox.iSize;

	if (!iMsgBoxSize) {
		return OpRet_Passthrough;
	}

	int iEntity = EntRefToEntIndex(eOpData.iEntityRef);

	float vecOrigin[3], vecDest[3];
	Entity_GetAbsOrigin(mContr.mBot.iEntity, vecOrigin);

	int iMsgIdx;
	if (iEntity == INVALID_ENT_REFERENCE || (iMsgIdx = mContrMsgBox.FindMessage(eOpData.iEntityRef, ContrMsgData_Target::iEntityRef)) == -1) {
		float fMinDist = POSITIVE_INFINITY;
		float vecMinOrigin[3];
	
		ContrMsgData_Target eContrMsgData;
		for (int i=0; i<iMsgBoxSize; i++) {
			mContrMsgBox.GetMessage(i, eContrMsgData);

			float fDist = GetVectorDistance(vecOrigin, eContrMsgData.vecOrigin);

			if (fDist < MIN_COMBAT_CHASE_DISTANCE) {
				return OpRet_Passthrough;
			}

			if (fDist < fMinDist) {
				int iTargetEntity = EntRefToEntIndex(eContrMsgData.iEntityRef);
				if (iTargetEntity != INVALID_ENT_REFERENCE) {
					fMinDist = fDist;
					iEntity = iTargetEntity;
					vecMinOrigin = eContrMsgData.vecOrigin;
				}
			}
		}

		if (iEntity == INVALID_ENT_REFERENCE) {
			return OpRet_Passthrough;
		}

		eOpData.iEntityRef = EntIndexToEntRef(iEntity);

		vecDest = vecMinOrigin;
	} else {
		ContrMsgData_Target eContrMsgData;
		mContrMsgBox.GetMessage(iMsgIdx, eContrMsgData);
		vecDest = eContrMsgData.vecOrigin;
	}

	TR_TraceRayFilter(vecDest, {90.0, 0.0, 0.0}, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
	if (!TR_DidHit()) {
		return OpRet_Passthrough;
	}

	TR_GetEndPosition(vecDest);

	KeyValues hInitParams = new KeyValues(OP_INIT_PARAM);
	hInitParams.SetNum("nav_mesh", view_as<int>(eOpData.mNavMesh));
	hInitParams.SetVector("origin", vecOrigin);
	hInitParams.SetVector("destination", vecDest);
	hInitParams.SetNum("config_nav_path", true);

	if (Operation.Configure(sIdentifier, hInitParams)) {
		hInitParams.JumpToKey(OP_INIT_CONFIG);

		// Player is too close to chase
		NavPath mNavPath = view_as<NavPath>(hInitParams.GetNum("nav_path"));
		if (mNavPath.iLength <= 1) {
			NavPath.Destroy(mNavPath);
			delete hInitParams;

			return OpRet_Passthrough;
		}

		hInitParams.GoBack(); // from OP_INIT_CONFIG

		KeyValues hActionInitParams;
		Operation mActionOp = Operation.Instance(sIdentifier, hActionInitParams);
		Controller.SetProcessAction(mOp, mActionOp);

		mActionOp.AddStateChangeForward(OpStateChangeFwd_ChaseCompleted);

		eOpData.mMoveOpRef = mActionOp.ToOpRef();

		hActionInitParams.Import(hInitParams);

		delete hInitParams;

		return OpRet_Continue;
	}

	delete hInitParams;

	return OpRet_Passthrough;
}

// Custom callbacks

public bool TraceEntityFilter_Environment(int iEntity, int iContentsMask) {
	return false;
}

public void OpStateChangeFwd_ChaseCompleted(Bot mBot, Operation mOp, OpState iOpState) {
	switch (iOpState) {
		case OpState_Complete: {
			Controller mContr = mBot.GetController();
// 			PrintToServer("OpStateChangeFwd_ChaseCompleted: mBot=%d, mContr=%d (valid=%d)", mBot, mContr, mContr.IsValid());
// 			mBot.GetController().Tick(); // Crashes
			RequestFrame(RequestFrameCallback_ControllerTick, mContr);
		}
	}
}

public void RequestFrameCallback_ControllerTick(Controller mContr) {
	if (mContr.IsValid()) {
// 		mContr.Tick();
	}
}
