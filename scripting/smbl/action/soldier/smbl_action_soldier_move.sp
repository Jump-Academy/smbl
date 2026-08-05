#pragma semicolon 1

// #define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <profiler>

#include <smlib/entities>
#include <smlib/math>

#include <smbl>
#include <smbl/nav_mesh>

#define NODE_PROXIMITY		500.0

#define PERIMETER_OFFSET	75.0

#define COLOR_WHITE			{255, 255, 255, 255}
#define COLOR_GRAY			{ 10,  10,  10, 255}

#define COLOR_YELLOW		{255, 255,   0, 255}

enum struct OpData_Move {
	NavPath mNavPath;
	any aPadding[15];
}

#if defined DEBUG
int g_iLaser;
int g_iHalo;
#endif

public Plugin myinfo = {
	name = "SMBL Soldier Bot Actions Library: Move",
	author = PLUGIN_AUTHOR,
	description = "Movement operations for soldier bots",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	SMBL_NotifyOnStart();
	SMBL_NavMesh_NotifyOnCache();
}

#if defined DEBUG
public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}
#endif

// Library forwards

public void SMBL_OnStart() {
	// Auto dispatch wrapper
	Operation.Register("Soldier.Move")
		.Init(Move_Init)
		.Suspend(UnsupportedFunction)
		.Cleanup(Move_Cleanup)
		.SubOps(true);
}

public void SMBL_NavMesh_OnCache() {
	NavMesh.RegisterCache("Soldier.Move.RocketJump", NavCacheableFunc_RocketJump);
}

// Operation callbacks

