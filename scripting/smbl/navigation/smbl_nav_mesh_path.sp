#define POSITIVE_INFINITY		view_as<float>(0x7F800000)

enum struct FrontierData {
	NavNode mParentNode; 
	float fCost;
	float fScore;		// Cost + Heuristic
}

void SetupPathNatives() {
	CreateNative("Navigation.FindShortestPath", 			Native_Navigation_FindShortestPath);
}

public any Native_Navigation_FindShortestPath(Handle hPlugin, int iArgC) {
	NavNode mStartNode = GetNativeCell(1);
	NavNode mEndNode = GetNativeCell(2);

	int iFilterAttributeFlags = GetNativeCell(3);

	ArrayList hPathResult = GetNativeCell(4);

	float vecOriginEnd[3];
	mEndNode.GetOrigin(vecOriginEnd);

	StringMap hFrontierDataMap = new StringMap();
	FrontierData eFrontierData;
	char sKey[6];

	ArrayList hFrontier = new ArrayList();
	hFrontier.Push(mStartNode);

	while (hFrontier.Length) {
		NavNode mCurrentNode = hFrontier.Get(0);

		if (mCurrentNode == mEndNode) {
			PackCellToStr(mCurrentNode, sKey);
			hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData));

			float fTotalCost = eFrontierData.fCost;

			hPathResult.Push(mCurrentNode);
			mCurrentNode = eFrontierData.mParentNode;

			while (mCurrentNode) {
				PackCellToStr(mCurrentNode, sKey);
				hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData));

				hPathResult.ShiftUp(0);
				hPathResult.Set(0, mCurrentNode);

				if (mCurrentNode == mStartNode) {
					break;
				}

				mCurrentNode = eFrontierData.mParentNode;
			}

			delete hFrontierDataMap;
			delete hFrontier;

			return fTotalCost;
		}

		hFrontier.Erase(0);

		if (!mCurrentNode) {
			continue;
		}

		int iVertices = mCurrentNode.iVertices;
		
		float vecOriginCurrent[3], vecOriginNeighbor[3];
		mCurrentNode.GetOrigin(vecOriginCurrent);

		PackCellToStr(mCurrentNode, sKey);
		float fCurrentCost = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fCost : 0.0;

		for (int i=0; i<iVertices; i++) {
			int iAttachmentsLength = mCurrentNode.GetAttachmentsLength(i);
			for (int j=0; j<iAttachmentsLength; j++) {
				NavNode mAttachedNode;
				int iAttachmentFlags;
				mCurrentNode.GetAttachment(i, j, mAttachedNode, _, iAttachmentFlags);

				if (iFilterAttributeFlags & iAttachmentFlags) {
					mAttachedNode.GetOrigin(vecOriginNeighbor);

					PackCellToStr(mAttachedNode, sKey);
					float fNeighborCost = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fCost : POSITIVE_INFINITY;

					float fNewCost = fCurrentCost + GetVectorDistance(vecOriginCurrent, vecOriginNeighbor);
					float fHeuristic = GetVectorDistance(vecOriginNeighbor, vecOriginEnd);
					float fScore = fNeighborCost + fHeuristic;

					if (fNewCost < fNeighborCost) {
						eFrontierData.mParentNode = mCurrentNode;
						eFrontierData.fCost = fNewCost;
						eFrontierData.fScore = fScore;
						hFrontierDataMap.SetArray(sKey, eFrontierData, sizeof(FrontierData));
						
						if (hFrontier.FindValue(mAttachedNode) == -1) {
							hFrontier.Push(mAttachedNode);
						}
					}

				}
			}
		}

		// TODO: Priority queue
		SortADTArrayCustom(hFrontier, Sort_Horizon, hFrontierDataMap);
	}

	delete hFrontierDataMap;
	delete hFrontier;

	return POSITIVE_INFINITY; // Not found, so infinite cost
}

int Sort_Horizon(int iIdxA, int iIdxB, Handle hArray, Handle hHndl) {
	ArrayList hFrontier = view_as<ArrayList>(hArray);
	StringMap hFrontierDataMap = view_as<StringMap>(hHndl);

	NavNode mNodeA = hFrontier.Get(iIdxA);
	NavNode mNodeB = hFrontier.Get(iIdxB);

	FrontierData eFrontierData;
	char sKey[6];

	PackCellToStr(mNodeA, sKey);
	float fScoreA = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fScore : POSITIVE_INFINITY;
	
	PackCellToStr(mNodeB, sKey);
	float fScoreB = hFrontierDataMap.GetArray(sKey, eFrontierData, sizeof(FrontierData)) ? eFrontierData.fScore : POSITIVE_INFINITY;

	if (fScoreA <= fScoreB) {
		return -1;
	}

	return 1;
}

/**
 * PackCellToStr
 * Credit: Asher 'Asherkin' Baker
 * Packs a key, as an integer, into a null-terminated buffer.
 */
stock void PackCellToStr(any aKey, char sBuffer[6]) {
	int i = aKey;
	sBuffer[0] = ((i >> 28) & 0x7F) | 0x80;
	sBuffer[1] = ((i >> 21) & 0x7F) | 0x80;
	sBuffer[2] = ((i >> 14) & 0x7F) | 0x80;
	sBuffer[3] = ((i >> 7) & 0x7F) | 0x80;
	sBuffer[4] = ((i) & 0x7F) | 0x80;
	sBuffer[5] = 0;
}
