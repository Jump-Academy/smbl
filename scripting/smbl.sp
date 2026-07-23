#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.2.0"

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>

#include <autoexecconfig>
#include <botcontroller>
#include <multicolors>
#include <smlib/arrays>
#include <smlib/clients>
#include <smlib/entities>
#include <tf2items>

#pragma newdecls required

#include <smbl>
#include <smbl/controller>
#include "smbl/common.sp"
#include "smbl/bot.sp"
#include "smbl/controller.sp"
#include "smbl/director.sp"
#include "smbl/monitor.sp"
#include "smbl/observable.sp"
#include "smbl/operation.sp"
#include "smbl/utility.sp"

#define PID_DEFAULT		{0.2,	0.001,	0.65}
#define PID_SLOW_LAZY	{0.05,	0.001,	0.01}
#define PID_FAST		{0.1,	0.001,	0.01}
#define PID_SNAP		{1.0,	0.000,	0.00}

#define MAIN_OPERATION	"Main"

enum BotQuotaMode {
	BotQuotaMode_Normal,
	BotQuotaMode_Fill,
	BotQuotaMode_Match
}

BotQuotaMode g_iBotQuotaMode;

bool g_bReady;
bool g_bShutdown = false;

ConVar g_hCVBotQuota;
ConVar g_hCVBotQuotaMode;

ConVar g_hCVBotDifficulty;
ConVar g_hCVBotClasses;

ConVar g_hCVBotDebugPrefix;

ConVar g_hCVThinkInterval;

GlobalForward g_hStartForward;

int g_iBotClasses;

