// src/composables/useAudit.js
import { ref, reactive, computed } from 'vue'
import { adminService } from '../api/adminService'
import { suitService } from '../api/suitService'
import { ATTRIBUTE_PAIRS, createClothesEntryFormState, normalizeClothingTags } from '../utils/gameConstants'
import { isAdminRole } from '../utils/roles'
// 🌟 引入全局数值大脑
import { SCORE_MATRIX, getBroadCategory } from './useScoreEngine'

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
    // 将 newClothes 替换为：
    const newClothes = reactive({
        pendingIds: [],
        ...createClothesEntryFormState()
    })
    // 2. 官方分值矩阵 (内部常量)
    

    const getMostFrequent = (arr) => {
        if (!arr.length) return null
        const counts = {}
        arr.forEach(v => counts[v] = (counts[v] || 0) + 1)
        return Object.keys(counts).reduce((a, b) => counts[a] >= counts[b] ? a : b)
    }

    // 3. 数据拉取方法 (🚀 极速且防崩溃版)
    const fetchAllData = async () => {
        isPendingLoading.value = true
        try {
            // 🌟 1. 让【查身份】和【查数据】同时起跑，但不互相绑定生死 (解耦并发)
            const authPromise = adminService.getCurrentUserRole()
            
            // 如果查数据报错了就内部消化，绝对不影响后面身份的显示
            const pendingPromise = adminService.getPendingData().catch(err => {
                console.error("获取待办数据失败，可能是网络或权限问题:", err)
                return { pendingClothes: [], pendingSuits: [], countsMap: {} }
            })

            // 🌟 2. 优先结算身份！只要数据库没动过，这里瞬间就能让你变成 super_admin
            const { userId, role } = await authPromise
            currentUserId.value = userId
            currentUserRole.value = role

            // 🌟 3. 结算待办数据
            const { pendingClothes, pendingSuits, countsMap } = await pendingPromise
            pendingList.value = pendingClothes || []
            pendingSuitsList.value = pendingSuits || []

            // 🌟 4. 只有确认为站长后，才去拉取人员名单（同样加上防崩溃保护）
            if (isAdminRole(role)) {
                allUsersList.value = await adminService.getAllUsers(countsMap).catch(err => {
                    console.error("获取全站用户名单失败:", err)
                    return []
                })
            }

        } catch (error) {
            console.error("🚨 致命错误：身份查验接口彻底崩溃！", error)
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
            if (!groups[key]) groups[key] = { key, name: item.name || '未命名散件', items: [] }
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
        newClothes.suit_status = bestItem.suit_id ? 'existing' : ''

        newClothes.tags = normalizeClothingTags(items.map(i => i.tags))

        if (bestItem.scores) {
            const matrix = SCORE_MATRIX[getBroadCategory(newClothes.category)] || SCORE_MATRIX['饰品']
            const getGradeFromScore = (val) => {
                let closest = '一般'; let minDiff = Infinity
                for (const [g, s] of Object.entries(matrix)) {
                    const diff = Math.abs((val || 0) - s)
                    if (diff < minDiff) { minDiff = diff; closest = g }
                }
                return closest
            }

            // 将 attrPairs 替换为：
            const attrPairs = [
                { key: 'pair1', gKey: 'grade1', p1: 'simple', p2: 'gorgeous' },
                // 🌟 active 和 cute 互换位置
                { key: 'pair2', gKey: 'grade2', p1: 'active', p2: 'elegant' },
                { key: 'pair3', gKey: 'grade3', p1: 'cute', p2: 'mature' },
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
        const missingFields = []
        const gameId = String(newClothes.game_id || '').trim()

        const clothesName = String(newClothes.name || '').trim()

        if (!clothesName) missingFields.push('服装名称')
        if (!String(newClothes.category || '').trim()) missingFields.push('分类部位')
        if (!gameId) missingFields.push('短编号')
        if (gameId && !/^\d+$/.test(gameId)) missingFields.push('数字短编号')
        if (!newClothes.stars) missingFields.push('星级')
        if (!newClothes.suit_id && newClothes.suit_status !== 'none') missingFields.push('套装状态')
        ATTRIBUTE_PAIRS.forEach((pair, index) => {
            if (!newClothes[pair.key] || !newClothes[pair.gradeKey]) {
                missingFields.push(`第 ${index + 1} 组属性`)
            }
        })

        if (missingFields.length) {
            throw new Error(`请先补全核心字段：${missingFields.join('、')}。特殊标签为选填。`)
        }

        isSubmitting.value = true
        try {
            const matrix = SCORE_MATRIX[getBroadCategory(newClothes.category)] || SCORE_MATRIX['饰品']
            const calculatedScores = {}
            // 🌟 修复：将数组单独提取为一个变量，彻底避开 JS 引擎的换行解析陷阱
            const pairs = [['pair1', 'grade1'], ['pair2', 'grade2'], ['pair3', 'grade3'], ['pair4', 'grade4'], ['pair5', 'grade5']]
            pairs.forEach(([p, g]) => {
                calculatedScores[newClothes[p]] = matrix[newClothes[g]] || 0
            })

            const payload = {
                id: `custom_${Date.now()}`, game_id: gameId, name: clothesName,
                category: newClothes.category, stars: Number(newClothes.stars), scores: calculatedScores,
                suit_id: newClothes.suit_id || null,
                tags: normalizeClothingTags(newClothes.tags) || null
            }

            await adminService.submitArbitration(payload, newClothes.pendingIds)

            const successName = newClothes.name
            Object.assign(newClothes, { ...createClothesEntryFormState(), pendingIds: [] })
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

    const approvePendingSuit = async (suitName) => {
        await adminService.approveSuit(suitName)
        await fetchAllData()
        await fetchSuits()
    }
    const rejectPendingSuit = async (suitName) => {
        await adminService.rejectPendingSuitsByName(suitName)
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
