#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smlib/clients>
#include <smlib/entities>
#include <smlib/math>

#include <smbl>

#include "attack/shoot.sp"

public Plugin myinfo = {
	name = "SMBL Common Bot Actions Library: Attack",
	author = PLUGIN_AUTHOR,
	description = "Common attack operations for all bot classes",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

// Library forwards

public void SMBL_OnStart() {
	Operation.Register("Common.Attack.Shoot")
		.Init(Shoot_Init)
		.Validate(Shoot_Validate)
		.PreRun(Shoot_PreRun)
		.Cleanup(Shoot_Cleanup)
		.Loop(true);
}


// Custom callbacks

public bool TraceEntityFilter_IgnoreTeam(int iEntity, int iContentsMask, int iTeam) {
	// TODO: Non-client bot teams
	return SMBL_GetEntityBot(iEntity) && GetClientTeam(iEntity) != iTeam;
}

// Helpers

void GetViewerPos(int iEntity, float vecViewerPos[3]) {
	float vecMins[3], vecMaxs[3], vecSize[3];

	if (1 <= iEntity < MaxClients) {
		GetClientEyePosition(iEntity, vecViewerPos);
	} else {
		// TODO: Custom bot viewer position
		Entity_GetAbsOrigin(iEntity, vecViewerPos);

		Entity_GetMinSize(iEntity, vecMins);
		Entity_GetMaxSize(iEntity, vecMaxs);

		// Midpoint
		SubtractVectors(vecMaxs, vecMins, vecSize);
		ScaleVector(vecSize, 0.5);
		AddVectors(vecViewerPos, vecSize, vecViewerPos);
	}
}

void GetEntityMidpoint(int iEntity, float vecMidpoint[3]) {
	float vecMins[3], vecMaxs[3];

	Entity_GetAbsOrigin(iEntity, vecMidpoint);

	Entity_GetMinSize(iEntity, vecMins);
	Entity_GetMaxSize(iEntity, vecMaxs);

	vecMidpoint[2] += 0.5*(vecMaxs[2]-vecMins[2]);
}
