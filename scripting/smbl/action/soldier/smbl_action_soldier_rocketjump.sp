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

#define PID_SLOW_LAZY	{0.05,	0.001,	0.01}
#define PID_FAST		{0.1,	0.001,	0.01}
#define PID_FAST_PREC	{0.1,	0.000,	0.00}

#define COLOR_WHITE		view_as<int>({255, 255, 255, 255})
#define COLOR_RED		view_as<int>({255, 0, 0, 255})
#define COLOR_GREEN		view_as<int>({0, 255, 0, 255})
#define COLOR_BLUE		view_as<int>({0, 0, 255, 255})
#define COLOR_YELLOW	view_as<int>({255, 255, 0, 255})
#define COLOR_MAGENTA	view_as<int>({255, 0, 255, 255})
#define COLOR_CYAN		view_as<int>({0, 255, 255, 255})

#include "soldier/rocketjump/wallclimb.sp"

enum struct OpData {
	float vecDest[3];
	float vecWallAng[3];
	float vecWallNormalYaw;
	float vecWallNormal[3];
	any aPadding[6];
}

enum struct SeqData {
	float vecDest[3];
	any aPadding[13];
}

public Plugin myinfo = {
	name = "SMBL Soldier Actions Library: Rocket Jump",
	author = PLUGIN_AUTHOR,
	description = "Rocket jump movement operations for soldier bots",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

int g_iLaser;
int g_iHalo;

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
}

OpRet UnsupportedFunction(Bot mBot, Operation mOp, OpData eOpData) {
	return OpRet_Abort;
}

// Custom callbacks

public bool TraceEntityFilter_Environment(int iEntity, int iContentsMask) {
	return false;
}

// Helpers

stock void DrawPath(ArrayList hPath, int iStart=0) {
	for (int i=0; i<iStart && i<hPath.Length-1; i++) {
		PathData ePathDataA;
		PathData ePathDataB;
		hPath.GetArray(i, ePathDataA);
		hPath.GetArray(i+1, ePathDataB);

		DrawDebugLine(ePathDataA.vecFocalPoint, ePathDataB.vecFocalPoint, COLOR_WHITE, 0.1);
	}

	for (int i=iStart; i<hPath.Length-1; i++) {
		PathData ePathDataA;
		PathData ePathDataB;
		hPath.GetArray(i, ePathDataA);
		hPath.GetArray(i+1, ePathDataB);

		if (ePathDataA.iPathMode == PathMode_Bypass) {
			DrawDebugLine(ePathDataA.vecFocalPoint, ePathDataB.vecFocalPoint, COLOR_CYAN, 0.1);
		} else {
			int iColor[4];

			switch (i%5) {
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
			}

			DrawDebugLine(ePathDataA.vecFocalPoint, ePathDataB.vecFocalPoint, iColor, 0.1);
		}
	}
}

stock void DrawDebugLine(float vecPos[3], float vecPos2[3], int iColor[4], float fLife=0.1) {
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
