extends Node
# Interface do jogo (HUD + celular + inventario + lojas + garagem + visual + documentos + troca + chat).
# Nada aqui altera dados: tudo vira Rede.pedir(...) e a tela se redesenha quando o servidor responde.

const Itens = preload("res://sistema/itens.gd")
const Cat = preload("res://sistema/catalogo.gd")
const Cidade = preload("res://sistema/config_cidade.gd")

const BRANCO = Color("ffffff")
const CINZA = Color("9aa4bd")
const AZUL = Color("3d7be0")
const VERDE = Color("2e9e5b")
const VERMELHO = Color("b03a3a")
const ESCURO = Color("2a3042")
const OURO = Color("f5b301")
# site oficial onde o jogador resgata o codigo de MTP COINS (troque pelo endereco do seu servico de coins)
const SITE_COINS = "https://SEU-SITE-DE-COINS.up.railway.app"
const CORES_CARRO = ["#1b4fa0", "#b01e1e", "#e8e8e8", "#151515", "#e0a000", "#2e8b57"]
const PELES = ["#f5d0b5", "#e0ac86", "#c68a62", "#8d5a3b", "#5c3a24", "#3b2417"]
const CABELOS = ["#1b1b1b", "#4a2f1a", "#a8782e", "#d9c27a", "#c9c9c9", "#a33a1f"]
const ESTILOS = ["Curto", "Coque", "Longo"]
const SLOTS = [["camisa", "Camisa"], ["calca", "Calça"], ["chapeu", "Chapéu"], ["oculos", "Óculos"], ["mochila", "Mochila"]]

var mundo
var cl
var hud_txt
var chat_txt
var gps_txt
var btn_interagir
var hud_botoes = []
var modal = null
var conteudo = null
var refresh_fn = Callable()
var poi = null
var metodo = "dinheiro"
var app = "home"
var id_copiado = false
var msg_num = ""
var chat_linhas = []
var chat_canal = "local"
var entradas = {}
var visual_tmp = {}
var troca = {}
var cor_sel = "#1b4fa0"
var doc_tmp = {}
var oferta_atual = {}
var btn_admin = null
var btn_mic = null
var mic_estado = ""
var adm_aba = "jogador"
var adm_sel = -1
var adm_tempo = 60
var adm_item = "agua"
var adm_modelo = ""
const TEMPOS_ADM = [[10, "10 min"], [30, "30 min"], [60, "1 h"], [360, "6 h"], [1440, "1 dia"], [4320, "3 dias"], [10080, "7 dias"], [43200, "30 dias"], [0, "Permanente"]]


func _ready():
	cl = CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	var s = get_viewport().get_visible_rect().size
	hud_txt = Label.new()
	hud_txt.position = Vector2(20, 96)
	hud_txt.add_theme_font_size_override("font_size", 22)
	cl.add_child(hud_txt)
	gps_txt = Label.new()
	gps_txt.position = Vector2(s.x / 2.0 - 200, 130)
	gps_txt.custom_minimum_size = Vector2(400, 0)
	gps_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gps_txt.add_theme_font_size_override("font_size", 26)
	cl.add_child(gps_txt)
	chat_txt = Label.new()
	chat_txt.position = Vector2(20, 210)
	chat_txt.custom_minimum_size = Vector2(520, 0)
	chat_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_txt.add_theme_font_size_override("font_size", 20)
	cl.add_child(chat_txt)
	var x = s.x - 230
	_hud_botao("CELULAR", Vector2(x, 114), _abrir_celular)
	_hud_botao("MOCHILA", Vector2(x, 182), _abrir_inventario)
	_hud_botao("CHAT", Vector2(x, 250), _abrir_chat)
	_hud_botao("EMOTE", Vector2(x, 318), _abrir_emotes)
	btn_admin = _hud_botao("ADMIN", Vector2(x, 386), _abrir_admin)
	btn_admin.visible = false
	btn_mic = _hud_botao("MIC", Vector2(x - 210, 114), _alternar_mic)
	btn_interagir = _b("INTERAGIR", _abrir_poi, VERDE, Vector2(260, 100), 30)
	btn_interagir.position = Vector2(s.x / 2.0 - 130, s.y - 130)
	btn_interagir.visible = false
	cl.add_child(btn_interagir)
	hud_botoes.append(btn_interagir)
	Rede.estado_mudou.connect(_refrescar)
	Rede.evento.connect(_ao_evento)
	_refrescar()


func _hud_botao(texto, pos, cb):
	var b = _b(texto, cb, Color(0.16, 0.2, 0.3, 0.9), Vector2(200, 60), 24)
	b.position = pos
	cl.add_child(b)
	hud_botoes.append(b)
	return b


func sobre_ui(pos):
	if modal != null:
		return true
	for b in hud_botoes:
		if b.visible and b.get_global_rect().grow(8).has_point(pos):
			return true
	return false


# ---------- pecas de interface ----------

func _est(cor, raio = 14, borda = 0, cor_borda = Color.WHITE):
	var s = StyleBoxFlat.new()
	s.bg_color = cor
	s.set_corner_radius_all(raio)
	if borda > 0:
		s.set_border_width_all(borda)
		s.border_color = cor_borda
	return s


func _b(texto, cb, cor = ESCURO, tam = Vector2(0, 56), fonte = 24):
	var b = Button.new()
	b.text = texto
	b.custom_minimum_size = tam
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fonte)
	for n in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(n, _est(cor, 14))
	b.pressed.connect(cb)
	return b


func _l(texto, tam = 24, cor = BRANCO, expandir = false):
	var l = Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", cor)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if expandir:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _linha(box):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	box.add_child(h)
	return h


func _cor_botao(h, hexa, selecionado, cb):
	var b = Button.new()
	b.custom_minimum_size = Vector2(52, 52)
	b.focus_mode = Control.FOCUS_NONE
	var st = _est(Color(hexa), 12, 5 if selecionado else 0, BRANCO)
	for n in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(n, st)
	b.pressed.connect(cb)
	h.add_child(b)


func _entrada(chave, dica, numerico = false):
	var le = LineEdit.new()
	le.placeholder_text = dica
	le.custom_minimum_size = Vector2(0, 56)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", 24)
	le.text = str(entradas.get(chave, ""))
	le.text_changed.connect(func(t): entradas[chave] = t)
	if numerico:
		le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	return le


func _pedir(op, args = {}):
	Rede.pedir(op, args)


func _pedir_pg(op, args):
	var a = args.duplicate()
	a["metodo"] = metodo
	Rede.pedir(op, a)


func _abrir(titulo, fn, largura = 760):
	_fechar(false)
	var s = get_viewport().get_visible_rect().size
	modal = PanelContainer.new()
	modal.add_theme_stylebox_override("panel", _est(Color(0.07, 0.09, 0.14, 0.97), 24, 2, Color("2f3a57")))
	var altura = min(s.y - 30.0, 660.0)
	modal.custom_minimum_size = Vector2(largura, altura)
	modal.position = Vector2((s.x - largura) / 2.0, (s.y - altura) / 2.0)
	cl.add_child(modal)
	var mg = MarginContainer.new()
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(lado, 16)
	modal.add_child(mg)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	mg.add_child(col)
	var topo = HBoxContainer.new()
	col.add_child(topo)
	topo.add_child(_l(titulo, 30, BRANCO, true))
	topo.add_child(_b("X", _fechar, VERMELHO, Vector2(70, 56)))
	var sc = ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, altura - 110.0)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sc)
	conteudo = VBoxContainer.new()
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.add_theme_constant_override("separation", 8)
	sc.add_child(conteudo)
	refresh_fn = fn
	mundo.ui_modal = true
	fn.call(conteudo)


