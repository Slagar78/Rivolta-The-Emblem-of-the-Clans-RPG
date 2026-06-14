#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use File::Spec::Functions qw(catfile catdir);
use File::Path qw(mkpath);
use File::Temp qw(tempdir);
use Digest::MD5 qw(md5_hex);
use FFI::Platypus;
use FFI::Platypus::Memory qw(malloc free memcpy);

my $BASE_DIR = catdir($FindBin::Bin, '..', '..');
my $BTN_DIR  = catdir($FindBin::Bin, '..', 'buttons');

# ---------- SDL ----------
my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib('SDL2');
$ffi->lib('SDL2_image');

$ffi->attach( SDL_Init               => ['uint'] => 'int' );
$ffi->attach( SDL_GetError           => []       => 'string' );
$ffi->attach( SDL_CreateWindow       => ['string','int','int','int','int','uint'] => 'opaque' );
$ffi->attach( SDL_CreateRenderer     => ['opaque','int','uint'] => 'opaque' );
$ffi->attach( SDL_DestroyRenderer    => ['opaque'] => 'void' );
$ffi->attach( SDL_DestroyWindow      => ['opaque'] => 'void' );
$ffi->attach( SDL_Quit               => [] => 'void' );
$ffi->attach( SDL_SetRenderDrawColor => ['opaque','uint8','uint8','uint8','uint8'] => 'int' );
$ffi->attach( SDL_RenderClear        => ['opaque'] => 'int' );
$ffi->attach( SDL_RenderCopy         => ['opaque','opaque','opaque','opaque'] => 'int' );
$ffi->attach( SDL_RenderPresent      => ['opaque'] => 'void' );
$ffi->attach( SDL_PollEvent          => ['opaque'] => 'int' );
$ffi->attach( SDL_Delay              => ['uint'] => 'void' );
$ffi->attach( SDL_FreeSurface        => ['opaque'] => 'void' );
$ffi->attach( SDL_CreateTextureFromSurface => ['opaque','opaque'] => 'opaque' );
$ffi->attach( SDL_DestroyTexture     => ['opaque'] => 'void' );
$ffi->attach( SDL_CreateRGBSurface   => ['uint','int','int','int','int','uint','uint','uint','uint'] => 'opaque' );
$ffi->attach( SDL_UpperBlit          => ['opaque','opaque','opaque','opaque'] => 'int' );
$ffi->attach( SDL_QueryTexture       => ['opaque','opaque','opaque','opaque','opaque'] => 'int' );
$ffi->attach( SDL_RenderDrawRect     => ['opaque','opaque'] => 'int' );
$ffi->attach( SDL_RenderFillRect     => ['opaque','opaque'] => 'int' );
$ffi->attach( SDL_RenderDrawLine     => ['opaque','int','int','int','int'] => 'int' );
$ffi->attach( SDL_RWFromFile         => ['string','string'] => 'opaque' );
$ffi->attach( SDL_SaveBMP_RW         => ['opaque','opaque','int'] => 'int' );

$ffi->attach( IMG_Load               => ['string'] => 'opaque' );
$ffi->attach( IMG_Init               => ['int'] => 'int' );

die "SDL_Init: ".SDL_GetError() if SDL_Init(0x00000020) != 0;
die "IMG_Init: ".SDL_GetError() unless IMG_Init(2) & 2;

# ---------- Константы ----------
my $TILE_SIZE    = 48;
my $SCALE        = 0.5;
my $DISPLAY_TILE = 24;
my $PAL_COLS     = 16;               # 16 колонок
my $PAL_TILE_W   = $DISPLAY_TILE;
my $PAL_TILE_H   = $DISPLAY_TILE;
my $PAL_WIDTH    = $PAL_COLS * $PAL_TILE_W;   # 384
my $SCROLLBAR_W  = 14;
my $PAL_PANEL_W  = $PAL_WIDTH + $SCROLLBAR_W; # 398

my $MAP_VIEW_COLS = 18;
my $MAP_VIEW_ROWS = 14;
my $MAP_VIEW_W   = $MAP_VIEW_COLS * $PAL_TILE_W + $SCROLLBAR_W;
my $MAP_VIEW_H   = $MAP_VIEW_ROWS * $PAL_TILE_H + $SCROLLBAR_W;

