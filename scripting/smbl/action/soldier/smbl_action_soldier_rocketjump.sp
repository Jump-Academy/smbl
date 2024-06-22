#pragma semicolon 1

// #define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smlib/entities>
#include <smlib/math>

#include <smbl>

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

#define DEFAULT_GOAL_PROXIMITY	50.0
#define CLOSE_RANGE_CUTOFF		300.0
#define MIN_START_SPEED			239.0

// Approximates
#define WALK_TIME				0.1350
#define LAUNCHER_AIM_TIME		0.0045
#define ROCKET_BLAST_TIME		0.0600
#define GROUND_START_TIME		WALK_TIME + LAUNCHER_AIM_TIME + ROCKET_BLAST_TIME

enum RocketJumpType {
	RocketJumpType_Groundshot_Back,
	RocketJumpType_Groundshot_Down
}

char g_sRocketJumpIdentifiers[][] = {
	"Soldier.GroundShot.Back",
	"Soldier.GroundShot.Down"
};

enum struct OpData_RocketJump {
	float vecDest[3];
	float vecLastPos[3];
	any aPadding[10];
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

	Operation.Register(g_sRocketJumpIdentifiers[RocketJumpType_Groundshot_Back], GroundShot_Back_Init);
	Operation.Register(g_sRocketJumpIdentifiers[RocketJumpType_Groundshot_Down], GroundShot_Down_Init);

	// Auto dispatch wrapper
#if defined DEBUG
	Operation.Register("Soldier.RocketJump", RocketJump_Init, _, _, RocketJump_PostRun, UnsupportedFunction, _, _, false, true);
#else
	Operation.Register("Soldier.RocketJump", RocketJump_Init, _, _, _, UnsupportedFunction, _, _, false, true);
#endif
}

// Operation callbacks

