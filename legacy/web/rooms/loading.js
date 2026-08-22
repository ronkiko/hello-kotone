(() => {
  const screen = document.querySelector("#loading-screen");
  if (!screen) return;

  const menu = [...screen.querySelectorAll(".menu-item")];
  const credits = screen.querySelector("[data-credits-panel]");
  const settingsPanel = screen.querySelector("[data-settings-panel]");
  const dialogue = document.querySelector("#dialogue-screen");
  const dialogueText = document.querySelector("#dialogue-text");
  const dialogueAdvance = document.querySelector("[data-dialogue-advance]");
  const volumeControl = document.querySelector("#master-volume");
  const volumeValue = document.querySelector("#master-volume-value");
  const muteControl = document.querySelector("#mute-sound");
  const graphicsControl = document.querySelector("#graphics-quality");
  const modelControls = [...document.querySelectorAll("[name='kotone-model']")];
  const settingsKey = "hello-kotone-settings";
  const defaultSettings = { volume: 70, muted: false, graphics: "pixel", model: "v1" };
  const music = new Audio(new URL("sounds/Dash @ フリーBGM DOVA-SYNDROME.mp3", document.baseURI).href);
  const schoolBell = new Audio(new URL("sounds/school-bell-japan-westminster.ogg", document.baseURI).href);
  const postBellMusic = new Audio(new URL("sounds/Epic and Dark Electronic Music - Welcome to Chaos (Copyright and Royalty Free).mp3", document.baseURI).href);
  music.loop = true;
  music.preload = "auto";
  schoolBell.preload = "auto";
  postBellMusic.loop = true;
  postBellMusic.preload = "auto";
  const firstLine = "Oh no, I'm late! It's already 7:58. I have to make it to class by 8:00, before the bell rings, or I'm in big trouble!";
  const burnedLetterLine = "No... the letters are burned! I can't enter them into the system now. Without them, I can't use the elevator to my classroom. I was already late... what am I going to do?";
  const henshinLine = "Wait... my body feels strange. My hair, my clothes... everything is changing. Did I just transform? This is my new body... then I have to keep running!";
  let selectedIndex = 0;
  let started = false;
  let dialogueTyping = false;
  let dialogueTimer = null;
  let dialoguePosition = 0;
  let dialogueLine = firstLine;
  let dialogueType = "intro";
  let postBellStarted = false;
  let settings = readSettings();

  function readSettings() {
    let stored = {};
    try {
      const parsed = JSON.parse(window.localStorage.getItem(settingsKey) || "{}");
      stored = parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      stored = {};
    }
    return {
      volume: Math.max(0, Math.min(100, Number.isFinite(Number(stored.volume)) ? Number(stored.volume) : defaultSettings.volume)),
      muted: Boolean(stored.muted),
      graphics: ["pixel", "smooth"].includes(stored.graphics) ? stored.graphics : defaultSettings.graphics,
      model: ["v1", "v2"].includes(stored.model) ? stored.model : defaultSettings.model,
    };
  }

  function masterVolume() {
    return settings.muted ? 0 : settings.volume / 100;
  }

  function updateSettings(patch) {
    settings = { ...settings, ...patch };
    try {
      window.localStorage.setItem(settingsKey, JSON.stringify(settings));
    } catch {
      // Settings still apply for this session when storage is unavailable.
    }
    window.dispatchEvent(new CustomEvent("game:settings-change", { detail: { ...settings } }));
    syncSettingsControls();
    applyAudioSettings();
  }

  window.gameSettings = {
    get: () => ({ ...settings }),
    masterVolume,
  };

  function syncSettingsControls() {
    if (volumeControl) volumeControl.value = String(settings.volume);
    if (volumeValue) volumeValue.textContent = `${settings.volume}%`;
    if (muteControl) muteControl.checked = settings.muted;
    if (graphicsControl) graphicsControl.value = settings.graphics;
    for (const control of modelControls) control.checked = control.value === settings.model;
  }

  function applyAudioSettings() {
    const volume = masterVolume();
    music.volume = 0.32 * volume;
    postBellMusic.volume = 0.32 * volume;
    schoolBell.volume = volume;
  }

  function startMusic() {
    if (!music) return;
    applyAudioSettings();
    const playback = music.play();
    if (playback) playback.catch(() => {});
  }

  function startPostBellMusic() {
    if (postBellStarted) return;
    postBellStarted = true;
    applyAudioSettings();
    postBellMusic.currentTime = 0;
    const playback = postBellMusic.play();
    if (playback) playback.catch(() => {});
  }

  function select(index) {
    selectedIndex = (index + menu.length) % menu.length;
    for (const [menuIndex, item] of menu.entries()) {
      const active = menuIndex === selectedIndex;
      item.classList.toggle("is-selected", active);
      item.setAttribute("aria-current", active ? "true" : "false");
    }
  }

  function startGame() {
    if (started) return;
    started = true;
    screen.classList.add("is-exiting");
    music.playbackRate = 1;
    startMusic();
    window.dispatchEvent(new Event("game:start"));
    window.setTimeout(() => {
      document.body.classList.add("is-playing");
      screen.hidden = true;
      screen.classList.remove("is-exiting");
      showDialogue();
    }, 620);
  }

  function showDialogue(line = firstLine, type = "intro") {
    dialogue.hidden = false;
    dialogue.classList.add("is-visible");
    dialogueLine = line;
    dialogueType = type;
    dialoguePosition = 0;
    dialogueTyping = true;
    dialogueText.textContent = "";
    dialogueTimer = window.setInterval(() => {
      dialoguePosition += 1;
      dialogueText.textContent = dialogueLine.slice(0, dialoguePosition);
      if (dialoguePosition >= dialogueLine.length) {
        window.clearInterval(dialogueTimer);
        dialogueTyping = false;
      }
    }, 22);
  }

  function advanceDialogue() {
    if (dialogueType === "intro") startMusic();
    if (dialogueTyping) {
      window.clearInterval(dialogueTimer);
      dialogueText.textContent = dialogueLine;
      dialoguePosition = dialogueLine.length;
      dialogueTyping = false;
      return;
    }
    dialogue.classList.remove("is-visible");
    dialogue.hidden = true;
    window.dispatchEvent(new CustomEvent("dialogue:complete", { detail: { type: dialogueType } }));
  }

  function openCredits() {
    screen.classList.add("show-credits");
    credits.hidden = false;
    const back = credits.querySelector("[data-menu-action='back']");
    back.focus();
  }

  function openSettings() {
    screen.classList.add("show-settings");
    settingsPanel.hidden = false;
    volumeControl.focus();
  }

  function closeSettings() {
    screen.classList.remove("show-settings");
    settingsPanel.hidden = true;
    menu[selectedIndex].focus();
  }

  function closeCredits() {
    screen.classList.remove("show-credits");
    credits.hidden = true;
    menu[selectedIndex].focus();
  }

  function activate(action) {
    if (action === "start") startGame();
    if (action === "settings") openSettings();
    if (action === "credits") openCredits();
    if (action === "back") closeCredits();
    if (action === "settings-back") closeSettings();
  }

  for (const item of menu) {
    item.addEventListener("pointerenter", () => select(menu.indexOf(item)));
    item.addEventListener("click", () => activate(item.dataset.menuAction));
  }
  credits.querySelector("[data-menu-action='back']").addEventListener("click", closeCredits);
  settingsPanel.querySelector("[data-menu-action='settings-back']").addEventListener("click", closeSettings);
  volumeControl.addEventListener("input", () => updateSettings({ volume: Number(volumeControl.value) }));
  muteControl.addEventListener("change", () => updateSettings({ muted: muteControl.checked }));
  graphicsControl.addEventListener("change", () => updateSettings({ graphics: graphicsControl.value }));
  for (const control of modelControls) {
    control.addEventListener("change", () => updateSettings({ model: control.value }));
  }
  dialogueAdvance.addEventListener("click", advanceDialogue);
  window.addEventListener("burned-letter-dialogue", () => {
    if (dialogue.hidden) showDialogue(burnedLetterLine, "burned-letter");
  });
  window.addEventListener("henshin-dialogue", () => {
    if (dialogue.hidden) showDialogue(henshinLine, "henshin");
  });

  window.addEventListener("rush-warning", () => {
    music.pause();
    window.setTimeout(() => {
      music.playbackRate = 1.25;
      const playback = music.play();
      if (playback) playback.catch(() => {});
    }, 1800);
  });

  window.addEventListener("school-bell", () => {
    music.pause();
    postBellStarted = false;
    schoolBell.currentTime = 0;
    schoolBell.addEventListener("ended", startPostBellMusic, { once: true });
    const playback = schoolBell.play();
    if (playback) playback.catch(() => {});
    window.setTimeout(startPostBellMusic, 3000);
  });

  window.addEventListener("keydown", (event) => {
    if (started) {
      if (!dialogue.hidden && ["Enter", " ", "ArrowDown"].includes(event.key)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        advanceDialogue();
      }
      return;
    }
    if (screen.classList.contains("show-credits")) {
      if (event.key === "Escape" || event.key === "Backspace") {
        event.preventDefault();
        closeCredits();
      }
      return;
    }
    if (screen.classList.contains("show-settings")) {
      if (event.key === "Escape" || event.key === "Backspace") {
        event.preventDefault();
        closeSettings();
      }
      return;
    }
    if (!["ArrowUp", "ArrowDown", "Enter", " "].includes(event.key)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.key === "ArrowUp") select(selectedIndex - 1);
    if (event.key === "ArrowDown") select(selectedIndex + 1);
    if (event.key === "Enter" || event.key === " ") activate(menu[selectedIndex].dataset.menuAction);
  });

  syncSettingsControls();
  applyAudioSettings();
  select(0);
})();
