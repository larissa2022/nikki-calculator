<script setup>
import { ref, reactive, onMounted, computed, watch } from 'vue'
import { useWardrobe } from '../composables/useWardrobe'
import MissingItemsQueue from './MissingItemsQueue.vue'
import { supabase, logErrorToCloud } from '../api/supabase'
import { suitService } from '../api/suitService'
import { getBroadCategory } from '../composables/useScoreEngine'

const props = defineProps({
  wardrobe: { type: Array, required: true },
  ownedIds: { type: Array, required: true },
  isLoggedIn: { type: Boolean, default: false }
})

const emit = defineEmits(['update:ownedIds', 'save-cloud', 'refresh-profile'])
const { saveWardrobeToCloud } = useWardrobe()

const importMode = ref('name')
const importText = ref('')
const codeImportCategory = ref('连衣裙')
const codeImportText = ref('')
const importStats = reactive({ show: false, newCount: 0, dupCount: 0, failCount: 0, newClothes: [], missingCodes: [], conflictCodes: [] })

// 🌟 核心：消消乐视窗逻辑，永远只展示前 3 个
const lastNotFoundNames = ref([])
const isSaving = ref(false)
const availableSuits = ref([])
const IMPORT_DRAFT_KEY = 'nikki.importZoneDraft.v1'
const DRAFT_TTL_MS = 24 * 60 * 60 * 1000
const PROCESS_BATCH_SIZE = 500
const CLOUD_REQUEST_TIMEOUT_MS = 15000
const IMPORT_TASK_TIMEOUT_MS = 20000
const CODE_IMPORT_CATEGORIES = ['发型', '连衣裙', '外套', '上装', '下装', '袜子', '鞋子', '饰品', '妆容', '萤光之灵']

const yieldToBrowser = () => new Promise(resolve => setTimeout(resolve, 0))

const withTimeout = (promise, timeoutMs, message) => Promise.race([
  promise,
  new Promise((_, reject) => {
    setTimeout(() => reject(new Error(message)), timeoutMs)
  })
])

const readImportDraft = () => {
  try {
    const raw = localStorage.getItem(IMPORT_DRAFT_KEY)
    if (!raw) return null
    const draft = JSON.parse(raw)
    if (!draft?.updatedAt || Date.now() - draft.updatedAt > DRAFT_TTL_MS) {
      localStorage.removeItem(IMPORT_DRAFT_KEY)
      return null
    }
    return draft
  } catch (err) {
    console.warn('读取录入草稿失败:', err)
    return null
  }
}

const saveImportDraft = () => {
  try {
    localStorage.setItem(IMPORT_DRAFT_KEY, JSON.stringify({
      importMode: importMode.value,
      importText: importText.value,
      codeImportCategory: codeImportCategory.value,
      codeImportText: codeImportText.value,
      lastNotFoundNames: lastNotFoundNames.value,
      importStats: JSON.parse(JSON.stringify(importStats)),
      updatedAt: Date.now()
    }))
  } catch (err) {
    console.warn('保存录入草稿失败:', err)
  }
}

const normalizeCodeImportCategory = (category) => {
  const broadCategory = getBroadCategory(category)
  return CODE_IMPORT_CATEGORIES.includes(broadCategory) ? broadCategory : '连衣裙'
}

const restoreImportDraft = () => {
  const draft = readImportDraft()
  if (!draft) return
  importMode.value = draft.importMode === 'code' ? 'code' : 'name'
  importText.value = draft.importText || ''
  codeImportCategory.value = normalizeCodeImportCategory(draft.codeImportCategory || '连衣裙')
  codeImportText.value = draft.codeImportText || ''
  lastNotFoundNames.value = Array.isArray(draft.lastNotFoundNames) ? draft.lastNotFoundNames : []
  if (draft.importStats) {
    Object.assign(importStats, {
      show: !!draft.importStats.show,
      newCount: Number(draft.importStats.newCount) || 0,
      dupCount: Number(draft.importStats.dupCount) || 0,
      failCount: Number(draft.importStats.failCount) || lastNotFoundNames.value.length,
      newClothes: Array.isArray(draft.importStats.newClothes) ? draft.importStats.newClothes : [],
      missingCodes: Array.isArray(draft.importStats.missingCodes) ? draft.importStats.missingCodes : [],
      conflictCodes: Array.isArray(draft.importStats.conflictCodes) ? draft.importStats.conflictCodes : []
    })
  }
}

