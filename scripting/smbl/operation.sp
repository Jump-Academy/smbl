#define OP_ALLOC_MAX	16384

enum struct _OperationTemplate {
	char sIdentifier[64];
	Handle hPlugin;

	bool bLoop;
	bool bHasSubOps;
	bool bConcurrent;
	bool bCascadeAborts;

	Function fnInit;		// OpInitFunc
	Function fnValidate;	// OpValidateFunc
	Function fnPreRun;		// OpFunc
	Function fnPostRun;		// OpFunc
	Function fnSuspend;		// OpFunc
	Function fnResume;		// OpFunc
	Function fnCleanup;		// CleanupFunc

	ArrayList hInstances;
	StringMap hEventForwards;
}

enum struct _Operation {
	char sIdentifier[64];
	Handle hPlugin;
	Op iOp;
	OpState iOpState;
	KeyValues hInitParams;
	bool bInitParamsExternal;
	Bot mBot; 				// Bot owning this Operation, or NULL_BOT if none

	int iUID;
	bool bStarted;
	bool bLoop;
	bool bConcurrent;
	bool bCascadeAborts;

	ArrayList hSequences;	// Sequence
	ArrayList hSubOpRefs;	// Operation references

	float fStartTime;
	OpData eOpData;

	char sError[256];

	Function fnValidate;	// OpValidateFunc
	Function fnInit;		// OpInitFunc
	Function fnPreRun;		// OpFunc
	Function fnPostRun;		// OpFunc
	Function fnSuspend;		// OpFunc
	Function fnResume;		// OpFunc
	Function fnCleanup;		// CleanupFunc

	PrivateForward hEventForward;

	PrivateForward hStateChangeForward;
	PrivateForward hStepForward;
	PrivateForward hAbortForward;

	bool bGCFlag;
}

static StringMap m_hOperationTemplates;
static ArrayList m_hOperations;

static int m_iUID;

// Operations control flow

