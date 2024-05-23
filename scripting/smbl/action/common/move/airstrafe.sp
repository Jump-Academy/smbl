enum AirStrafe_Mode {
	AirStrafe_Mode_Destination,
	AirStrafe_Mode_Heading,
	AirStrafe_Mode_Follow
}

enum struct OpData_AirStrafe {
	AirStrafe_Mode iAirStrafeMode;
	float vecDest[3];
	float fHeadingAng;
	int iFollowEntRef;
	float fFollowDistance;
	float fFollowZOffset;
	bool bAirBrake;
	bool bFlyby;
	bool bDecelerate;
	float fProximity;
	float fRemainingAirTime;
	any aPadding[3];
}

enum struct SeqData_AirStrafe {
	float fNextDecelerationTime;
	any aPadding[15];
}

#define DEFAULT_LANDING_PROXIMITY		50.0
#define AIRBRAKE_SPEED					36.0

// Operation callbacks

OpRet AirStrafe_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_AirStrafe eOpData) {
	int iEntity = mBot.iEntity;
	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		return mOp._Abort("cannot start on ground");
	}

	float vecDest[3];

	if (hInitParams.JumpToKey("destination")) {
		hInitParams.GoBack();
		hInitParams.GetVector("destination", eOpData.vecDest);

		eOpData.iAirStrafeMode = AirStrafe_Mode_Destination;
		vecDest = eOpData.vecDest;
	} else if (hInitParams.JumpToKey("heading_angle")) {
		hInitParams.GoBack();
		eOpData.fHeadingAng = hInitParams.GetFloat("heading_angle");

		eOpData.iAirStrafeMode = AirStrafe_Mode_Heading;
	} else if (hInitParams.JumpToKey("follow")) {
		hInitParams.GoBack();

		int iFollowEntity = hInitParams.GetNum("follow");
		if (!IsValidEntity(iFollowEntity)) {
			return mOp._Abort("invalid follow entity");
		}

		eOpData.iAirStrafeMode = AirStrafe_Mode_Follow;
		eOpData.iFollowEntRef = EntIndexToEntRef(iFollowEntity);

		Entity_GetAbsOrigin(iFollowEntity, vecDest);

		eOpData.fFollowDistance = hInitParams.GetFloat("follow_distance", 0.0);
		eOpData.fFollowZOffset = hInitParams.GetFloat("follow_zoffset", 0.0);
	} else {
		return mOp._Abort("missing init parameter (destination, heading, or follow)");
	}

	eOpData.bAirBrake = eOpData.iAirStrafeMode != AirStrafe_Mode_Heading && hInitParams.GetNum("airbrake", false);
	eOpData.bFlyby = hInitParams.GetNum("flyby", false) != 0;

	if (eOpData.bFlyby && eOpData.bAirBrake) {
		return mOp._Abort("conflicting init parameters set: flyby, airbrake");
	}

	eOpData.bDecelerate = hInitParams.GetNum("decelerate", 0) != 0;
	eOpData.fProximity = hInitParams.GetFloat("proximity", DEFAULT_LANDING_PROXIMITY);

	if (eOpData.iAirStrafeMode != AirStrafe_Mode_Heading) {
		float vecPos[3];
		Entity_GetAbsOrigin(iEntity, vecPos);

		float vecVel[3];
		Entity_GetAbsVelocity(iEntity, vecVel);

		float fAirTime = GetAirTime(iEntity, vecVel[2], vecDest[2]-vecPos[2]);

		float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);
		float fDist2D = GetVectorDistance2D(vecPos, vecDest);
		float fTime2D = fDist2D / fVel2D;

		if (fAirTime <= 0.0 || fAirTime < fTime2D) {
			return mOp._Abort("destination not reachable");
		}
	}

 	SeqData_AirStrafe eSeqData;
 	eSeqData.fNextDecelerationTime = 0.0;

	Sequence eSeq;
	eSeq.fnRun = AirStrafe_StraightHeading;
	eSeq.iSeq = view_as<Seq>(0);
 	eSeq.SetData(eSeqData);
	FormatEx(eSeq.sIdentifier, sizeof(Sequence::sIdentifier), "Straight_Heading");
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

