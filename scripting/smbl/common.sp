enum struct Director {
	char sIdentifier[64];
	Handle hPlugin;
	DirectorPriority iPriority;
	Function fnThink; // DirectorThinkFunc
}

ArrayList g_hDirectors;
Handle g_hDirectorThinkTimer;
float g_fDirectorThinkInterval;

ArrayList g_hBots;
StringMap g_hBotEntities;
Bot g_mClientBot[MAXPLAYERS+1];
int g_iClientBotCount;
