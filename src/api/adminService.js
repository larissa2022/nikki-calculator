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

    // 6. 驳回任意申请
    async rejectPending(tableName, id) {
        const { error } = await supabase.from(tableName).update({ status: 'rejected' }).eq('id', id);
        if (error) throw error;
        return true;
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

        if (error) throw new Error('补全正式库失败: ' + error.message);
        return true;
    }
};
