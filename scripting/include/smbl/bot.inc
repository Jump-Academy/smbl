methodmap Bot {
	property bool bActive {
		public native get();
		public native set(bool bActive);
	}

	property Operation mMainOperation {
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

	public native bool SetController(char[] sIdentifier);
	public native void RemoveController();

	public native void GetMoveTo(float vecPos[3]);
	public native void SetMoveTo(float vecPos[3]);

	public native void GetAimTo(float vecAng[3]);
	public native void SetAimTo(float vecAng[3]);

	public native void GetAimError(float &fPitchError=0.0, float &fYawError=0.0);

	public native void GetLocalVelocity(float vecLocalVel[3]);
	public native void SetLocalVelocity(float vecLocalVel[3]);

	public native void GetPID(float vecPID[3]);
	public native void SetPID(float vecPID[3]);

	public native int SwitchWeapon(int iWeaponSlot);

	public native void CleanUp();

	public static native Bot Instance();
	public static native void Destroy(Bot mBot);
}

#define NULL_BOT	view_as<Bot>(0)
