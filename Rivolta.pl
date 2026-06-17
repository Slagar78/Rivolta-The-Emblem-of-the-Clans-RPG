#!/usr/bin/perl
use strict;
use warnings;
use Config;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/lib";

use FFI::Platypus;
use FFI::Platypus::Memory qw(malloc free memcpy);
use Player;
use Menu;
use StatusMenu;
use Camera;
use Rain;
use Intro;
use TextRenderer;
use TOML::Tiny qw(from_toml);

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib('SDL2');
$ffi->lib('SDL2_image');
$ffi->lib('SDL2_mixer');
$ffi->lib('SDL2_ttf');

$ffi->attach( SDL_Init               => ['uint'] => 'int' );
$ffi->attach( SDL_GetError           => []       => 'string' );
$ffi->attach( SDL_CreateWindow       => ['string','int','int','int','int','uint'] => 'opaque' );
$ffi->attach( SDL_CreateRenderer     => ['opaque','int','uint'] => 'opaque' );
$ffi->attach( SDL_DestroyRenderer    => ['opaque'] => 'void' );
$ffi->attach( SDL_DestroyWindow      => ['opaque'] => 'void' );
$ffi->attach( SDL_Quit               => [] => 'void' );
$ffi->attach( SDL_SetRenderDrawColor => ['opaque','uint8','uint8','uint8','uint8'] => 'int' );
$ffi->attach( SDL_RenderClear        => ['opaque'] => 'int' );
$ffi->attach( SDL_RenderCopyEx => ['opaque','opaque','opaque','opaque','double','opaque','int'] => 'int' );
$ffi->attach( SDL_RenderDrawLine => ['opaque','int','int','int','int'] => 'int' );
$ffi->attach( SDL_RenderCopy         => ['opaque','opaque','opaque','opaque'] => 'int' );
$ffi->attach( SDL_RenderPresent      => ['opaque'] => 'void' );
$ffi->attach( SDL_PollEvent          => ['opaque'] => 'int' );
$ffi->attach( SDL_Delay              => ['uint'] => 'void' );
$ffi->attach( SDL_FreeSurface        => ['opaque'] => 'void' );
$ffi->attach( SDL_CreateTextureFromSurface => ['opaque','opaque'] => 'opaque' );
$ffi->attach( SDL_DestroyTexture     => ['opaque'] => 'void' );
$ffi->attach( SDL_SetTextureBlendMode => ['opaque','int'] => 'int' );
$ffi->attach( SDL_SetRenderDrawBlendMode => ['opaque','int'] => 'int' );
$ffi->attach( SDL_SetTextureColorMod => ['opaque','uint8','uint8','uint8'] => 'int' );
$ffi->attach( IMG_Load               => ['string'] => 'opaque' );
$ffi->attach( IMG_Init               => ['int']    => 'int' );
$ffi->attach( SDL_GetKeyboardState   => ['opaque'] => 'opaque' );

$ffi->attach( Mix_OpenAudio  => ['int','uint16','int','int'] => 'int' );
$ffi->attach( Mix_LoadMUS    => ['string']                   => 'opaque' );
$ffi->attach( Mix_PlayMusic  => ['opaque','int']             => 'int' );
$ffi->attach( Mix_VolumeMusic => ['int']                      => 'int' );
$ffi->attach( Mix_FreeMusic  => ['opaque']                   => 'void' );
$ffi->attach( Mix_CloseAudio => []                           => 'void' );

$ffi->attach( TTF_Init             => []                           => 'int' );
$ffi->attach( TTF_OpenFont         => ['string', 'int']            => 'opaque' );
$ffi->attach( TTF_RenderUTF8_Solid => ['opaque', 'string', 'opaque'] => 'opaque' );
$ffi->attach( TTF_RenderUTF8_Blended => ['opaque', 'string', 'opaque'] => 'opaque' );
$ffi->attach( TTF_SizeUTF8 => ['opaque', 'string', 'opaque', 'opaque'] => 'int' );
$ffi->attach( TTF_CloseFont        => ['opaque']                   => 'void' );
$ffi->attach( TTF_Quit             => []                           => 'void' );