onMounted(async () => {
  restoreImportDraft()
  try { availableSuits.value = await suitService.getAllSuits(); } catch (err) { console.error('加载失败', err); }
})

watch(
  () => ({
    importMode: importMode.value,
    importText: importText.value,
    codeImportCategory: codeImportCategory.value,
    codeImportText: codeImportText.value,
    lastNotFoundNames: lastNotFoundNames.value,
    importStats: { ...importStats }
  }),
  saveImportDraft,
  { deep: true }
)

watch(lastNotFoundNames, (names) => {
  importStats.failCount = names.length + importStats.missingCodes.length + importStats.conflictCodes.length
})

const parseImportTokens = (value) => value
  .split(/[,，、;；\s\n]+/)
  .map(n => n.trim())
  .filter(Boolean)

const normalizeGameId = (value) => {
  const digits = String(value || '').replace(/\D/g, '')
  return digits.replace(/^0+(?=\d)/, '') || digits
}

const missingCodeContributionNames = computed({
  get() {
    return importStats.missingCodes.map(item => `${item.category} #${item.game_id}`)
  },
  set(names) {
    const keep = new Set(names)
    importStats.missingCodes = importStats.missingCodes.filter(item => (
      keep.has(`${item.category} #${item.game_id}`)
    ))
    importStats.failCount = lastNotFoundNames.value.length + importStats.missingCodes.length + importStats.conflictCodes.length
  }
})

const missingCodeContributionPrefills = computed(() => Object.fromEntries(
  importStats.missingCodes.map(item => [
    `${item.category} #${item.game_id}`,
    { name: '', category: item.category, game_id: item.game_id }
  ])
))

const saveImportedWardrobe = async (updatedOwnedIds) => {
  if (!props.isLoggedIn) {
    emit('update:ownedIds', updatedOwnedIds)
    return updatedOwnedIds
  }

  const { data: { user }, error: authErr } = await withTimeout(
    supabase.auth.getUser(),
    CLOUD_REQUEST_TIMEOUT_MS,
    '登录状态校验超时，请刷新页面后重试。'
  )
  if (authErr || !user) throw new Error('登录状态已过期，请刷新页面重新登录！')

  const savedOwnedIds = await withTimeout(
    saveWardrobeToCloud(user.id, updatedOwnedIds, { mode: 'merge' }),
    CLOUD_REQUEST_TIMEOUT_MS,
    '云端衣柜同步超时。本次输入已自动保存在本地草稿，请刷新后重试。'
  )
  emit('update:ownedIds', savedOwnedIds)
  return savedOwnedIds
}

const reportImportError = async (err) => {
  if (typeof logErrorToCloud !== 'function') return

  try {
    const { data: { session } } = await withTimeout(
      supabase.auth.getSession(),
      3000,
      '日志上报会话读取超时'
    )
    await withTimeout(
      logErrorToCloud('import_wardrobe_mobile', err, session?.user?.id),
      3000,
      '日志上报超时'
    )
  } catch (logErr) {
    console.warn('录入错误日志上报跳过:', logErr.message)
  }
}

const runImportTask = async (task) => {
  // 1. 开启界面锁
  isSaving.value = true;
  
  // 🌟 核心优化 1：强制让出主线程，确保“正在同步”的动画能被浏览器立刻画出来，不假死！
  await new Promise(resolve => setTimeout(resolve, 50));

  try {
    await withTimeout(
      task(),
      IMPORT_TASK_TIMEOUT_MS,
      '录入处理超时。本次输入已自动保存在本地草稿，请刷新后重试。'
    )
  } catch (err) {
    isSaving.value = false
    alert('❌ 录入中断：\n' + (err.message || '网络请求异常，请检查网络后重试'));
    void reportImportError(err)
  } finally {
    isSaving.value = false;
  }
}

