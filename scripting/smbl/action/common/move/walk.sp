#define DEFAULT_GOAL_PROXIMITY	50.0

enum struct OpData_Walk {
	NavNode mEndNode;
	float vecDest[3];
	NavPath mNavPath;
	bool bBeelineStart;
	float vecLastPos[3];
	float fGoalProximity;
	any aPadding[6];
}

enum struct SeqData_Walk {
	NavNode mPrevNode;
	NavNode mCurrentNode;
	float vecDest[3];
	PathMode iPathMode;
	bool bLeftProbeHit;
	bool bRightProbeHit;
	any aPadding[8];
}

// Operation callbacks

OpRet Walk_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Walk eOpData) {
	float vecStart[3], vecEnd[3], vecOrigin[3], vecDest[3];

	NavMesh mNavMesh = view_as<NavMesh>(hInitParams.GetNum("nav_mesh", view_as<int>(NULL_NAV_MESH)));

	NavNode mStartNode = view_as<NavNode>(hInitParams.GetNum("start_node", view_as<int>(NULL_NAV_NODE)));
	NavNode mEndNode = view_as<NavNode>(hInitParams.GetNum("end_node", view_as<int>(NULL_NAV_NODE)));

	if ((!mStartNode || !mEndNode) && !mNavMesh) {
		return mOp._Abort("missing navigation mesh init parameter");
	}

	if (!hInitParams.JumpToKey("destination")) {
		return mOp._Abort("missing destination init parameter");
	}

	hInitParams.GoBack();
	hInitParams.GetVector("destination", vecDest);

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GoBack();
		hInitParams.GetVector("origin", vecOrigin);
	} else {
		Entity_GetAbsOrigin(mBot.iEntity, vecOrigin);
	}

	bool bBeelineStart, bBeelineEnd;

	if (!mStartNode) {
		mStartNode = mNavMesh.GetNearestNodeInRange(vecOrigin, NODE_PROXIMITY, true, 20.0);
		if (!mStartNode) {
			mStartNode = mNavMesh.GetNearestNodeInRange(vecOrigin, 4*NODE_PROXIMITY);

			PrintToServer("SMBL: Starting point is not within mesh.  Beeline %s.", mStartNode ? "to closest node" : "it");
			bBeelineStart = true;
		}
	}

	if (mStartNode) {
		if (mStartNode.Contains(vecOrigin)) {
			vecStart = vecOrigin;
		} else {
			mStartNode.GetHullProjection(vecOrigin, vecStart);
			PrintToServer("Projected start to hull point: (%.1f, %.1f, %.1f)", vecStart[0], vecStart[1], vecStart[2]);
		}

		eOpData.vecLastPos = vecStart;
	}

	if (mEndNode) {
		if (!mEndNode.Contains(vecDest)) {
			return mOp._Abort("destination init parameter is not within end_node init parameter");
		}

		vecEnd = vecDest;
	} else {
		mEndNode = mNavMesh.GetNearestNodeInRange(vecDest, NODE_PROXIMITY, true, 20.0);
		if (!mEndNode) {
			mEndNode = mNavMesh.GetNearestNodeInRange(vecDest, 4*NODE_PROXIMITY);
			PrintToServer("SMBL: Destination point is not within mesh.  Beeline %s.", mEndNode ? "to closest node" : "it");
			bBeelineEnd = true;
		}

		if (mEndNode) {
			mEndNode.GetHullProjection(vecDest, vecEnd);
			eOpData.mEndNode = mEndNode;
		}
	}

	eOpData.fGoalProximity = hInitParams.GetFloat("goal_proximity", DEFAULT_GOAL_PROXIMITY);

	int iSeqID;

	if (bBeelineStart && mStartNode) {
		Sequence eSeq;
		eSeq.iSeq = view_as<Seq>(iSeqID++);
		eSeq.fnRun = Walk;

		SeqData_Walk eSeqData;
		eSeqData.vecDest = vecStart;
		eSeq.SetData(eSeqData);
		FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk_Beeline [%.0f %.0f %.0f]", vecStart[0], vecStart[1], vecStart[2]);

		hSequences.PushArray(eSeq);
	}

	if (mStartNode && mEndNode) {
		NavPath mNavPath = Navigation.FindShortestPath(mStartNode, mEndNode, CostFunc_WalkDrop, _, vecStart, vecEnd);
		if (!mNavPath) {
			return mOp._Abort("end node is not reachable from start");
		}

		int iPathLength = mNavPath.iLength;

		eOpData.mNavPath = mNavPath;

		mNavPath.Optimize(CostFunc_WalkDrop, _, 0, -1, true);

		NavNode mPrevNode;
		for (int i=0; i<iPathLength; i++) {
			SeqData_Walk eSeqData;
			eSeqData.mPrevNode = mPrevNode;
			mNavPath.Get(i, eSeqData.mCurrentNode, _, _, _, _, eSeqData.iPathMode, eSeqData.vecDest);

			mPrevNode = eSeqData.mCurrentNode;

			Sequence eSeq;
			eSeq.fnRun = Walk;
			eSeq.iSeq = view_as<Seq>(iSeqID++);
			eSeq.SetData(eSeqData);
			FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk [%.0f %.0f %.0f]", eSeqData.vecDest[0], eSeqData.vecDest[1], eSeqData.vecDest[2]);

			hSequences.PushArray(eSeq);
		}
	}

	if (bBeelineEnd) {
		SeqData_Walk eSeqData;
		eSeqData.vecDest = vecDest;

		Sequence eSeq;
		eSeq.iSeq = view_as<Seq>(iSeqID);
		eSeq.fnRun = Walk;
		eSeq.SetData(eSeqData);
		FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk_Beeline [%.0f %.0f %.0f]", vecDest[0], vecDest[1], vecDest[2]);

		hSequences.PushArray(eSeq);
	}

	eOpData.bBeelineStart = bBeelineStart;

	mBot.iButtons |= IN_FORWARD;
	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	return OpRet_Continue;
}

