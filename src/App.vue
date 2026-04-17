<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { supabase } from './supabase'

// ====== 🌟 本地硬盘 (IndexedDB) 驱动 ======
const dbPromise = new Promise((resolve, reject) => {
  const request = indexedDB.open('NikkiCacheDB', 1)
  request.onupgradeneeded = e => e.target.result.createObjectStore('cache')
  request.onsuccess = e => resolve(e.target.result)
  request.onerror = () => reject('数据库挂了')
})

const saveToLocal = async (key, data) => {
  const db = await dbPromise
  // 🌟 核心修复：使用 JSON 的序列化与反序列化，把 Vue 的 Proxy 魔法外壳剥离，还原为纯净数组
  const pureData = JSON.parse(JSON.stringify(data))
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
// ====== 核心状态 ======


// ====== 基础状态 ======
const currentTab = ref('calculator')
const selectedTheme = ref('')
const myWardrobeIds = ref([])
const importText = ref('')
const fullWardrobeData = ref([])
const stagesData = ref([])
const isLoading = ref(true)

// ====== 账号与鉴权状态 ======
const currentUser = ref(null)
const userProfile = ref(null) // 🌟 唯一的用户画像中心

// 权限判定：不再看邮箱，直接看数据库给的 role
const isAdmin = computed(() => userProfile.value?.role === 'admin')
const userQuota = computed(() => userProfile.value?.quota || 0)

// ====== 🌟 增强功能状态 ======
// 🌟 新增：导入结果统计面板的状态
const importStats = reactive({ show: false, newCount: 0, dupCount: 0, failCount: 0 })
const searchQuery = ref('')
const isSelectMode = ref(false) 
const selectedIds = ref([]) 
const lastNotFoundNames = ref([]) 
const pendingList = ref([]) // 审核队列

const newClothes = reactive({
  pendingId: null,
  game_id: '', name: '', category: '连衣裙', stars: 5, tags: '',
  pair1: 'simple', grade1: 'S', pair2: 'cute', grade2: 'S',
  pair3: 'active', grade3: 'S', pair4: 'pure', grade4: 'S', pair5: 'cool', grade5: 'S'
})

// ====== 🌟 AI 图像识别模块状态 ======
const isRecognizing = ref(false)


// 1. 获取用户当前的 AI 额度 (建议在 onMounted 中也调用一次)
const fetchUserQuota = async () => {
  if (!currentUser.value) return
  // 去我们刚建的 user_quotas 表里拿数据
  const { data, error } = await supabase.from('user_quotas').select('free_count').single()
  if (data) userQuota.value = data.free_count
  if (error) console.error("额度获取失败:", error)
}

// 2. 核心：处理图片上传与 AI 调用
const onFileChange = async (e) => {
  const file = e.target.files[0]
  if (!file) return
  
  // 如果没登录，直接拦截（因为边缘函数需要鉴权扣费）
  if (!currentUser.value) {
    alert("请先登录账号，才能使用 AI 识别功能哦！")
    return
  }

  isRecognizing.value = true
  try {
    // A. 将图片转为 Base64（这是 AI 接收图片的标准格式）
    const reader = new FileReader()
    reader.readAsDataURL(file)
    reader.onload = async () => {
      const base64 = reader.result.split(',')[1]
      
      // B. 跨时空召唤：调用我们刚发布的 Supabase Edge Function
      const { data, error } = await supabase.functions.invoke('recognize-clothing', {
        body: { imageBase64: base64 }
      })

      if (error) {
        // 如果后端返回 403，通常是额度用光了
        throw new Error(error.message || "识别出了点小差错")
      }
      
      // C. 成功拿到名字！把 AI 识别到的名字塞进输入框
      // 通义千问返回的 names 已经是用逗号分隔好的了
      importText.value = data.names
      
      // D. 直接触发我们现成的 handleImport 函数，复用那套“解析报告”逻辑
      await handleImport()
      
      // E. 更新一下剩余额度显示
      await fetchUserQuota()
    }
  } catch (err) {
    alert('AI 罢工了：' + err.message)
  } finally {
    isRecognizing.value = false
    e.target.value = '' // 清空 input 方便下次连续识别
  }
}

// ====== 初始化 (加入极速本地缓存引擎) ======
onMounted(async () => {
  const userProfile = ref(null)
  const isAdmin = computed(() => userProfile.value?.role === 'admin')

  // 初始化时获取画像
  const fetchProfile = async () => {
    const { data } = await supabase.from('profiles').select('*').single()
    if (data) {
      userProfile.value = data
      userQuota.value = data.quota // 同步额度
    }
  }
  isLoading.value = true
  try {
    // 1. ⚡ 极速请求：只向云端索要衣服的“总数量”，不下载具体数据
    const { count: cloudClothesCount, error: countError } = await supabase
      .from('clothes')
      .select('*', { count: 'exact', head: true })
      
    if (countError) throw countError

    // 2. 💾 尝试从本地硬盘读取上次存下来的图鉴
    const localClothes = await getFromLocal('fullClothesData')
    const localStages = await getFromLocal('stagesData')

    // 3. 🧠 智能判断：如果本地有数据，且数量和云端一模一样，直接秒开！
    if (localClothes && localClothes.length === cloudClothesCount && localStages) {
      console.log('⚡ 触发本地缓存，瞬间加载完成！')
      fullWardrobeData.value = localClothes
      stagesData.value = localStages
    } else {
      // 4. 🐌 只有数量对不上（说明图鉴更新了），或者第一次打开，才去云端全量下载
      console.log('🔄 图鉴有更新或首次加载，正在从云端拉取...')
      const [clothesRes, stagesRes] = await Promise.all([
        supabase.from('clothes').select('*'),
        supabase.from('stages').select('*').order('id')
      ])
      if (clothesRes.error) throw clothesRes.error
      if (stagesRes.error) throw stagesRes.error

      fullWardrobeData.value = clothesRes.data || []
      stagesData.value = stagesRes.data || []
      
      // 下载完记得存进本地硬盘，下次就不用受苦了
      await saveToLocal('fullClothesData', fullWardrobeData.value)
      await saveToLocal('stagesData', stagesData.value)
    }

    if (stagesData.value.length > 0) selectedTheme.value = stagesData.value[0].name

    // ====== 账号登录与云端衣柜同步 ======
    const { data: { session } } = await supabase.auth.getSession()
    if (session) {
      currentUser.value = session.user
      await syncWardrobeFromCloud()
    }
    
    if (isAdmin.value) await fetchPendingList()

    supabase.auth.onAuthStateChange(async (event, session) => {
      currentUser.value = session?.user || null
      if (currentUser.value) {
        await syncWardrobeFromCloud()
        if (isAdmin.value) await fetchPendingList()
      } else {
        myWardrobeIds.value = []
        if (currentTab.value === 'admin') currentTab.value = 'calculator'
      }
    })
  } catch (err) { 
    alert('初始化失败，请检查网络或配置。') 
    console.error(err)
  } finally { 
    isLoading.value = false 
  }
})

// ====== 账号登录 / 注册 ======
const submitAuth = async () => {
  if (!authForm.email || !authForm.password) return alert('请输入邮箱和密码！')
  if (!isLoginMode.value && authForm.password !== authForm.confirmPassword) {
    return alert('❌ 两次输入的密码不一致，请重新检查！')
  }

  isLoading.value = true
  try {
    if (isLoginMode.value) {
      const { error } = await supabase.auth.signInWithPassword({ email: authForm.email, password: authForm.password })
      if (error) throw error
      alert('登录成功！欢迎回来。')
    } else {
      const { error } = await supabase.auth.signUp({ email: authForm.email, password: authForm.password })
      if (error) throw error
      alert('注册成功！')
    }
    isAuthModalOpen.value = false
    authForm.password = ''; authForm.confirmPassword = '' 
  } catch (err) {
    alert(isLoginMode.value ? '登录失败：' + err.message : '注册失败：' + err.message)
  } finally {
    isLoading.value = false
  }
}

const handleLogout = async () => {
  await supabase.auth.signOut()
  alert('已成功登出！')
}

// ====== 云端同步 ======
const syncWardrobeFromCloud = async () => {
  if (!currentUser.value) return
  const { data } = await supabase.from('user_wardrobes').select('owned_clothes').eq('user_id', currentUser.value.id).single()
  if (data) myWardrobeIds.value = data.owned_clothes || []
}

const saveWardrobeToCloud = async () => {
  if (!currentUser.value) return
  const { data } = await supabase.from('user_wardrobes').select('id').eq('user_id', currentUser.value.id).single()
  if (data) await supabase.from('user_wardrobes').update({ owned_clothes: myWardrobeIds.value }).eq('id', data.id)
  else await supabase.from('user_wardrobes').insert([{ user_id: currentUser.value.id, owned_clothes: myWardrobeIds.value }])
}

// ====== UGC 审核体系 ======
const submitRequest = async (name) => {
  try {
    const { error } = await supabase.from('pending_clothes').insert([{ name: name }])
    if (error) throw error
    alert(`【${name}】的添加申请已发送给站长！`)
    lastNotFoundNames.value = lastNotFoundNames.value.filter(n => n !== name)
  } catch (err) { alert('提交申请失败：' + err.message) }
}

const fetchPendingList = async () => {
  const { data } = await supabase.from('pending_clothes').select('*').order('id', { ascending: false })
  pendingList.value = data || []
}

const handlePendingItem = (item) => {
  newClothes.name = item.name
  newClothes.pendingId = item.id 
}

const rejectPendingItem = async (id) => {
  if (confirm('确定要驳回并删除这条申请吗？')) {
    await supabase.from('pending_clothes').delete().eq('id', id)
    pendingList.value = pendingList.value.filter(item => item.id !== id)
  }
}

// ====== 管理员录入 ======
// ====== 管理员录入 (包含严格查重机制) ======
const submitNewClothes = async () => {
  if (!newClothes.name) return alert('名字必须要填哦！')

  // 🌟 核心防重逻辑：在提交前，扫描整个图鉴库是否已有同名服装
  // 🌟 升级版核心防重逻辑：同时比对【名字】和【部位】
  const isDuplicate = fullWardrobeData.value.some(
    item => item.name === newClothes.name && item.category === newClothes.category
  )
  
  if (isDuplicate) {
    return alert(`❌ 录入中断：图鉴中已经存在名为【${newClothes.name}】的 [${newClothes.category}]，请勿重复添加！`)
  }

  let mul = 0.2
  if (newClothes.category === '连衣裙') mul = 4.0
  else if (newClothes.category.includes('装') || newClothes.category === '上衣') mul = 2.0
  else if (['发型', '外套', '鞋子', '袜子', '妆容', '萤光之灵'].includes(newClothes.category)) mul = 1.0

  const baseScores = { SS: 2500, S: 2000, A: 1500, B: 1000, C: 500, F: 0 }
  const calculatedScores = { simple: 0, gorgeous: 0, cute: 0, mature: 0, active: 0, elegant: 0, pure: 0, sexy: 0, cool: 0, warm: 0 }
  calculatedScores[newClothes.pair1] = baseScores[newClothes.grade1] * mul
  calculatedScores[newClothes.pair2] = baseScores[newClothes.grade2] * mul
  calculatedScores[newClothes.pair3] = baseScores[newClothes.grade3] * mul
  calculatedScores[newClothes.pair4] = baseScores[newClothes.grade4] * mul
  calculatedScores[newClothes.pair5] = baseScores[newClothes.grade5] * mul

  const parsedTags = newClothes.tags.split(/[,，\s]+/).map(t => t.trim()).filter(t => t !== '')
  const uniqueId = `custom_${Date.now()}`

  const payload = {
    id: uniqueId, game_id: newClothes.game_id || '新', name: newClothes.name,
    category: newClothes.category, stars: Number(newClothes.stars), scores: calculatedScores, tags: parsedTags
  }

  try {
    const { error } = await supabase.from('clothes').insert([payload])
    if (error) throw error
    fullWardrobeData.value.push(payload)
    
    if (newClothes.pendingId) {
      await supabase.from('pending_clothes').delete().eq('id', newClothes.pendingId)
      pendingList.value = pendingList.value.filter(item => item.id !== newClothes.pendingId)
    }

    alert(`🎉 新衣服【${newClothes.name}】已全网同步！`)
    newClothes.name = ''; newClothes.game_id = ''; newClothes.tags = ''; newClothes.pendingId = null
  } catch (err) { alert('上传失败：' + err.message) }
}

// ====== 衣柜导入与管理 ======
const handleImport = async () => {
  // 把输入框里的文本切成数组，并去除空白
  const inputNames = importText.value.split(/[,，\s\n]+/).map(n => n.trim()).filter(n => n !== '')
  if (inputNames.length === 0) return alert('请输入名字')

  let newCount = 0
  let dupCount = 0
  const notFound = []

  // 🌟 逐一核对衣服状态
  inputNames.forEach(name => {
    const found = fullWardrobeData.value.find(item => item.name === name)
    if (found) {
      // 检查是否已经拥有
      if (myWardrobeIds.value.includes(found.id)) {
        dupCount++ // 拥有的标记为重复
      } else {
        myWardrobeIds.value.push(found.id)
        newCount++ // 没拥有的标记为新增
      }
    } else {
      notFound.push(name) // 图鉴里没有的
    }
  })

  // 更新未找到列表（顺便去个重，防止用户输入了两个一样的错别字）
  lastNotFoundNames.value = [...new Set(notFound)] 
  
  // 只有真的加入了新衣服，才往云端同步，节省服务器性能
  if (newCount > 0 && currentUser.value) {
    await saveWardrobeToCloud()
  }

  // 🌟 更新并显示统计面板
  importStats.newCount = newCount
  importStats.dupCount = dupCount
  importStats.failCount = notFound.length
  importStats.show = true

  // 清空输入框
  importText.value = ''
}

const groupedOwnedClothes = computed(() => {
  const groups = {}
  const wardrobeSet = new Set(myWardrobeIds.value)
  const searchStr = searchQuery.value.trim()
  
  // 这里的查找复杂度从 O(M*N) 骤降为 O(N)
  const filtered = fullWardrobeData.value.filter(c => wardrobeSet.has(c.id) && c.name.includes(searchStr))
  filtered.forEach(item => { if (!groups[item.category]) groups[item.category] = []; groups[item.category].push(item) })
  return groups
})

const confirmRemove = async (item) => {
  if (confirm(`移除【${item.name}】吗？`)) {
    myWardrobeIds.value = myWardrobeIds.value.filter(id => id !== item.id)
    if (currentUser.value) await saveWardrobeToCloud()
  }
}

const batchDelete = async () => {
  if (selectedIds.value.length === 0) return
  if (confirm(`确认移除选中的 ${selectedIds.value.length} 件？`)) {
    myWardrobeIds.value = myWardrobeIds.value.filter(id => !selectedIds.value.includes(id))
    selectedIds.value = []; isSelectMode.value = false
    if (currentUser.value) await saveWardrobeToCloud()
  }
}

// ====== 🌟 终极搭配计算引擎 ======
const outfitResult = computed(() => {
  if (isLoading.value || fullWardrobeData.value.length === 0 || stagesData.value.length === 0) {
    return { items: [], totalScore: 0, penaltyRate: 100, accCount: 0 }
  }

  const currentStage = stagesData.value.find(s => s.name === selectedTheme.value)
  if (!currentStage || !currentStage.weights) return { items: [], totalScore: 0, penaltyRate: 100, accCount: 0 }
  
  const themeWeights = currentStage.weights

  // 🌟 算法优化：将数组转为 Set，底层使用哈希映射，实现 O(1) 极速查找
  const wardrobeSet = new Set(myWardrobeIds.value)
  const availableClothes = wardrobeSet.size > 0 
    ? fullWardrobeData.value.filter(c => wardrobeSet.has(c.id))
    : fullWardrobeData.value

  const scoredClothes = availableClothes.map(clothes => {
    let score = 0
    const s = clothes.scores || {}
    score += (s.simple || 0) * (themeWeights.simple || 0)
    score += (s.gorgeous || 0) * (themeWeights.gorgeous || 0)
    score += (s.cute || 0) * (themeWeights.cute || 0)
    score += (s.mature || 0) * (themeWeights.mature || 0)
    score += (s.active || 0) * (themeWeights.active || 0)
    score += (s.elegant || 0) * (themeWeights.elegant || 0)
    score += (s.pure || 0) * (themeWeights.pure || 0)
    score += (s.sexy || 0) * (themeWeights.sexy || 0)
    score += (s.cool || 0) * (themeWeights.cool || 0)
    score += (s.warm || 0) * (themeWeights.warm || 0)
    return { ...clothes, finalScore: Math.round(score) }
  })

  const bestPerCategory = new Map()
  scoredClothes.forEach(item => {
    const existing = bestPerCategory.get(item.category)
    if (!existing || existing.finalScore < item.finalScore) {
      bestPerCategory.set(item.category, item)
    }
  })

  const dress = bestPerCategory.get('连衣裙')
  const top = bestPerCategory.get('上衣') || bestPerCategory.get('上装') 
  const bottom = bestPerCategory.get('下装')
  const dressScore = dress ? dress.finalScore : 0
  const topBottomScore = (top ? top.finalScore : 0) + (bottom ? bottom.finalScore : 0)

  if (dressScore > topBottomScore) {
    if (top) bestPerCategory.delete(top.category)
    if (bottom) bestPerCategory.delete(bottom.category)
  } else {
    if (dress) bestPerCategory.delete('连衣裙')
  }

  const baseItems = []
  const accItems = []
  bestPerCategory.forEach(item => {
    if (item.category.includes('饰品')) accItems.push(item)
    else baseItems.push(item)
  })

  accItems.sort((a, b) => b.finalScore - a.finalScore)
  const selectedAccs = []
  let maxAccTotal = 0
  let currentPenalty = 1.0

  for (let i = 0; i < accItems.length; i++) {
    const item = accItems[i]
    const nextCount = selectedAccs.length + 1
    const nextPenalty = nextCount <= 3 ? 1.0 : Math.max(0.2, 1.0 - (nextCount - 3) * 0.05)
    const sumWithoutPenalty = selectedAccs.reduce((sum, a) => sum + a.finalScore, 0) + item.finalScore
    const nextAccTotal = sumWithoutPenalty * nextPenalty

    if (nextAccTotal > maxAccTotal || nextCount <= 3) {
      selectedAccs.push({ ...item, isAcc: true })
      maxAccTotal = nextAccTotal
      currentPenalty = nextPenalty
    } else { break }
  }

  baseItems.sort((a, b) => b.finalScore - a.finalScore)
  return {
    items: [...baseItems, ...selectedAccs],
    totalScore: Math.round(baseItems.reduce((sum, item) => sum + item.finalScore, 0) + maxAccTotal),
    penaltyRate: Math.round(currentPenalty * 100),
    accCount: selectedAccs.length
  }
})
</script>

<template>
  <div class="app-container">
    <div class="auth-bar">
      <div v-if="currentUser" class="user-info">
        <span>👋 {{ currentUser.email }}</span>
        <button class="btn-tiny btn-logout" @click="handleLogout">登出</button>
      </div>
      <button v-else class="btn-login" @click="isAuthModalOpen = true">🛡️ 登录开启云端同步</button>
    </div>

    <div v-if="isAuthModalOpen" class="modal-overlay" @click.self="isAuthModalOpen = false">
      <div class="modal-content">
        <h2>{{ isLoginMode ? '账号登录' : '注册新账号' }}</h2>
        <input type="email" v-model="authForm.email" placeholder="输入您的邮箱" />
        <input type="password" v-model="authForm.password" placeholder="输入密码 (至少6位)" @keyup.enter="isLoginMode ? submitAuth() : null" />
        <input v-if="!isLoginMode" type="password" v-model="authForm.confirmPassword" placeholder="请再次输入密码确认" @keyup.enter="submitAuth" />
        <button class="btn-primary" @click="submitAuth">{{ isLoginMode ? '立刻登录' : '确认注册' }}</button>
        <p class="toggle-mode" @click="isLoginMode = !isLoginMode">{{ isLoginMode ? '没有账号？点击注册' : '已有账号？返回登录' }}</p>
      </div>
    </div>

    <header>
      <h1>✨ 奇迹暖暖极速搭配器 ✨</h1>
      <div class="tabs">
        <button :class="{ active: currentTab === 'calculator' }" @click="currentTab = 'calculator'">搭配计算</button>
        <button :class="{ active: currentTab === 'import' }" @click="currentTab = 'import'">拥有的衣服</button>
        <button v-if="isAdmin" :class="{ active: currentTab === 'admin' }" @click="currentTab = 'admin'" class="admin-tab-btn">图鉴管理</button>
      </div>
    </header>

    <div v-if="isLoading" class="loading-state"><h2>⏳ 处理中...</h2></div>

    <main v-else-if="currentTab === 'calculator'">
      <div class="control-panel">
        <label>选择竞技场主题：</label>
        <select v-model="selectedTheme">
          <option v-for="stage in stagesData" :key="stage.id" :value="stage.name">{{ stage.name }}</option>
        </select>
      </div>

      <div class="result-panel">
        <div class="score-board">
          <div class="score-item">
            <span class="label">预计极限总分</span>
            <span class="huge-score">{{ outfitResult.totalScore }}</span>
          </div>
          <div class="score-item acc-info">
            <span class="label">佩戴饰品数 / 系数</span>
            <span class="value">{{ outfitResult.accCount }}件 / {{ outfitResult.penaltyRate }}%</span>
          </div>
        </div>
        <div class="item-list">
          <div class="item-card" v-for="item in outfitResult.items" :key="item.id">
            <div class="item-category" :class="{'is-acc': item.isAcc}">{{ item.category }}</div>
            <div class="item-info">
              <span class="item-name">{{ item.name }}</span>
              <span class="item-score">{{ item.finalScore }}</span>
            </div>
          </div>
        </div>
      </div>
    </main>

    <main v-else-if="currentTab === 'import'">
      <div class="import-panel">
        <h2>📥 批量录入新衣服</h2>
        <div class="ai-recognition-zone">
        <div class="ai-header">
          <div class="quota-info">
            ✨ 剩余 AI 识别次数：<strong :class="{ 'low-quota': userQuota < 5 }">{{ userQuota }}</strong> 次
          </div>
          <p class="ai-tip">提示：上传衣柜截图，AI 自动帮你录入</p>
        </div>
        
        <label class="ai-upload-btn" :class="{ 'is-loading': isRecognizing }">
          <span v-if="!isRecognizing">📸 截图一键识别导入</span>
          <span v-else>🔍 正在通过 AI 扫视衣柜...</span>
          <input 
            type="file" 
            accept="image/*" 
            @change="onFileChange" 
            :disabled="isRecognizing" 
            hidden 
          />
        </label>
      </div>
        <textarea v-model="importText" rows="3" placeholder="输入服装名字(如: 默认粉毛, 运动少年)..."></textarea>
        <button class="btn-primary" @click="handleImport">解析并保存到云端</button>
        <div v-if="importStats.show" class="import-stats-box">
          <h3>📊 解析报告</h3>
          <ul class="stats-list">
            <li class="stat-new">✅ 成功录入新服装：<strong>{{ importStats.newCount }}</strong> 件</li>
            <li class="stat-dup">🔁 已拥有并自动跳过：<strong>{{ importStats.dupCount }}</strong> 件</li>
            <li class="stat-fail">❌ 图鉴未找到：<strong>{{ importStats.failCount }}</strong> 件</li>
          </ul>
          <button @click="importStats.show = false" class="btn-clear-alert">关闭报告</button>
        </div>

        <div v-if="lastNotFoundNames.length > 0" class="not-found-alert">
          <p>😢 下列衣服图鉴中暂时没有，点击可提交添加申请：</p>
          <div class="not-found-tags">
            <div v-for="name in lastNotFoundNames" :key="name" class="missing-tag">
              {{ name }}
              <button @click="submitRequest(name)" class="btn-quick-add">申请添加</button>
            </div>
          </div>
        </div>
      </div>

      <div class="wardrobe-gallery">
        <div class="gallery-header">
          <h2>👗 我的衣柜 ({{ myWardrobeIds.length }} 件)</h2>
          <div class="gallery-controls">
            <input type="text" v-model="searchQuery" placeholder="🔍 搜索..." class="search-box" />
            <button @click="isSelectMode = !isSelectMode" :class="{ 'btn-active-mode': isSelectMode }">
              {{ isSelectMode ? '取消选择' : '批量管理' }}
            </button>
            <button v-if="isSelectMode" @click="batchDelete" class="btn-danger-action" :disabled="selectedIds.length === 0">
              永久移除({{ selectedIds.length }})
            </button>
          </div>
        </div>
        
        <div class="category-sections">
          <div v-for="(clothes, cat) in groupedOwnedClothes" :key="cat" class="cat-block">
            <h3 class="cat-title">{{ cat }} <span class="cat-count">({{ clothes.length }})</span></h3>
            <div class="tags-container">
              <div v-for="item in clothes" :key="item.id" class="clothes-tag" :class="{ 'is-selected': selectedIds.includes(item.id) }">
                <input v-if="isSelectMode" type="checkbox" :value="item.id" v-model="selectedIds" />
                <span class="tag-name" @click="isSelectMode ? null : confirmRemove(item)">{{ item.name }}</span>
                <button v-if="!isSelectMode" class="tag-remove" @click="confirmRemove(item)">×</button>
              </div>
            </div>
          </div>
          <div v-if="Object.keys(groupedOwnedClothes).length === 0" class="empty-tip">衣柜空空如也，或者没搜到结果~</div>
        </div>
      </div>
    </main>

    <main v-else-if="currentTab === 'admin'">
       <div class="admin-panel">
         <div class="review-queue" v-if="pendingList.length > 0">
            <h3>🔔 玩家提交的待审核申请 ({{ pendingList.length }})</h3>
            <div class="queue-list">
              <div v-for="item in pendingList" :key="item.id" class="queue-item">
                <span class="queue-name">{{ item.name }}</span>
                <div>
                  <button @click="handlePendingItem(item)" class="btn-tiny bg-blue">✍️ 完善属性</button>
                  <button @click="rejectPendingItem(item.id)" class="btn-tiny bg-red">驳回</button>
                </div>
              </div>
            </div>
         </div>

         <h2>👑 云端图鉴录入与补全</h2>
         <p v-if="newClothes.pendingId" class="processing-tip">正在处理玩家提交的申请：【{{ newClothes.name }}】</p>
         
         <div class="form-group">
           <input type="text" v-model="newClothes.game_id" placeholder="短编号" class="w-1/3" />
           <input type="text" v-model="newClothes.name" placeholder="服装名称(必填)" class="w-2/3" />
         </div>
         <div class="form-group">
          <select v-model="newClothes.category">
            <option>发型</option><option>连衣裙</option><option>外套</option><option>上装</option><option>下装</option>
            <option>袜子</option><option>鞋子</option><option>饰品·头饰</option><option>饰品·特殊</option><option>妆容</option>
          </select>
          <select v-model="newClothes.stars">
            <option value="1">1星</option><option value="2">2星</option><option value="3">3星</option>
            <option value="4">4星</option><option value="5">5星</option><option value="6">6星</option>
          </select>
         </div>
         <div class="form-group">
            <input type="text" v-model="newClothes.tags" placeholder="特殊标签 (童话系, 洛丽塔)" style="width: 100%;" />
         </div>
         <div class="attr-grid">
          <div class="attr-row" v-for="(pair, idx) in [
            {p: 'pair1', g: 'grade1', v1: 'simple', l1: '简约', v2: 'gorgeous', l2: '华丽'},
            {p: 'pair2', g: 'grade2', v1: 'cute', l1: '可爱', v2: 'mature', l2: '成熟'},
            {p: 'pair3', g: 'grade3', v1: 'active', l1: '活泼', v2: 'elegant', l2: '优雅'},
            {p: 'pair4', g: 'grade4', v1: 'pure', l1: '清纯', v2: 'sexy', l2: '性感'},
            {p: 'pair5', g: 'grade5', v1: 'cool', l1: '清凉', v2: 'warm', l2: '保暖'}
          ]" :key="idx">
            <select v-model="newClothes[pair.p]">
              <option :value="pair.v1">{{pair.l1}}</option><option :value="pair.v2">{{pair.l2}}</option>
            </select>
            <select v-model="newClothes[pair.g]" class="grade-sel">
              <option value="SS">完美+</option><option value="S">完美</option><option value="A">优秀</option><option value="B">不错</option><option value="C">一般</option><option value="F">无</option>
            </select>
          </div>
         </div>
         <button class="btn-primary admin-submit" @click="submitNewClothes">🚀 {{ newClothes.pendingId ? '通过审核并入库' : '提交并同步云端图鉴' }}</button>
       </div>
    </main>
  </div>
