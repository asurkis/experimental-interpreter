package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

Text :: [dynamic][dynamic]rune
renderer: ^sdl.Renderer

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
	input_window.pos.xy = 8
	input_window.pos.zw = 320
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
			case .KEY_DOWN:
				if evt.key.key == sdl.K_ESCAPE do break main_loop
			}
			_, updated := on_event_input_window(&input_window, evt)
			text_updated |= updated
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
		// sdl.SetRenderScale(renderer, 2, 2)
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

