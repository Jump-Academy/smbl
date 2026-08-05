#pragma semicolon 1

// #define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smlib/entities>
#include <smlib/effects>
#include <smlib/math>

#include <smbl>
#include <smbl/nav_mesh>

#define NODE_PROXIMITY	500.0

#define DEFAULT_GOAL_PROXIMITY			50.0

#define PROBE_MIN		{5.0, 5.0, 5.0}
#define PROBE_MAX		{5.0, 5.0, 5.0}

#define PID_DEFAULT		{0.20,	0.001,	0.65}
#define PID_SLOW_LAZY	{0.05,	0.001,	0.01}
#define PID_FAST		{0.10,	0.001,	0.01}
#define PID_FAST_PREC	{0.10,	0.000,	0.00}
#define PID_SNAP		{1.00,	0.000,	0.00}

#define COLOR_WHITE		{255, 255, 255, 255}
#define COLOR_GRAY		{ 10,  10,  10, 255}
#define COLOR_PALECYAN	{  0,  10,  10, 255}

#define COLOR_RED		{255,   0,   0, 255}
#define COLOR_YELLOW	{255, 255,   0, 255}
#define COLOR_GREEN		{  0, 255,   0, 255}
#define COLOR_CYAN		{  0, 255, 255, 255}
#define COLOR_BLUE		{  0,   0, 255, 255}
#define COLOR_MAGENTA	{255,   0, 255, 255}

ConVar g_hCVGravity;

#if defined DEBUG
int g_iLaser;
int g_iHalo;
#endif

#include "move/airstrafe.sp"
#include "move/walk.sp"
#include "move/walk_beeline.sp"
#include "move/walkfollow.sp"

public Plugin myinfo = {
	name = "SMBL Common Bot Actions Library: Move",
	author = PLUGIN_AUTHOR,
	description = "Common movement operations for all bot classes",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	g_hCVGravity = FindConVar("sv_gravity");

	SMBL_NotifyOnStart();
}

#if defined DEBUG
public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}
#endif

// Library forwards

public void SMBL_OnStart() {
	Operation.Register("Common.Move.AirStrafe")
		.Init(AirStrafe_Init)
		.Validate(AirStrafe_Validate);

	Operation.Register("Common.Move.Walk")
		.Init(Walk_Init)
		.Validate(Walk_Validate)
		.Suspend(Walk_Suspend)
		.Resume(Walk_Resume)
		.Cleanup(Walk_Cleanup);

	Operation.Register("Common.Move.Walk.Beeline")
		.Init(Walk_Beeline_Init)
		.Validate(Walk_Beeline_Validate);

	Operation.Register("Common.Move.Walk.Follow")
		.Init(Walk_Follow_Init)
		.Validate(Walk_Follow_Validate)
		.PreRun(Walk_Follow_PreRun)
		.Loop(true)
		.SubOps(true)
		.CascadeAborts(false);
}

// Custom callbacks

public float CostFunc_WalkDrop(NavMesh mNavMesh, NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bNodeAStart, bool bNodeBGoal, bool bHeuristic) {
	if (iAttachmentFlags & (FL_ATTACH_GROUND | FL_ATTACH_DROP) || bHeuristic) {
		return GetVectorDistance(vecPosA, vecPosB);
	}

	return POSITIVE_INFINITY;
}

public bool TraceEntityFilter_IgnoreTeam(int iEntity, int iContentsMask, TFTeam iTeam) {
	if (1 <= iEntity <= MaxClients) {
		return TF2_GetClientTeam(iEntity) != iTeam;
	}

	return true;
}

// Helpers

float GetVectorDistance2D(const float vecA[3], const float vecB[3]) {
	float fDelta0 = vecB[0] - vecA[0];
	float fDelta1 = vecB[1] - vecA[1];

	return SquareRoot(fDelta0*fDelta0 + fDelta1*fDelta1);
}

float GetAirTime(int iEntity, float fInitialZSpeed, float fZDistance) {
	float fEntityGravityRatio = GetEntityGravity(iEntity);
	if (fEntityGravityRatio == 0.0) {
		fEntityGravityRatio = 1.0;
	}

	float fGravity = -g_hCVGravity.FloatValue * fEntityGravityRatio;

	/*
	 * Kinematic equation
	 *
	 * dz = v0*t + (0.5*g)*t^2
	 * -> (0.5*g)*t^2 + v0*t - dz = 0
	 *       a           b      c
	 *
	 * Quadratic formula
	 *
	 * t = (-b ± sqrt(b^2 - 4*a*c)) / (2*a)
	 * -> t = (-v0 ± sqrt(v0^2 - 4*(0.5*g)*(-dz))) / (2*(0.5*g))
	 * -> t = (-v0 ± sqrt(v0^2 + 2*g*dz)) / g
	 *
	 * t must be larger of the two solutions due to being on the far end of the parabolic arc
	 */
	float fDiscriminant = fInitialZSpeed*fInitialZSpeed + 2*fGravity*fZDistance;

	// Unreachable since destination is above parabola
	if (fDiscriminant < 0) {
		return 0.0;
	}

	float fSqrtDiscriminant = SquareRoot(fDiscriminant);

	float fAirTimeA = (-fInitialZSpeed + fSqrtDiscriminant) / fGravity;
	float fAirTimeB = (-fInitialZSpeed - fSqrtDiscriminant) / fGravity;

	return fAirTimeA >= fAirTimeB ? fAirTimeA : fAirTimeB;
}

#if defined DEBUG
void DrawDebugLine(float vecPos[3], float vecPos2[3], int iColor[4], float fLife=0.1) {
	TE_SetupBeamPoints(vecPos, vecPos2, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 1.0, 1, 0.0, iColor, 0);
	TE_SendToAll();
}

void DrawDebugMarker(float vecPos[3], int iColor[4], float fLife=0.1) {
	float vecMarker[3];
	vecMarker = vecPos;
	vecMarker[2] += 100.0;
	DrawDebugLine(vecPos, vecMarker, iColor, fLife);
}

void DrawDebugRing(float vecPos[3], float fRadius, int iColor[4], float fLife=0.1) {
	TE_SetupBeamRingPoint(vecPos, fRadius-5.0, fRadius, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 0.0, iColor, 0, 0);
	TE_SendToAll();
}
#endif
