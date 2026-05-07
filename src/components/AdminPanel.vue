<script setup>
import { ref, reactive, onMounted, computed, nextTick } from 'vue'
import { supabase } from '../api/supabase'

const emit = defineEmits(['back-to-main']);

// ====== 🌟 1. 官方全品类分值矩阵 ======
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

// ====== 🌟 2. 状态管理 ======
const activeTab = ref('audit')
const currentUserRole = ref('user')
const currentUserId = ref(null)
const allUsersList = ref([])
const pendingList = ref([])           
const pendingSuitsList = ref([])      
const suitList = ref([])              
const isPendingLoading = ref(false)
const isSubmitting = ref(false)
const suitSearchText = ref('')        
const isSuitDropdownOpen = ref(false) 
const userPage = ref(1)
const userPageSize = 10

const newClothes = reactive({
  pendingIds: [], // 🌟 改为数组，存储所有被合并的ID
  suit_id: '', game_id: '', name: '', category: '发型', stars: 5, tags: '',
  pair1: 'simple', grade1: '完美', pair2: 'cute', grade2: '完美', pair3: 'active', grade3: '完美', pair4: 'pure', grade4: '完美', pair5: 'cool', grade5: '完美'
})

// ====== 🌟 3. 数据加载与聚类逻辑 ======
const fetchAllData = async () => {
  isPendingLoading.value = true
  try {
    const { data: { user } } = await supabase.auth.getUser()
    if (user) {
      currentUserId.value = user.id
      const { data: profile } = await supabase.from('profiles').select('role').eq('id', user.id).single()
      if (profile) currentUserRole.value = profile.role
    }

    const [clothesRes, pendingSuitsRes, contribRes] = await Promise.all([
      supabase.from('pending_clothes').select('*, suits(name)').eq('status', 'pending').order('id', { ascending: false }),
      supabase.from('pending_suits').select('*').eq('status', 'pending').order('created_at', { ascending: false }),
      supabase.from('pending_clothes').select('submitted_by').eq('status', 'approved')
    ])
    
    pendingList.value = clothesRes.data || []
    pendingSuitsList.value = pendingSuitsRes.data || []

    const countsMap = {}
    contribRes.data?.forEach(row => { if (row.submitted_by) countsMap[row.submitted_by] = (countsMap[row.submitted_by] || 0) + 1 })

    if (currentUserRole.value === 'super_admin') {
      const { data: usersData } = await supabase.from('profiles').select('*').order('created_at', { ascending: false })
      allUsersList.value = (usersData || []).map(u => ({ ...u, contribCount: countsMap[u.id] || 0 }))
    }
  } finally { isPendingLoading.value = false }
}

// 🌟 核心：聚类算法 (Clustering)
const clusteredPendingList = computed(() => {
  const groups = {};
  pendingList.value.forEach(item => {
    // 聚类钥匙：分类+短编号。如果没有编号，用名字保底
    const key = (item.game_id && item.game_id !== 'N') ? `${item.category}_${item.game_id}` : `NAME_${item.name}`;
    if (!groups[key]) groups[key] = { key, items: [] };
    groups[key].items.push(item);
  });
  return Object.values(groups);
});

// 🌟 辅助：寻找一组数据中的“众数/最准值” (Arbitration)
const getMostFrequent = (arr) => {
  if (!arr.length) return null;
  const counts = {};
  arr.forEach(v => counts[v] = (counts[v] || 0) + 1);
  return Object.keys(counts).reduce((a, b) => counts[a] >= counts[b] ? a : b);
};

