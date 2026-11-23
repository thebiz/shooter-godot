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
const ENEMY_H_FRONT = 2.5     # vorne hinter Kisten, Auto, Gabelstapler: näher dran, wirkt größer als die im Haus
const ENEMY_H_BACK = 3.0      # hinten in Fenstern und Containern: etwa doppelt so groß, sonst erkennt man sie kaum
const MIN_VIS = 1.8          # so lange bleibt jeder Gegner mindestens sichtbar
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
const RELOAD_TIME = 0.6
const RELOAD_SKIP = 0.08     # Nachladesound etwas später starten, damit der Schlitten-Klick genau am Ende kommt
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
var music: AudioStreamPlayer
var reload_player: AudioStreamPlayer
var music_vol = 0.5
var music_k = 1.0           # 1 = Menü (laut), 0 = Spiel (leise)
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
var mode = "easy"            # easy / hard (Kampagne) oder endless
const MODES = ["easy", "hard", "endless"]
const MODE_NAMES = {"easy": "EASY", "hard": "HARD", "endless": "ENDLESS"}
const ROUNDS_PER_MAP = 4
const CAMPAIGN_ROUNDS = 12   # drei Maps à vier Runden: Straße, Hafen, Motel
const MAPS = ["street", "harbor", "motel"]
var hs = {"easy": [], "hard": [], "endless": []}   # Top 5 je Modus: {n, s, r}
var hs_new = -1              # Platz des gerade eingetragenen Spielers
var last_name = ""
var entering = false         # Namenseingabe läuft
var won = false
var swap_to = "harbor"
var name_edit: LineEdit
var name_ok: Button
var hide_said = false
var last_bark = {}
var kills = 0
var stage = 1               # Runde der Campaign
var reserve = 0             # Munition außerhalb des Magazins (pro Runde knapp bemessen)
var round_kills = 0
var round_goal = 10
var out_t = -1.0            # läuft, wenn die Munition ganz leer ist
var over_reason = ""
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
	{"label": "AIM ASSIST", "key": "aim_assist", "min": 0.0, "max": 1.0},
	{"label": "MUSIC", "key": "music_vol", "min": 0.0, "max": 1.0}]
var panel_open = false
var panel_k = 0.0
var editing = false
var ui_idx = -1             # Finger, der gerade einen Regler oder Knopf zieht
var ui_drag = ""            # "slider0".., "thumb", "fire"
var holes_live = []
# Boxen, Waffen, Granaten, Auto
var car_card = {}
var scene = "street"        # street (Straße, Abendsonne), harbor (Containerhafen bei Nacht, ab Runde 5)
var scenes = {}             # pro Szene: Kulissen, Spots, Deckung, Auto, Himmel
var swap_t = -1.0           # läuft während des Szenenwechsels
var life_t = 0.0            # Uhr für Kran, Lichter, Vögel, Zeitung
var glows = []              # flackernde Lampen und blinkende Warnlichter {mi, base, mode, k, t, scene}
var crane_load: Node3D
var crane_x = Vector2.ZERO  # Fahrweg der Laufkatze (x links, x rechts)
var birds = []              # aktueller Schwarm
var bird_t = 6.0
var bird_mat: ShaderMaterial
var paper = {}              # Zeitung auf der Straße
var nb = {}                 # der genervte Nachbar
var nb_door: Node3D         # Haustür (Scharnier)
var nb_card = {}
var nb_snd = {}
var door_open = false       # Haustür steht offen (Gegner oder Nachbar in der Tür)
var door_t = 0.0
var shreds = []             # fliegende Pappfetzen
var shred_mats = {}
var shred_shader: Shader
var mflash = 0.0            # Mündungsfeuer im HUD
var shadows = []            # weiche Bodenschatten {mi, node, k, off}
var shadow_mat: ShaderMaterial
var kick_side = 0.0
const HARBOR_FROM = 5
const M_TEX = ["m_motel.png", "m_cop.png", "m_cop2.png", "m_pickup.png", "m_trash.png", "m_sign.png", "m_cover.png", "m_sky.jpg", "m_ground.jpg", "m_deb_tire.png", "m_deb_mirror.png", "m_deb_light.png"]
const H_TEX = ["h_stack.png", "h_stack_back.png", "h_prop.png", "h_crane.png", "h_load.png", "h_truck.png", "h_mast.png", "h_forklift.png", "h_pallets.png", "h_cover.png", "h_sky.jpg", "h_ground.jpg", "h_deb_tire.png", "h_deb_tank.png", "h_deb_lamp.png",
	"door_leaf.png", "curtain.png", "neighbor0.png", "neighbor1.png", "paper.png", "birds.png"]
const H_W = 12.2            # Containerstapel
const H_X = 0.6
# Öffnungen im versetzten Containerstapel (u0, u1, v0, v1 im Bild)
const S_HOLES = {"door_bl": [0.0778, 0.2503, 0.5209, 0.8929], "door_br": [0.7948, 0.9087, 0.5242, 0.8963],
	"door_tl": [0.2762, 0.3196, 0.0992, 0.4645], "door_tr": [0.7029, 0.7638, 0.0992, 0.4645]}
var car_dead = false
var car_fx = []             # Feuer und Rauch am kaputten Auto
var car_burn_t = 0.0
var car_burn_age = 0.0
var car_smoke_t = 0.0
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
var warmed2 = false
var warming = false
var mesh_cache = {}         # Partikel-Flächen nach Material und Größe, einmal angelegt
var fb_mesh: QuadMesh
var sfx_pool = []           # feste Ton-Abspieler statt für jeden Ton einen neuen
var sfx_next = 0
var label_pool = []         # Punkte-Texte zum Wiederverwenden
var label_next = 0
var hitch_total = 0
var evlog = []              # letzte Ereignisse (für das Ruckel-Protokoll)
var hitches = []            # gemessene Hänger: {ms, what}
var frame_avg = 0.016
var light_pool = []
var mega_light: OmniLight3D
var car_light: OmniLight3D
var img_cache = {}
var tex_cache = {}
var warmed = false
var break_t = 0.0           # Pause beim Rundenwechsel
var break_reload = false
var forcing = false
var early_snap = false


# ================================================================ Aufbau
func _ready() -> void:
	randomize()
	autotest = OS.get_environment("AUTOTEST") != ""
	_load_save()
	_make_shaders()
	_make_fx_assets()
	_make_lights()
	tex_nade = load("res://art/grenade.png")
	_make_world()
	_make_sounds()
	_make_hud()
	_audio_apply()
	_upd_check()
	_set_state("title")
	for c in cards:
		c.t = -10.0       # Buch zu
	_open_book(0.4)


func _make_shaders() -> void:
	card_shader = Shader.new()
	card_shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, alpha_to_coverage;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 back_col : source_color = vec3(0.56, 0.44, 0.32);
uniform float flash = 0.0;
uniform float dim = 1.0;
uniform float sway = 0.0;      // Baum wiegt sich (oben), Gardine weht (unten)
uniform float hang = 0.0;
uniform float sway_speed = 1.0;
uniform bool back_tex = false; // Rückseite zeigt das gespiegelte Bild (Tür)
uniform vec4 holes[16];        // Einschusslöcher in der Pappe: uv, Radius, Zufall
uniform int nholes = 0;
uniform float aspect = 0.5;
void vertex() {
	if (sway > 0.0) {
		float k = mix(pow(1.0 - UV.y, 1.6), pow(UV.y, 1.2), hang);
		float t = TIME * sway_speed;
		float s = sin(t * 0.9 + UV.x * 0.5) * 0.55 + sin(t * 2.1 + UV.y * 3.0 + UV.x * 2.0) * 0.3 + sin(t * 4.7 + UV.y * 9.0 + UV.x * 6.0) * 0.15;
		VERTEX.x += sway * k * s;
		VERTEX.z += sway * k * hang * sin(t * 1.7 + UV.y * 5.0 + UV.x * 4.0) * 0.8;
	}
}
void fragment() {
	vec4 c = texture(tex, back_tex && !FRONT_FACING ? vec2(1.0 - UV.x, UV.y) : UV);
	vec3 col = c.rgb;
	float alpha = c.a;
	float torn = 0.0;
	for (int i = 0; i < nholes; i++) {
		vec2 d = (UV - holes[i].xy) * vec2(aspect, 1.0);
		float L = length(d);
		float ang = atan(d.y, d.x);
		float r = holes[i].z * (1.0 + 0.3 * sin(ang * 5.0 + holes[i].w * 7.0) + 0.17 * sin(ang * 11.0 + holes[i].w * 3.0) + 0.09 * sin(ang * 23.0 + holes[i].w));
		if (L < r) {
			alpha = 0.0;
		} else if (L < r * 1.32) {
			torn = max(torn, 1.0 - (L - r) / (r * 0.32));
		}
	}
	if (back_tex && !FRONT_FACING) {
		col *= 0.72;
	} else if (!FRONT_FACING) {
		// Rückseite: graue Wellpappe
		float r = fract(UV.x * 90.0);
		col = back_col * (0.86 + 0.14 * smoothstep(0.3, 0.5, r) * smoothstep(0.9, 0.7, r));
	}
	col = mix(col, vec3(0.7, 0.58, 0.42), torn * 0.9);
	ALBEDO = col * dim;
	ALPHA = alpha;
	// Ausgeschnittene Pappe statt Transparenz: wird im deckenden Durchgang gemalt und schreibt Tiefe,
	// dadurch kann die Zeichenreihenfolge (Himmel, Innenraum, Gegner) nie mehr durcheinandergeraten
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.35;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(tex, 0));
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
func _tex(tex_name: String) -> Texture2D:
	if not tex_cache.has(tex_name):
		tex_cache[tex_name] = load("res://art/" + tex_name)
	return tex_cache[tex_name]


func _card(tex_name: String, w: float, pos: Vector3, kind: String, h: float = -1.0) -> Dictionary:
	var tex: Texture2D = _tex(tex_name)
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
	# kleine Kopie des Bildes für die Treffer-Prüfung (durchsichtige Stellen zählen nicht), einmal pro Bild
	var img: Image = img_cache.get(tex_name)
	if img == null:
		img = tex.get_image()
		if img.is_compressed():
			img.decompress()
		img = img.duplicate()
		if img.get_width() > 256:
			img.resize(256, maxi(1, int(256.0 * img.get_height() / img.get_width())), Image.INTERPOLATE_BILINEAR)
		img_cache[tex_name] = img
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
	var street_sky: Node3D = sky.pv
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
	car.label = "CAR"
	car.debris = [["car_bumper.png", 1.95, Vector3(-1.9, 0.0, 0.35), Vector3(-0.95, 0.45, 0.18)],
		["car_tire.png", 0.6, Vector3(-0.9, 0.0, 0.5), Vector3(0.0, 0.25, -0.12)],
		["car_mirror.png", 0.25, Vector3(-2.6, 0.0, 0.6), Vector3(-PI * 0.4, 0.8, 0.0)]]
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
		if i == 6:   # Haustür: ganze Figur, fast so hoch wie die Tür
			slots.append({"pos": Vector3(x, ybot, FAC_Z - 0.3), "mode": "flip", "busy": false, "name": "door", "eh": 2.5})
		else:
			# großer Gegner, Füße unter dem Fensterbrett, Kopf knapp unter dem Sturz
			var wh = (hh[3] - hh[2]) * fac_h
			var drop = ENEMY_H_BACK - (wh - 0.1)
			slots.append({"pos": Vector3(x, ybot - drop, FAC_Z - 0.32), "mode": "flip", "busy": false, "name": "window%d" % i, "box_lift": drop, "eh": ENEMY_H_BACK})
	slots.append({"pos": Vector3(-2.55, 0.0, -7.4), "mode": "flip", "busy": false, "name": "crates", "partner": "window4", "eh": ENEMY_H_FRONT})
	for sl in slots:
		if sl.name == "window4":
			sl.partner = "crates"
	slots.append({"pos": Vector3(4.25, 0.28, -8.75), "mode": "flip", "busy": false, "name": "car", "box_lift": 1.02, "eh": ENEMY_H_FRONT})
	var street_deco = _make_street_life(fac, fac_h, tree)
	_shadow(car, 1.0, 1.3, 0.6)
	_shadow(crates, 1.05, 1.4, 0.55)
	_shadow(tree, 0.45, 2.2, 0.35)
	_shadow(hedge, 1.05, 1.0, 0.45)
	_shadow(lamp, 0.35, 0.5, 0.4)
	scenes["street"] = {"deco": street_deco, "cards": cards, "slots": slots, "wall": wall, "car": car_card, "sky": street_sky,
		"bg": Color(0.86, 0.6, 0.38), "amb": "ambience"}
	_make_harbor()
	_make_motel()

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
	scenes.street.motes = mg
	var mh = Gradient.new()
	mh.set_color(0, Color(0.75, 0.85, 1.0, 0.0))
	mh.add_point(0.3, Color(0.8, 0.88, 1.0, 0.4))
	mh.add_point(0.7, Color(1.0, 0.8, 0.55, 0.35))
	mh.set_color(mh.get_point_count() - 1, Color(0.8, 0.88, 1.0, 0.0))
	scenes.harbor.motes = mh
	scenes.motel.motes = mg
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.3
	add_child(motes)
	_use_scene("street")


# Zweite Szene: Containerhafen bei Nacht. Gleicher Spielbereich wie die Straße, nur anders verkleidet
func _make_harbor() -> void:
	cards = []
	slots = []
	var sky = _card("h_sky.jpg", 220.0, Vector3(0.0, -28.6, -75.0), "sky")
	sky.mat.set_shader_parameter("dim", 1.0)
	var gm = ShaderMaterial.new()
	gm.shader = ground_shader
	gm.set_shader_parameter("tex", load("res://art/h_ground.jpg"))
	gm.set_shader_parameter("rep", 3.4)
	var gq = QuadMesh.new()
	gq.size = Vector2(60.0, 24.0)
	gq.center_offset = Vector3(0, 24.0 * 0.5, 0)
	var gi = MeshInstance3D.new()
	gi.mesh = gq
	gi.material_override = gm
	var gp = Node3D.new()
	gp.position = Vector3(0, 0, FAC_Z + 15.0)  # reicht 9 m hinter den Stapel
	gp.rotation.x = -PI * 0.5
	add_child(gp)
	gp.add_child(gi)
	cards.append({"pv": gp, "mi": gi, "mat": gm, "img": null, "w": 60.0, "h": 24.0, "kind": "ground", "t": 99.0, "delay": 0.0, "up": true, "static": true})
	# versetzter Containerstapel, Türen offen; dahinter die Innenräume (perspektivisch passend vergrößert)
	var ct = _card("h_stack.png", H_W, Vector3(H_X, FAC_Y, FAC_Z), "metal")
	ct.delay = 0.0
	cards.append(ct)
	var ch: float = ct.h
	# im Bild ist unter den Containern noch Rand: Karte so weit absenken, dass sie auf dem Boden stehen
	var sink = (1.0 - 826.0 / 887.0) * ch
	ct.pv.position.y -= sink
	var f = (13.0 + 1.0) / 13.0
	var bk = _card("h_stack_back.png", H_W * f, Vector3.ZERO, "room")
	_adopt(ct.pv, bk.pv, Vector3(H_X * f - H_X, CAM_UP.y + (FAC_Y - CAM_UP.y) * f - FAC_Y, -1.0))
	bk.static = true
	cards.append(bk)
	var prop = _card("h_prop.png", 2.7, Vector3(-0.5, -0.04, -10.0), "metal")
	prop.delay = 0.3
	cards.append(prop)
	var truck = _card("h_truck.png", 5.6, Vector3(-7.9, -0.05, -10.4), "metal")
	truck.delay = 0.25
	cards.append(truck)
	var mast = _card("h_mast.png", 1.9, Vector3(8.4, -0.05, -11.6), "metal")
	mast.delay = 0.45
	cards.append(mast)
	var fork = _card("h_forklift.png", 2.7, Vector3(4.45, -0.04, -8.4), "metal")
	fork.delay = 0.6
	fork.base = fork.pv.position
	fork.label = "FORKLIFT"
	fork.debris = [["h_deb_tire.png", 0.55, Vector3(-1.1, 0.0, 0.5), Vector3(0.0, 0.3, -0.1)],
		["h_deb_tank.png", 0.62, Vector3(-2.0, 0.0, 0.4), Vector3(-0.2, 0.5, 0.25)],
		["h_deb_lamp.png", 0.2, Vector3(-2.7, 0.0, 0.7), Vector3(-0.3, 0.8, 0.0)]]
	cards.append(fork)
	var pal = _card("h_pallets.png", 3.8, Vector3(-4.2, -0.04, -7.0), "wood")
	pal.delay = 0.8
	cards.append(pal)
	var cov = _card("h_cover.png", 5.2, Vector3(1.05, -0.31, -1.35), "brick")
	cov.delay = 1.05
	cards.append(cov)
	# Spots: in den offenen Containern ganze Figur, oben in den halb offenen Türen nur ein Streifen
	for n in S_HOLES:
		var hh = S_HOLES[n]
		var x = H_X + ((hh[0] + hh[1]) * 0.5 - 0.5) * H_W
		var ybot = FAC_Y - sink + (1.0 - hh[3]) * ch
		var oh = (hh[3] - hh[2]) * ch
		if n == "door_tl" or n == "door_tr":
			# schmaler Türspalt oben: Gegner steht vor der halb offenen Tür auf der Kante, ganz sichtbar
			slots.append({"pos": Vector3(x, ybot - 0.02, FAC_Z + 0.14), "mode": "flip", "busy": false, "name": n, "eh": oh - 0.05, "box_lift": 0.0})
		else:
			var eh = 2.8
			var drop = eh - (oh - 0.08)
			slots.append({"pos": Vector3(x, ybot - drop, FAC_Z - 0.5), "mode": "flip", "busy": false, "name": n, "eh": eh, "box_lift": drop})
	# oben auf dem mittleren Container, hinter der Schiffsschraube, hinter den Paletten, hinter dem Gabelstapler
	slots.append({"pos": Vector3(H_X, FAC_Y - sink + (1.0 - 0.058) * ch - 0.04, FAC_Z - 0.35), "mode": "flip", "busy": false, "name": "roof", "eh": 2.5})
	slots.append({"pos": Vector3(0.55, 0.0, -10.4), "mode": "flip", "busy": false, "name": "prop", "eh": ENEMY_H_FRONT})
	slots.append({"pos": Vector3(-2.95, 0.15, -7.4), "mode": "flip", "busy": false, "name": "crates", "eh": ENEMY_H_FRONT})
	# Gabelstapler-Spot liegt aus Spielersicht vor der rechten unteren Containertür: nie beide gleichzeitig
	slots.append({"pos": Vector3(4.0, 0.05, -8.75), "mode": "flip", "busy": false, "name": "car", "box_lift": 1.05, "partner": "door_br", "eh": ENEMY_H_FRONT})
	for sl in slots:
		if sl.name == "door_br":
			sl.partner = "car"
	var harbor_deco = _make_harbor_life(sky.pv)
	_shadow(truck, 0.9, 1.5, 0.6)
	_shadow(fork, 0.95, 1.2, 0.6)
	_shadow(pal, 1.05, 1.4, 0.55)
	_shadow(prop, 1.0, 1.3, 0.55)
	_shadow(mast, 0.4, 0.6, 0.45)
	_shadow(ct, 1.0, 1.6, 0.5)
	scenes["harbor"] = {"deco": harbor_deco, "cards": cards, "slots": slots, "wall": cov, "car": fork, "sky": sky.pv,
		"bg": Color(0.05, 0.07, 0.11), "amb": "ambience_harbor"}


