<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { RouterView, useRoute } from 'vue-router'
import { getAuthorizationContext, getAuthorizationDecision } from './api/client'

const serviceName = 'Service B'
const drawer = ref(true)
const subject = ref('')
const canViewAllMembers = ref(false)
const route = useRoute()
const allNavigation = [
  { title: 'Overview', to: '/' },
  { title: 'Groups', to: '/groups' },
  { title: 'Members', to: '/members' },
]
const navigation = computed(() => allNavigation.filter((item) => item.to !== '/members' || canViewAllMembers.value))
const currentTitle = computed(() => navigation.find((item) => item.to === route.path)?.title ?? serviceName)
const subjectLabel = computed(() => (subject.value ? `${subject.value.slice(0, 8)}…` : 'Not signed in'))

onMounted(async () => {
  try {
    subject.value = (await getAuthorizationContext()).user_subject ?? ''
    canViewAllMembers.value = (await getAuthorizationDecision('/services/service-b/administrators')).decision.can_manage_groups
  } catch {
    subject.value = ''
    canViewAllMembers.value = false
  }
})
</script>

<template>
  <v-app>
    <v-navigation-drawer v-model="drawer" width="272">
      <div class="pa-5">
        <div class="text-overline text-primary">vweb</div>
        <div class="text-h6 font-weight-bold">{{ serviceName }}</div>
        <div class="text-body-2 text-medium-emphasis">Service administration</div>
      </div>
      <v-divider />
      <v-list class="pa-3" nav>
        <v-list-item
          v-for="item in navigation"
          :key="item.to"
          :to="item.to"
          :title="item.title"
          color="primary"
          rounded="lg"
        />
      </v-list>
      <template #append>
        <div class="pa-4 text-caption text-medium-emphasis">
          Group and member data are managed by the service back end.
        </div>
      </template>
    </v-navigation-drawer>

    <v-app-bar border="b" color="surface" flat>
      <v-btn class="ml-2" variant="text" @click="drawer = !drawer">Menu</v-btn>
      <v-app-bar-title class="font-weight-bold">{{ currentTitle }}</v-app-bar-title>
      <v-spacer />
      <v-chip class="mr-3" color="primary" label size="small">{{ subjectLabel }}</v-chip>
      <v-btn class="mr-2" href="/auth/logout" variant="text">Sign out</v-btn>
    </v-app-bar>

    <v-main>
      <RouterView />
    </v-main>
  </v-app>
</template>
