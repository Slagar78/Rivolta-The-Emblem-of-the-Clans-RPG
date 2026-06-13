package TextRenderer;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        letter_tex   => $args{letter_tex},
        draw_cb      => $args{draw_cb},
        letter_w     => $args{letter_w} // 20,
        letter_h     => $args{letter_h} // 32,
        spacing      => $args{spacing} // 1,
        alpha_mod_cb => $args{alpha_mod_cb},
    };
    bless $self, $class;
    return $self;
}

sub draw {
    my ($self, $text, $x, $y, $alpha) = @_;
    my @chars = split //, $text;
    my $w = $self->{letter_w};
    my $h = $self->{letter_h};
    my $sp = $self->{spacing};

    for my $i (0..$#chars) {
        my $ch = $chars[$i];
        next unless exists $self->{letter_tex}{$ch};
        my $tex = $self->{letter_tex}{$ch};
        my $cx = $x + $i * ($w + $sp);
        if (defined $alpha && $self->{alpha_mod_cb}) {
            $self->{alpha_mod_cb}->($tex, $alpha);
        }
        $self->{draw_cb}->($tex, $cx, $y, 0, 0, $w, $h);
        if (defined $alpha && $self->{alpha_mod_cb}) {
            $self->{alpha_mod_cb}->($tex, 255);
        }
    }
}

sub draw_centered {
    my ($self, $text, $center_x, $y, $alpha) = @_;
    my $total_w = length($text) * ($self->{letter_w} + $self->{spacing}) - $self->{spacing};
    my $x = $center_x - $total_w / 2;
    $self->draw($text, $x, $y, $alpha);
}

1;