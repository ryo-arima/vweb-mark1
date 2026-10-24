# 運用・非機能要件

## セキュリティ制御

- 信頼されないクライアントへ公開するアプリケーションルートはOpenRestyだけとする。
- Keycloakの`master` RealmとAdmin Consoleを公開ルートから除外する。
- OpenRestyでプロキシヘッダーを上書きし、クライアント値をそのまま転送しない。
- OIDCの`state`、`nonce`、PKCE、issuer、audience、token timestampを検証する。
- Secure、HttpOnly、SameSite Cookieを利用し、ブラウザへtokenを保存しない。
- OpenRestyでリクエストサイズ、HTTPメソッド、許可プロキシパスを制限する。
- CA鍵、サービス鍵、クライアント鍵の権限を制限する。
- 証明書期限、更新失敗、CA到達性を監視する。
- token、Cookie、パスワード、秘密鍵、完全な証明書をログに出力しない。

## 非機能目標

| 項目 | 初期目標 |
|---|---|
| 可用性 | 単一ホストCompose。HAは対象外 |
| 性能 | 静的ファイルはOpenRestyが配信し、API処理は選択されたサービスのbackが担当 |
| 拡張性 | ドメインロジックをHTTP・認証アダプターから分離 |
| 監査性 | 必要に応じてrequest ID、ユーザーsubject、端末証明書シリアルを記録 |
| 運用性 | コンテナログをstdout/stderrへ出力しCompose logsで収集 |
| バックアップ | PostgreSQL、step-ca、発行済み証明書を分けてバックアップ |
| 開発環境 | Apple Siliconなどのため`DOCKER_PLATFORM`を上書き可能にする |

## 初回構築手順

予定する利用手順は次のとおり。

```bash
cp .env.example .env
make compose-config
make up
make logs
```

初回起動では次を実施する。

1. `.env`へDBパスワード、BFF session DB password、Keycloak管理者値、BFF client secret、session encryption key、サンプルユーザーパスワード、truststoreパスワード、step-ca bootstrapパスワード、開発用mail address/passwordを投入する。
2. step-caを初期化し、CA fingerprintを記録する。
3. `make up`を実行する。その`make init-pki` stepで、専用init containerを作成せずにOpenRestyとKeycloakのサーバー証明書、およびOpenRestyのクライアント証明書を発行する。
4. KeycloakへRealm、Client、ロールをimportする。
5. 許可済み開発端末へstep-ca root証明書とクライアント証明書をインストールする。
6. Keycloakと各サービスのサンプルデータを確認する。`seed-keycloak` targetが`sample-user-01`から`sample-user-20`を作成し、`migrate` targetがサービスSQLを適用する。ローカルの認証情報一覧が必要な場合は`make user-passwords`を実行する。gitignore対象の`private/keycloak/user-passwords.txt`へ`0600`で出力され、各sample userのservice、Group、Role access patternも含む。`sample-user-01`から`sample-user-10`はメールアドレス確認済み、`sample-user-11`から`sample-user-20`は未確認である。Service Aの全体管理画面を試す場合は`sample-user-01`、`sample-user-02`、`sample-user-04`、Service Bは`sample-user-01`、`sample-user-03`、`sample-user-05`を利用する。
7. `make up`が`make init-mailserver`を通じて開発用mail accountを作成または更新する。その後、`http://127.0.0.1:3005/`でRoundcubeを開く。mail UIはOpenRestyから独立する。
8. OpenResty経由で`/service-a/`または`/service-b/`を開く。ブラウザは最初にクライアント証明書を提示し、その後Keycloakへログインする必要がある。OpenRestyはOIDC sessionをPostgreSQLへ不透明な形式で保存し、その後にだけBFF生成の認証ヘッダー付きでAPI requestを転送する。ログイン状態は`/auth/session`で確認し、`/auth/logout`で削除する。

ブラウザから`vweb.local`を解決できるよう、アクセス前にhostsへ開発用ドメインを追加する。

```bash
echo '127.0.0.1 vweb.local' | sudo tee -a /etc/hosts
```

OpenRestyのホスト待受は80と443だけである。80番はHTTPSへredirectし、Keycloakとserviceのfront/back containerはOpenResty proxy経由で到達する。`127.0.0.1:9443`のKeycloak portはMake targetのbootstrap専用であり、独立したRoundcube UIは`http://127.0.0.1:3005/`に残る。

ブラウザから`vweb.local`を解決できるよう、アクセス前にhostsへ開発用ドメインを追加する。

```bash
echo '127.0.0.1 vweb.local' | sudo tee -a /etc/hosts
```

OpenRestyのホスト待受は80と443だけである。80番はHTTPSへredirectし、Keycloakとserviceのfront/back containerはOpenResty proxy経由で到達する。`127.0.0.1:9443`のKeycloak portはMake targetのbootstrap専用であり、独立したRoundcube UIは`http://127.0.0.1:3005/`に残る。

サービスbackはCompose network内で`/healthz`、`/readyz`、`/v1/identity`、`/v1/authorization/decision`と、data designで定義したGroup/Member管理routeを公開する。サービス管理者専用の`GET /v1/members`は全Groupを横断するMembers一覧を提供する。管理requestにはBFFが生成した`X-User-Sub`、`X-User-Roles`、`X-User-Groups` headerが必要である。これらはhostへ公開せず、OIDCログイン後の`/api/service-a/v1/*`または`/api/service-b/v1/*`からだけ利用する。

