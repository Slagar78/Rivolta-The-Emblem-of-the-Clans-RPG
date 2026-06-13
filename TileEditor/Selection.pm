package Selection;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        map           => $args{map},
        collision     => $args{collision},
        cols          => $args{cols} // 100,
        rows          => $args{rows} // 20,
        tile_size     => $args{tile_size} // 48,
        scale         => $args{scale} // 1,
        map_view_x    => $args{map_view_x} // 0,
        map_view_y    => $args{map_view_y} // 0,
        scroll_x_ref  => $args{scroll_x_ref},
        scroll_y_ref  => $args{scroll_y_ref},   # поддержка вертикального скролла

        cast          => $args{cast},            # функция приведения типов
        draw_color    => $args{draw_color},
        draw_rect     => $args{draw_rect},
        fill_rect     => $args{fill_rect},
        set_blend     => $args{set_blend},

        active        => 0,
        selecting     => 0,
        start_col     => -1,
        start_row     => -1,
        end_col       => -1,
        end_row       => -1,

        clip_tiles     => [],
        clip_collision => [],
        clip_w         => 0,
        clip_h         => 0,

        palette_active     => 0,
        palette_selecting  => 0,
        palette_start_col  => -1,
        palette_start_row  => -1,
        palette_end_col    => -1,
        palette_end_row    => -1,
        clip_palette       => [],
        palette_w          => 0,
        palette_h          => 0,

        paste_active  => 0,
        paste_col     => -1,
        paste_row     => -1,
        paste_source  => 'map',

        pal_cols      => $args{pal_cols} // 16,
        pal_rows      => $args{pal_rows} // 256,
    };
    bless $self, $class;
    return $self;
}

sub toggle_select_mode {
    my $self = shift;
    $self->{active} = !$self->{active};
    $self->{paste_active} = 0;
    $self->reset_selection();
    return $self->{active};
}

sub reset_selection {
    my $self = shift;
    $self->{selecting}   = 0;
    $self->{start_col}   = -1;
    $self->{start_row}   = -1;
    $self->{end_col}     = -1;
    $self->{end_row}     = -1;
    
    $self->{palette_selecting} = 0;
    $self->{palette_start_col} = -1;
    $self->{palette_start_row} = -1;
    $self->{palette_end_col}   = -1;
    $self->{palette_end_row}   = -1;
}

sub start_selection {
    my ($self, $screen_x, $screen_y) = @_;
    return unless $self->{active};
    my ($col, $row) = $self->_screen_to_cell($screen_x, $screen_y);
    return if $col < 0 || $row < 0;

    $col = $self->{cols} - 1 if $col >= $self->{cols};
    $row = $self->{rows} - 1 if $row >= $self->{rows};

    $self->{start_col} = $col;
    $self->{start_row} = $row;
    $self->{end_col}   = $col;
    $self->{end_row}   = $row;
    $self->{selecting}  = 1;
}

sub update_selection {
    my ($self, $screen_x, $screen_y) = @_;
    return unless $self->{selecting};
    my ($col, $row) = $self->_screen_to_cell($screen_x, $screen_y);
    $col = $self->{cols} - 1 if $col >= $self->{cols};
    $row = $self->{rows} - 1 if $row >= $self->{rows};
    $col = 0 if $col < 0;
    $row = 0 if $row < 0;
    $self->{end_col} = $col;
    $self->{end_row} = $row;
}

sub finish_selection {
    my $self = shift;
    $self->{selecting} = 0;
}

sub start_palette_selection {
    my ($self, $palette_col, $palette_row) = @_;
    return unless $self->{active};

    my $max_col = $self->{pal_cols} - 1;
    my $max_row = $self->{pal_rows} - 1;
    $palette_col = $max_col if $palette_col > $max_col;
    $palette_row = $max_row if $palette_row > $max_row;
    return if $palette_col < 0 || $palette_row < 0;

    $self->{palette_start_col} = $palette_col;
    $self->{palette_start_row} = $palette_row;
    $self->{palette_end_col}   = $palette_col;
    $self->{palette_end_row}   = $palette_row;
    $self->{palette_selecting} = 1;
}

sub update_palette_selection {
    my ($self, $palette_col, $palette_row) = @_;
    return unless $self->{palette_selecting};

    my $max_col = $self->{pal_cols} - 1;
    my $max_row = $self->{pal_rows} - 1;
    $palette_col = $max_col if $palette_col > $max_col;
    $palette_row = $max_row if $palette_row > $max_row;
    $palette_col = 0 if $palette_col < 0;
    $palette_row = 0 if $palette_row < 0;

    $self->{palette_end_col} = $palette_col;
    $self->{palette_end_row} = $palette_row;
}

sub finish_palette_selection {
    my $self = shift;
    $self->{palette_selecting} = 0;
}

