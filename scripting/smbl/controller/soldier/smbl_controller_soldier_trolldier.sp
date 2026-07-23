#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#define CONTROLLER_ALIAS "Soldier.Trolldier"

#include <smbl>
#include <smbl/nav_mesh>

public Plugin myinfo = {
	name = "SMBL Controller - Soldier",
	author = PLUGIN_AUTHOR,
	description = "Trolldier bot controller for soldier",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

// Library forwards

public void SMBL_OnStart() {
	Controller.Register(CONTROLLER_ALIAS, ContrInitFunc_Trolldier_Init, TFClass_Soldier);
}

// Controller callbacks

public void ContrInitFunc_Trolldier_Init(Controller mContr) {
	mContr.AddMonitor("TargetAcquisition.FOV").Start();

	mContr.AddAction("Soldier.Move3D", 			ActionType_Move);
	mContr.AddAction("Soldier.MarketGarden",	ActionType_Attack);

	NavMesh mGroundNavMesh = SMBL_GetNavMesh("Ground");

// 	mContr.AddProcess("Process.Combat.Proximity", ProcessPriority_High);
	mContr.AddProcess("Process.Combat.Attack", ProcessPriority_High);
	
	KeyValues hChaseInitParams;
	mContr.AddProcess("Process.Combat.Chase", ProcessPriority_High, hChaseInitParams);
	hChaseInitParams.SetNum("nav_mesh", view_as<int>(mGroundNavMesh));


	mContr.AddProcess("Process.Investigate.Touch", ProcessPriority_AboveNormal);
	mContr.AddProcess("Process.Investigate.Damage", ProcessPriority_AboveNormal);

	KeyValues hIdleRoamInitParams;
	mContr.AddProcess("Process.Idle.Roam3D", ProcessPriority_BelowNormal, hIdleRoamInitParams);
	hIdleRoamInitParams.SetNum("nav_mesh", view_as<int>(mGroundNavMesh));

	mContr.AddProcess("Process.Idle.LookAround", ProcessPriority_Low);
}