サービス管理者向けAPIはJSON契約である。例えば`POST /api/service-a/v1/groups`へ`{"name":"reviewers","description":"Review team"}`を送りGroupを作成する。既存Keycloak subjectを`POST /api/service-a/v1/groups/<group-id>/members`へ`{"keycloak_sub":"<subject>","email":"user@example.test","role_names":["group-viewer"]}`として送る。emailは必須で、既存Keycloak Userのemailと一致しなければならない。同じemailが登録済みの場合はHTTP 409を返し、同じUserを別Groupへ追加することは許可する。backがmTLSでKeycloak Admin APIを呼び出し、サービス固有の詳細をPostgreSQLへ保存する。

証明書交換では、計画されたCAローテーションを除き、既存のCA信頼チェーンを維持する。

ホスト側bootstrap targetにはDocker、`curl`、`jq`、`keytool`が必要である。これらは起動済みのPostgreSQLとstep-caコンテナを通じてスクリプトを実行するため、初期化やmigrationによって永続またはone-shotのコンテナはCompose projectへ追加されない。

### macOSへのブラウザ用クライアント証明書登録

`make up`でserviceがhealthyになった後、生成されたクライアント証明書をmacOSのlogin keychainへ登録する。

```bash
security add-trusted-cert \
  -d -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db \
  private/pki/ca/root_ca.crt

read -r -s -p "PKCS#12 password: " P12_PASSWORD
printf "\n"
export P12_PASSWORD
openssl pkcs12 -export \
  -out private/pki/openresty/vweb-client.p12 \
  -inkey private/pki/openresty/client.key \
  -in private/pki/openresty/client.crt \
  -certfile private/pki/ca/root_ca.crt \
  -name vweb-client \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -macalg sha1 \
  -passout env:P12_PASSWORD
security import \
  private/pki/openresty/vweb-client.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD"
unset P12_PASSWORD
```

PKCS#12 passwordはbundleの保護用である。Chromeがprivate keyの利用を求める場合は、PKCS#12 passwordではなくmacOSの`login` keychain passwordを入力する。証明書subjectとして`openresty-client`が表示されたらそれを選択し、Chromeからの鍵利用を許可する。SHA-1／3DES optionは、OpenSSL 3の既定PBES2／AES形式を拒否するmacOS Security.frameworkとの互換性のために指定する。

### 初回アクセスとライフサイクル

ホストからmTLSを確認した後、ブラウザで次のrouteを開く。

```bash
curl --cacert private/pki/ca/root_ca.crt \
  --cert private/pki/openresty/client.crt \
  --key private/pki/openresty/client.key \
  https://vweb.local/service-a/
```

- アプリケーション入口：`https://vweb.local/`（Service Aへredirect）
- Service A：`https://vweb.local/service-a/`
- Service B：`https://vweb.local/service-b/`
- 独立Roundcube：`http://127.0.0.1:3005/`

ブラウザでアプリケーション入口またはサービス画面を開くときは、証明書選択画面で
登録済みの`openresty-client`を選択する。その後Keycloakへredirectされるため、
`sample-user-01`または`sample-user-01@vweb.local`と`KEYCLOAK_SAMPLE_USER_PASSWORD`でログインする。未確認メールの動作を試す場合は`sample-user-11@vweb.local`を使い、Keycloakがmailserverへ送信した確認メールを`http://127.0.0.1:3005/`のRoundcubeで対応するsample mailboxから確認する。OIDC callbackが成功した後にだけBFF session cookieが発行される。

設定した`VWEB_MAIL_ADDRESS`と`VWEB_MAIL_PASSWORD`で開発用mailboxへログインする。mail UIはOpenRestyから独立している。

永続データを維持して停止・再構築する場合は`make down`と`make up`を使う。通常の開発で`docker compose down -v`を実行してはならない。

## GitHub Pages公開

`.github/workflows/docs.yml`は1つの多言語mdBookをビルドし、1つのPages artifactへまとめる。

- `/en/`は英語版
- `/jp/`は日本語版
- `/`は両言語へのリンクを表示し、英語版へリダイレクトする

Pull Requestでは両方のビルドだけを実行し、デプロイしない。`main`へのpushと手動実行では、`github-pages` environmentを通してデプロイする。リポジトリ設定のPagesのSourceは**GitHub Actions**に設定する。

## 検証方針

各実装段階で成功経路と拒否経路を検証する。

- Compose設定が正常に解決される。
- サービスが定義された順序で起動する。
- 信頼されない、または存在しないクライアント証明書が拒否される。
- OpenRestyが信頼されないKeycloakサーバー証明書を拒否する。
- KeycloakがOpenRestyクライアント証明書なしの接続を拒否する。
- OIDC callbackが不正なstate、nonce、PKCEを拒否する。
- 期限切れセッションが各サービスのbackへ到達できない。
- 権限のないロールが保護されたendpointへアクセスできない。
- クライアント送信の認証ヘッダーがBFF生成値を上書きできない。

