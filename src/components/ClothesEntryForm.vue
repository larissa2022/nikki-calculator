<script setup>
import { ref, computed, nextTick, watch } from 'vue'
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
  showGameIdWarning: { type: Boolean, default: false },
  readonlyFields: { type: Array, default: () => [] },
  visibleFields: { type: Array, default: () => [] },
  reviewMode: { type: Boolean, default: false },
  allowPendingReview: { type: Boolean, default: true },
  allowCreateSuit: { type: Boolean, default: true },
  showRuleNote: { type: Boolean, default: true },
  inlineValidation: { type: Boolean, default: false }
})

const emit = defineEmits(['update:suitSearchText', 'submit', 'create-suit', 'validation-error'])

const isSuitDropdownOpen = ref(false)
const explicitNoSuit = ref(false)
const explicitPendingReview = ref(false)
const isReadonly = field => props.readonlyFields.includes(field)
const isVisible = field => props.visibleFields.length === 0 || props.visibleFields.includes(field)
const hasVisibleAttributeFields = computed(() => ATTRIBUTE_PAIRS.some((pair, index) => (
  isVisible(`pair${index + 1}`)
)))

const cleanSuitSearchText = computed(() => props.suitSearchText.replace(/[《》]/g, '').trim())
const hasSuitData = computed(() => props.availableSuits.length > 0)
const suitInputValue = computed(() => {
  if (explicitNoSuit.value) return '-- 无关联套装（纯散件）--'
  if (explicitPendingReview.value) return '-- 所属套装待确认 --'
  return props.suitSearchText
})
const gameIdText = computed(() => String(props.form.game_id || '').trim())
const hasSuitStatus = computed(() => Boolean(
  props.form.suit_status
  || props.form.suit_id
  || cleanSuitSearchText.value
  || explicitNoSuit.value
  || explicitPendingReview.value
))
const missingCoreFields = computed(() => {
  const missing = []
  if (isVisible('name') && !String(props.form.name || '').trim()) missing.push('服装名称')
  if (isVisible('category') && !String(props.form.category || '').trim()) missing.push('分类部位')
  if (isVisible('game_id') && !gameIdText.value) missing.push('短编号')
  if (isVisible('stars') && !props.form.stars) missing.push('星级')
  if (isVisible('suit') && !hasSuitStatus.value) missing.push('套装状态（请选择已有套装或纯散件）')

  ATTRIBUTE_PAIRS.forEach((pair, index) => {
    if (isVisible(`pair${index + 1}`) && (!props.form[pair.key] || !props.form[pair.gradeKey])) {
      missing.push(`第 ${index + 1} 组属性`)
    }
  })

  if (isVisible('game_id') && gameIdText.value && !/^\d+$/.test(gameIdText.value)) {
    missing.push('数字短编号')
  }

  return missing
})
const coreFieldMissingText = computed(() => missingCoreFields.value.join('、'))

watch(
  () => props.form.suit_status,
  (status) => {
    explicitNoSuit.value = status === 'none'
    explicitPendingReview.value = status === 'pending_review'
  },
  { immediate: true }
)

// 智能模糊搜索
const filteredSuits = computed(() => {
  const query = cleanSuitSearchText.value.toLowerCase()
  if (!query) return props.availableSuits.slice(0, 50)
  return props.availableSuits.filter(s => s.name && s.name.toLowerCase().includes(query)).slice(0, 50)
})

const handleSuitInput = (value) => {
  if (isReadonly('suit')) return
  explicitNoSuit.value = false
  explicitPendingReview.value = false
  props.form.suit_status = value.trim() ? 'new' : ''
  if (props.form.suit_id) {
    props.form.suit_id = ''
  }
  emit('update:suitSearchText', value)
}

const handleGameIdInput = (event) => {
  if (isReadonly('game_id')) return
  const digitsOnly = event.target.value.replace(/\D/g, '')
  props.form.game_id = digitsOnly
  if (event.target.value !== digitsOnly) {
    event.target.value = digitsOnly
  }
}

const selectSuit = (suit) => {
  if (isReadonly('suit')) return
  explicitNoSuit.value = false
  explicitPendingReview.value = false
  props.form.suit_id = suit.id || ''
  props.form.suit_status = suit.id ? 'existing' : ''
  emit('update:suitSearchText', suit.id ? `《${suit.name}》` : '')
  isSuitDropdownOpen.value = false
}

const selectNoSuit = async () => {
  if (isReadonly('suit')) return
  explicitNoSuit.value = true
  explicitPendingReview.value = false
  props.form.suit_id = ''
  props.form.suit_status = 'none'
  emit('update:suitSearchText', '')
  isSuitDropdownOpen.value = false
  await nextTick()
  document.activeElement?.blur?.()
}

