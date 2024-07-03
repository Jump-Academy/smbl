#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smbl/nav_mesh>
#include "smbl/navigation/smbl_nav_mesh_path.sp"

#undef REQUIRE_PLUGIN
#include <octree>

#define NAV_FORMAT_VERSION_MAJOR	1
#define NAV_FORMAT_VERSION_MINOR	0

#define MIN_VERTICES			3
#define MAX_VERTICES			8

#define BBOX_BUFFER				50.0

#define POSITIVE_INFINITY		view_as<float>(0x7F800000)
#define NEGATIVE_INFINITY		view_as<float>(0xFF800000)

enum struct _NavNode {
	float vecOrigin[3];
	float vecVertices[MAX_VERTICES*3];
	float vecVertexAngles[MAX_VERTICES*3];
	float vecEdgeCenters[MAX_VERTICES*3];
	float vecBBoxMins[3];
	float vecBBoxMaxs[3];
	int iVertices;

	NavNode mAttachedNodes[MAX_VERTICES*MAX_EDGE_ATTACHMENTS];
	int iAttachedNodeEdges[MAX_VERTICES*MAX_EDGE_ATTACHMENTS];
	int iAttachmentFlags[MAX_VERTICES*MAX_EDGE_ATTACHMENTS];
	int iAttachedNodes[MAX_VERTICES];

	void GetVertex(int i, float vecVertex[3]) {
		int iOffset = 3*i;
		vecVertex[0] = this.vecVertices[iOffset  ];
		vecVertex[1] = this.vecVertices[iOffset+1];
		vecVertex[2] = this.vecVertices[iOffset+2];
	}

	void SetVertex(int i, float vecVertex[3]) {
		int iOffset = 3*i;
		this.vecVertices[iOffset  ] = vecVertex[0];
		this.vecVertices[iOffset+1] = vecVertex[1];
		this.vecVertices[iOffset+2] = vecVertex[2];
	}

	void GetVertexAngles(int i, float vecAngles[3]) {
		int iOffset = 3*i;
		vecAngles[0] = this.vecVertexAngles[iOffset  ];
		vecAngles[1] = this.vecVertexAngles[iOffset+1];
		vecAngles[2] = this.vecVertexAngles[iOffset+2];
	}

	void GetEdgeCenter(int iEdge, float vecPoint[3]) {
		int iOffset = 3*iEdge;
		vecPoint[0] = this.vecEdgeCenters[iOffset  ];
		vecPoint[1] = this.vecEdgeCenters[iOffset+1];
		vecPoint[2] = this.vecEdgeCenters[iOffset+2];
	}

	void GetEdgeVertices(int iEdge, float vecVertexA[3], float vecVertexB[3]) {
		int iOffset = 3*iEdge;
		vecVertexA[0] = this.vecVertices[iOffset  ];
		vecVertexA[1] = this.vecVertices[iOffset+1];
		vecVertexA[2] = this.vecVertices[iOffset+2];

		if (iEdge == this.iVertices-1) {
			vecVertexB[0] = this.vecVertices[0];
			vecVertexB[1] = this.vecVertices[1];
			vecVertexB[2] = this.vecVertices[2];
		} else {
			vecVertexB[0] = this.vecVertices[iOffset+3];
			vecVertexB[1] = this.vecVertices[iOffset+4];
			vecVertexB[2] = this.vecVertices[iOffset+5];
		}
	}

	void GetEdgeOverlap(int iEdge, NavNode mOtherNode, int iOtherEdge, float vecVertexA[3], float vecVertexB[3]) {
		this.GetEdgeVertices(iEdge, vecVertexA, vecVertexB);

		float vecVertexOtherA[3], vecVertexOtherB[3];
		mOtherNode.GetEdgeVertices(iOtherEdge, vecVertexOtherA, vecVertexOtherB);

		float vecVectorAB[3];
		SubtractVectors(vecVertexB, vecVertexA, vecVectorAB);
		NormalizeVector(vecVectorAB, vecVectorAB);

		float vecVectorAOtherB[3];
		SubtractVectors(vecVertexOtherB, vecVertexA, vecVectorAOtherB);

		float vecClipA[3], vecClipB[3];

		float fOtherBProjAB = GetVectorDotProduct(vecVectorAB, vecVectorAOtherB);
		if (fOtherBProjAB < 0) {
			vecClipA = vecVertexA;
		} else {
			ScaleVector(vecVectorAB, fOtherBProjAB);
			AddVectors(vecVertexA, vecVectorAB, vecClipA);
		}

		float vecVectorBA[3];
		SubtractVectors(vecVertexA, vecVertexB, vecVectorBA);
		NormalizeVector(vecVectorBA, vecVectorBA);

		float vecVectorBOtherA[3];
		SubtractVectors(vecVertexOtherA, vecVertexB, vecVectorBOtherA);

		float fOtherAProjBA = GetVectorDotProduct(vecVectorBA, vecVectorBOtherA);
		if (fOtherAProjBA < 0) {
			vecClipB = vecVertexB;
		} else {
			ScaleVector(vecVectorBA, fOtherAProjBA);
			AddVectors(vecVertexB, vecVectorBA, vecClipB);
		}

		vecVertexA = vecClipA;
		vecVertexB = vecClipB;
	}

	float GetNearestEdgeProjection(float vecInteralPoint[3], float vecEdgeProj[3], int &iEdge, int &iAttachment, int iAttachmentFlags, float vecDirection[3]) {
		if (!this.Contains(vecInteralPoint)) {
			ThrowError("Point is not within node");
		}

		float fMinDist = POSITIVE_INFINITY;
		int iMinEdge = -1;
		int iMinAttachment;
		float vecMinNearestEdge[3];

		int iSearchEdge =-1;
		int iSearchAttachment = -1;
		int iStartEdge, iStartAttachment;
		NavNode _mAttachedNode;
		int _iAttachedNodeEdge;
		int _iAttachmentFlags;

		while (this.FindAttachmentWithFlags(iAttachmentFlags, false, iSearchEdge, iSearchAttachment, _mAttachedNode, _iAttachedNodeEdge, _iAttachmentFlags, iStartEdge, iStartAttachment)) {
			float vecVertexA[3], vecVertexB[3];
			this.GetEdgeVertices(iSearchEdge, vecVertexA, vecVertexB);

			float vecEdgeVector[3];
			SubtractVectors(vecVertexB, vecVertexA, vecEdgeVector);

			float fEdgeLength = GetVectorLength(vecEdgeVector);
			NormalizeVector(vecEdgeVector, vecEdgeVector);

			float vecInternalToVertexAVector[3];
			SubtractVectors(vecInteralPoint, vecVertexA, vecInternalToVertexAVector);

			float vecNearestEdge[3];
			float fProjLength = GetVectorDotProduct(vecInternalToVertexAVector, vecEdgeVector);
			if (fProjLength < 0) {
				vecNearestEdge = vecVertexA;
			} else if (fProjLength >= fEdgeLength) {
				vecNearestEdge = vecVertexB;
			} else {
				ScaleVector(vecEdgeVector, fProjLength);
				AddVectors(vecVertexA, vecEdgeVector, vecNearestEdge);
			}

			float vecDirectionEdge[3];
			SubtractVectors(vecNearestEdge, vecInteralPoint, vecDirectionEdge);

			if (IsNullVector(vecDirection) || GetVectorDotProduct(vecDirection, vecDirectionEdge) > 1) {
				float fDist = GetVectorDistance(vecInteralPoint, vecNearestEdge);
				if (fDist < fMinDist) {
					fMinDist = fDist;
					iMinEdge = iSearchEdge;
					iMinAttachment = iSearchAttachment;
					vecMinNearestEdge = vecNearestEdge;
				}
			}

			// Reset to continue next iteration
			iSearchEdge = -1;
			iSearchAttachment = -1;
		}

		vecEdgeProj = vecMinNearestEdge;
		iEdge = iMinEdge;
		iAttachment = iMinAttachment;

		return fMinDist;
	}

