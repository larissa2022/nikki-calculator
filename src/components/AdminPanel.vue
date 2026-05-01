<script setup>
import { ref, reactive, onMounted, computed } from 'vue'
import { supabase } from '@/api/supabase'

const props = defineProps({
  fullWardrobeData: { type: Array, required: true }
})

// ====== 🌟 状态管理 ======
const pendingList = ref([])           // 待审核散件
const pendingSuitsList = ref([])      // 待审核套装申请
const suitList = ref([])              // 已有套装列表
const isPendingLoading = ref(false)
const isSubmitting = ref(false)
// ====== 🌟 核心：官方全品类数据字典 ======
const baseScoreMatrix = {
  '发型': { '完美+': 1324.5, '完美': 1089, '优秀': 837, '不错': 682.5, '一般': 517.5, '失败': 0 },
  '连衣裙': { '完美+': 5269.5, '完美': 4305, '优秀': 3366, '不错': 2749.5, '一般': 2100, '失败': 0 },
  '外套': { '完美+': 525, '完美': 423, '优秀': 331.5, '不错': 270, '一般': 213, '失败': 0 },
  '上装': { '完美+': 2619, '完美': 2140.5, '优秀': 1678.5, '不错': 1369.5, '一般': 1041, '失败': 0 },
  '下装': { '完美+': 2632.5, '完美': 2137.5, '优秀': 1678.5, '不错': 1357.5, '一般': 1041, '失败': 0 },
  '袜子': { '完美+': 789, '完美': 648, '优秀': 502.5, '不错': 403.5, '一般': 305, '失败': 0 },
  '鞋子': { '完美+': 1050, '完美': 855, '优秀': 667.5, '不错': 541.5, '一般': 423, '失败': 0 },
  '饰品': { '完美+': 526.5, '完美': 424.5, '优秀': 330, '不错': 271.5, '一般': 213, '失败': 0 },
  '妆容': { '完美+': 267, '完美': 213, '优秀': 168, '不错': 125, '一般': 85, '失败': 0 },
  '萤光之灵': { '完美+': 517.5, '完美': 421.5, '优秀': 325.5, '不错': 264, '一般': 200, '失败': 0 }
};

const getBroadCat = (cat) => {
  if (!cat) return '饰品';
  if (cat.includes('袜子')) return '袜子';
  if (cat.includes('饰品')) return '饰品';
  if (cat.includes('上')) return '上装';
  if (cat.includes('下')) return '下装';
  return cat;
};

// 🌟 新增：搜索选择器状态
const suitSearchText = ref('')        // 搜索框输入的文字
const isSuitDropdownOpen = ref(false) // 下拉列表显隐

// 录入表单状态
const newClothes = reactive({
  pendingId: null,
  suit_id: '',
  game_id: '',
  name: '',
  category: '发型',
  stars: 5,
  tags: '',
  pair1: 'simple', grade1: '完美',
  pair2: 'cute', grade2: '完美',
  pair3: 'active', grade3: '完美',
  pair4: 'pure', grade4: '完美',
  pair5: 'cool', grade5: '完美'
})

// ====== 🌟 搜索逻辑：计算过滤后的套装列表 ======
const filteredSuits = computed(() => {
  const query = suitSearchText.value.toLowerCase().trim()
  if (!query) return suitList.value
  return suitList.value.filter(s => s.name.toLowerCase().includes(query))
})

// 🌟 选择套装动作
const selectSuit = (suit) => {
  newClothes.suit_id = suit.id
  suitSearchText.value = suit.id ? `《${suit.name}》` : ''
  isSuitDropdownOpen.value = false
}

// ====== 💾 数据加载 ======
// ====== 💾 极速数据加载架构 ======
const fetchPending = async () => {
  isPendingLoading.value = true
  try {
    const [clothesRes, pendingSuitsRes] = await Promise.all([
      // 🌟 加上 limit(50)，只取最新 50 条，防止历史积压导致页面卡死
      supabase.from('pending_clothes').select('*, suits(name)').eq('status', 'pending').order('id', { ascending: false }).limit(50),
      supabase.from('pending_suits').select('*').eq('status', 'pending').order('created_at', { ascending: false }).limit(50)
    ])
    
    pendingList.value = clothesRes.data || []
    pendingSuitsList.value = pendingSuitsRes.data || []
  } finally {
    isPendingLoading.value = false // 此时骨架屏消失，列表瞬间展示！
  }
}

