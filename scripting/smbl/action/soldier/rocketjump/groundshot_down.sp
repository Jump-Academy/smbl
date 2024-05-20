enum struct OpData_Groundshot_Down {
	float vecDest[3];
	any aPadding[13];
}

enum struct SeqData_Groundshot_Down_PrepareRocketLauncher {
	float fReloadCompleteTime;
	any aPadding[15];
}

enum struct SeqData_Groundshot_Down {
	float vecDest[3];
	float fHeadingAng;
	float fMinSpeed;
	float fDelay;
	float fDelayOffset;
	bool bShot;
	any aPadding[8];
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
#define ROCKET_BLAST_DELAY	0.2

#define MIN_WALK_TIME		0.15
#define MIN_WALK_DISTANCE	25.0

// Operation callbacks

OpRet GroundShot_Down_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Groundshot_Down eOpData) {
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

	eOpData.vecDest = vecDest;

	float vecDiff[3];
	SubtractVectors(vecDest, vecOrigin, vecDiff);

	float fDist2D = SquareRoot(vecDiff[0]*vecDiff[0] + vecDiff[1]*vecDiff[1]);

// 	PrintToChatAll("fDist2D=%.2f", fDist2D);

	// Check straight-down ground shot viability

	float fEntityGravityRatio = GetEntityGravity(iEntity);
	if (fEntityGravityRatio == 0.0) {
		fEntityGravityRatio = 1.0;
	}

	float fGravity = -g_hCVGravity.FloatValue * fEntityGravityRatio;

	float vecDir[3];
	vecDir[0] = vecDiff[0];
	vecDir[1] = vecDiff[1];
	NormalizeVector(vecDir, vecDir);

	if (fDist2D < CLOSE_RANGE_CUTOFF) {
		if (vecDiff[2] < -50.0) {
			return mOp._Abort("destination is too close");
		}


		if (FloatAbs(vecDiff[2]) < 50.0) {
			if (fDist2D < 150.0) {
				return mOp._Abort("destination is too close");
			}
			// TODO: Do weak straight-down rocket hop


// 			if (fDist2D < 50 + 100.0*(g_fGroundShotParams[5][0] + ROCKET_BLAST_DELAY)) {
// 				return mOp._Abort("destination is too close");
// 			}


			float vecAimAng[3];
			GetVectorAngles(vecDiff, vecAimAng);

			SeqData_Groundshot_Down eSeqData;
			eSeqData.vecDest = vecDest;
			eSeqData.fHeadingAng = vecAimAng[1];
			eSeqData.fMinSpeed = 150.0;
// 			eSeqData.fMinSpeed = MIN_START_SPEED;
// 			eSeqData.fDelay = g_fGroundShotParams[6][0];
			eSeqData.fDelay = g_fGroundShotParams[4][0];

			Sequence eSeq;
			eSeq.fnRun = GroundShot_Down_Shoot_Ground;
			eSeq.iSeq = view_as<Seq>(0);
			eSeq.SetData(eSeqData);
			eSeq.sIdentifier = "Shoot_Ground";
			hSequences.PushArray(eSeq);

			return OpRet_Continue;
		}
	}

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
// 		float fWalkTime = g_fGroundShotParams[i][0] + ROCKET_BLAST_DELAY;
		float fWalkTime = g_fGroundShotParams[i][0];
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

// 		PrintToChatAll("fTraceDistance=%.2f, fExpectedDistance=%.2f", fTraceDistance, fExpectedDistance);

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
// 		float fWalkTime = g_fGroundShotParams[iGroundShotDownParamIdx][0] + ROCKET_BLAST_DELAY;
		float fWalkTime = g_fGroundShotParams[iGroundShotDownParamIdx][0];
		ShiftGroundPosition2D(vecWalkEndPos, vecDir, MIN_START_SPEED, fWalkTime, vecWalkDelayEndPos);

		if (CheckParabolicCollision(vecDir, fGravity, fTime2D, vecWalkDelayEndPos, g_fGroundShotParams[iGroundShotDownParamIdx][1], g_fGroundShotParams[iGroundShotDownParamIdx][2])) {
			iGroundShotDownParamIdx--;
			continue;
		}
			
		break;
	}

	if (iGroundShotDownParamIdx == -1) {
// 		if (fDist2D < CLOSE_RANGE_CUTOFF) {
// 			return mOp._Abort("check wall");
// 		}

		return mOp._Abort("destination not reachable");
	}

