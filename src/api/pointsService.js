const normalizeTotalPoints = (value) => {
  const points = Number(value ?? 0)
  return Number.isFinite(points) ? points : 0
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
