import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate, useSearch } from '@tanstack/react-router'
import { useEffect, useMemo, useState } from 'react'

import {
  runAttachTcgEngineEnergy,
  buildAshRpcHeaders,
  runCallTcgEngineCoinToss,
  runChooseTcgEngineActiveFromHand,
  runChooseTcgEnginePrompt,
  runChooseTcgEngineReplacementActive,
  runChooseTcgEngineSetupBenchFromHand,
  runChooseTcgEngineStartingPlayer,
  runCompleteTcgEngineSetup,
  runCreateOpenDeckTcgEngineGame,
  runCreateTcgEngineGame,
  runDeclareTcgEngineAttack,
  runDrawTcgEngineCardForTurn,
  runDrawTcgEngineOpeningHand,
  runEvolveTcgEngineFromHand,
  runFinishTcgEngineAttack,
  runFinishTcgEngineSetupChoices,
  runGetTcgEngineGameState,
  runListTcgEngineGames,
  runListSupportedTcgDecks,
  runMulliganTcgEngineOpeningHand,
  runOpenTcgEngineActionWindow,
  runPassTcgEngineTurn,
  runPlaceTcgEnginePrizes,
  runPlayTcgEngineBasicToBench,
  runPlayTcgEngineCard,
  runRetreatTcgEngineActive,
  runResolveTcgEngineDeclaredAttack,
  runSkipTcgEngineDrawForTurn,
  runStartNextTcgEngineTurn,
  runStartTcgEngineSetup,
  runUndoTcgEngineGame,
  type CreateOpenDeckTcgEngineGameFields,
  type CreateTcgEngineGameFields,
  type GetTcgEngineGameStateFields,
  type ListTcgEngineGamesFields,
  type ListSupportedTcgDecksFields
} from '@/lib/ash/client'

const PLAYER_ONE_ID = 'player_1'
const PLAYER_TWO_ID = 'player_2'
const PLAYER_IDS = [PLAYER_ONE_ID, PLAYER_TWO_ID] as const
const ULTRA_BALL_POST_SEARCH_HANDOFF_STORAGE_KEY = 'prizmo:tcg-ultra-ball-post-search-handoff'
const DISCARD_OWN_BASIC_ENERGY_FOR_DAMAGE_EFFECT = 'damage_per_discarded_own_basic_energy'
const DISCARD_OWN_BENCH_ENERGY_FOR_BONUS_DAMAGE_EFFECT = 'discard_energy_from_own_bench_for_bonus_damage'
const DISCARD_DEFENDING_ENERGY_ON_COIN_HEADS_EFFECT = 'discard_defending_energy_on_coin_heads'
const SHUFFLE_ATTACHED_ENERGY_INTO_DECK_THEN_DAMAGE_OPPONENT_BENCH_EFFECT =
  'shuffle_attached_energy_into_deck_then_damage_opponent_bench'
const COPY_OPPONENT_ACTIVE_TERA_POKEMON_ATTACK_EFFECT = 'copy_opponent_active_tera_pokemon_attack'
const ULTRA_BALL_CARD_ID = 'MEG-131'
const BENCH_SLOT_COUNT = 5
const EXPECTED_OPEN_DECK_CARD_COUNT = 60
const OPEN_DECK_CATALOG_CARD_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.:]*-[A-Za-z0-9][A-Za-z0-9_.:-]*$/
const OPEN_DECK_EXTERNAL_CARD_PATTERN = /(?:^|\s)([A-Za-z]{2,5})[-\s]+([A-Za-z0-9]{1,4})$/
const OPEN_DECK_SECTION_HEADING_PATTERN = /^(?:pok[eé]mon|trainers?|energy|energies|total cards)\s*(?::|-)?\s*\d+\s*$/i
const OPEN_DECK_DECK_HEADING_PATTERN = /^(?:deck(?:\s+list)?|cards)\s*$/i
const PLAYER_ONE_OPEN_DECK_KEY = 'player-1-open-deck'
const PLAYER_TWO_OPEN_DECK_KEY = 'player-2-open-deck'

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
  'flowState',
  'activePlayerId',
  'firstPlayerId',
  'winnerPlayerId',
  'coinTossCallingPlayerId',
  'coinTossCall',
  'coinTossResult',
  'coinTossWinnerPlayerId',
  'startingPlayerChosenByPlayerId',
  'cursorIndex',
  'latestEventIndex'
]

const OPEN_DECK_GAME_RESOURCE_FIELDS = GAME_RESOURCE_FIELDS as CreateOpenDeckTcgEngineGameFields

