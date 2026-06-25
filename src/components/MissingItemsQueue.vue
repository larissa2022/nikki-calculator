<script setup>
import { ref, reactive, computed, watch } from 'vue'
import { supabase, logErrorToCloud } from '../api/supabase'
import { calculateItemScores } from '../composables/useScoreEngine'
import { createClothesEntryFormState, normalizeClothingTags } from '../utils/gameConstants'
import ClothesEntryForm from './ClothesEntryForm.vue'



// 1. 接收父组件传递的缺失数组与套装池
// 使用 defineModel 可以让子组件过滤名字时，父组件的统计数据同步更新
const lastNotFoundNames = defineModel({ type: Array, required: true })
// 🌟 把它赋值给 props 变量
const props = defineProps({
  availableSuits: { type: Array, required: true }
})

// 2. 100% 移入原版本所需的独立表单状态
const displayNotFoundNames = computed(() => lastNotFoundNames.value.slice(0, 3))
const activeContribution = ref(null)
const isSubmittingContrib = ref(false)
const suitSearchText = ref('')

const createContributionFormState = (name = '') => createClothesEntryFormState({
  name,
  category: '连衣裙'
})

const contribForm = reactive(createContributionFormState())

watch(activeContribution, (newVal) => {
  suitSearchText.value = ''
  Object.assign(contribForm, createContributionFormState(newVal || ''))
})

// 🌟 新增：玩家点击“一键申请并应用”时的逻辑
const applyShadowSuit = (name) => {
  const cleanName = name.replace(/[《》]/g, '').trim();
  contribForm.suit_id = ''; // 故意留空，触发影子模式
  suitSearchText.value = `《${cleanName}》`;
}

