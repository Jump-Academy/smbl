enum struct _OperationTemplate {
	char sIdentifier[64];
	Handle hPlugin;

	bool bLoop;
	bool bHasSubOps;
	bool bConcurrent;
	bool bCascadeAborts;

	Function fnValidate;	// OpValidateFunc
	Function fnInit;		// OpInitFunc
	Function fnPreRun;		// OpFunc
	Function fnPostRun;		// OpFunc
	Function fnCleanup;		// CleanupFunc
}

enum struct _Operation {
	char sIdentifier[64];
	Handle hPlugin;
	Op iOp;
	OpState iOpState;

	int iUID;
	bool bStarted;
	bool bEnded;
	bool bLoop;
	bool bConcurrent;
	bool bCascadeAborts;

	ArrayList hSequences;	// Sequence
	ArrayList hSubOps;		// Operation
	float fStartTime;
	any aData[16];

	Function fnValidate;	// OpValidateFunc
	Function fnInit;		// OpInitFunc
	Function fnPreRun;		// OpFunc
	Function fnPostRun;		// OpFunc
	Function fnCleanup;		// CleanupFunc

	bool bGCFlag;
}

StringMap m_hOperationTemplates;
ArrayList m_hOperations;

// Operations control flow

OpRet RunOperations(Bot mBot, Operation mOp) {
	int iOpIdx = view_as<int>(mOp)-1;
	_Operation eOp;
	m_hOperations.GetArray(iOpIdx, eOp);

	if (eOp.iOp == Op_Invalid) {
		return OpRet_Abort;
	}

	if (eOp.bGCFlag) {
		PrintToServer("Attempted to run an Operation.%s(%d) marked for deletion", eOp.sIdentifier, eOp.iUID);
		return OpRet_Abort;
	}

	if (eOp.bEnded) {
		PrintToServer("Attempted to run a completed Operation.%s(%d)", eOp.sIdentifier, eOp.iUID);
		return OpRet_Abort;
	}

	if (!StrEqual(eOp.sIdentifier, "SMBL.MainLoop")) {
		PrintToServer("Operation.%s(%d) is running",  eOp.sIdentifier, eOp.iUID);
	}
	
	if (!eOp.bStarted) {
		eOp.bStarted = true;
		eOp.fStartTime = GetGameTime();

		PrintToServer("RunOp %s: Starting", eOp.sIdentifier);

		if (eOp.fnInit != INVALID_FUNCTION) {
			PrintToServer("RunOp %s: Starting Init Function", eOp.sIdentifier);
			Call_StartFunction(eOp.hPlugin, eOp.fnInit);
			Call_PushCell(mBot);
			Call_PushCell(eOp.hSequences);
			Call_PushCell(eOp.hSubOps);
			Call_PushArrayEx(eOp.aData, sizeof(_Operation::aData), SM_PARAM_COPYBACK);

			PrintToServer("Init finished eOp.aData[0]=%d", eOp.aData[0]);

			OpRet iReturn;
			int iCallError = Call_Finish(iReturn);
			if (iCallError != SP_ERROR_NONE) {
				LogError("Operation.%s(%d) initialization function call returned error code %d", eOp.sIdentifier, eOp.iUID, iCallError);
				m_hOperations.SetArray(iOpIdx, eOp);
				Cleanup_Op(mBot, mOp);
				return OpRet_Abort;
			}

			if (iReturn == OpRet_Abort) {
				LogError("Operation.%s(%d) initialization aborted", eOp.sIdentifier, eOp.iUID);
				m_hOperations.SetArray(iOpIdx, eOp);
				Cleanup_Op(mBot, mOp);
				return OpRet_Abort;	
			}
		}
	}

	switch (eOp.iOpState) {
		case OpState_Undefined: {
			if (eOp.fnValidate != INVALID_FUNCTION) {
				PrintToServer("RunOp %s: Starting Validate Function", eOp.sIdentifier);

				Call_StartFunction(eOp.hPlugin, eOp.fnValidate);
				Call_PushCell(mBot);
				Call_PushCell(eOp.hSequences);
				Call_PushArrayEx(eOp.aData, sizeof(_Operation::aData), SM_PARAM_COPYBACK);

				OpState iOpState;
				int iCallError = Call_Finish(iOpState);
				eOp.iOpState = iOpState;

				if (iCallError != SP_ERROR_NONE) {
					LogError("Operation.%s(%d) validation function call returned error code %d", eOp.sIdentifier, eOp.iUID, iCallError);

					m_hOperations.SetArray(iOpIdx, eOp);
					Cleanup_Op(mBot, mOp);
					return OpRet_Abort;
				}

				if (iOpState == OpState_Invalid) {
					m_hOperations.SetArray(iOpIdx, eOp);
					Cleanup_Op(mBot, mOp);
					return OpRet_Abort;
				}
			}
		}
		case OpState_Invalid: {
			PrintToServer("Attempted to run an invalid Operation.%s(%d)", eOp.sIdentifier, eOp.iUID);

			Cleanup_Op(mBot, mOp);
			return OpRet_Handled;
		}
	}

// 	g_eBot[iClient].iLastOp = eOp.iOp;
// 	g_eBot[iClient].iLastOpUID = eOp.iUID;

	if (eOp.fnPreRun != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnPreRun);
		Call_PushCell(mBot);
		Call_PushArrayEx(eOp.aData, sizeof(_Operation::aData), SM_PARAM_COPYBACK);

		any aResult;
		int iCallError = Call_Finish(aResult);
		if (iCallError != SP_ERROR_NONE) {
			LogError("Operation.%s(%d) pre-run function call returned error code %d", eOp.sIdentifier, eOp.iUID, iCallError);

			Cleanup_Op(mBot, mOp);
			return OpRet_Abort;
		}
	}

	int iSequencesLength = eOp.hSequences.Length;
	if (iSequencesLength) {
		OpRet iReturn = OpRet_Continue;

		Sequence eSeq;
		eOp.hSequences.GetArray(0, eSeq);

		PrintToServer("Operation.%s(%d) running Sequence.%s(%d) 1/%d", eOp.sIdentifier, eOp.iUID, eSeq.sIdentifier, eSeq.iUID, iSequencesLength);

// 		g_eBot[iClient].iLastSeq = eSeq.iSeq;
// 		g_eBot[iClient].iLastSeqUID = eSeq.iUID;

		Call_StartFunction(eOp.hPlugin, eSeq.fnRun);
		Call_PushCell(mBot);
		Call_PushArrayEx(eOp.aData, sizeof(_Operation::aData), SM_PARAM_COPYBACK);
		Call_PushArrayEx(eSeq.aData, sizeof(Sequence::aData), SM_PARAM_COPYBACK);

		int iCallError = Call_Finish(iReturn);
		if (iCallError != SP_ERROR_NONE) {
			LogError("Operation.%s(%d) Sequence.%s(%d) function call returned error code %d", eOp.sIdentifier, eOp.iUID, eSeq.sIdentifier, eSeq.iUID, iCallError);

			m_hOperations.SetArray(iOpIdx, eOp);
			Cleanup_Op(mBot, mOp);
			return OpRet_Abort;
		}

		eOp.hSequences.SetArray(0, eSeq);
		
		switch (iReturn) {
			case OpRet_Abort: {
				LogError("Operation.%s(%d) Sequence.%s(%d) aborted", eOp.sIdentifier, eOp.iUID, eSeq.sIdentifier, eSeq.iUID);

				m_hOperations.SetArray(iOpIdx, eOp);
				Cleanup_Op(mBot, mOp);
				return OpRet_Abort;
			}
			case OpRet_Handled: {
// 				PrintToServer("Operation.%s(%d) Sequence.%s(%d) handled (%d remaining)", eOp.sIdentifier, eOp.iUID, g_sSequence[eSeq.iSeq], eSeq.iUID, eOp.hSequences.Length);
				eOp.hSequences.Erase(0);
			}
		}
	}

	int iSubOpsLength;
	if (eOp.hSubOps) {
		iSubOpsLength = eOp.hSubOps.Length;
		Operation mSubOp;

		if (eOp.bConcurrent) {
			for (int i=0; i<iSubOpsLength; i++) {
				mSubOp = eOp.hSubOps.Get(i);

#if defined DEBUG
				_Operation eSubOp;
				m_hOperations.GetArray(view_as<int>(mSubOp)-1, eSubOp);
				PrintToServer("Operation.%s(%d) concurrently running sub [%d/%d]", eOp.sIdentifier, eOp.iUID, i+1, eOp.hSubOps.Length, eSubOp.sIdentifier, eSubOp.iUID);
#endif

				OpRet iReturn = RunOperations(mBot, mSubOp);
				switch (iReturn) {
// 					case OpRet_Continue: {
// 						eOp.hSubOps.SetArray(i, eSubOp);
// 					}
					case OpRet_Handled: {
						eOp.hSubOps.Erase(i--);
					}
					case OpRet_Abort: {
						// TODO: Should all parallel ops stop if one aborts?
						eOp.hSubOps.Erase(0);

#if defined DEBUG
						PrintToServer("Aborted Operation.%s(%d) concurrent sub [%d/%d] Operation.%s(%d)", eOp.sIdentifier, eOp.iUID, i+1, iSubOpsLength, eSubOp.sIdentifier, eSubOp.iUID);
#endif

						if (eOp.bCascadeAborts) {
							m_hOperations.SetArray(iOpIdx, eOp);
							Cleanup_Op(mBot, mOp);
							return OpRet_Abort;
						}
					}				
				}
			}
		} else if (iSubOpsLength) {
			mSubOp = eOp.hSubOps.Get(0);

#if defined DEBUG
			_Operation eSubOp;
			m_hOperations.GetArray(view_as<int>(mSubOp)-1, eSubOp);
			PrintToServer("Operation.%s(%d) running sub [1/%d] Operation.%s(%d)", eOp.sIdentifier, eOp.iUID, eOp.hSubOps.Length, eSubOp.sIdentifier, eSubOp.iUID);
#endif

			OpRet iReturn = RunOperations(mBot, mSubOp);
			switch (iReturn) {
// 				case OpRet_Continue: {
// 					eOp.hSubOps.SetArray(0, eSubOp);
// 				}
				case OpRet_Handled: {
					eOp.hSubOps.Erase(0);
				}
				case OpRet_Abort: {
					eOp.hSubOps.Erase(0);
#if defined DEBUG
					PrintToServer("Aborted Operation.%s(%d) sub [1/%d] Operation.%s(%d)", eOp.sIdentifier, eOp.iUID, iSubOpsLength, eSubOp.sIdentifier, eSubOp.iUID);
#endif
					if (eOp.bCascadeAborts) {
						m_hOperations.SetArray(iOpIdx, eOp);
						Cleanup_Op(mBot, mOp);
						return OpRet_Abort;
					}
				}				
			}
		}
	}

	if (eOp.fnPostRun != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnPostRun);
		Call_PushCell(mBot);
		Call_PushArrayEx(eOp.aData, sizeof(_Operation::aData), SM_PARAM_COPYBACK);

		any aResult;
		int iCallError = Call_Finish(aResult);
		if (iCallError != SP_ERROR_NONE) {
			LogError("Operation.%s(%d) post-run function call returned error code %d", eOp.sIdentifier, eOp.iUID, iCallError);

			m_hOperations.SetArray(iOpIdx, eOp);
			Cleanup_Op(mBot, mOp);
			return OpRet_Abort;
		}
	}

	if (eOp.bLoop || iSequencesLength || iSubOpsLength) {
		m_hOperations.SetArray(iOpIdx, eOp);
		return OpRet_Continue;
	}

	m_hOperations.SetArray(iOpIdx, eOp);
	Cleanup_Op(mBot, mOp);
	return OpRet_Handled;
}

