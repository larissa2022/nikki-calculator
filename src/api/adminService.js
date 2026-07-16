// src/api/adminService.js
import { supabase } from './supabase'
import { getRoleKey, getRoleLevel, getRoleUpdatePayload } from '../utils/roles'

const chunkArray = (items, size = 100) => {
    const chunks = []
    for (let i = 0; i < items.length; i += size) {
        chunks.push(items.slice(i, i + size))
    }
    return chunks
}

const fetchExistingClothesForPending = async (pendingClothes) => {
    const gameIds = [
        ...new Set(
            (pendingClothes || [])
                .map(item => String(item.game_id || '').trim())
                .filter(gameId => gameId && gameId !== 'N')
        )
    ]

    if (!gameIds.length) return []

    const rows = []
    for (const chunk of chunkArray(gameIds)) {
        const { data, error } = await supabase
            .from('clothes')
            .select('id,name,category,game_id')
            .in('game_id', chunk)

        if (error) throw error
        rows.push(...(data || []))
    }

    return rows
}

const createFriendlyCompleteExistingError = (error) => {
    const rawMessage = String(error?.message || '')
    const technicalReason = (() => {
        if (rawMessage.includes('星级已有非空值')) return '星级冲突'
        if (rawMessage.includes('短编号已有非空值')) return '短编号冲突'
        if (rawMessage.includes('属性分值已有非空值')) return '属性分值冲突'
        if (rawMessage.includes('套装关联已有非空值')) return '套装关联冲突'
        if (rawMessage.includes('临时套装名已有非空值')) return '临时套装名冲突'
        if (rawMessage.includes('标签已有非空值')) return '标签冲突'
        if (rawMessage.includes('不属于本次正式库补全范围')) return '待审核记录不匹配'
        if (rawMessage.includes('通过数量异常')) return '待审核状态已变化'
        if (rawMessage.includes('没有补全正式库权限')) return '权限不足'
        if (rawMessage.includes('正式库服装不存在')) return '正式库记录不匹配'
        return ''
    })()

    const message = (() => {
        if (technicalReason === '星级冲突') {
            return '这件衣服在正式库中已有不同的星级，不能直接覆盖。请走重审 / 陪审团流程。'
        }
        if (technicalReason === '短编号冲突') {
            return '这件衣服在正式库中已有不同的短编号，不能直接覆盖。请走重审 / 陪审团流程。'
        }
        if (technicalReason === '属性分值冲突') {
            return '这件衣服在正式库中已有不同的属性分值，不能直接覆盖。请走重审 / 陪审团流程。'
        }
        if (technicalReason === '套装关联冲突' || technicalReason === '临时套装名冲突') {
            return '这件衣服在正式库中已有不同的套装信息，不能直接覆盖。请走重审 / 陪审团流程。'
        }
        if (technicalReason === '标签冲突') {
            return '这件衣服在正式库中已有不同的标签，不能直接覆盖。请走重审 / 陪审团流程。'
        }
        if (technicalReason === '待审核记录不匹配' || technicalReason === '正式库记录不匹配') {
            return '该提交与正式库记录不匹配，不能直接补全。请进入重审 / 人工处理。'
        }
        if (technicalReason === '待审核状态已变化') {
            return '这条待审核记录的状态已经变化，请刷新审核页后再处理。'
        }
        if (technicalReason === '权限不足') {
            return '当前账号没有补全正式库的权限。'
        }
        return '补全正式库失败，请刷新后重试；如果仍失败，请进入重审 / 人工处理。'
    })()

    const friendlyError = new Error(technicalReason ? `${message}（技术原因：${technicalReason}）` : message)
    friendlyError.cause = error
    friendlyError.technicalReason = technicalReason
    return friendlyError
}

