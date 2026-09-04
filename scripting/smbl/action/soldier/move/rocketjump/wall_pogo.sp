enum struct OpData_Wall_Pogo_Up {
	float vecWallNormal[3];
	float fMaxWidth;
	any aPadding[12];
}

// Operation callbacks

OpRet Wall_Pogo_Up_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Wall_Pogo_Up eOpData, bool bConfigureOnly) {
	int iEntity = mBot.iEntity;

	float vecMaxs[3];
	Entity_GetMaxSize(iEntity, vecMaxs);
	eOpData.fMaxWidth = vecMaxs[0] > vecMaxs[1] ? vecMaxs[0] : vecMaxs[1];
	eOpData.fMaxWidth *= 1.4;

	Sequence eSeq;

	eSeq.fnRun = Wall_Pogo_Up_Aim_Align_Wall;
	eSeq.sIdentifier = "Aim_Align_Wall";
	hSequences.PushArray(eSeq);

	eSeq.fnRun = Wall_Pogo_Up_Shoot_Wall;
	eSeq.iSeq = view_as<Seq>(1);
	eSeq.sIdentifier = "Shoot_Wall";
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

OpRet Wall_Pogo_Up_Aim_Align_Wall(Bot mBot, Operation mOp, OpData_Wall_Pogo_Up eOpData, SeqData eSeqData, float fStartTime) {
	int iEntity = mBot.iEntity;

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	float vecAng[3];
	Entity_GetAbsAngles(iEntity, vecAng);
	vecAng[0] = 0.0;

	TR_TraceRayFilter(vecPos, vecAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
	if (!TR_DidHit()) {
		return mOp._Abort("missing wall surface");
	}

	float vecWallPos[3];
	TR_GetEndPosition(vecWallPos);

	float vecDiff[3];
	SubtractVectors(vecWallPos, vecPos, vecDiff);

	float fDist2D = SquareRoot(vecDiff[0]*vecDiff[0] + vecDiff[1]*vecDiff[1]);
	if (fDist2D > eOpData.fMaxWidth) {
		return mOp._Abort("detached from wall surface");
	}

	TR_GetPlaneNormal(null, eOpData.vecWallNormal);

	float vecWallAng[3];
	GetVectorAngles(eOpData.vecWallNormal, vecWallAng);

	float vecAimAng[3];
	vecAimAng[0] = 80.0;
	vecAimAng[1] = NormalizeAngle(vecWallAng[1] + 180.0 + 12.0);

	mBot.SetAimTo(vecAimAng);
	mBot.SetPID(PID_FAST);

	mBot.iButtons = IN_DUCK | IN_FORWARD;
	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	float fPitchError;
	mBot.GetAimError(fPitchError, _);

	if (FloatAbs(fPitchError) < 2.0) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet Wall_Pogo_Up_Shoot_Wall(Bot mBot, Operation mOp, OpData_Wall_Pogo_Up eOpData, SeqData eSeqData, float fStartTime) {
	int iEntity = mBot.iEntity;

	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return mOp._Abort("landed");
	}

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	float vecAng[3];
	Entity_GetAbsAngles(iEntity, vecAng);
	vecAng[0] = 0.0;

	TR_TraceRayFilter(vecPos, vecAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
	if (!TR_DidHit()) {
		return mOp._Abort("missing wall surface");
	}

	float vecWallPos[3];
	TR_GetEndPosition(vecWallPos);

	float vecDiff[3];
	SubtractVectors(vecWallPos, vecPos, vecDiff);

	float fDist2D = SquareRoot(vecDiff[0]*vecDiff[0] + vecDiff[1]*vecDiff[1]);
	if (fDist2D > eOpData.fMaxWidth) {
		return mOp._Abort("detached from wall surface");
	}

	// Since player is hugging the wall, the velocity vector is already projected onto wall

	float vecVelProj[3];
	Entity_GetAbsVelocity(iEntity, vecVelProj);

	float vecCrossProduct[3];
	GetVectorCrossProduct(eOpData.vecWallNormal, vecVelProj, vecCrossProduct);
	
	if (vecCrossProduct[2] > 0) {
		mBot.iButtons = IN_FORWARD | IN_DUCK | IN_ATTACK;
		mBot.SetLocalVelocity({400.0, 0.0, 0.0});
	} else {
		mBot.iButtons = IN_FORWARD | IN_MOVERIGHT | IN_DUCK | IN_ATTACK;
		mBot.SetLocalVelocity({400.0, 400.0, 0.0});
	}

	return OpRet_Continue;
}

void Wall_Pogo_Up_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Wall_Pogo_Up eOpData) {
	if (mBot) {
		mBot.iButtons = 0;
		mBot.SetLocalVelocity({0.0, 0.0, 0.0});
	}
}
