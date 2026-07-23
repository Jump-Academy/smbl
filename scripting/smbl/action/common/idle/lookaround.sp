#define RANDOM_LOOK_INTERVAL	2.5
#define TWO_PI	6.283185307179586476925286766559

enum struct OpData_Idle_LookAround {
	float fNextLookTime;
	float fLastYawAng;
	any aPadding[14];
}

OpRet Idle_LookAround_PreRun(Bot mBot, Operation mOp, OpData_Idle_LookAround eOpData) {
	float fTime = GetGameTime();
	if (fTime > eOpData.fNextLookTime) {
		eOpData.fNextLookTime = fTime + RANDOM_LOOK_INTERVAL;

		float vecAimAng[3];

		vecAimAng[0] = GetGaussianSample(0.0, 25.0);
		vecAimAng[1] = GetGaussianSample(eOpData.fLastYawAng, 90.0);

		ClipAngle(vecAimAng[0], -90.0, 90.0);
		NormalizeAngle(vecAimAng[1]);
		eOpData.fLastYawAng = vecAimAng[1];

		//vecAimAng[0] = 45.0 - GetGaussianSample()*90;
		//vecAimAng[1] = 180.0 - GetGaussianSample()*360;
		mBot.SetAimTo(vecAimAng);

		mBot.SetPID(PID_VSLOW_LAZY);
	}

	return OpRet_Continue;
}

// Helpers

// Box–Muller transform
// https://en.wikipedia.org/wiki/Box%E2%80%93Muller_transform
float GetGaussianSample(float fMean=0.0, float fStdDev=1.0) {
	float fRand1;
	do {
		fRand1 = GetURandomFloat();
	} while (fRand1 == 0);

	float fRand2 = GetURandomFloat();

	return fStdDev * SquareRoot(-2.0 * Logarithm(fRand1)) * Cosine(TWO_PI * fRand2) + fMean;
}
