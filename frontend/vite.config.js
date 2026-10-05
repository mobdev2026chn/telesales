import react from '@vitejs/plugin-react'
import { defineConfig, loadEnv } from 'vite'

// https://vite.dev/config/
// In development every /api request is proxied to the Express backend (port 5000), so the React
// portal talks to the same API as admin_web/index.html without any CORS or backend change.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const target = env.VITE_BACKEND_URL || 'http://localhost:5000'

  return {
    plugins: [react()],
    server: {
      port: 5173,
      proxy: {
        '/socket.io': {
          target,
          changeOrigin: true,
          ws: true,
        },
        '/api': {
          target,
          changeOrigin: true,
          configure: (proxy) => {
            // Backend down: answer like the API does, so the portal shows a clear message
            proxy.on('error', (_err, _req, res) => {
              if (res && !res.headersSent && typeof res.writeHead === 'function') {
                res.writeHead(503, { 'Content-Type': 'application/json' })
                res.end(JSON.stringify({ success: false, message: `Could not reach the backend at ${target} — is it running?` }))
              }
            })
          },
        },
      },
    },
  }
})
