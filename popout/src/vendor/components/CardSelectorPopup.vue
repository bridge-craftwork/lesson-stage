<template>
  <!-- Floating card-selector: the ONLY place suit cards wrap. Opened from a
       truncated, clickable suit row to reach the cards hidden behind the +N
       chip. Anchored over the row, above all grid content, zero layout impact
       (position: absolute, out of flow). Dumb: props in, `select`/`close` out —
       no engine awareness. -->
  <div class="cs-backdrop" @click="$emit('close')">
    <div class="cs-popup" :style="anchorStyle" @click.stop>
      <div class="cs-head">
        <span class="cs-symbol" :class="suitClass">{{ symbol }}</span>
        <span class="cs-hint">tap a card</span>
      </div>
      <!-- Full suit as standard cells. Wraps to continuation lines: the cells
           flow and break between cells only; the symbol is not repeated. -->
      <div class="cs-cards">
        <button
          v-for="c in cards"
          :key="c.rank"
          class="cs-cell"
          :class="{ red: isRed, played: c.played }"
          :style="c.fill ? { backgroundColor: c.fill } : null"
          :disabled="c.played"
          @click="pick(c)"
        >{{ formatCard(c.rank) }}<span v-if="c.badge" class="cs-badge">{{ c.badge }}</span></button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { SUIT_SYMBOLS, getSuitClass, formatCard } from '../utils/cardFormatting.js'

const props = defineProps({
  // Suit name ('spades' | 'hearts' | 'diamonds' | 'clubs').
  suit: { type: String, required: true },
  // Full suit as cells: [{ rank, played, badge, fill }, ...] high→low.
  cards: { type: Array, default: () => [] },
  // { top, left } page coordinates of the row that opened this (for anchoring).
  anchor: { type: Object, default: null },
})
const emit = defineEmits(['select', 'close'])

const symbol = computed(() => SUIT_SYMBOLS[props.suit])
const suitClass = computed(() => getSuitClass(props.suit))
const isRed = computed(() => suitClass.value === 'suit-red')
const anchorStyle = computed(() => {
  if (!props.anchor) return null
  return { top: `${props.anchor.top}px`, left: `${props.anchor.left}px` }
})

function pick(c) {
  if (c.played) return
  emit('select', c.rank)
  emit('close')
}
</script>

<style scoped>
/* Full-viewport catcher so an outside tap dismisses without action. */
.cs-backdrop {
  position: fixed;
  inset: 0;
  z-index: 1000;
  background: transparent;
}
.cs-popup {
  position: absolute;
  min-width: 160px;
  max-width: min(90vw, 360px);
  background: #fff;
  border: 1px solid #cfd4cd;
  border-radius: 10px;
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.22);
  padding: 10px 12px 12px;
}
.cs-head {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}
.cs-symbol { font-size: 22px; line-height: 1; }
.cs-symbol.suit-red { color: #d32f2f; }
.cs-symbol.suit-black { color: #1a1a1a; }
.cs-hint { font-size: 11px; color: #8a8f88; text-transform: uppercase; letter-spacing: 0.04em; }
/* Wrapping card grid — continuation lines, break between cells only. */
.cs-cards {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.cs-cell {
  /* ≥44px tap targets. */
  min-width: 44px;
  min-height: 44px;
  padding: 0 8px;
  border: 1px solid #d7dbd6;
  border-radius: 8px;
  background: #f7f9f6;
  font: 600 22px 'Segoe UI', system-ui, sans-serif;
  color: #1a1a1a;
  cursor: pointer;
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.cs-cell.red { color: #d32f2f; }
.cs-cell:hover:not(:disabled) { background: #e8f3ec; border-color: #52b788; }
.cs-cell.played { opacity: 0.4; text-decoration: line-through; cursor: default; }
.cs-badge {
  position: absolute;
  top: -6px;
  right: -4px;
  font-size: 10px;
  line-height: 1;
  font-weight: 700;
  color: #fff;
  background: #6a1b9a;
  border-radius: 8px;
  padding: 1px 4px;
}
</style>
