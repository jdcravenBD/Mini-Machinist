#pragma once

// Deterministic rigid-body physics for Mini Machinist's items: convex polygons that slide,
// tip, stack and settle, plus static segments, belts, spawners, crushers and bins.
//
// Position-based (XPBD style): each substep predicts where items go, finds contact points
// where outlines overlap, pushes them apart at those points (which also turns them), then
// derives velocity from how far they actually moved.
//
// The same machine must always produce the same result, so:
// - advance only through step() (fixed timestep, fixed substeps)
// - iterate in a fixed order (item index, segment index), never hash order
// - only + - * / and sqrt on doubles; build with FP contraction off (no fused multiply-add)

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstdint>
#include <map>
#include <vector>

namespace godot {

class ItemWorld : public RefCounted {
	GDCLASS(ItemWorld, RefCounted)

public:
	static constexpr int MAX_CORNERS = 8;

	// One item outline at one material and size; items point at a type.
	struct ItemType {
		int kind = 0;
		int size_rank = 0;
		int shape = 0;
		int count = 0;
		double local[MAX_CORNERS * 2] = {};
		double normals[MAX_CORNERS * 2] = {};
		double radius = 0.0;
		double inv_mass = 0.0;
		double inv_inertia = 0.0;
	};

	struct Body {
		int type = 0;
		double x = 0.0, y = 0.0, c = 1.0, s = 0.0;
		double vx = 0.0, vy = 0.0, w = 0.0;
		double world[MAX_CORNERS * 2] = {};
		double world_normals[MAX_CORNERS * 2] = {};
		bool sleeping = false;
		int still_ticks = 0;
		double still_x = 0.0, still_y = 0.0, still_c = 1.0, still_s = 0.0;
		int64_t carried_tick = -10;
		int64_t near_tick = -10;
		double step_x = 0.0, step_y = 0.0, step_c = 1.0, step_s = 0.0;
		double prev_x = 0.0, prev_y = 0.0, prev_c = 1.0, prev_s = 0.0;
		double push_right = 0.0, push_left = 0.0, push_down = 0.0, push_up = 0.0;
	};

	struct Segment {
		double ax, ay, bx, by, dx, dy, len_sq, length, tx, ty, nx, ny;
		double speed;
		double friction;
		int passes;
		bool belt;
	};

	struct Spawner {
		double x, y;
		int interval;
		int timer = 1;
		int count = 0;
		std::vector<int> ore_types;
		std::vector<int> rock_types;
	};

	struct Bin {
		double min_x, min_y, max_x, max_y;
		int caught = 0;
		std::map<int, int> by_kind_size;
	};

	struct Crusher {
		int takes, makes, pieces, duration;
		double min_x, min_y, max_x, max_y;
		double press_y, exit_x, exit_y;
		bool has_held = false;
		Body held;
		double held_x = 0.0, held_y = 0.0;
		bool passing = false;
		int timer = 0;
	};

	struct Contact {
		int a, b;
		double lax, lay, lbx, lby, nx, ny;
	};

	struct Contacts {
		std::vector<Contact> list;
		std::vector<int> touching;
		void clear() {
			list.clear();
			touching.clear();
		}
	};

protected:
	static void _bind_methods();

public:
	// Building.
	void set_bounds(int p_cols, int p_rows);
	void set_solid(int p_cx, int p_cy, int p_kind);
	void add_segment(double p_ax, double p_ay, double p_bx, double p_by, double p_speed, double p_friction, int p_passes, bool p_belt);
	void finish_build();
	int register_type(int p_kind, int p_size_rank, int p_shape, const PackedFloat64Array &p_outline);
	void add_spawner(double p_x, double p_y, int p_interval, const PackedInt32Array &p_ore_types, const PackedInt32Array &p_rock_types);
	int add_bin(double p_min_x, double p_min_y, double p_max_x, double p_max_y);
	int add_crusher(int p_takes, int p_makes, int p_pieces, int p_duration, double p_min_x, double p_min_y, double p_max_x, double p_max_y, double p_press_y, double p_exit_x, double p_exit_y);
	int add_item(int p_type, double p_x, double p_y, double p_c, double p_s, double p_vx, double p_vy);

	// Running.
	void step();

