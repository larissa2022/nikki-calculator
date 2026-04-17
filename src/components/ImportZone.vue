<script setup>
import { ref, reactive } from 'vue'
import { supabase } from '../api/supabase' // 根据你的实际路径调整，如果在上一级目录请用 '../supabase'

// 1. 定义从 App.vue 接收的数据
const props = defineProps({
  wardrobe: { type: Array, required: true }, // 完整图鉴
  ownedIds: { type: Array, required: true }, // 我拥有的衣服ID
  quota: { type: Number, default: 0 },       // AI 剩余额度
  isLoggedIn: { type: Boolean, default: false } // 是否已登录
})

// 2. 定义向 App.vue 发送的事件 (通知父组件更新数据)
const emit = defineEmits(['update:ownedIds', 'save-cloud', 'refresh-profile'])

// ====== 组件内部状态 ======
const importText = ref('')
const importStats = reactive({ show: false, newCount: 0, dupCount: 0, failCount: 0 })
const lastNotFoundNames = ref([])
const isRecognizing = ref(false)

// ====== 核心逻辑 1：处理文本导入与比对 ======
const handleImport = async () => {
  const inputNames = importText.value.split(/[,，\s\n]+/).map(n => n.trim()).filter(n => n !== '')
  if (inputNames.length === 0) return alert('请输入名字')

  let newCount = 0
  let dupCount = 0
  const notFound = []
  
  // 复制一份最新的拥有的衣服 ID 列表
  const updatedOwnedIds = [...props.ownedIds]

  inputNames.forEach(name => {
    const found = props.wardrobe.find(item => item.name === name)
    if (found) {
      if (updatedOwnedIds.includes(found.id)) {
        dupCount++
      } else {
        updatedOwnedIds.push(found.id)
        newCount++
      }
    } else {
      notFound.push(name)
    }
  })

  lastNotFoundNames.value = [...new Set(notFound)] 

  // 如果有新衣服加入，通知父组件更新数据并保存到云端
  if (newCount > 0) {
    emit('update:ownedIds', updatedOwnedIds)
    if (props.isLoggedIn) {
      emit('save-cloud') 
    }
  }

  // 显示数据报告面板
  importStats.newCount = newCount
  importStats.dupCount = dupCount
  importStats.failCount = notFound.length
  importStats.show = true

  importText.value = ''
}

// ====== 核心逻辑 2：处理 AI 图像识别 ======
const onFileChange = async (e) => {
  const file = e.target.files[0]
  if (!file) return
  
  if (!props.isLoggedIn) {
    alert("请先登录账号，才能使用 AI 识别功能哦！")
    return
  }

  isRecognizing.value = true
  try {
    const reader = new FileReader()
    reader.readAsDataURL(file)
    reader.onload = async () => {
      const base64 = reader.result.split(',')[1]
      
      // 先手动获取当前最新、最热乎的登录凭证
      const { data: { session } } = await supabase.auth.getSession()
      
      // 在发请求时，强行把凭证塞进 Headers 里
      const { data, error } = await supabase.functions.invoke('recognize-clothing', {
        body: { imageBase64: base64 },
        headers: {
          Authorization: `Bearer ${session?.access_token}` // 🌟 核心修复：手动递交通行证
        }
      })

      if (error) throw new Error(error.message || "识别出了点小差错")
      
      importText.value = data.names
      await handleImport()
      
      // 识别扣费完成后，通知父组件重新获取最新额度
      emit('refresh-profile')
    }
  } catch (err) {
    alert('AI 罢工了：' + err.message)
  } finally {
    isRecognizing.value = false
    e.target.value = '' 
  }
}

// ====== 核心逻辑 3：提交图鉴缺失申请 ======
const submitRequest = async (name) => {
  try {
    const { error } = await supabase.from('pending_clothes').insert([{ name: name }])
    if (error) throw error
    alert(`【${name}】的添加申请已发送给站长！`)
    // 提交成功后从列表中移除
    lastNotFoundNames.value = lastNotFoundNames.value.filter(n => n !== name)
  } catch (err) { 
    alert('提交申请失败：' + err.message) 
  }
}
</script>

