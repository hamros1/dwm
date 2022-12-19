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
    class Screen
        property layout_symbol : String
        property stack_factor : Float32
        property stacked_count : Int32
        property num : Int32
        property bar_height : Int32
        property x : Int32, y : Int32, width: Int32, height : Int32
        property win_x : Int32, win_y : Int32, win_width : Int32, win_height : Int32
        property tags : UInt32
        property layout : UInt32
        property tagset : UInt32[2]
        property bar : Bool, top_bar : Bool
        property clients : Client
        property focus : Client
        property stack : Client
        property "next" : Screen
        property bar_win : Window
        property layout : Layout[2]

        def initialize(@stack_factor, @stacked_count, @bar, @top_bar, @layouts)
            @tagset = [1, 1] of UInt32
            @layout_symbol = @layouts[0].symbol
        end

        def monocle
            count = 0

            client = @clients
            while !client.nil?
                if client.visible?
                    count += 1
                end

                client = client.next
            end

            if count > 0
                @layout_symbol = "[#{n}]"
            end

            client = @clients.next_tiled
            while !client.nil?
                client.resize(@win_x, @win_y, @win_width - 2 * client.border, @win_height - 2 * client.border, 0)

                client = client.next.next_tiled
            end
        end

        def restack
            draw_bar

            if @focus.floating? || !@layouts[@layout].arrange
                x_raise_window(display, @focus.win)
            end

            if @layouts[@layout].arrange
                wc = XWindowChanges.new(stack_mode: Below, sibling: @bar_win)

                client = @stack
                while !client.nil?
                    if !client.floating? && client.visible?
                        x_configure_window(display, client.window, CWSibling | CWStackMode, pointerof(wc))

                        wc.sibling = client.window
                    end

                    client = client.stack_next
                end
            end

            x_sync(display, false)

            loop do
                break if x_check_mask_event(display, EnterWindowMask, out event)
            end
        end
        
        def tile
            count = 0
            client = @clients.next_tiled
            while !client.nil?
                client = client.next.next_tiled
                count += 1
            end
            return if count == 0

            if count > stacked_count
                width = @stacked_count ? @win_width * @stack_factor : 0
            else
                width = @win_width
            end

            index = y = ty = 0
            client = @clients.next_tiled
            while !client.nil?
                if index < @stacked_count
                    height = (@win_height - @y) / (Math.min(count, @stacked_count) - index)
                    client.resize(@win_x, @win_y + y, width - (2 * client.border), height - (2 * client.border), 0)

                    if y + client.height < @win_height
                        y += client.height
                    end
                else 
                    height = (@win_height - ty) / (count - index)
                    client.resize(@win_x + width, @win_y + ty, @win_width - width - (2 * client.border), height - (2 * client.border), 0)
                end

                client = client.next.next_tiled
                i += 1
            end
        end

        def update_bar_position
            @win_y = @y
            @win_height = @height

            if bar?
                @win_height -= bar_height
                @bar_height = top_bar? ? @win_y : @win_y + @win_height
                @win_y = @top_bar? ? @win_y + bar_height : @win_y
            else
                @bar_height = -bar_height
            end
        end
    end

    def screen_from_client(window)
        if window == root && (point = root_ptr)
            return screen_from_area(point.x, point.y, 1, 1)
        end

        screen = screens
        while !screen.nil?
            if window == screen.bar_win
                return screen
            end

            screen = screen.next
        end

        if client = client_from_win(window)
            return client.screen
        end

        current_screen
    end
end