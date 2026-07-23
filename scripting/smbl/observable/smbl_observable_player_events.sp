#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <sourcemod>

#include <smbl>
#include <smbl/observable>

char g_sPlayerEvents[][] = {
	//"player_abandoned_match",
	//"player_account_changed",
	"player_askedforball",
// 	"player_bonuspoints",				// custom entindex
	"player_buff",
	"player_builtobject",
	//"player_buyback",
	"player_calledformedic",
	"player_carryobject",
	"player_changeclass",
	"player_chargedeployed",
	//"player_currency_changed",
	//"player_damage_dodged",			// incomplete info
	//"player_damaged",					// incomplete info
	"player_death",
	"player_destroyed_pipebomb",
	//"player_directhit_stun",			// custom entindex
	//"player_domination", 				// custom userid
	"player_dropobject",
	//"player_escort_score",			// custom
	//"player_extinguished",			// custom entindex
	//"player_healed",					// custom
	//"player_healedbymedic",			// incomplete info
	"player_healedmediccall",
	//"player_healonhit",				// incomplete info
	//"player_highfive_cancel",			// custom entindex
	//"player_highfive_start",			// custom entindex
	//"player_highfive_success",		// custom entindex
	"player_hurt",
	//"player_ignited",					// custom entindex
	//"player_ignited_inv",				// custom entindex
	//"player_initial_spawn",			// custom entindex
	"player_invulned",
	//"player_jarated",					// custom entindex
	//"player_jarated_fade",			// custom entindex
	//"player_killed_achievement_zone", // custom entindex
	//"player_mvp",
	//"player_next_map_vote_change",
	//"player_pinned",					// custom
	//"player_regenerate",				// ?
	//"player_rematch_change",			// ?
	//"player_rocketpack_pushed",		// custom userid
	"player_sapped_object",
// 	"player_score_changed", 			// custom
// 	"player_shield_blocked",			// custom entindex
	"player_spawn",
// 	"player_stats_updated",				// ?
// 	"player_stealsandvich",				// custom
// 	"player_stunned",					// custom
	"player_teleported",
	"player_turned_to_ghost",
// 	"player_upgraded",					// ?
	"player_upgradedobject",
// 	"player_used_powerup_bottle"		// custom

// 	"arrow_impact"						// custom
// 	"capper_killed",					// custom entindex
	"christmas_gift_grab",
// 	"crossbow_heal",					// custom userid

// 	"building_healed"					// custom
// 	"damage_prevented",					// custom
// 	"deadringer_cheat_death",			// custom userid
// 	"environmental_death",				// custom
// 	"halloween_boss_killed",			// custom
	"item_pickup",
// 	"killed_capping_player"				// custom entindex
// 	"landed"							// ?
	"medic_death",
	"medic_defended",
// 	"spy_pda_reset"						// ?
// 	"npc_hurt",							// custom entindex
	"object_deflected",
	"object_destroyed",
	"object_detonated",
	"object_removed",
// 	"parachute_deploy",					// custom entindex
// 	"parachute_holster",				// custom entindex
// 	"projectile_direct_hit",			// custom entindex
// 	"projectile_removed",				// ?
// 	"revive_player_notify",				// custom entindex
// 	"revive_player_stopped",			// custom entindex
// 	"revive_player_complete",			// custom entindex
	"rocket_jump",
	"rocket_jump_landed",
// 	"sentry_on_go_active"				// indirect builder entindex
	"sticky_jump",
	"sticky_jump_landed",
// 	"tagged_player_as_it",				// custom userid
	"rocketpack_launch",
	"rocketpack_landed",
};

bool g_bEventsHooked;

public Plugin myinfo = {
	name = "SMBL Observable Library: Events",
	author = PLUGIN_AUTHOR,
	description = "Player state observeables for controllers",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	//HookEvent("player_death", Event_PlayerDeath);
	//HookEvent("player_hurt", Event_PlayerHurt);
	//HookEvent("player_spawn", Event_PlayerSpawn);

	SMBL_NotifyOnStart();
}

// Library callbacks

public void SMBL_OnStart() {
	//Observable.Register("Event.player_death");
	//Observable.Register("Event.player_hurt");
	//Observable.Register("Event.player_spawn");
	for (int i=0; i<sizeof(g_sPlayerEvents); i++) {
		Observable.RegisterEvent(g_sPlayerEvents[i]);

		if (!g_bEventsHooked) {
			HookEvent(g_sPlayerEvents[i], Event_DispatchFromUserId);
		}
	}

	g_bEventsHooked = true;
}

// Custom callbacks
public Action Event_DispatchFromUserId(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	Observable.DispatchEvent(iClient, sName, hEvent).Send();

	return Plugin_Continue;
}
/*
public Action Event_PlayerDeath(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	Observable.Dispatch(iClient, "Event.player_death").Send();

	return Plugin_Continue;
}

public Action Event_PlayerHurt(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	
	KeyValues hObsData;
	Dispatcher mDispatcher = Observable.Dispatch(iClient, "Event.Player_Hurt", hObsData);
	if (mDispatcher) {
		mDispatcher.ImportFromEvent(hEvent,
			{
				KvData_Int,KvData_Int,KvData_Int,KvData_Int,KvData_String,
				KvData_Int,KvData_Int,KvData_Int,KvData_Int,KvData_String,
				KvData_Int,KvData_Int,KvData_Int,KvData_Int,KvData_String,
				KvData_Int,KvData_Int,KvData_Int,KvData_Int,KvData_Int,
				KvData_Int,KvData_Int,KvData_Int,KvData_Int,KvData_Int,
				KvData_Int
			},
			"userid,victim_entindex,inflictor_entindex,attacker,weapon,"...
			"weaponid,damagebits,customkill,assister,weapon_logclassname,"...
			"stun_flags,death_flags,silent_kill,playerpenetratecount,assister_fallback,"...
			"kill_streak_total,kill_streak_wep,kill_streak_assist,kill_streak_victim,ducks_streaked,"...
			"duck_streak_total,duck_streak_assist,duck_streak_victim,rocket_jump,weapon_def_index,"...
			"crit_type,",
			26
		);
// 		hObsData.SetNum("attacker", hEvent.GetInt("attacker"));
// 		hObsData.SetNum("damageamount", hEvent.GetInt("damageamount"));
		mDispatcher.Send();
	}

	Observable.DispatchEvent(iClient, "Event.player_hurt", hEvent).Send();

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	KeyValues hObsData;
	Dispatcher mDispatcher = Observable.Dispatch(iClient, "Event.player_spawn", hObsData);
	if (mDispatcher) {
		hObsData.SetNum("team", hEvent.GetInt("team"));
		hObsData.SetNum("class", hEvent.GetInt("class"));

		float vecPos[3], vecAng[3];
		GetClientAbsOrigin(iClient, vecPos);
		GetClientAbsAngles(iClient, vecAng);

		hObsData.SetVector("origin", vecPos);
		hObsData.SetVector("angles", vecAng);

		mDispatcher.Send();
	}

	return Plugin_Continue;
}
*/