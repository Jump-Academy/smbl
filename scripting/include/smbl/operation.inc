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
	OpRet_Abort,
	OpRet_Passthrough
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

typeset OpInitFunc {
	function OpRet (Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData);
	function OpRet (Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData, bool bConfigureOnly);
}

typedef OpValidateFunc = function OpRet (Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData, float fStartTime);
typedef OpFunc = function OpRet (Bot mBot, Operation mOp, OpData eOpData);
typedef OpCleanupFunc = function void (Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData);

typedef OpEventFwd = function void (Bot mBot, Operation mOp, OpData eOpData, any aData);

typedef OpValidatedFwd = function void (Bot mBot, Operation mOp, OpRet iOpRet);
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

	public native bool AddValidatedForward(OpValidatedFwd fnForward);
	public native bool RemoveValidatedForward(OpValidatedFwd fnForward);

	public native bool AddStateChangeForward(OpStateChangeFwd fnForward);
	public native bool RemoveStateChangeForward(OpStateChangeFwd fnForward);

	public native bool AddStepForward(OpStepFwd fnForward);
	public native bool RemoveStepForward(OpStepFwd fnForward);

	public native bool AddAbortForward(OpAbortFwd fnForward);
	public native bool RemoveAbortForward(OpAbortFwd fnForward);

	/**
	 * Pre-initializes the Operation.
	 *
	 * Use Operation.Configure() to check if runnable to avoid unnecessary instantiation
	 *
	 * @param mBot			Bot to bind this Operation to.
	 * @param bSilentFail	If set to true, failed initializations do not return an error or mark the Operation as aborted
	 * @return Returns OpRet_Abort if the Operation failed to initialize, OpRet_Continue otherwise.
	*/
	public native OpRet Init(Bot mBot, bool bSilentFail=false);

	/**
	 * Runs an initialized operation on a timer until completion or abort.
	 * Use Operation.Init() to pre-initialize before running.
	 * The operation can be terminated early by manually calling Operation.Abort().
	 *
	 * @param fInterval Interval from the current game time to run the operation or the delay between timer loops.
	 * @param Timer flags to set (TIMER_REPEAT and TIMER_FLAG_NO_MAPCHANGE only).
	 * @param bDestroy Destroy the operation when completed or aborted
	 * @error Operation is not initialized or cannot be run, or the operation is already running on a timer.
	 */
	public native void Run(float fInterval, int iTimerFlags=0, bool bDestroy=true);

	/**
	 * Runs an initialized operation operation for a single cycle.
	 * Use Operation.Init() to pre-initialize before running.
	 *
	 * @param bDestroy Destroy the operation when completed or aborted
	 * @return Returns OpRet_Continue if the operation ran successfully but is not yet complete,
	 * 			OpRet_Handled if it completed successfully, and OpRet_Abort if the operation aborted (such as due to error).
	 * @error Operation is not initialized or cannot be run.
	 */
	public native OpRet RunOnce(bool bDestroy=true);

	public native bool Suspend(bool bBlocking=true);
	public native bool Resume();

	public native void Abort(bool bAbortAsComplete=false);
	public native void Restart();

	/**
	 * Creates an independent and uninitialized copy of an Operation
	 * with the same initialization parameters.
	 *
	 * @return New Operation
	**/
	public native Operation Clone();

	// Helper function to prepare abort error message
	public native OpRet _Abort(char[] sError=NULL_STRING, any ...);

	public native OpRef ToOpRef();

	public static native void Register(char[] sIdentifier, OpInitFunc fnInit=INVALID_FUNCTION, OpValidateFunc fnValidate=INVALID_FUNCTION, OpFunc fnPreRun=INVALID_FUNCTION, OpFunc fnPostRun=INVALID_FUNCTION, OpFunc fnSuspend=INVALID_FUNCTION, OpFunc fnResume=INVALID_FUNCTION, OpCleanupFunc fnCleanup=INVALID_FUNCTION, bool bLoop=false, bool bHasSubOps=false, bool bConcurrent=false, bool bCascadeAborts=true);
	public static native bool Deregister(char[] sIdentifier=NULL_STRING);

	public static native Operation Instance(char[] sIdentifier, KeyValues &hInitParms=null, Op iOp=view_as<Op>(0));
	public static native void Destroy(Operation &mOp);

	/**
	 * Configures initialization parameters from an Operation template.
	 *
	 * Use this to prepare configuration parameters for an Operation without instantiating one first.
	 * This calls the initialization callback like Operation.Init but with bConfigureOnly set to true
	 * and null hSequences and null hSubOpRefs.  Writes to eOpData will be ignored.
	 *
	 * This can be used to check in advance if parameters are feasible to initialize an Operation.
	 *
	 * @param sIdentifier	Identifier for the Operation template
	 * @param hInitParams	Parameters to initialize the Operation and write the OP_INIT_CONFIG configuration subtree
	 * @return Returns true if the initialization callback returns OpRet_Continue and false otherwise
	 */
	public static native bool Configure(char[] sIdentifier, KeyValues &hInitParams);

	public static native bool AddEventListener(char[] sIdentifier, char[] sEvent, OpEventFwd fnEventForward);
	public static native bool RemoveEventListener(char[] sIdentifier, char[] sEvent, OpEventFwd fnEventForward);
	public static native bool DispatchEvent(char[] sIdentifier, char[] sEvent, any aData=0);
}

methodmap OpRef {
	public native Operation ToOperation();
}

#define OP_INIT_DISPATCH	"Init.Dispatch"
#define OP_INIT_IDENT		"Init.Identifier"
#define OP_INIT_PARAM		"Init.Param"
#define OP_INIT_CONFIG		"Init.Config"
