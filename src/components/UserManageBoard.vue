<script setup>
import { ref, computed } from 'vue'
import { adminService } from '../api/adminService'

// 接收外部传进来的数据和当前登录状态
const props = defineProps({
  allUsersList: { type: Array, required: true },
  currentUserId: { type: String, required: true }
})
const emit = defineEmits(['refresh-data']) // 通知父组件刷新数据

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
    emit('refresh-data'); // 通知大盘重新拉取数据
  } catch(err) { alert(err.message); }
}

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
            <tr><th>注册时间</th><th>管理员邮箱</th><th>系统身份</th><th>图鉴贡献</th><th>权限变更</th></tr>
          </thead>
          <tbody>
            <tr v-for="u in adminUsers" :key="u.id" :class="{ 'is-me': u.id === currentUserId }">
              <td class="time-col">{{ formatDate(u.created_at) }}</td>
              <td class="email-col"><strong>{{ u.email }}</strong></td>
              <td><span class="role-badge" :class="u.role">{{ u.role === 'super_admin' ? '👑 最高站长' : '🛡️ 系统管理' }}</span></td>
              <td><span class="contrib-tag">✨ {{ u.contribCount }} 次</span></td>
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

    <section class="section-card user-section">
      <div class="section-header">
        <h3 class="purple-title">👥 全站活跃玩家档案</h3>
        <span class="badge">总数：{{ regularUsers.length }}</span>
      </div>
      <div class="users-table-container">
        <table class="users-table">
          <thead>
            <tr><th>注册时间</th><th>玩家账号</th><th>图鉴贡献次数</th><th>设为管理</th></tr>
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