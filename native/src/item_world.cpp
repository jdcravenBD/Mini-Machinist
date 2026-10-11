#include "item_world.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

namespace {

// Starting rotations for spawned items, as exact unit vectors (cos, sin).
constexpr double SPAWN_ROTATIONS[] = { 1.0, 0.0, 0.6, 0.8, -0.8, 0.6, 0.0, -1.0, 0.8, -0.6 };
constexpr int SPAWN_ROTATION_COUNT = 5;

int floor_div(double p_value, double p_cell) {
	return (int)std::floor(p_value / p_cell);
}

ItemWorld::Segment make_segment(double ax, double ay, double bx, double by, double speed, double friction, int passes, bool belt, int group) {
	ItemWorld::Segment s;
	s.ax = ax;
	s.ay = ay;
	s.bx = bx;
	s.by = by;
	s.dx = bx - ax;
	s.dy = by - ay;
	s.len_sq = s.dx * s.dx + s.dy * s.dy;
	s.length = std::sqrt(s.len_sq);
	s.tx = s.dx / s.length;
	s.ty = s.dy / s.length;
	s.nx = s.ty;
	s.ny = -s.tx;
	s.speed = speed;
	s.friction = friction;
	s.passes = passes;
	s.belt = belt;
	s.group = group;
	return s;
}

bool is_flat(const ItemWorld::Segment &s) { return s.ay == s.by; }
bool is_upright(const ItemWorld::Segment &s) { return s.ax == s.bx; }

// True if `next` lies on the same line as `run`, behaves the same, and starts where `run`
// ends (or before).
bool continues(const ItemWorld::Segment &run, const ItemWorld::Segment &next) {
	if (run.speed != next.speed || run.friction != next.friction || run.passes != next.passes || run.belt != next.belt || run.group != next.group) {
		return false;
	}
	if (is_flat(run)) {
		return is_flat(next) && next.ay == run.ay && next.ax <= run.bx;
	}
	return is_upright(next) && next.ax == run.ax && is_upright(run) && next.ay <= run.by;
}

// Joins touching horizontal or vertical segments that lie on the same line and behave the
// same, so a row of conveyors becomes one long belt and items glide across the seams.
std::vector<ItemWorld::Segment> merge_runs(const std::vector<ItemWorld::Segment> &input) {
	std::vector<ItemWorld::Segment> straight;
	std::vector<ItemWorld::Segment> result;
	for (ItemWorld::Segment s : input) {
		// Point each straight segment toward +x or +y (flipping a belt flips its speed too).
		if ((is_flat(s) && s.ax > s.bx) || (is_upright(s) && s.ay > s.by)) {
			s = make_segment(s.bx, s.by, s.ax, s.ay, -s.speed, s.friction, s.passes, s.belt, s.group);
		}
		if (is_flat(s) || is_upright(s)) {
			straight.push_back(s);
		} else {
			result.push_back(s);
		}
	}
	std::sort(straight.begin(), straight.end(), [](const ItemWorld::Segment &p, const ItemWorld::Segment &q) {
		bool p_flat = is_flat(p);
		bool q_flat = is_flat(q);
		if (p_flat != q_flat) {
			return p_flat;
		}
		double p_line = p_flat ? p.ay : p.ax;
		double q_line = q_flat ? q.ay : q.ax;
		if (p_line != q_line) {
			return p_line < q_line;
		}
		if (p.speed != q.speed) {
			return p.speed < q.speed;
		}
		if (p.friction != q.friction) {
			return p.friction < q.friction;
		}
		if (p.passes != q.passes) {
			return p.passes < q.passes;
		}
		if (p.belt != q.belt) {
			return !p.belt;
		}
		if (p.group != q.group) {
			return p.group < q.group;
		}
		double p_start = p_flat ? p.ax : p.ay;
		double q_start = q_flat ? q.ax : q.ay;
		if (p_start != q_start) {
			return p_start < q_start;
		}
		return (p_flat ? p.bx : p.by) < (q_flat ? q.bx : q.by);
	});

	bool have_run = false;
	ItemWorld::Segment run;
	for (const ItemWorld::Segment &s : straight) {
		if (have_run && continues(run, s)) {
			if (is_flat(s)) {
				if (s.bx > run.bx) {
					run = make_segment(run.ax, run.ay, s.bx, s.by, run.speed, run.friction, run.passes, run.belt, run.group);
				}
			} else if (s.by > run.by) {
				run = make_segment(run.ax, run.ay, s.bx, s.by, run.speed, run.friction, run.passes, run.belt, run.group);
			}
			continue;
		}
		if (have_run) {
			result.push_back(run);
		}
		run = s;
		have_run = true;
	}
	if (have_run) {
		result.push_back(run);
	}
	return result;
}

} // namespace

// --- Building ------------------------------------------------------------------------

void ItemWorld::set_bounds(int p_cols, int p_rows) {
	cols = p_cols;
	rows = p_rows;
	solid.assign((size_t)cols * rows, SOLID_NONE);
	kill_min_x = -64.0;
	kill_max_x = cols * SEG_CELL + 64.0;
	kill_max_y = rows * SEG_CELL + 64.0;
	grid_cols = (int)std::ceil((cols * SEG_CELL + GRID_MARGIN * 2.0) / ITEM_CELL);
	grid_rows = (int)std::ceil((rows * SEG_CELL + GRID_MARGIN * 2.0) / ITEM_CELL);
	cell_head.assign((size_t)grid_cols * grid_rows, -1);
	seg_cols = cols + SEG_MARGIN * 2;
	seg_rows = rows + SEG_MARGIN * 2;
	seg_grid.assign((size_t)seg_cols * seg_rows, std::vector<int>());
}

void ItemWorld::set_solid(int p_cx, int p_cy, int p_kind) {
	if (p_cx >= 0 && p_cy >= 0 && p_cx < cols && p_cy < rows) {
		solid[(size_t)p_cy * cols + p_cx] = (uint8_t)p_kind;
	}
}

void ItemWorld::add_segment(double p_ax, double p_ay, double p_bx, double p_by, double p_speed, double p_friction, int p_passes, bool p_belt, int p_group) {
	segments.push_back(make_segment(p_ax, p_ay, p_bx, p_by, p_speed, p_friction, p_passes, p_belt, p_group));
	if (p_group >= (int)groups_off.size()) {
		groups_off.resize(p_group + 1, false);
	}
}

// Switches a group of walls off (items pass through them) or back on.
void ItemWorld::set_group_enabled(int p_group, bool p_enabled) {
	if (p_group >= 0 && p_group < (int)groups_off.size()) {
		groups_off[p_group] = !p_enabled;
	}
}

// Wakes every item whose center is in the area and sets its velocity (a tipping crucible
// throwing out what was sitting in its mouth).
void ItemWorld::push_items(double p_min_x, double p_min_y, double p_max_x, double p_max_y, double p_vx, double p_vy) {
	for (Body &it : items) {
		if (it.x > p_min_x && it.x < p_max_x && it.y > p_min_y && it.y < p_max_y) {
			_wake(it);
			it.vx = p_vx;
			it.vy = p_vy;
		}
	}
}

void ItemWorld::finish_build() {
	segments = merge_runs(segments);
	for (std::vector<int> &cell : seg_grid) {
		cell.clear();
	}
	for (int index = 0; index < (int)segments.size(); index++) {
		const Segment &s = segments[index];
		int x0 = floor_div(std::min(s.ax, s.bx) - MAX_RADIUS - 1.0, SEG_CELL) + SEG_MARGIN;
		int x1 = floor_div(std::max(s.ax, s.bx) + MAX_RADIUS + 1.0, SEG_CELL) + SEG_MARGIN;
		int y0 = floor_div(std::min(s.ay, s.by) - MAX_RADIUS - 1.0, SEG_CELL) + SEG_MARGIN;
		int y1 = floor_div(std::max(s.ay, s.by) + MAX_RADIUS + 1.0, SEG_CELL) + SEG_MARGIN;
		for (int cy = std::max(y0, 0); cy <= std::min(y1, seg_rows - 1); cy++) {
			for (int cx = std::max(x0, 0); cx <= std::min(x1, seg_cols - 1); cx++) {
				seg_grid[(size_t)cy * seg_cols + cx].push_back(index);
			}
		}
	}
}

