import React from 'react'
import { createRoot, type Root } from 'react-dom/client'

import { MainProvider } from '@/providers/main_provider'

declare global {
  interface Window {
    __prizmoRoot?: Root
  }
}

const root = (window.__prizmoRoot ??= createRoot(document.getElementById('app')!))

function render() {
  root.render(
    <React.StrictMode>
      <MainProvider />
    </React.StrictMode>
  )
}

render()