OpRet RunOperations(Bot mBot, Operation mOp) {
	if (!mOp.IsValid()) {
		LogError("Attempted to run an invalid Operation: %d", mOp);
		return OpRet_Abort;
	}

// 	PrintToServer("RunOperations eOp:");
// 	ByteDump(m_hOperations, iOpIdx);

	int iOpIdx = view_as<int>(mOp)-1;
	_Operation eOp;
	m_hOperations.GetArray(iOpIdx, eOp);

	switch (eOp.iOpState) {
		case OpState_Pend: {
			eOp.hInitParams.Rewind();

			PrintToServer("RunOp %s: Starting", eOp.sIdentifier);

			if (eOp.fnInit != INVALID_FUNCTION) {
				Call_StartFunction(eOp.hPlugin, eOp.fnInit);
				Call_PushCell(mBot);
				Call_PushCell(mOp);
				Call_PushCell(eOp.hInitParams);
				Call_PushCell(eOp.hSequences);
				Call_PushCell(eOp.hSubOpRefs);
				Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

				OpRet iReturn;
				int iCallError = Call_Finish(iReturn);
				if (iCallError != SP_ERROR_NONE) {
					return InternalAbort(mBot, mOp, eOp, "initialization function call returned error code %d", iCallError);
				}

				switch (iReturn) {
					case OpRet_Bypass: {
						return OpRet_Continue;
					}
					case OpRet_Abort: {
						m_hOperations.GetArray(iOpIdx, eOp);
						return InternalAbort(mBot, mOp, eOp, "initialization aborted (%s)", eOp.sError);
					}
				}
			}

			eOp.iOpState = OpState_Run;
			eOp.mBot = mBot;
			eOp.fStartTime = GetGameTime();
			m_hOperations.SetArray(iOpIdx, eOp);

			Call_StartForward(eOp.hStateChangeForward);
			Call_PushCell(mBot);
			Call_PushCell(mOp);
			Call_PushCell(OpState_Run);
			Call_Finish();
		}
		case OpState_Suspend: {
			return OpRet_Continue;
		}
		case OpState_Abort: {
			PrintToServer("Attempted to run an aborted Operation.%s(%d)", eOp.sIdentifier, eOp.iUID);
			return OpRet_Abort;
		}
		case OpState_Complete: {
			return OpRet_Handled;
		}
	}

	if (mBot != eOp.mBot) {
		LogError("Operation.%s(%d) was bound on start to %L and cannot be run on %L.", eOp.sIdentifier, eOp.iUID, eOp.mBot.iEntity, mBot.iEntity);
		return OpRet_Abort;
	}

	if (eOp.fnValidate != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnValidate);
		Call_PushCell(mBot);
		Call_PushCell(mOp);
		Call_PushCell(eOp.hSequences);
		Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);
		Call_PushCell(eOp.fStartTime);

		OpRet iOpRet;
		int iCallError = Call_Finish(iOpRet);

		if (iCallError != SP_ERROR_NONE) {
			return InternalAbort(mBot, mOp, eOp, "validation function call returned error code %d", iCallError);
		}

		switch (iOpRet) {
			case OpRet_Bypass: {
				return OpRet_Continue;
			}
			case OpRet_Restart: {
				m_hOperations.SetArray(iOpIdx, eOp);
				mOp.Restart();

				return OpRet_Continue;
			}
			case OpRet_Handled: {
				eOp.iOpState = OpState_Complete;
				m_hOperations.SetArray(iOpIdx, eOp);

				Call_StartForward(eOp.hStateChangeForward);
				Call_PushCell(mBot);
				Call_PushCell(mOp);
				Call_PushCell(OpState_Complete);
				Call_Finish();

				return OpRet_Handled;
			}
			case OpRet_Abort: {
				m_hOperations.GetArray(iOpIdx, eOp);
				return InternalAbort(mBot, mOp, eOp, "validation aborted (%s)", eOp.sError);
			}
		}
	}

	if (eOp.fnPreRun != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnPreRun);
		Call_PushCell(mBot);
		Call_PushCell(mOp);
		Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

		OpRet iOpRet;
		int iCallError = Call_Finish(iOpRet);
		if (iCallError != SP_ERROR_NONE) {
			return InternalAbort(mBot, mOp, eOp, "pre-run function call returned error code %d", iCallError);
		}

		switch (iOpRet) {
			case OpRet_Restart: {
				m_hOperations.SetArray(iOpIdx, eOp);
				mOp.Restart();

				return OpRet_Continue;
			}
			case OpRet_Handled: {
				eOp.iOpState = OpState_Complete;
				m_hOperations.SetArray(iOpIdx, eOp);

				Call_StartForward(eOp.hStateChangeForward);
				Call_PushCell(mBot);
				Call_PushCell(mOp);
				Call_PushCell(OpState_Complete);
				Call_Finish();

				return OpRet_Handled;
			}
			case OpRet_Abort: {
				m_hOperations.GetArray(iOpIdx, eOp);
				return InternalAbort(mBot, mOp, eOp, "pre-run aborted (%s)", eOp.sError);
			}
		}
	}

	int iSequencesLength = eOp.hSequences.Length;
	if (iSequencesLength) {
		OpRet iReturn = OpRet_Continue;

		Sequence eSeq;
		eOp.hSequences.GetArray(0, eSeq);

		Call_StartFunction(eOp.hPlugin, eSeq.fnRun);
		Call_PushCell(mBot);
		Call_PushCell(mOp);
		Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);
		Call_PushArrayEx(eSeq.eSeqData, sizeof(Sequence::eSeqData), SM_PARAM_COPYBACK);
		Call_PushCell(eSeq.fStartTime);

		int iCallError = Call_Finish(iReturn);
		if (iCallError != SP_ERROR_NONE) {
			return InternalAbort(mBot, mOp, eOp, "Sequence.%s(%d) function call returned error code %d", eSeq.sIdentifier, eSeq.iUID, iCallError);
		}

		if (!eSeq.fStartTime) {
			eSeq.fStartTime = GetGameTime();
		}

		eOp.hSequences.SetArray(0, eSeq);

		switch (iReturn) {
			case OpRet_Abort: {
				m_hOperations.GetArray(iOpIdx, eOp);
				return InternalAbort(mBot, mOp, eOp, "aborted Sequence.%s(%d): %s", eSeq.sIdentifier, eSeq.iUID, eOp.sError);
			}
			case OpRet_Handled: {
				eOp.hSequences.Erase(0);
			}
		}
	}

	int iSubOpRefsLength;
	if (eOp.hSubOpRefs) {
		iSubOpRefsLength = eOp.hSubOpRefs.Length;

		if (eOp.bConcurrent) {
			Op iLastOp;
			if (iSubOpRefsLength) {
				for (int i=iSubOpRefsLength-1; i>=0 && !iLastOp; i--) {
					OpRef mSubOpRef = eOp.hSubOpRefs.Get(i);
					Operation mSubOp = mSubOpRef.ToOperation();
					if (mSubOp.IsValid()) {
						iLastOp = mSubOp.iOp;
					}
				}
			}

			for (int i=0; i<iSubOpRefsLength; i++) {
				OpRef mSubOpRef = eOp.hSubOpRefs.Get(i);
				Operation mSubOp = mSubOpRef.ToOperation();

				if (!mSubOp.IsValid()) {
					if (eOp.bCascadeAborts) {
						return InternalAbort(mBot, mOp, eOp, "cascade abort concurrent subop [?/%d]: Invalid suboperation", view_as<int>(iLastOp)+1);
					}

					eOp.hSubOpRefs.Erase(i--);
					iSubOpRefsLength--;
					continue;
				}

				OpRet iOpRet = RunOperations(mBot, mSubOp);
				switch (iOpRet) {
					case OpRet_Restart: {
						mSubOp.Restart();
					}
					case OpRet_Handled: {
						Operation.Destroy(mSubOp);
						eOp.hSubOpRefs.Erase(i--);
						iSubOpRefsLength--;
					}
					case OpRet_Abort: {
						if (eOp.bCascadeAborts) {
							_Operation eSubOp;
							m_hOperations.GetArray(view_as<int>(mSubOp)-1, eSubOp);

							return InternalAbort(mBot, mOp, eOp, "cascade abort concurrent subop [%d/%d]: %s", view_as<int>(eSubOp.iOp)+1, view_as<int>(iLastOp)+1, eSubOp.sError);
						}

						Operation.Destroy(mSubOp);

						eOp.hSubOpRefs.Erase(i--);
						iSubOpRefsLength--;
					}
				}
			}
		} else if (iSubOpRefsLength) {
			Op iLastOp;
			if (iSubOpRefsLength) {
				for (int i=iSubOpRefsLength-1; i>=0 && !iLastOp; i--) {
					OpRef mSubOpRef = eOp.hSubOpRefs.Get(i);
					Operation mSubOp = mSubOpRef.ToOperation();
					if (mSubOp.IsValid()) {
						iLastOp = mSubOp.iOp;
					}
				}
			}

			OpRef mSubOpRef = eOp.hSubOpRefs.Get(0);
			Operation mSubOp = mSubOpRef.ToOperation();

			if (!mSubOp.IsValid()) {
				if (eOp.bCascadeAborts) {
					return InternalAbort(mBot, mOp, eOp, "cascade abort subop [?/%d]: Invalid suboperation", view_as<int>(iLastOp)+1);
				}

				eOp.hSubOpRefs.Erase(0);
				iSubOpRefsLength--;
			} else {
				OpRet iReturn = RunOperations(mBot, mSubOp);
				switch (iReturn) {
					case OpRet_Handled: {
						Operation.Destroy(mSubOp);
						eOp.hSubOpRefs.Erase(0);
					}
					case OpRet_Abort: {
						if (eOp.bCascadeAborts) {
							_Operation eSubOp;
							m_hOperations.GetArray(view_as<int>(mSubOp)-1, eSubOp);

							return InternalAbort(mBot, mOp, eOp, "cascade abort subop [%d/%d]: %s", view_as<int>(eSubOp.iOp)+1, view_as<int>(iLastOp)+1, eSubOp.sError);
						}

						Operation.Destroy(mSubOp);
						eOp.hSubOpRefs.Erase(0);
					}
				}
			}
		}
	}

	if (eOp.fnPostRun != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnPostRun);
		Call_PushCell(mBot);
		Call_PushCell(mOp);
		Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

		OpRet iOpRet;
		int iCallError = Call_Finish(iOpRet);
		if (iCallError != SP_ERROR_NONE) {
			return InternalAbort(mBot, mOp, eOp, "post-run function call returned error code %d", iCallError);
		}

		switch (iOpRet) {
			case OpRet_Restart: {
				m_hOperations.SetArray(iOpIdx, eOp);
				mOp.Restart();
			}
			case OpRet_Handled: {
				eOp.iOpState = OpState_Complete;
				m_hOperations.SetArray(iOpIdx, eOp);

				Call_StartForward(eOp.hStateChangeForward);
				Call_PushCell(mBot);
				Call_PushCell(mOp);
				Call_PushCell(OpState_Complete);
				Call_Finish();

				return OpRet_Handled;
			}
			case OpRet_Abort: {
				m_hOperations.GetArray(iOpIdx, eOp);
				return InternalAbort(mBot, mOp, eOp, "post-run aborted (%s)", eOp.sError);
			}
		}
	}

	if (eOp.bLoop || iSequencesLength || iSubOpRefsLength) {
		m_hOperations.SetArray(iOpIdx, eOp);

		Call_StartForward(eOp.hStepForward);
		Call_PushCell(mBot);
		Call_PushCell(mOp);

		OpRet iOpRet;
		Call_Finish(iOpRet);

		if (iOpRet == OpRet_Abort) {
			return InternalAbort(mBot, mOp, eOp, "step callback returned abort");
		}

		return OpRet_Continue;
	}

	eOp.iOpState = OpState_Complete;
	m_hOperations.SetArray(iOpIdx, eOp);

	Call_StartForward(eOp.hStateChangeForward);
	Call_PushCell(mBot);
	Call_PushCell(mOp);
	Call_PushCell(OpState_Complete);
	Call_Finish();

	return OpRet_Handled;
}

