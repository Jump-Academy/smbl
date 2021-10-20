void SetupControllerNatives() {
// 	CreateNative("Controller.GetIdentifier", 	Native_Controller_GetIdentifier);
// 	CreateNative("Controller.hPlugin.get", 		Native_Controller_GetPlugin);

	CreateNative("SMBL_RegisterController", Native_RegisterController);
	CreateNative("SMBL_DeregisterController", Native_DeregisterController);

	CreateNative("SMBL_AttachController", Native_AttachController);
	CreateNative("SMBL_DetachController", Native_DetachController);
}

// public int Native_Controller_GetPlugin(Handle hPlugin, int iArgC) {
// 	int iThis = GetNativeCell(1);
	
// }

public int Native_RegisterController(Handle hPlugin, int iArgC) {
	TFClassType iClass = GetNativeCell(2);
	if (!(TFClass_Scout <= iClass <= TFClass_Engineer)) {
		ThrowError("Invalid class: %d", iClass);
	}

	ArrayList hControllers = g_hControllers[view_as<int>(iClass)];
	if (!hControllers) {
		g_hControllers[view_as<int>(iClass)] = hControllers = new ArrayList(sizeof(Controller));
	}

	Controller eController;
	GetNativeString(1, eController.sIdentifier, sizeof(Controller::sIdentifier));

	if (hControllers.FindString(eController.sIdentifier) != -1) {
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

	g_hControllers[view_as<int>(iClass)].PushArray(eController);

	char sClassName[32];
	TF2_GetClassName(iClass, sClassName, sizeof(sClassName));

	PrintToServer("SMBL registered controller: %s (%s)", eController.sIdentifier, sClassName);
}

public int Native_DeregisterController(Handle hPlugin, int iArgC) {
	TFClassType iClass = GetNativeCell(2);

	if (iClass == TFClass_Unknown) {
		if (IsNativeParamNullString(1)) {
			for (TFClassType i=TFClass_Scout; i<=TFClass_Engineer; i++) {
				ArrayList hControllers = g_hControllers[view_as<int>(i)];
				if (!hControllers) {
					continue;
				}

				int iIdx;
				while ((iIdx = hControllers.FindValue(hPlugin, Controller::hPlugin)) != -1) {
					Controller eController;
					hControllers.GetArray(iIdx, eController);
					hControllers.Erase(iIdx);

					char sClassName[32];
					TF2_GetClassName(i, sClassName, sizeof(sClassName));

					PrintToServer("SMBL deregistered controller: %s (%s)", eController.sIdentifier, sClassName);
				}
			}

			return true;
		}

		char sIdentifier[64];
		GetNativeString(1, sIdentifier, sizeof(sIdentifier));

		for (TFClassType i=TFClass_Scout; i<=TFClass_Engineer; i++) {
			ArrayList hControllers = g_hControllers[view_as<int>(i)];
			if (!hControllers) {
				continue;
			}

			int iIdx = hControllers.FindString(sIdentifier);
			if (iIdx != -1) {
				Controller eController;
				hControllers.GetArray(iIdx, eController);

				if (eController.hPlugin != hPlugin) {
					char sPluginName[64];
					GetPluginInfo(eController.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
					ThrowError("Controller (%s) may only be deregistered from originating plugin: %s", sIdentifier, sPluginName);
				}

				char sClassName[32];
				TF2_GetClassName(i, sClassName, sizeof(sClassName));

				hControllers.Erase(iIdx);

				PrintToServer("SMBL deregistered controller: %s (%s)", eController.sIdentifier, sClassName);
			}
		}

		return true;
	} else {
		if (!(TFClass_Scout <= iClass <=TFClass_Engineer)) {
			ThrowError("Invalid class: %d", iClass);
		}

		ArrayList hControllers = g_hControllers[view_as<int>(iClass)];
		if (!hControllers) {
			return false;
		}

		char sClassName[32];
		TF2_GetClassName(iClass, sClassName, sizeof(sClassName));

		if (IsNativeParamNullString(1)) {
			int iIdx;
			while ((iIdx = hControllers.FindValue(hPlugin, Controller::hPlugin)) != -1) {
				Controller eController;
				hControllers.GetArray(iIdx, eController);
				hControllers.Erase(iIdx);

				PrintToServer("SMBL deregistered controller: %s (%s)", eController.sIdentifier, sClassName);
			}

			return true;
		}

		char sIdentifier[64];
		GetNativeString(1, sIdentifier, sizeof(sIdentifier));

		int iIdx = hControllers.FindString(sIdentifier);
		if (iIdx != -1) {
			Controller eController;
			hControllers.GetArray(iIdx, eController);

			if (eController.hPlugin != hPlugin) {
				char sPluginName[64];
				GetPluginInfo(eController.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
				ThrowError("Controller (%s) may only be deregistered from originating plugin: %s", eController.sIdentifier, sPluginName);
			}

			hControllers.Erase(iIdx);

			PrintToServer("SMBL deregistered controller: %s (%s)", eController.sIdentifier, sClassName);

			return true;
		}
	}

	return false;
}

public int Native_AttachController(Handle hPlugin, int iArgC) {
	Bot mBot = GetNativeCell(1);

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

	ArrayList hControllers = g_hControllers[view_as<int>(iClass)];

	bool bFound = false;
	if (hControllers) {
		int iControllersLength = hControllers.Length;
		for (int i=0; i<iControllersLength; i++) {
			Controller eController;
			hControllers.GetArray(i, eController);

			if (StrEqual(eController.sIdentifier, sController)) {
				_Bot eBot;
				g_hBots.GetArray(view_as<int>(mBot)-1, eBot);
				eBot.eController = eController;
				g_hBots.SetArray(view_as<int>(mBot)-1, eBot);
				bFound = true;

				PrintToServer("SMBL controller attached to %N: %s (%s)", iEntity, sController, sClassName);
			}
		}
	}

	if (!bFound) {
		PrintToServer("SMBL controller not found: %s (%s)", sController, sClassName);
		return false;
	}

	return true;
}

public int Native_DetachController(Handle hPlugin, int iArgC) {
	Bot mBot = GetNativeCell(1);

	Controller eController;
	_Bot eBot;
	g_hBots.GetArray(view_as<int>(mBot)-1, eBot);
	eBot.eController = eController;
	g_hBots.SetArray(view_as<int>(mBot)-1, eBot);

	int iEntity = mBot.iEntity;
	if (Client_IsValid(iEntity)) {
		PrintToServer("SMBL cleared controller from %N", iEntity);
	}
}
