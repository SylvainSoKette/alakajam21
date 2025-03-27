package alakajam21

import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import "core:strconv"
import "core:strings"

import glm "core:math/linalg/glsl"

import rl "vendor:raylib"

// constants / defines
IS_DEBUG_BUILD :: #config(IS_DEBUG_BUILD, false)
START_FULLSCREEN :: false

START_WIDTH :: 1280
START_HEIGHT :: 720
START_ZOOM :: 4.0

TILE_SIZE :: 32

SPRITE_GRASS :: rl.Rectangle{0, 0, TILE_SIZE, TILE_SIZE}
SPRITE_WATER :: rl.Rectangle{TILE_SIZE, 0, TILE_SIZE, TILE_SIZE}

SPRITE_DUST   :: rl.Rectangle{2 * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE}
SPRITE_ICE    :: rl.Rectangle{3 * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE}
SPRITE_ROCK   :: rl.Rectangle{4 * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE}
SPRITE_PLANET :: rl.Rectangle{5 * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE}

SPRITE_SUN_0 :: rl.Rectangle{  0, 32, 64, 64}
SPRITE_SUN_1 :: rl.Rectangle{ 64, 32, 64, 64}
SPRITE_SUN_2 :: rl.Rectangle{128, 32, 64, 64}
SPRITES_SUN  : []rl.Rectangle = { SPRITE_SUN_0, SPRITE_SUN_1, SPRITE_SUN_2 }

// assets
MUSIC_OGG :: #load("res/music.ogg")

SOUND_LOST :: #load("res/lost.wav")
SOUND_AGGREG_0 :: #load("res/aggregate1.wav")
SOUND_AGGREG_1 :: #load("res/aggregate2.wav")
SOUND_AGGREG_2 :: #load("res/aggregate3.wav")

SPRITESHEET :: #load("res/spritesheet.png")
MAIN_MENU :: #load("res/menu.png")

SHADER_DEFAULT :: #load("res/default.frag.glsl")
SHADER_CRT :: #load("res/scanlines.frag.glsl")

// utils
TILE_TO_WORLD_MAT :: glm.mat2{TILE_SIZE / 2.0, TILE_SIZE / 4.0, -TILE_SIZE / 2.0, TILE_SIZE / 4.0}
tile_to_world :: proc(x, y: int) -> rl.Vector2 {
	world_pos := rl.Vector2{f32(x), f32(y)}
	return world_pos * TILE_TO_WORLD_MAT
}

WORLD_TO_TILE_MAT := glm.inverse(TILE_TO_WORLD_MAT)
world_to_tile :: proc(pos: rl.Vector2) -> rl.Vector2 {
	// NOTE: prevent crash from odin bug
	mat_copy := WORLD_TO_TILE_MAT
	return pos * mat_copy
}

camera_normal :: proc(zoom: f32) -> rl.Camera2D {
	return rl.Camera2D {
		zoom = zoom
	}
}

camera_centered :: proc(screen_width, screen_height: f32, zoom: f32) -> rl.Camera2D {
	return rl.Camera2D {
		offset = rl.Vector2{screen_width / 2.0, screen_height / 2.0},
		target = tile_to_world(5, 5),
		zoom = zoom,
	}
}

load_texture :: proc(bytes: []u8) -> rl.Texture {
	image := rl.LoadImageFromMemory(".png", raw_data(bytes), i32(len(bytes)))
	return rl.LoadTextureFromImage(image)
}

// drawing
AnimatedSprite :: struct {
	currentIndex: int,
	frameTime:    f32,
	time:         f32,
	sprites:      ^[]rl.Rectangle,
}

animated_sprite_update :: proc(dt: f32, anim: ^AnimatedSprite) {
	anim.time += dt

	if anim.time > anim.frameTime {
		anim.time -= anim.frameTime
		anim.currentIndex += 1
	}

	if anim.currentIndex >= len(anim.sprites) {
		anim.currentIndex = 0
	}
}

animated_sprite_reset :: proc(anim: ^AnimatedSprite) {
	anim.currentIndex = 0
	anim.time = 0
}

animated_sprite_current :: proc(anim: ^AnimatedSprite) -> rl.Rectangle {
	return anim.sprites[anim.currentIndex]
}