	float GetHullProjection(float vecPoint[3], float vecHullPoint[3], int &iEdge) {
		if (this.Contains(vecPoint)) {
			vecHullPoint = vecPoint;
			return 0.0;
		}

		float fMinDist = POSITIVE_INFINITY;
		int iMinEdge = -1;
		float vecMinNearestEdge[3];

		for (int i=0; i<this.iVertices; i++) {
			float vecVertexA[3], vecVertexB[3];
			this.GetEdgeVertices(i, vecVertexA, vecVertexB);

			float vecEdgeVector[3];
			SubtractVectors(vecVertexB, vecVertexA, vecEdgeVector);

			float fEdgeLength = GetVectorLength(vecEdgeVector);
			NormalizeVector(vecEdgeVector, vecEdgeVector);

			float vecPointToVertexAVector[3];
			SubtractVectors(vecPoint, vecVertexA, vecPointToVertexAVector);

			float vecNearestEdge[3];
			float fProjLength = GetVectorDotProduct(vecPointToVertexAVector, vecEdgeVector);
			if (fProjLength < 0) {
				vecNearestEdge = vecVertexA;
			} else if (fProjLength >= fEdgeLength) {
				vecNearestEdge = vecVertexB;
			} else {
				ScaleVector(vecEdgeVector, fProjLength);
				AddVectors(vecVertexA, vecEdgeVector, vecNearestEdge);
			}

			float fDist = GetVectorDistance(vecPoint, vecNearestEdge);
			if (fDist < fMinDist) {
				fMinDist = fDist;
				iMinEdge = i;
				vecMinNearestEdge = vecNearestEdge;
			}
		}

		vecHullPoint = vecMinNearestEdge;
		iEdge = iMinEdge;

		return fMinDist;
	}

	int PushAttachment(int iEdge, NavNode mAttachedNode, int iAttachedNodeEdge, int iAttachmentFlags) {
		if (iEdge < 0 || iEdge >= this.iVertices) {
			ThrowError("Invalid edge index %d (count: %d)", iEdge, this.iVertices);
		}

		if (mAttachedNode && (iAttachedNodeEdge < 0 || iAttachedNodeEdge >= mAttachedNode.iVertices)) {
			ThrowError("Invalid attached node edge index %d (count: %d)", iAttachedNodeEdge, mAttachedNode.iVertices);
		}

		int iAttachmentLength = this.GetAttachmentsLength(iEdge);
		if (iAttachmentLength >= MAX_EDGE_ATTACHMENTS) {
			ThrowError("No free attachments (count: %d)", MAX_EDGE_ATTACHMENTS);
		}

		// Merge with existing attachment if found
		int iAttachment = this.FindAttachment(iEdge, mAttachedNode);
		if (iAttachment != -1) {
			this.iAttachmentFlags[MAX_EDGE_ATTACHMENTS*iEdge + iAttachment] |= iAttachmentFlags;
			return iAttachment;
		}

		int iOffset = MAX_EDGE_ATTACHMENTS*iEdge + iAttachmentLength;
		this.mAttachedNodes[iOffset] = mAttachedNode;
		this.iAttachedNodeEdges[iOffset] = iAttachedNodeEdge;
		this.iAttachmentFlags[iOffset] = iAttachmentFlags;

		this.iAttachedNodes[iEdge] = iAttachmentLength + 1;

		return iAttachmentLength;
	}

	void EraseAttachment(int iEdge, int iAttachment) {
		if (iEdge < 0 || iEdge > this.iVertices) {
			ThrowError("Invalid edge index %d (count: %d)", iEdge, this.iVertices);
		}

		int iAttachmentLength = this.GetAttachmentsLength(iEdge);

		if (iAttachment < 0 || iAttachment >= iAttachmentLength) {
			ThrowError("Invalid attachment index %d (count: %d)", iAttachment, iAttachmentLength);
		}

		for (int i=iAttachment+1; i<iAttachmentLength; i++) {
			int iOffset = MAX_EDGE_ATTACHMENTS*iEdge + i;
			this.mAttachedNodes[iOffset-1] = this.mAttachedNodes[iOffset];
			this.iAttachedNodeEdges[iOffset-1] = this.iAttachedNodeEdges[iOffset];
			this.iAttachmentFlags[iOffset-1] = this.iAttachmentFlags[iOffset];
		}

		this.iAttachedNodes[iEdge] = iAttachmentLength-1;
	}

	void GetAttachment(int iEdge, int iAttachment, NavNode &mAttachedNode, int &iAttachedNodeEdge, int &iAttachmentFlags) {
		if (iEdge < 0 || iEdge >= this.iVertices) {
			ThrowError(" Invalid edge index %d (count: %d)", iEdge, this.iVertices);
		}

		if (iAttachment < 0 || iAttachment >= this.iAttachedNodes[iEdge]) {
			ThrowError("Invalid attachment index %d (max: %d)", iAttachment, this.iAttachedNodes[iEdge]);
		}

		int iOffset = MAX_EDGE_ATTACHMENTS*iEdge + iAttachment;
		mAttachedNode = this.mAttachedNodes[iOffset];
		iAttachedNodeEdge = this.iAttachedNodeEdges[iOffset];
		iAttachmentFlags = this.iAttachmentFlags[iOffset];
	}

	void SetAttachment(int iEdge, int iAttachment, NavNode mAttachedNode, int iAttachedNodeEdge, int iAttachmentFlags) {
		if (iEdge < 0 || iEdge >= this.iVertices) {
			ThrowError("Invalid edge index %d (count: %d)", iEdge, this.iVertices);
		}

		if (mAttachedNode && (iAttachedNodeEdge < 0 || iAttachedNodeEdge >= mAttachedNode.iVertices)) {
			ThrowError("Invalid attached node edge index %d (count: %d)", iAttachedNodeEdge, mAttachedNode.iVertices);
		}

		if (iAttachment < 0 || iAttachment >= this.iAttachedNodes[iEdge]) {
			ThrowError("Invalid attachment index %d (max: %d)", iAttachment, this.iAttachedNodes[iEdge]);
		}

		int iAttachment0 = this.FindAttachment(iEdge, mAttachedNode);
		if (iAttachment0 != -1 && iAttachment0 != iAttachment) {
			ThrowError("Node already attached (index: %d, duplicate: %d)", iAttachment, iAttachment0);
		}

		int iOffset = MAX_EDGE_ATTACHMENTS*iEdge + iAttachment;
		this.mAttachedNodes[iOffset] = mAttachedNode;
		this.iAttachedNodeEdges[iOffset] = iAttachedNodeEdge;
		this.iAttachmentFlags[iOffset] = iAttachmentFlags;
	}

	int FindAttachment(int iEdge, NavNode mSearchNode, int iStart=0) {
		int iAttachmentLength = this.GetAttachmentsLength(iEdge);
		if (!iAttachmentLength) {
			return -1;
		}

		if (iStart < 0 || iStart >= iAttachmentLength) {
			ThrowError("Invalid attachment index %d (count: %d)", iStart, iAttachmentLength);
		}

		for (int i=iStart; i<iAttachmentLength; i++) {
			int iOffset = MAX_EDGE_ATTACHMENTS*iEdge + i;
			if (this.mAttachedNodes[iOffset] == mSearchNode) {
				return i;
			}
		}

		return -1;
	}

