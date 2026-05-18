
<script setup>
import { ref, reactive, computed, watch } from 'vue'
import { supabase } from '../api/supabase'
import { suitService } from '../api/suitService'
import { GRADE_OPTIONS, calculateItemScores } from '../composables/useScoreEngine'

// 1. 接收父组件传递的缺失数组与套装池
// 使用 defineModel 可以让子组件过滤名字时，父组件的统计数据同步更新
const lastNotFoundNames = defineModel({ type: Array, required: true })
defineProps({
  availableSuits: { type: Array, required: true }
})

// 2. 100% 移入原版本所需的独立表单状态
const displayNotFoundNames = computed(() => lastNotFoundNames.value.slice(0, 3))
const activeContribution = ref(null)
const isSubmittingContrib = ref(false)
const suitSearchText = ref('')
const isSuitDropdownOpen = ref(false)

const fullCategories = [
  '发型', '连衣裙', '外套', '上装', '下装', '袜子-袜套', '袜子-袜子', '鞋子', '妆容', '萤光之灵', 
  '饰品-头饰-发饰', '饰品-头饰-头纱', '饰品-头饰-发卡', '饰品-头耳朵', '饰品-耳饰', '饰品-颈饰-围巾', '饰品-颈饰-项链', 
  '饰品-手饰-右', '饰品-手饰-左', '饰品-手饰-双', '饰品-手持-右', '饰品-手持-左', '饰品-手持-双', '饰品-腰饰', 
  '饰品-特殊-面饰', '饰品-特殊-胸饰', '饰品-特殊-纹身', '饰品-特殊-翅膀', '饰品-特殊-尾巴', '饰品-特殊-前景', '饰品-特殊-后景', '饰品-特殊-顶饰', '饰品-特殊-地面', '饰品-皮肤'
]

const contribForm = reactive({
  name: '', 
  suit_id: '', game_id: '', tags: '', category: '连衣裙', stars: 5,
  pair1: 'simple', grade1: '完美', pair2: 'active', grade2: '完美',
  pair3: 'cute', grade3: '完美', pair4: 'pure', grade4: '完美',
  pair5: 'cool', grade5: '完美'
})

watch(activeContribution, (newVal) => { 
  suitSearchText.value = ''; 
  contribForm.suit_id = ''; 
  contribForm.game_id = ''; 
  contribForm.name = newVal || ''; 
})

const filteredSuits = computed(() => {
  const query = suitSearchText.value?.toLowerCase().trim() || '';
  if (!query || query.startsWith('《')) return availableSuits.value;
  return availableSuits.value.filter(s => s.name && s.name.toLowerCase().includes(query));
})

const handleSuitBlur = () => {
  setTimeout(() => { isSuitDropdownOpen.value = false }, 200)
}

const selectSuit = (suit) => {
  contribForm.suit_id = suit.id;
  suitSearchText.value = suit.id ? `《${suit.name}》` : '';
  isSuitDropdownOpen.value = false;
}

const promptAddNewSuit = async () => {
  const newSuitName = prompt('请输入要申请添加的新套装名称：')
  if (!newSuitName || !newSuitName.trim()) return
  try {
    const { data: { user } } = await supabase.auth.getUser()
    await suitService.applyNewSuit(newSuitName, user?.id)
    alert('✅ 套装申请已发送给管理员审核！请等待审核通过后再关联该部件。')
  } catch (error) {
    alert('套装申请提交失败！')
  }
}

const submitContribution = async (name) => {
  isSubmittingContrib.value = true;
  try {
    const { data: authData } = await supabase.auth.getSession();
    const userId = authData?.session?.user?.id;

    const pairs = [
      { attr: contribForm.pair1, grade: contribForm.grade1 },
      { attr: contribForm.pair2, grade: contribForm.grade2 },
      { attr: contribForm.pair3, grade: contribForm.grade3 },
      { attr: contribForm.pair4, grade: contribForm.grade4 },
      { attr: contribForm.pair5, grade: contribForm.grade5 }
    ];
    const calculatedScores = calculateItemScores(contribForm.category, pairs);

    const payload = {
      name: contribForm.name || name,
      game_id: contribForm.game_id || 'N', 
      category: contribForm.category,
      stars: Number(contribForm.stars), 
      scores: calculatedScores, 
      suit_id: contribForm.suit_id || null,
      tags: contribForm.tags || null, 
      submitted_by: userId || null, 
      status: 'pending'
    };

    const { error: dbErr } = await supabase.from('pending_clothes').insert(payload);
    if (dbErr) throw new Error(dbErr.message);
    
    alert(`🎉 提交成功！`);
    
    // 自动触发消消乐过滤
    lastNotFoundNames.value = lastNotFoundNames.value.filter(n => n !== name);
    activeContribution.value = null;
  } catch (err) { 
    console.error('上传失败详情:', err);
    alert('提交失败，数据库拒绝了请求: ' + err.message); 
  } finally { 
    isSubmittingContrib.value = false; 
  }
}
</script>

