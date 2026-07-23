#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <sourcemod>
#include <sdkhooks>

#include <smlib/arrays>
#include <smlib/clients>
#include <smlib/entities>
#include <tf2items>

#include <smbl>
#include <smbl/nav_mesh>

int g_iEntMGABlueSpawn;
int g_iEntMGARedSpawn;

bool g_bNavMeshLoaded = false;

Handle g_hSDKGetMaxClip1;

public Plugin myinfo = {
	name = "SMBL Game Mode - MGA",
	author = PLUGIN_AUTHOR,
	description = "Bot customizations for the Market Gardening Arena game mode",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("post_inventory_application", Event_Resupply,  EventHookMode_Post);
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Post);

	if (GetGameTime() > 5.0) {
		HookRegenTriggers();
	}

	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "gamedata/jse.regen.txt");
	if(FileExists(sFilePath)) {
		Handle hGameConf = LoadGameConfigFile("jse.regen");
		if(hGameConf != INVALID_HANDLE ) {
			StartPrepSDKCall(SDKCall_Entity);
			PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFWeaponBase::GetMaxClip1");
			PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_ByValue);
			g_hSDKGetMaxClip1 = EndPrepSDKCall();

			CloseHandle(hGameConf);
		}

		if (g_hSDKGetMaxClip1 == null) {
			LogError("Failed to load jse.regen gamedata.  Weapon clip regen will not be available.");
		}
	}

	SMBL_NotifyOnStart();
}

public void OnPluginEnd() {
	SMBL_DeregisterNavMesh("Ground");
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "smbl_nav_mesh")) {
		SetupNavMesh();
	}
}

public void OnLibraryRemoved(const char[] sName) {
	if (StrEqual(sName, "smbl_nav_mesh")) {
		g_bNavMeshLoaded = false;
	}
}

public void OnMapStart() {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

// 	if (StrContains(sMapName, "jump_academy_") != 0 && StrContains(sMapName, "mga_") != 0) {
// 		SetFailState("Not an MGA map");
// 	}

	g_iEntMGARedSpawn = FindEntityByName("info_target", "market_garden_red2_01");
	g_iEntMGABlueSpawn = FindEntityByName("info_target", "market_garden_blue2_01");

	if (LibraryExists("smbl_nav_mesh")) {
		SetupNavMesh();
	}

	CreateTimer(0.1, Timer_AmmoRegen, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd() {
	SMBL_DeregisterNavMesh("Ground");
	g_bNavMeshLoaded = false;
}

// Library forwards

public void SMBL_OnStart() {
	SetupBots();
}

public void SMBL_OnBotAdd(Bot mBot) {
	int iEntity = mBot.iEntity;
	if (Client_IsValid(iEntity)) {
		SetupBot(mBot);
	}
}

// Custom callbacks

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!SMBL_GetClientBot(iClient)) {
		return Plugin_Continue;
	}

	SetEntProp(iClient, Prop_Send, "m_bGlowEnabled", 1);

	float vecPos[3];
	if (IsValidEntity(g_iEntMGARedSpawn) && IsValidEntity(g_iEntMGABlueSpawn)) {
		if (TF2_GetClientTeam(iClient) == TFTeam_Red) {
			Entity_GetAbsOrigin(g_iEntMGARedSpawn, vecPos);
		} else {
			Entity_GetAbsOrigin(g_iEntMGABlueSpawn, vecPos);
		}

		TeleportEntity(iClient, vecPos, NULL_VECTOR, NULL_VECTOR);
		EquipMarketGardener(iClient);
		Client_SetFOV(iClient, 90);

// 		SetEntProp(iClient, Prop_Send, "m_bGlowEnabled", 1);
	}

	return Plugin_Continue;
}

public Action Event_Resupply(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (SMBL_GetClientBot(iClient)) {
		EquipMarketGardener(iClient);
	}

	return Plugin_Continue;
}

public Action Event_RoundStart(Event hEvent, const char[] sName, bool bDontBroadcast) {
	HookRegenTriggers();

	return Plugin_Continue;
}

