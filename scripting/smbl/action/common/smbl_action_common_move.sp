#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smlib/entities>

#include <smbl>
#include <smbl/nav_mesh>

#define NODE_PROXIMITY	500.0
#define NODE_MIN_REACH	50.0

#define PID_DEFAULT		{0.2,	0.001,	0.65}
#define PID_SLOW_LAZY	{0.05,	0.001,	0.01}
#define PID_FAST		{0.1,	0.001,	0.01}
#define PID_SNAP		{1.0,	0.000,	0.00}

#define COLOR_WHITE		view_as<int>({255, 255, 255, 255})
#define COLOR_RED		view_as<int>({255, 0, 0, 255})
#define COLOR_GREEN		view_as<int>({0, 255, 0, 255})
#define COLOR_BLUE		view_as<int>({0, 0, 255, 255})
#define COLOR_YELLOW	view_as<int>({255, 255, 0, 255})
#define COLOR_MAGENTA	view_as<int>({255, 0, 255, 255})
#define COLOR_CYAN		view_as<int>({0, 255, 255, 255})

int g_iLaser;
int g_iHalo;

public Plugin myinfo = {
	name = "SMBL Common Bot Actions Library: Move",
	author = PLUGIN_AUTHOR,
	description = "Common movement operations for all bot classes",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {

}

public void OnPluginEnd() {
	SMBL_DeregisterOperation();
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "SMBL")) {
		Setup_Walk();
	}
}

public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}

void Setup_Walk() {
	SMBL_RegisterOperation("Common.Walk", Walk_Init, Walk_Validate, _, _, Walk_Cleanup);
}