func _fechar(reverter = true):
	if modal != null:
		modal.queue_free()
		modal = null
	conteudo = null
	refresh_fn = Callable()
	mundo.ui_modal = false
	if reverter and not visual_tmp.is_empty():
		visual_tmp = {}
		mundo.aplicar_visual(Rede.estado.get("aparencia", {}))


func _refrescar():
	var papel = str(Rede.estado.get("papel", "jogador"))
	if btn_admin != null:
		btn_admin.visible = papel != "jogador"
	if modal != null and papel == "jogador" and refresh_fn == _p_admin:
		_fechar()
		return
	if modal == null or not refresh_fn.is_valid() or conteudo == null:
		return
	for c in conteudo.get_children():
		c.queue_free()
	refresh_fn.call(conteudo)


# ---------- eventos do servidor ----------

func _ao_evento(nome, d):
	if nome == "aviso":
		mundo._aviso(str(d.get("msg", "")), 4.0)
	elif nome == "resp":
		if str(d.get("msg", "")) != "":
			mundo._aviso(str(d["msg"]), 3.5)
		if d.has("doc"):
			doc_tmp = d["doc"]
			_abrir("Documento", _p_doc, 620)
		if d.get("ok", false) and d.get("op", "") == "visual_salvar":
			visual_tmp = {}
			_fechar(false)
	elif nome == "chat":
		var pref = "[G] " if d["canal"] == "global" else ""
		chat_linhas.append(pref + str(d["de"]) + ": " + str(d["texto"]))
		while chat_linhas.size() > 6:
			chat_linhas.pop_front()
		chat_txt.text = "\n".join(chat_linhas)
		get_tree().create_timer(20.0).timeout.connect(_limpar_chat_antigo)
	elif nome == "troca_oferta":
		oferta_atual = d
		_abrir("Oferta de troca", _p_oferta, 620)
	elif nome == "doc_mostrado":
		doc_tmp = d["doc"]
		_abrir("Documento mostrado a você", _p_doc, 620)


func _limpar_chat_antigo():
	if chat_linhas.size() > 0:
		chat_linhas.pop_front()
		chat_txt.text = "\n".join(chat_linhas)


func _alternar_mic():
	if mundo.voz != null:
		mundo.voz.alternar()
		_refrescar()


func _estilo_mic(cor):
	for n in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn_mic.add_theme_stylebox_override(n, _est(cor, 14))


func _atualizar_mic():
	if btn_mic == null or mundo.voz == null:
		return
	var online = Rede.modo != "offline"
	btn_mic.visible = online
	var v = mundo.voz
	var est = "off"
	if v.ligado:
		est = "falando" if v.falando else "on"
	if est == mic_estado:
		return
	mic_estado = est
	if est == "off":
		btn_mic.text = "MIC"
		_estilo_mic(Color(0.16, 0.2, 0.3, 0.9))
	elif est == "on":
		btn_mic.text = "MIC LIGADO"
		_estilo_mic(Color(0.12, 0.45, 0.25, 0.95))
	else:
		btn_mic.text = "FALANDO"
		_estilo_mic(Color(0.15, 0.65, 0.3, 1.0))


func atualizar_hud(delta):
	_atualizar_mic()
	var e = Rede.estado
	if e.is_empty():
		return
	var h = Rede.hora_jogo()
	var clima = "chuva" if Rede.clima == "chuva" else "sol"
	var v = Rede.veiculo_ativo()
	var linha_v = ""
	if v != null:
		linha_v = "\nCombustível %d L   Dano %d%%%s" % [int(v["comb"]), int(v["dano"]), "   TRANCADO" if v["trancado"] else ""]
	var linha_c = ""
	if Rede.modo != "offline":
		linha_c = "\nMTP COINS %d" % int(e.get("coins", 0))
	hud_txt.text = "R$ %d   Banco R$ %d%s\nFome %d%%   Sede %d%%\n%02d:%02d %s%s" % [int(e.get("dinheiro", 0)), int(e.get("banco", 0)), linha_c, int(e.get("fome", 0)), int(e.get("sede", 0)), int(h), int((h - floor(h)) * 60.0), clima, linha_v]


func set_poi(p):
	poi = p
	if modal == null and p != null:
		btn_interagir.text = p["nome"]
		btn_interagir.visible = true
	else:
		btn_interagir.visible = false


# ---------- inventario ----------

func _abrir_inventario():
	_abrir("Mochila", _p_inventario)


func _p_inventario(box):
	var e = Rede.estado
	box.add_child(_l("Carteira: R$ %d     Peso: %.1f / %d kg" % [int(e["dinheiro"]), float(e["peso"]), int(e["capacidade"])], 24, CINZA))
	var inv = e["inventario"]
	if inv.is_empty():
		box.add_child(_l("Mochila vazia. Compre itens no mercado.", 24, CINZA))
	for id in inv.keys():
		var h = _linha(box)
		h.add_child(_l("%s x%d" % [Itens.nome(id), int(inv[id])], 26, BRANCO, true))
		h.add_child(_b("Usar", _pedir.bind("usar_item", {"item": id}), VERDE, Vector2(100, 54)))
		h.add_child(_b("Trocar", _abrir_troca.bind(id), AZUL, Vector2(110, 54)))
		h.add_child(_b("Jogar", _pedir.bind("descartar", {"item": id, "qtd": 1}), VERMELHO, Vector2(100, 54)))
		box.add_child(_l(Itens.ITENS[id]["desc"], 20, CINZA))


# ---------- troca ----------

func _abrir_troca(item = ""):
	troca = {"item": item, "qtd": 1 if item != "" else 0, "dar": 0, "pedir": 0}
	_abrir("Troca com jogador", _p_troca, 700)


func _troca_ajuste(chave, delta):
	var v = int(troca[chave]) + delta
	if chave == "qtd":
		var maxq = 0
		if troca["item"] != "":
			maxq = int(Rede.estado["inventario"].get(troca["item"], 0))
		v = clampi(v, 0, maxq)
	else:
		v = maxi(0, v)
	troca[chave] = v
	_refrescar()


func _troca_enviar(alvo):
	var itens = {}
	if troca["item"] != "" and int(troca["qtd"]) > 0:
		itens[troca["item"]] = int(troca["qtd"])
	_pedir("troca_oferecer", {"alvo": alvo, "itens": itens, "dinheiro_dar": int(troca["dar"]), "dinheiro_pedir": int(troca["pedir"])})
	_fechar()


