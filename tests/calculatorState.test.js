import assert from 'node:assert/strict'
import test from 'node:test'

import {
  CALCULATOR_STATE,
  resolveCalculatorState,
  selectCalculatorClothes
} from '../src/utils/calculatorState.js'

const wardrobe = [
  { id: 'dress-1', name: '连衣裙' },
  { id: 2, name: '外套' }
]

test('登录状态未确认时不产生搭配结果', () => {
  assert.equal(resolveCalculatorState(), CALCULATOR_STATE.AUTH_LOADING)
  assert.deepEqual(selectCalculatorClothes({ wardrobe, calculatorState: CALCULATOR_STATE.AUTH_LOADING }), [])
})

test('登录用户在衣柜读取中、失败或为空时不使用全图鉴', () => {
  for (const state of [
    resolveCalculatorState({ isAuthInitialized: true, isLoggedIn: true, wardrobeStatus: 'loading' }),
    resolveCalculatorState({ isAuthInitialized: true, isLoggedIn: true, wardrobeStatus: 'error' }),
    resolveCalculatorState({ isAuthInitialized: true, isLoggedIn: true, wardrobeStatus: 'ready', ownedCount: 0 })
  ]) {
    assert.notEqual(state, CALCULATOR_STATE.READY)
    assert.deepEqual(selectCalculatorClothes({
      wardrobe,
      ownedIds: [],
      isLoggedIn: true,
      calculatorState: state
    }), [])
  }
})

test('登录用户只使用本人衣柜内的服装', () => {
  const state = resolveCalculatorState({
    isAuthInitialized: true,
    isLoggedIn: true,
    wardrobeStatus: 'ready',
    ownedCount: 1
  })

  assert.equal(state, CALCULATOR_STATE.READY)
  assert.deepEqual(selectCalculatorClothes({
    wardrobe,
    ownedIds: ['2'],
    isLoggedIn: true,
    calculatorState: state
  }), [wardrobe[1]])
})

test('匿名用户保持使用全图鉴试算的既有口径', () => {
  const state = resolveCalculatorState({ isAuthInitialized: true, isLoggedIn: false })
  assert.equal(state, CALCULATOR_STATE.READY)
  assert.deepEqual(selectCalculatorClothes({
    wardrobe,
    isLoggedIn: false,
    calculatorState: state
  }), wardrobe)
})
