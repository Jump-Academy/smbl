enum RocketJumpType {
	RocketJumpType_Ground_Shot_Back,
	RocketJumpType_Ground_Shot_Down
}

char g_sRocketJumpIdentifiers[][] = {
	"Soldier.Move.RocketJump.Ground.Shot.Back",
	"Soldier.Move.RocketJump.Ground.Shot.Down"
};

// Operation callbacks

OpRet Ground_Shot_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_RocketJump eOpData, bool bConfigureOnly) {
	int iEntity;

	if (!bConfigureOnly) {
		iEntity = mBot.iEntity;

		if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
			return mOp._Abort("unsupported TFClassType");
		}
	}

	int iFollowEntity;
	float fFollowDistance;
	float fFollowZOffset;

	if (hInitParams.JumpToKey("follow")) {
		iFollowEntity = hInitParams.GetNum(NULL_STRING);
		hInitParams.GoBack();
		fFollowDistance = hInitParams.GetFloat("follow_distance", 0.0);
		fFollowZOffset = hInitParams.GetFloat("follow_zoffset", 0.0);

		if (!IsValidEntity(iFollowEntity)) {
			return mOp._Abort("invalid follow entity");
		}
	}

	float vecDest[3];

	if (!hInitParams.JumpToKey("destination")) {
		if (!iFollowEntity) {
			return mOp._Abort("missing destination init parameter");
		}
	} else {
		hInitParams.GetVector(NULL_STRING, vecDest);
		hInitParams.GoBack();
	}

	float vecOrigin[3];

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GetVector(NULL_STRING, vecOrigin);
		hInitParams.GoBack();
	} else if (bConfigureOnly) {
		return mOp._Abort("missing origin init parameter");
	} else {
		float vecVel[3];
		Entity_GetAbsVelocity(iEntity, vecVel);
		// Wait until bot is stopped on ground before initializing
		if (!(GetEntityFlags(iEntity) & FL_ONGROUND) || GetVectorLength(vecVel) > 150.0) {
			return OpRet_Bypass;
		}

		Entity_GetAbsOrigin(mBot.iEntity, vecOrigin);
	}

	bool bStandingLaunch = hInitParams.GetNum("standing_launch", false) != 0;

	float fGoalProximity = hInitParams.GetFloat("goal_proximity", DEFAULT_GOAL_PROXIMITY);
	bool bAirBrake = hInitParams.GetNum("airbrake", false) != 0;

	if (iFollowEntity) {
		float vecFollowVel[3];
		Entity_GetAbsVelocity(iFollowEntity, vecFollowVel);

		float vecPredictShift[3];
		vecPredictShift = vecFollowVel;
		vecPredictShift[2] = 0.0; // 2D shifts only
		ScaleVector(vecPredictShift, PREDICT_TIME);
		AddVectors(vecDest, vecPredictShift, vecDest);

		if (fFollowDistance > 0.0) {
			float vecVector[3];
			SubtractVectors(vecDest, vecOrigin, vecVector);
			vecVector[2] = 0.0; // Only consider 2D distance
			NormalizeVector(vecVector, vecVector);

			ScaleVector(vecVector, fFollowDistance);
			SubtractVectors(vecDest, vecVector, vecDest);
		}
	}

	bool bHeightPriority = hInitParams.GetNum("height_priority", false) != 0;

	bool bConfigured = !bConfigureOnly && hInitParams.JumpToKey(OP_INIT_CONFIG);
	if (bConfigured) {
		char sIdentifier[64];
		hInitParams.GetString("rocketjump_identifier", sIdentifier, sizeof(sIdentifier));

		if (!sIdentifier[0]) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing rocketjump_identifier config parameter");
		}

		if (!hInitParams.JumpToKey("rocketjump_params")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing rocketjump_params config parameter");
		}

		// Must use real-time origin to calculate updated heading
		Entity_GetAbsOrigin(iEntity, vecOrigin);

		float vecDiff[3];
		SubtractVectors(vecDest, vecOrigin, vecDiff);

		NormalizeVector(vecDiff, vecDiff);

		float vecAng[3];
		GetVectorAngles(vecDiff, vecAng);

		KeyValues hGroundShotInitParams;
		Operation mGroundShotOp = Operation.Instance(sIdentifier, hGroundShotInitParams);

		hGroundShotInitParams.SetVector("origin", vecOrigin);
		hGroundShotInitParams.SetVector("destination", vecDest);

		hGroundShotInitParams.JumpToKey(OP_INIT_CONFIG, true);
		hGroundShotInitParams.SetFloat("heading", vecAng[1]);

		if (StrEqual(sIdentifier, g_sRocketJumpIdentifiers[RocketJumpType_Ground_Shot_Down])) {
			hGroundShotInitParams.SetFloat("start_speed", hInitParams.GetFloat("start_speed"));
			hGroundShotInitParams.SetFloat("shot_delay", hInitParams.GetFloat("shot_delay"));
		} else if (StrEqual(sIdentifier, g_sRocketJumpIdentifiers[RocketJumpType_Ground_Shot_Back])) {
			hGroundShotInitParams.SetFloat("yaw", hInitParams.GetFloat("yaw"));
			hGroundShotInitParams.SetFloat("pitch", hInitParams.GetFloat("pitch"));
			hGroundShotInitParams.SetNum("standing_launch", hInitParams.GetNum("standing_launch"));
		}

		hGroundShotInitParams.GoBack(); // from OP_INIT_CONFIG

		hInitParams.GoBack(); // from rocketjump_params
		hInitParams.GoBack(); // from OP_INIT_CONFIG

		mOp.AddSubOperation(mGroundShotOp);
	} else {
		RocketJumpType iPriortyRocketJumpType, iBackupRocketJumpType;

		if (bHeightPriority) {
			iPriortyRocketJumpType = RocketJumpType_Ground_Shot_Down;
			iBackupRocketJumpType = RocketJumpType_Ground_Shot_Back;
		} else {
			iPriortyRocketJumpType = RocketJumpType_Ground_Shot_Back;
			iBackupRocketJumpType = RocketJumpType_Ground_Shot_Down;
		}

		KeyValues hGroundShotInitParams = new KeyValues(OP_INIT_PARAM);
		hGroundShotInitParams.SetVector("origin", vecOrigin);
		hGroundShotInitParams.SetVector("destination", vecDest);
		hGroundShotInitParams.SetNum("standing_launch", bStandingLaunch);

		RocketJumpType iRocketJumpType;

		if (!Operation.Configure(g_sRocketJumpIdentifiers[iPriortyRocketJumpType], hGroundShotInitParams)) {
			if (!Operation.Configure(g_sRocketJumpIdentifiers[iBackupRocketJumpType], hGroundShotInitParams)) {
				delete hGroundShotInitParams;
				return mOp._Abort("destination not reachable");
			}

			iRocketJumpType = iBackupRocketJumpType;
		} else {
			iRocketJumpType = iPriortyRocketJumpType;
		}

		hInitParams.JumpToKey(OP_INIT_CONFIG, true);
		hInitParams.SetString("rocketjump_identifier", g_sRocketJumpIdentifiers[iRocketJumpType]);
		hInitParams.JumpToKey("rocketjump_params", true);

		hGroundShotInitParams.JumpToKey(OP_INIT_CONFIG);

		switch (iRocketJumpType) {
			case RocketJumpType_Ground_Shot_Down: {
				hInitParams.SetFloat("start_speed", hGroundShotInitParams.GetFloat("start_speed"));
				hInitParams.SetFloat("shot_delay", hGroundShotInitParams.GetFloat("shot_delay"));
			}
			case RocketJumpType_Ground_Shot_Back: {
				hInitParams.SetFloat("yaw", hGroundShotInitParams.GetFloat("yaw"));
				hInitParams.SetFloat("pitch", hGroundShotInitParams.GetFloat("pitch"));
				hInitParams.SetNum("standing_launch", hGroundShotInitParams.GetNum("standing_launch"));
			}
		}

		hGroundShotInitParams.GoBack(); // from OP_INIT_CONFIG

		hInitParams.GoBack(); // from rocketjump_params
		hInitParams.GoBack(); // from OP_INIT_CONFIG

		if (!bConfigureOnly) {
			KeyValues hRocketJumpInitParams;
			Operation mGroundShotOp = Operation.Instance(g_sRocketJumpIdentifiers[iRocketJumpType], hRocketJumpInitParams);
			hRocketJumpInitParams.Import(hGroundShotInitParams);
			mOp.AddSubOperation(mGroundShotOp);
		}

		delete hGroundShotInitParams;
	}

	if (bConfigureOnly) {
		return OpRet_Continue;
	}

	KeyValues hAirStrafeInitParams;
	Operation mAirStrafeOp = Operation.Instance("Common.Move.AirStrafe", hAirStrafeInitParams, view_as<Op>(1));
	hAirStrafeInitParams.SetFloat("goal_proximity", fGoalProximity);

	if (bAirBrake) {
		hAirStrafeInitParams.SetNum("airbrake", true);
	} else {
		hAirStrafeInitParams.SetNum("flyby", true);
	}

	if (iFollowEntity) {
		hAirStrafeInitParams.SetNum("follow", iFollowEntity);
		hAirStrafeInitParams.SetFloat("follow_distance", fFollowDistance);
		hAirStrafeInitParams.SetFloat("follow_zoffset", fFollowZOffset);
	} else {
		hAirStrafeInitParams.SetVector("destination", vecDest);
	}

	hAirStrafeInitParams.SetNum("decelerate", true);

	mOp.AddSubOperation(mAirStrafeOp);

	Entity_GetAbsOrigin(mBot.iEntity, eOpData.vecLastPos);

	return OpRet_Continue;
}

#if defined DEBUG
public OpRet Ground_Shot_PostRun(Bot mBot, Operation mOp, OpData_RocketJump eOpData) {
	float vecPos[3];
	Entity_GetAbsOrigin(mBot.iEntity, vecPos);

	DrawDebugLine(eOpData.vecLastPos, vecPos, COLOR_BLUE, 5.0);

	eOpData.vecLastPos = vecPos;

	return OpRet_Continue;
}
#endif
