#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <sourcemod>
#include <smlib/entities>
#include <smlib/math>

#include <smbl>
#include <smbl/nav_mesh>

#define RANDOM_LOOK_INTERVAL	1.5
#define RANDOM_ROAM_INTERVAL	5.0
#define RANDOM_ROAM3D_INTERVAL	1.0

#define RANDOM_ROAM_MIN_DISTANCE	1000.0
#define RANDOM_ROAM3D_MIN_DISTANCE	2000.0

#define NODE_PROXIMITY	500.0

#define PID_SLOW_LAZY	{0.1,	0.001,	0.01}

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

// Library forwards

public void SMBL_OnStart() {
	Operation.Register("Process.Idle.LookAround", Idle_LookAround_Init, Idle_LookAround_Validate, _, _, _, _, _, true);

	Operation.Register("Process.Idle.Roam", Idle_Roam_Init, Idle_Roam_Validate, _, _, _, _, _, true);
	Operation.Register("Process.Idle.Roam3D", Idle_Roam_Init, Idle_Roam3D_Validate, _, _, _, _, _, true);
}

// Look Around

OpRet Idle_LookAround_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData) {
	Operation mActionOp = Operation.Instance("Common.Idle.LookAround");
	Controller.SetProcessAction(mOp, mActionOp);

	return OpRet_Continue;
}

OpRet Idle_LookAround_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData, float fStartTime) {
	return OpRet_Continue;
}

// Idle Roam

#define MIN_ROAM_DIST	50.0

enum struct OpData_Idle_Roam {
	NavMesh mNavMesh;
	OpRef mMoveOpRef;
	float vecDest[3];
	float fNextRoamTime;
	float aPadding[10];
}

OpRet Idle_Roam_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Idle_Roam eOpData) {
// 	Operation mActionOp = Operation.Instance("Process.Idle.Roam.Task");
// 	Controller.SetProcessAction(mOp, mActionOp);

// 	mBot.GetMoveTo(eOpData.vecDest);

	eOpData.mNavMesh = view_as<NavMesh>(hInitParams.GetNum("nav_mesh"));

	return OpRet_Continue;
}

OpRet Idle_Roam_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Idle_Roam eOpData, float fStartTime) {
	Operation mMoveOp = eOpData.mMoveOpRef.ToOperation();

	if (mMoveOp.IsValid() && mMoveOp.iOpState == OpState_Run) {
		return OpRet_Continue;
	}

	eOpData.mMoveOpRef = INVALID_OPERATION_REFERENCE;

	float fTime = GetGameTime();
	if (fTime < eOpData.fNextRoamTime) {
		return OpRet_Passthrough;
	}

	Controller mContr = Controller.GetProcessController(mOp);

	char sIdentifier[64];
	if (!mContr.GetRandomAction(ActionType_Locomotion, sIdentifier, sizeof(sIdentifier))) {
		return OpRet_Passthrough;
	}

	int iEntity = mContr.mBot.iEntity;

	float vecOrigin[3];
	Entity_GetAbsOrigin(iEntity, vecOrigin);

	NavNode mStartNode = eOpData.mNavMesh.GetNearestNodeInRange(vecOrigin, NODE_PROXIMITY, true, 20.0);
	if (!mStartNode) {
		mStartNode = eOpData.mNavMesh.GetNearestNodeInRange(vecOrigin, 4*NODE_PROXIMITY);
	}

	if (!mStartNode) {
		return OpRet_Passthrough;
	}

	NavPath mNavPath = Navigation.FindShortestPath(eOpData.mNavMesh, mStartNode, NULL_NAV_NODE, CostFunc_Walkable, _, iEntity);
	if (!mNavPath) {
		return OpRet_Passthrough;
	}

	PrintToServer("Found new roam path");

	eOpData.fNextRoamTime = fTime + RANDOM_ROAM_INTERVAL;

	NavNode mEndNode;
	mNavPath.Get(mNavPath.iLength-1, mEndNode);

	// TODO: Duplicate path search, reuse path

	KeyValues hActionInitParams;
	Operation mActionOp = Operation.Instance(sIdentifier, hActionInitParams);
	Controller.SetProcessAction(mOp, mActionOp);

	eOpData.mMoveOpRef = mActionOp.ToOpRef();

	float vecDest[3];
	mEndNode.GetOrigin(vecDest);

	hActionInitParams.SetNum("nav_mesh", view_as<int>(eOpData.mNavMesh));
	hActionInitParams.SetNum("end_node", view_as<int>(mEndNode));
	hActionInitParams.SetVector("destination", vecDest);

	NavPath.Destroy(mNavPath);

	return OpRet_Continue;
}

