<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { getAuthorizationDecision, listAllMembers, listGroups } from '../api/client'

const groupCount = ref(0)
const memberCount = ref<number | null>(null)
const canViewAllMembers = ref(false)

onMounted(async () => {
  canViewAllMembers.value = (await getAuthorizationDecision('/services/service-b/administrators').catch(() => null))?.decision.can_manage_groups ?? false
  const groups = await listGroups().catch(() => [])
  groupCount.value = groups.length
  memberCount.value = canViewAllMembers.value
    ? await listAllMembers().then((members) => members.length).catch(() => null)
    : null
})
</script>

<template>
  <v-container class="py-8" max-width="1280">
    <div class="mb-8">
      <div class="text-overline text-primary">Service B</div>
      <h1 class="text-h4 font-weight-bold mb-2">Overview</h1>
      <p class="text-body-1 text-medium-emphasis mb-0">
        Review service authorization data and open the management lists from the side menu.
      </p>
    </div>

    <v-row>
      <v-col cols="12" sm="6" lg="4">
        <v-card border flat>
          <v-card-item>
            <v-card-subtitle>Groups</v-card-subtitle>
            <v-card-title class="text-h3 font-weight-bold">{{ groupCount }}</v-card-title>
          </v-card-item>
          <v-card-actions>
            <v-btn color="primary" to="/groups" variant="text">Open group list</v-btn>
          </v-card-actions>
        </v-card>
      </v-col>
      <v-col v-if="canViewAllMembers" cols="12" sm="6" lg="4">
        <v-card border flat>
          <v-card-item>
            <v-card-subtitle>Members across all groups</v-card-subtitle>
            <v-card-title class="text-h3 font-weight-bold">
              {{ memberCount === null ? '—' : memberCount }}
            </v-card-title>
          </v-card-item>
          <v-card-actions>
            <v-btn color="primary" to="/members" variant="text">Open member list</v-btn>
          </v-card-actions>
        </v-card>
      </v-col>
      <v-col cols="12" lg="4">
        <v-card border flat color="primary" variant="tonal">
          <v-card-item>
            <v-card-title>Service administration</v-card-title>
            <v-card-text class="px-0">
              Service administrators can access the complete Group and Member lists. Other users remain scoped to the groups granted in their session.
            </v-card-text>
          </v-card-item>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>