const GAME_LIST_FIELDS: ListTcgEngineGamesFields = [
  'id',
  'status',
  'flowState',
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
  'rulesStatus',
  'rulesLabel',
  'rulesNote',
  'executableAttackCount',
  'unsupportedAttackCount',
  'unsupportedAbilityCount',
  { unsupportedActions: ['kind', 'id', 'name', 'reason', 'text', 'cost', 'damage'] },
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
  'flowState',
  'activePlayerId',
  'firstPlayerId',
  'winnerPlayerId',
  'coinTossCallingPlayerId',
  'coinTossCall',
  'coinTossResult',
  'coinTossWinnerPlayerId',
  'startingPlayerChosenByPlayerId',
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
      'setupReady',
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
type GameCreationMode = 'open-deck' | 'fixture'

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

type OpenDeckCardCount = {
  cardId: string
  count: number
}

type OpenDeckParseError = {
  lineNumber: number
  line: string
  message: string
}

type OpenDeckParsedLine = OpenDeckCardCount & {
  source: 'catalog-id' | 'external-row'
}

type ParsedOpenDeck = {
  cards: OpenDeckCardCount[]
  errors: OpenDeckParseError[]
  importedLineCount: number
  totalCount: number
  uniqueCardCount: number
}

type CreatedGame = {
  id: string
  status: string
  flowState: string
  activePlayerId: string
  firstPlayerId: string
  winnerPlayerId: string | null
  coinTossCallingPlayerId: string | null
  coinTossCall: string | null
  coinTossResult: string | null
  coinTossWinnerPlayerId: string | null
  startingPlayerChosenByPlayerId: string | null
  cursorIndex: number
  latestEventIndex: number
}

type AvailableGame = {
  id: string
  status: string
  flowState: string
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
  rulesStatus: string
  rulesLabel: string
  rulesNote: string
  executableAttackCount: number
  unsupportedAttackCount: number
  unsupportedAbilityCount: number
  unsupportedActions: UnsupportedCardAction[]
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

type UnsupportedCardAction = {
  kind: string
  id: string | null
  name: string
  reason: string
  text: string | null
  cost: string[]
  damage: string | null
}

type CardPillVariant = 'active' | 'compact' | 'default' | 'hand'
type CardArtVariant = CardPillVariant | 'choice'

type PlayerView = {
  playerId: string
  deckKey: string
  energyAttachedThisTurn: boolean
  supporterPlayedThisTurn: boolean
  retreatedThisTurn: boolean
  aceSpecPlayedThisGame: boolean
  setupReady: boolean
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

type ActionGroupId = 'required' | 'hand' | 'battle' | 'turn' | 'pending' | 'other'

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

type CardIntent = {
  badge: string
  detail?: string
  disabled?: boolean
  label: string
  pending?: boolean
  tone?: 'primary' | 'secondary' | 'warning'
  onClick: () => void
}

type CardIntentMap = Map<string, CardIntent>

type CardInteractionModel = {
  cardIntentsById: CardIntentMap
  railActions: ActionAffordance[]
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
    id: 'pending',
    title: 'Pending card text',
    description: 'Named attacks, abilities, or Trainer text that are visible but not executable yet.'
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

type MulliganOpeningHandInput = {
  gameId: string
  playerId: PlayerId
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

type CoinTossCall = 'heads' | 'tails'

type CoinTossCommand = {
  playerId: PlayerId
  call: CoinTossCall
}

type ChooseStartingPlayerCommand = {
  chooserPlayerId: PlayerId
  startingPlayerId: PlayerId
}

type TurnPlayerCommand = {
  playerId: string
}

type GameState = {
  gameId: string
  viewerPlayerId: string
  status: string
  flowState: string
  activePlayerId: string
  firstPlayerId: string
  winnerPlayerId: string | null
  coinTossCallingPlayerId: string | null
  coinTossCall: string | null
  coinTossResult: string | null
  coinTossWinnerPlayerId: string | null
  startingPlayerChosenByPlayerId: string | null
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
  const navigate = useNavigate({ from: '/' })
  const search = useSearch({ from: '/' })
  const queryClient = useQueryClient()
  const [gameCreationMode, setGameCreationMode] = useState<GameCreationMode>('open-deck')
  const [playerOneDeckKey, setPlayerOneDeckKey] = useState('')
  const [playerTwoDeckKey, setPlayerTwoDeckKey] = useState('')
  const [playerOneOpenDeckText, setPlayerOneOpenDeckText] = useState('')
  const [playerTwoOpenDeckText, setPlayerTwoOpenDeckText] = useState('')
  const [openDeckRngSeed, setOpenDeckRngSeed] = useState('')
  const [ultraBallPostSearchHandoff, setUltraBallPostSearchHandoff] =
    useState<UltraBallPostSearchHandoff | null>(readStoredUltraBallPostSearchHandoff)

  const session: PlaytestSession = {
    gameId: search.gameId,
    viewerPlayerId: isPlayerId(search.viewerPlayerId) ? search.viewerPlayerId : PLAYER_ONE_ID
  }

  useEffect(() => {
    setStoredUltraBallPostSearchHandoff(ultraBallPostSearchHandoff)
  }, [ultraBallPostSearchHandoff])

  const decksQuery = useQuery({
    queryKey: ['tcg-engine', 'supported-decks'],
    queryFn: listSupportedDecks
  })

  const availableGamesQuery = useQuery({
    queryKey: ['tcg-engine', 'game-list'],
    queryFn: listAvailableGames,
    refetchOnWindowFocus: false
  })

  const decks = decksQuery.data ?? []
  const availableGames = availableGamesQuery.data ?? []
  const selectedPlayerOneDeckKey = playerOneDeckKey || decks[0]?.deckKey || ''
  const selectedPlayerTwoDeckKey = playerTwoDeckKey || decks[1]?.deckKey || decks[0]?.deckKey || ''
  const normalisedGameId = session.gameId.trim()
  const parsedPlayerOneOpenDeck = useMemo(() => parseOpenDeckText(playerOneOpenDeckText), [playerOneOpenDeckText])
  const parsedPlayerTwoOpenDeck = useMemo(() => parseOpenDeckText(playerTwoOpenDeckText), [playerTwoOpenDeckText])
  const openDeckRngSeedValue = openDeckRngSeed.trim()

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
      gameCreationMode === 'open-deck'
        ? createOpenDeckGame({
            playerOneCards: parsedPlayerOneOpenDeck.cards,
            playerTwoCards: parsedPlayerTwoOpenDeck.cards,
            rngSeed: openDeckRngSeedValue.length > 0 ? openDeckRngSeedValue : null
          })
        : createFixtureGame({
            playerOneDeckKey: selectedPlayerOneDeckKey,
            playerTwoDeckKey: selectedPlayerTwoDeckKey
          }),
    onSuccess: async game => {
      updateSession(currentSession => ({
        ...currentSession,
        gameId: game.id
      }))

      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-list'] })
    }
  })

  const startSetupMutation = useMutation({
    mutationFn: (gameId: string) => startSetup(gameId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const callCoinTossMutation = useMutation({
    mutationFn: (input: { gameId: string; playerId: PlayerId; call: CoinTossCall }) => callCoinToss(input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['tcg-engine', 'game-state'] })
    }
  })

  const chooseStartingPlayerMutation = useMutation({
    mutationFn: (input: { gameId: string; chooserPlayerId: PlayerId; startingPlayerId: PlayerId }) =>
      chooseStartingPlayer(input),
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

  const mulliganOpeningHandMutation = useMutation({
    mutationFn: (input: MulliganOpeningHandInput) => mulliganOpeningHand(input),
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

  const finishSetupChoicesMutation = useMutation({
    mutationFn: (input: { gameId: string; playerId: PlayerId }) => finishSetupChoices(input),
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

  const undoMutation = useMutation({
    mutationFn: (gameId: string) => undoGame(gameId),
    onSuccess: async () => {
      setUltraBallPostSearchHandoff(null)
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
  const fixtureLoadoutsReady = Boolean(selectedPlayerOneDeckKey && selectedPlayerTwoDeckKey)
  const openDeckLoadoutsReady = isOpenDeckReady(parsedPlayerOneOpenDeck) && isOpenDeckReady(parsedPlayerTwoOpenDeck)
  const loadoutsReady = gameCreationMode === 'open-deck' ? openDeckLoadoutsReady : fixtureLoadoutsReady
  const loadoutDetail =
    gameCreationMode === 'open-deck'
      ? openDeckLoadoutDetail(parsedPlayerOneOpenDeck, parsedPlayerTwoOpenDeck, openDeckRngSeedValue)
      : selectedPlayerOneDeck && selectedPlayerTwoDeck
        ? `${selectedPlayerOneDeck.name} vs ${selectedPlayerTwoDeck.name}`
        : decks.length > 0
          ? 'Choose one supported fixture for each player.'
          : 'Waiting for the engine-owned fixture catalog.'
  const canCreateGame = loadoutsReady && !createGameMutation.isPending
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
      callCoinTossMutation.error,
      'Coin toss failed',
      'No coin toss was recorded. Refresh state and retry only while the game is waiting for a call.'
    ) ??
    commandErrorNotice(
      chooseStartingPlayerMutation.error,
      'Starting player choice failed',
      'No starting player was chosen. Confirm this tab is viewing the coin toss winner, refresh state, then choose again.'
    ) ??
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
      mulliganOpeningHandMutation.error,
      'Opening mulligan failed',
      'The opening hand was not redrawn. Retry only when this viewer has no visible Basic before choosing an Active Pokémon.'
    ) ??
    commandErrorNotice(
      chooseSetupBenchMutation.error,
      'Setup Bench choice failed',
      'No setup Bench Pokémon was added. Confirm this viewer has an Active Pokémon and an open Bench slot, then retry.'
    ) ??
    commandErrorNotice(
      finishSetupChoicesMutation.error,
      'Setup ready failed',
      'This player was not marked ready. Confirm the player has an Active Pokémon and setup choices are still open.'
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
      'Pass failed',
      'The turn stayed open. Refresh state and confirm no required prompt, attack, or replacement choice is blocking.'
    )
  const undoCommandError = commandErrorNotice(
    undoMutation.error,
    'Undo failed',
    'No prior snapshot was restored. Refresh state and retry only when the event history shows a previous step.'
  )

  function updateSession(updater: (currentSession: PlaytestSession) => PlaytestSession) {
    const nextSession = updater(session)

    void navigate({
      search: currentSearch => ({
        ...currentSearch,
        gameId: nextSession.gameId,
        viewerPlayerId: nextSession.viewerPlayerId
      }),
      replace: true
    })
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
    <main className="prizmo-workbench-bg min-h-screen text-foreground">
      <div className="mx-auto flex w-full max-w-[96rem] flex-col gap-4 px-5 py-5 sm:px-8 lg:px-10">
        <header className="flex flex-col gap-3 pb-1 lg:flex-row lg:items-center lg:justify-between">
          <div className="max-w-2xl">
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-primary">Prizmo</p>
            <h1 className="mt-2 text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">
              Playtest board
            </h1>
          </div>

          <div className="prizmo-soft-surface flex min-w-0 items-center gap-3 rounded-full px-4 py-2 text-sm text-muted-foreground">
            <span className="font-medium text-foreground">{formatPlayerId(session.viewerPlayerId)}</span>
            <span className="h-1 w-1 rounded-full bg-muted-foreground/45" />
            <span className="truncate font-mono text-xs">
              {normalisedGameId ? formatGameId(normalisedGameId) : 'No game selected'}
            </span>
          </div>
        </header>

        <section
          className={`grid gap-6 ${
            normalisedGameId ? 'lg:grid-cols-[minmax(11rem,13rem)_1fr]' : 'lg:grid-cols-[minmax(18rem,22rem)_1fr]'
          }`}
        >
          <aside className="flex flex-col gap-5">
            <Panel title={normalisedGameId ? 'Session' : 'Create or reconnect'}>
              <div className="space-y-4">
                <SessionConnectionSummary
                  gameId={normalisedGameId}
                  hasViewerMismatch={gameStateHasViewerMismatch}
                  isRefreshing={gameStateQuery.isFetching}
                  viewerPlayerId={session.viewerPlayerId}
                />

                {!normalisedGameId ? (
                  <>
                    <GameCreationModeSelect value={gameCreationMode} onChange={setGameCreationMode} />

                    {gameCreationMode === 'open-deck' ? (
                      <>
                        <OpenDeckTextArea
                          label="Player 1 decklist"
                          parsedDeck={parsedPlayerOneOpenDeck}
                          playerId={PLAYER_ONE_ID}
                          value={playerOneOpenDeckText}
                          onChange={setPlayerOneOpenDeckText}
                        />
                        <OpenDeckTextArea
                          label="Player 2 decklist"
                          parsedDeck={parsedPlayerTwoOpenDeck}
                          playerId={PLAYER_TWO_ID}
                          value={playerTwoOpenDeckText}
                          onChange={setPlayerTwoOpenDeckText}
                        />
                        <label className="block space-y-2 rounded-2xl bg-secondary/55 p-3">
                          <span className="flex items-center justify-between gap-3">
                            <span className="text-sm font-medium text-foreground">Deterministic seed</span>
                            <StatusBadge tone={openDeckRngSeedValue ? 'warning' : 'neutral'}>
                              {openDeckRngSeedValue ? 'explicit' : 'fresh RNG'}
                            </StatusBadge>
                          </span>
                          <input
                            className="w-full rounded-xl border border-input bg-input/40 px-3 py-2 font-mono text-sm text-foreground outline-none transition placeholder:text-muted-foreground focus:border-ring focus:ring-2 focus:ring-ring/30"
                            onChange={event => setOpenDeckRngSeed(event.currentTarget.value)}
                            placeholder="Optional seed for reproducible dev games"
                            type="text"
                            value={openDeckRngSeed}
                          />
                        </label>
                      </>
                    ) : (
                      <>
                        {decksQuery.isPending ? <SkeletonLines count={3} /> : null}

                        {decksQuery.error ? (
                          <InlineNotice tone="error" title="Deck fixtures did not load">
                            {errorMessage(decksQuery.error)} Refresh before creating a table.
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
                      </>
                    )}
                  </>
                ) : null}

                <fieldset className="space-y-2">
                  <legend className="text-sm font-medium text-foreground">Seat</legend>
                  <div className="grid grid-cols-2 gap-2">
                    {PLAYER_IDS.map(playerId => (
                      <label
                        className="flex cursor-pointer items-center justify-between rounded-xl bg-secondary/75 px-3 py-2 text-sm text-muted-foreground transition hover:bg-accent hover:text-accent-foreground has-[:checked]:bg-primary/12 has-[:checked]:text-primary"
                        key={playerId}
                      >
                        <span>{formatPlayerId(playerId)}</span>
                        <input
                          checked={session.viewerPlayerId === playerId}
                          className="h-4 w-4 accent-primary"
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

                {!normalisedGameId ? (
                  <button
                    className="w-full rounded-xl bg-primary px-4 py-2.5 text-sm font-semibold text-primary-foreground shadow-sm shadow-black/20 transition hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:ring-offset-background disabled:cursor-not-allowed disabled:bg-muted disabled:text-muted-foreground disabled:shadow-none"
                    disabled={!canCreateGame}
                    onClick={() => createGameMutation.mutate()}
                    type="button"
                  >
                    {createGameMutation.isPending
                      ? 'Creating table...'
                      : gameCreationMode === 'open-deck'
                        ? 'Create RNG open-deck board'
                        : 'Create fixture board'}
                  </button>
                ) : null}

                {!normalisedGameId ? (
                  <FirstRunSetupGuide
                    hasGame={Boolean(normalisedGameId)}
                    loadoutDetail={loadoutDetail}
                    loadoutsReady={loadoutsReady}
                    sourceTitle={gameCreationMode === 'open-deck' ? 'Paste open decklists' : 'Pick fixture loadouts'}
                    viewerPlayerId={session.viewerPlayerId}
                  />
                ) : null}

                {createGameMutation.error ? (
                  <InlineNotice tone="error" title="Game creation failed">
                    {errorMessage(createGameMutation.error)}{' '}
                    {gameCreationMode === 'open-deck'
                      ? 'No table was created. Confirm both lists use catalog card IDs, include 60 cards, and contain at least one Basic Pokémon.'
                      : 'No table was created. Confirm both fixture decks are still available, then try again.'}
                  </InlineNotice>
                ) : null}

                <label className={normalisedGameId ? 'hidden' : 'block space-y-2'}>
                  <span className="text-sm font-medium text-foreground">Game ID</span>
                  <input
                    className="w-full rounded-xl border border-input bg-input/40 px-3 py-2 font-mono text-sm text-foreground outline-none transition placeholder:text-muted-foreground focus:border-ring focus:ring-2 focus:ring-ring/30"
                    onChange={event => {
                      const gameId = event.currentTarget.value

                      updateSession(currentSession => ({ ...currentSession, gameId }))
                    }}
                    placeholder="Paste a persisted game UUID"
                    type="text"
                    value={session.gameId}
                  />
                </label>

                {normalisedGameId ? (
                  <details className="rounded-xl bg-secondary/55 px-3 py-2 text-sm text-muted-foreground">
                    <summary className="cursor-pointer font-medium text-foreground">Game ID</summary>
                    <input
                      className="mt-3 w-full rounded-lg border border-input bg-input/40 px-2.5 py-2 font-mono text-xs text-foreground outline-none transition placeholder:text-muted-foreground focus:border-ring focus:ring-2 focus:ring-ring/30"
                      onChange={event => {
                        const gameId = event.currentTarget.value

                        updateSession(currentSession => ({ ...currentSession, gameId }))
                      }}
                      placeholder="Paste UUID"
                      type="text"
                      value={session.gameId}
                    />
                  </details>
                ) : null}

                <div className="flex gap-2">
                  <button
                    className="flex-1 rounded-xl bg-secondary/70 px-3 py-2 text-sm font-medium text-muted-foreground transition hover:bg-accent hover:text-accent-foreground focus:outline-none focus:ring-2 focus:ring-ring/50 disabled:cursor-not-allowed disabled:text-text-dim"
                    disabled={!normalisedGameId || gameStateQuery.isFetching}
                    onClick={() => void gameStateQuery.refetch()}
                    type="button"
                  >
                    {gameStateQuery.isFetching ? 'Refreshing...' : 'Refresh'}
                  </button>
                  <button
                    className="rounded-xl bg-secondary/70 px-3 py-2 text-sm font-medium text-muted-foreground transition hover:bg-accent hover:text-accent-foreground focus:outline-none focus:ring-2 focus:ring-ring/50 disabled:cursor-not-allowed disabled:text-text-dim"
                    disabled={!session.gameId}
                    onClick={clearGame}
                    type="button"
                  >
                    Clear
                  </button>
                </div>

              </div>
            </Panel>

            {!normalisedGameId && gameCreationMode === 'fixture' ? (
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
            ) : null}
          </aside>

          <section className="min-w-0">
            {!normalisedGameId ? (
              <AvailableGamesPanel
                games={availableGames}
                isLoading={availableGamesQuery.isPending}
                loadError={availableGamesQuery.error}
                onChooseGame={(gameId: string) => {
                  updateSession(currentSession => ({ ...currentSession, gameId }))
                }}
                viewerPlayerId={session.viewerPlayerId}
              />
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
                undoCommandError={undoCommandError}
                ultraBallPostSearchHandoff={ultraBallPostSearchHandoff}
                viewerPlayerId={session.viewerPlayerId}
                onCallCoinToss={({ playerId, call }) => {
                  callCoinTossMutation.mutate({ gameId: normalisedGameId, playerId, call })
                }}
                onChooseStartingPlayer={({ chooserPlayerId, startingPlayerId }) => {
                  chooseStartingPlayerMutation.mutate({
                    gameId: normalisedGameId,
                    chooserPlayerId,
                    startingPlayerId
                  })
                }}
                onChooseSetupActive={({ playerId, cardInstanceId }) => {
                  if (isPlayerId(playerId)) {
                    chooseActiveMutation.mutate({
                      gameId: normalisedGameId,
                      playerId,
                      cardInstanceId
                    })
                  }
                }}
                onMulliganOpeningHand={({ playerId }) => {
                  if (isPlayerId(playerId)) {
                    mulliganOpeningHandMutation.mutate({
                      gameId: normalisedGameId,
                      playerId
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
                onFinishSetupChoices={({ playerId }) => {
                  if (isPlayerId(playerId)) {
                    finishSetupChoicesMutation.mutate({ gameId: normalisedGameId, playerId })
                  }
                }}
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
                onUndo={() => {
                  undoMutation.mutate(normalisedGameId)
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
                mulliganOpeningHandPendingPlayerId={
                  mulliganOpeningHandMutation.isPending
                    ? mulliganOpeningHandMutation.variables?.playerId ?? null
                    : null
                }
                chooseSetupBenchPendingCardId={
                  chooseSetupBenchMutation.isPending ? chooseSetupBenchMutation.variables?.cardInstanceId ?? null : null
                }
                chooseReplacementActivePendingCardId={
                  chooseReplacementActiveMutation.isPending
                    ? chooseReplacementActiveMutation.variables?.benchCardInstanceId ?? null
                    : null
                }
                callCoinTossPending={callCoinTossMutation.isPending}
                chooseStartingPlayerPending={chooseStartingPlayerMutation.isPending}
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
                finishSetupChoicesPending={finishSetupChoicesMutation.isPending}
                undoPending={undoMutation.isPending}
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

async function listAvailableGames(): Promise<AvailableGame[]> {
  const result = await runListTcgEngineGames({
    fields: GAME_LIST_FIELDS,
    headers: buildAshRpcHeaders(),
    page: { limit: 50 }
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  const data = result.data as AvailableGame[] | { results: AvailableGame[] }
  const games = Array.isArray(data) ? data : data.results

  return games as AvailableGame[]
}

function parseOpenDeckText(text: string): ParsedOpenDeck {
  const countsByCardId = new Map<string, number>()
  const cardIdOrder: string[] = []
  const errors: OpenDeckParseError[] = []
  let importedLineCount = 0

  for (const [index, rawLine] of text.split(/\r?\n/).entries()) {
    const trimmedLine = rawLine.trim()

    if (!trimmedLine || trimmedLine.startsWith('#') || trimmedLine.startsWith('//')) {
      continue
    }

    const line = trimmedLine.replace(/\s+(?:#|\/\/).*$/, '').trim()

    if (!line || shouldIgnoreOpenDeckLine(line)) {
      continue
    }

    const parsedLine = parseOpenDeckLine(line)

    if ('message' in parsedLine) {
      errors.push({ lineNumber: index + 1, line: trimmedLine, message: parsedLine.message })
      continue
    }

    if (parsedLine.source === 'external-row') {
      importedLineCount += 1
    }

    if (!countsByCardId.has(parsedLine.cardId)) {
      cardIdOrder.push(parsedLine.cardId)
    }

    countsByCardId.set(parsedLine.cardId, (countsByCardId.get(parsedLine.cardId) ?? 0) + parsedLine.count)
  }

  const cards = cardIdOrder.map(cardId => ({ cardId, count: countsByCardId.get(cardId) ?? 0 }))
  const totalCount = cards.reduce((total, card) => total + card.count, 0)

  if (totalCount > 0 && totalCount !== EXPECTED_OPEN_DECK_CARD_COUNT) {
    errors.push({
      lineNumber: 0,
      line: 'deck total',
      message: `Deck must contain ${EXPECTED_OPEN_DECK_CARD_COUNT} cards; parsed ${totalCount}.`
    })
  }

  return {
    cards,
    errors,
    importedLineCount,
    totalCount,
    uniqueCardCount: cards.length
  }
}

function shouldIgnoreOpenDeckLine(line: string) {
  return OPEN_DECK_SECTION_HEADING_PATTERN.test(line) || OPEN_DECK_DECK_HEADING_PATTERN.test(line)
}

function parseOpenDeckLine(line: string): OpenDeckParsedLine | { message: string } {
  const { cardText, count } = parseOpenDeckQuantity(line)

  if (!Number.isSafeInteger(count) || count < 1) {
    return { message: 'Count must be a positive whole number.' }
  }

  if (!cardText) {
    return { message: 'Missing catalog card ID.' }
  }

  const catalogCardId = normalizeOpenDeckCatalogCardId(cardText)

  if (catalogCardId) {
    return { cardId: catalogCardId, count, source: 'catalog-id' }
  }

  const externalCardId = normalizeExternalOpenDeckCardId(cardText)

  if (externalCardId) {
    return { cardId: externalCardId, count, source: 'external-row' }
  }

  return { message: 'Use catalog IDs like MEG-131 or rows like 4 Dragapult ex TWM 130.' }
}

function parseOpenDeckQuantity(line: string) {
  const compactCountFirstMatch = line.match(/^(\d+)x(.+)$/i)

  if (compactCountFirstMatch) {
    return { count: Number(compactCountFirstMatch[1]), cardText: compactCountFirstMatch[2].trim() }
  }

  const countFirstMatch = line.match(/^(\d+)\s*x?\s+(.+)$/i)

  if (countFirstMatch) {
    return { count: Number(countFirstMatch[1]), cardText: countFirstMatch[2].trim() }
  }

  const explicitCountLastMatch = line.match(/^(.+?)\s+x\s*(\d+)$/i)

  if (explicitCountLastMatch) {
    return { count: Number(explicitCountLastMatch[2]), cardText: explicitCountLastMatch[1].trim() }
  }

  const catalogIdCountLastMatch = line.match(/^([A-Za-z0-9][A-Za-z0-9_.:]*-[A-Za-z0-9][A-Za-z0-9_.:-]*)\s+(\d+)$/i)

  if (catalogIdCountLastMatch) {
    return { count: Number(catalogIdCountLastMatch[2]), cardText: catalogIdCountLastMatch[1].trim() }
  }

  return { count: 1, cardText: line.trim() }
}

function normalizeOpenDeckCatalogCardId(cardText: string) {
  const catalogCardId = cardText.trim()

  return OPEN_DECK_CATALOG_CARD_ID_PATTERN.test(catalogCardId) ? catalogCardId.toUpperCase() : null
}

function normalizeExternalOpenDeckCardId(cardText: string) {
  const match = cardText.trim().match(OPEN_DECK_EXTERNAL_CARD_PATTERN)

  if (!match) {
    return null
  }

  const setCode = match[1].toUpperCase()
  const cardNumber = match[2].toUpperCase()
  const normalizedNumber = /^\d+$/.test(cardNumber) ? cardNumber.padStart(3, '0') : cardNumber

  return `${setCode}-${normalizedNumber}`
}

function isOpenDeckReady(parsedDeck: ParsedOpenDeck) {
  return parsedDeck.errors.length === 0 && parsedDeck.totalCount === EXPECTED_OPEN_DECK_CARD_COUNT
}

function openDeckLoadoutDetail(
  playerOneDeck: ParsedOpenDeck,
  playerTwoDeck: ParsedOpenDeck,
  rngSeed: string
) {
  if (isOpenDeckReady(playerOneDeck) && isOpenDeckReady(playerTwoDeck)) {
    const seedDetail = rngSeed ? ` explicit seed ${rngSeed}` : ' fresh RNG seed'
    const importedLineCount = playerOneDeck.importedLineCount + playerTwoDeck.importedLineCount
    const importDetail = importedLineCount > 0 ? `; ${importedLineCount} external rows normalized` : ''

    return `P1 ${playerOneDeck.uniqueCardCount} unique / P2 ${playerTwoDeck.uniqueCardCount} unique with${seedDetail}${importDetail}.`
  }

  if (playerOneDeck.errors.length > 0 || playerTwoDeck.errors.length > 0) {
    return 'Fix decklist format, total count, or catalog ID issues before creating the board.'
  }

  return `Paste ${EXPECTED_OPEN_DECK_CARD_COUNT}-card catalog-backed lists for both players.`
}

async function createOpenDeckGame(input: {
  playerOneCards: OpenDeckCardCount[]
  playerTwoCards: OpenDeckCardCount[]
  rngSeed: string | null
}): Promise<CreatedGame> {
  const result = await runCreateOpenDeckTcgEngineGame({
    input: {
      activePlayerId: PLAYER_ONE_ID,
      ...(input.rngSeed ? { rngSeed: input.rngSeed } : {}),
      players: [
        { playerId: PLAYER_ONE_ID, deckKey: PLAYER_ONE_OPEN_DECK_KEY, cards: input.playerOneCards },
        { playerId: PLAYER_TWO_ID, deckKey: PLAYER_TWO_OPEN_DECK_KEY, cards: input.playerTwoCards }
      ]
    },
    fields: OPEN_DECK_GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function createFixtureGame(input: {
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

async function callCoinToss(input: { gameId: string; playerId: PlayerId; call: CoinTossCall }): Promise<CreatedGame> {
  const result = await runCallTcgEngineCoinToss({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function chooseStartingPlayer(input: {
  gameId: string
  chooserPlayerId: PlayerId
  startingPlayerId: PlayerId
}): Promise<CreatedGame> {
  const result = await runChooseTcgEngineStartingPlayer({
    input,
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

async function mulliganOpeningHand(input: MulliganOpeningHandInput): Promise<CreatedGame> {
  const result = await runMulliganTcgEngineOpeningHand({
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

async function finishSetupChoices(input: { gameId: string; playerId: PlayerId }): Promise<CreatedGame> {
  const result = await runFinishTcgEngineSetupChoices({
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
  const result = await runPassTcgEngineTurn({
    input,
    fields: GAME_RESOURCE_FIELDS,
    headers: buildAshRpcHeaders()
  })

  if (!result.success) {
    throw new Error(rpcErrorMessage(result.errors))
  }

  return result.data as CreatedGame
}

async function undoGame(gameId: string): Promise<CreatedGame> {
  const result = await runUndoTcgEngineGame({
    input: { gameId },
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
  undoCommandError,
  ultraBallPostSearchHandoff,
  onCallCoinToss,
  onChooseSetupActive,
  onChooseSetupBench,
  onChooseStartingPlayer,
  onMulliganOpeningHand,
  onChoosePrompt,
  onChooseReplacementActive,
  onAttachEnergy,
  onDeclareAttack,
  onEndTurn,
  onEvolveFromHand,
  onFinishSetupChoices,
  onFinishAttack,
  onPlayBasicToBench,
  onPlayCard,
  onRetreat,
  onResolveDeclaredAttack,
  onUndo,
  attachEnergyPendingKey,
  callCoinTossPending,
  chooseSetupActivePendingCardId,
  chooseSetupBenchPendingCardId,
  chooseStartingPlayerPending,
  chooseReplacementActivePendingCardId,
  declareAttackPendingKey,
  endTurnPendingPlayerId,
  evolveFromHandPendingKey,
  finishAttackPendingPlayerId,
  finishSetupChoicesPending,
  mulliganOpeningHandPendingPlayerId,
  undoPending,
  playBasicToBenchPendingCardId,
  promptPendingId,
  playCardPendingCardId,
  resolveDeclaredAttackPendingPlayerId,
  retreatPendingKey
}: {
  actionCommandError: CommandErrorNotice | null
  attackCommandError: CommandErrorNotice | null
  flowCommandError: CommandErrorNotice | null
  gameState: GameState
  viewerPlayerId: PlayerId
  deckNamesByKey: Map<string, string>
  promptCommandError: CommandErrorNotice | null
  undoCommandError: CommandErrorNotice | null
  ultraBallPostSearchHandoff: UltraBallPostSearchHandoff | null
  onCallCoinToss: (input: CoinTossCommand) => void
  onChooseSetupActive: (input: SetupCardCommand) => void
  onChooseSetupBench: (input: SetupCardCommand) => void
  onChooseStartingPlayer: (input: ChooseStartingPlayerCommand) => void
  onMulliganOpeningHand: (input: TurnPlayerCommand) => void
  onChoosePrompt: (input: ChoosePromptCommand) => void
  onChooseReplacementActive: (input: ChooseReplacementActiveCommand) => void
  onAttachEnergy: (input: AttachEnergyCommand) => void
  onDeclareAttack: (input: DeclareAttackCommand) => void
  onEndTurn: (input: EndTurnCommand) => void
  onEvolveFromHand: (input: EvolveFromHandCommand) => void
  onFinishSetupChoices: (input: TurnPlayerCommand) => void
  onFinishAttack: (input: FinishAttackCommand) => void
  onPlayBasicToBench: (input: PlayBasicToBenchCommand) => void
  onPlayCard: (input: PlayCardCommand) => void
  onRetreat: (input: RetreatCommand) => void
  onResolveDeclaredAttack: (input: ResolveDeclaredAttackCommand) => void
  onUndo: () => void
  attachEnergyPendingKey: string | null
  callCoinTossPending: boolean
  chooseSetupActivePendingCardId: string | null
  chooseSetupBenchPendingCardId: string | null
  chooseStartingPlayerPending: boolean
  chooseReplacementActivePendingCardId: string | null
  declareAttackPendingKey: string | null
  endTurnPendingPlayerId: string | null
  evolveFromHandPendingKey: string | null
  finishAttackPendingPlayerId: string | null
  finishSetupChoicesPending: boolean
  mulliganOpeningHandPendingPlayerId: string | null
  undoPending: boolean
  playBasicToBenchPendingCardId: string | null
  promptPendingId: string | null
  playCardPendingCardId: string | null
  resolveDeclaredAttackPendingPlayerId: string | null
  retreatPendingKey: string | null
}) {
  const cardsById = useMemo(() => visibleCardsById(gameState), [gameState])
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
  const cardInteractions = buildCardInteractionModel({
    actionCommandPending,
    attachEnergyPendingKey,
    cardsById,
    chooseReplacementActivePendingCardId,
    chooseSetupActivePendingCardId,
    chooseSetupBenchPendingCardId,
    declareAttackPendingKey,
    evolveFromHandPendingKey,
    gameState,
    onAttachEnergy,
    onChooseReplacementActive,
    onChooseSetupActive,
    onChooseSetupBench,
    onDeclareAttack,
    onEvolveFromHand,
    onPlayBasicToBench,
    onPlayCard,
    onRetreat,
    playBasicToBenchPendingCardId,
    playCardPendingCardId,
    retreatPendingKey,
    viewerPlayerId
  })
  const legalActionCount = gameState.actionAffordances.filter(actionIsExecutable).length

  return (
    <div className="space-y-5">
      <div className="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_minmax(16rem,20rem)]">
        <BattlefieldPanel
          activePlayerId={gameState.activePlayerId}
          actionCount={legalActionCount}
          awaitingPromptPlayerIds={gameState.awaitingPromptPlayerIds}
          cardIntentsById={cardInteractions.cardIntentsById}
          currentTurn={gameState.currentTurn}
          deckNamesByKey={deckNamesByKey}
          flowState={gameState.flowState}
          players={gameState.players}
          status={gameState.status}
          stadium={gameState.stadium}
          viewerPlayerId={viewerPlayerId}
        />

        <aside className="space-y-4 xl:sticky xl:top-5" aria-label="Player command rail">
          <GameFlowPanel
            callCoinTossPending={callCoinTossPending}
            commandError={flowCommandError}
            chooseSetupActivePendingCardId={chooseSetupActivePendingCardId}
            chooseSetupBenchPendingCardId={chooseSetupBenchPendingCardId}
            chooseStartingPlayerPending={chooseStartingPlayerPending}
            finishSetupChoicesPending={finishSetupChoicesPending}
            gameState={gameState}
            onCallCoinToss={onCallCoinToss}
            onChooseSetupActive={onChooseSetupActive}
            onChooseSetupBench={onChooseSetupBench}
            onChooseStartingPlayer={onChooseStartingPlayer}
            onFinishSetupChoices={onFinishSetupChoices}
            onMulliganOpeningHand={onMulliganOpeningHand}
            mulliganOpeningHandPendingPlayerId={mulliganOpeningHandPendingPlayerId}
            viewerPlayerId={viewerPlayerId}
          />

          <UndoPanel
            commandError={undoCommandError}
            gameState={gameState}
            onUndo={onUndo}
            undoPending={undoPending}
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
            actions={cardInteractions.railActions}
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

      <EventHistoryPanel events={gameState.events} />

      <DiagnosticsDisclosure gameState={gameState} />
    </div>
  )
}

function buildCardInteractionModel({
  actionCommandPending,
  attachEnergyPendingKey,
  cardsById,
  chooseReplacementActivePendingCardId,
  chooseSetupActivePendingCardId,
  chooseSetupBenchPendingCardId,
  declareAttackPendingKey,
  evolveFromHandPendingKey,
  gameState,
  onAttachEnergy,
  onChooseReplacementActive,
  onChooseSetupActive,
  onChooseSetupBench,
  onDeclareAttack,
  onEvolveFromHand,
  onPlayBasicToBench,
  onPlayCard,
  onRetreat,
  playBasicToBenchPendingCardId,
  playCardPendingCardId,
  retreatPendingKey,
  viewerPlayerId
}: {
  actionCommandPending: boolean
  attachEnergyPendingKey: string | null
  cardsById: Map<string, CardSummary>
  chooseReplacementActivePendingCardId: string | null
  chooseSetupActivePendingCardId: string | null
  chooseSetupBenchPendingCardId: string | null
  declareAttackPendingKey: string | null
  evolveFromHandPendingKey: string | null
  gameState: GameState
  onAttachEnergy: (input: AttachEnergyCommand) => void
  onChooseReplacementActive: (input: ChooseReplacementActiveCommand) => void
  onChooseSetupActive: (input: SetupCardCommand) => void
  onChooseSetupBench: (input: SetupCardCommand) => void
  onDeclareAttack: (input: DeclareAttackCommand) => void
  onEvolveFromHand: (input: EvolveFromHandCommand) => void
  onPlayBasicToBench: (input: PlayBasicToBenchCommand) => void
  onPlayCard: (input: PlayCardCommand) => void
  onRetreat: (input: RetreatCommand) => void
  playBasicToBenchPendingCardId: string | null
  playCardPendingCardId: string | null
  retreatPendingKey: string | null
  viewerPlayerId: PlayerId
}): CardInteractionModel {
  const cardIntentsById: CardIntentMap = new Map()
  const cardDirectedActionKeys = new Set<string>()
  const viewerPlayer = gameState.players.find(player => player.playerId === viewerPlayerId)

  function setCardIntent(cardInstanceId: string, intent: CardIntent) {
    if (!cardIntentsById.has(cardInstanceId)) {
      cardIntentsById.set(cardInstanceId, intent)
    }
  }

  const attackSourceActionCounts = declareAttackSourceActionCounts(gameState)

  if (viewerPlayer && gameState.flowState === 'setup_choosing_opening_active' && !viewerPlayer.active) {
    for (const card of viewerPlayer.hand.filter(isSetupActiveCandidate)) {
      const pending = chooseSetupActivePendingCardId === card.id

      setCardIntent(card.id, {
        badge: 'Active',
        disabled: Boolean(chooseSetupActivePendingCardId),
        label: `Choose ${card.name} as Active`,
        pending,
        tone: 'primary',
        onClick: () => onChooseSetupActive({ playerId: viewerPlayerId, cardInstanceId: card.id })
      })
    }
  }

  if (
    viewerPlayer &&
    gameState.flowState === 'setup_choosing_opening_bench' &&
    viewerPlayer.active &&
    !viewerPlayer.setupReady
  ) {
    for (const card of viewerPlayer.hand.filter(isSetupBenchCandidate)) {
      const pending = chooseSetupBenchPendingCardId === card.id

      setCardIntent(card.id, {
        badge: 'Bench',
        disabled: Boolean(chooseSetupBenchPendingCardId),
        label: `Bench ${card.name}`,
        pending,
        tone: 'secondary',
        onClick: () => onChooseSetupBench({ playerId: viewerPlayerId, cardInstanceId: card.id })
      })
    }
  }

  for (const action of gameState.actionAffordances) {
    if (!isPlayerId(action.playerId)) {
      continue
    }

    const actionKeyValue = actionKey(action)
    const canRunAction = !actionCommandPending

    if (action.key === 'play_card') {
      for (const cardInstanceId of action.sourceCardInstanceIds) {
        const card = cardsById.get(cardInstanceId)
        const pending = playCardPendingCardId === cardInstanceId

        setCardIntent(cardInstanceId, {
          badge: 'Play',
          disabled: !canRunAction,
          label: `Play ${card?.name ?? formatCardInstanceId(cardInstanceId)}`,
          pending,
          tone: 'primary',
          onClick: () => onPlayCard({ playerId: action.playerId, cardInstanceId })
        })
      }

      cardDirectedActionKeys.add(actionKeyValue)
    }

    if (action.key === 'play_basic_to_bench') {
      for (const cardInstanceId of action.sourceCardInstanceIds) {
        const card = cardsById.get(cardInstanceId)
        const pending = playBasicToBenchPendingCardId === cardInstanceId

        setCardIntent(cardInstanceId, {
          badge: 'Bench',
          disabled: !canRunAction,
          label: `Bench ${card?.name ?? formatCardInstanceId(cardInstanceId)}`,
          pending,
          tone: 'secondary',
          onClick: () => onPlayBasicToBench({ playerId: action.playerId, cardInstanceId })
        })
      }

      cardDirectedActionKeys.add(actionKeyValue)
    }

    if (action.key === 'evolve_from_hand' && action.targetCardInstanceIds.length === 1) {
      const targetCardInstanceId = action.targetCardInstanceIds[0]!

      for (const evolutionCardInstanceId of action.sourceCardInstanceIds) {
        const evolutionCard = cardsById.get(evolutionCardInstanceId)
        const targetCard = cardsById.get(targetCardInstanceId)
        const pendingKey = evolveKey(evolutionCardInstanceId, targetCardInstanceId)

        setCardIntent(evolutionCardInstanceId, {
          badge: 'Evolve',
          disabled: !canRunAction,
          label: `Evolve ${targetCard?.name ?? 'target'} with ${evolutionCard?.name ?? formatCardInstanceId(evolutionCardInstanceId)}`,
          pending: evolveFromHandPendingKey === pendingKey,
          tone: 'primary',
          onClick: () => onEvolveFromHand({ playerId: action.playerId, evolutionCardInstanceId, targetCardInstanceId })
        })
      }

      cardDirectedActionKeys.add(actionKeyValue)
    }

    if (action.key === 'attach_energy' && action.targetCardInstanceIds.length === 1) {
      const targetCardInstanceId = action.targetCardInstanceIds[0]!

      for (const energyCardInstanceId of action.sourceCardInstanceIds) {
        const energyCard = cardsById.get(energyCardInstanceId)
        const targetCard = cardsById.get(targetCardInstanceId)
        const pairKey = attachEnergyPairKey(energyCardInstanceId, targetCardInstanceId)

        setCardIntent(energyCardInstanceId, {
          badge: 'Attach',
          disabled: !canRunAction,
          label: `Attach ${energyCard?.name ?? 'Energy'} to ${targetCard?.name ?? formatCardInstanceId(targetCardInstanceId)}`,
          pending: attachEnergyPendingKey === pairKey,
          tone: 'primary',
          onClick: () => onAttachEnergy({ playerId: action.playerId, energyCardInstanceId, targetCardInstanceId })
        })
      }

      cardDirectedActionKeys.add(actionKeyValue)
    }

    if (action.key === 'choose_replacement_active') {
      for (const benchCardInstanceId of action.targetCardInstanceIds) {
        const benchCard = cardsById.get(benchCardInstanceId)

        setCardIntent(benchCardInstanceId, {
          badge: 'Active',
          disabled: !canRunAction,
          label: `Promote ${benchCard?.name ?? formatCardInstanceId(benchCardInstanceId)}`,
          pending: chooseReplacementActivePendingCardId === benchCardInstanceId,
          tone: 'primary',
          onClick: () => onChooseReplacementActive({ playerId: action.playerId, benchCardInstanceId })
        })
      }

      cardDirectedActionKeys.add(actionKeyValue)
    }

    if (action.key === 'declare_attack' && action.attackId) {
      const attackSourceIds = declareAttackSourceIds(action, gameState)
      const sourceHasOneAttack = attackSourceIds.every(
        attackerCardInstanceId => (attackSourceActionCounts.get(attackerCardInstanceId) ?? 0) === 1
      )

      if (sourceHasOneAttack) {
        for (const attackerCardInstanceId of attackSourceIds) {
          setCardIntent(attackerCardInstanceId, {
            badge: 'Attack',
            detail: attackIntentDetail(action),
            disabled: !canRunAction,
            label: `Declare ${attackIntentName(action)}`,
            pending: declareAttackPendingKey === attackKey(action.playerId, action.attackId),
            tone: 'primary',
            onClick: () => onDeclareAttack({ playerId: action.playerId, attackId: action.attackId! })
          })
        }

        cardDirectedActionKeys.add(actionKeyValue)
      }
    }

    if (action.key === 'retreat') {
      const paymentOptions = retreatPaymentOptions(action.sourceCardInstanceIds, action.requiredSourceCount)

      if (paymentOptions.length === 1) {
        const energyCardInstanceIds = paymentOptions[0]!

        for (const benchCardInstanceId of action.targetCardInstanceIds) {
          const benchCard = cardsById.get(benchCardInstanceId)
          const paymentKey = retreatKey(benchCardInstanceId, energyCardInstanceIds)

          setCardIntent(benchCardInstanceId, {
            badge: 'Retreat',
            disabled: !canRunAction,
            label: `Retreat to ${benchCard?.name ?? formatCardInstanceId(benchCardInstanceId)}`,
            pending: retreatPendingKey === paymentKey,
            tone: 'warning',
            onClick: () => onRetreat({ playerId: action.playerId, benchCardInstanceId, energyCardInstanceIds })
          })
        }

        cardDirectedActionKeys.add(actionKeyValue)
      }
    }
  }

  return {
    cardIntentsById,
    railActions: gameState.actionAffordances.filter(action => !cardDirectedActionKeys.has(actionKey(action)))
  }
}

function declareAttackSourceActionCounts(gameState: GameState) {
  const counts = new Map<string, number>()

  for (const action of gameState.actionAffordances) {
    if (action.key !== 'declare_attack' || !action.attackId) {
      continue
    }

    for (const attackerCardInstanceId of declareAttackSourceIds(action, gameState)) {
      counts.set(attackerCardInstanceId, (counts.get(attackerCardInstanceId) ?? 0) + 1)
    }
  }

  return counts
}

function declareAttackSourceIds(action: ActionAffordance, gameState: GameState) {
  if (action.sourceCardInstanceIds.length > 0) {
    return action.sourceCardInstanceIds
  }

  const activeCard = gameState.players.find(player => player.playerId === action.playerId)?.active

  return activeCard ? [activeCard.id] : []
}

function attackIntentName(action: ActionAffordance) {
  return action.attackName ?? (action.attackId ? formatAttackId(action.attackId) : 'attack')
}

function attackIntentDetail(action: ActionAffordance) {
  return `${attackIntentName(action)} · ${attackCostSummary(action.attackCost)} · ${attackDamageSummary(action.attackDamage)}`
}

function DiagnosticsDisclosure({ gameState }: { gameState: GameState }) {
  return (
    <details className="prizmo-panel rounded-2xl p-4 text-sm text-muted-foreground sm:p-5">
      <summary className="flex cursor-pointer list-none items-center justify-between gap-3">
        <span className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">Diagnostics</span>
        <span className="flex items-center gap-2">
          <StatusBadge tone={gameState.status === 'finished' ? 'neutral' : 'active'}>{gameState.status}</StatusBadge>
          <StatusBadge>{gameState.events.length} events</StatusBadge>
        </span>
      </summary>

      <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Metric label="Game ID" value={gameState.gameId} mono />
        <Metric label="Active player" value={formatPlayerId(gameState.activePlayerId)} />
        <Metric label="Cursor" value={`${gameState.cursorIndex} of ${gameState.latestEventIndex}`} />
        <Metric label="Setup" value={gameState.setup?.status ?? 'not started'} />
      </div>

      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <StateRow label="First player" value={formatPlayerId(gameState.firstPlayerId)} />
        <StateRow label="Winner" value={gameState.winnerPlayerId ? formatPlayerId(gameState.winnerPlayerId) : 'None'} />
        <StateRow
          label="Current turn"
          value={gameState.currentTurn ? `Turn ${gameState.currentTurn.turnNumber}, ${gameState.currentTurn.status}` : 'None'}
        />
        <StateRow label="Stadium" value={gameState.stadium?.name ?? 'None'} />
      </div>

      <p className="mt-4 rounded-xl bg-secondary/65 px-3 py-2 text-xs leading-5 text-muted-foreground">
        Event history is part of the normal play surface below. This drawer keeps IDs, cursor state, and other engine
        diagnostics out of the table path.
      </p>
    </details>
  )
}

function GameFlowPanel({
  callCoinTossPending,
  commandError,
  chooseSetupActivePendingCardId,
  chooseSetupBenchPendingCardId,
  chooseStartingPlayerPending,
  finishSetupChoicesPending,
  gameState,
  onCallCoinToss,
  onChooseSetupActive,
  onChooseSetupBench,
  onChooseStartingPlayer,
  onFinishSetupChoices,
  onMulliganOpeningHand,
  mulliganOpeningHandPendingPlayerId,
  viewerPlayerId
}: {
  callCoinTossPending: boolean
  commandError: CommandErrorNotice | null
  chooseSetupActivePendingCardId: string | null
  chooseSetupBenchPendingCardId: string | null
  chooseStartingPlayerPending: boolean
  finishSetupChoicesPending: boolean
  gameState: GameState
  onCallCoinToss: (input: CoinTossCommand) => void
  onChooseSetupActive: (input: SetupCardCommand) => void
  onChooseSetupBench: (input: SetupCardCommand) => void
  onChooseStartingPlayer: (input: ChooseStartingPlayerCommand) => void
  onFinishSetupChoices: (input: TurnPlayerCommand) => void
  onMulliganOpeningHand: (input: TurnPlayerCommand) => void
  mulliganOpeningHandPendingPlayerId: string | null
  viewerPlayerId: PlayerId
}) {
  const viewerPlayer = gameState.players.find(player => player.playerId === viewerPlayerId)
  const flowState = gameState.flowState
  const flowStateLabel = formatEventType(flowState)
  const awaitingCoinToss = flowState === 'pregame_awaiting_coin_toss'
  const awaitingStartingPlayerChoice = flowState === 'pregame_awaiting_starting_player_choice'
  const choosingSetupActive = flowState === 'setup_choosing_opening_active'
  const choosingSetupBench = flowState === 'setup_choosing_opening_bench'
  const automaticFlowState = isAutomaticFlowState(flowState)
  const setupActiveCandidates = viewerPlayer?.hand.filter(isSetupActiveCandidate) ?? []
  const setupBenchCandidates = viewerPlayer?.hand.filter(isSetupBenchCandidate) ?? []
  const setupStatus = gameState.setup?.status ?? 'not started'
  const setupCompleted = gameState.setup?.status === 'completed' || gameState.status === 'in_progress'
  const coinTossWinnerPlayerId = isPlayerId(gameState.coinTossWinnerPlayerId) ? gameState.coinTossWinnerPlayerId : null
  const viewerCanChooseStartingPlayer = awaitingStartingPlayerChoice && coinTossWinnerPlayerId === viewerPlayerId
  const turnStatus = gameState.currentTurn
    ? `turn ${gameState.currentTurn.turnNumber}: ${formatEventType(gameState.currentTurn.status)}`
    : 'no turn'
  const flowStatus = gameState.status === 'finished' ? 'finished' : setupCompleted ? turnStatus : flowStateLabel
  const tableSetupDetail = setupCompleted
    ? completedSetupTurnDetail({
        currentTurn: gameState.currentTurn,
        firstPlayerId: gameState.firstPlayerId,
        players: gameState.players,
        viewerPlayerId
      })
    : 'Follow the live setup choice.'
  const canChooseSetupActive = Boolean(
    choosingSetupActive &&
      viewerPlayer &&
      !viewerPlayer.setupReady &&
      !viewerPlayer.active &&
      setupActiveCandidates.length > 0 &&
      !chooseSetupActivePendingCardId
  )
  const viewerNeedsOpeningMulligan = Boolean(
    choosingSetupActive &&
      viewerPlayer &&
      !viewerPlayer.setupReady &&
      !viewerPlayer.active &&
      viewerPlayer.hand.length > 0 &&
      setupActiveCandidates.length === 0
  )
  const mulliganOpeningHandPending = mulliganOpeningHandPendingPlayerId === viewerPlayerId
  const canMulliganOpeningHand = viewerNeedsOpeningMulligan && !mulliganOpeningHandPendingPlayerId
  const canChooseSetupBench = Boolean(
    choosingSetupBench &&
      viewerPlayer &&
      !viewerPlayer.setupReady &&
      viewerPlayer.active &&
      viewerPlayer.bench.length < 5 &&
      setupBenchCandidates.length > 0 &&
      !chooseSetupBenchPendingCardId
  )
  const canFinishSetupChoices = Boolean(
    choosingSetupBench && viewerPlayer?.active && !viewerPlayer.setupReady && !finishSetupChoicesPending
  )
  return (
    <Panel title="Next" trailing={<StatusBadge tone={gameState.setup ? 'active' : 'neutral'}>{flowStatus}</StatusBadge>}>
      <div className="space-y-3">
        {commandError ? <CommandErrorCard notice={commandError} /> : null}

        {!setupCompleted ? (
          <>
            {awaitingCoinToss ? (
              <RailActionBlock title="Coin toss" trailing={<StatusBadge tone="warning">call</StatusBadge>}>
                <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-1">
                  <ActionCommandButton
                    disabled={callCoinTossPending}
                    onClick={() => onCallCoinToss({ playerId: viewerPlayerId, call: 'heads' })}
                    tone="primary"
                  >
                    {callCoinTossPending ? 'Calling...' : 'Heads'}
                  </ActionCommandButton>

                  <ActionCommandButton
                    disabled={callCoinTossPending}
                    onClick={() => onCallCoinToss({ playerId: viewerPlayerId, call: 'tails' })}
                  >
                    {callCoinTossPending ? 'Calling...' : 'Tails'}
                  </ActionCommandButton>
                </div>
              </RailActionBlock>
            ) : null}

            {awaitingStartingPlayerChoice ? (
              <RailActionBlock
                title="Starting player"
                trailing={<StatusBadge tone={viewerCanChooseStartingPlayer ? 'warning' : 'neutral'}>{viewerCanChooseStartingPlayer ? 'choose' : 'wait'}</StatusBadge>}
              >
                <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-1">
                  {PLAYER_IDS.map(playerId => (
                    <ActionCommandButton
                      disabled={!viewerCanChooseStartingPlayer || chooseStartingPlayerPending}
                      key={playerId}
                      onClick={() => onChooseStartingPlayer({ chooserPlayerId: viewerPlayerId, startingPlayerId: playerId })}
                      tone={playerId === viewerPlayerId ? 'primary' : 'secondary'}
                    >
                      {chooseStartingPlayerPending
                        ? 'Choosing...'
                        : viewerCanChooseStartingPlayer
                          ? formatPlayerId(playerId)
                          : coinTossWinnerPlayerId
                            ? `${formatPlayerId(coinTossWinnerPlayerId)} tab`
                            : 'Waiting'}
                    </ActionCommandButton>
                  ))}
                </div>
              </RailActionBlock>
            ) : null}

            {automaticFlowState ? (
              <RailActionBlock title="Engine" trailing={<StatusBadge tone="warning">auto</StatusBadge>}>
                <p className="text-sm text-muted-foreground">{automaticFlowStateDetail(flowState)}</p>
              </RailActionBlock>
            ) : null}

            {choosingSetupActive ? (
              <RailActionBlock title="Opening Active" trailing={<StatusBadge tone="warning">active</StatusBadge>}>
                <p className="text-sm text-muted-foreground">
                  {canChooseSetupActive
                    ? 'Pick from hand.'
                    : viewerNeedsOpeningMulligan
                      ? 'No Basic in hand. Mulligan to redraw 7.'
                      : 'No Basic visible.'}
                </p>

                {viewerNeedsOpeningMulligan ? (
                  <ActionCommandButton
                    className="mt-2"
                    disabled={!canMulliganOpeningHand}
                    onClick={() => onMulliganOpeningHand({ playerId: viewerPlayerId })}
                    tone="primary"
                  >
                    {mulliganOpeningHandPending ? 'Redrawing...' : 'Mulligan opening hand'}
                  </ActionCommandButton>
                ) : null}
              </RailActionBlock>
            ) : null}

            {choosingSetupBench ? (
              <RailActionBlock
                title="Opening Bench"
                trailing={<StatusBadge tone={viewerPlayer?.bench.length ? 'active' : 'neutral'}>{viewerPlayer?.bench.length ?? 0}/5</StatusBadge>}
              >
                <p className="text-sm text-muted-foreground">
                  {canChooseSetupBench ? 'Pick Basics from hand.' : 'Bench is optional.'}
                </p>

                <ActionCommandButton
                  className="mt-2"
                  disabled={!canFinishSetupChoices}
                  onClick={() => onFinishSetupChoices({ playerId: viewerPlayerId })}
                  tone="primary"
                >
                  {finishSetupChoicesPending ? 'Saving...' : viewerPlayer?.setupReady ? 'Ready' : 'Done'}
                </ActionCommandButton>
              </RailActionBlock>
            ) : null}

            {!awaitingCoinToss && !awaitingStartingPlayerChoice && !automaticFlowState && !choosingSetupActive && !choosingSetupBench ? (
              <RailActionBlock title={formatEventType(flowState)} trailing={<StatusBadge>{formatEventType(setupStatus)}</StatusBadge>}>
                <p className="text-sm text-muted-foreground">Waiting.</p>
              </RailActionBlock>
            ) : null}

            <RailDetailsSummary label="Setup path">
              <SetupPathGuide gameState={gameState} viewerPlayerId={viewerPlayerId} />
            </RailDetailsSummary>
          </>
        ) : (
          <>
            <RailActionBlock title="Turn" trailing={<StatusBadge tone={gameState.currentTurn ? 'active' : 'neutral'}>{turnStatus}</StatusBadge>}>
              <p className="text-sm text-muted-foreground">{tableSetupDetail}</p>
            </RailActionBlock>

            <RailDetailsSummary label="Turn path">
              <TurnStepGuide gameState={gameState} viewerPlayerId={viewerPlayerId} />
            </RailDetailsSummary>
          </>
        )}
      </div>
    </Panel>
  )
}

function UndoPanel({
  commandError,
  gameState,
  onUndo,
  undoPending
}: {
  commandError: CommandErrorNotice | null
  gameState: GameState
  onUndo: () => void
  undoPending: boolean
}) {
  const canUndo = gameState.cursorIndex > 0
  const latestEvent = gameState.events[gameState.events.length - 1]

  if (!canUndo && !commandError) {
    return null
  }

  return (
    <Panel
      title="Undo"
      trailing={<StatusBadge tone={canUndo ? 'warning' : 'neutral'}>{canUndo ? `step ${gameState.cursorIndex}` : 'locked'}</StatusBadge>}
    >
      <div className="space-y-3">
        {commandError ? <CommandErrorCard notice={commandError} /> : null}

        <p className="text-sm text-muted-foreground">
          {latestEvent
            ? `Rewind the last persisted step, ${formatEventType(latestEvent.type)}.`
            : 'No persisted event is available to rewind yet.'}
        </p>

        <ActionCommandButton disabled={!canUndo || undoPending} onClick={onUndo} tone="secondary">
          {undoPending ? 'Undoing...' : 'Undo last step'}
        </ActionCommandButton>
      </div>
    </Panel>
  )
}

function RailActionBlock({
  title,
  trailing,
  children
}: {
  title: string
  trailing?: React.ReactNode
  children: React.ReactNode
}) {
  return (
    <section className="rounded-xl bg-secondary/60 p-3">
      <div className="mb-3 flex items-center justify-between gap-3">
        <h3 className="text-sm font-semibold text-foreground">{title}</h3>
        {trailing}
      </div>
      {children}
    </section>
  )
}

function RailDetailsSummary({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <details className="rounded-xl bg-secondary/35 px-3 py-2 text-sm text-muted-foreground">
      <summary className="cursor-pointer font-medium text-muted-foreground">{label}</summary>
      <div className="mt-3">{children}</div>
    </details>
  )
}

function isAutomaticFlowState(flowState: string) {
  return [
    'setup_dealing_opening_hands',
    'setup_completing_setup',
    'turn_starting_turn',
    'turn_drawing_for_turn',
    'turn_opening_action_window',
    'turn_ending_turn',
    'turn_attack_declared',
    'turn_attack_resolving'
  ].includes(flowState)
}

function automaticFlowStateDetail(flowState: string) {
  switch (flowState) {
    case 'setup_dealing_opening_hands':
      return 'Opening hands are dealt automatically after the starting player is chosen.'
    case 'setup_completing_setup':
      return 'Both players are setup ready. The engine is placing Prizes, completing setup, and starting the first turn.'
    case 'turn_starting_turn':
      return 'The engine is starting the next turn.'
    case 'turn_drawing_for_turn':
      return 'The engine is resolving the draw step.'
    case 'turn_opening_action_window':
      return 'The engine is opening the action window.'
    case 'turn_ending_turn':
      return 'The engine is ending the passed turn and handing priority to the opponent.'
    case 'turn_attack_declared':
      return 'The engine is resolving the declared attack when no player choice is required.'
    case 'turn_attack_resolving':
      return 'The engine is finishing attack cleanup when prompts and replacement Active choices are clear.'
    default:
      return 'The engine is resolving an automatic flow transition. Refresh if this state remains visible.'
  }
}

function TurnStepGuide({
  gameState,
  viewerPlayerId
}: {
  gameState: GameState
  viewerPlayerId: PlayerId
}) {
  const currentTurn = gameState.currentTurn
  const flowState = gameState.flowState
  const turnOwnerId = currentTurn?.activePlayerId ?? gameState.activePlayerId ?? gameState.firstPlayerId
  const turnOwnerLabel = formatPlayerId(turnOwnerId)
  const viewerLabel = formatPlayerId(viewerPlayerId)
  const viewerOwnsTurn = turnOwnerId === viewerPlayerId
  const activeWindowOpen = currentTurn?.status === 'action_window'
  const drawStepResolved = currentTurn
    ? ['drawn', 'action_window', 'attack_declared', 'attack_resolving', 'ended'].includes(currentTurn.status)
    : false
  const actionWindowResolved = currentTurn
    ? ['action_window', 'attack_declared', 'attack_resolving', 'ended'].includes(currentTurn.status)
    : false
  const handoffInProgress = ['turn_ending_turn', 'turn_attack_declared', 'turn_attack_resolving'].includes(flowState)
  const guideTitle = currentTurn ? 'Turn path' : 'First-turn path'
  const startStepState = currentTurn ? 'done' : flowState === 'turn_starting_turn' ? 'next' : 'needed'
  const drawStepState = drawStepResolved
    ? 'done'
    : flowState === 'turn_drawing_for_turn' || currentTurn?.status === 'start'
      ? 'next'
      : 'needed'
  const actionWindowState = actionWindowResolved
    ? 'done'
    : flowState === 'turn_opening_action_window' || currentTurn?.status === 'drawn'
      ? 'next'
      : 'needed'
  const handoffState = currentTurn?.status === 'ended'
    ? 'done'
    : handoffInProgress
      ? 'next'
      : activeWindowOpen
        ? 'ready'
        : 'needed'
  const startDetail = currentTurn
    ? `Turn ${currentTurn.turnNumber}: ${turnOwnerLabel}. Tab: ${viewerLabel}.`
    : `Turn one: ${turnOwnerLabel}.`
  const drawDetail = drawStepResolved
    ? `Draw resolved for ${turnOwnerLabel}.`
    : `Draw one card for ${turnOwnerLabel}.`
  const actionWindowDetail = activeWindowOpen
    ? viewerOwnsTurn
      ? `Actions live for ${turnOwnerLabel}.`
      : `Switch to ${turnOwnerLabel} for actions.`
    : 'Opens after draw.'
  const handoffDetail = activeWindowOpen
    ? 'Pass or attack.'
    : handoffInProgress
      ? automaticFlowStateDetail(flowState)
      : 'Waiting for pass or attack.'

  return (
    <div className="mt-3 rounded-xl border border-amber-100 bg-[oklch(0.985_0.018_90)] p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h4 className="text-xs font-semibold uppercase tracking-[0.14em] text-amber-800">{guideTitle}</h4>
          <p className="mt-1 text-xs leading-5 text-stone-600">
            Legal choices appear in Available actions.
          </p>
        </div>
        <StatusBadge tone={activeWindowOpen ? 'active' : 'warning'}>
          {activeWindowOpen ? 'actions live' : formatEventType(flowState)}
        </StatusBadge>
      </div>

      <div className="mt-3 space-y-2">
        <SetupGuideRow
          detail={startDetail}
          number="1"
          state={startStepState}
          title="Start turn"
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
            title="Action window"
        />
        <SetupGuideRow
          detail={handoffDetail}
          number="4"
          state={handoffState}
          title="Pass or attack"
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
  const flowState = gameState.flowState
  const awaitingCoinToss = flowState === 'pregame_awaiting_coin_toss'
  const awaitingStartingPlayerChoice = flowState === 'pregame_awaiting_starting_player_choice'
  const choosingActive = flowState === 'setup_choosing_opening_active'
  const choosingBench = flowState === 'setup_choosing_opening_bench'
  const setupCompleted = gameState.setup?.status === 'completed' || gameState.status === 'in_progress'
  const coinTossDone = !awaitingCoinToss
  const startingPlayerChosen = Boolean(gameState.startingPlayerChosenByPlayerId || gameState.setup || setupCompleted)
  const openingHandsDrawn = Boolean(gameState.setup && !awaitingCoinToss && !awaitingStartingPlayerChoice && flowState !== 'setup_dealing_opening_hands')
  const viewerPlayer = gameState.players.find(player => player.playerId === viewerPlayerId)
  const viewerNeedsOpeningMulligan = Boolean(
    openingHandsDrawn &&
      choosingActive &&
      viewerPlayer &&
      !viewerPlayer.active &&
      viewerPlayer.hand.length > 0 &&
      viewerPlayer.hand.every(card => !isSetupActiveCandidate(card))
  )
  const playersMissingActive = gameState.players.filter(player => !player.active)
  const allPlayersHaveSetupActive = playersMissingActive.length === 0
  const playersSetupReady = gameState.players.filter(player => player.setupReady)
  const allPlayersSetupReady = gameState.players.length > 0 && playersSetupReady.length === gameState.players.length
  const activeSummary = gameState.players
    .map(player => `${formatPlayerId(player.playerId)}: ${player.active?.name ?? 'needs Active'}`)
    .join(', ')
  const missingActiveSummary = playersMissingActive.map(player => formatPlayerId(player.playerId)).join(', ')
  const benchCountSummary = gameState.players
    .map(player => `${formatPlayerId(player.playerId)} ${player.bench.length}/5`)
    .join(', ')
  const setupReadySummary = gameState.players
    .map(player => `${formatPlayerId(player.playerId)}: ${player.setupReady ? 'ready' : 'choosing'}`)
    .join(', ')
  const coinTossDetail = awaitingCoinToss
    ? `${formatPlayerId(viewerPlayerId)} can call heads or tails from this tab.`
    : gameState.coinTossResult && gameState.coinTossWinnerPlayerId
      ? `${formatPlayerId(gameState.coinTossWinnerPlayerId)} won after ${gameState.coinTossResult}.`
      : 'Coin toss is recorded.'
  const startingPlayerDetail = awaitingStartingPlayerChoice
    ? gameState.coinTossWinnerPlayerId
      ? `${formatPlayerId(gameState.coinTossWinnerPlayerId)} chooses who starts.`
      : 'The coin toss winner chooses who starts.'
    : startingPlayerChosen
      ? `${formatPlayerId(gameState.firstPlayerId)} starts the game.`
      : 'Resolve the coin toss before choosing the first player.'

  const activeDetail = allPlayersHaveSetupActive
    ? activeSummary
    : openingHandsDrawn
      ? viewerPlayer?.active
        ? `${viewerPlayer.active.name} is ready here. ${missingActiveSummary} still needs an Active.`
        : viewerNeedsOpeningMulligan
          ? `${formatPlayerId(viewerPlayerId)} has no Basic in hand. Use the mulligan command to redraw 7.`
        : `${formatPlayerId(viewerPlayerId)} chooses a visible Basic Pokémon from this hand.`
      : 'Opening hands are dealt automatically after the starting player is chosen.'

  const benchDetail = setupCompleted || allPlayersSetupReady
    ? `Opening Bench choices are locked: ${benchCountSummary}. ${setupReadySummary}.`
    : choosingBench && allPlayersHaveSetupActive
      ? `Optional before setup ready: ${formatPlayerId(viewerPlayerId)} can Bench visible Basics or mark ready.`
      : 'Bench choices open after both players have an Active Pokémon.'

  const lockDetail = setupCompleted
    ? 'Setup is complete. The turn flow machine has started the game.'
    : allPlayersSetupReady
      ? 'Both seats are ready. The engine places Prizes, completes setup, draws for turn, and opens actions.'
      : choosingBench && viewerPlayer?.setupReady
        ? `${formatPlayerId(viewerPlayerId)} is ready. Waiting for the other player.`
        : 'Mark both players ready after optional Bench choices.'

  return (
    <div className="mt-3 rounded-xl border border-emerald-100 bg-[oklch(0.985_0.012_155)] p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h4 className="text-xs font-semibold uppercase tracking-[0.14em] text-emerald-800">Setup path</h4>
          <p className="mt-1 text-xs leading-5 text-stone-600">
            Follow player choices only. Forced setup steps are handled by the engine. This tab is {formatPlayerId(viewerPlayerId)}.
          </p>
        </div>
        <StatusBadge tone={setupCompleted ? 'active' : flowState.startsWith('setup_') ? 'warning' : 'neutral'}>
          {formatEventType(flowState)}
        </StatusBadge>
      </div>

      <div className="mt-3 space-y-2">
        <SetupGuideRow
          detail={coinTossDetail}
          number="1"
          state={awaitingCoinToss ? 'next' : 'done'}
          title="Call the coin toss"
        />
        <SetupGuideRow
          detail={startingPlayerDetail}
          number="2"
          state={!coinTossDone ? 'needed' : awaitingStartingPlayerChoice ? 'next' : startingPlayerChosen ? 'done' : 'needed'}
          title="Choose who starts"
        />
        <SetupGuideRow
          detail={openingHandsDrawn ? 'Both players have opening hands.' : 'Opening hands are dealt by the flow machine.'}
          number="3"
          state={!startingPlayerChosen ? 'needed' : openingHandsDrawn ? 'done' : 'next'}
          title="Deal opening hands"
        />
        <SetupGuideRow
          detail={activeDetail}
          number="4"
          state={!openingHandsDrawn ? 'needed' : allPlayersHaveSetupActive ? 'done' : choosingActive ? 'next' : 'needed'}
          title="Choose Active Pokémon"
        />
        <SetupGuideRow
          detail={benchDetail}
          number="5"
          state={!allPlayersHaveSetupActive ? 'needed' : allPlayersSetupReady ? 'done' : choosingBench ? 'next' : 'needed'}
          title="Bench, then mark ready"
        />
        <SetupGuideRow
          detail={lockDetail}
          number="6"
          state={setupCompleted ? 'done' : allPlayersSetupReady ? 'ready' : 'needed'}
          title="Auto-complete setup"
        />
      </div>
    </div>
  )
}

function CompletedSetupSummary({
  currentTurn,
  firstPlayerId,
  players,
  viewerPlayerId
}: {
  currentTurn: GameState['currentTurn']
  firstPlayerId: string
  players: PlayerView[]
  viewerPlayerId: PlayerId
}) {
  const setupDetail = completedSetupTurnDetail({ currentTurn, firstPlayerId, players, viewerPlayerId })

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

function completedSetupTurnDetail({
  currentTurn,
  firstPlayerId,
  players,
  viewerPlayerId
}: {
  currentTurn: GameState['currentTurn']
  firstPlayerId: string
  players: PlayerView[]
  viewerPlayerId: PlayerId
}) {
  if (!currentTurn) {
    return 'Opening choices are locked. Use Turn step to start turn one, resolve draw timing, and open legal actions.'
  }

  const turnOwnerLabel = formatPlayerId(currentTurn.activePlayerId ?? firstPlayerId)
  const turnOwnerTabLabel = `the ${turnOwnerLabel} tab`
  const viewerOwnsTurn = currentTurn.activePlayerId === viewerPlayerId
  const ownerTabDirection = viewerOwnsTurn ? 'this tab' : turnOwnerTabLabel

  if (currentTurn.status === 'ended') {
    const nextTurnOwnerId = players.find(player => player.playerId !== currentTurn.activePlayerId)?.playerId ?? firstPlayerId
    const nextTurnOwnerLabel = formatPlayerId(nextTurnOwnerId)
    const nextTurnOwnerTabLabel = `the ${nextTurnOwnerLabel} tab`
    const nextTurnOwnerTabDirection = nextTurnOwnerId === viewerPlayerId ? 'this tab' : nextTurnOwnerTabLabel

    return `Opening choices are locked. Use Turn step to start ${nextTurnOwnerLabel}'s next turn, resolve draw timing from ${nextTurnOwnerTabDirection}, and reopen legal actions.`
  }

  if (currentTurn.status === 'start') {
    return `Opening choices are locked. Turn ${currentTurn.turnNumber} belongs to ${turnOwnerLabel}; resolve draw timing from ${ownerTabDirection} before actions reopen.`
  }

  if (currentTurn.status === 'drawn') {
    return `Opening choices are locked. Draw timing is resolved for ${turnOwnerLabel}; open legal actions from ${ownerTabDirection}.`
  }

  if (currentTurn.status === 'action_window') {
    return `Opening choices are locked. The action window is live for ${turnOwnerLabel}; continue in Available actions from ${ownerTabDirection}.`
  }

  if (currentTurn.status === 'attack_declared' || currentTurn.status === 'attack_resolving') {
    return `Opening choices are locked. ${turnOwnerLabel} is resolving an attack; finish the battle lane before the next turn path.`
  }

  return 'Opening choices are locked. Use Turn step to track this turn, draw timing, and live legal actions.'
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
          {promptChoiceRows.map(({ card, cardInstanceId, detail, label }) => {
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
                <span className="flex items-center gap-3">
                  {card ? <CardArt card={card} variant="choice" /> : null}
                  <span className="min-w-0">
                    <span className="block truncate font-semibold">{label}</span>
                    <span className="mt-0.5 block text-xs text-stone-500">{detail}</span>
                  </span>
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
  const attackFlowManaged = ['turn_attack_declared', 'turn_attack_resolving'].includes(gameState.flowState)
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
      } The flow machine finishes the attack when blockers are clear.`
    : attackFlowManaged
      ? `The flow machine resolves ${attackLabel} automatically when no player choice is required.`
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

        {turn.status === 'attack_declared' && attackFlowManaged ? (
          <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            Attack resolution is flow-managed for this game. If this state remains visible, refresh the board or inspect the engine error before exposing a manual resolve control.
          </p>
        ) : turn.status === 'attack_declared' ? (
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
            {attackFlowManaged ? (
              <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs leading-5 text-amber-900">
                Attack finish is flow-managed. Resolve any prompt or replacement Active blocker, then refresh if automatic cleanup does not continue.
              </div>
            ) : null}

            {awaitingPromptBlocksFinish ? (
              <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs leading-5 text-amber-900">
                {awaitingOwnPrompt
                  ? 'Resolve the prompt in the Viewer prompts panel before finishing this attack.'
                  : `Waiting for ${formatPlayerList(awaitingPromptPlayerIds)} to resolve their prompt before this attack can finish.`}
              </div>
            ) : null}

            {!attackFlowManaged ? (
              <button
                className="w-full rounded-xl border border-emerald-700 px-3 py-2 text-left text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 focus:outline-none focus:ring-2 focus:ring-emerald-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:border-stone-300 disabled:text-stone-400 disabled:hover:bg-transparent"
                disabled={!viewerCanAdvanceAttack || commandPending || attackCannotFinish}
                onClick={() => onFinishAttack({ playerId: turn.activePlayerId })}
                type="button"
              >
                {finishAttackButtonLabel}
              </button>
            ) : null}
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
  const executableActionCount = actions.filter(actionIsExecutable).length
  const pendingActionCount = actions.length - executableActionCount
  const postSearchHandoff = ultraBallPostSearchHandoffPlan(
    gameState,
    viewerPlayerId,
    ultraBallPostSearchHandoff,
    cardsById,
    actionGroups
  )

  if (actionGroups.length === 0 && !commandError) {
    return null
  }

  return (
    <Panel
      title="Actions"
      trailing={
        <StatusBadge tone={executableActionCount > 0 ? 'active' : pendingActionCount > 0 ? 'warning' : 'neutral'}>
          {pendingActionCount > 0 ? `${executableActionCount} legal · ${pendingActionCount} pending` : String(executableActionCount)}
        </StatusBadge>
      }
    >
      <div className="space-y-3">
        {commandError ? <CommandErrorCard notice={commandError} /> : null}

        {postSearchHandoff ? (
          <UltraBallPostSearchHandoffCard handoff={postSearchHandoff} />
        ) : null}

        {actionGroups.length > 0 ? (
          actionGroups.map(group => (
            <section className="space-y-2" key={group.id}>
              <div className="flex items-center justify-between gap-3 px-1">
                <h3 className="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">
                  {group.title}
                </h3>
                <div className="flex shrink-0 items-center gap-2">
                  {group.id === primaryActionGroupId && group.id !== 'pending' ? (
                    <span className="rounded-full bg-accent-mint/15 px-2 py-0.5 text-xs font-medium text-accent-mint">
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
          <RailEmptyState title="No legal action">
            Refresh or switch seats.
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
  const turnAction = turnGroup?.actions.find(action => action.key === 'pass')
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
    turnGroup?.actions.flatMap(action => (action.key === 'pass' && isPlayerId(action.playerId) ? [action.playerId] : [])) ?? []
  const battleActionLabel = battleAction?.attackName
    ? `Declare ${battleAction.attackName}`
    : battleAction?.attackId
      ? `Declare ${formatAttackId(battleAction.attackId)}`
      : null
  const turnActionLabel = turnAction ? `Pass as ${formatPlayerId(turnAction.playerId)}` : null

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
  const rawHandDetail = handGroup
    ? handActionGuideDetail(handGroup, basicBenchOptions, evolutionOptions, playCardOptions, handChoiceCount, {
        hasBattleActions: Boolean(battleGroup),
        hasTurnFlow: Boolean(turnGroup)
      })
    : battleGroup
      ? 'No hand or board command is legal from this view. Review battle decisions before turn flow.'
      : turnGroup
        ? 'No hand or board command is legal from this view. Only turn flow remains.'
        : 'No hand or board command is legal from this view. Finish the required choice before more actions appear.'
  const handRulesDetail = handRulesSupportActionDetail(viewerPlayer)
  const handDetail = handRulesDetail ? `${rawHandDetail} ${handRulesDetail}` : rawHandDetail
  const battleDetail = battleGroup
    ? turnGroup
      ? 'Battle decisions and Pass are both legal. Attack when the board is set, otherwise pass the turn.'
      : 'Battle decisions are available. Review retreat and paid attacks before leaving the window.'
    : turnGroup
      ? handGroup
        ? 'Turn flow is available, but hand and board choices are still live. Pass only after this board is set.'
        : 'Only turn flow remains. Pass after confirming hand, Bench, and attached Energy.'
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

function handRulesSupportActionDetail(player: PlayerView | null) {
  const counts = rulesSupportCounts(player?.hand ?? [])

  if (counts.total === 0) {
    return null
  }

  const verb = counts.total === 1 ? 'shows' : 'show'

  return `${actionCountLabel(
    counts.total,
    'hand card'
  )} ${verb} partial or unsupported rules badges; if no card-attached action or Play button appears, that card text is pending.`
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
        return 'Retreat is complete and battle choices are no longer live from this Active. Use remaining hand and board actions now, then pass.'
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
      return 'No higher-priority move is available. Pass after confirming the board state.'
    case 'pending':
      return 'No command is available for these named card-text entries yet; use another legal action or pass when ready.'
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
  const isBlockedAction = !actionIsExecutable(action)
  const canRunAction = !actionCommandPending && isPlayerId(action.playerId) && !isBlockedAction
  const isPostSearchEndTurnAction = isPlayerId(action.playerId) && postSearchEndTurnPlayerIds.includes(action.playerId)
  const playCardPromptGuide = ultraBallPlayCardPromptGuide(action, cardsById)
  const playCardOptions = uniquePlayCardOptions(playCardCommandOptions(action, cardsById))
  const repeatedPlayCardLabels = repeatedPlayCardBaseLabels(playCardOptions)
  const benchOptions = providedBenchOptions ?? basicBenchCommandOptions(action, cardsById)
  const repeatedBenchLabels = repeatedBasicBenchBaseLabels(benchOptions)
  const evolutionOptions = providedEvolutionOptions ?? evolutionCommandOptions(action, cardsById)
  const repeatedEvolutionLabels = repeatedEvolutionBaseLabels(evolutionOptions)

  return (
    <li className={`rounded-xl border px-3 py-2 text-sm ${actionSurfaceClassName(action)}`}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <p className="font-medium leading-5 text-stone-950">{action.label}</p>
            <span className="rounded-full bg-stone-200 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.12em] text-stone-600">
              {formatEventType(action.kind)}
            </span>
          </div>
        </div>
        <StatusBadge tone={action.key === 'choose_replacement_active' || isBlockedAction ? 'warning' : 'neutral'}>
          {formatPlayerId(action.playerId)}
        </StatusBadge>
      </div>

      {isBlockedAction ? <BlockedActionNotice action={action} /> : null}

      {playCardPromptGuide ? (
        <details className="mt-2 rounded-lg border border-stone-200 bg-stone-50 px-3 py-2 text-xs text-stone-600">
          <summary className="cursor-pointer font-medium text-stone-700">Prompt plan</summary>
          <PromptFlowGuideCard guide={playCardPromptGuide} />
        </details>
      ) : null}

      {action.note || actionHasMetadata(action) ? (
        <details className="mt-2 rounded-lg border border-stone-200 bg-stone-50 px-3 py-2 text-xs text-stone-600">
          <summary className="cursor-pointer font-medium text-stone-700">Details</summary>
          {action.note ? <p className="mt-2 leading-5">{action.note}</p> : null}
          {actionHasMetadata(action) ? (
            <div className="mt-2 flex flex-wrap gap-2">
              <ActionCount count={action.sourceCardInstanceIds.length} label="source" />
              <ActionCount count={action.targetCardInstanceIds.length} label="target" />
              <ActionCount count={action.requiredSourceCount} label="required source" />
              <ActionCount count={action.promptIds.length} label="prompt" />
              <ActionCount count={action.choiceKeys.length} label="choice key" />
            </div>
          ) : null}
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
            : `${postSearchBattleAttackIds.includes(action.attackId) ? 'Attack after search: ' : ''}Declare ${
                action.attackName ?? formatAttackId(action.attackId)
              }${attackCostLabel(action.attackCost)}${attackDamageLabel(action.attackDamage)}`}
        </ActionCommandButton>
      ) : null}

      {action.key === 'pass' ? (
        <ActionCommandButton
          className="mt-2"
          disabled={!canRunAction}
          onClick={() => onEndTurn({ playerId: action.playerId })}
          tone="primary"
        >
          {endTurnPendingPlayerId === action.playerId
            ? `Ending ${formatPlayerId(action.playerId)}'s turn...`
            : `${isPostSearchEndTurnAction ? 'Pass after search: ' : ''}Pass as ${formatPlayerId(action.playerId)}`}
        </ActionCommandButton>
      ) : null}
    </li>
  )
}

function BlockedActionNotice({ action }: { action: ActionAffordance }) {
  return (
    <div className="mt-2 rounded-lg border border-attention/25 bg-attention/10 px-3 py-2 text-xs leading-5 text-attention">
      <p className="font-semibold">Known card text, no command yet</p>
      <p className="mt-1 text-attention/90">{actionSummary(action)}</p>
    </div>
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
    'w-full rounded-lg px-3 py-2 text-left text-sm transition focus:outline-none focus:ring-2 focus:ring-ring/50 focus:ring-offset-2 focus:ring-offset-background disabled:cursor-not-allowed disabled:bg-muted/70 disabled:text-text-dim disabled:shadow-none'
  const toneClassName =
    tone === 'primary'
      ? 'bg-primary font-semibold text-primary-foreground shadow-sm shadow-black/20 hover:bg-primary/90'
      : 'bg-secondary/85 font-medium text-foreground hover:bg-primary/10 hover:text-primary'

  return (
    <button className={[className, baseClassName, toneClassName].filter(Boolean).join(' ')} disabled={disabled} onClick={onClick} type="button">
      {children}
    </button>
  )
}

function actionSurfaceClassName(action: ActionAffordance) {
  switch (action.key) {
    case 'choose_replacement_active':
      return 'border-attention/35 bg-attention/10'
    case 'declare_attack':
      return 'border-accent-mint/30 bg-accent-mint/10'
    case 'unsupported_attack':
    case 'unsupported_ability':
    case 'unsupported_trainer':
      return 'border-attention/35 bg-attention/10'
    default:
      return 'border-border bg-card'
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
    case 'unsupported_attack':
      return `${action.attackName ?? (action.attackId ? formatAttackId(action.attackId) : 'Attack')} is visible and paid, but its effect is pending implementation.`
    case 'unsupported_ability':
      return `${pendingActionName(action)} is visible on a Pokémon in play, but ability execution is pending implementation.`
    case 'unsupported_trainer':
      return `${pendingActionName(action)} is in hand and known to the catalog, but no executable Play command is available yet.`
    case 'pass':
      return `End the action window for ${formatPlayerId(action.playerId)}.`
    default:
      return `${formatEventType(action.kind)} command exposed by the current engine state.`
  }
}

function pendingActionName(action: ActionAffordance) {
  return action.label.replace(/^Pending (Attack|Ability|Trainer): /, '')
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
    return Number.isFinite(card.position) ? `Bench ${card.position}` : 'Bench'
  }

  if (card.zone === 'hand') {
    return Number.isFinite(card.position) ? `hand slot ${card.position}` : 'hand'
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

function actionIsExecutable(action: ActionAffordance) {
  return action.kind === 'command' || action.kind === 'prompt'
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
    case 'pass':
      return 'turn'
    case 'unsupported_attack':
    case 'unsupported_ability':
    case 'unsupported_trainer':
      return 'pending'
    default:
      return 'other'
  }
}

function actionGroupBadgeTone(groupId: ActionGroupId, isPrimaryGroup: boolean): 'active' | 'neutral' | 'warning' {
  if (groupId === 'required') {
    return 'warning'
  }

  if (groupId === 'pending') {
    return 'warning'
  }

  return isPrimaryGroup ? 'active' : 'neutral'
}

function BattlefieldPanel({
  activePlayerId,
  actionCount,
  awaitingPromptPlayerIds,
  cardIntentsById,
  currentTurn,
  deckNamesByKey,
  flowState,
  players,
  status,
  stadium,
  viewerPlayerId
}: {
  activePlayerId: string
  actionCount: number
  awaitingPromptPlayerIds: string[]
  cardIntentsById: CardIntentMap
  currentTurn: GameState['currentTurn']
  deckNamesByKey: Map<string, string>
  flowState: string
  players: PlayerView[]
  status: string
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
      title="Table"
      trailing={<StatusBadge tone={currentTurn ? 'active' : 'neutral'}>{turnLabel}</StatusBadge>}
    >
      <TurnPriorityStrip
        actionCount={actionCount}
        activePlayerId={activePlayerId}
        awaitingPromptPlayerIds={awaitingPromptPlayerIds}
        currentTurn={currentTurn}
        flowState={flowState}
        status={status}
        viewerPlayerId={viewerPlayerId}
      />

      <div className="prizmo-felt rounded-[2rem] p-2.5 sm:p-3">
        {topPlayer ? (
          <PlayerBattleSide
            activePlayerId={activePlayerId}
            cardIntentsById={cardIntentsById}
            deckName={deckNamesByKey.get(topPlayer.deckKey)}
            isViewer={topPlayer.playerId === viewerPlayerId}
            player={topPlayer}
            side="top"
          />
        ) : null}

        <div className="my-2 grid items-center gap-3 sm:grid-cols-[1fr_auto_1fr]">
          <div className="hidden h-px bg-border/60 sm:block" />
          <div className="rounded-full bg-background/55 px-3 py-1.5 text-center text-xs font-medium text-muted-foreground">
            {stadium ? `Stadium: ${stadium.name}` : 'No stadium'}
          </div>
          <div className="hidden h-px bg-border/60 sm:block" />
        </div>

        {bottomPlayer ? (
          <PlayerBattleSide
            activePlayerId={activePlayerId}
            cardIntentsById={cardIntentsById}
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

function TurnPriorityStrip({
  actionCount,
  activePlayerId,
  awaitingPromptPlayerIds,
  currentTurn,
  flowState,
  status,
  viewerPlayerId
}: {
  actionCount: number
  activePlayerId: string
  awaitingPromptPlayerIds: string[]
  currentTurn: GameState['currentTurn']
  flowState: string
  status: string
  viewerPlayerId: PlayerId
}) {
  const activePlayerLabel = isPlayerId(activePlayerId) ? formatPlayerId(activePlayerId) : 'No active player'
  const viewerLabel = formatPlayerId(viewerPlayerId)
  const viewerHasPriority = activePlayerId === viewerPlayerId
  const promptLabel = awaitingPromptPlayerIds.length
    ? awaitingPromptPlayerIds.map(playerId => (isPlayerId(playerId) ? formatPlayerId(playerId) : playerId)).join(', ')
    : 'None'
  const priorityDetail = viewerHasPriority
    ? `${viewerLabel} can act from this tab when a legal action is listed.`
    : `${activePlayerLabel} owns priority. Switch seats before sending commands for that player.`

  return (
    <div className="mb-3 grid gap-2 rounded-[1.5rem] bg-background/45 p-3 md:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)]">
      <div className="min-w-0 rounded-2xl bg-surface-control/70 px-3 py-3">
        <div className="flex flex-wrap items-center gap-2">
          <StatusBadge tone={viewerHasPriority ? 'active' : 'warning'}>
            {viewerHasPriority ? 'your priority' : 'other seat priority'}
          </StatusBadge>
          <span className="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">
            {currentTurn ? `Turn ${currentTurn.turnNumber}` : formatEventType(status)}
          </span>
        </div>
        <p className="mt-2 truncate text-sm font-semibold text-foreground">
          {activePlayerLabel} active, {formatEventType(flowState)}
        </p>
        <p className="mt-1 text-xs leading-5 text-muted-foreground">{priorityDetail}</p>
      </div>

      <div className="grid gap-2 sm:grid-cols-3 md:grid-cols-1 lg:grid-cols-3">
        <TurnSignal label="Legal actions" value={String(actionCount)} tone={actionCount > 0 ? 'active' : 'neutral'} />
        <TurnSignal label="Prompts" value={promptLabel} tone={awaitingPromptPlayerIds.length > 0 ? 'warning' : 'neutral'} />
        <TurnSignal label="Turn state" value={currentTurn ? formatEventType(currentTurn.status) : formatEventType(status)} tone="neutral" />
      </div>
    </div>
  )
}

function TurnSignal({
  label,
  tone,
  value
}: {
  label: string
  tone: 'active' | 'neutral' | 'warning'
  value: string
}) {
  const toneClassName =
    tone === 'active'
      ? 'bg-accent-mint/10 text-accent-mint'
      : tone === 'warning'
        ? 'bg-attention/10 text-attention'
        : 'bg-surface-control/70 text-muted-foreground'

  return (
    <div className={`min-w-0 rounded-2xl px-3 py-2 ${toneClassName}`}>
      <p className="text-[0.68rem] font-semibold uppercase tracking-[0.14em] opacity-75">{label}</p>
      <p className="mt-1 truncate text-sm font-semibold text-foreground">{value}</p>
    </div>
  )
}

function PlayerBattleSide({
  activePlayerId,
  cardIntentsById,
  deckName,
  isViewer,
  player,
  side
}: {
  activePlayerId: string
  cardIntentsById: CardIntentMap
  deckName?: string
  isViewer: boolean
  player: PlayerView
  side: 'top' | 'bottom'
}) {
  const isActivePlayer = player.playerId === activePlayerId
  const activeZone = (
    <BattleZone
      cards={player.active ? [player.active] : []}
      cardIntentsById={cardIntentsById}
      emptyLabel="No Active Pokémon"
      title="Active Spot"
      variant="active"
    />
  )
  const benchZone = (
    <BattleZone
      cards={player.bench}
      cardIntentsById={cardIntentsById}
      emptyLabel="Bench is empty"
      title="Bench"
      variant="bench"
    />
  )

  return (
    <section
      className={`rounded-[1.5rem] p-2.5 sm:p-3 ${
        isViewer
          ? 'bg-accent-mint/10'
          : 'bg-background/45'
      }`}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-0 flex items-center gap-2">
          <h3 className="text-sm font-semibold tracking-tight text-foreground">{formatPlayerId(player.playerId)}</h3>
          {isViewer ? <StatusBadge tone="active">you</StatusBadge> : null}
          {isActivePlayer ? <StatusBadge tone="warning">turn</StatusBadge> : null}
        </div>
        <p className="max-w-[16rem] truncate text-xs text-muted-foreground">{deckName ?? player.deckKey}</p>
      </div>

      <div className="mt-3 grid gap-2.5 xl:grid-cols-[5.5rem_minmax(0,1fr)_minmax(10rem,14rem)]">
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

        <PrivateHandZone cardIntentsById={cardIntentsById} isViewer={isViewer} player={player} />
      </div>
    </section>
  )
}

function BattleZone({
  cards,
  cardIntentsById,
  emptyLabel,
  title,
  variant
}: {
  cards: CardSummary[]
  cardIntentsById: CardIntentMap
  emptyLabel: string
  title: string
  variant: 'active' | 'bench'
}) {
  const cardVariant = variant === 'active' ? 'active' : 'compact'
  const countLabel = variant === 'bench' ? `${cards.length}/${BENCH_SLOT_COUNT}` : String(cards.length)

  return (
    <div className="rounded-2xl bg-background/45 p-2.5">
      <div className="mb-2 flex items-center justify-between gap-2">
        <h4 className="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">{title}</h4>
        <span className="rounded-full bg-muted/80 px-2 py-0.5 text-xs font-medium text-muted-foreground">
          {countLabel}
        </span>
      </div>

      {variant === 'bench' ? (
        <BenchSlots cards={cards} cardIntentsById={cardIntentsById} />
      ) : cards.length > 0 ? (
        <div
          className={
            variant === 'active'
              ? 'mx-auto grid max-w-sm gap-2'
              : 'grid gap-2 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5'
          }
        >
          {cards.map(card => (
            <CardPill card={card} intent={cardIntentsById.get(card.id)} key={card.id} variant={cardVariant} />
          ))}
        </div>
      ) : (
        <p className="rounded-xl bg-secondary/45 px-3 py-4 text-center text-sm text-muted-foreground">
          {emptyLabel}
        </p>
      )}
    </div>
  )
}

function BenchSlots({ cards, cardIntentsById }: { cards: CardSummary[]; cardIntentsById: CardIntentMap }) {
  const cardsByPosition = new Map(cards.map(card => [card.position, card]))

  return (
    <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
      {Array.from({ length: BENCH_SLOT_COUNT }, (_, index) => {
        const slotNumber = index + 1
        const card = cardsByPosition.get(slotNumber)

        return (
          <div className="rounded-xl bg-background/35 p-1.5 ring-1 ring-border/45" key={slotNumber}>
            <div className="mb-1 flex items-center justify-between gap-2 px-1 text-[0.62rem] font-semibold uppercase tracking-[0.12em] text-muted-foreground">
              <span>Bench {slotNumber}</span>
              {card ? <span className="text-accent-mint">occupied</span> : <span>open</span>}
            </div>
            {card ? (
              <CardPill card={card} intent={cardIntentsById.get(card.id)} variant="compact" />
            ) : (
              <div className="flex min-h-32 items-center justify-center rounded-xl border border-dashed border-border/60 bg-secondary/35 px-2 py-6 text-center text-xs font-medium text-muted-foreground">
                Open slot
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}

function EventHistoryPanel({ events }: { events: GameState['events'] }) {
  const latestEvents = events.slice(-24)

  return (
    <Panel title="Event history" trailing={<StatusBadge tone={events.length > 0 ? 'active' : 'neutral'}>{events.length} events</StatusBadge>}>
      <div className="space-y-3">
        <p className="text-sm leading-6 text-muted-foreground">
          Persisted domain facts from the engine. New events appear at the bottom so the table reads like a played turn.
        </p>

        {latestEvents.length > 0 ? (
          <ol className="max-h-80 space-y-2 overflow-auto pr-1" aria-label="Recent persisted game events">
            {latestEvents.map(event => (
              <li
                className="grid gap-2 rounded-xl bg-secondary/65 px-3 py-2 text-sm sm:grid-cols-[4.5rem_minmax(0,1fr)_auto] sm:items-center"
                key={event.id}
              >
                <span className="font-mono text-xs text-muted-foreground">#{event.index}</span>
                <span className="min-w-0 truncate font-medium text-foreground">{formatEventType(event.type)}</span>
                {event.playerId ? <StatusBadge>{formatPlayerId(event.playerId)}</StatusBadge> : <span className="text-xs text-muted-foreground">engine</span>}
              </li>
            ))}
          </ol>
        ) : (
          <RailEmptyState title="No events yet">Create or reconnect to a game, then engine facts will appear here.</RailEmptyState>
        )}
      </div>
    </Panel>
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
      ? 'bg-accent-mint/10 text-accent-mint'
      : tone === 'hidden'
        ? 'bg-muted/55 text-muted-foreground'
        : 'bg-background/55 text-foreground'

  return (
    <div className={`rounded-xl px-2 py-2 text-center ${toneClassName}`}>
      <p className="text-lg font-semibold tabular-nums">{value}</p>
      <p className="mt-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.14em] opacity-70">{label}</p>
    </div>
  )
}

function PrivateHandZone({
  cardIntentsById,
  isViewer,
  player
}: {
  cardIntentsById: CardIntentMap
  isViewer: boolean
  player: PlayerView
}) {
  return (
    <div className="rounded-2xl bg-background/45 p-2.5">
      <div className="mb-2 flex items-center justify-between gap-2">
        <h4 className="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">
          {isViewer ? 'Your hand' : 'Opponent hand'}
        </h4>
        <span className="rounded-full bg-muted/80 px-2 py-0.5 text-xs font-medium text-muted-foreground">
          {player.handCount}
        </span>
      </div>

      {isViewer ? (
        <>
          <HandRulesSupportNotice cards={player.hand} />
          {player.hand.length > 0 ? (
            <div className="grid max-h-80 grid-cols-2 gap-2 overflow-auto pr-1">
              {player.hand.map(card => (
                <HandCardTile card={card} intent={cardIntentsById.get(card.id)} key={card.id} />
              ))}
            </div>
          ) : (
            <p className="rounded-xl bg-secondary/45 px-3 py-4 text-center text-sm text-muted-foreground">
              Empty.
            </p>
          )}
        </>
      ) : (
        <div className="rounded-xl bg-muted/55 px-3 py-4 text-center text-sm text-muted-foreground">
          {player.handCount} hidden
        </div>
      )}
    </div>
  )
}

function HandRulesSupportNotice({ cards }: { cards: CardSummary[] }) {
  const counts = rulesSupportCounts(cards)
  const unsupportedActionCount = cards.reduce((count, card) => count + card.unsupportedActions.length, 0)

  if (counts.total === 0) {
    return null
  }

  const detail =
    counts.unsupported > 0 && counts.partial > 0
      ? `${counts.unsupported} unsupported and ${counts.partial} partial cards have visible badges.`
      : counts.unsupported > 0
        ? `${actionCountLabel(counts.unsupported, 'card')} ${counts.unsupported === 1 ? 'has' : 'have'} card text that is not executable yet.`
        : `${actionCountLabel(counts.partial, 'card')} ${counts.partial === 1 ? 'has' : 'have'} only partial card-text support.`
  const pendingActionDetail = unsupportedActionCount > 0
    ? ` ${actionCountLabel(unsupportedActionCount, 'named card-text item')} ${unsupportedActionCount === 1 ? 'is' : 'are'} listed in card details as pending.`
    : ''

  return (
    <div className="mb-2 rounded-xl border border-attention/25 bg-attention/10 px-3 py-2 text-xs leading-5 text-attention">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-semibold">Rules coverage</p>
        <StatusBadge tone="warning">{counts.total} flagged</StatusBadge>
      </div>
      <p className="mt-1 text-attention/90">
        {detail} Legal generic actions still appear as card badges or action buttons.{pendingActionDetail}
      </p>
    </div>
  )
}

function HandCardTile({ card, intent }: { card: CardSummary; intent?: CardIntent }) {
  const content = (
    <>
      <CardArt card={card} variant="hand" />
      <RulesSupportBadge card={card} compact />
      {intent ? <CardIntentBadge intent={intent} compact /> : null}
    </>
  )
  const className = `relative rounded-xl bg-secondary/70 p-1.5 text-left ring-1 ring-border/40 ${intent ? cardIntentClassName(intent) : ''}`
  const title = intent ? `${intent.label} · ${card.name} · ${card.cardId}` : `${card.name} · ${card.cardId}`

  return intent ? (
    <button
      aria-label={intent.label}
      className={className}
      disabled={intent.disabled}
      onClick={intent.onClick}
      title={title}
      type="button"
    >
      {content}
    </button>
  ) : (
    <div className={className} title={title}>
      {content}
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
    <div className="prizmo-soft-surface rounded-2xl p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-semibold text-foreground">{formatPlayerId(viewerPlayerId)}</p>
          <p className="mt-1 truncate font-mono text-xs text-muted-foreground">
            {gameId ? formatGameId(gameId) : 'No game'}
          </p>
        </div>
        <StatusBadge tone={statusTone}>{statusLabel}</StatusBadge>
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
    <section className="prizmo-panel rounded-2xl p-4 sm:p-5">
      <div className="mb-4 flex items-center justify-between gap-3">
        <h2 className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">{title}</h2>
        {trailing}
      </div>
      {children}
    </section>
  )
}

function GameCreationModeSelect({
  value,
  onChange
}: {
  value: GameCreationMode
  onChange: (value: GameCreationMode) => void
}) {
  const options: Array<{ value: GameCreationMode; title: string; detail: string }> = [
    {
      value: 'open-deck',
      title: 'Open decklists',
      detail: 'Paste catalog card IDs. The engine validates, seeds, and shuffles the table.'
    },
    {
      value: 'fixture',
      title: 'Fixture shortcut',
      detail: 'Use committed regression fixtures for known playtest scenarios.'
    }
  ]

  return (
    <fieldset className="space-y-2">
      <legend className="text-sm font-medium text-foreground">Game source</legend>
      <div className="grid gap-2">
        {options.map(option => (
          <label
            className="flex cursor-pointer items-start justify-between gap-3 rounded-2xl bg-secondary/70 px-3 py-2.5 text-sm text-muted-foreground transition hover:bg-accent hover:text-accent-foreground has-[:checked]:bg-primary/12 has-[:checked]:text-primary"
            key={option.value}
          >
            <span>
              <span className="block font-medium text-foreground">{option.title}</span>
              <span className="mt-1 block text-xs leading-5 text-muted-foreground">{option.detail}</span>
            </span>
            <input
              checked={value === option.value}
              className="mt-1 h-4 w-4 shrink-0 accent-primary"
              name="game-creation-mode"
              onChange={() => onChange(option.value)}
              type="radio"
            />
          </label>
        ))}
      </div>
    </fieldset>
  )
}

function OpenDeckTextArea({
  label,
  parsedDeck,
  playerId,
  value,
  onChange
}: {
  label: string
  parsedDeck: ParsedOpenDeck
  playerId: PlayerId
  value: string
  onChange: (value: string) => void
}) {
  const ready = isOpenDeckReady(parsedDeck)
  const hasInput = value.trim().length > 0
  const statusTone = ready ? 'active' : parsedDeck.errors.length > 0 || hasInput ? 'warning' : 'neutral'
  const statusLabel = ready
    ? 'ready'
    : parsedDeck.errors.length > 0
      ? `${parsedDeck.errors.length} ${parsedDeck.errors.length === 1 ? 'issue' : 'issues'}`
      : `${parsedDeck.totalCount}/${EXPECTED_OPEN_DECK_CARD_COUNT}`

  return (
    <div className="prizmo-soft-surface rounded-2xl p-3">
      <label className="block space-y-2">
        <span className="flex items-center justify-between gap-3">
          <span className="text-sm font-medium text-foreground">{label}</span>
          <span className="flex items-center gap-1.5">
            <StatusBadge tone={statusTone}>{statusLabel}</StatusBadge>
            <StatusBadge tone="neutral">{formatPlayerId(playerId)}</StatusBadge>
          </span>
        </span>
        <textarea
          className="min-h-44 w-full resize-y rounded-xl border border-input bg-input/40 px-3 py-2 font-mono text-xs leading-5 text-foreground outline-none transition placeholder:text-muted-foreground focus:border-ring focus:ring-2 focus:ring-ring/30"
          onChange={event => onChange(event.currentTarget.value)}
          placeholder={'Pokémon: 17\n4 Dragapult ex TWM 130\n3 MEG-132\nMEG-133 x2\n# catalog IDs and PTCGL/Limitless rows both work'}
          spellCheck={false}
          value={value}
        />
      </label>

      <p className="mt-2 text-xs leading-5 text-muted-foreground">
        Paste catalog IDs like <span className="font-mono text-foreground">4 MEG-131</span> or copied rows like{' '}
        <span className="font-mono text-foreground">4 Dragapult ex TWM 130</span>. Section headings are ignored.
      </p>

      <div className="mt-3 flex flex-wrap gap-1.5 text-xs font-medium text-muted-foreground">
        <span className="rounded-full bg-muted px-2 py-1">
          {parsedDeck.totalCount}/{EXPECTED_OPEN_DECK_CARD_COUNT} cards
        </span>
        <span className="rounded-full bg-muted px-2 py-1">{parsedDeck.uniqueCardCount} unique</span>
        <span className="rounded-full bg-muted px-2 py-1">catalog or PTCGL rows</span>
        {parsedDeck.importedLineCount > 0 ? (
          <span className="rounded-full bg-primary/12 px-2 py-1 text-primary">
            {parsedDeck.importedLineCount} normalized
          </span>
        ) : null}
      </div>

      {parsedDeck.errors.length > 0 ? (
        <div className="mt-3 rounded-xl bg-attention/10 px-3 py-2 text-xs leading-5 text-attention">
          <p className="font-semibold">Fix decklist import before creating the board.</p>
          <ul className="mt-1 list-disc space-y-1 pl-4">
            {parsedDeck.errors.slice(0, 3).map(error => (
              <li key={`${error.lineNumber}-${error.message}`}>
                {error.lineNumber > 0 ? `Line ${error.lineNumber}` : 'Deck total'}: {error.message}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
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
    <div className="prizmo-soft-surface rounded-2xl p-3">
      <label className="block space-y-2">
        <span className="flex items-center justify-between gap-3">
          <span className="text-sm font-medium text-foreground">{label}</span>
          <StatusBadge tone={selectedDeck ? 'active' : 'neutral'}>{formatPlayerId(playerId)}</StatusBadge>
        </span>
        <select
          className="w-full rounded-xl border border-input bg-input/40 px-3 py-2 text-sm text-foreground outline-none transition focus:border-ring focus:ring-2 focus:ring-ring/30 disabled:cursor-not-allowed disabled:text-text-dim"
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
        <div className="mt-3 pt-3">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-foreground">{selectedDeck.name}</p>
              <p className="mt-1 font-mono text-xs text-muted-foreground">{selectedDeck.deckKey}</p>
            </div>
            <a
              className="shrink-0 text-xs font-medium text-primary hover:text-primary/80"
              href={selectedDeck.sourceUrl}
              rel="noreferrer"
              target="_blank"
            >
              Source
            </a>
          </div>
          <div className="mt-3 flex flex-wrap gap-1.5 text-xs font-medium text-muted-foreground">
            <span className="rounded-full bg-muted px-2 py-1">{selectedDeck.cardCount} cards</span>
            <span className="rounded-full bg-muted px-2 py-1">{selectedDeck.uniqueCardCount} unique</span>
          </div>
        </div>
      ) : (
        <p className="mt-3 pt-3 text-xs leading-5 text-muted-foreground">
          Choose a fixture after the engine catalog loads.
        </p>
      )}
    </div>
  )
}

function FirstRunSetupGuide({
  hasGame,
  loadoutDetail,
  loadoutsReady,
  sourceTitle,
  viewerPlayerId
}: {
  hasGame: boolean
  loadoutDetail: string
  loadoutsReady: boolean
  sourceTitle: string
  viewerPlayerId: PlayerId
}) {
  return (
    <section className="rounded-2xl bg-accent-mint/10 p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-foreground">First table checklist</p>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">
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
          title={sourceTitle}
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
  const showDetail = state === 'next' || state === 'ready'

  return (
    <div className="flex items-start gap-3 rounded-xl bg-surface-control/55 px-3 py-2.5">
      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted/80 text-xs font-semibold text-muted-foreground">
        {number}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-center justify-between gap-2">
          <p className="text-sm font-medium text-foreground">{title}</p>
          <StatusBadge tone={badgeTone}>{badgeLabel}</StatusBadge>
        </div>
        {showDetail ? <p className="mt-1 text-xs leading-5 text-muted-foreground">{detail}</p> : null}
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
      <p className="rounded-xl bg-secondary/70 px-3 py-2 text-sm leading-6 text-muted-foreground">
        Supported fixture metadata appears here after the engine catalog loads.
      </p>
    )
  }

  return (
    <div className="space-y-3">
      <p className="text-sm leading-6 text-muted-foreground">Engine fixtures. Selected seats are marked.</p>
      {decks.map(deck => {
        const selectedSeats = [
          deck.deckKey === playerOneDeckKey ? 'P1' : null,
          deck.deckKey === playerTwoDeckKey ? 'P2' : null
        ].filter(Boolean)

        return (
          <div className="rounded-xl bg-secondary/70 p-3" key={deck.deckKey}>
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-foreground">{deck.name}</p>
                <p className="mt-1 font-mono text-xs text-muted-foreground">{deck.deckKey}</p>
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
                <span className="shrink-0 text-xs text-muted-foreground">{deck.uniqueCardCount} unique</span>
              )}
            </div>
            <div className="mt-3 flex items-center justify-between gap-3 text-xs text-muted-foreground">
              <span>{deck.cardCount} cards</span>
              <a
                className="font-medium text-primary hover:text-primary/80"
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

function CardPill({
  card,
  intent,
  variant = 'default'
}: {
  card: CardSummary
  intent?: CardIntent
  variant?: CardPillVariant
}) {
  const attachedCards = card.attachedCards ?? []
  const evolutionStackCards = evolutionStackForCard(card, attachedCards)
  const evolutionStackCardIds = new Set(evolutionStackCards.map(attachedCard => attachedCard.id))
  const regularAttachedCards = attachedCards.filter(attachedCard => !evolutionStackCardIds.has(attachedCard.id))
  const cardMeta = [card.category, card.stage, card.status]
    .filter((value): value is string => Boolean(value))
    .map(formatEventType)
  const cardClassName =
    variant === 'active'
      ? 'rounded-2xl bg-accent-mint/10 p-3 shadow-sm shadow-black/20 ring-1 ring-accent-mint/20'
      : variant === 'compact'
        ? 'rounded-xl bg-secondary/80 p-2.5 ring-1 ring-border/40'
        : variant === 'hand'
          ? 'rounded-xl bg-secondary/80 p-2.5 ring-1 ring-border/40'
          : 'rounded-xl bg-secondary/80 p-3 ring-1 ring-border/40'
  const titleClassName = variant === 'active' ? 'text-base' : 'text-sm'
  const contentClassName =
    variant === 'active'
      ? 'grid gap-3 sm:grid-cols-[minmax(6.75rem,8.5rem)_minmax(0,1fr)]'
      : variant === 'hand'
        ? 'grid grid-cols-[3.25rem_minmax(0,1fr)] gap-3'
        : 'space-y-2'
  const showMeta = variant !== 'hand' && cardMeta.length > 0

  if (variant === 'compact') {
    const content = (
      <>
        <CardArt card={card} variant={variant} />
        <div className="mt-2 flex items-start justify-between gap-2">
          <p className="min-w-0 truncate text-xs font-medium text-foreground">{card.name}</p>
          {card.damage > 0 ? <StatusBadge tone="warning">{card.damage}</StatusBadge> : null}
        </div>
        {attachedCards.length > 0 ? (
          <p className="mt-1 text-[0.68rem] font-medium text-muted-foreground">{attachedCards.length} attached</p>
        ) : null}
        <RulesSupportBadge card={card} compact />
        {intent ? <CardIntentBadge intent={intent} compact /> : null}
      </>
    )

    return intent ? (
      <button
        aria-label={intent.label}
        className={`${cardClassName} relative text-left transition ${cardIntentClassName(intent)}`}
        disabled={intent.disabled}
        onClick={intent.onClick}
        type="button"
      >
        {content}
      </button>
    ) : (
      <div className={cardClassName}>
        {content}
      </div>
    )
  }

  const content = (
    <div className={contentClassName}>
      <CardArt card={card} variant={variant} />

      <div className="min-w-0">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className={`truncate font-medium text-foreground ${titleClassName}`}>{card.name}</p>
            <p className="mt-1 font-mono text-xs text-muted-foreground">{card.cardId}</p>
          </div>
          {card.damage > 0 ? <StatusBadge tone="warning">{card.damage} dmg</StatusBadge> : null}
        </div>

        {showMeta ? (
          <div className="mt-2 flex flex-wrap gap-1.5">
            {cardMeta.map(meta => (
              <span
                className="rounded-full bg-muted/70 px-2 py-0.5 text-[0.68rem] font-medium text-muted-foreground"
                key={meta}
              >
                {meta}
              </span>
            ))}
          </div>
        ) : null}

        <RulesSupportCallout card={card} />

        {evolutionStackCards.length > 0 ? (
          <AttachedCardGroup cards={evolutionStackCards} title="Evolution" titleSuffix="evolved under" />
        ) : null}

        {regularAttachedCards.length > 0 ? (
          <AttachedCardGroup cards={regularAttachedCards} title="Attached" titleSuffix="attached" />
        ) : null}

        {intent?.detail ? <CardIntentDetail intent={intent} /> : null}
      </div>

      {intent ? <CardIntentBadge intent={intent} /> : null}
    </div>
  )

  return intent ? (
    <button
      aria-label={intent.label}
      className={`${cardClassName} relative text-left transition ${cardIntentClassName(intent)}`}
      disabled={intent.disabled}
      onClick={intent.onClick}
      type="button"
    >
      {content}
    </button>
  ) : (
    <div className={cardClassName}>
      {content}
    </div>
  )
}

function RulesSupportCallout({ card }: { card: CardSummary }) {
  if (!rulesSupportNeedsNotice(card)) {
    return null
  }

  const details = rulesSupportDetails(card)

  return (
    <div className="mt-3 rounded-lg border border-attention/25 bg-attention/10 px-2.5 py-2 text-xs leading-5 text-attention">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-semibold">{card.rulesLabel}</p>
        <StatusBadge tone={rulesSupportTone(card)}>{formatEventType(card.rulesStatus)}</StatusBadge>
      </div>
      <p className="mt-1 text-attention/90">{card.rulesNote}</p>
      {details.length > 0 ? (
        <p className="mt-1 font-medium text-attention/90">{details.join(' · ')}</p>
      ) : null}
      {card.unsupportedActions.length > 0 ? <UnsupportedCardActionList actions={card.unsupportedActions} /> : null}
    </div>
  )
}

function UnsupportedCardActionList({ actions }: { actions: UnsupportedCardAction[] }) {
  return (
    <ul className="mt-2 space-y-1.5">
      {actions.map((action, index) => (
        <li className="rounded-md bg-background/45 px-2 py-1.5" key={`${action.kind}-${action.id ?? index}-${action.name}`}>
          <p className="font-semibold text-attention">{unsupportedCardActionTitle(action)}</p>
          <p className="mt-0.5 text-attention/85">{unsupportedCardActionDetail(action)}</p>
        </li>
      ))}
    </ul>
  )
}

function unsupportedCardActionTitle(action: UnsupportedCardAction) {
  return `${formatEventType(action.kind)} · ${action.name}`
}

function unsupportedCardActionDetail(action: UnsupportedCardAction) {
  const attackMeta = action.kind === 'attack'
    ? ` ${attackCostSummary(action.cost)}, ${attackDamageSummary(action.damage)}.`
    : ''
  const cardText = action.text ? ` Text: ${action.text}` : ''

  return `${action.reason}${attackMeta}${cardText}`
}

function RulesSupportBadge({ card, compact = false }: { card: CardSummary; compact?: boolean }) {
  if (!rulesSupportNeedsNotice(card)) {
    return null
  }

  const className = compact
    ? 'mt-1 inline-flex rounded-full bg-attention/12 px-2 py-0.5 text-[0.62rem] font-semibold uppercase tracking-[0.1em] text-attention'
    : 'inline-flex rounded-full bg-attention/12 px-2 py-0.5 text-xs font-semibold text-attention'

  return <span className={className}>{card.rulesLabel}</span>
}

function rulesSupportNeedsNotice(card: CardSummary) {
  return ['partial', 'unsupported', 'unknown'].includes(card.rulesStatus)
}

function rulesSupportTone(card: CardSummary): 'active' | 'neutral' | 'warning' {
  return card.rulesStatus === 'engine_defined' || card.rulesStatus === 'generic' ? 'active' : 'warning'
}

function rulesSupportCounts(cards: CardSummary[]) {
  return cards.reduce(
    (counts, card) => {
      if (card.rulesStatus === 'unsupported' || card.rulesStatus === 'unknown') {
        return { ...counts, total: counts.total + 1, unsupported: counts.unsupported + 1 }
      }

      if (card.rulesStatus === 'partial') {
        return { ...counts, total: counts.total + 1, partial: counts.partial + 1 }
      }

      return counts
    },
    { partial: 0, total: 0, unsupported: 0 }
  )
}

function rulesSupportDetails(card: CardSummary) {
  return [
    card.executableAttackCount > 0 ? `${card.executableAttackCount} executable attacks` : null,
    card.unsupportedAttackCount > 0 ? `${card.unsupportedAttackCount} unsupported attacks` : null,
    card.unsupportedAbilityCount > 0 ? `${card.unsupportedAbilityCount} unsupported abilities` : null
  ].filter((detail): detail is string => Boolean(detail))
}

function CardIntentDetail({ intent }: { intent: CardIntent }) {
  return (
    <span className="mt-3 block rounded-lg bg-primary/12 px-2.5 py-2 text-xs font-medium leading-5 text-primary">
      {intent.pending ? 'Resolving...' : intent.detail}
    </span>
  )
}

function CardIntentBadge({ intent, compact = false }: { intent: CardIntent; compact?: boolean }) {
  const className =
    intent.tone === 'warning'
      ? 'bg-attention text-primary-foreground'
      : intent.tone === 'secondary'
        ? 'bg-muted text-foreground'
        : 'bg-primary text-primary-foreground'

  return (
    <span
      className={`absolute right-2 top-2 rounded-full px-2 py-0.5 font-semibold shadow-sm shadow-black/25 ${
        compact ? 'text-[0.62rem]' : 'text-[0.68rem]'
      } ${className}`}
    >
      {intent.pending ? '...' : intent.badge}
    </span>
  )
}

function cardIntentClassName(intent: CardIntent) {
  const ringClassName =
    intent.tone === 'warning'
      ? 'ring-attention/70 hover:ring-attention'
      : intent.tone === 'secondary'
        ? 'ring-muted-foreground/55 hover:ring-foreground/70'
        : 'ring-primary/70 hover:ring-primary'

  return `cursor-pointer focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:ring-offset-background disabled:cursor-wait disabled:opacity-70 ${ringClassName}`
}

function CardArt({ card, variant }: { card: CardSummary; variant: CardArtVariant }) {
  const [failed, setFailed] = useState(false)
  const quality = variant === 'active' ? 'high' : 'low'
  const imageSrc = !failed ? cardImageSrc(card, quality) : null
  const artClassName = cardArtClassName(variant)

  return (
    <div className={`relative overflow-hidden rounded-lg bg-muted/55 ring-1 ring-border/50 ${artClassName}`}>
      {imageSrc ? (
        <img
          alt={`${card.name} card image`}
          className="h-full w-full object-contain"
          decoding="async"
          loading={variant === 'active' ? 'eager' : 'lazy'}
          onError={() => setFailed(true)}
          src={imageSrc}
        />
      ) : isEnergyCard(card) ? (
        <EnergyCardFallback card={card} />
      ) : (
        <div className="flex h-full w-full flex-col items-center justify-center gap-1 px-2 text-center">
          <span className="line-clamp-2 text-xs font-medium leading-tight text-foreground">{card.name}</span>
          <span className="font-mono text-[0.62rem] text-muted-foreground">{card.cardId}</span>
        </div>
      )}
    </div>
  )
}

function EnergyCardFallback({ card }: { card: CardSummary }) {
  return (
    <div className={`flex h-full w-full items-center justify-center ${energyCardFallbackClassName(card)}`}>
      <span className="flex h-9 w-9 items-center justify-center rounded-full bg-background/65 font-semibold text-foreground shadow-sm shadow-black/30 ring-1 ring-foreground/10">
        {energySymbol(card)}
      </span>
      <span className="sr-only">{card.name}</span>
    </div>
  )
}

function energyCardFallbackClassName(card: CardSummary) {
  const name = card.name.toLowerCase()

  if (name.includes('fire')) {
    return 'bg-attention/18'
  }

  if (name.includes('water')) {
    return 'bg-sky-100/15'
  }

  if (name.includes('grass')) {
    return 'bg-accent-mint/15'
  }

  if (name.includes('lightning')) {
    return 'bg-yellow-100/15'
  }

  if (name.includes('psychic')) {
    return 'bg-fuchsia-100/15'
  }

  if (name.includes('fighting')) {
    return 'bg-orange-100/15'
  }

  if (name.includes('darkness')) {
    return 'bg-muted/75'
  }

  return 'bg-secondary/80'
}

function energySymbol(card: CardSummary) {
  const name = card.name.toLowerCase()

  if (name.includes('fire')) return 'R'
  if (name.includes('water')) return 'W'
  if (name.includes('grass')) return 'G'
  if (name.includes('lightning')) return 'L'
  if (name.includes('psychic')) return 'P'
  if (name.includes('fighting')) return 'F'
  if (name.includes('darkness')) return 'D'

  return 'E'
}

function cardImageSrc(card: CardSummary, quality: 'high' | 'low') {
  return tcgdexCardImageSrc(card.image, quality) ?? localEnergyCardImageSrc(card)
}

function tcgdexCardImageSrc(image: string | null, quality: 'high' | 'low') {
  if (!image) {
    return null
  }

  if (/\.(?:avif|gif|jpe?g|png|webp)$/i.test(image)) {
    return image
  }

  return `${image.replace(/\/+$/, '')}/${quality}.webp`
}

function localEnergyCardImageSrc(card: CardSummary) {
  const match = /^MEE-(\d{3})$/.exec(card.cardId)

  return match ? `/tcg/cards/limitless/MEE/MEE_${match[1]}_R_EN_SM.png` : null
}

function cardArtClassName(variant: CardArtVariant) {
  switch (variant) {
    case 'active':
      return 'aspect-[63/88] w-full max-w-[8.5rem] justify-self-center sm:justify-self-start'
    case 'choice':
      return 'aspect-[63/88] w-12 shrink-0'
    case 'hand':
      return 'aspect-[63/88] w-full'
    case 'compact':
      return 'aspect-[63/88] w-full'
    case 'default':
      return 'aspect-[63/88] w-full'
  }
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
    <div className="mt-3 rounded-lg bg-muted/70 px-2.5 py-2">
      <p className="text-xs font-medium uppercase tracking-[0.12em] text-muted-foreground">{title}</p>
      <div className="mt-2 flex flex-wrap gap-1.5">
        {cards.map(attachedCard => (
          <span
            className="rounded-full bg-secondary/80 px-2 py-1 text-xs font-medium text-muted-foreground"
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
    <div className="min-w-0 rounded-xl bg-secondary/70 p-3">
      <p className="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">{label}</p>
      <p className={`mt-2 truncate text-sm font-semibold text-foreground ${mono ? 'font-mono' : ''}`}>
        {value}
      </p>
    </div>
  )
}

function StateRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 rounded-xl bg-secondary/65 px-3 py-2 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="text-right font-medium text-foreground">{value}</span>
    </div>
  )
}

function resolutionChecklistItemClassName(tone: ResolutionChecklistTone) {
  switch (tone) {
    case 'blocked':
      return 'border-destructive/35 bg-destructive/10 text-destructive'
    case 'ready':
      return 'border-accent-mint/30 bg-accent-mint/10 text-accent-mint'
    case 'waiting':
      return 'border-attention/35 bg-attention/10 text-attention'
  }
}

function resolutionChecklistToneClassName(tone: ResolutionChecklistTone) {
  switch (tone) {
    case 'blocked':
      return 'bg-destructive/15 text-destructive'
    case 'ready':
      return 'bg-accent-mint/15 text-accent-mint'
    case 'waiting':
      return 'bg-attention/15 text-attention'
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
      ? 'bg-accent-mint/12 text-accent-mint'
      : tone === 'warning'
        ? 'bg-attention/12 text-attention'
        : 'bg-muted/70 text-muted-foreground'

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
      ? 'bg-destructive/10 text-destructive'
      : 'bg-muted/70 text-muted-foreground'

  return (
    <div className={`rounded-2xl p-4 ${className}`}>
      <p className="text-sm font-semibold">{title}</p>
      <div className="mt-1 text-sm leading-6">{children}</div>
    </div>
  )
}

function CommandErrorCard({ notice }: { notice: CommandErrorNotice }) {
  return (
    <div className="rounded-2xl bg-destructive/10 p-3 text-destructive" role="alert">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold">{notice.title}</p>
          <p className="mt-1 text-sm leading-6 text-destructive/90">{notice.message}</p>
        </div>
        <span className="rounded-full bg-destructive/15 px-2 py-0.5 text-xs font-semibold text-destructive">not applied</span>
      </div>
      <div className="mt-3 rounded-xl bg-background/60 px-3 py-2 text-xs leading-5 text-muted-foreground">
        <span className="font-semibold text-foreground">Next step:</span> {notice.recovery}
      </div>
    </div>
  )
}

function AvailableGamesPanel({
  games,
  isLoading,
  loadError,
  onChooseGame,
  viewerPlayerId
}: {
  games: AvailableGame[]
  isLoading: boolean
  loadError: unknown
  onChooseGame: (gameId: string) => void
  viewerPlayerId: PlayerId
}) {
  if (isLoading) {
    return (
      <Panel title="Available games" trailing={<StatusBadge tone="warning">loading</StatusBadge>}>
        <SkeletonLines count={6} />
      </Panel>
    )
  }

  if (loadError) {
    return (
      <Panel title="Available games" trailing={<StatusBadge tone="warning">unavailable</StatusBadge>}>
        <InlineNotice tone="error" title="Game list did not load">
          {errorMessage(loadError)} Refresh the page or create a new board from the left rail.
        </InlineNotice>
      </Panel>
    )
  }

  if (games.length === 0) {
    return <EmptyWorkbench />
  }

  return (
    <Panel title="Available games" trailing={<StatusBadge tone="active">{games.length}</StatusBadge>}>
      <div className="space-y-3">
        <p className="text-sm leading-6 text-muted-foreground">
          Pick a persisted board to open as {formatPlayerId(viewerPlayerId)}. Refreshing this page will reuse the URL and refetch the same viewer state.
        </p>

        <ol className="space-y-2">
          {games.map(game => (
            <li className="rounded-2xl bg-secondary/60 p-3" key={game.id}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-medium text-foreground">{formatGameId(game.id)}</p>
                  <p className="mt-1 text-sm text-muted-foreground">
                    {formatEventType(game.status)}, {formatEventType(game.flowState)}
                  </p>
                </div>
                <StatusBadge tone={game.status === 'in_progress' ? 'active' : 'neutral'}>
                  {game.status === 'finished' && game.winnerPlayerId
                    ? `${formatPlayerId(game.winnerPlayerId)} won`
                    : `cursor ${game.cursorIndex}/${game.latestEventIndex}`}
                </StatusBadge>
              </div>

              <div className="mt-3 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                <span>{formatPlayerId(game.activePlayerId)} active</span>
                <span className="h-1 w-1 rounded-full bg-muted-foreground/45" />
                <span>{formatPlayerId(game.firstPlayerId)} went first</span>
              </div>

              <button
                className="mt-3 rounded-xl bg-secondary px-3 py-2 text-sm font-medium text-foreground transition hover:bg-accent hover:text-accent-foreground focus:outline-none focus:ring-2 focus:ring-ring/50"
                onClick={() => onChooseGame(game.id)}
                type="button"
              >
                Open board
              </button>
            </li>
          ))}
        </ol>
      </div>
    </Panel>
  )
}

function EmptyWorkbench() {
  return (
    <div className="prizmo-panel grid min-h-[32rem] place-items-center rounded-3xl p-8 text-center">
      <div className="max-w-md">
        <p className="text-sm font-semibold uppercase tracking-[0.22em] text-primary">No game selected</p>
        <h2 className="mt-3 text-2xl font-bold tracking-tight text-foreground">
          Create a game board or open one from the list
        </h2>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">
          Paste two catalog-backed decklists or switch to a fixture shortcut, then create a persisted board. Existing boards appear here whenever the server still has them.
        </p>
        <div className="mt-6 rounded-2xl bg-secondary/65 px-4 py-3 text-left text-sm text-muted-foreground">
          <p className="font-medium text-foreground">Next action</p>
          <p className="mt-1 leading-6">Use the left rail to create a board, or pick one from the game list when it is available.</p>
        </div>
      </div>
    </div>
  )
}

function GameStateLoadingPanel({ gameId, viewerPlayerId }: { gameId: string; viewerPlayerId: PlayerId }) {
  return (
    <Panel title="Catching up board" trailing={<StatusBadge tone="warning">loading</StatusBadge>}>
      <div className="space-y-4">
        <div className="rounded-2xl bg-secondary/70 p-4">
          <p className="text-sm font-semibold text-foreground">Requesting {formatPlayerId(viewerPlayerId)}'s view</p>
          <p className="mt-2 text-sm leading-6 text-muted-foreground">
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
    <Panel title="Board unavailable" trailing={<StatusBadge tone="warning">not loaded</StatusBadge>}>
      <div className="space-y-4">
        <div className="rounded-2xl border border-destructive/35 bg-destructive/10 p-4 text-destructive" role="alert">
          <p className="text-sm font-semibold">Game state did not load</p>
          <p className="mt-2 text-sm leading-6 text-destructive/90">{errorMessage(error)}</p>
          <div className="mt-3 rounded-xl border border-destructive/20 bg-background/60 px-3 py-2 text-xs leading-5 text-muted-foreground">
            <span className="font-semibold text-foreground">Next step:</span> Confirm the game ID still exists and this tab is
            using the intended player seat, then retry the board request.
          </div>
        </div>

        <div className="grid gap-2 rounded-2xl bg-secondary/70 p-3 sm:grid-cols-2">
          <StateRow label="Game" value={formatGameId(gameId)} />
          <StateRow label="Viewer" value={formatPlayerId(viewerPlayerId)} />
        </div>

        <div className="flex flex-col gap-2 sm:flex-row">
          <button
            className="rounded-xl bg-primary px-4 py-2.5 text-sm font-semibold text-primary-foreground shadow-sm shadow-black/20 transition hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:ring-offset-background disabled:cursor-not-allowed disabled:bg-muted disabled:text-muted-foreground"
            disabled={isRetrying}
            onClick={onRetry}
            type="button"
          >
            {isRetrying ? 'Retrying board...' : 'Retry board'}
          </button>
          <button
            className="rounded-xl border border-border px-4 py-2.5 text-sm font-medium text-muted-foreground transition hover:bg-accent hover:text-accent-foreground focus:outline-none focus:ring-2 focus:ring-ring/50"
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
        <div className="rounded-2xl border border-attention/35 bg-attention/10 p-4 text-attention">
          <p className="text-sm font-semibold">Waiting for the current tab seat</p>
          <p className="mt-2 text-sm leading-6 text-attention/90">
            The engine returned {formatPlayerId(actualViewerPlayerId)} state after this tab asked for{' '}
            {formatPlayerId(expectedViewerPlayerId)}. The board is hidden so private hand data cannot flash in the
            wrong seat.
          </p>
        </div>

        <div className="grid gap-2 rounded-2xl bg-secondary/70 p-3 sm:grid-cols-2">
          <StateRow label="Returned" value={formatPlayerId(actualViewerPlayerId)} />
          <StateRow label="This tab" value={formatPlayerId(expectedViewerPlayerId)} />
        </div>

        <button
          className="rounded-xl border border-border px-4 py-2.5 text-sm font-medium text-muted-foreground transition hover:bg-accent hover:text-accent-foreground focus:outline-none focus:ring-2 focus:ring-ring/50 disabled:cursor-not-allowed disabled:text-text-dim"
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
    <div className="rounded-xl bg-secondary/70 px-3 py-4">
      <p className="text-sm font-medium text-foreground">{title}</p>
      <p className="mt-2 text-sm leading-6 text-muted-foreground">{children}</p>
    </div>
  )
}

function EmptyState({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl bg-secondary/45 px-4 py-8 text-center">
      <p className="text-sm font-medium text-foreground">{title}</p>
      <p className="mt-2 text-sm leading-6 text-muted-foreground">{children}</p>
    </div>
  )
}

function SkeletonLines({ count }: { count: number }) {
  return (
    <div className="space-y-2" role="status">
      {Array.from({ length: count }).map((_, index) => (
        <div className="h-10 animate-pulse rounded-xl bg-muted" key={index} />
      ))}
      <span className="sr-only">Loading</span>
    </div>
  )
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
