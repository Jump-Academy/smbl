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
	bool bAirBrake;
	bool bFlyby;
	bool bDecelerate;
	float fProximity;
	float fRemainingAirTime;
	any aPadding[5];
}

enum struct SeqData_AirStrafe {
	float fNextDecelerationTime;
	any aPadding[15];
}

#define DEFAULT_PROXIMITY	50.0
#define AIRBRAKE_SPEED		36.0

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
	} else {
		return mOp._Abort("missing init parameter (destination, heading, or follow)");
	}

	eOpData.bAirBrake = eOpData.iAirStrafeMode != AirStrafe_Mode_Heading && hInitParams.GetNum("airbrake", false);
	eOpData.bFlyby = hInitParams.GetNum("flyby", false) != 0;

	if (eOpData.bFlyby && eOpData.bAirBrake) {
		return mOp._Abort("conflicting init parameters set: flyby, airbrake");
	}

	eOpData.bDecelerate = hInitParams.GetNum("decelerate", 0) != 0;
	eOpData.fProximity = hInitParams.GetFloat("proximity", DEFAULT_PROXIMITY);

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
		Entity_GetAbsOrigin(mBot.iEntity, vecPos);

		float vecDest[3];

		if (eOpData.iAirStrafeMode == AirStrafe_Mode_Follow) {
			int iFollowEntity = EntRefToEntIndex(eOpData.iFollowEntRef);
			if (iFollowEntity == INVALID_ENT_REFERENCE) {
				return mOp._Abort("invalid follow entity");
			}

			Entity_GetAbsOrigin(iFollowEntity, vecDest);
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
		} else {
			vecDest = eOpData.vecDest;
		}

		float fAirTime = GetAirTime(iEntity, vecVel[2], vecDest[2]-vecPos[2]);

		if (!(eOpData.bAirBrake || eOpData.bDecelerate)) {
			float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);
			float fDist2D = GetVectorDistance2D(vecPos, vecDest);
			float fTime2D = fDist2D / fVel2D;

			//PrintToServer("fTime2D: %.2f    fAirTime: %.2f", fTime2D, fAirTime);

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
			SubtractVectors(eOpData.vecDest, vecPos, vecAng);
			GetVectorAngles(vecAng, vecAng);

			vecDest = eOpData.vecDest;
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

			SubtractVectors(vecDest, vecPos, vecAng);
			GetVectorAngles(vecAng, vecAng);
		}
	}

	float fAngDisparity;
	GetAngDiff(vecAng[1], vecAngTangent[1], fAngDisparity);

	if (FloatAbs(fAngDisparity) > 5.0) {
		if (fAngDisparity > 0) {
			iButtons |= IN_MOVELEFT;
			vecLocalVel[1] = -400.0;
		} else {
			iButtons |= IN_MOVERIGHT;
			vecLocalVel[1] = 400.0;
		}
	}

// 	if (GetGameTime() - fStartTime < 0.3) {
// 		mBot.SetPID(PID_FAST_PREC);
// 		return OpRet_Continue;
// 	}

// 	float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);
// 	if (fVel2D < 50) {
// 		iButtons |= IN_FORWARD;
// 		vecLocalVel[0] = 400.0;
// 	}

	if (eOpData.bAirBrake && GetVectorDistance2D(vecPos, vecDest) < eOpData.fProximity) {
// 		PrintToServer("AIRBRAKE dist to destination: %.2f", GetVectorDistance2D(vecPos, vecDest));
		iButtons |= IN_BACK;
		vecLocalVel[0] = -400.0;
	} else if (eOpData.bFlyby && GetVectorDistance2D(vecPos, vecDest) < eOpData.fProximity) {
		return OpRet_Handled;
	} else {
		float fVel2D = SquareRoot(vecVel[0]*vecVel[0]+vecVel[1]*vecVel[1]);
		float fDist2D = GetVectorDistance2D(vecPos, vecDest);
		float fTime2D = fDist2D / fVel2D;
// 	 	PrintToServer("%.2f: fVel2D: %.2f\tfTime2D: %.2f\tfAirTime=%.2f\tfNextDecelTime: %.2f", GetGameTime(), fVel2D, fTime2D, eOpData.fRemainingAirTime, eSeqData.fNextDecelerationTime);

		if (eOpData.bDecelerate) {
		 	if (GetGameTime() >= eSeqData.fNextDecelerationTime) {
		 		if (eSeqData.fNextDecelerationTime > 0.0) {
			 		iButtons |= IN_BACK;
			 		vecLocalVel[0] = -400.0;
// 			 		PrintToServer("Decelerating");
		 		}

	// 	 		PrintToServer("  Post-AirBrake fTime2D predict: %.2f", fDist2D/(fVel2D-AIRBRAKE_SPEED));

				if (fDist2D/(fVel2D-AIRBRAKE_SPEED) <= eOpData.fRemainingAirTime) {
	// 				float fDecelerationInterval = 0.5*fTime2D/(fVel2D/AIRBRAKE_SPEED);
					float fDecelerationInterval = 0.1*fTime2D*fTime2D;
			 		eSeqData.fNextDecelerationTime = GetGameTime() + fDecelerationInterval;
	// 				eSeqData.fNextDecelerationTime = GetGameTime() + GetTickInterval();
	// 		 		PrintToServer("  Next decel at: %.2f", eSeqData.fNextDecelerationTime);
				} else {
					eSeqData.fNextDecelerationTime = POSITIVE_INFINITY;
				}
		 	}

		 	//else {
		 	//	iButtons &= ~IN_BACK;
		 	//}

		}
	}

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

	//PrintToServer("GetAirTime(fInitialZSpeed=%.2f, fZDistance=%.2f)", fInitialZSpeed, fZDistance)

	float fGravity = -g_hCVGravity.FloatValue * fEntityGravityRatio;

// 	PrintToServer("  fGravity= -%.2f * %.2f = %.2f", g_hCVGravity.FloatValue, fEntityGravityRatio, fGravity);

// 	PrintToServer("  v0^2 + 2*g*dz = %.2f + %.2f = %.2f", fInitialZSpeed*fInitialZSpeed, 2*fGravity*fZDistance, fInitialZSpeed*fInitialZSpeed + 2*fGravity*fZDistance);
// 	PrintToServer("  v0^2 - 4*0.5*g*-dz = %.2f - 4*0.5*%.2f*-%.2f = %.2f",
// 		fInitialZSpeed*fInitialZSpeed,
// 		fGravity, fZDistance,
// 		fInitialZSpeed*fInitialZSpeed - 4*0.5*fGravity*(-fZDistance));
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
// 	return (-fInitialZSpeed + SquareRoot(fInitialZSpeed*fInitialZSpeed + 2*fGravity*fZDistance)) / fGravity;
	float fDiscriminant = fInitialZSpeed*fInitialZSpeed + 2*fGravity*fZDistance;
	
	// Unreachable since destination is above parabola
	if (fDiscriminant < 0) {
		//PrintToServer("%.2f: !! destination not reachable !!", GetGameTime());
		return 0.0;
	}

	float fSqrtDiscriminant = SquareRoot(fDiscriminant);

	float fAirTimeA = (-fInitialZSpeed + fSqrtDiscriminant) / fGravity;
	float fAirTimeB = (-fInitialZSpeed - fSqrtDiscriminant) / fGravity;

	//PrintToServer("  %.2f: fAirTime=%.2f", GetGameTime(), fAirTimeA > fAirTimeB ? fAirTimeA : fAirTimeB);
	return fAirTimeA >= fAirTimeB ? fAirTimeA : fAirTimeB;
}
