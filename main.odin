package main

import "core:unicode/utf8"
import rl "vendor:raylib"

Cursor :: struct {
	row: int,
	col: int,
}

draw_cursor :: proc(font: rl.Font, pos: [2]f32, padding: int, font_size: f32) {
	scale := font_size / f32(font.baseSize)
	space_idx := rl.GetGlyphIndex(font, ' ')
	step_x := f32(font.glyphs[space_idx].advanceX)
	if step_x == 0 do step_x = font.recs[space_idx].width
	rec := rl.Rectangle {
		x      = pos.x + f32(padding) * (step_x * scale + scale + 3) - 1,
		y      = pos.y - 1,
		width  = 2,
		height = font_size + 2,
	}
	rl.DrawRectangleRec(rec, rl.BLACK)
}

draw_text_and_cursor :: proc(text: [dynamic][dynamic]u8, cursor: Cursor) {
	font := rl.GetFontDefault()
	offset: [2]f32
	TOPLEFT :: 30
	FONT_SIZE :: 30

	scale := FONT_SIZE / f32(font.baseSize)
	step_y := f32(FONT_SIZE + 2)

	for line, row in text {
		for col := 0; col < len(line); {
			ch, ch_sz := utf8.decode_rune(line[col:])
			defer col += ch_sz
			if row == cursor.row && col == cursor.col {
				draw_cursor(font, TOPLEFT + offset, 0, FONT_SIZE)
			}

			ch_idx := rl.GetGlyphIndex(font, ch)
			offset.x += 3
			if ch != ' ' && ch != '\t' {
				rl.DrawTextCodepoint(font, ch, TOPLEFT + offset, FONT_SIZE, rl.BLACK)
			}
			step := f32(font.glyphs[ch_idx].advanceX)
			if step == 0 do step = font.recs[ch_idx].width
			offset.x += step * scale + scale
		}
		if row == cursor.row && len(line) <= cursor.col {
			draw_cursor(font, TOPLEFT + offset, cursor.col - len(line), FONT_SIZE)
		}

		offset.x = 0
		offset.y += step_y
	}
	if len(text) <= cursor.row {
		pos: [2]f32
		pos += TOPLEFT
		pos.y += f32(cursor.row) * step_y
		draw_cursor(font, pos, cursor.col, FONT_SIZE)
	}
}

main :: proc() {
	rl.InitWindow(1280, 720, "Main window")
	defer rl.CloseWindow()

	cursor: Cursor
	main_text := make([dynamic][dynamic]u8)
	defer {
		for row in main_text {
			delete(row)
		}
		delete(main_text)
	}
	append(&main_text, make([dynamic]u8))
	append(&main_text[0], "Hello, world!")

	for !rl.WindowShouldClose() {
		read_char := false
		for {
			ch := rl.GetCharPressed()
			if ch == 0 do break
			read_char = true
			for len(main_text) <= cursor.row {
				append(&main_text, make([dynamic]u8))
			}
			line := &main_text[cursor.row]
			for len(line^) < cursor.col {
				append(line, ' ')
			}
			ch_arr, ch_sz := utf8.encode_rune(ch)
			n := len(line^)
			resize(line, n + ch_sz)
			for i := n - 1; i >= cursor.col; i -= 1 {
				line^[i + ch_sz] = line^[i]
			}
			for i in 0 ..< ch_sz {
				line^[cursor.col + i] = ch_arr[i]
			}
			cursor.col += ch_sz
		}
		key_loop: for !read_char {
			if read_char do break
			key := rl.GetKeyPressed()
			#partial switch key {
			case .KEY_NULL:
				break key_loop
			case .LEFT:
				cursor.col = max(cursor.col - 1, 0)
			case .RIGHT:
				cursor.col += 1
			case .UP:
				cursor.row = max(cursor.row - 1, 0)
			case .DOWN:
				cursor.row += 1
			case .HOME:
				cursor.col = 0
			case .END:
				if cursor.row < len(main_text) {
					cursor.col = len(main_text[cursor.row])
				} else {
					cursor.col = 0
				}
			case .ENTER:
				if cursor.row < len(main_text) {
					line := &main_text[cursor.row]
					to_retain := min(cursor.col, len(line^))
					to_move := max(len(line^) - cursor.col, 0)
					new_line := make([dynamic]u8, to_move)
					for i in 0 ..< to_move {
						new_line[i] = line[to_retain + i]
					}
					resize(line, to_retain)
					inject_at(&main_text, cursor.row + 1, new_line)
				}
				cursor.row += 1
				cursor.col = 0
			case .BACKSPACE:
				if cursor.row < len(main_text) && cursor.col <= len(main_text[cursor.row]) {
					line := &main_text[cursor.row]
					if cursor.col > 0 {
						_, ch_sz := utf8.decode_last_rune(line^[:cursor.col])
						cursor.col -= ch_sz
						n := len(line^) - ch_sz
						for i in cursor.col ..< n {
							line^[i] = line^[i + ch_sz]
						}
						resize(line, n)
					} else if cursor.row > 0 {
						cursor.row -= 1
						prev_line := &main_text[cursor.row]
						cursor.col = len(prev_line^)
						resize(prev_line, cursor.col + len(line^))
						for b, i in line {
							prev_line^[cursor.col + i] = b
						}
						delete(line^)
						ordered_remove(&main_text, cursor.row + 1)
					}
				} else {
					if cursor.col > 0 {
						cursor.col -= 1
					} else if cursor.row > 0 {
						cursor.row -= 1
					}
				}
			case .DELETE:
				if cursor.row < len(main_text) {
					line := &main_text[cursor.row]
					if cursor.col < len(line^) {
						_, ch_sz := utf8.decode_rune(line^[cursor.col:])
						n := len(line^) - ch_sz
						for i in cursor.col ..< n {
							line^[i] = line^[i + ch_sz]
						}
						resize(line, n)
					} else if cursor.row + 1 < len(main_text) {
						next_line := main_text[cursor.row + 1]
						n := len(line^)
						resize(line, cursor.col + len(next_line))
						for i in n ..< cursor.col {
							line^[i] = ' '
						}
						for b, i in next_line {
							line^[cursor.col + i] = b
						}
						delete(next_line)
						ordered_remove(&main_text, cursor.row + 1)
					}
				}
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)
		draw_text_and_cursor(main_text, cursor)
		rl.EndDrawing()
	}
}