// ====== 🌟 4. 处理聚类后的审核申请 ======
const handleClusteredItem = (group) => {
  const items = group.items;
  const userMap = Object.fromEntries(allUsersList.value.map(u => [u.id, u.contribCount]));

  // 1. 基础信息：取第一个或根据权重取
  const bestItem = items.reduce((prev, curr) => (userMap[curr.submitted_by] || 0) > (userMap[prev.submitted_by] || 0) ? curr : prev);
  
  newClothes.pendingIds = items.map(i => i.id);
  newClothes.name = bestItem.name;
  newClothes.game_id = bestItem.game_id || '';
  newClothes.category = bestItem.category;
  newClothes.stars = Number(getMostFrequent(items.map(i => i.stars)));
  newClothes.suit_id = bestItem.suit_id || '';

  // 2. 标签合并 (去重并集)
  const allTags = items.flatMap(i => i.tags ? (Array.isArray(i.tags) ? i.tags : i.tags.split(/[,，\s]+/)) : []).map(t => t.trim());
  newClothes.tags = [...new Set(allTags)].filter(t => t).join(', ');

  // 3. 属性智能算分
  if (bestItem.scores) {
    const matrix = baseScoreMatrix[getBroadCat(newClothes.category)] || baseScoreMatrix['饰品'];
    const getGradeFromScore = (val) => {
      let closest = '一般'; let minDiff = Infinity;
      for (const [g, s] of Object.entries(matrix)) {
        const diff = Math.abs((val||0) - s);
        if (diff < minDiff) { minDiff = diff; closest = g; }
      }
      return closest;
    };

    // 针对每一对属性，收集所有人的意见并取众数
    const attrPairs = [
      { key: 'pair1', gKey: 'grade1', p1: 'simple', p2: 'gorgeous' },
      { key: 'pair2', gKey: 'grade2', p1: 'cute', p2: 'mature' },
      { key: 'pair3', gKey: 'grade3', p1: 'active', p2: 'elegant' },
      { key: 'pair4', gKey: 'grade4', p1: 'pure', p2: 'sexy' },
      { key: 'pair5', gKey: 'grade5', p1: 'cool', p2: 'warm' }
    ];

    attrPairs.forEach(ap => {
      const votes = items.map(i => {
        const s = i.scores || {};
        const p = (s[ap.p1]||0) > (s[ap.p2]||0) ? ap.p1 : ap.p2;
        const g = getGradeFromScore(Math.max(s[ap.p1]||0, s[ap.p2]||0));
        return { p, g };
      });
      newClothes[ap.key] = getMostFrequent(votes.map(v => v.p));
      newClothes[ap.gKey] = getMostFrequent(votes.map(v => v.g));
    });
  }

  const matchedSuit = suitList.value.find(s => s.id === newClothes.suit_id);
  suitSearchText.value = matchedSuit ? `《${matchedSuit.name}》` : '';
  window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
};

// ====== 🌟 5. 最终入库 (批量批准) ======
const submitNewClothes = async () => {
  if (!newClothes.name) return alert('名字是必填项哦！')
  isSubmitting.value = true
  try {
    const matrix = baseScoreMatrix[getBroadCat(newClothes.category)] || baseScoreMatrix['饰品'];
    const calculatedScores = {};
    [['pair1', 'grade1'], ['pair2', 'grade2'], ['pair3', 'grade3'], ['pair4', 'grade4'], ['pair5', 'grade5']].forEach(([p, g]) => {
      calculatedScores[newClothes[p]] = matrix[newClothes[g]] || 0;
    });

    const payload = {
      id: `custom_${Date.now()}`, game_id: newClothes.game_id || 'N', name: newClothes.name,
      category: newClothes.category, stars: Number(newClothes.stars), scores: calculatedScores,
      suit_id: newClothes.suit_id || null, tags: newClothes.tags.split(/[,，\s]+/).filter(t => t)
    };

    const { error } = await supabase.from('clothes').insert([payload]);
    if (error) throw error;
    
    // 🌟 一键通过该聚类下的所有申请
    if (newClothes.pendingIds.length > 0) {
      await supabase.from('pending_clothes').update({ status: 'approved' }).in('id', newClothes.pendingIds);
    }

    alert(`🎉 【${newClothes.name}】已汇聚多方数据并成功入库！`);
    Object.assign(newClothes, { name: '', game_id: '', tags: '', suit_id: '', pendingIds: [] });
    suitSearchText.value = ''; fetchAllData();
  } catch (err) { alert('入库失败：' + err.message) } 
  finally { isSubmitting.value = false }
}

const selectSuit = (suit) => {
  newClothes.suit_id = suit.id
  suitSearchText.value = suit.id ? `《${suit.name}》` : ''
  isSuitDropdownOpen.value = false
}

const filteredSuits = computed(() => {
  const query = suitSearchText.value.toLowerCase().trim();
  if (!query || query.startsWith('《')) return suitList.value.slice(0, 50);
  return suitList.value.filter(s => s.name.includes(query)).slice(0, 50);
})