export const adminService = {
    // 1. 获取当前登录站长的身份
    async getCurrentUserRole() {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) return { userId: null, role: 'user' };
        const { data: profile } = await supabase.from('profiles').select('*').eq('id', user.id).single();
        return { userId: user.id, role: getRoleKey(profile), roleLevel: getRoleLevel(profile) };
    },

    // 2. 获取审核大盘数据 (散件、套装、贡献度统计)
    async getPendingData() {
        const [clothesRes, suitsRes, contribRes] = await Promise.all([
            supabase.from('pending_clothes').select('*, suits(name)').eq('status', 'pending').order('id', { ascending: false }),
            supabase.from('pending_suits').select('*').eq('status', 'pending').order('created_at', { ascending: false }),
            supabase.from('pending_clothes').select('submitted_by').eq('status', 'approved')
        ]);

        // 🌟 修复：取代原先脆弱的可选链操作，使用前置结构判断
        const countsMap = {};
        if (contribRes.data && Array.isArray(contribRes.data)) {
            contribRes.data.forEach(row => {
                if (row.submitted_by) countsMap[row.submitted_by] = (countsMap[row.submitted_by] || 0) + 1;
            });
        }

        const pendingClothes = clothesRes.data || []
        const existingClothes = await fetchExistingClothesForPending(pendingClothes).catch(err => {
            console.error('获取正式库重复项失败:', err)
            return []
        })

        return {
            pendingClothes,
            pendingSuits: suitsRes.data || [],
            countsMap,
            existingClothes
        };
    },

    // 3. 获取全站玩家档案 (仅限超管)
    async getAllUsers(countsMap) {
        const { data } = await supabase.from('profiles').select('*').order('created_at', { ascending: false });
        return (data || []).map(u => ({
            ...u,
            role: getRoleKey(u),
            role_level: getRoleLevel(u),
            contribCount: countsMap[u.id] || 0
        }));
    },

    // 4. 更改用户权限
    async updateUserRole(userId, newRole) {
        const { error } = await supabase.from('profiles').update(getRoleUpdatePayload(newRole)).eq('id', userId);
        if (error) throw new Error('权限修改失败：' + error.message);
        return true;
    },

    async approveSuit(name) {
        const cleanName = name?.trim()
        if (!cleanName) throw new Error('套装名称不能为空')

        const { error: insertErr } = await supabase
            .from('suits')
            .upsert(
                [{ name: cleanName }],
                { onConflict: 'name', ignoreDuplicates: true }
            )

        if (insertErr) {
            throw new Error('写入套装库失败: ' + insertErr.message)
        }

        const { error: delErr } = await supabase
            .from('pending_suits')
            .delete()
            .eq('name', cleanName)

        if (delErr) {
            throw new Error('清理待办套装失败: ' + delErr.message)
        }

        return true
    },

    // 6. 驳回当前选中的服装申请
    async rejectPendingClothes(ids) {
        const pendingIds = [...new Set((Array.isArray(ids) ? ids : [ids]).filter(Boolean))]
        if (!pendingIds.length) throw new Error('没有可驳回的服装申请')

        const { data, error } = await supabase
            .from('pending_clothes')
            .update({ status: 'rejected' })
            .in('id', pendingIds)
            .eq('status', 'pending')
            .select('id')

        if (error) throw new Error('驳回服装申请失败: ' + error.message)
        if ((data || []).length !== pendingIds.length) {
            throw new Error('部分服装申请的状态已经变化，请刷新审核页后重试。')
        }
        return data.map(item => item.id)
    },

    async rejectPendingSuitsByName(name) {
        const cleanName = name?.trim()
        if (!cleanName) throw new Error('套装名称不能为空')

        const { error } = await supabase
            .from('pending_suits')
            .update({ status: 'rejected' })
            .eq('name', cleanName)

        if (error) throw error
        return true
    },

    async findClothesByNameCategory(name, category) {
        const cleanName = String(name || '').trim()
        const cleanCategory = String(category || '').trim()
        if (!cleanName || !cleanCategory) return null

        const { data, error } = await supabase
            .from('clothes')
            .select('id,name,category,game_id')
            .eq('name', cleanName)
            .eq('category', cleanCategory)
            .maybeSingle()

        if (error) throw error
        return data || null
    },

    // 7. 终极仲裁入库 (散件)
    async submitArbitration(payload, pendingIds) {
        const { error } = await supabase.rpc('approve_pending_clothes_arbitration', {
            p_id: payload.id,
            p_name: payload.name,
            p_game_id: payload.game_id,
            p_category: payload.category,
            p_stars: Number(payload.stars),
            p_scores: payload.scores,
            p_suit_id: payload.suit_id || null,
            p_temp_suit_name: payload.temp_suit_name || null,
            p_tags: payload.tags || null,
            p_pending_ids: pendingIds || []
        });

        if (error) {
            const isDuplicateClothes = error.code === '23505'
                || String(error.message || '').includes('clothes_name_category_unique')
            if (isDuplicateClothes) {
                throw new Error('正式库已存在同名同分类服装，请刷新后台后在“正式库已有”中处理。')
            }
            throw new Error('入库失败: ' + error.message);
        }
        return true;
    },

    async completeExistingClothes(payload, pendingIds) {
        const { error } = await supabase.rpc('complete_existing_clothes_from_pending', {
            p_existing_id: payload.id,
            p_name: payload.name,
            p_game_id: payload.game_id,
            p_category: payload.category,
            p_stars: Number(payload.stars),
            p_scores: payload.scores,
            p_suit_id: payload.suit_id || null,
            p_temp_suit_name: payload.temp_suit_name || null,
            p_tags: payload.tags || null,
            p_pending_ids: pendingIds || []
        });

        if (error) throw createFriendlyCompleteExistingError(error);
        return true;
    }
};
