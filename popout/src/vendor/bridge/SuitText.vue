<script setup lang="ts">
/**
 * Renders arbitrary text with red-suit glyphs (♥/♦) colored red. Use for free
 * text that may contain suit symbols — response-box cells, footnotes, quiz
 * prose. (Full calls in letter notation go through CallLabel instead.)
 */
import { computed } from 'vue'
import { splitRedSuits } from '../dsl/suits'

const props = defineProps<{ text: string }>()
const segments = computed(() => splitRedSuits(props.text))
</script>

<template>
  <span
    ><template v-for="(seg, i) in segments" :key="i"
      ><span v-if="seg.red" style="color: #d32f2f">{{ seg.text }}</span
      ><template v-else>{{ seg.text }}</template></template
    ></span
  >
</template>
