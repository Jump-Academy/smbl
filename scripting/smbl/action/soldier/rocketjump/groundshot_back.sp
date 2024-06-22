enum struct OpData_Groundshot_Back {
	float vecStart[3];
	float vecDest[3];
	float fHeadingAng;
	float fShootPitchAng;
	float fShootYawAng;
	any aPadding[7];
}

enum struct SeqData_Groundshot_Back_PrepareRocketLauncher {
	float fReloadCompleteTime;
	any aPadding[15];
}

// Operation callbacks

OpRet GroundShot_Back_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Groundshot_Back eOpData, bool bConfigureOnly) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("unsupported TFClassType");
	}

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GetVector(NULL_STRING, eOpData.vecStart);
		hInitParams.GoBack();
	} else {
		Entity_GetAbsOrigin(mBot.iEntity, eOpData.vecStart);
	}

	if (!hInitParams.JumpToKey("destination")) {
		return mOp._Abort("missing destination init parameter");
	}

	hInitParams.GetVector(NULL_STRING, eOpData.vecDest);
	hInitParams.GoBack();

	bool bStandingLaunch = hInitParams.GetNum("standing_launch", false) != 0;

	float fPitchAng;
	float fYawAng;
	float fHeadingAng;

	bool bConfigured = !bConfigureOnly && hInitParams.JumpToKey(OP_INIT_CONFIG);
	if (bConfigured) {
		if (!hInitParams.JumpToKey("pitch")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing pitch config parameter");
		}

		fPitchAng = hInitParams.GetFloat(NULL_STRING);
		hInitParams.GoBack();

		if (!hInitParams.JumpToKey("yaw")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing yaw config parameter");
		}

		fYawAng = hInitParams.GetFloat(NULL_STRING);
		hInitParams.GoBack();

		if (!hInitParams.JumpToKey("heading")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing heading config parameter");
		}

		fHeadingAng = hInitParams.GetFloat(NULL_STRING);
		hInitParams.GoBack();

		if (!hInitParams.JumpToKey("standing_launch")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing standing_launch config parameter");
		}

		// overrides init param
		bStandingLaunch = hInitParams.GetNum(NULL_STRING, bStandingLaunch) != 0;
		hInitParams.GoBack();

		hInitParams.GoBack(); // from OP_INIT_CONFIG
	} else {
		if (FindParameters(iEntity, eOpData.vecStart, eOpData.vecDest, fPitchAng, fYawAng, fHeadingAng, bStandingLaunch) == -1) {
			return mOp._Abort("destination not reachable");
		}

		hInitParams.JumpToKey(OP_INIT_CONFIG, true);
		hInitParams.SetFloat("pitch", fPitchAng);
		hInitParams.SetFloat("yaw", fYawAng);
		hInitParams.SetFloat("heading", fHeadingAng);
		hInitParams.SetNum("standing_launch", bStandingLaunch);
		hInitParams.GoBack(); // from OP_INIT_CONFIG
	}

	if (bConfigureOnly) {
		return OpRet_Continue;
	}

	eOpData.fHeadingAng = fHeadingAng;
	eOpData.fShootPitchAng = fPitchAng;
	eOpData.fShootYawAng = fYawAng;

	Sequence eSeq;

	eSeq.fnRun = GroundShot_Back_PrepRocketLauncher;
	eSeq.sIdentifier = "Prep_Rocket_Launcher";
	hSequences.PushArray(eSeq);

	eSeq.iSeq = view_as<Seq>(1);

	if (bStandingLaunch) {
		eSeq.fnRun = GroundShot_Back_Start_Stand;
		eSeq.sIdentifier = "Start_Stand";
	} else {
		eSeq.fnRun = GroundShot_Back_Start_Walk;
		eSeq.sIdentifier = "Start_Walk";
	}

	hSequences.PushArray(eSeq);

	eSeq.fnRun = GroundShot_Back_Shoot_Ground;
	eSeq.iSeq = view_as<Seq>(2);
	eSeq.sIdentifier = "Shoot_Ground";
	hSequences.PushArray(eSeq);

	eSeq.fnRun = GroundShot_Back_Face_Heading;
	eSeq.iSeq = view_as<Seq>(3);
	eSeq.sIdentifier = "Face_Heading";
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

// Sequences

