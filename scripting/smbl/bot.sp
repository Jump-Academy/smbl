GlobalForward g_hOnBotAddForward;
GlobalForward g_hOnBotRemoveForward;

static ArrayList m_hBots;

static Handle m_hSDKWeaponSwitch;

// Bot natives

void SetupBotNatives() {
	m_hBots = new ArrayList(sizeof(_Bot));

	g_hOnBotAddForward = new GlobalForward("SMBL_OnBotAdd", ET_Ignore, Param_Cell);
	g_hOnBotRemoveForward = new GlobalForward("SMBL_OnBotRemove", ET_Ignore, Param_Cell);

	CreateNative("Bot.bActive.get", 			Native_Bot_GetActive);
	CreateNative("Bot.bActive.set", 			Native_Bot_SetActive);

	CreateNative("Bot.GetDefaultName",			Native_Bot_GetDefaultName);
	CreateNative("Bot.SetDefaultName",			Native_Bot_SetDefaultName);

	CreateNative("Bot.SetController", 			Native_Bot_SetController);
	CreateNative("Bot.RemoveController", 		Native_RemoveController);

	CreateNative("Bot.mMainOperation.get", 		Native_Bot_GetMainOp);
	CreateNative("Bot.mMainOperation.set", 		Native_Bot_SetMainOp);

	CreateNative("Bot.iEntity.get", 			Native_Bot_GetEntity);
	CreateNative("Bot.iEntity.set", 			Native_Bot_SetEntity);

	CreateNative("Bot.iTarget.get", 			Native_Bot_GetTarget);
	CreateNative("Bot.iTarget.set", 			Native_Bot_SetTarget);

	CreateNative("Bot.iButtons.get", 			Native_Bot_GetButtons);
	CreateNative("Bot.iButtons.set", 			Native_Bot_SetButtons);


	CreateNative("Bot.GetMoveTo",				Native_Bot_GetMoveTo);
	CreateNative("Bot.SetMoveTo",				Native_Bot_SetMoveTo);

	CreateNative("Bot.GetAimTo",				Native_Bot_GetAimTo);
	CreateNative("Bot.SetAimTo",				Native_Bot_SetAimTo);

	CreateNative("Bot.GetAimError",				Native_Bot_GetAimError);

	CreateNative("Bot.GetLocalVelocity",		Native_Bot_GetLocalVelocity);
	CreateNative("Bot.SetLocalVelocity",		Native_Bot_SetLocalVelocity);

	CreateNative("Bot.GetPID",		 			Native_Bot_GetPID);
	CreateNative("Bot.SetPID",		 			Native_Bot_SetPID);

	CreateNative("Bot.SwitchWeapon",			Native_Bot_SwitchWeapon);

	CreateNative("Bot.CleanUp",		 			Native_Bot_Cleanup);

	CreateNative("Bot.Instance", 				Native_Bot_Instance);
	CreateNative("Bot.Destroy", 				Native_Bot_Destroy);

	CreateNative("SMBL_GetBots", 				Native_GetBots);
	CreateNative("SMBL_GetClientBot", 			Native_GetClientBot);
}

void SetupBotSDKCalls() {
	GameData hGameData = new GameData("sdkhooks.games");
	if (hGameData) {
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "Weapon_Switch");
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); // CBaseCombatWeapon* pWeapon
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // viewmodelindex = 0
		m_hSDKWeaponSwitch = EndPrepSDKCall();

		delete hGameData;
	}
}

public int Native_Bot_GetActive(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return m_hBots.Get(iThis, _Bot::bActive);
}

public int Native_Bot_SetActive(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	bool bActive = GetNativeCell(2);

	m_hBots.Set(iThis, bActive, _Bot::bActive);

	return 0;
}

public int Native_Bot_GetDefaultName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	
	int iMaxLength = GetNativeCell(3);

	_Bot eBot;
	m_hBots.GetArray(iThis, eBot);
	SetNativeString(2, eBot.sDefaultName, iMaxLength);

	return 0;
}

