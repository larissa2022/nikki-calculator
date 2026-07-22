<script setup>
import { ref, reactive, onUnmounted } from 'vue'
import { supabase } from '@/api/supabase'
import { getAuthTimeoutRecovery } from '@/utils/authTimeout'

const emit = defineEmits(['close'])
const currentMode = ref('login')
const authForm = reactive({ email: '', password: '', confirmPassword: '', otpCode: '' })
const isAuthLoading = ref(false)

// ==========================================
// 🌟 1. 非阻塞式消息提示系统
// ==========================================
const feedback = reactive({ show: false, text: '', type: 'error' })
let feedbackTimer = null

const showMessage = (text, type = 'error') => {
  feedback.text = text
  feedback.type = type
  feedback.show = true
  if (feedbackTimer) clearTimeout(feedbackTimer)
  feedbackTimer = setTimeout(() => {
    feedback.show = false
  }, 4000)
}

const isErrorMessage = (err, keyword) => err?.message?.toLowerCase().includes(keyword.toLowerCase())

const getErrorMessage = (err) => {
  if (!err?.message) return '操作失败，请稍后重试'
  if (isErrorMessage(err, 'Email not confirmed')) return '该邮箱尚未完成验证，请输入邮件验证码；如果没收到，请点击重新发送。'
  if (isErrorMessage(err, 'Invalid login credentials')) return '账号或密码错误；如果刚注册过，请先完成邮箱验证。'
  if (isErrorMessage(err, 'User already registered') || isErrorMessage(err, 'already registered')) return '该邮箱已经注册过，请直接登录；如果忘记密码，请使用找回密码。'
  if (isErrorMessage(err, 'Token has expired or is invalid') || isErrorMessage(err, 'otp')) return '验证码错误或已过期，请检查邮件中的最新验证码。'
  if (isErrorMessage(err, 'rate_limit') || isErrorMessage(err, 'too many')) return '发送太频繁啦，请稍后再试。'
  if (isErrorMessage(err, 'network') || isErrorMessage(err, 'fetch')) return '网络连接异常，请检查网络后重试。'
  return err.message
}

const handleAuthErrorState = (err) => {
  if (isErrorMessage(err, 'Email not confirmed')) {
    currentMode.value = 'verify_register'
    authForm.otpCode = ''
  }
}

const switchMode = (mode) => {
  currentMode.value = mode
  authForm.password = ''
  authForm.confirmPassword = ''
  authForm.otpCode = ''
  feedback.show = false
}

// ==========================================
// 🌟 2. 60秒倒计时逻辑
// ==========================================
const countdown = ref(0)
let timer = null

const startCountdown = () => {
  countdown.value = 60
  if (timer) clearInterval(timer)
  timer = setInterval(() => {
    if (countdown.value > 0) {
      countdown.value--
    } else {
      clearInterval(timer)
    }
  }, 1000)
}

// 组件卸载时清理定时器，防止内存泄漏
onUnmounted(() => {
  if (timer) clearInterval(timer)
})

// ==========================================
// 🌟 3. 重新发送验证码逻辑
// ==========================================
const resendOtp = async () => {
  if (countdown.value > 0 || isAuthLoading.value) return
  const cleanEmail = authForm.email?.trim() || ''
  if (!cleanEmail) return showMessage('未获取到邮箱信息，请返回重新填写！', 'error')

  isAuthLoading.value = true
  try {
    if (currentMode.value === 'verify_register') {
      // Supabase 专属的重发注册验证码方法
      const { error } = await supabase.auth.resend({ type: 'signup', email: cleanEmail })
      if (error) throw error
    } else if (currentMode.value === 'reset') {
      const { error } = await supabase.auth.resetPasswordForEmail(cleanEmail)
      if (error) throw error
    }
    
    showMessage('验证码已重新发送，请前往邮箱查收！', 'success')
    startCountdown()
  } catch (err) {
    handleAuthErrorState(err)
    showMessage(getErrorMessage(err), 'error')
  } finally {
    isAuthLoading.value = false
  }
}

