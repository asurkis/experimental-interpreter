package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

Text :: [dynamic][dynamic]byte

renderer: ^sdl.Renderer

draw_cursor :: proc(pos: [2]f32, padding: int) {
	rect := sdl.FRect {
		x = pos.x + f32(padding) * 8 - 1,
		y = pos.y - 1,
		w = 2,
		h = 10,
	}
	sdl.RenderRect(renderer, &rect)
}

draw_text_and_cursor :: proc(text: Text, cursor: [2]int) {
	TOPLEFT :: 8
	offset: [2]f32

	for line, row in text {
		for col := 0; col < len(line); {
			ch, ch_sz := utf8.decode_rune(line[col:])
			defer col += ch_sz
			if row == cursor.y && col == cursor.x {
				draw_cursor(TOPLEFT + offset, 0)
			}

			if ch != ' ' && ch != '\t' {
				ch0: [5]byte
				for i in 0 ..< ch_sz {
					ch0[i] = line[col + i]
				}
				ch_cstr := cast(cstring)cast([^]byte)raw_data(ch0[:])
				xy := TOPLEFT + offset
				sdl.RenderDebugText(renderer, xy.x, xy.y, ch_cstr)
			}
			offset.x += 8
		}
		if row == cursor.y && len(line) <= cursor.x {
			draw_cursor(TOPLEFT + offset, cursor.x - len(line))
		}

		offset.x = 0
		offset.y += 8
	}
	if len(text) <= cursor.y {
		pos: [2]f32
		pos += TOPLEFT
		pos.y += f32(cursor.y) * 8
		draw_cursor(pos, cursor.x)
	}
}

is_space :: proc "contextless" (ch: rune) -> bool {
	return ch == ' ' || ch == '\t' || ch == '\n'
}

is_delimiter :: proc "contextless" (ch: rune) -> bool {
	return is_space(ch) || ch == '(' || ch == ')'
}

next_rune :: proc "contextless" (text: Text, cursor: [2]int) -> ([2]int, rune) {
	if cursor.y >= len(text) do return cursor, -1
	if cursor.x >= len(text[cursor.y]) do return {0, cursor.y + 1}, '\n'
	ch, ch_sz := utf8.decode_rune(text[cursor.y][cursor.x:])
	return {cursor.x + ch_sz, cursor.y}, ch
}

skip_spaces :: proc "contextless" (text: Text, cursor: [2]int) -> [2]int {
	cursor := cursor
	for {
		cursor1, ch := next_rune(text, cursor)
		if !is_space(ch) do break
		cursor = cursor1
	}
	return cursor
}

next_word :: proc(text: Text, cursor: [2]int) -> (out_cursor: [2]int, out: string) {
	out_cursor = cursor
	for {
		cursor1, ch := next_rune(text, out_cursor)
		if ch == -1 || is_delimiter(ch) do break
		out_cursor = cursor1
	}
	assert(cursor.y == out_cursor.y)
	if cursor.x == out_cursor.x {
		out = ""
	} else {
		out = string(text[cursor.y][cursor.x:out_cursor.x])
	}
	return
}

read_uint :: proc "contextless" (
	text: Text,
	cursor: [2]int,
) -> (
	out_cursor: [2]int,
	out: i64,
	ok: bool,
) {
	out_cursor = cursor
	for {
		cursor1, ch := next_rune(text, out_cursor)
		if '0' > ch || ch > '9' do break
		out_cursor = cursor1
		out = 10 * out + i64(ch - '0')
		ok = true
	}
	return
}

interpret_array :: proc(
	err_log: ^strings.Builder,
	text: Text,
	cursor: [2]int,
) -> (
	out_cursor: [2]int,
	out: i64,
	out_ok: bool,
) {
	cursor1, ch1 := next_rune(text, cursor)
	assert(ch1 == '(')
	out_cursor = cursor1
	operation: rune
	is_first := true
	out_ok = true
	for {
		cursor2 := skip_spaces(text, out_cursor)
		cursor3, ch3 := next_rune(text, cursor2)
		if ch3 == -1 {
			fmt.sbprintln(err_log, "Unexpected EOF at", cursor3.y + 1, ":", cursor3.x + 1)
			fmt.sbprintln(err_log, "Unbalanced ( at", cursor.y + 1, ":", cursor.x + 1)
			return cursor3, 0, false
		} else if ch3 == ')' {
			if operation == 0 {
				fmt.sbprintln(
					err_log,
					"Empty arrays are not supported at",
					cursor.y + 1,
					":",
					cursor.x + 1,
				)
				return cursor3, 0, false
			} else {
				return cursor3, out, out_ok
			}
		} else if operation == 0 {
			if ch3 == '(' {
				fmt.sbprintln(
					err_log,
					"Array operators are not supported at",
					cursor2.y + 1,
					":",
					cursor2.x + 1,
				)
				return cursor2, 0, false
			} else {
				cursor4, word := next_word(text, cursor2)
				out_cursor = cursor4
				switch word {
				case "":
					fmt.sbprintln(
						err_log,
						"Operator must be a word at",
						cursor2.y + 1,
						":",
						cursor2.x + 1,
					)
					out_ok = false
				case "+":
					operation = '+'
				case "-":
					operation = '-'
				case "*":
					operation = '*'
				case "/":
					operation = '/'
				case:
					fmt.sbprintln(
						err_log,
						"Unknown operator",
						word,
						"at",
						cursor2.y + 1,
						":",
						cursor2.x + 1,
					)
					out_ok = false
				}
			}
		} else {
			cursor4, x, ok := interpret(err_log, text, cursor2)
			out_cursor = cursor4
			out_ok &= ok
			if out_ok {
				if is_first {
					out = x
					is_first = false
				} else do switch operation {
				case '+':
					out = out + x
				case '-':
					out = out - x
				case '*':
					out = out * x
				case '/':
					out = out / x
				}
			}
		}
	}
}

