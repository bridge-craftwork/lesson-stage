<script setup lang="ts">
/**
 * Phase-1 PLACEHOLDER for the Bridge-Classroom `ResponseBox` (Contract 2).
 * A titled bid/meaning table; the left column renders with suit glyphs when it
 * parses as a call.
 */
import BidText from './BidText.vue'
import SuitText from './SuitText.vue'

defineProps<{
  title: string
  rows: { left: string; right: string }[]
  note?: string
}>()
</script>

<template>
  <div class="bc-responsebox-placeholder">
    <div class="title"><SuitText :text="title" /></div>
    <table>
      <tbody>
        <tr v-for="(row, i) in rows" :key="i">
          <td class="bid"><BidText :text="row.left" /></td>
          <td class="meaning"><SuitText :text="row.right" /></td>
        </tr>
      </tbody>
    </table>
    <div v-if="note" class="note">{{ note }}</div>
  </div>
</template>

<style scoped>
.bc-responsebox-placeholder {
  display: inline-block;
  border: 1px solid var(--ls-border, #e4e4e7);
  border-radius: 8px;
  overflow: hidden;
  /* 15em keeps the box from shrink-wrapping to a cramped width when there's
     room — but it must never exceed the column, or it spills into the gutter
     and crowds the next column. At 3 print columns the column is ~212px
     against this 240px floor, which is exactly what that looked like. */
  min-width: min(15em, 100%);
  max-width: 100%;
}
.title {
  padding: 0.4em 0.75em;
  font-weight: 650;
  font-size: 0.85em;
  background: var(--ls-panel, #f7f7f8);
  border-bottom: 1px solid var(--ls-border, #e4e4e7);
}
table {
  border-collapse: collapse;
  width: 100%;
}
td {
  padding: 0.3em 0.75em;
  font-size: 0.85em;
}
td.bid {
  font-family: var(--ls-mono, monospace);
  font-weight: 600;
  white-space: nowrap;
  border-right: 1px solid var(--ls-border, #e4e4e7);
}
tr:not(:last-child) td {
  border-bottom: 1px solid var(--ls-border, #eee);
}
.note {
  padding: 0.4em 0.75em;
  font-size: 0.75em;
  color: var(--ls-muted, #666);
  border-top: 1px solid var(--ls-border, #e4e4e7);
}
</style>