// 	PrintToChatAll("GroundShot.Down idx=%d, delay=%.2f", iGroundShotDownParamIdx, g_fGroundShotParams[iGroundShotDownParamIdx][0]);

	float vecAimAng[3];
	GetVectorAngles(vecDiff, vecAimAng);

	SeqData_Groundshot_Down eSeqData;
	eSeqData.vecDest = vecDest;
	eSeqData.fHeadingAng = vecAimAng[1];
	eSeqData.fMinSpeed = MIN_START_SPEED;
	eSeqData.fDelay = g_fGroundShotParams[iGroundShotDownParamIdx][0];

	Sequence eSeq;

	eSeq.fnRun = GroundShot_Down_PrepRocketLauncher;
	eSeq.iSeq = view_as<Seq>(0);
	eSeq.sIdentifier = "Prep_Rocket_Launcher";
	hSequences.PushArray(eSeq);

	eSeq.fnRun = GroundShot_Down_Shoot_Ground;
	eSeq.iSeq = view_as<Seq>(1);
	eSeq.SetData(eSeqData);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Shoot_Ground");
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
// 	mBot.iButtons |= IN_FORWARD | IN_JUMP | IN_DUCK | IN_ATTACK;
// 	mBot.SetLocalVelocity({400.0, 0.0, 0.0});
	mBot.SetMoveTo(eSeqData.vecDest);

	float vecAimAng[3];
// 	mBot.GetAimTo(vecAimAng);
// 	vecAimAng[0] = 82.0;
	vecAimAng[0] = 89.0;
	vecAimAng[1] = eSeqData.fHeadingAng;
	mBot.SetAimTo(vecAimAng);

	mBot.SetPID(PID_VFAST_PREC);

// 	PrintToServer("RocketJump_Shoot_Ground vecAimAng=[%.1f %.1f %.1f]", eSeqData.vecWallAng[0], eSeqData.vecWallAng[1], eSeqData.vecWallAng[2]);

	int iEntity = mBot.iEntity;

	float fPitchError, fYawError;
	mBot.GetAimError(fPitchError, fYawError);

// 	PrintToChatAll("%N GroundShot_Down_Shoot_Ground fPitchError:%.2f", mBot.iEntity, fPitchError);

	if (FloatAbs(fPitchError) < 1.0 && FloatAbs(fYawError) < 45.0) {
		float vecVel[3];
		Entity_GetAbsVelocity(iEntity, vecVel);

		float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);
// 		PrintToServer("fDelay=%.2f (required: %.2f)", GetGameTime()-fStartTime, eSeqData.fDelay);

