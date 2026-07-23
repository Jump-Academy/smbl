#pragma semicolon 1

// #define DEBUG
// #define DEBUG_DRAW_ALL_TRACES

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#define PRECISION_SAMPLING_RANGE		1000.0
#define PRECISION_SAMPLING_ITERATIONS	10

#define CONTROLLER_MESSAGE_BUCKET		"targets"

// #define DEFAULT_ASPECT_RATIO	1.77777777777777 // 4:3
#define DEFAULT_ASPECT_RATIO	1.0 // 1:1

#define TARGET_REFRESH_INTERVAL	0.25

#include <sourcemod>
#include <smlib/entities>
#include <smlib/math>

#include <smbl>
#include <smbl/controller>
#include <smbl/monitor>
#include <smbl/observable>

enum struct MonData_TargetAcquisition_FOV {
	float fHorizontalFOV;
	float fVerticalFOV;
	float fAspectRatio;
	any aPadding[29];
}

enum struct ContrMsgData_Target {
	int iEntityRef;
	Bot mBot;
	TFTeam iTeam;
	TFClassType iClass;
	float vecOrigin[3];
	any aPadding[25];
}

#if defined DEBUG
int g_iLaser;
int g_iHalo;

#define COLOR_RED			{255,   0,   0, 255}
#define COLOR_YELLOW		{255, 255,   0, 255}
#endif

public Plugin myinfo = {
	name = "SMBL Controller - Target Acquisition - FOV",
	author = PLUGIN_AUTHOR,
	description = "Field-of-view target acquisition monitor for controllers",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

#if defined DEBUG
public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
}
#endif

// Library forwards

public void SMBL_OnStart() {
	Monitor.Register("TargetAcquisition.FOV", TargetAcquisition_FOV_Init, TargetAcquisition_FOV_Think, TargetAcquisition_FOV_Cleanup);
}

// Monitor callbacks

public void TargetAcquisition_FOV_Init(Controller mContr, KeyValues hInitParams, MonData_TargetAcquisition_FOV eMonData, float &fThinkInterval) {
	fThinkInterval = hInitParams.GetFloat("interval", TARGET_REFRESH_INTERVAL);

	eMonData.fAspectRatio = hInitParams.GetFloat("aspect_ratio", DEFAULT_ASPECT_RATIO);
	eMonData.fHorizontalFOV = hInitParams.GetFloat("fov", 90.0);
	eMonData.fVerticalFOV = RadToDeg(2 * ArcTangent(Tangent(0.5 * DegToRad(eMonData.fHorizontalFOV)) / eMonData.fAspectRatio));

// 	int iEntity = mContr.mBot.iEntity;
	//Observable.WatchEvent(iEntity, "player_death", EventObservation_PlayerDeath_RemoveFromControllerTargetList, mContr);
}

public void TargetAcquisition_FOV_Think(Controller mContr, MonData_TargetAcquisition_FOV eMonData, float &fThinkInterval) {
	int iEntity = mContr.mBot.iEntity;

	float vecViewerPos[3], vecViewerAng[3];
	int iTeam;

	float vecMins[3], vecMaxs[3];

	if (1 <= iEntity <= MaxClients) {
		GetClientEyePosition(iEntity, vecViewerPos);
		GetClientEyeAngles(iEntity, vecViewerAng);
		iTeam = GetClientTeam(iEntity);
	} else {
		// TODO: Custom bot viewer position
		Entity_GetAbsOrigin(iEntity, vecViewerPos);
		Entity_GetAbsAngles(iEntity, vecViewerAng);

		Entity_GetMinSize(iEntity, vecMins);
		Entity_GetMaxSize(iEntity, vecMaxs);

		// Midpoint
		vecViewerPos[2] += 0.5*(vecMaxs[2]-vecMins[2]);

		// TODO: Custom non-client bot teams
		iTeam = 1;
	}

	float vecHitPos[3];
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) != iTeam) {
			if (TF2_IsPlayerInCondition(i, TFCond_Stealthed)) {
				continue;
			}

			if (TF2_GetPlayerClass(i) == TFClass_Spy) {
				if (TF2_IsPlayerInCondition(i, TFCond_Cloaked) && !TF2_IsPlayerInCondition(i, TFCond_CloakFlicker) && !TF2_IsPlayerInCondition(i, TFCond_Jarated) && !TF2_IsPlayerInCondition(i, TFCond_Milked)) {
					continue;
				}

				if (TF2_IsPlayerInCondition(i, TFCond_Disguised) && !TF2_IsPlayerInCondition(i, TFCond_Disguising) && GetDisguiseTeam(i) == iTeam && GetDisguiseTargetIndex(i) != iEntity) {
					continue;
				}
			}

			if (CheckTargetVisibility(iEntity, i, vecViewerPos, vecViewerAng, eMonData.fHorizontalFOV, eMonData.fVerticalFOV, vecHitPos)) {
				AppendControllerTargetList(mContr, i, SMBL_GetClientBot(i), vecHitPos);
			}
		}
	}

	// TODO: Custom non-client bot teams

	ArrayList hBots = new ArrayList();
	int iBotsCount = SMBL_GetBots(hBots);

	for (int i=0; i<iBotsCount; i++) {
		Bot mBot = hBots.Get(i);
		int iTargetEntity = mBot.iEntity;
		if (iEntity > MaxClients && iEntity != iTargetEntity) {
			if (CheckTargetVisibility(iEntity, iTargetEntity, vecViewerPos, vecViewerAng, eMonData.fHorizontalFOV, eMonData.fVerticalFOV, vecHitPos)) {
				AppendControllerTargetList(mContr, iEntity, mBot, vecHitPos);
			}
		}
	}

	delete hBots;
}