OpRet RocketJump_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_RocketJump eOpData, bool bConfigureOnly) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("unsupported TFClassType");
	}

	int iFollowEntity;
	float fFollowDistance;
	float fFollowZOffset;

	if (hInitParams.JumpToKey("follow")) {
		iFollowEntity = hInitParams.GetNum(NULL_STRING);
		hInitParams.GoBack();
		fFollowDistance = hInitParams.GetFloat("follow_distance", 0.0);
		fFollowZOffset = hInitParams.GetFloat("follow_zoffset", 0.0);

		if (!IsValidEntity(iFollowEntity)) {
			return mOp._Abort("invalid follow entity");
		}
	}

	float vecDest[3];

	if (!hInitParams.JumpToKey("destination")) {
		if (!iFollowEntity) {
			return mOp._Abort("missing destination init parameter");
		}
	} else {
		hInitParams.GetVector(NULL_STRING, vecDest);
		hInitParams.GoBack();
	}

	float vecOrigin[3];

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GetVector(NULL_STRING, vecOrigin);
		hInitParams.GoBack();
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

	float fGoalProximity = hInitParams.GetFloat("goal_proximity", DEFAULT_GOAL_PROXIMITY);
	bool bAirBrake = hInitParams.GetNum("airbrake", false) != 0;

	if (iFollowEntity) {
		float vecFollowVel[3];
		Entity_GetAbsVelocity(iFollowEntity, vecFollowVel);

		float vecPredictShift[3];
		vecPredictShift = vecFollowVel;
		vecPredictShift[2] = 0.0; // 2D shifts only
		ScaleVector(vecPredictShift, PREDICT_TIME);
		AddVectors(vecDest, vecPredictShift, vecDest);

		if (fFollowDistance > 0.0) {
			float vecVector[3];
			SubtractVectors(vecDest, vecOrigin, vecVector);
			vecVector[2] = 0.0; // Only consider 2D distance
			NormalizeVector(vecVector, vecVector);

			ScaleVector(vecVector, fFollowDistance);
			SubtractVectors(vecDest, vecVector, vecDest);
		}
	}

	bool bHeightPriority = hInitParams.GetNum("height_priority", false) != 0;

	bool bConfigured = !bConfigureOnly && hInitParams.JumpToKey(OP_INIT_CONFIG);
	if (bConfigured) {
		char sIdentifier[64];
		hInitParams.GetString("rocketjump_identifier", sIdentifier, sizeof(sIdentifier));

		if (!sIdentifier[0]) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing rocketjump_identifier config parameter");
		}

		if (!hInitParams.JumpToKey("rocketjump_params")) {
			hInitParams.GoBack(); // from OP_INIT_CONFIG
			return mOp._Abort("missing rocketjump_params config parameter");
		}

		// Must use real-time origin to calculate updated heading
		Entity_GetAbsOrigin(iEntity, vecOrigin);

		float vecDiff[3];
		SubtractVectors(vecDest, vecOrigin, vecDiff);

		NormalizeVector(vecDiff, vecDiff);

		float vecAng[3];
		GetVectorAngles(vecDiff, vecAng);

		KeyValues hGroundShotInitParams;
		Operation mGroundShotOp = Operation.Instance(sIdentifier, hGroundShotInitParams);

		hGroundShotInitParams.SetVector("origin", vecOrigin);
		hGroundShotInitParams.SetVector("destination", vecDest);

		hGroundShotInitParams.JumpToKey(OP_INIT_CONFIG, true);
		hGroundShotInitParams.SetFloat("heading", vecAng[1]);

		if (StrEqual(sIdentifier, g_sRocketJumpIdentifiers[RocketJumpType_Groundshot_Down])) {
			hGroundShotInitParams.SetFloat("start_speed", hInitParams.GetFloat("start_speed"));
			hGroundShotInitParams.SetFloat("shot_delay", hInitParams.GetFloat("shot_delay"));
		} else if (StrEqual(sIdentifier, g_sRocketJumpIdentifiers[RocketJumpType_Groundshot_Back])) {
			hGroundShotInitParams.SetFloat("yaw", hInitParams.GetFloat("yaw"));
			hGroundShotInitParams.SetFloat("pitch", hInitParams.GetFloat("pitch"));
			hGroundShotInitParams.SetNum("standing_launch", hInitParams.GetNum("standing_launch"));
		}

		hGroundShotInitParams.GoBack(); // from OP_INIT_CONFIG

		hInitParams.GoBack(); // from rocketjump_params
		hInitParams.GoBack(); // from OP_INIT_CONFIG

		mOp.AddSubOperation(mGroundShotOp);
	} else {
		RocketJumpType iPriortyRocketJumpType, iBackupRocketJumpType;

		if (bHeightPriority) {
			iPriortyRocketJumpType = RocketJumpType_Groundshot_Down;
			iBackupRocketJumpType = RocketJumpType_Groundshot_Back;
		} else {
			iPriortyRocketJumpType = RocketJumpType_Groundshot_Back;
			iBackupRocketJumpType = RocketJumpType_Groundshot_Down;
		}

		KeyValues hGroundShotInitParams = new KeyValues(OP_INIT_PARAM);
		hGroundShotInitParams.SetVector("origin", vecOrigin);
		hGroundShotInitParams.SetVector("destination", vecDest);
		hGroundShotInitParams.SetNum("standing_launch", bStandingLaunch);

		RocketJumpType iRocketJumpType;

		if (!Operation.Configure(g_sRocketJumpIdentifiers[iPriortyRocketJumpType], hGroundShotInitParams, mBot)) {
			if (!Operation.Configure(g_sRocketJumpIdentifiers[iBackupRocketJumpType], hGroundShotInitParams, mBot)) {
				delete hGroundShotInitParams;
				return mOp._Abort("destination not reachable");
			}

			iRocketJumpType = iBackupRocketJumpType;
		} else {
			iRocketJumpType = iPriortyRocketJumpType;
		}

		hInitParams.JumpToKey(OP_INIT_CONFIG, true);
		hInitParams.SetString("rocketjump_identifier", g_sRocketJumpIdentifiers[iRocketJumpType]);
		hInitParams.JumpToKey("rocketjump_params", true);

		hGroundShotInitParams.JumpToKey(OP_INIT_CONFIG);

		switch (iRocketJumpType) {
			case RocketJumpType_Groundshot_Down: {
				hInitParams.SetFloat("start_speed", hGroundShotInitParams.GetFloat("start_speed"));
				hInitParams.SetFloat("shot_delay", hGroundShotInitParams.GetFloat("shot_delay"));
			}
			case RocketJumpType_Groundshot_Back: {
				hInitParams.SetFloat("yaw", hGroundShotInitParams.GetFloat("yaw"));
				hInitParams.SetFloat("pitch", hGroundShotInitParams.GetFloat("pitch"));
				hInitParams.SetNum("standing_launch", hGroundShotInitParams.GetNum("standing_launch"));
			}
		}

		hGroundShotInitParams.GoBack(); // from OP_INIT_CONFIG

		hInitParams.GoBack(); // from rocketjump_params
		hInitParams.GoBack(); // from OP_INIT_CONFIG

		if (!bConfigureOnly) {
			KeyValues hRocketJumpInitParams;
			Operation mGroundShotOp = Operation.Instance(g_sRocketJumpIdentifiers[iRocketJumpType], hRocketJumpInitParams);
			hRocketJumpInitParams.Import(hGroundShotInitParams);
			mOp.AddSubOperation(mGroundShotOp);
		}

		delete hGroundShotInitParams;
	}

	if (bConfigureOnly) {
		return OpRet_Continue;
	}

	KeyValues hAirStrafeInitParams;
	Operation mAirStrafeOp = Operation.Instance("Common.AirStrafe", hAirStrafeInitParams, view_as<Op>(1));
	hAirStrafeInitParams.SetFloat("goal_proximity", fGoalProximity);

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

	Entity_GetAbsOrigin(mBot.iEntity, eOpData.vecLastPos);

	return OpRet_Continue;
}

