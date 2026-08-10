const normalizeTotalPoints = (value) => {
  const points = Number(value ?? 0)
  return Number.isFinite(points) ? points : 0
}

const LEADERBOARD_TABLES = {
  total: 'points_leaderboard_total',
  current_month: 'points_leaderboard_current_month',
  last_month: 'points_leaderboard_last_month'
}

const DEFAULT_LEADERBOARD_PAGE_SIZE = 1000

const levelForPoints = points => {
  if (points >= 10000) return 4
  if (points >= 5000) return 3
  if (points >= 2000) return 2
  if (points >= 500) return 1
  return 0
}

export const normalizeLeaderboardRow = (row) => {
  const rank = Number(row?.leaderboard_rank)
  const points = Number(row?.points)
  const displayName = String(row?.display_name || '').trim()

  if (!Number.isInteger(rank) || rank < 1 || !Number.isFinite(points) || !displayName) {
    return null
  }

  return {
    rank,
    displayName,
    points,
    level: Number.isInteger(Number(row?.current_level))
      ? Math.min(4, Math.max(0, Number(row.current_level)))
      : levelForPoints(points),
    isCurrentUser: row?.is_current_user === true
  }
}

export const fetchCurrentUserPoints = async (client) => {
  if (!client) throw new Error('缺少积分查询客户端')

  const { data, error } = await client
    .from('user_points_summary')
    .select('total_points')
    .limit(1)

  if (error) throw error

  return normalizeTotalPoints(data?.[0]?.total_points)
}

export const normalizeLevelBenefits = (data = {}) => ({
  level: Math.min(4, Math.max(0, Number(data?.level) || 0)),
  totalPoints: normalizeTotalPoints(data?.total_points),
  bonusPerEvent: Math.max(0, Number(data?.bonus_per_event) || 0),
  voteWeight: Math.max(1, Number(data?.vote_weight) || 1),
  canSubmitReviewNote: data?.can_submit_review_note === true,
  adminCandidateEligible: data?.admin_candidate_eligible === true,
  pointsEntries: Array.isArray(data?.points_entries) ? data.points_entries : null,
  contributions: Array.isArray(data?.contributions) ? data.contributions : null,
  votes: Array.isArray(data?.votes) ? data.votes : null,
  communityStats: Array.isArray(data?.community_stats) ? data.community_stats : null,
  governanceStats: data?.governance_stats && typeof data.governance_stats === 'object'
    ? data.governance_stats
    : null
})

export const fetchMyLevelBenefits = async (client) => {
  if (!client) throw new Error('缺少等级权益查询客户端')
  const { data, error } = await client.rpc('get_my_level_benefits')
  if (error) throw error
  return normalizeLevelBenefits(data)
}

export const fetchPointsLeaderboard = async (
  client,
  period,
  { pageSize = DEFAULT_LEADERBOARD_PAGE_SIZE } = {}
) => {
  if (!client) throw new Error('缺少排行榜查询客户端')

  const table = LEADERBOARD_TABLES[period]
  if (!table) throw new Error('不支持的排行榜周期')

  const rows = []
  let from = 0

  while (true) {
    const { data, error } = await client
      .from(table)
      .select('leaderboard_rank, display_name, points, current_level, is_current_user')
      .order('leaderboard_rank', { ascending: true })
      .order('display_name', { ascending: true })
      .range(from, from + pageSize - 1)

    if (error) throw error

    const page = data || []
    rows.push(...page)

    if (page.length < pageSize) break
    from += pageSize
  }

  return rows
    .map(normalizeLeaderboardRow)
    .filter(Boolean)
}
