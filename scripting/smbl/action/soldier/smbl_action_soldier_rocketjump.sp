#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smlib/entities>
#include <smlib/math>

#include <smbl>
#include <smbl/nav_mesh>

#define NODE_PROXIMITY	500.0

#define WALL_MIN_REACH	50.0

#define PREDICT_TIME	1.85

#define PID_SLOW_LAZY	{0.05,	0.001,	0.01}
#define PID_FAST		{0.10,	0.001,	0.01}
#define PID_FAST_PREC	{0.10,	0.000,	0.00}
#define PID_VFAST_PREC	{0.50,	0.000,	0.00}
#define PID_SNAP		{1.00,	0.000,	0.00}

#define COLOR_WHITE		{255, 255, 255, 255}
#define COLOR_RED		{255, 0, 0, 255}
#define COLOR_GREEN		{0, 255, 0, 255}
#define COLOR_BLUE		{0, 0, 255, 255}
#define COLOR_YELLOW	{255, 255, 0, 255}
#define COLOR_MAGENTA	{255, 0, 255, 255}
#define COLOR_CYAN		{0, 255, 255, 255}
#define COLOR_ORANGE	{127, 31, 0, 255}

enum struct OpData_RocketJump {
	float vecDest[3];
	any aPadding[13];
}

ConVar g_hCVGravity;

#include "soldier/rocketjump/wallclimb.sp"
#include "soldier/rocketjump/groundshot_back.sp"
#include "soldier/rocketjump/groundshot_down.sp"

public Plugin myinfo = {
	name = "SMBL Soldier Actions Library: Rocket Jump",
	author = PLUGIN_AUTHOR,
	description = "Rocket jump movement operations for soldier bots",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

int g_iLaser;
int g_iHalo;

public void OnPluginStart() {
	g_hCVGravity = FindConVar("sv_gravity");
}

public void OnPluginEnd() {
	Operation.Deregister();
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "smbl")) {
		Setup_RocketJump();
	}
}

public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}

void Setup_RocketJump() {
	Operation.Register("Soldier.WallClimb", WallClimb_Init, _, _, _, UnsupportedFunction, _, WallClimb_Cleanup);

	Operation.Register("Soldier.GroundShot.Back", GroundShot_Back_Init);
	Operation.Register("Soldier.GroundShot.Down", GroundShot_Down_Init);

	// Auto dispatch wrapper
	Operation.Register("Soldier.RocketJump", RocketJump_Init, _, _, _, UnsupportedFunction, _, _, false, true);
}

// Operation callbacks

