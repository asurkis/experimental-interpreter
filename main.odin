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

	window_in: InputWindow
	window_out: OutputWindow
	window_err: OutputWindow
	window_in.pos.xy = 16
	window_in.pos.zw = 336
	window_out.pos.x = 352
	window_out.pos.y = 16
	window_out.pos.z = 672
	window_out.pos.w = 48
	window_err.pos.x = 352
	window_err.pos.y = 64
	window_err.pos.z = 672
	window_err.pos.w = 368
	last_ok: bool
	text_updated := true

	out_buf: [4096]byte
	out_log := strings.builder_from_bytes(out_buf[:])

	err_log: strings.Builder
	strings.builder_init(&err_log)
	defer strings.builder_destroy(&err_log)

	defer {
		for row in window_in.text do delete(row)
		delete(window_in.text)
	}
	append(&window_in.text, make([dynamic]rune))
	for ch in "(+ 1 1)" do append(&window_in.text[0], ch)

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
			consumed1, updated := on_event_input_window(&window_in, evt)
			consumed2 := consumed1 || on_event_window(&window_out, evt)
			if !consumed2 do on_event_window(&window_err, evt)
			text_updated |= updated
		}

		if text_updated {
			new_result: i64
			strings.builder_reset(&err_log)
			_, new_result, ok = interpret(&err_log, window_in.text, 0)
			if ok {
				strings.builder_reset(&out_log)
				fmt.sbprint(&out_log, new_result)
				window_out.text = strings.to_string(out_log)
				fmt.sbprint(&err_log, "Everything OK")
			}
			window_err.text = strings.to_string(err_log)
			last_ok = ok
			text_updated = false
		}

		sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
		sdl.RenderClear(renderer)
		// sdl.SetRenderScale(renderer, 2, 2)
		sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
		draw_input_window(window_in)

		if last_ok {
			sdl.SetRenderDrawColor(renderer, 0, 191, 0, 255)
		} else {
			sdl.SetRenderDrawColor(renderer, 191, 191, 191, 255)
		}
		draw_output_window(window_out)
		if last_ok {
			sdl.SetRenderDrawColor(renderer, 191, 191, 191, 255)
		} else {
			sdl.SetRenderDrawColor(renderer, 191, 0, 0, 255)
		}
		draw_output_window(window_err)
		sdl.RenderPresent(renderer)
	}
}

