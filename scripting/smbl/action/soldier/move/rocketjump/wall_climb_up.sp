enum struct OpData_Wall_Climb_Up {
	OpRef mWallPogoUpOpRef;
	float fDestinationZ;
	any aPadding[9];
}

// Operation callbacks

OpRet Wall_Climb_Up_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Wall_Climb_Up eOpData, bool bConfigureOnly) {
	if (hInitParams.JumpToKey("destination_z")) {
		hInitParams.GoBack();

		eOpData.fDestinationZ = hInitParams.GetFloat("destination_z");
	} else {
		if (!hInitParams.JumpToKey("destination")) {
			return mOp._Abort("missing destination_z init parameter");
		}

		hInitParams.GoBack();

		float vecDest[3];
		hInitParams.GetVector("destination", vecDest);

		eOpData.fDestinationZ = vecDest[2];
	}

	hInitParams.GoBack();

	if (!hInitParams.JumpToKey("wall_normal")) {
		return mOp._Abort("missing parameter wall_normal");
	}

	hInitParams.GoBack();

	float vecWallNormal[3];
	hInitParams.GetVector("wall_normal", vecWallNormal);

	int iEntity = mBot.iEntity;
	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return mOp._Abort("cannot init while grounded");
	}

	Operation mSubOp;

	mSubOp = Operation.Instance("Soldier.Move.RocketJump.Wall.Pogo.Up");
	eOpData.mWallPogoUpOpRef = mSubOp.ToOpRef();
	hSubOpRefs.Push(eOpData.mWallPogoUpOpRef);

	KeyValues hWallClimbInitParams;
	mSubOp = Operation.Instance("Soldier.Move.RocketJump.Wall.Climb.Pull", hWallClimbInitParams, view_as<Op>(1));
	hWallClimbInitParams.SetVector("wall_normal", vecWallNormal);
	hWallClimbInitParams.SetNum("ledge", true);
	hSubOpRefs.Push(mSubOp.ToOpRef());

	return OpRet_Continue;
}

OpRet Wall_Climb_Up_PreRun(Bot mBot, Operation mOp, OpData_Wall_Climb_Up eOpData) {
	if (eOpData.mWallPogoUpOpRef == INVALID_OPERATION_REFERENCE) {
		return OpRet_Continue;
	}

	int iEntity = mBot.iEntity;

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	if (vecPos[2] > eOpData.fDestinationZ) {
		Operation mWallPogoOp = eOpData.mWallPogoUpOpRef.ToOperation();

		if (mWallPogoOp.IsValid()) {
			mWallPogoOp.Abort(true);
		}

		eOpData.mWallPogoUpOpRef = INVALID_OPERATION_REFERENCE;
	}

	return OpRet_Continue;
}

void Wall_Climb_Up_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Wall_Climb_Up eOpData) {
	if (mBot) {
		mBot.iButtons = 0;
		mBot.SetLocalVelocity({0.0, 0.0, 0.0});
	}
}