const adminUsers = computed(() => allUsersList.value.filter(u => u.role !== 'user'))
const regularUsers = computed(() => allUsersList.value.filter(u => u.role === 'user'))
const paginatedRegularUsers = computed(() => {
  const start = (userPage.value - 1) * userPageSize
  return regularUsers.value.slice(start, start + userPageSize)
})
const totalUserPages = computed(() => Math.ceil(regularUsers.value.length / userPageSize))

const fetchSuits = async () => {
  const { data } = await supabase.from('suits').select('id, name').order('name')
  if (data) suitList.value = data
}

onMounted(() => { fetchAllData(); fetchSuits(); })

const changeUserRole = async (uId, role) => {
  await supabase.from('profiles').update({ role }).eq('id', uId);
  alert('权限更新成功！'); fetchAllData();
}
const approvePendingSuit = async (item) => {
  await supabase.from('suits').upsert({ name: item.name });
  await supabase.from('pending_suits').update({ status: 'approved' }).eq('id', item.id);
  alert('套装已建档！'); fetchAllData(); fetchSuits();
}
const rejectPendingSuit = (id) => supabase.from('pending_suits').update({ status: 'rejected' }).eq('id', id).then(fetchAllData)
const rejectPendingItem = (id) => supabase.from('pending_clothes').update({ status: 'rejected' }).eq('id', id).then(fetchAllData)
const formatDate = (ds) => new Date(ds).toLocaleString();
</script>

