OpRet WallClimb_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData eOpData) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("Unsupported TFClassType");
	}

	float vecDest[3];

	NavNode mStartNode = view_as<NavNode>(hInitParams.GetNum("start_node", view_as<int>(NULL_NAV_NODE)));
	NavNode mEndNode = view_as<NavNode>(hInitParams.GetNum("end_node", view_as<int>(NULL_NAV_NODE)));

	if (!mStartNode || !mEndNode) {
		NavMesh mNavMesh = SMBL_GetNavMesh("Ground");
		if (!mNavMesh) {
			return mOp._Abort("missing ground navigation mesh");
		}

		ArrayList hNodes = mNavMesh.GetNodes();
		PrintToServer("Looking up NavMesh with %d nodes", hNodes.Length);
		delete hNodes;

		float vecStart[3];
		Entity_GetAbsOrigin(iEntity, vecStart);

		PrintToServer("WalkClimb Start: %.1f, %.1f, %.1f", vecStart[0], vecStart[1], vecStart[2]);

		mStartNode = mStartNode ? mStartNode : mNavMesh.GetNearestNodeInRange(vecStart, NODE_PROXIMITY, true);
		if (!mStartNode) {
			return mOp._Abort("bot is not within mesh");
		}

		if (mEndNode) {
			mEndNode.GetOrigin(vecDest);
		} else {
			hInitParams.GetVector("destination", vecDest, {NaN, NaN, NaN});
			if (vecDest[0] == NaN) {
				return mOp._Abort("missing destination init parameter");
			}

			mEndNode = mNavMesh.GetNearestNodeInRange(vecDest, NODE_PROXIMITY, true);
			if (!mEndNode) {
				PrintToServer("End node is not within mesh.  Finding closest node.");
				mEndNode = mNavMesh.GetNearestNodeInRange(vecDest);
				if (!mEndNode) {
					return mOp._Abort("end point is not within mesh");
				}
			}
		}
	}

	int iEdge, iAttachedNodeEdge;
	int iAttachmentFlags;
	if (!mStartNode.FindAttachedNode(mEndNode, iEdge, _, iAttachmentFlags, iAttachedNodeEdge) || iAttachmentFlags & FL_ATTACH_WALL == 0) {
		return mOp._Abort("end node is not attached to start node");
	}

	eOpData.vecDest = vecDest;

	Sequence eSeq;
	eSeq.fnRun = WallClimb_Walk;
	eSeq.iSeq = view_as<Seq>(0);

	float vecVertexA[3], vecVertexB[3];
	mStartNode.GetEdgeOverlap(iEdge, mEndNode, iAttachedNodeEdge, vecVertexA, vecVertexB);

	eSeq.aData[0] = 0.5 * (vecVertexA[0] + vecVertexB[0]);
	eSeq.aData[1] = 0.5 * (vecVertexA[1] + vecVertexB[1]);
	eSeq.aData[2] = vecVertexA[2];

	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk [%.1f %.1f %.1f]", eSeq.aData[0], eSeq.aData[1], eSeq.aData[2]);

	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimb_Aim_Align_Wall;
	eSeq.iSeq = view_as<Seq>(1);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Aim_Align_Wall");
	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimb_Shoot_Ground;
	eSeq.iSeq = view_as<Seq>(2);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Shoot_Ground");
	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimb_Shoot_Wall;
	eSeq.iSeq = view_as<Seq>(3);
	eSeq.aData[2] = vecDest[2];
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Shoot_Wall");
	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimb_Airstrafe_Ledge;
	eSeq.iSeq = view_as<Seq>(4);
	eSeq.aData[0] = vecDest[0];
	eSeq.aData[1] = vecDest[1];
	eSeq.aData[2] = vecDest[2];
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Airstrafe_Ledge");
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

void WallClimb_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData eOpData) {
	PrintToServer("WallClimb Cleanup");
}

// Sequences

OpRet WallClimb_Walk(Bot mBot, Operation mOp, OpData eOpData, SeqData eSeqData, float fStartTime) {
	mBot.SetMoveTo(eSeqData.vecDest);

	int iEntity = mBot.iEntity;

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	float vecDelta[3];
	SubtractVectors(eSeqData.vecDest, vecPos, vecDelta);

	if (GetVectorLength(vecDelta) < WALL_MIN_REACH) {
		return OpRet_Handled;
	}

	float vecAimAng[3];
	GetVectorAngles(vecDelta, vecAimAng);
	mBot.SetAimTo(vecAimAng);

	float fYawError;
	mBot.GetAimError(_, fYawError);

	if (FloatAbs(fYawError) < 45.0) {
		mBot.iButtons |= IN_FORWARD;
		mBot.SetLocalVelocity({400.0, 0.0, 0.0});
		mBot.SetPID(PID_SLOW_LAZY);
	} else {
		mBot.SetPID(PID_FAST);
	}

	return OpRet_Continue;
}

