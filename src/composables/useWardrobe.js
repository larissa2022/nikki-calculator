import { ref, computed } from 'vue'
import { supabase } from '../api/supabase'

const SUPABASE_PAGE_SIZE = 1000
const INDEXED_DB_TIMEOUT_MS = 3000

const fetchAllRows = async (table, selectColumns, applyQuery = query => query) => {
  const rows = []
  let from = 0

  while (true) {
    const to = from + SUPABASE_PAGE_SIZE - 1
    let query = supabase
      .from(table)
      .select(selectColumns)
      .range(from, to)

    query = applyQuery(query)

    const { data, error } = await query
    if (error) throw error

    const page = data || []
    rows.push(...page)

    if (page.length < SUPABASE_PAGE_SIZE) break
    from += SUPABASE_PAGE_SIZE
  }

  return rows
}

const normalizeOwnedIds = (ownedClothes) => {
  if (!Array.isArray(ownedClothes)) return []
  return [...new Set(ownedClothes.filter(Boolean).map(id => String(id)))]
}

const shouldBlockUnsafeShrink = (currentIds, nextIds) => {
  const currentCount = currentIds.length
  const nextCount = nextIds.length
  return currentCount >= 500 && currentCount - nextCount >= 100 && nextCount < currentCount * 0.5
}

// ====== 🌟 本地硬盘 (IndexedDB) 驱动逻辑 ======
const withCacheTimeout = (promise, label) => new Promise(resolve => {
  let settled = false
  const finish = value => {
    if (settled) return
    settled = true
    clearTimeout(timer)
    resolve(value)
  }

  const timer = setTimeout(() => {
    console.warn(`${label}超时，已降级跳过本地缓存`)
    finish(null)
  }, INDEXED_DB_TIMEOUT_MS)

  Promise.resolve(promise).then(
    finish,
    err => {
      console.warn(`${label}失败，已降级跳过本地缓存`, err)
      finish(null)
    }
  )
})

const dbPromise = withCacheTimeout(new Promise(resolve => {
  if (typeof indexedDB === 'undefined') {
    console.warn('IndexedDB不可用，已降级跳过本地缓存')
    resolve(null)
    return
  }

  try {
    const request = indexedDB.open('NikkiCacheDB', 1)
    request.onupgradeneeded = e => {
      const db = e.target.result
      if (!db.objectStoreNames.contains('cache')) db.createObjectStore('cache')
    }
    request.onsuccess = e => resolve(e.target.result)
    request.onerror = () => {
      console.warn('IDB初始化失败，已降级跳过本地缓存', request.error)
      resolve(null)
    }
    request.onblocked = () => {
      console.warn('IDB初始化被阻塞，已降级跳过本地缓存')
      resolve(null)
    }
  } catch (err) {
    console.warn('IDB初始化异常，已降级跳过本地缓存', err)
    resolve(null)
  }
}), 'IDB初始化')

const runCacheTransaction = async (mode, action, label) => {
  const db = await dbPromise
  if (!db) return null

  return withCacheTimeout(new Promise(resolve => {
    try {
      const tx = db.transaction('cache', mode)
      const store = tx.objectStore('cache')

      tx.onabort = () => {
        console.warn(`${label}中断，已降级跳过本地缓存`, tx.error)
        resolve(null)
      }
      tx.onerror = () => {
        console.warn(`${label}失败，已降级跳过本地缓存`, tx.error)
        resolve(null)
      }

      action(store, resolve)
    } catch (err) {
      console.warn(`${label}异常，已降级跳过本地缓存`, err)
      resolve(null)
    }
  }), label)
}

const saveToLocal = async (key, data) => {
  try {
    const pureData = JSON.parse(JSON.stringify(data)) // 脱离 Vue Proxy 魔法
    await runCacheTransaction('readwrite', (store, resolve) => {
      const req = store.put(pureData, key)
      req.onsuccess = () => resolve(true)
      req.onerror = () => {
        console.warn(`写入本地缓存 ${key} 失败，已跳过`, req.error)
        resolve(null)
      }
    }, `写入本地缓存 ${key}`)
  } catch (err) {
    console.warn(`写入本地缓存 ${key} 异常，已跳过`, err)
  }
}

const getFromLocal = async (key) => {
  try {
    return await runCacheTransaction('readonly', (store, resolve) => {
      const req = store.get(key)
      req.onsuccess = () => resolve(req.result || null)
      req.onerror = () => {
        console.warn(`读取本地缓存 ${key} 失败，已改走云端`, req.error)
        resolve(null)
      }
    }, `读取本地缓存 ${key}`)
  } catch (err) {
    console.warn(`读取本地缓存 ${key} 异常，已改走云端`, err)
    return null
  }
}