// ==========================================
// 🌟 4. 核心鉴权逻辑 (登录/注册/重置)
// ==========================================
const submitAuth = async () => {
  const submittedMode = currentMode.value
  const cleanEmail = authForm.email?.trim() || ''
  const cleanOtp = authForm.otpCode?.replace(/\s+/g, '') || ''
  const cleanPassword = authForm.password?.trim() || ''

  if (!cleanEmail) return showMessage('请输入邮箱！')
  if (['login', 'register', 'reset'].includes(currentMode.value) && !cleanPassword) {
    return showMessage('请输入密码！')
  }
  if (['register', 'reset'].includes(currentMode.value) && cleanPassword !== authForm.confirmPassword?.trim()) {
    return showMessage('两次输入的密码不一致！')
  }
  if (['verify_register', 'reset'].includes(currentMode.value) && !cleanOtp) {
    return showMessage('请输入验证码！')
  }

  isAuthLoading.value = true
  feedback.show = false 

  try {
    const timeoutPromise = new Promise((_, reject) => 
      setTimeout(() => reject(new Error('网络请求超时，请检查网络📶')), 10000)
    )

    const executeAuth = async () => {
      if (currentMode.value === 'login') {
        const { error } = await supabase.auth.signInWithPassword({ email: cleanEmail, password: cleanPassword })
        if (error) throw error
        return { msg: '登录成功！欢迎回来。', type: 'success', action: 'close' }
      } 
      else if (currentMode.value === 'register') {
        const { data, error } = await supabase.auth.signUp({ email: cleanEmail, password: cleanPassword })
        if (error) throw error
        if (data?.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) {
          return { msg: '该邮箱已经注册过，请点击下方“返回登录”后直接登录；如果忘记密码，请使用找回密码。', type: 'error' }
        }
        currentMode.value = 'verify_register'
        startCountdown() // 🌟 第一次发完验证码，自动启动倒计时
        return { msg: '验证码已发送至邮箱，请查收！', type: 'success' }
      } 
      else if (currentMode.value === 'verify_register') {
        const { error } = await supabase.auth.verifyOtp({ email: cleanEmail, token: cleanOtp, type: 'signup' })
        if (error) throw error
        return { msg: '激活成功！已为您自动登录。', type: 'success', action: 'close' }
      } 
      else if (currentMode.value === 'forgot') {
        const { error } = await supabase.auth.resetPasswordForEmail(cleanEmail)
        if (error) throw error
        currentMode.value = 'reset'
        startCountdown() // 🌟 第一次发完重置验证码，自动启动倒计时
        return { msg: '重置验证码已发送至邮箱。', type: 'success' }
      } 
      else if (currentMode.value === 'reset') {
        const { error: verifyErr } = await supabase.auth.verifyOtp({ email: cleanEmail, token: cleanOtp, type: 'recovery' })
        if (verifyErr) throw verifyErr
        
        const { error: updateErr } = await supabase.auth.updateUser({ password: cleanPassword })
        if (updateErr) throw updateErr
        
        currentMode.value = 'login'
        authForm.password = ''
        authForm.confirmPassword = ''
        authForm.otpCode = ''
        return { msg: '密码重置成功！请重新登录。', type: 'success' }
      }
    }

    const result = await Promise.race([executeAuth(), timeoutPromise])

    isAuthLoading.value = false
    showMessage(result.msg, result.type)
    
    if (result.action === 'close') {
      setTimeout(() => emit('close'), 1000)
    }

  } catch (err) {
    isAuthLoading.value = false
    handleAuthErrorState(err)
    if (err.message.includes('超时')) {
      const recovery = getAuthTimeoutRecovery(submittedMode)
      currentMode.value = recovery.nextMode
      if (recovery.clearSensitiveFields) {
        authForm.password = ''
        authForm.confirmPassword = ''
        authForm.otpCode = ''
      }
      showMessage(recovery.message, recovery.type)
      return
    }
    showMessage(getErrorMessage(err), 'error')
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="modal-overlay" @click.self="$emit('close')">
      <div class="modal-content">
        <h2>
          {{ currentMode === 'login' ? '账号登录' : 
             currentMode === 'register' ? '注册新账号' : 
             currentMode === 'verify_register' ? '邮箱验证激活' :
             currentMode === 'forgot' ? '找回密码' : '重置密码' }}
        </h2>

        <div v-if="feedback.show" class="feedback-banner" :class="feedback.type">
          {{ feedback.text }}
        </div>

        <input 
          type="email" 
          v-model="authForm.email" 
          placeholder="输入您的邮箱" 
          :disabled="currentMode === 'verify_register' || currentMode === 'reset' || isAuthLoading" 
        />

        <input 
          v-if="['login', 'register', 'reset'].includes(currentMode)" 
          type="password" 
          v-model="authForm.password" 
          :placeholder="currentMode === 'reset' ? '输入新密码 (至少6位)' : '输入密码 (至少6位)'" 
          @keyup.enter="submitAuth" 
          :disabled="isAuthLoading"
        />

        <input 
          v-if="['register', 'reset'].includes(currentMode)" 
          type="password" 
          v-model="authForm.confirmPassword" 
          placeholder="请再次输入密码确认" 
          @keyup.enter="submitAuth" 
          :disabled="isAuthLoading"
        />

        <div v-if="['verify_register', 'reset'].includes(currentMode)" style="position: relative; margin-bottom: 15px;">
          <input 
            type="text" 
            v-model="authForm.otpCode" 
            placeholder="输入邮件中的验证码" 
            @keyup.enter="submitAuth" 
            style="text-align: center; letter-spacing: 4px; font-size: 16px; margin-bottom: 0; padding-right: 100px;"
            :disabled="isAuthLoading"
          />
          <button 
            @click="resendOtp"
            :disabled="countdown > 0 || isAuthLoading"
            style="position: absolute; right: 6px; top: 6px; bottom: 6px; padding: 0 12px; border-radius: 8px; font-size: 12px; font-weight: bold; border: none; transition: 0.2s;"
            :style="countdown > 0 ? 'background: #f1f5f9; color: #94a3b8; cursor: not-allowed;' : 'background: #fdf2f8; color: #db2777; cursor: pointer;'"
          >
            {{ countdown > 0 ? `${countdown}s 后重发` : '重新发送' }}
          </button>
        </div>

        <button class="btn-primary" @click="submitAuth" :disabled="isAuthLoading">
          {{ isAuthLoading ? '处理中...' : 
             currentMode === 'login' ? '立刻登录' : 
             currentMode === 'register' ? '获取注册验证码' :
             currentMode === 'verify_register' ? '验证并激活账号' :
             currentMode === 'forgot' ? '获取重置验证码' : '验证并重置密码' }}
        </button>

        <div style="margin-top: 15px;">
          <p v-if="currentMode === 'login'" class="toggle-mode" @click="switchMode('forgot')" style="margin-bottom: 8px;">忘记密码？</p>
          <p v-if="['login', 'forgot'].includes(currentMode)" class="toggle-mode" @click="switchMode('register')">没有账号？点击注册</p>
          <p v-if="['register', 'verify_register', 'forgot', 'reset'].includes(currentMode)" class="toggle-mode" @click="switchMode('login')">返回登录</p>
        </div>

      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0, 0, 0, 0.4); display: flex; align-items: center; justify-content: center; z-index: 9999; backdrop-filter: blur(4px); }
