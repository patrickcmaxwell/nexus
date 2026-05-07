/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  // Keep face-api / tfjs / sharp as runtime requires — Turbopack's static
  // analysis trips on their internal optional deps and inflates the bundle.
  serverExternalPackages: ["@vladmandic/face-api", "@tensorflow/tfjs", "sharp"],
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          {
            key: "Content-Security-Policy",
            value: [
              "default-src 'self'",
              "script-src 'self' 'unsafe-eval' 'unsafe-inline'",
              "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
              "font-src 'self' https://fonts.gstatic.com",
              "connect-src 'self' https://cdn.jsdelivr.net https://raw.githubusercontent.com https://*.supabase.co https://api.x.ai wss://*.supabase.co",
              "media-src 'self' blob: mediastream:",
              "img-src 'self' data: blob:",
              "worker-src 'self' blob:",
            ].join("; "),
          },
        ],
      },
    ]
  },
}

export default nextConfig
