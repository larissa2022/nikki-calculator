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
      // 获取云端总条数
      const { count: cloudCount } = await supabase
        .from('clothes')
        .select('*', { count: 'exact', head: true })

      const localClothes = await getFromLocal('fullClothesData')
      const localStages = await getFromLocal('stagesData')

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
    const { data } = await supabase.from('user_wardrobes').select('wardrobe_data').single()
    if (data) myWardrobeIds.value = data.wardrobe_data || []
  }

  // 3. 将我的衣柜存入云端
  const saveWardrobeToCloud = async (userId) => {
    if (!userId) return
    await supabase.from('user_wardrobes').upsert({ 
      user_id: userId, 
      wardrobe_data: myWardrobeIds.value 
    })
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