// 		if (GetVectorLength(vecVel) >= 239 || GetGameTime()-fStartTime > 0.3) {
		if (fVel2D >= eSeqData.fMinSpeed || eSeqData.bShot) {
// 			PrintToServer("%.2f: fDelay=%.2f (required: %.2f)", GetGameTime(), GetGameTime()-(fStartTime+eSeqData.fDelayOffset), eSeqData.fDelay);
// 			mBot.iButtons = IN_JUMP | IN_DUCK | IN_ATTACK | IN_RIGHT;
// 			mBot.SetLocalVelocity({0.0, 400.0, 0.0});
// 			return OpRet_Handled;

			if (eSeqData.fDelayOffset == 0) {
				eSeqData.fDelayOffset = GetGameTime()-fStartTime;
// 				PrintToServer("%.2f: Aim is now good, fDelayOffset=%.2f (delay now to %.2f)", GetGameTime(), eSeqData.fDelayOffset, GetGameTime()+eSeqData.fDelay+eSeqData.fDelayOffset);
			}

			mBot.iButtons = IN_JUMP | IN_DUCK;
			mBot.SetLocalVelocity({0.0, 0.0, 0.0});

			float fShootTime = fStartTime+eSeqData.fDelayOffset+eSeqData.fDelay;
			float fTime = GetGameTime();
			if (fTime >= fShootTime) {
// 			if (GetGameTime()-fStartTime >= eSeqData.fDelay) {
				mBot.iButtons = IN_JUMP | IN_DUCK | IN_ATTACK | IN_RIGHT;
				mBot.SetLocalVelocity({0.0, 400.0, 0.0});

				eSeqData.bShot = true;

// 				PrintToServer("Ground rocket | fTime=%.2f, fShootTime=%.2f (t-s=%.2f) >? RBD: %.2f", fTime, fShootTime, fTime-fShootTime, ROCKET_BLAST_DELAY);
				// Wait for approx rocket travel time before blast
				if (fTime-fShootTime > ROCKET_BLAST_DELAY) {
					return OpRet_Handled;
				}
			}

			return OpRet_Continue;
		}

		if (eSeqData.fMinSpeed >= MIN_START_SPEED && fStartTime > 0 && GetGameTime()-fStartTime > 0.75) {
			return mOp._Abort("start impeded");
		}

		mBot.iButtons |= IN_FORWARD;
		mBot.SetLocalVelocity({400.0, 0.0, 0.0});
	}

	return OpRet_Continue;
}

// Helpers

bool CheckParabolicCollision(float vecDir[3], float fGravity, float fTime, float vecStartPos[3], float fVel2D, float fVelZ_0, bool bDrawArc=false) {
// bool CheckParabolicCollision(float vecMins[3], float vecMaxs[3], float vecDir[3], float fGravity, float fTime, float vecStartPos[3], float fVel2D, float fVelZ_0, bool bDrawArc=false) {
	float vecLastPt[3];
	vecLastPt = vecStartPos;

	for (float fT=0.1; fT<=fTime; fT+=0.3) {
		float vecPt[3];
		vecPt[0] = vecStartPos[0] + vecDir[0]*fT*fVel2D;
		vecPt[1] = vecStartPos[1] + vecDir[1]*fT*fVel2D;
		vecPt[2] = vecStartPos[2] + fVelZ_0*fT + 0.5*fGravity*fT*fT;

		if (TR_PointOutsideWorld(vecPt)) {
			if (bDrawArc) {
				DrawDebugLine(vecLastPt, vecPt, COLOR_RED, 5.0);
			}

			return true;
		}

		TR_TraceRayFilter(vecLastPt, vecPt, MASK_SHOT_HULL, RayType_EndPoint, TraceEntityFilter_Environment);
// 		TR_TraceHullFilter(vecPos, vecPredictPos, vecMins, vecMaxs, MASK_SHOT_HULL, TraceEntityFilter_Environment);
		if (TR_DidHit()) {
			if (bDrawArc) {
				DrawDebugLine(vecLastPt, vecPt, COLOR_MAGENTA, 5.0);
			}
			return true;
		}

		if (bDrawArc) {
			DrawDebugLine(vecLastPt, vecPt, COLOR_YELLOW, 5.0);
		}

		vecLastPt = vecPt;
	}


	return false;
}

void ShiftGroundPosition2D(float vecStartPos[3], float vecDir[3], float fSpeed, float fTime, float vecEndPos[3]) {
	float fMoveDist = fSpeed*fTime;
	vecEndPos[0] = vecStartPos[0] + fMoveDist*vecDir[0];
	vecEndPos[1] = vecStartPos[1] + fMoveDist*vecDir[1];
	vecEndPos[2] = vecStartPos[2];
}