OpRet Walk_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Walk eOpData, float fStartTime) {
	NavPath mNavPath = eOpData.mNavPath;
	if (mNavPath) {
		if (hSequences.Length) {
			Sequence eSeq;
			hSequences.GetArray(0, eSeq);

			if (!eSeq.fStartTime) {
				return OpRet_Continue;
			}

			SeqData_Walk eSeqData;
			eSeq.GetData(eSeqData);

			float vecVector[3];
			SubtractVectors(eSeqData.vecDest, eOpData.vecLastPos, vecVector);
			NormalizeVector(vecVector, vecVector);

			float fTimeElapsed = GetGameTime() - eSeq.fStartTime;
			int iEntity = mBot.iEntity;

			float vecPos[3];
			Entity_GetAbsOrigin(iEntity, vecPos);

			float fMaxSpeed = GetEntPropFloat(iEntity, Prop_Data, "m_flMaxspeed");

			float vecExpectedPos[3];
			ScaleVector(vecVector, fMaxSpeed * fTimeElapsed);
			AddVectors(eOpData.vecLastPos, vecVector, vecExpectedPos);

			float vecVel[3];
			Entity_GetAbsVelocity(iEntity, vecVel);

			float fVel2D = SquareRoot(vecVel[0]*vecVel[0] + vecVel[1]*vecVel[1]);

			if (fVel2D < 0.5 * fMaxSpeed && GetVectorDistance(vecPos, vecExpectedPos) > 200.0) {
				return mOp._Abort("path deviation");
			}

#if defined DEBUG
			DrawDebugLine(eOpData.vecLastPos, vecExpectedPos, COLOR_PALECYAN);
			DrawDebugLine(vecExpectedPos, eSeqData.vecDest, COLOR_CYAN);
#endif
		}

#if defined DEBUG
		int iDrawOffset = mNavPath.iLength-hSequences.Length-view_as<int>(eOpData.bBeelineStart);
		if (iDrawOffset >= 0) {
			DrawPath(mNavPath, iDrawOffset);
		}
#endif

		return OpRet_Continue;
	}

#if defined DEBUG
	DrawDebugLine(eOpData.vecLastPos, eOpData.vecDest, COLOR_CYAN);
#endif

	return OpRet_Continue;
}

OpRet Walk_Suspend(Bot mBot, Operation mOp, OpData_Walk eOpData) {
	mBot.iButtons &= ~IN_FORWARD;
	mBot.SetLocalVelocity({0.0, 0.0, 0.0});

	return OpRet_Continue;
}

OpRet Walk_Resume(Bot mBot, Operation mOp, OpData_Walk eOpData) {
	KeyValues hInitParams = mOp.hInitParams;
	hInitParams.Rewind();
	hInitParams.DeleteKey("start_node");

	return OpRet_Restart;
}