// ====== 👗 衣柜核心逻辑导出 ======
export function useWardrobe() {
  const fullWardrobeData = ref([])
  const myWardrobeIds = ref([])
  const stagesData = ref([])
  const isLoading = ref(false)
  const isSaving = ref(false) // 🌟 1. 新增：防抖与防误触的全局锁

  // 🚀 高性能计算：使用 Set 实现 O(1) 极速查找
  const myWardrobeSet = computed(() => new Set(myWardrobeIds.value))

  // 1. 初始化加载图鉴 (含智能缓存比对)
  const loadData = async ({ force = false } = {}) => {
    isLoading.value = true
    try {
      const { count: cloudCount, error: countError } = await supabase
        .from('clothes')
        .select('id', { count: 'exact' })
        .limit(1)

      if (countError) throw countError

      const localClothes = await getFromLocal('fullClothesData_v2') 
      const localStages = await getFromLocal('stagesData')

      if (!force && localClothes && localClothes.length === cloudCount && localStages) {
        fullWardrobeData.value = localClothes
        stagesData.value = localStages
      } else {
        const [clothesRows, stageRows] = await Promise.all([
          fetchAllRows('clothes', '*, suits(name)', query => query.order('id')),
          fetchAllRows('stages', '*', query => query.order('id'))
        ])
        
        fullWardrobeData.value = clothesRows.map(item => ({
          ...item,
          suit_name: item.suits?.name || null
        }))
        stagesData.value = stageRows

        await saveToLocal('fullClothesData_v2', fullWardrobeData.value) 
        await saveToLocal('stagesData', stagesData.value)
      }
    } catch (err) {
      console.error("加载图鉴失败:", err)
    } finally {
      isLoading.value = false
    }
  }

  // 2. 从云端同步我的衣柜
  const syncWardrobeFromCloud = async (userId) => {
    if (!userId) return
    try {
      const { data, error } = await supabase
        .from('user_wardrobes')
        .select('owned_clothes') 
        .eq('user_id', userId)   
        .maybeSingle()

      if (error && error.code !== 'PGRST116') throw error
      
      if (data && data.owned_clothes) {
        myWardrobeIds.value = normalizeOwnedIds(data.owned_clothes)
      }
    } catch (err) {
      console.error("☁️ 从云端同步衣柜失败:", err.message)
    }
  }

  // 3. 🌟 将我的衣柜存入云端 (重构为：悲观更新安全版)
  const saveWardrobeToCloud = async (userId, pendingIds = null, options = {}) => {
    if (!userId) throw new Error('用户未登录')
    
    // 如果传入了新的待存数组，就用新的；如果没有，就兜底用旧的
    const inputIds = normalizeOwnedIds(pendingIds || myWardrobeIds.value)
    const saveMode = options.mode || 'replace'
    
    isSaving.value = true // 🔒 开启界面锁

    try {
      // 🛡️ 防御 1：强行查岗！防止移动端微信悄悄杀后台导致 Token 失效
      const { data: { session }, error: authErr } = await supabase.auth.getSession()
      if (authErr || !session) throw new Error('登录状态已过期，请重新登录！')

      const { data: currentWardrobe, error: fetchError } = await supabase
        .from('user_wardrobes')
        .select('owned_clothes')
        .eq('user_id', userId)
        .maybeSingle()

      if (fetchError && fetchError.code !== 'PGRST116') throw fetchError

      const cloudIds = normalizeOwnedIds(currentWardrobe?.owned_clothes)
      const dataToSave = saveMode === 'merge'
        ? normalizeOwnedIds([...cloudIds, ...inputIds])
        : inputIds

      if (saveMode !== 'merge' && shouldBlockUnsafeShrink(cloudIds, dataToSave)) {
        throw new Error(`本次保存会把云端衣柜从 ${cloudIds.length} 件减少到 ${dataToSave.length} 件，已自动拦截。请刷新页面后重试。`)
      }

      // 🛡️ 防御 2：强行写入数据库
      const { error } = await supabase
        .from('user_wardrobes')
        .upsert(
          { user_id: userId, owned_clothes: dataToSave }, 
          { onConflict: 'user_id' }
        )

      if (error) throw error
      
      // 🛡️ 防御 3：只有数据库明确没报错，才允许前台数组更新！！！
      if (pendingIds) {
        myWardrobeIds.value = dataToSave // 顺手去个重
      }
      
      return dataToSave // 告诉外部组件“保存成功了！”
    } catch (err) {
      console.error('保存云端失败:', err)
      throw err // 把错误抛出去，让录入按钮捕获并弹窗警告
    } finally {
      isSaving.value = false // 🔓 无论成功失败，解开界面锁
    }
  }

  return {
    fullWardrobeData,
    myWardrobeIds,
    stagesData,
    isLoading,
    isSaving, // 🌟 把锁暴露给外部组件
    myWardrobeSet,
    loadData,
    syncWardrobeFromCloud,
    saveWardrobeToCloud
  }
}
