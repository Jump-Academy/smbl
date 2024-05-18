enum struct OpData_MarketGarden_Swing {
	int iTargetEntRef;
	bool bAirborne;
	any aPadding[14];
}

enum struct SeqData_MarketGarden_Swing {
	int iSwingStartTick;
	any aPadding[15];
}

// Operation callbacks

OpRet MarketGarden_Swing_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_MarketGarden_Swing eOpData) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("unsupported TFClassType");
	}

	if (!hInitParams.JumpToKey("target")) {
		return mOp._Abort("missing target init parameter");
	}

	hInitParams.GoBack();
	int iTargetEntity = hInitParams.GetNum("target");
	eOpData.iTargetEntRef = EntIndexToEntRef(iTargetEntity);

	if (!IsValidEntity(iTargetEntity)) {
		return mOp._Abort("invalid target entity");
	}

	Sequence eSeq;

	eSeq.fnRun = MarketGarden_WaitAirborne;
	eSeq.sIdentifier = "Wait_Airborne";
	eSeq.iSeq = view_as<Seq>(0);
	hSequences.PushArray(eSeq);

	eSeq.fnRun = MarketGarden_PrepShovel;
	eSeq.iSeq = view_as<Seq>(1);
	eSeq.sIdentifier = "Prep_Shovel";
	hSequences.PushArray(eSeq);

	eSeq.fnRun = MarketGarden_Swing;
	eSeq.iSeq = view_as<Seq>(2);
	eSeq.sIdentifier = "Swing";
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

// Sequences

OpRet MarketGarden_WaitAirborne(Bot mBot, Operation mOp, OpData_MarketGarden_Swing eOpData, SeqData_MarketGarden_Swing eSeqData, float fStartTime) {
	if (!eOpData.bAirborne) {
		return OpRet_Continue;
	}

	return OpRet_Handled;
}

OpRet MarketGarden_PrepShovel(Bot mBot, Operation mOp, OpData_MarketGarden_Swing eOpData, SeqData_MarketGarden_Swing eSeqData, float fStartTime) {
	int iEntity = mBot.iEntity;
	int iMeleeWeapon = fStartTime ? GetPlayerWeaponSlot(iEntity, TFWeaponSlot_Melee) : mBot.SwitchWeapon(TFWeaponSlot_Melee);
	mBot.iButtons &= ~IN_ATTACK;

	if (GetGameTime() >= GetEntPropFloat(iMeleeWeapon, Prop_Send, "m_flNextPrimaryAttack")) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet MarketGarden_Swing(Bot mBot, Operation mOp, OpData_MarketGarden_Swing eOpData, SeqData_MarketGarden_Swing eSeqData, float fStartTime) {
	int iTargetEntity = EntRefToEntIndex(eOpData.iTargetEntRef);
	if (iTargetEntity == INVALID_ENT_REFERENCE) {
		return mOp._Abort("invalid target entity");
	}

	if (!IsPlayerAlive(iTargetEntity)) {
		return OpRet_Handled;
	}

	int iEntity = mBot.iEntity;

	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return mOp._Abort("landed before swing");
	}
	
	float vecTargetPos[3];
	Entity_GetAbsOrigin(iTargetEntity, vecTargetPos);

	float vecMins[3], vecMaxs[3];
	Entity_GetMinSize(iEntity, vecMins);
	Entity_GetMaxSize(iEntity, vecMaxs);

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	float vecVel[3];
	Entity_GetAbsVelocity(iEntity, vecVel);

	float fEntityGravityRatio = GetEntityGravity(iEntity);
	if (fEntityGravityRatio == 0.0) {
		fEntityGravityRatio = 1.0;
	}

	float fGravity = -g_hCVGravity.FloatValue * fEntityGravityRatio;

	const float fTimeAhead = 0.25;

	float vecPredictPos[3];

	// d = v0*t + 0.5*g*t^2 = (v0 + 0.5*g*t)*t
	vecPredictPos[0] = vecPos[0] + vecVel[0]*fTimeAhead;
	vecPredictPos[1] = vecPos[1] + vecVel[1]*fTimeAhead;
	vecPredictPos[2] = vecPos[2] + (vecVel[2] + 0.5*fGravity*fTimeAhead)*fTimeAhead;

	TFTeam iTeam = TF2_GetClientTeam(iEntity);

	TR_TraceHullFilter(vecPos, vecPredictPos, vecMins, vecMaxs, MASK_PLAYERSOLID, TraceEntityFilter_IgnoreTeam, iTeam);
	
	// Check if hit entity is not 0/worldspawn
	if (TR_DidHit() && TR_GetEntityIndex()) {
		mBot.iButtons |= IN_ATTACK | IN_DUCK;

		if (!eSeqData.iSwingStartTick) {
			eSeqData.iSwingStartTick = GetGameTickCount();
		} else if (GetGameTickCount() > eSeqData.iSwingStartTick + 30) {
			return OpRet_Handled;
		}

		return OpRet_Continue;
	}

	mBot.iButtons = IN_DUCK;

	return OpRet_Continue;
}

void MarketGarden_Swing_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_MarketGarden_Swing eOpData) {
	if (!mBot) {
		return;
	}

	mBot.iButtons = 0;
	mBot.SwitchWeapon(TFWeaponSlot_Primary);
}

// Custom callbacks

public bool TraceEntityFilter_IgnoreTeam(int iEntity, int iContentsMask, TFTeam iTeam) {
	if (1 <= iEntity <= MaxClients) {
		return TF2_GetClientTeam(iEntity) != iTeam;
	}

	return false;
}
