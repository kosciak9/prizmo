interface ImportMetaEnv {
  readonly DEV: boolean
  readonly PROD: boolean
  readonly MODE: string
}

interface ImportMetaHot {
  accept(callback?: () => void): void
}

interface ImportMeta {
  readonly env: ImportMetaEnv
  readonly hot?: ImportMetaHot
}
