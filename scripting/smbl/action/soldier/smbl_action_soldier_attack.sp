#pragma semicolon 1

// #define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <sourcemod>
#include <sdkhooks>

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

void Setup_Attacks() {
	Operation.Register("Soldier.MarketGarden.Swing", MarketGarden_Swing_Init, _, _, _, UnsupportedFunction, _, MarketGarden_Swing_Cleanup);

	// Auto dispatch wrapper
	Operation.Register("Soldier.MarketGarden", MarketGarden_Init, _, _, _, UnsupportedFunction, _, MarketGarden_Cleanup, false, true, true);

	// Internal use
	Operation.AddEventListener("Soldier.MarketGarden", ".player_death", OpEventFwd_CheckTargetDeath);
	Operation.AddEventListener("Soldier.MarketGarden", ".target_damage", OpEventFwd_CheckTargetDamage);
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

	float vecTargetPos[3];
	Entity_GetAbsOrigin(iTargetEntity, vecTargetPos);

	float vecTargetEyePos[3];
	GetClientEyePosition(iTargetEntity, vecTargetEyePos);

	float vecMaxs[3];
	Entity_GetMaxSize(iEntity, vecMaxs);

	float fTimestamp = GetEngineTime();

	KeyValues hRocketJumpInitParams;
	Operation mRocketJumpOp = Operation.Instance("Soldier.RocketJump", hRocketJumpInitParams);
	hRocketJumpInitParams.SetNum("follow", iTargetEntity);
	hRocketJumpInitParams.SetFloat("follow_distance", 25.0);
	hRocketJumpInitParams.SetFloat("follow_zoffset", 1.2*vecMaxs[2]);
	hRocketJumpInitParams.SetFloat("proximity", 15.0);
	hRocketJumpInitParams.SetNum("decelerate", true);
	hRocketJumpInitParams.SetNum("airbrake", true);

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

	KeyValues hMarketGardenSwingInitParams;
	Operation mMarketGardenSwingOp = Operation.Instance("Soldier.MarketGarden.Swing", hMarketGardenSwingInitParams);
	hMarketGardenSwingInitParams.SetNum("target", iTargetEntity);

	// Init and assign bot on same tick to prevent race conditions where rocket jump operation aborts before on-demand init
	mMarketGardenSwingOp.Init(mBot);

	mOp.AddSubOperation(mMarketGardenSwingOp);

	SDKHook(iTargetEntity, SDKHook_OnTakeDamagePost, SDKHookCB_OnTakeDamagePost_Target);

	return OpRet_Continue;
}

void MarketGarden_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_MarketGarden_Swing eOpData) {
	int iTargetEntity = EntRefToEntIndex(eOpData.iTargetEntRef);
	if (IsValidEntity(iTargetEntity)) {
		SDKUnhook(iTargetEntity, SDKHook_OnTakeDamagePost, SDKHookCB_OnTakeDamagePost_Target);
	}
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

public void SDKHookCB_OnTakeDamagePost_Target(int iVictim, int iAttacker, int iInflictor, float fDamage, int iDamageType) {
	Bot mBot = SMBL_GetClientBot(iAttacker);
	if (mBot) {
		int iData = (iVictim << 16) | view_as<int>(mBot);
		Operation.DispatchEvent("Soldier.MarketGarden", ".target_damage", iData);
	}
}

public void OpEventFwd_CheckTargetDeath(Bot mBot, Operation mOp, OpData_MarketGarden eOpData, any aData) {
	if (aData == EntRefToEntIndex(eOpData.iTargetEntRef)) {
		mOp.Abort(true);
	}
}

public void OpEventFwd_CheckTargetDamage(Bot mBot, Operation mOp, OpData_MarketGarden eOpData, any aData) {
	Bot mAttackerBot = view_as<Bot>(aData & 0xFFFF);
	int iVictim = aData >>> 16;
	if (mAttackerBot == mBot && iVictim == EntRefToEntIndex(eOpData.iTargetEntRef)) {
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
