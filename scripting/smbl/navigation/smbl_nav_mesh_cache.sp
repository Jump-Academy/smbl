#define NAV_CACHE_PATH	"data/smbl/nav/.cache"
#define MAX_FRAME_TIME	4.0

enum struct NavCacheable {
	Handle hCachePlugin;
	Function fnNavCacheableFunc;
	char sBucketName[256];
}

enum struct NavCache {
	KeyValues hKVData;
	StringMap hBuckets;
	int iBucketListKVID;
}

enum struct NavCacheBucket {
	int iBucketKVID;
	StringMap hNodeKVIDs;
}

enum struct NavCacheNodeKVID {
	int iNodeA;
	int iNodeB;
}

bool g_bCacheReady;

static ArrayList m_hNavCacheables;

Operation m_mCacheQueueOp;

GlobalForward g_hCacheForward;

// Natives

void SetupCacheNatives() {
	CreateNative("SMBL_NavMesh_IsCacheReady",			Native_IsCacheReady);
	CreateNative("SMBL_NavMesh_NotifyOnCache",			Native_NotifyOnCache);

	CreateNative("NavMesh.LookupCache",					Native_NavMesh_LookupCache);

	// Static
	CreateNative("NavMesh.RegisterCache",				Native_NavMesh_RegisterCache);
	CreateNative("NavMesh.DeregisterCache",				Native_NavMesh_DeregisterCache);

	m_hNavCacheables = new ArrayList(sizeof(NavCacheable));

	g_hCacheForward = new GlobalForward("SMBL_NavMesh_OnCache", ET_Ignore);
}

public any Native_IsCacheReady(Handle hPlugin, int iArgC) {
	return g_bCacheReady;
}

public any Native_NotifyOnCache(Handle hPlugin, int iArgC) {
	if (g_bCacheReady) {
		Function fnForward = GetFunctionByName(hPlugin, "SMBL_NavMesh_OnCache");
		if (fnForward != INVALID_FUNCTION) {
			Call_StartFunction(hPlugin, fnForward);
			Call_Finish();
		}
	}

	return 0;
}

public any Native_NavMesh_LookupCache(Handle hPlugin, int iArgC) {
	NavMesh mNavMesh = GetNativeCell(1);

	char sBucketName[256];
	GetNativeString(2, sBucketName, sizeof(sBucketName));

	NavNode mNodeA = GetNativeCell(3);
	NavNode mNodeB = GetNativeCell(4);

	if (!mNodeA || !mNodeB) {
		return false;
	}

	KeyValues hKVData = GetNativeCell(5);

	char sPluginKey[6];
	PackCellToStr(hPlugin, sPluginKey);

	ArrayList hNavMeshes = GetNavMeshes();
	StringMap hNavCaches = hNavMeshes.Get(view_as<int>(mNavMesh)-1, _NavMesh::hNavCaches);

	NavCache eNavCache;
	if (!hNavCaches || !hNavCaches.GetArray(sPluginKey, eNavCache, sizeof(NavCache))) {
		char sPluginFilePath[PLATFORM_MAX_PATH];
		char sPluginFileName[PLATFORM_MAX_PATH];
		GetPluginFilename(hPlugin, sPluginFilePath, sizeof(sPluginFilePath));
		GetBaseFileName(sPluginFilePath, sPluginFileName, sizeof(sPluginFileName));

		PrintToServer("[SMBL] NavCache: Cache not loaded (%s)", sPluginFileName);
		return false;
	}

	NavCacheBucket eNavCacheBucket;
	if (!eNavCache.hBuckets.GetArray(sBucketName, eNavCacheBucket, sizeof(NavCacheBucket))) {
		char sPluginFilePath[PLATFORM_MAX_PATH];
		char sPluginFileName[PLATFORM_MAX_PATH];
		GetPluginFilename(hPlugin, sPluginFilePath, sizeof(sPluginFilePath));
		GetBaseFileName(sPluginFilePath, sPluginFileName, sizeof(sPluginFileName));

		PrintToServer("[SMBL] NavCache: %s not found in cache (%s)", sBucketName, sPluginFileName);
		return false;
	}

	char sNodeIndexKey[6];
	PackCellToStr((view_as<int>(mNodeB.iIndex) << 16) | view_as<int>(mNodeA.iIndex), sNodeIndexKey);

	NavCacheNodeKVID eNavCacheNodeKVID;
	if (!eNavCacheBucket.hNodeKVIDs.GetArray(sNodeIndexKey, eNavCacheNodeKVID, sizeof(NavCacheNodeKVID))) {
		PrintToServer("[SMBL] NavCache: Cache miss (%s: %d, %d)", sBucketName, mNodeA.iIndex, mNodeB.iIndex);
		return false;
	}

	if (!hKVData) {
		return true;
	}

	eNavCache.hKVData.Rewind();

	if (eNavCache.hKVData.JumpToKeySymbol(eNavCache.iBucketListKVID) &&
		eNavCache.hKVData.JumpToKeySymbol(eNavCacheBucket.iBucketKVID) &&
		eNavCache.hKVData.JumpToKeySymbol(eNavCacheNodeKVID.iNodeA) &&
		eNavCache.hKVData.JumpToKeySymbol(eNavCacheNodeKVID.iNodeB)) {
		hKVData.Import(eNavCache.hKVData);
		eNavCache.hKVData.Rewind();

		PrintToServer("[SMBL] NavCache: Cache hit (%s: %d, %d)",  sBucketName, mNodeA.iIndex, mNodeA.iIndex);

		return true;
	}

	PrintToServer("[SMBL] NavCache: Cache lookup failed (%s: %d, %d)", sBucketName, mNodeA.iIndex, mNodeA.iIndex);

// 		if (!hNavCache.JumpToKeySymbol(eNavIndexKeys.iBucket)) {
// 			PrintToServer("[SMBL] NavCache: Bucket %s not found", sBucketName);
// 			hNavCache.Rewind();
// 			return false;
// 		}

// 		if (!hNavCache.JumpToKeySymbol(eNavIndexKeys.iNodeA)) {
// 			PrintToServer("[SMBL] NavCache: Bucket %s key symbols (%d, x) not found", sBucketName, eNavIndexKeys.iNodeA);
// 			hNavCache.Rewind();
// 			return false;
// 		}

// 		if (!hNavCache.JumpToKeySymbol(eNavIndexKeys.iNodeB)) {
// 			PrintToServer("[SMBL] NavCache: Bucket %s key symbols (%d, %d) not found", sBucketName, eNavIndexKeys.iNodeA, eNavIndexKeys.iNodeB);
// 			hNavCache.Rewind();
// 			return false;
// 		}

// 		hCacheData.Import(hNavCache);
	eNavCache.hKVData.Rewind();

	return true;
}