OpRet Move_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Move eOpData, bool bConfigureOnly) {
	int iEntity;

	if (!bConfigureOnly) {
		iEntity = mBot.iEntity;

		if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
			return mOp._Abort("unsupported TFClassType");
		}
	}

	NavMesh mNavMesh = view_as<NavMesh>(hInitParams.GetNum("nav_mesh"));

 	NavNode mStartNode = view_as<NavNode>(hInitParams.GetNum("start_node"));
	NavNode mEndNode = view_as<NavNode>(hInitParams.GetNum("end_node"));

	if ((!mStartNode || !mEndNode) && !mNavMesh) {
		return mOp._Abort("missing navigation mesh init parameter");
	}

	float vecStart[3], vecEnd[3], vecOrigin[3], vecDest[3];

	if (!hInitParams.JumpToKey("destination")) {
		return mOp._Abort("missing destination init parameter");
	}

	hInitParams.GetVector(NULL_STRING, vecDest);
	hInitParams.GoBack();

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GetVector(NULL_STRING, vecOrigin);
		hInitParams.GoBack();
	} else if (bConfigureOnly) {
		return mOp._Abort("missing origin init parameter");
	} else {
		Entity_GetAbsOrigin(iEntity, vecOrigin);
	}

	NavPath mNavPath;

	bool bConfigNavPath = hInitParams.GetNum("config_nav_path") != 0;

	bool bBeelineStart, bBeelineEnd;

	bool bConfigured = !bConfigureOnly && hInitParams.JumpToKey(OP_INIT_CONFIG);
	if (bConfigured) {
		mStartNode = view_as<NavNode>(hInitParams.GetNum("start_node"));
		mEndNode = view_as<NavNode>(hInitParams.GetNum("end_node"));

		bBeelineStart = hInitParams.GetNum("beeline_start") != 0;
		bBeelineEnd = hInitParams.GetNum("beeline_end") != 0;

		hInitParams.GetVector("vecStart", vecStart);
		hInitParams.GetVector("vecEnd", vecEnd);

		mNavPath = view_as<NavPath>(hInitParams.GetNum("nav_path"));

		hInitParams.GoBack(); // from OP_INIT_CONFIG
	} else {
		if (!mStartNode) {
			mStartNode = mNavMesh.GetNearestNodeInRange(vecOrigin, NODE_PROXIMITY, true, 20.0);
			if (!mStartNode) {
				mStartNode = mNavMesh.GetNearestNodeInRange(vecOrigin, 4*NODE_PROXIMITY);
				bBeelineStart = true;
			}
		}

		if (mStartNode) {
			if (mStartNode.Contains(vecOrigin)) {
				vecStart = vecOrigin;
			} else {
				mStartNode.GetHullProjection(vecOrigin, vecStart);
			}
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
				bBeelineEnd = true;
			}

			if (mEndNode) {
				mEndNode.GetHullProjection(vecDest, vecEnd);
			}
		}

		hInitParams.JumpToKey(OP_INIT_CONFIG, true);

		hInitParams.SetNum("start_node", view_as<int>(mStartNode));
		hInitParams.SetNum("end_node", view_as<int>(mEndNode));

		hInitParams.SetNum("beeline_start", bBeelineStart);
		hInitParams.SetNum("beeline_end", bBeelineEnd);

		hInitParams.SetVector("vecStart", vecStart);
		hInitParams.SetVector("vecEnd", vecEnd);

		hInitParams.GoBack(); // from OP_INIT_CONFIG
	}

	if (!mNavPath) {
		char sMapName[32];
		mNavMesh.GetMapName(sMapName, sizeof(sMapName));

		char sFileName[32];
		mNavMesh.GetFileName(sFileName, sizeof(sFileName));

		mNavPath = Navigation.FindShortestPath(mNavMesh, mStartNode, mEndNode, CostFunc_Move, LocalDataPackCleanupFunc_Cleanup, _, vecStart, vecEnd);
		if (!mNavPath) {
			return mOp._Abort("destination is not reachable");
		}

		if (bConfigNavPath) {
			hInitParams.JumpToKey(OP_INIT_CONFIG);
			hInitParams.SetNum("nav_path", view_as<int>(mNavPath));
			hInitParams.GoBack(); // from OP_INIT_CONFIG
		}
	}

	if (bConfigureOnly) {
		if (!bConfigNavPath) {
			NavPath.Destroy(mNavPath);
		}

		return OpRet_Continue;
	}

	eOpData.mNavPath = mNavPath;

	Op iOp;

	if (bBeelineStart && mStartNode) {
		KeyValues hWalkInitParams;
		Operation mSubOp = Operation.Instance("Common.Move.Walk.Beeline", hWalkInitParams, iOp++);

		hWalkInitParams.SetVector("origin", vecOrigin);
		hWalkInitParams.SetVector("destination", vecStart);

		mOp.AddSubOperation(mSubOp);
	}

	NavNode mPrevNode;
	float vecPrevFocalPoint[3];
	int iPrevExitAttachmentFlags;

	mNavPath.Get(0, mPrevNode, _, _, iPrevExitAttachmentFlags, _, _, vecPrevFocalPoint);

	int iPathLength = mNavPath.iLength;
	for (int i=1; i<iPathLength; i++) {
		NavNode mNode;
		int iExitAttachmentFlags;
		float vecFocalPoint[3];
		LocalDataPack mEdgeData;

		mNavPath.Get(i, mNode, _, _, iExitAttachmentFlags, mEdgeData, _, vecFocalPoint);

		if (iPrevExitAttachmentFlags & (FL_ATTACH_GROUND | FL_ATTACH_DROP) && GetVectorDistance2D(vecPrevFocalPoint, vecFocalPoint) < 200.0) {
			KeyValues hWalkInitParams;
			Operation mSubOp = Operation.Instance("Common.Move.Walk", hWalkInitParams, iOp++);
			hWalkInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
			hWalkInitParams.SetNum("start_node", view_as<int>(mPrevNode));
			hWalkInitParams.SetNum("end_node", view_as<int>(mNode));
			hWalkInitParams.SetVector("origin", vecPrevFocalPoint);
			hWalkInitParams.SetVector("destination", vecFocalPoint);
			mOp.AddSubOperation(mSubOp);

			mPrevNode = mNode;
			iPrevExitAttachmentFlags = iExitAttachmentFlags;
			vecPrevFocalPoint = vecFocalPoint;
			continue;
		}

		// Try rocket jumping ahead of path as far as possible

		int iRocketJumpDestinationIdx = -1;
		for (int j=i; j<iPathLength; j++) {
			mNavPath.Get(j, mNode, _, _, iExitAttachmentFlags, mEdgeData, _, vecFocalPoint);

			if (!mNavMesh.LookupCache("Soldier.Move.RocketJump", mPrevNode, mNode)) {
				break;
			}

			iRocketJumpDestinationIdx = j;
		}

		if (iRocketJumpDestinationIdx != -1) {
			mNavPath.Get(iRocketJumpDestinationIdx, mNode, _, _, iExitAttachmentFlags, _, _, vecFocalPoint);

			KeyValues hFarthestInitParams = new KeyValues(OP_INIT_DISPATCH);
			mNavMesh.LookupCache("Soldier.Move.RocketJump", mPrevNode, mNode, hFarthestInitParams);

			if (!hFarthestInitParams.GotoFirstSubKey(true)) {
				return mOp._Abort("cannot find cached init parameters");
			}

			KeyValues hParameterizeSubOpInitParams;
			Operation mParameterizeSubOp = Operation.Instance("Utility.Parameterize.ByPosition", hParameterizeSubOpInitParams, iOp++);
			hParameterizeSubOpInitParams.SetNum("prefer_forward", true);
			mOp.AddSubOperation(mParameterizeSubOp);

			hParameterizeSubOpInitParams.JumpToKey("positions", true);

			int iParamIdx;
			char sParamIdx[8];

			do {
				IntToString(iParamIdx++, sParamIdx, sizeof(sParamIdx));
				hParameterizeSubOpInitParams.JumpToKey(sParamIdx, true);

				char sIdentifier[32];
				hFarthestInitParams.GetString(OP_INIT_IDENT, sIdentifier, sizeof(sIdentifier));
				hFarthestInitParams.JumpToKey(OP_INIT_PARAM);

				float vecRocketJumpOrigin[3];
				hFarthestInitParams.GetVector("origin", vecRocketJumpOrigin);

				hParameterizeSubOpInitParams.SetVector("origin", vecRocketJumpOrigin);
				hParameterizeSubOpInitParams.JumpToKey("parameters", true);

				// Common.Move.Walk init param overrides
				hParameterizeSubOpInitParams.JumpToKey("1", true);
				hParameterizeSubOpInitParams.SetVector("destination", vecRocketJumpOrigin); // Walk to rocket jump starting position
				hParameterizeSubOpInitParams.GoBack();

				// Soldier.Move.RocketJump init param overrides
				hParameterizeSubOpInitParams.JumpToKey("2", true);
				hParameterizeSubOpInitParams.Import(hFarthestInitParams);
				hParameterizeSubOpInitParams.GoBack();

				hParameterizeSubOpInitParams.GoBack(); // from parameters
				hParameterizeSubOpInitParams.GoBack(); // from sParamIdx
			} while (hFarthestInitParams.GotoNextKey(true));

			delete hFarthestInitParams;

			hParameterizeSubOpInitParams.GoBack(); // from positions

			hParameterizeSubOpInitParams.JumpToKey("operations", true);

			KeyValues hWalkSubOpInitParams;
			Operation mWalkSubOp = Operation.Instance("Common.Move.Walk", hWalkSubOpInitParams, iOp++);

			hWalkSubOpInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
			hWalkSubOpInitParams.SetNum("start_node", view_as<int>(mPrevNode));
			hWalkSubOpInitParams.SetNum("end_node", view_as<int>(mPrevNode));
			hWalkSubOpInitParams.SetFloat("proximity", 15.0);
			hWalkSubOpInitParams.SetVector("origin", vecPrevFocalPoint);
			mOp.AddSubOperation(mWalkSubOp);
			hParameterizeSubOpInitParams.SetNum("1", view_as<int>(mWalkSubOp));

			KeyValues hRocketJumpInitParams;
			Operation mRocketJumpSubOp = Operation.Instance("Soldier.Move.RocketJump", hRocketJumpInitParams, iOp++);

			hRocketJumpInitParams.SetNum("decelerate", true);
			hRocketJumpInitParams.SetNum("airbrake", true);
			hRocketJumpInitParams.SetFloat("goal_proximity", 100.0);

			mOp.AddSubOperation(mRocketJumpSubOp);
			hParameterizeSubOpInitParams.SetNum("2", view_as<int>(mRocketJumpSubOp));

			i = iRocketJumpDestinationIdx;
			mPrevNode = mNode;
			iPrevExitAttachmentFlags = iExitAttachmentFlags;
			vecPrevFocalPoint = vecFocalPoint;

			continue;
		}

		// Backup is walking

		mNavPath.Get(i, mNode, _, _, iExitAttachmentFlags, _, _, vecFocalPoint);

		KeyValues hWalkInitParams;
		Operation mSubOp = Operation.Instance("Common.Move.Walk", hWalkInitParams, iOp++);
		hWalkInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
		hWalkInitParams.SetNum("start_node", view_as<int>(mPrevNode));
		hWalkInitParams.SetNum("end_node", view_as<int>(mNode));
		hWalkInitParams.SetVector("origin", vecPrevFocalPoint);
		hWalkInitParams.SetVector("destination", vecFocalPoint);
		mOp.AddSubOperation(mSubOp);

		mPrevNode = mNode;
		iPrevExitAttachmentFlags = iExitAttachmentFlags;
		vecPrevFocalPoint = vecFocalPoint;
	}

	if (bBeelineEnd) {
		KeyValues hWalkInitParams;
		Operation mSubOp = Operation.Instance("Common.Move.Walk.Beeline", hWalkInitParams, iOp++);

		hWalkInitParams.SetVector("destination", vecEnd);

		mOp.AddSubOperation(mSubOp);
	}

	return OpRet_Continue;
}

