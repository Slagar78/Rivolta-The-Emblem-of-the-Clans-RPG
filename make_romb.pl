#!/usr/bin/perl
use strict;
use warnings;
use GD;

my $size = 64;

my @colors = (
    { main => [220, 40, 40], dark => [160, 20, 20] },   # красный
    { main => [40, 60, 220], dark => [20, 30, 160] },    # синий
    { main => [40, 200, 60], dark => [20, 150, 30] },    # зелёный
    { main => [240, 200, 40], dark => [180, 150, 20] },  # жёлтый
);

for my $i (0..3) {
    my $img = GD::Image->new($size, $size, 1);
    $img->saveAlpha(1);
    $img->alphaBlending(0);

    my $transp = $img->colorAllocateAlpha(0,0,0,127);
    $img->filledRectangle(0,0,$size-1,$size-1,$transp);

    my $c = $colors[$i];
    my $main   = $img->colorAllocate(@{$c->{main}});
    my $dark   = $img->colorAllocate(@{$c->{dark}});
    my $border = $img->colorAllocate(40,40,40);
    my $white  = $img->colorAllocateAlpha(255,255,255,60);

    my $poly = GD::Polygon->new;
    $poly->addPt($size/2, 0);
    $poly->addPt($size,   $size/2);
    $poly->addPt($size/2, $size);
    $poly->addPt(0,       $size/2);
    $img->filledPolygon($poly, $main);

    my $shadow = GD::Polygon->new;
    $shadow->addPt($size/2, $size/2);
    $shadow->addPt($size,   $size/2);
    $shadow->addPt($size/2, $size);
    $img->filledPolygon($shadow, $dark);
    $shadow = GD::Polygon->new;
    $shadow->addPt($size/2, $size/2);
    $shadow->addPt(0,       $size/2);
    $shadow->addPt($size/2, $size);
    $img->filledPolygon($shadow, $dark);

    $img->setThickness(2);
    $img->polygon($poly, $border);
    $img->setThickness(1);

    my $blink = GD::Polygon->new;
    my $off = $size * 0.08;
    $blink->addPt($size/2, $off);
    $blink->addPt($size/2 + $off*0.7, $size/2 - $off*0.5);
    $blink->addPt($size/2, $size/2 - $off);
    $blink->addPt($size/2 - $off*0.7, $size/2 - $off*0.5);
    $img->filledPolygon($blink, $white);

    my $dir = 'assets/buttons';
    mkdir $dir unless -d $dir;
    my $filename = "$dir/button_" . ($i+1) . ".png";
    open my $fh, '>', $filename or die "Cannot write $filename: $!";
    binmode $fh;
    print $fh $img->png;
    close $fh;
    print "Created $filename\n";
}