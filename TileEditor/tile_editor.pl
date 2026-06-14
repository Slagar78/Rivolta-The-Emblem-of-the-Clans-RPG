#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;

use File::Spec::Functions qw(catfile catdir);
use File::Basename qw(dirname);
use Time::HiRes qw(time);

my $BASE_DIR = $FindBin::Bin;   # \TileEditor
if (! -d catdir($BASE_DIR, 'assets')) {
    $BASE_DIR = catdir($BASE_DIR, '..');
}

binmode(STDOUT, ':encoding(cp866)');
use FFI::Platypus;
use FFI::Platypus::Memory qw(malloc free memcpy);
use Selection;

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib('SDL2');
$ffi->lib('SDL2_image');
$ffi->lib('SDL2_ttf');

# ----- SDL functions -----
$ffi->attach( SDL_Init               => ['uint']                     => 'int' );
$ffi->attach( SDL_GetError           => []                           => 'string' );
$ffi->attach( SDL_SetHint            => ['string', 'string']         => 'int' );
$ffi->attach( SDL_CreateWindow       => ['string','int','int','int','int','uint'] => 'opaque' );
$ffi->attach( SDL_CreateRenderer     => ['opaque','int','uint']      => 'opaque' );
$ffi->attach( SDL_CreateTextureFromSurface => ['opaque','opaque']    => 'opaque' );
$ffi->attach( SDL_DestroyTexture     => ['opaque']                   => 'void' );
$ffi->attach( SDL_SetRenderDrawColor => ['opaque','uint8','uint8','uint8','uint8'] => 'int' );
$ffi->attach( SDL_RenderClear        => ['opaque']                   => 'int' );
$ffi->attach( SDL_RenderCopy         => ['opaque','opaque','opaque','opaque'] => 'int' );
$ffi->attach( SDL_RenderPresent      => ['opaque']                   => 'void' );
$ffi->attach( SDL_PollEvent          => ['opaque']                   => 'int' );
$ffi->attach( SDL_Delay              => ['uint']                     => 'void' );
$ffi->attach( SDL_DestroyRenderer    => ['opaque']                   => 'void' );
$ffi->attach( SDL_DestroyWindow      => ['opaque']                   => 'void' );
$ffi->attach( SDL_Quit               => []                           => 'void' );
$ffi->attach( SDL_FreeSurface        => ['opaque']                   => 'void' );
$ffi->attach( SDL_RenderDrawLine     => ['opaque', 'int', 'int', 'int', 'int'] => 'int' );
$ffi->attach( SDL_RenderDrawRect     => ['opaque', 'opaque']         => 'int' );
$ffi->attach( SDL_RenderFillRect     => ['opaque', 'opaque']         => 'int' );
$ffi->attach( SDL_CreateRGBSurface   => ['uint','int','int','int','int','uint','uint','uint','uint'] => 'opaque' );
$ffi->attach( SDL_MapRGBA            => ['opaque','uint8','uint8','uint8','uint8'] => 'uint' );
$ffi->attach( SDL_FillRect           => ['opaque','opaque','uint']   => 'int' );
$ffi->attach( SDL_StartTextInput     => []                           => 'void' );
$ffi->attach( SDL_StopTextInput      => []                           => 'void' );
$ffi->attach( SDL_GetModState        => []                           => 'uint' );
$ffi->attach( SDL_SetRenderDrawBlendMode => ['opaque', 'int']       => 'int' );
$ffi->attach( SDL_SetTextureColorMod => ['opaque', 'uint8', 'uint8', 'uint8'] => 'int' );

$ffi->attach( IMG_Load                => ['string']                  => 'opaque' );
$ffi->attach( IMG_Init                => ['int']                     => 'int' );

$ffi->attach( TTF_Init               => []                           => 'int' );
$ffi->attach( TTF_OpenFont           => ['string', 'int']            => 'opaque' );
$ffi->attach( TTF_RenderUTF8_Solid   => ['opaque', 'string', 'opaque'] => 'opaque' );
$ffi->attach( TTF_RenderUTF8_Blended => ['opaque', 'string', 'opaque'] => 'opaque' );
$ffi->attach( TTF_RenderUTF8_Shaded => ['opaque', 'string', 'opaque', 'opaque'] => 'opaque' );
$ffi->attach( TTF_CloseFont          => ['opaque']                   => 'void' );
$ffi->attach( TTF_Quit               => []                           => 'void' );

# ----- Init SDL -----
die "SDL_Init: " . SDL_GetError() if SDL_Init(0x00000020) != 0;
die "IMG_Init: " . SDL_GetError() unless IMG_Init(2) & 2;
die "TTF_Init: " . SDL_GetError() if TTF_Init() != 0;
SDL_SetHint("SDL_HINT_RENDER_SCALE_QUALITY", "0");

# ----- Пути -----
sub asset {
    return catfile($BASE_DIR, 'assets', @_);
}

sub button_file {
    return catfile($FindBin::Bin, 'buttons', @_);
}

sub symbol_file {
    return catfile($FindBin::Bin, 'symbols', @_);
}

# ----- Font (из assets) -----
my $FONT_PATH = asset('fonts', 'arial.ttf');
$FONT_PATH = "C:/Windows/Fonts/arial.ttf" unless -f $FONT_PATH;
die "No font found! Put arial.ttf in ../assets/fonts/" unless -f $FONT_PATH;
my $font24 = TTF_OpenFont($FONT_PATH, 24) or die "Cannot open font 24";
my $font16 = TTF_OpenFont($FONT_PATH, 16) or die "Cannot open font 16";
my $font12 = TTF_OpenFont($FONT_PATH, 12) or die "Cannot open font 12";

# ----- FIXED PARAMS -----
my $TILE_SIZE    = 48;
my $SCALE        = 0.5;
my $VISIBLE_COLS = 10;
my $VISIBLE_ROWS = 17;

my $PAL_COLS     = 16;
my $PAL_TILE_W   = $TILE_SIZE * $SCALE;
my $PAL_TILE_H   = $TILE_SIZE * $SCALE;
my $PAL_WIDTH    = $PAL_COLS * $PAL_TILE_W;
my $SCROLLBAR_W  = 16;
my $PAL_PANEL_W  = $PAL_WIDTH + $SCROLLBAR_W;

my $TILE_AREA_W  = $VISIBLE_COLS * $PAL_TILE_W;
my $TILE_AREA_H  = $VISIBLE_ROWS * $PAL_TILE_H;

my $MAP_VIEW_W   = $TILE_AREA_W + $SCROLLBAR_W;
my $MAP_VIEW_H   = $TILE_AREA_H + $SCROLLBAR_W;
my $TOP_BAR_H    = 90;
my $PAL_AREA_H   = $MAP_VIEW_H;

my $WIN_W = $PAL_PANEL_W + $MAP_VIEW_W;
my $WIN_H = $TOP_BAR_H + $MAP_VIEW_H;

# ----- Main window and renderer -----
my $window   = SDL_CreateWindow("Tile Map Editor", 100, 100, $WIN_W, $WIN_H, 0x00000004);
my $renderer = SDL_CreateRenderer($window, -1, 0x0000000A);
die "Main renderer: " . SDL_GetError() unless $renderer;

