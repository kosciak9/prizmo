import { Link, Outlet, createRootRoute, createRoute, createRouter } from '@tanstack/react-router'

import { HomeRoute } from '@/features/home/routes'
import { TcgRoute } from '@/features/tcg/routes'

function NotFoundRoute() {
  return (
    <main className="grid min-h-screen place-items-center">
      <div className="text-center">
        <p>Page not found.</p>
        <Link to="/">Go home</Link>
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
  component: HomeRoute
})

const tcgRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/tcg',
  component: TcgRoute
})

const routeTree = rootRoute.addChildren([indexRoute, tcgRoute])

export const router = createRouter({ routeTree })

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}
