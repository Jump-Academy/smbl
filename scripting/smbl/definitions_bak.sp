enum Op {
	Op_Invalid = -1
}

enum OpState {
	OpState_Undefined,
	OpState_Valid,
	OpState_Invalid
}

enum OpRet {
	Op_Continue,
	Op_Handled,
	Op_Abort
}

enum Seq {
	Seq_Invalid = -1
}

enum struct Sequence {
	Seq iSeq;
	int iUID;

	float fStartTime;
	any aData[8];
	float fVec[3];

	SeqFunc fnRun;
}

enum struct Operation {
	Op iOp;
	OpState iOpState;

	int iUID;
	bool bStarted;
	bool bEnded;
	bool bLoop;
	bool bConcurrent;

	ArrayList hSequences;	// Sequence
	ArrayList hSubOps;		// Operation
	float fStartTime;
	any aData[8];
	float fVec[3];

	OpValidateFunc fnValidate;
	OpFunc fnInit;
	OpFunc fnPreRun;
	OpFunc fnPostRun;
	CleanupFunc pCleanup;
}

typedef SeqFunc = function OpRet (int iClient, Operation eOp, Sequence eSeq);
typedef OpFunc = function OpRet (int iClient, Operation eOp);
typedef OpValidateFunc = function OpState (int iClient, Operation eOp);
typedef CleanupFunc = function void (Operation eOp);

enum struct Bot {
	bool bActive;
	char sDefaultName[MAX_NAME_LENGTH];

	Operation eOp;
	int iLastNavPointIdx;

	Op iLastOp;
	int iLastOpUID;

	Seq iLastSeq;
	int iLastSeqUID;

// 	State iState;
// 	State iLastState;
	float fLastStateChange;

	float fMoveTo[3];
	float fAimTo[3];
	float fAng[3];
	float fAngError[3];
	int iTarget;

	int iButtons;
	float fLocalVel[3];

	float fKPID[3];
	float fIError[2];

	Handle hThinkTimer;

	float fData[4];
	int iData[4];

	void SetPID(float fKPID[3]) {
		this.fKPID = fKPID;
	}
}
