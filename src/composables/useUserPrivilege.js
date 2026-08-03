// 1. 匿名名称渲染器
export const getDisplayUsername = (user) => {
  if (user?.username) return user.username;
  // 如果没有名字，截取用户 UUID 的前 4 位，转大写，拼成匿名
  const shortId = user?.id ? user.id.substring(0, 4).toUpperCase() : '0000';
  return `匿名搭配师_${shortId}`;
}

export const USER_LEVELS = Object.freeze([
  { level: 0, title: '初级搭配师', threshold: 0, badgeName: '尚未解锁等级徽章', badgeIcon: '✨' },
  { level: 1, title: '见习搭配师', threshold: 500, badgeName: '铜色新星徽章', badgeIcon: '✦' },
  { level: 2, title: '资深收集者', threshold: 2000, badgeName: '银色放大镜徽章', badgeIcon: '🔍' },
  { level: 3, title: '图鉴守护者', threshold: 5000, badgeName: '金色流光盾牌徽章', badgeIcon: '🛡️' },
  { level: 4, title: '奇迹编年史官', threshold: 10000, badgeName: '至尊皇冠徽章', badgeIcon: '👑' }
].map(level => Object.freeze(level)));

const normalizeTotalPoints = (totalPoints) => {
  const points = Number(totalPoints)
  return Number.isFinite(points) ? Math.max(0, Math.trunc(points)) : 0
}

// 2. 核心等级、展示进度与特权计算器
export const getUserRankAndPrivilege = (totalPoints) => {
  const points = normalizeTotalPoints(totalPoints)
  const currentIndex = USER_LEVELS.reduce(
    (resolvedIndex, level, index) => (points >= level.threshold ? index : resolvedIndex),
    0
  )
  const currentLevel = USER_LEVELS[Math.max(0, currentIndex)]
  const nextLevel = USER_LEVELS[currentIndex + 1] || null
  const levelSpan = nextLevel ? nextLevel.threshold - currentLevel.threshold : 0
  const levelProgress = nextLevel ? points - currentLevel.threshold : 0

  return {
    ...currentLevel,
    totalPoints: points,
    pointMultiplier: 1.0,
    voteWeight: 1,
    adFree: false,
    nextLevel: nextLevel?.level ?? null,
    nextTitle: nextLevel?.title ?? null,
    nextThreshold: nextLevel?.threshold ?? null,
    pointsToNext: nextLevel ? Math.max(0, nextLevel.threshold - points) : 0,
    progressPercent: nextLevel
      ? Math.min(100, Math.max(0, Math.round((levelProgress / levelSpan) * 100)))
      : 100,
    isMaxLevel: nextLevel === null
  }
}

// 3. 判断是否为当月活跃用户
export const isActiveUser = (monthlyActionCount) => {
  return monthlyActionCount >= 5;
}
