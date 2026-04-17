<script setup>
import { ref, reactive, onMounted, computed } from 'vue'
import { supabase } from '@/api/supabase' // 🌟 路径已修正

const props = defineProps({
  fullWardrobeData: { type: Array, required: true }
})

const pendingList = ref([])
const isPendingLoading = ref(false)
const isSubmitting = ref(false)

// 录入表单状态
const newClothes = reactive({
  pendingId: null,
  game_id: '',
  name: '',
  category: '连衣裙',
  stars: 5,
  tags: '',
  pair1: 'simple', grade1: 'S',
  pair2: 'cute', grade2: 'S',
  pair3: 'active', grade3: 'S',
  pair4: 'pure', grade4: 'S',
  pair5: 'cool', grade5: 'S'
})

// 1. 获取审核列表 (带加载状态)
const fetchPendingList = async () => {
  isPendingLoading.value = true
  try {
    const { data } = await supabase.from('pending_clothes').select('*').order('id', { ascending: false })
    pendingList.value = data || []
  } finally {
    isPendingLoading.value = false
  }
}

onMounted(fetchPendingList)

// 2. 快捷填单
const handlePendingItem = (item) => {
  newClothes.name = item.name
  newClothes.pendingId = item.id 
  window.scrollTo({ top: 500, behavior: 'smooth' }) // 丝滑滚动到编辑区
}

// 3. 驳回申请
const rejectPendingItem = async (id) => {
  if (confirm('确定要驳回并删除这条申请吗？')) {
    await supabase.from('pending_clothes').delete().eq('id', id)
    pendingList.value = pendingList.value.filter(item => item.id !== id)
  }
}

