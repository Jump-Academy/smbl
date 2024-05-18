enum struct OpData_Groundshot_Back {
	float vecStart[3];
	float vecDest[3];
	any aPadding[10];
// 	any aPadding[13];
}

enum struct SeqData_Groundshot_Back_PrepareRocketLauncher {
	float fReloadCompleteTime;
	any aPadding[15];
}
enum struct SeqData_Groundshot_Back {
	float vecDest[3];
	float fHeadingAng;
	float fShootPitchAng;
	float fShootYawAng;
	any aPadding[10];
}

#define CLOSE_RANGE_CUTOFF	300.0
#define MIN_START_SPEED		239.0
#define ROCKET_BLAST_DELAY	0.2

#define MIN_WALK_TIME		0.15
#define MIN_WALK_DISTANCE	25.0

// Operation callbacks

OpRet GroundShot_Back_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Groundshot_Back eOpData) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("unsupported TFClassType");
	}

	if (!hInitParams.JumpToKey("destination")) {
		return mOp._Abort("missing destination init parameter");
	}

	float vecOrigin[3], vecDest[3];

	hInitParams.GoBack();
	hInitParams.GetVector("destination", vecDest);

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GoBack();
		hInitParams.GetVector("origin", vecOrigin);
	} else {
		Entity_GetAbsOrigin(mBot.iEntity, vecOrigin);
	}

	eOpData.vecStart = vecOrigin;

	eOpData.vecDest = vecDest;

	float vecDiff[3];
	SubtractVectors(vecDest, vecOrigin, vecDiff);

	float fDist2D = SquareRoot(vecDiff[0]*vecDiff[0] + vecDiff[1]*vecDiff[1]);

	float fEntityGravityRatio = GetEntityGravity(iEntity);
	if (fEntityGravityRatio == 0.0) {
		fEntityGravityRatio = 1.0;
	}

	float fGravity = -g_hCVGravity.FloatValue * fEntityGravityRatio;

	float vecDir[3];
	vecDir[0] = vecDiff[0];
	vecDir[1] = vecDiff[1];
	NormalizeVector(vecDir, vecDir);

	float vecTraceStartPos[3];
	vecTraceStartPos[0] = vecOrigin[0];
	vecTraceStartPos[1] = vecOrigin[1];
	vecTraceStartPos[2] = vecOrigin[2] + 50.0;

	float vecWalkEndPos[3];
	vecWalkEndPos = vecDir;
	ScaleVector(vecWalkEndPos, MIN_WALK_DISTANCE);
	AddVectors(vecOrigin, vecWalkEndPos, vecWalkEndPos);
