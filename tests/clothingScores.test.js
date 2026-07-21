import assert from 'node:assert/strict'
import test from 'node:test'

import { buildClothingScoresFromForm } from '../src/utils/clothingScores.js'

test('提交与审核共用十属性标准分值结构', () => {
  const scores = buildClothingScoresFromForm('连衣裙', {
    pair1: 'simple',
    grade1: '完美',
    pair2: 'active',
    grade2: '完美',
    pair3: 'cute',
    grade3: '完美',
    pair4: 'pure',
    grade4: '完美',
    pair5: 'cool',
    grade5: '完美'
  })

  assert.deepEqual(scores, {
    simple: 4305,
    gorgeous: 0,
    cute: 4305,
    mature: 0,
    active: 4305,
    elegant: 0,
    pure: 4305,
    sexy: 0,
    cool: 4305,
    warm: 0
  })
})
