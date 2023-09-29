#if defined _SMBL_NAV_MESH_included
	#endinput
#endif
#define _SMBL_NAV_MESH_included

#include <sourcemod>

public SharedPlugin __pl_smbl_nav_mesh = {
	name = "smbl_nav_mesh",
	file = "smbl_nav_mesh.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_smbl_nav_mesh_SetNTVOptional() {
	MarkNativeAsOptional("NavNode.iVertices.get");
	MarkNativeAsOptional("NavNode.iVertices.set");
	MarkNativeAsOptional("NavNode.GetOrigin");
	MarkNativeAsOptional("NavNode.SetOrigin");
	MarkNativeAsOptional("NavNode.GetVertex");
	MarkNativeAsOptional("NavNode.SetVertex");
	MarkNativeAsOptional("NavNode.GetVertexAngles");
	MarkNativeAsOptional("NavNode.GetEdgeCenter");
	MarkNativeAsOptional("NavNode.GetEdgeVertices");
	MarkNativeAsOptional("NavNode.GetEdgeOverlap");

	MarkNativeAsOptional("NavNode.PushAttachment");	
	MarkNativeAsOptional("NavNode.EraseAttachment");	
	MarkNativeAsOptional("NavNode.GetAttachment");	
	MarkNativeAsOptional("NavNode.SetAttachment");	
	MarkNativeAsOptional("NavNode.FindAttachment");	
	MarkNativeAsOptional("NavNode.ClearAttachments");	
	MarkNativeAsOptional("NavNode.GetAttachmentsLength");	

	MarkNativeAsOptional("NavNode.Contains");

	MarkNativeAsOptional("NavNode.Update");

	MarkNativeAsOptional("NavNode.Instance");
	MarkNativeAsOptional("NavNode.Destroy");

	MarkNativeAsOptional("NavMesh.GetNodes");
	MarkNativeAsOptional("NavMesh.GetNodesInRange");
	MarkNativeAsOptional("NavMesh.GetNearestNodeInRange");
	MarkNativeAsOptional("NavMesh.UpdateIndex");

	MarkNativeAsOptional("NavMesh.Instance");
	MarkNativeAsOptional("NavMesh.Destroy");

	MarkNativeAsOptional("NavMesh.LoadNavFile");
	MarkNativeAsOptional("NavMesh.SaveNavFile");

	MarkNativeAsOptional("Navigation.FindShortestPath");
	MarkNativeAsOptional("Navigation.CheckLineOfSight");

	MarkNativeAsOptional("SMBL_RegisterNavMesh");
	MarkNativeAsOptional("SMBL_DeregisterNavMesh");
	MarkNativeAsOptional("SMBL_DeregisterAllNavMeshes");
	MarkNativeAsOptional("SMBL_GetNavMesh");
}
#endif

#define NULL_NAV_NODE	view_as<NavNode>(0)
#define NULL_NAV_MESH	view_as<NavMesh>(0)

#define MAX_NODE_VERTICES		8
#define MAX_EDGE_ATTACHMENTS	8

// Attached node attribute masks
#define FL_ATTACH_BLOCKED			(1 << 0)
#define FL_ATTACH_GROUND			(1 << 1)
#define FL_ATTACH_SOLID				(1 << 2)
#define FL_ATTACH_WALL				(1 << 3)
#define FL_ATTACH_NO_CLEARANCE		(1 << 4)
#define FL_ATTACH_UNCHARTED			(1 << 5)
#define FL_ATTACH_MUST_DUCK			(1 << 6)
#define FL_ATTACH_MUST_JUMP			(1 << 7)
#define FL_ATTACH_PRECISE			(1 << 8)
#define FL_ATTACH_DROP				(1 << 9)
#define FL_ATTACH_AVOID				(1 << 10)
#define FL_ATTACH_HAZARD			(1 << 11)
#define FL_ATTACH_UNSURVIVABLE		(1 << 12)
#define FL_ATTACH_TRANSIENT			(1 << 13)
#define FL_ATTACH_ANY				0xFFFFFFFF

#define NaN					view_as<float>(0x7FC00000)
#define POSITIVE_INFINITY	view_as<float>(0x7F800000)

