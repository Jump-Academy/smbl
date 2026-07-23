// enum struct OpData_Walk_Beeline {
// 	float vecDest[3];
// 	float vecLastPos[3];
// 	float fGoalProximity;
// 	any aPadding[9];
// }

// Operation callbacks

OpRet Walk_Beeline_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Walk eOpData) {
	if (hInitParams.JumpToKey("origin")) {
		hInitParams.GoBack();
		hInitParams.GetVector("origin", eOpData.vecLastPos);
	} else {
		Entity_GetAbsOrigin(mBot.iEntity, eOpData.vecLastPos);
	}

	if (!hInitParams.JumpToKey("destination")) {
		return mOp._Abort("missing destination init parameter");
	}

	SeqData_Walk eSeqData;
	hInitParams.GetVector(NULL_STRING, eSeqData.vecDest)

	Sequence eSeq;
	eSeq.fnRun = Walk;
	eSeq.SetData(eSeqData);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk_Beeline [%.0f %.0f %.0f]", eSeqData.vecDest[0], eSeqData.vecDest[1], eSeqData.vecDest[2]);

	hSequences.PushArray(eSeq);

	eOpData.fGoalProximity = hInitParams.GetFloat("goal_proximity", DEFAULT_GOAL_PROXIMITY);

	hInitParams.Rewind();

	return OpRet_Continue;
}

OpRet Walk_Beeline_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Walk eOpData, float fStartTime) {
	if (hSequences.Length) {
		Sequence eSeq;
		hSequences.GetArray(0, eSeq);

		if (!eSeq.fStartTime) {
			return OpRet_Continue;
		}

		SeqData_Walk eSeqData;
		eSeq.GetData(eSeqData);

		float vecVector[3];
		SubtractVectors(eSeqData.vecDest, eOpData.vecLastPos, vecVector);
		NormalizeVector(vecVector, vecVector);

		float fTimeElapsed = GetGameTime() - eSeq.fStartTime;
		int iEntity = mBot.iEntity;

		float vecPos[3];
		Entity_GetAbsOrigin(iEntity, vecPos);

		float fMaxSpeed = GetEntPropFloat(iEntity, Prop_Data, "m_flMaxspeed");

		float vecExpectedPos[3];
		ScaleVector(vecVector, fMaxSpeed * fTimeElapsed);
		AddVectors(eOpData.vecLastPos, vecVector, vecExpectedPos);

		float vecVel[3];
		Entity_GetAbsVelocity(iEntity, vecVel);

		float fVel2D = SquareRoot(vecVel[0]*vecVel[0] + vecVel[1]*vecVel[1]);

		if (fVel2D < 0.5 * fMaxSpeed && GetVectorDistance(vecPos, vecExpectedPos) > 200.0) {
			return mOp._Abort("path deviation");
		}
	}

	return OpRet_Continue;
}
