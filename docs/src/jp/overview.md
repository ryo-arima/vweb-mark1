# 概要

[English documentation](../en/) | 日本語

## 文書情報

| 項目 | 内容 |
|---|---|
| 文書名 | vweb-mark1 基本設計 |
| 版数 | 0.2（Draft） |
| 日付 | 2026-10-24 |
| 言語 | 日本語 |
| 対象 | Webアプリケーションおよびローカル／開発実行基盤 |
| 参考方式 | `cmn-core`方式のCompose分割 |

## 目的

`vweb-mark1`は複数サービスで構成するWebアプリケーションである。各サービスはVite + VueのfrontとVのbackを持ち、OpenRestyをBFF（Backend for Frontend）として選択されたサービスのbackへリクエストをルーティングする。

KeycloakをOIDC認証およびロール管理の認証基盤とする。step-caをサービス証明書・クライアント証明書を発行するプライベート認証局とする。PostgreSQLには、認証基盤データ、BFFセッション、業務データを保存する。

## 認証モデル

端末・通信路の認証と、利用者の認証を分離する。

1. step-caが発行したクライアント証明書で、接続元端末がOpenRestyへ接続可能であることを確認する。
2. KeycloakによるOIDCログインで利用者の本人性とロールを確認する。
3. BFFがアプリケーションセッションを作成し、正規化した認証コンテキストを選択されたサービスのbackへ渡す。

クライアント証明書が有効であるだけでは、業務APIを利用できない。

## 対象範囲

### 対象

- 各サービスのVによるサービスロジックとアプリケーション境界
- 各サービスのVue 3によるWeb UI
- サービスごとのVue 3 Web UIと独立したRoundcube mail UI
- OpenRestyによるTLS終端、mTLS、OIDC BFF、静的ファイル配信、APIルーティング
- KeycloakによるOIDC、ユーザー、Realm、Client、ロール管理
- step-caによる証明書発行と更新
- Keycloak、BFF、業務データを保存するPostgreSQL
- 初期インフラを構築するDocker Compose

### 対象外

- 業務ドメイン固有の画面、テーブル、API詳細
- 本番HA、ロードバランサー、クラウド固有のデプロイ
- 外部端末への証明書配布運用
- Keycloak Admin Consoleの公開運用

## Compose対象サービスの解釈

Docker Composeで構築する4つのインフラサービスは次のとおりとする。

- Keycloak
- OpenResty
- step-ca
- PostgreSQL

各サービスのfrontとbackはアプリケーションコンポーネントとして定義する。プラットフォームの`main` Web UIは内部ComposeコンポーネントとしてOpenResty経由で到達させる。Roundcube mail UI、mail server、DNSはloopbackを中心とする独立Composeコンポーネントとし、OpenResty/BFF境界の外側に置く。

