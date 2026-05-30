import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useMemo, useState } from 'react'

import {
  buildAshRpcHeaders,
  runChooseTcgEngineActiveFromHand,
  runChooseTcgEngineSetupBenchFromHand,
  runCompleteTcgEngineSetup,
  runCreateTcgEngineGame,
  runDrawTcgEngineCardForTurn,
  runDrawTcgEngineOpeningHand,
  runGetTcgEngineGameState,
  runListSupportedTcgDecks,
  runPlaceTcgEnginePrizes,
  runSkipTcgEngineDrawForTurn,
  runStartNextTcgEngineTurn,
  runStartTcgEngineSetup,
  type CreateTcgEngineGameFields,
  type GetTcgEngineGameStateFields,
  type ListSupportedTcgDecksFields
} from '@/lib/ash/client'

const PLAYER_ONE_ID = 'player_1'
const PLAYER_TWO_ID = 'player_2'
const PLAYER_IDS = [PLAYER_ONE_ID, PLAYER_TWO_ID] as const
const SESSION_STORAGE_KEY = 'prizmo:tcg-playtest-session'

const SUPPORTED_DECK_FIELDS: ListSupportedTcgDecksFields = [
  'deckKey',
  'name',
  'sourceUrl',
  'cardCount',
  'uniqueCardCount'
]

const GAME_RESOURCE_FIELDS: CreateTcgEngineGameFields = [
  'id',
  'status',
  'activePlayerId',
  'firstPlayerId',
  'winnerPlayerId',
  'cursorIndex',
  'latestEventIndex'
]

const CARD_SUMMARY_FIELDS = [
  'id',
  'instanceId',
  'cardId',
  'name',
  'image',
  'category',
  'stage',
  'ownerPlayerId',
  'zone',
  'position',
  'damage',
  'status',
  'attachedToCardInstanceId',
  'evolvesFromCardInstanceId',
  'turnEnteredPlay'
] as const

const GAME_STATE_FIELDS = [
  'gameId',
  'viewerPlayerId',
  'status',
  'activePlayerId',
  'firstPlayerId',
  'winnerPlayerId',
  'cursorIndex',
  'latestEventIndex',
  { setup: ['id', 'status'] },
  {
    currentTurn: [
      'id',
      'turnNumber',
      'activePlayerId',
      'status',
      'visible',
      'pendingAttackId',
      'pendingAttackerCardInstanceId',
      'pendingDefenderCardInstanceId'
    ]
  },
  { stadium: [...CARD_SUMMARY_FIELDS] },
  {
    players: [
      'playerId',
      'deckKey',
      'energyAttachedThisTurn',
      'supporterPlayedThisTurn',
      'retreatedThisTurn',
      'aceSpecPlayedThisGame',
      'deckCount',
      'handCount',
      'prizeCount',
      'discardCount',
      { active: [...CARD_SUMMARY_FIELDS] },
      { bench: [...CARD_SUMMARY_FIELDS] },
      { hand: [...CARD_SUMMARY_FIELDS] },
      { discard: [...CARD_SUMMARY_FIELDS] }
    ]
  },
  { events: ['id', 'index', 'type', 'playerId', 'turnId'] },
  { prompts: ['id', 'promptType', 'status', 'playerId', 'payload'] }
] as unknown as GetTcgEngineGameStateFields

type PlayerId = (typeof PLAYER_IDS)[number]

type PlaytestSession = {
  gameId: string
  viewerPlayerId: PlayerId
}

type RpcError = {
  message?: string
  shortMessage?: string
  type?: string
}

type SupportedDeck = {
  deckKey: string
  name: string
  sourceUrl: string
  cardCount: number
  uniqueCardCount: number
}

type CreatedGame = {
  id: string
  status: string
  activePlayerId: string
  firstPlayerId: string
  winnerPlayerId: string | null
  cursorIndex: number
  latestEventIndex: number
}

type CardSummary = {
  id: string
  instanceId: string
  cardId: string
  name: string
  image: string | null
  category: string | null
  stage: string | null
  ownerPlayerId: string
  zone: string
  position: number
  damage: number
  status: string | null
  attachedToCardInstanceId: string | null
  evolvesFromCardInstanceId: string | null
  turnEnteredPlay: number | null
}

type PlayerView = {
  playerId: string
  deckKey: string
  energyAttachedThisTurn: boolean
  supporterPlayedThisTurn: boolean
  retreatedThisTurn: boolean
  aceSpecPlayedThisGame: boolean
  deckCount: number
  handCount: number
  prizeCount: number
  discardCount: number
  active: CardSummary | null
  bench: CardSummary[]
  hand: CardSummary[]
  discard: CardSummary[]
}

type GameState = {
  gameId: string
  viewerPlayerId: string
  status: string
  activePlayerId: string
  firstPlayerId: string
  winnerPlayerId: string | null
  cursorIndex: number
  latestEventIndex: number
  setup: { id: string; status: string } | null
  currentTurn: {
    id: string
    turnNumber: number
    activePlayerId: string
    status: string
    visible: boolean
    pendingAttackId: string | null
    pendingAttackerCardInstanceId: string | null
    pendingDefenderCardInstanceId: string | null
  } | null
  stadium: CardSummary | null
  players: PlayerView[]
  events: Array<{
    id: string
    index: number
    type: string
    playerId: string | null
    turnId: string | null
  }>
  prompts: Array<{
    id: string
    promptType: string
    status: string
    playerId: string
    payload: Record<string, unknown>
  }>
}