void Move_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Move eOpData) {
	NavPath.Destroy(eOpData.mNavPath);
}

// Custom callbacks

public float CostFunc_Move(NavMesh mNavMesh, NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bNodeAStart, bool bNodeBGoal, bool bHeuristic, any aData, LocalDataPack mEdgeData) {
	if (bHeuristic) {
		return GetVectorDistance(vecPosA, vecPosB);
	}

	if (!(iAttachmentFlags & (FL_ATTACH_GROUND | FL_ATTACH_DROP | FL_ATTACH_AIR_GAP | FL_ATTACH_WALL))) {
		return POSITIVE_INFINITY;
	}

	if (iAttachmentFlags & (FL_ATTACH_AIR_GAP | FL_ATTACH_WALL)) {
		if (mNavMesh.LookupCache("Soldier.Move.RocketJump", mNodeA, mNodeB)) {
			return 0.75*GetVectorDistance2D(vecPosA, vecPosB);
		}

		return POSITIVE_INFINITY;
	}

 	return GetVectorDistance(vecPosA, vecPosB);
}

public void LocalDataPackCleanupFunc_Cleanup(LocalDataPack mLocalDataPack) {
	mLocalDataPack.Reset();

	while (mLocalDataPack.IsReadable()) {
		delete view_as<KeyValues>(mLocalDataPack.ReadCell());
	}
}

