package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

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