const fetchSuits = async () => {
  // 🌟 后台静默加载几千个套装供搜索框使用，绝不阻塞界面渲染
  const { data } = await supabase.from('suits').select('id, name').order('name')
  if (data) suitList.value = data
}

onMounted(() => {
  fetchPending()
  fetchSuits()
})

// ====== ✍️ 审核与入库逻辑 ======
const handlePendingItem = (item) => {
  newClothes.name = item.name;
  newClothes.pendingId = item.id;
  newClothes.suit_id = item.suit_id || '';
  newClothes.game_id = item.game_id || '';
  
  
  if (item.tags) {
    newClothes.tags = Array.isArray(item.tags) ? item.tags.join(', ') : item.tags;
  } else {
    newClothes.tags = '';
  }

  const matchedSuit = suitList.value.find(s => s.id === item.suit_id)
  suitSearchText.value = matchedSuit ? `《${matchedSuit.name}》` : ''

  if (item.category) newClothes.category = item.category;
  if (item.stars) newClothes.stars = item.stars;

  // 3. 🌟 核心：逆向还原属性分值
  if (item.scores) {
    const broadCat = getBroadCat(newClothes.category);
    const matrix = baseScoreMatrix[broadCat] || baseScoreMatrix['饰品'];

    // 🌟 物理吸附解码：拿数值去字典里对比，谁的差值最小，就是哪个评级！
    const getGrade = (val) => {
      if (!val || val <= 0) return '失败';
      let closestGrade = '一般';
      let minDiff = Infinity;
      for (const [grade, score] of Object.entries(matrix)) {
        if (grade === '失败') continue;
        const diff = Math.abs(val - score);
        if (diff < minDiff) {
          minDiff = diff;
          closestGrade = grade;
        }
      }
      return closestGrade;
    };

    const s = item.scores;
    if ((s.gorgeous || 0) > (s.simple || 0)) { newClothes.pair1 = 'gorgeous'; newClothes.grade1 = getGrade(s.gorgeous); }
    else { newClothes.pair1 = 'simple'; newClothes.grade1 = getGrade(s.simple || 0); }
    if ((s.mature || 0) > (s.cute || 0)) { newClothes.pair2 = 'mature'; newClothes.grade2 = getGrade(s.mature); }
    else { newClothes.pair2 = 'cute'; newClothes.grade2 = getGrade(s.cute || 0); }
    if ((s.elegant || 0) > (s.active || 0)) { newClothes.pair3 = 'elegant'; newClothes.grade3 = getGrade(s.elegant); }
    else { newClothes.pair3 = 'active'; newClothes.grade3 = getGrade(s.active || 0); }
    if ((s.sexy || 0) > (s.pure || 0)) { newClothes.pair4 = 'sexy'; newClothes.grade4 = getGrade(s.sexy); }
    else { newClothes.pair4 = 'pure'; newClothes.grade4 = getGrade(s.pure || 0); }
    if ((s.warm || 0) > (s.cool || 0)) { newClothes.pair5 = 'warm'; newClothes.grade5 = getGrade(s.warm); }
    else { newClothes.pair5 = 'cool'; newClothes.grade5 = getGrade(s.cool || 0); }
  }
  
  window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
};

const approvePendingSuit = async (item) => {
  try {
    const { error: suitErr } = await supabase.from('suits').upsert({ name: item.name }, { onConflict: 'name' })
    if (suitErr) throw suitErr
    await supabase.from('pending_suits').update({ status: 'approved' }).eq('id', item.id)
    alert(`✅ 套装【${item.name}】已批准建档！`)
    // 🌟 只有审核了新套装，才需要重新拉取套装字典
    fetchPending() 
    fetchSuits()
  } catch (err) {
    alert('操作失败：' + err.message)
  }
}

const rejectPendingSuit = async (id) => {
  if (confirm('确定要驳回这个套装申请吗？')) {
    await supabase.from('pending_suits').update({ status: 'rejected' }).eq('id', id)
    fetchPending() // 只刷新列表
  }
}

const rejectPendingItem = async (id) => {
  if (confirm('确定要驳回并删除这条散件申请吗？')) {
    await supabase.from('pending_clothes').update({ status: 'rejected' }).eq('id', id)
    pendingList.value = pendingList.value.filter(item => item.id !== id) // 瞬间移除，无需网络请求
  }
}