// `p_outline` is flat x, y pairs going clockwise on screen, centered on the center of mass.
int ItemWorld::register_type(int p_kind, int p_size_rank, int p_shape, const PackedFloat64Array &p_outline) {
	ItemType t;
	t.kind = p_kind;
	t.size_rank = p_size_rank;
	t.shape = p_shape;
	t.count = std::min((int)p_outline.size() / 2, MAX_CORNERS);
	for (int i = 0; i < t.count * 2; i++) {
		t.local[i] = p_outline[i];
	}
	double area = 0.0;
	double inertia = 0.0;
	double radius_sq = 0.0;
	for (int i = 0; i < t.count; i++) {
		int j = (i + 1) % t.count;
		double ax = t.local[i * 2], ay = t.local[i * 2 + 1];
		double bx = t.local[j * 2], by = t.local[j * 2 + 1];
		double cross = ax * by - ay * bx;
		area += cross;
		inertia += cross * (ax * ax + ax * bx + bx * bx + ay * ay + ay * by + by * by);
		double ex = bx - ax, ey = by - ay;
		double length = std::sqrt(ex * ex + ey * ey);
		t.normals[i * 2] = ey / length;
		t.normals[i * 2 + 1] = -ex / length;
		radius_sq = std::max(radius_sq, ax * ax + ay * ay);
	}
	area *= 0.5;
	inertia /= 12.0;
	t.radius = std::sqrt(radius_sq);
	t.inv_mass = 1.0 / area;
	t.inv_inertia = 1.0 / inertia;
	types.push_back(t);
	int id = (int)types.size() - 1;
	type_lookup[type_key(p_kind, p_size_rank, p_shape)] = id;
	return id;
}

void ItemWorld::add_spawner(double p_x, double p_y, int p_interval, const PackedInt32Array &p_ore_types, const PackedInt32Array &p_rock_types) {
	Spawner sp;
	sp.x = p_x;
	sp.y = p_y;
	sp.interval = p_interval;
	for (int i = 0; i < p_ore_types.size(); i++) {
		sp.ore_types.push_back(p_ore_types[i]);
	}
	for (int i = 0; i < p_rock_types.size(); i++) {
		sp.rock_types.push_back(p_rock_types[i]);
	}
	spawners.push_back(sp);
}

int ItemWorld::add_bin(double p_min_x, double p_min_y, double p_max_x, double p_max_y) {
	Bin b;
	b.min_x = p_min_x;
	b.min_y = p_min_y;
	b.max_x = p_max_x;
	b.max_y = p_max_y;
	bins.push_back(b);
	return (int)bins.size() - 1;
}

int ItemWorld::add_crusher(int p_takes, int p_makes, int p_pieces, int p_duration, double p_min_x, double p_min_y, double p_max_x, double p_max_y, double p_press_y, double p_exit_x, double p_exit_y) {
	Crusher cr;
	cr.takes = p_takes;
	cr.makes = p_makes;
	cr.pieces = p_pieces;
	cr.duration = p_duration;
	cr.min_x = p_min_x;
	cr.min_y = p_min_y;
	cr.max_x = p_max_x;
	cr.max_y = p_max_y;
	cr.press_y = p_press_y;
	cr.exit_x = p_exit_x;
	cr.exit_y = p_exit_y;
	crushers.push_back(cr);
	return (int)crushers.size() - 1;
}

int ItemWorld::add_sorter(double p_min_x, double p_min_y, double p_max_x, double p_max_y, int p_filter, double p_out_x, double p_out_y, double p_out_vx, double p_drop_x, double p_drop_y) {
	Sorter so;
	so.min_x = p_min_x;
	so.min_y = p_min_y;
	so.max_x = p_max_x;
	so.max_y = p_max_y;
	so.filter = p_filter;
	so.out_x = p_out_x;
	so.out_y = p_out_y;
	so.out_vx = p_out_vx;
	so.drop_x = p_drop_x;
	so.drop_y = p_drop_y;
	sorters.push_back(so);
	return (int)sorters.size() - 1;
}

int ItemWorld::add_intake(double p_min_x, double p_min_y, double p_max_x, double p_max_y) {
	Intake in;
	in.min_x = p_min_x;
	in.min_y = p_min_y;
	in.max_x = p_max_x;
	in.max_y = p_max_y;
	intakes.push_back(in);
	return (int)intakes.size() - 1;
}

void ItemWorld::set_intake_open(int p_intake, bool p_open) {
	if (p_intake >= 0 && p_intake < (int)intakes.size()) {
		intakes[p_intake].open = p_open;
	}
}

// The type ids of everything the intake swallowed since the last call.
PackedInt32Array ItemWorld::take_intake(int p_intake) {
	PackedInt32Array result;
	if (p_intake >= 0 && p_intake < (int)intakes.size()) {
		for (int type : intakes[p_intake].taken) {
			result.push_back(type);
		}
		intakes[p_intake].taken.clear();
	}
	return result;
}

// The first y at or below `p_from_y` where a straight drop at `p_x` would hit a wall or an
// item, or `p_max_y` if nothing is in the way (where a poured stream lands).
double ItemWorld::raycast_down(double p_x, double p_from_y, double p_max_y) const {
	double best = p_max_y;
	for (const Segment &s : segments) {
		if (s.dx == 0.0 || _segment_off(s)) {
			continue;
		}
		double u = (p_x - s.ax) / s.dx;
		if (u < 0.0 || u > 1.0) {
			continue;
		}
		double y = s.ay + u * s.dy;
		if (y >= p_from_y && y < best) {
			best = y;
		}
	}
	for (const Body &it : items) {
		const ItemType &t = types[it.type];
		if (std::abs(it.x - p_x) > t.radius || it.y + t.radius < p_from_y || it.y - t.radius > best) {
			continue;
		}
		for (int i = 0; i < t.count; i++) {
			int j = (i + 1) % t.count;
			double ax = it.x + it.c * t.local[i * 2] - it.s * t.local[i * 2 + 1];
			double ay = it.y + it.s * t.local[i * 2] + it.c * t.local[i * 2 + 1];
			double bx = it.x + it.c * t.local[j * 2] - it.s * t.local[j * 2 + 1];
			double by = it.y + it.s * t.local[j * 2] + it.c * t.local[j * 2 + 1];
			if ((ax - p_x) * (bx - p_x) > 0.0 || ax == bx) {
				continue;
			}
			double y = ay + (p_x - ax) / (bx - ax) * (by - ay);
			if (y >= p_from_y && y < best) {
				best = y;
			}
		}
	}
	return best;
}

double ItemWorld::type_radius(int p_type) const {
	return p_type >= 0 && p_type < (int)types.size() ? types[p_type].radius : 0.0;
}

int ItemWorld::add_item(int p_type, double p_x, double p_y, double p_c, double p_s, double p_vx, double p_vy) {
	Body b;
	_init_body(b, p_type, p_x, p_y, p_c, p_s);
	b.vx = p_vx;
	b.vy = p_vy;
	items.push_back(b);
	return (int)items.size() - 1;
}

void ItemWorld::_init_body(Body &b, int p_type, double p_x, double p_y, double p_c, double p_s) const {
	b = Body();
	b.type = p_type;
	b.x = p_x;
	b.y = p_y;
	b.c = p_c;
	b.s = p_s;
	b.step_x = b.prev_x = p_x;
	b.step_y = b.prev_y = p_y;
	b.step_c = b.prev_c = p_c;
	b.step_s = b.prev_s = p_s;
	_update_world(b);
}

