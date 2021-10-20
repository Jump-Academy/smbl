public void __MarkOperationNativesAsOptional() {

}

enum Op {
	Op_Invalid = -1
}

enum OpState {
	OpState_Undefined,
	OpState_Valid,
	OpState_Invalid
}

enum OpRet {
	OpRet_Continue,
	OpRet_Handled,
	OpRet_Abort
}

enum Seq {
	Seq_Invalid = -1
}

enum struct Sequence {
	char sIdentifier[64];
	Seq iSeq;
	int iUID;

	float fStartTime;
	any aData[16];

	SeqFunc fnRun;
}

typedef SeqFunc = function OpRet (Bot mBot, any aOpData[16], any aSeqData[16]);
typedef OpFunc = function OpRet (Bot mBot, any aData[16]);
typedef OpInitFunc = function OpRet (Bot mBot, ArrayList hSequences, ArrayList hSubOps, any aData[16]);
typedef OpValidateFunc = function OpState (Bot mBot, ArrayList hSequences, any aData[16]);
typedef CleanupFunc = function void (Bot mBot, ArrayList hSequences, any aData[16]);

methodmap Operation {
	property Op iOp {
		public native get();
		public native set(Op iOp);
	}

// 	property Function fnValidate {
// 		public native get();
// 		public native set(Function fnValidate);
// 	}

// 	property Function fnInit {
// 		public native get();
// 		public native set(Function fnInit);
// 	}

// 	property Function fnPreRun {
// 		public native get();
// 		public native set(Function fnPreRun);
// 	}

// 	property Function fnPostRun {
// 		public native get();
// 		public native set(Function fnPreRun);
// 	}

// 	property Function fnCleanup {
// 		public native get();
// 		public native set(Function fnCleanup);
// 	}
}

#define NULL_OPERATION	view_as<Operation>(0)
