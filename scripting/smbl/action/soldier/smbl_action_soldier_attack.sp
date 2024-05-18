#pragma semicolon 1

// #define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smlib/entities>
#include <smlib/effects>
#include <smlib/math>

#include <smbl>
#include <smbl/nav_mesh>

#define PID_FAST		{0.10,	0.001,	0.01}

#define COLOR_RED		{255, 0, 0, 255}

ConVar g_hCVGravity;

#include "soldier/attack/marketgarden.sp"

enum struct OpData_MarketGarden {
	int iTargetEntRef;
	any aPadding[15];
}

int g_iLaser;
int g_iHalo;


public Plugin myinfo = {
	name = "SMBL Soldier Actions Library: Attack",
	author = PLUGIN_AUTHOR,
	description = "Attack operations for soldier bots",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	g_hCVGravity = FindConVar("sv_gravity");

	HookEvent("rocket_jump", Event_RocketJump, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
}

public void OnPluginEnd() {
	Operation.Deregister();
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "smbl")) {
		Setup_Attacks();
	}
}

public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}

void Setup_Attacks() {
	Operation.Register("Soldier.MarketGarden.Swing", MarketGarden_Swing_Init);

	// Auto dispatch wrapper
	//Operation.Register("Soldier.MarketGarden", MarketGarden_Init, _, _, _, UnsupportedFunction, _, MarketGarden_Swing_Cleanup, false, true, true, false);
	Operation.Register("Soldier.MarketGarden", MarketGarden_Init, _, _, _, UnsupportedFunction, _, MarketGarden_Swing_Cleanup, false, true, true);

	// Internal use
	Operation.AddEventListener("Soldier.MarketGarden", ".player_death", OpEventFwd_CheckTargetDeath);
	Operation.AddEventListener("Soldier.MarketGarden.Swing", ".rocket_jump", OpEventFwd_DetectRocketJump);
	Operation.AddEventListener("Soldier.MarketGarden.Swing", ".rocket_jump_completed", OpEventFwd_RocketJumpCompleted);
}

// Operation callbacks

OpRet MarketGarden_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_MarketGarden eOpData) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("unsupported TFClassType");
	}

	if (!hInitParams.JumpToKey("target")) {
		return mOp._Abort("missing target init parameter");
	}

	hInitParams.GoBack();
	int iTargetEntity = hInitParams.GetNum("target");

	if (!IsValidEntity(iTargetEntity)) {
		return mOp._Abort("invalid target entity");
	}

	eOpData.iTargetEntRef = EntRefToEntIndex(iTargetEntity);

// 	float vecTargetPos[3];
// 	Entity_GetAbsOrigin(iTargetEntity, vecTargetPos);

// 	float vecPos[3];
// 	Entity_GetAbsOrigin(mBot.iEntity, vecPos);

// 	float vecVector[3];
// 	SubtractVectors(vecTargetPos, vecPos, vecVector);
// 	NormalizeVector(vecVector, vecVector);

// 	ScaleVector(vecVector, -30.0);

// 	float vecLandingPos[3];
// 	AddVectors(vecTargetPos, vecVector, vecLandingPos);

	float fTimestamp = GetEngineTime();

	KeyValues hRocketJumpInitParams;
	Operation mRocketJumpOp = Operation.Instance("Soldier.RocketJump", hRocketJumpInitParams);
// 	hRocketJumpInitParams.SetVector("destination", vecLandingPos);
	hRocketJumpInitParams.SetNum("follow", iTargetEntity);
	hRocketJumpInitParams.SetFloat("proximity", 36.0);
// 	hRocketJumpInitParams.SetNum("airbrake", true);

	if (mRocketJumpOp.Init(mBot) == OpRet_Abort) {
		char sError[256];
		mRocketJumpOp.GetError(sError, sizeof(sError));

		Operation.Destroy(mRocketJumpOp);

		PrintToServer("MG rocket jump init failed after %.3f ms", 1000*(GetEngineTime()-fTimestamp));

		return mOp._Abort(sError);
	}

	PrintToServer("MG rocket jump init completed in %.3f ms", 1000*(GetEngineTime()-fTimestamp));

	mRocketJumpOp.AddStateChangeForward(OpStateChangeFwd_RocketJumpLaunched);

	mOp.AddSubOperation(mRocketJumpOp);

// 	int iPrimaryWeaponEntityIdx = GetPlayerWeaponSlot(iEntity, TFWeaponSlot_Primary);
// 	SetEntPropEnt(iEntity, Prop_Send, "m_hActiveWeapon", iPrimaryWeaponEntityIdx);

	KeyValues hMarketGardenSwingInitParams;
	Operation mMarketGardenSwingOp = Operation.Instance("Soldier.MarketGarden.Swing", hMarketGardenSwingInitParams);
	hMarketGardenSwingInitParams.SetNum("target", iTargetEntity);

	// Init and assign bot on same tick to prevent race conditions where rocket jump operation aborts before on-demand init
	mMarketGardenSwingOp.Init(mBot);

	mOp.AddSubOperation(mMarketGardenSwingOp);

// 	DrawDebugLine(vecPos, vecLandingPos, COLOR_RED, 5.0);

	return OpRet_Continue;
}

// Custom callbacks

public Action Event_PlayerDeath(Event hEvent, const char[] sName, bool bDontBroadcast) {
	Operation.DispatchEvent("Soldier.MarketGarden", ".player_death", hEvent.GetInt("victim_entindex"));
	return Plugin_Continue;
}

public Action Event_RocketJump(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	Operation.DispatchEvent("Soldier.MarketGarden.Swing", ".rocket_jump", iClient);
	return Plugin_Continue;
}

public void OpEventFwd_CheckTargetDeath(Bot mBot, Operation mOp, OpData_MarketGarden eOpData, any aData) {
	if (aData == EntRefToEntIndex(eOpData.iTargetEntRef)) {
		mOp.Abort(true);
	}
}

public void OpEventFwd_RocketJumpCompleted(Bot mBot, Operation mOp, OpData_MarketGarden_Swing eOpData, any aData) {
	if (aData == mBot && !eOpData.bAirborne) {
		// Concurrent market gardening operation never proceeded (missed .rocket_jump event due to misaimed or unexploded rocket)
		mOp.Abort();
	}
}

public void OpEventFwd_DetectRocketJump(Bot mBot, Operation mOp, OpData_MarketGarden_Swing eOpData, any aData) {
	if (aData == mBot.iEntity) {
		eOpData.bAirborne = true;
	}
}

public void OpStateChangeFwd_RocketJumpLaunched(Bot mBot, Operation mOp, OpState iOpState) {
	if (iOpState == OpState_Complete) {
		Operation.DispatchEvent("Soldier.MarketGarden.Swing", ".rocket_jump_completed", mBot);
	}
}

// Helpers

stock void DrawDebugLine(float vecPos[3], float vecPos2[3], int iColor[4], float fLife=0.1) {
	TE_SetupBeamPoints(vecPos, vecPos2, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 1.0, 1, 0.0, iColor, 0);
	TE_SendToAll();
}