<template>
  <div class="admin-container">
    <div class="admin-nav-tabs">
      <button class="btn-back" @click="emit('back-to-main')">⬅️ 返回玩家前台</button> 
      <button :class="{ active: activeTab === 'audit' }" @click="activeTab = 'audit'">📋 聚类审核中心</button>
      <button v-if="currentUserRole === 'super_admin'" :class="{ active: activeTab === 'users' }" @click="activeTab = 'users'">👑 全站用户与权限</button>
      <div class="role-indicator">当前登录身份：<span>{{ currentUserRole }}</span></div>
    </div>

    <div v-show="activeTab === 'audit'">
      <section class="section-card review-section">
        <div class="section-header">
          <h3 class="purple-title">🎁 套装建档申请</h3>
          <span class="badge">{{ pendingSuitsList.length }} 条</span>
        </div>
        <div class="section-header" style="margin-top: 30px;">
          <h3 class="purple-title">🔔 散件众筹审核</h3>
          <span class="badge">{{ clusteredPendingList.length }} 组待办</span>
        </div>

        <div v-if="clusteredPendingList.length === 0" class="empty-status">☕ 暂时没有新的散件申请</div>
        <div v-else class="queue-grid">
          <div v-for="group in clusteredPendingList" :key="group.key" class="glass-card cluster-item">
            
            <div class="item-info-meta">
              <span class="item-name">{{ group.items[0].name }}</span>
              <div class="cluster-badges">
                <span class="badge-mini cat">{{ group.items[0].category }}</span>
                <span class="badge-mini id">#{{ group.items[0].game_id || 'N' }}</span>
                <span class="badge-mini count">🔥 {{ group.items.length }} 人提交</span>
              </div>
            </div>
            
            <div class="action-btns">
              <button @click="handleClusteredItem(group)" class="btn-process">✍️ 仲裁处理</button>
              <button @click="rejectPendingItem(group.items[0].id)" class="btn-reject">一键驳回</button>
            </div>
            
          </div>
        </div>
      </section>

      <section class="section-card form-section" id="entry-form">
        <div class="section-header">
          <h3 class="purple-title">👑 图鉴仲裁入库</h3>
          <span v-if="newClothes.pendingIds.length" class="edit-mode-tag">
            正在合并处理 {{ newClothes.pendingIds.length }} 份数据
          </span>
        </div>
        <div class="form-grid">
          <div class="input-group"><label>服装名称</label><input type="text" v-model="newClothes.name" /></div>
          <div class="input-group">
            <label>关联套装</label>
            <div class="searchable-select">
              <input type="text" v-model="suitSearchText" @focus="isSuitDropdownOpen = true" @blur="setTimeout(() => isSuitDropdownOpen = false, 200)" placeholder="🔍 搜索..." class="search-input" />
              <div v-if="isSuitDropdownOpen" class="select-dropdown">
                <div class="option" @click="selectSuit({id: '', name: ''})">-- 纯散件 --</div>
                <div v-for="s in filteredSuits" :key="s.id" class="option" @click="selectSuit(s)">《{{ s.name }}》</div>
              </div>
            </div>
          </div>
          <div class="input-group"><label>短编号</label><input type="text" v-model="newClothes.game_id" /></div>
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
          <div class="input-group"><label>标签</label><input type="text" v-model="newClothes.tags" /></div>
        </div>

        <div class="attr-form-card">
          <p class="card-tip">🎨 智能推荐：基于 {{ newClothes.pendingIds.length || 0 }} 份数据的众数计算</p>
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
          {{ isSubmitting ? '⌛ 正在同步...' : (newClothes.pendingIds.length ? '✅ 仲裁完毕：一键入库并结案' : '🚀 发布新图鉴') }}
        </button>
      </section>
    </div>

  </div>
  <div v-show="activeTab === 'users' && currentUserRole === 'super_admin'">
      
      <section class="section-card user-section" style="border-left: 4px solid #7c3aed; background: #f5f3ff;">
        <div class="section-header">
          <h3 class="purple-title">🛡️ 管理与决策团队</h3>
          <span class="badge">席位：{{ adminUsers.length }}</span>
        </div>
        <div class="users-table-container">
          <table class="users-table">
            <thead>
              <tr>
                <th>注册时间</th>
                <th>管理员邮箱</th>
                <th>系统身份</th>
                <th>图鉴贡献</th>
                <th>权限变更</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="u in adminUsers" :key="u.id" :class="{ 'is-me': u.id === currentUserId }">
                <td class="time-col">{{ formatDate(u.created_at) }}</td>
                <td class="email-col"><strong>{{ u.email }}</strong></td>
                <td><span class="role-badge" :class="u.role">{{ u.role === 'super_admin' ? '👑 最高站长' : '🛡️ 系统管理' }}</span></td>
                <td><span class="contrib-tag">✨ {{ u.contribCount }} 次</span></td>
                <td>
                  <select v-if="u.role !== 'super_admin'" class="role-select" :value="u.role" @change="changeUserRole(u.id, $event.target.value)">
                    <option value="user">降级为玩家</option>
                    <option value="admin">维持管理员</option>
                  </select>
                  <span v-else class="protected-text">权限锁定</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="section-card user-section">
        <div class="section-header">
          <h3 class="purple-title">👥 全站活跃玩家档案</h3>
          <span class="badge">总数：{{ regularUsers.length }}</span>
        </div>
        
        <div class="users-table-container">
          <table class="users-table">
            <thead>
              <tr>
                <th>注册时间</th>
                <th>玩家账号</th>
                <th>图鉴贡献次数</th>
                <th>设为管理</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="u in paginatedRegularUsers" :key="u.id">
                <td class="time-col">{{ formatDate(u.created_at) }}</td>
                <td class="email-col">{{ u.email }}</td>
                <td>
                  <div class="contrib-progress-bar">
                    <span class="count-txt">{{ u.contribCount }}</span>
                    <div class="track"><div class="fill" :style="{ width: Math.min(u.contribCount * 10, 100) + '%' }"></div></div>
                  </div>
                </td>
                <td>
                  <button class="btn-promote" @click="changeUserRole(u.id, 'admin')">🛡️ 提拔为管理员</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="pagination-admin" v-if="totalUserPages > 1">
          <button :disabled="userPage === 1" @click="userPage--">◀</button>
          <span>第 {{ userPage }} / {{ totalUserPages }} 页</span>
          <button :disabled="userPage === totalUserPages" @click="userPage++">▶</button>
        </div>
      </section>
    </div>
</template>

<style scoped>
/* 🌟 新增聚类样式 */
/* ========================================== */
/* 🌟 聚类审核卡片：悬浮水晶风格重构 */
/* ========================================== */

.queue-grid { 
  display: grid; 
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); 
  gap: 20px; 
}