void ItemWorld::_update_world(Body &b) const {
	const ItemType &t = types[b.type];
	for (int i = 0; i < t.count; i++) {
		double lx = t.local[i * 2], ly = t.local[i * 2 + 1];
		b.world[i * 2] = b.x + b.c * lx - b.s * ly;
		b.world[i * 2 + 1] = b.y + b.s * lx + b.c * ly;
		double nx = t.normals[i * 2], ny = t.normals[i * 2 + 1];
		b.world_normals[i * 2] = b.c * nx - b.s * ny;
		b.world_normals[i * 2 + 1] = b.s * nx + b.c * ny;
	}
}

// Turns by a small angle (radians), staying a unit vector without using trig.
void ItemWorld::_turn(Body &b, double p_angle) {
	double nc = b.c - b.s * p_angle;
	double ns = b.s + b.c * p_angle;
	double length = std::sqrt(nc * nc + ns * ns);
	b.c = nc / length;
	b.s = ns / length;
}

// --- Stepping ------------------------------------------------------------------------

void ItemWorld::step() {
	_run_spawners();
	_run_crushers();
	_run_sorters();
	for (Body &it : items) {
		it.prev_x = it.x;
		it.prev_y = it.y;
		it.prev_c = it.c;
		it.prev_s = it.s;
	}
	for (int i = 0; i < SUBSTEPS; i++) {
		_predict();
		_detect();
		// Items push each other first, then walls get the last word so nothing ends inside one.
		_solve(item_contacts);
		_solve(wall_contacts);
		_finish_substep();
		_settle_velocities(item_contacts);
		_settle_velocities(wall_contacts);
	}
	_update_sleep();
	_check_support();
	_collect();
	tick += 1;
}

void ItemWorld::_run_spawners() {
	for (Spawner &sp : spawners) {
		sp.timer -= 1;
		if (sp.timer > 0) {
			continue;
		}
		sp.timer = sp.interval;
		if ((int)items.size() >= MAX_ITEMS || _is_blocked_near(sp.x, sp.y + MAX_RADIUS, MAX_RADIUS * 2.0)) {
			continue;
		}
		// Every third chunk is rock (the impurity). Shape, rotation and a small sideways
		// offset follow fixed patterns so piles look natural while staying repeatable.
		const std::vector<int> &choices = sp.count % 3 == 2 ? sp.rock_types : sp.ore_types;
		int type = choices[sp.count % choices.size()];
		int rot = (sp.count % SPAWN_ROTATION_COUNT) * 2;
		double jitter = (double)((sp.count * 7) % 5 - 2);
		Body b;
		_init_body(b, type, sp.x + jitter, sp.y + types[type].radius + 0.5, SPAWN_ROTATIONS[rot], SPAWN_ROTATIONS[rot + 1]);
		items.push_back(b);
		sp.count += 1;
	}
}

void ItemWorld::_run_crushers() {
	for (Crusher &cr : crushers) {
		if (!cr.has_held) {
			for (size_t i = 0; i < items.size(); i++) {
				const Body &it = items[i];
				int rank = types[it.type].size_rank;
				if (rank >= cr.takes && it.x > cr.min_x && it.x < cr.max_x && it.y > cr.min_y && it.y < cr.max_y) {
					cr.held = it;
					cr.has_held = true;
					cr.held_x = it.x;
					cr.held_y = it.y;
					cr.passing = rank > cr.takes;
					cr.timer = cr.passing ? PASS_TICKS : cr.duration;
					items.erase(items.begin() + i);
					_wake_near(cr.held_x, cr.held_y);
					break;
				}
			}
		} else if (cr.timer > 0) {
			cr.timer -= 1;
		} else {
			const ItemType &held = types[cr.held.type];
			int out_rank = cr.passing ? held.size_rank : cr.makes;
			auto out = type_lookup.find(type_key(held.kind, out_rank, held.shape));
			double piece_size = out == type_lookup.end() ? held.radius : types[out->second].radius;
			if (!_is_blocked_near(cr.exit_x, cr.exit_y + piece_size * 2.0, piece_size * 3.0)) {
				_release_pieces(cr);
			}
		}
	}
}

// Takes in whatever reached each sorter's mouth (while it has room) and lets the first one
// inside back out once its time is up and its exit is clear.
void ItemWorld::_run_sorters() {
	for (Sorter &so : sorters) {
		for (size_t i = 0; i < items.size() && (int)so.inside.size() < SORTER_HOLDS;) {
			const Body &it = items[i];
			if (it.x > so.min_x && it.x < so.max_x && it.y > so.min_y && it.y < so.max_y) {
				Sorter::Held held;
				held.body = it;
				held.release = tick + SORTER_TICKS;
				held.match = types[it.type].kind == so.filter;
				so.inside.push_back(held);
				double x = it.x, y = it.y;
				items.erase(items.begin() + i);
				_wake_near(x, y);
			} else {
				i++;
			}
		}
		if (so.inside.empty() || tick < so.inside.front().release) {
			continue;
		}
		const Sorter::Held &next = so.inside.front();
		double r = types[next.body.type].radius;
		double x, y, vx, vy;
		if (next.match) {
			x = so.drop_x;
			y = so.drop_y + r + 0.5;
			vx = 0.0;
			vy = 40.0;
		} else {
			x = so.out_x + (so.out_vx >= 0.0 ? r + 0.5 : -r - 0.5);
			y = so.out_y - r - 0.5;
			vx = so.out_vx;
			vy = 0.0;
		}
		if (_is_blocked_near(x, y, r * 2.0)) {
			continue;
		}
		Body out;
		_init_body(out, next.body.type, x, y, next.body.c, next.body.s);
		out.vx = vx;
		out.vy = vy;
		items.push_back(out);
		so.inside.erase(so.inside.begin());
	}
}

// The crushed item comes out as several smaller pieces in a fixed little spread (or, if it
// was only passing through, as itself).
void ItemWorld::_release_pieces(Crusher &cr) {
	const Body held = cr.held;
	const ItemType &held_type = types[held.type];
	cr.has_held = false;
	if (cr.passing) {
		Body out;
		_init_body(out, held.type, cr.exit_x, cr.exit_y + held_type.radius + 0.5, held.c, held.s);
		out.vy = 40.0;
		items.push_back(out);
		return;
	}
	int shape_count = 0;
	while (type_lookup.count(type_key(held_type.kind, cr.makes, shape_count))) {
		shape_count++;
	}
	if (shape_count == 0) {
		return;
	}
	for (int k = 0; k < cr.pieces; k++) {
		int type = type_lookup[type_key(held_type.kind, cr.makes, (held_type.shape + k + 1) % shape_count)];
		double piece_size = types[type].radius;
		double side = k - (cr.pieces - 1) * 0.5;
		int rot = ((held_type.shape + k) % SPAWN_ROTATION_COUNT) * 2;
		Body piece;
		_init_body(piece, type, cr.exit_x + side * piece_size * 1.3, cr.exit_y + piece_size * (1.2 + (k % 2)), SPAWN_ROTATIONS[rot], SPAWN_ROTATIONS[rot + 1]);
		piece.vx = side * 15.0;
		piece.vy = 40.0;
		items.push_back(piece);
	}
}

// True if any item's center is within `p_reach` of (p_x, p_y).
bool ItemWorld::_is_blocked_near(double p_x, double p_y, double p_reach) const {
	for (const Body &it : items) {
		double dx = it.x - p_x;
		double dy = it.y - p_y;
		if (dx * dx + dy * dy < p_reach * p_reach) {
			return true;
		}
	}
	return false;
}

// Moves every awake item by its velocity plus gravity, remembering where it started.
void ItemWorld::_predict() {
	for (Body &it : items) {
		if (it.sleeping) {
			continue;
		}
		it.step_x = it.x;
		it.step_y = it.y;
		it.step_c = it.c;
		it.step_s = it.s;
		it.push_right = it.push_left = it.push_down = it.push_up = 0.0;
		it.vy += GRAVITY * H;
		double speed_sq = it.vx * it.vx + it.vy * it.vy;
		if (speed_sq > MAX_SPEED * MAX_SPEED) {
			double k = MAX_SPEED / std::sqrt(speed_sq);
			it.vx *= k;
			it.vy *= k;
		}
		it.w = std::min(std::max(it.w * ANGULAR_DAMPING, -MAX_SPIN), MAX_SPIN);
		it.x += it.vx * H;
		it.y += it.vy * H;
		_turn(it, it.w * H);
		_update_world(it);
	}
}

