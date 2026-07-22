<script setup lang="ts">
import { computed, ref } from 'vue';

/**
 * Interactive demo of RNP's three trust states, rendered as the signature
 * banner Mail shows above a signed message. Mirrors the real states:
 * unverified (usable, no badge), verified (green badge), and problem
 * (encryption blocked until the new key is verified).
 */

type TrustState = 'unverified' | 'verified' | 'problem';

interface StateInfo {
  label: string;
  color: string;
  /** Brighter variant used for inactive-tab text/borders in dark mode. */
  colorDark: string;
  bg: string;
  border: string;
  bannerTitle: string;
  bannerText: string;
  effect: string;
}

const STATES: Record<TrustState, StateInfo> = {
  unverified: {
    label: 'Unverified',
    color: '#B07708',
    colorDark: '#E8A13A',
    bg: 'rgba(232, 161, 58, 0.12)',
    border: 'rgba(232, 161, 58, 0.45)',
    bannerTitle: 'Signed by alice@example.com — key not verified',
    bannerText:
      'The signature is valid, but you have not verified the signer’s key. This is the normal state for new correspondents (trust on first use).',
    effect: 'Encryption and verification proceed normally. The key is shown without a badge.',
  },
  verified: {
    label: 'Verified',
    color: '#0E7A55',
    colorDark: '#3ECF9A',
    bg: 'rgba(14, 159, 110, 0.12)',
    border: 'rgba(14, 159, 110, 0.45)',
    bannerTitle: 'Signed by alice@example.com — verified key',
    bannerText:
      'The signature is valid and you have compared the key’s fingerprint with the owner over a trusted channel.',
    effect: 'Usable, shown with a green badge in the key list and in Mail’s banner.',
  },
  problem: {
    label: 'Problem',
    color: '#B33535',
    colorDark: '#F08A8A',
    bg: 'rgba(214, 69, 69, 0.12)',
    border: 'rgba(214, 69, 69, 0.45)',
    bannerTitle: 'Key conflict for alice@example.com',
    bannerText:
      'A different fingerprint appeared for an address you already know. This can be a legitimate re-key — or a key-substitution attempt.',
    effect: 'Encryption to this address is blocked until you verify the new key’s fingerprint.',
  },
};

const ORDER: TrustState[] = ['unverified', 'verified', 'problem'];

const active = ref<TrustState>('unverified');

const info = computed(() => STATES[active.value]);
</script>

<template>
  <div class="not-content widget">
    <div class="widget-header">
      <span class="mono-label">Trust states · Mail banner preview</span>
      <span class="live-dot" aria-hidden="true"></span>
    </div>

    <div class="widget-body">
      <div class="flex flex-wrap gap-2" role="tablist" aria-label="Trust state">
        <button
          v-for="s in ORDER"
          :key="s"
          type="button"
          role="tab"
          :aria-selected="active === s"
          class="trust-tab rounded-full border px-4 py-1.5 font-mono text-sm transition-all"
          :style="
            active === s
              ? { backgroundColor: STATES[s].color, borderColor: STATES[s].color, color: '#fff' }
              : { '--c': STATES[s].color, '--c-dark': STATES[s].colorDark }
          "
          @click="active = s"
        >
          {{ STATES[s].label }}
        </button>
      </div>

      <Transition mode="out-in" name="banner">
        <div :key="active" class="mt-5">
          <!-- Mock of the Mail signature banner -->
          <div
            class="flex items-start gap-3 rounded-xl border p-4"
            :style="{ backgroundColor: info.bg, borderColor: info.border }"
          >
            <svg
              class="mt-0.5 h-5 w-5 shrink-0"
              :style="{ color: info.color }"
              viewBox="0 0 20 20"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                v-if="active === 'verified'"
                fill-rule="evenodd"
                d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm3.7-9.3a1 1 0 0 0-1.4-1.4L9 10.6 7.7 9.3a1 1 0 0 0-1.4 1.4l2 2a1 1 0 0 0 1.4 0l4-4Z"
                clip-rule="evenodd"
              />
              <path
                v-else-if="active === 'problem'"
                fill-rule="evenodd"
                d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM8.3 6.3a1 1 0 0 0-1.4 1.4L8.6 10l-1.7 1.7a1 1 0 1 0 1.4 1.4L10 11.4l1.7 1.7a1 1 0 0 0 1.4-1.4L11.4 10l1.7-1.7a1 1 0 0 0-1.4-1.4L10 8.6 8.3 6.3Z"
                clip-rule="evenodd"
              />
              <path
                v-else
                fill-rule="evenodd"
                d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm1-5a1 1 0 1 1-2 0 1 1 0 0 1 2 0Zm-1-8a1 1 0 0 0-1 1v4a1 1 0 1 0 2 0V6a1 1 0 0 0-1-1Z"
                clip-rule="evenodd"
              />
            </svg>
            <div>
              <div class="text-sm font-semibold" :style="{ color: info.color }">
                {{ info.bannerTitle }}
              </div>
              <p class="mt-1 text-sm leading-relaxed text-soft">
                {{ info.bannerText }}
              </p>
            </div>
          </div>
          <p class="mt-3 text-sm text-faint">
            <span class="font-semibold text-foreground">Effect:</span>
            {{ info.effect }}
          </p>
        </div>
      </Transition>
    </div>

    <div class="widget-footer">
      Fails closed: an unverified key never blocks you — a changed key always does.
    </div>
  </div>
</template>

<style scoped>
/* Inactive tabs tint with the state color; brighten it in dark mode. */
.trust-tab:not([aria-selected='true']) {
  color: var(--c);
  border-color: color-mix(in srgb, var(--c) 45%, transparent);
}

:root[data-theme='dark'] .trust-tab:not([aria-selected='true']) {
  color: var(--c-dark);
  border-color: color-mix(in srgb, var(--c-dark) 45%, transparent);
}

.banner-enter-active,
.banner-leave-active {
  transition:
    opacity 0.25s ease,
    transform 0.25s ease;
}

.banner-enter-from {
  opacity: 0;
  transform: translateY(6px);
}

.banner-leave-to {
  opacity: 0;
  transform: translateY(-6px);
}

@media (prefers-reduced-motion: reduce) {
  .banner-enter-active,
  .banner-leave-active {
    transition: none;
  }
}
</style>