// Natives

void SetupOperationNatives() {
	m_hOperationTemplates = new StringMap();
	m_hOperations = new ArrayList(sizeof(_Operation));

	CreateNative("SMBL_RegisterOperation",		Native_RegisterOperation);
	CreateNative("SMBL_DeregisterOperation",	Native_DeregisterOperation);
	CreateNative("SMBL_NewOperation", 			Native_NewOperation);
}

public int Native_RegisterOperation(Handle hPlugin, int iArgC) {
	_OperationTemplate eOperationTemplate;
	eOperationTemplate.hPlugin = hPlugin;

	GetNativeString(1, eOperationTemplate.sIdentifier, sizeof(_Operation::sIdentifier));

	if (m_hOperations.FindString(eOperationTemplate.sIdentifier) != -1) {
		ThrowError("Operation with this identifier is already registered: %s", eOperationTemplate.sIdentifier);
	}

	// OpInitFunc
	eOperationTemplate.fnInit = GetNativeFunction(2);

	// OpValidateFunc
	eOperationTemplate.fnValidate = GetNativeFunction(3);

	// OpFunc
	eOperationTemplate.fnPreRun = GetNativeFunction(4);

	// OpFunc
	eOperationTemplate.fnPostRun = GetNativeFunction(5);

	// CleanupFunc
	eOperationTemplate.fnCleanup = GetNativeFunction(6);

	eOperationTemplate.bLoop = GetNativeCell(7);
	eOperationTemplate.bHasSubOps = GetNativeCell(8);
	eOperationTemplate.bConcurrent = GetNativeCell(9);
	eOperationTemplate.bCascadeAborts = GetNativeCell(10);

	if (m_hOperationTemplates.SetArray(eOperationTemplate.sIdentifier, eOperationTemplate, sizeof(_OperationTemplate), false)) {
		PrintToServer("SMBL registered operation: %s", eOperationTemplate.sIdentifier);
		return true;
	}

	PrintToServer("SMBL failed to register operation (duplicate?): %s", eOperationTemplate.sIdentifier);

	return false;
}

