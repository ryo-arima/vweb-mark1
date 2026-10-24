# Docker Compose環境

## Composeファイル構成

`cmn-core`方式に従い、サービス単位のYAML断片を作成し、Makefileで統合する。

```text
docker/
├── network.yaml        # vweb-network
├── postgres.yaml       # PostgreSQL, bootstrap SQL, and healthcheck
├── step-ca.yaml        # step-ca and CA data volume
├── keycloak.yaml       # Keycloak, realm import, and TLS settings
├── openresty.yaml      # OpenResty, BFF, and Vue delivery
├── dns.yaml             # Independent mail DNS sandbox
├── mailserver.yaml      # Independent docker-mailserver sandbox
├── roundcube.yaml       # Independent Roundcube mail UI
├── service-a.yaml       # service-a front/back application services
└── service-b.yaml       # service-b front/back application services
```

初期インフラ用Composeでは最初の5つを基盤断片として扱い、アプリケーションと独立mail stackの断片を同じMakefileで統合する。

```makefile
ENV_FILE ?= .env
COMPOSE_FILES := \
  -f docker/network.yaml \
  -f docker/postgres.yaml \
  -f docker/step-ca.yaml \
  -f docker/keycloak.yaml \
  -f docker/openresty.yaml \
  -f docker/dns.yaml \
  -f docker/mailserver.yaml \
  -f docker/roundcube.yaml \
  -f docker/service-a.yaml \
  -f docker/service-b.yaml
COMPOSE := docker compose --env-file $(ENV_FILE) --project-directory . $(COMPOSE_FILES)

up: check-env host-tools
	$(COMPOSE) up -d --build --remove-orphans --wait postgres step-ca dns service-a-front service-b-front
	$(COMPOSE) up -d --build mailserver
	$(MAKE) init-mailserver
	$(MAKE) init-pki
	$(COMPOSE) up -d --build --wait keycloak
	$(MAKE) seed-keycloak
	$(MAKE) migrate
	$(MAKE) init-roundcube
	$(COMPOSE) up -d --build --wait service-a-back service-b-back roundcube openresty
```

`make up`をコンテナ作成の標準入口とする。リポジトリの`.env.example`から作成したローカル`.env`を要求し、ローカルimageをbuildし、統合済みCompose projectを起動する。初期化とmigrationのスクリプトは起動済みの常駐コンテナに対してMake targetから実行し、専用のone-shot Compose containerは作成しない。

## 起動順序

```text
postgresとstep-caがhealthy
       ↓
make init-postgres / sync-postgres-roles (host script)
       ↓
make init-mailserver (host script)
       ↓
make init-pki (host script)
       ↓
keycloak healthy
       ↓
make seed-keycloak (host script)
       ↓
make migrate (host script)
       ↓
make init-roundcube (host script)
       ↓
service-a/back, service-b/back, roundcube, openresty healthy

service-a-front、service-b-front、dnsは最初の段階で起動する。mailserverは`make init-mailserver`の前に起動し、Dovecotの起動完了前に初期アカウントを作成する。
```

`make init-pki`は起動済みの`step-ca`コンテナ経由で証明書スクリプトを実行し、ホスト上でKeycloak用の派生PKCS#12 truststoreを作成して永続PKI volumeへコピーする。CAデータを所有せず、起動のたびに新しいroot CAを生成してはならない。`make seed-keycloak`はloopback限定のKeycloak bootstrap port経由で、冪等なRealm／Group／User seed scriptをホスト上から実行する。

Composeが対応する場合は`depends_on`のhealth条件を利用する。

