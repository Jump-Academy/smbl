#define DEFAULT_FOLLOW_DISTANCE	250.0
#define DEFAULT_STARE 0

enum struct OpData_WalkFollow {
	int iTargetRef;
	float vecDest[3];
	float fFollowDistance;
	bool bStare;
	NavMesh mNavMesh;
	NavNode mCurrentNode;
	NavNode mEndNode;
	OpRef mWalkOpRef;
	any aPadding[6];
}

// Operation callbacks

OpRet WalkFollow_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_WalkFollow eOpData) {
	int iTarget = hInitParams.GetNum("target");
	if (!iTarget) {
		return mOp._Abort("missing follow target");
	}

	NavMesh mNavMesh = view_as<NavMesh>(hInitParams.GetNum("nav_mesh", view_as<int>(NULL_NAV_MESH)));
	if (!mNavMesh) {
		return mOp._Abort("missing navigation mesh init parameter");
	}

	eOpData.iTargetRef = EntIndexToEntRef(iTarget);
	eOpData.fFollowDistance = hInitParams.GetFloat("distance", DEFAULT_FOLLOW_DISTANCE);
	eOpData.bStare = hInitParams.GetNum("stare", DEFAULT_STARE) != 0;
	eOpData.mNavMesh = mNavMesh;

	return OpRet_Continue;
}

OpRet WalkFollow_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_WalkFollow eOpData, float fStartTime) {
	int iTarget = EntRefToEntIndex(eOpData.iTargetRef);
	if (iTarget == INVALID_ENT_REFERENCE || Client_IsValid(iTarget) && !IsPlayerAlive(iTarget)) {
		return mOp._Abort("target entity is no longer valid");
	}

	int iBotEntity = mBot.iEntity;

	float vecDest[3];
	Entity_GetAbsOrigin(iTarget, vecDest);

	float vecPos[3];
	Entity_GetAbsOrigin(iBotEntity, vecPos);

	// Stop walking if close enough
	if (GetVectorDistance(vecPos, vecDest) < eOpData.fFollowDistance) {
		mOp.ClearSubOperations();

		if (eOpData.bStare && Client_IsValid(iBotEntity) && Client_IsValid(iTarget)) {
			GetClientEyePosition(iBotEntity, vecPos);
			GetClientEyePosition(iTarget, vecDest);

			float vecAimAngles[3];
			SubtractVectors(vecDest, vecPos, vecAimAngles);
			NormalizeVector(vecAimAngles, vecAimAngles);
			GetVectorAngles(vecAimAngles, vecAimAngles);
			mBot.SetAimTo(vecAimAngles);
		}

		return OpRet_Bypass;
	}

	return OpRet_Continue;
}

OpRet WalkFollow_PreRun(Bot mBot, Operation mOp, OpData_WalkFollow eOpData) {
	if (GetGameTickCount() % 33 != 0 && GetGameTime() > mOp.fStartTime+GetTickInterval()) {
		return OpRet_Continue;
	}

	int iTarget = EntRefToEntIndex(eOpData.iTargetRef);

	float vecDest[3];
	Entity_GetAbsOrigin(iTarget, vecDest);

	Operation mWalkOp = eOpData.mWalkOpRef.ToOperation();

	// Reuse currently running walk suboperation by updating destination
	if (mWalkOp.IsValid()) {
		ArrayList hSequences = mWalkOp.hSequences;

		if (eOpData.mEndNode && eOpData.mEndNode.Contains(vecDest)) {
			if (hSequences.Length) {
				Sequence eSeq;
				hSequences.GetArray(hSequences.Length-1, eSeq);

				SeqData_Walk eSeqData;
				eSeq.GetData(eSeqData);

				eOpData.mCurrentNode = eSeqData.mCurrentNode;

				eSeqData.vecDest = vecDest;
				eSeq.SetData(eSeqData);

				hSequences.SetArray(hSequences.Length-1, eSeq);

				return OpRet_Continue;
			}
		}

		KeyValues hInitParams = mWalkOp.hInitParams;

		Sequence eSeq;
		hSequences.GetArray(0, eSeq);

		SeqData_Walk eSeqData;
		eSeq.GetData(eSeqData);

		NavNode mCurrentNode = eOpData.mCurrentNode = eSeqData.mCurrentNode;
		if (!mCurrentNode) {
			mCurrentNode = eOpData.mNavMesh.GetNearestNodeInRange(vecDest, NODE_PROXIMITY, true, 20.0);
		}

		NavNode mEndNode = eOpData.mNavMesh.GetNearestNodeInRange(vecDest, NODE_PROXIMITY, true, 20.0);

		hInitParams.SetVector("destination", vecDest);
		hInitParams.SetNum("start_node", view_as<int>(mCurrentNode));
		hInitParams.SetNum("end_node", view_as<int>(mEndNode));
		mWalkOp.Restart();

		if (mWalkOp.Init(mBot, true) == OpRet_Continue) {
			OpData_Walk eWalkOpData;
			mWalkOp.GetData(eWalkOpData);

			eOpData.mEndNode = eWalkOpData.mEndNode;
		} else {
			mOp.ClearSubOperations();
		}

		return OpRet_Continue;
	}

	mOp.ClearSubOperations();

	KeyValues hInitParams;
	mWalkOp = Operation.Instance("Common.Walk", hInitParams);

	if (eOpData.mCurrentNode) {
		hInitParams.SetNum("start_node", view_as<int>(eOpData.mCurrentNode));
	}

	hInitParams.SetNum("nav_mesh", view_as<int>(eOpData.mNavMesh));
	hInitParams.SetVector("destination", vecDest);

	if (mWalkOp.Init(mBot, true) == OpRet_Continue) {
	 	eOpData.mWalkOpRef = mWalkOp.ToOpRef();
		mOp.AddSubOperation(mWalkOp);

		OpData_Walk eWalkOpData;
		mWalkOp.GetData(eWalkOpData);

		eOpData.mEndNode = eWalkOpData.mEndNode;
	}

	return OpRet_Continue;
}
