public void __MarkOperationNativesAsOptional() {

}

enum Op {
	Op_Invalid = -1
}

enum OpState {
	OpState_Pend,
	OpState_Run,
	OpState_Suspend,
	OpState_Complete,
	OpState_Abort,
}

enum OpRet {
	OpRet_Continue,
	OpRet_Handled,
	OpRet_Restart,
	OpRet_Abort
}

enum Seq {
	Seq_Invalid = -1
}

typedef SeqFunc = function OpRet (Bot mBot, Operation mOp, any aOpData[16], any aSeqData[16], float fStartTime);

enum struct Sequence {
	char sIdentifier[64];
	Seq iSeq;
	int iUID;
	SeqFunc fnRun;

	float fStartTime;
	any aData[16];
}

typedef OpFunc = function OpRet (Bot mBot, Operation mOp, any aData[16]);
typedef OpInitFunc = function OpRet (Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, any aData[16]);
typedef OpValidateFunc = function OpRet (Bot mBot, Operation mOp, ArrayList hSequences, any aData[16], float fStartTime);
typedef CleanupFunc = function void (Bot mBot, Operation mOp, ArrayList hSequences, any aData[16]);

typedef OpStateChangeFwd = function void (Bot mBot, Operation mOp, OpState iOpState);
typedef OpStepFwd = function OpRet (Bot mBot, Operation mOp);
typedef OpAbortFwd = function void (Bot mBot, Operation mOp, char[] sError);

#define NULL_OPERATION	view_as<Operation>(0)
#define INVALID_OPERATION_REFERENCE	view_as<OpRef>(-1)

methodmap Operation {
	property Op iOp {
		public native get();
		public native set(Op iOp);
	}

	property OpState iOpState {
		public native get();
	}

	property KeyValues hInitParams {
		public native get();
	}

	property bool bLoop {
		public native get();
	}

	property bool bConcurrent {
		public native get();
	}

	property int iUID {
		public native get();
	}

	property ArrayList hSequences {
		public native get();
	}

	property ArrayList hSubOpRefs {
		public native get();
	}

	property float fStartTime {
		public native get();
	}

	public native void GetIdentifier(char[] sIdentifier, int iMaxLength);

	public native void GetError(char[] sError, int iMaxLength);
	public native void SetError(char[] sError);

	public native bool Equals(Operation mOtherOperation);
	public native bool IsValid();

	public native bool AddSubOperation(Operation mSubOperation, int iIndex=-1);
	public native void ClearSubOperations();

	public native bool AddStateChangeForward(OpStateChangeFwd funcForward);
	public native bool RemoveStateChangeForward(OpStateChangeFwd funcForward);

	public native bool AddStepForward(OpStepFwd funcForward);
	public native bool RemoveStepForward(OpStepFwd funcForward);

	public native bool AddAbortForward(OpAbortFwd funcForward);
	public native bool RemoveAbortForward(OpAbortFwd funcForward);

	/**
	 * Pre-initialize the Operation (optional, but can be used to check if runnable)
	 *
	 * @param mBot			Bot to bind this Operation to
	 * @param bSilentFail	If set to true, failed initializations do not return an error or mark the Operation as aborted
	 * @return Returns OpRet_Abort if the Operation failed to initalize, OpRet_Continue otherwise
	*/
	public native OpRet Init(Bot mBot, bool bSilentFail=false);

	public native bool Interrupt();
	public native bool Resume();

	public native void Abort();
	public native void Restart();

	/**
	 * Creates an independent and uninitialized copy of an Operation
	 * with the same initialization parameters
	 *
	 * @return New Operation
	**/
	public native Operation Clone();

	// Helper function to prepare abort error message
	public native OpRet _Abort(char[] sError=NULL_STRING, any ...);

	public native OpRef ToOpRef();

	public static native void Register(char[] sIdentifier, OpInitFunc fnInit=INVALID_FUNCTION, OpValidateFunc fnValidate=INVALID_FUNCTION, OpFunc fnPreRun=INVALID_FUNCTION, OpFunc fnPostRun=INVALID_FUNCTION, OpFunc fnSuspend=INVALID_FUNCTION, OpFunc fnResume=INVALID_FUNCTION, CleanupFunc fnCleanup=INVALID_FUNCTION, bool bLoop=false, bool bHasSubOps=false, bool bConcurrent=false, bool bCascadeAborts=true);
	public static native bool Deregister(char[] sIdentifier=NULL_STRING);

	public static native Operation Instance(char[] sIdentifier, KeyValues &hInitParms=null);
	public static native void Destroy(Operation &mOp);
}

methodmap OpRef {
	public native Operation ToOperation();
}