void Walk_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Walk eOpData) {
	if (mBot) {
		mBot.iButtons &= ~IN_FORWARD;
		mBot.SetLocalVelocity({0.0, 0.0, 0.0});
	}

	NavPath.Destroy(eOpData.mNavPath);
}

// Sequences

OpRet Walk(Bot mBot, Operation mOp, OpData_Walk eOpData, SeqData_Walk eSeqData, float fStartTime) {
	mBot.SetMoveTo(eSeqData.vecDest);

	int iEntity = mBot.iEntity;

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	float vecDelta[3];
	SubtractVectors(eSeqData.vecDest, vecPos, vecDelta);

	float fDist2D = SquareRoot(vecDelta[0]*vecDelta[0] + vecDelta[1]*vecDelta[1]);

	if (eSeqData.iPathMode == PathMode_Bypass) {
		return OpRet_Handled;
	} else if (fDist2D < eOpData.fGoalProximity) {
		eOpData.vecLastPos = eSeqData.vecDest;
		return OpRet_Handled;
	}

	float vecAimAng[3];
	GetVectorAngles(vecDelta, vecAimAng);
	vecAimAng[0] = 0.0;

	mBot.SetAimTo(vecAimAng);

	float vecAng[3];
	Entity_GetAbsAngles(iEntity, vecAng);

	float vecAngDiff;
	GetAngDiff(vecAng[1], vecAimAng[1], vecAngDiff);

	float vecLocalVel[3];

	if (FloatAbs(vecAngDiff) < 45.0) {
		mBot.iButtons |= IN_FORWARD;
		vecLocalVel = {400.0, 0.0, 0.0};
		mBot.SetLocalVelocity(vecLocalVel);
		mBot.SetPID(PID_SLOW_LAZY);
	} else {
		mBot.SetPID(PID_FAST);
	}

	bool bLeftProbeHit = eSeqData.bLeftProbeHit;
	bool bRightProbeHit = eSeqData.bRightProbeHit;

	if (GetGameTickCount() % 11 == 0) {
		float vecMaxs[3];
		Entity_GetMaxSize(iEntity, vecMaxs);

		const float fDistAhead = 50.0;
		const float fDistApart = 15.0;
		const float fDistGroundOffset = 10.0;
		const float fProbeHalfWidth = 15.0;

		float fDiag = SquareRoot(fDistApart*fDistApart + fDistAhead*fDistAhead);
		float fAngOffset = ArcTangent2(fDistApart, fDistAhead);

		float vecProbeMins[3];
		vecProbeMins[0] = -fProbeHalfWidth;
		vecProbeMins[1] = -fProbeHalfWidth;
		vecProbeMins[2] = fDistGroundOffset;

		float vecProbeMaxs[3];
		vecProbeMaxs[0] = fProbeHalfWidth;
		vecProbeMaxs[1] = fProbeHalfWidth;
		vecProbeMaxs[2] = vecMaxs[2];

		float vecProbeLeftPos[3];
		vecProbeLeftPos[0] = vecPos[0] + fDiag*Cosine(DegToRad(vecAng[1]) + fAngOffset);
		vecProbeLeftPos[1] = vecPos[1] + fDiag*Sine(DegToRad(vecAng[1]) + fAngOffset);
		vecProbeLeftPos[2] = vecPos[2] + fDistGroundOffset;

		TFTeam iTeam = TF2_GetClientTeam(iEntity);

		float vecLeftProbeHitPos[3], vecRightProbeHitPos[3];

		TR_TraceHullFilter(vecPos, vecProbeLeftPos, vecProbeMins, vecProbeMaxs, MASK_PLAYERSOLID, TraceEntityFilter_IgnoreTeam, iTeam);
		bLeftProbeHit = TR_DidHit();
		if (bLeftProbeHit) {
			TR_GetEndPosition(vecLeftProbeHitPos);
		} else {
			vecLeftProbeHitPos = vecProbeLeftPos;
		}

// #if defined DEBUG
// 		float vecHullMins[3], vecHullMaxs[3];
// 		AddVectors(vecLeftProbeHitPos, vecProbeMins, vecHullMins);
// 		AddVectors(vecLeftProbeHitPos, vecProbeMaxs, vecHullMaxs);

// 		Effect_DrawBeamBoxToAll(vecHullMins, vecHullMaxs, g_iLaser, g_iHalo, 0, 66, 0.1, 1.0, 1.0, 1, 0.0, COLOR_BLUE, 0);
// #endif

		float vecProbeRightPos[3];
		vecProbeRightPos[0] = vecPos[0] + fDiag*Cosine(DegToRad(vecAng[1]) - fAngOffset);
		vecProbeRightPos[1] = vecPos[1] + fDiag*Sine(DegToRad(vecAng[1]) - fAngOffset);
		vecProbeRightPos[2] = vecPos[2] + fDistGroundOffset;

		TR_TraceHullFilter(vecPos, vecProbeRightPos, vecProbeMins, vecProbeMaxs, MASK_PLAYERSOLID, TraceEntityFilter_IgnoreTeam, iTeam);
		bRightProbeHit = TR_DidHit();
		if (bRightProbeHit) {
			TR_GetEndPosition(vecRightProbeHitPos);
		} else {
			vecRightProbeHitPos = vecProbeRightPos;
		}

// #if defined DEBUG
// 		AddVectors(vecRightProbeHitPos, vecProbeMins, vecHullMins);
// 		AddVectors(vecRightProbeHitPos, vecProbeMaxs, vecHullMaxs);

// 		Effect_DrawBeamBoxToAll(vecHullMins, vecHullMaxs, g_iLaser, g_iHalo, 0, 66, 0.1, 1.0, 1.0, 1, 0.0, COLOR_RED, 0);
// #endif

		if (bLeftProbeHit && bRightProbeHit) {
			if (GetVectorDistance(vecPos, vecLeftProbeHitPos) < GetVectorDistance(vecPos, vecRightProbeHitPos)) {
				bRightProbeHit = false;
			} else {
				bLeftProbeHit = false;
			}
		}

		eSeqData.bLeftProbeHit = bLeftProbeHit;
		eSeqData.bRightProbeHit = bRightProbeHit;
	}

	if (bLeftProbeHit) {
		mBot.iButtons |= IN_RIGHT;
		vecLocalVel[1] = 400.0;
		mBot.SetLocalVelocity(vecLocalVel);
	} else if (bRightProbeHit) {
		mBot.iButtons |= IN_LEFT;
		vecLocalVel[1] = -400.0;
		mBot.SetLocalVelocity(vecLocalVel);
	}

	return OpRet_Continue;
}

