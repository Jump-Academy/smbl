#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#define CONTROLLER_ALIAS "Generic"

#include <smbl>

public Plugin myinfo = {
	name = "SMBL Controller - All-class Generic",
	author = PLUGIN_AUTHOR,
	description = "Generical bot controller for any class",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "smbl")) {
		RegisterAllClasses();
	}
}

void RegisterAllClasses() {
	for (TFClassType i=TFClass_Scout; i<=TFClass_Engineer; i++) {
		SMBL_RegisterController(CONTROLLER_ALIAS, i, Controller_Think, Controller_Move, Controller_Encounter, Controller_Attack);
	}
}

public void Controller_Think(Bot mBot) {

}

public void Controller_Move(Bot mBot, float vecCoords[3]) {
	int iClient = mBot.iEntity;
	if (!IsPlayerAlive(iClient)) {
		return;
	}

	
}

public void Controller_Encounter(Bot mBot, int iOther) {

}

public void Controller_Attack(Bot mBot, int iTarget) {

}
