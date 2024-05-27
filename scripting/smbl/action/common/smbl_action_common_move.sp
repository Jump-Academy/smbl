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
#define NODE_MIN_REACH	50.0

#define PROBE_MIN		{5.0, 5.0, 5.0}
#define PROBE_MAX		{5.0, 5.0, 5.0}

#define PID_DEFAULT		{0.20,	0.001,	0.65}
#define PID_SLOW_LAZY	{0.05,	0.001,	0.01}
#define PID_FAST		{0.10,	0.001,	0.01}
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

#if defined DEBUG
int g_iLaser;
int g_iHalo;
#endif

#include "common/move/walk.sp"
#include "common/move/walkfollow.sp"

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
	Operation.Deregister();
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "smbl")) {
		Setup_Move();
	}
}

#if defined DEBUG
public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}
#endif

// Custom callbacks

public float CostFunc_WalkDrop(NavNode mNodeA, int iEdgeA, NavNode mNodeB, int iEdgeB, int iAttachmentFlags, float vecPosA[3], float vecPosB[3], bool bHeuristic) {
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

void Setup_Move() {
	Operation.Register("Common.Walk", Walk_Init, Walk_Validate, _, _, Walk_Suspend, Walk_Resume, Walk_Cleanup);
	Operation.Register("Common.Walk.Follow", WalkFollow_Init, WalkFollow_Validate, WalkFollow_PreRun, _, _, _, _, true, true, false, false);
}

#if defined DEBUG
void DrawDebugLine(float vecPos[3], float vecPos2[3], int iColor[4], float fLife=0.1) {
	TE_SetupBeamPoints(vecPos, vecPos2, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 1.0, 1, 0.0, iColor, 0);
	TE_SendToAll();
}
#endif
