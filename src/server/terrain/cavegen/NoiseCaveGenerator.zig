const std = @import("std");
const Allocator = std.mem.Allocator;
const sign = std.math.sign;

const main = @import("root");
const Array2D = main.utils.Array2D;
const Array3D = main.utils.Array3D;
const RandomList = main.utils.RandomList;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const InterpolatableCaveBiomeMapView = terrain.CaveBiomeMap.InterpolatableCaveBiomeMapView;
const FractalNoise = terrain.noise.FractalNoise;
const RandomlyWeightedFractalNoise = terrain.noise.RandomlyWeightedFractalNoise;
const PerlinNoise = terrain.noise.PerlinNoise;
const FractalNoise3D = terrain.noise.FractalNoise3D;
const Biome = terrain.biomes.Biome;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:noise_cave";

pub const priority = 65536;

pub const generatorSeed = 0x76490367012869;

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

const scale = 64;
const interpolatedPart = 4;

fn getValue(noise: Array3D(f32), map: *CaveMapFragment, biomeMap: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32) f32 {
	return noise.get(@intCast(u31, wx - map.pos.wx) >> map.voxelShift, @intCast(u31, wy - map.pos.wy) >> map.voxelShift, @intCast(u31, wz - map.pos.wz) >> map.voxelShift) + biomeMap.interpolateValue(wx, wy, wz, "caves")*scale;
}

pub fn generate(map: *CaveMapFragment, worldSeed: u64) Allocator.Error!void {
	if(map.pos.voxelSize > 2) return;
	const biomeMap = try InterpolatableCaveBiomeMapView.init(map.pos, CaveMapFragment.width*map.pos.voxelSize);
	defer biomeMap.deinit();
	const outerSize = @max(map.pos.voxelSize, interpolatedPart);
	var noise = try FractalNoise3D.generateAligned(main.threadAllocator, map.pos.wx, map.pos.wy, map.pos.wz, map.pos.voxelSize, CaveMapFragment.width + 1, CaveMapFragment.height + 1, CaveMapFragment.width + 1, worldSeed, scale);//try Cached3DFractalNoise.init(map.pos.wx, map.pos.wy & ~@as(i32, CaveMapFragment.width*map.pos.voxelSize - 1), map.pos.wz, outerSize, map.pos.voxelSize*CaveMapFragment.width, worldSeed, scale);
	defer noise.deinit(main.threadAllocator);
	var x: u31 = 0;
	while(x < map.pos.voxelSize*CaveMapFragment.width) : (x += outerSize) {
		var y: u31 = 0;
		while(y < map.pos.voxelSize*CaveMapFragment.height) : (y += outerSize) {
			var z: u31 = 0;
			while(z < map.pos.voxelSize*CaveMapFragment.width) : (z += outerSize) {
				const val000 = getValue(noise, map, biomeMap, x + map.pos.wx, y + map.pos.wy, z + map.pos.wz);
				const val001 = getValue(noise, map, biomeMap, x + map.pos.wx, y + map.pos.wy, z + map.pos.wz + outerSize);
				const val010 = getValue(noise, map, biomeMap, x + map.pos.wx, y + map.pos.wy + outerSize, z + map.pos.wz);
				const val011 = getValue(noise, map, biomeMap, x + map.pos.wx, y + map.pos.wy + outerSize, z + map.pos.wz + outerSize);
				const val100 = getValue(noise, map, biomeMap, x + map.pos.wx + outerSize, y + map.pos.wy, z + map.pos.wz);
				const val101 = getValue(noise, map, biomeMap, x + map.pos.wx + outerSize, y + map.pos.wy, z + map.pos.wz + outerSize);
				const val110 = getValue(noise, map, biomeMap, x + map.pos.wx + outerSize, y + map.pos.wy + outerSize, z + map.pos.wz);
				const val111 = getValue(noise, map, biomeMap, x + map.pos.wx + outerSize, y + map.pos.wy + outerSize, z + map.pos.wz + outerSize);
				// Test if they are all inside or all outside the cave to skip these cases:
				const measureForEquality = sign(val000) + sign(val001) + sign(val010) + sign(val011) + sign(val100) + sign(val101) + sign(val110) + sign(val111);
				if(measureForEquality == -8) {
					// No cave in here :)
					continue;
				}
				if(measureForEquality == 8) {
					// All cave in here :)
					var dx: u31 = 0;
					while(dx < outerSize) : (dx += map.pos.voxelSize) {
						var dz: u31 = 0;
						while(dz < outerSize) : (dz += map.pos.voxelSize) {
							map.removeRange(x + dx, z + dz, y, y + outerSize);
						}
					}
				} else {
					// Uses trilinear interpolation for the details.
					// Luckily due to the blocky nature of the game there is no visible artifacts from it.
					var dx: u31 = 0;
					while(dx < outerSize) : (dx += map.pos.voxelSize) {
						var dz: u31 = 0;
						while(dz < outerSize) : (dz += map.pos.voxelSize) {
							const ix = @intToFloat(f32, dx)/@intToFloat(f32, outerSize);
							const iz = @intToFloat(f32, dz)/@intToFloat(f32, outerSize);
							const lowerVal = (
								(1 - ix)*(1 - iz)*val000
								+ (1 - ix)*iz*val001
								+ ix*(1 - iz)*val100
								+ ix*iz*val101
							);
							const upperVal = (
								(1 - ix)*(1 - iz)*val010
								+ (1 - ix)*iz*val011
								+ ix*(1 - iz)*val110
								+ ix*iz*val111
							);
							// TODO: Determine the range that needs to be removed, and remove it in one go.
							if(upperVal*lowerVal > 0) { // All y values have the same sign → the entire column is the same.
								if(upperVal > 0) {
									// All cave in here :)
									map.removeRange(x + dx, z + dz, y, y + outerSize);
								} else {
									// No cave in here :)
								}
							} else {
								// Could be more efficient, but I'm lazy right now and I'll just go through the entire range:
								var dy: u31 = 0;
								while(dy < outerSize) : (dy += map.pos.voxelSize) {
									const iy = @intToFloat(f32, dy)/@intToFloat(f32, outerSize);
									const val = (1 - iy)*lowerVal + iy*upperVal;
									if(val > 0)
										map.removeRange(x + dx, z + dz, y + dy, y + dy + map.pos.voxelSize);
								}
							}
						}
					}
				}
			}
		}
	}
}