# Szene umschalten: andere Kulissen ausblenden, Spots, Deckung und Auto übernehmen
func _use_scene(n: String) -> void:
	scene = n
	for k in scenes:
		var on = k == n
		scenes[k].sky.visible = on
		if scenes[k].has("deco"):
			scenes[k].deco.visible = on
		for c in scenes[k].cards:
			c.pv.visible = on
	var sc = scenes[n]
	cards = sc.cards
	slots = sc.slots
	wall = sc.wall
	car_card = sc.car
	env.background_color = sc.bg
	if motes != null and sc.has("motes"):
		motes.color_ramp = sc.motes
	if ambience != null and sounds.has(sc.amb) and ambience.stream != sounds[sc.amb]:
		ambience.stream = sounds[sc.amb]
		ambience.play()


func _make_sounds() -> void:
	for n in ["music", "boom", "car_boom", "shotgun", "smg", "rocket", "pickup", "mega_appear", "warn", "throw", "shot_player", "shot_enemy", "impact_brick", "impact_metal", "impact_card", "target_up", "target_down", "reload", "empty", "player_hit", "ambience", "ambience_harbor", "ambience_motel", "siren", "radio0", "radio1"]:
		for ext in [".ogg", ".wav"]:
			var p = "res://sfx/" + n + ext
			if ResourceLoader.exists(p):
				sounds[n] = load(p)
				break
	# Sprüche: voices[kategorie][stimme] = [Streams]; Stimmen A Boss, B Hitzkopf, C Brecher, D Gangsterin
	for cat in ["appear", "fire", "hit", "taunt", "mandown", "hide", "nade"]:
		voices[cat] = {}
		for v in ["A", "B", "C", "D"]:
			var arr = []
			for i in range(1, 13):
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
	reload_player = AudioStreamPlayer.new()
	reload_player.volume_db = -1.0
	add_child(reload_player)
	var bi = AudioServer.bus_count
	AudioServer.add_bus(bi)
	AudioServer.set_bus_name(bi, "Music")
	AudioServer.set_bus_send(bi, "Master")
	var lim = AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.8
	AudioServer.add_bus_effect(bi, lim)
	# Gegnerstimmen: eigener Kanal mit Hall und weniger Höhen, damit sie klar nach "weit weg im Gebäude" klingen
	var fb = AudioServer.bus_count
	AudioServer.add_bus(fb)
	AudioServer.set_bus_name(fb, "Far")
	AudioServer.set_bus_send(fb, "Master")
	var lp = AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3800.0
	AudioServer.add_bus_effect(fb, lp)
	var rv = AudioEffectReverb.new()
	rv.room_size = 0.55
	rv.damping = 0.6
	rv.wet = 0.32
	rv.dry = 0.85
	rv.predelay_msec = 40.0
	AudioServer.add_bus_effect(fb, rv)
	AudioServer.set_bus_volume_db(fb, -2.0)
	far_bus = fb
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	music.stream = sounds.get("music")
	add_child(music)
	music.finished.connect(func(): music.play())
	_music_apply()
	if music.stream != null and not autotest:
		music.play()


func _music_apply() -> void:
	if music == null:
		return
	# im Menü und nach Game Over voll, während der Runde leiser, damit man Schüsse und Stimmen hört
	if music_vol <= 0.01:
		music.volume_db = -80.0
		return
	var base = linear_to_db(music_vol)
	music.volume_db = lerpf(base - 14.0, base + 13.0, music_k)


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
	_evt("voice " + cat)
	# nie zweimal hintereinander derselbe Spruch
	var key = cat + e.get("voice", "A")
	var stream = arr[randi() % arr.size()]
	if arr.size() > 1:
		while stream == last_bark.get(key):
			stream = arr[randi() % arr.size()]
	last_bark[key] = stream
	var go = func():
		if not is_instance_valid(e.pv):
			return
		_far_voice(stream, e.mi.global_transform * Vector3(0, e.h * 0.85, 0), randf_range(0.97, 1.03))
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(go)
	else:
		go.call()


func _sfx(n: String, vol: float = 0.0, pitch_var: float = 0.08) -> void:
	if not sounds.has(n):
		return
	if sfx_pool.is_empty():
		for i in 16:
			var np = AudioStreamPlayer.new()
			add_child(np)
			sfx_pool.append(np)
	var p: AudioStreamPlayer = null
	for i in sfx_pool.size():
		var c: AudioStreamPlayer = sfx_pool[(sfx_next + i) % sfx_pool.size()]
		if not c.playing:
			p = c
			sfx_next = (sfx_next + i + 1) % sfx_pool.size()
			break
	if p == null:
		p = sfx_pool[sfx_next]
		sfx_next = (sfx_next + 1) % sfx_pool.size()
	p.stream = sounds[n]
	p.volume_db = -80.0 if warming else vol
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
	if vol > -60.0 and not n.begins_with("target"):
		_evt("snd " + n)


# ================================================================ HUD
class HudDraw extends Control:
	var g   # Hauptszene
	func _draw() -> void:
		g._hud_draw(self)
		g._snd_draw(self)


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
	_make_name_entry(layer)


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
	return panel_k > 0.02 or editing or snd_open


func _tab_rect() -> Rect2:
	var vs = _vs()
	return Rect2(vs.x - PANEL_W * panel_k - 34, vs.y * 0.42 - 48, 34, 96)


func _panel_rect() -> Rect2:
	var vs = _vs()
	return Rect2(vs.x - PANEL_W * panel_k, 48, PANEL_W, 578)


func _slider_rect(i: int) -> Rect2:
	var pr = _panel_rect()
	return Rect2(pr.position.x + 22, pr.position.y + 16 + i * 66 + 34, PANEL_W - 44, 26)


func _panel_btn_rect(i: int) -> Rect2:
	var pr = _panel_rect()
	# die letzten beiden (Sound, Menü) nebeneinander
	if i >= 3:
		var hw = (PANEL_W - 44 - 10) * 0.5
		return Rect2(pr.position.x + 22 + (i - 3) * (hw + 10), pr.position.y + 362 + 3 * 54, hw, 44)
	return Rect2(pr.position.x + 22, pr.position.y + 362 + i * 54, PANEL_W - 44, 44)


func _done_btn_rect() -> Rect2:
	var vs = _vs()
	return Rect2(vs.x * 0.5 - 90, 92, 180, 50)