public any Native_NavMesh_RegisterCache(Handle hPlugin, int iArgC) {
	char sBucketName[256];
	GetNativeString(1, sBucketName, sizeof(sBucketName));

	if (IsValidFileName(sBucketName)) {
		ThrowError("Invalid bucket name (%s)", sBucketName);
	}

	char sPluginFilePath[PLATFORM_MAX_PATH];
	char sPluginFileName[PLATFORM_MAX_PATH];

	GetPluginFilename(hPlugin, sPluginFilePath, sizeof(sPluginFilePath));
	GetBaseFileName(sPluginFilePath, sPluginFileName, sizeof(sPluginFileName));

	Function fnNavCacheableFunc = GetNativeFunction(2);

	for (int i=0; i<m_hNavCacheables.Length; i++) {
		NavCacheable eNavCacheable;
		m_hNavCacheables.GetArray(i, eNavCacheable);

		if (eNavCacheable.hCachePlugin == hPlugin && StrEqual(eNavCacheable.sBucketName, sBucketName)) {
			if (eNavCacheable.fnNavCacheableFunc == fnNavCacheableFunc) {
				return true;
			}

			ThrowError("Bucket with this name is already registered: %s", sBucketName);
		}
	}

	NavCacheable eNavCacheable;
	eNavCacheable.hCachePlugin = hPlugin;
	eNavCacheable.fnNavCacheableFunc = fnNavCacheableFunc;
	eNavCacheable.sBucketName = sBucketName;

	m_hNavCacheables.PushArray(eNavCacheable);

	PrintToServer("[SMBL] NavCache: Registered %s with cache (%s)", sBucketName, sPluginFileName);

	LoadNavMeshCacheable(eNavCacheable);

	return true;
}

