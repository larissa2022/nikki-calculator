import { ref, computed } from 'vue'
import { supabase } from '../api/supabase'

// ====== 🌟 本地硬盘 (IndexedDB) 驱动逻辑 ======
const dbPromise = new Promise((resolve, reject) => {
  const request = indexedDB.open('NikkiCacheDB', 1)
  request.onupgradeneeded = e => e.target.result.createObjectStore('cache')
  request.onsuccess = e => resolve(e.target.result)
  request.onerror = () => reject('IDB初始化失败')
})

const saveToLocal = async (key, data) => {
  const db = await dbPromise
  const pureData = JSON.parse(JSON.stringify(data)) // 脱离 Vue Proxy 魔法
  db.transaction('cache', 'readwrite').objectStore('cache').put(pureData, key)
}

const getFromLocal = async (key) => {
  const db = await dbPromise
  return new Promise(resolve => {
    const req = db.transaction('cache').objectStore('cache').get(key)
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => resolve(null)
  })
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
  const loadData = async () => {
    isLoading.value = true
    try {
      const { count: cloudCount, error: countError } = await supabase
        .from('clothes')
        .select('id', { count: 'exact' })
        .limit(1)

      if (countError) throw countError

      const localClothes = await getFromLocal('fullClothesData_v2') 
      const localStages = await getFromLocal('stagesData')

      if (localClothes && localClothes.length === cloudCount && localStages) {
        fullWardrobeData.value = localClothes
        stagesData.value = localStages
      } else {
        const [cRes, sRes] = await Promise.all([
          supabase.from('clothes').select('*, suits(name)'),
          supabase.from('stages').select('*').order('id')
        ])
        
        const rawClothes = cRes.data || []
        fullWardrobeData.value = rawClothes.map(item => ({
          ...item,
          suit_name: item.suits?.name || null
        }))
        stagesData.value = sRes.data || []

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
        myWardrobeIds.value = data.owned_clothes
      }
    } catch (err) {
      console.error("☁️ 从云端同步衣柜失败:", err.message)
    }
  }

  // 3. 🌟 将我的衣柜存入云端 (重构为：悲观更新安全版)
  const saveWardrobeToCloud = async (userId, pendingIds = null) => { 
    if (!userId) throw new Error('用户未登录')
    
    // 如果传入了新的待存数组，就用新的；如果没有，就兜底用旧的
    const dataToSave = pendingIds || myWardrobeIds.value
    
    isSaving.value = true // 🔒 开启界面锁

    try {
      // 🛡️ 防御 1：强行查岗！防止移动端微信悄悄杀后台导致 Token 失效
      const { data: { session }, error: authErr } = await supabase.auth.getSession()
      if (authErr || !session) throw new Error('登录状态已过期，请重新登录！')

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
        myWardrobeIds.value = [...new Set(pendingIds)] // 顺手去个重
      }
      
      return true // 告诉外部组件“保存成功了！”
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