draw_sprite :: proc(
	tileset: rl.Texture2D,
	sprite: rl.Rectangle,
	pos: rl.Vector2,
	tint: rl.Color = rl.WHITE,
) {
	center_offset := rl.Vector2{-sprite.width / 2.0, -sprite.height / 2.0}
	rl.DrawTextureRec(tileset, sprite, pos + center_offset, tint)
	when IS_DEBUG_BUILD {
		rl.DrawRectangleLines(
			i32(pos.x + center_offset.x),
			i32(pos.y + center_offset.y),
			i32(sprite.width),
			i32(sprite.height),
			rl.RED,
		)
	}
}

// application
Application :: struct {
	// window
	width:         i32,
	height:        i32,
	name:          cstring,
	flags:         rl.ConfigFlags,
	targetFps:     i32,
	// game
	renderTarget:  rl.RenderTexture2D,
	currentShader: i32,
	shaders:       [len(shaderSources)]rl.Shader,
	spritesheet:   rl.Texture2D,
	menuScreen:    rl.Texture2D,
	music:         rl.Music,
	soundLost:     rl.Sound,
	sounds:        [3]rl.Sound,
}
app := Application {
	width     = START_WIDTH,
	height    = START_HEIGHT,
	name      = "Accretion - Alakajam21 - SoKette",
	flags     = START_FULLSCREEN ? {.FULLSCREEN_MODE} : {},
	targetFps = 60,
}

//shaderSources := [?]cstring {
//	"res/scanlines.frag.glsl",
//	"res/default.frag.glsl",
//}
shaderSources := [?]cstring {
	cstring(raw_data(SHADER_CRT)),
	cstring(raw_data(SHADER_DEFAULT))
}

reload_shaders :: proc() {
	for i in 0 ..< len(shaderSources) {
		oldShader := app.shaders[i]
		newShader := rl.LoadShaderFromMemory(nil, shaderSources[i])
		if rl.IsShaderValid(newShader) {
			rl.UnloadShader(oldShader)
			app.shaders[i] = newShader
		}
	}
}

// gameplay
GameScreen :: enum {
	MENU,
	GAME,
	LOST,
}

TileType :: enum {
	VOID,
	DUST,
	ICE,
	ROCK,
	PLANET,
}
Tile :: struct {
	type: TileType,
}

Objective :: struct {
	ice: int,
	rock: int,
	planet: int,
}

tile_sprite :: proc(tileType: TileType) -> rl.Rectangle {
	switch tileType {
		case .VOID: return SPRITE_GRASS
		case .DUST: return SPRITE_DUST
		case .ICE: return SPRITE_ICE
		case .ROCK: return SPRITE_ROCK
		case .PLANET: return SPRITE_PLANET
	}
	return SPRITE_GRASS
}

WORLD_SIZE :: 9
GameData :: struct {
	screen :    GameScreen,
	gameCamera: rl.Camera2D,
	uiCamera:   rl.Camera2D,
	sunPeriod:  f32,
	sun:        AnimatedSprite,
	tiles:      [WORLD_SIZE * WORLD_SIZE]Tile,
	score:      int,
	level:      int,
	objective:  Objective,
}
game := GameData {
	screen = GameScreen.MENU,
	gameCamera = camera_normal(START_ZOOM),
	uiCamera = rl.Camera2D{offset = rl.Vector2{}, target = rl.Vector2{}, zoom = 1.0},
	sunPeriod = 0.15,
	sun = AnimatedSprite{
		frameTime = 2.0,
		sprites = &SPRITES_SUN,
	},
}

init_game_data :: proc() {
	app.renderTarget = rl.LoadRenderTexture(app.width, app.height)
	reload_shaders()
	app.currentShader = 0

	app.spritesheet = load_texture(SPRITESHEET)
	app.menuScreen = load_texture(MAIN_MENU)
	app.music = rl.LoadMusicStreamFromMemory(".ogg", raw_data(MUSIC_OGG), i32(len(MUSIC_OGG)))
	rl.SeekMusicStream(app.music, 0.0)
	rl.SetMusicVolume(app.music, 0.2)

	soundLost := rl.LoadWaveFromMemory(".wav", raw_data(SOUND_LOST), i32(len(SOUND_LOST)))
	app.soundLost = rl.LoadSoundFromWave(soundLost)
	sound0 := rl.LoadWaveFromMemory(".wav", raw_data(SOUND_AGGREG_0), i32(len(SOUND_AGGREG_0)))
	app.sounds[0] = rl.LoadSoundFromWave(sound0)
	sound1 := rl.LoadWaveFromMemory(".wav", raw_data(SOUND_AGGREG_1), i32(len(SOUND_AGGREG_1)))
	app.sounds[1] = rl.LoadSoundFromWave(sound1)
	sound2 := rl.LoadWaveFromMemory(".wav", raw_data(SOUND_AGGREG_2), i32(len(SOUND_AGGREG_2)))
	app.sounds[2] = rl.LoadSoundFromWave(sound2)
}

