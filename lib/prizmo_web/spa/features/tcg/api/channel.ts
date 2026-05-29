import { Channel, Socket } from 'phoenix'

export type TcgDeck = {
  id: string
  name: string
  sourceUrl: string
  cardCount: number
  counts: Array<{ cardId: string; count: number }>
}

export type CardDisplay = {
  id: string
  name: string
  supertype: string | null
  type: string | null
  types: string[]
  hp: number | null
  stage: string | null
  trainerType: string | null
  energyType: string | null
  image: string | null
  imageLow: string | null
  imageHigh: string | null
  attacks: Array<{ id: string; name: string; damage: string | number | null; cost: string[]; text: string | null }>
  abilities: Array<{ id: string; name: string; text: string | null }>
}

export type CardInstance = {
  instanceId: string
  cardId: string
  owner: string
  lifecycle: string
  zone: string
  damage: number
  status: string | null
  turnEnteredPlay: number | null
  attachments: CardInstance[]
  tool: CardInstance | null
  evolvedFrom: CardInstance[]
  card: CardDisplay
}

export type PlayerView = {
  id: string
  expectedCardCount: number | null
  deckCount: number
  hand: CardInstance[]
  prizes: CardInstance[]
  prizeCount: number
  discard: CardInstance[]
  discardCount: number
  lostZone: CardInstance[]
  active: CardInstance | null
  bench: CardInstance[]
  mulligansTaken: number
  mulliganBonusDrawsTaken: number
  markers: string[]
  flags: Record<string, boolean>
}

export type GameStateView = {
  activePlayer: string | null
  firstPlayer: string | null
  gameLifecycle: string
  turnLifecycle: string
  promptLifecycle: string
  turnNumber: number
  winner: string | null
  stadium: CardInstance | null
  pendingPrompts: unknown
  pendingAttack: unknown
  pendingPrizes: unknown
  log: string[]
  players: Record<string, PlayerView>
}

export type GamePayload = { gameId: string; state: GameStateView }
export type ActionPayload = { type: string; playerId?: string; params?: Record<string, unknown> }

let socket: Socket | null = null

export function getTcgSocket() {
  if (!socket) {
    socket = new Socket('/socket')
    socket.connect()
  }

  return socket
}

export function joinChannel(topic: string, params: Record<string, unknown> = {}) {
  const channel = getTcgSocket().channel(topic, params)
  return channel
}

export function join<T>(channel: Channel) {
  return pushJoin<T>(channel)
}

export function push<T>(channel: Channel, event: string, payload: Record<string, unknown> = {}) {
  return new Promise<T>((resolve, reject) => {
    channel
      .push(event, payload, 10_000)
      .receive('ok', (response: T) => resolve(response))
      .receive('error', (response: unknown) => reject(response))
      .receive('timeout', () => reject({ reason: 'timeout' }))
  })
}

function pushJoin<T>(channel: Channel) {
  return new Promise<T>((resolve, reject) => {
    channel
      .join(10_000)
      .receive('ok', (response: T) => resolve(response))
      .receive('error', (response: unknown) => reject(response))
      .receive('timeout', () => reject({ reason: 'timeout' }))
  })
}
