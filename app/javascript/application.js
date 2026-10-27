// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// A morph refresh (turbo_refreshes_with :morph) sets every attribute back to the server's HTML. Keep what the person did:
// a <details> they opened stays open.
document.addEventListener("turbo:before-morph-attribute", event => {
  const { attributeName, mutationType } = event.detail
  if (attributeName === "open" && mutationType === "remove" && event.target.localName === "details") event.preventDefault()
})

// Mobile Safari applies :active to buttons only when the page listens to touches; this gives taps a visible press.
document.addEventListener("touchstart", () => {}, { passive: true })
