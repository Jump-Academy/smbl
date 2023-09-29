#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#define DIRECTOR_ALIAS "Debugger"

#include <smlib/clients>
#include <smlib/strings>

#include <smbl>

#define MANUAL_OPERATION	"Director.Debug.Manual"

enum struct Debugger {
	bool bEnabled;
	Operation mOperation;
	char sTargetParam[64];
	int iTargets[MAXPLAYERS];
	int iTargetCount;
	int iLastBotObsTarget;
}

Debugger g_eDebugger[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "SMBL Debug Director",
	author = PLUGIN_AUTHOR,
	description = "Bot director for debugging and manual bot control",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("smbl_director_debug_version", PLUGIN_VERSION, "SMBL debug director version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	RegAdminCmd("smbl_debug", cmdDebug, ADMFLAG_ROOT, "Show SMBL debug menu");

	RegAdminCmd("smbl_debug_new", cmdNew, ADMFLAG_ROOT, "Create new operation");
	RegAdminCmd("smbl_debug_set", cmdSetCell, ADMFLAG_ROOT, "Set cell parameter");
	RegAdminCmd("smbl_debug_setaim", cmdSetAim, ADMFLAG_ROOT, "Set aim parameter");
	RegAdminCmd("smbl_debug_setmesh", cmdSetMesh, ADMFLAG_ROOT, "Set mesh parameter");
	RegAdminCmd("smbl_debug_settarget", cmdSetTarget, ADMFLAG_ROOT, "Set target parameter");
	RegAdminCmd("smbl_debug_start", cmdStart, ADMFLAG_ROOT, "Start operation");
	RegAdminCmd("smbl_debug_startchain", cmdStartChain, ADMFLAG_ROOT, "Start chained operations");
	RegAdminCmd("smbl_debug_stop", cmdStop, ADMFLAG_ROOT, "Stop operation");

	RegAdminCmd("smbl_debug_goto", cmdGoTo, ADMFLAG_ROOT, "Set bot movement destination");

	HookEvent("player_spawn", Event_PlayerReset, EventHookMode_Post);
	HookEvent("player_changeclass", Event_PlayerReset, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerReset, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerReset, EventHookMode_Post);

	LoadTranslations("common.phrases.txt");
}

public void OnPluginEnd() {
	SMBL_DeregisterDirector();
	Operation.Deregister();
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "smbl")) {
		SMBL_RegisterDirector(DIRECTOR_ALIAS, DirectorPriority_Admin, Director_Think);
		Operation.Register(MANUAL_OPERATION, INVALID_FUNCTION, INVALID_FUNCTION, INVALID_FUNCTION, INVALID_FUNCTION, INVALID_FUNCTION, INVALID_FUNCTION, INVALID_FUNCTION, false, true, false, true);
	}
}

public void OnAllPluginsLoaded() {
}

public void OnMapEnd() {
	for (int i=1; i<=MaxClients; i++ ) {
		ResetClient(i);
	}
}

public void OnClientDisconnect(int iClient) {
	ResetClient(iClient);
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float vecVel[3], float vecAng[3], int &iWeapon) {
	if (!IsFakeClient(iClient) || GetGameTickCount() % 15 != 0) {
		return Plugin_Continue;
	}

	Bot mBot = SMBL_GetClientBot(iClient);
	if (!mBot) {
		return Plugin_Continue;
	}

	static int iDebuggers[MAXPLAYERS];
	int iDebuggerCount = GetDebuggers(iDebuggers);
	if (!iDebuggerCount) {
		return Plugin_Continue;
	}

	float vecPos[3];
	float vecVelAbs[3];

	GetClientAbsOrigin(iClient, vecPos);
	Entity_GetAbsVelocity(iClient, vecVelAbs);

	Panel hDebugPanel;

	char sBuffer[512];

	for (int i=0; i<iDebuggerCount; i++) {
		int iObsTarget = Client_GetObserverTarget(iDebuggers[i]);
		if (iClient == iObsTarget) {
			g_eDebugger[iDebuggers[i]].iLastBotObsTarget = iObsTarget;

			if (!hDebugPanel) {
				hDebugPanel = new Panel();

				FormatEx(sBuffer, sizeof(sBuffer), "%N :: Operations ― ", iClient);
				int iTitleLength = strlen(sBuffer);

				Operation mMainOperation = mBot.mMainOperation;
				if (!mBot.mMainOperation) {
					PrintToServer("%N has no main operation!", mBot.iEntity);
					continue;
				}

				int iLongestWidth;
				int iLines = PrintCallChain(mMainOperation, true, sBuffer[iTitleLength], sizeof(sBuffer)-iTitleLength, iLongestWidth);

				hDebugPanel.DrawText(sBuffer);

				for (int j=iLines; j<8; j++) {
					hDebugPanel.DrawText(" ");
				}

				hDebugPanel.DrawText(" ");

				hDebugPanel.CurrentKey = 10;
				hDebugPanel.DrawItem("Close", ITEMDRAW_CONTROL);
			}

			hDebugPanel.Send(iDebuggers[i], MenuHandler_Debug, 1);
		}
	}

	delete hDebugPanel;

	return Plugin_Continue;
}

