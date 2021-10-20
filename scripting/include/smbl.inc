#if defined _SMBL_included
	#endinput
#endif
#define _SMBL_included

#include <tf2>
#include <tf2_stocks>

#include <smbl/bot>
#include <smbl/operation>
#include <smbl/nav_mesh>

public SharedPlugin __pl_smbl = 
{
	name = "SMBL",
	file = "smbl.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_SMBL_SetNTVOptional() {
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


// methodmap Controller {
// 	property Handle hPlugin {
// 		public native get();
// 	}

// 	public native void Think(Bot mBot);
// 	public native void Move(Bot mBot, float vecPos[3]);
// 	public native void Encounter(Bot mBot, int iOther);
// 	public native void Attack(Bot mBot, int iTarget);
// }

typedef DirectorThinkFunc = function void ();

typedef ControllerThinkFunc = function void (Bot mBot);
typedef ControllerMoveFunc = function void (Bot mBot, float vecPos[3]);
typedef ControllerEncounterFunc = function void (Bot mBot, int iOther);
typedef ControllerAttackFunc = function void (Bot mBot, int iTarget);

native bool SMBL_RegisterNavMesh(char[] sIdentifier, NavMesh mNavMesh);
native bool SMBL_DeregisterNavMesh(char[] sIdentifier, bool bDestroy=false);
native void SMBL_DeregisterAllNavMeshes(bool bDestroy=false);
native NavMesh SMBL_GetNavMesh(char[] sIdentifier);

native void SMBL_RegisterDirector(char[] sIdentifier, DirectorPriority iDirectorPriority, DirectorThinkFunc fnThink);
native bool SMBL_DeregisterDirector(char[] sIdentifier=NULL_STRING);

native void SMBL_RegisterController(char[] sIdentifier, TFClassType iClass, ControllerThinkFunc fnThink, ControllerMoveFunc fnMove, ControllerEncounterFunc fnEncounter, ControllerAttackFunc fnAttack);
native bool SMBL_DeregisterController(char[] sIdentifier=NULL_STRING, TFClassType iClass=TFClass_Unknown);

native int SMBL_GetBots(ArrayList hBots);
native Bot SMBL_GetBotClient(int iClient);

native void SMBL_AttachController(Bot mBot, char[] sController);
native bool SMBL_DetachController(Bot mBot);

native void SMBL_RegisterOperation(char[] sIdentifier, OpInitFunc fnInit=INVALID_FUNCTION, OpValidateFunc fnValidate=INVALID_FUNCTION, OpFunc fnPreRun=INVALID_FUNCTION, OpFunc fnPostRun=INVALID_FUNCTION, CleanupFunc fnCleanup=INVALID_FUNCTION, bool bLoop=false, bool bHasSubOps=false, bool bConcurrent=false, bool bCascadeAborts=true);
native bool SMBL_DeregisterOperation(char[] sIdentifier=NULL_STRING);
native Operation SMBL_NewOperation(char[] sIdentifier, any aInitialData[16]=0, Operation mOpParent=NULL_OPERATION);

forward void SMBL_OnBotAdd(Bot mBot);
forward void SMBL_OnBotRemove(Bot mBot);
