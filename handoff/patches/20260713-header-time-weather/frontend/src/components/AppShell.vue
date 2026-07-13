Exit code: 0
Wall time: 0.1 seconds
Output:
<script setup lang="ts">
import {
  Bell,
  BellRing,
  Boxes,
  Building2,
  CalendarClock,
  Camera,
  ChevronDown,
  ClipboardCheck,
  CloudSun,
  CloudUpload,
  Cpu,
  Database,
  FileArchive,
  FileText,
  Gauge,
  History,
  LayoutDashboard,
  ListChecks,
  LockKeyhole,
  MapPinned,
  Menu,
  Monitor,
  Route,
  Settings,
  ShieldCheck,
  Siren,
  SquareStack,
  UserCog,
} from '@lucide/vue';
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useHeaderStatus } from '../composables/useHeaderStatus';
import { usePlatformStore } from '../stores/platform';
import AlarmAlertOrb from './AlarmAlertOrb.vue';
import PageState from './PageState.vue';
import WorkspaceDialogs from './WorkspaceDialogs.vue';

const platform = usePlatformStore();
const route = useRoute();
const router = useRouter();
const { dateTimeText, weatherText } = useHeaderStatus();
const collapsed = ref(false);
const retiredNavKeys = new Set(['uav', 'ops']);

const visibleNavItems = computed(() =>
  platform.navItems.filter(
    (item) => !retiredNavKeys.has(item.key) && item.path !== '/uav' && item.path !== '/ops' && item.label !== '鏃犱汉鏈哄鏌? && item.label !== '鐩戞帶杩愮淮',
  ),
);

const groupedNav = computed(() => {
  return visibleNavItems.value.reduce<Record<string, typeof platform.navItems>>((groups, item) => {
    groups[item.group] ||= [];
    groups[item.group].push(item);
    return groups;
  }, {});
});

const icons = {
  monitor: Monitor,
  map: MapPinned,
  twin: SquareStack,
  playback: History,
  events: Siren,
  dashboard: LayoutDashboard,
  alarms: Bell,
  workorder: ClipboardCheck,
  evidence: FileArchive,
  import: CloudUpload,
  devices: Camera,
  diag: Route,
  template: Boxes,
  algorithm: Cpu,
  storage: Database,
  report: FileText,
  notify: BellRing,
  user: UserCog,
  log: ListChecks,
} as const;

function navIcon(key: string) {
  return icons[key as keyof typeof icons] || Gauge;
}

function navBadge(key: string) {
  return platform.navBadgeByKey[key] || '';
}

function goTo(path: string) {
  void router.push(path);
}
</script>

<template>
  <div class="app-shell command-shell" :class="{ collapsed }">
    <aside class="sidebar">
      <RouterLink to="/monitor" class="brand">
        <span class="brand-mark"><ShieldCheck :size="20" /></span>
        <strong>AI瑙嗛鍒嗘瀽绯荤粺</strong>
      </RouterLink>

      <nav class="side-nav" aria-label="涓诲鑸?>
        <section v-for="(items, group) in groupedNav" :key="group">
          <h2>{{ group }}</h2>
          <RouterLink
            v-for="item in items"
            :key="item.key"
            :to="item.path"
            class="nav-link"
            :class="{ active: route.name === item.key }"
            :aria-current="route.name === item.key ? 'page' : undefined"
          >
            <component :is="navIcon(item.key)" :size="18" />
            <span>{{ item.label }}</span>
            <b v-if="navBadge(item.key)">{{ navBadge(item.key) }}</b>
          </RouterLink>
        </section>
      </nav>

      <div class="side-foot">
        <RouterLink to="/settings" class="nav-link" :class="{ active: route.path === '/settings' }">
          <Settings :size="18" />
          <span>绯荤粺璁剧疆</span>
        </RouterLink>
      </div>
    </aside>

    <section class="workspace">
      <header class="topbar">
        <button class="icon-button" type="button" title="鎶樺彔鑿滃崟" @click="collapsed = !collapsed">
          <Menu :size="20" />
        </button>
        <strong class="topbar-title">娲嬫渤鑲′唤娉楅槼鍩哄湴瀹夌幆閮?/strong>
        <div class="top-actions">
          <div class="topbar-status" aria-label="鏃ユ湡鏃堕棿涓庡杩佸ぉ姘?>
            <span class="topbar-clock" :title="dateTimeText">
              <CalendarClock :size="16" />
              <span>{{ dateTimeText }}</span>
            </span>
            <span class="topbar-weather" :title="weatherText">
              <CloudSun :size="16" />
              <span>{{ weatherText }}</span>
            </span>
          </div>
          <button class="icon-button" type="button" title="瀹夊叏涓績" @click="goTo('/user')"><LockKeyhole :size="18" /></button>
          <div class="tenant-chip">
            <Building2 :size="16" />
            <span>{{ platform.currentUser }}</span>
            <ChevronDown :size="15" />
          </div>
          <el-button size="small" @click="platform.logout()">閫€鍑?/el-button>
        </div>
      </header>

      <main class="workspace-body">
        <PageState
          :loading="platform.isLoading"
          :error="platform.loadError"
        >
          <RouterView />
        </PageState>
        <WorkspaceDialogs />
      </main>
    </section>
    <AlarmAlertOrb />
  </div>
</template>

