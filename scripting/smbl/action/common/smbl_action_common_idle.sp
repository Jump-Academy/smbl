#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smbl>
#include <smbl/nav_mesh>

#include <smlib/entities>
#include <smlib/math>

#define PID_FAST		{0.10,	0.001,	0.01}
#define PID_VSLOW_LAZY	{0.005,	0.001,	0.1}

#include "idle/lookaround.sp"
#include "idle/lookat.sp"

public Plugin myinfo = {
	name = "SMBL Common Bot Actions Library: Idle",
	author = PLUGIN_AUTHOR,
	description = "Idle operations for all bot classes",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

// Library forwards

public void SMBL_OnStart() {
	Operation.Register("Common.Idle.LookAround")
		.PreRun(Idle_LookAround_PreRun)
		.Loop(true);

	Operation.Register("Common.Idle.LookAt")
		.Init(Idle_LookAt_Init)
		.PreRun(Idle_LookAt_PreRun)
		.Loop(true);

// 	Operation.Register("Common.Idle.LookAttention")
// 		.Init(Idle_LookAround_Init)
// 		.PreRun(Idle_LookAround_PreRun)
// 		.Cleanup(Idle_LookAround_Cleanup)
// 		.Loop(true);
}

// Helpers

void ClipAngle(float &fValue, float fMin=-360.0, float fMax=360.0) {
	if (fValue < fMin) {
		fValue = fMin;
	} else if (fValue > fMax) {
		fValue = fMax;
	}
}

void NormalizeAngle(float &fAngle) {
	if (fAngle < 0.0) {
		fAngle += 360.0;
	} else if (fAngle > 360.0) {
		fAngle -= 360.0;
	}
}