// 🌟 替换：带【智能防重】与【自动自愈刷新】的最终提交逻辑
const submitContribution = async (name) => {
  // ==========================================
  // 🛡️ 第一防线：前端格式拦截
  // ==========================================
  if (!contribForm.game_id || contribForm.game_id.trim() === '') {
    return alert('⚠️ 提交被拦截：短编号为必填项！\n(如果该散件没有短编号，请填写 N)');
  }

  const gameIdStr = contribForm.game_id.trim();
  const typedSuitName = suitSearchText.value.replace(/[《》]/g, '').trim();

  // ==========================================
  // 🛡️ 第二防线：套装名的模糊重复查询 (本地秒级计算)
  // ==========================================
  if (!contribForm.suit_id && typedSuitName) {
    const exactMatch = props.availableSuits.find(s => s.name === typedSuitName);
    if (exactMatch) return alert(`🛑 拦截：套装《${typedSuitName}》已存在！请直接在下拉列表中点击选择，无需新建。`);
    
    const cleanTyped = typedSuitName.replace(/[的之与和·\s]/g, '');
    if (cleanTyped.length >= 2) {
      const fuzzyMatches = props.availableSuits.filter(s => {
        if (!s.name) return false;
        const cleanExist = s.name.replace(/[的之与和·\s]/g, '');
        if (cleanExist === cleanTyped) return true; 
        if (cleanTyped.length >= 3 && cleanExist.length >= 3) {
          return cleanExist.includes(cleanTyped) || cleanTyped.includes(cleanExist);
        }
        return false;
      }).slice(0, 3);
      
      if (fuzzyMatches.length > 0) {
        const matchNames = fuzzyMatches.map(m => `《${m.name}》`).join('、');
        const isConfirmed = confirm(`🤔 疑似套装重复：\n\n您申请的新套装《${typedSuitName}》，数据库中找到了名字相似的：\n${matchNames}\n\n确认这是两套不同的衣服吗？\n点击【确定】继续提交，【取消】则中止。`);
        if (!isConfirmed) return; 
      }
    }
  }

  // 锁住按钮，开始转圈圈
  isSubmittingContrib.value = true;
  
  try {
    // ==========================================
    // 🛡️ 第三防线：云端衣服编号精确查重 
    // ==========================================
    if (gameIdStr.toUpperCase() !== 'N') {
      const { data: existClothes } = await supabase
        .from('clothes')
        .select('name')
        .eq('category', contribForm.category)
        .eq('game_id', gameIdStr)
        .limit(1);
        
      if (existClothes && existClothes.length > 0) {
        isSubmittingContrib.value = false; // 拦截时也要先解锁UI
        return alert(`🛑 撞车拦截：\n分类【${contribForm.category}】的短编号【${gameIdStr}】已被占用！\n数据库中已有该服装：《${existClothes[0].name}》`);
      }
    }

    // ==========================================
    // 🚀 第四防线：10秒超时赛跑机制
    // ==========================================
    const timeoutPromise = new Promise((_, reject) => 
      setTimeout(() => reject(new Error('网络请求超时')), 10000)
    );

    const executeUpload = async () => {
      const { error: authErr } = await supabase.auth.getUser();
      if (authErr) throw new Error('登录校验失败: ' + authErr.message);
      
      const pairs = [
        { attr: contribForm.pair1, grade: contribForm.grade1 },
        { attr: contribForm.pair2, grade: contribForm.grade2 },
        { attr: contribForm.pair3, grade: contribForm.grade3 },
        { attr: contribForm.pair4, grade: contribForm.grade4 },
        { attr: contribForm.pair5, grade: contribForm.grade5 }
      ];
      const calculatedScores = calculateItemScores(contribForm.category, pairs);

      // ... 准备 payload ... (保留原有的 payload 定义)
      // ... 前面生成 payload 的代码保持不变 ...
      const payload = {
        name: contribForm.name || name,
        game_id: gameIdStr.toUpperCase() === 'N' ? 'N' : gameIdStr,
        category: contribForm.category,
        stars: Number(contribForm.stars),
        scores: calculatedScores,
        suit_id: contribForm.suit_id || null,
        temp_suit_name: contribForm.suit_id ? null : (typedSuitName || null),
        tags: normalizeClothingTags(contribForm.tags) || null
      };

      const { error: submitErr } = await supabase.rpc('submit_clothing_contribution', {
        p_name: payload.name,
        p_game_id: payload.game_id,
        p_category: payload.category,
        p_stars: payload.stars,
        p_scores: payload.scores,
        p_suit_id: payload.suit_id,
        p_temp_suit_name: payload.temp_suit_name,
        p_tags: payload.tags
      })

      if (submitErr) throw new Error(submitErr.message)
      return true; 
    };

    // 执行赛跑
    await Promise.race([executeUpload(), timeoutPromise]);

    // ==========================================
    // 🌟 成功：先关掉转圈圈，再弹窗
    // ==========================================
    isSubmittingContrib.value = false; 
    setTimeout(() => {
      alert(`🎉 提交成功！`);
      lastNotFoundNames.value = lastNotFoundNames.value.filter(n => n !== name);
      activeContribution.value = null;
    }, 50); // 延迟 50 毫秒，确保 Vue 已经把动画从屏幕上移除了

  } catch (err) {
    console.error('上传失败详情:', err);
    
    // ==========================================
    // 🌟 失败：强制先关掉转圈圈，防止卡死！
    // ==========================================
    isSubmittingContrib.value = false;
    
    setTimeout(() => {
      // 既然刷新能解决，如果检测到超时或认证失败（僵尸状态），直接提示刷新！
      if (err.message.includes('超时') || err.message.includes('校验失败')) {
        const needRefresh = confirm('⚠️ 页面离开太久，网络连接已休眠！\n\n为确保数据成功录入，需要刷新页面重新激活。是否立即刷新？');
        if (needRefresh) {
          window.location.reload(); // 帮玩家一键刷新网页
        }
      } else {
        alert('❌ 提交失败: ' + err.message);
      }
    }, 50);

    if (typeof logErrorToCloud === 'function') {
      logErrorToCloud('submit_missing_item', err);
    }
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
        <div class="flex justify-between items-center gap-3">
          <span class="font-black text-slate-700 truncate">{{ name }}</span>
          <button
            type="button"
            class="btn btn-xs btn-outline btn-secondary rounded-full shrink-0"
            @click="activeContribution = (activeContribution === name ? null : name)"
          >
            {{ activeContribution === name ? '收起' : '完善资料' }}
          </button>
        </div>

        <Transition name="slide">
          <div v-if="activeContribution === name" class="mt-4 pt-4 border-t border-dashed">
            <ClothesEntryForm
              :form="contribForm"
              v-model:suitSearchText="suitSearchText"
          :availableSuits="props.availableSuits"
          :isSubmitting="isSubmittingContrib"
          submitText="🚀 提交图鉴申请"
          submitLoadingText="正在提交申请..."
          suitNotFoundText="一键申请并应用"
              :showGameIdWarning="true"
              @submit="submitContribution(name)"
              @create-suit="applyShadowSuit"
            />
          </div>
        </Transition>
      </div>

      <div v-if="lastNotFoundNames.length > 3" class="text-center py-2 text-xs font-bold text-slate-400 bg-slate-50 rounded-xl border border-dashed border-slate-200">
        还有 {{ lastNotFoundNames.length - 3 }} 件缺失服装正在排队
      </div>
    </div>
  </div>
</template>
<style scoped>
/* =========================================
   1. 滚动条与基础动画 (基础框架)
   ========================================= */
.custom-scroll::-webkit-scrollbar {
  width: 5px;
}

.custom-scroll::-webkit-scrollbar-thumb {
  background: #e2e8f0;
  border-radius: 10px;
}

.custom-scroll::-webkit-scrollbar-track {
  background: transparent;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.slide-enter-active,
.slide-leave-active {
  transition: opacity 0.2s ease-out, transform 0.2s ease-out;
}

.slide-enter-from,
.slide-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}

/* =========================================
   2. 沉浸式表单样式 (个性化整合)
   ========================================= */
.mini-form-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.form-row {
  display: grid;
  gap: 12px;
}

.form-row.three-cols {
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-group label {
  font-size: 12px;
  font-weight: 800;
  color: #64748b;
  padding-left: 2px;
}

/* 极简风输入框 */
.custom-input {
  width: 100%;
  border: 2px solid #f1f5f9;
  border-radius: 12px;
  padding: 8px 12px;
  font-size: 14px;
  font-weight: 800;
  color: #334155;
  transition: all 0.2s;
  outline: none;
  background: #fff;
}

.custom-input:focus {
  border-color: #f472b6;
  box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1);
}

.custom-input::placeholder {
  color: #cbd5e1;
  font-weight: 600;
}

/* 搜索下拉框体系 */
.searchable-select {
  position: relative;
}

.search-input {
  width: 100%;
  border: 2px solid #f1f5f9;
  border-radius: 12px;
  padding: 8px 12px;
  font-size: 14px;
  font-weight: 800;
  color: #334155;
  outline: none;
  transition: all 0.2s;
  background: #f8fafc;
}

.search-input:focus {
  border-color: #f472b6;
  background: #fff;
}

.select-dropdown {
  position: absolute;
  z-index: 50;
  top: 100%;
  left: 0;
  right: 0;
  margin-top: 6px;
  background: white;
  border: 1px solid #f1f5f9;
  border-radius: 12px;
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.05);
  max-height: 200px;
  overflow-y: auto;
  padding: 6px;
}

.option {
  padding: 8px 12px;
  font-size: 13px;
  font-weight: 800;
  color: #475569;
  border-radius: 8px;
  cursor: pointer;
  transition: background 0.2s;
}

.option:hover {
  background: #fdf2f8;
  color: #db2777;
}

.empty-option {
  color: #94a3b8;
  text-align: center;
  pointer-events: none;
}

/* 个性化按钮 */
.btn-action-outline {
  border: 2px solid #e2e8f0;
  background: transparent;
  color: #64748b;
  font-weight: 800;
  font-size: 13px;
  border-radius: 12px;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-action-outline:hover {
  border-color: #f472b6;
  color: #f472b6;
  background: #fdf2f8;
}

.btn-submit-contrib {
  background: linear-gradient(135deg, #a855f7, #ec4899);
  color: white;
  border: none;
  font-size: 15px;
  font-weight: 900;
  padding: 12px;
  border-radius: 14px;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 4px 15px rgba(236, 72, 153, 0.25);
  margin-top: 10px;
}

.btn-submit-contrib:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 20px rgba(236, 72, 153, 0.35);
}

.btn-submit-contrib:disabled {
  opacity: 0.7;
  cursor: not-allowed;
  background: #cbd5e1;
  box-shadow: none;
}

/* =========================================
   3. 移动端响应式修正
   ========================================= */
@media (max-width: 768px) {
  .form-row.three-cols {
    grid-template-columns: 1fr;
    gap: 12px;
  }
}
</style>
