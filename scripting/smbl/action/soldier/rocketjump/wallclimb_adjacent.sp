enum struct OpData_WallClimbAdjacent {
	float vecDest[3];
	float vecWallAng[3];
	float vecWallNormalYaw;
	float vecWallNormal[3];
	any aPadding[6];
}

enum struct SeqData_WallClimbAdjacent {
	float vecDest[3];
	any aPadding[13];
}

// Operation callbacks

OpRet WallClimbAdjacent_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_WallClimbAdjacent eOpData) {
	int iEntity = mBot.iEntity;

	if (!(1 <= iEntity <= MaxClients) || TF2_GetPlayerClass(iEntity) != TFClass_Soldier) {
		return mOp._Abort("Unsupported TFClassType");
	}

	float vecStart[3];
	float vecDest[3];

	NavNode mStartNode = view_as<NavNode>(hInitParams.GetNum("start_node", view_as<int>(NULL_NAV_NODE)));
	NavNode mEndNode = view_as<NavNode>(hInitParams.GetNum("end_node", view_as<int>(NULL_NAV_NODE)));

	if (!mStartNode || !mEndNode) {
		NavMesh mNavMesh = SMBL_GetNavMesh("Ground");
		if (!mNavMesh) {
			return mOp._Abort("cannot initialize walk: Missing ground navigation mesh");
		}

		ArrayList hNodes = mNavMesh.GetNodes();
		PrintToServer("Looking up NavMesh with %d nodes", hNodes.Length);
		delete hNodes;

		PrintToServer("WallClimbAdjacent Start: %.1f, %.1f, %.1f", vecStart[0], vecStart[1], vecStart[2]);

		if (mStartNode) {
			mStartNode.GetOrigin(vecStart);
		} else {
			Entity_GetAbsOrigin(iEntity, vecStart);

			mStartNode = mNavMesh.GetNearestNodeInRange(vecStart, NODE_PROXIMITY, true);

			if (!mStartNode) {
				return mOp._Abort("bot is not within mesh");
			}
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

	// Find adjacent attached walls

	float vecStartOrigin[3];
	mStartNode.GetOrigin(vecStartOrigin);

	float vecDirection[3];
	SubtractVectors(vecDest, vecStartOrigin, vecDirection);

	float vecNearestWall[3];
	int iEdge = -1;
	int iAttachment;

	float vecDirectionWall[3];
	vecDirectionWall = vecDirection;
	ScaleVector(vecDirectionWall, -1.0);

	mStartNode.GetNearestEdgeProjection(vecStart, vecNearestWall, iEdge, iAttachment, FL_ATTACH_WALL, vecDirectionWall);

	if (iEdge == -1) {
		return mOp._Abort("no compatible adjacent walls found at start node");
	}

#if defined DEBUG
	DrawDebugLine(vecStart, vecNearestWall, COLOR_RED, 3.0);
#endif

	// Determine adjacent wall height

	NavNode mAttachedNode;
	int iAttachedNodeEdge;
	mStartNode.GetAttachment(iEdge, iAttachment, mAttachedNode, iAttachedNodeEdge);

	float vecWallTopEdge[3];
	float fWallMaxHeight;
	if (mAttachedNode) {
		mAttachedNode.GetEdgeCenter(iAttachedNodeEdge, vecWallTopEdge);
		fWallMaxHeight = vecWallTopEdge[2] - vecStartOrigin[2];
	} else {
		float vecTracePos[3], vecTraceAng[3];

		vecTracePos = vecNearestWall;
// 		SubtractVectors(vecStartOrigin, vecNearestWall, vecTracePos);
// 		NormalizeVector(vecTracePos, vecTracePos);
// 		vecTracePos[0] *= 50.0;
// 		vecTracePos[1] *= 50.0;
// 		vecTracePos[2] = 50.0;
// 		AddVectors(vecNearestWall, vecTracePos, vecTracePos);

// 		vecTracePos = vecStartOrigin;
		float vecEndPos[3];

		float fDistCeiling = TR_GetRayDistance(vecTracePos, {-90.0, 0.0, 0.0}, vecEndPos);
		PrintToServer("Ceiling is %.1f", fDistCeiling);
		SubtractVectors(vecNearestWall, vecStartOrigin, vecTraceAng)
		GetVectorAngles(vecTraceAng, vecTraceAng);
		vecTracePos = vecNearestWall;

#if defined DEBUG
		DrawDebugLine(vecNearestWall, vecEndPos, COLOR_RED, 3.0);
#endif

		for (float fZ=100.0; fZ<fDistCeiling; fZ += 50.0) {
			vecTracePos[2] = vecNearestWall[2] + fZ;

			float fDist = TR_GetRayDistance(vecTracePos, vecTraceAng, vecEndPos);

#if defined DEBUG
			DrawDebugLine(vecTracePos, vecEndPos, COLOR_YELLOW, 3.0);
#endif

			PrintToServer("fZ: %.1f, fDist=%.1f", fZ, fDist);

			if (fDist > 10.0) {
				fWallMaxHeight = fZ - 50.0;
				break;
			}
		}
	}

	PrintToServer("Wall height is %.1f", fWallMaxHeight);

// 	mStartNode.GetEdgeCenter(iMinEdge, vecEdgeCenter);

	float fDist2D = GetVectorDistance2D(vecNearestWall, vecDest);
	if (fDist2D > 1200.0) {
		PrintToServer("End node too far away from start node.");
// 		return Abort(mOp, "End node too far away from start node.");
	}

// 	SubtractVectors(vecDest, vecNearestWall, vecDirection);
// 	NormalizeVector(vecDirection, vecDirection);

// 	ScaleVector(vecDirectionWall, -1.0);
// 	NormalizeVector(vecDirectionWall, vecDirectionWall);

// 	float fVDP = GetVectorDotProduct(vecDirection, vecDirectionWall);
// 	PrintToServer("VDP: %.2f", fVDP);
// 	float fAngDiff = RadToDeg(ArcCosine(fVDP));
// 	return Abort(mOp, "Angle from wall is too steep (%.1f > 50.0).", fAngDiff);
// 	if (fAngDiff > 50.0) {
// 		return Abort(mOp, "Angle from wall is too steep (%.1f > 50.0).", fAngDiff);
// 	}

// 	DrawDebugLine(vecMinNearestWall, vecDest, COLOR_BLUE, 3.0);


// 	int iEdge, iAttachedNodeEdge;
// 	int iAttachmentFlags;
// 	if (!mStartNode.FindAttachedNode(mEndNode, iEdge, _, iAttachmentFlags, iAttachedNodeEdge) || iAttachmentFlags & FL_ATTACH_WALL == 0) {
// 		return Abort(mOp, "End node is not attached to start node");
// 	}



	eOpData.vecDest = vecDest;

	SeqData_WallClimbAdjacent eSeqData;
	eSeqData.vecDest = vecNearestWall;

	Sequence eSeq;
	eSeq.fnRun = WallClimbAdjacent_Walk;
	eSeq.iSeq = view_as<Seq>(0);
	eSeq.SetData(eSeqData);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Walk [%.1f %.1f %.1f]", eSeqData.vecDest[0], eSeqData.vecDest[1], eSeqData.vecDest[2]);

	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimbAdjacent_Aim_Align_Wall;
	eSeq.iSeq = view_as<Seq>(1);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Aim_Align_Wall");
	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimbAdjacent_Shoot_Ground;
	eSeq.iSeq = view_as<Seq>(2);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Shoot_Ground");
	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimbAdjacent_Shoot_Wall;
	eSeq.iSeq = view_as<Seq>(3);
	eSeqData.vecDest[2] = vecDest[2] - 100.0;
	eSeq.SetData(eSeqData);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Shoot_Wall_Climb");
	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimbAdjacent_Shoot_Wall_Away;
	eSeq.iSeq = view_as<Seq>(4);
	eSeqData.vecDest[2] = vecDest[2];
	eSeq.SetData(eSeqData);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Shoot_Wall_Away");
	hSequences.PushArray(eSeq);

	eSeq.fnRun = WallClimbAdjacent_Airstrafe;
	eSeq.iSeq = view_as<Seq>(5);
	eSeqData.vecDest = vecDest;
	eSeq.SetData(eSeqData);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Airstrafe");
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

void WallClimbAdjacent_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_WallClimbAdjacent eOpData) {
	PrintToServer("WallClimbAdjacent Cleanup");
}

// Sequences

OpRet WallClimbAdjacent_Walk(Bot mBot, Operation mOp, OpData_WallClimbAdjacent eOpData, SeqData_WallClimbAdjacent eSeqData, float fStartTime) {
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

OpRet WallClimbAdjacent_Aim_Align_Wall(Bot mBot, Operation mOp, OpData_WallClimbAdjacent eOpData, SeqData_WallClimbAdjacent eSeqData, float fStartTime) {
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
	eOpData.vecWallNormal = vecAng;
	GetVectorAngles(vecAng, vecAng);
	eOpData.vecWallNormalYaw = vecAng[1];

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

OpRet WallClimbAdjacent_Shoot_Ground(Bot mBot, Operation mOp, OpData_WallClimbAdjacent eOpData, SeqData_WallClimbAdjacent eSeqData, float fStartTime) {
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

// 	PrintToServer("WallClimbAdjacent_Shoot_Ground vecAimAng=[%.1f %.1f %.1f]", eSeqData.vecWallAng[0], eSeqData.vecWallAng[1], eSeqData.vecWallAng[2]);

// 	eSeqData.fGroundShotTime = GetGameTime();

	return OpRet_Handled;
}

OpRet WallClimbAdjacent_Shoot_Wall(Bot mBot, Operation mOp, OpData_WallClimbAdjacent eOpData, SeqData_WallClimbAdjacent eSeqData, float fStartTime) {
// 	PrintToServer("WallClimbAdjacent_Shoot_Wall vecAimAng=[%.1f %.1f %.1f]", eSeqData.vecWallAng[0], eSeqData.vecWallAng[1], eSeqData.vecWallAng[2]);
// 	Abort(mOp, "Pause");
// 	return OpRet_Abort;

	mBot.iButtons = IN_FORWARD | IN_DUCK | IN_ATTACK;
	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	int iEntity = mBot.iEntity;
	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return mOp._Abort("touched ground early");
	}

	float vecAimAng[3];
	mBot.GetAimTo(vecAimAng);

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
// 	if (vecPos[2] >= eSeqData.vecDest[2]) {
// 		vecAimAng[0] = 70.0;
// 		vecAimAng[1] += 15.0;
// 		mBot.SetAimTo(vecAimAng);
		return OpRet_Handled;
	}

	return OpRet_Continue;
}

OpRet WallClimbAdjacent_Shoot_Wall_Away(Bot mBot, Operation mOp, OpData_WallClimbAdjacent eOpData, SeqData_WallClimbAdjacent eSeqData, float fStartTime) {
// 	PrintToServer("WallClimbAdjacent_Shoot_Wall vecAimAng=[%.1f %.1f %.1f]", eSeqData.vecWallAng[0], eSeqData.vecWallAng[1], eSeqData.vecWallAng[2]);
// 	Abort(mOp, "Pause");
// 	return OpRet_Abort;
	int iEntity = mBot.iEntity;
	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return mOp._Abort("touched ground early");
	}

	int iWeapon = GetPlayerWeaponSlot(iEntity, TFWeaponSlot_Primary);

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	if (!fStartTime) {
		float vecVector[3];
		SubtractVectors(eOpData.vecDest, vecPos, vecVector);
		float fDistance2D = SquareRoot(vecVector[0]*vecVector[0] + vecVector[1]*vecVector[1]);
		NormalizeVector(vecVector, vecVector);

#if defined DEBUG
		DrawDebugLine(vecPos, eOpData.vecDest, COLOR_RED, 3.0);
#endif

		float vecVectorAng[3];
		GetVectorAngles(vecVector, vecVectorAng);


		float vecCrossProduct[3];
		GetVectorCrossProduct(vecVector, eOpData.vecWallNormal, vecCrossProduct);

		int iDirection = vecCrossProduct[2] > 0 ? 1 : -1;
		float fAngDiff = RadToDeg(ArcCosine(GetVectorDotProduct(eOpData.vecWallNormal, vecVector)) * iDirection);

// 		float fYawVector = eOpData.vecWallAng[1]-vecVectorAng[1];
// 		NormalizeAngle(fYawVector);
		const float fA = 0.00344;
		const float fB = 0.89003892;
		const float fC = -29.13201354;
		/*
			Solve for fAimYaw:

			fAngDiff =  fA*fAimYaw^2 +  fB*fAimYaw + fC
			-> fA*fAimYaw^2 +  fB*fAimYaw * fAimYaw - fAngDiff + fC = 0
			-> fAimYaw = (-fB + Sqrt(fB^2 - 4*fA*(fAngDiff+fC))) / (2*fA)
		*/
		PrintToServer("vecWallAng=%.2f, vecVectorAng=%.2f, fAngDiff=%.2f", eOpData.vecWallNormalYaw, vecVectorAng[1], fAngDiff);
		float fAimYawB = (-fB - SquareRoot(fB*fB - 4*fA*(fAngDiff+fC))) / (2*fA);
		float fAimYaw = (-fB + SquareRoot(fB*fB - 4*fA*(fAngDiff+fC) )) / (2*fA);
		PrintToServer("fAimYawB=%.2f or %.2f **", fAimYawB, fAimYaw);


		float vecVel[3];
		Entity_GetAbsVelocity(iEntity, vecVel);

		float fGravityRatio = GetEntityGravity(iEntity);
		if (fGravityRatio == 0.0) {
			fGravityRatio = 1.0;
		}

// 		float fGravity = -g_hCVGravity.FloatValue * fGravityRatio * GetTickInterval() * GetTickInterval();
// 		float fGravity = -g_hCVGravity.FloatValue * fGravityRatio * GetTickInterval();
		float fGravity = -g_hCVGravity.FloatValue * fGravityRatio;

		float fMinAimPitch;
		float fMinDist = POSITIVE_INFINITY;
		float fMinPosZ;

// 		float fLastDist  = POSITIVE_INFINITY;

// 		float fAimPitchLB = -75.0;
// 		float fAimPitchRB = 75.0;

		for (float fAimPitch=-75.0; fAimPitch<=75.0; fAimPitch+=2.0) {
// 		while (fAimPitchLB < fAimPitchRB && (fAimPitchRB-fAimPitchLB) > 1.0) {

// 			float fAimPitch = 0.5*(fAimPitchLB+fAimPitchRB);

// 			PrintToServer("Bounds: [ %.1f  <=  %.1f  <= %.1f ]", fAimPitchLB, fAimPitch, fAimPitchRB);

			// coef: [5.04502208  0.58830107 -0.08074415  0.01476509 -0.02462284 -0.00062996  0.00009546 -0.00034251  0.00005302]
			// intercept: 663.9569786386485
			float fSpeedXY = \
				 5.04502208 * fAimPitch \
				+0.58830107 * fAimYaw \
				-0.08074415 * fAimPitch * fAimPitch \
				+0.01476509 * fAimPitch * fAimYaw \
				-0.02462284 * fAimYaw   * fAimYaw \
				-0.00062996 * fAimPitch * fAimPitch * fAimPitch \
	  			+0.00009546 * fAimPitch * fAimPitch * fAimYaw \
	  			-0.00034251 * fAimPitch * fAimYaw   * fAimYaw \
	  			+0.00005302 * fAimYaw   * fAimYaw   * fAimYaw \
	  			+663.9569786386485;

  			float fTime = fDistance2D/(fSpeedXY);
//   			float fTime = fDistance2D/(fSpeedXY*GetTickInterval());
//   			if (fTime < 0.0) {
//   				continue;
//   			}

			// coef: [ 9.43899368 -2.28579271  0.0637217   0.00729635  0.02617375 -0.00047485  0.00017915 -0.00013754  0.00026552]
			// intercept: -273.1905268641352
			float fSpeedZ = \
				9.43899368 * fAimPitch \
				-2.28579271 * fAimYaw \
				+0.0637217 * fAimPitch * fAimPitch \
				+0.00729635 * fAimPitch * fAimYaw \
				+0.02617375 * fAimYaw   * fAimYaw \
				-0.00047485 * fAimPitch * fAimPitch * fAimPitch \
	  			+0.00017915 * fAimPitch * fAimPitch * fAimYaw \
	  			-0.00013754 * fAimPitch * fAimYaw   * fAimYaw \
	  			+0.00026552 * fAimYaw   * fAimYaw   * fAimYaw \
	  			-273.1905268641352;

// 				float fPosZ = vecPos[2] + (vecVel[2]*GetTickInterval()+fSpeedZ)*fTime + 0.5*fGravity*fTime*fTime;
			PrintToServer("vecVel[2]=%.1f, fSpeedZ=%.1f, sum=%.1f", vecVel[2], fSpeedZ, vecVel[2]+fSpeedZ);
			float fPosZ = vecPos[2] + 10.0 + (0.7*vecVel[2]+fSpeedZ)*fTime + 0.5*fGravity*fTime*fTime;
//   			float fPosZ = vecPos[2] + fSpeedZ*fTime + 0.5*fGravity*fTime*fTime;

  			float fDist = FloatAbs(fPosZ-eOpData.vecDest[2]);
  			PrintToServer("Iter: fSpeedXY=%.1f, fAimPitch=%.1f, fTime=%.1f, fDist=%.1f", fSpeedXY, fAimPitch, fTime, fDist);

  			float vecPosLanding[3];
			vecPosLanding = eOpData.vecDest;
			vecPosLanding[2] = fPosZ;

  			if (fDist < fMinDist && !TR_CheckRayCollision(vecPos, vecPosLanding)) {
				fMinDist = fDist;
				fMinAimPitch = fAimPitch;
				fMinPosZ = fPosZ;
  			}

//   			if (fDist < fLastDist) {
// 				fAimPitchLB = fAimPitch;
// 			} else {
//   				fAimPitchRB = fAimPitch;
// 			}

// 			fLastDist = fDist;
		}

		if (fMinDist == POSITIVE_INFINITY) {
			return mOp._Abort("destination is not reachable by current wall jump");
		}

		float vecPosLanding[3];
		vecPosLanding = eOpData.vecDest;
		vecPosLanding[2] = fMinPosZ;
#if defined DEBUG
		DrawDebugLine(vecPos, vecPosLanding, COLOR_GREEN, 3.0);
#endif

		PrintToServer("fAimPitch=%.1f, fMinDist=%.1f", fMinAimPitch, fMinDist);

		float vecAimAng[3];
		vecAimAng[0] = fMinAimPitch;
// 		vecAimAng[0] = 50.0;
// 		vecAimAng[1] = eOpData.vecWallAng[1] + fAimYaw*iDirection;
		vecAimAng[1] = eOpData.vecWallAng[1] + fAimYaw;
		NormalizeAngle(vecAimAng[1]);
		mBot.SetAimTo(vecAimAng);

		eSeqData.aPadding[0] = GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack");
	}


	float vecAimAng[3];
	mBot.GetAimTo(vecAimAng);

	float fYawError;
	mBot.GetAimError(_, fYawError);

	mBot.iButtons = IN_DUCK;

	if (FloatAbs(fYawError) > 1.0) {
		return OpRet_Continue;
	}

// 	vecAimAng[0] = 60.0;
// 	vecAimAng[1] -= 25.0;
	mBot.SetAimTo(vecAimAng);


	mBot.SetPID(PID_FAST_PREC);

	mBot.iButtons = IN_DUCK | IN_ATTACK;
	mBot.SetLocalVelocity({0.0, 0.0, 0.0});

	float fNextAttackTime = GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack");
	if (fNextAttackTime > eSeqData.aPadding[0]) {
		return OpRet_Handled;
	}

	return OpRet_Continue;
}


OpRet WallClimbAdjacent_Airstrafe(Bot mBot, Operation mOp, OpData_WallClimbAdjacent eOpData, SeqData_WallClimbAdjacent eSeqData, float fStartTime) {
	int iEntity = mBot.iEntity;
	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return OpRet_Handled;
	}


// 	mBot.iButtons = IN_FORWARD | IN_DUCK;
// 	mBot.SetLocalVelocity({400.0, 0.0, 0.0});

	mBot.iButtons = IN_DUCK;
	mBot.SetLocalVelocity({0.0, 0.0, 0.0});

	float vecVel[3];
	Entity_GetAbsVelocity(iEntity, vecVel);

	float vecAngTangent[3];
	GetVectorAngles(vecVel, vecAngTangent);

	float vecPos[3];
	GetClientAbsOrigin(iEntity, vecPos);

	float vecAng[3];
	SubtractVectors(eSeqData.vecDest, vecPos, vecAng);
	GetVectorAngles(vecAng, vecAng);

	mBot.SetAimTo(vecAng);

	if (GetGameTime() - fStartTime < 0.3) {
		mBot.SetPID(PID_FAST_PREC);
		return OpRet_Continue;
	}

	if (GetVectorDistance2D(vecPos, eOpData.vecDest) < 100.0) {
		mBot.iButtons = IN_DUCK | IN_BACK;
		mBot.SetLocalVelocity({-400.0, 0.0, 0.0});
		return OpRet_Continue;
	}

	mBot.SetPID(PID_SLOW_LAZY);

	float fAngDisparity;
	GetAngDiff(vecAng[1], vecAngTangent[1], fAngDisparity);

	if (FloatAbs(fAngDisparity) > 5.0) {
		if (fAngDisparity > 0) {
			mBot.iButtons = IN_DUCK | IN_MOVELEFT;
			mBot.SetLocalVelocity({0.0, -400.0, 0.0});
		} else {
			mBot.iButtons = IN_DUCK | IN_MOVERIGHT;
			mBot.SetLocalVelocity({0.0, 400.0, 0.0});
		}
	}

	return OpRet_Continue;
}

// Helpers

stock float GetVectorDistance2D(const float vecA[3], const float vecB[3]) {
	float fDelta0 = vecB[0] - vecA[0];
	float fDelta1 = vecB[1] - vecA[1];

	return SquareRoot(fDelta0*fDelta0 + fDelta1*fDelta1);
}

float TR_GetRayDistance(float vecPos[3], float vecAng[3], float vecEndPos[3]=NULL_VECTOR) {
	TR_TraceRayFilter(vecPos, vecAng, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
	if (!TR_DidHit()) {
		return POSITIVE_INFINITY;
	}

	TR_GetEndPosition(vecEndPos);

	return GetVectorDistance(vecPos, vecEndPos);
}

bool TR_CheckRayCollision(float vecPos[3], float vecPosEnd[3]) {
	TR_TraceRayFilter(vecPos, vecPosEnd, MASK_SHOT_HULL, RayType_EndPoint, TraceEntityFilter_Environment);
	if (!TR_DidHit()) {
		return false;
	}

	TR_GetEndPosition(vecPosEnd);

	return true;
}
