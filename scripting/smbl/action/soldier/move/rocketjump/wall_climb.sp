// Operation callbacks

OpRet Wall_Climb_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData, bool bConfigureOnly) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("unsupported TFClassType");
	}

	NavMesh mNavMesh = view_as<NavMesh>(hInitParams.GetNum("nav_mesh"));
	if (!mNavMesh) {
		return mOp._Abort("missing navigation mesh init parameter");
	}

	NavNode mStartNode = view_as<NavNode>(hInitParams.GetNum("start_node"));
	NavNode mEndNode = view_as<NavNode>(hInitParams.GetNum("end_node"));

	float vecOrigin[3];

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GoBack();
		hInitParams.GetVector("origin", vecOrigin);
	} else {
		Entity_GetAbsOrigin(mBot.iEntity, vecOrigin);
	}

	if (!mStartNode) {
		mStartNode = mNavMesh.GetNearestNodeInRange(vecOrigin, NODE_PROXIMITY, true, 20.0);
		if (!mStartNode) {
			return mOp._Abort("origin is not within mesh");
		}
	}

	if (!mEndNode) {
		if (!hInitParams.JumpToKey("destination")) {
			return mOp._Abort("missing destination init parameter");
		}

		hInitParams.GoBack();

		float vecDest[3];
		hInitParams.GetVector("destination", vecDest);

		mEndNode = mNavMesh.GetNearestNodeInRange(vecDest, NODE_PROXIMITY, true, 20.0);
		if (!mEndNode) {
			return mOp._Abort("destination is not within mesh");
		}

// 		mEndNode.GetHullProjection(vecDest, vecDest);
	}

	int iEdge, iAttachedNodeEdge;
	int iAttachmentFlags;
	if (!mStartNode.FindAttachedNode(mEndNode, iEdge, _, iAttachmentFlags, iAttachedNodeEdge) || iAttachmentFlags & FL_ATTACH_WALL == 0) {
		return mOp._Abort("end node is not attached to start node");
	}

	float vecVertexA[3], vecVertexB[3];
	mStartNode.GetEdgeOverlap(iEdge, mEndNode, iAttachedNodeEdge, vecVertexA, vecVertexB);

	// Walk to closest point projected onto the wall

	float vecEdgeVector[3];
	SubtractVectors(vecVertexB, vecVertexA, vecEdgeVector);

	float fEdgeLength = GetVectorLength(vecEdgeVector);
	NormalizeVector(vecEdgeVector, vecEdgeVector);

	float vecPointToVertexAVector[3];
	SubtractVectors(vecOrigin, vecVertexA, vecPointToVertexAVector);

	float vecProjEdge[3];
	float fProjLength = GetVectorDotProduct(vecPointToVertexAVector, vecEdgeVector);
	if (fProjLength < 0) {
		vecProjEdge = vecVertexA;
	} else if (fProjLength >= fEdgeLength) {
		vecProjEdge = vecVertexB;
	} else {
		ScaleVector(vecEdgeVector, fProjLength);
		AddVectors(vecVertexA, vecEdgeVector, vecProjEdge);
	}

	KeyValues hWalkInitParams;
	Operation mWalkOp = Operation.Instance("Common.Move.Walk", hWalkInitParams);
	hWalkInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
	hWalkInitParams.SetVector("destination", vecProjEdge);
	mOp.AddSubOperation(mWalkOp);

	float vecAimAng[3];
	SubtractVectors(vecProjEdge, vecOrigin, vecAimAng);
	GetVectorAngles(vecAimAng, vecAimAng);

	KeyValues hRocketJumpInitParams;
	Operation mRocketJumpOp = Operation.Instance("Soldier.Move.RocketJump.Ground.Shot.Down", hRocketJumpInitParams);
	hRocketJumpInitParams.SetFloat("heading", vecAimAng[1] + 180.0);

	float vecLaunchTarget[3];
	vecLaunchTarget = vecProjEdge;
	vecLaunchTarget[2] += 500.0; // Use fastest vertical launch
	hRocketJumpInitParams.SetVector("destination", vecLaunchTarget);
	hRocketJumpInitParams.SetNum("standing_launch", true);
	mOp.AddSubOperation(mRocketJumpOp);

	float vecWallNormal[3];
	GetVectorCrossProduct(vecEdgeVector, {0.0, 0.0, 1.0}, vecWallNormal);

	mEndNode.GetEdgeOverlap(iAttachedNodeEdge, mStartNode, iAttachedNodeEdge, vecVertexA, vecVertexB);

	float fDestinationZ = 0.5 * (vecVertexA[2] + vecVertexB[2]);

	KeyValues hWallClimbInitParams;
	Operation mWallClimbOp = Operation.Instance("Soldier.Move.RocketJump.Wall.Climb.Up", hWallClimbInitParams);
	hWallClimbInitParams.SetVector("wall_normal", vecWallNormal);
	hWallClimbInitParams.SetFloat("destination_z", fDestinationZ);
	mOp.AddSubOperation(mWallClimbOp);

	return OpRet_Continue;
}
