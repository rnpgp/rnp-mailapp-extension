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

watch(
  localPart,
  async (part) => {
    if (!part || !globalThis.crypto?.subtle) {
      huHash.value = '';
      return;
    }
    try {
      const digest = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(part));
      huHash.value = zbase32Encode(new Uint8Array(digest));
    } catch {
      huHash.value = '';
    }
  },
  { immediate: true },
);

interface Source {
  method: string;
  label: string;
  url: string;
  note: string;
}

const sources = computed<Source[]>(() => {
  if (!isValid.value) return [];
  const encodedEmail = encodeURIComponent(trimmed.value);
  const encodedLocal = encodeURIComponent(localPart.value);
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
    },
    {
      method: 'WKD (direct)',
      label: `${domain.value} directly`,
      url: `https://${domain.value}/.well-known/openpgpkey/hu/${hu}?l=${encodedLocal}`,
      note: 'Fallback when the domain has no openpgpkey subdomain.',
    },
  ];
});
</script>

<template>
  <div
    class="not-content rounded-2xl border border-slate-200 bg-white p-6 shadow-sm transition-colors dark:border-slate-700 dark:bg-slate-900"
  >
    <label for="keyserver-email" class="block text-sm font-semibold text-slate-700 dark:text-slate-200">
      Correspondent’s email address
    </label>
    <input
      id="keyserver-email"
      v-model="email"
      type="email"
      spellcheck="false"
      autocomplete="off"
      placeholder="alice@example.com"
      class="mt-2 w-full rounded-lg border border-slate-300 bg-slate-50 px-4 py-3 font-mono text-sm text-slate-900 outline-none transition focus:border-[#1A7BEC] focus:ring-2 focus:ring-[#1A7BEC]/30 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
    />
    <p v-if="email && !isValid" class="mt-2 text-sm text-red-600 dark:text-red-400" role="alert">
      That does not look like an email address.
    </p>
    <p v-else class="mt-2 text-sm text-slate-500 dark:text-slate-400">
      Enter an address to see where RNP would look up the public key. Computed locally — nothing is
      sent anywhere.
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
          class="rounded-xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-700 dark:bg-slate-950"
        >
          <div class="flex items-center gap-2">
            <span
              class="rounded-full bg-[#1A7BEC]/10 px-2.5 py-0.5 text-xs font-bold text-[#0B54B8] dark:bg-[#58A0F4]/15 dark:text-[#58A0F4]"
            >
              {{ source.method }}
            </span>
            <span class="text-sm font-medium text-slate-700 dark:text-slate-200">{{ source.label }}</span>
          </div>
          <code class="mt-2 block break-all rounded-lg bg-white px-3 py-2 font-mono text-xs text-slate-800 ring-1 ring-slate-200 dark:bg-slate-900 dark:text-slate-200 dark:ring-slate-700">
            {{ source.url }}
          </code>
          <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">{{ source.note }}</p>
        </li>
      </ul>
    </Transition>
  </div>
</template>
