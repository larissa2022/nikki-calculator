<script setup>
import { supabase } from '@/api/supabase'

defineProps(['user'])
const emit = defineEmits(['open-login'])

const handleLogout = async () => {
  await supabase.auth.signOut()
  alert('已成功登出！')
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