func _p_troca(box):
	var alvo = Rede.jogador_mais_perto(mundo.player.global_position, 8.0)
	if alvo == null:
		box.add_child(_l("Nenhum jogador por perto (até 8 m).", 26, CINZA))
		return
	box.add_child(_l("Trocar com: " + str(alvo["nome"]), 28))
	var h = _linha(box)
	var nome_item = "(sem item)"
	if troca["item"] != "":
		nome_item = Itens.nome(troca["item"])
	h.add_child(_l("Item: %s  x%d" % [nome_item, int(troca["qtd"])], 24, BRANCO, true))
	h.add_child(_b("-", _troca_ajuste.bind("qtd", -1), ESCURO, Vector2(64, 54)))
	h.add_child(_b("+", _troca_ajuste.bind("qtd", 1), ESCURO, Vector2(64, 54)))
	var h2 = _linha(box)
	h2.add_child(_l("Eu dou: R$ %d" % int(troca["dar"]), 24, BRANCO, true))
	h2.add_child(_b("-100", _troca_ajuste.bind("dar", -100), ESCURO, Vector2(90, 54)))
	h2.add_child(_b("+100", _troca_ajuste.bind("dar", 100), ESCURO, Vector2(90, 54)))
	var h3 = _linha(box)
	h3.add_child(_l("Eu peço: R$ %d" % int(troca["pedir"]), 24, BRANCO, true))
	h3.add_child(_b("-100", _troca_ajuste.bind("pedir", -100), ESCURO, Vector2(90, 54)))
	h3.add_child(_b("+100", _troca_ajuste.bind("pedir", 100), ESCURO, Vector2(90, 54)))
	box.add_child(_b("Enviar oferta (o outro jogador precisa aceitar)", _troca_enviar.bind(int(alvo["peer"])), VERDE, Vector2(0, 64)))


func _p_oferta(box):
	var o = oferta_atual
	box.add_child(_l(str(o.get("de", "?")) + " quer fazer uma troca:", 26))
	for k in o.get("itens", {}).keys():
		box.add_child(_l("Ele dá: %dx %s" % [int(o["itens"][k]), Itens.nome(k)], 24, CINZA))
	if int(o.get("dar", 0)) > 0:
		box.add_child(_l("Ele dá: R$ %d" % int(o["dar"]), 24, CINZA))
	if int(o.get("pedir", 0)) > 0:
		box.add_child(_l("Ele pede: R$ %d" % int(o["pedir"]), 24, CINZA))
	var h = _linha(box)
	h.add_child(_b("Aceitar", _responder_oferta.bind(true), VERDE, Vector2(0, 64)))
	h.add_child(_b("Recusar", _responder_oferta.bind(false), VERMELHO, Vector2(0, 64)))
	for c in h.get_children():
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _responder_oferta(aceitar):
	_pedir("troca_responder", {"id": int(oferta_atual.get("id", -1)), "aceitar": aceitar})
	_fechar()


# ---------- chat e emotes ----------

func _abrir_chat():
	_abrir("Chat", _p_chat, 700)


func _enviar_chat():
	var t = str(entradas.get("chat", ""))
	if t.strip_edges() != "":
		_pedir("chat", {"canal": chat_canal, "texto": t})
	entradas["chat"] = ""
	_fechar()


func _trocar_canal():
	chat_canal = "global" if chat_canal == "local" else "local"
	_refrescar()


func _p_chat(box):
	box.add_child(_l("Canal local: quem está a até 35 m. Global: todos.", 20, CINZA))
	box.add_child(_b("Canal: " + chat_canal.to_upper() + " (toque para trocar)", _trocar_canal, AZUL))
	box.add_child(_entrada("chat", "Digite sua mensagem"))
	box.add_child(_b("Enviar", _enviar_chat, VERDE, Vector2(0, 64)))


func _abrir_emotes():
	_abrir("Interações", _p_emotes, 520)


func _emote(id):
	mundo.set_emote(id)
	_fechar()


func _p_emotes(box):
	box.add_child(_b("Acenar", _emote.bind(1), AZUL, Vector2(0, 64)))
	box.add_child(_b("Cumprimentar", _emote.bind(2), AZUL, Vector2(0, 64)))
	box.add_child(_b("Sentar", _emote.bind(3), AZUL, Vector2(0, 64)))
	box.add_child(_b("Parar", _emote.bind(0), ESCURO, Vector2(0, 64)))
	box.add_child(_l("Os outros jogadores veem a sua animação. Ao andar, ela para.", 20, CINZA))


# ---------- celular ----------

func _abrir_celular():
	app = "home"
	id_copiado = false
	_abrir("Celular  " + str(Rede.estado.get("numero", "")), _p_celular, 480)


func _app(nome):
	app = nome
	_refrescar()


func _p_celular(box):
	if app == "home":
		var apps = [["Contatos", "contatos"], ["Mensagens", "mensagens"], ["Banco", "banco"], ["GPS", "gps"], ["Veículos", "veiculos"], ["Documentos", "docs"], ["MTP COINS", "coins"], ["Configurações", "config"]]
		for a in apps:
			box.add_child(_b(a[0], _app.bind(a[1]), AZUL, Vector2(0, 64), 28))
		return
	box.add_child(_b("< Voltar", _app.bind("home"), ESCURO, Vector2(0, 52)))
	if app == "contatos":
		_app_contatos(box)
	elif app == "mensagens":
		_app_mensagens(box)
	elif app == "banco":
		_app_banco(box)
	elif app == "gps":
		_app_gps(box)
	elif app == "veiculos":
		_app_veiculos(box)
	elif app == "docs":
		_app_docs(box)
	elif app == "coins":
		_app_coins(box)
	elif app == "config":
		_app_config(box)


func _abrir_msg(num):
	msg_num = num
	app = "mensagens"
	_pedir("msg_ler", {"numero": num})
	_refrescar()


func _contato_add_num():
	_pedir("contato_add", {"numero": str(entradas.get("c_num", "")), "nome": str(entradas.get("c_nome", ""))})
	entradas["c_num"] = ""
	entradas["c_nome"] = ""


func _app_contatos(box):
	box.add_child(_l("Contatos", 28))
	for c in Rede.estado["contatos"]:
		var h = _linha(box)
		h.add_child(_l(str(c["nome"]) + "\n" + str(c["numero"]), 22, BRANCO, true))
		h.add_child(_b("Msg", _abrir_msg.bind(c["numero"]), VERDE, Vector2(90, 54)))
		h.add_child(_b("X", _pedir.bind("contato_del", {"numero": c["numero"]}), VERMELHO, Vector2(64, 54)))
	box.add_child(_l("Adicionar por número", 24, CINZA))
	box.add_child(_entrada("c_nome", "Nome"))
	box.add_child(_entrada("c_num", "Número (ex: 91234-5678)"))
	box.add_child(_b("Adicionar", _contato_add_num, VERDE))
	box.add_child(_l("Jogadores online", 24, CINZA))
	for peer in Rede.remotos.keys():
		var r = Rede.remotos[peer]
		var h2 = _linha(box)
		h2.add_child(_l(str(r["nome"]), 22, BRANCO, true))
		h2.add_child(_b("Adicionar", _pedir.bind("contato_add", {"alvo": int(peer)}), VERDE, Vector2(150, 54)))
	if Rede.remotos.is_empty():
		box.add_child(_l("Ninguém mais online.", 20, CINZA))


func _msg_enviar():
	_pedir("msg_enviar", {"numero": msg_num, "texto": str(entradas.get("msg", ""))})
	entradas["msg"] = ""


func _nome_do_numero(num):
	for c in Rede.estado["contatos"]:
		if c["numero"] == num:
			return str(c["nome"])
	return str(num)


