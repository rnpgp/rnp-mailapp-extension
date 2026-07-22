<script setup lang="ts">
import { computed, ref, watch } from 'vue';

/**
 * Keyserver lookup demo.
 * Given an email address, show the exact URLs RNP would query to discover
 * the correspondent's public key: VKS (keys.openpgp.org) and Web Key
 * Directory (advanced + direct methods). Everything is computed locally —
 * no network requests are made.
 */

const email = ref('');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const trimmed = computed(() => email.value.trim().toLowerCase());
const isValid = computed(() => EMAIL_RE.test(trimmed.value));
const localPart = computed(() => trimmed.value.split('@')[0] ?? '');
const domain = computed(() => trimmed.value.split('@')[1] ?? '');

/* --- WKD "hu" hash: SHA-1 of the lowercase local part, z-base-32 encoded. --- */

const ZBASE32_ALPHABET = 'ybndrfg8ejkmcpqxot1uwisza345h769';

function zbase32Encode(data: Uint8Array): string {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of data) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += ZBASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    out += ZBASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  return out;
}

const huHash = ref('');
/** True while the SHA-1 digest is in flight (or crypto is unavailable). */
const computing = ref(false);

watch(
  localPart,
  async (part) => {
    if (!part || !globalThis.crypto?.subtle) {
      huHash.value = '';
      computing.value = false;
      return;
    }
    computing.value = true;
    try {
      const digest = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(part));
      huHash.value = zbase32Encode(new Uint8Array(digest));
    } catch {
      huHash.value = '';
    } finally {
      computing.value = false;
    }
  },
  { immediate: true },
);

interface Source {
  method: string;
  label: string;
  url: string;
  note: string;
  /** WKD rows need the async hu hash; show a loading state until it arrives. */
  pending?: boolean;
}

const sources = computed<Source[]>(() => {
  if (!isValid.value) return [];
  const encodedEmail = encodeURIComponent(trimmed.value);
  const encodedLocal = encodeURIComponent(localPart.value);
  const pending = computing.value || !huHash.value;
  const hu = huHash.value || '…';
  return [
    {
      method: 'VKS',
      label: 'keys.openpgp.org (default keyserver)',
      url: `https://keys.openpgp.org/vks/v1/by-email/${encodedEmail}`,
      note: 'Keys are discoverable by email once the owner confirmed the verification mail.',
    },
    {
      method: 'WKD (advanced)',
      label: `${domain.value} via its openpgpkey subdomain`,
      url: `https://openpgpkey.${domain.value}/.well-known/openpgpkey/${domain.value}/hu/${hu}?l=${encodedLocal}`,
      note: 'Served by the recipient’s own domain — no central server involved.',
      pending,
    },
    {
      method: 'WKD (direct)',
      label: `${domain.value} directly`,
      url: `https://${domain.value}/.well-known/openpgpkey/hu/${hu}?l=${encodedLocal}`,
      note: 'Fallback when the domain has no openpgpkey subdomain.',
      pending,
    },
  ];
});
</script>

<template>
  <div class="not-content widget">
    <div class="widget-header">
      <span class="mono-label">Key discovery · VKS + WKD</span>
      <span class="live-dot" aria-hidden="true"></span>
    </div>

    <div class="widget-body">
      <label for="keyserver-email" class="field-label">Correspondent’s email address</label>
      <input
        id="keyserver-email"
        v-model="email"
        type="email"
        spellcheck="false"
        autocomplete="off"
        placeholder="alice@example.com"
        class="field-input mt-2"
      />
      <p v-if="email && !isValid" class="mt-2 text-sm text-red-600 dark:text-red-400" role="alert">
        That does not look like an email address.
      </p>
      <p v-else class="mt-2 text-sm text-faint">
        Enter an address to see where RNP would look up the public key.
      </p>

      <Transition
        enter-active-class="transition duration-300 ease-out"
        enter-from-class="opacity-0 -translate-y-1"
        enter-to-class="opacity-100 translate-y-0"
      >
        <ul v-if="isValid" class="mt-5 space-y-3">
          <li
            v-for="source in sources"
            :key="source.method"
            class="rounded-xl border border-line bg-surface-dim p-4"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span class="chip">{{ source.method }}</span>
              <span class="text-sm font-medium text-foreground">{{ source.label }}</span>
            </div>
            <div
              v-if="source.pending"
              class="mt-2 flex h-[2.15rem] items-center rounded-lg border border-line bg-surface px-3"
              aria-busy="true"
            >
              <span class="h-2 w-2/3 animate-pulse rounded-full bg-line"></span>
            </div>
            <code
              v-else
              class="mt-2 block break-all rounded-lg border border-line bg-surface px-3 py-2 font-mono text-xs text-foreground"
            >
              {{ source.url }}
            </code>
            <p class="mt-2 text-xs text-faint">{{ source.note }}</p>
          </li>
        </ul>
      </Transition>
    </div>

    <div class="widget-footer">Computed locally — nothing leaves this page.</div>
  </div>
</template>
