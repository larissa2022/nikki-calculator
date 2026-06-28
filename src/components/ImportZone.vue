<script setup>
import { ref, reactive, onMounted, computed, watch } from 'vue'
import { useWardrobe } from '../composables/useWardrobe'
import MissingItemsQueue from './MissingItemsQueue.vue'
import { supabase, logErrorToCloud } from '../api/supabase'
import { suitService } from '../api/suitService'

const props = defineProps({
  wardrobe: { type: Array, required: true },
  ownedIds: { type: Array, required: true },
  isLoggedIn: { type: Boolean, default: false }
})

const emit = defineEmits(['update:ownedIds', 'save-cloud', 'refresh-profile'])
const { saveWardrobeToCloud } = useWardrobe()

const importText = ref('')
const importStats = reactive({ show: false, newCount: 0, dupCount: 0, failCount: 0, newClothes: [] })

// 🌟 核心：消消乐视窗逻辑，永远只展示前 3 个
const lastNotFoundNames = ref([])
const isSaving = ref(false)
const availableSuits = ref([])
const IMPORT_DRAFT_KEY = 'nikki.importZoneDraft.v1'
const DRAFT_TTL_MS = 24 * 60 * 60 * 1000
const PROCESS_BATCH_SIZE = 500

const yieldToBrowser = () => new Promise(resolve => setTimeout(resolve, 0))

const fullCategories = [
  '发型', '连衣裙', '外套', '上装', '下装', '袜子-袜套', '袜子-袜子', '鞋子', '妆容', '萤光之灵', 
  '饰品-头饰-发饰', '饰品-头饰-头纱', '饰品-头饰-发卡', '饰品-头饰-耳朵', '饰品-耳饰', '饰品-颈饰-围巾', '饰品-颈饰-项链', 
  '饰品-手饰-右', '饰品-手饰-左', '饰品-手饰-双', '饰品-手持-右', '饰品-手持-左', '饰品-手持-双', '饰品-腰饰', 
  '饰品-特殊-面饰', '饰品-特殊-胸饰', '饰品-特殊-纹身', '饰品-特殊-翅膀', '饰品-特殊-尾巴', '饰品-特殊-前景', '饰品-特殊-后景', '饰品-特殊-顶饰', '饰品-特殊-地面', '饰品-皮肤'
]

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
      importText: importText.value,
      lastNotFoundNames: lastNotFoundNames.value,
      importStats: JSON.parse(JSON.stringify(importStats)),
      updatedAt: Date.now()
    }))
  } catch (err) {
    console.warn('保存录入草稿失败:', err)
  }
}

const restoreImportDraft = () => {
  const draft = readImportDraft()
  if (!draft) return
  importText.value = draft.importText || ''
  lastNotFoundNames.value = Array.isArray(draft.lastNotFoundNames) ? draft.lastNotFoundNames : []
  if (draft.importStats) {
    Object.assign(importStats, {
      show: !!draft.importStats.show,
      newCount: Number(draft.importStats.newCount) || 0,
      dupCount: Number(draft.importStats.dupCount) || 0,
      failCount: Number(draft.importStats.failCount) || lastNotFoundNames.value.length,
      newClothes: Array.isArray(draft.importStats.newClothes) ? draft.importStats.newClothes : []
    })
  }
}

onMounted(async () => {
  restoreImportDraft()
  try { availableSuits.value = await suitService.getAllSuits(); } catch (err) { console.error('加载失败', err); }
})

watch(
  () => ({
    importText: importText.value,
    lastNotFoundNames: lastNotFoundNames.value,
    importStats: { ...importStats }
  }),
  saveImportDraft,
  { deep: true }
)

watch(lastNotFoundNames, (names) => {
  importStats.failCount = names.length
})

