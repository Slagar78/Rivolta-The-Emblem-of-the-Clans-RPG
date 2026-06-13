package Intro;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        logo_tex       => $args{logo_tex},
        state          => 'BLACK_WAIT',
        start_ticks    => 0,
        flicker_visible=> 0,
        next_flicker   => 0,
        fade_alpha     => 255,
        logo_w         => $args{logo_w} // 456,
        logo_h         => $args{logo_h} // 456,
        win_w          => $args{win_w} // 800,
        win_h          => $args{win_h} // 600,
        get_ticks      => $args{get_ticks},
        show_press_start => 0,          # показывать ли надпись Press Start
    };
    bless $self, $class;
    $self->{start_ticks} = $self->{get_ticks}->();
    return $self;
}

sub update {
    my ($self) = @_;
    my $now = $self->{get_ticks}->();
    my $elapsed = $now - $self->{start_ticks};

    if ($self->{state} eq 'BLACK_WAIT') {
        if ($elapsed >= 1000) {
            $self->{state} = 'FLICKER';
            $self->{start_ticks} = $now;
            $self->{flicker_visible} = 0;
            $self->{next_flicker} = int(rand(200)) + 50;
        }
    }
    elsif ($self->{state} eq 'FLICKER') {
        my $flick_elapsed = $now - $self->{start_ticks};
        if ($flick_elapsed >= 2000) {
            $self->{state} = 'FADE_IN';
            $self->{start_ticks} = $now;
            $self->{flicker_visible} = 1;
        } else {
            if ($flick_elapsed >= $self->{next_flicker}) {
                $self->{flicker_visible} = !$self->{flicker_visible};
                $self->{next_flicker} = $flick_elapsed + int(rand(200)) + 50;
            }
        }
    }
    elsif ($self->{state} eq 'FADE_IN') {
        my $fade_elapsed = $now - $self->{start_ticks};
        if ($fade_elapsed >= 800) {
            $self->{state} = 'STEADY';
            $self->{start_ticks} = $now;
            $self->{fade_alpha} = 255;
        } else {
            $self->{fade_alpha} = int(255 * ($fade_elapsed / 800));
            $self->{fade_alpha} = 255 if $self->{fade_alpha} > 255;
        }
    }
    elsif ($self->{state} eq 'STEADY') {
        # Через 2 секунды показываем Press Start, но не выключаем логотип
        if ($now - $self->{start_ticks} >= 2000) {
            $self->{state} = 'WAIT_START';
            $self->{start_ticks} = $now;
            $self->{show_press_start} = 0;   # появится через 2 секунды в этом же состоянии
        }
    }
    elsif ($self->{state} eq 'WAIT_START') {
        my $wait_elapsed = $now - $self->{start_ticks};
        if ($wait_elapsed >= 2000) {
            $self->{show_press_start} = 1;
        }
        # ждём внешнего перехода в FADE_OUT
    }
    elsif ($self->{state} eq 'FADE_OUT') {
        my $fade_elapsed = $now - $self->{start_ticks};
        if ($fade_elapsed >= 2000) {
            $self->{state} = 'DONE';
        } else {
            $self->{fade_alpha} = int(255 * (1 - $fade_elapsed / 2000));
            $self->{fade_alpha} = 0 if $self->{fade_alpha} < 0;
        }
    }
    return $self->{state} eq 'DONE';
}

# Вызывается извне при нажатии клавиши
sub start_fade_out {
    my $self = shift;
    if ($self->{state} eq 'WAIT_START') {
        $self->{state} = 'FADE_OUT';
        $self->{start_ticks} = $self->{get_ticks}->();
        $self->{fade_alpha} = 255;
    }
}

# Методы доступа
sub state           { $_[0]->{state} }
sub flicker_visible { $_[0]->{flicker_visible} }
sub fade_alpha      { $_[0]->{fade_alpha} }
sub logo_w          { $_[0]->{logo_w} }
sub logo_h          { $_[0]->{logo_h} }
sub win_w           { $_[0]->{win_w} }
sub win_h           { $_[0]->{win_h} }
sub logo_tex        { $_[0]->{logo_tex} }
sub show_press_start{ $_[0]->{show_press_start} }

1;