extends Node3D
# Shooter (Arbeitstitel) – Deckungs-Shooter im Pappaufsteller-Look.
# Alle Kulissen und Gegner sind flache Bilder („Pappe“) auf echten 3D-Ebenen:
# dadurch entsteht beim Zielen und Kamerafahren eine Parallaxe, und Mündungsfeuer,
# Funken, Staub und Splitter sind echte 3D-Effekte mit Licht.

const UPD_API = "https://api.github.com/repos/thebiz/shooter-godot/releases/latest"
const SAVE_PATH = "user://save.cfg"

# ---------------------------------------------------------------- Szene (Maße in Metern)
const FAC_W = 14.0           # Hausfassade
const FAC_Z = -13.0
const FAC_Y = -0.05
# Fenster- und Türöffnungen der Fassade (u0, u1, v0, v1 im Bild)
const HOLES = [
	[0.4501, 0.546, 0.1895, 0.4161], [0.23, 0.3259, 0.1906, 0.4172],
	[0.6682, 0.7464, 0.1906, 0.4161], [0.8095, 0.885, 0.1906, 0.4172],
	[0.2037, 0.3114, 0.6068, 0.8377], [0.7011, 0.8101, 0.6068, 0.8377],
	[0.4494, 0.5532, 0.6242, 0.9858]]
const ENEMY_H = 1.8
const ENEMY_TEX = ["enemy0", "enemy1", "enemy2", "enemy3", "enemy4", "enemy5"]
const GUN_V = [0.23, 0.23, 0.24, 0.23, 0.23, 0.2]   # Höhe der Pistole im Bild (von oben)

# Kamera: aufrecht (zielen) und in Deckung
const CAM_UP = Vector3(0.0, 1.38, 0.0)
const CAM_UP_PITCH = 4.0
const CAM_COVER = Vector3(-0.15, 0.6, 0.35)
const CAM_COVER_PITCH = 14.0
const CAM_INTRO = Vector3(0.0, 3.1, 2.6)
const CAM_INTRO_PITCH = -5.0

const MAG = 8                 # Schuss pro Magazin
const RELOAD_TIME = 0.75
const KILLS_PER_STAGE = 12

var cam: Camera3D
var env: Environment
var card_shader: Shader
var ground_shader: Shader
var fx_mat_spark: StandardMaterial3D
var fx_mat_dust: StandardMaterial3D
var fx_mat_chunk: StandardMaterial3D
var tex_flash: Texture2D
var tex_hole: Texture2D

var cards = []          # Kulissen-Pappen
var wall = {}           # Mauer im Vordergrund (Deckung)
var slots = []          # Stellen, an denen Gegner auftauchen
var enemies = []
var sounds = {}
var voices = {}
var bark_cd = 0.0
var ambience: AudioStreamPlayer
var motes: CPUParticles3D

# Spielzustand
var state = "boot"      # boot, title, intro, play, over
var st_t = 0.0
var book = 0.0          # 0 = Pop-up-Buch zu, 1 = aufgeklappt (gesteuert über card.t)
var cover = false
var cover_k = 0.0       # 0 aufrecht … 1 in Deckung (geglättet)
var ammo = MAG
var reload_t = 0.0
var health = 100.0
var score = 0
var best = 0
var kills = 0
var stage = 1
var spawn_t = 1.0
var aim = Vector2(640, 330)
var aim_n = Vector2.ZERO
var aim_s = Vector2.ZERO
var kick = 0.0
var shake = 0.0
var hurt = 0.0
var hit_mark = 0.0
var msg = ""
var msg_t = 0.0
var msg_sub = ""
var msg_dur = 1.0
var tip_t = 0.0
var aim_idx = -1
var thumb = Vector2.ZERO
var thumb0 = Vector2.ZERO
# Steuerung (im Handy gespeichert, über die Leiste am rechten Rand einstellbar)
var aim_sens = 1.7          # Grundempfindlichkeit
var aim_accel = 1.0         # Beschleunigung bei schnellen Daumenbewegungen
var recenter = 0.6          # wie schnell das Fadenkreuz beim Loslassen zur Mitte gleitet (0 = aus)
var aim_assist = 0.35       # Zielhilfe: bremsen über Gegnern, sanftes Ziehen, knappe Fehlschüsse zählen
var aim_mode = "snap"       # "snap": Daumenrichtung schnappt auf feste Zielzonen, "free": freies Zielen
var thumb_n = Vector2(0.2, 0.64)    # Daumenfeld (Anteil der Bildschirmgröße)
var fire_n = Vector2(0.906, 0.7)    # Feuerknopf
const PANEL_W = 300.0
const SLIDERS = [
	{"label": "AIM SPEED", "key": "aim_sens", "min": 0.6, "max": 3.5},
	{"label": "ACCELERATION", "key": "aim_accel", "min": 0.0, "max": 3.0},
	{"label": "RETURN TO CENTER", "key": "recenter", "min": 0.0, "max": 1.0},
	{"label": "AIM ASSIST", "key": "aim_assist", "min": 0.0, "max": 1.0}]
var panel_open = false
var panel_k = 0.0
var editing = false
var ui_idx = -1             # Finger, der gerade einen Regler oder Knopf zieht
var ui_drag = ""            # "slider0".., "thumb", "fire"
var holes_live = []
# Boxen, Waffen, Granaten, Auto
var car_card = {}
var car_dead = false
var car_fx = []             # Feuer und Rauch am kaputten Auto
var weapon = "pistol"       # pistol, shotgun, smg, rocket
var wpn_ammo = 0
var grenades = 1
var fire_idx = -1           # Finger auf dem Feuerknopf (Dauerfeuer beim Maschinengewehr)
var auto_t = 0.0
var cover_time = 0.0        # wie lange man schon in Deckung hockt
var nade_limit = 4.5        # danach wirft ein Gegner eine Granate über die Mauer
var projs = []              # fliegende Granaten und Raketen
var fbs = []                # Explosions-Bildfolgen
var fb_sh: Shader
var fb_mats = {}
var tex_nade: Texture2D
const WPN_NAMES = {"shotgun": "SHOTGUN", "smg": "MACHINE GUN", "rocket": "ROCKETS"}
var shots_fired = 0
var fx_k = 1.0
var hits = 0

# HUD
var hud: Control
var vignette: TextureRect
var font: SystemFont
var font_light: SystemFont

# Update
static var upd_url = ""
static var upd_build = 0
static var upd_done = false

# Test (nur am Rechner)
var autotest = false
var at_t = 0.0
var at_step = 0


# ================================================================ Aufbau
func _ready() -> void:
	randomize()
	autotest = OS.get_environment("AUTOTEST") != ""
	_load_save()
	_make_shaders()
	_make_fx_assets()
	tex_nade = load("res://art/grenade.png")
	_make_world()
	_make_sounds()
	_make_hud()
	_upd_check()
	_set_state("title")
	for c in cards:
		c.t = -10.0       # Buch zu
	_open_book(0.4)


func _make_shaders() -> void:
	card_shader = Shader.new()
	card_shader.code = """
shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 back_col : source_color = vec3(0.56, 0.44, 0.32);
uniform float flash = 0.0;
uniform float dim = 1.0;
void fragment() {
	vec4 c = texture(tex, UV);
	vec3 col = c.rgb;
	if (!FRONT_FACING) {
		// Rückseite: graue Wellpappe
		float r = fract(UV.x * 90.0);
		col = back_col * (0.86 + 0.14 * smoothstep(0.3, 0.5, r) * smoothstep(0.9, 0.7, r));
	}
	ALBEDO = col * dim;
	ALPHA = c.a;
	ROUGHNESS = 1.0;
	EMISSION = col * flash;
}
"""
	ground_shader = Shader.new()
	ground_shader.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rep = 2.0;
