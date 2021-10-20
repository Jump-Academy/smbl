#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#define DIRECTOR_ALIAS "Debugger"

#include <smlib/clients>

#include <smbl>

#define POSITIVE_INFINITY	view_as<float>(0x7F800000)

#define COLOR_WHITE		{255, 255, 255, 255}
#define COLOR_RED		{255, 0, 0, 255}
#define COLOR_BLUE		{0, 0, 255, 255}

bool g_bDebugger[MAXPLAYERS+1];

int g_iLaser;
int g_iHalo;

public Plugin myinfo = {
	name = "SMBL Debug Director",
	author = PLUGIN_AUTHOR,
	description = "Bot director for debugging and manual bot control",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("smbl_director_debug_version", PLUGIN_VERSION, "SMBL debug director version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	RegAdminCmd("SMBL_debug", cmdDebug, ADMFLAG_ROOT, "Show SMBL debug menu");
	RegAdminCmd("SMBL_debug_goto", cmdGoTo, ADMFLAG_ROOT, "Set bot movement destination");

	LoadTranslations("common.phrases.txt");
}

public void OnPluginEnd() {
	SMBL_DeregisterDirector();
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "SMBL")) {
		SMBL_RegisterDirector(DIRECTOR_ALIAS, DirectorPriority_Admin, Director_Think);
	}
}

public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");

	Array_Fill(g_bDebugger, sizeof(g_bDebugger), false);
}

public void OnClientDisconnect(int iClient) {
	g_bDebugger[iClient] = false;
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float vecVel[3], float vecAng[3], int &iWeapon) {
	if (!IsFakeClient(iClient)) {
		return Plugin_Continue;
	}

	Bot mBot = SMBL_GetBotClient(iClient);
	if (!mBot) {
		return Plugin_Continue;
	}

	RefillAmmo(iClient);

	static int iDebuggers[MAXPLAYERS + 1];
	int iDebuggerCount = GetDebuggers(iDebuggers);
	if (!iDebuggerCount) {
		return Plugin_Continue;
	}

	float vecPos[3];
	float vecPosTarget[3];
	float vecVelAbs[3];
	float vecTemp[3];

	GetClientAbsOrigin(iClient, vecPos);
	Entity_GetAbsVelocity(iClient, vecVelAbs);

	float fVel2D = SquareRoot(vecVelAbs[0]*vecVelAbs[0] + vecVelAbs[1]*vecVelAbs[1]);

	int iTeamColor[4];
	switch (TF2_GetClientTeam(iClient)) {
		case TFTeam_Red:
			iTeamColor = COLOR_RED;
		case TFTeam_Blue:
			iTeamColor = COLOR_BLUE;
		default:
			iTeamColor = COLOR_WHITE;
	}

	Panel hDebugPanel;

	for (int i=0; i<iDebuggerCount; i++) {
		int iObsTarget = Client_GetObserverTarget(iDebuggers[i]);
		if (iClient == iObsTarget) {
			if (!hDebugPanel) {
				hDebugPanel = new Panel();

				char sBuffer[128];
				FormatEx(sBuffer, sizeof(sBuffer), "=== %N ===", iClient);
				hDebugPanel.SetTitle(sBuffer);
				hDebugPanel.DrawText(" ");

				int iTarget = mBot.iTarget;
				if (iTarget && iTarget != iClient) {
					Entity_GetAbsOrigin(iTarget, vecPosTarget);
					SubtractVectors(vecPos, vecPosTarget, vecTemp);
					vecTemp[2] = 0.0;
					FormatEx(sBuffer, sizeof(sBuffer), "Target: %N", iTarget);
					hDebugPanel.DrawText(sBuffer);
					hDebugPanel.DrawText(" ");
				} else {
					mBot.GetMoveTo(vecPosTarget);
					SubtractVectors(vecPosTarget, vecPos, vecTemp);
					vecTemp[2] = 0.0;
					hDebugPanel.DrawText("Target: None");
					hDebugPanel.DrawText(" ");
				}

				DrawDebugLine(vecPos, vecPosTarget, iTeamColor, 0.1, 1.0, iDebuggers[i], 1);

				FormatEx(sBuffer, sizeof(sBuffer), "Ang: %.1f %.1f\n", vecAng[0], vecAng[1]);
				hDebugPanel.DrawText(sBuffer);
				hDebugPanel.DrawText(" ");

				FormatEx(sBuffer, sizeof(sBuffer), "Dist2D: %.1f\nDist3D: %.1f\nAlt: %.1f\n", GetVectorLength(vecTemp), GetVectorDistance(vecPos, vecPosTarget), GetAltitude(vecPos));
				hDebugPanel.DrawText(sBuffer);
				hDebugPanel.DrawText(" ");

				FormatEx(sBuffer, sizeof(sBuffer), "Vel2D: %.1f\nVel3D: %.1f\nVelZ: %.1f\n", fVel2D, GetVectorLength(vecVelAbs), vecVelAbs[2]);
				hDebugPanel.DrawText(sBuffer);
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

// Custom callbacks

public void Director_Think() {
// 	PrintToServer("Debug Director: Think");
}

public bool TraceEntityFilter_Environment(int iEntity, int iContentsMask) {
	return false;
}

// Helpers

int GetDebuggers(int iClients[MAXPLAYERS+1]) {
	int iCount = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && g_bDebugger[i]) {
			iClients[iCount++] = i;
		}
	}

	return iCount;
}

float GetTraceEndpoint(const float vecPos[3], const float vecAng[3], float vecPosEnd[3], float vecNormal[3]=NULL_VECTOR) {
	Handle hTr = TR_TraceRayFilterEx(vecPos, vecAng, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilter_Environment);
	if (TR_DidHit(hTr)) {
		TR_GetEndPosition(vecPosEnd, hTr);
		TR_GetPlaneNormal(hTr, vecNormal);
		delete hTr;

		return GetVectorDistance(vecPos, vecPosEnd);
	}
	delete hTr;

	return 0.0;
}

float GetAltitude(float vecPos[3]) {
	float vecAng[3] = {90.0, 0.0, 0.0};
	float fAltitude = POSITIVE_INFINITY; // +inf

	Handle hTr = TR_TraceRayFilterEx(vecPos, vecAng, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilter_Environment);
	if (TR_DidHit(hTr)) {
		float vecGround[3];
		TR_GetEndPosition(vecGround, hTr);

		fAltitude = vecPos[2] - vecGround[2];
	}
	delete hTr;

	return fAltitude;
}

void RefillAmmo(int iClient) {
	int iWeapon = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Primary);
	if (iWeapon != -1) {
		int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
		if(iAmmoType != -1) {
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 20, _, iAmmoType);
		}

		SetEntProp(iWeapon, Prop_Data, "m_iClip1", 4);
	}
}

