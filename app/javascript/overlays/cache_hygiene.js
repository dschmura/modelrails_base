// Closes overlays before Turbo caches the page (#713).
//
// Turbo's snapshot clone normalises only `select`, `input[type=password]` and
// `noscript` (turbo-rails 2.0.23), so an overlay left open when the user navigates
// away is frozen open in the cached page and Back restores it. A menu comes back as
// a `role="menu"` with live menuitems — nothing hides it once `hidden` is gone, and
// `menu_controller#disconnect()` only cancels the type-ahead — under a trigger still
// reporting `aria-expanded="true"`, whose next click is dead because the controller
// reads `openValue` as true.
//
// Dialogs are deliberately NOT swept here. #713 filed them too, but Turbo defers the
// clone one event-loop tick past this event, and in that window the body is replaced
// and `modal_controller#disconnect()` closes the dialog on the detached body the
// clone is taken from. `spec/system/modal_spec.rb` pins that; adding a sweep here
// would be code no test can fail for.
//
// The close set runs on the live DOM and must be synchronous — anything deferred
// misses the clone. All three parts of a menu's open state are reversed together or
// none: `hidden` on the panel, `aria-expanded` on the trigger, and the Stimulus
// value. The top layer is left alone on purpose: the `[data-top-layer]` reset in
// application.css does not restore `display`, so stripping `popover` without the
// `hidden` above would promote an unreachable panel into a visible menu under a
// trigger that reports closed. A cloned popover is closed anyway, so
// `[popover]:not(:popover-open)` keeps it out of the restored page regardless.
document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll('[data-controller~="menu"][data-menu-open-value="true"]')
    .forEach((root) => {
      root.setAttribute("data-menu-open-value", "false")
      root.querySelectorAll('[data-menu-target="menu"]').forEach((menu) => { menu.hidden = true })
      root.querySelectorAll('[data-menu-target="trigger"]')
        .forEach((trigger) => trigger.setAttribute("aria-expanded", "false"))
    })
})
