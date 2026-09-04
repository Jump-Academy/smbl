enum struct OpData_Wall_Climb_Pull {
	float vecAimAng[3];
	float vecHeading[3];
	float fMaxWidth;
	bool bLedge;
	any aPadding[8];
}

// Operation callbacks

OpRet Wall_Climb_Pull_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Wall_Climb_Pull eOpData, bool bConfigureOnly) {
	int iEntity = mBot.iEntity;

	if (!hInitParams.JumpToKey("wall_normal")) {
		return mOp._Abort("missing parameter wall_normal");
	}

	hInitParams.GoBack();

	hInitParams.GetVector("wall_normal", eOpData.vecHeading);

	eOpData.bLedge = hInitParams.GetNum("ledge", 0) != 0;

	GetVectorAngles(eOpData.vecHeading, eOpData.vecAimAng);

	// Wall climbs head in the direction opposite to the wall normal
	NegateVector(eOpData.vecHeading);

	float vecMaxs[3];
	Entity_GetMaxSize(iEntity, vecMaxs);
	eOpData.fMaxWidth = vecMaxs[0] > vecMaxs[1] ? vecMaxs[0] : vecMaxs[1];
	eOpData.fMaxWidth *= 1.4;

	Sequence eSeq;
	eSeq.fnRun = Wall_Climb_Pull_Forward;
	eSeq.sIdentifier = "Pull_Forward";
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

// Sequences

OpRet Wall_Climb_Pull_Forward(Bot mBot, Operation mOp, OpData_Wall_Climb_Pull eOpData, SeqData eSeqData, float fStartTime) {
	if (!fStartTime) {
		mBot.SetPID(PID_FAST);
	}

	int iEntity = mBot.iEntity;

	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return OpRet_Handled;
	}

	if (!eOpData.bLedge) {
		float vecPos[3];
		Entity_GetAbsOrigin(iEntity, vecPos);

		float vecAng[3];
		Entity_GetAbsAngles(iEntity, vecAng);
		vecAng[0] = 0.0;

		TR_TraceRayFilter(vecPos, vecAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
		if (TR_DidHit()) {
			float vecPosAhead[3];
			TR_GetEndPosition(vecPosAhead);

			float vecDiff[3];
			SubtractVectors(vecPosAhead, vecPos, vecDiff);

			float fDist2D = SquareRoot(vecDiff[0]*vecDiff[0] + vecDiff[1]*vecDiff[1]);
			if (fDist2D <= eOpData.fMaxWidth) {
				return OpRet_Handled;
			}
		}
	}

	float vecVelProj[3];
	Entity_GetAbsVelocity(iEntity, vecVelProj);

	float vecCrossProduct[3];
	GetVectorCrossProduct(eOpData.vecHeading, vecVelProj, vecCrossProduct);
	
	if (vecCrossProduct[2] > 0) {
		mBot.iButtons = IN_FORWARD | IN_MOVELEFT | IN_DUCK;
		mBot.SetLocalVelocity({400.0, -400.0, 0.0});
	} else {
		mBot.iButtons = IN_FORWARD | IN_MOVERIGHT | IN_DUCK;
		mBot.SetLocalVelocity({400.0, 400.0, 0.0});
	}

	float vecAimAng[3];
	mBot.GetAimTo(vecAimAng);
	vecAimAng[1] = eOpData.vecAimAng[1];
	mBot.SetAimTo(vecAimAng);

	return OpRet_Continue;
}

void Wall_Climb_Pull_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Wall_Climb_Up eOpData) {
	if (mBot) {
		mBot.iButtons = 0;
		mBot.SetLocalVelocity({0.0, 0.0, 0.0});
	}
}
