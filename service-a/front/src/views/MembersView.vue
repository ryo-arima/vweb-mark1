<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { getAuthorizationDecision, listAllMembers } from '../api/client'
import type { Member } from '../types/authorization'

const members = ref<Member[]>([])
const loading = ref(false)
const error = ref('')
const canViewAllMembers = ref(false)

async function loadMembers() {
  loading.value = true
  error.value = ''
  try {
    canViewAllMembers.value = (await getAuthorizationDecision('/services/service-a/administrators')).decision.can_manage_groups
    if (!canViewAllMembers.value) {
      members.value = []
      return
    }
    members.value = await listAllMembers()
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'The member list could not be loaded.'
  } finally {
    loading.value = false
  }
}

onMounted(loadMembers)
</script>

<template>
  <v-container class="py-8" max-width="1440">
    <div class="d-flex flex-wrap align-center justify-space-between ga-4 mb-7">
      <div>
        <div class="text-overline text-primary">Service A</div>
        <h1 class="text-h4 font-weight-bold mb-2">All members</h1>
        <p class="text-body-1 text-medium-emphasis mb-0">
          Service administrators can review memberships across every group.
        </p>
      </div>
      <v-btn v-if="canViewAllMembers" :loading="loading" color="primary" variant="flat" @click="loadMembers">Refresh</v-btn>
    </div>

    <v-alert v-if="error" class="mb-4" closable type="error" variant="tonal" @click:close="error = ''">
      {{ error }}
    </v-alert>
    <v-alert v-if="!canViewAllMembers && !loading" class="mb-4" type="info" variant="tonal">
      The all-members list requires the service administrator role. Open Groups to view the groups granted to your account.
    </v-alert>

    <v-card v-if="canViewAllMembers" border flat>
      <v-card-item>
        <v-card-title>{{ members.length }} members</v-card-title>
        <v-card-subtitle>PostgreSQL service records with Keycloak membership projections</v-card-subtitle>
      </v-card-item>
      <v-divider />
      <v-table hover>
        <thead>
          <tr>
            <th>Member</th>
            <th>Group</th>
            <th>Email</th>
            <th>Roles</th>
            <th>Keycloak subject</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="member in members" :key="member.id">
            <td>
              <div class="font-weight-medium">{{ member.display_name || 'Unnamed user' }}</div>
              <div class="text-caption text-medium-emphasis">{{ member.email || 'No email' }}</div>
            </td>
            <td>
              <div class="font-weight-medium">{{ member.group_name || member.group_id }}</div>
              <div class="text-caption text-medium-emphasis">{{ member.group_path }}</div>
            </td>
            <td>{{ member.email || '—' }}</td>
            <td>
              <v-chip v-for="role in member.role_names" :key="role" class="mr-1" color="primary" label size="small" variant="tonal">
                {{ role }}
              </v-chip>
              <span v-if="member.role_names.length === 0" class="text-medium-emphasis">No roles</span>
            </td>
            <td class="text-caption">{{ member.keycloak_sub }}</td>
          </tr>
          <tr v-if="!loading && members.length === 0">
            <td class="text-center text-medium-emphasis py-8" colspan="5">No members found.</td>
          </tr>
        </tbody>
      </v-table>
      <v-progress-linear v-if="loading" color="primary" indeterminate />
    </v-card>
  </v-container>
</template>