$ffi->attach( SDL_GetTicks          => []                => 'uint32' );
$ffi->attach( SDL_SetTextureAlphaMod => ['opaque','uint8'] => 'int' );
$ffi->attach( SDL_RenderFillRect => ['opaque','opaque'] => 'int' );

# Параметры окна и тайлов
my $TILE_SIZE = 48;
my $WIN_W = 800; my $WIN_H = 600;
my $COLS = 16; my $ROWS = 12;
my $MAP_W = $COLS * $TILE_SIZE;
my $MAP_H = $ROWS * $TILE_SIZE;
my $MAP_X = 0;
my $MAP_Y = 24;

die "SDL_Init: " . SDL_GetError() if SDL_Init(0x00000020) != 0;
die "IMG_Init: " . SDL_GetError() unless IMG_Init(2) & 2;
die "Mix_OpenAudio: " . SDL_GetError() if Mix_OpenAudio(44100, 0x8010, 2, 2048) != 0;

my $window   = SDL_CreateWindow("Rivolta: The Emblem of the Clans", 100, 100, $WIN_W, $WIN_H, 0x00000004);
my $renderer = SDL_CreateRenderer($window, -1, 0x0000000A);
die "Renderer: " . SDL_GetError() unless $renderer;

# --- Тайлсет (основной) ---
my $tileset_path = 'assets/tileset/tileset.png';
die "Tileset not found" unless -f $tileset_path;
my $tileset_surf = IMG_Load($tileset_path) or die "IMG_Load tileset: ".SDL_GetError();
my $tileset_tex  = SDL_CreateTextureFromSurface($renderer, $tileset_surf);
SDL_FreeSurface($tileset_surf);
SDL_SetTextureBlendMode($tileset_tex, 0x00000001);

# --- Одиночный тайл-заполнитель (шахматный узор) ---
my $alpha_path = 'assets/tileset/alpha.png';
my $alpha_tex  = undef;
if (-f $alpha_path) {
    my $alpha_surf = IMG_Load($alpha_path) or die "IMG_Load alpha: ".SDL_GetError();
    $alpha_tex     = SDL_CreateTextureFromSurface($renderer, $alpha_surf);
    SDL_FreeSurface($alpha_surf);
}

# --- Спрайт персонажа ---
my $sprite_path = 'assets/mapsprites/Bryan.png';
die "Sprite not found" unless -f $sprite_path;
my $sprite_surf = IMG_Load($sprite_path) or die "IMG_Load sprite: ".SDL_GetError();
my $sprite_tex  = SDL_CreateTextureFromSurface($renderer, $sprite_surf);
SDL_FreeSurface($sprite_surf);
SDL_SetTextureBlendMode($sprite_tex, 0x00000001);

# --- Логотип для интро ---
my $logo_path = 'assets/intro/logo.png';
die "Logo not found: $logo_path" unless -f $logo_path;
my $logo_surf = IMG_Load($logo_path) or die "IMG_Load logo: " . SDL_GetError();
my $logo_tex = SDL_CreateTextureFromSurface($renderer, $logo_surf);
SDL_FreeSurface($logo_surf);
SDL_SetTextureBlendMode($logo_tex, 0x00000001);

# Загрузка буквенных текстур
my %letter_tex;
my $LETTER_W = 20;
my $LETTER_H = 32;

# Заглавные A–Z (012–037)
for my $i (0..25) {
    my $num  = 12 + $i;
    my $char = chr(65 + $i);
    my $path = sprintf('assets/fonts/white/symbol%03d.png', $num);
    next unless -f $path;
    my $surf = IMG_Load($path) or die "IMG_Load $path: " . SDL_GetError();
    my $tex = SDL_CreateTextureFromSurface($renderer, $surf);
    SDL_FreeSurface($surf);
    SDL_SetTextureBlendMode($tex, 0x00000001);
    $letter_tex{$char} = $tex;
}

