<script setup>
import { ref, reactive, onMounted, computed, watch } from 'vue'
import { suitService } from '../api/suitService'
import { contributionService } from '../api/contributionService'
import { supabase } from '../api/supabase'
import { useWardrobe } from '../composables/useWardrobe'
import { GRADE_OPTIONS, calculateItemScores } from '../composables/useScoreEngine'
import MissingItemsQueue from './MissingItemsQueue.vue'

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

const fullCategories = [
  '发型', '连衣裙', '外套', '上装', '下装', '袜子-袜套', '袜子-袜子', '鞋子', '妆容', '萤光之灵', 
  '饰品-头饰-发饰', '饰品-头饰-头纱', '饰品-头饰-发卡', '饰品-头饰-耳朵', '饰品-耳饰', '饰品-颈饰-围巾', '饰品-颈饰-项链', 
  '饰品-手饰-右', '饰品-手饰-左', '饰品-手饰-双', '饰品-手持-右', '饰品-手持-左', '饰品-手持-双', '饰品-腰饰', 
  '饰品-特殊-面饰', '饰品-特殊-胸饰', '饰品-特殊-纹身', '饰品-特殊-翅膀', '饰品-特殊-尾巴', '饰品-特殊-前景', '饰品-特殊-后景', '饰品-特殊-顶饰', '饰品-特殊-地面', '饰品-皮肤'
]



onMounted(async () => {
  try { availableSuits.value = await suitService.getAllSuits(); } catch (err) { console.error('加载失败', err); }
})







const handleImport = async () => {
  const inputNames = importText.value.split(/[,，\s\n]+/).map(n => n.trim()).filter(n => n !== '')
  if (inputNames.length === 0) return alert('请输入内容')
  isSaving.value = true;
  let newCount = 0, dupCount = 0;
  const notFound = [], newlyAdded = [], updatedOwnedIds = [...props.ownedIds];

  inputNames.forEach(name => {
    const found = props.wardrobe.find(item => item.name === name)
    if (found) {
      if (updatedOwnedIds.includes(found.id)) { dupCount++; } 
      else { updatedOwnedIds.push(found.id); newCount++; newlyAdded.push(found); }
    } else { notFound.push(name); }
  });

  lastNotFoundNames.value = [...new Set(notFound)];

  try {
    if (newCount > 0) {
      if (props.isLoggedIn) {
        const { data: { user } } = await supabase.auth.getUser();
        await saveWardrobeToCloud(user.id, updatedOwnedIds);
      }
      emit('update:ownedIds', updatedOwnedIds);
    }
    importStats.newCount = newCount; importStats.dupCount = dupCount;
    importStats.failCount = lastNotFoundNames.value.length;
    importStats.newClothes = newlyAdded; importStats.show = true; importText.value = '';
  } catch (err) { alert('同步失败'); } finally { isSaving.value = false; }
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