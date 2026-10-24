<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import {
  createGroup,
  createMember,
  deleteGroup,
  deleteMember,
  getAuthorizationDecision,
  listGroups,
  listMembers,
  updateGroup,
  updateMember,
} from '../api/client'
import type { AuthorizationDecision, Group, Member } from '../types/authorization'

const roleOptions = ['group-admin', 'group-editor', 'group-viewer']

const groups = ref<Group[]>([])
const members = ref<Member[]>([])
const selectedGroupId = ref('')
const error = ref('')
const success = ref('')
const loading = ref(false)
const memberLoading = ref(false)
const groupSaving = ref(false)
const memberSaving = ref(false)
const groupDialog = ref(false)
const memberDialog = ref(false)
const editingGroupId = ref<string | null>(null)
const editingMemberId = ref<string | null>(null)
const serviceAdmin = ref(false)
const selectedDecision = ref<AuthorizationDecision>(emptyDecision())

function emptyDecision(): AuthorizationDecision {
  return {
    can_manage_groups: false,
    can_manage_roles: false,
    can_manage_policies: false,
    can_manage_members: false,
    can_assign_roles: false,
    can_read_resources: false,
    can_write_resources: false,
  }
}

const groupForm = reactive({
  name: '',
  description: '',
  parent_id: '',
})

const memberForm = reactive({
  keycloak_sub: '',
  email: '',
  display_name: '',
  role_names: [] as string[],
})

const selectedGroup = computed(() => groups.value.find((group) => group.id === selectedGroupId.value) ?? null)
const editingGroup = computed(() => groups.value.find((group) => group.id === editingGroupId.value) ?? null)
const parentGroupOptions = computed(() =>
  groups.value
    .filter((group) => group.id !== editingGroupId.value)
    .map((group) => ({ title: group.path, value: group.id })),
)
function reportError(cause: unknown) {
  error.value = cause instanceof Error ? cause.message : 'The request failed.'
  success.value = ''
}

async function loadMembers(groupId = selectedGroupId.value) {
  if (!groupId) {
    members.value = []
    return
  }
  memberLoading.value = true
  try {
    members.value = await listMembers(groupId)
  } catch (cause) {
    reportError(cause)
  } finally {
    memberLoading.value = false
  }
}

async function loadPermissions(groupId = selectedGroupId.value) {
  const group = groups.value.find((item) => item.id === groupId)
  if (!group) {
    selectedDecision.value = emptyDecision()
    return
  }
  try {
    selectedDecision.value = (await getAuthorizationDecision(group.path)).decision
  } catch (cause) {
    selectedDecision.value = emptyDecision()
    reportError(cause)
  }
}

async function loadPage() {
  loading.value = true
  error.value = ''
  try {
    serviceAdmin.value = (await getAuthorizationDecision('/services/service-b/administrators')).decision.can_manage_groups
    groups.value = await listGroups()
    if (!groups.value.some((group) => group.id === selectedGroupId.value)) {
      selectedGroupId.value = groups.value[0]?.id ?? ''
    }
    await loadPermissions()
    await loadMembers()
  } catch (cause) {
    reportError(cause)
  } finally {
    loading.value = false
  }
}

async function selectGroup(groupId: string) {
  selectedGroupId.value = groupId
  await loadPermissions(groupId)
  await loadMembers(groupId)
}

function openCreateGroup() {
  editingGroupId.value = null
  groupForm.name = ''
  groupForm.description = ''
  groupForm.parent_id = ''
  groupDialog.value = true
}

function openEditGroup(group: Group) {
  editingGroupId.value = group.id
  groupForm.name = group.name
  groupForm.description = group.description
  groupForm.parent_id = group.parent_id ?? ''
  groupDialog.value = true
}

async function saveGroup() {
  const name = groupForm.name.trim()
  if (!name) {
    error.value = 'Group name is required.'
    return
  }
  groupSaving.value = true
  error.value = ''
  try {
    const input = {
      name,
      description: groupForm.description.trim(),
      ...(groupForm.parent_id ? { parent_id: groupForm.parent_id } : {}),
    }
    const wasEditing = Boolean(editingGroupId.value)
    const saved = editingGroupId.value
      ? await updateGroup(editingGroupId.value, input)
      : await createGroup(input)
    groupDialog.value = false
    groups.value = await listGroups()
    selectedGroupId.value = saved.id
    await loadMembers(saved.id)
    success.value = wasEditing ? 'Group updated.' : 'Group created.'
  } catch (cause) {
    reportError(cause)
  } finally {
    groupSaving.value = false
  }
}

