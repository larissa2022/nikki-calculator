<script setup>
import { ref, reactive, onMounted, computed } from 'vue'
import { supabase } from '@/api/supabase'

const props = defineProps({
  fullWardrobeData: { type: Array, required: true }
})

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

// ====== 🌟 状态管理 ======
const activeTab = ref('audit')        // 标签页切换：'audit' (审核) | 'users' (超管用户管理)
const currentUserRole = ref('user')   // 当前登录者的权限级别
const allUsersList = ref([])          // 全站用户列表

const pendingList = ref([])           
const pendingSuitsList = ref([])      
const suitList = ref([])              
const isPendingLoading = ref(false)
const isSubmitting = ref(false)

const suitSearchText = ref('')        
const isSuitDropdownOpen = ref(false) 

const newClothes = reactive({
  pendingId: null, suit_id: '', game_id: '', name: '', category: '发型', stars: 5, tags: '',
  pair1: 'simple', grade1: '完美', pair2: 'cute', grade2: '完美', pair3: 'active', grade3: '完美', pair4: 'pure', grade4: '完美', pair5: 'cool', grade5: '完美'
})

const filteredSuits = computed(() => {
  const query = suitSearchText.value.toLowerCase().trim()
  if (!query) return suitList.value
  return suitList.value.filter(s => s.name.toLowerCase().includes(query))
})

const selectSuit = (suit) => {
  newClothes.suit_id = suit.id
  suitSearchText.value = suit.id ? `《${suit.name}》` : ''
  isSuitDropdownOpen.value = false
}

// ====== 💾 极速数据加载架构 ======
const fetchAllData = async () => {
  isPendingLoading.value = true
  try {
    // 1. 获取当前操作人的身份权限
    const { data: { user } } = await supabase.auth.getUser()
    if (user) {
      const { data: profile } = await supabase.from('profiles').select('role').eq('id', user.id).single()
      if (profile) currentUserRole.value = profile.role
    }

    // 2. 拉取审核列表
    const [clothesRes, pendingSuitsRes] = await Promise.all([
      supabase.from('pending_clothes').select('*, suits(name)').eq('status', 'pending').order('id', { ascending: false }).limit(50),
      supabase.from('pending_suits').select('*').eq('status', 'pending').order('created_at', { ascending: false }).limit(50)
    ])
    pendingList.value = clothesRes.data || []
    pendingSuitsList.value = pendingSuitsRes.data || []

    // 3. 如果是超管，额外拉取所有用户档案
    if (currentUserRole.value === 'super_admin') {
      const { data: usersData } = await supabase.from('profiles').select('*').order('created_at', { ascending: false })
      allUsersList.value = usersData || []
    }
  } finally {
    isPendingLoading.value = false 
  }
}

const fetchSuits = async () => {
  const { data } = await supabase.from('suits').select('id, name').order('name')
  if (data) suitList.value = data
}

onMounted(() => {
  fetchAllData()
  fetchSuits()
})

// ====== 👑 超级管理员专属：修改权限 ======
const changeUserRole = async (userId, newRole) => {
  const { error } = await supabase.from('profiles').update({ role: newRole }).eq('id', userId)
  if (error) alert('权限修改失败：' + error.message)
  else alert('✨ 权限变更成功！')
}

