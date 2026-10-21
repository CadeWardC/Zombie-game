class_name BuildingData
extends RefCounted
## Everything generated for one building, in lot-local space (origin at the
## lot centre on the ground-floor level, +Z facing the street).

var ext := MeshData.new() # Opaque, vertex-coloured.
var glass := MeshData.new() # Windows.
var boxes: Array = [] # Collision: [Transform3D, Vector3 size]
## Interactive doors: {xf: Transform3D (hinge, closed), w, h, t, color, id}
var doors: Array = []
## Searchable loot containers: {pos: Vector3, type: String, id: String}
var containers: Array = []
## Shop signs: {xf: Transform3D, text: String, size: float, color: Color}
var signs: Array = []
## Props drawn by the chunk with shared meshes: {type: String, xf: Transform3D}
var props: Array = []
var interior := true # False for far-away (shell only) buildings.
