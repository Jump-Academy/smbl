enum struct OpData_Walk {
	float vecDest[3];
	ArrayList hPathResult;
	bool bBeelineStart;
	float vecLastPos[3];
	any aPadding[8];
}

enum struct SeqData_Walk {
	float vecDest[3];
	PathMode iPathMode;
	bool bLeftProbeHit;
	bool bRightProbeHit;
	any aPadding[10];
}

// Operation callbacks

OpRet Walk_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Walk eOpData) {
	float vecStart[3], vecEnd[3], vecEntity[3], vecDest[3];

	NavMesh mNavMesh = view_as<NavMesh>(hInitParams.GetNum("nav_mesh", view_as<int>(NULL_NAV_MESH)));

	NavNode mStartNode = view_as<NavNode>(hInitParams.GetNum("start_node", view_as<int>(NULL_NAV_NODE)));
	NavNode mEndNode = view_as<NavNode>(hInitParams.GetNum("end_node", view_as<int>(NULL_NAV_NODE)));

	if ((!mStartNode || !mEndNode) && !mNavMesh) {
		return mOp._Abort("missing navigation mesh init parameter");
	}

	bool bBeelineStart, bBeelineEnd;

	if (!mStartNode) {
		Entity_GetAbsOrigin(mBot.iEntity, vecEntity);

		mStartNode = mNavMesh.GetNearestNodeInRange(vecEntity, NODE_PROXIMITY, true, 20.0);
		if (!mStartNode) {
			mStartNode = mNavMesh.GetNearestNodeInRange(vecEntity, 4*NODE_PROXIMITY);

			PrintToServer("SMBL: Starting point is not within mesh.  Beeline %s.", mStartNode ? "to closest node" : "it");
			bBeelineStart = true;
		}
	}

	if (mStartNode) {
		mStartNode.GetHullProjection(vecEntity, vecStart);
		PrintToServer("Projected start to hull point: (%.1f, %.1f, %.1f)", vecStart[0], vecStart[1], vecStart[2]);
		eOpData.vecLastPos = vecStart;
	}

	if (mEndNode) {
		if (hInitParams.JumpToKey("destination")) {
			hInitParams.GoBack();
			hInitParams.GetVector("destination", vecDest);
		}

		if (!mEndNode.Contains(vecDest)) {
			return mOp._Abort("destination init parameter is not within end_node init parameter");
		}
	} else {
		if (!hInitParams.JumpToKey("destination")) {
			return mOp._Abort("missing destination init parameter");
		}

		hInitParams.GoBack();
		hInitParams.GetVector("destination", vecDest);

		mEndNode = mNavMesh.GetNearestNodeInRange(vecDest, NODE_PROXIMITY, true, 20.0);
		if (!mEndNode) {
			mEndNode = mNavMesh.GetNearestNodeInRange(vecDest, 4*NODE_PROXIMITY);
			PrintToServer("SMBL: Destination point is not within mesh.  Beeline %s.", mEndNode ? "to closest node" : "it");
			bBeelineEnd = true;
		}
	}

	if (mEndNode) {
		mEndNode.GetHullProjection(vecDest, vecEnd);
	}

	int iSeqID;

	if (bBeelineStart && mStartNode) {
		Sequence eSeq;
		eSeq.iSeq = view_as<Seq>(iSeqID++);
		eSeq.fnRun = Walk;

		eSeq.aData[SeqData_Walk::vecDest  ] = vecStart[0];
		eSeq.aData[SeqData_Walk::vecDest+1] = vecStart[1];
		eSeq.aData[SeqData_Walk::vecDest+2] = vecStart[2];

		FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk_Beeline [%.0f %.0f %.0f]", vecStart[0], vecStart[1], vecStart[2]);

		hSequences.PushArray(eSeq);
	}

	if (mStartNode && mEndNode) {
		ArrayList hPathResult = new ArrayList(sizeof(PathData));
		Navigation.FindShortestPath(mStartNode, mEndNode, CostFunc_WalkDrop, hPathResult, _, vecStart, vecEnd);
		int iPathResultLength = hPathResult.Length;
		if (!iPathResultLength) {
			delete hPathResult;

			float vecS[3];
			mStartNode.GetOrigin(vecS);
			float vecE[3];
			mEndNode.GetOrigin(vecE);

			return mOp._Abort("end node is not reachable from start");
		}

		eOpData.hPathResult = hPathResult;

		Navigation.OptimizePath(hPathResult, CostFunc_WalkDrop, _, 0, -1, true);
		
		for (int i=0; i<iPathResultLength; i++) {
			Sequence eSeq;
			eSeq.fnRun = Walk;
			eSeq.iSeq = view_as<Seq>(iSeqID++);

			PathData ePathData;
			hPathResult.GetArray(i, ePathData);

			FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk [%.0f %.0f %.0f]", ePathData.vecFocalPoint[0], ePathData.vecFocalPoint[1], ePathData.vecFocalPoint[2]);

			eSeq.aData[SeqData_Walk::vecDest  ] = ePathData.vecFocalPoint[0];
			eSeq.aData[SeqData_Walk::vecDest+1] = ePathData.vecFocalPoint[1];
			eSeq.aData[SeqData_Walk::vecDest+2] = ePathData.vecFocalPoint[2];
			eSeq.aData[SeqData_Walk::iPathMode] = ePathData.iPathMode;

			hSequences.PushArray(eSeq);
		}
	}

	if (bBeelineEnd) {
		Sequence eSeq;
		eSeq.iSeq = view_as<Seq>(iSeqID);
		eSeq.fnRun = Walk;
		eSeq.aData[SeqData_Walk::vecDest  ] = vecDest[0];
		eSeq.aData[SeqData_Walk::vecDest+1] = vecDest[1];
		eSeq.aData[SeqData_Walk::vecDest+2] = vecDest[2];

		FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk_Beeline [%.0f %.0f %.0f]", vecDest[0], vecDest[1], vecDest[2]);

		hSequences.PushArray(eSeq);
	}

	eOpData.bBeelineStart = bBeelineStart;

	mBot.iButtons |= IN_FORWARD;
	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	return OpRet_Continue;
}

