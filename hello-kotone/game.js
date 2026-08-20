const canvas = document.querySelector("#hall");
const ctx = canvas.getContext("2d");
const wordCells = [...document.querySelectorAll("#word span")];
const message = document.querySelector("#message");
const objective = document.querySelector("#objective");
const clock = document.querySelector("#clock");

const scene = document.createElement("canvas");
scene.width = 482;
scene.height = 270;
const paint = scene.getContext("2d");
const WORLD_WIDTH = 1690;
const HERO_SIZE = 130;
const HERO_FOOT_Y = 216;
const HERO_ALPHA_BOTTOM = 122 / 130;
const input = { left: false, right: false, up: false, down: false };
const player = { worldX: 70, direction: "right", view: null, animationTime: 0, idleTime: 0 };
const pickups = [
  { value: "H", worldX: 255, collected: false, popTime: -1 },
  { value: "E", worldX: 525, collected: false, popTime: -1 },
  { value: "L", worldX: 805, room: "2C", collected: false, popTime: -1 },
  { value: "L", worldX: 1100, collected: false, popTime: -1 },
  { value: "O", worldX: 1435, collected: false, popTime: -1 },
];
const doors = [
  { worldX: 208, label: "2-B", interactionRange: 72, event: "closed" },
  { worldX: 700, label: "2-C", interactionRange: 72, event: "room-2C" },
  { worldX: 1125, label: "3-C", interactionRange: 72, event: "room-3C" },
];
const roomModules = {
  "2C": window.rooms.class2C,
  "3C": window.rooms.class3C,
};
const sheets = { front: null, back: null, left: null, right: null };
const kotoneV2Sheets = { front: null, back: null, left: null, right: null };
const idleSheets = {};
let cameraX = 0;
let renderCameraX = 0;
let previousTime = 0;
let complete = false;
let audioContext;
let doorOpenBuffer = null;
let doorOpenLoad = null;
let doorHandleBuffer = null;
let doorHandleLoad = null;
let doorSlamBuffer = null;
let doorSlamLoad = null;
let rushWarningAudio = null;
const DOOR_OPEN_URL = new URL("sounds/door-open.mp3", document.baseURI).href;
const DOOR_HANDLE_URL = new URL("sounds/door-handle-cc0.mp3", document.baseURI).href;
const DOOR_SLAM_URL = new URL("sounds/door-close.mp3", document.baseURI).href;
const RUSH_WARNING_URL = new URL("sounds/hurry-alarm-cc0.ogg", document.baseURI).href;
const DOOR_OPEN_OFFSET = 0.1;
const DOOR_HANDLE_OFFSET = 0.14;
const DOOR_HANDLE_PULL_DURATION = 0.22;
const DOOR_CLOSE_OFFSET = 1.96;
let automaticPose = null;
let idleFor = 0;
let automaticPoseTime = 0;
let fanfarePlayed = false;
let celebrationTime = -1;
let interactionNotice = "";
let interactionNoticeTime = 0;
let gameStarted = false;
let dialogueActive = false;
let clockTimer = null;
let clockStartedAt = 0;
let lastClockElapsed = -1;
let rushWarningTriggered = false;
let schoolBellTriggered = false;
let lettersBurned = false;
let burnedLetterDialogueTriggered = false;
let roomMode = "hall";
let roomTransition = null;
let roomPlayerX = 112;
let kotoneV2Active = false;
const POP_DURATION = 420;
const INTERACTION_NOTICE_DURATION = 1500;
const ROOM_FADE_OUT = 320;
const ROOM_BLACKOUT = 1000;
const ROOM_FADE_IN = 520;
const ROOM_PLAYER_MIN = 76;
const ROOM_PLAYER_START = 112;
const ROOM_PLAYER_MAX = 408;
const ROOM_DOOR_INTERACTION_MAX = 118;
const CLOCK_START_SECONDS = 7 * 60 * 60 + 58 * 60;
const RUSH_WARNING_SECONDS = 90;
const SCHOOL_BELL_SECONDS = 120;

function block(x, y, width, height, color) {
  paint.fillStyle = color;
  paint.fillRect(Math.round(x), Math.round(y), Math.round(width), Math.round(height));
}

function edge(x1, y1, x2, y2, color, width = 1) {
  paint.strokeStyle = color;
  paint.lineWidth = width;
  paint.beginPath();
  paint.moveTo(Math.round(x1), Math.round(y1));
  paint.lineTo(Math.round(x2), Math.round(y2));
  paint.stroke();
}

function disk(x, y, radius, color) {
  paint.fillStyle = color;
  paint.beginPath();
  paint.arc(Math.round(x), Math.round(y), radius, 0, Math.PI * 2);
  paint.fill();
}

function screenX(worldX) {
  return Math.round(worldX - renderCameraX);
}

function visible(worldX, width) {
  const x = screenX(worldX);
  return x + width > 0 && x < scene.width;
}

function loadWalk(direction) {
  const image = new Image();
  image.src = `assets/kotone-v1/frames/walking_${direction}.png`;
  image.addEventListener("load", () => {
    sheets[direction] = { image, frameCount: image.naturalWidth / 130 };
  });
}

function loadIdle(pose) {
  const image = new Image();
  image.src = `assets/kotone-v1/frames/idle_${pose}.png`;
  image.addEventListener("load", () => {
    idleSheets[pose] = { image, frameCount: image.naturalWidth / 130 };
  });
}

function loadKotoneV2(direction) {
  const image = new Image();
  image.src = `assets/kotone-v2/running_${direction}.png`;
  image.addEventListener("load", () => {
    kotoneV2Sheets[direction] = { image, frameCount: image.naturalWidth / 130 };
  });
}

function resetIdleTimer() {
  idleFor = 0;
  automaticPose = null;
  automaticPoseTime = 0;
  player.idleTime = 0;
}

