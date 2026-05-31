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
const ULTRA_BALL_POST_SEARCH_HANDOFF_STORAGE_KEY = 'prizmo:tcg-ultra-ball-post-search-handoff'
const DISCARD_OWN_BASIC_ENERGY_FOR_DAMAGE_EFFECT = 'damage_per_discarded_own_basic_energy'
const DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT = 'discard_energy_from_own_bench_for_bonus_damage'
const DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT = 'discard_defending_energy_on_coin_heads'
const SHUFFLE_ATTACHED_ENERGY_INTO_DECK_THEN_DAMAGE_OPPONENT_BENCH_EFFECT =
  'shuffle_attached_energy_into_deck_then_damage_opponent_bench'
const COPY_OPPONENT_ACTIVE_TERA_POKEMON_ATTACK_EFFECT = 'copy_opponent_active_tera_pokemon_attack'
const ULTRA_BALL_CARD_ID = 'MEG-131'

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
  'awaitingPromptPlayerIds',
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
      'pendingAttackRequiresBenchDamageCounters',
      'pendingAttackRequiresCoinResult',
      'pendingAttackRequiresHeadsCount',
      'pendingAttackRequiresCopiedAttack',
      { pendingAttackCopyChoices: ['attackId', 'attackName', 'attackDamage', 'attackEffectType'] },
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
type CoinResult = 'heads' | 'tails'
type ResolutionChecklistTone = 'blocked' | 'ready' | 'waiting'
type SetupGuideState = 'done' | 'needed' | 'next' | 'ready'

type ResolutionChecklistItem = {
  label: string
  tone: ResolutionChecklistTone
  value: string
}

type PromptFlowStep = {
  label: string
  title: string
  detail: string
  tone: 'complete' | 'focus' | 'next'
}

type PromptFlowGuide = {
  eyebrow: string
  title: string
  detail: string
  steps: PromptFlowStep[]
}

type PromptChoiceLabel = {
  id: string
  label: string
  detail?: string | null
}

type PromptChoiceRow = {
  cardInstanceId: string
  card: CardSummary | undefined
  choiceLabel: PromptChoiceLabel | undefined
  detail: string
  includesCopyLabel: boolean
  label: string
}

type UltraBallPostSearchHandoff = {
  gameId: string
  playerId: PlayerId
  selectedCardInstanceIds: string[]
}

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

type CommandErrorNotice = {
  title: string
  message: string
  recovery: string
}

type ActionGroupId = 'required' | 'hand' | 'battle' | 'turn' | 'other'

type ActionGroup = {
  id: ActionGroupId
  title: string
  description: string
  actions: ActionAffordance[]
}

type EvolutionCommandOption = {
  key: string
  evolutionCardInstanceId: string
  targetCardInstanceId: string
  evolutionCard: CardSummary | undefined
  targetCard: CardSummary | undefined
  baseLabel: string
}

type BasicBenchCommandOption = {
  key: string
  cardInstanceId: string
  card: CardSummary | undefined
  baseLabel: string
}

type PlayCardCommandOption = {
  key: string
  cardInstanceId: string
  card: CardSummary | undefined
  baseLabel: string
}

type ActionRenderEntry = {
  key: string
  action: ActionAffordance
  benchOptions?: BasicBenchCommandOption[]
  evolutionOptions?: EvolutionCommandOption[]
}

const ACTION_GROUPS: Array<Omit<ActionGroup, 'actions'>> = [
  {
    id: 'required',
    title: 'Required choices',
    description: 'Resolve forced choices before the game can advance.'
  },
  {
    id: 'battle',
    title: 'Battle decisions',
    description: 'Retreat or declare a paid attack with the Active Pokémon.'
  },
  {
    id: 'hand',
    title: 'Hand and board',
    description: 'Play cards from hand, evolve Pokémon, and attach Energy.'
  },
  {
    id: 'turn',
    title: 'Turn flow',
    description: 'Pass priority back to the engine when this turn is done.'
  },
  {
    id: 'other',
    title: 'Other engine actions',
    description: 'Additional engine commands exposed by the current state.'
  }
]

type AttackCopyChoice = {
  attackId: string
  attackName: string
  attackDamage: string | null
  attackEffectType: string | null
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
  benchDamageCounterAllocations?: Record<string, number>
  coinResult?: CoinResult | null
  headsCount?: number | null
  copiedAttackId?: string | null
}

type ResolveDeclaredAttackCommand = {
  playerId: string
  switchBenchCardInstanceId?: string | null
  discardedEnergyCardInstanceIds?: string[]
  returnedEnergyCardInstanceId?: string | null
  shuffledEnergyCardInstanceIds?: string[]
  benchDamageTargetCardInstanceId?: string | null
  benchDamageCounterAllocations?: Record<string, number>
  coinResult?: CoinResult | null
  headsCount?: number | null
  copiedAttackId?: string | null
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
  choiceKey?: string
}

type ChoosePromptCommand = {
  playerId: string
  promptId: string
  selectedCardInstanceIds: string[]
  choiceKey?: string
}

type SetupCardCommand = {
  playerId: string
  cardInstanceId: string
}

