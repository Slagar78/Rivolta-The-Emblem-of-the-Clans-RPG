#!/usr/bin/perl
use strict;
use warnings;
use Compress::Zlib qw(crc32);

sub fix_indexed_png {
    my ($src, $dst) = @_;
    return if -f $dst;

    open my $in, '<:raw', $src or die "$src: $!";
    local $/; my $data = <$in>; close $in;

    die "$src: Not PNG" unless substr($data,0,8) eq "\x89PNG\r\n\x1a\n";

    my $pos = 8;
    my @chunks;   # каждый элемент: { type => $type, data => $data }
    my ($ihdr, $plte_idx, $plte_data, $plte_len, $trns_data);

    while ($pos < length($data)) {
        my $len = unpack('N', substr($data, $pos, 4));
        my $type = substr($data, $pos+4, 4);
        my $chunk = substr($data, $pos+8, $len);
        push @chunks, { type => $type, data => $chunk };

        if ($type eq 'IHDR') {
            $ihdr = $chunk;
            my ($w, $h, $depth, $color_type) = unpack('NNCC', $chunk);
            die "$src: Not indexed" unless $color_type == 3;
        } elsif ($type eq 'PLTE') {
            $plte_idx = $#chunks;
            $plte_data = $chunk;
            $plte_len = $len;
        } elsif ($type eq 'tRNS') {
            $trns_data = $chunk;
        } elsif ($type eq 'IEND') {
            last;
        }
        $pos += 12 + $len;
    }

    die "$src: Missing PLTE" unless defined $plte_data;

    # Меняем чёрный (0,0,0) на белый (255,255,255) в палитре
    my @palette = unpack('C*', $plte_data);
    for my $i (0..$plte_len/3 - 1) {
        my $r = $palette[$i*3];
        my $g = $palette[$i*3+1];
        my $b = $palette[$i*3+2];
        if ($r==0 && $g==0 && $b==0) {
            $palette[$i*3]   = 255;
            $palette[$i*3+1] = 255;
            $palette[$i*3+2] = 255;
        }
    }
    my $new_plte = pack('C*', @palette);
    $chunks[$plte_idx]{data} = $new_plte;  # заменяем PLTE

    # Собираем новый PNG
    my $out = "\x89PNG\r\n\x1a\n";
    for my $chunk (@chunks) {
        my $type = $chunk->{type};
        my $data = $chunk->{data};
        my $len = length($data);
        $out .= pack('N', $len) . $type . $data . pack('N', crc32($type . $data));
        last if $type eq 'IEND';   # на всякий случай
    }

    open my $ofh, '>:raw', $dst or die "$dst: $!";
    print $ofh $out;
    close $ofh;
}

mkdir 'assets/fonts/white' unless -d 'assets/fonts/white';

for my $num (1..80) {
    my $src = sprintf('assets/fonts/symbol%03d.png', $num);
    my $dst = sprintf('assets/fonts/white/symbol%03d.png', $num);
    next unless -f $src;
    fix_indexed_png($src, $dst);
    print "Converted $src\n";
}