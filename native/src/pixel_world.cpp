// The pixel layer: molten and hardened metal, one material per world pixel.
//
// Molten metal flows like falling sand: each tick, from the bottom row up, a molten pixel
// falls, slides down a slope, or spreads sideways toward level. Heavier iron sinks through
// slag, so slag ends up floating on top. Items are rasterized in each tick as obstacles the
// metal flows around (and pushes up out of the way when an item sinks in). Metal pixels trade
// heat with the heat map, harden when they cool below their freezing point, and melt again
// when heated back past their melting point. Hardened metal gets collision edges so items
// land on it.
//
// Determinism: rows are visited bottom-up and the sideways direction alternates by tick, so
// every choice depends only on the tick and positions; no randomness.

#include "item_world.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

int floor_div(double p_value, double p_cell) {
	return (int)std::floor(p_value / p_cell);
}

// A stable per-pixel number for picking ore's iron/slag mix and for color speckle.
uint32_t pixel_hash(int x, int y) {
	uint32_t h = (uint32_t)x * 374761393u + (uint32_t)y * 668265263u;
	h = (h ^ (h >> 13)) * 1274126177u;
	return h ^ (h >> 16);
}

bool inside_polygon(double x, double y, const double *pts, int n) {
	bool inside = false;
	for (int i = 0, j = n - 1; i < n; j = i++) {
		double xi = pts[i * 2], yi = pts[i * 2 + 1];
		double xj = pts[j * 2], yj = pts[j * 2 + 1];
		if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
			inside = !inside;
		}
	}
	return inside;
}

bool is_molten(uint8_t m) {
	return m == ItemWorld::PIX_IRON || m == ItemWorld::PIX_SLAG;
}

bool is_hardened(uint8_t m) {
	return m == ItemWorld::PIX_SOLID_IRON || m == ItemWorld::PIX_SOLID_SLAG;
}

} // namespace

// --- Building ------------------------------------------------------------------------

template <typename Inside>
void ItemWorld::_fill_pixels(double p_x0, double p_y0, double p_x1, double p_y1, Inside p_inside) {
	int x0 = std::max(0, floor_div(p_x0, 1.0));
	int x1 = std::min(pix_w - 1, floor_div(p_x1, 1.0));
	int y0 = std::max(0, floor_div(p_y0, 1.0));
	int y1 = std::min(pix_h - 1, floor_div(p_y1, 1.0));
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			if (p_inside(x + 0.5, y + 0.5)) {
				pix[(size_t)y * pix_w + x] = PIX_WALL;
			}
		}
	}
}

// Marks the pixels a part fills as wall: molten metal can't flow into them.
void ItemWorld::pixel_fill_rect(double p_x0, double p_y0, double p_x1, double p_y1) {
	_fill_pixels(p_x0, p_y0, p_x1, p_y1, [&](double x, double y) {
		return x >= p_x0 && x < p_x1 && y >= p_y0 && y < p_y1;
	});
}

void ItemWorld::pixel_fill_polygon(const PackedFloat64Array &p_points) {
	int n = (int)p_points.size() / 2;
	std::vector<double> pts(p_points.size());
	double x0 = 1e18, y0 = 1e18, x1 = -1e18, y1 = -1e18;
	for (int i = 0; i < n; i++) {
		pts[i * 2] = p_points[i * 2];
		pts[i * 2 + 1] = p_points[i * 2 + 1];
		x0 = std::min(x0, pts[i * 2]);
		x1 = std::max(x1, pts[i * 2]);
		y0 = std::min(y0, pts[i * 2 + 1]);
		y1 = std::max(y1, pts[i * 2 + 1]);
	}
	_fill_pixels(x0, y0, x1, y1, [&](double x, double y) {
		return inside_polygon(x, y, pts.data(), n);
	});
}

void ItemWorld::set_melt_point(int p_kind, double p_temp) {
	if (p_kind >= (int)melt_points.size()) {
		melt_points.resize(p_kind + 1, 0.0);
	}
	melt_points[p_kind] = p_temp;
}