public Plugin myinfo = {
	name = "SMBL SourceMod Bot Library",
	author = PLUGIN_AUTHOR,
	description = "Custom Bots Library for TF2",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("smbl_version", PLUGIN_VERSION, "SMBL version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("smbl");

	g_hCVBotQuota		= AutoExecConfig_CreateConVar("smbl_bot_quota",			"4", 															"Bot quota",									FCVAR_NOTIFY,	true,	0.0);
	g_hCVBotQuotaMode	= AutoExecConfig_CreateConVar("smbl_bot_quota_mode",	"normal",														"Bot quota mode",								FCVAR_NOTIFY);
	g_hCVBotDifficulty	= AutoExecConfig_CreateConVar("smbl_bot_difficulty",	"1",															"Bot difficulty",								FCVAR_NOTIFY,	true,	1.0, 	true,	5.0);
	g_hCVBotClasses		= AutoExecConfig_CreateConVar("smbl_bot_classes",		"scout,sniper,soldier,demoman,medic,heavy,pyro,spy,engineer",	"Bot enabled classes",							FCVAR_NOTIFY);
	g_hCVBotDebugPrefix	= AutoExecConfig_CreateConVar("smbl_bot_debug_prefix",	"0",															"Show bot difficulty and class in name prefix",	FCVAR_NOTIFY);
	g_hCVThinkInterval	= AutoExecConfig_CreateConVar("smbl_think_interval",	"0.5",															"Director think interval (seconds)",			FCVAR_NOTIFY,	true,	0.0);

	AutoExecConfig_ExecuteFile();

	g_hCVBotQuota.AddChangeHook(ConVarChanged_BotQuota);
	g_hCVBotQuotaMode.AddChangeHook(ConVarChanged_BotQuotaMode);

	RegAdminCmd("smbl_status", cmdStatus, ADMFLAG_ROOT, "Display the resource use of the bot library");

	g_hStartForward = new GlobalForward("SMBL_OnStart", ET_Ignore);

	g_hBots = new ArrayList();
	g_hBotEntities = new StringMap();

	g_hDirectors = new ArrayList(sizeof(Director));

	SetupBotSDKCalls();
}

public void OnPluginEnd() {
	g_bShutdown = true;
	RemoveBots("Plugin terminated");
	DestroyAllOperations();
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("smbl");

	SetupSMBLNatives();
	SetupBotNatives();
	SetupOperationNatives();
	SetupControllerNatives();
	SetupDirectorNatives();
	SetupMonitorNatives();
	SetupObservableNatives();
	SetupUtilityNatives();

	return APLRes_Success;
}

public void OnAllPluginsLoaded() {
	Operation.Register(MAIN_OPERATION, _, _, _, _, _, _, _, true, true, true, false);

	RegisterControllerOperations();

	RequestFrame(RequestFrameCallback_Start);
}

public void OnNotifyPluginUnloaded(Handle hPlugin) {
	DeregisterPluginObservables(hPlugin);
	DeregisterPluginMonitors(hPlugin);
	DeregisterPluginDirectors(hPlugin);
	DeregisterPluginControllers(hPlugin);
	DeregisterPluginOperations(hPlugin);
}

public void OnConfigsExecuted() {
	char sClasses[64];
	g_hCVBotClasses.GetString(sClasses, sizeof(sClasses));

	TrimString(sClasses);
	TFClassType iClass = TF2_GetClass(sClasses);

	g_iBotClasses = 0;

	char sBuffer[32];
	int iIdx = 0;
	int iOffset = 0;

	while ((iIdx = SplitString(sClasses[iOffset], ",", sBuffer, sizeof(sBuffer))) != -1) {
		TrimString(sBuffer);
		if ((iClass = TF2_GetClass(sBuffer)) != TFClass_Unknown) {
			g_iBotClasses |= 1 << view_as<int>(TF2_GetClass(sBuffer));
		}

		iOffset += iIdx;
	}

	TrimString(sClasses[iOffset]);
	if ((iClass = TF2_GetClass(sClasses[iOffset])) != TFClass_Unknown) {
		g_iBotClasses |= 1 << view_as<int>(iClass);
	}

	if (!g_iBotClasses) {
		PrintToServer("[SMBL] Warning: No bot classes were set.");
	}

	g_fDirectorThinkInterval = g_hCVThinkInterval.FloatValue;
}

public void OnMapStart() {

}

public void OnMapEnd() {
	RemoveBots("Map ended");
	DestroyAllOperations();
}

public void OnClientConnected(int iClient) {
	if (g_bShutdown) {
		return;
	}

	if (!IsFakeClient(iClient)) {
		SetupBots();
	}
}

public void OnClientDisconnect(int iClient) {
	if (g_bShutdown) {
		return;
	}

	if (g_mClientBot[iClient]) {
		Bot.Destroy(g_mClientBot[iClient]);

		g_iClientBotCount--;
	}

	if (Client_GetCount(true, false)) {
		RequestFrame(RequestFrameCallback_SetupBots);
	} else {
		RemoveBots("Server emptied");
		DestroyAllOperations();
	}
}

public void OnEntityDestroyed(int iEntity) {
	if (iEntity < 0) {
		return;
	}

	UnwatchObservableEntity(iEntity);

	char sKey[6];
	PackCellToStr(EntIndexToEntRef(iEntity), sKey);

	Bot mBot;
	if (g_hBotEntities.GetValue(sKey, mBot)) {
		PrintToServer("OnEntityDestroyed(%d)", iEntity);

		if (1 <= iEntity <= MaxClients) {
			PrintToServer("Bot destroyed is a client: %N", iEntity);
		} else {
			char sClassName[32];
			GetEntityClassname(iEntity, sClassName, sizeof(sClassName));
			PrintToServer("Bot destroyed is an entity: %s", sClassName);
		}

		// Check flag to prevent a duplicate call to Bot.Destroy()
		// If a manual call to Bot.Destroy() did not cause this entity's destruction,
		// mBot.iEntity would still have been valid up to this point.
		if (mBot.iEntity !=  INVALID_ENT_REFERENCE) {
			Bot.Destroy(mBot);
		}

		g_hBotEntities.Remove(sKey);

		int iIdx = g_hBots.FindValue(mBot);
		if (iIdx != -1) {
			g_hBots.Erase(iIdx);
		}
	}
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float vecVel[3], float vecAng[3], int &iWeapon) {
	Bot mBot = g_mClientBot[iClient];
	if (!mBot) {
		return Plugin_Continue;
	}

	mBot.iButtons = 0;
	mBot.SetLocalVelocity({0.0,  0.0, 0.0});

	RunOperations(mBot, mBot.mMainOperation);

	// PID aim controller
	AdjustAim(mBot, vecAng);

	iButtons = mBot.iButtons;
	mBot.GetLocalVelocity(vecVel);

	return Plugin_Changed;
}

// Custom callbacks

public void ConVarChanged_BotQuota(ConVar hCVConVar, const char[] sOldValue, const char[] sNewValue) {
	if (Client_GetCount(true, false)) {
		SetupBots();
	}
}

public void ConVarChanged_BotQuotaMode(ConVar hCVConVar, const char[] sOldValue, const char[] sNewValue) {
	if (StrEqual(sNewValue, "fill", false)) {
		g_iBotQuotaMode = BotQuotaMode_Fill;
	} else if (StrEqual(sNewValue, "match", false)) {
		g_iBotQuotaMode = BotQuotaMode_Match;
	} else {
		g_iBotQuotaMode = BotQuotaMode_Normal;
	}

	if (Client_GetCount(true, false)) {
		SetupBots();
	}
}

public void RequestFrameCallback_Start(any aData) {
	g_bReady = true;

	Call_StartForward(g_hStartForward);
	Call_Finish();

	RequestFrame(RequestFrameCallback_SetupBots);
}

public void RequestFrameCallback_SetupBots(any aData) {
	if (GetClientCount()) {
		SetupBots();
	}
}

// Natives

void SetupSMBLNatives() {
	CreateNative("SMBL_IsReady",		Native_SMBL_IsReady);
	CreateNative("SMBL_NotifyOnStart",	Native_SMBL_NotifyOnStart);
}

public any Native_SMBL_IsReady(Handle hPlugin, int iArgC) {
	return g_bReady && !g_bShutdown;
}

public any Native_SMBL_NotifyOnStart(Handle hPlugin, int iArgC) {
	if (g_bReady && !g_bShutdown) {
		Function fnForward = GetFunctionByName(hPlugin, "SMBL_OnStart");
		if (fnForward != INVALID_FUNCTION) {
			Call_StartFunction(hPlugin, fnForward);
			Call_Finish();
		}
	}

	return 0;
}

// Timers

public Action Timer_DirectorThink(Handle hTimer) {
	int iDirectorsTotal = g_hDirectors.Length;
	for (int i=0; i<iDirectorsTotal; i++) {
		Director eDirector;
		g_hDirectors.GetArray(i, eDirector);

		Call_StartFunction(eDirector.hPlugin, eDirector.fnThink);
		Call_Finish();
	}

	return Plugin_Continue;
}

// Commands

public Action cmdStatus(int iClient, int iArgC) {
	ShowOperationStatus(iClient);

	return Plugin_Handled;
}

// Helpers

void SetupBots() {
	int iBlueCount;
	int iRedCount;

	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && !IsClientSourceTV(i) && !IsClientReplay(i)) {
			switch (TF2_GetClientTeam(i)) {
				case TFTeam_Red: {
					iRedCount++;
				}
				case TFTeam_Blue: {
					iBlueCount++;
				}
			}
		}
	}

	char sName[MAX_NAME_LENGTH];

	int iClientCount = Client_GetCount(true, true);
	int iPlayerCount = Client_GetCount(true, false);
	int iBotsQuota = g_hCVBotQuota.IntValue;

	int iClientBotsAdjustment;

	switch (g_iBotQuotaMode) {
		case BotQuotaMode_Normal: {
			iClientBotsAdjustment = iBotsQuota - g_iClientBotCount;
		}
		case BotQuotaMode_Fill: {
			iClientBotsAdjustment = iBotsQuota - g_iClientBotCount - iPlayerCount;
		}
		case BotQuotaMode_Match: {
			iClientBotsAdjustment = iPlayerCount*iBotsQuota - g_iClientBotCount;
		}
	}

	if (!iClientBotsAdjustment) {
		return;
	}

	if (iClientBotsAdjustment < 0) {
		for (int i=MaxClients; i>=0 && iClientBotsAdjustment != 0; i--) {
			if (!g_mClientBot[i]) {
				continue;
			}

			// Sets g_mClientBot[i] to NULL_BOT, which prevents a duplicate call to Bot.Destroy() from OnClientDisconnect().
			Bot.Destroy(g_mClientBot[i], "Bot quota adjustment");

			iClientBotsAdjustment++;
			g_iClientBotCount--;
		}
	} else {
		int iBotClasses;
		int iBotClassesCount;

		for (TFClassType i=TFClass_Scout; i<=TFClass_Engineer; i++) {
			bool bAvailable = (g_iBotClasses & (1 << view_as<int>(i))) != 0 && AreClientControllersAvailable(i);
			if (bAvailable) {
				iBotClassesCount++;
				iBotClasses |= view_as<int>(bAvailable) << view_as<int>(i);
			}
		}

		if (!iBotClassesCount) {
			return;
		}

		while(iClientCount < GetMaxHumanPlayers() && iClientBotsAdjustment--) {
			int iRandom =  1 + GetURandomInt() % iBotClassesCount;
			TFClassType iRandomClass;

			for (TFClassType i=TFClass_Scout; i<=TFClass_Engineer && iRandom>0; i++) {
				if (iBotClasses & (1 << view_as<int>(i))) {
					iRandomClass = i;
					iRandom--;
				}
			}

			char sClassName[32];
			TF2_GetClassName(iRandomClass, sClassName, sizeof(sClassName));

			GenerateBotName(sName, sizeof(sName));

			if (g_hCVBotDebugPrefix.BoolValue) {
				char sClassChars[4];
				TF2_GetClassChars(view_as<TFClassType>(iRandomClass), sClassChars, sizeof(sClassChars));

				Format(sName, sizeof(sName), "%s.%d - %s", sClassChars, 0, sName);
			}

			int iClient = BotController_CreateBot(sName);
			if (iClient == -1) {
				LogError("Failed to create bot");
				return;
			}

			Bot mBot = Bot.Instance();

			char sKey[6];
			PackCellToStr(mBot, sKey);

			g_hBots.Push(mBot);
			g_hBotEntities.SetValue(sKey, EntIndexToEntRef(iClient));

			g_mClientBot[iClient] = mBot;

			mBot.iEntity = iClient;

			mBot.bActive = true;
			mBot.SetDefaultName(sName);

			mBot.mMainOperation = Operation.Instance(MAIN_OPERATION);

			TF2_SetPlayerClass(iClient, view_as<TFClassType>(iRandomClass));

			if (iBlueCount > iRedCount) {
				TF2_ChangeClientTeam(iClient, TFTeam_Red);
				iRedCount++;
			} else {
				TF2_ChangeClientTeam(iClient, TFTeam_Blue);
				iBlueCount++;
			}

			mBot.SetPID(PID_DEFAULT);

			g_iClientBotCount++;
			iClientCount++;

			Call_StartForward(g_hOnBotAddForward);
			Call_PushCell(mBot);
			Call_Finish();
		}
	}
}

