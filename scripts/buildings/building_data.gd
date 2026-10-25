class_name BuildingData
extends RefCounted
## Everything generated for one building, in lot-local space (origin at the
## lot centre on the ground-floor level, +Z facing the street).

var ext := MeshData.new() # Opaque, vertex-coloured.
var glass := MeshData.new() # Windows.
var boxes: Array = [] # Collision: [Transform3D, Vector3 size]
var id := "" # The lot id (prefix for door, window and spawn ids).
## Interactive doors: {xf: Transform3D (hinge, closed), w, h, t, color, id,
## out (+1/-1: which side is outdoors, 0: inside door), key, power}
var doors: Array = []
## Smashable ground-floor windows: {xf: Transform3D (pane centre), w, h, id}
var windows: Array = []
## Where zombies wait inside: {pos: Vector3, id, kind (zombie type or "")}
var spawns: Array = []
## Searchable loot containers: {pos: Vector3, type: String, id: String}
var containers: Array = []
## Shop signs: {xf: Transform3D, text: String, size: float, color: Color}
var signs: Array = []
## Props drawn by the chunk with shared meshes: {type: String, xf: Transform3D}
var props: Array = []
## Window openings, so furniture stays out of them: {rect: Rect2 (x, z,
## either side of the wall), y: float (floor), sill: float (height above it)}
var window_spots: Array = []
var interior := true # False for far-away (shell only) buildings.