	bool FindAttachmentWithFlags(int iFindAttachmentFlags, bool bExactMatch, int &iEdge, int &iAttachment, NavNode &mAttachedNode, int &iAttachedNodeEdge, int &iAttachmentFlags, int &iStartEdge, int &iStartAttachment) {
		NavNode mAttachedNodeCandidate;
		int iAttachedNodeEdgeCandidate;
		int iAttachmentFlagsCandidate;

		if (iEdge == -1) {
			for (int i=iStartEdge; i<this.iVertices; i++) {
				int iAttachmentLength = this.GetAttachmentsLength(i);

				for (int j=iStartAttachment; j<iAttachmentLength; j++) {
					int iOffset = MAX_EDGE_ATTACHMENTS*i + j;

					iAttachmentFlagsCandidate = this.iAttachmentFlags[iOffset];
					mAttachedNodeCandidate = this.mAttachedNodes[iOffset];
					iAttachedNodeEdge = this.iAttachedNodeEdges[iOffset];

					if (bExactMatch && iFindAttachmentFlags == iAttachmentFlagsCandidate || !bExactMatch && (iFindAttachmentFlags & iAttachmentFlagsCandidate) == iFindAttachmentFlags) {
						iEdge = i;
						iAttachment = j;
						mAttachedNode = mAttachedNodeCandidate;
						iAttachedNodeEdge = iAttachedNodeEdgeCandidate;
						iAttachmentFlags = iAttachmentFlagsCandidate;

						if (j < iAttachmentLength-1) {
							iStartAttachment++;
						} else {
							iStartEdge = i+1;
							iStartAttachment = 0;
						}

						return true;
					}
				}
			}
		} else {
			if (iAttachment == -1) {
				int iAttachmentLength = this.GetAttachmentsLength(iEdge);

				for (int j=iStartAttachment; j<iAttachmentLength; j++) {
					int iOffset = MAX_EDGE_ATTACHMENTS*iEdge + j;

					iAttachmentFlagsCandidate = this.iAttachmentFlags[iOffset];
					mAttachedNodeCandidate = this.mAttachedNodes[iOffset];
					iAttachedNodeEdge = this.iAttachedNodeEdges[iOffset];

					if (bExactMatch && iFindAttachmentFlags == iAttachmentFlagsCandidate || !bExactMatch && (iFindAttachmentFlags & iAttachmentFlagsCandidate) == iFindAttachmentFlags) {
						iAttachment = j;
						mAttachedNode = mAttachedNodeCandidate;
						iAttachedNodeEdge = iAttachedNodeEdgeCandidate;
						iAttachmentFlags = iAttachmentFlagsCandidate;

						if (j < iAttachmentLength-1) {
							iStartAttachment++;
						}

						return true;
					}
				}

				return false;
			}

			this.GetAttachment(iEdge, iAttachment, mAttachedNodeCandidate, iAttachedNodeEdgeCandidate, iAttachmentFlagsCandidate);

			if (bExactMatch && iFindAttachmentFlags == iAttachmentFlagsCandidate || !bExactMatch && (iFindAttachmentFlags & iAttachmentFlagsCandidate) == iFindAttachmentFlags) {
				mAttachedNode = mAttachedNodeCandidate;
				iAttachedNodeEdge = iAttachedNodeEdgeCandidate;
				iAttachmentFlags = iFindAttachmentFlags;
				return true;
			}
		}

		return false;
	}

	bool FindAttachedNode(NavNode mSearchNode, int &iEdge, int &iAttachment, int &iAttachmentFlags, int &iAttachedNodeEdge) {
		for (int i=0; i<this.iVertices; i++) {
			int iAttachmentLength = this.GetAttachmentsLength(i);

			for (int j=0; j<iAttachmentLength; j++) {
				int iOffset = MAX_EDGE_ATTACHMENTS*i + j;
				if (this.mAttachedNodes[iOffset] == mSearchNode) {
					iEdge = i;
					iAttachment = j;
					iAttachmentFlags = this.iAttachmentFlags[iOffset];
					iAttachedNodeEdge = this.iAttachedNodeEdges[iOffset];
					return true;
				}
			}
		}

		return false;
	}

	void ClearAttachments(int iEdge) {
		if (iEdge < 0 || iEdge >= this.iVertices) {
			ThrowError("Invalid edge index %d (count: %d)", iEdge, this.iVertices);
		}

		this.iAttachedNodes[iEdge] = 0;
	}

	int GetAttachmentsLength(int iEdge) {
		if (iEdge < 0 || iEdge >= this.iVertices) {
			ThrowError("Invalid edge index %d (count: %d)", iEdge, this.iVertices);
		}

		return this.iAttachedNodes[iEdge];
	}

	int GetClosestEdge(float vecPoint[3]) {
		float vecCenter[3];
		this.GetEdgeCenter(0, vecCenter);

		float fMinDist = GetVectorDistance(vecPoint, vecCenter);
		int iMinEdge = 0;

		for (int i=1; i<this.iVertices; i++) {
			this.GetEdgeCenter(i, vecCenter);

			float fDist = GetVectorDistance(vecPoint, vecCenter);
			if (fDist < fMinDist) {
				fMinDist = fDist;
				iMinEdge = i;
			}
		}

		return iMinEdge;
	}

	int GetFarthestEdge(float vecPoint[3]) {
		float vecCenter[3];
		this.GetEdgeCenter(0, vecCenter);

		float fMaxDist = GetVectorDistance(vecPoint, vecCenter);
		int iMaxEdge = 0;

		for (int i=1; i<this.iVertices; i++) {
			this.GetEdgeCenter(i, vecCenter);

			float fDist = GetVectorDistance(vecPoint, vecCenter);
			if (fDist > fMaxDist) {
				fMaxDist = fDist;
				iMaxEdge = i;
			}
		}

		return iMaxEdge;
	}

	bool Contains(float vecPoint[3], float fSlack=0.0) {
		if (vecPoint[0]<this.vecBBoxMins[0] || vecPoint[1]<this.vecBBoxMins[1] || vecPoint[2]<this.vecBBoxMins[2] ||
			vecPoint[0]>this.vecBBoxMaxs[0] || vecPoint[1]>this.vecBBoxMaxs[1] || vecPoint[2]>this.vecBBoxMaxs[2]) {
			return false;
		}

		// Move probe point closer to node origin by slack amount
		// Equivalent to extending hull vertices outward by slack amount to check for probe
		if (fSlack != 0.0) {
			float vecVector[3];
			SubtractVectors(vecPoint, this.vecOrigin, vecVector);
			float fDist = GetVectorLength(vecVector);
			NormalizeVector(vecVector, vecVector);
			ScaleVector(vecVector, fDist-fSlack);
			AddVectors(this.vecOrigin,  vecVector, vecPoint);
		}

		float vecVertex[3], vecFirstVertex[3], vecLastVertex[3];

		this.GetVertex(0, vecLastVertex);
		vecFirstVertex = vecLastVertex;

		for (int i=1; i<this.iVertices; i++) {
			this.GetVertex(i, vecVertex);

			if (GetOrientation2D(vecPoint, vecLastVertex, vecVertex) == Orientation_Clockwise) {
				return false;
			}

			vecLastVertex = vecVertex;
		}

		return GetOrientation2D(vecPoint, vecLastVertex, vecFirstVertex) != Orientation_Clockwise;
	}

