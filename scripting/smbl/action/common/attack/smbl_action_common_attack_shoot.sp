#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <smlib/clients>
#include <smlib/entities>
#include <smlib/math>

#include <smbl>

#define PID_FAST		{0.10,	0.001,	0.01}

#define AIM_ERROR_TARGET	5.0

enum struct OpData_Shoot {
	int iTargetRef;
	float vecTargetPos[3];
	any aPadding[12];
}

public Plugin myinfo = {
	name = "SMBL Common Bot Actions Library: Shoot",
	author = PLUGIN_AUTHOR,
	description = "Shooting operations for all bot classes",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	SMBL_NotifyOnStart();
}

// Library forwards

public void SMBL_OnStart() {
	Operation.Register("Common.Attack.Shoot", Shoot_Init, Shoot_Validate, Shoot_PreRun, _, _, _, Shoot_Cleanup, true);
}

// Operation callbacks

OpRet Shoot_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Shoot eOpData) {
	int iTarget = hInitParams.GetNum("target");
	eOpData.iTargetRef = iTarget ? EntIndexToEntRef(iTarget) : INVALID_ENT_REFERENCE;

	if (hInitParams.JumpToKey("targetpos")) {
		hInitParams.GoBack();
		hInitParams.GetVector("targetpos", eOpData.vecTargetPos);
	} else if (!iTarget) {
		return mOp._Abort("missing targetpos init parameter");
	}

	return OpRet_Continue;
}

OpRet Shoot_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Shoot eOpData, float fStartTime) {
	if (eOpData.iTargetRef != INVALID_ENT_REFERENCE) {
		int iEntity = mBot.iEntity;

		int iTarget = EntRefToEntIndex(eOpData.iTargetRef);
		if (!iTarget || !IsValidEntity(iTarget) || (Client_IsValid(iTarget) && !IsPlayerAlive(iTarget)) || Entity_GetHealth(iTarget) <= 0) {
			return mOp._Abort("target entity is no longer valid");
		}

		float vecViewerPos[3];
		GetViewerPos(iEntity, vecViewerPos);

		float vecTargetPos[3];
		GetEntityMidpoint(iTarget, vecTargetPos);

		int iTeam = GetClientTeam(iEntity);

		TR_TraceRayFilter(vecViewerPos, vecTargetPos, MASK_SHOT_HULL, RayType_EndPoint, TraceEntityFilter_IgnoreTeam, iTeam);
		int iHitEntity = TR_GetEntityIndex();
		if (iHitEntity <= 0 || (TR_GetEntityIndex() != iTarget && GetClientTeam(iHitEntity) != GetClientTeam(iTarget))) {
			return mOp._Abort("target entity is not visible");
		}
	}

	return OpRet_Continue;
}

void Shoot_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Shoot eOpData) {
	if (mBot) {
		mBot.iButtons &= ~IN_ATTACK;
	}
}

// Custom callbacks

public bool TraceEntityFilter_IgnoreTeam(int iEntity, int iContentsMask, int iTeam) {
	// TODO: Non-client bot teams
	return SMBL_GetEntityBot(iEntity) && GetClientTeam(iEntity) != iTeam;
}

// Helpers

OpRet Shoot_PreRun(Bot mBot, Operation mOp, OpData_Shoot eOpData) {
	int iEntity = mBot.iEntity;

	float vecViewerPos[3], vecTargetPos[3];

	GetViewerPos(iEntity, vecViewerPos);

	if (eOpData.iTargetRef != INVALID_ENT_REFERENCE) {
		int iTarget = EntRefToEntIndex(eOpData.iTargetRef);
		GetEntityMidpoint(iTarget, vecTargetPos);
	} else {
		vecTargetPos = eOpData.vecTargetPos;
	}

	float vecDiff[3];
	SubtractVectors(vecTargetPos, vecViewerPos, vecDiff);

	float vecAng[3];
	GetVectorAngles(vecDiff, vecAng);

	mBot.SetPID(PID_FAST);
	mBot.SetAimTo(vecAng);

	float fPitchError, fYawError;
	mBot.GetAimError(fPitchError, fYawError);

	if (FloatAbs(fPitchError) < AIM_ERROR_TARGET && FloatAbs(fYawError) < AIM_ERROR_TARGET) {
		mBot.iButtons |= IN_ATTACK;
	} else {
		mBot.iButtons &= ~IN_ATTACK;
	}

	return OpRet_Continue;
}

void GetViewerPos(int iEntity, float vecViewerPos[3]) {
	float vecMins[3], vecMaxs[3], vecSize[3];

	if (1 <= iEntity < MaxClients) {
		GetClientEyePosition(iEntity, vecViewerPos);
	} else {
		// TODO: Custom bot viewer position
		Entity_GetAbsOrigin(iEntity, vecViewerPos);

		Entity_GetMinSize(iEntity, vecMins);
		Entity_GetMaxSize(iEntity, vecMaxs);

		// Midpoint
		SubtractVectors(vecMaxs, vecMins, vecSize);
		ScaleVector(vecSize, 0.5);
		AddVectors(vecViewerPos, vecSize, vecViewerPos);
	}
}

void GetEntityMidpoint(int iEntity, float vecMidpoint[3]) {
	float vecMins[3], vecMaxs[3];

	Entity_GetAbsOrigin(iEntity, vecMidpoint);

	Entity_GetMinSize(iEntity, vecMins);
	Entity_GetMaxSize(iEntity, vecMaxs);

	vecMidpoint[2] += 0.5*(vecMaxs[2]-vecMins[2]);
}
