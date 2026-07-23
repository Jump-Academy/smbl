#pragma semicolon 1

#define DEBUG

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

#define COLOR_RED			{255,   0,   0, 255}
#define COLOR_YELLOW		{255, 255,   0, 255}
#define COLOR_GREEN			{  0, 255,   0, 255}
#define COLOR_CYAN			{  0, 255, 255, 255}
#define COLOR_BLUE			{  0,   0, 255, 255}
#define COLOR_MAGENTA		{255,   0, 255, 255}
#define COLOR_ORANGE		{127, 31, 0, 255}

enum struct OpData_Move3D {
	NavPath mNavPath;
	any aPadding[15];
}

#if defined DEBUG
int g_iLaser;
int g_iHalo;
Profiler g_hProfilerA;
Profiler g_hProfilerB;
Profiler g_hProfilerC;
#endif

public Plugin myinfo = {
	name = "SMBL Soldier Bot Actions Library: Move",
	author = PLUGIN_AUTHOR,
	description = "Movement operations for soldier bots",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

#if defined DEBUG
public void OnPluginStart() {
	g_hProfilerA = new Profiler();
	g_hProfilerB = new Profiler();
	g_hProfilerC = new Profiler();

	SMBL_NotifyOnStart();
	SMBL_NavMesh_NotifyOnCache();
}
#endif

#if defined DEBUG
public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}
#endif

// Library forwards

public void SMBL_OnStart() {
	// Auto dispatch wrapper
	Operation.Register("Soldier.Move3D", Move3D_Init, Move3D_Validate, _, _, UnsupportedFunction, _, Move3D_Cleanup, _, true);

	//Operation.Register("Soldier.Move3D")
	//	.Init(Move3D_Init)
	//	.Validate(Move3D_Validate)
	//	.Resume(UnsupportedFunction)
	//	.Cleanup(Move3D_Cleanup)
	//	.SubOps(true);
}

public void SMBL_NavMesh_OnCache() {
	NavMesh.RegisterCache("Soldier.Move3D", NavCacheableFunc_RocketJump);
	NavMesh.RegisterCache("Soldier.Dummy", NavCacheableFunc_Dummy);
}

// Operation callbacks

OpRet Move3D_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Move3D eOpData, bool bConfigureOnly) {
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

				PrintToServer("[SMBL] Starting point is not within mesh.  Beeline %s.", mStartNode ? "to closest node" : "it");
				bBeelineStart = true;
			}
		}

		if (mStartNode) {
			if (mStartNode.Contains(vecOrigin)) {
				vecStart = vecOrigin;
			} else {
				mStartNode.GetHullProjection(vecOrigin, vecStart);
	// 			mStartNode.GetOrigin(vecStart);
				PrintToServer("[SMBL] Projected start to hull point: (%.1f, %.1f, %.1f)", vecStart[0], vecStart[1], vecStart[2]);

	// 			// Nudge slightly into node to ensure contains check passes in Navigation.FindShortestPath()
	// 			float vecVector[3];
	// 			SubtractVectors(vecStart, vecOrigin, vecVector);
	// 			NormalizeVector(vecVector, vecVector);
	// 			ScaleVector(vecVector, 150.0);
	// 			AddVectors(vecStart, vecVector, vecStart);
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
				PrintToServer("SMBL: Destination point is not within mesh.  Beeline %s.", mEndNode ? "to closest node" : "it");
				bBeelineEnd = true;
			}

			if (mEndNode) {
				mEndNode.GetHullProjection(vecDest, vecEnd);
	// 			mEndNode.GetOrigin(vecEnd);
// 				eOpData.mEndNode = mEndNode;

	// 			// Nudge slightly into node to ensure contains check passes in Navigation.FindShortestPath()
	// 			float vecVector[3];
	// 			SubtractVectors(vecEnd, vecDest, vecVector);
	// 			NormalizeVector(vecVector, vecVector);
	// 			ScaleVector(vecVector, 150.0);
	// 			AddVectors(vecEnd, vecVector, vecEnd);
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

		PrintToServer("Soldier.Move3D got nav mesh %d (file=%s, map=%s, timestamp=%d)", mNavMesh, sFileName, sMapName, mNavMesh.iTimestamp);

	// 	bool bSkipLast = hInitParams.GetNum("skip_last", 0) != 0;

		g_hProfilerA.Start();

		PrintToServer("Soldier.Move3D(origin: [%.1f, %.1f, %.1f] -> dest: [%.1f, %.1f, %.1f])", vecOrigin[0], vecOrigin[1], vecOrigin[2], vecDest[0], vecDest[1], vecDest[2]);

		mNavPath = Navigation.FindShortestPath(mNavMesh, mStartNode, mEndNode, CostFunc_Move3D, LocalDataPackCleanupFunc_Cleanup, _, vecStart, vecEnd);

		g_hProfilerA.Stop();

		PrintToServer("Move3D FindShortestPath returned after %.3f ms", 1000*(g_hProfilerA.Time));

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
			PrintToServer("Delete mNavPath");
			NavPath.Destroy(mNavPath);
		}

		return OpRet_Continue;
	}

	eOpData.mNavPath = mNavPath;

	Op iOp;

	if (bBeelineStart && mStartNode) {
		KeyValues hWalkInitParams;
		Operation mSubOp = Operation.Instance("Common.Walk.Beeline", hWalkInitParams, iOp++);

		hWalkInitParams.SetVector("origin", vecOrigin);
		hWalkInitParams.SetVector("destination", vecStart);

		mOp.AddSubOperation(mSubOp);
	}

	PrintToServer("Path Length=%d", mNavPath.iLength);

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
			Operation mSubOp = Operation.Instance("Common.Walk", hWalkInitParams, iOp++);
			hWalkInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
			hWalkInitParams.SetNum("start_node", view_as<int>(mPrevNode));
			hWalkInitParams.SetNum("end_node", view_as<int>(mNode));
			hWalkInitParams.SetVector("origin", vecPrevFocalPoint);
			hWalkInitParams.SetVector("destination", vecFocalPoint);
			mOp.AddSubOperation(mSubOp);