function startAutomaticPose() {
  const choices = ["foldarm", "clap", "heart", "heel", "idea", "ipad", "thinking", "waving"];
  automaticPose = choices[Math.floor(Math.random() * choices.length)];
  automaticPoseTime = 0;
  player.idleTime = 0;
}

function enableAudio() {
  if (!audioContext) {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return;
    audioContext = new AudioContext();
  }
  if (audioContext.state === "suspended") audioContext.resume();
  loadDoorOpen();
  loadDoorHandle();
  loadDoorSlam();
}

function loadDoorOpen() {
  if (!audioContext || doorOpenBuffer || doorOpenLoad) return;
  doorOpenLoad = fetch(DOOR_OPEN_URL)
    .then((response) => {
      if (!response.ok) throw new Error(`Door open request failed: ${response.status}`);
      return response.arrayBuffer();
    })
    .then((data) => audioContext.decodeAudioData(data))
    .then((buffer) => { doorOpenBuffer = buffer; })
    .catch(() => { doorOpenLoad = null; });
}

function loadDoorSlam() {
  if (!audioContext || doorSlamBuffer || doorSlamLoad) return;
  doorSlamLoad = fetch(DOOR_SLAM_URL)
    .then((response) => {
      if (!response.ok) throw new Error(`Door sound request failed: ${response.status}`);
      return response.arrayBuffer();
    })
    .then((data) => audioContext.decodeAudioData(data))
    .then((buffer) => { doorSlamBuffer = buffer; })
    .catch(() => { doorSlamLoad = null; });
}

function loadDoorHandle() {
  if (!audioContext || doorHandleBuffer || doorHandleLoad) return;
  doorHandleLoad = fetch(DOOR_HANDLE_URL)
    .then((response) => {
      if (!response.ok) throw new Error(`Door handle request failed: ${response.status}`);
      return response.arrayBuffer();
    })
    .then((data) => audioContext.decodeAudioData(data))
    .then((buffer) => { doorHandleBuffer = buffer; })
    .catch(() => { doorHandleLoad = null; });
}

function scheduleNoise(start, duration, filterType, frequency, resonance, peak) {
  if (!audioContext) return;
  const sampleCount = Math.floor(audioContext.sampleRate * duration);
  const buffer = audioContext.createBuffer(1, sampleCount, audioContext.sampleRate);
  const samples = buffer.getChannelData(0);
  const attackSamples = Math.max(1, Math.floor(audioContext.sampleRate * 0.006));
  for (let index = 0; index < samples.length; index += 1) {
    const attack = Math.min(1, index / attackSamples);
    const release = 1 - index / samples.length;
    samples[index] = (Math.random() * 2 - 1) * attack * release;
  }

  const noise = audioContext.createBufferSource();
  const filter = audioContext.createBiquadFilter();
  const volume = audioContext.createGain();
  filter.type = filterType;
  filter.frequency.setValueAtTime(frequency, start);
  filter.Q.setValueAtTime(resonance, start);
  volume.gain.setValueAtTime(0.0001, start);
  volume.gain.exponentialRampToValueAtTime(peak, start + 0.006);
  volume.gain.exponentialRampToValueAtTime(0.0001, start + duration);
  noise.buffer = buffer;
  noise.connect(filter).connect(volume).connect(audioContext.destination);
  noise.start(start);
  noise.stop(start + duration);
}

function playFootstep() {
  if (!audioContext) return;
  const now = audioContext.currentTime;
  scheduleNoise(now, 0.07, "bandpass", 1150, 0.9, 0.082);
  scheduleTone(108, now, 0.075, "triangle", 0.035);
}

function scheduleTone(frequency, start, duration, type, volume) {
  if (!audioContext) return;
  const oscillator = audioContext.createOscillator();
  const gain = audioContext.createGain();
  oscillator.type = type;
  oscillator.frequency.setValueAtTime(frequency, start);
  gain.gain.setValueAtTime(0.0001, start);
  gain.gain.exponentialRampToValueAtTime(volume, start + 0.012);
  gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
  oscillator.connect(gain).connect(audioContext.destination);
  oscillator.start(start);
  oscillator.stop(start + duration + 0.02);
}

function playCollectSound() {
  if (!audioContext) return;
  const start = audioContext.currentTime;
  scheduleTone(520, start, 0.11, "sine", 0.055);
  scheduleTone(760, start + 0.065, 0.12, "sine", 0.05);
  scheduleTone(1040, start + 0.13, 0.16, "triangle", 0.04);
}

function playFanfare() {
  if (!audioContext) return;
  const start = audioContext.currentTime + 0.03;
  scheduleTone(523, start, 0.18, "triangle", 0.07);
  scheduleTone(659, start + 0.13, 0.18, "triangle", 0.07);
  scheduleTone(784, start + 0.26, 0.2, "triangle", 0.08);
  scheduleTone(1047, start + 0.42, 0.42, "sine", 0.1);
  scheduleTone(1319, start + 0.47, 0.54, "sine", 0.055);
}

function playDoorHandleSound() {
  if (!audioContext) return;
  const start = audioContext.currentTime;
  if (doorHandleBuffer) {
    const pulls = [
      { delay: 0, gain: 4.8, rate: 1 },
      { delay: 0.12, gain: 4.15, rate: 0.97 },
      { delay: 0.26, gain: 4.55, rate: 1.03 },
      { delay: 0.41, gain: 3.7, rate: 0.95 },
    ];
    for (const pull of pulls) {
      const pullStart = start + pull.delay;
      const source = audioContext.createBufferSource();
      const volume = audioContext.createGain();
      const duration = Math.min(DOOR_HANDLE_PULL_DURATION, doorHandleBuffer.duration - DOOR_HANDLE_OFFSET);
      source.playbackRate.setValueAtTime(pull.rate, pullStart);
      volume.gain.setValueAtTime(0.0001, pullStart);
      volume.gain.linearRampToValueAtTime(pull.gain, pullStart + 0.006);
      volume.gain.exponentialRampToValueAtTime(0.0001, pullStart + duration);
      source.buffer = doorHandleBuffer;
      source.connect(volume).connect(audioContext.destination);
      source.start(pullStart, DOOR_HANDLE_OFFSET, duration);
    }
    return;
  }

  for (const delay of [0, 0.12, 0.26, 0.41]) {
    const pullStart = start + delay;
    scheduleNoise(pullStart, 0.032, "highpass", 2800, 0.8, 0.12);
    scheduleTone(1880, pullStart, 0.045, "sine", 0.1);
    scheduleTone(1240, pullStart + 0.035, 0.055, "sine", 0.07);
  }
}

