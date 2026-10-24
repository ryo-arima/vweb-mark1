import type {
  AuthorizationContext,
  AuthorizationResponse,
  Group,
  Member,
} from '../types/authorization'

const apiPrefix = '/api/service-b/v1'

export type GroupInput = {
  name: string
  description: string
  parent_id?: string
}

export type MemberInput = {
  keycloak_sub?: string
  email: string
  display_name?: string
  role_names: string[]
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  headers.set('Accept', 'application/json')
  if (init.body) {
    headers.set('Content-Type', 'application/json')
  }

  const response = await fetch(`${apiPrefix}${path}`, {
    ...init,
    credentials: 'include',
    headers,
  })
  const payload = await response.json().catch(() => null)
  if (!response.ok) {
    const detail =
      payload && typeof payload === 'object' && 'error' in payload && typeof payload.error === 'string'
        ? payload.error
        : `Request failed: ${response.status}`
    throw new Error(detail)
  }
  return payload as T
}

export async function getAuthorizationContext(): Promise<AuthorizationContext> {
  return request<AuthorizationContext>('/identity')
}

export async function getAuthorizationDecision(group: string): Promise<AuthorizationResponse> {
  return request<AuthorizationResponse>(`/authorization/decision?group=${encodeURIComponent(group)}`)
}

export function listGroups(): Promise<Group[]> {
  return request<Group[]>('/groups')
}

export function createGroup(input: GroupInput): Promise<Group> {
  return request<Group>('/groups', {
    method: 'POST',
    body: JSON.stringify(input),
  })
}

export function updateGroup(groupId: string, input: GroupInput): Promise<Group> {
  return request<Group>(`/groups/${encodeURIComponent(groupId)}`, {
    method: 'PATCH',
    body: JSON.stringify(input),
  })
}

export function deleteGroup(groupId: string): Promise<{ deleted: string }> {
  return request<{ deleted: string }>(`/groups/${encodeURIComponent(groupId)}`, {
    method: 'DELETE',
  })
}

export function listMembers(groupId: string): Promise<Member[]> {
  return request<Member[]>(`/groups/${encodeURIComponent(groupId)}/members`)
}

export function listAllMembers(): Promise<Member[]> {
  return request<Member[]>('/members')
}

export function createMember(
  groupId: string,
  input: Required<Pick<MemberInput, 'keycloak_sub' | 'email'>> & MemberInput,
): Promise<Member> {
  return request<Member>(`/groups/${encodeURIComponent(groupId)}/members`, {
    method: 'POST',
    body: JSON.stringify(input),
  })
}

export function updateMember(memberId: string, input: MemberInput): Promise<Member> {
  return request<Member>(`/members/${encodeURIComponent(memberId)}`, {
    method: 'PATCH',
    body: JSON.stringify(input),
  })
}

export function deleteMember(memberId: string): Promise<{ deleted: string }> {
  return request<{ deleted: string }>(`/members/${encodeURIComponent(memberId)}`, {
    method: 'DELETE',
  })
}
