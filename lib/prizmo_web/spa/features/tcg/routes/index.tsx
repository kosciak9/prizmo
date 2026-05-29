import { useEffect, useMemo, useState } from 'react'

import type { Channel } from 'phoenix'

import {
  type ActionPayload,
  type CardInstance,
  type GamePayload,
  type GameStateView,
  type PlayerView,
  type TcgDeck,
  join,
  joinChannel,
  push
} from '@/features/tcg/api/channel'

type LobbyJoinPayload = { decks: TcgDeck[] }

const firstAction = JSON.stringify({ type: 'start_setup', params: {} }, null, 2)

export function TcgRoute() {
  const [lobby, setLobby] = useState<Channel | null>(null)
  const [gameChannel, setGameChannel] = useState<Channel | null>(null)
  const [decks, setDecks] = useState<TcgDeck[]>([])
  const [player1DeckId, setPlayer1DeckId] = useState('')
  const [player2DeckId, setPlayer2DeckId] = useState('')
  const [game, setGame] = useState<GamePayload | null>(null)
  const [actionJson, setActionJson] = useState(firstAction)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    const channel = joinChannel('tcg:lobby')
    let active = true

    join<LobbyJoinPayload>(channel)
      .then((payload) => {
        if (!active) return
        setLobby(channel)
        setDecks(payload.decks)
        setPlayer1DeckId(payload.decks[0]?.id ?? '')
        setPlayer2DeckId(payload.decks[1]?.id ?? payload.decks[0]?.id ?? '')
      })
      .catch((reason) => setError(formatError(reason)))

    return () => {
      active = false
      channel.leave()
    }
  }, [])

  useEffect(() => {
    if (!gameChannel) return

    const ref = gameChannel.on('state_updated', (payload: GamePayload) => setGame(payload))

    return () => gameChannel.off('state_updated', ref)
  }, [gameChannel])

  const selectedNames = useMemo(() => {
    const byId = new Map(decks.map((deck) => [deck.id, deck.name]))
    return {
      player1: byId.get(player1DeckId) ?? player1DeckId,
      player2: byId.get(player2DeckId) ?? player2DeckId
    }
  }, [decks, player1DeckId, player2DeckId])

  async function startGame() {
    if (!lobby || !player1DeckId || !player2DeckId) return

    setBusy(true)
    setError(null)

    try {
      const created = await push<GamePayload>(lobby, 'create_game', { player1DeckId, player2DeckId })
      const channel = joinChannel(`tcg_game:${created.gameId}`)
      const joined = await join<GamePayload>(channel)
      setGameChannel(channel)
      setGame(joined)
      setActionJson(firstAction)
    } catch (reason) {
      setError(formatError(reason))
    } finally {
      setBusy(false)
    }
  }

  async function submitAction() {
    if (!gameChannel) return

    setBusy(true)
    setError(null)

    try {
      const parsed = JSON.parse(actionJson) as ActionPayload
      const response = await push<GamePayload>(gameChannel, 'submit_action', parsed as unknown as Record<string, unknown>)
      setGame(response)
    } catch (reason) {
      setError(formatError(reason))
    } finally {
      setBusy(false)
    }
  }

  async function runAction(action: ActionPayload) {
    if (!gameChannel) return

    setBusy(true)
    setError(null)
    setActionJson(JSON.stringify(action, null, 2))

    try {
      const response = await push<GamePayload>(gameChannel, 'submit_action', action as unknown as Record<string, unknown>)
      setGame(response)
    } catch (reason) {
      setError(formatError(reason))
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="min-h-screen bg-stone-50 text-stone-950">
      <div className="border-b border-stone-200 bg-stone-100/80 px-5 py-4">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-emerald-700">Prizmo TCG</p>
            <h1 className="mt-1 text-2xl font-semibold tracking-tight">Rough playable table</h1>
          </div>
          <div className="flex flex-wrap items-end gap-3">
            <DeckSelect label="Player 1" value={player1DeckId} decks={decks} onChange={setPlayer1DeckId} />
            <DeckSelect label="Player 2" value={player2DeckId} decks={decks} onChange={setPlayer2DeckId} />
            <button
              className="rounded-lg bg-emerald-700 px-4 py-2 text-sm font-semibold text-stone-50 shadow-sm hover:bg-emerald-800 disabled:cursor-not-allowed disabled:bg-stone-300"
              disabled={busy || !lobby || !player1DeckId || !player2DeckId}
              type="button"
              onClick={startGame}
            >
              {busy ? 'Working…' : 'Start game'}
            </button>
          </div>
        </div>
        <p className="mt-3 max-w-4xl text-sm text-stone-600">
          Click through setup and use card buttons for common choices. The JSON box stays as an advanced escape hatch for engine actions that do not have controls yet.
        </p>
      </div>

      {error && <div className="border-b border-red-200 bg-red-50 px-5 py-3 text-sm text-red-800">{error}</div>}

      <div className="grid gap-4 p-4 xl:grid-cols-[minmax(0,1fr)_420px]">
        <section className="min-w-0">
          {game ? (
            <Board state={game.state} busy={busy} player1Name={selectedNames.player1} player2Name={selectedNames.player2} onAction={runAction} />
          ) : (
            <EmptyTable />
          )}
        </section>

        <aside className="space-y-4">
          {game && <QuickActions state={game.state} busy={busy} onAction={runAction} />}
          <ActionPanel actionJson={actionJson} busy={busy} disabled={!gameChannel} onChange={setActionJson} onSubmit={submitAction} />
          {game && <DebugPanel game={game} />}
        </aside>
      </div>
    </main>
  )
}

