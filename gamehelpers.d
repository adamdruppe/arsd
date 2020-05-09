/++
	Note: much of the functionality of gamehelpers was moved to [arsd.game] on May 3, 2020.
	If you used that code, change `import arsd.gamehelpers;` to `import arsd.game;` and add
	game.d to your build (in addition to gamehelpers.d; the new game.d still imports this module)
	and you should be good to go.

	This module now builds on only [arsd.color] to provide additional algorithm functions
	and data types that are common in games.

	History:
		Massive change on May 3, 2020 to move the previous flagship class out and to
		a new module, [arsd.game], to make this one lighter on dependencies, just
		containing helpers rather than a consolidated omnibus import.
+/
module arsd.gamehelpers;

deprecated("change `import arsd.gamehelpers;` to `import arsd.game;`")
void* create2dWindow(string title, int width = 512, int height = 512) { return null; }

deprecated("change `import arsd.gamehelpers;` to `import arsd.game;`")
class GameHelperBase {}

import std.math;

import arsd.color;

// Some math helpers

int nextPowerOfTwo(int v) {
	v--;
	v |= v >> 1;
	v |= v >> 2;
	v |= v >> 4;
	v |= v >> 8;
	v |= v >> 16;
	v++;
	return v;
}

/++
	Calculates the cross product of <u1, u2, u3> and <v1, v2, v3>, putting the result in <s1, s2, s3>.
+/
void crossProduct(
	float u1, float u2, float u3,
	float v1, float v2, float v3,
	out float s1, out float s2, out float s3)
{
	s1 = u2 * v3 - u3 * v2;
	s2 = u3 * v1 - u1 * v3;
	s3 = u1 * v2 - u2 * v1;
}

/++
	3D rotates (x, y, z) theta radians about the axis represented by unit-vector (u, v, w), putting the results in (s1, s2, s3).

	For example, to rotate about the Y axis, pass (0, 1, 0) as (u, v, w).
+/
void rotateAboutAxis(
	float theta, // in RADIANS
	float x, float y, float z,
	float u, float v, float w,
	out float xp, out float yp, out float zp)
{
	xp = u * (u*x + v*y + w*z) * (1 - cos(theta)) + x * cos(theta) + (-w*y + v*z) * sin(theta);
	yp = v * (u*x + v*y + w*z) * (1 - cos(theta)) + y * cos(theta) + (w*x - u*z) * sin(theta);
	zp = w * (u*x + v*y + w*z) * (1 - cos(theta)) + z * cos(theta) + (-v*x + u*y) * sin(theta);
}

/++
	2D rotates (rotatingX, rotatingY) theta radians about (originX, originY), putting the result in (xp, yp).
+/
void rotateAboutPoint(
	float theta, // in RADIANS
	float originX, float originY,
	float rotatingX, float rotatingY,
	out float xp, out float yp)
{
	if(theta == 0) {
		xp = rotatingX;
		yp = rotatingY;
		return;
	}

	rotatingX -= originX;
	rotatingY -= originY;

	float s = sin(theta);
	float c = cos(theta);

	float x = rotatingX * c - rotatingY * s;
	float y = rotatingX * s + rotatingY * c;

	xp = x + originX;
	yp = y + originY;
}

/++
	Represents the four basic directions on a grid. You can conveniently use it like:

	---
	Point pt = Point(5, 3);
	pt += Dir.N; // moves up
	---

	The opposite direction btw can be gotten with `pt * -1`.

	History: Added May 3, 2020
+/
enum Dir { N = Point(0, -1), S = Point(0, 1), W = Point(-1, 0), E = Point(1, 0) }

/++
	The four directions as a static array so you can assign to a local variable
	then shuffle, etc.

	History: Added May 3, 2020
+/
Point[4] directions() {
	with(Dir) return [N, S, W, E];
}

/++
	A random value off [Dir].

	History: Added May 3, 2020
+/
Point randomDirection() {
	import std.random;
	return directions()[uniform(0, 4)];
}

/++
	Cycles through all the directions the given number of times. If you have
	one cycle, it goes through each direction once in a random order. With two
	cycles, it will move each direction twice, but in random order - can be
	W, W, N, E, S, S, N, E, for example; it will not do the cycles in order but
	upon completion will have gone through them all.

	This can be convenient because if the character's movement is not constrained,
	it will always return back to where it started after a random movement.

	Returns: an input range of [Point]s. Please note that the current version returns
	`Point[]`, but I reserve the right to change that in the future; I only promise
	input range capabilities.

	History: Added May 3, 2020