public bool NavCacheableFunc_RocketJump(NavNode mNodeA, NavNode mNodeB, KeyValues hKVData) {
	float vecNodeAOrigin[3];
	mNodeA.GetOrigin(vecNodeAOrigin);

	int iIdx;
	char sKey[8];

	int iVertices = mNodeA.iVertices;
	for (int i=0; i<iVertices; i++) {
		float vecEdgeCenterA[3];
		mNodeA.GetEdgeCenter(i, vecEdgeCenterA);

		ShiftToOrigin(vecEdgeCenterA, vecNodeAOrigin, PERIMETER_OFFSET);

		KeyValues hInitParamsEdgeCenter = GetRocketJumpDispatchToNode(vecEdgeCenterA, mNodeB);
		if (hInitParamsEdgeCenter) {
			IntToString(iIdx++, sKey, sizeof(sKey));
			hKVData.JumpToKey(sKey, true);
			hKVData.Import(hInitParamsEdgeCenter);
			hKVData.GoBack();

			delete hInitParamsEdgeCenter;
		}

		float vecVertexA[3];
		mNodeA.GetVertex(i, vecVertexA);

		ShiftToOrigin(vecVertexA, vecNodeAOrigin, PERIMETER_OFFSET);

		KeyValues hInitParamsVertex = GetRocketJumpDispatchToNode(vecVertexA, mNodeB);
		if (hInitParamsVertex) {
			IntToString(iIdx++, sKey, sizeof(sKey));
			hKVData.JumpToKey(sKey, true);
			hKVData.Import(hInitParamsVertex);
			hKVData.GoBack();

			delete hInitParamsVertex;
		}
	}

	return iIdx > 0;
}