// Natives

void SetupOperationNatives() {
	m_hOperationTemplates = new StringMap();
	m_hOperations = new ArrayList(sizeof(_Operation));

	CreateNative("Operation.iOp.get",					Native_Operation_GetOp);
	CreateNative("Operation.iOp.set",					Native_Operation_SetOp);

	CreateNative("Operation.iOpState.get",				Native_Operation_GetOpState);
	CreateNative("Operation.hInitParams.get",			Native_Operation_GetInitParams);
	CreateNative("Operation.bLoop.get",					Native_Operation_GetLoop);
	CreateNative("Operation.bConcurrent.get",			Native_Operation_GetConcurrent);
	CreateNative("Operation.iUID.get",					Native_Operation_GetUID);
	CreateNative("Operation.hSequences.get",			Native_Operation_GetSequences);
	CreateNative("Operation.hSubOpRefs.get",			Native_Operation_GetSubOpRefs);
	CreateNative("Operation.fStartTime.get",			Native_Operation_GetStartTime);
	CreateNative("Operation.GetIdentifier",				Native_Operation_GetIdentifier);

	CreateNative("Operation.GetData",					Native_Operation_GetData);
	CreateNative("Operation.SetData",					Native_Operation_SetData);

	CreateNative("Operation.GetError",					Native_Operation_GetError);
	CreateNative("Operation.SetError",					Native_Operation_SetError);

	CreateNative("Operation.AddSubOperation",			Native_Operation_AddSubOperation);
	CreateNative("Operation.ClearSubOperations",		Native_Operation_ClearSubOperations);

	CreateNative("Operation.AddStateChangeForward",		Native_Operation_AddStateChangeForward);
	CreateNative("Operation.RemoveStateChangeForward",	Native_Operation_RemoveStateChangeForward);

	CreateNative("Operation.AddStepForward",			Native_Operation_AddStepForward);
	CreateNative("Operation.RemoveStepForward",			Native_Operation_RemoveStepForward);

	CreateNative("Operation.AddAbortForward",			Native_Operation_AddAbortForward);
	CreateNative("Operation.RemoveAbortForward",		Native_Operation_RemoveAbortForward);

	CreateNative("Operation.Equals", 					Native_Operation_Equals);
	CreateNative("Operation.IsValid", 					Native_Operation_IsValid);

	CreateNative("Operation.Init", 						Native_Operation_Init);

	CreateNative("Operation.Interrupt",					Native_Operation_Interrupt);
	CreateNative("Operation.Resume",					Native_Operation_Resume);

	CreateNative("Operation.Abort",						Native_Operation_Abort);
	CreateNative("Operation.Restart",					Native_Operation_Restart);

	CreateNative("Operation.Clone",						Native_Operation_Clone);

	CreateNative("Operation._Abort",					Native_Operation__Abort);

	CreateNative("Operation.ToOpRef",					Native_Operation_ToOpRef);

	CreateNative("OpRef.ToOperation", 					Native_OpRef_ToOperation);

	// Static

	CreateNative("Operation.Register",					Native_Operation_Register);
	CreateNative("Operation.Deregister",				Native_Operation_Deregister);

	CreateNative("Operation.Instance", 					Native_Operation_Instance);
	CreateNative("Operation.Destroy", 					Native_Operation_Destroy);

	CreateNative("Operation.AddEventListener", 			Native_Operation_AddEventListener);
	CreateNative("Operation.RemoveEventListener", 		Native_Operation_RemoveEventListener);
	CreateNative("Operation.DispatchEvent",		 		Native_Operation_DispatchEvent);
}

public int Native_Operation_GetOp(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::iOp);
}

public int Native_Operation_SetOp(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Op iOp = GetNativeCell(2);
	m_hOperations.Set(view_as<int>(mOp)-1, iOp, _Operation::iOp);

	return 0;
}

public any Native_Operation_GetOpState(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::iOpState);
}

public int Native_Operation_GetLoop(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::bLoop);
}

public int Native_Operation_GetConcurrent(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::bConcurrent);
}

public int Native_Operation_GetInitParams(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hInitParams);
}

public int Native_Operation_GetUID(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::iUID);
}

public any Native_Operation_GetSequences(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hSequences);
}

public any Native_Operation_GetSubOpRefs(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hSubOpRefs);
}

public any Native_Operation_GetStartTime(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	return m_hOperations.Get(view_as<int>(mOp)-1, _Operation::fStartTime);
}

public any Native_Operation_GetIdentifier(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	int iMaxLength = GetNativeCell(3);

	char sIdentifier[64];
	m_hOperations.GetString(view_as<int>(mOp)-1, sIdentifier, sizeof(sIdentifier));

	SetNativeString(2, sIdentifier, iMaxLength);

	return 0;
}