// Library callbacks

public void SMBL_OnBotAdd(Bot mBot) {
	int iDebuggers[MAXPLAYERS];
	int iDebuggerCount = GetDebuggers(iDebuggers);

	for (int i=0; i<iDebuggerCount; i++) {
		int iObsTarget = Client_GetObserverTarget(iDebuggers[i]);
		Bot mObsBot = SMBL_GetClientBot(iObsTarget);

		// If debugger was previously spectating a bot that got removed, spectate the new bot instead
		if (iObsTarget == g_eDebugger[iDebuggers[i]].iLastBotObsTarget && !mObsBot) {
			Client_SetObserverTarget(iDebuggers[i], mBot.iEntity);
		}
	}
}

// Custom callbacks

public void Director_Think() {
// 	PrintToServer("Debug Director: Think");
}

public bool TraceEntityFilter_Environment(int iEntity, int iContentsMask) {
	return false;
}

public void Callback_Operation_StateChange(Bot mBot, Operation mOp, OpState iOpState) {
	if (iOpState != OpState_Complete) {
		return;
	}

	static int iDebuggers[MAXPLAYERS];
	int iDebuggerCount = GetDebuggers(iDebuggers);
	if (!iDebuggerCount) {
		return;
	}

	char sIdentifier[64];
	mOp.GetIdentifier(sIdentifier, sizeof(sIdentifier));

	int iClientBot = mBot.iEntity;
	int iUID = mOp.iUID;

	for (int i=0; i<iDebuggerCount; i++) {
		int iObsTarget = Client_GetObserverTarget(iDebuggers[i]);
		if (iClientBot == iObsTarget) {
			PrintToChat(iDebuggers[i], "[smbl] %N: %s:%d completed", iClientBot, sIdentifier, iUID);
		}
	}
}

public void Callback_Operation_Aborted(Bot mBot, Operation mOp, char[] sError) {
	static int iDebuggers[MAXPLAYERS];
	int iDebuggerCount = GetDebuggers(iDebuggers);
	if (!iDebuggerCount) {
		return;
	}

	int iClientBot = mBot.iEntity;

	for (int i=0; i<iDebuggerCount; i++) {
		int iObsTarget = Client_GetObserverTarget(iDebuggers[i]);
		if (iClientBot == iObsTarget) {
			PrintToChat(iDebuggers[i], "[smbl] %N: %s", iClientBot, sError);
		}
	}
}

public Action Event_PlayerReset(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	Bot mBot = SMBL_GetClientBot(iClient);
	if (!mBot) {
		return Plugin_Continue;
	}

	Operation mManualOp = FindManualOp(mBot);
	if (mManualOp) {
		ArrayList hSubOpRefs = mManualOp.hSubOpRefs;
		for (int i=0; i<hSubOpRefs.Length; i++) {
			Operation mSubOp = view_as<OpRef>(hSubOpRefs.Get(i)).ToOperation();
			mSubOp.Abort();
		}
	}

	return Plugin_Continue;
}

// Commands

public Action cmdDebug(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[smbl] This command cannot be run from server console.");
		return Plugin_Handled;
	}

	if (iArgC == 1) {
		char sArg1[32];
		GetCmdArg(1, sArg1, sizeof(sArg1));

		int iTarget;
		if ((iTarget = FindTarget(iClient, sArg1)) != -1 && IsFakeClient(iTarget) && SMBL_GetClientBot(iTarget)) {
			Client_SetObserverTarget(iClient, iTarget);
			g_eDebugger[iClient].bEnabled = true;
		}
	} else {
		if (g_eDebugger[iClient].bEnabled) {
			ResetClient(iClient);
			g_eDebugger[iClient].bEnabled = false;
		} else {
			for (int i=1; i<=MaxClients; i++) {
				if (IsClientInGame(i) && IsFakeClient(i) && SMBL_GetClientBot(i)) {
					Client_SetObserverTarget(iClient, i);
					g_eDebugger[iClient].bEnabled = true;
					break;
				}
			}
		}
	}

	ReplyToCommand(iClient, "[smbl] Debugger %s", g_eDebugger[iClient].bEnabled ? "enabled" : "disabled");

	return Plugin_Handled;
}

