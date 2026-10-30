extends Node
# REDE: liga o cliente (jogo) ao servidor autoritativo.
#  - offline : o servidor roda dentro do jogo, sem rede
#  - host    : o servidor roda dentro do jogo E aceita outros jogadores (WebSocket)
#  - cliente : conecta no servidor publico (SERVIDOR_URL, por WebSocket) e escolhe o servidor 1, 2, 3 ou 4
#  - dedicado: o servidor publico (roda no Railway/VPS, sem tela). Tambem por WebSocket.
# Todos os pedidos passam por pedir(); nunca alteram dados direto.

signal estado_mudou
signal evento(nome, dados)
signal remotos_mudou
signal conectado_ok
signal conexao_falhou
signal rede_pronta
signal voz_recebida(de, dados)

const PORTA_PADRAO = 8080
# >>> COLOQUE AQUI o endereco do servidor publico (o dominio que o Railway gera).
# Com dominio https use  wss://  (sem porta).  Ex.: "wss://rpgame-production.up.railway.app"
# Para testar no seu PC/rede local use  ws://IP:7777  Ex.: "ws://192.168.0.10:7777"
const SERVIDOR_URL = "wss://metr-pole-rp-production.up.railway.app"
const NUM_SALAS = 4

var modo = "offline"
var logado = false
var conta_id = ""
var estado = {}
var remotos = {}
var meu_peer = 1
var offset_tempo = 0.0
var clima = "sol"
var pos_func = Callable()
var t_pos = 0.0
var versao_estado = 0
var sala_atual = 0
var aviso_menu = ""
var saida_forcada = false   # banido/expulso: nao tenta reconectar sozinho
# reconexao automatica (cliente caiu no meio do jogo)
const MAX_TENTATIVAS = 6
var reconectando = false
var tentativas = 0
var tok_reconexao = 0
var agendado = false


func _ready():
	conta_id = _carregar_conta_id()
	multiplayer.connected_to_server.connect(_ao_conectar)
	multiplayer.connection_failed.connect(_ao_falhar)
	multiplayer.server_disconnected.connect(_ao_cair)
	multiplayer.peer_disconnected.connect(_ao_sair_peer)
	multiplayer.peer_connected.connect(_ao_entrar_peer)


func _carregar_conta_id():
	var cfg = ConfigFile.new()
	if cfg.load("user://conta.cfg") == OK:
		var id = str(cfg.get_value("conta", "id", ""))
		if id.length() >= 16:
			return id
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var id2 = ""
	for i in range(32):
		id2 += "0123456789abcdef".substr(rng.randi() % 16, 1)
	cfg.set_value("conta", "id", id2)
	cfg.save("user://conta.cfg")
	return id2


func eh_servidor():
	return modo != "cliente"


# ---------- iniciar sessao ----------

func iniciar_offline():
	_resetar()
	modo = "offline"
	Servidor.iniciar()
	logado = Servidor.entrar(1, conta_id)


func hospedar(porta = PORTA_PADRAO):
	_resetar()
	var peer = WebSocketMultiplayerPeer.new()
	var erro = peer.create_server(porta)
	if erro != OK:
		return false
	multiplayer.multiplayer_peer = peer
	modo = "host"
	sala_atual = 1
	Servidor.iniciar()
	logado = Servidor.entrar(1, conta_id)
	return true


func conectar(url):
	_resetar()
	var peer = WebSocketMultiplayerPeer.new()
	var erro = peer.create_client(str(url))
	if erro != OK:
		return false
	multiplayer.multiplayer_peer = peer
	modo = "cliente"
	return true


func servidor_dedicado(porta = 0):
	# Railway e outras hospedagens dizem a porta pela variavel de ambiente PORT
	if porta <= 0:
		porta = int(OS.get_environment("PORT"))
	if porta <= 0:
		porta = PORTA_PADRAO
	_resetar()
	var peer = WebSocketMultiplayerPeer.new()
	var erro = peer.create_server(porta)
	if erro != OK:
		return false
	multiplayer.multiplayer_peer = peer
	modo = "dedicado"
	Servidor.iniciar()
	return true


func _resetar():
	saida_forcada = false
	reconectando = false
	agendado = false
	tok_reconexao += 1
	logado = false
	sala_atual = 0
	estado = {}
	remotos = {}
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func desconectar():
	if modo != "offline" and Servidor.ativo and eh_servidor():
		Servidor.salvar_tudo()
	_resetar()
	modo = "offline"


# ---------- pedidos do cliente ----------

func pedir(op, args = {}):
	if modo == "cliente":
		if not conectado():
			return
		rpc_id(1, "srv_pedir", op, args)
	else:
		Servidor.processar(1, op, args)