# ----- Загрузка текстур кнопок -----
sub load_button_texture {
    my ($filename) = @_;
    my $full = button_file($filename);
    if (-f $full) {
        my $surf = IMG_Load($full);
        if ($surf) {
            my $tex = SDL_CreateTextureFromSurface($renderer, $surf);
            SDL_FreeSurface($surf);
            return $tex;
        }
    }
    my $w = 40; my $h = 28;
    if ($filename eq 'apply.png')      { $w = 52; $h = 28; }
    elsif ($filename eq 'collision.png') { $w = 60; $h = 28; }
    elsif ($filename eq 'select.png')  { $w = 46; $h = 28; }
	elsif ($filename eq 'input.png') { $w = 64; $h = 34; }
    my $s = SDL_CreateRGBSurface(0, $w, $h, 32, 0x00FF0000,0x0000FF00,0x000000FF,0xFF000000);
    my $fmt = $ffi->cast('opaque' => 'opaque', $s + 24);
    my $col = SDL_MapRGBA($fmt, 200,200,200,255);
    my $rr = pack('iiii', 0,0,$w,$h);
    SDL_FillRect($s, $ffi->cast('string' => 'opaque', $rr), $col);
    my $tex = SDL_CreateTextureFromSurface($renderer, $s);
    SDL_FreeSurface($s);
    return $tex;
}

my $btn_apply_tex     = load_button_texture('apply.png');      # 52x28
my $btn_load_tex      = load_button_texture('load.png');       # 40x28
my $btn_save_tex      = load_button_texture('save.png');       # 40x28
my $btn_tiles_tex     = load_button_texture('tiles.png');      # 40x28
my $btn_collision_tex = load_button_texture('collision.png');  # 60x28
my $btn_select_tex    = load_button_texture('select.png');     # 46x28
my $input_field_tex   = load_button_texture('input.png');      # 60x26 (поле ввода W/H)

# ----- Загрузка символов (цифры + пробел) -----
my @symbol_tex;
for my $i (1..11) {
    my $fname = sprintf("symbol%03d.png", $i);
    my $full = symbol_file($fname);
    if (-f $full) {
        my $surf = IMG_Load($full);
        if ($surf) {
            $symbol_tex[$i] = SDL_CreateTextureFromSurface($renderer, $surf);
            SDL_FreeSurface($surf);
        }
    }
}

# ----- Загрузка иконок W и H -----
my $label_w_tex = undef;
my $label_h_tex = undef;
if (-f symbol_file('W.png')) {
    my $surf = IMG_Load(symbol_file('W.png'));
    $label_w_tex = SDL_CreateTextureFromSurface($renderer, $surf) if $surf;
    SDL_FreeSurface($surf) if $surf;
}
if (-f symbol_file('H.png')) {
    my $surf = IMG_Load(symbol_file('H.png'));
    $label_h_tex = SDL_CreateTextureFromSurface($renderer, $surf) if $surf;
    SDL_FreeSurface($surf) if $surf;
}

# Отладочный вывод
print "Buttons loaded:\n";
print "  Apply:    " . ($btn_apply_tex     ? "OK" : "FAIL") . "\n";
print "  Load:     " . ($btn_load_tex      ? "OK" : "FAIL") . "\n";
print "  Save:     " . ($btn_save_tex      ? "OK" : "FAIL") . "\n";
print "  Tiles:    " . ($btn_tiles_tex     ? "OK" : "FAIL") . "\n";
print "  Collision:" . ($btn_collision_tex ? "OK" : "FAIL") . "\n";
print "  Select:   " . ($btn_select_tex    ? "OK" : "FAIL") . "\n";

# ----- Tileset loading (без изменений) -----
my $tileset_tex = undef;
my $atlas_w = 0;
my $atlas_h = 0;
my @tiles;
my $TOTAL_TILES = 0;

my $tileset_dir = asset('tileset');
my $atlas_path  = "$tileset_dir/tileset.png";

if (-f $atlas_path) {
    my $surf = IMG_Load($atlas_path);
    if ($surf) {
        $atlas_w = 3072;
        $atlas_h = 3072;
        $tileset_tex = SDL_CreateTextureFromSurface($renderer, $surf);
        SDL_FreeSurface($surf);
        $TOTAL_TILES = ($atlas_w / $TILE_SIZE) * ($atlas_h / $TILE_SIZE);
        print "Atlas loaded ($atlas_w x $atlas_h) -> $TOTAL_TILES tiles.\n";
    } else {
        print "Failed to load atlas: " . SDL_GetError() . "\n";
    }
}

unless ($tileset_tex) {
    if (-d $tileset_dir) {
        opendir(my $dh, $tileset_dir) or warn "Cannot open $tileset_dir";
        my @files = sort grep { /\.png$/i } readdir($dh);
        closedir $dh;
        foreach my $f (@files) {
            next if $f eq "tileset.png";
            my $surf = IMG_Load("$tileset_dir/$f");
            if ($surf) {
                push @tiles, SDL_CreateTextureFromSurface($renderer, $surf);
                SDL_FreeSurface($surf);
            } else { push @tiles, undef }
        }
        $TOTAL_TILES = scalar @tiles;
        print "Loaded $TOTAL_TILES individual tiles.\n";
    }
    if ($TOTAL_TILES == 0) {
        print "No tiles found, creating 4096 placeholder tiles...\n";
        @tiles = ();
        for my $i (0..4095) {
            my $s = SDL_CreateRGBSurface(0, $TILE_SIZE, $TILE_SIZE, 32, 0x00FF0000,0x0000FF00,0x000000FF,0xFF000000);
            my $fmt = $ffi->cast('opaque' => 'opaque', $s + 24);
            my $col = SDL_MapRGBA($fmt, 128,128,128,255);
            my $rr = pack('iiii', 0,0,$TILE_SIZE,$TILE_SIZE);
            SDL_FillRect($s, $ffi->cast('string' => 'opaque', $rr), $col);
            push @tiles, SDL_CreateTextureFromSurface($renderer, $s);
            SDL_FreeSurface($s);
        }
        $TOTAL_TILES = 4096;
        print "Generated 4096 placeholder tiles.\n";
    }
}

sub tile_src {
    my ($id) = @_;
    return (0, 0) if $id < 0 || !$tileset_tex;
    my $TILES_PER_STRIP = 16;
    my $STRIP_WIDTH_PX  = $TILES_PER_STRIP * $TILE_SIZE;
    my $TILES_HIGH      = 64;

    my $strip = int($id / ($TILES_PER_STRIP * $TILES_HIGH));
    my $local_id = $id % ($TILES_PER_STRIP * $TILES_HIGH);
    my $col_in_strip = $local_id % $TILES_PER_STRIP;
    my $row_in_strip = int($local_id / $TILES_PER_STRIP);

    my $src_x = $strip * $STRIP_WIDTH_PX + $col_in_strip * $TILE_SIZE;
    my $src_y = $row_in_strip * $TILE_SIZE;

    if ($src_x >= $atlas_w || $src_y >= $atlas_h) {
        return (0, 0);
    }
    return ($src_x, $src_y);
}

# ----- Map data and collision -----
my $MAP_COLS = 100;
my $MAP_ROWS = 20;
my @map;
my @collision;