interpret :: proc(
	err_log: ^strings.Builder,
	text: Text,
	cursor: [2]int,
) -> (
	out_cursor: [2]int,
	out: i64,
	out_ok: bool,
) {
	cursor1 := skip_spaces(text, cursor)
	_, ch := next_rune(text, cursor)
	switch ch {
	case -1:
		fmt.sbprintln(err_log, "Unexpected EOF")
	case '(':
		return interpret_array(err_log, text, cursor1)
	case ')':
		fmt.sbprintln(err_log, "Unbalanced ) at", cursor1.y + 1, ":", cursor1.x + 1)
		out_cursor = cursor1
	case:
		cursor2, word := next_word(text, cursor1)
		out_cursor, out, out_ok = cursor2, strconv.parse_i64(word)
		if !out_ok {
			fmt.sbprintln(
				err_log,
				"Could not parse as integer:",
				word,
				"at",
				cursor1.y + 1,
				":",
				cursor1.x + 1,
			)
		}
	}
	return
}

main :: proc() {
	ok: bool
	ok = sdl.Init(sdl.INIT_EVENTS | sdl.INIT_VIDEO)
	assert(ok)
	window := sdl.CreateWindow("Main window", 1280, 720, {})
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ok = sdl.StartTextInput(window)
	assert(ok)
	renderer = sdl.CreateRenderer(window, nil)
	assert(renderer != nil)
	defer sdl.DestroyRenderer(renderer)

	cursor: [2]int
	main_text: Text
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
		for row in main_text {
			delete(row)
		}
		delete(main_text)
	}
	append(&main_text, make([dynamic]byte))
	append(&main_text[0], "(+ 1 1)")

	main_loop: for {
		ok = sdl.WaitEvent(nil)
		assert(ok)
		for evt: sdl.Event; sdl.PollEvent(&evt); {
			#partial switch evt.type {
			case .QUIT:
				break main_loop
			case .TEXT_INPUT:
				if len(main_text) <= cursor.y {
					resize(&main_text, cursor.y + 1)
				}
				line := &main_text[cursor.y]
				for len(line^) < cursor.x {
					append(line, ' ')
				}
				str := transmute([]byte)cast(string)evt.text.text
				inject_at(line, cursor.x, ..str)
				cursor.x += len(str)
				text_updated = true
			case .KEY_DOWN:
				switch evt.key.key {
				case sdl.K_ESCAPE:
					break main_loop
				case sdl.K_LEFT:
					cursor.x = max(cursor.x - 1, 0)
				case sdl.K_RIGHT:
					cursor.x += 1
				case sdl.K_UP:
					cursor.y = max(cursor.y - 1, 0)
				case sdl.K_DOWN:
					cursor.y += 1
				case sdl.K_HOME:
					cursor.x = 0
				case sdl.K_END:
					if cursor.y < len(main_text) {
						cursor.x = len(main_text[cursor.y])
					} else {
						cursor.x = 0
					}
				case sdl.K_RETURN:
					if cursor.y < len(main_text) {
						line := &main_text[cursor.y]
						to_retain := min(cursor.x, len(line^))
						to_move := max(len(line^) - cursor.x, 0)
						new_line := make([dynamic]byte, 0, to_move)
						append(&new_line, ..line^[to_retain:])
						resize(line, to_retain)
						inject_at(&main_text, cursor.y + 1, new_line)
						text_updated = true
					}
					cursor.y += 1
					cursor.x = 0
				case sdl.K_BACKSPACE:
					if cursor.y < len(main_text) && cursor.x <= len(main_text[cursor.y]) {
						line := &main_text[cursor.y]
						if cursor.x > 0 {
							_, ch_sz := utf8.decode_last_rune(line^[:cursor.x])
							cursor.x -= ch_sz
							n := len(line^) - ch_sz
							for i in cursor.x ..< n {
								line^[i] = line^[i + ch_sz]
							}
							resize(line, n)
							text_updated = true
						} else if cursor.y > 0 {
							cursor.y -= 1
							prev_line := &main_text[cursor.y]
							cursor.x = len(prev_line^)
							append(prev_line, ..line^[:])
							delete(line^)
							ordered_remove(&main_text, cursor.y + 1)
							text_updated = true
						}
					} else {
						if cursor.x > 0 {
							cursor.x -= 1
						} else if cursor.y > 0 {
							cursor.y -= 1
						}
					}
				case sdl.K_DELETE:
					if cursor.y < len(main_text) {
						line := &main_text[cursor.y]
						if cursor.x < len(line^) {
							_, ch_sz := utf8.decode_rune(line^[cursor.x:])
							n := len(line^) - ch_sz
							for i in cursor.x ..< n {
								line^[i] = line^[i + ch_sz]
							}
							resize(line, n)
							text_updated = true
						} else if cursor.y + 1 < len(main_text) {
							next_line := main_text[cursor.y + 1]
							n := len(line^)
							reserve(line, cursor.x + len(next_line))
							resize(line, cursor.x)
							for i in n ..< cursor.x {
								line^[i] = ' '
							}
							append(line, ..next_line[:])
							delete(next_line)
							ordered_remove(&main_text, cursor.y + 1)
							text_updated = true
						}
					}
				}
			}
		}

		if text_updated {
			strings.builder_reset(&err_log)
			_, new_result, ok := interpret(&err_log, main_text, 0)
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
		draw_text_and_cursor(main_text, cursor)

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

