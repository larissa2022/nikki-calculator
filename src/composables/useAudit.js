// src/composables/useAudit.js
import { ref, reactive, computed } from 'vue'
import { adminService } from '../api/adminService'
import { suitService } from '../api/suitService'
import { ATTRIBUTE_PAIRS, createClothesEntryFormState, normalizeClothingTags } from '../utils/gameConstants'
import { buildClothingScoresFromForm } from '../utils/clothingScores'
import { restorePendingSuitState } from '../utils/pendingSuitState'
import { isAdminRole } from '../utils/roles'
// 🌟 引入全局数值大脑
import { GRADE_OPTIONS, SCORE_MATRIX, getBroadCategory } from './useScoreEngine'

export function useAudit() {
    // 1. 核心状态
    const currentUserRole = ref('user')
    const currentUserId = ref(null)
    const allUsersList = ref([])
    const pendingList = ref([])
    const existingClothesList = ref([])
    const pendingSuitsList = ref([])
    const suitList = ref([])
    const isPendingLoading = ref(false)
    const isSubmitting = ref(false)
    const auditSelectionInfo = ref(null)

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

    const normalizeText = (value) => String(value ?? '').trim()

    const stableStringify = (value) => {
        if (value === null || value === undefined) return ''
        if (typeof value !== 'object') return String(value)
        if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`
        return `{${Object.keys(value).sort().map(key => `${key}:${stableStringify(value[key])}`).join(',')}}`
    }

    const getPendingItemKey = (item) => {
        const gameId = normalizeText(item.game_id)
        return gameId && gameId !== 'N'
            ? `${normalizeText(item.category)}::${gameId}`
            : `NAME::${normalizeText(item.name)}`
    }

    const getVariantKey = (item) => [
        normalizeText(item.name),
        normalizeText(item.category),
        normalizeText(item.game_id),
        normalizeText(item.stars),
        normalizeText(item.suit_id),
        normalizeText(item.temp_suit_name),
        item.needs_suit_review === true ? 'needs-suit-review' : 'settled-suit-status',
        normalizeClothingTags(item.tags) || '',
        stableStringify(item.scores || {})
    ].join('||')

    const countSubmitters = (items) => new Set(
        items.map(item => item.submitted_by).filter(Boolean)
    ).size

    const isSameClothesIdentity = (pendingItem, existingItem) => {
        if (!pendingItem || !existingItem) return false
        const pendingGameId = normalizeText(pendingItem.game_id)
        const existingGameId = normalizeText(existingItem.game_id)
        const gameIdMatches = !existingGameId || existingGameId === pendingGameId
        return normalizeText(pendingItem.name) === normalizeText(existingItem.name)
            && normalizeText(pendingItem.category) === normalizeText(existingItem.category)
            && gameIdMatches
    }

    const createKnownClothesMap = () => {
        const map = new Map()
        existingClothesList.value.forEach(item => {
            const gameId = normalizeText(item.game_id)
            const category = normalizeText(item.category)
            if (!gameId || !category) return
            const key = `${category}::${gameId}`
            if (!map.has(key)) map.set(key, [])
            map.get(key).push(item)
        })
        return map
    }

    const analyzePendingGroup = (group, knownClothesMap) => {
        const variants = new Map()
        group.items.forEach(item => {
            const key = getVariantKey(item)
            if (!variants.has(key)) variants.set(key, [])
            variants.get(key).push(item)
        })

        const variantList = Array.from(variants.values())
            .map(items => ({
                items,
                rowCount: items.length,
                submitterCount: countSubmitters(items),
                sample: items[0]
            }))
            .sort((a, b) => b.submitterCount - a.submitterCount || b.rowCount - a.rowCount)

        const topVariant = variantList[0] || null
        const topSample = topVariant?.sample || group.items[0] || null
        const gameId = normalizeText(topSample?.game_id)
        const category = normalizeText(topSample?.category)
        const knownCandidates = knownClothesMap.get(`${category}::${gameId}`) || []
        const knownClothes = knownCandidates.filter(item => isSameClothesIdentity(topSample, item))
        const distinctSubmitterCount = countSubmitters(group.items)
        const anonymousCount = group.items.filter(item => !item.submitted_by).length
        const hasConflict = variantList.length > 1
        const hasKnownClothes = knownClothes.length > 0
        const hasKnownMismatch = knownCandidates.length > 0 && !hasKnownClothes
        const canCompleteExisting = hasKnownClothes
            && Boolean(topVariant?.items?.length)
            && topVariant.items.every(item => isSameClothesIdentity(item, knownClothes[0]))
        const topSubmitterCount = topVariant?.submitterCount || 0
        const legacyOnly = distinctSubmitterCount === 0 && group.items.length > 0

        let candidateStatus = 'insufficient'
        let statusLabel = '人数不足'
        let statusClass = 'bg-slate-100 text-slate-500'
        let riskRank = 4

        if (hasKnownMismatch) {
            candidateStatus = 'known_mismatch'
            statusLabel = '需人工处理'
            statusClass = 'bg-rose-100 text-rose-600'
            riskRank = 2
        } else if (hasKnownClothes) {
            candidateStatus = 'known'
            statusLabel = '补全已有'
            statusClass = 'bg-blue-100 text-blue-600'
            riskRank = 3
        } else if (legacyOnly) {
            candidateStatus = 'legacy'
            statusLabel = '匿名历史数据'
            statusClass = 'bg-slate-100 text-slate-500'
            riskRank = 5
        } else if (topSubmitterCount >= 5 && hasConflict) {
            candidateStatus = 'conflict'
            statusLabel = '可按多数入库'
            statusClass = 'bg-amber-100 text-amber-700'
            riskRank = 1
        } else if (topSubmitterCount >= 5) {
            candidateStatus = 'ready'
            statusLabel = '可入库'
            statusClass = 'bg-emerald-100 text-emerald-700'
            riskRank = 0
        } else if (hasConflict) {
            candidateStatus = 'weak_conflict'
            statusLabel = '需要继续收集'
            statusClass = 'bg-orange-100 text-orange-600'
            riskRank = 2
        }

        return {
            ...group,
            totalRows: group.items.length,
            distinctSubmitterCount,
            anonymousCount,
            variantCount: variantList.length,
            variants: variantList,
            topVariant,
            topSubmitterCount,
            knownClothes,
            knownCandidates,
            hasKnownClothes,
            hasKnownMismatch,
            canCompleteExisting,
            hasConflict,
            candidateStatus,
            statusLabel,
            statusClass,
            riskRank
        }
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
            const { pendingClothes, pendingSuits, countsMap, existingClothes } = await pendingPromise
            pendingList.value = pendingClothes || []
            existingClothesList.value = existingClothes || []
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
        const knownClothesMap = createKnownClothesMap()

        pendingList.value.forEach(item => {
            const key = getPendingItemKey(item)
            if (!groups[key]) groups[key] = { key, name: item.name || '未命名散件', items: [] }
            groups[key].items.push(item)
        })
        return Object.values(groups).map(group => analyzePendingGroup(group, knownClothesMap))
    })

    // 5. 仲裁处理逻辑
    const processClusteredItem = (group) => {
        const items = group.topVariant?.items?.length ? group.topVariant.items : group.items
        const userMap = Object.fromEntries(allUsersList.value.map(u => [u.id, u.contribCount]))
        const bestItem = items.reduce((prev, curr) => (userMap[curr.submitted_by] || 0) > (userMap[prev.submitted_by] || 0) ? curr : prev)
        const existingClothes = group.canCompleteExisting ? group.knownClothes?.[0] : null
        const requiresManualReview = Boolean(group.hasKnownMismatch || (group.hasKnownClothes && !group.canCompleteExisting))
        const manualReviewMessage = requiresManualReview
            ? '该提交与正式库记录不匹配，不能直接补全，请进入重审 / 人工处理。'
            : ''
        auditSelectionInfo.value = {
            selectedCount: items.length,
            totalCount: group.items.length,
            selectedSubmitterCount: countSubmitters(items),
            totalSubmitterCount: group.distinctSubmitterCount || countSubmitters(group.items),
            conflictCount: Math.max((group.variantCount || 1) - 1, 0),
            statusLabel: group.statusLabel || '',
            existingClothes,
            canCompleteExisting: Boolean(existingClothes),
            requiresManualReview,
            manualReviewMessage,
            variants: (group.variants || []).map((variant, index) => ({
                key: `${group.key}_${index}`,
                selected: variant === group.topVariant,
                rowCount: variant.rowCount,
                submitterCount: variant.submitterCount,
                name: variant.sample?.name || '',
                stars: variant.sample?.stars || '',
                suitLabel: variant.sample?.suit_id
                    ? '已关联套装'
                    : (
                        variant.sample?.temp_suit_name
                            ? `新套装：${variant.sample.temp_suit_name}`
                            : (variant.sample?.needs_suit_review ? '所属套装待确认' : '无关联套装（纯散件）')
                    ),
                tags: normalizeClothingTags(variant.sample?.tags) || '无标签',
                pendingIds: variant.items.map(item => item.id).join(', ')
            }))
        }

        newClothes.pendingIds = items.map(i => i.id)
        newClothes.name = bestItem.name
        newClothes.game_id = bestItem.game_id || ''
        newClothes.category = bestItem.category
        newClothes.stars = Number(getMostFrequent(items.map(i => i.stars)))
        const pendingSuitState = restorePendingSuitState(bestItem)
        newClothes.suit_id = pendingSuitState.suitId
        newClothes.suit_status = pendingSuitState.status
        newClothes.existingClothesId = existingClothes?.id || ''
        newClothes.requiresManualReview = requiresManualReview

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
        // 返回完整套装状态，供 UI 层同步已有套装、临时套装和纯散件显示。
        return pendingSuitState
    }

    // 6. 最终执行入库
    const resetAuditSelection = () => {
        Object.assign(newClothes, { ...createClothesEntryFormState(), pendingIds: [] })
        newClothes.existingClothesId = ''
        newClothes.requiresManualReview = false
        auditSelectionInfo.value = null
    }

    const executeSubmit = async () => {
        if (isSubmitting.value) {
            throw new Error('上一条审核还在处理中，请稍等片刻。')
        }

        const missingFields = []
        const gameId = String(newClothes.game_id || '').trim()

        const clothesName = String(newClothes.name || '').trim()

        if (!clothesName) missingFields.push('服装名称')
        if (!String(newClothes.category || '').trim()) missingFields.push('分类部位')
        if (!gameId) missingFields.push('短编号')
        if (gameId && !/^\d+$/.test(gameId)) missingFields.push('数字短编号')
        if (!newClothes.stars) missingFields.push('星级')
        if (
            !newClothes.suit_id
            && !['none', 'pending_review'].includes(newClothes.suit_status)
        ) missingFields.push('套装状态')
        const matrix = SCORE_MATRIX[getBroadCategory(newClothes.category)] || SCORE_MATRIX['饰品']
        const invalidAttributeGrades = []
        ATTRIBUTE_PAIRS.forEach((pair, index) => {
            const attrValue = String(newClothes[pair.key] || '').trim()
            const gradeValue = String(newClothes[pair.gradeKey] || '').trim()
            if (!attrValue || !gradeValue) {
                missingFields.push(`第 ${index + 1} 组属性`)
            } else if (!GRADE_OPTIONS.includes(gradeValue) || !Object.prototype.hasOwnProperty.call(matrix, gradeValue)) {
                invalidAttributeGrades.push(pair.options.find(option => option.value === attrValue)?.label || `第 ${index + 1} 组属性`)
            }
        })

        if (missingFields.length) {
            throw new Error(`请先补全核心字段：${missingFields.join('、')}。特殊标签为选填。`)
        }

        if (invalidAttributeGrades.length) {
            throw new Error(`请先补全所有属性等级，例如“简约：完美/优秀/完美+”。需检查：${invalidAttributeGrades.join('、')}。`)
        }

        if (auditSelectionInfo.value?.requiresManualReview) {
            throw new Error(auditSelectionInfo.value.manualReviewMessage || '该提交与正式库记录不匹配，不能直接补全，请进入重审 / 人工处理。')
        }

        isSubmitting.value = true
        try {
            const calculatedScores = buildClothingScoresFromForm(newClothes.category, newClothes)

            const payload = {
                id: `custom_${Date.now()}`, game_id: gameId, name: clothesName,
                category: newClothes.category, stars: Number(newClothes.stars), scores: calculatedScores,
                suit_id: newClothes.suit_id || null,
                needs_suit_review: newClothes.suit_status === 'pending_review',
                tags: normalizeClothingTags(newClothes.tags) || null
            }

            const pendingIds = newClothes.pendingIds || []
            const existingClothes = auditSelectionInfo.value?.existingClothes
                || await adminService.findClothesByNameCategory(clothesName, newClothes.category)
            if (existingClothes) {
                if (!pendingIds.length) {
                    throw new Error(`正式库已存在「${existingClothes.name}」（${existingClothes.category}，短编号 ${existingClothes.game_id || '无'}），不能重复发布。`)
                }

                if (!isSameClothesIdentity({ name: clothesName, category: newClothes.category, game_id: gameId }, existingClothes)) {
                    throw new Error('该提交与正式库记录不匹配，不能直接补全，请进入重审 / 人工处理。')
                }

                await adminService.completeExistingClothes(
                    { ...payload, id: existingClothes.id },
                    pendingIds
                )
            } else {
                await adminService.submitArbitration(payload, pendingIds)
            }

            const successName = newClothes.name
            resetAuditSelection()
            await fetchAllData()
            return successName
        } finally {
            isSubmitting.value = false
        }
    }

    const rejectPendingItem = async (ids) => {
        if (isSubmitting.value) {
            throw new Error('上一条审核还在处理中，请稍等片刻。')
        }

        isSubmitting.value = true
        try {
            const rejectedIds = await adminService.rejectPendingClothes(ids)
            resetAuditSelection()
            await fetchAllData()
            return rejectedIds.length
        } finally {
            isSubmitting.value = false
        }
    }

    const approvePendingSuit = async (suitName, options) => {
        const result = await adminService.approveSuit(suitName, options)
        await fetchAllData()
        await fetchSuits()
        return result
    }
    const rejectPendingSuit = async (suitName, reason) => {
        const result = await adminService.rejectPendingSuitsByName(suitName, reason)
        await fetchAllData()
        return result
    }

    // 对外暴露的属性和方法
    return {
        currentUserRole, currentUserId, allUsersList,
        pendingSuitsList, suitList, isPendingLoading, isSubmitting, newClothes, auditSelectionInfo,
        fetchAllData, fetchSuits, clusteredPendingList,
        processClusteredItem, executeSubmit, rejectPendingItem,
        approvePendingSuit, rejectPendingSuit // 👈 🌟 记得在这里把它们暴露出去！
    }
}