<template>
  <div class="import-panel">
    <h2>📥 批量录入新衣服</h2>
    
    <div class="ai-recognition-zone">
      <div class="ai-header">
        <div class="quota-info">
          ✨ 剩余 AI 识别次数：<strong :class="{ 'low-quota': quota < 5 }">{{ quota }}</strong> 次
        </div>
        <p class="ai-tip">提示：上传衣柜截图，AI 自动帮你录入</p>
      </div>
      
      <label class="ai-upload-btn" :class="{ 'is-loading': isRecognizing }">
        <span v-if="!isRecognizing">📸 截图一键识别导入</span>
        <span v-else>🔍 正在通过 AI 扫视衣柜...</span>
        <input 
          type="file" 
          accept="image/*" 
          @change="onFileChange" 
          :disabled="isRecognizing" 
          hidden 
        />
      </label>
    </div>
    
    <textarea v-model="importText" rows="3" placeholder="输入服装名字(如: 默认粉毛, 运动少年)..."></textarea>
    <button class="btn-primary" @click="handleImport">解析并保存到云端</button>
    
    <div v-if="importStats.show" class="import-stats-box">
      <h3>📊 解析报告</h3>
      <ul class="stats-list">
        <li class="stat-new">✅ 成功录入新服装：<strong>{{ importStats.newCount }}</strong> 件</li>
        <li class="stat-dup">🔁 已拥有并自动跳过：<strong>{{ importStats.dupCount }}</strong> 件</li>
        <li class="stat-fail">❌ 图鉴未找到：<strong>{{ importStats.failCount }}</strong> 件</li>
      </ul>
      <button @click="importStats.show = false" class="btn-clear-alert">关闭报告</button>
    </div>

    <div v-if="lastNotFoundNames.length > 0" class="not-found-alert">
      <p>😢 下列衣服图鉴中暂时没有，点击可提交添加申请：</p>
      <div class="not-found-tags">
        <div v-for="name in lastNotFoundNames" :key="name" class="missing-tag">
          {{ name }}
          <button @click="submitRequest(name)" class="btn-quick-add">申请添加</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.import-panel { 
  background: #fff; padding: 25px; border-radius: 12px; 
  box-shadow: 0 4px 15px rgba(0,0,0,0.05); margin-bottom: 20px; 
  animation: fadeIn 0.3s ease;
}

textarea { 
  width: 100%; padding: 15px; box-sizing: border-box; 
  border: 1px solid #ddd; border-radius: 8px; 
  font-family: monospace; resize: vertical; 
  margin-bottom: 10px;
}

.btn-primary { 
  background: #f472b6; color: white; width: 100%; 
  padding: 12px; font-size: 16px; border: none; 
  border-radius: 8px; font-weight: bold; cursor: pointer;
}
.btn-primary:hover { background: #ec4899; }

.btn-clear-alert {
  background: #e2e8f0; color: #475569; border: none; 
  padding: 6px 12px; border-radius: 6px; cursor: pointer; 
  font-size: 12px; margin-top: 5px;
}

/* AI 识别区专属样式 */
.ai-recognition-zone {
  background: linear-gradient(135deg, #fdf2f8 0%, #f5f3ff 100%);
  border: 2px dashed #ddd6fe; padding: 20px; border-radius: 12px;
  margin-bottom: 20px; text-align: center;
}
.ai-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
.quota-info { font-size: 14px; color: #6d28d9; font-weight: bold; }
.low-quota { color: #ef4444; }
.ai-tip { font-size: 12px; color: #9ca3af; margin: 0; }

.ai-upload-btn {
  display: block; background: #7c3aed; color: white;
  padding: 12px; border-radius: 10px; font-weight: bold;
  cursor: pointer; transition: all 0.3s;
  box-shadow: 0 4px 12px rgba(124, 58, 237, 0.2);
}
.ai-upload-btn:hover { background: #6d28d9; transform: translateY(-2px); }
.ai-upload-btn.is-loading { background: #a78bfa; cursor: not-allowed; }

/* 导入报告面板样式 */
.import-stats-box { background: #f8fafc; border: 1px solid #e2e8f0; padding: 15px; border-radius: 8px; margin-top: 15px; }
.import-stats-box h3 { margin: 0 0 10px 0; font-size: 15px; color: #334155; }
.stats-list { list-style: none; padding: 0; margin: 0 0 12px 0; font-size: 14px; }
.stats-list li { margin-bottom: 6px; }
.stat-new { color: #10b981; }
.stat-dup { color: #64748b; }
.stat-fail { color: #ef4444; }

/* UGC审核相关 */
.not-found-alert { background: #fffbeb; border: 1px solid #fde68a; padding: 15px; border-radius: 8px; margin-top: 15px; }
.not-found-tags { display: flex; flex-wrap: wrap; gap: 8px; margin: 10px 0; }
.missing-tag { background: #fef3c7; color: #92400e; padding: 4px 10px; border-radius: 4px; font-size: 13px; display: flex; align-items: center; gap: 5px;}
.btn-quick-add { background: #7c3aed; color: white; border: none; padding: 2px 6px; border-radius: 4px; font-size: 11px; cursor: pointer; }

@media (max-width: 480px) {
  .ai-header { flex-direction: column; gap: 8px; }
}
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(5px); }
  to { opacity: 1; transform: translateY(0); }
}
</style>