void RemoveBots(char[] sReason=NULL_STRING) {
	while (g_hBots.Length) {
		Bot mBot = g_hBots.Get(g_hBots.Length-1);

		int iEntity = mBot.iEntity;
		if (1 <= iEntity <= MaxClients) {
			g_mClientBot[iEntity] = NULL_BOT;
			g_iClientBotCount--;
		}

		Bot.Destroy(mBot, sReason);
	}
}

void GenerateBotName(char[] sBotName, int iMaxLength) {
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "data/smbl/bot_names.txt");

	File hFile;
	if (!FileExists(sFilePath) || !(hFile = OpenFile(sFilePath, "r"))) {
		strcopy(sBotName, iMaxLength, "BOT");

		GenerateUniqueName(sBotName, iMaxLength);
	} else {
		ArrayList hNames = new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));

		char sName[MAX_NAME_LENGTH];
		while (hFile.ReadLine(sName, sizeof(sName))) {
			TrimString(sName);
			if (sName[0]) {
				hNames.PushString(sName);
			}
		}

		hFile.Close();

		ArrayList hNamesTemp = hNames.Clone();

		bool bFound = false;

		while (!bFound && hNamesTemp.Length) {
			int iIdx = GetRandomInt(0, hNamesTemp.Length-1);
			hNamesTemp.GetString(iIdx, sName, sizeof(sName));

			if (IsNameUnique(sName)) {
				bFound = true;
			} else {
				hNamesTemp.Erase(iIdx);
			}
		}

		if (bFound) {
			strcopy(sBotName, iMaxLength, sName);
		} else {
			hNames.GetString(GetRandomInt(0, hNames.Length-1), sBotName, iMaxLength);
			GenerateUniqueName(sBotName, iMaxLength);
		}

		delete hNames;
		delete hNamesTemp;
	}
}

