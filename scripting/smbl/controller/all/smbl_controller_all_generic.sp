#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#define CONTROLLER_ALIAS "Generic"

#include <smbl>
#include <smbl/controller>
#include <smbl/nav_mesh>

public Plugin myinfo = {
	name = "SMBL Controller - All-class Generic",
	author = PLUGIN_AUTHOR,
	description = "Generical bot controller for any class",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

// Library forwards

public void SMBL_OnStart() {
	for (TFClassType i=TFClass_Scout; i<=TFClass_Engineer; i++) {
		Controller.Register(CONTROLLER_ALIAS, ContrInitFunc_Generic_Init, i);
	}
}

// Controller callbacks

public void ContrInitFunc_Generic_Init(Controller mContr) {
	mContr.AddMonitor("TargetAcquisition.FOV").Start();

// 	mContr.AddProcess(Operation.Instance("Process.Combat.Attack"), ProcessPriority_AboveNormal);

	mContr.AddAction("Common.Walk", ActionType_Move);

	NavMesh mGroundNavMesh = SMBL_GetNavMesh("Ground");

	KeyValues hIdleRoamInitParams;
	mContr.AddProcess("Process.Idle.Roam", ProcessPriority_BelowNormal, hIdleRoamInitParams);
	hIdleRoamInitParams.SetNum("nav_mesh", view_as<int>(mGroundNavMesh));

	mContr.AddProcess("Process.Idle.LookAround", ProcessPriority_Low);
}
