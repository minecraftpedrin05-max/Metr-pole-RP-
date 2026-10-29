extends Node
# SERVIDOR AUTORITATIVO.
# Todo dado importante (dinheiro, inventario, veiculos, propriedades, documentos) vive aqui.
# O cliente so PEDE (Rede.pedir); o servidor valida, altera, salva em disco e devolve o estado.
# No modo offline e no modo "hospedar" este script roda dentro do proprio jogo.

const Itens = preload("res://sistema/itens.gd")
const Cat = preload("res://sistema/catalogo.gd")
const Cidade = preload("res://sistema/config_cidade.gd")

const PASTA = "user://servidor/"
const LONGE = Vector3(1.0e9, 1.0e9, 1.0e9)
const VEL_MAX = 90.0
const SALAS = 4          # quantos servidores (salas) existem. Cada um e separado dos outros.
const MAX_POR_SALA = 32  # limite de jogadores em cada servidor

var ativo = false
var contas = {}
var peer_conta = {}
var conta_peer = {}
var online = {}
var mundo = {"veiculos": {}, "numeros": {}, "propriedades": {}, "prox": 1}
var trocas = {}
var prox_troca = 1
var rng = RandomNumberGenerator.new()
var re_hex = RegEx.new()
var t_save = 0.0
var t_stats = 0.0
var t_tempo = 0.0
var t_remotos = 0.0
var t_sal = 0.0
var t_salas = {}
var remotos_ativos = {}
var clima = "sol"
var clima_t = 0.0
var clima_dur = 700.0


func _ready():
	rng.randomize()
	re_hex.compile("^#[0-9a-fA-F]{6}$")
	DirAccess.make_dir_recursive_absolute(PASTA + "contas")
	set_process(false)


func iniciar():
	if ativo:
		return
	ativo = true
	_carregar_mundo()
	set_process(true)


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and ativo:
		salvar_tudo()


# ---------- disco ----------

func _ler_json(caminho):
	if not FileAccess.file_exists(caminho):
		return null
	var f = FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return null
	var txt = f.get_as_text()
	f.close()
	var j = JSON.new()
	if j.parse(txt) != OK:
		return null
	return j.data


func _gravar_json(caminho, dados):
	var tmp = caminho + ".tmp"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(dados))
	f.close()
	if FileAccess.file_exists(caminho):
		DirAccess.copy_absolute(caminho, caminho + ".bak")
		DirAccess.remove_absolute(caminho)
	return DirAccess.rename_absolute(tmp, caminho) == OK