	void Update() {
		static float vecVertices[MAX_VERTICES][3];
		static float vecAngles[3];
		static float vecEdgeCenter[3];

		int iVertices = this.iVertices;

		vecVertices[0][0] = this.vecVertices[0];
		vecVertices[0][1] = this.vecVertices[1];
		vecVertices[0][2] = this.vecVertices[2];

		this.vecBBoxMins[0] = this.vecBBoxMaxs[0] = this.vecVertices[0];
		this.vecBBoxMins[1] = this.vecBBoxMaxs[1] = this.vecVertices[1];
		this.vecBBoxMins[2] = this.vecBBoxMaxs[2] = this.vecVertices[2];

		GetVectorAngles(vecVertices[0], vecAngles);
		this.vecVertexAngles[0] = vecAngles[0];
		this.vecVertexAngles[1] = vecAngles[1];
		this.vecVertexAngles[2] = vecAngles[2];

		for (int i=1; i<iVertices; i++) {
			int iVertexOffset = 3*i;
			vecVertices[i][0] = this.vecVertices[iVertexOffset  ];
			vecVertices[i][1] = this.vecVertices[iVertexOffset+1];
			vecVertices[i][2] = this.vecVertices[iVertexOffset+2];

			AddVectors(vecVertices[i-1], vecVertices[i], vecEdgeCenter);
			ScaleVector(vecEdgeCenter, 0.5);

			int iEdgeOffset = 3*(i-1);
			this.vecEdgeCenters[iEdgeOffset  ]  = vecEdgeCenter[0];
			this.vecEdgeCenters[iEdgeOffset+1]  = vecEdgeCenter[1];
			this.vecEdgeCenters[iEdgeOffset+2]  = vecEdgeCenter[2];

			this.vecBBoxMins[0] = vecVertices[i][0] < this.vecBBoxMins[0] ? vecVertices[i][0] : this.vecBBoxMins[0];
			this.vecBBoxMins[1] = vecVertices[i][1] < this.vecBBoxMins[1] ? vecVertices[i][1] : this.vecBBoxMins[1];
			this.vecBBoxMins[2] = vecVertices[i][2] < this.vecBBoxMins[2] ? vecVertices[i][2] : this.vecBBoxMins[2];

			this.vecBBoxMaxs[0] = vecVertices[i][0] > this.vecBBoxMaxs[0] ? vecVertices[i][0] : this.vecBBoxMaxs[0];
			this.vecBBoxMaxs[1] = vecVertices[i][1] > this.vecBBoxMaxs[1] ? vecVertices[i][1] : this.vecBBoxMaxs[1];
			this.vecBBoxMaxs[2] = vecVertices[i][2] > this.vecBBoxMaxs[2] ? vecVertices[i][2] : this.vecBBoxMaxs[2];

			GetVectorAngles(vecVertices[i], vecAngles);
			this.vecVertexAngles[iEdgeOffset  ] = vecAngles[0];
			this.vecVertexAngles[iEdgeOffset+1] = vecAngles[1];
			this.vecVertexAngles[iEdgeOffset+2] = vecAngles[2];
		}

		AddVectors(vecVertices[iVertices-1], vecVertices[0], vecEdgeCenter);
		ScaleVector(vecEdgeCenter, 0.5);

		int iEdgeOffset = 3*(iVertices-1);
		this.vecEdgeCenters[iEdgeOffset  ]  = vecEdgeCenter[0];
		this.vecEdgeCenters[iEdgeOffset+1]  = vecEdgeCenter[1];
		this.vecEdgeCenters[iEdgeOffset+2]  = vecEdgeCenter[2];

		this.vecBBoxMins[0] -= BBOX_BUFFER;
		this.vecBBoxMins[1] -= BBOX_BUFFER;
		this.vecBBoxMins[2] -= BBOX_BUFFER;

		this.vecBBoxMaxs[0] += BBOX_BUFFER;
		this.vecBBoxMaxs[1] += BBOX_BUFFER;
		this.vecBBoxMaxs[2] += BBOX_BUFFER;
	}

	bool bGCFlag;
}

enum struct _NavMesh {
	ArrayList hNavNodes;
	ArrayList hVertexNodes;
	Octree mOctree;
	char sFileName[PLATFORM_MAX_PATH];
	char sMapName[PLATFORM_MAX_PATH];
	int iTimestamp;
	bool bGCFlag;
}

enum Orientation {
	Orientation_Colinear,
	Orientation_Clockwise,
	Orientation_CounterClockwise,
}

ArrayList g_hNavNodes;
ArrayList g_hNavMeshes;

StringMap g_hNavMeshesMap;
bool g_bOctreeAvailable;

public Plugin myinfo = {
	name = "SMBL NavMesh",
	author = PLUGIN_AUTHOR,
	description = "Navigation mesh for pathfinding",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("smbl_nav_mesh_version", PLUGIN_VERSION, "SMBL navigation mesh version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	g_hNavNodes = new ArrayList(sizeof(_NavNode));
	g_hNavMeshes = new ArrayList(sizeof(_NavMesh));

	g_hNavMeshesMap = new StringMap();
}

public void OnPluginEnd() {
	if (g_bOctreeAvailable) {
		int iNavMeshesLength = g_hNavMeshes.Length;
		for (int i=0; i<iNavMeshesLength; i++) {
			Octree mOctree = g_hNavMeshes.Get(i, _NavMesh::mOctree);
			Octree.Destroy(mOctree);
		}
	}
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "octree")) {
		g_bOctreeAvailable = true;

		int iNavMeshesLength = g_hNavMeshes.Length;
		for (int i=0; i<iNavMeshesLength; i++) {
			BuildSpatialIdx(i);
		}
	}
}

public void OnLibraryRemoved(const char[] sName) {
	if (StrEqual(sName, "octree")) {
		g_bOctreeAvailable = false;

		int iNavMeshesLength = g_hNavMeshes.Length;
		for (int i=0; i<iNavMeshesLength; i++) {
			g_hNavMeshes.Set(i, NULL_OCTREE, _NavMesh::mOctree);
		}
	}
}

public void OnAllPluginsLoaded() {
	g_bOctreeAvailable = LibraryExists("octree");
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("smbl_nav_mesh");

	SetupNavNatives();
	SetupPathNatives();

	return APLRes_Success;
}

// Navigation node natives

void SetupNavNatives() {
	CreateNative("NavNode.iVertices.get", 				Native_NavNode_GetVertices);
	CreateNative("NavNode.iVertices.set", 				Native_NavNode_SetVertices);
	CreateNative("NavNode.GetOrigin", 					Native_NavNode_GetOrigin);
	CreateNative("NavNode.SetOrigin", 					Native_NavNode_SetOrigin);
	CreateNative("NavNode.GetVertex", 					Native_NavNode_GetVertex);
	CreateNative("NavNode.SetVertex", 					Native_NavNode_SetVertex);
	CreateNative("NavNode.GetVertexAngles", 			Native_NavNode_GetVertexAngles);
	CreateNative("NavNode.GetEdgeCenter", 				Native_NavNode_GetEdgeCenter);
	CreateNative("NavNode.GetEdgeVertices", 			Native_NavNode_GetEdgeVertices);
	CreateNative("NavNode.GetEdgeOverlap", 				Native_NavNode_GetEdgeOverlap);
	CreateNative("NavNode.GetNearestEdgeProjection",	Native_NavNode_GetNearestEdgeProjection);
	CreateNative("NavNode.GetHullProjection",			Native_NavNode_GetHullProjection);

	CreateNative("NavNode.PushAttachment",				Native_NavNode_PushAttachment);
	CreateNative("NavNode.EraseAttachment",				Native_NavNode_EraseAttachment);
	CreateNative("NavNode.GetAttachment",				Native_NavNode_GetAttachment);
	CreateNative("NavNode.SetAttachment",				Native_NavNode_SetAttachment);
	CreateNative("NavNode.FindAttachment",				Native_NavNode_FindAttachment);
	CreateNative("NavNode.FindAttachmentWithFlags",		Native_NavNode_FindAttachmentWithFlags);
	CreateNative("NavNode.FindAttachedNode",			Native_NavNode_FindAttachedNode);
	CreateNative("NavNode.ClearAttachments",			Native_NavNode_ClearAttachments);
	CreateNative("NavNode.GetAttachmentsLength",		Native_NavNode_GetAttachmentsLength);

	CreateNative("NavNode.GetClosestEdge",				Native_NavNode_GetClosestEdge);
	CreateNative("NavNode.GetFarthestEdge",				Native_NavNode_GetFarthestEdge);

	CreateNative("NavNode.Contains", 					Native_NavNode_Contains);
	CreateNative("NavNode.Update",						Native_NavNode_Update);

	CreateNative("NavNode.Instance", 					Native_NavNode_Instance);
	CreateNative("NavNode.Destroy", 					Native_NavNode_Destroy);

	CreateNative("NavMesh.iTimestamp.get", 				Native_NavMesh_GetTimestamp);
	CreateNative("NavMesh.iTimestamp.set", 				Native_NavMesh_SetTimestamp);
	CreateNative("NavMesh.GetFileName", 				Native_NavMesh_GetFileName);
	CreateNative("NavMesh.SetFileName", 				Native_NavMesh_SetFileName);
	CreateNative("NavMesh.GetMapName", 					Native_NavMesh_GetMapName);
	CreateNative("NavMesh.SetMapName", 					Native_NavMesh_SetMapName);
	CreateNative("NavMesh.GetNodes",	 				Native_NavMesh_GetNodes);
	CreateNative("NavMesh.GetNodesInRange",				Native_NavMesh_GetNodesInRange);
	CreateNative("NavMesh.GetNearestNodeInRange",		Native_NavMesh_GetNearestNodeInRange);
	CreateNative("NavMesh.UpdateIndex",					Native_NavMesh_UpdateIndex);

	CreateNative("NavMesh.Instance", 					Native_NavMesh_Instance);
	CreateNative("NavMesh.Destroy", 					Native_NavMesh_Destroy);

	CreateNative("NavMesh.LoadNavFile", 				Native_NavMesh_LoadNavFile);
	CreateNative("NavMesh.SaveNavFile", 				Native_NavMesh_SaveNavFile);

	CreateNative("SMBL_RegisterNavMesh",				Native_RegisterNavMesh);
	CreateNative("SMBL_DeregisterNavMesh",				Native_DeregisterNavMesh);
	CreateNative("SMBL_DeregisterAllNavMeshes",			Native_DeregisterAllNavMeshes);
	CreateNative("SMBL_GetNavMesh",						Native_GetNavMesh);
}