roll_tiles :: proc() {
	for &tile in game.tiles {
		r := rand.int_max(101)
		when IS_DEBUG_BUILD {
			assert(r <= 100)
			assert(r >= 0)
		}
		tile.type = (game.level * 5) - r > 0 ? .VOID : .DUST
	}
	game.objective = Objective{
		ice = rand.int_max(3) + 1,
		rock = rand.int_max(3) + 1,
		planet = rand.int_max(3) + 1,
	}
	when IS_DEBUG_BUILD {
		o := game.objective
		assert(o.ice > 0)
		assert(o.ice < 4)
		assert(o.rock > 0)
		assert(o.rock < 4)
		assert(o.planet > 0)
		assert(o.planet < 4)
	}
}

enter_menu :: proc() {
	game.screen = .MENU
	rl.SetExitKey(rl.KeyboardKey.ESCAPE)
	game.gameCamera = camera_normal(START_ZOOM)
}

enter_lost :: proc() {
	game.screen = .LOST
	rl.SetExitKey(nil)
	rl.PlaySound(app.soundLost)
	game.gameCamera = camera_normal(START_ZOOM)
}


enter_game :: proc() {
	game.screen = .GAME
	rl.SetExitKey(nil)
	game.gameCamera = camera_centered(START_WIDTH, START_HEIGHT, START_ZOOM)
	game.score = 0
	game.level = 1
	game.sunPeriod = 0.15
	roll_tiles()
}

render_menu :: proc(dt: f32) {
	rl.DrawTexture(app.menuScreen, 0, 0, rl.WHITE)
}

render_lost :: proc(dt: f32) {}

in_world :: proc(x, y: int) -> bool {
	return x >= 0 && y >= 0 && x < WORLD_SIZE && y < WORLD_SIZE
}

count_adjacent :: proc(x, y: int) -> int {
	neighbours := 0
	tile: Tile
	if in_world(x + 1, y) {
		tile = game.tiles[(x + 1) + y * WORLD_SIZE]
		neighbours += tile.type != TileType.VOID ? 1 : 0
	}
	if in_world(x - 1, y) {
		tile = game.tiles[(x - 1) + y * WORLD_SIZE]
		neighbours += tile.type != TileType.VOID ? 1 : 0
	}
	if in_world(x, y + 1) {
		tile = game.tiles[x + (y + 1) * WORLD_SIZE]
		neighbours += tile.type != TileType.VOID ? 1 : 0
	}
	if in_world(x, y - 1) {
		tile = game.tiles[x + (y - 1) * WORLD_SIZE]
		neighbours += tile.type != TileType.VOID ? 1 : 0
	}
	return neighbours
}

is_adjacent :: proc(x, y, mouseX, mouseY: int) -> bool {
	if (mouseX == x) {
		return mouseY - 1 == y || mouseY + 1 == y
	} else if (mouseY == y) {
		return mouseX - 1 == x || mouseX + 1 == x
	}
	return false
}