public int Native_NavMesh_DeregisterCache(Handle hPlugin, int iArgC) {
	char sBucketName[256];
	GetNativeString(1, sBucketName, sizeof(sBucketName));

	char sPluginFilePath[PLATFORM_MAX_PATH];
	char sPluginFileName[PLATFORM_MAX_PATH];

	GetPluginFilename(hPlugin, sPluginFilePath, sizeof(sPluginFilePath));
	GetBaseFileName(sPluginFilePath, sPluginFileName, sizeof(sPluginFileName));

	if (sBucketName[0]) {
		if (IsValidFileName(sBucketName)) {
			ThrowError("Invalid bucket name (%s)", sBucketName);
		}

		for (int i=0; i<m_hNavCacheables.Length; i++) {
			NavCacheable eNavCacheable;
			m_hNavCacheables.GetArray(i, eNavCacheable);

			if (eNavCacheable.hCachePlugin == hPlugin && StrEqual(eNavCacheable.sBucketName, sBucketName)) {
				m_hNavCacheables.Erase(i);

				PrintToServer("[SMBL] NavCache: Deregistered %s from cache (%s)", sBucketName, sPluginFileName);

				return true;
			}
		}

		return false;
	}

	bool bRemoved;

	for (int i=0; i<m_hNavCacheables.Length; i++) {
		NavCacheable eNavCacheable;
		m_hNavCacheables.GetArray(i, eNavCacheable);

		if (eNavCacheable.hCachePlugin == hPlugin) {
			m_hNavCacheables.Erase(i--);

			PrintToServer("[SMBL] NavCache: Deregistered %s from cache (%s)", eNavCacheable.sBucketName, sPluginFileName);

			bRemoved = true;
		}
	}

	return bRemoved;
}

// Operation structs

enum struct OpData_Cache_ProcessCacheable {
	ArrayList hNavNodes;
	KeyValues hKVData;
	int iBucketListKVID;
	int iBucketKVID;
	StringMap hNodeKVIDs;
	DataPack hComplexParams;
	int iTotal;
	int iCacheCount;
	int iNextPercent;
	any aPadding[7];
}

enum struct SeqData_Cache_ProcessCacheable {
	int i;
	int j;
	int iKVIDNodeA;
	bool bDataWritten;
	any aPadding[12];
}

// Operation callbacks

OpRet Cache_ProcessCacheable_Init(Bot mBot, Operation mOp, KeyValues hInitParams, ArrayList hSequences, ArrayList hSubOpRefs, OpData_Cache_ProcessCacheable eOpData) {
	eOpData.hNavNodes = view_as<ArrayList>(hInitParams.GetNum("nav_nodes"));

	eOpData.hKVData = view_as<KeyValues>(hInitParams.GetNum("kv_data"));

	eOpData.iBucketListKVID = hInitParams.GetNum("bucketlist_kv_id");
	eOpData.iBucketKVID = hInitParams.GetNum("bucket_kv_id");
	eOpData.hNodeKVIDs = view_as<StringMap>(hInitParams.GetNum("node_kv_ids"));

	eOpData.hComplexParams = view_as<DataPack>(hInitParams.GetNum("complex_params"));
	eOpData.iTotal = eOpData.hNavNodes.Length * eOpData.hNavNodes.Length;

	Sequence eSeq;

	eSeq.iSeq = view_as<Seq>(0);
	eSeq.sIdentifier = "Iterate";
	eSeq.fnRun = Cache_ProcessCacheable_Iterate;
	hSequences.PushArray(eSeq);

	eSeq.iSeq = view_as<Seq>(1);
	eSeq.sIdentifier = "Export_To_File";
	eSeq.fnRun = Cache_ProcessCacheable_ExportToFile;
	hSequences.PushArray(eSeq);

	return OpRet_Continue;
}

void Cache_ProcessCacheable_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Cache_ProcessCacheable eOpData) {
	delete eOpData.hComplexParams;
}

void Cache_Queue_Cleanup(Bot mBot, Operation mOp, ArrayList hSequences, OpData_Cache_ProcessCacheable eOpData) {
	// Operation timer will automatically destroy the operation after returning from cleanup
	m_mCacheQueueOp = NULL_OPERATION;
}

// Sequence callbacks

