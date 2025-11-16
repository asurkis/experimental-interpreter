package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

Text :: [dynamic][dynamic]rune

WINDOW_PADDING :: 2

Window :: struct {
	topleft:  [2]f32,
	botright: [2]f32,
}

InputWindow :: struct {
	using window: Window,
	text:         Text,
	cursor:       [2]int,
}

renderer: ^sdl.Renderer

draw_window_frame :: proc(w: Window) {
	ogc: [4]u8
	sdl.GetRenderDrawColor(renderer, &ogc.x, &ogc.y, &ogc.z, &ogc.w)
	defer sdl.SetRenderDrawColor(renderer, ogc.x, ogc.y, ogc.z, ogc.w)

	sdl.SetRenderDrawColor(renderer, 63, 63, 255, 255)
	rect: sdl.FRect
	rect.w = WINDOW_PADDING
	rect.h = WINDOW_PADDING
	for i in 0 ..< 4 {
		rect.x = ((i & 1) == 0) ? w.topleft.x : w.botright.x - WINDOW_PADDING
		rect.y = ((i & 2) == 0) ? w.topleft.y : w.botright.y - WINDOW_PADDING
		sdl.RenderFillRect(renderer, &rect)
	}
	rect.y = w.topleft.y + WINDOW_PADDING
	rect.w = WINDOW_PADDING
	rect.h = w.botright.y - w.topleft.y - 2 * WINDOW_PADDING
	rect.x = w.topleft.x
	sdl.RenderFillRect(renderer, &rect)
	rect.x = w.botright.x - WINDOW_PADDING
	sdl.RenderFillRect(renderer, &rect)

	rect.x = w.topleft.x + WINDOW_PADDING
	rect.w = w.botright.x - w.topleft.x - 2 * WINDOW_PADDING
	rect.h = WINDOW_PADDING
	rect.y = w.topleft.y
	sdl.RenderFillRect(renderer, &rect)
	rect.y = w.botright.y - WINDOW_PADDING
	sdl.RenderFillRect(renderer, &rect)

	sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
	rect.x = w.topleft.x + WINDOW_PADDING
	rect.y = w.topleft.y + WINDOW_PADDING
	rect.w = w.botright.x - w.topleft.x - 2 * WINDOW_PADDING
	rect.h = w.botright.y - w.topleft.y - 2 * WINDOW_PADDING
	sdl.RenderFillRect(renderer, &rect)
}

draw_cursor :: proc(pos: [2]f32, padding: int) {
	rect: sdl.FRect
	rect.x = pos.x + f32(padding) * 8 - 2
	rect.y = pos.y - 2
	rect.w = 2
	rect.h = 10
	sdl.RenderFillRect(renderer, &rect)
}

draw_input_window :: proc(w: InputWindow) {
	draw_window_frame(w)
	topleft := w.topleft + WINDOW_PADDING + 4
	// botright := w.botright - WINDOW_PADDING
	offset: [2]f32
	for line, row in w.text {
		for ch, col in line {
			if row == w.cursor.y && col == w.cursor.x {
				draw_cursor(topleft + offset, 0)
			}
			if ch != ' ' && ch != '\t' {
				ch0: [5]byte
				ch1, _ := utf8.encode_rune(ch)
				for i in 0 ..< 4 do ch0[i] = ch1[i]
				ch_cstr := cstring(raw_data(ch0[:]))
				xy := topleft + offset
				sdl.RenderDebugText(renderer, xy.x, xy.y, ch_cstr)
			}
			offset.x += 8
		}
		if row == w.cursor.y && len(line) <= w.cursor.x {
			draw_cursor(topleft + offset, w.cursor.x - len(line))
		}
		offset.x = 0
		offset.y += 8
	}
	if len(w.text) <= w.cursor.y {
		pos := topleft
		pos.y += f32(w.cursor.y) * 8
		draw_cursor(pos, w.cursor.x)
	}
}

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