public any Native_Operation_GetData(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);

	_Operation eOp;
	m_hOperations.GetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	SetNativeArray(2, eOp.eOpData, sizeof(OpData));

	return 0;
}

public any Native_Operation_SetData(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);

	_Operation eOp;
	m_hOperations.GetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	GetNativeArray(2, eOp.eOpData, sizeof(OpData));

	m_hOperations.SetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	return 0;
}

public any Native_Operation_GetError(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	int iMaxLength = GetNativeCell(3);

	_Operation eOp;
	m_hOperations.GetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	SetNativeString(2, eOp.sError, iMaxLength);

	return 0;
}

public any Native_Operation_SetError(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);

	_Operation eOp;
	m_hOperations.GetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	GetNativeString(2, eOp.sError, sizeof(_Operation::sError));

	m_hOperations.SetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	return 0;
}

public any Native_Operation_Equals(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Operation mOtherOp = GetNativeCell(2);

	int iThis = view_as<int>(mOp)-1;
	int iOtherThis = view_as<int>(mOtherOp)-1;

	if (iThis <= 0 || iThis >= m_hOperations.Length || iOtherThis <= 0 || iOtherThis >= m_hOperations.Length) {
		return false;
	}

	if (m_hOperations.Get(iThis, _Operation::bGCFlag) || m_hOperations.Get(iOtherThis, _Operation::bGCFlag)) {
		return false;
	}

	return m_hOperations.Get(iThis, _Operation::iUID) == m_hOperations.Get(iOtherThis, _Operation::iUID);
}

public any Native_Operation_IsValid(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);

	int iThis = view_as<int>(mOp)-1;
	if (iThis < 0 || iThis >= m_hOperations.Length) {
		return false;
	}

	return !m_hOperations.Get(iThis, _Operation::bGCFlag);
}

public any Native_Operation_AddSubOperation(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Operation mSubOp = GetNativeCell(2);
	int iIndex = GetNativeCell(3);

	if (!mOp.IsValid() || !mSubOp.IsValid() || iIndex < -1) {
		return false;
	}

	int iThis = view_as<int>(mOp)-1;

	ArrayList hSubOpRefs = m_hOperations.Get(iThis, _Operation::hSubOpRefs);
	if (!hSubOpRefs) {
		ThrowError("Suboperations are not supported by this Operation");
	}

	if (iIndex == -1 || iIndex >= hSubOpRefs.Length) {
		hSubOpRefs.Push(mSubOp.ToOpRef());
	} else {
		hSubOpRefs.ShiftUp(iIndex);
		hSubOpRefs.Set(iIndex, mSubOp.ToOpRef());
	}

	Bot mBot = m_hOperations.Get(iThis, _Operation::mBot);
	if (mBot) {
		m_hOperations.Set(view_as<int>(mSubOp)-1, mBot, _Operation::mBot);
	}

	return true;
}

public any Native_Operation_ClearSubOperations(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);

	ArrayList hSubOpRefs = m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hSubOpRefs);
	if (hSubOpRefs) {
		for (int i=0; i<hSubOpRefs.Length; i++) {
			OpRef mSubOpRef = hSubOpRefs.Get(i);
			Operation mSubOp = mSubOpRef.ToOperation();
			if (mSubOp.IsValid()) {
				Operation.Destroy(mSubOp);
			}
		}

		hSubOpRefs.Clear();
	}

	return 0;
}

public any Native_Operation_AddStateChangeForward(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Function fnFwd = GetNativeFunction(2);

	PrivateForward hFwd = m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hStateChangeForward);
	return hFwd.AddFunction(hPlugin, fnFwd);
}

public any Native_Operation_RemoveStateChangeForward(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Function fnFwd = GetNativeFunction(2);

	PrivateForward hFwd = m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hStateChangeForward);
	return hFwd.RemoveFunction(hPlugin, fnFwd);
}

public any Native_Operation_AddStepForward(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Function fnFwd = GetNativeFunction(2);

	PrivateForward hFwd = m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hStepForward);
	return hFwd.AddFunction(hPlugin, fnFwd);
}

public any Native_Operation_RemoveStepForward(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Function fnFwd = GetNativeFunction(2);

	PrivateForward hFwd = m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hStepForward);
	return hFwd.RemoveFunction(hPlugin, fnFwd);
}

public any Native_Operation_AddAbortForward(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Function fnFwd = GetNativeFunction(2);

	PrivateForward hFwd = m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hAbortForward);
	return hFwd.AddFunction(hPlugin, fnFwd);
}

public any Native_Operation_RemoveAbortForward(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	Function fnFwd = GetNativeFunction(2);

	PrivateForward hFwd = m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hAbortForward);
	return hFwd.RemoveFunction(hPlugin, fnFwd);
}

public any Native_Operation_ToOpRef(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);

	if (mOp.IsValid()) {
		return view_as<OpRef>(mOp.iUID << 14 | view_as<int>(mOp));
	}

	return INVALID_OPERATION_REFERENCE;
}

public any Native_Operation_Init(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	if (!mOp.IsValid()) {
		ThrowError("Invalid Operation");
	}

	Bot mBot = GetNativeCell(2);

	bool bSilentFail = GetNativeCell(3);

	int iOpIdx = view_as<int>(mOp)-1;
	_Operation eOp;
	m_hOperations.GetArray(iOpIdx, eOp);

	if (eOp.iOpState == OpState_Run && mBot != eOp.mBot) {
		LogError("Operation.%s(%d) was bound on start to %L and cannot be run on %L.", eOp.sIdentifier, eOp.iUID, eOp.mBot.iEntity, mBot.iEntity);
		return OpRet_Abort;
	}

	switch (eOp.iOpState) {
		case OpState_Pend: {
			eOp.hInitParams.Rewind();

			PrintToServer("RunOp %s: Initializing", eOp.sIdentifier);

			if (eOp.fnInit != INVALID_FUNCTION) {
				Call_StartFunction(eOp.hPlugin, eOp.fnInit);
				Call_PushCell(mBot);
				Call_PushCell(mOp);
				Call_PushCell(eOp.hInitParams);
				Call_PushCell(eOp.hSequences);
				Call_PushCell(eOp.hSubOpRefs);
				Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

				OpRet iReturn;
				int iCallError = Call_Finish(iReturn);
				if (iCallError != SP_ERROR_NONE) {
					if (bSilentFail) {
						return OpRet_Abort;
					}

					return InternalAbort(mBot, mOp, eOp, "initialization function call returned error code %d", iCallError);
				}

				if (iReturn == OpRet_Abort) {
					if (bSilentFail) {
						return OpRet_Abort;
					}

					m_hOperations.GetArray(iOpIdx, eOp);
					return InternalAbort(mBot, mOp, eOp, "initialization aborted (%s)", eOp.sError);
				}
			}

			eOp.iOpState = OpState_Run;
			eOp.fStartTime = GetGameTime();
			eOp.mBot = mBot;
			m_hOperations.SetArray(iOpIdx, eOp);

			Call_StartForward(eOp.hStateChangeForward);
			Call_PushCell(mBot);
			Call_PushCell(mOp);
			Call_PushCell(OpState_Run);
			Call_Finish();
		}
		case OpState_Abort: {
			PrintToServer("Attempted to run an aborted Operation.%s(%d)", eOp.sIdentifier, eOp.iUID);
			return OpRet_Abort;
		}
		case OpState_Complete: {
			PrintToServer("Attempted to run a completed Operation.%s(%d)", eOp.sIdentifier, eOp.iUID);
			return OpRet_Abort;
		}
	}

	return OpRet_Continue;
}