function playDoorOpenSound() {
  if (!audioContext) return;
  const start = audioContext.currentTime;
  if (doorOpenBuffer) {
    const source = audioContext.createBufferSource();
    const volume = audioContext.createGain();
    const duration = Math.min(0.3, doorOpenBuffer.duration - DOOR_OPEN_OFFSET);
    volume.gain.setValueAtTime(0.0001, start);
    volume.gain.linearRampToValueAtTime(1.05, start + 0.008);
    volume.gain.exponentialRampToValueAtTime(0.0001, start + duration);
    source.buffer = doorOpenBuffer;
    source.connect(volume).connect(audioContext.destination);
    source.start(start, DOOR_OPEN_OFFSET, duration);
    return;
  }

  scheduleNoise(start, 0.42, "bandpass", 510, 1.4, 0.075);
  const oscillator = audioContext.createOscillator();
  const volume = audioContext.createGain();
  oscillator.type = "triangle";
  oscillator.frequency.setValueAtTime(170, start);
  oscillator.frequency.exponentialRampToValueAtTime(305, start + 0.36);
  oscillator.frequency.exponentialRampToValueAtTime(88, start + 0.38);
  volume.gain.setValueAtTime(0.0001, start);
  volume.gain.exponentialRampToValueAtTime(0.06, start + 0.035);
  volume.gain.exponentialRampToValueAtTime(0.0001, start + 0.42);
  oscillator.connect(volume).connect(audioContext.destination);
  oscillator.start(start);
  oscillator.stop(start + 0.45);
  scheduleTone(1250, start, 0.05, "square", 0.045);
  scheduleTone(720, start + 0.055, 0.08, "triangle", 0.035);
}

function playDoorCloseSound() {
  if (!audioContext) return;
  const start = audioContext.currentTime;
  if (!doorSlamBuffer) {
    scheduleNoise(start, 0.12, "lowpass", 360, 0.7, 0.1);
    scheduleTone(78, start, 0.16, "sine", 0.09);
    return;
  }

  const source = audioContext.createBufferSource();
  const volume = audioContext.createGain();
  const duration = Math.min(0.35, doorSlamBuffer.duration - DOOR_CLOSE_OFFSET);
  volume.gain.setValueAtTime(0.0001, start);
  volume.gain.linearRampToValueAtTime(1.15, start + 0.004);
  volume.gain.exponentialRampToValueAtTime(0.0001, start + duration);
  source.buffer = doorSlamBuffer;
  source.connect(volume).connect(audioContext.destination);
  source.start(start, DOOR_CLOSE_OFFSET, duration);
}

function paintWindow(worldX) {
  if (!visible(worldX, 140)) return;
  const x = screenX(worldX);
  const distantOffset = Math.round((renderCameraX * 0.22) % 34);
  block(x, 47, 140, 138, "#283342");
  paint.save();
  paint.beginPath();
  paint.rect(x + 5, 52, 130, 128);
  paint.clip();
  block(x + 5, 52, 130, 128, "#8caeb8");
  block(x + 5, 108, 130, 72, "#749293");
  block(x + 5, 135, 130, 45, "#607d70");
  block(x + 5, 115, 130, 9, "#a5aaa0");
  for (let building = -34 - distantOffset; building < 140; building += 34) {
    block(x + 5 + building, 121, 25, 14, "#909a99");
    block(x + 9 + building, 124, 17, 8, "#d3dfd5");
  }
  paint.restore();
  block(x, 42, 140, 7, "#3b4250");
  block(x, 180, 140, 7, "#3b4250");
  for (const frame of [0, 45, 90, 134]) block(x + frame, 42, 6, 145, "#3b4250");
  block(x + 6, 95, 128, 4, "#566876");
  block(x + 6, 151, 128, 4, "#566876");
  block(x + 13, 54, 36, 2, "rgba(255,255,255,0.3)");
}

function paintDoor({ worldX, label }) {
  if (!visible(worldX, 102)) return;
  const x = screenX(worldX);
  block(x - 4, 54, 102, 138, "#2c3442");
  block(x, 58, 94, 130, "#737b87");
  block(x + 4, 62, 86, 49, "#9cb6ba");
  block(x + 9, 67, 76, 39, "#c8d8d9");
  block(x + 4, 113, 86, 5, "#535e6b");
  block(x + 4, 120, 86, 64, "#858d97");
  block(x + 46, 120, 4, 64, "#656e79");
  block(x + 11, 129, 30, 3, "#9da4aa");
  block(x + 58, 129, 30, 3, "#9da4aa");
  block(x + 39, 151, 5, 8, "#c7a55f");
  block(x + 52, 151, 5, 8, "#c7a55f");
  block(x + 20, 37, 56, 13, "#e4dfcf");
  paint.fillStyle = "#444653";
  paint.textAlign = "center";
  paint.font = "900 7px ui-monospace, monospace";
  paint.fillText(label, x + 48, 46);
}

