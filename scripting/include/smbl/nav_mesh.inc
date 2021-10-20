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
	MarkNativeAsOptional("NavNode.GetEdgeCenter");

	MarkNativeAsOptional("NavNode.PushAttachment");	
	MarkNativeAsOptional("NavNode.EraseAttachment");	
	MarkNativeAsOptional("NavNode.GetAttachment");	
	MarkNativeAsOptional("NavNode.SetAttachment");	
	MarkNativeAsOptional("NavNode.FindAttachment");	
	MarkNativeAsOptional("NavNode.ClearAttachments");	
	MarkNativeAsOptional("NavNode.GetAttachmentsLength");	

	MarkNativeAsOptional("NavNode.Contains");
	MarkNativeAsOptional("NavNode.Instance");
	MarkNativeAsOptional("NavNode.Destroy");

	MarkNativeAsOptional("NavMesh.GetNodes");
	MarkNativeAsOptional("NavMesh.GetNearestNode");
	MarkNativeAsOptional("NavMesh.UpdateIndex");
	MarkNativeAsOptional("NavMesh.Instance");
	MarkNativeAsOptional("NavMesh.Destroy");

	MarkNativeAsOptional("NavMesh.LoadNavFile");
	MarkNativeAsOptional("NavMesh.SaveNavFile");
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

	public native void GetEdgeCenter(int iEdge, float vecPoint[3]);

	public native int PushAttachment(int iEdge, NavNode mAttachedNode, int iAttachedNodeEdge, int iAttachmentFlags);
	public native void EraseAttachment(int iEdge, int iAttachment);
	public native void GetAttachment(int iEdge, int iAttachment, NavNode &mAttachedNode=NULL_NAV_NODE, int &iAttachedNodeEdge=-1, int &iAttachmentFlags=0);
	public native void SetAttachment(int iEdge, int iAttachment, NavNode mAttachedNode, int iAttachedNodeEdge, int iAttachmentFlags);
	public native int FindAttachment(int iEdge, NavNode mAttachedNode, int iStart=0);
	public native int ClearAttachments(int iEdge);
	public native int GetAttachmentsLength(int iEdge);

	public native bool Contains(float vecPoint[3]);

	public native void Update();

	public static native NavNode Instance();
	public static native void Destroy(NavNode mNavNode);
}

methodmap NavMesh {
	public native ArrayList GetNodes();
	public native int GetNodesInRange(float vecPoint[3], float fRadius, ArrayList hResults, bool bCheckHulls=true);
	public native NavNode GetNearestNodeInRange(float vecPoint[3], float fRadius=view_as<float>(0x7F800000), bool bCheckHulls=true);
	public native void UpdateIndex();

	public static native NavMesh Instance();
	public static native void Destroy(NavMesh mNavMesh);

	public static native NavMesh LoadNavFile(char[] sFilePath);
	public static native bool SaveNavFile(NavMesh mNavMesh, char[] sFilePath);
}

methodmap Navigation {
	public static native float FindShortestPath(NavNode mStartNode, NavNode mEndNode, int iFilterAttributeFlags, ArrayList hPathResult);
}
