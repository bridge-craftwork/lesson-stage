import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  // Relative asset URLs: the bundle is served from the root of a custom
  // scheme (lesson-popout://), not from a known absolute path.
  base: './',
  build: {
    outDir: 'dist',
    // One JS file and one CSS file keeps the WKURLSchemeHandler trivial and
    // makes the Xcode resource copy a folder reference rather than a manifest.
    assetsInlineLimit: 0,
    rollupOptions: {
      output: {
        entryFileNames: 'popout.js',
        assetFileNames: 'popout.[ext]',
      },
    },
  },
})
