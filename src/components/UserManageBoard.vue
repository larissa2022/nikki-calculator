<script setup>
import { ref, computed } from 'vue'
import { adminService } from '../api/adminService'
// 🌟 1. 补上缺失的 supabase 和等级算法工具库的引入
import { supabase } from '../api/supabase'
import { getDisplayUsername, getUserRankAndPrivilege, isActiveUser } from '../composables/useUserPrivilege'

// 接收外部传进来的数据和当前登录状态
const props = defineProps({
  allUsersList: { type: Array, required: true },
  currentUserId: { type: String, required: true }
})
const emit = defineEmits(['refresh-data']) // 通知父组件刷新数据

// 🌟 新增：用于 v-if / v-else 切换视图的状态
const currentView = ref('profile') // 可选值: 'profile' (个人档案) | 'dashboard' (全站大盘)

// 🌟 2. 补上缺失的 currentUserInfo 和 myRank 的计算逻辑
const currentUserInfo = computed(() => props.allUsersList.find(u => u.id === props.currentUserId) || {})
const myRank = computed(() => getUserRankAndPrivilege(currentUserInfo.value.total_points || 0))

const newUsername = ref('')
const isUpdatingName = ref(false)
const isSendingEmail = ref(false)

// ==========================================
// 1. 修改用户名逻辑 (自带唯一性防撞车)
// ==========================================
const updateUsername = async () => {
  const cleanName = newUsername.value.trim()
  if (!cleanName) return alert('用户名不能为空！')
  if (cleanName.startsWith('匿名搭配师_')) return alert('不能使用系统保留的匿名格式哦！')

  isUpdatingName.value = true
  try {
    const { error } = await supabase
      .from('profiles')
      .update({ username: cleanName })
      .eq('id', props.currentUserId) // 🌟 修复：直接使用传入的真实 ID

    if (error) {
      if (error.code === '23505') {
        throw new Error(`用户名 "${cleanName}" 已被其他玩家抢注，换一个霸气点的名字吧！`)
      }
      throw error
    }
    
    alert('🎉 用户名修改成功！')
    newUsername.value = ''
    emit('refresh-data') // 通知大盘重新拉取数据，刷新名字
    
  } catch (err) {
    alert('❌ 修改失败：' + err.message)
  } finally {
    isUpdatingName.value = false
  }
}

// ==========================================
// 2. 修改密码逻辑 (触发邮件验证)
// ==========================================
const resetPassword = async () => {
  const userEmail = currentUserInfo.value.email // 🌟 修复：自动获取当前用户的真实邮箱
  if (!userEmail) return alert('未获取到用户邮箱信息')
  
  const isConfirmed = confirm(`系统将向您的邮箱 ${userEmail} 发送一封密码重置邮件。\n是否继续？`)
  if (!isConfirmed) return

  isSendingEmail.value = true
  try {
    const { error } = await supabase.auth.resetPasswordForEmail(userEmail, {
      redirectTo: `${window.location.origin}/update-password`, 
    })

    if (error) throw error
    alert('📧 密码重置邮件已发送！请前往您的邮箱查收，并点击邮件中的链接设置新密码。')
    
  } catch (err) {
    alert('❌ 邮件发送失败：' + err.message)
  } finally {
    isSendingEmail.value = false
  }
}

// ==========================================
// 3. 全站大盘逻辑
// ==========================================
const userPage = ref(1)
const userPageSize = 10

const adminUsers = computed(() => props.allUsersList.filter(u => u.role !== 'user'))
const regularUsers = computed(() => props.allUsersList.filter(u => u.role === 'user'))
const paginatedRegularUsers = computed(() => {
  const start = (userPage.value - 1) * userPageSize;
  return regularUsers.value.slice(start, start + userPageSize);
})
const totalUserPages = computed(() => Math.ceil(regularUsers.value.length / userPageSize))

const changeUserRole = async (uId, role) => {
  try {
    await adminService.updateUserRole(uId, role);
    alert('权限更新成功！'); 
    emit('refresh-data'); 
  } catch(err) { alert(err.message); }
}

const formatDate = (ds) => new Date(ds).toLocaleString();
</script>

