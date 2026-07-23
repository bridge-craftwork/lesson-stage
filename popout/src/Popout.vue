<script setup>
import { computed, onMounted, ref } from 'vue'
import HandDisplay from './vendor/components/HandDisplay.vue'
import TrickArea from './vendor/components/TrickArea.vue'
import {
  computeRemaining,
  getLegalCards,
  isLegalPlay,
  nextSeatToPlay,
  trickWinner,
  trumpFromContract,
} from './vendor/utils/cardplayRules.js'
import { RANK_ORDER, SUIT_ORDER } from './vendor/utils/cardFormatting.js'
import { DEMO_DEAL } from './deal.js'

const SEATS = ['N', 'E', 'S', 'W']
const SUIT_KEY = { S: 'spades', H: 'hearts', D: 'diamonds', C: 'clubs' }

const deal = ref(DEMO_DEAL)

// The whole of play state: an ordered list of plays. Everything else is
// derived from it, which is what makes stepping back a truncation rather
// than an undo stack.
const played = ref([])

const trump = computed(() => trumpFromContract(deal.value.contract))

/** Group the flat play list into tricks, threading each winner into the next leader. */
const tricks = computed(() => {
  const completedTricks = []
  let leader = deal.value.openingLeader
  let i = 0
  while (i + 4 <= played.value.length) {
    const plays = played.value.slice(i, i + 4)
    const winner = trickWinner(plays, trump.value)
    completedTricks.push({ leader, plays, winner })
    leader = winner
    i += 4
  }
  return {
    completedTricks,
    currentTrick: { leader, plays: played.value.slice(i) },
  }
})

const remaining = computed(() => computeRemaining(deal.value.hands, played.value))

const nextSeat = computed(() =>
  nextSeatToPlay(tricks.value, trump.value, deal.value.openingLeader)
)

const tricksTaken = computed(() => {
  const taken = { NS: 0, EW: 0 }
  for (const t of tricks.value.completedTricks) {
    if (t.winner === 'N' || t.winner === 'S') taken.NS++
    else taken.EW++
  }
  return taken
})

/** Flat [{suit,rank}] back into the suit-keyed hand shape HandDisplay expects. */
function cardsToHand(cards) {
  const hand = { spades: [], hearts: [], diamonds: [], clubs: [] }
  for (const c of cards) hand[SUIT_KEY[c.suit]].push(c.rank)
  for (const suit of SUIT_ORDER) {
    hand[suit].sort((a, b) => RANK_ORDER.indexOf(a) - RANK_ORDER.indexOf(b))
  }
  return hand
}

const handsToShow = computed(() => {
  const out = {}
  for (const seat of SEATS) out[seat] = cardsToHand(remaining.value[seat])
  return out
})

const status = ref('')

function play(seat, { suit, rank }) {
  if (seat !== nextSeat.value) {
    status.value = `${nextSeat.value} is to play, not ${seat}.`
    return
  }
  const currentPlays = tricks.value.currentTrick.plays
  if (!isLegalPlay({ suit, rank }, remaining.value[seat], currentPlays)) {
    const legal = getLegalCards(remaining.value[seat], currentPlays)
    status.value = `Must follow suit — ${legal.length} legal card${legal.length === 1 ? '' : 's'}.`
    return
  }
  played.value = [...played.value, { seat, suit, rank }]
  status.value = ''
}

/** Step back one trick: truncate to the last trick boundary. */
function backATrick() {
  const boundary = Math.max(0, (Math.ceil(played.value.length / 4) - 1) * 4)
  played.value = played.value.slice(0, boundary)
  status.value = ''
}

function reset() {
  played.value = []
  status.value = ''
}

// ---- The seam -------------------------------------------------------------
// Native owns PDFs, taps and bytes; it posts a payload in and knows nothing
// about what a trick is. Everything crossing here is plain JSON — no live
// object may span the boundary.

const seam = ref('waiting for native…')

