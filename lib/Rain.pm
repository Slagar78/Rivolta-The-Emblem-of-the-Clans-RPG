package Rain;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        max_drops     => $args{max_drops} // 300,
        angle_deg     => $args{angle} // 25,
        speed         => $args{speed} // 9,
        length        => $args{length} // 26,
        splash_chance => $args{splash_chance} // 0.4,
        spawn_rate    => $args{spawn_rate} // 5,
        drops         => [],
        splashes      => [],
        map_w         => 0,
        map_h         => 0,
    };
    bless $self, $class;
    return $self;
}

sub update {
    my ($self, $tile_size, $map_w, $map_h, $cam_x, $cam_y) = @_;
    $self->{map_w} = $map_w;
    $self->{map_h} = $map_h;

    my $angle_rad = $self->{angle_deg} * 3.14159 / 180;
    my $vx = $self->{speed} * sin($angle_rad);
    my $vy = $self->{speed} * cos($angle_rad);

    foreach my $d (@{$self->{drops}}) {
        my $prev_y = $d->{y};
        $d->{x} += $vx;
        $d->{y} += $vy;

        my $start_line = int($prev_y / $tile_size);
        my $end_line   = int($d->{y} / $tile_size);

        if ($end_line > $start_line) {
            for my $line ($start_line + 1 .. $end_line) {
                next if rand() > $self->{splash_chance};
                my $hit_y = $line * $tile_size;
                my $count = 4 + int(rand(4));
                my @parts;
                for (1 .. $count) {
                    push @parts, {
                        dx => int(rand(11)) - 5,
                        dy => -int(rand(8)) - 3,
                    };
                }
                push @{$self->{splashes}}, {
                    x     => $d->{x} - $vx * (($d->{y} - $hit_y) / $vy),
                    y     => $hit_y,
                    life  => 8 + int(rand(7)),
                    parts => \@parts,
                };
            }
        }

        if ($d->{y} > $cam_y + 800 || $d->{x} < -100 || $d->{x} > $map_w + 100) {
            $d = undef;
        }
    }
    @{$self->{drops}} = grep defined, @{$self->{drops}};

    my $needed = $self->{max_drops} - scalar @{$self->{drops}};
    my $to_spawn = $needed < $self->{spawn_rate} ? $needed : $self->{spawn_rate};

    for (1 .. $to_spawn) {
        my $spawn_x = $cam_x - 100 + int(rand(1000));
        $spawn_x = 0 if $spawn_x < 0;
        $spawn_x = $map_w - 1 if $spawn_x >= $map_w;

        my $spawn_y = $cam_y - 100 + int(rand(800));
        $spawn_y = 0 if $spawn_y < 0;
        $spawn_y = $map_h - 1 if $spawn_y >= $map_h;

        push @{$self->{drops}}, {
            x => $spawn_x,
            y => $spawn_y,
        };
    }

    foreach my $s (@{$self->{splashes}}) { $s->{life}--; }
    @{$self->{splashes}} = grep { $_->{life} > 0 } @{$self->{splashes}};
}

sub draw {
    my ($self, $renderer, $cam_x, $cam_y, $draw_line) = @_;
    my $angle_rad = $self->{angle_deg} * 3.14159 / 180;
    my $lx = $self->{length} * sin($angle_rad);
    my $ly = $self->{length} * cos($angle_rad);

    foreach my $d (@{$self->{drops}}) {
        my $sx = $d->{x} - $cam_x;
        my $sy = $d->{y} - $cam_y;
        $draw_line->($sx, $sy, $sx + $lx, $sy + $ly);
    }

    foreach my $s (@{$self->{splashes}}) {
        my $sx = $s->{x} - $cam_x;
        my $sy = $s->{y} - $cam_y;
        foreach my $p (@{$s->{parts}}) {
            my $px = $sx + $p->{dx};
            my $py = $sy + $p->{dy};
            my $ex = $px + ($p->{dx} > 0 ? 2 : -2);
            my $ey = $py + ($p->{dy} > 0 ? 2 : -2);
            $draw_line->($px, $py, $ex, $ey);
        }
    }
}

sub clear {
    my $self = shift;
    @{$self->{drops}} = ();
    @{$self->{splashes}} = ();
}

1;