// Caps movement, rescues anything squeezed into a solid, and derives velocity from
// whatever movement survived the pushes.
void ItemWorld::_finish_substep() {
	for (Body &it : items) {
		if (it.sleeping) {
			continue;
		}
		double dx = it.x - it.step_x;
		double dy = it.y - it.step_y;
		double d2 = dx * dx + dy * dy;
		if (d2 > MAX_STEP * MAX_STEP) {
			double k = MAX_STEP / std::sqrt(d2);
			it.x = it.step_x + dx * k;
			it.y = it.step_y + dy * k;
		}
		_push_out_of_solid(it);
		it.vx = (it.x - it.step_x) / H;
		it.vy = (it.y - it.step_y) / H;
		// sin of the angle turned this substep, which is the angle itself at these sizes.
		it.w = (it.step_c * it.s - it.step_s * it.c) / H;
	}
}

// --- Contact detection ---------------------------------------------------------------

void ItemWorld::_detect() {
	item_contacts.clear();
	wall_contacts.clear();
	_build_item_grid();

	// Only awake items look for contacts; two sleepers never need resolving.
	for (int i = 0; i < (int)items.size(); i++) {
		if (items[i].sleeping) {
			continue;
		}
		const std::vector<int> *walls = _walls_at(items[i].x, items[i].y);
		if (walls) {
			for (int si : *walls) {
				_detect_wall(i, si);
			}
		}

		query += 1;
		const Body &a = items[i];
		double reach_a = types[a.type].radius + SUPPORT_GAP;
		int gx0 = _grid_x(a.x - reach_a);
		int gx1 = _grid_x(a.x + reach_a);
		int gy0 = _grid_y(a.y - reach_a);
		int gy1 = _grid_y(a.y + reach_a);
		for (int gy = gy0; gy <= gy1; gy++) {
			for (int gx = gx0; gx <= gx1; gx++) {
				int node = cell_head[(size_t)gy * grid_cols + gx];
				while (node >= 0) {
					int j = node_item[node];
					node = node_next[node];
					if (seen[j] == query) {
						continue;
					}
					seen[j] = query;
					Body &b = items[j];
					if (j == i || (!b.sleeping && j < i)) {
						continue;
					}
					double dx = b.x - items[i].x;
					double dy = b.y - items[i].y;
					double reach = reach_a + types[b.type].radius;
					if (dx * dx + dy * dy < reach * reach) {
						if (b.sleeping) {
							b.near_tick = tick;
						}
						_detect_pair(i, j);
					}
				}
			}
		}
	}
}

// Lists every item in each grid cell its bounding box covers.
void ItemWorld::_build_item_grid() {
	std::fill(cell_head.begin(), cell_head.end(), -1);
	node_item.clear();
	node_next.clear();
	seen.resize(items.size(), 0);
	for (int i = 0; i < (int)items.size(); i++) {
		const Body &it = items[i];
		double r = types[it.type].radius;
		int gx0 = _grid_x(it.x - r);
		int gx1 = _grid_x(it.x + r);
		int gy0 = _grid_y(it.y - r);
		int gy1 = _grid_y(it.y + r);
		for (int gy = gy0; gy <= gy1; gy++) {
			for (int gx = gx0; gx <= gx1; gx++) {
				size_t cell = (size_t)gy * grid_cols + gx;
				node_item.push_back(i);
				node_next.push_back(cell_head[cell]);
				cell_head[cell] = (int)node_item.size() - 1;
			}
		}
	}
}

int ItemWorld::_grid_x(double p_x) const {
	return std::min(std::max(floor_div(p_x + GRID_MARGIN, ITEM_CELL), 0), grid_cols - 1);
}

int ItemWorld::_grid_y(double p_y) const {
	return std::min(std::max(floor_div(p_y + GRID_MARGIN, ITEM_CELL), 0), grid_rows - 1);
}

const std::vector<int> *ItemWorld::_walls_at(double p_x, double p_y) const {
	int cx = floor_div(p_x, SEG_CELL) + SEG_MARGIN;
	int cy = floor_div(p_y, SEG_CELL) + SEG_MARGIN;
	if (cx < 0 || cy < 0 || cx >= seg_cols || cy >= seg_rows) {
		return nullptr;
	}
	const std::vector<int> &cell = seg_grid[(size_t)cy * seg_cols + cx];
	return cell.empty() ? nullptr : &cell;
}

// Contacts where a corner of one item pokes into the other.
void ItemWorld::_detect_pair(int ia, int ib) {
	Body &a = items[ia];
	Body &b = items[ib];
	const ItemType &ta = types[a.type];
	const ItemType &tb = types[b.type];
	size_t first = item_contacts.list.size();
	double depth = 0.0;
	// A corner outside the other item's bounding circle can't be inside it; skipping those
	// saves most of the work.
	double rb = tb.radius * tb.radius;
	double ra = ta.radius * ta.radius;
	for (int k = 0; k < ta.count; k++) {
		double px = a.world[k * 2], py = a.world[k * 2 + 1];
		if ((px - b.x) * (px - b.x) + (py - b.y) * (py - b.y) >= rb) {
			continue;
		}
		int face = _deepest_face(px, py, b, 0.0, depth);
		if (face >= 0) {
			double nx = b.world_normals[face * 2], ny = b.world_normals[face * 2 + 1];
			_add_contact(item_contacts, ia, ib, px, py, px + nx * depth, py + ny * depth, nx, ny);
		}
	}
	for (int k = 0; k < tb.count; k++) {
		double px = b.world[k * 2], py = b.world[k * 2 + 1];
		if ((px - a.x) * (px - a.x) + (py - a.y) * (py - a.y) >= ra) {
			continue;
		}
		int face = _deepest_face(px, py, a, 0.0, depth);
		if (face >= 0) {
			double nx = a.world_normals[face * 2], ny = a.world_normals[face * 2 + 1];
			_add_contact(item_contacts, ia, ib, px + nx * depth, py + ny * depth, px, py, -nx, -ny);
		}
	}

	if (b.sleeping) {
		// Wake a sleeper on a real impact, or when it sits on something being carried.
		bool carried = _is_carried(a);
		for (size_t k = first; k < item_contacts.list.size(); k++) {
			double nx = item_contacts.list[k].nx, ny = item_contacts.list[k].ny;
			if (-(a.vx * nx + a.vy * ny) > WAKE_SPEED || (carried && ny > SUPPORT_SLOPE)) {
				_wake(b);
				break;
			}
		}
	}
}

// Contacts between an item and a static line: item corners past the line, and line ends
// poking into the item. The line pushes toward whichever side the item's center was on at
// the start of the substep, so a small fast item that got all the way across a thin wall
// still goes back where it came from.
void ItemWorld::_detect_wall(int ia, int si) {
	const Segment &sg = segments[si];
	Body &a = items[ia];
	const ItemType &ta = types[a.type];
	if (sg.passes == ta.kind || _segment_off(sg)) {
		return;
	}
	double along = (a.x - sg.ax) * sg.tx + (a.y - sg.ay) * sg.ty;
	if (along < -ta.radius || along * along > (sg.length + ta.radius) * (sg.length + ta.radius)) {
		return;
	}
	double side = (a.x - sg.ax) * sg.nx + (a.y - sg.ay) * sg.ny;
	double was = (a.step_x - sg.ax) * sg.nx + (a.step_y - sg.ay) * sg.ny;
	if (std::abs(side) >= ta.radius && (side >= 0.0) == (was >= 0.0)) {
		return;
	}
	double nx = was >= 0.0 ? sg.nx : -sg.nx;
	double ny = was >= 0.0 ? sg.ny : -sg.ny;
	for (int k = 0; k < ta.count; k++) {
		double px = a.world[k * 2], py = a.world[k * 2 + 1];
		double u = ((px - sg.ax) * sg.dx + (py - sg.ay) * sg.dy) / sg.len_sq;
		if (u < 0.0 || u > 1.0) {
			continue;
		}
		double d = (px - sg.ax) * nx + (py - sg.ay) * ny;
		if (d < 0.0) {
			_add_contact(wall_contacts, ia, -1 - si, px, py, px - nx * d, py - ny * d, nx, ny);
		}
	}
	double depth = 0.0;
	for (int e = 0; e < 2; e++) {
		double ex = e == 0 ? sg.ax : sg.bx;
		double ey = e == 0 ? sg.ay : sg.by;
		if ((ex - a.x) * (ex - a.x) + (ey - a.y) * (ey - a.y) >= ta.radius * ta.radius) {
			continue;
		}
		int face = _deepest_face(ex, ey, a, 0.0, depth);
		if (face >= 0) {
			double fx = a.world_normals[face * 2], fy = a.world_normals[face * 2 + 1];
			_add_contact(wall_contacts, ia, -1 - si, ex + fx * depth, ey + fy * depth, ex, ey, -fx, -fy);
		}
	}
}

