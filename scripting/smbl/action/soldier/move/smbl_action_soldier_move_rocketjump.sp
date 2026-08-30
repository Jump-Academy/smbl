#pragma semicolon 1

// #define DEBUG

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

#define COLOR_RED		{255, 0, 0, 255}
#define COLOR_YELLOW	{255, 255, 0, 255}
#define COLOR_MAGENTA	{255, 0, 255, 255}

#define DEFAULT_GOAL_PROXIMITY	50.0
#define CLOSE_RANGE_CUTOFF		300.0
#define MIN_START_SPEED			239.0

#define SOLDIER_MIN_BBOX	{-24.0, -24.0, 0.0}
#define SOLDIER_MAX_BBOX	{24.0, 24.0, 82.0}

// Approximates
#define WALK_TIME				0.1350
#define LAUNCHER_AIM_TIME		0.0045
#define ROCKET_BLAST_TIME		0.0600
#define GROUND_START_TIME		WALK_TIME + LAUNCHER_AIM_TIME + ROCKET_BLAST_TIME

enum struct OpData_RocketJump {
	float vecDest[3];
	float vecLastPos[3];
	any aPadding[10];
}

ConVar g_hCVGravity;

#include "rocketjump/wall_climb.sp"
#include "rocketjump/wall_climb_adjacent.sp"
#include "rocketjump/ground_shot.sp"
#include "rocketjump/ground_shot_back.sp"
#include "rocketjump/ground_shot_down.sp"

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

	SMBL_NotifyOnStart();
}

public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}

// Library forwards

public void SMBL_OnStart() {
	Operation.Register("Soldier.Move.RocketJump.Wall.Climb")
		.Init(Wall_Climb_Init)
		.Suspend(UnsupportedFunction)
		.Cleanup(Wall_Climb_Cleanup);

	Operation.Register("Soldier.Move.RocketJump.Wall.Climb.Adjacent")
		.Init(Wall_Climb_Adjacent_Init)
		.Suspend(UnsupportedFunction)
		.Cleanup(Wall_Climb_Adjacent_Cleanup);

	// Auto dispatch wrapper
	Operation.Register("Soldier.Move.RocketJump.Ground.Shot")
		.Init(Ground_Shot_Init)
#if defined DEBUG
		.PostRun(Ground_Shot_PostRun)
#endif
		.Suspend(UnsupportedFunction)
		.SubOps(true);

	Operation.Register("Soldier.Move.RocketJump.Ground.Shot.Back")
		.Init(Ground_Shot_Back_Init);

	Operation.Register("Soldier.Move.RocketJump.Ground.Shot.Down")
		.Init(Ground_Shot_Down_Init);
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

float GetMaxHeight(int iEntity, float fInitialZSpeed) {
	float fEntityGravityRatio = GetEntityGravity(iEntity);
	if (fEntityGravityRatio == 0.0) {
		fEntityGravityRatio = 1.0;
	}

	float fGravity = -g_hCVGravity.FloatValue * fEntityGravityRatio;

	/*
	 * Kinematic equations
	 * 
	 * vf = v0 + g*t
	 * ->    0 = v0 + g*t   (vf=0 at peak)
	 * -> -g*t = v0
	 * ->    t = -v0 / g
	 *
	 * d = v0*t + 0.5*g*t^2
	*/
	float fTime = -fInitialZSpeed / fGravity;

	return fInitialZSpeed*fTime + 0.5*fGravity*fTime*fTime;
}
