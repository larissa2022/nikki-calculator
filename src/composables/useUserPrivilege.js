// 1. 匿名名称渲染器
export const getDisplayUsername = (user) => {
  if (user?.username) return user.username;
  // 如果没有名字，截取用户 UUID 的前 4 位，转大写，拼成匿名
  const shortId = user?.id ? user.id.substring(0, 4).toUpperCase() : '0000';
  return `匿名搭配师_${shortId}`;
}

// 2. 核心等级与特权计算器
export const getUserRankAndPrivilege = (totalPoints) => {
  // 默认初始状态 (不到 500 分，无特权)
  let rank = { level: 0, title: '初级搭配师', pointMultiplier: 1.0, voteWeight: 1, adFree: false };

  if (totalPoints >= 10000) {
    rank = { level: 4, title: '奇迹编年史官', pointMultiplier: 1.0, voteWeight: 1, adFree: false };
  } else if (totalPoints >= 5000) {
    rank = { level: 3, title: '图鉴守护者', pointMultiplier: 1.0, voteWeight: 1, adFree: false };
  } else if (totalPoints >= 2000) {
    rank = { level: 2, title: '资深收集者', pointMultiplier: 1.0, voteWeight: 1, adFree: false };
  } else if (totalPoints >= 500) {
    rank = { level: 1, title: '见习搭配师', pointMultiplier: 1.0, voteWeight: 1, adFree: false };
  }

  return rank;
}

// 3. 判断是否为当月活跃用户
export const isActiveUser = (monthlyActionCount) => {
  return monthlyActionCount >= 5;
}
