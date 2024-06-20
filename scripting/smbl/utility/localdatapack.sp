void SetupLocalDataPackNatives() {
	CreateNative("LocalDataPack.WriteCell",			Native_LocalDataPack_WriteCell);
	CreateNative("LocalDataPack.WriteFloat",		Native_LocalDataPack_WriteFloat);
	CreateNative("LocalDataPack.WriteString",		Native_LocalDataPack_WriteString);
// 	CreateNative("LocalDataPack.WriteFunction",		Native_LocalDataPack_WriteFunction);
	CreateNative("LocalDataPack.WriteCellArray",	Native_LocalDataPack_WriteCellArray);
	CreateNative("LocalDataPack.WriteFloatArray",	Native_LocalDataPack_WriteFloatArray);

	CreateNative("LocalDataPack.ReadCell",			Native_LocalDataPack_ReadCell);
	CreateNative("LocalDataPack.ReadFloat",			Native_LocalDataPack_ReadFloat);
	CreateNative("LocalDataPack.ReadString",		Native_LocalDataPack_ReadString);
// 	CreateNative("LocalDataPack.ReadFunction",		Native_LocalDataPack_ReadFunction);
	CreateNative("LocalDataPack.ReadCellArray",		Native_LocalDataPack_ReadCellArray);
	CreateNative("LocalDataPack.ReadFloatArray",	Native_LocalDataPack_ReadFloatArray);

	CreateNative("LocalDataPack.Reset",				Native_LocalDataPack_Reset);
	CreateNative("LocalDataPack.IsReadable",		Native_LocalDataPack_IsReadable);

	CreateNative("LocalDataPack.Clone",				Native_LocalDataPack_Clone);

	CreateNative("LocalDataPack.Position.get",		Native_LocalDataPack_GetPosition);
	CreateNative("LocalDataPack.Position.set",		Native_LocalDataPack_SetPosition);

// 	// Static

	CreateNative("LocalDataPack.Instance",			Native_LocalDataPack_Instance);
	CreateNative("LocalDataPack.Destroy",			Native_LocalDataPack_Destroy);
}

public any Native_LocalDataPack_WriteCell(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	any aCell = GetNativeCell(2);
	bool bInsert = GetNativeCell(3);

	hDataPack.WriteCell(aCell, bInsert);

	return 0;
}

public any Native_LocalDataPack_WriteFloat(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	float fVal = GetNativeCell(2);
	bool bInsert = GetNativeCell(3);

	hDataPack.WriteFloat(fVal, bInsert);
	return 0;
}

public any Native_LocalDataPack_WriteString(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);

	int iStringLength;
	GetNativeStringLength(2, iStringLength);

	char[] sString = new char[iStringLength];
	GetNativeString(2, sString, iStringLength);

	bool bInsert = GetNativeCell(3);

	hDataPack.WriteString(sString, bInsert);

	return 0;
}

/*
// Unsupported since there is no read equivalent (see below)
public any Native_LocalDataPack_WriteFunction(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	Function fnPtr = GetNativeFunction(2);
	bool bInsert = GetNativeCell(3);

	hDataPack.WriteFunction(fnPtr, bInsert);

	return 0;
}
*/

public any Native_LocalDataPack_WriteCellArray(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	int iCount = GetNativeCell(3);

	any[] aArray = new any[iCount];
	GetNativeArray(2, aArray, iCount);

	bool bInsert = GetNativeCell(3);

	hDataPack.WriteCellArray(aArray, iCount, bInsert);

	return 0;
}

public any Native_LocalDataPack_WriteFloatArray(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	int iCount = GetNativeCell(3);

	float[] fArray = new float[iCount];
	GetNativeArray(2, fArray, iCount);

	bool bInsert = GetNativeCell(3);

	hDataPack.WriteFloatArray(fArray, iCount, bInsert);

	return 0;
}

public any Native_LocalDataPack_ReadCell(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	return hDataPack.ReadCell();
}