public any Native_Operation_Interrupt(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	if (!mOp.IsValid()) {
		return false;
	}

	_Operation eOp;
	m_hOperations.GetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	switch (eOp.iOpState) {
		case OpState_Run: {
			if (eOp.fnSuspend != INVALID_FUNCTION) {
				Call_StartFunction(eOp.hPlugin, eOp.fnSuspend);
				Call_PushCell(eOp.mBot);
				Call_PushCell(mOp);
				Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

				OpRet iOpRet;
				int iCallError = Call_Finish(iOpRet);
				if (iCallError != SP_ERROR_NONE) {
					return false;
				}

				if (iOpRet == OpRet_Abort) {
					m_hOperations.SetArray(view_as<int>(mOp)-1, eOp);
					mOp.Abort();
					return false;
				}

				eOp.iOpState = OpState_Suspend;
				m_hOperations.SetArray(view_as<int>(mOp)-1, eOp);

				return true;
			}

			m_hOperations.Set(view_as<int>(mOp)-1, OpState_Suspend, _Operation::iOpState);

			return true;
		}
		case OpState_Suspend: {
			return true;
		}
	}

	return false;
}

public any Native_Operation_Resume(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	if (!mOp.IsValid()) {
		return false;
	}

	_Operation eOp;
	m_hOperations.GetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	switch (eOp.iOpState) {
		case OpState_Run: {
			return true;
		}
		case OpState_Suspend: {
			if (eOp.fnResume != INVALID_FUNCTION) {
				Call_StartFunction(eOp.hPlugin, eOp.fnResume);
				Call_PushCell(eOp.mBot);
				Call_PushCell(mOp);
				Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

				OpRet iOpRet;
				int iCallError = Call_Finish(iOpRet);
				if (iCallError != SP_ERROR_NONE) {
					return false;
				}

				switch (iOpRet) {
					case OpRet_Handled: {
						m_hOperations.SetArray(view_as<int>(mOp)-1, eOp);
						return false;
					}
					case OpRet_Restart: {
						m_hOperations.SetArray(view_as<int>(mOp)-1, eOp);
						mOp.Restart();
						return true;
					}
					case OpRet_Abort: {
						m_hOperations.SetArray(view_as<int>(mOp)-1, eOp);
						mOp.Abort();
						return true;
					}
				}

				eOp.iOpState = OpState_Suspend;
				m_hOperations.SetArray(view_as<int>(mOp)-1, eOp);

				return true;
			}

			m_hOperations.Set(view_as<int>(mOp)-1, OpState_Suspend, _Operation::iOpState);

			return true;
		}
	}

	return false;
}

public any Native_Operation_Abort(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	if (!mOp.IsValid()) {
		return 0;
	}

	bool bAbortAsComplete = GetNativeCell(2);

	_Operation eOp;
	m_hOperations.GetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	if (eOp.hSubOpRefs) {
		int iSubOpRefsLength = eOp.hSubOpRefs.Length;
		for (int i=0; i<iSubOpRefsLength; i++) {
			OpRef mSubOpRef = eOp.hSubOpRefs.Get(i);
			Operation mSubOp = mSubOpRef.ToOperation();
			if (mSubOp.IsValid()) {
				Operation.Destroy(mSubOp);
			}
		}

		eOp.hSubOpRefs.Clear();
	}

	if (eOp.fnCleanup != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnCleanup);
		Call_PushCell(eOp.mBot);
		Call_PushCell(mOp);
		Call_PushCell(eOp.hSequences);
		Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

		int iCallError = Call_Finish();
		if (iCallError != SP_ERROR_NONE) {
			LogStackTrace("Operation.%s(%d) cleanup function call returned error code %d", eOp.sIdentifier, eOp.iUID, iCallError);
		}
	}

	eOp.hSequences.Clear();

	eOp.iOpState = bAbortAsComplete ? OpState_Complete : OpState_Abort;
	m_hOperations.SetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	Call_StartForward(eOp.hStateChangeForward);
	Call_PushCell(eOp.mBot);
	Call_PushCell(mOp);
	Call_PushCell(eOp.iOpState);
	Call_Finish();

	if (!bAbortAsComplete) {
		char sBuffer[256];
		FormatEx(sBuffer, sizeof(sBuffer), "Operation.%s(%d) abort called", eOp.sIdentifier, eOp.iUID);

		Call_StartForward(eOp.hAbortForward);
		Call_PushCell(eOp.mBot);
		Call_PushCell(mOp);
		Call_PushString(sBuffer);
		Call_Finish();
	}

	return 0;
}