export function HomeRoute() {
  const queryClient = useQueryClient()
  const [session, setSession] = useState<PlaytestSession>(readStoredSession)
  const [playerOneDeckKey, setPlayerOneDeckKey] = useState('')
  const [playerTwoDeckKey, setPlayerTwoDeckKey] = useState('')

  const decksQuery = useQuery({
    queryKey: ['tcg-engine', 'supported-decks'],
    queryFn: listSupportedDecks
  })

  const decks = decksQuery.data ?? []
  const selectedPlayerOneDeckKey = playerOneDeckKey || decks[0]?.deckKey || ''
  const selectedPlayerTwoDeckKey = playerTwoDeckKey || decks[1]?.deckKey || decks[0]?.deckKey || ''
  const normalisedGameId = session.gameId.trim()

  const gameStateQuery = useQuery({
    queryKey: ['tcg-engine', 'game-state', normalisedGameId, session.viewerPlayerId],
    queryFn: () => getGameState(normalisedGameId, session.viewerPlayerId),
    enabled: normalisedGameId.length > 0,
    refetchOnWindowFocus: false
  })

  const createGameMutation = useMutation({
    mutationFn: () =>
      createGame({
        playerOneDeckKey: selectedPlayerOneDeckKey,
        playerTwoDeckKey: selectedPlayerTwoDeckKey
      }),
    onSuccess: async game => {
      const nextSession = {
        gameId: game.id,
        viewerPlayerId: session.viewerPlayerId
      }

      setStoredSession(nextSession)
      setSession(nextSession)

      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const startSetupMutation = useMutation({
    mutationFn: (gameId: string) => startSetup(gameId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const drawOpeningHandMutation = useMutation({
    mutationFn: (gameId: string) => drawOpeningHand(gameId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const chooseActiveMutation = useMutation({
    mutationFn: (input: { gameId: string; playerId: PlayerId; cardInstanceId: string }) => chooseActiveFromHand(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const chooseSetupBenchMutation = useMutation({
    mutationFn: (input: { gameId: string; playerId: PlayerId; cardInstanceId: string }) =>
      chooseSetupBenchFromHand(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const placePrizesMutation = useMutation({
    mutationFn: (gameId: string) => placePrizes(gameId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const completeSetupMutation = useMutation({
    mutationFn: (gameId: string) => completeSetup(gameId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const startNextTurnMutation = useMutation({
    mutationFn: (gameId: string) => startNextTurn(gameId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const drawForTurnMutation = useMutation({
    mutationFn: (input: { gameId: string; playerId: PlayerId }) => drawCardForTurn(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const skipDrawForTurnMutation = useMutation({
    mutationFn: (input: { gameId: string; playerId: PlayerId }) => skipDrawForTurn(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const gameState = gameStateQuery.data
  const viewerPlayer = gameState?.players.find(player => player.playerId === gameState.viewerPlayerId)
  const currentTurnActivePlayerId = gameState?.currentTurn?.activePlayerId
  const setupActiveCandidates = viewerPlayer?.hand.filter(isSetupActiveCandidate) ?? []
  const setupBenchCandidates = viewerPlayer?.hand.filter(isSetupBenchCandidate) ?? []
  const allPlayersHaveSetupActive = gameState?.players.every(player => player.active) ?? false
  const setupPrizesAreUnplaced = gameState?.players.every(player => player.prizeCount === 0) ?? false
  const deckNamesByKey = useMemo(
    () => new Map(decks.map(deck => [deck.deckKey, deck.name])),
    [decks]
  )
  const canCreateGame =
    Boolean(selectedPlayerOneDeckKey && selectedPlayerTwoDeckKey) && !createGameMutation.isPending
  const canStartSetup =
    Boolean(normalisedGameId && gameState && !gameState.setup) && !startSetupMutation.isPending
  const canDrawOpeningHand =
    Boolean(normalisedGameId && gameState?.setup?.status === 'waiting_to_draw') && !drawOpeningHandMutation.isPending
  const canChooseSetupActive =
    Boolean(
      normalisedGameId &&
        gameState?.setup?.status === 'hands_drawn' &&
        viewerPlayer &&
        !viewerPlayer.active &&
        setupActiveCandidates.length > 0
    ) && !chooseActiveMutation.isPending
  const canChooseSetupBench =
    Boolean(
      normalisedGameId &&
        gameState?.setup?.status === 'hands_drawn' &&
        viewerPlayer &&
        viewerPlayer.active &&
        viewerPlayer.bench.length < 5 &&
        setupBenchCandidates.length > 0
    ) && !chooseSetupBenchMutation.isPending
  const canPlacePrizes =
    Boolean(
      normalisedGameId &&
        gameState?.setup?.status === 'hands_drawn' &&
        allPlayersHaveSetupActive &&
        setupPrizesAreUnplaced
    ) && !placePrizesMutation.isPending
  const canCompleteSetup =
    Boolean(normalisedGameId && gameState?.setup?.status === 'prizes_placed') && !completeSetupMutation.isPending
  const canStartNextTurn =
    Boolean(
      normalisedGameId &&
        gameState?.status === 'in_progress' &&
        gameState.setup?.status === 'completed' &&
        !gameState.currentTurn
    ) && !startNextTurnMutation.isPending
  const canDrawForTurn =
    Boolean(
      normalisedGameId &&
        gameState?.status === 'in_progress' &&
        gameState.currentTurn?.status === 'start' &&
        currentTurnActivePlayerId &&
        isPlayerId(currentTurnActivePlayerId)
    ) &&
    !drawForTurnMutation.isPending &&
    !skipDrawForTurnMutation.isPending
  const canSkipDrawForTurn =
    Boolean(
      normalisedGameId &&
        gameState?.status === 'in_progress' &&
        gameState.currentTurn?.status === 'start' &&
        currentTurnActivePlayerId &&
        isPlayerId(currentTurnActivePlayerId)
    ) &&
    !drawForTurnMutation.isPending &&
    !skipDrawForTurnMutation.isPending

  function updateSession(nextSession: PlaytestSession) {
    setStoredSession(nextSession)
    setSession(nextSession)
  }

  function clearGame() {
    updateSession({ ...session, gameId: '' })
    queryClient.removeQueries({ queryKey: ['tcg-engine', 'game-state'] })
  }

  return (
    <main className="min-h-screen bg-stone-50 text-stone-950">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-8 px-5 py-6 sm:px-8 lg:px-10">
        <header className="flex flex-col gap-5 border-b border-stone-200 pb-6 lg:flex-row lg:items-end lg:justify-between">
          <div className="max-w-3xl">
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-stone-500">
              Prizmo TCG engine
            </p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight text-stone-950 sm:text-4xl">
              Ash-backed playtest console
            </h1>
            <p className="mt-3 max-w-2xl text-sm leading-6 text-stone-600">
              Create a supported fixture game, reconnect by game ID, and inspect the viewer-scoped
              board state returned by the persisted engine.
            </p>
          </div>

          <div className="rounded-2xl border border-stone-200 bg-stone-100 px-4 py-3 text-sm text-stone-700">
            <p className="font-medium text-stone-950">Current viewer</p>
            <p className="mt-1 font-mono text-xs">{session.viewerPlayerId}</p>
          </div>
        </header>

        <section className="grid gap-5 lg:grid-cols-[minmax(18rem,24rem)_1fr]">
          <aside className="flex flex-col gap-5">
            <Panel title="Create or reconnect">
              <div className="space-y-4">
                {decksQuery.isPending ? <SkeletonLines count={3} /> : null}

                {decksQuery.error ? (
                  <InlineNotice tone="error" title="Deck fixtures did not load">
                    {errorMessage(decksQuery.error)}
                  </InlineNotice>
                ) : null}

                {!decksQuery.isPending && decks.length === 0 ? (
                  <InlineNotice tone="info" title="No supported decks exposed yet">
                    The engine RPC returned an empty fixture list.
                  </InlineNotice>
                ) : null}

                <DeckSelect
                  label="Player 1 deck"
                  value={selectedPlayerOneDeckKey}
                  decks={decks}
                  onChange={setPlayerOneDeckKey}
                />
                <DeckSelect
                  label="Player 2 deck"
                  value={selectedPlayerTwoDeckKey}
                  decks={decks}
                  onChange={setPlayerTwoDeckKey}
                />

                <fieldset className="space-y-2">
                  <legend className="text-sm font-medium text-stone-800">View as</legend>
                  <div className="grid grid-cols-2 gap-2">
                    {PLAYER_IDS.map(playerId => (
                      <label
                        className="flex cursor-pointer items-center justify-between rounded-xl border border-stone-200 bg-stone-50 px-3 py-2 text-sm text-stone-700 has-[:checked]:border-emerald-500 has-[:checked]:bg-emerald-50 has-[:checked]:text-emerald-950"
                        key={playerId}
                      >
                        <span>{formatPlayerId(playerId)}</span>
                        <input
                          checked={session.viewerPlayerId === playerId}
                          className="h-4 w-4 accent-emerald-600"
                          name="viewer-player"
                          onChange={() => updateSession({ ...session, viewerPlayerId: playerId })}
                          type="radio"
                        />
                      </label>
                    ))}
                  </div>
                </fieldset>

                <button
                  className="w-full rounded-xl bg-emerald-700 px-4 py-2.5 text-sm font-semibold text-stone-50 shadow-sm transition hover:bg-emerald-800 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-stone-300 disabled:text-stone-600"
                  disabled={!canCreateGame}
                  onClick={() => createGameMutation.mutate()}
                  type="button"
                >
                  {createGameMutation.isPending ? 'Creating game...' : 'Create fixture game'}
                </button>

                {createGameMutation.error ? (
                  <InlineNotice tone="error" title="Game creation failed">
                    {errorMessage(createGameMutation.error)}
                  </InlineNotice>
                ) : null}

                <label className="block space-y-2">
                  <span className="text-sm font-medium text-stone-800">Reconnect to game ID</span>
                  <input
                    className="w-full rounded-xl border border-stone-300 bg-stone-50 px-3 py-2 font-mono text-sm text-stone-950 outline-none transition placeholder:text-stone-400 focus:border-emerald-600 focus:ring-2 focus:ring-emerald-100"
                    onChange={event => updateSession({ ...session, gameId: event.currentTarget.value })}
                    placeholder="Paste a persisted game UUID"
                    type="text"
                    value={session.gameId}
                  />
                </label>

                <div className="flex gap-2">
                  <button
                    className="flex-1 rounded-xl border border-stone-300 px-3 py-2 text-sm font-medium text-stone-700 transition hover:bg-stone-100 focus:outline-none focus:ring-2 focus:ring-stone-300 disabled:cursor-not-allowed disabled:text-stone-400"
                    disabled={!normalisedGameId || gameStateQuery.isFetching}
                    onClick={() => gameStateQuery.refetch()}
                    type="button"
                  >
                    {gameStateQuery.isFetching ? 'Refreshing...' : 'Refresh state'}
                  </button>
                  <button
                    className="rounded-xl border border-stone-300 px-3 py-2 text-sm font-medium text-stone-700 transition hover:bg-stone-100 focus:outline-none focus:ring-2 focus:ring-stone-300 disabled:cursor-not-allowed disabled:text-stone-400"
                    disabled={!session.gameId}
                    onClick={clearGame}
                    type="button"
                  >
                    Clear
                  </button>
                </div>

                <div className="rounded-2xl border border-stone-200 bg-stone-50 p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-sm font-medium text-stone-950">Setup commands</p>
                      <p className="mt-1 text-xs leading-5 text-stone-500">
                        Advance setup through Ash RPC, then refresh the viewer-scoped state.
                      </p>
                    </div>
                    <StatusBadge tone={gameState?.setup ? 'active' : 'neutral'}>
                      {gameState?.setup?.status ?? 'not started'}
                    </StatusBadge>
                  </div>

                  <div className="mt-3 space-y-2">
                    <button
                      className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                      disabled={!canStartSetup}
                      onClick={() => startSetupMutation.mutate(normalisedGameId)}
                      type="button"
                    >
                      {startSetupMutation.isPending
                        ? 'Starting setup...'
                        : gameState?.setup
                          ? 'Setup already started'
                          : 'Start setup'}
                    </button>
                    <button
                      className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                      disabled={!canDrawOpeningHand}
                      onClick={() => drawOpeningHandMutation.mutate(normalisedGameId)}
                      type="button"
                    >
                      {drawOpeningHandMutation.isPending
                        ? 'Drawing hands...'
                        : gameState?.setup?.status === 'waiting_to_draw'
                          ? 'Draw opening hands'
                          : gameState?.setup
                            ? 'Opening hands resolved'
                            : 'Start setup first'}
                    </button>
                    <div className="rounded-xl border border-stone-200 bg-stone-50 p-3">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="text-sm font-medium text-stone-950">Choose setup Active</p>
                          <p className="mt-1 text-xs leading-5 text-stone-500">
                            Select a Basic Pokémon from {formatPlayerId(session.viewerPlayerId)}'s hand.
                          </p>
                        </div>
                        <StatusBadge tone={viewerPlayer?.active ? 'active' : 'neutral'}>
                          {viewerPlayer?.active ? 'chosen' : 'pending'}
                        </StatusBadge>
                      </div>

                      {gameState?.setup?.status === 'hands_drawn' && viewerPlayer && !viewerPlayer.active ? (
                        setupActiveCandidates.length > 0 ? (
                          <div className="mt-3 space-y-2">
                            {setupActiveCandidates.map(card => (
                              <button
                                className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                                disabled={!canChooseSetupActive}
                                key={card.id}
                                onClick={() =>
                                  chooseActiveMutation.mutate({
                                    gameId: normalisedGameId,
                                    playerId: session.viewerPlayerId,
                                    cardInstanceId: card.id
                                  })
                                }
                                type="button"
                              >
                                {chooseActiveMutation.isPending ? 'Choosing Active...' : `Choose ${card.name}`}
                              </button>
                            ))}
                          </div>
                        ) : (
                          <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                            No Basic Pokémon are visible in this viewer's hand.
                          </p>
                        )
                      ) : (
                        <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                          Draw opening hands, then view a player without an Active Pokémon to choose one.
                        </p>
                      )}
                    </div>

                    <div className="rounded-xl border border-stone-200 bg-stone-50 p-3">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="text-sm font-medium text-stone-950">Choose setup Bench</p>
                          <p className="mt-1 text-xs leading-5 text-stone-500">
                            Optionally bench Basic Pokémon from {formatPlayerId(session.viewerPlayerId)}'s hand.
                          </p>
                        </div>
                        <StatusBadge tone={viewerPlayer?.bench.length ? 'active' : 'neutral'}>
                          {viewerPlayer?.bench.length ?? 0}/5
                        </StatusBadge>
                      </div>

                      {gameState?.setup?.status === 'hands_drawn' && viewerPlayer && viewerPlayer.active ? (
                        viewerPlayer.bench.length >= 5 ? (
                          <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                            This viewer's Bench is full.
                          </p>
                        ) : setupBenchCandidates.length > 0 ? (
                          <div className="mt-3 space-y-2">
                            {setupBenchCandidates.map(card => (
                              <button
                                className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                                disabled={!canChooseSetupBench}
                                key={card.id}
                                onClick={() =>
                                  chooseSetupBenchMutation.mutate({
                                    gameId: normalisedGameId,
                                    playerId: session.viewerPlayerId,
                                    cardInstanceId: card.id
                                  })
                                }
                                type="button"
                              >
                                {chooseSetupBenchMutation.isPending ? 'Benching Pokémon...' : `Bench ${card.name}`}
                              </button>
                            ))}
                          </div>
                        ) : (
                          <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                            No additional Basic Pokémon are visible in this viewer's hand.
                          </p>
                        )
                      ) : (
                        <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                          Draw opening hands and choose this viewer's Active Pokémon before benching setup Pokémon.
                        </p>
                      )}
                    </div>

                    <button
                      className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                      disabled={!canPlacePrizes}
                      onClick={() => placePrizesMutation.mutate(normalisedGameId)}
                      type="button"
                    >
                      {placePrizesMutation.isPending
                        ? 'Placing prizes...'
                        : gameState?.setup?.status === 'prizes_placed'
                          ? 'Prizes placed'
                          : gameState?.setup?.status === 'hands_drawn'
                            ? allPlayersHaveSetupActive
                              ? 'Place setup prizes'
                              : 'Choose both Active Pokémon first'
                            : 'Choose Active Pokémon first'}
                    </button>
                    <button
                      className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                      disabled={!canCompleteSetup}
                      onClick={() => completeSetupMutation.mutate(normalisedGameId)}
                      type="button"
                    >
                      {completeSetupMutation.isPending
                        ? 'Completing setup...'
                        : gameState?.setup?.status === 'prizes_placed'
                          ? 'Complete setup'
                          : gameState?.setup?.status === 'completed'
                            ? 'Setup completed'
                            : 'Place prizes first'}
                    </button>
                  </div>
                </div>

                {startSetupMutation.error ? (
                  <InlineNotice tone="error" title="Setup command failed">
                    {errorMessage(startSetupMutation.error)}
                  </InlineNotice>
                ) : null}

                {drawOpeningHandMutation.error ? (
                  <InlineNotice tone="error" title="Opening hand command failed">
                    {errorMessage(drawOpeningHandMutation.error)}
                  </InlineNotice>
                ) : null}

                {chooseActiveMutation.error ? (
                  <InlineNotice tone="error" title="Active choice command failed">
                    {errorMessage(chooseActiveMutation.error)}
                  </InlineNotice>
                ) : null}

                {chooseSetupBenchMutation.error ? (
                  <InlineNotice tone="error" title="Bench choice command failed">
                    {errorMessage(chooseSetupBenchMutation.error)}
                  </InlineNotice>
                ) : null}

                {placePrizesMutation.error ? (
                  <InlineNotice tone="error" title="Prize placement command failed">
                    {errorMessage(placePrizesMutation.error)}
                  </InlineNotice>
                ) : null}

                {completeSetupMutation.error ? (
                  <InlineNotice tone="error" title="Setup completion command failed">
                    {errorMessage(completeSetupMutation.error)}
                  </InlineNotice>
                ) : null}

                <div className="rounded-2xl border border-stone-200 bg-stone-50 p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-sm font-medium text-stone-950">Turn commands</p>
                      <p className="mt-1 text-xs leading-5 text-stone-500">
                        Start the first persisted turn, then draw or skip draw for the active player.
                      </p>
                    </div>
                    <StatusBadge tone={gameState?.currentTurn ? 'active' : 'neutral'}>
                      {gameState?.currentTurn
                        ? `turn ${gameState.currentTurn.turnNumber}: ${gameState.currentTurn.status}`
                        : 'no turn'}
                    </StatusBadge>
                  </div>

                  <button
                    className="mt-3 w-full rounded-xl border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                    disabled={!canStartNextTurn}
                    onClick={() => startNextTurnMutation.mutate(normalisedGameId)}
                    type="button"
                  >
                    {startNextTurnMutation.isPending
                      ? 'Starting turn...'
                      : gameState?.currentTurn
                        ? `Turn ${gameState.currentTurn.turnNumber} started`
                        : gameState?.setup?.status === 'completed'
                          ? 'Start first turn'
                          : 'Complete setup first'}
                  </button>
                  <button
                    className="mt-2 w-full rounded-xl border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                    disabled={!canDrawForTurn}
                    onClick={() => {
                      if (currentTurnActivePlayerId && isPlayerId(currentTurnActivePlayerId)) {
                        drawForTurnMutation.mutate({
                          gameId: normalisedGameId,
                          playerId: currentTurnActivePlayerId
                        })
                      }
                    }}
                    type="button"
                  >
                    {drawForTurnMutation.isPending
                      ? 'Drawing for turn...'
                      : gameState?.currentTurn?.status === 'start'
                        ? `Draw for ${formatPlayerId(gameState.currentTurn.activePlayerId)}`
                        : gameState?.currentTurn?.status === 'drawn'
                          ? 'Draw for turn resolved'
                          : gameState?.currentTurn
                            ? 'Turn is not in draw step'
                            : 'Start first turn first'}
                  </button>
                  <button
                    className="mt-2 w-full rounded-xl border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                    disabled={!canSkipDrawForTurn}
                    onClick={() => {
                      if (currentTurnActivePlayerId && isPlayerId(currentTurnActivePlayerId)) {
                        skipDrawForTurnMutation.mutate({
                          gameId: normalisedGameId,
                          playerId: currentTurnActivePlayerId
                        })
                      }
                    }}
                    type="button"
                  >
                    {skipDrawForTurnMutation.isPending
                      ? 'Skipping draw...'
                      : gameState?.currentTurn?.status === 'start'
                        ? `Skip draw for ${formatPlayerId(gameState.currentTurn.activePlayerId)}`
                        : gameState?.currentTurn?.status === 'action_window'
                          ? 'Draw step skipped'
                          : gameState?.currentTurn
                            ? 'Turn is not in draw step'
                            : 'Start first turn first'}
                  </button>
                </div>

                {startNextTurnMutation.error ? (
                  <InlineNotice tone="error" title="Turn start command failed">
                    {errorMessage(startNextTurnMutation.error)}
                  </InlineNotice>
                ) : null}

                {drawForTurnMutation.error ? (
                  <InlineNotice tone="error" title="Draw for turn command failed">
                    {errorMessage(drawForTurnMutation.error)}
                  </InlineNotice>
                ) : null}

                {skipDrawForTurnMutation.error ? (
                  <InlineNotice tone="error" title="Skip draw command failed">
                    {errorMessage(skipDrawForTurnMutation.error)}
                  </InlineNotice>
                ) : null}
              </div>
            </Panel>

            <Panel title="Supported decks">
              <div className="space-y-3">
                {decks.map(deck => (
                  <div className="rounded-xl border border-stone-200 bg-stone-50 p-3" key={deck.deckKey}>
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="text-sm font-medium text-stone-950">{deck.name}</p>
                        <p className="mt-1 font-mono text-xs text-stone-500">{deck.deckKey}</p>
                      </div>
                      <p className="text-xs text-stone-500">{deck.uniqueCardCount} unique</p>
                    </div>
                    <a
                      className="mt-2 inline-flex text-xs font-medium text-emerald-700 hover:text-emerald-900"
                      href={deck.sourceUrl}
                      rel="noreferrer"
                      target="_blank"
                    >
                      Source decklist
                    </a>
                  </div>
                ))}
              </div>
            </Panel>
          </aside>

          <section className="min-w-0">
            {!normalisedGameId ? (
              <EmptyWorkbench />
            ) : gameStateQuery.isPending ? (
              <Panel title="Loading game state">
                <SkeletonLines count={8} />
              </Panel>
            ) : gameStateQuery.error ? (
              <InlineNotice tone="error" title="Game state did not load">
                {errorMessage(gameStateQuery.error)}
              </InlineNotice>
            ) : gameState ? (
              <GameStateWorkbench gameState={gameState} deckNamesByKey={deckNamesByKey} />
            ) : null}
          </section>
        </section>
      </div>
    </main>
  )
}

async function listSupportedDecks(): Promise<SupportedDeck[]> {
  const result = await runListSupportedTcgDecks({
    fields: SUPPORTED_DECK_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as SupportedDeck[]
}

async function createGame(input: {
  playerOneDeckKey: string
  playerTwoDeckKey: string
}): Promise<CreatedGame> {
  const result = await runCreateTcgEngineGame({
    input: {
      activePlayerId: PLAYER_ONE_ID,
      players: [
        { playerId: PLAYER_ONE_ID, deckKey: input.playerOneDeckKey },
        { playerId: PLAYER_TWO_ID, deckKey: input.playerTwoDeckKey }
      ]
    },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function getGameState(gameId: string, viewerPlayerId: PlayerId): Promise<GameState> {
  const result = await runGetTcgEngineGameState({
    input: { gameId, viewerPlayerId },
    fields: GAME_STATE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as unknown as GameState
}

async function startSetup(gameId: string): Promise<CreatedGame> {
  const result = await runStartTcgEngineSetup({
    input: { gameId },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function drawOpeningHand(gameId: string): Promise<CreatedGame> {
  const result = await runDrawTcgEngineOpeningHand({
    input: { gameId },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function chooseActiveFromHand(input: {
  gameId: string
  playerId: PlayerId
  cardInstanceId: string
}): Promise<CreatedGame> {
  const result = await runChooseTcgEngineActiveFromHand({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function chooseSetupBenchFromHand(input: {
  gameId: string
  playerId: PlayerId
  cardInstanceId: string
}): Promise<CreatedGame> {
  const result = await runChooseTcgEngineSetupBenchFromHand({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function placePrizes(gameId: string): Promise<CreatedGame> {
  const result = await runPlaceTcgEnginePrizes({
    input: { gameId },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function completeSetup(gameId: string): Promise<CreatedGame> {
  const result = await runCompleteTcgEngineSetup({
    input: { gameId },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function startNextTurn(gameId: string): Promise<CreatedGame> {
  const result = await runStartNextTcgEngineTurn({
    input: { gameId },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function drawCardForTurn(input: { gameId: string; playerId: PlayerId }): Promise<CreatedGame> {
  const result = await runDrawTcgEngineCardForTurn({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function skipDrawForTurn(input: { gameId: string; playerId: PlayerId }): Promise<CreatedGame> {
  const result = await runSkipTcgEngineDrawForTurn({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

function GameStateWorkbench({
  gameState,
  deckNamesByKey
}: {
  gameState: GameState
  deckNamesByKey: Map<string, string>
}) {
  return (
    <div className="space-y-5">
      <Panel
        title="Game state"
        trailing={<StatusBadge tone={gameState.status === 'finished' ? 'neutral' : 'active'}>{gameState.status}</StatusBadge>}
      >
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <Metric label="Game ID" value={gameState.gameId} mono />
          <Metric label="Active player" value={formatPlayerId(gameState.activePlayerId)} />
          <Metric label="Cursor" value={`${gameState.cursorIndex} of ${gameState.latestEventIndex}`} />
          <Metric label="Setup" value={gameState.setup?.status ?? 'not started'} />
        </div>

        <div className="mt-5 grid gap-3 md:grid-cols-2">
          <StateRow label="First player" value={formatPlayerId(gameState.firstPlayerId)} />
          <StateRow label="Winner" value={gameState.winnerPlayerId ? formatPlayerId(gameState.winnerPlayerId) : 'None'} />
          <StateRow
            label="Current turn"
            value={
              gameState.currentTurn
                ? `Turn ${gameState.currentTurn.turnNumber}, ${gameState.currentTurn.status}`
                : 'None'
            }
          />
          <StateRow label="Stadium" value={gameState.stadium?.name ?? 'None'} />
        </div>
      </Panel>

      <div className="grid gap-5 xl:grid-cols-2">
        {gameState.players.map(player => (
          <PlayerPanel
            deckName={deckNamesByKey.get(player.deckKey)}
            isViewer={player.playerId === gameState.viewerPlayerId}
            key={player.playerId}
            player={player}
          />
        ))}
      </div>

      <div className="grid gap-5 xl:grid-cols-[1fr_minmax(18rem,24rem)]">
        <Panel title="Event log">
          {gameState.events.length > 0 ? (
            <ol className="space-y-2">
              {gameState.events.map(event => (
                <li
                  className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-xl border border-stone-200 bg-stone-50 px-3 py-2 text-sm"
                  key={event.id}
                >
                  <span className="font-mono text-xs text-stone-500">#{event.index}</span>
                  <span className="font-medium text-stone-950">{formatEventType(event.type)}</span>
                  {event.playerId ? (
                    <span className="text-xs text-stone-500">{formatPlayerId(event.playerId)}</span>
                  ) : null}
                </li>
              ))}
            </ol>
          ) : (
            <EmptyState title="No events persisted yet">
              Create a game or run setup commands to populate the chronological log.
            </EmptyState>
          )}
        </Panel>

        <Panel title="Viewer prompts">
          {gameState.prompts.length > 0 ? (
            <div className="space-y-3">
              {gameState.prompts.map(prompt => (
                <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-3" key={prompt.id}>
                  <p className="text-sm font-medium text-emerald-950">{formatEventType(prompt.promptType)}</p>
                  <p className="mt-1 text-xs text-emerald-800">{prompt.status}</p>
                  <pre className="mt-3 max-h-48 overflow-auto rounded-lg bg-stone-950 p-3 text-xs text-stone-100">
                    {JSON.stringify(prompt.payload, null, 2)}
                  </pre>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState title="No prompt is awaiting this viewer">
              Prompt resolution UI can attach here once the next command boundary is exposed.
            </EmptyState>
          )}
        </Panel>
      </div>
    </div>
  )
}

function PlayerPanel({
  player,
  deckName,
  isViewer
}: {
  player: PlayerView
  deckName?: string
  isViewer: boolean
}) {
  return (
    <Panel
      title={formatPlayerId(player.playerId)}
      trailing={isViewer ? <StatusBadge tone="active">viewer</StatusBadge> : <StatusBadge>opponent</StatusBadge>}
    >
      <div className="space-y-5">
        <div>
          <p className="text-sm font-medium text-stone-950">{deckName ?? player.deckKey}</p>
          <p className="mt-1 font-mono text-xs text-stone-500">{player.deckKey}</p>
        </div>

        <div className="grid grid-cols-4 gap-2">
          <ZoneCount label="Deck" value={player.deckCount} />
          <ZoneCount label="Hand" value={player.handCount} />
          <ZoneCount label="Prize" value={player.prizeCount} />
          <ZoneCount label="Discard" value={player.discardCount} />
        </div>

        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-1 2xl:grid-cols-2">
          <ZoneList cards={player.active ? [player.active] : []} emptyLabel="No Active Pokémon" title="Active" />
          <ZoneList cards={player.bench} emptyLabel="Bench is empty" title="Bench" />
          <ZoneList
            cards={player.hand}
            emptyLabel={isViewer ? 'Hand is empty' : 'Hidden from this viewer'}
            title={isViewer ? 'Viewer hand' : 'Opponent hand'}
          />
          <ZoneList cards={player.discard} emptyLabel="Discard is empty" title="Discard" />
        </div>
      </div>
    </Panel>
  )
}

function Panel({
  title,
  trailing,
  children
}: {
  title: string
  trailing?: React.ReactNode
  children: React.ReactNode
}) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-stone-100/70 p-4 shadow-sm shadow-stone-200/50 sm:p-5">
      <div className="mb-4 flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold uppercase tracking-[0.18em] text-stone-600">{title}</h2>
        {trailing}
      </div>
      {children}
    </section>
  )
}

function DeckSelect({
  label,
  value,
  decks,
  onChange
}: {
  label: string
  value: string
  decks: SupportedDeck[]
  onChange: (value: string) => void
}) {
  return (
    <label className="block space-y-2">
      <span className="text-sm font-medium text-stone-800">{label}</span>
      <select
        className="w-full rounded-xl border border-stone-300 bg-stone-50 px-3 py-2 text-sm text-stone-950 outline-none transition focus:border-emerald-600 focus:ring-2 focus:ring-emerald-100 disabled:cursor-not-allowed disabled:text-stone-400"
        disabled={decks.length === 0}
        onChange={event => onChange(event.currentTarget.value)}
        value={value}
      >
        {decks.length === 0 ? <option value="">No decks available</option> : null}
        {decks.map(deck => (
          <option key={deck.deckKey} value={deck.deckKey}>
            {deck.name}
          </option>
        ))}
      </select>
    </label>
  )
}

function ZoneList({
  title,
  cards,
  emptyLabel
}: {
  title: string
  cards: CardSummary[]
  emptyLabel: string
}) {
  return (
    <div>
      <div className="mb-2 flex items-center justify-between gap-2">
        <h3 className="text-sm font-medium text-stone-800">{title}</h3>
        <span className="rounded-full bg-stone-200 px-2 py-0.5 text-xs font-medium text-stone-600">
          {cards.length}
        </span>
      </div>
      {cards.length > 0 ? (
        <div className="space-y-2">
          {cards.map(card => (
            <CardPill card={card} key={card.id} />
          ))}
        </div>
      ) : (
        <p className="rounded-xl border border-dashed border-stone-300 px-3 py-4 text-center text-sm text-stone-500">
          {emptyLabel}
        </p>
      )}
    </div>
  )
}

function CardPill({ card }: { card: CardSummary }) {
  return (
    <div className="rounded-xl border border-stone-200 bg-stone-50 p-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-stone-950">{card.name}</p>
          <p className="mt-1 font-mono text-xs text-stone-500">{card.cardId}</p>
        </div>
        {card.damage > 0 ? <StatusBadge tone="warning">{card.damage} dmg</StatusBadge> : null}
      </div>
      <div className="mt-2 flex flex-wrap gap-1.5 text-xs text-stone-500">
        {card.category ? <span>{card.category}</span> : null}
        {card.stage ? <span>{card.stage}</span> : null}
        {card.status ? <span>{card.status}</span> : null}
      </div>
    </div>
  )
}

function Metric({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="min-w-0 rounded-xl border border-stone-200 bg-stone-50 p-3">
      <p className="text-xs font-medium uppercase tracking-[0.14em] text-stone-500">{label}</p>
      <p className={`mt-2 truncate text-sm font-semibold text-stone-950 ${mono ? 'font-mono' : ''}`}>
        {value}
      </p>
    </div>
  )
}

function StateRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 rounded-xl bg-stone-50 px-3 py-2 text-sm">
      <span className="text-stone-500">{label}</span>
      <span className="text-right font-medium text-stone-950">{value}</span>
    </div>
  )
}

function ZoneCount({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-xl bg-stone-50 px-3 py-2 text-center">
      <p className="text-lg font-semibold text-stone-950">{value}</p>
      <p className="mt-0.5 text-xs text-stone-500">{label}</p>
    </div>
  )
}

function StatusBadge({
  tone = 'neutral',
  children
}: {
  tone?: 'active' | 'neutral' | 'warning'
  children: React.ReactNode
}) {
  const className =
    tone === 'active'
      ? 'bg-emerald-100 text-emerald-800'
      : tone === 'warning'
        ? 'bg-amber-100 text-amber-800'
        : 'bg-stone-200 text-stone-700'

  return <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${className}`}>{children}</span>
}

function InlineNotice({
  tone,
  title,
  children
}: {
  tone: 'error' | 'info'
  title: string
  children: React.ReactNode
}) {
  const className =
    tone === 'error'
      ? 'border-red-200 bg-red-50 text-red-900'
      : 'border-stone-200 bg-stone-100 text-stone-700'

  return (
    <div className={`rounded-2xl border p-4 ${className}`}>
      <p className="text-sm font-semibold">{title}</p>
      <div className="mt-1 text-sm leading-6">{children}</div>
    </div>
  )
}

function EmptyWorkbench() {
  return (
    <div className="grid min-h-[32rem] place-items-center rounded-3xl border border-dashed border-stone-300 bg-stone-100/60 p-8 text-center">
      <div className="max-w-md">
        <p className="text-sm font-semibold uppercase tracking-[0.22em] text-stone-500">No game selected</p>
        <h2 className="mt-3 text-2xl font-semibold tracking-tight text-stone-950">
          Create a fixture game or reconnect by ID
        </h2>
        <p className="mt-3 text-sm leading-6 text-stone-600">
          This first shell is read-only after creation. Setup action buttons can build on the same RPC
          state refresh path.
        </p>
      </div>
    </div>
  )
}

function EmptyState({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-stone-300 px-4 py-8 text-center">
      <p className="text-sm font-medium text-stone-800">{title}</p>
      <p className="mt-2 text-sm leading-6 text-stone-500">{children}</p>
    </div>
  )
}

function SkeletonLines({ count }: { count: number }) {
  return (
    <div className="space-y-2" role="status">
      {Array.from({ length: count }).map((_, index) => (
        <div className="h-10 animate-pulse rounded-xl bg-stone-200" key={index} />
      ))}
      <span className="sr-only">Loading</span>
    </div>
  )
}

function readStoredSession(): PlaytestSession {
  if (typeof window === 'undefined') {
    return defaultSession()
  }

  try {
    const item = window.localStorage.getItem(SESSION_STORAGE_KEY)

    if (!item) {
      return defaultSession()
    }

    const parsed = JSON.parse(item) as Partial<PlaytestSession>
    const viewerPlayerId = isPlayerId(parsed.viewerPlayerId) ? parsed.viewerPlayerId : PLAYER_ONE_ID

    return {
      gameId: typeof parsed.gameId === 'string' ? parsed.gameId : '',
      viewerPlayerId
    }
  } catch {
    return defaultSession()
  }
}

function setStoredSession(session: PlaytestSession) {
  if (typeof window === 'undefined') {
    return
  }

  window.localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session))
}

function defaultSession(): PlaytestSession {
  return { gameId: '', viewerPlayerId: PLAYER_ONE_ID }
}

function isPlayerId(value: unknown): value is PlayerId {
  return PLAYER_IDS.some(playerId => playerId === value)
}

function isSetupActiveCandidate(card: CardSummary) {
  return card.category === 'pokemon' && card.stage === 'basic'
}

function isSetupBenchCandidate(card: CardSummary) {
  return isSetupActiveCandidate(card)
}

function rpcErrorMessage(errors: RpcError[] = []) {
  return errors.map(error => error.shortMessage || error.message || error.type).filter(Boolean).join('; ') || 'Unknown RPC error'
}

function errorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message
  }

  return String(error)
}

function formatPlayerId(playerId: string) {
  return playerId.replace('_', ' ')
}

function formatEventType(type: string) {
  return type.replaceAll('_', ' ')
}