public int Native_NavNode_GetOrigin(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	SetNativeArray(2, eNavNode.vecOrigin, sizeof(_NavNode::vecOrigin));

	return 0;
}

public int Native_NavNode_SetOrigin(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	GetNativeArray(2, eNavNode.vecOrigin, sizeof(_NavNode::vecOrigin));

	g_hNavNodes.SetArray(iThis, eNavNode);

	return 0;
}

public int Native_NavNode_GetVertex(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iVertex = GetNativeCell(2);

	if (iVertex < 0 || iVertex >= MAX_VERTICES) {
		ThrowError("Invalid vertex index");
	}

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecVertex[3];
	eNavNode.GetVertex(iVertex, vecVertex);

	SetNativeArray(3, vecVertex, sizeof(vecVertex));

	return 0;
}

public int Native_NavNode_SetVertex(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iVertex = GetNativeCell(2);

	if (iVertex < 0 || iVertex >= MAX_VERTICES) {
		ThrowError("Invalid vertex index");
	}

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecVertex[3];
	GetNativeArray(3, vecVertex, sizeof(vecVertex));

	eNavNode.SetVertex(iVertex, vecVertex);

	g_hNavNodes.SetArray(iThis, eNavNode);

	return 0;
}

public int Native_NavNode_GetVertices(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return g_hNavNodes.Get(iThis, _NavNode::iVertices);
}

public int Native_NavNode_GetVertexAngles(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iVertex = GetNativeCell(2);

	if (iVertex < 0 || iVertex >= MAX_VERTICES) {
		ThrowError("Invalid vertex index");
	}

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecAngles[3];
	eNavNode.GetVertexAngles(iVertex, vecAngles);

	SetNativeArray(3, vecAngles, sizeof(vecAngles));

	return 0;
}

public int Native_NavNode_SetVertices(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iVertices = GetNativeCell(2);

	if (iVertices < 0 || iVertices > MAX_VERTICES) {
		ThrowError("Invalid number of vertices: %d", iVertices);
	}

	g_hNavNodes.Set(iThis, iVertices, _NavNode::iVertices);

	return 0;
}

public int Native_NavNode_GetEdgeCenter(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);

	if (iEdge < 0 || iEdge >= MAX_VERTICES) {
		ThrowError("Invalid edge index");
	}

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecPoint[3];
	eNavNode.GetEdgeCenter(iEdge, vecPoint);

	SetNativeArray(3, vecPoint, sizeof(vecPoint));

	return 0;
}

public int Native_NavNode_GetEdgeVertices(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);

	if (iEdge < 0 || iEdge >= MAX_VERTICES) {
		ThrowError("Invalid edge index");
	}

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecVertexA[3], vecVertexB[3];
	eNavNode.GetEdgeVertices(iEdge, vecVertexA,vecVertexB);

	SetNativeArray(3, vecVertexA, sizeof(vecVertexA));
	SetNativeArray(4, vecVertexB, sizeof(vecVertexB));

	return 0;
}

public int Native_NavNode_GetEdgeOverlap(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);

	NavNode mOtherNode = GetNativeCell(3);
	int iOtherEdge = GetNativeCell(4);

	if (iEdge < 0 || iEdge >= MAX_VERTICES) {
		ThrowError("Invalid edge index");
	}

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecVertexA[3], vecVertexB[3];
	eNavNode.GetEdgeOverlap(iEdge, mOtherNode, iOtherEdge, vecVertexA,vecVertexB);

	SetNativeArray(5, vecVertexA, sizeof(vecVertexA));
	SetNativeArray(6, vecVertexB, sizeof(vecVertexB));

	return 0;
}

public any Native_NavNode_GetNearestEdgeProjection(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecInteralPoint[3];
	GetNativeArray(2, vecInteralPoint, sizeof(vecInteralPoint));

	float vecEdgeProj[3];

	int iEdge = GetNativeCellRef(4);
	int iAttachment = GetNativeCellRef(5);
	int iAttachmentFlags = GetNativeCell(6);

	float vecDirection[3];
	GetNativeArray(7, vecDirection, sizeof(vecDirection));

	float fDist = eNavNode.GetNearestEdgeProjection(vecInteralPoint, vecEdgeProj, iEdge, iAttachment, iAttachmentFlags, vecDirection);

	SetNativeArray(3, vecEdgeProj, sizeof(vecEdgeProj));
	SetNativeCellRef(4, iEdge);
	SetNativeCellRef(5, iAttachment);

	return fDist;
}


public any Native_NavNode_GetHullProjection(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecPoint[3];
	GetNativeArray(2, vecPoint, sizeof(vecPoint));

	float vecHullPoint[3];
	int iEdge;

	float fDistance = eNavNode.GetHullProjection(vecPoint, vecHullPoint, iEdge);

	SetNativeArray(3, vecHullPoint, sizeof(vecHullPoint));
	SetNativeCellRef(4, iEdge);

	return fDistance;
}

public int Native_NavNode_PushAttachment(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);
	NavNode mNavNode = GetNativeCell(3);
	int iAttachedNodeEdge = GetNativeCell(4);
	int iAttachmentFlags = GetNativeCell(5);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	int iAttachment = eNavNode.PushAttachment(iEdge, mNavNode, iAttachedNodeEdge, iAttachmentFlags);

	g_hNavNodes.SetArray(iThis, eNavNode);

	return iAttachment;
}

public int Native_NavNode_EraseAttachment(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);
	int iAttachment = GetNativeCell(3);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	eNavNode.EraseAttachment(iEdge, iAttachment);

	g_hNavNodes.SetArray(iThis, eNavNode);

	return 0;
}

public int Native_NavNode_FindAttachment(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);
	NavNode mSearchNode = GetNativeCell(3);
	int iStart = GetNativeCell(4);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	int iAttachment = eNavNode.FindAttachment(iEdge, mSearchNode, iStart);

	return iAttachment;
}

public any Native_NavNode_FindAttachmentWithFlags(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iFindAttachmentFlags = GetNativeCell(2);
	bool bExactMatch = GetNativeCell(3);
	int iEdge = GetNativeCellRef(4);
	int iAttachment = GetNativeCellRef(5);
	NavNode mAttachedNode = GetNativeCellRef(6);
	int iAttachedNodeEdge = GetNativeCellRef(7);
	int iAttachmentFlags = GetNativeCellRef(8);
	int iStartEdge = GetNativeCellRef(9);
	int iStartAttachment = GetNativeCellRef(10);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	bool bFound = eNavNode.FindAttachmentWithFlags(iFindAttachmentFlags, bExactMatch, iEdge, iAttachment, mAttachedNode, iAttachedNodeEdge, iAttachmentFlags, iStartEdge, iStartAttachment);

	SetNativeCellRef(4, iEdge);
	SetNativeCellRef(5, iAttachment);
	SetNativeCellRef(6, mAttachedNode);
	SetNativeCellRef(7, iAttachedNodeEdge);
	SetNativeCellRef(8, iAttachmentFlags);
	SetNativeCellRef(9, iStartEdge);
	SetNativeCellRef(10, iStartAttachment);

	return bFound;
}

