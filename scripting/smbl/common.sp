enum struct Director {
	char sIdentifier[64];
	Handle hPlugin;
	DirectorPriority iPriority;
	Function fnThink; // DirectorThinkFunc
}

enum struct Controller {
	char sIdentifier[64];
	Handle hPlugin;
	Function fnThink;		// ControllerThinkFunc
	Function fnMove;		// ControllerMoveFunc
	Function fnEncounter;	// ControllerEncounterFunc
	Function fnAttack;		// ControllerAttackFunc
}

enum struct _Bot {
	bool bActive;
	char sDefaultName[MAX_NAME_LENGTH];
	
	Controller eController;
	Operation mOpMain;

	int iEntity;
	int iTarget;
	int iButtons;

	float vecMoveTo[3];
	float vecAimTo[3];
	float vecAng[3];
	float vecAngError[3];

	float vecLocalVel[3];

	float vecPID[3];
	float fIError[2];

	bool bGCFlag;
}

ArrayList g_hDirectors;
Handle g_hDirectorThinkTimer;
float g_fDirectorThinkInterval;

ArrayList g_hControllers[TFClassType];

ArrayList g_hBots;
Bot g_mBotClients[MAXPLAYERS+1];
int g_iBotClientsCount;
