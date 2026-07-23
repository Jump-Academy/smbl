OpRet Parameterize_ByPosition_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData) {
	hInitParams.Rewind();

	bool bPreferForward = hInitParams.GetNum("prefer_forward", 0) != 0;

	if (!hInitParams.JumpToKey("positions")) {
		return mOp._Abort("missing positions init parameter");
	}

	if (!hInitParams.GotoFirstSubKey(true)) {
		return OpRet_Continue;
	}

	int iEntity = mBot.iEntity;

	float vecOrigin[3];
	Entity_GetAbsOrigin(iEntity, vecOrigin);

	float vecAng[3];
	Entity_GetAbsAngles(iEntity, vecAng);

	float vecFwd[3];
	GetAngleVectors(vecAng, vecFwd, NULL_VECTOR, NULL_VECTOR);

	char sMinParamIdx[8];
	float fMinDist = POSITIVE_INFINITY;

	char sMinFrontParamIdx[8];
	float fMinFrontDist = POSITIVE_INFINITY;

	do {
		char sParamIdx[8];
		hInitParams.GetSectionName(sParamIdx, sizeof(sParamIdx));

		float vecPos[3];
		hInitParams.GetVector("origin", vecPos);

		float vecDiff[3];
		SubtractVectors(vecPos, vecOrigin, vecDiff);

		float fDist = GetVectorLength(vecDiff);
		if (fDist < fMinDist) {
			fMinDist = fDist;
			sMinParamIdx = sParamIdx;
		}

		NormalizeVector(vecDiff, vecDiff);

		// Front-facing
		if (GetVectorDotProduct(vecDiff, vecFwd) > 0) {
			if (fDist < fMinFrontDist) {
				fMinFrontDist = fDist;
				sMinFrontParamIdx = sParamIdx;
			}
		}

	} while (hInitParams.GotoNextKey(true));

	hInitParams.GoBack(); // from subkey
	hInitParams.GoBack(); // from positions

	if (bPreferForward && fMinFrontDist < POSITIVE_INFINITY) {
		sMinParamIdx = sMinFrontParamIdx;
	}

	if (!hInitParams.JumpToKey("operations")) {
		return mOp._Abort("missing operations init parameter");
	}

	if (!hInitParams.GotoFirstSubKey(false)) {
		return OpRet_Continue;
	}

	StringMap hOperations = new StringMap();

	do {
		char sOperationIdx[8];
		hInitParams.GetSectionName(sOperationIdx, sizeof(sOperationIdx));

		Operation mOperation = view_as<Operation>(hInitParams.GetNum(NULL_STRING));

		hOperations.SetValue(sOperationIdx, mOperation);
	} while (hInitParams.GotoNextKey(false));

	hInitParams.Rewind();
	hInitParams.JumpToKey("positions");
	hInitParams.JumpToKey(sMinParamIdx);
	hInitParams.JumpToKey("parameters");

	StringMapSnapshot hSnapshot = hOperations.Snapshot();
	for (int i=0; i<hSnapshot.Length; i++) {
		char sOperationIdx[8];
		hSnapshot.GetKey(i, sOperationIdx, sizeof(sOperationIdx));

		Operation mOperation;
		hOperations.GetValue(sOperationIdx, mOperation);

		if (mOperation) {
			hInitParams.JumpToKey(sOperationIdx);

			CopyKeyValues(hInitParams, mOperation.hInitParams);

			hInitParams.GoBack();
		}
	}
	delete hSnapshot;

	delete hOperations;

	hInitParams.Rewind();

	return OpRet_Continue;
}

void CopyKeyValues(KeyValues hKVSource, KeyValues hKVDestination) {
	// Cannot do this directly, unlike ImportFromString this does not merge but replaces the whole subtree instead
// 	hKVDestination.Import(hKVSource);

	// Waiting for PR of this new function with the correct behavior: https://github.com/alliedmodders/sourcemod/pull/2184
// 	hKVDestination.Merge(hKVSource);

	// Temporary workaround
	char sBuffer[4096];
	hKVSource.ExportToString(sBuffer, sizeof(sBuffer));
	hKVDestination.ImportFromString(sBuffer);

	hKVDestination.SetSectionName(OP_INIT_PARAM);
}
