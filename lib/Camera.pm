package Camera;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        map_width    => $args{map_width} // 768,
        map_height   => $args{map_height} // 576,
        view_width   => $args{view_width} // 800,
        view_height  => $args{view_height} // 600,
        margin_x     => $args{margin_x} // 0,
        margin_y     => $args{margin_y} // 0,
        dead_zone_x  => $args{dead_zone_x} // 0,
        dead_zone_y  => $args{dead_zone_y} // 0,
        speed        => $args{speed} // 4,
        fast_speed   => $args{fast_speed} // 0,
        speedup_threshold => $args{speedup_threshold} // 6,
        x            => 0,
        y            => 0,
        target_x     => 0,
        target_y     => 0,
        scrolling    => 0,
        scroll_timer => 0,
        cursor_mode  => 0,
        pulsating    => 0,
    };
    bless $self, $class;

    # Начальная позиция камеры: левый верхний угол карты (0,0) отображается в (margin_x, margin_y)
    $self->{x} = -$self->{margin_x};
    $self->{y} = -$self->{margin_y};
    $self->{target_x} = $self->{x};
    $self->{target_y} = $self->{y};
    return $self;
}

sub set_target {
    my ($self, $entity_x, $entity_y) = @_;

    my $target_x = $entity_x - $self->{view_width} / 2;
    my $target_y = $entity_y - $self->{view_height} / 2;

    # Не даём камере выйти за пределы, при которых поля остаются нетронутыми
    my $min_x = -$self->{margin_x};
    my $max_x = $self->{map_width} - $self->{view_width} + $self->{margin_x};
    my $min_y = -$self->{margin_y};
    my $max_y = $self->{map_height} - $self->{view_height} + $self->{margin_y};

    # Если max < min (карта меньше окна), камера фиксируется в начальной позиции
    if ($max_x < $min_x) {
        $target_x = $min_x;
    } else {
        $target_x = $min_x if $target_x < $min_x;
        $target_x = $max_x if $target_x > $max_x;
    }
    if ($max_y < $min_y) {
        $target_y = $min_y;
    } else {
        $target_y = $min_y if $target_y < $min_y;
        $target_y = $max_y if $target_y > $max_y;
    }

    $self->{target_x} = $target_x;
    $self->{target_y} = $target_y;
}

sub _out_of_dead_zone {
    my ($self, $entity_x, $entity_y) = @_;
    my $cx = $self->{x} + $self->{view_width} / 2;
    my $cy = $self->{y} + $self->{view_height} / 2;
    my $dead_w = $self->{dead_zone_x} || ($self->{view_width} / 4);
    my $dead_h = $self->{dead_zone_y} || ($self->{view_height} / 4);
    return abs($entity_x - $cx) > $dead_w || abs($entity_y - $cy) > $dead_h;
}

sub update {
    my $self = shift;
    $self->{scrolling} = 0;
    if ($self->{x} == $self->{target_x} && $self->{y} == $self->{target_y}) {
        $self->{scroll_timer} = 0;
        return;
    }
    $self->{scrolling} = 1;
    $self->{scroll_timer}++;

    my $speed = $self->{speed};
    if ($self->{cursor_mode}) {
        $speed = 8;
    } elsif ($self->{pulsating}) {
        $speed = 2;
    } elsif ($self->{fast_speed} && $self->{scroll_timer} > $self->{speedup_threshold}) {
        $speed = $self->{fast_speed};
    }

    if ($self->{x} != $self->{target_x}) {
        my $diff = $self->{target_x} - $self->{x};
        if (abs($diff) <= $speed) {
            $self->{x} = $self->{target_x};
        } else {
            $self->{x} += ($diff > 0 ? $speed : -$speed);
        }
    }
    if ($self->{y} != $self->{target_y}) {
        my $diff = $self->{target_y} - $self->{y};
        if (abs($diff) <= $speed) {
            $self->{y} = $self->{target_y};
        } else {
            $self->{y} += ($diff > 0 ? $speed : -$speed);
        }
    }
}

sub is_scrolling { $_[0]->{scrolling} }
sub x            { $_[0]->{x} }
sub y            { $_[0]->{y} }

sub set_cursor_mode { $_[0]->{cursor_mode} = 1; }
sub set_pulsating   { $_[0]->{pulsating} = 1; }
sub clear_special_modes { $_[0]->{cursor_mode} = 0; $_[0]->{pulsating} = 0; }

1;