export const clampJuryCardIndex = (index, total) => {
  const safeTotal = Math.max(0, Number(total) || 0)
  if (safeTotal === 0) return 0
  return Math.min(Math.max(0, Number(index) || 0), safeTotal - 1)
}

export const getJurySwipeDirection = ({
  startX,
  startY,
  endX,
  endY,
  threshold = 50
}) => {
  const deltaX = Number(endX) - Number(startX)
  const deltaY = Number(endY) - Number(startY)
  if (Math.abs(deltaX) < threshold || Math.abs(deltaX) <= Math.abs(deltaY)) return ''
  return deltaX < 0 ? 'next' : 'previous'
}
