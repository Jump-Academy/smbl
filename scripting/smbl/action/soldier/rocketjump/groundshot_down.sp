enum struct OpData_Groundshot_Down {
	float fHeadingAng;
	float fStartSpeed;
	float fShotDelay;
	any aPadding[13];
}

enum struct SeqData_Groundshot_Down_PrepareRocketLauncher {
	float fReloadCompleteTime;
	any aPadding[15];
}

enum struct SeqData_Groundshot_Down {
	float fDelayOffset;
	bool bShot;
	any aPadding[14];
}

// Sorted by decreasing max distance on flat ground
static float g_fGroundShotParams[][] = {
//	  Delay    Vel2D     VelZ
	{0.0000, 323.1305, 928.9940},
	{0.0151, 254.5355, 892.3454},
	{0.0757, 272.5390, 767.2135},
	{0.1666, 284.3861, 643.0847},
	{0.5909, 287.5218, 428.9412},
	{0.6666, 261.8510, 424.6311},
	{0.6818, 216.6229, 424.8501},
	{0.7424, 149.8582, 392.7835}
};

#define CLOSE_RANGE_CUTOFF	300.0
#define MIN_START_SPEED		239.0

#define MIN_WALK_TIME		0.15
#define MIN_WALK_DISTANCE	25.0

// Operation callbacks

OpRet GroundShot_Down_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Groundshot_Down eOpData, bool bConfigureOnly) {
	int iEntity;

	if (!bConfigureOnly) {
		iEntity = mBot.iEntity;

		if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
			return mOp._Abort("unsupported TFClassType");
		}
	}

	float vecOrigin[3];

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GoBack();
		hInitParams.GetVector("origin", vecOrigin);
	} else if (bConfigureOnly) {
		return mOp._Abort("missing origin init parameter");
	} else {
		Entity_GetAbsOrigin(iEntity, vecOrigin);
	}

	if (!hInitParams.JumpToKey("destination")) {
		return mOp._Abort("missing destination init parameter");
	}

	hInitParams.GoBack();

	float vecDest[3];
	hInitParams.GetVector("destination", vecDest);

	float fHeadingAng;
	float fStartSpeed;
	float fShotDelay;

	bool bConfigured = !bConfigureOnly && hInitParams.JumpToKey(OP_INIT_CONFIG);
	if (bConfigured) {
		if (!hInitParams.JumpToKey("shot_delay")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing shot_delay config parameter");
		}

		fShotDelay = hInitParams.GetFloat(NULL_STRING);
		hInitParams.GoBack();

		if (fShotDelay < 0.0) {
			fShotDelay = 0.0;
		}

		if (!hInitParams.JumpToKey("start_speed")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing start_speed config parameter");
		}

		fStartSpeed = hInitParams.GetFloat(NULL_STRING);
		hInitParams.GoBack();

		if (!hInitParams.JumpToKey("heading")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing heading config parameter");
		}

		fHeadingAng = hInitParams.GetFloat(NULL_STRING);
		hInitParams.GoBack();

		hInitParams.GoBack(); // from OP_INIT_CONFIG
	} else {
		switch (FindParameters(vecOrigin, vecDest, fStartSpeed, fShotDelay, fHeadingAng)) {
			case -1: {
				hInitParams.GoBack(); // from OP_INIT_CONFIG
				return mOp._Abort("destination not reachable")
			}
			case -2: {
				hInitParams.GoBack(); // from OP_INIT_CONFIG
				return mOp._Abort("destination too close")
			}
		}

		hInitParams.JumpToKey(OP_INIT_CONFIG, true);
		hInitParams.SetFloat("start_speed", fStartSpeed);
		hInitParams.SetFloat("shot_delay", fShotDelay);
		hInitParams.SetFloat("heading", fHeadingAng);
		hInitParams.GoBack(); // from OP_INIT_CONFIG
	}

	if (bConfigureOnly) {
		return OpRet_Continue;
	}

	eOpData.fHeadingAng = fHeadingAng;
	eOpData.fStartSpeed = fStartSpeed;
	eOpData.fShotDelay = fShotDelay;

	Sequence eSeq;

	eSeq.fnRun = GroundShot_Down_PrepRocketLauncher;
	eSeq.sIdentifier = "Prep_Rocket_Launcher";
	hSequences.PushArray(eSeq);

	eSeq.fnRun = GroundShot_Down_Shoot_Ground;
	eSeq.iSeq = view_as<Seq>(1);
	eSeq.sIdentifier = "Shoot_Ground";
	hSequences.PushArray(eSeq);

	eSeq.fnRun = GroundShot_Down_Face_Heading;
	eSeq.iSeq = view_as<Seq>(2);
	eSeq.sIdentifier = "Face_Heading";
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

