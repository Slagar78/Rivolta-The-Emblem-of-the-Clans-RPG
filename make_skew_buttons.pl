#!/usr/bin/perl
use strict;
use warnings;
use GD;

my $w      = 128;
my $h      = 48;
my $r      = 10;               # радиус закругления
my $border = 2;                # толщина обводки
my $margin = 2;                # отступ от краёв

my $img = GD::Image->new($w, $h, 1);
$img->saveAlpha(1);
$img->alphaBlending(0);        # без смешивания, чтобы альфа сохранилась

# Прозрачный фон
my $transp = $img->colorAllocateAlpha(0,0,0,127);
$img->filledRectangle(0,0,$w-1,$h-1,$transp);

# Тот же синий, что и на ромбах (button_2)
my $blue  = $img->colorAllocate(40, 60, 220);   # #283CDC
my $black = $img->colorAllocate(0,0,0);

# Рабочая область
my $x1 = $margin;
my $y1 = $margin;
my $x2 = $w - 1 - $margin;
my $y2 = $h - 1 - $margin;

# --- Заливка ---
$img->filledRectangle($x1+$r, $y1, $x2-$r, $y2, $blue);
$img->filledRectangle($x1, $y1+$r, $x2, $y2-$r, $blue);
$img->filledArc($x1+$r, $y1+$r, 2*$r, 2*$r, 180, 270, $blue);
$img->filledArc($x2-$r, $y1+$r, 2*$r, 2*$r, 270, 360, $blue);
$img->filledArc($x2-$r, $y2-$r, 2*$r, 2*$r, 0, 90, $blue);
$img->filledArc($x1+$r, $y2-$r, 2*$r, 2*$r, 90, 180, $blue);

# --- Чёрная обводка ---
$img->setThickness($border);
$img->line($x1+$r, $y1, $x2-$r, $y1, $black);
$img->line($x1+$r, $y2, $x2-$r, $y2, $black);
$img->line($x1, $y1+$r, $x1, $y2-$r, $black);
$img->line($x2, $y1+$r, $x2, $y2-$r, $black);

$img->arc($x1+$r, $y1+$r, 2*$r, 2*$r, 180, 270, $black);
$img->arc($x2-$r, $y1+$r, 2*$r, 2*$r, 270, 360, $black);
$img->arc($x2-$r, $y2-$r, 2*$r, 2*$r, 0, 90, $black);
$img->arc($x1+$r, $y2-$r, 2*$r, 2*$r, 90, 180, $black);
$img->setThickness(1);

# Сохранение
my $dir = 'assets/buttons';
mkdir $dir unless -d $dir;
my $filename = "$dir/Label_panel.png";
open my $fh, '>', $filename or die "Cannot write $filename: $!";
binmode $fh;
print $fh $img->png;
close $fh;
print "Created $filename (matching button blue, transparent bg, black border)\n";