// Pours molten iron (or slag) into the empty pixels of a rectangle (for tests and set pieces).
void ItemWorld::add_liquid(double p_x0, double p_y0, double p_x1, double p_y1, bool p_iron, double p_temp) {
	for (int y = std::max(0, (int)p_y0); y < std::min(pix_h, (int)p_y1); y++) {
		for (int x = std::max(0, (int)p_x0); x < std::min(pix_w, (int)p_x1); x++) {
			if (pix[(size_t)y * pix_w + x] == PIX_EMPTY) {
				_place_pixel(x, y, p_iron ? PIX_IRON : PIX_SLAG, (float)p_temp);
			}
		}
	}
}

// A skimmer's box: molten slag touching its edge is taken off and dropped as slag lumps.
int ItemWorld::add_skimmer(double p_x0, double p_y0, double p_x1, double p_y1, const PackedInt32Array &p_slag_types) {
	Skimmer sk;
	sk.x0 = p_x0;
	sk.y0 = p_y0;
	sk.x1 = p_x1;
	sk.y1 = p_y1;
	for (int i = 0; i < p_slag_types.size(); i++) {
		sk.slag_types.push_back(p_slag_types[i]);
	}
	skimmers.push_back(sk);
	return (int)skimmers.size() - 1;
}

// --- Each tick -----------------------------------------------------------------------

void ItemWorld::_step_pixels() {
	if (pix.empty()) {
		return;
	}
	_touch_liquid_items();
	_melt_items();
	_flow_liquids();
	_pixel_heat();
	_run_skimmers();
	if (solids_changed && tick % SOLID_REBUILD_TICKS == 0) {
		_rebuild_solid_edges();
	}
}

// Marks where items near molten metal sit, so the metal flows around them. An item sinking
// into molten metal pushes it up out of the way, picks up its heat, is slowed, and is lifted
// in proportion to how much of it is in molten iron (ore and rock float on iron).
void ItemWorld::_touch_liquid_items() {
	for (int i : item_pixels) {
		pix_item[i] = 0;
	}
	item_pixels.clear();
	if (liq_x0 > liq_x1) {
		return;
	}
	int reach = DISPLACE_REACH;
	for (Body &it : items) {
		const ItemType &t = types[it.type];
		if (it.x + t.radius < liq_x0 - reach || it.x - t.radius > liq_x1 + reach || it.y + t.radius < liq_y0 - reach || it.y - t.radius > liq_y1 + reach) {
			continue;
		}
		double corners[MAX_CORNERS * 2];
		for (int k = 0; k < t.count; k++) {
			corners[k * 2] = it.x + it.c * t.local[k * 2] - it.s * t.local[k * 2 + 1];
			corners[k * 2 + 1] = it.y + it.s * t.local[k * 2] + it.c * t.local[k * 2 + 1];
		}
		int x0 = std::max(0, floor_div(it.x - t.radius, 1.0));
		int x1 = std::min(pix_w - 1, floor_div(it.x + t.radius, 1.0));
		int y0 = std::max(0, floor_div(it.y - t.radius, 1.0));
		int y1 = std::min(pix_h - 1, floor_div(it.y + t.radius, 1.0));
		int area = 0, in_metal = 0, in_iron = 0;
		double hottest = -1.0;
		for (int y = y0; y <= y1; y++) {
			for (int x = x0; x <= x1; x++) {
				if (!inside_polygon(x + 0.5, y + 0.5, corners, t.count)) {
					continue;
				}
				area++;
				int i = y * pix_w + x;
				if (is_molten(pix[i])) {
					in_metal++;
					in_iron += pix[i] == PIX_IRON ? 1 : 0;
					hottest = std::max(hottest, (double)pix_temp[i]);
					// Push the metal up its column to the first free pixel.
					for (int up = 1; up <= reach && y - up >= 0; up++) {
						int j = i - up * pix_w;
						if (pix[j] == PIX_EMPTY && !pix_item[j]) {
							_move_pixel(i, j);
							break;
						}
						if (pix[j] == PIX_WALL || is_hardened(pix[j])) {
							break;
						}
					}
				}
				if (pix[i] == PIX_EMPTY) {
					pix_item[i] = 1;
					item_pixels.push_back(i);
				}
			}
		}
		if (in_metal > 0 && area > 0) {
			_wake(it);
			it.temp += (hottest - it.temp) * std::min(1.0, LIQUID_ITEM_HEATING * (double)(1 << t.size_rank));
			it.vy -= BUOYANCY * GRAVITY / TICK_RATE * (double)in_iron / area;
			it.vx *= LIQUID_DRAG;
			it.vy *= LIQUID_DRAG;
			it.w *= LIQUID_DRAG;
		}
	}
}