func _log(texto):
	var caminho = PASTA + "auditoria.log"
	var f = null
	if FileAccess.file_exists(caminho):
		f = FileAccess.open(caminho, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(caminho, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(Time.get_datetime_string_from_system() + " " + texto)
	f.close()


func _salvar_mundo():
	_gravar_json(PASTA + "mundo.json", mundo)


func _salvar_conta(c):
	_gravar_json(PASTA + "contas/" + c["id"] + ".json", c)


func salvar_tudo():
	for cid in contas.keys():
		_salvar_conta(contas[cid])
	_salvar_mundo()


func _carregar_mundo():
	var d = _ler_json(PASTA + "mundo.json")
	if d == null:
		d = _ler_json(PASTA + "mundo.json.bak")
	if d is Dictionary:
		mundo["veiculos"] = d.get("veiculos", {})
		mundo["numeros"] = d.get("numeros", {})
		mundo["propriedades"] = d.get("propriedades", {})
		mundo["prox"] = int(d.get("prox", 1))
	for vid in mundo["veiculos"].keys():
		var v = mundo["veiculos"][vid]
		v["ativo_por"] = ""
		v["local"] = str(v.get("local", "rua"))
	# reconstroi o indice de telefones a partir das contas salvas
	var dir = DirAccess.open(PASTA + "contas")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				var c = _ler_json(PASTA + "contas/" + f)
				if c is Dictionary and c.has("numero") and c.has("id"):
					mundo["numeros"][str(c["numero"])] = str(c["id"])


func _id_valido(cid):
	if cid.length() < 16 or cid.length() > 40:
		return false
	for i in range(cid.length()):
		var ch = cid.substr(i, 1)
		if "0123456789abcdef".find(ch) < 0:
			return false
	return true


func _conta_padrao(cid):
	return {
		"id": cid, "criado": false, "nome": "", "numero": "", "criado_em": 0,
		"dinheiro": 10000000, "banco": 99999999, "fome": 100.0, "sede": 100.0,
		"inventario": {}, "aparencia": {}, "guarda_roupa": [],
		"contatos": [], "mensagens": [], "extrato": [],
		"docs": {"rg": {}, "cnh": null}, "emprego": "civil",
		"pos": [Cidade.SPAWN.x, Cidade.SPAWN.y, Cidade.SPAWN.z],
	}


func _normalizar(c):
	var padrao = _conta_padrao(str(c.get("id", "")))
	for k in padrao.keys():
		if not c.has(k):
			c[k] = padrao[k]
	for k in c["inventario"].keys():
		c["inventario"][k] = int(c["inventario"][k])
	c["dinheiro"] = int(c["dinheiro"])
	c["banco"] = int(c["banco"])
	return c


func _obter_conta(cid) -> Variant:
	if contas.has(cid):
		return contas[cid]
	var d = _ler_json(PASTA + "contas/" + cid + ".json")
	if d == null:
		d = _ler_json(PASTA + "contas/" + cid + ".json.bak")
	if d is Dictionary and d.has("id"):
		contas[cid] = _normalizar(d)
		return contas[cid]
	return null


func _conta_por_numero(num) -> Variant:
	var cid = mundo["numeros"].get(str(num), "")
	if cid == "":
		return null
	return _obter_conta(cid)


func _nome_de(cid):
	var c = _obter_conta(cid)
	if c == null:
		return "?"
	return str(c["nome"])


# ---------- sessao ----------

func entrar(peer, cid, sala = 1):
	cid = str(cid)
	sala = int(sala)
	if sala < 1 or sala > SALAS:
		Rede.enviar_cliente(peer, "entrada_negada", {"msg": "Servidor inválido."})
		return false
	if not _id_valido(cid):
		Rede.enviar_cliente(peer, "entrada_negada", {"msg": "Conta inválida."})
		return false
	if peer_conta.has(peer):
		sair(peer)
	if _jogadores_na_sala(sala, cid) >= MAX_POR_SALA:
		Rede.enviar_cliente(peer, "entrada_negada", {"msg": "O Servidor " + str(sala) + " está lotado."})
		return false
	if conta_peer.has(cid) and conta_peer[cid] != peer:
		var velho = conta_peer[cid]
		sair(velho)
		Rede.derrubar(velho)
	var c = _obter_conta(cid)
	if c == null:
		c = _normalizar({"id": cid})
		contas[cid] = c
		_salvar_conta(c)
	peer_conta[peer] = cid
	conta_peer[cid] = peer
	var p = c["pos"]
	online[peer] = {"sala": sala, "pos": Vector3(float(p[0]), float(p[1]), float(p[2])), "rot": 0.0, "emote": 0, "em_carro": false,
		"carro_pos": LONGE, "carro_rot": 0.0, "carro_vid": "", "t": Time.get_ticks_msec() / 1000.0, "ult_msg": 0.0, "ult_chat": 0.0,
		"ult_imp": 0.0, "avisou_comb": 0.0}
	_push(peer)
	Rede.enviar_cliente(peer, "tempo", _tempo_dict())
	_log("entrou " + cid + " peer " + str(peer) + " servidor " + str(sala))
	return true


func sair(peer):
	if not peer_conta.has(peer):
		return
	var cid = peer_conta[peer]
	var c = contas.get(cid, null)
	if c != null:
		var o = online.get(peer, null)
		if o != null:
			c["pos"] = [o["pos"].x, o["pos"].y, o["pos"].z]
		_salvar_conta(c)
	# veiculo ativo volta pra rua, na ultima posicao conhecida
	for vid in mundo["veiculos"].keys():
		var v = mundo["veiculos"][vid]
		if v["ativo_por"] == cid:
			v["ativo_por"] = ""
			v["local"] = "rua"
	_cancelar_trocas(cid)
	peer_conta.erase(peer)
	conta_peer.erase(cid)
	online.erase(peer)
	remotos_ativos.erase(peer)
	_salvar_mundo()
	_log("saiu " + cid)


# ---------- servidores (salas) ----------

func _sala_de(peer):
	if online.has(peer):
		return int(online[peer]["sala"])
	return -1


func _mesma_sala(a, b):
	var sa = _sala_de(a)
	return sa >= 0 and sa == _sala_de(b)


func _jogadores_na_sala(sala, ignorar_cid = ""):
	var n = 0
	for peer in online.keys():
		if int(online[peer]["sala"]) != sala:
			continue
		if ignorar_cid != "" and peer_conta.get(peer, "") == ignorar_cid:
			continue
		n += 1
	return n


func contagem_salas():
	var lista = []
	for i in range(1, SALAS + 1):
		lista.append({"sala": i, "jogadores": _jogadores_na_sala(i), "max": MAX_POR_SALA})
	return lista


func enviar_salas(peer):
	# lista de servidores com a quantidade de jogadores (o menu usa isso). Limitado a 2 pedidos por segundo.
	var agora = Time.get_ticks_msec()
	if agora - int(t_salas.get(peer, -10000)) < 500:
		return
	t_salas[peer] = agora
	Rede.enviar_cliente(peer, "salas", {"lista": contagem_salas()})


# ---------- recepcao de pedidos ----------

func processar(peer, op, a):
	if not ativo or not (a is Dictionary):
		return
	var c = _conta_de(peer)
	if c == null:
		return
	op = str(op)
	for i in range(op.length()):
		var ch = op.substr(i, 1)
		if "abcdefghijklmnopqrstuvwxyz_0123456789".find(ch) < 0:
			return
	var f = "op_" + op
	if not has_method(f):
		_resp(peer, {"ok": false, "msg": "Operação inválida."})
		return
	var r = call(f, peer, c, a)
	if not (r is Dictionary):
		r = _err("Erro interno.")
	if r.get("ok", false):
		_salvar_conta(c)
		_salvar_mundo()
	r["op"] = op
	if r.get("ok", false):
		_push(peer)
	_resp(peer, r)


func _conta_de(peer):
	var cid = peer_conta.get(peer, "")
	if cid == "":
		return null
	return contas.get(cid, null)


func _ok(msg = ""):
	return {"ok": true, "msg": msg}


func _err(msg):
	return {"ok": false, "msg": msg}


func _resp(peer, r):
	Rede.enviar_cliente(peer, "resp", r)


func _push(peer):
	var c = _conta_de(peer)
	if c != null:
		Rede.enviar_cliente(peer, "estado", estado_cliente(c))


func _push_conta(cid):
	if conta_peer.has(cid):
		_push(conta_peer[cid])


func _aviso(peer, texto):
	Rede.enviar_cliente(peer, "aviso", {"msg": texto})


func peso_total(c):
	var t = 0.0
	for id in c["inventario"].keys():
		t += Itens.peso(id) * int(c["inventario"][id])
	return t


func estado_cliente(c):
	var veics = []
	for vid in mundo["veiculos"].keys():
		var v = mundo["veiculos"][vid]
		if v["dono"] == c["id"] or c["id"] in v["chaves"]:
			var chaves_nomes = []
			if v["dono"] == c["id"]:
				for k in v["chaves"]:
					chaves_nomes.append({"conta": k, "nome": _nome_de(k)})
			veics.append({"id": vid, "modelo": v["modelo"], "cor": v["cor"], "placa": v["placa"], "comb": v["comb"], "dano": v["dano"],
				"trancado": v["trancado"], "local": v["local"], "pos": v["pos"], "rot": v["rot"], "ativo": v["ativo_por"] == c["id"], "upg_motor": int(v.get("upg_motor", 0)),
				"minha": v["dono"] == c["id"], "dono_nome": _nome_de(v["dono"]), "chaves": chaves_nomes})
	var props = []
	for pid in mundo["propriedades"].keys():
		if mundo["propriedades"][pid] == c["id"]:
			props.append(pid)
	var donos = {}
	for pid in mundo["propriedades"].keys():
		donos[pid] = true
	return {"criado": c["criado"], "nome": c["nome"], "numero": c["numero"], "dinheiro": c["dinheiro"], "banco": c["banco"],
		"fome": c["fome"], "sede": c["sede"], "inventario": c["inventario"], "peso": peso_total(c), "capacidade": Itens.CAPACIDADE_KG,
		"aparencia": c["aparencia"], "guarda_roupa": c["guarda_roupa"], "contatos": c["contatos"], "mensagens": c["mensagens"],
		"extrato": c["extrato"], "docs": c["docs"], "emprego": c["emprego"], "veiculos": veics, "propriedades": props,
		"casas_vendidas": donos, "pos": c["pos"]}


# ---------- utilidades ----------

func _extrato(c, desc, valor):
	c["extrato"].push_front({"t": int(Time.get_unix_time_from_system()), "desc": desc, "valor": valor})
	while c["extrato"].size() > 30:
		c["extrato"].pop_back()


func _pagar(c, valor, metodo, desc):
	valor = int(valor)
	if valor < 0:
		return false
	if metodo == "cartao":
		if c["banco"] < valor:
			return false
		c["banco"] -= valor
		_extrato(c, desc, -valor)
	else:
		if c["dinheiro"] < valor:
			return false
		c["dinheiro"] -= valor
	if valor >= 1000:
		_log("pagamento " + c["id"] + " " + str(valor) + " " + desc)
	return true


func _add_item(c, id, qtd):
	if not Itens.existe(id) or qtd < 1:
		return false
	if peso_total(c) + Itens.peso(id) * qtd > Itens.CAPACIDADE_KG + 0.001:
		return false
	c["inventario"][id] = int(c["inventario"].get(id, 0)) + qtd
	return true


func _rem_item(c, id, qtd):
	if qtd < 1 or int(c["inventario"].get(id, 0)) < qtd:
		return false
	c["inventario"][id] = int(c["inventario"][id]) - qtd
	if c["inventario"][id] <= 0:
		c["inventario"].erase(id)
	return true


func _pos_de(peer):
	if online.has(peer):
		return online[peer]["pos"]
	return LONGE


func _poi_perto(peer, id) -> Variant:
	var p = Cidade.poi(id)
	if p == null:
		return null
	if _pos_de(peer).distance_to(p["pos"]) <= Cat.RAIO_INTERACAO:
		return p
	return null


func _ok_vec(v):
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z) and abs(v.x) < 100000.0 and abs(v.y) < 100000.0 and abs(v.z) < 100000.0


func _hex(s):
	s = str(s)
	if re_hex.search(s) != null:
		return s.to_lower()
	return ""


func _limpar_texto(s, maximo):
	s = str(s).replace("\n", " ").replace("\r", " ").strip_edges()
	if s.length() > maximo:
		s = s.substr(0, maximo)
	return s


func _veic(vid):
	return mundo["veiculos"].get(str(vid), null)


func _tem_chave(v, c):
	return v["dono"] == c["id"] or c["id"] in v["chaves"]


func _ativo_de(cid):
	for vid in mundo["veiculos"].keys():
		if mundo["veiculos"][vid]["ativo_por"] == cid:
			return vid
	return ""


func _alvo_perto(peer, a, raio):
	var alvo = int(a.get("alvo", -1))
	if alvo == peer or not peer_conta.has(alvo) or not _mesma_sala(peer, alvo):
		return -1
	if _pos_de(alvo).distance_to(_pos_de(peer)) > raio:
		return -1
	return alvo


func _placa():
	var L = "ABCDEFGHJKLMNPRSTUVWXYZ"
	return L.substr(rng.randi() % L.length(), 1) + L.substr(rng.randi() % L.length(), 1) + L.substr(rng.randi() % L.length(), 1) + str(rng.randi() % 10) + L.substr(rng.randi() % L.length(), 1) + str(rng.randi() % 10) + str(rng.randi() % 10)


func _criar_veiculo(cid, modelo, cor, pos, rot, comb):
	var vid = "v" + str(mundo["prox"])
	mundo["prox"] += 1
	mundo["veiculos"][vid] = {"id": vid, "modelo": modelo, "dono": cid, "cor": cor, "placa": _placa(), "comb": comb, "dano": 0.0,
		"trancado": false, "upg_motor": 0, "local": "rua", "pos": [pos.x, pos.y, pos.z], "rot": rot, "ativo_por": "", "chaves": []}
	return vid


# ---------- criacao e visual ----------

func _validar_visual(c, ap, criando):
	if not (ap is Dictionary):
		return null
	var skin = _hex(ap.get("skin", ""))
	var hair = _hex(ap.get("hair", ""))
	if skin == "" or hair == "":
		return null
	var style = int(ap.get("style", 0))
	if style < 0 or style > 2:
		return null
	var roupa = ap.get("roupa", {})
	if not (roupa is Dictionary):
		return null
	var out = {"camisa": "", "calca": "", "chapeu": "", "oculos": "", "mochila": ""}
	for slot in out.keys():
		var id = str(roupa.get(slot, ""))
		if id == "":
			if slot == "camisa" or slot == "calca":
				return null
			continue
		if not Cat.ROUPAS.has(id) or Cat.ROUPAS[id]["slot"] != slot:
			return null
		if criando:
			if slot == "camisa" and not (id in Cat.INICIAIS_CAMISA):
				return null
			if slot != "camisa" and id != "calca_jeans":
				return null
		elif not (id in c["guarda_roupa"]):
			return null
		out[slot] = id
	return {"skin": skin, "hair": hair, "style": style, "roupa": out}


func op_criar_personagem(peer, c, a):
	if c["criado"]:
		return _err("Personagem já criado.")
	var nome = _limpar_texto(a.get("nome", ""), 16)
	if nome.length() < 3:
		return _err("Nome muito curto.")
	var vis = _validar_visual(c, a.get("aparencia", {}), true)
	if vis == null:
		return _err("Aparência inválida.")
	var cor_carro = _hex(a.get("cor_carro", ""))
	if cor_carro == "":
		cor_carro = "#1b4fa0"
	var numero = ""
	for i in range(50):
		numero = "9%04d-%04d" % [rng.randi() % 10000, rng.randi() % 10000]
		if not mundo["numeros"].has(numero):
			break
	if mundo["numeros"].has(numero):
		return _err("Não foi possível gerar um número de telefone. Tente de novo.")
	c["nome"] = nome
	c["numero"] = numero
	c["criado"] = true
	c["criado_em"] = int(Time.get_unix_time_from_system())
	c["dinheiro"] = Cat.DINHEIRO_INICIAL
	c["banco"] = Cat.BANCO_INICIAL
	c["aparencia"] = vis
	c["guarda_roupa"] = [vis["roupa"]["camisa"], "calca_jeans"]
	c["inventario"] = {"agua": 2, "sanduiche": 2}
	c["docs"] = {"rg": {"numero": "%08d" % (rng.randi() % 100000000), "nascimento": "%02d/%02d/%d" % [1 + rng.randi() % 28, 1 + rng.randi() % 12, 1975 + rng.randi() % 30]}, "cnh": null}
	mundo["numeros"][numero] = c["id"]
	var pos = Cidade.SPAWN + Vector3(0, 0.0, 0)
	_criar_veiculo(c["id"], "m4gt3", cor_carro, pos + Vector3(0, 0, 0), deg_to_rad(Cidade.SPAWN_YAW), 40.0)
	_extrato(c, "Saldo inicial", Cat.BANCO_INICIAL)
	_log("personagem criado " + c["id"] + " " + nome)
	return _ok("Personagem criado!")


func op_visual_salvar(peer, c, a):
	var perto = _poi_perto(peer, "roupas") != null
	if not perto:
		for pid in mundo["propriedades"].keys():
			if mundo["propriedades"][pid] == c["id"]:
				var p = Cidade.poi(pid)
				if p != null and _pos_de(peer).distance_to(p["pos"]) <= Cat.RAIO_INTERACAO:
					perto = true
	if not perto:
		return _err("Troque de roupa na loja de roupas ou na sua casa.")
	var vis = _validar_visual(c, a, false)
	if vis == null:
		return _err("Visual inválido (você não tem alguma peça).")
	c["aparencia"] = vis
	return _ok("Visual salvo.")


# ---------- compras, inventario ----------

func op_comprar(peer, c, a):
	var poi = _poi_perto(peer, str(a.get("loja", "")))
	if poi == null:
		return _err("Você está longe da loja.")
	var loja = Cat.LOJAS.get(poi["id"], null)
	if loja == null:
		return _err("Loja inválida.")
	var item = str(a.get("item", ""))
	var qtd = clampi(int(a.get("qtd", 1)), 1, 20)
	var metodo = str(a.get("metodo", "dinheiro"))
	if loja.has("roupas"):
		if not Cat.ROUPAS.has(item):
			return _err("Produto inválido.")
		if item in c["guarda_roupa"]:
			return _err("Você já tem essa peça.")
		if not _pagar(c, Cat.ROUPAS[item]["preco"], metodo, "Compra: " + Cat.ROUPAS[item]["nome"]):
			return _err("Saldo insuficiente.")
		c["guarda_roupa"].append(item)
		return _ok("Comprou " + Cat.ROUPAS[item]["nome"] + ".")
	var itens = loja["itens"]
	if not itens.has(item):
		return _err("Produto indisponível.")
	if peso_total(c) + Itens.peso(item) * qtd > Itens.CAPACIDADE_KG + 0.001:
		return _err("Sua mochila não aguenta esse peso.")
	if not _pagar(c, int(itens[item]) * qtd, metodo, "Compra: " + Itens.nome(item) + " x" + str(qtd)):
		return _err("Saldo insuficiente.")
	_add_item(c, item, qtd)
	return _ok("Comprou " + str(qtd) + "x " + Itens.nome(item) + ".")


func op_usar_item(peer, c, a):
	var item = str(a.get("item", ""))
	if not Itens.existe(item) or int(c["inventario"].get(item, 0)) < 1:
		return _err("Você não tem esse item.")
	var ef = Itens.ITENS[item]["efeito"]
	if ef.has("combustivel") or ef.has("reparo"):
		var vid = _ativo_de(c["id"])
		if vid == "":
			return _err("Tire o veículo da garagem primeiro.")
		var v = _veic(vid)
		var o = online[peer]
		if o["carro_pos"].distance_to(o["pos"]) > 8.0:
			return _err("Chegue perto do seu veículo.")
		if ef.has("combustivel"):
			if v["comb"] >= Cat.TANQUE_L - 0.5:
				return _err("O tanque já está cheio.")
			v["comb"] = min(Cat.TANQUE_L, v["comb"] + float(ef["combustivel"]))
		else:
			if v["dano"] <= 0.5:
				return _err("O veículo não tem dano.")
			v["dano"] = max(0.0, v["dano"] - float(ef["reparo"]))
	else:
		var gasto = false
		for k in ef.keys():
			if float(c[k]) < 100.0:
				gasto = true
		if not gasto:
			return _err("Você não precisa disso agora.")
		for k in ef.keys():
			c[k] = min(100.0, float(c[k]) + float(ef[k]))
	_rem_item(c, item, 1)
	return _ok("Usou " + Itens.nome(item) + ".")


func op_descartar(peer, c, a):
	var item = str(a.get("item", ""))
	var qtd = clampi(int(a.get("qtd", 1)), 1, 999)
	if not _rem_item(c, item, qtd):
		return _err("Quantidade inválida.")
	_log("descarte " + c["id"] + " " + item + " " + str(qtd))
	return _ok("Descartou " + str(qtd) + "x " + Itens.nome(item) + ".")


# ---------- banco e celular ----------

func op_banco_depositar(peer, c, a):
	if _poi_perto(peer, "banco") == null:
		return _err("Vá até o banco.")
	var v = int(a.get("valor", 0))
	if v < 1 or v > c["dinheiro"]:
		return _err("Valor inválido.")
	c["dinheiro"] -= v
	c["banco"] += v
	_extrato(c, "Depósito", v)
	return _ok("Depositou R$ " + str(v) + ".")


func op_banco_sacar(peer, c, a):
	if _poi_perto(peer, "banco") == null:
		return _err("Vá até o banco.")
	var v = int(a.get("valor", 0))
	if v < 1 or v > c["banco"]:
		return _err("Valor inválido.")
	c["banco"] -= v
	c["dinheiro"] += v
	_extrato(c, "Saque", -v)
	return _ok("Sacou R$ " + str(v) + ".")


func op_banco_transferir(peer, c, a):
	var num = str(a.get("numero", "")).strip_edges()
	var v = int(a.get("valor", 0))
	var dest = _conta_por_numero(num)
	if dest == null:
		return _err("Número não encontrado.")
	if dest["id"] == c["id"]:
		return _err("Você não pode transferir para si mesmo.")
	if v < 1 or v > c["banco"]:
		return _err("Valor inválido ou saldo insuficiente.")
	c["banco"] -= v
	dest["banco"] += v
	_extrato(c, "Transferência para " + str(dest["nome"]), -v)
	_extrato(dest, "Transferência de " + str(c["nome"]), v)
	_salvar_conta(dest)
	_log("transferencia " + c["id"] + " -> " + dest["id"] + " " + str(v))
	if conta_peer.has(dest["id"]):
		_aviso(conta_peer[dest["id"]], c["nome"] + " transferiu R$ " + str(v) + " para você.")
		_push_conta(dest["id"])
	return _ok("Transferiu R$ " + str(v) + " para " + str(dest["nome"]) + ".")


func op_contato_add(peer, c, a):
	var num = ""
	var nome = _limpar_texto(a.get("nome", ""), 20)
	if a.has("alvo"):
		var alvo = int(a.get("alvo", -1))
		var ct = _conta_de(alvo)
		if ct == null or alvo == peer or not _mesma_sala(peer, alvo):
			return _err("Jogador inválido.")
		num = str(ct["numero"])
		if nome == "":
			nome = str(ct["nome"])
	else:
		num = str(a.get("numero", "")).strip_edges()
	var dest = _conta_por_numero(num)
	if dest == null:
		return _err("Número não encontrado.")
	if dest["id"] == c["id"]:
		return _err("Esse é o seu número.")
	if nome == "":
		nome = str(dest["nome"])
	for ct2 in c["contatos"]:
		if ct2["numero"] == num:
			return _err("Contato já existe.")
	if c["contatos"].size() >= 50:
		return _err("Lista de contatos cheia.")
	c["contatos"].append({"nome": nome, "numero": num})
	return _ok("Contato adicionado.")


func op_contato_del(peer, c, a):
	var num = str(a.get("numero", ""))
	for i in range(c["contatos"].size()):
		if c["contatos"][i]["numero"] == num:
			c["contatos"].remove_at(i)
			return _ok("Contato removido.")
	return _err("Contato não encontrado.")


func op_msg_enviar(peer, c, a):
	var num = str(a.get("numero", "")).strip_edges()
	var texto = _limpar_texto(a.get("texto", ""), 200)
	var o = online[peer]
	var agora = Time.get_ticks_msec() / 1000.0
	if agora - o["ult_msg"] < 0.5:
		return _err("Calma, você está enviando rápido demais.")
	if texto == "":
		return _err("Mensagem vazia.")
	var dest = _conta_por_numero(num)
	if dest == null:
		return _err("Número não encontrado.")
	if dest["id"] == c["id"]:
		return _err("Você não pode mandar mensagem para si mesmo.")
	o["ult_msg"] = agora
	var m = {"de": c["numero"], "para": dest["numero"], "texto": texto, "t": int(Time.get_unix_time_from_system()), "lida": false}
	c["mensagens"].append(m.duplicate())
	dest["mensagens"].append(m.duplicate())
	for conta in [c, dest]:
		while conta["mensagens"].size() > 200:
			conta["mensagens"].pop_front()
	c["mensagens"][c["mensagens"].size() - 1]["lida"] = true
	_salvar_conta(dest)
	if conta_peer.has(dest["id"]):
		_aviso(conta_peer[dest["id"]], "Mensagem de " + str(c["nome"]) + ": " + texto.substr(0, 40))
		_push_conta(dest["id"])
	return _ok("")


func op_msg_ler(peer, c, a):
	var num = str(a.get("numero", ""))
	for m in c["mensagens"]:
		if m["de"] == num:
			m["lida"] = true
	return _ok("")


func op_estado(peer, c, a):
	return _ok("")


# ---------- propriedades e garagem ----------

func op_prop_comprar(peer, c, a):
	var pid = str(a.get("prop", ""))
	var p = Cidade.poi(pid)
	if p == null or p["tipo"] != "casa":
		return _err("Propriedade inválida.")
	if _pos_de(peer).distance_to(p["pos"]) > Cat.RAIO_INTERACAO:
		return _err("Chegue perto da propriedade.")
	if mundo["propriedades"].has(pid):
		return _err("Esta propriedade já tem dono.")
	if not _pagar(c, p["preco"], str(a.get("metodo", "cartao")), "Compra de " + p["nome"]):
		return _err("Saldo insuficiente.")
	mundo["propriedades"][pid] = c["id"]
	_log("propriedade " + pid + " -> " + c["id"])
	return _ok("Você comprou a " + p["nome"] + "!")


func op_prop_vender(peer, c, a):
	var pid = str(a.get("prop", ""))
	var p = Cidade.poi(pid)
	if p == null or mundo["propriedades"].get(pid, "") != c["id"]:
		return _err("Você não é dono dessa propriedade.")
	if _pos_de(peer).distance_to(p["pos"]) > Cat.RAIO_INTERACAO:
		return _err("Chegue perto da propriedade.")
	for vid in mundo["veiculos"].keys():
		if mundo["veiculos"][vid]["local"] == "garagem:" + pid:
			return _err("Tire os veículos da garagem antes de vender.")
	var valor = int(p["preco"] * Cat.VENDA_CASA)
	mundo["propriedades"].erase(pid)
	c["banco"] += valor
	_extrato(c, "Venda de " + p["nome"], valor)
	_log("venda propriedade " + pid + " " + c["id"] + " " + str(valor))
	return _ok("Vendida por R$ " + str(valor) + " (no banco).")


func _garagem_perto(peer, c, raio) -> Variant:
	var o = online[peer]
	for pid in mundo["propriedades"].keys():
		if mundo["propriedades"][pid] == c["id"]:
			var p = Cidade.poi(pid)
			if p != null and o["pos"].distance_to(p["garagem"]) <= raio:
				return p
	return null


func op_garagem_guardar(peer, c, a):
	var v = _veic(a.get("vid", ""))
	if v == null or v["dono"] != c["id"] or v["ativo_por"] != c["id"]:
		return _err("Veículo inválido.")
	var p = _garagem_perto(peer, c, 30.0)
	if p == null:
		return _err("Vá até a garagem de uma propriedade sua.")
	if online[peer]["carro_pos"].distance_to(p["garagem"]) > 30.0:
		return _err("Leve o veículo até a garagem.")
	var usadas = 0
	for vid in mundo["veiculos"].keys():
		if mundo["veiculos"][vid]["local"] == "garagem:" + p["id"]:
			usadas += 1
	if usadas >= int(p["vagas"]):
		return _err("Garagem cheia.")
	v["local"] = "garagem:" + p["id"]
	v["ativo_por"] = ""
	return _ok("Veículo guardado na " + p["nome"] + ".")


func op_garagem_retirar(peer, c, a):
	var v = _veic(a.get("vid", ""))
	if v == null or v["dono"] != c["id"] or not str(v["local"]).begins_with("garagem:"):
		return _err("Veículo inválido.")
	var pid = str(v["local"]).substr(9)
	var p = Cidade.poi(pid)
	if p == null or mundo["propriedades"].get(pid, "") != c["id"]:
		return _err("Você não é dono dessa garagem.")
	if _pos_de(peer).distance_to(p["garagem"]) > 30.0:
		return _err("Vá até a garagem.")
	if _ativo_de(c["id"]) != "":
		return _err("Você já está com um veículo fora. Estacione ou guarde ele.")
	v["local"] = "rua"
	v["ativo_por"] = c["id"]
	v["pos"] = [p["garagem"].x, p["garagem"].y, p["garagem"].z]
	v["rot"] = atan2(-p["frente"].x, -p["frente"].z)
	return _ok("Veículo retirado.")


# ---------- veiculos e chaves ----------

func op_veiculo_ativar(peer, c, a):
	var v = _veic(a.get("vid", ""))
	if v == null or not _tem_chave(v, c):
		return _err("Você não tem a chave desse veículo.")
	if v["local"] != "rua" or v["ativo_por"] != "":
		return _err("Esse veículo não está disponível na rua.")
	if _ativo_de(c["id"]) != "":
		return _err("Você já está com outro veículo fora. Estacione ele primeiro.")
	var vp = Vector3(float(v["pos"][0]), float(v["pos"][1]), float(v["pos"][2]))
	if v["dono"] != c["id"] and _pos_de(peer).distance_to(vp) > 40.0:
		return _err("Chegue perto do veículo.")
	v["ativo_por"] = c["id"]
	return _ok("Veículo pronto.")


func op_veiculo_estacionar(peer, c, a):
	var v = _veic(a.get("vid", ""))
	if v == null or v["ativo_por"] != c["id"]:
		return _err("Veículo inválido.")
	var o = online[peer]
	if o["carro_pos"] != LONGE:
		v["pos"] = [o["carro_pos"].x, o["carro_pos"].y, o["carro_pos"].z]
		v["rot"] = o["carro_rot"]
	v["ativo_por"] = ""
	v["local"] = "rua"
	return _ok("Veículo estacionado.")


func op_veiculo_trancar(peer, c, a):
	var v = _veic(a.get("vid", ""))
	if v == null or not _tem_chave(v, c):
		return _err("Você não tem a chave.")
	v["trancado"] = bool(a.get("trancar", true))
	if v["trancado"]:
		return _ok("Veículo trancado.")
	return _ok("Veículo destrancado.")


func op_chave_dar(peer, c, a):
	var v = _veic(a.get("vid", ""))
	if v == null or v["dono"] != c["id"]:
		return _err("Só o dono pode dar chaves.")
	var alvo = _alvo_perto(peer, a, 10.0)
	if alvo < 0:
		return _err("Ninguém por perto.")
	var cid = peer_conta[alvo]
	if cid in v["chaves"]:
		return _err("Essa pessoa já tem a chave.")
	if v["chaves"].size() >= 4:
		return _err("Limite de chaves atingido.")
	v["chaves"].append(cid)
	_aviso(alvo, str(c["nome"]) + " te deu a chave de um " + str(Cat.VEICULOS[v["modelo"]]["nome"]) + ".")
	_push(alvo)
	return _ok("Chave entregue.")


func op_chave_tirar(peer, c, a):
	var v = _veic(a.get("vid", ""))
	var cid = str(a.get("conta", ""))
	if v == null or v["dono"] != c["id"] or not (cid in v["chaves"]):
		return _err("Chave inválida.")
	v["chaves"].erase(cid)
	if v["ativo_por"] == cid:
		v["ativo_por"] = ""
	_push_conta(cid)
	return _ok("Chave removida.")


func op_veiculo_comprar(peer, c, a):
	var p = _poi_perto(peer, "concessionaria")
	if p == null:
		return _err("Vá até a concessionária.")
	var modelo = str(a.get("modelo", ""))
	if not Cat.VEICULOS.has(modelo):
		return _err("Modelo inválido.")
	var cor = _hex(a.get("cor", ""))
	if cor == "":
		return _err("Cor inválida.")
	var total = 0
	for vid in mundo["veiculos"].keys():
		if mundo["veiculos"][vid]["dono"] == c["id"]:
			total += 1
	if total >= 8:
		return _err("Limite de veículos atingido.")
	if not _pagar(c, Cat.VEICULOS[modelo]["preco"], str(a.get("metodo", "cartao")), "Compra: " + Cat.VEICULOS[modelo]["nome"]):
		return _err("Saldo insuficiente.")
	var g = p["garagem"]
	_criar_veiculo(c["id"], modelo, cor, g, atan2(-p["frente"].x, -p["frente"].z), 20.0)
	return _ok("Veículo comprado! Ele está na rua, em frente à concessionária.")


func op_veiculo_vender(peer, c, a):
	var vid = str(a.get("vid", ""))
	var v = _veic(vid)
	if v == null or v["dono"] != c["id"]:
		return _err("Veículo inválido.")
	if _poi_perto(peer, "concessionaria") == null:
		return _err("Vá até a concessionária.")
	if v["ativo_por"] != "":
		return _err("Estacione o veículo antes de vender.")
	var valor = int(Cat.VEICULOS[v["modelo"]]["preco"] * Cat.VENDA_VEICULO * (1.0 - float(v["dano"]) / 200.0))
	for i in range(int(v.get("upg_motor", 0))):
		valor += int(Cat.UPGRADE_MOTOR[i] * 0.5)
	mundo["veiculos"].erase(vid)
	c["banco"] += valor
	_extrato(c, "Venda de veículo", valor)
	_log("venda veiculo " + vid + " " + c["id"] + " " + str(valor))
	return _ok("Vendido por R$ " + str(valor) + " (no banco).")


func op_posto_abastecer(peer, c, a):
	if _poi_perto(peer, "posto") == null:
		return _err("Vá até o posto.")
	var vid = _ativo_de(c["id"])
	if vid == "":
		return _err("Você não está com um veículo.")
	var v = _veic(vid)
	var o = online[peer]
	if o["carro_pos"].distance_to(o["pos"]) > 15.0 or o["carro_pos"].distance_to(Cidade.poi("posto")["pos"]) > 40.0:
		return _err("Leve o veículo até o posto.")
	var falta = Cat.TANQUE_L - float(v["comb"])
	var litros = min(float(a.get("litros", falta)), falta)
	if litros < 0.5:
		return _err("O tanque já está cheio.")
	var custo = int(ceil(litros * Cat.PRECO_L))
	if not _pagar(c, custo, str(a.get("metodo", "dinheiro")), "Combustível"):
		return _err("Saldo insuficiente (R$ " + str(custo) + ").")
	v["comb"] = min(Cat.TANQUE_L, float(v["comb"]) + litros)
	return _ok("Abasteceu " + str(snappedf(litros, 0.1)) + " L por R$ " + str(custo) + ".")


func op_oficina_reparar(peer, c, a):
	if _poi_perto(peer, "oficina") == null:
		return _err("Vá até a oficina.")
	var vid = _ativo_de(c["id"])
	if vid == "":
		return _err("Você não está com um veículo.")
	var v = _veic(vid)
	if online[peer]["carro_pos"].distance_to(Cidade.poi("oficina")["pos"]) > 40.0:
		return _err("Leve o veículo até a oficina.")
	if float(v["dano"]) < 1.0:
		return _err("O veículo não tem dano.")
	var custo = int(ceil(float(v["dano"]) * Cat.CUSTO_REPARO_PONTO))
	if c["emprego"] == "mecanico":
		custo = int(custo * 0.7)
	if not _pagar(c, custo, str(a.get("metodo", "dinheiro")), "Reparo de veículo"):
		return _err("Saldo insuficiente (R$ " + str(custo) + ").")
	v["dano"] = 0.0
	return _ok("Veículo reparado por R$ " + str(custo) + ".")


func op_oficina_upgrade(peer, c, a):
	if _poi_perto(peer, "oficina") == null:
		return _err("Vá até a oficina.")
	var vid = _ativo_de(c["id"])
	if vid == "":
		return _err("Você não está com um veículo.")
	var v = _veic(vid)
	if online[peer]["carro_pos"].distance_to(Cidade.poi("oficina")["pos"]) > 40.0:
		return _err("Leve o veículo até a oficina.")
	var nivel = int(v.get("upg_motor", 0))
	if nivel >= Cat.UPGRADE_MOTOR.size():
		return _err("O motor já está no nível máximo.")
	var custo = int(Cat.UPGRADE_MOTOR[nivel])
	if not _pagar(c, custo, str(a.get("metodo", "dinheiro")), "Upgrade de motor nível " + str(nivel + 1)):
		return _err("Saldo insuficiente (R$ " + str(custo) + ").")
	v["upg_motor"] = nivel + 1
	return _ok("Motor melhorado para o nível " + str(nivel + 1) + "!")


func op_oficina_pintar(peer, c, a):
	if _poi_perto(peer, "oficina") == null:
		return _err("Vá até a oficina.")
	var vid = _ativo_de(c["id"])
	if vid == "":
		return _err("Você não está com um veículo.")
	var cor = _hex(a.get("cor", ""))
	if cor == "":
		return _err("Cor inválida.")
	if not _pagar(c, Cat.CUSTO_PINTURA, str(a.get("metodo", "dinheiro")), "Pintura"):
		return _err("Saldo insuficiente.")
	_veic(vid)["cor"] = cor
	return _ok("Pintura feita.")


func op_impacto(peer, c, a):
	var vid = _ativo_de(c["id"])
	if vid == "":
		return _ok("")
	var o = online[peer]
	var agora = Time.get_ticks_msec() / 1000.0
	if agora - o["ult_imp"] < 0.4:
		return _ok("")
	o["ult_imp"] = agora
	var forca = clampf(float(a.get("forca", 0.0)), 0.0, 80.0)
	var v = _veic(vid)
	v["dano"] = min(100.0, float(v["dano"]) + clampf((forca - 8.0) * 1.2, 0.0, 25.0))
	return _ok("")


# ---------- documentos e empregos ----------

func op_cnh_emitir(peer, c, a):
	if _poi_perto(peer, "prefeitura") == null:
		return _err("Vá até a prefeitura.")
	if c["docs"]["cnh"] != null:
		return _err("Você já tem CNH.")
	if not _pagar(c, Cat.PRECO_CNH, str(a.get("metodo", "dinheiro")), "Emissão de CNH"):
		return _err("Saldo insuficiente (R$ " + str(Cat.PRECO_CNH) + ").")
	c["docs"]["cnh"] = {"numero": "%011d" % (rng.randi() % 100000000000), "categoria": "B", "emissao": Time.get_date_string_from_system()}
	return _ok("CNH categoria B emitida.")


func op_emprego(peer, c, a):
	if _poi_perto(peer, "prefeitura") == null:
		return _err("Vá até a prefeitura.")
	var e = str(a.get("emprego", ""))
	if not Cat.EMPREGOS.has(e):
		return _err("Emprego inválido.")
	c["emprego"] = e
	return _ok("Agora você é " + str(Cat.EMPREGOS[e]["nome"]) + ".")


func _doc_publico(ct):
	return {"nome": ct["nome"], "rg": ct["docs"]["rg"], "cnh": ct["docs"]["cnh"], "numero": ct["numero"], "emprego": ct["emprego"]}


func op_doc_consultar(peer, c, a):
	if c["emprego"] != "policial":
		return _err("Só policiais podem consultar documentos.")
	var alvo = _alvo_perto(peer, a, 8.0)
	if alvo < 0:
		return _err("Ninguém por perto.")
	var r = _ok("")
	r["doc"] = _doc_publico(_conta_de(alvo))
	return r


func op_doc_mostrar(peer, c, a):
	var alvo = _alvo_perto(peer, a, 6.0)
	if alvo < 0:
		return _err("Ninguém por perto.")
	Rede.enviar_cliente(alvo, "doc_mostrado", {"doc": _doc_publico(c)})
	return _ok("Documento mostrado.")


# ---------- trocas ----------

func _cancelar_trocas(cid):
	for id in trocas.keys():
		var t = trocas[id]
		if t["de"] == cid or t["para"] == cid:
			trocas.erase(id)


func op_troca_oferecer(peer, c, a):
	var alvo = _alvo_perto(peer, a, 8.0)
	if alvo < 0:
		return _err("Ninguém por perto.")
	var tc = _conta_de(alvo)
	for id in trocas.keys():
		if trocas[id]["de"] == c["id"] or trocas[id]["para"] == c["id"]:
			return _err("Você já tem uma troca em andamento.")
		if trocas[id]["para"] == tc["id"] or trocas[id]["de"] == tc["id"]:
			return _err("Essa pessoa está ocupada.")
	var itens = {}
	var raw = a.get("itens", {})
	if raw is Dictionary:
		for k in raw.keys():
			var q = int(raw[k])
			if q > 0:
				if not Itens.existe(str(k)) or int(c["inventario"].get(str(k), 0)) < q:
					return _err("Você não tem os itens oferecidos.")
				itens[str(k)] = q
	var dar = maxi(0, int(a.get("dinheiro_dar", 0)))
	var pedir = maxi(0, int(a.get("dinheiro_pedir", 0)))
	if dar > c["dinheiro"]:
		return _err("Você não tem esse dinheiro na carteira.")
	if itens.is_empty() and dar == 0 and pedir == 0:
		return _err("Oferta vazia.")
	var id = prox_troca
	prox_troca += 1
	trocas[id] = {"id": id, "de": c["id"], "para": tc["id"], "itens": itens, "dar": dar, "pedir": pedir, "t": Time.get_ticks_msec() / 1000.0}
	Rede.enviar_cliente(alvo, "troca_oferta", {"id": id, "de": c["nome"], "itens": itens, "dar": dar, "pedir": pedir})
	return _ok("Oferta enviada.")


func op_troca_responder(peer, c, a):
	var id = int(a.get("id", -1))
	if not trocas.has(id):
		return _err("Oferta expirada.")
	var t = trocas[id]
	if t["para"] != c["id"]:
		return _err("Essa oferta não é sua.")
	trocas.erase(id)
	var de = _obter_conta(t["de"])
	if de == null:
		return _err("Jogador indisponível.")
	if not bool(a.get("aceitar", false)):
		if conta_peer.has(de["id"]):
			_aviso(conta_peer[de["id"]], str(c["nome"]) + " recusou a troca.")
		return _ok("Troca recusada.")
	if not conta_peer.has(de["id"]) or not _mesma_sala(conta_peer[de["id"]], peer) or _pos_de(conta_peer[de["id"]]).distance_to(_pos_de(peer)) > 12.0:
		return _err("Vocês se afastaram.")
	# valida tudo antes de mexer em qualquer coisa
	for k in t["itens"].keys():
		if int(de["inventario"].get(k, 0)) < int(t["itens"][k]):
			return _err("O outro jogador não tem mais os itens.")
	if de["dinheiro"] < t["dar"]:
		return _err("O outro jogador não tem mais o dinheiro.")
	if c["dinheiro"] < t["pedir"]:
		return _err("Você não tem o dinheiro pedido.")
	var peso_extra = 0.0
	for k in t["itens"].keys():
		peso_extra += Itens.peso(k) * int(t["itens"][k])
	if peso_total(c) + peso_extra > Itens.CAPACIDADE_KG + 0.001:
		return _err("Sua mochila não aguenta esse peso.")
	for k in t["itens"].keys():
		_rem_item(de, k, int(t["itens"][k]))
		_add_item(c, k, int(t["itens"][k]))
	de["dinheiro"] -= t["dar"]
	c["dinheiro"] += t["dar"]
	c["dinheiro"] -= t["pedir"]
	de["dinheiro"] += t["pedir"]
	_salvar_conta(de)
	_log("troca " + de["id"] + " -> " + c["id"] + " " + JSON.stringify(t["itens"]) + " " + str(t["dar"]) + "/" + str(t["pedir"]))
	_aviso(conta_peer[de["id"]], str(c["nome"]) + " aceitou a troca.")
	_push_conta(de["id"])
	return _ok("Troca concluída.")


# ---------- chat ----------

func op_chat(peer, c, a):
	var texto = _limpar_texto(a.get("texto", ""), 140)
	if texto == "":
		return _ok("")
	var o = online[peer]
	var agora = Time.get_ticks_msec() / 1000.0
	if agora - o["ult_chat"] < 0.8:
		return _err("Calma, você está falando rápido demais.")
	o["ult_chat"] = agora
	var canal = "local"
	if str(a.get("canal", "local")) == "global":
		canal = "global"
	var msg = {"canal": canal, "de": c["nome"], "texto": texto}
	for p2 in peer_conta.keys():
		if not _mesma_sala(p2, peer):
			continue # cada servidor tem o seu proprio chat
		if canal == "global" or _pos_de(p2).distance_to(o["pos"]) <= 35.0:
			Rede.enviar_cliente(p2, "chat", msg)
	return _ok("")


# ---------- posicoes, combustivel ----------

func relatar_pos(peer, d):
	if not online.has(peer) or not (d is Dictionary):
		return
	var o = online[peer]
	var agora = Time.get_ticks_msec() / 1000.0
	var dt = clampf(agora - o["t"], 0.001, 1.0)
	o["t"] = agora
	var p = d.get("pos", null)
	if not (p is Vector3) or not _ok_vec(p):
		return
	o["pos"] = p
	o["rot"] = float(d.get("rot", 0.0))
	o["emote"] = clampi(int(d.get("emote", 0)), 0, 3)
	o["em_carro"] = bool(d.get("em_carro", false))
	var c = _conta_de(peer)
	if c == null:
		return
	var vid = _ativo_de(c["id"])
	var cp = d.get("carro_pos", null)
	if vid == "" or not (cp is Vector3) or not _ok_vec(cp):
		o["carro_pos"] = LONGE
		o["carro_vid"] = ""
		return
	var v = _veic(vid)
	if o["carro_vid"] == vid and o["carro_pos"] != LONGE:
		var dist = minf(cp.distance_to(o["carro_pos"]), VEL_MAX * dt)
		if dist > 0.05:
			v["comb"] = maxf(0.0, float(v["comb"]) - dist / 1000.0 * Cat.CONSUMO_L_KM)
	o["carro_vid"] = vid
	o["carro_pos"] = cp
	o["carro_rot"] = float(d.get("carro_rot", 0.0))
	v["pos"] = [cp.x, cp.y, cp.z]
	v["rot"] = o["carro_rot"]
	if agora - o["avisou_comb"] > 2.0:
		o["avisou_comb"] = agora
		Rede.enviar_cliente(peer, "veiculo", {"id": vid, "comb": v["comb"], "dano": v["dano"], "trancado": v["trancado"]})


func _tempo_dict():
	return {"unix": Time.get_unix_time_from_system(), "clima": clima}


# ---------- laco principal ----------

func _process(delta):
	t_save += delta
	t_stats += delta
	t_tempo += delta
	t_remotos += delta
	t_sal += delta
	clima_t += delta
	if t_remotos >= 0.1:
		t_remotos = 0.0
		_enviar_remotos()
	if t_save >= 20.0:
		t_save = 0.0
		salvar_tudo()
	if t_stats >= 30.0:
		t_stats = 0.0
		for peer in peer_conta.keys():
			var c = _conta_de(peer)
			if c != null and c["criado"]:
				c["fome"] = maxf(0.0, float(c["fome"]) - 1.0)
				c["sede"] = maxf(0.0, float(c["sede"]) - 1.5)
				Rede.enviar_cliente(peer, "stats", {"fome": c["fome"], "sede": c["sede"]})
	if t_sal >= Cat.SALARIO_INTERVALO:
		t_sal = 0.0
		for peer in peer_conta.keys():
			var c2 = _conta_de(peer)
			if c2 != null and c2["criado"]:
				var sal = int(Cat.EMPREGOS.get(c2["emprego"], {"salario": 0})["salario"])
				if sal > 0:
					c2["banco"] += sal
					_extrato(c2, "Salário", sal)
					_salvar_conta(c2)
					_aviso(peer, "Salário de R$ " + str(sal) + " depositado no banco.")
					_push(peer)
	if clima_t >= clima_dur:
		clima_t = 0.0
		clima_dur = rng.randf_range(600.0, 1200.0)
		if clima == "sol" and rng.randf() < 0.4:
			clima = "chuva"
		else:
			clima = "sol"
		t_tempo = 30.0
	if t_tempo >= 30.0:
		t_tempo = 0.0
		for peer in peer_conta.keys():
			Rede.enviar_cliente(peer, "tempo", _tempo_dict())
	# ofertas de troca expiram
	var agora = Time.get_ticks_msec() / 1000.0
	for id in trocas.keys():
		if agora - float(trocas[id]["t"]) > 60.0:
			trocas.erase(id)


func _enviar_remotos():
	# cada jogador so recebe quem esta no MESMO servidor
	var por_sala = {}
	for peer in online.keys():
		var c = _conta_de(peer)
		if c == null or not c["criado"]:
			continue
		var o = online[peer]
		var item = {"peer": peer, "nome": c["nome"], "pos": o["pos"], "rot": o["rot"], "emote": o["emote"], "em_carro": o["em_carro"], "ap": c["aparencia"]}
		if o["carro_vid"] != "":
			var v = _veic(o["carro_vid"])
			if v != null:
				item["carro"] = {"pos": o["carro_pos"], "rot": o["carro_rot"], "cor": v["cor"], "placa": v["placa"]}
		var sala = int(o["sala"])
		if not por_sala.has(sala):
			por_sala[sala] = []
		por_sala[sala].append(item)
	for peer in peer_conta.keys():
		if not online.has(peer):
			continue
		var lista = por_sala.get(int(online[peer]["sala"]), [])
		# sozinho na sala: nao manda nada (mas manda uma ultima lista vazia se alguem acabou de sair)
		if lista.size() < 2 and not remotos_ativos.get(peer, false):
			continue
		remotos_ativos[peer] = lista.size() >= 2
		Rede.enviar_remotos(peer, lista)