OpRet Walk_Init(Bot mBot, ArrayList hSequences, ArrayList hSubOps, any aData[16]) {
	NavMesh mNavMesh = SMBL_GetNavMesh("Ground");
	if (!mNavMesh) {
		LogError("Cannot initialize walk: Missing ground navigation mesh");
		return OpRet_Abort;
	}

	ArrayList hNodes = mNavMesh.GetNodes();
	PrintToServer("Looking up NavMesh with %d nodes", hNodes.Length);
	delete hNodes;

	float vecStart[3];
	Entity_GetAbsOrigin(mBot.iEntity, vecStart);

	float vecDest[3];
	vecDest[0] = aData[0];
	vecDest[1] = aData[1];
	vecDest[2] = aData[2];

	PrintToServer("MoveTo Start: %.1f, %.1f, %.1f", vecStart[0], vecStart[1], vecStart[2]);

	NavNode mStartNode = mNavMesh.GetNearestNodeInRange(vecStart, NODE_PROXIMITY, true);

	if (!mStartNode) {
		PrintToServer("Bot is not within mesh.  Beeline it.");

		Sequence eSeq;
		eSeq.fnRun = Walk_Sequence;
		eSeq.aData[0] = vecDest[0];
		eSeq.aData[1] = vecDest[1];
		eSeq.aData[2] = vecDest[2];

		aData[3] = hSequences;

		hSequences.PushArray(eSeq);

		return OpRet_Continue;
	}


	PrintToServer("MoveTo End: %.1f, %.1f, %.1f", vecDest[0], vecDest[1], vecDest[2]);

	NavNode mEndNode = mNavMesh.GetNearestNodeInRange(vecDest, NODE_PROXIMITY, true);
	if (!mEndNode) {
		PrintToServer("SMBL: Bot is not within mesh.  Finding closest node.");
		mEndNode = mNavMesh.GetNearestNodeInRange(vecDest);
		if (!mEndNode) {
			LogError("Cannot initialize walk: Mesh has no nodes.");
			return OpRet_Abort;
		}

		ArrayList hPathResult = new ArrayList();
		Navigation.FindShortestPath(mStartNode, mEndNode, FL_ATTACH_GROUND | FL_ATTACH_DROP, hPathResult);
		aData[4] = hPathResult;

		int iPathResultLength = hPathResult.Length;
		if (!iPathResultLength) {
			PrintToServer("End node is not reachable from start");
			return OpRet_Abort;
		}

		for (int i=0; i<iPathResultLength; i++) {
			Sequence eSeq;
			eSeq.fnRun = Walk_Sequence;

			float vecOrigin[3];
			NavNode mNavNode = hPathResult.Get(i);
			mNavNode.GetOrigin(vecOrigin);

			eSeq.aData[0] = vecOrigin[0];
			eSeq.aData[1] = vecOrigin[1];
			eSeq.aData[2] = vecOrigin[2];
			eSeq.aData[3] = i;

			hSequences.PushArray(eSeq);
		}

		PrintToServer("Init walk N2N + ext");

		mBot.iButtons |= IN_FORWARD;
		mBot.SetLocalVelocity({400.0, 0.0, 0.0});

		Sequence eSeq;
		eSeq.fnRun = Walk_Sequence;
		eSeq.aData[0] = vecDest[0];
		eSeq.aData[1] = vecDest[1];
		eSeq.aData[2] = vecDest[2];
		eSeq.aData[3] = iPathResultLength;

		hSequences.PushArray(eSeq);

		return OpRet_Continue;
	}

	ArrayList hPathResult = new ArrayList();
	Navigation.FindShortestPath(mStartNode, mEndNode, FL_ATTACH_GROUND | FL_ATTACH_DROP, hPathResult);
	aData[4] = hPathResult;

	int iPathResultLength = hPathResult.Length;
	if (!iPathResultLength) {
		PrintToServer("End node is not reachable from start");
		return OpRet_Abort;
	}

	PrintToServer("Init walk N2N");
	
	Sequence eSeq;
	for (int i=0; i<iPathResultLength; i++) {
		eSeq.fnRun = Walk_Sequence;

		float vecOrigin[3];
		NavNode mNavNode = hPathResult.Get(i);
		mNavNode.GetOrigin(vecOrigin);

		eSeq.aData[0] = vecOrigin[0];
		eSeq.aData[1] = vecOrigin[1];
		eSeq.aData[2] = vecOrigin[2];
		eSeq.aData[3] = i;

		hSequences.PushArray(eSeq);
	}

	eSeq.aData[0] = vecDest[0];
	eSeq.aData[1] = vecDest[1];
	eSeq.aData[2] = vecDest[2];
	eSeq.aData[3] = iPathResultLength;

	hSequences.PushArray(eSeq);

// 	hPathResult.Push(mStartNode);
// 	hPathResult.Push(mEndNode);

// 	Sequence eSeq;
// 	eSeq.fnRun = Walk_Sequence;

// 	eSeq.aData[0] = vecStart[0];
// 	eSeq.aData[1] = vecStart[1];
// 	eSeq.aData[2] = vecStart[2];

// 	hSequences.PushArray(eSeq);

// 	eSeq.aData[0] = vecDest[0];
// 	eSeq.aData[1] = vecDest[1];
// 	eSeq.aData[2] = vecDest[2];

// 	hSequences.PushArray(eSeq);

// 	PrintToServer("Init setting alt aData[0]=%d", aData[0]);

	mBot.iButtons |= IN_FORWARD;
	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	return OpRet_Continue;
}

OpState Walk_Validate(Bot mBot, ArrayList hSequences, any aData[16]) {
	ArrayList hPath = view_as<ArrayList>(aData[4]);
	if (!hPath) {
		return OpState_Undefined;
	}

	PrintToServer("Walk_Validate: hPath: %d, hSequences: %d", hPath.Length, hSequences.Length);

	int iDrawOffset = hPath.Length-hSequences.Length;
	if (iDrawOffset >= 0) {
		DrawPath(hPath, iDrawOffset);
	}

	return OpState_Undefined;
}

// OpRet Walk_PreRun(Operation mOp, int iClient) {

// }

// OpRet Walk_PostRun(Operation mOp, int iClient) {

// }

void Walk_Cleanup(Bot mBot, ArrayList hSequences, any aData[16]) {
	delete view_as<ArrayList>(aData[4]); // NavNode array
}