const selectPendingReview = async () => {
  if (isReadonly('suit') || !props.allowPendingReview) return
  explicitNoSuit.value = false
  explicitPendingReview.value = true
  props.form.suit_id = ''
  props.form.suit_status = 'pending_review'
  emit('update:suitSearchText', '')
  isSuitDropdownOpen.value = false
  await nextTick()
  document.activeElement?.blur?.()
}

const handleCreateSuit = () => {
  if (isReadonly('suit') || !props.allowCreateSuit || !cleanSuitSearchText.value) return
  explicitNoSuit.value = false
  explicitPendingReview.value = false
  props.form.suit_id = ''
  props.form.suit_status = 'new'
  emit('create-suit', cleanSuitSearchText.value)
  isSuitDropdownOpen.value = false
}

const handleSubmit = () => {
  if (missingCoreFields.value.length) {
    const message = `请先补全：${coreFieldMissingText.value}。特殊标签为选填。`
    if (props.inlineValidation) emit('validation-error', message)
    else alert(`⚠️ ${message}`)
    return
  }

  emit('submit')
}
</script>

<template>
  <div class="mini-form-body">
    <div v-if="showRuleNote" class="entry-rule-note">
      新增服装按 <strong>分类部位 + 短编号</strong> 识别；特殊标签可选填。
    </div>

    <div class="form-row" style="grid-template-columns: 1fr;">
      <div v-if="isVisible('name')" class="form-group">
        <label>服装名称 <span :class="reviewMode ? 'review-mark' : 'required-mark'">{{ reviewMode ? '请审核' : '必填' }}</span></label>
        <input type="text" v-model.trim="form.name" class="custom-input" placeholder="确认官方精准名称" :disabled="isReadonly('name')" />
      </div>
      
      <div v-if="isVisible('suit')" class="form-group">
        <label>套装状态 <span :class="reviewMode ? 'review-mark' : 'required-mark'">{{ reviewMode ? '请审核' : '必填' }}</span></label>
        <div class="searchable-select">
          <input 
            type="text" 
            :value="suitInputValue"
            @input="handleSuitInput($event.target.value)"
            @focus="!isReadonly('suit') && (isSuitDropdownOpen = true)"
            @blur="setTimeout(() => isSuitDropdownOpen = false, 200)"
            @keydown.escape="isSuitDropdownOpen = false"
            placeholder="🔍 搜索已有套装、输入新套装名，或选择套装状态"
            class="search-input"
            :class="{'border-rose-200 bg-rose-50/30': !hasSuitStatus}"
            :readonly="isReadonly('suit')"
          />
          <Transition name="slide">
            <div v-if="isSuitDropdownOpen" class="select-dropdown">
              <div class="option no-suit-option" @pointerdown.prevent="selectNoSuit">-- 无关联套装（纯散件）--</div>
              <div v-if="allowPendingReview" class="option pending-review-option" @pointerdown.prevent="selectPendingReview">-- 所属套装待确认 --</div>
              <div v-for="s in filteredSuits" :key="s.id" class="option" @pointerdown.prevent="selectSuit(s)">《{{ s.name }}》</div>
              
              <div v-if="!hasSuitData && !cleanSuitSearchText" class="option empty-option">
                暂无套装数据。可直接输入套装名后申请，也可选择“无关联套装”或“所属套装待确认”。
              </div>

              <div 
                v-if="allowCreateSuit && filteredSuits.length === 0 && cleanSuitSearchText !== ''"
                class="option bg-purple-50 text-purple-600 font-bold flex justify-between items-center border border-purple-100 hover:bg-purple-100"
                @pointerdown.prevent="handleCreateSuit"
              >
                <span class="text-xs">⚠️ 暂无《{{ cleanSuitSearchText }}》</span>
                <span class="bg-purple-500 text-white px-2 py-1 rounded-md text-xs shadow-sm">{{ suitNotFoundText }}</span>
              </div>
            </div>
          </Transition>
        </div>
      </div>
    </div>
    
    <div class="form-row three-cols">
      <div v-if="isVisible('category')" class="form-group">
        <label>分类部位 <span :class="reviewMode ? 'review-mark' : 'required-mark'">{{ reviewMode ? '请审核' : '必填' }}</span></label>
        <select v-model="form.category" class="custom-input" :disabled="isReadonly('category')">
          <option v-for="cat in FULL_CATEGORIES" :key="cat">{{cat}}</option>
        </select>
      </div>
      <div v-if="isVisible('game_id')" class="form-group">
        <label :class="{'text-rose-500': showGameIdWarning}">短编号(如001) <span :class="reviewMode ? 'review-mark' : 'required-mark'">{{ reviewMode ? '请审核' : '必填' }}</span></label>
        <input
          type="text"
          :value="form.game_id"
          @input="handleGameIdInput"
          class="custom-input"
          :class="{'border-rose-200 bg-rose-50/30': showGameIdWarning || !gameIdText}"
          inputmode="numeric"
          pattern="[0-9]*"
          placeholder="请输入数字短编号"
          :disabled="isReadonly('game_id')"
        />
      </div>
      <div v-if="isVisible('stars')" class="form-group">
        <label>星级 <span :class="reviewMode ? 'review-mark' : 'required-mark'">{{ reviewMode ? '请审核' : '必填' }}</span></label>
        <select v-model="form.stars" class="custom-input" :disabled="isReadonly('stars')">
          <option v-for="s in 6" :key="s" :value="s">{{s}} 星</option>
        </select>
      </div>
    </div>
    
    <div class="form-row">
      <div v-if="isVisible('tags')" class="form-group">
        <label>特殊标签 <span :class="reviewMode ? 'review-mark' : 'optional-mark'">{{ reviewMode ? '请审核' : '选填' }}</span></label>
        <input type="text" v-model="form.tags" class="custom-input" placeholder="如: 洛丽塔, 中式古典..." :disabled="isReadonly('tags')" />
      </div>
    </div>

    <div v-if="hasVisibleAttributeFields" class="flex flex-col gap-3 mt-2">
      <div class="attribute-title">需要核对的属性 <span :class="reviewMode ? 'review-mark' : 'required-mark'">{{ reviewMode ? '请审核' : '必填' }}</span></div>
      <template v-for="(pair, index) in ATTRIBUTE_PAIRS" :key="pair.key">
        <div v-if="isVisible(`pair${index + 1}`)" class="grid grid-cols-2 gap-3">
          <select v-model="form[pair.key]" class="custom-input !py-2" :disabled="isReadonly(pair.key)">
            <option v-for="opt in pair.options" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
          </select>
          <select v-model="form[pair.gradeKey]" class="custom-input !py-2 bg-pink-50 text-pink-600 border-pink-200" :disabled="isReadonly(pair.gradeKey)">
            <option v-for="g in GRADE_OPTIONS" :key="g">{{ g }}</option>
          </select>
        </div>
      </template>
    </div>

    <slot name="admin-tips"></slot>

    <div v-if="coreFieldMissingText" class="core-field-hint">
      需补全：{{ coreFieldMissingText }}
    </div>

    <button type="button" class="btn-submit-contrib w-full" @click="handleSubmit" :disabled="isSubmitting">
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
.entry-rule-note { background: #fdf2f8; border: 1.5px solid #fbcfe8; color: #be185d; border-radius: 12px; padding: 8px 10px; font-size: 12px; font-weight: 800; }
.required-mark { color: #e11d48; font-size: 11px; margin-left: 4px; }
.review-mark { color: #7c3aed; font-size: 11px; margin-left: 4px; }
.optional-mark { color: #94a3b8; font-size: 11px; margin-left: 4px; }
.attribute-title { font-size: 12px; font-weight: 900; color: #64748b; padding-left: 2px; }
.core-field-hint { background: #fff1f2; border: 1.5px solid #fecdd3; color: #be123c; border-radius: 12px; padding: 8px 10px; font-size: 12px; font-weight: 800; line-height: 1.5; }
.custom-input, .search-input { width: 100%; border: 2px solid #f1f5f9; border-radius: 12px; padding: 10px 12px; font-size: 14px; font-weight: 800; color: #334155; transition: all 0.2s; outline: none; background: #fff; }
.custom-input:focus, .search-input:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }
.custom-input:disabled, .search-input:read-only { background: #f8fafc; color: #64748b; cursor: not-allowed; }
.searchable-select { position: relative; }
.select-dropdown { position: absolute; z-index: 50; top: 100%; left: 0; right: 0; margin-top: 6px; background: white; border: 1px solid #f1f5f9; border-radius: 12px; box-shadow: 0 10px 25px rgba(0, 0, 0, 0.05); max-height: 200px; overflow-y: auto; padding: 6px; }
.option { padding: 8px 12px; font-size: 13px; font-weight: 800; color: #475569; border-radius: 8px; cursor: pointer; transition: background 0.2s; }
.option:hover { background: #fdf2f8; color: #db2777; }
.empty-option { color: #94a3b8; cursor: default; text-align: center; }
.empty-option:hover { background: transparent; color: #94a3b8; }
.no-suit-option { color: #db2777; background: #fdf2f8; }
.btn-submit-contrib { background: linear-gradient(135deg, #a855f7, #ec4899); color: white; border: none; font-size: 15px; font-weight: 900; padding: 12px; border-radius: 14px; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 15px rgba(236, 72, 153, 0.25); margin-top: 10px; }
.btn-submit-contrib:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(236, 72, 153, 0.35); }
.btn-submit-contrib:disabled { opacity: 0.7; cursor: not-allowed; background: #cbd5e1; box-shadow: none; }
@media (max-width: 768px) { .form-row.three-cols { grid-template-columns: 1fr; gap: 12px; } }
</style>
