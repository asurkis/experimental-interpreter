package main

ptr_at :: proc "contextless" (arr: []$T, #any_int pos: int) -> ^T {
	out: ^T
	if pos < len(arr) do out = &arr[pos]
	return out
}

at_or_default :: proc "contextless" (arr: []$T, #any_int pos: int, default: T) -> T {
	out := default
	if pos < len(arr) do out = arr[pos]
	return out
}

at_or_zero :: proc "contextless" (arr: []$T, #any_int pos: int) -> T {
	return at_or_default(arr, pos, T{})
}

at :: proc {
	at_or_default,
	at_or_zero,
}

line_len :: proc(text: Text, row: int) -> int {
	return len(at(text[:], row))
}

