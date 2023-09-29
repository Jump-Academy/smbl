void SetupDirectorNatives() {
	CreateNative("SMBL_RegisterDirector", Native_RegisterDirector);
	CreateNative("SMBL_DeregisterDirector", Native_DeregisterDirector);
}

public int Native_RegisterDirector(Handle hPlugin, int iArgC) {
	Director eDirector;
	GetNativeString(1, eDirector.sIdentifier, sizeof(Director::sIdentifier));

	if (g_hDirectors.FindString(eDirector.sIdentifier) != -1) {
		ThrowError("Director with this identifier is already registered: %s", eDirector.sIdentifier);
	}

	eDirector.hPlugin = hPlugin;

	eDirector.iPriority = GetNativeCell(2);

	// DirectorThinkFunc
	eDirector.fnThink = GetNativeFunction(3);

	g_hDirectors.PushArray(eDirector);

	if (!g_hDirectorThinkTimer) {
		g_hDirectorThinkTimer = CreateTimer(g_fDirectorThinkInterval, Timer_DirectorThink, _, TIMER_REPEAT);
	}

	PrintToServer("SMBL registered director: %s", eDirector.sIdentifier);

	return 0;
}

public int Native_DeregisterDirector(Handle hPlugin, int iArgC) {
	if (IsNativeParamNullString(1)) {
		int iIdx;
		while ((iIdx = g_hDirectors.FindValue(hPlugin, Director::hPlugin)) != -1) {
			Director eDirector;
			g_hDirectors.GetArray(iIdx, eDirector);
			g_hDirectors.Erase(iIdx);

			PrintToServer("SMBL deregistered director: %s", eDirector.sIdentifier);
		}

		if (!g_hDirectors.Length) {
			delete g_hDirectorThinkTimer;
		}

		return true;
	}

	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	int iIdx = g_hDirectors.FindString(sIdentifier);
	if (iIdx != -1) {
		Director eDirector;
		g_hDirectors.GetArray(iIdx, eDirector);
		if (eDirector.hPlugin != hPlugin) {
			char sPluginName[64];
			GetPluginInfo(eDirector.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
			ThrowError("Director (%s) may only be deregistered from originating plugin: %s", sIdentifier, sPluginName);
		}

		g_hDirectors.Erase(iIdx);

		PrintToServer("SMBL deregistered director: %s", eDirector.sIdentifier);

		return true;
	}

	return false;
}
