#include <sdktools_trace>

#define POSITIVE_INFINITY		view_as<float>(0x7F800000)
#define NEGATIVE_INFINITY		view_as<float>(0xFF800000)

enum struct _NavPath {
	ArrayList hPathData;
	float fCost;
	bool bGCFlag;
}

enum struct PathData {
	NavNode mNavNode;
	int iEntryEdge;
	int iExitEdge;
	int iExitAttachmentFlags;
	LocalDataPack mEdgeData;
	PathMode iPathMode;
	float vecFocalPoint[3];
}

enum struct Frontier {
	char sIdentifier[32];
	NavNode mNode;
}

enum struct VertexFrontier {
	char sIdentifier[32];
	any aData;
}

enum struct FrontierData {
	char sIdentifier[32];
	char sParentIdentifier[32];
	NavNode mParentNode;
	int iParentEdge;
	int iParentAttachmentFlags;
	LocalDataPack mEdgeData;
	NavNode mNode;
	int iEdge;
	float vecFocalPoint[3];
	float fCost;
	float fScore;		// Cost + Heuristic
}

enum struct VertexFrontierData {
	char sIdentifier[32];
	char sParentIdentifier[32];
	float vecVertex[3];
	any aData;
	LocalDataPack mEdgeData;
	float fCost;
	float fScore;		// Cost + Heuristic
}

enum struct EdgeOverlap {
	float vecVertexA[3];
	float vecVertexB[3];
}

ArrayList g_hNavPaths;

void SetupPathNatives() {
	g_hNavPaths = new ArrayList(sizeof(_NavPath));

	CreateNative("NavPath.iLength.get",						Native_NavPath_GetLength);
	CreateNative("NavPath.fCost.get",						Native_NavPath_GetCost);
	CreateNative("NavPath.Get",								Native_NavPath_Get);
	CreateNative("NavPath.Optimize",						Native_NavPath_Optimize);
	CreateNative("NavPath.Destroy", 						Native_NavPath_Destroy);

	CreateNative("Navigation.FindShortestPath", 			Native_Navigation_FindShortestPath);
}

//  Natives

public int Native_NavPath_GetLength(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return view_as<ArrayList>(g_hNavPaths.Get(iThis, _NavPath::hPathData)).Length;
}

public any Native_NavPath_GetCost(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return g_hNavPaths.Get(iThis, _NavPath::fCost);
}

public any Native_NavPath_Get(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iIndex = GetNativeCell(2);

	ArrayList hPathData = g_hNavPaths.Get(iThis, _NavPath::hPathData);

	PathData ePathData;
	hPathData.GetArray(iIndex, ePathData);

	SetNativeCellRef(3, ePathData.mNavNode);
	SetNativeCellRef(4, ePathData.iEntryEdge);
	SetNativeCellRef(5, ePathData.iExitEdge);
	SetNativeCellRef(6, ePathData.iExitAttachmentFlags);
	SetNativeCellRef(7, ePathData.mEdgeData);
	SetNativeCellRef(8, ePathData.iPathMode);
	SetNativeArray(9, ePathData.vecFocalPoint, sizeof(PathData::vecFocalPoint));

	return 0;
}