const handleNameImport = async () => {
  const inputNames = parseImportTokens(importText.value)
  if (inputNames.length === 0) return alert('请输入衣服名称')

  await runImportTask(async () => {
    let newCount = 0, dupCount = 0
    const notFound = [], newlyAdded = []

    // 🌟 核心优化 2：建立哈希表 (Map)，把几万件衣服的查询时间从 O(N) 降为 O(1)
    const wardrobeMap = new Map(props.wardrobe.map(item => [item.name, item]))
    // 🌟 核心优化 3：建立集合 (Set)，把是否拥有的查重时间从 O(N) 降为 O(1)
    const ownedSet = new Set(props.ownedIds);

    // 开始极速匹配；大量录入时分批让出主线程，避免页面假死
    for (let index = 0; index < inputNames.length; index++) {
      const name = inputNames[index]
      const found = wardrobeMap.get(name) // 瞬间拿结果，不需要 find 遍历
      
      if (found) {
        if (ownedSet.has(found.id)) { // 瞬间判断，不需要 includes 遍历
          dupCount++; 
        } else { 
          ownedSet.add(found.id); 
          newCount++; 
          newlyAdded.push(found); 
        }
      } else { 
        notFound.push(name); 
      }
      if ((index + 1) % PROCESS_BATCH_SIZE === 0) await yieldToBrowser()
    }

    // 重新转回纯净的数组，准备提交给云端
    const updatedOwnedIds = Array.from(ownedSet)
    lastNotFoundNames.value = [...new Set(notFound)]

    if (newCount > 0) {
      await saveImportedWardrobe(updatedOwnedIds)
    }
    
    // 渲染统计结果
    importStats.newCount = newCount; 
    importStats.dupCount = dupCount;
    importStats.missingCodes = []
    importStats.conflictCodes = []
    importStats.failCount = lastNotFoundNames.value.length
    importStats.newClothes = newlyAdded; 
    importStats.show = true; 
    importText.value = '';
  })
}

const handleCodeImport = async () => {
  const inputCodes = parseImportTokens(codeImportText.value)
    .map(code => code.replace(/\D/g, ''))
    .filter(Boolean)
  if (inputCodes.length === 0) return alert('请输入数字短编号')

  await runImportTask(async () => {
    let newCount = 0, dupCount = 0
    const notFound = [], conflicts = [], newlyAdded = []
    const selectedBroadCategory = codeImportCategory.value
    const ownedSet = new Set(props.ownedIds)
    const normalizedMap = new Map()
    const duplicateNormalizedKeys = new Set()

    props.wardrobe.forEach(item => {
      if (getBroadCategory(item.category) !== selectedBroadCategory || item.game_id == null) return
      const rawGameId = String(item.game_id).trim()
      const normalizedKey = `${selectedBroadCategory}::${normalizeGameId(rawGameId)}`

      if (normalizedMap.has(normalizedKey) && normalizedMap.get(normalizedKey).id !== item.id) {
        duplicateNormalizedKeys.add(normalizedKey)
      } else {
        normalizedMap.set(normalizedKey, item)
      }
    })

    for (let index = 0; index < inputCodes.length; index++) {
      const code = inputCodes[index]
      const normalizedCode = normalizeGameId(code)
      const normalizedKey = `${selectedBroadCategory}::${normalizedCode}`
      const found = duplicateNormalizedKeys.has(normalizedKey) ? null : normalizedMap.get(normalizedKey)

      if (duplicateNormalizedKeys.has(normalizedKey)) {
        conflicts.push({ category: selectedBroadCategory, game_id: code })
      } else if (found) {
        if (ownedSet.has(found.id)) {
          dupCount++
        } else {
          ownedSet.add(found.id)
          newCount++
          newlyAdded.push(found)
        }
      } else {
        notFound.push({ category: selectedBroadCategory, game_id: code })
      }

      if ((index + 1) % PROCESS_BATCH_SIZE === 0) await yieldToBrowser()
    }

    if (conflicts.length > 0) {
      const conflictText = conflicts.map(item => `${item.category} #${item.game_id}`).join('、')
      alert(`以下编号暂时无法自动录入：${conflictText}\n图鉴中有多件服装使用相同编号，系统无法确定你要录入哪一件，因此没有把这些服装加入衣柜。请改用“按名称录入”；其他可识别的编号会照常录入。`)
    }

    const updatedOwnedIds = Array.from(ownedSet)

    if (newCount > 0) {
      await saveImportedWardrobe(updatedOwnedIds)
    }

    lastNotFoundNames.value = []
    importStats.newCount = newCount
    importStats.dupCount = dupCount
    importStats.missingCodes = [...new Map(notFound.map(item => [`${item.category}_${item.game_id}`, item])).values()]
    importStats.conflictCodes = [...new Map(conflicts.map(item => [`${item.category}_${item.game_id}`, item])).values()]
    importStats.failCount = importStats.missingCodes.length + importStats.conflictCodes.length
    importStats.newClothes = newlyAdded
    importStats.show = true
    codeImportText.value = ''
  })
}

const handleImport = () => {
  if (importMode.value === 'code') return handleCodeImport()
  return handleNameImport()
}
</script>