// Index of the face of `b` that point (px, py) is least deep behind, or -1 if the point is
// more than `margin` outside. Sets `depth` to how deep it is (negative if outside).
int ItemWorld::_deepest_face(double px, double py, const Body &b, double margin, double &depth) const {
	const ItemType &t = types[b.type];
	double best = -std::numeric_limits<double>::infinity();
	int best_face = -1;
	for (int f = 0; f < t.count; f++) {
		double d = (px - b.world[f * 2]) * b.world_normals[f * 2] + (py - b.world[f * 2 + 1]) * b.world_normals[f * 2 + 1];
		if (d > margin) {
			return -1;
		}
		if (d > best) {
			best = d;
			best_face = f;
		}
	}
	depth = -best;
	return best_face;
}

void ItemWorld::_add_contact(Contacts &list, int ia, int ib, double pax, double pay, double pbx, double pby, double nx, double ny) {
	const Body &a = items[ia];
	Contact ct;
	ct.a = ia;
	ct.b = ib;
	double dx = pax - a.x;
	double dy = pay - a.y;
	ct.lax = a.c * dx + a.s * dy;
	ct.lay = -a.s * dx + a.c * dy;
	if (ib < 0) {
		ct.lbx = pbx;
		ct.lby = pby;
	} else {
		const Body &b = items[ib];
		dx = pbx - b.x;
		dy = pby - b.y;
		ct.lbx = b.c * dx + b.s * dy;
		ct.lby = -b.s * dx + b.c * dy;
	}
	ct.nx = nx;
	ct.ny = ny;
	list.list.push_back(ct);
}

// --- Contact solving -----------------------------------------------------------------

void ItemWorld::_solve(Contacts &list) {
	for (int k = 0; k < (int)list.list.size(); k++) {
		const Contact &ct = list.list[k];
		Body &a = items[ct.a];
		const ItemType &ta = types[a.type];
		Body *b = nullptr;
		const Segment *seg = nullptr;
		double pbx = ct.lbx, pby = ct.lby;
		if (ct.b < 0) {
			seg = &segments[-1 - ct.b];
		} else {
			b = &items[ct.b];
			pbx = b->x + b->c * ct.lbx - b->s * ct.lby;
			pby = b->y + b->s * ct.lbx + b->c * ct.lby;
		}
		double pax = a.x + a.c * ct.lax - a.s * ct.lay;
		double pay = a.y + a.s * ct.lax + a.c * ct.lay;
		double depth = (pbx - pax) * ct.nx + (pby - pay) * ct.ny;
		if (depth <= 0.0) {
			continue;
		}
		list.touching.push_back(k);

		// Push apart at the contact point. Off-center pushes also turn the item, which is
		// what tips a chunk off its corner.
		bool b_moves = b != nullptr && !b->sleeping;
		double rax = pax - a.x, ray = pay - a.y;
		double cra = rax * ct.ny - ray * ct.nx;
		double weight = ta.inv_mass + ta.inv_inertia * cra * cra;
		double rbx = 0.0, rby = 0.0;
		if (b_moves) {
			const ItemType &tb = types[b->type];
			rbx = pbx - b->x;
			rby = pby - b->y;
			double crb = rbx * ct.ny - rby * ct.nx;
			weight += tb.inv_mass + tb.inv_inertia * crb * crb;
		}
		double lam = depth / weight;
		_move(a, ct.nx * lam, ct.ny * lam, rax, ray);
		if (b_moves) {
			_move(*b, -ct.nx * lam, -ct.ny * lam, rbx, rby);
		}

		// Whatever rests on a carried item is carried too (ny < 0: A is pushed up, so on top).
		if (seg) {
			if (seg->speed != 0.0) {
				a.carried_tick = tick;
			}
		} else if (ct.ny < -SUPPORT_SLOPE && _is_carried(*b)) {
			a.carried_tick = tick;
		} else if (ct.ny > SUPPORT_SLOPE && b_moves && _is_carried(a)) {
			b->carried_tick = tick;
		}

		_apply_friction(a, b_moves ? b : nullptr, seg, ct, lam);
	}
}

// Moves an item by impulse (px, py) applied at offset (rx, ry) from its center.
void ItemWorld::_move(Body &it, double px, double py, double rx, double ry) {
	const ItemType &t = types[it.type];
	double mx = px * t.inv_mass;
	double my = py * t.inv_mass;
	it.x += mx;
	it.y += my;
	_add_push(it, mx, my);
	_turn(it, t.inv_inertia * (rx * py - ry * px));
}

// Static friction: cancels sliding at the contact this substep, up to what the contact's
// push allows (Coulomb). On a belt the "not sliding" target is the belt's own movement.
void ItemWorld::_apply_friction(Body &a, Body *b, const Segment *seg, const Contact &ct, double lam) {
	const ItemType &ta = types[a.type];
	double pax = a.x + a.c * ct.lax - a.s * ct.lay;
	double pay = a.y + a.s * ct.lax + a.c * ct.lay;
	double mx = pax - (a.step_x + a.step_c * ct.lax - a.step_s * ct.lay);
	double my = pay - (a.step_y + a.step_s * ct.lax + a.step_c * ct.lay);
	double mu = ITEM_FRICTION;
	double rbx = 0.0, rby = 0.0;
	if (seg) {
		mu = seg->friction;
		mx -= seg->tx * seg->speed * H;
		my -= seg->ty * seg->speed * H;
	} else if (b) {
		double pbx = b->x + b->c * ct.lbx - b->s * ct.lby;
		double pby = b->y + b->s * ct.lbx + b->c * ct.lby;
		rbx = pbx - b->x;
		rby = pby - b->y;
		mx -= pbx - (b->step_x + b->step_c * ct.lbx - b->step_s * ct.lby);
		my -= pby - (b->step_y + b->step_s * ct.lbx + b->step_c * ct.lby);
	}

	double mn = mx * ct.nx + my * ct.ny;
	double tx = mx - ct.nx * mn;
	double ty = my - ct.ny * mn;
	double slide = std::sqrt(tx * tx + ty * ty);
	if (slide < 1e-9) {
		return;
	}
	tx /= slide;
	ty /= slide;

	double rax = pax - a.x, ray = pay - a.y;
	double cra = rax * ty - ray * tx;
	double weight = ta.inv_mass + ta.inv_inertia * cra * cra;
	if (b) {
		const ItemType &tb = types[b->type];
		double crb = rbx * ty - rby * tx;
		weight += tb.inv_mass + tb.inv_inertia * crb * crb;
	}
	double lam_t = std::min(slide / weight, mu * lam);

	if (seg && seg->belt) {
		// A belt mostly slips under an item that something is holding back (a wall, the item
		// ahead in a queue), keeping only BELT_PRESS of its grip. Full grip would squash a
		// long queue together; none would leave a backed-up queue limp.
		double held = (-tx > 0.0 ? a.push_left : a.push_right) * std::abs(tx);
		held += (-ty > 0.0 ? a.push_up : a.push_down) * std::abs(ty);
		lam_t = std::max(lam_t * BELT_PRESS, lam_t - held / ta.inv_mass);
	}

	_move(a, -tx * lam_t, -ty * lam_t, rax, ray);
	if (b) {
		_move(*b, tx * lam_t, ty * lam_t, rbx, rby);
	}
}