- KeycloakはPostgreSQLを待つ。`make up`はKeycloak起動前にPKIを準備する。
- OpenRestyはKeycloakのreadinessと証明書を待つ。
- OpenRestyは`service-a-front`、`service-b-front`の静的ファイルhealth check完了を待つ。
- `dns`、`mailserver`、`roundcube`はOpenRestyから独立する。mail stackは`vweb-mail-network`と`vweb.local`ドメインを利用する。
- `make init-mailserver`は`VWEB_MAIL_ADDRESS`と`VWEB_MAIL_PASSWORD`から開発用mailboxを作成または更新し、`KEYCLOAK_SAMPLE_USER_PASSWORD`で20個のサンプルmailboxも作成する。docker-mailserverはDovecot起動前に最低1件のaccountを要求する。
- Keycloakはローカルのメール確認メッセージを`mailserver`へ送信するためだけにmail networkへ参加する。ブラウザからmailへ接続する経路はloopback限定のRoundcube UIである。
- `make migrate`はサービスback起動前にhealthyなPostgreSQLコンテナへ各サービスmigrationを適用する。
- `make init-roundcube`はRoundcube起動前にhealthyなPostgreSQLコンテナへRoundcube roleとdatabaseを作成する。

現在のサービスmigrationは、各back配下の`001_authorization.sql`、`002_sample_data.sql`、`003_management.sql`、`004_sample_access_patterns.sql`、`005_user_email_constraints.sql`である。3番目のmigrationでGroup description、Keycloak投影ID、管理用indexを追加し、4番目のmigrationでdata designの明示的なaccess matrixへ生成sampleのMemberとMemberRoleを収束させる。5番目のmigrationでUserのemailを空不可とし、大文字小文字を区別しない一意indexを追加する。制約追加前に旧形式の重複User投影も統合する。User、Group、Role、Policy、Member、MemberRoleのサービス単位テーブルを作成する。各migrationはサービスごとに20ユーザーと5グループのサンプルデータも投入する。

`make seed-keycloak`は`vweb` Realmへ同じ20ユーザーを作成し、各サービス配下に5グループを作成する。サービス／GroupのClient Role mappingと、data designで定義したservice、Group、cross-service、multi-role、所属なしのpatternを設定する。さらに`service-a-api`と`service-b-api`のservice-account clientを作成し、backの投影clientに必要なAdmin API roleだけを付与する。各サービスbackには`/pki/service-a`または`/pki/service-b`の専用mTLS client certificateを渡す。サンプルユーザーのパスワードは`KEYCLOAK_SAMPLE_USER_PASSWORD`から読み込み、リポジトリには保存しない。
サンプルメールアドレスは`sample-user-01@vweb.local`から`sample-user-20@vweb.local`であり、前半10件を確認済み、後半10件を未確認として作成する。Keycloakはメールアドレスログイン、重複メール拒否、mailserver経由の確認メールを有効にする。サービスのMember作成でも、既存Keycloak Userのemailと一致する入力を必須とする。
ローカルで認証情報の一覧が必要な場合は`make user-passwords`を実行する。Keycloak bootstrap administratorと`vweb`の20サンプルユーザーを含む一覧を、gitignore対象の`private/keycloak/user-passwords.txt`へTSV形式で出力する。ファイル権限は`0600`であり、公開や本番での再利用は禁止する。

## ローカル起動

```bash
cp .env.example .env
# 起動前に.envのplaceholderをすべて置き換える。
echo '127.0.0.1 vweb.local' | sudo tee -a /etc/hosts
make compose-config
make up
```

