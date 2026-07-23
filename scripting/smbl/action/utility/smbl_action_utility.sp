#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#define POSITIVE_INFINITY	view_as<float>(0x7F800000)

#include <smlib/entities>
#include <smlib/math>

#include <smbl>

#include "parameterize/byposition.sp"


public Plugin myinfo = {
	name = "SMBL Bot Actions Utility Library",
	author = PLUGIN_AUTHOR,
	description = "Utility operations",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "smbl")) {
		Setup_Utilities();
	}
}

// Helpers

void Setup_Utilities() {
	Operation.Register("Utility.Parameterize.ByPosition", Parameterize_ByPosition_Init);
}