<template>
  <div v-if="lastNotFoundNames.length > 0" class="space-y-3">
    <div class="flex items-center gap-2 px-1">
      <span class="text-rose-500">⚠️</span>
      <h4 class="font-black text-sm text-slate-700 m-0">图鉴缺失项 (建议补录)</h4>
    </div>
    
    <div class="space-y-3 pr-2">
      <div v-for="name in displayNotFoundNames" :key="name" class="bg-white border-2 border-slate-100 rounded-2xl p-4 shadow-sm">
        <div class="flex justify-between items-center">
          <span class="font-black text-slate-700">{{ name }}</span>
          <button @click="activeContribution = (activeContribution === name ? null : name)" class="btn btn-xs btn-outline btn-secondary rounded-full">
            {{ activeContribution === name ? '收起' : '完善资料' }}
          </button>
        </div>

        <Transition name="slide">
          <div v-if="activeContribution === name" class="mt-4 pt-4 border-t border-dashed space-y-4">
            <div class="grid gap-4 text-xs">
              <div class="flex flex-col gap-1">
                <span class="font-bold text-slate-400">服装名称</span>
                <input type="text" v-model="contribForm.name" class="input input-bordered w-full font-bold text-slate-700" />
              </div>
              <div class="flex flex-col gap-1">
                <span class="font-bold text-slate-400">所属套装</span>
                <div class="flex gap-2">
                  <div class="relative flex-1">
                    <input type="text" v-model="suitSearchText" @focus="isSuitDropdownOpen = true" @blur="handleSuitBlur" placeholder="搜索套装..." class="input input-sm input-bordered w-full font-bold bg-slate-50 focus:bg-white" />
                    <div v-if="isSuitDropdownOpen" class="absolute z-50 w-full mt-1 bg-white border border-slate-200 rounded-xl shadow-xl max-h-40 overflow-y-auto">
                      <div class="p-2 hover:bg-pink-50 font-bold cursor-pointer" @click="selectSuit({id: '', name: ''})">-- 无关联套装 --</div>
                      <div v-for="s in filteredSuits" :key="s.id" class="p-2 hover:bg-pink-50 font-bold cursor-pointer" @click="selectSuit(s)">《{{ s.name }}》</div>
                    </div>
                  </div>
                  <button @click="promptAddNewSuit" class="btn btn-sm btn-outline whitespace-nowrap">➕ 新套装</button>
                </div>
              </div>
              
              <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div><span class="font-bold text-slate-400 mb-1 block">短编号</span><input type="text" v-model="contribForm.game_id" class="input input-bordered w-full font-bold" placeholder="选填" /></div>
                <div><span class="font-bold text-slate-400 mb-1 block">分类部位</span><select v-model="contribForm.category" class="select select-bordered font-bold w-full"><option v-for="cat in fullCategories" :key="cat">{{cat}}</option></select></div>
                <div><span class="font-bold text-slate-400 mb-1 block">星级</span><select v-model="contribForm.stars" class="select select-bordered font-bold w-full"><option v-for="s in 6" :key="s" :value="s">{{s}} 星</option></select></div>
              </div>
              
              <div>
                <span class="font-bold text-slate-400 mb-1 block">特殊标签</span>
                <input type="text" v-model="contribForm.tags" class="input input-sm input-bordered w-full font-bold" placeholder="如: 洛丽塔, 中式古典..." />
              </div>

              <div class="flex flex-col gap-3">
                <div v-for="i in 5" :key="i" class="grid grid-cols-2 gap-3">
                  <select v-model="contribForm['pair'+i]" class="select select-bordered w-full font-bold">
                    <option v-if="i==1" value="simple">简约</option><option v-if="i==1" value="gorgeous">华丽</option>
                    <option v-if="i==2" value="active">活泼</option><option v-if="i==2" value="elegant">优雅</option>
                    <option v-if="i==3" value="cute">可爱</option><option v-if="i==3" value="mature">成熟</option>
                    <option v-if="i==4" value="pure">清纯</option><option v-if="i==4" value="sexy">性感</option>
                    <option v-if="i==5" value="cool">清凉</option><option v-if="i==5" value="warm">保暖</option>
                  </select>
                  <select v-model="contribForm['grade'+i]" class="select select-bordered w-full font-bold bg-pink-50 text-pink-500 border-pink-200">
                    <option v-for="g in GRADE_OPTIONS" :key="g">{{g}}</option>
                  </select>
                </div>
              </div>
              
              <button class="btn btn-primary w-full shadow-md font-black mt-2" @click="submitContribution(name)" :disabled="isSubmittingContrib">
                <span v-if="isSubmittingContrib" class="loading loading-spinner loading-sm"></span>
                {{ isSubmittingContrib ? '上传中...' : '🚀 确认提交申请' }}
              </button>
            </div>
          </div>
        </Transition>
      </div>
      
      <div v-if="lastNotFoundNames.length > 3" class="text-center py-2 text-xs font-bold text-slate-400 bg-slate-50 rounded-xl border border-dashed border-slate-200">
        👇 还有 {{ lastNotFoundNames.length - 3 }} 件缺失服装正在排队...
      </div>
    </div>
  </div>