async function removeSelectedGroup() {
  if (!selectedGroup.value || !window.confirm(`Delete ${selectedGroup.value.name}?`)) return
  loading.value = true
  error.value = ''
  try {
    await deleteGroup(selectedGroup.value.id)
    groups.value = await listGroups()
    selectedGroupId.value = groups.value[0]?.id ?? ''
    await loadMembers()
    success.value = 'Group deleted.'
  } catch (cause) {
    reportError(cause)
  } finally {
    loading.value = false
  }
}

function openCreateMember() {
  editingMemberId.value = null
  memberForm.keycloak_sub = ''
  memberForm.email = ''
  memberForm.display_name = ''
  memberForm.role_names = ['group-viewer']
  memberDialog.value = true
}

function openEditMember(member: Member) {
  editingMemberId.value = member.id
  memberForm.keycloak_sub = member.keycloak_sub
  memberForm.email = member.email
  memberForm.display_name = member.display_name
  memberForm.role_names = [...member.role_names]
  memberDialog.value = true
}

async function saveMember() {
  if (!selectedGroupId.value) return
  if (!editingMemberId.value && !memberForm.keycloak_sub.trim()) {
    error.value = 'Keycloak subject is required for a new member.'
    return
  }
  const email = memberForm.email.trim().toLowerCase()
  if (!email) {
    error.value = 'Email address is required.'
    return
  }
  memberSaving.value = true
  error.value = ''
  try {
    if (editingMemberId.value) {
      await updateMember(editingMemberId.value, {
        email,
        display_name: memberForm.display_name.trim(),
        role_names: memberForm.role_names,
      })
    } else {
      await createMember(selectedGroupId.value, {
        keycloak_sub: memberForm.keycloak_sub.trim(),
        email,
        role_names: memberForm.role_names,
      })
    }
    memberDialog.value = false
    await loadMembers()
    success.value = editingMemberId.value ? 'Member updated.' : 'Member added.'
  } catch (cause) {
    reportError(cause)
  } finally {
    memberSaving.value = false
  }
}

async function removeMember(member: Member) {
  if (!window.confirm(`Remove ${member.display_name || member.email}?`)) return
  memberLoading.value = true
  error.value = ''
  try {
    await deleteMember(member.id)
    await loadMembers()
    success.value = 'Member removed.'
  } catch (cause) {
    reportError(cause)
  } finally {
    memberLoading.value = false
  }
}

onMounted(loadPage)
</script>

