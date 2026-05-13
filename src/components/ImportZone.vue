<script setup>
import { ref, reactive, onMounted, computed, watch ,nextTick} from 'vue'
import { suitService } from '../api/suitService'
import { contributionService } from '../api/contributionService' // 🌟 新增这行
import { supabase } from '../api/supabase' // 保留这个用于获取 user
import { useWardrobe } from '../composables/useWardrobe'
const props = defineProps({
  wardrobe: { type: Array, required: true },
  ownedIds: { type: Array, required: true },
  quota: { type: Number, default: 0 },
  isLoggedIn: { type: Boolean, default: false }
})

const emit = defineEmits(['update:ownedIds', 'save-cloud', 'refresh-profile'])
const { saveWardrobeToCloud } = useWardrobe()
// ====== 基础状态 ======
const importText = ref('')
const importStats = reactive({ show: false, newCount: 0, dupCount: 0, failCount: 0, newClothes: [] })
const lastNotFoundNames = ref([])
const isRecognizing = ref(false)
const isSaving = ref(false) // 🌟 3. 新增：全局录入锁

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

// 以前这里写了一大堆 supabase.from... 现在只需一行！
onMounted(async () => {
  try {
    availableSuits.value = await suitService.getAllSuits();
  } catch (err) {
    alert('加载套装字典失败，请刷新重试');
  }
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

// ====== 🌟 搜索逻辑强化：防崩溃与符号过滤 ======
const filteredSuits = computed(() => {
  const query = suitSearchText.value?.toLowerCase().trim() || '';
  // 如果搜索框是空的，或者是点选后带《》的，直接返回全列表
  if (!query || query.startsWith('《')) return availableSuits.value;
  // 安全过滤，防止 name 为 null 时报错闪退
  return availableSuits.value.filter(s => s.name && s.name.toLowerCase().includes(query));
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

  isSaving.value = true // 🔒 第一步：咔嚓！锁死所有操作！

  let newCount = 0
  let dupCount = 0
  const notFound = []
  const newlyAdded = []
  
  // 生成准备要存入的最新数组
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

  try {
    if (newCount > 0) {
      // 🛡️ 悲观更新核心：必须先等云端确认保存成功！
      if (props.isLoggedIn) {
        const { data: { user } } = await supabase.auth.getUser()
        if (!user) throw new Error('登录失效，请重新登录')
        
        // 调用我们刚才写的带安全防御的保存机制
        await saveWardrobeToCloud(user.id, updatedOwnedIds)
      }

      // 🛡️ 只有云端没报错（或者未登录的纯本地体验），才允许更新前台 UI ！！
      // 彻底告别假录入！
      emit('update:ownedIds', updatedOwnedIds)
      // 注意：这里不再需要 emit('save-cloud') 了，因为已经在上方存好了
      
      // 渲染报表
      importStats.newCount = newCount
      importStats.dupCount = dupCount
      importStats.failCount = notFound.length
      importStats.newClothes = newlyAdded
      importStats.show = true
      importText.value = ''
    } else if (dupCount > 0 || notFound.length > 0) {
      // 没录入新衣服也要弹报告
      importStats.newCount = 0
      importStats.dupCount = dupCount
      importStats.failCount = notFound.length
      importStats.newClothes = []
      importStats.show = true
      importText.value = ''
    }
  } catch (err) {
    // 🚨 一旦断网、微信杀后台，直接拦截在这里！本地衣服原封不动！
    alert('☁️ 同步云端失败：' + err.message + '\n\n本次录入已自动撤销，请检查网络后重新录入。')
  } finally {
    isSaving.value = false // 🔓 最后一步：无论成败，解开锁
  }
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

    // ... 前面算分的逻辑保留 ...

    const { data: { user } } = await supabase.auth.getUser()

    // 🌟 核心替换：直接呼叫专员提交！
    await contributionService.submitPendingClothes({
      name: name,
      game_id: contribForm.game_id || 'N', 
      category: contribForm.category,      
      stars: Number(contribForm.stars),
      scores: calculatedScores,
      suit_id: contribForm.suit_id || null,
      tags: contribForm.tags || null,
      submitted_by: user?.id,
      status: 'pending'
    })
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
  
  try {
    const { data: { user } } = await supabase.auth.getUser()
    // 🌟 直接呼叫 API
    await suitService.applyNewSuit(newSuitName, user?.id)
    alert('✅ 套装申请已发送给管理员审核！请等待审核通过后再关联该部件。')
  } catch (error) {
    alert('套装申请提交失败！')
  }
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
    const data = await contributionService.recognizeImage(b64, 'clothes')
    importText.value = data.names
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
      <button 
        class="btn btn-primary w-full shadow-lg text-white font-bold" 
        @click="handleImport"
        :disabled="isSaving"
      >
        {{ isSaving ? '☁️ 正在全力同步至云端...' : '🚀 录入到我的云端衣柜' }}
      </button>
    </div>

    <Transition name="fade">
      <div v-if="importStats.show" class="bg-white rounded-[18px] p-5 mt-5 border border-slate-100 shadow-[0_10px_25px_rgba(0,0,0,0.03)]">
        
        <div class="flex justify-between items-center mb-4">
          <h3 class="m-0 text-base font-bold text-slate-600">📊 本次录入报告</h3>
          <button class="btn btn-sm btn-circle btn-ghost bg-slate-100" @click="importStats.show = false">✕</button>
        </div>

        <div class="grid grid-cols-3 gap-2 mb-4">
          <div class="text-center p-2.5 rounded-xl bg-emerald-50 text-emerald-600">
            <span class="block text-[11px] font-bold mb-1">新解锁</span>
            <strong class="text-lg font-black">{{ importStats.newCount }}</strong>
          </div>
          <div class="text-center p-2.5 rounded-xl bg-slate-50 text-slate-500">
            <span class="block text-[11px] font-bold mb-1">已拥有</span>
            <strong class="text-lg font-black">{{ importStats.dupCount }}</strong>
          </div>
          <div class="text-center p-2.5 rounded-xl bg-rose-50 text-rose-600">
            <span class="block text-[11px] font-bold mb-1">缺失</span>
            <strong class="text-lg font-black">{{ importStats.failCount }}</strong>
          </div>
        </div>

        <div v-if="importStats.newClothes.length > 0" class="grid grid-cols-[repeat(auto-fill,minmax(120px,1fr))] gap-2 max-h-[280px] overflow-y-auto pr-1 custom-scroll">
          <div v-for="item in importStats.newClothes" :key="item.id" class="bg-white border border-pink-200 p-2 rounded-xl flex flex-col gap-1 shadow-sm">
            <span class="text-[10px] font-black text-pink-500 bg-pink-50 px-2 py-0.5 rounded-md self-start">{{ item.category }}</span>
            <span class="text-[13px] font-bold text-slate-800">{{ item.name }}</span>
          </div>
        </div>
      </div>
    </Transition>

    <div v-if="lastNotFoundNames.length > 0" class="mt-6 pt-6 border-t-2 border-dashed border-slate-100">
      <div class="mb-4">
        <p class="m-0 text-sm font-bold text-slate-500">😢 发现 {{ lastNotFoundNames.length }} 件图鉴缺失，请帮帮站长：</p>
      </div>
      
      <div class="max-h-[380px] overflow-y-auto pr-2 custom-scroll">
        <div v-for="name in lastNotFoundNames" :key="name" class="bg-white/60 border border-slate-200 rounded-2xl p-3 mb-3 transition-all hover:bg-white">
          <div class="flex justify-between items-center">
            <span class="font-extrabold text-slate-600">{{ name }}</span>
            <button @click="activeContribution = (activeContribution === name ? null : name)" class="btn btn-sm btn-outline btn-secondary rounded-full">
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

              <button class="btn-submit-contrib" @click="submitContribution(name)" :disabled="isSubmittingContrib">
                {{ isSubmittingContrib ? '⌛ 正在加密上传...' : '确认提交申请' }}
              </button>
            </div>
          </Transition>
        </div>
      </div>
    </div>
    
    <Teleport to="body">
      <div v-if="isSaving" class="hard-lock-overlay">
        <div class="hard-lock-box">
          <span class="spinner">⏳</span>
          <span class="loading-text">正在强力写入云端...请勿切出应用！</span>
        </div>
      </div>
    </Teleport>
    
  </div>
</template>

<style scoped>
/* ==========================================
   📥 1. 极速录入容器与头部
   ========================================== */
.panel-header h2 { margin: 0 0 25px 0; color: #db2777; font-size: 20px; font-weight: 900; border-bottom: 2px dashed #fbcfe8; padding-bottom: 12px; }

/* ==========================================
   🤖 2. AI 扫描特区 (目前保持原样)
   ========================================== */
.ai-zone { background: linear-gradient(135deg, #fdf2f8 0%, #f5f3ff 100%); border: 2px dashed #ddd6fe; border-radius: 18px; padding: 20px; margin-bottom: 20px; }
.ai-info-bar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
.quota-badge { background: #fff; color: #7c3aed; padding: 4px 12px; border-radius: 20px; font-size: 13px; font-weight: bold; border: 1px solid #ddd6fe; }
.quota-badge.warning { color: #f43f5e; border-color: #fecdd3; }
.ai-label { font-size: 12px; color: #a78bfa; font-weight: bold; }

.scan-button { display: block; background: linear-gradient(135deg, #7c3aed 0%, #f472b6 100%); color: white; padding: 14px; border-radius: 14px; text-align: center; font-weight: 800; cursor: pointer; transition: all 0.3s; box-shadow: 0 6px 15px rgba(124, 58, 237, 0.2); }
.scan-button:hover { transform: translateY(-2px); box-shadow: 0 8px 20px rgba(124, 58, 237, 0.3); }
.scan-button.scanning { filter: grayscale(1); cursor: wait; }

/* ==========================================
   🎯 3. 补录表单内层专属样式
   ========================================== */
.mini-form-body { margin-top: 15px; padding-top: 15px; border-top: 1px dashed #e2e8f0; }
.form-row { display: grid; gap: 10px; margin-bottom: 12px; }
.three-cols { grid-template-columns: 1fr 1.5fr 1fr; } 

.form-group label { display: block; font-size: 11px; font-weight: bold; color: #94a3b8; margin-bottom: 4px; }

.attr-grid-mini { display: flex; flex-direction: column; gap: 8px; margin-bottom: 15px; }
.attr-line { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.attr-line select { width: 100%; padding: 8px; border-radius: 8px; border: 1px solid #f1f5f9; background: white; font-weight: bold; font-size: 12px; color: #1e293b; outline: none; }
.grade-sel { color: #f472b6 !important; background: #fdf2f8 !important; border-color: #fbcfe8 !important;}

/* 专属补录提交按钮 */
.btn-submit-contrib { width: 100%; background: #a78bfa; color: white; border: none; padding: 12px; border-radius: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s; }
.btn-submit-contrib:hover { background: #8b5cf6; transform: translateY(-1px); }

/* 🌟 移动端防掉线：强制锁定遮罩 */
.hard-lock-overlay { position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: rgba(0,0,0,0.6); backdrop-filter: blur(5px); z-index: 999999; display: flex; align-items: center; justify-content: center; }
.hard-lock-box { background: white; padding: 25px 30px; border-radius: 20px; display: flex; align-items: center; gap: 15px; box-shadow: 0 20px 50px rgba(0,0,0,0.3); animation: popIn 0.3s ease-out; }
.spinner { font-size: 26px; display: inline-block; animation: spin 1.5s linear infinite; }
.loading-text { color: #db2777; font-weight: 900; font-size: 15px; letter-spacing: 0.5px;}

/* 🌟 唯独保留一个精致的通用滚动条样式 */
.custom-scroll { -webkit-overflow-scrolling: touch; }
.custom-scroll::-webkit-scrollbar { width: 4px; }
.custom-scroll::-webkit-scrollbar-thumb { background: #cbd5e1; border-radius: 10px; }
.custom-scroll::-webkit-scrollbar-track { background: transparent; }

@keyframes spin { 100% { transform: rotate(360deg); } }
@keyframes popIn { 0% { opacity: 0; transform: scale(0.9); } 100% { opacity: 1; transform: scale(1); } }

/* ==========================================
   📱 4. 手机端独有适配
   ========================================== */
@media (max-width: 768px) {
  .three-cols { grid-template-columns: 1fr; }
  .import-panel { padding: 15px; }
}
</style>