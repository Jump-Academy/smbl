/**
 * Wrappers for SourceMod's built-in DataPack to work around its quirky
 * cross-plugin handle passing ownership and closing restrictions
 *
 * See SourceMod API's datapack.inc for documentation for most of these functions
 *
 * ReadFunction and WriteFunction are unsupported since there is no way to pass or return functions
 * out from natives anymore, even though they can still be passed in.
 */
methodmap LocalDataPack {
	public native void WriteCell(any aCell, bool bInsert=false);
	public native void WriteFloat(float fVal, bool iInsert=false);
	public native void WriteString(const char[] sStr, bool bInsert=false);
// 	public native void WriteFunction(Function fnPtr, bool bInsert=false); // Unsupported
	public native void WriteCellArray(const any[] aArray, int iCount, bool bInsert=false);
	public native void WriteFloatArray(const float[] fArray, int iCount, bool bInsert=false);

	public native any ReadCell();
	public native float ReadFloat();
	public native void ReadString(char[] sBuffer, int iMaxLen);
// 	public native Function ReadFunction(); // Unsupported
	public native void ReadCellArray(any[] aBuffer, int iCount);
	public native void ReadFloatArray(float[] fBuffer, int iCount);

	public native void Reset(bool bClear=false);

	public native bool IsReadable(int iUnused=0);

	public native LocalDataPack Clone();

	property DataPackPos Position {
		public native get();
		public native set(DataPackPos iPos);
	}

	public static native LocalDataPack Instance(Function fnLocalDataPackCleanup=INVALID_FUNCTION, Handle hCleanupPlugin=null);
	public static native void Destroy(LocalDataPack &mLocalDataPack);
}

#define NULL_LOCAL_DATAPACK view_as<LocalDataPack>(0)

typedef LocalDataPackCleanupFunc = function void (LocalDataPack mLocalDataPack);
