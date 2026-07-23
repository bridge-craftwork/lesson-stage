<template>
  <div class="trick-area" :class="{ inactive: !active }">
    <div v-if="active" class="trick-grid">
      <!-- N -->
      <div class="slot slot-n" :class="{ 'is-next': nextSeat === 'N' }">
        <div class="card" v-if="cardForSeat('N')">
          <span :class="suitClass(cardForSeat('N').suit)">{{ suitSymbol(cardForSeat('N').suit) }}</span>{{ formatRank(cardForSeat('N').rank) }}
        </div>
      </div>
      <!-- W -->
      <div class="slot slot-w" :class="{ 'is-next': nextSeat === 'W' }">
        <div class="card" v-if="cardForSeat('W')">
          <span :class="suitClass(cardForSeat('W').suit)">{{ suitSymbol(cardForSeat('W').suit) }}</span>{{ formatRank(cardForSeat('W').rank) }}
        </div>
      </div>
      <!-- Center: trick counter / bot status -->
      <div class="slot slot-center">
        <div v-if="showCounter" class="counter">NS&nbsp;{{ tricksTaken.NS }} · EW&nbsp;{{ tricksTaken.EW }}</div>
        <div v-if="botLoading" class="bot-thinking">{{ botName ? `${botName} thinking…` : 'Thinking…' }}</div>
        <div v-else-if="lastWinner" class="last-winner">Trick to {{ lastWinner }}</div>
      </div>
      <!-- E -->
      <div class="slot slot-e" :class="{ 'is-next': nextSeat === 'E' }">
        <div class="card" v-if="cardForSeat('E')">
          <span :class="suitClass(cardForSeat('E').suit)">{{ suitSymbol(cardForSeat('E').suit) }}</span>{{ formatRank(cardForSeat('E').rank) }}
        </div>
      </div>
      <!-- S -->
      <div class="slot slot-s" :class="{ 'is-next': nextSeat === 'S' }">
        <div class="card" v-if="cardForSeat('S')">
          <span :class="suitClass(cardForSeat('S').suit)">{{ suitSymbol(cardForSeat('S').suit) }}</span>{{ formatRank(cardForSeat('S').rank) }}
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { SUIT_SYMBOLS, formatCard } from '../utils/cardFormatting.js'

const props = defineProps({
  // { leader, plays: [{ seat, suit, rank }] }
  currentTrick: { type: Object, required: true },
  // Last completed trick — shown briefly between tricks. { leader, plays, winner }
  lastFinishedTrick: { type: Object, default: null },
  tricksTaken: { type: Object, default: () => ({ NS: 0, EW: 0 }) },
  // Show the NS/EW trick counter. Off for the defense/choose-card scenes, which don't
  // track tricks (the count would sit at 0·0 and mislead).
  showCounter: { type: Boolean, default: true },
  // Seat to play next (for visual cue).
  nextSeat: { type: String, default: null },
  botLoading: { type: Boolean, default: false },
  botName: { type: String, default: '' },
  active: { type: Boolean, default: true },
})

// Show the lastFinishedTrick cards if present (during the inter-trick pause),
// otherwise show currentTrick.plays.
const visiblePlays = computed(() => {
  if (props.lastFinishedTrick) return props.lastFinishedTrick.plays
  return props.currentTrick?.plays || []
})

const lastWinner = computed(() => props.lastFinishedTrick?.winner || null)

function cardForSeat(seat) {
  return visiblePlays.value.find(p => p.seat === seat)
}

function suitSymbol(suit) {
  return SUIT_SYMBOLS[suit] || suit
}

// Key on the suit's first letter so both formats colour correctly: the declarer
// engine passes single letters ('H'/'D'), the defense grid trick passes full names
// ('hearts'/'diamonds', via parseCardCode) — the latter was rendering red suits black.
function suitClass(suit) {
  const s = String(suit)[0]?.toUpperCase()
  return (s === 'H' || s === 'D') ? 'suit-red' : 'suit-black'
}

function formatRank(rank) {
  return formatCard(rank)
}
</script>

<style scoped>
.trick-area {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: calc(220px * var(--table-scale));
  padding: 0 calc(8px * var(--table-scale));  /* clearance from adjacent E/W hand panels */
}
.trick-area.inactive {
  display: none;
}

.trick-grid {
  display: grid;
  /* Fixed-width side columns sized to the actual card box (~50px) so the
     trick area doesn't over-claim space and force layout shifts. Center
     column flexes to fit the trick counter / status. */
  grid-template-columns: 56px 1fr 56px;
  grid-template-rows: minmax(48px, auto) minmax(48px, auto) minmax(48px, auto);
  gap: calc(6px * var(--table-scale));
  width: calc(200px * var(--table-scale));
}

.slot {
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
}
.slot-n { grid-column: 2; grid-row: 1; }
.slot-w { grid-column: 1; grid-row: 2; }
.slot-center { grid-column: 2; grid-row: 2; flex-direction: column; gap: calc(4px * var(--table-scale)); color: #666; text-align: center; }
.slot-e { grid-column: 3; grid-row: 2; }
.slot-s { grid-column: 2; grid-row: 3; }

.slot.is-next .card {
  outline: 1.5px solid #1D9E75;
  outline-offset: 2px;
}
.slot:not(:has(.card)).is-next::after {
  content: '·';
  color: #1D9E75;
  font-size: calc(28px * var(--table-scale));
  line-height: 1;
}

.card {
  background: #fff;
  border: 0.5px solid #bbb;
  border-radius: 4px;
  padding: calc(6px * var(--table-scale)) calc(10px * var(--table-scale));
  font-weight: 500;
  /* Unified glyph scale (glyph-scale.md): the played card matches the hand-rank
     reference (~24px medium), so trick cards read ≥ the cards in hand. */
  font-size: calc(24px * var(--table-scale));
  white-space: nowrap;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
  letter-spacing: 1px;
}

.suit-red { color: #d32f2f; }
.suit-black { color: #222; }

.counter {
  font-variant-numeric: tabular-nums;
  color: #555;
  font-weight: 500;
  font-size: calc(14px * var(--table-scale));
  line-height: 1.3;
}
.bot-thinking {
  color: #1D9E75;
  font-style: italic;
  font-size: calc(11px * var(--table-scale));
}
.last-winner {
  color: #1D9E75;
  font-size: calc(11px * var(--table-scale));
  font-weight: 500;
}
</style>
