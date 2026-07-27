<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { supabase } from '../api/supabase'
import {
  castJuryVote,
  fetchJuryReviewQueue,
  rejectJuryCandidateAsAdmin,
  submitJuryCandidate
} from '../api/juryService'
import { suitService } from '../api/suitService'
import { getJuryStatusText, JURY_VOTE } from '../utils/juryRules'

const props = defineProps({
  isLoggedIn: Boolean,
  isSuperAdmin: Boolean
})

const items = ref([])
const suits = ref([])
const selectedSuitIds = ref({})
const adminReasons = ref({})
const isLoading = ref(false)
const loadError = ref('')
const activeActionKey = ref('')

const suitsById = computed(() => new Map(
  suits.value.map(suit => [String(suit.id), suit])
))

const loadQueue = async () => {
  if (!props.isLoggedIn) {
    items.value = []
    return
  }

  isLoading.value = true
  loadError.value = ''
  try {
    const [queue, suitRows] = await Promise.all([
      fetchJuryReviewQueue(supabase),
      suitService.getAllSuits()
    ])
    items.value = queue
    suits.value = suitRows
  } catch (error) {
    console.error('加载陪审团失败:', error)
    loadError.value = error?.message || '陪审团暂时无法加载'
  } finally {
    isLoading.value = false
  }
}

const candidateSuitName = (item) => {
  const suitId = String(item.candidatePayload?.suit_id || '')
  return suitsById.value.get(suitId)?.name || (suitId ? `套装 ${suitId}` : '尚未提交候选套装')
}

const runAction = async (key, action, successMessage) => {
  if (activeActionKey.value) return
  activeActionKey.value = key
  try {
    await action()
    alert(successMessage)
    await loadQueue()
  } catch (error) {
    alert(error?.message || '操作失败，请稍后重试。')
  } finally {
    activeActionKey.value = ''
  }
}

const handleSubmitCandidate = async (item) => {
  const suitId = selectedSuitIds.value[item.reReviewItemId]
  if (!suitId) return alert('请先选择一个明确的正式套装。')

  await runAction(
    `candidate:${item.reReviewItemId}`,
    () => submitJuryCandidate(supabase, item.reReviewItemId, suitId),
    '候选快照已冻结，陪审团可以开始投票。'
  )
}

const handleVote = async (item, vote) => {
  const label = vote === JURY_VOTE.APPROVE ? '赞同' : '驳回'
  if (!confirm(`确认对《${item.clothesName}》投“${label}”吗？投票后不能修改。`)) return

  await runAction(
    `vote:${item.candidateId}`,
    () => castJuryVote(supabase, item.candidateId, vote),
    '投票已记录。'
  )
}

const handleAdminReject = async (item) => {
  const reason = String(adminReasons.value[item.candidateId] || '').trim()
  if (!reason) return alert('永久驳回必须填写终审理由。')
  if (!confirm(`确认永久驳回《${item.clothesName}》当前候选吗？该动作与普通投票分开记录。`)) return

  await runAction(
    `admin:${item.candidateId}`,
    () => rejectJuryCandidateAsAdmin(supabase, item.candidateId, reason),
    '管理员终审已记录，该审核项已永久驳回。'
  )
}

watch(() => props.isLoggedIn, loadQueue)
onMounted(loadQueue)
</script>