render_game :: proc(dt: f32) {
	sunPosition := rl.Vector2{
		linalg.cos(game.sunPeriod) * f32(app.width / 4.0) - 180,
		linalg.sin(game.sunPeriod) * f32(app.height / 4.0) - 80,
	}
	sunSprite := animated_sprite_current(&game.sun)
	draw_sprite(app.spritesheet, sunSprite, sunPosition, rl.WHITE)

	mouseWorld := rl.GetScreenToWorld2D(rl.GetMousePosition(), game.gameCamera)
	mousePos := world_to_tile(mouseWorld)
	mouseX := int(mousePos.x)
	mouseY := int(mousePos.y)

	tileAtMouse := Tile{ type = .VOID }
	if in_world(mouseX, mouseY) {
		tileAtMouse = game.tiles[mouseX + mouseY * WORLD_SIZE]
	}
	neighbours := count_adjacent(mouseX, mouseY)
	for y in 0 ..< WORLD_SIZE {
		for x in 0 ..< WORLD_SIZE {
			pos := tile_to_world(x, y)
			tile := game.tiles[x + y * WORLD_SIZE]
			if tile.type == .VOID { continue }

			tileOffset := rl.Vector2{0, TILE_SIZE / 2}
			color := rl.WHITE
			// special case, hovered, adjacent to hovered
			if tileAtMouse.type != .VOID {
				if mouseX == x && mouseY == y {
					color = tile.type == TileType.DUST ? (neighbours > 1 ? rl.GREEN : rl.RED) : rl.GRAY
					tileOffset.y -= 2
				} else if (is_adjacent(x, y, mouseX, mouseY) && tile.type == .DUST) {
					color = neighbours > 1 ? rl.LIME : rl.MAROON
					tileOffset.y -= 2
				}
			}
			pos += tileOffset
			sprite := tile_sprite(tile.type)
			draw_sprite(app.spritesheet, sprite, pos, color)
			when IS_DEBUG_BUILD {
				rl.DrawPixel(i32(pos.x), i32(pos.y), rl.MAGENTA)
			}
		}
	}
}

render_debug :: proc(dt: f32) {
	h: i32 = 8
	size: i32 = 32

	mouseWorld := rl.GetScreenToWorld2D(rl.GetMousePosition(), game.gameCamera)
	rl.DrawText(
		fmt.caprintf("mouse world %i - %i", int(mouseWorld.x), int(mouseWorld.y)),
		8,
		h,
		size,
		rl.SKYBLUE,
	)
	h += size

	mousePos := world_to_tile(mouseWorld)
	rl.DrawText(
		fmt.caprintf("mouse tile %i - %i", int(mousePos.x), int(mousePos.y)),
		8,
		h,
		size,
		rl.SKYBLUE,
	)
	h += size

	offset := game.gameCamera.offset
	rl.DrawText(fmt.caprintf("camera offset %f - %f", offset.x, offset.y), 8, h, size, rl.SKYBLUE)
	h += size

	target := game.gameCamera.target
	rl.DrawText(fmt.caprintf("camera target %f - %f", target.x, target.y), 8, h, size, rl.SKYBLUE)
	h += size

	rl.DrawText(fmt.caprintf("score %i", game.score), 8, h, size, rl.SKYBLUE)
	h += size

	rl.DrawText(fmt.caprintf("level %i", game.level), 8, h, size, rl.SKYBLUE)
	h += size

	o := game.objective
	rl.DrawText(fmt.caprintf("objective: %i %i %d", o.ice, o.rock, o.planet), 8, h, size, rl.SKYBLUE)
	h += size

	c := Objective{}
	for tile in game.tiles {
		if tile.type == .ICE { c.ice += 1 }
		if tile.type == .ROCK { c.rock += 1 }
		if tile.type == .PLANET { c.planet += 1 }
	}
	rl.DrawText(fmt.caprintf("current: %i %i %d", c.ice, c.rock, c.planet), 8, h, size, rl.SKYBLUE)
	h += size
}

render_ui_menu :: proc(dt: f32) {
	left: i32 = 64
	size: i32 = 24
	line: i32 = 32
	h: i32 = 260

	rl.DrawText("Made by SoKette in 24 hours for Alakajam21", left, h, size, rl.MAROON)
	h += line
	h += line

	rl.DrawText("Press [SPACE] / click [left mouse button] to start", left, h, size, rl.ORANGE)
	h += line
	rl.DrawText("Press [ESCAPE] to quit", left, h, size, rl.ORANGE)
	h += line
	rl.DrawText("Press [R] to restart", left, h, size, rl.GOLD)
	h += line
	rl.DrawText("Press [F4] to toggle post-processing effects", left, h, size, rl.GOLD)
}

