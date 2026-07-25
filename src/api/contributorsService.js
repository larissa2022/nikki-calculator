const DEFAULT_PAGE_SIZE = 1000

const normalizeContributor = (row) => {
  const rank = Number(row?.contribution_rank)
  const clothesId = row?.clothes_id ? String(row.clothes_id) : ''

  if (!clothesId || !Number.isInteger(rank) || rank < 1 || rank > 3) return null

  return {
    clothesId,
    rank,
    displayName: String(row?.display_name || '匿名贡献者'),
    contributedAt: row?.contributed_at || null
  }
}

export const fetchPublicClothingContributors = async (
  client,
  { pageSize = DEFAULT_PAGE_SIZE } = {}
) => {
  if (!client) throw new Error('缺少贡献者查询客户端')

  const rows = []
  let from = 0

  while (true) {
    const { data, error } = await client
      .from('clothing_contributors_public')
      .select('clothes_id, contribution_rank, display_name, contributed_at')
      .order('clothes_id', { ascending: true })
      .order('contribution_rank', { ascending: true })
      .range(from, from + pageSize - 1)

    if (error) throw error

    const page = data || []
    rows.push(...page)

    if (page.length < pageSize) break
    from += pageSize
  }

  return rows
}

export const buildContributorEntries = (rows, clothes) => {
  const clothesById = new Map(
    (clothes || [])
      .filter(item => item?.id)
      .map(item => [String(item.id), item])
  )
  const groups = new Map()

  for (const row of rows || []) {
    const contributor = normalizeContributor(row)
    if (!contributor) continue

    if (!groups.has(contributor.clothesId)) groups.set(contributor.clothesId, [])
    groups.get(contributor.clothesId).push(contributor)
  }

  return [...groups.entries()]
    .map(([clothesId, contributors]) => {
      const item = clothesById.get(clothesId)
      const stableContributors = contributors
        .sort((left, right) => (
          left.rank - right.rank
          || String(left.contributedAt || '').localeCompare(String(right.contributedAt || ''))
          || left.displayName.localeCompare(right.displayName, 'zh-CN')
        ))
        .filter((contributor, index, all) => (
          all.findIndex(candidate => candidate.rank === contributor.rank) === index
        ))
        .slice(0, 3)

      return {
        clothesId,
        name: item?.name || `未知服装（${clothesId}）`,
        gameId: item?.game_id || '',
        category: item?.category || '',
        contributors: stableContributors,
        latestContributionAt: stableContributors.reduce((latest, contributor) => (
          String(contributor.contributedAt || '') > latest
            ? String(contributor.contributedAt || '')
            : latest
        ), '')
      }
    })
    .sort((left, right) => (
      right.latestContributionAt.localeCompare(left.latestContributionAt)
      || left.name.localeCompare(right.name, 'zh-CN')
      || left.clothesId.localeCompare(right.clothesId)
    ))
}
