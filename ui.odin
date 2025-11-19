package main

import "core:unicode/utf8"
import sdl "vendor:sdl3"

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

handle_event_input_window :: proc(w: ^InputWindow, evt: sdl.Event) -> (updated: bool) {
	#partial switch evt.type {
	case .TEXT_INPUT:
		if len(w.text) <= w.cursor.y {
			resize(&w.text, w.cursor.y + 1)
		}
		line := &w.text[w.cursor.y]
		for len(line^) < w.cursor.x do append(line, ' ')
		str := string(evt.text.text)
		rune_count := utf8.rune_count(str)
		n := len(line)
		resize(line, n + rune_count)
		for i := n - 1; i >= w.cursor.x; i -= 1 {
			line[i + rune_count] = line[i]
		}
		for ch in str {
			line[w.cursor.x] = ch
			w.cursor.x += 1
		}
		updated = true
	case .KEY_DOWN:
		switch evt.key.key {
		case sdl.K_LEFT:
			w.cursor.x = max(w.cursor.x - 1, 0)
		case sdl.K_RIGHT:
			w.cursor.x += 1
		case sdl.K_UP:
			w.cursor.y = max(w.cursor.y - 1, 0)
		case sdl.K_DOWN:
			w.cursor.y += 1
		case sdl.K_HOME:
			w.cursor.x = 0
		case sdl.K_END:
			w.cursor.x = line_len(w.text, w.cursor.y)
		case sdl.K_RETURN:
			line := ptr_at(w.text[:], w.cursor.y)
			if line != nil {
				to_retain := min(w.cursor.x, len(line^))
				to_move := max(len(line^) - w.cursor.x, 0)
				new_line := make([dynamic]rune, 0, to_move)
				append(&new_line, ..line^[to_retain:])
				resize(line, to_retain)
				inject_at(&w.text, w.cursor.y + 1, new_line)
				updated = true
			}
			w.cursor.y += 1
			w.cursor.x = 0
		case sdl.K_BACKSPACE:
			if w.cursor.x > line_len(w.text, w.cursor.y) {
				w.cursor.x -= 1
				break
			}
			if w.cursor.y >= len(w.text) {
				w.cursor.y -= 1
				w.cursor.x = line_len(w.text, w.cursor.y)
				break
			}
			line := &w.text[w.cursor.y]
			if w.cursor.x > 0 {
				ordered_remove(line, w.cursor.x - 1)
				w.cursor.x -= 1
				updated = true
			} else if w.cursor.y > 0 {
				w.cursor.y -= 1
				prev_line := &w.text[w.cursor.y]
				w.cursor.x = len(prev_line^)
				append(prev_line, ..line^[:])
				delete(line^)
				ordered_remove(&w.text, w.cursor.y + 1)
				updated = true
			}
		case sdl.K_DELETE:
			line := ptr_at(w.text[:], w.cursor.y)
			(line != nil) or_break
			if w.cursor.x < len(line^) {
				ordered_remove(line, w.cursor.x)
				updated = true
			} else if w.cursor.y + 1 < len(w.text) {
				next_line := w.text[w.cursor.y + 1]
				n := len(line^)
				reserve(line, w.cursor.x + len(next_line))
				resize(line, w.cursor.x)
				for i in n ..< w.cursor.x do line^[i] = ' '
				append(line, ..next_line[:])
				delete(next_line)
				ordered_remove(&w.text, w.cursor.y + 1)
				updated = true
			}
		}
	}
	return
}