</template>
<style scoped>
/* =========================================
   1. 滚动条与基础动画 (基础框架)
   ========================================= */
.custom-scroll::-webkit-scrollbar { width: 5px; }
.custom-scroll::-webkit-scrollbar-thumb { background: #e2e8f0; border-radius: 10px; }
.custom-scroll::-webkit-scrollbar-track { background: transparent; }

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

.slide-enter-active, .slide-leave-active { transition: opacity 0.2s ease-out, transform 0.2s ease-out; }
.slide-enter-from, .slide-leave-to { opacity: 0; transform: translateY(-10px); }

/* =========================================
   2. 沉浸式表单样式 (个性化整合)
   ========================================= */
.mini-form-body { display: flex; flex-direction: column; gap: 12px; }

.form-row { display: grid; gap: 12px; }
.form-row.three-cols { grid-template-columns: repeat(3, minmax(0, 1fr)); }

.form-group { display: flex; flex-direction: column; gap: 6px; }
.form-group label { font-size: 12px; font-weight: 800; color: #64748b; padding-left: 2px;}

/* 极简风输入框 */
.custom-input { 
  width: 100%; border: 2px solid #f1f5f9; border-radius: 12px; 
  padding: 8px 12px; font-size: 14px; font-weight: 800; color: #334155; 
  transition: all 0.2s; outline: none; background: #fff;
}
.custom-input:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }
.custom-input::placeholder { color: #cbd5e1; font-weight: 600; }

/* 搜索下拉框体系 */
.searchable-select { position: relative; }
.search-input { 
  width: 100%; border: 2px solid #f1f5f9; border-radius: 12px; 
  padding: 8px 12px; font-size: 14px; font-weight: 800; color: #334155; 
  outline: none; transition: all 0.2s; background: #f8fafc;
}
.search-input:focus { border-color: #f472b6; background: #fff; }

.select-dropdown { 
  position: absolute; z-index: 50; top: 100%; left: 0; right: 0; margin-top: 6px; 
  background: white; border: 1px solid #f1f5f9; border-radius: 12px; 
  box-shadow: 0 10px 25px rgba(0,0,0,0.05); max-height: 200px; overflow-y: auto; padding: 6px; 
}
.option { 
  padding: 8px 12px; font-size: 13px; font-weight: 800; color: #475569; 
  border-radius: 8px; cursor: pointer; transition: background 0.2s; 
}
.option:hover { background: #fdf2f8; color: #db2777; }
.empty-option { color: #94a3b8; text-align: center; pointer-events: none; }

/* 个性化按钮 */
.btn-action-outline { 
  border: 2px solid #e2e8f0; background: transparent; color: #64748b; 
  font-weight: 800; font-size: 13px; border-radius: 12px; cursor: pointer; transition: all 0.2s; 
}
.btn-action-outline:hover { border-color: #f472b6; color: #f472b6; background: #fdf2f8; }

.btn-submit-contrib { 
  background: linear-gradient(135deg, #a855f7, #ec4899); color: white; border: none; 
  font-size: 15px; font-weight: 900; padding: 12px; border-radius: 14px; 
  cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 15px rgba(236, 72, 153, 0.25); margin-top: 10px; 
}
.btn-submit-contrib:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(236, 72, 153, 0.35); }
.btn-submit-contrib:disabled { opacity: 0.7; cursor: not-allowed; background: #cbd5e1; box-shadow: none; }

/* =========================================
   3. 移动端响应式修正
   ========================================= */
@media (max-width: 768px) {
  .form-row.three-cols { grid-template-columns: 1fr; gap: 12px; }
}
</style>