+/
auto randomDirectionCycle(int cycleCount = 1) {
	Point[] all = new Point[](cycleCount * 4);
	foreach(c; 0 .. cycleCount)
		all[c * 4 .. c * 4 + 4] = directions()[];

	import std.random;
	return all.randomShuffle;
}

/++
	Represents a 2d grid like an array. To encapsulate the whole `[y*width + x]` thing.

	History:
		Added May 3, 2020
+/
struct Grid(T) {
	private Size size_;
	private T[] array;

	pure @safe nothrow:

	/// Creates a new GC-backed array
	this(Size size) {
		this.size_ = size;
		array = new T[](size.area);
	}

	/// ditto
	this(int width, int height) {
		this(Size(width, height));
	}

	@nogc:

	/// Wraps an existing array.
	this(T[] array, Size size) {
		assert(array.length == size.area);
		this.array = array;
		this.size_ = size;
	}

	@property {
		///
		inout(Size) size() inout { return size_; }
		///
		int width() const { return size.width; }
		///
		int height() const { return size.height; }
	}

	/// Slice operation gives a view into the underlying 1d array.
	inout(T)[] opIndex() inout {
		return array;
	}

	///
	ref inout(T) opIndex(int x, int y) inout {
		return array[y * width + x];
	}

	///
	ref inout(T) opIndex(const Point pt) inout {
		return this.opIndex(pt.x, pt.y);
	}
	// T[] opSlice

	///
	bool inBounds(int x, int y) const {
		return x >= 0 && y >= 0 && x < width && y < height;
	}

	///
	bool inBounds(const Point pt) const {
		return inBounds(pt.x, pt.y);
	}

	/// Supports `if(point in grid) {}`
	bool opBinaryRight(string op : "in")(Point pt) const {
		return inBounds(pt);
	}
}

/++
	Directions as a maskable bit flag.

	History: Added May 3, 2020
+/
enum DirFlag : ubyte {
	N = 4,
	S = 8,
	W = 1,
	E = 2
}

/++
	History: Added May 3, 2020
+/
DirFlag dirFlag(Dir dir) {
	assert(dir.x >= -1 && dir.x <= 1);
	assert(dir.y >= -1 && dir.y <= 1);


	/+
		(-1 + 3) / 2 = 2 / 2 = 1
		(1 + 3) / 2  = 4 / 2 = 2

		So the al-gore-rhythm is
			(x + 3) / 2
				which is aka >> 1
			  or
			((y + 3) / 2) << 2
				which is aka >> 1 << 2 aka << 1
		So:
			1 = left
			2 = right
			4 = up
			8 = down
	+/

	ubyte dirFlag;
	if(dir.x) dirFlag |= ((dir.x + 3) >> 1);
	if(dir.y) dirFlag |= ((dir.y + 3) << 1);
	return cast(DirFlag) dirFlag;
}

// this is public but like i don't want do document it since it can so easily fail the asserts.
DirFlag dirFlag(Point dir) {
	return dirFlag(cast(Dir) dir);
}

/++
	Generates a maze.

	The returned array is a grid of rooms, with a bit flag pattern of directions you can travel from each room. See [DirFlag] for bits.

	History: Added May 3, 2020
+/
Grid!ubyte generateMaze(int mazeWidth, int mazeHeight) {
	import std.random;

	Point[] cells;
	cells ~= Point(uniform(0, mazeWidth), uniform(0, mazeHeight));

	auto grid = Grid!ubyte(mazeWidth, mazeHeight);

	Point[4] directions = .directions;

	while(cells.length) {
		auto index = cells.length - 1; // could also be 0 or uniform or whatever too
		Point p = cells[index];
		bool added;
		foreach(dir; directions[].randomShuffle) {
			auto n = p + dir;
			if(n !in grid)
				continue;

			if(grid[n])
				continue;

			grid[p] |= dirFlag(dir);
			grid[n] |= dirFlag(dir * -1);

			cells ~= n;

			added = true;
			break;
		}

		if(!added) {
			foreach(i; index .. cells.length - 1)
				cells[index] = cells[index + 1];
			cells = cells[0 .. $-1];
		}
	}

	return grid;
}


