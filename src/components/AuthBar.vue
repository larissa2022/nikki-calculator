<script setup>
import { computed, ref, watch } from 'vue'
import { supabase } from '@/api/supabase'

const props = defineProps(['user', 'profile'])
// 🌟 新增抛出 'open-profile' 事件
const emit = defineEmits(['open-login', 'open-profile', 'signed-out'])

const displayName = computed(() => props.profile?.username || props.user?.email || '个人中心')
const isSigningOut = ref(false)
const authNotice = ref('')

watch(() => props.user?.id, (userId, previousUserId) => {
  if (userId && userId !== previousUserId) authNotice.value = ''
})

const withLogoutTimeout = promise => new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('退出请求等待时间过长')), 15000)
  Promise.resolve(promise).then(
    value => {
      clearTimeout(timer)
      resolve(value)
    },
    error => {
      clearTimeout(timer)
      reject(error)
    }
  )
})

const handleLogout = async () => {
  if (isSigningOut.value) return
  isSigningOut.value = true
  authNotice.value = ''
  try {
    const { error } = await withLogoutTimeout(supabase.auth.signOut())
    if (error) throw error
    authNotice.value = '已安全退出。'
    emit('signed-out')
  } catch (err) {
    const { data } = await withLogoutTimeout(supabase.auth.getSession()).catch(() => ({ data: null }))
    if (!data?.session) {
      authNotice.value = '已安全退出。'
      emit('signed-out')
    } else {
      authNotice.value = `${err?.message || '退出失败'}，请稍后重试。`
    }
  } finally {
    isSigningOut.value = false
  }
}
</script>

<template>
  <div class="auth-bar">
    <div v-if="user" class="user-info">
      <span class="user-email" @click="$emit('open-profile')" title="进入个人中心">
        👋 {{ displayName }}
      </span>
      <button class="btn-tiny btn-profile" @click="$emit('open-profile')">✨ 个人中心</button>
      
      <button class="btn-tiny btn-logout" :disabled="isSigningOut" @click="handleLogout">{{ isSigningOut ? '退出中…' : '登出' }}</button>
    </div>
    <button v-else class="btn-login" @click="$emit('open-login')">🛡️ 登录开启云端同步</button>
    <span v-if="authNotice" class="auth-notice" role="status">{{ authNotice }}</span>
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
.btn-logout:disabled { opacity: 0.6; cursor: wait; }
.auth-notice { margin-left: 8px; color: #64748b; font-size: 12px; font-weight: 700; }
.btn-tiny { font-size: 12px; cursor: pointer; }
</style>