OpRet Cache_ProcessCacheable_Iterate(Bot mBot, Operation mOp, OpData_Cache_ProcessCacheable eOpData, SeqData_Cache_ProcessCacheable eSeqData, float fStartTime) {
	eOpData.hKVData.Rewind();
	eOpData.hKVData.JumpToKeySymbol(eOpData.iBucketListKVID);
	eOpData.hKVData.JumpToKeySymbol(eOpData.iBucketKVID);

	float fIterStartTime = GetEngineTime();

	eOpData.hComplexParams.Reset();

	Handle hCachePlugin = eOpData.hComplexParams.ReadCell();
	Function fnNavCacheableFunc = eOpData.hComplexParams.ReadFunction();

	char sBucketName[256];
	char sPluginFileName[PLATFORM_MAX_PATH];
	eOpData.hComplexParams.ReadString(sBucketName, sizeof(sBucketName));
	eOpData.hComplexParams.ReadString(sPluginFileName, sizeof(sPluginFileName));

	char sKeyA[8];

	while (eSeqData.i < eOpData.hNavNodes.Length) {
		IntToString(eSeqData.i, sKeyA, sizeof(sKeyA));

		eOpData.hKVData.JumpToKey(sKeyA, true);
		eOpData.hKVData.GetSectionSymbol(eSeqData.iKVIDNodeA);

		NavNode mNodeA = eOpData.hNavNodes.Get(eSeqData.i);

		while (eSeqData.j < eOpData.hNavNodes.Length) {
			float fMaxFrameTime = GetClientCount() ? 5*GetTickInterval() : MAX_FRAME_TIME;
			if (GetEngineTime()-fIterStartTime > fMaxFrameTime) {
				eOpData.hKVData.Rewind();

				return OpRet_Continue;
			}

			int iCount = eSeqData.i*eOpData.hNavNodes.Length + eSeqData.j+1;
			int iPercent = 100*iCount/eOpData.iTotal;
			if (iPercent >= eOpData.iNextPercent) {
				PrintToServer("[SMBL] NavCache: Generating %s... %d%%", sBucketName, iPercent);
				eOpData.iNextPercent += 10;
			}

			NavNode mNodeB = eOpData.hNavNodes.Get(eSeqData.j);

			KeyValues hCacheData = new KeyValues("CacheData");

			Call_StartFunction(hCachePlugin, fnNavCacheableFunc);
			Call_PushCell(mNodeA);
			Call_PushCell(mNodeB);
			Call_PushCell(hCacheData);

			bool bReturn;
			int iCallError = Call_Finish(bReturn);
			if (iCallError != SP_ERROR_NONE || !bReturn) {
				delete hCacheData;
				eSeqData.j++;

				continue;
			}

			eSeqData.bDataWritten = true;
			eOpData.iCacheCount++;

			NavCacheNodeKVID eNavCacheNodeKVID;
			eNavCacheNodeKVID.iNodeA = eSeqData.iKVIDNodeA;

			char sKeyB[8];
			IntToString(eSeqData.j, sKeyB, sizeof(sKeyB));

			eOpData.hKVData.JumpToKey(sKeyB, true);
			eOpData.hKVData.GetSectionSymbol(eNavCacheNodeKVID.iNodeB);

			eOpData.hKVData.Import(hCacheData);
			eOpData.hKVData.SetSectionName(sKeyB);

			char sBucketIndexKey[6];
			PackCellToStr((eSeqData.j << 16) | eSeqData.i, sBucketIndexKey);
			eOpData.hNodeKVIDs.SetArray(sBucketIndexKey, eNavCacheNodeKVID, sizeof(NavCacheNodeKVID));

			eOpData.hKVData.GoBack();  // from sKeyB

			delete hCacheData;

			eSeqData.j++;
		}

		eOpData.hKVData.GoBack(); // from sKeyA

		if (!eSeqData.bDataWritten) {
			eOpData.hKVData.DeleteKey(sKeyA);
		}

		eSeqData.i++;
		eSeqData.j = 0;

		eSeqData.bDataWritten = false;
	}

	eOpData.hKVData.Rewind();

	return OpRet_Handled;
}

OpRet Cache_ProcessCacheable_ExportToFile(Bot mBot, Operation mOp, OpData_Cache_ProcessCacheable eOpData, SeqData eSeqData, float fStartTime) {
	eOpData.hKVData.Rewind();
	eOpData.hKVData.JumpToKeySymbol(eOpData.iBucketListKVID);
	eOpData.hKVData.JumpToKeySymbol(eOpData.iBucketKVID);

	eOpData.hComplexParams.Reset();
	eOpData.hComplexParams.ReadCell();
	eOpData.hComplexParams.ReadFunction();

	char sBucketName[256];
	eOpData.hComplexParams.ReadString(sBucketName, sizeof(sBucketName));

	char sFilePath[PLATFORM_MAX_PATH];
	eOpData.hComplexParams.ReadString(sFilePath, sizeof(sFilePath)); // Plugin filename

	char sFileName[PLATFORM_MAX_PATH];
	GetBaseFileName(sFilePath, sFileName, sizeof(sFileName));

	eOpData.hComplexParams.ReadString(sFilePath, sizeof(sFilePath)); // Cache file path

	eOpData.hKVData.SetNum("count", eOpData.iCacheCount);

	eOpData.hKVData.Rewind();
	eOpData.hKVData.ExportToFile(sFilePath);

	PrintToServer("[SMBL] NavCache: Saved %s to cache with %d items (%s)", sBucketName, eOpData.iCacheCount, sFileName);

	return OpRet_Handled;
}