main :: proc() {
	ok: bool
	ok = sdl.Init(sdl.INIT_EVENTS | sdl.INIT_VIDEO)
	assert(ok)
	window := sdl.CreateWindow("Main window", 1280, 720, sdl.WINDOW_RESIZABLE)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ok = sdl.StartTextInput(window)
	assert(ok)
	renderer = sdl.CreateRenderer(window, nil)
	assert(renderer != nil)
	defer sdl.DestroyRenderer(renderer)

	input_window: InputWindow
	input_window.topleft = 8
	input_window.botright = 320
	last_out: cstring
	last_err: cstring
	last_ok: bool
	text_updated := true

	out_buf: [4096]byte
	out_log := strings.builder_from_bytes(out_buf[:])

	err_log: strings.Builder
	strings.builder_init(&err_log)
	defer strings.builder_destroy(&err_log)

	defer {
		for row in input_window.text do delete(row)
		delete(input_window.text)
	}
	append(&input_window.text, make([dynamic]rune))
	for ch in "(+ 1 1)" do append(&input_window.text[0], ch)

	main_loop: for {
		ok = sdl.WaitEvent(nil)
		assert(ok)
		for evt: sdl.Event; sdl.PollEvent(&evt); {
			#partial switch evt.type {
			case .QUIT:
				break main_loop
			case .TEXT_INPUT:
				if len(input_window.text) <= input_window.cursor.y {
					resize(&input_window.text, input_window.cursor.y + 1)
				}
				line := &input_window.text[input_window.cursor.y]
				for len(line^) < input_window.cursor.x do append(line, ' ')
				str := string(evt.text.text)
				rune_count := utf8.rune_count(str)
				n := len(line)
				resize(line, n + rune_count)
				for i := n - 1; i >= input_window.cursor.x; i -= 1 {
					line[i + rune_count] = line[i]
				}
				for ch in str {
					line[input_window.cursor.x] = ch
					input_window.cursor.x += 1
				}
				text_updated = true
			case .KEY_DOWN:
				switch evt.key.key {
				case sdl.K_ESCAPE:
					break main_loop
				case sdl.K_LEFT:
					input_window.cursor.x = max(input_window.cursor.x - 1, 0)
				case sdl.K_RIGHT:
					input_window.cursor.x += 1
				case sdl.K_UP:
					input_window.cursor.y = max(input_window.cursor.y - 1, 0)
				case sdl.K_DOWN:
					input_window.cursor.y += 1
				case sdl.K_HOME:
					input_window.cursor.x = 0
				case sdl.K_END:
					input_window.cursor.x = line_len(input_window.text, input_window.cursor.y)
				case sdl.K_RETURN:
					line := ptr_at(input_window.text[:], input_window.cursor.y)
					if line != nil {
						to_retain := min(input_window.cursor.x, len(line^))
						to_move := max(len(line^) - input_window.cursor.x, 0)
						new_line := make([dynamic]rune, 0, to_move)
						append(&new_line, ..line^[to_retain:])
						resize(line, to_retain)
						inject_at(&input_window.text, input_window.cursor.y + 1, new_line)
						text_updated = true
					}
					input_window.cursor.y += 1
					input_window.cursor.x = 0
				case sdl.K_BACKSPACE:
					if input_window.cursor.x > line_len(input_window.text, input_window.cursor.y) {
						input_window.cursor.x -= 1
						break
					}
					if input_window.cursor.y >= len(input_window.text) {
						input_window.cursor.y -= 1
						input_window.cursor.x = line_len(input_window.text, input_window.cursor.y)
						break
					}
					line := &input_window.text[input_window.cursor.y]
					if input_window.cursor.x > 0 {
						ordered_remove(line, input_window.cursor.x - 1)
						input_window.cursor.x -= 1
						text_updated = true
					} else if input_window.cursor.y > 0 {
						input_window.cursor.y -= 1
						prev_line := &input_window.text[input_window.cursor.y]
						input_window.cursor.x = len(prev_line^)
						append(prev_line, ..line^[:])
						delete(line^)
						ordered_remove(&input_window.text, input_window.cursor.y + 1)
						text_updated = true
					}
				case sdl.K_DELETE:
					line := ptr_at(input_window.text[:], input_window.cursor.y)
					(line != nil) or_break
					if input_window.cursor.x < len(line^) {
						ordered_remove(line, input_window.cursor.x)
						text_updated = true
					} else if input_window.cursor.y + 1 < len(input_window.text) {
						next_line := input_window.text[input_window.cursor.y + 1]
						n := len(line^)
						reserve(line, input_window.cursor.x + len(next_line))
						resize(line, input_window.cursor.x)
						for i in n ..< input_window.cursor.x do line^[i] = ' '
						append(line, ..next_line[:])
						delete(next_line)
						ordered_remove(&input_window.text, input_window.cursor.y + 1)
						text_updated = true
					}
				}
			}
		}

		if text_updated {
			new_result: i64
			strings.builder_reset(&err_log)
			_, new_result, ok = interpret(&err_log, input_window.text, 0)
			if ok {
				strings.builder_reset(&out_log)
				fmt.sbprint(&out_log, new_result)
				last_out = strings.to_cstring(&out_log)
			}
			last_err = strings.to_cstring(&err_log)
			last_ok = ok
			text_updated = false
		}

		sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
		sdl.RenderClear(renderer)
		sdl.SetRenderScale(renderer, 2, 2)
		sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
		draw_input_window(input_window)

		if last_ok {
			sdl.SetRenderDrawColor(renderer, 0, 191, 0, 255)
		} else {
			sdl.SetRenderDrawColor(renderer, 191, 191, 191, 255)
		}
		sdl.RenderDebugText(renderer, 320, 8, last_out)
		sdl.SetRenderDrawColor(renderer, 191, 0, 0, 255)
		sdl.RenderDebugText(renderer, 320, 16, last_err)
		sdl.RenderPresent(renderer)
	}
}