/* 悬浮磨砂卡片主体 */
.glass-card { 
  background: rgba(255, 255, 255, 0.65); 
  backdrop-filter: blur(12px); 
  border: 1px solid rgba(255, 255, 255, 0.8); 
  box-shadow: 0 8px 24px rgba(149, 117, 205, 0.08); /* 极度柔和的紫灰阴影 */
  padding: 20px; 
  border-radius: 18px; 
  display: flex; 
  flex-direction: column; /* 核心：改为上下排布 */
  gap: 18px; 
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); 
}
.glass-card:hover { 
  transform: translateY(-5px); 
  box-shadow: 0 12px 32px rgba(149, 117, 205, 0.15); 
  background: rgba(255, 255, 255, 0.85); 
}

/* 去掉原本生硬的左侧边框，改为顶部精致的彩色渐变光晕线 */
.cluster-item { 
  border-left: none; 
  position: relative; 
  overflow: hidden; 
}
.cluster-item::before {
  content: ''; 
  position: absolute; 
  top: 0; left: 0; right: 0; 
  height: 4px;
  background: linear-gradient(90deg, #f472b6, #a855f7);
  opacity: 0.85;
}

/* 文本与标签区 */
.item-info-meta { display: flex; flex-direction: column; gap: 10px; }
.item-name { font-weight: 900; color: #1e293b; font-size: 17px; letter-spacing: 0.5px; }

.cluster-badges { display: flex; flex-wrap: wrap; gap: 8px; }
.badge-mini { 
  font-size: 11px; 
  padding: 5px 12px; 
  border-radius: 20px; /* 胶囊形状 */
  font-weight: 800; 
  display: inline-flex; 
  align-items: center; 
  letter-spacing: 0.5px; 
}
.badge-mini.cat { background: #f3e8ff; color: #7e22ce; }
.badge-mini.id { background: #f1f5f9; color: #475569; }
.badge-mini.count { background: #fff1f2; color: #e11d48; }

/* 底部按钮排版重构 */
.action-btns { 
  display: flex; 
  gap: 12px; 
  width: 100%; 
  margin-top: auto; /* 把按钮推到卡片最底部对齐 */
}

/* 仲裁按钮：梦幻渐变 */
.btn-process { 
  flex: 2; /* 比例放大，强调主要操作 */
  background: linear-gradient(135deg, #a855f7 0%, #7c3aed 100%); 
  color: white; 
  border: none; 
  padding: 10px; 
  border-radius: 12px; 
  font-weight: 900; 
  cursor: pointer; 
  font-size: 13px; 
  box-shadow: 0 4px 12px rgba(124, 58, 237, 0.25); 
  transition: all 0.2s; 
}
.btn-process:hover { filter: brightness(1.15); transform: translateY(-2px); box-shadow: 0 6px 16px rgba(124, 58, 237, 0.35); }

/* 驳回按钮：纯净去红线 */
.btn-reject { 
  flex: 1; /* 次要操作，比例稍小 */
  background: #fff1f2; 
  color: #ef4444; 
  border: none; /* 去掉以前那根很丑的红线边框 */
  padding: 10px; 
  border-radius: 12px; 
  font-weight: 900; 
  cursor: pointer; 
  font-size: 13px; 
  transition: all 0.2s; 
}
.btn-reject:hover { background: #fecdd3; color: #b91c1c; }
.badge-mini { font-size: 10px; padding: 2px 6px; border-radius: 4px; font-weight: bold; }
.badge-mini.cat { background: #ede9fe; color: #7c3aed; }
.badge-mini.id { background: #f1f5f9; color: #64748b; }
.badge-mini.count { background: #fff1f2; color: #e11d48; border: 1px solid #fecaca; }

.cluster-item { border-left: 5px solid #f472b6; }
.role-indicator { margin-left: auto; display: flex; align-items: center; font-size: 13px; font-weight: bold; color: #64748b; }
.role-indicator span { color: #db2777; margin-left: 5px; }

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

.item-info-meta { display: flex; flex-direction: column; gap: 6px; }
.item-name { font-weight: 800; color: #1e1b4b; font-size: 15px; }
.suit-tag { font-size: 11px; color: #db2777; background: #fdf2f8; padding: 2px 6px; border-radius: 6px; font-weight: bold; }


/* ========================================== */
/* 🌟 底部按钮排版重构：轻量通透风 */
/* ========================================== */

.action-btns { 
  display: flex; 
  gap: 12px; 
  width: 100%; 
  margin-top: auto; 
  padding-top: 15px; /* 增加顶部空间 */
  border-top: 1px dashed rgba(149, 117, 205, 0.2); /* 增加极淡的紫色虚线分割，拉满精致感 */
}

/* 仲裁按钮：微光描边，悬浮亮起 */
.btn-process { 
  flex: 1; /* 恢复 1:1 等宽，视觉更平衡 */
  background: #faf5ff; /* 极微弱的紫底（已修复） */
  color: #7c3aed; /* 优雅紫字 */
  border: 1px solid #e9d5ff; /* 细腻边框 */
  padding: 10px 0; 
  border-radius: 10px; /* 稍微调方一点，更有高级App的质感 */
  font-weight: 800; 
  cursor: pointer; 
  font-size: 13px; 
  letter-spacing: 0.5px;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); 
  display: flex;
  justify-content: center;
  align-items: center;
}
/* 鼠标悬浮：渐变色填充，展现核心操作感 */
.btn-process:hover { 
  background: linear-gradient(135deg, #a855f7 0%, #7c3aed 100%); 
  color: white; 
  border-color: transparent; 
  box-shadow: 0 6px 16px rgba(124, 58, 237, 0.25); 
  transform: translateY(-2px); 
}

/* 驳回按钮：次要弱化，避免视觉干扰 */
.btn-reject { 
  flex: 1; /* 1:1 等宽 */
  background: #f8fafc; /* 极淡的灰白底 */
  color: #64748b; /* 灰色字体，不抢视觉 */
  border: 1px solid #e2e8f0; /* 灰色边框 */
  padding: 10px 0; 
  border-radius: 10px; 
  font-weight: 800; 
  cursor: pointer; 
  font-size: 13px; 
  letter-spacing: 0.5px;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); 
  display: flex;
  justify-content: center;
  align-items: center;
}
/* 鼠标悬浮：变为危险红色，提示这是破坏性操作 */
.btn-reject:hover { 
  background: #fff1f2; 
  color: #e11d48; 
  border-color: #fecaca; 
  box-shadow: 0 6px 16px rgba(225, 29, 72, 0.15); 
  transform: translateY(-2px); 
}
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
.admin-container {
  max-width: 1200px; /* 🌟 限制 PC 端最大宽度 */
  margin: 0 auto;    /* 🌟 居中 */
  padding: 20px;
  padding-bottom: 50px;
  animation: fadeIn 0.4s ease;
}
.btn-back {
  background: #f1f5f9 !important;
  color: #64748b !important;
  border-color: #e2e8f0 !important;
  flex: 0.5 !important; /* 让它比另外两个按钮稍微窄一点 */
}
.btn-back:hover {
  background: #e2e8f0 !important;
  color: #334155 !important;
}
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }

/* 📱 手机端专属：后台管理面板适配 */
@media (max-width: 768px) {
  .admin-container {
    width: 100%;
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
/* 贡献次数小进度条样式 */
.contrib-progress-bar { display: flex; align-items: center; gap: 10px; width: 120px; }
.count-txt { font-weight: 900; color: #db2777; font-size: 14px; min-width: 25px; }
.contrib-progress-bar .track { flex: 1; height: 6px; background: #f1f5f9; border-radius: 10px; overflow: hidden; }
.contrib-progress-bar .fill { height: 100%; background: linear-gradient(90deg, #f472b6, #7c3aed); border-radius: 10px; }

.contrib-tag { background: #fdf2f8; color: #db2777; padding: 4px 10px; border-radius: 20px; font-weight: 900; font-size: 12px; border: 1px solid #fbcfe8; }

.btn-promote { background: white; border: 1.5px solid #ddd6fe; color: #7c3aed; padding: 5px 12px; border-radius: 8px; font-size: 11px; font-weight: bold; cursor: pointer; transition: 0.2s; }
.btn-promote:hover { background: #7c3aed; color: white; }

.pagination-admin { display: flex; justify-content: center; align-items: center; gap: 15px; margin-top: 20px; font-size: 13px; font-weight: bold; color: #64748b; }
.pagination-admin button { background: white; border: 1.5px solid #e2e8f0; border-radius: 8px; padding: 5px 12px; cursor: pointer; }
.pagination-admin button:disabled { opacity: 0.5; cursor: not-allowed; }
</style>