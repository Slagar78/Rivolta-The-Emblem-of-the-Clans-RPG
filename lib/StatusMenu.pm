package StatusMenu;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        renderer      => $args{renderer},
        draw_cb       => $args{draw_cb},
        win_w         => $args{win_w},
        win_h         => $args{win_h},
        active        => 0,
        frame_tex     => $args{frame_tex},       # Текстура рамки (portrait.png)
        character_tex => $args{character_tex},   # Текстура персонажа (Bryan.png)
        panel1_tex    => $args{panel1_tex},
        panel2_tex    => $args{panel2_tex},
    };
    bless $self, $class;
    return $self;
}

sub open  { $_[0]->{active} = 1; }
sub close { $_[0]->{active} = 0; }
sub is_active { return $_[0]->{active}; }

sub draw {
    my $self = shift;
    return unless $self->{active} && $self->{draw_cb};

    my $block_w = 600;
    my $block_h = 500;

    my $bx = ($self->{win_w} - $block_w) / 2;
    my $by = ($self->{win_h} - $block_h) / 2;

    # 1. Рисуем РАМКУ портрета (150x200)
    $self->{draw_cb}->($self->{frame_tex},     $bx,       $by,       0, 0, 150, 200);
    
    # 2. ПОВЕРХ РАМКИ рисуем ПОРТРЕТ со смещением 
    $self->{draw_cb}->($self->{character_tex}, $bx + 10,  $by + 10,  0, 0, 130, 180);

    # 3. Остальные панели
    $self->{draw_cb}->($self->{panel1_tex},    $bx + 150, $by,       0, 0, 450, 200);
    $self->{draw_cb}->($self->{panel2_tex},    $bx,       $by + 200, 0, 0, 600, 300);
}

1;