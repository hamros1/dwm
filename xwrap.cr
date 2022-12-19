module XWrap
    @@display

    def configure_window(window, value_mask, values)
        LibX11.x_configure_window(@@display, window, value_mask, values)
    end

    def sync(discard)
        x_sync(@@display, discard)
    end

    def get_class_hint(window)
        x_get_class_hint(@@display, window, out class_hints_return)

        class_hints_return
    end
end