<script setup>
import { ref, reactive } from 'vue'
import { supabase } from '../api/supabase'

const props = defineProps({
  wardrobe: { type: Array, required: true },
  ownedIds: { type: Array, required: true },
  quota: { type: Number, default: 0 },
  isLoggedIn: { type: Boolean, default: false }
})

const emit = defineEmits(['update:ownedIds', 'save-cloud', 'refresh-profile'])

// ====== 基础状态 ======
const importText = ref('')
const importStats = reactive({ show: false, newCount: 0, dupCount: 0, failCount: 0, newClothes: [] })
const lastNotFoundNames = ref([])
const isRecognizing = ref(false)

// ====== 玩家贡献模块状态 ======
const activeContribution = ref(null)
const isSubmittingContrib = ref(false)
const contribForm = reactive({
  category: '连衣裙', stars: 5,
  pair1: 'simple', grade1: '完美',
  pair2: 'cute', grade2: '完美',
  pair3: 'active', grade3: '完美',
  pair4: 'pure', grade4: '完美',
  pair5: 'cool', grade5: '完美'
})

// ====== 逻辑 1：处理文本导入 ======
const handleImport = async () => {
  const inputNames = importText.value.split(/[,，\s\n]+/).map(n => n.trim()).filter(n => n !== '')
  if (inputNames.length === 0) return alert('请输入衣服名字哦~')

  let newCount = 0
  let dupCount = 0
  const notFound = []
  const newlyAdded = []
  const updatedOwnedIds = [...props.ownedIds]

  inputNames.forEach(name => {
    const found = props.wardrobe.find(item => item.name === name)
    if (found) {
      if (updatedOwnedIds.includes(found.id)) {
        dupCount++
      } else {
        updatedOwnedIds.push(found.id)
        newCount++
        newlyAdded.push(found)
      }
    } else {
      notFound.push(name)
    }
  })

  lastNotFoundNames.value = [...new Set(notFound)]

  if (newCount > 0) {
    emit('update:ownedIds', updatedOwnedIds)
    if (props.isLoggedIn) emit('save-cloud')
  }

  importStats.newCount = newCount
  importStats.dupCount = dupCount
  importStats.failCount = notFound.length
  importStats.newClothes = newlyAdded
  importStats.show = true
  importText.value = ''
}

// ====== 逻辑 2：玩家提交贡献数据 ======
// 新增：防连点和加载状态

const submitContribution = async (name) => {
  isSubmittingContrib.value = true // 🌟 按钮变成加载中
  try {
    const mul = contribForm.category === '连衣裙' ? 4.0 : 
                (contribForm.category.includes('装') || contribForm.category === '上衣' ? 2.0 : 1.0)
    
    const baseScores = { '完美+': 2500, '完美': 2000, '优秀': 1500, '不错': 1000, '一般': 500, '失败': 0 }
    const calculatedScores = {
      simple: 0, gorgeous: 0, cute: 0, mature: 0, active: 0, 
      elegant: 0, pure: 0, sexy: 0, cool: 0, warm: 0
    }
    
    const pairs = [['pair1','grade1'],['pair2','grade2'],['pair3','grade3'],['pair4','grade4'],['pair5','grade5']]
    pairs.forEach(([p, g]) => {
      calculatedScores[contribForm[p]] = baseScores[contribForm[g]] * mul
    })

    const { error } = await supabase.from('pending_clothes').insert([{
      name: name,
      category: contribForm.category,
      stars: Number(contribForm.stars),
      scores: calculatedScores
    }])

    if (error) throw error
    alert(`🎉 感谢小仙女的贡献！【${name}】的详细资料已提交！`)
    lastNotFoundNames.value = lastNotFoundNames.value.filter(n => n !== name)
    activeContribution.value = null
  } catch (err) {
    // 🌟 核心修复：把真实报错印在控制台，并确保弹窗能出来
    console.error("❌ 提交报错详情:", err)
    alert('提交失败，真实原因：' + (err.message || '请按 F12 查看控制台红字'))
  } finally {
    isSubmittingContrib.value = false // 🌟 恢复按钮
  }
}