# Строчные a–z (038–063)
for my $i (0..25) {
    my $num  = 38 + $i;
    my $char = chr(97 + $i);
    my $path = sprintf('assets/fonts/white/symbol%03d.png', $num);
    next unless -f $path;
    my $surf = IMG_Load($path) or die "IMG_Load $path: " . SDL_GetError();
    my $tex = SDL_CreateTextureFromSurface($renderer, $surf);
    SDL_FreeSurface($surf);
    SDL_SetTextureBlendMode($tex, 0x00000001);
    $letter_tex{$char} = $tex;
}

# --- Функция отрисовки спрайта ---
my $draw_sprite = sub {
    my ($tex, $x, $y, $src_x, $src_y, $w, $h) = @_;
    my $src_pack = pack('iiii', $src_x, $src_y, $w, $h);
    my $dst_pack = pack('iiii', $x, $y, $w, $h);
    my $src_rect = malloc(16); memcpy($src_rect, $ffi->cast('string'=>'opaque', $src_pack), 16);
    my $dst_rect = malloc(16); memcpy($dst_rect, $ffi->cast('string'=>'opaque', $dst_pack), 16);
    SDL_RenderCopy($renderer, $tex, $src_rect, $dst_rect);
    free($src_rect); free($dst_rect);
};

my $text_renderer = TextRenderer->new(
    letter_tex   => \%letter_tex,
    draw_cb      => $draw_sprite,
    letter_w     => $LETTER_W,
    letter_h     => $LETTER_H,
    spacing      => 1,
    alpha_mod_cb => sub { SDL_SetTextureAlphaMod(@_) },
);

# --- Карта ---
my $maplist_path = 'data/map/maplist.toml';
die "Maplist not found: $maplist_path" unless -f $maplist_path;
my $maplist_raw = do { local $/; open my $fh, '<', $maplist_path; <$fh> };
my $maplist = from_toml($maplist_raw);
my $selected_map = $maplist->{maps}[0] or die "No maps in maplist";

my $map_folder   = $selected_map->{folder};
my $music_path   = $selected_map->{music};
my $layout_path  = "data/map/$map_folder/layout.toml";
die "Layout not found: $layout_path" unless -f $layout_path;

my $layout_raw = do { local $/; open my $fh, '<', $layout_path; <$fh> };
my $layout = from_toml($layout_raw);

my $map_cols = $layout->{map}{cols} // die "No cols in layout";
my $map_rows = $layout->{map}{rows} // die "No rows in layout";

my @map;
my @collision;

for my $r (0 .. $map_rows - 1) {
    my $tile_row = $layout->{tiles}{sprintf("row%02d", $r)} // '';
    my $coll_row = $layout->{collision}{sprintf("row%02d", $r)} // '';
    push @map, [split /\s+/, $tile_row];
    push @collision, [split /\s+/, $coll_row];
    while (@{$map[-1]} < $map_cols) { push @{$map[-1]}, 0; }
    while (@{$collision[-1]} < $map_cols) { push @{$collision[-1]}, 0; }
}

sub tile_src {
    my ($id) = @_;
    return (0,0) if $id <= 0;
    my $tp = 16; my $sw = $tp * $TILE_SIZE; my $th = 64;
    my $strip = int($id / ($tp * $th));
    my $local = $id % ($tp * $th);
    my $col = $local % $tp;
    my $row = int($local / $tp);
    my $sx = $strip * $sw + $col * $TILE_SIZE;
    my $sy = $row * $TILE_SIZE;
    return (0,0) if $sx>=3072 || $sy>=3072;
    return ($sx, $sy);
}