func _ao_conectar():
	# conectou no servidor: ainda NAO entrou em nenhum. Pede a lista de servidores; o jogador escolhe um.
	meu_peer = multiplayer.get_unique_id()
	if reconectando:
		print("[cliente] reconectado, voltando para o servidor ", sala_atual)
		rpc_id(1, "srv_entrar", conta_id, sala_atual)
		return
	rede_pronta.emit()
	rpc_id(1, "srv_salas")


func conectado():
	var p = multiplayer.multiplayer_peer
	return modo == "cliente" and p != null and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func pedir_salas():
	if conectado():
		rpc_id(1, "srv_salas")


func entrar_sala(n):
	if not conectado():
		return false
	sala_atual = int(n)
	rpc_id(1, "srv_entrar", conta_id, int(n))
	return true


func _ao_falhar():
	if reconectando:
		_agendar_reconexao()
		return
	modo = "offline"
	conexao_falhou.emit()


func _ao_cair():
	if reconectando:
		_agendar_reconexao()
		return
	if saida_forcada:
		_desistir(aviso_menu if aviso_menu != "" else "Você foi desconectado.")
		return
	# caiu no meio do jogo (logado numa sala): tenta voltar sozinho antes de desistir
	if modo == "cliente" and logado and sala_atual > 0:
		print("[cliente] conexão caiu, tentando reconectar...")
		reconectando = true
		tentativas = 0
		logado = false
		evento.emit("aviso", {"msg": "Conexão instável. Reconectando..."})
		_agendar_reconexao()
		return
	_desistir("Conexão com o servidor perdida.")


func _desistir(msg):
	reconectando = false
	agendado = false
	tok_reconexao += 1
	logado = false
	modo = "offline"
	aviso_menu = msg
	evento.emit("aviso", {"msg": msg})
	evento.emit("desconectado", {})


func _agendar_reconexao():
	if agendado:
		return
	agendado = true
	tok_reconexao += 1
	tentativas += 1
	if tentativas > MAX_TENTATIVAS:
		_desistir("Não foi possível reconectar ao servidor.")
		return
	var t = tok_reconexao
	var espera = minf(1.5 * tentativas, 6.0)
	get_tree().create_timer(espera).timeout.connect(_tentar_reconectar.bind(t))


func _tentar_reconectar(t):
	if not reconectando or t != tok_reconexao:
		return
	print("[cliente] tentativa de reconexão ", tentativas, " de ", MAX_TENTATIVAS)
	var velho = multiplayer.multiplayer_peer
	if velho != null and not (velho is OfflineMultiplayerPeer):
		velho.close()
	var peer = WebSocketMultiplayerPeer.new()
	var erro = peer.create_client(SERVIDOR_URL)
	if erro != OK:
		agendado = false
		_agendar_reconexao()
		return
	multiplayer.multiplayer_peer = peer
	agendado = false
	# se em 10 s nao voltou (nem conectou, nem entrou), tenta de novo
	get_tree().create_timer(10.0).timeout.connect(_reconexao_pendente.bind(t))


func _reconexao_pendente(t):
	if reconectando and t == tok_reconexao:
		agendado = false
		_agendar_reconexao()


func _ao_entrar_peer(id):
	# aparece no log do servidor (Railway > Deploy Logs)
	if modo == "dedicado" or modo == "host":
		print("[servidor] jogador conectou, peer ", id)


func _ao_sair_peer(id):
	if modo == "dedicado" or modo == "host":
		print("[servidor] jogador saiu, peer ", id)
	if multiplayer.is_server():
		Servidor.sair(id)
		Servidor.t_salas.erase(id)


func derrubar(peer):
	if peer == 1:
		return
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.disconnect_peer(peer)


# ---------- servidor -> cliente ----------

func enviar_cliente(peer, nome, dados):
	if peer == 1 and modo != "cliente":
		_receber(nome, dados)
	elif multiplayer.multiplayer_peer != null:
		rpc_id(peer, "cli_receber", nome, dados)


func enviar_remotos(peer, lista):
	if peer == 1 and modo != "cliente":
		_aplicar_remotos(lista)
	elif multiplayer.multiplayer_peer != null:
		rpc_id(peer, "cli_remotos", lista)


@rpc("any_peer", "call_remote", "reliable")
func srv_pedir(op, args):
	if not multiplayer.is_server():
		return
	Servidor.processar(multiplayer.get_remote_sender_id(), op, args)