func _app_mensagens(box):
	if msg_num == "":
		box.add_child(_l("Conversas", 28))
		var vistos = []
		var msgs = Rede.estado["mensagens"]
		for i in range(msgs.size() - 1, -1, -1):
			var m = msgs[i]
			var outro = m["para"] if m["de"] == Rede.estado["numero"] else m["de"]
			if outro in vistos:
				continue
			vistos.append(outro)
			var marca = "" if (m["lida"] or m["de"] == Rede.estado["numero"]) else "(nova) "
			box.add_child(_b(marca + _nome_do_numero(outro) + ": " + str(m["texto"]).substr(0, 30), _abrir_msg.bind(outro), ESCURO, Vector2(0, 60), 22))
		if vistos.is_empty():
			box.add_child(_l("Nenhuma mensagem. Abra um contato e toque em Msg.", 22, CINZA))
		return
	box.add_child(_b("< Conversas", _sair_conversa, ESCURO, Vector2(0, 48)))
	box.add_child(_l("Conversa com " + _nome_do_numero(msg_num), 26))
	for m in Rede.estado["mensagens"]:
		if m["de"] == msg_num or m["para"] == msg_num:
			var meu = m["de"] == Rede.estado["numero"]
			var l = _l(("Você: " if meu else "Ele: ") + str(m["texto"]), 22, AZUL if meu else BRANCO)
			box.add_child(l)
	box.add_child(_entrada("msg", "Mensagem"))
	box.add_child(_b("Enviar", _msg_enviar, VERDE))


func _sair_conversa():
	msg_num = ""
	_refrescar()


func _transferir():
	_pedir("banco_transferir", {"numero": str(entradas.get("t_num", "")), "valor": int(str(entradas.get("t_val", "0")).to_int())})
	entradas["t_val"] = ""


func _app_banco(box):
	box.add_child(_l("Saldo no banco: R$ %d" % int(Rede.estado["banco"]), 30, VERDE))
	box.add_child(_l("Carteira: R$ %d   (depósito/saque só nos caixas do banco)" % int(Rede.estado["dinheiro"]), 20, CINZA))
	box.add_child(_l("Transferir (PIX)", 26))
	box.add_child(_entrada("t_num", "Número do destinatário"))
	box.add_child(_entrada("t_val", "Valor", true))
	box.add_child(_b("Transferir", _transferir, VERDE))
	box.add_child(_l("Extrato", 26))
	for x in Rede.estado["extrato"]:
		var v = int(x["valor"])
		box.add_child(_l("%s   %s R$ %d" % [str(x["desc"]), "+" if v >= 0 else "-", abs(v)], 20, VERDE if v >= 0 else VERMELHO))


func _copiar_id():
	DisplayServer.clipboard_set(str(Rede.conta_id))
	id_copiado = true
	_refrescar()


func _abrir_site_coins():
	OS.shell_open(SITE_COINS)


func _app_coins(box):
	box.add_child(_l("MTP COINS", 28, OURO))
	if Rede.modo == "offline":
		box.add_child(_l("Os MTP COINS só existem nos servidores online.", 20, CINZA))
		return
	box.add_child(_l("Saldo: %d" % int(Rede.estado.get("coins", 0)), 34, OURO))
	box.add_child(_l("Como resgatar", 24))
	box.add_child(_l("1. Compre um código com a administração.", 20, CINZA))
	box.add_child(_l("2. Abra o site oficial e cole o código e o seu ID.", 20, CINZA))
	box.add_child(_l("3. Os coins chegam aqui em até 1 minuto.", 20, CINZA))
	box.add_child(_l("Seu ID da conta (toque em COPIAR e cole no site):", 20, CINZA))
	var idl = _l(str(Rede.conta_id), 22, BRANCO)
	idl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	box.add_child(idl)
	box.add_child(_b("ID COPIADO!" if id_copiado else "COPIAR ID", _copiar_id, OURO, Vector2(0, 60), 26))
	box.add_child(_b("ABRIR SITE DE RESGATE", _abrir_site_coins, AZUL, Vector2(0, 56), 22))
	box.add_child(_l("Histórico", 26))
	var hist = Rede.estado.get("coins_hist", [])
	if hist.is_empty():
		box.add_child(_l("Nenhum resgate ainda.", 20, CINZA))
	for x in hist:
		var v = int(x["valor"])
		box.add_child(_l("%s   %s %d" % [str(x["desc"]), "+" if v >= 0 else "-", abs(v)], 20, VERDE if v >= 0 else VERMELHO))


func _app_gps(box):
	box.add_child(_l("Para onde?", 28))
	if mundo.waypoint != null:
		box.add_child(_b("Cancelar GPS", _gps_ir.bind(Vector3.ZERO, "", true), VERMELHO))
	for p in Cidade.POIS:
		if p["tipo"] != "casa":
			box.add_child(_b(str(p["nome"]), _gps_ir.bind(p["pos"], p["nome"], false), ESCURO))
	for pid in Rede.estado["propriedades"]:
		var p2 = Cidade.poi(pid)
		box.add_child(_b("Minha " + str(p2["nome"]), _gps_ir.bind(p2["pos"], p2["nome"], false), ESCURO))
	for v in Rede.estado["veiculos"]:
		if v["local"] == "rua" and not v["ativo"] and v["pos"].size() == 3:
			var vp = Vector3(float(v["pos"][0]), float(v["pos"][1]), float(v["pos"][2]))
			box.add_child(_b("Veículo " + str(v["placa"]), _gps_ir.bind(vp, "Veículo " + str(v["placa"]), false), ESCURO))


func _gps_ir(pos, nome, cancelar):
	if cancelar:
		mundo.definir_waypoint(null, "")
	else:
		mundo.definir_waypoint(pos, nome)
	_fechar()


func _nome_modelo(m):
	if Cat.VEICULOS.has(m):
		return str(Cat.VEICULOS[m]["nome"])
	return str(m)


func _app_veiculos(box):
	box.add_child(_l("Meus veículos", 28))
	if Rede.estado["veiculos"].is_empty():
		box.add_child(_l("Você não tem veículos.", 22, CINZA))
	for v in Rede.estado["veiculos"]:
		box.add_child(_l("%s  [%s]%s\nCombustível %d L  Dano %d%%  %s" % [_nome_modelo(v["modelo"]), str(v["placa"]), "" if v["minha"] else "  (chave de " + str(v["dono_nome"]) + ")", int(v["comb"]), int(v["dano"]), "TRANCADO" if v["trancado"] else "destrancado"], 22))
		var loc = "Em uso" if v["ativo"] else ("Na garagem" if str(v["local"]).begins_with("garagem") else "Na rua")
		box.add_child(_l("Local: " + loc, 20, CINZA))
		var h = _linha(box)
		if v["ativo"]:
			h.add_child(_b("Estacionar", _pedir.bind("veiculo_estacionar", {"vid": v["id"]}), AZUL, Vector2(0, 54), 20))
			h.add_child(_b("Guardar", _pedir.bind("garagem_guardar", {"vid": v["id"]}), AZUL, Vector2(0, 54), 20))
			h.add_child(_b("Trazer", _trazer_carro, VERDE, Vector2(0, 54), 20))
		elif v["local"] == "rua":
			h.add_child(_b("Chamar", _pedir.bind("veiculo_ativar", {"vid": v["id"]}), VERDE, Vector2(0, 54), 20))
		else:
			h.add_child(_b("Retirar", _pedir.bind("garagem_retirar", {"vid": v["id"]}), VERDE, Vector2(0, 54), 20))
		h.add_child(_b("Destrancar" if v["trancado"] else "Trancar", _pedir.bind("veiculo_trancar", {"vid": v["id"], "trancar": not v["trancado"]}), ESCURO, Vector2(0, 54), 20))
		for c in h.get_children():
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if v["minha"]:
			var alvo = Rede.jogador_mais_perto(mundo.player.global_position, 10.0)
			if alvo != null:
				box.add_child(_b("Dar chave a " + str(alvo["nome"]), _pedir.bind("chave_dar", {"vid": v["id"], "alvo": int(alvo["peer"])}), AZUL, Vector2(0, 50), 20))
			for k in v["chaves"]:
				box.add_child(_b("Tirar chave de " + str(k["nome"]), _pedir.bind("chave_tirar", {"vid": v["id"], "conta": k["conta"]}), VERMELHO, Vector2(0, 50), 20))


