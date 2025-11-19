package main

import "core:math"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

WINDOW_PADDING :: 8
WINDOW_HEADER :: 16
GRID_SIZE :: 16

Window :: struct {
	pos:        [4]f32,
	pos_start:  [4]f32,
	drag_start: [2]f32,
	ctrl_down:  bool,
	dragging:   u8,
}

InputWindow :: struct {
	using window: Window,
	text:         Text,
	cursor:       [2]int,
}

OutputWindow :: struct {
	using window: Window,
	text:         string,
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
		rect.x = ((i & 1) == 0) ? w.pos.x : w.pos.z - WINDOW_PADDING
		rect.y = ((i & 2) == 0) ? w.pos.y : w.pos.w - WINDOW_PADDING
		sdl.RenderFillRect(renderer, &rect)
	}
	rect.y = w.pos.y + WINDOW_PADDING
	rect.w = WINDOW_PADDING
	rect.h = w.pos.w - w.pos.y - 2 * WINDOW_PADDING
	rect.x = w.pos.x
	sdl.RenderFillRect(renderer, &rect)
	rect.x = w.pos.z - WINDOW_PADDING
	sdl.RenderFillRect(renderer, &rect)

	rect.x = w.pos.x + WINDOW_PADDING
	rect.w = w.pos.z - w.pos.x - 2 * WINDOW_PADDING
	rect.h = WINDOW_PADDING
	rect.y = w.pos.y
	sdl.RenderFillRect(renderer, &rect)
	rect.y = w.pos.w - WINDOW_PADDING
	sdl.RenderFillRect(renderer, &rect)

	sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
	rect.x = w.pos.x + WINDOW_PADDING
	rect.y = w.pos.y + WINDOW_PADDING
	rect.w = w.pos.z - w.pos.x - 2 * WINDOW_PADDING
	rect.h = w.pos.w - w.pos.y - 2 * WINDOW_PADDING
	sdl.RenderFillRect(renderer, &rect)
}

set_window_clip_rect :: proc(w: Window) {
	clip_rect: sdl.Rect
	clip_rect.x = i32(w.pos.x + WINDOW_PADDING)
	clip_rect.y = i32(w.pos.y + WINDOW_PADDING)
	clip_rect.w = i32(w.pos.z - w.pos.x - 2 * WINDOW_PADDING)
	clip_rect.h = i32(w.pos.w - w.pos.y - 2 * WINDOW_PADDING)
	sdl.SetRenderClipRect(renderer, &clip_rect)
}

draw_rune :: proc(pos: [2]f32, ch: rune) {
	if ch == ' ' || ch == '\t' do return
	ch0: [5]byte
	ch1, _ := utf8.encode_rune(ch)
	for i in 0 ..< 4 do ch0[i] = ch1[i]
	ch_cstr := cstring(raw_data(ch0[:]))
	sdl.RenderDebugText(renderer, pos.x, pos.y, ch_cstr)
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
	og_clip_rect: sdl.Rect
	og_clip_rect_ptr: ^sdl.Rect
	if sdl.RenderClipEnabled(renderer) {
		og_clip_rect_ptr = &og_clip_rect
		sdl.GetRenderClipRect(renderer, og_clip_rect_ptr)
	}
	defer sdl.SetRenderClipRect(renderer, og_clip_rect_ptr)
	set_window_clip_rect(w)

	topleft := w.pos.xy + WINDOW_PADDING + 4
	// botright := w.pos.zw - WINDOW_PADDING
	offset: [2]f32
	for line, row in w.text {
		for ch, col in line {
			if row == w.cursor.y && col == w.cursor.x {
				draw_cursor(topleft + offset, 0)
			}
			draw_rune(topleft + offset, ch)
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

draw_output_window :: proc(w: OutputWindow) {
	draw_window_frame(w)
	og_clip_rect: sdl.Rect
	og_clip_rect_ptr: ^sdl.Rect
	if sdl.RenderClipEnabled(renderer) {
		og_clip_rect_ptr = &og_clip_rect
		sdl.GetRenderClipRect(renderer, og_clip_rect_ptr)
	}
	defer sdl.SetRenderClipRect(renderer, og_clip_rect_ptr)
	set_window_clip_rect(w)

	topleft := w.pos.xy + WINDOW_PADDING + 4
	// botright := w.pos.zw - WINDOW_PADDING
	offset: [2]f32
	for ch in w.text {
		if ch == '\n' {
			offset.x = 0
			offset.y += 8
			continue
		}
		draw_rune(topleft + offset, ch)
		offset.x += 8
	}
}

on_event_window :: proc(w: ^Window, evt: sdl.Event) -> (consumed: bool) {
	#partial switch evt.type {
	case .MOUSE_BUTTON_DOWN:
		if evt.button.button != sdl.BUTTON_LEFT do break
		if w.pos.x > evt.button.x || evt.button.x > w.pos.z do break
		if w.pos.y > evt.button.y || evt.button.y > w.pos.w do break

		consumed = true
		w.dragging = 0
		if evt.button.x <= w.pos.x + WINDOW_PADDING do w.dragging |= 1
		if evt.button.y <= w.pos.y + WINDOW_PADDING do w.dragging |= 2
		if evt.button.x >= w.pos.z - WINDOW_PADDING do w.dragging |= 4
		if evt.button.y >= w.pos.w - WINDOW_PADDING do w.dragging |= 8
		if w.dragging == 0 do w.dragging = 15
		w.pos_start = w.pos
		w.drag_start.x = evt.button.x
		w.drag_start.y = evt.button.y

	case .MOUSE_BUTTON_UP:
		if evt.button.button != sdl.BUTTON_LEFT do break
		if w.dragging == 0 do break
		consumed = true
		w.dragging = 0

	case .KEY_DOWN:
		if evt.key.key == sdl.K_LCTRL do w.ctrl_down = true

	case .KEY_UP:
		if evt.key.key == sdl.K_LCTRL do w.ctrl_down = false

	case .MOUSE_MOTION:
		if w.dragging == 0 do break
		consumed = true
		mouse_pos := [2]f32{evt.motion.x, evt.motion.y}
		for i in 0 ..< uint(4) {
			if w.dragging & (1 << i) == 0 do continue
			w.pos[i] = w.pos_start[i] + mouse_pos[i & 1] - w.drag_start[i & 1]
			if w.ctrl_down do w.pos[i] = math.round(w.pos[i] / GRID_SIZE) * GRID_SIZE
			if i < 2 {
				w.pos[i] = min(w.pos[i + 2] - 2 * WINDOW_PADDING, w.pos[i])
			} else {
				w.pos[i] = max(w.pos[i - 2] + 2 * WINDOW_PADDING, w.pos[i])
			}
		}
	}
	return
}

on_event_input_window :: proc(w: ^InputWindow, evt: sdl.Event) -> (consumed, updated: bool) {
	consumed |= on_event_window(w, evt)
	if consumed do return
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