function DeckSelect(props: { label: string; value: string; decks: TcgDeck[]; onChange: (value: string) => void }) {
  return (
    <label className="grid gap-1 text-xs font-medium text-stone-600">
      {props.label}
      <select
        className="w-56 rounded-lg border border-stone-300 bg-stone-50 px-3 py-2 text-sm text-stone-950 shadow-sm focus:border-emerald-600 focus:outline-none focus:ring-2 focus:ring-emerald-200"
        value={props.value}
        onChange={(event) => props.onChange(event.target.value)}
      >
        {props.decks.map((deck) => (
          <option key={deck.id} value={deck.id}>
            {deck.name} ({deck.id})
          </option>
        ))}
      </select>
    </label>
  )
}

function Board(props: {
  state: GameStateView
  busy: boolean
  player1Name: string
  player2Name: string
  onAction: (action: ActionPayload) => void
}) {
  const player1 = props.state.players.player1
  const player2 = props.state.players.player2

  return (
    <div className="space-y-4">
      <LifecycleStrip state={props.state} />
      {player2 && <PlayerArea player={player2} state={props.state} busy={props.busy} label={`Player 2 · ${props.player2Name}`} opponent onAction={props.onAction} />}
      <div className="grid gap-4 rounded-2xl border border-stone-200 bg-stone-100 p-4 md:grid-cols-[1fr_180px_1fr]">
        <Zone title="Player 2 discard" cards={player2?.discard ?? []} compact />
        <div className="rounded-xl border border-dashed border-stone-300 bg-stone-50 p-3 text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-stone-500">Stadium</p>
          <div className="mt-3 flex justify-center">{props.state.stadium ? <CardTile card={props.state.stadium} compact /> : <FaceDown label="No stadium" />}</div>
        </div>
        <Zone title="Player 1 discard" cards={player1?.discard ?? []} compact />
      </div>
      {player1 && <PlayerArea player={player1} state={props.state} busy={props.busy} label={`Player 1 · ${props.player1Name}`} onAction={props.onAction} />}
    </div>
  )
}

function LifecycleStrip({ state }: { state: GameStateView }) {
  return (
    <div className="grid gap-2 rounded-2xl border border-stone-200 bg-stone-100 p-3 text-sm md:grid-cols-5">
      <Stat label="Game" value={state.gameLifecycle} />
      <Stat label="Turn" value={String(state.turnNumber)} />
      <Stat label="Turn phase" value={state.turnLifecycle} />
      <Stat label="Active" value={state.activePlayer ?? 'none'} />
      <Stat label="Prompt" value={state.promptLifecycle} />
    </div>
  )
}

