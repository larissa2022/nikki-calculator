// src/api/adminService.js
import { supabase } from './supabase'

export const adminService = {
  // 1. 获取当前登录站长的身份
  async getCurrentUserRole() {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return { userId: null, role: 'user' };
    const { data: profile } = await supabase.from('profiles').select('role').eq('id', user.id).single();
    return { userId: user.id, role: profile?.role || 'user' };
  },

  // 2. 获取审核大盘数据 (散件、套装、贡献度统计)
  async getPendingData() {
    const [clothesRes, suitsRes, contribRes] = await Promise.all([
      supabase.from('pending_clothes').select('*, suits(name)').eq('status', 'pending').order('id', { ascending: false }),
      supabase.from('pending_suits').select('*').eq('status', 'pending').order('created_at', { ascending: false }),
      supabase.from('pending_clothes').select('submitted_by').eq('status', 'approved')
    ]);
    
    const countsMap = {};
    contribRes.data?.forEach(row => { 
      if (row.submitted_by) countsMap[row.submitted_by] = (countsMap[row.submitted_by] || 0) + 1;
    });

    return {
      pendingClothes: clothesRes.data || [],
      pendingSuits: suitsRes.data || [],
      countsMap
    };
  },

  // 3. 获取全站玩家档案 (仅限超管)
  async getAllUsers(countsMap) {
    const { data } = await supabase.from('profiles').select('*').order('created_at', { ascending: false });
    return (data || []).map(u => ({ ...u, contribCount: countsMap[u.id] || 0 }));
  },

  // 4. 更改用户权限
  async updateUserRole(userId, newRole) {
    const { error } = await supabase.from('profiles').update({ role: newRole }).eq('id', userId);
    if (error) throw new Error('权限修改失败：' + error.message);
    return true;
  },

  // 5. 批准套装建档 (带事务安全检测)
  async approveSuit(id, name) {
    const { error: suitErr } = await supabase.from('suits').insert([{ name }]);
    if (suitErr) throw new Error('写入套装库失败: ' + suitErr.message);

    const { error: pendingErr } = await supabase.from('pending_suits').update({ status: 'approved' }).eq('id', id);
    if (pendingErr) throw new Error('更新审核状态失败: ' + pendingErr.message);
    return true;
  },

  // 6. 驳回任意申请
  async rejectPending(tableName, id) {
    const { error } = await supabase.from(tableName).update({ status: 'rejected' }).eq('id', id);
    if (error) throw error;
    return true;
  },

  // 7. 终极仲裁入库 (散件)
  async submitArbitration(payload, pendingIds) {
    // 写入主衣服库
    const { error } = await supabase.from('clothes').insert([payload]);
    if (error) throw new Error('入库失败: ' + error.message);
    
    // 批量通过该聚类下的所有玩家申请
    if (pendingIds && pendingIds.length > 0) {
      await supabase.from('pending_clothes').update({ status: 'approved' }).in('id', pendingIds);
    }
    return true;
  }
};