# --- Персонаж ---
my $player = Player->new(
    draw_cb      => $draw_sprite,
    texture      => $sprite_tex,
    x            => 2 * $TILE_SIZE,
    y            => 9 * $TILE_SIZE,
    direction    => 'down',
    map_cols     => $map_cols,
    map_rows     => $map_rows,
    map_offset_x => 0,
    map_offset_y => 0,
    tile_size    => $TILE_SIZE,
    collision    => \@collision,
);

my $camera = Camera->new(
    map_width   => $map_cols * $TILE_SIZE,
    map_height  => $map_rows * $TILE_SIZE,
    view_width  => $WIN_W,
    view_height => $WIN_H,
    margin_x    => 0,
    margin_y    => 0,
    dead_zone_x => 0,
    dead_zone_y => 0,
    speed       => 7,
    fast_speed  => 7,
    speedup_threshold => 999,
);

$camera->{y} = -$MAP_Y;
$camera->{target_y} = -$MAP_Y;

my $rain = Rain->new( max_drops => 200, length => 26, speed => 9, angle => 25 );

# Управление дождём
my $rain_scheduled = 0;
my $rain_active    = 0;
my $rain_start_time = 0;
my $rain_end_time   = 0;
my $rain_minute     = 0;
my $last_rain_hour  = -1;

# --- Меню 4 кнопки ---
my @button_textures;
for my $i (1..4) {
    my $path = "assets/buttons/button_$i.png";
    die "Button $i not found: $path" unless -f $path;
    my $surf = IMG_Load($path) or die "IMG_Load button $i: " . SDL_GetError();
    my $tex  = SDL_CreateTextureFromSurface($renderer, $surf);
    SDL_FreeSurface($surf);
    SDL_SetTextureBlendMode($tex, 0x00000001);
    push @button_textures, $tex;
}

# --- Панель с названиями ---
my $label_panel_tex = undef;
my $label_path = 'assets/buttons/Label_panel.png';
if (-f $label_path) {
    my $surf = IMG_Load($label_path) or die "IMG_Load label_panel: " . SDL_GetError();
    $label_panel_tex = SDL_CreateTextureFromSurface($renderer, $surf);
    SDL_FreeSurface($surf);
    SDL_SetTextureBlendMode($label_panel_tex, 0x00000001);
}

my $draw_sprite_flip = sub {
    my ($tex, $x, $y, $src_x, $src_y, $w, $h, $scale_x, $flip) = @_;
    my $src_pack = pack('iiii', $src_x, $src_y, $w, $h);
    my $dst_w = $w * $scale_x;
    my $dst_h = $h;
    my $dst_x = $x + ($w - $dst_w)/2;
    my $dst_y = $y;
    my $dst_pack = pack('iiii', $dst_x, $dst_y, $dst_w, $dst_h);
    my $src_rect = malloc(16); memcpy($src_rect, $ffi->cast('string'=>'opaque', $src_pack), 16);
    my $dst_rect = malloc(16); memcpy($dst_rect, $ffi->cast('string'=>'opaque', $dst_pack), 16);
    my $center = pack('ii', 0, 0);
    SDL_RenderCopyEx($renderer, $tex, $src_rect, $dst_rect, 0, $ffi->cast('string'=>'opaque', $center), $flip ? 1 : 0);
    free($src_rect); free($dst_rect);
};

my $draw_border = sub {
    my ($x1, $y1, $x2, $y2, $x3, $y3, $x4, $y4) = @_;
    SDL_SetRenderDrawBlendMode($renderer, 1);
    SDL_SetRenderDrawColor($renderer, 255, 105, 180, 220);
    for my $dx (0, 1) {
        for my $dy (0, 1) {
            SDL_RenderDrawLine($renderer, $x1+$dx, $y1+$dy, $x2+$dx, $y2+$dy);
            SDL_RenderDrawLine($renderer, $x2+$dx, $y2+$dy, $x3+$dx, $y3+$dy);
            SDL_RenderDrawLine($renderer, $x3+$dx, $y3+$dy, $x4+$dx, $y4+$dy);
            SDL_RenderDrawLine($renderer, $x4+$dx, $y4+$dy, $x1+$dx, $y1+$dy);
        }
    }
    SDL_SetRenderDrawBlendMode($renderer, 0);
    SDL_SetRenderDrawColor($renderer, 255, 255, 255, 255);
};

