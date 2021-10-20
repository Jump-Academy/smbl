GlobalForward g_hOnBotAddForward;
GlobalForward g_hOnBotRemoveForward;

static ArrayList m_hBots;

// Bot natives

void SetupBotNatives() {
	m_hBots = new ArrayList(sizeof(_Bot));

	g_hOnBotAddForward = new GlobalForward("SMBL_OnBotAdd", ET_Ignore, Param_Cell);
	g_hOnBotRemoveForward = new GlobalForward("SMBL_OnBotRemove", ET_Ignore, Param_Cell);

// 	CreateNative("Bot.mController.get", 		Native_Bot_GetController);
// 	CreateNative("Bot.mController.set", 		Native_Bot_SetController);

	CreateNative("Bot.mOpMain.get", 			Native_Bot_GetOpMain);
	CreateNative("Bot.mOpMain.set", 			Native_Bot_SetOpMain);

	CreateNative("Bot.GetDefaultName",			Native_Bot_GetDefaultName);
	CreateNative("Bot.SetDefaultName",			Native_Bot_SetDefaultName);
	
	CreateNative("Bot.bActive.get", 			Native_Bot_GetActive);
	CreateNative("Bot.bActive.set", 			Native_Bot_SetActive);

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

	CreateNative("Bot.GetLocalVelocity",		Native_Bot_GetLocalVelocity);
	CreateNative("Bot.SetLocalVelocity",		Native_Bot_SetLocalVelocity);

	CreateNative("Bot.GetPID",		 			Native_Bot_GetPID);
	CreateNative("Bot.SetPID",		 			Native_Bot_SetPID);

	CreateNative("Bot.CleanUp",		 			Native_Bot_Cleanup);

	CreateNative("Bot.Instance", 				Native_Bot_Instance);
	CreateNative("Bot.Destroy", 				Native_Bot_Destroy);

	CreateNative("SMBL_GetBots", 				Native_GetBots);
	CreateNative("SMBL_GetBotClient", 			Native_GetBotClient);
}


public int Native_Bot_GetActive(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return m_hBots.Get(iThis, _Bot::bActive);
}

public int Native_Bot_SetActive(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	bool bActive = GetNativeCell(2);

	m_hBots.Set(iThis, bActive, _Bot::bActive);
}

public int Native_Bot_GetDefaultName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	
	int iMaxLength = GetNativeCell(3);

	_Bot eBot;
	m_hBots.GetArray(iThis, eBot);
	SetNativeString(2, eBot.sDefaultName, iMaxLength);	
}

public int Native_Bot_SetDefaultName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_Bot eBot;
	m_hBots.GetArray(iThis, eBot);
	GetNativeString(2, eBot.sDefaultName, sizeof(_Bot::sDefaultName));	
	m_hBots.SetArray(iThis, eBot);
}

// public int Native_Bot_GetController(Handle hPlugin, int iArgC) {
// 	int iThis = GetNativeCell(1)-1;

// 	return m_hBots.Get(iThis, _Bot::mController);
// }

// public int Native_Bot_SetController(Handle hPlugin, int iArgC) {
// 	int iThis = GetNativeCell(1)-1;
// 	Controller mController = GetNativeCell(2);

// 	m_hBots.Set(iThis, mController, _Bot::mController);
// }

public int Native_Bot_GetOpMain(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return m_hBots.Get(iThis, _Bot::mOpMain);
}

public int Native_Bot_SetOpMain(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	Operation mOpMain = GetNativeCell(2);

	m_hBots.Set(iThis, mOpMain, _Bot::mOpMain);
}

public int Native_Bot_GetEntity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return EntRefToEntIndex(m_hBots.Get(iThis, _Bot::iEntity));
}

public int Native_Bot_SetEntity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iEntity = EntIndexToEntRef(GetNativeCell(2));

	m_hBots.Set(iThis, iEntity, _Bot::iEntity);
}

public int Native_Bot_GetTarget(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return m_hBots.Get(iThis, _Bot::iTarget);
}

public int Native_Bot_SetTarget(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iTarget = GetNativeCell(2);

	m_hBots.Set(iThis, iTarget, _Bot::iTarget);
}

public int Native_Bot_GetButtons(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return m_hBots.Get(iThis, _Bot::iButtons);
}

public int Native_Bot_SetButtons(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iButtons = GetNativeCell(2);

	m_hBots.Set(iThis, iButtons, _Bot::iButtons);
}

public int Native_Bot_GetPID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPID[3];
	vecPID[0] = m_hBots.Get(iThis, _Bot::vecPID  );
	vecPID[1] = m_hBots.Get(iThis, _Bot::vecPID+1);
	vecPID[2] = m_hBots.Get(iThis, _Bot::vecPID+2);

	SetNativeArray(2, vecPID, sizeof(vecPID));
}

public int Native_Bot_SetPID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPID[3];
	GetNativeArray(2, vecPID, sizeof(vecPID));

	m_hBots.Set(iThis, vecPID[0], _Bot::vecPID  );
	m_hBots.Set(iThis, vecPID[1], _Bot::vecPID+1);
	m_hBots.Set(iThis, vecPID[2], _Bot::vecPID+2);
}