public any Native_NavNode_FindAttachedNode(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	NavNode mSearchNode = GetNativeCell(2);
	int iEdge = GetNativeCellRef(3);
	int iAttachment = GetNativeCellRef(4);
	int iAttachmentFlags = GetNativeCellRef(5);
	int iAttachedNodeEdge = GetNativeCellRef(6);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	if (eNavNode.FindAttachedNode(mSearchNode, iEdge, iAttachment, iAttachmentFlags, iAttachedNodeEdge)) {
		SetNativeCellRef(3, iEdge);
		SetNativeCellRef(4, iAttachment);
		SetNativeCellRef(5, iAttachmentFlags);
		SetNativeCellRef(6, iAttachedNodeEdge);
		return true;
	}

	return false;
}

public int Native_NavNode_GetAttachment(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);
	int iAttachment = GetNativeCell(3);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	NavNode mAttachedNode;
	int iAttachedNodeEdge;
	int iAttachmentFlags;
	eNavNode.GetAttachment(iEdge, iAttachment, mAttachedNode, iAttachedNodeEdge, iAttachmentFlags);

	SetNativeCellRef(4, mAttachedNode);
	SetNativeCellRef(5, iAttachedNodeEdge);
	SetNativeCellRef(6, iAttachmentFlags);

	return 0;
}

public int Native_NavNode_SetAttachment(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);
	int iAttachment = GetNativeCell(3);
	NavNode mAttachedNode = GetNativeCell(4);
	int iAttachedNodeEdge = GetNativeCell(5);
	int iAttachmentFlags = GetNativeCell(6);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	eNavNode.SetAttachment(iEdge, iAttachment, mAttachedNode, iAttachedNodeEdge, iAttachmentFlags);

	g_hNavNodes.SetArray(iThis, eNavNode);

	return 0;
}

public int Native_NavNode_GetAttachmentsLength(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	return eNavNode.GetAttachmentsLength(iEdge);
}

public int Native_NavNode_GetClosestEdge(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecPoint[3];
	GetNativeArray(2, vecPoint, sizeof(vecPoint));

	return eNavNode.GetClosestEdge(vecPoint);
}

public int Native_NavNode_GetFarthestEdge(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPoint[3];
	GetNativeArray(2, vecPoint, sizeof(vecPoint));

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	return eNavNode.GetFarthestEdge(vecPoint);
}

public int Native_NavNode_ClearAttachments(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	eNavNode.ClearAttachments(iEdge);

	g_hNavNodes.SetArray(iThis, eNavNode);

	return 0;
}

public any Native_NavNode_Contains(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float fSlack = GetNativeCell(2);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecPoint[3];
	GetNativeArray(2, vecPoint, sizeof(vecPoint));

	return eNavNode.Contains(vecPoint, fSlack);
}

public int Native_NavNode_Update(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	eNavNode.Update();

	g_hNavNodes.SetArray(iThis, eNavNode);

	return 0;
}

public any Native_NavNode_Instance(Handle hPlugin, int iArgC) {
	static _NavNode eNavNode;

	int iFreeIdx = g_hNavNodes.FindValue(true, _NavNode::bGCFlag);
	if (iFreeIdx != -1) {
		g_hNavNodes.SetArray(iFreeIdx, eNavNode);

		return iFreeIdx+1;
	}

	return g_hNavNodes.PushArray(eNavNode)+1;
}

public any Native_NavNode_Destroy(Handle hPlugin, int iArgC) {
	int iNavNodeIdx = GetNativeCell(1)-1;
	if (iNavNodeIdx < 0 || iNavNodeIdx >= g_hNavNodes.Length) {
		return 0;
	}

	g_hNavNodes.Set(iNavNodeIdx, true, _NavNode::bGCFlag);

	SetNativeCellRef(1, NULL_NAV_NODE);

	if (iNavNodeIdx == g_hNavNodes.Length-1) {
		for (int i=iNavNodeIdx; i>0; i--) {
			if (!g_hNavNodes.Get(i-1, _NavNode::bGCFlag)) {
				g_hNavNodes.Resize(i);
				return 0;
			}
		}

		g_hNavNodes.Clear();
	}

	return 0;
}

// Navigation mesh natives

public int Native_NavMesh_GetTimestamp(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;
	return g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::iTimestamp);
}

public any Native_NavMesh_SetTimestamp(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;
	int iTimestamp = GetNativeCell(2);

	g_hNavMeshes.Set(iNavMeshIdx, iTimestamp, _NavMesh::iTimestamp);

	return 0;
}

public any Native_NavMesh_GetFileName(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;
	int iMaxLength = GetNativeCell(3);

	_NavMesh eNavMesh;
	g_hNavMeshes.GetArray(iNavMeshIdx, eNavMesh);

	SetNativeString(2, eNavMesh.sFileName, iMaxLength);

	return 0;
}

public any Native_NavMesh_SetFileName(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;

	_NavMesh eNavMesh;
	g_hNavMeshes.GetArray(iNavMeshIdx, eNavMesh);

	GetNativeString(2, eNavMesh.sFileName, sizeof(_NavMesh::sFileName));

	g_hNavMeshes.SetArray(iNavMeshIdx, eNavMesh);

	return 0;
}

public any Native_NavMesh_GetMapName(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;
	int iMaxLength = GetNativeCell(3);

	_NavMesh eNavMesh;
	g_hNavMeshes.GetArray(iNavMeshIdx, eNavMesh);

	SetNativeString(2, eNavMesh.sMapName, iMaxLength);

	return 0;
}

public any Native_NavMesh_SetMapName(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;

	_NavMesh eNavMesh;
	g_hNavMeshes.GetArray(iNavMeshIdx, eNavMesh);

	GetNativeString(2, eNavMesh.sMapName, sizeof(_NavMesh::sMapName));

	g_hNavMeshes.SetArray(iNavMeshIdx, eNavMesh);

	return 0;
}

public any Native_NavMesh_GetNodes(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;

	ArrayList hNavNodes = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::hNavNodes);

	return CloneHandle(hNavNodes, hPlugin);
}

public int Native_NavMesh_GetNodesInRange(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;

	float vecPoint[3];
	GetNativeArray(2, vecPoint, sizeof(vecPoint));

	float fRadius = GetNativeCell(3);

	ArrayList hResults = GetNativeCell(4);
	hResults.Clear();

	bool bCheckHulls = GetNativeCell(5);

	if (g_bOctreeAvailable) {
		Octree mOctree = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::mOctree);
		if (!mOctree) {
			return 0;
		}

		int iNodesFound = mOctree.Find(vecPoint, fRadius, hResults);
		if (bCheckHulls) {
			for (int i=0; i<iNodesFound; i++) {
				NavNode mNavNode = hResults.Get(i);
				if (!mNavNode.Contains(vecPoint)) {
					hResults.Erase(i--);
					iNodesFound--;
				}
			}
		}

		return iNodesFound;
	}

	ArrayList hNavNodes = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::hNavNodes);

	int iNavNodesLength = hNavNodes.Length;
	if (!iNavNodesLength) {
		return 0;
	}

	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);

		float vecOrigin[3];
		mNavNode.GetOrigin(vecOrigin);

		float fDistance = GetVectorDistance(vecPoint, vecOrigin);
		if (fDistance <= fRadius && !(bCheckHulls && !mNavNode.Contains(vecPoint))) {
			hResults.Push(mNavNode);
		}
	}

	return hResults.Length;
}