const submitNewClothes = async () => {
  if (!newClothes.name) return alert('名字是必填项哦！')
  isSubmitting.value = true
  try {
    let mul = 1.0
    if (newClothes.category === '连衣裙') mul = 4.0
    else if (newClothes.category.includes('装') || newClothes.category === '上衣') mul = 2.0

    const broadCat = getBroadCat(newClothes.category);
    const matrix = baseScoreMatrix[broadCat] || baseScoreMatrix['饰品'];

    const calculatedScores = {}
    const pairs = [['pair1', 'grade1'], ['pair2', 'grade2'], ['pair3', 'grade3'], ['pair4', 'grade4'], ['pair5', 'grade5']]
    pairs.forEach(([p, g]) => {
      calculatedScores[newClothes[p]] = matrix[newClothes[g]] || 0;
    })

    const payload = {
      id: `custom_${Date.now()}`,
      game_id: newClothes.game_id || 'N',
      name: newClothes.name,
      category: newClothes.category,
      stars: Number(newClothes.stars),
      scores: calculatedScores,
      suit_id: newClothes.suit_id || null,
      tags: newClothes.tags.split(/[,，\s]+/).filter(t => t)
    }

    const { error } = await supabase.from('clothes').insert([payload])
    if (error) throw error

    if (newClothes.pendingId) {
      await supabase.from('pending_clothes').update({ status: 'approved' }).eq('id', newClothes.pendingId)
    }

    alert(`🎉 【${newClothes.name}】入库成功！`)
    resetForm()
    fetchPending() // 🌟 仅刷新列表，不再重复下载几千个套装！
  } catch (err) {
    alert('入库失败：' + err.message)
  } finally {
    isSubmitting.value = false
  }
}

const resetForm = () => {
  Object.assign(newClothes, { name: '', game_id: '', tags: '', suit_id: '', pendingId: null })
  suitSearchText.value = ''
}
</script>