OpRet AirStrafe_Validate(Bot mBot, Operation mOp, ArrayList hSequences, OpData_AirStrafe eOpData, float fStartTime) {
	int iEntity = mBot.iEntity;
	if (GetEntityFlags(iEntity) & FL_ONGROUND) {
		if (eOpData.iAirStrafeMode == AirStrafe_Mode_Heading) {
			return OpRet_Handled;
		}

		float vecPos[3];
		Entity_GetAbsOrigin(iEntity, vecPos);

		float vecDest[3];

		if (eOpData.iAirStrafeMode == AirStrafe_Mode_Follow) {
			int iFollowEntity = EntRefToEntIndex(eOpData.iFollowEntRef);
			if (iFollowEntity == INVALID_ENT_REFERENCE) {
				return mOp._Abort("invalid follow entity");
			}

			Entity_GetAbsOrigin(iFollowEntity, vecDest);

			float vecVector[3];
			SubtractVectors(vecDest, vecPos, vecVector);
			vecVector[2] = 0.0; // Only consider 2D distance
			NormalizeVector(vecVector, vecVector);
			ScaleVector(vecVector, eOpData.fFollowDistance);

			SubtractVectors(vecDest, vecVector, vecDest);
		} else {
			vecDest = eOpData.vecDest;
		}

		if (GetVectorDistance2D(vecPos, vecDest) > eOpData.fProximity) {
			return mOp._Abort("landed without reaching destination");
		}

		return OpRet_Handled;
	}

	if (eOpData.iAirStrafeMode != AirStrafe_Mode_Heading) {
		float vecPos[3];
		Entity_GetAbsOrigin(iEntity, vecPos);

		float vecVel[3];
		Entity_GetAbsVelocity(iEntity, vecVel);

		float vecDest[3];

		if (eOpData.iAirStrafeMode == AirStrafe_Mode_Follow) {
			int iFollowEntity = EntRefToEntIndex(eOpData.iFollowEntRef);
			if (iFollowEntity == INVALID_ENT_REFERENCE) {
				return mOp._Abort("invalid follow entity");
			}

			Entity_GetAbsOrigin(iFollowEntity, vecDest);

			float vecVector[3];
			SubtractVectors(vecDest, vecPos, vecVector);
			vecVector[2] = 0.0; // Only consider 2D distance
			NormalizeVector(vecVector, vecVector);
			ScaleVector(vecVector, eOpData.fFollowDistance);

			SubtractVectors(vecDest, vecVector, vecDest);
		} else {
			vecDest = eOpData.vecDest;
		}

		float fAirTime = GetAirTime(iEntity, vecVel[2], vecDest[2]-vecPos[2]);

		if (!(eOpData.bAirBrake || eOpData.bDecelerate)) {
			float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);
			float fDist2D = GetVectorDistance2D(vecPos, vecDest);
			float fTime2D = fDist2D / fVel2D;

			if (fAirTime <= 0.0 || fAirTime < fTime2D) {
				return mOp._Abort("destination not reachable");
			}
		}

		eOpData.fRemainingAirTime = fAirTime;
	}

	return OpRet_Continue;
}

// Sequences