OpRet GroundShot_Down_PrepRocketLauncher(Bot mBot, Operation mOp, OpData_Groundshot_Down eOpData, SeqData_Groundshot_Down_PrepareRocketLauncher eSeqData, float fStartTime) {
	if (!fStartTime) {
		mBot.SwitchWeapon(TFWeaponSlot_Primary);
	}

	int iEntity = mBot.iEntity;

	int iPrimaryEntityIdx = GetPlayerWeaponSlot(iEntity, TFWeaponSlot_Primary);
	int iPrimaryAmmoType = GetEntProp(iPrimaryEntityIdx, Prop_Send, "m_iPrimaryAmmoType");
	int iPrimaryAmmo = GetEntProp(iEntity, Prop_Data, "m_iAmmo", 4, iPrimaryAmmoType);

	if (!iPrimaryAmmo) {
		return mOp._Abort("out of rocket ammo");
	}

	// TODO: Ideally, reload early to prevent running empty on launcher to prevent forced full-clip consecutive reloads
	float fTime = GetGameTime();
	float fNextAttackTime = GetEntPropFloat(iPrimaryEntityIdx, Prop_Send, "m_flNextPrimaryAttack");
	if (fNextAttackTime >= fTime || !GetEntProp(iPrimaryEntityIdx, Prop_Send, "m_iClip1")) {
		eSeqData.fReloadCompleteTime = fTime + 0.1;
	}

	if (eSeqData.fReloadCompleteTime < GetGameTime()) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet GroundShot_Down_Shoot_Ground(Bot mBot, Operation mOp, OpData_Groundshot_Down eOpData, SeqData_Groundshot_Down eSeqData, float fStartTime) {
	if (!fStartTime) {
		float vecAimAng[3];
		vecAimAng[0] = 89.0;
		vecAimAng[1] = eOpData.fHeadingAng;
		mBot.SetAimTo(vecAimAng);

		mBot.SetPID(PID_VFAST_PREC);
	}

	int iEntity = mBot.iEntity;

	float fPitchError, fYawError;
	mBot.GetAimError(fPitchError, fYawError);

	if (FloatAbs(fPitchError) < 1.0 && FloatAbs(fYawError) < 45.0) {
		float vecVel[3];
		Entity_GetAbsVelocity(iEntity, vecVel);

		float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);

		if (fVel2D >= eOpData.fStartSpeed || eSeqData.bShot) {
			if (eSeqData.fDelayOffset == 0) {
				eSeqData.fDelayOffset = GetGameTime() - fStartTime;
			}

			mBot.iButtons = IN_JUMP | IN_DUCK;
			mBot.SetLocalVelocity({0.0, 0.0, 0.0});

			float fShootTime = fStartTime + eSeqData.fDelayOffset + eOpData.fShotDelay;
			float fTime = GetGameTime();
			if (fTime >= fShootTime) {
				mBot.iButtons = IN_JUMP | IN_DUCK | IN_ATTACK | IN_RIGHT;
				mBot.SetLocalVelocity({0.0, 400.0, 0.0});

				eSeqData.bShot = true;

				// Wait for approx rocket travel time before blast
				if (fTime-fShootTime > ROCKET_BLAST_TIME) {
					return OpRet_Handled;
				}
			}

			return OpRet_Continue;
		}

		if (eOpData.fStartSpeed >= MIN_START_SPEED && fStartTime > 0 && GetGameTime()-fStartTime > 0.75) {
			return mOp._Abort("start impeded");
		}

		mBot.iButtons |= IN_FORWARD;
		mBot.SetLocalVelocity({400.0, 0.0, 0.0});
	}

	return OpRet_Continue;
}

