window.rooms = window.rooms || {};

window.rooms.class3C = (() => {
  let lightLevel = 0;
  let flickerDelay = 0;
  let flickerPattern = [];
  let flickerStep = 0;
  let flickerStepTime = 0;
  let boardInspected = false;

  function resetFlicker() {
    lightLevel = 0;
    flickerPattern = [];
    flickerStep = 0;
    flickerStepTime = 0;
    flickerDelay = 1800 + Math.random() * 2600;
  }

  function startFlicker() {
    flickerPattern = [
      { duration: 55, level: 0.9 },
      { duration: 75, level: 0 },
      { duration: 38, level: 0.55 },
      { duration: 95, level: 0 },
      { duration: 180, level: 1 },
    ];
    flickerStep = 0;
    flickerStepTime = flickerPattern[0].duration;
    lightLevel = flickerPattern[0].level;
  }

  function updateFlicker(deltaMs) {
    if (flickerStepTime > 0) {
      flickerStepTime -= deltaMs;
      if (flickerStepTime <= 0) {
        flickerStep += 1;
        if (flickerStep >= flickerPattern.length) {
          lightLevel = 0;
          flickerPattern = [];
          flickerDelay = 1800 + Math.random() * 2600;
        } else {
          const step = flickerPattern[flickerStep];
          flickerStepTime = step.duration;
          lightLevel = step.level;
        }
      }
      return;
    }

    flickerDelay -= deltaMs;
    if (flickerDelay <= 0) startFlicker();
  }

  function block(paint, x, y, width, height, color) {
    paint.fillStyle = color;
    paint.fillRect(Math.round(x), Math.round(y), Math.round(width), Math.round(height));
  }

  function edge(paint, x1, y1, x2, y2, color, width = 1) {
    paint.strokeStyle = color;
    paint.lineWidth = width;
    paint.beginPath();
    paint.moveTo(Math.round(x1), Math.round(y1));
    paint.lineTo(Math.round(x2), Math.round(y2));
    paint.stroke();
  }

  function paintDoorInside(paint) {
    const x = 20;
    block(paint, x - 4, 54, 102, 138, "#202938");
    block(paint, x, 58, 94, 130, "#596271");
    block(paint, x + 4, 62, 86, 49, "#536c72");
    block(paint, x + 9, 67, 76, 39, "#718d8e");
    block(paint, x + 4, 113, 86, 5, "#343d4c");
    block(paint, x + 4, 120, 86, 64, "#626a78");
    block(paint, x + 46, 120, 4, 64, "#464f5e");
    block(paint, x + 11, 129, 30, 3, "#78818b");
    block(paint, x + 58, 129, 30, 3, "#78818b");
    block(paint, x + 39, 151, 5, 8, "#a68546");
    block(paint, x + 52, 151, 5, 8, "#a68546");
    paintRoomSign(paint, false);
  }

  function paintRoomSign(paint, lit) {
    const color = lit ? "#e4bf60" : "#77705e";
    block(paint, 40, 37, 56, 13, lit ? "#d3a94e" : "#383b42");
    paint.fillStyle = color;
    paint.textAlign = "center";
    paint.textBaseline = "alphabetic";
    paint.font = "900 7px ui-monospace, monospace";
    paint.fillText("3-C", 68, 46);
  }

  function paintWindow(paint) {
    block(paint, 132, 48, 120, 111, "#202936");
    block(paint, 138, 54, 108, 99, "#243747");
    block(paint, 142, 58, 100, 91, "#304a57");
    block(paint, 142, 109, 100, 40, "#273c44");
    block(paint, 142, 126, 100, 6, "#405456");
    for (let building = 146; building < 242; building += 26) {
      block(paint, building, 119, 18, 13, "#394951");
      block(paint, building + 3, 122, 12, 7, "#57615d");
    }
    block(paint, 184, 54, 5, 99, "#202936");
    block(paint, 138, 99, 108, 5, "#202936");
  }

  function paintDesk(paint, x, y, width = 64) {
    block(paint, x, y, width, 9, "#3f2f31");
    block(paint, x + 2, y + 2, width - 4, 5, "#765344");
    block(paint, x + 4, y + 9, width - 8, 8, "#4d3940");
    block(paint, x + 9, y + 11, width - 18, 3, "#644746");
    block(paint, x + 7, y + 17, 5, 23, "#242e3b");
    block(paint, x + width - 12, y + 17, 5, 23, "#242e3b");
    edge(paint, x + 6, y + 40, x + 14, y + 40, "#171e29", 2);
    edge(paint, x + width - 14, y + 40, x + width - 6, y + 40, "#171e29", 2);
  }

  function paintBlackboard(paint) {
    block(paint, 270, 47, 194, 75, "#252f32");
    block(paint, 276, 53, 182, 63, "#293d3c");
    edge(paint, 276, 53, 458, 53, "#695746", 2);
    edge(paint, 276, 116, 458, 116, "#171e26", 2);
    paintRunMessage(paint, boardInspected ? "#d6c77d" : "#526a5e");
  }

  function paintRunMessage(paint, color) {
    paint.save();
    paint.strokeStyle = color;
    paint.lineWidth = 2;
    paint.lineCap = "round";
    paint.lineJoin = "round";
    paint.beginPath();

    // Uneven chalk strokes keep the warning handwritten rather than typeset.
    paint.moveTo(307, 98);
    paint.lineTo(307, 68);
    paint.lineTo(322, 68);
    paint.lineTo(328, 73);
    paint.lineTo(327, 81);
    paint.lineTo(320, 85);
    paint.lineTo(308, 84);
    paint.moveTo(319, 85);
    paint.lineTo(331, 99);

    paint.moveTo(340, 68);
    paint.lineTo(341, 92);
    paint.lineTo(347, 98);
    paint.lineTo(358, 98);
    paint.lineTo(364, 92);
    paint.lineTo(365, 68);

    paint.moveTo(378, 98);
    paint.lineTo(378, 68);
    paint.lineTo(400, 98);
    paint.lineTo(400, 68);

    paint.moveTo(416, 68);
    paint.lineTo(415, 88);
    paint.stroke();
    paint.beginPath();
    paint.arc(415, 98, 1.5, 0, Math.PI * 2);
    paint.fillStyle = color;
    paint.fill();
    paint.restore();
  }

  function draw(paint, width, height) {
    paint.save();
    paint.imageSmoothingEnabled = false;
    paint.clearRect(0, 0, width, height);

    block(paint, 0, 0, width, height, "#0c121c");
    block(paint, 0, 29, width, 152, "#59626e");
    block(paint, 0, 29, width, 5, "#333d4b");
    paintDoorInside(paint);
    paintWindow(paint);
    paintBlackboard(paint);

    block(paint, 0, 181, width, height - 181, "#634b4d");
    block(paint, 0, 181, width, 5, "#393641");
    for (let y = 198; y < height; y += 17) edge(paint, 0, y, width, y, "#503f47");
    for (let x = -20; x < width; x += 32) edge(paint, x, 186, x + 18, height, "#503f47");

    paintDesk(paint, 132, 164);
    paintDesk(paint, 204, 164);
    paintDesk(paint, 276, 164);
    paintDesk(paint, 348, 164);
    paintDesk(paint, 420, 164, 52);

    paint.restore();
  }

  function drawForeground(paint) {
    paintDesk(paint, 150, 199, 64);
    paintDesk(paint, 226, 199, 64);
    paintDesk(paint, 302, 199, 64);
    paintDesk(paint, 378, 199, 64);
  }

  function paintLighting(paint, width, height) {
    paint.save();
    const darkness = 0.965 - lightLevel * 0.88;
    paint.fillStyle = `rgba(2, 4, 9, ${darkness})`;
    paint.fillRect(0, 0, width, height);

    paint.shadowColor = "#e8bf5d";
    paint.shadowBlur = 13;
    paintRoomSign(paint, true);
    paint.shadowBlur = 0;
    paint.restore();
  }

  function interact(playerX) {
    if (playerX < 250) return "Nothing to inspect here.";
    boardInspected = true;
    return "The chalk says: RUN.";
  }

  return {
    enter() {
      resetFlicker();
      boardInspected = false;
    },
    update(deltaMs) {
      updateFlicker(deltaMs);
    },
    draw,
    drawForeground,
    paintLighting,
    interact,
    reset() {
      resetFlicker();
      boardInspected = false;
    },
  };
})();
