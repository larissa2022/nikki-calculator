export const CALCULATOR_STATE = Object.freeze({
  READY: 'ready',
  AUTH_LOADING: 'auth-loading',
  WARDROBE_LOADING: 'wardrobe-loading',
  WARDROBE_ERROR: 'wardrobe-error',
  WARDROBE_EMPTY: 'wardrobe-empty'
})

export const resolveCalculatorState = ({
  isAuthInitialized = false,
  isLoggedIn = false,
  wardrobeStatus = 'idle',
  ownedCount = 0
} = {}) => {
  if (!isAuthInitialized) return CALCULATOR_STATE.AUTH_LOADING
  if (!isLoggedIn) return CALCULATOR_STATE.READY
  if (wardrobeStatus === 'loading' || wardrobeStatus === 'idle') {
    return CALCULATOR_STATE.WARDROBE_LOADING
  }
  if (wardrobeStatus === 'error') return CALCULATOR_STATE.WARDROBE_ERROR
  if (ownedCount === 0) return CALCULATOR_STATE.WARDROBE_EMPTY
  return CALCULATOR_STATE.READY
}

export const selectCalculatorClothes = ({
  wardrobe = [],
  ownedIds = [],
  isLoggedIn = false,
  calculatorState = CALCULATOR_STATE.READY
} = {}) => {
  if (calculatorState !== CALCULATOR_STATE.READY) return []
  if (!isLoggedIn) return wardrobe

  const ownedSet = new Set(ownedIds.map(id => String(id)))
  return wardrobe.filter(item => ownedSet.has(String(item.id)))
}