public Action cmdNew(int iClient, int iArgC) {
	if (iArgC < 1) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_new <operation identifier>");
		return Plugin_Handled;
	}

	char sOperationIdentifier[128];
	GetCmdArg(1, sOperationIdentifier, sizeof(sOperationIdentifier));

	Operation.Destroy(g_eDebugger[iClient].mOperation);
	g_eDebugger[iClient].mOperation = Operation.Instance(sOperationIdentifier);

	if (!g_eDebugger[iClient].mOperation) {
		ReplyToCommand(iClient, "[smbl] Failed to instantiate operation: %s", sOperationIdentifier);
	}

	return Plugin_Handled;
}

public Action cmdSetCell(int iClient, int iArgC) {
	if (iArgC < 2) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_set <name> <value>");
		return Plugin_Handled;
	}

	if (!g_eDebugger[iClient].mOperation) {
		ReplyToCommand(iClient, "[smbl] New operation required");
		return Plugin_Handled;
	}

	char sArg1[32], sArg2[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	GetCmdArg(2, sArg2, sizeof(sArg2));

	KeyValues hInitParams = g_eDebugger[iClient].mOperation.hInitParams;
	hInitParams.SetNum(sArg1, StringToInt(sArg2));

	return Plugin_Handled;
}

public Action cmdSetAim(int iClient, int iArgC) {
	if (iArgC < 1) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_setaim <name>");
		return Plugin_Handled;
	}

	if (!g_eDebugger[iClient].mOperation) {
		ReplyToCommand(iClient, "[smbl] New operation required");
		return Plugin_Handled;
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	float vecPos[3], vecAng[3];
	GetClientEyePosition(iClient, vecPos);
	GetClientEyeAngles(iClient, vecAng);

	float vecAimPos[3];
	GetTraceEndpoint(vecPos, vecAng, vecAimPos);

	KeyValues hInitParams = g_eDebugger[iClient].mOperation.hInitParams;
	hInitParams.SetVector(sArg1, vecAimPos);

	return Plugin_Handled;
}

public Action cmdSetMesh(int iClient, int iArgC) {
	if (iArgC < 2) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_setmesh <name> <mesh name>");
		return Plugin_Handled;
	}

	if (!g_eDebugger[iClient].mOperation) {
		ReplyToCommand(iClient, "[smbl] New operation required");
		return Plugin_Handled;
	}

	char sArg1[32], sArg2[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	GetCmdArg(2, sArg2, sizeof(sArg2));

	NavMesh mNavMesh = SMBL_GetNavMesh(sArg2);
	if (!mNavMesh) {
		ReplyToCommand(iClient, "[smbl] Invalid nav mesh: %s", sArg2);
		return Plugin_Handled;
	}

	KeyValues hInitParams = g_eDebugger[iClient].mOperation.hInitParams;
	hInitParams.SetNum(sArg1, view_as<int>(mNavMesh));

	return Plugin_Handled;
}

public Action cmdSetTarget(int iClient, int iArgC) {
	if (iArgC < 2) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_settarget <name> <target>");
		return Plugin_Handled;
	}

	if (!g_eDebugger[iClient].mOperation) {
		ReplyToCommand(iClient, "[smbl] New operation required");
		return Plugin_Handled;
	}

	char sArg1[32], sArg2[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	GetCmdArg(2, sArg2, sizeof(sArg2));

	char sTargetName[MAX_TARGET_LENGTH];
	bool bTnIsML;

	if ((g_eDebugger[iClient].iTargetCount = ProcessTargetString(
			sArg2,
			iClient,
			g_eDebugger[iClient].iTargets,
			MAXPLAYERS,
			COMMAND_FILTER_CONNECTED,
			sTargetName,
			sizeof(sTargetName),
			bTnIsML)) <= 0) {
		ReplyToTargetError(iClient, g_eDebugger[iClient].iTargetCount);
		return Plugin_Handled;
	}

	PrintToServer("Targetting %s on %d clients", sArg1, g_eDebugger[iClient].iTargetCount);

	g_eDebugger[iClient].sTargetParam = sArg1;

	KeyValues hInitParams = g_eDebugger[iClient].mOperation.hInitParams;
	hInitParams.SetNum(sArg1, g_eDebugger[iClient].iTargets[0]);

	return Plugin_Handled;
}

