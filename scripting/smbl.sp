#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

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

#define PID_DEFAULT		{0.2,	0.001,	0.65}
#define PID_SLOW_LAZY	{0.05,	0.001,	0.01}
#define PID_FAST		{0.1,	0.001,	0.01}
#define PID_SNAP		{1.0,	0.000,	0.00}

bool g_bShutdown = false;

ConVar g_hCVBotQuota;
ConVar g_hCVBotQuotaMode;

ConVar g_hCVBotDifficulty;
ConVar g_hCVBotClasses;

ConVar g_hCVThinkInterval;

int g_iBotClasses;

StringMap g_hNavMeshes;

public Plugin myinfo = {
	name = "Teufort AI Library",
	author = PLUGIN_AUTHOR,
	description = "TF2 Bots AI Library",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("smbl_version", PLUGIN_VERSION, "SMBL version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("smbl");

	g_hCVBotQuota		= AutoExecConfig_CreateConVar("smbl_bot_quota",			"4", 															"Bot quota",							FCVAR_NOTIFY,	true,	0.0);
	g_hCVBotQuotaMode	= AutoExecConfig_CreateConVar("smbl_bot_quota_mode",	"fill",															"Bot quota mode",						FCVAR_NOTIFY);
	g_hCVBotDifficulty	= AutoExecConfig_CreateConVar("smbl_bot_difficulty",	"1",															"Bot difficulty",						FCVAR_NOTIFY,	true,	1.0, 	true,	5.0);
	g_hCVBotClasses		= AutoExecConfig_CreateConVar("smbl_bot_classes",		"scout,sniper,soldier,demoman,medic,heavy,pyro,spy,engineer",	"Bot enabled classes",					FCVAR_NOTIFY);
	g_hCVThinkInterval	= AutoExecConfig_CreateConVar("smbl_think_interval",	"0.5",															"Director think interval (seconds)",	FCVAR_NOTIFY,	true,	0.0);

	AutoExecConfig_ExecuteFile();

	g_hNavMeshes = new StringMap();
	g_hBots = new ArrayList();
	g_hDirectors = new ArrayList(sizeof(Director));
}

public void OnPluginEnd() {
	g_bShutdown = true;
	RemoveBots();
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("SMBL");

	CreateNative("SMBL_RegisterNavMesh", Native_RegisterNavMesh);
	CreateNative("SMBL_DeregisterNavMesh", Native_DeregisterNavMesh);
	CreateNative("SMBL_DeregisterAllNavMeshes", Native_DeregisterAllNavMeshes);
	CreateNative("SMBL_GetNavMesh", Native_GetNavMesh);

	SetupBotNatives();
	SetupOperationNatives();
	SetupControllerNatives();
	SetupDirectorNatives();
}

public void OnAllPluginsLoaded() {
	SMBL_RegisterOperation("SMBL.MainLoop", INVALID_FUNCTION, INVALID_FUNCTION, INVALID_FUNCTION, INVALID_FUNCTION, INVALID_FUNCTION, true, true, false, false);
}

public void OnConfigsExecuted() {
	char sClasses[64];
	g_hCVBotClasses.GetString(sClasses, sizeof(sClasses));

	TrimString(sClasses);
	TFClassType iClass = TF2_GetClass(sClasses);

	if (iClass != TFClass_Unknown) {
		if (!g_hControllers[iClass] || !g_hControllers[iClass].Length) {
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
	int iBotsLength = g_hBots.Length;
	for (int i=0; i<iBotsLength; i++) {
		Bot mBot = g_hBots.Get(i);
// 		int iClient = mBot.iEntity;
// 		if (1 <= iClient <= MaxClients && IsClientInGame(iClient)) {
// 			KickClient(iClient, "SMBL plugin terminating");
// 		}
		mBot.CleanUp();
	}

	Array_Fill(g_mBotClients, sizeof(g_mBotClients), NULL_BOT);
}

public void OnClientConnected(int iClient) {
	if (g_bShutdown) {
		return;
	}

	if (!IsFakeClient(iClient)) {
		SetupBots();
	}

// 	if (g_iBotClientsCount > 0 && GetClientCount() >= GetMaxHumanPlayers()-g_hCVBotQuota.IntValue) {
// 		for (int i=1; i<=MaxClients; i++) {
// 			if (g_eBot[i].bActive) {
// 				KickClient(i, "Player slot priority");
// 				break;
// 			}
// 		}
// 	}
}

public void OnClientDisconnect(int iClient) {
	if (g_bShutdown) {
		return;
	}

	if (g_mBotClients[iClient]) {
		g_mBotClients[iClient].CleanUp();
		g_mBotClients[iClient] = NULL_BOT;
		g_iBotClientsCount--;
	}

	int iPlayerCount = Client_GetCount(true, false);
	if (iPlayerCount == 0) {
		RemoveBots();

		g_iBotClientsCount = 0;
	} else if (iPlayerCount < GetMaxHumanPlayers()-g_hCVBotQuota.IntValue) {
		SetupBots();
	}
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float vecVel[3], float vecAng[3], int &iWeapon) {
	Bot mBot = g_mBotClients[iClient];
	if (!mBot) {
		return Plugin_Continue;
	}

	mBot.iButtons = 0;
	mBot.SetLocalVelocity({0.0,  0.0, 0.0});

	RunOperations(mBot, mBot.mOpMain);

	// PID aim controller
	AdjustAim(mBot, vecAng);

	iButtons = mBot.iButtons;
	mBot.GetLocalVelocity(vecVel);

	return Plugin_Changed;
}

// Natives

public int Native_RegisterNavMesh(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	NavMesh mNavMesh = GetNativeCell(2);

	if (g_hNavMeshes.SetValue(sIdentifier, mNavMesh, false)) {
		PrintToServer("SMBL registered navigation mesh: %s", sIdentifier);
		return true;
	}

	PrintToServer("SMBL cannot register navigation mesh: %s (duplicate?)", sIdentifier);

	return false;
}

public int Native_DeregisterNavMesh(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	bool bDestroy = GetNativeCell(2);
	if (bDestroy) {
		NavMesh mNavMesh;
		if (!g_hNavMeshes.GetValue(sIdentifier, mNavMesh)) {
			PrintToServer("SMBL cannot find navigation mesh to deregister: %s", sIdentifier);
			return false;
		}

		PrintToServer("SMBL deregistered navigation mesh: %s", sIdentifier);

		NavMesh.Destroy(mNavMesh);
	}

	return g_hNavMeshes.Remove(sIdentifier);
}

public int Native_DeregisterAllNavMeshes(Handle hPlugin, int iArgC) {
	bool bDestroy = GetNativeCell(1);
	if (bDestroy) {
		StringMapSnapshot hSnapshot = g_hNavMeshes.Snapshot();
		int iSnapshotLength = hSnapshot.Length;
		char sIdentifier[64];

		for (int i=0; i<iSnapshotLength; i++) {
			hSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));
			NavMesh mNavMesh;
			if (g_hNavMeshes.GetValue(sIdentifier, mNavMesh)) {
				NavMesh.Destroy(mNavMesh);
			}
		}

		delete hSnapshot;

		PrintToServer("SMBL deregistered %d navigation meshes", g_hNavMeshes.Size);
	}
	
	g_hNavMeshes.Clear();
}

public any Native_GetNavMesh(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	NavMesh mNavMesh;
	g_hNavMeshes.GetValue(sIdentifier, mNavMesh);

	return mNavMesh;
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

	int iPlayerCount = Client_GetCount(true, true);
	int iMaxBots = g_hCVBotQuota.IntValue;
	while(iPlayerCount < GetMaxHumanPlayers() && g_iBotClientsCount < iMaxBots) {
		int iRandomClass = GetRandomInt(1, 9);
		while (!(g_iBotClasses & (1 << iRandomClass))) {
			iRandomClass = (iRandomClass+1) % 10;
		}

		char sClassChars[4];
		TF2_GetClassChars(view_as<TFClassType>(iRandomClass), sClassChars, sizeof(sClassChars));

		GenerateBotName(sName, sizeof(sName));

		Format(sName, sizeof(sName), "%s.%d - %s", sClassChars, 0, sName);

		int iClient = BotController_CreateBot(sName);
		if (iClient == -1) {
			LogError("Failed to create bot");
			return;
		}

		Bot mBot = Bot.Instance();
		g_hBots.Push(mBot);
		g_mBotClients[iClient] = mBot;

		mBot.iEntity = iClient;

		mBot.bActive = true;
		mBot.SetDefaultName(sName);

		mBot.mOpMain = SMBL_NewOperation("SMBL.MainLoop");

// 		g_eBot[iClient].eOp.iOp = Op_Invalid;
// 		g_eBot[iClient].eOp.iUID = 0;

		TF2_SetPlayerClass(iClient, view_as<TFClassType>(iRandomClass));

		if (iBlueCount > iRedCount) {
			TF2_ChangeClientTeam(iClient, TFTeam_Red);
			iRedCount++;
		} else {
			TF2_ChangeClientTeam(iClient, TFTeam_Blue);
			iBlueCount++;
		}

// 		g_eBot[iClient].iLastNavPointIdx = -1;

		mBot.SetPID(PID_DEFAULT);

// 		TF2_RespawnPlayer(iClient);

		g_iBotClientsCount++;
		iPlayerCount++;

		Call_StartForward(g_hOnBotAddForward);
		Call_PushCell(mBot);
		Call_Finish();
	}
}

void RemoveBots() {
	int iBotsLength = g_hBots.Length;
	for (int i=0; i<iBotsLength; i++) {
		Bot mBot = g_hBots.Get(i);
// 		int iClient = mBot.iEntity;
// 		if (1 <= iClient <= MaxClients && IsClientInGame(iClient)) {
// 			KickClient(iClient, "SMBL plugin terminating");
// 		}
		mBot.CleanUp();
	}

	Array_Fill(g_mBotClients, sizeof(g_mBotClients), NULL_BOT);
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

// Angle Helpers

void ClipAngle(float &fValue, float fMin=-360.0, float fMax=360.0) {
	if (fValue < fMin) {
		fValue = fMin;
	} else if (fValue > fMax) {
		fValue = fMax;
	}
}

void NormalizeAngle(float &fAngle) {
	if (fAngle < 0.0) {
		fAngle += 360.0;
	} else if (fAngle > 360.0) {
		fAngle -= 360.0;
	}
}

int GetAngDiff(float fAngA, float fAngB, float &fDiff) {
	fDiff = fAngA - fAngB;
	if (fDiff < -180.0) {
		fDiff += 360.0;

		ClipAngle(fDiff);
		return -1;
	} else if (fDiff > 180.0) {
		fDiff -= 360.0;
	}

	ClipAngle(fDiff);
	return 1;
}

// Stocks

stock void TF2_GetClassName(TFClassType iClass, char[] sName, int iMaxLength) {
	char sClass[10][10] = {"unknown", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer"};
	strcopy(sName, iMaxLength, sClass[view_as<int>(iClass)]);
}

stock void TF2_GetClassChars(TFClassType iClass, char[] sChars, int iMaxLength) {
	char sClassChars[10][4] = {"unk", "sc", "sn", "so", "dm", "md", "hw", "py", "sp", "en"};
	strcopy(sChars, iMaxLength, sClassChars[view_as<int>(iClass)]);
}