methodmap NavNode {
	property int iVertices {
		public native get();
		public native set(int iVertices);
	}

	public native void GetOrigin(float vecOrigin[3]);
	public native void SetOrigin(float vecOrigin[3]);

	public native void GetVertex(int iVertex, float vecVertex[3]);
	public native void SetVertex(int iVertex, float vecVertex[3]);

	public void GetVertices(float vecVertices[MAX_NODE_VERTICES][3], int &iVertices) {
		iVertices = this.iVertices;

		for (int i=0; i<iVertices; i++) {
			this.GetVertex(i, vecVertices[i]);
		}
	}

	public native void GetVertexAngles(int iVertex, float vecAngles[3]);

	public native void GetEdgeCenter(int iEdge, float vecPoint[3]);
	public native void GetEdgeVertices(int iEdge, float vecVertexA[3], float vecVertexB[3]);
	public native void GetEdgeOverlap(int iEdge, NavNode mOtherNode, int iOtherEdge, float vecVertexA[3], float vecVertexB[3]);
	public native float GetNearestEdgeProjection(float vecInteralPoint[3], float vecEdgeProj[3], int &iEdge=-1, int &iAttachment, int iAttachmentFlags=0, float vecDirection[3]=NULL_VECTOR);
	public native float GetHullProjection(float vecPoint[3], float vecHullPoint[3], int &iEdge=-1);

	public native int PushAttachment(int iEdge, NavNode mAttachedNode, int iAttachedNodeEdge, int iAttachmentFlags);
	public native void EraseAttachment(int iEdge, int iAttachment);
	public native void GetAttachment(int iEdge, int iAttachment, NavNode &mAttachedNode=NULL_NAV_NODE, int &iAttachedNodeEdge=-1, int &iAttachmentFlags=0);
	public native void SetAttachment(int iEdge, int iAttachment, NavNode mAttachedNode, int iAttachedNodeEdge, int iAttachmentFlags);
	public native int FindAttachment(int iEdge, NavNode mSearchNode, int iStart=0);
	public native bool FindAttachmentWithFlags(int iFindAttachmentFlags, bool bExactMatch=false, int &iEdge=-1, int &iAttachment=-1, NavNode &mAttachedNode=NULL_NAV_NODE, int &iAttachedNodeEdge=-1, int &iAttachmentFlags, int &iStartEdge=0, int &iStartAttachment=0);
	public native bool FindAttachedNode(NavNode mSearchNode, int &iEdge, int &iAttachment=-1, int &iAttachmentFlags=0, int &iAttachedNodeEdge=-1);
	public native void ClearAttachments(int iEdge);
	public native int GetAttachmentsLength(int iEdge);

	public native int GetClosestEdge(float vecPoint[3]);
	public native int GetFarthestEdge(float vecPoint[3]);

	public native bool Contains(float vecPoint[3], float fSlack=0.0);

	public native void Update();

	public static native NavNode Instance();
	public static native void Destroy(NavNode mNavNode);
}

methodmap NavMesh {
	public native ArrayList GetNodes();
	public native int GetNodesInRange(float vecPoint[3], float fRadius, ArrayList hResults, bool bCheckHulls=true);
	public native NavNode GetNearestNodeInRange(float vecPoint[3], float fRadius=POSITIVE_INFINITY, bool bCheckHulls=false, float fSlack=0.0);
	public native void UpdateIndex();

	public static native NavMesh Instance();
	public static native void Destroy(NavMesh mNavMesh);

	public static native NavMesh LoadNavFile(char[] sFilePath);
	public static native bool SaveNavFile(NavMesh mNavMesh, char[] sFilePath);
}

enum PathMode {
	PathMode_Normal,
	PathMode_Bypass
}

enum struct PathData {
	NavNode mNavNode;
	int iEntryEdge;
	int iExitEdge;
	int iExitAttachmentFlags;
	PathMode iPathMode;
	float vecFocalPoint[3];
}

methodmap Navigation {
	public static native float FindShortestPath(NavNode mStartNode, NavNode mEndNode, CostFunc fnCostFunction, ArrayList hPathResult, any aData=0, float vecStartPos[3]={NaN, NaN, NaN}, float vecEndPos[3]={NaN, NaN, NaN});
	public static native void OptimizePath(ArrayList hPath, CostFunc fnCostFunction, any aData=0, int iStartIdx=0, int iEndIdx=-1, bool bBypassWithLOS=false);
	public static native float FindNearby(NavNode mStartNode, CostFunc fnCostFunction, ArrayList hPathResult, any aData=0, float vecStartPos[3]={NaN, NaN, NaN});
}

typeset CostFunc {
	function float (NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bHeuristic, any aData);
	function float (NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bHeuristic, any aData, bool &bStop);
}

native bool SMBL_RegisterNavMesh(char[] sIdentifier, NavMesh mNavMesh);
native bool SMBL_DeregisterNavMesh(char[] sIdentifier, bool bDestroy=false);
native void SMBL_DeregisterAllNavMeshes(bool bDestroy=false);
native NavMesh SMBL_GetNavMesh(char[] sIdentifier);