function PlayerArea({
  player,
  state,
  busy,
  label,
  opponent = false,
  onAction
}: {
  player: PlayerView
  state: GameStateView
  busy: boolean
  label: string
  opponent?: boolean
  onAction: (action: ActionPayload) => void
}) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-stone-100 p-4 shadow-sm">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h2 className="font-semibold">{label}</h2>
        <div className="flex gap-2 text-xs text-stone-600">
          <Badge>Deck {player.deckCount}</Badge>
          <Badge>Prizes {player.prizeCount}</Badge>
          <Badge>Discard {player.discardCount}</Badge>
        </div>
      </div>
      <div className="grid gap-4 lg:grid-cols-[150px_240px_minmax(0,1fr)]">
        <div className="space-y-3">
          <Zone title="Active" cards={player.active ? [player.active] : []} empty="No active" />
          <div className="grid grid-cols-2 gap-2">
            <FaceDown label={`Deck ${player.deckCount}`} />
            <FaceDown label={`Prizes ${player.prizeCount}`} />
          </div>
        </div>
        <Zone title="Bench" cards={player.bench} empty="No benched Pokémon" compact />
        <Zone title={opponent ? 'Hand' : 'Hand'} cards={player.hand} empty="No cards in hand" player={player} state={state} busy={busy} onAction={onAction} />
      </div>
    </section>
  )
}

function Zone({
  title,
  cards,
  empty = 'Empty',
  compact = false,
  player,
  state,
  busy = false,
  onAction
}: {
  title: string
  cards: CardInstance[]
  empty?: string
  compact?: boolean
  player?: PlayerView
  state?: GameStateView
  busy?: boolean
  onAction?: (action: ActionPayload) => void
}) {
  return (
    <div className="min-w-0 rounded-xl border border-stone-200 bg-stone-50 p-3">
      <div className="mb-2 flex items-center justify-between gap-2">
        <h3 className="text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">{title}</h3>
        <span className="text-xs text-stone-500">{cards.length}</span>
      </div>
      {cards.length > 0 ? (
        <div className={compact ? 'flex gap-2 overflow-x-auto' : 'flex min-h-36 gap-2 overflow-x-auto pb-1'}>
          {cards.map((card) => (
            <CardTile key={card.instanceId} card={card} compact={compact} player={player} state={state} busy={busy} onAction={onAction} />
          ))}
        </div>
      ) : (
        <div className="grid min-h-24 place-items-center rounded-lg border border-dashed border-stone-300 text-xs text-stone-500">{empty}</div>
      )}
    </div>
  )
}

function CardTile({
  card,
  compact = false,
  player,
  state,
  busy = false,
  onAction
}: {
  card: CardInstance
  compact?: boolean
  player?: PlayerView
  state?: GameStateView
  busy?: boolean
  onAction?: (action: ActionPayload) => void
}) {
  const width = compact ? 'w-20' : 'w-28'
  const setupHandActions = player && state && onAction && card.zone === 'hand' && state.gameLifecycle === 'setup'
  const canChooseActive = setupHandActions && !player.active && isBasicPokemon(card)
  const canBench = setupHandActions && player.bench.length < 5 && isBasicPokemon(card)

  return (
    <article className={`shrink-0 ${width}`} title={`${card.card.name} · ${card.instanceId}`}>
      {card.card.imageLow ? (
        <img className="w-full rounded-md border border-stone-300 bg-stone-200 shadow-sm" src={card.card.imageLow} alt={card.card.name} loading="lazy" />
      ) : (
        <div className="grid aspect-[5/7] place-items-center rounded-md border border-stone-300 bg-stone-200 p-2 text-center text-xs font-semibold text-stone-700">
          <span>{card.card.name}</span>
        </div>
      )}
      <div className="mt-1 space-y-1 text-[11px] leading-tight text-stone-600">
        <p className="truncate font-medium text-stone-800">{card.card.name}</p>
        <p className="truncate">{card.cardId}</p>
        {(card.damage > 0 || card.status) && <p className="font-semibold text-red-700">{card.damage} dmg {card.status}</p>}
        {card.attachments.length > 0 && <p>{card.attachments.length} attached</p>}
      </div>
      {(canChooseActive || canBench) && (
        <div className="mt-2 grid gap-1">
          {canChooseActive && (
            <button
              className="rounded-md bg-emerald-700 px-2 py-1 text-[11px] font-semibold text-stone-50 hover:bg-emerald-800 disabled:bg-stone-300"
              disabled={busy}
              type="button"
              onClick={() => onAction({ type: 'choose_active_from_hand', playerId: player.id, params: { instanceId: card.instanceId } })}
            >
              Active
            </button>
          )}
          {canBench && (
            <button
              className="rounded-md border border-stone-300 bg-stone-50 px-2 py-1 text-[11px] font-semibold text-stone-700 hover:bg-stone-200 disabled:bg-stone-100 disabled:text-stone-400"
              disabled={busy}
              type="button"
              onClick={() => onAction({ type: 'choose_setup_bench_from_hand', playerId: player.id, params: { instanceId: card.instanceId } })}
            >
              Bench
            </button>
          )}
        </div>
      )}
    </article>
  )
}

