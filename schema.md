# schema

| 表名            | 字段名        | 数据类型                 | 默认值                       | 能否为空 |
| --------------- | ------------- | ------------------------ | ---------------------------- | -------- |
| clothes         | id            | character varying        | null                         | NO       |
| clothes         | created_at    | timestamp with time zone | now()                        | NO       |
| clothes         | name          | text                     | null                         | YES      |
| clothes         | category      | text                     | null                         | YES      |
| clothes         | stars         | text                     | null                         | YES      |
| clothes         | tags          | text                     | null                         | YES      |
| clothes         | scores        | jsonb                    | null                         | YES      |
| clothes         | game_id       | text                     | null                         | YES      |
| clothes         | suit_id       | uuid                     | null                         | YES      |
| pending_clothes | id            | bigint                   | null                         | NO       |
| pending_clothes | created_at    | timestamp with time zone | now()                        | NO       |
| pending_clothes | name          | text                     | null                         | YES      |
| pending_clothes | category      | text                     | null                         | YES      |
| pending_clothes | stars         | integer                  | null                         | YES      |
| pending_clothes | scores        | jsonb                    | null                         | YES      |
| pending_clothes | tags          | text                     | null                         | YES      |
| pending_clothes | suit_name     | text                     | null                         | YES      |
| pending_clothes | game_id       | text                     | null                         | YES      |
| pending_clothes | status        | text                     | 'pending'::text              | YES      |
| pending_clothes | submitted_by  | uuid                     | null                         | YES      |
| pending_clothes | suit_id       | uuid                     | null                         | YES      |
| pending_suits   | id            | uuid                     | gen_random_uuid()            | NO       |
| pending_suits   | name          | text                     | null                         | NO       |
| pending_suits   | submitted_by  | uuid                     | null                         | YES      |
| pending_suits   | status        | text                     | 'pending'::text              | YES      |
| pending_suits   | created_at    | timestamp with time zone | now()                        | YES      |
| profiles        | id            | uuid                     | null                         | NO       |
| profiles        | email         | text                     | null                         | YES      |
| profiles        | nickname      | text                     | null                         | YES      |
| profiles        | role          | text                     | 'user'::text                 | YES      |
| profiles        | quota         | integer                  | 30                           | YES      |
| profiles        | updated_at    | timestamp with time zone | now()                        | YES      |
| profiles        | created_at    | timestamp with time zone | timezone('utc'::text, now()) | YES      |
| stages          | id            | bigint                   | null                         | NO       |
| stages          | created_at    | timestamp with time zone | now()                        | NO       |
| stages          | name          | text                     | null                         | YES      |
| stages          | weights       | jsonb                    | null                         | YES      |
| suits           | id            | uuid                     | gen_random_uuid()            | NO       |
| suits           | name          | text                     | null                         | NO       |
| suits           | description   | text                     | null                         | YES      |
| suits           | source        | text                     | null                         | YES      |
| suits           | created_at    | timestamp with time zone | now()                        | YES      |
| user_quotas     | user_id       | uuid                     | null                         | NO       |
| user_quotas     | free_count    | integer                  | 20                           | YES      |
| user_wardrobes  | id            | uuid                     | gen_random_uuid()            | NO       |
| user_wardrobes  | created_at    | timestamp with time zone | now()                        | NO       |
| user_wardrobes  | user_id       | uuid                     | gen_random_uuid()            | YES      |
| user_wardrobes  | owned_clothes | jsonb                    | null                         | YES      |