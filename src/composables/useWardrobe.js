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

  // 🚀 高性能计算：使用 Set 实现 O(1) 极速查找
  const myWardrobeSet = computed(() => new Set(myWardrobeIds.value))

  // 1. 初始化加载图鉴 (含智能缓存比对)
  const loadData = async () => {
    isLoading.value = true
    try {
      // 🌟 修复网络拦截：移除 head: true，改用 GET 请求获取 count
      // 技巧：只 select('id') 并且 limit(1)，既避开了 HEAD 拦截，又极大地节省了流量
      const { count: cloudCount, error: countError } = await supabase
        .from('clothes')
        .select('id', { count: 'exact' })
        .limit(1)

      if (countError) throw countError

      const localClothes = await getFromLocal('fullClothesData')
      const localStages = await getFromLocal('stagesData')

      // 缓存比对逻辑保持不变...
      if (localClothes && localClothes.length === cloudCount && localStages) {
        fullWardrobeData.value = localClothes
        stagesData.value = localStages
      } else {
        const [cRes, sRes] = await Promise.all([
          supabase.from('clothes').select('*'),
          supabase.from('stages').select('*').order('id')
        ])
        fullWardrobeData.value = cRes.data || []
        stagesData.value = sRes.data || []
        await saveToLocal('fullClothesData', fullWardrobeData.value)
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
        .select('owned_clothes') // 🌟 精准呼叫真实的列名
        .eq('user_id', userId)   // 绑定身份证，防止 400 报错
        .single()

      if (error) {
        // 忽略新用户第一次登录时“找不到空衣柜”的正常提示
        if (error.code !== 'PGRST116') throw error
      }
      
      // 🌟 接收数据时也要用真实的列名
      if (data && data.owned_clothes) {
        myWardrobeIds.value = data.owned_clothes
      }
    } catch (err) {
      console.error("☁️ 从云端同步衣柜失败:", err.message)
    }
  }

  // 3. 将我的衣柜存入云端
  const saveWardrobeToCloud = async (userId) => {
    if (!userId) return
    try {
      const { error } = await supabase.from('user_wardrobes').upsert({ 
        user_id: userId, 
        owned_clothes: myWardrobeIds.value // 🌟 保存时使用真实的列名
      })
      
      if (error) throw error
    } catch (err) {
      console.error("☁️ 保存衣柜到云端失败:", err.message)
    }
  }

  return {
    fullWardrobeData,
    myWardrobeIds,
    stagesData,
    isLoading,
    myWardrobeSet,
    loadData,
    syncWardrobeFromCloud,
    saveWardrobeToCloud
  }
}