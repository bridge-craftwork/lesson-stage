<script setup lang="ts">
/**
 * Renders free-form bid notation with suit glyphs — including the compound
 * shorthand used in convention tables (`2/3H` -> 2/3♥). Only red suit glyphs
 * are colored; levels and `NT` stay black. Use for columns that are bid
 * notation by convention (a response-box's left column), not for prose.
 */
import { computed } from 'vue'
import { bidTextSegments } from '../dsl/call'

const props = defineProps<{ text: string }>()
const segments = computed(() => bidTextSegments(props.text))
</script>

<template>
  <span
    ><template v-for="(seg, i) in segments" :key="i"
      ><span v-if="seg.red" style="color: #d32f2f">{{ seg.text }}</span
      ><template v-else>{{ seg.text }}</template></template
    ></span
  >
</template>