public int Native_Bot_SetDefaultName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_Bot eBot;
	m_hBots.GetArray(iThis, eBot);
	GetNativeString(2, eBot.sDefaultName, sizeof(_Bot::sDefaultName));	
	m_hBots.SetArray(iThis, eBot);

	return 0;
}

public int Native_Bot_SetController(Handle hPlugin, int iArgC) {
	Bot mBot = GetNativeCell(1);

	int iThis = view_as<int>(mBot)-1;

	char sController[64];
	GetNativeString(2, sController, sizeof(sController));

	int iEntity = mBot.iEntity;
	if (!Client_IsValid(iEntity)) {
		PrintToServer("SMBL currently only supports client controllers");
		return false;
	}

	TFClassType iClass = TF2_GetPlayerClass(iEntity);

	char sClassName[32];
	TF2_GetClassName(iClass, sClassName, sizeof(sClassName));

	StringMap hControllers = g_hControllers[view_as<int>(iClass)];

	_Bot eBot;
	m_hBots.GetArray(iThis, eBot);

	if (hControllers.GetArray(sController, eBot.eController, sizeof(_Bot::eController))) {
		m_hBots.SetArray(iThis, eBot);
		PrintToServer("SMBL controller set to %N: %s (%s)", iEntity, sController, sClassName);
	} else {
		PrintToServer("SMBL controller not found: %s (%s)", sController, sClassName);
		return false;
	}

	return true;
}

public int Native_RemoveController(Handle hPlugin, int iArgC) {
	Bot mBot = GetNativeCell(1);

	int iThis = view_as<int>(mBot)-1;

	_Bot eBot;
	m_hBots.GetArray(iThis, eBot);

	Controller eController;
	eBot.eController = eController;

	m_hBots.SetArray(iThis, eBot);

	int iEntity = eBot.iEntity;
	if (Client_IsValid(iEntity)) {
		PrintToServer("SMBL removed controller from %N", iEntity);
	}

	return 0;
}

public any Native_Bot_GetMainOp(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	OpRef mOpRef = m_hBots.Get(iThis, _Bot::mMainOpRef);
	return mOpRef.ToOperation();
}

public int Native_Bot_SetMainOp(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	Operation mMainOperation = GetNativeCell(2);

	m_hBots.Set(iThis, mMainOperation.ToOpRef(), _Bot::mMainOpRef);

	return 0;
}

public int Native_Bot_GetEntity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return EntRefToEntIndex(m_hBots.Get(iThis, _Bot::iEntity));
}

public int Native_Bot_SetEntity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEntity = EntIndexToEntRef(GetNativeCell(2));

	m_hBots.Set(iThis, iEntity, _Bot::iEntity);

	return 0;
}

public int Native_Bot_GetTarget(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return m_hBots.Get(iThis, _Bot::iTarget);
}

public int Native_Bot_SetTarget(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iTarget = GetNativeCell(2);

	m_hBots.Set(iThis, iTarget, _Bot::iTarget);

	return 0;
}

public int Native_Bot_GetButtons(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return m_hBots.Get(iThis, _Bot::iButtons);
}

public int Native_Bot_SetButtons(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iButtons = GetNativeCell(2);

	m_hBots.Set(iThis, iButtons, _Bot::iButtons);

	return 0;
}

public int Native_Bot_SwitchWeapon(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iWeaponSlot = GetNativeCell(2);

	int iEntity = EntRefToEntIndex(m_hBots.Get(iThis, _Bot::iEntity));
	if (!IsValidEntity(iEntity) || !Client_IsValid(iEntity)) {
		return -1;
	}

	int iWeapon = GetPlayerWeaponSlot(iEntity, iWeaponSlot);
	if (iWeapon == -1) {
		return -1;
	}

	if (m_hSDKWeaponSwitch) {
		SDKCall(m_hSDKWeaponSwitch, iEntity, iWeapon, 0);
	} else {
		Client_SetActiveWeapon(iEntity, iWeapon);
	}

	return iWeapon;
}

