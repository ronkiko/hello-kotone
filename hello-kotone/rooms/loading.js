(() => {
  const screen = document.querySelector("#loading-screen");
  if (!screen) return;

  const menu = [...screen.querySelectorAll(".menu-item")];
  const credits = screen.querySelector("[data-credits-panel]");
  const dialogue = document.querySelector("#dialogue-screen");
  const dialogueText = document.querySelector("#dialogue-text");
  const dialogueAdvance = document.querySelector("[data-dialogue-advance]");
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

  function startMusic() {
    if (!music) return;
    music.volume = 0.32;
    const playback = music.play();
    if (playback) playback.catch(() => {});
  }

  function startPostBellMusic() {
    if (postBellStarted) return;
    postBellStarted = true;
    postBellMusic.volume = 0.32;
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

  function closeCredits() {
    screen.classList.remove("show-credits");
    credits.hidden = true;
    menu[selectedIndex].focus();
  }

  function activate(action) {
    if (action === "start") startGame();
    if (action === "credits") openCredits();
    if (action === "back") closeCredits();
  }

  for (const item of menu) {
    item.addEventListener("pointerenter", () => select(menu.indexOf(item)));
    item.addEventListener("click", () => activate(item.dataset.menuAction));
  }
  credits.querySelector("[data-menu-action='back']").addEventListener("click", closeCredits);
  dialogueAdvance.addEventListener("click", advanceDialogue);
  window.addEventListener("burned-letter-dialogue", () => {
    if (dialogue.hidden) showDialogue(burnedLetterLine, "burned-letter");
  });
  window.addEventListener("dialogue:complete", (event) => {
    if (event.detail && event.detail.type === "burned-letter") showDialogue(henshinLine, "henshin");
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
    if (!["ArrowUp", "ArrowDown", "Enter", " "].includes(event.key)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.key === "ArrowUp") select(selectedIndex - 1);
    if (event.key === "ArrowDown") select(selectedIndex + 1);
    if (event.key === "Enter" || event.key === " ") activate(menu[selectedIndex].dataset.menuAction);
  });

  select(0);
})();