// 	float fWalkTime = MIN_WALK_TIME + ROCKET_BLAST_DELAY;
// 	float fWalkTime = ROCKET_BLAST_DELAY;
// 	ShiftGroundPosition2D(vecWalkEndPos, vecDir, MIN_START_SPEED, fWalkTime, vecWalkEndPos);

	float vecTraceAng[3];
	SubtractVectors(vecWalkEndPos, vecTraceStartPos, vecTraceAng);
	GetVectorAngles(vecTraceAng, vecTraceAng);

	bool bStandingLaunch;

	TR_TraceRayFilter(vecTraceStartPos, vecTraceAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
	if (TR_DidHit()) {
		float vecTraceEndPos[3];
		TR_GetEndPosition(vecTraceEndPos);

		float fTraceDistance = GetVectorDistance(vecTraceStartPos, vecTraceEndPos);
		float fExpectedDistance = GetVectorDistance(vecTraceStartPos, vecWalkEndPos);

// 		PrintToChatAll("fTraceDistance=%.2f, fExpectedDistance=%.2f", fTraceDistance, fExpectedDistance);

		if (FloatAbs(fTraceDistance-fExpectedDistance) > 10.0) {
			PrintToServer("Bot is too close to a ledge. Trying standing launch instead.");
			bStandingLaunch = true;
		}
	}

	// FIXME: Rocket launcher position
// 	GetClientEyePosition(iEntity, vecTraceStartPos);
	vecTraceStartPos = vecOrigin;
	vecTraceStartPos[2] += 200.0;

	float fTimestamp = GetEngineTime();

	float fBestPitchAng;
	float fBestVel2D;

	for (float fPitchAng=30.0; fPitchAng<90.0; fPitchAng+=5.0) {
		float fInitialVel2D = (bStandingLaunch ? 0.0 : MIN_START_SPEED) + GetInitialVel2D(fPitchAng);

		float fTime2D = fDist2D / fInitialVel2D;

		float fInitialVelZ = GetInitialVelZ(fPitchAng);

		// d = v0*t + 0.5*g*t^2 = (v0 + 0.5*g*t)*t
		float fPredictedZ = vecWalkEndPos[2] + (fInitialVelZ + 0.5*fGravity*fTime2D)*fTime2D;

		// vf = v0 + g*t
		float fPredictedVelZ = fInitialVelZ + fGravity*fTime2D;

		PrintToServer("Trying pitch=%.2f | vel2d: %.2f, velz: %.2f | predictedvelz: %.2f, predictedz err: %.2f", fPitchAng, fInitialVel2D, fInitialVelZ, fPredictedVelZ, fPredictedZ-vecDest[2]);


// 		if (fZPredict < vecDest[2]-50.0 && fVelPredict < 0) {
		//if (fPredictedZ < vecDest[2] && fPredictedVelZ < 0) {
		if (fPredictedZ < vecDest[2]) {
			PrintToServer("\tFailed z-test: predictz: %.2f, destz: %.2f", fPredictedZ, vecDest[2]);
			continue;
		}

		if (CheckParabolicCollision(vecDir, fGravity, fTime2D, vecWalkEndPos, fInitialVel2D, fInitialVelZ)) {
			PrintToServer("\tFailed parabolic check");
			continue;
		}

		float vecTraceRocketAng[3];
		vecTraceRocketAng[0] = fPitchAng;
		vecTraceRocketAng[1] = NormalizeAngle(vecTraceAng[1] + 180.0 + 90.0 - GetYawAngleCompensation(fPitchAng));

		TR_TraceRayFilter(vecTraceStartPos, vecTraceRocketAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
		if (TR_DidHit()) {
			float vecTraceEndPos[3];
			TR_GetEndPosition(vecTraceEndPos);

			// Rocket misses nearby ground
			if (FloatAbs(vecTraceEndPos[2]-vecWalkEndPos[2]) > 10.0) {
				PrintToServer("\tRocket will miss ground");
				continue;
			}
		}

		PrintToServer("\tPassed");

		if (fInitialVel2D < fBestVel2D) {
			break;
		}

		PrintToServer("\tNew best");
		fBestVel2D = fInitialVel2D;
		fBestPitchAng = fPitchAng;
	}

	PrintToServer("Traces completed in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

	if (!fBestPitchAng) {
		return mOp._Abort("destination not reachable");
	}

// 	float fInitialVel2D = MIN_START_SPEED + GetInitialVel2D(fBestPitchAng);
// 	float fTime2D = fDist2D / fInitialVel2D;
// 	float fInitialVelZ = GetInitialVelZ(fBestPitchAng);
// 	CheckParabolicCollision(vecDir, fGravity, fTime2D, vecWalkEndPos, fInitialVel2D, fInitialVelZ, true)

	PrintToServer("Found best pitch angle: %.2f with vel %.2f", fBestPitchAng, fBestVel2D);


	SeqData_Groundshot_Back eSeqData;
	eSeqData.vecDest = vecDest;
	eSeqData.fHeadingAng = vecTraceAng[1];
	eSeqData.fShootPitchAng = fBestPitchAng;
	eSeqData.fShootYawAng = NormalizeAngle(vecTraceAng[1] + 180.0 + 90.0 - GetYawAngleCompensation(fBestPitchAng));

	Sequence eSeq;

	eSeq.fnRun = GroundShot_Back_PrepRocketLauncher;
	eSeq.iSeq = view_as<Seq>(0);
	eSeq.sIdentifier = "Prep_Rocket_Launcher";
	hSequences.PushArray(eSeq);

	if (bStandingLaunch) {
		eSeq.fnRun = GroundShot_Back_Start_Stand;
		eSeq.iSeq = view_as<Seq>(1);
		eSeq.SetData(eSeqData);
		eSeq.sIdentifier = "Start_Stand";
		hSequences.PushArray(eSeq);
	} else {
		eSeq.fnRun = GroundShot_Back_Start_Walk;
		eSeq.iSeq = view_as<Seq>(1);
		eSeq.SetData(eSeqData);
		eSeq.sIdentifier = "Start_Walk";
		hSequences.PushArray(eSeq);
	}

	eSeq.fnRun = GroundShot_Back_Shoot_Ground;
	eSeq.iSeq = view_as<Seq>(2);
	eSeq.SetData(eSeqData);
	eSeq.sIdentifier = "Shoot_Ground";
	hSequences.PushArray(eSeq);

	eSeq.fnRun = GroundShot_Back_Face_Heading;
	eSeq.iSeq = view_as<Seq>(3);
	eSeq.SetData(eSeqData);
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

OpRet GroundShot_Back_Start_Stand(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData_Groundshot_Back eSeqData, float fStartTime) {
	float vecAimAng[3];
	mBot.GetAimTo(vecAimAng);
	vecAimAng[1] = eSeqData.fShootYawAng;
	mBot.SetAimTo(vecAimAng);
	mBot.SetPID(PID_VFAST_PREC);

	float fYawError;
	mBot.GetAimError(_, fYawError);

	if (FloatAbs(fYawError) < 1.0) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet GroundShot_Back_Start_Walk(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData_Groundshot_Back eSeqData, float fStartTime) {
	float vecAimAng[3];
	mBot.GetAimTo(vecAimAng);
	vecAimAng[1] = NormalizeAngle(eSeqData.fHeadingAng - 90.0);
	mBot.SetAimTo(vecAimAng);
	mBot.SetPID(PID_VFAST_PREC);

	float vecVel[3];
	Entity_GetAbsVelocity(mBot.iEntity, vecVel);

	float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);

	float vecPos[3];
	Entity_GetAbsOrigin(mBot.iEntity, vecPos);

	float fTime = fStartTime ? GetGameTime()-fStartTime : 0.0;
	PrintToServer("fTime: %.2f, vel2D: %.2f, dist=%.2f", fTime, fVel2D, GetVectorDistance(vecPos, eOpData.vecStart));

// 	mBot.iButtons |= IN_FORWARD;
// 	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	mBot.iButtons |= IN_LEFT;
	mBot.SetLocalVelocity({0.0, -400.0, 0.0});

	float fYawError;
	mBot.GetAimError(_, fYawError);

	if (fVel2D > MIN_START_SPEED && FloatAbs(fYawError) < 1.0) {
		return OpRet_Handled;
	}

	if (fStartTime && GetGameTime()-fStartTime > 0.3) {
		return mOp._Abort("start impeded");
	}

	return OpRet_Continue;
}

OpRet GroundShot_Back_Shoot_Ground(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData_Groundshot_Back eSeqData, float fStartTime) {
	float vecAimAng[3];
	vecAimAng[0] = eSeqData.fShootPitchAng;
	vecAimAng[1] = eSeqData.fShootYawAng;
	mBot.SetAimTo(vecAimAng);
	mBot.SetPID(PID_SNAP);

	float fPitchError, fYawError;
	mBot.GetAimError(fPitchError, fYawError);

// 	mBot.iButtons = IN_JUMP | IN_DUCK | IN_ATTACK;
	mBot.SetLocalVelocity({0.0, 0.0, 0.0});

// 	float fTime = GetGameTime();
// 	if (fStartTime && fTime-fStartTime > ROCKET_BLAST_DELAY) {
// 		return OpRet_Handled;
// 	}

	if (FloatAbs(fPitchError) < 1.0 && FloatAbs(fYawError) < 1.0) {
		mBot.iButtons = IN_JUMP | IN_DUCK | IN_ATTACK;
// // 		mBot.iButtons = IN_JUMP | IN_DUCK;

		return OpRet_Handled;
	}

	return OpRet_Continue;
// 	return OpRet_Handled;
}

OpRet GroundShot_Back_Face_Heading(Bot mBot, Operation mOp, OpData_Groundshot_Back eOpData, SeqData_Groundshot_Back eSeqData, float fStartTime) {
	float vecPos[3];
	Entity_GetAbsOrigin(mBot.iEntity, vecPos);

	float vecDiff[3];
	SubtractVectors(eOpData.vecDest, vecPos, vecDiff);

	float vecAimAng[3];
	GetVectorAngles(vecDiff, vecAimAng);

	mBot.SetAimTo(vecAimAng);
	mBot.SetPID(PID_FAST);

	float fTime = GetGameTime();
	if (fStartTime && fTime-fStartTime > ROCKET_BLAST_DELAY) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

// Helpers

float GetInitialVel2D(float fPitchAng) {
	float fX  = fPitchAng;
	float fX2 = fX*fX;
	float fX3 = fX2*fX;
	float fX4 = fX3*fX;
	float fX5 = fX4*fX;

// delay0
/*
	return \
		-94.14193058 * fX \
		+3.66023376  * fX2 \
		-0.06304769  * fX3 \
		+0.00047658  * fX4 \
		-0.00000128  * fX5 \
		+1205.2901552518301;
*/

	// delay1
	return \
		-131.62623492 * fX \
		+4.68495106  * fX2 \
		-0.07703477  * fX3 \
		+0.00058851  * fX4 \
		-0.00000172  * fX5 \
		+1699.365006059887;
}

float GetInitialVelZ(float fPitchAng) {
	// delay0
/*
	return \
		 22.60315843 * fPitchAng \
		-0.11758572  * fPitchAng*fPitchAng \
		-140.50038391612662;
*/

	// delay1
	return \
		 21.16759727 * fPitchAng \
		-0.10122961  * fPitchAng*fPitchAng \
		-191.58256250650533;
}

float GetYawAngleCompensation(float fPitchAng) {
	float fX  = fPitchAng;
	float fX2 = fX*fX;
	float fX3 = fX2*fX;
	float fX4 = fX3*fX;
	float fX5 = fX4*fX;

	return \
		-14.10738620 * fX \
		+0.54216773  * fX2 \
		-0.01036420  * fX3 \ 
		+0.00009752  * fX4 \
		-0.00000037  * fX5  \
		+231.3442763196645;
}