func _trazer_carro():
	mundo.trazer_carro()
	_fechar()


func _fmt_doc_rg(d):
	return d["rg"]


func _app_docs(box):
	var e = Rede.estado
	box.add_child(_l("Meus documentos", 28))
	box.add_child(_l("Nome: %s\nRG: %s\nNascimento: %s\nTelefone: %s\nEmprego: %s" % [str(e["nome"]), str(e["docs"]["rg"].get("numero", "")), str(e["docs"]["rg"].get("nascimento", "")), str(e["numero"]), str(Cat.EMPREGOS.get(e["emprego"], {"nome": "?"})["nome"])], 22))
	var cnh = e["docs"]["cnh"]
	if cnh == null:
		box.add_child(_l("CNH: não possui (emita na prefeitura)", 22, CINZA))
	else:
		box.add_child(_l("CNH: %s  categoria %s  emitida em %s" % [str(cnh["numero"]), str(cnh["categoria"]), str(cnh["emissao"])], 22))
	var alvo = Rede.jogador_mais_perto(mundo.player.global_position, 6.0)
	if alvo != null:
		box.add_child(_b("Mostrar documentos a " + str(alvo["nome"]), _pedir.bind("doc_mostrar", {"alvo": int(alvo["peer"])}), AZUL))
		if e["emprego"] == "policial":
			box.add_child(_b("Consultar documentos de " + str(alvo["nome"]), _pedir.bind("doc_consultar", {"alvo": int(alvo["peer"])}), VERDE))
	else:
		box.add_child(_l("Chegue perto de outro jogador para mostrar/consultar documentos.", 20, CINZA))


func _p_doc(box):
	var d = doc_tmp
	var rg = d.get("rg", {})
	box.add_child(_l("Nome: %s\nRG: %s\nNascimento: %s\nTelefone: %s\nEmprego: %s" % [str(d.get("nome", "")), str(rg.get("numero", "")), str(rg.get("nascimento", "")), str(d.get("numero", "")), str(Cat.EMPREGOS.get(d.get("emprego", "civil"), {"nome": "?"})["nome"])], 24))
	var cnh = d.get("cnh", null)
	if cnh == null:
		box.add_child(_l("CNH: NÃO POSSUI", 24, VERMELHO))
	else:
		box.add_child(_l("CNH: %s  categoria %s  emitida em %s" % [str(cnh["numero"]), str(cnh["categoria"]), str(cnh["emissao"])], 24, VERDE))


func _app_config(box):
	box.add_child(_l("Gráficos (para celulares fracos)", 26))
	var nomes = ["Baixo", "Médio", "Alto"]
	for i in range(3):
		box.add_child(_b(nomes[i] + (" (ativo)" if mundo.gfx == i else ""), _gfx.bind(i), AZUL if mundo.gfx == i else ESCURO))
	box.add_child(_l("Baixo: sem sombras, menos NPCs, sem partículas de chuva e alcance de visão menor.", 20, CINZA))
	box.add_child(_l("Chat de voz", 26))
	if Rede.modo == "offline":
		box.add_child(_l("Só funciona nos servidores online.", 20, CINZA))
	else:
		var voz = mundo.voz
		box.add_child(_b("Microfone: " + ("LIGADO (toque para desligar)" if voz.ligado else "desligado (toque para ligar)"), _alternar_mic, VERDE if voz.ligado else AZUL, Vector2(0, 60), 22))
		box.add_child(_l("Quem estiver até 40 m ouve você. Use fones de ouvido para não dar eco. No PC: tecla V.", 18, CINZA))
		box.add_child(_l("Sensibilidade do microfone", 22, CINZA))
		var hs = _linha(box)
		for i in range(3):
			var bs = _b(str(voz.SENSIB_NOMES[i]), _voz_sensib.bind(i), AZUL if voz.sensib == i else ESCURO, Vector2(0, 52), 20)
			bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hs.add_child(bs)
		box.add_child(_l("Volume das vozes", 22, CINZA))
		var hv = _linha(box)
		for i in range(3):
			var bv = _b(str(voz.VOLUME_NOMES[i]), _voz_vol.bind(i), AZUL if voz.vol_i == i else ESCURO, Vector2(0, 52), 20)
			bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hv.add_child(bv)
		box.add_child(_l("Enviado: %d KB   Recebido: %d KB" % [int(voz.bytes_enviados / 1024), int(voz.bytes_recebidos / 1024)], 18, CINZA))
	box.add_child(_l("Áudio do carro", 26))
	for n in ["motor", "buzina", "derrapagem", "batida", "porta"]:
		box.add_child(_l(n + ": " + str(mundo.audio_diag.get(n, "?")), 18, CINZA))
	box.add_child(_b("Testar som (buzina)", _testar_som, AZUL))


func _voz_sensib(i):
	mundo.voz.set_sensib(i)
	_refrescar()


func _voz_vol(i):
	mundo.voz.set_volume(i)
	_refrescar()


func _testar_som():
	mundo.testar_audio()


func _gfx(n):
	mundo.aplicar_graficos(n)
	_refrescar()


# ---------- pontos do mapa ----------

func _abrir_poi():
	if poi == null:
		return
	var t = poi["tipo"]
	if t == "banco":
		_abrir(poi["nome"], _p_banco, 620)
	elif t == "mercado" or t == "roupas":
		_abrir(poi["nome"], _p_loja, 700)
	elif t == "posto":
		_abrir(poi["nome"], _p_posto, 620)
	elif t == "oficina":
		_abrir(poi["nome"], _p_oficina, 700)
	elif t == "concessionaria":
		_abrir(poi["nome"], _p_conc, 700)
	elif t == "prefeitura":
		_abrir(poi["nome"], _p_pref, 640)
	elif t == "casa":
		_abrir(poi["nome"], _p_casa, 700)


func _p_banco(box):
	box.add_child(_l("Banco: R$ %d     Carteira: R$ %d" % [int(Rede.estado["banco"]), int(Rede.estado["dinheiro"])], 26))
	box.add_child(_l("Depositar", 24, CINZA))
	var h = _linha(box)
	for v in [100, 500, 1000]:
		h.add_child(_b(str(v), _pedir.bind("banco_depositar", {"valor": v}), VERDE, Vector2(0, 56)))
	h.add_child(_b("Tudo", _pedir.bind("banco_depositar", {"valor": int(Rede.estado["dinheiro"])}), VERDE, Vector2(0, 56)))
	box.add_child(_l("Sacar", 24, CINZA))
	var h2 = _linha(box)
	for v in [100, 500, 1000]:
		h2.add_child(_b(str(v), _pedir.bind("banco_sacar", {"valor": v}), AZUL, Vector2(0, 56)))
	h2.add_child(_b("Tudo", _pedir.bind("banco_sacar", {"valor": int(Rede.estado["banco"])}), AZUL, Vector2(0, 56)))
	for c in h.get_children():
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in h2.get_children():
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _metodo_botao(box):
	box.add_child(_b("Pagar com: " + ("CARTÃO (banco)" if metodo == "cartao" else "DINHEIRO (carteira)") + "   (toque para trocar)", _trocar_metodo, ESCURO, Vector2(0, 52), 20))


func _trocar_metodo():
	metodo = "dinheiro" if metodo == "cartao" else "cartao"
	_refrescar()


