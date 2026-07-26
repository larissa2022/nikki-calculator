import assert from 'node:assert/strict'
import test from 'node:test'

import { restorePendingSuitState } from '../src/utils/pendingSuitState.js'

test('审核表单还原已有套装状态', () => {
  assert.deepEqual(restorePendingSuitState({ suit_id: 'suit-1', temp_suit_name: null }), {
    suitId: 'suit-1',
    status: 'existing',
    searchText: ''
  })
})

test('审核表单还原临时套装名称和状态', () => {
  assert.deepEqual(restorePendingSuitState({ suit_id: null, temp_suit_name: '  星夜套装  ' }), {
    suitId: '',
    status: 'new',
    searchText: '星夜套装'
  })
})

test('审核表单将空套装事实还原为纯散件', () => {
  assert.deepEqual(restorePendingSuitState({ suit_id: null, temp_suit_name: null }), {
    suitId: '',
    status: 'none',
    searchText: ''
  })
})

test('审核表单将待补套装事实还原为所属套装待确认', () => {
  assert.deepEqual(
    restorePendingSuitState({
      suit_id: null,
      temp_suit_name: null,
      needs_suit_review: true
    }),
    {
      suitId: '',
      status: 'pending_review',
      searchText: ''
    }
  )
})