<template>
  <div class="glass-card p-6 bg-white/80 rounded-2xl shadow-sm border border-slate-100">
    <div class="mb-4">
      <h2 class="text-xl font-black text-pink-500 m-0 border-b-2 border-dashed border-pink-100 pb-3">📥 极速录入衣柜</h2>
    </div>
    
    <div class="flex flex-col gap-3">
      <div class="mode-switch">
        <button type="button" :class="{ active: importMode === 'name' }" @click="importMode = 'name'">按名称录入</button>
        <button type="button" :class="{ active: importMode === 'code' }" @click="importMode = 'code'">按分类短编号录入</button>
      </div>

      <div v-if="importMode === 'name'" class="flex flex-col gap-3">
        <textarea v-model="importText" class="textarea textarea-bordered h-32 focus:border-pink-400 font-bold" placeholder="输入衣服名字，用逗号或换行隔开..."></textarea>
      </div>

      <div v-else class="flex flex-col gap-3">
        <div class="code-import-grid">
          <label class="code-import-label">
            <span>分类部位</span>
            <select v-model="codeImportCategory" class="select select-bordered w-full font-black">
              <option v-for="cat in CODE_IMPORT_CATEGORIES" :key="cat" :value="cat">{{ cat }}</option>
            </select>
          </label>
          <label class="code-import-label">
            <span>短编号</span>
            <textarea
              v-model="codeImportText"
              class="textarea textarea-bordered h-32 focus:border-pink-400 font-bold"
              placeholder="输入短编号，用逗号、空格或换行隔开，如：0001 0002 0003"
            ></textarea>
          </label>
        </div>
        <div class="code-import-tip">
          系统会按“{{ codeImportCategory }} + 短编号”匹配图鉴，成功匹配后加入你的衣柜。
        </div>
      </div>

      <button class="btn btn-primary w-full shadow-lg text-white font-black" @click="handleImport" :disabled="isSaving">
        {{ isSaving ? '同步中...' : '🚀 录入到云端衣柜' }}
      </button>
    </div>

    <Teleport to="body">
      <Transition name="slide-up">
        <div v-if="importStats.show" class="fixed inset-0 z-[150] bg-slate-50 flex flex-col">
          
          <div class="bg-white px-4 py-3 border-b flex justify-between items-center sticky top-0 z-10 shadow-sm">
            <h3 class="font-black text-lg text-slate-800 m-0">📊 录入结果报告</h3>
            <button class="btn btn-sm btn-ghost font-bold" @click="importStats.show = false">关闭</button>
          </div>

          <div class="flex-1 overflow-y-auto p-4 space-y-6 custom-scroll pb-24">
            
            <div class="grid grid-cols-3 gap-3">
              <div class="text-center p-3 rounded-2xl bg-rose-50 border border-rose-100 text-rose-600 shadow-sm">
                <span class="block text-xs font-bold mb-1">图鉴缺失</span>
                <strong class="text-2xl font-black">{{ importStats.failCount }}</strong>
              </div>
              <div class="text-center p-3 rounded-2xl bg-emerald-50 border border-emerald-100 text-emerald-600 shadow-sm">
                <span class="block text-xs font-bold mb-1">新解锁</span>
                <strong class="text-2xl font-black">{{ importStats.newCount }}</strong>
              </div>
              <div class="text-center p-3 rounded-2xl bg-slate-50 border border-slate-200 text-slate-500 shadow-sm">
                <span class="block text-xs font-bold mb-1">已拥有</span>
                <strong class="text-2xl font-black">{{ importStats.dupCount }}</strong>
              </div>
            </div>

            <MissingItemsQueue v-model="lastNotFoundNames" :availableSuits="availableSuits" />

            <div v-if="importStats.missingCodes.length > 0" class="space-y-3">
              <div class="flex items-center gap-2 px-1">
                <span class="text-rose-500">⚠️</span>
                <h4 class="font-black text-sm text-slate-700 m-0">未匹配到图鉴编号</h4>
              </div>
              <div class="missing-code-grid">
                <div v-for="item in importStats.missingCodes" :key="`${item.category}_${item.game_id}`" class="missing-code-card">
                  <span>{{ item.category }}</span>
                  <strong>#{{ item.game_id }}</strong>
                </div>
              </div>
              <p class="missing-code-note">
                这些编号未在正式图鉴中找到；如确认游戏内存在，可在下方补齐名称与属性后提交。
              </p>
            </div>

            <div v-if="importStats.conflictCodes.length > 0" class="space-y-3">
              <div class="flex items-center gap-2 px-1">
                <span class="text-amber-500">⚠️</span>
                <h4 class="font-black text-sm text-slate-700 m-0">有些编号无法自动识别</h4>
              </div>
              <div class="missing-code-grid">
                <div v-for="item in importStats.conflictCodes" :key="`${item.category}_${item.game_id}`" class="missing-code-card">
                  <span>{{ item.category }}</span>
                  <strong>#{{ item.game_id }}</strong>
                </div>
              </div>
              <p class="missing-code-note">
                图鉴中有多件服装使用这些编号，系统无法确定你要录入哪一件，因此没有加入衣柜。请改用“按名称录入”；其他可识别的编号会照常录入。
              </p>
            </div>

            <MissingItemsQueue
              v-if="importStats.missingCodes.length > 0"
              v-model="missingCodeContributionNames"
              :availableSuits="availableSuits"
              :prefills="missingCodeContributionPrefills"
            />

            <div v-if="importStats.newClothes.length > 0" class="space-y-3">
              <div class="flex items-center gap-2 px-1">
                <span class="text-emerald-500">✨</span>
                <h4 class="font-black text-sm text-slate-700 m-0">本次成功录入</h4>
              </div>
              <div class="max-h-[30vh] overflow-y-auto grid grid-cols-2 gap-2 pr-2 custom-scroll">
                <div v-for="item in importStats.newClothes" :key="item.id" class="bg-white border border-emerald-100 p-3 rounded-xl shadow-sm">
                  <span class="text-[10px] font-black text-emerald-500 bg-emerald-50 px-2 py-0.5 rounded-md">{{ item.category }}</span>
                  <div class="text-sm font-bold text-slate-800 mt-1 truncate">{{ item.name }}</div>
                </div>
              </div>
            </div>

          </div>
        </div>
      </Transition>

      <div v-if="isSaving" class="fixed inset-0 z-[200] bg-black/60 backdrop-blur-sm flex items-center justify-center">
        <div class="bg-white px-8 py-6 rounded-3xl flex items-center gap-4 animate-bounce">
          <span class="text-3xl">⏳</span>
          <span class="text-pink-600 font-black">正在同步到云端...</span>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.mode-switch {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 6px;
  padding: 6px;
  background: #f8fafc;
  border: 1.5px solid #f1f5f9;
  border-radius: 16px;
}

