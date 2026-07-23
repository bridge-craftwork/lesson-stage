// Spike fixture. Phase 4 replaces this with the deal native posts across the
// seam, parsed from the PDF's `lesson-hands.pbn`.
//
// A full deal, because trick play needs four hands. Real lesson hands are
// usually a single seat (Contract 5 writes the rest as `-`), which is open
// item 3 in that contract and still ours to close.
export const DEMO_DEAL = {
  contract: '4S',
  declarer: 'N',
  openingLeader: 'E',
  hands: {
    N: { spades: ['A', 'K', 'Q', '4'], hearts: ['K', 'J', '3'], diamonds: ['A', '7', '2'], clubs: ['K', 'J', '5'] },
    E: { spades: ['J', '9', '3', '2'], hearts: ['Q', '9', '7', '6'], diamonds: ['K', 'Q', '4'], clubs: ['8', '3'] },
    S: { spades: ['T', '8', '6', '5'], hearts: ['A', 'T', '4'], diamonds: ['J', '6', '5', '3'], clubs: ['A', '9'] },
    W: { spades: ['7'], hearts: ['8', '5', '2'], diamonds: ['T', '9', '8'], clubs: ['Q', 'T', '7', '6', '4', '2'] },
  },
}