public any Native_NavMesh_GetNearestNodeInRange(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;

	float vecPoint[3];
	GetNativeArray(2, vecPoint, sizeof(vecPoint));

	float fRadius = GetNativeCell(3);

	bool bCheckHulls = GetNativeCell(4);

	float fSlack = GetNativeCell(5);

	ArrayList hNavNodes;

	if (g_bOctreeAvailable) {
		Octree mOctree = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::mOctree);
		if (!mOctree) {
			return NULL_NAV_NODE;
		}

		hNavNodes = new ArrayList();
		int iNodesFound = mOctree.Find(vecPoint, fRadius, hNavNodes, true);
		if (bCheckHulls) {
			for (int i=0; i<iNodesFound; i++) {
				NavNode mNavNode = hNavNodes.Get(i);
				if (!mNavNode.Contains(vecPoint, fSlack)) {
					hNavNodes.Erase(i--);
					iNodesFound--;
				}
			}
		}
	} else {
		hNavNodes = view_as<ArrayList>(g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::hNavNodes)).Clone();
	}

	int iNavNodesLength = hNavNodes.Length;
	if (!iNavNodesLength) {
		delete hNavNodes;
		return NULL_NAV_NODE;
	}

	float fMinDistance = POSITIVE_INFINITY;
	NavNode mNearestNode;

	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);

		float vecOrigin[3];
		mNavNode.GetOrigin(vecOrigin);

		float fDistance = GetVectorDistance(vecPoint, vecOrigin);
		if (fDistance <= fRadius && !(bCheckHulls && !mNavNode.Contains(vecPoint)) && fDistance < fMinDistance) {
			mNearestNode = mNavNode;
			fMinDistance = fDistance;
		}
	}

	delete hNavNodes;
	return mNearestNode;
}

public int Native_NavMesh_UpdateIndex(Handle hPlugin, int iArgC) {
	if (g_bOctreeAvailable) {
		int iNavMeshIdx = GetNativeCell(1)-1;
		BuildSpatialIdx(iNavMeshIdx);
	}

	return 0;
}

public any Native_NavMesh_Instance(Handle hPlugin, int iArgC) {
	_NavMesh eNavMesh;
	eNavMesh.hNavNodes = new ArrayList();

	int iFreeIdx = g_hNavMeshes.FindValue(true, _NavMesh::bGCFlag);
	if (iFreeIdx != -1) {
		g_hNavMeshes.SetArray(iFreeIdx, eNavMesh);

		return iFreeIdx+1;
	}

	return g_hNavMeshes.PushArray(eNavMesh)+1;
}

public any Native_NavMesh_Destroy(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;
	if (iNavMeshIdx < 0 || iNavMeshIdx >= g_hNavMeshes.Length) {
		return 0;
	}

	ArrayList hNavNodes = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::hNavNodes);
	int iNavNodesLength = hNavNodes.Length;
	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);
		NavNode.Destroy(mNavNode);
	}
	delete hNavNodes;

	Octree mOctree = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::mOctree);
	if (mOctree) {
		Octree.Destroy(mOctree);
	}

	g_hNavMeshes.Set(iNavMeshIdx, true, _NavMesh::bGCFlag);

	SetNativeCellRef(1, NULL_NAV_MESH);

	if (iNavMeshIdx == g_hNavMeshes.Length-1) {
		for (int i=iNavMeshIdx; i>0; i--) {
			if (!g_hNavMeshes.Get(i-1, _NavMesh::bGCFlag)) {
				g_hNavMeshes.Resize(i);
				return 0;
			}
		}

		g_hNavMeshes.Clear();
	}

	return 0;
}

public any Native_NavMesh_LoadNavFile(Handle hPlugin, int iArgC) {
	char sFilePath[PLATFORM_MAX_PATH];
	GetNativeString(1, sFilePath, sizeof(sFilePath));

	float fTimestamp = GetEngineTime();

	File hFile = OpenFile(sFilePath, "rb");
	if (hFile == null) {
		LogError("Cannot open file for reading: %s", sFilePath);
		return NULL_NAV_MESH;
	}

	char sIdentifier[8];
	if (hFile.ReadString(sIdentifier, sizeof(sIdentifier)) == -1 || !StrEqual("SMBLNAV", sIdentifier)) {
		LogError("Not a SMBL nav file: %s %s", sIdentifier, sFilePath);
		delete hFile;
		return NULL_NAV_MESH;
	}

	char sFileName[PLATFORM_MAX_PATH];
	int iPathFileSplit = FindCharInString(sFilePath, '/', true);
	if (iPathFileSplit == -1) {
		sFileName = sFilePath;
	} else {
		strcopy(sFileName, sizeof(sFileName), sFilePath[iPathFileSplit+1]);
	}

	NavMesh mNavMesh = NavMesh.Instance();
	mNavMesh.SetFileName(sFileName);

	hFile.Seek(0xA, SEEK_SET);

	int iTimestamp;
	hFile.ReadInt32(iTimestamp);
	mNavMesh.iTimestamp = iTimestamp;

	hFile.Seek(0xE, SEEK_SET);

	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sFileMapName[32];
	hFile.ReadString(sFileMapName, sizeof(sFileMapName));
	if (!StrEqual(sMapName, sFileMapName, false)) {
		PrintToServer("[SMBL] Warning: Map mismatch (%s): %s", sFileMapName, sFilePath);
	}

	mNavMesh.SetMapName(sFileMapName);

	hFile.Seek(0x2E, SEEK_SET);
	int iMetaPosNodeData;
	hFile.ReadInt32(iMetaPosNodeData);

	hFile.Seek(0x32, SEEK_SET);
	int iMetaPosAttachmentData;
	hFile.ReadInt32(iMetaPosAttachmentData);

	hFile.Seek(iMetaPosNodeData, SEEK_SET);

	int iNavNodesLength;
	hFile.ReadInt32(iNavNodesLength);

	ArrayList hNavNodes = mNavMesh.GetNodes();

	float vecPoint[3];
	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = NavNode.Instance();

		// Origin
		hFile.ReadInt32(view_as<int>(vecPoint[0]));
		hFile.ReadInt32(view_as<int>(vecPoint[1]));
		hFile.ReadInt32(view_as<int>(vecPoint[2]));

		mNavNode.SetOrigin(vecPoint);

		int iVertices;
		hFile.ReadUint8(iVertices);
		mNavNode.iVertices = iVertices;

		for (int j=0; j<iVertices; j++) {
			hFile.ReadInt32(view_as<int>(vecPoint[0]));
			hFile.ReadInt32(view_as<int>(vecPoint[1]));
			hFile.ReadInt32(view_as<int>(vecPoint[2]));

			mNavNode.SetVertex(j, vecPoint);
		}

		mNavNode.Update();

		hNavNodes.Push(mNavNode);
	}

	hFile.Seek(iMetaPosAttachmentData, SEEK_SET);

	int iAttachmentCount;

	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);

		int iVertices = mNavNode.iVertices;
		for (int j=0; j<iVertices; j++) {
			int iAttachmentsLength;
			hFile.ReadUint8(iAttachmentsLength);

			for (int k=0; k<iAttachmentsLength; k++) {
				NavNode mAttachedNode;
				int iAttachedNodeIdx;
				int iAttachedNodeEdge;
				int iAttachmentFlags;

				hFile.ReadInt32(iAttachedNodeIdx);
				hFile.ReadUint8(iAttachedNodeEdge);
				hFile.ReadInt32(iAttachmentFlags);

				mAttachedNode = iAttachedNodeIdx == -1 ? NULL_NAV_NODE : hNavNodes.Get(iAttachedNodeIdx);

				mNavNode.PushAttachment(j, mAttachedNode, iAttachedNodeEdge, iAttachmentFlags);

				if (mAttachedNode) {
					iAttachmentCount++;
				}
			}
		}
	}

	delete hFile;

	PrintToServer("[SMBL] Loaded nav mesh with %d nodes and %d attachments in %.3f ms", iNavNodesLength, iAttachmentCount, 1000*(GetEngineTime()-fTimestamp));

	mNavMesh.UpdateIndex();


	return mNavMesh;
}

