<script setup>
import { ref, reactive, onMounted, computed, watch ,nextTick} from 'vue'
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

// ====== 🌟 玩家贡献模块状态 ======
const activeContribution = ref(null)
const isSubmittingContrib = ref(false)
const availableSuits = ref([])

// 🌟 终极分类字典同步
const fullCategories = [
  '发型', '连衣裙', '外套', '上装', '下装', '袜子-袜套', '袜子-袜子', '鞋子', '妆容', '萤光之灵', 
  '饰品-头饰-发饰', '饰品-头饰-头纱', '饰品-头饰-发卡', '饰品-头饰-耳朵', '饰品-耳饰', '饰品-颈饰-围巾', '饰品-颈饰-项链', 
  '饰品-手饰-右', '饰品-手饰-左', '饰品-手饰-双', '饰品-手持-右', '饰品-手持-左', '饰品-手持-双', '饰品-腰饰', 
  '饰品-特殊-面饰', '饰品-特殊-胸饰', '饰品-特殊-纹身', '饰品-特殊-翅膀', '饰品-特殊-尾巴', '饰品-特殊-前景', '饰品-特殊-后景', '饰品-特殊-顶饰', '饰品-特殊-地面', '饰品-皮肤'
]

// 🌟 新增：搜索套装选择器状态
const suitSearchText = ref('')
const isSuitDropdownOpen = ref(false)

onMounted(async () => {
  const { data } = await supabase.from('suits').select('id, name').order('created_at', { ascending: false })
  if (data) availableSuits.value = data
})

const contribForm = reactive({
  suit_id: '',
  game_id: '', // 🌟 新增编号录入
  tags: '', // 🌟 新增：特殊标签
  category: '连衣裙', stars: 5,
  pair1: 'simple', grade1: '完美',
  pair2: 'cute', grade2: '完美',
  pair3: 'active', grade3: '完美',
  pair4: 'pure', grade4: '完美',
  pair5: 'cool', grade5: '完美'
})

// 监听展开状态，清空残留表单
watch(activeContribution, () => {
  suitSearchText.value = ''
  contribForm.suit_id = ''
  contribForm.game_id = ''
})

// ====== 🌟 搜索逻辑：计算过滤后的套装 ======
const filteredSuits = computed(() => {
  const query = suitSearchText.value.toLowerCase().trim()
  if (!query) return availableSuits.value
  return availableSuits.value.filter(s => s.name.toLowerCase().includes(query))
})

const selectSuit = (suit) => {
  contribForm.suit_id = suit.id
  suitSearchText.value = suit.id ? `《${suit.name}》` : ''
  isSuitDropdownOpen.value = false
}


// ====== 逻辑 1：处理文本导入 ======
const handleImport = async () => {
  const inputNames = importText.value.split(/[,，\s\n]+/).map(n => n.trim()).filter(n => n !== '')
  if (inputNames.length === 0) return alert('请输入衣服名字哦~')

  let newCount = 0
  let dupCount = 0
  const notFound = []
  const newlyAdded = []
  
  // 🌟 使用一个全新的数组来装载合并后的结果
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

  // 🌟 核心修复区：确保数据同步与云端保存
  if (newCount > 0) {
    // 1. 先把新的拥有列表发给父组件
    emit('update:ownedIds', updatedOwnedIds)
    
    // 2. 等待 Vue 完成这波数据更新 (极度重要，防止保存空数据)
    await nextTick() 
    
    // 3. 如果已登录，强制命令父组件把最新的列表存到云端
    if (props.isLoggedIn) {
      emit('save-cloud')
    }
  }

  // 渲染报表
  importStats.newCount = newCount
  importStats.dupCount = dupCount
  importStats.failCount = notFound.length
  importStats.newClothes = newlyAdded
  importStats.show = true
  importText.value = ''
}

