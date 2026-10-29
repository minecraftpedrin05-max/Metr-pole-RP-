extends RefCounted
# Dados fixos do jogo: precos, lojas, roupas, empregos. Quem decide preco e o servidor.

const DINHEIRO_INICIAL = 99999999999999
const BANCO_INICIAL = 9999999999
const RAIO_INTERACAO = 12.0
const TANQUE_L = 60.0
const CONSUMO_L_KM = 0.25
const PRECO_L = 6
const CUSTO_REPARO_PONTO = 8
const CUSTO_PINTURA = 200
const PRECO_CNH = 350
const SALARIO_INTERVALO = 600.0
const VENDA_VEICULO = 0.6
const UPGRADE_MOTOR = [2500, 5000, 9000, 15000]
const UPGRADE_VEL = 0.10
const UPGRADE_FORCA = 0.12
const VENDA_CASA = 0.7

const VEICULOS = {
	"m4gt3": {"nome": "BMW M4 GT3", "preco": 18000},
}

const EMPREGOS = {
	"civil": {"nome": "Civil", "salario": 0},
	"policial": {"nome": "Policial", "salario": 600},
	"mecanico": {"nome": "Mecânico", "salario": 450},
}

# slot: camisa, calca, chapeu, oculos, mochila
const ROUPAS = {
	"camisa_cinza": {"nome": "Camiseta cinza", "slot": "camisa", "cor": "#8a8a8a", "preco": 0},
	"camisa_vermelha": {"nome": "Camiseta vermelha", "slot": "camisa", "cor": "#aa3333", "preco": 0},
	"camisa_azul": {"nome": "Camiseta azul", "slot": "camisa", "cor": "#3366aa", "preco": 0},
	"camisa_verde": {"nome": "Camiseta verde", "slot": "camisa", "cor": "#2e8b57", "preco": 0},
	"camisa_amarela": {"nome": "Camiseta amarela", "slot": "camisa", "cor": "#d4a017", "preco": 0},
	"camisa_preta": {"nome": "Camiseta preta", "slot": "camisa", "cor": "#222222", "preco": 0},
	"camisa_branca": {"nome": "Camiseta branca", "slot": "camisa", "cor": "#e8e8e8", "preco": 35},
	"camisa_rosa": {"nome": "Camiseta rosa", "slot": "camisa", "cor": "#d86aa0", "preco": 35},
	"camisa_laranja": {"nome": "Camiseta laranja", "slot": "camisa", "cor": "#e07b39", "preco": 35},
	"camisa_roxa": {"nome": "Camiseta roxa", "slot": "camisa", "cor": "#7b3fa0", "preco": 45},
	"camisa_policia": {"nome": "Uniforme policial", "slot": "camisa", "cor": "#1c2a4a", "preco": 90},
	"calca_jeans": {"nome": "Calça jeans", "slot": "calca", "cor": "#2b3a55", "preco": 0},
	"calca_preta": {"nome": "Calça preta", "slot": "calca", "cor": "#2a2a2a", "preco": 50},
	"calca_cinza": {"nome": "Calça cinza", "slot": "calca", "cor": "#6b6b6b", "preco": 50},
	"calca_caqui": {"nome": "Calça cáqui", "slot": "calca", "cor": "#8a7a58", "preco": 55},
	"calca_azul_clara": {"nome": "Jeans claro", "slot": "calca", "cor": "#4f78a8", "preco": 60},
	"bone_preto": {"nome": "Boné preto", "slot": "chapeu", "cor": "#1a1a1a", "preco": 40},
	"bone_vermelho": {"nome": "Boné vermelho", "slot": "chapeu", "cor": "#b02020", "preco": 40},
	"bone_azul": {"nome": "Boné azul", "slot": "chapeu", "cor": "#2050a0", "preco": 40},
	"oculos_escuros": {"nome": "Óculos escuros", "slot": "oculos", "cor": "#111111", "preco": 80},
	"mochila_preta": {"nome": "Mochila preta", "slot": "mochila", "cor": "#222222", "preco": 120},
	"mochila_vermelha": {"nome": "Mochila vermelha", "slot": "mochila", "cor": "#a02828", "preco": 120},
}

const INICIAIS_CAMISA = ["camisa_cinza", "camisa_vermelha", "camisa_azul", "camisa_verde", "camisa_amarela", "camisa_preta"]

# loja (= id do ponto no mapa)
const LOJAS = {
	"mercado": {"nome": "Mercado", "itens": {"agua": 5, "refrigerante": 8, "sanduiche": 12, "marmita": 25, "galao": 90, "kit_reparo": 150}},
	"roupas": {"nome": "Loja de Roupas", "roupas": true},
}


static func cor(id):
	if ROUPAS.has(id):
		return Color(ROUPAS[id]["cor"])
	return Color("888888")
