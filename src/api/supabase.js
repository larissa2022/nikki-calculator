import { createClient } from '@supabase/supabase-js'

// 你的 Supabase 配置 (请保留你原本的 URL 和 Anon Key)
const supabaseUrl = 'https://fopyjewbsvusftpqbtml.supabase.co'
const supabaseKey = 'sb_publishable_XxYDVPY0_Ir4kfF-rQCGkA_dtRBH1Yh' 

// 1. 确保开启了自动刷新和持久化会话
export const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
  }
})

// 🌟 2. 核心补丁：监听网页的“唤醒”事件
if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => {
    // 当用户从其他标签页切回当前网页时
    if (document.visibilityState === 'visible') {
      console.log('🔄 网页已唤醒，正在恢复 Supabase 连接...')
      // 强制触发一次 Session 获取，这会让 Supabase 内部重新激活定时器并刷新过期 Token
      supabase.auth.getSession().then(({ error }) => {
        if (error) console.error('唤醒会话失败:', error.message)
      })
    }
  })
}