public int Native_Bot_GetPID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPID[3];
	vecPID[0] = m_hBots.Get(iThis, _Bot::vecPID  );
	vecPID[1] = m_hBots.Get(iThis, _Bot::vecPID+1);
	vecPID[2] = m_hBots.Get(iThis, _Bot::vecPID+2);

	SetNativeArray(2, vecPID, sizeof(vecPID));

	return 0;
}

public int Native_Bot_SetPID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPID[3];
	GetNativeArray(2, vecPID, sizeof(vecPID));

	m_hBots.Set(iThis, vecPID[0], _Bot::vecPID  );
	m_hBots.Set(iThis, vecPID[1], _Bot::vecPID+1);
	m_hBots.Set(iThis, vecPID[2], _Bot::vecPID+2);

	return 0;
}

public int Native_Bot_GetMoveTo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPos[3];
	vecPos[0] = m_hBots.Get(iThis, _Bot::vecMoveTo  );
	vecPos[1] = m_hBots.Get(iThis, _Bot::vecMoveTo+1);
	vecPos[2] = m_hBots.Get(iThis, _Bot::vecMoveTo+2);

	SetNativeArray(2, vecPos, sizeof(vecPos));

	return 0;
}

public int Native_Bot_SetMoveTo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPos[3];
	GetNativeArray(2, vecPos, sizeof(vecPos));

	m_hBots.Set(iThis, vecPos[0], _Bot::vecMoveTo  );
	m_hBots.Set(iThis, vecPos[1], _Bot::vecMoveTo+1);
	m_hBots.Set(iThis, vecPos[2], _Bot::vecMoveTo+2);

	return 0;
}

public int Native_Bot_GetAimTo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecAng[3];
	vecAng[0] = m_hBots.Get(iThis, _Bot::vecAimTo  );
	vecAng[1] = m_hBots.Get(iThis, _Bot::vecAimTo+1);
	vecAng[2] = m_hBots.Get(iThis, _Bot::vecAimTo+2);

	SetNativeArray(2, vecAng, sizeof(vecAng));

	return 0;
}

public int Native_Bot_SetAimTo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_Bot eBot;
	m_hBots.GetArray(iThis, eBot, sizeof(_Bot));

	GetNativeArray(2, eBot.vecAimTo[0], sizeof(_Bot::vecAimTo));

	GetAngDiff(eBot.vecAimTo[0], eBot.vecAng[0], eBot.vecAngError[0]);
	GetAngDiff(eBot.vecAimTo[1], eBot.vecAng[1], eBot.vecAngError[1]);

	m_hBots.SetArray(iThis, eBot, sizeof(_Bot));

	return 0;
}

public int Native_Bot_GetAimError(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	SetNativeCellRef(2, m_hBots.Get(iThis, _Bot::vecAngError  ));
	SetNativeCellRef(3, m_hBots.Get(iThis, _Bot::vecAngError+1));

	return 0;
}

public int Native_Bot_GetLocalVelocity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecLocalVel[3];
	vecLocalVel[0] = m_hBots.Get(iThis, _Bot::vecLocalVel  );
	vecLocalVel[1] = m_hBots.Get(iThis, _Bot::vecLocalVel+1);
	vecLocalVel[2] = m_hBots.Get(iThis, _Bot::vecLocalVel+2);

	SetNativeArray(2, vecLocalVel, sizeof(vecLocalVel));

	return 0;
}

public int Native_Bot_SetLocalVelocity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecLocalVel[3];
	GetNativeArray(2, vecLocalVel, sizeof(vecLocalVel));

	m_hBots.Set(iThis, vecLocalVel[0], _Bot::vecLocalVel  );
	m_hBots.Set(iThis, vecLocalVel[1], _Bot::vecLocalVel+1);
	m_hBots.Set(iThis, vecLocalVel[2], _Bot::vecLocalVel+2);

	return 0;
}

