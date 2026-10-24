export type AuthorizationContext = {
  service: string
  identity_source: 'bff'
  user_subject?: string
}

export type Group = {
  id: string
  parent_id?: string | null
  name: string
  path: string
  description: string
  keycloak_id: string
}

export type Member = {
  id: string
  group_id: string
  group_name?: string
  group_path?: string
  user_id: string
  keycloak_sub: string
  email: string
  display_name: string
  role_names: string[]
}

export type AuthorizationDecision = {
  can_manage_groups: boolean
  can_manage_roles: boolean
  can_manage_policies: boolean
  can_manage_members: boolean
  can_assign_roles: boolean
  can_read_resources: boolean
  can_write_resources: boolean
}

export type AuthorizationResponse = {
  service: string
  group: string
  subject: string
  decision: AuthorizationDecision
}