function QuickActions({ state, busy, onAction }: { state: GameStateView; busy: boolean; onAction: (action: ActionPayload) => void }) {
  const activePlayer = state.activePlayer ?? 'player1'
  const setupReady = state.gameLifecycle === 'setup'
  const inProgress = state.gameLifecycle === 'in_progress'

  return (
    <section className="rounded-2xl border border-stone-200 bg-stone-100 p-4 shadow-sm">
      <h2 className="font-semibold">Click actions</h2>
      <div className="mt-3 grid grid-cols-2 gap-2 text-sm">
        <ActionButton disabled={busy || state.gameLifecycle !== 'not_started'} onClick={() => onAction({ type: 'start_setup', params: {} })}>
          Start setup
        </ActionButton>
        <ActionButton disabled={busy || !setupReady} onClick={() => onAction({ type: 'draw_opening_hand', params: {} })}>
          Draw hands
        </ActionButton>
        <ActionButton disabled={busy || !setupReady} onClick={() => onAction({ type: 'place_prizes', params: {} })}>
          Place prizes
        </ActionButton>
        <ActionButton disabled={busy || !setupReady} onClick={() => onAction({ type: 'complete_setup', params: {} })}>
          Complete setup
        </ActionButton>
        <ActionButton disabled={busy || !inProgress} onClick={() => onAction({ type: 'draw_for_turn', playerId: activePlayer, params: {} })}>
          Draw turn
        </ActionButton>
        <ActionButton disabled={busy || !inProgress} onClick={() => onAction({ type: 'open_action_window', params: {} })}>
          Open actions
        </ActionButton>
        <ActionButton disabled={busy || !inProgress} onClick={() => onAction({ type: 'end_turn', playerId: activePlayer, params: {} })}>
          End turn
        </ActionButton>
        <ActionButton disabled={busy || !inProgress} onClick={() => onAction({ type: 'start_next_turn', params: {} })}>
          Next turn
        </ActionButton>
      </div>
      <p className="mt-3 text-xs text-stone-600">During setup, each Basic Pokémon in hand gets Active and Bench buttons.</p>
    </section>
  )
}

function ActionButton(props: { children: React.ReactNode; disabled: boolean; onClick: () => void }) {
  return (
    <button className="rounded-lg border border-stone-300 bg-stone-50 px-3 py-2 font-semibold text-stone-800 hover:bg-stone-200 disabled:cursor-not-allowed disabled:bg-stone-100 disabled:text-stone-400" type="button" disabled={props.disabled} onClick={props.onClick}>
      {props.children}
    </button>
  )
}