// ====== 逻辑 2：玩家提交贡献数据 ======
const submitContribution = async (name) => {
  isSubmittingContrib.value = true 
  try {
    // 🌟 终极解密：奇迹暖暖官方固定分值字典
    const baseScoreMatrix = {
      '发型': { '完美+': 1324.5, '完美': 1089, '优秀': 837, '不错': 682.5, '一般': 517.5, '失败': 0 },
      '连衣裙': { '完美+': 5269.5, '完美': 4305, '优秀': 3366, '不错': 2749.5, '一般': 2100, '失败': 0 },
      '外套': { '完美+': 525, '完美': 423, '优秀': 331.5, '不错': 270, '一般': 213, '失败': 0 },
      '上装': { '完美+': 2619, '完美': 2140.5, '优秀': 1678.5, '不错': 1369.5, '一般': 1041, '失败': 0 },
      '下装': { '完美+': 2632.5, '完美': 2137.5, '优秀': 1678.5, '不错': 1357.5, '一般': 1041, '失败': 0 },
      '袜子': { '完美+': 789, '完美': 648, '优秀': 502.5, '不错': 403.5, '一般': 305, '失败': 0 },
      '鞋子': { '完美+': 1050, '完美': 855, '优秀': 667.5, '不错': 541.5, '一般': 423, '失败': 0 },
      '饰品': { '完美+': 526.5, '完美': 424.5, '优秀': 330, '不错': 271.5, '一般': 213, '失败': 0 },
      '妆容': { '完美+': 267, '完美': 213, '优秀': 168, '不错': 125, '一般': 85, '失败': 0 },
      '萤光之灵': { '完美+': 517.5, '完美': 421.5, '优秀': 325.5, '不错': 264, '一般': 200, '失败': 0 }
    };

    // 智能大类提取器
    const getBroadCat = (cat) => {
      if (cat.includes('袜子')) return '袜子';
      if (cat.includes('饰品')) return '饰品';
      if (cat.includes('上')) return '上装';
      if (cat.includes('下')) return '下装';
      return cat;
    };

    const broadCat = getBroadCat(contribForm.category);
    const matrix = baseScoreMatrix[broadCat] || baseScoreMatrix['饰品'];

    const calculatedScores = {
      simple: 0, gorgeous: 0, cute: 0, mature: 0, active: 0, 
      elegant: 0, pure: 0, sexy: 0, cool: 0, warm: 0
    }
    
    const pairs = [['pair1','grade1'],['pair2','grade2'],['pair3','grade3'],['pair4','grade4'],['pair5','grade5']]
    pairs.forEach(([p, g]) => {
      // 🌟 直接从字典取值，分毫不差！
      calculatedScores[contribForm[p]] = matrix[contribForm[g]] || 0;
    })

    // 🌟 核心修复 1：先获取当前点击提交按钮的玩家身份
    const { data: { user } } = await supabase.auth.getUser()

    // 🌟 核心修复 2：在插入数据时，把玩家 ID (submitted_by) 一起写进数据库
    const { error } = await supabase.from('pending_clothes').insert([{
      name: name,
      game_id: contribForm.game_id || 'N', 
      category: contribForm.category,      
      stars: Number(contribForm.stars),
      scores: calculatedScores,
      suit_id: contribForm.suit_id || null,
      tags: contribForm.tags || null,
      submitted_by: user?.id, // 👈 🌟 补上这句极其重要的“署名”！
      status: 'pending'       // 👈 🌟 确保有初始状态
    }])

    if (error) throw error
    alert(`🎉 感谢小仙女的贡献！【${name}】的详细资料已提交！`)
    lastNotFoundNames.value = lastNotFoundNames.value.filter(n => n !== name)
    activeContribution.value = null
  } catch (err) {
    console.error("❌ 提交报错详情:", err)
    alert('提交失败，真实原因：' + (err.message || '请按 F12 查看控制台红字'))
  } finally {
    isSubmittingContrib.value = false 
  }
}

// 🌟 一键申请新套装功能
const promptAddNewSuit = async () => {
  const newSuitName = prompt('请输入要申请添加的新套装名称：')
  if (!newSuitName || !newSuitName.trim()) return
  
  const { data: { user } } = await supabase.auth.getUser()
  const { error } = await supabase.from('pending_suits').insert([{
    name: newSuitName.trim(),
    submitted_by: user?.id,
    status: 'pending'
  }])
  
  if (error) alert('套装申请提交失败！')
  else alert('✅ 套装申请已发送给管理员审核！请等待审核通过后再关联该部件。')
}

