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
    class Argument
        property i : Int32
        property ui : UInt32
        property f : Float32
        property v : Pointer(Void)
    end

    class Button
        property click : UInt32
        property mask : UInt32
        property button : UInt32
        property proc : ->(Argument, Nil)
        property argument : Argument
    end

    class Key
        property mod : UInt32
        property keysym : KeySym
        property proc : ->(Argument, Nil)
        property argument : Argument
    end

    class Layout
        property symbol : String
        property arrange : Screen
    end

    class Rule
        property "class" : String
        property instance : String
        property title : String
        property tags : UInt32
        property floating : Int32
        property scren : Int32
    end

    def focus_screen(argument)
        return if !screens.nexxt

        return if screen = screen_from_dir(argument.i) == current_screen

        current_screen.focus.unfocus

        current_screen = screen

        focus(nil)
    end

    def focus_stack(argument)
        return if !current_screen.focus || (current_screen.focus.maximized? && lock_maximized?)

        if argument.i > 0
            client = current_screen.focus.next
            while !client.nil? && !client.visible?
                if !client
                    client = current_screen.clients
                    while !client && !client.visible?
                        client = client.next
                    end
                end
                client = client.next
            end 
        else
            i = current_screen.clients
            while i != current_screen.focus
                if i.visible?
                    client = i
                end
                i = i.next
            end
            if !c
                while i 
                    if i.visible?
                        client = i
                    end
                    i = i.next
                end
            end 
        end
        if client
            client.focus
            current_screen.restack
        end
    end

    def stacked_count(argument)
        current_screen.stacked_count = Math.max(current_screen.stacked_count + argument.i, 0)
        current_screen.arrange
    end

    def kill_client(argument)
        return if !current_screen.focus

        if !current_screen.send_event(WM_DELETE)
            x_grab_server(display)
            x_set_error_handler(->x_error_dummy)
            x_set_close_down_mode(DestroyAll)
            x_kill_client(current_screen.focus.win)
            x_sync(false)
            x_set_error_handler(->x_error)
            x_ungrab_server(display)
        end
    end 

    def move_mouse(argument)
        return if !client = current_screen.focus

        return if client.maximized

        current_screen.restack

        old_x = client.x
        old_y = client.y

        return if x_grab_pointer(display, root, false, MOUSE_MASK, GrabModeAsync, GrabModeAsync, None, cursors[Cursor::Move].cursor, CurrentTime) != GrabSuccess

        loop do
            x_mask_event(display, MOUSE_MASK | ExposureMask | SubstructureRedirectMask, out event)
            case event.type
            when ConfigureRequest, Expose, MapRequest
                handler[event.type].call(event)
            when MotionNotify
                next if (event.xmotion.time - last_time) <= (1000 / 60)

                last_time = event.xmotion.time

                new_x = old_x + (event.xmotion.x - x)
                new_y = old_y + (event.xmotion.y - y)

                if (current_screen.win_x - new_x).abs < snap
                    new_x = current_scren.win_x
                elsif ((current_screen.win_x + current_screen.win_width).abs - (new_x + client.width)) < snap
                    new_x = current_screen.win_x + current_screen.win_width - client.width
                end

                if (current_screen.win_y - new_y) < snap
                    new_y = current_screen.win_y
                elsif ((current_screen.win_y + current_screen.win_height).abs - (new_y + client.height)) < snap
                    new_y = current_screen.win_y + current_screen.win_height - client.height
                end

                if !client.floating? && current_screen.layouts[current_screen.layout].arrange &&
                (new_x - client.x) > snap || (new_y - client.y).abs > snap
                floating(nil)
                end

                if !current_screen.layouts[current_screen.layout].arrange || client.floating?
                    client.resize(new_x, new_y, client.width, client.height, 1)
                end

                break
            end

            break if event.type != ButtonRelease
        end

        x_ungrab_pointer(display, CurrentTime)

        if screen = screen_from_area(client.x, client.y, client.width, client.height) != current_screen
            client.move_to_screen(screen)
            current_screen = screen
            focus(nil)
        end
    end

    def quit(argument)
        running = 0
    end

    def resize_mouse(argument)
        return if !client = current_screen.client

        return if client.maximized?

        current_screen.restack

        old_x = client.x
        old_y = client.y

        return if x_grab_pointer(display, root, false, MOUSE_MASK, GrabModeAsync, GrabModeAsync, None, cursors[Cursor::Resize].cursor, CurrentTime) != GrabSuccess

        x_warp_pointer(display, None, client.window, 0, 0, 0, 0, client.window + client.border - 1, client.height + client.border - 1)

        loop do
            x_mask_event(display, MOUSE_MASK | ExposureMask | SubstructureRedirectMask, out event)
            case event.type
            when ConfigureRequest, Expose, MapRequest
                handler[event.type].call(event)
            when MotionNotify
                next if (event.xmotion.time - last_time) <= 1000 / 60

                last_time = event.xmotion.time
                new_width = Math.max(event.xmotion.x - old_x - 2 * client.border + 1, 1)
                new_height = Math.max(event.xmotion.y - old_y - 2 * client.border + 1, 1)

                if client.screen.win_xx + new_width >= current_screen.win_x && client.screen.win_x + new_width <= current_screen.win_x + current_screen.win_width &&
                client.screen.win_y + new_height >= current_screen.win_y && client.screen.win_y + new_height <= current_screen.win_y + current_screen.win_height
                if !client.floating? && current_screen.layouts[current_screen.layout].arrange &&
                    (new_width - client.width).abs > snap || (new_height - client.height).abs > snap
                    floating(nil)
                end

                if current_screen.layouts[current_screen.layout].arrange || client.floating?
                    client.resize(client.x, client.y, new_width, new_height, 1)
                end
                break
                end
            end
            break if event.type != ButtonRelease
        end

        x_warp_pointer(display, None, client.window, 0, 0, 0, 0, client.window + client.border -  1, client.height + client.border - 1)
        x_ungrab_pointer(display, CurrentTime)
        
        while x_check_mask_event(display, EnterWindowMask, out event)
            if screen = screen_by_area(client.x, client.y, client.width, client.height) != current_screen
                client.move_to_screen(screen)
                current_screen = screen
                focus(nil)
            end
        end
    end 

    def layout(argument)
        if !argument || !argument.v || argument.v != current_screen.layouts[current_screen.layout]
            current_screen.layout ^= 1
        end

        if argument && argument.v
            current_screen.layouts[current_screen.layout] = Box(Layout).unbox(argument.v)
        end

        current_screen.layout_symbol = current_screen.layouts[current_screen.layout].symbol

        if current_screen.focus
            current_screen.arrange
        else
            current_screen.draw_bar
        end
    end

    def stack_factor(argument)
        return if !argument || !current_screen.layouts[current_screen.layout].arrange

        f = argument.f < 1.0 ? argument.f + current_screen.stack_factor : argument.f - 1.0

        return if f < 0.05 || f > 0.95

        current_screen.stack_factor = f

        current_screen.arrange
    end

    def spawn(argument)
    end

    def tag(argument)
        if current_screen.focus && argument.ui && TAG_MASK
            current_screen.focus.tags = argument.ui & TAG_MASK
            focus(nil)
            current_screen.arrange
        end
    end 

    def tag_screen(argument)
        return if !current_screen.focus || !screens.next

        current_screen.focus.move_to_screen(screen_from_by(arg.i))
    end

    def bar(argument)
        current_screen.bar = !current_screen.bar

        update_bar_position(current_screen)

        x_move_resize_window(display, current_screen.bar_win, current_screen.win_x, current_screen.bar_height, current_screen.win_width, bar_height)

        current_screen.arrange
    end

    def floating(argument)
        return if !current_screen.focus

        return if current_screen.fullscreen

        current_screen.focus.floating = !current_screen.focus.floating || current_screen.focus.fixed?

        if current_screen.focus.floating
            resize(current_screen.focus, current_screen.focus.x, current_screen.focus.y, current_screen.focus.width, current_screen.focus.height, 0)
        end

        current_screen.arrange
    end

    def tag(argument)
        return if !current_screen.focus

        tags = current_screen.focs.tags ^ (argument.ui & TAG_MASK)
        if tags
            current_screen.focus.tags = tags
            focus(nil)
            current_screen.arrange
        end
    end

    def view(argument)
        tagset = current_screen.tagset[current_screen.tags] ^ (argument.ui & TAG_MASK)

        if tagset
            current_screen.tagset[current_screen.tags] = tagset
            focus(nil)
            current_screen.arrange
        end
    end

    def view(argument)
        return if argument.ui & TAG_MASK == current_screen.tagset[current_screen.tags]

        current_screen.tags ^= 1

        if argument.ui & TAG_MASK
            current_screen.tagset[current_screen.tags] = argument.ui & TAG_MASK
        end

        focus(nil)

        current_screen.arrange
    end

    def zoom(argument)
        client = current_screen.focus

        return if !current_screen.layouts[current_screen.layout].arrange || !client || client.floating?

        return if client == current_screen.clients.next_tiled && !(client = client.next.next_tiled)
    end
end