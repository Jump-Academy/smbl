#if defined _smbl_included
	#endinput
#endif
#define _smbl_included

#include <tf2>
#include <tf2_stocks>

#include <smbl/bot>
#include <smbl/operation>

public SharedPlugin __pl_smbl = 
{
	name = "smbl",
	file = "smbl.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_smbl_SetNTVOptional() {
	__MarkBotNativesAsOptional();
	__MarkOperationNativesAsOptional();
}
#endif

enum DirectorPriority {
	DirectorPriority_Low,
	DirectorPriority_Medium,
	DirectorPriority_High,
	DirectorPriority_GameMode,
	DirectorPriority_Admin
}

enum DirectorAction {
	DirectorAction_Continue,
	DirectorAction_Handled
}

typedef DirectorThinkFunc = function void ();

typedef ControllerThinkFunc = function void (Bot mBot);
typedef ControllerMoveFunc = function void (Bot mBot, float vecPos[3]);
typedef ControllerEncounterFunc = function void (Bot mBot, int iOther);
typedef ControllerAttackFunc = function void (Bot mBot, int iTarget);

native void SMBL_RegisterDirector(char[] sIdentifier, DirectorPriority iDirectorPriority, DirectorThinkFunc fnThink);
native bool SMBL_DeregisterDirector(char[] sIdentifier=NULL_STRING);

/**
 * Returns whether the bot library is ready to accept registrations.
 * @return True if ready, false if setting up or shutting down
 */
native bool SMBL_IsReady();

/**
 * Request the bot library to notify the plugin it is ready to accept registrations via a call to SMBL_OnStart().
 * Use this to request a call to the forward if this plugin is late loaded, such as in OnPluginStart().
 * Calling this in OnPluginStart() will not cause a duplicate call to the SMBL_OnStart() forward.
 */
native void SMBL_NotifyOnStart();

/**
 * Returns whether the bot library is ready to accept registrations.
 * @return True if ready, false if setting up or shutting down
 */
native bool SMBL_IsReady();

/**
 * Request the bot library to notify the plugin it is ready to accept registrations via a call to SMBL_OnStart().
 * Use this to request a call to the forward if this plugin is late loaded, such as in OnPluginStart().
 * Calling this in OnPluginStart() will not cause a duplicate call to the SMBL_OnStart() forward.
 */
native void SMBL_NotifyOnStart();

native int SMBL_GetBots(ArrayList hBots=null);
native Bot SMBL_GetClientBot(int iClient);
native Bot SMBL_GetEntityBot(int iEntity);

/**
 * Called when the bot library is ready to accept registrations.
 * This is normally called automatically after OnAllPluginsLoaded() but plugins can request a call
 * via SMBL_NotifyOnStart() in case of late-loading.
 */
forward void SMBL_OnStart();

forward void SMBL_OnBotAdd(Bot mBot);
forward void SMBL_OnBotRemove(Bot mBot);
