import type { Metadata } from 'next'
import { Inter, JetBrains_Mono } from 'next/font/google'
import { Analytics } from '@vercel/analytics/next'
import './globals.css'

const inter = Inter({ subsets: ['latin'], variable: '--font-inter' })
const jetbrainsMono = JetBrains_Mono({ subsets: ['latin'], variable: '--font-jetbrains-mono' })

export const metadata: Metadata = {
  title: 'Nexus',
  description: 'Nexus — Operational Command Platform',
  icons: {
    icon: [
      { url: '/icon-light-32x32.png', media: '(prefers-color-scheme: light)' },
      { url: '/icon-dark-32x32.png',  media: '(prefers-color-scheme: dark)' },
      { url: '/icon.svg',             type: 'image/svg+xml' },
    ],
    apple: '/apple-icon.png',
  },
}

// Theme init runs before paint to prevent FOUC. React 19 / Next 16 stopped
// silently allowing inline `<Script>` children without warning, so use the
// supported `dangerouslySetInnerHTML` escape hatch and inline in <head> so
// SSR ships it before <body> parses.
const themeInitScript = `(function(){try{var p=JSON.parse(localStorage.getItem('nexus_theme')||'{}');var isDark=p.colorMode==='dark'||(p.colorMode!=='light'&&window.matchMedia('(prefers-color-scheme: dark)').matches);var ui=p.uiMode||'futuristic';var h=document.documentElement;if(!isDark)h.classList.add('light');else h.classList.remove('light');h.setAttribute('data-ui',ui);}catch(e){}})();`

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${jetbrainsMono.variable} bg-background`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
      </head>
      <body className="font-sans antialiased bg-background text-foreground">
        {children}
        {process.env.NODE_ENV === 'production' && <Analytics />}
      </body>
    </html>
  )
}