my $reset_color = sub {
    SDL_SetRenderDrawColor($renderer, 255, 255, 255, 255);
};

my $draw_line = sub { SDL_RenderDrawLine($renderer, @_); };

# --- Буквенные наборы для надписей меню ---
my @menu_label_strings = ("Stato", "Magia", "Oggetti", "Cerca");
my @menu_label_letters;

for my $word (@menu_label_strings) {
    my @word_tex;
    for my $ch (split //, $word) {
        if (exists $letter_tex{$ch}) {
            push @word_tex, $letter_tex{$ch};
        } else {
            warn "Нет текстуры для буквы '$ch'";
            push @word_tex, undef;
        }
    }
    push @menu_label_letters, \@word_tex;
}

# --- Создание главного меню ---
my $menu = Menu->new(
    renderer            => $renderer,
    draw_cb             => $draw_sprite,
    draw_cb_flip        => $draw_sprite_flip,
    draw_border         => $draw_border,
    reset_color         => $reset_color,
    set_texture_color_mod => sub { SDL_SetTextureColorMod(@_) },
    label_panel_tex     => $label_panel_tex,
    label_textures      => [],
    label_letter_textures => \@menu_label_letters,
    letter_w            => $LETTER_W,
    letter_h            => $LETTER_H,
    letter_spacing      => 0,
    center_x            => $WIN_W / 2,
    center_y            => $WIN_H - 100,
    offset              => 34,
    textures            => \@button_textures,
);

# --- Загрузка текстур для меню статуса ---
my $load_status_tex = sub {
    my ($path) = @_;
    die "Status texture not found: $path" unless -f $path;
    my $surf = IMG_Load($path) or die "IMG_Load $path: " . SDL_GetError();
    my $tex = SDL_CreateTextureFromSurface($renderer, $surf);
    SDL_FreeSurface($surf);
    SDL_SetTextureBlendMode($tex, 0x00000001);
    return $tex;
};

my $status_portrait_tex = $load_status_tex->('assets/ui/portrait.png');
my $status_panel1_tex   = $load_status_tex->('assets/ui/panel1.png');
my $status_panel2_tex   = $load_status_tex->('assets/ui/panel2.png');

my $status_menu = StatusMenu->new(
    renderer     => $renderer,
    draw_cb      => $draw_sprite,
    win_w        => $WIN_W,
    win_h        => $WIN_H,
    portrait_tex => $status_portrait_tex,
    panel1_tex   => $status_panel1_tex,
    panel2_tex   => $status_panel2_tex,
);

# Флаги движения
my %move_flags = ( up => 0, down => 0, left => 0, right => 0 );

my $event_ptr = malloc(56);
my $src_rect  = malloc(16);
my $dst_rect  = malloc(16);
my $running   = 1;

# --- Запуск интро ---
my $intro = Intro->new(
    logo_tex  => $logo_tex,
    get_ticks => sub { SDL_GetTicks() },
    win_w     => $WIN_W,
    win_h     => $WIN_H,
);