OpRet Walk_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Walk eOpData, float fStartTime) {
	ArrayList hPath = view_as<ArrayList>(eOpData.hPathResult);
	if (hPath) {
		if (hSequences.Length) {
			Sequence eSeq;
			hSequences.GetArray(0, eSeq);

			if (!eSeq.fStartTime) {
				return OpRet_Continue;
			}

			float vecDest[3];
			vecDest[0] = eSeq.aData[SeqData_Walk::vecDest  ];
			vecDest[1] = eSeq.aData[SeqData_Walk::vecDest+1];
			vecDest[2] = eSeq.aData[SeqData_Walk::vecDest+2];

			float vecVector[3];
			SubtractVectors(vecDest, eOpData.vecLastPos, vecVector);
			NormalizeVector(vecVector, vecVector);

			float fTimeElapsed = GetGameTime() - eSeq.fStartTime;
			int iEntity = mBot.iEntity;

			float vecPos[3];
			Entity_GetAbsOrigin(iEntity, vecPos);

			float fMaxSpeed = GetEntPropFloat(iEntity, Prop_Data, "m_flMaxspeed");
			float fExpectedTime = GetVectorDistance(eOpData.vecLastPos, vecDest) / fMaxSpeed;

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
			if (fTimeElapsed <= fExpectedTime) {

				DrawDebugLine(eOpData.vecLastPos, vecExpectedPos, COLOR_PALECYAN);
				DrawDebugLine(vecExpectedPos, vecDest, COLOR_CYAN);
			} else {
				DrawDebugLine(eOpData.vecLastPos, vecDest, COLOR_PALECYAN);
			}
#endif
		}

#if defined DEBUG
		int iDrawOffset = hPath.Length-hSequences.Length-view_as<int>(eOpData.bBeelineStart);
		if (iDrawOffset >= 0) {
			DrawPath(hPath, iDrawOffset);
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
	mBot.iButtons = 0;
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
	delete view_as<ArrayList>(eOpData.hPathResult);
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
	} else if (fDist2D < NODE_MIN_REACH) {
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

stock void DrawPath(ArrayList hPath, int iStart=0) {
	for (int i=0; i<iStart && i<hPath.Length-1; i++) {
		PathData ePathDataA;
		PathData ePathDataB;
		hPath.GetArray(i, ePathDataA);
		hPath.GetArray(i+1, ePathDataB);

		DrawDebugLine(ePathDataA.vecFocalPoint, ePathDataB.vecFocalPoint, COLOR_GRAY, 0.1);
	}

	for (int i=iStart; i<hPath.Length-1; i++) {
		PathData ePathDataA;
		PathData ePathDataB;
		hPath.GetArray(i, ePathDataA);
		hPath.GetArray(i+1, ePathDataB);

		if (ePathDataA.iPathMode == PathMode_Bypass) {
			DrawDebugLine(ePathDataA.vecFocalPoint, ePathDataB.vecFocalPoint, COLOR_WHITE, 0.1);
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

			DrawDebugLine(ePathDataA.vecFocalPoint, ePathDataB.vecFocalPoint, iColor, 0.1);
		}
	}
}