const formatDate = (dateString) => {
  const d = new Date(dateString)
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`
}

// ====== ✍️ 审核与入库逻辑 (保持原样) ======
const handlePendingItem = (item) => {
  newClothes.name = item.name; newClothes.pendingId = item.id;
  newClothes.suit_id = item.suit_id || ''; newClothes.game_id = item.game_id || '';
  newClothes.tags = item.tags ? (Array.isArray(item.tags) ? item.tags.join(', ') : item.tags) : '';

  const matchedSuit = suitList.value.find(s => s.id === item.suit_id)
  suitSearchText.value = matchedSuit ? `《${matchedSuit.name}》` : ''

  if (item.category) newClothes.category = item.category;
  if (item.stars) newClothes.stars = item.stars;

  if (item.scores) {
    const broadCat = getBroadCat(newClothes.category);
    const matrix = baseScoreMatrix[broadCat] || baseScoreMatrix['饰品'];

    const getGrade = (val) => {
      if (!val || val <= 0) return '失败';
      let closestGrade = '一般';
      let minDiff = Infinity;
      for (const [grade, score] of Object.entries(matrix)) {
        if (grade === '失败') continue;
        const diff = Math.abs(val - score);
        if (diff < minDiff) { minDiff = diff; closestGrade = grade; }
      }
      return closestGrade;
    };

    const s = item.scores;
    newClothes.pair1 = (s.gorgeous || 0) > (s.simple || 0) ? 'gorgeous' : 'simple'; newClothes.grade1 = getGrade(Math.max(s.gorgeous||0, s.simple||0));
    newClothes.pair2 = (s.mature || 0) > (s.cute || 0) ? 'mature' : 'cute'; newClothes.grade2 = getGrade(Math.max(s.mature||0, s.cute||0));
    newClothes.pair3 = (s.elegant || 0) > (s.active || 0) ? 'elegant' : 'active'; newClothes.grade3 = getGrade(Math.max(s.elegant||0, s.active||0));
    newClothes.pair4 = (s.sexy || 0) > (s.pure || 0) ? 'sexy' : 'pure'; newClothes.grade4 = getGrade(Math.max(s.sexy||0, s.pure||0));
    newClothes.pair5 = (s.warm || 0) > (s.cool || 0) ? 'warm' : 'cool'; newClothes.grade5 = getGrade(Math.max(s.warm||0, s.cool||0));
  }
  window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
};

const approvePendingSuit = async (item) => {
  try {
    const { error: suitErr } = await supabase.from('suits').upsert({ name: item.name }, { onConflict: 'name' })
    if (suitErr) throw suitErr
    await supabase.from('pending_suits').update({ status: 'approved' }).eq('id', item.id)
    alert(`✅ 套装【${item.name}】已批准建档！`)
    fetchAllData(); fetchSuits();
  } catch (err) { alert('操作失败：' + err.message) }
}

const rejectPendingSuit = async (id) => {
  if (confirm('确定要驳回这个套装申请吗？')) {
    await supabase.from('pending_suits').update({ status: 'rejected' }).eq('id', id)
    fetchAllData()
  }
}

const rejectPendingItem = async (id) => {
  if (confirm('确定要驳回并删除这条散件申请吗？')) {
    await supabase.from('pending_clothes').update({ status: 'rejected' }).eq('id', id)
    pendingList.value = pendingList.value.filter(item => item.id !== id) 
  }
}

const submitNewClothes = async () => {
  if (!newClothes.name) return alert('名字是必填项哦！')
  isSubmitting.value = true
  try {
    const broadCat = getBroadCat(newClothes.category);
    const matrix = baseScoreMatrix[broadCat] || baseScoreMatrix['饰品'];

    const calculatedScores = {}
    const pairs = [['pair1', 'grade1'], ['pair2', 'grade2'], ['pair3', 'grade3'], ['pair4', 'grade4'], ['pair5', 'grade5']]
    pairs.forEach(([p, g]) => {
      calculatedScores[newClothes[p]] = matrix[newClothes[g]] || 0;
    })

    const payload = {
      id: `custom_${Date.now()}`, game_id: newClothes.game_id || 'N', name: newClothes.name,
      category: newClothes.category, stars: Number(newClothes.stars), scores: calculatedScores,
      suit_id: newClothes.suit_id || null, tags: newClothes.tags.split(/[,，\s]+/).filter(t => t)
    }

    const { error } = await supabase.from('clothes').insert([payload])
    if (error) throw error

    if (newClothes.pendingId) {
      await supabase.from('pending_clothes').update({ status: 'approved' }).eq('id', newClothes.pendingId)
    }

    alert(`🎉 【${newClothes.name}】入库成功！`)
    Object.assign(newClothes, { name: '', game_id: '', tags: '', suit_id: '', pendingId: null })
    suitSearchText.value = ''
    fetchAllData() 
  } catch (err) { alert('入库失败：' + err.message) } 
  finally { isSubmitting.value = false }
}
</script>

<template>
  <div class="admin-container">
    <div class="admin-nav-tabs">
      <button :class="{ active: activeTab === 'audit' }" @click="activeTab = 'audit'">📋 图鉴审核中心</button>
      <button v-if="currentUserRole === 'super_admin'" :class="{ active: activeTab === 'users' }" @click="activeTab = 'users'">👑 全站用户与权限</button>
    </div>

    <div v-show="activeTab === 'audit'">
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
          <div v-for="i in 3" :key="i" class="skeleton-item">加载中...</div>
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
              <input type="text" v-model="suitSearchText" @focus="isSuitDropdownOpen = true" @blur="setTimeout(() => isSuitDropdownOpen = false, 200)" placeholder="🔍 搜索并选择套装..." class="search-input" />
              <Transition name="slide">
                <div v-if="isSuitDropdownOpen" class="select-dropdown">
                  <div class="option" @click="selectSuit({id: '', name: ''})">-- 纯散件 (无关联套装) --</div>
                  <div v-for="s in filteredSuits" :key="s.id" class="option" @click="selectSuit(s)">《{{ s.name }}》</div>
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
          <p class="card-tip">🎨 属性分值设定 (基于分类自动匹配官方原版数据)</p>
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

    <div v-show="activeTab === 'users' && currentUserRole === 'super_admin'">
      <section class="section-card user-section">
        <div class="section-header">
          <h3 class="purple-title">👥 全站玩家档案库</h3>
          <span class="badge">总人数：{{ allUsersList.length }}</span>
        </div>
        
        <div class="users-table-container">
          <table class="users-table">
            <thead>
              <tr>
                <th>注册时间</th>
                <th>玩家账号 (邮箱)</th>
                <th>系统身份</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="u in allUsersList" :key="u.id">
                <td class="time-col">{{ formatDate(u.created_at) }}</td>
                <td class="email-col"><strong>{{ u.email }}</strong></td>
                <td>
                  <span class="role-badge" :class="u.role">{{ u.role === 'super_admin' ? '👑 站长' : (u.role === 'admin' ? '🛡️ 管理员' : '玩家') }}</span>
                </td>
                <td>
                  <select 
                    v-if="u.role !== 'super_admin'" 
                    class="role-select" 
                    :value="u.role" 
                    @change="changeUserRole(u.id, $event.target.value)"
                  >
                    <option value="user">普通玩家</option>
                    <option value="admin">管理员 (可审核图鉴)</option>
                  </select>
                  <span v-else class="protected-text">不可更改</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>

  </div>
</template>

<style scoped>
/* 🌟 新增：顶部导航卡样式 */
.admin-nav-tabs { display: flex; gap: 15px; margin-bottom: 25px; padding: 0 5px;}
.admin-nav-tabs button { flex: 1; padding: 14px; background: white; border: 2px solid #f1f5f9; border-radius: 14px; font-size: 15px; font-weight: 900; color: #64748b; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 10px rgba(0,0,0,0.02);}
.admin-nav-tabs button.active { border-color: #f472b6; color: #db2777; background: #fdf2f8; box-shadow: 0 6px 15px rgba(244, 114, 182, 0.15);}

/* 🌟 新增：用户表格样式 */
.users-table-container { overflow-x: auto; background: white; border: 1px solid #f1f5f9; border-radius: 12px; }
.users-table { width: 100%; border-collapse: collapse; text-align: left; font-size: 13px;}
.users-table th { background: #f8fafc; padding: 12px 15px; color: #64748b; font-weight: 900; border-bottom: 2px solid #e2e8f0; }
.users-table td { padding: 12px 15px; border-bottom: 1px solid #f1f5f9; color: #334155; vertical-align: middle;}
.time-col { color: #94a3b8; font-family: monospace; }
.email-col { color: #1e293b; }

.role-badge { padding: 4px 10px; border-radius: 8px; font-size: 11px; font-weight: 800; display: inline-block;}
.role-badge.user { background: #f1f5f9; color: #64748b; }
.role-badge.admin { background: #ecfdf5; color: #10b981; border: 1px solid #a7f3d0;}
.role-badge.super_admin { background: #fef2f2; color: #ef4444; border: 1px solid #fecaca;}

.role-select { padding: 6px 10px; border: 1.5px solid #e2e8f0; border-radius: 8px; background: #f8fafc; font-weight: bold; color: #475569; outline: none; cursor: pointer;}
.role-select:focus { border-color: #a855f7; }
.protected-text { font-size: 11px; color: #cbd5e1; font-weight: bold; }

/* 保持原有搜索下拉和表单样式不变... */
.searchable-select { position: relative; width: 100%; }
.search-input { width: 100%; padding: 10px 12px; border: 2px solid #e5e7eb; border-radius: 10px; outline: none; font-weight: bold; background: #fff; cursor: text; box-sizing: border-box;}
.search-input:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }

.select-dropdown { position: absolute; top: 100%; left: 0; right: 0; margin-top: 5px; background: white; border: 1.5px solid #fbcfe8; border-radius: 12px; max-height: 250px; overflow-y: auto; z-index: 1000; box-shadow: 0 10px 25px rgba(0,0,0,0.1); }
.option { padding: 12px 15px; cursor: pointer; font-size: 13px; color: #4b5563; transition: all 0.2s; border-bottom: 1px solid #f1f5f9; }
.option:last-child { border-bottom: none; }
.option:hover { background: #fdf2f8; color: #db2777; font-weight: bold; }
.empty-option { text-align: center; color: #94a3b8; padding: 20px; font-style: italic; pointer-events: none; }

.admin-container { padding-bottom: 50px; animation: fadeIn 0.4s ease; }
.section-card { background: white; border-radius: 16px; padding: 24px; margin-bottom: 25px; box-shadow: 0 10px 25px rgba(124,58,237,0.05); border: 1px solid #f3f4f6; }
.section-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
.purple-title { color: #7c3aed; font-size: 18px; font-weight: 900; border-left: 4px solid #f472b6; padding-left: 12px; margin:0;}
.badge { font-size: 12px; padding: 4px 10px; border-radius: 10px; background: #f3f4f6; color: #64748b; font-weight: bold; }

.queue-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px; }
.glass-card { background: #f5f3ff; border: 1px solid #ddd6fe; padding: 15px; border-radius: 14px; display: flex; justify-content: space-between; align-items: center; }
.item-info-meta { display: flex; flex-direction: column; gap: 6px; }
.item-name { font-weight: 800; color: #1e1b4b; font-size: 15px; }
.suit-tag { font-size: 11px; color: #db2777; background: #fdf2f8; padding: 2px 6px; border-radius: 6px; font-weight: bold; }

.action-btns { display: flex; gap: 8px; }
.btn-process { background: #7c3aed; color: white; border: none; padding: 8px 14px; border-radius: 10px; font-weight: bold; cursor: pointer; font-size: 13px; }
.btn-process-green { background: #10b981; color: white; border: none; padding: 8px 14px; border-radius: 10px; font-weight: bold; cursor: pointer; font-size: 13px; }
.btn-reject { background: white; color: #ef4444; border: 1.5px solid #fecaca; padding: 8px 14px; border-radius: 10px; font-weight: bold; cursor: pointer; font-size: 13px; }

.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-bottom: 20px; }
.input-group label { display: block; font-size: 13px; color: #64748b; font-weight: 800; margin-bottom: 6px; }
.input-group input, .input-group select { width: 100%; padding: 10px 12px; border: 2px solid #e5e7eb; border-radius: 10px; outline: none; font-weight: bold; box-sizing: border-box;}
.input-group input:focus, .input-group select:focus { border-color: #f472b6; }

.attr-form-card { background: #fdf2f8; border-radius: 16px; padding: 20px; margin-bottom: 20px; border: 1px dashed #fbcfe8; }
.card-tip { font-size: 12px; color: #db2777; font-weight: 800; margin-bottom: 15px; }
.attr-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.attr-row { display: flex; background: white; border-radius: 10px; border: 1.5px solid #fbcfe8; overflow: hidden; }
.attr-select { flex: 1; border: none; padding: 10px; font-weight: 900; color: #7c3aed; outline: none; font-size: 14px; }
.grade-select { width: 80px; border: none; border-left: 1.5px dashed #fbcfe8; background: #fff1f2; text-align: center; font-weight: 900; color: #f472b6; cursor: pointer; outline: none; }

.btn-submit-all { width: 100%; padding: 16px; background: linear-gradient(135deg, #7c3aed 0%, #f472b6 100%); color: white; border: none; border-radius: 14px; font-size: 16px; font-weight: 900; cursor: pointer; box-shadow: 0 4px 15px rgba(124,58,237,0.3); }
.btn-submit-all:hover { filter: brightness(1.1); transform: translateY(-1px); }

.slide-enter-active { transition: all 0.3s ease-out; }
.slide-enter-from { opacity: 0; transform: translateY(-10px); }
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }

/* 📱 手机端专属：后台管理面板适配 */
@media (max-width: 768px) {
  .admin-container {
    padding: 10px;
  }

  /* 1. 顶部导航按钮并排改换行，或者缩小字号 */
  .admin-nav-tabs {
    flex-direction: column;
    gap: 10px;
  }
  .admin-nav-tabs button {
    padding: 12px;
    font-size: 14px;
  }

  /* 2. 表单区的双列/多列 强制变成单列瀑布流 */
  .form-grid {
    grid-template-columns: 1fr; /* 一行只放一个输入框 */
    gap: 12px;
  }
  
  .attr-grid {
    grid-template-columns: 1fr; /* 5个属性分值排成一列 */
  }

  /* 3. 卡片内边距缩小，留出更多可视空间 */
  .section-card {
    padding: 16px;
  }

  /* 4. 拯救超管表格：防止表格撑破屏幕 */
  .users-table-container {
    overflow-x: auto; /* 允许表格在手机上左右滑动！极其重要！ */
    -webkit-overflow-scrolling: touch; /* 让滑动像丝般顺滑 */
  }
  .users-table {
    min-width: 500px; /* 强制表格保持最小宽度，超出就滑动 */
  }

  /* 5. 调整操作按钮 */
  .action-btns {
    flex-direction: column; /* 按钮上下排布防止拥挤 */
    width: 100%;
  }
  .action-btns button {
    width: 100%;
    margin-top: 5px;
  }
}
</style>