// Removes motion along the normal at every contact that pushed this substep. Pushing
// overlapping items apart turns into speed in this kind of solver; without this pass a
// chunk landing on a corner would spring off and spin far more than a real rock does.
void ItemWorld::_settle_velocities(const Contacts &list) {
	for (int k : list.touching) {
		const Contact &ct = list.list[k];
		Body &a = items[ct.a];
		const ItemType &ta = types[a.type];
		double rax = a.c * ct.lax - a.s * ct.lay;
		double ray = a.s * ct.lax + a.c * ct.lay;
		double vn = (a.vx - a.w * ray) * ct.nx + (a.vy + a.w * rax) * ct.ny;
		double cra = rax * ct.ny - ray * ct.nx;
		double weight = ta.inv_mass + ta.inv_inertia * cra * cra;
		Body *b = nullptr;
		double crb = 0.0;
		if (ct.b >= 0 && !items[ct.b].sleeping) {
			b = &items[ct.b];
			const ItemType &tb = types[b->type];
			double rbx = b->c * ct.lbx - b->s * ct.lby;
			double rby = b->s * ct.lbx + b->c * ct.lby;
			vn -= (b->vx - b->w * rby) * ct.nx + (b->vy + b->w * rbx) * ct.ny;
			crb = rbx * ct.ny - rby * ct.nx;
			weight += tb.inv_mass + tb.inv_inertia * crb * crb;
		}
		double j = -vn / weight;
		a.vx += ct.nx * j * ta.inv_mass;
		a.vy += ct.ny * j * ta.inv_mass;
		a.w += cra * j * ta.inv_inertia;
		if (b) {
			const ItemType &tb = types[b->type];
			b->vx -= ct.nx * j * tb.inv_mass;
			b->vy -= ct.ny * j * tb.inv_mass;
			b->w -= crb * j * tb.inv_inertia;
		}
	}
}

void ItemWorld::_add_push(Body &it, double dx, double dy) {
	if (dx > 0.0) {
		it.push_right += dx;
	} else {
		it.push_left -= dx;
	}
	if (dy > 0.0) {
		it.push_down += dy;
	} else {
		it.push_up -= dy;
	}
}

// --- Solids --------------------------------------------------------------------------

// If a heavy pile squeezed an item's center into a solid tile, move it out through the
// nearest open face. Faces shared with another solid never count as a way out.
void ItemWorld::_push_out_of_solid(Body &it) {
	int cx = floor_div(it.x, SEG_CELL);
	int cy = floor_div(it.y, SEG_CELL);
	int kind = _solid_at(cx, cy);
	if (kind == SOLID_NONE) {
		return;
	}
	double lx = it.x - cx * SEG_CELL;
	double ly = it.y - cy * SEG_CELL;

	if (kind == SOLID_TOP_HALF) {
		// Only the top half is solid; out through the top if that's open, else the bottom.
		double half = SEG_CELL * 0.5;
		if (ly >= half) {
			return;
		}
		if (_is_open(cx, cy - 1, 0, 1) && ly <= half - ly) {
			_push_out_along(it, ly, 0.0, -1.0);
		} else {
			_push_out_along(it, half - ly, 0.0, 1.0);
		}
		return;
	}

	if (kind == SOLID_RAMP_DOWN_RIGHT || kind == SOLID_RAMP_DOWN_LEFT) {
		bool down_right = kind == SOLID_RAMP_DOWN_RIGHT;
		double depth = down_right ? (ly - lx) : (lx + ly - SEG_CELL);
		if (depth > 0.0) {
			_push_out_along(it, depth * INV_SQRT2, down_right ? INV_SQRT2 : -INV_SQRT2, -INV_SQRT2);
		}
		return;
	}

	// Prefer the faces on the side the item came from this tick, so an item squeezed into the
	// corner where two solids touch diagonally goes back where it was, not through.
	int from_x = floor_div(it.prev_x, SEG_CELL) - cx;
	int from_y = floor_div(it.prev_y, SEG_CELL) - cy;
	from_x = (from_x > 0) - (from_x < 0);
	from_y = (from_y > 0) - (from_y < 0);
	double best = std::numeric_limits<double>::infinity();
	double nx = 0.0, ny = 0.0;
	for (int pass = 0; pass < 2; pass++) {
		bool any_side = pass == 1;
		if ((any_side || from_y < 0) && _is_open(cx, cy - 1, 0, 1) && ly < best) {
			best = ly;
			nx = 0.0;
			ny = -1.0;
		}
		if ((any_side || from_x < 0) && _is_open(cx - 1, cy, 1, 0) && lx < best) {
			best = lx;
			nx = -1.0;
			ny = 0.0;
		}
		if ((any_side || from_x > 0) && _is_open(cx + 1, cy, -1, 0) && SEG_CELL - lx < best) {
			best = SEG_CELL - lx;
			nx = 1.0;
			ny = 0.0;
		}
		if ((any_side || from_y > 0) && _is_open(cx, cy + 1, 0, -1) && SEG_CELL - ly < best) {
			best = SEG_CELL - ly;
			nx = 0.0;
			ny = 1.0;
		}
		if (best != std::numeric_limits<double>::infinity()) {
			_push_out_along(it, best, nx, ny);
			return;
		}
	}
}

void ItemWorld::_push_out_along(Body &it, double depth, double nx, double ny) {
	double r = types[it.type].radius;
	it.x += nx * (depth + r);
	it.y += ny * (depth + r);
}

int ItemWorld::_solid_at(int cx, int cy) const {
	if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) {
		return SOLID_NONE;
	}
	return solid[(size_t)cy * cols + cx];
}

// True if the cell can be exited into from its side (side_x, side_y), i.e. that side isn't
// a full solid face. (0, 1) is the cell's bottom, (1, 0) its right, and so on.
bool ItemWorld::_is_open(int cx, int cy, int side_x, int side_y) const {
	switch (_solid_at(cx, cy)) {
		case SOLID_NONE:
			return true;
		case SOLID_RAMP_DOWN_RIGHT:
			return !(side_x == 0 && side_y == 1) && !(side_x == -1 && side_y == 0);
		case SOLID_RAMP_DOWN_LEFT:
			return !(side_x == 0 && side_y == 1) && !(side_x == 1 && side_y == 0);
		case SOLID_TOP_HALF:
			// Only its bottom is open: the lower half of the tile is empty.
			return side_x == 0 && side_y == 1;
	}
	return false;
}

// --- Sleeping ------------------------------------------------------------------------

void ItemWorld::_wake(Body &it) {
	it.sleeping = false;
	it.still_ticks = 0;
	it.step_x = it.x;
	it.step_y = it.y;
	it.step_c = it.c;
	it.step_s = it.s;
}

// An item that stays within SLEEP_MOVE pixels and SLEEP_TURN radians of one pose for
// SLEEP_TICKS ticks goes to sleep. Measured over the whole stretch, not per tick, so a chunk
// rocking slightly on its resting spot still settles while a slow creep doesn't.
void ItemWorld::_update_sleep() {
	for (Body &it : items) {
		if (it.sleeping) {
			continue;
		}
		if (_is_carried(it)) {
			it.still_ticks = 0;
			continue;
		}
		double mx = it.x - it.still_x;
		double my = it.y - it.still_y;
		double turned = std::abs(it.still_c * it.s - it.still_s * it.c);
		if (it.still_ticks > 0 && mx * mx + my * my < SLEEP_MOVE * SLEEP_MOVE && turned < SLEEP_TURN) {
			it.still_ticks += 1;
			if (it.still_ticks >= SLEEP_TICKS) {
				it.sleeping = true;
				it.vx = it.vy = it.w = 0.0;
				_update_world(it);
			}
		} else {
			// Start a new stretch from here.
			it.still_ticks = 1;
			it.still_x = it.x;
			it.still_y = it.y;
			it.still_c = it.c;
			it.still_s = it.s;
		}
	}
}