OpRet AirStrafe_StraightHeading(Bot mBot, Operation mOp, OpData_AirStrafe eOpData, SeqData_AirStrafe eSeqData, float fStartTime) {
	int iEntity = mBot.iEntity;

	int iButtons = IN_DUCK;
	float vecLocalVel[3];

	float vecVel[3];
	Entity_GetAbsVelocity(iEntity, vecVel);

	float vecAngTangent[3];
	GetVectorAngles(vecVel, vecAngTangent);

	float vecPos[3];
	Entity_GetAbsOrigin(iEntity, vecPos);

	float vecDest[3], vecAng[3];

	switch (eOpData.iAirStrafeMode) {
		case AirStrafe_Mode_Destination: {
			vecDest = eOpData.vecDest;

			float vecEyePos[3];
			GetClientEyePosition(iEntity, vecEyePos);

			SubtractVectors(vecDest, vecEyePos, vecAng);
			GetVectorAngles(vecAng, vecAng);
		}
		case AirStrafe_Mode_Heading: {
			vecAng[1] = eOpData.fHeadingAng;
		}
		case AirStrafe_Mode_Follow: {
			int iFollowEntity = EntRefToEntIndex(eOpData.iFollowEntRef);
			if (iFollowEntity == INVALID_ENT_REFERENCE) {
				return mOp._Abort("invalid follow entity");
			}

			Entity_GetAbsOrigin(iFollowEntity, vecDest);

			float vecEyePos[3];
			GetClientEyePosition(iEntity, vecEyePos);

			float vecFollowVel[3];
			Entity_GetAbsVelocity(iFollowEntity, vecFollowVel);

			float vecPredictShift[3];
			vecPredictShift = vecFollowVel;
			vecPredictShift[2] = 0.0; // 2D shifts only
			ScaleVector(vecPredictShift, eOpData.fRemainingAirTime);
			AddVectors(vecDest, vecPredictShift, vecDest);

			float vecAimVector[3];
			vecAimVector = vecDest;
			vecAimVector[2] += eOpData.fFollowZOffset;
			SubtractVectors(vecAimVector, vecEyePos, vecAimVector);
			GetVectorAngles(vecAimVector, vecAng);

			float vecVector[3];
			SubtractVectors(vecDest, vecPos, vecVector);
			vecVector[2] = 0.0; // Only consider 2D distance
			NormalizeVector(vecVector, vecVector);

			ScaleVector(vecVector, eOpData.fFollowDistance);
			SubtractVectors(vecDest, vecVector, vecDest);
		}
	}

	float fAngDisparity;
	GetAngDiff(vecAng[1], vecAngTangent[1], fAngDisparity);

	float fAbsAngDisparity = FloatAbs(fAngDisparity);

	if (fAbsAngDisparity >= 90.0) {
		return mOp._Abort("angle deviation is too large")
	}

	if (fAbsAngDisparity > 5.0) {
		if (fAngDisparity > 0) {
			iButtons |= IN_MOVELEFT;
			vecLocalVel[1] = -400.0;
		} else {
			iButtons |= IN_MOVERIGHT;
			vecLocalVel[1] = 400.0;
		}
	}

	float fDist2D = GetVectorDistance2D(vecPos, vecDest);

	if (fDist2D < eOpData.fProximity) {
		if (eOpData.bFlyby) {
			return OpRet_Handled;
		}

		if (eOpData.bAirBrake) {
			iButtons |= IN_BACK;
			vecLocalVel[0] = -400.0;

#if defined DEBUG
			DrawDebugMarker(vecDest, COLOR_RED, 0.1);
#endif
		}
	} else if (eOpData.bDecelerate && GetGameTime() >= eSeqData.fNextDecelerationTime) {
		float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);
		float fTime2D = fDist2D / fVel2D;

		if (eSeqData.fNextDecelerationTime) {
			iButtons |= IN_BACK;
			vecLocalVel[0] = -400.0;

#if defined DEBUG
			DrawDebugMarker(vecDest, COLOR_RED, 0.1);
#endif
		}

		if (fDist2D/(fVel2D-AIRBRAKE_SPEED) <= eOpData.fRemainingAirTime) {
			float fDecelerationInterval = 0.025*fTime2D;
			eSeqData.fNextDecelerationTime = GetGameTime() + fDecelerationInterval;

		} else {
			eSeqData.fNextDecelerationTime = POSITIVE_INFINITY;
		}
	}
#if defined DEBUG
	else
		DrawDebugMarker(vecDest, COLOR_GREEN, 0.1);
#endif

	mBot.SetAimTo(vecAng);
	mBot.SetPID(PID_SLOW_LAZY);

	mBot.SetLocalVelocity(vecLocalVel);
	mBot.iButtons = iButtons;

	return OpRet_Continue;
}

// Helpers

float GetAirTime(int iEntity, float fInitialZSpeed, float fZDistance) {
	float fEntityGravityRatio = GetEntityGravity(iEntity);
	if (fEntityGravityRatio == 0.0) {
		fEntityGravityRatio = 1.0;
	}

	float fGravity = -g_hCVGravity.FloatValue * fEntityGravityRatio;

	/*
	 * Kinematic equation
	 *
	 * dz = v0*t + (0.5*g)*t^2                  
	 * -> (0.5*g)*t^2 + v0*t - dz = 0
	 *       a           b      c
	 *      
	 * Quadratic formula
	 *
	 * t = (-b ± sqrt(b^2 - 4*a*c)) / (2*a)
	 * -> t = (-v0 ± sqrt(v0^2 - 4*(0.5*g)*(-dz))) / (2*(0.5*g))
	 * -> t = (-v0 ± sqrt(v0^2 + 2*g*dz)) / g
	 *
	 * t must be larger of the two solutions due to being on the far end of the parabolic arc
	 */
	float fDiscriminant = fInitialZSpeed*fInitialZSpeed + 2*fGravity*fZDistance;

	// Unreachable since destination is above parabola
	if (fDiscriminant < 0) {
		return 0.0;
	}

	float fSqrtDiscriminant = SquareRoot(fDiscriminant);

	float fAirTimeA = (-fInitialZSpeed + fSqrtDiscriminant) / fGravity;
	float fAirTimeB = (-fInitialZSpeed - fSqrtDiscriminant) / fGravity;

	return fAirTimeA >= fAirTimeB ? fAirTimeA : fAirTimeB;
}
