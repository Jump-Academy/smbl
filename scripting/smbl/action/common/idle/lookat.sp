#define LOOK_PITCH_OFFSET	25.0

enum struct OpData_Idle_LookAt {
	int iTargetEntityRef;
	float vecTargetOrigin[3];
	any aPadding[12];
}

OpRet Idle_LookAt_Init(any aIgnore, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Idle_LookAt eOpData) {
	hInitParams.Rewind();

	if (hInitParams.JumpToKey("target")) {
		eOpData.iTargetEntityRef = EntIndexToEntRef(hInitParams.GetNum(NULL_STRING));
	} else if (hInitParams.JumpToKey("target_origin")) {
		eOpData.iTargetEntityRef = INVALID_ENT_REFERENCE;
		hInitParams.GetVector(NULL_STRING, eOpData.vecTargetOrigin);
	}

	hInitParams.Rewind();

	return OpRet_Continue;
}

OpRet Idle_LookAt_PreRun(Bot mBot, Operation mOp, OpData_Idle_LookAt eOpData) {
	int iTargetEntity = EntRefToEntIndex(eOpData.iTargetEntityRef);
	if (iTargetEntity != INVALID_ENT_REFERENCE) {
		Entity_GetAbsOrigin(iTargetEntity, eOpData.vecTargetOrigin);
	}

	float vecOrigin[3];
	int iEntity = mBot.iEntity;
	if (1 <= iEntity <= MaxClients) {
		GetClientEyePosition(iEntity, vecOrigin);
	} else {
		Entity_GetAbsOrigin(iEntity, vecOrigin);
	}

	float vecDiff[3];
	SubtractVectors(eOpData.vecTargetOrigin, vecOrigin, vecDiff);

	float vecAng[3];
	GetVectorAngles(vecDiff, vecAng);

	vecAng[0] -= LOOK_PITCH_OFFSET;

	mBot.SetPID(PID_FAST);
	mBot.SetAimTo(vecAng);

	return OpRet_Continue;
}