// ====== 逻辑 3：AI 识别图片 ======
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
              <div class="form-row" style="grid-template-columns: 1fr;">
                <div class="form-group">
                  <label>所属套装 (选填)</label>
                  <div style="display: flex; gap: 8px;">
                    <div class="searchable-select" style="flex: 1;">
                      <input 
                        type="text" 
                        v-model="suitSearchText" 
                        @focus="isSuitDropdownOpen = true"
                        @blur="setTimeout(() => isSuitDropdownOpen = false, 200)"
                        placeholder="🔍 搜索并选择套装..."
                        class="search-input"
                      />
                      <Transition name="slide">
                        <div v-if="isSuitDropdownOpen" class="select-dropdown">
                          <div class="option" @click="selectSuit({id: '', name: ''})">-- 作为散件 (无关联套装) --</div>
                          <div v-for="s in filteredSuits" :key="s.id" class="option" @click="selectSuit(s)">
                            《{{ s.name }}》
                          </div>
                          <div v-if="filteredSuits.length === 0" class="option empty-option">未找到匹配套装</div>
                        </div>
                      </Transition>
                    </div>
                    <button @click="promptAddNewSuit" class="btn-action-outline" style="white-space: nowrap; padding: 0 10px;">
                      ➕ 申请新套装
                    </button>
                  </div>
                </div>
              </div>

              <div class="form-row three-cols">
                <div class="form-group">
                  <label>短编号(如001)</label>
                  <input type="text" v-model="contribForm.game_id" class="custom-input" placeholder="选填" />
                </div>
                <div class="form-group">
                  <label>分类部位</label>
                  <select v-model="contribForm.category" class="custom-input">
                    <option v-for="cat in fullCategories" :key="cat">{{cat}}</option>
                  </select>
                </div>
                <div class="form-group">
                  <label>星级</label>
                  <select v-model="contribForm.stars" class="custom-input">
                    <option v-for="s in 6" :key="s" :value="s">{{s}} 星</option>
                  </select>
                </div>
              </div>
              <div class="form-row">
                <div class="form-group">
                  <label>特殊标签</label>
                  <input type="text" v-model="contribForm.tags" class="custom-input" placeholder="如: 洛丽塔, 中式古典..." />
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
                  <select v-model="contribForm['grade'+i]" class="grade-sel custom-input" style="padding: 6px;">
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
/* 🌟 搜索下拉框样式 (同步自 AdminPanel) */
.searchable-select { position: relative; width: 100%; }
.search-input { width: 100%; padding: 8px 12px; border: 1px solid #f1f5f9; border-radius: 8px; outline: none; font-weight: bold; background: #fff; cursor: text; font-size: 13px; box-sizing: border-box;}
.search-input:focus { border-color: #f472b6; box-shadow: 0 0 0 2px rgba(244, 114, 182, 0.1); }
.select-dropdown {
  position: absolute; top: 100%; left: 0; right: 0; margin-top: 5px;
  background: white; border: 1.5px solid #fbcfe8; border-radius: 12px;
  max-height: 200px; overflow-y: auto; z-index: 1000;
  box-shadow: 0 10px 25px rgba(0,0,0,0.1);
}
.option { padding: 10px 12px; cursor: pointer; font-size: 12px; color: #4b5563; border-bottom: 1px solid #f1f5f9; }
.option:last-child { border-bottom: none; }
.option:hover { background: #fdf2f8; color: #db2777; font-weight: bold; }
.empty-option { text-align: center; color: #94a3b8; padding: 15px; font-style: italic; pointer-events: none; }

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

/* 解析报告 */
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

/* 玩家贡献模块 */
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
.form-row { display: grid; gap: 10px; margin-bottom: 12px; }
.three-cols { grid-template-columns: 1fr 1.5fr 1fr; } /* 🌟 三列排版 */

.form-group label { display: block; font-size: 11px; font-weight: bold; color: #94a3b8; margin-bottom: 4px; }
.custom-input { 
  width: 100%; padding: 8px; border-radius: 8px; border: 1px solid #f1f5f9; 
  background: white; font-weight: bold; font-size: 12px; color: #1e293b;
  box-sizing: border-box; outline: none; transition: border-color 0.2s;
}
.custom-input:focus { border-color: #f472b6; }

.attr-grid-mini { display: flex; flex-direction: column; gap: 8px; margin-bottom: 15px; }
.attr-line { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.attr-line select {
  width: 100%; padding: 8px; border-radius: 8px; border: 1px solid #f1f5f9; 
  background: white; font-weight: bold; font-size: 12px; color: #1e293b; outline: none;
}
.grade-sel { color: #f472b6 !important; background: #fdf2f8 !important; border-color: #fbcfe8 !important;}

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
@media (max-width: 768px) {
  .three-cols {
    grid-template-columns: 1fr; /* 把新短编号、分类等强制变成单列 */
  }
  .import-panel {
    padding: 15px;
  }
}
</style>