// ====== 逻辑 3：AI 识别图片 (含压缩) ======
const compressImage = (file) => {
  return new Promise((resolve) => {
    const reader = new FileReader()
    reader.readAsDataURL(file)
    reader.onload = (e) => {
      const img = new Image()
      img.src = e.target.result
      img.onload = () => {
        const canvas = document.createElement('canvas')
        const MAX_WIDTH = 800
        let width = img.width
        let height = img.height
        if (width > MAX_WIDTH) {
          height = Math.round((height * MAX_WIDTH) / width)
          width = MAX_WIDTH
        }
        canvas.width = width
        canvas.height = height
        const ctx = canvas.getContext('2d')
        ctx.drawImage(img, 0, 0, width, height)
        resolve(canvas.toDataURL('image/jpeg', 0.7))
      }
    }
  })
}

const onFileChange = async (event) => {
  const file = event.target.files[0]
  if (!file) return
  isRecognizing.value = true
  try {
    const b64 = await compressImage(file)
    const { data, error } = await supabase.functions.invoke('recognize-clothing', {
      body: { imageBase64: b64 }
    })
    if (error) throw error
    importText.value = data.names
    await handleImport()
    emit('refresh-profile')
  } catch (err) {
    alert(`识别失败: ${err.message}`)
  } finally {
    isRecognizing.value = false
    event.target.value = ''
  }
}
</script>

<template>
  <div class="import-panel glass-card">
    <div class="panel-header">
      <h2>📥 极速录入衣柜</h2>
    </div>
    
    <div class="ai-zone">
      <div class="ai-info-bar">
        <span class="quota-badge" :class="{ 'warning': quota < 5 }">
          ✨ 剩余 AI 次数：{{ quota }}
        </span>
        <span class="ai-label">智能扫视技术已就绪</span>
      </div>
      
      <label class="scan-button" :class="{ 'scanning': isRecognizing }">
        <span v-if="!isRecognizing">📸 上传截图一键识别</span>
        <span v-else>🔍 正在提取服装信息...</span>
        <input type="file" accept="image/*" @change="onFileChange" :disabled="isRecognizing" hidden />
      </label>
    </div>

    <div class="manual-input">
      <textarea v-model="importText" rows="3" placeholder="也可以在这里输入衣服名字，用逗号隔开..."></textarea>
      <button class="btn-primary" @click="handleImport">🚀 录入到我的云端衣柜</button>
    </div>

    <Transition name="fade">
      <div v-if="importStats.show" class="report-box">
        <div class="report-header">
          <h3>📊 本次录入报告</h3>
          <button class="btn-close-mini" @click="importStats.show = false">×</button>
        </div>
        <div class="stats-summary">
          <div class="stat-item success"><span>新解锁</span><strong>{{ importStats.newCount }}</strong></div>
          <div class="stat-item skip"><span>已拥有</span><strong>{{ importStats.dupCount }}</strong></div>
          <div class="stat-item missing"><span>缺失</span><strong>{{ importStats.failCount }}</strong></div>
        </div>

        <div v-if="importStats.newClothes.length > 0" class="loot-display">
          <div v-for="item in importStats.newClothes" :key="item.id" class="loot-card">
            <span class="loot-tag">{{ item.category }}</span>
            <span class="loot-name">{{ item.name }}</span>
          </div>
        </div>
      </div>
    </Transition>

    <div v-if="lastNotFoundNames.length > 0" class="contribution-section">
      <div class="contrib-header">
        <p>😢 发现 {{ lastNotFoundNames.length }} 件图鉴缺失，请帮帮站长：</p>
      </div>
      
      <div class="missing-items-list">
        <div v-for="name in lastNotFoundNames" :key="name" class="contrib-card">
          <div class="contrib-row">
            <span class="missing-name">{{ name }}</span>
            <button @click="activeContribution = (activeContribution === name ? null : name)" class="btn-action-outline">
              {{ activeContribution === name ? '收起' : '✍️ 完善资料' }}
            </button>
          </div>

          <Transition name="slide">
            <div v-if="activeContribution === name" class="mini-form-body">
              <div class="form-row">
                <div class="form-group">
                  <label>分类</label>
                  <select v-model="contribForm.category">
                    <option v-for="cat in ['发型','连衣裙','外套','上装','下装','袜子','鞋子','饰品','妆容']" :key="cat">{{cat}}</option>
                  </select>
                </div>
                <div class="form-group">
                  <label>星级</label>
                  <select v-model="contribForm.stars">
                    <option v-for="s in 6" :key="s" :value="s">{{s}} 星</option>
                  </select>
                </div>
              </div>

              <div class="attr-grid-mini">
                <div v-for="i in 5" :key="i" class="attr-line">
                  <select v-model="contribForm['pair'+i]">
                    <option v-if="i==1" value="simple">简约</option><option v-if="i==1" value="gorgeous">华丽</option>
                    <option v-if="i==2" value="cute">可爱</option><option v-if="i==2" value="mature">成熟</option>
                    <option v-if="i==3" value="active">活泼</option><option v-if="i==3" value="elegant">优雅</option>
                    <option v-if="i==4" value="pure">清纯</option><option v-if="i==4" value="sexy">性感</option>
                    <option v-if="i==5" value="cool">清凉</option><option v-if="i==5" value="warm">保暖</option>
                  </select>
                  <select v-model="contribForm['grade'+i]" class="grade-sel">
                    <option v-for="g in ['完美+','完美','优秀','不错','一般']" :key="g">{{g}}</option>
                  </select>
                </div>
              </div>

              <button class="btn-submit-contrib" @click="submitContribution(name)">确认提交申请</button>
            </div>
          </Transition>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* 容器 */