// Items hotter than their material's melting point turn into molten pixels in their own
// shape: iron ore into mostly iron with some slag, rock and slag into slag, scrap into iron.
void ItemWorld::_melt_items() {
	std::vector<Body> kept;
	std::vector<std::pair<double, double>> melted;
	for (const Body &it : items) {
		int kind = types[it.type].kind;
		double melt = kind < (int)melt_points.size() ? melt_points[kind] : 0.0;
		if (melt > 0.0 && it.temp >= melt) {
			_melt_into_pixels(it);
			melted.emplace_back(it.x, it.y);
		} else {
			kept.push_back(it);
		}
	}
	if (melted.empty()) {
		return;
	}
	items.swap(kept);
	for (const auto &m : melted) {
		_wake_near(m.first, m.second);
	}
}

void ItemWorld::_melt_into_pixels(const Body &it) {
	const ItemType &t = types[it.type];
	double corners[MAX_CORNERS * 2];
	for (int k = 0; k < t.count; k++) {
		corners[k * 2] = it.x + it.c * t.local[k * 2] - it.s * t.local[k * 2 + 1];
		corners[k * 2 + 1] = it.y + it.s * t.local[k * 2] + it.c * t.local[k * 2 + 1];
	}
	// Material kinds are registered in ItemDefs.ORDER: 0 iron ore, 1 rock, 2 scrap iron, 3 slag.
	for (int y = std::max(0, floor_div(it.y - t.radius, 1.0)); y <= std::min(pix_h - 1, floor_div(it.y + t.radius, 1.0)); y++) {
		for (int x = std::max(0, floor_div(it.x - t.radius, 1.0)); x <= std::min(pix_w - 1, floor_div(it.x + t.radius, 1.0)); x++) {
			if (!inside_polygon(x + 0.5, y + 0.5, corners, t.count)) {
				continue;
			}
			bool iron = t.kind == 2 || (t.kind == 0 && (pixel_hash(x, y) & 1023) < (uint32_t)(ORE_IRON * 1024.0));
			_place_pixel(x, y, iron ? PIX_IRON : PIX_SLAG, (float)it.temp);
		}
	}
}

// Puts molten metal at (x, y), or in the first free pixel above it if that's taken.
void ItemWorld::_place_pixel(int x, int y, uint8_t material, float temp) {
	for (; y >= 0; y--) {
		int i = y * pix_w + x;
		if (pix[i] == PIX_EMPTY) {
			pix[i] = material;
			pix_temp[i] = temp;
			pix_moved[i] = tick;
			pix_dir[i] = ((x + y) & 1) ? 1 : -1;
			_grow_box(liq_x0, liq_y0, liq_x1, liq_y1, x, y);
			_dirty(x, y);
			return;
		}
		if (pix[i] == PIX_WALL) {
			return;
		}
	}
}

void ItemWorld::_flow_liquids() {
	if (liq_x0 > liq_x1) {
		return;
	}
	int spread = std::max(IRON_SPREAD, SLAG_SPREAD) + 1;
	int x0 = std::max(0, liq_x0 - spread), x1 = std::min(pix_w - 1, liq_x1 + spread);
	int y0 = std::max(0, liq_y0 - 1), y1 = std::min(pix_h - 1, liq_y1 + 1);
	liq_x0 = liq_y0 = 1;
	liq_x1 = liq_y1 = 0;
	bool right_to_left = (tick & 1) != 0;
	for (int y = y1; y >= y0; y--) {
		for (int k = 0; k <= x1 - x0; k++) {
			int x = right_to_left ? x1 - k : x0 + k;
			int i = y * pix_w + x;
			if (!is_molten(pix[i]) || pix_moved[i] == tick) {
				continue;
			}
			_flow_one(x, y);
		}
	}
	// Anything that didn't move still counts toward where molten metal is.
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			if (is_molten(pix[y * pix_w + x])) {
				_grow_box(liq_x0, liq_y0, liq_x1, liq_y1, x, y);
			}
		}
	}
}