// Custom callbacks

public void RequestFrameCallback_Cache(any aData) {
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), NAV_CACHE_PATH);
	if (!DirExists(sFilePath)) {
		CreateDirectory(sFilePath);
	}

	g_bCacheReady = true;

	Call_StartForward(g_hCacheForward);
	Call_Finish();
}

// Helpers

void Setup_CacheOperation() {
	Operation.Register("NavMesh.Cache.Queue", _, _, _, _, _, _, Cache_Queue_Cleanup, false, true, false, false);
	Operation.Register("NavMesh.Cache.ProcessCacheable", Cache_ProcessCacheable_Init, _, _, _, _, _, Cache_ProcessCacheable_Cleanup);

	RequestFrame(RequestFrameCallback_Cache);
}

void LoadNavMeshCacheable(NavCacheable eNavCacheable) {
	ArrayList hNavMeshes = GetNavMeshes();

	for (int i=0; i<hNavMeshes.Length; i++) {
		_NavMesh eNavMesh;
		hNavMeshes.GetArray(i, eNavMesh);

		if (!eNavMesh.bGCFlag && eNavMesh.sFileName[0]) {
			PopulateCache(eNavCacheable, eNavMesh.hNavCaches, eNavMesh.iTimestamp, eNavMesh.sFileName, eNavMesh.hNavNodes);
		}
	}
}

void PopulateCaches(StringMap hNavCaches, int iNavMeshTimestamp, char[] sNavMeshFileName, ArrayList hNavNodes) {
	for (int i=0; i<m_hNavCacheables.Length; i++) {
		NavCacheable eNavCacheable;
		m_hNavCacheables.GetArray(i, eNavCacheable);

		PopulateCache(eNavCacheable, hNavCaches, iNavMeshTimestamp, sNavMeshFileName, hNavNodes)
	}
}