my $TOP_BAR_H    = 50;
my $GAP          = 12;

my $WIN_W = $PAL_PANEL_W + $GAP + $MAP_VIEW_W;
my $WIN_H = $TOP_BAR_H + $MAP_VIEW_H + 40;

# ---------- Окно и рендерер ----------
my $window   = SDL_CreateWindow("Map Creator", 100, 100, $WIN_W, $WIN_H, 0x00000004);
my $renderer = SDL_CreateRenderer($window, -1, 0x0000000A);
die "Renderer: ".SDL_GetError() unless $renderer;

# ---------- Кнопки ----------
sub load_texture {
    my ($path) = @_;
    return undef unless -f $path;
    my $surf = IMG_Load($path) or return undef;
    my $tex = SDL_CreateTextureFromSurface($renderer, $surf);
    SDL_FreeSurface($surf);
    return $tex;
}
my $btn_import_tex = load_texture(catfile($BTN_DIR, 'import.png'));
my $btn_save_tex   = load_texture(catfile($BTN_DIR, 'save.png'));

# ---------- Данные ----------
my @unique_tiles;
my %tile_index;
my @map_data;
my $map_cols = 0;
my $map_rows = 0;
my $pal_scroll_y = 0;
my $map_scroll_x = 0;
my $map_scroll_y = 0;

# ---------- Блит ----------
sub blit_surface_region {
    my ($src, $src_x, $src_y, $w, $h, $dst, $dst_x, $dst_y) = @_;
    $dst_x //= 0;
    $dst_y //= 0;
    my $sr = malloc(16);
    my $dr = malloc(16);
    memcpy($sr, $ffi->cast('string'=>'opaque', pack('iiii', $src_x, $src_y, $w, $h)), 16);
    memcpy($dr, $ffi->cast('string'=>'opaque', pack('iiii', $dst_x, $dst_y, $w, $h)), 16);
    SDL_UpperBlit($src, $sr, $dst, $dr);
    free($sr); free($dr);
}

# ---------- Импорт через внешний filedialog.exe ----------
sub import_map {
    my $exe = catfile($FindBin::Bin, 'filedialog.exe');
    return unless -f $exe;
    my $file = `"$exe"`;
    chomp $file;
    return unless $file && -f $file;

    # --- Нарезка карты ---
    my $src_surf = IMG_Load($file) or return;
    my $src_tex = SDL_CreateTextureFromSurface($renderer, $src_surf);
    my ($fmt, $acc, $w_ptr, $h_ptr) = map { malloc(4) } 1..4;
    SDL_QueryTexture($src_tex, $fmt, $acc, $w_ptr, $h_ptr);
    SDL_DestroyTexture($src_tex);
    my ($wb, $hb) = ("\0"x4, "\0"x4);
    memcpy($ffi->cast('string'=>'opaque', $wb), $w_ptr, 4);
    memcpy($ffi->cast('string'=>'opaque', $hb), $h_ptr, 4);
    my $img_w = unpack('i', $wb);
    my $img_h = unpack('i', $hb);
    free($_) for $fmt, $acc, $w_ptr, $h_ptr;

    $map_cols = int($img_w / 48);
    $map_rows = int($img_h / 48);
    unless ($map_cols >= 4 && $map_rows >= 4) {
        SDL_FreeSurface($src_surf);
        return;
    }

    foreach (@unique_tiles) {
        SDL_DestroyTexture($_->{tex}) if $_->{tex};
        SDL_FreeSurface($_->{surf}) if $_->{surf};
    }
    @unique_tiles = ();
    %tile_index   = ();
    @map_data     = ();
    $pal_scroll_y = 0;
    $map_scroll_x = 0;
    $map_scroll_y = 0;

    my $Rmask = 0x000000FF;
    my $Gmask = 0x0000FF00;
    my $Bmask = 0x00FF0000;
    my $Amask = 0xFF000000;

    my $tmpdir = tempdir(CLEANUP => 1);
    print "Slicing ${map_cols}x${map_rows} map...\n";

    for my $row (0 .. $map_rows-1) {
        my @row_ids;
        for my $col (0 .. $map_cols-1) {
            my $tile_surf = SDL_CreateRGBSurface(0, 48, 48, 32, $Rmask, $Gmask, $Bmask, $Amask);
            blit_surface_region($src_surf, $col*48, $row*48, 48, 48, $tile_surf, 0, 0);

            my $tmp_bmp = catfile($tmpdir, "tile_${row}_${col}.bmp");
            my $rw = SDL_RWFromFile($tmp_bmp, "wb");
            SDL_SaveBMP_RW($tile_surf, $rw, 1);
            open(my $fh, '<:raw', $tmp_bmp) or next;
            my $md5 = md5_hex(<$fh>);
            close $fh;
            unlink $tmp_bmp;

            unless (exists $tile_index{$md5}) {
                my $tex = SDL_CreateTextureFromSurface($renderer, $tile_surf);
                push @unique_tiles, { tex => $tex, surf => $tile_surf, md5 => $md5 };
                $tile_index{$md5} = $#unique_tiles;
            } else {
                SDL_FreeSurface($tile_surf);
            }
            push @row_ids, $tile_index{$md5};
        }
        push @map_data, \@row_ids;
    }
    SDL_FreeSurface($src_surf);
    print "Done! Unique tiles: " . scalar(@unique_tiles) . "\n";
}