// Wakes sleepers whose support has moved away. A sleeper's support can only go if something
// next to it moves (removed items are handled in _collect), so only sleepers a moving item
// came near this tick are checked.
void ItemWorld::_check_support() {
	for (int i = 0; i < (int)items.size(); i++) {
		Body &it = items[i];
		if (it.sleeping && it.near_tick == tick && !_is_supported(i)) {
			_wake(it);
		}
	}
}

// True if a wall or another item touches this one in a way that pushes it upward.
bool ItemWorld::_is_supported(int index) {
	const Body &it = items[index];
	const ItemType &t = types[it.type];
	double depth = 0.0;
	const std::vector<int> *walls = _walls_at(it.x, it.y);
	if (walls) {
		for (int si : *walls) {
			const Segment &sg = segments[si];
			if (sg.passes == t.kind || _segment_off(sg)) {
				continue;
			}
			double side = (it.x - sg.ax) * sg.nx + (it.y - sg.ay) * sg.ny;
			if (std::abs(side) >= t.radius + SUPPORT_GAP) {
				continue;
			}
			double nx = side >= 0.0 ? sg.nx : -sg.nx;
			double ny = side >= 0.0 ? sg.ny : -sg.ny;
			if (ny < -SUPPORT_SLOPE) {
				for (int k = 0; k < t.count; k++) {
					double px = it.world[k * 2], py = it.world[k * 2 + 1];
					double u = ((px - sg.ax) * sg.dx + (py - sg.ay) * sg.dy) / sg.len_sq;
					if (u >= 0.0 && u <= 1.0 && (px - sg.ax) * nx + (py - sg.ay) * ny <= SUPPORT_GAP) {
						return true;
					}
				}
			}
			for (int e = 0; e < 2; e++) {
				int face = _deepest_face(e == 0 ? sg.ax : sg.bx, e == 0 ? sg.ay : sg.by, it, SUPPORT_GAP, depth);
				if (face >= 0 && it.world_normals[face * 2 + 1] > SUPPORT_SLOPE) {
					return true;
				}
			}
		}
	}

	query += 1;
	double reach_it = t.radius + SUPPORT_GAP;
	int gx0 = _grid_x(it.x - reach_it);
	int gx1 = _grid_x(it.x + reach_it);
	int gy0 = _grid_y(it.y - reach_it);
	int gy1 = _grid_y(it.y + reach_it);
	for (int gy = gy0; gy <= gy1; gy++) {
		for (int gx = gx0; gx <= gx1; gx++) {
			int node = cell_head[(size_t)gy * grid_cols + gx];
			while (node >= 0) {
				int j = node_item[node];
				node = node_next[node];
				if (j == index || seen[j] == query) {
					continue;
				}
				seen[j] = query;
				const Body &o = items[j];
				const ItemType &to = types[o.type];
				double dx = o.x - it.x;
				double dy = o.y - it.y;
				double reach = reach_it + to.radius;
				if (dx * dx + dy * dy >= reach * reach) {
					continue;
				}
				for (int k = 0; k < t.count; k++) {
					int face = _deepest_face(it.world[k * 2], it.world[k * 2 + 1], o, SUPPORT_GAP, depth);
					if (face >= 0 && o.world_normals[face * 2 + 1] < -SUPPORT_SLOPE) {
						return true;
					}
				}
				for (int k = 0; k < to.count; k++) {
					int face = _deepest_face(o.world[k * 2], o.world[k * 2 + 1], it, SUPPORT_GAP, depth);
					if (face >= 0 && it.world_normals[face * 2 + 1] > SUPPORT_SLOPE) {
						return true;
					}
				}
			}
		}
	}
	return false;
}

// --- Bookkeeping ---------------------------------------------------------------------

// Removes items that fell out of the world or landed in a bin, keeping the rest in order.
// Sleepers that were resting on a removed item are woken so they don't hang in mid-air.
void ItemWorld::_collect() {
	std::vector<Body> kept;
	kept.reserve(items.size());
	std::vector<std::pair<double, double>> removed;
	for (const Body &it : items) {
		if (it.y > kill_max_y || it.x < kill_min_x || it.x > kill_max_x) {
			lost += 1;
			removed.emplace_back(it.x, it.y);
			continue;
		}
		bool caught = false;
		for (Bin &b : bins) {
			if (it.x > b.min_x && it.x < b.max_x && it.y > b.min_y && it.y < b.max_y) {
				const ItemType &t = types[it.type];
				b.caught += 1;
				b.by_kind_size[kind_size_key(t.kind, t.size_rank)] += 1;
				delivered[t.kind] += 1;
				caught = true;
				break;
			}
		}
		if (!caught) {
			for (Intake &in : intakes) {
				if (in.open && it.x > in.min_x && it.x < in.max_x && it.y > in.min_y && it.y < in.max_y) {
					in.taken.push_back(it.type);
					caught = true;
					break;
				}
			}
		}
		if (caught) {
			removed.emplace_back(it.x, it.y);
		} else {
			kept.push_back(it);
		}
	}
	items.swap(kept);
	for (const auto &r : removed) {
		_wake_near(r.first, r.second);
	}
}

// Wakes sleepers that could have been resting on something at (x, y) that just left.
void ItemWorld::_wake_near(double x, double y) {
	double reach = MAX_RADIUS * 2.0 + SUPPORT_GAP;
	for (Body &it : items) {
		if (it.sleeping) {
			double dx = it.x - x;
			double dy = it.y - y;
			if (dx * dx + dy * dy < reach * reach) {
				_wake(it);
			}
		}
	}
}

// --- Reading -------------------------------------------------------------------------

int ItemWorld::sleeping_count() const {
	int count = 0;
	for (const Body &it : items) {
		count += it.sleeping ? 1 : 0;
	}
	return count;
}

Dictionary ItemWorld::get_item(int p_index) const {
	Dictionary d;
	if (p_index < 0 || p_index >= (int)items.size()) {
		return d;
	}
	const Body &it = items[p_index];
	const ItemType &t = types[it.type];
	d["type"] = it.type;
	d["kind"] = t.kind;
	d["size"] = t.size_rank;
	d["shape"] = t.shape;
	d["x"] = it.x;
	d["y"] = it.y;
	d["c"] = it.c;
	d["s"] = it.s;
	d["vx"] = it.vx;
	d["vy"] = it.vy;
	d["w"] = it.w;
	d["radius"] = t.radius;
	d["sleeping"] = it.sleeping;
	d["carried"] = it.carried_tick >= tick - 2;
	// Outline in world space, freshly computed from the current pose.
	PackedFloat64Array world;
	for (int i = 0; i < t.count; i++) {
		double lx = t.local[i * 2], ly = t.local[i * 2 + 1];
		world.push_back(it.x + it.c * lx - it.s * ly);
		world.push_back(it.y + it.s * lx + it.c * ly);
	}
	d["world"] = world;
	return d;
}

// Every item's state, for checking two runs are identical.
PackedFloat64Array ItemWorld::snapshot() const {
	PackedFloat64Array data;
	data.resize(items.size() * 7);
	double *w = data.ptrw();
	for (size_t i = 0; i < items.size(); i++) {
		const Body &it = items[i];
		w[i * 7 + 0] = it.x;
		w[i * 7 + 1] = it.y;
		w[i * 7 + 2] = it.c;
		w[i * 7 + 3] = it.s;
		w[i * 7 + 4] = it.vx;
		w[i * 7 + 5] = it.vy;
		w[i * 7 + 6] = it.w;
	}
	return data;
}

Dictionary ItemWorld::delivered_by_kind() const {
	Dictionary d;
	for (const auto &entry : delivered) {
		d[entry.first] = entry.second;
	}
	return d;
}