void PopulateCache(NavCacheable eNavCacheable, StringMap hNavCaches, int iNavMeshTimestamp, char[] sNavMeshFileName, ArrayList hNavNodes) {
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/%s", NAV_CACHE_PATH, sNavMeshFileName);
	if (!DirExists(sFilePath)) {
		CreateDirectory(sFilePath);
	}

	char sPluginFilePath[PLATFORM_MAX_PATH];
	char sPluginFileName[PLATFORM_MAX_PATH];

	char sNavPluginVersion[32], sCachePluginVersion[32];
	char sSavedNavPluginVersion[32], sSavedCachePluginVersion[32];

	GetPluginInfo(null, PlInfo_Version, sNavPluginVersion, sizeof(sNavPluginVersion));

	char sPluginKey[6];
	PackCellToStr(eNavCacheable.hCachePlugin, sPluginKey);

	NavCache eNavCache;
	bool bCachePluginFound = hNavCaches.GetArray(sPluginKey, eNavCache, sizeof(NavCache));

	bool bValidCache;

	if (bCachePluginFound) {
		if (eNavCache.hBuckets.ContainsKey(eNavCacheable.sBucketName)) {
			return;
		}

		GetPluginFilename(eNavCacheable.hCachePlugin, sPluginFilePath, sizeof(sPluginFilePath));
		GetBaseFileName(sPluginFilePath, sPluginFileName, sizeof(sPluginFileName));

		BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/%s/%s.txt", NAV_CACHE_PATH, sNavMeshFileName, sPluginFileName);

		eNavCache.hKVData.Rewind();

		bValidCache = FileExists(sFilePath);
	} else {
		// Check if already in processing queue
		if (m_mCacheQueueOp) {
			bool bAlreadyQueued;

			ArrayList hSubOpRefs = m_mCacheQueueOp.hSubOpRefs;

			char sSubOpBucketName[256];

			for (int j=0; j<hSubOpRefs.Length; j++) {
				Operation mSubOp = view_as<OpRef>(hSubOpRefs.Get(j)).ToOperation();

				if (mSubOp) {
					DataPack hComplexParams = view_as<DataPack>(mSubOp.hInitParams.GetNum("complex_params"));
					hComplexParams.Reset();

					Handle hSubOpCachePlugin = hComplexParams.ReadCell();
					hComplexParams.ReadFunction();
					hComplexParams.ReadString(sSubOpBucketName, sizeof(sSubOpBucketName));

					if (eNavCacheable.hCachePlugin == hSubOpCachePlugin && StrEqual(eNavCacheable.sBucketName, sSubOpBucketName)) {
						bAlreadyQueued = true;
						break;
					}
				}
			}

			if (bAlreadyQueued) {
				return;
			}
		}

		eNavCache.hKVData = new KeyValues("NavCache");
		eNavCache.hBuckets = new StringMap();

		GetPluginFilename(eNavCacheable.hCachePlugin, sPluginFilePath, sizeof(sPluginFilePath));
		GetBaseFileName(sPluginFilePath, sPluginFileName, sizeof(sPluginFileName));

		BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/%s/%s.txt", NAV_CACHE_PATH, sNavMeshFileName, sPluginFileName);

		GetPluginInfo(eNavCacheable.hCachePlugin, PlInfo_Version, sCachePluginVersion, sizeof(sCachePluginVersion));

		if (FileExists(sFilePath)) {
			PrintToServer("[SMBL] NavCache: Checking cache (%s)", sPluginFileName);

			eNavCache.hKVData.ImportFromFile(sFilePath);

			eNavCache.hKVData.GetString("nav_plugin_version", sSavedNavPluginVersion, sizeof(sSavedNavPluginVersion));
			eNavCache.hKVData.GetString("cache_plugin_version", sSavedCachePluginVersion, sizeof(sSavedCachePluginVersion));

			int iTimestamp = eNavCache.hKVData.GetNum("nav_mesh_timestamp");

			bValidCache = iTimestamp == iNavMeshTimestamp && StrEqual(sNavPluginVersion, sSavedNavPluginVersion) && StrEqual(sCachePluginVersion, sSavedCachePluginVersion);

			if (!bValidCache) {
				PrintToServer("[SMBL] NavCache: Cache is outdated and will be regenerated (%s)", sPluginFileName);

				ClearCache(hNavCaches, sPluginKey);
				DeleteFile(sFilePath);
			}
		} else {
			PrintToServer("[SMBL] NavCache: Generating new cache (%s)", sPluginFileName);
		}

		eNavCache.hKVData.SetString("nav_plugin_version", sNavPluginVersion);
		eNavCache.hKVData.SetString("cache_plugin_version", sCachePluginVersion);
		eNavCache.hKVData.SetNum("nav_mesh_timestamp", iNavMeshTimestamp);
	}

	eNavCache.hKVData.JumpToKey("buckets", true);
	eNavCache.hKVData.GetSectionSymbol(eNavCache.iBucketListKVID);

	hNavCaches.SetArray(sPluginKey, eNavCache, sizeof(NavCache));

	NavCacheBucket eNavCacheBucket;
	eNavCacheBucket.hNodeKVIDs = new StringMap();

	NavCacheNodeKVID eNavCacheNodeKVID;

	if (bValidCache && eNavCache.hKVData.JumpToKey(eNavCacheable.sBucketName)) {
		eNavCache.hKVData.GetSectionSymbol(eNavCacheBucket.iBucketKVID);

		eNavCache.hBuckets.SetArray(eNavCacheable.sBucketName, eNavCacheBucket, sizeof(NavCacheBucket));

		int iCacheCount = eNavCache.hKVData.GetNum("count");

		if (eNavCache.hKVData.GotoFirstSubKey(true)) {
			char sKeyA[8], sKeyB[8];

			do {
				eNavCache.hKVData.GetSectionName(sKeyA, sizeof(sKeyA));
				eNavCache.hKVData.GetSectionSymbol(eNavCacheNodeKVID.iNodeA);

				if (eNavCache.hKVData.GotoFirstSubKey(true)) {
					do {
						eNavCache.hKVData.GetSectionName(sKeyB, sizeof(sKeyB));
						eNavCache.hKVData.GetSectionSymbol(eNavCacheNodeKVID.iNodeB);

						int iNodeA = StringToInt(sKeyA);
						int iNodeB = StringToInt(sKeyB);

						char sBucketIndexKey[6];
						PackCellToStr((iNodeB << 16) | iNodeA, sBucketIndexKey);
						eNavCacheBucket.hNodeKVIDs.SetArray(sBucketIndexKey, eNavCacheNodeKVID, sizeof(NavCacheNodeKVID));
					} while (eNavCache.hKVData.GotoNextKey(true));

					eNavCache.hKVData.GoBack();
				}
			} while (eNavCache.hKVData.GotoNextKey(true));
		}

		PrintToServer("[SMBL] NavCache: Loaded %s from cache with %d items (%s)", eNavCacheable.sBucketName, iCacheCount, sPluginFileName);

		eNavCache.hKVData.Rewind();
	} else {
		eNavCache.hKVData.JumpToKey(eNavCacheable.sBucketName, true);
		eNavCache.hKVData.GetSectionSymbol(eNavCacheBucket.iBucketKVID);

		eNavCache.hBuckets.SetArray(eNavCacheable.sBucketName, eNavCacheBucket, sizeof(NavCacheBucket));

		if (!m_mCacheQueueOp) {
			m_mCacheQueueOp = Operation.Instance("NavMesh.Cache.Queue");
			m_mCacheQueueOp.Init(NULL_BOT);
			m_mCacheQueueOp.Run(0.1, TIMER_REPEAT);
		}

		KeyValues hInitParams;
		Operation mProcessCacheableOp = Operation.Instance("NavMesh.Cache.ProcessCacheable", hInitParams);

		hInitParams.SetNum("nav_nodes", view_as<int>(hNavNodes));
		hInitParams.SetNum("kv_data", view_as<int>(eNavCache.hKVData));
		hInitParams.SetNum("bucketlist_kv_id", eNavCache.iBucketListKVID);
		hInitParams.SetNum("bucket_kv_id", eNavCacheBucket.iBucketKVID);
		hInitParams.SetNum("node_kv_ids", view_as<int>(eNavCacheBucket.hNodeKVIDs));

		DataPack hComplexParams = new DataPack();
		hComplexParams.WriteCell(eNavCacheable.hCachePlugin);
		hComplexParams.WriteFunction(eNavCacheable.fnNavCacheableFunc);
		hComplexParams.WriteString(eNavCacheable.sBucketName);
		hComplexParams.WriteString(sPluginFileName);
		hComplexParams.WriteString(sFilePath);
		hInitParams.SetNum("complex_params", view_as<int>(hComplexParams));

		m_mCacheQueueOp.AddSubOperation(mProcessCacheableOp);

		// Operation spreads across multiple frames the equivalent of this sequential code,
		// which causes script execution timeouts for computationally expensive cacheables.

		/*
		int iNodesLength = hNavNodes.Length;
		int iTotal = iNodesLength*iNodesLength;
		int iCacheCount;

		int iNextPercent;
		for (int j=0; j<iNodesLength; j++) {
			NavNode mNodeA = hNavNodes.Get(j);

			char sKeyA[8];
			IntToString(i, sKeyA, sizeof(sKeyA));

			eNavCache.hKVData.JumpToKey(sKeyA, true);
			eNavCache.hKVData.GetSectionSymbol(eNavCacheNodeKVID.iNodeA);

			bool bDataWritten;

			for (int k=0; k<iNodesLength; k++) {
				int iCount = j*iNodesLength + k+1;
				int iPercent = 100*iCount/iTotal;
				if (iPercent >= iNextPercent) {
					PrintToServer("[SMBL] NavCache: Generating cache %s (%s)... %d%%", eNavCacheable.sBucketName, sPluginFileName, iPercent);
					iNextPercent += 10;
				}

				NavNode mNodeB = hNavNodes.Get(k);

				KeyValues hCacheData = new KeyValues("CacheData");

				Call_StartFunction(eNavCacheable.hCachePlugin, eNavCacheable.fnNavCacheableFunc);
				Call_PushCell(mNodeA);
				Call_PushCell(mNodeB);
				Call_PushCell(hCacheData);

				bool bReturn;
				int iCallError = Call_Finish(bReturn);
				if (iCallError != SP_ERROR_NONE || !bReturn) {
					delete hCacheData;
					continue;
				}

				bDataWritten = true;
				iCacheCount++;

				char sKeyB[8];
				IntToString(j, sKeyB, sizeof(sKeyB));

				eNavCache.hKVData.JumpToKey(sKeyB, true);
				eNavCache.hKVData.GetSectionSymbol(eNavCacheNodeKVID.iNodeB);

				eNavCache.hKVData.Import(hCacheData);
				eNavCache.hKVData.SetSectionName(sKeyB);

				char sBucketIndexKey[6];
				PackCellToStr((j << 16) | i, sBucketIndexKey);
				eNavCacheBucket.hNodeKVIDs.SetArray(sBucketIndexKey, eNavCacheNodeKVID, sizeof(NavCacheNodeKVID));

				eNavCache.hKVData.GoBack();  // from sKeyB

				delete hCacheData;
			}

			eNavCache.hKVData.GoBack(); // from sKeyA

			if (!bDataWritten) {
				eNavCache.hKVData.DeleteKey(sKeyA);
			}
		}

		eNavCache.hKVData.SetNum("count", iCacheCount);

		eNavCache.hKVData.Rewind();
		eNavCache.hKVData.ExportToFile(sFilePath);

		PrintToServer("[SMBL] NavCache: Generated %s with %d items (%s)", eNavCacheable.sBucketName, iCacheCount, sPluginFileName);
		*/
	}
}

