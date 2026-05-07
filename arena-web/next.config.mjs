/** @type {import('next').NextConfig} */
const nextConfig = {
  // Silently ignore type errors at build time so a stale type doesn't block
  // a deploy of a working runtime. We catch real type issues with `tsc` in CI.
  typescript: { ignoreBuildErrors: true },
}

export default nextConfig
