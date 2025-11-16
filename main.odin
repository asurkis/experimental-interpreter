package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

Text :: [dynamic][dynamic]byte

WINDOW_PADDING :: 2

Window :: struct {
	topleft:  [2]f32,
	botright: [2]f32,
}

InputWindow :: struct {
	using window: Window,
	text:         Text,
	cursor:       [2]int, // -1 for non-editable
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
		for col := 0; col < len(line); {
			ch, ch_sz := utf8.decode_rune(line[col:])
			defer col += ch_sz
			if row == w.cursor.y && col == w.cursor.x {
				draw_cursor(topleft + offset, 0)
			}
			if ch != ' ' && ch != '\t' {
				ch0: [5]byte
				for i in 0 ..< ch_sz {
					ch0[i] = line[col + i]
				}
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
	append(&input_window.text, make([dynamic]byte))
	append(&input_window.text[0], "(+ 1 1)")

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
				for len(line^) < input_window.cursor.x {
					append(line, ' ')
				}
				str := transmute([]byte)cast(string)evt.text.text
				inject_at(line, input_window.cursor.x, ..str)
				input_window.cursor.x += len(str)
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
					if input_window.cursor.y < len(input_window.text) {
						input_window.cursor.x = len(input_window.text[input_window.cursor.y])
					} else {
						input_window.cursor.x = 0
					}
				case sdl.K_RETURN:
					if input_window.cursor.y < len(input_window.text) {
						line := &input_window.text[input_window.cursor.y]
						to_retain := min(input_window.cursor.x, len(line^))
						to_move := max(len(line^) - input_window.cursor.x, 0)
						new_line := make([dynamic]byte, 0, to_move)
						append(&new_line, ..line^[to_retain:])
						resize(line, to_retain)
						inject_at(&input_window.text, input_window.cursor.y + 1, new_line)
						text_updated = true
					}
					input_window.cursor.y += 1
					input_window.cursor.x = 0
				case sdl.K_BACKSPACE:
					if input_window.cursor.y < len(input_window.text) &&
					   input_window.cursor.x <= len(input_window.text[input_window.cursor.y]) {
						line := &input_window.text[input_window.cursor.y]
						if input_window.cursor.x > 0 {
							_, ch_sz := utf8.decode_last_rune(line^[:input_window.cursor.x])
							input_window.cursor.x -= ch_sz
							n := len(line^) - ch_sz
							for i in input_window.cursor.x ..< n {
								line^[i] = line^[i + ch_sz]
							}
							resize(line, n)
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
					} else {
						if input_window.cursor.x > 0 {
							input_window.cursor.x -= 1
						} else if input_window.cursor.y > 0 {
							input_window.cursor.y -= 1
						}
					}
				case sdl.K_DELETE:
					if input_window.cursor.y < len(input_window.text) {
						line := &input_window.text[input_window.cursor.y]
						if input_window.cursor.x < len(line^) {
							_, ch_sz := utf8.decode_rune(line^[input_window.cursor.x:])
							n := len(line^) - ch_sz
							for i in input_window.cursor.x ..< n {
								line^[i] = line^[i + ch_sz]
							}
							resize(line, n)
							text_updated = true
						} else if input_window.cursor.y + 1 < len(input_window.text) {
							next_line := input_window.text[input_window.cursor.y + 1]
							n := len(line^)
							reserve(line, input_window.cursor.x + len(next_line))
							resize(line, input_window.cursor.x)
							for i in n ..< input_window.cursor.x {
								line^[i] = ' '
							}
							append(line, ..next_line[:])
							delete(next_line)
							ordered_remove(&input_window.text, input_window.cursor.y + 1)
							text_updated = true
						}
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