function paintFirePanel(worldX) {
  if (!visible(worldX, 28)) return;
  const x = screenX(worldX);
  block(x, 76, 22, 73, "#4c5664");
  block(x + 3, 79, 16, 67, "#c3c8c6");
  disk(x + 11, 90, 6, "#c84d51");
  disk(x + 11, 90, 3, "#ef7a65");
  disk(x + 11, 108, 6, "#777f87");
  block(x + 4, 120, 14, 17, "#ae4548");
  block(x + 7, 124, 8, 6, "#f3e3bf");
}

function paintNoticeBoard(worldX) {
  if (!visible(worldX, 68)) return;
  const x = screenX(worldX);
  block(x, 93, 68, 72, "#705f5c");
  block(x + 4, 97, 60, 64, "#d8c793");
  block(x + 10, 104, 20, 3, "#c76464");
  block(x + 34, 104, 20, 3, "#7a96aa");
  block(x + 10, 116, 41, 2, "#8a705f");
  block(x + 10, 124, 35, 2, "#8a705f");
  block(x + 10, 135, 46, 17, "#edf0d9");
  block(x + 13, 139, 33, 2, "#8095a0");
  block(x + 13, 145, 26, 2, "#c37972");
}

function paintWaterCooler(worldX) {
  if (!visible(worldX, 28)) return;
  const x = screenX(worldX);
  block(x + 4, 138, 20, 45, "#57606c");
  block(x + 7, 143, 14, 17, "#9fc2c4");
  block(x + 9, 147, 10, 10, "#d6e6df");
  block(x + 7, 165, 14, 14, "#bcc4c4");
  block(x + 5, 181, 18, 4, "#333b47");
}

function paintElevator(worldX) {
  if (!visible(worldX, 170)) return;
  const x = screenX(worldX);
  block(x, 54, 136, 137, "#303846");
  block(x + 5, 59, 126, 128, "#9ca1a5");
  block(x + 20, 73, 96, 96, "#555e6c");
  block(x + 22, 76, 46, 90, "#707986");
  block(x + 68, 76, 46, 90, "#707986");
  block(x + 66, 76, 4, 90, "#414b58");
  block(x + 143, 107, 16, 34, "#c1c7c4");
  block(x + 146, 112, 10, 8, "#d3a84c");
  block(x + 146, 127, 10, 8, "#5b6570");
  block(x + 36, 37, 50, 13, "#242b36");
  paint.fillStyle = "#e5c65d";
  paint.textAlign = "center";
  paint.font = "900 7px ui-monospace, monospace";
  paint.fillText("2F", x + 61, 46);
}

function paintCorridor(time) {
  paint.clearRect(0, 0, scene.width, scene.height);
  paint.imageSmoothingEnabled = false;
  block(0, 0, scene.width, 270, "#111720");
  block(12, 14, scene.width - 24, 225, "#a7adb7");
  block(12, 14, scene.width - 24, 29, "#465161");
  block(12, 42, scene.width - 24, 6, "#273241");
  block(12, 48, scene.width - 24, 140, "#abb1b9");
  block(12, 48, scene.width - 24, 3, "#c7ccc8");

  const tileStart = -((renderCameraX * 0.52) % 43);
  for (let x = tileStart; x < scene.width; x += 43) edge(x, 15, x, 42, "#5f6a78");
  edge(12, 30, scene.width - 14, 30, "#5f6a78");
  for (let worldX = Math.floor(renderCameraX / 156) * 156 + 47; worldX < renderCameraX + scene.width; worldX += 156) {
    const x = screenX(worldX);
    block(x, 25, 66, 5, "#f4efd1");
    block(x + 3, 22, 60, 3, "#68717d");
    block(x - 2, 30, 70, 2, "rgba(238,222,164,0.25)");
  }

  paintWindow(18);
  paintDoor(doors[0]);
  paintFirePanel(344);
  paintNoticeBoard(408);
  paintWindow(498);
  paintDoor(doors[1]);
  paintWaterCooler(850);
  paintWindow(925);
  paintDoor(doors[2]);
  paintFirePanel(1265);
  paintElevator(1340);
  paintWindow(1510);

  block(12, 188, scene.width - 24, 47, "#8b655f");
  block(12, 188, scene.width - 24, 4, "#55505a");
  block(12, 192, scene.width - 24, 43, "#a87869");
  for (const y of [202, 216, 232]) block(12, y, scene.width - 24, 1, "#75585a");
  const plankStart = -(renderCameraX % 32);
  for (let x = plankStart; x < scene.width; x += 32) {
    block(x, 193, 1, 9, "rgba(79,55,55,0.42)");
    block(x + 16, 203, 1, 13, "rgba(79,55,55,0.42)");
    block(x, 217, 1, 15, "rgba(79,55,55,0.42)");
  }
  block(12, 235, scene.width - 24, 5, "#303641");

  block(0, 0, 12, 270, "#0d131d");
  block(scene.width - 12, 0, 12, 270, "#0d131d");
  block(12, 240, scene.width - 24, 30, "#121822");
  block(18, 240, scene.width - 36, 3, "#414753");
}

