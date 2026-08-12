<script setup>
const props = defineProps({
  benefits: { type: Object, required: true }
})

const sourceLabels = {
  clothing_contribution: '有效入库或补全',
  re_review_candidate: '重审修正通过',
  jury_vote: '首次有效投票',
  correction_request: '报错被采纳',
  level_bonus: '等级额外奖励',
  reversal: '积分扣回'
}

const outcomeLabels = {
  approved: '通过',
  returned: '退回重审',
  rejected: '管理员终审驳回',
  voting: '投票中'
}

const formatDate = value => {
  if (!value) return '时间未知'
  const date = new Date(value)
  return Number.isNaN(date.getTime())
    ? '时间未知'
    : new Intl.DateTimeFormat('zh-CN', { dateStyle: 'medium', timeStyle: 'short' }).format(date)
}

const formatMonth = value => String(value || '').slice(0, 7) || '未知月份'
</script>

<template>
  <section class="benefits-panel" aria-labelledby="level-benefits-title">
    <header>
      <div>
        <p>等级功能权益</p>
        <h4 id="level-benefits-title">当前累计 Lv{{ benefits.level }}</h4>
      </div>
      <span>{{ benefits.monthlyLv4Experience
        ? '累计等级不变；三项体验以资格有效期为准'
        : '权益以积分事件和投票发生前的等级为准' }}</span>
    </header>

    <div v-if="benefits.monthlyLv4Experience" class="experience-banner" role="status">
      <div>
        <strong>
          {{ benefits.monthlyLv4Experience.temporarilyApplied
            ? '上月并列第一，Lv4 三项体验生效中'
            : '上月并列第一，体验资格已记录' }}
        </strong>
        <span>
          依据 {{ formatMonth(benefits.monthlyLv4Experience.sourceMonth) }} 冻结榜，
          {{ formatDate(benefits.monthlyLv4Experience.scheduledEndAt) }} 自动回收
        </span>
      </div>
      <small>
        {{ benefits.monthlyLv4Experience.temporarilyApplied
          ? '仅含 +5 奖励、3 票票权和 Lv4 治理统计；累计等级与管理员资格不变'
          : '当前累计 Lv4 不受体验资格到期影响；管理员资格仍独立计算' }}
      </small>
    </div>

    <div class="benefit-grid">
      <article><small>有效业务奖励</small><strong>额外 +{{ benefits.bonusPerEvent }} 分</strong></article>
      <article><small>陪审票权</small><strong>{{ benefits.voteWeight }} 票</strong></article>
      <article><small>复核意见</small><strong>{{ benefits.canSubmitReviewNote ? '可以提交' : 'Lv2 解锁' }}</strong></article>
      <article><small>月度管理员候选</small><strong>{{ benefits.adminCandidateEligible ? '具备等级资格' : 'Lv2 解锁' }}</strong></article>
    </div>

    <details v-if="benefits.pointsEntries" open>
      <summary>本人积分明细（最近 {{ benefits.pointsEntries.length }} 条）</summary>
      <p v-if="benefits.pointsEntries.length === 0" class="empty">暂无积分流水。</p>
      <ul v-else class="activity-list">
        <li v-for="(entry, index) in benefits.pointsEntries" :key="`${entry.occurred_at}-${index}`">
          <span>{{ sourceLabels[entry.source_type] || '积分事件' }}</span>
          <time>{{ formatDate(entry.occurred_at) }}</time>
          <strong :class="{ negative: Number(entry.delta) < 0 }">{{ Number(entry.delta) > 0 ? '+' : '' }}{{ entry.delta }}</strong>
        </li>
      </ul>
    </details>
    <p v-else class="locked">Lv1 解锁本人积分流水。</p>

    <details v-if="benefits.contributions" :open="benefits.level === 2">
      <summary>本人贡献记录（最近 {{ benefits.contributions.length }} 条）</summary>
      <p v-if="benefits.contributions.length === 0" class="empty">暂无有效贡献记录。</p>
      <ul v-else class="activity-list">
        <li v-for="(entry, index) in benefits.contributions" :key="`${entry.contributed_at}-${index}`">
          <span>{{ entry.clothes_name }} · {{ entry.category || '未分类' }}</span>
          <time>{{ formatDate(entry.contributed_at) }}</time>
          <strong>#{{ entry.contribution_rank || '-' }}</strong>
        </li>
      </ul>
    </details>

    <details v-if="benefits.votes">
      <summary>本人陪审记录（最近 {{ benefits.votes.length }} 条）</summary>
      <p v-if="benefits.votes.length === 0" class="empty">暂无陪审记录。</p>
      <ul v-else class="activity-list">
        <li v-for="(entry, index) in benefits.votes" :key="`${entry.created_at}-${index}`">
          <span>{{ entry.clothes_name }} · {{ entry.vote === 'approve' ? '赞同' : '反对' }}</span>
          <time>{{ formatDate(entry.created_at) }}</time>
          <strong>{{ entry.vote_weight }} 票</strong>
        </li>
      </ul>
    </details>

    <details v-if="benefits.communityStats">
      <summary>{{ benefits.level >= 3 ? '最近 12 个月' : '本月' }}匿名社区审核统计</summary>
      <p v-if="benefits.communityStats.length === 0" class="empty">当前周期暂无已结案审核。</p>
      <ul v-else class="stats-list">
        <li v-for="(item, index) in benefits.communityStats" :key="`${item.month_start}-${item.reason}-${item.outcome}-${index}`">
          <span>{{ formatMonth(item.month_start) }} · {{ item.reason }}</span>
          <strong>{{ outcomeLabels[item.outcome] || item.outcome }} {{ item.item_count }} 项</strong>
        </li>
      </ul>
    </details>

    <details v-if="benefits.governanceStats">
      <summary>匿名管理员治理统计</summary>
      <div class="governance-summary">
        <strong>当前可处理低风险积压：{{ benefits.governanceStats.eligible_backlog_count || 0 }} 项</strong>
        <span>管理员任期 {{ benefits.governanceStats.terms?.length || 0 }} 组统计</span>
        <span>低风险决定 {{ benefits.governanceStats.decisions?.length || 0 }} 组统计</span>
      </div>
    </details>
  </section>