function ActionPanel(props: { actionJson: string; busy: boolean; disabled: boolean; onChange: (value: string) => void; onSubmit: () => void }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-stone-100 p-4 shadow-sm">
      <div className="mb-3 flex items-center justify-between gap-3">
        <h2 className="font-semibold">Submit action JSON</h2>
        <button
          className="rounded-lg bg-stone-900 px-3 py-1.5 text-sm font-semibold text-stone-50 hover:bg-stone-700 disabled:cursor-not-allowed disabled:bg-stone-300"
          disabled={props.busy || props.disabled}
          type="button"
          onClick={props.onSubmit}
        >
          Submit
        </button>
      </div>
      <textarea
        className="h-44 w-full resize-y rounded-xl border border-stone-300 bg-stone-950 p-3 font-mono text-xs leading-relaxed text-emerald-100 shadow-inner focus:border-emerald-600 focus:outline-none focus:ring-2 focus:ring-emerald-200"
        spellCheck={false}
        value={props.actionJson}
        onChange={(event) => props.onChange(event.target.value)}
      />
      <div className="mt-3 grid grid-cols-2 gap-2 text-xs">
        <Preset label="Setup" value={{ type: 'start_setup', params: {} }} onPick={props.onChange} />
        <Preset label="Draw hands" value={{ type: 'draw_opening_hand', params: {} }} onPick={props.onChange} />
        <Preset label="Place prizes" value={{ type: 'place_prizes', params: {} }} onPick={props.onChange} />
        <Preset label="Complete setup" value={{ type: 'complete_setup', params: {} }} onPick={props.onChange} />
      </div>
    </section>
  )
}

function Preset(props: { label: string; value: ActionPayload; onPick: (value: string) => void }) {
  return (
    <button className="rounded-md border border-stone-300 bg-stone-50 px-2 py-1 text-stone-700 hover:bg-stone-200" type="button" onClick={() => props.onPick(JSON.stringify(props.value, null, 2))}>
      {props.label}
    </button>
  )
}

function DebugPanel({ game }: { game: GamePayload }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-stone-100 p-4 shadow-sm">
      <h2 className="font-semibold">Debug state</h2>
      <div className="mt-3 rounded-xl border border-stone-200 bg-stone-50 p-3">
        <h3 className="text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">Log</h3>
        <ol className="mt-2 max-h-32 space-y-1 overflow-auto text-xs text-stone-700">
          {game.state.log.length > 0 ? game.state.log.map((entry, index) => <li key={`${entry}-${index}`}>{entry}</li>) : <li>No log entries yet.</li>}
        </ol>
      </div>
      <pre className="mt-3 max-h-[48rem] overflow-auto rounded-xl bg-stone-950 p-3 text-xs leading-relaxed text-stone-100">{JSON.stringify(game, null, 2)}</pre>
    </section>
  )
}

function EmptyTable() {
  return (
    <div className="grid min-h-[36rem] place-items-center rounded-2xl border border-dashed border-stone-300 bg-stone-100 p-8 text-center">
      <div className="max-w-md">
        <h2 className="text-xl font-semibold">Choose two decks to open a channel game.</h2>
        <p className="mt-2 text-sm text-stone-600">The first slice is intentionally rough: card images, visible zones, raw JSON, and engine actions over WebSockets.</p>
      </div>
    </div>
  )
}

function FaceDown({ label }: { label: string }) {
  return <div className="grid aspect-[5/7] min-h-24 place-items-center rounded-lg border border-stone-300 bg-stone-200 px-2 text-center text-xs font-semibold text-stone-600">{label}</div>
}

function Badge({ children }: { children: React.ReactNode }) {
  return <span className="rounded-full border border-stone-300 bg-stone-50 px-2 py-1">{children}</span>
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl bg-stone-50 px-3 py-2">
      <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-500">{label}</p>
      <p className="mt-1 truncate font-mono text-sm text-stone-900">{value}</p>
    </div>
  )
}

function Code({ children }: { children: React.ReactNode }) {
  return <code className="rounded bg-stone-200 px-1 py-0.5 font-mono text-xs text-stone-800">{children}</code>
}

function formatError(reason: unknown) {
  if (reason instanceof Error) return reason.message
  if (typeof reason === 'string') return reason
  return JSON.stringify(reason)
}

function isBasicPokemon(card: CardInstance) {
  return card.card.supertype === 'pokemon' && card.card.stage === 'basic'
}
