extends RefCounted
# PERSONAGENS 3D ESCOLHIVEIS (tela "Criar personagem" e painel Visual).
#
# Onde colocar os modelos (.glb / .gltf / .fbx) no projeto:
#   res://personagens/gratis/   -> personagens GRATIS (os "feios", qualquer um escolhe)
#   res://personagens/vip/      -> personagens BONITOS (so quem COMPRAR pode usar)
# O id do personagem e o nome do arquivo sem extensao. Para mudar nome/preco de um deles,
# preencha NOMES / PRECOS abaixo. Preco padrao dos vip: PRECO_VIP.

const PASTAS = [["res://personagens/gratis", false], ["res://personagens/vip", true]]
const EXTENSOES = ["glb", "gltf", "fbx"]
const PRECO_VIP = 25000
const NOMES = {}    # ex.: {"jorge": "Jorge Almeida"}
const PRECOS = {}   # ex.: {"jorge": 40000}

static var _cache = null


static func _bonito(id) -> String:
	if NOMES.has(id):
		return str(NOMES[id])
	var t = str(id).replace("_", " ").replace("-", " ").strip_edges()
	return t.capitalize()


static func lista() -> Array:
	if _cache != null:
		return _cache
	var saida = []
	for p in PASTAS:
		var d = DirAccess.open(p[0])
		if d == null:
			continue
		var vistos = {}
		for f in d.get_files():
			var nome = f
			if nome.ends_with(".import"):
				nome = nome.trim_suffix(".import")
			elif nome.ends_with(".remap"):
				nome = nome.trim_suffix(".remap")
			if not (nome.get_extension().to_lower() in EXTENSOES):
				continue
			var caminho = p[0] + "/" + nome
			if vistos.has(caminho) or not ResourceLoader.exists(caminho):
				continue
			vistos[caminho] = true
			var id = nome.get_basename()
			var vip = bool(p[1])
			saida.append({
				"id": id,
				"nome": _bonito(id),
				"arquivo": caminho,
				"vip": vip,
				"preco": int(PRECOS.get(id, PRECO_VIP)) if vip else 0,
			})
		# gratis primeiro, depois vip; dentro de cada grupo, por nome
	saida.sort_custom(func(a, b):
		if a["vip"] != b["vip"]:
			return not a["vip"]
		return a["nome"] < b["nome"])
	_cache = saida
	return saida


static func achar(id) -> Dictionary:
	for it in lista():
		if it["id"] == id:
			return it
	return {}


static func arquivo(id) -> String:
	var it = achar(id)
	if it.is_empty():
		return ""
	return str(it["arquivo"])


# true se o jogador pode usar (gratis, ou ja comprou). comprados = lista de ids.
static func liberado(id, comprados) -> bool:
	var it = achar(id)
	if it.is_empty():
		return false
	return (not bool(it["vip"])) or (id in comprados)


static func primeiro_gratis() -> String:
	for it in lista():
		if not it["vip"]:
			return str(it["id"])
	return ""
