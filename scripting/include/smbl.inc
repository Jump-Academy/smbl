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

native void SMBL_RegisterController(char[] sIdentifier, TFClassType iClass, ControllerThinkFunc fnThink, ControllerMoveFunc fnMove, ControllerEncounterFunc fnEncounter, ControllerAttackFunc fnAttack);
native bool SMBL_DeregisterController(char[] sIdentifier=NULL_STRING, TFClassType iClass=TFClass_Unknown);

native int SMBL_GetBots(ArrayList hBots=null);
native Bot SMBL_GetClientBot(int iClient);

forward void SMBL_OnBotAdd(Bot mBot);
forward void SMBL_OnBotRemove(Bot mBot);
