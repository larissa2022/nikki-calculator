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
      correction_requests: {
        Row: {
          accepted_patch: Json | null
          clothes_id: string
          clothes_snapshot: Json
          created_at: string
          evidence_image_path: string | null
          field_key: string
          id: string
          proposed_patch: Json
          re_review_item_id: string | null
          reason: string
          reported_by: string | null
          resolution_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          source_pending_id: number | null
          status: string
          updated_at: string
        }
        Insert: {
          accepted_patch?: Json | null
          clothes_id: string
          clothes_snapshot: Json
          created_at?: string
          evidence_image_path?: string | null
          field_key: string
          id?: string
          proposed_patch: Json
          re_review_item_id?: string | null
          reason: string
          reported_by?: string | null
          resolution_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_pending_id?: number | null
          status?: string
          updated_at?: string
        }
        Update: {
          accepted_patch?: Json | null
          clothes_id?: string
          clothes_snapshot?: Json
          created_at?: string
          evidence_image_path?: string | null
          field_key?: string
          id?: string
          proposed_patch?: Json
          re_review_item_id?: string | null
          reason?: string
          reported_by?: string | null
          resolution_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_pending_id?: number | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "correction_requests_clothes_id_fkey"
            columns: ["clothes_id"]
            isOneToOne: false
            referencedRelation: "clothes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "correction_requests_re_review_item_id_fkey"
            columns: ["re_review_item_id"]
            isOneToOne: false
            referencedRelation: "re_review_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "correction_requests_source_pending_id_fkey"
            columns: ["source_pending_id"]
            isOneToOne: false
            referencedRelation: "pending_clothes"
            referencedColumns: ["id"]
          },
        ]
      }
      jury_admin_decisions: {
        Row: {
          admin_user_id: string | null
          candidate_id: string
          created_at: string
          decision: string
          id: string
          re_review_item_id: string
          reason: string
        }
        Insert: {
          admin_user_id?: string | null
          candidate_id: string
          created_at?: string
          decision: string
          id?: string
          re_review_item_id: string
          reason: string
        }
        Update: {
          admin_user_id?: string | null
          candidate_id?: string
          created_at?: string
          decision?: string
          id?: string
          re_review_item_id?: string
          reason?: string
        }
        Relationships: [
          {
            foreignKeyName: "jury_admin_decisions_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: true
            referencedRelation: "re_review_candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jury_admin_decisions_item_id_fkey"
            columns: ["re_review_item_id"]
            isOneToOne: false
            referencedRelation: "re_review_items"
            referencedColumns: ["id"]
          },
        ]
      }
      jury_votes: {
        Row: {
          candidate_id: string
          created_at: string
          id: string
          user_id: string | null
          vote: string
        }
        Insert: {
          candidate_id: string
          created_at?: string
          id?: string
          user_id?: string | null
          vote: string
        }
        Update: {
          candidate_id?: string
          created_at?: string
          id?: string
          user_id?: string | null
          vote?: string
        }
        Relationships: [
          {
            foreignKeyName: "jury_votes_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "re_review_candidates"
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
          needs_suit_review: boolean
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
          needs_suit_review?: boolean
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
          needs_suit_review?: boolean
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
          correction_request_id: string | null
          created_at: string
          delta: number
          id: string
          jury_vote_id: string | null
          occurred_at: string
          re_review_candidate_id: string | null
          reversal_of: string | null
          source_id: string | null
          source_type: string
          status: string
          user_id: string | null
        }
        Insert: {
          correction_request_id?: string | null
          created_at?: string
          delta: number
          id?: string
          jury_vote_id?: string | null
          occurred_at?: string
          re_review_candidate_id?: string | null
          reversal_of?: string | null
          source_id?: string | null
          source_type: string
          status?: string
          user_id?: string | null
        }
        Update: {
          correction_request_id?: string | null
          created_at?: string
          delta?: number
          id?: string
          jury_vote_id?: string | null
          occurred_at?: string
          re_review_candidate_id?: string | null
          reversal_of?: string | null
          source_id?: string | null
          source_type?: string
          status?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "points_ledger_correction_request_id_fkey"
            columns: ["correction_request_id"]
            isOneToOne: false
            referencedRelation: "correction_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "points_ledger_jury_vote_id_fkey"
            columns: ["jury_vote_id"]
            isOneToOne: false
            referencedRelation: "jury_votes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "points_ledger_re_review_candidate_id_fkey"
            columns: ["re_review_candidate_id"]
            isOneToOne: false
            referencedRelation: "re_review_candidates"
            referencedColumns: ["id"]
          },
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
      re_review_candidates: {
        Row: {
          created_at: string
          id: string
          payload: Json
          re_review_item_id: string
          resolved_at: string | null
          status: string
          submitted_by: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          payload: Json
          re_review_item_id: string
          resolved_at?: string | null
          status?: string
          submitted_by?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          payload?: Json
          re_review_item_id?: string
          resolved_at?: string | null
          status?: string
          submitted_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "re_review_candidates_item_id_fkey"
            columns: ["re_review_item_id"]
            isOneToOne: false
            referencedRelation: "re_review_items"
            referencedColumns: ["id"]
          },
        ]
      }
      re_review_item_sources: {
        Row: {
          created_at: string
          re_review_item_id: string
          source_pending_id: number
          source_user_id: string | null
        }
        Insert: {
          created_at?: string
          re_review_item_id: string
          source_pending_id: number
          source_user_id?: string | null
        }
        Update: {
          created_at?: string
          re_review_item_id?: string
          source_pending_id?: number
          source_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "re_review_item_sources_item_id_fkey"
            columns: ["re_review_item_id"]
            isOneToOne: false
            referencedRelation: "re_review_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_review_item_sources_pending_id_fkey"
            columns: ["source_pending_id"]
            isOneToOne: false
            referencedRelation: "pending_clothes"
            referencedColumns: ["id"]
          },
        ]
      }
      re_review_items: {
        Row: {
          clothes_id: string | null
          created_at: string
          id: string
          identity_key: string | null
          payload: Json
          reason: string
          resolved_at: string | null
          resolved_by: string | null
          source_pending_id: number | null
          status: string
          submitted_by: string | null
          updated_at: string
        }
        Insert: {
          clothes_id?: string | null
          created_at?: string
          id?: string
          identity_key?: string | null
          payload: Json
          reason: string
          resolved_at?: string | null
          resolved_by?: string | null
          source_pending_id?: number | null
          status?: string
          submitted_by?: string | null
          updated_at?: string
        }
        Update: {
          clothes_id?: string | null
          created_at?: string
          id?: string
          identity_key?: string | null
          payload?: Json
          reason?: string
          resolved_at?: string | null
          resolved_by?: string | null
          source_pending_id?: number | null
          status?: string
          submitted_by?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "re_review_items_clothes_id_fkey"
            columns: ["clothes_id"]
            isOneToOne: false
            referencedRelation: "clothes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_review_items_source_pending_id_fkey"
            columns: ["source_pending_id"]
            isOneToOne: false
            referencedRelation: "pending_clothes"
            referencedColumns: ["id"]
          },
        ]
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
      clothing_contributors_public: {
        Row: {
          clothes_id: string | null
          contributed_at: string | null
          contribution_rank: number | null
          display_name: string | null
        }
        Relationships: []
      }
      user_points_summary: {
        Row: {
          total_points: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      add_clothes_to_submitter_wardrobes: {
        Args: { p_clothes_id: string; p_user_ids: string[] }
        Returns: number
      }
      admin_reject_jury_candidate: {
        Args: { p_candidate_id: string; p_reason: string }
        Returns: Json
      }
      apply_approved_jury_candidate: {
        Args: {
          p_candidate_id: string
          p_re_review_item_id: string
          p_resolved_by: string
        }
        Returns: Json
      }
      approve_pending_clothes_arbitration: {
        Args: {
          p_category: string
          p_game_id: string
          p_id: string
          p_name: string
          p_needs_suit_review?: boolean
          p_pending_ids?: number[]
          p_scores: Json
          p_stars: number
          p_suit_id?: string
          p_tags?: string
          p_temp_suit_name?: string
        }
        Returns: Json
      }
      approve_pending_clothes_arbitration_db4_core: {
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
      build_jury_review_payload: {
        Args: { p_clothes_id?: string; p_pending_ids: number[] }
        Returns: Json
      }
      cast_jury_vote: {
        Args: { p_candidate_id: string; p_vote: string }
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
      complete_existing_clothes_from_pending_db3_core: {
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
      correction_accepted_value_is_valid: {
        Args: { p_field: string; p_value: Json }
        Returns: boolean
      }
      correction_field_is_directly_completable: {
        Args: { p_field: string; p_payload: Json }
        Returns: boolean
      }
      correction_field_value: {
        Args: { p_field: string; p_payload: Json }
        Returns: Json
      }
      correction_proposed_value_is_valid: {
        Args: { p_field: string; p_value: Json }
        Returns: boolean
      }
      deduct_user_quota: { Args: { user_id_param: string }; Returns: boolean }
      ensure_full_jury_review_item: {
        Args: {
          p_clothes_id?: string
          p_pending_id: number
          p_require_five_sources?: boolean
        }
        Returns: string
      }
      ensure_missing_suit_re_review_item: {
        Args: {
          p_allow_create?: boolean
          p_clothes_id: string
          p_pending_ids: number[]
        }
        Returns: string
      }
      get_correction_review_queue: { Args: never; Returns: Json }
      get_jury_review_queue: { Args: never; Returns: Json }
      get_jury_review_queue_with_evidence: { Args: never; Returns: Json }
      get_my_correction_requests: { Args: never; Returns: Json }
      is_admin_or_super_admin: { Args: never; Returns: boolean }
      is_super_admin: { Args: never; Returns: boolean }
      jury_clothes_payload: { Args: { p_clothes_id: string }; Returns: Json }
      jury_field_value_is_missing: {
        Args: { p_field: string; p_payload: Json }
        Returns: boolean
      }
      jury_payload_field_value: {
        Args: { p_field: string; p_payload: Json }
        Returns: Json
      }
      jury_payload_is_complete: { Args: { p_payload: Json }; Returns: boolean }
      jury_pending_payload: { Args: { p_pending_id: number }; Returns: Json }
      jury_record_payload: {
        Args: {
          p_category: string
          p_game_id: string
          p_name: string
          p_needs_suit_review: boolean
          p_scores: Json
          p_stars: number
          p_suit_id: string
          p_tags: string
          p_temp_suit_name: string
        }
        Returns: Json
      }
      jury_scores_are_complete: { Args: { p_scores: Json }; Returns: boolean }
      normalize_known_clothing_tags: {
        Args: { p_tags: string }
        Returns: string
      }
      profile_role_level_to_text: {
        Args: { p_role_level: number }
        Returns: string
      }
      profile_role_to_level: { Args: { p_role: string }; Returns: number }
      review_correction_request: {
        Args: {
          p_accepted_value?: Json
          p_action: string
          p_request_id: string
          p_resolution_note?: string
        }
        Returns: Json
      }
      route_correction_request_to_jury: {
        Args: { p_request_id: string }
        Returns: string
      }
      submit_clothing_contribution: {
        Args: {
          p_category: string
          p_game_id: string
          p_name: string
          p_needs_suit_review?: boolean
          p_scores: Json
          p_stars: number
          p_suit_id?: string
          p_tags?: string
          p_temp_suit_name?: string
        }
        Returns: Json
      }
      submit_clothing_contribution_db7_core: {
        Args: {
          p_category: string
          p_game_id: string
          p_name: string
          p_needs_suit_review?: boolean
          p_scores: Json
          p_stars: number
          p_suit_id?: string
          p_tags?: string
          p_temp_suit_name?: string
        }
        Returns: Json
      }
      submit_correction_request: {
        Args: { p_clothes_id: string; p_proposed_patch: Json; p_reason: string }
        Returns: Json
      }
      submit_correction_request_with_evidence: {
        Args: {
          p_clothes_id: string
          p_evidence_image_path: string
          p_proposed_patch: Json
        }
        Returns: Json
      }
      submit_jury_candidate: {
        Args: { p_payload: Json; p_re_review_item_id: string }
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