.mode-switch button {
  border: 0;
  border-radius: 12px;
  padding: 10px 8px;
  background: transparent;
  color: #64748b;
  font-size: 13px;
  font-weight: 900;
  cursor: pointer;
  transition: all 0.2s ease;
}

.mode-switch button.active {
  background: #f472b6;
  color: white;
  box-shadow: 0 6px 16px rgba(244, 114, 182, 0.25);
}

.code-import-grid {
  display: grid;
  grid-template-columns: minmax(160px, 220px) 1fr;
  gap: 12px;
}

.code-import-label {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.code-import-label span {
  color: #64748b;
  font-size: 12px;
  font-weight: 900;
  padding-left: 2px;
}

.code-import-tip,
.missing-code-note {
  color: #94a3b8;
  font-size: 12px;
  font-weight: 800;
  line-height: 1.5;
}

.missing-code-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
  gap: 8px;
}

.missing-code-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  background: #fff1f2;
  border: 1px solid #fecdd3;
  border-radius: 12px;
  padding: 10px 12px;
  color: #be123c;
  font-size: 12px;
  font-weight: 900;
}

.missing-code-card strong {
  color: #e11d48;
  font-size: 14px;
}

.custom-scroll::-webkit-scrollbar { width: 4px; }
.custom-scroll::-webkit-scrollbar-thumb { background: #cbd5e1; border-radius: 10px; }
.custom-scroll::-webkit-scrollbar-track { background: transparent; }

.slide-up-enter-active, .slide-up-leave-active { transition: transform 0.4s cubic-bezier(0.16, 1, 0.3, 1); }
.slide-up-enter-from, .slide-up-leave-to { transform: translateY(100%); }

/* 🌟 彻底抛弃重绘成本极高的 max-height，改用极其丝滑的 GPU 加速特效 */
.slide-enter-active, .slide-leave-active { transition: opacity 0.2s ease-out, transform 0.2s ease-out; }
.slide-enter-from, .slide-leave-to { opacity: 0; transform: translateY(-10px); }

@media (max-width: 768px) {
  .code-import-grid {
    grid-template-columns: 1fr;
  }
}
</style>
