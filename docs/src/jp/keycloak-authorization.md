# Keycloak認可モデル

## 設計目標

権限階層は次のとおりとする。

```text
全サービス管理者（platform-admin）
└── service-a-admin                    # service-b以降も同じ規約
    └── group-a
        ├── グループ管理者（group-admin）
        ├── グループ編集者（group-editor）
        └── グループ閲覧者（group-viewer）
```

開発用seedは各`/groups`配下に`group-a`から`group-e`を作成する。図は代表として`group-a`だけを示している。

サービスごとに同じ階層を独立して適用する。あるユーザーがservice-aでは管理者、service-bでは別グループの閲覧者になることを許可する。

## 責務分担

Keycloakは認証基盤と粗粒度の認証claimを管理する。各サービスのbackは、そのサービスの認可データを正規管理する。

| 概念 | Keycloak表現 | サービスbackの表現 | 正規管理元 |
|---|---|---|---|
| User | Realm userと`sub` | `keycloak_sub`をキーにしたUser投影 | Keycloakの認証情報、サービス側投影 |
| Group | 階層Realm groupと`groups` claim | サービスのGroupレコードと親子関係 | サービスback |
| Role | token context用の固定アプリケーションRole | サービスのRole定義と割当 | サービスback |
| Policy | 必要に応じた粗粒度claim | Resource、action、condition、effect | サービスback |
| Member | 必要時のKeycloak membership投影 | Group所属とRole割当 | サービスback |

これにより、すべてのサービスリソースごとにKeycloak Role・Policyを無制限に増やさずに済む。KeycloakのGroupとRoleは認証コンテキストを提供し、最終的なリソース認可はサービスbackが行う。

## RealmとClient

アプリケーションRealmは`vweb`の1つとする。Keycloakサーバー自体を管理する`master` Realmの`admin` Roleをアプリケーション認可に利用しない。

### Realm Role

| Role | 意味 |
|---|---|
| `platform-admin` | 全サービスに対する管理権限 |

`platform-admin`は`vweb` RealmのアプリケーションRoleであり、Keycloakサーバー管理者Roleとは分離する。

### BFF Client Role

`vweb-bff` Clientには、次の規約でサービス単位のRoleを作成する。

| Client Role | スコープ |
|---|---|
| `service-a-admin` | service-aの管理 |
| `service-b-admin` | service-bの管理 |

サービス追加時は、そのサービス用のservice-admin Roleを追加する。`vweb-bff` ClientではRole scope mappingを制限し、アプリケーションに必要なRoleだけをtokenへ含める。

## Keycloak内のGroup階層

認証情報の投影は階層Realm groupで表現する。

```text
/services
├── /service-a
│   ├── /administrators
│   └── /groups
│       └── /group-a
│           ├── /administrators
│           ├── /editors
│           └── /viewers
└── /service-b
    ├── /administrators
    └── /groups
        └── /group-b
            ├── /administrators
            ├── /editors
            └── /viewers
```

Group pathがスコープを、割り当てられたClient Roleが能力を表す。

| Keycloak Group | Client Role | サービス上の意味 |
|---|---|---|
| `/services/service-a/administrators` | `service-a-admin` | service-a管理者 |
| `/services/service-a/groups/group-a/administrators` | `group-admin` | グループA管理者 |
| `/services/service-a/groups/group-a/editors` | `group-editor` | グループA編集者 |
| `/services/service-a/groups/group-a/viewers` | `group-viewer` | グループA閲覧者 |

`vweb-bff` ClientにはGroup Membership mapperを設定し、完全なGroup pathを`groups` claimへ含める。サービスbackはRole名だけで認可せず、サービス／Group pathまたはサービスDBの投影と組み合わせて判断する。

## サービス側の認可モデル

各サービスのbackは次の概念を管理する。

- **User：** Keycloak userのローカル投影。`keycloak_sub`で紐付ける。
- **Group：** 安定IDと任意の親Groupを持つサービススコープの集合。
- **Role：** administrator、editor、viewerなどのサービス単位の能力集合。
- **Policy：** RoleまたはMember contextをResource・actionへ結び付ける条件付きルール。
- **Member：** UserをGroupへ所属させ、1つ以上のRoleを割り当てたもの。

標準Roleの権限は次のとおりとする。

| Role | 初期権限 |
|---|---|
| サービス管理者 | サービス内のGroup、Role、Policyを作成・管理 |
| グループ管理者 | 対象GroupへのMember追加・削除、MemberのRole割当更新 |
| グループ編集者 | Policyが許可するサービスリソース操作 |
| グループ閲覧者 | Policyが許可するサービスリソース参照 |

グループ管理者はRole・Policyを作成できず、他のGroupを管理できない。編集者と閲覧者はMember管理や認可設定を行えない。

## 管理フロー

### サービス管理者がGroup、Role、Policyを作成する場合

1. 利用者がKeycloakとBFFを通して認証する。
2. サービスbackが`platform-admin`または対象サービスのservice-admin権限を検証する。
3. サービスbackが専用Service Accountで対応するKeycloak GroupまたはRole mappingを更新する。
4. 投影が成功した後、サービスbackがPostgreSQLへ正規レコードを保存する。この2システム間で失敗した場合に備え、投影のreconcileは必要である。
5. 監査レコードとreconciliation用outbox eventを記録する。

### グループ管理者がMemberを管理する場合

1. グループ管理者がサービスのMember管理APIを呼び出す。
2. サービスbackが呼び出し元に対象Groupの管理権限があることを確認する。
3. サービスbackがService Account経由でKeycloak Group membership投影とRole mappingを更新する。
4. サービスbackがPostgreSQLの正規`member`レコードとRole割当を作成または更新する。
5. 操作を監査する。ブラウザへKeycloak Admin APIの認証情報を渡さない。

### Role更新

グループ管理者は、既存RoleをMemberへ割り当てたり置き換えたりできるが、新しいRoleの作成やPolicyの変更はできない。Role・Policyの作成はサービス管理者または`platform-admin`に限定する。

## TokenとBFFの処理

BFFはKeycloak tokenを検証し、次を抽出する。

- `sub`
- `platform-admin`を含むRealm Role
- `resource_access.vweb-bff.roles`に含まれるservice-admin／group Role
- 階層pathを含む`groups` claim

BFFはサーバー側で生成した認証コンテキストだけを選択されたサービスbackへ渡す。サービスbackは`keycloak_sub`で正規のUser、Group、Role、Policy、Memberを取得し、最終的な認可判断を行う。

## Keycloak管理境界

Keycloak Admin Consoleや無制限のAdmin REST APIを利用者へ公開しない。サービスbackが自身のGroup投影を管理する場合は、必要最小限のrealm-management権限だけを持つサービス専用confidential Service Accountを利用する。認証情報はサーバー側secretとし、ブラウザへ送らない。

Keycloak Authorization ServicesはResource、Scope、Permission、Policyを表現できるが、初期設計では動的なサービスPolicyをサービスDBで管理する。Policy storeを二重化しないためである。後からKeycloakをPolicy Decision Pointとして利用する場合は、移行と整合性設計を別途行う。

