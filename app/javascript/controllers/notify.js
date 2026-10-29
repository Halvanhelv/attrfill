import { announce } from "controllers/announce"

// A visible notification at the bottom of the screen, also read by screen readers.
// notify("Copied", { action: { label: "Undo", run: () => … }, tone: "error", timeout: 5000 })
// Returns close(); close.element is the notice itself. An error stays until closed; any other notice waits while
// it is hovered or focused, then leaves after its timeout.
export function notify(message, { action, tone = "info", timeout = action ? 6000 : 4000 } = {}) {
  const region = document.getElementById("notifications")
  if (!region) return Object.assign(() => {}, { element: null })

  const item = document.createElement("div")
  item.className = `notice animate-in ${tone === "error" ? "notice-error" : ""}`

  const text = document.createElement("p")
  text.className = "flex-1 py-1"
  text.textContent = message
  item.append(text)

  let timer
  const close = () => {
    clearTimeout(timer)
    // A focus inside the leaving notice would fall to <body>; it goes back to the page instead.
    const focused = item.contains(document.activeElement)
    item.remove()
    if (focused) document.getElementById("main")?.focus({ preventScroll: true })
  }
  close.element = item

  if (action) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = `btn btn-sm ${tone === "error" ? "btn-white" : "btn-dark"} shrink-0`
    button.textContent = action.label
    button.addEventListener("click", () => {
      // The action first: it usually moves the focus somewhere meaningful (the row brought back, the result).
      action.run()
      close()
    })
    item.append(button)
  }

  const dismiss = document.createElement("button")
  dismiss.type = "button"
  dismiss.className = "-m-1 grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg opacity-60 hover:opacity-100 pointer-coarse:size-11"
  dismiss.setAttribute("aria-label", "Close notification")
  dismiss.textContent = "✕"
  dismiss.addEventListener("click", close)
  item.append(dismiss)

  // Only the newest few stay on screen.
  while (region.children.length >= 3) region.firstElementChild.remove()
  region.append(item)

  if (tone !== "error") {
    const start = () => {
      clearTimeout(timer)
      timer = setTimeout(close, timeout)
    }
    const hold = () => clearTimeout(timer)
    item.addEventListener("mouseenter", hold)
    item.addEventListener("focusin", hold)
    item.addEventListener("mouseleave", () => item.contains(document.activeElement) || start())
    item.addEventListener("focusout", event => item.contains(event.relatedTarget) || item.matches(":hover") || start())
    start()
  }

  // Read once through the live regions (the notice itself is not a live region, so it is not read twice).
  const sentence = /[.!?…»]$/.test(message.trim()) ? message.trim() : `${message.trim()}.`
  announce(action ? `${sentence} The "${action.label}" button is in the notification.` : sentence, { assertive: tone === "error" })
  return close
}