// Keys are kind * 16 + size rank.
Dictionary ItemWorld::bin_counts(int p_bin) const {
	Dictionary d;
	if (p_bin >= 0 && p_bin < (int)bins.size()) {
		for (const auto &entry : bins[p_bin].by_kind_size) {
			d[entry.first] = entry.second;
		}
	}
	return d;
}

Dictionary ItemWorld::crusher_state(int p_crusher) const {
	Dictionary d;
	if (p_crusher < 0 || p_crusher >= (int)crushers.size()) {
		return d;
	}
	const Crusher &cr = crushers[p_crusher];
	d["held"] = cr.has_held;
	if (cr.has_held) {
		d["type"] = cr.held.type;
		d["c"] = cr.held.c;
		d["s"] = cr.held.s;
		d["held_x"] = cr.held_x;
		d["held_y"] = cr.held_y;
		d["press_y"] = cr.press_y;
		d["exit_x"] = cr.exit_x;
		d["passing"] = cr.passing;
		d["progress"] = 1.0 - (double)cr.timer / (cr.passing ? PASS_TICKS : cr.duration);
	}
	return d;
}

int ItemWorld::spawned_count(int p_spawner) const {
	return p_spawner >= 0 && p_spawner < (int)spawners.size() ? spawners[p_spawner].count : 0;
}

// Per item type, the 2D transforms of every item of that type, in the layout MultiMesh
// expects (8 floats each), so drawing needs no per-item script work.
Array ItemWorld::draw_buffers(int p_type_count) const {
	std::vector<int> counts(p_type_count, 0);
	for (const Body &it : items) {
		if (it.type < p_type_count) {
			counts[it.type] += 1;
		}
	}
	std::vector<PackedFloat32Array> buffers(p_type_count);
	std::vector<float *> cursors(p_type_count, nullptr);
	for (int t = 0; t < p_type_count; t++) {
		buffers[t].resize(counts[t] * 8);
		cursors[t] = counts[t] > 0 ? buffers[t].ptrw() : nullptr;
	}
	for (const Body &it : items) {
		if (it.type >= p_type_count) {
			continue;
		}
		float *w = cursors[it.type];
		w[0] = (float)it.c;
		w[1] = (float)-it.s;
		w[2] = 0.0f;
		w[3] = (float)it.x;
		w[4] = (float)it.s;
		w[5] = (float)it.c;
		w[6] = 0.0f;
		w[7] = (float)it.y;
		cursors[it.type] = w + 8;
	}
	Array result;
	for (int t = 0; t < p_type_count; t++) {
		result.push_back(buffers[t]);
	}
	return result;
}

// How deep the deepest corner of any item sits inside another item (for tests).
double ItemWorld::max_overlap() {
	for (Body &it : items) {
		_update_world(it);
	}
	double worst = 0.0;
	double depth = 0.0;
	for (size_t i = 0; i < items.size(); i++) {
		const Body &a = items[i];
		const ItemType &ta = types[a.type];
		for (size_t j = 0; j < items.size(); j++) {
			if (i == j) {
				continue;
			}
			const Body &b = items[j];
			double reach = ta.radius + types[b.type].radius;
			if ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) >= reach * reach) {
				continue;
			}
			for (int k = 0; k < ta.count; k++) {
				if (_deepest_face(a.world[k * 2], a.world[k * 2 + 1], b, 0.0, depth) >= 0) {
					worst = std::max(worst, depth);
				}
			}
		}
	}
	return worst;
}

// Takes another world's items and clock (for tests that rebuild a machine mid-run).
void ItemWorld::copy_items_from(const Ref<ItemWorld> &p_other) {
	if (p_other.is_valid()) {
		items = p_other->items;
		tick = p_other->tick;
	}
}

void ItemWorld::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_bounds", "cols", "rows"), &ItemWorld::set_bounds);
	ClassDB::bind_method(D_METHOD("set_solid", "cx", "cy", "kind"), &ItemWorld::set_solid);
	ClassDB::bind_method(D_METHOD("add_segment", "ax", "ay", "bx", "by", "speed", "friction", "passes", "belt", "group"), &ItemWorld::add_segment);
	ClassDB::bind_method(D_METHOD("set_group_enabled", "group", "enabled"), &ItemWorld::set_group_enabled);
	ClassDB::bind_method(D_METHOD("push_items", "min_x", "min_y", "max_x", "max_y", "vx", "vy"), &ItemWorld::push_items);
	ClassDB::bind_method(D_METHOD("finish_build"), &ItemWorld::finish_build);
	ClassDB::bind_method(D_METHOD("register_type", "kind", "size_rank", "shape", "outline"), &ItemWorld::register_type);
	ClassDB::bind_method(D_METHOD("add_spawner", "x", "y", "interval", "ore_types", "rock_types"), &ItemWorld::add_spawner);
	ClassDB::bind_method(D_METHOD("add_bin", "min_x", "min_y", "max_x", "max_y"), &ItemWorld::add_bin);
	ClassDB::bind_method(D_METHOD("add_crusher", "takes", "makes", "pieces", "duration", "min_x", "min_y", "max_x", "max_y", "press_y", "exit_x", "exit_y"), &ItemWorld::add_crusher);
	ClassDB::bind_method(D_METHOD("add_item", "type", "x", "y", "c", "s", "vx", "vy"), &ItemWorld::add_item);
	ClassDB::bind_method(D_METHOD("add_intake", "min_x", "min_y", "max_x", "max_y"), &ItemWorld::add_intake);
	ClassDB::bind_method(D_METHOD("add_sorter", "min_x", "min_y", "max_x", "max_y", "filter", "out_x", "out_y", "out_vx", "drop_x", "drop_y"), &ItemWorld::add_sorter);
	ClassDB::bind_method(D_METHOD("set_intake_open", "intake", "open"), &ItemWorld::set_intake_open);
	ClassDB::bind_method(D_METHOD("take_intake", "intake"), &ItemWorld::take_intake);
	ClassDB::bind_method(D_METHOD("raycast_down", "x", "from_y", "max_y"), &ItemWorld::raycast_down);
	ClassDB::bind_method(D_METHOD("type_radius", "type"), &ItemWorld::type_radius);
	ClassDB::bind_method(D_METHOD("step"), &ItemWorld::step);
	ClassDB::bind_method(D_METHOD("get_tick"), &ItemWorld::get_tick);
	ClassDB::bind_method(D_METHOD("set_tick", "tick"), &ItemWorld::set_tick);
	ClassDB::bind_method(D_METHOD("get_lost"), &ItemWorld::get_lost);
	ClassDB::bind_method(D_METHOD("item_count"), &ItemWorld::item_count);
	ClassDB::bind_method(D_METHOD("sleeping_count"), &ItemWorld::sleeping_count);
	ClassDB::bind_method(D_METHOD("get_item", "index"), &ItemWorld::get_item);
	ClassDB::bind_method(D_METHOD("snapshot"), &ItemWorld::snapshot);
	ClassDB::bind_method(D_METHOD("delivered_by_kind"), &ItemWorld::delivered_by_kind);
	ClassDB::bind_method(D_METHOD("bin_counts", "bin"), &ItemWorld::bin_counts);
	ClassDB::bind_method(D_METHOD("crusher_count"), &ItemWorld::crusher_count);
	ClassDB::bind_method(D_METHOD("crusher_state", "crusher"), &ItemWorld::crusher_state);
	ClassDB::bind_method(D_METHOD("spawned_count", "spawner"), &ItemWorld::spawned_count);
	ClassDB::bind_method(D_METHOD("clear_spawners"), &ItemWorld::clear_spawners);
	ClassDB::bind_method(D_METHOD("draw_buffers", "type_count"), &ItemWorld::draw_buffers);
	ClassDB::bind_method(D_METHOD("max_overlap"), &ItemWorld::max_overlap);
	ClassDB::bind_method(D_METHOD("copy_items_from", "other"), &ItemWorld::copy_items_from);
}
