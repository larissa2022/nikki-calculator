export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      app_errors: {
        Row: {
          action_name: string | null
          created_at: string
          error_message: string | null
          error_stack: string | null
          id: string
          user_agent: string | null
          user_id: string | null
        }
        Insert: {
          action_name?: string | null
          created_at?: string
          error_message?: string | null
          error_stack?: string | null
          id?: string
          user_agent?: string | null
          user_id?: string | null
        }
        Update: {
          action_name?: string | null
          created_at?: string
          error_message?: string | null
          error_stack?: string | null
          id?: string
          user_agent?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      clothes: {
        Row: {
          category: string | null
          created_at: string
          game_id: string | null
          id: string
          name: string | null
          scores: Json | null
          stars: string | null
          suit_id: string | null
          tags: string | null
          temp_suit_name: string | null
        }
        Insert: {
          category?: string | null
          created_at?: string
          game_id?: string | null
          id: string
          name?: string | null
          scores?: Json | null
          stars?: string | null
          suit_id?: string | null
          tags?: string | null
          temp_suit_name?: string | null
        }
        Update: {
          category?: string | null
          created_at?: string
          game_id?: string | null
          id?: string
          name?: string | null
          scores?: Json | null
          stars?: string | null
          suit_id?: string | null
          tags?: string | null
          temp_suit_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clothes_suit_id_fkey"
            columns: ["suit_id"]
            isOneToOne: false
            referencedRelation: "suits"
            referencedColumns: ["id"]
          },
        ]
      }
      clothing_contributions: {
        Row: {
          clothes_id: string
          contribution_rank: number
          contribution_type: string
          created_at: string
          event_id: string
          id: string
          source_created_at: string
          source_pending_id: number
          user_id: string | null
        }
        Insert: {
          clothes_id: string
          contribution_rank: number
          contribution_type: string
          created_at?: string
          event_id: string
          id?: string
          source_created_at: string
          source_pending_id: number
          user_id?: string | null
        }
        Update: {
          clothes_id?: string
          contribution_rank?: number
          contribution_type?: string
          created_at?: string
          event_id?: string
          id?: string
          source_created_at?: string
          source_pending_id?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clothing_contributions_clothes_id_fkey"
            columns: ["clothes_id"]
            isOneToOne: false
            referencedRelation: "clothes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clothing_contributions_source_pending_id_fkey"
            columns: ["source_pending_id"]
            isOneToOne: true
            referencedRelation: "pending_clothes"
            referencedColumns: ["id"]
          },
        ]
      }
      pending_clothes: {
        Row: {
          category: string | null
          created_at: string
          game_id: string | null
          id: number
          name: string | null
          scores: Json | null
          stars: number | null
          status: string | null
          submitted_by: string | null
          suit_id: string | null
          suit_name: string | null
          tags: string | null
          temp_suit_name: string | null
        }
        Insert: {
          category?: string | null
          created_at?: string
          game_id?: string | null
          id?: number
          name?: string | null
          scores?: Json | null
          stars?: number | null
          status?: string | null
          submitted_by?: string | null
          suit_id?: string | null
          suit_name?: string | null
          tags?: string | null
          temp_suit_name?: string | null
        }
        Update: {
          category?: string | null
          created_at?: string
          game_id?: string | null
          id?: number
          name?: string | null
          scores?: Json | null
          stars?: number | null
          status?: string | null
          submitted_by?: string | null
          suit_id?: string | null
          suit_name?: string | null
          tags?: string | null
          temp_suit_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pending_clothes_suit_id_fkey"
            columns: ["suit_id"]
            isOneToOne: false
            referencedRelation: "suits"
            referencedColumns: ["id"]
          },
        ]
      }
      pending_suits: {
        Row: {
          created_at: string | null
          id: string
          name: string
          status: string | null
          submitted_by: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          name: string
          status?: string | null
          submitted_by?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          name?: string
          status?: string | null
          submitted_by?: string | null
        }
        Relationships: []
      }
      points_ledger: {
        Row: {
          created_at: string
          delta: number
          id: string
          occurred_at: string
          reversal_of: string | null
          source_id: string | null
          source_type: string
          status: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          delta: number
          id?: string
          occurred_at?: string
          reversal_of?: string | null
          source_id?: string | null
          source_type: string
          status?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          delta?: number
          id?: string
          occurred_at?: string
          reversal_of?: string | null
          source_id?: string | null
          source_type?: string
          status?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "points_ledger_reversal_of_fkey"
            columns: ["reversal_of"]
            isOneToOne: false
            referencedRelation: "points_ledger"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "points_ledger_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "clothing_contributions"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string | null
          current_month_points: number | null
          email: string | null
          id: string
          monthly_action_count: number | null
          nickname: string | null
          quota: number | null
          role: string | null
          role_level: number
          total_points: number | null
          updated_at: string | null
          username: string | null
        }
        Insert: {
          created_at?: string | null
          current_month_points?: number | null
          email?: string | null
          id: string
          monthly_action_count?: number | null
          nickname?: string | null
          quota?: number | null
          role?: string | null
          role_level?: number
          total_points?: number | null
          updated_at?: string | null
          username?: string | null
        }
        Update: {
          created_at?: string | null
          current_month_points?: number | null
          email?: string | null
          id?: string
          monthly_action_count?: number | null
          nickname?: string | null
          quota?: number | null
          role?: string | null
          role_level?: number
          total_points?: number | null
          updated_at?: string | null
          username?: string | null
        }
        Relationships: []
      }
      stages: {
        Row: {
          created_at: string
          id: number
          name: string | null
          weights: Json | null
        }
        Insert: {
          created_at?: string
          id?: number
          name?: string | null
          weights?: Json | null
        }
        Update: {
          created_at?: string
          id?: number
          name?: string | null
          weights?: Json | null
        }
        Relationships: []
      }
      suits: {
        Row: {
          created_at: string | null
          description: string | null
          id: string
          name: string
          source: string | null
        }
        Insert: {
          created_at?: string | null
          description?: string | null
          id?: string
          name: string
          source?: string | null
        }
        Update: {
          created_at?: string | null
          description?: string | null
          id?: string
          name?: string
          source?: string | null
        }
        Relationships: []
      }
      user_quotas: {
        Row: {
          free_count: number | null
          user_id: string
        }
        Insert: {
          free_count?: number | null
          user_id: string
        }
        Update: {
          free_count?: number | null
          user_id?: string
        }
        Relationships: []
      }
      user_wardrobes: {
        Row: {
          created_at: string
          id: string
          owned_clothes: Json | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          owned_clothes?: Json | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          owned_clothes?: Json | null
          user_id?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      add_clothes_to_submitter_wardrobes: {
        Args: { p_clothes_id: string; p_user_ids: string[] }
        Returns: number
      }
      approve_pending_clothes_arbitration: {
        Args: {
          p_category: string
          p_game_id: string
          p_id: string
          p_name: string
          p_pending_ids?: number[]
          p_scores: Json
          p_stars: number
          p_suit_id?: string
          p_tags?: string
          p_temp_suit_name?: string
        }
        Returns: Json
      }
      complete_existing_clothes_from_pending: {
        Args: {
          p_category: string
          p_existing_id: string
          p_game_id: string
          p_name: string
          p_pending_ids?: number[]
          p_scores: Json
          p_stars: number
          p_suit_id?: string
          p_tags?: string
          p_temp_suit_name?: string
        }
        Returns: Json
      }
      deduct_user_quota: { Args: { user_id_param: string }; Returns: boolean }
      is_admin_or_super_admin: { Args: never; Returns: boolean }
      is_super_admin: { Args: never; Returns: boolean }
      normalize_known_clothing_tags: {
        Args: { p_tags: string }
        Returns: string
      }
      profile_role_level_to_text: {
        Args: { p_role_level: number }
        Returns: string
      }
      profile_role_to_level: { Args: { p_role: string }; Returns: number }
      submit_clothing_contribution: {
        Args: {
          p_category: string
          p_game_id: string
          p_name: string
          p_scores: Json
          p_stars: number
          p_suit_id?: string
          p_tags?: string
          p_temp_suit_name?: string
        }
        Returns: Json
      }
      update_profile_username: {
        Args: { p_username: string }
        Returns: {
          created_at: string | null
          current_month_points: number | null
          email: string | null
          id: string
          monthly_action_count: number | null
          nickname: string | null
          quota: number | null
          role: string | null
          role_level: number
          total_points: number | null
          updated_at: string | null
          username: string | null
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