func _slider_set(i: int, x: float) -> void:
	var sd = SLIDERS[i]
	var r = _slider_rect(i)
	var k = clampf((x - r.position.x) / r.size.x, 0, 1)
	set(sd.key, snappedf(lerpf(sd.min, sd.max, k), 0.05))
	_music_apply()


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
		elif _panel_btn_rect(3).has_point(p):
			snd_open = true
			panel_open = false
		elif _panel_btn_rect(4).has_point(p):
			_quit_to_menu()
		elif _panel_btn_rect(2).has_point(p):
			aim_mode = "snap"
			aim_sens = 1.7
			aim_accel = 1.0
			recenter = 0.6
			aim_assist = 0.35
			music_vol = 0.5
			_music_apply()
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
		# Mündungsfeuer: heller, warmer Blitz von rechts unten (dort, wo die Waffe wäre)
		if mflash > 0.0 and not cover:
			var fo = Vector2(vs.x * 0.74, vs.y * 1.04)
			var fk = minf(mflash, 1.0)
			for i in 5:
				var rr = (60.0 + i * 55.0) * (0.8 + 0.2 * mflash)
				c.draw_circle(fo, rr, Color(1.0, 0.72 - i * 0.06, 0.35 - i * 0.05, 0.16 * fk * (1.0 - i * 0.16)))
			var dirv = (aim - fo).normalized()
			for i in 6:
				var a = dirv.angle() + randf_range(-0.6, 0.6)
				var ln = randf_range(70.0, 170.0) * mflash
				c.draw_line(fo, fo + Vector2.from_angle(a) * ln, Color(1.0, 0.85, 0.55, 0.35 * fk), randf_range(6.0, 14.0), true)
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
		_text(c, Vector2(282, 51), "%d" % maxi(0, ceili(health)), 20)
		# Punkte oben rechts
		_panel(c, Rect2(vs.x - 270, 18, 250, 50))
		_text(c, Vector2(vs.x - 252, 51), "SCORE", 17, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
		_text(c, Vector2(vs.x - 252, 52), "%06d" % score, 28, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 214)
		# Stufe und Treffer oben Mitte
		_text(c, Vector2(0, 50), "ROUND %d  ·  %d / %d" % [stage, mini(round_kills, round_goal), round_goal], 17, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, vs.x, font_light)
		# Munition unten rechts
		_panel(c, Rect2(vs.x - 250, vs.y - 86, 230, 66))
		if weapon != "pistol":
			_text(c, Vector2(vs.x - 232, vs.y - 45), WPN_NAMES.get(weapon, ""), 19, Color(1.0, 0.82, 0.45), HORIZONTAL_ALIGNMENT_LEFT, -1)
			_text(c, Vector2(vs.x - 92, vs.y - 43), "%d" % wpn_ammo, 34, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 70)
		else:
			for i in MAG:
				var bx = vs.x - 236 + i * 14
				var full = i < ammo
				var bc = Color(1.0, 0.82, 0.45) if full else Color(1, 1, 1, 0.16)
				c.draw_rect(Rect2(bx, vs.y - 70, 9, 24), bc)
				c.draw_circle(Vector2(bx + 4.5, vs.y - 70), 4.5, bc)
			_text(c, Vector2(vs.x - 112, vs.y - 43), "%d" % ammo, 34, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 56)
			_text(c, Vector2(vs.x - 54, vs.y - 43), "/%d" % reserve, 17, Color(1, 0.55, 0.45, 0.9) if reserve <= 3 else Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
	if state == "play":
		# linkes Daumenfeld: halten = aufstehen und zielen
		var tc = thumb if (aim_idx >= 0 and not editing) else _thumb_home()
		var held = aim_idx >= 0
		c.draw_circle(tc, 62, Color(0.06, 0.05, 0.05, 0.4 if held else 0.3))
		c.draw_arc(tc, 62, 0, TAU, 48, Color(1, 1, 1, 0.7 if held else 0.35), 2.5, true)
		c.draw_circle(tc, 20, Color(1, 1, 1, 0.55 if held else 0.25))
		if not held:
			_text(c, tc + Vector2(-90, 92), "HOLD TO AIM", 15, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 180, font_light)
		# Feuerknopf rechts (bei offener Einstell-Leiste ausgeblendet)
		var fc = _fire_center() + Vector2(4000.0 if panel_k > 0.3 else 0.0, 0)
		var can = not cover
		c.draw_circle(fc, 70, Color(0.55, 0.08, 0.04, 0.55 if can else 0.25))
		c.draw_arc(fc, 70, 0, TAU, 48, Color(1, 0.75, 0.6, 0.85 if can else 0.3), 3.0, true)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			c.draw_line(fc + d * 12, fc + d * 30, Color(1, 1, 1, 0.9 if can else 0.35), 3.0, true)
		c.draw_arc(fc, 21, 0, TAU, 32, Color(1, 1, 1, 0.9 if can else 0.35), 3.0, true)
		# Granaten-Knopf mit Anzahl
		var gc = _nade_center() + Vector2(4000.0 if panel_k > 0.3 else 0.0, 0)
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
		# Nachlade-Hinweis: gelb bei der letzten Patrone, rot und blinkend bei leerem Magazin
		if weapon == "pistol" and not cover and reload_t <= 0 and ammo <= 1 and break_t <= 0.0 and (ammo == 0 or reserve > 0):
			var bl = 0.75 + 0.25 * sin(st_t * 10.0)
			var bw = 230.0 if (ammo == 0 and reserve == 0) else 190.0
			_panel(c, Rect2(vs.x * 0.5 - bw * 0.5, vs.y * 0.64 - 40.0, bw, 52.0), 0.5)
			if ammo == 0 and reserve == 0:
				_text(c, Vector2(0, vs.y * 0.64), "NO AMMO", 34, Color(1, 0.3, 0.22, bl), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
			elif ammo == 0:
				_text(c, Vector2(0, vs.y * 0.64), "RELOAD", 34, Color(1, 0.3, 0.22, bl), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
			elif reserve > 0:
				_text(c, Vector2(0, vs.y * 0.64), "RELOAD", 30, Color(1, 0.85, 0.25, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		# Fortschritt beim Nachladen als Ring ums Fadenkreuz
		if reload_t > 0.0:
			var rp = aim if not cover else vs * Vector2(0.5, 0.5)
			var fr = 1.0 - reload_t / RELOAD_TIME
			c.draw_arc(rp, 30, 0, TAU, 40, Color(0, 0, 0, 0.35), 5.0, true)
			c.draw_arc(rp, 30, -PI * 0.5, -PI * 0.5 + TAU * fr, 40, Color(1, 0.85, 0.4, 0.95), 3.5, true)
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
		# drei Modi zur Wahl, darunter jeweils der beste Eintrag
		var subs = {"easy": "3 maps · 12 rounds", "hard": "3 maps · real challenge", "endless": "how far can you get?"}
		for i in MODES.size():
			var m = MODES[i]
			var r = _mode_btn_rect(i)
			var on = m == mode
			_panel(c, r, 0.72 if on else 0.5)
			if on:
				c.draw_rect(Rect2(r.position + Vector2(14, r.size.y - 5), Vector2(r.size.x - 28, 3)), Color(1, 0.8, 0.35, 0.9 * a))
			_text(c, Vector2(r.position.x, r.position.y + 40), MODE_NAMES[m], 30, Color(1, 0.95, 0.86, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			_text(c, Vector2(r.position.x, r.position.y + 62), subs[m], 14, Color(1, 1, 1, 0.65 * a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_light)
			if i == 0:
				for j in 2:
					var tb = _title_btn_rect(j)
					_panel(c, tb, 0.55)
					_text(c, Vector2(tb.position.x, tb.position.y + 31), ["SOUND", "EXIT"][j], 17, Color(1, 1, 1, 0.85 * a), HORIZONTAL_ALIGNMENT_CENTER, tb.size.x, font_light)
			if not hs[m].is_empty():
				_text(c, Vector2(r.position.x, r.end.y + 24), "BEST  %s  %06d" % [hs[m][0].n, int(hs[m][0].s)], 15, Color(1, 0.86, 0.6, 0.8 * a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_light)
		_text(c, Vector2(vs.x - 220, vs.y - 18), "Build %d" % _my_build(), 14, Color(1, 1, 1, 0.5 * a), HORIZONTAL_ALIGNMENT_RIGHT, 200, font_light)
		_upd_draw(c, a)
	if state == "over" and st_t > 1.2 and not hitches.is_empty():
		var ha = clampf((st_t - 1.2) * 2.0, 0, 1)
		var y0 = vs.y - 24.0 - 20.0 * (hitches.size() - 1)
		_text(c, Vector2(20, y0 - 20), "Stutters this game: %d" % hitch_total, 14, Color(1, 0.8, 0.6, 0.8 * ha), HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
		for i in hitches.size():
			var h = hitches[i]
			_text(c, Vector2(20, y0 + i * 20), "Stutter %d ms after: %s" % [h.ms, h.what], 14, Color(1, 0.8, 0.6, 0.8 * ha), HORIZONTAL_ALIGNMENT_LEFT, vs.x - 260, font_light)
	if state == "over" and entering:
		_text(c, Vector2(0, vs.y * 0.13), "NEW HIGHSCORE  –  ENTER YOUR NAME", 22, Color(1, 0.86, 0.5, 0.95), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if state == "over" and st_t > 1.2 and not entering:
		var a = clampf((st_t - 1.2) * 2.0, 0, 1)
		_hs_draw(c, Vector2(vs.x * 0.5, vs.y * 0.53), a)
		_text(c, Vector2(0, vs.y * 0.9), "TAP TO CONTINUE", 24, Color(1, 1, 1, a * (0.45 + 0.55 * absf(sin(st_t * 2.6)))), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_upd_draw(c, a)


func _mode_btn_rect(i: int) -> Rect2:
	var vs = _vs()
	var w = 230.0
	var gap = 22.0
	var x0 = vs.x * 0.5 - (3.0 * w + 2.0 * gap) * 0.5
	return Rect2(x0 + i * (w + gap), vs.y * 0.56, w, 80)


# Top-5-Liste des gespielten Modus, der neue Eintrag leuchtet
func _hs_draw(c: Control, top: Vector2, a: float) -> void:
	var list: Array = hs[mode]
	if list.is_empty():
		return
	var w = 420.0
	var r = Rect2(top.x - w * 0.5, top.y, w, 34.0 + 30.0 * list.size())
	_panel(c, r, 0.78 * a)
	_text(c, Vector2(r.position.x, r.position.y + 24), "TOP 5  ·  " + MODE_NAMES[mode], 15, Color(1, 0.86, 0.6, 0.85 * a), HORIZONTAL_ALIGNMENT_CENTER, w, font_light)
	for i in list.size():
		var e = list[i]
		var y = r.position.y + 54 + i * 30
		var col = Color(1, 0.85, 0.4, a) if i == hs_new else Color(1, 1, 1, 0.85 * a)
		_text(c, Vector2(r.position.x + 24, y), "%d." % (i + 1), 20, col, HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
		_text(c, Vector2(r.position.x + 62, y), str(e.n), 20, col)
		_text(c, Vector2(r.position.x + 230, y), "R%d" % int(e.get("r", 0)), 16, Color(col.r, col.g, col.b, col.a * 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
		_text(c, Vector2(r.position.x, y), "%06d" % int(e.s), 20, col, HORIZONTAL_ALIGNMENT_RIGHT, w - 24)


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
			if sd.key == "recenter" or sd.key == "aim_assist" or sd.key == "music_vol":
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
		for i in 5:
			var br = _panel_btn_rect(i)
			var bs = StyleBoxFlat.new()
			bs.bg_color = Color(1, 1, 1, 0.1)
			bs.border_color = Color(1, 1, 1, 0.35)
			bs.set_border_width_all(1)
			bs.set_corner_radius_all(22)
			c.draw_style_box(bs, br)
			_text(c, Vector2(br.position.x, br.position.y + 29), [("AIM:  SNAP TO SPOTS" if aim_mode == "snap" else "AIM:  FREE"), "MOVE BUTTONS", "RESET CONTROLS", "SOUND", "QUIT TO MENU"][i], 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, br.size.x, font_light)
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
# Jeder Effekt einmal unsichtbar hinter der Fassade: das Handy bereitet dabei Shader und Partikel vor,
# damit es beim ersten echten Schuss, Treffer oder der ersten Explosion nicht ruckelt
func _warmup() -> void:
	for n in ENEMY_TEX:
		_tex(n + ".png")
	for n in ["box.png", "box_mega.png", "car_bumper.png", "car_tire.png", "car_mirror.png"] + H_TEX + M_TEX:
		_tex(n)
	# unter der Straße: der Boden deckt alles ab, auch solange die Fassade noch flach liegt
	var p = Vector3(0.0, -3.2, -7.0)
	fx_k = 1.0
	_fb_boom(p, 1.0)
	for k in ["boom0", "boom1", "boom2", "smoke5", "smoke5_dark"]:
		var q = _fb_quad(k, p, 0.5)
		q.visible = true
		get_tree().create_timer(0.4).timeout.connect(q.queue_free)
	_sparks(p, Vector3.UP, 4)
	_dust(p, Vector3.UP, 3, Color(0.7, 0.6, 0.5), 0.3)
	_chunks(p, Vector3.UP, 3, [Color(0.5, 0.4, 0.3), Color(0.6, 0.5, 0.4), Color(0.4, 0.3, 0.2)], 0.04)
	_smoke(p, 2)
	var fl = Sprite3D.new()
	fl.texture = tex_flash
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.shaded = false
	fl.position = p
	add_child(fl)
	get_tree().create_timer(0.4).timeout.connect(fl.queue_free)
	_flash_light(p, 2.0, Color(1, 0.7, 0.4), 1.0)
	var nd = Sprite3D.new()
	nd.texture = tex_nade
	nd.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nd.shaded = false
	nd.position = p
	add_child(nd)
	get_tree().create_timer(0.4).timeout.connect(nd.queue_free)
	var hole = Sprite3D.new()
	hole.texture = tex_hole
	hole.shaded = true
	hole.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	hole.position = p
	add_child(hole)
	get_tree().create_timer(0.4).timeout.connect(hole.queue_free)
	var lb = Label3D.new()
	lb.text = "+100"
	lb.font = font
	lb.font_size = 54
	lb.outline_size = 14
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Color(1, 1, 1, 0.01)
	lb.pixel_size = 0.0001
	lb.position = p
	add_child(lb)
	get_tree().create_timer(0.4).timeout.connect(lb.queue_free)
	# eine Figur und eine Kiste einmal anlegen (Bild-Cache, Material)
	var all_cards = []
	for n in ENEMY_TEX:
		all_cards.append(n + ".png")
	all_cards += ["box.png", "box_mega.png", "car_bumper.png", "car_tire.png", "car_mirror.png"] + H_TEX + M_TEX
	for i in all_cards.size():
		var c = _card(all_cards[i], 0.6, p + Vector3(-2.0 + i * 0.5, -0.5, 0), "card")
		get_tree().create_timer(0.6).timeout.connect(c.pv.queue_free)
	_flash_light(p + Vector3(0, 0.5, 0.5), 4.0, Color(1, 0.7, 0.4), 1.0, 0.5)
	_flash_light(p + Vector3(1, 0.5, 0.5), 4.0, Color(1, 0.7, 0.4), 1.0, 0.5)
	# räumlicher Ton: einmal stumm einrichten, damit der erste Spruch nicht hängt
	var a3 = AudioStreamPlayer3D.new()
	a3.stream = sounds.get("target_up")
	a3.volume_db = -80.0
	a3.unit_size = 14.0
	add_child(a3)
	a3.global_position = p
	a3.play()
	get_tree().create_timer(1.0).timeout.connect(a3.queue_free)
	for snd in ["target_up", "shot_player", "shot_enemy", "impact_brick", "pickup", "reload"]:
		_sfx(snd, -80.0, 0.0)


# Alle Einschlag-Arten einmal komplett (Funken, Staub, Splitter, Einschussloch, Punkte-Text),
# mit einem, zwei und drei Lichtblitzen gleichzeitig – unter der Straße und stumm
func _warmup_impacts() -> void:
	warming = true
	var p = Vector3(0.0, -3.2, -7.0)
	var fake = _card(ENEMY_TEX[0] + ".png", 1.0, p, "card")
	var kinds = ["room", "brick", "metal", "wood", "leaf", "card", "ground", "box", "sky"]
	for i in kinds.size():
		for l in (i % 3) + 1:
			_flash_light(p + Vector3(0.3 * l, 0.5, 0.4), 3.5, Color(1, 0.7, 0.4), 2.0, 0.3)
		var c = {"kind": kinds[i], "mi": fake.mi, "w": fake.w, "h": fake.h}
		var lp = Vector3(randf_range(-0.2, 0.2), 0.9, 0.0)
		for dist in [1.5, 7.0, 14.0]:
			fx_k = clampf(dist / 7.0, 0.22, 1.3)
			_impact({"card": c, "point": p + Vector3(0, 0.9, 0), "normal": Vector3(0, 0, 1), "local": lp, "uv": Vector2(0.5, 0.5)}, true)
	_sparks(p, Vector3.UP, 26)
	_sparks(p, Vector3.UP, 14)
	for i in 6:
		_float_text(p, "+%d" % (100 + i), i % 2 == 0)
	for e in label_pool:
		e.l.modulate = Color(1, 1, 1, 0.0)   # Texte liegen immer im Vordergrund: beim Vorwärmen unsichtbar
	_sfx("pickup")
	_sfx("impact_card")
	warming = false
	get_tree().create_timer(0.8).timeout.connect(fake.pv.queue_free)


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


func _start_mode(m: String) -> void:
	mode = m
	_save()
	_back_to_street()
	_close_book()
	_open_book(0.35)
	_start_game()


func _back_to_street() -> void:
	swap_t = -1.0
	_nb_reset()
	if scene != "street":
		_car_reset()
		_use_scene("street")
		for c in cards:
			c.t = -10.0


func _start_game() -> void:
	for e in enemies:
		e.pv.queue_free()
	enemies.clear()
	for s in slots:
		s.busy = false
	_nb_reset()
	for h in holes_live:
		if is_instance_valid(h):
			h.queue_free()
	holes_live.clear()
	health = 100.0
	score = 0
	kills = 0
	stage = 1
	won = false
	hs_new = -1
	hide_said = false
	round_kills = 0
	hitch_total = 0
	hitches.clear()
	out_t = -1.0
	over_reason = ""
	break_t = 0.0
	_round_setup()
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
	_megaphone(0, 1.4)
	_show_msg("ROUND 1", "%s  ·  %d enemies  ·  %d bullets" % [MODE_NAMES[mode], round_goal, ammo + reserve], 2.4)


# Runde vorbereiten: feste Gegnerzahl, knappe Munition (Gegner plus Reserve für Fehlschüsse)
func _goal_for(st: int) -> int:
	return 10 + (_lv_for(st) - 1) * 3 + (2 if mode == "hard" else 0)


func _pool_for(st: int) -> int:
	var spare = maxi(3, 6 - _lv_for(st)) + (2 if mode == "easy" else (-1 if mode == "hard" else 0))
	return _goal_for(st) + maxi(2, spare)


func _round_setup() -> void:
	round_goal = _goal_for(stage)
	var pool = _pool_for(stage)
	ammo = mini(MAG, pool)
	reserve = pool - ammo
	round_kills = 0
	_nb_plan()


func _round_clear() -> void:
	if break_t > 0.0:
		return
	var left = ammo + reserve
	var bonus = left * 50 + int(health) * 5
	score += bonus
	stage += 1
	if mode != "endless" and stage > CAMPAIGN_ROUNDS:
		_mission_complete(bonus)
		return
	health = minf(100.0, health + 25.0)
	var goal = _goal_for(stage)
	var pool = _pool_for(stage)
	_show_msg("ROUND %d" % stage, "clear bonus +%d  ·  %d enemies  ·  %d bullets" % [bonus, goal, pool], 2.6)
	# kurze Ruhe: alle verschwinden, dann hört man das Nachladen und die Waffe ist voll
	for e in enemies:
		if e.state != "fall":
			e.state = "hide"
			e.t = 0.0
	for pr in projs.duplicate():
		if pr.kind == "enade":
			_proj_remove(pr)
	break_t = 2.6
	break_reload = false
	cover_time = 0.0
	spawn_t = 0.6
	# Durchsage per Megafon: letzte Runde der Kampagne = "we're coming in"
	_megaphone(5 if (mode != "endless" and stage == CAMPAIGN_ROUNDS) else randi_range(1, 4), 1.0)
	# alle vier Runden die nächste Map: Kulisse klappt zu, die neue klappt auf
	var target = _scene_for(stage)
	if target != scene:
		swap_to = target
		_show_msg("ROUND %d" % stage, "%s  ·  %d enemies  ·  %d bullets" % [{"harbor": "the docks", "motel": "the motel  ·  final showdown", "street": "back on the street"}[target], goal, pool], 4.2)
		break_t = 5.4
		swap_t = 1.25
		_close_book()


func _mission_complete(bonus: int) -> void:
	won = true
	stage -= 1
	score += 2000 + (500 if mode == "hard" else 0)
	_game_over()


# Top 5 je Modus: reicht die Punktzahl, fragt das Spiel nach dem Namen
func _hs_check() -> void:
	var list: Array = hs[mode]
	if score <= 0 or (list.size() >= 5 and score <= int(list[-1].s)):
		return
	entering = true
	get_tree().create_timer(1.3).timeout.connect(_name_prompt)


func _name_prompt() -> void:
	if autotest:
		_snap("27_name_entry_pre")
	var vs = _vs()
	name_edit.size = Vector2(360, 64)
	name_edit.position = Vector2(vs.x * 0.5 - 180 - 60, vs.y * 0.17)
	name_ok.size = Vector2(110, 64)
	name_ok.position = Vector2(vs.x * 0.5 + 190 - 60, vs.y * 0.17)
	name_edit.text = last_name
	name_edit.visible = true
	name_ok.visible = true
	name_edit.grab_focus()
	name_edit.select_all()


func _name_done(_t = "") -> void:
	if not entering:
		return
	var n = name_edit.text.strip_edges().to_upper()
	if n == "":
		n = "PLAYER"
	last_name = n
	var list: Array = hs[mode]
	var entry = {"n": n, "s": score, "r": stage}
	list.append(entry)
	list.sort_custom(func(a, b): return int(a.s) > int(b.s))
	while list.size() > 5:
		list.pop_back()
	hs_new = list.find(entry)
	entering = false
	name_edit.release_focus()
	name_edit.visible = false
	name_ok.visible = false
	DisplayServer.virtual_keyboard_hide()
	st_t = maxf(st_t, 1.2)
	_save()


func _make_name_entry(layer: CanvasLayer) -> void:
	name_edit = LineEdit.new()
	name_edit.max_length = 12
	name_edit.placeholder_text = "YOUR NAME"
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.add_theme_font_override("font", font)
	name_edit.add_theme_font_size_override("font_size", 30)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.05, 0.85)
	sb.border_color = Color(1, 0.85, 0.4, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	name_edit.add_theme_stylebox_override("normal", sb)
	name_edit.add_theme_stylebox_override("focus", sb)
	name_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	name_edit.text_submitted.connect(_name_done)
	name_edit.text_changed.connect(func(t):
		var up = t.to_upper()
		if up != t:
			var cpos = name_edit.caret_column
			name_edit.text = up
			name_edit.caret_column = cpos)
	name_edit.visible = false
	layer.add_child(name_edit)
	name_ok = Button.new()
	name_ok.text = "OK"
	name_ok.add_theme_font_override("font", font)
	name_ok.add_theme_font_size_override("font_size", 28)
	var bs = sb.duplicate()
	bs.bg_color = Color(1, 0.78, 0.3, 0.95)
	name_ok.add_theme_stylebox_override("normal", bs)
	name_ok.add_theme_stylebox_override("hover", bs)
	name_ok.add_theme_stylebox_override("pressed", bs)
	name_ok.add_theme_color_override("font_color", Color(0.1, 0.07, 0.03))
	name_ok.pressed.connect(func(): _name_done())
	name_ok.visible = false
	layer.add_child(name_ok)


func _game_over() -> void:
	if autotest:
		print("GAMEOVER reason=", over_reason, " health=", health, " ammo=", ammo, "/", reserve, " stage=", stage, " t=", at_t, " break=", break_t)
	_set_state("over")
	for pr in projs:
		if is_instance_valid(pr.n):
			pr.n.queue_free()
	projs.clear()
	cover = false
	if score > best:
		best = score
		_save()
	var acc = 0
	if shots_fired > 0:
		acc = roundi(100.0 * hits / shots_fired)
	if won:
		_show_msg("MISSION COMPLETE", "%s  ·  SCORE %06d  ·  ACCURACY %d%%" % [MODE_NAMES[mode], score, acc], 999.0)
	else:
		_show_msg(over_reason if over_reason != "" else "GAME OVER", "%s  ·  ROUND %d  ·  SCORE %06d  ·  ACCURACY %d%%" % [MODE_NAMES[mode], stage, score, acc], 999.0)
	_hs_check()
	for e in enemies:
		if e.state != "fall":
			e.state = "hide"
			e.t = 0.0


func _pop(t: float) -> float:
	# Feder: klappt hoch, schwingt leicht über und pendelt aus
	if t <= 0.0:
		return 0.0
	return 1.0 - exp(-7.5 * t) * cos(12.5 * t)


func _evt(what: String) -> void:
	evlog.append({"t": Time.get_ticks_msec(), "w": what})
	if evlog.size() > 24:
		evlog.pop_front()


func _process(dt: float) -> void:
	# Ruckel-Protokoll: ein Bild, das länger als 0,12 s gebraucht hat, wird mit den Ereignissen davor notiert
	var spike = dt > maxf(0.12, frame_avg * 3.0)
	frame_avg = lerpf(frame_avg, minf(dt, 0.1), 0.05)
	if spike and (state == "play" or state == "intro"):
		var now = Time.get_ticks_msec()
		var ws = []
		for e in evlog:
			if now - int(e.t) < int(dt * 1000.0) + 250:
				ws.append(e.w)
		hitch_total += 1
		var last_ago = (now - int(evlog[-1].t)) if not evlog.is_empty() else -1
		var what = ", ".join(ws) if not ws.is_empty() else ("nothing logged (last: %s, %d ms before)" % [evlog[-1].w, last_ago] if not evlog.is_empty() else "nothing logged")
		hitches.append({"ms": int(dt * 1000.0), "what": what})
		if hitches.size() > 6:
			hitches.pop_front()
		print("HITCH ", int(dt * 1000.0), " ms after: ", hitches[-1].what)
	dt = minf(dt, 0.05)
	st_t += dt
	msg_t = maxf(0.0, msg_t - dt)
	tip_t = maxf(0.0, tip_t - dt)
	bark_cd = maxf(0.0, bark_cd - dt)
	kick = maxf(0.0, kick - dt * 6.0)
	mflash = maxf(0.0, mflash - dt * 13.0)
	shake = maxf(0.0, shake - dt * 3.0)
	hurt = maxf(0.0, hurt - dt * 1.6)
	hit_mark = maxf(0.0, hit_mark - dt * 3.0)
	vignette.modulate.a = hurt
	panel_k = move_toward(panel_k, 1.0 if (panel_open and state == "play") else 0.0, dt / 0.18)
	var mk_target = 0.0 if (state == "play" or state == "intro") else 1.0
	music_k = move_toward(music_k, mk_target, dt / (1.2 if mk_target < music_k else 3.0))
	_music_apply()
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
			if not warmed and st_t > 0.15:
				warmed = true
				_warmup()
			if not warmed2 and st_t > 0.5:
				warmed2 = true
				_warmup_impacts()
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
	_lights_update(dt)
	_life_update(dt)
	_shreds_update(dt)
	_shadows_update()
	_car_burn(dt)
	_camera_update(dt)
	if autotest:
		_autotest(dt)
	hud.queue_redraw()


func _play_update(dt: float) -> void:
	if break_t > 0.0:
		break_t -= dt
		if swap_t > 0.0:
			swap_t -= dt
			if swap_t <= 0.0:
				_car_reset()
				_nb_reset()
				for f in fbs:
					if is_instance_valid(f.n):
						f.n.queue_free()
				fbs.clear()
				_use_scene(swap_to)
				for c in cards:
					c.t = -10.0
				_open_book(0.15)
		if not break_reload and break_t < 1.9:
			break_reload = true
			reload_player.stream = sounds.get("reload")
			reload_player.pitch_scale = 1.0
			reload_player.play(RELOAD_SKIP)
		if break_reload and break_t < 1.9 - RELOAD_TIME and round_kills >= round_goal:
			_round_setup()   # genau mit dem Schlitten-Klick ist die Waffe voll
		return
	# Nachladen: startet beim Ducken und läuft zu Ende, auch wenn man gleich wieder aufsteht
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0:
			var take = mini(MAG - ammo, reserve)
			ammo += take
			reserve -= take
			reload_t = 0.0
	elif cover and ammo < MAG and reserve > 0:
		reload_t = RELOAD_TIME
		reload_player.stream = sounds.get("reload")
		reload_player.pitch_scale = 1.0
		reload_player.play(RELOAD_SKIP)
	# Maschinengewehr: Feuerknopf halten = Dauerfeuer
	if weapon == "smg" and fire_idx >= 0 and not cover:
		auto_t -= dt
		if auto_t <= 0.0:
			_shoot(aim)
			auto_t = 0.085
	# zu lange in Deckung: ein Gegner wirft eine Granate über die Mauer
	if not _frozen():
		if cover:
			cover_time += dt
			if cover_time > 2.2 and not hide_said:
				hide_said = true
				for e in enemies:
					if not e.get("box", false) and (e.state == "aim" or e.state == "linger"):
						_bark(e, "hide", 0.8, 0.0, true)
						break
		else:
			cover_time = maxf(0.0, cover_time - dt * 2.0)
			hide_said = false
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
				nade_limit = maxf(2.6, randf_range(3.6, 5.0) - _lvl() * 0.2)
	# Gegner nachschicken
	var alive = 0
	for e in enemies:
		if e.state != "fall" and not e.get("box", false):
			alive += 1
	var max_alive = 1
	if round_kills >= 4 or _lvl() >= 2:
		max_alive = 2
	if _lvl() >= 3 and round_kills >= 3:
		max_alive = 3
	if _frozen():
		return
	spawn_t -= dt
	if spawn_t <= 0 and alive < max_alive and round_kills + alive < round_goal:
		_spawn()
		var base = maxf(0.6, 1.9 - _lvl() * 0.25)
		spawn_t = base * randf_range(0.6, 1.25)
	if ammo + reserve <= 0 and weapon == "pistol" and grenades <= 0:
		if out_t < 0.0:
			out_t = 1.4
			_show_msg("OUT OF AMMO", "", 1.4)
		out_t -= dt
		if out_t <= 0.0:
			over_reason = "OUT OF AMMO"
			_game_over()
			return
	else:
		out_t = -1.0
	if health <= 0:
		_game_over()


# Schwierigkeit: im Hafen fängt es wieder ruhiger an (Runde 5 spielt sich wie Runde 2 auf der Straße)
func _lvl() -> int:
	return _lv_for(stage)


# Kampagne: jede Map startet etwas leichter (Map 2 beginnt wie Runde 2); endlos: steigt immer weiter
func _lv_for(st: int) -> int:
	if mode == "endless":
		return st
	var map_i = (st - 1) / ROUNDS_PER_MAP
	return (st - 1) % ROUNDS_PER_MAP + 1 + map_i


func _scene_for(st: int) -> String:
	return MAPS[((st - 1) / ROUNDS_PER_MAP) % MAPS.size()]


func _dk(easy: float, hard: float) -> float:
	return easy if mode == "easy" else (hard if mode == "hard" else 1.0)


func _diff_aim() -> float:
	return maxf(0.75, 1.75 - (_lvl() - 1) * 0.15 - round_kills * 0.015) * _dk(1.3, 0.85)


func _spawn() -> void:
	var free = []
	for s in slots:
		if not s.busy and not s.get("off", false) and not _partner_busy(s):
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
	_evt("spawn " + ENEMY_TEX[ti])
	var tex: Texture2D = _tex(ENEMY_TEX[ti] + ".png")
	var eh: float = s.get("eh", ENEMY_H)
	var w = eh * tex.get_width() / float(tex.get_height())
	var c = _card(ENEMY_TEX[ti] + ".png", w, s.pos, "card", eh)
	if s.pos.y < 0.45:
		_shadow(c, 0.75, 0.9, 0.5)
	if scene == "harbor":
		c.mat.set_shader_parameter("dim", 0.8)
	c.merge({"slot": s, "state": "appear", "t": -0.3 if (scene == "street" and s.name == "door" and not door_open) else 0.0, "aim": _diff_aim() * randf_range(0.85, 1.2), "shots": 1 + (1 if _lvl() >= 2 and randf() < 0.35 else 0), "gun_v": GUN_V[ti], "mode": s.mode, "seen": 0.0, "side": -1.0 if randf() < 0.5 else 1.0, "voice": ["A", "B", "C", "D"][randi() % 4]}, true)
	_enemy_pose(c, 0.0)
	enemies.append(c)
	_sfx("target_up", -6.0, 0.12)
	_bark(c, "appear", 0.55, 0.25)


# Kisten-Spot und das Fenster dahinter liegen aus Spielersicht übereinander: nie beide gleichzeitig besetzt
func _partner_busy(s: Dictionary) -> bool:
	if forcing or not s.has("partner"):
		return false
	for o in slots:
		if o.name == s.partner:
			return o.busy
	return false


func _spawn_box(s: Dictionary, mega: bool) -> void:
	_evt("box" + (" mega" if mega else ""))
	var pos: Vector3 = s.pos
	if s.name == "car":
		pos.y += s.get("box_lift", 1.02)
	elif s.has("box_lift"):
		pos.y += s.box_lift
		pos.z += 0.1
	var c = _card("box_mega.png" if mega else "box.png", 0.85 if mega else 0.8, pos, "box")
	c.merge({"slot": s, "state": "appear", "t": 0.0, "aim": 99.0, "shots": 0, "gun_v": 0.5, "mode": "flip", "seen": 0.0, "side": 1.0,
		"box": true, "mega": mega, "life": 2.4 if mega else 3.2}, true)
	_enemy_pose(c, 0.0)
	enemies.append(c)
	_sfx("target_up", -4.0, 0.12)
	if mega:
		_sfx("mega_appear", -2.0, 0.0)
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
	_evt("box opened")
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
		r = "ammo" if x < 0.32 else ("grenade" if x < 0.52 else ("health" if x < 0.7 else ("shotgun" if x < 0.86 else "smg")))
	match r:
		"ammo":
			reserve += 6
			title = "+6 BULLETS"
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
	_evt("hit")
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
	round_kills += 1
	if round_kills == round_goal and state == "play" and break_t <= 0.0:
		get_tree().create_timer(0.9).timeout.connect(func():
			if state == "play":
				_round_clear())


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
		if e.state != "hide" and e.state != "fall" and e.t > 0.0:
			e.vis = e.get("vis", 0.0) + dt
		match e.state:
			"appear":
				var k = _pop(maxf(e.t, 0.0) * 1.3)
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
					if e.t > e.life and state == "play":
						e.state = "hide"
						e.t = 0.0
					continue
				e.seen += dt
				if state != "play" or break_t > 0.0:
					e.t = minf(e.t, e.aim * 0.5)
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
				if e.t > 0.45 and e.get("vis", 0.0) >= MIN_VIS:
					_evt("enemy hides")
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
		_evt("enemy removed")
		e.slot.busy = false
		e.pv.queue_free()
		enemies.erase(e)


func _enemy_fire(e: Dictionary) -> void:
	_evt("enemy shot")
	_bark(e, "fire", 0.3)
	var mp = _muzzle(e)
	_flash(mp + Vector3(0, 0, 0.15), 0.9, Color(1.0, 0.7, 0.35), 7.0)
	_smoke(mp, 4)
	_sfx("shot_enemy", -2.0, 0.1)
	var acc = minf(0.75, (0.38 + _lvl() * 0.05) * _dk(0.75, 1.12))
	if not cover and cover_k < 0.5 and randf() < acc:
		health -= randf_range(9.0, 14.0) * _dk(0.7, 1.15)
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
	pitch += kick * 2.8
	yaw += kick * kick * kick_side * 0.9
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
			if ui_drag == "snd":
				_snd_release(ev.position)
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
			if ui_drag == "snd":
				_snd_drag(ev.position)
			elif ui_drag.begins_with("slider"):
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
	if snd_open:
		_snd_press(p, idx)
		return
	match state:
		"title":
			if st_t < 0.6:
				return
			if _upd_btn_rect().has_point(p) and upd_url != "" and upd_build > _my_build():
				OS.shell_open(upd_url)
				return
			for i in MODES.size():
				if _mode_btn_rect(i).grow(10).has_point(p):
					_start_mode(MODES[i])
					return
			if _title_btn_rect(0).grow(6).has_point(p):
				snd_open = true
				return
			if _title_btn_rect(1).grow(6).has_point(p):
				_save()
				get_tree().quit()
				return
		"over":
			if st_t < 1.2:
				return
			if entering:
				return
			if _upd_btn_rect().has_point(p) and upd_url != "" and upd_build > _my_build():
				OS.shell_open(upd_url)
				return
			# zurück ins Hauptmenü (Modus wählen)
			if scene != "street":
				_back_to_street()
				_close_book()
				_open_book(0.2)
			msg_t = 0.0
			_set_state("title")
		"play":
			if _ui_press(p, idx):
				return
			if p.distance_to(_nade_center()) < 58:
				_throw_grenade()
			elif p.distance_to(_fire_center()) < 105:
				fire_idx = idx
				auto_t = 0.085
				if not cover:
					_shoot(aim)
			elif aim_idx < 0:
				# Daumen drauf: aufstehen, ziehen bewegt das Fadenkreuz
				aim_idx = idx
				thumb = p
				thumb0 = p
				cover = false


func _shoot(p: Vector2) -> void:
	_evt("shot " + weapon)
	var w = weapon
	if w == "pistol" and reload_t > 0.0:
		return
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
	kick = 1.0 if w != "smg" else 0.75
	kick_side = randf_range(-1.0, 1.0)
	mflash = 1.4 if w in ["shotgun", "rocket"] else 1.0
	shake = maxf(shake, 0.32 if w == "pistol" else (0.36 if w == "smg" else 0.7))
	match w:
		"shotgun":
			_sfx("shotgun", 1.0, 0.04)
		"smg":
			_sfx("smg", 2.0, 0.06)
		"rocket":
			_sfx("rocket", 1.0, 0.04)
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
			_shred(tg.e, tg.e.mi.global_transform * tg.lp, "shotgun")
			_kill_enemy(tg.e, tg.e.mi.global_transform * tg.lp, false)
		for i in 5:
			var sp = p + Vector2(randf_range(-55, 55), randf_range(-40, 40))
			var sh = _pick(sp, (cards).filter(func(x): return x != wall))
			if not sh.is_empty():
				_impact(sh, true)
	# Mündungslicht der eigenen Waffe (rechts unten) erhellt kurz die Mauer
	_flash_light(cam.global_transform * Vector3(0.35, -0.3, -0.6), 3.5, Color(1.0, 0.72, 0.4), 3.0)
	var targets = (cards + enemies).filter(func(x): return x != wall)
	if nb.get("state", "off") == "stay":
		targets.append(nb_card)
	var hit = _pick(p, targets)
	if not hit.is_empty() and hit.card == nb_card:
		_nb_hit(hit.point)
		return
	# Gegner und Bonus-Kisten haben Vorrang vor der Kulisse: wer auf den Gegner zielt, trifft ihn, egal was davorsteht: steht eine Kiste knapp hinter dem Kistenstapel,
	# soll der Schuss nicht im Holz davor hängen bleiben
	var live = enemies.filter(func(x): return x.state != "fall" and x.state != "hide" and (x.kind == "box" or x.kind == "card"))
	var eh = _pick(p, live)
	if not eh.is_empty():
		hit = eh
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
		if c.kind == "card":
			_shred(c, hit.point, w)
		_kill_enemy(c, hit.point, hit.uv.y < 0.17 and not c.get("box", false))
	elif enemies.has(c) and c.state == "fall" and c.kind == "card":
		# auf den fallenden Aufsteller weiterschießen: noch mehr Löcher und Fetzen
		_impact(hit, false)
		_shred(c, hit.point, w)
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
	var cc: Vector3 = car_card.pv.global_position + Vector3(0, minf(0.6, car_card.h * 0.3), 0.15)
	if cam.is_position_behind(cc):
		return tp
	# Trefferzone wächst mit der Fahrzeugbreite (großer Pickup im Motel)
	var half = car_card.w * 0.5
	var sl = cam.unproject_position(cc - Vector3(half, 0, 0))
	var sr = cam.unproject_position(cc + Vector3(half, 0, 0))
	var sp = cam.unproject_position(cc)
	var reach = maxf(150.0, sl.distance_to(sr) * 0.5 + 40.0)
	var near_screen = absf(p.x - sp.x) < reach and absf(p.y - sp.y) < 170.0
	var near_world = Vector2(tp.x - cc.x, tp.z - cc.z).length() < maxf(3.5, half + 1.0)
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
	_bark(e, "nade", 1.0, 0.0, true)
	_sfx("throw", -2.0, 0.08)
	_sfx("warn", 2.0, 0.0)
	_show_msg("GRENADE!", "pop up and shoot it", 1.4)


func _launch(from: Vector3, to: Vector3, dur: float, apex: float, kind: String) -> void:
	_evt("launch " + kind)
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
func _explode(pos: Vector3, radius: float, hurts_player: bool, snd: String = "boom") -> void:
	_evt("explosion")
	var dcam = pos.distance_to(cam.global_position)
	var k = clampf(radius / 3.0, 0.5, 1.4) * (0.45 if dcam < 3.0 else 1.0)
	_fb_boom(pos, k)
	fx_k = clampf(dcam / 7.0, 0.22, 1.3)
	_sparks(pos, Vector3.UP, 30)
	_chunks(pos, Vector3.UP, 18, [Color(0.35, 0.3, 0.26), Color(0.6, 0.45, 0.3), Color(0.2, 0.18, 0.16)], 0.06, 1.0)
	_flash_light(pos + Vector3(0, 0.8, 0.5), 9.0, Color(1.0, 0.6, 0.25), 9.0, 0.55)
	_sfx(snd, 2.0 if dcam > 4.0 else 4.0, 0.06)
	shake = maxf(shake, clampf(1.5 - dcam / 14.0, 0.35, 1.3))
	if hurts_player:
		health -= 35.0 * _dk(0.7, 1.15)
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
			if e.kind == "card" and not e.get("box", false):
				_shred(e, ep, "boom")
			_kill_enemy(e, ep, false)
	if not car_dead and not car_card.is_empty():
		var cp: Vector3 = car_card.pv.global_position + Vector3(0, 0.7, 0)
		var dx = maxf(0.0, absf(pos.x - cp.x) - car_card.w * 0.35)
		if Vector3(dx, pos.y - cp.y, pos.z - cp.z).length() < radius + 0.9:
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
	_explode(cp, 3.2, false, "car_boom")
	_fb_boom(cp + Vector3(0, 0.6, 0), 1.6)
	score += 300
	_float_text(cp + Vector3(0, 1.4, 0), car_card.get("label", "CAR") + "  +300", true)
	# Pappauto hüpft hoch, landet schief und verkohlt als Wrack wieder auf der Straße
	car_card.mat.set_shader_parameter("dim", 0.22)
	var pv: Node3D = car_card.pv
	var base: Vector3 = car_card.base
	var tw = create_tween()
	tw.tween_property(pv, "position", base + Vector3(0.15, 1.5, -0.2), 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(pv, "rotation", Vector3(-0.35, 0.2, 0.28), 0.32)
	tw.tween_property(pv, "position", base + Vector3(0.25, -0.03, -0.3), 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(pv, "rotation", Vector3(-0.05, 0.03, 0.0), 0.3)
	tw.tween_callback(func(): _sfx("target_down", 3.0, 0.0))
	tw.tween_property(pv, "position", base + Vector3(0.25, 0.08, -0.3), 0.08)
	tw.tween_property(pv, "position", base + Vector3(0.25, -0.01, -0.3), 0.1)
	# Trümmerteile fliegen weg und bleiben liegen: Stoßstange, Reifen, Spiegel
	for pt in car_card.get("debris", []):
		var d = _card(pt[0], pt[1], base + Vector3(0, 0.6, 0), "metal")
		d.mat.set_shader_parameter("dim", 0.45)
		car_fx.append(d.pv)
		var end: Vector3 = base + pt[2]
		var mid: Vector3 = (base + end) * 0.5 + Vector3(0, 1.6 + randf() * 0.6, 0)
		var dt2 = create_tween()
		dt2.tween_property(d.pv, "position", mid, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		dt2.parallel().tween_property(d.pv, "rotation", Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3)), 0.28)
		dt2.tween_property(d.pv, "position", end, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		dt2.parallel().tween_property(d.pv, "rotation", pt[3], 0.3)
	car_burn_age = 0.0
	# Feuer und Rauch bleiben: laufen über _car_burn() aus echten Bildfolgen
	car_burn_t = 0.0
	car_smoke_t = 0.0
	car_light.global_position = base + Vector3(0.5, 0.9, 0.3)
	car_light.light_energy = 2.0


func _car_burn(dt: float) -> void:
	if not car_dead or car_card.is_empty():
		return
	# Flammen nur ein paar Sekunden und immer kleiner, danach nur noch Qualm, der langsam dünner wird
	car_burn_age += dt
	var fk = clampf(1.0 - car_burn_age / 7.0, 0.0, 1.0)
	var sk = clampf(1.0 - car_burn_age / 40.0, 0.0, 1.0)
	var base: Vector3 = car_card.base + Vector3(0.25, 0.0, -0.25)
	car_burn_t -= dt
	if fk > 0.0 and car_burn_t <= 0.0:
		car_burn_t = randf_range(0.04, 0.07) / maxf(fk, 0.25)
		var fp = base + Vector3(randf_range(-0.8, 0.8) * (0.4 + 0.6 * fk), randf_range(0.5, 0.95), randf_range(-0.1, 0.35))
		var sz = randf_range(3.0, 4.2) * (0.35 + 0.65 * fk)
		var mi = _fb_quad(["boom0", "boom1", "boom2"][randi() % 3], fp, sz)
		mi.set_instance_shader_parameter("em", 2.4)
		fbs.append({"n": mi, "t": 0.0, "dur": randf_range(0.4, 0.6), "g": randf_range(1.2, 1.9), "f0": 2.0, "f1": 8.5})
	car_smoke_t -= dt
	if sk > 0.0 and car_smoke_t <= 0.0:
		car_smoke_t = randf_range(0.28, 0.42) / maxf(sk, 0.2)
		var sp = base + Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.2, 0.1))
		var sm = _fb_quad("smoke5_dark" if car_burn_age < 12.0 else "smoke5", sp, randf_range(1.6, 2.4) * (0.45 + 0.55 * sk))
		sm.set_instance_shader_parameter("em", 0.0)
		fbs.append({"n": sm, "t": 0.0, "dur": randf_range(2.6, 3.4), "g": randf_range(0.8, 1.2), "drift": 0.25})
	if randf() < 0.5:
		car_light.light_energy = (1.6 + 0.9 * randf()) * fk


func _car_reset() -> void:
	if car_light != null:
		car_light.light_energy = 0.0
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
	var dark = key.ends_with("_dark")
	var tkey = key.trim_suffix("_dark")
	m.set_shader_parameter("tex", load("res://fx/%s.png" % tkey))
	m.set_shader_parameter("grid", 8.0 if key == "wisp8" else 5.0)
	m.set_shader_parameter("smk", Vector3(0.85, 0.78, 0.72) if key in ["wisp8", "smoke5"] else Vector3(1, 1, 1))
	if dark:
		m.set_shader_parameter("smk", Vector3(0.22, 0.19, 0.17))
	fb_mats[key] = m
	return m


func _fb_quad(key: String, pos: Vector3, size: float) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	if fb_mesh == null:
		fb_mesh = QuadMesh.new()
		fb_mesh.size = Vector2(1, 1)
	mi.mesh = fb_mesh
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
	_evt("fireball")
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
		var f0 = float(e.get("f0", 0.0))
		mi.set_instance_shader_parameter("fr", f0 + uu * (float(e.get("f1", 23.999)) - f0))
		if e.has("drift"):
			mi.global_position += Vector3(float(e.drift) * dt, 0, 0)
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
		var wp: Vector3 = sl.pos + Vector3(0, sl.get("eh", ENEMY_H) * 0.73, 0)
		var live = false
		for e in enemies:
			if e.slot == sl and e.state != "fall" and e.state != "hide" and is_instance_valid(e.mi):
				wp = e.mi.global_transform * Vector3(0, (1.0 - e.gun_v - 0.04) * e.h, 0)
				live = e.state == "aim" or (e.state == "appear" and e.t > 0.2)
		if cam.is_position_behind(wp) or sl.get("off", false):
			continue
		if not sl.busy and _partner_busy(sl):
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
	_evt("impact " + str(hit.card.kind))
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
			_sparks(out, n, 14)
			_dust(out, n, 10, Color(0.78, 0.64, 0.5), 0.45)
			_chunks(out, n, 13, [Color(0.6, 0.33, 0.22), Color(0.82, 0.74, 0.62), Color(0.45, 0.3, 0.22)], 0.035)
			_sfx("impact_brick", -3.0, 0.15)
		"metal":
			_sparks(out, n, 32)
			_dust(out, n, 4, Color(0.5, 0.45, 0.4), 0.28)
			_sfx("impact_metal", -4.0, 0.15)
		"wood":
			_chunks(out, n, 16, [Color(0.55, 0.38, 0.22), Color(0.72, 0.55, 0.35)], 0.045)
			_dust(out, n, 6, Color(0.62, 0.5, 0.36), 0.25)
			_sfx("impact_card", -2.0, 0.2)
		"leaf":
			_chunks(out, n, 12, [Color(0.35, 0.42, 0.15), Color(0.55, 0.55, 0.2), Color(0.42, 0.33, 0.12)], 0.05, 0.25)
			_sfx("impact_card", -10.0, 0.3)
		"card":
			_chunks(out, n, 16, [Color(0.78, 0.66, 0.5), Color(0.6, 0.48, 0.34)], 0.045)
			_dust(out, n, 5, Color(0.7, 0.6, 0.48), 0.28)
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
	var sz = snappedf(size, 0.005)
	var key = "%d_%.3f" % [mat.get_instance_id(), sz]
	if not mesh_cache.has(key):
		var q = QuadMesh.new()
		q.size = Vector2(sz, sz)
		q.material = mat
		mesh_cache[key] = q
	p.mesh = mesh_cache[key]
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


func _make_lights() -> void:
	for i in 8:
		var l = OmniLight3D.new()
		l.shadow_enabled = false
		l.omni_attenuation = 1.4
		l.light_energy = 0.0
		l.position = Vector3(0, -50, 0)
		add_child(l)
		light_pool.append({"l": l, "t": 0.0, "dur": 0.1, "e0": 0.0})
	mega_light = OmniLight3D.new()
	mega_light.light_color = Color(1.0, 0.78, 0.3)
	mega_light.omni_range = 2.6
	mega_light.light_energy = 0.0
	mega_light.position = Vector3(0, -50, 0)
	add_child(mega_light)
	car_light = OmniLight3D.new()
	car_light.light_color = Color(1.0, 0.55, 0.2)
	car_light.omni_range = 4.0
	car_light.light_energy = 0.0
	car_light.position = Vector3(0, -50, 0)
	add_child(car_light)


func _flash_light(pos: Vector3, rng: float, col: Color, energy: float, dur: float = 0.09) -> void:
	# das Licht, das am längsten frei ist, wird wiederverwendet
	var best = light_pool[0]
	for f in light_pool:
		if f.t >= f.dur:
			best = f
			break
		if f.t / f.dur > best.t / best.dur:
			best = f
	var l: OmniLight3D = best.l
	l.position = pos
	l.omni_range = rng
	l.light_color = col
	l.light_energy = energy
	best.t = 0.0
	best.dur = dur
	best.e0 = energy


func _lights_update(dt: float) -> void:
	for f in light_pool:
		if f.t < f.dur:
			f.t += dt
			f.l.light_energy = f.e0 * maxf(0.0, 1.0 - f.t / f.dur)
	# goldener Schein der Mega-Box
	var mb = {}
	for e in enemies:
		if e.get("mega", false) and e.state != "fall" and is_instance_valid(e.mi):
			mb = e
	if mb.is_empty():
		mega_light.light_energy = 0.0
	else:
		mega_light.global_position = mb.mi.global_transform * Vector3(0, mb.h * 0.5, 0.35)
		mega_light.light_energy = 1.5 + 2.5 * (0.5 + 0.5 * sin(mb.t * 9.0)) if mb.state == "aim" else 1.5


func _float_text(pos: Vector3, s: String, big: bool) -> void:
	_evt("text")
	if label_pool.is_empty():
		for i in 6:
			var nl = Label3D.new()
			nl.font = font
			nl.font_size = 60
			nl.outline_size = 14
			nl.outline_modulate = Color(0, 0, 0, 0.55)
			nl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			nl.no_depth_test = true
			nl.fixed_size = false
			nl.visible = false
			add_child(nl)
			label_pool.append({"l": nl, "tw": null})
	var e = label_pool[label_next]
	label_next = (label_next + 1) % label_pool.size()
	if e.tw != null and e.tw.is_valid():
		e.tw.kill()
	var l: Label3D = e.l
	l.text = s
	l.pixel_size = 0.0045 if not big else 0.0055
	l.modulate = Color(1.0, 0.9, 0.55) if big else Color(1, 1, 1)
	l.position = pos
	l.visible = true
	var tw = create_tween().set_parallel(true)
	tw.tween_property(l, "position", pos + Vector3(0, 0.9, 0), 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.chain().tween_callback(func(): l.visible = false)
	e.tw = tw


# ================================================================ Speichern
func _load_save() -> void:
	var c = ConfigFile.new()
	if c.load(SAVE_PATH) == OK:
		best = int(c.get_value("game", "best", 0))
		for sd in SND:
			set(sd.key, float(c.get_value("audio", sd.key, get(sd.key))))
		mode = str(c.get_value("game", "mode", mode))
		last_name = str(c.get_value("game", "name", ""))
		for m in MODES:
			hs[m] = c.get_value("hs", m, [])
		aim_sens = float(c.get_value("ctrl", "aim_sens", aim_sens))
		aim_accel = float(c.get_value("ctrl", "aim_accel", aim_accel))
		recenter = float(c.get_value("ctrl", "recenter", recenter))
		aim_assist = float(c.get_value("ctrl", "aim_assist", aim_assist))
		aim_mode = str(c.get_value("ctrl", "aim_mode", aim_mode))
		music_vol = float(c.get_value("ctrl", "music_vol", music_vol))
		thumb_n = c.get_value("ctrl", "thumb_n", thumb_n)
		fire_n = c.get_value("ctrl", "fire_n", fire_n)


func _save() -> void:
	if autotest:
		return
	var c = ConfigFile.new()
	c.set_value("game", "best", best)
	for sd in SND:
		c.set_value("audio", sd.key, get(sd.key))
	c.set_value("game", "mode", mode)
	c.set_value("game", "name", last_name)
	for m in MODES:
		c.set_value("hs", m, hs[m])
	c.set_value("ctrl", "aim_sens", aim_sens)
	c.set_value("ctrl", "aim_accel", aim_accel)
	c.set_value("ctrl", "recenter", recenter)
	c.set_value("ctrl", "aim_assist", aim_assist)
	c.set_value("ctrl", "aim_mode", aim_mode)
	c.set_value("ctrl", "music_vol", music_vol)
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
			forcing = true
			_spawn()
			forcing = false
			for o in slots:
				o.busy = false
			for e in enemies:
				e.slot.busy = true
			return enemies[-1]
	return {}


func _autotest(dt: float) -> void:
	at_t += dt
	var plan = OS.get_environment("AUTOTEST")
	if at_step == 0 and at_t > 0.6 and not early_snap:
		early_snap = true
		_snap("00_warmup")
	if at_step == 0 and at_t > 1.0:
		_snap("01_title_opening")
		at_step = 1
	elif at_step == 1 and at_t > 3.0:
		_snap("02_title")
		_press(_mode_btn_rect(0).get_center())
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
		for n in ["window0", "door", "car", "crates", "window4"]:
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
				round_goal = round_kills + 1
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
		var bx = enemies.filter(func(x): return x.get("box", false))[-1]
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
		car_burn_age = 20.0
		at_step = 138
	elif at_step == 138 and at_t > 18.0:
		_snap("17_car_smoke")
		print("after enemy nade health=", health, " round=", stage, " goal=", round_goal, " ammo=", ammo, "/", reserve)
		# Nachbar, Vögel, Zeitung
		health = 100
		for e in enemies:
			if e.state != "fall":
				e.state = "hide"
				e.t = 0.0
		spawn_t = 999.0
		var dsl = _door_slot()
		dsl.busy = false
		_nb_start()
		bird_t = 0.0
		paper.next = 0.0
		paper.pos = Vector3(-4.0, 0.012, -10.0)
		weapon = "pistol"
		ammo = 8
		at_step = 140
	elif at_step == 140 and at_t > 18.9:
		cover = false
		_snap("17n_neighbor")
		var bp: Vector3 = nb_card.mi.global_transform * Vector3((0.3 - 0.5) * nb_card.w, (1.0 - 0.07) * nb_card.h, 0.0)
		aim = cam.unproject_position(bp)
		var sc0 = score
		_shoot(aim)
		print("NEIGHBOR shot=", nb.shot, " score ", sc0, " -> ", score)
		at_step = 141
	elif at_step == 141 and at_t > 19.25:
		_snap("17o_beer")
		at_step = 142
	elif at_step == 142 and at_t > 20.4:
		_snap("17q_life")
		print("PAPER pos=", paper.pos, " air=", paper.air, " scr=", cam.unproject_position(paper.pos), " birds=", birds.size())
		at_step = 143
	elif at_step == 143 and at_t > 21.6:
		_snap("17r_paper")
		print("PAPER pos=", paper.pos, " air=", paper.air, " vis=", paper.n.is_visible_in_tree(), " scr=", cam.unproject_position(paper.pos))
		at_step = 144
	elif at_step == 144 and at_t > 24.3:
		print("NEIGHBOR state=", nb.state, " door=", nb_door.rotation_degrees.y)
		_snap("17p_door_shut")
		at_step = 145
	elif at_step == 145 and at_t > 25.0:
		# Szenenwechsel in den Hafen
		health = 100
		stage = HARBOR_FROM - 1
		round_kills = round_goal
		_round_clear()
		at_step = 150
	elif at_step == 150 and at_t > 25.7:
		_snap("18_harbor_fold")
		at_step = 151
	elif at_step == 151 and at_t > 27.0:
		_snap("19_harbor_unfold")
		at_step = 152
	elif at_step == 152 and at_t > 30.6:
		print("HARBOR scene=", scene, " stage=", stage, " ammo=", ammo, "/", reserve, " slots=", slots.size())
		spawn_t = 999.0
		cover = false
		aim_idx = 99
		for n in ["door_bl", "door_tl", "door_tr", "roof", "prop", "crates", "door_br"]:
			var e = _force_enemy(n)
			e.aim = 99.0
		at_step = 153
	elif at_step == 153 and at_t > 31.6:
		_snap("20_harbor")
		aim = _vs() * Vector2(0.85, 0.6)
		at_step = 158
	elif at_step == 158 and at_t > 31.9:
		_snap("20r_aim_right")
		aim = _vs() * Vector2(0.15, 0.3)
		at_step = 159
	elif at_step == 159 and at_t > 32.2:
		_snap("20l_aim_left")
		aim = _vs() * Vector2(0.5, 0.45)
		weapon = "shotgun"
		wpn_ammo = 3
		for e in enemies:
			if e.slot.name == "door_bl" and not e.get("box", false):
				_shoot(cam.unproject_position(e.mi.global_transform * Vector3(0, e.h * 0.6, 0)))
		at_step = 154
	elif at_step == 154 and at_t > 32.45:
		_snap("20b_shotgun")
		at_step = 157
	elif at_step == 157 and at_t > 33.0:
		_snap("21_shreds")
		cover = false
		for e in enemies:
			if not e.get("box", false) and e.state != "fall":
				e.aim = 99.0
		_car_explode()
		at_step = 155
	elif at_step == 155 and at_t > 33.6:
		_snap("22_forklift_boom")
		at_step = 156
	elif at_step == 156 and at_t > 35.4:
		_snap("23_forklift_wreck")
		life_t = 14.0
		weapon = "pistol"
		cover = false
		ammo = 1
		reserve = 5
		at_step = 160
	elif at_step == 160 and at_t > 35.8:
		_snap("24_reload_yellow")
		ammo = 0
		at_step = 161
	elif at_step == 161 and at_t > 36.1:
		_snap("25_reload_red")
		cover = true
		at_step = 162
	elif at_step == 162 and at_t > 36.25:
		cover = false
		at_step = 163
	elif at_step == 163 and at_t > 36.45:
		_snap("26_reload_ring")
		print("RELOAD t=", reload_t, " ammo=", ammo, "/", reserve)
		at_step = 164
	elif at_step == 164 and at_t > 37.0:
		print("RELOAD done ammo=", ammo, "/", reserve)
		# dritte Map: Motel
		for e in enemies:
			if e.state != "fall":
				e.state = "hide"
				e.t = 0.0
		health = 100
		stage = 2 * ROUNDS_PER_MAP
		round_kills = round_goal
		_round_clear()
		at_step = 170
	elif at_step == 170 and at_t > 39.4:
		_snap("30_motel_unfold")
		at_step = 171
	elif at_step == 171 and at_t > 43.0:
		var vv = 0
		for sd in shadows:
			if sd.mi.visible: vv += 1
		print("SHADOWS ", shadows.size(), " vis=", vv, " first=", shadows[0].mi.global_position if shadows.size() > 0 else null, " k=", shadows[0].mi.get_instance_shader_parameter("k") if shadows.size() > 0 else 0)
		print("MOTEL scene=", scene, " stage=", stage, " slots=", slots.size(), " goal=", round_goal)
		spawn_t = 999.0
		cover = false
		for n in ["up1", "up2", "door", "win", "crates"]:
			var e = _force_enemy(n)
			e.aim = 99.0
		for sl in slots:
			if sl.name == "car":
				sl.busy = true
				_spawn_box(sl, false)
		at_step = 172
	elif at_step == 172 and at_t > 44.2:
		_snap("31_motel")
		cover = true
		at_step = 173
	elif at_step == 173 and at_t > 44.8:
		_snap("31b_motel_cover")
		cover = false
		grenades = 1
		# Granate auf die hintere Hälfte des Pickups werfen, nicht genau auf die Mitte
		aim = cam.unproject_position(car_card.pv.global_position + Vector3(car_card.w * 0.32, 0.9, 0))
		_throw_grenade()
		at_step = 174
	elif at_step == 174 and at_t > 46.3:
		print("PICKUP dead=", car_dead)
		_snap("32_pickup_boom")
		weapon = "pistol"
		ammo = 0
		reserve = 0
		grenades = 0
		at_step = 13
	elif at_step == 13 and at_t > 47.5:
		_snap("09_game_over")
		at_step = 14
	elif at_step == 14 and at_t > 48.9:
		_snap("27_name_entry")
		name_edit.text = "JOHN"
		_name_done()
		at_step = 15
	elif at_step == 15 and at_t > 49.7:
		_snap("28_highscores")
		_press(_vs() * 0.5)
		at_step = 16
	elif at_step == 16 and at_t > 50.9:
		_snap("29_menu")
		_press(_title_btn_rect(0).get_center())
		at_step = 17
	elif at_step == 17 and at_t > 51.4:
		_snap("33_sound")
		# senkrecht wischen über einem Regler: darf nur scrollen
		var t = _snd_track(2)
		var v0 = snd_bright
		_press(t.get_center(), 5)
		var ev = InputEventScreenDrag.new()
		ev.index = 5
		ev.position = t.get_center() + Vector2(6, -60)
		_input(ev)
		ev.position = t.get_center() + Vector2(10, -200)
		_input(ev)
		var up = InputEventScreenTouch.new()
		up.index = 5
		up.position = ev.position
		up.pressed = false
		_input(up)
		print("SND scroll=", snd_scroll, " bright ", v0, " -> ", snd_bright)
		# waagerecht ziehen: Regler bewegt sich
		var t2 = _snd_track(4)
		var m0 = snd_muffle
		_press(t2.get_center(), 6)
		var ev2 = InputEventScreenDrag.new()
		ev2.index = 6
		ev2.position = t2.get_center() + Vector2(-90, 4)
		_input(ev2)
		up.index = 6
		up.position = ev2.position
		_input(up)
		print("SND muffle ", m0, " -> ", snd_muffle)
		at_step = 18
	elif at_step == 18 and at_t > 51.8:
		_snap("34_sound_scrolled")
		get_tree().quit()


# ---------------------------------------------------------------------------
# Leben in den Szenen: Baum, Gardine, Vögel, Zeitung, Nachbar (Straße) – Kran und Lichter (Hafen)

# Karte an einen anderen Knoten hängen (lokale Position)
func _adopt(parent: Node3D, child: Node3D, local: Vector3) -> void:
	child.get_parent().remove_child(child)
	parent.add_child(child)
	child.position = local


func _subdivide(c: Dictionary, sx: int, sy: int) -> void:
	var q: QuadMesh = c.mi.mesh
	q.subdivide_width = sx
	q.subdivide_depth = sy


func _make_street_life(fac: Dictionary, fac_h: float, tree: Dictionary) -> Node3D:
	var deco = Node3D.new()
	add_child(deco)
	# Baum wiegt sich leicht im Wind
	_subdivide(tree, 8, 14)
	tree.mat.set_shader_parameter("sway", 0.11)
	tree.mat.set_shader_parameter("sway_speed", 1.0)
	# vergilbte Gardine im rechten oberen Fenster, hinter den Gegnern, weht hin und her
	var hh = HOLES[3]
	var ww = (hh[1] - hh[0]) * FAC_W
	var wh = (hh[3] - hh[2]) * fac_h
	var cu = _card("curtain.png", ww * 0.5, Vector3.ZERO, "room", wh * 0.92)
	_adopt(fac.pv, cu.pv, Vector3((hh[0] - 0.5) * FAC_W + ww * 0.27, (1.0 - hh[3]) * fac_h + wh * 0.06, -0.55))
	_subdivide(cu, 6, 12)
	cu.mat.set_shader_parameter("sway", 0.09)
	cu.mat.set_shader_parameter("hang", 1.0)
	cu.mat.set_shader_parameter("sway_speed", 1.3)
	cu.mat.set_shader_parameter("dim", 0.62)
	# Haustür: hängt am linken Rand der Türöffnung, steht normalerweise ganz offen an der Wand
	var dh = HOLES[6]
	var dw = (dh[1] - dh[0]) * FAC_W
	var dhh = (dh[3] - dh[2]) * fac_h
	var door = _card("door_leaf.png", dw, Vector3.ZERO, "wood", dhh)
	door.mat.set_shader_parameter("back_tex", true)
	nb_door = Node3D.new()
	fac.pv.add_child(nb_door)
	nb_door.position = Vector3((dh[0] - 0.5) * FAC_W, (1.0 - dh[3]) * fac_h, 0.04)
	_adopt(nb_door, door.pv, Vector3(dw * 0.5, 0, 0))
	nb_door.rotation.y = 0.0
	# der Nachbar (Pappaufsteller wie die Gegner)
	# fast so hoch wie die Tür, steht auf der Schwelle vor der Wand (damit Arm und Flasche nicht im Rahmen verschwinden)
	var npos = Vector3(((dh[0] + dh[1]) * 0.5 - 0.5) * FAC_W + 0.08, FAC_Y + (1.0 - dh[3]) * fac_h, FAC_Z + 0.14)
	nb_card = _card("neighbor0.png", 2.6 * 720.0 / 1166.0, npos, "npc", 2.6)
	nb_card.pv.visible = false
	nb = {"state": "off", "t": 0.0, "at": 999.0, "shot": false, "stay": 0.0}
	for n in ["nb_yell0", "nb_yell1", "nb_yell2", "nb_beer0", "nb_beer1", "nb_beer2"]:
		nb_snd[n] = load("res://sfx/voice/" + n + ".ogg")
	for n in ["door_slam", "door_open", "bottle"]:
		sounds[n] = load("res://sfx/" + n + ".ogg")
	# Vögel (Schwarm zieht ab und zu über die Dächer)
	var bs = Shader.new()
	bs.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
instance uniform float frame = 0.0;
void fragment() {
	vec4 c = texture(tex, vec2((UV.x + frame) * 0.25, UV.y));
	ALBEDO = c.rgb;
	ALPHA = c.a * 0.9;
}
"""
	bird_mat = ShaderMaterial.new()
	bird_mat.shader = bs
	bird_mat.set_shader_parameter("tex", _tex("birds.png"))
	# Zeitung: Blatt mit vielen Feldern, wird im Shader gebogen und flattert
	var ps = Shader.new()
	ps.code = """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_lambert, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float curl = 0.0;
uniform float roll = 0.0;
uniform float flap = 0.0;
void vertex() {
	vec2 q = VERTEX.xz;
	float r = max(0.0, q.x + q.y + 0.1);
	VERTEX.y += curl * q.x * q.x * 3.0 + roll * r * r * 2.2;
	VERTEX.y += flap * sin(TIME * 17.0 + q.x * 11.0 + q.y * 7.0) * 0.035 * (abs(q.x) + abs(q.y) + 0.1);
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * (FRONT_FACING ? 0.95 : 0.7);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
"""
	var pm = ShaderMaterial.new()
	pm.shader = ps
	pm.set_shader_parameter("tex", _tex("paper.png"))
	var pl = PlaneMesh.new()
	pl.size = Vector2(0.46, 0.56)
	pl.subdivide_width = 10
	pl.subdivide_depth = 12
	var pmi = MeshInstance3D.new()
	pmi.mesh = pl
	pmi.material_override = pm
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pn = Node3D.new()
	deco.add_child(pn)
	pn.add_child(pmi)
	# unsichtbarer Leuchtpunkt unter der Straße, damit der Licht-Shader schon vor dem Hafen fertig ist
	_glow(deco, _soft_tex(16, 1.4), Vector3(0, -3.4, -7.0), 0.2, Color(0, 0, 0), "flick")
	var wq = MeshInstance3D.new()
	var wqm = QuadMesh.new()
	wqm.size = Vector2(0.2, 0.2)
	wq.mesh = wqm
	wq.material_override = _shred_mat(_tex("enemy0.png"))
	deco.add_child(wq)
	wq.position = Vector3(0.6, -3.4, -7.0)
	paper = {"n": pn, "mat": pm, "pos": Vector3(-3.2, 0.012, -10.3), "vel": Vector3.ZERO, "rot": Vector3(0, 0.4, 0), "av": Vector3.ZERO,
		"gust": 0.0, "next": 5.0, "curl": 0.12, "roll": 0.0, "flap": 0.0, "air": false}
	pn.position = paper.pos
	pn.rotation = paper.rot
	return deco


func _make_harbor_life(sky_pv: Node3D) -> Node3D:
	var deco = Node3D.new()
	add_child(deco)
	# Kran links hinten, die Laufkatze fährt mit einem Container am Ausleger hin und her
	var cw = 55.0
	var cx = 0.0
	var cy = 9.1     # Fuß steht hinter dem Containerstapel
	var cz = -60.0
	var crane = _card("h_crane.png", cw, Vector3(cx, cy, cz), "sky")
	_adopt(deco, crane.pv, Vector3(cx, cy, cz))
	var chh: float = crane.h
	var boom_y = cy + (1.0 - 0.4236) * chh
	crane_load = Node3D.new()
	deco.add_child(crane_load)
	crane_load.position = Vector3(cx - 0.3 * cw, boom_y + 0.6, cz + 0.15)
	var ld = _card("h_load.png", 6.5, Vector3.ZERO, "sky")
	_adopt(crane_load, ld.pv, Vector3(0, -ld.h, 0))
	crane_x = Vector2(cx - 0.45 * cw, cx - 0.12 * cw)
	var gl = _soft_tex(64, 1.4)
	# rote Warnlichter (blinken) und Lampen unter dem Ausleger (flackern)
	for uv in [Vector2(0.623, 0.007), Vector2(0.6723, 0.007), Vector2(0.033, 0.325), Vector2(0.9764, 0.331)]:
		_glow(deco, gl, Vector3(cx + (uv.x - 0.5) * cw, cy + (1.0 - uv.y) * chh, cz + 0.3), 2.2, Color(1.0, 0.12, 0.08), "blink")
	for u in [0.1861, 0.3264, 0.5338, 0.6679]:
		_glow(deco, gl, Vector3(cx + (u - 0.5) * cw, cy + (1.0 - 0.411) * chh, cz + 0.3), 2.6, Color(1.0, 0.72, 0.38), "flick")
	# Lampen im Hintergrundbild
	for uv in [Vector2(0.0757, 0.3319), Vector2(0.1323, 0.486), Vector2(0.2398, 0.5505), Vector2(0.2957, 0.3806), Vector2(0.4603, 0.4269),
			Vector2(0.4034, 0.5974), Vector2(0.6928, 0.5981), Vector2(0.7568, 0.5883), Vector2(0.042, 0.5018), Vector2(0.6023, 0.6261)]:
		_glow(deco, gl, Vector3((uv.x - 0.5) * 220.0, -28.6 + (1.0 - uv.y) * 94.27, -74.6), 4.0, Color(1.0, 0.75, 0.42), "flick")
	for uv in [Vector2(0.5822, 0.42), Vector2(0.7965, 0.5024), Vector2(0.0799, 0.5901)]:
		_glow(deco, gl, Vector3((uv.x - 0.5) * 220.0, -28.6 + (1.0 - uv.y) * 94.27, -74.6), 5.5, Color(0.8, 0.9, 1.0), "flick")
	for uv in [Vector2(0.2294, 0.1437), Vector2(0.4074, 0.204)]:
		_glow(deco, gl, Vector3((uv.x - 0.5) * 220.0, -28.6 + (1.0 - uv.y) * 94.27, -74.6), 3.0, Color(1.0, 0.1, 0.06), "blink")
	# Flutlichtmast rechts: Lampenkranz oben
	for u in [0.22, 0.5, 0.78]:
		_glow(deco, gl, Vector3(8.4 + (u - 0.5) * 1.9, -0.05 + 7.25, -11.5), 1.1, Color(1.0, 0.8, 0.5), "flick")
	_harbor_atmo(deco)
	return deco


var glow_shader: Shader
func _glow(parent: Node3D, tex: Texture2D, pos: Vector3, size: float, col: Color, mode: String) -> void:
	if glow_shader == null:
		glow_shader = Shader.new()
		glow_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : filter_linear_mipmap;
uniform vec4 col : source_color = vec4(1.0);
instance uniform float k = 1.0;
void fragment() {
	float a = texture(tex, UV).a;
	ALBEDO = col.rgb;
	ALPHA = a * k * col.a;
}
"""
	var m = ShaderMaterial.new()
	m.shader = glow_shader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("col", Color(col.r, col.g, col.b, 0.85))
	var mi = MeshInstance3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	glows.append({"mi": mi, "mode": mode, "k": 1.0, "t": randf() * 3.0, "dip": 0.0, "ph": randf() * TAU})


func _life_update(dt: float) -> void:
	life_t += dt
	if scene == "harbor":
		_harbor_update(dt)
	elif scene == "motel":
		_glows_update(dt)
		_motel_update(dt)
	else:
		_birds_update(dt)
		_paper_update(dt)
	_nb_update(dt)
	_door_update(dt)


func _harbor_update(dt: float) -> void:
	_atmo_update(dt)
	_glows_update(dt)
	_crane_update(dt)


func _glows_update(dt: float) -> void:
	# Lampen: meist ruhig, ab und zu ein kurzes Flackern; Warnlichter blinken langsam
	for g in glows:
		var k = 1.0
		if g.mode == "blink":
			k = 1.0 if fmod(life_t + g.ph, 1.8) < 0.7 else 0.08
		elif g.mode == "beacon":
			k = 0.25 + 0.75 * pow(maxf(0.0, sin(life_t * 4.2 + g.ph)), 3.0)
		elif g.mode == "steady":
			k = 0.9 + sin(life_t * 1.3 + g.ph) * 0.05
		else:
			# sanftes Atmen, ab und zu ein kleines Zucken; jede fünfte Lampe ist eine Wackelkandidatin
			var faulty = int(g.ph * 10.0) % 5 == 0
			g.t -= dt
			if g.t <= 0.0:
				if g.dip > 0.0:
					g.dip = 0.0
					g.t = randf_range(2.0, 9.0) if (not faulty or randf() < 0.6) else randf_range(0.05, 0.15)
				else:
					g.dip = randf_range(0.4, 0.75) if faulty else randf_range(0.1, 0.25)
					g.t = randf_range(0.05, 0.14) if faulty else randf_range(0.15, 0.4)
			k = 1.0 - g.dip + sin(life_t * 1.7 + g.ph) * 0.06 + sin(life_t * 7.0 + g.ph * 3.0) * 0.02
		g.k = lerpf(g.k, k, 1.0 - exp(-dt * (30.0 if g.mode == "blink" else 12.0)))
		g.mi.set_instance_shader_parameter("k", g.k)


func _crane_update(dt: float) -> void:
	# Laufkatze: fährt langsam hin und her, hält an den Enden, der Container pendelt nach
	if crane_load != null:
		var cyc = fmod(life_t, 44.0)
		var u: float
		if cyc < 16.0:
			u = smoothstep(0.0, 16.0, cyc)
		elif cyc < 22.0:
			u = 1.0
		elif cyc < 38.0:
			u = 1.0 - smoothstep(22.0, 38.0, cyc)
		else:
			u = 0.0
		var nx = lerpf(crane_x.x, crane_x.y, u)
		var v = (nx - crane_load.position.x) / maxf(dt, 0.001)
		crane_load.position.x = nx
		crane_load.rotation.z = lerpf(crane_load.rotation.z, clampf(-v * 0.018, -0.06, 0.06) + sin(life_t * 1.1) * 0.012, 1.0 - exp(-dt * 1.5))


func _birds_update(dt: float) -> void:
	bird_t -= dt
	if bird_t <= 0.0 and birds.is_empty() and scenes.has("street"):
		bird_t = randf_range(16.0, 30.0)
		var dir = 1.0 if randf() < 0.5 else -1.0
		var n = randi_range(4, 7)
		var y0 = randf_range(10.0, 11.4)
		var spd = randf_range(8.0, 10.0)
		for i in n:
			var mi = MeshInstance3D.new()
			var q = QuadMesh.new()
			q.size = Vector2(1.0, 1.06)
			mi.mesh = q
			mi.material_override = bird_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			scenes.street.deco.add_child(mi)
			mi.scale = Vector3(dir, 1, 1)
			var b = {"mi": mi, "x": -30.0 * dir - dir * randf_range(0.0, 5.0), "y": y0 + randf_range(-0.7, 0.7), "z": -21.0 + randf_range(-1.5, 1.5),
				"spd": spd * randf_range(0.92, 1.08), "dir": dir, "ph": randf() * 4.0, "glide": 0.0}
			birds.append(b)
	for i in range(birds.size() - 1, -1, -1):
		var b = birds[i]
		b.x += b.dir * b.spd * dt
		b.ph += dt * 9.0
		var fr: float
		if b.glide > 0.0:
			b.glide -= dt
			fr = 3.0
		else:
			fr = [0.0, 1.0, 2.0, 1.0][int(b.ph) % 4]
			if randf() < dt * 0.25:
				b.glide = randf_range(0.5, 1.1)
		b.mi.position = Vector3(b.x, b.y + sin(b.ph * 0.35) * 0.12, b.z)
		b.mi.set_instance_shader_parameter("frame", fr)
		if absf(b.x) > 34.0:
			b.mi.queue_free()
			birds.remove_at(i)


func _paper_update(dt: float) -> void:
	if paper.is_empty():
		return
	var pp = paper
	pp.next -= dt
	if pp.next <= 0.0 and pp.gust <= 0.0:
		pp.gust = randf_range(2.2, 4.2)
		pp.next = randf_range(7.0, 15.0)
		pp.air = true
		pp.vel.y = randf_range(1.2, 1.8)
		pp.av = Vector3(randf_range(-7, 7), randf_range(-2, 2), randf_range(-6, 6))
	if pp.air:
		var wind = 0.0
		if pp.gust > 0.0:
			pp.gust -= dt
			wind = 3.4
			# Auftrieb in kleinen Böen, das Blatt springt und überschlägt sich
			if randf() < dt * 2.2 and pp.pos.y < 0.9:
				pp.vel.y += randf_range(0.6, 1.4)
				pp.av += Vector3(randf_range(-5, 5), randf_range(-2, 2), randf_range(-5, 5))
		pp.vel.x = lerpf(pp.vel.x, wind, 1.0 - exp(-dt * 1.6))
		pp.vel.z = lerpf(pp.vel.z, sin(life_t * 0.7) * 0.4, 1.0 - exp(-dt))
		pp.vel.y -= 4.2 * dt
		pp.vel.y = maxf(pp.vel.y, -0.9)
		pp.pos += pp.vel * dt
		pp.pos.z = clampf(pp.pos.z, -11.4, -9.4)
		pp.rot += pp.av * dt
		pp.av = pp.av.lerp(Vector3.ZERO, 1.0 - exp(-dt * 0.8))
		pp.curl = lerpf(pp.curl, sin(life_t * 3.1) * 0.45, 1.0 - exp(-dt * 5.0))
		pp.roll = lerpf(pp.roll, 0.3 + sin(life_t * 2.3) * 0.25, 1.0 - exp(-dt * 4.0))
		pp.flap = lerpf(pp.flap, 1.0, 1.0 - exp(-dt * 6.0))
		if pp.pos.y <= 0.012 and pp.vel.y < 0.0:
			if pp.gust > 0.0:
				pp.vel.y = randf_range(0.6, 1.4)   # schlägt kurz auf und wird weitergetrieben
				pp.pos.y = 0.012
			else:
				pp.pos.y = 0.012
				pp.air = false
				pp.vel = Vector3.ZERO
	else:
		# liegt: richtet sich flach aus (mit der Vorder- oder Rückseite nach oben), zuckt ein bisschen
		pp.rot.x = lerpf(pp.rot.x, roundf(pp.rot.x / PI) * PI, 1.0 - exp(-dt * 8.0))
		pp.rot.z = lerpf(pp.rot.z, roundf(pp.rot.z / PI) * PI, 1.0 - exp(-dt * 8.0))
		pp.curl = lerpf(pp.curl, 0.12, 1.0 - exp(-dt * 3.0))
		pp.roll = lerpf(pp.roll, 0.1 + 0.08 * sin(life_t * 1.3), 1.0 - exp(-dt * 3.0))
		pp.flap = lerpf(pp.flap, 0.12, 1.0 - exp(-dt * 3.0))
	if pp.pos.x > 10.5:
		pp.pos = Vector3(-10.5, 0.012, randf_range(-10.8, -9.8))
		pp.vel = Vector3.ZERO
		pp.air = false
		pp.gust = 0.0
	pp.n.position = pp.pos
	pp.n.rotation = pp.rot
	pp.mat.set_shader_parameter("curl", pp.curl)
	pp.mat.set_shader_parameter("roll", pp.roll)
	pp.mat.set_shader_parameter("flap", pp.flap)


# --- Nachbar: reißt mitten in der Schießerei die Tür auf und meckert
func _nb_plan() -> void:
	if nb.is_empty():
		return
	nb.at = randf_range(9.0, 22.0) if (stage <= 2 or randf() < 0.65) else 999.0
	nb.t = 0.0


func _door_slot() -> Dictionary:
	for sl in slots:
		if sl.name == "door":
			return sl
	return {}


func _nb_start() -> void:
	var sl = _door_slot()
	if sl.is_empty():
		return
	sl.busy = true
	_evt("neighbor")
	nb.state = "opening"
	nb.t = 0.0
	nb.shot = false
	nb_card.mat.set_shader_parameter("tex", _tex("neighbor0.png"))
	nb_card.img = img_cache.get("neighbor0.png")
	_door_swing(true, 0.3)


func _nb_appear() -> void:
	nb.state = "up"
	nb.t = 0.0
	nb_card.pv.visible = true
	nb_card.pv.rotation.x = -PI * 0.5
	var tw = create_tween()
	tw.tween_property(nb_card.pv, "rotation:x", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sfx("target_up", -4.0, 0.1)
	var line = "nb_yell%d" % (randi() % 3)
	nb.stay = nb_snd[line].get_length() + 0.9
	get_tree().create_timer(0.3).timeout.connect(func(): _nb_say(line))


# Haustür auf- oder zuschwingen (nach außen, liegt offen flach an der Wand)
func _door_swing(open: bool, dur: float) -> void:
	door_open = open
	door_t = 0.0
	var tw = create_tween()
	tw.tween_property(nb_door, "rotation:y", deg_to_rad(-163.0) if open else 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	if open:
		_sfx("door_open", -9.0, 0.08)


# ohne Nachbar: Tür geht auf, wenn ein Gegner in der Tür auftaucht, und wieder zu, wenn er weg ist
func _door_update(dt: float) -> void:
	if nb_door == null or scene != "street" or nb.get("state", "off") != "off":
		return
	var sl = _door_slot()
	if sl.is_empty():
		return
	door_t += dt
	if sl.busy and not door_open:
		_door_swing(true, 0.28)
	elif not sl.busy and door_open and door_t > 0.6:
		_door_swing(false, 0.32)
		get_tree().create_timer(0.3).timeout.connect(func(): _sfx("door_slam", -14.0, 0.1))


func _nb_say(line: String) -> void:
	if not nb_card.pv.visible:
		return
	_far_voice(nb_snd[line], nb_card.pv.global_position + Vector3(0, 1.6, 0.3), 1.0, 1.0)


func _nb_hit(pt: Vector3) -> void:
	if nb.shot:
		return
	nb.shot = true
	_evt("neighbor beer")
	# Flasche zerspringt: Glassplitter, Bierspritzer, er starrt auf seine leere Hand
	var bp: Vector3 = nb_card.mi.global_transform * Vector3((0.3 - 0.5) * nb_card.w, (1.0 - 0.07) * nb_card.h, 0.05)
	fx_k = 1.0
	_sparks(bp, Vector3(0, 0.3, 1).normalized(), 10)
	_chunks(bp, Vector3(0, 0.4, 1).normalized(), 14, [Color(0.35, 0.2, 0.08), Color(0.55, 0.36, 0.15), Color(0.85, 0.8, 0.7)], 0.03)
	_dust(bp, Vector3(0, 0.2, 1).normalized(), 8, Color(0.85, 0.62, 0.2), 0.3)
	var sp = AudioStreamPlayer3D.new()
	sp.stream = sounds["bottle"]
	sp.unit_size = 16.0
	sp.volume_db = 3.0
	add_child(sp)
	sp.global_position = bp
	sp.finished.connect(sp.queue_free)
	sp.play()
	nb_card.mat.set_shader_parameter("tex", _tex("neighbor1.png"))
	nb_card.img = img_cache.get("neighbor1.png", nb_card.img)
	score = maxi(0, score - 100)
	_float_text(bp + Vector3(0.2, 0.35, 0.9), "MY BEER!  -100", true)
	var line = "nb_beer%d" % (randi() % 3)
	nb.stay = nb.t + 1.5   # schimpft noch kurz und verschwindet dann (der Spruch läuft weiter)
	get_tree().create_timer(0.45).timeout.connect(func(): _nb_say(line))


func _nb_update(dt: float) -> void:
	if nb.is_empty():
		return
	if nb.state == "off":
		if state == "play" and scene == "street" and break_t <= 0.0 and not panel_open:
			nb.t += dt
			if nb.t >= nb.at:
				nb.at = 999.0
				var sl = _door_slot()
				if not sl.is_empty() and not sl.busy:
					_nb_start()
				else:
					nb.at = nb.t + 2.5   # Tür gerade besetzt: gleich nochmal versuchen
		return
	nb.t += dt
	match nb.state:
		"opening":
			if nb.t > 0.3:
				_nb_appear()
		"up":
			if nb.t > 0.35:
				nb.state = "stay"
		"stay":
			if nb.t > nb.stay:
				nb.state = "down"
				nb.t = 0.0
				var tw = create_tween()
				tw.tween_property(nb_card.pv, "rotation:x", -PI * 0.5, 0.22).set_ease(Tween.EASE_IN)
		"down":
			if nb.t > 0.25:
				nb_card.pv.visible = false
				nb.state = "slam"
				nb.t = 0.0
				door_open = false
				var tw = create_tween()
				tw.tween_property(nb_door, "rotation:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"slam":
			if nb.t > 0.2:
				nb.state = "closed"
				nb.t = 0.0
				var sp = AudioStreamPlayer3D.new()
				sp.stream = sounds["door_slam"]
				sp.unit_size = 18.0
				sp.volume_db = 4.0
				add_child(sp)
				sp.global_position = nb_door.global_position + Vector3(0.7, 1.5, 0.2)
				sp.finished.connect(sp.queue_free)
				sp.play()
				shake = maxf(shake, 0.18)
				fx_k = 1.0
				_dust(nb_door.global_position + Vector3(0.7, 0.1, 0.15), Vector3(0, 0.3, 1).normalized(), 8, Color(0.7, 0.6, 0.5), 0.4)
		"closed":
			if nb.t > 1.2:
				nb.state = "off"
				nb.t = 0.0
				door_t = 0.0
				var sl = _door_slot()
				if not sl.is_empty():
					sl.busy = false


func _nb_reset() -> void:
	if nb.is_empty():
		return
	nb.state = "off"
	nb.t = 0.0
	nb_card.pv.visible = false
	nb_door.rotation.y = 0.0
	door_open = false
	if scenes.has("street"):
		for sl in scenes.street.slots:
			if sl.name == "door":
				sl.busy = false


# ---------------------------------------------------------------------------
# Pappe zerfetzen: Löcher im Aufsteller (Shader) und Fetzen aus dem Gegnerbild, die wegfliegen

func _shred_mat(tex: Texture2D) -> ShaderMaterial:
	var key = tex.get_instance_id()
	if shred_mats.has(key):
		return shred_mats[key]
	if shred_shader == null:
		shred_shader = Shader.new()
		shred_shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_lambert, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float dim = 1.0;
instance uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
instance uniform float seed = 0.0;
void fragment() {
	vec2 d = UV - 0.5;
	float ang = atan(d.y, d.x);
	float r = 0.4 + 0.08 * sin(ang * 5.0 + seed * 6.0) + 0.05 * sin(ang * 9.0 + seed * 2.0) + 0.03 * sin(ang * 17.0 + seed);
	vec4 c = texture(tex, region.xy + UV * region.zw);
	float L = length(d);
	vec3 col = FRONT_FACING ? c.rgb : vec3(0.56, 0.44, 0.32);
	col = mix(col, vec3(0.7, 0.58, 0.42), smoothstep(r - 0.07, r, L) * 0.85);
	ALBEDO = col * dim;
	ALPHA = (FRONT_FACING ? c.a : max(c.a, 0.0)) * step(L, r);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
"""
	var m = ShaderMaterial.new()
	m.shader = shred_shader
	m.set_shader_parameter("tex", tex)
	shred_mats[key] = m
	return m


func _shred(c: Dictionary, point: Vector3, power: String) -> void:
	if not is_instance_valid(c.get("mi")):
		return
	var tex: Texture2D = c.mat.get_shader_parameter("tex")
	var lp: Vector3 = c.mi.global_transform.affine_inverse() * point
	var u = clampf(lp.x / c.w + 0.5, 0.0, 1.0)
	var v = clampf(1.0 - lp.y / c.h, 0.0, 1.0)
	var asp = c.w / c.h
	if not c.has("holes"):
		c.holes = []
	# Löcher: (u, v, Radius in Bildhöhe, Zufall)
	var new_holes = []
	var frags = []   # [u, v, Größe in m]
	var k = c.h / 1.8          # Fetzen wachsen mit der Größe des Aufstellers
	# Jeder Treffer reißt ein großes Stück raus (mindestens etwa ein Fünftel der Figur), die Fetzen sind genau
	# die Pappe, die dort fehlt: pro Loch mehrere Stücke aus genau dieser Stelle des Bildes
	var big = []     # [u, v, r]
	var hx = 0.5 / asp   # Bildbreite in Höhen-Einheiten umrechnen
	match power:
		"shotgun":
			big.append([u, v, randf_range(0.13, 0.16)])
			for i in 4:
				big.append([u + randf_range(-0.28, 0.28) * hx * 0.5, v + randf_range(-0.18, 0.18), randf_range(0.08, 0.12)])
			for i in 8:
				new_holes.append(Vector4(u + randf_range(-0.3, 0.3) * hx * 0.5, v + randf_range(-0.22, 0.22), randf_range(0.03, 0.05), randf() * 9.0))
		"boom", "rocket":
			for i in 9:
				big.append([randf_range(0.2, 0.8), randf_range(0.1, 0.92), randf_range(0.1, 0.16)])
		"smg":
			big.append([u, v, randf_range(0.075, 0.095)])
		_:
			big.append([u, v, randf_range(0.11, 0.13)])
			big.append([u + randf_range(-0.12, 0.12) * hx * 0.5, v + randf_range(-0.1, 0.1), randf_range(0.06, 0.08)])
	for b in big:
		new_holes.append(Vector4(b[0], b[1], b[2], randf() * 9.0))
		# das ausgerissene Stück zerfällt in 3–4 Fetzen aus genau diesem Bereich
		var n = 4 if b[2] > 0.1 else 3
		for i in n:
			var a = TAU * (i + randf() * 0.6) / n
			var rr = b[2] * randf_range(0.2, 0.6)
			frags.append([b[0] + cos(a) * rr * hx * 2.0 * 0.5, b[1] + sin(a) * rr, b[2] * c.h * randf_range(1.0, 1.35)])
	for i in (3 if power in ["pistol", "smg"] else 6):
		frags.append([u + randf_range(-0.08, 0.08), v + randf_range(-0.08, 0.08), randf_range(0.06, 0.12) * k])
	c.holes.append_array(new_holes)
	while c.holes.size() > 16:
		c.holes.pop_front()
	var arr = PackedVector4Array()
	for h in c.holes:
		arr.append(h)
	c.mat.set_shader_parameter("holes", arr)
	c.mat.set_shader_parameter("nholes", c.holes.size())
	c.mat.set_shader_parameter("aspect", asp)
	# Fetzen fliegen vom Spieler weg (in die Szene), etwas nach oben und zur Seite
	var m = _shred_mat(tex)
	m.set_shader_parameter("dim", c.mat.get_shader_parameter("dim"))
	var away: Vector3 = (point - cam.global_position).normalized()
	var xf: Transform3D = c.mi.global_transform
	for f in frags:
		var sz: float = f[2]
		var fu: float = f[0]
		var fv: float = f[1]
		var mi = MeshInstance3D.new()
		var q = QuadMesh.new()
		q.size = Vector2(sz, sz)
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var du = sz / c.w
		var dv = sz / c.h
		mi.set_instance_shader_parameter("region", Vector4(fu - du * 0.5, fv - dv * 0.5, du, dv))
		mi.set_instance_shader_parameter("seed", randf() * 9.0)
		var pos: Vector3 = xf * Vector3((fu - 0.5) * c.w, (1.0 - fv) * c.h, 0.03)
		mi.global_position = pos
		mi.global_rotation = c.mi.global_rotation
		var pk = 1.0 if power in ["pistol", "smg"] else 1.5
		var vel = away * randf_range(1.5, 3.5) * pk + Vector3(randf_range(-2.0, 2.0), randf_range(1.5, 3.6), 0) * pk
		shreds.append({"mi": mi, "vel": vel, "av": Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)), "t": 0.0, "life": randf_range(2.4, 3.4), "rest": false})
	# ein paar Farbspritzer wie von einer Farbpatrone
	fx_k = clampf(point.distance_to(cam.global_position) / 7.0, 0.22, 1.3)
	var nrm: Vector3 = -away
	_chunks(point + nrm * 0.03, nrm, 5 if power in ["pistol", "smg"] else 10, [Color(0.78, 0.07, 0.05), Color(0.55, 0.03, 0.03)], 0.025)
	while shreds.size() > 90:
		var o = shreds.pop_front()
		if is_instance_valid(o.mi):
			o.mi.queue_free()


func _shreds_update(dt: float) -> void:
	for i in range(shreds.size() - 1, -1, -1):
		var f = shreds[i]
		f.t += dt
		if not is_instance_valid(f.mi) or f.t > f.life:
			if is_instance_valid(f.mi):
				f.mi.queue_free()
			shreds.remove_at(i)
			continue
		if not f.rest:
			f.vel.y -= 7.5 * dt
			f.vel *= exp(-dt * 1.0)          # Luftwiderstand: Pappe segelt
			f.mi.global_position += f.vel * dt
			f.mi.rotate_x(f.av.x * dt)
			f.mi.rotate_y(f.av.y * dt)
			f.mi.rotate_z(f.av.z * dt)
			if f.mi.global_position.y < 0.02:
				var gp: Vector3 = f.mi.global_position
				gp.y = 0.02
				f.mi.global_position = gp
				f.mi.global_rotation = Vector3(-PI * 0.5, randf() * TAU, 0)
				f.rest = true
		var left = f.life - f.t
		if left < 0.35:
			f.mi.scale = Vector3.ONE * maxf(0.01, left / 0.35)


# ---------------------------------------------------------------------------
# Hafen-Atmosphäre: Nebelschwaden, vorbeiziehendes Schiff, Rundumleuchte am Lkw

var fog = []
var fog_shader: Shader
var ship: Node3D
func _harbor_atmo(deco: Node3D) -> void:
	var gl = _soft_tex(64, 1.4)
	# mehr Lampen im Hintergrund, in verschiedenen Entfernungen
	for uv in [Vector2(0.125, 0.486), Vector2(0.065, 0.3301), Vector2(0.071, 0.3106), Vector2(0.6981, 0.5932), Vector2(0.7088, 0.6218),
			Vector2(0.7411, 0.606), Vector2(0.9415, 0.5579), Vector2(0.3995, 0.4653), Vector2(0.2422, 0.3709), Vector2(0.1829, 0.5365)]:
		_glow(deco, gl, Vector3((uv.x - 0.5) * 220.0, -28.6 + (1.0 - uv.y) * 94.27, -74.5), 3.2, Color(1.0, 0.74, 0.4), "flick")
	for uv in [Vector2(0.6537, 0.6504), Vector2(0.9682, 0.5792), Vector2(0.9462, 0.7533), Vector2(0.5739, 0.4233)]:
		_glow(deco, gl, Vector3((uv.x - 0.5) * 220.0, -28.6 + (1.0 - uv.y) * 94.27, -74.5), 4.5, Color(0.8, 0.9, 1.0), "flick")
	# Rundumleuchte auf dem Lkw-Dach
	_glow(deco, gl, Vector3(-7.9 + (0.793 - 0.5) * 5.6, -0.05 + (1.0 - 0.044) * 3.0, -10.3), 0.9, Color(1.0, 0.55, 0.1), "beacon")
	# ein Schiff zieht ganz hinten langsam vorbei (Topplicht weiß, Seitenlichter rot/grün)
	ship = Node3D.new()
	deco.add_child(ship)
	_glow(ship, gl, Vector3(0, 2.2, 0), 2.2, Color(1.0, 0.95, 0.85), "steady")
	_glow(ship, gl, Vector3(-3.0, 0.6, 0), 1.6, Color(1.0, 0.15, 0.1), "steady")
	_glow(ship, gl, Vector3(3.0, 0.6, 0), 1.6, Color(0.2, 1.0, 0.35), "steady")
	_glow(ship, gl, Vector3(-1.2, 0.9, 0), 1.2, Color(1.0, 0.8, 0.5), "steady")
	_glow(ship, gl, Vector3(1.0, 0.9, 0), 1.2, Color(1.0, 0.8, 0.5), "steady")
	ship.position = Vector3(-120.0, -1.0, -74.0)
	# Nebelschwaden: weich, kaum sichtbar, ziehen langsam durchs Flutlicht
	fog_shader = Shader.new()
	fog_shader.code = """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : filter_linear_mipmap;
uniform vec4 col : source_color = vec4(0.62, 0.7, 0.8, 1.0);
instance uniform float k = 0.1;
void fragment() {
	float a = texture(tex, UV).a;
	ALBEDO = col.rgb;
	ALPHA = a * k;
}
"""
	var ft = _soft_tex(64, 1.0)
	for i in 9:
		var m = ShaderMaterial.new()
		m.shader = fog_shader
		m.set_shader_parameter("tex", ft)
		if i % 3 == 0:
			m.set_shader_parameter("col", Color(0.85, 0.7, 0.5, 1.0))   # im warmen Flutlicht
		var mi = MeshInstance3D.new()
		var q = QuadMesh.new()
		var far = i < 6
		q.size = Vector2(randf_range(14.0, 22.0), randf_range(2.5, 4.5)) if far else Vector2(randf_range(8.0, 12.0), randf_range(1.0, 1.6))
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		deco.add_child(mi)
		var z = randf_range(-34.0, -17.0) if far else randf_range(-11.5, -8.5)
		var y = randf_range(3.0, 9.0) if far else randf_range(0.4, 0.9)
		mi.position = Vector3(randf_range(-28.0, 28.0), y, z)
		fog.append({"mi": mi, "spd": randf_range(0.25, 0.6) * (1.0 if randf() < 0.7 else -1.0), "a": (0.13 if far else 0.07), "ph": randf() * TAU})


func _atmo_update(dt: float) -> void:
	for f in fog:
		var p: Vector3 = f.mi.position
		p.x += f.spd * dt
		if p.x > 32.0:
			p.x = -32.0
		elif p.x < -32.0:
			p.x = 32.0
		f.mi.position = p
		f.mi.set_instance_shader_parameter("k", f.a * (0.65 + 0.35 * sin(life_t * 0.21 + f.ph)))
	if ship != null:
		ship.position.x += 1.4 * dt
		if ship.position.x > 120.0:
			ship.position.x = -120.0


# ---------------------------------------------------------------------------
# Dritte Map: Motel an der Landstraße in der Dämmerung, Polizei hat umstellt (Finale der Kampagne)

const MO_W = 18.0
const MO_X = -0.8
const SIGN_W = 4.0
const CW = 8.1               # Streifenwagen (50 % größer)
const MO_HOLES = {"up1": [0.3241, 0.4087, 0.1443, 0.4216], "up2": [0.7621, 0.8399, 0.1488, 0.4216],
	"door": [0.4081, 0.4769, 0.5727, 0.8929], "win": [0.8095, 0.8754, 0.5750, 0.7621]}
var cop_red: OmniLight3D
var cop_blue: OmniLight3D
var cop_glows = []
var neon = {}
var siren_t = 14.0
var radio_t = 6.0
var mega_player: AudioStreamPlayer
var mega_last = -1


func _make_motel() -> void:
	cards = []
	slots = []
	var sky = _card("m_sky.jpg", 220.0, Vector3(0.0, -41.0, -75.0), "sky")
	var gm = ShaderMaterial.new()
	gm.shader = ground_shader
	gm.set_shader_parameter("tex", load("res://art/m_ground.jpg"))
	gm.set_shader_parameter("rep", 3.4)
	var gq = QuadMesh.new()
	gq.size = Vector2(60.0, 24.0)
	gq.center_offset = Vector3(0, 24.0 * 0.5, 0)
	var gi = MeshInstance3D.new()
	gi.mesh = gq
	gi.material_override = gm
	var gp = Node3D.new()
	gp.position = Vector3(0, 0, FAC_Z + 15.0)
	gp.rotation.x = -PI * 0.5
	add_child(gp)
	gp.add_child(gi)
	cards.append({"pv": gp, "mi": gi, "mat": gm, "img": null, "w": 60.0, "h": 24.0, "kind": "ground", "t": 99.0, "delay": 0.0, "up": true, "static": true})
	# Motel: zwei Etagen, offene Zimmertüren oben, unten Tür und Fenster offen; dahinter dunkle Zimmer
	var mo = _card("m_motel.png", MO_W, Vector3(MO_X, FAC_Y, FAC_Z), "brick")
	mo.delay = 0.0
	cards.append(mo)
	var mh: float = mo.h
	var sink = (1.0 - 851.0 / 887.0) * mh
	mo.pv.position.y -= sink
	var room = MeshInstance3D.new()
	var rq = QuadMesh.new()
	rq.size = Vector2(MO_W, mh)
	rq.center_offset = Vector3(0, mh * 0.5, 0)
	room.mesh = rq
	var rm = StandardMaterial3D.new()
	rm.albedo_color = Color(0.045, 0.035, 0.03)
	rm.roughness = 1.0
	room.material_override = rm
	room.position = Vector3(0, 0, -0.85)
	mo.pv.add_child(room)
	cards.append({"pv": mo.pv, "mi": room, "mat": rm, "img": null, "w": MO_W, "h": mh, "kind": "room", "t": 99.0, "delay": 0.0, "up": true, "static": true})
	var cop = _card("m_cop.png", CW, Vector3(-7.7, -0.04, -9.8), "metal")
	cop.delay = 0.25
	cards.append(cop)
	var sign = _card("m_sign.png", SIGN_W, Vector3(7.6, -0.05, -11.8), "metal")
	sign.delay = 0.4
	cards.append(sign)
	var cop2 = _card("m_cop2.png", CW, Vector3(8.4, -0.04, -12.3), "metal")
	cop2.delay = 0.5
	cards.append(cop2)
	var pk = _card("m_pickup.png", 7.3, Vector3(5.6, -0.02, -8.4), "metal")
	pk.delay = 0.6
	pk.base = pk.pv.position
	pk.label = "PICKUP"
	pk.debris = [["m_deb_mirror.png", 0.42, Vector3(-2.1, 0.0, 0.6), Vector3(-PI * 0.4, 0.6, 0.0)],
		["m_deb_light.png", 0.36, Vector3(-2.8, 0.0, 0.4), Vector3(-PI * 0.45, 0.9, 0.0)]]
	cards.append(pk)
	var tr = _card("m_trash.png", 4.6, Vector3(-4.3, -0.04, -7.0), "metal")
	tr.delay = 0.8
	cards.append(tr)
	# deine Deckung: die offene Fahrertür des Streifenwagens
	var cov = _card("m_cover.png", 5.6, Vector3(1.05, -1.04, -1.35), "metal")
	cov.delay = 1.05
	cards.append(cov)
	# Spots: oben in den offenen Zimmertüren und unten in Tür und Fenster ganze bzw. halbe Figur
	for n in MO_HOLES:
		var hh = MO_HOLES[n]
		var x = MO_X + ((hh[0] + hh[1]) * 0.5 - 0.5) * MO_W
		var ybot = FAC_Y - sink + (1.0 - hh[3]) * mh
		var oh = (hh[3] - hh[2]) * mh
		if n == "win":
			var drop = 3.0 - (oh - 0.1)
			slots.append({"pos": Vector3(x, ybot - drop, FAC_Z - 0.32), "mode": "flip", "busy": false, "name": n, "eh": 3.0, "box_lift": drop})
		else:
			slots.append({"pos": Vector3(x, ybot - 0.02, FAC_Z - 0.3), "mode": "flip", "busy": false, "name": n, "eh": oh - 0.06, "box_lift": 0.0})
	slots.append({"pos": Vector3(-3.1, 0.2, -7.4), "mode": "flip", "busy": false, "name": "crates", "eh": ENEMY_H_FRONT})
	# vorne seitlich an der Motorhaube des Pickups, gut sichtbar
	slots.append({"pos": Vector3(1.6, 0.0, -8.0), "mode": "flip", "busy": false, "name": "car", "box_lift": 0.0, "eh": ENEMY_H_FRONT})
	var deco = _make_motel_life(mo, mh, sink, sign)
	_shadow(cop, 0.9, 1.6, 0.62)
	_shadow(cop2, 0.9, 1.6, 0.62)
	_shadow(pk, 0.9, 1.6, 0.62)
	_shadow(tr, 1.02, 1.5, 0.58)
	_shadow(sign, 0.25, 0.5, 0.4)
	_shadow(mo, 1.0, 1.4, 0.45)
	scenes["motel"] = {"deco": deco, "cards": cards, "slots": slots, "wall": cov, "car": pk, "sky": sky.pv,
		"bg": Color(0.3, 0.18, 0.2), "amb": "ambience_motel"}


func _make_motel_life(mo: Dictionary, mh: float, sink: float, sign: Dictionary) -> Node3D:
	var deco = Node3D.new()
	add_child(deco)
	var gl = _soft_tex(64, 1.4)
	# Blaulicht: zwei farbige Lichter am Streifenwagen links, die abwechselnd über Fassade und Tür zucken
	cop_red = OmniLight3D.new()
	cop_red.light_color = Color(1.0, 0.12, 0.08)
	cop_red.omni_range = 15.0
	cop_red.light_energy = 0.0
	cop_red.position = Vector3(-8.5, 3.0, -8.6)
	deco.add_child(cop_red)
	cop_blue = OmniLight3D.new()
	cop_blue.light_color = Color(0.15, 0.35, 1.0)
	cop_blue.omni_range = 15.0
	cop_blue.light_energy = 0.0
	cop_blue.position = Vector3(-7.9, 3.0, -8.6)
	deco.add_child(cop_blue)
	# Lichtbalken auf den Dächern (Glühpunkte)
	var bar_h = CW * 674.0 / 1954.0 * (1.0 - 0.075)
	for sp in [[-7.7 + (0.405 - 0.5) * CW, "r"], [-7.7 + (0.46 - 0.5) * CW, "b"], [8.4 + (0.5 - 0.405) * CW, "r"], [8.4 + (0.5 - 0.46) * CW, "b"]]:
		var z = -9.7 if sp[0] < 0 else -12.2
		var mi = _glow_node(deco, gl, Vector3(sp[0], bar_h, z), 2.0, Color(1.0, 0.15, 0.1) if sp[1] == "r" else Color(0.2, 0.4, 1.0))
		cop_glows.append({"mi": mi, "c": sp[1], "ph": 0.0 if sp[0] < 0 else 0.37})
	# Neonschild: MOTEL-Schriftzug flackert ab und zu, der Stern leuchtet ruhig
	var sw = SIGN_W
	var shh: float = sign.h
	var sx = 7.6
	neon.letters = _glow_node(deco, gl, Vector3(sx + 0.03 * sw, -0.05 + (1.0 - 0.265) * shh, -11.7), 3.4 * SIGN_W / 3.0, Color(1.0, 0.3, 0.14))
	neon.letters.scale = Vector3(1.0, 0.42, 1.0)
	neon.star = _glow_node(deco, gl, Vector3(sx + 0.02 * sw, -0.05 + (1.0 - 0.1) * shh, -11.7), 1.6 * SIGN_W / 3.0, Color(1.0, 0.75, 0.4))
	neon.t = 3.0
	neon.dip = 0.0
	# Wandlampen am Motel (sanft, eine wackelt)
	for uv in [Vector2(0.2825, 0.1625), Vector2(0.679, 0.175), Vector2(0.08, 0.6125), Vector2(0.381, 0.6125), Vector2(0.759, 0.595)]:
		_glow(deco, gl, Vector3(MO_X + (uv.x - 0.5) * MO_W, FAC_Y - sink + (1.0 - uv.y) * mh, FAC_Z + 0.2), 1.1, Color(1.0, 0.72, 0.38), "flick")
	_glow(deco, gl, Vector3(MO_X + (0.7375 - 0.5) * MO_W, FAC_Y - sink + (1.0 - 0.5175) * mh, FAC_Z + 0.2), 1.8, Color(0.9, 0.95, 1.0), "flick")
	mega_player = AudioStreamPlayer.new()
	mega_player.volume_db = 3.0
	add_child(mega_player)
	return deco


func _glow_node(parent: Node3D, tex: Texture2D, pos: Vector3, size: float, col: Color) -> MeshInstance3D:
	_glow(parent, tex, pos, size, col, "steady")
	var g = glows.pop_back()   # selbst gesteuert, nicht über die Lampenliste
	return g.mi


func _motel_update(dt: float) -> void:
	# Polizei-Strobe: rot zweimal, dann blau zweimal
	var cyc = fmod(life_t, 0.9)
	var r = 1.0 if (cyc < 0.07 or (cyc > 0.15 and cyc < 0.22)) else 0.0
	var b = 1.0 if ((cyc > 0.45 and cyc < 0.52) or (cyc > 0.6 and cyc < 0.67)) else 0.0
	cop_red.light_energy = lerpf(cop_red.light_energy, r * 3.2, 1.0 - exp(-dt * 40.0))
	cop_blue.light_energy = lerpf(cop_blue.light_energy, b * 3.6, 1.0 - exp(-dt * 40.0))
	for g in cop_glows:
		var cc = fmod(life_t + g.ph, 0.9)
		var on: bool
		if g.c == "r":
			on = cc < 0.07 or (cc > 0.15 and cc < 0.22)
		else:
			on = (cc > 0.45 and cc < 0.52) or (cc > 0.6 and cc < 0.67)
		g.mi.set_instance_shader_parameter("k", 1.0 if on else 0.15)
	# Neon: meistens an, ab und zu ein kaputtes Flackern
	neon.t -= dt
	if neon.t <= 0.0:
		if neon.dip > 0.0:
			neon.dip = 0.0
			neon.t = randf_range(2.0, 7.0) if randf() < 0.7 else randf_range(0.05, 0.12)
		else:
			neon.dip = randf_range(0.5, 0.9)
			neon.t = randf_range(0.04, 0.14)
	neon.letters.set_instance_shader_parameter("k", 1.0 - neon.dip + sin(life_t * 50.0) * 0.04)
	neon.star.set_instance_shader_parameter("k", 0.85 + sin(life_t * 2.0) * 0.1)
	# Sirene und Funk ab und zu
	if state == "play" or state == "intro":
		siren_t -= dt
		if siren_t <= 0.0:
			siren_t = randf_range(22.0, 38.0)
			_sfx("siren", -9.0, 0.05)
		radio_t -= dt
		if radio_t <= 0.0:
			radio_t = randf_range(9.0, 17.0)
			_sfx("radio%d" % (randi() % 2), -6.0, 0.04)


# Megafon-Durchsage der Polizei (in allen Maps, zu Rundenbeginn)
func _megaphone(i: int, delay: float) -> void:
	if mega_player == null:
		return
	if i >= 1 and i <= 4 and i == mega_last:
		i = (i % 4) + 1
	mega_last = i
	var st = load("res://sfx/voice/cop%d.ogg" % i)
	get_tree().create_timer(delay).timeout.connect(func():
		if warming:
			return
		mega_player.stream = st
		mega_player.play())



# ---------------------------------------------------------------------------
# Weiche Bodenschatten unter Fahrzeugen, Kisten und Gegnern, die auf dem Boden stehen.
# Folgen ihrer Karte (Wrack, Gegner) und blenden aus, solange die Karte flach liegt (Aufklappen, Umfallen).

func _shadow(c: Dictionary, wk: float, depth: float, alpha: float) -> void:
	if shadow_mat == null:
		var sh = Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : filter_linear_mipmap;
instance uniform float k = 0.5;
void fragment() {
	float a = texture(tex, UV).a;
	ALBEDO = vec3(0.03, 0.02, 0.02);
	ALPHA = a * k;
}
"""
		shadow_mat = ShaderMaterial.new()
		shadow_mat.shader = sh
		var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d = Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length() / 32.0
				var a = 1.0 - smoothstep(0.35, 1.0, d)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		shadow_mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	var mi = MeshInstance3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(c.w * wk, depth)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = shadow_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = -1.0
	add_child(mi)
	shadows.append({"mi": mi, "node": c.pv, "k": alpha, "off": Vector3(0, 0, depth * 0.1)})
	_shadow_place(shadows[-1])


func _shadow_place(sd: Dictionary) -> void:
	var n: Node3D = sd.node
	var p: Vector3 = n.global_position + sd.off
	sd.mi.global_position = Vector3(p.x, 0.014, p.z)
	sd.mi.global_rotation = Vector3(0, n.global_rotation.y, 0)
	var up = clampf(n.global_basis.y.normalized().y, 0.0, 1.0)
	var vis = n.is_visible_in_tree()
	sd.mi.visible = vis and up > 0.05
	sd.mi.set_instance_shader_parameter("k", minf(0.9, sd.k * 1.45) * up * up)


func _shadows_update() -> void:
	for i in range(shadows.size() - 1, -1, -1):
		var sd = shadows[i]
		if not is_instance_valid(sd.node) or sd.node.is_queued_for_deletion():
			sd.mi.queue_free()
			shadows.remove_at(i)
			continue
		_shadow_place(sd)



# ---------------------------------------------------------------------------
# Klang-Einstellungen: wie die Gegnerstimmen im Raum klingen (Hall, Entfernung, Richtung) und Lautstärken.
# Eigenes Fenster mit Scrollen; ein Regler bewegt sich nur bei waagerechtem Ziehen, senkrecht wird gescrollt.

const SND = [
	{"label": "ROOM SIZE", "hint": "small room … big hall", "key": "snd_room", "min": 0.0, "max": 1.0, "def": 0.35},
	{"label": "REVERB AMOUNT", "hint": "how much echo you hear", "key": "snd_wet", "min": 0.0, "max": 0.8, "def": 0.2},
	{"label": "REVERB BRIGHTNESS", "hint": "dull … bright echo", "key": "snd_bright", "min": 0.0, "max": 1.0, "def": 0.4},
	{"label": "PRE-DELAY", "hint": "how far away the walls feel", "key": "snd_pre", "min": 0.0, "max": 150.0, "def": 30.0},
	{"label": "MUFFLE", "hint": "less treble = further away", "key": "snd_muffle", "min": 0.0, "max": 1.0, "def": 0.45},
	{"label": "DISTANCE FALLOFF", "hint": "how fast voices fade with distance", "key": "snd_fall", "min": 0.0, "max": 1.0, "def": 0.5},
	{"label": "LEFT / RIGHT", "hint": "how strongly voices pan", "key": "snd_pan", "min": 0.0, "max": 2.0, "def": 1.6},
	{"label": "ENEMY VOICES", "hint": "volume", "key": "snd_vol_far", "min": -18.0, "max": 12.0, "def": 0.0},
	{"label": "MEGAPHONE", "hint": "volume of your police voice", "key": "snd_vol_mega", "min": -18.0, "max": 12.0, "def": 3.0}]
var snd_room = 0.35
var snd_wet = 0.2
var snd_bright = 0.4
var snd_pre = 30.0
var snd_muffle = 0.45
var snd_fall = 0.5
var snd_pan = 1.6
var snd_vol_far = 0.0
var snd_vol_mega = 3.0
var snd_open = false
var snd_scroll = 0.0
var snd_touch = {}
var far_bus = -1
const SND_ROW = 84.0


func _far_voice(stream: AudioStream, pos: Vector3, pitch: float = 1.0, extra_unit: float = 0.0) -> void:
	var p = AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Far"
	p.unit_size = lerpf(14.0, 3.0, snd_fall) + extra_unit
	p.volume_db = 7.0 + snd_vol_far
	p.max_db = 6.0
	p.panning_strength = snd_pan
	p.pitch_scale = pitch
	p.attenuation_filter_cutoff_hz = lerpf(12000.0, 3000.0, snd_muffle)
	p.attenuation_filter_db = lerpf(-2.0, -18.0, snd_muffle)
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _audio_apply() -> void:
	if far_bus >= 0:
		var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(far_bus, 0)
		lp.cutoff_hz = exp(lerpf(log(14000.0), log(1800.0), snd_muffle))
		var rv: AudioEffectReverb = AudioServer.get_bus_effect(far_bus, 1)
		rv.room_size = snd_room
		rv.wet = snd_wet
		rv.dry = 1.0 - snd_wet * 0.35
		rv.damping = 1.0 - snd_bright
		rv.hipass = 0.15
		rv.predelay_msec = snd_pre
	if mega_player != null:
		mega_player.volume_db = snd_vol_mega


func _quit_to_menu() -> void:
	panel_open = false
	for e in enemies:
		e.pv.queue_free()
	enemies.clear()
	for sl in slots:
		sl.busy = false
	if scene != "street":
		_back_to_street()
		_close_book()
		_open_book(0.2)
	msg_t = 0.0
	cover = true
	_set_state("title")


func _title_btn_rect(i: int) -> Rect2:
	var vs = _vs()
	return Rect2(24 + i * 142, vs.y - 74, 128, 48)


func _snd_rect() -> Rect2:
	var vs = _vs()
	var w = minf(700.0, vs.x - 40.0)
	return Rect2(vs.x * 0.5 - w * 0.5, 24, w, vs.y - 48)


func _snd_list_rect() -> Rect2:
	var r = _snd_rect()
	return Rect2(r.position.x + 20, r.position.y + 84, r.size.x - 40, r.size.y - 100)


func _snd_hdr_btn(i: int) -> Rect2:
	var r = _snd_rect()
	return Rect2(r.end.x - 20 - (3 - i) * 128, r.position.y + 18, 118, 48)


func _snd_max_scroll() -> float:
	return maxf(0.0, SND.size() * SND_ROW - _snd_list_rect().size.y)


func _snd_row_y(i: int) -> float:
	return _snd_list_rect().position.y + i * SND_ROW - snd_scroll


func _snd_track(i: int) -> Rect2:
	var lr = _snd_list_rect()
	var y = _snd_row_y(i) + 34
	return Rect2(lr.position.x + 70, y, lr.size.x - 140, 40)


func _snd_minus(i: int) -> Rect2:
	var t = _snd_track(i)
	return Rect2(t.position.x - 64, t.position.y - 2, 48, 44)


func _snd_plus(i: int) -> Rect2:
	var t = _snd_track(i)
	return Rect2(t.end.x + 16, t.position.y - 2, 48, 44)


func _snd_set(i: int, v: float) -> void:
	var sd = SND[i]
	var stp = (sd.max - sd.min) / 40.0
	set(sd.key, clampf(snappedf(v, stp), sd.min, sd.max))
	_audio_apply()


func _snd_press(p: Vector2, idx: int) -> void:
	for i in 3:
		if _snd_hdr_btn(i).has_point(p):
			match i:
				0:
					_snd_test()
				1:
					for sd in SND:
						set(sd.key, sd.def)
					_audio_apply()
					_save()
				2:
					snd_open = false
					_save()
			return
	if _snd_list_rect().has_point(p):
		ui_idx = idx
		ui_drag = "snd"
		var row = int((p.y - _snd_list_rect().position.y + snd_scroll) / SND_ROW)
		snd_touch = {"p0": p, "mode": "", "row": row, "s0": snd_scroll}


func _snd_drag(p: Vector2) -> void:
	var d: Vector2 = p - snd_touch.p0
	if snd_touch.mode == "":
		if absf(d.y) > 12.0 and absf(d.y) > absf(d.x):
			snd_touch.mode = "scroll"
		elif absf(d.x) > 12.0 and absf(d.x) > absf(d.y) * 1.2:
			var r = snd_touch.row
			if r >= 0 and r < SND.size():
				var t = _snd_track(r)
				if p.y > t.position.y - 30 and p.y < t.end.y + 20 and snd_touch.p0.x > t.position.x - 20 and snd_touch.p0.x < t.end.x + 20:
					snd_touch.mode = "slider"
					snd_touch.v0 = float(get(SND[r].key))
	if snd_touch.mode == "scroll":
		snd_scroll = clampf(snd_touch.s0 - d.y, 0.0, _snd_max_scroll())
	elif snd_touch.mode == "slider":
		var sd = SND[snd_touch.row]
		var t = _snd_track(snd_touch.row)
		# relativ ziehen: der Wert springt nicht unter den Finger, sondern folgt der Bewegung
		_snd_set(snd_touch.row, snd_touch.v0 + d.x / t.size.x * (sd.max - sd.min))


func _snd_release(p: Vector2) -> void:
	if snd_touch.get("mode", "x") != "":
		return
	var r = snd_touch.row
	if r < 0 or r >= SND.size():
		return
	var sd = SND[r]
	var stp = (sd.max - sd.min) / 40.0
	if _snd_minus(r).grow(8).has_point(p):
		_snd_set(r, float(get(sd.key)) - stp)
	elif _snd_plus(r).grow(8).has_point(p):
		_snd_set(r, float(get(sd.key)) + stp)


# Probe: ein Gegner ruft aus einem Fenster links hinten, danach das Megafon
func _snd_test() -> void:
	var pick = null
	for sl in slots:
		if sl.pos.y > 1.0:
			pick = sl
			break
	if pick == null:
		pick = slots[0]
	var arr: Array = voices.get("appear", {}).get(["A", "B", "C", "D"][randi() % 4], [])
	if not arr.is_empty():
		_far_voice(arr[randi() % arr.size()], pick.pos + Vector3(0, 1.6, 0))
	get_tree().create_timer(2.2).timeout.connect(func():
		var near = null
		for sl in slots:
			if sl.name == "car" or sl.name == "crates":
				near = sl
				break
		if near != null and not arr.is_empty():
			_far_voice(arr[randi() % arr.size()], near.pos + Vector3(0, 1.4, 0)))
	_megaphone(randi_range(1, 4), 4.2)


func _snd_draw(c: Control) -> void:
	if not snd_open:
		return
	var vs = _vs()
	c.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5))
	var r = _snd_rect()
	_panel(c, r, 0.9)
	_text(c, Vector2(r.position.x + 24, r.position.y + 50), "SOUND", 26, Color(1, 0.92, 0.8))
	for i in 3:
		var b = _snd_hdr_btn(i)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Color(1, 0.78, 0.3, 0.95) if i == 2 else Color(1, 1, 1, 0.1)
		bs.border_color = Color(1, 1, 1, 0.35)
		bs.set_border_width_all(1)
		bs.set_corner_radius_all(24)
		c.draw_style_box(bs, b)
		_text(c, Vector2(b.position.x, b.position.y + 31), ["TEST", "RESET", "DONE"][i], 17, Color(0.1, 0.07, 0.03) if i == 2 else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, b.size.x, font_light)
	var lr = _snd_list_rect()
	for i in SND.size():
		var y = _snd_row_y(i)
		if y + SND_ROW < lr.position.y - 2 or y > lr.end.y:
			continue
		# Zeilen am Rand ausblenden statt hart abschneiden
		var a = clampf(minf((y + SND_ROW - lr.position.y) / 30.0, (lr.end.y - y) / 30.0), 0.0, 1.0)
		if a <= 0.02:
			continue
		var sd = SND[i]
		var val: float = get(sd.key)
		var k = clampf((val - sd.min) / (sd.max - sd.min), 0, 1)
		var vt: String
		if sd.key.begins_with("snd_vol"):
			vt = "%+.0f dB" % val
		elif sd.key == "snd_pre":
			vt = "%d ms" % roundi(val)
		elif sd.key == "snd_pan":
			vt = "%d %%" % roundi(val / 2.0 * 100.0)
		else:
			vt = "%d %%" % roundi(k * 100.0)
		_text(c, Vector2(lr.position.x + 6, y + 22), sd.label, 16, Color(1, 1, 1, 0.9 * a))
		_text(c, Vector2(lr.position.x + 200, y + 22), sd.hint, 13, Color(1, 1, 1, 0.5 * a), HORIZONTAL_ALIGNMENT_LEFT, -1, font_light)
		_text(c, Vector2(lr.position.x, y + 22), vt, 17, Color(1, 0.86, 0.55, a), HORIZONTAL_ALIGNMENT_RIGHT, lr.size.x - 6)
		var t = _snd_track(i)
		var cy = t.get_center().y
		c.draw_line(Vector2(t.position.x, cy), Vector2(t.end.x, cy), Color(1, 1, 1, 0.22 * a), 5.0, true)
		c.draw_line(Vector2(t.position.x, cy), Vector2(t.position.x + t.size.x * k, cy), Color(1.0, 0.78, 0.45, a), 5.0, true)
		c.draw_circle(Vector2(t.position.x + t.size.x * k, cy), 14.0, Color(1, 1, 1, a))
		for j in 2:
			var b = _snd_minus(i) if j == 0 else _snd_plus(i)
			c.draw_circle(b.get_center(), 21.0, Color(1, 1, 1, 0.12 * a))
			c.draw_arc(b.get_center(), 21.0, 0, TAU, 32, Color(1, 1, 1, 0.4 * a), 1.5, true)
			_text(c, Vector2(b.position.x, b.position.y + 32), "–" if j == 0 else "+", 24, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, b.size.x)
	# Scrollbalken
	var ms = _snd_max_scroll()
	if ms > 0.0:
		var h = lr.size.y * lr.size.y / (lr.size.y + ms)
		var y0 = lr.position.y + (lr.size.y - h) * snd_scroll / ms
		c.draw_line(Vector2(r.end.x - 8, y0), Vector2(r.end.x - 8, y0 + h), Color(1, 1, 1, 0.35), 4.0, true)
	_text(c, Vector2(r.position.x, r.end.y - 6), "Swipe up/down to scroll  ·  drag sideways to change a value", 12, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_light)