public int Native_Bot_Cleanup(Handle hPlugin, int iArgC) {
	Bot mBot = GetNativeCell(1);
	int iThis = view_as<int>(mBot)-1;

	int iEntity = EntRefToEntIndex(m_hBots.Get(iThis, _Bot::iEntity));
	if (iEntity <= 0) {
		return 0;
	}

	Call_StartForward(g_hOnBotRemoveForward);
	Call_PushCell(mBot);
	Call_Finish();

	OpRef mMainOpRef = m_hBots.Get(iThis, _Bot::mMainOpRef);
	Operation mMainOperation = mMainOpRef.ToOperation();
	if (mMainOperation) {
		Operation.Destroy(mMainOperation);
	}

	if (1 <= iEntity <= MaxClients) {
		if (IsClientInGame(iEntity)) {
			KickClient(iEntity);
		}
	} else {
		AcceptEntityInput(iEntity, "Kill");
	}

	return 0;
}

public any Native_Bot_Instance(Handle hPlugin, int iArgC) {
	_Bot eBot;

	int iFreeIdx = m_hBots.FindValue(true, _Bot::bGCFlag);
	if (iFreeIdx != -1) {
		m_hBots.SetArray(iFreeIdx, eBot);

		return iFreeIdx+1;
	}

	return m_hBots.PushArray(eBot)+1;
}

public any Native_Bot_Destroy(Handle hPlugin, int iArgC) {
	int iBotIdx = GetNativeCell(1)-1;
	if (iBotIdx < 0 || iBotIdx >= m_hBots.Length) {
		return 0;
	}

	m_hBots.Set(iBotIdx, true, _Bot::bGCFlag);

	SetNativeCellRef(1, NULL_BOT);

	if (iBotIdx == m_hBots.Length-1) {
		for (int i=iBotIdx; i>0; i--) {
			if (!m_hBots.Get(i-1, _Bot::bGCFlag)) {
				m_hBots.Resize(i);
				return 0;
			}
		}

		m_hBots.Clear();
	}

	return 0;
}

public int Native_GetBots(Handle hPlugin, int iArgC) {
	ArrayList hBots = GetNativeCell(1);

	int iBotsLength = g_hBots.Length;

	if (hBots) {
		for (int i=0; i<iBotsLength; i++) {
			hBots.Push(g_hBots.Get(i));
		}
	}

	return iBotsLength;
}

public any Native_GetClientBot(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	if (!Client_IsValid(iClient)) {
		ThrowError("Index %d is not a client", iClient);
	}

	return g_mClientBot[iClient];
}

// Helpers

public void AdjustAim(Bot mBot, float vecAng[3]) {
	int iBotIdx = view_as<int>(mBot)-1;

	_Bot eBot;
	m_hBots.GetArray(iBotIdx, eBot);

	float vecAngDiff[3];
	GetAngDiff(eBot.vecAimTo[0], eBot.vecAng[0], vecAngDiff[0]);
	GetAngDiff(eBot.vecAimTo[1], eBot.vecAng[1], vecAngDiff[1]);

	float vecPID[3];
	vecPID = eBot.vecPID;

	if (FloatAbs(vecAngDiff[1]) > 60.0) {
		vecPID[1] = vecPID[2] = 0.0;
	}

	eBot.vecAng[0] += (vecPID[0] * vecAngDiff[0]) + (vecPID[1] * eBot.fIError[0]) + vecPID[2] * (eBot.vecAngError[0] - vecAngDiff[0]);
	eBot.vecAng[1] += (vecPID[0] * vecAngDiff[1]) + (vecPID[1] * eBot.fIError[1]) + vecPID[2] * (eBot.vecAngError[1] - vecAngDiff[1]);

	ClipAngle(eBot.vecAng[0], -90.0, 90.0);
	NormalizeAngle(eBot.vecAng[1]);
	ClipAngle(eBot.vecAng[1]);

	vecAng = eBot.vecAng;

	eBot.vecAngError = vecAngDiff;

	eBot.fIError[0] += vecAngDiff[0];
	eBot.fIError[1] += vecAngDiff[1];

	ClipAngle(eBot.fIError[0], -180.0, 180.0);
	ClipAngle(eBot.fIError[1], -180.0, 180.0);

	m_hBots.SetArray(iBotIdx, eBot);
}

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
