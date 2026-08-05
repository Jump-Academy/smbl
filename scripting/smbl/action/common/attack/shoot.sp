#define PID_FAST		{0.10,	0.001,	0.01}

#define AIM_ERROR_TARGET	5.0

enum struct OpData_Shoot {
	int iTargetRef;
	float vecTargetPos[3];
	any aPadding[12];
}

// Operation callbacks

OpRet Shoot_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Shoot eOpData) {
	int iTarget = hInitParams.GetNum("target");
	eOpData.iTargetRef = iTarget ? EntIndexToEntRef(iTarget) : INVALID_ENT_REFERENCE;

	if (hInitParams.JumpToKey("targetpos")) {
		hInitParams.GoBack();
		hInitParams.GetVector("targetpos", eOpData.vecTargetPos);
	} else if (!iTarget) {
		return mOp._Abort("missing targetpos init parameter");
	}

	return OpRet_Continue;
}

OpRet Shoot_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Shoot eOpData, float fStartTime) {
	if (eOpData.iTargetRef != INVALID_ENT_REFERENCE) {
		int iEntity = mBot.iEntity;

		int iTarget = EntRefToEntIndex(eOpData.iTargetRef);
		if (!iTarget || !IsValidEntity(iTarget) || (Client_IsValid(iTarget) && !IsPlayerAlive(iTarget)) || Entity_GetHealth(iTarget) <= 0) {
			return mOp._Abort("target entity is no longer valid");
		}

		float vecViewerPos[3];
		GetViewerPos(iEntity, vecViewerPos);

		float vecTargetPos[3];
		GetEntityMidpoint(iTarget, vecTargetPos);

		int iTeam = GetClientTeam(iEntity);

		TR_TraceRayFilter(vecViewerPos, vecTargetPos, MASK_SHOT_HULL, RayType_EndPoint, TraceEntityFilter_IgnoreTeam, iTeam);
		int iHitEntity = TR_GetEntityIndex();
		if (iHitEntity <= 0 || (TR_GetEntityIndex() != iTarget && GetClientTeam(iHitEntity) != GetClientTeam(iTarget))) {
			return mOp._Abort("target entity is not visible");
		}
	}

	return OpRet_Continue;
}

OpRet Shoot_PreRun(Bot mBot, Operation mOp, OpData_Shoot eOpData) {
	int iEntity = mBot.iEntity;

	float vecViewerPos[3], vecTargetPos[3];

	GetViewerPos(iEntity, vecViewerPos);

	if (eOpData.iTargetRef != INVALID_ENT_REFERENCE) {
		int iTarget = EntRefToEntIndex(eOpData.iTargetRef);
		GetEntityMidpoint(iTarget, vecTargetPos);
	} else {
		vecTargetPos = eOpData.vecTargetPos;
	}

	float vecDiff[3];
	SubtractVectors(vecTargetPos, vecViewerPos, vecDiff);

	float vecAng[3];
	GetVectorAngles(vecDiff, vecAng);

	mBot.SetPID(PID_FAST);
	mBot.SetAimTo(vecAng);

	float fPitchError, fYawError;
	mBot.GetAimError(fPitchError, fYawError);

	if (FloatAbs(fPitchError) < AIM_ERROR_TARGET && FloatAbs(fYawError) < AIM_ERROR_TARGET) {
		mBot.iButtons |= IN_ATTACK;
	} else {
		mBot.iButtons &= ~IN_ATTACK;
	}

	return OpRet_Continue;
}

void Shoot_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Shoot eOpData) {
	if (mBot) {
		mBot.iButtons &= ~IN_ATTACK;
	}
}