<template>
  <div class="space-y-5">
    <section class="rounded-2xl border border-purple-100 bg-white p-5 shadow-sm">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 class="text-xl font-black text-slate-800">⚖️ 陪审团</h2>
          <p class="mt-1 text-xs font-bold leading-relaxed text-slate-500">
            每人一票。赞同票至少 5 且多于反对票时通过；反对票领先至少 3 时退回重审；其他情况继续投票。
          </p>
        </div>
        <button
          type="button"
          class="rounded-xl border border-purple-200 px-4 py-2 text-sm font-black text-purple-600 hover:bg-purple-50 disabled:cursor-wait disabled:opacity-50"
          :disabled="isLoading"
          @click="loadQueue"
        >
          {{ isLoading ? '刷新中…' : '刷新陪审团' }}
        </button>
      </div>
    </section>

    <section v-if="!isLoggedIn" class="rounded-2xl border border-dashed border-slate-200 bg-white p-8 text-center text-sm font-bold text-slate-400">
      登录后才能查看与你无关的重审项并参与陪审团。
    </section>

    <section v-else-if="loadError" class="rounded-2xl border border-rose-100 bg-rose-50 p-6 text-center text-sm font-bold text-rose-600">
      <p>{{ loadError }}</p>
      <button type="button" class="mt-3 underline" @click="loadQueue">重新加载</button>
    </section>

    <section v-else-if="isLoading" class="rounded-2xl border border-dashed border-purple-100 bg-white p-8 text-center text-sm font-bold text-purple-500">
      正在读取可参与的审核项…
    </section>

    <section v-else-if="items.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-white p-8 text-center text-sm font-bold text-slate-400">
      当前没有你可以参与的陪审团事项。
    </section>

    <template v-else>
    <article
      v-for="item in items"
      :key="item.reReviewItemId"
      class="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-lg font-black text-slate-800">{{ item.clothesName }}</h3>
            <span class="rounded-full bg-purple-50 px-2.5 py-1 text-[11px] font-black text-purple-600">
              {{ getJuryStatusText(item.itemStatus) }}
            </span>
          </div>
          <p class="mt-1 text-xs font-bold text-slate-400">
            {{ item.category || '未知分类' }} · 短编号 {{ item.gameId || '未知' }} · 所属套装待确认
          </p>
        </div>
        <div class="flex gap-2 text-xs font-black">
          <span class="rounded-lg bg-emerald-50 px-3 py-2 text-emerald-600">赞同 {{ item.approveCount }}</span>
          <span class="rounded-lg bg-rose-50 px-3 py-2 text-rose-600">反对 {{ item.rejectCount }}</span>
        </div>
      </div>

      <div v-if="item.canSubmitCandidate" class="mt-4 rounded-xl border border-amber-100 bg-amber-50 p-4">
        <p class="text-sm font-black text-amber-700">该事项已退回或尚无候选，请选择一个明确套装形成新的冻结快照。</p>
        <div class="mt-3 flex flex-col gap-2 sm:flex-row">
          <select
            v-model="selectedSuitIds[item.reReviewItemId]"
            class="min-w-0 flex-1 rounded-xl border border-amber-200 bg-white px-3 py-2 text-sm font-bold text-slate-700"
          >
            <option value="">选择正式套装</option>
            <option v-for="suit in suits" :key="suit.id" :value="suit.id">{{ suit.name }}</option>
          </select>
          <button
            type="button"
            class="rounded-xl bg-amber-500 px-4 py-2 text-sm font-black text-white disabled:opacity-50"
            :disabled="Boolean(activeActionKey)"
            @click="handleSubmitCandidate(item)"
          >
            提交并冻结候选
          </button>
        </div>
      </div>

      <div v-else-if="item.candidateId" class="mt-4 rounded-xl border border-slate-100 bg-slate-50 p-4">
        <div class="text-xs font-bold text-slate-400">当前冻结候选</div>
        <div class="mt-1 text-base font-black text-slate-700">《{{ candidateSuitName(item) }}》</div>
        <p class="mt-2 text-xs font-bold text-slate-500">候选内容在本轮投票期间不会变化；若被退回，旧票保留为历史，新候选重新计票。</p>

        <div v-if="item.myVote" class="mt-4 rounded-lg bg-white px-3 py-2 text-sm font-black text-purple-600">
          你已投：{{ item.myVote === JURY_VOTE.APPROVE ? '赞同' : '驳回' }}（一票定稿）
        </div>
        <div v-else-if="item.isCandidateAuthor" class="mt-4 rounded-lg bg-white px-3 py-2 text-sm font-black text-slate-500">
          这是你提交的候选快照，不能参与本轮投票。
        </div>
        <div v-else class="mt-4 grid grid-cols-2 gap-3">
          <button
            type="button"
            class="rounded-xl bg-emerald-500 px-4 py-3 text-sm font-black text-white disabled:opacity-50"
            :disabled="!item.canVote || Boolean(activeActionKey)"
            @click="handleVote(item, JURY_VOTE.APPROVE)"
          >
            赞同候选
          </button>
          <button
            type="button"
            class="rounded-xl bg-rose-500 px-4 py-3 text-sm font-black text-white disabled:opacity-50"
            :disabled="!item.canVote || Boolean(activeActionKey)"
            @click="handleVote(item, JURY_VOTE.REJECT)"
          >
            驳回并要求修正
          </button>
        </div>

        <div v-if="isSuperAdmin" class="mt-5 border-t border-slate-200 pt-4">
          <div class="text-xs font-black text-rose-600">管理员独立终审</div>
          <p class="mt-1 text-[11px] font-bold text-slate-500">永久驳回不会计入普通票；已经投过本候选的管理员不能终审。</p>
          <div class="mt-2 flex flex-col gap-2 sm:flex-row">
            <input
              v-model="adminReasons[item.candidateId]"
              type="text"
              maxlength="200"
              placeholder="填写永久驳回理由"
              class="min-w-0 flex-1 rounded-xl border border-rose-200 bg-white px-3 py-2 text-sm font-bold text-slate-700"
            />
            <button
              type="button"
              class="rounded-xl border border-rose-200 bg-white px-4 py-2 text-sm font-black text-rose-600 disabled:opacity-50"
              :disabled="Boolean(activeActionKey)"
              @click="handleAdminReject(item)"
            >
              永久驳回
            </button>
          </div>
        </div>
      </div>
    </article>
    </template>
  </div>
</template>
