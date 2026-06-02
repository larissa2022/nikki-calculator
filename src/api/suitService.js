// src/api/suitService.js
import { supabase } from './supabase'

export const suitService = {
  // 1. 获取所有套装列表 (用于下拉搜索)
  async getAllSuits() {
    try {
      const { data, error } = await supabase
        .from('suits')
        .select('id, name')
        // 🌟 核心修改：改为按照创建时间倒序排列 (最新的在最上面)
        .order('created_at', { ascending: false }); 
        
      if (error) throw error;
      return data || [];
    } catch (error) {
      console.error("❌ 数据库读取 [suits] 表失败：", error);
      throw error;
    }
  },
  // 2. 申请新建一个套装
  async applyNewSuit(name, userId) {
    const { error } = await supabase.from('pending_suits').insert([{
      name: name.trim(),
      submitted_by: userId,
      status: 'pending'
    }]);
    
    if (error) throw error;
    return true;
  }
}