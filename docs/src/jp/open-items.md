# 未決事項

次の事項は詳細設計・実装時に決定する。

- 業務ドメイン、画面一覧、API一覧、権限マトリクス
- PostgreSQLドライバーとマイグレーションツールの実装詳細
- BFFセッション暗号方式、鍵ローテーション、セッション有効期間
- クライアント証明書の配布、更新、失効、端末と利用者の紐付け
- step-caのprovisioner種別とSAN発行ポリシー
- OpenRestyと各サービスのback間の防御用mTLSを採用するか
- Keycloak Group／Role投影のreconcile、retry、drift検知方式
- 本番PostgreSQLバックアップ、CA鍵保管、監視、アラート
- Keycloak、OpenResty、step-ca、PostgreSQLの正確なバージョンとimage digest
- サービスback imageで利用するV builder imageの正確なバージョンまたはdigest
- 本番mail DNS、TLS、mailbox永続化、アカウントライフサイクル、外向き配送ポリシー

決定した事項は対応するmdBook章へ反映する。実装不変条件が変わる場合はAIエージェント指示も更新する。