// 			DrawDebugLine(vecPrevFocalPoint, vecFocalPoint, COLOR_GREEN, 5.0);

			mPrevNode = mNode;
			iPrevExitAttachmentFlags = iExitAttachmentFlags;
			vecPrevFocalPoint = vecFocalPoint;
			continue;
		}

// 		KeyValues hFarthestInitParams;

		// Try rocket jumping ahead of path as far as possible

		PrintToServer("Finding farthest rocket jump in forward path...");

		g_hProfilerB.Start();

		int iRocketJumpDestinationIdx = -1;
		for (int j=i; j<iPathLength; j++) {
			mNavPath.Get(j, mNode, _, _, iExitAttachmentFlags, mEdgeData, _, vecFocalPoint);
			//PrintToServer("Path idx=%d, mEdgeData=%x (pos: %d)", i, mEdgeData, mEdgeData ? view_as<int>(mEdgeData.Position) : -1);

// 			KeyValues hTestInitParams = new KeyValues(OP_INIT_PARAM);
// 			hTestInitParams.SetVector("origin", vecPrevFocalPoint);
// 			hTestInitParams.SetVector("destination", vecFocalPoint);

// 			if (!Operation.Configure("Soldier.RocketJump", hTestInitParams)) {
// 				delete hTestInitParams;
// 				break;
// 			}

// 			KeyValues hTestInitParams = new KeyValues(OP_INIT_DISPATCH);

// 			if (!mNavMesh.LookupCache("Soldier.Move3D", mPrevNode, mNode, hTestInitParams)) {
			if (!mNavMesh.LookupCache("Soldier.Move3D", mPrevNode, mNode)) {
				break;
			}

			iRocketJumpDestinationIdx = j;
// 			delete hFarthestInitParams;
// 			hFarthestInitParams = hTestInitParams;
		}

		g_hProfilerB.Stop();
		PrintToServer("Found in %.4f ms", 1000*(g_hProfilerB.Time));

		if (iRocketJumpDestinationIdx != -1) {
			mNavPath.Get(iRocketJumpDestinationIdx, mNode, _, _, iExitAttachmentFlags, _, _, vecFocalPoint);

			KeyValues hFarthestInitParams = new KeyValues(OP_INIT_DISPATCH);
			mNavMesh.LookupCache("Soldier.Move3D", mPrevNode, mNode, hFarthestInitParams);

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

	// 			DrawDebugLine(vecPrevFocalPoint, vecFocalPoint, COLOR_YELLOW, 5.0);

// 				hFarthestInitParams.JumpToKey("0"); // TODO: Multiple

				char sIdentifier[32];
				hFarthestInitParams.GetString(OP_INIT_IDENT, sIdentifier, sizeof(sIdentifier));
				hFarthestInitParams.JumpToKey(OP_INIT_PARAM);

				float vecRocketJumpOrigin[3];
				hFarthestInitParams.GetVector("origin", vecRocketJumpOrigin);

				hParameterizeSubOpInitParams.SetVector("origin", vecRocketJumpOrigin);
				hParameterizeSubOpInitParams.JumpToKey("parameters", true);

				// Common.Walk init param overrides
				hParameterizeSubOpInitParams.JumpToKey("1", true);
				hParameterizeSubOpInitParams.SetVector("destination", vecRocketJumpOrigin); // Walk to rocket jump starting position
				hParameterizeSubOpInitParams.GoBack();

				// Soldier.RocketJump init param overrides
				hParameterizeSubOpInitParams.JumpToKey("2", true);
				hParameterizeSubOpInitParams.Import(hFarthestInitParams);
				hParameterizeSubOpInitParams.GoBack();

				hParameterizeSubOpInitParams.GoBack(); // from parameters
				hParameterizeSubOpInitParams.GoBack(); // from sParamIdx
			} while (hFarthestInitParams.GotoNextKey(true));

			delete hFarthestInitParams;

			hParameterizeSubOpInitParams.GoBack(); // from positions

			hParameterizeSubOpInitParams.JumpToKey("operations", true);

