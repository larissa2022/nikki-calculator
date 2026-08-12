const MONTH_PATTERN = /^\d{4}-\d{2}-01$/

export const normalizeHomepageThanksRow = (row) => {
  const monthStart = String(row?.month_start || '').trim()
  const displayOrder = Number(row?.display_order)
  const displayName = String(row?.display_name || '').trim()

  if (
    !MONTH_PATTERN.test(monthStart)
    || !Number.isInteger(displayOrder)
    || displayOrder < 1
    || displayOrder > 10
    || !displayName
  ) {
    return null
  }

  return { monthStart, displayOrder, displayName }
}

export const fetchHomepageThanks = async (client) => {
  if (!client) throw new Error('缺少首页鸣谢查询客户端')

  const { data, error } = await client
    .from('homepage_monthly_thanks')
    .select('month_start, display_order, display_name')
    .order('display_order', { ascending: true })

  if (error) throw error

  const rows = (data || [])
    .map(normalizeHomepageThanksRow)
    .filter(Boolean)

  const monthStart = rows[0]?.monthStart
  return rows
    .filter(row => row.monthStart === monthStart)
    .slice(0, 10)
}