sub copy {
    my $self = shift;
    
    if ($self->{palette_start_col} >= 0 && $self->{palette_end_col} >= 0) {
        return $self->_copy_from_palette();
    }
    
    my ($c1, $c2, $r1, $r2) = $self->_ordered_bounds();
    return unless defined $c1;
    $self->{clip_w} = $c2 - $c1 + 1;
    $self->{clip_h} = $r2 - $r1 + 1;
    $self->{clip_tiles} = [];
    $self->{clip_collision} = [];
    $self->{paste_source} = 'map';
    
    for my $r ($r1 .. $r2) {
        my @trow;
        my @crow;
        for my $c ($c1 .. $c2) {
            push @trow, $self->{map}[$r][$c];
            push @crow, $self->{collision}[$r][$c];
        }
        push @{$self->{clip_tiles}}, \@trow;
        push @{$self->{clip_collision}}, \@crow;
    }
    print "Selection copied: $self->{clip_w} x $self->{clip_h}\n";
}

sub _copy_from_palette {
    my $self = shift;
    my ($c1, $c2, $r1, $r2) = $self->_ordered_palette_bounds();
    return unless defined $c1;
    
    $self->{clip_w} = $c2 - $c1 + 1;
    $self->{clip_h} = $r2 - $r1 + 1;
    $self->{clip_palette} = [];
    $self->{paste_source} = 'palette';
    
    for my $r ($r1 .. $r2) {
        my @row;
        for my $c ($c1 .. $c2) {
            my $id = $self->_palette_to_tile_id($c, $r);
            push @row, $id;
        }
        push @{$self->{clip_palette}}, \@row;
    }
    
    print "Palette selection copied: $self->{clip_w} x $self->{clip_h}\n";
}

sub _palette_to_tile_id {
    my ($self, $col, $row) = @_;
    my $block_w = 16;
    my $block_h = 64;
    my $tiles_per_block = $block_w * $block_h;
    
    my $block = int($row / $block_h);
    my $row_in_block = $row % $block_h;
    my $col_in_block = $col;
    
    return $block * $tiles_per_block + $row_in_block * $block_w + $col_in_block;
}

sub start_paste {
    my $self = shift;
    
    my $has_data = 0;
    if ($self->{paste_source} eq 'map' && @{$self->{clip_tiles}} > 0) {
        $has_data = 1;
    } elsif ($self->{paste_source} eq 'palette' && @{$self->{clip_palette}} > 0) {
        $has_data = 1;
    }
    
    return unless $has_data;
    
    $self->{paste_active} = 1;
    $self->{active} = 0;
    $self->{paste_col} = -1;
    $self->{paste_row} = -1;
    print "Paste mode ON. Click to place.\n";
}

sub update_paste_preview {
    my ($self, $screen_x, $screen_y) = @_;
    return unless $self->{paste_active};
    my ($col, $row) = $self->_screen_to_cell($screen_x, $screen_y);
    $col = -1 if $col < 0 || $col >= $self->{cols};
    $row = -1 if $row < 0 || $row >= $self->{rows};
    $self->{paste_col} = $col;
    $self->{paste_row} = $row;
}

sub paste_confirm {
    my $self = shift;
    return unless $self->{paste_active};
    my $col = $self->{paste_col};
    my $row = $self->{paste_row};
    if ($col >= 0 && $row >= 0) {
        $self->_paste_at($col, $row);
        print "Pasted at ($col, $row)\n";
    }
}

sub cancel {
    my $self = shift;
    $self->{active} = 0;
    $self->{paste_active} = 0;
    $self->reset_selection();
    print "Selection/paste cancelled.\n";
}

