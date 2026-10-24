import { createRouter, createWebHistory } from 'vue-router'
import DashboardView from '../views/DashboardView.vue'
import HomeView from '../views/HomeView.vue'
import MembersView from '../views/MembersView.vue'

export default createRouter({
  history: createWebHistory('/service-a/'),
  routes: [
    { path: '/', component: DashboardView },
    { path: '/groups', component: HomeView },
    { path: '/members', component: MembersView },
  ],
})
