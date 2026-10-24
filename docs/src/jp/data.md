# データ設計

## データベース分離

Keycloakとアプリケーションが互いのテーブル所有権を持たないよう、PostgreSQLに論理データベースとユーザーを分けて配置する。

| DB | 所有者 | 内容 |
|---|---|---|
| `keycloak` | `keycloak` | Realm、Client、ユーザー、ロール、Keycloakセッション |
| `vweb` | `service_a`と`service_b` schema | BFFセッション、サービス単位の業務テーブル、監査データ |
| `roundcube` | `roundcube` | Roundcube identity、preference、mailbox metadata |

各サービスのbackは、サービススコープのUser、Group、Role、Policy、Memberレコードを所有する。初期段階では`vweb` DBを共有してよいが、schemaまたはtable prefixでサービス所有境界を分け、サービスAPIで強制する。あるサービスが他サービスの認可テーブルを直接変更してはならない。

初期SQLはDB、ユーザー、schema、必要最小限の接続権限を作成し、PostgreSQLコンテナへread-onlyでマウントする。既存PostgreSQL volumeがmail UI追加前に作成された場合も、冪等な`make init-roundcube` targetがRoundcube roleとdatabaseを作成する。サービスmigrationは`make migrate`でPostgreSQL bootstrapとは分離して実行し、専用migration containerは作成しない。
既存volumeに対しても`make init-postgres`でbootstrapを再実行でき、`make sync-postgres-roles`が現在のローカル`.env`値へアプリケーションroleのパスワードを同期する。

## BFFセッションテーブル

初期の論理モデルは次のとおりとする。

| カラム | 内容 |
|---|---|
| `session_id` | 推測困難なランダムID。主キー |
| `user_sub` | Keycloak subject |
| `access_token_enc` | 暗号化済みアクセストークン |
| `refresh_token_enc` | 暗号化済みリフレッシュトークン |
| `expires_at` | セッション／tokenの有効期限 |
| `created_at` | 作成日時 |
| `last_seen_at` | 最終利用日時 |

ブラウザへ渡すBFF Cookieには`session_id`だけを含める。token暗号化鍵はリポジトリ外からsecretとしてマウントする。期限切れ行を削除し、logout時にはサーバー側セッションを無効化する。

## サービス認可エンティティ

| Entity | 必須項目 | 用途 |
|---|---|---|
| User | `id`、`keycloak_sub`、空でない一意な`email`、profile参照、日時 | ローカル認証情報投影 |
| Group | `id`、`parent_group_id`、`name`、`path`、`description`、`keycloak_id`、日時 | サービス単位の階層GroupとKeycloak投影参照 |
| Role | `id`、`service_id`、`name`、capability定義、日時 | 名前付きサービス権限集合 |
| Policy | `id`、`service_id`、resource、action、effect、condition | 認可ルール |
| Member | `id`、`group_id`、`user_id`、日時 | UserのGroup所属 |
| MemberRole | `member_id`、`role_id`、日時 | Group MemberへのRole割当 |

これらのレコードはサービスbackが正規管理する。KeycloakのGroup pathとUser/Group membershipは認証コンテキストを提供する投影である。サービスrepositoryはmTLSでKeycloak Admin APIを呼び出し、サービス固有のdescription、profile、member roleはPostgreSQLで管理する。Memberまたは子Groupが残っているGroupの削除は拒否し、Member削除でKeycloak User自体を削除しない。

初期管理endpointは次のとおりである。

| Method | Path | 動作 |
|---|---|---|
| `GET` | `/v1/groups` | PostgreSQLからサービスGroupを一覧する |
| `POST` | `/v1/groups` | PostgreSQLとKeycloakの`/services/<service>/groups`配下へGroupを作成する |
| `PATCH`、`DELETE` | `/v1/groups/:group_id` | 両方の投影を更新または削除する |
| `GET`、`POST` | `/v1/groups/:group_id/members` | 既存Keycloak Userを一覧またはサービスGroupへ追加する |
| `GET` | `/v1/members` | サービス全体のMemberを一覧する。サービス管理者専用 |
| `GET`、`PATCH`、`DELETE` | `/v1/members/:member_id` | 詳細参照、profile/role更新、Group membership削除を行う |