// Moves one molten pixel: straight down (swapping with lighter slag if it's iron), else down
// a slope, else sideways, taking the first way that's free. Sideways it tries the way it's
// already flowing first, and turns around when that's blocked.
bool ItemWorld::_flow_one(int x, int y) {
	int i = y * pix_w + x;
	uint8_t m = pix[i];
	if (y + 1 >= pix_h) {
		// Fell out of the world.
		pix[i] = PIX_EMPTY;
		_dirty(x, y);
		return true;
	}
	auto free_at = [&](int j) { return pix[j] == PIX_EMPTY && !pix_item[j]; };
	int below = i + pix_w;
	if (free_at(below) || (m == PIX_IRON && pix[below] == PIX_SLAG && pix_moved[below] != tick)) {
		_move_pixel(i, below);
		return true;
	}
	int first = pix_dir[i];
	for (int d : { first, -first }) {
		int nx = x + d;
		if (nx >= 0 && nx < pix_w && free_at(below + d)) {
			pix_dir[i] = (int8_t)d;
			_move_pixel(i, below + d);
			return true;
		}
	}
	int reach = m == PIX_IRON ? IRON_SPREAD : SLAG_SPREAD;
	for (int d : { first, -first }) {
		int target = -1;
		for (int step = 1; step <= reach; step++) {
			int nx = x + d * step;
			if (nx < 0 || nx >= pix_w || !free_at(i + d * step)) {
				break;
			}
			target = i + d * step;
			// Stop where it can fall again, so it pours off ledges instead of skating past.
			if (free_at(target + pix_w)) {
				break;
			}
		}
		if (target >= 0) {
			pix_dir[i] = (int8_t)d;
			_move_pixel(i, target);
			return true;
		}
	}
	return false;
}

// Swaps two pixels (the destination may be empty or slag being displaced by iron).
void ItemWorld::_move_pixel(int from, int to) {
	std::swap(pix[from], pix[to]);
	std::swap(pix_temp[from], pix_temp[to]);
	std::swap(pix_dir[from], pix_dir[to]);
	pix_moved[to] = tick;
	if (pix[from] != PIX_EMPTY) {
		pix_moved[from] = tick;
	}
	_dirty(from % pix_w, from / pix_w);
	_dirty(to % pix_w, to / pix_w);
}

// Metal pixels trade heat with their heat cell; molten metal that cools enough hardens and
// hardened metal heated enough melts again.
void ItemWorld::_pixel_heat() {
	int x0 = std::min(liq_x0 > liq_x1 ? pix_w : liq_x0, sol_x0 > sol_x1 ? pix_w : sol_x0);
	int x1 = std::max(liq_x0 > liq_x1 ? -1 : liq_x1, sol_x0 > sol_x1 ? -1 : sol_x1);
	int y0 = std::min(liq_x0 > liq_x1 ? pix_h : liq_y0, sol_x0 > sol_x1 ? pix_h : sol_y0);
	int y1 = std::max(liq_x0 > liq_x1 ? -1 : liq_y1, sol_x0 > sol_x1 ? -1 : sol_y1);
	heat_eff = heat_mat;
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			int i = y * pix_w + x;
			uint8_t m = pix[i];
			if (!is_molten(m) && !is_hardened(m)) {
				continue;
			}
			int c = _heat_cell(x + 0.5, y + 0.5);
			if (c < 0) {
				continue;
			}
			if (heat_eff[c] == HEAT_AIR) {
				heat_eff[c] = HEAT_METAL;
			}
			double t = pix_temp[i];
			double shift = (heat[c] - t) * PIXEL_HEAT_RATE;
			t += shift;
			heat[c] -= shift * PIXEL_HEAT_SHARE;
			pix_temp[i] = (float)t;
			if (m == PIX_IRON && t < IRON_FREEZE) {
				pix[i] = PIX_SOLID_IRON;
			} else if (m == PIX_SLAG && t < SLAG_FREEZE) {
				pix[i] = PIX_SOLID_SLAG;
			} else if (m == PIX_SOLID_IRON && t >= IRON_MELT) {
				pix[i] = PIX_IRON;
			} else if (m == PIX_SOLID_SLAG && t >= SLAG_MELT) {
				pix[i] = PIX_SLAG;
			} else {
				if (is_molten(m) || t > GLOW_START) {
					_dirty(x, y);
				}
				continue;
			}
			// Changed between molten and hardened.
			solids_changed = true;
			if (is_hardened(pix[i])) {
				_grow_box(sol_x0, sol_y0, sol_x1, sol_y1, x, y);
			} else {
				_grow_box(liq_x0, liq_y0, liq_x1, liq_y1, x, y);
			}
			_dirty(x, y);
		}
	}
}

