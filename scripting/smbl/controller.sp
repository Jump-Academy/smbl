void SetupControllerNatives() {
	CreateNative("SMBL_RegisterController", Native_RegisterController);
	CreateNative("SMBL_DeregisterController", Native_DeregisterController);
}

public int Native_RegisterController(Handle hPlugin, int iArgC) {
	TFClassType iClass = GetNativeCell(2);
	if (!(TFClass_Scout <= iClass <= TFClass_Engineer)) {
		ThrowError("Invalid class: %d", iClass);
	}

	StringMap hControllers = g_hControllers[view_as<int>(iClass)];
	if (!hControllers) {
		g_hControllers[view_as<int>(iClass)] = hControllers = new StringMap();
	}

	Controller eController;
	GetNativeString(1, eController.sIdentifier, sizeof(Controller::sIdentifier));

	if (hControllers.ContainsKey(eController.sIdentifier)) {
		ThrowError("Controller with this identifier is already registered: %s", eController.sIdentifier);
	}

	eController.hPlugin = hPlugin;

	// ControllerThinkFunc
	eController.fnThink = GetNativeFunction(3);

	// ControllerMoveFunc
	eController.fnMove = GetNativeFunction(4);

	// ControllerEncounterFunc
	eController.fnEncounter = GetNativeFunction(5);

	// ControllerAttackFunc
	eController.fnAttack = GetNativeFunction(6);

	g_hControllers[view_as<int>(iClass)].SetArray(eController.sIdentifier, eController, sizeof(Controller));

	char sClassName[32];
	TF2_GetClassName(iClass, sClassName, sizeof(sClassName));

	PrintToServer("[SMBL] Registered controller: %s (%s)", eController.sIdentifier, sClassName);

	return 0;
}

public int Native_DeregisterController(Handle hPlugin, int iArgC) {
	TFClassType iClass = GetNativeCell(2);
	char sIdentifier[64];

	if (iClass == TFClass_Unknown) {
		if (IsNativeParamNullString(1)) {
			DeregisterPluginControllers(hPlugin);
			return true;
		}

		GetNativeString(1, sIdentifier, sizeof(sIdentifier));

		for (TFClassType i=TFClass_Scout; i<=TFClass_Engineer; i++) {
			StringMap hControllers = g_hControllers[view_as<int>(i)];
			if (!hControllers) {
				continue;
			}

			Controller eController;
			if (hControllers.GetArray(sIdentifier, eController, sizeof(Controller))) {
				if (eController.hPlugin != hPlugin) {
					char sPluginName[64];
					GetPluginInfo(eController.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
					ThrowError("Controller (%s) may only be deregistered from originating plugin: %s", sIdentifier, sPluginName);
				}

				char sClassName[32];
				TF2_GetClassName(i, sClassName, sizeof(sClassName));

				hControllers.Remove(sIdentifier);

				PrintToServer("[SMBL] Deregistered controller: %s (%s)", eController.sIdentifier, sClassName);
			}
		}

		return true;
	}

	if (!(TFClass_Scout <= iClass <=TFClass_Engineer)) {
		ThrowError("Invalid class: %d", iClass);
	}

	StringMap hControllers = g_hControllers[view_as<int>(iClass)];
	if (!hControllers) {
		return false;
	}

	char sClassName[32];
	TF2_GetClassName(iClass, sClassName, sizeof(sClassName));

	if (IsNativeParamNullString(1)) {
		StringMapSnapshot hSnapshot = hControllers.Snapshot();

		Controller eController;
		for (int i=0; i<hSnapshot.Length; i++) {
			hSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));
			hControllers.GetArray(sIdentifier, eController, sizeof(Controller));

			if (eController.hPlugin == hPlugin) {
				hControllers.Remove(sIdentifier);
				PrintToServer("[SMBL] Deregistered controller: %s (%s)", eController.sIdentifier, sClassName);
			}
		}

		delete hSnapshot;

		return true;
	}

	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	Controller eController;
	if (hControllers.GetArray(sIdentifier, eController, sizeof(Controller))) {
		if (eController.hPlugin != hPlugin) {
			char sPluginName[64];
			GetPluginInfo(eController.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
			ThrowError("Controller (%s) may only be deregistered from originating plugin: %s", eController.sIdentifier, sPluginName);
		}

		hControllers.Remove(sIdentifier);

		PrintToServer("[SMBL] Deregistered controller: %s (%s)", eController.sIdentifier, sClassName);

		return true;
	}

	return false;
}

// Helpers

void DeregisterPluginControllers(Handle hPlugin) {
	char sIdentifier[64];
	char sClassName[32];

	Controller eController;

	for (TFClassType i=TFClass_Scout; i<=TFClass_Engineer; i++) {
		StringMap hControllers = g_hControllers[view_as<int>(i)];
		if (!hControllers) {
			continue;
		}

		StringMapSnapshot hSnapshot = hControllers.Snapshot();

		for (int j=0; j<hSnapshot.Length; j++) {
			hSnapshot.GetKey(j, sIdentifier, sizeof(sIdentifier));
			hControllers.GetArray(sIdentifier, eController, sizeof(Controller));

			if (eController.hPlugin == hPlugin) {
				hControllers.Remove(sIdentifier);
				TF2_GetClassName(i, sClassName, sizeof(sClassName));

				PrintToServer("[SMBL] Deregistered controller: %s (%s)", eController.sIdentifier, sClassName);
			}
		}

		delete hSnapshot;
	}
}