const handleImport = async () => {
  const inputNames = importText.value.split(/[,，\s\n]+/).map(n => n.trim()).filter(n => n !== '')
  if (inputNames.length === 0) return alert('请输入内容')
  
  // 1. 开启界面锁
  isSaving.value = true;
  
  // 🌟 核心优化 1：强制让出主线程，确保“正在同步”的动画能被浏览器立刻画出来，不假死！
  await new Promise(resolve => setTimeout(resolve, 50));

  try {
    let newCount = 0, dupCount = 0;
    const notFound = [], newlyAdded = [];

    // 🌟 核心优化 2：建立哈希表 (Map)，把几万件衣服的查询时间从 O(N) 降为 O(1)
    const wardrobeMap = new Map(props.wardrobe.map(item => [item.name, item]));
    // 🌟 核心优化 3：建立集合 (Set)，把是否拥有的查重时间从 O(N) 降为 O(1)
    const ownedSet = new Set(props.ownedIds);

    // 开始极速匹配；大量录入时分批让出主线程，避免页面假死
    for (let index = 0; index < inputNames.length; index++) {
      const name = inputNames[index]
      const found = wardrobeMap.get(name); // 瞬间拿结果，不需要 find 遍历
      
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
    const updatedOwnedIds = Array.from(ownedSet);
    lastNotFoundNames.value = [...new Set(notFound)];

    if (newCount > 0) {
      if (props.isLoggedIn) {
        // 严格查岗，防止死 Token
        const { data: { user }, error: authErr } = await supabase.auth.getUser();
        if (authErr || !user) throw new Error('登录状态已过期，请刷新页面重新登录！');
        
        // 提交云端
        const savedOwnedIds = await saveWardrobeToCloud(user.id, updatedOwnedIds, { mode: 'merge' });
        emit('update:ownedIds', savedOwnedIds);
      } else {
        emit('update:ownedIds', updatedOwnedIds);
      }
    }
    
    // 渲染统计结果
    importStats.newCount = newCount; 
    importStats.dupCount = dupCount;
    importStats.failCount = lastNotFoundNames.value.length;
    importStats.newClothes = newlyAdded; 
    importStats.show = true; 
    importText.value = '';

  } catch (err) { 
    alert('❌ 录入中断：\n' + (err.message || '网络请求异常，请检查网络后重试')); 
    // 云端异常上报 (上一回合加的代码)
    const { data: { session } } = await supabase.auth.getSession();
    if (typeof logErrorToCloud === 'function') {
      logErrorToCloud('import_wardrobe_mobile', err, session?.user?.id);
    }
  } finally { 
    isSaving.value = false; 
  }
}
</script>

<template>
  <div class="glass-card p-6 bg-white/80 rounded-2xl shadow-sm border border-slate-100">
    <div class="mb-4">
      <h2 class="text-xl font-black text-pink-500 m-0 border-b-2 border-dashed border-pink-100 pb-3">📥 极速录入衣柜</h2>
    </div>
    
    <div class="flex flex-col gap-3">
      <textarea v-model="importText" class="textarea textarea-bordered h-32 focus:border-pink-400 font-bold" placeholder="输入衣服名字，用逗号或换行隔开..."></textarea>
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
.custom-scroll::-webkit-scrollbar { width: 4px; }
.custom-scroll::-webkit-scrollbar-thumb { background: #cbd5e1; border-radius: 10px; }
.custom-scroll::-webkit-scrollbar-track { background: transparent; }

.slide-up-enter-active, .slide-up-leave-active { transition: transform 0.4s cubic-bezier(0.16, 1, 0.3, 1); }
.slide-up-enter-from, .slide-up-leave-to { transform: translateY(100%); }

/* 🌟 彻底抛弃重绘成本极高的 max-height，改用极其丝滑的 GPU 加速特效 */
.slide-enter-active, .slide-leave-active { transition: opacity 0.2s ease-out, transform 0.2s ease-out; }
.slide-enter-from, .slide-leave-to { opacity: 0; transform: translateY(-10px); }
</style>
