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

	void GetEdgeCenter(int iEdge, float vecPoint[3]) {
		int iOffset = 3*iEdge;
		vecPoint[0] = this.vecEdgeCenters[iOffset  ];
		vecPoint[1] = this.vecEdgeCenters[iOffset+1];
		vecPoint[2] = this.vecEdgeCenters[iOffset+2];
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

	int ClearAttachments(int iEdge) {
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

	void Update() {
		static float vecVertices[MAX_VERTICES][3];
		int iVertices = this.iVertices;

		vecVertices[0][0] = this.vecVertices[0];
		vecVertices[0][1] = this.vecVertices[1];
		vecVertices[0][2] = this.vecVertices[2];

		this.vecBBoxMins[0] = this.vecVertices[0];
		this.vecBBoxMins[1] = this.vecVertices[1];
		this.vecBBoxMins[2] = this.vecVertices[2];

		float vecEdgeCenter[3];
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
	Octree mOctree;
	bool bGCFlag;
}

enum Orientation {
	Orientation_Colinear,
	Orientation_Clockwise,
	Orientation_CounterClockwise,
}

ArrayList g_hNavNodes;
ArrayList g_hNavMeshes;

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
}

// Navigation node natives

void SetupNavNatives() {
	CreateNative("NavNode.iVertices.get", 			Native_NavNode_GetVertices);
	CreateNative("NavNode.iVertices.set", 			Native_NavNode_SetVertices);
	CreateNative("NavNode.GetOrigin", 				Native_NavNode_GetOrigin);
	CreateNative("NavNode.SetOrigin", 				Native_NavNode_SetOrigin);
	CreateNative("NavNode.GetVertex", 				Native_NavNode_GetVertex);
	CreateNative("NavNode.SetVertex", 				Native_NavNode_SetVertex);
	CreateNative("NavNode.GetEdgeCenter", 			Native_NavNode_GetEdgeCenter);

	CreateNative("NavNode.PushAttachment",			Native_NavNode_PushAttachment);
	CreateNative("NavNode.EraseAttachment",			Native_NavNode_EraseAttachment);
	CreateNative("NavNode.GetAttachment",			Native_NavNode_GetAttachment);
	CreateNative("NavNode.SetAttachment",			Native_NavNode_SetAttachment);
	CreateNative("NavNode.FindAttachment",			Native_NavNode_FindAttachment);
	CreateNative("NavNode.ClearAttachments",		Native_NavNode_ClearAttachments);
	CreateNative("NavNode.GetAttachmentsLength",	Native_NavNode_GetAttachmentsLength);

	CreateNative("NavNode.Contains", 				Native_NavNode_Contains);
	CreateNative("NavNode.Update",					Native_NavNode_Update);

	CreateNative("NavNode.Instance", 				Native_NavNode_Instance);
	CreateNative("NavNode.Destroy", 				Native_NavNode_Destroy);

	CreateNative("NavMesh.GetNodes",	 			Native_NavMesh_GetNodes);
	CreateNative("NavMesh.GetNodesInRange",			Native_NavMesh_GetNodesInRange);
	CreateNative("NavMesh.GetNearestNodeInRange",	Native_NavMesh_GetNearestNodeInRange);
	CreateNative("NavMesh.UpdateIndex",				Native_NavMesh_UpdateIndex);

	CreateNative("NavMesh.Instance", 				Native_NavMesh_Instance);
	CreateNative("NavMesh.Destroy", 				Native_NavMesh_Destroy);

	CreateNative("NavMesh.LoadNavFile", 			Native_NavMesh_LoadNavFile);
	CreateNative("NavMesh.SaveNavFile", 			Native_NavMesh_SaveNavFile);
}

public int Native_NavNode_GetOrigin(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	SetNativeArray(2, eNavNode.vecOrigin, sizeof(_NavNode::vecOrigin));
}

public int Native_NavNode_SetOrigin(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	GetNativeArray(2, eNavNode.vecOrigin, sizeof(_NavNode::vecOrigin));
	
	g_hNavNodes.SetArray(iThis, eNavNode);
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
}

public int Native_NavNode_GetVertices(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return g_hNavNodes.Get(iThis, _NavNode::iVertices);
}

public int Native_NavNode_SetVertices(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iVertices = GetNativeCell(2);

	if (iVertices < 0 || iVertices > MAX_VERTICES) {
		ThrowError("Invalid number of vertices: %d", iVertices);
	}

	g_hNavNodes.Set(iThis, iVertices, _NavNode::iVertices);
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
}

public int Native_NavNode_FindAttachment(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);
	NavNode mNavNode = GetNativeCell(3);
	int iStart = GetNativeCell(4);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	int iAttachment = eNavNode.FindAttachment(iEdge, mNavNode, iStart);

	return iAttachment;
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
}

public int Native_NavNode_GetAttachmentsLength(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	return eNavNode.GetAttachmentsLength(iEdge);
}

public int Native_NavNode_ClearAttachments(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEdge = GetNativeCell(2);

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	eNavNode.ClearAttachments(iEdge);

	g_hNavNodes.SetArray(iThis, eNavNode);
}

