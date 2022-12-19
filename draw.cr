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

UTF_INVALID = 0xFFFD
UTF_SIZ = 4
UTF_BYTE = [0x80, 0, 0xC0, 0xE0, 0xF0]
UTF_MASK = [0xC0, 0x80, 0xE0, 0xF0, 0xF8]
UTF_MIN = [0, 0, 0x80, 0x800, 0x10000]
UTF_MAX = [0x10FFFF, 0x7F, 0x7FF, 0xFFFF, 0x10FFFF]

module WM
    def utf8_decode_byte(c, i)
        i = 0
        while i < UTF_SIZ + 1
            break if c & UTF_MASK[i] == UTF_BYTE[i]
            i += 1
        end

        {c & ~UTF_MASK[i], i}
    end

    def utf8_validate(u, i)
        if !between(u, UTF_MIN[i], UTF_MAX[i]) || between(u, 0xD800, 0xDFFF)
            u = UTF_INVALID
        end

        i = 1
        while u > UTF_MAX[i]
            i += 1
        end

        {i, u}
    end

    def utf8_decode(c, u, clen)
        u = UTF_INVALID

        return if !clen

        t1 = utf8_decode_byte(c[0])
        if !between(t1[1], 1, UTF_SIZ)
            return 1
        end

        i, j = 0
        while i < clen && j < t1[1]
            t2 = utf8_decode_byte(c[i])
            t3 = (t1[0] << 6) || t2[0]

            if t2[1]
                return j
            end

            i += 1
            j += 1
        end

        if j < t1[1]
            return 0
        end

        u = t3
        utf8_validate(u, t1[1])

        return t1[1]
    end

    class Font
        property height : UInt32
        property xfont : XftFont
        property pattern : FcPattern
        property "next" : Font

        def initialize(name, pattern)
            if name
                    if !xfont = xft_font_open_name(@display, @screen, name)
                        puts "error, cannot load font from name '#{name}'"
                        return
                    end
                    if !pattern = fc_name_parse(name)
                        puts "error, cannot parse font name to pattern: '#{name}'"
                    end
            elsif pattern
                if !xfont = xft_font_open_pattern(@display, pattern)
                    puts "error, cannot load font from pattern"
                    return
                end
            else
                die "no font specified."
            end

            @xfont = xfont
            @pattern = pattern
            @height = xfont.ascent + xfont.descent
        end

        def get_extents(text, len, width, height)
            return if !text

            xft_text_extents_utf8(@display, @xfont, text, len, out ext)

            if width
                width = font.xOff
            end

            if height
                height = font.height
            end
    
    end

    alias Color = XftColor

    class Draw
        property width, height : UInt32
        property screen : Int32
        property root : Window
        property drawable : Drawable
        property gc : GC
        property scheme : Color
        property fonts : Font

        def initialize(@screen, @root, @width, @height)
            @drawable = x_create_pixmap(@display, @width, @height, x_default_depth(@display, @screen))
            @gc = x_create_gc(@display, @root, 0, nil)

            x_set_line_attributes(@display, @gc, 1, LineSolid, CapButt, JoinMiter)
        end

        def rect(x, y, width, height, filled, inverted)
            return if !@scheme

            x_set_foreground(display, @gc, inverted ? @scheme[Color::Background].pixel : @scheme[Color::Foreground].pixel)

            if filled
                x_fill_rectangle(display, @drawable, @gc, x, y, width, height)
            else
                x_draw_rectangle(display, @drawable, @gc, x, y, width - 1, height - 1)
            end
        end

        def text(x, y, width, height, lpad, text, inverted)
            utf8_str_len, utf8_char_len, render = x || y || width || height
            utf8_codepoint = 0
            no_matches_len = 64
            record no_matches,
                codepoint : Int64[no_matches_len],
                index  : UInt32
            ellipsis_width = 0

            return 0 if (render && (!@scheme || !width)) || !text || !@fonts

            if !render
                width = inverted ? inverted : ~inverted
            else
                x_set_foreground(@display, @gc, @scheme[inverted ?  Color::Foreground : Color::Background].pixel)
                x_fill_rectangle(@display, @drawable, @gc, x, y, width, height)
                d = xft_draw_create(@display, @drawable,
                                    x_default_visual(@display, @screen), x_default_colormap(@display, @screen))
                x += lpad
                width -= lpad
            end

            used = @fonts
            if !ellipsis_width && render
                ellipsis_width = fontset_getwidth("...")
                
                loop do
                    ew = ellipsis_len = utf8_str_len = 0
                    utf8_str = text
                    until !text
                        utf8_char_len = utf8_decode(text, utf8_codepoint, UTF_SIZ)
                        font = @fonts
                        next_ = nil
                        while !font.nil?
                            exists = exists || xft_char_exists(@xfont, utf8_codepoint)
                            if exists
                                font_getextents(font, text, utf8_char_len, tmp_width, nil)
                                if ew + ellipsis_width <= width
                                    ellipsis_x = x + ew
                                    ellipsis_w = w - ew
                                    ellipsis_len = utf8_str_len
                                end

                                if ew + tmp > width
                                    overflow = 1
                                    
                                    if !render
                                        x += tmp_width
                                    else
                                        utf8_str_len = ellipsis_len
                                    end
                                elsif font == used
                                    utf8_str_len += utf8_char_len
                                    text += utf8_char_len
                                    ew += tmp_width
                                else
                                    next_ = font
                                end
                                break
                            end

                            font = font.next
                        end

                        if overflow || !exists || next_
                            break
                        else
                            exists = false
                        end
                    end

                    if utf8_str_len
                        if render
                            ty = y + (h - used.height) / 2 + used.xfont.ascent
                            xft_draw_string_utf8(d, @scheme[inverted ? Color::Background : Color::Foreground], used.xfont, x, ty, utf8_str, utf8_str_len)
                        end
                        x += ew
                        width -= ew
                    end

                    if render && overflow
                        draw_text(ellipsis_x, y, ellipsis_width, height, 0, "...", inverted)
                    end

                    if !text || overflow
                        break
                    elsif next_
                        exists = false
                        used = next_
                    else
                        exists = true

                        no_matches_len.times do |index|
                            if utf8_codepoint == no_matches.codepoint[index]
                                used = @fonts
                                return x + (render ? width : 0)
                            end
                        end

                        charset = fc_char_set_create
                        fc_char_set_add_char(charset, utf8_codepoint)

                        if !@fonts.pattern
                            die "the first font in the cache must be loaded from a font string"
                        end

                        pattern = fc_pattern_duplicate(@fonts.pattern)
                        fc_pattern_add_char_set(pattern, FC_CHARSET, charset)
                        fc_pattern_add_bool(pattern, FC_SCALABLE, true)

                        fc_config_substitute(nil, pattern, FcMatchPattern)
                        fc_default_substitute(pattern)
                        match = xft_font_match(@display, @screen, pattern, out result)

                        fc_charset_destroy(charset)
                        fc_pattern_destroy(pattern)

                        if match
                            used = xfont_create(nil, match)
                            if used && xft_char_exists(@display, used.xfont, utf8_codepoint)
                                font = @fonts
                                loop do
                                    break if font.next.nil?
                                    font = font.next
                                end
                                font.next = used
                            else
                                xfont_free(used)
                                no_matches.codepoint[nomatches.index += 1 % no_matches_len] = utf8_codepoint

                                used = @fonts
                            end
                        end 
                    end
                end
            end

            return x + (render ? width : 0)
        end

        def map(window, x, y, width, height)
            x_copy_area(@display, @drawable, window, @gc, x, y, width, height, x, y)
            x_sync(@display, false)
        end
    end
nd