Member作成には既存のKeycloak subjectと空でないemailが必要であり、入力emailはKeycloak Userのemailと一致しなければならない。サービス所有のUser投影には空または重複したemailを登録できず、一意性は大文字小文字を区別しない。同じKeycloak Userを複数Groupへ追加することは許可するが、既存emailを別Userへ登録することは拒否する。Emailとdisplay nameの更新は先にKeycloakを呼び出し、その後サービス所有のPostgreSQL User投影を更新する。Member requestのrole名はサービスのPostgreSQL `roles` tableから解決する。

## 開発用サンプルデータ

Makefileのseed処理は非本番用データを作成する。

| スコープ | ユーザー | Group | 内容 |
|---|---:|---:|---|
| Keycloak `vweb` Realm | 共通20 | `service-a`配下5、`service-b`配下5 | service-adminとgroup-admin/editor/viewerのmapping |
| `service_a` schema | 20 | 5 | User、Group、Role、Policy、Member、MemberRole |
| `service_b` schema | 20 | 5 | User、Group、Role、Policy、Member、MemberRole |

ユーザー名は`sample-user-01`から`sample-user-20`を利用し、対応するメールアドレスは`sample-user-01@vweb.local`から`sample-user-20@vweb.local`とする。前半10件をメールアドレス確認済み、後半10件を未確認としてseedする。パスワードは`KEYCLOAK_SAMPLE_USER_PASSWORD`から実行時に注入し、`.env`には開発専用の値を設定する。seed処理は冪等であり、本番credentialで有効化してはならない。

サンプルaccess matrixは、サービス全体、Group scope、サービス横断、複数Group、複数Role、所属なしのパターンを意図的に含む。

| ユーザー | サンプルaccess pattern |
|---|---|
| `01` | `platform-admin`、両サービスのservice administrator |
| `02` | `service-a-admin` |
| `03` | `service-b-admin` |
| `04` | service A administrator、service B group-a viewer |
| `05` | service B administrator、service A group-b editor |
| `06` | Aのgroup-a administrator、Bのgroup-b administrator |
| `07` | Aのgroup-a editor、Bのgroup-b editor |
| `08` | Aのgroup-a viewer、Bのgroup-b viewer |
| `09` | Aのgroup-b administratorとgroup-c viewer、Bのgroup-c administrator |
| `10` | Aのgroup-b editor、Bのgroup-b viewer |
| `11` | Aのgroup-c viewer、Bのgroup-d viewer、未確認メール |
| `12` | Aのgroup-c editor、Bのgroup-c administrator、未確認メール |
| `13` | Aのgroup-d administrator、Bのgroup-e editor、未確認メール |
| `14` | Aのgroup-d editor、Bのgroup-e viewer、未確認メール |
| `15` | Aのgroup-e viewer、Bのgroup-a editor、未確認メール |
| `16` | Aのgroup-aとBのgroup-bでadministratorとeditor、未確認メール |
| `17` | 両サービスのgroup-b viewer、未確認メール |
| `18` | 両サービスのgroup-c editor、未確認メール |
| `19` | 認証済みだがサービス所属なし、未確認メール |
| `20` | Aのgroup-e viewer、Bのgroup-e administrator、未確認メール |

Keycloak seedは生成対象sample userの所属Groupをresetしてからこのmatrixを適用する。サービスmigrationも生成対象のPostgreSQL MemberとMemberRoleを同様にresetするため、既存local環境でも`make seed-keycloak`と`make migrate`を再実行すれば同じdatasetへ収束する。

## 業務データ

業務ドメイン確定まで、エンティティとインデックスは未確定とする。新しいテーブルでは次を定義する。

- 所有者とマイグレーション順序
- 主キーと外部キー
- 監査日時
- 認可スコープ
- 保持期間とバックアップ要件
- 想定クエリとインデックス

## バックアップと復旧

PostgreSQLのデータとstep-caのデータは分けてバックアップする。復旧計画には、次を含める。

- `keycloak` DB
- `vweb` DB
- 復旧後のBFFセッションの扱い
- step-caのroot/intermediate鍵と証明書
- PostgreSQL、step-ca、Keycloak、OpenRestyを復旧する順序

通常の停止操作で`docker compose down -v`を実行しない。永続ボリュームが削除されるためである。

開発用docker-mailserverは`cmn-core`のsandbox方式に従い、mailboxとmail log directoryにtmpfsを利用する。そのため、本番の永続化方針が決まるまでmail contentは一時的である。