<template>
  <div>
    <div class="flex gap-2 mb-6 bg-white p-2 rounded-2xl border border-slate-100 shadow-sm w-fit">
      <button 
        @click="currentView = 'profile'" 
        class="px-5 py-2 rounded-xl font-black text-sm transition-all"
        :class="currentView === 'profile' ? 'bg-pink-50 text-pink-500 shadow-sm border border-pink-100' : 'text-slate-400 hover:bg-slate-50'"
      >
        ✨ 个人档案
      </button>
      <button 
        @click="currentView = 'dashboard'" 
        class="px-5 py-2 rounded-xl font-black text-sm transition-all"
        :class="currentView === 'dashboard' ? 'bg-purple-50 text-purple-600 shadow-sm border border-purple-100' : 'text-slate-400 hover:bg-slate-50'"
      >
        📊 数据大盘
      </button>
    </div>

    <div v-if="currentView === 'profile'" class="space-y-6">
      
      <section class="bg-white rounded-2xl p-6 shadow-sm border border-slate-100 relative overflow-hidden">
        <div class="absolute top-0 left-0 w-full h-1.5 bg-gradient-to-r from-pink-400 to-purple-500"></div>
        <h3 class="text-lg font-black text-slate-800 mb-6 flex items-center gap-2">
          <span>✨</span> 我的搭配师档案
        </h3>
        
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="p-4 rounded-xl bg-slate-50 border border-slate-100">
            <div class="text-xs font-bold text-slate-400 mb-1">当前代号</div>
            <div class="text-lg font-black text-pink-500 truncate">{{ getDisplayUsername(currentUserInfo) }}</div>
            <div v-if="!currentUserInfo.username" class="mt-1 text-[10px] font-bold text-rose-500 bg-rose-50 px-2 py-0.5 rounded w-fit">尚未设置专属代号</div>
          </div>
          
          <div class="p-4 rounded-xl bg-slate-50 border border-slate-100">
            <div class="text-xs font-bold text-slate-400 mb-1">社区头衔</div>
            <div class="text-lg font-black text-slate-700">{{ myRank.title }}</div>
            <div class="mt-1 text-[11px] font-bold text-slate-500">投票权重: 1 顶 <span class="text-purple-500">{{ myRank.voteWeight }}</span> 票</div>
          </div>
          
          <div class="p-4 rounded-xl bg-slate-50 border border-slate-100">
            <div class="text-xs font-bold text-slate-400 mb-1">累计积分</div>
            <div class="text-lg font-black text-purple-600">{{ currentUserInfo.total_points || 0 }} 分</div>
            <div class="mt-1 text-[11px] font-bold text-slate-500">本月活跃度: {{ currentUserInfo.monthly_action_count || 0 }} 次</div>
          </div>
        </div>
      </section>

      <section class="bg-white rounded-2xl p-6 shadow-sm border border-slate-100">
        <h3 class="text-base font-black text-slate-800 mb-2 flex items-center gap-2">
          <span>🏷️</span> 设置专属代号
        </h3>
        <p class="text-xs font-bold text-slate-400 mb-4">代号具有全站唯一性，设置后将展示在您的图鉴贡献榜中。</p>
        
        <div class="flex flex-col sm:flex-row gap-3 max-w-md">
          <input 
            type="text" 
            v-model="newUsername" 
            placeholder="输入新昵称 (不可重复)" 
            class="input input-bordered w-full font-bold bg-slate-50 focus:bg-white focus:border-pink-400" 
          />
          <button @click="updateUsername" :disabled="isUpdatingName" class="btn btn-primary font-black shadow-sm shrink-0">
            {{ isUpdatingName ? '保存中...' : '确认修改' }}
          </button>
        </div>
      </section>

      <section class="bg-white rounded-2xl p-6 shadow-sm border border-slate-100">
        <h3 class="text-base font-black text-slate-800 mb-2 flex items-center gap-2">
          <span>🔒</span> 账号安全与密码
        </h3>
        <p class="text-xs font-bold text-slate-400 mb-4">为了保护您的账号安全，密码修改需要通过您注册时的邮箱进行验证。</p>
        
        <div class="p-4 rounded-xl bg-blue-50 border border-blue-100 flex flex-col sm:flex-row justify-between items-center gap-4">
          <div class="text-sm font-bold text-blue-800">
            当前绑定邮箱：<span class="opacity-75">{{ currentUserInfo.email || '未获取' }}</span>
          </div>
          <button @click="resetPassword" :disabled="isSendingEmail" class="btn btn-sm bg-white hover:bg-blue-600 hover:text-white border-blue-200 text-blue-600 font-black shrink-0 transition-colors">
            {{ isSendingEmail ? '正在发送...' : '📧 发送密码重置邮件' }}
          </button>
        </div>
      </section>

    </div>

    <div v-else>
      <section class="section-card user-section" style="border-left: 4px solid #7c3aed; background: #f5f3ff;">
        <div class="section-header">
          <h3 class="purple-title">🛡️ 管理与决策团队</h3>
          <span class="badge">席位：{{ adminUsers.length }}</span>
        </div>
        <div class="users-table-container">
          <table class="users-table">
            <thead>
              <tr><th>注册时间</th><th>玩家代号 (邮箱)</th><th>系统身份</th><th>当前积分</th><th>权限变更</th></tr>
            </thead>
            <tbody>
              <tr v-for="u in adminUsers" :key="u.id" :class="{ 'is-me': u.id === currentUserId }">
                <td class="time-col">{{ formatDate(u.created_at) }}</td>
                <td class="email-col">
                  <strong>{{ getDisplayUsername(u) }}</strong><br>
                  <span class="text-[10px] text-slate-400">{{ u.email }}</span>
                </td>
                <td><span class="role-badge" :class="u.role">{{ u.role === 'super_admin' ? '👑 最高站长' : '🛡️ 系统管理' }}</span></td>
                <td><span class="contrib-tag">✨ {{ u.total_points || 0 }} 分</span></td>
                <td>
                  <select v-if="u.role !== 'super_admin'" class="role-select" :value="u.role" @change="changeUserRole(u.id, $event.target.value)">
                    <option value="user">降级为玩家</option><option value="admin">维持管理员</option>
                  </select>
                  <span v-else class="protected-text">权限锁定</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="section-card user-section mt-6">
        <div class="section-header">
          <h3 class="purple-title">👥 全站活跃玩家档案</h3>
          <span class="badge">总数：{{ regularUsers.length }}</span>
        </div>
        <div class="users-table-container">
          <table class="users-table">
            <thead>
              <tr><th>玩家代号</th><th>头衔等级</th><th>累计积分</th><th>本月状态</th><th>设为管理</th></tr>
            </thead>
            <tbody>
              <tr v-for="u in paginatedRegularUsers" :key="u.id">
                <td class="email-col font-bold">{{ getDisplayUsername(u) }}</td>
                <td><span class="badge bg-slate-100">{{ getUserRankAndPrivilege(u.total_points || 0).title }}</span></td>
                <td>
                  <div class="contrib-progress-bar">
                    <span class="count-txt">{{ u.total_points || 0 }}</span>
                    <div class="track"><div class="fill" :style="{ width: Math.min((u.total_points || 0) / 100, 100) + '%' }"></div></div>
                  </div>
                </td>
                <td>
                  <span v-if="isActiveUser(u.monthly_action_count)" class="text-xs font-bold text-emerald-500 bg-emerald-50 px-2 py-1 rounded">✅ 活跃</span>
                  <span v-else class="text-xs font-bold text-slate-400">潜水</span>
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
  </div>
</template>

<style scoped>
/* 🌟 这里只保留与用户表格、进度条、权限徽章、翻页器相关的 CSS */
/* 把 AdminPanel 里对应的 CSS 剪切到这里，其他的不变 */
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
.protected-text { font-size: 11px; color: #cbd5e1; font-weight: bold; }
.section-card { background: white; border-radius: 16px; padding: 24px; margin-bottom: 25px; box-shadow: 0 10px 25px rgba(124,58,237,0.05); border: 1px solid #f3f4f6; }
.section-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
.purple-title { color: #7c3aed; font-size: 18px; font-weight: 900; border-left: 4px solid #f472b6; padding-left: 12px; margin:0;}
.badge { font-size: 12px; padding: 4px 10px; border-radius: 10px; background: #f3f4f6; color: #64748b; font-weight: bold; }
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