# ----- Scroll states -----
my $pal_scroll_y = 0;
my $total_rows = int(($TOTAL_TILES + $PAL_COLS - 1) / $PAL_COLS);
my $pal_content_h = $total_rows * $PAL_TILE_H;
$pal_content_h = $PAL_AREA_H if $pal_content_h <= 0;
my $pal_max_scroll = $pal_content_h - $PAL_AREA_H;
$pal_max_scroll = 0 if $pal_max_scroll < 0;
my $pal_thumb_h = ($pal_content_h > 0) ? ($PAL_AREA_H / $pal_content_h) * $PAL_AREA_H : $PAL_AREA_H;
$pal_thumb_h = 16 if $pal_thumb_h < 16;
$pal_thumb_h = $PAL_AREA_H if $pal_thumb_h > $PAL_AREA_H;
my $pal_thumb_y = 0;

my $map_scroll_x = 0;
my $map_scroll_y = 0;
my $total_map_w = $MAP_COLS * $PAL_TILE_W;
my $total_map_h = $MAP_ROWS * $PAL_TILE_H;
my $map_max_scroll_x = $total_map_w - $TILE_AREA_W;
my $map_max_scroll_y = $total_map_h - $TILE_AREA_H;
$map_max_scroll_x = 0 if $map_max_scroll_x < 0;
$map_max_scroll_y = 0 if $map_max_scroll_y < 0;
my $map_thumb_w = ($total_map_w > 0) ? ($TILE_AREA_W / $total_map_w) * $TILE_AREA_W : $TILE_AREA_W;
$map_thumb_w = 16 if $map_thumb_w < 16;
$map_thumb_w = $TILE_AREA_W if $map_thumb_w > $TILE_AREA_W;
my $map_thumb_h = ($total_map_h > 0) ? ($TILE_AREA_H / $total_map_h) * $TILE_AREA_H : $TILE_AREA_H;
$map_thumb_h = 16 if $map_thumb_h < 16;
$map_thumb_h = $TILE_AREA_H if $map_thumb_h > $TILE_AREA_H;
my $map_thumb_x = 0;
my $map_thumb_y = 0;

# Interaction state
my $cur_tile_id = 1;
my $mouse_x = 0;
my $mouse_y = 0;
my $mouse_button = 0;
my $dragging_pal = 0;
my $dragging_map_x = 0;
my $dragging_map_y = 0;
my $drag_start_x = 0;
my $drag_start_y = 0;
my $drag_thumb_x = 0;
my $drag_thumb_y = 0;
my $pal_drag_start_y = 0;
my $pal_drag_thumb_y = 0;

my $input_w = "$MAP_COLS";
my $input_h = "$MAP_ROWS";
my $active_field = 0;
my $edit_mode = 0;
my $save_flash = 0;
my $save_flash_time = 0;

my $tile_area_x = $PAL_PANEL_W;
my $tile_area_y = $TOP_BAR_H;

# ----- Selection object -----
my $selection = Selection->new(
    map           => \@map,
    collision     => \@collision,
    cols          => $MAP_COLS,
    rows          => $MAP_ROWS,
    tile_size     => $TILE_SIZE,
    scale         => $SCALE,
    map_view_x    => $tile_area_x,
    map_view_y    => $tile_area_y,
    scroll_x_ref  => \$map_scroll_x,
    scroll_y_ref  => \$map_scroll_y,
    cast          => sub { $ffi->cast(@_) },
    draw_color    => \&SDL_SetRenderDrawColor,
    draw_rect     => \&SDL_RenderDrawRect,
    fill_rect     => \&SDL_RenderFillRect,
    set_blend     => \&SDL_SetRenderDrawBlendMode,
);

SDL_StartTextInput();

