<script setup>
import { ref, computed } from 'vue'
import { FULL_CATEGORIES, ATTRIBUTE_PAIRS } from '../utils/gameConstants'
// 直接复用你已经写好的计分引擎里的评级
import { GRADE_OPTIONS } from '../composables/useScoreEngine' 

const props = defineProps({
  form: { type: Object, required: true },
  suitSearchText: { type: String, required: true },
  availableSuits: { type: Array, required: true },
  isSubmitting: { type: Boolean, default: false },
  submitText: { type: String, default: '确认提交' },
  submitLoadingText: { type: String, default: '系统处理中...' },
  suitNotFoundText: { type: String, default: '新建套装' },
  showGameIdWarning: { type: Boolean, default: false }
})

const emit = defineEmits(['update:suitSearchText', 'submit', 'create-suit'])

const isSuitDropdownOpen = ref(false)

// 智能模糊搜索
const filteredSuits = computed(() => {
  const query = props.suitSearchText?.toLowerCase().trim() || ''
  if (!query || query.startsWith('《')) return props.availableSuits.slice(0, 50)
  return props.availableSuits.filter(s => s.name && s.name.toLowerCase().includes(query)).slice(0, 50)
})

const selectSuit = (suit) => {
  props.form.suit_id = suit.id
  emit('update:suitSearchText', suit.id ? `《${suit.name}》` : '')
  isSuitDropdownOpen.value = false
}

const handleCreateSuit = () => {
  emit('create-suit', props.suitSearchText)
  isSuitDropdownOpen.value = false
}
</script>

<template>
  <div class="mini-form-body">
    <div class="form-row" style="grid-template-columns: 1fr;">
      <div class="form-group">
        <label>服装名称</label>
        <input type="text" v-model="form.name" class="custom-input" placeholder="确认官方精准名称" />
      </div>
      
      <div class="form-group">
        <label>所属套装</label>
        <div class="searchable-select">
          <input 
            type="text" 
            :value="suitSearchText"
            @input="emit('update:suitSearchText', $event.target.value)"
            @focus="isSuitDropdownOpen = true"
            @blur="setTimeout(() => isSuitDropdownOpen = false, 200)"
            placeholder="🔍 搜索并选择套装..."
            class="search-input"
          />
          <Transition name="slide">
            <div v-if="isSuitDropdownOpen" class="select-dropdown">
              <div class="option" @mousedown.prevent="selectSuit({id: '', name: ''})">-- 无关联套装 (纯散件) --</div>
              <div v-for="s in filteredSuits" :key="s.id" class="option" @mousedown.prevent="selectSuit(s)">《{{ s.name }}》</div>
              
              <div 
                v-if="filteredSuits.length === 0 && suitSearchText.trim() !== ''" 
                class="option bg-purple-50 text-purple-600 font-bold flex justify-between items-center border border-purple-100 hover:bg-purple-100"
                @mousedown.prevent="handleCreateSuit"
              >
                <span class="text-xs">⚠️ 暂无《{{ suitSearchText.replace(/[《》]/g, '') }}》</span>
                <span class="bg-purple-500 text-white px-2 py-1 rounded-md text-xs shadow-sm">{{ suitNotFoundText }}</span>
              </div>
            </div>
          </Transition>
        </div>
      </div>
    </div>
    
    <div class="form-row three-cols">
      <div class="form-group">
        <label :class="{'text-rose-500': showGameIdWarning}">短编号(如001) <span v-if="showGameIdWarning">必填</span></label>
        <input type="text" v-model="form.game_id" class="custom-input" :class="{'border-rose-200 bg-rose-50/30': showGameIdWarning}" placeholder="若无填 N" />
      </div>
      <div class="form-group">
        <label>分类部位</label>
        <select v-model="form.category" class="custom-input">
          <option v-for="cat in FULL_CATEGORIES" :key="cat">{{cat}}</option>
        </select>
      </div>
      <div class="form-group">
        <label>星级</label>
        <select v-model="form.stars" class="custom-input">
          <option v-for="s in 6" :key="s" :value="s">{{s}} 星</option>
        </select>
      </div>
    </div>
    
    <div class="form-row">
      <div class="form-group">
        <label>特殊标签</label>
        <input type="text" v-model="form.tags" class="custom-input" placeholder="如: 洛丽塔, 中式古典..." />
      </div>
    </div>

    <div class="flex flex-col gap-3 mt-2">
      <div v-for="pair in ATTRIBUTE_PAIRS" :key="pair.key" class="grid grid-cols-2 gap-3">
        <select v-model="form[pair.key]" class="custom-input !py-2">
          <option v-for="opt in pair.options" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
        </select>
        <select v-model="form[pair.gradeKey]" class="custom-input !py-2 bg-pink-50 text-pink-600 border-pink-200">
          <option v-for="g in GRADE_OPTIONS" :key="g">{{ g }}</option>
        </select>
      </div>
    </div>

    <slot name="admin-tips"></slot>

    <button class="btn-submit-contrib w-full" @click="emit('submit')" :disabled="isSubmitting">
      <span v-if="isSubmitting" class="loading loading-spinner loading-sm mr-2 inline-block"></span>
      {{ isSubmitting ? submitLoadingText : submitText }}
    </button>
  </div>
</template>

<style scoped>
/* 整合了原 AdminView 和 MissingQueue 共用的表单级 CSS */
.mini-form-body { display: flex; flex-direction: column; gap: 12px; }
.form-row { display: grid; gap: 12px; }
.form-row.three-cols { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.form-group { display: flex; flex-direction: column; gap: 6px; }
.form-group label { font-size: 12px; font-weight: 800; color: #64748b; padding-left: 2px; }
.custom-input, .search-input { width: 100%; border: 2px solid #f1f5f9; border-radius: 12px; padding: 10px 12px; font-size: 14px; font-weight: 800; color: #334155; transition: all 0.2s; outline: none; background: #fff; }
.custom-input:focus, .search-input:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }
.searchable-select { position: relative; }
.select-dropdown { position: absolute; z-index: 50; top: 100%; left: 0; right: 0; margin-top: 6px; background: white; border: 1px solid #f1f5f9; border-radius: 12px; box-shadow: 0 10px 25px rgba(0, 0, 0, 0.05); max-height: 200px; overflow-y: auto; padding: 6px; }
.option { padding: 8px 12px; font-size: 13px; font-weight: 800; color: #475569; border-radius: 8px; cursor: pointer; transition: background 0.2s; }
.option:hover { background: #fdf2f8; color: #db2777; }
.btn-submit-contrib { background: linear-gradient(135deg, #a855f7, #ec4899); color: white; border: none; font-size: 15px; font-weight: 900; padding: 12px; border-radius: 14px; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 15px rgba(236, 72, 153, 0.25); margin-top: 10px; }
.btn-submit-contrib:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(236, 72, 153, 0.35); }
.btn-submit-contrib:disabled { opacity: 0.7; cursor: not-allowed; background: #cbd5e1; box-shadow: none; }
@media (max-width: 768px) { .form-row.three-cols { grid-template-columns: 1fr; gap: 12px; } }
</style>