function paintPickup(item, time) {
  if (item.room || !visible(item.worldX, 32) || (item.collected && item.popTime >= POP_DURATION)) return;
  if (item.burned && !item.collected) {
    paintBurnedPickup(item, time);
    return;
  }
  const x = screenX(item.worldX);
  const lift = Math.round(Math.sin(time / 260 + item.worldX) * 2);
  const popping = item.collected;
  const progress = popping ? Math.min(1, item.popTime / POP_DURATION) : 0;
  const alpha = popping ? 1 - progress : 1;
  const radius = 11 + progress * 8;
  paint.save();
  paint.globalAlpha = alpha;
  paint.shadowColor = "#ffdf78";
  paint.shadowBlur = popping ? 8 * (1 - progress) : 8;
  disk(x, 185 + lift, radius, "#e9be59");
  paint.shadowBlur = 0;
  paint.fillStyle = "#483848";
  paint.textAlign = "center";
  paint.textBaseline = "middle";
  paint.font = `900 ${13 + progress * 4}px Georgia, serif`;
  paint.fillText(item.value, x, 186 + lift);

  if (popping) {
    paint.globalAlpha = alpha * 0.85;
    paint.strokeStyle = "#ffe38b";
    paint.lineWidth = 2;
    paint.beginPath();
    paint.arc(x, 185 + lift, radius + progress * 8, 0, Math.PI * 2);
    paint.stroke();
    for (let shard = 0; shard < 8; shard += 1) {
      const angle = (Math.PI * 2 * shard) / 8;
      const distance = progress * (18 + (shard % 3) * 7);
      const shardX = x + Math.cos(angle) * distance;
      const shardY = 185 + lift + Math.sin(angle) * distance;
      const size = Math.max(1, 3 - progress * 2);
      paint.fillStyle = shard % 2 ? "#ffe38b" : "#ef9bad";
      paint.fillRect(Math.round(shardX), Math.round(shardY), size, size);
    }
  }
  paint.restore();
}

function paintBurnedPickup(item, time) {
  const x = screenX(item.worldX);
  const flicker = Math.round(Math.sin(time / 90 + item.worldX) * 2);
  paint.save();
  paint.shadowColor = "#e45f4f";
  paint.shadowBlur = 5;
  disk(x, 185 + flicker, 11, "#493a3d");
  paint.shadowBlur = 0;
  paint.fillStyle = "#151820";
  paint.textAlign = "center";
  paint.textBaseline = "middle";
  paint.font = "900 13px Georgia, serif";
  paint.fillText(item.value, x, 186 + flicker);
  paint.fillStyle = "#ef7652";
  paint.fillRect(x - 2, 168 + flicker, 3, 5);
  paint.fillStyle = "#f2bf62";
  paint.fillRect(x + 4, 171 + flicker, 2, 3);
  paint.fillStyle = "#74636a";
  paint.fillRect(x - 8, 164 + flicker, 2, 2);
  paint.fillRect(x + 8, 160 + flicker, 2, 2);
  paint.restore();
}

function paintPlayerAt(x) {
  const walking = input.left !== input.right;
  const activeSheets = kotoneV2Active ? kotoneV2Sheets : sheets;
  const idleSheet = kotoneV2Active
    ? activeSheets.front || sheets.front
    : automaticPose ? idleSheets[automaticPose] || sheets.front : sheets.front;
  const walkingSheet = activeSheets[player.direction] || sheets.front;
  const sheet = walking ? walkingSheet : (player.view === "back" ? activeSheets.back || sheets.back || sheets.front : idleSheet);
  const animationTime = walking ? player.animationTime : (automaticPose ? player.idleTime : 0);
  const frameDuration = walking ? 150 : 140;
  const frame = sheet ? Math.floor(animationTime / frameDuration) % sheet.frameCount : 0;
  const spriteY = HERO_FOOT_Y - HERO_SIZE * HERO_ALPHA_BOTTOM;

  paint.save();
  paint.fillStyle = "rgba(20, 20, 26, 0.42)";
  paint.beginPath();
  paint.ellipse(x, HERO_FOOT_Y, 32, 5, 0, 0, Math.PI * 2);
  paint.fill();
  if (sheet) paint.drawImage(sheet.image, frame * 130, 0, 130, 130, x - HERO_SIZE / 2, spriteY, HERO_SIZE, HERO_SIZE);
  paint.restore();
}

function paintPlayer() {
  paintPlayerAt(screenX(player.worldX));
}

function paintRoomPlayer() {
  paintPlayerAt(roomPlayerX);
}

function paintComplete() {
  if (!complete) return;
  paintFireworks();
  block(150, 55, 180, 39, "rgba(24,27,37,0.91)");
  edge(150, 55, 330, 55, "#d69b72");
  edge(150, 94, 330, 94, "#d69b72");
  paint.fillStyle = "#f6cf75";
  paint.textAlign = "center";
  paint.font = "900 16px Georgia, serif";
  paint.fillText("HELLO, SAKURA", 240, 72);
  paint.fillStyle = "#e8e0ce";
  paint.font = "700 6px ui-monospace, monospace";
  paint.fillText("PRESS R TO WALK AGAIN", 240, 84);
}

function paintInteractionNotice() {
  if (!interactionNotice || interactionNoticeTime <= 0) return;
  const fade = interactionNoticeTime < 220 ? interactionNoticeTime / 220 : 1;
  const width = 142;
  const height = 34;
  const x = (scene.width - width) / 2;
  const y = (scene.height - height) / 2;
  paint.save();
  paint.globalAlpha = fade;
  block(x, y, width, height, "rgba(24,27,37,0.92)");
  edge(x, y, x + width, y, "#d69b72");
  edge(x, y + height, x + width, y + height, "#d69b72");
  paint.fillStyle = "#f6cf75";
  paint.textAlign = "center";
  paint.textBaseline = "middle";
  paint.font = "900 13px Georgia, serif";
  paint.fillText(interactionNotice, scene.width / 2, scene.height / 2 + 1);
  paint.restore();
}

function paintFireworks() {
  if (celebrationTime < 0) return;
  const progress = Math.min(1, celebrationTime / 1200);
  const travel = 1 - (1 - progress) * (1 - progress);
  const fade = progress < 0.72 ? 1 : 1 - (progress - 0.72) / 0.28;
  const centerX = 240;
  const centerY = 48;
  paint.save();
  paint.globalAlpha = Math.max(0, fade);
  for (let spark = 0; spark < 24; spark += 1) {
    const angle = (Math.PI * 2 * spark) / 24 - Math.PI / 2;
    const length = 16 + (spark % 4) * 4;
    const startDistance = Math.max(0, travel * 38 - length);
    const endDistance = travel * 38;
    const startX = centerX + Math.cos(angle) * startDistance;
    const startY = centerY + Math.sin(angle) * startDistance;
    const endX = centerX + Math.cos(angle) * endDistance;
    const endY = centerY + Math.sin(angle) * endDistance;
    paint.strokeStyle = spark % 3 === 0 ? "#f19ab7" : "#f6cf75";
    paint.lineWidth = spark % 3 === 0 ? 2 : 1;
    paint.beginPath();
    paint.moveTo(Math.round(startX), Math.round(startY));
    paint.lineTo(Math.round(endX), Math.round(endY));
    paint.stroke();
    paint.fillStyle = "#fff5bd";
    paint.fillRect(Math.round(endX), Math.round(endY), 2, 2);
  }
  paint.restore();
}