public Action cmdStart(int iClient, int iArgC) {
	if (iArgC < 1) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_start <bot target> [append]");
		return Plugin_Handled;
	}

	if (!g_eDebugger[iClient].mOperation) {
		ReplyToCommand(iClient, "[smbl] New operation required");
		return Plugin_Handled;
	}

	bool bAppend;
	if (iArgC == 2) {
		char sArg2[8];
		GetCmdArg(2, sArg2, sizeof(sArg2));
		bAppend = StringToInt(sArg2) != 0;
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	char sTargetName[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool bTnIsML;

	if ((iTargetCount = ProcessTargetString(
			sArg1,
			iClient,
			iTargetList,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			sTargetName,
			sizeof(sTargetName),
			bTnIsML)) <= 0) {
		ReplyToTargetError(iClient, iTargetCount);
		return Plugin_Handled;
	}

	int iBotsCount;
	for (int i=0; i<iTargetCount; i++) {
		Bot mBot = SMBL_GetClientBot(iTargetList[i]);
		if (!mBot) {
			ReplyToCommand(iClient, "[smbl] %N is not a BOT.", iTargetList[i]);
			continue;
		}

		Operation mManualOp = FindManualOp(mBot);

		if (!mManualOp) {
			mManualOp = Operation.Instance(MANUAL_OPERATION);

			mBot.mMainOperation.AddSubOperation(mManualOp, 0);
		}

		Operation mOp = iBotsCount++ ? g_eDebugger[iClient].mOperation.Clone() : g_eDebugger[iClient].mOperation;

		mOp.AddStateChangeForward(Callback_Operation_StateChange);
		mOp.AddAbortForward(Callback_Operation_Aborted);

		ArrayList hSubOpRefs = mManualOp.hSubOpRefs;
		Op iOp;
		if (bAppend) {
			if (hSubOpRefs.Length) {
				OpRef mLastOpRef = hSubOpRefs.Get(hSubOpRefs.Length-1);
				Operation mLastOp = mLastOpRef.ToOperation();
				if (mLastOp.IsValid()) {
					iOp = view_as<Op>(view_as<int>(mLastOp.iOp)+1);
				}
			}
		} else {
			mManualOp.ClearSubOperations();
		}

		mOp.iOp = iOp;
		mManualOp.AddSubOperation(mOp);

		char sOperation[128];
		mOp.GetIdentifier(sOperation, sizeof(sOperation));
		ReplyToCommand(iClient, "[smbl] %N: %s:%d added", mBot.iEntity, sOperation, mOp.iUID);
	}

	g_eDebugger[iClient].mOperation = NULL_OPERATION;

	return Plugin_Handled;
}

public Action cmdStartChain(int iClient, int iArgC) {
	if (iArgC < 1) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_startchain <bot target> [append]");
		return Plugin_Handled;
	}

	if (!g_eDebugger[iClient].mOperation) {
		ReplyToCommand(iClient, "[smbl] New operation required");
		return Plugin_Handled;
	}

	bool bAppend;
	if (iArgC == 2) {
		char sArg2[8];
		GetCmdArg(2, sArg2, sizeof(sArg2));
		bAppend = StringToInt(sArg2) != 0;
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	char sTargetName[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool bTnIsML;

	if ((iTargetCount = ProcessTargetString(
			sArg1,
			iClient,
			iTargetList,
			MAXPLAYERS,
			COMMAND_FILTER_CONNECTED,
			sTargetName,
			sizeof(sTargetName),
			bTnIsML)) <= 0) {
		ReplyToTargetError(iClient, iTargetCount);
		return Plugin_Handled;
	}

	int iTargetted;
	int iBotsCount;
	for (int i=0; i<iTargetCount; i++) {
		if (iTargetted >= g_eDebugger[iClient].iTargetCount) {
			ReplyToCommand(iClient, "[smbl] Target list exhausted (selected %d (%d) / %d).", iTargetted, iTargetCount, g_eDebugger[iClient].iTargetCount);
			return Plugin_Handled;
		}

		Bot mBot = SMBL_GetClientBot(iTargetList[i]);
		if (!mBot) {
			ReplyToCommand(iClient, "[smbl] %N is not a BOT.", iTargetList[i]);
			continue;
		}

		for (int j=0; j<g_eDebugger[iClient].iTargetCount; j++) {
			int iTarget = g_eDebugger[iClient].iTargets[j];
			if (iTarget && iTarget != mBot.iEntity) {
				g_eDebugger[iClient].iTargets[(iTargetted+j)%g_eDebugger[iClient].iTargetCount] = 0;

				Operation mManualOp = FindManualOp(mBot);

				if (!mManualOp) {
					mManualOp = Operation.Instance(MANUAL_OPERATION);

					mBot.mMainOperation.AddSubOperation(mManualOp, 0);
				}

				Operation mOp = iBotsCount++ ? g_eDebugger[iClient].mOperation.Clone() : g_eDebugger[iClient].mOperation;

				mOp.AddStateChangeForward(Callback_Operation_StateChange);
				mOp.AddAbortForward(Callback_Operation_Aborted);

				ArrayList hSubOpRefs = mManualOp.hSubOpRefs;
				Op iOp;
				if (bAppend) {
					if (hSubOpRefs.Length) {
						OpRef mLastOpRef = hSubOpRefs.Get(hSubOpRefs.Length-1);
						Operation mLastOp = mLastOpRef.ToOperation();
						if (mLastOp.IsValid()) {
							iOp = view_as<Op>(view_as<int>(mLastOp.iOp)+1);
						}
					}
				} else {
					mManualOp.ClearSubOperations();
				}

				mOp.hInitParams.SetNum(g_eDebugger[iClient].sTargetParam, iTarget);

				mOp.iOp = iOp;
				mManualOp.AddSubOperation(mOp);

				char sOperation[128];
				mOp.GetIdentifier(sOperation, sizeof(sOperation));
				ReplyToCommand(iClient, "[smbl] %N: %s:%d added", mBot.iEntity, sOperation, mOp.iUID);

				iTargetted++;
				break;
			}
		}
	}

	return Plugin_Handled;
}

public Action cmdStop(int iClient, int iArgC) {
	if (iArgC < 1) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_stop <bot target>");
		return Plugin_Handled;
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	char sTargetName[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool bTnIsML;

	if ((iTargetCount = ProcessTargetString(
			sArg1,
			iClient,
			iTargetList,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			sTargetName,
			sizeof(sTargetName),
			bTnIsML)) <= 0) {
		ReplyToTargetError(iClient, iTargetCount);
		return Plugin_Handled;
	}

	for (int i=0; i<iTargetCount; i++) {
		Bot mBot = SMBL_GetClientBot(iTargetList[i]);
		if (!mBot) {
			ReplyToCommand(iClient, "[smbl] %N is not a BOT.", iTargetList[i]);
			continue;
		}

		Operation mManualOp = FindManualOp(mBot);
		if (mManualOp) {
			ArrayList hSubOpRefs = mManualOp.hSubOpRefs;
			for (int j=0; j<hSubOpRefs.Length; j++) {
				Operation mSubOp = view_as<OpRef>(hSubOpRefs.Get(j)).ToOperation();
				mSubOp.Abort();
			}
		}

		ReplyToCommand(iClient, "[smbl] %N stopped", mBot.iEntity);
	}

	return Plugin_Handled;
}

public Action cmdGoTo(int iClient, int iArgC) {
	if (iArgC < 1) {
		ReplyToCommand(iClient, "[smbl] Usage: smbl_debug_goto <bot> [operation [append (0/1)]]");
		return Plugin_Handled;
	}

	char sOperation[128];
	bool bAppend = false;
	switch (iArgC) {
		case 1: {
			sOperation = "Common.Walk";
		}
		case 2: {
			GetCmdArg(2, sOperation, sizeof(sOperation));
		}
		case 3: {
			GetCmdArg(2, sOperation, sizeof(sOperation));

			char sArg3[8];
			GetCmdArg(3, sArg3, sizeof(sArg3));
			bAppend = StringToInt(sArg3) != 0;
		}
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	FakeClientCommand(iClient, "smbl_debug_new %s", sOperation);
	FakeClientCommand(iClient, "smbl_debug_setmesh nav_mesh Ground");
	FakeClientCommand(iClient, "smbl_debug_setaim destination");
	FakeClientCommand(iClient, "smbl_debug_start %s %d", sArg1, bAppend);

	return Plugin_Handled;
}

// Helpers

void ResetClient(int iClient) {
	g_eDebugger[iClient].bEnabled = false;
	Operation.Destroy(g_eDebugger[iClient].mOperation);
}

int GetDebuggers(int iClients[MAXPLAYERS]) {
	int iCount = 0;
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && g_eDebugger[i].bEnabled) {
			iClients[iCount++] = i;
		}
	}

	return iCount;
}

Operation FindManualOp(Bot mBot) {
	if (!mBot.mMainOperation) {
		ThrowError("%N has no main operation!", mBot.iEntity);
	}
	ArrayList hMainSubOpRefs = mBot.mMainOperation.hSubOpRefs;

	char sOperation[128];
	for (int i=0; i<hMainSubOpRefs.Length; i++) {
		Operation mSubOp = view_as<OpRef>(hMainSubOpRefs.Get(i)).ToOperation();
		mSubOp.GetIdentifier(sOperation, sizeof(sOperation));

		if (StrEqual(sOperation, MANUAL_OPERATION)) {
			return mSubOp;
		}
	}

	return NULL_OPERATION;
}

bool GetTraceEndpoint(const float vecPos[3], const float vecAng[3], float vecEndPos[3]) {
	TR_TraceRayFilter(vecPos, vecAng, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilter_Environment);
	if (TR_DidHit()) {
		TR_GetEndPosition(vecEndPos);
		return true;
	}

	return false;
}

void Indent(char[] sBuffer, int iMaxLength, int iDepth, int iLast) {
	for (int i=1; i<iDepth; i++) {
		Format(sBuffer, iMaxLength, "%s%s   ", sBuffer, (iLast >> i) & 1 ? "  " : "│");
	}
}

int PrintCallChain(Operation mOperation, bool bConcurrentParent, char[] sBuffer, int iBufferSize, int &iLongestWidth, int iDepth=0, bool bFirst=true, int iLast=1) {
	int iLines;

	char[] sIndent = new char[8*iDepth+1];
	Indent(sIndent, 8*iDepth+1, iDepth, iLast);

	char sIdentifier[64];
	mOperation.GetIdentifier(sIdentifier, sizeof(sIdentifier));

	KeyValues hInitParams = mOperation.hInitParams;

	char sBufferParams[128];

	if (bFirst) {
		hInitParams.JumpToKey("InitParams");
		if (hInitParams.GotoFirstSubKey(false)) {
			do {
				char sComma[3];
				if (sBufferParams[0]) {
					sComma = ", ";
				}

				char sKey[32];
				hInitParams.GetSectionName(sKey, sizeof(sKey));

				if (hInitParams.GotoFirstSubKey(false)) {
					hInitParams.GoBack();
					continue;
				}

				switch (hInitParams.GetDataType(NULL_STRING)) {
					case KvData_String: {
						char sValue[32];
						hInitParams.GetString(NULL_STRING, sValue, sizeof(sValue));

						// Check if a vector
						char sFloatBuffers[3][32];
						if (ExplodeString(sValue, " ", sFloatBuffers, 3, sizeof(sFloatBuffers[]), true) == 3 \
							&& String_IsNumeric(sFloatBuffers[0]) \
							&& String_IsNumeric(sFloatBuffers[1]) \
							&& String_IsNumeric(sFloatBuffers[2])) {
							float vecValue[3];
							hInitParams.GetVector(NULL_STRING, vecValue);
							Format(sBufferParams, sizeof(sBufferParams), "%s%s%s=[%.0f, %.0f, %.0f]", sBufferParams, sComma, sKey, vecValue[0], vecValue[1], vecValue[2]);
						} else {
							Format(sBufferParams, sizeof(sBufferParams), "%s%s%s=%s", sBufferParams, sComma, sKey, sValue);
						}
					}
					case KvData_Int: {
						int iValue = hInitParams.GetNum(NULL_STRING);
						if (StrEqual(sKey, "target", false) && Client_IsIngame(iValue)) {
							Format(sBufferParams, sizeof(sBufferParams), "%s%s%s=%N", sBufferParams, sComma, sKey, iValue);
						} else {
							Format(sBufferParams, sizeof(sBufferParams), "%s%s%s=%d", sBufferParams, sComma, sKey, iValue);
						}
					}
					case KvData_Float: {
						Format(sBufferParams, sizeof(sBufferParams), "%s%s%s=%.3f", sBufferParams, sComma, sKey, hInitParams.GetFloat(NULL_STRING));
					}

				}
			} while (hInitParams.GotoNextKey(false));
		}

		hInitParams.Rewind();
	}

	int iUID = mOperation.iUID;

	bool bLoop = mOperation.bLoop;
	bool bConcurrent = mOperation.bConcurrent;
	char sLoopConcurrent[32];
	if (bLoop || bConcurrent) {
		FormatEx(sLoopConcurrent, sizeof(sLoopConcurrent), "[%s%s] ", bLoop ? "L" : "", bConcurrent ? "C" : "");
	}

	if (sBufferParams[0]) {
		Format(sBufferParams, sizeof(sBufferParams), "(%s)", sBufferParams);
	}

	char sIdx[8];
	if (!bConcurrentParent) {
		FormatEx(sIdx, sizeof(sIdx), "%d ", view_as<int>(mOperation.iOp)+1);
	}

	bool bLast = ((iLast >> iDepth) & 1) != 0;

	char sBufferSection[256];
	if (iDepth) {
		Format(sBufferSection, sizeof(sBufferSection), "%s%s %s%s:%d %s%s", sIndent, bLast ? "└─" : "├─", sIdx, sIdentifier, iUID, sLoopConcurrent, sBufferParams);
	} else {
		Format(sBufferSection, sizeof(sBufferSection), "%s%s:%d %s%s", sIdx, sIdentifier, iUID, sLoopConcurrent, sBufferParams);
	}

	int iWidth = strlen(sBufferSection);
	if (iWidth > iLongestWidth) {
		iWidth = iLongestWidth;
	}

	ArrayList hSequences = mOperation.hSequences;
	if (hSequences) {
		int iSequencesLength = hSequences.Length;
		int iMaxIdx = iSequencesLength < 2 ? iSequencesLength : 2;

		// Prevents pointlessly showing (1 more...) on third line when there are only 3 items
		if (iSequencesLength == 3) {
			iMaxIdx = 3;
			iLines += 3;
		} else {
			iLines += iMaxIdx;
		}

		for (int i=0; i<iMaxIdx; i++) {
			Sequence eSequence;
			hSequences.GetArray(i, eSequence, sizeof(Sequence));
			Format(sBufferSection, iBufferSize, "%s\n%s%s   %s─ %d %s", sBufferSection, sIndent, bLast ? "  " : "│", (i == iSequencesLength-1) ? "└" : "├", view_as<int>(eSequence.iSeq)+1, eSequence.sIdentifier);
		}

		if (iSequencesLength > iMaxIdx) {
			Format(sBufferSection, iBufferSize, "%s\n%s%s   └─ (%d more...)", sBufferSection, sIndent, bLast ? "  " : "│", iSequencesLength-iMaxIdx);
			iLines++;
		}
	}

	Format(sBuffer, iBufferSize, "%s%s%s", sBuffer, sBuffer[0] ? "\n" : "", sBufferSection);

	iLines++;

	ArrayList hSubOpRefs = mOperation.hSubOpRefs;
	if (hSubOpRefs) {
		for (int i=0; i<hSubOpRefs.Length; i++) {
			OpRef mSubOpRef = hSubOpRefs.Get(i);
			Operation mSubOp = mSubOpRef.ToOperation();
			if (mSubOp.IsValid()) {
				iLines += PrintCallChain(mSubOp, bConcurrent, sBuffer, iBufferSize, iLongestWidth, iDepth+1, i==0, iLast | view_as<int>(i==hSubOpRefs.Length-1) << (iDepth+1));
			} else {
				Indent(sIndent, 8*iDepth+2, iDepth+1, iLast | view_as<int>(i==hSubOpRefs.Length-1) << (iDepth+1));
				Format(sBuffer, iBufferSize, "%s\n%s %s ? (Invalid Operation)", sBuffer, sIndent, (i==hSubOpRefs.Length-1) ? "└─" : "├─");
				iLines++;
			}
		}
	}

	return iLines;
}

// Menus

public int MenuHandler_Debug(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	if (iAction == MenuAction_Select) {
		g_eDebugger[iClient].bEnabled = false;
	}

	return 0;
}