type TurnPlayerCommand = {
  playerId: string
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
  awaitingPromptPlayerIds: string[]
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
    pendingAttackRequiresBenchDamageCounters: boolean
    pendingAttackRequiresCoinResult: boolean
    pendingAttackRequiresHeadsCount: boolean
    pendingAttackRequiresCopiedAttack: boolean
    pendingAttackCopyChoices: AttackCopyChoice[]
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
  const [ultraBallPostSearchHandoff, setUltraBallPostSearchHandoff] =
    useState<UltraBallPostSearchHandoff | null>(readStoredUltraBallPostSearchHandoff)

  useEffect(() => {
    setStoredSession(session)
  }, [session])

  useEffect(() => {
    setStoredUltraBallPostSearchHandoff(ultraBallPostSearchHandoff)
  }, [ultraBallPostSearchHandoff])

  const decksQuery = useQuery({
    queryKey: ['tcg-engine', 'supported-decks'],
    queryFn: listSupportedDecks
  })

  const decks = decksQuery.data ?? []
  const selectedPlayerOneDeckKey = playerOneDeckKey || decks[0]?.deckKey || ''
  const selectedPlayerTwoDeckKey = playerTwoDeckKey || decks[1]?.deckKey || decks[0]?.deckKey || ''
  const normalisedGameId = session.gameId.trim()

  useEffect(() => {
    setUltraBallPostSearchHandoff(currentHandoff => {
      if (!currentHandoff) {
        return null
      }

      if (currentHandoff.gameId !== normalisedGameId || currentHandoff.playerId !== session.viewerPlayerId) {
        return null
      }

      return currentHandoff
    })
  }, [normalisedGameId, session.viewerPlayerId])

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
    onSuccess: async (_game, input) => {
      clearUltraBallPostSearchHandoff(input.gameId, input.playerId)
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const playBasicToBenchMutation = useMutation({
    mutationFn: (input: PlayBasicToBenchInput) => playBasicToBench(input),
    onSuccess: async (_game, input) => {
      clearUltraBallPostSearchHandoff(input.gameId, input.playerId)
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const evolveFromHandMutation = useMutation({
    mutationFn: (input: EvolveFromHandInput) => evolveFromHand(input),
    onSuccess: async (_game, input) => {
      clearUltraBallPostSearchHandoff(input.gameId, input.playerId)
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const attachEnergyMutation = useMutation({
    mutationFn: (input: AttachEnergyInput) => attachEnergy(input),
    onSuccess: async (_game, input) => {
      clearUltraBallPostSearchHandoff(input.gameId, input.playerId)
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const endTurnMutation = useMutation({
    mutationFn: (input: EndTurnInput) => endTurn(input),
    onSuccess: async (_game, input) => {
      clearUltraBallPostSearchHandoff(input.gameId, input.playerId)
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const retreatMutation = useMutation({
    mutationFn: (input: RetreatInput) => retreat(input),
    onSuccess: async (_game, input) => {
      clearUltraBallPostSearchHandoff(input.gameId, input.playerId)
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const declareAttackMutation = useMutation({
    mutationFn: (input: DeclareAttackInput) => declareAttack(input),
    onSuccess: async (_game, input) => {
      clearUltraBallPostSearchHandoff(input.gameId, input.playerId)
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
    onSuccess: async (_game, input) => {
      if (input.choiceKey === 'search_deck_for_pokemon') {
        setUltraBallPostSearchHandoff({
          gameId: input.gameId,
          playerId: input.playerId,
          selectedCardInstanceIds: input.selectedCardInstanceIds
        })
      } else {
        setUltraBallPostSearchHandoff(null)
      }

      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const queriedGameState = gameStateQuery.data
  const gameStateHasViewerMismatch = Boolean(
    queriedGameState && queriedGameState.viewerPlayerId !== session.viewerPlayerId
  )
  const gameState = gameStateHasViewerMismatch ? undefined : queriedGameState
  const deckNamesByKey = useMemo(
    () => new Map(decks.map(deck => [deck.deckKey, deck.name])),
    [decks]
  )
  const selectedPlayerOneDeck = useMemo(
    () => decks.find(deck => deck.deckKey === selectedPlayerOneDeckKey) ?? null,
    [decks, selectedPlayerOneDeckKey]
  )
  const selectedPlayerTwoDeck = useMemo(
    () => decks.find(deck => deck.deckKey === selectedPlayerTwoDeckKey) ?? null,
    [decks, selectedPlayerTwoDeckKey]
  )
  const canCreateGame =
    Boolean(selectedPlayerOneDeckKey && selectedPlayerTwoDeckKey) && !createGameMutation.isPending
  const promptCommandError = commandErrorNotice(
    choosePromptMutation.error,
    'Prompt choice failed',
    'No prompt choice was saved. Confirm this tab is viewing the prompted player, refresh state, then choose again.'
  )
  const attackCommandError =
    commandErrorNotice(
      resolveDeclaredAttackMutation.error,
      'Attack resolution failed',
      'The attack was not advanced. Check the resolve requirements above, confirm the active player is viewing this tab, then retry.'
    ) ??
    commandErrorNotice(
      finishAttackMutation.error,
      'Finish attack failed',
      'The turn was not advanced. Resolve any Prize, prompt, or replacement Active blocker, then retry finishing the attack.'
    )
  const flowCommandError =
    commandErrorNotice(
      startSetupMutation.error,
      'Setup start failed',
      'Setup was not started. Refresh state and retry only if the table still has no setup record.'
    ) ??
    commandErrorNotice(
      drawOpeningHandMutation.error,
      'Opening hand failed',
      'Opening hands were not changed. Refresh state and retry only while setup is waiting to draw.'
    ) ??
    commandErrorNotice(
      chooseActiveMutation.error,
      'Setup Active choice failed',
      'No Active Pokémon was chosen. Confirm the selected card is still a visible Basic in this viewer hand, then retry.'
    ) ??
    commandErrorNotice(
      chooseSetupBenchMutation.error,
      'Setup Bench choice failed',
      'No setup Bench Pokémon was added. Confirm this viewer has an Active Pokémon and an open Bench slot, then retry.'
    ) ??
    commandErrorNotice(
      placePrizesMutation.error,
      'Prize placement failed',
      'Prizes were not placed. Confirm both players have an Active Pokémon, refresh state, then retry.'
    ) ??
    commandErrorNotice(
      completeSetupMutation.error,
      'Setup completion failed',
      'Setup was not completed. Confirm Prizes are placed and no setup choice is still pending, then retry.'
    ) ??
    commandErrorNotice(
      startNextTurnMutation.error,
      'Turn start failed',
      'No new turn was started. Refresh state and retry only when setup is complete and the prior turn is ended.'
    ) ??
    commandErrorNotice(
      drawForTurnMutation.error,
      'Draw for turn failed',
      'The draw step was not advanced. Confirm the current turn is still at start and the active player has priority.'
    ) ??
    commandErrorNotice(
      skipDrawForTurnMutation.error,
      'Skip draw failed',
      'The draw step was not skipped. Confirm the current turn is still at start, then retry.'
    ) ??
    commandErrorNotice(
      openActionWindowMutation.error,
      'Open action window failed',
      'The action window was not opened. Confirm the draw step is resolved, refresh state, then retry.'
    )
  const actionCommandError =
    commandErrorNotice(
      playCardMutation.error,
      'Play card failed',
      'The card stayed in place. Refresh state and confirm the card is still playable from this viewer hand.'
    ) ??
    commandErrorNotice(
      playBasicToBenchMutation.error,
      'Bench Basic failed',
      'No Pokémon was Benched. Confirm the card is a visible Basic and this viewer has an open Bench slot.'
    ) ??
    commandErrorNotice(
      evolveFromHandMutation.error,
      'Evolution failed',
      'No evolution was applied. Confirm turn timing, target eligibility, and this viewer hand before retrying.'
    ) ??
    commandErrorNotice(
      attachEnergyMutation.error,
      'Attach Energy failed',
      'Energy was not attached. Confirm this player has not already attached Energy this turn, then retry.'
    ) ??
    commandErrorNotice(
      retreatMutation.error,
      'Retreat failed',
      'The Active Pokémon did not retreat. Confirm retreat cost, target Bench Pokémon, and turn restrictions.'
    ) ??
    commandErrorNotice(
      declareAttackMutation.error,
      'Attack declaration failed',
      'No attack was declared. Confirm the Active Pokémon can pay the cost and is not blocked by a marker.'
    ) ??
    commandErrorNotice(
      chooseReplacementActiveMutation.error,
      'Replacement Active failed',
      'No replacement was promoted. Confirm this viewer owns the required choice and the Bench target is still present.'
    ) ??
    commandErrorNotice(
      endTurnMutation.error,
      'End turn failed',
      'The turn stayed open. Refresh state and confirm no required prompt, attack, or replacement choice is blocking.'
    )

  function updateSession(updater: (currentSession: PlaytestSession) => PlaytestSession) {
    setSession(currentSession => updater(currentSession))
  }

  function clearGame() {
    updateSession(currentSession => ({ ...currentSession, gameId: '' }))
    queryClient.removeQueries({ queryKey: ['tcg-engine', 'game-state'] })
  }

  function clearUltraBallPostSearchHandoff(gameId: string, playerId: PlayerId) {
    setUltraBallPostSearchHandoff(currentHandoff =>
      currentHandoff?.gameId === gameId && currentHandoff.playerId === playerId ? null : currentHandoff
    )
  }

  return (
    <main className="min-h-screen bg-stone-50 text-stone-950">
      <div className="mx-auto flex w-full max-w-[96rem] flex-col gap-8 px-5 py-6 sm:px-8 lg:px-10">
        <header className="flex flex-col gap-5 border-b border-stone-200 pb-6 lg:flex-row lg:items-end lg:justify-between">
          <div className="max-w-3xl">
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-stone-500">
              Prizmo TCG engine
            </p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight text-stone-950 sm:text-4xl">
              Ash-backed playtest console
            </h1>
            <p className="mt-3 max-w-2xl text-sm leading-6 text-stone-600">
              Create a supported fixture game, reconnect by game ID, and play from a tab-scoped
              player seat backed by the persisted engine.
            </p>
          </div>

          <div className="min-w-56 rounded-2xl border border-stone-200 bg-stone-100 px-4 py-3 text-sm text-stone-700">
            <p className="font-medium text-stone-950">Current seat</p>
            <p className="mt-1 text-sm font-semibold text-stone-950">{formatPlayerId(session.viewerPlayerId)}</p>
            <p className="mt-1 font-mono text-xs text-stone-500">
              {normalisedGameId ? formatGameId(normalisedGameId) : 'No game selected'}
            </p>
          </div>
        </header>

        <section className="grid gap-5 lg:grid-cols-[minmax(18rem,24rem)_1fr]">
          <aside className="flex flex-col gap-5">
            <Panel title="Create or reconnect">
              <div className="space-y-4">
                <SessionConnectionSummary
                  gameId={normalisedGameId}
                  hasViewerMismatch={gameStateHasViewerMismatch}
                  isRefreshing={gameStateQuery.isFetching}
                  viewerPlayerId={session.viewerPlayerId}
                />

                {decksQuery.isPending ? <SkeletonLines count={3} /> : null}

                {decksQuery.error ? (
                  <InlineNotice tone="error" title="Deck fixtures did not load">
                    {errorMessage(decksQuery.error)} Refresh before creating a table so both fixture
                    selectors use the engine-owned deck catalog.
                  </InlineNotice>
                ) : null}

                {!decksQuery.isPending && decks.length === 0 ? (
                  <InlineNotice tone="info" title="No supported decks exposed yet">
                    The engine RPC returned an empty fixture list.
                  </InlineNotice>
                ) : null}

                <DeckSelect
                  label="Player 1 loadout"
                  playerId={PLAYER_ONE_ID}
                  value={selectedPlayerOneDeckKey}
                  decks={decks}
                  onChange={setPlayerOneDeckKey}
                />
                <DeckSelect
                  label="Player 2 loadout"
                  playerId={PLAYER_TWO_ID}
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
                  {createGameMutation.isPending ? 'Creating table...' : 'Create game board'}
                </button>

                <FirstRunSetupGuide
                  deckCount={decks.length}
                  hasGame={Boolean(normalisedGameId)}
                  selectedPlayerOneDeck={selectedPlayerOneDeck}
                  selectedPlayerTwoDeck={selectedPlayerTwoDeck}
                  viewerPlayerId={session.viewerPlayerId}
                />

                {createGameMutation.error ? (
                  <InlineNotice tone="error" title="Game creation failed">
                    {errorMessage(createGameMutation.error)} No table was created. Confirm both fixture
                    decks are still available, then try again.
                  </InlineNotice>
                ) : null}

                <label className="block space-y-2">
                  <span className="text-sm font-medium text-stone-800">Game ID</span>
                  <span className="block text-xs leading-5 text-stone-500">
                    Paste a persisted game UUID. This tab will request {formatPlayerId(session.viewerPlayerId)}'s
                    private view after the ID changes.
                  </span>
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
                    onClick={() => void gameStateQuery.refetch()}
                    type="button"
                  >
                    {gameStateQuery.isFetching ? 'Refreshing board...' : 'Refresh board'}
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

              </div>
            </Panel>

            <Panel
              title="Fixture catalog"
              trailing={<StatusBadge tone={decks.length > 0 ? 'active' : 'neutral'}>{decks.length} decks</StatusBadge>}
            >
              <SupportedDeckCatalog
                decks={decks}
                playerOneDeckKey={selectedPlayerOneDeckKey}
                playerTwoDeckKey={selectedPlayerTwoDeckKey}
              />
            </Panel>
          </aside>

          <section className="min-w-0">
            {!normalisedGameId ? (
              <EmptyWorkbench />
            ) : gameStateQuery.isPending ? (
              <GameStateLoadingPanel gameId={normalisedGameId} viewerPlayerId={session.viewerPlayerId} />
            ) : gameStateQuery.error ? (
              <GameStateErrorPanel
                error={gameStateQuery.error}
                gameId={normalisedGameId}
                isRetrying={gameStateQuery.isFetching}
                viewerPlayerId={session.viewerPlayerId}
                onClear={clearGame}
                onRetry={() => void gameStateQuery.refetch()}
              />
            ) : gameStateHasViewerMismatch ? (
              <StaleViewerPanel
                actualViewerPlayerId={queriedGameState?.viewerPlayerId ?? 'unknown'}
                expectedViewerPlayerId={session.viewerPlayerId}
                isRefreshing={gameStateQuery.isFetching}
                onRefresh={() => void gameStateQuery.refetch()}
              />
            ) : gameState ? (
              <GameStateWorkbench
                actionCommandError={actionCommandError}
                attackCommandError={attackCommandError}
                deckNamesByKey={deckNamesByKey}
                flowCommandError={flowCommandError}
                gameState={gameState}
                promptCommandError={promptCommandError}
                ultraBallPostSearchHandoff={ultraBallPostSearchHandoff}
                viewerPlayerId={session.viewerPlayerId}
                onStartSetup={() => startSetupMutation.mutate(normalisedGameId)}
                onDrawOpeningHand={() => drawOpeningHandMutation.mutate(normalisedGameId)}
                onChooseSetupActive={({ playerId, cardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    chooseActiveMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      cardInstanceId
                    })
                  }
                }}
                onChooseSetupBench={({ playerId, cardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    chooseSetupBenchMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      cardInstanceId
                    })
                  }
                }}
                onPlacePrizes={() => placePrizesMutation.mutate(normalisedGameId)}
                onCompleteSetup={() => completeSetupMutation.mutate(normalisedGameId)}
                onStartNextTurn={() => startNextTurnMutation.mutate(normalisedGameId)}
                onDrawForTurn={({ playerId }) => {
                  if (isPlayerId(playerId)) {
                    drawForTurnMutation.mutate({ gameId: normalisedGameId, playerId })
                  }
                }}
                onSkipDrawForTurn={({ playerId }) => {
                  if (isPlayerId(playerId)) {
                    skipDrawForTurnMutation.mutate({ gameId: normalisedGameId, playerId })
                  }
                }}
                onOpenActionWindow={() => openActionWindowMutation.mutate(normalisedGameId)}
                onChooseReplacementActive={({ playerId, benchCardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    chooseReplacementActiveMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      benchCardInstanceId
                    })
                  }
                }}
                onChoosePrompt={({ playerId, promptId, selectedCardInstanceIds, choiceKey }) => {
                  if (isPlayerId(playerId)) {
                    choosePromptMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      promptId,
                      selectedCardInstanceIds,
                      choiceKey
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
                  benchDamageTargetCardInstanceId,
                  benchDamageCounterAllocations,
                  coinResult,
                  headsCount,
                  copiedAttackId
                }) => {
                  if (isPlayerId(playerId)) {
                    resolveDeclaredAttackMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      switchBenchCardInstanceId,
                      discardedEnergyCardInstanceIds,
                      returnedEnergyCardInstanceId,
                      shuffledEnergyCardInstanceIds,
                      benchDamageTargetCardInstanceId,
                      benchDamageCounterAllocations,
                      coinResult,
                      headsCount,
                      copiedAttackId
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
                chooseSetupActivePendingCardId={
                  chooseActiveMutation.isPending ? chooseActiveMutation.variables?.cardInstanceId ?? null : null
                }
                chooseSetupBenchPendingCardId={
                  chooseSetupBenchMutation.isPending ? chooseSetupBenchMutation.variables?.cardInstanceId ?? null : null
                }
                chooseReplacementActivePendingCardId={
                  chooseReplacementActiveMutation.isPending
                    ? chooseReplacementActiveMutation.variables?.benchCardInstanceId ?? null
                    : null
                }
                completeSetupPending={completeSetupMutation.isPending}
                drawForTurnPending={drawForTurnMutation.isPending}
                drawOpeningHandPending={drawOpeningHandMutation.isPending}
                promptPendingId={choosePromptMutation.isPending ? choosePromptMutation.variables?.promptId ?? null : null}
                endTurnPendingPlayerId={endTurnMutation.isPending ? endTurnMutation.variables?.playerId ?? null : null}
                openActionWindowPending={openActionWindowMutation.isPending}
                placePrizesPending={placePrizesMutation.isPending}
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
                skipDrawForTurnPending={skipDrawForTurnMutation.isPending}
                startNextTurnPending={startNextTurnMutation.isPending}
                startSetupPending={startSetupMutation.isPending}
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

async function choosePrompt({ gameId, playerId, promptId, selectedCardInstanceIds }: ChoosePromptInput): Promise<CreatedGame> {
  const result = await runChooseTcgEnginePrompt({
    input: { gameId, playerId, promptId, selectedCardInstanceIds },
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

function GameStateWorkbench({
  actionCommandError,
  attackCommandError,
  flowCommandError,
  gameState,
  viewerPlayerId,
  deckNamesByKey,
  promptCommandError,
  ultraBallPostSearchHandoff,
  onChooseSetupActive,
  onChooseSetupBench,
  onChoosePrompt,
  onChooseReplacementActive,
  onAttachEnergy,
  onDeclareAttack,
  onCompleteSetup,
  onDrawForTurn,
  onDrawOpeningHand,
  onEndTurn,
  onEvolveFromHand,
  onOpenActionWindow,
  onPlacePrizes,
  onFinishAttack,
  onPlayBasicToBench,
  onPlayCard,
  onRetreat,
  onResolveDeclaredAttack,
  onSkipDrawForTurn,
  onStartNextTurn,
  onStartSetup,
  attachEnergyPendingKey,
  chooseSetupActivePendingCardId,
  chooseSetupBenchPendingCardId,
  chooseReplacementActivePendingCardId,
  completeSetupPending,
  declareAttackPendingKey,
  drawForTurnPending,
  drawOpeningHandPending,
  endTurnPendingPlayerId,
  evolveFromHandPendingKey,
  finishAttackPendingPlayerId,
  openActionWindowPending,
  placePrizesPending,
  playBasicToBenchPendingCardId,
  promptPendingId,
  playCardPendingCardId,
  resolveDeclaredAttackPendingPlayerId,
  retreatPendingKey,
  skipDrawForTurnPending,
  startNextTurnPending,
  startSetupPending
}: {
  actionCommandError: CommandErrorNotice | null
  attackCommandError: CommandErrorNotice | null
  flowCommandError: CommandErrorNotice | null
  gameState: GameState
  viewerPlayerId: PlayerId
  deckNamesByKey: Map<string, string>
  promptCommandError: CommandErrorNotice | null
  ultraBallPostSearchHandoff: UltraBallPostSearchHandoff | null
  onChooseSetupActive: (input: SetupCardCommand) => void
  onChooseSetupBench: (input: SetupCardCommand) => void
  onChoosePrompt: (input: ChoosePromptCommand) => void
  onChooseReplacementActive: (input: ChooseReplacementActiveCommand) => void
  onAttachEnergy: (input: AttachEnergyCommand) => void
  onDeclareAttack: (input: DeclareAttackCommand) => void
  onCompleteSetup: () => void
  onDrawForTurn: (input: TurnPlayerCommand) => void
  onDrawOpeningHand: () => void
  onEndTurn: (input: EndTurnCommand) => void
  onEvolveFromHand: (input: EvolveFromHandCommand) => void
  onOpenActionWindow: () => void
  onPlacePrizes: () => void
  onFinishAttack: (input: FinishAttackCommand) => void
  onPlayBasicToBench: (input: PlayBasicToBenchCommand) => void
  onPlayCard: (input: PlayCardCommand) => void
  onRetreat: (input: RetreatCommand) => void
  onResolveDeclaredAttack: (input: ResolveDeclaredAttackCommand) => void
  onSkipDrawForTurn: (input: TurnPlayerCommand) => void
  onStartNextTurn: () => void
  onStartSetup: () => void
  attachEnergyPendingKey: string | null
  chooseSetupActivePendingCardId: string | null
  chooseSetupBenchPendingCardId: string | null
  chooseReplacementActivePendingCardId: string | null
  completeSetupPending: boolean
  declareAttackPendingKey: string | null
  drawForTurnPending: boolean
  drawOpeningHandPending: boolean
  endTurnPendingPlayerId: string | null
  evolveFromHandPendingKey: string | null
  finishAttackPendingPlayerId: string | null
  openActionWindowPending: boolean
  placePrizesPending: boolean
  playBasicToBenchPendingCardId: string | null
  promptPendingId: string | null
  playCardPendingCardId: string | null
  resolveDeclaredAttackPendingPlayerId: string | null
  retreatPendingKey: string | null
  skipDrawForTurnPending: boolean
  startNextTurnPending: boolean
  startSetupPending: boolean
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

      <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(19rem,24rem)]">
        <BattlefieldPanel
          activePlayerId={gameState.activePlayerId}
          currentTurn={gameState.currentTurn}
          deckNamesByKey={deckNamesByKey}
          players={gameState.players}
          stadium={gameState.stadium}
          viewerPlayerId={viewerPlayerId}
        />

        <aside className="space-y-5 xl:sticky xl:top-6" aria-label="Player command rail">
          <GameFlowPanel
            commandError={flowCommandError}
            completeSetupPending={completeSetupPending}
            chooseSetupActivePendingCardId={chooseSetupActivePendingCardId}
            chooseSetupBenchPendingCardId={chooseSetupBenchPendingCardId}
            drawForTurnPending={drawForTurnPending}
            drawOpeningHandPending={drawOpeningHandPending}
            gameState={gameState}
            onChooseSetupActive={onChooseSetupActive}
            onChooseSetupBench={onChooseSetupBench}
            onCompleteSetup={onCompleteSetup}
            onDrawForTurn={onDrawForTurn}
            onDrawOpeningHand={onDrawOpeningHand}
            onOpenActionWindow={onOpenActionWindow}
            onPlacePrizes={onPlacePrizes}
            onSkipDrawForTurn={onSkipDrawForTurn}
            onStartNextTurn={onStartNextTurn}
            onStartSetup={onStartSetup}
            openActionWindowPending={openActionWindowPending}
            placePrizesPending={placePrizesPending}
            skipDrawForTurnPending={skipDrawForTurnPending}
            startNextTurnPending={startNextTurnPending}
            startSetupPending={startSetupPending}
            viewerPlayerId={viewerPlayerId}
          />

          <ViewerPromptsPanel
            cardsById={cardsById}
            commandError={promptCommandError}
            onChoosePrompt={onChoosePrompt}
            promptPendingId={promptPendingId}
            prompts={gameState.prompts}
          />

          <AttackProgressPanel
            cardsById={cardsById}
            commandError={attackCommandError}
            finishAttackPendingPlayerId={finishAttackPendingPlayerId}
            gameState={gameState}
            onFinishAttack={onFinishAttack}
            onResolveDeclaredAttack={onResolveDeclaredAttack}
            resolveDeclaredAttackPendingPlayerId={resolveDeclaredAttackPendingPlayerId}
            viewerPlayerId={viewerPlayerId}
          />

          <ActionAffordancesPanel
            actions={gameState.actionAffordances}
            cardsById={cardsById}
            commandError={actionCommandError}
            chooseReplacementActivePendingCardId={chooseReplacementActivePendingCardId}
            gameState={gameState}
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
            ultraBallPostSearchHandoff={ultraBallPostSearchHandoff}
            viewerPlayerId={viewerPlayerId}
          />
        </aside>
      </div>

      <div className="grid gap-5">
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

      </div>
    </div>
  )
}

function GameFlowPanel({
  commandError,
  completeSetupPending,
  chooseSetupActivePendingCardId,
  chooseSetupBenchPendingCardId,
  drawForTurnPending,
  drawOpeningHandPending,
  gameState,
  onChooseSetupActive,
  onChooseSetupBench,
  onCompleteSetup,
  onDrawForTurn,
  onDrawOpeningHand,
  onOpenActionWindow,
  onPlacePrizes,
  onSkipDrawForTurn,
  onStartNextTurn,
  onStartSetup,
  openActionWindowPending,
  placePrizesPending,
  skipDrawForTurnPending,
  startNextTurnPending,
  startSetupPending,
  viewerPlayerId
}: {
  commandError: CommandErrorNotice | null
  completeSetupPending: boolean
  chooseSetupActivePendingCardId: string | null
  chooseSetupBenchPendingCardId: string | null
  drawForTurnPending: boolean
  drawOpeningHandPending: boolean
  gameState: GameState
  onChooseSetupActive: (input: SetupCardCommand) => void
  onChooseSetupBench: (input: SetupCardCommand) => void
  onCompleteSetup: () => void
  onDrawForTurn: (input: TurnPlayerCommand) => void
  onDrawOpeningHand: () => void
  onOpenActionWindow: () => void
  onPlacePrizes: () => void
  onSkipDrawForTurn: (input: TurnPlayerCommand) => void
  onStartNextTurn: () => void
  onStartSetup: () => void
  openActionWindowPending: boolean
  placePrizesPending: boolean
  skipDrawForTurnPending: boolean
  startNextTurnPending: boolean
  startSetupPending: boolean
  viewerPlayerId: PlayerId
}) {
  const viewerPlayer = gameState.players.find(player => player.playerId === viewerPlayerId)
  const currentTurnActivePlayerId = gameState.currentTurn?.activePlayerId
  const currentTurnActivePlayerIsViewer = currentTurnActivePlayerId === viewerPlayerId
  const currentTurnActivePlayerLabel = currentTurnActivePlayerId
    ? formatPlayerId(currentTurnActivePlayerId)
    : 'the turn owner'
  const setupActiveCandidates = viewerPlayer?.hand.filter(isSetupActiveCandidate) ?? []
  const setupBenchCandidates = viewerPlayer?.hand.filter(isSetupBenchCandidate) ?? []
  const allPlayersHaveSetupActive = gameState.players.every(player => player.active)
  const setupPrizesAreUnplaced = gameState.players.every(player => player.prizeCount === 0)
  const turnStepPending = drawForTurnPending || skipDrawForTurnPending || openActionWindowPending
  const setupStatus = gameState.setup?.status ?? 'not started'
  const setupCompleted = gameState.setup?.status === 'completed'
  const setupChoicesClosed = gameState.setup?.status === 'prizes_placed' || setupCompleted
  const turnStatus = gameState.currentTurn
    ? `turn ${gameState.currentTurn.turnNumber}: ${formatEventType(gameState.currentTurn.status)}`
    : 'no turn'
  const flowStatus = setupCompleted ? turnStatus : setupStatus
  const nextTurnOwnerId = gameState.currentTurn?.status === 'ended'
    ? (gameState.players.find(player => player.playerId !== gameState.currentTurn?.activePlayerId)?.playerId ?? gameState.activePlayerId)
    : null
  const nextTurnOwnerLabel = nextTurnOwnerId ? formatPlayerId(nextTurnOwnerId) : null
  const nextTurnOwnerTabLabel = nextTurnOwnerLabel ? `the ${nextTurnOwnerLabel} tab` : 'the next player tab'
  const tableSetupDetail = setupCompleted
    ? gameState.currentTurn?.status === 'ended'
      ? `Opening choices are locked. Use Turn step to start ${nextTurnOwnerLabel ?? 'the next player'}'s next turn, then resolve draw timing from ${nextTurnOwnerTabLabel}.`
      : gameState.currentTurn?.status === 'start'
        ? `Opening choices are locked. Turn ${gameState.currentTurn.turnNumber} belongs to ${currentTurnActivePlayerLabel}; resolve draw timing from the ${currentTurnActivePlayerLabel} tab before actions reopen.`
      : 'Opening choices are locked. Use Turn step for the live turn path.'
    : 'Build the opening board from the viewer hand, then move into the first turn.'
  const canStartSetup = !gameState.setup && !startSetupPending
  const canDrawOpeningHand = gameState.setup?.status === 'waiting_to_draw' && !drawOpeningHandPending
  const canChooseSetupActive = Boolean(
    gameState.setup?.status === 'hands_drawn' &&
      viewerPlayer &&
      !viewerPlayer.active &&
      setupActiveCandidates.length > 0 &&
      !chooseSetupActivePendingCardId
  )
  const canChooseSetupBench = Boolean(
    gameState.setup?.status === 'hands_drawn' &&
      viewerPlayer &&
      viewerPlayer.active &&
      viewerPlayer.bench.length < 5 &&
      setupBenchCandidates.length > 0 &&
      !chooseSetupBenchPendingCardId
  )
  const canPlacePrizes = Boolean(
    gameState.setup?.status === 'hands_drawn' &&
      allPlayersHaveSetupActive &&
      setupPrizesAreUnplaced &&
      !placePrizesPending
  )
  const canCompleteSetup = gameState.setup?.status === 'prizes_placed' && !completeSetupPending
  const canStartNextTurn = Boolean(
    gameState.status === 'in_progress' &&
      gameState.setup?.status === 'completed' &&
      (!gameState.currentTurn || gameState.currentTurn.status === 'ended') &&
      !startNextTurnPending
  )
  const canDrawForTurn = Boolean(
    gameState.status === 'in_progress' &&
      gameState.currentTurn?.status === 'start' &&
      currentTurnActivePlayerId &&
      isPlayerId(currentTurnActivePlayerId) &&
      currentTurnActivePlayerIsViewer &&
      !turnStepPending
  )
  const canSkipDrawForTurn = canDrawForTurn
  const canOpenActionWindow = Boolean(
    gameState.status === 'in_progress' &&
      gameState.currentTurn?.status === 'drawn' &&
      currentTurnActivePlayerIsViewer &&
      !turnStepPending
  )
  const openingActiveStatusMessage = viewerPlayer?.active
    ? `${viewerPlayer.active.name} is this viewer's setup Active.`
    : setupChoicesClosed
      ? 'Setup Active choices are locked after Prize placement.'
      : 'Draw opening hands, then view a player without an Active Pokémon to choose one.'
  const openingBenchUnavailableMessage = setupChoicesClosed
    ? 'Setup Bench choices are locked after Prize placement.'
    : 'Draw opening hands and choose this viewer\'s Active Pokémon before benching setup Pokémon.'
  const placePrizesButtonLabel = placePrizesPending
    ? 'Placing prizes...'
    : setupChoicesClosed
      ? 'Prizes placed'
      : gameState.setup?.status === 'hands_drawn'
        ? allPlayersHaveSetupActive
          ? 'Place setup prizes'
          : 'Choose both Active Pokémon first'
        : 'Choose Active Pokémon first'

  return (
    <Panel title="Game flow" trailing={<StatusBadge tone={gameState.setup ? 'active' : 'neutral'}>{flowStatus}</StatusBadge>}>
      <div className="space-y-4">
        {commandError ? <CommandErrorCard notice={commandError} /> : null}

        <section className={setupCompleted ? 'rounded-xl border border-emerald-100 bg-emerald-50/70 p-3' : 'rounded-xl border border-stone-200 bg-white p-3'}>
          <div className="flex items-start justify-between gap-3">
            <div>
              <h3 className="text-sm font-semibold text-stone-950">Table setup</h3>
              <p className="mt-1 text-xs leading-5 text-stone-500">
                {tableSetupDetail}
              </p>
            </div>
            <StatusBadge tone={gameState.setup?.status === 'completed' ? 'active' : 'warning'}>
              {formatEventType(setupStatus)}
            </StatusBadge>
          </div>

          {setupCompleted ? (
            <CompletedSetupSummary
              currentTurn={gameState.currentTurn}
              firstPlayerId={gameState.firstPlayerId}
              players={gameState.players}
            />
          ) : (
            <>
              <SetupPathGuide gameState={gameState} viewerPlayerId={viewerPlayerId} />

              <div className="mt-3 space-y-2">
                <ActionCommandButton disabled={!canStartSetup} onClick={onStartSetup} tone={gameState.setup ? 'secondary' : 'primary'}>
                  {startSetupPending ? 'Starting setup...' : gameState.setup ? 'Setup already started' : 'Start setup'}
                </ActionCommandButton>

                <ActionCommandButton disabled={!canDrawOpeningHand} onClick={onDrawOpeningHand} tone="primary">
                  {drawOpeningHandPending
                    ? 'Drawing opening hands...'
                    : gameState.setup?.status === 'waiting_to_draw'
                      ? 'Draw opening hands'
                      : gameState.setup
                        ? 'Opening hands resolved'
                        : 'Start setup first'}
                </ActionCommandButton>
              </div>

              <div className="mt-3 rounded-xl border border-stone-200 bg-stone-50 p-3">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h4 className="text-xs font-semibold uppercase tracking-[0.14em] text-stone-500">Opening Active</h4>
                    <p className="mt-1 text-xs leading-5 text-stone-500">
                      Choose {formatPlayerId(viewerPlayerId)}'s first Basic Pokémon.
                    </p>
                  </div>
                  <StatusBadge tone={viewerPlayer?.active ? 'active' : 'neutral'}>
                    {viewerPlayer?.active ? 'chosen' : 'pending'}
                  </StatusBadge>
                </div>

                {gameState.setup?.status === 'hands_drawn' && viewerPlayer && !viewerPlayer.active ? (
                  setupActiveCandidates.length > 0 ? (
                    <div className="mt-3 space-y-1.5">
                      {setupActiveCandidates.map(card => {
                        const isPending = chooseSetupActivePendingCardId === card.id

                        return (
                          <ActionCommandButton
                            disabled={!canChooseSetupActive}
                            key={card.id}
                            onClick={() => onChooseSetupActive({ playerId: viewerPlayerId, cardInstanceId: card.id })}
                            tone="primary"
                          >
                            {isPending ? `Choosing ${card.name}...` : `Choose ${card.name}`}
                          </ActionCommandButton>
                        )
                      })}
                    </div>
                  ) : (
                    <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                      No Basic Pokémon are visible in this viewer's hand.
                    </p>
                  )
                ) : (
                  <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                    {openingActiveStatusMessage}
                  </p>
                )}
              </div>

              <div className="mt-3 rounded-xl border border-stone-200 bg-stone-50 p-3">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h4 className="text-xs font-semibold uppercase tracking-[0.14em] text-stone-500">Opening Bench</h4>
                    <p className="mt-1 text-xs leading-5 text-stone-500">
                      Add optional Basic Pokémon before Prizes are placed.
                    </p>
                  </div>
                  <StatusBadge tone={viewerPlayer?.bench.length ? 'active' : 'neutral'}>
                    {viewerPlayer?.bench.length ?? 0}/5
                  </StatusBadge>
                </div>

                {gameState.setup?.status === 'hands_drawn' && viewerPlayer && viewerPlayer.active ? (
                  viewerPlayer.bench.length >= 5 ? (
                    <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                      This viewer's Bench is full.
                    </p>
                  ) : setupBenchCandidates.length > 0 ? (
                    <div className="mt-3 space-y-1.5">
                      {setupBenchCandidates.map(card => {
                        const isPending = chooseSetupBenchPendingCardId === card.id

                        return (
                          <ActionCommandButton
                            disabled={!canChooseSetupBench}
                            key={card.id}
                            onClick={() => onChooseSetupBench({ playerId: viewerPlayerId, cardInstanceId: card.id })}
                          >
                            {isPending ? `Benching ${card.name}...` : `Bench ${card.name}`}
                          </ActionCommandButton>
                        )
                      })}
                    </div>
                  ) : (
                    <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                      No additional Basic Pokémon are visible in this viewer's hand.
                    </p>
                  )
                ) : (
                  <p className="mt-3 rounded-lg border border-dashed border-stone-300 px-3 py-3 text-sm text-stone-500">
                    {openingBenchUnavailableMessage}
                  </p>
                )}
              </div>

              <div className="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-1">
                <ActionCommandButton disabled={!canPlacePrizes} onClick={onPlacePrizes} tone="primary">
                  {placePrizesButtonLabel}
                </ActionCommandButton>

                <ActionCommandButton disabled={!canCompleteSetup} onClick={onCompleteSetup} tone="primary">
                  {completeSetupPending
                    ? 'Completing setup...'
                    : gameState.setup?.status === 'prizes_placed'
                      ? 'Complete setup'
                      : gameState.setup?.status === 'completed'
                        ? 'Setup completed'
                        : 'Place prizes first'}
                </ActionCommandButton>
              </div>
            </>
          )}
        </section>

        <section className="rounded-xl border border-stone-200 bg-white p-3">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h3 className="text-sm font-semibold text-stone-950">Turn step</h3>
              <p className="mt-1 text-xs leading-5 text-stone-500">
                Start the turn, resolve draw-step timing, then open the action window.
              </p>
            </div>
            <StatusBadge tone={gameState.currentTurn ? 'active' : 'neutral'}>{turnStatus}</StatusBadge>
          </div>

          {setupCompleted ? <TurnStepGuide gameState={gameState} viewerPlayerId={viewerPlayerId} /> : null}

          <div className="mt-3 space-y-2">
            <ActionCommandButton disabled={!canStartNextTurn} onClick={onStartNextTurn} tone="primary">
              {startNextTurnPending
                ? 'Starting turn...'
                : gameState.currentTurn?.status === 'ended'
                  ? nextTurnOwnerLabel
                    ? `Start ${nextTurnOwnerLabel}'s turn`
                    : 'Start next turn'
                  : gameState.currentTurn
                    ? `Turn ${gameState.currentTurn.turnNumber} in progress`
                    : gameState.setup?.status === 'completed'
                      ? 'Start first turn'
                      : 'Complete setup first'}
            </ActionCommandButton>

            <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-1">
              <ActionCommandButton
                disabled={!canDrawForTurn}
                onClick={() => {
                  if (currentTurnActivePlayerId && isPlayerId(currentTurnActivePlayerId)) {
                    onDrawForTurn({ playerId: currentTurnActivePlayerId })
                  }
                }}
              >
                {drawForTurnPending
                  ? 'Drawing for turn...'
                  : gameState.currentTurn?.status === 'start'
                    ? currentTurnActivePlayerIsViewer
                      ? `Draw for ${formatPlayerId(gameState.currentTurn.activePlayerId)}`
                      : `Use ${currentTurnActivePlayerLabel} tab to draw`
                    : gameState.currentTurn?.status === 'drawn'
                      ? 'Draw for turn resolved'
                      : gameState.currentTurn
                        ? 'Turn is not in draw step'
                        : 'Start first turn first'}
              </ActionCommandButton>

              <ActionCommandButton
                disabled={!canSkipDrawForTurn}
                onClick={() => {
                  if (currentTurnActivePlayerId && isPlayerId(currentTurnActivePlayerId)) {
                    onSkipDrawForTurn({ playerId: currentTurnActivePlayerId })
                  }
                }}
              >
                {skipDrawForTurnPending
                  ? 'Skipping draw...'
                  : gameState.currentTurn?.status === 'start'
                    ? currentTurnActivePlayerIsViewer
                      ? `Skip draw for ${formatPlayerId(gameState.currentTurn.activePlayerId)}`
                      : `Use ${currentTurnActivePlayerLabel} tab to skip`
                    : gameState.currentTurn?.status === 'action_window'
                      ? 'Draw step skipped'
                      : gameState.currentTurn
                        ? 'Turn is not in draw step'
                        : 'Start first turn first'}
              </ActionCommandButton>
            </div>

            <ActionCommandButton disabled={!canOpenActionWindow} onClick={onOpenActionWindow} tone="primary">
              {openActionWindowPending
                ? 'Opening action window...'
                : gameState.currentTurn?.status === 'drawn'
                  ? currentTurnActivePlayerIsViewer
                    ? 'Open action window'
                    : `Use ${currentTurnActivePlayerLabel} tab to open actions`
                  : gameState.currentTurn?.status === 'action_window'
                    ? 'Action window open'
                    : gameState.currentTurn?.status === 'start' && !currentTurnActivePlayerIsViewer
                      ? `Use ${currentTurnActivePlayerLabel} tab for draw first`
                    : gameState.currentTurn
                      ? 'Draw or skip draw first'
                      : 'Start first turn first'}
            </ActionCommandButton>
          </div>
        </section>
      </div>
    </Panel>
  )
}

function TurnStepGuide({
  gameState,
  viewerPlayerId
}: {
  gameState: GameState
  viewerPlayerId: PlayerId
}) {
  const currentTurn = gameState.currentTurn
  const endedTurn = currentTurn?.status === 'ended'
  const nextTurnOwnerId = endedTurn
    ? (gameState.players.find(player => player.playerId !== currentTurn.activePlayerId)?.playerId ?? gameState.activePlayerId)
    : null
  const turnOwnerId = nextTurnOwnerId ?? currentTurn?.activePlayerId ?? gameState.firstPlayerId
  const turnOwnerLabel = formatPlayerId(turnOwnerId)
  const viewerLabel = formatPlayerId(viewerPlayerId)
  const viewerOwnsTurn = turnOwnerId === viewerPlayerId
  const activeWindowOpen = currentTurn?.status === 'action_window'
  const drawStepResolved = currentTurn ? ['drawn', 'action_window', 'attack_declared', 'attack_resolving'].includes(currentTurn.status) : false
  const guideTitle = endedTurn ? 'Next-turn path' : currentTurn ? 'Turn path' : 'First-turn path'
  const startStepTitle = endedTurn ? 'Start the next turn' : currentTurn ? 'Turn started' : 'Start the first turn'
  const startStepState = !currentTurn || endedTurn ? 'next' : 'done'
  const drawStepState = !currentTurn || endedTurn
    ? 'needed'
    : drawStepResolved
      ? 'done'
      : currentTurn.status === 'start'
        ? 'next'
        : 'needed'
  const actionWindowState = activeWindowOpen
    ? 'done'
    : currentTurn?.status === 'drawn'
      ? 'next'
      : 'needed'

  const startDetail = endedTurn
    ? `Turn ${currentTurn.turnNumber} is closed. Start turn ${currentTurn.turnNumber + 1} for ${turnOwnerLabel}. This tab is ${viewerLabel}.`
    : currentTurn
      ? `Turn ${currentTurn.turnNumber} belongs to ${turnOwnerLabel}. This tab is ${viewerLabel}.`
      : `Start turn one for ${turnOwnerLabel}. This tab is ${viewerLabel}.`
  let drawDetail = 'After the turn starts, draw for turn or skip the draw when a fixture scenario calls for it.'

  if (endedTurn) {
    drawDetail = viewerOwnsTurn
      ? `Start ${turnOwnerLabel}'s next turn, then resolve draw timing from this tab.`
      : `Start ${turnOwnerLabel}'s next turn, then use the ${turnOwnerLabel} tab for draw timing.`
  } else if (currentTurn?.status === 'start') {
    drawDetail = viewerOwnsTurn
      ? `Use this ${turnOwnerLabel} tab to draw a card, or skip only when the fixture scenario calls for it.`
      : `Draw timing belongs to ${turnOwnerLabel}. Use the ${turnOwnerLabel} tab, then refresh here.`
  } else if (drawStepResolved) {
    drawDetail = `Draw-step timing is resolved for ${turnOwnerLabel}.`
  } else if (currentTurn) {
    drawDetail = 'Finish the current attack or prompt flow before the next draw step.'
  }

  let actionWindowDetail = 'The action window opens after draw timing resolves.'

  if (endedTurn) {
    actionWindowDetail = viewerOwnsTurn
      ? `After ${turnOwnerLabel}'s draw timing, open the action window from this tab for hand, board, battle, and end-turn choices.`
      : `After ${turnOwnerLabel}'s draw timing, use the ${turnOwnerLabel} tab to open the action window, then refresh here.`
  } else if (currentTurn?.status === 'start') {
    actionWindowDetail = viewerOwnsTurn
      ? `Draw or skip from this ${turnOwnerLabel} tab before opening actions.`
      : `Use the ${turnOwnerLabel} tab to finish draw timing before opening actions, then refresh here.`
  } else if (currentTurn?.status === 'drawn') {
    actionWindowDetail = viewerOwnsTurn
      ? `Use this ${turnOwnerLabel} tab to open the action window so hand, board, retreat, attack, and end-turn actions can appear below.`
      : `Draw timing is resolved for ${turnOwnerLabel}. Use the ${turnOwnerLabel} tab to open the action window, then refresh here.`
  } else if (activeWindowOpen) {
    actionWindowDetail = `Action decisions are live for ${turnOwnerLabel}. Use Available actions below.`
  } else if (currentTurn) {
    actionWindowDetail = 'Resolve the current battle or prompt step before opening new actions.'
  }

  return (
    <div className="mt-3 rounded-xl border border-amber-100 bg-[oklch(0.985_0.018_90)] p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h4 className="text-xs font-semibold uppercase tracking-[0.14em] text-amber-800">{guideTitle}</h4>
          <p className="mt-1 text-xs leading-5 text-stone-600">
            Use this timing lane after setup locks. Legal actions stay hidden until the action window opens.
          </p>
        </div>
        <StatusBadge tone={activeWindowOpen ? 'active' : 'warning'}>
          {activeWindowOpen ? 'actions live' : currentTurn ? formatEventType(currentTurn.status) : 'next'}
        </StatusBadge>
      </div>

      <div className="mt-3 space-y-2">
        <SetupGuideRow
          detail={startDetail}
          number="1"
          state={startStepState}
          title={startStepTitle}
        />
        <SetupGuideRow
          detail={drawDetail}
          number="2"
          state={drawStepState}
          title="Resolve draw timing"
        />
        <SetupGuideRow
          detail={actionWindowDetail}
          number="3"
          state={actionWindowState}
          title="Open the action window"
        />
      </div>
    </div>
  )
}

function SetupPathGuide({
  gameState,
  viewerPlayerId
}: {
  gameState: GameState
  viewerPlayerId: PlayerId
}) {
  const setupStatus = gameState.setup?.status ?? 'not_started'
  const setupStarted = Boolean(gameState.setup)
  const openingHandsDrawn = ['hands_drawn', 'prizes_placed', 'completed'].includes(setupStatus)
  const setupLocked = setupStatus === 'prizes_placed' || setupStatus === 'completed'
  const viewerPlayer = gameState.players.find(player => player.playerId === viewerPlayerId)
  const playersMissingActive = gameState.players.filter(player => !player.active)
  const allPlayersHaveSetupActive = playersMissingActive.length === 0
  const activeSummary = gameState.players
    .map(player => `${formatPlayerId(player.playerId)}: ${player.active?.name ?? 'needs Active'}`)
    .join(', ')
  const missingActiveSummary = playersMissingActive.map(player => formatPlayerId(player.playerId)).join(', ')
  const benchCountSummary = gameState.players
    .map(player => `${formatPlayerId(player.playerId)} ${player.bench.length}/5`)
    .join(', ')

  const activeDetail = allPlayersHaveSetupActive
    ? activeSummary
    : openingHandsDrawn
      ? viewerPlayer?.active
        ? `${viewerPlayer.active.name} is ready here. ${missingActiveSummary} still needs an Active.`
        : `${formatPlayerId(viewerPlayerId)} chooses a visible Basic Pokémon from this hand.`
      : 'Opening hands must be drawn before either player can choose an Active Pokémon.'

  const benchDetail = setupLocked
    ? `Opening Bench choices are locked: ${benchCountSummary}.`
    : openingHandsDrawn && allPlayersHaveSetupActive
      ? `Optional before Prizes: ${formatPlayerId(viewerPlayerId)} can Bench visible Basics or move on.`
      : 'Bench choices open after both players have an Active Pokémon.'

  const lockDetail =
    setupStatus === 'prizes_placed'
      ? 'Prizes are down. Complete setup, then start the first turn.'
      : openingHandsDrawn && allPlayersHaveSetupActive
        ? 'When both seats are ready, place face-down Prizes and lock setup.'
        : 'Finish opening Active choices before Prizes can be placed.'

  return (
    <div className="mt-3 rounded-xl border border-emerald-100 bg-[oklch(0.985_0.012_155)] p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h4 className="text-xs font-semibold uppercase tracking-[0.14em] text-emerald-800">Setup path</h4>
          <p className="mt-1 text-xs leading-5 text-stone-600">
            Follow these table steps after creating a board. This tab is {formatPlayerId(viewerPlayerId)}.
          </p>
        </div>
        <StatusBadge tone={setupStarted ? 'warning' : 'neutral'}>
          {setupStarted ? formatEventType(setupStatus) : 'next'}
        </StatusBadge>
      </div>

      <div className="mt-3 space-y-2">
        <SetupGuideRow
          detail={setupStarted ? 'The persisted setup record is ready.' : 'Start setup to prepare the opening table.'}
          number="1"
          state={setupStarted ? 'done' : 'next'}
          title="Start setup"
        />
        <SetupGuideRow
          detail={openingHandsDrawn ? 'Both players have opening hands.' : 'Draw hidden opening hands for both players.'}
          number="2"
          state={!setupStarted ? 'needed' : openingHandsDrawn ? 'done' : 'next'}
          title="Draw opening hands"
        />
        <SetupGuideRow
          detail={activeDetail}
          number="3"
          state={!openingHandsDrawn ? 'needed' : allPlayersHaveSetupActive ? 'done' : 'next'}
          title="Choose Active Pokémon"
        />
        <SetupGuideRow
          detail={benchDetail}
          number="4"
          state={!openingHandsDrawn || !allPlayersHaveSetupActive ? 'needed' : setupLocked ? 'done' : 'ready'}
          title="Optional Bench"
        />
        <SetupGuideRow
          detail={lockDetail}
          number="5"
          state={setupStatus === 'prizes_placed' ? 'next' : openingHandsDrawn && allPlayersHaveSetupActive ? 'ready' : 'needed'}
          title="Place Prizes, then complete"
        />
      </div>
    </div>
  )
}

function CompletedSetupSummary({
  currentTurn,
  firstPlayerId,
  players
}: {
  currentTurn: GameState['currentTurn']
  firstPlayerId: string
  players: PlayerView[]
}) {
  const turnOwnerLabel = formatPlayerId(currentTurn?.activePlayerId ?? firstPlayerId)
  const nextTurnOwnerId = currentTurn?.status === 'ended'
    ? (players.find(player => player.playerId !== currentTurn.activePlayerId)?.playerId ?? firstPlayerId)
    : null
  const nextTurnOwnerLabel = nextTurnOwnerId ? formatPlayerId(nextTurnOwnerId) : null
  const nextTurnOwnerTabLabel = nextTurnOwnerLabel ? `the ${nextTurnOwnerLabel} tab` : 'the turn owner tab'
  const setupDetail = currentTurn
    ? currentTurn.status === 'ended'
      ? `Opening choices are locked. Use Turn step to start ${nextTurnOwnerLabel ?? 'the next player'}'s next turn, resolve draw timing from ${nextTurnOwnerTabLabel}, and reopen legal actions.`
      : currentTurn.status === 'start'
        ? `Opening choices are locked. Turn ${currentTurn.turnNumber} belongs to ${turnOwnerLabel}; resolve draw timing from the ${turnOwnerLabel} tab before legal actions reopen.`
      : 'Opening choices are locked. Use Turn step to track this turn, draw timing, and live legal actions.'
    : 'Opening choices are locked. Use Turn step to start turn one, resolve draw timing, and open legal actions.'

  return (
    <div className="mt-3 space-y-3">
      <p className="text-xs leading-5 text-emerald-900">
        {setupDetail}
      </p>

      <dl className="grid gap-2">
        {players.map(player => (
          <div className="rounded-lg border border-emerald-100 bg-white/80 px-3 py-2" key={player.playerId}>
            <div className="flex items-center justify-between gap-3">
              <dt className="text-xs font-semibold uppercase tracking-[0.14em] text-stone-500">
                {formatPlayerId(player.playerId)}
              </dt>
              <dd className="text-xs font-medium text-emerald-800">
                {player.playerId === firstPlayerId ? 'First player' : 'Second player'}
              </dd>
            </div>

            <p className="mt-1 truncate text-sm font-semibold text-stone-950">
              {player.active?.name ?? 'No Active Pokémon'}
            </p>
            <p className="mt-1 text-xs leading-5 text-stone-500">
              {player.bench.length}/5 Bench · {actionCountLabel(player.prizeCount, 'Prize')} left ·{' '}
              {actionCountLabel(player.handCount, 'card')} in hand
            </p>
          </div>
        ))}
      </dl>
    </div>
  )
}

function ViewerPromptsPanel({
  cardsById,
  commandError,
  onChoosePrompt,
  promptPendingId,
  prompts
}: {
  cardsById: Map<string, CardSummary>
  commandError: CommandErrorNotice | null
  onChoosePrompt: (input: ChoosePromptCommand) => void
  promptPendingId: string | null
  prompts: GameState['prompts']
}) {
  if (prompts.length === 0 && !commandError) {
    return null
  }

  return (
    <Panel title="Viewer prompts">
      <div className="space-y-3">
        {commandError ? <CommandErrorCard notice={commandError} /> : null}

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
          <RailEmptyState title="No prompt is open for this viewer">
            The failed prompt command above did not leave a selectable prompt here. Refresh state, or switch viewers if
            the engine is waiting on the other player.
          </RailEmptyState>
        )}
      </div>
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
  const choiceKey = promptChoiceKey(prompt.payload)
  const promptFlowGuide = ultraBallPromptFlowGuide(choiceKey, min, max, legalChoiceIds.length)
  const promptGuidance = promptGuidanceMessages(prompt, min, max, legalChoiceIds.length)
  const promptChoiceRows = promptChoiceButtonRows(legalChoiceIds, legalChoiceCardsById, cardsById, legalChoiceLabelsById)
  const promptChoiceDisambiguation = promptChoiceDisambiguationMessage(promptChoiceRows)

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

      {promptFlowGuide ? (
        <PromptFlowGuideCard guide={promptFlowGuide} />
      ) : promptGuidance.length > 0 ? (
        <div className="mt-3 rounded-lg border border-emerald-200 bg-stone-50 px-3 py-2 text-xs leading-5 text-emerald-900">
          {promptGuidance.map(message => (
            <p key={message}>{message}</p>
          ))}
        </div>
      ) : null}

      {promptChoiceDisambiguation ? (
        <p className="mt-3 rounded-lg border border-emerald-200 bg-stone-50 px-3 py-2 text-xs leading-5 text-emerald-900">
          {promptChoiceDisambiguation}
        </p>
      ) : null}

      {legalChoiceIds.length > 0 ? (
        <div className="mt-3 space-y-2">
          {promptChoiceRows.map(({ cardInstanceId, detail, label }) => {
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
                <span className="block font-semibold">{label}</span>
                <span className="mt-0.5 block text-xs text-stone-500">{detail}</span>
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
                selectedCardInstanceIds,
                choiceKey
              })
            }
            type="button"
          >
            {promptSubmitLabel(choiceKey, selectedCardInstanceIds.length, max, isPending)}
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

function PromptFlowGuideCard({ guide }: { guide: PromptFlowGuide }) {
  return (
    <div className="mt-3 rounded-lg bg-[oklch(0.99_0.01_155)] px-3 py-2.5 text-xs leading-5 text-emerald-950">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-semibold uppercase tracking-[0.14em] text-emerald-800">{guide.eyebrow}</p>
          <p className="mt-1 font-medium text-stone-950">{guide.title}</p>
          <p className="mt-0.5 text-stone-600">{guide.detail}</p>
        </div>
      </div>

      <PromptFlowStepList steps={guide.steps} />
    </div>
  )
}

function PromptFlowStepList({ steps }: { steps: PromptFlowStep[] }) {
  return (
    <ol className="mt-3 grid gap-1.5">
      {steps.map(step => (
        <li
          className={`flex items-start gap-2 rounded-md px-2 py-1.5 ${promptFlowStepClassName(step.tone)}`}
          key={`${step.label}:${step.title}`}
        >
          <span className={`mt-0.5 rounded-full px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.12em] ${promptFlowStepBadgeClassName(step.tone)}`}>
            {step.label}
          </span>
          <span className="min-w-0">
            <span className="block font-medium text-stone-950">{step.title}</span>
            <span className="block text-stone-600">{step.detail}</span>
          </span>
        </li>
      ))}
    </ol>
  )
}

function AttackProgressPanel({
  cardsById,
  commandError,
  finishAttackPendingPlayerId,
  gameState,
  onFinishAttack,
  onResolveDeclaredAttack,
  resolveDeclaredAttackPendingPlayerId,
  viewerPlayerId
}: {
  cardsById: Map<string, CardSummary>
  commandError: CommandErrorNotice | null
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
  const [selectedBenchDamageCounterAllocations, setSelectedBenchDamageCounterAllocations] = useState<
    Record<string, number>
  >({})
  const [selectedCoinResult, setSelectedCoinResult] = useState<CoinResult | ''>('')
  const [selectedHeadsCount, setSelectedHeadsCount] = useState('')
  const [selectedCopiedAttackId, setSelectedCopiedAttackId] = useState('')
  const turn = gameState.currentTurn
  const activePlayer = turn ? gameState.players.find(player => player.playerId === turn.activePlayerId) : undefined
  const opponentPlayer = turn ? gameState.players.find(player => player.playerId !== turn.activePlayerId) : undefined
  const copiedAttackOptions = turn?.pendingAttackRequiresCopiedAttack ? turn.pendingAttackCopyChoices : []
  const selectedCopiedAttackChoice = copiedAttackOptions.find(choice => choice.attackId === selectedCopiedAttackId)
  const copiedAttackChoiceForResolve = selectedCopiedAttackChoice ?? (copiedAttackOptions.length === 1 ? copiedAttackOptions[0] : null)
  const copiedAttackIdForResolve = turn?.pendingAttackRequiresCopiedAttack
    ? (copiedAttackChoiceForResolve?.attackId ?? null)
    : null
  const resolutionEffectType = copiedAttackChoiceForResolve?.attackEffectType ?? turn?.pendingAttackEffectType ?? null
  const pendingAttackRequiresSwitchTarget = Boolean(
    turn?.pendingAttackRequiresSwitchTarget || resolutionEffectType === 'switch_self_with_bench'
  )
  const pendingAttackRequiresDiscardedEnergy = Boolean(
    turn?.pendingAttackRequiresDiscardedEnergy ||
      resolutionEffectType === DISCARD_OWN_BASIC_ENERGY_FOR_DAMAGE_EFFECT ||
      resolutionEffectType === DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT ||
      resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT
  )
  const pendingAttackRequiresReturnedEnergy = Boolean(
    turn?.pendingAttackRequiresReturnedEnergy || resolutionEffectType === 'return_attached_energy_to_hand'
  )
  const pendingAttackRequiresShuffledEnergy = Boolean(
    turn?.pendingAttackRequiresShuffledEnergy ||
      resolutionEffectType === SHUFFLE_ATTACHED_ENERGY_INTO_DECK_THEN_DAMAGE_OPPONENT_BENCH_EFFECT
  )
  const pendingAttackRequiresBenchDamageTarget = Boolean(
    turn?.pendingAttackRequiresBenchDamageTarget ||
      resolutionEffectType === SHUFFLE_ATTACHED_ENERGY_INTO_DECK_THEN_DAMAGE_OPPONENT_BENCH_EFFECT
  )
  const pendingAttackRequiresBenchDamageCounters = Boolean(
    turn?.pendingAttackRequiresBenchDamageCounters || resolutionEffectType === 'opponent_bench_damage_counters'
  )
  const pendingAttackRequiresCoinResult = Boolean(
    turn?.pendingAttackRequiresCoinResult ||
      resolutionEffectType === 'bonus_damage_on_coin_heads' ||
      resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT ||
      resolutionEffectType === 'prevent_damage_and_effects_from_attacks_next_turn_on_coin_heads'
  )
  const pendingAttackRequiresHeadsCount = Boolean(
    turn?.pendingAttackRequiresHeadsCount || resolutionEffectType === 'bonus_damage_per_coin_heads_count'
  )
  const switchTargetOptions = pendingAttackRequiresSwitchTarget ? (activePlayer?.bench ?? []) : []
  const selectedSwitchTargetIsValid = switchTargetOptions.some(card => card.id === selectedSwitchBenchCardInstanceId)
  const discardedEnergyOptions = useMemo(() => {
    if (!pendingAttackRequiresDiscardedEnergy || !activePlayer) {
      return []
    }

    const sourceCards =
      resolutionEffectType === DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT
        ? activePlayer.bench
        : resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT
          ? opponentPlayer?.active
            ? [opponentPlayer.active]
            : []
        : resolutionEffectType === DISCARD_OWN_BASIC_ENERGY_FOR_DAMAGE_EFFECT
          ? [activePlayer.active, ...activePlayer.bench]
          : []

    return sourceCards
      .filter((card): card is CardSummary => Boolean(card))
      .flatMap(card =>
        (card.attachedCards ?? [])
          .filter(isEnergyCard)
          .map(energyCard => ({ attachedTo: card, energyCard }))
      )
  }, [activePlayer, opponentPlayer?.active, pendingAttackRequiresDiscardedEnergy, resolutionEffectType])
  const discardedEnergyOptionIds = useMemo(
    () => new Set(discardedEnergyOptions.map(option => option.energyCard.id)),
    [discardedEnergyOptions]
  )
  const selectedDiscardedEnergyIdsForResolve = pendingAttackRequiresDiscardedEnergy
    ? selectedDiscardedEnergyCardInstanceIds.filter(id => discardedEnergyOptionIds.has(id))
    : []
  const returnedEnergyOptions = useMemo(() => {
    if (!pendingAttackRequiresReturnedEnergy || !activePlayer?.active) {
      return []
    }

    return (activePlayer.active.attachedCards ?? []).filter(isEnergyCard)
  }, [activePlayer?.active, pendingAttackRequiresReturnedEnergy])
  const returnedEnergyOptionIds = useMemo(
    () => new Set(returnedEnergyOptions.map(energyCard => energyCard.id)),
    [returnedEnergyOptions]
  )
  const selectedReturnedEnergyIsValid = returnedEnergyOptionIds.has(selectedReturnedEnergyCardInstanceId)
  const returnedEnergyIdForResolve = pendingAttackRequiresReturnedEnergy
    ? selectedReturnedEnergyIsValid
      ? selectedReturnedEnergyCardInstanceId
      : returnedEnergyOptions.length === 1
        ? (returnedEnergyOptions[0]?.id ?? null)
        : null
    : null
  const shuffledEnergyOptions = useMemo(() => {
    if (!pendingAttackRequiresShuffledEnergy || !activePlayer?.active) {
      return []
    }

    return (activePlayer.active.attachedCards ?? []).filter(isEnergyCard)
  }, [activePlayer?.active, pendingAttackRequiresShuffledEnergy])
  const shuffledEnergyOptionIds = useMemo(
    () => new Set(shuffledEnergyOptions.map(energyCard => energyCard.id)),
    [shuffledEnergyOptions]
  )
  const selectedShuffledEnergyIdsForResolve = pendingAttackRequiresShuffledEnergy
    ? selectedShuffledEnergyCardInstanceIds.filter(id => shuffledEnergyOptionIds.has(id))
    : []
  const benchDamageTargetOptions = pendingAttackRequiresBenchDamageTarget ? (opponentPlayer?.bench ?? []) : []
  const selectedBenchDamageTargetIsValid = benchDamageTargetOptions.some(
    card => card.id === selectedBenchDamageTargetCardInstanceId
  )
  const benchDamageTargetIdForResolve = selectedBenchDamageTargetIsValid
    ? selectedBenchDamageTargetCardInstanceId
    : benchDamageTargetOptions.length === 1
      ? (benchDamageTargetOptions[0]?.id ?? null)
      : null
  const benchDamageCounterOptions = pendingAttackRequiresBenchDamageCounters ? (opponentPlayer?.bench ?? []) : []
  const benchDamageCounterOptionIds = useMemo(
    () => new Set(benchDamageCounterOptions.map(card => card.id)),
    [benchDamageCounterOptions]
  )
  const selectedBenchDamageCounterAllocationsForResolve = useMemo(
    () =>
      Object.fromEntries(
        Object.entries(selectedBenchDamageCounterAllocations).filter(
          ([cardInstanceId, counters]) => benchDamageCounterOptionIds.has(cardInstanceId) && counters > 0
        )
      ),
    [benchDamageCounterOptionIds, selectedBenchDamageCounterAllocations]
  )
  const selectedBenchDamageCounterTotal = Object.values(selectedBenchDamageCounterAllocationsForResolve).reduce(
    (total, counters) => total + counters,
    0
  )
  const coinResultForResolve = pendingAttackRequiresCoinResult && selectedCoinResult ? selectedCoinResult : null
  const selectedHeadsCountValue = selectedHeadsCount.trim()
  const parsedHeadsCount = Number(selectedHeadsCountValue)
  const headsCountForResolve =
    pendingAttackRequiresHeadsCount &&
    selectedHeadsCountValue !== '' &&
    Number.isInteger(parsedHeadsCount) &&
    parsedHeadsCount >= 0
      ? parsedHeadsCount
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
    setSelectedBenchDamageCounterAllocations({})
    setSelectedCoinResult('')
    setSelectedHeadsCount('')
    setSelectedCopiedAttackId('')
  }, [turn?.id, turn?.pendingAttackId])

  useEffect(() => {
    if (selectedCopiedAttackId && !selectedCopiedAttackChoice) {
      setSelectedCopiedAttackId('')
    }
  }, [selectedCopiedAttackChoice, selectedCopiedAttackId])

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

  useEffect(() => {
    setSelectedBenchDamageCounterAllocations(previousAllocations => {
      const nextAllocations = Object.fromEntries(
        Object.entries(previousAllocations).filter(([cardInstanceId]) => benchDamageCounterOptionIds.has(cardInstanceId))
      )

      return Object.keys(nextAllocations).length === Object.keys(previousAllocations).length
        ? previousAllocations
        : nextAllocations
    })
  }, [benchDamageCounterOptionIds])

  if (!turn || (turn.status !== 'attack_declared' && turn.status !== 'attack_resolving')) {
    return null
  }

  const attacker = turn.pendingAttackerCardInstanceId ? cardsById.get(turn.pendingAttackerCardInstanceId) : null
  const defender = turn.pendingDefenderCardInstanceId ? cardsById.get(turn.pendingDefenderCardInstanceId) : null
  const attackLabel = turn.pendingAttackId ? formatAttackId(turn.pendingAttackId) : 'declared attack'
  const viewerCanAdvanceAttack = viewerPlayerId === turn.activePlayerId && isPlayerId(turn.activePlayerId)
  const commandPending = Boolean(resolveDeclaredAttackPendingPlayerId || finishAttackPendingPlayerId)
  const copiedAttackUnavailable = turn.pendingAttackRequiresCopiedAttack && copiedAttackOptions.length === 0
  const copiedAttackRequiresChoice = turn.pendingAttackRequiresCopiedAttack && copiedAttackOptions.length > 1 && !selectedCopiedAttackChoice
  const switchTargetRequired = pendingAttackRequiresSwitchTarget && switchTargetOptions.length > 1
  const discardedEnergyMaxSelection =
    resolutionEffectType === DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT
      ? 2
      : resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT
        ? 1
        : null
  const discardedEnergyDescription =
    resolutionEffectType === DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT
      ? 'This attack does 60 more damage for each selected Energy attached to Benched Pokémon, then discards those Energy cards during resolution. Select up to 2, or select none for no bonus damage.'
      : resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT
        ? "On Heads, this attack discards one Energy attached to the opponent's Active Pokémon after damage. If exactly one Energy is attached, resolution will discard it automatically. Tails discards none."
      : resolutionEffectType === DISCARD_OWN_BASIC_ENERGY_FOR_DAMAGE_EFFECT
        ? 'This attack does damage for each selected own Basic Energy attached to Pokémon in play, then discards those Energy cards during resolution. Selecting none resolves it for zero bonus damage.'
        : 'This attack resolves with the selected discarded Energy cards.'
  const discardedEnergyEmptyDescription =
    resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT
      ? `No Energy cards are visible on the opponent's Active Pokémon, so Heads will discard none.`
      : `No attached Energy cards are visible for ${formatPlayerId(turn.activePlayerId)}, so resolution will deal zero damage from this effect.`
  const returnedEnergyRequiresChoice = pendingAttackRequiresReturnedEnergy && returnedEnergyOptions.length > 1
  const returnedEnergyUnavailable = pendingAttackRequiresReturnedEnergy && returnedEnergyOptions.length === 0
  const shuffledEnergyRequiredCount = 3
  const shuffledEnergySelectedCount = selectedShuffledEnergyIdsForResolve.length
  const shuffledEnergyPartialSelection =
    pendingAttackRequiresShuffledEnergy &&
    shuffledEnergySelectedCount > 0 &&
    shuffledEnergySelectedCount !== shuffledEnergyRequiredCount
  const benchDamageTargetRequired =
    pendingAttackRequiresBenchDamageTarget &&
    shuffledEnergySelectedCount === shuffledEnergyRequiredCount &&
    benchDamageTargetOptions.length > 1
  const benchDamageTargetUnavailable =
    pendingAttackRequiresBenchDamageTarget &&
    shuffledEnergySelectedCount === shuffledEnergyRequiredCount &&
    benchDamageTargetOptions.length === 0
  const benchDamageCounterRequiredCount = 6
  const benchDamageCounterAllocationRequired =
    pendingAttackRequiresBenchDamageCounters && benchDamageCounterOptions.length > 0
  const benchDamageCounterAllocationIncomplete =
    benchDamageCounterAllocationRequired && selectedBenchDamageCounterTotal !== benchDamageCounterRequiredCount
  const coinResultRequired = pendingAttackRequiresCoinResult && !coinResultForResolve
  const defendingEnergyDiscardRequiresChoice =
    resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT &&
    coinResultForResolve === 'heads' &&
    discardedEnergyOptions.length > 1 &&
    selectedDiscardedEnergyIdsForResolve.length !== 1
  const headsCountRequired = pendingAttackRequiresHeadsCount && headsCountForResolve === null
  const missingActivePlayers = gameState.players.filter(player => !player.active)
  const awaitingPromptPlayerIds = gameState.awaitingPromptPlayerIds
  const awaitingPromptBlocksFinish = viewerCanAdvanceAttack && awaitingPromptPlayerIds.length > 0
  const awaitingOwnPrompt = awaitingPromptPlayerIds.includes(viewerPlayerId)
  const attackCannotFinish = missingActivePlayers.length > 0 || awaitingPromptBlocksFinish
  const finishAttackButtonLabel = finishAttackPendingPlayerId === turn.activePlayerId
    ? 'Finishing attack...'
    : missingActivePlayers.length > 0
      ? 'Choose replacement Active before finishing'
      : awaitingPromptBlocksFinish
        ? awaitingOwnPrompt
          ? 'Resolve your prompt before finishing'
          : `Waiting for ${formatPlayerList(awaitingPromptPlayerIds)} prompt`
        : 'Finish attack and end turn'
  const resolveDisabled =
    !viewerCanAdvanceAttack ||
    commandPending ||
    copiedAttackUnavailable ||
    copiedAttackRequiresChoice ||
    (switchTargetRequired && !selectedSwitchTargetIsValid) ||
    returnedEnergyUnavailable ||
    (returnedEnergyRequiresChoice && !selectedReturnedEnergyIsValid) ||
    shuffledEnergyPartialSelection ||
    benchDamageTargetUnavailable ||
    (benchDamageTargetRequired && !selectedBenchDamageTargetIsValid) ||
    benchDamageCounterAllocationIncomplete ||
    coinResultRequired ||
    defendingEnergyDiscardRequiresChoice ||
    headsCountRequired
  const resolveButtonLabel = resolveDeclaredAttackPendingPlayerId === turn.activePlayerId
    ? `Resolving ${attackLabel}...`
    : copiedAttackUnavailable
      ? `No copyable Tera attacks for ${attackLabel}`
      : copiedAttackRequiresChoice
        ? `Choose a copied attack for ${attackLabel}`
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
                    : benchDamageCounterAllocationIncomplete
                      ? `Allocate exactly ${benchDamageCounterRequiredCount} Bench damage counters for ${attackLabel}`
                      : coinResultRequired
                        ? `Choose a coin result for ${attackLabel}`
                        : defendingEnergyDiscardRequiresChoice
                          ? `Choose an Energy to discard for ${attackLabel}`
                          : headsCountRequired
                            ? `Enter a heads count for ${attackLabel}`
                            : `Resolve ${attackLabel}`
  const attackProgressGuideTitle = turn.status === 'attack_resolving' ? 'Damage recorded' : 'Attack declared'
  const attackProgressGuideDetail = turn.status === 'attack_resolving'
    ? `${attackLabel} has resolved. ${
        defender ? `${defender.name} now has ${defender.damage} damage.` : 'Damage and effects are recorded.'
      } Finish the attack to end ${formatPlayerId(turn.activePlayerId)}'s turn.`
    : `Resolve ${attackLabel} to apply its persisted damage and any authored effect before ending the turn.`
  const resolutionChecklistItems: ResolutionChecklistItem[] = []

  if (turn.pendingAttackRequiresCopiedAttack) {
    resolutionChecklistItems.push({
      label: 'Copied attack',
      tone: copiedAttackUnavailable ? 'blocked' : copiedAttackRequiresChoice ? 'waiting' : 'ready',
      value: copiedAttackUnavailable
        ? 'No executable Tera attacks'
        : copiedAttackOptions.length === 1
          ? `Auto: ${copiedAttackOptions[0]?.attackName ?? 'only copied attack'}`
          : selectedCopiedAttackChoice
            ? selectedCopiedAttackChoice.attackName
            : `${copiedAttackOptions.length} copy choices`
    })
  }

  if (pendingAttackRequiresCoinResult) {
    resolutionChecklistItems.push({
      label: 'Coin result',
      tone: coinResultRequired ? 'waiting' : 'ready',
      value: coinResultForResolve
        ? coinResultForResolve === 'heads'
          ? 'Heads selected'
          : 'Tails selected'
        : 'Choose Heads or Tails'
    })
  }

  if (pendingAttackRequiresHeadsCount) {
    resolutionChecklistItems.push({
      label: 'Heads count',
      tone: headsCountRequired ? 'waiting' : 'ready',
      value: headsCountForResolve === null ? 'Enter a count' : `${headsCountForResolve} heads`
    })
  }

  if (pendingAttackRequiresSwitchTarget) {
    resolutionChecklistItems.push({
      label: 'Switch target',
      tone: switchTargetRequired && !selectedSwitchTargetIsValid ? 'waiting' : 'ready',
      value: switchTargetOptions.length > 1
        ? selectedSwitchTargetIsValid
          ? cardsById.get(selectedSwitchBenchCardInstanceId)?.name ?? 'Bench target selected'
          : `${switchTargetOptions.length} Bench choices`
        : switchTargetOptions.length === 1
          ? `Auto: ${switchTargetOptions[0]?.name ?? 'only Bench target'}`
          : 'No switch target needed'
    })
  }

  if (pendingAttackRequiresDiscardedEnergy) {
    const selectedDiscardedEnergyCount = selectedDiscardedEnergyIdsForResolve.length
    const discardedEnergyValue =
      resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT && coinResultForResolve !== 'heads'
        ? 'Only after Heads'
        : resolutionEffectType === DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT && discardedEnergyOptions.length === 1
          ? `Auto: ${discardedEnergyOptions[0]?.energyCard.name ?? 'only Energy'}`
          : discardedEnergyOptions.length === 0
            ? 'No visible Energy'
            : discardedEnergyMaxSelection
              ? `${selectedDiscardedEnergyCount} / ${discardedEnergyMaxSelection} selected`
              : `${selectedDiscardedEnergyCount} selected`

    resolutionChecklistItems.push({
      label: 'Discarded Energy',
      tone: defendingEnergyDiscardRequiresChoice ? 'waiting' : 'ready',
      value: discardedEnergyValue
    })
  }

  if (pendingAttackRequiresReturnedEnergy) {
    resolutionChecklistItems.push({
      label: 'Returned Energy',
      tone: returnedEnergyUnavailable
        ? 'blocked'
        : returnedEnergyRequiresChoice && !selectedReturnedEnergyIsValid
          ? 'waiting'
          : 'ready',
      value: returnedEnergyUnavailable
        ? 'No Energy to return'
        : returnedEnergyOptions.length > 1
          ? selectedReturnedEnergyIsValid
            ? cardsById.get(selectedReturnedEnergyCardInstanceId)?.name ?? 'Energy selected'
            : `${returnedEnergyOptions.length} Energy choices`
          : `Auto: ${returnedEnergyOptions[0]?.name ?? 'only Energy'}`
    })
  }

  if (pendingAttackRequiresShuffledEnergy) {
    resolutionChecklistItems.push({
      label: 'Shuffled Energy',
      tone: shuffledEnergyPartialSelection ? 'waiting' : 'ready',
      value: shuffledEnergySelectedCount === 0
        ? 'Optional effect skipped'
        : `${shuffledEnergySelectedCount} / ${shuffledEnergyRequiredCount} selected`
    })
  }

  if (pendingAttackRequiresBenchDamageTarget && shuffledEnergySelectedCount === shuffledEnergyRequiredCount) {
    resolutionChecklistItems.push({
      label: 'Bench damage target',
      tone: benchDamageTargetUnavailable
        ? 'blocked'
        : benchDamageTargetRequired && !selectedBenchDamageTargetIsValid
          ? 'waiting'
          : 'ready',
      value: benchDamageTargetUnavailable
        ? 'No opponent Bench'
        : benchDamageTargetOptions.length > 1
          ? selectedBenchDamageTargetIsValid
            ? cardsById.get(selectedBenchDamageTargetCardInstanceId)?.name ?? 'Bench target selected'
            : `${benchDamageTargetOptions.length} Bench choices`
          : `Auto: ${benchDamageTargetOptions[0]?.name ?? 'only Bench target'}`
    })
  }

  if (pendingAttackRequiresBenchDamageCounters) {
    resolutionChecklistItems.push({
      label: 'Bench counters',
      tone: benchDamageCounterAllocationIncomplete ? 'waiting' : 'ready',
      value: benchDamageCounterOptions.length > 0
        ? `${selectedBenchDamageCounterTotal} / ${benchDamageCounterRequiredCount} counters`
        : 'No Bench targets'
    })
  }

  const resolutionChecklistReadyCount = resolutionChecklistItems.filter(item => item.tone === 'ready').length
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

  const setBenchDamageCounterAllocation = (cardInstanceId: string, counters: number) => {
    const normalizedCounters = Math.max(0, Math.min(benchDamageCounterRequiredCount, Math.floor(counters || 0)))

    setSelectedBenchDamageCounterAllocations(previousAllocations => {
      if (normalizedCounters === 0) {
        const { [cardInstanceId]: _removed, ...remainingAllocations } = previousAllocations

        return remainingAllocations
      }

      return {
        ...previousAllocations,
        [cardInstanceId]: normalizedCounters
      }
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

        <div className="rounded-xl border border-stone-200 bg-stone-50/80 px-3 py-2">
          <p className="text-xs font-semibold uppercase tracking-[0.14em] text-stone-600">
            {attackProgressGuideTitle}
          </p>
          <p className="mt-1 text-xs leading-5 text-stone-600">{attackProgressGuideDetail}</p>
        </div>

        {commandError ? <CommandErrorCard notice={commandError} /> : null}

        {resolutionChecklistItems.length > 0 ? (
          <div className="rounded-xl border border-stone-200 bg-stone-50/80 p-3">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.14em] text-stone-600">
                  Resolve requirements
                </p>
                <p className="mt-1 text-xs leading-5 text-stone-500">
                  Pick only the missing inputs, then resolve the attack in one engine command.
                </p>
              </div>
              <StatusBadge
                tone={resolutionChecklistReadyCount === resolutionChecklistItems.length ? 'active' : 'warning'}
              >
                {resolutionChecklistReadyCount}/{resolutionChecklistItems.length} ready
              </StatusBadge>
            </div>

            <ul className="mt-3 grid gap-1.5">
              {resolutionChecklistItems.map(item => (
                <li
                  className={`flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2 text-xs ${resolutionChecklistItemClassName(item.tone)}`}
                  key={item.label}
                >
                  <span className="font-medium">{item.label}</span>
                  <span className="flex flex-wrap items-center justify-end gap-2 text-right">
                    <span>{item.value}</span>
                    <span
                      className={`rounded-full px-2 py-0.5 font-semibold ${resolutionChecklistToneClassName(item.tone)}`}
                    >
                      {formatResolutionChecklistTone(item.tone)}
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {turn.pendingAttackRequiresCopiedAttack ? (
          <div className="rounded-xl border border-cyan-200 bg-cyan-50/70 p-3">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-cyan-900">Copied attack</p>
              <p className="text-xs leading-5 text-cyan-900/80">
                Gemstone Mimicry uses one executable attack from the opponent's Active Tera Pokémon as this attack.
              </p>
            </div>

            {copiedAttackOptions.length > 1 ? (
              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                {copiedAttackOptions.map(choice => {
                  const selected = choice.attackId === selectedCopiedAttackId

                  return (
                    <label
                      className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 text-xs transition ${
                        selected
                          ? 'border-cyan-700 bg-cyan-100 text-cyan-950'
                          : 'border-cyan-200 bg-stone-50 text-stone-700 hover:border-cyan-400'
                      }`}
                      key={choice.attackId}
                    >
                      <input
                        checked={selected}
                        className="mt-0.5"
                        disabled={!viewerCanAdvanceAttack || commandPending}
                        name="copied-attack-id"
                        onChange={() => setSelectedCopiedAttackId(choice.attackId)}
                        type="radio"
                      />
                      <span className="min-w-0">
                        <span className="block font-medium">{choice.attackName}</span>
                        <span className="mt-0.5 block font-mono text-[0.68rem] opacity-70">
                          {choice.attackId}
                          {choice.attackDamage ? ` · ${choice.attackDamage} damage` : ''}
                          {choice.attackEffectType ? ` · ${formatEventType(choice.attackEffectType)}` : ''}
                        </span>
                      </span>
                    </label>
                  )
                })}
              </div>
            ) : copiedAttackOptions.length === 1 ? (
              <p className="mt-3 rounded-lg border border-cyan-200 bg-stone-50 px-3 py-2 text-xs text-cyan-900">
                Only {copiedAttackOptions[0]?.attackName} is executable, so resolution will copy it automatically.
              </p>
            ) : (
              <p className="mt-3 rounded-lg border border-cyan-200 bg-stone-50 px-3 py-2 text-xs text-cyan-900">
                The opponent's Active Pokémon has no engine-executable Tera attacks available to copy.
              </p>
            )}
          </div>
        ) : null}

        {pendingAttackRequiresCoinResult ? (
          <div className="rounded-xl border border-yellow-200 bg-yellow-50/70 p-3">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-yellow-900">Coin result</p>
              <p className="text-xs leading-5 text-yellow-900/80">
                This attack needs a deterministic coin result before the persisted engine can resolve its coin-gated
                damage or effect.
              </p>
            </div>

            <div className="mt-3 grid gap-2 sm:grid-cols-2">
              {(['heads', 'tails'] as const).map(result => {
                const selected = selectedCoinResult === result

                return (
                  <label
                    className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 text-xs transition ${
                      selected
                        ? 'border-yellow-700 bg-yellow-100 text-yellow-950'
                        : 'border-yellow-200 bg-stone-50 text-stone-700 hover:border-yellow-400'
                    }`}
                    key={result}
                  >
                    <input
                      checked={selected}
                      className="mt-0.5"
                      disabled={!viewerCanAdvanceAttack || commandPending}
                      name="coin-result"
                      onChange={() => setSelectedCoinResult(result)}
                      type="radio"
                    />
                    <span className="min-w-0">
                      <span className="block font-medium">{result === 'heads' ? 'Heads' : 'Tails'}</span>
                      <span className="mt-0.5 block text-[0.68rem] opacity-70">
                        {result === 'heads' ? 'Apply the authored heads result.' : 'Resolve without the heads result.'}
                      </span>
                    </span>
                  </label>
                )
              })}
            </div>
          </div>
        ) : null}

        {pendingAttackRequiresHeadsCount ? (
          <div className="rounded-xl border border-yellow-200 bg-yellow-50/70 p-3">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-yellow-900">Heads count</p>
              <p className="text-xs leading-5 text-yellow-900/80">
                This attack needs a deterministic non-negative heads count before the persisted engine can resolve its
                coin-flip bonus damage.
              </p>
            </div>

            <label className="mt-3 block space-y-2 text-xs text-yellow-950">
              <span className="font-medium">Number of heads</span>
              <input
                className="w-full rounded-lg border border-yellow-200 bg-stone-50 px-3 py-2 font-mono text-sm text-yellow-950 outline-none transition placeholder:text-yellow-900/40 focus:border-yellow-600 focus:ring-2 focus:ring-yellow-100 disabled:cursor-not-allowed disabled:bg-stone-100 disabled:text-stone-400"
                disabled={!viewerCanAdvanceAttack || commandPending}
                min={0}
                onChange={event => setSelectedHeadsCount(event.currentTarget.value)}
                placeholder="0"
                step={1}
                type="number"
                value={selectedHeadsCount}
              />
              <span className="block text-[0.68rem] leading-4 text-yellow-900/70">
                Each heads adds the authored bonus damage. Enter 0 when the first flip is tails.
              </span>
            </label>
          </div>
        ) : null}

        {pendingAttackRequiresSwitchTarget ? (
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

        {pendingAttackRequiresDiscardedEnergy ? (
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
                {discardedEnergyEmptyDescription}
              </p>
            )}
          </div>
        ) : null}

        {pendingAttackRequiresReturnedEnergy ? (
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

        {pendingAttackRequiresShuffledEnergy ? (
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

        {pendingAttackRequiresBenchDamageCounters ? (
          <div className="rounded-xl border border-fuchsia-200 bg-fuchsia-50/70 p-3">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-fuchsia-900">
                Opponent Bench damage counters
              </p>
              <p className="text-xs leading-5 text-fuchsia-900/80">
                This attack puts exactly {benchDamageCounterRequiredCount} damage counters on the opponent's Benched
                Pokémon in any allocation. Bench knockouts now route through the engine's face-down Prize prompt
                sequence before the attack can finish.
              </p>
            </div>

            {benchDamageCounterOptions.length > 0 ? (
              <div className="mt-3 space-y-3">
                <div className="rounded-lg border border-fuchsia-200 bg-stone-50 px-3 py-2 text-xs text-fuchsia-900">
                  Allocated {selectedBenchDamageCounterTotal} / {benchDamageCounterRequiredCount} counters.
                </div>

                <div className="grid gap-2 sm:grid-cols-2">
                  {benchDamageCounterOptions.map(card => {
                    const counters = selectedBenchDamageCounterAllocations[card.id] ?? 0

                    return (
                      <label
                        className="flex items-start justify-between gap-3 rounded-lg border border-fuchsia-200 bg-stone-50 px-3 py-2 text-xs text-stone-700"
                        key={card.id}
                      >
                        <span className="min-w-0">
                          <span className="block font-medium">{card.name}</span>
                          <span className="mt-0.5 block font-mono text-[0.68rem] opacity-70">
                            {card.damage} damage · {card.cardId}
                          </span>
                        </span>
                        <input
                          className="w-16 rounded-lg border border-fuchsia-200 bg-stone-50 px-2 py-1 text-right font-mono text-xs text-fuchsia-950 outline-none focus:border-fuchsia-600 focus:ring-2 focus:ring-fuchsia-100 disabled:cursor-not-allowed disabled:bg-stone-100 disabled:text-stone-400"
                          disabled={!viewerCanAdvanceAttack || commandPending}
                          max={benchDamageCounterRequiredCount}
                          min={0}
                          onChange={event =>
                            setBenchDamageCounterAllocation(card.id, Number(event.currentTarget.value))
                          }
                          type="number"
                          value={counters}
                        />
                      </label>
                    )
                  })}
                </div>
              </div>
            ) : (
              <p className="mt-3 rounded-lg border border-fuchsia-200 bg-stone-50 px-3 py-2 text-xs text-fuchsia-900">
                No opponent Benched Pokémon are available, so resolution will apply only the Active damage.
              </p>
            )}
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
                benchDamageTargetCardInstanceId: benchDamageTargetIdForResolve,
                benchDamageCounterAllocations: selectedBenchDamageCounterAllocationsForResolve,
                coinResult: coinResultForResolve,
                headsCount: headsCountForResolve,
                copiedAttackId: copiedAttackIdForResolve
              })
            }
            type="button"
          >
            {resolveButtonLabel}
          </button>
        ) : null}

        {turn.status === 'attack_resolving' ? (
          <div className="space-y-2">
            {awaitingPromptBlocksFinish ? (
              <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs leading-5 text-amber-900">
                {awaitingOwnPrompt
                  ? 'Resolve the prompt in the Viewer prompts panel before finishing this attack.'
                  : `Waiting for ${formatPlayerList(awaitingPromptPlayerIds)} to resolve their prompt before this attack can finish.`}
              </div>
            ) : null}

            <button
              className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
              disabled={!viewerCanAdvanceAttack || commandPending || attackCannotFinish}
              onClick={() => onFinishAttack({ playerId: turn.activePlayerId })}
              type="button"
            >
              {finishAttackButtonLabel}
            </button>
          </div>
        ) : null}
      </div>
    </Panel>
  )
}

function ActionAffordancesPanel({
  actions,
  cardsById,
  commandError,
  chooseReplacementActivePendingCardId,
  gameState,
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
  retreatPendingKey,
  ultraBallPostSearchHandoff,
  viewerPlayerId
}: {
  actions: ActionAffordance[]
  cardsById: Map<string, CardSummary>
  commandError: CommandErrorNotice | null
  chooseReplacementActivePendingCardId: string | null
  gameState: GameState
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
  ultraBallPostSearchHandoff: UltraBallPostSearchHandoff | null
  viewerPlayerId: PlayerId
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
  const actionGroups = useMemo(() => groupActionAffordances(actions), [actions])
  const primaryActionGroup = actionGroups[0]
  const primaryActionGroupId = primaryActionGroup?.id
  const postSearchHandoff = ultraBallPostSearchHandoffPlan(
    gameState,
    viewerPlayerId,
    ultraBallPostSearchHandoff,
    cardsById,
    actionGroups
  )
  const showActionWindowGuide = Boolean(gameState.currentTurn?.status === 'action_window' && primaryActionGroup)

  if (actionGroups.length === 0 && !commandError) {
    return null
  }

  return (
    <Panel
      title="Available actions"
      trailing={<StatusBadge tone={actions.length > 0 ? 'active' : 'neutral'}>{actions.length}</StatusBadge>}
    >
      <div className="space-y-4">
        {commandError ? <CommandErrorCard notice={commandError} /> : null}

        {postSearchHandoff ? (
          <UltraBallPostSearchHandoffCard handoff={postSearchHandoff} />
        ) : primaryActionGroup && showActionWindowGuide ? (
          <ActionWindowGuide
            actionGroups={actionGroups}
            cardsById={cardsById}
            currentTurn={gameState.currentTurn}
            primaryActionGroup={primaryActionGroup}
            viewerPlayer={gameState.players.find(player => player.playerId === viewerPlayerId) ?? null}
            viewerPlayerId={viewerPlayerId}
          />
        ) : primaryActionGroup ? (
          <div className="rounded-xl border border-emerald-200 bg-emerald-50/80 px-3 py-2 text-xs leading-5 text-emerald-950">
            <span className="font-semibold uppercase tracking-[0.14em] text-emerald-800">Current priority</span>
            <span className="mt-0.5 block">
              {primaryActionGroup.title}: {actionGroupDescription(primaryActionGroup, actionGroups)}
            </span>
          </div>
        ) : null}

        {actionGroups.length > 0 ? (
          actionGroups.map(group => (
            <section className="space-y-2" key={group.id}>
              <div className="flex items-start justify-between gap-3 px-1">
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-[0.16em] text-stone-500">
                    {group.title}
                  </h3>
                  <p className="mt-1 text-xs leading-5 text-stone-500">
                    {actionGroupDescription(group, actionGroups)}
                  </p>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  {group.id === primaryActionGroupId ? (
                    <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800">
                      next
                    </span>
                  ) : null}
                  <StatusBadge tone={actionGroupBadgeTone(group.id, group.id === primaryActionGroupId)}>
                    {group.actions.length}
                  </StatusBadge>
                </div>
              </div>

              <ul className="space-y-1.5">
                {actionRenderEntries(group.actions, cardsById).map(entry => (
                  <ActionAffordanceCard
                    action={entry.action}
                    actionCommandPending={actionCommandPending}
                    attachEnergyPendingKey={attachEnergyPendingKey}
                    benchOptions={entry.benchOptions}
                    cardsById={cardsById}
                    chooseReplacementActivePendingCardId={chooseReplacementActivePendingCardId}
                    declareAttackPendingKey={declareAttackPendingKey}
                    endTurnPendingPlayerId={endTurnPendingPlayerId}
                    evolutionOptions={entry.evolutionOptions}
                    evolveFromHandPendingKey={evolveFromHandPendingKey}
                    key={entry.key}
                    onAttachEnergy={onAttachEnergy}
                    onChooseReplacementActive={onChooseReplacementActive}
                    onDeclareAttack={onDeclareAttack}
                    onEndTurn={onEndTurn}
                    onEvolveFromHand={onEvolveFromHand}
                    onPlayBasicToBench={onPlayBasicToBench}
                    onPlayCard={onPlayCard}
                    onRetreat={onRetreat}
                    playBasicToBenchPendingCardId={playBasicToBenchPendingCardId}
                    playCardPendingCardId={playCardPendingCardId}
                    postSearchBattleAttackIds={postSearchHandoff?.battleAttackIds ?? []}
                    postSearchBenchCardInstanceIds={postSearchHandoff?.benchableCardInstanceIds ?? []}
                    postSearchEndTurnPlayerIds={postSearchHandoff?.endTurnPlayerIds ?? []}
                    retreatPendingKey={retreatPendingKey}
                  />
                ))}
              </ul>
            </section>
          ))
        ) : (
          <RailEmptyState title="No legal action returned for this viewer">
            The command error above did not expose a follow-up action. Refresh state, confirm turn ownership, or switch
            to the player currently asked to act.
          </RailEmptyState>
        )}
      </div>
    </Panel>
  )
}

type UltraBallPostSearchHandoffPlan = {
  selectedCardNames: string
  benchableCardInstanceIds: string[]
  battleAttackIds: string[]
  endTurnPlayerIds: PlayerId[]
  handTitle: string
  handDetail: string
  battleDetail: string
  turnDetail: string
  nextLabel: string
}

function ultraBallPostSearchHandoffPlan(
  gameState: GameState,
  viewerPlayerId: PlayerId,
  handoff: UltraBallPostSearchHandoff | null,
  cardsById: Map<string, CardSummary>,
  actionGroups: ActionGroup[]
): UltraBallPostSearchHandoffPlan | null {
  if (!handoff || handoff.gameId !== gameState.gameId || handoff.playerId !== viewerPlayerId) {
    return null
  }

  if (gameState.currentTurn?.status !== 'action_window' || gameState.prompts.length > 0) {
    return null
  }

  const latestEvent = gameState.events[gameState.events.length - 1]

  if (latestEvent?.type !== 'card_play_completed' || latestEvent.playerId !== viewerPlayerId) {
    return null
  }

  const selectedCards = handoff.selectedCardInstanceIds.map(cardInstanceId => cardsById.get(cardInstanceId))
  const selectedCardNames = selectedCards
    .map(card => card?.name)
    .filter((name): name is string => Boolean(name))
    .join(', ')
  const selectedCardSummary = selectedCardNames || 'The selected Pokémon'
  const handGroup = actionGroups.find(group => group.id === 'hand')
  const battleGroup = actionGroups.find(group => group.id === 'battle')
  const turnGroup = actionGroups.find(group => group.id === 'turn')
  const battleAction = battleGroup?.actions.find(action => action.key === 'declare_attack')
  const turnAction = turnGroup?.actions.find(action => action.key === 'end_turn')
  const benchableSearchedCards = handGroup
    ? handGroup.actions.flatMap(action =>
        action.key === 'play_basic_to_bench'
          ? handoff.selectedCardInstanceIds.filter(cardInstanceId => action.sourceCardInstanceIds.includes(cardInstanceId))
          : []
      )
    : []
  const benchableNames = benchableSearchedCards
    .map(cardInstanceId => cardsById.get(cardInstanceId)?.name)
    .filter((name): name is string => Boolean(name))
    .join(', ')
  const benchableSummary = benchableNames || 'The searched Basic Pokémon'
  const battleAttackIds =
    battleGroup?.actions.flatMap(action =>
      action.key === 'declare_attack' && action.attackId ? [action.attackId] : []
    ) ?? []
  const endTurnPlayerIds =
    turnGroup?.actions.flatMap(action => (action.key === 'end_turn' && isPlayerId(action.playerId) ? [action.playerId] : [])) ?? []
  const battleActionLabel = battleAction?.attackName
    ? `Declare ${battleAction.attackName}`
    : battleAction?.attackId
      ? `Declare ${formatAttackId(battleAction.attackId)}`
      : null
  const turnActionLabel = turnAction ? `End ${formatPlayerId(turnAction.playerId)}'s turn` : null

  return {
    selectedCardNames: selectedCardSummary,
    benchableCardInstanceIds: benchableSearchedCards,
    battleAttackIds,
    endTurnPlayerIds,
    handTitle: benchableSearchedCards.length
      ? 'Bench the searched Basic if it helps now'
      : handGroup
        ? 'Review the searched card in hand'
        : 'Searched card is ready for later',
    handDetail: benchableSearchedCards.length
      ? `${benchableSummary} is now in hand and can take the next Bench slot. Bench it if it improves this turn.`
      : handGroup
        ? `${selectedCardSummary} is in hand. Use any remaining Hand and board actions before committing to battle.`
        : `${selectedCardSummary} is in hand. No Hand and board action remains from this state; move directly to battle or turn flow.`,
    battleDetail: battleActionLabel
      ? `${battleActionLabel} is live in Battle decisions; choosing it clears this handoff and advances into attack resolution.`
      : battleGroup
        ? 'Battle decisions are available again; retreat or pick the stronger battle line before passing.'
        : 'No battle decision is legal yet from the refreshed action window.',
    turnDetail: turnActionLabel
      ? `${turnActionLabel} is live if you want to pass; choosing it clears this handoff and advances the persisted turn.`
      : 'Turn flow will appear once required battle or board decisions are cleared.',
    nextLabel: benchableSearchedCards.length ? 'bench' : battleActionLabel ? 'battle' : turnActionLabel ? 'pass' : handGroup ? 'review' : 'clear'
  }
}

function UltraBallPostSearchHandoffCard({ handoff }: { handoff: UltraBallPostSearchHandoffPlan }) {
  return (
    <div className="rounded-xl border border-emerald-200 bg-[oklch(0.982_0.018_155)] p-3 text-xs leading-5 text-emerald-950">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-xs font-semibold uppercase tracking-[0.14em] text-emerald-800">
            Trainer complete
          </h3>
          <p className="mt-1 font-medium text-stone-950">Ultra Ball returned you to the action window</p>
          <p className="mt-1 text-stone-600">
            {handoff.selectedCardNames} moved from deck to hand and the deck shuffled. Continue from the legal
            actions below.
          </p>
        </div>
        <StatusBadge tone="active">search done</StatusBadge>
      </div>

      <div className="mt-3 space-y-2">
        <ActionWindowGuideStep
          detail="The required discard and deck-search prompts are resolved, so the engine has released priority back to this player."
          label="done"
          title="Trainer resolved"
          tone="clear"
        />
        <ActionWindowGuideStep
          detail={handoff.handDetail}
          label={handoff.nextLabel}
          title={handoff.handTitle}
          tone="focus"
        />
        <ActionWindowGuideStep
          detail={`${handoff.battleDetail} ${handoff.turnDetail}`}
          label="then"
          title="Return to battle or turn flow"
          tone="available"
        />
      </div>
    </div>
  )
}

function ActionWindowGuide({
  actionGroups,
  cardsById,
  currentTurn,
  primaryActionGroup,
  viewerPlayer,
  viewerPlayerId
}: {
  actionGroups: ActionGroup[]
  cardsById: Map<string, CardSummary>
  currentTurn: GameState['currentTurn']
  primaryActionGroup: ActionGroup
  viewerPlayer: PlayerView | null
  viewerPlayerId: PlayerId
}) {
  const handGroup = actionGroups.find(group => group.id === 'hand')
  const battleGroup = actionGroups.find(group => group.id === 'battle')
  const turnGroup = actionGroups.find(group => group.id === 'turn')
  const basicBenchOptions = handGroup
    ? uniqueBasicBenchOptions(handGroup.actions.flatMap(action => basicBenchCommandOptions(action, cardsById)))
    : []
  const playCardOptions = handGroup
    ? uniquePlayCardOptions(handGroup.actions.flatMap(action => playCardCommandOptions(action, cardsById)))
    : []
  const evolutionOptions = handGroup
    ? uniqueEvolutionOptions(handGroup.actions.flatMap(action => evolutionCommandOptions(action, cardsById)))
    : []
  const handChoiceCount = handGroup ? handActionChoiceCount(handGroup, cardsById) : 0
  const turnOwnerId = currentTurn?.activePlayerId ?? viewerPlayerId
  const turnOwnerLabel = formatPlayerId(turnOwnerId)
  const viewerLabel = formatPlayerId(viewerPlayerId)
  const viewerOwnsTurn = turnOwnerId === viewerPlayerId
  const activeName = viewerPlayer?.active?.name ?? 'the Active Pokémon'
  const hasRetreatedThisTurn = viewerOwnsTurn && Boolean(viewerPlayer?.retreatedThisTurn)
  const viewerBoardDetail = viewerOwnsTurn
    ? `${viewerLabel} has ${activeName} Active${hasRetreatedThisTurn ? ' after retreating this turn' : ''}, ${
        actionCountLabel(viewerPlayer?.handCount ?? 0, 'card')
      } in hand, and ${viewerPlayer?.bench.length ?? 0} on Bench.`
    : `${turnOwnerLabel} owns this action window. This tab is ${viewerLabel}; use the matching seat for commands.`
  const handDetail = handGroup
    ? handActionGuideDetail(handGroup, basicBenchOptions, evolutionOptions, playCardOptions, handChoiceCount, {
        hasBattleActions: Boolean(battleGroup),
        hasTurnFlow: Boolean(turnGroup)
      })
    : battleGroup
      ? 'No hand or board command is legal from this view. Review battle decisions before turn flow.'
      : turnGroup
        ? 'No hand or board command is legal from this view. Only turn flow remains.'
        : 'No hand or board command is legal from this view. Finish the required choice before more actions appear.'
  const battleDetail = battleGroup
    ? turnGroup
      ? 'Battle decisions and End Turn are both legal. Attack when the board is set, otherwise pass the turn.'
      : 'Battle decisions are available. Review retreat and paid attacks before leaving the window.'
    : turnGroup
      ? handGroup
        ? 'Turn flow is available, but hand and board choices are still live. End the turn only after this board is set.'
        : 'Only turn flow remains. End the turn after confirming hand, Bench, and attached Energy.'
      : 'Finish the required choice before battle or turn-flow actions appear.'
  const guideTitle = currentTurn?.turnNumber === 1 ? 'First action window' : 'Action window plan'
  const priorityTitle =
    hasRetreatedThisTurn && primaryActionGroup.id === 'hand'
      ? 'Retreat complete; hand choices remain'
      : primaryActionGroup.id === 'battle' && handGroup
      ? 'Battle ready, board still open'
      : `Follow ${primaryActionGroup.title}`

  return (
    <div className="rounded-xl border border-emerald-200 bg-[oklch(0.982_0.018_155)] p-3 text-xs leading-5 text-emerald-950">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-xs font-semibold uppercase tracking-[0.14em] text-emerald-800">
            {guideTitle}
          </h3>
          <p className="mt-1 text-stone-600">{viewerBoardDetail}</p>
        </div>
        <StatusBadge tone="active">actions live</StatusBadge>
      </div>

      <div className="mt-3 space-y-2">
        <ActionWindowGuideStep
          detail={priorityInstruction(primaryActionGroup, {
            hasBattleActions: Boolean(battleGroup),
            hasHandActions: Boolean(handGroup),
            hasTurnFlow: Boolean(turnGroup),
            retreatedThisTurn: hasRetreatedThisTurn
          })}
          label="focus"
          title={priorityTitle}
          tone="focus"
        />
        <ActionWindowGuideStep
          detail={handDetail}
          label={handGroup ? 'available' : 'clear'}
          title="Check hand and board"
          tone={primaryActionGroup.id === 'hand' ? 'focus' : handGroup ? 'available' : 'clear'}
        />
        <ActionWindowGuideStep
          detail={battleDetail}
          label={battleGroup ? 'ready' : turnGroup ? 'pass' : 'blocked'}
          title="Commit or pass"
          tone={primaryActionGroup.id === 'battle' || primaryActionGroup.id === 'turn' ? 'focus' : battleGroup || turnGroup ? 'available' : 'clear'}
        />
      </div>
    </div>
  )
}

function actionGroupDescription(group: ActionGroup, actionGroups: ActionGroup[]) {
  if (group.id !== 'hand') {
    return group.description
  }

  const commandPhrases = [
    group.actions.some(action => action.key === 'play_card') ? 'play engine-defined cards' : null,
    group.actions.some(action => action.key === 'play_basic_to_bench') ? 'Bench Basic Pokémon' : null,
    group.actions.some(action => action.key === 'evolve_from_hand') ? 'evolve eligible Pokémon' : null,
    group.actions.some(action => action.key === 'attach_energy') ? 'attach Energy' : null
  ].filter((phrase): phrase is string => Boolean(phrase))

  if (commandPhrases.length === 0) {
    return group.description
  }

  const followUpPhrase = handActionFollowUpPhrase({
    hasBattleActions: actionGroups.some(actionGroup => actionGroup.id === 'battle'),
    hasTurnFlow: actionGroups.some(actionGroup => actionGroup.id === 'turn')
  })

  return `${capitalizeSentence(formatPhraseList(commandPhrases))} ${followUpPhrase}.`
}

function handActionGuideDetail(
  handGroup: ActionGroup,
  basicBenchOptions: BasicBenchCommandOption[],
  evolutionOptions: EvolutionCommandOption[],
  playCardOptions: PlayCardCommandOption[],
  handChoiceCount: number,
  followUp: { hasBattleActions: boolean; hasTurnFlow: boolean }
) {
  const choiceLabel = actionCountLabel(handChoiceCount, 'hand and board choice')
  const hasRepeatedBenchChoices = repeatedBasicBenchBaseLabels(basicBenchOptions).size > 0
  const hasRepeatedEvolutionChoices = repeatedEvolutionBaseLabels(evolutionOptions).size > 0
  const hasRepeatedPlayCardChoices = repeatedPlayCardBaseLabels(playCardOptions).size > 0
  const hasBasicBenchChoices = basicBenchOptions.length > 0
  const hasEvolutionChoices = evolutionOptions.length > 0
  const hasAttachEnergyChoice = handGroup.actions.some(action => action.key === 'attach_energy')
  const hasTrainerChoice = playCardOptions.length > 0
  const followUpPhrase = handActionFollowUpPhrase(followUp)
  const evolutionTargetScope = evolutionTargetScopeLabel(evolutionOptions)
  const evolutionSourceCount = new Set(evolutionOptions.map(option => option.evolutionCardInstanceId)).size
  const evolutionTargetCount = new Set(evolutionOptions.map(option => option.targetCardInstanceId)).size

  if (hasBasicBenchChoices && hasEvolutionChoices) {
    return hasRepeatedBenchChoices || hasRepeatedEvolutionChoices
      ? `${choiceLabel} visible across Bench and Evolution. Duplicate Basics use hand-slot labels; evolution choices name the in-play target, so pick the exact cards ${followUpPhrase}.`
      : `${choiceLabel} visible across Bench and Evolution. Grow the Bench first, then decide whether an evolution improves the board ${followUpPhrase}.`
  }

  if (hasEvolutionChoices) {
    if (hasRepeatedEvolutionChoices && evolutionSourceCount === 1 && evolutionTargetCount > 1) {
      return `${choiceLabel} visible. The same hand copy can evolve ${evolutionTargetCountLabel(
        evolutionOptions
      )}; use the target label to choose the exact Pokémon stack ${followUpPhrase}.`
    }

    return hasRepeatedEvolutionChoices
      ? `${choiceLabel} visible. Evolution choices name ${evolutionTargetScope} and the hand copy, so choose the exact Pokémon stack ${followUpPhrase}.`
      : `${choiceLabel} visible. Evolution is legal now; choose the Pokémon stack that improves the board ${followUpPhrase}.`
  }

  if (hasBasicBenchChoices) {
    return hasRepeatedBenchChoices
      ? `${choiceLabel} visible. Duplicate Basics use hand-slot labels, so choose the exact copy to Bench ${followUpPhrase}.`
      : `${choiceLabel} visible. Bench the Basic Pokémon that improves the board ${followUpPhrase}.`
  }

  if (hasAttachEnergyChoice && hasTrainerChoice) {
    return hasRepeatedPlayCardChoices
      ? `${choiceLabel} visible. Duplicate Trainers use hand-slot labels; play one or attach Energy ${followUpPhrase}.`
      : `${choiceLabel} visible. Play Trainers or attach Energy ${followUpPhrase}.`
  }

  if (hasTrainerChoice) {
    return hasRepeatedPlayCardChoices
      ? `${choiceLabel} visible. Duplicate Trainers use hand-slot labels, so choose the exact copy to play ${followUpPhrase}.`
      : `${choiceLabel} visible. Play Trainers ${followUpPhrase}.`
  }

  if (hasAttachEnergyChoice) {
    return `${choiceLabel} visible. Attach Energy ${followUpPhrase}.`
  }

  return `${choiceLabel} visible. Resolve the remaining hand or board choice ${followUpPhrase}.`
}

function evolutionTargetScopeLabel(evolutionOptions: EvolutionCommandOption[]) {
  const targetZones = new Set(evolutionOptions.map(option => option.targetCard?.zone).filter(Boolean))
  const hasActiveTarget = targetZones.has('active')
  const hasBenchTarget = targetZones.has('bench')

  if (hasActiveTarget && hasBenchTarget) {
    return 'the Active or Bench target'
  }

  if (hasBenchTarget) {
    return 'each Bench target'
  }

  if (hasActiveTarget) {
    return 'the Active target'
  }

  return 'the in-play target'
}

function evolutionTargetCountLabel(evolutionOptions: EvolutionCommandOption[]) {
  const targetCount = new Set(evolutionOptions.map(option => option.targetCardInstanceId)).size
  const targetZones = new Set(evolutionOptions.map(option => option.targetCard?.zone).filter(Boolean))

  if (targetZones.size === 1 && targetZones.has('bench')) {
    return actionCountLabel(targetCount, 'Bench target')
  }

  if (targetZones.size === 1 && targetZones.has('active')) {
    return actionCountLabel(targetCount, 'Active target')
  }

  return actionCountLabel(targetCount, 'target')
}

function handActionFollowUpPhrase({
  hasBattleActions,
  hasTurnFlow
}: {
  hasBattleActions: boolean
  hasTurnFlow: boolean
}) {
  if (hasBattleActions && hasTurnFlow) {
    return 'before attacking or passing'
  }

  if (hasBattleActions) {
    return 'before choosing a battle action'
  }

  if (hasTurnFlow) {
    return 'before ending the turn'
  }

  return 'before the next engine decision'
}

function formatPhraseList(phrases: string[]) {
  if (phrases.length === 0) {
    return ''
  }

  if (phrases.length === 1) {
    return phrases[0]
  }

  return `${phrases.slice(0, -1).join(', ')} and ${phrases[phrases.length - 1]}`
}

function capitalizeSentence(sentence: string) {
  return sentence ? `${sentence.slice(0, 1).toUpperCase()}${sentence.slice(1)}` : sentence
}

function handActionChoiceCount(handGroup: ActionGroup, cardsById: Map<string, CardSummary>) {
  return handGroup.actions.reduce((count, action) => {
    switch (action.key) {
      case 'play_basic_to_bench':
        return count + basicBenchCommandOptions(action, cardsById).length
      case 'evolve_from_hand':
        return count + evolutionCommandOptions(action, cardsById).length
      case 'attach_energy':
        return count + action.sourceCardInstanceIds.length * action.targetCardInstanceIds.length
      case 'play_card':
        return count + action.sourceCardInstanceIds.length
      default:
        return count + 1
    }
  }, 0)
}

function ActionWindowGuideStep({
  detail,
  label,
  title,
  tone
}: {
  detail: string
  label: string
  title: string
  tone: 'available' | 'clear' | 'focus'
}) {
  const className =
    tone === 'focus'
      ? 'border-emerald-200 bg-white text-emerald-950'
      : tone === 'available'
        ? 'border-stone-200 bg-white text-stone-700'
        : 'border-stone-200 bg-[oklch(0.99_0.004_155)] text-stone-500'
  const badgeClassName =
    tone === 'focus'
      ? 'bg-emerald-100 text-emerald-800'
      : tone === 'available'
        ? 'bg-stone-200 text-stone-700'
        : 'bg-stone-100 text-stone-500'

  return (
    <div className={`rounded-lg border px-3 py-2 ${className}`}>
      <div className="flex items-center justify-between gap-2">
        <p className="font-medium text-stone-950">{title}</p>
        <span className={`rounded-full px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.12em] ${badgeClassName}`}>
          {label}
        </span>
      </div>
      <p className="mt-1 text-xs leading-5">{detail}</p>
    </div>
  )
}

function priorityInstruction(
  group: ActionGroup,
  context: {
    hasBattleActions?: boolean
    hasHandActions?: boolean
    hasTurnFlow?: boolean
    retreatedThisTurn?: boolean
  } = {}
) {
  switch (group.id) {
    case 'required':
      return 'A required choice is blocking progress. Resolve it before optional actions.'
    case 'battle':
      if (context.hasHandActions && context.hasTurnFlow) {
        return 'Battle is ready, but hand and board choices remain legal. Improve the board first if it helps, then attack or pass.'
      }

      if (context.hasHandActions) {
        return 'Battle is ready, but hand and board choices remain legal. Improve the board first if it helps, then choose the attack.'
      }

      return 'Battle decisions are most consequential now. Review retreat and paid attacks first.'
    case 'hand':
      if (context.retreatedThisTurn && context.hasTurnFlow) {
        return 'Retreat is complete and battle choices are no longer live from this Active. Use remaining hand and board actions now, then end the turn.'
      }

      if (context.hasBattleActions && context.hasTurnFlow) {
        return 'Hand and board actions are the safest first pass. Improve the board before attacking or ending.'
      }

      if (context.hasBattleActions) {
        return 'Hand and board actions are the safest first pass. Improve the board before choosing a battle action.'
      }

      if (context.hasTurnFlow) {
        return 'Hand and board actions are the safest first pass. Improve the board before ending the turn.'
      }

      return 'Hand and board actions are the safest first pass. Improve the board before the next engine decision.'
    case 'turn':
      return 'No higher-priority move is available. End the turn after confirming the board state.'
    default:
      return 'Use the engine action exposed first, then refresh the board if the next step is unclear.'
  }
}

function ActionAffordanceCard({
  action,
  actionCommandPending,
  attachEnergyPendingKey,
  benchOptions: providedBenchOptions,
  cardsById,
  chooseReplacementActivePendingCardId,
  declareAttackPendingKey,
  endTurnPendingPlayerId,
  evolutionOptions: providedEvolutionOptions,
  evolveFromHandPendingKey,
  onAttachEnergy,
  onChooseReplacementActive,
  onDeclareAttack,
  onEndTurn,
  onEvolveFromHand,
  onPlayBasicToBench,
  onPlayCard,
  onRetreat,
  playBasicToBenchPendingCardId,
  playCardPendingCardId,
  postSearchBattleAttackIds,
  postSearchBenchCardInstanceIds,
  postSearchEndTurnPlayerIds,
  retreatPendingKey
}: {
  action: ActionAffordance
  actionCommandPending: boolean
  attachEnergyPendingKey: string | null
  benchOptions?: BasicBenchCommandOption[]
  cardsById: Map<string, CardSummary>
  chooseReplacementActivePendingCardId: string | null
  declareAttackPendingKey: string | null
  endTurnPendingPlayerId: string | null
  evolutionOptions?: EvolutionCommandOption[]
  evolveFromHandPendingKey: string | null
  onAttachEnergy: (input: AttachEnergyCommand) => void
  onChooseReplacementActive: (input: ChooseReplacementActiveCommand) => void
  onDeclareAttack: (input: DeclareAttackCommand) => void
  onEndTurn: (input: EndTurnCommand) => void
  onEvolveFromHand: (input: EvolveFromHandCommand) => void
  onPlayBasicToBench: (input: PlayBasicToBenchCommand) => void
  onPlayCard: (input: PlayCardCommand) => void
  onRetreat: (input: RetreatCommand) => void
  playBasicToBenchPendingCardId: string | null
  playCardPendingCardId: string | null
  postSearchBattleAttackIds: string[]
  postSearchBenchCardInstanceIds: string[]
  postSearchEndTurnPlayerIds: PlayerId[]
  retreatPendingKey: string | null
}) {
  const canRunAction = !actionCommandPending && isPlayerId(action.playerId)
  const isPostSearchEndTurnAction = isPlayerId(action.playerId) && postSearchEndTurnPlayerIds.includes(action.playerId)
  const playCardPromptGuide = ultraBallPlayCardPromptGuide(action, cardsById)
  const playCardOptions = uniquePlayCardOptions(playCardCommandOptions(action, cardsById))
  const repeatedPlayCardLabels = repeatedPlayCardBaseLabels(playCardOptions)
  const benchOptions = providedBenchOptions ?? basicBenchCommandOptions(action, cardsById)
  const repeatedBenchLabels = repeatedBasicBenchBaseLabels(benchOptions)
  const evolutionOptions = providedEvolutionOptions ?? evolutionCommandOptions(action, cardsById)
  const repeatedEvolutionLabels = repeatedEvolutionBaseLabels(evolutionOptions)

  return (
    <li className={`rounded-xl border px-3 py-2.5 text-sm ${actionSurfaceClassName(action)}`}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <p className="font-medium leading-5 text-stone-950">{action.label}</p>
            <span className="rounded-full bg-stone-200 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.12em] text-stone-600">
              {formatEventType(action.kind)}
            </span>
          </div>
          <p className="mt-1 text-xs leading-5 text-stone-500">{actionSummary(action)}</p>
        </div>
        <StatusBadge tone={action.key === 'choose_replacement_active' ? 'warning' : 'neutral'}>
          {formatPlayerId(action.playerId)}
        </StatusBadge>
      </div>

      {action.note ? <p className="mt-2 text-xs leading-5 text-stone-600">{action.note}</p> : null}

      {playCardPromptGuide ? <PromptFlowGuideCard guide={playCardPromptGuide} /> : null}

      {actionHasMetadata(action) ? (
        <details className="mt-2 rounded-lg border border-stone-200 bg-stone-50 px-3 py-2 text-xs text-stone-600">
          <summary className="cursor-pointer font-medium text-stone-700">Engine details</summary>
          <div className="mt-2 flex flex-wrap gap-2">
            <ActionCount count={action.sourceCardInstanceIds.length} label="source" />
            <ActionCount count={action.targetCardInstanceIds.length} label="target" />
            <ActionCount count={action.requiredSourceCount} label="required source" />
            <ActionCount count={action.promptIds.length} label="prompt" />
            <ActionCount count={action.choiceKeys.length} label="choice key" />
          </div>
        </details>
      ) : null}

      {playCardOptions.length > 0 ? (
        <div className="mt-2 space-y-1.5">
          {playCardOptions.length > 1 ? <PlayCardChoiceGuide options={playCardOptions} /> : null}

          {playCardOptions.map(option => {
            const isPending = playCardPendingCardId === option.cardInstanceId
            const needsSourceCopyLabel = repeatedPlayCardLabels.has(option.baseLabel)

            return (
              <ActionCommandButton
                disabled={!canRunAction}
                key={option.key}
                onClick={() => onPlayCard({ playerId: action.playerId, cardInstanceId: option.cardInstanceId })}
              >
                {isPending ? playCardPendingLabel(option) : playCardButtonLabel(option, needsSourceCopyLabel)}
              </ActionCommandButton>
            )
          })}
        </div>
      ) : null}

      {benchOptions.length > 0 ? (
        <div className="mt-2 space-y-1.5">
          {benchOptions.length > 1 ? <BasicBenchChoiceGuide options={benchOptions} /> : null}

          {benchOptions.map(option => {
            const isPending = playBasicToBenchPendingCardId === option.cardInstanceId
            const isPostSearchBenchTarget = postSearchBenchCardInstanceIds.includes(option.cardInstanceId)
            const needsSourceCopyLabel = repeatedBenchLabels.has(option.baseLabel)

            return (
              <ActionCommandButton
                disabled={!canRunAction}
                key={option.key}
                onClick={() => onPlayBasicToBench({ playerId: action.playerId, cardInstanceId: option.cardInstanceId })}
                tone={isPostSearchBenchTarget ? 'primary' : 'secondary'}
              >
                {isPending
                  ? basicBenchPendingLabel(option)
                  : basicBenchButtonLabel(option, needsSourceCopyLabel, isPostSearchBenchTarget)}
              </ActionCommandButton>
            )
          })}
        </div>
      ) : null}

      {evolutionOptions.length > 0 ? (
        <div className="mt-2 space-y-1.5">
          <EvolutionChoiceGuide options={evolutionOptions} />

          {evolutionOptions.map(option => {
            const isPending = evolveFromHandPendingKey === option.key
            const needsSourceCopyLabel = repeatedEvolutionLabels.has(option.baseLabel)

            return (
              <ActionCommandButton
                disabled={!canRunAction}
                key={option.key}
                onClick={() =>
                  onEvolveFromHand({
                    playerId: action.playerId,
                    evolutionCardInstanceId: option.evolutionCardInstanceId,
                    targetCardInstanceId: option.targetCardInstanceId
                  })
                }
              >
                {isPending ? evolutionPendingLabel(option) : evolutionButtonLabel(option, needsSourceCopyLabel)}
              </ActionCommandButton>
            )
          })}
        </div>
      ) : null}

      {action.key === 'attach_energy' && action.sourceCardInstanceIds.length > 0 && action.targetCardInstanceIds.length > 0 ? (
        <div className="mt-2 space-y-1.5">
          {action.sourceCardInstanceIds.flatMap(energyCardInstanceId =>
            action.targetCardInstanceIds.map(targetCardInstanceId => {
              const energyCard = cardsById.get(energyCardInstanceId)
              const targetCard = cardsById.get(targetCardInstanceId)
              const pairKey = attachEnergyPairKey(energyCardInstanceId, targetCardInstanceId)
              const isPending = attachEnergyPendingKey === pairKey

              return (
                <ActionCommandButton
                  disabled={!canRunAction}
                  key={pairKey}
                  onClick={() =>
                    onAttachEnergy({
                      playerId: action.playerId,
                      energyCardInstanceId,
                      targetCardInstanceId
                    })
                  }
                >
                  {isPending
                    ? `Attaching ${energyCard?.name ?? 'Energy'}...`
                    : `Attach ${energyCard?.name ?? formatCardInstanceId(energyCardInstanceId)} to ${
                        targetCard?.name ?? formatCardInstanceId(targetCardInstanceId)
                      }`}
                </ActionCommandButton>
              )
            })
          )}
        </div>
      ) : null}

      {action.key === 'retreat' && action.targetCardInstanceIds.length > 0 ? (
        <div className="mt-2 space-y-1.5">
          {action.targetCardInstanceIds.flatMap(benchCardInstanceId =>
            retreatPaymentOptions(action.sourceCardInstanceIds, action.requiredSourceCount).map(energyCardInstanceIds => {
              const benchCard = cardsById.get(benchCardInstanceId)
              const paymentKey = retreatKey(benchCardInstanceId, energyCardInstanceIds)
              const isPending = retreatPendingKey === paymentKey

              return (
                <ActionCommandButton
                  disabled={!canRunAction}
                  key={paymentKey}
                  onClick={() =>
                    onRetreat({
                      playerId: action.playerId,
                      benchCardInstanceId,
                      energyCardInstanceIds
                    })
                  }
                >
                  {isPending
                    ? `Retreating to ${benchCard?.name ?? 'Bench'}...`
                    : `Retreat to ${benchCard?.name ?? formatCardInstanceId(benchCardInstanceId)}${retreatPaymentLabel(
                        energyCardInstanceIds,
                        cardsById
                      )}`}
                </ActionCommandButton>
              )
            })
          )}
        </div>
      ) : null}

      {action.key === 'choose_replacement_active' && action.targetCardInstanceIds.length > 0 ? (
        <div className="mt-2 space-y-1.5">
          {action.targetCardInstanceIds.map(benchCardInstanceId => {
            const benchCard = cardsById.get(benchCardInstanceId)
            const isPending = chooseReplacementActivePendingCardId === benchCardInstanceId

            return (
              <ActionCommandButton
                disabled={!canRunAction}
                key={benchCardInstanceId}
                onClick={() => onChooseReplacementActive({ playerId: action.playerId, benchCardInstanceId })}
                tone="primary"
              >
                {isPending
                  ? `Promoting ${benchCard?.name ?? 'Bench'}...`
                  : `Promote ${benchCard?.name ?? formatCardInstanceId(benchCardInstanceId)} to Active`}
              </ActionCommandButton>
            )
          })}
        </div>
      ) : null}

      {action.key === 'declare_attack' && action.attackId ? (
        <ActionCommandButton
          className="mt-2"
          disabled={!canRunAction}
          onClick={() => onDeclareAttack({ playerId: action.playerId, attackId: action.attackId! })}
          tone="primary"
        >
          {declareAttackPendingKey === attackKey(action.playerId, action.attackId)
            ? `Declaring ${action.attackName ?? 'attack'}...`
            : `${postSearchBattleAttackIds.includes(action.attackId) ? 'Attack after search — ' : ''}Declare ${
                action.attackName ?? formatAttackId(action.attackId)
              }${attackCostLabel(action.attackCost)}${attackDamageLabel(action.attackDamage)}`}
        </ActionCommandButton>
      ) : null}

      {action.key === 'end_turn' ? (
        <ActionCommandButton
          className="mt-2"
          disabled={!canRunAction}
          onClick={() => onEndTurn({ playerId: action.playerId })}
          tone="primary"
        >
          {endTurnPendingPlayerId === action.playerId
            ? `Ending ${formatPlayerId(action.playerId)}'s turn...`
            : `${isPostSearchEndTurnAction ? 'Pass after search — ' : ''}End ${formatPlayerId(action.playerId)}'s turn`}
        </ActionCommandButton>
      ) : null}
    </li>
  )
}

function BasicBenchChoiceGuide({ options }: { options: BasicBenchCommandOption[] }) {
  const duplicatedBaseLabelCount = repeatedBasicBenchBaseLabels(options).size
  const detail = duplicatedBaseLabelCount > 0
    ? 'Repeated Basic names are separate cards in hand. Buttons include the hand slot so the chosen copy is unambiguous.'
    : options.length > 1
      ? 'Choose which Basic Pokémon moves from hand to the next Bench space. The engine uses the exact card you choose.'
      : 'One Basic Pokémon can move from hand to the next Bench space.'

  return (
    <div className="rounded-lg border border-emerald-200 bg-emerald-50/70 px-3 py-2 text-xs leading-5 text-emerald-950">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-semibold uppercase tracking-[0.14em] text-emerald-800">Basic Bench choice</p>
          <p className="mt-0.5 text-emerald-900/80">{detail}</p>
        </div>
        <StatusBadge tone="active">
          {options.length} {options.length === 1 ? 'choice' : 'choices'}
        </StatusBadge>
      </div>
    </div>
  )
}

function PlayCardChoiceGuide({ options }: { options: PlayCardCommandOption[] }) {
  const duplicatedBaseLabelCount = repeatedPlayCardBaseLabels(options).size
  const detail = duplicatedBaseLabelCount > 0
    ? 'Repeated playable names are separate cards in hand. Buttons include the hand slot so the chosen copy is unambiguous.'
    : 'Choose which engine-defined card to play. The engine uses the exact hand card you choose.'

  return (
    <div className="rounded-lg border border-emerald-200 bg-emerald-50/70 px-3 py-2 text-xs leading-5 text-emerald-950">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-semibold uppercase tracking-[0.14em] text-emerald-800">Playable card choice</p>
          <p className="mt-0.5 text-emerald-900/80">{detail}</p>
        </div>
        <StatusBadge tone="active">
          {options.length} {options.length === 1 ? 'choice' : 'choices'}
        </StatusBadge>
      </div>
    </div>
  )
}

function EvolutionChoiceGuide({ options }: { options: EvolutionCommandOption[] }) {
  const targetCount = new Set(options.map(option => option.targetCardInstanceId)).size
  const sourceCount = new Set(options.map(option => option.evolutionCardInstanceId)).size
  const duplicatedBaseLabelCount = repeatedEvolutionBaseLabels(options).size
  const detail = duplicatedBaseLabelCount > 0
    ? sourceCount === 1 && targetCount > 1
      ? `The same hand copy can evolve ${evolutionTargetCountLabel(
          options
        )}. Buttons name each target location so the chosen stack is unambiguous.`
      : 'Repeated names are separate legal choices. Buttons now show the in-play target location and, when needed, the hand copy so the chosen evolution is unambiguous.'
    : targetCount > 1
      ? 'Choose which in-play Pokémon evolves. Buttons name Active or Bench position so identical Basics stay distinguishable.'
      : sourceCount > 1
        ? 'Multiple evolution cards can evolve the same target. Choose the hand copy you want to play.'
        : 'One legal evolution is ready from the current hand and board.'

  return (
    <div className="rounded-lg border border-violet-200 bg-violet-50/70 px-3 py-2 text-xs leading-5 text-violet-950">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-semibold uppercase tracking-[0.14em] text-violet-800">Evolution choice</p>
          <p className="mt-0.5 text-violet-900/80">{detail}</p>
        </div>
        <StatusBadge tone="warning">
          {options.length} {options.length === 1 ? 'choice' : 'choices'}
        </StatusBadge>
      </div>
    </div>
  )
}

function ActionCommandButton({
  children,
  className = '',
  disabled,
  onClick,
  tone = 'secondary'
}: {
  children: string
  className?: string
  disabled: boolean
  onClick: () => void
  tone?: 'primary' | 'secondary'
}) {
  const baseClassName =
    'w-full rounded-lg px-3 py-2 text-left text-sm transition focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:bg-stone-100 disabled:text-stone-400 disabled:shadow-none'
  const toneClassName =
    tone === 'primary'
      ? 'border border-emerald-700 bg-emerald-700 font-semibold text-stone-50 shadow-sm shadow-emerald-900/10 hover:border-emerald-800 hover:bg-emerald-800 focus:ring-emerald-600'
      : 'border border-stone-300 bg-white font-medium text-stone-800 hover:border-emerald-500 hover:bg-emerald-50 hover:text-emerald-900 focus:ring-emerald-500'

  return (
    <button className={[className, baseClassName, toneClassName].filter(Boolean).join(' ')} disabled={disabled} onClick={onClick} type="button">
      {children}
    </button>
  )
}

function actionSurfaceClassName(action: ActionAffordance) {
  switch (action.key) {
    case 'choose_replacement_active':
      return 'border-amber-200 bg-amber-50/80'
    case 'declare_attack':
      return 'border-emerald-200 bg-emerald-50/70'
    default:
      return 'border-stone-200 bg-white'
  }
}

function actionSummary(action: ActionAffordance) {
  switch (action.key) {
    case 'choose_prompt':
      return 'Resolve the engine prompt before this game can advance.'
    case 'choose_replacement_active':
      return `${actionCountLabel(action.targetCardInstanceIds.length, 'Bench candidate')} can become Active.`
    case 'play_card':
      return `${actionCountLabel(action.sourceCardInstanceIds.length, 'card')} from hand can be played.`
    case 'play_basic_to_bench':
      return `${actionCountLabel(action.sourceCardInstanceIds.length, 'Basic Pokémon', 'Basic Pokémon')} can move to Bench.`
    case 'evolve_from_hand':
      return `${actionCountLabel(action.sourceCardInstanceIds.length, 'evolution card')} can evolve ${actionCountLabel(
        action.targetCardInstanceIds.length,
        'target'
      )}.`
    case 'attach_energy':
      return `${actionCountLabel(action.sourceCardInstanceIds.length, 'Energy card')} can attach to ${actionCountLabel(
        action.targetCardInstanceIds.length,
        'target'
      )}.`
    case 'retreat':
      return `${actionCountLabel(action.targetCardInstanceIds.length, 'Bench target')} with ${retreatCostSummary(
        action.requiredSourceCount
      )}.`
    case 'declare_attack':
      return `${action.attackName ?? (action.attackId ? formatAttackId(action.attackId) : 'Attack')}: ${attackCostSummary(
        action.attackCost
      )}, ${attackDamageSummary(action.attackDamage)}.`
    case 'end_turn':
      return `End the action window for ${formatPlayerId(action.playerId)}.`
    default:
      return `${formatEventType(action.kind)} command exposed by the current engine state.`
  }
}

function evolutionCommandOptions(
  action: ActionAffordance,
  cardsById: Map<string, CardSummary>
): EvolutionCommandOption[] {
  if (action.key !== 'evolve_from_hand') {
    return []
  }

  return action.sourceCardInstanceIds.flatMap(evolutionCardInstanceId =>
    action.targetCardInstanceIds.map(targetCardInstanceId => {
      const evolutionCard = cardsById.get(evolutionCardInstanceId)
      const targetCard = cardsById.get(targetCardInstanceId)

      return {
        key: evolveKey(evolutionCardInstanceId, targetCardInstanceId),
        evolutionCardInstanceId,
        targetCardInstanceId,
        evolutionCard,
        targetCard,
        baseLabel: evolutionBaseLabel(evolutionCard, evolutionCardInstanceId, targetCard, targetCardInstanceId)
      }
    })
  )
}

function basicBenchCommandOptions(
  action: ActionAffordance,
  cardsById: Map<string, CardSummary>
): BasicBenchCommandOption[] {
  if (action.key !== 'play_basic_to_bench') {
    return []
  }

  return action.sourceCardInstanceIds.map(cardInstanceId => {
    const card = cardsById.get(cardInstanceId)

    return {
      key: cardInstanceId,
      cardInstanceId,
      card,
      baseLabel: card?.name ?? formatCardInstanceId(cardInstanceId)
    }
  })
}

function playCardCommandOptions(
  action: ActionAffordance,
  cardsById: Map<string, CardSummary>
): PlayCardCommandOption[] {
  if (action.key !== 'play_card') {
    return []
  }

  return action.sourceCardInstanceIds.map(cardInstanceId => {
    const card = cardsById.get(cardInstanceId)

    return {
      key: cardInstanceId,
      cardInstanceId,
      card,
      baseLabel: card?.name ?? formatCardInstanceId(cardInstanceId)
    }
  })
}

function repeatedBasicBenchBaseLabels(options: BasicBenchCommandOption[]) {
  const labelCounts = new Map<string, number>()

  for (const option of options) {
    labelCounts.set(option.baseLabel, (labelCounts.get(option.baseLabel) ?? 0) + 1)
  }

  return new Set([...labelCounts.entries()].filter(([, count]) => count > 1).map(([label]) => label))
}

function repeatedPlayCardBaseLabels(options: PlayCardCommandOption[]) {
  const labelCounts = new Map<string, number>()

  for (const option of options) {
    labelCounts.set(option.baseLabel, (labelCounts.get(option.baseLabel) ?? 0) + 1)
  }

  return new Set([...labelCounts.entries()].filter(([, count]) => count > 1).map(([label]) => label))
}

function playCardPendingLabel(option: PlayCardCommandOption) {
  return `Playing ${option.card?.name ?? 'card'}...`
}

function playCardButtonLabel(option: PlayCardCommandOption, includeSourceCopyLabel: boolean) {
  const cardName = option.card?.name ?? formatCardInstanceId(option.cardInstanceId)
  const sourceCopyLabel = includeSourceCopyLabel ? ` from ${cardLocationLabel(option.card, 'hand')}` : ''

  return `Play ${cardName}${sourceCopyLabel}`
}

function basicBenchPendingLabel(option: BasicBenchCommandOption) {
  return `Benching ${option.card?.name ?? 'Pokémon'}...`
}

function basicBenchButtonLabel(
  option: BasicBenchCommandOption,
  includeSourceCopyLabel: boolean,
  isPostSearchBenchTarget: boolean
) {
  const cardName = option.card?.name ?? formatCardInstanceId(option.cardInstanceId)
  const sourceCopyLabel = includeSourceCopyLabel ? ` from ${cardLocationLabel(option.card, 'hand')}` : ''

  return `${isPostSearchBenchTarget ? 'Bench searched ' : 'Bench '}${cardName}${sourceCopyLabel}`
}

function repeatedEvolutionBaseLabels(options: EvolutionCommandOption[]) {
  const labelCounts = new Map<string, number>()

  for (const option of options) {
    labelCounts.set(option.baseLabel, (labelCounts.get(option.baseLabel) ?? 0) + 1)
  }

  return new Set([...labelCounts.entries()].filter(([, count]) => count > 1).map(([label]) => label))
}

function evolutionBaseLabel(
  evolutionCard: CardSummary | undefined,
  evolutionCardInstanceId: string,
  targetCard: CardSummary | undefined,
  targetCardInstanceId: string
) {
  return `${targetCard?.name ?? formatCardInstanceId(targetCardInstanceId)}:${
    evolutionCard?.name ?? formatCardInstanceId(evolutionCardInstanceId)
  }`
}

function evolutionPendingLabel(option: EvolutionCommandOption) {
  return `Evolving ${evolutionTargetLabel(option.targetCard, option.targetCardInstanceId)}...`
}

function evolutionButtonLabel(option: EvolutionCommandOption, includeSourceCopyLabel: boolean) {
  const sourceName = option.evolutionCard?.name ?? formatCardInstanceId(option.evolutionCardInstanceId)
  const sourceCopyLabel = includeSourceCopyLabel ? ` from ${cardLocationLabel(option.evolutionCard, 'hand')}` : ''

  return `Evolve ${evolutionTargetLabel(option.targetCard, option.targetCardInstanceId)} into ${sourceName}${sourceCopyLabel}`
}

function evolutionTargetLabel(card: CardSummary | undefined, cardInstanceId: string) {
  if (!card) {
    return formatCardInstanceId(cardInstanceId)
  }

  return `${cardLocationLabel(card, 'in play')} ${card.name}`
}

function cardLocationLabel(card: CardSummary | undefined, fallback: string) {
  if (!card) {
    return fallback
  }

  if (card.zone === 'active') {
    return 'Active'
  }

  if (card.zone === 'bench') {
    return Number.isFinite(card.position) ? `Bench ${card.position + 1}` : 'Bench'
  }

  if (card.zone === 'hand') {
    return Number.isFinite(card.position) ? `hand slot ${card.position + 1}` : 'hand'
  }

  return formatEventType(card.zone)
}

function actionCountLabel(count: number, singular: string, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`
}

function retreatCostSummary(requiredSourceCount: number) {
  if (requiredSourceCount === 0) {
    return 'free Retreat Cost'
  }

  return `${requiredSourceCount} Energy payment${requiredSourceCount === 1 ? '' : 's'}`
}

function attackCostSummary(attackCost: string[]) {
  return attackCost.length > 0 ? `${attackCost.length} Energy cost` : 'no Energy cost'
}

function attackDamageSummary(attackDamage: string | null) {
  return attackDamage ? `${attackDamage} damage` : 'effect damage'
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

function actionRenderEntries(actions: ActionAffordance[], cardsById: Map<string, CardSummary>): ActionRenderEntry[] {
  const entries: ActionRenderEntry[] = []
  let pendingBasicBenchActions: ActionAffordance[] = []
  let pendingEvolutionActions: ActionAffordance[] = []

  function flushBasicBenchActions() {
    const entry = mergedBasicBenchRenderEntry(pendingBasicBenchActions, cardsById)

    if (entry) {
      entries.push(entry)
    }

    pendingBasicBenchActions = []
  }

  function flushEvolutionActions() {
    const entry = mergedEvolutionRenderEntry(pendingEvolutionActions, cardsById)

    if (entry) {
      entries.push(entry)
    }

    pendingEvolutionActions = []
  }

  for (const action of actions) {
    if (action.key === 'play_basic_to_bench') {
      flushEvolutionActions()
      pendingBasicBenchActions.push(action)
    } else if (action.key === 'evolve_from_hand') {
      flushBasicBenchActions()
      pendingEvolutionActions.push(action)
    } else {
      flushBasicBenchActions()
      flushEvolutionActions()
      entries.push({ key: actionKey(action), action })
    }
  }

  flushBasicBenchActions()
  flushEvolutionActions()

  return entries
}

function mergedBasicBenchRenderEntry(
  actions: ActionAffordance[],
  cardsById: Map<string, CardSummary>
): ActionRenderEntry | null {
  const firstAction = actions[0]

  if (!firstAction) {
    return null
  }

  const options = uniqueBasicBenchOptions(actions.flatMap(action => basicBenchCommandOptions(action, cardsById)))
  const sourceCardInstanceIds = uniqueStrings(options.map(option => option.cardInstanceId))
  const mergedAction: ActionAffordance = {
    ...firstAction,
    sourceCardInstanceIds,
    targetCardInstanceIds: uniqueStrings(actions.flatMap(action => action.targetCardInstanceIds)),
    promptIds: uniqueStrings(actions.flatMap(action => action.promptIds)),
    choiceKeys: uniqueStrings(actions.flatMap(action => action.choiceKeys))
  }

  return {
    key: ['play_basic_to_bench', firstAction.playerId, ...sourceCardInstanceIds].join(':'),
    action: mergedAction,
    benchOptions: options
  }
}

function mergedEvolutionRenderEntry(
  actions: ActionAffordance[],
  cardsById: Map<string, CardSummary>
): ActionRenderEntry | null {
  const firstAction = actions[0]

  if (!firstAction) {
    return null
  }

  const options = uniqueEvolutionOptions(actions.flatMap(action => evolutionCommandOptions(action, cardsById)))
  const sourceCardInstanceIds = uniqueStrings(options.map(option => option.evolutionCardInstanceId))
  const targetCardInstanceIds = uniqueStrings(options.map(option => option.targetCardInstanceId))
  const mergedAction: ActionAffordance = {
    ...firstAction,
    sourceCardInstanceIds,
    targetCardInstanceIds,
    promptIds: uniqueStrings(actions.flatMap(action => action.promptIds)),
    choiceKeys: uniqueStrings(actions.flatMap(action => action.choiceKeys))
  }

  return {
    key: ['evolve_from_hand', firstAction.playerId, ...options.map(option => option.key)].join(':'),
    action: mergedAction,
    evolutionOptions: options
  }
}

function uniqueEvolutionOptions(options: EvolutionCommandOption[]) {
  const optionsByKey = new Map<string, EvolutionCommandOption>()

  for (const option of options) {
    optionsByKey.set(option.key, option)
  }

  return [...optionsByKey.values()]
}

function uniqueBasicBenchOptions(options: BasicBenchCommandOption[]) {
  const optionsByKey = new Map<string, BasicBenchCommandOption>()

  for (const option of options) {
    optionsByKey.set(option.key, option)
  }

  return [...optionsByKey.values()]
}

function uniquePlayCardOptions(options: PlayCardCommandOption[]) {
  const optionsByKey = new Map<string, PlayCardCommandOption>()

  for (const option of options) {
    optionsByKey.set(option.key, option)
  }

  return [...optionsByKey.values()]
}

function uniqueStrings(values: string[]) {
  return [...new Set(values)]
}

function groupActionAffordances(actions: ActionAffordance[]): ActionGroup[] {
  const groupedActions = new Map<ActionGroupId, ActionAffordance[]>()

  for (const action of actions) {
    const groupId = actionGroupId(action)
    const groupActions = groupedActions.get(groupId) ?? []

    groupActions.push(action)
    groupedActions.set(groupId, groupActions)
  }

  return ACTION_GROUPS.map(group => ({
    ...group,
    actions: groupedActions.get(group.id) ?? []
  })).filter(group => group.actions.length > 0)
}

function actionGroupId(action: ActionAffordance): ActionGroupId {
  switch (action.key) {
    case 'choose_prompt':
    case 'choose_replacement_active':
      return 'required'
    case 'play_card':
    case 'play_basic_to_bench':
    case 'evolve_from_hand':
    case 'attach_energy':
      return 'hand'
    case 'retreat':
    case 'declare_attack':
      return 'battle'
    case 'end_turn':
      return 'turn'
    default:
      return 'other'
  }
}

function actionGroupBadgeTone(groupId: ActionGroupId, isPrimaryGroup: boolean): 'active' | 'neutral' | 'warning' {
  if (groupId === 'required') {
    return 'warning'
  }

  return isPrimaryGroup ? 'active' : 'neutral'
}

function BattlefieldPanel({
  activePlayerId,
  currentTurn,
  deckNamesByKey,
  players,
  stadium,
  viewerPlayerId
}: {
  activePlayerId: string
  currentTurn: GameState['currentTurn']
  deckNamesByKey: Map<string, string>
  players: PlayerView[]
  stadium: CardSummary | null
  viewerPlayerId: PlayerId
}) {
  const viewerPlayer = players.find(player => player.playerId === viewerPlayerId)
  const opponentPlayer = players.find(player => player.playerId !== viewerPlayerId)
  const topPlayer = opponentPlayer ?? players[0]
  const bottomPlayer = viewerPlayer ?? players.find(player => player.playerId !== topPlayer?.playerId)
  const turnLabel = currentTurn ? `Turn ${currentTurn.turnNumber}, ${formatEventType(currentTurn.status)}` : 'No turn'

  return (
    <Panel
      title="Battlefield"
      trailing={<StatusBadge tone={currentTurn ? 'active' : 'neutral'}>{turnLabel}</StatusBadge>}
    >
      <div className="rounded-[2rem] border border-stone-300 bg-[oklch(0.965_0.006_155)] p-3 shadow-inner shadow-stone-300/50 sm:p-4">
        {topPlayer ? (
          <PlayerBattleSide
            activePlayerId={activePlayerId}
            deckName={deckNamesByKey.get(topPlayer.deckKey)}
            isViewer={topPlayer.playerId === viewerPlayerId}
            player={topPlayer}
            side="top"
          />
        ) : null}

        <div className="my-3 grid items-center gap-3 sm:grid-cols-[1fr_auto_1fr]">
          <div className="hidden h-px bg-stone-300 sm:block" />
          <div className="rounded-full border border-stone-300 bg-[oklch(0.985_0.004_155)] px-4 py-2 text-center text-xs font-medium text-stone-600 shadow-sm shadow-stone-300/40">
            {stadium ? `Stadium: ${stadium.name}` : 'No Stadium in play'}
          </div>
          <div className="hidden h-px bg-stone-300 sm:block" />
        </div>

        {bottomPlayer ? (
          <PlayerBattleSide
            activePlayerId={activePlayerId}
            deckName={deckNamesByKey.get(bottomPlayer.deckKey)}
            isViewer={bottomPlayer.playerId === viewerPlayerId}
            player={bottomPlayer}
            side="bottom"
          />
        ) : null}
      </div>
    </Panel>
  )
}

function PlayerBattleSide({
  activePlayerId,
  deckName,
  isViewer,
  player,
  side
}: {
  activePlayerId: string
  deckName?: string
  isViewer: boolean
  player: PlayerView
  side: 'top' | 'bottom'
}) {
  const isActivePlayer = player.playerId === activePlayerId
  const activeZone = (
    <BattleZone
      cards={player.active ? [player.active] : []}
      emptyLabel="No Active Pokémon"
      title="Active Spot"
      variant="active"
    />
  )
  const benchZone = <BattleZone cards={player.bench} emptyLabel="Bench is empty" title="Bench" variant="bench" />

  return (
    <section
      className={`rounded-[1.5rem] border p-3 sm:p-4 ${
        isViewer
          ? 'border-emerald-300 bg-[oklch(0.985_0.012_155)]'
          : 'border-stone-300 bg-[oklch(0.978_0.006_155)]'
      }`}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="text-base font-semibold tracking-tight text-stone-950">{formatPlayerId(player.playerId)}</h3>
            {isViewer ? <StatusBadge tone="active">viewer</StatusBadge> : <StatusBadge>opponent</StatusBadge>}
            {isActivePlayer ? <StatusBadge tone="warning">turn owner</StatusBadge> : null}
          </div>
          <p className="mt-1 truncate text-sm text-stone-600">{deckName ?? player.deckKey}</p>
        </div>
        <p className="font-mono text-xs text-stone-500">{player.deckKey}</p>
      </div>

      <div className="mt-4 grid gap-3 xl:grid-cols-[8rem_minmax(0,1fr)_minmax(12rem,18rem)]">
        <div className="grid grid-cols-4 gap-2 xl:grid-cols-1">
          <ZoneStack label="Deck" value={player.deckCount} />
          <ZoneStack label="Prizes" value={player.prizeCount} />
          <ZoneStack label="Discard" value={player.discardCount} />
          <ZoneStack label="Hand" value={player.handCount} tone={isViewer ? 'active' : 'hidden'} />
        </div>

        <div className="space-y-3">
          {side === 'top' ? (
            <>
              {benchZone}
              {activeZone}
            </>
          ) : (
            <>
              {activeZone}
              {benchZone}
            </>
          )}
        </div>

        <PrivateHandZone isViewer={isViewer} player={player} />
      </div>
    </section>
  )
}

function BattleZone({
  cards,
  emptyLabel,
  title,
  variant
}: {
  cards: CardSummary[]
  emptyLabel: string
  title: string
  variant: 'active' | 'bench'
}) {
  const cardVariant = variant === 'active' ? 'active' : 'compact'

  return (
    <div className="rounded-2xl border border-stone-300 bg-[oklch(0.99_0.004_155)] p-3">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h4 className="text-xs font-semibold uppercase tracking-[0.16em] text-stone-500">{title}</h4>
        <span className="rounded-full bg-stone-200 px-2 py-0.5 text-xs font-medium text-stone-600">
          {cards.length}
        </span>
      </div>

      {cards.length > 0 ? (
        <div
          className={
            variant === 'active'
              ? 'mx-auto grid max-w-sm gap-2'
              : 'grid gap-2 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5'
          }
        >
          {cards.map(card => (
            <CardPill card={card} key={card.id} variant={cardVariant} />
          ))}
        </div>
      ) : (
        <p className="rounded-xl border border-dashed border-stone-300 px-3 py-5 text-center text-sm text-stone-500">
          {emptyLabel}
        </p>
      )}
    </div>
  )
}

function ZoneStack({
  label,
  tone = 'neutral',
  value
}: {
  label: string
  tone?: 'active' | 'hidden' | 'neutral'
  value: number
}) {
  const toneClassName =
    tone === 'active'
      ? 'border-emerald-200 bg-emerald-50 text-emerald-950'
      : tone === 'hidden'
        ? 'border-stone-300 bg-stone-100 text-stone-600'
        : 'border-stone-200 bg-stone-50 text-stone-950'

  return (
    <div className={`rounded-2xl border px-3 py-2.5 text-center ${toneClassName}`}>
      <p className="text-xl font-semibold tabular-nums">{value}</p>
      <p className="mt-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.14em] opacity-70">{label}</p>
    </div>
  )
}

function PrivateHandZone({ isViewer, player }: { isViewer: boolean; player: PlayerView }) {
  return (
    <div className="rounded-2xl border border-stone-300 bg-[oklch(0.99_0.004_155)] p-3">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h4 className="text-xs font-semibold uppercase tracking-[0.16em] text-stone-500">
          {isViewer ? 'Your hand' : 'Opponent hand'}
        </h4>
        <span className="rounded-full bg-stone-200 px-2 py-0.5 text-xs font-medium text-stone-600">
          {player.handCount}
        </span>
      </div>

      {isViewer ? (
        player.hand.length > 0 ? (
          <div className="max-h-80 space-y-2 overflow-auto pr-1">
            {player.hand.map(card => (
              <CardPill card={card} key={card.id} variant="hand" />
            ))}
          </div>
        ) : (
          <p className="rounded-xl border border-dashed border-stone-300 px-3 py-5 text-center text-sm text-stone-500">
            Your hand is empty.
          </p>
        )
      ) : (
        <div className="rounded-xl border border-dashed border-stone-300 bg-stone-100 px-3 py-5 text-center text-sm text-stone-500">
          {player.handCount} hidden {player.handCount === 1 ? 'card' : 'cards'}
        </div>
      )}
    </div>
  )
}

function SessionConnectionSummary({
  gameId,
  viewerPlayerId,
  isRefreshing,
  hasViewerMismatch
}: {
  gameId: string
  viewerPlayerId: PlayerId
  isRefreshing: boolean
  hasViewerMismatch: boolean
}) {
  const statusLabel = !gameId ? 'not connected' : hasViewerMismatch ? 'seat guard' : isRefreshing ? 'refreshing' : 'connected'
  const statusTone = !gameId ? 'neutral' : hasViewerMismatch || isRefreshing ? 'warning' : 'active'

  return (
    <div className="rounded-2xl border border-stone-200 bg-stone-50 p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-stone-950">Table seat</p>
          <p className="mt-1 text-xs leading-5 text-stone-500">Local browser storage keeps the table ID and tab seat separate.</p>
        </div>
        <StatusBadge tone={statusTone}>{statusLabel}</StatusBadge>
      </div>
      <div className="mt-3 space-y-2">
        <StateRow label="Game" value={gameId ? formatGameId(gameId) : 'Create or paste an ID'} />
        <StateRow label="Viewer" value={`${formatPlayerId(viewerPlayerId)} in this tab`} />
      </div>
    </div>
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
  playerId,
  value,
  decks,
  onChange
}: {
  label: string
  playerId: PlayerId
  value: string
  decks: SupportedDeck[]
  onChange: (value: string) => void
}) {
  const selectedDeck = decks.find(deck => deck.deckKey === value) ?? null

  return (
    <div className="rounded-2xl border border-stone-200 bg-stone-50 p-3">
      <label className="block space-y-2">
        <span className="flex items-center justify-between gap-3">
          <span className="text-sm font-medium text-stone-800">{label}</span>
          <StatusBadge tone={selectedDeck ? 'active' : 'neutral'}>{formatPlayerId(playerId)}</StatusBadge>
        </span>
        <select
          className="w-full rounded-xl border border-stone-300 bg-[oklch(0.995_0.004_155)] px-3 py-2 text-sm text-stone-950 outline-none transition focus:border-emerald-600 focus:ring-2 focus:ring-emerald-100 disabled:cursor-not-allowed disabled:text-stone-400"
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

      {selectedDeck ? (
        <div className="mt-3 border-t border-stone-200 pt-3">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-stone-950">{selectedDeck.name}</p>
              <p className="mt-1 font-mono text-xs text-stone-500">{selectedDeck.deckKey}</p>
            </div>
            <a
              className="shrink-0 text-xs font-medium text-emerald-700 hover:text-emerald-900"
              href={selectedDeck.sourceUrl}
              rel="noreferrer"
              target="_blank"
            >
              Source
            </a>
          </div>
          <div className="mt-3 flex flex-wrap gap-1.5 text-xs font-medium text-stone-600">
            <span className="rounded-full bg-stone-100 px-2 py-1">{selectedDeck.cardCount} cards</span>
            <span className="rounded-full bg-stone-100 px-2 py-1">{selectedDeck.uniqueCardCount} unique</span>
          </div>
        </div>
      ) : (
        <p className="mt-3 border-t border-stone-200 pt-3 text-xs leading-5 text-stone-500">
          Choose a fixture after the engine catalog loads.
        </p>
      )}
    </div>
  )
}

function FirstRunSetupGuide({
  deckCount,
  hasGame,
  selectedPlayerOneDeck,
  selectedPlayerTwoDeck,
  viewerPlayerId
}: {
  deckCount: number
  hasGame: boolean
  selectedPlayerOneDeck: SupportedDeck | null
  selectedPlayerTwoDeck: SupportedDeck | null
  viewerPlayerId: PlayerId
}) {
  const loadoutsReady = Boolean(selectedPlayerOneDeck && selectedPlayerTwoDeck)
  const loadoutDetail =
    selectedPlayerOneDeck && selectedPlayerTwoDeck
      ? `${selectedPlayerOneDeck.name} vs ${selectedPlayerTwoDeck.name}`
      : deckCount > 0
        ? 'Choose one supported fixture for each player.'
        : 'Waiting for the engine-owned fixture catalog.'

  return (
    <section className="rounded-2xl border border-emerald-100 bg-[oklch(0.982_0.015_155)] p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-stone-950">First table checklist</p>
          <p className="mt-1 text-xs leading-5 text-stone-600">
            Create the board here, then run setup from the Game flow rail after the board loads.
          </p>
        </div>
        <StatusBadge tone={hasGame ? 'active' : loadoutsReady ? 'warning' : 'neutral'}>
          {hasGame ? 'board linked' : loadoutsReady ? 'ready' : 'setup'}
        </StatusBadge>
      </div>

      <div className="mt-3 space-y-2">
        <SetupGuideRow
          detail={loadoutDetail}
          number="1"
          state={loadoutsReady ? 'ready' : 'needed'}
          title="Pick player loadouts"
        />
        <SetupGuideRow
          detail={hasGame ? 'This tab is connected to a persisted game.' : 'Create a board when both loadouts are ready.'}
          number="2"
          state={hasGame ? 'done' : loadoutsReady ? 'next' : 'needed'}
          title="Create the game board"
        />
        <SetupGuideRow
          detail="Use Game flow for opening hands, Active choices, Prizes, and the first turn."
          number="3"
          state={hasGame ? 'next' : 'needed'}
          title="Run table setup"
        />
        <SetupGuideRow
          detail={`This tab is ${formatPlayerId(viewerPlayerId)}. Open another tab and select the other seat.`}
          number="4"
          state={hasGame ? 'ready' : 'needed'}
          title="Seat the second player"
        />
      </div>
    </section>
  )
}

function SetupGuideRow({
  number,
  title,
  detail,
  state
}: {
  number: string
  title: string
  detail: string
  state: SetupGuideState
}) {
  const badgeTone = state === 'done' || state === 'ready' ? 'active' : state === 'next' ? 'warning' : 'neutral'
  const badgeLabel = state === 'done' ? 'done' : state === 'ready' ? 'ready' : state === 'next' ? 'next' : 'needed'

  return (
    <div className="flex items-start gap-3 rounded-xl border border-stone-200 bg-[oklch(0.995_0.004_155)] px-3 py-2.5">
      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-stone-100 text-xs font-semibold text-stone-700">
        {number}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-center justify-between gap-2">
          <p className="text-sm font-medium text-stone-950">{title}</p>
          <StatusBadge tone={badgeTone}>{badgeLabel}</StatusBadge>
        </div>
        <p className="mt-1 text-xs leading-5 text-stone-500">{detail}</p>
      </div>
    </div>
  )
}

function SupportedDeckCatalog({
  decks,
  playerOneDeckKey,
  playerTwoDeckKey
}: {
  decks: SupportedDeck[]
  playerOneDeckKey: string
  playerTwoDeckKey: string
}) {
  if (decks.length === 0) {
    return (
      <p className="rounded-xl border border-stone-200 bg-stone-50 px-3 py-2 text-sm leading-6 text-stone-600">
        Supported fixture metadata appears here after the engine catalog loads.
      </p>
    )
  }

  return (
    <div className="space-y-3">
      <p className="text-sm leading-6 text-stone-600">
        Engine-owned deck fixtures for browser playtests. Selected fixtures are marked with their current seat.
      </p>
      {decks.map(deck => {
        const selectedSeats = [
          deck.deckKey === playerOneDeckKey ? 'P1' : null,
          deck.deckKey === playerTwoDeckKey ? 'P2' : null
        ].filter(Boolean)

        return (
          <div className="rounded-xl border border-stone-200 bg-stone-50 p-3" key={deck.deckKey}>
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-stone-950">{deck.name}</p>
                <p className="mt-1 font-mono text-xs text-stone-500">{deck.deckKey}</p>
              </div>
              {selectedSeats.length > 0 ? (
                <div className="flex shrink-0 gap-1">
                  {selectedSeats.map(seat => (
                    <StatusBadge key={seat} tone="active">
                      {seat}
                    </StatusBadge>
                  ))}
                </div>
              ) : (
                <span className="shrink-0 text-xs text-stone-500">{deck.uniqueCardCount} unique</span>
              )}
            </div>
            <div className="mt-3 flex items-center justify-between gap-3 text-xs text-stone-500">
              <span>{deck.cardCount} cards</span>
              <a
                className="font-medium text-emerald-700 hover:text-emerald-900"
                href={deck.sourceUrl}
                rel="noreferrer"
                target="_blank"
              >
                Source decklist
              </a>
            </div>
          </div>
        )
      })}
    </div>
  )
}

function CardPill({ card, variant = 'default' }: { card: CardSummary; variant?: 'active' | 'compact' | 'default' | 'hand' }) {
  const attachedCards = card.attachedCards ?? []
  const evolutionStackCards = evolutionStackForCard(card, attachedCards)
  const evolutionStackCardIds = new Set(evolutionStackCards.map(attachedCard => attachedCard.id))
  const regularAttachedCards = attachedCards.filter(attachedCard => !evolutionStackCardIds.has(attachedCard.id))
  const cardClassName =
    variant === 'active'
      ? 'rounded-2xl border border-emerald-200 bg-[oklch(0.985_0.01_155)] p-4 shadow-sm shadow-emerald-200/60'
      : variant === 'compact'
        ? 'rounded-xl border border-stone-200 bg-stone-50 p-2.5'
        : variant === 'hand'
          ? 'rounded-xl border border-stone-200 bg-[oklch(0.992_0.004_155)] p-2.5'
          : 'rounded-xl border border-stone-200 bg-stone-50 p-3'
  const titleClassName = variant === 'active' ? 'text-base' : 'text-sm'

  return (
    <div className={cardClassName}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className={`truncate font-medium text-stone-950 ${titleClassName}`}>{card.name}</p>
          <p className="mt-1 font-mono text-xs text-stone-500">{card.cardId}</p>
        </div>
        {card.damage > 0 ? <StatusBadge tone="warning">{card.damage} dmg</StatusBadge> : null}
      </div>
      <div className="mt-2 flex flex-wrap gap-1.5 text-xs text-stone-500">
        {card.category ? <span>{card.category}</span> : null}
        {card.stage ? <span>{card.stage}</span> : null}
        {card.status ? <span>{card.status}</span> : null}
      </div>

      {evolutionStackCards.length > 0 ? (
        <AttachedCardGroup cards={evolutionStackCards} title="Evolution stack" titleSuffix="evolved under" />
      ) : null}

      {regularAttachedCards.length > 0 ? (
        <AttachedCardGroup cards={regularAttachedCards} title="Attached cards" titleSuffix="attached" />
      ) : null}
    </div>
  )
}

function evolutionStackForCard(card: CardSummary, attachedCards: CardSummary[]) {
  const attachedCardsById = new Map(attachedCards.map(attachedCard => [attachedCard.id, attachedCard]))
  const stackCards: CardSummary[] = []
  const visitedCardIds = new Set<string>()
  let nextCardId = card.evolvesFromCardInstanceId

  while (nextCardId && !visitedCardIds.has(nextCardId)) {
    visitedCardIds.add(nextCardId)
    const stackCard = attachedCardsById.get(nextCardId)

    if (!stackCard) {
      break
    }

    stackCards.push(stackCard)
    nextCardId = stackCard.evolvesFromCardInstanceId
  }

  return stackCards
}

function AttachedCardGroup({ cards, title, titleSuffix }: { cards: CardSummary[]; title: string; titleSuffix: string }) {
  return (
    <div className="mt-3 rounded-lg border border-stone-200 bg-stone-100 px-2.5 py-2">
      <p className="text-xs font-medium uppercase tracking-[0.12em] text-stone-500">{title}</p>
      <div className="mt-2 flex flex-wrap gap-1.5">
        {cards.map(attachedCard => (
          <span
            className="rounded-full bg-stone-50 px-2 py-1 text-xs font-medium text-stone-700"
            key={attachedCard.id}
            title={`${attachedCard.cardId} · ${titleSuffix}`}
          >
            {attachedCard.name}
          </span>
        ))}
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

function resolutionChecklistItemClassName(tone: ResolutionChecklistTone) {
  switch (tone) {
    case 'blocked':
      return 'border-red-200 bg-red-50/80 text-red-950'
    case 'ready':
      return 'border-emerald-200 bg-emerald-50/80 text-emerald-950'
    case 'waiting':
      return 'border-amber-200 bg-amber-50/80 text-amber-950'
  }
}

function resolutionChecklistToneClassName(tone: ResolutionChecklistTone) {
  switch (tone) {
    case 'blocked':
      return 'bg-red-100 text-red-800'
    case 'ready':
      return 'bg-emerald-100 text-emerald-800'
    case 'waiting':
      return 'bg-amber-100 text-amber-800'
  }
}

function formatResolutionChecklistTone(tone: ResolutionChecklistTone) {
  switch (tone) {
    case 'blocked':
      return 'blocked'
    case 'ready':
      return 'ready'
    case 'waiting':
      return 'needed'
  }
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

function CommandErrorCard({ notice }: { notice: CommandErrorNotice }) {
  return (
    <div className="rounded-2xl border border-red-200 bg-red-50 p-3 text-red-950" role="alert">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold">{notice.title}</p>
          <p className="mt-1 text-sm leading-6 text-red-900">{notice.message}</p>
        </div>
        <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800">not applied</span>
      </div>
      <div className="mt-3 rounded-xl border border-red-100 bg-stone-50 px-3 py-2 text-xs leading-5 text-stone-700">
        <span className="font-semibold text-stone-950">Next step:</span> {notice.recovery}
      </div>
    </div>
  )
}

function EmptyWorkbench() {
  return (
    <div className="grid min-h-[32rem] place-items-center rounded-3xl border border-dashed border-stone-300 bg-stone-100/60 p-8 text-center">
      <div className="max-w-md">
        <p className="text-sm font-semibold uppercase tracking-[0.22em] text-stone-500">No game selected</p>
        <h2 className="mt-3 text-2xl font-semibold tracking-tight text-stone-950">
          Create a game board or reconnect by ID
        </h2>
        <p className="mt-3 text-sm leading-6 text-stone-600">
          Pick two supported loadouts, create a persisted board, then use the Game flow rail for setup. Viewer identity is
          stored per tab so separate browser sessions can safely sit in different player seats.
        </p>
        <div className="mt-6 grid gap-2 text-left text-sm text-stone-700">
          <div className="flex items-center gap-3 rounded-xl border border-stone-200 bg-stone-50 px-3 py-2">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-100 text-xs font-semibold text-emerald-800">
              1
            </span>
            <span>Choose two supported player loadouts.</span>
          </div>
          <div className="flex items-center gap-3 rounded-xl border border-stone-200 bg-stone-50 px-3 py-2">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-100 text-xs font-semibold text-emerald-800">
              2
            </span>
            <span>Create a game board or paste a persisted game ID.</span>
          </div>
          <div className="flex items-center gap-3 rounded-xl border border-stone-200 bg-stone-50 px-3 py-2">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-100 text-xs font-semibold text-emerald-800">
              3
            </span>
            <span>Use Game flow to draw opening hands, choose Active Pokémon, place Prizes, and start turn one.</span>
          </div>
          <div className="flex items-center gap-3 rounded-xl border border-stone-200 bg-stone-50 px-3 py-2">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-100 text-xs font-semibold text-emerald-800">
              4
            </span>
            <span>Open another tab and choose the other player seat for two-human playtests.</span>
          </div>
        </div>
      </div>
    </div>
  )
}

function GameStateLoadingPanel({ gameId, viewerPlayerId }: { gameId: string; viewerPlayerId: PlayerId }) {
  return (
    <Panel title="Catching up board" trailing={<StatusBadge tone="warning">loading</StatusBadge>}>
      <div className="space-y-4">
        <div className="rounded-2xl border border-stone-200 bg-stone-50 p-4">
          <p className="text-sm font-semibold text-stone-950">Requesting {formatPlayerId(viewerPlayerId)}'s view</p>
          <p className="mt-2 text-sm leading-6 text-stone-600">
            The board stays covered until the persisted engine returns the viewer-scoped state for {formatGameId(gameId)}.
          </p>
        </div>
        <SkeletonLines count={6} />
      </div>
    </Panel>
  )
}

function GameStateErrorPanel({
  error,
  gameId,
  viewerPlayerId,
  isRetrying,
  onRetry,
  onClear
}: {
  error: unknown
  gameId: string
  viewerPlayerId: PlayerId
  isRetrying: boolean
  onRetry: () => void
  onClear: () => void
}) {
  return (
    <Panel title="Board unavailable" trailing={<span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800">not loaded</span>}>
      <div className="space-y-4">
        <div className="rounded-2xl border border-red-200 bg-red-50 p-4 text-red-950" role="alert">
          <p className="text-sm font-semibold">Game state did not load</p>
          <p className="mt-2 text-sm leading-6 text-red-900">{errorMessage(error)}</p>
          <div className="mt-3 rounded-xl border border-red-100 bg-stone-50 px-3 py-2 text-xs leading-5 text-stone-700">
            <span className="font-semibold text-stone-950">Next step:</span> Confirm the game ID still exists and this tab is
            using the intended player seat, then retry the board request.
          </div>
        </div>

        <div className="grid gap-2 rounded-2xl border border-stone-200 bg-stone-50 p-3 sm:grid-cols-2">
          <StateRow label="Game" value={formatGameId(gameId)} />
          <StateRow label="Viewer" value={formatPlayerId(viewerPlayerId)} />
        </div>

        <div className="flex flex-col gap-2 sm:flex-row">
          <button
            className="rounded-xl bg-emerald-700 px-4 py-2.5 text-sm font-semibold text-stone-50 shadow-sm transition hover:bg-emerald-800 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-stone-300 disabled:text-stone-600"
            disabled={isRetrying}
            onClick={onRetry}
            type="button"
          >
            {isRetrying ? 'Retrying board...' : 'Retry board'}
          </button>
          <button
            className="rounded-xl border border-stone-300 px-4 py-2.5 text-sm font-medium text-stone-700 transition hover:bg-stone-100 focus:outline-none focus:ring-2 focus:ring-stone-300"
            onClick={onClear}
            type="button"
          >
            Clear game ID
          </button>
        </div>
      </div>
    </Panel>
  )
}

function StaleViewerPanel({
  actualViewerPlayerId,
  expectedViewerPlayerId,
  isRefreshing,
  onRefresh
}: {
  actualViewerPlayerId: string
  expectedViewerPlayerId: PlayerId
  isRefreshing: boolean
  onRefresh: () => void
}) {
  return (
    <Panel title="Viewer guard" trailing={<StatusBadge tone="warning">seat check</StatusBadge>}>
      <div className="space-y-4">
        <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-amber-950">
          <p className="text-sm font-semibold">Waiting for the current tab seat</p>
          <p className="mt-2 text-sm leading-6 text-amber-900">
            The engine returned {formatPlayerId(actualViewerPlayerId)} state after this tab asked for{' '}
            {formatPlayerId(expectedViewerPlayerId)}. The board is hidden so private hand data cannot flash in the
            wrong seat.
          </p>
        </div>

        <div className="grid gap-2 rounded-2xl border border-stone-200 bg-stone-50 p-3 sm:grid-cols-2">
          <StateRow label="Returned" value={formatPlayerId(actualViewerPlayerId)} />
          <StateRow label="This tab" value={formatPlayerId(expectedViewerPlayerId)} />
        </div>

        <button
          className="rounded-xl border border-stone-300 px-4 py-2.5 text-sm font-medium text-stone-700 transition hover:bg-stone-100 focus:outline-none focus:ring-2 focus:ring-stone-300 disabled:cursor-not-allowed disabled:text-stone-400"
          disabled={isRefreshing}
          onClick={onRefresh}
          type="button"
        >
          {isRefreshing ? 'Refreshing seat...' : `Retry for ${formatPlayerId(expectedViewerPlayerId)}`}
        </button>
      </div>
    </Panel>
  )
}

function RailEmptyState({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-stone-300 bg-stone-50/80 px-3 py-4">
      <p className="text-sm font-medium text-stone-800">{title}</p>
      <p className="mt-2 text-sm leading-6 text-stone-500">{children}</p>
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

function readStoredUltraBallPostSearchHandoff(): UltraBallPostSearchHandoff | null {
  if (typeof window === 'undefined') {
    return null
  }

  try {
    const item = window.sessionStorage.getItem(ULTRA_BALL_POST_SEARCH_HANDOFF_STORAGE_KEY)

    if (!item) {
      return null
    }

    const parsed = JSON.parse(item) as unknown

    return isUltraBallPostSearchHandoff(parsed) ? parsed : null
  } catch {
    return null
  }
}

function setStoredUltraBallPostSearchHandoff(handoff: UltraBallPostSearchHandoff | null) {
  if (typeof window === 'undefined') {
    return
  }

  try {
    if (handoff) {
      window.sessionStorage.setItem(ULTRA_BALL_POST_SEARCH_HANDOFF_STORAGE_KEY, JSON.stringify(handoff))
    } else {
      window.sessionStorage.removeItem(ULTRA_BALL_POST_SEARCH_HANDOFF_STORAGE_KEY)
    }
  } catch {
    // Tab-scoped recovery guidance should never block command rendering.
  }
}

function defaultSession(): PlaytestSession {
  return { gameId: '', viewerPlayerId: PLAYER_ONE_ID }
}

function isPlayerId(value: unknown): value is PlayerId {
  return PLAYER_IDS.some(playerId => playerId === value)
}

function isUltraBallPostSearchHandoff(value: unknown): value is UltraBallPostSearchHandoff {
  if (!value || typeof value !== 'object') {
    return false
  }

  const handoff = value as Partial<UltraBallPostSearchHandoff>

  return (
    typeof handoff.gameId === 'string' &&
    isPlayerId(handoff.playerId) &&
    Array.isArray(handoff.selectedCardInstanceIds) &&
    handoff.selectedCardInstanceIds.every(cardInstanceId => typeof cardInstanceId === 'string')
  )
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

function isPromptChoiceLabel(value: unknown): value is PromptChoiceLabel {
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

function ultraBallPlayCardPromptGuide(action: ActionAffordance, cardsById: Map<string, CardSummary>): PromptFlowGuide | null {
  if (action.key !== 'play_card') {
    return null
  }

  const hasUltraBallSource = action.sourceCardInstanceIds.some(cardInstanceId => {
    const card = cardsById.get(cardInstanceId)

    return card?.cardId === ULTRA_BALL_CARD_ID
  })

  if (!hasUltraBallSource) {
    return null
  }

  return {
    eyebrow: 'Trainer prompt path',
    title: 'Ultra Ball resolves through Viewer prompts',
    detail:
      'Play the Trainer here, then continue in Viewer prompts above the action list. The engine pauses at each required choice.',
    steps: [
      {
        label: 'play',
        title: 'Start Ultra Ball',
        detail: 'The card-play command starts the Trainer and opens the cost prompt.',
        tone: 'focus'
      },
      {
        label: 'cost',
        title: 'Discard 2 cards',
        detail: 'Choose two other hand cards in Viewer prompts before the Trainer can move on.',
        tone: 'next'
      },
      {
        label: 'search',
        title: 'Find 1 Pokémon',
        detail: 'After the discard resolves, choose a Pokémon from deck and the engine shuffles.',
        tone: 'next'
      }
    ]
  }
}

function ultraBallPromptFlowGuide(
  choiceKey: string,
  min: number,
  max: number,
  legalChoiceCount: number
): PromptFlowGuide | null {
  if (choiceKey === 'discard_two_from_hand') {
    return {
      eyebrow: 'Ultra Ball prompt',
      title: 'Pay the discard cost',
      detail: 'This is the required follow-up from playing Ultra Ball. Submit the cost to open the deck search.',
      steps: [
        {
          label: 'play',
          title: 'Trainer started',
          detail: 'Ultra Ball is paused by the engine until its cost is paid.',
          tone: 'complete'
        },
        {
          label: 'cost',
          title: 'Discard from hand',
          detail: `${promptChoiceInstruction(min, max)} from ${legalChoiceCount} legal hand choices.`,
          tone: 'focus'
        },
        {
          label: 'search',
          title: 'Search next',
          detail: 'The Pokémon search prompt replaces this prompt after the discard resolves.',
          tone: 'next'
        }
      ]
    }
  }

  if (choiceKey === 'search_deck_for_pokemon') {
    return {
      eyebrow: 'Ultra Ball prompt',
      title: 'Choose the Pokémon to add to hand',
      detail: 'The discard cost is complete. Finish the Trainer by selecting one Pokémon from deck.',
      steps: [
        {
          label: 'play',
          title: 'Trainer started',
          detail: 'Ultra Ball is resolving from the prior action.',
          tone: 'complete'
        },
        {
          label: 'cost',
          title: 'Discard cost paid',
          detail: 'The selected hand cards moved to discard.',
          tone: 'complete'
        },
        {
          label: 'search',
          title: 'Search deck',
          detail: `${promptChoiceInstruction(min, max)} from ${legalChoiceCount} legal Pokémon choices, then shuffle.`,
          tone: 'focus'
        }
      ]
    }
  }

  return null
}

function promptSubmitLabel(choiceKey: string, selectedCount: number, max: number, isPending: boolean) {
  if (isPending) {
    return 'Resolving prompt...'
  }

  switch (choiceKey) {
    case 'discard_two_from_hand':
      return `Discard selected cards ${selectedCount}/${max}`
    case 'search_deck_for_pokemon':
      return `Add Pokémon to hand ${selectedCount}/${max}`
    case 'knockout_prize_cards':
      return `Take selected Prizes ${selectedCount}/${max}`
    default:
      return `Submit ${selectedCount}/${max}`
  }
}

function promptFlowStepClassName(tone: PromptFlowStep['tone']) {
  switch (tone) {
    case 'complete':
      return 'bg-emerald-100/70 text-emerald-950'
    case 'focus':
      return 'bg-white text-emerald-950 shadow-sm shadow-emerald-900/5'
    case 'next':
      return 'bg-[oklch(0.985_0.004_155)] text-stone-700'
  }
}

function promptFlowStepBadgeClassName(tone: PromptFlowStep['tone']) {
  switch (tone) {
    case 'complete':
      return 'bg-emerald-700 text-stone-50'
    case 'focus':
      return 'bg-emerald-100 text-emerald-800'
    case 'next':
      return 'bg-stone-200 text-stone-600'
  }
}

function promptGuidanceMessages(
  prompt: GameState['prompts'][number],
  min: number,
  max: number,
  legalChoiceCount: number
) {
  if (prompt.promptType !== 'choose_knockout_prizes') {
    return []
  }

  const prizeCount = max
  const knockoutCount = promptPayloadArrayCount(prompt.payload, 'knocked_out_card_instance_ids')
  const queuedPromptCount = promptPayloadNumber(prompt.payload, 'queued_knockout_prize_selection_count', 0)
  const messages = [
    `Choose ${prizeCount} face-down Prize ${prizeCount === 1 ? 'card' : 'cards'} from ${legalChoiceCount} legal ${legalChoiceCount === 1 ? 'Prize' : 'Prizes'}. Prize identities stay hidden until selected.`
  ]

  if (knockoutCount > 1) {
    messages.push(`This Prize choice covers ${knockoutCount} Knocked Out Pokémon from the resolved attack.`)
  }

  if (queuedPromptCount > 0) {
    messages.push(
      `${queuedPromptCount} queued Prize ${queuedPromptCount === 1 ? 'prompt' : 'prompts'} will appear after this choice, so the attack cannot finish until every Prize prompt resolves.`
    )
  }

  if (min !== max) {
    messages.push(`This prompt accepts ${promptChoiceInstruction(min, max)}.`)
  }

  return messages
}

function promptPayloadNumber(payload: Record<string, unknown>, key: string, fallback: number) {
  const value = payload[key]

  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function promptPayloadArrayCount(payload: Record<string, unknown>, key: string) {
  const value = payload[key]

  return Array.isArray(value) ? value.length : 0
}

function promptChoiceKey(payload: Record<string, unknown>) {
  const value = payload.choice_key

  return typeof value === 'string' ? value : 'prompt_choice'
}

function promptChoiceButtonRows(
  cardInstanceIds: string[],
  legalChoiceCardsById: Map<string, CardSummary>,
  cardsById: Map<string, CardSummary>,
  legalChoiceLabelsById: Map<string, PromptChoiceLabel>
): PromptChoiceRow[] {
  const baseRows = cardInstanceIds.map(cardInstanceId => {
    const card = legalChoiceCardsById.get(cardInstanceId) ?? cardsById.get(cardInstanceId)
    const choiceLabel = legalChoiceLabelsById.get(cardInstanceId)
    const baseLabel = card?.name ?? choiceLabel?.label ?? formatCardInstanceId(cardInstanceId)

    return {
      baseLabel,
      card,
      cardInstanceId,
      choiceLabel,
      duplicateKey: promptChoiceDuplicateKey(card, baseLabel)
    }
  })
  const duplicateCounts = new Map<string, number>()

  for (const row of baseRows) {
    duplicateCounts.set(row.duplicateKey, (duplicateCounts.get(row.duplicateKey) ?? 0) + 1)
  }

  const rows = baseRows.map(row => {
    const copyLabel = promptChoiceCopyLabel(row.card)
    const includesCopyLabel = Boolean(copyLabel && (duplicateCounts.get(row.duplicateKey) ?? 0) > 1)
    const label = includesCopyLabel ? `${row.baseLabel} from ${copyLabel}` : row.baseLabel

    return {
      cardInstanceId: row.cardInstanceId,
      card: row.card,
      choiceLabel: row.choiceLabel,
      detail: promptChoiceCardDetail(row.card, row.cardInstanceId, row.choiceLabel),
      includesCopyLabel,
      label
    }
  })
  const labelCounts = new Map<string, number>()

  for (const row of rows) {
    labelCounts.set(row.label, (labelCounts.get(row.label) ?? 0) + 1)
  }

  const labelIndexes = new Map<string, number>()

  return rows.map(row => {
    const labelCount = labelCounts.get(row.label) ?? 0

    if (labelCount <= 1) {
      return row
    }

    const copyNumber = (labelIndexes.get(row.label) ?? 0) + 1
    labelIndexes.set(row.label, copyNumber)

    return {
      ...row,
      label: `${row.label}, copy ${copyNumber} of ${labelCount}`
    }
  })
}

function promptChoiceDisambiguationMessage(rows: PromptChoiceRow[]) {
  const disambiguatedRows = rows.filter(row => row.includesCopyLabel || promptChoiceHasOrdinalCopyLabel(row.label))

  if (disambiguatedRows.length === 0) {
    return null
  }

  const zones = new Set(disambiguatedRows.map(row => row.card?.zone).filter(Boolean))
  const hasOrdinalCopyLabels = disambiguatedRows.some(row => promptChoiceHasOrdinalCopyLabel(row.label))

  if (zones.has('deck') && zones.size === 1) {
    return 'Repeated deck choices are separate deck copies. Copy numbers distinguish identical Pokémon before the chosen card is added to hand.'
  }

  if (zones.has('hand') && zones.size === 1) {
    return hasOrdinalCopyLabels
      ? 'Repeated hand choices are separate cards. Labels include the hand slot, with copy numbers only when two rows still share a slot.'
      : 'Repeated hand choices are separate cards. Labels include the hand slot so you can choose the exact copy.'
  }

  return hasOrdinalCopyLabels
    ? 'Repeated choices are separate cards. Location labels and copy numbers distinguish identical choices.'
    : 'Repeated choices are separate cards. Location labels distinguish identical choices.'
}

function promptChoiceHasOrdinalCopyLabel(label: string) {
  return /, copy \d+ of \d+$/.test(label)
}

function promptChoiceDuplicateKey(card: CardSummary | undefined, fallbackLabel: string) {
  return card ? `${card.name}:${card.zone}` : fallbackLabel
}

function promptChoiceCopyLabel(card: CardSummary | undefined) {
  if (!card) {
    return null
  }

  if (card.zone === 'active' || card.zone === 'bench' || card.zone === 'hand') {
    return cardLocationLabel(card, formatEventType(card.zone))
  }

  return null
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

function commandErrorNotice(error: unknown, title: string, recovery: string): CommandErrorNotice | null {
  if (!error) {
    return null
  }

  return { title, message: errorMessage(error), recovery }
}

function formatGameId(gameId: string) {
  return gameId.length > 16 ? `${gameId.slice(0, 8)}...${gameId.slice(-4)}` : gameId
}

function formatPlayerId(playerId: string) {
  return playerId.replace('_', ' ')
}

function formatPlayerList(playerIds: string[]) {
  const labels = playerIds.map(formatPlayerId)

  if (labels.length === 0) {
    return 'no players'
  }

  if (labels.length === 1) {
    return labels[0]
  }

  return `${labels.slice(0, -1).join(', ')} and ${labels[labels.length - 1]}`
}

function formatEventType(type: string) {
  return type.replaceAll('_', ' ')
}

function formatAttackId(attackId: string) {
  return attackId
    .replaceAll('_', ' ')
    .split(' ')
    .filter(Boolean)
    .map(word => `${word.slice(0, 1).toUpperCase()}${word.slice(1)}`)
    .join(' ')
}
