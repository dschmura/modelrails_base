import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
import BiscuitController from "biscuit/biscuit_controller"
// Self-registers docs-search and docs-mode against window.Stimulus, which
// controllers/application sets. Imported here rather than from application.js
// so that registration lands before the lazy loader below.
import "markdowndocs"

// Everything registered by hand goes in BEFORE lazyLoadControllersFrom runs.
// stimulus-loading skips an identifier the router already knows and otherwise
// tries to import controllers/<identifier>_controller — a path these
// controllers do not have — so every page logged "Failed to autoload
// controller" (#1072). They worked either way; the console did not.
application.register("biscuit", BiscuitController)

// Lazy, not eager (#681): under importmap (no bundling) eager loading fetched
// and evaluated all 60 controllers on EVERY page — signed-out pages included.
// Lazy loading fetches a controller on the first matching data-controller in
// the DOM; the app's own dynamic imports (cropperjs) already follow this.
lazyLoadControllersFrom("controllers", application)