public any Native_Operation_Restart(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);

	_Operation eOp;
	m_hOperations.GetArray(view_as<int>(mOp)-1, eOp, sizeof(_Operation));

	if (eOp.hSubOpRefs) {
		int iSubOpRefsLength = eOp.hSubOpRefs.Length;
		for (int i=0; i<iSubOpRefsLength; i++) {
			OpRef mSubOpRef = eOp.hSubOpRefs.Get(i);
			Operation mSubOp = mSubOpRef.ToOperation();
			if (mSubOp.IsValid()) {
				Operation.Destroy(mSubOp);
			}
		}

		eOp.hSubOpRefs.Clear();
	}

	if (eOp.fnCleanup != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnCleanup);
		Call_PushCell(eOp.mBot);
		Call_PushCell(mOp);
		Call_PushCell(eOp.hSequences);
		Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

		int iCallError = Call_Finish();
		if (iCallError != SP_ERROR_NONE) {
			LogStackTrace("Operation.%s(%d) cleanup function call returned error code %d", eOp.sIdentifier, eOp.iUID, iCallError);
		}
	}

	eOp.hSequences.Clear();

	eOp.iOpState = OpState_Pend;
	m_hOperations.SetArray(view_as<int>(mOp)-1, eOp);

	Call_StartForward(eOp.hStateChangeForward);
	Call_PushCell(eOp.mBot);
	Call_PushCell(mOp);
	Call_PushCell(OpState_Pend);
	Call_Finish();

	return 0;
}

public any Native_Operation_Clone(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);
	if (!mOp.IsValid()) {
		return NULL_OPERATION;
	}

	char sIdentifier[64];
	m_hOperations.GetString(view_as<int>(mOp)-1, sIdentifier, sizeof(sIdentifier));

	KeyValues hInitParams =	m_hOperations.Get(view_as<int>(mOp)-1, _Operation::hInitParams);

	KeyValues hCloneInitParams;
	Operation mCloneOp = Operation.Instance(sIdentifier, hCloneInitParams);

	hInitParams.Rewind();
	hCloneInitParams.Import(hInitParams);

	return mCloneOp;
}

public any Native_Operation__Abort(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCell(1);

	char sBuffer[256];
	FormatNativeString(0, 2, 3, sizeof(sBuffer), _, sBuffer);

	mOp.SetError(sBuffer);

	return OpRet_Abort;
}

public int Native_Operation_Register(Handle hPlugin, int iArgC) {
	_OperationTemplate eOperationTemplate;
	eOperationTemplate.hPlugin = hPlugin;

	GetNativeString(1, eOperationTemplate.sIdentifier, sizeof(_OperationTemplate::sIdentifier));

	if (m_hOperationTemplates.ContainsKey(eOperationTemplate.sIdentifier)) {
		_OperationTemplate eExistingOperationTemplate;
		m_hOperationTemplates.GetArray(eOperationTemplate.sIdentifier, eExistingOperationTemplate, sizeof(_OperationTemplate));

		if (eExistingOperationTemplate.hPlugin != hPlugin) {
			ThrowError("Operation with this identifier is already registered: %s", eOperationTemplate.sIdentifier);
		}
	}

	// OpInitFunc
	eOperationTemplate.fnInit = GetNativeFunction(2);

	// OpValidateFunc
	eOperationTemplate.fnValidate = GetNativeFunction(3);

	// OpFunc
	eOperationTemplate.fnPreRun = GetNativeFunction(4);

	// OpFunc
	eOperationTemplate.fnPostRun = GetNativeFunction(5);

	// OpFunc
	eOperationTemplate.fnSuspend = GetNativeFunction(6);

	// OpFunc
	eOperationTemplate.fnResume = GetNativeFunction(7);

	// CleanupFunc
	eOperationTemplate.fnCleanup = GetNativeFunction(8);

	eOperationTemplate.bLoop = GetNativeCell(9);
	eOperationTemplate.bHasSubOps = GetNativeCell(10);
	eOperationTemplate.bConcurrent = GetNativeCell(11);
	eOperationTemplate.bCascadeAborts = GetNativeCell(12);

	eOperationTemplate.hInstances = new ArrayList();
	eOperationTemplate.hEventForwards = new StringMap();

	if (m_hOperationTemplates.SetArray(eOperationTemplate.sIdentifier, eOperationTemplate, sizeof(_OperationTemplate), false)) {
		PrintToServer("SMBL registered operation: %s", eOperationTemplate.sIdentifier);

		return true;
	}

	PrintToServer("SMBL failed to register operation (duplicate?): %s", eOperationTemplate.sIdentifier);

	return false;
}

public int Native_Operation_Deregister(Handle hPlugin, int iArgC) {
	if (IsNativeParamNullString(1)) {
		StringMapSnapshot hOperationTemplatesSnapshot = m_hOperationTemplates.Snapshot();

		for (int i=0; i<hOperationTemplatesSnapshot.Length; i++) {
			char sIdentifier[64];
			hOperationTemplatesSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));

			_OperationTemplate eOperationTemplate;
			if (m_hOperationTemplates.GetArray(sIdentifier, eOperationTemplate, sizeof(_OperationTemplate)) && eOperationTemplate.hPlugin == hPlugin) {

				StringMapSnapshot hEventForwardsSnapshot = eOperationTemplate.hEventForwards.Snapshot();

				for (int j=0; j<hEventForwardsSnapshot.Length; j++) {
					char sEvent[64];
					hEventForwardsSnapshot.GetKey(j, sEvent, sizeof(sEvent));

					PrivateForward hEventForward;
					eOperationTemplate.hEventForwards.GetValue(sEvent, hEventForward);
					delete hEventForward;
				}

				delete hEventForwardsSnapshot;
				delete eOperationTemplate.hEventForwards;

				DestroyDeregisteredOperation(sIdentifier);

				delete eOperationTemplate.hInstances;
				m_hOperationTemplates.Remove(sIdentifier);

				PrintToServer("SMBL deregistered operation: %s", eOperationTemplate.sIdentifier);
			}
		}

		delete hOperationTemplatesSnapshot;

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


		StringMapSnapshot hEventForwardsSnapshot = eOperationTemplate.hEventForwards.Snapshot();

		for (int j=0; j<hEventForwardsSnapshot.Length; j++) {
			char sEvent[64];
			hEventForwardsSnapshot.GetKey(j, sEvent, sizeof(sEvent));

			PrivateForward hEventForward;
			eOperationTemplate.hEventForwards.GetValue(sEvent, hEventForward);
			delete hEventForward;
		}

		delete hEventForwardsSnapshot;
		delete eOperationTemplate.hEventForwards;

		DestroyDeregisteredOperation(sIdentifier);

		delete eOperationTemplate.hInstances;
		m_hOperationTemplates.Remove(sIdentifier);

		return true;
	}

	return false;
}