// Helpers

float GetVectorDistance2D(const float vecA[3], const float vecB[3]) {
	float fDelta0 = vecB[0] - vecA[0];
	float fDelta1 = vecB[1] - vecA[1];

	return SquareRoot(fDelta0*fDelta0 + fDelta1*fDelta1);
}

KeyValues GetRocketJumpDispatchToNode(float vecStart[3], NavNode mEndNode) {
	float vecEndNodeOrigin[3];
	mEndNode.GetOrigin(vecEndNodeOrigin);

	float fMinDist = GetVectorDistance(vecStart, vecEndNodeOrigin);
	KeyValues hInitParams = GetRocketJumpDispatch(vecStart, vecEndNodeOrigin);

	int iVertices = mEndNode.iVertices;
	for (int i=0; i<iVertices; i++) {
		float vecEdgeCenter[3];
		mEndNode.GetEdgeCenter(i, vecEdgeCenter);

		ShiftToOrigin(vecEdgeCenter, vecEndNodeOrigin, PERIMETER_OFFSET);

		float fEdgeCenterDist = GetVectorDistance(vecStart, vecEdgeCenter);
		if (fEdgeCenterDist < fMinDist) {
			KeyValues hEdgeCenterInitParams = GetRocketJumpDispatch(vecStart, vecEdgeCenter);
			if (hEdgeCenterInitParams) {
				fMinDist = fEdgeCenterDist;

				delete hInitParams;
				hInitParams = hEdgeCenterInitParams;
			}
		}

		float vecVertex[3];
		mEndNode.GetVertex(i, vecVertex);

		ShiftToOrigin(vecVertex, vecEndNodeOrigin, PERIMETER_OFFSET);

		float fVertexDist = GetVectorDistance(vecStart, vecVertex);
		if (fVertexDist < fMinDist) {
			KeyValues hVertexInitParams = GetRocketJumpDispatch(vecStart, vecVertex);
			if (hVertexInitParams) {
				fMinDist = fVertexDist;

				delete hInitParams;
				hInitParams = hVertexInitParams;
			}
		}
	}

	return hInitParams;
}

KeyValues GetRocketJumpDispatch(float vecStart[3], float vecDest[3]) {
	KeyValues hInitParams = new KeyValues(OP_INIT_DISPATCH);
	hInitParams.SetString(OP_INIT_IDENT, "Soldier.Move.RocketJump");
	hInitParams.JumpToKey(OP_INIT_PARAM, true);

	hInitParams.SetVector("origin", vecStart);
	hInitParams.SetVector("destination", vecDest);

	if (Operation.Configure("Soldier.Move.RocketJump", hInitParams)) {
		hInitParams.Rewind();
		return hInitParams;
	}

	delete hInitParams;

	return null;
}

void ShiftToOrigin(float vecPos[3], float vecOrigin[3], float fShift) {
	float vecVector[3];
	SubtractVectors(vecOrigin, vecPos, vecVector);
	NormalizeVector(vecVector, vecVector);
	ScaleVector(vecVector, fShift);
	AddVectors(vecPos, vecVector, vecPos);
}

#if defined DEBUG

void DrawDebugLine(float vecPos[3], float vecPos2[3], int iColor[4], float fLife=0.1) {
	TE_SetupBeamPoints(vecPos, vecPos2, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 1.0, 1, 0.0, iColor, 0);
	TE_SendToAll();
}

void DrawDebugMarker(float vecPos[3], int iColor[4], float fLife) {
	float vecMarker[3];
	vecMarker = vecPos;
	vecMarker[2] += 150.0;
	DrawDebugLine(vecPos, vecMarker, iColor, fLife);
}

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
			DrawDebugLine(vecPointA, vecPointB, COLOR_YELLOW, fLife);
		}
	}
}
#endif