OpRet GroundShot_Down_Face_Heading(Bot mBot, Operation mOp, OpData_Groundshot_Down eOpData, SeqData eSeqData, float fStartTime) {
	if (!fStartTime) {
		float vecAimAng[3];
		vecAimAng[1] = eOpData.fHeadingAng;

		mBot.SetAimTo(vecAimAng);
		mBot.SetPID(PID_FAST_PREC);
	}

	float fTime = GetGameTime();
	if (fStartTime && fTime-fStartTime > ROCKET_BLAST_TIME) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

// Helpers

static int FindParameters(float vecOrigin[3], float vecDest[3], float &fMinSpeed, float &fDelay, float &fHeadingAng) {
	float vecDiff[3];
	SubtractVectors(vecDest, vecOrigin, vecDiff);

	float fDist2D = SquareRoot(vecDiff[0]*vecDiff[0] + vecDiff[1]*vecDiff[1]);

	if (fDist2D < CLOSE_RANGE_CUTOFF) {
		if (vecDiff[2] < -50.0) {
			return -2;
		}

		if (FloatAbs(vecDiff[2]) < 50.0) {
			if (fDist2D < 150.0) {
				return -2;
			}

			float vecAimAng[3];
			GetVectorAngles(vecDiff, vecAimAng);

			fHeadingAng = vecAimAng[1];
			fMinSpeed = 150.0;
			fDelay = g_fGroundShotParams[4][0];

			return 0;
		}
	}

	float fGravity = -g_hCVGravity.FloatValue;

	float vecDir[3];
	vecDir[0] = vecDiff[0];
	vecDir[1] = vecDiff[1];
	NormalizeVector(vecDir, vecDir);

	float vecMins[3] = SOLDIER_MIN_BBOX;
	float vecMaxs[3] = SOLDIER_MAX_BBOX;

	float vecTraceStartPos[3];
	vecTraceStartPos[0] = vecOrigin[0];
	vecTraceStartPos[1] = vecOrigin[1];
	vecTraceStartPos[2] = vecOrigin[2] + 50.0;

	float vecWalkEndPos[3];
	vecWalkEndPos = vecDir;
	ScaleVector(vecWalkEndPos, MIN_WALK_DISTANCE);
	AddVectors(vecOrigin, vecWalkEndPos, vecWalkEndPos);

	int iGroundShotDownParamIdx = -1;
	for (int i=0; i<sizeof(g_fGroundShotParams); i++) {
		float vecWalkDelayEndPos[3];
		float fWalkTime = g_fGroundShotParams[i][0] + GROUND_START_TIME;

		ShiftGroundPosition2D(vecWalkEndPos, vecDir, MIN_START_SPEED, fWalkTime, vecWalkDelayEndPos);

		float vecTraceAng[3];
		SubtractVectors(vecWalkDelayEndPos, vecTraceStartPos, vecTraceAng);
		GetVectorAngles(vecTraceAng, vecTraceAng);

		TR_TraceRayFilter(vecTraceStartPos, vecTraceAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
		if (!TR_DidHit()) {
			break;
		}

		float vecTraceEndPos[3];
		TR_GetEndPosition(vecTraceEndPos);

		float fTraceDistance = GetVectorDistance(vecTraceStartPos, vecTraceEndPos);
		float fExpectedDistance = GetVectorDistance(vecTraceStartPos, vecWalkDelayEndPos);

		if (FloatAbs(fTraceDistance-fExpectedDistance) > 10.0) {
			break;
		}

		float fTime2D = fDist2D / g_fGroundShotParams[i][1];

		// d = v0*t + 0.5*g*t^2 = (v0 + 0.5*g*t)*t
		float fPredictedZ = vecOrigin[2] + (g_fGroundShotParams[i][2] + 0.5*fGravity*fTime2D)*fTime2D;

		if (fPredictedZ < vecDest[2]) {
			break;
		}

		iGroundShotDownParamIdx = i;
	}

	while (iGroundShotDownParamIdx >= 0) {
		float fTime2D = fDist2D / g_fGroundShotParams[iGroundShotDownParamIdx][1];

		float vecWalkDelayEndPos[3];
		float fWalkTime = g_fGroundShotParams[iGroundShotDownParamIdx][0] + GROUND_START_TIME;

		ShiftGroundPosition2D(vecWalkEndPos, vecDir, MIN_START_SPEED, fWalkTime, vecWalkDelayEndPos);

		if (CheckParabolicCollision(vecMins, vecMaxs, vecDir, fGravity, fTime2D, vecWalkDelayEndPos, g_fGroundShotParams[iGroundShotDownParamIdx][1], g_fGroundShotParams[iGroundShotDownParamIdx][2])) {
			iGroundShotDownParamIdx--;
			continue;
		}

		break;
	}

	if (iGroundShotDownParamIdx == -1) {
		return -1;
	}

#if defined DEBUG
	float fTime2D = fDist2D / g_fGroundShotParams[iGroundShotDownParamIdx][1];

	float vecWalkDelayEndPos[3];
	float fWalkTime = g_fGroundShotParams[iGroundShotDownParamIdx][0] + GROUND_START_TIME;

	ShiftGroundPosition2D(vecWalkEndPos, vecDir, MIN_START_SPEED, fWalkTime, vecWalkDelayEndPos);

	CheckParabolicCollision(vecMins, vecMaxs, vecDir, fGravity, fTime2D, vecWalkDelayEndPos, g_fGroundShotParams[iGroundShotDownParamIdx][1], g_fGroundShotParams[iGroundShotDownParamIdx][2], true);
#endif

	float vecAimAng[3];
	GetVectorAngles(vecDiff, vecAimAng);

	fHeadingAng = vecAimAng[1];
	fMinSpeed = MIN_START_SPEED;
	fDelay = g_fGroundShotParams[iGroundShotDownParamIdx][0];

	return 0;
}