public int Native_NavNode_Contains(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	float vecPoint[3];
	GetNativeArray(2, vecPoint, sizeof(vecPoint));

	if (vecPoint[0]<eNavNode.vecBBoxMins[0] || vecPoint[1]<eNavNode.vecBBoxMins[1] || vecPoint[2]<eNavNode.vecBBoxMins[2] ||
		vecPoint[0]>eNavNode.vecBBoxMaxs[0] || vecPoint[1]>eNavNode.vecBBoxMaxs[1] || vecPoint[2]>eNavNode.vecBBoxMaxs[2]) {
		return false;
	}
	
	float vecVertex[3], vecFirstVertex[3], vecLastVertex[3];
	eNavNode.GetVertex(0, vecLastVertex);
	vecFirstVertex = vecLastVertex;

	for (int i=1; i<eNavNode.iVertices; i++) {
		eNavNode.GetVertex(i, vecVertex);

		if (GetOrientation2D(vecPoint, vecLastVertex, vecVertex) != Orientation_CounterClockwise) {
			return false;
		}

		vecLastVertex = vecVertex;
	}

	return GetOrientation2D(vecPoint, vecLastVertex, vecFirstVertex) == Orientation_CounterClockwise;
}

public int Native_NavNode_Update(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_NavNode eNavNode;
	g_hNavNodes.GetArray(iThis, eNavNode);

	eNavNode.Update();

	g_hNavNodes.SetArray(iThis, eNavNode);
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
		return;
	}

	g_hNavNodes.Set(iNavNodeIdx, true, _NavNode::bGCFlag);

	SetNativeCellRef(1, NULL_NAV_NODE);

	if (iNavNodeIdx == g_hNavNodes.Length-1) {
		for (int i=iNavNodeIdx; i>0; i--) {
			if (!g_hNavNodes.Get(i-1, _NavNode::bGCFlag)) {
				g_hNavNodes.Resize(i);
				return;
			}
		}

		g_hNavNodes.Clear();
	}
}

// Navigation mesh natives

public any Native_NavMesh_GetNodes(Handle hPlugin, int iArgC) {
	int iNavMeshIdx = GetNativeCell(1)-1;

	ArrayList hNavNodes = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::hNavNodes);
// 	int iNavNodesLength = hNavNodes;

// 	for (int i=0; i<iNavNodesLength; i++) {
// 		hList.Push(hNavNodes.Get(i));
// 	}

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

	if (g_bOctreeAvailable) {
		Octree mOctree = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::mOctree);
		if (!mOctree) {
			return NULL_NAV_NODE;
		}

		ArrayList hResults = new ArrayList();
		int iNodesFound = mOctree.Find(vecPoint, fRadius, hResults, true);
		if (bCheckHulls) {
			for (int i=0; i<iNodesFound; i++) {
				NavNode mNavNode = hResults.Get(i);
				if (!mNavNode.Contains(vecPoint)) {
					hResults.Erase(i--);
					iNodesFound--;
				}
			}
		}

		if (iNodesFound) {
			NavNode mNearestNode = hResults.Get(0);
			delete hResults;
			return mNearestNode;
		}

		delete hResults;

		return NULL_NAV_NODE;
	}

	ArrayList hNavNodes = g_hNavMeshes.Get(iNavMeshIdx, _NavMesh::hNavNodes);

	int iNavNodesLength = hNavNodes.Length;
	if (!iNavNodesLength) {
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

	return mNearestNode;
}

public int Native_NavMesh_UpdateIndex(Handle hPlugin, int iArgC) {
	if (g_bOctreeAvailable) {
		int iNavMeshIdx = GetNativeCell(1)-1;
		BuildSpatialIdx(iNavMeshIdx);
	}
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
		return;
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
				return;
			}
		}

		g_hNavMeshes.Clear();
	}
}

public any Native_NavMesh_LoadNavFile(Handle hPlugin, int iArgC) {
	char sFilePath[PLATFORM_MAX_PATH];
	GetNativeString(1, sFilePath, sizeof(sFilePath));

	File hFile = OpenFile(sFilePath, "rb");
	if (hFile == null) {
		LogError("Cannot open file for reading: %s", sFilePath);
		return NULL_NAV_MESH;
	}

	char sIdentifier[8];
	if (hFile.ReadString(sIdentifier, sizeof(sIdentifier)) == -1 || !StrEqual("SMBLNAV", sIdentifier)) {
		LogError("Not a SMBL nav file: %s %s", sIdentifier, sFilePath);
		return NULL_NAV_MESH;
	}

	NavMesh mNavMesh = NavMesh.Instance();

	hFile.Seek(0xE, SEEK_SET);

	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sFileMapName[32];
	hFile.ReadString(sFileMapName, sizeof(sFileMapName));
	if (!StrEqual(sMapName, sFileMapName, false)) {
		PrintToServer("[SMBL] Warning: Map mismatch (%s): %s", sFileMapName, sFilePath);
	}

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

	mNavMesh.UpdateIndex();

	PrintToServer("[SMBL] Loaded nav mesh with %d nodes and %d attachments", iNavNodesLength, iAttachmentCount);

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

// Helpers

void BuildSpatialIdx(int iNavMeshIdx) {
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

	mOctree = Octree.Instance(vecCenter, fMaxHalfWidth, 3);

	for (int i=0; i<iNavNodesLength; i++) {
		NavNode mNavNode = hNavNodes.Get(i);

		float vecOrigin[3];
		mNavNode.GetOrigin(vecOrigin);

		mOctree.Insert(vecOrigin, mNavNode);
	}

	g_hNavMeshes.Set(iNavMeshIdx, mOctree, _NavMesh::mOctree);
}

// Adapted from https://www.geeksforgeeks.org/orientation-3-ordered-points/
Orientation GetOrientation2D(float vec1[3], float vec2[3], float vec3[3]) {
	float fVal =	(vec2[1]-vec1[1]) * (vec3[0]-vec2[0]) - 
					(vec2[0]-vec1[0]) * (vec3[1]-vec2[1]);

	if (FloatAbs(fVal) < 0.0001) {
		return Orientation_Colinear;
	}

	return fVal > 0 ? Orientation_Clockwise : Orientation_CounterClockwise;
}