function syncHud() {
  let count = 0;
  for (let index = 0; index < pickups.length; index += 1) {
    const active = pickups[index].collected;
    wordCells[index].classList.toggle("on", active);
    if (active) count += 1;
  }
  message.textContent = count ? `${count} of 5 letters found.` : "Walk into the east wing.";
}

function formatClock(totalSeconds) {
  const hours = Math.floor(totalSeconds / 3600) % 24;
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return [hours, minutes, seconds].map((value) => String(value).padStart(2, "0")).join(":");
}

function syncGameClock(elapsedSeconds) {
  if (!clock) return;
  clock.textContent = formatClock(CLOCK_START_SECONDS + elapsedSeconds);
  if (elapsedSeconds >= RUSH_WARNING_SECONDS && !rushWarningTriggered) triggerRushWarning();
  if (elapsedSeconds >= SCHOOL_BELL_SECONDS && !schoolBellTriggered) {
    triggerSchoolBell();
  }
}

function startGameClock() {
  stopGameClock();
  clockStartedAt = performance.now();
  lastClockElapsed = -1;
  rushWarningTriggered = false;
  schoolBellTriggered = false;
  clock.classList.remove("rush-blink", "rush-red", "late");
  syncGameClock(0);
  clockTimer = window.setInterval(() => {
    const elapsedSeconds = Math.floor((performance.now() - clockStartedAt) / 1000);
    if (elapsedSeconds === lastClockElapsed) return;
    lastClockElapsed = elapsedSeconds;
    syncGameClock(elapsedSeconds);
  }, 250);
}

function stopGameClock() {
  if (clockTimer) window.clearInterval(clockTimer);
  clockTimer = null;
}

function triggerSchoolBell() {
  schoolBellTriggered = true;
  lettersBurned = true;
  burnedLetterDialogueTriggered = false;
  for (const item of pickups) {
    if (!item.collected) item.burned = true;
  }
  if (!complete) {
    objective.textContent = "Too late. The letters burned away.";
    message.textContent = "The bell has rung.";
  }
  stopGameClock();
  clock.classList.remove("rush-blink", "rush-red");
  clock.classList.add("late");
  clock.textContent = "KOTONE IS LATE.";
  window.dispatchEvent(new Event("school-bell"));
}

function checkBurnedLetterEncounter(item, playerX) {
  if (!lettersBurned || burnedLetterDialogueTriggered || !item || !item.burned) return;
  const targetX = item.room ? 368 : item.worldX;
  if (Math.abs(playerX - targetX) >= 22) return;
  burnedLetterDialogueTriggered = true;
  dialogueActive = true;
  input.left = false;
  input.right = false;
  input.up = false;
  input.down = false;
  player.animationTime = 0;
  window.dispatchEvent(new Event("burned-letter-dialogue"));
}

function playRushWarningSound() {
  if (!rushWarningAudio) {
    rushWarningAudio = new Audio(RUSH_WARNING_URL);
    rushWarningAudio.volume = 0.85;
  }
  rushWarningAudio.currentTime = 0;
  const playback = rushWarningAudio.play();
  if (playback) playback.catch(() => {});
}

function triggerRushWarning() {
  rushWarningTriggered = true;
  playRushWarningSound();
  clock.classList.remove("rush-red");
  clock.classList.add("rush-blink");
  window.setTimeout(() => {
    clock.classList.remove("rush-blink");
    clock.classList.add("rush-red");
  }, 1800);
  window.dispatchEvent(new Event("rush-warning"));
}

function showInteractionNotice(text) {
  interactionNotice = text;
  interactionNoticeTime = INTERACTION_NOTICE_DURATION;
}

function findNearbyInteractable() {
  let closest = null;
  let closestDistance = Infinity;
  for (const door of doors) {
    if (!door.event) continue;
    const distance = Math.abs(player.worldX - (door.worldX + 48));
    if (distance <= door.interactionRange && distance < closestDistance) {
      closest = door;
      closestDistance = distance;
    }
  }
  return closest;
}

function interact() {
  const target = findNearbyInteractable();
  if (!target) return;
  player.view = "back";
  if (target.event === "closed") {
    showInteractionNotice("Door closed");
    playDoorHandleSound();
  } else if (target.event === "room-2C") {
    beginRoomTransition("2C");
  } else if (target.event === "room-3C") {
    beginRoomTransition("3C");
  }
}

function inspectRoom() {
  const room = roomModules[roomMode];
  if (!room || typeof room.interact !== "function") {
    showInteractionNotice("Nothing to inspect here.");
    return;
  }
  player.view = "back";
  showInteractionNotice(room.interact(roomPlayerX));
}

function beginRoomTransition(target) {
  if (roomMode !== "hall" || roomTransition) return;
  input.left = false;
  input.right = false;
  input.up = false;
  input.down = false;
  roomTransition = { phase: "fade-out", elapsed: 0, target };
  playDoorOpenSound();
}

function beginHallTransition() {
  if (!roomModules[roomMode] || roomTransition || roomPlayerX > ROOM_DOOR_INTERACTION_MAX) return;
  input.left = false;
  input.right = false;
  input.up = false;
  input.down = false;
  roomTransition = { phase: "fade-out", elapsed: 0, target: "hall", previousRoom: roomMode };
  playDoorOpenSound();
}

