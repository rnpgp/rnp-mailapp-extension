/* ==========================================================================
   RNP docs site — shared interactivity layer (vanilla JS, no dependencies)
   Loaded on the landing page and every Starlight docs page.

   Contents:
     1.  Motion preference (respects prefers-reduced-motion + manual toggle)
     2.  Toast system (aria-live, accessible)
     3.  Scroll-to-top button
     4.  Command palette (Cmd/Ctrl+K) — incl. the hidden "rnp" command
     5.  Konami code easter egg (confetti + toast)
     6.  "openpgp" typing easter egg (base64 scramble)
     7.  "g" then "k" -> secret key page
     8.  TOFU tooltip on the trust-state demo (hover/focus for 5 s)
     9.  Service worker registration (offline support, production only)
   ========================================================================== */
(() => {
  'use strict';

  const doc = document;
  const root = doc.documentElement;

  /* ------------------------------------------------------------------
     1. Motion preference
     `data-motion` on <html>: "reduced" or "auto" (persisted). When set,
     it overrides the OS-level prefers-reduced-motion for JS effects;
     CSS mirrors the override via [data-motion='reduced'] rules.
  ------------------------------------------------------------------ */
  const MOTION_KEY = 'rnp-motion';
  const osReduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  const motionReduced = () => {
    const stored = root.dataset.motion;
    return stored ? stored === 'reduced' : osReduced();
  };
  try {
    const saved = localStorage.getItem(MOTION_KEY);
    if (saved === 'reduced' || saved === 'auto') root.dataset.motion = saved;
  } catch {
    /* private mode etc. — fall back to OS preference */
  }

  const syncMotionToggles = () => {
    const reduced = motionReduced();
    doc.querySelectorAll('[data-motion-toggle]').forEach((btn) => {
      btn.setAttribute('aria-pressed', String(reduced));
      const state = btn.querySelector('[data-motion-state]');
      if (state) state.textContent = reduced ? 'on' : 'off';
    });
  };

  const toggleMotion = () => {
    const next = motionReduced() ? 'auto' : 'reduced';
    root.dataset.motion = next;
    try {
      localStorage.setItem(MOTION_KEY, next);
    } catch {
      /* ignore */
    }
    syncMotionToggles();
    toast(
      next === 'reduced'
        ? 'Reduced motion enabled — animations and easter-egg effects are now minimal.'
        : 'Reduced motion disabled — full animations restored.',
    );
  };

  doc.addEventListener('click', (event) => {
    const btn = event.target.closest?.('[data-motion-toggle]');
    if (btn) toggleMotion();
  });

  /* ------------------------------------------------------------------
     2. Toast system — single aria-live region, queued, auto-dismiss.
  ------------------------------------------------------------------ */
  let toastRegion = null;
  const toast = (message, { sticky = false } = {}) => {
    if (!toastRegion) {
      toastRegion = doc.createElement('div');
      toastRegion.className = 'toast-region';
      toastRegion.setAttribute('aria-live', 'polite');
      toastRegion.setAttribute('role', 'status');
      doc.body.appendChild(toastRegion);
    }
    const el = doc.createElement('div');
    el.className = 'toast';
    el.textContent = message;
    toastRegion.appendChild(el);
    // Force a frame so the enter transition runs.
    requestAnimationFrame(() => el.classList.add('is-visible'));
    const dismiss = () => {
      el.classList.remove('is-visible');
      el.addEventListener('transitionend', () => el.remove(), { once: true });
      // transitionend may not fire under reduced motion; clean up anyway.
      setTimeout(() => el.remove(), 400);
    };
    if (!sticky) setTimeout(dismiss, 4200);
    el.addEventListener('click', dismiss);
    return dismiss;
  };

  /* ------------------------------------------------------------------
     3. Scroll-to-top button (created on every page).
  ------------------------------------------------------------------ */
  const toTop = doc.createElement('button');
  toTop.type = 'button';
  toTop.className = 'to-top';
  toTop.setAttribute('aria-label', 'Scroll back to top');
  toTop.innerHTML =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="m18 15-6-6-6 6"/></svg>';
  toTop.addEventListener('click', () => {
    const behavior = motionReduced() ? 'auto' : 'smooth';
    window.scrollTo({ top: 0, behavior });
    // Move focus back to the top of the document for keyboard users.
    const skipTarget = doc.getElementById('_top') || doc.getElementById('main') || doc.body;
    if (skipTarget instanceof HTMLElement) {
      skipTarget.setAttribute('tabindex', '-1');
      skipTarget.focus({ preventScroll: true });
    }
  });
  doc.body.appendChild(toTop);
  let toTopVisible = false;
  const onScroll = () => {
    const show = window.scrollY > 600;
    if (show !== toTopVisible) {
      toTopVisible = show;
      toTop.classList.toggle('is-visible', show);
    }
  };
  addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  /* ------------------------------------------------------------------
     4. Command palette (Cmd/Ctrl+K, or "/" on docs pages)
  ------------------------------------------------------------------ */
  const NAV_INDEX = [
    { title: 'Home', hint: 'Landing page', href: '/', keywords: 'rnp home start download features' },
    { title: 'Installation', hint: 'User guide', href: '/getting-started/installation/', keywords: 'install dmg notarized download setup' },
    { title: 'First Launch & Onboarding', hint: 'User guide', href: '/getting-started/first-launch/', keywords: 'onboarding generate key first run setup' },
    { title: 'Key Management', hint: 'User guide', href: '/key-management/', keywords: 'keys generate import export fingerprint ed25519 rsa' },
    { title: 'Trust & Verification', hint: 'User guide', href: '/trust-verification/', keywords: 'tofu trust verify fingerprint compare tofu' },
    { title: 'Keyservers', hint: 'User guide', href: '/keyserver/', keywords: 'vks hkps wkd publish lookup keys.openpgp.org' },
    { title: 'Using with Mail', hint: 'User guide', href: '/using-with-mail/', keywords: 'mail.app compose sign encrypt decrypt banner' },
    { title: 'Security & Privacy', hint: 'Reference', href: '/security/', keywords: 'sandbox keychain touch id privacy telemetry threat model' },
    { title: 'Troubleshooting', hint: 'Help', href: '/troubleshooting/', keywords: 'error problem fix extension not showing' },
    { title: 'FAQ', hint: 'Help', href: '/faq/', keywords: 'questions faq gnupg gpg compatibility' },
    { title: 'Landing — Features', hint: 'Section', href: '/#features', keywords: 'features overview' },
    { title: 'Landing — App preview', hint: 'Section', href: '/#preview', keywords: 'key manager window preview screenshot' },
    { title: 'Landing — Interactive demos', hint: 'Section', href: '/#demos', keywords: 'fingerprint checker trust demo keyserver lookup try' },
    { title: 'Landing — Download', hint: 'Section', href: '/#download', keywords: 'download release dmg' },
    { title: 'GitHub repository', hint: 'External', href: 'https://github.com/rnpgp/swift-rnp', keywords: 'github source code repo issues' },
  ];

  let palette = null;
  let paletteInput = null;
  let paletteList = null;
  let paletteResults = [];
  let paletteActive = 0;
  let paletteLastFocus = null;

  const RNP_EGG =
    'RNP — the open-source OpenPGP engine (librnp) that also powers ' +
    'Thunderbird’s end-to-end encryption. This app wraps it in a native ' +
    'Mac shell: sandboxed, notarized, and telemetry-free.';

  const buildPalette = () => {
    palette = doc.createElement('div');
    palette.className = 'cmdk';
    palette.setAttribute('role', 'dialog');
    palette.setAttribute('aria-modal', 'true');
    palette.setAttribute('aria-label', 'Command palette');
    palette.innerHTML =
      '<div class="cmdk-backdrop" data-cmdk-close></div>' +
      '<div class="cmdk-panel">' +
      '  <div class="cmdk-input-row">' +
      '    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
      '      stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="cmdk-icon">' +
      '      <circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>' +
      '    <input type="text" class="cmdk-input" placeholder="Search the manual… (try typing “rnp”)" ' +
      '      aria-label="Search the manual" autocomplete="off" spellcheck="false" />' +
      '    <kbd class="cmdk-kbd">esc</kbd>' +
      '  </div>' +
      '  <ul class="cmdk-list" role="listbox" aria-label="Results"></ul>' +
      '  <div class="cmdk-footer"><kbd>↑↓</kbd> navigate <kbd>↵</kbd> open <kbd>esc</kbd> close</div>' +
      '</div>';
    doc.body.appendChild(palette);
    paletteInput = palette.querySelector('.cmdk-input');
    paletteList = palette.querySelector('.cmdk-list');

    paletteInput.addEventListener('input', renderPaletteResults);
    paletteInput.addEventListener('keydown', (event) => {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        movePalette(event.key === 'ArrowDown' ? 1 : -1);
      } else if (event.key === 'Enter') {
        event.preventDefault();
        openPaletteResult(paletteActive);
      }
    });
    palette.addEventListener('click', (event) => {
      if (event.target.closest?.('[data-cmdk-close]')) closePalette();
      const option = event.target.closest?.('[data-cmdk-index]');
      if (option) openPaletteResult(Number(option.dataset.cmdkIndex));
    });
  };

  const filterPalette = (query) => {
    const q = query.trim().toLowerCase();
    if (!q) return NAV_INDEX.slice(0, 8);
    return NAV_INDEX.filter((item) => {
      const hay = `${item.title} ${item.hint} ${item.keywords}`.toLowerCase();
      return q.split(/\s+/).every((word) => hay.includes(word));
    }).slice(0, 8);
  };

  const renderPaletteResults = () => {
    const query = paletteInput.value;
    paletteResults = filterPalette(query);
    paletteActive = 0;
    paletteList.innerHTML = '';

    // Easter egg: the hidden "rnp" command.
    if (query.trim().toLowerCase() === 'rnp') {
      const li = doc.createElement('li');
      li.className = 'cmdk-item cmdk-egg';
      li.setAttribute('role', 'option');
      li.id = 'cmdk-egg';
      li.dataset.cmdkIndex = '-1';
      li.innerHTML =
        '<span class="cmdk-item-title">You found the “rnp” command</span>' +
        `<span class="cmdk-item-hint">${RNP_EGG}</span>`;
      paletteList.appendChild(li);
      return;
    }

    if (paletteResults.length === 0) {
      const li = doc.createElement('li');
      li.className = 'cmdk-empty';
      li.textContent = `No results for “${query}”.`;
      paletteList.appendChild(li);
      return;
    }

    paletteResults.forEach((item, i) => {
      const li = doc.createElement('li');
      li.className = 'cmdk-item';
      li.setAttribute('role', 'option');
      li.id = `cmdk-opt-${i}`;
      li.dataset.cmdkIndex = String(i);
      li.setAttribute('aria-selected', String(i === paletteActive));
      li.innerHTML =
        `<span class="cmdk-item-title">${item.title}</span>` +
        `<span class="cmdk-item-hint">${item.hint}</span>`;
      paletteList.appendChild(li);
    });
  };

  const movePalette = (delta) => {
    if (paletteResults.length === 0) return;
    paletteActive = (paletteActive + delta + paletteResults.length) % paletteResults.length;
    paletteList.querySelectorAll('.cmdk-item').forEach((el, i) => {
      const selected = i === paletteActive;
      el.setAttribute('aria-selected', String(selected));
      if (selected) el.scrollIntoView({ block: 'nearest' });
    });
    paletteInput.setAttribute('aria-activedescendant', `cmdk-opt-${paletteActive}`);
  };

  const openPaletteResult = (index) => {
    const item = paletteResults[index];
    if (!item) return;
    closePalette();
    location.href = item.href;
  };

  const openPalette = () => {
    if (!palette) buildPalette();
    paletteLastFocus = doc.activeElement;
    palette.classList.add('is-open');
    paletteInput.value = '';
    renderPaletteResults();
    requestAnimationFrame(() => paletteInput.focus());
  };

  const closePalette = () => {
    if (!palette) return;
    palette.classList.remove('is-open');
    if (paletteLastFocus instanceof HTMLElement) paletteLastFocus.focus();
  };

  const isTypingTarget = (el) =>
    el instanceof HTMLElement &&
    (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);

  /* ------------------------------------------------------------------
     5–7. Global keyboard easter eggs.
     Buffered so sequences work across key presses; ignored while typing
     in form fields or while the palette is open.
  ------------------------------------------------------------------ */
  let keyBuffer = '';
  const KONAMI = [
    'arrowup', 'arrowup', 'arrowdown', 'arrowdown',
    'arrowleft', 'arrowright', 'arrowleft', 'arrowright',
    'b', 'a',
  ];
  let konamiPos = 0;

  const base64Scramble = () => {
    // Collect visible text nodes inside the main content, encode each to
    // base64 for a moment, then decode back. Skipped under reduced motion.
    const scope = doc.querySelector('main') || doc.body;
    const walker = doc.createTreeWalker(scope, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const text = node.nodeValue || '';
        if (!text.trim() || text.length > 400) return NodeFilter.FILTER_REJECT;
        const parent = node.parentElement;
        if (!parent || parent.closest('script, style, input, textarea, .cmdk, .toast-region')) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const nodes = [];
    while (walker.nextNode() && nodes.length < 300) nodes.push(walker.currentNode);
    if (nodes.length === 0) return;

    const originals = nodes.map((n) => n.nodeValue);
    const encode = (s) => {
      try {
        return btoa(unescape(encodeURIComponent(s))).slice(0, Math.max(8, s.length));
      } catch {
        return s;
      }
    };
    nodes.forEach((n, i) => {
      n.nodeValue = encode(originals[i]);
    });
    toast('OpenPGP mode: everything is base64 for a second. Decoding…');
    setTimeout(() => {
      nodes.forEach((n, i) => {
        if (n.isConnected) n.nodeValue = originals[i];
      });
    }, 1400);
  };

  const confetti = () => {
    // Lightweight canvas confetti in brand colors. Skipped under reduced motion.
    const canvas = doc.createElement('canvas');
    canvas.className = 'confetti-canvas';
    canvas.setAttribute('aria-hidden', 'true');
    doc.body.appendChild(canvas);
    const ctx = canvas.getContext('2d');
    const dpr = Math.min(devicePixelRatio || 1, 2);
    canvas.width = innerWidth * dpr;
    canvas.height = innerHeight * dpr;
    const COLORS = ['#1A7BEC', '#00DFB7', '#FFDC4A', '#5EA2F5', '#2BE8C8'];
    const pieces = Array.from({ length: 160 }, () => ({
      x: Math.random() * canvas.width,
      y: -20 * dpr - Math.random() * canvas.height * 0.3,
      w: (5 + Math.random() * 6) * dpr,
      h: (8 + Math.random() * 8) * dpr,
      vy: (2.2 + Math.random() * 2.8) * dpr,
      vx: (Math.random() - 0.5) * 1.6 * dpr,
      rot: Math.random() * Math.PI,
      vr: (Math.random() - 0.5) * 0.22,
      color: COLORS[Math.floor(Math.random() * COLORS.length)],
    }));
    const start = performance.now();
    const frame = (now) => {
      const elapsed = now - start;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      for (const p of pieces) {
        p.x += p.vx;
        p.y += p.vy;
        p.rot += p.vr;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rot);
        ctx.fillStyle = p.color;
        ctx.globalAlpha = Math.max(0, 1 - elapsed / 3600);
        ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
        ctx.restore();
      }
      if (elapsed < 3800) {
        requestAnimationFrame(frame);
      } else {
        canvas.remove();
      }
    };
    requestAnimationFrame(frame);
  };

  const onKonami = () => {
    toast('You found the OpenPGP easter egg! ↑↑↓↓←→←→BA — a classic, like RFC 4880.');
    if (!motionReduced()) confetti();
  };

  doc.addEventListener('keydown', (event) => {
    // Command palette toggles work everywhere.
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      if (palette?.classList.contains('is-open')) closePalette();
      else openPalette();
      return;
    }
    if (event.key === 'Escape' && palette?.classList.contains('is-open')) {
      closePalette();
      return;
    }
    if (isTypingTarget(event.target)) return;

    const key = event.key.toLowerCase();

    // Konami code (arrow keys + b + a).
    const expected = KONAMI[konamiPos];
    if (key === expected) {
      konamiPos += 1;
      if (konamiPos === KONAMI.length) {
        konamiPos = 0;
        onKonami();
      }
    } else {
      konamiPos = key === KONAMI[0] ? 1 : 0;
    }

    // Buffered word eggs: "openpgp" scrambles, "g" then "k" opens the
    // secret key page (vim-style sequence, no modifier).
    if (/^[a-z]$/.test(key) && !event.metaKey && !event.ctrlKey && !event.altKey) {
      keyBuffer = (keyBuffer + key).slice(-16);
      if (keyBuffer.endsWith('openpgp')) {
        keyBuffer = '';
        if (motionReduced()) {
          toast('OpenPGP mode requested — effects are minimal because reduced motion is on.');
        } else {
          base64Scramble();
        }
      } else if (keyBuffer.endsWith('gk')) {
        keyBuffer = '';
        toast('Generating a key… (not really)');
        setTimeout(() => {
          location.href = '/secret-key/';
        }, 700);
      }
    }
  });

  /* ------------------------------------------------------------------
     8. TOFU tooltip — hover (or keyboard focus inside) the trust-state
     demo for 5 seconds and a fun fact appears.
  ------------------------------------------------------------------ */
  const attachTofuTip = () => {
    const demo = doc.querySelector('[data-tofu-demo]');
    if (!demo) return;
    let timer = null;
    let tip = null;
    const hideTip = () => {
      clearTimeout(timer);
      timer = null;
      if (tip) {
        tip.remove();
        tip = null;
        removeEventListener('scroll', hideTip);
      }
    };
    const showTip = () => {
      if (tip) return;
      tip = doc.createElement('div');
      tip.className = 'tofu-tip';
      tip.setAttribute('role', 'note');
      tip.innerHTML =
        '<span class="tofu-tip-label">TOFU fun fact</span>' +
        '“Trust on first use” is the same model SSH uses: the first key you see ' +
        'is remembered, and you are only warned if it ever changes. RNP adds one ' +
        'ingredient SSH leaves to you — a manual fingerprint check upgrades ' +
        '“first-use trust” to “verified”.';
      doc.body.appendChild(tip);
      // Fixed positioning: the widget has overflow:hidden, so the tip cannot
      // live inside it. Anchored just above the widget, horizontally centered.
      const rect = demo.getBoundingClientRect();
      tip.style.left = `${Math.min(Math.max(rect.left + rect.width / 2, 190), innerWidth - 190)}px`;
      tip.style.top = `${Math.max(rect.top - 10, 8)}px`;
      // A scroll detaches the tip from its anchor — dismiss it instead.
      addEventListener('scroll', hideTip, { passive: true });
      requestAnimationFrame(() => tip?.classList.add('is-visible'));
    };
    demo.addEventListener('pointerenter', () => {
      timer = setTimeout(showTip, 5000);
    });
    demo.addEventListener('pointerleave', hideTip);
    demo.addEventListener('focusin', () => {
      timer = setTimeout(showTip, 5000);
    });
    demo.addEventListener('focusout', (event) => {
      if (!demo.contains(event.relatedTarget)) hideTip();
    });
  };
  attachTofuTip();

  /* ------------------------------------------------------------------
     9. Service worker — offline support in production only.
  ------------------------------------------------------------------ */
  if ('serviceWorker' in navigator && !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) {
    addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js').catch(() => {
        /* offline support is a nice-to-have; fail silently */
      });
    });
  }

  // Initial sync of any reduce-motion toggles rendered into footers.
  syncMotionToggles();
})();