#if defined DEBUG
public OpRet RocketJump_PostRun(Bot mBot, Operation mOp, OpData_RocketJump eOpData) {
	float vecPos[3];
	Entity_GetAbsOrigin(mBot.iEntity, vecPos);

	DrawDebugLine(eOpData.vecLastPos, vecPos, COLOR_BLUE, 5.0);

	eOpData.vecLastPos = vecPos;

	return OpRet_Continue;
}
#endif

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

bool CheckParabolicCollision(float vecMins[3], float vecMaxs[3], float vecDir[3], float fGravity, float fTime, float vecStartPos[3], float fVel2D, float fVelZ, bool bDrawArc=false, float fDrawTime=5.0) {
	float vecLastPt[3];
	vecLastPt = vecStartPos;

	for (float fT=0.1; fT<=fTime; fT+=0.15) {
		float vecPt[3];
		vecPt[0] = vecStartPos[0] + vecDir[0]*fT*fVel2D;
		vecPt[1] = vecStartPos[1] + vecDir[1]*fT*fVel2D;
		vecPt[2] = vecStartPos[2] + fVelZ*fT + 0.5*fGravity*fT*fT;

		if (TR_PointOutsideWorld(vecPt)) {
			if (bDrawArc) {
				DrawDebugLine(vecLastPt, vecPt, COLOR_RED, 5.0);
			}

			return true;
		}

		TR_TraceHullFilter(vecLastPt, vecPt, vecMins, vecMaxs, MASK_SHOT_HULL, TraceEntityFilter_Environment);
		if (TR_DidHit()) {
			if (bDrawArc) {
				DrawDebugLine(vecLastPt, vecPt, COLOR_MAGENTA, fDrawTime);
			}

			return true;
		}

		if (bDrawArc) {
			DrawDebugLine(vecLastPt, vecPt, COLOR_YELLOW, fDrawTime);
		}

		vecLastPt = vecPt;
	}

	return false;
}

void ShiftGroundPosition2D(float vecStartPos[3], float vecDir[3], float fSpeed, float fTime, float vecEndPos[3]) {
	float fMoveDist = fSpeed*fTime;
	vecEndPos[0] = vecStartPos[0] + fMoveDist*vecDir[0];
	vecEndPos[1] = vecStartPos[1] + fMoveDist*vecDir[1];
	vecEndPos[2] = vecStartPos[2];
}