function updateRoomTransition(deltaMs) {
  roomTransition.elapsed += deltaMs;
  if (roomTransition.phase === "fade-out" && roomTransition.elapsed >= ROOM_FADE_OUT) {
    roomTransition.phase = "blackout";
    roomTransition.elapsed = 0;
    return;
  }
  if (roomTransition.phase === "blackout" && roomTransition.elapsed >= ROOM_BLACKOUT) {
    roomMode = roomTransition.target;
    if (roomMode === "hall") {
      player.view = "front";
      roomModules[roomTransition.previousRoom].reset();
    } else {
      roomPlayerX = ROOM_PLAYER_START;
      player.view = "front";
      roomModules[roomMode].enter();
    }
    playDoorCloseSound();
    roomTransition.phase = "fade-in";
    roomTransition.elapsed = 0;
    return;
  }
  if (roomTransition.phase === "fade-in" && roomTransition.elapsed >= ROOM_FADE_IN) {
    roomTransition = null;
  }
}

function transitionAlpha() {
  if (!roomTransition) return 0;
  if (roomTransition.phase === "fade-out") return Math.min(1, roomTransition.elapsed / ROOM_FADE_OUT);
  if (roomTransition.phase === "blackout") return 1;
  return Math.max(0, 1 - roomTransition.elapsed / ROOM_FADE_IN);
}

function paintTransitionOverlay() {
  const alpha = transitionAlpha();
  if (!alpha) return;
  paint.save();
  paint.fillStyle = `rgba(0, 0, 0, ${alpha})`;
  paint.fillRect(0, 0, scene.width, scene.height);
  paint.restore();
}

function updateRoomPlayer(delta) {
  const walking = input.left !== input.right;
  const previousStep = Math.floor(player.animationTime / 150);
  if (input.left) {
    roomPlayerX = Math.max(ROOM_PLAYER_MIN, roomPlayerX - 1.7 * delta);
    player.direction = "left";
  }
  if (input.right) {
    roomPlayerX = Math.min(ROOM_PLAYER_MAX, roomPlayerX + 1.7 * delta);
    player.direction = "right";
  }
  player.animationTime = walking ? player.animationTime + delta * 16.67 : 0;
  if (walking) player.view = null;
  const currentStep = Math.floor(player.animationTime / 150);
  if (walking && currentStep !== previousStep && currentStep % 3 === 0) playFootstep();

  const roomLetter = pickups.find((item) => item.room === "2C");
  checkBurnedLetterEncounter(roomLetter, roomPlayerX);
  if (!lettersBurned && roomLetter && !roomLetter.collected && Math.abs(roomPlayerX - 368) < 22) {
    roomLetter.collected = true;
    roomLetter.popTime = 0;
    playCollectSound();
    syncHud();
  }
}

function update(delta) {
  for (const item of pickups) {
    if (item.popTime >= 0) item.popTime += delta * 16.67;
  }
  if (celebrationTime >= 0) celebrationTime += delta * 16.67;
  if (interactionNoticeTime > 0) interactionNoticeTime = Math.max(0, interactionNoticeTime - delta * 16.67);
  if (roomTransition) {
    updateRoomTransition(delta * 16.67);
    return;
  }
  if (roomMode !== "hall") {
    updateRoomPlayer(delta);
    roomModules[roomMode].update(delta * 16.67);
    return;
  }
  if (complete) return;
  const walking = input.left !== input.right;
  if (input.left) {
    player.worldX -= 1.7 * delta;
    player.direction = "left";
  }
  if (input.right) {
    player.worldX += 1.7 * delta;
    player.direction = "right";
  }
  player.worldX = Math.max(66, Math.min(WORLD_WIDTH - 70, player.worldX));
  const previousStep = Math.floor(player.animationTime / 150);
  player.animationTime = walking ? player.animationTime + delta * 16.67 : 0;
  player.idleTime = walking ? 0 : player.idleTime + delta * 16.67;
  const currentStep = Math.floor(player.animationTime / 150);
  if (walking && currentStep !== previousStep && currentStep % 3 === 0) playFootstep();

  if (!walking && player.view !== "back" && !automaticPose) {
    idleFor += delta * 16.67;
    if (idleFor >= 10000) startAutomaticPose();
  }
  if (automaticPose && !walking) {
    automaticPoseTime += delta * 16.67;
    const automaticSheet = idleSheets[automaticPose];
    const automaticDuration = automaticSheet ? automaticSheet.frameCount * 140 : 1800;
    if (automaticPoseTime >= automaticDuration) {
      automaticPose = null;
      automaticPoseTime = 0;
      idleFor = 0;
      player.idleTime = 0;
    }
  }

  const cameraTarget = Math.max(0, Math.min(WORLD_WIDTH - scene.width, player.worldX - 155));
  cameraX += (cameraTarget - cameraX) * Math.min(1, delta * 0.12);
  renderCameraX = Math.floor(cameraX);

  for (const item of pickups) {
    if (!item.room) checkBurnedLetterEncounter(item, player.worldX);
    if (!lettersBurned && !item.room && !item.collected && Math.abs(player.worldX - item.worldX) < 22) {
      item.collected = true;
      item.popTime = 0;
      playCollectSound();
      syncHud();
    }
  }
  if (!lettersBurned && pickups.every((item) => item.collected)) {
    complete = true;
    input.left = false;
    input.right = false;
    input.up = false;
    input.down = false;
    celebrationTime = 0;
    if (!fanfarePlayed) {
      fanfarePlayed = true;
      playFanfare();
    }
    objective.textContent = "The first hello of the day.";
    message.textContent = "The bell rings somewhere upstairs.";
  }
}