func _p_loja(box):
	_metodo_botao(box)
	var loja = Cat.LOJAS.get(poi["id"], null)
	if loja == null:
		return
	if loja.has("roupas"):
		box.add_child(_b("Provador / trocar de roupa", _abrir_visual, AZUL, Vector2(0, 60)))
		for id in Cat.ROUPAS.keys():
			if id in Rede.estado["guarda_roupa"]:
				continue
			var r = Cat.ROUPAS[id]
			var h = _linha(box)
			h.add_child(_l("%s   R$ %d" % [str(r["nome"]), int(r["preco"])], 24, BRANCO, true))
			h.add_child(_b("Comprar", _pedir_pg.bind("comprar", {"loja": poi["id"], "item": id}), VERDE, Vector2(150, 54)))
		return
	for id in loja["itens"].keys():
		var h2 = _linha(box)
		h2.add_child(_l("%s   R$ %d" % [Itens.nome(id), int(loja["itens"][id])], 24, BRANCO, true))
		h2.add_child(_b("Comprar", _pedir_pg.bind("comprar", {"loja": poi["id"], "item": id, "qtd": 1}), VERDE, Vector2(150, 54)))
		box.add_child(_l(Itens.ITENS[id]["desc"], 18, CINZA))


func _p_posto(box):
	_metodo_botao(box)
	var v = Rede.veiculo_ativo()
	if v == null:
		box.add_child(_l("Traga seu veículo até o posto.", 24, CINZA))
		return
	box.add_child(_l("Combustível: %d / %d L     R$ %d por litro" % [int(v["comb"]), int(Cat.TANQUE_L), Cat.PRECO_L], 24))
	box.add_child(_b("Abastecer 10 L", _pedir_pg.bind("posto_abastecer", {"litros": 10.0}), VERDE, Vector2(0, 60)))
	box.add_child(_b("Encher o tanque", _pedir_pg.bind("posto_abastecer", {"litros": 100.0}), VERDE, Vector2(0, 60)))


func _cor_oficina(hexa):
	cor_sel = hexa
	_refrescar()


func _p_oficina(box):
	_metodo_botao(box)
	var v = Rede.veiculo_ativo()
	if v == null:
		box.add_child(_l("Traga seu veículo até a oficina.", 24, CINZA))
		return
	var custo = int(ceil(float(v["dano"]) * Cat.CUSTO_REPARO_PONTO))
	if Rede.estado["emprego"] == "mecanico":
		custo = int(custo * 0.7)
	box.add_child(_l("Dano: %d%%" % int(v["dano"]), 26))
	box.add_child(_b("Reparar tudo  (R$ %d)" % custo, _pedir_pg.bind("oficina_reparar", {}), VERDE, Vector2(0, 60)))
	var nivel = int(v.get("upg_motor", 0))
	box.add_child(_l("Motor: nível %d de %d  (+%d%% de velocidade por nível)" % [nivel, Cat.UPGRADE_MOTOR.size(), int(Cat.UPGRADE_VEL * 100.0)], 24))
	if nivel < Cat.UPGRADE_MOTOR.size():
		box.add_child(_b("Melhorar motor para o nível %d  (R$ %d)" % [nivel + 1, int(Cat.UPGRADE_MOTOR[nivel])], _pedir_pg.bind("oficina_upgrade", {}), AZUL, Vector2(0, 60)))
	else:
		box.add_child(_l("Motor no nível máximo.", 22, CINZA))
	box.add_child(_l("Pintura  (R$ %d)" % Cat.CUSTO_PINTURA, 24, CINZA))
	var h = _linha(box)
	for c in CORES_CARRO:
		_cor_botao(h, c, c == cor_sel, _cor_oficina.bind(c))
	box.add_child(_b("Pintar com a cor escolhida", _pedir_pg.bind("oficina_pintar", {"cor": cor_sel}), AZUL, Vector2(0, 60)))
	box.add_child(_l("Peças: kits de reparo e galões vendem no mercado.", 18, CINZA))


func _p_conc(box):
	_metodo_botao(box)
	box.add_child(_l("Cor", 24, CINZA))
	var h = _linha(box)
	for c in CORES_CARRO:
		_cor_botao(h, c, c == cor_sel, _cor_oficina.bind(c))
	for m in Cat.VEICULOS.keys():
		box.add_child(_b("Comprar %s  R$ %d" % [str(Cat.VEICULOS[m]["nome"]), int(Cat.VEICULOS[m]["preco"])], _pedir_pg.bind("veiculo_comprar", {"modelo": m, "cor": cor_sel}), VERDE, Vector2(0, 60)))
	box.add_child(_l("Vender veículo (60% do valor, desconta o dano; cai no banco)", 22, CINZA))
	for v in Rede.estado["veiculos"]:
		if v["minha"] and not v["ativo"]:
			box.add_child(_b("Vender %s [%s]" % [_nome_modelo(v["modelo"]), str(v["placa"])], _pedir.bind("veiculo_vender", {"vid": v["id"]}), VERMELHO, Vector2(0, 56), 22))


func _p_pref(box):
	_metodo_botao(box)
	var cnh = Rede.estado["docs"]["cnh"]
	if cnh == null:
		box.add_child(_b("Emitir CNH  (R$ %d)" % Cat.PRECO_CNH, _pedir_pg.bind("cnh_emitir", {}), VERDE, Vector2(0, 60)))
	else:
		box.add_child(_l("Você já tem CNH.", 24, CINZA))
	box.add_child(_l("Empregos", 26))
	for e in Cat.EMPREGOS.keys():
		var txt = "%s  (salário R$ %d a cada 10 min online)" % [str(Cat.EMPREGOS[e]["nome"]), int(Cat.EMPREGOS[e]["salario"])]
		var atual = Rede.estado["emprego"] == e
		box.add_child(_b(txt + (" (ativo)" if atual else ""), _pedir.bind("emprego", {"emprego": e}), AZUL if atual else ESCURO, Vector2(0, 60), 20))


func _p_casa(box):
	_metodo_botao(box)
	var meu = poi["id"] in Rede.estado["propriedades"]
	var vendida = Rede.estado["casas_vendidas"].has(poi["id"])
	box.add_child(_l("%s   Garagem: %d vagas" % [str(poi["nome"]), int(poi["vagas"])], 26))
	if not meu and vendida:
		box.add_child(_l("Esta propriedade já tem dono.", 24, CINZA))
		return
	if not meu:
		box.add_child(_l("À venda por R$ %d" % int(poi["preco"]), 26, VERDE))
		box.add_child(_b("Comprar propriedade", _pedir_pg.bind("prop_comprar", {"prop": poi["id"]}), VERDE, Vector2(0, 64)))
		return
	box.add_child(_b("Guarda-roupa (trocar visual)", _abrir_visual, AZUL, Vector2(0, 60)))
	box.add_child(_l("Garagem", 26))
	for v in Rede.estado["veiculos"]:
		if not v["minha"]:
			continue
		if v["ativo"]:
			box.add_child(_b("Guardar %s [%s]" % [_nome_modelo(v["modelo"]), str(v["placa"])], _pedir.bind("garagem_guardar", {"vid": v["id"]}), VERDE, Vector2(0, 56), 22))
		elif v["local"] == "garagem:" + str(poi["id"]):
			box.add_child(_b("Retirar %s [%s]" % [_nome_modelo(v["modelo"]), str(v["placa"])], _pedir.bind("garagem_retirar", {"vid": v["id"]}), AZUL, Vector2(0, 56), 22))
	box.add_child(_b("Vender propriedade (70%)", _pedir.bind("prop_vender", {"prop": poi["id"]}), VERMELHO, Vector2(0, 56), 22))