// Each skimmer takes molten slag touching its edge and drops it as lumps out the side away
// from where the slag was.
void ItemWorld::_run_skimmers() {
	for (Skimmer &sk : skimmers) {
		int x0 = (int)sk.x0 - 1, x1 = (int)sk.x1, y0 = (int)sk.y0 - 1, y1 = (int)sk.y1;
		int taken = 0;
		for (int y = std::max(0, y0); y <= std::min(pix_h - 1, y1) && taken < SKIM_PER_TICK; y++) {
			for (int x = std::max(0, x0); x <= std::min(pix_w - 1, x1) && taken < SKIM_PER_TICK; x++) {
				bool edge = x == x0 || x == x1 || y == y0 || y == y1;
				int i = y * pix_w + x;
				if (edge && pix[i] == PIX_SLAG) {
					pix[i] = PIX_EMPTY;
					_dirty(x, y);
					sk.side += x - (sk.x0 + sk.x1) * 0.5;
					taken++;
				}
			}
		}
		sk.taken += taken;
		if (sk.taken >= SKIM_LUMP && !sk.slag_types.empty()) {
			int type = sk.slag_types[sk.lumps % sk.slag_types.size()];
			double r = types[type].radius;
			double dir = sk.side > 0.0 ? -1.0 : 1.0;
			double x = dir > 0.0 ? sk.x1 + r + 0.5 : sk.x0 - r - 0.5;
			Body lump;
			_init_body(lump, type, x, (sk.y0 + sk.y1) * 0.5, 1.0, 0.0);
			lump.temp = SLAG_FREEZE;
			lump.vx = dir * 30.0;
			items.push_back(lump);
			sk.taken -= SKIM_LUMP;
			sk.side = 0.0;
			sk.lumps++;
		}
	}
}

// Hardened metal's outline (pixel edges facing anything that isn't hardened metal or a part's
// wall) becomes collision segments, joined into straight runs, on top of the parts' walls.
void ItemWorld::_rebuild_solid_edges() {
	solids_changed = false;
	std::vector<Segment> edges;
	auto open = [&](int x, int y) {
		if (x < 0 || y < 0 || x >= pix_w || y >= pix_h) {
			return true;
		}
		uint8_t m = pix[y * pix_w + x];
		return !is_hardened(m) && m != PIX_WALL;
	};
	int nx0 = 1, ny0 = 1, nx1 = 0, ny1 = 0;
	for (int y = std::max(0, sol_y0); y <= std::min(pix_h - 1, sol_y1); y++) {
		for (int x = std::max(0, sol_x0); x <= std::min(pix_w - 1, sol_x1); x++) {
			if (!is_hardened(pix[y * pix_w + x])) {
				continue;
			}
			_grow_box(nx0, ny0, nx1, ny1, x, y);
			if (open(x, y - 1)) {
				edges.push_back(make_wall(x, y, x + 1, y));
			}
			if (open(x, y + 1)) {
				edges.push_back(make_wall(x, y + 1, x + 1, y + 1));
			}
			if (open(x - 1, y)) {
				edges.push_back(make_wall(x, y, x, y + 1));
			}
			if (open(x + 1, y)) {
				edges.push_back(make_wall(x + 1, y, x + 1, y + 1));
			}
		}
	}
	sol_x0 = nx0;
	sol_y0 = ny0;
	sol_x1 = nx1;
	sol_y1 = ny1;
	segments = base_segments;
	std::vector<Segment> merged = merge_walls(edges);
	segments.insert(segments.end(), merged.begin(), merged.end());
	_index_segments();
}