public void TargetAcquisition_FOV_Cleanup(Controller mContr, MonData eMonData) {
// 	int iEntity = mContr.mBot.iEntity;
// 	Observable.UnwatchEvent(iEntity, "player_death", EventObservation_PlayerDeath_RemoveFromControllerTargetList);
}

// Observable callbacks

public void EventObservation_PlayerDeath_RemoveFromControllerTargetList(int iEntity, Event hEvent, Controller mContr) {
	PrintToServer("Remove target %N from target list", iEntity);
	Observable.UnwatchEvent(iEntity, "player_death", EventObservation_PlayerDeath_RemoveFromControllerTargetList);

	ContrMsgBox mContrMsgBox = mContr.GetMessageBox("targets");

	int iIndex = mContrMsgBox.FindMessage(EntIndexToEntRef(iEntity), ContrMsgData_Target::iEntityRef);
	if (iIndex != -1) {
		mContrMsgBox.EraseMessage(iIndex);
	}
}

// Custom callbacks

public bool TraceEntityFilter_IgnoreViewerEntity(int iEntity, int iContentsMask, int iViewerEntity) {
	return iEntity != iViewerEntity;
}

// Helpers

bool CheckTargetVisibility(int iViewerEntity, int iTargetEntity, float vecViewerPos[3], float vecViewerAng[3], float fHorizontalFOV, float fVerticalFOV, float vecHitPos[3]=NULL_VECTOR) {
	float vecTargetPos[3];
	Entity_GetAbsOrigin(iTargetEntity, vecTargetPos);

	float vecMins[3], vecMaxs[3], vecSize[3];
	Entity_GetMinSize(iTargetEntity, vecMins);
	Entity_GetMaxSize(iTargetEntity, vecMaxs);
	SubtractVectors(vecMaxs, vecMins, vecSize);

	// Midpoint
	float vecSamplePos[3];
	vecSamplePos[0] = vecTargetPos[0];
	vecSamplePos[1] = vecTargetPos[1];
	vecSamplePos[2] = vecTargetPos[2] + 0.5*vecSize[2];

	float vecDiff[3];
	SubtractVectors(vecSamplePos, vecViewerPos, vecDiff);

	float vecAng[3];
	GetVectorAngles(vecDiff, vecAng);

	float fPitchAngDiff, fYawAngDiff;
	GetAngDiff(vecAng[0], vecViewerAng[0], fPitchAngDiff);
	GetAngDiff(vecAng[1], vecViewerAng[1], fYawAngDiff);

	if (FloatAbs(fYawAngDiff) < 0.5*fHorizontalFOV && FloatAbs(fPitchAngDiff) < 0.5*fVerticalFOV) {
		TR_TraceRayFilter(vecViewerPos, vecSamplePos, MASK_SHOT_HULL, RayType_EndPoint, TraceEntityFilter_IgnoreViewerEntity, iViewerEntity);
#if defined DEBUG
		if (TR_DidHit()) {
			if (TR_GetEntityIndex() == iTargetEntity) {
				vecHitPos = vecSamplePos;
				DrawDebugLine(vecViewerPos, vecSamplePos, COLOR_RED);
				return true;
			}

	#if defined DEBUG_DRAW_ALL_TRACES
				float vecBlockedPos[3];
				TR_GetEndPosition(vecBlockedPos);
				DrawDebugLine(vecViewerPos, vecBlockedPos, COLOR_YELLOW);
	#endif
		}
#else
		if (TR_DidHit() && TR_GetEntityIndex() == iTargetEntity) {
			vecHitPos = vecSamplePos;

			return true;
		}
#endif

		if (GetVectorDistance(vecViewerPos, vecTargetPos) < PRECISION_SAMPLING_RANGE) {
			for (int j=0; j<PRECISION_SAMPLING_ITERATIONS; j++) {
				vecSamplePos[0] = vecTargetPos[0] + vecMins[0] + GetURandomFloat()*vecSize[0];
				vecSamplePos[1] = vecTargetPos[1] + vecMins[1] + GetURandomFloat()*vecSize[1];
				vecSamplePos[2] = vecTargetPos[2]              + GetURandomFloat()*vecSize[2];

				TR_TraceRayFilter(vecViewerPos, vecSamplePos, MASK_SHOT_HULL, RayType_EndPoint, TraceEntityFilter_IgnoreViewerEntity, iViewerEntity);
#if defined DEBUG
				if (TR_DidHit()) {
					if (TR_GetEntityIndex() == iTargetEntity) {
						vecHitPos = vecSamplePos;
						DrawDebugLine(vecViewerPos, vecSamplePos, COLOR_RED);
						return true;
					}

	#if defined DEBUG_DRAW_ALL_TRACES
					float vecBlockedPos[3];
					TR_GetEndPosition(vecBlockedPos);
					DrawDebugLine(vecViewerPos, vecBlockedPos, COLOR_YELLOW);
	#endif
				}
#else
				if (TR_DidHit() && TR_GetEntityIndex() == iTargetEntity) {
					vecHitPos = vecSamplePos;
					return true;
				}
#endif
			}
		}
	}

	return false;
}

