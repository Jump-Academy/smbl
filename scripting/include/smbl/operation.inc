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
	OpRet_Bypass,
	OpRet_Continue,
	OpRet_Handled,
	OpRet_Restart,
	OpRet_Abort
}

enum struct OpData {
	any aData[16]
}

enum Seq {
	Seq_Invalid = -1
}

enum struct SeqData {
	any aData[16]
}

typedef SeqFunc = function OpRet (Bot mBot, Operation mOp, OpData eOpData, SeqData eSeqData, float fStartTime);

enum struct Sequence {
	char sIdentifier[64];
	Seq iSeq;
	int iUID;
	SeqFunc fnRun;

	float fStartTime;
	SeqData eSeqData;

	void GetData(any aData[16]) {
		aData = this.eSeqData.aData;
	}

	void SetData(any aData[16]) {
		this.eSeqData.aData = aData;
	}
}

typedef OpInitFunc = function OpRet (Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData);
typedef OpValidateFunc = function OpRet (Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData, float fStartTime);
typedef OpFunc = function OpRet (Bot mBot, Operation mOp, OpData eOpData);
typedef OpCleanupFunc = function void (Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData);

typedef OpEventFwd = function void (Bot mBot, Operation mOp, OpData eOpData, any aData);

typedef OpStateChangeFwd = function void (Bot mBot, Operation mOp, OpState iOpState);
typedef OpStepFwd = function OpRet (Bot mBot, Operation mOp);
typedef OpAbortFwd = function void (Bot mBot, Operation mOp, char[] sError);

stock OpRet UnsupportedFunction(Bot mBot, Operation mOp, OpData eOpData) {
	return OpRet_Abort;
}

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

	public native void GetData(any aOpData[16]); // OpData
	public native void SetData(any aOpData[16]); // OpData

	public native void GetError(char[] sError, int iMaxLength);
	public native void SetError(char[] sError);

	public native bool Equals(Operation mOtherOperation);
	public native bool IsValid();

	public native bool AddSubOperation(Operation mSubOperation, int iIndex=-1);
	public native void ClearSubOperations();

	public native bool AddStateChangeForward(OpStateChangeFwd fnForward);
	public native bool RemoveStateChangeForward(OpStateChangeFwd fnForward);

	public native bool AddStepForward(OpStepFwd fnForward);
	public native bool RemoveStepForward(OpStepFwd fnForward);

	public native bool AddAbortForward(OpAbortFwd fnForward);
	public native bool RemoveAbortForward(OpAbortFwd fnForward);

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

	public native void Abort(bool bAbortAsComplete=false);
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

	public static native void Register(char[] sIdentifier, OpInitFunc fnInit=INVALID_FUNCTION, OpValidateFunc fnValidate=INVALID_FUNCTION, OpFunc fnPreRun=INVALID_FUNCTION, OpFunc fnPostRun=INVALID_FUNCTION, OpFunc fnSuspend=INVALID_FUNCTION, OpFunc fnResume=INVALID_FUNCTION, OpCleanupFunc fnCleanup=INVALID_FUNCTION, bool bLoop=false, bool bHasSubOps=false, bool bConcurrent=false, bool bCascadeAborts=true);
	public static native bool Deregister(char[] sIdentifier=NULL_STRING);

	public static native Operation Instance(char[] sIdentifier, KeyValues &hInitParms=null);
	public static native void Destroy(Operation &mOp);

	public static native bool AddEventListener(char[] sIdentifier, char[] sEvent, OpEventFwd fnEventForward);
	public static native bool RemoveEventListener(char[] sIdentifier, char[] sEvent, OpEventFwd fnEventForward);
	public static native bool DispatchEvent(char[] sIdentifier, char[] sEvent, any aData=0);
}

methodmap OpRef {
	public native Operation ToOperation();
}
