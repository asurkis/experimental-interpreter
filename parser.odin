package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

VAtom :: string

VArray :: [dynamic]VTree

VLiteral :: union {
	i64,
}

VTree :: union {
	VAtom,
	VArray,
	VLiteral,
}

delete_vatom :: proc(v: VAtom) {
	delete(v)
}

delete_varray :: proc(v: VArray) {
	for it in v do delete_vtree(it)
	delete(v)
}

delete_vliteral :: proc(literal: VLiteral) {
	switch v in literal {
	case i64:
	}
}

delete_vtree :: proc(tree: VTree) {
	switch v in tree {
	case VAtom:
		delete_vatom(v)
	case VArray:
		delete_varray(v)
	case VLiteral:
		delete_vliteral(v)
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
	return {cursor.x + 1, cursor.y}, text[cursor.y][cursor.x]
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
	sbuf := make([dynamic]byte)
	for ch in text[cursor.y][cursor.x:out_cursor.x] {
		buf, sz := utf8.encode_rune(ch)
		for i in 0 ..< sz do append(&sbuf, buf[i])
	}
	out = transmute(string)sbuf[:]
	return
}

parse_varray :: proc(
	err_log: ^strings.Builder,
	text: Text,
	cursor: [2]int,
) -> (
	out_cursor: [2]int,
	out: VArray,
	out_ok: bool,
) {
	cursor1, ch1 := next_rune(text, cursor)
	out = make([dynamic]VTree)
	assert(ch1 == '(')
	for {
		cursor2 := skip_spaces(text, cursor1)
		cursor3, ch3 := next_rune(text, cursor2)
		switch ch3 {
		case -1:
			fmt.sbprintln(err_log, "Unexpected EOF at", cursor3.y + 1, ":", cursor3.x + 1)
			fmt.sbprintln(err_log, "Unbalanced ( at", cursor.y + 1, ":", cursor.x + 1)
			delete_varray(out)
			return cursor3, {}, false
		case ')':
			return cursor3, out, true
		case:
			cursor4, item, item_ok := parse_vtree(err_log, text, cursor2)
			if !item_ok {
				delete_varray(out)
				return cursor4, {}, false
			}
			append(&out, item)
		}
	}
}

parse_vtree :: proc(
	err_log: ^strings.Builder,
	text: Text,
	cursor: [2]int,
) -> (
	out_cursor: [2]int,
	out: VTree,
	out_ok: bool,
) {
	cursor1 := skip_spaces(text, cursor)
	cursor2, ch2 := next_rune(text, cursor1)
	switch ch2 {
	case -1:
		fmt.sbprintln(err_log, "Unexpected EOF at", cursor2.y + 1, ":", cursor2.x + 1)
		return cursor2, {}, false
	case '(':
		return parse_varray(err_log, text, cursor2)
	case:
		cursor3, word := next_word(text, cursor2)
		as_int, as_int_ok := strconv.parse_i64(word)
		if as_int_ok {
			delete(word)
			return cursor3, VLiteral(as_int), true
		} else {
			return cursor3, VAtom(word), true
		}
	}
}

