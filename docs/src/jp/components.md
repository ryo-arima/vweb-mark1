# コンポーネント設計

## サービスのback

各サービスのbackはサービスロジックを実装し、ブラウザへ直接公開しない。`service-a/back`と`service-b/back`は、`cmn-core`リポジトリを基準にした[サービス構成](service-layout.md)のディレクトリ・レイヤー構造に従う。HTTP固有処理はドメイン、アプリケーション、インフラストラクチャ層から分離する。

現在のHTTP scaffoldはV標準のVebを利用する。PostgreSQL repository境界を`/readyz`から利用し、HTTP adapterへ認証情報を公開せずDB接続性を確認する。各サービスbackは`/healthz`と`/readyz`を分けて公開し、サービスルールをHTTP adapterから分離する。

backのrepositoryはauthorization repository facadeの背後で`psql.v`と`keycloak.v`に分割する。`psql.v`はサービス単位のUser、Group、Member、MemberRoleを所有し、`keycloak.v`はサービス専用のmTLS証明書とservice accountでKeycloak Admin APIを呼び出す。GroupとMemberの変更では、そのAPI経由でKeycloakの投影を更新し、サービス固有の詳細情報はPostgreSQLへ保存する。backがKeycloakのテーブルを直接更新することはない。

管理APIは認証済みCRUDとして`/v1/groups`、`/v1/groups/:group_id/members`、`/v1/members/:member_id`を提供し、サービス管理者専用の`/v1/members`全体一覧も提供する。Vue UIにはVuetifyのnavigation drawerでOverview、Groups、Members画面を用意する。サービス管理者はすべての一覧画面を利用でき、Group単位のユーザーはセッションで許可されたGroupに限定される。

UIはprivileged controlを描画する前にauthorization decision endpointを確認する。Service Groupの作成・編集・削除はサービス管理者だけ、Member変更は選択したGroupを管理できるユーザーだけに表示する。全体Members画面は非サービス管理者のnavigation drawerから隠し、routeを直接開いた場合も説明メッセージを表示する。Member formではemailを必須入力とし、新規Member requestへ送信する。重複emailの場合はAPIのconflictを表示する。これらは操作性のための判定であり、back-end認可の代替ではない。

## Vue UI

- Vue 3を利用する。
- サービスUIにはVuetify 4とVite auto-import pluginを利用する。
- `/api/service-a/v1/...`のような同一オリジンの相対パスでAPIを呼び出す。
- アクセストークンを`localStorage`へ保存しない。
- BFFが発行するHttpOnlyセッションCookieを利用する。
- UIとAPIを同一オリジンで提供し、原則としてCORSを不要にする。

Roundcubeは`mailserver`、`dns`、Roundcube専用PostgreSQL databaseへ接続する独立したthird-party UI containerであり、OpenRestyへ依存しない。サービスUIは`service-a/front`と`service-b/front`をOpenResty経由で配信する。

## OpenResty BFF

OpenRestyのNginxリバースプロキシ機能と、LuaによるOIDC・セッション処理を組み合わせる。

OpenResty imageは、PostgreSQL-backed sessionで使用する`lua-resty-session` 4.x APIと互換性のある`lua-resty-openidc` 1.8.0を固定して利用する。

| ルート | 責務 |
|---|---|
| `/service-a/`、`/service-b/` | サービスごとのVue静的ファイルを配信 |
| `/` | BFF認証後に`/service-a/`へredirect |
| `/auth/login` | OIDC Authorization Code Flowを開始 |
| `/auth/callback` | callbackを検証し、KeycloakとmTLSでコード交換 |
| `/auth/logout` | BFFセッションを削除してアプリケーション入口へ戻す |
| `/auth/session` | UIへログイン状態を返す |
| `/api/service-a/v1/*` | BFFセッションを確認して`service-a/back`へプロキシ |
| `/api/service-b/v1/*` | BFFセッションを確認して`service-b/back`へプロキシ |
| `/healthz` | 内部ヘルスエンドポイント |
| `/auth/realms/*` | OIDCに必要なKeycloakプロトコルパスだけをプロキシ |

ブラウザには不透明なセッションIDだけを返す。アクセストークンとリフレッシュトークンは暗号化してPostgreSQLへ保存する。暗号化鍵はComposeの環境変数へ直接記載せず、secretファイルで注入する。

## Keycloak

- 初期Realm名は`vweb`とする。
- `vweb-bff`などのconfidential BFF Clientを登録する。
- Authorization Code Flow + PKCE（S256）を利用する。
- 明確な要件がない限りDirect Access Grantsを無効化する。
- [Keycloak認可モデル](keycloak-authorization.md)で定義した`platform-admin` Realm Roleとサービス／Group Roleを利用する。
- seed時に`service-a-api`と`service-b-api`のconfidential service-account clientを作成する。secretは`.env`に残し、`manage-users`、`query-clients`、`query-groups`、`query-users`、`view-clients`、`view-users`だけを各サービスのprivate networkから利用する。
- `master` RealmのAdmin ConsoleとAdmin APIを公開OpenRestyルートへ出さない。
- Keycloakの公開URLはOpenRestyのURLとし、内部接続先とは分離する。

全サービス／サービス／グループの権限階層は[Keycloak認可モデル](keycloak-authorization.md)で定義する。Keycloakは認証、粗粒度Role、Group path claimを提供し、各サービスのbackが正規のRole、Policy、Memberレコードを評価する。

## step-ca

step-caをプライベートPKIとし、CAデータを永続化する。初期証明書発行では少なくとも次を作成する。

- 公開開発／本番DNS名をSANに含むOpenRestyサーバー証明書
- 内部Keycloak DNS名をSANに含むKeycloakサーバー証明書
- Keycloakバックエンド接続用のOpenRestyクライアント証明書
- 許可済みブラウザまたはAPIクライアント用の端末証明書

SANとprovisionerポリシーで発行対象を制限する。証明書更新でCAルートを置き換えない。

## PostgreSQL

1つのPostgreSQLインスタンスに、論理データベースとユーザーを分けて配置する。

| DB | 所有者 | 用途 |
|---|---|---|
| `keycloak` | `keycloak` | Keycloak内部データ |
| `vweb` | `service_a`と`service_b` schema | BFFセッションとサービス業務データ |
| `roundcube` | `roundcube` | Roundcube metadataとpreference |

初期SQLは`cmn-core`方式を踏襲する。初回起動時にDBとユーザーを作成し、各所有者には自DBだけを許可する。初期化スクリプトはコンテナへread-onlyでマウントする。独立mail stackでは、既存PostgreSQL volume向けに冪等な`make init-roundcube` targetを利用する。サービスmigrationは専用migration containerではなく、起動済みPostgreSQLコンテナへ`make migrate`から適用する。

