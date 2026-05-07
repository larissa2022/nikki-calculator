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
      emit('close') 
    } else {
      const { error } = await supabase.auth.signUp({ email: authForm.email, password: authForm.password })
      if (error) throw error
      
      alert('🎉 注册请求已发送！\n\n一封验证邮件已经发送到您的邮箱：' + authForm.email + '\n\n⚠️ 请前往邮箱点击里面的验证链接来激活账号（如果收件箱没有，请务必检查【垃圾邮件】或【拦截网关】）。\n\n验证通过后即可使用该账号登录！')
      emit('close') 
    }
  } catch (err) {
    // 🌟 核心修改：精准拦截并翻译 Supabase 的英文报错
    if (isLoginMode.value) {
      // 拦截 1：邮箱未验证
      if (err.message.includes('Email not confirmed')) {
        alert('⚠️ 登录失败：您的邮箱尚未验证！\n\n请前往邮箱（' + authForm.email + '）点击系统发送的验证链接。\n\n如果没有收到，请务必去【垃圾箱】找找看哦！')
      } 
      // 拦截 2：账号或密码错误
      else if (err.message.includes('Invalid login credentials')) {
        alert('❌ 登录失败：账号或密码错误，请检查后再试！')
      } 
      // 其他未知登录报错
      else {
        alert('登录失败：' + err.message)
      }
    } else {
      // 拦截 3：注册时邮箱已被占用
      if (err.message.includes('User already registered')) {
        alert('❌ 注册失败：该邮箱已经被注册过了，请直接切换到登录模式！')
      } 
      // 其他未知注册报错
      else {
        alert('注册失败：' + err.message)
      }
    }
  } finally {
    isAuthLoading.value = false
  }
}
</script>

<template>
  <Teleport to="body">
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
  </Teleport>
</template>

<style scoped>
* { box-sizing: border-box; }

.modal-overlay {
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999; /* 确保在最上层 */
}
.modal-content {
  background: white;
  padding: 30px;
  border-radius: 12px;
  width: 400px; /* PC端固定宽度 */
  position: relative;
  box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1);
  animation: popIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
}
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
/* 📱 手机端适配 */
@media (max-width: 768px) {
  .modal-content {
    width: 92% !important; /* 🌟 不要 100%，给左右留出呼吸空隙 */
    margin: 0 auto;
    padding: 24px 20px !important;
    max-height: 85vh; /* 🌟 限制最高度，防止长页面滑不动 */
    overflow-y: auto;
  }
}

@keyframes popIn {
  from { opacity: 0; transform: scale(0.9); }
  to { opacity: 1; transform: scale(1); }
}
</style>