void ClearCaches(StringMap hNavCaches) {
	StringMapSnapshot hNavCachesSnapshot = hNavCaches.Snapshot();

	for (int i=0; i<hNavCachesSnapshot.Length; i++) {
		char sPluginKey[6];
		hNavCachesSnapshot.GetKey(i, sPluginKey, sizeof(sPluginKey));

		ClearCache(hNavCaches, sPluginKey);
	}

	delete hNavCachesSnapshot;

	hNavCaches.Clear();
}

void ClearCache(StringMap hNavCaches, char[] sPluginKey) {
	NavCache eNavCache;
	if (!hNavCaches.GetArray(sPluginKey, eNavCache, sizeof(NavCache))) {
		return;
	}

	// Remove any running cache operation using this plugin
	if (m_mCacheQueueOp) {
		ArrayList hSubOpRefs = m_mCacheQueueOp.hSubOpRefs;

		for (int i=0; i<hSubOpRefs.Length; i++) {
			Operation mSubOp = view_as<OpRef>(hSubOpRefs.Get(i)).ToOperation();

			if (mSubOp) {
				DataPack hComplexParams = view_as<DataPack>(mSubOp.hInitParams.GetNum("complex_params"));
				hComplexParams.Reset();

				Handle hSubOpCachePlugin = hComplexParams.ReadCell();

				char sSubOpCachePluginKey[6];
				PackCellToStr(hSubOpCachePlugin, sSubOpCachePluginKey);

				if (StrEqual(sPluginKey, sSubOpCachePluginKey)) {
					Operation.Destroy(mSubOp);
					hSubOpRefs.Erase(i--);
				}
			}
		}
	}

	delete eNavCache.hKVData;

	StringMapSnapshot hBucketSnapshot = eNavCache.hBuckets.Snapshot();

	for (int i=0; i<hBucketSnapshot.Length; i++) {
		char sBucketName[32];
		hBucketSnapshot.GetKey(i, sBucketName, sizeof(sBucketName));

		NavCacheBucket eNavCacheBucket;
		eNavCache.hBuckets.GetArray(sBucketName, eNavCacheBucket, sizeof(NavCacheBucket));
		delete eNavCacheBucket.hNodeKVIDs;
	}

	delete hBucketSnapshot;
	delete eNavCache.hBuckets;

	hNavCaches.Remove(sPluginKey);
}

void CheckUnloadCacheable(Handle hPlugin) {
	bool bUnloaded;
	for (int i=0; i<m_hNavCacheables.Length; i++) {
		if (m_hNavCacheables.Get(i, NavCacheable::hCachePlugin) == hPlugin) {
			m_hNavCacheables.Erase(i--);
			bUnloaded = true;
		}
	}

	if (bUnloaded) {
		char sPluginFilePath[PLATFORM_MAX_PATH];
		char sPluginFileName[PLATFORM_MAX_PATH];
		GetPluginFilename(hPlugin, sPluginFilePath, sizeof(sPluginFilePath));
		GetBaseFileName(sPluginFilePath, sPluginFileName, sizeof(sPluginFileName));

		PrintToServer("[SMBL] NavCache: Cache cleared on plugin unload (%s)", sPluginFileName);
	}
}

void CheckUnloadCaches(Handle hPlugin, StringMap hNavCaches) {
	char sPluginKey[6];
	PackCellToStr(hPlugin, sPluginKey);

	ClearCache(hNavCaches, sPluginKey);
}