# ---------- Сохранение ----------
sub save_map {
    return unless @unique_tiles && $map_cols && $map_rows;
    my $map_folder = 'newmap';
    my $map_dir = catdir($BASE_DIR, 'data', 'map', $map_folder);
    mkpath($map_dir) unless -d $map_dir;
    my $tileset_dir = catdir($BASE_DIR, 'assets', 'tileset');
    mkpath($tileset_dir) unless -d $tileset_dir;
    my $atlas_path = catfile($tileset_dir, 'newtileset.png');

    my $Rmask = 0x000000FF;
    my $Gmask = 0x0000FF00;
    my $Bmask = 0x00FF0000;
    my $Amask = 0xFF000000;
    my $atlas = SDL_CreateRGBSurface(0, 3072, 3072, 32, $Rmask, $Gmask, $Bmask, $Amask);
    my $tiles_per_strip = 16 * 64;
    my $strip_w = 16 * 48;

    for my $i (0 .. $#unique_tiles) {
        my $surf = $unique_tiles[$i]{surf};
        my $strip = int($i / $tiles_per_strip);
        my $local = $i % $tiles_per_strip;
        my $col = $local % 16;
        my $row = int($local / 16);
        my $dx = $strip * $strip_w + $col * 48;
        my $dy = $row * 48;
        blit_surface_region($surf, 0, 0, 48, 48, $atlas, $dx, $dy);
    }

    my $tmp_bmp = catfile($tileset_dir, 'tmp.bmp');
    my $rw = SDL_RWFromFile($tmp_bmp, "wb");
    SDL_SaveBMP_RW($atlas, $rw, 1);
    SDL_FreeSurface($atlas);
    my $ps = qq{powershell -Command "Add-Type -AssemblyName System.Drawing; \$img = [System.Drawing.Image]::FromFile('$tmp_bmp'); \$img.Save('$atlas_path', [System.Drawing.Imaging.ImageFormat]::Png); \$img.Dispose()"};
    system($ps);
    unlink $tmp_bmp;

    my $layout = catfile($map_dir, 'layout.toml');
    open my $fh, '>', $layout or die "Cannot save $layout: $!";
    print $fh "[map]\ncols = $map_cols\nrows = $map_rows\n\n[tiles]\n";
    for my $r (0 .. $map_rows-1) {
        printf $fh "row%02d = \"%s\"\n", $r, join(' ', @{$map_data[$r]});
    }
    print $fh "\n[collision]\n";
    for my $r (0 .. $map_rows-1) {
        printf $fh "row%02d = \"%s\"\n", $r, join(' ', (0) x $map_cols);
    }
    close $fh;
    print "Saved to $map_dir and $atlas_path\n";
}

