import { Link, Outlet, createRootRoute, createRoute, createRouter } from '@tanstack/react-router'

import { HomeRoute } from '@/features/home/routes'

function NotFoundRoute() {
  return (
    <main className="grid min-h-screen place-items-center">
      <div className="text-center">
        <p>Page not found.</p>
        <Link search={{ gameId: '', viewerPlayerId: 'player_1' }} to="/">
          Go home
        </Link>
      </div>
    </main>
  )
}

const rootRoute = createRootRoute({
  component: Outlet,
  notFoundComponent: NotFoundRoute
})

const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  validateSearch: search => ({
    gameId: typeof search.gameId === 'string' ? search.gameId : '',
    viewerPlayerId: search.viewerPlayerId === 'player_2' ? 'player_2' : 'player_1'
  }),
  component: HomeRoute
})

const routeTree = rootRoute.addChildren([indexRoute])

export const router = createRouter({ routeTree })

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}