OpRet Walk_Sequence(Bot mBot, any aOpData[16], any aSeqData[16]) {
	float vecDest[3];
	vecDest[0] = aSeqData[0];
	vecDest[1] = aSeqData[1];
	vecDest[2] = aSeqData[2];

	mBot.SetMoveTo(vecDest);

	int iEntity = mBot.iEntity;

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);


	float vecDelta[3];
	SubtractVectors(vecDest, vecPos, vecDelta);

// 	float fDistance = GetVectorLength(vecDelta);
// 	PrintToServer("Distance to walk target (%.1f, %.1f, %.1f): %.1f", vecDest[0], vecDest[1], vecDest[2], fDistance);

	ArrayList hPath = view_as<ArrayList>(aOpData[4]);
	int iPathIdx = aSeqData[3];
	if (hPath && iPathIdx < hPath.Length) {
		NavNode mNode = hPath.Get(aSeqData[3]);
		if (mNode && mNode.Contains(vecPos) || GetVectorLength(vecDelta) < NODE_MIN_REACH) {
			return OpRet_Handled;
		}
	} else if (GetVectorLength(vecDelta) < NODE_MIN_REACH) {
		return OpRet_Handled;
	}

	float vecAimAng[3];
	GetVectorAngles(vecDelta, vecAimAng);
	vecAimAng[0] = 0.0;

	mBot.SetAimTo(vecAimAng);

	float vecAng[3];
	Entity_GetAbsAngles(iEntity, vecAng);

	float vecAngDiff;
	GetAngDiff(vecAng[1], vecAimAng[1], vecAngDiff);

	if (FloatAbs(vecAngDiff) < 45.0) {
		mBot.iButtons |= IN_FORWARD;
		mBot.SetLocalVelocity({400.0, 0.0, 0.0});
		mBot.SetPID(PID_SLOW_LAZY);
	} else {
		mBot.SetPID(PID_FAST);
	}

// 	mBot.iButtons |= IN_FORWARD;
// 	mBot.SetLocalVelocity({400.0, 0.0, 0.0});
// 	mBot.SetPID(PID_SLOW_LAZY);

	return OpRet_Continue;
}

void DrawPath(ArrayList hPath, int iStart=0) {
	for (int j=iStart; j<hPath.Length-1; j++) {
		NavNode mNodeA = hPath.Get(j);
		NavNode mNodeB = hPath.Get(j+1);

		int iColor[4];

		switch (j%6) {
			case 0:
				iColor = COLOR_RED;
			case 1:
				iColor = COLOR_YELLOW;
			case 2:
				iColor = COLOR_GREEN;
			case 3:
				iColor = COLOR_MAGENTA;
			case 4:
				iColor = COLOR_BLUE;
			case 5:
				iColor = COLOR_CYAN;
		}

		float vecOriginA[3], vecOriginB[3];
		mNodeA.GetOrigin(vecOriginA);
		mNodeB.GetOrigin(vecOriginB);

		DrawDebugLine(vecOriginA, vecOriginB, iColor, 0.1);
	}
}

void DrawDebugLine(float fPos[3], float fPos2[3], int iColor[4], float fLife=0.1) {
	TE_SetupBeamPoints(fPos, fPos2, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 1.0, 1, 0.0, iColor, 0);
	TE_SendToAll();
}

void ClipAngle(float &fValue, float fMin=-360.0, float fMax=360.0) {
	if (fValue < fMin) {
		fValue = fMin;
	} else if (fValue > fMax) {
		fValue = fMax;
	}
}

int GetAngDiff(float fAngA, float fAngB, float &fDiff) {
	fDiff = fAngA - fAngB;
	if (fDiff < -180.0) {
		fDiff += 360.0;

		ClipAngle(fDiff);
		return -1;
	} else if (fDiff > 180.0) {
		fDiff -= 360.0;
	}

	ClipAngle(fDiff);
	return 1;
}