/** Called by native via evaluateJavaScript. */
function load(payload) {
  if (payload?.deal) deal.value = payload.deal
  played.value = payload?.plays ?? []
  status.value = ''
  seam.value = `received ${payload?.kind ?? 'payload'} from native`
}

function toNative(message) {
  window.webkit?.messageHandlers?.popout?.postMessage(message)
}

onMounted(() => {
  window.lessonStage = { load }
  // JS → native: the popout announces it is mounted and ready for a payload.
  // Native cannot know this from `didFinish` alone, which fires before Vue
  // has mounted.
  toNative({ type: 'ready' })
})
</script>

<template>
  <div class="popout">
    <header>
      <span class="contract">{{ deal.contract }} by {{ deal.declarer }}</span>
      <span class="dim">
        {{ tricks.completedTricks.length }}
        {{ tricks.completedTricks.length === 1 ? 'trick' : 'tricks' }} played
      </span>
      <span class="spacer" />
      <button :disabled="!played.length" @click="backATrick">Back a trick</button>
      <button :disabled="!played.length" @click="reset">Reset</button>
    </header>

    <!-- Each seat is labelled as a group so a test (or a screen reader) can
         address one hand. The vendored components carry no such hooks and
         must not be edited to add them, so the wrapper supplies them. -->
    <div class="table">
      <div class="seat north" role="group" aria-label="North hand">
        <span class="label">N</span>
        <HandDisplay
          :hand="handsToShow.N"
          show-hcp
          :clickable="nextSeat === 'N'"
          @card-click="play('N', $event)"
        />
      </div>

      <div class="middle">
        <div class="seat west" role="group" aria-label="West hand">
          <span class="label">W</span>
          <HandDisplay
            :hand="handsToShow.W"
            show-hcp
            :clickable="nextSeat === 'W'"
            @card-click="play('W', $event)"
          />
        </div>

        <TrickArea
          :current-trick="tricks.currentTrick"
          :tricks-taken="tricksTaken"
          :next-seat="nextSeat"
        />

        <div class="seat east" role="group" aria-label="East hand">
          <span class="label">E</span>
          <HandDisplay
            :hand="handsToShow.E"
            show-hcp
            :clickable="nextSeat === 'E'"
            @card-click="play('E', $event)"
          />
        </div>
      </div>

      <div class="seat south" role="group" aria-label="South hand">
        <span class="label">S</span>
        <HandDisplay
          :hand="handsToShow.S"
          show-hcp
          :clickable="nextSeat === 'S'"
          @card-click="play('S', $event)"
        />
      </div>
    </div>

    <footer :class="{ warn: !!status }">
      <span>{{ status || `${nextSeat} to play — tap a card` }}</span>
      <span class="spacer" />
      <span class="seam">{{ seam }}</span>
    </footer>
  </div>
</template>

<style scoped>
.popout {
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  padding: 12px 16px;
  box-sizing: border-box;
  gap: 10px;
}

header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding-bottom: 8px;
  border-bottom: 1px solid var(--popout-line);
}

.contract {
  font-weight: 600;
}

.dim {
  color: var(--popout-dim);
}

.spacer {
  flex: 1;
}

button {
  font: inherit;
  color: var(--popout-fg);
  background: #fff;
  border: 1px solid var(--popout-line);
  border-radius: 7px;
  padding: 5px 11px;
}

button:disabled {
  opacity: 0.4;
}

.table {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 14px;
  flex: 1;
}

.middle {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 28px;
}

.seat {
  display: flex;
  align-items: flex-start;
  gap: 8px;
}

.label {
  color: var(--popout-dim);
  font-weight: 600;
  width: 1em;
}

footer {
  display: flex;
  align-items: center;
  gap: 12px;
  color: var(--popout-dim);
  border-top: 1px solid var(--popout-line);
  padding-top: 8px;
}

.seam {
  font-size: 13px;
  opacity: 0.8;
}

footer.warn {
  color: #b45309;
}
</style>
