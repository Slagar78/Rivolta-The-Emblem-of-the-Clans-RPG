package Menu;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        draw_cb          => $args{draw_cb},
        draw_cb_flip     => $args{draw_cb_flip},
        draw_border      => $args{draw_border},
		reset_color      => $args{reset_color},
		renderer => $args{renderer},
        label_panel_tex  => $args{label_panel_tex},
        label_textures   => $args{label_textures} // [],
        visible          => 0,
        center_x         => $args{center_x} // 400,
        center_y         => $args{center_y} // 300,
        offset           => $args{offset} // 34,
        selected         => 0,
        textures         => $args{textures} // [],
        flipping         => 0,
        flip_phase       => 0,
        flip_timer       => 0,
        flip_duration    => $args{flip_duration} // 8,
    };
    bless $self, $class;
	
	$self->{label_letter_textures}  = $args{label_letter_textures} // [];
    $self->{letter_w}               = $args{letter_w} // 16;
    $self->{letter_h}               = $args{letter_h} // 16;
    $self->{letter_spacing}         = $args{letter_spacing} // 0;
	$self->{set_texture_color_mod}  = $args{set_texture_color_mod};
	
    return $self;
}

sub open  { $_[0]->{visible}=1; $_[0]->{selected}=0; $_[0]->{flipping}=0; }
sub close { $_[0]->{visible}=0; }

sub handle_input {
    my ($self, $flags) = @_;
    return unless $self->{visible};
    my $prev = $self->{selected};
    if    ($flags->{up})    { $self->{selected}=0; }
    elsif ($flags->{left})  { $self->{selected}=1; }
    elsif ($flags->{right}) { $self->{selected}=2; }
    elsif ($flags->{down})  { $self->{selected}=3; }
    if ($self->{selected} != $prev) {
        $self->{flipping} = 1;
        $self->{flip_timer} = 0;
        $self->{flip_phase} = 0;
    }
}

sub update {
    my $self = shift;
    return unless $self->{visible} && $self->{flipping};
    $self->{flip_timer}++;
    my $t = $self->{flip_timer} / $self->{flip_duration};
    if ($t >= 1.0) {
        $self->{flip_timer} = 0;
        $self->{flipping} = 0;
        $self->{flip_phase} = 0;
        return;
    }
    if ($t < 0.5) {
        $self->{flip_phase} = 2 * $t;
    } else {
        $self->{flip_phase} = 2 - 2 * $t;
    }
}

sub draw {
    my $self = shift;
    return unless $self->{visible} && $self->{draw_cb};

    my $cx = $self->{center_x};
    my $cy = $self->{center_y};
    my $off = $self->{offset};
    my @pos = (
        { x=>$cx,        y=>$cy-$off },
        { x=>$cx-$off,   y=>$cy },
        { x=>$cx+$off,   y=>$cy },
        { x=>$cx,        y=>$cy+$off },
    );

    for my $i (0..3) {
        my $tex = $self->{textures}[$i];
        next unless $tex;
        my $px = $pos[$i]{x} - 32;
        my $py = $pos[$i]{y} - 32;
        if ($i == $self->{selected} && $self->{flipping} && $self->{draw_cb_flip}) {
            my $scale_x = 1 - $self->{flip_phase};
            my $flip = ($self->{flip_timer} > $self->{flip_duration}/2) ? 1 : 0;
            $self->{draw_cb_flip}->($tex, $px, $py, 0, 0, 64, 64, $scale_x, $flip);
        } else {
            $self->{draw_cb}->($tex, $px, $py, 0, 0, 64, 64);
        }
        if ($i == $self->{selected} && !$self->{flipping} && $self->{draw_border}) {
            my ($x1, $y1) = ($px + 32, $py);
            my ($x2, $y2) = ($px + 64, $py + 32);
            my ($x3, $y3) = ($px + 32, $py + 64);
            my ($x4, $y4) = ($px,      $py + 32);
            $self->{draw_border}->($x1, $y1, $x2, $y2, $x3, $y3, $x4, $y4);
        }
    }

    if ($self->{label_panel_tex}) {
        my $right_btn = $pos[2];
        my $btn_x = $right_btn->{x} - 32;
        my $btn_y = $right_btn->{y} - 32;
        my $panel_x = $btn_x + 64 + 16;
        my $panel_y = $right_btn->{y} - 24;
        $self->{draw_cb}->($self->{label_panel_tex}, $panel_x, $panel_y, 0, 0, 150, 48);

            if ($self->{label_letter_textures} && $self->{label_letter_textures}[$self->{selected}]) {
            my $letters = $self->{label_letter_textures}[$self->{selected}];
            my $lw = $self->{letter_w};
            my $lh = $self->{letter_h};
            my $sp  = $self->{letter_spacing};
            my $word_w = scalar(@$letters) * ($lw + $sp) - $sp;
            my $start_x = $panel_x + (150 - $word_w) / 2;
            my $txt_y   = $panel_y + (48 - $lh) / 2;

            $self->{reset_color}->() if $self->{reset_color};
            for my $i (0..$#$letters) {
                next unless $letters->[$i];
                my $cx = $start_x + $i * ($lw + $sp);
                $self->{draw_cb}->($letters->[$i], $cx, $txt_y, 0, 0, $lw, $lh);
            }
        }
    }
}

1;