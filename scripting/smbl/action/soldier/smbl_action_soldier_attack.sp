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

#define MARKET_GARDEN_MIN_DISTANCE	85.0
#define STANDING_LAUNCH_RANGE		300.0

ConVar g_hCVGravity;

#include "attack/marketgarden.sp"

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

	SMBL_NotifyOnStart();
}

public void SMBL_OnStart() {
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

OpRet MarketGarden_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_MarketGarden eOpData, bool bConfigureOnly) {
	int iEntity;

	if (!bConfigureOnly) {
		iEntity = mBot.iEntity;

		if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
			return mOp._Abort("unsupported TFClassType");
		}
	}

	if (!hInitParams.JumpToKey("target")) {
		return mOp._Abort("missing target init parameter");
	}

	hInitParams.GoBack();
	int iTargetEntity = hInitParams.GetNum("target");

	if (!IsValidEntity(iTargetEntity)) {
		return mOp._Abort("invalid target entity");
	}

	PrintToServer("MG target is %N", iTargetEntity);

	eOpData.iTargetEntRef = EntRefToEntIndex(iTargetEntity);

	float vecOrigin[3];

	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GetVector(NULL_STRING, vecOrigin);
		hInitParams.GoBack();
	} else if (bConfigureOnly) {
		return mOp._Abort("missing origin init parameter");
	} else {
		Entity_GetAbsOrigin(iEntity, vecOrigin);
	}

	float vecTargetPos[3];
	Entity_GetAbsOrigin(iTargetEntity, vecTargetPos);

	PrintToServer("origin: [%.1f, %.1f, %.1f]\ttarget: [%.1f, %.1f, %.1f", vecOrigin[0], vecOrigin[1], vecOrigin[2], vecTargetPos[0], vecTargetPos[1], vecTargetPos[2]);

	float vecDiff[3];
	SubtractVectors(vecTargetPos, vecOrigin, vecDiff);

	float fDist2D = SquareRoot(vecDiff[0]*vecDiff[0] + vecDiff[1]*vecDiff[1]);

	if (fDist2D < MARKET_GARDEN_MIN_DISTANCE) {
		return mOp._Abort("target is too close");
	}

	float vecMaxs[3];
	Entity_GetMaxSize(iEntity, vecMaxs);

	bool bStandingLaunch = fDist2D < STANDING_LAUNCH_RANGE;

	float fFollowZOffset = bStandingLaunch ? 0.25*vecMaxs[2] : 1.2*vecMaxs[2];

	KeyValues hTestInitParams = new KeyValues(OP_INIT_PARAM);
	hTestInitParams.SetVector("origin", vecOrigin);
	hTestInitParams.SetVector("destination", vecTargetPos);
	hTestInitParams.SetNum("follow", iTargetEntity);
	hTestInitParams.SetFloat("follow_distance", 25.0);
	hTestInitParams.SetFloat("follow_zoffset", fFollowZOffset);
	hTestInitParams.SetNum("standing_launch", bStandingLaunch);
	hTestInitParams.SetFloat("proximity", 15.0);

	if (!bStandingLaunch) {
		hTestInitParams.SetNum("decelerate", true);
		hTestInitParams.SetNum("airbrake", true);
	}

	if (!Operation.Configure("Soldier.RocketJump", hTestInitParams)) {
		delete hTestInitParams;
		PrintToServer("target not reachable with rocket jump");
		return mOp._Abort("target not reachable with rocket jump");
	}

	if (bConfigureOnly) {
		return OpRet_Continue;
	}

	KeyValues hRocketJumpInitParams;
	Operation mRocketJumpOp = Operation.Instance("Soldier.RocketJump", hRocketJumpInitParams);

	hRocketJumpInitParams.Import(hTestInitParams);
	delete hTestInitParams;

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
	// Ignore damage by world and other non-client entities
	if (1 <= iAttacker <= MaxClients) {
		Bot mBot = SMBL_GetClientBot(iAttacker);
		if (mBot) {
			int iData = (iVictim << 16) | view_as<int>(mBot);
			Operation.DispatchEvent("Soldier.MarketGarden", ".target_damage", iData);
		}
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