<template>
  <div class="admin-container">
    
    <section class="section-card review-section">
      <div v-if="pendingSuitsList.length > 0" class="suits-review-zone">
        <div class="section-header">
          <h3 class="purple-title">🎁 套装建档申请</h3>
          <span class="badge">{{ pendingSuitsList.length }} 条</span>
        </div>
        <div class="queue-grid">
          <div v-for="item in pendingSuitsList" :key="item.id" class="glass-card suit-item">
            <span class="item-name">《{{ item.name }}》</span>
            <div class="action-btns">
              <button @click="approvePendingSuit(item)" class="btn-process-green">批准</button>
              <button @click="rejectPendingSuit(item.id)" class="btn-reject">驳回</button>
            </div>
          </div>
        </div>
      </div>

      <div class="section-header">
        <h3 class="purple-title">🔔 散件属性审核</h3>
        <span class="badge" v-if="pendingList.length">{{ pendingList.length }} 条待办</span>
      </div>

      <div v-if="isPendingLoading" class="skeleton-list">
        <div v-for="i in 3" :key="i" class="skeleton-item"></div>
      </div>

      <div v-else-if="pendingList.length === 0 && pendingSuitsList.length === 0" class="empty-status">
        ☕ 暂时没有新的申请
      </div>

      <div v-else class="queue-grid">
        <div v-for="item in pendingList" :key="item.id" class="glass-card">
          <div class="item-info-meta">
            <span class="item-name">{{ item.name }}</span>
            <span v-if="item.suits?.name" class="suit-tag">归属：{{ item.suits.name }}</span>
          </div>
          <div class="action-btns">
            <button @click="handlePendingItem(item)" class="btn-process">✍️ 处理</button>
            <button @click="rejectPendingItem(item.id)" class="btn-reject">驳回</button>
          </div>
        </div>
      </div>
    </section>

    <section class="section-card form-section">
      <div class="section-header">
        <h3 class="purple-title">👑 图鉴云端入库</h3>
        <span v-if="newClothes.pendingId" class="edit-mode-tag">正在处理：{{ newClothes.name }}</span>
      </div>

      <div class="form-grid">
        <div class="input-group">
          <label>服装名称</label>
          <input type="text" v-model="newClothes.name" placeholder="服装全名" />
        </div>

        <div class="input-group">
          <label>关联套装</label>
          <div class="searchable-select">
            <input 
              type="text" 
              v-model="suitSearchText" 
              @focus="isSuitDropdownOpen = true"
              @blur="setTimeout(() => isSuitDropdownOpen = false, 200)"
              placeholder="🔍 搜索并选择套装..."
              class="search-input"
            />
            <Transition name="slide">
              <div v-if="isSuitDropdownOpen" class="select-dropdown">
                <div class="option" @click="selectSuit({id: '', name: ''})">-- 纯散件 (无关联套装) --</div>
                <div 
                  v-for="s in filteredSuits" 
                  :key="s.id" 
                  class="option" 
                  @click="selectSuit(s)"
                >
                  《{{ s.name }}》
                </div>
                <div v-if="filteredSuits.length === 0" class="option empty-option">未找到匹配套装</div>
              </div>
            </Transition>
          </div>
        </div>

        <div class="input-group">
          <label>短编号</label>
          <input type="text" v-model="newClothes.game_id" placeholder="如: 001" />
        </div>
        <div class="input-group">
          <label>分类部位</label>
          <select v-model="newClothes.category">
            <option v-for="cat in ['发型', '连衣裙', '外套', '上装', '下装', '袜子-袜套', '袜子-袜子', '鞋子', '妆容', '萤光之灵', '饰品-头饰-发饰', '饰品-头饰-头纱', '饰品-头饰-发卡', '饰品-头饰-耳朵', '饰品-耳饰', '饰品-颈饰-围巾', '饰品-颈饰-项链', '饰品-手饰-右', '饰品-手饰-左', '饰品-手饰-双', '饰品-手持-右', '饰品-手持-左', '饰品-手持-双', '饰品-腰饰', '饰品-特殊-面饰', '饰品-特殊-胸饰', '饰品-特殊-纹身', '饰品-特殊-翅膀', '饰品-特殊-尾巴', '饰品-特殊-前景', '饰品-特殊-后景', '饰品-特殊-顶饰', '饰品-特殊-地面', '饰品-皮肤']" :key="cat">{{cat}}</option>
          </select>
        </div>
        <div class="input-group">
          <label>星级</label>
          <select v-model="newClothes.stars">
            <option v-for="s in 6" :key="s" :value="s">{{s}} 星</option>
          </select>
        </div>
        <div class="input-group">
          <label>特殊标签</label>
          <input type="text" v-model="newClothes.tags" placeholder="洛丽塔, 中式古典" />
        </div>
      </div>

      <div class="attr-form-card">
        <p class="card-tip">🎨 属性分值设定 (基于分类自动计算倍率)</p>
        <div class="attr-grid">
          <div class="attr-row" v-for="(pair, idx) in [
            {p:'pair1', g:'grade1', o:[{v:'simple',l:'简约'},{v:'gorgeous',l:'华丽'}]},
            {p:'pair2', g:'grade2', o:[{v:'cute',l:'可爱'},{v:'mature',l:'成熟'}]},
            {p:'pair3', g:'grade3', o:[{v:'active',l:'活泼'},{v:'elegant',l:'优雅'}]},
            {p:'pair4', g:'grade4', o:[{v:'pure',l:'清纯'},{v:'sexy',l:'性感'}]},
            {p:'pair5', g:'grade5', o:[{v:'cool',l:'清凉'},{v:'warm',l:'保暖'}]}
          ]" :key="idx">
            <select v-model="newClothes[pair.p]" class="attr-select">
              <option v-for="opt in pair.o" :key="opt.v" :value="opt.v">{{opt.l}}</option>
            </select>
            <select v-model="newClothes[pair.g]" class="grade-select">
              <option v-for="g in ['完美+','完美','优秀','不错','一般','失败']" :key="g">{{g}}</option>
            </select>
          </div>
        </div>
      </div>

      <button @click="submitNewClothes" class="btn-submit-all" :disabled="isSubmitting">
        {{ isSubmitting ? '⌛ 同步中...' : (newClothes.pendingId ? '✅ 审核通过并入库' : '🚀 发布新图鉴') }}
      </button>
    </section>
  </div>
</template>

<style scoped>
/* 🌟 核心：搜索下拉框样式 */
.searchable-select { position: relative; width: 100%; }
.search-input { width: 100%; padding: 10px 12px; border: 2px solid #e5e7eb; border-radius: 10px; outline: none; font-weight: bold; background: #fff; cursor: text; }
.search-input:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }

