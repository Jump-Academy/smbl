#if defined _SMBL_NAV_MESH_included
	#endinput
#endif
#define _SMBL_NAV_MESH_included

#include <sourcemod>
#include <smbl/utility/localdatapack>

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
	MarkNativeAsOptional("NavNode.iIndex.get");
	MarkNativeAsOptional("NavNode.iIndex.set");
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

	MarkNativeAsOptional("NavMesh.iTimestamp.get");
	MarkNativeAsOptional("NavMesh.iTimestamp.set");
	MarkNativeAsOptional("NavMesh.GetFileName");
	MarkNativeAsOptional("NavMesh.SetFileName");
	MarkNativeAsOptional("NavMesh.GetMapName");
	MarkNativeAsOptional("NavMesh.SetMapName");
	MarkNativeAsOptional("NavMesh.GetNodes");
	MarkNativeAsOptional("NavMesh.GetNodesInRange");
	MarkNativeAsOptional("NavMesh.GetNearestNodeInRange");
	MarkNativeAsOptional("NavMesh.UpdateIndex");
	MarkNativeAsOptional("NavMesh.LookupCache");

	MarkNativeAsOptional("NavMesh.Instance");
	MarkNativeAsOptional("NavMesh.Destroy");

	MarkNativeAsOptional("NavMesh.LoadNavFile");
	MarkNativeAsOptional("NavMesh.SaveNavFile");

	MarkNativeAsOptional("NavMesh.SetCacheable");
	MarkNativeAsOptional("NavMesh.RemoveCacheable");

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
#define NULL_NAV_PATH	view_as<NavPath>(0)

#define MAX_NODE_VERTICES		8
#define MAX_EDGE_ATTACHMENTS	8

// Node attachment attribute masks
#define FL_ATTACH_BLOCKED			(1 << 0)
#define FL_ATTACH_GROUND			(1 << 1)
#define FL_ATTACH_SOLID				(1 << 2)
#define FL_ATTACH_WALL				(1 << 3)
#define FL_ATTACH_LOW_CLEARANCE		(1 << 4)
#define FL_ATTACH_AIR_GAP			(1 << 5)
#define FL_ATTACH_MUST_DUCK			(1 << 6)
#define FL_ATTACH_MUST_JUMP			(1 << 7)
#define FL_ATTACH_PRECISE			(1 << 8)
#define FL_ATTACH_DROP				(1 << 9)

// Node area attribute masks
#define FL_NODE_UNCHARTED			(1 << 0)
#define FL_NODE_AVOID				(1 << 1)
#define FL_NODE_HAZARD				(1 << 2)
#define FL_NODE_UNSURVIVABLE		(1 << 3)
#define FL_NODE_TRANSIENT			(1 << 4)

#define NaN					view_as<float>(0x7FC00000)
#define POSITIVE_INFINITY	view_as<float>(0x7F800000)
#define NEGATIVE_INFINITY	view_as<float>(0xFF800000)

methodmap NavNode {
	property int iIndex {
		public native get();
		public native set(int iIndex);
	}

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
	property int iTimestamp {
		public native get();
		public native set(int iTimestamp);
	}

	public native void GetFileName(char[] sFileName, int iMaxLength);
	public native void SetFileName(char[] sFileName);

	public native void GetMapName(char[] sMapName, int iMaxLength);
	public native void SetMapName(char[] sMapName);

	public native ArrayList GetNodes();
	public native int GetNodesInRange(float vecPoint[3], float fRadius, ArrayList hResults, bool bCheckHulls=true);
	public native NavNode GetNearestNodeInRange(float vecPoint[3], float fRadius=POSITIVE_INFINITY, bool bCheckHulls=false, float fSlack=0.0);
	public native void UpdateIndex();

	public native bool LookupCache(char[] sBucketName, NavNode mNodeA, NavNode mNodeB, KeyValues hKVData=null);

	public static native NavMesh Instance();
	public static native void Destroy(NavMesh mNavMesh);

	public static native NavMesh LoadNavFile(char[] sFilePath);
	public static native bool SaveNavFile(NavMesh mNavMesh, char[] sFilePath);

	public static native bool RegisterCache(char[] sBucketName, Function fnNavCacheableFunc);
	public static native bool DeregisterCache(char[] sBucketName=NULL_STRING);
}

typedef NavCacheableFunc = function bool (NavNode mNodeA, NavNode mNodeB, KeyValues hKVData);

enum PathMode {
	PathMode_Normal,
	PathMode_Bypass
}