</template>

<style scoped>
.benefits-panel { margin-top: 22px; padding: 18px; border: 1px solid #dbeafe; border-radius: 18px; background: linear-gradient(135deg, #eff6ff, #faf5ff); }
header { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; }
header p { margin: 0 0 3px; color: #4f46e5; font-size: 10px; font-weight: 900; letter-spacing: .08em; }
header h4 { margin: 0; color: #1e293b; font-size: 17px; font-weight: 900; }
header > span { color: #64748b; font-size: 10px; font-weight: 700; text-align: right; }
.experience-banner { display: flex; align-items: center; justify-content: space-between; gap: 14px; margin-top: 14px; padding: 12px 14px; border: 1px solid #c4b5fd; border-radius: 14px; background: linear-gradient(120deg, rgba(237,233,254,.95), rgba(254,249,195,.9)); }
.experience-banner div { display: grid; gap: 3px; }
.experience-banner strong { color: #5b21b6; font-size: 12px; font-weight: 900; }
.experience-banner span { color: #6d28d9; font-size: 10px; font-weight: 700; }
.experience-banner small { max-width: 290px; color: #64748b; font-size: 9px; font-weight: 800; text-align: right; }
.benefit-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px; margin-top: 14px; }
.benefit-grid article { padding: 11px; border: 1px solid rgba(199, 210, 254, .8); border-radius: 12px; background: rgba(255,255,255,.84); }
.benefit-grid small, .benefit-grid strong { display: block; }
.benefit-grid small { color: #64748b; font-size: 9px; font-weight: 800; }
.benefit-grid strong { margin-top: 4px; color: #4338ca; font-size: 12px; font-weight: 900; }
details { margin-top: 10px; padding: 10px 12px; border: 1px solid #e2e8f0; border-radius: 12px; background: rgba(255,255,255,.82); }
summary { color: #334155; font-size: 11px; font-weight: 900; cursor: pointer; }
.activity-list, .stats-list { display: grid; gap: 6px; margin: 10px 0 0; padding: 0; list-style: none; }
.activity-list li, .stats-list li { display: grid; grid-template-columns: minmax(0,1fr) auto auto; align-items: center; gap: 8px; padding: 7px 9px; border-radius: 8px; background: #f8fafc; color: #475569; font-size: 10px; }
.activity-list time { color: #94a3b8; }
.activity-list strong, .stats-list strong { color: #4f46e5; }
.activity-list strong.negative { color: #e11d48; }
.stats-list li { grid-template-columns: minmax(0,1fr) auto; }
.empty, .locked { margin: 9px 0 0; color: #94a3b8; font-size: 10px; font-weight: 700; }
.locked { padding: 10px 12px; border: 1px dashed #cbd5e1; border-radius: 11px; }
.governance-summary { display: flex; flex-wrap: wrap; gap: 8px 14px; margin-top: 10px; color: #64748b; font-size: 10px; }
.governance-summary strong { color: #4338ca; }
@media (max-width: 760px) { .benefit-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } header, .experience-banner { align-items: flex-start; flex-direction: column; } header > span, .experience-banner small { text-align: left; } }
@media (max-width: 480px) { .activity-list li { grid-template-columns: minmax(0,1fr) auto; } .activity-list time { grid-column: 1 / -1; } }
</style>