# ---------- visual / guarda-roupa ----------

func _abrir_visual():
	var ap = Rede.estado.get("aparencia", {})
	visual_tmp = ap.duplicate(true)
	_abrir("Visual", _p_visual, 720)


func _vis_set(chave, valor):
	visual_tmp[chave] = valor
	mundo.aplicar_visual(visual_tmp)
	_refrescar()


func _vis_roupa(slot, id):
	var r = visual_tmp["roupa"].duplicate()
	r[slot] = id
	visual_tmp["roupa"] = r
	mundo.aplicar_visual(visual_tmp)
	_refrescar()


func _vis_salvar():
	_pedir("visual_salvar", visual_tmp)


func _p_visual(box):
	if visual_tmp.is_empty():
		return
	box.add_child(_l("Pele", 24, CINZA))
	var h = _linha(box)
	for c in PELES:
		_cor_botao(h, c, c == visual_tmp["skin"], _vis_set.bind("skin", c))
	box.add_child(_l("Cabelo", 24, CINZA))
	var h2 = _linha(box)
	for c in CABELOS:
		_cor_botao(h2, c, c == visual_tmp["hair"], _vis_set.bind("hair", c))
	var h3 = _linha(box)
	for i in range(3):
		var b = _b(ESTILOS[i], _vis_set.bind("style", i), AZUL if visual_tmp["style"] == i else ESCURO, Vector2(120, 52), 22)
		h3.add_child(b)
	for s in SLOTS:
		box.add_child(_l(s[1], 24, CINZA))
		var flow = HFlowContainer.new()
		box.add_child(flow)
		if s[0] != "camisa" and s[0] != "calca":
			flow.add_child(_b("Nenhum", _vis_roupa.bind(s[0], ""), AZUL if visual_tmp["roupa"][s[0]] == "" else ESCURO, Vector2(0, 52), 20))
		for id in Rede.estado["guarda_roupa"]:
			if Cat.ROUPAS[id]["slot"] == s[0]:
				var sel = visual_tmp["roupa"][s[0]] == id
				flow.add_child(_b(str(Cat.ROUPAS[id]["nome"]), _vis_roupa.bind(s[0], id), AZUL if sel else ESCURO, Vector2(0, 52), 20))
	box.add_child(_b("Salvar visual", _vis_salvar, VERDE, Vector2(0, 64)))


# ---------- painel de administracao ----------

func _abrir_admin():
	_pedir("admin_atualizar")
	_abrir("Painel Admin", _p_admin, 900)


func _adm_info():
	return Rede.estado.get("adm", {})


func _adm_online():
	return _adm_info().get("online", [])


func _adm_aba_set(aba):
	adm_aba = aba
	_refrescar()


func _adm_escolher(peer):
	adm_sel = peer
	_refrescar()


func _adm_alvo():
	for j in _adm_online():
		if int(j["peer"]) == adm_sel:
			return {"alvo": adm_sel}
	var num = str(entradas.get("adm_num", "")).strip_edges()
	if num != "":
		return {"numero": num}
	return {}


func _adm_pedir(op, extra = {}):
	var args = _adm_alvo()
	if args.is_empty() and not extra.has("conta") and op != "admin_aviso" and op != "admin_clima" and op != "admin_tp_poi":
		mundo._aviso("Escolha um jogador na lista (ou digite o número do celular dele).", 3.5)
		return
	for k in extra.keys():
		args[k] = extra[k]
	_pedir(op, args)


func _adm_valor():
	return str(entradas.get("adm_valor", "")).replace(".", "").replace(",", "").replace(" ", "").to_int()


func _adm_dinheiro(tipo, sinal):
	var v = abs(_adm_valor())
	if v == 0:
		mundo._aviso("Digite um valor.", 3.0)
		return
	_adm_pedir("admin_dinheiro", {"tipo": tipo, "valor": v * sinal})


func _adm_tempo_set(t):
	adm_tempo = t
	_refrescar()


func _adm_item_set(id):
	adm_item = id
	_refrescar()


func _adm_modelo_set(m):
	adm_modelo = m
	_refrescar()


func _adm_cor_set(hexa):
	cor_sel = hexa
	_refrescar()


func _adm_banir():
	_adm_pedir("admin_banir", {"minutos": adm_tempo, "motivo": str(entradas.get("adm_motivo", ""))})


func _adm_expulsar():
	_adm_pedir("admin_expulsar", {"motivo": str(entradas.get("adm_motivo", ""))})


func _adm_mutar(ligar):
	var t = 0
	if ligar:
		t = adm_tempo if adm_tempo > 0 else 525600
	_adm_pedir("admin_mutar", {"minutos": t})


func _adm_item_dar():
	var q = clampi(str(entradas.get("adm_qtd", "1")).to_int(), 1, 99)
	_adm_pedir("admin_item", {"item": adm_item, "qtd": q})


func _adm_carro_dar():
	var m = adm_modelo
	if m == "" and not Cat.VEICULOS.is_empty():
		m = str(Cat.VEICULOS.keys()[0])
	_adm_pedir("admin_carro", {"modelo": m, "cor": cor_sel})


func _adm_aviso_enviar():
	var t = str(entradas.get("adm_aviso", "")).strip_edges()
	if t == "":
		mundo._aviso("Digite o aviso.", 3.0)
		return
	_pedir("admin_aviso", {"texto": t})
	entradas["adm_aviso"] = ""
	_refrescar()


func _adm_poi_ir(id):
	_pedir("admin_tp_poi", {"poi": id})


func _adm_admin_set(ligar):
	_adm_pedir("admin_papel", {"admin": ligar})


func _adm_admin_remover(cid):
	_pedir("admin_papel", {"conta": cid, "admin": false})


func _adm_desbanir(cid):
	_pedir("admin_desbanir", {"conta": cid})


func _adm_lista_jogadores(box):
	box.add_child(_l("Jogadores online (toque para escolher):", 22, CINZA))
	var lista = _adm_online()
	if lista.is_empty():
		box.add_child(_l("Ninguém online.", 20, CINZA))
	for j in lista:
		var txt = str(j["nome"])
		if bool(j.get("verificado", false)):
			txt += " " + Cat.TAG_VERIFICADO
		txt += "  [" + str(j["papel"]) + "]  S" + str(j.get("sala", 1)) + "  " + str(j["numero"])
		if bool(j.get("mudo", false)):
			txt += "  (mudo)"
		var cor = AZUL if int(j["peer"]) == adm_sel else ESCURO
		box.add_child(_b(txt, _adm_escolher.bind(int(j["peer"])), cor, Vector2(0, 52), 22))
	box.add_child(_entrada("adm_num", "Ou número do celular (jogador offline)", true))