public int Native_Bot_GetMoveTo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPos[3];
	vecPos[0] = m_hBots.Get(iThis, _Bot::vecMoveTo  );
	vecPos[1] = m_hBots.Get(iThis, _Bot::vecMoveTo+1);
	vecPos[2] = m_hBots.Get(iThis, _Bot::vecMoveTo+2);

	SetNativeArray(2, vecPos, sizeof(vecPos));
}

public int Native_Bot_SetMoveTo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecPos[3];
	GetNativeArray(2, vecPos, sizeof(vecPos));

	m_hBots.Set(iThis, vecPos[0], _Bot::vecMoveTo  );
	m_hBots.Set(iThis, vecPos[1], _Bot::vecMoveTo+1);
	m_hBots.Set(iThis, vecPos[2], _Bot::vecMoveTo+2);
}

public int Native_Bot_GetAimTo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecAng[3];
	vecAng[0] = m_hBots.Get(iThis, _Bot::vecAimTo  );
	vecAng[1] = m_hBots.Get(iThis, _Bot::vecAimTo+1);
	vecAng[2] = m_hBots.Get(iThis, _Bot::vecAimTo+2);

	SetNativeArray(2, vecAng, sizeof(vecAng));
}

public int Native_Bot_SetAimTo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecAng[3];
	GetNativeArray(2, vecAng, sizeof(vecAng));

	m_hBots.Set(iThis, vecAng[0], _Bot::vecAimTo  );
	m_hBots.Set(iThis, vecAng[1], _Bot::vecAimTo+1);
	m_hBots.Set(iThis, vecAng[2], _Bot::vecAimTo+2);
}

public int Native_Bot_GetLocalVelocity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecLocalVel[3];
	vecLocalVel[0] = m_hBots.Get(iThis, _Bot::vecLocalVel  );
	vecLocalVel[1] = m_hBots.Get(iThis, _Bot::vecLocalVel+1);
	vecLocalVel[2] = m_hBots.Get(iThis, _Bot::vecLocalVel+2);

	SetNativeArray(2, vecLocalVel, sizeof(vecLocalVel));
}

public int Native_Bot_SetLocalVelocity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	float vecLocalVel[3];
	GetNativeArray(2, vecLocalVel, sizeof(vecLocalVel));

	m_hBots.Set(iThis, vecLocalVel[0], _Bot::vecLocalVel  );
	m_hBots.Set(iThis, vecLocalVel[1], _Bot::vecLocalVel+1);
	m_hBots.Set(iThis, vecLocalVel[2], _Bot::vecLocalVel+2);
}

public int Native_Bot_Cleanup(Handle hPlugin, int iArgC) {
	Bot mBot = GetNativeCell(1);
	int iThis = view_as<int>(mBot)-1;

	int iEntity = EntRefToEntIndex(m_hBots.Get(iThis, _Bot::iEntity));
	if (iEntity <= 0) {
		return;
	}

	Call_StartForward(g_hOnBotRemoveForward);
	Call_PushCell(mBot);
	Call_Finish();

	if (1 <= iEntity <= MaxClients) {
		if (IsClientInGame(iEntity)) {
			KickClient(iEntity);
		}
	} else {
		AcceptEntityInput(iEntity, "Kill");
	}
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
		return;
	}

	m_hBots.Set(iBotIdx, true, _Bot::bGCFlag);

	SetNativeCellRef(1, NULL_BOT);

	if (iBotIdx == m_hBots.Length-1) {
		for (int i=iBotIdx; i>0; i--) {
			if (!m_hBots.Get(i-1, _Bot::bGCFlag)) {
				m_hBots.Resize(i);
				return;
			}
		}

		m_hBots.Clear();
	}
}

public int Native_GetBots(Handle hPlugin, int iArgC) {
	ArrayList hBots = GetNativeCell(1);

	int iBotsLength = g_hBots.Length;
	for (int i=0; i<iBotsLength; i++) {
		hBots.Push(g_hBots.Get(i));
	}

	return hBots.Length;
}

public any Native_GetBotClient(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	if (!Client_IsValid(iClient)) {
		ThrowError("Index %d is not a client", iClient);
	}

	return g_mBotClients[iClient];
}

// Internal helpers

public void AdjustAim(Bot mBot, float vecAng[3]) {
	int iBotIdx = view_as<int>(mBot)-1;

	_Bot eBot;
	m_hBots.GetArray(iBotIdx, eBot);

	float vecAngDiff[3];
	GetAngDiff(eBot.vecAimTo[0], eBot.vecAng[0], vecAngDiff[0]);
	GetAngDiff(eBot.vecAimTo[1], eBot.vecAng[1], vecAngDiff[1]);

	float vecPID[3];
	vecPID = eBot.vecPID;

// 	PrintToServer("Adjusting aim with PID: %.1f, %.1f, %.1f", vecPID[0], vecPID[1], vecPID[2]);

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

// 	vecAng = eBot.vecAimTo;
}