# ---------- Отрисовка ----------
sub draw_palette {
    my $t = $DISPLAY_TILE;
    my $cols = $PAL_COLS;
    my $start_x = 0;
    my $start_y = $TOP_BAR_H;

    for my $i (0 .. $#unique_tiles) {
        my $c = $i % $cols;
        my $r = int($i / $cols);
        my $dx = $start_x + $c * $t;
        my $dy = $start_y + $r * $t - $pal_scroll_y;
        next if $dy + $t < $start_y || $dy > $start_y + $MAP_VIEW_H;
        my $dst = pack('iiii', $dx, $dy, $t, $t);
        SDL_RenderCopy($renderer, $unique_tiles[$i]{tex}, undef, $ffi->cast('string'=>'opaque', $dst));
        SDL_SetRenderDrawColor($renderer, 100,100,100,255);
        SDL_RenderDrawRect($renderer, $ffi->cast('string'=>'opaque', $dst));
    }

    my $total_rows = int((@unique_tiles + $cols - 1) / $cols);
    my $h = $total_rows * $t;
    $h = $MAP_VIEW_H if $h < $MAP_VIEW_H;
    my $max = $h - $MAP_VIEW_H;
    if ($max > 0) {
        my $track = pack('iiii', $PAL_WIDTH, $start_y, $SCROLLBAR_W, $MAP_VIEW_H);
        SDL_SetRenderDrawColor($renderer, 70,70,70,255);
        SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $track));
        my $th = int(($MAP_VIEW_H / $h) * $MAP_VIEW_H);
        $th = 12 if $th < 12;
        my $ty = int(($pal_scroll_y / $max) * ($MAP_VIEW_H - $th));
        my $thumb = pack('iiii', $PAL_WIDTH, $start_y + $ty, $SCROLLBAR_W, $th);
        SDL_SetRenderDrawColor($renderer, 150,150,150,255);
        SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $thumb));
    }
}

sub draw_map {
    my $t = $DISPLAY_TILE;
    my $start_x = $PAL_PANEL_W + $GAP;
    my $start_y = $TOP_BAR_H;

    my $bg = pack('iiii', $start_x, $start_y, $MAP_VIEW_W - $SCROLLBAR_W, $MAP_VIEW_H - $SCROLLBAR_W);
    SDL_SetRenderDrawColor($renderer, 25,25,70,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $bg));

    return unless @map_data;
    my $c0 = int($map_scroll_x / $t);
    my $c1 = int(($map_scroll_x + $MAP_VIEW_W - $SCROLLBAR_W - 1) / $t);
    my $r0 = int($map_scroll_y / $t);
    my $r1 = int(($map_scroll_y + $MAP_VIEW_H - $SCROLLBAR_W - 1) / $t);
    $c1 = $map_cols - 1 if $c1 >= $map_cols;
    $r1 = $map_rows - 1 if $r1 >= $map_rows;

    for my $row ($r0 .. $r1) {
        for my $col ($c0 .. $c1) {
            my $id = $map_data[$row][$col];
            next unless $id < @unique_tiles;
            my $dx = $start_x + $col * $t - $map_scroll_x;
            my $dy = $start_y + $row * $t - $map_scroll_y;
            my $dst = pack('iiii', $dx, $dy, $t, $t);
            SDL_RenderCopy($renderer, $unique_tiles[$id]{tex}, undef, $ffi->cast('string'=>'opaque', $dst));
        }
    }

    SDL_SetRenderDrawColor($renderer, 80,80,80,100);
    for (my $c = $c0; $c <= $c1+1; ++$c) {
        my $x = $start_x + $c*$t - $map_scroll_x;
        next if $x < $start_x || $x > $start_x + $MAP_VIEW_W - $SCROLLBAR_W;
        SDL_RenderDrawLine($renderer, $x, $start_y, $x, $start_y + $MAP_VIEW_H - $SCROLLBAR_W);
    }
    for (my $r = $r0; $r <= $r1+1; ++$r) {
        my $y = $start_y + $r*$t - $map_scroll_y;
        next if $y < $start_y || $y > $start_y + $MAP_VIEW_H - $SCROLLBAR_W;
        SDL_RenderDrawLine($renderer, $start_x, $y, $start_x + $MAP_VIEW_W - $SCROLLBAR_W, $y);
    }

    my $tw = $map_cols * $t;
    my $th = $map_rows * $t;
    my $vis_w = $MAP_VIEW_W - $SCROLLBAR_W;
    my $vis_h = $MAP_VIEW_H - $SCROLLBAR_W;
    my $mx = $tw - $vis_w; $mx = 0 if $mx<0;
    my $my = $th - $vis_h; $my = 0 if $my<0;
    if ($mx > 0) {
        my $track = pack('iiii', $start_x, $start_y + $vis_h, $vis_w, $SCROLLBAR_W);
        SDL_SetRenderDrawColor($renderer, 70,70,70,255);
        SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $track));
        my $twb = int(($vis_w / $tw) * $vis_w); $twb = 12 if $twb<12;
        my $txb = int(($map_scroll_x / $mx) * ($vis_w - $twb));
        my $thumb = pack('iiii', $start_x + $txb, $start_y + $vis_h, $twb, $SCROLLBAR_W);
        SDL_SetRenderDrawColor($renderer, 150,150,150,255);
        SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $thumb));
    }
    if ($my > 0) {
        my $track = pack('iiii', $start_x + $vis_w, $start_y, $SCROLLBAR_W, $vis_h);
        SDL_SetRenderDrawColor($renderer, 70,70,70,255);
        SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $track));
        my $thb = int(($vis_h / $th) * $vis_h); $thb = 12 if $thb<12;
        my $tyb = int(($map_scroll_y / $my) * ($vis_h - $thb));
        my $thumb = pack('iiii', $start_x + $vis_w, $start_y + $tyb, $SCROLLBAR_W, $thb);
        SDL_SetRenderDrawColor($renderer, 150,150,150,255);
        SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $thumb));
    }
}