while (!$intro->update()) {
    while (SDL_PollEvent($event_ptr)) {
        my $event_str = "\0" x 56;
        memcpy($ffi->cast('string' => 'opaque', $event_str), $event_ptr, 56);
        my $type = unpack('V', substr($event_str, 0, 4));
        if ($type == 0x100) {
            $running = 0;
            last;
        }
        elsif ($type == 0x300) {
            my $scancode = unpack('V', substr($event_str, 16, 4));
            if ($scancode == 0x04 || $scancode == 0x07) {
                $intro->start_fade_out();
            }
        }
    }
    last unless $running;

    SDL_SetRenderDrawColor($renderer, 0, 0, 0, 255);
    SDL_RenderClear($renderer);

    my $state = $intro->state;

    if ($state ne 'BLACK_WAIT' && $state ne 'DONE') {
        if ($state ne 'FLICKER' || $intro->flicker_visible) {
            my $half_w = $intro->logo_w / 2;
            my $half_h = $intro->logo_h / 2;
            my $dx = ($intro->win_w - $half_w) / 2;
            my $dy = ($intro->win_h - $half_h) / 2;

            my $src_pack = pack('iiii', 0, 0, $intro->logo_w, $intro->logo_h);
            my $dst_pack = pack('iiii', $dx, $dy, $half_w, $half_h);

            my $src_rect_tmp = malloc(16);
            memcpy($src_rect_tmp, $ffi->cast('string'=>'opaque', $src_pack), 16);
            my $dst_rect_tmp = malloc(16);
            memcpy($dst_rect_tmp, $ffi->cast('string'=>'opaque', $dst_pack), 16);

            if ($state eq 'FADE_OUT' || $state eq 'FADE_IN') {
                SDL_SetTextureAlphaMod($intro->logo_tex, $intro->fade_alpha);
            }
            SDL_RenderCopy($renderer, $intro->logo_tex, $src_rect_tmp, $dst_rect_tmp);
            if ($state eq 'FADE_OUT' || $state eq 'FADE_IN') {
                SDL_SetTextureAlphaMod($intro->logo_tex, 255);
            }
            free($src_rect_tmp);
            free($dst_rect_tmp);
        }

        if ($state eq 'WAIT_START' && $intro->show_press_start) {
            my $logo_bottom = ($intro->win_h + $intro->logo_h/2) / 2;
            my $text_y = $logo_bottom + 20;
            my $alpha = ($state eq 'FADE_OUT') ? $intro->fade_alpha : undef;
            $text_renderer->draw_centered("Press Start", $intro->win_w / 2, $text_y, $alpha);
        }
    }

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

# --- Запуск музыки ---
if ($music_path && -f $music_path) {
    my $music = Mix_LoadMUS($music_path);
    if ($music) {
        Mix_VolumeMusic(64);
        Mix_PlayMusic($music, -1);
    }
}

while ($running) {
    # --- Обработка событий ---
    while (SDL_PollEvent($event_ptr)) {
        my $event_str = "\0" x 56;
        memcpy($ffi->cast('string' => 'opaque', $event_str), $event_ptr, 56);
        my $type = unpack('V', substr($event_str, 0, 4));

        if ($type == 0x100) { $running = 0; }
        elsif ($type == 0x300) {
            my $scancode = unpack('V', substr($event_str, 16, 4));
            my $sym      = unpack('V', substr($event_str, 20, 4));

            if ($sym == 27) { $running = 0; }
            elsif ($sym == 0x40000052) { $move_flags{up}    = 1; }
            elsif ($sym == 0x40000051) { $move_flags{down}  = 1; }
            elsif ($sym == 0x40000050) { $move_flags{left}  = 1; }
            elsif ($sym == 0x4000004F) { $move_flags{right} = 1; }
			elsif ($scancode == 0x04 || $sym == 97 || $sym == 65) {
				# Клавиша A (a/A) — открыть главное меню
				$menu->open();
				%move_flags = ( up => 0, down => 0, left => 0, right => 0 );
			}
			elsif ($scancode == 0x07 || $sym == 100 || $sym == 68) {
				# Клавиша D (d/D) — открыть экран статуса
				$status_menu->open();
				$menu->close();
				%move_flags = ( up => 0, down => 0, left => 0, right => 0 );
			}
            elsif ($scancode == 0x16) {   # S
                if ($status_menu->is_active) {
                    $status_menu->close();
                    $menu->open();
                } else {
                    $menu->close();
                }
            }
            elsif ($scancode == 0x28) {   # Enter
                if ($menu->{visible}) {
                    if ($menu->{selected} == 0) {
                        $status_menu->open();
                        $menu->close();
                        %move_flags = ( up => 0, down => 0, left => 0, right => 0 );
                    }
                } elsif ($status_menu->is_active) {
                    $status_menu->close();
                    $menu->open();
                }
            }
        }
        elsif ($type == 0x301) {
            my $key = unpack('V', substr($event_str, 20, 4));
            if ($key == 0x40000052) { $move_flags{up}    = 0; }
            elsif ($key == 0x40000051) { $move_flags{down}  = 0; }
            elsif ($key == 0x40000050) { $move_flags{left}  = 0; }
            elsif ($key == 0x4000004F) { $move_flags{right} = 0; }
        }
    }

    # --- Расписание дождя ---
    my ($sec, $min, $hour) = (localtime)[0,1,2];
    if ($hour != $last_rain_hour) {
        $rain_minute = int(rand(51));
        $last_rain_hour = $hour;
        $rain_scheduled = 1;
        $rain_active = 0;
    }
    if ($rain_scheduled && !$rain_active && $min == $rain_minute) {
        $rain_active = 1;
        $rain_scheduled = 0;
        my $duration = 120 + int(rand(301));
        $rain_start_time = time();
        $rain_end_time = $rain_start_time + $duration;
    }
    if ($rain_active && time() >= $rain_end_time) {
        $rain_active = 0;
        $rain->clear();
    }

    $menu->handle_input(\%move_flags);
    $menu->update();

    if ($menu->{visible} || $status_menu->is_active) {
        $player->update({ up => 0, down => 0, left => 0, right => 0 });
    } else {
        $player->update(\%move_flags);
    }

    # Центр игрока в мировых координатах
    my $px = $player->{tile_x} * $TILE_SIZE + $TILE_SIZE/2;
    my $py = $player->{tile_y} * $TILE_SIZE + $TILE_SIZE/2;
    if (defined $player->{target_tile_x}) {
        if    ($player->{direction} eq 'right') { $px += $player->{pixel_offset}; }
        elsif ($player->{direction} eq 'left')  { $px -= $player->{pixel_offset}; }
        elsif ($player->{direction} eq 'down')  { $py += $player->{pixel_offset}; }
        elsif ($player->{direction} eq 'up')    { $py -= $player->{pixel_offset}; }
    }

    my $target_x = $px - $WIN_W / 2;
    my $target_y = $py - $WIN_H / 2;
    $target_x = 0 if $target_x < 0;
    my $max_x = $map_cols * $TILE_SIZE - $WIN_W;
    $target_x = $max_x if $target_x > $max_x;
    $target_y = -$MAP_Y if $target_y < -$MAP_Y;
    my $max_y = $map_rows * $TILE_SIZE - $WIN_H;
    $target_y = $max_y if $target_y > $max_y;

    $camera->{target_x} = $target_x;
    $camera->{target_y} = $target_y;
    $camera->update();
    my $cam_x = $camera->x;
    my $cam_y = $camera->y;

    $player->set_camera_offset($MAP_X - $cam_x, -$cam_y);

    if ($rain_active) {
        $rain->update($TILE_SIZE, $map_cols * $TILE_SIZE, $map_rows * $TILE_SIZE, $cam_x, $cam_y);
    }

    # --- Рендер ---
    SDL_SetRenderDrawColor($renderer, 0,0,0,255);
    SDL_RenderClear($renderer);

    # Шахматный фон
    if ($alpha_tex) {
        my $src_alpha = pack('iiii', 0, 0, $TILE_SIZE, $TILE_SIZE);
        my $src_tmp   = malloc(16);
        memcpy($src_tmp, $ffi->cast('string' => 'opaque', $src_alpha), 16);

        my $start_col = int($cam_x / $TILE_SIZE);
        my $end_col   = int(($cam_x + $WIN_W) / $TILE_SIZE);
        my $start_row = int($cam_y / $TILE_SIZE);
        my $end_row   = int(($cam_y + $WIN_H) / $TILE_SIZE);

        for my $row ($start_row .. $end_row) {
            next if $row < 0 || $row >= $map_rows;
            for my $col ($start_col .. $end_col) {
                next if $col < 0 || $col >= $map_cols;
                next if $map[$row][$col] != 0;
                my $dx = ($col * $TILE_SIZE) - $cam_x + $MAP_X;
                my $dy = ($row * $TILE_SIZE) - $cam_y;
                my $dst_alpha = pack('iiii', $dx, $dy, $TILE_SIZE, $TILE_SIZE);
                my $dst_tmp   = malloc(16);
                memcpy($dst_tmp, $ffi->cast('string' => 'opaque', $dst_alpha), 16);
                SDL_RenderCopy($renderer, $alpha_tex, $src_tmp, $dst_tmp);
                free($dst_tmp);
            }
        }
        free($src_tmp);
    }

    # Карта
    my $start_col = int($cam_x / $TILE_SIZE);
    my $end_col   = int(($cam_x + $WIN_W) / $TILE_SIZE);
    my $start_row = int($cam_y / $TILE_SIZE);
    my $end_row   = int(($cam_y + $WIN_H) / $TILE_SIZE);

    for my $row ($start_row .. $end_row) {
        next if $row < 0 || $row >= $map_rows;
        for my $col ($start_col .. $end_col) {
            next if $col < 0 || $col >= $map_cols;
            my $id = $map[$row][$col];
            next if $id < 0;
            my ($sx, $sy) = tile_src($id);
            my $src_pack = pack('iiii', $sx, $sy, $TILE_SIZE, $TILE_SIZE);
            memcpy($src_rect, $ffi->cast('string' => 'opaque', $src_pack), 16);
            my $dx = ($col * $TILE_SIZE) - $cam_x + $MAP_X;
            my $dy = ($row * $TILE_SIZE) - $cam_y;
            my $dst_pack = pack('iiii', $dx, $dy, $TILE_SIZE, $TILE_SIZE);
            memcpy($dst_rect, $ffi->cast('string' => 'opaque', $dst_pack), 16);
            SDL_RenderCopy($renderer, $tileset_tex, $src_rect, $dst_rect);
        }
    }

    $player->draw();
    if ($rain_active) {
        SDL_SetRenderDrawBlendMode($renderer, 1);
        SDL_SetRenderDrawColor($renderer, 200, 230, 255, 255);
        $rain->draw($renderer, $cam_x, $cam_y, $draw_line);
        SDL_SetRenderDrawBlendMode($renderer, 0);
    }

    if ($status_menu->is_active) {
        $status_menu->draw();
    } else {
        $menu->draw();
    }

    SDL_RenderPresent($renderer);
    SDL_Delay(16);
}

# --- Очистка ресурсов ---
free($src_rect); free($dst_rect); free($event_ptr);
SDL_DestroyTexture($alpha_tex) if $alpha_tex;
SDL_DestroyTexture($sprite_tex);
SDL_DestroyTexture($tileset_tex);
SDL_DestroyRenderer($renderer);
SDL_DestroyWindow($window);
Mix_CloseAudio();
SDL_DestroyTexture($label_panel_tex) if $label_panel_tex;
SDL_DestroyTexture($_) for values %letter_tex;
SDL_DestroyTexture($status_portrait_tex) if $status_portrait_tex;
SDL_DestroyTexture($status_panel1_tex)   if $status_panel1_tex;
SDL_DestroyTexture($status_panel2_tex)   if $status_panel2_tex;
SDL_Quit();