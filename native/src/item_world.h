#pragma once

// Deterministic physics for Mini Machinist: items as convex polygons that slide, tip, stack
// and settle, plus static segments, belts, spawners, crushers, sorters and bins (this file
// and item_world.cpp); heat (item_world.cpp); and a pixel layer of molten and hardened metal
// that flows like falling sand (pixel_world.cpp).
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
#include <godot_cpp/variant/packed_byte_array.hpp>
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

	// Every world pixel is empty, part wall, or metal: molten (flows like falling sand,
	// heavier iron sinks through slag) or hardened (stays put, and items land on it).
	enum Pixel : uint8_t { PIX_EMPTY = 0, PIX_WALL = 1, PIX_IRON = 2, PIX_SLAG = 3, PIX_SOLID_IRON = 4, PIX_SOLID_SLAG = 5 };

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
		// Degrees Celsius; taken on from whatever the item touches.
		double temp = 20.0;
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

	// A closed box on a belt line. Items that ride or drop into its mouth vanish inside; after a
	// moment each comes out either the bottom (its material matches `filter`) or the far side
	// onto the next belt, in the order they went in.
	struct Sorter {
		double min_x, min_y, max_x, max_y;
		int filter;
		// Far-side exit: an edge x (items come out beyond it), the belt's top y and speed.
		double out_x, out_y, out_vx;
		// Bottom exit: center x and the box's bottom y.
		double drop_x, drop_y;
		struct Held {
			Body body;
			int64_t release;
			bool match;
		};
		std::vector<Held> inside;
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
	int add_sorter(double p_min_x, double p_min_y, double p_max_x, double p_max_y, int p_filter, double p_out_x, double p_out_y, double p_out_vx, double p_drop_x, double p_drop_y);

	// Heat.
	void heat_fill_rect(double p_x0, double p_y0, double p_x1, double p_y1, int p_material);
	void heat_fill_polygon(const PackedFloat64Array &p_points, int p_material);
	int add_heater(double p_x0, double p_y0, double p_x1, double p_y1);
	void set_heater_power(int p_heater, double p_power);
	double heat_at(double p_x, double p_y) const;
	PackedByteArray heat_image() const;
	int heat_columns() const { return heat_cols; }
	int heat_rows_count() const { return heat_rows; }
	double type_radius(int p_type) const;
	// How a hot solid glows at temperature `t`: RGBA, all zero below GLOW_START.
	static void glow_color(double t, double out[4]);

	// Pixels: molten and hardened metal (pixel_world.cpp).
	void pixel_fill_rect(double p_x0, double p_y0, double p_x1, double p_y1);
	void pixel_fill_polygon(const PackedFloat64Array &p_points);
	void set_melt_point(int p_kind, double p_temp);
	void add_liquid(double p_x0, double p_y0, double p_x1, double p_y1, bool p_iron, double p_temp);
	int add_skimmer(double p_x0, double p_y0, double p_x1, double p_y1, const PackedInt32Array &p_slag_types);
	Dictionary pixel_counts() const;
	int pixel_at(int p_x, int p_y) const;
	PackedInt32Array dirty_chunks();
	PackedByteArray chunk_image(int p_chunk) const;
	int chunk_columns() const { return chunk_cols; }
	int chunk_size() const { return CHUNK; }

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
	// How many items a sorter holds at once, and how long each stays inside.
	static constexpr int SORTER_HOLDS = 3;
	static constexpr int SORTER_TICKS = 12;

	// Heat: a grid of HEAT_CELL-pixel cells, each made of a material that sets how well it
	// passes heat to its neighbours. Air also slowly cools back toward room temperature.
	static constexpr double HEAT_CELL = 4.0;
	static constexpr double AMBIENT = 20.0;
	enum HeatMaterial { HEAT_AIR = 0, HEAT_METAL = 1, HEAT_INSULATION = 2 };
	// Share of the temperature difference that crosses between two touching cells per tick
	// (the smaller of the two materials' values is used). Metal: 4 neighbours x 0.2 keeps
	// the update stable.
	static constexpr double CONDUCT[3] = { 0.02, 0.2, 0.004 };
	static constexpr double AIR_COOLING = 0.003;
	static constexpr double MAX_TEMP = 3000.0;
	// Items take on the temperature of what they touch: this share of the gap per tick
	// touching something solid (doubling for each size down), or AIR_HEATING in open air.
	static constexpr double CONTACT_HEATING = 0.02;
	static constexpr double AIR_HEATING = 0.003;
	// Below this, nothing glows.
	static constexpr double GLOW_START = 450.0;

	static constexpr int CHUNK = 64;
	// Molten metal hardens below its freezing point and hardened metal melts above its
	// melting point (the gap stops it flickering between the two).
	static constexpr double IRON_FREEZE = 1400.0;
	static constexpr double IRON_MELT = 1500.0;
	static constexpr double SLAG_FREEZE = 1150.0;
	static constexpr double SLAG_MELT = 1250.0;
	// A metal pixel closes this share of the gap to its heat cell's temperature per tick, and
	// the heat cell moves PIXEL_HEAT_SHARE of that the other way (molten metal heats what holds it).
	static constexpr double PIXEL_HEAT_RATE = 0.01;
	static constexpr double PIXEL_HEAT_SHARE = 0.125;
	// Items touching molten metal take on its temperature this fast (doubling for each size down).
	static constexpr double LIQUID_ITEM_HEATING = 0.05;
	// Share of melting iron ore that becomes iron; the rest is slag.
	static constexpr double ORE_IRON = 0.7;
	// How far a molten pixel can slide sideways in one tick; iron runs thinner than slag.
	static constexpr int IRON_SPREAD = 4;
	static constexpr int SLAG_SPREAD = 2;
	// Items in molten metal: lifted by this many times gravity per share of them that's in
	// molten iron (rock and ore float on iron), and slowed each tick.
	static constexpr double BUOYANCY = 1.6;
	static constexpr double LIQUID_DRAG = 0.9;
	// How far up a molten pixel looks for room when an item pushes into it.
	static constexpr int DISPLACE_REACH = 24;
	// A skimmer takes this many slag pixels a tick, and drops a lump per SKIM_LUMP taken.
	static constexpr int SKIM_PER_TICK = 3;
	static constexpr int SKIM_LUMP = 35;
	// Hardened metal's collision edges are rebuilt this often (in ticks) while it changes.
	static constexpr int SOLID_REBUILD_TICKS = 8;

	// SOLID_TOP_HALF fills the top half of its tile (a conveyor).
	enum Solid { SOLID_NONE = 0, SOLID_BOX = 1, SOLID_RAMP_DOWN_RIGHT = 2, SOLID_RAMP_DOWN_LEFT = 3, SOLID_TOP_HALF = 4 };

	std::vector<ItemType> types;
	std::map<int, int> type_lookup; // (kind, size_rank, shape) key -> type id
	std::vector<Body> items;
	std::vector<Segment> segments;
	std::vector<Spawner> spawners;
	std::vector<Bin> bins;
	std::vector<Crusher> crushers;
	std::vector<Sorter> sorters;

	struct Heater {
		std::vector<int> cells;
		double power = 0.0;
	};
	int heat_cols = 0, heat_rows = 0;
	std::vector<double> heat, heat_next;
	std::vector<uint8_t> heat_mat;
	// heat_mat with every air cell that has metal pixels in it counted as metal, so a pool of
	// molten metal passes heat along and doesn't cool like air (refreshed by _pixel_heat).
	std::vector<uint8_t> heat_eff;
	std::vector<Heater> heaters;

	struct Skimmer {
		double x0, y0, x1, y1;
		std::vector<int> slag_types;
		int taken = 0;
		// Where the slag came from (left of center negative), so lumps leave the other way.
		double side = 0.0;
		int lumps = 0;
	};
	int pix_w = 0, pix_h = 0;
	std::vector<uint8_t> pix;
	std::vector<float> pix_temp;
	// The tick each pixel last moved, so a pixel moves once per tick.
	std::vector<int64_t> pix_moved;
	// Which way each molten pixel is flowing sideways (-1 or 1): it keeps going until it's
	// blocked, then turns, so a pool levels out instead of jittering in place.
	std::vector<int8_t> pix_dir;
	// Pixels covered by an item this tick (molten metal flows around them).
	std::vector<uint8_t> pix_item;
	std::vector<int> item_pixels;
	int chunk_cols = 0, chunk_rows = 0;
	std::vector<uint8_t> chunk_dirty;
	// Bounding boxes of molten pixels and of hardened ones (x0 > x1 when there are none).
	int liq_x0 = 1, liq_y0 = 1, liq_x1 = 0, liq_y1 = 0;
	int sol_x0 = 1, sol_y0 = 1, sol_x1 = 0, sol_y1 = 0;
	bool solids_changed = false;
	// The parts' walls; hardened metal's edges are added on top of these.
	std::vector<Segment> base_segments;
	// Per material kind; 0 never melts.
	std::vector<double> melt_points;
	std::vector<Skimmer> skimmers;
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
	void _run_sorters();
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

	void _index_segments();
	// A plain wall segment, and straight runs of segments joined (see merge_runs).
	static Segment make_wall(double ax, double ay, double bx, double by);
	static std::vector<Segment> merge_walls(const std::vector<Segment> &input);
	void _step_pixels();
	void _touch_liquid_items();
	void _melt_items();
	void _melt_into_pixels(const Body &it);
	void _place_pixel(int x, int y, uint8_t material, float temp);
	void _flow_liquids();
	bool _flow_one(int x, int y);
	void _move_pixel(int from, int to);
	void _pixel_heat();
	void _run_skimmers();
	void _rebuild_solid_edges();
	void _grow_box(int &x0, int &y0, int &x1, int &y1, int x, int y);
	void _dirty(int x, int y);
	template <typename Inside>
	void _fill_pixels(double p_x0, double p_y0, double p_x1, double p_y1, Inside p_inside);

	void _step_heat();
	void _heat_items();
	int _heat_cell(double p_x, double p_y) const;
	template <typename Inside>
	void _fill_heat(double p_x0, double p_y0, double p_x1, double p_y1, int p_material, Inside p_inside);
};

} // namespace godot
