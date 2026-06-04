<script setup>
import { supabase } from '@/api/supabase'

defineProps(['user'])
const emit = defineEmits(['open-login'])

const handleLogout = async () => {
  try {
    // 1. 通知 Supabase 销毁本地 Token 和服务器 Session
    const { error } = await supabase.auth.signOut()
    if (error) throw error
    
    // 2. 只需要弹窗提示
    alert('已成功安全退出！')
    
    // 3. 强制刷新页面，浏览器会清空所有 Vue 内存残留，彻底解决幽灵状态
    window.location.reload() 
  } catch (err) {
    alert('退出失败：' + err.message)
  }
}
</script>

<template>
  <div class="auth-bar">
    <div v-if="user" class="user-info">
      <span>👋 {{ user.email }}</span>
      <button class="btn-tiny btn-logout" @click="handleLogout">登出</button>
    </div>
    <button v-else class="btn-login" @click="$emit('open-login')">🛡️ 登录开启云端同步</button>
  </div>
</template>

<style scoped>
.auth-bar { display: flex; justify-content: flex-end; padding-bottom: 10px; border-bottom: 1px dashed #ddd; margin-bottom: 20px;}
.user-info { font-size: 14px; color: #4b5563; display: flex; align-items: center; gap: 10px;}
.btn-login { background: white; color: #3b82f6; border: 1px solid #3b82f6; padding: 5px 15px; font-size: 13px; border-radius: 20px; cursor: pointer;}
.btn-login:hover { background: #eff6ff; }
.btn-logout { background: #fee2e2; color: #ef4444; border-radius: 4px; padding: 3px 8px; cursor: pointer; border: none;}
.btn-tiny { font-size: 12px; cursor: pointer; }
</style>