<template>
  <v-progress-linear v-if="loading" color="primary" indeterminate absolute top />
  <v-container class="py-8" max-width="1440">
        <div class="mb-7">
          <div class="text-overline text-primary">Administration</div>
          <h1 class="text-h4 font-weight-bold mb-2">Groups and members</h1>
          <p class="text-body-1 text-medium-emphasis mb-0">
            Manage service-owned group details and synchronize membership with Keycloak.
          </p>
        </div>

        <v-alert v-if="error" class="mb-4" closable type="error" variant="tonal" @click:close="error = ''">
          {{ error }}
        </v-alert>
        <v-alert v-if="success" class="mb-4" closable type="success" variant="tonal" @click:close="success = ''">
          {{ success }}
        </v-alert>

        <v-row align="start">
          <v-col cols="12" md="5" lg="4">
            <v-card border flat>
              <v-card-item>
                <template #prepend>
                  <v-avatar color="primary" variant="tonal">G</v-avatar>
                </template>
                <v-card-title>Groups</v-card-title>
                <v-card-subtitle>{{ groups.length }} service groups</v-card-subtitle>
              </v-card-item>
              <v-card-actions class="px-4 pb-4">
                <v-btn v-if="serviceAdmin" color="primary" variant="flat" @click="openCreateGroup">New group</v-btn>
                <v-btn variant="text" @click="loadPage">Refresh</v-btn>
              </v-card-actions>
              <v-divider />
              <v-list class="py-2" lines="two" nav>
                <v-list-item
                  v-for="group in groups"
                  :key="group.id"
                  :active="selectedGroupId === group.id"
                  color="primary"
                  rounded="lg"
                  @click="selectGroup(group.id)"
                >
                  <template #prepend>
                    <v-avatar class="mr-3" color="primary" size="36" variant="tonal">
                      {{ group.name.slice(0, 1).toUpperCase() }}
                    </v-avatar>
                  </template>
                  <v-list-item-title>{{ group.name }}</v-list-item-title>
                  <v-list-item-subtitle class="text-truncate">{{ group.path }}</v-list-item-subtitle>
                  <template #append>
                    <v-btn v-if="serviceAdmin" size="small" variant="text" @click.stop="openEditGroup(group)">Edit</v-btn>
                  </template>
                </v-list-item>
                <v-list-item v-if="groups.length === 0" class="text-medium-emphasis">
                  No groups have been created yet.
                </v-list-item>
              </v-list>
            </v-card>
          </v-col>

          <v-col cols="12" md="7" lg="8">
            <v-card border flat>
              <v-card-item>
                <template #prepend>
                  <v-avatar color="secondary" variant="tonal">M</v-avatar>
                </template>
                <v-card-title>{{ selectedGroup?.name ?? 'Select a group' }}</v-card-title>
                <v-card-subtitle>{{ selectedGroup?.path ?? 'Choose a group to view its members.' }}</v-card-subtitle>
                <template #append>
                  <v-btn v-if="selectedDecision.can_manage_members" :disabled="!selectedGroup" color="primary" variant="flat" @click="openCreateMember">
                    Add member
                  </v-btn>
                </template>
              </v-card-item>
              <v-card-text v-if="selectedGroup?.description" class="pt-0 text-medium-emphasis">
                {{ selectedGroup.description }}
              </v-card-text>
              <v-divider />
              <v-table class="member-table" hover>
                <thead>
                  <tr>
                    <th>Member</th>
                    <th>Email</th>
                    <th>Roles</th>
                    <th class="text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="member in members" :key="member.id">
                    <td>
                      <div class="font-weight-medium">{{ member.display_name || 'Unnamed user' }}</div>
                      <div class="text-caption text-medium-emphasis">{{ member.keycloak_sub }}</div>
                    </td>
                    <td>{{ member.email || '—' }}</td>
                    <td>
                      <v-chip v-for="role in member.role_names" :key="role" class="mr-1" color="primary" label size="small" variant="tonal">
                        {{ role }}
                      </v-chip>
                      <span v-if="member.role_names.length === 0" class="text-medium-emphasis">No roles</span>
                    </td>
                    <td class="text-right text-no-wrap">
                      <v-btn v-if="selectedDecision.can_manage_members" size="small" variant="text" @click="openEditMember(member)">Edit</v-btn>
                      <v-btn v-if="selectedDecision.can_manage_members" color="error" size="small" variant="text" @click="removeMember(member)">Remove</v-btn>
                    </td>
                  </tr>
                  <tr v-if="!memberLoading && members.length === 0">
                    <td class="text-center text-medium-emphasis py-8" colspan="4">
                      {{ selectedGroup ? 'No members in this group.' : 'Select a group to view members.' }}
                    </td>
                  </tr>
                </tbody>
              </v-table>
              <v-progress-linear v-if="memberLoading" color="primary" indeterminate />
            </v-card>

            <v-card v-if="selectedGroup" class="mt-4" border flat>
              <v-card-item>
                <v-card-title>Group details</v-card-title>
                <template #append>
                  <v-btn v-if="serviceAdmin" color="error" variant="text" @click="removeSelectedGroup">Delete group</v-btn>
                </template>
              </v-card-item>
              <v-card-text class="text-body-2 text-medium-emphasis">
                The group is stored in PostgreSQL and projected to Keycloak. Groups with members or child groups cannot be deleted.
              </v-card-text>
            </v-card>
          </v-col>
        </v-row>
  </v-container>

    <v-dialog v-model="groupDialog" max-width="560">
      <v-card>
        <v-card-title>{{ editingGroup ? 'Edit group' : 'Create group' }}</v-card-title>
        <v-card-text>
          <v-text-field v-model="groupForm.name" autofocus label="Name" @keyup.enter="saveGroup" />
          <v-textarea v-model="groupForm.description" auto-grow label="Description" rows="3" />
          <v-select
            v-if="!editingGroup"
            v-model="groupForm.parent_id"
            :items="parentGroupOptions"
            clearable
            item-title="title"
            item-value="value"
            label="Parent group (optional)"
          />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="groupDialog = false">Cancel</v-btn>
          <v-btn :loading="groupSaving" color="primary" variant="flat" @click="saveGroup">Save</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="memberDialog" max-width="560">
      <v-card>
        <v-card-title>{{ editingMemberId ? 'Edit member' : 'Add member' }}</v-card-title>
        <v-card-text>
          <v-text-field v-if="!editingMemberId" v-model="memberForm.keycloak_sub" label="Keycloak subject" />
          <v-text-field v-model="memberForm.display_name" label="Display name" />
          <v-text-field v-model="memberForm.email" label="Email address" type="email" required />
          <v-select v-model="memberForm.role_names" :items="roleOptions" chips closable-chips label="Roles" multiple />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="memberDialog = false">Cancel</v-btn>
          <v-btn :loading="memberSaving" color="primary" variant="flat" @click="saveMember">Save</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
</template>

<style scoped>
.member-table th {
  color: rgb(var(--v-theme-on-surface-variant));
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.member-table td {
  min-width: 9rem;
  padding-bottom: 1rem !important;
  padding-top: 1rem !important;
}
</style>