// 				PrintToServer("Walk to RJ origin: [%.1f %.1f %.1f]", vecRocketJumpOrigin[0], vecRocketJumpOrigin[1], vecRocketJumpOrigin[2]);

			KeyValues hWalkSubOpInitParams;
			Operation mWalkSubOp = Operation.Instance("Common.Walk", hWalkSubOpInitParams, iOp++);

	// 			int iVertices = mPrevNode.iVertices;
	// 			for (int v=0; v<iVertices; v++) {
	// 				float vecVertexA[3];
	// 				float vecVertexB[3];
	// 				mPrevNode.GetEdgeVertices(v, vecVertexA, vecVertexB);
	// 				DrawDebugLine(vecVertexA, vecVertexB, COLOR_CYAN, 5.0);
	// 			}

	// 			DrawDebugMarker(vecRocketJumpOrigin, COLOR_RED, 5.0);

			hWalkSubOpInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
			hWalkSubOpInitParams.SetNum("start_node", view_as<int>(mPrevNode));
			hWalkSubOpInitParams.SetNum("end_node", view_as<int>(mPrevNode));
			hWalkSubOpInitParams.SetFloat("proximity", 15.0);
			hWalkSubOpInitParams.SetVector("origin", vecPrevFocalPoint);
// 			hWalkSubOpInitParams.SetVector("destination", vecRocketJumpOrigin);
			mOp.AddSubOperation(mWalkSubOp);
			hParameterizeSubOpInitParams.SetNum("1", view_as<int>(mWalkSubOp));

			KeyValues hRocketJumpInitParams;
			Operation mRocketJumpSubOp = Operation.Instance("Soldier.RocketJump", hRocketJumpInitParams, iOp++);

// 			KeyValues hRocketJumpInitParams;
// 			Operation mSubOp = Operation.Instance("Soldier.RocketJump", hRocketJumpInitParams, iOp++);
// 			hRocketJumpInitParams.Import(hFarthestInitParams);
			hRocketJumpInitParams.SetNum("decelerate", true);
			hRocketJumpInitParams.SetNum("airbrake", true);
			hRocketJumpInitParams.SetFloat("goal_proximity", 100.0);
			//char sBuffer[4096];
			//hRocketJumpInitParams.ExportToString(sBuffer, sizeof(sBuffer));
			//PrintToServer("RJ params\n%s", sBuffer);
			mOp.AddSubOperation(mRocketJumpSubOp);
			hParameterizeSubOpInitParams.SetNum("2", view_as<int>(mRocketJumpSubOp));

// 			char sBuffer[4096];
// 			hParameterizeSubOpInitParams.Rewind();
// 			hParameterizeSubOpInitParams.ExportToString(sBuffer, sizeof(sBuffer));
// 			PrintToServer(sBuffer);

			i = iRocketJumpDestinationIdx;
			mPrevNode = mNode;
			iPrevExitAttachmentFlags = iExitAttachmentFlags;
			vecPrevFocalPoint = vecFocalPoint;

			continue;
		}

// 		delete hFarthestInitParams;

		// Backup is walking

		mNavPath.Get(i, mNode, _, _, iExitAttachmentFlags, _, _, vecFocalPoint);

		KeyValues hWalkInitParams;
		Operation mSubOp = Operation.Instance("Common.Walk", hWalkInitParams, iOp++);
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