public int Native_DeregisterOperation(Handle hPlugin, int iArgC) {
	if (IsNativeParamNullString(1)) {
		StringMapSnapshot hSnapshot = m_hOperationTemplates.Snapshot();

		int iSnapshotLength = hSnapshot.Length;
		for (int i=0; i<iSnapshotLength; i++) {
			char sIdentifier[64];
			hSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));

			_OperationTemplate eOperationTemplate;
			if (m_hOperationTemplates.GetArray(sIdentifier, eOperationTemplate, sizeof(eOperationTemplate)) && eOperationTemplate.hPlugin == hPlugin) {
				m_hOperationTemplates.Remove(sIdentifier);
				PrintToServer("SMBL deregistered operation: %s", eOperationTemplate.sIdentifier);
			}
		}

		delete hSnapshot;

		return true;
	}

	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	_OperationTemplate eOperationTemplate;
	if (m_hOperationTemplates.GetArray(sIdentifier, eOperationTemplate, sizeof(_OperationTemplate))) {
		if (eOperationTemplate.hPlugin != hPlugin) {
			char sPluginName[64];
			GetPluginInfo(eOperationTemplate.hPlugin, PlInfo_Name, sPluginName, sizeof(sPluginName));
			ThrowError("Operation (%s) may only be deregistered from originating plugin: %s", sIdentifier, sPluginName);
		}

		m_hOperationTemplates.Remove(sIdentifier);

		return true;
	}

	return false;
}

