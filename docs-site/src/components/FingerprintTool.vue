<script setup lang="ts">
import { computed, ref } from 'vue';

/**
 * OpenPGP fingerprint formatter / verifier.
 * A v4 fingerprint is 40 hexadecimal characters (160-bit SHA-1 over the key
 * material). This tool normalizes pasted input, validates it, and renders
 * the canonical 10×4 grouped form shown in RNP's key detail sheet.
 */

const SAMPLE = '9F3B 7A2C 55E1 08D4 6C90 A3F7 12B8 4D6E C1A5 7F09';

const raw = ref('');
const copied = ref(false);

/** Strip everything that is not a hex digit, uppercase the rest. */
const hex = computed(() => raw.value.toUpperCase().replace(/[^0-9A-F]/g, ''));

const hasBadChars = computed(() => /[^0-9a-fA-F\s]/.test(raw.value));

type State = 'empty' | 'partial' | 'invalid' | 'valid';

const state = computed<State>(() => {
  if (raw.value.trim() === '') return 'empty';
  if (hex.value.length !== 40) return 'partial';
  if (hasBadChars.value) return 'invalid';
  return 'valid';
});

/** Canonical display form: ten groups of four hex characters. */
const grouped = computed(() => hex.value.replace(/(.{4})/g, '$1 ').trim());

/** Long key ID: the low 16 hex digits of the fingerprint. */
const keyId = computed(() => hex.value.slice(-16).replace(/(.{4})/g, '$1 ').trim());

const statusMessage = computed(() => {
  switch (state.value) {
    case 'empty':
      return 'Paste a fingerprint to check it — for example from a business card, a signed message, or a keyserver.';
    case 'partial':
      return `${hex.value.length} of 40 hex characters — an OpenPGP v4 fingerprint is 40 hexadecimal digits.`;
    case 'invalid':
      return 'This input contains characters that are not hexadecimal digits (0–9, A–F).';
    case 'valid':
      return 'Well-formed OpenPGP fingerprint. Compare it with the owner over a trusted channel.';
  }
});

async function copy() {
  try {
    await navigator.clipboard.writeText(grouped.value);
    copied.value = true;
    setTimeout(() => (copied.value = false), 1500);
  } catch {
    /* clipboard unavailable — ignore */
  }
}

function useSample() {
  raw.value = SAMPLE;
}
</script>

<template>
  <div
    class="not-content rounded-2xl border border-slate-200 bg-white p-6 shadow-sm transition-colors dark:border-slate-700 dark:bg-slate-900"
  >
    <label
      for="fingerprint-input"
      class="block text-sm font-semibold text-slate-700 dark:text-slate-200"
    >
      Fingerprint
    </label>
    <input
      id="fingerprint-input"
      v-model="raw"
      type="text"
      spellcheck="false"
      autocomplete="off"
      placeholder="9F3B 7A2C 55E1 08D4 …"
      class="mt-2 w-full rounded-lg border bg-slate-50 px-4 py-3 font-mono text-sm tracking-wider text-slate-900 outline-none transition focus:border-[#1A7BEC] focus:ring-2 focus:ring-[#1A7BEC]/30 dark:bg-slate-950 dark:text-slate-100"
      :class="
        state === 'invalid' || (state === 'partial' && hasBadChars)
          ? 'border-red-400 dark:border-red-500'
          : 'border-slate-300 dark:border-slate-700'
      "
    />

    <div class="mt-3 flex items-center justify-between gap-3">
      <p
        class="text-sm transition-colors"
        :class="{
          'text-slate-500 dark:text-slate-400': state === 'empty' || state === 'partial',
          'text-red-600 dark:text-red-400': state === 'invalid',
          'text-emerald-600 dark:text-emerald-400': state === 'valid',
        }"
        role="status"
      >
        {{ statusMessage }}
      </p>
      <button
        type="button"
        class="shrink-0 rounded-full border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 transition hover:border-[#1A7BEC] hover:text-[#1A7BEC] dark:border-slate-600 dark:text-slate-300 dark:hover:border-[#58A0F4] dark:hover:text-[#58A0F4]"
        @click="useSample"
      >
        Try a sample
      </button>
    </div>

    <Transition
      enter-active-class="transition duration-300 ease-out"
      enter-from-class="opacity-0 -translate-y-1"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="state === 'valid'"
        class="mt-5 rounded-xl bg-slate-50 p-5 dark:bg-slate-950"
      >
        <div class="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
          Formatted fingerprint
        </div>
        <div class="mt-2 font-mono text-base leading-relaxed text-slate-900 dark:text-slate-50">
          {{ grouped }}
        </div>
        <div class="mt-4 grid gap-3 sm:grid-cols-2">
          <div>
            <div class="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
              Key ID (long)
            </div>
            <div class="mt-1 font-mono text-sm text-slate-700 dark:text-slate-300">
              {{ keyId }}
            </div>
          </div>
          <div class="flex items-end justify-start sm:justify-end">
            <button
              type="button"
              class="rounded-lg bg-[#1A7BEC] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#0B54B8]"
              @click="copy"
            >
              {{ copied ? 'Copied!' : 'Copy' }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>
