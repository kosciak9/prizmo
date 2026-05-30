import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useMemo, useState } from 'react'

import {
  runAttachTcgEngineEnergy,
  buildAshRpcHeaders,
  runChooseTcgEngineActiveFromHand,
  runChooseTcgEnginePrompt,
  runChooseTcgEngineReplacementActive,
  runChooseTcgEngineSetupBenchFromHand,
  runCompleteTcgEngineSetup,
  runCreateTcgEngineGame,
  runDeclareTcgEngineAttack,
  runDrawTcgEngineCardForTurn,
  runDrawTcgEngineOpeningHand,
  runEndTcgEngineTurn,
  runEvolveTcgEngineFromHand,
  runFinishTcgEngineAttack,
  runGetTcgEngineGameState,
  runListSupportedTcgDecks,
  runOpenTcgEngineActionWindow,
  runPlaceTcgEnginePrizes,
  runPlayTcgEngineBasicToBench,
  runPlayTcgEngineCard,
  runRetreatTcgEngineActive,
  runResolveTcgEngineDeclaredAttack,
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
const LEGACY_SESSION_STORAGE_KEY = 'prizmo:tcg-playtest-session'
const GAME_ID_STORAGE_KEY = 'prizmo:tcg-playtest-game-id'
const VIEWER_STORAGE_KEY = 'prizmo:tcg-playtest-viewer'
const DISCARD_OWN_BASIC_ENERGY_FOR_DAMAGE_EFFECT = 'damage_per_discarded_own_basic_energy'
const DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT = 'discard_energy_from_own_bench_for_bonus_damage'
const SHUFFLE_ATTACHED_ENERGY_INTO_DECK_THEN_DAMAGE_OPPONENT_BENCH_EFFECT =
  'shuffle_attached_energy_into_deck_then_damage_opponent_bench'

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

const BASE_CARD_SUMMARY_FIELDS = [
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

const ATTACHED_CARD_SUMMARY_FIELDS = [...BASE_CARD_SUMMARY_FIELDS] as const

const CARD_SUMMARY_FIELDS = [
  ...BASE_CARD_SUMMARY_FIELDS,
  { attachedCards: [...ATTACHED_CARD_SUMMARY_FIELDS] }
] as const

const ACTION_AFFORDANCE_FIELDS = [
  'key',
  'label',
  'kind',
  'playerId',
  'sourceCardInstanceIds',
  'targetCardInstanceIds',
  'requiredSourceCount',
  'attackId',
  'attackName',
  'attackCost',
  'attackDamage',
  'promptIds',
  'choiceKeys',
  'note'
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
      'pendingAttackEffectType',
      'pendingAttackRequiresSwitchTarget',
      'pendingAttackRequiresDiscardedEnergy',
      'pendingAttackRequiresReturnedEnergy',
      'pendingAttackRequiresShuffledEnergy',
      'pendingAttackRequiresBenchDamageTarget',
      'pendingAttackerCardInstanceId',
      'pendingDefenderCardInstanceId'
    ]
  },
  { actionAffordances: [...ACTION_AFFORDANCE_FIELDS] },
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
  attachedCards?: CardSummary[]
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

type ActionAffordance = {
  key: string
  label: string
  kind: string
  playerId: string
  sourceCardInstanceIds: string[]
  targetCardInstanceIds: string[]
  requiredSourceCount: number
  attackId: string | null
  attackName: string | null
  attackCost: string[]
  attackDamage: string | null
  promptIds: string[]
  choiceKeys: string[]
  note: string | null
}

type PlayCardInput = {
  gameId: string
  playerId: PlayerId
  cardInstanceId: string
}

type PlayCardCommand = {
  playerId: string
  cardInstanceId: string
}

type PlayBasicToBenchInput = {
  gameId: string
  playerId: PlayerId
  cardInstanceId: string
}

type PlayBasicToBenchCommand = {
  playerId: string
  cardInstanceId: string
}

type EvolveFromHandInput = {
  gameId: string
  playerId: PlayerId
  evolutionCardInstanceId: string
  targetCardInstanceId: string
}

type EvolveFromHandCommand = {
  playerId: string
  evolutionCardInstanceId: string
  targetCardInstanceId: string
}

type AttachEnergyInput = {
  gameId: string
  playerId: PlayerId
  energyCardInstanceId: string
  targetCardInstanceId: string
}

type AttachEnergyCommand = {
  playerId: string
  energyCardInstanceId: string
  targetCardInstanceId: string
}

type EndTurnInput = {
  gameId: string
  playerId: PlayerId
}

type EndTurnCommand = {
  playerId: string
}

type RetreatInput = {
  gameId: string
  playerId: PlayerId
  benchCardInstanceId: string
  energyCardInstanceIds: string[]
}

type RetreatCommand = {
  playerId: string
  benchCardInstanceId: string
  energyCardInstanceIds: string[]
}

type DeclareAttackInput = {
  gameId: string
  playerId: PlayerId
  attackId: string
}

type DeclareAttackCommand = {
  playerId: string
  attackId: string
}

type ResolveDeclaredAttackInput = {
  gameId: string
  playerId: PlayerId
  switchBenchCardInstanceId?: string | null
  discardedEnergyCardInstanceIds?: string[]
  returnedEnergyCardInstanceId?: string | null
  shuffledEnergyCardInstanceIds?: string[]
  benchDamageTargetCardInstanceId?: string | null
}

type ResolveDeclaredAttackCommand = {
  playerId: string
  switchBenchCardInstanceId?: string | null
  discardedEnergyCardInstanceIds?: string[]
  returnedEnergyCardInstanceId?: string | null
  shuffledEnergyCardInstanceIds?: string[]
  benchDamageTargetCardInstanceId?: string | null
}

type FinishAttackInput = {
  gameId: string
  playerId: PlayerId
}

type FinishAttackCommand = {
  playerId: string
}

type ChooseReplacementActiveInput = {
  gameId: string
  playerId: PlayerId
  benchCardInstanceId: string
}

type ChooseReplacementActiveCommand = {
  playerId: string
  benchCardInstanceId: string
}

type ChoosePromptInput = {
  gameId: string
  playerId: PlayerId
  promptId: string
  selectedCardInstanceIds: string[]
}

type ChoosePromptCommand = {
  playerId: string
  promptId: string
  selectedCardInstanceIds: string[]
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
    pendingAttackEffectType: string | null
    pendingAttackRequiresSwitchTarget: boolean
    pendingAttackRequiresDiscardedEnergy: boolean
    pendingAttackRequiresReturnedEnergy: boolean
    pendingAttackRequiresShuffledEnergy: boolean
    pendingAttackRequiresBenchDamageTarget: boolean
    pendingAttackerCardInstanceId: string | null
    pendingDefenderCardInstanceId: string | null
  } | null
  actionAffordances: ActionAffordance[]
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

  useEffect(() => {
    setStoredSession(session)
  }, [session])

  const decksQuery = useQuery({
    queryKey: ['tcg-engine', 'supported-decks'],
    queryFn: listSupportedDecks
  })

  const decks = decksQuery.data ?? []
  const selectedPlayerOneDeckKey = playerOneDeckKey || decks[0]?.deckKey || ''
  const selectedPlayerTwoDeckKey = playerTwoDeckKey || decks[1]?.deckKey || decks[0]?.deckKey || ''
  const normalisedGameId = session.gameId.trim()

  const gameStateQuery = useQuery({
    queryKey: ['tcg-engine', 'game-state', normalisedGameId, session.viewerPlayerId] as const,
    queryFn: ({ queryKey }) => {
      const [, , gameId, viewerPlayerId] = queryKey

      return getGameState(gameId, viewerPlayerId)
    },
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
      updateSession(currentSession => ({
        ...currentSession,
        gameId: game.id
      }))

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

  const openActionWindowMutation = useMutation({
    mutationFn: (gameId: string) => openActionWindow(gameId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const playCardMutation = useMutation({
    mutationFn: (input: PlayCardInput) => playCard(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const playBasicToBenchMutation = useMutation({
    mutationFn: (input: PlayBasicToBenchInput) => playBasicToBench(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const evolveFromHandMutation = useMutation({
    mutationFn: (input: EvolveFromHandInput) => evolveFromHand(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const attachEnergyMutation = useMutation({
    mutationFn: (input: AttachEnergyInput) => attachEnergy(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const endTurnMutation = useMutation({
    mutationFn: (input: EndTurnInput) => endTurn(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const retreatMutation = useMutation({
    mutationFn: (input: RetreatInput) => retreat(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const declareAttackMutation = useMutation({
    mutationFn: (input: DeclareAttackInput) => declareAttack(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const resolveDeclaredAttackMutation = useMutation({
    mutationFn: (input: ResolveDeclaredAttackInput) => resolveDeclaredAttack(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const finishAttackMutation = useMutation({
    mutationFn: (input: FinishAttackInput) => finishAttack(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const chooseReplacementActiveMutation = useMutation({
    mutationFn: (input: ChooseReplacementActiveInput) => chooseReplacementActive(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const choosePromptMutation = useMutation({
    mutationFn: (input: ChoosePromptInput) => choosePrompt(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const queriedGameState = gameStateQuery.data
  const gameStateHasViewerMismatch = Boolean(
    queriedGameState && queriedGameState.viewerPlayerId !== session.viewerPlayerId
  )
  const gameState = gameStateHasViewerMismatch ? undefined : queriedGameState
  const viewerPlayer = gameState?.players.find(player => player.playerId === session.viewerPlayerId)
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
        (!gameState.currentTurn || gameState.currentTurn.status === 'ended')
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
    !skipDrawForTurnMutation.isPending &&
    !openActionWindowMutation.isPending
  const canSkipDrawForTurn =
    Boolean(
      normalisedGameId &&
        gameState?.status === 'in_progress' &&
        gameState.currentTurn?.status === 'start' &&
        currentTurnActivePlayerId &&
        isPlayerId(currentTurnActivePlayerId)
    ) &&
    !drawForTurnMutation.isPending &&
    !skipDrawForTurnMutation.isPending &&
    !openActionWindowMutation.isPending
  const canOpenActionWindow =
    Boolean(
      normalisedGameId &&
        gameState?.status === 'in_progress' &&
        gameState.currentTurn?.status === 'drawn'
    ) &&
    !drawForTurnMutation.isPending &&
    !skipDrawForTurnMutation.isPending &&
    !openActionWindowMutation.isPending

  function updateSession(updater: (currentSession: PlaytestSession) => PlaytestSession) {
    setSession(currentSession => updater(currentSession))
  }

  function clearGame() {
    updateSession(currentSession => ({ ...currentSession, gameId: '' }))
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
                          onChange={() =>
                            updateSession(currentSession => ({
                              ...currentSession,
                              viewerPlayerId: playerId
                            }))
                          }
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
                    onChange={event => {
                      const gameId = event.currentTarget.value

                      updateSession(currentSession => ({ ...currentSession, gameId }))
                    }}
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
                        Start the first or next persisted turn, then draw, skip draw, or open the action window.
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
                      : gameState?.currentTurn?.status === 'ended'
                        ? 'Start next turn'
                        : gameState?.currentTurn
                          ? `Turn ${gameState.currentTurn.turnNumber} in progress`
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
                  <button
                    className="mt-2 w-full rounded-xl border border-emerald-700 px-3 py-2 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                    disabled={!canOpenActionWindow}
                    onClick={() => openActionWindowMutation.mutate(normalisedGameId)}
                    type="button"
                  >
                    {openActionWindowMutation.isPending
                      ? 'Opening action window...'
                      : gameState?.currentTurn?.status === 'drawn'
                        ? 'Open action window'
                        : gameState?.currentTurn?.status === 'action_window'
                          ? 'Action window open'
                          : gameState?.currentTurn
                            ? 'Draw or skip draw first'
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

                {openActionWindowMutation.error ? (
                  <InlineNotice tone="error" title="Open action window command failed">
                    {errorMessage(openActionWindowMutation.error)}
                  </InlineNotice>
                ) : null}

                {playCardMutation.error ? (
                  <InlineNotice tone="error" title="Play card command failed">
                    {errorMessage(playCardMutation.error)}
                  </InlineNotice>
                ) : null}

                {playBasicToBenchMutation.error ? (
                  <InlineNotice tone="error" title="Bench Basic command failed">
                    {errorMessage(playBasicToBenchMutation.error)}
                  </InlineNotice>
                ) : null}

                {evolveFromHandMutation.error ? (
                  <InlineNotice tone="error" title="Evolution command failed">
                    {errorMessage(evolveFromHandMutation.error)}
                  </InlineNotice>
                ) : null}

                {attachEnergyMutation.error ? (
                  <InlineNotice tone="error" title="Attach Energy command failed">
                    {errorMessage(attachEnergyMutation.error)}
                  </InlineNotice>
                ) : null}

                {endTurnMutation.error ? (
                  <InlineNotice tone="error" title="End turn command failed">
                    {errorMessage(endTurnMutation.error)}
                  </InlineNotice>
                ) : null}

                {retreatMutation.error ? (
                  <InlineNotice tone="error" title="Retreat command failed">
                    {errorMessage(retreatMutation.error)}
                  </InlineNotice>
                ) : null}

                {declareAttackMutation.error ? (
                  <InlineNotice tone="error" title="Attack declaration command failed">
                    {errorMessage(declareAttackMutation.error)}
                  </InlineNotice>
                ) : null}

                {resolveDeclaredAttackMutation.error ? (
                  <InlineNotice tone="error" title="Attack resolution command failed">
                    {errorMessage(resolveDeclaredAttackMutation.error)}
                  </InlineNotice>
                ) : null}

                {finishAttackMutation.error ? (
                  <InlineNotice tone="error" title="Finish attack command failed">
                    {errorMessage(finishAttackMutation.error)}
                  </InlineNotice>
                ) : null}

                {chooseReplacementActiveMutation.error ? (
                  <InlineNotice tone="error" title="Replacement Active command failed">
                    {errorMessage(chooseReplacementActiveMutation.error)}
                  </InlineNotice>
                ) : null}

                {choosePromptMutation.error ? (
                  <InlineNotice tone="error" title="Prompt choice command failed">
                    {errorMessage(choosePromptMutation.error)}
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
            ) : gameStateHasViewerMismatch ? (
              <InlineNotice tone="info" title="Viewer state is refreshing">
                Ignoring a stale {formatPlayerId(queriedGameState?.viewerPlayerId ?? 'unknown')} read while this tab is
                viewing {formatPlayerId(session.viewerPlayerId)}. Refresh state again if this persists.
              </InlineNotice>
            ) : gameState ? (
              <GameStateWorkbench
                deckNamesByKey={deckNamesByKey}
                gameState={gameState}
                viewerPlayerId={session.viewerPlayerId}
                onChooseReplacementActive={({ playerId, benchCardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    chooseReplacementActiveMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      benchCardInstanceId
                    })
                  }
                }}
                onChoosePrompt={({ playerId, promptId, selectedCardInstanceIds }) => {
                  if (isPlayerId(playerId)) {
                    choosePromptMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      promptId,
                      selectedCardInstanceIds
                    })
                  }
                }}
                onAttachEnergy={({ playerId, energyCardInstanceId, targetCardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    attachEnergyMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      energyCardInstanceId,
                      targetCardInstanceId
                    })
                  }
                }}
                onEndTurn={({ playerId }) => {
                  if (isPlayerId(playerId)) {
                    endTurnMutation.mutate({
                      gameId: normalisedGameId,
                      playerId
                    })
                  }
                }}
                onRetreat={({ playerId, benchCardInstanceId, energyCardInstanceIds }) => {
                  if (isPlayerId(playerId)) {
                    retreatMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      benchCardInstanceId,
                      energyCardInstanceIds
                    })
                  }
                }}
                onDeclareAttack={({ playerId, attackId }) => {
                  if (isPlayerId(playerId)) {
                    declareAttackMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      attackId
                    })
                  }
                }}
                onResolveDeclaredAttack={({
                  playerId,
                  switchBenchCardInstanceId,
                  discardedEnergyCardInstanceIds,
                  returnedEnergyCardInstanceId,
                  shuffledEnergyCardInstanceIds,
                  benchDamageTargetCardInstanceId
                }) => {
                  if (isPlayerId(playerId)) {
                    resolveDeclaredAttackMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      switchBenchCardInstanceId,
                      discardedEnergyCardInstanceIds,
                      returnedEnergyCardInstanceId,
                      shuffledEnergyCardInstanceIds,
                      benchDamageTargetCardInstanceId
                    })
                  }
                }}
                onFinishAttack={({ playerId }) => {
                  if (isPlayerId(playerId)) {
                    finishAttackMutation.mutate({
                      gameId: normalisedGameId,
                      playerId
                    })
                  }
                }}
                onPlayCard={({ playerId, cardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    playCardMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      cardInstanceId
                    })
                  }
                }}
                onPlayBasicToBench={({ playerId, cardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    playBasicToBenchMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      cardInstanceId
                    })
                  }
                }}
                onEvolveFromHand={({ playerId, evolutionCardInstanceId, targetCardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    evolveFromHandMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      evolutionCardInstanceId,
                      targetCardInstanceId
                    })
                  }
                }}
                playBasicToBenchPendingCardId={
                  playBasicToBenchMutation.isPending ? playBasicToBenchMutation.variables?.cardInstanceId ?? null : null
                }
                evolveFromHandPendingKey={
                  evolveFromHandMutation.isPending && evolveFromHandMutation.variables
                    ? evolveKey(
                        evolveFromHandMutation.variables.evolutionCardInstanceId,
                        evolveFromHandMutation.variables.targetCardInstanceId
                      )
                    : null
                }
                attachEnergyPendingKey={
                  attachEnergyMutation.isPending && attachEnergyMutation.variables
                    ? attachEnergyPairKey(
                        attachEnergyMutation.variables.energyCardInstanceId,
                        attachEnergyMutation.variables.targetCardInstanceId
                      )
                    : null
                }
                chooseReplacementActivePendingCardId={
                  chooseReplacementActiveMutation.isPending
                    ? chooseReplacementActiveMutation.variables?.benchCardInstanceId ?? null
                    : null
                }
                promptPendingId={choosePromptMutation.isPending ? choosePromptMutation.variables?.promptId ?? null : null}
                endTurnPendingPlayerId={endTurnMutation.isPending ? endTurnMutation.variables?.playerId ?? null : null}
                playCardPendingCardId={playCardMutation.isPending ? playCardMutation.variables?.cardInstanceId ?? null : null}
                retreatPendingKey={
                  retreatMutation.isPending && retreatMutation.variables
                    ? retreatKey(
                        retreatMutation.variables.benchCardInstanceId,
                        retreatMutation.variables.energyCardInstanceIds
                      )
                    : null
                }
                declareAttackPendingKey={
                  declareAttackMutation.isPending && declareAttackMutation.variables
                    ? attackKey(declareAttackMutation.variables.playerId, declareAttackMutation.variables.attackId)
                    : null
                }
                resolveDeclaredAttackPendingPlayerId={
                  resolveDeclaredAttackMutation.isPending
                    ? resolveDeclaredAttackMutation.variables?.playerId ?? null
                    : null
                }
                finishAttackPendingPlayerId={
                  finishAttackMutation.isPending ? finishAttackMutation.variables?.playerId ?? null : null
                }
              />
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

async function openActionWindow(gameId: string): Promise<CreatedGame> {
  const result = await runOpenTcgEngineActionWindow({
    input: { gameId },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function playCard(input: PlayCardInput): Promise<CreatedGame> {
  const result = await runPlayTcgEngineCard({
    input: { ...input, choices: {} },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function playBasicToBench(input: PlayBasicToBenchInput): Promise<CreatedGame> {
  const result = await runPlayTcgEngineBasicToBench({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function evolveFromHand(input: EvolveFromHandInput): Promise<CreatedGame> {
  const result = await runEvolveTcgEngineFromHand({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function attachEnergy(input: AttachEnergyInput): Promise<CreatedGame> {
  const result = await runAttachTcgEngineEnergy({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function endTurn(input: EndTurnInput): Promise<CreatedGame> {
  const result = await runEndTcgEngineTurn({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function retreat(input: RetreatInput): Promise<CreatedGame> {
  const result = await runRetreatTcgEngineActive({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function declareAttack(input: DeclareAttackInput): Promise<CreatedGame> {
  const result = await runDeclareTcgEngineAttack({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function resolveDeclaredAttack(input: ResolveDeclaredAttackInput): Promise<CreatedGame> {
  const result = await runResolveTcgEngineDeclaredAttack({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function finishAttack(input: FinishAttackInput): Promise<CreatedGame> {
  const result = await runFinishTcgEngineAttack({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function chooseReplacementActive(input: ChooseReplacementActiveInput): Promise<CreatedGame> {
  const result = await runChooseTcgEngineReplacementActive({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function choosePrompt(input: ChoosePromptInput): Promise<CreatedGame> {
  const result = await runChooseTcgEnginePrompt({
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
  viewerPlayerId,
  deckNamesByKey,
  onChoosePrompt,
  onChooseReplacementActive,
  onAttachEnergy,
  onDeclareAttack,
  onEndTurn,
  onEvolveFromHand,
  onFinishAttack,
  onPlayBasicToBench,
  onPlayCard,
  onRetreat,
  onResolveDeclaredAttack,
  attachEnergyPendingKey,
  chooseReplacementActivePendingCardId,
  declareAttackPendingKey,
  endTurnPendingPlayerId,
  evolveFromHandPendingKey,
  finishAttackPendingPlayerId,
  playBasicToBenchPendingCardId,
  promptPendingId,
  playCardPendingCardId,
  resolveDeclaredAttackPendingPlayerId,
  retreatPendingKey
}: {
  gameState: GameState
  viewerPlayerId: PlayerId
  deckNamesByKey: Map<string, string>
  onChoosePrompt: (input: ChoosePromptCommand) => void
  onChooseReplacementActive: (input: ChooseReplacementActiveCommand) => void
  onAttachEnergy: (input: AttachEnergyCommand) => void
  onDeclareAttack: (input: DeclareAttackCommand) => void
  onEndTurn: (input: EndTurnCommand) => void
  onEvolveFromHand: (input: EvolveFromHandCommand) => void
  onFinishAttack: (input: FinishAttackCommand) => void
  onPlayBasicToBench: (input: PlayBasicToBenchCommand) => void
  onPlayCard: (input: PlayCardCommand) => void
  onRetreat: (input: RetreatCommand) => void
  onResolveDeclaredAttack: (input: ResolveDeclaredAttackCommand) => void
  attachEnergyPendingKey: string | null
  chooseReplacementActivePendingCardId: string | null
  declareAttackPendingKey: string | null
  endTurnPendingPlayerId: string | null
  evolveFromHandPendingKey: string | null
  finishAttackPendingPlayerId: string | null
  playBasicToBenchPendingCardId: string | null
  promptPendingId: string | null
  playCardPendingCardId: string | null
  resolveDeclaredAttackPendingPlayerId: string | null
  retreatPendingKey: string | null
}) {
  const cardsById = useMemo(() => visibleCardsById(gameState), [gameState])

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

      <ActionAffordancesPanel
        actions={gameState.actionAffordances}
        cardsById={cardsById}
        chooseReplacementActivePendingCardId={chooseReplacementActivePendingCardId}
        onAttachEnergy={onAttachEnergy}
        onChooseReplacementActive={onChooseReplacementActive}
        onDeclareAttack={onDeclareAttack}
        onEndTurn={onEndTurn}
        onEvolveFromHand={onEvolveFromHand}
        onPlayBasicToBench={onPlayBasicToBench}
        onPlayCard={onPlayCard}
        onRetreat={onRetreat}
        attachEnergyPendingKey={attachEnergyPendingKey}
        declareAttackPendingKey={declareAttackPendingKey}
        endTurnPendingPlayerId={endTurnPendingPlayerId}
        evolveFromHandPendingKey={evolveFromHandPendingKey}
        playBasicToBenchPendingCardId={playBasicToBenchPendingCardId}
        playCardPendingCardId={playCardPendingCardId}
        retreatPendingKey={retreatPendingKey}
      />

      <AttackProgressPanel
        cardsById={cardsById}
        finishAttackPendingPlayerId={finishAttackPendingPlayerId}
        gameState={gameState}
        onFinishAttack={onFinishAttack}
        onResolveDeclaredAttack={onResolveDeclaredAttack}
        resolveDeclaredAttackPendingPlayerId={resolveDeclaredAttackPendingPlayerId}
        viewerPlayerId={viewerPlayerId}
      />

      <div className="grid gap-5 xl:grid-cols-2">
        {gameState.players.map(player => (
          <PlayerPanel
            deckName={deckNamesByKey.get(player.deckKey)}
            isViewer={player.playerId === viewerPlayerId}
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

        <ViewerPromptsPanel
          cardsById={cardsById}
          onChoosePrompt={onChoosePrompt}
          promptPendingId={promptPendingId}
          prompts={gameState.prompts}
        />
      </div>
    </div>
  )
}

function ViewerPromptsPanel({
  cardsById,
  onChoosePrompt,
  promptPendingId,
  prompts
}: {
  cardsById: Map<string, CardSummary>
  onChoosePrompt: (input: ChoosePromptCommand) => void
  promptPendingId: string | null
  prompts: GameState['prompts']
}) {
  return (
    <Panel title="Viewer prompts">
      {prompts.length > 0 ? (
        <div className="space-y-3">
          {prompts.map(prompt => (
            <PromptChoiceCard
              cardsById={cardsById}
              isPending={promptPendingId === prompt.id}
              key={prompt.id}
              onChoosePrompt={onChoosePrompt}
              prompt={prompt}
              promptPendingId={promptPendingId}
            />
          ))}
        </div>
      ) : (
        <EmptyState title="No prompt is awaiting this viewer">
          Pending card effects will appear here with selectable legal choices.
        </EmptyState>
      )}
    </Panel>
  )
}

function PromptChoiceCard({
  cardsById,
  isPending,
  onChoosePrompt,
  prompt,
  promptPendingId
}: {
  cardsById: Map<string, CardSummary>
  isPending: boolean
  onChoosePrompt: (input: ChoosePromptCommand) => void
  prompt: GameState['prompts'][number]
  promptPendingId: string | null
}) {
  const legalChoiceIds = promptLegalChoiceIds(prompt.payload)
  const legalChoiceCards = promptLegalChoiceCards(prompt.payload)
  const legalChoiceCardsById = useMemo(() => new Map(legalChoiceCards.map(card => [card.id, card])), [legalChoiceCards])
  const legalChoiceLabels = promptLegalChoiceLabels(prompt.payload)
  const legalChoiceLabelsById = useMemo(
    () => new Map(legalChoiceLabels.map(choice => [choice.id, choice])),
    [legalChoiceLabels]
  )
  const [selectedCardInstanceIds, setSelectedCardInstanceIds] = useState<string[]>([])
  const min = promptChoiceCount(prompt.payload, 'min', 1)
  const max = promptChoiceCount(prompt.payload, 'max', min)
  const canSubmit =
    selectedCardInstanceIds.length >= min &&
    selectedCardInstanceIds.length <= max &&
    !promptPendingId &&
    isPlayerId(prompt.playerId)

  function toggleChoice(cardInstanceId: string) {
    setSelectedCardInstanceIds(current => {
      if (current.includes(cardInstanceId)) {
        return current.filter(id => id !== cardInstanceId)
      }

      if (current.length >= max) {
        return max === 1 ? [cardInstanceId] : current
      }

      return [...current, cardInstanceId]
    })
  }

  return (
    <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-sm font-medium text-emerald-950">{formatEventType(prompt.promptType)}</p>
          <p className="mt-1 text-xs text-emerald-800">
            {formatEventType(promptChoiceKey(prompt.payload))} · {promptChoiceInstruction(min, max)} ·{' '}
            {legalChoiceIds.length} legal {legalChoiceIds.length === 1 ? 'choice' : 'choices'}
          </p>
        </div>
        <StatusBadge tone="warning">{prompt.status}</StatusBadge>
      </div>

      {legalChoiceIds.length > 0 ? (
        <div className="mt-3 space-y-2">
          {legalChoiceIds.map(cardInstanceId => {
            const card = legalChoiceCardsById.get(cardInstanceId) ?? cardsById.get(cardInstanceId)
            const choiceLabel = legalChoiceLabelsById.get(cardInstanceId)
            const selected = selectedCardInstanceIds.includes(cardInstanceId)

            return (
              <button
                className={`w-full rounded-xl border px-3 py-2 text-left text-sm transition focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-60 ${
                  selected
                    ? 'border-emerald-700 bg-emerald-100 text-emerald-950'
                    : 'border-emerald-200 bg-stone-50 text-stone-700 hover:border-emerald-500 hover:bg-emerald-50'
                }`}
                disabled={Boolean(promptPendingId)}
                key={cardInstanceId}
                onClick={() => toggleChoice(cardInstanceId)}
                type="button"
              >
                <span className="block font-semibold">
                  {card?.name ?? choiceLabel?.label ?? formatCardInstanceId(cardInstanceId)}
                </span>
                <span className="mt-0.5 block text-xs text-stone-500">
                  {promptChoiceCardDetail(card, cardInstanceId, choiceLabel)}
                </span>
              </button>
            )
          })}

          <button
            className="w-full rounded-xl bg-emerald-700 px-3 py-2 text-sm font-semibold text-stone-50 transition hover:bg-emerald-800 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-stone-300 disabled:text-stone-600"
            disabled={!canSubmit}
            onClick={() =>
              onChoosePrompt({
                playerId: prompt.playerId,
                promptId: prompt.id,
                selectedCardInstanceIds
              })
            }
            type="button"
          >
            {isPending ? 'Submitting choice...' : `Submit ${selectedCardInstanceIds.length}/${max}`}
          </button>
        </div>
      ) : (
        <p className="mt-3 rounded-lg border border-dashed border-emerald-200 px-3 py-3 text-sm text-emerald-900">
          This prompt did not include selectable card choices.
        </p>
      )}

      <details className="mt-3 rounded-lg border border-emerald-200 bg-stone-50 px-3 py-2 text-xs text-stone-600">
        <summary className="cursor-pointer font-medium text-emerald-900">Debug prompt payload</summary>
        <pre className="mt-2 max-h-32 overflow-auto rounded-lg bg-stone-950 p-3 text-xs text-stone-100">
          {JSON.stringify(prompt.payload, null, 2)}
        </pre>
      </details>
    </div>
  )
}

function AttackProgressPanel({
  cardsById,
  finishAttackPendingPlayerId,
  gameState,
  onFinishAttack,
  onResolveDeclaredAttack,
  resolveDeclaredAttackPendingPlayerId,
  viewerPlayerId
}: {
  cardsById: Map<string, CardSummary>
  finishAttackPendingPlayerId: string | null
  gameState: GameState
  onFinishAttack: (input: FinishAttackCommand) => void
  onResolveDeclaredAttack: (input: ResolveDeclaredAttackCommand) => void
  resolveDeclaredAttackPendingPlayerId: string | null
  viewerPlayerId: PlayerId
}) {
  const [selectedSwitchBenchCardInstanceId, setSelectedSwitchBenchCardInstanceId] = useState('')
  const [selectedDiscardedEnergyCardInstanceIds, setSelectedDiscardedEnergyCardInstanceIds] = useState<string[]>([])
  const [selectedReturnedEnergyCardInstanceId, setSelectedReturnedEnergyCardInstanceId] = useState('')
  const [selectedShuffledEnergyCardInstanceIds, setSelectedShuffledEnergyCardInstanceIds] = useState<string[]>([])
  const [selectedBenchDamageTargetCardInstanceId, setSelectedBenchDamageTargetCardInstanceId] = useState('')
  const turn = gameState.currentTurn
  const activePlayer = turn ? gameState.players.find(player => player.playerId === turn.activePlayerId) : undefined
  const opponentPlayer = turn ? gameState.players.find(player => player.playerId !== turn.activePlayerId) : undefined
  const switchTargetOptions = turn?.pendingAttackRequiresSwitchTarget ? (activePlayer?.bench ?? []) : []
  const selectedSwitchTargetIsValid = switchTargetOptions.some(card => card.id === selectedSwitchBenchCardInstanceId)
  const discardedEnergyOptions = useMemo(() => {
    if (!turn?.pendingAttackRequiresDiscardedEnergy || !activePlayer) {
      return []
    }

    const sourceCards =
      turn.pendingAttackEffectType === DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT
        ? activePlayer.bench
        : turn.pendingAttackEffectType === DISCARD_OWN_BASIC_ENERGY_FOR_DAMAGE_EFFECT
          ? [activePlayer.active, ...activePlayer.bench]
          : []

    return sourceCards
      .filter((card): card is CardSummary => Boolean(card))
      .flatMap(card =>
        (card.attachedCards ?? [])
          .filter(isEnergyCard)
          .map(energyCard => ({ attachedTo: card, energyCard }))
      )
  }, [activePlayer, turn?.pendingAttackEffectType, turn?.pendingAttackRequiresDiscardedEnergy])
  const discardedEnergyOptionIds = useMemo(
    () => new Set(discardedEnergyOptions.map(option => option.energyCard.id)),
    [discardedEnergyOptions]
  )
  const selectedDiscardedEnergyIdsForResolve = turn?.pendingAttackRequiresDiscardedEnergy
    ? selectedDiscardedEnergyCardInstanceIds.filter(id => discardedEnergyOptionIds.has(id))
    : []
  const returnedEnergyOptions = useMemo(() => {
    if (!turn?.pendingAttackRequiresReturnedEnergy || !activePlayer?.active) {
      return []
    }

    return (activePlayer.active.attachedCards ?? []).filter(isEnergyCard)
  }, [activePlayer?.active, turn?.pendingAttackRequiresReturnedEnergy])
  const returnedEnergyOptionIds = useMemo(
    () => new Set(returnedEnergyOptions.map(energyCard => energyCard.id)),
    [returnedEnergyOptions]
  )
  const selectedReturnedEnergyIsValid = returnedEnergyOptionIds.has(selectedReturnedEnergyCardInstanceId)
  const returnedEnergyIdForResolve = turn?.pendingAttackRequiresReturnedEnergy
    ? selectedReturnedEnergyIsValid
      ? selectedReturnedEnergyCardInstanceId
      : returnedEnergyOptions.length === 1
        ? (returnedEnergyOptions[0]?.id ?? null)
        : null
    : null
  const shuffledEnergyOptions = useMemo(() => {
    if (!turn?.pendingAttackRequiresShuffledEnergy || !activePlayer?.active) {
      return []
    }

    return (activePlayer.active.attachedCards ?? []).filter(isEnergyCard)
  }, [activePlayer?.active, turn?.pendingAttackRequiresShuffledEnergy])
  const shuffledEnergyOptionIds = useMemo(
    () => new Set(shuffledEnergyOptions.map(energyCard => energyCard.id)),
    [shuffledEnergyOptions]
  )
  const selectedShuffledEnergyIdsForResolve = turn?.pendingAttackRequiresShuffledEnergy
    ? selectedShuffledEnergyCardInstanceIds.filter(id => shuffledEnergyOptionIds.has(id))
    : []
  const benchDamageTargetOptions = turn?.pendingAttackRequiresBenchDamageTarget ? (opponentPlayer?.bench ?? []) : []
  const selectedBenchDamageTargetIsValid = benchDamageTargetOptions.some(
    card => card.id === selectedBenchDamageTargetCardInstanceId
  )
  const benchDamageTargetIdForResolve = selectedBenchDamageTargetIsValid
    ? selectedBenchDamageTargetCardInstanceId
    : benchDamageTargetOptions.length === 1
      ? (benchDamageTargetOptions[0]?.id ?? null)
      : null

  useEffect(() => {
    if (selectedSwitchBenchCardInstanceId && !selectedSwitchTargetIsValid) {
      setSelectedSwitchBenchCardInstanceId('')
    }
  }, [selectedSwitchBenchCardInstanceId, selectedSwitchTargetIsValid])

  useEffect(() => {
    setSelectedDiscardedEnergyCardInstanceIds([])
    setSelectedReturnedEnergyCardInstanceId('')
    setSelectedShuffledEnergyCardInstanceIds([])
    setSelectedBenchDamageTargetCardInstanceId('')
  }, [turn?.id, turn?.pendingAttackId])

  useEffect(() => {
    setSelectedDiscardedEnergyCardInstanceIds(previousSelectedIds => {
      const filteredSelectedIds = previousSelectedIds.filter(id => discardedEnergyOptionIds.has(id))

      return filteredSelectedIds.length === previousSelectedIds.length ? previousSelectedIds : filteredSelectedIds
    })
  }, [discardedEnergyOptionIds])

  useEffect(() => {
    if (selectedReturnedEnergyCardInstanceId && !selectedReturnedEnergyIsValid) {
      setSelectedReturnedEnergyCardInstanceId('')
    }
  }, [selectedReturnedEnergyCardInstanceId, selectedReturnedEnergyIsValid])

  useEffect(() => {
    setSelectedShuffledEnergyCardInstanceIds(previousSelectedIds => {
      const filteredSelectedIds = previousSelectedIds.filter(id => shuffledEnergyOptionIds.has(id))

      return filteredSelectedIds.length === previousSelectedIds.length ? previousSelectedIds : filteredSelectedIds
    })
  }, [shuffledEnergyOptionIds])

  useEffect(() => {
    if (selectedBenchDamageTargetCardInstanceId && !selectedBenchDamageTargetIsValid) {
      setSelectedBenchDamageTargetCardInstanceId('')
    }
  }, [selectedBenchDamageTargetCardInstanceId, selectedBenchDamageTargetIsValid])

  if (!turn || (turn.status !== 'attack_declared' && turn.status !== 'attack_resolving')) {
    return null
  }

  const attacker = turn.pendingAttackerCardInstanceId ? cardsById.get(turn.pendingAttackerCardInstanceId) : null
  const defender = turn.pendingDefenderCardInstanceId ? cardsById.get(turn.pendingDefenderCardInstanceId) : null
  const attackLabel = turn.pendingAttackId ? formatEventType(turn.pendingAttackId) : 'declared attack'
  const viewerCanAdvanceAttack = viewerPlayerId === turn.activePlayerId && isPlayerId(turn.activePlayerId)
  const commandPending = Boolean(resolveDeclaredAttackPendingPlayerId || finishAttackPendingPlayerId)
  const switchTargetRequired = turn.pendingAttackRequiresSwitchTarget && switchTargetOptions.length > 1
  const discardedEnergyMaxSelection =
    turn.pendingAttackEffectType === DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT ? 2 : null
  const discardedEnergyDescription =
    turn.pendingAttackEffectType === DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT
      ? 'This attack does 60 more damage for each selected Energy attached to Benched Pokémon, then discards those Energy cards during resolution. Select up to 2, or select none for no bonus damage.'
      : turn.pendingAttackEffectType === DISCARD_OWN_BASIC_ENERGY_FOR_DAMAGE_EFFECT
        ? 'This attack does damage for each selected own Basic Energy attached to Pokémon in play, then discards those Energy cards during resolution. Selecting none resolves it for zero bonus damage.'
        : 'This attack resolves with the selected discarded Energy cards.'
  const returnedEnergyRequiresChoice = turn.pendingAttackRequiresReturnedEnergy && returnedEnergyOptions.length > 1
  const returnedEnergyUnavailable = turn.pendingAttackRequiresReturnedEnergy && returnedEnergyOptions.length === 0
  const shuffledEnergyRequiredCount = 3
  const shuffledEnergySelectedCount = selectedShuffledEnergyIdsForResolve.length
  const shuffledEnergyPartialSelection =
    turn.pendingAttackRequiresShuffledEnergy &&
    shuffledEnergySelectedCount > 0 &&
    shuffledEnergySelectedCount !== shuffledEnergyRequiredCount
  const benchDamageTargetRequired =
    turn.pendingAttackRequiresBenchDamageTarget &&
    shuffledEnergySelectedCount === shuffledEnergyRequiredCount &&
    benchDamageTargetOptions.length > 1
  const benchDamageTargetUnavailable =
    turn.pendingAttackRequiresBenchDamageTarget &&
    shuffledEnergySelectedCount === shuffledEnergyRequiredCount &&
    benchDamageTargetOptions.length === 0
  const missingActivePlayers = gameState.players.filter(player => !player.active)
  const viewerPromptBlocksFinish = viewerCanAdvanceAttack && gameState.prompts.length > 0
  const attackCannotFinish = missingActivePlayers.length > 0 || viewerPromptBlocksFinish
  const resolveDisabled =
    !viewerCanAdvanceAttack ||
    commandPending ||
    (switchTargetRequired && !selectedSwitchTargetIsValid) ||
    returnedEnergyUnavailable ||
    (returnedEnergyRequiresChoice && !selectedReturnedEnergyIsValid) ||
    shuffledEnergyPartialSelection ||
    benchDamageTargetUnavailable ||
    (benchDamageTargetRequired && !selectedBenchDamageTargetIsValid)
  const resolveButtonLabel = resolveDeclaredAttackPendingPlayerId === turn.activePlayerId
    ? `Resolving ${attackLabel}...`
    : switchTargetRequired && !selectedSwitchTargetIsValid
      ? `Choose a switch target for ${attackLabel}`
      : returnedEnergyUnavailable
        ? `No Energy available to return for ${attackLabel}`
        : returnedEnergyRequiresChoice && !selectedReturnedEnergyIsValid
          ? `Choose returned Energy for ${attackLabel}`
          : shuffledEnergyPartialSelection
            ? `Select exactly ${shuffledEnergyRequiredCount} Energy or none for ${attackLabel}`
            : benchDamageTargetUnavailable
              ? `No opponent Bench target for ${attackLabel}`
              : benchDamageTargetRequired && !selectedBenchDamageTargetIsValid
                ? `Choose a Bench damage target for ${attackLabel}`
      : `Resolve ${attackLabel}`
  const toggleDiscardedEnergyCard = (energyCardInstanceId: string) => {
    setSelectedDiscardedEnergyCardInstanceIds(previousSelectedIds => {
      if (previousSelectedIds.includes(energyCardInstanceId)) {
        return previousSelectedIds.filter(id => id !== energyCardInstanceId)
      }

      if (discardedEnergyMaxSelection && previousSelectedIds.length >= discardedEnergyMaxSelection) {
        return previousSelectedIds
      }

      return [...previousSelectedIds, energyCardInstanceId]
    })
  }

  const toggleShuffledEnergyCard = (energyCardInstanceId: string) => {
    setSelectedShuffledEnergyCardInstanceIds(previousSelectedIds => {
      if (previousSelectedIds.includes(energyCardInstanceId)) {
        return previousSelectedIds.filter(id => id !== energyCardInstanceId)
      }

      if (previousSelectedIds.length >= shuffledEnergyRequiredCount) {
        return previousSelectedIds
      }

      return [...previousSelectedIds, energyCardInstanceId]
    })
  }

  return (
    <Panel title="Attack resolution" trailing={<StatusBadge tone="warning">{turn.status}</StatusBadge>}>
      <div className="space-y-3 text-sm text-stone-700">
        <div className="grid gap-2 sm:grid-cols-2">
          <StateRow label="Attack" value={attackLabel} />
          <StateRow label="Active player" value={formatPlayerId(turn.activePlayerId)} />
          <StateRow label="Attacker" value={attacker?.name ?? formatNullableCardId(turn.pendingAttackerCardInstanceId)} />
          <StateRow label="Defender" value={defender?.name ?? formatNullableCardId(turn.pendingDefenderCardInstanceId)} />
        </div>

        <p className="text-xs leading-5 text-stone-500">
          Resolve applies the declared attack's currently executable damage/effect behavior. Finish closes the
          attack and ends the turn after resolution.
        </p>

        {turn.pendingAttackRequiresSwitchTarget ? (
          <div className="rounded-xl border border-emerald-200 bg-emerald-50/70 p-3">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-emerald-900">Switch target</p>
              <p className="text-xs leading-5 text-emerald-900/80">
                This attack switches the attacking Active Pokémon with one of {formatPlayerId(turn.activePlayerId)}'s
                Benched Pokémon after damage.
              </p>
            </div>

            {switchTargetOptions.length > 1 ? (
              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                {switchTargetOptions.map(card => {
                  const selected = card.id === selectedSwitchBenchCardInstanceId

                  return (
                    <label
                      className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 text-xs transition ${
                        selected
                          ? 'border-emerald-700 bg-emerald-100 text-emerald-950'
                          : 'border-emerald-200 bg-stone-50 text-stone-700 hover:border-emerald-400'
                      }`}
                      key={card.id}
                    >
                      <input
                        checked={selected}
                        className="mt-0.5"
                        disabled={!viewerCanAdvanceAttack || commandPending}
                        name="switch-bench-card-instance-id"
                        onChange={() => setSelectedSwitchBenchCardInstanceId(card.id)}
                        type="radio"
                      />
                      <span className="min-w-0">
                        <span className="block font-medium">{card.name}</span>
                        <span className="mt-0.5 block font-mono text-[0.68rem] opacity-70">{card.cardId}</span>
                      </span>
                    </label>
                  )
                })}
              </div>
            ) : switchTargetOptions.length === 1 ? (
              <p className="mt-3 rounded-lg border border-emerald-200 bg-stone-50 px-3 py-2 text-xs text-emerald-900">
                Only {switchTargetOptions[0]?.name} is Benched, so resolution will switch with it automatically.
              </p>
            ) : (
              <p className="mt-3 rounded-lg border border-emerald-200 bg-stone-50 px-3 py-2 text-xs text-emerald-900">
                No Benched Pokémon are available, so resolution will apply the attack without switching.
              </p>
            )}
          </div>
        ) : null}

        {turn.pendingAttackRequiresDiscardedEnergy ? (
          <div className="rounded-xl border border-orange-200 bg-orange-50/70 p-3">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-orange-900">Discarded Energy</p>
              <p className="text-xs leading-5 text-orange-900/80">
                {discardedEnergyDescription}
              </p>
            </div>

            {discardedEnergyOptions.length > 0 ? (
              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                {discardedEnergyOptions.map(({ attachedTo, energyCard }) => {
                  const selected = selectedDiscardedEnergyCardInstanceIds.includes(energyCard.id)
                  const maxSelectionReached = Boolean(
                    discardedEnergyMaxSelection &&
                      selectedDiscardedEnergyCardInstanceIds.length >= discardedEnergyMaxSelection
                  )

                  return (
                    <label
                      className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 text-xs transition ${
                        selected
                          ? 'border-orange-700 bg-orange-100 text-orange-950'
                          : 'border-orange-200 bg-stone-50 text-stone-700 hover:border-orange-400'
                      }`}
                      key={energyCard.id}
                    >
                      <input
                        checked={selected}
                        className="mt-0.5"
                        disabled={!viewerCanAdvanceAttack || commandPending || (!selected && maxSelectionReached)}
                        onChange={() => toggleDiscardedEnergyCard(energyCard.id)}
                        type="checkbox"
                      />
                      <span className="min-w-0">
                        <span className="block font-medium">{energyCard.name}</span>
                        <span className="mt-0.5 block font-mono text-[0.68rem] opacity-70">
                          attached to {attachedTo.name}
                        </span>
                      </span>
                    </label>
                  )
                })}
              </div>
            ) : (
              <p className="mt-3 rounded-lg border border-orange-200 bg-stone-50 px-3 py-2 text-xs text-orange-900">
                No attached Energy cards are visible for {formatPlayerId(turn.activePlayerId)}, so resolution will deal
                zero damage from this effect.
              </p>
            )}
          </div>
        ) : null}

        {turn.pendingAttackRequiresReturnedEnergy ? (
          <div className="rounded-xl border border-sky-200 bg-sky-50/70 p-3">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-sky-900">Returned Energy</p>
              <p className="text-xs leading-5 text-sky-900/80">
                This attack returns one Energy attached to the attacking Active Pokémon to that player's hand after
                damage. If exactly one Energy is attached, resolution will return it automatically.
              </p>
            </div>

            {returnedEnergyOptions.length > 1 ? (
              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                {returnedEnergyOptions.map(energyCard => {
                  const selected = energyCard.id === selectedReturnedEnergyCardInstanceId

                  return (
                    <label
                      className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 text-xs transition ${
                        selected
                          ? 'border-sky-700 bg-sky-100 text-sky-950'
                          : 'border-sky-200 bg-stone-50 text-stone-700 hover:border-sky-400'
                      }`}
                      key={energyCard.id}
                    >
                      <input
                        checked={selected}
                        className="mt-0.5"
                        disabled={!viewerCanAdvanceAttack || commandPending}
                        name="returned-energy-card-instance-id"
                        onChange={() => setSelectedReturnedEnergyCardInstanceId(energyCard.id)}
                        type="radio"
                      />
                      <span className="min-w-0">
                        <span className="block font-medium">{energyCard.name}</span>
                        <span className="mt-0.5 block font-mono text-[0.68rem] opacity-70">
                          attached to {attacker?.name ?? formatPlayerId(turn.activePlayerId)}
                        </span>
                      </span>
                    </label>
                  )
                })}
              </div>
            ) : returnedEnergyOptions.length === 1 ? (
              <p className="mt-3 rounded-lg border border-sky-200 bg-stone-50 px-3 py-2 text-xs text-sky-900">
                Only {returnedEnergyOptions[0]?.name} is attached, so resolution will return it automatically.
              </p>
            ) : (
              <p className="mt-3 rounded-lg border border-sky-200 bg-stone-50 px-3 py-2 text-xs text-sky-900">
                No attached Energy cards are visible for the attacking Active Pokémon, so this attack cannot resolve
                through the browser.
              </p>
            )}
          </div>
        ) : null}

        {turn.pendingAttackRequiresShuffledEnergy ? (
          <div className="rounded-xl border border-violet-200 bg-violet-50/70 p-3">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-violet-900">
                Shuffled Energy + Bench damage
              </p>
              <p className="text-xs leading-5 text-violet-900/80">
                This attack may shuffle exactly {shuffledEnergyRequiredCount} Energy attached to the attacking Active
                Pokémon into the deck. If you choose that option, select one opponent Benched Pokémon to receive 120
                damage. Select no Energy to skip the optional Bench damage.
              </p>
            </div>

            {shuffledEnergyOptions.length > 0 ? (
              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                {shuffledEnergyOptions.map(energyCard => {
                  const selected = selectedShuffledEnergyCardInstanceIds.includes(energyCard.id)
                  const maxSelectionReached = selectedShuffledEnergyCardInstanceIds.length >= shuffledEnergyRequiredCount

                  return (
                    <label
                      className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 text-xs transition ${
                        selected
                          ? 'border-violet-700 bg-violet-100 text-violet-950'
                          : 'border-violet-200 bg-stone-50 text-stone-700 hover:border-violet-400'
                      }`}
                      key={energyCard.id}
                    >
                      <input
                        checked={selected}
                        className="mt-0.5"
                        disabled={!viewerCanAdvanceAttack || commandPending || (!selected && maxSelectionReached)}
                        onChange={() => toggleShuffledEnergyCard(energyCard.id)}
                        type="checkbox"
                      />
                      <span className="min-w-0">
                        <span className="block font-medium">{energyCard.name}</span>
                        <span className="mt-0.5 block font-mono text-[0.68rem] opacity-70">
                          attached to {attacker?.name ?? formatPlayerId(turn.activePlayerId)}
                        </span>
                      </span>
                    </label>
                  )
                })}
              </div>
            ) : (
              <p className="mt-3 rounded-lg border border-violet-200 bg-stone-50 px-3 py-2 text-xs text-violet-900">
                No Energy is attached to the attacking Active Pokémon, so resolution will skip this optional effect.
              </p>
            )}

            {shuffledEnergySelectedCount > 0 ? (
              <div className="mt-3 rounded-xl border border-violet-200 bg-stone-50 p-3">
                <p className="text-xs font-semibold uppercase tracking-[0.14em] text-violet-900">
                  Opponent Bench target
                </p>

                {benchDamageTargetOptions.length > 1 ? (
                  <div className="mt-3 grid gap-2 sm:grid-cols-2">
                    {benchDamageTargetOptions.map(card => {
                      const selected = card.id === selectedBenchDamageTargetCardInstanceId

                      return (
                        <label
                          className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 text-xs transition ${
                            selected
                              ? 'border-violet-700 bg-violet-100 text-violet-950'
                              : 'border-violet-200 bg-stone-50 text-stone-700 hover:border-violet-400'
                          }`}
                          key={card.id}
                        >
                          <input
                            checked={selected}
                            className="mt-0.5"
                            disabled={!viewerCanAdvanceAttack || commandPending}
                            name="bench-damage-target-card-instance-id"
                            onChange={() => setSelectedBenchDamageTargetCardInstanceId(card.id)}
                            type="radio"
                          />
                          <span className="min-w-0">
                            <span className="block font-medium">{card.name}</span>
                            <span className="mt-0.5 block font-mono text-[0.68rem] opacity-70">
                              {card.damage} damage · {card.cardId}
                            </span>
                          </span>
                        </label>
                      )
                    })}
                  </div>
                ) : benchDamageTargetOptions.length === 1 ? (
                  <p className="mt-3 rounded-lg border border-violet-200 bg-violet-50 px-3 py-2 text-xs text-violet-900">
                    Only {benchDamageTargetOptions[0]?.name} is on the opponent Bench, so resolution will target it
                    automatically.
                  </p>
                ) : (
                  <p className="mt-3 rounded-lg border border-violet-200 bg-violet-50 px-3 py-2 text-xs text-violet-900">
                    No opponent Benched Pokémon are available. Clear the selected Energy cards to skip this optional
                    effect.
                  </p>
                )}
              </div>
            ) : null}
          </div>
        ) : null}

        {!viewerCanAdvanceAttack ? (
          <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            Switch this tab to {formatPlayerId(turn.activePlayerId)} to advance the attack.
          </p>
        ) : null}

        {attackCannotFinish ? (
          <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            {missingActivePlayers.length > 0
              ? `${missingActivePlayers.map(player => formatPlayerId(player.playerId)).join(', ')} must choose a replacement Active Pokémon before this attack can finish.`
              : 'Resolve the pending viewer prompt before this attack can finish.'}
          </p>
        ) : null}

        {turn.status === 'attack_declared' ? (
          <button
            className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
            disabled={resolveDisabled}
            onClick={() =>
              onResolveDeclaredAttack({
                playerId: turn.activePlayerId,
                switchBenchCardInstanceId: selectedSwitchTargetIsValid ? selectedSwitchBenchCardInstanceId : null,
                discardedEnergyCardInstanceIds: selectedDiscardedEnergyIdsForResolve,
                returnedEnergyCardInstanceId: returnedEnergyIdForResolve,
                shuffledEnergyCardInstanceIds: selectedShuffledEnergyIdsForResolve,
                benchDamageTargetCardInstanceId: benchDamageTargetIdForResolve
              })
            }
            type="button"
          >
            {resolveButtonLabel}
          </button>
        ) : null}

        {turn.status === 'attack_resolving' ? (
          <button
            className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
            disabled={!viewerCanAdvanceAttack || commandPending || attackCannotFinish}
            onClick={() => onFinishAttack({ playerId: turn.activePlayerId })}
            type="button"
          >
            {finishAttackPendingPlayerId === turn.activePlayerId ? 'Finishing attack...' : 'Finish attack and end turn'}
          </button>
        ) : null}
      </div>
    </Panel>
  )
}

function ActionAffordancesPanel({
  actions,
  cardsById,
  chooseReplacementActivePendingCardId,
  onAttachEnergy,
  onChooseReplacementActive,
  onDeclareAttack,
  onEndTurn,
  onEvolveFromHand,
  onPlayBasicToBench,
  onPlayCard,
  onRetreat,
  attachEnergyPendingKey,
  declareAttackPendingKey,
  endTurnPendingPlayerId,
  evolveFromHandPendingKey,
  playBasicToBenchPendingCardId,
  playCardPendingCardId,
  retreatPendingKey
}: {
  actions: ActionAffordance[]
  cardsById: Map<string, CardSummary>
  chooseReplacementActivePendingCardId: string | null
  onAttachEnergy: (input: AttachEnergyCommand) => void
  onChooseReplacementActive: (input: ChooseReplacementActiveCommand) => void
  onDeclareAttack: (input: DeclareAttackCommand) => void
  onEndTurn: (input: EndTurnCommand) => void
  onEvolveFromHand: (input: EvolveFromHandCommand) => void
  onPlayBasicToBench: (input: PlayBasicToBenchCommand) => void
  onPlayCard: (input: PlayCardCommand) => void
  onRetreat: (input: RetreatCommand) => void
  attachEnergyPendingKey: string | null
  declareAttackPendingKey: string | null
  endTurnPendingPlayerId: string | null
  evolveFromHandPendingKey: string | null
  playBasicToBenchPendingCardId: string | null
  playCardPendingCardId: string | null
  retreatPendingKey: string | null
}) {
  const actionCommandPending = Boolean(
    playCardPendingCardId ||
      playBasicToBenchPendingCardId ||
      attachEnergyPendingKey ||
      chooseReplacementActivePendingCardId ||
      declareAttackPendingKey ||
      endTurnPendingPlayerId ||
      evolveFromHandPendingKey ||
      retreatPendingKey
  )

  return (
    <Panel
      title="Viewer legal actions"
      trailing={<StatusBadge tone={actions.length > 0 ? 'active' : 'neutral'}>{actions.length}</StatusBadge>}
    >
      {actions.length > 0 ? (
        <ul className="space-y-2">
          {actions.map(action => (
            <li
              className="rounded-xl border border-stone-200 bg-stone-50 px-3 py-3 text-sm"
              key={actionKey(action)}
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-medium text-stone-950">{action.label}</p>
                  <p className="mt-1 text-xs text-stone-500">
                    Available for {formatPlayerId(action.playerId)}
                  </p>
                </div>
                <StatusBadge tone={action.kind === 'prompt' ? 'warning' : 'active'}>
                  {formatEventType(action.kind)}
                </StatusBadge>
              </div>

              {action.note ? <p className="mt-2 text-xs leading-5 text-stone-600">{action.note}</p> : null}

              {actionHasMetadata(action) ? (
                <details className="mt-3 rounded-lg border border-stone-200 bg-stone-100 px-3 py-2 text-xs text-stone-600">
                  <summary className="cursor-pointer font-medium text-stone-700">Action metadata</summary>
                  <div className="mt-2 flex flex-wrap gap-2">
                    <ActionCount count={action.sourceCardInstanceIds.length} label="source" />
                    <ActionCount count={action.targetCardInstanceIds.length} label="target" />
                    <ActionCount count={action.requiredSourceCount} label="required source" />
                    <ActionCount count={action.promptIds.length} label="prompt" />
                    <ActionCount count={action.choiceKeys.length} label="choice key" />
                  </div>
                </details>
              ) : null}

              {action.key === 'play_card' && action.sourceCardInstanceIds.length > 0 ? (
                <div className="mt-3 space-y-2">
                  {action.sourceCardInstanceIds.map(cardInstanceId => {
                    const card = cardsById.get(cardInstanceId)
                    const isPending = playCardPendingCardId === cardInstanceId

                    return (
                      <button
                        className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                        disabled={actionCommandPending || !isPlayerId(action.playerId)}
                        key={cardInstanceId}
                        onClick={() => onPlayCard({ playerId: action.playerId, cardInstanceId })}
                        type="button"
                      >
                        {isPending ? `Playing ${card?.name ?? 'card'}...` : `Play ${card?.name ?? formatCardInstanceId(cardInstanceId)}`}
                      </button>
                    )
                  })}
                </div>
              ) : null}

              {action.key === 'play_basic_to_bench' && action.sourceCardInstanceIds.length > 0 ? (
                <div className="mt-3 space-y-2">
                  {action.sourceCardInstanceIds.map(cardInstanceId => {
                    const card = cardsById.get(cardInstanceId)
                    const isPending = playBasicToBenchPendingCardId === cardInstanceId

                    return (
                      <button
                        className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                        disabled={actionCommandPending || !isPlayerId(action.playerId)}
                        key={cardInstanceId}
                        onClick={() => onPlayBasicToBench({ playerId: action.playerId, cardInstanceId })}
                        type="button"
                      >
                        {isPending
                          ? `Benching ${card?.name ?? 'Pokémon'}...`
                          : `Bench ${card?.name ?? formatCardInstanceId(cardInstanceId)}`}
                      </button>
                    )
                  })}
                </div>
              ) : null}

              {action.key === 'evolve_from_hand' &&
              action.sourceCardInstanceIds.length > 0 &&
              action.targetCardInstanceIds.length > 0 ? (
                <div className="mt-3 space-y-2">
                  {action.sourceCardInstanceIds.flatMap(evolutionCardInstanceId =>
                    action.targetCardInstanceIds.map(targetCardInstanceId => {
                      const evolutionCard = cardsById.get(evolutionCardInstanceId)
                      const targetCard = cardsById.get(targetCardInstanceId)
                      const evolutionActionKey = evolveKey(evolutionCardInstanceId, targetCardInstanceId)
                      const isPending = evolveFromHandPendingKey === evolutionActionKey

                      return (
                        <button
                          className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                          disabled={actionCommandPending || !isPlayerId(action.playerId)}
                          key={evolutionActionKey}
                          onClick={() =>
                            onEvolveFromHand({
                              playerId: action.playerId,
                              evolutionCardInstanceId,
                              targetCardInstanceId
                            })
                          }
                          type="button"
                        >
                          {isPending
                            ? `Evolving ${targetCard?.name ?? 'Pokémon'}...`
                            : `Evolve ${targetCard?.name ?? formatCardInstanceId(targetCardInstanceId)} into ${
                                evolutionCard?.name ?? formatCardInstanceId(evolutionCardInstanceId)
                              }`}
                        </button>
                      )
                    })
                  )}
                </div>
              ) : null}

              {action.key === 'attach_energy' &&
              action.sourceCardInstanceIds.length > 0 &&
              action.targetCardInstanceIds.length > 0 ? (
                <div className="mt-3 space-y-2">
                  {action.sourceCardInstanceIds.flatMap(energyCardInstanceId =>
                    action.targetCardInstanceIds.map(targetCardInstanceId => {
                      const energyCard = cardsById.get(energyCardInstanceId)
                      const targetCard = cardsById.get(targetCardInstanceId)
                      const pairKey = attachEnergyPairKey(energyCardInstanceId, targetCardInstanceId)
                      const isPending = attachEnergyPendingKey === pairKey

                      return (
                        <button
                          className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                          disabled={actionCommandPending || !isPlayerId(action.playerId)}
                          key={pairKey}
                          onClick={() =>
                            onAttachEnergy({
                              playerId: action.playerId,
                              energyCardInstanceId,
                              targetCardInstanceId
                            })
                          }
                          type="button"
                        >
                          {isPending
                            ? `Attaching ${energyCard?.name ?? 'Energy'}...`
                            : `Attach ${energyCard?.name ?? formatCardInstanceId(energyCardInstanceId)} to ${
                                targetCard?.name ?? formatCardInstanceId(targetCardInstanceId)
                              }`}
                        </button>
                      )
                    })
                  )}
                </div>
              ) : null}

              {action.key === 'retreat' && action.targetCardInstanceIds.length > 0 ? (
                <div className="mt-3 space-y-2">
                  {action.targetCardInstanceIds.flatMap(benchCardInstanceId =>
                    retreatPaymentOptions(action.sourceCardInstanceIds, action.requiredSourceCount).map(
                      energyCardInstanceIds => {
                        const benchCard = cardsById.get(benchCardInstanceId)
                        const paymentKey = retreatKey(benchCardInstanceId, energyCardInstanceIds)
                        const isPending = retreatPendingKey === paymentKey

                        return (
                          <button
                            className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                            disabled={actionCommandPending || !isPlayerId(action.playerId)}
                            key={paymentKey}
                            onClick={() =>
                              onRetreat({
                                playerId: action.playerId,
                                benchCardInstanceId,
                                energyCardInstanceIds
                              })
                            }
                            type="button"
                          >
                            {isPending
                              ? `Retreating to ${benchCard?.name ?? 'Bench'}...`
                              : `Retreat to ${benchCard?.name ?? formatCardInstanceId(benchCardInstanceId)}${retreatPaymentLabel(
                                  energyCardInstanceIds,
                                  cardsById
                                )}`}
                          </button>
                        )
                      }
                    )
                  )}
                </div>
              ) : null}

              {action.key === 'choose_replacement_active' && action.targetCardInstanceIds.length > 0 ? (
                <div className="mt-3 space-y-2">
                  {action.targetCardInstanceIds.map(benchCardInstanceId => {
                    const benchCard = cardsById.get(benchCardInstanceId)
                    const isPending = chooseReplacementActivePendingCardId === benchCardInstanceId

                    return (
                      <button
                        className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                        disabled={actionCommandPending || !isPlayerId(action.playerId)}
                        key={benchCardInstanceId}
                        onClick={() =>
                          onChooseReplacementActive({
                            playerId: action.playerId,
                            benchCardInstanceId
                          })
                        }
                        type="button"
                      >
                        {isPending
                          ? `Promoting ${benchCard?.name ?? 'Bench'}...`
                          : `Promote ${benchCard?.name ?? formatCardInstanceId(benchCardInstanceId)} to Active`}
                      </button>
                    )
                  })}
                </div>
              ) : null}

              {action.key === 'declare_attack' && action.attackId ? (
                <button
                  className="mt-3 w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                  disabled={actionCommandPending || !isPlayerId(action.playerId)}
                  onClick={() => onDeclareAttack({ playerId: action.playerId, attackId: action.attackId! })}
                  type="button"
                >
                  {declareAttackPendingKey === attackKey(action.playerId, action.attackId)
                    ? `Declaring ${action.attackName ?? 'attack'}...`
                    : `Declare ${action.attackName ?? formatEventType(action.attackId)}${attackCostLabel(
                        action.attackCost
                      )}${attackDamageLabel(action.attackDamage)}`}
                </button>
              ) : null}

              {action.key === 'end_turn' ? (
                <button
                  className="mt-3 w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                  disabled={actionCommandPending || !isPlayerId(action.playerId)}
                  onClick={() => onEndTurn({ playerId: action.playerId })}
                  type="button"
                >
                  {endTurnPendingPlayerId === action.playerId
                    ? `Ending ${formatPlayerId(action.playerId)}'s turn...`
                    : `End ${formatPlayerId(action.playerId)}'s turn`}
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      ) : (
        <EmptyState title="No viewer action available">
          Action window commands appear for the active viewer. Prompt choices and replacement Active choices
          appear when pending effects or knockouts ask this player to choose.
        </EmptyState>
      )}
    </Panel>
  )
}

function ActionCount({ count, label }: { count: number; label: string }) {
  if (count === 0) {
    return null
  }

  return (
    <span className="rounded-full bg-stone-200 px-2 py-0.5 text-xs font-medium text-stone-600">
      {count} {label}
      {count === 1 ? '' : 's'}
    </span>
  )
}

function actionHasMetadata(action: ActionAffordance) {
  return (
    action.sourceCardInstanceIds.length > 0 ||
    action.targetCardInstanceIds.length > 0 ||
    action.requiredSourceCount > 0 ||
    action.promptIds.length > 0 ||
    action.choiceKeys.length > 0
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
  const attachedCards = card.attachedCards ?? []

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

      {attachedCards.length > 0 ? (
        <div className="mt-3 rounded-lg border border-stone-200 bg-stone-100 px-2.5 py-2">
          <p className="text-xs font-medium uppercase tracking-[0.12em] text-stone-500">Attached</p>
          <div className="mt-2 flex flex-wrap gap-1.5">
            {attachedCards.map(attachedCard => (
              <span
                className="rounded-full bg-stone-50 px-2 py-1 text-xs font-medium text-stone-700"
                key={attachedCard.id}
                title={`${attachedCard.cardId} · ${formatEventType(attachedCard.zone)}`}
              >
                {attachedCard.name}
              </span>
            ))}
          </div>
        </div>
      ) : null}
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

  return {
    gameId: readStoredGameId(),
    viewerPlayerId: readStoredViewerPlayerId()
  }
}

function setStoredSession(session: PlaytestSession) {
  if (typeof window === 'undefined') {
    return
  }

  if (session.gameId) {
    window.localStorage.setItem(GAME_ID_STORAGE_KEY, session.gameId)
  } else {
    window.localStorage.removeItem(GAME_ID_STORAGE_KEY)
  }

  window.localStorage.removeItem(LEGACY_SESSION_STORAGE_KEY)
  window.sessionStorage.setItem(VIEWER_STORAGE_KEY, session.viewerPlayerId)
}

function readStoredGameId() {
  try {
    const storedGameId = window.localStorage.getItem(GAME_ID_STORAGE_KEY)

    if (storedGameId !== null) {
      return storedGameId
    }

    return readLegacyStoredGameId()
  } catch {
    return ''
  }
}

function readLegacyStoredGameId() {
  try {
    const item = window.localStorage.getItem(LEGACY_SESSION_STORAGE_KEY)

    if (!item) {
      return ''
    }

    const parsed = JSON.parse(item) as Partial<PlaytestSession>

    return typeof parsed.gameId === 'string' ? parsed.gameId : ''
  } catch {
    return ''
  }
}

function readStoredViewerPlayerId() {
  try {
    const viewerPlayerId = window.sessionStorage.getItem(VIEWER_STORAGE_KEY)

    return isPlayerId(viewerPlayerId) ? viewerPlayerId : PLAYER_ONE_ID
  } catch {
    return PLAYER_ONE_ID
  }
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

function isEnergyCard(card: CardSummary) {
  return card.category === 'energy'
}

function promptLegalChoiceIds(payload: Record<string, unknown>) {
  const value = payload.legal_choices

  if (!Array.isArray(value)) {
    return []
  }

  return value.filter((cardInstanceId): cardInstanceId is string => typeof cardInstanceId === 'string')
}

function promptLegalChoiceCards(payload: Record<string, unknown>) {
  const value = payload.legal_choice_cards

  if (!Array.isArray(value)) {
    return []
  }

  return value.filter(isCardSummary)
}

function promptLegalChoiceLabels(payload: Record<string, unknown>) {
  const value = payload.legal_choice_labels

  if (!Array.isArray(value)) {
    return []
  }

  return value.filter(isPromptChoiceLabel)
}

function isPromptChoiceLabel(value: unknown): value is { id: string; label: string; detail?: string | null } {
  if (!value || typeof value !== 'object') {
    return false
  }

  const choice = value as { id?: unknown; label?: unknown }

  return typeof choice.id === 'string' && typeof choice.label === 'string'
}

function isCardSummary(value: unknown): value is CardSummary {
  if (!value || typeof value !== 'object') {
    return false
  }

  const card = value as Partial<CardSummary>

  return typeof card.id === 'string' && typeof card.name === 'string'
}

function promptChoiceCount(payload: Record<string, unknown>, key: 'min' | 'max', fallback: number) {
  const value = payload[key]

  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function promptChoiceInstruction(min: number, max: number) {
  if (min === max) {
    return `choose ${min} ${min === 1 ? 'card' : 'cards'}`
  }

  return `choose ${min}-${max} cards`
}

function promptChoiceKey(payload: Record<string, unknown>) {
  const value = payload.choice_key

  return typeof value === 'string' ? value : 'prompt_choice'
}

function promptChoiceCardDetail(
  card: CardSummary | undefined,
  cardInstanceId: string,
  choiceLabel?: { detail?: string | null }
) {
  if (!card) {
    return choiceLabel?.detail ?? formatCardInstanceId(cardInstanceId)
  }

  return [card.cardId, card.category ? formatEventType(card.category) : null, formatEventType(card.zone)]
    .filter(Boolean)
    .join(' · ')
}

function actionKey(action: ActionAffordance) {
  return [
    action.key,
    action.attackId ?? '',
    ...action.sourceCardInstanceIds,
    ...action.targetCardInstanceIds,
    ...action.promptIds,
    ...action.choiceKeys
  ].join(':')
}

function attachEnergyPairKey(energyCardInstanceId: string, targetCardInstanceId: string) {
  return `${energyCardInstanceId}:${targetCardInstanceId}`
}

function evolveKey(evolutionCardInstanceId: string, targetCardInstanceId: string) {
  return `${evolutionCardInstanceId}:${targetCardInstanceId}`
}

function retreatKey(benchCardInstanceId: string, energyCardInstanceIds: string[]) {
  return `${benchCardInstanceId}:${energyCardInstanceIds.join(',')}`
}

function attackKey(playerId: string, attackId: string) {
  return `${playerId}:${attackId}`
}

function attackCostLabel(cost: string[]) {
  if (cost.length === 0) {
    return ' for free'
  }

  return ` for ${cost.map(formatEventType).join(' + ')}`
}

function attackDamageLabel(damage: string | null) {
  return damage ? ` (${damage} damage)` : ''
}

function formatNullableCardId(cardInstanceId: string | null) {
  return cardInstanceId ? formatCardInstanceId(cardInstanceId) : 'None'
}

function retreatPaymentOptions(sourceCardInstanceIds: string[], requiredSourceCount: number) {
  if (requiredSourceCount === 0) {
    return [[]]
  }

  if (requiredSourceCount < 0 || sourceCardInstanceIds.length < requiredSourceCount) {
    return []
  }

  return cardCombinations(sourceCardInstanceIds, requiredSourceCount)
}

function cardCombinations(cardInstanceIds: string[], count: number): string[][] {
  if (count === 0) {
    return [[]]
  }

  if (cardInstanceIds.length < count) {
    return []
  }

  const [firstCardInstanceId, ...remainingCardInstanceIds] = cardInstanceIds
  const withFirst = cardCombinations(remainingCardInstanceIds, count - 1).map(combination => [
    firstCardInstanceId,
    ...combination
  ])
  const withoutFirst = cardCombinations(remainingCardInstanceIds, count)

  return [...withFirst, ...withoutFirst]
}

function retreatPaymentLabel(energyCardInstanceIds: string[], cardsById: Map<string, CardSummary>) {
  if (energyCardInstanceIds.length === 0) {
    return ' for free'
  }

  const names = energyCardInstanceIds.map(cardInstanceId => cardsById.get(cardInstanceId)?.name ?? formatCardInstanceId(cardInstanceId))

  return `, discarding ${names.join(' + ')}`
}

function visibleCardsById(gameState: GameState) {
  const cards = new Map<string, CardSummary>()

  for (const player of gameState.players) {
    if (player.active) {
      addVisibleCard(cards, player.active)
    }

    for (const card of [...player.bench, ...player.hand, ...player.discard]) {
      addVisibleCard(cards, card)
    }
  }

  if (gameState.stadium) {
    addVisibleCard(cards, gameState.stadium)
  }

  return cards
}

function addVisibleCard(cards: Map<string, CardSummary>, card: CardSummary) {
  cards.set(card.id, card)

  for (const attachedCard of card.attachedCards ?? []) {
    cards.set(attachedCard.id, attachedCard)
  }
}

function formatCardInstanceId(cardInstanceId: string) {
  return `card ${cardInstanceId.slice(0, 8)}`
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