public int Native_NavMesh_SaveNavFile(Handle hPlugin, int iArgC) {
	NavMesh mNavMesh;
	mNavMesh = GetNativeCell(1);
	if (!mNavMesh) {
		return false;
	}

	char sFilePath[PLATFORM_MAX_PATH];
	GetNativeString(2, sFilePath, sizeof(sFilePath));

	File hFile = OpenFile(sFilePath, "wb");
	if (hFile == null) {
		LogError("Cannot open file for writing: %s", sFilePath);
		return false;
	}

	hFile.WriteString("SMBLNAV", true); // Identifier

	// 0x8
	hFile.WriteInt8(NAV_FORMAT_VERSION_MAJOR); // File format version major
	hFile.WriteInt8(NAV_FORMAT_VERSION_MINOR); // File format version minor

	// 0xA
	hFile.WriteInt32(GetTime());

	// 0xE
	int iPosMapName = hFile.Position;
	hFile.Write(view_as<int>({0, 0, 0, 0, 0, 0, 0, 0}), 8, 4);

	// 0x2E
	int iMetaPosNodeData = hFile.Position;
	hFile.WriteInt32(0);

	// 0x32
	int iMetaPosAttachmentData = hFile.Position;
	hFile.WriteInt32(0);

	// 0x36
	int iPosNodeData = hFile.Position;
	hFile.Seek(iMetaPosNodeData, SEEK_SET);
	hFile.WriteInt32(iPosNodeData);

	hFile.Seek(iPosMapName, SEEK_SET);
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));
	hFile.WriteString(sMapName, true);

	hFile.Seek(iPosNodeData, SEEK_SET);

	ArrayList hNavNodes = mNavMesh.GetNodes();
	int iNavNodesLength = hNavNodes.Length;

	// Lookup 0x2E for this address
	hFile.WriteInt32(iNavNodesLength);	// Number of nodes

	float vecPoint[3];
	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);
		mNavNode.GetOrigin(vecPoint);

		// Origin
		hFile.WriteInt32(view_as<int>(vecPoint[0]));
		hFile.WriteInt32(view_as<int>(vecPoint[1]));
		hFile.WriteInt32(view_as<int>(vecPoint[2]));

		int iVertices = mNavNode.iVertices;
		hFile.WriteInt8(iVertices);	// Number of vertices in hull

		for (int j=0; j<iVertices; j++) {
			mNavNode.GetVertex(j, vecPoint);

			// Vertex coordinates
			hFile.WriteInt32(view_as<int>(vecPoint[0]));
			hFile.WriteInt32(view_as<int>(vecPoint[1]));
			hFile.WriteInt32(view_as<int>(vecPoint[2]));
		}
	}

	int iPosAttachmentData = hFile.Position;
	hFile.Seek(iMetaPosAttachmentData, SEEK_SET);
	hFile.WriteInt32(iPosAttachmentData);
	hFile.Seek(iPosAttachmentData, SEEK_SET);

	// Lookup 0x32 for this address
	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);

		int iVertices = mNavNode.iVertices;
		for (int j=0; j<iVertices; j++) {
			int iAttachmentsLength = mNavNode.GetAttachmentsLength(j);

			hFile.WriteInt8(iAttachmentsLength);

			for (int k=0; k<iAttachmentsLength; k++) {
				NavNode mAttachedNode;
				int iAttachedNodeEdge;
				int iAttachmentFlags;
				mNavNode.GetAttachment(j, k, mAttachedNode, iAttachedNodeEdge, iAttachmentFlags);

				hFile.WriteInt32(hNavNodes.FindValue(mAttachedNode));
				hFile.WriteInt8(iAttachedNodeEdge);
				hFile.WriteInt32(iAttachmentFlags);
			}
		}
	}

	delete hNavNodes;

	hFile.Flush();

	delete hFile;

	return true;
}

public int Native_RegisterNavMesh(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	NavMesh mNavMesh = GetNativeCell(2);

	if (g_hNavMeshesMap.SetValue(sIdentifier, mNavMesh, false)) {
		PrintToServer("SMBL registered navigation mesh: %s", sIdentifier);
		return true;
	}

	PrintToServer("SMBL cannot register navigation mesh: %s (duplicate?)", sIdentifier);

	return false;
}

public int Native_DeregisterNavMesh(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	bool bDestroy = GetNativeCell(2);
	if (bDestroy) {
		NavMesh mNavMesh;
		if (!g_hNavMeshesMap.GetValue(sIdentifier, mNavMesh)) {
			PrintToServer("SMBL cannot find navigation mesh to deregister: %s", sIdentifier);
			return false;
		}

		PrintToServer("SMBL deregistered navigation mesh: %s", sIdentifier);

		NavMesh.Destroy(mNavMesh);
	}

	return g_hNavMeshesMap.Remove(sIdentifier);
}

public int Native_DeregisterAllNavMeshes(Handle hPlugin, int iArgC) {
	bool bDestroy = GetNativeCell(1);
	if (bDestroy) {
		StringMapSnapshot hSnapshot = g_hNavMeshesMap.Snapshot();
		int iSnapshotLength = hSnapshot.Length;
		char sIdentifier[64];

		for (int i=0; i<iSnapshotLength; i++) {
			hSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));
			NavMesh mNavMesh;
			if (g_hNavMeshesMap.GetValue(sIdentifier, mNavMesh)) {
				NavMesh.Destroy(mNavMesh);
			}
		}

		delete hSnapshot;

		PrintToServer("SMBL deregistered %d navigation meshes", g_hNavMeshesMap.Size);
	}

	g_hNavMeshes.Clear();

	return 0;
}

public any Native_GetNavMesh(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	NavMesh mNavMesh;
	g_hNavMeshesMap.GetValue(sIdentifier, mNavMesh);

	return mNavMesh;
}

// Helpers

void BuildSpatialIdx(int iNavMeshIdx) {
	float fTimestamp = GetEngineTime();

	ArrayList hNavNodes = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::hNavNodes);

	float vecMin[3] = {POSITIVE_INFINITY, ...};
	float vecMax[3] = {NEGATIVE_INFINITY, ...};

	int iNavNodesLength = hNavNodes.Length;
	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);

		float vecOrigin[3];
		mNavNode.GetOrigin(vecOrigin);

		vecMin[0] = vecOrigin[0] < vecMin[0] ? vecOrigin[0] : vecMin[0];
		vecMin[1] = vecOrigin[1] < vecMin[1] ? vecOrigin[1] : vecMin[1];
		vecMin[2] = vecOrigin[2] < vecMin[2] ? vecOrigin[2] : vecMin[2];

		vecMax[0] = vecOrigin[0] > vecMax[0] ? vecOrigin[0] : vecMax[0];
		vecMax[1] = vecOrigin[1] > vecMax[1] ? vecOrigin[1] : vecMax[1];
		vecMax[2] = vecOrigin[2] > vecMax[2] ? vecOrigin[2] : vecMax[2];
	}

	Octree mOctree = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::mOctree);
	if (mOctree) {
		Octree.Destroy(mOctree);
	}

	float vecCenter[3];
	AddVectors(vecMin, vecMax, vecCenter);
	ScaleVector(vecCenter, 0.5);

	float vecHalfWidth[3];
	SubtractVectors(vecMax, vecMin, vecHalfWidth);
	ScaleVector(vecHalfWidth, 0.5);

	float fMaxHalfWidth = vecHalfWidth[0];
	fMaxHalfWidth = vecHalfWidth[1] > fMaxHalfWidth ? vecHalfWidth[1] : fMaxHalfWidth;
	fMaxHalfWidth = vecHalfWidth[2] > fMaxHalfWidth ? vecHalfWidth[2] : fMaxHalfWidth;
	fMaxHalfWidth += 50.0; // Prevents Octree out of bounds

	mOctree = Octree.Instance(vecCenter, fMaxHalfWidth, 3);

	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);

		float vecOrigin[3];
		mNavNode.GetOrigin(vecOrigin);

		mOctree.Insert(vecOrigin, mNavNode);
	}

	g_hNavMeshes.Set(iNavMeshIdx, mOctree, _NavMesh::mOctree);

	PrintToServer("[SMBL] Built nav %d spatial index in %.3f ms", iNavMeshIdx, 1000*(GetEngineTime()-fTimestamp));
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