OpRet Idle_Roam3D_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Idle_Roam eOpData, float fStartTime) {
	Operation mMoveOp = eOpData.mMoveOpRef.ToOperation();

	if (mMoveOp.IsValid() && mMoveOp.iOpState == OpState_Run) {
		return OpRet_Continue;
	}

	eOpData.mMoveOpRef = INVALID_OPERATION_REFERENCE;

	float fTime = GetGameTime();
	if (fTime < eOpData.fNextRoamTime) {
		return OpRet_Passthrough;
	}

	Controller mContr = Controller.GetProcessController(mOp);

	char sIdentifier[64];
	if (!mContr.GetRandomAction(ActionType_Locomotion, sIdentifier, sizeof(sIdentifier))) {
		return OpRet_Passthrough;
	}

	int iEntity = mContr.mBot.iEntity;

	float vecOrigin[3];
	Entity_GetAbsOrigin(iEntity, vecOrigin);

	NavNode mStartNode = eOpData.mNavMesh.GetNearestNodeInRange(vecOrigin, NODE_PROXIMITY, true, 20.0);
	if (!mStartNode) {
		mStartNode = eOpData.mNavMesh.GetNearestNodeInRange(vecOrigin, 4*NODE_PROXIMITY);
	}

	if (!mStartNode) {
		return OpRet_Passthrough;
	}

	NavPath mNavPath = Navigation.FindShortestPath(eOpData.mNavMesh, mStartNode, NULL_NAV_NODE, CostFunc_Move3D, _, iEntity);
	if (!mNavPath) {
		return OpRet_Passthrough;
	}

	PrintToServer("Found new roam path");

	eOpData.fNextRoamTime = fTime + RANDOM_ROAM3D_INTERVAL;

	NavNode mEndNode;
	mNavPath.Get(mNavPath.iLength-1, mEndNode);

	KeyValues hActionInitParams;
	Operation mActionOp = Operation.Instance(sIdentifier, hActionInitParams);
	Controller.SetProcessAction(mOp, mActionOp);

	eOpData.mMoveOpRef = mActionOp.ToOpRef();

	float vecDest[3];
	mEndNode.GetOrigin(vecDest);

	hActionInitParams.SetNum("nav_mesh", view_as<int>(eOpData.mNavMesh));
	hActionInitParams.SetNum("end_node", view_as<int>(mEndNode));
	hActionInitParams.SetVector("destination", vecDest);

	NavPath.Destroy(mNavPath);

	return OpRet_Continue;
}

// Custom callbacks

float CostFunc_Walkable(NavMesh mNavMesh, NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bNodeAStart, bool bNodeBGoal, bool bHeuristic, int iEntity, LocalDataPack mEdgeData, bool &bMarkGoalNode, bool &bMarkGoalEdge) {
	if (!(iAttachmentFlags & (FL_ATTACH_GROUND | FL_ATTACH_DROP))) {
		return POSITIVE_INFINITY;
	}

	float vecOrigin[3];
	Entity_GetAbsOrigin(iEntity, vecOrigin);

	float fDistance = GetVectorDistance(vecOrigin, vecPosB);
	if (fDistance > RANDOM_ROAM_MIN_DISTANCE && GetURandomFloat() > 0.9) {
		bMarkGoalNode = true;
	}

	return GetVectorDistance(vecPosA, vecPosB);
}

float CostFunc_Move3D(NavMesh mNavMesh, NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bNodeAStart, bool bNodeBGoal, bool bHeuristic, int iEntity, LocalDataPack mEdgeData, bool &bMarkGoalNode, bool &bMarkGoalEdge) {
	if (!(iAttachmentFlags & (FL_ATTACH_WALL | FL_ATTACH_GROUND | FL_ATTACH_DROP | FL_ATTACH_AIR_GAP))) {
		return POSITIVE_INFINITY;
	}

	float vecOrigin[3];
	Entity_GetAbsOrigin(iEntity, vecOrigin);

	float fDistance = GetVectorDistance(vecOrigin, vecPosB);
	if (fDistance > RANDOM_ROAM3D_MIN_DISTANCE && GetURandomFloat() > 0.9) {
		bMarkGoalNode = true;
	}

	return GetVectorDistance(vecPosA, vecPosB);
}