</template>

<style scoped>
/* ====== 完整样式库，没有任何省略 ====== */
.app-container { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 650px; margin: 0 auto; padding: 20px; background: #fafafa; min-height: 100vh; position: relative;}
h1 { color: #f472b6; text-align: center; margin-bottom: 30px;}
.tabs { display: flex; gap: 10px; margin-bottom: 25px; justify-content: center; }
button { padding: 10px 15px; border: none; background: #e5e7eb; cursor: pointer; border-radius: 8px; font-weight: bold; transition: all 0.2s;}
button.active { background: #f472b6; color: white; box-shadow: 0 4px 6px rgba(244, 114, 182, 0.3);}
.admin-tab-btn { background: #8b5cf6; color: white; }
.admin-tab-btn.active { background: #7c3aed; box-shadow: 0 4px 6px rgba(124, 58, 237, 0.3); }

.btn-primary { background: #f472b6; color: white; margin-top: 15px; width: 100%; padding: 12px; font-size: 16px;}
.control-panel, .result-panel, .import-panel { background: #fff; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); margin-bottom: 20px; }
select { padding: 10px; font-size: 16px; width: 100%; margin-top: 10px; border: 1px solid #ddd; border-radius: 6px;}
.score-board { display: flex; justify-content: space-between; align-items: center; background: #fff5f8; padding: 15px 20px; border-radius: 10px; margin-bottom: 20px; border-left: 5px solid #f472b6;}
.score-item { display: flex; flex-direction: column; }
.acc-info { align-items: flex-end; font-size: 14px;}
.label { color: #6b7280; margin-bottom: 5px; font-size: 12px; text-transform: uppercase;}
.huge-score { font-size: 28px; font-weight: 900; color: #f472b6; }
.value { font-weight: bold; color: #374151;}
.item-list { display: flex; flex-direction: column; gap: 8px; }
.item-card { display: flex; justify-content: space-between; align-items: center; padding: 12px 15px; background: #f9fafb; border-radius: 8px; border: 1px solid #f3f4f6;}
.item-category { color: #4b5563; font-weight: 600; font-size: 13px; width: 70px;}
.item-category.is-acc { color: #8b5cf6; } 
.item-name { font-weight: bold; margin-right: 20px; color: #1f2937; flex-grow: 1;}
.item-score { color: #f472b6; font-weight: bold; font-family: monospace; font-size: 15px;}
textarea { width: 100%; padding: 15px; box-sizing: border-box; border: 1px solid #ddd; border-radius: 8px; font-family: monospace; resize: vertical;}
.loading-state { text-align: center; padding: 50px; background: white; border-radius: 12px; color: #f472b6;}

/* 账号模块 */
.auth-bar { display: flex; justify-content: flex-end; padding-bottom: 10px; border-bottom: 1px dashed #ddd; margin-bottom: 20px;}
.user-info { font-size: 14px; color: #4b5563; display: flex; align-items: center; gap: 10px;}
.btn-login { background: white; color: #3b82f6; border: 1px solid #3b82f6; padding: 5px 15px; font-size: 13px; border-radius: 20px;}
.btn-login:hover { background: #eff6ff; }
.btn-logout { background: #fee2e2; color: #ef4444; border-radius: 4px; padding: 3px 8px;}
.btn-tiny { font-size: 12px; cursor: pointer; border: none;}

/* 弹窗样式 */
.modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); display: flex; justify-content: center; align-items: center; z-index: 1000;}
.modal-content { background: white; padding: 30px; border-radius: 12px; width: 90%; max-width: 350px; box-shadow: 0 10px 25px rgba(0,0,0,0.2);}
.modal-content h2 { text-align: center; color: #374151; margin-top: 0; margin-bottom: 20px;}
.modal-content input { width: 100%; padding: 12px; margin-bottom: 15px; border: 1px solid #d1d5db; border-radius: 6px; box-sizing: border-box; font-size: 15px;}
.toggle-mode { text-align: center; color: #3b82f6; font-size: 13px; margin-top: 15px; cursor: pointer;}
.toggle-mode:hover { text-decoration: underline; }

/* 图鉴展示与管理 */
.wardrobe-gallery { background: #fff; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }
.gallery-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; flex-wrap: wrap; gap: 10px;}
.gallery-header h2 { margin: 0; color: #374151;}
.search-box { padding: 8px 15px; border: 1px solid #ddd; border-radius: 20px; outline: none; width: 180px; font-size: 14px;}
.search-box:focus { border-color: #f472b6; box-shadow: 0 0 0 2px rgba(244,114,182,0.2);}

.gallery-controls { display: flex; gap: 8px; align-items: center; }
.btn-active-mode { background: #3b82f6 !important; color: white !important; }
.btn-danger-action { background: #ef4444; color: white; padding: 8px 12px; border-radius: 8px; border: none; cursor: pointer; font-weight: bold; }
.btn-danger-action:disabled { background: #fecaca; cursor: not-allowed; }

.cat-block { margin-bottom: 25px; }
.cat-title { border-bottom: 2px solid #f472b6; padding-bottom: 5px; color: #db2777; font-size: 16px; margin-bottom: 12px; display: flex; align-items: center; gap: 8px;}
.cat-count { font-size: 12px; color: #9ca3af; font-weight: normal; }

.tags-container { display: flex; flex-wrap: wrap; gap: 10px; }
.clothes-tag { cursor: pointer; user-select: none; display: flex; align-items: center; gap: 6px; background: #fdf2f8; border: 1px solid #fbcfe8; padding: 6px 12px; border-radius: 20px; font-size: 13px; transition: all 0.2s;}
.clothes-tag:hover { box-shadow: 0 2px 5px rgba(244,114,182,0.2); transform: translateY(-1px);}
.clothes-tag.is-selected { background: #dbeafe; border-color: #3b82f6; }
.clothes-tag input[type="checkbox"] { cursor: pointer; }
.tag-name { color: #1f2937; }
.tag-remove { background: none; border: none; color: #9ca3af; font-size: 16px; cursor: pointer; padding: 0 2px; line-height: 1;}
.tag-remove:hover { color: #ef4444; }
.empty-tip { width: 100%; text-align: center; color: #9ca3af; padding: 30px 0; font-style: italic;}

/* UGC审核相关 */
.not-found-alert { background: #fffbeb; border: 1px solid #fde68a; padding: 15px; border-radius: 8px; margin-top: 15px; }
.not-found-tags { display: flex; flex-wrap: wrap; gap: 8px; margin: 10px 0; }
.missing-tag { background: #fef3c7; color: #92400e; padding: 4px 10px; border-radius: 4px; font-size: 13px; display: flex; align-items: center; gap: 5px;}
.btn-quick-add { background: #7c3aed; color: white; border: none; padding: 2px 6px; border-radius: 4px; font-size: 11px; cursor: pointer; }

.review-queue { background: #fff; padding: 15px; border-radius: 8px; margin-bottom: 20px; border: 1px dashed #3b82f6;}
.review-queue h3 { margin-top: 0; color: #1e3a8a; font-size: 15px;}
.queue-list { display: flex; flex-direction: column; gap: 8px; max-height: 150px; overflow-y: auto;}
.queue-item { display: flex; justify-content: space-between; align-items: center; background: #eff6ff; padding: 8px 12px; border-radius: 6px; font-size: 14px;}
.queue-name { font-weight: bold; color: #1e40af;}
.bg-blue { background: #3b82f6; color: white; margin-right: 5px;}
.bg-red { background: #ef4444; color: white;}
.processing-tip { color: #d97706; font-weight: bold; background: #fef3c7; padding: 5px 10px; border-radius: 4px; display: inline-block; margin-bottom: 15px;}

/* 管理员面板 */
.admin-panel { background: #f5f3ff; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); border: 1px solid #ddd6fe;}
.admin-panel h2 { color: #7c3aed; margin-top: 0;}
.form-group { display: flex; gap: 10px; margin-bottom: 10px; }
.form-group input, .form-group select { padding: 10px; border: 1px solid #c4b5fd; border-radius: 6px; box-sizing: border-box;}
.w-1\/3 { width: 33%; } .w-2\/3 { width: 67%; }
.attr-grid { display: flex; flex-direction: column; gap: 10px; background: white; padding: 15px; border-radius: 8px; border: 1px dashed #c4b5fd; margin-bottom: 15px;}
.attr-row { display: flex; gap: 10px; align-items: center;}
.grade-sel { width: 90px; font-weight: bold; color: #f472b6;}
.admin-submit { background: #7c3aed; font-size: 18px; font-weight: bold;}
/* 导入报告面板样式 */
.import-stats-box { background: #f8fafc; border: 1px solid #e2e8f0; padding: 15px; border-radius: 8px; margin-top: 15px; }
.import-stats-box h3 { margin: 0 0 10px 0; font-size: 15px; color: #334155; }
.stats-list { list-style: none; padding: 0; margin: 0 0 12px 0; font-size: 14px; }
.stats-list li { margin-bottom: 6px; }
.stat-new { color: #10b981; }
.stat-dup { color: #64748b; }
.stat-fail { color: #ef4444; }
/* AI 识别区专属样式 */
.ai-recognition-zone {
  background: linear-gradient(135deg, #fdf2f8 0%, #f5f3ff 100%);
  border: 2px dashed #ddd6fe;
  padding: 20px;
  border-radius: 12px;
  margin-bottom: 20px;
  text-align: center;
}
.ai-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
.quota-info { font-size: 14px; color: #6d28d9; font-weight: bold; }
.low-quota { color: #ef4444; }
.ai-tip { font-size: 12px; color: #9ca3af; margin: 0; }

.ai-upload-btn {
  display: block;
  background: #7c3aed;
  color: white;
  padding: 12px;
  border-radius: 10px;
  font-weight: bold;
  cursor: pointer;
  transition: all 0.3s;
  box-shadow: 0 4px 12px rgba(124, 58, 237, 0.2);
}
.ai-upload-btn:hover { background: #6d28d9; transform: translateY(-2px); }
.ai-upload-btn.is-loading { background: #a78bfa; cursor: not-allowed; }

/* 响应式调整 */
@media (max-width: 480px) {
  .ai-header { flex-direction: column; gap: 8px; }
}
</style>