@rpc("any_peer", "call_remote", "reliable")
func srv_entrar(cid, sala):
	if not multiplayer.is_server():
		return
	var quem = multiplayer.get_remote_sender_id()
	print("[servidor] pedido de entrada: peer ", quem, " sala ", sala, " ativo=", Servidor.ativo)
	if not Servidor.ativo:
		enviar_cliente(quem, "entrada_negada", {"msg": "O servidor ainda está iniciando. Tente de novo em instantes."})
		return
	Servidor.entrar(quem, cid, sala)


@rpc("any_peer", "call_remote", "reliable")
func srv_salas():
	if not multiplayer.is_server() or not Servidor.ativo:
		return
	Servidor.enviar_salas(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "unreliable")
func srv_pos(d):
	if not multiplayer.is_server():
		return
	Servidor.relatar_pos(multiplayer.get_remote_sender_id(), d)


# ---------- chat de voz ----------
# cliente -> servidor: pacote de voz (comprimido, ver sistema/voz.gd)
func enviar_voz(dados):
	if modo == "cliente":
		if conectado():
			rpc_id(1, "srv_voz", dados)
	elif modo == "host":
		Servidor.relatar_voz(1, dados)


# servidor -> cliente: voz de outro jogador
func entregar_voz(peer, de, dados):
	if peer == 1 and modo != "cliente":
		voz_recebida.emit(de, dados)
	elif multiplayer.multiplayer_peer != null:
		rpc_id(peer, "cli_voz", de, dados)


@rpc("any_peer", "call_remote", "unreliable")
func srv_voz(dados):
	if not multiplayer.is_server():
		return
	Servidor.relatar_voz(multiplayer.get_remote_sender_id(), dados)


@rpc("authority", "call_remote", "unreliable")
func cli_voz(de, dados):
	voz_recebida.emit(int(de), dados)


@rpc("authority", "call_remote", "reliable")
func cli_receber(nome, dados):
	_receber(nome, dados)


@rpc("authority", "call_remote", "unreliable")
func cli_remotos(lista):
	_aplicar_remotos(lista)


func _receber(nome, dados):
	if nome == "estado":
		estado = dados
		logado = true
		versao_estado += 1
		estado_mudou.emit()
		if reconectando:
			reconectando = false
			tentativas = 0
			print("[cliente] reconectado com sucesso")
			evento.emit("aviso", {"msg": "Reconectado!"})
		if modo == "cliente":
			conectado_ok.emit()
	elif nome == "stats":
		estado["fome"] = dados.get("fome", 100.0)
		estado["sede"] = dados.get("sede", 100.0)
		estado_mudou.emit()
	elif nome == "veiculo":
		for v in estado.get("veiculos", []):
			if v["id"] == dados.get("id", ""):
				v["comb"] = dados.get("comb", v["comb"])
				v["dano"] = dados.get("dano", v["dano"])
				v["trancado"] = dados.get("trancado", v["trancado"])
		evento.emit("veiculo", dados)
	elif nome == "tempo":
		offset_tempo = float(dados.get("unix", 0.0)) - Time.get_unix_time_from_system()
		clima = str(dados.get("clima", "sol"))
		evento.emit("tempo", dados)
	elif nome == "banido" or nome == "expulso":
		saida_forcada = true
		aviso_menu = str(dados.get("msg", ""))
		if reconectando:
			_desistir(aviso_menu)
			return
		evento.emit(nome, dados)
	else:
		if nome == "entrada_negada" and reconectando:
			_desistir(str(dados.get("msg", "Não foi possível voltar ao servidor.")))
			return
		evento.emit(nome, dados)


func _aplicar_remotos(lista):
	var novo = {}
	for item in lista:
		if int(item["peer"]) != meu_peer:
			novo[int(item["peer"])] = item
	remotos = novo
	remotos_mudou.emit()


# ---------- utilidades do cliente ----------

func hora_jogo():
	# 1 dia de jogo = 24 minutos reais
	var t = Time.get_unix_time_from_system() + offset_tempo
	return fmod(t / 60.0, 24.0)


func veiculo(vid):
	for v in estado.get("veiculos", []):
		if v["id"] == vid:
			return v
	return null


func veiculo_ativo():
	for v in estado.get("veiculos", []):
		if v["ativo"]:
			return v
	return null


func jogador_mais_perto(pos, raio):
	var melhor = null
	var menor = raio
	for peer in remotos.keys():
		var d = pos.distance_to(remotos[peer]["pos"])
		if d < menor:
			menor = d
			melhor = remotos[peer]
	return melhor


func _process(delta):
	if not logado or not pos_func.is_valid():
		return
	t_pos += delta
	if t_pos < 0.1:
		return
	t_pos = 0.0
	var d = pos_func.call()
	if not (d is Dictionary):
		return
	if modo == "cliente":
		if conectado():
			rpc_id(1, "srv_pos", d)
	else:
		Servidor.relatar_pos(1, d)
