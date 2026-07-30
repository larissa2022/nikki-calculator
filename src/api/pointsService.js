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
      .select('leaderboard_rank, display_name, points, is_current_user')
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
