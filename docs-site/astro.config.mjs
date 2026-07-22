// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import vue from '@astrojs/vue';
import tailwindcss from '@tailwindcss/vite';

// https://astro.build/config
//
// Deploying to GitHub Pages as a *project* site? Set the base path:
//   export default defineConfig({ site: 'https://rnpgp.github.io', base: '/swift-rnp', ... })
// Netlify / Vercel / a custom domain work with the defaults below.
export default defineConfig({
  site: 'https://rnpgp.github.io',
  vite: {
    plugins: [tailwindcss()],
  },
  integrations: [
    starlight({
      title: 'RNP',
      description:
        'RNP brings OpenPGP signing, encryption, and key management to Apple Mail on macOS. Native, sandboxed, and free of telemetry.',
      logo: {
        src: './src/assets/rnp-icon.png',
        alt: 'RNP',
      },
      favicon: '/favicon.svg',
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/rnpgp/swift-rnp' },
      ],
      customCss: ['./src/styles/global.css'],
      components: {
        // Adds back-to-top + reduced-motion toggle to the docs footer.
        Footer: './src/components/overrides/Footer.astro',
      },
      head: [
        // Shared interactivity layer (command palette, easter eggs,
        // scroll-to-top, motion preference). Vanilla JS, deferred.
        {
          tag: 'script',
          attrs: { src: '/js/site.js', defer: true },
        },
      ],
      expressiveCode: {
        styleOverrides: {
          borderRadius: '0.75rem',
          codeFontFamily: "'IBM Plex Mono', ui-monospace, 'SF Mono', Menlo, monospace",
          codeBackground: ({ theme }) => (theme.type === 'dark' ? '#0f1326' : '#f4f8fd'),
        },
      },
      editLink: {
        baseUrl: 'https://github.com/rnpgp/swift-rnp/edit/main/docs-site/',
      },
      sidebar: [
        {
          label: 'Start Here',
          items: [
            { label: 'Installation', slug: 'getting-started/installation' },
            { label: 'First Launch & Onboarding', slug: 'getting-started/first-launch' },
          ],
        },
        {
          label: 'User Guide',
          items: [
            { label: 'Key Management', slug: 'key-management' },
            { label: 'Trust & Verification', slug: 'trust-verification' },
            { label: 'Keyservers', slug: 'keyserver' },
            { label: 'Using with Mail', slug: 'using-with-mail' },
          ],
        },
        {
          label: 'Help & Reference',
          items: [
            { label: 'Security & Privacy', slug: 'security' },
            { label: 'Troubleshooting', slug: 'troubleshooting' },
            { label: 'FAQ', slug: 'faq' },
          ],
        },
      ],
    }),
    vue(),
  ],
});