/*
		if (iPrevExitAttachmentFlags & FL_ATTACH_GROUND) {
			PrintToServer("Handled by case 1");
			NavNode mPrevIterNode = mNode;

			float vecPrevIterFocalPoint[3];
			vecPrevIterFocalPoint = vecFocalPoint;

			for (int j=i+1; j<iPathLength; j++) {
				NavNode mIterNode;
				int iIterAttachmentFlags;
				float vecIterFocalPoint[3];
				mNavPath.Get(j, mIterNode, _, _, iIterAttachmentFlags, _, _, vecIterFocalPoint);

				if (!(iIterAttachmentFlags & FL_ATTACH_GROUND)) {
					PrintToServer("  Mid path leaves ground");
					KeyValues hSubOpInitParams;
					Operation mSubOp = Operation.Instance("Common.Walk", hSubOpInitParams, iOp++);
					hSubOpInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
					hSubOpInitParams.SetNum("start_node", view_as<int>(mNode));
					hSubOpInitParams.SetNum("end_node", view_as<int>(mPrevIterNode));
					hSubOpInitParams.SetVector("origin", vecFocalPoint);
					hSubOpInitParams.SetVector("destination", vecPrevIterFocalPoint);
					mOp.AddSubOperation(mSubOp);

					i = j-1;
					mPrevNode = mPrevIterNode;
					vecPrevFocalPoint = vecPrevIterFocalPoint;
					iPrevExitAttachmentFlags = iExitAttachmentFlags;

					break;
				} else if (j == iPathLength-1 && iIterAttachmentFlags & FL_ATTACH_GROUND) {
					PrintToServer("  End of path on ground");
					KeyValues hSubOpInitParams;
					Operation mSubOp = Operation.Instance("Common.Walk", hSubOpInitParams, iOp++);
					hSubOpInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
					hSubOpInitParams.SetNum("start_node", view_as<int>(mNode));
					hSubOpInitParams.SetNum("end_node", view_as<int>(mIterNode));
					hSubOpInitParams.SetVector("origin", vecFocalPoint);
					hSubOpInitParams.SetVector("destination", vecIterFocalPoint);
					DrawDebugMarker(vecIterFocalPoint, COLOR_RED, 5.0);
					mOp.AddSubOperation(mSubOp);
				}

				mPrevIterNode = mIterNode;
				vecPrevIterFocalPoint = vecIterFocalPoint;
			}
		} else if (iPrevExitAttachmentFlags & FL_ATTACH_DROP) {
			PrintToServer("Handled by case 2");

			KeyValues hSubOpInitParams = new KeyValues(OP_INIT_PARAM);
			hSubOpInitParams.SetVector("origin", vecPrevFocalPoint);
			hSubOpInitParams.SetVector("destination", vecFocalPoint);

			if (Operation.Configure("Soldier.RocketJump", hSubOpInitParams, mBot)) {
				KeyValues hRocketJumpInitParams;
				Operation mSubOp = Operation.Instance("Soldier.RocketJump", hRocketJumpInitParams, iOp++);
				hRocketJumpInitParams.SetNum("decelerate", true);
				hRocketJumpInitParams.SetNum("airbrake", true);
				hRocketJumpInitParams.SetFloat("goal_proximity", 100.0);
				hRocketJumpInitParams.Import(hSubOpInitParams);
				mOp.AddSubOperation(mSubOp);
			} else {
				KeyValues hWalkInitParams;
				Operation mSubOp = Operation.Instance("Common.Walk", hWalkInitParams, iOp++);
				hWalkInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
				hWalkInitParams.SetNum("start_node", view_as<int>(mPrevNode));
				hWalkInitParams.SetNum("end_node", view_as<int>(mNode));
// 				hSubOpInitParams.SetVector("origin", vecPrevFocalPoint);
// 				hSubOpInitParams.SetVector("destination", vecFocalPoint);
				hWalkInitParams.Import(hSubOpInitParams);
				mOp.AddSubOperation(mSubOp);
			}

			delete hSubOpInitParams;

			mPrevNode = mNode;
			vecPrevFocalPoint = vecFocalPoint;
			iPrevExitAttachmentFlags = iExitAttachmentFlags;
		} else if (iPrevExitAttachmentFlags & (FL_ATTACH_WALL | FL_ATTACH_AIR_GAP)) {
// 			for (int j=i+1; j<iPathLength; j++) {
// 			}
			PrintToServer("Handled by case 3");

			KeyValues hParameterizeSubOpInitParams;
			Operation mParameterizeSubOp = Operation.Instance("Utility.Parameterize.ByPosition", hParameterizeSubOpInitParams, iOp++);
			hParameterizeSubOpInitParams.SetNum("prefer_forward", true);
			mOp.AddSubOperation(mParameterizeSubOp);

			hParameterizeSubOpInitParams.JumpToKey("positions", true);

			PrintToServer("mEdgeData.IsReadable()=%d", mEdgeData.IsReadable());
			mEdgeData.Reset();

			if (!mEdgeData.IsReadable()) {
				return mOp._Abort("missing rocket jump dispatch from edge data");
			}

			int iParamIdx;
			char sParamIdx[8];
			char sDispatchIdentifier[64];
// 			char sBuffer[4096];

			while (mEdgeData.IsReadable()) {
				IntToString(iParamIdx++, sParamIdx, sizeof(sParamIdx));
				hParameterizeSubOpInitParams.JumpToKey(sParamIdx, true);

				KeyValues hRocketJumpDispatch = mEdgeData.ReadCell();
				hRocketJumpDispatch.GetString(OP_INIT_IDENT, sDispatchIdentifier, sizeof(sDispatchIdentifier));
// 				PrintToServer("Reading dispatch %d: %s", iParamIdx, sDispatchIdentifier);

				hRocketJumpDispatch.JumpToKey(OP_INIT_PARAM);

				float vecRocketJumpOrigin[3];
				hRocketJumpDispatch.GetVector("origin", vecRocketJumpOrigin);

				hParameterizeSubOpInitParams.SetVector("origin", vecRocketJumpOrigin);
				hParameterizeSubOpInitParams.JumpToKey("parameters", true);

				// Common.Walk init param overrides
				hParameterizeSubOpInitParams.JumpToKey("1", true);
				hParameterizeSubOpInitParams.SetVector("destination", vecRocketJumpOrigin); // Walk to rocket jump starting position
				hParameterizeSubOpInitParams.GoBack(); // from 1

				// Soldier.RocketJump init param overrides
				hParameterizeSubOpInitParams.JumpToKey("2", true);
				hParameterizeSubOpInitParams.JumpToKey(OP_INIT_PARAM, true);
				hParameterizeSubOpInitParams.Import(hRocketJumpDispatch);
// 				hParameterizeSubOpInitParams.SetVector("origin", vecRocketJumpOrigin);
//  				hParameterizeSubOpInitParams.SetVector("destination", vecRocketJumpDest);
				hParameterizeSubOpInitParams.GoBack(); // from OP_INIT_PARAM
				hParameterizeSubOpInitParams.GoBack(); // from 2

				hParameterizeSubOpInitParams.GoBack(); // from parameters
				hParameterizeSubOpInitParams.GoBack(); // from sParamIdx
			}

			hParameterizeSubOpInitParams.GoBack(); // from positions

			hParameterizeSubOpInitParams.JumpToKey("operations", true);

			KeyValues hWalkSubOpInitParams;
			Operation mWalkSubOp = Operation.Instance("Common.Walk", hWalkSubOpInitParams, iOp++);

			hWalkSubOpInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
			hWalkSubOpInitParams.SetNum("start_node", view_as<int>(mPrevNode));
			hWalkSubOpInitParams.SetNum("end_node", view_as<int>(mPrevNode));
			hWalkSubOpInitParams.SetFloat("proximity", 15.0);
			hWalkSubOpInitParams.SetVector("origin", vecPrevFocalPoint);
			hWalkSubOpInitParams.Rewind();

			mOp.AddSubOperation(mWalkSubOp);
			hParameterizeSubOpInitParams.SetNum("1", view_as<int>(mWalkSubOp));

			KeyValues hRocketJumpSubOpInitParams;
			Operation mRocketJumpSubOp = Operation.Instance("Soldier.RocketJump", hRocketJumpSubOpInitParams, iOp++);

			hRocketJumpSubOpInitParams.SetNum("decelerate", true);
			hRocketJumpSubOpInitParams.SetNum("airbrake", true);
			hRocketJumpSubOpInitParams.SetFloat("goal_proximity", 100.0);
			hRocketJumpSubOpInitParams.Rewind();

			mOp.AddSubOperation(mRocketJumpSubOp);
			hParameterizeSubOpInitParams.SetNum("2", view_as<int>(mRocketJumpSubOp));

			hParameterizeSubOpInitParams.Rewind();

// 			hParameterizeSubOpInitParams.ExportToString(sBuffer, sizeof(sBuffer));

// 			PrintToServer(sBuffer);

			mPrevNode = mNode;
			vecPrevFocalPoint = vecFocalPoint;
			iPrevExitAttachmentFlags = iExitAttachmentFlags;
		}
	}
*/
	if (bBeelineEnd) {
		KeyValues hWalkInitParams;
		Operation mSubOp = Operation.Instance("Common.Walk.Beeline", hWalkInitParams, iOp++);

		hWalkInitParams.SetVector("destination", vecEnd);

		mOp.AddSubOperation(mSubOp);
	}

	return OpRet_Continue;
}