// Draw debugging functions

void DrawDebugLine(float vecPosA[3], float vecPosB[3], int iColor[4], float fLife=0.1, float fThickness=1.0, int[] iClients=0, int iClientCount=-1) {
	TE_SetupBeamPoints(vecPosA, vecPosB, g_iLaser, g_iHalo, 0, 66, fLife, fThickness, fThickness, 1, 0.0, iColor, 0);
	if (iClientCount == -1) {
		TE_SendToAll();
	} else {
		TE_Send(iClients, iClientCount);
	}
}

// Commands

public Action cmdDebug(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[SMBL] This command cannot be run from server console.");
		return Plugin_Handled;
	}

	g_bDebugger[iClient] = !g_bDebugger[iClient];

	ReplyToCommand(iClient, "[SMBL] Debugger %s", g_bDebugger[iClient] ? "enabled" : "disabled");

	if (iArgC == 1) {
		char sArg1[32];
		GetCmdArg(1, sArg1, sizeof(sArg1));

		int iTarget;
		if ((iTarget = FindTarget(iClient, sArg1)) != -1 && IsFakeClient(iTarget) && SMBL_GetBotClient(iTarget)) {
			Client_SetObserverTarget(iClient, iTarget);
		}
	} else {
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && IsFakeClient(i) && SMBL_GetBotClient(i)) {
				Client_SetObserverTarget(iClient, i);
				return Plugin_Handled;
			}
		}
	}

// 	SendDebugMenu(iClient);
	return Plugin_Handled;
}

public Action cmdGoTo(int iClient, int iArgC) {
	if (iArgC != 1 && iArgC != 2) {
		ReplyToCommand(iClient, "[SMBL] Usage: smbl_debug_goto <bot> [append (0/1)]");
		return Plugin_Handled;
	}

	bool bAppend = false;
	if (iArgC ==2) {
		char sArg2[32];
		GetCmdArg(2, sArg2, sizeof(sArg2));

		bAppend = StringToInt(sArg2) != 0;
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	int iTarget = FindTarget(iClient, sArg1);
	if (iTarget != -1) {
		Bot mBot = SMBL_GetBotClient(iTarget);
		if (!mBot) {
			ReplyToCommand(iClient, "[SMBL] %N is not an BOT.", iTarget);
			return Plugin_Handled;
		}

		float vecPos[3], vecAng[3];
		GetClientEyePosition(iClient, vecPos);
		GetClientEyeAngles(iClient, vecAng);

		float vecAimPos[3];
		GetTraceEndpoint(vecPos, vecAng, vecAimPos);

// 		mBot.SetMoveTo(vecAimPos);
		any aData[16];
		aData[0] = vecAimPos[0];
		aData[1] = vecAimPos[1];
		aData[2] = vecAimPos[2];
		SMBL_NewOperation("Common.Walk", aData, mBot.mOpMain);
	}

	return Plugin_Handled;
}

// Menus

void SendDebugMenu(int iClient) {
	Panel hPanel = new Panel();
	hPanel.SetTitle("SMBL Debug");
	hPanel.DrawText(" ");

	hPanel.DrawItem("Bots");

	hPanel.DrawText(" ");

	hPanel.CurrentKey = 10;
	hPanel.DrawItem("Exit");

	hPanel.Send(iClient, MenuHandler_Debug, 5);
}

void SendBotListMenu(int iClient) {
	char sBuffer[MAX_NAME_LENGTH];

	Menu hMenu = new Menu(MenuHandler_BotList);
	hMenu.SetTitle("Select a bot");

	ArrayList hBots = new ArrayList();
	int iBotsLength = SMBL_GetBots(hBots);
	for (int i=0; i<iBotsLength; i++) {
		Bot mBot = hBots.Get(i);
		int iEntity = mBot.iEntity;
		if (Client_IsValid(iEntity)) {
			GetClientName(iEntity, sBuffer, sizeof(sBuffer));
		} else {
			mBot.GetDefaultName(sBuffer, sizeof(sBuffer));
		}

		hMenu.AddItem(NULL_STRING, sBuffer);
	}
	delete hBots;

	hMenu.Display(iClient, 0);
}

public int MenuHandler_Debug(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			switch (iOption) {
				case 1: {
					SendBotListMenu(iClient);
				}
				default: {
					g_bDebugger[iClient] = false;
				}
			}
		}
	}
}

public int MenuHandler_BotList(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			
		}

		case MenuAction_Cancel: {
			if (iOption == MenuCancel_ExitBack) {
				SendDebugMenu(iClient);
			}
		}

		case MenuAction_End: {
			delete hMenu;
		}
	}
}