func _p_admin(box):
	var papel = str(Rede.estado.get("papel", "jogador"))
	box.add_child(_l("Você é: " + papel.to_upper() + "   (ID da conta: " + str(Rede.conta_id) + ")", 20, CINZA))
	var abas = [["jogador", "Jogador"], ["punir", "Punir"], ["itens", "Itens/Carros"], ["mundo", "Mundo"]]
	if papel == "dono":
		abas.append(["admins", "Admins"])
	var h = _linha(box)
	for ab in abas:
		var b = _b(ab[1], _adm_aba_set.bind(ab[0]), AZUL if adm_aba == ab[0] else ESCURO, Vector2(0, 52), 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	if adm_aba == "jogador":
		_adm_lista_jogadores(box)
		box.add_child(_entrada("adm_valor", "Valor em R$", true))
		var h1 = _linha(box)
		for par in [["+ Dinheiro", "dinheiro", 1], ["- Dinheiro", "dinheiro", -1]]:
			var b1 = _b(par[0], _adm_dinheiro.bind(par[1], par[2]), VERDE if par[2] > 0 else VERMELHO, Vector2(0, 56), 22)
			b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h1.add_child(b1)
		var h2 = _linha(box)
		for par2 in [["+ Banco", "banco", 1], ["- Banco", "banco", -1]]:
			var b2 = _b(par2[0], _adm_dinheiro.bind(par2[1], par2[2]), VERDE if par2[2] > 0 else VERMELHO, Vector2(0, 56), 22)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h2.add_child(b2)
		var h3 = _linha(box)
		var bv1 = _b("Dar " + Cat.TAG_VERIFICADO, _adm_pedir.bind("admin_verificado", {"valor": true}), VERDE, Vector2(0, 56), 22)
		bv1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h3.add_child(bv1)
		var bv2 = _b("Tirar " + Cat.TAG_VERIFICADO, _adm_pedir.bind("admin_verificado", {"valor": false}), VERMELHO, Vector2(0, 56), 22)
		bv2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h3.add_child(bv2)
		var h4 = _linha(box)
		var bi = _b("Ir até ele", _adm_pedir.bind("admin_ir"), ESCURO, Vector2(0, 56), 22)
		bi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h4.add_child(bi)
		var bt = _b("Trazer até mim", _adm_pedir.bind("admin_trazer"), ESCURO, Vector2(0, 56), 22)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h4.add_child(bt)
		var h5 = _linha(box)
		var br = _b("Restaurar fome/sede", _adm_pedir.bind("admin_restaurar"), ESCURO, Vector2(0, 56), 20)
		br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h5.add_child(br)
		var bc = _b("Reparar + encher carro", _adm_pedir.bind("admin_veiculo"), ESCURO, Vector2(0, 56), 20)
		bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h5.add_child(bc)
		box.add_child(_l("Emprego:", 22, CINZA))
		var h6 = _linha(box)
		for emp in Cat.EMPREGOS.keys():
			var be = _b(str(Cat.EMPREGOS[emp]["nome"]), _adm_pedir.bind("admin_emprego", {"emprego": emp}), ESCURO, Vector2(0, 52), 20)
			be.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h6.add_child(be)
	elif adm_aba == "punir":
		_adm_lista_jogadores(box)
		box.add_child(_l("Duração:", 22, CINZA))
		var ht = null
		var n = 0
		for t in TEMPOS_ADM:
			if n % 3 == 0:
				ht = _linha(box)
			var bt2 = _b(str(t[1]), _adm_tempo_set.bind(int(t[0])), AZUL if adm_tempo == int(t[0]) else ESCURO, Vector2(0, 52), 20)
			bt2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ht.add_child(bt2)
			n += 1
		box.add_child(_entrada("adm_motivo", "Motivo"))
		box.add_child(_b("BANIR (usa a duração e o motivo)", _adm_banir, VERMELHO, Vector2(0, 60), 22))
		box.add_child(_b("Expulsar agora (usa o motivo)", _adm_expulsar, VERMELHO, Vector2(0, 56), 22))
		var h7 = _linha(box)
		var bm1 = _b("Silenciar chat", _adm_mutar.bind(true), ESCURO, Vector2(0, 56), 22)
		bm1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h7.add_child(bm1)
		var bm2 = _b("Liberar chat", _adm_mutar.bind(false), VERDE, Vector2(0, 56), 22)
		bm2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h7.add_child(bm2)
		box.add_child(_l("Banidos:", 22, CINZA))
		var bans = _adm_info().get("bans", [])
		if bans.is_empty():
			box.add_child(_l("Ninguém banido.", 20, CINZA))
		for bn in bans:
			var dur = "permanente" if int(bn["dur"]) <= 0 else str(int(bn["dur"])) + " min"
			box.add_child(_b("Desbanir " + str(bn["nome"]) + " (" + dur + ") - " + str(bn["motivo"]), _adm_desbanir.bind(str(bn["conta"])), ESCURO, Vector2(0, 52), 18))
	elif adm_aba == "itens":
		_adm_lista_jogadores(box)
		box.add_child(_l("Item (toque para escolher):", 22, CINZA))
		for id in Itens.ITENS.keys():
			box.add_child(_b(str(Itens.ITENS[id]["nome"]), _adm_item_set.bind(id), AZUL if adm_item == id else ESCURO, Vector2(0, 48), 20))
		box.add_child(_entrada("adm_qtd", "Quantidade (1 a 99)", true))
		box.add_child(_b("Dar item", _adm_item_dar, VERDE, Vector2(0, 58), 22))
		box.add_child(_l("Carro:", 22, CINZA))
		for m in Cat.VEICULOS.keys():
			var sel = adm_modelo == m or (adm_modelo == "" and m == Cat.VEICULOS.keys()[0])
			box.add_child(_b(str(Cat.VEICULOS[m]["nome"]), _adm_modelo_set.bind(m), AZUL if sel else ESCURO, Vector2(0, 48), 20))
		var hc = _linha(box)
		for cc in CORES_CARRO:
			_cor_botao(hc, cc, cor_sel == cc, _adm_cor_set.bind(cc))
		box.add_child(_b("Dar carro", _adm_carro_dar, VERDE, Vector2(0, 58), 22))
	elif adm_aba == "mundo":
		box.add_child(_entrada("adm_aviso", "Aviso para todos os jogadores"))
		box.add_child(_b("Enviar aviso", _adm_aviso_enviar, VERDE, Vector2(0, 58), 22))
		box.add_child(_l("Clima:", 22, CINZA))
		var h8 = _linha(box)
		var bs = _b("Sol", _adm_pedir.bind("admin_clima", {"clima": "sol"}), ESCURO, Vector2(0, 56), 22)
		bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h8.add_child(bs)
		var bch = _b("Chuva", _adm_pedir.bind("admin_clima", {"clima": "chuva"}), ESCURO, Vector2(0, 56), 22)
		bch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h8.add_child(bch)
		box.add_child(_l("Teleportar para:", 22, CINZA))
		for p in Cidade.POIS:
			box.add_child(_b(str(p["nome"]), _adm_poi_ir.bind(str(p["id"])), ESCURO, Vector2(0, 48), 20))
	elif adm_aba == "admins":
		box.add_child(_l("Só o dono promove ou rebaixa admins.", 20, CINZA))
		_adm_lista_jogadores(box)
		var h9 = _linha(box)
		var ba1 = _b("Tornar ADMIN", _adm_admin_set.bind(true), VERDE, Vector2(0, 56), 22)
		ba1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h9.add_child(ba1)
		var ba2 = _b("Tirar admin", _adm_admin_set.bind(false), VERMELHO, Vector2(0, 56), 22)
		ba2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h9.add_child(ba2)
		box.add_child(_l("Admins atuais:", 22, CINZA))
		var admins = _adm_info().get("admins", [])
		if admins.is_empty():
			box.add_child(_l("Nenhum.", 20, CINZA))
		for ad in admins:
			box.add_child(_b("Remover " + str(ad["nome"]), _adm_admin_remover.bind(str(ad["conta"])), ESCURO, Vector2(0, 52), 20))
