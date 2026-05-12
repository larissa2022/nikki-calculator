// src/composables/useAudit.js
import { ref, reactive, computed } from 'vue'
import { adminService } from '../api/adminService'
import { suitService } from '../api/suitService'

export function useAudit() {
    // 1. 核心状态
    const currentUserRole = ref('user')
    const currentUserId = ref(null)
    const allUsersList = ref([])
    const pendingList = ref([])
    const pendingSuitsList = ref([])
    const suitList = ref([])
    const isPendingLoading = ref(false)
    const isSubmitting = ref(false)

    // 待提交的新图鉴表单数据
    const newClothes = reactive({
        pendingIds: [], suit_id: '', game_id: '', name: '', category: '发型', stars: 5, tags: '',
        pair1: 'simple', grade1: '完美', pair2: 'cute', grade2: '完美', pair3: 'active', grade3: '完美', pair4: 'pure', grade4: '完美', pair5: 'cool', grade5: '完美'
    })

    // 2. 官方分值矩阵 (内部常量)
    const baseScoreMatrix = {
        '发型': { '完美+': 1324.5, '完美': 1089, '优秀': 837, '不错': 682.5, '一般': 517.5, '失败': 0 },
        '连衣裙': { '完美+': 5269.5, '完美': 4305, '优秀': 3366, '不错': 2749.5, '一般': 2100, '失败': 0 },
        '外套': { '完美+': 525, '完美': 423, '优秀': 331.5, '不错': 270, '一般': 213, '失败': 0 },
        '上装': { '完美+': 2619, '完美': 2140.5, '优秀': 1678.5, '不错': 1369.5, '一般': 1041, '失败': 0 },
        '下装': { '完美+': 2632.5, '完美': 2137.5, '优秀': 1678.5, '不错': 1357.5, '一般': 1041, '失败': 0 },
        '袜子': { '完美+': 789, '完美': 648, '优秀': 502.5, '不错': 403.5, '一般': 305, '失败': 0 },
        '鞋子': { '完美+': 1050, '完美': 855, '优秀': 667.5, '不错': 541.5, '一般': 423, '失败': 0 },
        '饰品': { '完美+': 526.5, '完美': 424.5, '优秀': 330, '不错': 271.5, '一般': 213, '失败': 0 },
        '妆容': { '完美+': 267, '完美': 213, '优秀': 168, '不错': 125, '一般': 85, '失败': 0 },
        '萤光之灵': { '完美+': 517.5, '完美': 421.5, '优秀': 325.5, '不错': 264, '一般': 200, '失败': 0 }
    }

    const getBroadCat = (cat) => {
        if (!cat) return '饰品'
        if (cat.includes('袜子')) return '袜子'
        if (cat.includes('饰品')) return '饰品'
        if (cat.includes('上')) return '上装'
        if (cat.includes('下')) return '下装'
        return cat
    }

    const getMostFrequent = (arr) => {
        if (!arr.length) return null
        const counts = {}
        arr.forEach(v => counts[v] = (counts[v] || 0) + 1)
        return Object.keys(counts).reduce((a, b) => counts[a] >= counts[b] ? a : b)
    }

    // 3. 数据拉取方法
    const fetchAllData = async () => {
        isPendingLoading.value = true
        try {
            const { userId, role } = await adminService.getCurrentUserRole()
            currentUserId.value = userId
            currentUserRole.value = role

            // 🌟 修复：加上 || []，防止从 API 服务层传过来的对象结构缺失导致 undefined
            const { pendingClothes, pendingSuits, countsMap } = await adminService.getPendingData()
            pendingList.value = pendingClothes || []
            pendingSuitsList.value = pendingSuits || []


            if (role === 'super_admin') {
                allUsersList.value = await adminService.getAllUsers(countsMap)
            }
        } finally {
            isPendingLoading.value = false
        }
    }

    const fetchSuits = async () => {
        try { suitList.value = await suitService.getAllSuits() } catch (err) { console.error(err) }
    }

    // 4. 智能聚类引擎
    // 🌟 修复：加入严格的数组拦截屏障
    const clusteredPendingList = computed(() => {
        const groups = {}
        if (!pendingList.value || !Array.isArray(pendingList.value)) return [] // 👈 增加这行绝对防御

        pendingList.value.forEach(item => {
            const key = (item.game_id && item.game_id !== 'N') ? `${item.category}_${item.game_id}` : `NAME_${item.name}`
            if (!groups[key]) groups[key] = { key, items: [] }
            groups[key].items.push(item)
        })
        return Object.values(groups)
    })

    // 5. 仲裁处理逻辑
    const processClusteredItem = (group) => {
        const items = group.items
        const userMap = Object.fromEntries(allUsersList.value.map(u => [u.id, u.contribCount]))
        const bestItem = items.reduce((prev, curr) => (userMap[curr.submitted_by] || 0) > (userMap[prev.submitted_by] || 0) ? curr : prev)

        newClothes.pendingIds = items.map(i => i.id)
        newClothes.name = bestItem.name
        newClothes.game_id = bestItem.game_id || ''
        newClothes.category = bestItem.category
        newClothes.stars = Number(getMostFrequent(items.map(i => i.stars)))
        newClothes.suit_id = bestItem.suit_id || ''

        const allTags = items.flatMap(i => i.tags ? (Array.isArray(i.tags) ? i.tags : i.tags.split(/[,，\s]+/)) : []).map(t => t.trim())
        newClothes.tags = [...new Set(allTags)].filter(t => t).join(', ')

        if (bestItem.scores) {
            const matrix = baseScoreMatrix[getBroadCat(newClothes.category)] || baseScoreMatrix['饰品']
            const getGradeFromScore = (val) => {
                let closest = '一般'; let minDiff = Infinity
                for (const [g, s] of Object.entries(matrix)) {
                    const diff = Math.abs((val || 0) - s)
                    if (diff < minDiff) { minDiff = diff; closest = g }
                }
                return closest
            }

            const attrPairs = [
                { key: 'pair1', gKey: 'grade1', p1: 'simple', p2: 'gorgeous' },
                { key: 'pair2', gKey: 'grade2', p1: 'cute', p2: 'mature' },
                { key: 'pair3', gKey: 'grade3', p1: 'active', p2: 'elegant' },
                { key: 'pair4', gKey: 'grade4', p1: 'pure', p2: 'sexy' },
                { key: 'pair5', gKey: 'grade5', p1: 'cool', p2: 'warm' }
            ]

            attrPairs.forEach(ap => {
                const votes = items.map(i => {
                    const s = i.scores || {}
                    const p = (s[ap.p1] || 0) > (s[ap.p2] || 0) ? ap.p1 : ap.p2
                    const g = getGradeFromScore(Math.max(s[ap.p1] || 0, s[ap.p2] || 0))
                    return { p, g }
                })
                newClothes[ap.key] = getMostFrequent(votes.map(v => v.p))
                newClothes[ap.gKey] = getMostFrequent(votes.map(v => v.g))
            })
        }
        // 返回匹配到的套装 ID，供 UI 层处理显示逻辑
        return newClothes.suit_id
    }

    // 6. 最终执行入库
    const executeSubmit = async () => {
        if (!newClothes.name) throw new Error('名字是必填项哦！')
        isSubmitting.value = true
        try {
            const matrix = baseScoreMatrix[getBroadCat(newClothes.category)] || baseScoreMatrix['饰品']
            const calculatedScores = {}
            // 🌟 修复：将数组单独提取为一个变量，彻底避开 JS 引擎的换行解析陷阱
            const pairs = [['pair1', 'grade1'], ['pair2', 'grade2'], ['pair3', 'grade3'], ['pair4', 'grade4'], ['pair5', 'grade5']]
            pairs.forEach(([p, g]) => {
                calculatedScores[newClothes[p]] = matrix[newClothes[g]] || 0
            })

            const payload = {
                id: `custom_${Date.now()}`, game_id: newClothes.game_id || 'N', name: newClothes.name,
                category: newClothes.category, stars: Number(newClothes.stars), scores: calculatedScores,
                suit_id: newClothes.suit_id || null,
                // 🌟 修复：确保 tags 哪怕被意外清空也是个安全字符串，再进行拆分
                tags: (newClothes.tags || '').split(/[,，\s]+/).filter(t => t)
            }

            await adminService.submitArbitration(payload, newClothes.pendingIds)

            const successName = newClothes.name
            Object.assign(newClothes, { name: '', game_id: '', tags: '', suit_id: '', pendingIds: [] })
            await fetchAllData()
            return successName
        } finally {
            isSubmitting.value = false
        }
    }

    const rejectPendingItem = async (id) => {
        await adminService.rejectPending('pending_clothes', id)
        await fetchAllData()
    }

    // 🌟 补充：新增套装专用的批准与驳回方法
    const approvePendingSuit = async (id, name) => {
        await adminService.approveSuit(id, name)
        await fetchAllData()
    }
    const rejectPendingSuit = async (id) => {
        await adminService.rejectPending('pending_suits', id)
        await fetchAllData()
    }

    // 对外暴露的属性和方法
    return {
        currentUserRole, currentUserId, allUsersList,
        pendingSuitsList, suitList, isPendingLoading, isSubmitting, newClothes,
        fetchAllData, fetchSuits, clusteredPendingList,
        processClusteredItem, executeSubmit, rejectPendingItem,
        approvePendingSuit, rejectPendingSuit // 👈 🌟 记得在这里把它们暴露出去！
    }
}