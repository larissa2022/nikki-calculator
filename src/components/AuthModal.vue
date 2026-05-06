<script setup>
import { ref, reactive } from 'vue'
import { supabase } from '@/api/supabase'

const emit = defineEmits(['close'])
const isLoginMode = ref(true)
const authForm = reactive({ email: '', password: '', confirmPassword: '' })
const isAuthLoading = ref(false)

const submitAuth = async () => {
  if (!authForm.email || !authForm.password) return alert('请输入邮箱和密码！')
  if (!isLoginMode.value && authForm.password !== authForm.confirmPassword) {
    return alert('❌ 两次输入的密码不一致！')
  }
  isAuthLoading.value = true
  try {
    if (isLoginMode.value) {
      const { error } = await supabase.auth.signInWithPassword({ email: authForm.email, password: authForm.password })
      if (error) throw error
      alert('登录成功！欢迎回来。')
    } else {
      const { error } = await supabase.auth.signUp({ email: authForm.email, password: authForm.password })
      if (error) throw error
      alert('注册成功！')
    }
    emit('close') // 成功后通知父组件关闭弹窗
  } catch (err) {
    alert(isLoginMode.value ? '登录失败：' + err.message : '注册失败：' + err.message)
  } finally {
    isAuthLoading.value = false
  }
}
</script>

<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal-content">
      <h2>{{ isLoginMode ? '账号登录' : '注册新账号' }}</h2>
      <input type="email" v-model="authForm.email" placeholder="输入您的邮箱" />
      <input type="password" v-model="authForm.password" placeholder="输入密码 (至少6位)" @keyup.enter="isLoginMode ? submitAuth() : null" />
      <input v-if="!isLoginMode" type="password" v-model="authForm.confirmPassword" placeholder="请再次输入密码确认" @keyup.enter="submitAuth" />
      <button class="btn-primary" @click="submitAuth" :disabled="isAuthLoading">
        {{ isAuthLoading ? '处理中...' : (isLoginMode ? '立刻登录' : '确认注册') }}
      </button>
      <p class="toggle-mode" @click="isLoginMode = !isLoginMode">
        {{ isLoginMode ? '没有账号？点击注册' : '已有账号？返回登录' }}
      </p>
    </div>
  </div>
</template>

<style scoped>
.modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); display: flex; justify-content: center; align-items: center; z-index: 1000; backdrop-filter: blur(2px);}
.modal-content { background: white; padding: 30px; border-radius: 12px; width: 90%; max-width: 350px; box-shadow: 0 10px 25px rgba(0,0,0,0.2); animation: popIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);}
.modal-content h2 { text-align: center; color: #374151; margin-top: 0; margin-bottom: 20px;}
.modal-content input { width: 100%; padding: 12px; margin-bottom: 15px; border: 1px solid #d1d5db; border-radius: 6px; box-sizing: border-box; font-size: 15px; outline: none; transition: border-color 0.2s;}
.modal-content input:focus { border-color: #f472b6; }
.btn-primary { background: #f472b6; color: white; width: 100%; padding: 12px; font-size: 16px; border: none; border-radius: 8px; font-weight: bold; cursor: pointer;}
.btn-primary:hover { background: #ec4899; }
.btn-primary:disabled { background: #fbcfe8; cursor: not-allowed; }
.toggle-mode { text-align: center; color: #3b82f6; font-size: 13px; margin-top: 15px; cursor: pointer;}
.toggle-mode:hover { text-decoration: underline; }
@keyframes popIn {
  from { opacity: 0; transform: scale(0.9); }
  to { opacity: 1; transform: scale(1); }
}
/* 📱 手机端专属：弹窗适配 */
@media (max-width: 768px) {
  /* 让遮罩层牢牢锁死在屏幕上 */
  .modal-overlay {
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    z-index: 9999;
    padding: 20px; /* 留出安全距离 */
    box-sizing: border-box;
    display: flex;
    align-items: center; /* 绝对垂直居中 */
    justify-content: center;
  }

  /* 弹窗本体改造 */
  .modal-content {
    width: 100% !important; /* 充分利用手机宽度 */
    max-width: 400px;
    max-height: 80vh; /* 最高只能占屏幕的 80% */
    overflow-y: auto; /* 内容太多就在弹窗内部滑动，不拉长整个网页 */
    margin: 0; /* 清除电脑端的居中 margin */
    border-radius: 20px;
    padding: 24px 20px !important;
  }
}
</style>