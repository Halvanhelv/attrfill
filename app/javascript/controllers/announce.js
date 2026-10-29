// Says a short message through the screen reader, via the live regions in the layout.
export function announce(message, { assertive = false } = {}) {
  const region = document.getElementById(assertive ? "announce-assertive" : "announce-polite")
  if (!region) return

  // Clearing first makes the same text be read again.
  region.textContent = ""
  setTimeout(() => (region.textContent = message), 50)
}