public any Native_LocalDataPack_ReadFloat(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	return hDataPack.ReadFloat();
}

public any Native_LocalDataPack_ReadString(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);

	int iMaxLen = GetNativeCell(3);

	char[] sString = new char[iMaxLen];
	hDataPack.ReadString(sString, iMaxLen);

	SetNativeString(2, sString, iMaxLen);

	return 0;
}

/*
// Unsupported since there is no way to pass or return functions out from natives anymore
public any Native_LocalDataPack_ReadFunction(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	return hDataPack.ReadFunction();
}
*/

public any Native_LocalDataPack_ReadCellArray(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	int iCount = GetNativeCell(3);

	any[] aArray = new any[iCount];
	hDataPack.ReadCellArray(aArray, iCount);
	SetNativeArray(2, aArray, iCount);

	return 0;
}

public any Native_LocalDataPack_ReadFloatArray(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	int iCount = GetNativeCell(3);

	float[] fArray = new float[iCount];
	hDataPack.ReadFloatArray(fArray, iCount);
	SetNativeArray(2, fArray, iCount);

	return 0;
}

public any Native_LocalDataPack_Reset(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	bool bClear = GetNativeCell(2);

	hDataPack.Reset();

	Handle hCleanupPlugin = hDataPack.ReadCell();
	Function fnCleanup = hDataPack.ReadFunction();

	if (bClear) {
		hDataPack.Reset(true);
		hDataPack.WriteCell(hCleanupPlugin);
		hDataPack.WriteFunction(fnCleanup);
	}

	return 0;
}

public any Native_LocalDataPack_IsReadable(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	int iUnused = GetNativeCell(2);

	return hDataPack.IsReadable(iUnused);
}

public any Native_LocalDataPack_Clone(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);

	if (hDataPack) {
		LocalDataPack hCloneDataPack = view_as<LocalDataPack>(CloneHandle(hDataPack));
		hCloneDataPack.Reset(); // Move DataPackPos past cleanup plugin and function

		return hCloneDataPack;
	}

	return NULL_LOCAL_DATAPACK;
}

public any Native_LocalDataPack_GetPosition(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);

	return hDataPack.Position;
}

public any Native_LocalDataPack_SetPosition(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCell(1);
	DataPackPos iPosition = GetNativeCell(2);

	hDataPack.Reset();
	hDataPack.ReadCell();
	hDataPack.ReadFunction();

	if (iPosition < hDataPack.Position) {
		ThrowError("Inaccessible position");
	}

	hDataPack.Position = iPosition;

	return 0;
}

public any Native_LocalDataPack_Instance(Handle hPlugin, int iArgC) {
	Function fnCleanupFunc = GetNativeFunction(1);
	Handle hCleanupPlugin = GetNativeCell(2);

	DataPack hDataPack = new DataPack();

	if (fnCleanupFunc == INVALID_FUNCTION) {
		hDataPack.WriteCell(0); // null
		hDataPack.WriteFunction(INVALID_FUNCTION);
	} else {
		hDataPack.WriteCell(hCleanupPlugin ? hCleanupPlugin : hPlugin);
		hDataPack.WriteFunction(fnCleanupFunc);
	}

	return hDataPack;
}

public any Native_LocalDataPack_Destroy(Handle hPlugin, int iArgC) {
	DataPack hDataPack = GetNativeCellRef(1);
	if (!hDataPack) {
		return 0;
	}

	hDataPack.Reset();

	Handle hCleanupPlugin = hDataPack.ReadCell();
	Function fnCleanup = hDataPack.ReadFunction();

	if (fnCleanup != INVALID_FUNCTION) {
		Call_StartFunction(hCleanupPlugin, fnCleanup);
		Call_PushCell(hDataPack);
		Call_Finish();
	}

	delete hDataPack;
	SetNativeCellRef(1, NULL_LOCAL_DATAPACK);

	return 0;
}