public any Native_Operation_Instance(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	KeyValues hInitParams = GetNativeCellRef(2);

	Op iOp = GetNativeCell(3);

	_OperationTemplate eOperationTemplate;
	if (m_hOperationTemplates.GetArray(sIdentifier, eOperationTemplate, sizeof(_OperationTemplate))) {
		_Operation eOp;
		eOp.iOp = iOp;
		eOp.sIdentifier = eOperationTemplate.sIdentifier;
		eOp.hPlugin = eOperationTemplate.hPlugin;

		eOp.iUID = m_iUID++;

		if (hInitParams == null) {
			hInitParams = new KeyValues("InitParams");
			SetNativeCellRef(2, hInitParams);
		} else {
			eOp.bInitParamsExternal = true;
		}

		eOp.hInitParams = hInitParams;
		eOp.bLoop = eOperationTemplate.bLoop;
		eOp.bConcurrent = eOperationTemplate.bConcurrent;
		eOp.bCascadeAborts = eOperationTemplate.bCascadeAborts;

		eOp.hSequences = new ArrayList(sizeof(Sequence));

		if (eOperationTemplate.bHasSubOps) {
			eOp.hSubOpRefs = new ArrayList();
		}

		eOp.fnValidate = eOperationTemplate.fnValidate;
		eOp.fnInit = eOperationTemplate.fnInit;
		eOp.fnPreRun = eOperationTemplate.fnPreRun;
		eOp.fnPostRun = eOperationTemplate.fnPostRun;
		eOp.fnSuspend = eOperationTemplate.fnSuspend;
		eOp.fnResume = eOperationTemplate.fnResume;
		eOp.fnCleanup = eOperationTemplate.fnCleanup;

		eOp.hEventForward = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

		eOp.hStateChangeForward = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
		eOp.hStepForward = new PrivateForward(ET_Hook, Param_Cell, Param_Cell);
		eOp.hAbortForward = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_String);

		Operation mOp;
		int iFreeIdx = m_hOperations.FindValue(true, _Operation::bGCFlag);
		if (iFreeIdx != -1) {
			if (m_hOperations.Length == OP_ALLOC_MAX) {
				ThrowError("Op_Alloc: No free operations");
			}

			m_hOperations.SetArray(iFreeIdx, eOp);

			mOp = view_as<Operation>(iFreeIdx+1);
		} else {
			mOp = view_as<Operation>(m_hOperations.PushArray(eOp)+1);
		}

		eOperationTemplate.hInstances.Push(mOp);

		return mOp;
	}

	LogError("No Operation template found with identifier: %s", sIdentifier);

	return NULL_OPERATION;
}

public any Native_Operation_Destroy(Handle hPlugin, int iArgC) {
	Operation mOp = GetNativeCellRef(1);
	if (!mOp.IsValid()) {
		return 0;
	}

	int iThis = view_as<int>(mOp)-1;

	m_hOperations.Set(iThis, true, _Operation::bGCFlag);

	_Operation eOp;
	m_hOperations.GetArray(iThis, eOp);

	_OperationTemplate eOperationTemplate;
	m_hOperationTemplates.GetArray(eOp.sIdentifier, eOperationTemplate, sizeof(_OperationTemplate));
	int iInstanceIdx = eOperationTemplate.hInstances.FindValue(mOp);
	if (iInstanceIdx != -1) {
		eOperationTemplate.hInstances.Erase(iInstanceIdx);
	}

	if (!eOp.bInitParamsExternal) {
		delete eOp.hInitParams;
	}

	eOp.hInitParams = null;

	delete eOp.hStateChangeForward;
	delete eOp.hStepForward;
	delete eOp.hAbortForward;

	if (eOp.hSubOpRefs) {
		int iSubOpRefsLength = eOp.hSubOpRefs.Length;
		for (int i=0; i<iSubOpRefsLength; i++) {
			OpRef mSubOpRef = eOp.hSubOpRefs.Get(i);
			Operation mSubOp = mSubOpRef.ToOperation();
			if (mSubOp.IsValid()) {
				Operation.Destroy(mSubOp);
			}
		}

		delete eOp.hSubOpRefs;
	}

	if (eOp.fnCleanup != INVALID_FUNCTION) {
		Call_StartFunction(eOp.hPlugin, eOp.fnCleanup);
		Call_PushCell(eOp.mBot);
		Call_PushCell(mOp);
		Call_PushCell(eOp.hSequences);
		Call_PushArrayEx(eOp.eOpData, sizeof(_Operation::eOpData), SM_PARAM_COPYBACK);

		int iCallError = Call_Finish();
		if (iCallError != SP_ERROR_NONE) {
			LogStackTrace("Operation.%s(%d) cleanup function call returned error code %d", eOp.sIdentifier, eOp.iUID, iCallError);
		}
	}

	delete eOp.hSequences;

	SetNativeCellRef(1, NULL_OPERATION);

	if (iThis == m_hOperations.Length-1) {
		for (int i=iThis; i>0; i--) {
			if (!m_hOperations.Get(i-1, _Operation::bGCFlag)) {
				m_hOperations.Resize(i);
				return 0;
			}
		}

		m_hOperations.Clear();
	}

	return 0;
}

public any Native_Operation_AddEventListener(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	char sEvent[64];
	GetNativeString(2, sEvent, sizeof(sEvent));

	Function fnEventForward = GetNativeFunction(3);

	_OperationTemplate eOperationTemplate;
	if (!m_hOperationTemplates.GetArray(sIdentifier, eOperationTemplate, sizeof(_OperationTemplate))) {
		return false;
	}

	PrivateForward hEventForward;
	if (!eOperationTemplate.hEventForwards.GetValue(sEvent, hEventForward)) {
		hEventForward = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Array, Param_Cell);
		eOperationTemplate.hEventForwards.SetValue(sEvent, hEventForward);
	}

	return hEventForward.AddFunction(hPlugin, fnEventForward);
}

public any Native_Operation_RemoveEventListener(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	char sEvent[64];
	GetNativeString(2, sEvent, sizeof(sEvent));

	Function fnEventForward = GetNativeFunction(3);

	_OperationTemplate eOperationTemplate;
	if (!m_hOperationTemplates.GetArray(sIdentifier, eOperationTemplate, sizeof(_OperationTemplate))) {
		return false;
	}

	PrivateForward hEventForward;
	if (!eOperationTemplate.hEventForwards.GetValue(sEvent, hEventForward)) {
		return false;
	}

	return hEventForward.RemoveFunction(hPlugin, fnEventForward);
}

