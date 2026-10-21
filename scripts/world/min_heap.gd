class_name MinHeap
extends RefCounted
## Binary min-heap of (priority, int value) pairs.

var _keys := PackedFloat32Array()
var _vals := PackedInt32Array()


func size() -> int:
	return _keys.size()


func push(key: float, val: int) -> void:
	_keys.append(key)
	_vals.append(val)
	var i := _keys.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _keys[parent] <= key:
			break
		_keys[i] = _keys[parent]
		_vals[i] = _vals[parent]
		i = parent
	_keys[i] = key
	_vals[i] = val


func pop() -> int:
	var top := _vals[0]
	var last := _keys.size() - 1
	var key := _keys[last]
	var val := _vals[last]
	_keys.resize(last)
	_vals.resize(last)
	if last == 0:
		return top
	var i := 0
	while true:
		var child := i * 2 + 1
		if child >= last:
			break
		if child + 1 < last and _keys[child + 1] < _keys[child]:
			child += 1
		if _keys[child] >= key:
			break
		_keys[i] = _keys[child]
		_vals[i] = _vals[child]
		i = child
	_keys[i] = key
	_vals[i] = val
	return top