# ----- Map loading -----
sub load_map_from_file {
    my ($filepath) = @_;
    if (-f $filepath) {
        open(my $fh, '<', $filepath) or return;
        my @lines;
        my @new_coll;
        my $in_collision = 0;
        while (<$fh>) {
            chomp;
            s/^\s+//; s/\s+$//;
            if (/^#collision/i) { $in_collision = 1; next; }
            next if $_ eq '' || $_ =~ /^\s+$/;   # пропускаем пустые и пробельные строки
            if (!$in_collision) {
                push @lines, [split /\s+/, $_];
            } else {
                push @new_coll, [split /\s+/, $_];
            }
        }
        close $fh;

        if (@lines) {
            my $new_rows = @lines;
            my $new_cols = 0;
            for my $r (@lines) { my $c = scalar @$r; $new_cols = $c if $c > $new_cols; }
            @map = ();
            for my $r (@lines) { push @map, [@{$r}, (0) x ($new_cols - @{$r})]; }
            if (@new_coll) {
                @collision = ();
                for my $r (0..$new_rows-1) {
                    my $crow = $new_coll[$r] // [];
                    while (@$crow < $new_cols) { push @$crow, 0; }
                    push @collision, [@$crow[0..$new_cols-1]];
                }
            } else {
                @collision = ();
                for (0..$new_rows-1) { $collision[$_] = [(0) x $new_cols]; }
            }
            $MAP_ROWS = $new_rows;
            $MAP_COLS = $new_cols;
            $input_w = "$MAP_COLS";
            $input_h = "$MAP_ROWS";
            $selection->{cols} = $MAP_COLS;
            $selection->{rows} = $MAP_ROWS;
            $selection->cancel();
            recalc_scrolls();
            print "Map loaded: ${MAP_COLS}x${MAP_ROWS}\n";
            return 1;
        }
    }
    return 0;
}

sub recalc_scrolls {
    $total_map_w = $MAP_COLS * $PAL_TILE_W;
    $total_map_h = $MAP_ROWS * $PAL_TILE_H;
    $map_max_scroll_x = $total_map_w - $TILE_AREA_W;
    $map_max_scroll_y = $total_map_h - $TILE_AREA_H;
    $map_max_scroll_x = 0 if $map_max_scroll_x < 0;
    $map_max_scroll_y = 0 if $map_max_scroll_y < 0;
    $map_scroll_x = 0; $map_scroll_y = 0;
    $map_thumb_w = ($total_map_w > 0) ? ($TILE_AREA_W / $total_map_w) * $TILE_AREA_W : $TILE_AREA_W;
    $map_thumb_w = 16 if $map_thumb_w < 16;
    $map_thumb_w = $TILE_AREA_W if $map_thumb_w > $TILE_AREA_W;
    $map_thumb_h = ($total_map_h > 0) ? ($TILE_AREA_H / $total_map_h) * $TILE_AREA_H : $TILE_AREA_H;
    $map_thumb_h = 16 if $map_thumb_h < 16;
    $map_thumb_h = $TILE_AREA_H if $map_thumb_h > $TILE_AREA_H;
    $map_thumb_x = 0; $map_thumb_y = 0;
}

unless (load_map_from_file(asset('map', 'map01.txt'))) {
    @map = ();
    @collision = ();
    for (0..$MAP_ROWS-1) {
        $map[$_] = [(0) x $MAP_COLS];
        $collision[$_] = [(0) x $MAP_COLS];
    }
    recalc_scrolls();
}

# ----- Helpers -----
sub get_palette_tile_id {
    my ($mx, $my) = @_;
    my $py = $my - $TOP_BAR_H;
    return -1 if $py < 0 || $py >= $PAL_AREA_H;
    my $cy = $py + $pal_scroll_y;
    my $col = int($mx / $PAL_TILE_W);
    my $row = int($cy / $PAL_TILE_H);
    return -1 if $col < 0 || $col >= $PAL_COLS || $row < 0;

    my $block_w = 16;
    my $block_h = 64;
    my $tiles_per_block = $block_w * $block_h;
    my $global_row = $row;
    my $block = int($global_row / $block_h);
    my $row_in_block = $global_row % $block_h;
    my $id = $block * $tiles_per_block + $row_in_block * $block_w + $col;
    return ($id < $TOTAL_TILES) ? $id : -1;
}

sub set_collision_cell {
    my ($sx, $sy, $value) = @_;
    my $rel_x = $sx - $tile_area_x + $map_scroll_x;
    my $rel_y = $sy - $tile_area_y + $map_scroll_y;
    my $col = int($rel_x / $PAL_TILE_W);
    my $row = int($rel_y / $PAL_TILE_H);
    if ($row>=0 && $row<$MAP_ROWS && $col>=0 && $col<$MAP_COLS) {
        $collision[$row][$col] = $value;
    }
}

sub paint_map_cell {
    my ($sx, $sy, $tid) = @_;
    return if $edit_mode;
    my $rel_x = $sx - $tile_area_x + $map_scroll_x;
    my $rel_y = $sy - $tile_area_y + $map_scroll_y;
    my $col = int($rel_x / $PAL_TILE_W);
    my $row = int($rel_y / $PAL_TILE_H);
    if ($row>=0 && $row<$MAP_ROWS && $col>=0 && $col<$MAP_COLS) {
        $map[$row][$col] = $tid;
    }
}

sub save_map {
    my $save_file = asset('map', 'map01.txt');
    my $dir = dirname($save_file);
    mkdir $dir unless -d $dir;
    open(my $fh, '>', $save_file) or warn "Cannot save $save_file: $!";
    return unless $fh;
    for my $row (@map) { print $fh join(' ', @$row), "\n"; }
    print $fh "\n#collision\n";
    for my $row (@collision) { print $fh join(' ', @$row), "\n"; }
    close $fh;
    print "Map saved to $save_file\n";
}

sub resize_map {
    my ($new_w, $new_h) = @_;
    $new_w = 1 if $new_w < 1;
    $new_h = 1 if $new_h < 1;
    my @new_map;
    my @new_coll;
    for my $r (0..$new_h-1) {
        my @new_row;
        my @new_crow;
        for my $c (0..$new_w-1) {
            push @new_row, ($r < $MAP_ROWS && $c < $MAP_COLS) ? $map[$r][$c] : 0;
            push @new_crow, ($r < $MAP_ROWS && $c < $MAP_COLS) ? $collision[$r][$c] : 0;
        }
        push @new_map, \@new_row;
        push @new_coll, \@new_crow;
    }
    @map = @new_map;
    @collision = @new_coll;
    $MAP_COLS = $new_w;
    $MAP_ROWS = $new_h;
    $input_w = "$MAP_COLS";
    $input_h = "$MAP_ROWS";
    $selection->{cols} = $MAP_COLS;
    $selection->{rows} = $MAP_ROWS;
    $selection->cancel();
    recalc_scrolls();
    print "Map size changed to ${MAP_COLS}x${MAP_ROWS}\n";
}

# ----- Функция отрисовки символа по символу (1=пробел, 2..11=0..9) -----
sub draw_symbol {
    my ($ch, $x, $y) = @_;
    my $idx;
    if ($ch eq ' ') { $idx = 1; }
    elsif ($ch =~ /^\d$/) { $idx = 2 + int($ch); }
    else { return; }
    return if !$symbol_tex[$idx];
    SDL_RenderCopy($renderer, $symbol_tex[$idx], undef,
        $ffi->cast('string'=>'opaque', pack('iiii', $x, $y, 20, 32)));
}

# ----- Main loop -----
my $event_ptr = malloc(56);
my $src_rect = malloc(16);
my $dst_rect = malloc(16);
my $running = 1;
print "Editor started. B=toggle collision, S=toggle select.\n";

# ----- Параметры кнопок (новые) -----
my $BTN_TOP = 26;
my $BTN_H   = 28;
my $LEFT_MARGIN = 20;
my $GAP = 12;

my $btn1_x = $LEFT_MARGIN;                    # Apply 52
my $btn2_x = $btn1_x + 52 + $GAP;             # Load  40
my $btn3_x = $btn2_x + 40 + $GAP;             # Save  40
my $btn4_x = $btn3_x + 40 + $GAP;             # Tiles 40
my $btn5_x = $btn4_x + 40 + $GAP;             # Collision 60
my $btn6_x = $btn5_x + 60 + $GAP;             # Select 46

while ($running) {
    my $event_str = "\0" x 56;
    my $estr_ptr = $ffi->cast('string' => 'opaque', $event_str);
    while (SDL_PollEvent($event_ptr)) {
        memcpy($estr_ptr, $event_ptr, 56);
        my $type = unpack('V', substr($event_str, 0, 4));

        if ($type == 0x100) { $running = 0; }
        elsif ($type == 0x303) {
            my $text = unpack('Z*', substr($event_str, 12, 32));
        if ($text =~ /^\d$/ && $active_field) {
        if ($active_field == 1 && length($input_w) < 3) { $input_w .= $text; }
           elsif ($active_field == 2 && length($input_h) < 3) { $input_h .= $text; }
           }
        }
        elsif ($type == 0x400) {   # Mouse motion
            $mouse_x = unpack('V', substr($event_str, 20, 4));
            $mouse_y = unpack('V', substr($event_str, 24, 4));
            if ($dragging_pal) {
                my $dy = $mouse_y - $pal_drag_start_y;
                my $max_t = $PAL_AREA_H - $pal_thumb_h;
                my $new_t = $pal_drag_thumb_y + $dy;
                $new_t = 0 if $new_t<0; $new_t = $max_t if $new_t>$max_t;
                $pal_scroll_y = ($max_t>0 && $pal_max_scroll>0) ? int(($new_t/$max_t)*$pal_max_scroll) : 0;
                $pal_thumb_y = $new_t;
            }
            if ($dragging_map_x) {
                my $dx = $mouse_x - $drag_start_x;
                my $max_t = $TILE_AREA_W - $map_thumb_w;
                my $new_t = $drag_thumb_x + $dx;
                $new_t = 0 if $new_t<0; $new_t = $max_t if $new_t>$max_t;
                $map_scroll_x = ($max_t>0 && $map_max_scroll_x>0) ? int(($new_t/$max_t)*$map_max_scroll_x) : 0;
                $map_thumb_x = $new_t;
            }
            if ($dragging_map_y) {
                my $dy = $mouse_y - $drag_start_y;
                my $max_t = $TILE_AREA_H - $map_thumb_h;
                my $new_t = $drag_thumb_y + $dy;
                $new_t = 0 if $new_t<0; $new_t = $max_t if $new_t>$max_t;
                $map_scroll_y = ($max_t>0 && $map_max_scroll_y>0) ? int(($new_t/$max_t)*$map_max_scroll_y) : 0;
                $map_thumb_y = $new_t;
            }
            if ($selection->{selecting}) {
                $selection->update_selection($mouse_x, $mouse_y);
            }
            if ($selection->{paste_active}) {
                $selection->update_paste_preview($mouse_x, $mouse_y);
            }
            if ($selection->{palette_selecting}) {
                my $py = $mouse_y - $TOP_BAR_H;
                my $cy_pal = $py + $pal_scroll_y;
                my $pal_col = int($mouse_x / $PAL_TILE_W);
                my $pal_row = int($cy_pal / $PAL_TILE_H);
                $pal_col = 0 if $pal_col < 0;
                $pal_col = $PAL_COLS - 1 if $pal_col >= $PAL_COLS;
                $pal_row = 0 if $pal_row < 0;
                $selection->update_palette_selection($pal_col, $pal_row);
            }
            if (($mouse_button==1 || $mouse_button==3) && !$selection->{active} && !$selection->{paste_active}
                && $mouse_x>=$tile_area_x && $mouse_y>=$tile_area_y
                && $mouse_x<$tile_area_x+$TILE_AREA_W && $mouse_y<$tile_area_y+$TILE_AREA_H) {
                if ($edit_mode == 0) {
                    my $tid = ($mouse_button==1)? $cur_tile_id : 0;
                    paint_map_cell($mouse_x, $mouse_y, $tid);
                } else {
                    if ($mouse_button == 1) { set_collision_cell($mouse_x, $mouse_y, 0); }
                    elsif ($mouse_button == 3) { set_collision_cell($mouse_x, $mouse_y, 1); }
                }
            }
        }
        elsif ($type == 0x401) {   # Mouse button down
            my $btn = unpack('C', substr($event_str, 16, 1));
            $mouse_button = $btn;
            my $cx = unpack('V', substr($event_str, 20, 4));
            my $cy = unpack('V', substr($event_str, 24, 4));
            $mouse_x = $cx; $mouse_y = $cy;

            # ----- Верхняя панель с новыми кнопками -----
            if ($cy >= $BTN_TOP && $cy <= $BTN_TOP + $BTN_H) {
                # Apply (52x28)
                if ($cx >= $btn1_x && $cx <= $btn1_x + 52) {
                    resize_map(int($input_w) || $MAP_COLS, int($input_h) || $MAP_ROWS);
                    next;
                }
                # Load (40x28)
                if ($cx >= $btn2_x && $cx <= $btn2_x + 40) {
                    load_map_from_file(asset('map', 'map01.txt'));
                    next;
                }
                # Save (40x28)
                if ($cx >= $btn3_x && $cx <= $btn3_x + 40) {
                    save_map();
                    $save_flash = 1;
                    $save_flash_time = time();
                    next;
                }
                # Tiles (40x28)
                if ($cx >= $btn4_x && $cx <= $btn4_x + 40) {
                    $edit_mode = 0;
                    print "Mode: Tiles\n";
                    next;
                }
                # Collision (60x28)
                if ($cx >= $btn5_x && $cx <= $btn5_x + 60) {
                    $edit_mode = 1;
                    print "Mode: Collision\n";
                    next;
                }
                # Select (46x28)
                if ($cx >= $btn6_x && $cx <= $btn6_x + 46) {
                    $selection->toggle_select_mode();
                    print "Select mode: " . ($selection->{active} ? "ON" : "OFF") . "\n";
                    next;
                }
            }

            # Поля W/H
            my $fields_top = 54;
            if ($cy >= $fields_top && $cy <= $fields_top + 26) {
            if ($cx >= 380 && $cx <= 460) { $active_field = 1; next; }   # W: (подпись + поле)
            if ($cx >= 470 && $cx <= 550) { $active_field = 2; next; }   # H: (подпись + поле)
            }

            # Palette click
            if ($cx<$PAL_WIDTH && $cy>=$TOP_BAR_H) {
                if ($selection->{active} && !$edit_mode) {
                    my $py = $cy - $TOP_BAR_H;
                    my $cy_pal = $py + $pal_scroll_y;
                    my $pal_col = int($cx / $PAL_TILE_W);
                    my $pal_row = int($cy_pal / $PAL_TILE_H);
                    if ($pal_col >= 0 && $pal_col < $PAL_COLS && $pal_row >= 0) {
                        $selection->start_palette_selection($pal_col, $pal_row);
                    }
                } else {
                    my $id = get_palette_tile_id($cx, $cy);
                    if ($id>=0) { $cur_tile_id = $id; print "Tile $id\n"; }
                }
                next;
            }

            # Palette scrollbar
            if ($cx>=$PAL_WIDTH && $cx<=$PAL_PANEL_W && $cy>=$TOP_BAR_H && $cy<=$TOP_BAR_H+$PAL_AREA_H) {
                my $ly = $cy - $TOP_BAR_H;
                if ($ly < $pal_thumb_y) { $pal_scroll_y -= $PAL_AREA_H; }
                elsif ($ly > $pal_thumb_y+$pal_thumb_h) { $pal_scroll_y += $PAL_AREA_H; }
                else { $dragging_pal=1; $pal_drag_start_y=$cy; $pal_drag_thumb_y=$pal_thumb_y; }
                $pal_scroll_y = 0 if $pal_scroll_y<0; $pal_scroll_y = $pal_max_scroll if $pal_scroll_y>$pal_max_scroll;
                my $max_t = $PAL_AREA_H - $pal_thumb_h;
                $pal_thumb_y = ($pal_max_scroll>0 && $max_t>0) ? int(($pal_scroll_y/$pal_max_scroll)*$max_t) : 0;
                next;
            }

            # Horizontal map scrollbar
            if ($cy >= $tile_area_y+$TILE_AREA_H && $cy <= $tile_area_y+$TILE_AREA_H+$SCROLLBAR_W &&
                $cx >= $tile_area_x && $cx <= $tile_area_x+$TILE_AREA_W) {
                my $lx = $cx - $tile_area_x;
                if ($lx < $map_thumb_x) { $map_scroll_x -= $TILE_AREA_W; }
                elsif ($lx > $map_thumb_x+$map_thumb_w) { $map_scroll_x += $TILE_AREA_W; }
                else { $dragging_map_x=1; $drag_start_x=$cx; $drag_thumb_x=$map_thumb_x; }
                $map_scroll_x = 0 if $map_scroll_x<0; $map_scroll_x = $map_max_scroll_x if $map_scroll_x>$map_max_scroll_x;
                my $max_t = $TILE_AREA_W - $map_thumb_w;
                $map_thumb_x = ($map_max_scroll_x>0 && $max_t>0) ? int(($map_scroll_x/$map_max_scroll_x)*$max_t) : 0;
                next;
            }

            # Vertical map scrollbar
            if ($cx >= $tile_area_x+$TILE_AREA_W && $cx <= $tile_area_x+$TILE_AREA_W+$SCROLLBAR_W &&
                $cy >= $tile_area_y && $cy <= $tile_area_y+$TILE_AREA_H) {
                my $ly = $cy - $tile_area_y;
                if ($ly < $map_thumb_y) { $map_scroll_y -= $TILE_AREA_H; }
                elsif ($ly > $map_thumb_y+$map_thumb_h) { $map_scroll_y += $TILE_AREA_H; }
                else { $dragging_map_y=1; $drag_start_y=$cy; $drag_thumb_y=$map_thumb_y; }
                $map_scroll_y = 0 if $map_scroll_y<0; $map_scroll_y = $map_max_scroll_y if $map_scroll_y>$map_max_scroll_y;
                my $max_t = $TILE_AREA_H - $map_thumb_h;
                $map_thumb_y = ($map_max_scroll_y>0 && $max_t>0) ? int(($map_scroll_y/$map_max_scroll_y)*$max_t) : 0;
                next;
            }

            # Map area (рисование)
            if ($cx>=$tile_area_x && $cx<=$tile_area_x+$TILE_AREA_W && $cy>=$tile_area_y && $cy<=$tile_area_y+$TILE_AREA_H) {
                if ($selection->{paste_active} && $btn == 1 && !$edit_mode) {
                    $selection->paste_confirm();
                    next;
                }
                if (($selection->{active} || $selection->{paste_active}) && $btn == 3) {
                    $selection->cancel();
                    next;
                }
                if ($selection->{active} && $btn == 1 && !$edit_mode) {
                    $selection->start_selection($cx, $cy);
                    next;
                }
                if (!$selection->{active} && !$selection->{paste_active}) {
                    if ($edit_mode == 0) {
                        my $tid = ($btn==1)? $cur_tile_id : ($btn==3?0:-1);
                        if ($tid>=0) { paint_map_cell($cx, $cy, $tid); }
                    } else {
                        if ($btn == 1) { set_collision_cell($cx, $cy, 0); }
                        elsif ($btn == 3) { set_collision_cell($cx, $cy, 1); }
                    }
                }
            }
        }
        elsif ($type == 0x402) {   # Mouse button up
            $mouse_button=0;
            $dragging_pal=0;
            $dragging_map_x=0;
            $dragging_map_y=0;
            if ($selection->{selecting}) {
                $selection->finish_selection();
            }
            if ($selection->{palette_selecting}) {
                $selection->finish_palette_selection();
            }
        }
        elsif ($type == 0x700) {   # Mouse wheel
            my $wx = unpack('l', substr($event_str, 16, 4));
            my $wy = unpack('l', substr($event_str, 20, 4));
            if ($mouse_x>=$tile_area_x && $mouse_x<=$tile_area_x+$TILE_AREA_W &&
                $mouse_y>=$tile_area_y && $mouse_y<=$tile_area_y+$TILE_AREA_H) {
                $map_scroll_x -= $wx*32;
                $map_scroll_y -= $wy*32;
                $map_scroll_x = 0 if $map_scroll_x<0; $map_scroll_x = $map_max_scroll_x if $map_scroll_x>$map_max_scroll_x;
                $map_scroll_y = 0 if $map_scroll_y<0; $map_scroll_y = $map_max_scroll_y if $map_scroll_y>$map_max_scroll_y;
                my $mtx = $TILE_AREA_W-$map_thumb_w;
                $map_thumb_x = ($map_max_scroll_x>0 && $mtx>0) ? int(($map_scroll_x/$map_max_scroll_x)*$mtx) : 0;
                my $mty = $TILE_AREA_H-$map_thumb_h;
                $map_thumb_y = ($map_max_scroll_y>0 && $mty>0) ? int(($map_scroll_y/$map_max_scroll_y)*$mty) : 0;
            } else {
                $pal_scroll_y -= $wy*24;
                $pal_scroll_y = 0 if $pal_scroll_y<0; $pal_scroll_y = $pal_max_scroll if $pal_scroll_y>$pal_max_scroll;
                my $max_t = $PAL_AREA_H-$pal_thumb_h;
                $pal_thumb_y = ($pal_max_scroll>0 && $max_t>0) ? int(($pal_scroll_y/$pal_max_scroll)*$max_t) : 0;
            }
        }
        elsif ($type == 0x300) {   # Key down
            my $key = unpack('V', substr($event_str, 20, 4));
            my $mod_state = SDL_GetModState();

            if ($key == 27) {
                if ($selection->{active} || $selection->{paste_active}) {
                    $selection->cancel();
                } else {
                    $running = 0;
                }
            }
            elsif ($key == 13) { resize_map(int($input_w) || $MAP_COLS, int($input_h) || $MAP_ROWS); }
            elsif ($key == 8)  {
                if ($active_field == 1) { chop($input_w); }
                elsif ($active_field == 2) { chop($input_h); }
            }
            elsif ($key == 115) { $selection->toggle_select_mode(); }
            elsif ($key == 98)  { $edit_mode = 1 - $edit_mode; }

            if ($key == 99 && ($mod_state & 0x40) && !$edit_mode) {
                $selection->copy();
                next;
            }
            if ($key == 118 && ($mod_state & 0x40) && !$edit_mode) {
                $selection->start_paste();
                next;
            }
        }
    }

    # Непрерывное рисование при зажатой кнопке
    if (($mouse_button==1||$mouse_button==3) && !$selection->{active} && !$selection->{paste_active}
        && $mouse_x>=$tile_area_x && $mouse_y>=$tile_area_y
        && $mouse_x<$tile_area_x+$TILE_AREA_W && $mouse_y<$tile_area_y+$TILE_AREA_H) {
        if ($edit_mode == 0) {
            my $tid = ($mouse_button==1)? $cur_tile_id : 0;
            paint_map_cell($mouse_x, $mouse_y, $tid);
        } else {
            if ($mouse_button == 1) { set_collision_cell($mouse_x, $mouse_y, 0); }
            elsif ($mouse_button == 3) { set_collision_cell($mouse_x, $mouse_y, 1); }
        }
    }

    if ($save_flash && time() - $save_flash_time >= 0.5) {
        $save_flash = 0;
    }

    # ----- RENDER -----
    SDL_SetRenderDrawColor($renderer, 40,40,40,255);
    SDL_RenderClear($renderer);

    # Верхняя панель
    my $top_rect = pack('iiii', 0,0,$WIN_W,$TOP_BAR_H);
    SDL_SetRenderDrawColor($renderer, 55,55,65,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque',$top_rect));
    SDL_SetRenderDrawColor($renderer, 100,100,120,255);
    SDL_RenderDrawRect($renderer, $ffi->cast('string'=>'opaque',$top_rect));

    # Кнопки-картинки
    my $by = $BTN_TOP;
    SDL_RenderCopy($renderer, $btn_apply_tex,     undef, $ffi->cast('string'=>'opaque', pack('iiii', $btn1_x, $by, 52, $BTN_H)));
    SDL_RenderCopy($renderer, $btn_load_tex,      undef, $ffi->cast('string'=>'opaque', pack('iiii', $btn2_x, $by, 40, $BTN_H)));
    SDL_RenderCopy($renderer, $btn_save_tex,      undef, $ffi->cast('string'=>'opaque', pack('iiii', $btn3_x, $by, 40, $BTN_H)));
    SDL_RenderCopy($renderer, $btn_tiles_tex,     undef, $ffi->cast('string'=>'opaque', pack('iiii', $btn4_x, $by, 40, $BTN_H)));
    SDL_RenderCopy($renderer, $btn_collision_tex, undef, $ffi->cast('string'=>'opaque', pack('iiii', $btn5_x, $by, 60, $BTN_H)));
    SDL_RenderCopy($renderer, $btn_select_tex,    undef, $ffi->cast('string'=>'opaque', pack('iiii', $btn6_x, $by, 46, $BTN_H)));

    # Эффект нажатия: затемнение кнопки при зажатой ЛКМ
    if ($mouse_button == 1) {
        my ($bx, $bw) = (-1, 0);
        if ($mouse_y >= $BTN_TOP && $mouse_y <= $BTN_TOP + $BTN_H) {
            if ($mouse_x >= $btn1_x && $mouse_x <= $btn1_x + 52)      { ($bx, $bw) = ($btn1_x, 52); }
            elsif ($mouse_x >= $btn2_x && $mouse_x <= $btn2_x + 40)   { ($bx, $bw) = ($btn2_x, 40); }
            elsif ($mouse_x >= $btn3_x && $mouse_x <= $btn3_x + 40)   { ($bx, $bw) = ($btn3_x, 40); }
            elsif ($mouse_x >= $btn4_x && $mouse_x <= $btn4_x + 40)   { ($bx, $bw) = ($btn4_x, 40); }
            elsif ($mouse_x >= $btn5_x && $mouse_x <= $btn5_x + 60)   { ($bx, $bw) = ($btn5_x, 60); }
            elsif ($mouse_x >= $btn6_x && $mouse_x <= $btn6_x + 46)   { ($bx, $bw) = ($btn6_x, 46); }
        }
        if ($bx != -1) {
            SDL_SetRenderDrawBlendMode($renderer, 1);
            SDL_SetRenderDrawColor($renderer, 0, 0, 0, 80);
            my $press_rect = pack('iiii', $bx, $BTN_TOP, $bw, $BTN_H);
            SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $press_rect));
            SDL_SetRenderDrawBlendMode($renderer, 0);
        }
    }

    # Подсветка активных режимов
    if (!$edit_mode) {
        SDL_SetRenderDrawColor($renderer, 100, 255, 100, 255);
        my $r = pack('iiii', $btn4_x-2, $BTN_TOP-2, 44, $BTN_H+4);
        SDL_RenderDrawRect($renderer, $ffi->cast('string'=>'opaque', $r));
    }
    if ($edit_mode) {
        SDL_SetRenderDrawColor($renderer, 255, 100, 100, 255);
        my $r = pack('iiii', $btn5_x-2, $BTN_TOP-2, 64, $BTN_H+4);
        SDL_RenderDrawRect($renderer, $ffi->cast('string'=>'opaque', $r));
    }
    if ($selection->{active}) {
        SDL_SetRenderDrawColor($renderer, 100, 255, 100, 255);
        my $r = pack('iiii', $btn6_x-2, $BTN_TOP-2, 50, $BTN_H+4);
        SDL_RenderDrawRect($renderer, $ffi->cast('string'=>'opaque', $r));
    }

    my $fw = 64; my $fh = 34;
    my $fields_y = 54;          # чуть выше, ровно под кнопками

    # Подписи W: и H: (теперь PNG-файлы W.png и H.png)
    if ($label_w_tex) {
        SDL_RenderCopy($renderer, $label_w_tex, undef,
            $ffi->cast('string'=>'opaque', pack('iiii', 380, $fields_y, 20, 20)));
    }
    if ($label_h_tex) {
        SDL_RenderCopy($renderer, $label_h_tex, undef,
            $ffi->cast('string'=>'opaque', pack('iiii', 470, $fields_y, 20, 20)));
    }

    # Поле W (фон input.png + символы)
    my $rect_w = pack('iiii', 400, $fields_y, $fw, $fh);
    SDL_RenderCopy($renderer, $input_field_tex, undef, $ffi->cast('string'=>'opaque', $rect_w));
    if ($active_field == 1) {
        SDL_SetRenderDrawColor($renderer, 0,200,0,255);
        SDL_RenderDrawRect($renderer, $ffi->cast('string'=>'opaque',$rect_w));
    }
    {
        my $str = $input_w;
        $str = " " if $str eq "";
        my @chars = split //, $str;
        my $sx = 402;
        for my $ch (@chars) {
            draw_symbol($ch, $sx, $fields_y + 1);
            $sx += 20;
        }
    }

    # Поле H (фон input.png + символы)
    my $rect_h = pack('iiii', 490, $fields_y, $fw, $fh);
    SDL_RenderCopy($renderer, $input_field_tex, undef, $ffi->cast('string'=>'opaque', $rect_h));
    if ($active_field == 2) {
        SDL_SetRenderDrawColor($renderer, 0,200,0,255);
        SDL_RenderDrawRect($renderer, $ffi->cast('string'=>'opaque',$rect_h));
    }
    {
        my $str = $input_h;
        $str = " " if $str eq "";
        my @chars = split //, $str;
        my $sx = 492;
        for my $ch (@chars) {
            draw_symbol($ch, $sx, $fields_y + 1);
            $sx += 20;
        }
    }

    # ---------- ПАЛИТРА ----------
    my $pal_y0 = $TOP_BAR_H;
    my $pal_bg = pack('iiii', 0, $pal_y0, $PAL_WIDTH, $PAL_AREA_H);
    SDL_SetRenderDrawColor($renderer, 45,45,50,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $pal_bg));

    my $block_w = 16;
    my $block_h = 64;
    my $tiles_per_block = $block_w * $block_h;
    my $total_rows_in_palette = 256;
    my $scroll_row = int($pal_scroll_y / $PAL_TILE_H);
    my $vis_rows   = int($PAL_AREA_H / $PAL_TILE_H) + 2;

    for my $r (0 .. $vis_rows) {
        my $global_row = $scroll_row + $r;
        last if $global_row >= $total_rows_in_palette;
        my $block = int($global_row / $block_h);
        my $row_in_block = $global_row % $block_h;
        for my $col_in_block (0 .. $block_w - 1) {
            my $id = $block * $tiles_per_block + $row_in_block * $block_w + $col_in_block;
            next if $id >= $TOTAL_TILES;

            my $col_palette = $col_in_block;
            my $dx = $col_palette * $PAL_TILE_W;
            my $dy = $pal_y0 + ($r * $PAL_TILE_H) - ($pal_scroll_y % $PAL_TILE_H);

            my $dst_pack = pack('iiii', $dx, $dy, $PAL_TILE_W, $PAL_TILE_H);
            memcpy($dst_rect, $ffi->cast('string'=>'opaque', $dst_pack), 16);

            if ($tileset_tex) {
                my ($sx, $sy) = tile_src($id);
                my $src_pack = pack('iiii', $sx, $sy, $TILE_SIZE, $TILE_SIZE);
                memcpy($src_rect, $ffi->cast('string'=>'opaque', $src_pack), 16);
                SDL_RenderCopy($renderer, $tileset_tex, $src_rect, $dst_rect);
            }

            if ($id == $cur_tile_id) {
                SDL_SetRenderDrawColor($renderer, 255, 255, 0, 255);
                SDL_RenderDrawRect($renderer, $dst_rect);
            }
        }
    }

    # Скроллбар палитры
    my $ptrack = pack('iiii', $PAL_WIDTH, $pal_y0, $SCROLLBAR_W, $PAL_AREA_H);
    SDL_SetRenderDrawColor($renderer,70,70,70,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $ptrack));
    if ($pal_max_scroll > 0) {
        my $pthumb = pack('iiii', $PAL_WIDTH, $pal_y0 + $pal_thumb_y, $SCROLLBAR_W, $pal_thumb_h);
        SDL_SetRenderDrawColor($renderer,150,150,150,255);
        SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $pthumb));
    }

    # ----- Область карты -----
    my $map_bg = pack('iiii', $tile_area_x, $tile_area_y, $MAP_VIEW_W, $MAP_VIEW_H);
    SDL_SetRenderDrawColor($renderer, 0,0,0,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $map_bg));

    my $tw = $PAL_TILE_W;
    my $th = $PAL_TILE_H;

    if ($edit_mode) {
        my $c0_bg = int($map_scroll_x / $tw);
        my $r0_bg = int($map_scroll_y / $th);
        my $c1_bg = int(($map_scroll_x + $TILE_AREA_W - 1) / $tw);
        my $r1_bg = int(($map_scroll_y + $TILE_AREA_H - 1) / $th);
        $c1_bg = $MAP_COLS - 1 if $c1_bg >= $MAP_COLS;
        $r1_bg = $MAP_ROWS - 1 if $r1_bg >= $MAP_ROWS;
        for my $row ($r0_bg .. $r1_bg) {
            for my $col ($c0_bg .. $c1_bg) {
                my $dx = $tile_area_x + $col * $tw - $map_scroll_x;
                my $dy = $tile_area_y + $row * $th - $map_scroll_y;
                my $color = (($row + $col) % 2 == 0) ? 180 : 140;
                my $cell = pack('iiii', $dx, $dy, $tw, $th);
                SDL_SetRenderDrawColor($renderer, $color, $color, $color, 255);
                SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $cell));
            }
        }
    } else {
        my $tile_area_rect = pack('iiii', $tile_area_x, $tile_area_y, $TILE_AREA_W, $TILE_AREA_H);
        SDL_SetRenderDrawColor($renderer, 25, 25, 70, 255);
        SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque', $tile_area_rect));
    }

    my $c0 = int($map_scroll_x / $tw);
    my $c1 = int(($map_scroll_x + $TILE_AREA_W - 1) / $tw);
    my $r0 = int($map_scroll_y / $th);
    my $r1 = int(($map_scroll_y + $TILE_AREA_H - 1) / $th);
    $c1 = $MAP_COLS - 1 if $c1 >= $MAP_COLS;
    $r1 = $MAP_ROWS - 1 if $r1 >= $MAP_ROWS;

    for my $row ($r0 .. $r1) {
        for my $col ($c0 .. $c1) {
            my $id = $map[$row][$col];
            my $dx = $tile_area_x + $col * $tw - $map_scroll_x;
            my $dy = $tile_area_y + $row * $th - $map_scroll_y;
            my $dst_pack = pack('iiii', $dx, $dy, $tw, $th);
            memcpy($dst_rect, $ffi->cast('string'=>'opaque', $dst_pack), 16);

            if (!$edit_mode && $id > 0) {
                if ($tileset_tex) {
                    my ($sx, $sy) = tile_src($id);
                    my $src_pack = pack('iiii', $sx, $sy, $TILE_SIZE, $TILE_SIZE);
                    memcpy($src_rect, $ffi->cast('string'=>'opaque', $src_pack), 16);
                    SDL_RenderCopy($renderer, $tileset_tex, $src_rect, $dst_rect);
                } else {
                    if ($tiles[$id]) { SDL_RenderCopy($renderer, $tiles[$id], undef, $dst_rect); }
                }
            }

            if ($collision[$row][$col] == 1) {
                SDL_SetRenderDrawColor($renderer, 255, 0, 0, 220);
                SDL_RenderDrawLine($renderer, $dx+2, $dy+2, $dx+$tw-2, $dy+$th-2);
                SDL_RenderDrawLine($renderer, $dx+$tw-2, $dy+2, $dx+2, $dy+$th-2);
            } elsif ($edit_mode && $collision[$row][$col] == 0) {
                SDL_SetRenderDrawColor($renderer, 0, 200, 0, 220);
                my $x1 = $dx + 4;
                my $y1 = $dy + $th/2;
                my $x2 = $dx + $tw/2;
                my $y2 = $dy + $th - 4;
                my $x3 = $dx + $tw - 4;
                my $y3 = $dy + 4;
                SDL_RenderDrawLine($renderer, $x1, $y1, $x2, $y2);
                SDL_RenderDrawLine($renderer, $x2, $y2, $x3, $y3);
            }
        }
    }

    # Сетка
    if (!$edit_mode) {
        SDL_SetRenderDrawColor($renderer,80,80,80,100);
        for (my $c=$c0; $c<=$c1+1; $c++) {
            my $x = $tile_area_x + $c*$tw - $map_scroll_x;
            next if $x<$tile_area_x || $x>$tile_area_x+$TILE_AREA_W;
            SDL_RenderDrawLine($renderer,$x,$tile_area_y,$x,$tile_area_y+$TILE_AREA_H);
        }
        for (my $r=$r0; $r<=$r1+1; $r++) {
            my $y = $tile_area_y + $r*$th - $map_scroll_y;
            next if $y<$tile_area_y || $y>$tile_area_y+$TILE_AREA_H;
            SDL_RenderDrawLine($renderer,$tile_area_x,$y,$tile_area_x+$TILE_AREA_W,$y);
        }
    }

    # Скроллбары карты
    my $htrack = pack('iiii', $tile_area_x, $tile_area_y+$TILE_AREA_H, $TILE_AREA_W, $SCROLLBAR_W);
    SDL_SetRenderDrawColor($renderer,70,70,70,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque',$htrack));
    my $hthumb = pack('iiii', $tile_area_x+$map_thumb_x, $tile_area_y+$TILE_AREA_H, $map_thumb_w, $SCROLLBAR_W);
    SDL_SetRenderDrawColor($renderer,150,150,150,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque',$hthumb));

    my $vtrack = pack('iiii', $tile_area_x+$TILE_AREA_W, $tile_area_y, $SCROLLBAR_W, $TILE_AREA_H);
    SDL_SetRenderDrawColor($renderer,70,70,70,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque',$vtrack));
    my $vthumb = pack('iiii', $tile_area_x+$TILE_AREA_W, $tile_area_y+$map_thumb_y, $SCROLLBAR_W, $map_thumb_h);
    SDL_SetRenderDrawColor($renderer,150,150,150,255);
    SDL_RenderFillRect($renderer, $ffi->cast('string'=>'opaque',$vthumb));

    # Выделение
    $selection->render($renderer, $tile_area_x, $tile_area_y, $tw, $th,
                       0, $TOP_BAR_H, $PAL_TILE_W, $PAL_TILE_H, $pal_scroll_y);

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

# Cleanup
SDL_StopTextInput();
if ($tileset_tex) { SDL_DestroyTexture($tileset_tex); }
foreach my $t (@tiles) { SDL_DestroyTexture($t) if $t; }
TTF_CloseFont($font24);
TTF_CloseFont($font16);
TTF_CloseFont($font12);
TTF_Quit();
free($src_rect);
free($dst_rect);
free($event_ptr);

SDL_DestroyTexture($btn_apply_tex)     if $btn_apply_tex;
SDL_DestroyTexture($btn_load_tex)      if $btn_load_tex;
SDL_DestroyTexture($btn_save_tex)      if $btn_save_tex;
SDL_DestroyTexture($btn_tiles_tex)     if $btn_tiles_tex;
SDL_DestroyTexture($btn_collision_tex) if $btn_collision_tex;
SDL_DestroyTexture($btn_select_tex)    if $btn_select_tex;
SDL_DestroyTexture($input_field_tex) if $input_field_tex;
foreach my $tex (@symbol_tex) {
    SDL_DestroyTexture($tex) if $tex;
}
SDL_DestroyTexture($label_w_tex) if $label_w_tex;
SDL_DestroyTexture($label_h_tex) if $label_h_tex;

SDL_DestroyRenderer($renderer);
SDL_DestroyWindow($window);
SDL_Quit();
print "Editor closed.\n";