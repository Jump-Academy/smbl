public void __MarkBotNativesAsOptional() {
	MarkNativeAsOptional("Bot.bActive.get");
	MarkNativeAsOptional("Bot.bActive.set");

// 	MarkNativeAsOptional("Bot.mController.get");
// 	MarkNativeAsOptional("Bot.mController.set");

	MarkNativeAsOptional("Bot.mOpMain.get");
	MarkNativeAsOptional("Bot.mOpMain.set");

	MarkNativeAsOptional("Bot.iEntity.get");
	MarkNativeAsOptional("Bot.iEntity.set");

	MarkNativeAsOptional("Bot.iTarget.get");
	MarkNativeAsOptional("Bot.iTarget.set");

	MarkNativeAsOptional("Bot.iButtons.get");
	MarkNativeAsOptional("Bot.iButtons.set");

	MarkNativeAsOptional("Bot.GetMoveTo");
	MarkNativeAsOptional("Bot.SetMoveTo");

	MarkNativeAsOptional("Bot.GetAimTo");
	MarkNativeAsOptional("Bot.SetAimTo");

	MarkNativeAsOptional("Bot.GetLocalVelocity");
	MarkNativeAsOptional("Bot.SetLocalVelocity");

	MarkNativeAsOptional("Bot.GetPID");
	MarkNativeAsOptional("Bot.SetPID");

	MarkNativeAsOptional("Bot.CleanUp");

	MarkNativeAsOptional("Bot.Instance");
	MarkNativeAsOptional("Bot.Destroy");
}

methodmap Bot {
	property bool bActive {
		public native get();
		public native set(bool bActive);
	}

// 	property Controller mController {
// 		public native get();
// 		public native set(Controller mController);
// 	}

	property Operation mOpMain {
		public native get();
		public native set(Operation mOp);
	}

	property int iEntity {
		public native get();
		public native set(int iEntity);
	}

	property int iTarget {
		public native get();
		public native set(int iTarget);
	}

	property int iButtons {
		public native get();
		public native set(int iButtons);	
	}

	public native void GetDefaultName(char[] sName, int iMaxLength);
	public native void SetDefaultName(char[] sName);

	public native void GetMoveTo(float vecPos[3]);
	public native void SetMoveTo(float vecPos[3]);

	public native void GetAimTo(float vecAng[3]);
	public native void SetAimTo(float vecAng[3]);

	public native void GetLocalVelocity(float vecLocalVel[3]);
	public native void SetLocalVelocity(float vecLocalVel[3]);

	public native void GetPID(float vecPID[3]);
	public native void SetPID(float vecPID[3]);

	public native void GetIErrors(float &fPitchIError, float &fYawIError);
	public native void SetIErrors(float fPitchIError, float fYawIError);

	public native void GetAngErrors(float &fPitchError, float &fYawError);
	public native void SetAngErrors(float fPitchError, float fYawError);

	public native void CleanUp();

	public static native Bot Instance();
	public static native void Destroy(Bot mBot);
}

#define NULL_BOT	view_as<Bot>(0)