render_ui_game :: proc(dt: f32) {
	{
		left: i32 = 64
		size: i32 = 24
		line: i32 = 42
		h: i32 = 504

		rl.DrawText("Objective:", left, h, size, rl.GOLD)
		h += line
		o := game.objective
		c := Objective{}
		for tile in game.tiles {
			if tile.type == .ICE { c.ice += 1 }
			if tile.type == .ROCK { c.rock += 1 }
			if tile.type == .PLANET { c.planet += 1 }
		}
		colorIce := c.ice == o.ice ? rl.GREEN : rl.GOLD
		rl.DrawText(fmt.caprintf("> Ice: %i / %i", c.ice, o.ice), left, h, size, colorIce)
		h += line
		colorRock := c.rock == o.rock ? rl.GREEN : rl.GOLD
		rl.DrawText(fmt.caprintf("> Rocks: %i / %i", c.rock, o.rock), left, h, size, colorRock)
		h += line
		colorPlanet := c.planet == o.planet ? rl.GREEN : rl.GOLD
		rl.DrawText(fmt.caprintf("> Planets: %i / %i", c.planet, o.planet), left, h, size, colorPlanet)
	}

	{
		left: i32 = 1080
		size: i32 = 24
		line: i32 = 42
		h: i32 = 504

		rl.DrawText(fmt.caprintf("Level: %i", game.level), left, h, size, rl.GOLD)
		h += line
		rl.DrawText(fmt.caprintf("Score: %i", game.score), left, h, size, rl.GOLD)
	}
}

render_ui_lost :: proc(dt: f32) {
	{
		left: i32 = 64
		size: i32 = 24
		line: i32 = 42
		h: i32 = 504

		rl.DrawText("Objective:", left, h, size, rl.GOLD)
		h += line
		o := game.objective
		c := Objective{}
		for tile in game.tiles {
			if tile.type == .ICE { c.ice += 1 }
			if tile.type == .ROCK { c.rock += 1 }
			if tile.type == .PLANET { c.planet += 1 }
		}
		rl.DrawText(fmt.caprintf("> Ice: %i / %i", c.ice, o.ice), left, h, size,
			c.ice > o.ice ? rl.MAROON : rl.GOLD)
		h += line
		rl.DrawText(fmt.caprintf("> Rocks: %i / %i", c.rock, o.rock), left, h, size,
			c.rock > o.rock ? rl.MAROON : rl.GOLD)
		h += line
		rl.DrawText(fmt.caprintf("> Planets: %i / %i", c.planet, o.planet), left, h, size,
			c.planet > o.planet ? rl.MAROON :rl.GOLD)
	}

	rl.DrawText("This system is out of balance !", 64, 256, 72, rl.RED)
	{
		left: i32 = 640
		size: i32 = 24
		line: i32 = 42
		h: i32 = 504

		rl.DrawText(fmt.caprintf("Final level: %i", game.level), left, h, size, rl.GOLD)
		h += line
		rl.DrawText(fmt.caprintf("Final score: %i", game.score), left, h, size, rl.GOLD)
		h += line
		rl.DrawText("Press [ESCAPE] to return to main menu", left, h, size, rl.GOLD)
	}
}

next_level :: proc() {
	game.level += 1
	roll_tiles()
}

check_win :: proc() {
	current := Objective{}
	for tile in game.tiles {
		if tile.type == .ICE { current.ice += 1 }
		if tile.type == .ROCK { current.rock += 1 }
		if tile.type == .PLANET { current.planet += 1 }
	}

	o := game.objective
	if (
		current.ice > o.ice ||
		current.rock > o.rock ||
		current.planet > o.planet
	) {
		enter_lost()
		return
	}

	if (
		current.ice == o.ice &&
		current.rock == o.rock &&
		current.planet == o.planet
	) {
		next_level()
	}

	sound := app.sounds[rand.int127() % len(app.sounds)]
	rl.PlaySound(sound)


}

update_menu :: proc(dt: f32) {
	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) || rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
		enter_game()
	}
}

update_lost :: proc(dt: f32) {
	if (
		rl.IsKeyPressed(rl.KeyboardKey.SPACE) ||
		rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) ||
		rl.IsMouseButtonPressed(rl.MouseButton.LEFT)
	) {
		enter_menu()
	}
}