public any Native_NewOperation(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	any aData[16];
	GetNativeArray(2, aData, sizeof(aData));

	Operation mOpParent = GetNativeCell(3);

	_OperationTemplate eOperationTemplate;
	if (m_hOperationTemplates.GetArray(sIdentifier, eOperationTemplate, sizeof(_OperationTemplate))) {
		_Operation eOp;
		eOp.sIdentifier = eOperationTemplate.sIdentifier;
		eOp.hPlugin = eOperationTemplate.hPlugin;
		eOp.bLoop = eOperationTemplate.bLoop;
		eOp.bConcurrent = eOperationTemplate.bConcurrent;
		eOp.bCascadeAborts = eOperationTemplate.bCascadeAborts;

		eOp.hSequences = new ArrayList(sizeof(Sequence));

		if (eOperationTemplate.bHasSubOps) {
			eOp.hSubOps = new ArrayList();
		}

		eOp.fnValidate = eOperationTemplate.fnValidate;
		eOp.fnInit = eOperationTemplate.fnInit;
		eOp.fnPreRun = eOperationTemplate.fnPreRun;
		eOp.fnPostRun = eOperationTemplate.fnPostRun;
		eOp.fnCleanup = eOperationTemplate.fnCleanup;

		eOp.aData = aData;

		Operation mOp;
		int iFreeIdx = m_hOperations.FindValue(true, _Operation::bGCFlag);
		if (iFreeIdx != -1) {
			m_hOperations.SetArray(iFreeIdx, eOp);

			mOp = view_as<Operation>(iFreeIdx+1);
		} else {
			mOp = view_as<Operation>(m_hOperations.PushArray(eOp)+1);
		}

		if (mOpParent) {
			ArrayList hSubOps = m_hOperations.Get(view_as<int>(mOpParent)-1, _Operation::hSubOps);
			if (!hSubOps) {
				delete eOp.hSequences;
				delete eOp.hSubOps;

				ThrowError("Operation(%s) does not support sub-operations", sIdentifier);
			}

			hSubOps.Push(mOp);
		}

		return mOp;
	}

	return NULL_OPERATION;
}


// Internal helpers

public void Cleanup_Op(Bot mBot, Operation mOp) {
	int iOpIdx = view_as<int>(mOp)-1;

	_Operation eOp;
	m_hOperations.GetArray(iOpIdx, eOp);

	if (eOp.hSubOps) {
		int iSubOpsLength = eOp.hSubOps.Length;
		for (int i=0; i<iSubOpsLength; i++) {
			Cleanup_Op(mBot, eOp.hSubOps.Get(i));
		}

		delete eOp.hSubOps;
	}

	if (eOp.fnCleanup != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnCleanup);
		Call_PushCell(mBot);
		Call_PushCell(eOp.hSequences);
		Call_PushArrayEx(eOp.aData, sizeof(_Operation::aData), SM_PARAM_COPYBACK);

		int iCallError = Call_Finish();
		if (iCallError != SP_ERROR_NONE) {
			LogStackTrace("Operation.%s(%d) cleanup function call returned error code %d", eOp.sIdentifier, eOp.iUID, iCallError);
		}
	}

	delete eOp.hSequences;

	m_hOperations.Set(iOpIdx, true, _Operation::bGCFlag);

	if (iOpIdx == m_hOperations.Length-1) {
		for (int i=iOpIdx; i>0; i--) {
			if (!m_hOperations.Get(i-1, _Operation::bGCFlag)) {
				m_hOperations.Resize(i);
				return;
			}
		}

		m_hOperations.Clear();
	}
}