/++
	Implements the A* path finding algorithm on a grid.

	Params:
		start = starting point on the grid
		goal = destination point on the grid
		size = size of the grid
		isPassable = used to determine if the tile at the given coordinates are passible
		d = weight function to the A* algorithm. If null, assumes all will be equal weight. Returned value must be greater than or equal to 1.
		h = heuristic function to the A* algorithm. Gives an estimation of how many steps away the goal is from the given point to speed up the search. If null, assumes "taxicab distance"; the number of steps based solely on distance without diagonal movement. If you want to disable this entirely, pass `p => 0`.
	Returns:
		A list of waypoints to reach the destination, or `null` if impossible. The waypoints are returned in reverse order, starting from the goal and working back to the start.

		So to get to the goal from the starting point, follow the returned array in $(B backwards).

		The waypoints will not necessarily include every step but also may not only list turns, but if you follow
		them you will get get to the destination.

	Bugs:
		The current implementation uses more memory than it really has to; it will eat like 8 MB of scratch space RAM on a 512x512 grid.

		It doesn't consider wraparound possible so it might ask you to go all the way around the world unnecessarily.

	History:
		Added May 2, 2020.
+/
Point[] pathfind(Point start, Point goal, Size size, scope bool delegate(Point) isPassable, scope int delegate(Point, Point) d = null, scope int delegate(Point) h = null) {

	Point[] reconstruct_path(scope Point[] cameFrom, Point current) {
		Point[] totalPath;
		totalPath ~= current;

		auto cf = cameFrom[current.y * size.width + current.x];
		while(cf != Point(int.min, int.min)) {
			current = cf;
			cf = cameFrom[current.y * size.width + current.x];
			totalPath ~= current;
		}
		return totalPath;
	}

	// weighting thing.....
	static int d_default(Point a, Point b) {
		return 1;
	}

	if(d is null)
		d = (Point a, Point b) => d_default(a, b);

	if(h is null)
		h = (Point a) { return abs(a.y - goal.x) + abs(a.y - goal.y); };

	Point[] openSet = [start];

	Point[] cameFrom = new Point[](size.area);
	cameFrom[] = Point(int.min, int.min);

	int[] gScore = new int[](size.area);
	gScore[] = int.max;
	gScore[start.y * size.width + start.x] = 0;

	int[] fScore = new int[](size.area);
	fScore[] = int.max;
	fScore[start.y * size.width + start.x] = h(start);

	while(openSet.length) {
		Point current;
		size_t currentIdx;
		int currentFscore = int.max;
		foreach(idx, pt; openSet) {
			auto p = fScore[pt.y * size.width + pt.x];
			if(p <= currentFscore) {
				currentFscore = p;
				current = pt;
				currentIdx = idx;
			}
		}

		if(current == goal) {
/+
import std.stdio;
foreach(y; 0 .. size.height)
	writefln("%(%02d,%)", gScore[y * size.width .. y * size.width + size.width]);
+/
			return reconstruct_path(cameFrom, current);
		}

		openSet[currentIdx] = openSet[$-1];
		openSet = openSet[0 .. $-1];

		Point[4] neighborsBuffer;
		int neighborsBufferLength = 0;

		if(current.x + 1 < size.width && isPassable(current + Point(1, 0)))
			neighborsBuffer[neighborsBufferLength++] = current + Point(1, 0);
		if(current.x && isPassable(current + Point(-1, 0)))
			neighborsBuffer[neighborsBufferLength++] = current + Point(-1, 0);
		if(current.y && isPassable(current + Point(0, -1)))
			neighborsBuffer[neighborsBufferLength++] = current + Point(0, -1);
		if(current.y + 1 < size.height && isPassable(current + Point(0, 1)))
			neighborsBuffer[neighborsBufferLength++] = current + Point(0, 1);

		foreach(neighbor; neighborsBuffer[0 .. neighborsBufferLength]) {
			auto tentative_gScore = gScore[current.y * size.width + current.x] + d(current, neighbor);
			if(tentative_gScore < gScore[neighbor.y * size.width + neighbor.x]) {
				cameFrom[neighbor.y * size.width + neighbor.x] = current;
				gScore[neighbor.y * size.width + neighbor.x] = tentative_gScore;
				fScore[neighbor.y * size.width + neighbor.x] = tentative_gScore + h(neighbor);
				// this linear thing might not be so smart after all
				bool found = false;
				foreach(o; openSet)
					if(o == neighbor) { found = true; break; }
				if(!found)
					openSet ~= neighbor;
			}
		}
	}

	return null;
}
