import "@hotwired/turbo-rails";
import "./controllers/index.js";
import { finishEntranceOnFocus } from "./motion.js";

document.addEventListener("focusin", finishEntranceOnFocus);
