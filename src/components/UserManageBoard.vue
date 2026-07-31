<script setup>
import { ref, computed } from 'vue'
import { getDisplayUsername, getUserRankAndPrivilege, isActiveUser } from '../composables/useUserPrivilege'
import { getRoleKey, getRoleLabel, isAdminRole, isSuperAdminRole } from '../utils/roles'

const props = defineProps({
  allUsersList: { type: Array, required: true },
  currentUserId: { type: String, required: true }
})

// ==========================================
// 全站大盘逻辑
// ==========================================
const userPage = ref(1)
const userPageSize = 10

const adminUsers = computed(() => props.allUsersList.filter(u => isAdminRole(u)))
const regularUsers = computed(() => props.allUsersList.filter(u => !isAdminRole(u)))
const paginatedRegularUsers = computed(() => {
  const start = (userPage.value - 1) * userPageSize;
  return regularUsers.value.slice(start, start + userPageSize);
})
const totalUserPages = computed(() => Math.ceil(regularUsers.value.length / userPageSize))

const formatDate = (ds) => new Date(ds).toLocaleString();
</script>

<template>
  <div>
    <section class="section-card user-section" style="border-left: 4px solid #7c3aed; background: #f5f3ff;">
      <div class="section-header">
        <h3 class="purple-title">🛡️ 管理与决策团队</h3>
        <span class="badge">席位：{{ adminUsers.length }}</span>
      </div>
      <div class="users-table-container">
        <table class="users-table">
          <thead>
            <tr><th>注册时间</th><th>玩家代号</th><th>系统身份</th><th>当前积分</th><th>权限状态</th></tr>
          </thead>
          <tbody>
            <tr v-for="u in adminUsers" :key="u.id" :class="{ 'is-me': u.id === currentUserId }">
              <td class="time-col">{{ formatDate(u.created_at) }}</td>
              <td class="email-col">
                <strong>{{ getDisplayUsername(u) }}</strong>
              </td>
              <td><span class="role-badge" :class="getRoleKey(u)">{{ isSuperAdminRole(u) ? '👑 ' : '🛡️ ' }}{{ getRoleLabel(u) }}</span></td>
              <td><span class="contrib-tag">✨ {{ u.total_points || 0 }} 分</span></td>
              <td>
                <span class="protected-text">超级管理员固定权限</span>
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
            <tr><th>玩家代号</th><th>头衔等级</th><th>累计积分</th><th>本月状态</th><th>管理员制度</th></tr>
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
                <span class="text-xs font-bold text-purple-600">请在“任期治理”创建手动任期</span>
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
/* 保持原有样式不变 */
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