	// Reading.
	int64_t get_tick() const { return tick; }
	void set_tick(int64_t p_tick) { tick = p_tick; }
	int get_lost() const { return lost; }
	int item_count() const { return (int)items.size(); }
	int sleeping_count() const;
	Dictionary get_item(int p_index) const;
	PackedFloat64Array snapshot() const;
	Dictionary delivered_by_kind() const;
	Dictionary bin_counts(int p_bin) const;
	int crusher_count() const { return (int)crushers.size(); }
	Dictionary crusher_state(int p_crusher) const;
	int spawned_count(int p_spawner) const;
	void clear_spawners() { spawners.clear(); }
	Array draw_buffers(int p_type_count) const;
	double max_overlap();
	void copy_items_from(const Ref<ItemWorld> &p_other);

private:
	// Tuning (same meaning as the comments in scripts/sim/simulation.gd).
	static constexpr int TICK_RATE = 60;
	static constexpr int SUBSTEPS = 2;
	static constexpr double H = 1.0 / (TICK_RATE * SUBSTEPS);
	static constexpr double GRAVITY = 900.0;
	static constexpr double MAX_SPEED = 400.0;
	static constexpr double MAX_SPIN = 30.0;
	static constexpr double ANGULAR_DAMPING = 0.998;
	static constexpr double MAX_STEP = 2.5;
	static constexpr double ITEM_FRICTION = 0.6;
	static constexpr int MAX_ITEMS = 3000;
	static constexpr double MAX_RADIUS = 9.0;
	static constexpr double SEG_CELL = 32.0;
	static constexpr double ITEM_CELL = 12.0;
	static constexpr double GRID_MARGIN = 64.0;
	static constexpr double INV_SQRT2 = 0.7071067811865476;
	static constexpr double SLEEP_MOVE = 0.5;
	static constexpr double SLEEP_TURN = 0.03;
	static constexpr int SLEEP_TICKS = 30;
	static constexpr double WAKE_SPEED = 60.0;
	static constexpr double SUPPORT_GAP = 1.0;
	static constexpr double SUPPORT_SLOPE = 0.3;
	static constexpr int PASS_TICKS = 6;
	static constexpr double BELT_PRESS = 0.15;

	enum Solid { SOLID_NONE = 0, SOLID_BOX = 1, SOLID_RAMP_DOWN_RIGHT = 2, SOLID_RAMP_DOWN_LEFT = 3 };

	std::vector<ItemType> types;
	std::map<int, int> type_lookup; // (kind, size_rank, shape) key -> type id
	std::vector<Body> items;
	std::vector<Segment> segments;
	std::vector<Spawner> spawners;
	std::vector<Bin> bins;
	std::vector<Crusher> crushers;
	std::map<int, int> delivered;
	int64_t tick = 0;
	int lost = 0;

	double kill_min_x = -64.0, kill_max_x = 64.0, kill_max_y = 64.0;
	int cols = 0, rows = 0;
	std::vector<uint8_t> solid;

	// Segment grid: SEG_CELL cells covering the world plus a margin of SEG_MARGIN cells.
	static constexpr int SEG_MARGIN = 2;
	int seg_cols = 1, seg_rows = 1;
	std::vector<std::vector<int>> seg_grid;

	// Item grid as linked lists in flat arrays (see _build_item_grid).
	int grid_cols = 1, grid_rows = 1;
	std::vector<int> cell_head;
	std::vector<int> node_item;
	std::vector<int> node_next;
	std::vector<int64_t> seen;
	int64_t query = 0;

	Contacts item_contacts;
	Contacts wall_contacts;

	static int type_key(int p_kind, int p_size_rank, int p_shape) { return (p_kind * 16 + p_size_rank) * 16 + p_shape; }
	static int kind_size_key(int p_kind, int p_size_rank) { return p_kind * 16 + p_size_rank; }

	void _init_body(Body &b, int p_type, double p_x, double p_y, double p_c, double p_s) const;
	void _update_world(Body &b) const;
	static void _turn(Body &b, double p_angle);

	void _run_spawners();
	void _run_crushers();
	void _release_pieces(Crusher &cr);
	bool _is_blocked_near(double p_x, double p_y, double p_reach) const;

	void _predict();
	void _finish_substep();
	void _detect();
	void _build_item_grid();
	int _grid_x(double p_x) const;
	int _grid_y(double p_y) const;
	const std::vector<int> *_walls_at(double p_x, double p_y) const;
	void _detect_pair(int ia, int ib);
	void _detect_wall(int ia, int si);
	int _deepest_face(double px, double py, const Body &b, double margin, double &depth) const;
	void _add_contact(Contacts &list, int ia, int ib, double pax, double pay, double pbx, double pby, double nx, double ny);

	void _solve(Contacts &list);
	void _move(Body &it, double px, double py, double rx, double ry);
	void _apply_friction(Body &a, Body *b, const Segment *seg, const Contact &ct, double lam);
	void _settle_velocities(const Contacts &list);
	static void _add_push(Body &it, double dx, double dy);

	void _push_out_of_solid(Body &it);
	void _push_out_along(Body &it, double depth, double nx, double ny);
	int _solid_at(int cx, int cy) const;
	bool _is_open(int cx, int cy, int side_x, int side_y) const;

	bool _is_carried(const Body &it) const { return it.carried_tick >= tick - 1; }
	void _wake(Body &it);
	void _update_sleep();
	void _check_support();
	bool _is_supported(int index);
	void _collect();
	void _wake_near(double x, double y);
};

} // namespace godot