public any Native_Operation_DispatchEvent(Handle hPlugin, int iArgC) {
	char sIdentifier[64];
	GetNativeString(1, sIdentifier, sizeof(sIdentifier));

	char sEvent[64];
	GetNativeString(2, sEvent, sizeof(sEvent));

	any aData = GetNativeCell(3);

	_OperationTemplate eOperationTemplate;
	if (!m_hOperationTemplates.GetArray(sIdentifier, eOperationTemplate, sizeof(_OperationTemplate))) {
		return false;
	}

	PrivateForward hEventForward;
	if (!eOperationTemplate.hEventForwards.GetValue(sEvent, hEventForward)) {
		return false;
	}

	if (hPlugin == eOperationTemplate.hPlugin) {
		for (int i=0; i<eOperationTemplate.hInstances.Length; i++) {
			Operation mOp = eOperationTemplate.hInstances.Get(i);
			_Operation eOp;
			m_hOperations.GetArray(view_as<int>(mOp)-1, eOp);

			Call_StartForward(hEventForward);
			Call_PushCell(eOp.mBot);
			Call_PushCell(mOp);
			Call_PushArrayEx(eOp.eOpData, sizeof(OpData), SM_PARAM_COPYBACK);
			Call_PushCell(aData);
			Call_Finish();

			m_hOperations.SetArray(view_as<int>(mOp)-1, eOp);
		}
	} else {
		for (int i=0; i<eOperationTemplate.hInstances.Length; i++) {
			Operation mOp = eOperationTemplate.hInstances.Get(i);
			_Operation eOp;
			m_hOperations.GetArray(view_as<int>(mOp)-1, eOp);

			Call_StartForward(hEventForward);
			Call_PushCell(eOp.mBot);
			Call_PushCell(mOp);
			Call_PushArray(eOp.eOpData, sizeof(OpData));
			Call_PushCell(aData);
			Call_Finish();
		}
	}

	return true;
}

public any Native_OpRef_ToOperation(Handle hPlugin, int iArgC) {
	OpRef mOpRef = GetNativeCell(1);

	if (mOpRef == INVALID_OPERATION_REFERENCE) {
		return NULL_OPERATION;
	}

	Operation mOp = view_as<Operation>(view_as<int>(mOpRef) & 0x3FFF);
	int iUID = view_as<int>(mOpRef) >> 14;

	if (mOp.IsValid() && mOp.iUID == iUID) {
		return mOp;
	}

	return NULL_OPERATION;
}

// Custom callbacks

public Action Callback_SubOpAborted(Bot mBot, Operation mOp, char[] sError, Operation mParentOp) {
	mParentOp.SetError(sError);

	return Plugin_Handled;
}

// Helpers

void DestroyDeregisteredOperation(char[] sTemplateIdentifier) {
	char sIdentifier[64];
	for (int i=0; i<m_hOperations.Length; i++) {
		if (m_hOperations.Get(i, _Operation::bGCFlag)) {
			continue;
		}

		m_hOperations.GetString(i, sIdentifier, sizeof(sIdentifier));
		if (StrEqual(sIdentifier, sTemplateIdentifier)) {
			Operation mOp = view_as<Operation>(i+1);
			Operation.Destroy(mOp);
		}
	}
}

OpRet InternalAbort(Bot mBot, Operation mOperation, _Operation eOp, char[] sFormat, any ...) {
	SetGlobalTransTarget(LANG_SERVER);
	VFormat(eOp.sError, sizeof(_Operation::sError), sFormat, 5);

	Format(eOp.sError, sizeof(_Operation::sError), "Operation.%s(%d) %s", eOp.sIdentifier, eOp.iUID, eOp.sError);

	eOp.iOpState = OpState_Abort;
	m_hOperations.SetArray(view_as<int>(mOperation)-1, eOp);

	LogError(eOp.sError);

	Call_StartForward(eOp.hStateChangeForward);
	Call_PushCell(mBot);
	Call_PushCell(mOperation);
	Call_PushCell(OpState_Abort);
	Call_Finish();

	Call_StartForward(eOp.hAbortForward);
	Call_PushCell(mBot);
	Call_PushCell(mOperation);
	Call_PushString(eOp.sError);
	Call_Finish();

	return OpRet_Abort;
}

void ShowOperationStatus(int iClient) {
	StringMap hOpStatsMap = new StringMap();

	int iTotalOps;

	for (int i=0; i<m_hOperations.Length; i++) {
		_Operation eOp;
		m_hOperations.GetArray(i, eOp);

		if (!eOp.bGCFlag) {
			int iOpCount;
			hOpStatsMap.GetValue(eOp.sIdentifier, iOpCount);
			hOpStatsMap.SetValue(eOp.sIdentifier, iOpCount+1);

			iTotalOps++;
		}
	}

	char sIdentifier[64];
	StringMapSnapshot hSnapshot = hOpStatsMap.Snapshot();

	ArrayList hIdentifiers = new ArrayList(ByteCountToCells(sizeof(sIdentifier)));

	for (int i=0; i<hSnapshot.Length; i++) {
		hSnapshot.GetKey(i, sIdentifier, sizeof(sIdentifier));
		hIdentifiers.PushString(sIdentifier);
	}

	hIdentifiers.Sort(Sort_Ascending, Sort_String);

	int iBotCount = SMBL_GetBots();

	ReplyToCommand(
		iClient,
		"smbl running %d bot%s, %d operation%s of %d max (%d allocated)",
		iBotCount, iBotCount == 1 ? "" : "s",
		iTotalOps, iTotalOps == 1 ? "" : "s",
		OP_ALLOC_MAX, m_hOperations.Length
	);

	for (int i=0; i<hIdentifiers.Length; i++) {
		hIdentifiers.GetString(i, sIdentifier, sizeof(sIdentifier));

		int iOpCount;
		hOpStatsMap.GetValue(sIdentifier, iOpCount);

		ReplyToCommand(iClient, " %4d %s", iOpCount, sIdentifier);
	}

	delete hSnapshot;
	delete hIdentifiers;
	delete hOpStatsMap;
}
