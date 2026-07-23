#include <smbl/controller>

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

	public native Controller GetController();
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

	public static native Bot Instance();

	/**
	 * Destroys the bot
	 *
	 * If the bot has an entity, it will be killed in the next frame.
	 * The associated main operation and controller will also be destroyed.
	 *
	 * @param mBot Reference to the bot to destroy, which will be set to NULL_BOT on success.
	 * @param sClientKickReason Optional kick reason for client bots only.
	 */
	public static native void Destroy(Bot &mBot, char[] sClientKickReason=NULL_STRING);
}

#define NULL_BOT	view_as<Bot>(0)
