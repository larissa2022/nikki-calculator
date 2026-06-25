// src/utils/gameConstants.js

export const FULL_CATEGORIES = [
  '发型', '连衣裙', '外套', '上装', '下装', '袜子-袜套', '袜子-袜子', '鞋子', '妆容', '萤光之灵',
  '饰品-头饰-发饰', '饰品-头饰-头纱', '饰品-头饰-发卡', '饰品-头饰-耳朵', '饰品-耳饰', '饰品-颈饰-围巾', '饰品-颈饰-项链',
  '饰品-手饰-右', '饰品-手饰-左', '饰品-手饰-双', '饰品-手持-右', '饰品-手持-左', '饰品-手持-双', '饰品-腰饰',
  '饰品-特殊-面饰', '饰品-特殊-胸饰', '饰品-特殊-纹身', '饰品-特殊-翅膀', '饰品-特殊-尾巴', '饰品-特殊-前景', '饰品-特殊-后景', '饰品-特殊-顶饰', '饰品-特殊-地面', '饰品-皮肤'
]

// 🌟 将数十行的 v-if 判断转化为规整的数据结构，前端直接循环渲染即可
export const ATTRIBUTE_PAIRS = [
  { key: 'pair1', gradeKey: 'grade1', options: [{ value: 'simple', label: '简约' }, { value: 'gorgeous', label: '华丽' }] },
  { key: 'pair2', gradeKey: 'grade2', options: [{ value: 'active', label: '活泼' }, { value: 'elegant', label: '优雅' }] },
  { key: 'pair3', gradeKey: 'grade3', options: [{ value: 'cute', label: '可爱' }, { value: 'mature', label: '成熟' }] },
  { key: 'pair4', gradeKey: 'grade4', options: [{ value: 'pure', label: '清纯' }, { value: 'sexy', label: '性感' }] },
  { key: 'pair5', gradeKey: 'grade5', options: [{ value: 'cool', label: '清凉' }, { value: 'warm', label: '保暖' }] }
]

export const KNOWN_CLOTHING_TAGS = [
  '现代流行', '欧式古典', '中式古典', '中式现代', '波西米亚', '森女系列',
  '洛丽塔', '哥特风', '女仆装', '童话系', '未来系', '侠客联盟',
  '民国服饰', '民族风', '英伦', '学院系', '运动系', '居家服',
  '晚礼服', '婚纱', '旗袍', '军装', '工装风', '航海风',
  '乐队风', '舞者', '女神系', '大小姐', '兔女郎', '医务使者',
  '雨季装备', '冬装', '泳装', '沐浴', '围裙', '碎花',
  '防晒', '睡衣', '动物系', '潮酷风', '轻熟风', '异域风',
  '中性风',
  '简约+200', '简约+500', '简约+800', '简约+1200', '简约+1500',
  '华丽+200', '华丽+500', '华丽+800', '华丽+1200', '华丽+1500',
  '活泼+200', '活泼+500', '活泼+800', '活泼+1200', '活泼+1500',
  '优雅+200', '优雅+500', '优雅+800', '优雅+1200', '优雅+1500',
  '可爱+200', '可爱+500', '可爱+800', '可爱+1200', '可爱+1500',
  '成熟+200', '成熟+500', '成熟+800', '成熟+1200', '成熟+1500',
  '清纯+200', '清纯+500', '清纯+800', '清纯+1200', '清纯+1500',
  '性感+200', '性感+500', '性感+800', '性感+1200', '性感+1500',
  '清凉+200', '清凉+500', '清凉+800', '清凉+1200'
]

export const createClothesEntryFormState = (overrides = {}) => ({
  suit_id: '',
  game_id: '',
  name: '',
  category: '发型',
  stars: 5,
  tags: '',
  pair1: 'simple',
  grade1: '完美',
  pair2: 'active',
  grade2: '完美',
  pair3: 'cute',
  grade3: '完美',
  pair4: 'pure',
  grade4: '完美',
  pair5: 'cool',
  grade5: '完美',
  ...overrides
})

export const normalizeClothingTags = (rawTags) => {
  const values = Array.isArray(rawTags) ? rawTags : [rawTags]
  const knownTagsByLength = [...KNOWN_CLOTHING_TAGS].sort((a, b) => b.length - a.length)

  return [...new Set(
    values
      .flatMap(value => String(value || '').split(/[,，、;；]+/))
      .map(tag => tag.trim())
      .filter(Boolean)
      .flatMap(tag => {
        if (KNOWN_CLOTHING_TAGS.includes(tag)) return [tag]

        const matchedKnownTags = knownTagsByLength
          .map(knownTag => ({ tag: knownTag, index: tag.indexOf(knownTag) }))
          .filter(match => match.index >= 0)
          .sort((a, b) => a.index - b.index || b.tag.length - a.tag.length)
          .map(match => match.tag)
        return matchedKnownTags.length ? matchedKnownTags : [tag]
      })
  )].join(', ')
}