// 4. 提交入库逻辑 (包含计算公式)
const submitNewClothes = async () => {
  if (!newClothes.name) return alert('名字是必填项哦！')

  // 查重
  const isDuplicate = props.fullWardrobeData.some(
    item => item.name === newClothes.name && item.category === newClothes.category
  )
  if (isDuplicate) return alert(`❌ 该服装已存在于图鉴中！`)

  isSubmitting.value = true
  try {
    // 自动计算倍率 (沿用之前的核心算法)
    let mul = 1.0
    if (newClothes.category === '连衣裙') mul = 4.0
    else if (newClothes.category.includes('装') || newClothes.category === '上衣') mul = 2.0
    else if (['发型', '外套', '鞋子', '袜子', '妆容', '萤光之灵'].includes(newClothes.category)) mul = 1.0

    const baseScores = { SS: 2500, S: 2000, A: 1500, B: 1000, C: 500, F: 0 }
    const calculatedScores = {
      simple: 0, gorgeous: 0, cute: 0, mature: 0, active: 0, 
      elegant: 0, pure: 0, sexy: 0, cool: 0, warm: 0
    }
    
    // 映射五个属性对
    const pairs = [['pair1', 'grade1'], ['pair2', 'grade2'], ['pair3', 'grade3'], ['pair4', 'grade4'], ['pair5', 'grade5']]
    pairs.forEach(([p, g]) => {
      calculatedScores[newClothes[p]] = baseScores[newClothes[g]] * mul
    })

    const payload = {
      id: `custom_${Date.now()}`,
      game_id: newClothes.game_id || 'N',
      name: newClothes.name,
      category: newClothes.category,
      stars: Number(newClothes.stars),
      scores: calculatedScores,
      tags: newClothes.tags.split(/[,，\s]+/).filter(t => t)
    }

    const { error } = await supabase.from('clothes').insert([payload])
    if (error) throw error

    // 如果是审核通过，删除申请条目
    if (newClothes.pendingId) {
      await supabase.from('pending_clothes').delete().eq('id', newClothes.pendingId)
      pendingList.value = pendingList.value.filter(i => i.id !== newClothes.pendingId)
    }

    alert(`🎉 【${newClothes.name}】录入成功！`)
    // 重置表单
    Object.assign(newClothes, { name: '', game_id: '', tags: '', pendingId: null })
  } catch (err) {
    alert('入库失败：' + err.message)
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div class="admin-container">
    <section class="section-card review-section">
      <div class="section-header">
        <h3 class="purple-title">🔔 待处理申请</h3>
        <span class="badge" v-if="pendingList.length">{{ pendingList.length }} 条待办</span>
      </div>

      <div v-if="isPendingLoading" class="skeleton-list">
        <div v-for="i in 3" :key="i" class="skeleton-item"></div>
      </div>

      <div v-else-if="pendingList.length === 0" class="empty-status">
        ☕ 暂时没有新的申请，喝杯茶休息下吧
      </div>

      <div v-else class="queue-grid">
        <div v-for="item in pendingList" :key="item.id" class="glass-card">
          <span class="item-name">{{ item.name }}</span>
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
          <input type="text" v-model="newClothes.name" placeholder="请输入服装全名" />
        </div>
        <div class="input-group">
          <label>短编号</label>
          <input type="text" v-model="newClothes.game_id" placeholder="如: 001" />
        </div>
        <div class="input-group">
          <label>分类部位</label>
          <select v-model="newClothes.category">
            <option v-for="cat in ['发型','连衣裙','外套','上装','下装','袜子','鞋子','饰品','妆容','萤光之灵']" :key="cat">{{cat}}</option>
          </select>
        </div>
        <div class="input-group">
          <label>稀有度</label>
          <select v-model="newClothes.stars">
            <option v-for="s in 6" :key="s" :value="s">{{s}} 星</option>
          </select>
        </div>
      </div>

      <div class="attr-form-card">
        <p class="card-tip">🎨 属性分值设定 (SS=2500, S=2000...)</p>
        <div class="attr-grid">
          <div class="attr-row" v-for="(pair, idx) in [
            {p:'pair1', g:'grade1', o:[{v:'simple',l:'简约'},{v:'gorgeous',l:'华丽'}]},
            {p:'pair2', g:'grade2', o:[{v:'cute',l:'可爱'},{v:'mature',l:'成熟'}]},
            {p:'pair3', g:'grade3', o:[{v:'active',l:'活泼'},{v:'elegant',l:'优雅'}]},
            {p:'pair4', g:'grade4', o:[{v:'pure',l:'清纯'},{v:'sexy',l:'性感'}]},
            {p:'pair5', g:'grade5', o:[{v:'cool',l:'清凉'},{v:'warm',l:'保暖'}]}
          ]" :key="idx">
            <select v-model="newClothes[pair.p]" class="attr-select">
              <option :value="pair.o[0].v">{{pair.o[0].l}}</option>
              <option :value="pair.o[1].v">{{pair.o[1].l}}</option>
            </select>
            <select v-model="newClothes[pair.g]" class="grade-select">
              <option v-for="g in ['SS','S','A','B','C','F']" :key="g">{{g}}</option>
            </select>
          </div>
        </div>
      </div>

      <div class="input-group full-width">
        <label>特殊标签 (用逗号隔开)</label>
        <input type="text" v-model="newClothes.tags" placeholder="例如: 洛丽塔, 中式古典, 小动物" />
      </div>

      <button @click="submitNewClothes" class="btn-submit-all" :disabled="isSubmitting">
        {{ isSubmitting ? '⌛ 正在同步云端...' : (newClothes.pendingId ? '✅ 审核通过并发布' : '🚀 全网发布新图鉴') }}
      </button>
    </section>
  </div>
</template>

<style scoped>
.admin-container { animation: fadeIn 0.4s ease; padding-bottom: 50px; }

/* 通用卡片样式 */
.section-card {
  background: white;
  border-radius: 16px;
  padding: 24px;
  margin-bottom: 25px;
  box-shadow: 0 10px 25px rgba(124, 58, 237, 0.05);
  border: 1px solid #f3f4f6;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}

.purple-title {
  color: #7c3aed;
  margin: 0;
  font-size: 18px;
  font-weight: 800;
  border-left: 4px solid #f472b6;
  padding-left: 12px;
}

/* 审核队列样式 */
.queue-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
}

.glass-card {
  background: #f5f3ff;
  border: 1px solid #ddd6fe;
  padding: 12px 16px;
  border-radius: 12px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  transition: transform 0.2s;
}
.glass-card:hover { transform: translateY(-2px); }

.item-name { font-weight: bold; color: #1e1b4b; }

.action-btns { display: flex; gap: 8px; }
.btn-process { background: #7c3aed; color: white; border: none; padding: 6px 12px; border-radius: 6px; cursor: pointer; font-size: 13px; }
.btn-reject { background: #fee2e2; color: #ef4444; border: none; padding: 6px 12px; border-radius: 6px; cursor: pointer; font-size: 13px; }

/* 表单样式 */
.form-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 15px;
  margin-bottom: 20px;
}

.input-group label {
  display: block;
  font-size: 13px;
  color: #6b7280;
  margin-bottom: 6px;
  font-weight: 600;
}

.input-group input, .input-group select {
  width: 100%;
  padding: 10px 12px;
  border: 1.5px solid #e5e7eb;
  border-radius: 10px;
  outline: none;
  transition: all 0.2s;
}

.input-group input:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }

.attr-form-card {
  background: #fdf2f8;
  border-radius: 12px;
  padding: 15px;
  margin-bottom: 20px;
}
.card-tip { font-size: 12px; color: #db2777; margin-top: 0; margin-bottom: 12px; font-weight: bold; }

.attr-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}

.attr-row {
  display: flex;
  background: white;
  border-radius: 8px;
  overflow: hidden;
  border: 1px solid #fbcfe8;
}

.attr-select { flex: 1; border: none; padding: 8px; font-size: 13px; color: #7c3aed; font-weight: bold; }
.grade-select { width: 60px; border: none; border-left: 1px solid #fbcfe8; background: #fff1f2; text-align: center; font-weight: 900; color: #f472b6; }

.btn-submit-all {
  width: 100%;
  padding: 15px;
  background: linear-gradient(135deg, #7c3aed 0%, #f472b6 100%);
  color: white;
  border: none;
  border-radius: 12px;
  font-size: 16px;
  font-weight: 800;
  cursor: pointer;
  box-shadow: 0 4px 15px rgba(124, 58, 237, 0.3);
  transition: all 0.3s;
}
.btn-submit-all:hover { filter: brightness(1.1); transform: translateY(-2px); }
.btn-submit-all:disabled { filter: grayscale(1); cursor: not-allowed; }

/* 骨架屏动画 */
.skeleton-item {
  height: 50px;
  background: linear-gradient(90deg, #f3f4f6 25%, #e5e7eb 50%, #f3f4f6 75%);
  background-size: 200% 100%;
  animation: loading 1.5s infinite;
  border-radius: 8px;
  margin-bottom: 10px;
}

@keyframes loading {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

@media (max-width: 480px) {
  .form-grid, .attr-grid { grid-template-columns: 1fr; }
}
</style>