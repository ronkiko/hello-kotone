window.rooms = window.rooms || {};

window.rooms.class2C = (() => {
  let light = 0;

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
    block(paint, x - 4, 54, 102, 138, "#2c3442");
    block(paint, x, 58, 94, 130, "#737b87");
    block(paint, x + 4, 62, 86, 49, "#9cb6ba");
    block(paint, x + 9, 67, 76, 39, "#c8d8d9");
    block(paint, x + 4, 113, 86, 5, "#535e6b");
    block(paint, x + 4, 120, 86, 64, "#858d97");
    block(paint, x + 46, 120, 4, 64, "#656e79");
    block(paint, x + 11, 129, 30, 3, "#9da4aa");
    block(paint, x + 58, 129, 30, 3, "#9da4aa");
    block(paint, x + 39, 151, 5, 8, "#c7a55f");
    block(paint, x + 52, 151, 5, 8, "#c7a55f");
    block(paint, x + 20, 37, 56, 13, "#e4dfcf");
    paint.fillStyle = "#444653";
    paint.textAlign = "center";
    paint.textBaseline = "alphabetic";
    paint.font = "900 7px ui-monospace, monospace";
    paint.fillText("2-C", x + 48, 46);
  }

  function paintJapaneseClassDisplay(paint) {
    paint.save();
    paint.translate(-10, 0);
    block(paint, 137, 46, 54, 88, "#5b4038");
    block(paint, 142, 51, 44, 78, "#f1eadb");
    paint.fillStyle = "#c84d51";
    paint.beginPath();
    paint.arc(164, 73, 12, 0, Math.PI * 2);
    paint.fill();
    block(paint, 148, 93, 31, 2, "#7a6b63");
    block(paint, 148, 101, 24, 2, "#7a6b63");
    block(paint, 148, 109, 29, 2, "#7a6b63");

    block(paint, 195, 50, 45, 84, "#6d4b3e");
    block(paint, 200, 55, 35, 74, "#e4dfcf");
    block(paint, 216, 61, 3, 55, "#403f43");
    block(paint, 208, 69, 20, 3, "#403f43");
    block(paint, 208, 86, 20, 3, "#403f43");
    block(paint, 208, 103, 16, 3, "#403f43");
    paint.restore();
  }

  function paintDesk(paint, x, y, width = 64) {
    block(paint, x, y, width, 9, "#5a3d36");
    block(paint, x + 2, y + 2, width - 4, 5, "#a8785c");
    block(paint, x + 4, y + 9, width - 8, 8, "#704a3d");
    block(paint, x + 9, y + 11, width - 18, 3, "#8d604c");
    block(paint, x + 7, y + 17, 5, 23, "#394552");
    block(paint, x + width - 12, y + 17, 5, 23, "#394552");
    edge(paint, x + 6, y + 40, x + 14, y + 40, "#252e3a", 2);
    edge(paint, x + width - 14, y + 40, x + width - 6, y + 40, "#252e3a", 2);
  }

  function paintLetter(paint, x, y, item) {
    if (item && item.burned && !item.collected) {
      paint.save();
      paint.shadowColor = "#e45f4f";
      paint.shadowBlur = 5;
      paint.fillStyle = "#493a3d";
      paint.beginPath();
      paint.arc(Math.round(x), Math.round(y), 11, 0, Math.PI * 2);
      paint.fill();
      paint.shadowBlur = 0;
      paint.fillStyle = "#151820";
      paint.textAlign = "center";
      paint.textBaseline = "middle";
      paint.font = "900 14px Georgia, serif";
      paint.fillText("L", x, y + 1);
      paint.fillStyle = "#ef7652";
      paint.fillRect(Math.round(x - 2), Math.round(y - 17), 3, 5);
      paint.fillStyle = "#f2bf62";
      paint.fillRect(Math.round(x + 4), Math.round(y - 14), 2, 3);
      paint.restore();
      return;
    }
    const popping = item && item.collected;
    const progress = popping ? Math.min(1, item.popTime / 420) : 0;
    if (popping && progress >= 1) return;
    paint.save();
    paint.globalAlpha = popping ? 1 - progress : 1;
    paint.shadowColor = "#ffe08a";
    paint.shadowBlur = popping ? 7 * (1 - progress) : 7;
    paint.fillStyle = "#e9be59";
    paint.beginPath();
    paint.arc(Math.round(x), Math.round(y), 11 + progress * 8, 0, Math.PI * 2);
    paint.fill();
    paint.shadowBlur = 0;
    paint.fillStyle = "#483848";
    paint.textAlign = "center";
    paint.textBaseline = "middle";
    paint.font = `900 ${14 + progress * 4}px Georgia, serif`;
    paint.fillText("L", x, y + 1);
    paint.restore();
  }

  function paintLighting(paint, width, height) {
    if (light >= 1) return;
    paint.fillStyle = `rgba(7, 12, 20, ${(1 - light) * 0.72})`;
    paint.fillRect(0, 0, width, height);
  }

  function draw(paint, width, height, letter) {
    paint.save();
    paint.imageSmoothingEnabled = false;
    paint.clearRect(0, 0, width, height);

    block(paint, 0, 0, width, height, "#17212d");
    block(paint, 0, 0, width, 29, "#3c4757");
    for (let x = 10; x < width; x += 38) edge(paint, x, 3, x + 16, 3, "#667384");

    block(paint, 0, 29, width, 152, "#a3aab3");
    block(paint, 0, 29, width, 5, "#596575");
    paintDoorInside(paint);
    paintJapaneseClassDisplay(paint);

    block(paint, 245, 47, 222, 74, "#39433f");
    block(paint, 250, 52, 212, 64, "#526d5e");
    edge(paint, 250, 52, 462, 52, "#b08b68", 2);
    edge(paint, 250, 116, 462, 116, "#2d3734", 2);
    block(paint, 270, 70, 68, 2, "#839b86");
    block(paint, 270, 80, 43, 2, "#839b86");
    block(paint, 270, 90, 57, 2, "#839b86");
    block(paint, 370, 70, 55, 2, "#839b86");
    block(paint, 370, 80, 36, 2, "#839b86");

    block(paint, 0, 181, width, height - 181, "#a67565");
    block(paint, 0, 181, width, 5, "#5a4b53");
    for (let y = 198; y < height; y += 17) edge(paint, 0, y, width, y, "#805d5d");
    for (let x = -20; x < width; x += 32) edge(paint, x, 186, x + 18, height, "#805d5d");

    // One side-view row of desks, leaving a clear walking line in front.
    paintDesk(paint, 132, 164);
    paintDesk(paint, 204, 164);
    paintDesk(paint, 276, 164);
    paintDesk(paint, 348, 164);
    paintDesk(paint, 420, 164, 52);
    paintLetter(paint, 368, 153, letter);

    paint.restore();
  }

  function drawForeground(paint) {
    paintDesk(paint, 150, 199, 64);
    paintDesk(paint, 226, 199, 64);
    paintDesk(paint, 302, 199, 64);
    paintDesk(paint, 378, 199, 64);
  }

  return {
    enter() {
      light = 0;
    },
    update(deltaMs) {
      light = Math.min(1, light + deltaMs / 480);
    },
    draw,
    drawForeground,
    paintLighting,
    reset() {
      light = 0;
    },
  };
})();
