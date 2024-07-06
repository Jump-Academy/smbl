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
#include "smbl/common.sp"
#include "smbl/bot.sp"
#include "smbl/controller.sp"
#include "smbl/director.sp"
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

bool g_bShutdown = false;

ConVar g_hCVBotQuota;
ConVar g_hCVBotQuotaMode;

ConVar g_hCVBotDifficulty;
ConVar g_hCVBotClasses;

ConVar g_hCVBotDebugPrefix;

ConVar g_hCVThinkInterval;

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

	g_hBots = new ArrayList();
	g_hDirectors = new ArrayList(sizeof(Director));

	SetupBotSDKCalls();
}

public void OnPluginEnd() {
	g_bShutdown = true;
	RemoveBots();
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("smbl");

	SetupBotNatives();
	SetupOperationNatives();
	SetupControllerNatives();
	SetupDirectorNatives();
	SetupUtilityNatives();

	return APLRes_Success;
}

public void OnAllPluginsLoaded() {
	Operation.Register(MAIN_OPERATION, _, _, _, _, _, _, _, true, true, true, false);
}

public void OnNotifyPluginUnloaded(Handle hPlugin) {
	DeregisterPluginDirectors(hPlugin);
	DeregisterPluginControllers(hPlugin);
	DeregisterPluginOperations(hPlugin);
}

public void OnConfigsExecuted() {
	char sClasses[64];
	g_hCVBotClasses.GetString(sClasses, sizeof(sClasses));

	TrimString(sClasses);
	TFClassType iClass = TF2_GetClass(sClasses);

	if (iClass != TFClass_Unknown) {
		if (!g_hControllers[iClass] || !g_hControllers[iClass].Size) {
			char sClass[32];
			TF2_GetClassName(iClass, sClass, sizeof(sClass));
			PrintToServer("No controllers found for %s", sClass);
		} else {
			g_iBotClasses = 1 << view_as<int>(iClass);
		}
	} else {
		g_iBotClasses = 0;

		char sBuffer[32];
		int iIdx = 0;
		int iOffset = 0;

		while ((iIdx = SplitString(sClasses[iOffset], ",", sBuffer, sizeof(sBuffer))) != -1) {
			TrimString(sBuffer);
			if ((iClass = TF2_GetClass(sBuffer)) != TFClass_Unknown) {
				if (g_hControllers[iClass]) {
					g_iBotClasses |= 1 << view_as<int>(TF2_GetClass(sBuffer));
				} else {
					char sClass[32];
					TF2_GetClassName(iClass, sClass, sizeof(sClass));
					PrintToServer("SMBL: No controller found for %s", sClass);
				}
			}

			iOffset += iIdx;
		}

		TrimString(sClasses[iOffset]);
		if ((iClass = TF2_GetClass(sClasses[iOffset])) != TFClass_Unknown) {
			if (!g_hControllers[iClass]) {
				char sClass[32];
				TF2_GetClassName(iClass, sClass, sizeof(sClass));
				PrintToServer("SMBL: No controller found for %s", sClass);
			} else {
				g_iBotClasses |= 1 << view_as<int>(iClass);
			}
		}
	}

	if (!g_iBotClasses) {
		PrintToServer("SMBL: Warning: No bot classes are available");
	}

	if (GetGameTime() > 5.0 && GetClientCount()) {
		SetupBots();
	}

	g_fDirectorThinkInterval = g_hCVThinkInterval.FloatValue;
}

public void OnMapStart() {

}

public void OnMapEnd() {
	RemoveBots();
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
		int iIdx = g_hBots.FindValue(g_mClientBot[iClient]);
		if (iIdx != -1) {
			g_hBots.Erase(iIdx);
		}

		g_mClientBot[iClient].CleanUp();
		g_mClientBot[iClient] = NULL_BOT;
		g_iClientBotCount--;
	}

	if (Client_GetCount(true, false)) {
		SetupBots();
	} else {
		RemoveBots();
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
	SetupBots();
}

public void ConVarChanged_BotQuotaMode(ConVar hCVConVar, const char[] sOldValue, const char[] sNewValue) {
	if (StrEqual(sNewValue, "fill", false)) {
		g_iBotQuotaMode = BotQuotaMode_Fill;
	} else if (StrEqual(sNewValue, "match", false)) {
		g_iBotQuotaMode = BotQuotaMode_Match;
	} else {
		g_iBotQuotaMode = BotQuotaMode_Normal;
	}

	SetupBots();
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
	if (!g_iBotClasses) {
		return;
	}

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
		for (int i=g_hBots.Length-1; i>=0 && iClientBotsAdjustment != 0; i--, iClientBotsAdjustment++) {
			Bot mBot = g_hBots.Get(i);
			int iClient = mBot.iEntity;
			if (1 <= iClient <= MaxClients && IsClientInGame(iClient)) {
				mBot.CleanUp();
				KickClient(iClient);
			}
		}
	} else {
		while(iClientCount < GetMaxHumanPlayers() && iClientBotsAdjustment--) {
			int iRandomClass = GetRandomInt(1, 9);
			while (!(g_iBotClasses & (1 << iRandomClass))) {
				iRandomClass = (iRandomClass+1) % 10;
			}

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
			g_hBots.Push(mBot);
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

void RemoveBots() {
	int iBotsLength = g_hBots.Length;
	for (int i=0; i<iBotsLength; i++) {
		Bot mBot = g_hBots.Get(i);
		mBot.CleanUp();

		int iClient = mBot.iEntity;
		if (1 <= iClient <= MaxClients && IsClientInGame(iClient)) {
			KickClient(iClient);
		}
	}

	g_hBots.Clear();

	Array_Fill(g_mClientBot, sizeof(g_mClientBot), NULL_BOT);
	g_iClientBotCount = 0;
}

void GenerateBotName(char[] sBotName, int iMaxLength) {
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "data/smbl/bot_names.txt");

	File hFile;
	if (!FileExists(sFilePath) || !(hFile = OpenFile(sFilePath, "r"))) {
		PrintToServer("Cannot read from bot_names.txt");
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

void TF2_GetClassName(TFClassType iClassType, char[] sName, int iMaxLength) {
	char sClass[10][10] = {"unknown", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer"};
	strcopy(sName, iMaxLength, sClass[view_as<int>(iClassType)]);
}

void TF2_GetClassChars(TFClassType iClassType, char[] sChars, int iMaxLength) {
	char sClassChars[10][4] = {"unk", "sc", "sn", "so", "dm", "md", "hw", "py", "sp", "en"};
	strcopy(sChars, iMaxLength, sClassChars[view_as<int>(iClassType)]);
}
