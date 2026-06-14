#!/usr/bin/perl
use strict;
use warnings;
use GD;

my $size = 64;
my $cx   = $size / 2;          # 32
my $cy   = $size / 2;          # 32
my $leg  = 31;                 # длина катета (влезает с обводкой)

my @colors = (
    { main => [220, 40, 40], dark => [160, 20, 20] },   # красный (вниз)
    { main => [40, 60, 220], dark => [20, 30, 160] },    # синий (вправо)
    { main => [40, 200, 60], dark => [20, 150, 30] },    # зелёный (влево)
    { main => [240, 200, 40], dark => [180, 150, 20] },  # жёлтый (вверх)
);

my @corners = (
    { px => $cx,       py => $size,    dx1 => -$leg, dy1 => -$leg,  dx2 =>  $leg, dy2 => -$leg },  # красный (верх)
    { px => $size,     py => $cy,      dx1 => -$leg, dy1 => -$leg,  dx2 => -$leg, dy2 =>  $leg },  # синий (право)
    { px => 0,         py => $cy,      dx1 =>  $leg, dy1 => -$leg,  dx2 =>  $leg, dy2 =>  $leg },  # зелёный (лево)
    { px => $cx,       py => 0,        dx1 => -$leg, dy1 =>  $leg,  dx2 =>  $leg, dy2 =>  $leg },  # жёлтый (низ)
);

for my $i (0..3) {
    my $img = GD::Image->new($size, $size, 1);
    $img->saveAlpha(1);
    $img->alphaBlending(0);

    my $transp = $img->colorAllocateAlpha(0,0,0,127);
    $img->filledRectangle(0,0,$size-1,$size-1, $transp);

    my $c = $colors[$i];
    my $main   = $img->colorAllocateAlpha(@{$c->{main}}, 0);
    my $border = $img->colorAllocateAlpha(40,40,40, 0);
    my $white  = $img->colorAllocateAlpha(255,255,255, 0);

    my $corner = $corners[$i];
    my $x0 = $corner->{px};
    my $y0 = $corner->{py};
    my $x1 = $x0 + $corner->{dx1};
    my $y1 = $y0 + $corner->{dy1};
    my $x2 = $x0 + $corner->{dx2};
    my $y2 = $y0 + $corner->{dy2};

    my $poly = GD::Polygon->new;
    $poly->addPt($x0, $y0);
    $poly->addPt($x1, $y1);
    $poly->addPt($x2, $y2);

    # Заливка
    $img->filledPolygon($poly, $main);

    # Обводка (толщина 2)
    $img->setThickness(2);
    $img->polygon($poly, $border);
    $img->setThickness(1);

    # Блик
    my $blink_x = ($x0 + $x1 + $x2) / 3;
    my $blink_y = ($y0 + $y1 + $y2) / 3;
    $img->filledEllipse($blink_x, $blink_y, 5, 3, $white);

    my $dir = 'assets/buttons';
    mkdir $dir unless -d $dir;
    my $filename = "$dir/button_" . ($i+5) . ".png";
    open my $fh, '>', $filename or die "Cannot write $filename: $!";
    binmode $fh;
    print $fh $img->png;
    close $fh;
    print "Created $filename\n";
}