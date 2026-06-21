inlets = 1;
outlets = 1;

var colors = [
	[66, 233, 113],
	[66, 150, 255],
	[255, 82, 82],
	[255, 200, 50],
	[200, 100, 255],
	[255, 150, 50]
];

var boxes = {};
var W = 640;
var H = 360;

function anything() {
	var sel = messagename;
	var val = arrayfromargs(arguments)[0];

	if (sel === "/count") {
		boxes = {};
		if (val == 0) outlet(0, "clear");
		return;
	}

	var parts = sel.split("/");
	if (parts.length >= 3) {
		var id = parts[1];
		var prop = parts[2];
		if (!boxes[id]) boxes[id] = { x: 0, y: 0, w: 0, h: 0 };
		if (prop === "x" || prop === "y" || prop === "w" || prop === "h") {
			boxes[id][prop] = val;
		}
		if (prop === "confidence") redraw();
	}
}

function redraw() {
	outlet(0, "clear");
	outlet(0, "pensize", 3, 3);
	for (var id in boxes) {
		var b = boxes[id];
		var ci = (parseInt(id) - 1) % colors.length;
		var c = colors[ci];
		outlet(0, "frgb", c[0], c[1], c[2]);
		var x1 = Math.round(b.x * W);
		var y1 = Math.round(b.y * H);
		var x2 = Math.round((b.x + b.w) * W);
		var y2 = Math.round((b.y + b.h) * H);
		outlet(0, "framerect", x1, y1, x2, y2);
		outlet(0, "moveto", x1 + 2, y1 + 12);
		outlet(0, "write", "P" + id);
	}
}