.import-panel { 
  background: rgba(255, 255, 255, 0.85);
  border: 1px solid rgba(255, 255, 255, 0.3);
  padding: 30px; 
  border-radius: 24px; 
  margin-bottom: 25px;
}
.panel-header h2 { 
  margin: 0 0 25px 0; color: #db2777; font-size: 20px; font-weight: 900;
  border-bottom: 2px dashed #fbcfe8; padding-bottom: 12px;
}

/* AI 扫描区 */
.ai-zone {
  background: linear-gradient(135deg, #fdf2f8 0%, #f5f3ff 100%);
  border: 2px dashed #ddd6fe; border-radius: 18px; padding: 20px; margin-bottom: 20px;
}
.ai-info-bar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
.quota-badge { 
  background: #fff; color: #7c3aed; padding: 4px 12px; border-radius: 20px; 
  font-size: 13px; font-weight: bold; border: 1px solid #ddd6fe;
}
.quota-badge.warning { color: #f43f5e; border-color: #fecdd3; }
.ai-label { font-size: 12px; color: #a78bfa; font-weight: bold; }

.scan-button {
  display: block; background: linear-gradient(135deg, #7c3aed 0%, #f472b6 100%);
  color: white; padding: 14px; border-radius: 14px; text-align: center;
  font-weight: 800; cursor: pointer; transition: all 0.3s;
  box-shadow: 0 6px 15px rgba(124, 58, 237, 0.2);
}
.scan-button:hover { transform: translateY(-2px); box-shadow: 0 8px 20px rgba(124, 58, 237, 0.3); }
.scan-button.scanning { filter: grayscale(1); cursor: wait; }

/* 文本区 */
textarea {
  width: 100%; padding: 15px; border-radius: 14px; border: 2px solid #f1f5f9;
  background: #f8fafc; margin-bottom: 12px; box-sizing: border-box; outline: none;
  transition: all 0.2s; font-family: inherit;
}
textarea:focus { border-color: #f472b6; background: #fff; box-shadow: 0 0 0 4px rgba(244, 114, 182, 0.1); }

/* 解析报告 (SSR 卡片风格) */
.report-box {
  background: white; border-radius: 18px; padding: 20px; margin-top: 20px;
  border: 1px solid #f1f5f9; box-shadow: 0 10px 25px rgba(0,0,0,0.03);
}
.report-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
.report-header h3 { margin: 0; font-size: 16px; color: #475569; }
.btn-close-mini { background: #f1f5f9; border: none; width: 24px; height: 24px; border-radius: 50%; cursor: pointer; }

.stats-summary { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 10px; margin-bottom: 20px; }
.stat-item { text-align: center; padding: 10px; border-radius: 12px; }
.stat-item span { display: block; font-size: 11px; margin-bottom: 4px; font-weight: bold; }
.stat-item strong { font-size: 18px; font-weight: 900; }
.success { background: #ecfdf5; color: #059669; }
.skip { background: #f8fafc; color: #64748b; }
.missing { background: #fff1f2; color: #e11d48; }

.loot-display { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 8px; }
.loot-card { 
  background: #fff; border: 1px solid #fbcfe8; padding: 8px 12px; border-radius: 10px;
  display: flex; flex-direction: column; gap: 4px; box-shadow: 0 2px 6px rgba(244, 114, 182, 0.05);
}
.loot-tag { font-size: 10px; font-weight: 900; color: #f472b6; background: #fdf2f8; padding: 2px 6px; border-radius: 6px; align-self: flex-start; }
.loot-name { font-size: 13px; font-weight: bold; color: #1e293b; }

/* 玩家贡献模块 (重塑后的) */
.contribution-section { margin-top: 25px; padding-top: 25px; border-top: 2px dashed #f1f5f9; }
.contrib-header p { margin: 0 0 15px 0; font-size: 14px; font-weight: bold; color: #64748b; }

.contrib-card { 
  background: rgba(255, 255, 255, 0.6); border: 1px solid #e2e8f0; 
  border-radius: 16px; padding: 12px; margin-bottom: 12px; transition: all 0.3s;
}
.contrib-row { display: flex; justify-content: space-between; align-items: center; }
.missing-name { font-weight: 800; color: #4b5563; }
.btn-action-outline { 
  background: #fff; border: 1.5px solid #ddd6fe; color: #8b5cf6;
  padding: 6px 14px; border-radius: 20px; font-size: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s;
}
.btn-action-outline:hover { background: #8b5cf6; color: white; border-color: #8b5cf6; }

/* 贡献表单内部 */
.mini-form-body { margin-top: 15px; padding-top: 15px; border-top: 1px dashed #e2e8f0; }
.form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 12px; }
.form-group label { display: block; font-size: 11px; font-weight: bold; color: #94a3b8; margin-bottom: 4px; }
.form-group select, .attr-line select { 
  width: 100%; padding: 8px; border-radius: 8px; border: 1px solid #f1f5f9; 
  background: white; font-weight: bold; font-size: 13px; color: #1e293b;
}

.attr-grid-mini { display: flex; flex-direction: column; gap: 8px; margin-bottom: 15px; }
.attr-line { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.grade-sel { color: #f472b6 !important; background: #fdf2f8 !important; }

.btn-submit-contrib {
  width: 100%; background: #a78bfa; color: white; border: none; padding: 12px;
  border-radius: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s;
}
.btn-submit-contrib:hover { background: #8b5cf6; transform: translateY(-1px); }

/* 动画 */
.fade-enter-active, .fade-leave-active { transition: opacity 0.3s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }

.slide-enter-active { transition: all 0.3s ease-out; }
.slide-enter-from { opacity: 0; transform: translateY(-10px); }
</style>