methodmap NavPath {
	property NavMesh mNavMesh {
		public native get();
	}

	property int iLength {
		public native get();
	}

	property float fCost {
		public native get();
	}

	public native void Get(int iIndex, NavNode &mNavNode=NULL_NAV_NODE, int &iEntryEdge=-1, int &iExitEdge=-1, int &iExitAttachmentFlags=0, LocalDataPack &mEdgeData=NULL_LOCAL_DATAPACK, PathMode &iPathMode=PathMode_Normal, float vecFocalPoint[3]={NaN, NaN, NaN});
	public native void Optimize(CostFunc fnCostFunction, LocalDataPackCleanupFunc fnCleanup=INVALID_FUNCTION, any aData=0, int iStartIdx=0, int iEndIdx=-1, bool bBypassWithLOS=false);

	public static native void Destroy(NavPath &mNavPath);
}

methodmap Navigation {
	/**
	 * Finds the shortest path from a start node to a goal using A* graph traversal
	 * If end node is not specified as the goal, this will run breadth-first search (no heuristic) unless the cost function marks a goal.
	 *
	 * @param mNavMesh			Navigation mesh to be searched
	 * @param mStartNode		Node to start the search from
	 * @param mEndNode			Node to end search (or NULL_NAV_NODE for run BFS)
	 * @param fnCostFunction	Cost function for the graph
	 * @param fnCleanup			Optional cleanup function for custom data added to the mEdgeData LocalDataPack while inside the cost function
	 * @param aData				Optional data to pass to search function
	 * @param vecStartPos		Optional position within start node
	 * @param vecEndPos			Optional position within end node
	 * @return					Navigation path (or NULL_NAV_PATH if goal is unreachable), must be destroyed with NavPath.Destroy().
	 **/
	public static native NavPath FindShortestPath(NavMesh mNavMesh, NavNode mStartNode, NavNode mEndNode, CostFunc fnCostFunction, LocalDataPackCleanupFunc fnCleanup=INVALID_FUNCTION, any aData=0, float vecStartPos[3]={NaN, NaN, NaN}, float vecEndPos[3]={NaN, NaN, NaN});
}

/**
 * Cost functions used to find the shortest path
 */
typeset CostFunc {
	/**
	 * Called to calculate the cost or heuristic between two nodes
	 *
	 * @param mNavMesh			Navigation mesh being searched
	 * @param mNodeA			Source node
	 * @param iEdgeA			Exit edge from source node
	 * @param mNodeB			Destination node
	 * @param iEdgeB			Entry edge from destination node
	 * @param iAttachmentFlags	Bit flags from source node edge for this attachment
	 * @param vecPosA			Position within source node
	 * @param vecPosB			Position within destination node
	 * @param bNodeAStart		True if mNodeA is the start node
	 * @param bNodeBGoal		True if mNodeB is the end goal node
	 * @param bHeuristic		True if callback is requesting heuristic value, false if requesting edge cost
	 * @param aData				Optional data passed to the search
	 * @param mEdgeData			Local data pack provided to optionally store metadata about this attachment to be included with the navigation path data.  It is automatically cleaned up during NavPath.Destroy().
	 * @param bMarkGoalNode		Marks destination node as a goal node to terminate the search
	 * @param bMarkGoalEdge		Marks source node exit edge as a candidate goal edge (search ends with the last node as the source node with a focal point on the edge goal, if the path from the search start node to this goal edge has the lowest cost of all paths leading to goal edge candidates)
	 */
	function float (NavMesh mNavMesh, NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bNodeAStart, bool bNodeBGoal, bool bHeuristic);
	function float (NavMesh mNavMesh, NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bNodeAStart, bool bNodeBGoal, bool bHeuristic, any aData, LocalDataPack mEdgeData);
	function float (NavMesh mNavMesh, NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bNodeAStart, bool bNodeBGoal, bool bHeuristic, any aData, LocalDataPack mEdgeData, bool &bMarkGoalNode, bool &bMarkGoalEdge);
}

native bool SMBL_RegisterNavMesh(char[] sIdentifier, NavMesh mNavMesh);
native bool SMBL_DeregisterNavMesh(char[] sIdentifier, bool bDestroy=false);
native void SMBL_DeregisterAllNavMeshes(bool bDestroy=false);
native NavMesh SMBL_GetNavMesh(char[] sIdentifier);

/**
 * Returns whether the navigation mesh is ready to accept caching.
 * @return True if ready, false if setting up
 */
native bool SMBL_NavMesh_IsCacheReady();

/**
 * Request the navigation mesh library to notify the plugin it is ready to accept caching via a call to SMBL_NavMesh_OnCache().
 * Use this to request a call to the forward if this plugin is late loaded, such as in OnPluginStart().
 * Calling this in OnPluginStart() will not cause a duplicate call to the SMBL_NavMesh_OnCache() forward.
 */
native void SMBL_NavMesh_NotifyOnCache();

/**
 * Called when the navigation mesh library is ready to accept caching.
 * This is normally called automatically after OnAllPluginsLoaded() but plugins can request a call
 * via SMBL_NavMesh_NotifyOnCache() in case of late-loading.
 */
forward void SMBL_NavMesh_OnCache();