OpRet WallClimb_Aim_Align_Wall(Bot mBot, Operation mOp, OpData eOpData, SeqData eSeqData, float fStartTime) {
	int iEntity = mBot.iEntity;

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	float vecAng[3];
	SubtractVectors(eSeqData.vecDest, vecPos, vecAng);
	GetVectorAngles(vecAng, vecAng);
	vecAng[0] = 0.0;

	TR_TraceRayFilter(vecPos, vecAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
	if (!TR_DidHit()) {
		return mOp._Abort("not facing any wall");
	}

	float vecPosAhead[3];
	TR_GetEndPosition(vecPosAhead);

	TR_GetPlaneNormal(null, vecAng);
	GetVectorAngles(vecAng, vecAng);

	float vecAimAng[3];
	vecAimAng[0] = 89.0;
	vecAimAng[1] = NormalizeAngle(vecAng[1] + 180.0);
	mBot.SetAimTo(vecAimAng);

	mBot.SetPID(PID_FAST);

// 	mBot.iButtons |= IN_FORWARD;
// 	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	float fPitchError;
	mBot.GetAimError(fPitchError, _);

// 	PrintToServer("Align: fPitchError=%.1f, fYawError=%.1f", fPitchError, fYawError);

	if (FloatAbs(fPitchError) < 2.0) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet WallClimb_Shoot_Ground(Bot mBot, Operation mOp, OpData eOpData, SeqData eSeqData, float fStartTime) {
	if (!fStartTime) {
		mBot.GetAimTo(eOpData.vecWallAng);
	}

	mBot.iButtons |= IN_FORWARD | IN_RIGHT | IN_JUMP | IN_DUCK | IN_ATTACK;
	mBot.SetLocalVelocity({400.0, 400.0, 0.0});

	float vecAimAng[3];
	mBot.GetAimTo(vecAimAng);
// 	vecAimAng[0] = 82.0;
	vecAimAng[0] = 80.0;
	vecAimAng[1] = NormalizeAngle(eOpData.vecWallAng[1] + 12.0);
	mBot.SetAimTo(vecAimAng);

// 	PrintToServer("WallClimb_Shoot_Ground vecAimAng=[%.1f %.1f %.1f]", eSeqData.vecWallAng[0], eSeqData.vecWallAng[1], eSeqData.vecWallAng[2]);

// 	eSeqData.fGroundShotTime = GetGameTime();

	return OpRet_Handled;
}

OpRet WallClimb_Shoot_Wall(Bot mBot, Operation mOp, OpData eOpData, SeqData eSeqData, float fStartTime) {
// 	PrintToServer("WallClimb_Shoot_Wall vecAimAng=[%.1f %.1f %.1f]", eSeqData.vecWallAng[0], eSeqData.vecWallAng[1], eSeqData.vecWallAng[2]);
// 	Abort(mOp, "Pause");
// 	return OpRet_Abort;

	mBot.iButtons = IN_FORWARD | IN_DUCK | IN_ATTACK;
	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	int iEntity = mBot.iEntity;
	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return mOp._Abort("touched ground early");
	}

	float fYawError;
	mBot.GetAimError(_, fYawError);

	if (FloatAbs(fYawError) > 1.0) {
		return OpRet_Continue;
	}

	mBot.SetPID(PID_FAST_PREC);

	int iWeapon = GetPlayerWeaponSlot(iEntity, TFWeaponSlot_Primary);
	float fLastFireTime = GetEntPropFloat(iWeapon, Prop_Send, "m_flLastFireTime");

	if (GetGameTime() - fLastFireTime <= 0.6) {
		mBot.iButtons = IN_FORWARD | IN_DUCK | IN_ATTACK | IN_MOVERIGHT;
		mBot.SetLocalVelocity({400.0, 400.0, 0.0});
	}

	float vecPos[3];
	GetClientEyePosition(iEntity, vecPos);
// 	GetClientAbsOrigin(iEntity, vecPos);

	if (vecPos[2] >= eSeqData.vecDest[2]-50.0) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet WallClimb_Airstrafe_Ledge(Bot mBot, Operation mOp, OpData eOpData, SeqData eSeqData, float fStartTime) {
	int iEntity = mBot.iEntity;
	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return OpRet_Handled;
	}

	mBot.iButtons = IN_FORWARD | IN_DUCK;
	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	float vecVel[3];
	Entity_GetAbsVelocity(iEntity, vecVel);

	float vecAngTangent[3];
	GetVectorAngles(vecVel, vecAngTangent);

	float vecPos[3];
	GetClientAbsOrigin(iEntity, vecPos);

	float vecAng[3];
	SubtractVectors(eSeqData.vecDest, vecPos, vecAng);
	GetVectorAngles(vecAng, vecAng);

	float fAngDisparity;
	GetAngDiff(vecAng[1], vecAngTangent[1], fAngDisparity);

	if (FloatAbs(fAngDisparity) > 5.0) {
		if (fAngDisparity > 0) {
			mBot.iButtons = IN_FORWARD | IN_DUCK | IN_MOVELEFT;
			mBot.SetLocalVelocity({400.0, -400.0, 0.0});
		} else {
			mBot.iButtons = IN_FORWARD | IN_DUCK | IN_MOVERIGHT;
			mBot.SetLocalVelocity({400.0, 400.0, 0.0});
		}
	}

	mBot.SetAimTo(vecAng);
	mBot.SetPID(PID_SLOW_LAZY);

	return OpRet_Continue;
}