update_game :: proc(dt: f32) {
	if rl.IsKeyDown(rl.KeyboardKey.G) {
		game.sunPeriod += dt
	} else {
		game.sunPeriod += dt / f32(30)
	}
	animated_sprite_update(dt, &game.sun)

	if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
		mouseWorld := rl.GetScreenToWorld2D(rl.GetMousePosition(), game.gameCamera)
		mouseTile := world_to_tile(mouseWorld)
		x := int(mouseTile.x)
		y := int(mouseTile.y)
		if in_world(x, y) {
			tile := &game.tiles[x + y * WORLD_SIZE]
			if (tile.type == .VOID) { return }
			right, left, top, bottom: ^Tile
			neighbours := 0
			if in_world(x + 1, y) {
				// right
				right = &game.tiles[x + 1 + y * WORLD_SIZE]
				neighbours += right.type != TileType.VOID ? 1 : 0
			}
			if in_world(x - 1, y) {
				// left
				left = &game.tiles[x - 1 + y * WORLD_SIZE]
				neighbours += left.type != TileType.VOID ? 1 : 0
			}
			if in_world(x, y + 1) {
				// top
				top = &game.tiles[x + (y + 1) * WORLD_SIZE]
				neighbours += top.type != TileType.VOID ? 1 : 0
			}
			if in_world(x, y - 1) {
				// bottom
				bottom = &game.tiles[x + (y - 1) * WORLD_SIZE]
				neighbours += bottom.type != TileType.VOID ? 1 : 0
			}

			if neighbours == 4 {
				tile.type = TileType.PLANET
				game.score += 21
			} else if neighbours == 3 {
				tile.type = TileType.ROCK
				game.score += 7
			} else if neighbours == 2 {
				tile.type = TileType.ICE
				game.score += 3
			}

			if neighbours > 1 {
				if top != nil    {    top.type = .VOID }
				if left != nil   {   left.type = .VOID }
				if right != nil  {  right.type = .VOID }
				if bottom != nil { bottom.type = .VOID }

				check_win()
			}

		}
	}

	if rl.IsKeyPressed(rl.KeyboardKey.R) {
		enter_game()
	}

	if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
		enter_menu()
	}
}

update :: proc(dt: f32) {
	when IS_DEBUG_BUILD {
		if rl.IsKeyPressed(rl.KeyboardKey.F5) {
			reload_shaders()
		}
	}

	if rl.IsKeyPressed(rl.KeyboardKey.F4) {
		app.currentShader = (app.currentShader + 1) % (len(app.shaders))
	}
}

main :: proc() {
	when IS_DEBUG_BUILD {
		rl.SetTraceLogLevel(rl.TraceLogLevel.TRACE)
	} else {
		rl.SetTraceLogLevel(rl.TraceLogLevel.ERROR)
	}

	rl.InitWindow(app.width, app.height, app.name)
	defer rl.CloseWindow()
	rl.SetWindowState(app.flags)
	rl.SetTargetFPS(app.targetFps)

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	init_game_data()

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		switch game.screen {
			case .MENU: update_menu(dt)
			case .GAME: update_game(dt)
			case .LOST: update_lost(dt)
		}
		update(dt)

		if rl.IsMusicReady(app.music) && !rl.IsMusicStreamPlaying(app.music) {
			rl.PlayMusicStream(app.music)
		}
		rl.UpdateMusicStream(app.music)

		rl.BeginTextureMode(app.renderTarget)
		rl.ClearBackground(rl.BLACK)
		{
			rl.BeginMode2D(game.gameCamera)
			switch game.screen {
				case .MENU: render_menu(dt)
				case .GAME: render_game(dt)
				case .LOST: render_lost(dt)
			}
			rl.EndMode2D()
		}
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		{
			rl.BeginShaderMode(app.shaders[app.currentShader])
			rl.DrawTextureRec(
				app.renderTarget.texture,
				rl.Rectangle {
					0,
					0,
					f32(app.renderTarget.texture.width),
					f32(-app.renderTarget.texture.height),
				},
				rl.Vector2{},
				rl.WHITE,
			)
			rl.EndShaderMode()

			rl.BeginMode2D(game.uiCamera)
			switch game.screen {
				case .MENU: render_ui_menu(dt)
				case .GAME: render_ui_game(dt)
				case .LOST: render_ui_lost(dt)
			}
			when IS_DEBUG_BUILD {
				render_debug(dt)
			}
			rl.EndMode2D()
		}
		rl.EndDrawing()

		free_all(context.temp_allocator)
	}
}
