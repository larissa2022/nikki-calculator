import test from 'node:test'
import assert from 'node:assert/strict'
import {
  fetchHomepageThanks,
  normalizeHomepageThanksRow
} from '../src/api/homepageThanksService.js'

const createClient = ({ data = [], error = null } = {}) => ({
  from(table) {
    assert.equal(table, 'homepage_monthly_thanks')
    return {
      select(columns) {
        assert.equal(columns, 'month_start, display_order, display_name')
        return {
          order(column, options) {
            assert.equal(column, 'display_order')
            assert.deepEqual(options, { ascending: true })
            return Promise.resolve({ data, error })
          }
        }
      }
    }
  }
})

test('首页鸣谢行只接受完整月份、1 至 10 顺序和非空名称', () => {
  assert.deepEqual(normalizeHomepageThanksRow({
    month_start: '2026-07-01',
    display_order: '2',
    display_name: ' 活跃玩家 '
  }), {
    monthStart: '2026-07-01',
    displayOrder: 2,
    displayName: '活跃玩家'
  })

  assert.equal(normalizeHomepageThanksRow({ month_start: '2026-07-02', display_order: 1, display_name: '甲' }), null)
  assert.equal(normalizeHomepageThanksRow({ month_start: '2026-07-01', display_order: 11, display_name: '甲' }), null)
  assert.equal(normalizeHomepageThanksRow({ month_start: '2026-07-01', display_order: 1, display_name: '' }), null)
})

test('首页鸣谢查询过滤异常行、其他月份并限制十人', async () => {
  const data = Array.from({ length: 12 }, (_, index) => ({
    month_start: index === 11 ? '2026-06-01' : '2026-07-01',
    display_order: index + 1,
    display_name: `玩家 ${index + 1}`
  }))

  const rows = await fetchHomepageThanks(createClient({ data }))

  assert.equal(rows.length, 10)
  assert.equal(rows[0].displayName, '玩家 1')
  assert.equal(rows[9].displayName, '玩家 10')
})

test('首页鸣谢查询透传数据库错误', async () => {
  const queryError = new Error('读取失败')
  await assert.rejects(
    fetchHomepageThanks(createClient({ error: queryError })),
    queryError
  )
})