function restart() {
  stopGameClock();
  player.worldX = 70;
  player.direction = "right";
  player.view = null;
  player.animationTime = 0;
  player.idleTime = 0;
  automaticPose = null;
  idleFor = 0;
  automaticPoseTime = 0;
  cameraX = 0;
  renderCameraX = 0;
  roomPlayerX = ROOM_PLAYER_START;
  complete = false;
  fanfarePlayed = false;
  celebrationTime = -1;
  kotoneV2Active = false;
  interactionNotice = "";
  interactionNoticeTime = 0;
  rushWarningTriggered = false;
  schoolBellTriggered = false;
  lettersBurned = false;
  burnedLetterDialogueTriggered = false;
  if (clock) {
    clock.classList.remove("rush-blink", "rush-red", "late");
    clock.textContent = formatClock(CLOCK_START_SECONDS);
  }
  roomMode = "hall";
  roomTransition = null;
  roomModules["2C"].reset();
  roomModules["3C"].reset();
  input.left = false;
  input.right = false;
  input.up = false;
  input.down = false;
  for (const item of pickups) {
    item.collected = false;
    item.burned = false;
    item.popTime = -1;
  }
  objective.textContent = "Find the letters before the bell.";
  syncHud();
  if (gameStarted && !dialogueActive) startGameClock();
}

function render(time) {
  const delta = Math.min((time - previousTime) / 16.67 || 1, 2);
  previousTime = time;
  if (gameStarted) update(delta);
  if (roomMode === "hall") {
    paintCorridor(time);
    for (const item of pickups) paintPickup(item, time);
    paintPlayer();
    paintComplete();
    paintInteractionNotice();
  } else {
    const roomLetter = pickups.find((item) => item.room === "2C");
    const room = roomModules[roomMode];
    room.draw(paint, scene.width, scene.height, roomLetter);
    paintRoomPlayer();
    room.drawForeground(paint);
    room.paintLighting(paint, scene.width, scene.height, roomPlayerX, player.view);
    paintInteractionNotice();
  }
  paintTransitionOverlay();
  ctx.imageSmoothingEnabled = false;
  const fractionalCamera = roomMode === "hall" ? cameraX - renderCameraX : 0;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(scene, -fractionalCamera * 2, 0, scene.width * 2, scene.height * 2);
  requestAnimationFrame(render);
}

function changeInput(key, pressed) {
  if (!gameStarted || dialogueActive || complete || roomTransition) return;
  if (pressed && key === "e") {
    enableAudio();
    resetIdleTimer();
    if (roomMode !== "hall") inspectRoom();
    return;
  }
  if (roomMode !== "hall") {
    if (pressed) {
      enableAudio();
      resetIdleTimer();
    }
    if (key === "arrowleft" || key === "a") {
      input.left = pressed;
      if (pressed) player.view = null;
    }
    if (key === "arrowright" || key === "d") {
      input.right = pressed;
      if (pressed) player.view = null;
    }
    if (key === "arrowup" || key === "w") {
      const firstPress = pressed && !input.up;
      input.up = pressed;
      if (pressed) player.view = "back";
      if (firstPress) beginHallTransition();
    }
    if (key === "arrowdown" || key === "s") {
      input.down = pressed;
      if (pressed) player.view = "front";
    }
    return;
  }
  if (pressed) {
    enableAudio();
    resetIdleTimer();
  }
  if (key === "arrowleft" || key === "a") {
    input.left = pressed;
    if (pressed) player.view = null;
  }
  if (key === "arrowright" || key === "d") {
    input.right = pressed;
    if (pressed) player.view = null;
  }
  if (key === "arrowup" || key === "w") {
    const firstPress = pressed && !input.up;
    input.up = pressed;
    if (pressed) {
      player.view = "back";
      if (firstPress) interact();
    }
  }
  if (key === "arrowdown" || key === "s") {
    input.down = pressed;
    if (pressed) player.view = "front";
  }
}

window.addEventListener("keydown", (event) => {
  const key = event.key.toLowerCase();
  if (["arrowleft", "arrowright", "arrowup", "arrowdown", "a", "d", "w", "s", "r"].includes(key)) event.preventDefault();
  if (key === "r" && gameStarted) restart();
  changeInput(key, true);
});
window.addEventListener("keyup", (event) => changeInput(event.key.toLowerCase(), false));
window.addEventListener("blur", () => { input.left = false; input.right = false; input.up = false; input.down = false; });

for (const button of document.querySelectorAll("[data-key]")) {
  const keyMap = { left: "arrowleft", right: "arrowright", up: "arrowup", down: "arrowdown", inspect: "e" };
  const key = keyMap[button.dataset.key];
  button.addEventListener("pointerdown", (event) => { event.preventDefault(); changeInput(key, true); });
  button.addEventListener("pointerup", (event) => { event.preventDefault(); changeInput(key, false); });
  button.addEventListener("pointerleave", (event) => { event.preventDefault(); changeInput(key, false); });
  button.addEventListener("pointercancel", (event) => { event.preventDefault(); changeInput(key, false); });
}

window.addEventListener("game:start", () => {
  gameStarted = true;
  dialogueActive = true;
  restart();
});
window.addEventListener("dialogue:complete", (event) => {
  const type = event.detail && event.detail.type;
  if (type === "burned-letter") {
    dialogueActive = true;
    return;
  }
  dialogueActive = false;
  enableAudio();
  if (type === "henshin") {
    kotoneV2Active = true;
    player.animationTime = 0;
    player.idleTime = 0;
    return;
  }
  if (!event.detail || type === "intro") startGameClock();
});

loadWalk("front");
loadWalk("back");
loadWalk("left");
loadWalk("right");
loadKotoneV2("front");
loadKotoneV2("back");
loadKotoneV2("left");
loadKotoneV2("right");
for (const pose of ["foldarm", "clap", "heart", "heel", "idea", "ipad", "thinking", "waving"]) loadIdle(pose);
syncHud();
requestAnimationFrame(render);