void GenerateUniqueName(char[] sBaseName, int iMaxLen) {
	char sName[MAX_NAME_LENGTH];
	strcopy(sName, sizeof(sName), sBaseName);

	for (int i=0; i<MaxClients; i++) {
		if (i > 0) {
			FormatEx(sName, iMaxLen, "%s-%d", sBaseName, i);
		}

		if (IsNameUnique(sName)) {
			strcopy(sBaseName, iMaxLen, sName);
			return;
		}
	}
}

bool IsNameUnique(char[] sNameSearch) {
	char sName[MAX_NAME_LENGTH];

	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i)) {
			GetClientName(i, sName, sizeof(sName));

			if (StrContains(sName, sNameSearch, false) != -1) {
				return false;
			}
		}
	}

	return true;
}

/**
 * PackCellToStr
 * Credit: Asher 'Asherkin' Baker
 * Packs a key, as an integer, into a null-terminated buffer.
 */
void PackCellToStr(any aKey, char[] sBuffer) {
	int i = aKey;
	sBuffer[0] = ((i >> 28) & 0x7F) | 0x80;
	sBuffer[1] = ((i >> 21) & 0x7F) | 0x80;
	sBuffer[2] = ((i >> 14) & 0x7F) | 0x80;
	sBuffer[3] = ((i >>  7) & 0x7F) | 0x80;
	sBuffer[4] = ((i      ) & 0x7F) | 0x80;
	sBuffer[5] = 0;
}

void TF2_GetClassName(TFClassType iClassType, char[] sName, int iMaxLength) {
	char sClass[10][10] = {"unknown", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer"};
	strcopy(sName, iMaxLength, sClass[view_as<int>(iClassType)]);
}

void TF2_GetClassChars(TFClassType iClassType, char[] sChars, int iMaxLength) {
	char sClassChars[10][4] = {"unk", "sc", "sn", "so", "dm", "md", "hw", "py", "sp", "en"};
	strcopy(sChars, iMaxLength, sClassChars[view_as<int>(iClassType)]);
}