OpRet GroundShot_Back_PrepRocketLauncher(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData_Groundshot_Back_PrepareRocketLauncher eSeqData, float fStartTime) {
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

	// TODO: Ideally, reload early to prevent running empty on launcher and avoid forced full-clip consecutive reloads
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

OpRet GroundShot_Back_Start_Stand(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData eSeqData, float fStartTime) {
	if (!fStartTime) {
		float vecAimAng[3];
		mBot.GetAimTo(vecAimAng);
		vecAimAng[1] = eOpData.fShootYawAng;
		mBot.SetAimTo(vecAimAng);
		mBot.SetPID(PID_FAST);
	}

	float fYawError;
	mBot.GetAimError(_, fYawError);

	if (FloatAbs(fYawError) < 5.0) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet GroundShot_Back_Start_Walk(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData eSeqData, float fStartTime) {
	if (!fStartTime) {
		float vecAimAng[3];
		vecAimAng[0] = eOpData.fShootPitchAng;
		vecAimAng[1] = NormalizeAngle(eOpData.fHeadingAng - 90.0);
		mBot.SetAimTo(vecAimAng);
		mBot.SetPID(PID_VFAST_PREC);
	}

	float fYawError;
	mBot.GetAimError(_, fYawError);

	if (FloatAbs(fYawError) < 1.0) {
		mBot.iButtons |= IN_LEFT;
		mBot.SetLocalVelocity({0.0, -400.0, 0.0});

		float vecVel[3];
		Entity_GetAbsVelocity(mBot.iEntity, vecVel);

		float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);

		if (fVel2D > MIN_START_SPEED) {
			float vecVelAng[3];
			GetVectorAngles(vecVel, vecVelAng);

			float fAngDiff;
			GetAngDiff(vecVelAng[1], eOpData.fHeadingAng, fAngDiff);

			if (FloatAbs(fAngDiff) < 15.0) {
				return OpRet_Handled;
			}
		}
	}

	if (fStartTime && GetGameTime()-fStartTime > 0.5) {
		return mOp._Abort("start impeded");
	}

	return OpRet_Continue;
}

OpRet GroundShot_Back_Shoot_Ground(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData eSeqData, float fStartTime) {
	if (!fStartTime) {
		float vecAimAng[3];
		vecAimAng[0] = eOpData.fShootPitchAng;
		vecAimAng[1] = eOpData.fShootYawAng;
		mBot.SetAimTo(vecAimAng);
		mBot.SetPID(PID_SNAP);
		mBot.iButtons = 0;
		mBot.SetLocalVelocity({0.0, 0.0, 0.0});
	}

	float fPitchError, fYawError;
	mBot.GetAimError(fPitchError, fYawError);

	if (FloatAbs(fPitchError) < 1.0 && FloatAbs(fYawError) < 1.0) {
		mBot.iButtons = IN_JUMP | IN_DUCK | IN_ATTACK;

		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet GroundShot_Back_Face_Heading(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData eSeqData, float fStartTime) {
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

static float GetInitialVel2D(float fPitchAng) {
	float fX  = fPitchAng;
	float fX2 = fX*fX;
	float fX3 = fX2*fX;
	float fX4 = fX3*fX;
	float fX5 = fX4*fX;

	// Coefficients for 1 tick delay between jump and shoot
	return \
		-131.62623492 * fX \
		+4.68495106  * fX2 \
		-0.07703477  * fX3 \
		+0.00058851  * fX4 \
		-0.00000172  * fX5 \
		+1699.365006059887;
}

static float GetInitialVelZ(float fPitchAng) {
	// Coefficients for 1 tick delay between jump and shoot
	return \
		 21.16759727 * fPitchAng \
		-0.10122961  * fPitchAng*fPitchAng \
		-191.58256250650533;
}

static float GetYawAngleCompensation(float fPitchAng) {
	float fX  = fPitchAng;
	float fX2 = fX*fX;
	float fX3 = fX2*fX;
	float fX4 = fX3*fX;
	float fX5 = fX4*fX;

	return \
		14.10738620 * fX \
		-0.54216773  * fX2 \
		+0.01036420  * fX3 \
		-0.00009752  * fX4 \
		+0.00000037  * fX5  \
		-141.3442763196645;
}

static int FindParameters(int iEntity, float vecOrigin[3], float vecDest[3], float &fPitchAng, float &fYawAng, float &fHeadingAng, bool &bStandingLaunch) {
	float vecDiff[3];
	SubtractVectors(vecDest, vecOrigin, vecDiff);

	float fDist2D = SquareRoot(vecDiff[0]*vecDiff[0] + vecDiff[1]*vecDiff[1]);

	float vecDir[3];
	vecDir[0] = vecDiff[0];
	vecDir[1] = vecDiff[1];
	NormalizeVector(vecDir, vecDir);

	float vecAng[3];
	GetVectorAngles(vecDir, vecAng);

	float vecWalkEndPos[3];

	if (bStandingLaunch) {
		vecWalkEndPos = vecOrigin;
	} else {
		ShiftGroundPosition2D(vecOrigin, vecDir, MIN_START_SPEED, GROUND_START_TIME, vecWalkEndPos);

		float vecTraceStartPos[3];
		vecTraceStartPos[0] = vecOrigin[0];
		vecTraceStartPos[1] = vecOrigin[1];
		vecTraceStartPos[2] = vecOrigin[2] + 50.0;

		float vecTraceAng[3];
		SubtractVectors(vecWalkEndPos, vecTraceStartPos, vecTraceAng);
		GetVectorAngles(vecTraceAng, vecTraceAng);

		TR_TraceRayFilter(vecTraceStartPos, vecTraceAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
		if (TR_DidHit()) {
			float vecTraceEndPos[3];
			TR_GetEndPosition(vecTraceEndPos);

			float fTraceDistance = GetVectorDistance(vecTraceStartPos, vecTraceEndPos);
			float fExpectedDistance = GetVectorDistance(vecTraceStartPos, vecWalkEndPos);

			if (FloatAbs(fTraceDistance-fExpectedDistance) > 10.0) {
#if defined DEBUG
				PrintToServer("Bot is too close to a ledge. Trying standing launch instead.");
#endif
				bStandingLaunch = true;
				vecWalkEndPos = vecOrigin;
			}
		}
	}

	float fEntityGravityRatio = GetEntityGravity(iEntity);
	if (fEntityGravityRatio == 0.0) {
		fEntityGravityRatio = 1.0;
	}

	float fGravity = -g_hCVGravity.FloatValue * fEntityGravityRatio;

	float vecMins[3], vecMaxs[3];
	Entity_GetMinSize(iEntity, vecMins);
	Entity_GetMaxSize(iEntity, vecMaxs);

	float vecTraceStartPos[3];
	vecTraceStartPos = vecOrigin;
	vecTraceStartPos[2] += 0.75*vecMaxs[2];

	float fTimestamp = GetEngineTime();

	float fBestPitchAng;
	float fBestVel2D;

	float fGroundStartSpeed = bStandingLaunch ? 0.0 : MIN_START_SPEED;

	for (float fTestPitchAng=35.0; fTestPitchAng<90.0; fTestPitchAng+=5.0) {
		float fInitialVel2D = fGroundStartSpeed + GetInitialVel2D(fTestPitchAng);

		float fTime2D = fDist2D / fInitialVel2D;

		float fInitialVelZ = GetInitialVelZ(fTestPitchAng);

		// d = v0*t + 0.5*g*t^2 = (v0 + 0.5*g*t)*t
		float fPredictedZ = vecWalkEndPos[2] + (fInitialVelZ + 0.5*fGravity*fTime2D)*fTime2D;

		// vf = v0 + g*t
		float fPredictedVelZ = fInitialVelZ + fGravity*fTime2D;

#if defined DEBUG
		PrintToServer("Trying pitch=%.2f | vel2d: %.2f, velz: %.2f | predictedvelz: %.2f, predictedz err: %.2f", fTestPitchAng, fInitialVel2D, fInitialVelZ, fPredictedVelZ, fPredictedZ-vecDest[2]);
#endif

		if (fPredictedZ < vecDest[2]) {
#if defined DEBUG
			PrintToServer("\tFailed z-test: predictz: %.2f, destz: %.2f", fPredictedZ, vecDest[2]);
#endif
			continue;
		}

		if (CheckParabolicCollision(vecMins, vecMaxs, vecDir, fGravity, fTime2D, vecWalkEndPos, fInitialVel2D, fInitialVelZ)) {
#if defined DEBUG
			PrintToServer("\tFailed parabolic check");
#endif
			continue;
		}

		float vecTraceRocketAng[3];
		vecTraceRocketAng[0] = fTestPitchAng;
		vecTraceRocketAng[1] = NormalizeAngle(vecAng[1] + 180.0 + GetYawAngleCompensation(fTestPitchAng));

		float vecFwd[3], vecRight[3], vecUp[3];
		GetAngleVectors(vecTraceRocketAng, vecFwd, vecRight, vecUp);

		ScaleVector(vecRight, 12.0);

		float vecLauncherPos[3];
		AddVectors(vecTraceStartPos, vecRight, vecLauncherPos);

		TR_TraceRayFilter(vecLauncherPos, vecTraceRocketAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
		if (TR_DidHit()) {
			float vecTraceEndPos[3];
			TR_GetEndPosition(vecTraceEndPos);

			// Rocket misses nearby ground
			if (FloatAbs(vecTraceEndPos[2]-vecWalkEndPos[2]) > 10.0) {
#if defined DEBUG
				PrintToServer("\tRocket will miss ground");
#endif
				continue;
			}
		}

#if defined DEBUG
		PrintToServer("\tPassed");
#endif

		if (fInitialVel2D < fBestVel2D) {
			break;
		}

#if defined DEBUG
		PrintToServer("\tNew best");
#endif

		fBestVel2D = fInitialVel2D;
		fBestPitchAng = fTestPitchAng;
	}

#if defined DEBUG
	PrintToServer("Traces completed in %.3f ms", 1000*(GetEngineTime()-fTimestamp));
#endif

	if (!fBestPitchAng) {
		return -1;
	}

#if defined DEBUG
	float fInitialVel2D = fGroundStartSpeed + GetInitialVel2D(fBestPitchAng);
	float fTime2D = fDist2D / fInitialVel2D;
	float fInitialVelZ = GetInitialVelZ(fBestPitchAng);
	CheckParabolicCollision(vecMins, vecMaxs, vecDir, fGravity, fTime2D, vecWalkEndPos, fInitialVel2D, fInitialVelZ, true);

	PrintToServer("Found best pitch angle: %.2f with vel %.2f", fBestPitchAng, fBestVel2D);
#endif

	fPitchAng = fBestPitchAng;
	fYawAng = NormalizeAngle(vecAng[1] + 180.0 + GetYawAngleCompensation(fBestPitchAng));
	fHeadingAng = vecAng[1];

	return 0;
}
