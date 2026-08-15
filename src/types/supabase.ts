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
      admin_candidate_exclusions: {
        Row: {
          created_at: string
          created_by: string
          ends_at: string
          id: string
          reason: string
          revoked_at: string | null
          revoked_by: string | null
          starts_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          ends_at: string
          id?: string
          reason: string
          revoked_at?: string | null
          revoked_by?: string | null
          starts_at: string
          user_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          ends_at?: string
          id?: string
          reason?: string
          revoked_at?: string | null
          revoked_by?: string | null
          starts_at?: string
          user_id?: string
        }
        Relationships: []
      }
      admin_review_decision_sources: {
        Row: {
          decision_id: string
          is_adopted: boolean
          pending_id: number
        }
        Insert: {
          decision_id: string
          is_adopted: boolean
          pending_id: number
        }
        Update: {
          decision_id?: string
          is_adopted?: boolean
          pending_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "admin_review_decision_sources_decision_id_fkey"
            columns: ["decision_id"]
            isOneToOne: false
            referencedRelation: "admin_review_decisions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admin_review_decision_sources_pending_id_fkey"
            columns: ["pending_id"]
            isOneToOne: false
            referencedRelation: "pending_clothes"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_review_decisions: {
        Row: {
          action: string
          admin_term_id: string | null
          adopted_payload: Json
          adopted_pending_ids: number[]
          all_source_pending_ids: number[]
          candidate_key: string
          created_at: string
          id: string
          reason: string | null
          reviewer_user_id: string | null
        }
        Insert: {
          action: string
          admin_term_id?: string | null
          adopted_payload: Json
          adopted_pending_ids: number[]
          all_source_pending_ids: number[]
          candidate_key: string
          created_at?: string
          id?: string
          reason?: string | null
          reviewer_user_id?: string | null
        }
        Update: {
          action?: string
          admin_term_id?: string | null
          adopted_payload?: Json
          adopted_pending_ids?: number[]
          all_source_pending_ids?: number[]
          candidate_key?: string
          created_at?: string
          id?: string
          reason?: string | null
          reviewer_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "admin_review_decisions_admin_term_id_fkey"
            columns: ["admin_term_id"]
            isOneToOne: false
            referencedRelation: "admin_terms"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_terms: {
        Row: {
          candidate_order: number | null
          created_at: string
          end_reason: string | null
          ended_at: string | null
          ended_by: string | null
          frozen_points: number | null
          granted_by: string | null
          id: string
          qualifying_action_count: number | null
          reason: string | null
          scheduled_end_at: string
          service_month: string | null
          source: string
          source_month: string | null
          starts_at: string
          status: string
          user_id: string
        }
        Insert: {
          candidate_order?: number | null
          created_at?: string
          end_reason?: string | null
          ended_at?: string | null
          ended_by?: string | null
          frozen_points?: number | null
          granted_by?: string | null
          id?: string
          qualifying_action_count?: number | null
          reason?: string | null
          scheduled_end_at: string
          service_month?: string | null
          source: string
          source_month?: string | null
          starts_at: string
          status?: string
          user_id: string
        }
        Update: {
          candidate_order?: number | null
          created_at?: string
          end_reason?: string | null
          ended_at?: string | null
          ended_by?: string | null
          frozen_points?: number | null
          granted_by?: string | null
          id?: string
          qualifying_action_count?: number | null
          reason?: string | null
          scheduled_end_at?: string
          service_month?: string | null
          source?: string
          source_month?: string | null
          starts_at?: string
          status?: string
          user_id?: string
        }
        Relationships: []
      }
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
      feature_request_events: {
        Row: {
          actor_user_id: string | null
          created_at: string
          duplicate_of: string | null
          event_type: string
          feature_request_id: string
          from_status: string | null
          from_visibility: string | null
          id: number
          public_response: string | null
          reason: string | null
          to_status: string | null
          to_visibility: string | null
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          duplicate_of?: string | null
          event_type: string
          feature_request_id: string
          from_status?: string | null
          from_visibility?: string | null
          id?: never
          public_response?: string | null
          reason?: string | null
          to_status?: string | null
          to_visibility?: string | null
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          duplicate_of?: string | null
          event_type?: string
          feature_request_id?: string
          from_status?: string | null
          from_visibility?: string | null
          id?: never
          public_response?: string | null
          reason?: string | null
          to_status?: string | null
          to_visibility?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "feature_request_events_duplicate_of_fkey"
            columns: ["duplicate_of"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feature_request_events_feature_request_id_fkey"
            columns: ["feature_request_id"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_request_likes: {
        Row: {
          cancelled_at: string | null
          created_at: string
          feature_request_id: string
          id: string
          is_active: boolean
          updated_at: string
          user_id: string | null
        }
        Insert: {
          cancelled_at?: string | null
          created_at?: string
          feature_request_id: string
          id?: string
          is_active?: boolean
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          cancelled_at?: string | null
          created_at?: string
          feature_request_id?: string
          id?: string
          is_active?: boolean
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "feature_request_likes_feature_request_id_fkey"
            columns: ["feature_request_id"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_requests: {
        Row: {
          content_fingerprint: string
          created_at: string
          description: string
          duplicate_of: string | null
          handled_at: string | null
          handled_by: string | null
          id: string
          public_response: string | null
          status: string
          submitted_by: string | null
          title: string
          updated_at: string
          visibility: string
        }
        Insert: {
          content_fingerprint: string
          created_at?: string
          description: string
          duplicate_of?: string | null
          handled_at?: string | null
          handled_by?: string | null
          id?: string
          public_response?: string | null
          status?: string
          submitted_by?: string | null
          title: string
          updated_at?: string
          visibility?: string
        }
        Update: {
          content_fingerprint?: string
          created_at?: string
          description?: string
          duplicate_of?: string | null
          handled_at?: string | null
          handled_by?: string | null
          id?: string
          public_response?: string | null
          status?: string
          submitted_by?: string | null
          title?: string
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "feature_requests_duplicate_of_fkey"
            columns: ["duplicate_of"]
            isOneToOne: false
            referencedRelation: "feature_requests"
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
          review_note: string | null
          user_id: string | null
          vote: string
          vote_weight: number
          voter_level: number
        }
        Insert: {
          candidate_id: string
          created_at?: string
          id?: string
          review_note?: string | null
          user_id?: string | null
          vote: string
          vote_weight?: number
          voter_level?: number
        }
        Update: {
          candidate_id?: string
          created_at?: string
          id?: string
          review_note?: string | null
          user_id?: string | null
          vote?: string
          vote_weight?: number
          voter_level?: number
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
          bonus_of: string | null
          correction_request_id: string | null
          created_at: string
          delta: number
          id: string
          jury_vote_id: string | null
          level_snapshot: number | null
          occurred_at: string
          re_review_candidate_id: string | null
          reversal_correction_request_id: string | null
          reversal_of: string | null
          source_id: string | null
          source_type: string
          status: string
          user_id: string | null
        }
        Insert: {
          bonus_of?: string | null
          correction_request_id?: string | null
          created_at?: string
          delta: number
          id?: string
          jury_vote_id?: string | null
          level_snapshot?: number | null
          occurred_at?: string
          re_review_candidate_id?: string | null
          reversal_correction_request_id?: string | null
          reversal_of?: string | null
          source_id?: string | null
          source_type: string
          status?: string
          user_id?: string | null
        }
        Update: {
          bonus_of?: string | null
          correction_request_id?: string | null
          created_at?: string
          delta?: number
          id?: string
          jury_vote_id?: string | null
          level_snapshot?: number | null
          occurred_at?: string
          re_review_candidate_id?: string | null
          reversal_correction_request_id?: string | null
          reversal_of?: string | null
          source_id?: string | null
          source_type?: string
          status?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "points_ledger_bonus_of_fkey"
            columns: ["bonus_of"]
            isOneToOne: false
            referencedRelation: "points_ledger"
            referencedColumns: ["id"]
          },
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
            foreignKeyName: "points_ledger_reversal_correction_request_id_fkey"
            columns: ["reversal_correction_request_id"]
            isOneToOne: false
            referencedRelation: "correction_requests"
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
          contributor_level: number | null
          display_name: string | null
        }
        Relationships: []
      }
      homepage_monthly_thanks: {
        Row: {
          display_name: string | null
          display_order: number | null
          month_start: string | null
        }
        Relationships: []
      }
      points_leaderboard_current_month: {
        Row: {
          current_level: number | null
          display_name: string | null
          is_current_user: boolean | null
          leaderboard_rank: number | null
          points: number | null
        }
        Relationships: []
      }
      points_leaderboard_last_month: {
        Row: {
          current_level: number | null
          display_name: string | null
          is_current_user: boolean | null
          leaderboard_rank: number | null
          points: number | null
        }
        Relationships: []
      }
      points_leaderboard_total: {
        Row: {
          current_level: number | null
          display_name: string | null
          is_current_user: boolean | null
          leaderboard_rank: number | null
          points: number | null
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
      cast_jury_vote:
        | { Args: { p_candidate_id: string; p_vote: string }; Returns: Json }
        | {
            Args: {
              p_candidate_id: string
              p_review_note: string
              p_vote: string
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
      create_admin_candidate_exclusion: {
        Args: {
          p_ends_at: string
          p_reason: string
          p_starts_at: string
          p_user_id: string
        }
        Returns: string
      }
      create_manual_admin_term: {
        Args: { p_ends_at: string; p_reason: string; p_user_id: string }
        Returns: string
      }
      deduct_user_quota: { Args: { user_id_param: string }; Returns: boolean }
      end_admin_term: {
        Args: { p_reason: string; p_term_id: string }
        Returns: boolean
      }
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
      get_current_admin_capabilities: { Args: never; Returns: Json }
      get_jury_review_queue: { Args: never; Returns: Json }
      get_jury_review_queue_with_evidence: { Args: never; Returns: Json }
      get_my_correction_requests: { Args: never; Returns: Json }
      get_my_feature_requests: { Args: never; Returns: Json }
      get_my_level_benefits: { Args: never; Returns: Json }
      get_my_rejected_clothing_submissions: {
        Args: never
        Returns: {
          can_resubmit: boolean
          category: string
          game_id: string
          name: string
          pending_id: number
          reason: string
          rejected_at: string
        }[]
      }
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
      leave_current_admin_term: { Args: never; Returns: boolean }
      list_admin_governance: { Args: never; Returns: Json }
      list_feature_requests: {
        Args: { p_filter?: string; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      list_feature_requests_for_admin: { Args: never; Returns: Json }
      list_low_risk_clothes_review_candidates: { Args: never; Returns: Json }
      list_pending_suits_for_review: {
        Args: never
        Returns: {
          first_created_at: string
          name: string
          request_count: number
        }[]
      }
      moderate_feature_request: {
        Args: {
          p_action: string
          p_duplicate_of?: string
          p_public_response?: string
          p_reason: string
          p_request_id: string
        }
        Returns: Json
      }
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
      review_low_risk_clothes_candidate: {
        Args: {
          p_action: string
          p_reason?: string
          p_representative_pending_id: number
        }
        Returns: Json
      }
      review_pending_suit: {
        Args: { p_decision: string; p_name: string }
        Returns: Json
      }
      revoke_admin_candidate_exclusion: {
        Args: { p_exclusion_id: string }
        Returns: boolean
      }
      route_correction_request_to_jury: {
        Args: { p_request_id: string }
        Returns: string
      }
      set_feature_request_like: {
        Args: { p_liked: boolean; p_request_id: string }
        Returns: Json
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
      submit_feature_request: {
        Args: { p_description: string; p_title: string }
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
      withdraw_feature_request: {
        Args: { p_request_id: string }
        Returns: Json
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