/*
	int iPathLength = mNavPath.iLength;
	if (bSkipLast && iPathLength) {
		iPathLength--;
	}

	eOpData.mNavPath = mNavPath;
par

	float vecPrevFocalPoint[3];
	vecPrevFocalPoint = vecOrigin;

	int iPreviousExitAttachmentFlags;

	NavNode mPrevNode;
	NavNode mCurrentNode = mStartNode;

	Op iOp;

	fTimestamp = GetEngineTime();


	for (int i=0; i<iPathLength; i++) {
// 		PrintToChatAll("PathData %d", i);
// 		hSubOpInitParams = null;

		int iSkipPreviousExitAttachmentFlags = iPreviousExitAttachmentFlags;
		int iSkipAhead = i;

		for (int j=i; j<iPathLength; j++) {
// 			if (iSkipPreviousExitAttachmentFlags & FL_ATTACH_GROUND) {
// 				break;
// 			}

			int iExitAttachmentFlags;
			float vecFocalPoint[3];
			mNavPath.Get(j, _, _, _, iExitAttachmentFlags, _, _, vecFocalPoint);

			if (GetVectorDistance(vecPrevFocalPoint, vecFocalPoint) < 200.0) {
				continue;
			}

			KeyValues hRocketJumpInitParams;
			Operation mRocketJumpSubOp = Operation.Instance("Soldier.RocketJump", hRocketJumpInitParams);
			hRocketJumpInitParams.SetVector("origin", vecPrevFocalPoint);
			hRocketJumpInitParams.SetVector("destination", vecFocalPoint);

			if (mRocketJumpSubOp.Init(mBot, true) == OpRet_Continue) {
				iSkipAhead = j;

				Operation.Destroy(mRocketJumpSubOp);

				iSkipPreviousExitAttachmentFlags = iExitAttachmentFlags;
				continue;
			}

			Operation.Destroy(mRocketJumpSubOp);
			break;
		}

		int iExitAttachmentFlags;
		float vecFocalPoint[3];
		LocalDataPack mEdgeData;

		mPrevNode = mCurrentNode;
		mNavPath.Get(iSkipAhead, mCurrentNode, _, _, iExitAttachmentFlags, mEdgeData, _, vecFocalPoint);

		DrawDebugMarker(vecFocalPoint, COLOR_GREEN, 5.0);

		PrintToServer("Attachment flags (%d -> %d): %5b", i-1, i, iPreviousExitAttachmentFlags);

		int iColor[4];

		if (iSkipAhead > i || iPreviousExitAttachmentFlags & (FL_ATTACH_WALL | FL_ATTACH_AIR_GAP)) {
			mEdgeData.Reset();

			KeyValues hParameterizeSubOpInitParams;
			Operation mParameterizeSubOp = Operation.Instance("Utility.Parameterize.ByPosition", hParameterizeSubOpInitParams, iOp++);
			hParameterizeSubOpInitParams.SetNum("prefer_forward", true);
			mOp.AddSubOperation(mParameterizeSubOp);

			hParameterizeSubOpInitParams.JumpToKey("positions", true);

			char sBuffer[1024];

			int iParamIdx;
			char sParamIdx[8];
			while (mEdgeData.IsReadable()) {
				IntToString(iParamIdx++, sParamIdx, sizeof(sParamIdx));
				hParameterizeSubOpInitParams.JumpToKey(sParamIdx, true);

				float vecRocketJumpOrigin[3], vecRocketJumpDest[3];
				KeyValues hRocketJumpInitParams = mEdgeData.ReadCell();
				hRocketJumpInitParams.GetVector("origin", vecRocketJumpOrigin);
				hRocketJumpInitParams.GetVector("destination", vecRocketJumpDest);

				hParameterizeSubOpInitParams.SetVector("origin", vecRocketJumpOrigin);

				hParameterizeSubOpInitParams.JumpToKey("parameters", true);

				// Common.Walk init param overrides
				hParameterizeSubOpInitParams.JumpToKey("1", true);
				hParameterizeSubOpInitParams.SetVector("destination", vecRocketJumpOrigin); // Walk to rocket jump starting position
				hParameterizeSubOpInitParams.GoBack();

				// Soldier.RocketJump init param overrides
				hParameterizeSubOpInitParams.JumpToKey("2", true);
				hParameterizeSubOpInitParams.SetVector("origin", vecRocketJumpOrigin);
 				hParameterizeSubOpInitParams.SetVector("destination", vecRocketJumpDest);

				hRocketJumpInitParams.JumpToKey("dispatch");
				hParameterizeSubOpInitParams.JumpToKey("dispatch", true);
				hRocketJumpInitParams.ExportToString(sBuffer, sizeof(sBuffer));
				hParameterizeSubOpInitParams.ImportFromString(sBuffer);
				hParameterizeSubOpInitParams.GoBack();

				hParameterizeSubOpInitParams.GoBack();

				hParameterizeSubOpInitParams.GoBack(); // from parameters
				hParameterizeSubOpInitParams.GoBack(); // from sParamIdx
			}

			hParameterizeSubOpInitParams.GoBack(); // from positions

			hParameterizeSubOpInitParams.JumpToKey("operations", true);

			KeyValues hWalkSubOpInitParams;
			Operation mWalkSubOp = Operation.Instance("Common.Walk", hWalkSubOpInitParams, iOp++);

			hWalkSubOpInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
			hWalkSubOpInitParams.SetNum("start_node", view_as<int>(mPrevNode));
			hWalkSubOpInitParams.SetNum("end_node", view_as<int>(mPrevNode));
			hWalkSubOpInitParams.SetFloat("proximity", 15.0);
			hWalkSubOpInitParams.SetVector("origin", vecPrevFocalPoint);

			mOp.AddSubOperation(mWalkSubOp);
			hParameterizeSubOpInitParams.SetNum("1", view_as<int>(mWalkSubOp));

			//DrawDebugMarker(vecEdgeCenter, COLOR_GREEN, 1.0);

			KeyValues hRocketJumpSubOpInitParams;
			Operation mRocketJumpSubOp = Operation.Instance("Soldier.RocketJump", hRocketJumpSubOpInitParams, iOp++);

			hRocketJumpSubOpInitParams.SetNum("decelerate", true);
			hRocketJumpSubOpInitParams.SetNum("airbrake", true);
			hRocketJumpSubOpInitParams.SetFloat("goal_proximity", 100.0);

			mOp.AddSubOperation(mRocketJumpSubOp);
			hParameterizeSubOpInitParams.SetNum("2", view_as<int>(mRocketJumpSubOp));

			hParameterizeSubOpInitParams.Rewind();

			hParameterizeSubOpInitParams.ExportToString(sBuffer, sizeof(sBuffer));

			PrintToServer(sBuffer);

			iColor = COLOR_ORANGE;
		} else {
			KeyValues hSubOpInitParams;
			Operation mSubOp = Operation.Instance("Common.Walk", hSubOpInitParams, iOp++);
			hSubOpInitParams.SetNum("nav_mesh", view_as<int>(mNavMesh));
			hSubOpInitParams.SetNum("start_node", view_as<int>(mPrevNode));
			hSubOpInitParams.SetNum("end_node", view_as<int>(mCurrentNode));
			hSubOpInitParams.SetVector("origin", vecPrevFocalPoint);
			hSubOpInitParams.SetVector("destination", vecFocalPoint);
			iColor = COLOR_MAGENTA;
			mOp.AddSubOperation(mSubOp);
		}

// 		DrawDebugLine(vecPreviousFocalPoint, ePathData.vecFocalPoint, iColor, 5.0);

// 		hSubOpInitParams.SetVector("destination", vecFocalPoint);

// 		DrawDebugMarker(ePathData.vecFocalPoint, COLOR_GREEN, 5.0);

		vecPrevFocalPoint = vecFocalPoint;
		iPreviousExitAttachmentFlags = iExitAttachmentFlags;
	}

	PrintToServer("Move3D jump sequences init after %.3f ms", 1000*(GetEngineTime()-fTimestamp));

	return OpRet_Handled;
}
*/