void ItemWorld::_grow_box(int &x0, int &y0, int &x1, int &y1, int x, int y) {
	if (x0 > x1) {
		x0 = x1 = x;
		y0 = y1 = y;
		return;
	}
	x0 = std::min(x0, x);
	x1 = std::max(x1, x);
	y0 = std::min(y0, y);
	y1 = std::max(y1, y);
}

void ItemWorld::_dirty(int x, int y) {
	chunk_dirty[(size_t)(y / CHUNK) * chunk_cols + x / CHUNK] = 1;
}

// --- Reading -------------------------------------------------------------------------

Dictionary ItemWorld::pixel_counts() const {
	int64_t count[6] = {};
	double sum_y[6] = {};
	for (int y = 0; y < pix_h; y++) {
		for (int x = 0; x < pix_w; x++) {
			uint8_t m = pix[(size_t)y * pix_w + x];
			count[m]++;
			sum_y[m] += y;
		}
	}
	Dictionary d;
	const char *names[6] = { "", "", "iron", "slag", "solid_iron", "solid_slag" };
	for (int m = PIX_IRON; m <= PIX_SOLID_SLAG; m++) {
		d[names[m]] = count[m];
		d[String(names[m]) + "_y"] = count[m] > 0 ? sum_y[m] / count[m] : 0.0;
	}
	return d;
}

int ItemWorld::pixel_at(int p_x, int p_y) const {
	if (p_x < 0 || p_y < 0 || p_x >= pix_w || p_y >= pix_h) {
		return PIX_EMPTY;
	}
	return pix[(size_t)p_y * pix_w + p_x];
}

// The chunks whose look changed since the last call.
PackedInt32Array ItemWorld::dirty_chunks() {
	PackedInt32Array result;
	for (int i = 0; i < (int)chunk_dirty.size(); i++) {
		if (chunk_dirty[i]) {
			result.push_back(i);
			chunk_dirty[i] = 0;
		}
	}
	return result;
}

// One CHUNK x CHUNK block of metal pixels as RGBA, or empty if it has no metal in it.
// Molten iron glows by temperature, molten slag is a dull red-orange, hardened metal is gray
// (iron) or near black (slag) and still glows while hot.
PackedByteArray ItemWorld::chunk_image(int p_chunk) const {
	PackedByteArray data;
	int cx = p_chunk % chunk_cols, cy = p_chunk / chunk_cols;
	data.resize(CHUNK * CHUNK * 4);
	uint8_t *w = data.ptrw();
	bool any = false;
	for (int ly = 0; ly < CHUNK; ly++) {
		for (int lx = 0; lx < CHUNK; lx++) {
			int x = cx * CHUNK + lx, y = cy * CHUNK + ly;
			double c[4] = { 0.0, 0.0, 0.0, 0.0 };
			if (x < pix_w && y < pix_h) {
				int i = y * pix_w + x;
				uint8_t m = pix[i];
				double t = pix_temp[i];
				double speck = ((pixel_hash(x, y) & 15) - 7.5) / 160.0;
				double g[4];
				glow_color(t, g);
				if (m == PIX_IRON) {
					glow_color(std::max(t, 1350.0), g);
					c[0] = g[0];
					c[1] = g[1];
					c[2] = g[2];
					c[3] = 1.0;
				} else if (m == PIX_SLAG) {
					double heat_share = std::min(1.0, std::max(0.0, (t - SLAG_FREEZE) / 600.0));
					c[0] = 0.55 + 0.3 * heat_share;
					c[1] = 0.20 + 0.15 * heat_share;
					c[2] = 0.08;
					c[3] = 1.0;
				} else if (is_hardened(m)) {
					double base = m == PIX_SOLID_IRON ? 0.55 : 0.23;
					c[0] = base + g[0] * g[3] * 0.8;
					c[1] = base + 0.02 + g[1] * g[3] * 0.8;
					c[2] = base + 0.05 + g[2] * g[3] * 0.8;
					c[3] = 1.0;
				}
				if (c[3] > 0.0) {
					any = true;
					for (int k = 0; k < 3; k++) {
						c[k] = std::min(1.0, std::max(0.0, c[k] + speck));
					}
				}
			}
			for (int k = 0; k < 4; k++) {
				w[(ly * CHUNK + lx) * 4 + k] = (uint8_t)(c[k] * 255.0 + 0.5);
			}
		}
	}
	return any ? data : PackedByteArray();
}
