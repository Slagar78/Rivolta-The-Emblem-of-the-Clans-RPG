package Player;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        draw_cb    => $args{draw_cb},
        texture    => $args{texture},
        frame_w    => 48,
        frame_h    => 48,
        direction  => $args{direction} // 'down',
        speed      => 7,                     # пикселей за кадр при движении к тайлу
        anim_timer => 0,
        anim_frame => 1,                     # стоячий кадр
        idle_timer => 0,
        moving     => 0,
        just_turned=> 0,
        tile_size  => $args{tile_size} // 48,
        map_cols   => $args{map_cols} // 16,
        map_rows   => $args{map_rows} // 12,
        map_offset_x => $args{map_offset_x} // 0,
        map_offset_y => $args{map_offset_y} // 0,

        tile_x     => 0,
        tile_y     => 0,
        pixel_offset => 0,
        target_tile_x => undef,
        target_tile_y => undef,
    };
    bless $self, $class;

    my $start_x = $args{x} // 0;
    my $start_y = $args{y} // 0;
    $self->{tile_x} = int($start_x / $self->{tile_size});
    $self->{tile_y} = int($start_y / $self->{tile_size});
    $self->{pixel_offset} = 0;
    return $self;
}

sub update {
    my ($self, $flags) = @_;

    # Если персонаж уже движется – двигаем пиксельное смещение
    if (defined $self->{target_tile_x}) {
        $self->{pixel_offset} += $self->{speed};
        if ($self->{pixel_offset} >= $self->{tile_size}) {
            # Достигли целевого тайла
            $self->{tile_x} = $self->{target_tile_x};
            $self->{tile_y} = $self->{target_tile_y};
            $self->{pixel_offset} = 0;
            $self->{target_tile_x} = undef;
            $self->{target_tile_y} = undef;

            # Сразу пытаемся продолжить движение в том же направлении,
            # если клавиша всё ещё зажата.
            my ($dx, $dy) = (0,0);
            my $dir = $self->{direction};
            if ($dir eq 'right' && $flags->{right}) { $dx = 1; }
            elsif ($dir eq 'left'  && $flags->{left})  { $dx = -1; }
            elsif ($dir eq 'down'  && $flags->{down})  { $dy = 1; }
            elsif ($dir eq 'up'    && $flags->{up})    { $dy = -1; }

            if ($dx != 0 || $dy != 0) {
                my $new_tile_x = $self->{tile_x} + $dx;
                my $new_tile_y = $self->{tile_y} + $dy;
                if ($new_tile_x >= 0 && $new_tile_x < $self->{map_cols} &&
                    $new_tile_y >= 0 && $new_tile_y < $self->{map_rows}) {
                    # Начинаем следующий шаг без разрыва анимации
                    $self->{target_tile_x} = $new_tile_x;
                    $self->{target_tile_y} = $new_tile_y;
                    $self->{moving} = 1;
                    # Не сбрасываем anim_frame – оставляем тот же кадр, чтобы не было рывка
                    $self->{pixel_offset} = 0;
                    # Не меняем anim_timer, продолжим с того же места
                    return;
                }
            }
            # Если продолжать некуда, останавливаемся
            $self->{moving} = 0;
            $self->{anim_frame} = 1;   # стоячий кадр
            $self->{idle_timer} = 0;
        } else {
            # Анимация шага
            $self->{anim_timer}++;
            if ($self->{anim_timer} >= 6) {
                $self->{anim_timer} = 0;
                $self->{anim_frame} = ($self->{anim_frame} + 1) % 2;
            }
        }
        return;
    }

    # Обработка ввода с приоритетом: RIGHT > LEFT > DOWN > UP
    my ($new_dir, $dx, $dy);
    if ($flags->{right}) {
        $new_dir = 'right'; $dx = 1; $dy = 0;
    } elsif ($flags->{left}) {
        $new_dir = 'left';  $dx = -1; $dy = 0;
    } elsif ($flags->{down}) {
        $new_dir = 'down';  $dx = 0; $dy = 1;
    } elsif ($flags->{up}) {
        $new_dir = 'up';    $dx = 0; $dy = -1;
    }

    unless (defined $new_dir) {
        # Idle-анимация
        $self->{idle_timer}++;
        if ($self->{idle_timer} >= 15) {
            $self->{idle_timer} = 0;
            $self->{anim_frame} = ($self->{anim_frame} + 1) % 2;
        }
        $self->{just_turned} = 0;
        return;
    }

    # Поворот на месте
    if ($self->{direction} ne $new_dir) {
        $self->{direction} = $new_dir;
        $self->{just_turned} = 1;
        $self->{anim_frame} = 1;
        return;
    }

    if ($self->{just_turned}) {
        $self->{just_turned} = 0;
        return;
    }

    # Начинаем шаг
    my $new_tile_x = $self->{tile_x} + $dx;
    my $new_tile_y = $self->{tile_y} + $dy;
    if ($new_tile_x >= 0 && $new_tile_x < $self->{map_cols} &&
        $new_tile_y >= 0 && $new_tile_y < $self->{map_rows}) {
        $self->{target_tile_x} = $new_tile_x;
        $self->{target_tile_y} = $new_tile_y;
        $self->{moving} = 1;
        $self->{pixel_offset} = 0;
        $self->{anim_frame} = 0;
        $self->{anim_timer} = 0;
        $self->{just_turned} = 0;
    }
}

sub draw {
    my $self = shift;
    return unless $self->{texture} && $self->{draw_cb};

    # Строка спрайт-листа: 0=up, 1=left, 2=right, 3=down
    my $row = 0;
    if    ($self->{direction} eq 'left')  { $row = 1; }
    elsif ($self->{direction} eq 'right') { $row = 2; }
    elsif ($self->{direction} eq 'down')  { $row = 3; }

    my $frame = $self->{anim_frame};
    my $src_x = $frame * $self->{frame_w};
    my $src_y = $row   * $self->{frame_h};

    # Вычисляем экранные координаты с плавным смещением
    my $base_x = $self->{tile_x} * $self->{tile_size};
    my $base_y = $self->{tile_y} * $self->{tile_size};
    if (defined $self->{target_tile_x}) {
        if ($self->{direction} eq 'right') {
            $base_x += $self->{pixel_offset};
        } elsif ($self->{direction} eq 'left') {
            $base_x -= $self->{pixel_offset};
        } elsif ($self->{direction} eq 'down') {
            $base_y += $self->{pixel_offset};
        } elsif ($self->{direction} eq 'up') {
            $base_y -= $self->{pixel_offset};
        }
    }

    my $screen_x = $base_x + $self->{map_offset_x};
    my $screen_y = $base_y + $self->{map_offset_y} - 16;   # спрайт приподнят

    $self->{draw_cb}->(
        $self->{texture},
        $screen_x, $screen_y,
        $src_x, $src_y,
        $self->{frame_w}, $self->{frame_h}
    );
}

sub set_camera_offset {
    my ($self, $ox, $oy) = @_;
    $self->{map_offset_x} = $ox;
    $self->{map_offset_y} = $oy;
}

1;