public any Native_NavPath_Optimize(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	Function fnCostFunc = GetNativeCell(2);
	any aData = GetNativeCell(3);
	int iStartIdx = GetNativeCell(4);
	int iEndIdx = GetNativeCell(5);
	bool bBypassWithLOS = GetNativeCell(6);

	ArrayList hPathData = g_hNavPaths.Get(iThis, _NavPath::hPathData);

	int iPathLength = hPathData.Length;
	if (iPathLength < 3) {
		return 0;
	}

	if (iEndIdx == -1) {
		iEndIdx = iPathLength;
	}

	if (iEndIdx-iStartIdx < 3) {
		return 0;
	}

	float fTimestamp = GetEngineTime();

	PathData ePathData;

	NavNode mEndNode;
	float vecEndPos[3];
	hPathData.GetArray(iEndIdx-1, ePathData);
	mEndNode = ePathData.mNavNode;
	vecEndPos = ePathData.vecFocalPoint;

	hPathData.GetArray(iStartIdx, ePathData);

	StringMap hFrontierDataMap = new StringMap();
	VertexFrontierData eVertexFrontierData;
	eVertexFrontierData.aData = iStartIdx;
	eVertexFrontierData.vecVertex = ePathData.vecFocalPoint;

	char sKey[8];
	PackCellToStr(iStartIdx, sKey);
	hFrontierDataMap.SetArray(sKey, eVertexFrontierData, sizeof(VertexFrontierData));

	ArrayList hFrontier = new ArrayList(sizeof(Frontier));
	VertexFrontier eVertexFrontier;
	eVertexFrontier.sIdentifier = sKey;
	eVertexFrontier.aData = iStartIdx;
	hFrontier.PushArray(eVertexFrontier);

	while (hFrontier.Length) {
		hFrontier.GetArray(0, eVertexFrontier);
		int iCurrentIdx = eVertexFrontier.aData;

		if (iCurrentIdx == iEndIdx-1) {
			hFrontierDataMap.GetArray(eVertexFrontier.sIdentifier, eVertexFrontierData, sizeof(VertexFrontierData));

			for (int i=iCurrentIdx-1; i>eVertexFrontierData.aData; i--) {
				hPathData.Set(i, PathMode_Bypass, PathData::iPathMode);
			}

			int iNewPathLength = 1;

			hPathData.GetArray(iCurrentIdx, ePathData);
			LocalDataPack.Destroy(ePathData.mEdgeData);
			ePathData.mEdgeData = eVertexFrontierData.mEdgeData;
			hPathData.SetArray(iCurrentIdx, ePathData);

			hFrontierDataMap.Remove(eVertexFrontier.sIdentifier);

			char sCurrentIdentifier[32];
			sCurrentIdentifier = eVertexFrontierData.sParentIdentifier;

			while (sCurrentIdentifier[0]) {
				hFrontierDataMap.GetArray(sCurrentIdentifier, eVertexFrontierData, sizeof(VertexFrontierData));

				for (int i=iCurrentIdx-1; i>eVertexFrontierData.aData; i--) {
					hPathData.Set(i, PathMode_Bypass, PathData::iPathMode);
				}

				iCurrentIdx = eVertexFrontierData.aData;

				hPathData.GetArray(iCurrentIdx, ePathData);
				ePathData.vecFocalPoint = eVertexFrontierData.vecVertex;
				LocalDataPack.Destroy(ePathData.mEdgeData);
				ePathData.mEdgeData = eVertexFrontierData.mEdgeData;
				hPathData.SetArray(iCurrentIdx, ePathData);

				hFrontierDataMap.Remove(sCurrentIdentifier);

				sCurrentIdentifier = eVertexFrontierData.sParentIdentifier;
				iNewPathLength++;
			}

			DeleteVertexEdgeData(hFrontierDataMap);

			delete hFrontierDataMap;
			delete hFrontier;

			PrintToServer("Path optimization completed after %.3f ms (%d nodes)", 1000*(GetEngineTime()-fTimestamp), iNewPathLength);

			return iNewPathLength;
		}

		hFrontier.Erase(0);

		hFrontierDataMap.GetArray(eVertexFrontier.sIdentifier, eVertexFrontierData, sizeof(VertexFrontierData));

		float fCurrentCost = hFrontierDataMap.GetArray(eVertexFrontier.sIdentifier, eVertexFrontierData, sizeof(VertexFrontierData)) ? eVertexFrontierData.fCost : 0.0;

		hPathData.GetArray(iCurrentIdx, ePathData);

		NavNode mPrevNode = ePathData.mNavNode;
		int iPrevEdge = ePathData.iExitEdge;

		float vecStartVertex[3];
		vecStartVertex = eVertexFrontierData.vecVertex;

		ArrayList hEdgeOverlaps;
		if (bBypassWithLOS) {
			hEdgeOverlaps = new ArrayList(sizeof(EdgeOverlap));
		}

		for (int iNextIdx=iCurrentIdx+1; iNextIdx<iEndIdx; iNextIdx++) {
			hPathData.GetArray(iNextIdx, ePathData);

			// Paths ending with a null node coming from an edge with no neighbor (i.e. wall)
			if (!ePathData.mNavNode) {
				break;
			}

			float vecOverlapPointA[3];
			float vecOverlapPointB[3];
			mPrevNode.GetEdgeOverlap(iPrevEdge, ePathData.mNavNode, ePathData.iEntryEdge, vecOverlapPointA, vecOverlapPointB);

			// Adjust for player collision box
			float vecOffset[3];
			SubtractVectors(vecOverlapPointB, vecOverlapPointA, vecOffset);
			NormalizeVector(vecOffset, vecOffset);
			ScaleVector(vecOffset, 50.0);
			AddVectors(vecOverlapPointA, vecOffset, vecOverlapPointA);
			SubtractVectors(vecOverlapPointB, vecOffset, vecOverlapPointB);

			bool bAddVertexA = true;
			bool bAddVertexB = true;
			bool bAddVertexEnd = false;

			if (bBypassWithLOS) {
				EdgeOverlap eEdgeOverlap;
				eEdgeOverlap.vecVertexA = vecOverlapPointA;
				eEdgeOverlap.vecVertexB = vecOverlapPointB;

				hEdgeOverlaps.PushArray(eEdgeOverlap);

				for (int i=0; i<hEdgeOverlaps.Length && (bAddVertexA || bAddVertexB); i++) {
					hEdgeOverlaps.GetArray(i, eEdgeOverlap);

					float vecOverlapVector[3];
					SubtractVectors(eEdgeOverlap.vecVertexB, eEdgeOverlap.vecVertexA, vecOverlapVector);

					if (bAddVertexA && !CheckIntersection2D(vecStartVertex, vecOverlapPointA, eEdgeOverlap.vecVertexA, eEdgeOverlap.vecVertexB)) {
						bAddVertexA = false;
					}

					if (bAddVertexB && !CheckIntersection2D(vecStartVertex, vecOverlapPointB, eEdgeOverlap.vecVertexA, eEdgeOverlap.vecVertexB)) {
						bAddVertexB = false;
					}

					if (iNextIdx == iEndIdx-1 && i == hEdgeOverlaps.Length-1 && (bAddVertexA || bAddVertexB)) {
						bAddVertexEnd = CheckIntersection2D(vecStartVertex, vecEndPos, eEdgeOverlap.vecVertexA, eEdgeOverlap.vecVertexB);
					}
				}
			}

			PackCellToStr(iNextIdx, sKey);

			if (bAddVertexA) {
				bool bAddedVertexA;
				VertexFrontierData eNewVertexFrontierData;

				char sKeyA[8];
				sKeyA = sKey;
				sKeyA[5] = 'A';

				float fNeighborCostA = hFrontierDataMap.GetArray(sKeyA, eNewVertexFrontierData, sizeof(VertexFrontierData)) ? eVertexFrontierData.fCost : POSITIVE_INFINITY;

				LocalDataPack mEdgeData = LocalDataPack.Instance();
				bool _bIgnore;
				Call_StartFunction(hPlugin, fnCostFunc);
				Call_PushCell(mPrevNode);
				Call_PushCell(iPrevEdge);
				Call_PushCell(ePathData.mNavNode);
				Call_PushCell(ePathData.iEntryEdge);
				Call_PushCell(ePathData.iExitAttachmentFlags);
				Call_PushArray(vecStartVertex, sizeof(vecStartVertex));
				Call_PushArray(vecOverlapPointA, sizeof(vecOverlapPointA));
				Call_PushCell(true);
				Call_PushCell(aData);
				Call_PushCell(mEdgeData);
				Call_PushCellRef(_bIgnore);
				Call_PushCellRef(_bIgnore);

				float fCost;
				if (Call_Finish(fCost) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
					float fNewCostA = fCurrentCost + fCost;
					if (fNewCostA < fNeighborCostA) {
						eNewVertexFrontierData.sIdentifier = sKeyA;
						eNewVertexFrontierData.sParentIdentifier = eVertexFrontier.sIdentifier;
						eNewVertexFrontierData.vecVertex = vecOverlapPointA;
						eNewVertexFrontierData.aData = iNextIdx;

						_bIgnore = false;
						Call_StartFunction(hPlugin, fnCostFunc);
						Call_PushCell(ePathData.mNavNode);
						Call_PushCell(-1);
						Call_PushCell(mEndNode);
						Call_PushCell(-1);
						Call_PushCell(0);
						Call_PushArray(vecOverlapPointA, sizeof(vecOverlapPointA));
						Call_PushArray(vecEndPos, sizeof(vecEndPos));
						Call_PushCell(true);
						Call_PushCell(aData);
						Call_PushCell(0);
						Call_PushCellRef(_bIgnore);
						Call_PushCellRef(_bIgnore);

						float fHeuristic;
						if (Call_Finish(fHeuristic) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
							eNewVertexFrontierData.fCost = fNewCostA;
							eNewVertexFrontierData.fScore = fNewCostA + fHeuristic;

							LocalDataPack.Destroy(eNewVertexFrontierData.mEdgeData);
							eNewVertexFrontierData.mEdgeData = mEdgeData;

							hFrontierDataMap.SetArray(sKeyA, eNewVertexFrontierData, sizeof(VertexFrontierData));

							if (hFrontier.FindString(sKeyA) == -1) {
								VertexFrontier eVertexFrontierNeighbor;
								eVertexFrontierNeighbor.sIdentifier = sKeyA;
								eVertexFrontierNeighbor.aData = iNextIdx;
								hFrontier.PushArray(eVertexFrontierNeighbor);
							}

							bAddedVertexA = true;
						}
					}
				}

				if (!bAddedVertexA) {
					LocalDataPack.Destroy(mEdgeData);
				}
			}

			if (bAddVertexB) {
				bool bAddedVertexB;
				VertexFrontierData eNewVertexFrontierData;

				char sKeyB[8];
				sKeyB = sKey;
				sKeyB[5] = 'B';

				float fNeighborCostB = hFrontierDataMap.GetArray(sKeyB, eNewVertexFrontierData, sizeof(VertexFrontierData)) ? eNewVertexFrontierData.fCost : POSITIVE_INFINITY;

				LocalDataPack mEdgeData = LocalDataPack.Instance();
				bool _bIgnore;
				Call_StartFunction(hPlugin, fnCostFunc);
				Call_PushCell(mPrevNode);
				Call_PushCell(iPrevEdge);
				Call_PushCell(ePathData.mNavNode);
				Call_PushCell(ePathData.iEntryEdge);
				Call_PushCell(ePathData.iExitAttachmentFlags);
				Call_PushArray(vecStartVertex, sizeof(vecStartVertex));
				Call_PushArray(vecOverlapPointB, sizeof(vecOverlapPointB));
				Call_PushCell(true);
				Call_PushCell(aData);
				Call_PushCell(mEdgeData);
				Call_PushCellRef(_bIgnore);
				Call_PushCellRef(_bIgnore);

				float fCost;
				if (Call_Finish(fCost) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
					float fNewCostB = fCurrentCost + fCost;
					if (fNewCostB < fNeighborCostB) {
						eNewVertexFrontierData.sIdentifier = sKeyB;
						eNewVertexFrontierData.sParentIdentifier = eVertexFrontier.sIdentifier;
						eNewVertexFrontierData.vecVertex = vecOverlapPointB;
						eNewVertexFrontierData.aData = iNextIdx;

						_bIgnore = false;
						Call_StartFunction(hPlugin, fnCostFunc);
						Call_PushCell(ePathData.mNavNode);
						Call_PushCell(-1);
						Call_PushCell(mEndNode);
						Call_PushCell(-1);
						Call_PushCell(0);
						Call_PushArray(vecOverlapPointB, sizeof(vecOverlapPointB));
						Call_PushArray(vecEndPos, sizeof(vecEndPos));
						Call_PushCell(true);
						Call_PushCell(aData);
						Call_PushCell(0);
						Call_PushCellRef(_bIgnore);
						Call_PushCellRef(_bIgnore);

						float fHeuristic;
						if (Call_Finish(fHeuristic) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
							eNewVertexFrontierData.fCost = fNewCostB;
							eNewVertexFrontierData.fScore = fNewCostB + fHeuristic;

							LocalDataPack.Destroy(eNewVertexFrontierData.mEdgeData);
							eNewVertexFrontierData.mEdgeData = mEdgeData;

							hFrontierDataMap.SetArray(sKeyB, eNewVertexFrontierData, sizeof(VertexFrontierData));

							if (hFrontier.FindString(sKeyB) == -1) {
								VertexFrontier eVertexFrontierNeighbor;
								eVertexFrontierNeighbor.sIdentifier = sKeyB;
								eVertexFrontierNeighbor.aData = iNextIdx;
								hFrontier.PushArray(eVertexFrontierNeighbor);
							}

							bAddedVertexB = true;
						}
					}
				}

				if (!bAddedVertexB) {
					LocalDataPack.Destroy(mEdgeData);
				}
			}

			if (bAddVertexEnd) {
				bool bAddedVertexEnd;
				VertexFrontierData eNewVertexFrontierData;

				char sKeyEnd[8];
				sKeyEnd = sKey;
				sKeyEnd[5] = 'E';

				float fNeighborCostEnd = hFrontierDataMap.GetArray(sKeyEnd, eNewVertexFrontierData, sizeof(VertexFrontierData)) ? eNewVertexFrontierData.fCost : POSITIVE_INFINITY;

				LocalDataPack mEdgeData = LocalDataPack.Instance();
				bool _bIgnore;
				Call_StartFunction(hPlugin, fnCostFunc);
				Call_PushCell(ePathData.mNavNode);
				Call_PushCell(-1);
				Call_PushCell(mEndNode);
				Call_PushCell(-1);
				Call_PushCell(0);
				Call_PushArray(vecStartVertex, sizeof(vecStartVertex));
				Call_PushArray(vecEndPos, sizeof(vecEndPos));
				Call_PushCell(true);
				Call_PushCell(aData);
				Call_PushCell(mEdgeData);
				Call_PushCellRef(_bIgnore);
				Call_PushCellRef(_bIgnore);

				float fCost;
				if (Call_Finish(fCost) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
					float fNewCostEnd = fCurrentCost + fCost
					if (fNewCostEnd < fNeighborCostEnd) {
						eNewVertexFrontierData.sIdentifier = sKeyEnd;
						eNewVertexFrontierData.sParentIdentifier = eVertexFrontier.sIdentifier;
						eNewVertexFrontierData.vecVertex = vecEndPos;
						eNewVertexFrontierData.aData = iNextIdx;

						eNewVertexFrontierData.fCost = fNewCostEnd;
						eNewVertexFrontierData.fScore = 0.0;

						LocalDataPack.Destroy(eNewVertexFrontierData.mEdgeData);
						eNewVertexFrontierData.mEdgeData = mEdgeData;

						hFrontierDataMap.SetArray(sKeyEnd, eNewVertexFrontierData, sizeof(VertexFrontierData));

						if (hFrontier.FindString(sKeyEnd) == -1) {
							VertexFrontier eVertexFrontierNeighbor;
							eVertexFrontierNeighbor.sIdentifier = sKeyEnd;
							eVertexFrontierNeighbor.aData = iNextIdx;
							hFrontier.PushArray(eVertexFrontierNeighbor);
						}

						bAddedVertexEnd = true;
					}
				}

				if (!bAddedVertexEnd) {
					LocalDataPack.Destroy(mEdgeData);
				}
			}

			if (bBypassWithLOS && (bAddVertexA || bAddVertexB)) {
				mPrevNode = ePathData.mNavNode;
				iPrevEdge = ePathData.iExitEdge;

				continue;
			}

			break;
		}

		delete hEdgeOverlaps;

		// TODO: Priority queue
		hFrontier.SortCustom(Sort_VertexHorizon_FScore, hFrontierDataMap);
	}

	DeleteVertexEdgeData(hFrontierDataMap);

	delete hFrontierDataMap;
	delete hFrontier;

	PrintToServer("Path optimization failed after %.3f ms", 1000*(GetEngineTime()-fTimestamp));

	return 0;
}

