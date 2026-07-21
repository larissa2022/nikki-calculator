import { calculateItemScores } from '../composables/useScoreEngine.js'
import { ATTRIBUTE_PAIRS } from './gameConstants.js'

export const buildClothingScoresFromForm = (category, form) => calculateItemScores(
  category,
  ATTRIBUTE_PAIRS.map(pair => ({
    attr: form?.[pair.key],
    grade: form?.[pair.gradeKey]
  }))
)