.select-dropdown {
  position: absolute; top: 100%; left: 0; right: 0; margin-top: 5px;
  background: white; border: 1.5px solid #fbcfe8; border-radius: 12px;
  max-height: 250px; overflow-y: auto; z-index: 1000;
  box-shadow: 0 10px 25px rgba(0,0,0,0.1);
}
.option { padding: 12px 15px; cursor: pointer; font-size: 13px; color: #4b5563; transition: all 0.2s; border-bottom: 1px solid #f1f5f9; }
.option:last-child { border-bottom: none; }
.option:hover { background: #fdf2f8; color: #db2777; font-weight: bold; }
.empty-option { text-align: center; color: #94a3b8; padding: 20px; font-style: italic; pointer-events: none; }

/* 基础排版与卡片样式 */
.admin-container { padding-bottom: 50px; animation: fadeIn 0.4s ease; }
.section-card { background: white; border-radius: 16px; padding: 24px; margin-bottom: 25px; box-shadow: 0 10px 25px rgba(124,58,237,0.05); border: 1px solid #f3f4f6; }
.section-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
.purple-title { color: #7c3aed; font-size: 18px; font-weight: 900; border-left: 4px solid #f472b6; padding-left: 12px; }
.badge { font-size: 12px; padding: 4px 10px; border-radius: 10px; background: #f3f4f6; color: #64748b; font-weight: bold; }

/* 审核列表 */
.queue-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px; }
.glass-card { background: #f5f3ff; border: 1px solid #ddd6fe; padding: 15px; border-radius: 14px; display: flex; justify-content: space-between; align-items: center; }
.item-info-meta { display: flex; flex-direction: column; gap: 6px; }
.item-name { font-weight: 800; color: #1e1b4b; font-size: 15px; }
.suit-tag { font-size: 11px; color: #db2777; background: #fdf2f8; padding: 2px 6px; border-radius: 6px; font-weight: bold; }

.action-btns { display: flex; gap: 8px; }
.btn-process { background: #7c3aed; color: white; border: none; padding: 8px 14px; border-radius: 10px; font-weight: bold; cursor: pointer; font-size: 13px; }
.btn-process-green { background: #10b981; color: white; border: none; padding: 8px 14px; border-radius: 10px; font-weight: bold; cursor: pointer; font-size: 13px; }
.btn-reject { background: white; color: #ef4444; border: 1.5px solid #fecaca; padding: 8px 14px; border-radius: 10px; font-weight: bold; cursor: pointer; font-size: 13px; }

/* 表单输入样式 */
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-bottom: 20px; }
.input-group label { display: block; font-size: 13px; color: #64748b; font-weight: 800; margin-bottom: 6px; }
.input-group input, .input-group select { width: 100%; padding: 10px 12px; border: 2px solid #e5e7eb; border-radius: 10px; outline: none; font-weight: bold; }
.input-group input:focus, .input-group select:focus { border-color: #f472b6; }

/* 属性分值卡片 */
.attr-form-card { background: #fdf2f8; border-radius: 16px; padding: 20px; margin-bottom: 20px; border: 1px dashed #fbcfe8; }
.card-tip { font-size: 12px; color: #db2777; font-weight: 800; margin-bottom: 15px; }
.attr-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.attr-row { display: flex; background: white; border-radius: 10px; border: 1.5px solid #fbcfe8; overflow: hidden; }
.attr-select { flex: 1; border: none; padding: 10px; font-weight: 900; color: #7c3aed; outline: none; font-size: 14px; }
.grade-select { width: 80px; border: none; border-left: 1.5px dashed #fbcfe8; background: #fff1f2; text-align: center; font-weight: 900; color: #f472b6; cursor: pointer; outline: none; }

.btn-submit-all { width: 100%; padding: 16px; background: linear-gradient(135deg, #7c3aed 0%, #f472b6 100%); color: white; border: none; border-radius: 14px; font-size: 16px; font-weight: 900; cursor: pointer; box-shadow: 0 4px 15px rgba(124,58,237,0.3); }
.btn-submit-all:hover { filter: brightness(1.1); transform: translateY(-1px); }

/* 动画与响应式 */
.slide-enter-active { transition: all 0.3s ease-out; }
.slide-enter-from { opacity: 0; transform: translateY(-10px); }
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
@media (max-width: 480px) { .form-grid, .attr-grid { grid-template-columns: 1fr; } }
</style>