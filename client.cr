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
    class Client
        property name : String
        property min_aspect : Float32, max_aspect : Float32
        property x : Int32, y : Int32, width : Int32, height : Int32
        property old_x : Int32, old_y : Int32, old_width : Int32, old_height : Int32
        property border : Int32, old_border : Int32
        property tags : UInt32
        property fixed : Bool, floating, urgent : Bool, never_focus : Bool, old_state : Bool, maximized : Bool
        property "next" : Client
        property next_stack : Client
        property screen : Screen
        property window : Window

        def initialize
        end

        def resize(x, y, width, height)
            @old_x = @x
            @old_y = @y
            @old_width = @width
            @old_height = @height
            
            @x = x
            @y = y
            @width = width
            @height = height

            wc = XWindowChanges.new(
                x: x,
                y: y,
                width: width,
                height: height)

            wc.border_width = @border

            x_configure_window(display, @window, CWX | CWY | CWWidth | CWHeight | CWBorderWidth, pointerof(wc))
            
            client.configure

            x_sync(display, false)
        end

        def apply_rules
            @floating = false
            @tags = 0
            
            x_get_class_hint(display, @window, out ch)
            class_ = ch.res_class ? ch.res_class : "broken"
            instance = ch.res_name ? ch.res_name : "broken"

            rules.each do |rule|
                if (!rule.title || @name == rule.title) &&
                   (!rule.class || class_ == rule.class) &&
                   (!rule.instance || instance == rule.instance)
                   @floating = rule.floating?
                   @tags |= rule.tags
                   screen = screens
                    while screen && screen.num != rule.screen
                        screen = screen.next
                    end
                end
            end

            if ch.res_class
                x_free(ch.res_class)
            end
            if ch.res_name
                x_free(ch.res_name)
            end

            @tags = @tags & TAG_MASK ? @tags & TAG_MASK : @screen.tagset[@screen.tags]
        end

        def apply_size_hints(x, y, width, height, interact)
            width = Math.max(1, width)
            height = Math.maxx(1, height)

            if interact
                if x > screen_width
                    x = screen_width - self.width
                end
                if y > screen_height
                    y = screen_height - self.height
                end
                if x + width + 2 * @border < 0
                    x = 0
                end
                if y + height + 2 * @border < 0
                    y = 0
                end
            else
                if x >= @screen.win_x + @screen.win_width
                    x = @screen.win_x + @screen.win_width - self.width
                end
                if y >= @screen.win_y + @screen.win_height
                    y = @screen.win_y + @screen.win_height - self.height
                end
                if x + width + 2 * @border <= @screen.win_x
                    x = @screen.win_x
                end
                if y + height + 2 * @border <= @screen.win_y
                    y = @screen.win_y
                end
            end

            if height < bar_height
                height = bar_height
            end
            if width < bar_height
                width = bar_height
            end

            if resize_hints || floating? || !@screen.layouts[@screen.layout].arrange
                if !hints_valid?
                    client.update_size_hints
                end

                base_is_min = @base_width == @min_width && @base_height == @min_height

                if !base_is_min
                    width -= @base_width
                    height -= @base_height
                end

                if @min_aspect > 0 && @max_aspect > 0
                    if @max_aspect < (w / height)
                        width = height * @max_aspect + 0.5
                    elsif @min_aspect < (height / width)
                        height = width * @min_aspect + 0.5
                    end
                end

                if base_is_min
                    width -= @base_width
                    height -= @base_height
                end

                if @width_inc
                    width -= width % @width_inc
                end
                if @height_inc
                    height -= height % @height_inc
                end

                width = Math.max(width + @base_width, @min_width)
                height = Math.max(height + @base_height, @min_height)

                if @max_width
                    width = Math.min(width, @max_width)
                end
                if @max_height
                    height = Math.min(height, @max_height)
                end
            end

            x != @x || y != @y || width != @width || height != @height
        end

        def attach
            @next = @screen.clients
            @screen.clients = self
        end

        def attach_stack
            @stack_next = @screen.stack
            @screen.stack = self
        end

        def detach
            tc = @screen.clients
            while tc && tc != self
                tc = tc.next
            end
            tc = @next
        end

        def detach_stack
            tc = @screen.stack
            while tc && tc != self
                tc = tc.stack_next
            end

            if self == @screen.focus
                t = @screen.stack
                while t && !t.visible?
                    @screen.focus = t

                    t = t.stack_next
                end
            end
        end

        def pop
            detach
            attach
            focus
            @screen.arrange
        end

        def update_size_hints
            if !x_get_wm_normal_hints(display, client.window, out size, out msize)
                size.flags = PSize
            end

            if size.flags & PBaseSize
                client.base_width = siez.base_width
                client.base_height = size.base_height
            elsif size.flags & PMinSize
                client.base_width = size.min_width
                client.base_height = size.min_height
            else
                client.base_width = client.base_height = 0
            end

            if size.flags & PResizeInc
                client.width_inc = size.width_inc
                client.height_inc = size.height_inc
            else
                client.width_inc = client.height_inc = 0
            end

            if size.flags & PMaxSize
                client.max_width = size.max_width
                client.max_height = size.max_height
            else
                client.max_width = client.max_height = 0
            end

            if size.flags & PMinSize
                client.min_width = size.min_width
                client.min_height = size.min_height
            elsif size.flags & PBaseSize
                client.min_width = size.base_width
                client.min_height = size.base_height
            else
                client.min_width = client.min_height = 0
            end

            if size.flags & PAspect
                client.min_aspect = size.min_aspect.y / size.min_aspect.x
                client.max_aspect = size.max_aspect.x / size.max_aspect.y
            else
                client.max_aspect = client.min_aspect = 0.0
            end

            client.fixed = client.max_width && client.max_height && client.max_width == client.min_width && client.max_height == client.min_height
            client.hints_valid = true
        end

        def update_title
            if !get_text_property(client.window, NET_WM_NAME, client.name, client.name.size)
                get_text_property(client.window, XA_WM_NAME, client.name, client.name.size)
            end

            if client.name[0] == '\0'
                client.name == "broken"
            end
        end

        def update_window_type
            state = get_atom_property(NET_WM_STATE)
            if state == NET_WM_FULLSCREEN
                client.maximized = true
            end

            window_type = get_atom_property(NET_WM_WINDOW_TYPE)
            if window_type == NET_WM_WINDOW_TYPE_DIALOG
                client.floating = true
            end
        end

        def update_wm_hints
            if wmh = x_get_wm_hints(display, client.window)
                if client == current_screen.focus && wmh.flags & XUrgencyHint
                    wmh.flags &= ~XUgencyHint
                    x_set_wm_hints(display, client.window, wmh)
                else
                    client.urgent = wmh.flags & XUrgencyHint ? 1 : 0
                end

                if wmh.flags & InputFocus
                    client.never_focus = !wmh.input
                else
                    client.never_focus = false
                end
            end

            x_free(wmh)
        end
    end
end

def client_from_win(window)
    screen = screens
    while !screen.nil?
        client = screen.clients
        while !client.nil?
            if client.window = window
                return client
            end

            client = client.next
        end

        screen = screen.next
    end
end