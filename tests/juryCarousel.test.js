import assert from 'node:assert/strict'
import test from 'node:test'

import { clampJuryCardIndex, getJurySwipeDirection } from '../src/utils/juryCarousel.js'

test('单卡陪审索引始终限制在当前队列范围内', () => {
  assert.equal(clampJuryCardIndex(-2, 3), 0)
  assert.equal(clampJuryCardIndex(1, 3), 1)
  assert.equal(clampJuryCardIndex(9, 3), 2)
  assert.equal(clampJuryCardIndex(2, 0), 0)
})

test('只有明显的横向手势才切换陪审卡片', () => {
  assert.equal(getJurySwipeDirection({ startX: 200, startY: 100, endX: 80, endY: 112 }), 'next')
  assert.equal(getJurySwipeDirection({ startX: 80, startY: 100, endX: 200, endY: 90 }), 'previous')
  assert.equal(getJurySwipeDirection({ startX: 100, startY: 100, endX: 120, endY: 220 }), '')
})
