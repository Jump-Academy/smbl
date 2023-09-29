#include <sdktools_trace>

#define POSITIVE_INFINITY		view_as<float>(0x7F800000)
#define NEGATIVE_INFINITY		view_as<float>(0xFF800000)

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
	float fCost;
	float fScore;		// Cost + Heuristic
}

enum struct EdgeOverlap {
	float vecVertexA[3];
	float vecVertexB[3];
}

void SetupPathNatives() {
	CreateNative("Navigation.FindShortestPath", 			Native_Navigation_FindShortestPath);
	CreateNative("Navigation.OptimizePath", 				Native_Navigation_OptimizePath);
	CreateNative("Navigation.FindNearby", 					Native_Navigation_FindNearby);
}

//  Natives

public any Native_Navigation_FindShortestPath(Handle hPlugin, int iArgC) {
	float fTimestamp = GetEngineTime();

	NavNode mStartNode = GetNativeCell(1);
	NavNode mEndNode = GetNativeCell(2);

	if (!mStartNode || !mEndNode) {
		return POSITIVE_INFINITY;
	}

	Function fnCostFunc = GetNativeFunction(3);

	ArrayList hPathResult = GetNativeCell(4);
	if (hPathResult.BlockSize != sizeof(PathData)) {
		ThrowError("Path result array block size must match PathData");
	}

	any aData = GetNativeCell(5);

	float vecStartPos[3];
	GetNativeArray(6, vecStartPos, sizeof(vecStartPos));

	bool bCustomStartPos = vecStartPos[0] == vecStartPos[0] && vecStartPos[1] == vecStartPos[1] && vecStartPos[2] == vecStartPos[2];
	if (!bCustomStartPos) {
		mStartNode.GetOrigin(vecStartPos);
	} else if(!mStartNode.Contains(vecStartPos)) {
		ThrowError("Start position (%.1f, %.1f, %.1f) is not within start node", vecStartPos[0], vecStartPos[1], vecStartPos[2]);
	}

	float vecEndPos[3];
	GetNativeArray(7, vecEndPos, sizeof(vecEndPos));

	bool bCustomEndPos = vecEndPos[0] == vecEndPos[0] && vecEndPos[1] == vecEndPos[1] && vecEndPos[2] == vecEndPos[2];
	if (!bCustomEndPos) {
		mEndNode.GetOrigin(vecEndPos);
	} else if (!mEndNode.Contains(vecEndPos)) {
		ThrowError("End position (%.1f, %.1f, %.1f) is not within end node", vecEndPos[0], vecEndPos[1], vecEndPos[2]);
	}

	StringMap hFrontierDataMap = new StringMap();
	FrontierData eFrontierData; // Default initialization with NULL_NODE mParentNode and 0 elsewhere
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

	while (hFrontier.Length) {
		hFrontier.GetArray(0, eFrontier);
		NavNode mCurrentNode = eFrontier.mNode;

		if (mCurrentNode == mEndNode) {
			hFrontierDataMap.GetArray(eFrontier.sIdentifier, eFrontierData, sizeof(FrontierData));

			float fTotalCost = eFrontierData.fCost;

			PathData ePathData;
			ePathData.mNavNode = mCurrentNode;
			int iParentExitEdge = eFrontierData.iParentEdge;
			int iParentExitAttachmentFlags = eFrontierData.iParentAttachmentFlags;
			ePathData.iEntryEdge = eFrontierData.iEdge;
			ePathData.iExitEdge = -1;
			ePathData.iExitAttachmentFlags = 0;
			ePathData.vecFocalPoint = vecEndPos;

			hPathResult.PushArray(ePathData);

			char sCurrentIdentifier[32];
			sCurrentIdentifier = eFrontierData.sParentIdentifier;

			while (sCurrentIdentifier[0]) {
				hFrontierDataMap.GetArray(sCurrentIdentifier, eFrontierData, sizeof(FrontierData));

				ePathData.mNavNode = eFrontierData.mNode;
				ePathData.iEntryEdge = eFrontierData.iEdge;
				ePathData.iExitEdge = iParentExitEdge;
				ePathData.iExitAttachmentFlags = iParentExitAttachmentFlags;
				ePathData.vecFocalPoint = eFrontierData.vecFocalPoint;
				ePathData.iPathMode = PathMode_Normal;

				iParentExitEdge = eFrontierData.iParentEdge;
				iParentExitAttachmentFlags = eFrontierData.iParentAttachmentFlags;

				hPathResult.ShiftUp(0);
				hPathResult.SetArray(0, ePathData);

				sCurrentIdentifier = eFrontierData.sParentIdentifier;
			}

			PrintToServer("Main search completed in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

			delete hFrontierDataMap;
			delete hFrontier;

			return fTotalCost;
		}

		hFrontier.Erase(0);

		int iVertices = mCurrentNode.iVertices;

		float vecFocalPointCurrent[3], vecFocalPointNeighbor[3];
		vecFocalPointCurrent = eFrontierData.vecFocalPoint;

		float fCurrentCost = hFrontierDataMap.GetArray(eFrontier.sIdentifier, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fCost : 0.0;

		for (int i=0; i<iVertices; i++) {
			int iAttachmentsLength = mCurrentNode.GetAttachmentsLength(i);
			for (int j=0; j<iAttachmentsLength; j++) {
				NavNode mAttachedNode;
				int iAttachedNodeEdge;
				int iAttachmentFlags;
				mCurrentNode.GetAttachment(i, j, mAttachedNode, iAttachedNodeEdge, iAttachmentFlags);

				if (!mAttachedNode) {
					continue;
				}

				mAttachedNode.GetOrigin(vecFocalPointNeighbor);

				bool bStop;
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
				Call_PushCellRef(bStop);

				// Make sure cost is not NaN (since NaN != NaN) or +infinity (unreachable)
				float fCost;
				if (Call_Finish(fCost) == SP_ERROR_NONE) {
					if (bStop) {
						PathData ePathData;
						ePathData.iPathMode = PathMode_Normal;

						int iParentExitEdge = i;
						int iParentExitAttachmentFlags = iAttachmentFlags;
						ePathData.mNavNode = mAttachedNode;
						ePathData.iEntryEdge = iAttachedNodeEdge;
						ePathData.iExitEdge = -1;
						ePathData.iExitAttachmentFlags = 0;

						if (mAttachedNode == mEndNode) {
							ePathData.vecFocalPoint = vecEndPos;
						} else {
							mAttachedNode.GetOrigin(ePathData.vecFocalPoint);
						}

						hPathResult.PushArray(ePathData);

						float fTotalCost = eFrontierData.fCost + fCost;

						ePathData.mNavNode = eFrontierData.mNode;
						ePathData.iEntryEdge = eFrontierData.iEdge;
						ePathData.iExitEdge = iParentExitEdge;
						ePathData.iExitAttachmentFlags = iParentExitAttachmentFlags;
						ePathData.vecFocalPoint = eFrontierData.vecFocalPoint;
						ePathData.iPathMode = PathMode_Normal;

						iParentExitEdge = eFrontierData.iParentEdge;
						iParentExitAttachmentFlags = eFrontierData.iParentAttachmentFlags;

						hPathResult.ShiftUp(0);
						hPathResult.SetArray(0, ePathData);

						char sCurrentIdentifier[32];
						sCurrentIdentifier = eFrontierData.sParentIdentifier;

						while (sCurrentIdentifier[0]) {
							hFrontierDataMap.GetArray(sCurrentIdentifier, eFrontierData, sizeof(FrontierData));

							ePathData.mNavNode = eFrontierData.mNode;
							ePathData.iEntryEdge = eFrontierData.iEdge;
							ePathData.iExitEdge = iParentExitEdge;
							ePathData.iExitAttachmentFlags = iParentExitAttachmentFlags;
							ePathData.vecFocalPoint = eFrontierData.vecFocalPoint;
							ePathData.iPathMode = PathMode_Normal;

							iParentExitEdge = eFrontierData.iParentEdge;
							iParentExitAttachmentFlags = eFrontierData.iParentAttachmentFlags;

							hPathResult.ShiftUp(0);
							hPathResult.SetArray(0, ePathData);

							sCurrentIdentifier = eFrontierData.sParentIdentifier;
						}

						PrintToServer("Main search stopped in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

						delete hFrontierDataMap;
						delete hFrontier;

						return fTotalCost;
					}

					if (fCost == fCost && fCost != POSITIVE_INFINITY) {
						PackCellToStr(mAttachedNode, sKey);
						float fNeighborCost = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fCost : POSITIVE_INFINITY;
						float fNewCost = fCurrentCost + fCost;

						if (fNewCost < fNeighborCost) {
							eFrontierData.sIdentifier = sKey;
							eFrontierData.sParentIdentifier = eFrontier.sIdentifier;
							eFrontierData.mParentNode = mCurrentNode;
							eFrontierData.iParentEdge = i;
							eFrontierData.iParentAttachmentFlags = iAttachmentFlags;
							eFrontierData.mNode = mAttachedNode;
							eFrontierData.iEdge = iAttachedNodeEdge;

							eFrontierData.vecFocalPoint = vecFocalPointNeighbor;

							bStop = false;
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
							Call_PushCellRef(bStop);

							float fHeuristic;
							if (Call_Finish(fHeuristic) == SP_ERROR_NONE && fHeuristic == fHeuristic && fHeuristic != POSITIVE_INFINITY) {
								eFrontierData.fCost = fNewCost;
								eFrontierData.fScore = fNewCost + fHeuristic;
								hFrontierDataMap.SetArray(sKey, eFrontierData, sizeof(FrontierData));

								if (hFrontier.FindString(sKey) == -1) {
									Frontier eFrontierNeighbor;
									eFrontierNeighbor.sIdentifier = sKey;
									eFrontierNeighbor.mNode = mAttachedNode;
									hFrontier.PushArray(eFrontierNeighbor);
								}
							}
						}
					}
				}
			}
		}

		// TODO: Priority queue
		SortADTArrayCustom(hFrontier, Sort_Horizon_FScore, hFrontierDataMap);
	}

	delete hFrontierDataMap;
	delete hFrontier;

	PrintToServer("Main search completed with no path in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

	return POSITIVE_INFINITY; // Not found, so infinite cost
}

public any Native_Navigation_OptimizePath(Handle hPlugin, int iArgC) {
	float fTimestamp = GetEngineTime();
	ArrayList hPath = GetNativeCell(1);
	Function fnCostFunc = GetNativeCell(2);
	any aData = GetNativeCell(3);
	int iStartIdx = GetNativeCell(4);
	int iEndIdx = GetNativeCell(5);
	bool bBypassWithLOS = GetNativeCell(6);

	int iPathLength = hPath.Length;
	if (iPathLength < 2) {
		return 0;
	}

	if (iEndIdx == -1) {
		iEndIdx = iPathLength;
	}

	if (iEndIdx-iStartIdx < 2) {
		return 0;
	}

	PathData ePathData;

	NavNode mEndNode;
	float vecEndPos[3];
	hPath.GetArray(iEndIdx-1, ePathData);
	mEndNode = ePathData.mNavNode;
	vecEndPos = ePathData.vecFocalPoint;

	hPath.GetArray(iStartIdx, ePathData);

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
				hPath.Set(i, PathMode_Bypass, PathData::iPathMode);
			}

			int iNewPathLength = 1;

			char sCurrentIdentifier[32];
			sCurrentIdentifier = eVertexFrontierData.sParentIdentifier;

			while (sCurrentIdentifier[0]) {
				hFrontierDataMap.GetArray(sCurrentIdentifier, eVertexFrontierData, sizeof(VertexFrontierData));

				for (int i=iCurrentIdx-1; i>eVertexFrontierData.aData; i--) {
					hPath.Set(i, PathMode_Bypass, PathData::iPathMode);
				}

// 				DrawDebugLine(ePathData.vecFocalPoint, eVertexFrontierData.vecVertex, {255,0,0,255}, 10.0)

				iCurrentIdx = eVertexFrontierData.aData;

				hPath.GetArray(iCurrentIdx, ePathData);
				ePathData.vecFocalPoint = eVertexFrontierData.vecVertex;
				hPath.SetArray(iCurrentIdx, ePathData);


				sCurrentIdentifier = eVertexFrontierData.sParentIdentifier;
				iNewPathLength++;
			}

			delete hFrontierDataMap;
			delete hFrontier;

			PrintToServer("Path optimization completed after %.3f ms (%d nodes)", 1000*(GetEngineTime()-fTimestamp), iNewPathLength);

			return iNewPathLength;
		}

		hFrontier.Erase(0);

		hFrontierDataMap.GetArray(eVertexFrontier.sIdentifier, eVertexFrontierData, sizeof(VertexFrontierData));

		float fCurrentCost = hFrontierDataMap.GetArray(eVertexFrontier.sIdentifier, eVertexFrontierData, sizeof(VertexFrontierData)) ? eVertexFrontierData.fCost : 0.0;

		hPath.GetArray(iCurrentIdx, ePathData);

		NavNode mPrevNode = ePathData.mNavNode;
		int iPrevEdge = ePathData.iExitEdge;

		float vecStartVertex[3];
		vecStartVertex = eVertexFrontierData.vecVertex;

		ArrayList hEdgeOverlaps;
		if (bBypassWithLOS) {
			hEdgeOverlaps = new ArrayList(sizeof(EdgeOverlap));
		}

		for (int iNextIdx=iCurrentIdx+1; iNextIdx<iEndIdx; iNextIdx++) {
			hPath.GetArray(iNextIdx, ePathData);

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
				char sKeyA[8];
				sKeyA = sKey;
				sKeyA[5] = 'A';

				float fNeighborCostA = hFrontierDataMap.GetArray(sKeyA, eVertexFrontierData, sizeof(VertexFrontierData)) ? eVertexFrontierData.fCost : POSITIVE_INFINITY;

				bool bStop;
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
				Call_PushCellRef(bStop);

				float fCost;
				if (Call_Finish(fCost) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
					float fNewCostA = fCurrentCost + fCost;
					if (fNewCostA < fNeighborCostA) {
// 						DrawDebugLine(vecStartVertex, vecOverlapPointA, {255,255,255,255}, 10.0);

						eVertexFrontierData.sIdentifier = sKeyA;
						eVertexFrontierData.sParentIdentifier = eVertexFrontier.sIdentifier;
						eVertexFrontierData.vecVertex = vecOverlapPointA;
						eVertexFrontierData.aData = iNextIdx;

						bStop = false;
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
						Call_PushCellRef(bStop);

						float fHeuristic;
						if (Call_Finish(fHeuristic) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
							eVertexFrontierData.fCost = fNewCostA;
							eVertexFrontierData.fScore = fNewCostA + fHeuristic;
							hFrontierDataMap.SetArray(sKeyA, eVertexFrontierData, sizeof(VertexFrontierData));

							if (hFrontier.FindString(sKeyA) == -1) {
								VertexFrontier eVertexFrontierNeighbor;
								eVertexFrontierNeighbor.sIdentifier = sKeyA;
								eVertexFrontierNeighbor.aData = iNextIdx;
								hFrontier.PushArray(eVertexFrontierNeighbor);
							}
						}
					}
				}
			}

			if (bAddVertexB) {
				char sKeyB[8];
				sKeyB = sKey;
				sKeyB[5] = 'B';

				float fNeighborCostB = hFrontierDataMap.GetArray(sKeyB, eVertexFrontierData, sizeof(VertexFrontierData)) ? eVertexFrontierData.fCost : POSITIVE_INFINITY;

				bool bStop;
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
				Call_PushCellRef(bStop);

				float fCost;
				if (Call_Finish(fCost) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
					float fNewCostB = fCurrentCost + fCost;
					if (fNewCostB < fNeighborCostB) {
// 						DrawDebugLine(vecStartVertex, vecOverlapPointB, {255,255,255,255}, 10.0);

						eVertexFrontierData.sIdentifier = sKeyB;
						eVertexFrontierData.sParentIdentifier = eVertexFrontier.sIdentifier;
						eVertexFrontierData.vecVertex = vecOverlapPointB;
						eVertexFrontierData.aData = iNextIdx;

						bStop = false;
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
						Call_PushCellRef(bStop);

						float fHeuristic;
						if (Call_Finish(fHeuristic) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
							eVertexFrontierData.fCost = fNewCostB;
							eVertexFrontierData.fScore = fNewCostB + fHeuristic;
							hFrontierDataMap.SetArray(sKeyB, eVertexFrontierData, sizeof(VertexFrontierData));

							if (hFrontier.FindString(sKeyB) == -1) {
								VertexFrontier eVertexFrontierNeighbor;
								eVertexFrontierNeighbor.sIdentifier = sKeyB;
								eVertexFrontierNeighbor.aData = iNextIdx;
								hFrontier.PushArray(eVertexFrontierNeighbor);
							}
						}
					}
				}
			}

			if (bAddVertexEnd) {
				char sKeyEnd[8];
				sKeyEnd = sKey;
				sKeyEnd[5] = 'E';

				float fNeighborCostEnd = hFrontierDataMap.GetArray(sKeyEnd, eVertexFrontierData, sizeof(VertexFrontierData)) ? eVertexFrontierData.fCost : POSITIVE_INFINITY;

				bool bStop;
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
				Call_PushCellRef(bStop);

				float fCost;
				if (Call_Finish(fCost) == SP_ERROR_NONE && fCost == fCost && fCost != POSITIVE_INFINITY) {
					float fNewCostEnd = fCurrentCost + fCost
					if (fNewCostEnd < fNeighborCostEnd) {
						eVertexFrontierData.sIdentifier = sKeyEnd;
						eVertexFrontierData.sParentIdentifier = eVertexFrontier.sIdentifier;
						eVertexFrontierData.vecVertex = vecEndPos;
						eVertexFrontierData.aData = iNextIdx;

						eVertexFrontierData.fCost = fNewCostEnd;
						eVertexFrontierData.fScore = 0.0;
						hFrontierDataMap.SetArray(sKeyEnd, eVertexFrontierData, sizeof(VertexFrontierData));

						if (hFrontier.FindString(sKeyEnd) == -1) {
							VertexFrontier eVertexFrontierNeighbor;
							eVertexFrontierNeighbor.sIdentifier = sKeyEnd;
							eVertexFrontierNeighbor.aData = iNextIdx;
							hFrontier.PushArray(eVertexFrontierNeighbor);
						}
					}
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
		SortADTArrayCustom(hFrontier, Sort_VertexHorizon_FScore, hFrontierDataMap);
	}

	delete hFrontierDataMap;
	delete hFrontier;

	PrintToServer("Path optimization failed after %.3f ms", 1000*(GetEngineTime()-fTimestamp));

	return 0;
}

public any Native_Navigation_FindNearby(Handle hPlugin, int iArgC) {
	float fTimestamp = GetEngineTime();

	NavNode mStartNode = GetNativeCell(1);
	Function fnCostFunc = GetNativeFunction(2);
	ArrayList hPathResult = GetNativeCell(3);
	if (hPathResult.BlockSize != sizeof(PathData)) {
		ThrowError("Path result array block size must match PathData");
	}

	any aData = GetNativeCell(4);

	float vecStartPos[3];
	GetNativeArray(5, vecStartPos, sizeof(vecStartPos));

	bool bCustomStartPos = vecStartPos[0] == vecStartPos[0] && vecStartPos[1] == vecStartPos[1] && vecStartPos[2] == vecStartPos[2];
	if (!bCustomStartPos) {
		mStartNode.GetOrigin(vecStartPos);
	} else if(!mStartNode.Contains(vecStartPos)) {
		ThrowError("Start position (%.1f, %.1f, %.1f) is not within start node", vecStartPos[0], vecStartPos[1], vecStartPos[2]);
	}

	StringMap hFrontierDataMap = new StringMap();
	FrontierData eFrontierData; // Default initialization with NULL_NODE mParentNode and 0 elsewhere
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

	while (hFrontier.Length) {
		hFrontier.GetArray(0, eFrontier);
		hFrontier.Erase(0);

		NavNode mCurrentNode = eFrontier.mNode;

		int iVertices = mCurrentNode.iVertices;

		float vecFocalPointCurrent[3], vecFocalPointNeighbor[3];
		vecFocalPointCurrent = eFrontierData.vecFocalPoint;

		float fCurrentCost = hFrontierDataMap.GetArray(eFrontier.sIdentifier, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fCost : 0.0;

		for (int i=0; i<iVertices; i++) {
			int iAttachmentsLength = mCurrentNode.GetAttachmentsLength(i);
			for (int j=0; j<iAttachmentsLength; j++) {
				NavNode mAttachedNode;
				int iAttachedNodeEdge;
				int iAttachmentFlags;
				mCurrentNode.GetAttachment(i, j, mAttachedNode, iAttachedNodeEdge, iAttachmentFlags);

				if (mAttachedNode) {
					mAttachedNode.GetOrigin(vecFocalPointNeighbor);
				} else {
					vecFocalPointNeighbor = NULL_VECTOR;
				}

				bool bStop;
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
				Call_PushCellRef(bStop);

				float fCost;
				if (Call_Finish(fCost) == SP_ERROR_NONE) {
					if (bStop) {
						PathData ePathData;
						ePathData.iPathMode = PathMode_Normal;

						int iParentExitEdge = i;
						int iParentExitAttachmentFlags = iAttachmentFlags;
						ePathData.mNavNode = mAttachedNode;
						ePathData.iEntryEdge = iAttachedNodeEdge;
						ePathData.iExitEdge = -1;
						ePathData.iExitAttachmentFlags = 0;

						if (mAttachedNode) {
							mAttachedNode.GetOrigin(ePathData.vecFocalPoint);
						} else {
							mCurrentNode.GetEdgeCenter(i, ePathData.vecFocalPoint);
						}

						hPathResult.PushArray(ePathData);

						float fTotalCost = eFrontierData.fCost + fCost;
						
						ePathData.mNavNode = eFrontierData.mNode;
						ePathData.iEntryEdge = eFrontierData.iEdge;
						ePathData.iExitEdge = iParentExitEdge;
						ePathData.iExitAttachmentFlags = iParentExitAttachmentFlags;
						ePathData.vecFocalPoint = eFrontierData.vecFocalPoint;
						ePathData.iPathMode = PathMode_Normal;

						iParentExitEdge = eFrontierData.iParentEdge;
						iParentExitAttachmentFlags = eFrontierData.iParentAttachmentFlags;

						hPathResult.ShiftUp(0);
						hPathResult.SetArray(0, ePathData);

						char sCurrentIdentifier[32];
						sCurrentIdentifier = eFrontierData.sParentIdentifier;

						while (sCurrentIdentifier[0]) {
							hFrontierDataMap.GetArray(sCurrentIdentifier, eFrontierData, sizeof(FrontierData));

							ePathData.mNavNode = eFrontierData.mNode;
							ePathData.iEntryEdge = eFrontierData.iEdge;
							ePathData.iExitEdge = iParentExitEdge;
							ePathData.iExitAttachmentFlags = iParentExitAttachmentFlags;
							ePathData.vecFocalPoint = eFrontierData.vecFocalPoint;
							ePathData.iPathMode = PathMode_Normal;

							iParentExitEdge = eFrontierData.iParentEdge;
							iParentExitAttachmentFlags = eFrontierData.iParentAttachmentFlags;

							hPathResult.ShiftUp(0);
							hPathResult.SetArray(0, ePathData);

							sCurrentIdentifier = eFrontierData.sParentIdentifier;
						}

						PrintToServer("Main search stopped in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

						delete hFrontierDataMap;
						delete hFrontier;

						return fTotalCost;
					}

					if (mAttachedNode && fCost == fCost && fCost != POSITIVE_INFINITY) {
						PackCellToStr(mAttachedNode, sKey);
						float fNeighborCost = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fCost : POSITIVE_INFINITY;
						float fNewCost = fCurrentCost + fCost;

						if (fNewCost < fNeighborCost) {
							eFrontierData.sIdentifier = sKey;
							eFrontierData.sParentIdentifier = eFrontier.sIdentifier;
							eFrontierData.mParentNode = mCurrentNode;
							eFrontierData.iParentEdge = i;
							eFrontierData.iParentAttachmentFlags = iAttachmentFlags;
							eFrontierData.mNode = mAttachedNode;
							eFrontierData.iEdge = iAttachedNodeEdge;

							eFrontierData.vecFocalPoint = vecFocalPointNeighbor;

							eFrontierData.fCost = fNewCost;
							hFrontierDataMap.SetArray(sKey, eFrontierData, sizeof(FrontierData));

							if (hFrontier.FindString(sKey) == -1) {
								Frontier eFrontierNeighbor;
								eFrontierNeighbor.sIdentifier = sKey;
								eFrontierNeighbor.mNode = mAttachedNode;
								hFrontier.PushArray(eFrontierNeighbor);
							}
						}
					}
				}
			}
		}

		// TODO: Priority queue
		SortADTArrayCustom(hFrontier, Sort_Horizon_Cost, hFrontierDataMap);
	}

	PrintToServer("Main search completed with no path in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

	return POSITIVE_INFINITY; // Not found, so infinite cost
}

// Helpers



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

/**
 * PackCellToStr
 * Credit: Asher 'Asherkin' Baker
 * Packs a key, as an integer, into a null-terminated buffer.
 */
stock void PackCellToStr(any aKey, char[] sBuffer) {
	int i = aKey;
	sBuffer[0] = ((i >> 28) & 0x7F) | 0x80;
	sBuffer[1] = ((i >> 21) & 0x7F) | 0x80;
	sBuffer[2] = ((i >> 14) & 0x7F) | 0x80;
	sBuffer[3] = ((i >>  7) & 0x7F) | 0x80;
	sBuffer[4] = ((i      ) & 0x7F) | 0x80;
	sBuffer[5] = 0;
}

// Adapted from https://www.geeksforgeeks.org/orientation-3-ordered-points/
stock Orientation GetOrientation2D(float vec1[3], float vec2[3], float vec3[3]) {
	float fVal =	(vec2[1]-vec1[1]) * (vec3[0]-vec2[0]) - 
					(vec2[0]-vec1[0]) * (vec3[1]-vec2[1]);

	if (FloatAbs(fVal) < 0.01) {
		return Orientation_Colinear;
	}

	return fVal > 0 ? Orientation_Clockwise : Orientation_CounterClockwise;
}

// Adapted from https://www.geeksforgeeks.org/check-if-two-given-line-segments-intersect/
stock bool CheckIntersection2D(float vecLineAPointA[3], float vecLineAPointB[3], float vecLineBPointA[3], float vecLineBPointB[3]) {
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

// Debugging

#include <sdktools>

int g_iLaser;
int g_iHalo;

public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}

stock void DrawDebugLine(float fPos[3], float fPos2[3], int iColor[4], float fLife=0.1) {
	TE_SetupBeamPoints(fPos, fPos2, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 1.0, 1, 0.0, iColor, 0);
	TE_SendToAll();
}

stock void DrawNode(NavNode mNode, int iColors[4], float fTime) {
	float vecVertices[8][3];
	int iVertices;
	mNode.GetVertices(vecVertices, iVertices);

	for (int i=1; i<iVertices; i++) {
		DrawDebugLine(vecVertices[i-1], vecVertices[i], iColors, fTime);
	}

	DrawDebugLine(vecVertices[iVertices-1], vecVertices[0], iColors, fTime);
}

stock void DrawPath(ArrayList hPath, int iColor[4], float fTime) {
	for (int j=0; j<hPath.Length-1; j++) {
		PathData ePathDataA;
		PathData ePathDataB;
		hPath.GetArray(j, ePathDataA);
		hPath.GetArray(j+1, ePathDataB);

		DrawDebugLine(ePathDataA.vecFocalPoint, ePathDataB.vecFocalPoint, iColor, fTime);
	}
}

public bool TraceEntityFilter_Environment(int iEntity, int iContentsMask) {
	return false;
}
