// Build do jogo: saída em dist/ (Cloudflare Pages roda "npm run build" e publica dist/)
import { defineConfig } from 'vitest/config';

export default defineConfig({
  build: { outDir: 'dist', assetsInlineLimit: 0, chunkSizeWarningLimit: 2000 },
  test: { include: ['tests/**/*.test.ts'] },
});
