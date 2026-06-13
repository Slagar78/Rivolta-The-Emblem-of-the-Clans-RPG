package Camera;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        # Размеры карты (пиксели)
        map_width    => $args{map_width} // 768,
        map_height   => $args{map_height} // 576,
        # Размеры видимой области (окно)
        view_width   => $args{view_width} // 800,
        view_height  => $args{view_height} // 600,
        # Мёртвая зона (можно задать отдельно по X и Y, иначе считается от центра)
        dead_zone_x  => $args{dead_zone_x} // 0,   # 0 – авто
        dead_zone_y  => $args{dead_zone_y} // 0,
        # Базовая скорость (пикселей за кадр)
        speed        => $args{speed} // 4,
        # Текущая позиция камеры (левый верхний угол)
        x            => 0,
        y            => 0,
        # Целевая позиция, к которой движемся
        target_x     => 0,
        target_y     => 0,
        # Флаг: выполняется скроллинг
        scrolling    => 0,
        # Счётчик кадров непрерывного скролла (аналог word_FFA828)
        scroll_timer => 0,
        # Порог для увеличения скорости (после скольких кадров)
        speedup_threshold => $args{speedup_threshold} // 6,
        # Скорость после порога (если 0, не меняется)
        fast_speed   => $args{fast_speed} // 0,
        # Дополнительные особые режимы
        cursor_mode  => 0,   # ускоренный режим курсора
        pulsating    => 0,   # замедление при затемнении
    };
    bless $self, $class;

    # Если карта меньше экрана – центрируем
    if ($self->{map_width} < $self->{view_width}) {
        $self->{x} = ($self->{map_width} - $self->{view_width}) / 2;
    }
    if ($self->{map_height} < $self->{view_height}) {
        $self->{y} = ($self->{map_height} - $self->{view_height}) / 2;
    }
    $self->{target_x} = $self->{x};
    $self->{target_y} = $self->{y};

    return $self;
}

# Установить цель (мировые координаты точки, на которую центрируемся)
sub set_target {
    my ($self, $entity_x, $entity_y) = @_;

    # Больше не блокируем смену цели во время движения
    my $target_x = $entity_x - $self->{view_width} / 2;
    my $target_y = $entity_y - $self->{view_height} / 2;

    # Ограничения карты
    $target_x = 0 if $target_x < 0;
    $target_y = 0 if $target_y < 0;
    if ($target_x + $self->{view_width} > $self->{map_width}) {
        $target_x = $self->{map_width} - $self->{view_width};
    }
    if ($target_y + $self->{view_height} > $self->{map_height}) {
        $target_y = $self->{map_height} - $self->{view_height};
    }
    if ($self->{map_width} < $self->{view_width}) {
        $target_x = ($self->{map_width} - $self->{view_width}) / 2;
    }
    if ($self->{map_height} < $self->{view_height}) {
        $target_y = ($self->{map_height} - $self->{view_height}) / 2;
    }

    $self->{target_x} = $target_x;
    $self->{target_y} = $target_y;
}

# Проверить, находится ли точка в мёртвой зоне (возвращает истину, если нужно скроллить)
sub _out_of_dead_zone {
    my ($self, $entity_x, $entity_y) = @_;
    my $cx = $self->{x} + $self->{view_width} / 2;   # центр текущего вида
    my $cy = $self->{y} + $self->{view_height} / 2;

    # Размеры мёртвой зоны: если не заданы явно, берём 1/4 от размера экрана,
    # как в оригинале (1536 от 3840? у нас 800 -> 200, 600 -> 150)
    my $dead_w = $self->{dead_zone_x} || ($self->{view_width} / 4);
    my $dead_h = $self->{dead_zone_y} || ($self->{view_height} / 4);

    return abs($entity_x - $cx) > $dead_w || abs($entity_y - $cy) > $dead_h;
}

# Обновить состояние камеры (вызывать каждый кадр)
sub update {
    my $self = shift;
    $self->{scrolling} = 0;

    # Если не движемся, счётчик сбрасываем
    if ($self->{x} == $self->{target_x} && $self->{y} == $self->{target_y}) {
        $self->{scroll_timer} = 0;
        return;
    }

    $self->{scrolling} = 1;
    $self->{scroll_timer}++;

    # Определяем скорость на основе счётчика и режимов
    my $speed = $self->{speed};
    if ($self->{cursor_mode}) {
        $speed = 8;   # быстрее для курсора
    } elsif ($self->{pulsating}) {
        $speed = 2;   # медленнее при затемнении
    } elsif ($self->{fast_speed} && $self->{scroll_timer} > $self->{speedup_threshold}) {
        $speed = $self->{fast_speed};
    }

    # Плавное движение по X
    if ($self->{x} != $self->{target_x}) {
        my $diff = $self->{target_x} - $self->{x};
        if (abs($diff) <= $speed) {
            $self->{x} = $self->{target_x};
        } else {
            $self->{x} += ($diff > 0 ? $speed : -$speed);
        }
    }

    # Плавное движение по Y
    if ($self->{y} != $self->{target_y}) {
        my $diff = $self->{target_y} - $self->{y};
        if (abs($diff) <= $speed) {
            $self->{y} = $self->{target_y};
        } else {
            $self->{y} += ($diff > 0 ? $speed : -$speed);
        }
    }
}

# Ждать остановки скролла (блокирующая функция, для скриптовых нужд)
sub wait_for_scroll_end {
    my $self = shift;
    while ($self->{scrolling}) {
        # В реальном коде здесь будет вызов SDL_Delay или ожидание VBlank
        # Для упрощения просто выйдем, пусть вызывающий сам делает задержку
        return if $self->{scrolling};   # заглушка, но можно реализовать через колбэк
    }
}

# Аксессоры
sub is_scrolling { $_[0]->{scrolling} }
sub x            { $_[0]->{x} }
sub y            { $_[0]->{y} }

# Установка особых режимов
sub set_cursor_mode { $_[0]->{cursor_mode} = 1; }
sub set_pulsating   { $_[0]->{pulsating} = 1; }
sub clear_special_modes { $_[0]->{cursor_mode} = 0; $_[0]->{pulsating} = 0; }

1;