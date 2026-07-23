#define RANDOM_LOOK_INTERVAL	1.5

enum struct OpData_Idle_LookAttention {
	float fNextLookTime;
	ArrayList hProbDist;
	any aPadding[14];
}

enum struct ProbDist {
	float fProbabilty;
	float fCumulativeSum;
}

#define DISCRETE_PROBDIST_SIZE 32

OpRet Idle_LookAttention_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Idle_LookAttention eOpData) {
	eOpData.hProbDist = new ArrayList(sizeof(ProbDist), DISCRETE_PROBDIST_SIZE);

	ProbDist eProbDist;
	eProbDist.fProbability = 1.0 / DISCRETE_PROBDIST_SIZE;

	for (int i=0; i<DISCRETE_PROBDIST_SIZE; i++) {
		eProbDist.fCumulativeSum += eProbDist.fProbability;
		eOpData.hProbDist.SetArray(i, eProbDist);
	}
}

void Idle_LookAttention_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Idle_LookAttention eOpData) {
	delete eOpData.hProbDist;
}

OpRet Idle_LookAttention_PreRun(Bot mBot, Operation mOp, OpData_Idle_LookAttention eOpData) {
	float fTime = GetGameTime();
	if (fTime > eOpData.fNextLookTime) {
		eOpData.fNextLookTime = fTime + RANDOM_LOOK_INTERVAL;

		float vecAimAng[3];
		vecAimAng[0] = 45.0 - GetURandomFloat()*90;
		vecAimAng[1] = 180.0 - GetURandomFloat()*360;
		mBot.SetAimTo(vecAimAng);

		mBot.SetPID(PID_SLOW_LAZY);
	}

	return OpRet_Continue;
}