public Action Hook_TouchRegen(int iEntity, int iOther) {
	if (Client_IsValid(iOther) && SMBL_GetClientBot(iOther)) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Timer_AmmoRegen(Handle hTimer) {
	for (int i=1; i<=MaxClients; i++) {
		if (Client_IsValid(i) && SMBL_GetClientBot(i)) {
			int iWeapon1 = GetPlayerWeaponSlot(i, TFWeaponSlot_Primary);
			if (iWeapon1 != -1) {
				int iAmmoType1 = GetEntProp(iWeapon1, Prop_Data, "m_iPrimaryAmmoType");
				GivePlayerAmmo(i, 500, iAmmoType1, true);

				int iMaxClip = SDKCall(g_hSDKGetMaxClip1, iWeapon1);
				SetEntProp(iWeapon1, Prop_Send, "m_iClip1", iMaxClip);
			}
		}
	}
	return Plugin_Continue;
}

// Helpers

int FindEntityByName(char sClassName[32], char sName[32]) {
	char sEntityName[32];

	int iEntity = -1;
	while ((iEntity = FindEntityByClassname(iEntity, sClassName)) != INVALID_ENT_REFERENCE) {
		GetEntPropString(iEntity, Prop_Data, "m_iName", sEntityName, sizeof(sEntityName));
		if (sEntityName[0] != 0 && StrEqual(sName, sEntityName)) {
			return iEntity;
		}
	}

	return INVALID_ENT_REFERENCE;
}

void EquipMarketGardener(int iClient) {
	if (TF2_GetPlayerClass(iClient) != TFClass_Soldier) {
		return;
	}

	int iWeapon = GetPlayerWeaponSlot(iClient, 2);
	RemovePlayerItem(iClient, iWeapon);
	RemoveEdict(iWeapon);

	Handle hWeaponMG = CreateMGWeaponHandle();
	iWeapon = TF2Items_GiveNamedItem(iClient, hWeaponMG);
	delete hWeaponMG;

	EquipPlayerWeapon(iClient, iWeapon);
}

Handle CreateMGWeaponHandle() {
	Handle hWeapon = TF2Items_CreateItem(OVERRIDE_ALL);
	TF2Items_SetClassname(hWeapon, "tf_weapon_shovel");
	TF2Items_SetItemIndex(hWeapon, 416);
	TF2Items_SetLevel(hWeapon, 10);
	TF2Items_SetQuality(hWeapon, 6);

	TF2Items_SetNumAttributes(hWeapon, 3);
	TF2Items_SetAttribute(hWeapon, 0, 267, 1.0); // Crit when airborne
	TF2Items_SetAttribute(hWeapon, 1, 15, 0.0); // No random crits
	TF2Items_SetAttribute(hWeapon, 2, 2, 1.1); // 10% damage bonus

	return hWeapon;
}

void SetupBots() {
	int iRed, iBlue;
	CountBotTeams(iRed, iBlue);

	if (iBlue == iRed) {
		return;
	}

	int iSwapCount;
	TFTeam iSourceTeam, iTargetTeam;

	if (iRed < iBlue) {
		iSwapCount = (iBlue-iRed)/2;

		iSourceTeam = TFTeam_Blue;
		iTargetTeam = TFTeam_Red;
	} else {
		iSwapCount = (iRed-iBlue)/2;

		iSourceTeam = TFTeam_Red;
		iTargetTeam = TFTeam_Blue;
	}

	for (int i=MaxClients; i>=1 && iSwapCount; i--) {
		if (!IsClientInGame(i) || !SMBL_GetClientBot(i)) {
			continue;
		}

		TFTeam iTeam = TF2_GetClientTeam(i);

		if (iTeam == iSourceTeam) {
			TF2_ChangeClientTeam(i, iTargetTeam);
			iSwapCount--;
		}
	}
}

void SetupBot(Bot mBot) {
	int iBotEntity = mBot.iEntity;
	if (!(1 <= iBotEntity <= MaxClients)) {
		return;
	}

	mBot.SetController("Soldier.Trolldier");

	int iRed, iBlue;
	CountBotTeams(iRed, iBlue);

	if (iRed == iBlue) {
		return;
	}

	TFTeam iTargetTeam = iRed < iBlue ? TFTeam_Red : TFTeam_Blue;
	TF2_ChangeClientTeam(iBotEntity, iTargetTeam);
}

void SetupNavMesh() {
	if (g_bNavMeshLoaded) {
		return;
	}

	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "data/smbl/nav/%s.snav", sMapName);
	NavMesh mNavMesh = NavMesh.LoadNavFile(sFilePath);
	SMBL_RegisterNavMesh("Ground", mNavMesh);

	g_bNavMeshLoaded = true;
}

void HookRegenTriggers() {
	int iEntity = -1;
	while ((iEntity = FindEntityByClassname(iEntity, "func_regenerate")) != INVALID_ENT_REFERENCE) {
		SDKHook(iEntity, SDKHook_Touch, Hook_TouchRegen);
	}
}

void CountBotTeams(int &iRed, int &iBlue) {
	iRed = iBlue = 0;

	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && SMBL_GetClientBot(i)) {
			switch (TF2_GetClientTeam(i)) {
				case TFTeam_Red:
					iRed++;
				case TFTeam_Blue:
					iBlue++;
			}
		}
	}
}
