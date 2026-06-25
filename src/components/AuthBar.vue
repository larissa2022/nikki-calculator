<script setup>
import { supabase } from '@/api/supabase'

defineProps(['user'])
// 🌟 新增抛出 'open-profile' 事件
const emit = defineEmits(['open-login', 'open-profile'])

const handleLogout = async () => {
  try {
    const { error } = await supabase.auth.signOut()
    if (error) throw error
    alert('已成功安全退出！')
    window.location.reload() 
  } catch (err) {
    alert('退出失败：' + err.message)
  }
}
</script>

<template>
  <div class="auth-bar">
    <div v-if="user" class="user-info">
      <span class="user-email" @click="$emit('open-profile')" title="进入个人中心">
        👋 {{ user.email }}
      </span>
      <button class="btn-tiny btn-profile" @click="$emit('open-profile')">✨ 个人中心</button>
      
      <button class="btn-tiny btn-logout" @click="handleLogout">登出</button>
    </div>
    <button v-else class="btn-login" @click="$emit('open-login')">🛡️ 登录开启云端同步</button>
  </div>
</template>

<style scoped>
.auth-bar { display: flex; justify-content: flex-end; padding-bottom: 10px; border-bottom: 1px dashed #ddd; margin-bottom: 20px;}
.user-info { font-size: 14px; color: #4b5563; display: flex; align-items: center; gap: 8px;}

/* 🌟 新增：专属个人中心按钮和可点击的邮箱样式 */
.btn-profile { background: #fdf2f8; color: #db2777; border-radius: 6px; padding: 4px 10px; cursor: pointer; border: 1px solid #fbcfe8; font-weight: bold; transition: all 0.2s;}
.btn-profile:hover { background: #fbcfe8; transform: translateY(-1px); }
.user-email { cursor: pointer; font-weight: bold; transition: color 0.2s; padding: 2px 6px; border-radius: 4px; }
.user-email:hover { color: #db2777; background: #fdf2f8; }

.btn-login { background: white; color: #3b82f6; border: 1px solid #3b82f6; padding: 5px 15px; font-size: 13px; border-radius: 20px; cursor: pointer;}
.btn-login:hover { background: #eff6ff; }
.btn-logout { background: #fee2e2; color: #ef4444; border-radius: 6px; padding: 4px 10px; cursor: pointer; border: none; font-weight: bold; transition: background 0.2s;}
.btn-logout:hover { background: #fca5a5; color: white;}
.btn-tiny { font-size: 12px; cursor: pointer; }
</style>