// Helpers

void ClipAngle(float &fValue, float fMin=-360.0, float fMax=360.0) {
	if (fValue < fMin) {
		fValue = fMin;
	} else if (fValue > fMax) {
		fValue = fMax;
	}
}

int GetAngDiff(float fAngA, float fAngB, float &fDiff) {
	fDiff = fAngA - fAngB;
	if (fDiff < -180.0) {
		fDiff += 360.0;

		ClipAngle(fDiff);
		return -1;
	} else if (fDiff > 180.0) {
		fDiff -= 360.0;
	}

	ClipAngle(fDiff);
	return 1;
}

#if defined DEBUG
void DrawPath(NavPath mNavPath, int iStart=0, float fLife=0.1) {
	for (int i=0; i<iStart && i<mNavPath.iLength-1; i++) {
		float vecPointA[3];
		float vecPointB[3];

		mNavPath.Get(i, _, _, _, _, _, _, vecPointA);
		mNavPath.Get(i+1, _, _, _, _, _, _, vecPointB);

		DrawDebugLine(vecPointA, vecPointB, COLOR_GRAY, fLife);
	}

	for (int i=iStart; i<mNavPath.iLength-1; i++) {
		float vecPointA[3];
		float vecPointB[3];

		PathMode iPathModeA;

		mNavPath.Get(i, _, _, _, _, _, iPathModeA, vecPointA);
		mNavPath.Get(i+1, _, _, _, _, _, _, vecPointB);

		if (iPathModeA == PathMode_Bypass) {
			DrawDebugLine(vecPointA, vecPointB, COLOR_WHITE, fLife);
		} else {
			int iColor[4];

			switch (i%5) {
				case 0:
					iColor = COLOR_RED;
				case 1:
					iColor = COLOR_YELLOW;
				case 2:
					iColor = COLOR_GREEN;
				case 3:
					iColor = COLOR_BLUE;
				case 4:
					iColor = COLOR_MAGENTA;
			}

			DrawDebugLine(vecPointA, vecPointB, iColor, fLife);
		}
	}
}
#endif