.modal-content { background: white; padding: 30px; border-radius: 20px; width: 400px; position: relative; box-shadow: 0 20px 50px rgba(0, 0, 0, 0.15); animation: popIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275); }

.modal-content h2 { text-align: center; color: #db2777; margin-top: 0; margin-bottom: 20px; font-weight: 900; }

.feedback-banner { padding: 10px; border-radius: 8px; font-size: 13px; font-weight: bold; margin-bottom: 15px; text-align: center; animation: slideDown 0.2s ease-out; }
.feedback-banner.error { background: #fef2f2; color: #ef4444; border: 1px solid #fecaca; }
.feedback-banner.success { background: #ecfdf5; color: #10b981; border: 1px solid #a7f3d0; }
.feedback-banner.warning { background: #fffbeb; color: #b45309; border: 1px solid #fde68a; }

.modal-content input { width: 100%; padding: 12px; margin-bottom: 15px; border: 2px solid #f1f5f9; border-radius: 12px; box-sizing: border-box; font-size: 14px; font-weight: bold; outline: none; transition: border-color 0.2s; color: #1e293b; background: #f8fafc; }
.modal-content input:disabled { background: #f1f5f9; color: #94a3b8; cursor: not-allowed; }
.modal-content input:focus { border-color: #f472b6; background: #fff; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }

.toggle-mode { text-align: center; color: #8b5cf6; font-size: 13px; font-weight: bold; margin: 0; cursor: pointer; transition: color 0.2s; }
.toggle-mode:hover { color: #f472b6; text-decoration: underline; }

.btn-primary { width: 100%; padding: 12px; border-radius: 12px; background: #db2777; color: white; border: none; font-weight: bold; font-size: 15px; cursor: pointer; transition: background 0.2s; }
.btn-primary:hover { background: #be185d; }
.btn-primary:disabled { background: #f472b6; cursor: not-allowed; }

@keyframes slideDown {
  from { opacity: 0; transform: translateY(-10px); }
  to { opacity: 1; transform: translateY(0); }
}

@media (max-width: 768px) {
  .modal-content { width: 92% !important; margin: 0 auto; padding: 24px 20px !important; max-height: 85vh; overflow-y: auto; }
}
</style>
