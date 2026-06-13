#!/usr/bin/perl
use strict;
use warnings;
use GD;

my $size = 64;
my $cx   = $size / 2;          # 32
my $cy   = $size / 2;          # 32
my $r    = 28;                 # радиус основного круга
my $d    = $r * 2;             # 56

# Допустимая граница: всё, что дальше $clean_radius от центра, станет прозрачным
# Обводка толщиной 2 добавляет 1 пиксель наружу, так что чистим за пределами r+2 (для запаса)
my $clean_radius = $r + 2;

my @colors = (
    { main => [220, 40, 40], dark => [160, 20, 20] },   # красный
    { main => [40, 60, 220], dark => [20, 30, 160] },    # синий
    { main => [40, 200, 60], dark => [20, 150, 30] },    # зелёный
    { main => [240, 200, 40], dark => [180, 150, 20] },  # жёлтый
);

for my $i (0..3) {
    my $img = GD::Image->new($size, $size, 1);
    $img->saveAlpha(1);
    $img->alphaBlending(0);          # работаем с альфой напрямую

    # Полностью прозрачный фон
    my $transp = $img->colorAllocateAlpha(0,0,0,127);
    $img->filledRectangle(0,0,$size-1,$size-1, $transp);

    my $c = $colors[$i];
    my $main   = $img->colorAllocateAlpha(@{$c->{main}}, 0);
    my $dark   = $img->colorAllocateAlpha(@{$c->{dark}}, 0);
    my $border = $img->colorAllocateAlpha(40,40,40, 0);
    my $white  = $img->colorAllocateAlpha(255,255,255, 0);

    # 1. Основной круг
    $img->filledEllipse($cx, $cy, $d, $d, $main);

    # 2. Тень (правая нижняя четверть) – обычная дуга с хордой, как раньше
    $img->filledArc($cx, $cy, $d, $d, 0, 90, $dark, gdChord);

    # 3. Обводка (толщина 2)
    $img->setThickness(2);
    $img->ellipse($cx, $cy, $d, $d, $border);
    $img->setThickness(1);

    # 4. Блик
    my $blink_x = $cx - $r * 0.3;
    my $blink_y = $cy - $r * 0.3;
    my $blink_w = $r * 0.35;
    my $blink_h = $r * 0.2;
    $img->filledEllipse($blink_x, $blink_y, $blink_w*2, $blink_h*2, $white);
    $img->filledEllipse($blink_x + 4, $blink_y - 4, 4, 3, $white);

    # --- Очистка пикселей за пределами обводки ---
    # Проходим по всем пикселям изображения
    for my $y (0..$size-1) {
        for my $x (0..$size-1) {
            my $dx = $x - $cx;
            my $dy = $y - $cy;
            my $dist = sqrt($dx*$dx + $dy*$dy);
            if ($dist > $clean_radius) {
                # Делаем пиксель полностью прозрачным
                $img->setPixel($x, $y, $transp);
            }
        }
    }

    # Сохранение
    my $dir = 'assets/buttons';
    mkdir $dir unless -d $dir;
    my $filename = "$dir/button_" . ($i+5) . ".png";
    open my $fh, '>', $filename or die "Cannot write $filename: $!";
    binmode $fh;
    print $fh $img->png;
    close $fh;
    print "Created $filename\n";
}