void fragment() {
	float m = mod(UV.x * rep, 2.0);
	vec2 uv = vec2(m < 1.0 ? m : 2.0 - m, UV.y);
	ALBEDO = texture(tex, uv).rgb;
	ROUGHNESS = 1.0;
}
"""


func _soft_tex(sz: int, hard: float) -> ImageTexture:
	var img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var d = Vector2(x + 0.5 - sz * 0.5, y + 0.5 - sz * 0.5).length() / (sz * 0.5)
			var a = clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, hard)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_fx_assets() -> void:
	var soft = _soft_tex(64, 1.6)
	var dot = _soft_tex(32, 0.6)
	# Mündungsfeuer: heller Kern mit Strahlen
	var n = 128
	var img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p = Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
			var d = p.length()
			var ang = atan2(p.y, p.x)
			var ray = pow(abs(cos(ang * 3.0)), 18.0) * 0.8 + pow(abs(cos(ang * 2.0 + 0.6)), 30.0) * 0.5
			var a = clampf(pow(clampf(1.0 - d * 2.2, 0, 1), 1.5) + ray * pow(clampf(1.0 - d, 0, 1), 2.0), 0, 1)
			var col = Color(1.0, 0.92, 0.7).lerp(Color(1.0, 0.55, 0.15), clampf(d * 1.6, 0, 1))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	img.generate_mipmaps()
	tex_flash = ImageTexture.create_from_image(img)
	# Einschussloch: dunkler Kern, ausgefranster heller Rand
	n = 64
	img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p = Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
			var d = p.length() * (1.0 + 0.18 * sin(atan2(p.y, p.x) * 7.0) + 0.1 * sin(atan2(p.y, p.x) * 13.0))
			var c: Color
			if d < 0.32:
				c = Color(0.05, 0.035, 0.03, 0.95)
			elif d < 0.55:
				c = Color(0.18, 0.13, 0.1, 0.85 * (1.0 - (d - 0.32) / 0.23) + 0.2)
			elif d < 0.95:
				c = Color(0.85, 0.76, 0.64, 0.45 * (1.0 - (d - 0.55) / 0.4))
			else:
				c = Color(0, 0, 0, 0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	tex_hole = ImageTexture.create_from_image(img)

	fx_mat_spark = StandardMaterial3D.new()
	fx_mat_spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fx_mat_spark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fx_mat_spark.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fx_mat_spark.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fx_mat_spark.vertex_color_use_as_albedo = true
	fx_mat_spark.albedo_texture = dot
	fx_mat_spark.no_depth_test = false

	fx_mat_dust = StandardMaterial3D.new()
	fx_mat_dust.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fx_mat_dust.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fx_mat_dust.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fx_mat_dust.vertex_color_use_as_albedo = true
	fx_mat_dust.albedo_texture = soft

	fx_mat_chunk = StandardMaterial3D.new()
	fx_mat_chunk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fx_mat_chunk.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fx_mat_chunk.vertex_color_use_as_albedo = true


# Eine Pappe: Bild auf einer Ebene, Drehpunkt unten in der Mitte
func _card(tex_name: String, w: float, pos: Vector3, kind: String, h: float = -1.0) -> Dictionary:
	var tex: Texture2D = load("res://art/" + tex_name)
	if h < 0:
		h = w * tex.get_height() / float(tex.get_width())
	var mi = MeshInstance3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(w, h)
	q.center_offset = Vector3(0, h * 0.5, 0)
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m = ShaderMaterial.new()
	m.shader = card_shader
	m.set_shader_parameter("tex", tex)
	mi.material_override = m
	var pv = Node3D.new()
	pv.position = pos
	add_child(pv)
	pv.add_child(mi)
	# kleine Kopie des Bildes für die Treffer-Prüfung (durchsichtige Stellen zählen nicht)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img = img.duplicate()
	if img.get_width() > 256:
		img.resize(256, maxi(1, int(256.0 * img.get_height() / img.get_width())), Image.INTERPOLATE_BILINEAR)
	return {"pv": pv, "mi": mi, "mat": m, "img": img, "w": w, "h": h, "kind": kind, "t": 99.0, "delay": 0.0, "up": true}


func _make_world() -> void:
	# Kamera und Umgebung
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 200.0
	add_child(cam)
	cam.position = CAM_INTRO
	cam.rotation_degrees.x = CAM_INTRO_PITCH

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.6, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Himmel ganz hinten
	var sky = _card("sky.jpg", 270.0, Vector3(25.0, -62.0, -75.0), "sky")
	sky.pv.rotation.y = 0.0
	sky.mat.set_shader_parameter("dim", 1.0)
	# Boden (Gehweg und Straße) liegt flach
	var gtex: Texture2D = load("res://art/street.jpg")
	var gm = ShaderMaterial.new()
	gm.shader = ground_shader
	gm.set_shader_parameter("tex", gtex)
	gm.set_shader_parameter("rep", 2.6)
	var gq = QuadMesh.new()
	gq.size = Vector2(46.0, 15.0)
	gq.center_offset = Vector3(0, 15.0 * 0.5, 0)
	var gi = MeshInstance3D.new()
	gi.mesh = gq
	gi.material_override = gm
	var gp = Node3D.new()
	gp.position = Vector3(0, 0, FAC_Z + 15.0)
	gp.rotation.x = -PI * 0.5
	add_child(gp)
	gp.add_child(gi)
	cards.append({"pv": gp, "mi": gi, "mat": gm, "img": null, "w": 46.0, "h": 15.0, "kind": "ground", "t": 99.0, "delay": 0.0, "up": true, "static": true})

	# dunkle Räume hinter den Fenstern
	var fac_h = FAC_W * 920.0 / 1522.0
	var grad = Gradient.new()
	grad.set_color(0, Color(0.16, 0.11, 0.08))
	grad.set_color(1, Color(0.05, 0.035, 0.03))
	var gt = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 64
	var inner = MeshInstance3D.new()
	var iq = QuadMesh.new()
	iq.size = Vector2(FAC_W, fac_h)
	iq.center_offset = Vector3(0, fac_h * 0.5, 0)
	inner.mesh = iq
	var im = StandardMaterial3D.new()
	im.albedo_texture = gt
	im.roughness = 1.0
	inner.material_override = im
	# Kulissen (Reihenfolge = Reihenfolge beim Aufklappen)
	var fac = _card("facade.png", FAC_W, Vector3(0, FAC_Y, FAC_Z), "brick")
	fac.delay = 0.0
	cards.append(fac)
	# der dunkle Raum hängt an der Fassade und klappt mit ihr hoch (kein schwarzer Kasten vorher)
	inner.position = Vector3(0, 0, -0.85)
	fac.pv.add_child(inner)
	cards.append({"pv": fac.pv, "mi": inner, "mat": im, "img": null, "w": FAC_W, "h": fac_h, "kind": "room", "t": 99.0, "delay": 0.0, "up": true, "static": true})
	var tree = _card("tree.png", 7.2, Vector3(-7.4, -0.05, -9.6), "leaf")
	tree.delay = 0.25
	cards.append(tree)
	var lamp = _card("lamp.png", 1.6, Vector3(7.3, -0.05, -9.3), "metal")
	lamp.delay = 0.45
	cards.append(lamp)
	var car = _card("car.png", 2.1, Vector3(4.0, -0.04, -8.4), "metal")
	car.delay = 0.6
	cards.append(car)
	car_card = car
	car.base = car.pv.position
	var hedge = _card("hedge.png", 2.9, Vector3(6.6, -0.04, -7.7), "leaf")
	hedge.delay = 0.7
	cards.append(hedge)
	var crates = _card("crates.png", 3.5, Vector3(-4.1, -0.04, -7.0), "wood")
	crates.delay = 0.8
	cards.append(crates)
	wall = _card("wall.png", 5.2, Vector3(1.05, -0.32, -1.35), "brick")
	wall.delay = 1.05
	cards.append(wall)

	# Stellen für Gegner
	for i in HOLES.size():
		var hh = HOLES[i]
		var x = ((hh[0] + hh[1]) * 0.5 - 0.5) * FAC_W
		var ybot = FAC_Y + (1.0 - hh[3]) * fac_h
		if i == 6:   # Haustür: ganze Figur
			slots.append({"pos": Vector3(x, ybot, FAC_Z - 0.3), "mode": "flip", "busy": false, "name": "door"})
		else:
			slots.append({"pos": Vector3(x, ybot - 0.74, FAC_Z - 0.32), "mode": "flip", "busy": false, "name": "window%d" % i})
	slots.append({"pos": Vector3(-2.55, 0.0, -7.4), "mode": "flip", "busy": false, "name": "crates"})
	slots.append({"pos": Vector3(4.25, 0.28, -8.75), "mode": "flip", "busy": false, "name": "car"})
	slots.append({"pos": Vector3(-6.75, 0.0, -9.95), "mode": "flip", "busy": false, "name": "tree"})

	# Staubkörnchen im Abendlicht
	motes = CPUParticles3D.new()
	var mq = QuadMesh.new()
	mq.size = Vector2(0.03, 0.03)
	mq.material = fx_mat_spark
	motes.mesh = mq
	motes.amount = 70
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(7.0, 2.5, 3.0)
	motes.position = Vector3(-1.5, 3.0, -6.0)
	motes.direction = Vector3(1, 0.2, 0)
	motes.spread = 40.0
	motes.gravity = Vector3(0, 0.02, 0)
	motes.initial_velocity_min = 0.05
	motes.initial_velocity_max = 0.18
	var mg = Gradient.new()
	mg.set_color(0, Color(1.0, 0.85, 0.55, 0.0))
	mg.add_point(0.3, Color(1.0, 0.85, 0.55, 0.55))
	mg.add_point(0.7, Color(1.0, 0.8, 0.5, 0.45))
	mg.set_color(mg.get_point_count() - 1, Color(1.0, 0.8, 0.5, 0.0))
	motes.color_ramp = mg
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.3
	add_child(motes)


func _make_sounds() -> void:
	for n in ["shot_player", "shot_enemy", "impact_brick", "impact_metal", "impact_card", "target_up", "target_down", "reload", "empty", "player_hit", "ambience"]:
		for ext in [".ogg", ".wav"]:
			var p = "res://sfx/" + n + ext
			if ResourceLoader.exists(p):
				sounds[n] = load(p)
				break
	# Sprüche: voices[kategorie][stimme] = [Streams]; Stimmen A Boss, B Hitzkopf, C Brecher, D Gangsterin
	for cat in ["appear", "fire", "hit", "taunt", "mandown"]:
		voices[cat] = {}
		for v in ["A", "B", "C", "D"]:
			var arr = []
			for i in range(1, 8):
				var vp = "res://sfx/voice/bark_%s_%s%d.ogg" % [cat, v, i]
				if ResourceLoader.exists(vp):
					arr.append(load(vp))
			voices[cat][v] = arr
	ambience = AudioStreamPlayer.new()
	ambience.stream = sounds.get("ambience")
	ambience.volume_db = -8.0
	add_child(ambience)
	ambience.finished.connect(func(): ambience.play())
	ambience.play()


# Spruch eines Gegners, kommt räumlich von seiner Position
func _bark(e: Dictionary, cat: String, chance: float = 1.0, delay: float = 0.0, force: bool = false) -> void:
	if e.get("box", false) or randf() > chance or not voices.has(cat):
		return
	if not force and bark_cd > 0.0:
		return
	var arr: Array = voices[cat].get(e.get("voice", "A"), [])
	if arr.is_empty():
		return
	bark_cd = 0.9
	var stream = arr[randi() % arr.size()]
	var go = func():
		if not is_instance_valid(e.pv):
			return
		var p = AudioStreamPlayer3D.new()
		p.stream = stream
		p.unit_size = 14.0
		p.volume_db = 2.0
		p.pitch_scale = randf_range(0.97, 1.03)
		p.attenuation_filter_cutoff_hz = 20500.0
		add_child(p)
		p.global_position = e.mi.global_transform * Vector3(0, e.h * 0.85, 0)
		p.finished.connect(p.queue_free)
		p.play()
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(go)
	else:
		go.call()


func _sfx(n: String, vol: float = 0.0, pitch_var: float = 0.08) -> void:
	if not sounds.has(n):
		return
	var p = AudioStreamPlayer.new()
	p.stream = sounds[n]
	p.volume_db = vol
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ================================================================ HUD
class HudDraw extends Control:
	var g   # Hauptszene
	func _draw() -> void:
		g._hud_draw(self)


func _make_hud() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Roboto", "Noto Sans", "DejaVu Sans", "sans-serif"])
	font.font_weight = 700
	font_light = SystemFont.new()
	font_light.font_names = PackedStringArray(["Roboto", "Noto Sans", "DejaVu Sans", "sans-serif"])
	font_light.font_weight = 400
	var layer = CanvasLayer.new()
	add_child(layer)
	vignette = TextureRect.new()
	var vg = Gradient.new()
	vg.set_color(0, Color(0.7, 0.0, 0.0, 0.0))
	vg.add_point(0.55, Color(0.7, 0.0, 0.0, 0.0))
	vg.set_color(vg.get_point_count() - 1, Color(0.75, 0.02, 0.0, 0.85))
	var vt = GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.05, 1.05)
	vt.width = 128
	vt.height = 128
	vignette.texture = vt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	layer.add_child(vignette)
	hud = HudDraw.new()
	hud.g = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)


func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size


func _panel(c: Control, r: Rect2, a: float = 0.55) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.05, a)
	sb.border_color = Color(1, 1, 1, 0.12 * a / 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	c.draw_style_box(sb, r)


func _text(c: Control, pos: Vector2, s: String, size: int, col: Color = Color.WHITE, align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1, f: Font = null) -> void:
	if f == null:
		f = font
	c.draw_string_outline(f, pos, s, align, w, size, 4, Color(0, 0, 0, 0.45 * col.a))
	c.draw_string(f, pos, s, align, w, size, col)


func _thumb_home() -> Vector2:
	return _vs() * thumb_n


func _fire_center() -> Vector2:
	return _vs() * fire_n


func _nade_center() -> Vector2:
	return _fire_center() + Vector2(-14, -168)


func _frozen() -> bool:
	# Einstell-Leiste offen oder Knöpfe verschieben: Gegner warten
	return panel_k > 0.02 or editing


func _tab_rect() -> Rect2:
	var vs = _vs()
	return Rect2(vs.x - PANEL_W * panel_k - 34, vs.y * 0.42 - 48, 34, 96)


func _panel_rect() -> Rect2:
	var vs = _vs()
	return Rect2(vs.x - PANEL_W * panel_k, 74, PANEL_W, 458)


func _slider_rect(i: int) -> Rect2:
	var pr = _panel_rect()
	return Rect2(pr.position.x + 22, pr.position.y + 16 + i * 66 + 34, PANEL_W - 44, 26)


func _panel_btn_rect(i: int) -> Rect2:
	var pr = _panel_rect()
	return Rect2(pr.position.x + 22, pr.position.y + 296 + i * 54, PANEL_W - 44, 44)


func _done_btn_rect() -> Rect2:
	var vs = _vs()
	return Rect2(vs.x * 0.5 - 90, 92, 180, 50)


func _slider_set(i: int, x: float) -> void:
	var sd = SLIDERS[i]
	var r = _slider_rect(i)
	var k = clampf((x - r.position.x) / r.size.x, 0, 1)
	set(sd.key, snappedf(lerpf(sd.min, sd.max, k), 0.05))


# Tipp auf Leiste, Regler oder Knöpfe im Bearbeiten-Modus. true = verbraucht
func _ui_press(p: Vector2, idx: int) -> bool:
	if editing:
		if _done_btn_rect().grow(10).has_point(p):
			editing = false
			_save()
		elif p.distance_to(_thumb_home()) < 95:
			ui_idx = idx
			ui_drag = "thumb"
		elif p.distance_to(_fire_center()) < 95:
			ui_idx = idx
			ui_drag = "fire"
		return true
	if _tab_rect().grow(8).has_point(p):
		panel_open = not panel_open
		return true
	if panel_k > 0.5 and _panel_rect().has_point(p):
		for i in SLIDERS.size():
			if _slider_rect(i).grow(14).has_point(p):
				ui_idx = idx
				ui_drag = "slider%d" % i
				_slider_set(i, p.x)
				return true
		if _panel_btn_rect(0).has_point(p):
			aim_mode = "free" if aim_mode == "snap" else "snap"
			_save()
		elif _panel_btn_rect(1).has_point(p):
			editing = true
			panel_open = false
			cover = true
			aim_idx = -1
		elif _panel_btn_rect(2).has_point(p):
			aim_mode = "snap"
			aim_sens = 1.7
			aim_accel = 1.0
			recenter = 0.6
			aim_assist = 0.35
			thumb_n = Vector2(0.2, 0.64)
			fire_n = Vector2(0.906, 0.7)
			_save()
		return true
	return false


func _upd_btn_rect() -> Rect2:
	var vs = _vs()
	return Rect2(vs.x * 0.5 - 170, vs.y - 92, 340, 58)


func _hud_draw(c: Control) -> void:
	var vs = _vs()
	var playing = state == "play" or state == "intro"
	if state == "play":
		# Gefahren-Ringe: Gegner, der gleich schießt
		for e in enemies:
			if e.state == "aim" and e.t > e.aim - 0.75:
				var k = clampf((e.t - (e.aim - 0.75)) / 0.75, 0, 1)
				var sp = cam.unproject_position(_muzzle(e))
				if cam.is_position_behind(_muzzle(e)):
					continue
				var r = lerpf(70.0, 22.0, k)
				var col = Color(1.0, 0.2, 0.12, 0.35 + 0.55 * k)
				c.draw_arc(sp, r, 0, TAU, 40, col, 3.0, true)
				c.draw_arc(sp, r * 0.55, 0, TAU, 30, Color(col.r, col.g, col.b, col.a * 0.6), 2.0, true)
		# Fadenkreuz
		if not cover:
			var p = aim + Vector2(0, -kick * 26.0)
			var g = 9.0 + kick * 14.0
			var l = 16.0
			var cc = Color(1, 1, 1, 0.95)
			var oc = Color(0, 0, 0, 0.55)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				c.draw_line(p + d * g, p + d * (g + l), oc, 5.0, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				c.draw_line(p + d * g, p + d * (g + l), cc, 2.4, true)
			c.draw_circle(p, 2.6, oc)
			c.draw_circle(p, 1.6, cc)
			if hit_mark > 0:
				var hc = Color(1.0, 0.25, 0.15, hit_mark)
				for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
					c.draw_line(p + d * 8, p + d * 18, hc, 3.0, true)
	if playing or state == "over":
		# Leben oben links
		_panel(c, Rect2(20, 18, 330, 50))
		var cx = 46.0
		var cy = 43.0
		c.draw_rect(Rect2(cx - 11, cy - 3.5, 22, 7), Color.WHITE)
		c.draw_rect(Rect2(cx - 3.5, cy - 11, 7, 22), Color.WHITE)
		var bw = 200.0
		c.draw_rect(Rect2(70, 34, bw, 18), Color(0, 0, 0, 0.5))
		var hk = clampf(health / 100.0, 0, 1)
		var hcol = Color(0.36, 0.86, 0.3).lerp(Color(0.95, 0.25, 0.15), clampf(1.0 - hk * 1.6, 0, 1))
		c.draw_rect(Rect2(70, 34, bw * hk, 18), hcol)
		_text(c, Vector2(282, 51), "%d" % ceili(health), 20)
		# Punkte oben rechts
		_panel(c, Rect2(vs.x - 270, 18, 250, 50))
		_text(c, Vector2(vs.x - 252, 51), "SCORE", 17, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
		_text(c, Vector2(vs.x - 252, 52), "%06d" % score, 28, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 214)
		# Stufe und Treffer oben Mitte
		_text(c, Vector2(0, 50), "STAGE %d  ·  %d / %d" % [stage, kills % KILLS_PER_STAGE, KILLS_PER_STAGE], 17, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
		# Munition unten rechts
		_panel(c, Rect2(vs.x - 250, vs.y - 86, 230, 66))
		if weapon != "pistol":
			_text(c, Vector2(vs.x - 232, vs.y - 45), WPN_NAMES.get(weapon, ""), 19, Color(1.0, 0.82, 0.45), HORIZONTAL_ALIGNMENT_LEFT, -1)
			_text(c, Vector2(vs.x - 92, vs.y - 43), "%d" % wpn_ammo, 34, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 70)
		else:
			for i in MAG:
				var bx = vs.x - 232 + i * 17
				var full = i < ammo
				var bc = Color(1.0, 0.82, 0.45) if full else Color(1, 1, 1, 0.16)
				c.draw_rect(Rect2(bx, vs.y - 70, 9, 24), bc)
				c.draw_circle(Vector2(bx + 4.5, vs.y - 70), 4.5, bc)
			_text(c, Vector2(vs.x - 92, vs.y - 43), "%d" % ammo, 34, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 56)
			_text(c, Vector2(vs.x - 34, vs.y - 43), "/%d" % MAG, 17, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
	if state == "play":
		# linkes Daumenfeld: halten = aufstehen und zielen
		var tc = thumb if (aim_idx >= 0 and not editing) else _thumb_home()
		var held = aim_idx >= 0
		c.draw_circle(tc, 62, Color(0.06, 0.05, 0.05, 0.4 if held else 0.3))
		c.draw_arc(tc, 62, 0, TAU, 48, Color(1, 1, 1, 0.7 if held else 0.35), 2.5, true)
		c.draw_circle(tc, 20, Color(1, 1, 1, 0.55 if held else 0.25))
		if not held:
			_text(c, tc + Vector2(-90, 92), "HOLD TO AIM", 15, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 180, font_light)
		# Feuerknopf rechts
		var fc = _fire_center()
		var can = not cover
		c.draw_circle(fc, 70, Color(0.55, 0.08, 0.04, 0.55 if can else 0.25))
		c.draw_arc(fc, 70, 0, TAU, 48, Color(1, 0.75, 0.6, 0.85 if can else 0.3), 3.0, true)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			c.draw_line(fc + d * 12, fc + d * 30, Color(1, 1, 1, 0.9 if can else 0.35), 3.0, true)
		c.draw_arc(fc, 21, 0, TAU, 32, Color(1, 1, 1, 0.9 if can else 0.35), 3.0, true)
		# Granaten-Knopf mit Anzahl
		var gc = _nade_center()
		var has = grenades > 0
		c.draw_circle(gc, 44, Color(0.06, 0.05, 0.05, 0.55 if has else 0.3))
		c.draw_arc(gc, 44, 0, TAU, 40, Color(0.7, 0.85, 0.45, 0.85 if has else 0.3), 2.5, true)
		c.draw_texture_rect(tex_nade, Rect2(gc - Vector2(17, 24), Vector2(34, 46)), false, Color(1, 1, 1, 1.0 if has else 0.35))
		c.draw_circle(gc + Vector2(30, -30), 14, Color(0.12, 0.1, 0.08, 0.9))
		_text(c, gc + Vector2(16, -23), "%d" % grenades, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 28)
		# anfliegende Gegner-Granate: roter Ring zum Abschießen
		for pr in projs:
			if pr.kind == "enade" and is_instance_valid(pr.n) and not cam.is_position_behind(pr.n.global_position):
				var gsp = cam.unproject_position(pr.n.global_position)
				var bl = 0.5 + 0.5 * sin(st_t * 18.0)
				c.draw_arc(gsp, 34, 0, TAU, 36, Color(1.0, 0.2, 0.1, 0.6 + 0.4 * bl), 3.5, true)
				c.draw_arc(gsp, 50, 0, TAU, 36, Color(1.0, 0.2, 0.1, 0.35 * bl), 2.0, true)
		if ammo == 0 and not cover and reload_t <= 0:
			var bl = 0.55 + 0.45 * sin(st_t * 10.0)
			_text(c, Vector2(0, vs.y * 0.66), "RELOAD  –  LET GO TO TAKE COVER", 30, Color(1, 0.85, 0.4, bl), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		if cover and reload_t > 0:
			_text(c, Vector2(0, vs.y * 0.62), "RELOADING", 24, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
		if tip_t > 0:
			var ta = clampf(tip_t, 0, 1)
			_text(c, Vector2(0, vs.y - 30), "Left thumb: hold to stand up and drag to aim  ·  let go to take cover and reload  ·  right: FIRE", 17, Color(1, 1, 1, 0.8 * ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
	if state == "play":
		_settings_draw(c)
	# große Meldungen
	if msg_t > 0 and msg != "" and not editing:
		var a = clampf(msg_t * 2.5, 0, 1)
		var sc = 1.0 + maxf(0.0, 0.25 - (msg_dur - msg_t)) * 1.6
		_text(c, Vector2(0, vs.y * 0.42), msg, int(64 * sc), Color(1, 0.93, 0.8, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		if msg_sub != "":
			_text(c, Vector2(0, vs.y * 0.42 + 46), msg_sub, 22, Color(1, 1, 1, 0.8 * a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
	if state == "title":
		var a = clampf(st_t * 1.5 - 0.6, 0, 1)
		c.draw_rect(Rect2(0, 0, vs.x, vs.y), Color(0.05, 0.03, 0.02, 0.25 * a))
		_text(c, Vector2(0, vs.y * 0.4), "SHOOTER", 96, Color(1, 0.95, 0.86, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(c, Vector2(0, vs.y * 0.4 + 40), "GOLDEN HOUR SHOOTOUT", 20, Color(1, 0.86, 0.6, 0.9 * a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
		if best > 0:
			_text(c, Vector2(0, vs.y * 0.4 + 80), "BEST  %06d" % best, 20, Color(1, 1, 1, 0.75 * a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
		var bl = 0.45 + 0.55 * absf(sin(st_t * 2.6))
		_text(c, Vector2(0, vs.y * 0.74), "TAP TO START", 30, Color(1, 1, 1, bl * a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(c, Vector2(vs.x - 220, vs.y - 18), "Build %d" % _my_build(), 14, Color(1, 1, 1, 0.5 * a), HORIZONTAL_ALIGNMENT_RIGHT, 200, font_light)
		_upd_draw(c, a)
	if state == "over" and st_t > 1.2:
		var a = clampf((st_t - 1.2) * 2.0, 0, 1)
		_text(c, Vector2(0, vs.y * 0.62), "TAP TO PLAY AGAIN", 26, Color(1, 1, 1, a * (0.45 + 0.55 * absf(sin(st_t * 2.6)))), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_upd_draw(c, a)


func _settings_draw(c: Control) -> void:
	var vs = _vs()
	# Lasche am rechten Rand
	var tr = _tab_rect()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.05, 0.6)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 10
	sb.corner_radius_bottom_left = 10
	c.draw_style_box(sb, tr)
	var tc = tr.get_center()
	for i in 3:
		var y = tc.y - 12 + i * 12
		c.draw_line(Vector2(tc.x - 7, y), Vector2(tc.x + 7, y), Color(1, 1, 1, 0.8), 2.0, true)
		var kx = tc.x - 7 + [10, 3, 8][i]
		c.draw_circle(Vector2(kx, y), 3.2, Color.WHITE)
	if panel_k > 0.01:
		var pr = _panel_rect()
		var ps = StyleBoxFlat.new()
		ps.bg_color = Color(0.06, 0.05, 0.05, 0.62)
		ps.border_color = Color(1, 1, 1, 0.14)
		ps.border_width_left = 1
		ps.border_width_top = 1
		ps.border_width_bottom = 1
		ps.corner_radius_top_left = 12
		ps.corner_radius_bottom_left = 12
		c.draw_style_box(ps, pr)
		for i in SLIDERS.size():
			var sd = SLIDERS[i]
			var r = _slider_rect(i)
			var val: float = get(sd.key)
			var k = clampf((val - sd.min) / (sd.max - sd.min), 0, 1)
			var vt: String
			if sd.key == "recenter" or sd.key == "aim_assist":
				vt = "OFF" if val <= 0.001 else "%d %%" % roundi(val * 100.0)
			elif sd.key == "aim_accel":
				vt = "OFF" if val <= 0.001 else "%.1f" % val
			else:
				vt = "%.1f ×" % val
			_text(c, Vector2(r.position.x, r.position.y - 12), sd.label, 14, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
			_text(c, Vector2(r.position.x, r.position.y - 12), vt, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x)
			var cy = r.get_center().y
			c.draw_line(Vector2(r.position.x, cy), Vector2(r.end.x, cy), Color(1, 1, 1, 0.22), 4.0, true)
			c.draw_line(Vector2(r.position.x, cy), Vector2(r.position.x + r.size.x * k, cy), Color(1.0, 0.78, 0.45), 4.0, true)
			c.draw_circle(Vector2(r.position.x + r.size.x * k, cy), 11.0, Color.WHITE)
		for i in 3:
			var br = _panel_btn_rect(i)
			var bs = StyleBoxFlat.new()
			bs.bg_color = Color(1, 1, 1, 0.1)
			bs.border_color = Color(1, 1, 1, 0.35)
			bs.set_border_width_all(1)
			bs.set_corner_radius_all(22)
			c.draw_style_box(bs, br)
			_text(c, Vector2(br.position.x, br.position.y + 29), [("AIM:  SNAP TO SPOTS" if aim_mode == "snap" else "AIM:  FREE"), "MOVE BUTTONS", "RESET"][i], 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, br.size.x, font_light)
		_text(c, Vector2(pr.position.x, pr.end.y + 24), "Enemies wait while this is open", 13, Color(1, 1, 1, 0.6 * panel_k), HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, font_light)
	if editing:
		c.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.25))
		_text(c, Vector2(0, 178), "Drag the buttons where your thumbs like them", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
		var dr = _done_btn_rect()
		var ds = StyleBoxFlat.new()
		ds.bg_color = Color(0.95, 0.62, 0.2, 0.95)
		ds.set_corner_radius_all(25)
		c.draw_style_box(ds, dr)
		_text(c, Vector2(dr.position.x, dr.position.y + 34), "DONE", 20, Color(0.1, 0.06, 0.03), HORIZONTAL_ALIGNMENT_CENTER, dr.size.x)
		for pnt in [_thumb_home(), _fire_center()]:
			c.draw_arc(pnt, 86, 0, TAU, 56, Color(1.0, 0.78, 0.45, 0.9), 2.0, true)


func _upd_draw(c: Control, a: float) -> void:
	var mine = _my_build()
	if upd_url == "" or mine <= 0 or upd_build <= mine:
		return
	var r = _upd_btn_rect()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.62, 0.2, 0.92 * a)
	sb.set_corner_radius_all(29)
	c.draw_style_box(sb, r)
	_text(c, Vector2(r.position.x, r.position.y + 37), "UPDATE  ·  Build %d" % upd_build, 21, Color(0.1, 0.06, 0.03, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


# ================================================================ Ablauf
func _set_state(s: String) -> void:
	state = s
	st_t = 0.0


func _show_msg(m: String, sub: String = "", dur: float = 2.0) -> void:
	msg = m
	msg_sub = sub
	msg_t = dur
	msg_dur = dur


func _open_book(start_delay: float) -> void:
	for c in cards:
		if c.get("static", false) or c.kind == "sky" or c.kind == "room":
			continue
		c.t = -start_delay - c.delay
		c.up = true


func _close_book() -> void:
	for c in cards:
		if c.get("static", false) or c.kind == "sky" or c.kind == "room":
			continue
		c.t = -c.delay * 0.4
		c.up = false


func _start_game() -> void:
	for e in enemies:
		e.pv.queue_free()
	enemies.clear()
	for s in slots:
		s.busy = false
	for h in holes_live:
		if is_instance_valid(h):
			h.queue_free()
	holes_live.clear()
	health = 100.0
	score = 0
	kills = 0
	stage = 1
	ammo = MAG
	weapon = "pistol"
	wpn_ammo = 0
	grenades = 1
	fire_idx = -1
	cover_time = 0.0
	nade_limit = 4.5
	for pr in projs:
		if is_instance_valid(pr.n):
			pr.n.queue_free()
	projs.clear()
	_car_reset()
	reload_t = 0.0
	cover = true
	aim_idx = -1
	aim = _vs() * Vector2(0.5, 0.45)
	spawn_t = 2.6
	shots_fired = 0
	hits = 0
	tip_t = 7.0
	_set_state("intro")
	_show_msg("GET READY", "", 2.2)


func _game_over() -> void:
	_set_state("over")
	for pr in projs:
		if is_instance_valid(pr.n):
			pr.n.queue_free()
	projs.clear()
	cover = false
	var newbest = score > best
	if newbest:
		best = score
		_save()
	var acc = 0
	if shots_fired > 0:
		acc = roundi(100.0 * hits / shots_fired)
	_show_msg("GAME OVER", ("NEW BEST  %06d" % score) if newbest else ("SCORE %06d  ·  BEST %06d  ·  ACCURACY %d%%" % [score, best, acc]), 999.0)
	for e in enemies:
		if e.state != "fall":
			e.state = "hide"
			e.t = 0.0


func _pop(t: float) -> float:
	# Feder: klappt hoch, schwingt leicht über und pendelt aus
	if t <= 0.0:
		return 0.0
	return 1.0 - exp(-7.5 * t) * cos(12.5 * t)


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	st_t += dt
	msg_t = maxf(0.0, msg_t - dt)
	tip_t = maxf(0.0, tip_t - dt)
	bark_cd = maxf(0.0, bark_cd - dt)
	kick = maxf(0.0, kick - dt * 6.0)
	shake = maxf(0.0, shake - dt * 3.0)
	hurt = maxf(0.0, hurt - dt * 1.6)
	hit_mark = maxf(0.0, hit_mark - dt * 3.0)
	vignette.modulate.a = hurt
	panel_k = move_toward(panel_k, 1.0 if (panel_open and state == "play") else 0.0, dt / 0.18)
	if state != "play":
		editing = false
	# Snap: Fadenkreuz gleitet auf die Zone in Daumenrichtung und schwankt dort leicht wie eine ruhige Hand
	if aim_idx >= 0 and aim_mode == "snap" and state == "play" and not editing:
		var tgt = _snap_target()
		var tt = Time.get_ticks_msec() / 1000.0
		var sway = Vector2(sin(tt * 1.3) * 2.6 + sin(tt * 3.1 + 1.0) * 1.2, sin(tt * 1.7 + 2.0) * 2.0 + sin(tt * 2.6) * 1.0)
		aim = aim.lerp(tgt + sway, 1.0 - exp(-dt * 17.0))
	# losgelassen: Fadenkreuz gleitet zurück zur Bildmitte
	if aim_idx < 0 and recenter > 0.0:
		aim = aim.lerp(_vs() * Vector2(0.5, 0.45), 1.0 - exp(-dt * recenter * 12.0))

	# Pop-up-Buch: Kulissen klappen auf oder zu
	for c in cards:
		if c.get("static", false) or c.kind == "sky" or c.kind == "room" or c.get("dead", false):
			continue
		var prev = c.t
		c.t += dt
		var k: float
		if c.up:
			k = _pop(c.t * 1.15)
			if prev <= 0.0 and c.t > 0.0:
				_sfx("target_up", -4.0 if c.kind != "brick" else 0.0, 0.15)
		else:
			k = 1.0 - clampf(c.t * 3.2, 0, 1) * clampf(c.t * 3.2, 0, 1)
		c.pv.rotation.x = -PI * 0.5 * (1.0 - k)

	match state:
		"title":
			pass
		"intro":
			if st_t > 1.6:
				_set_state("play")
		"play":
			_play_update(dt)
		"over":
			pass

	_enemies_update(dt)
	_proj_update(dt)
	_fb_update(dt)
	_camera_update(dt)
	if autotest:
		_autotest(dt)
	hud.queue_redraw()


func _play_update(dt: float) -> void:
	# Nachladen nur in Deckung
	if cover and ammo < MAG:
		if reload_t <= 0:
			reload_t = RELOAD_TIME
			_sfx("reload", -3.0, 0.03)
		reload_t -= dt
		if reload_t <= 0:
			ammo = MAG
			reload_t = 0.0
	elif not cover:
		reload_t = 0.0
	# Maschinengewehr: Feuerknopf halten = Dauerfeuer
	if weapon == "smg" and fire_idx >= 0 and not cover:
		auto_t -= dt
		if auto_t <= 0.0:
			_shoot(aim)
			auto_t = 0.09
	# zu lange in Deckung: ein Gegner wirft eine Granate über die Mauer
	if not _frozen():
		if cover:
			cover_time += dt
		else:
			cover_time = maxf(0.0, cover_time - dt * 2.0)
		if cover_time > nade_limit:
			var thrower = {}
			for e in enemies:
				if not e.get("box", false) and (e.state == "aim" or e.state == "linger"):
					thrower = e
					break
			var flying = false
			for pr in projs:
				if pr.kind == "enade":
					flying = true
			if not thrower.is_empty() and not flying:
				_enemy_grenade(thrower)
				cover_time = 0.0
				nade_limit = maxf(2.6, randf_range(3.6, 5.0) - stage * 0.2)
	# Gegner nachschicken
	var alive = 0
	for e in enemies:
		if e.state != "fall" and not e.get("box", false):
			alive += 1
	var max_alive = 1
	if kills >= 4:
		max_alive = 2
	if stage >= 3:
		max_alive = 3
	if _frozen():
		return
	spawn_t -= dt
	if spawn_t <= 0 and alive < max_alive:
		_spawn()
		var base = maxf(0.6, 1.9 - stage * 0.25)
		spawn_t = base * randf_range(0.6, 1.25)
	if health <= 0:
		_game_over()


func _diff_aim() -> float:
	return maxf(0.75, 1.75 - (stage - 1) * 0.2 - kills % KILLS_PER_STAGE * 0.015)


func _spawn() -> void:
	var free = []
	for s in slots:
		if not s.busy and not s.get("off", false):
			free.append(s)
	if free.is_empty():
		return
	var s = free[randi() % free.size()]
	s.busy = true
	var boxes = 0
	for e in enemies:
		if e.get("box", false):
			boxes += 1
	if boxes == 0 and kills >= 2 and randf() < 0.16:
		_spawn_box(s, kills >= 5 and randf() < 0.15)
		return
	var ti = randi() % ENEMY_TEX.size()
	var tex: Texture2D = load("res://art/" + ENEMY_TEX[ti] + ".png")
	var w = ENEMY_H * tex.get_width() / float(tex.get_height())
	var c = _card(ENEMY_TEX[ti] + ".png", w, s.pos, "card", ENEMY_H)
	c.merge({"slot": s, "state": "appear", "t": 0.0, "aim": _diff_aim() * randf_range(0.85, 1.2), "shots": 1 + (1 if stage >= 2 and randf() < 0.35 else 0), "gun_v": GUN_V[ti], "mode": s.mode, "seen": 0.0, "side": -1.0 if randf() < 0.5 else 1.0, "voice": ["A", "B", "C", "D"][randi() % 4]}, true)
	_enemy_pose(c, 0.0)
	enemies.append(c)
	_sfx("target_up", -6.0, 0.12)
	_bark(c, "appear", 0.55, 0.25)


func _spawn_box(s: Dictionary, mega: bool) -> void:
	var pos: Vector3 = s.pos
	if s.name.begins_with("window"):
		pos.y += 0.74
		pos.z += 0.1
	elif s.name == "car":
		pos.y += 1.02
	var c = _card("box_mega.png" if mega else "box.png", 0.85 if mega else 0.8, pos, "box")
	c.merge({"slot": s, "state": "appear", "t": 0.0, "aim": 99.0, "shots": 0, "gun_v": 0.5, "mode": "flip", "seen": 0.0, "side": 1.0,
		"box": true, "mega": mega, "life": 2.4 if mega else 3.2}, true)
	_enemy_pose(c, 0.0)
	enemies.append(c)
	_sfx("target_up", -4.0, 0.12)
	if mega:
		_sfx("mega_appear", -2.0, 0.0)
		var l = OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.3)
		l.omni_range = 2.6
		l.light_energy = 2.5
		l.position = Vector3(0, c.h * 0.5, 0.35)
		c.mi.add_child(l)
		c.glow = l
		var sp = CPUParticles3D.new()
		var q = QuadMesh.new()
		q.size = Vector2(0.05, 0.05)
		q.material = fx_mat_spark
		sp.mesh = q
		sp.amount = 18
		sp.lifetime = 0.9
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		sp.emission_box_extents = Vector3(c.w * 0.55, c.h * 0.5, 0.05)
		sp.position = Vector3(0, c.h * 0.5, 0.12)
		sp.gravity = Vector3(0, 0.6, 0)
		sp.initial_velocity_min = 0.1
		sp.initial_velocity_max = 0.4
		var g = Gradient.new()
		g.set_color(0, Color(3.0, 2.4, 0.9, 0.0))
		g.add_point(0.25, Color(3.0, 2.4, 0.9, 1.0))
		g.set_color(g.get_point_count() - 1, Color(2.0, 1.4, 0.4, 0.0))
		sp.color_ramp = g
		sp.scale_amount_min = 0.4
		sp.scale_amount_max = 1.2
		c.mi.add_child(sp)


func _open_box(c: Dictionary) -> void:
	c.state = "fall"
	c.t = 0.0
	var title = ""
	var sub = ""
	var pts = 50
	var r = ""
	if c.mega:
		r = ["rocket", "bonanza"][randi() % 2]
		pts = 250
	else:
		var x = randf()
		r = "grenade" if x < 0.3 else ("health" if x < 0.55 else ("shotgun" if x < 0.8 else "smg"))
	match r:
		"grenade":
			grenades += 1
			title = "+1 GRENADE"
		"health":
			health = minf(100.0, health + 30.0)
			title = "+30 HEALTH"
		"shotgun":
			weapon = "shotgun"
			wpn_ammo = 8
			title = "SHOTGUN"
			sub = "8 shells"
		"smg":
			weapon = "smg"
			wpn_ammo = 40
			title = "MACHINE GUN"
			sub = "hold FIRE"
		"rocket":
			weapon = "rocket"
			wpn_ammo = 3
			title = "ROCKET LAUNCHER"
			sub = "3 rockets"
		"bonanza":
			health = 100.0
			grenades += 3
			title = "FULL HEALTH"
			sub = "+3 GRENADES"
	score += pts
	_show_msg(title, sub, 1.6)
	_sfx("pickup", 0.0, 0.0)
	var cp: Vector3 = c.mi.global_transform * Vector3(0, c.h * 0.5, 0.1)
	fx_k = clampf(cp.distance_to(cam.global_position) / 7.0, 0.22, 1.3)
	_sparks(cp, Vector3(0, 0.5, 1).normalized(), 26 if c.mega else 14)
	_float_text(cp + Vector3(0, 0.3, 0.1), "+%d" % pts, c.mega)


# Gegner (oder Box) erledigt – auch von Explosionen
func _kill_enemy(c: Dictionary, point: Vector3, head: bool) -> void:
	if c.get("box", false):
		_open_box(c)
		return
	hits += 1
	var pts = 100 + int(clampf(1.0 - c.seen / maxf(c.aim, 0.1), 0, 1) * 100.0)
	if head:
		pts += 50
	score += pts
	kills += 1
	hit_mark = 1.0
	c.state = "fall"
	c.t = 0.0
	_bark(c, "hit", 1.0, 0.0, true)
	for o in enemies:
		if o != c and o.state != "fall" and o.state != "hide" and not o.get("box", false):
			_bark(o, "mandown", 0.5, 0.75, true)
			break
	_float_text(point + Vector3(0, 0.25, 0.1), ("HEADSHOT  +%d" if head else "+%d") % pts, head)
	if kills % KILLS_PER_STAGE == 0:
		stage += 1
		health = minf(100.0, health + 25.0)
		_show_msg("STAGE %d" % stage, "+25 HEALTH", 2.2)


func _enemy_pose(e: Dictionary, k: float) -> void:
	# k = 1: steht und zeigt zum Spieler, k = 0: verdeckt (seitlich weggedreht bzw. flach hingelegt)
	if e.mode == "turn":
		e.pv.rotation = Vector3(0, e.side * PI * 0.5 * (1.0 - k), 0)
	else:
		e.pv.rotation = Vector3(-PI * 0.5 * (1.0 - k), 0, 0)


func _muzzle(e: Dictionary) -> Vector3:
	return e.mi.global_transform * Vector3(0.0, (1.0 - e.gun_v) * e.h, 0.06)


func _enemies_update(dt: float) -> void:
	var gone = []
	for e in enemies:
		e.t += dt
		match e.state:
			"appear":
				var k = _pop(e.t * 1.3)
				_enemy_pose(e, k)
				if e.t > 0.55:
					e.state = "aim"
					e.t = 0.0
			"aim":
				_enemy_pose(e, 1.0)
				if _frozen():
					e.t -= dt
					continue
				if e.get("box", false):
					if e.mega:
						var pu = 0.5 + 0.5 * sin(e.t * 9.0)
						e.mat.set_shader_parameter("flash", 0.12 + 0.22 * pu)
						if e.has("glow") and is_instance_valid(e.glow):
							e.glow.light_energy = 1.5 + 2.5 * pu
					if e.t > e.life and state == "play":
						e.state = "hide"
						e.t = 0.0
					continue
				e.seen += dt
				if state != "play":
					continue
				if e.t >= e.aim:
					_enemy_fire(e)
					e.shots -= 1
					if e.shots > 0:
						e.aim = 0.65
						e.t = 0.0
					else:
						e.state = "linger"
						e.t = 0.0
			"linger":
				if e.t > 0.45:
					e.state = "hide"
					e.t = 0.0
			"hide":
				var k = 1.0 - clampf(e.t / 0.28, 0, 1)
				_enemy_pose(e, k * k)
				if e.t > 0.3:
					gone.append(e)
			"fall":
				var f: float
				var ft = e.t
				if ft < 0.32:
					f = pow(ft / 0.32, 2.0)
				else:
					f = 1.0 - 0.09 * absf(sin((ft - 0.32) * 13.0)) * exp(-(ft - 0.32) * 7.0)
				var base = e.pv.rotation
				if e.mode == "turn":
					e.pv.rotation = Vector3(-PI * 0.5 * f, 0, 0)
				else:
					e.pv.rotation = Vector3(-PI * 0.5 * f, 0, 0)
				e.mat.set_shader_parameter("flash", maxf(0.0, 0.6 - ft * 4.0))
				if ft > 0.3 and not e.get("thud", false):
					e.thud = true
					_sfx("target_down", -2.0)
				if ft > 1.4:
					gone.append(e)
	for e in gone:
		e.slot.busy = false
		e.pv.queue_free()
		enemies.erase(e)


func _enemy_fire(e: Dictionary) -> void:
	_bark(e, "fire", 0.3)
	var mp = _muzzle(e)
	_flash(mp + Vector3(0, 0, 0.15), 0.9, Color(1.0, 0.7, 0.35), 7.0)
	_smoke(mp, 4)
	_sfx("shot_enemy", -2.0, 0.1)
	var acc = minf(0.7, 0.38 + stage * 0.05)
	if not cover and cover_k < 0.5 and randf() < acc:
		health -= randf_range(9.0, 14.0)
		hurt = 0.85
		shake = 0.7
		_sfx("player_hit", 0.0, 0.04)
		_bark(e, "taunt", 0.6, 0.45, true)
		if not autotest:
			Input.vibrate_handheld(70)
	else:
		# Kugel schlägt in die Mauer vor einem ein
		_wall_hit()


func _wall_hit() -> void:
	# Die Kugel kommt von vorn: sie schlägt oben auf der Mauerkrone ein, nie auf unserer Seite
	var img: Image = wall.img
	for i in 8:
		var wx = cam.global_position.x + randf_range(-1.0, 1.0)
		var lx = wx - wall.pv.global_position.x
		var u = lx / wall.w + 0.5
		if u < 0.02 or u > 0.98:
			continue
		var px = clampi(int(u * img.get_width()), 0, img.get_width() - 1)
		var vt = -1.0
		for py in img.get_height():
			if img.get_pixel(px, py).a > 0.5:
				vt = float(py) / img.get_height()
				break
		if vt < 0 or vt > 0.5:
			continue
		var lp = Vector3(lx, (1.0 - vt) * wall.h - 0.015, -0.04)
		var p: Vector3 = wall.mi.global_transform * lp
		var n = Vector3(randf_range(-0.3, 0.3), 1.0, 0.45).normalized()
		fx_k = clampf(p.distance_to(cam.global_position) / 7.0, 0.22, 1.3)
		_sparks(p, n, 10)
		_dust(p, n, 6, Color(0.78, 0.64, 0.5), 0.35)
		_chunks(p, n, 10, [Color(0.6, 0.33, 0.22), Color(0.82, 0.74, 0.62), Color(0.45, 0.3, 0.22)], 0.035)
		_sfx("impact_brick", -3.0, 0.15)
		return


# ================================================================ Kamera
func _camera_update(dt: float) -> void:
	var target_k = 1.0 if cover else 0.0
	cover_k = move_toward(cover_k, target_k, dt / 0.2)
	var ck = cover_k * cover_k * (3.0 - 2.0 * cover_k)
	var vs = _vs()
	aim_n = Vector2((aim.x / vs.x - 0.5) * 2.0, (aim.y / vs.y - 0.5) * 2.0)
	aim_s = aim_s.lerp(aim_n, 1.0 - exp(-dt * 4.0))
	var pos = CAM_UP.lerp(CAM_COVER, ck)
	var pitch = lerpf(CAM_UP_PITCH, CAM_COVER_PITCH, ck)
	# Parallaxe: Kamera wandert leicht mit dem Fadenkreuz
	pos += Vector3(aim_s.x * 0.42, -aim_s.y * 0.12, 0) * (1.0 - ck * 0.5)
	var yaw = -aim_s.x * 3.5
	pitch -= aim_s.y * 2.2
	# Atmen
	var tt = Time.get_ticks_msec() / 1000.0
	pos += Vector3(sin(tt * 0.7) * 0.03, sin(tt * 1.1) * 0.02, 0)
	var ik = 0.0
	if state == "title" or state == "boot":
		ik = 1.0
	elif state == "intro":
		var q = clampf(st_t / 1.5, 0, 1)
		ik = 1.0 - q * q * (3.0 - 2.0 * q)
	elif state == "over":
		var q = clampf(st_t / 2.5, 0, 1)
		ik = q * q * (3.0 - 2.0 * q) * 0.6
	if ik > 0:
		var ipos = CAM_INTRO + Vector3(sin(tt * 0.25) * 1.2, 0, 0)
		pos = pos.lerp(ipos, ik)
		pitch = lerpf(pitch, CAM_INTRO_PITCH, ik)
		yaw = lerpf(yaw, -sin(tt * 0.25) * 3.0, ik)
	# Rückstoß und Erschütterung
	pitch += kick * 1.6
	var sh = shake * shake
	pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * sh * 0.05
	cam.position = pos
	cam.rotation_degrees = Vector3(pitch, yaw, sh * randf_range(-1.5, 1.5))


# ================================================================ Eingabe
func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_press(ev.position, ev.index)
		elif ev.index == ui_idx:
			ui_idx = -1
			ui_drag = ""
			_save()
		elif ev.index == fire_idx:
			fire_idx = -1
		elif ev.index == aim_idx:
			# Daumen weg: zurück in Deckung (lädt automatisch nach), Fadenkreuz gleitet zur Mitte
			aim_idx = -1
			cover = true
	elif ev is InputEventScreenDrag:
		var vs = _vs()
		if ev.index == ui_idx:
			if ui_drag.begins_with("slider"):
				_slider_set(int(ui_drag.substr(6)), ev.position.x)
			elif ui_drag == "thumb":
				thumb_n = (ev.position / vs).clamp(Vector2(0.06, 0.12), Vector2(0.94, 0.9))
			elif ui_drag == "fire":
				fire_n = (ev.position / vs).clamp(Vector2(0.06, 0.12), Vector2(0.94, 0.9))
		elif ev.index == aim_idx and state == "play" and aim_mode == "snap":
			thumb = ev.position
		elif ev.index == aim_idx and state == "play":
			# Beschleunigung: langsame Bewegung bleibt fein, schnelle trägt weiter
			var v = ev.velocity.length()
			var gain = aim_sens * (1.0 + aim_accel * clampf((v - 250.0) / 1300.0, 0.0, 1.6))
			var tg = _assist_nearest(aim, 2.2)
			if not tg.is_empty() and aim_assist > 0.0:
				# 1) über einem Gegner bremst das Fadenkreuz etwas ab
				if tg.d < tg.r * 1.25:
					gain *= 1.0 - 0.5 * aim_assist
			var mv: Vector2 = ev.relative * gain
			aim += mv
			if not tg.is_empty() and aim_assist > 0.0:
				# 2) nur während der Bewegung ein Hauch Zug Richtung Gegner
				var to: Vector2 = tg.sp - aim
				var pull = minf(mv.length() * 0.3 * aim_assist, to.length())
				if to.length() > 1.0:
					aim += to.normalized() * pull
			aim = aim.clamp(Vector2(20, 20), vs - Vector2(20, 20))
			thumb = ev.position


func _press(p: Vector2, idx: int = 0) -> void:
	match state:
		"title":
			if st_t < 0.6:
				return
			if _upd_btn_rect().has_point(p) and upd_url != "" and upd_build > _my_build():
				OS.shell_open(upd_url)
				return
			_close_book()
			_open_book(0.35)
			_start_game()
		"over":
			if st_t < 1.2:
				return
			if _upd_btn_rect().has_point(p) and upd_url != "" and upd_build > _my_build():
				OS.shell_open(upd_url)
				return
			_close_book()
			_open_book(0.45)
			_start_game()
		"play":
			if _ui_press(p, idx):
				return
			if p.distance_to(_nade_center()) < 58:
				_throw_grenade()
			elif p.distance_to(_fire_center()) < 105:
				fire_idx = idx
				auto_t = 0.09
				if not cover:
					_shoot(aim)
			elif aim_idx < 0:
				# Daumen drauf: aufstehen, ziehen bewegt das Fadenkreuz
				aim_idx = idx
				thumb = p
				thumb0 = p
				cover = false


func _shoot(p: Vector2) -> void:
	var w = weapon
	if w == "pistol":
		if ammo <= 0:
			_sfx("empty", -2.0, 0.02)
			return
		ammo -= 1
	else:
		wpn_ammo -= 1
		if wpn_ammo <= 0:
			weapon = "pistol"
			wpn_ammo = 0
	shots_fired += 1
	kick = 1.0 if w != "smg" else 0.45
	shake = maxf(shake, 0.25 if w == "pistol" else (0.18 if w == "smg" else 0.55))
	match w:
		"shotgun":
			_sfx("shot_player", 3.0, 0.05)
			_sfx("shot_enemy", 0.0, 0.05)
		"smg":
			_sfx("shot_player", -5.0, 0.12)
		"rocket":
			_sfx("throw", 2.0, 0.05)
			_sfx("shot_enemy", -2.0, 0.05)
		_:
			_sfx("shot_player", -1.0, 0.06)
	# anfliegende Gegner-Granate abschießen?
	for pr in projs:
		if pr.kind == "enade" and is_instance_valid(pr.n):
			var gp: Vector3 = pr.n.global_position
			if not cam.is_position_behind(gp) and cam.unproject_position(gp).distance_to(p) < 60.0:
				_proj_remove(pr)
				_explode(gp, 1.6, false)
				score += 200
				_float_text(gp + Vector3(0, 0.3, 0), "NICE SHOT  +200", true)
				return
	if w == "rocket":
		var tp = _car_magnet(p, _aim_point(p))
		var from: Vector3 = cam.global_transform * Vector3(0.35, -0.3, -0.6)
		_launch(from, tp, maxf(0.12, from.distance_to(tp) / 38.0), 0.0, "rocket")
		return
	if w == "shotgun":
		# Schrotflinte: alle Gegner nahe am Fadenkreuz, plus Streuschüsse in die Umgebung
		for e in enemies.duplicate():
			if e.state == "fall" or e.state == "hide":
				continue
			var tg = _assist_nearest(p, 3.4)
			if tg.is_empty():
				break
			_kill_enemy(tg.e, tg.e.mi.global_transform * tg.lp, false)
		for i in 5:
			var sp = p + Vector2(randf_range(-55, 55), randf_range(-40, 40))
			var sh = _pick(sp, (cards).filter(func(x): return x != wall))
			if not sh.is_empty():
				_impact(sh, true)
	# Mündungslicht der eigenen Waffe (rechts unten) erhellt kurz die Mauer
	_flash_light(cam.global_transform * Vector3(0.35, -0.3, -0.6), 3.5, Color(1.0, 0.72, 0.4), 3.0)
	var targets = (cards + enemies).filter(func(x): return x != wall)
	var hit = _pick(p, targets)
	# 3) knapp neben der Figur zählt noch als Treffer
	var hit_enemy = not hit.is_empty() and hit.card.kind == "card" and enemies.has(hit.card) and hit.card.state != "fall"
	if not hit_enemy and aim_assist > 0.0:
		var tg = _assist_nearest(p, 1.2 + 1.5 * aim_assist)
		if not tg.is_empty():
			var e = tg.e
			hit = {"card": e, "point": e.mi.global_transform * tg.lp, "uv": Vector2(0.5, 1.0 - tg.lp.y / e.h), "local": tg.lp, "normal": e.mi.global_transform.basis.z.normalized()}
	if hit.is_empty():
		return
	var c = hit.card
	if enemies.has(c) and c.state != "fall" and c.state != "hide" and (c.kind == "card" or c.kind == "box"):
		_impact(hit, false)
		_kill_enemy(c, hit.point, hit.uv.y < 0.17 and not c.get("box", false))
	else:
		_impact(hit, true)
		# Schuss aufs Auto mit der Schrotflinte o. Ä. lässt es nicht explodieren – dafür braucht es Granate oder Rakete


# Weltpunkt unter dem Fadenkreuz (Kulisse, sonst Boden)
func _aim_point(p: Vector2) -> Vector3:
	var hit = _pick(p, (cards + enemies).filter(func(x): return x != wall and x.kind != "room"))
	if not hit.is_empty():
		return hit.point
	var o = cam.project_ray_origin(p)
	var d = cam.project_ray_normal(p)
	if d.y < -0.01:
		return o + d * (-o.y / d.y)
	return o + d * 14.0


# Granate/Rakete in der Nähe des Autos: geht aufs Auto (sonst fliegt sie oft übers Dach an die Hauswand)
func _car_magnet(p: Vector2, tp: Vector3) -> Vector3:
	if car_dead or car_card.is_empty():
		return tp
	var cc: Vector3 = car_card.pv.global_position + Vector3(0, 0.6, 0.15)
	if cam.is_position_behind(cc):
		return tp
	var sp = cam.unproject_position(cc)
	var near_screen = sp.distance_to(p) < 150.0
	var near_world = Vector2(tp.x - cc.x, tp.z - cc.z).length() < 3.5
	if near_screen or near_world:
		return cc
	return tp


func _throw_grenade() -> void:
	if grenades <= 0 or state != "play":
		_sfx("empty", -4.0, 0.0)
		return
	grenades -= 1
	var tp = _car_magnet(aim, _aim_point(aim))
	var from: Vector3 = cam.global_transform * Vector3(0.3, -0.35, -0.4)
	var dist = from.distance_to(tp)
	_launch(from, tp, 0.55 + dist * 0.03, 1.5 + dist * 0.12, "nade")
	_sfx("throw", 0.0, 0.08)


func _enemy_grenade(e: Dictionary) -> void:
	var from: Vector3 = e.mi.global_transform * Vector3(0, e.h * 0.8, 0.1)
	var tp = Vector3(cam.global_position.x + randf_range(-0.3, 0.3), 0.35, -0.55)
	_launch(from, tp, 1.9, 4.2, "enade")
	_bark(e, "fire", 1.0, 0.0, true)
	_sfx("throw", -2.0, 0.08)
	_sfx("warn", 0.0, 0.0)
	_show_msg("GRENADE!", "pop up and shoot it", 1.4)


func _launch(from: Vector3, to: Vector3, dur: float, apex: float, kind: String) -> void:
	var sp = Sprite3D.new()
	if kind == "rocket":
		sp.texture = tex_flash
		sp.pixel_size = 0.5 / 128.0
		sp.modulate = Color(2.5, 1.6, 0.8)
	else:
		sp.texture = tex_nade
		sp.pixel_size = 0.16 / 256.0
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.render_priority = 5
	add_child(sp)
	sp.global_position = from
	projs.append({"n": sp, "from": from, "to": to, "t": 0.0, "dur": dur, "apex": apex, "kind": kind, "trail": 0.0})


func _proj_remove(pr: Dictionary) -> void:
	if is_instance_valid(pr.n):
		pr.n.queue_free()
	projs.erase(pr)


func _proj_update(dt: float) -> void:
	for pr in projs.duplicate():
		if not is_instance_valid(pr.n):
			projs.erase(pr)
			continue
		if _frozen():
			continue
		pr.t += dt
		var u = clampf(pr.t / pr.dur, 0, 1)
		var pos: Vector3 = pr.from.lerp(pr.to, u) + Vector3(0, 4.0 * pr.apex * u * (1.0 - u), 0)
		pr.n.global_position = pos
		pr.n.rotation.z += dt * (14.0 if pr.kind != "rocket" else 0.0)
		pr.trail -= dt
		if pr.kind == "rocket" and pr.trail <= 0.0:
			pr.trail = 0.03
			_smoke(pos, 1)
		if u >= 1.0:
			var kind = pr.kind
			_proj_remove(pr)
			if kind == "enade":
				_explode(pos, 1.5, true)
			else:
				_explode(pos, 3.0 if kind == "nade" else 2.6, false)


# Explosion: Feuerball, Rauch, Funken, Licht; erledigt alles im Umkreis
func _explode(pos: Vector3, radius: float, hurts_player: bool) -> void:
	var dcam = pos.distance_to(cam.global_position)
	var k = clampf(radius / 3.0, 0.5, 1.4) * (0.45 if dcam < 3.0 else 1.0)
	_fb_boom(pos, k)
	fx_k = clampf(dcam / 7.0, 0.22, 1.3)
	_sparks(pos, Vector3.UP, 30)
	_chunks(pos, Vector3.UP, 18, [Color(0.35, 0.3, 0.26), Color(0.6, 0.45, 0.3), Color(0.2, 0.18, 0.16)], 0.06, 1.0)
	var l = OmniLight3D.new()
	l.position = pos + Vector3(0, 0.8, 0.5)
	l.omni_range = 9.0
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 9.0
	add_child(l)
	var tw = create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.55)
	tw.tween_callback(l.queue_free)
	_sfx("boom", 2.0 if dcam > 4.0 else 4.0, 0.1)
	shake = maxf(shake, clampf(1.5 - dcam / 14.0, 0.35, 1.3))
	if hurts_player:
		health -= 35.0
		hurt = 1.0
		_sfx("player_hit", 0.0, 0.04)
		if not autotest:
			Input.vibrate_handheld(200)
		return
	for e in enemies.duplicate():
		if e.state == "fall" or e.state == "hide" or not is_instance_valid(e.mi):
			continue
		var ep: Vector3 = e.mi.global_transform * Vector3(0, e.h * 0.5, 0)
		var d = Vector2(ep.x - pos.x, ep.z - pos.z).length()
		if d < radius and absf(ep.y - pos.y) < radius + 1.0:
			_kill_enemy(e, ep, false)
	if not car_dead and not car_card.is_empty():
		var cp: Vector3 = car_card.pv.global_position + Vector3(0, 0.7, 0)
		if cp.distance_to(pos) < radius + 0.9:
			get_tree().create_timer(0.15).timeout.connect(_car_explode)


func _car_explode() -> void:
	if car_dead:
		return
	car_dead = true
	car_card.dead = true
	for s in slots:
		if s.name == "car":
			s.off = true
	var cp: Vector3 = car_card.pv.global_position + Vector3(0, 0.6, 0.3)
	_explode(cp, 3.2, false)
	_fb_boom(cp + Vector3(0, 0.6, 0), 1.6)
	score += 300
	_float_text(cp + Vector3(0, 1.4, 0), "CAR  +300", true)
	# Pappauto fliegt hoch, dreht sich und klatscht verkohlt hinten auf
	car_card.mat.set_shader_parameter("dim", 0.32)
	var pv: Node3D = car_card.pv
	var base: Vector3 = car_card.base
	var tw = create_tween()
	tw.tween_property(pv, "position", base + Vector3(0.3, 2.4, -0.6), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(pv, "rotation", Vector3(-1.1, 0.25, 0.5), 0.45)
	tw.tween_property(pv, "position", base + Vector3(0.5, 0.0, -0.9), 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(pv, "rotation", Vector3(-PI * 0.5, 0.3, 0.12), 0.4)
	tw.tween_callback(func(): _sfx("target_down", 2.0, 0.0))
	# Feuer und Rauch bleiben
	var fire = CPUParticles3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = fx_mat_spark
	fire.mesh = q
	fire.amount = 40
	fire.lifetime = 0.8
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire.emission_box_extents = Vector3(0.9, 0.1, 0.4)
	fire.direction = Vector3.UP
	fire.spread = 15.0
	fire.gravity = Vector3(0, 1.5, 0)
	fire.initial_velocity_min = 0.5
	fire.initial_velocity_max = 1.4
	var fg = Gradient.new()
	fg.set_color(0, Color(2.6, 1.5, 0.4, 0.0))
	fg.add_point(0.15, Color(2.6, 1.3, 0.35, 0.9))
	fg.set_color(fg.get_point_count() - 1, Color(0.8, 0.15, 0.02, 0.0))
	fire.color_ramp = fg
	var fsc = Curve.new()
	fsc.add_point(Vector2(0, 1.0))
	fsc.add_point(Vector2(1, 0.3))
	fire.scale_amount_curve = fsc
	add_child(fire)
	fire.global_position = base + Vector3(0.5, 0.15, -0.6)
	car_fx.append(fire)
	var smoke = CPUParticles3D.new()
	var q2 = QuadMesh.new()
	q2.size = Vector2(0.9, 0.9)
	q2.material = fx_mat_dust
	smoke.mesh = q2
	smoke.amount = 26
	smoke.lifetime = 4.5
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(0.7, 0.1, 0.3)
	smoke.direction = Vector3(0.25, 1, 0)
	smoke.spread = 12.0
	smoke.gravity = Vector3(0.15, 0.35, 0)
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.9
	var ssc = Curve.new()
	ssc.add_point(Vector2(0, 0.5))
	ssc.add_point(Vector2(1, 2.6))
	smoke.scale_amount_curve = ssc
	var sg = Gradient.new()
	sg.set_color(0, Color(0.12, 0.1, 0.09, 0.0))
	sg.add_point(0.15, Color(0.14, 0.12, 0.1, 0.6))
	sg.set_color(sg.get_point_count() - 1, Color(0.35, 0.3, 0.28, 0.0))
	smoke.color_ramp = sg
	add_child(smoke)
	smoke.global_position = base + Vector3(0.5, 0.6, -0.7)
	car_fx.append(smoke)
	var fl = OmniLight3D.new()
	fl.light_color = Color(1.0, 0.55, 0.2)
	fl.omni_range = 4.0
	fl.light_energy = 1.6
	add_child(fl)
	fl.global_position = base + Vector3(0.5, 0.8, 0.2)
	car_fx.append(fl)


func _car_reset() -> void:
	for n in car_fx:
		if is_instance_valid(n):
			n.queue_free()
	car_fx.clear()
	for s in slots:
		s.off = false
	if car_card.is_empty():
		return
	car_dead = false
	car_card.dead = false
	car_card.pv.position = car_card.base
	car_card.pv.rotation = Vector3.ZERO
	car_card.mat.set_shader_parameter("dim", 1.0)


# ---------------- Explosions-Bildfolgen (aus AntiGrav, Unity Labs CC0)
const FB_SH = """
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float grid=5.;
uniform vec3 smk=vec3(1.);
instance uniform float fr=0.;
instance uniform float al=1.;
instance uniform float rot=0.;
instance uniform float flip=1.;
instance uniform float em=1.3;
void vertex(){
	mat4 mv=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
	float sx=length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX=mv*mat4(vec4(sx,0.,0.,0.),vec4(0.,sx,0.,0.),vec4(0.,0.,sx,0.),vec4(0.,0.,0.,1.));
}
vec4 cel(float f,vec2 uv){
	float n=grid*grid;
	f=clamp(f,0.,n-1.);
	vec2 c=vec2(mod(f,grid),floor(f/grid));
	return texture(tex,(c+clamp(uv,vec2(.004),vec2(.996)))/grid);
}
void fragment(){
	vec2 uv=UV-.5;
	uv.x*=flip;
	float cs=cos(rot),sn=sin(rot);
	uv=vec2(cs*uv.x-sn*uv.y,sn*uv.x+cs*uv.y)+.5;
	float m=step(0.,uv.x)*step(uv.x,1.)*step(0.,uv.y)*step(uv.y,1.);
	float f0=floor(fr);
	vec4 c=mix(cel(f0,uv),cel(f0+1.,uv),fr-f0);
	float lum=max(c.r,max(c.g,c.b));
	ALBEDO=c.rgb*smk*(1.+em*smoothstep(.55,1.,lum));
	ALPHA=c.a*al*m;
}
"""


func _fb_mat(key: String) -> ShaderMaterial:
	if fb_mats.has(key):
		return fb_mats[key]
	if fb_sh == null:
		fb_sh = Shader.new()
		fb_sh.code = FB_SH
	var m = ShaderMaterial.new()
	m.shader = fb_sh
	m.set_shader_parameter("tex", load("res://fx/%s.png" % key))
	m.set_shader_parameter("grid", 8.0 if key == "wisp8" else 5.0)
	m.set_shader_parameter("smk", Vector3(0.85, 0.78, 0.72) if key in ["wisp8", "smoke5"] else Vector3(1, 1, 1))
	fb_mats[key] = m
	return m


func _fb_quad(key: String, pos: Vector3, size: float) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	mi.material_override = _fb_mat(key)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size
	mi.set_instance_shader_parameter("rot", randf() * TAU)
	mi.set_instance_shader_parameter("flip", -1.0 if randf() < 0.5 else 1.0)
	mi.set_instance_shader_parameter("fr", 0.0)
	mi.visible = false
	return mi


func _fb_boom(pos: Vector3, k: float) -> void:
	var keys = ["boom0", "boom1", "boom2"]
	keys.shuffle()
	for i in 2:
		var off = Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.4), randf_range(-0.2, 0.2)) * k * (0.0 if i == 0 else 1.0)
		var sz = k * (3.2 if i == 0 else randf_range(2.0, 2.7))
		var mi = _fb_quad(keys[i], pos + off + Vector3(0, sz * 0.2, 0.2), sz)
		mi.set_instance_shader_parameter("em", 1.3)
		fbs.append({"n": mi, "t": -0.05 * i, "dur": randf_range(1.4, 1.9), "g": randf_range(0.25, 0.55) * k})
	var sm = _fb_quad("smoke5", pos + Vector3(0, k * 0.5, 0.1), k * 3.8)
	sm.set_instance_shader_parameter("em", 0.0)
	fbs.append({"n": sm, "t": -0.12, "dur": 3.0, "g": 0.35 * k})


func _fb_update(dt: float) -> void:
	for i in range(fbs.size() - 1, -1, -1):
		var e: Dictionary = fbs[i]
		if not is_instance_valid(e.n):
			fbs.remove_at(i)
			continue
		e.t += dt
		var u = e.t / float(e.dur)
		if u >= 1.0:
			e.n.queue_free()
			fbs.remove_at(i)
			continue
		var mi: MeshInstance3D = e.n
		mi.visible = e.t >= 0.0
		var uu = clampf(u, 0.0, 1.0)
		mi.set_instance_shader_parameter("fr", uu * 23.999)
		mi.set_instance_shader_parameter("al", clampf((1.0 - uu) * 3.0, 0.0, 1.0))
		mi.global_position += Vector3(0, float(e.g) * dt, 0)


# Snap-Modus: Daumenweg vom Aufsetzpunkt zeigt in eine Richtung, das Fadenkreuz nimmt die feste Zone,
# die dort am nächsten liegt. Steht in einer Zone gerade ein Gegner, zielt es auf ihn.
func _snap_target() -> Vector2:
	var vs = _vs()
	var center = vs * Vector2(0.5, 0.45)
	var v = center + (thumb - thumb0) * (2.8 * aim_sens / 1.7)
	var best_p = center
	var bd = 1e9
	for sl in slots:
		var wp: Vector3 = sl.pos + Vector3(0, ENEMY_H * 0.73, 0)
		var live = false
		for e in enemies:
			if e.slot == sl and e.state != "fall" and e.state != "hide" and is_instance_valid(e.mi):
				wp = e.mi.global_transform * Vector3(0, (1.0 - e.gun_v - 0.04) * e.h, 0)
				live = e.state == "aim" or (e.state == "appear" and e.t > 0.2)
		if cam.is_position_behind(wp):
			continue
		var sp = cam.unproject_position(wp)
		var d = v.distance_to(sp) * (0.75 if live else 1.0)
		if d < bd:
			bd = d
			best_p = sp
	return best_p


# Zielhilfe: nächster sichtbarer Gegner um einen Bildschirmpunkt (Brustbereich, Radius in Bildpunkten)
func _assist_nearest(p: Vector2, reach: float) -> Dictionary:
	var best_t = {}
	var bd = 1e9
	for e in enemies:
		if e.state == "fall" or e.state == "hide" or not is_instance_valid(e.mi):
			continue
		if e.state == "appear" and e.t < 0.3:
			continue
		var lp = Vector3(0.0, (1.0 - e.gun_v - 0.04) * e.h, 0.0)
		var wp: Vector3 = e.mi.global_transform * lp
		if cam.is_position_behind(wp):
			continue
		var sp = cam.unproject_position(wp)
		var top = cam.unproject_position(e.mi.global_transform * (lp + Vector3(0, e.h * 0.17, 0)))
		var r = maxf(14.0, sp.distance_to(top))
		var d = p.distance_to(sp)
		if d < r * reach and d < bd:
			bd = d
			best_t = {"e": e, "sp": sp, "r": r, "d": d, "lp": lp}
	return best_t


# Strahl vom Bildschirmpunkt in die Szene: vorderste undurchsichtige Pappe
func _pick(sp: Vector2, only) -> Dictionary:
	var o = cam.project_ray_origin(sp)
	var d = cam.project_ray_normal(sp)
	var best_hit = {}
	var bt = 1e9
	var list = only if only != null else (cards + enemies)
	for c in list:
		if c.kind == "sky" or not is_instance_valid(c.mi):
			continue
		var tf: Transform3D = c.mi.global_transform
		var inv = tf.affine_inverse()
		var lo = inv * o
		var ld = inv.basis * d
		if absf(ld.z) < 1e-5:
			continue
		var t = -lo.z / ld.z
		if t <= 0.05 or t >= bt:
			continue
		var lp = lo + ld * t
		var u = lp.x / c.w + 0.5
		var v = 1.0 - lp.y / c.h
		if u < 0 or u > 1 or v < 0 or v > 1:
			continue
		if c.img != null:
			var img: Image = c.img
			var px = clampi(int(u * img.get_width()), 0, img.get_width() - 1)
			var py = clampi(int(v * img.get_height()), 0, img.get_height() - 1)
			if img.get_pixel(px, py).a < 0.5:
				continue
		bt = t
		best_hit = {"card": c, "point": o + d * t, "uv": Vector2(u, v), "local": lp, "normal": tf.basis.z.normalized()}
	return best_hit


# ================================================================ Effekte
func _impact(hit: Dictionary, hole: bool) -> void:
	var c = hit.card
	var p: Vector3 = hit.point
	var n: Vector3 = hit.normal
	if n.dot(cam.global_position - p) < 0:
		n = -n
	var kind: String = c.kind
	var out = p + n * 0.02
	# Effekte nah an der Kamera (Mauer) kleiner, sonst füllt ein Staubwölkchen den halben Bildschirm
	fx_k = clampf(p.distance_to(cam.global_position) / 7.0, 0.22, 1.3)
	match kind:
		"brick":
			_sparks(out, n, 9)
			_dust(out, n, 7, Color(0.78, 0.64, 0.5), 0.35)
			_chunks(out, n, 9, [Color(0.6, 0.33, 0.22), Color(0.82, 0.74, 0.62), Color(0.45, 0.3, 0.22)], 0.035)
			_sfx("impact_brick", -3.0, 0.15)
		"metal":
			_sparks(out, n, 22)
			_dust(out, n, 2, Color(0.5, 0.45, 0.4), 0.2)
			_sfx("impact_metal", -4.0, 0.15)
		"wood":
			_chunks(out, n, 11, [Color(0.55, 0.38, 0.22), Color(0.72, 0.55, 0.35)], 0.04)
			_dust(out, n, 4, Color(0.62, 0.5, 0.36), 0.25)
			_sfx("impact_card", -2.0, 0.2)
		"leaf":
			_chunks(out, n, 12, [Color(0.35, 0.42, 0.15), Color(0.55, 0.55, 0.2), Color(0.42, 0.33, 0.12)], 0.05, 0.25)
			_sfx("impact_card", -10.0, 0.3)
		"card":
			_chunks(out, n, 10, [Color(0.78, 0.66, 0.5), Color(0.6, 0.48, 0.34)], 0.04)
			_dust(out, n, 3, Color(0.7, 0.6, 0.48), 0.2)
			_sfx("impact_card", 0.0, 0.1)
		"ground":
			_dust(out, Vector3.UP, 8, Color(0.6, 0.48, 0.36), 0.35)
			_chunks(out, Vector3.UP, 6, [Color(0.4, 0.34, 0.28)], 0.03)
			_sfx("impact_brick", -10.0, 0.25)
		_:
			_dust(out, n, 5, Color(0.3, 0.24, 0.2), 0.3)
	if hole and kind in ["brick", "metal", "wood", "card"]:
		_bullet_hole(c, hit.local, kind)


func _bullet_hole(c: Dictionary, lp: Vector3, kind: String) -> void:
	var s = Sprite3D.new()
	s.texture = tex_hole
	var size = 0.12 if kind != "metal" else 0.07
	if c == wall:
		size = 0.05
	s.pixel_size = size / 64.0
	s.position = Vector3(lp.x, lp.y, 0.01)
	s.rotation.z = randf() * TAU
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.double_sided = false
	s.modulate = Color(1, 1, 1, 0.9)
	if kind == "metal":
		s.modulate = Color(0.6, 0.6, 0.65, 0.9)
	c.mi.add_child(s)
	holes_live.append(s)
	if holes_live.size() > 60:
		var old = holes_live.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _particles(pos: Vector3, mat: Material, size: float, amount: int, life: float) -> CPUParticles3D:
	var p = CPUParticles3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	p.mesh = q
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)
	return p


func _sparks(pos: Vector3, n: Vector3, amount: int) -> void:
	var p = _particles(pos, fx_mat_spark, 0.035 * fx_k, amount, 0.45)
	p.direction = (n + Vector3(0, 0.6, 0)).normalized()
	p.spread = 55.0
	p.initial_velocity_min = 2.5 * fx_k
	p.initial_velocity_max = 6.5 * fx_k
	p.gravity = Vector3(0, -9.8, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var g = Gradient.new()
	g.set_color(0, Color(2.6, 2.0, 1.1, 1.0))
	g.add_point(0.4, Color(1.8, 0.9, 0.3, 1.0))
	g.set_color(g.get_point_count() - 1, Color(1.0, 0.3, 0.05, 0.0))
	p.color_ramp = g
	_flash_light(pos + n * 0.6, 1.6, Color(1.0, 0.75, 0.4), 0.5)


func _dust(pos: Vector3, n: Vector3, amount: int, col: Color, size: float) -> void:
	var p = _particles(pos, fx_mat_dust, size * fx_k, amount, 1.1)
	p.direction = (n + Vector3(0, 0.4, 0)).normalized()
	p.spread = 45.0
	p.initial_velocity_min = 0.4 * fx_k
	p.initial_velocity_max = 1.4 * fx_k
	p.damping_min = 2.0
	p.damping_max = 3.5
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	var sc = Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.8))
	p.scale_amount_curve = sc
	var g = Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.6))
	g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g


func _smoke(pos: Vector3, amount: int) -> void:
	var p = _particles(pos, fx_mat_dust, 0.18, amount, 1.0)
	p.direction = Vector3(0, 0.6, 1).normalized()
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.gravity = Vector3(0, 0.3, 0)
	var sc = Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.0))
	p.scale_amount_curve = sc
	var g = Gradient.new()
	g.set_color(0, Color(0.75, 0.7, 0.65, 0.45))
	g.set_color(g.get_point_count() - 1, Color(0.75, 0.7, 0.65, 0.0))
	p.color_ramp = g


func _chunks(pos: Vector3, n: Vector3, amount: int, cols: Array, size: float, grav: float = 1.0) -> void:
	var p = _particles(pos, fx_mat_chunk, size * fx_k, amount, 0.9)
	p.direction = (n + Vector3(0, 0.8, 0)).normalized()
	p.spread = 60.0
	p.initial_velocity_min = 1.2 * fx_k
	p.initial_velocity_max = 3.8 * fx_k
	p.gravity = Vector3(0, -9.8 * grav * fx_k, 0)
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	var g = Gradient.new()
	g.set_color(0, cols[0])
	if cols.size() > 1:
		g.set_color(1, cols[1])
	if cols.size() > 2:
		g.add_point(0.5, cols[2])
	p.color_initial_ramp = g


func _flash(pos: Vector3, size: float, col: Color, energy: float) -> void:
	var s = Sprite3D.new()
	s.texture = tex_flash
	s.pixel_size = size / 128.0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.modulate = Color(2.4, 1.9, 1.3)
	s.rotation.z = randf() * TAU
	s.position = pos
	s.render_priority = 10
	add_child(s)
	get_tree().create_timer(0.06).timeout.connect(s.queue_free)
	_flash_light(pos, 6.0, col, energy)


func _flash_light(pos: Vector3, rng: float, col: Color, energy: float) -> void:
	var l = OmniLight3D.new()
	l.position = pos
	l.omni_range = rng
	l.light_color = col
	l.light_energy = energy
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	add_child(l)
	var tw = create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.09)
	tw.tween_callback(l.queue_free)


func _float_text(pos: Vector3, s: String, big: bool) -> void:
	var l = Label3D.new()
	l.text = s
	l.font = font
	l.font_size = 64 if big else 54
	l.pixel_size = 0.0045 if not big else 0.0052
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.55)
	l.modulate = Color(1.0, 0.9, 0.55) if big else Color(1, 1, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.position = pos
	add_child(l)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(l, "position", pos + Vector3(0, 0.9, 0), 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


# ================================================================ Speichern
func _load_save() -> void:
	var c = ConfigFile.new()
	if c.load(SAVE_PATH) == OK:
		best = int(c.get_value("game", "best", 0))
		aim_sens = float(c.get_value("ctrl", "aim_sens", aim_sens))
		aim_accel = float(c.get_value("ctrl", "aim_accel", aim_accel))
		recenter = float(c.get_value("ctrl", "recenter", recenter))
		aim_assist = float(c.get_value("ctrl", "aim_assist", aim_assist))
		aim_mode = str(c.get_value("ctrl", "aim_mode", aim_mode))
		thumb_n = c.get_value("ctrl", "thumb_n", thumb_n)
		fire_n = c.get_value("ctrl", "fire_n", fire_n)


func _save() -> void:
	if autotest:
		return
	var c = ConfigFile.new()
	c.set_value("game", "best", best)
	c.set_value("ctrl", "aim_sens", aim_sens)
	c.set_value("ctrl", "aim_accel", aim_accel)
	c.set_value("ctrl", "recenter", recenter)
	c.set_value("ctrl", "aim_assist", aim_assist)
	c.set_value("ctrl", "aim_mode", aim_mode)
	c.set_value("ctrl", "thumb_n", thumb_n)
	c.set_value("ctrl", "fire_n", fire_n)
	c.save(SAVE_PATH)


# ================================================================ Update: neueste Version auf GitHub
func _my_build() -> int:
	if OS.get_environment("MYBUILD") != "":
		return int(OS.get_environment("MYBUILD"))
	var v = str(ProjectSettings.get_setting("application/config/version", "1.0"))
	return int(v.get_slice(".", 1)) if v.contains(".") else 0


func _upd_check() -> void:
	if upd_done or autotest:
		return
	upd_done = true
	var h = HTTPRequest.new()
	h.timeout = 12.0
	add_child(h)
	h.request_completed.connect(func(res, code, _hd, body):
		h.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var d = JSON.parse_string(body.get_string_from_utf8())
		if not (d is Dictionary):
			return
		var n = int(str(d.get("tag_name", "")).trim_prefix("build-"))
		for a in d.get("assets", []):
			var u = str(a.get("browser_download_url", ""))
			if u.ends_with(".apk"):
				upd_url = u
		upd_build = n)
	if h.request(UPD_API, ["User-Agent: Shooter", "Accept: application/vnd.github+json"]) != OK:
		h.queue_free()


# ================================================================ Test am Rechner (AUTOTEST=1, Bilder nach SHOT_DIR)
func _snap(name: String) -> void:
	var dir = OS.get_environment("SHOT_DIR")
	if dir == "":
		return
	var img = get_viewport().get_texture().get_image()
	img.save_png(dir + "/" + name + ".png")
	print("SNAP ", name)


func _force_enemy(slot_name: String) -> Dictionary:
	for s in slots:
		if s.name == slot_name:
			for o in slots:
				o.busy = true
			s.busy = false
			_spawn()
			for o in slots:
				o.busy = false
			for e in enemies:
				e.slot.busy = true
			return enemies[-1]
	return {}


func _autotest(dt: float) -> void:
	at_t += dt
	var plan = OS.get_environment("AUTOTEST")
	if at_step == 0 and at_t > 1.0:
		_snap("01_title_opening")
		at_step = 1
	elif at_step == 1 and at_t > 3.0:
		_snap("02_title")
		_press(_vs() * 0.5)
		at_step = 2
	elif at_step == 2 and at_t > 4.0:
		_snap("03_intro")
		at_step = 3
	elif at_step == 3 and at_t > 5.3:
		spawn_t = 999.0
		tip_t = 0.0
		cover = false
		aim_idx = 99
		thumb = _thumb_home() + Vector2(30, -20)
		for n in ["window0", "door", "car", "crates", "tree", "window4"]:
			var e = _force_enemy(n)
			e.aim = 99.0
		at_step = 4
	elif at_step == 4 and at_t > 6.4:
		aim = _vs() * Vector2(0.55, 0.45)
		_snap("04_enemies")
		# Snap-Test: Daumen nach links oben ziehen
		aim_mode = "snap"
		thumb0 = _thumb_home()
		thumb = thumb0 + Vector2(-140, -110)
		at_step = 5
	elif at_step == 5 and at_t > 6.6:
		_snap("04s_snap_upleft")
		print("SNAP aim ", aim, " target ", _snap_target())
		# auf den Gegner an der Tür schießen
		for e in enemies:
			if e.slot.name == "door":
				# Ziehen mit Zielhilfe prüfen, dann knapp daneben schießen
				var dv = InputEventScreenDrag.new()
				dv.index = 99
				dv.relative = Vector2(6, 0)
				dv.velocity = Vector2(400, 0)
				_input(dv)
				var tg = _assist_nearest(Vector2.ZERO, 1e9)
				aim = cam.unproject_position(e.mi.global_transform * Vector3(0, e.h * (1.0 - e.gun_v), 0)) + Vector2(28, 0)
				var before = kills
				_shoot(aim)
				print("ASSIST test kills ", before, " -> ", kills)
				var t2 = _assist_nearest(aim, 1e9)
				print("ASSIST r=", t2.get("r"), " d=", t2.get("d"))
		at_step = 6
	elif at_step == 6 and at_t > 6.68:
		_snap("05_shot_hit")
		# Mauer und Fassade treffen
		aim = _vs() * Vector2(0.26, 0.6)
		_shoot(aim)
		aim = _vs() * Vector2(0.62, 0.3)
		_shoot(aim)
		at_step = 7
	elif at_step == 7 and at_t > 6.75:
		_snap("06_impacts")
		at_step = 8
	elif at_step == 8 and at_t > 7.3:
		for e in enemies:
			if e.slot.name == "car":
				e.aim = 0.0
		at_step = 9
	elif at_step == 9 and at_t > 7.36:
		_snap("07_enemy_fire")
		cover = true
		aim_idx = -1
		at_step = 10
	elif at_step == 10 and at_t > 8.0:
		_wall_hit()
		at_step = 11
	elif at_step == 11 and at_t > 8.06:
		_snap("08_cover_impact")
		at_step = 12
	elif at_step == 12 and at_t > 9.0:
		panel_open = true
		at_step = 120
	elif at_step == 120 and at_t > 9.5:
		_snap("08b_panel")
		panel_open = false
		editing = true
		at_step = 121
	elif at_step == 121 and at_t > 9.8:
		_snap("08c_edit")
		editing = false
		cover = false
		aim_idx = 99
		health = 100
		for e in enemies:
			if not e.get("box", false) and e.state != "fall":
				e.aim = 99.0
		# Mega-Box im Fenster oben
		for sl in slots:
			if sl.name == "window2":
				sl.busy = true
				_spawn_box(sl, true)
		at_step = 130
	elif at_step == 130 and at_t > 10.5:
		_snap("10_megabox")
		var bx = enemies[-1]
		aim = cam.unproject_position(bx.mi.global_transform * Vector3(0, bx.h * 0.5, 0))
		_shoot(aim)
		print("BOX weapon=", weapon, " grenades=", grenades, " health=", health)
		at_step = 131
	elif at_step == 131 and at_t > 10.65:
		_snap("11_box_open")
		grenades = max(grenades, 1)
		aim = cam.unproject_position(car_card.pv.global_position + Vector3(0.25, 1.75, -0.35))
		_throw_grenade()
		at_step = 132
	elif at_step == 132 and at_t > 11.45:
		_snap("12_nade_flying")
		at_step = 133
	elif at_step == 133 and at_t > 11.85:
		_snap("13_car_boom")
		at_step = 134
	elif at_step == 134 and at_t > 13.2:
		_snap("14_car_burning")
		print("CAR dead=", car_dead, " score=", score)
		# Gegner-Granate
		var e = _force_enemy("door")
		e.aim = 99.0
		at_step = 135
	elif at_step == 135 and at_t > 14.0:
		_enemy_grenade(enemies[-1])
		at_step = 136
	elif at_step == 136 and at_t > 14.9:
		_snap("15_incoming")
		at_step = 137
	elif at_step == 137 and at_t > 16.2:
		_snap("16_nade_hit")
		print("after enemy nade health=", health)
		health = 0
		at_step = 13
	elif at_step == 13 and at_t > 18.6:
		_snap("09_game_over")
		get_tree().quit()
