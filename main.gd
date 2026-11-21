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
const AIM_SENS = 1.7
var holes_live = []
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
	slots.append({"pos": Vector3(6.35, 0.12, -8.0), "mode": "flip", "busy": false, "name": "hedge"})
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
	ambience = AudioStreamPlayer.new()
	ambience.stream = sounds.get("ambience")
	ambience.volume_db = -8.0
	add_child(ambience)
	ambience.finished.connect(func(): ambience.play())
	ambience.play()


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
	var vs = _vs()
	return Vector2(vs.x * 0.2, vs.y * 0.64)


func _fire_center() -> Vector2:
	var vs = _vs()
	return Vector2(vs.x - 150, vs.y - 215)


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
		var tc = thumb if aim_idx >= 0 else _thumb_home()
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
		if ammo == 0 and not cover and reload_t <= 0:
			var bl = 0.55 + 0.45 * sin(st_t * 10.0)
			_text(c, Vector2(0, vs.y * 0.66), "RELOAD  –  LET GO TO TAKE COVER", 30, Color(1, 0.85, 0.4, bl), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		if cover and reload_t > 0:
			_text(c, Vector2(0, vs.y * 0.62), "RELOADING", 24, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
		if tip_t > 0:
			var ta = clampf(tip_t, 0, 1)
			_text(c, Vector2(0, vs.y - 30), "Left thumb: hold to stand up and drag to aim  ·  let go to take cover and reload  ·  right: FIRE", 17, Color(1, 1, 1, 0.8 * ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
	# große Meldungen
	if msg_t > 0 and msg != "":
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
	kick = maxf(0.0, kick - dt * 6.0)
	shake = maxf(0.0, shake - dt * 3.0)
	hurt = maxf(0.0, hurt - dt * 1.6)
	hit_mark = maxf(0.0, hit_mark - dt * 3.0)
	vignette.modulate.a = hurt

	# Pop-up-Buch: Kulissen klappen auf oder zu
	for c in cards:
		if c.get("static", false) or c.kind == "sky" or c.kind == "room":
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
	# Gegner nachschicken
	var alive = 0
	for e in enemies:
		if e.state != "fall":
			alive += 1
	var max_alive = 1
	if kills >= 4:
		max_alive = 2
	if stage >= 3:
		max_alive = 3
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
		if not s.busy:
			free.append(s)
	if free.is_empty():
		return
	var s = free[randi() % free.size()]
	s.busy = true
	var ti = randi() % ENEMY_TEX.size()
	var tex: Texture2D = load("res://art/" + ENEMY_TEX[ti] + ".png")
	var w = ENEMY_H * tex.get_width() / float(tex.get_height())
	var c = _card(ENEMY_TEX[ti] + ".png", w, s.pos, "card", ENEMY_H)
	c.merge({"slot": s, "state": "appear", "t": 0.0, "aim": _diff_aim() * randf_range(0.85, 1.2), "shots": 1 + (1 if stage >= 2 and randf() < 0.35 else 0), "gun_v": GUN_V[ti], "mode": s.mode, "seen": 0.0, "side": -1.0 if randf() < 0.5 else 1.0}, true)
	_enemy_pose(c, 0.0)
	enemies.append(c)
	_sfx("target_up", -6.0, 0.12)


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
	var mp = _muzzle(e)
	_flash(mp + Vector3(0, 0, 0.15), 0.9, Color(1.0, 0.7, 0.35), 7.0)
	_smoke(mp, 4)
	_sfx("shot_enemy", -2.0, 0.1)
	var acc = minf(0.7, 0.38 + stage * 0.05)
	if not cover and cover_k < 0.5 and randf() < acc:
		health -= randf_range(9.0, 14.0)
		hurt = 0.85
		shake = 0.7
		_sfx("player_hit", 0.0)
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
		elif ev.index == aim_idx:
			# Daumen weg: zurück in Deckung (lädt automatisch nach)
			aim_idx = -1
			cover = true
	elif ev is InputEventScreenDrag:
		if ev.index == aim_idx and state == "play":
			var vs = _vs()
			aim = (aim + ev.relative * AIM_SENS).clamp(Vector2(20, 20), vs - Vector2(20, 20))
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
			if p.x < _vs().x * 0.5:
				# linker Daumen drauf: aufstehen, ziehen bewegt das Fadenkreuz
				aim_idx = idx
				thumb = p
				thumb0 = p
				cover = false
			elif not cover:
				_shoot(aim)


func _shoot(p: Vector2) -> void:
	if ammo <= 0:
		_sfx("empty", -2.0, 0.02)
		return
	ammo -= 1
	shots_fired += 1
	kick = 1.0
	shake = maxf(shake, 0.25)
	_sfx("shot_player", -1.0, 0.06)
	# Mündungslicht der eigenen Waffe (rechts unten) erhellt kurz die Mauer
	_flash_light(cam.global_transform * Vector3(0.35, -0.3, -0.6), 3.5, Color(1.0, 0.72, 0.4), 3.0)
	var targets = (cards + enemies).filter(func(x): return x != wall)
	var hit = _pick(p, targets)
	if hit.is_empty():
		return
	var c = hit.card
	if c.kind == "card" and enemies.has(c) and c.state != "fall":
		hits += 1
		var head = hit.uv.y < 0.17
		var pts = 100 + int(clampf(1.0 - c.seen / maxf(c.aim, 0.1), 0, 1) * 100.0)
		if head:
			pts += 50
		score += pts
		kills += 1
		hit_mark = 1.0
		c.state = "fall"
		c.t = 0.0
		_impact(hit, false)
		_float_text(hit.point + Vector3(0, 0.25, 0.1), ("HEADSHOT  +%d" if head else "+%d") % pts, head)
		if kills % KILLS_PER_STAGE == 0:
			stage += 1
			health = minf(100.0, health + 25.0)
			_show_msg("STAGE %d" % stage, "+25 HEALTH", 2.2)
	else:
		_impact(hit, true)


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


func _save() -> void:
	var c = ConfigFile.new()
	c.set_value("game", "best", best)
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
		for n in ["window0", "door", "car", "crates", "hedge", "window4"]:
			var e = _force_enemy(n)
			e.aim = 99.0
		at_step = 4
	elif at_step == 4 and at_t > 6.4:
		aim = _vs() * Vector2(0.55, 0.45)
		_snap("04_enemies")
		at_step = 5
	elif at_step == 5 and at_t > 6.6:
		# auf den Gegner an der Tür schießen
		for e in enemies:
			if e.slot.name == "door":
				aim = cam.unproject_position(e.mi.global_transform * Vector3(0, e.h * 0.55, 0))
				_shoot(aim)
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
		cover = false
		health = 0
		at_step = 13
	elif at_step == 13 and at_t > 11.5:
		_snap("09_game_over")
		get_tree().quit()