OpRet RocketJump_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_RocketJump eOpData) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("unsupported TFClassType");
	}

	int iFollowEntity;
	float fFollowDistance;
	float fFollowZOffset;

	if (hInitParams.JumpToKey("follow")) {
		hInitParams.GoBack();
		iFollowEntity = hInitParams.GetNum("follow");
		fFollowDistance = hInitParams.GetFloat("follow_distance", 0.0);
		fFollowZOffset = hInitParams.GetFloat("follow_zoffset", 0.0);

		if (!IsValidEntity(iFollowEntity)) {
			return mOp._Abort("invalid follow entity");
		}
	}

	if (!iFollowEntity && !hInitParams.JumpToKey("destination")) {
		return mOp._Abort("missing destination init parameter");
	}

	float vecDest[3];

	if (iFollowEntity) {
		Entity_GetAbsOrigin(iFollowEntity, vecDest);
	} else {
		hInitParams.GoBack();
		hInitParams.GetVector("destination", vecDest);
	}

	float vecOrigin[3];

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GoBack();
		hInitParams.GetVector("origin", vecOrigin);
	} else {
		float vecVel[3];
		Entity_GetAbsVelocity(iEntity, vecVel);
		// Wait until bot is stopped on ground before initializing
		if (!(GetEntityFlags(iEntity) & FL_ONGROUND) || GetVectorLength(vecVel) > 150.0) {
			return OpRet_Bypass;
		}

		Entity_GetAbsOrigin(mBot.iEntity, vecOrigin);
	}

	bool bStandingLaunch = hInitParams.GetNum("standing_launch", false) != 0;

	float fProximity = hInitParams.GetFloat("proximity", 0.0);
	bool bAirBrake = hInitParams.GetNum("airbrake", false) != 0;

	if (iFollowEntity) {
		float vecFollowVel[3];
		Entity_GetAbsVelocity(iFollowEntity, vecFollowVel);

		float vecPredictShift[3];
		vecPredictShift = vecFollowVel;
		vecPredictShift[2] = 0.0; // 2D shifts only
		ScaleVector(vecPredictShift, PREDICT_TIME);
		AddVectors(vecDest, vecPredictShift, vecDest);
	}

	float vecVector[3];
	SubtractVectors(vecDest, vecOrigin, vecVector);
	vecVector[2] = 0.0; // Only consider 2D distance
	NormalizeVector(vecVector, vecVector);

	ScaleVector(vecVector, iFollowEntity ? fFollowDistance : fProximity);
	SubtractVectors(vecDest, vecVector, vecDest);

	bool bHeightPriority = hInitParams.GetNum("height_priority", false) != 0;

	char sOpPriority[64], sOpBackup[64];
	if (bHeightPriority) {
		sOpPriority = "Soldier.GroundShot.Down";
		sOpBackup = "Soldier.GroundShot.Back";
	} else {
		sOpPriority = "Soldier.GroundShot.Back";
		sOpBackup = "Soldier.GroundShot.Down";
	}

	KeyValues hGroundShotInitParams;
	Operation mGroundShotOp = Operation.Instance(sOpPriority, hGroundShotInitParams);
	hGroundShotInitParams.SetVector("origin", vecOrigin);
	hGroundShotInitParams.SetVector("destination", vecDest);
	hGroundShotInitParams.SetNum("standing_launch", bStandingLaunch);

	if (mGroundShotOp.Init(mBot, true) == OpRet_Abort) {
		Operation.Destroy(mGroundShotOp);
		hGroundShotInitParams = null;

		mGroundShotOp = Operation.Instance(sOpBackup, hGroundShotInitParams);
		hGroundShotInitParams.SetVector("origin", vecOrigin);
		hGroundShotInitParams.SetVector("destination", vecDest);
		hGroundShotInitParams.SetNum("standing_launch", bStandingLaunch);

		if (mGroundShotOp.Init(mBot, true) == OpRet_Abort) {
			char sError[256];
			mGroundShotOp.GetError(sError, sizeof(sError));

			Operation.Destroy(mGroundShotOp);

			return mOp._Abort(sError);
		}
	}

	mOp.AddSubOperation(mGroundShotOp);

	KeyValues hAirStrafeInitParams;
	Operation mAirStrafeOp = Operation.Instance("Common.AirStrafe", hAirStrafeInitParams, view_as<Op>(1));
	hAirStrafeInitParams.SetFloat("proximity", 2*fProximity);

	if (bAirBrake) {
		hAirStrafeInitParams.SetNum("airbrake", true);
	} else {
		hAirStrafeInitParams.SetNum("flyby", true);
	}

	if (iFollowEntity) {
		hAirStrafeInitParams.SetNum("follow", iFollowEntity);
		hAirStrafeInitParams.SetFloat("follow_distance", fFollowDistance);
		hAirStrafeInitParams.SetFloat("follow_zoffset", fFollowZOffset);
	} else {
		hAirStrafeInitParams.SetVector("destination", vecDest);
	}

	hAirStrafeInitParams.SetNum("decelerate", true);

	mOp.AddSubOperation(mAirStrafeOp);

	return OpRet_Continue;
}

// Custom callbacks

public bool TraceEntityFilter_Environment(int iEntity, int iContentsMask) {
	return false;
}

// Helpers

void DrawDebugLine(float vecPos[3], float vecPos2[3], int iColor[4], float fLife=0.1) {
	TE_SetupBeamPoints(vecPos, vecPos2, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 1.0, 1, 0.0, iColor, 0);
	TE_SendToAll();
}

float NormalizeAngle(float fAngle) {
	if (fAngle < 0.0) {
		return fAngle + 360.0;
	} else if (fAngle > 360.0) {
		return fAngle - 360.0;
	}

	return fAngle;
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