sub render {
    my ($self, $renderer, $map_view_x, $map_view_y, $tile_w, $tile_h, 
        $pal_view_x, $pal_view_y, $pal_tile_w, $pal_tile_h, $pal_scroll_y) = @_;
    return unless $renderer && $self->{cast};

    my $draw_color = $self->{draw_color};
    my $draw_rect  = $self->{draw_rect};
    my $fill_rect  = $self->{fill_rect};
    my $set_blend  = $self->{set_blend};
    my $cast       = $self->{cast};

    # Выделение на карте
    if ($self->{start_col} >= 0 && $self->{end_col} >= 0) {
        my ($c1, $c2, $r1, $r2) = $self->_ordered_bounds();
        my $x = $map_view_x + $c1 * $tile_w - ${$self->{scroll_x_ref}};
        my $y = $map_view_y + $r1 * $tile_h - ${$self->{scroll_y_ref}};
        my $w = ($c2 - $c1 + 1) * $tile_w;
        my $h = ($r2 - $r1 + 1) * $tile_h;
        $draw_color->($renderer, 255, 255, 255, 255);
        for my $offset (0..2) {
            my $rect = pack('iiii', $x - $offset, $y - $offset, $w + 2*$offset, $h + 2*$offset);
            $draw_rect->($renderer, $cast->('string' => 'opaque', $rect));
        }
    }
    
    # Выделение в палитре
    if ($self->{palette_start_col} >= 0 && $self->{palette_end_col} >= 0) {
        my ($c1, $c2, $r1, $r2) = $self->_ordered_palette_bounds();
        my $x = $pal_view_x + $c1 * $pal_tile_w;
        my $y = $pal_view_y + $r1 * $pal_tile_h - $pal_scroll_y;
        my $w = ($c2 - $c1 + 1) * $pal_tile_w;
        my $h = ($r2 - $r1 + 1) * $pal_tile_h;
        $draw_color->($renderer, 0, 255, 255, 255);
        for my $offset (0..2) {
            my $rect = pack('iiii', $x - $offset, $y - $offset, $w + 2*$offset, $h + 2*$offset);
            $draw_rect->($renderer, $cast->('string' => 'opaque', $rect));
        }
    }

    # Paste preview
    if ($self->{paste_active} && $self->{paste_col} >= 0 && $self->{paste_row} >= 0) {
        my $x = $map_view_x + $self->{paste_col} * $tile_w - ${$self->{scroll_x_ref}};
        my $y = $map_view_y + $self->{paste_row} * $tile_h - ${$self->{scroll_y_ref}};
        my $w = $self->{clip_w} * $tile_w;
        my $h = $self->{clip_h} * $tile_h;
        my $rect = pack('iiii', $x, $y, $w, $h);
        my $alpha = (time() * 4) % 2 ? 200 : 80;
        $set_blend->($renderer, 0x00000001);
        $draw_color->($renderer, 0, 255, 255, $alpha);
        $draw_rect->($renderer, $cast->('string' => 'opaque', $rect));
        $draw_color->($renderer, 0, 255, 255, 50);
        $fill_rect->($renderer, $cast->('string' => 'opaque', $rect));

        my $marker_size = 6;
        $draw_color->($renderer, 255, 255, 0, 255);
        my $marker = pack('iiii',
            $x - $marker_size / 2,
            $y - $marker_size / 2,
            $marker_size,
            $marker_size
        );
        $fill_rect->($renderer, $cast->('string' => 'opaque', $marker));
        $draw_color->($renderer, 0, 0, 0, 255);
        $draw_rect->($renderer, $cast->('string' => 'opaque', $marker));

        $set_blend->($renderer, 0x00000000);
    }
}

sub _screen_to_cell {
    my ($self, $screen_x, $screen_y) = @_;
    my $rel_x = $screen_x - $self->{map_view_x} + ${$self->{scroll_x_ref}};
    my $rel_y = $screen_y - $self->{map_view_y} + ${$self->{scroll_y_ref}};
    my $cell_w = $self->{tile_size} * $self->{scale};
    my $col = int($rel_x / $cell_w);
    my $row = int($rel_y / $cell_w);
    return ($col, $row);
}

sub _ordered_bounds {
    my $self = shift;
    return undef unless $self->{start_col} >= 0 && $self->{end_col} >= 0;
    my $c1 = $self->{start_col} < $self->{end_col} ? $self->{start_col} : $self->{end_col};
    my $c2 = $self->{start_col} < $self->{end_col} ? $self->{end_col} : $self->{start_col};
    my $r1 = $self->{start_row} < $self->{end_row} ? $self->{start_row} : $self->{end_row};
    my $r2 = $self->{start_row} < $self->{end_row} ? $self->{end_row} : $self->{start_row};
    return ($c1, $c2, $r1, $r2);
}

sub _ordered_palette_bounds {
    my $self = shift;
    return undef unless $self->{palette_start_col} >= 0 && $self->{palette_end_col} >= 0;
    my $c1 = $self->{palette_start_col} < $self->{palette_end_col} ? $self->{palette_start_col} : $self->{palette_end_col};
    my $c2 = $self->{palette_start_col} < $self->{palette_end_col} ? $self->{palette_end_col} : $self->{palette_start_col};
    my $r1 = $self->{palette_start_row} < $self->{palette_end_row} ? $self->{palette_start_row} : $self->{palette_end_row};
    my $r2 = $self->{palette_start_row} < $self->{palette_end_row} ? $self->{palette_end_row} : $self->{palette_start_row};
    return ($c1, $c2, $r1, $r2);
}

sub _paste_at {
    my ($self, $col, $row) = @_;
    
    if ($self->{paste_source} eq 'palette') {
        for my $r (0 .. $self->{clip_h} - 1) {
            my $map_row = $row + $r;
            next if $map_row < 0 || $map_row >= $self->{rows};
            for my $c (0 .. $self->{clip_w} - 1) {
                my $map_col = $col + $c;
                next if $map_col < 0 || $map_col >= $self->{cols};
                $self->{map}[$map_row][$map_col] = $self->{clip_palette}[$r][$c];
            }
        }
    } else {
        for my $r (0 .. $self->{clip_h} - 1) {
            my $map_row = $row + $r;
            next if $map_row < 0 || $map_row >= $self->{rows};
            for my $c (0 .. $self->{clip_w} - 1) {
                my $map_col = $col + $c;
                next if $map_col < 0 || $map_col >= $self->{cols};
                $self->{map}[$map_row][$map_col] = $self->{clip_tiles}[$r][$c];
                $self->{collision}[$map_row][$map_col] = $self->{clip_collision}[$r][$c];
            }
        }
    }
}

1;