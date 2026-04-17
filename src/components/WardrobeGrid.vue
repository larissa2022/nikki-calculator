<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  wardrobe: { type: Array, required: true }, // 完整图鉴
  ownedIds: { type: Array, required: true }, // 已拥有ID
  isLoggedIn: { type: Boolean, default: false }
})

const emit = defineEmits(['update:ownedIds', 'save-cloud'])

const searchQuery = ref('')
const isSelectMode = ref(false)
const selectedIds = ref([])

// 🌟 核心逻辑：按分类对已拥有的服装进行分组
const groupedOwnedClothes = computed(() => {
  const groups = {}
  const wardrobeSet = new Set(props.ownedIds)
  const searchStr = searchQuery.value.trim()
  
  const filtered = props.wardrobe.filter(c => 
    wardrobeSet.has(c.id) && c.name.includes(searchStr)
  )

  filtered.forEach(item => { 
    if (!groups[item.category]) groups[item.category] = []
    groups[item.category].push(item) 
  })
  return groups
})

// 单件删除
const confirmRemove = (item) => {
  if (confirm(`确定要从衣柜中移除【${item.name}】吗？`)) {
    const updated = props.ownedIds.filter(id => id !== item.id)
    emit('update:ownedIds', updated)
    if (props.isLoggedIn) emit('save-cloud')
  }
}

// 批量删除
const batchDelete = () => {
  if (selectedIds.value.length === 0) return
  if (confirm(`确认永久移除选中的 ${selectedIds.value.length} 件服装？`)) {
    const updated = props.ownedIds.filter(id => !selectedIds.value.includes(id))
    emit('update:ownedIds', updated)
    selectedIds.value = []
    isSelectMode.value = false
    if (props.isLoggedIn) emit('save-cloud')
  }
}
</script>

<template>
  <div class="wardrobe-gallery">
    <div class="gallery-header">
      <h2>👗 我的衣柜 ({{ ownedIds.length }} 件)</h2>
      <div class="gallery-controls">
        <input type="text" v-model="searchQuery" placeholder="🔍 搜索名称..." class="search-box" />
        <button @click="isSelectMode = !isSelectMode" :class="{ 'btn-active-mode': isSelectMode }">
          {{ isSelectMode ? '取消选择' : '批量管理' }}
        </button>
        <button v-if="isSelectMode" @click="batchDelete" class="btn-danger-action" :disabled="selectedIds.length === 0">
          永久移除({{ selectedIds.length }})
        </button>
      </div>
    </div>
    
    <div class="category-sections">
      <div v-for="(clothes, cat) in groupedOwnedClothes" :key="cat" class="cat-block">
        <h3 class="cat-title">{{ cat }} <span class="cat-count">({{ clothes.length }})</span></h3>
        <div class="tags-container">
          <div v-for="item in clothes" :key="item.id" class="clothes-tag" :class="{ 'is-selected': selectedIds.includes(item.id) }">
            <input v-if="isSelectMode" type="checkbox" :value="item.id" v-model="selectedIds" />
            <span class="tag-name" @click="isSelectMode ? null : confirmRemove(item)">{{ item.name }}</span>
            <button v-if="!isSelectMode" class="tag-remove" @click="confirmRemove(item)">×</button>
          </div>
        </div>
      </div>
      <div v-if="Object.keys(groupedOwnedClothes).length === 0" class="empty-tip">
        {{ searchQuery ? '没搜到相关衣服哦~' : '衣柜空空如也，快去录入新衣服吧！' }}
      </div>
    </div>
  </div>
</template>

<style scoped>
/* 此处包含之前 App.vue 中关于 .wardrobe-gallery 及内部的所有样式 */
.wardrobe-gallery { background: #fff; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); animation: fadeIn 0.3s ease;}
.gallery-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; flex-wrap: wrap; gap: 10px;}
.search-box { padding: 8px 15px; border: 1px solid #ddd; border-radius: 20px; outline: none; width: 180px; font-size: 14px;}
.gallery-controls { display: flex; gap: 8px; align-items: center; }
.btn-active-mode { background: #3b82f6 !important; color: white !important; }
.btn-danger-action { background: #ef4444; color: white; padding: 8px 12px; border-radius: 8px; border: none; cursor: pointer; font-weight: bold; }
.cat-block { margin-bottom: 25px; }
.cat-title { border-bottom: 2px solid #f472b6; padding-bottom: 5px; color: #db2777; font-size: 16px; margin-bottom: 12px;}
.tags-container { display: flex; flex-wrap: wrap; gap: 10px; }
.clothes-tag { cursor: pointer; display: flex; align-items: center; gap: 6px; background: #fdf2f8; border: 1px solid #fbcfe8; padding: 6px 12px; border-radius: 20px; font-size: 13px; transition: all 0.2s;}
.clothes-tag.is-selected { background: #dbeafe; border-color: #3b82f6; }
.tag-remove { background: none; border: none; color: #9ca3af; font-size: 16px; cursor: pointer; }
.tag-remove:hover { color: #ef4444; }
.empty-tip { width: 100%; text-align: center; color: #9ca3af; padding: 30px 0; font-style: italic;}
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
</style>