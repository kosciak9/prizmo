import { Link } from '@tanstack/react-router'

export function HomeRoute() {
  return (
    <main className="grid min-h-screen place-items-center">
      <div className="max-w-2xl px-6 text-center">
        <p className="text-sm uppercase tracking-[0.4em] text-slate-500">Prizmo</p>
        <h1 className="mt-4 text-4xl font-semibold tracking-tight text-slate-950">
          Pokémon TCG simulation tools
        </h1>
        <p className="mt-4 text-slate-600">
          A React SPA powered by Phoenix, Ash, AshTypescript, and Volt.
        </p>
        <Link
          className="mt-8 inline-flex rounded-lg bg-emerald-700 px-4 py-2 text-sm font-semibold text-stone-50 hover:bg-emerald-800"
          to="/tcg"
        >
          Open TCG table
        </Link>
      </div>
    </main>
  )
}