void AppendControllerTargetList(Controller mContr, int iEntity, Bot mBot, float vecOrigin[3]) {
	Observable.WatchEvent(iEntity, "player_death", EventObservation_PlayerDeath_RemoveFromControllerTargetList, mContr);

	ContrMsgBox mContrMsgBox = mContr.GetMessageBox("targets");

	ContrMsgData_Target eContrMsgData;
	eContrMsgData.iEntityRef = EntIndexToEntRef(iEntity);

	eContrMsgData.mBot = mBot;

	// TODO: Non-client bot teams
	if (1 <= iEntity <= MaxClients) {
		eContrMsgData.iTeam = TF2_GetClientTeam(iEntity);
		eContrMsgData.iClass = TF2_GetPlayerClass(iEntity);
	}

	eContrMsgData.vecOrigin = vecOrigin;

	float fExpiry = GetGameTime() + 5*TARGET_REFRESH_INTERVAL;

	int iIndex = mContrMsgBox.FindMessage(eContrMsgData.iEntityRef, ContrMsgData_Target::iEntityRef);
	if (iIndex == -1) {
		mContrMsgBox.PublishMessage(eContrMsgData, fExpiry);
	} else {
		mContrMsgBox.ReplaceMessage(iIndex, eContrMsgData, fExpiry);
	}
}

int GetDisguiseTeam(int iClient) {
	return GetEntProp(iClient, Prop_Send, "m_nDisguiseTeam");
}

int GetDisguiseTargetIndex(int iClient) {
	return GetEntPropEnt(iClient, Prop_Send, "m_hDisguiseTarget");
}

void ClipAngle(float &fValue, float fMin=-360.0, float fMax=360.0) {
	if (fValue < fMin) {
		fValue = fMin;
	} else if (fValue > fMax) {
		fValue = fMax;
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

#if defined DEBUG
void DrawDebugLine(float vecPos[3], float vecPos2[3], int iColor[4], float fLife=0.1) {
	TE_SetupBeamPoints(vecPos, vecPos2, g_iLaser, g_iHalo, 0, 66, fLife, 1.0, 1.0, 1, 0.0, iColor, 0);
	TE_SendToAll();
}
#endif