public any Native_NavPath_Destroy(Handle hPlugin, int iArgC) {
	int iNavPathIdx = GetNativeCellRef(1)-1;
	if (iNavPathIdx < 0 || iNavPathIdx >= g_hNavPaths.Length) {
		return 0;
	}

	ArrayList hPathData = g_hNavPaths.Get(iNavPathIdx, _NavPath::hPathData);

	for (int i=0; i<hPathData.Length; i++) {
		LocalDataPack mEdgeData = hPathData.Get(i, PathData::mEdgeData);
		LocalDataPack.Destroy(mEdgeData);
	}

	delete hPathData;

	g_hNavPaths.Set(iNavPathIdx, true, _NavPath::bGCFlag);

	SetNativeCellRef(1, NULL_NAV_PATH);

	return 0;
}

public any Native_Navigation_FindShortestPath(Handle hPlugin, int iArgC) {
	float fTimestamp = GetEngineTime();

	NavNode mStartNode = GetNativeCell(1);
	NavNode mEndNode = GetNativeCell(2);

	if (!mStartNode) {
		return NULL_NAV_PATH;
	}

	Function fnCostFunc = GetNativeFunction(3);

	any aData = GetNativeCell(4);

	float vecStartPos[3];
	GetNativeArray(5, vecStartPos, sizeof(vecStartPos));

	bool bCustomStartPos = vecStartPos[0] == vecStartPos[0] && vecStartPos[1] == vecStartPos[1] && vecStartPos[2] == vecStartPos[2];
	if (!bCustomStartPos) {
		mStartNode.GetOrigin(vecStartPos);
	} else if(!mStartNode.Contains(vecStartPos)) {
		LogError("Start position (%.1f, %.1f, %.1f) is not within start node", vecStartPos[0], vecStartPos[1], vecStartPos[2]);
		return NULL_NAV_PATH;
	}

	float vecEndPos[3];
	GetNativeArray(6, vecEndPos, sizeof(vecEndPos));

	if (mEndNode) {
		bool bCustomEndPos = vecEndPos[0] == vecEndPos[0] && vecEndPos[1] == vecEndPos[1] && vecEndPos[2] == vecEndPos[2];
		if (!bCustomEndPos) {
			mEndNode.GetOrigin(vecEndPos);
		} else if (!mEndNode.Contains(vecEndPos)) {
			LogError("End position (%.1f, %.1f, %.1f) is not within end node", vecEndPos[0], vecEndPos[1], vecEndPos[2]);
			return NULL_NAV_PATH;
		}
	}

	StringMap hFrontierDataMap = new StringMap();

	FrontierData eFrontierData;
	eFrontierData.mNode = mStartNode;
	eFrontierData.iParentEdge = -1;
	eFrontierData.vecFocalPoint = vecStartPos;

	char sKey[32];
	PackCellToStr(mStartNode, sKey);
	hFrontierDataMap.SetArray(sKey, eFrontierData, sizeof(FrontierData));

	ArrayList hFrontier = new ArrayList(sizeof(Frontier));
	Frontier eFrontier;
	eFrontier.sIdentifier = sKey;
	eFrontier.mNode = mStartNode;
	hFrontier.PushArray(eFrontier);

	float fGoalEdgeTotalCost = POSITIVE_INFINITY;
	NavPath mGoalEdgeNavPath;

	while (hFrontier.Length) {
		hFrontier.GetArray(0, eFrontier);
		NavNode mCurrentNode = eFrontier.mNode;

		hFrontierDataMap.GetArray(eFrontier.sIdentifier, eFrontierData, sizeof(FrontierData));

		if (mCurrentNode == mEndNode) {
			float fTotalCost = eFrontierData.fCost;

			eFrontierData.vecFocalPoint = vecEndPos;

			ArrayList hPathData = BuildPathData(hFrontierDataMap, eFrontierData, true);

			delete hFrontierDataMap;
			delete hFrontier;

			PrintToServer("Main search completed with end node in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

			return CreateNavPath(hPathData, fTotalCost);
		}

		hFrontier.Erase(0);

		int iVertices = mCurrentNode.iVertices;

		float vecFocalPointCurrent[3];
		vecFocalPointCurrent = eFrontierData.vecFocalPoint;

		for (int i=0; i<iVertices; i++) {
			int iAttachmentsLength = mCurrentNode.GetAttachmentsLength(i);
			for (int j=0; j<iAttachmentsLength; j++) {
				NavNode mAttachedNode;
				int iAttachedNodeEdge;
				int iAttachmentFlags;
				mCurrentNode.GetAttachment(i, j, mAttachedNode, iAttachedNodeEdge, iAttachmentFlags);

				float vecFocalPointNeighbor[3];

				if (mAttachedNode) {
					mAttachedNode.GetOrigin(vecFocalPointNeighbor);
				} else if (mEndNode) {
					continue;
				} else {
					mCurrentNode.GetEdgeCenter(i, vecFocalPointNeighbor);
				}

				LocalDataPack mEdgeData = LocalDataPack.Instance();
				bool bMarkGoalNode;
				bool bMarkGoalEdge;
				Call_StartFunction(hPlugin, fnCostFunc);
				Call_PushCell(mCurrentNode);
				Call_PushCell(i);
				Call_PushCell(mAttachedNode);
				Call_PushCell(iAttachedNodeEdge);
				Call_PushCell(iAttachmentFlags);
				Call_PushArray(vecFocalPointCurrent, sizeof(vecFocalPointCurrent));
				Call_PushArray(vecFocalPointNeighbor, sizeof(vecFocalPointNeighbor));
				Call_PushCell(false);
				Call_PushCell(aData);
				Call_PushCell(mEdgeData);
				Call_PushCellRef(bMarkGoalNode);
				Call_PushCellRef(bMarkGoalEdge);

				// Make sure cost is not NaN (since NaN != NaN) or +infinity (unreachable)
				float fCost;
				if (Call_Finish(fCost) != SP_ERROR_NONE || fCost != fCost || fCost == POSITIVE_INFINITY) {
					LocalDataPack.Destroy(mEdgeData);
					continue;
				}

				float fTotalCost = eFrontierData.fCost + fCost;

				if (mAttachedNode && bMarkGoalNode) {
					if (bMarkGoalEdge) {
						mCurrentNode.GetEdgeCenter(i, vecFocalPointNeighbor);
					} else if (mAttachedNode == mEndNode) {
						vecFocalPointNeighbor = vecEndPos;
					}

					// Recreate same conditions as if the node was found through frontier traversal

					PackCellToStr(mAttachedNode, sKey);

					FrontierData eNewFrontierData;
					hFrontierDataMap.GetArray(sKey, eNewFrontierData, sizeof(FrontierData));

					eNewFrontierData.sIdentifier = sKey;
					eNewFrontierData.sParentIdentifier = eFrontier.sIdentifier;
// 					eNewFrontierData.mParentNode = mCurrentNode; // Not needed for BuildPathData
					eNewFrontierData.iParentEdge = i;
					eNewFrontierData.iParentAttachmentFlags = iAttachmentFlags;
					eNewFrontierData.mNode = mAttachedNode;
					eNewFrontierData.iEdge = iAttachedNodeEdge;
// 					eNewFrontierData.fCost = fTotalCost;  // Not needed for BuildPathData
					eNewFrontierData.vecFocalPoint = vecFocalPointNeighbor;

					LocalDataPack.Destroy(eNewFrontierData.mEdgeData);
					eNewFrontierData.mEdgeData = mEdgeData;

					hFrontierDataMap.SetArray(sKey, eNewFrontierData, sizeof(FrontierData));

					ArrayList hPathData = BuildPathData(hFrontierDataMap, eNewFrontierData, true);

					delete hFrontierDataMap;
					delete hFrontier;

					PrintToServer("Main search stopped with goal node in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

					return CreateNavPath(hPathData, fTotalCost);
				}

				if (!mEndNode && bMarkGoalEdge) {
					mCurrentNode.GetEdgeCenter(i, vecFocalPointNeighbor);

					// Goal is on exit edge of current node, so recalculate cost from parent node if it exists,
					// rather than adding cost from parent to center of current node to cost from center to goal edge.

					FrontierData eParentData;
					if (hFrontierDataMap.GetArray(eFrontierData.sParentIdentifier, eParentData, sizeof(FrontierData))) {
						LocalDataPack.Destroy(mEdgeData);

						mEdgeData = LocalDataPack.Instance();
						bool bIgnore;
						Call_StartFunction(hPlugin, fnCostFunc);
						Call_PushCell(eParentData.mNode);
						Call_PushCell(i);
						Call_PushCell(mCurrentNode);
						Call_PushCell(eFrontierData.iParentEdge);
						Call_PushCell(eFrontierData.iParentAttachmentFlags);
						Call_PushArray(eParentData.vecFocalPoint, sizeof(vecFocalPointCurrent));
						Call_PushArray(vecFocalPointNeighbor, sizeof(vecFocalPointNeighbor));
						Call_PushCell(false);
						Call_PushCell(aData);
						Call_PushCell(mEdgeData);
						Call_PushCellRef(bIgnore);
						Call_PushCellRef(bIgnore);

						if (Call_Finish(fCost) != SP_ERROR_NONE || fCost != fCost || fCost == POSITIVE_INFINITY) {
							LocalDataPack.Destroy(mEdgeData);
							continue;
						}

						fTotalCost = eParentData.fCost + fCost;
					}

					if (fTotalCost < fGoalEdgeTotalCost) {
						fGoalEdgeTotalCost = fTotalCost;

						// Recreate same conditions as if the node with goal edge was found through frontier traversal

						FrontierData eNewFrontierData;

						eNewFrontierData.sIdentifier = sKey;
						eNewFrontierData.sParentIdentifier = eFrontier.sIdentifier;
// 						eNewFrontierData.mParentNode = mCurrentNode; // Not needed for BuildPathData
						eNewFrontierData.iParentEdge = i;
						eNewFrontierData.iParentAttachmentFlags = iAttachmentFlags;
						eNewFrontierData.mNode = mAttachedNode;
						eNewFrontierData.iEdge = iAttachedNodeEdge;
// 						eNewFrontierData.fCost = fTotalCost; // Not needed for BuildPathData
						eNewFrontierData.vecFocalPoint = vecFocalPointNeighbor;
						eNewFrontierData.mEdgeData = mEdgeData;

						ArrayList hPathData = BuildPathData(hFrontierDataMap, eNewFrontierData, false, true);

						NavPath.Destroy(mGoalEdgeNavPath);
						mGoalEdgeNavPath = CreateNavPath(hPathData, fTotalCost);
					} else {
						LocalDataPack.Destroy(mEdgeData);
					}

					continue;
				}

				if (!mAttachedNode) {
					LocalDataPack.Destroy(mEdgeData);
					continue;
				}

				FrontierData eNewFrontierData;

				PackCellToStr(mAttachedNode, sKey);
				float fNeighborCost = hFrontierDataMap.GetArray(sKey, eNewFrontierData, sizeof(FrontierData)) ? eNewFrontierData.fCost : POSITIVE_INFINITY;
				float fNewCost = eFrontierData.fCost + fCost;

				if (fNewCost >= fNeighborCost || fNewCost > fGoalEdgeTotalCost) {
					LocalDataPack.Destroy(mEdgeData);
					continue;
				}

				eNewFrontierData.sIdentifier = sKey;
				eNewFrontierData.sParentIdentifier = eFrontier.sIdentifier;
				eNewFrontierData.mParentNode = mCurrentNode;
				eNewFrontierData.iParentEdge = i;
				eNewFrontierData.iParentAttachmentFlags = iAttachmentFlags;
				eNewFrontierData.mNode = mAttachedNode;
				eNewFrontierData.iEdge = iAttachedNodeEdge;
				eNewFrontierData.fCost = fNewCost;
				eNewFrontierData.vecFocalPoint = vecFocalPointNeighbor;

				if (mEndNode) {
					bMarkGoalNode = false;
					bMarkGoalEdge = false;
					Call_StartFunction(hPlugin, fnCostFunc);
					Call_PushCell(mAttachedNode);
					Call_PushCell(-1);
					Call_PushCell(mEndNode);
					Call_PushCell(-1);
					Call_PushCell(0);
					Call_PushArray(vecFocalPointNeighbor, sizeof(vecFocalPointNeighbor));
					Call_PushArray(vecEndPos, sizeof(vecEndPos));
					Call_PushCell(true);
					Call_PushCell(aData);
					Call_PushCell(0);
					Call_PushCellRef(bMarkGoalNode);
					Call_PushCellRef(bMarkGoalEdge);

					float fHeuristic;
					if (Call_Finish(fHeuristic) == SP_ERROR_NONE && fHeuristic == fHeuristic && fHeuristic != POSITIVE_INFINITY) {
						eNewFrontierData.fScore = fNewCost + fHeuristic;
					} else {
						LocalDataPack.Destroy(mEdgeData);
						continue;
					}
				}

				LocalDataPack.Destroy(eNewFrontierData.mEdgeData);
				eNewFrontierData.mEdgeData = mEdgeData;

				hFrontierDataMap.SetArray(sKey, eNewFrontierData, sizeof(FrontierData));

				if (hFrontier.FindString(sKey) == -1) {
					Frontier eFrontierNeighbor;
					eFrontierNeighbor.sIdentifier = sKey;
					eFrontierNeighbor.mNode = mAttachedNode;
					hFrontier.PushArray(eFrontierNeighbor);
				}
			}
		}

		// TODO: Priority queue
		hFrontier.SortCustom(mEndNode ? Sort_Horizon_FScore : Sort_Horizon_Cost, hFrontierDataMap);
	}

	DeleteEdgeData(hFrontierDataMap);

	delete hFrontierDataMap;
	delete hFrontier;

	if (mGoalEdgeNavPath) {
		PrintToServer("Main search completed with goal edge in %.3f ms", 1000*(GetEngineTime()-fTimestamp));
		return mGoalEdgeNavPath;
	}

	PrintToServer("Main search completed with no path in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

	return NULL_NAV_PATH;
}

// Custom callbacks

int Sort_Horizon_Cost(int iIdxA, int iIdxB, Handle hArray, Handle hHndl) {
	ArrayList hFrontier = view_as<ArrayList>(hArray);
	StringMap hFrontierDataMap = view_as<StringMap>(hHndl);

	FrontierData eFrontierData;
	char sKey[32];

	hFrontier.GetString(iIdxA, sKey, sizeof(sKey));
	float fScoreA = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fCost : POSITIVE_INFINITY;

	hFrontier.GetString(iIdxB, sKey, sizeof(sKey));
	float fScoreB = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fCost : POSITIVE_INFINITY;

	return RoundToNearest(fScoreA-fScoreB);
}

int Sort_Horizon_FScore(int iIdxA, int iIdxB, Handle hArray, Handle hHndl) {
	ArrayList hFrontier = view_as<ArrayList>(hArray);
	StringMap hFrontierDataMap = view_as<StringMap>(hHndl);

	FrontierData eFrontierData;
	char sKey[32];

	hFrontier.GetString(iIdxA, sKey, sizeof(sKey));
	float fScoreA = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fScore : POSITIVE_INFINITY;

	hFrontier.GetString(iIdxB, sKey, sizeof(sKey));
	float fScoreB = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fScore : POSITIVE_INFINITY;

	return RoundToNearest(fScoreA-fScoreB);
}

int Sort_VertexHorizon_FScore(int iIdxA, int iIdxB, Handle hArray, Handle hHndl) {
	ArrayList hFrontier = view_as<ArrayList>(hArray);
	StringMap hFrontierDataMap = view_as<StringMap>(hHndl);

	VertexFrontierData eVertexFrontierData;
	char sKey[32];

	hFrontier.GetString(iIdxA, sKey, sizeof(sKey));
	float fScoreA = hFrontierDataMap.GetArray(sKey, eVertexFrontierData, sizeof(VertexFrontierData)) ? eVertexFrontierData.fScore : POSITIVE_INFINITY;

	hFrontier.GetString(iIdxB, sKey, sizeof(sKey));
	float fScoreB = hFrontierDataMap.GetArray(sKey, eVertexFrontierData, sizeof(VertexFrontierData)) ? eVertexFrontierData.fScore : POSITIVE_INFINITY;

	return RoundToNearest(fScoreA-fScoreB);
}

// Helpers

NavPath CreateNavPath(ArrayList hPathData, float fCost) {
	_NavPath eNavPath;
	eNavPath.hPathData = hPathData;
	eNavPath.fCost = fCost;

	int iFreeIdx = g_hNavPaths.FindValue(true, _NavPath::bGCFlag);
	if (iFreeIdx != -1) {
		g_hNavPaths.SetArray(iFreeIdx, eNavPath);
		return view_as<NavPath>(iFreeIdx+1);
	}

	return view_as<NavPath>(g_hNavPaths.PushArray(eNavPath)+1);
}

void DeleteEdgeData(StringMap hFrontierDataMap) {
	StringMapSnapshot hSnapshot = hFrontierDataMap.Snapshot();

	char sKey[32];
	FrontierData eFrontierData;

	for (int i=0; i<hSnapshot.Length; i++) {
		hSnapshot.GetKey(i, sKey, sizeof(sKey));
		hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData));
		LocalDataPack.Destroy(eFrontierData.mEdgeData);
	}

	delete hSnapshot;
}

void DeleteVertexEdgeData(StringMap hFrontierDataMap) {
	StringMapSnapshot hSnapshot = hFrontierDataMap.Snapshot();

	char sKey[32];
	VertexFrontierData eVertexFrontierData;

	for (int i=0; i<hSnapshot.Length; i++) {
		hSnapshot.GetKey(i, sKey, sizeof(sKey));
		hFrontierDataMap.GetArray(sKey, eVertexFrontierData, sizeof(eVertexFrontierData));
		LocalDataPack.Destroy(eVertexFrontierData.mEdgeData);
	}

	delete hSnapshot;
}

ArrayList BuildPathData(StringMap hFrontierDataMap, FrontierData eFrontierData, bool bDeleteFrontierEdgeData, bool bCloneEdgeData=false) {
	ArrayList hPathResult = new ArrayList(sizeof(PathData));

	PathData ePathData;
	ePathData.mNavNode = eFrontierData.mNode;
	int iParentExitEdge = eFrontierData.iParentEdge;
	int iParentExitAttachmentFlags = eFrontierData.iParentAttachmentFlags;
	ePathData.iEntryEdge = eFrontierData.iEdge;
	ePathData.iExitEdge = -1;
	ePathData.iExitAttachmentFlags = 0;
	ePathData.mEdgeData = eFrontierData.mEdgeData;
	ePathData.vecFocalPoint = eFrontierData.vecFocalPoint;

	hPathResult.PushArray(ePathData);

	if (bDeleteFrontierEdgeData) {
		hFrontierDataMap.Remove(eFrontierData.sIdentifier);
	}

	char sCurrentIdentifier[32];
	sCurrentIdentifier = eFrontierData.sParentIdentifier;

	while (sCurrentIdentifier[0]) {
		hFrontierDataMap.GetArray(sCurrentIdentifier, eFrontierData, sizeof(FrontierData));

		ePathData.mNavNode = eFrontierData.mNode;
		ePathData.iEntryEdge = eFrontierData.iEdge;
		ePathData.iExitEdge = iParentExitEdge;
		ePathData.iExitAttachmentFlags = iParentExitAttachmentFlags;
		ePathData.mEdgeData = bCloneEdgeData ? eFrontierData.mEdgeData.Clone() : eFrontierData.mEdgeData;
		ePathData.vecFocalPoint = eFrontierData.vecFocalPoint;
		ePathData.iPathMode = PathMode_Normal;

		iParentExitEdge = eFrontierData.iParentEdge;
		iParentExitAttachmentFlags = eFrontierData.iParentAttachmentFlags;

		hPathResult.ShiftUp(0);
		hPathResult.SetArray(0, ePathData);

		if (bDeleteFrontierEdgeData) {
			hFrontierDataMap.Remove(sCurrentIdentifier);
		}

		sCurrentIdentifier = eFrontierData.sParentIdentifier;
	}

	if (bDeleteFrontierEdgeData) {
		DeleteEdgeData(hFrontierDataMap);
	}

	return hPathResult;
}

/**
 * PackCellToStr
 * Credit: Asher 'Asherkin' Baker
 * Packs a key, as an integer, into a null-terminated buffer.
 */
void PackCellToStr(any aKey, char[] sBuffer) {
	int i = aKey;
	sBuffer[0] = ((i >> 28) & 0x7F) | 0x80;
	sBuffer[1] = ((i >> 21) & 0x7F) | 0x80;
	sBuffer[2] = ((i >> 14) & 0x7F) | 0x80;
	sBuffer[3] = ((i >>  7) & 0x7F) | 0x80;
	sBuffer[4] = ((i      ) & 0x7F) | 0x80;
	sBuffer[5] = 0;
}

// Adapted from https://www.geeksforgeeks.org/orientation-3-ordered-points/
Orientation GetOrientation2D(float vec1[3], float vec2[3], float vec3[3]) {
	float fVal =	(vec2[1]-vec1[1]) * (vec3[0]-vec2[0]) -
					(vec2[0]-vec1[0]) * (vec3[1]-vec2[1]);

	if (FloatAbs(fVal) < 0.01) {
		return Orientation_Colinear;
	}

	return fVal > 0 ? Orientation_Clockwise : Orientation_CounterClockwise;
}

// Adapted from https://www.geeksforgeeks.org/check-if-two-given-line-segments-intersect/
bool CheckIntersection2D(float vecLineAPointA[3], float vecLineAPointB[3], float vecLineBPointA[3], float vecLineBPointB[3]) {
	Orientation iO1 = GetOrientation2D(vecLineAPointA, vecLineAPointB, vecLineBPointA);
	Orientation iO2 = GetOrientation2D(vecLineAPointA, vecLineAPointB, vecLineBPointB);
	Orientation iO3 = GetOrientation2D(vecLineBPointA, vecLineBPointB, vecLineAPointA);
	Orientation iO4 = GetOrientation2D(vecLineBPointA, vecLineBPointB, vecLineAPointB);

	// General case
	if (iO1 != iO2 && iO3 != iO4) {
		return true;
	}

	// Omit co-linear special cases not applicable for our use case

	return false;
}
