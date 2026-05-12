// src/api/suitService.js
import { supabase } from './supabase'

export const suitService = {
  // 1. 获取所有套装列表 (用于下拉搜索)
  async getAllSuits() {
    const { data, error } = await supabase
      .from('suits')
      .select('id, name')
      .order('name');
      
    if (error) {
      console.error("❌ 获取套装列表失败：", error);
      throw error;
    }
    return data || [];
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