OpRet Move3D_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Move3D eOpData, float fStartTime) {
// 	NavPath mNavPath = eOpData.mNavPath;
// 	if (mNavPath) {
// 		DrawPath(mNavPath, _, 0.1);
// 	}

	return OpRet_Continue;
}

void Move3D_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Move3D eOpData) {
// 	if (mBot) {
// 		mBot.iButtons &= ~IN_FORWARD;
// 		mBot.SetLocalVelocity({0.0, 0.0, 0.0});
// 	}

	NavPath.Destroy(eOpData.mNavPath);
}

// Custom callbacks

// public float CostFunc_Move3D(NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bHeuristic, any aData) {
// 	if (iAttachmentFlags & (FL_ATTACH_GROUND | FL_ATTACH_DROP) || bHeuristic) {
// 		if (!bHeuristic) {
// 			DrawDebugLine(vecPosA, vecPosB, COLOR_MAGENTA, 5.0);
// 		}
// 		return GetVectorDistance(vecPosA, vecPosB);
// 	}

// 	DrawDebugLine(vecPosA, vecPosB, COLOR_RED, 5.0);

// 	return POSITIVE_INFINITY;
// }

public float CostFunc_Move3D(NavMesh mNavMesh, NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bNodeAStart, bool bNodeBGoal, bool bHeuristic, any aData, LocalDataPack mEdgeData) {
	if (bHeuristic) {
		return GetVectorDistance(vecPosA, vecPosB);
	}

	if (!(iAttachmentFlags & (FL_ATTACH_GROUND | FL_ATTACH_DROP | FL_ATTACH_AIR_GAP | FL_ATTACH_WALL))) {
		return POSITIVE_INFINITY;
	}

// 	DrawDebugLine(vecPosA, vecPosB, COLOR_WHITE, 5.0);

	if (iAttachmentFlags & (FL_ATTACH_AIR_GAP | FL_ATTACH_WALL)) {
// 		PrintToServer("CostFunc_Move3D mNodeB=%d, iEdgeB=%d", mNodeB, iEdgeB);

// 		bool bFound;
// 		g_hProfilerC.Start(); 
		bool bFound = mNavMesh.LookupCache("Soldier.Move3D", mNodeA, mNodeB);
// 		g_hProfilerC.Stop(); 
// 		PrintToServer("NavMesh.LookupCache returned after %.4f ms", g_hProfilerC.Time*1000);

		/*
		if (bNodeBGoal) {
			float vecNodeAOrigin[3];
			mNodeA.GetOrigin(vecNodeAOrigin);

			KeyValues hInitParamsPosA = GetRocketJumpDispatch(mNodeA, mNodeB, vecPosA, vecPosB);
			if (hInitParamsPosA) {
				mEdgeData.WriteCell(hInitParamsPosA);
				bFound = true;
			}

			int iVertices = mNodeA.iVertices;
			for (int i=0; i<iVertices; i++) {
				float vecEdgeCenterA[3];
				mNodeA.GetEdgeCenter(i, vecEdgeCenterA);

				ShiftToOrigin(vecEdgeCenterA, vecNodeAOrigin, PERIMETER_OFFSET);

				KeyValues hInitParamsEdgeCenter = GetRocketJumpDispatch(mNodeA, mNodeB, vecEdgeCenterA, vecPosB);
				if (hInitParamsEdgeCenter) {
					mEdgeData.WriteCell(hInitParamsEdgeCenter);
					bFound = true;
				}

				float vecVertexA[3];
				mNodeA.GetVertex(i, vecVertexA);

				ShiftToOrigin(vecVertexA, vecNodeAOrigin, PERIMETER_OFFSET);

				KeyValues hInitParamsVertex = GetRocketJumpDispatch(mNodeA, mNodeB, vecVertexA, vecPosB);
				if (hInitParamsVertex) {
					mEdgeData.WriteCell(hInitParamsVertex);
					bFound = true;
				}
			}
		} else if (iEdgeB != 255) {
			float vecEdgeBVertexA[3], vecEdgeBCenter[3], vecEdgeBVertexB[3];
			mNodeB.GetEdgeVertices(iEdgeB, vecEdgeBVertexA, vecEdgeBVertexB);
			mNodeB.GetEdgeCenter(iEdgeB, vecEdgeBCenter);

			float vecNodeAOrigin[3], vecNodeBOrigin[3];
			mNodeA.GetOrigin(vecNodeAOrigin);
			mNodeB.GetOrigin(vecNodeBOrigin);

			ShiftToOrigin(vecEdgeBVertexA, vecNodeBOrigin, PERIMETER_OFFSET);
			ShiftToOrigin(vecEdgeBCenter, vecNodeBOrigin, PERIMETER_OFFSET);
			ShiftToOrigin(vecEdgeBVertexB, vecNodeBOrigin, PERIMETER_OFFSET);

			KeyValues hInitParamsPosA = GetRocketJumpDispatchToEdge(mNodeA, mNodeB, vecPosA, vecEdgeBVertexA, vecEdgeBCenter, vecEdgeBVertexB);
			if (hInitParamsPosA) {
				mEdgeData.WriteCell(hInitParamsPosA);
				bFound = true;
			}

			int iVertices = mNodeA.iVertices;
			for (int i=0; i<iVertices; i++) {
				float vecEdgeCenterA[3];
				mNodeA.GetEdgeCenter(i, vecEdgeCenterA);

				ShiftToOrigin(vecEdgeCenterA, vecNodeAOrigin, PERIMETER_OFFSET);

				KeyValues hInitParamsEdgeCenter = GetRocketJumpDispatchToEdge(mNodeA, mNodeB, vecEdgeCenterA, vecEdgeBVertexA, vecEdgeBCenter, vecEdgeBVertexB);
				if (hInitParamsEdgeCenter) {
					mEdgeData.WriteCell(hInitParamsEdgeCenter);
					bFound = true;
				}

				float vecVertexA[3];
				mNodeA.GetVertex(i, vecVertexA);

				ShiftToOrigin(vecVertexA, vecNodeAOrigin, PERIMETER_OFFSET);

				KeyValues hInitParamsVertex = GetRocketJumpDispatchToEdge(mNodeA, mNodeB, vecVertexA, vecEdgeBVertexA, vecEdgeBCenter, vecEdgeBVertexB);
				if (hInitParamsVertex) {
					mEdgeData.WriteCell(hInitParamsVertex);
					bFound = true;
				}
			}
		}
		*/

		if (bFound) {
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

// 	KeyValues hOriginDispatch = GetRocketJumpDispatchToNode(vecNodeAOrigin, mNodeB);
// 	if (hOriginDispatch) {
// 		hKVData.JumpToKey("0", true);
// 		hKVData.Import(hOriginDispatch);
// 		hKVData.GoBack();

// 		delete hOriginDispatch;
// 		iIdx++;
// 	}

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

public bool NavCacheableFunc_Dummy(NavNode mNodeA, NavNode mNodeB, KeyValues hKVData) {
	return false;
}

// Helpers

float GetVectorDistance2D(const float vecA[3], const float vecB[3]) {
	float fDelta0 = vecB[0] - vecA[0];
	float fDelta1 = vecB[1] - vecA[1];

	return SquareRoot(fDelta0*fDelta0 + fDelta1*fDelta1);
}
/*
KeyValues GetRocketJumpDispatchToEdge(NavNode mNodeA, NavNode mNodeB, float vecStart[3], float vecVertexA[3], float vecEdgeCenter[3], float vecVertexB[3]) {
	float fMinDist = POSITIVE_INFINITY;
	KeyValues hInitParams;

	float fDistA = GetVectorDistance(vecStart, vecVertexA);
	KeyValues hInitParamsA = GetRocketJumpDispatch(mNodeA, mNodeB, vecStart, vecVertexA);
	if (hInitParamsA) {
		fMinDist = fDistA;
		hInitParams = hInitParamsA;
	}

	float fDistCenter = GetVectorDistance(vecStart, vecEdgeCenter);
	if (fDistCenter < fMinDist) {
		KeyValues hInitParamsCenter = GetRocketJumpDispatch(mNodeA, mNodeB, vecStart, vecEdgeCenter);
		if (hInitParamsCenter) {
			fMinDist = fDistCenter;

			delete hInitParams;
			hInitParams = hInitParamsCenter;
		}
	}

	float fDistB = GetVectorDistance(vecStart, vecVertexB);
	if (fDistB < fMinDist) {
		KeyValues hInitParamsB = GetRocketJumpDispatch(mNodeA, mNodeB, vecStart, vecVertexB);
		if (hInitParamsB) {
			fMinDist = fDistB;

			delete hInitParams;
			hInitParams = hInitParamsB;
		}
	}

	return hInitParams;
}
*/

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

// TODO: Make use of corresponding NavNodes for op config caching
KeyValues GetRocketJumpDispatch(float vecStart[3], float vecDest[3]) {
	KeyValues hInitParams = new KeyValues(OP_INIT_DISPATCH);
	hInitParams.SetString(OP_INIT_IDENT, "Soldier.RocketJump");
	hInitParams.JumpToKey(OP_INIT_PARAM, true);

	hInitParams.SetVector("origin", vecStart);
	hInitParams.SetVector("destination", vecDest);

	if (Operation.Configure("Soldier.RocketJump", hInitParams)) {
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
// 			int iColor[4];

// 			switch (i%5) {
// 				case 0:
// 					iColor = COLOR_RED;
// 				case 1:
// 					iColor = COLOR_YELLOW;
// 				case 2:
// 					iColor = COLOR_GREEN;
// 				case 3:
// 					iColor = COLOR_BLUE;
// 				case 4:
// 					iColor = COLOR_MAGENTA;
// 			}

// 			DrawDebugLine(vecPointA, vecPointB, iColor, fLife);
			DrawDebugLine(vecPointA, vecPointB, COLOR_YELLOW, fLife);
		}
	}
}
#endif
