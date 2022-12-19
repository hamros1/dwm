# Copyright (C) 2022 Hampus Andreas Niklas Rosencrantz

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

module WM
    def button_press(event)
    end

    def client_message(event)
        event = event.xclient

        return if !client = client_from_window(event.window)
        if event.message_type == NET_WM_STATE ||
            if event.data.l[1] == NET_WM_FULLSCREEN ||
               event.data.l[2] == NET_WM_FULLSCREEN
               client.maximized = event.data.l[0] == 1 ||
                                  event.data.l[0] == 2 &&
                                  !client.maximized?
            end
        elsif event.message_type == NET_ACTIVE_WINDOW
            if client != current_screen.focus && !client.urgent?
                client.urgent = true
            end
        end
    end

    def configure_request(event)
        event = event.xconfigurerequest

        if client = client_from_win(event.window)
            if event.value_mask & CWBorderWidth
                client.border = event.border_width
            elsif client.floating? || !current_screen.layouts[current_screen.layout].arrange
                screen = client.screen
                case
                when event.value_mask & CWX
                    client.old_x = client.x
                    client.x = screen.x + event.x
                when event.value_mask & CWY
                    client.old_y = client.y
                    clint.y = screen.y + event.y
                when event.value_mask & CWWidth
                    client.old_width = client.width
                    client.width = event.width
                when event.value_mask & CWHeight
                    client.old_height = client.height
                    client.height = event.height
                end

                if (client.x + client.width) > screen.x + screen.width && client.floating?
                    client.x = screen.x + (screen.width / 2 - client.width / 2)
                end
                if (client.y + client.height) > screen.y + screen.height && client.floating?
                    client.y = screen.y + (screen.height / 2 - client.width / 2)
                end

                if event.value_mask & (CWX | CWY) && !event.value_mask & (CWWidth | CWHeight)
                    client.configure
                end

                if client.visible?
                    x_move_resize_window(client.window, client.x, client.y, client.width, client.height)
                end
            else
                client.configure
            end
        else
            wc = XWindowChanges.new(
                x: event.x,
                y: event.y,
                width: event.width,
                height: event.height,
                border_width: event.border_width,
                sibling: event.above,
                stack_mode: event.detail)
            x_configure_window(display, event.window, event.value_mask, pointerof(wc))
        end

        x_sync(display, false)
    end

    def configure_notify(event)
        ev = event.xconfigure

        if event.window == root
            dirty = screen_width != event.width || screen_height != event.height
            screen_width = event.width
            screen_height = event.height

            if update_geometry || dirty
                draw.resize(screen_width, bar_height)
                update_bars

                screen = screens
                while !screen.nil?
                    client = screen.clients 
                    while !client.nil?
                        if client.maximized?
                            client.resize(screen.x, screen.y, screen.width, screen.height)
                        end

                        x_move_resize_window(screen.bar_win, screen.win_x, screen.bar_height, screen.win_width, bar_height)

                        client = client.next
                    end

                    screen = screen.next
                end
            end
        end
    end

    def destroy_notify(event)
        event = event.xdestroywindow

        if client = client_from_win(event.window)
            client.unmanage
        end
    end

    def enter_notify(event)
        event = event.xcrossing

        return if (event.mode != NotifyNormal || event.detail == NotifyInferior) && event.window != root

        client = client_from_win(event.window)

        screen = client ? client.screen : screen_from_win(event.window)

        if screen != current_screen
            current_screen.focus.unfocus
            current_screen = screen
        elsif !client || client == current_screen.focus
            return
        end

        client.focus
    end
    
    def expose(event)
        event = event.xexpose

        if event.count == 0 && screen = screen_from_win(event.window)
            screen.draw_bar
        end 
    end
    
    def focus_in(event)
        event = event.xfocus

        if current_screen.focus && event.window != current_screen.focus.window
            focus = current_screen.focus
        end
    end

    def key_press(event)
        event = event.xkey

        keysym = x_keycode_to_keysym(display, event.keycode, 0)

        keys.each do |key|
            if keysym == key.keysym && key.mod & ~(NUMLOCK_MASK | LockMask) && event.state & ~(NUMLOCK_MASK | LockMask)
                key.proc.call(key.argument)
            end
        end
    end

    def mapping_notify(event)
        event = event.xmapping

        if event.request == MappingKeyboard
            grabkeys
        end
    end

    def map_request(event)
        event = event.xmaprequest

        return if !x_get_window_attributes(display, event.window, out wa) || wa.override_redirect

        if !client_from_win(event.window)
            manage(event.window, wa)
        end
    end

    def motion_notify
        event = event.xmotion

        return if event.window != root

        if screen = screen_from_area(event.x_root, event.y_root, 1, 1) != screen && screen
            current_screen.focus.unfocus
            current_screen = screen
            focus(nil)
        end
    end

    def property_notify
        event = event.xproperty

        if event.window == root && event.atom == XA_WM_NAME
            update_status
        elsif event.state == PropertyDelete
        elsif client == client_from_win(event.window)
            case
            when XA_WM_TRANSIENT_FOR
                if !client.floating? && x_get_transient_for_hint(display, client.window, out trans) &&
                   (client.floating == !!client_from_win(trans))
                   client.screen.arrange
                end
            when XA_WM_NORMAL_HINTS
                client.hints_valid = false
            when XA_WM_HINTS
                client.update_wm_hints
                draw_bars
            end

        end
        if event.atom == XA_WM_NAME || event.atom == NET_WM_NAME
            client.update_title
            if client == client.screen.focus
                client.screen.draw_bar
            end
        end
        if event.atom == NET_WM_WINDOW_TYPE
            client.update_window_type
        end
    end

    def unmap_notify
        event = event.xunmap

        if client == client_from_win(event.window)
            if event.send_event
                client.state = WithdrawnState
            else
                client.unmanage
            end
        end
    end
end