<script setup>
import { GRADE_OPTIONS } from '../composables/useScoreEngine'

defineProps({
  form: { type: Object, required: true }
})
</script>

<template>
  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 md:gap-3">
    <div v-for="i in 5" :key="i" class="flex items-center bg-white rounded-xl border-2 border-pink-100 overflow-hidden shadow-sm h-11">
      
      <select v-model="form['pair'+i]" class="w-1/2 bg-transparent text-center text-sm font-black text-purple-600 focus:outline-none cursor-pointer py-2">
        <option v-if="i==1" value="simple">简约</option><option v-if="i==1" value="gorgeous">华丽</option>
        <option v-if="i==2" value="active">活泼</option><option v-if="i==2" value="elegant">优雅</option>
        <option v-if="i==3" value="cute">可爱</option><option v-if="i==3" value="mature">成熟</option>
        <option v-if="i==4" value="pure">清纯</option><option v-if="i==4" value="sexy">性感</option>
        <option v-if="i==5" value="cool">清凉</option><option v-if="i==5" value="warm">保暖</option>
      </select>
      
      <div class="w-[2px] h-5 bg-pink-100 shrink-0"></div>
      
      <select v-model="form['grade'+i]" class="w-1/2 bg-pink-50/30 text-center text-sm font-black text-pink-500 focus:outline-none cursor-pointer h-full py-2">
        <option v-for="g in GRADE_OPTIONS" :key="g">{{g}}</option>
      </select>
      
    </div>
  </div>
</template>