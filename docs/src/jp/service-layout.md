# サービス構成

## 複数サービスモデル

リポジトリは、独立してビルド可能な複数サービスで構成する。各サービスはVue/ViteのフロントエンドとVのバックエンドを持つ。

backの構成は[`cmn-core`](https://github.com/ryo-arima/cmn-core)リポジトリのトップレベル構成に従う。

```text
service-a/
├── front/                  # Vite + Vue application
└── back/                   # V service implementation

service-b/
├── front/                  # Vite + Vue application
└── back/                   # V service implementation
```

追加サービスも`service-<name>/front`と`service-<name>/back`のパターンを利用する。BFFはリクエストされたサービスを所有するbackへルーティングし、各frontは同一オリジンのAPIパスでBFFを呼び出す。

## バックエンド構成

各`back/`は`cmn-core`のトップレベル構成に従う。実装言語はGoからVへ変更するが、ディレクトリの責務は参照リポジトリに合わせる。

```text
service-a/back/
├── cmd/
│   ├── server/
│   │   └── main.v             # Service entry point
│   └── client/                 # Optional service-specific clients
│       ├── admin/
│       ├── anonymous/
│       └── app/
├── pkg/
│   ├── client/                 # Optional client controllers, repositories, and use cases
│   ├── code/                  # Response and message codes
│   ├── config/                # Configuration and external-service settings
│   ├── entity/
│   │   ├── model/             # Persistent and domain models
│   │   ├── request/            # Request DTOs
│   │   └── response/           # Response DTOs
│   ├── global/                # Shared logger and global values
│   └── server/
│       ├── controller/         # HTTP controllers
│       ├── repository/         # PostgreSQL and identity-provider access
│       ├── share/              # Request context, logging, and common server code
│       └── usecase/            # Service use cases
├── docker/                    # Service-specific Compose fragments
├── etc/                       # Example and container configuration
├── scripts/
│   ├── data/                  # Seed and service data
│   └── lib/                   # Shared shell helpers
├── test/
│   ├── e2e/                   # End-to-end tests
│   └── unit/                  # Unit tests and fixtures
├── Dockerfile
├── Makefile
├── README.md
├── VERSION
└── v.mod
```

`service-b/back/`も同じ構成とする。パッケージ名と設定名はサービスごとに分けるが、`cmd`、`pkg`、`docker`、`etc`、`scripts`、`test`の境界はサービス間で統一する。

`cmn-core`にある`go.mod`や`.go`ソースなどGo固有ファイルは、Vの同等ファイルへ置き換える。controller、usecase、repository、entity、config、testの構造的な関係は維持する。

## フロントエンド構成

各`front/`はコンポーネントシステムにVuetify 4を利用するVite + Vueアプリケーションとする。

```text
service-a/front/
├── public/
├── src/
│   ├── api/                  # Same-origin BFF API clients
│   ├── components/           # Reusable Vue components
│   ├── layouts/              # Page layouts
│   ├── router/               # Vue Router configuration
│   ├── stores/               # Client state
│   ├── types/                # TypeScript types
│   ├── views/                # Service screens
│   ├── App.vue
│   └── main.ts
├── index.html
├── package.json
├── tsconfig.json
└── vite.config.ts
```

`service-b/front/`も同じ構成とする。frontからbackへ直接接続せず、アクセストークンをブラウザストレージへ保存しない。OpenRestyがビルド済み静的ファイルを配信し、対応するbackへAPIをルーティングする。

## Mail UI

独立したmail UIは`mailserver`と`dns`のCompose serviceを背後に持つRoundcubeとする。Roundcubeは開発環境で`127.0.0.1:3005`へbindし、OpenRestyを経由せず、vwebアプリケーションネットワークも共有しない。mailドメインは`vweb.local`とする。

## サービスルーティング

初期BFFルート規約は次のとおりとする。

| ルート | 転送先 |
|---|---|
| `/service-a/` | `service-a/front`の静的ファイル |
| `/api/service-a/v1/*` | `service-a/back` |
| `/api/service-a/v1/authorization/decision` | `service-a/back`の認可判定endpoint |
| `/service-b/` | `service-b/front`の静的ファイル |
| `/api/service-b/v1/*` | `service-b/back` |
| `/api/service-b/v1/authorization/decision` | `service-b/back`の認可判定endpoint |
| `/` | BFF認証後に`/service-a/`へredirect |

公開ルート名はプロダクト設計で変更してよいが、各サービスでfrontとbackの所有境界を明確にする。