初回checkoutからの詳しい手順と、ブラウザへクライアント証明書を
インストールする手順は、[初回構築手順](operations.md#初回構築手順)を参照する。

`.env`へ`VWEB_MAIL_ADDRESS`と`VWEB_MAIL_PASSWORD`を設定する。`make up`はmail stackの残りを待つ前にmailboxを作成または更新する。

常駐stackが起動済みの場合は、個別に`make init-postgres`、`make sync-postgres-roles`、`make init-mailserver`、`make init-pki`、`make seed-keycloak`、`make migrate`、`make init-roundcube`を実行できる。seed targetにはホスト上の`curl`、`jq`、`keytool`が必要である。

OpenRestyのホスト待受は80と443だけである。80番はcanonical URLである`https://vweb.local`へredirectする。サービス画面、API route、KeycloakへのOIDC proxyはHTTPSのOpenResty入口を経由し、application containerはホストへ公開しない。OpenRestyは、まず許可されたクライアント証明書を要求し、その後サービス画面にKeycloak OIDC sessionを要求する。`/`は認証後に`/service-a/`へredirectし、`/auth/login`がPKCE付きAuthorization Code Flowを開始する。同じPostgreSQL-backed BFF sessionが存在するまでAPI routeは`401`を返す。独立したRoundcubeは`http://127.0.0.1:3005/`、サービス画面は`/service-a/`と`/service-b/`で確認できる。

OpenRestyはKeycloakとserviceのfront／back container名をDocker組み込みDNSでrequestごとに解決し、短いcache windowだけ保持する。proxy locationは転送前に公開path prefixを取り除く。これによりcontainerを再作成してIP addressが変わってもproxy先を維持できる。相当するreload strategyなしにstaticなupstream addressを設定してはならない。

## 開発用ポート

| サービス | コンテナポート | 開発ホスト公開 | 方針 |
|---|---:|---|---|
| OpenResty | 80/443 | `80:80`、`443:443` | 公開アプリケーション入口はこれだけ。80番はHTTPSへredirect |
| step-ca | 9000 | `127.0.0.1:9000:9000` | 証明書bootstrap／発行用 |
| Keycloak | 8443 | `127.0.0.1:9443:8443` | loopback限定のbootstrap／seed用。公開アクセスはOpenResty経由 |
| PostgreSQL | 5432 | 原則非公開。必要時はloopback | DBツール／マイグレーション用 |
| `service-a/back` | 8000 | 公開しない | OpenRestyからのみ到達 |
| `service-b/back` | 8000 | 公開しない | OpenRestyからのみ到達 |
| `service-a/front` | 80 | 公開しない | OpenRestyからのみ到達 |
| `service-b/front` | 80 | 公開しない | OpenRestyからのみ到達 |
| `roundcube` | 80 | `127.0.0.1:3005:80` | loopback限定の独立mail UI |
| `mailserver` | 25/143/587/993 | 公開しない | 内部mail transportとmailbox service |
| `dns` | 53/8080 | `127.0.0.1:8053:8080` | mail DNS sandboxとlocal diagnostics |

## 永続化

- PostgreSQLは`postgres-data` named volumeを利用する。
- step-caは`step-ca-data` named volumeを利用する。
- docker-mailserverはPostfixとDovecotのruntime stateに`vweb-mail-state` named volumeを利用する。生成されたaccount hashはgitignore対象の`private/mailserver`へ保存し、開発用mailboxの内容とmail logは一時データのままとする。
- 発行済み証明書はGit管理外の`private/pki`ホストディレクトリへ保存する。`make prepare-pki-data`が作成し、利用側にはread-onlyでマウントする。
- CA秘密鍵とDBデータは通常のコンテナ再起動後も維持する。
- KeycloakとOpenRestyへ証明書・秘密鍵を可能な限りread-onlyでマウントする。

## ヘルスチェック

- PostgreSQL：必要なDBに対して`pg_isready`を実行する。
- step-ca：health endpointまたは同等のCA healthコマンドを利用する。
- Keycloak：内部HTTPSのhealth/readiness endpointを確認する。
- OpenResty：内部`/healthz`とupstream・信頼チェーンファイルを確認する。
- 各サービスのback：プロセスlivenessとDB接続を含むreadinessを分ける。

## 設定と秘密情報

`.env.example`には変数名、安全な例、説明だけを記載する。実値は`.env`またはsecretファイルから注入する。次をコミットしてはならない。

- PostgreSQLパスワード
- Keycloak Client secret
- セッション暗号化鍵
- step-ca provisionerパスワード
- 秘密鍵や発行済み証明書

開発専用パスワードを本番で再利用しない。