# ---------- Главный цикл ----------
my $event_ptr = malloc(56);
my $running = 1;
my ($mx, $my, $mb) = (0,0,0);

while ($running) {
    my $ev = "\0"x56;
    while (SDL_PollEvent($event_ptr)) {
        memcpy($ffi->cast('string'=>'opaque', $ev), $event_ptr, 56);
        my $type = unpack('V', substr($ev,0,4));
        if ($type == 0x100) { $running = 0; last }
        elsif ($type == 0x400) {
            $mx = unpack('V', substr($ev,20,4));
            $my = unpack('V', substr($ev,24,4));
        }
        elsif ($type == 0x401) {
            $mb = unpack('C', substr($ev,16,1));
            $mx = unpack('V', substr($ev,20,4));
            $my = unpack('V', substr($ev,24,4));
            if ($my >= 8 && $my <= 36) {
                if ($mx >= 10 && $mx <= 62) { import_map(); next }
                if ($mx >= 74 && $mx <= 114) { save_map(); next }
            }
            if ($mx >= $PAL_WIDTH && $mx <= $PAL_PANEL_W && $my >= $TOP_BAR_H && $my <= $TOP_BAR_H+$MAP_VIEW_H) {
                my $rows = int((@unique_tiles+$PAL_COLS-1)/$PAL_COLS);
                my $h = $rows*$PAL_TILE_H; $h=$MAP_VIEW_H if $h<$MAP_VIEW_H;
                my $max = $h-$MAP_VIEW_H;
                if ($max>0) {
                    $pal_scroll_y = int(($my-$TOP_BAR_H)/$MAP_VIEW_H*$max);
                    $pal_scroll_y = 0 if $pal_scroll_y<0;
                    $pal_scroll_y = $max if $pal_scroll_y>$max;
                }
                next;
            }
            my $map_start_x = $PAL_PANEL_W + $GAP;
            if ($mx >= $map_start_x && $mx <= $map_start_x+$MAP_VIEW_W-$SCROLLBAR_W &&
                $my >= $TOP_BAR_H+$MAP_VIEW_H-$SCROLLBAR_W && $my <= $TOP_BAR_H+$MAP_VIEW_H) {
                my $tw = $map_cols*$PAL_TILE_W;
                my $vis_w = $MAP_VIEW_W-$SCROLLBAR_W;
                my $max = $tw-$vis_w;
                if ($max>0) {
                    $map_scroll_x = int(($mx-$map_start_x)/$vis_w*$max);
                    $map_scroll_x = 0 if $map_scroll_x<0;
                    $map_scroll_x = $max if $map_scroll_x>$max;
                }
                next;
            }
            if ($mx >= $map_start_x+$MAP_VIEW_W-$SCROLLBAR_W && $mx <= $map_start_x+$MAP_VIEW_W &&
                $my >= $TOP_BAR_H && $my <= $TOP_BAR_H+$MAP_VIEW_H-$SCROLLBAR_W) {
                my $th = $map_rows*$PAL_TILE_H;
                my $vis_h = $MAP_VIEW_H-$SCROLLBAR_W;
                my $max = $th-$vis_h;
                if ($max>0) {
                    $map_scroll_y = int(($my-$TOP_BAR_H)/$vis_h*$max);
                    $map_scroll_y = 0 if $map_scroll_y<0;
                    $map_scroll_y = $max if $map_scroll_y>$max;
                }
                next;
            }
        }
        elsif ($type == 0x402) { $mb = 0 }
        elsif ($type == 0x700) {
            my $wx = unpack('l', substr($ev,16,4));
            my $wy = unpack('l', substr($ev,20,4));
            if ($mx <= $PAL_PANEL_W && $my >= $TOP_BAR_H && $my <= $TOP_BAR_H+$MAP_VIEW_H) {
                $pal_scroll_y -= $wy*24;
                my $rows = int((@unique_tiles+$PAL_COLS-1)/$PAL_COLS);
                my $h = $rows*$PAL_TILE_H; $h=$MAP_VIEW_H if $h<$MAP_VIEW_H;
                my $max = $h-$MAP_VIEW_H;
                $pal_scroll_y = 0 if $pal_scroll_y<0;
                $pal_scroll_y = $max if $pal_scroll_y>$max;
            }
            else {
                $map_scroll_x -= $wx*24;
                $map_scroll_y -= $wy*24;
                my $maxx = $map_cols*$PAL_TILE_W - ($MAP_VIEW_W-$SCROLLBAR_W);
                my $maxy = $map_rows*$PAL_TILE_H - ($MAP_VIEW_H-$SCROLLBAR_W);
                $maxx = 0 if $maxx<0; $maxy = 0 if $maxy<0;
                $map_scroll_x = 0 if $map_scroll_x<0; $map_scroll_x = $maxx if $map_scroll_x>$maxx;
                $map_scroll_y = 0 if $map_scroll_y<0; $map_scroll_y = $maxy if $map_scroll_y>$maxy;
            }
        }
    }

    SDL_SetRenderDrawColor($renderer,40,40,40,255);
    SDL_RenderClear($renderer);

    my $top = pack('iiii',0,0,$WIN_W,$TOP_BAR_H);
    SDL_SetRenderDrawColor($renderer,55,55,65,255);
    SDL_RenderFillRect($renderer,$ffi->cast('string'=>'opaque',$top));

    if ($btn_import_tex) {
        SDL_RenderCopy($renderer,$btn_import_tex,undef,$ffi->cast('string'=>'opaque',pack('iiii',10,8,52,28)));
    }
    if ($btn_save_tex) {
        SDL_RenderCopy($renderer,$btn_save_tex,undef,$ffi->cast('string'=>'opaque',pack('iiii',74,8,40,28)));
    }

    draw_palette();
    draw_map();

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

free($event_ptr);
foreach (@unique_tiles) {
    SDL_DestroyTexture($_->{tex}) if $_->{tex};
    SDL_FreeSurface($_->{surf}) if $_->{surf};
}
SDL_DestroyTexture($btn_import_tex) if $btn_import_tex;
SDL_DestroyTexture($btn_save_tex) if $btn_save_tex;
SDL_DestroyRenderer($renderer);
SDL_DestroyWindow($window);
SDL_Quit();