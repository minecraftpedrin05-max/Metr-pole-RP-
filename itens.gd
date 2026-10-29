extends RefCounted
# Catalogo de itens. O servidor usa estes dados para validar tudo; o cliente so mostra.

const CAPACIDADE_KG = 30.0

const ITENS = {
	"agua": {"nome": "Água", "peso": 0.5, "desc": "Mata a sede.", "efeito": {"sede": 35}},
	"refrigerante": {"nome": "Refrigerante", "peso": 0.4, "desc": "Sede e um pouco de fome.", "efeito": {"sede": 25, "fome": 5}},
	"sanduiche": {"nome": "Sanduíche", "peso": 0.3, "desc": "Mata a fome.", "efeito": {"fome": 40}},
	"marmita": {"nome": "Marmita", "peso": 0.6, "desc": "Refeição completa.", "efeito": {"fome": 70}},
	"galao": {"nome": "Galão de combustível", "peso": 8.0, "desc": "Põe 15 L no seu veículo (perto dele).", "efeito": {"combustivel": 15}},
	"kit_reparo": {"nome": "Kit de reparo", "peso": 3.0, "desc": "Tira 40% do dano do seu veículo (perto dele).", "efeito": {"reparo": 40}},
}


static func existe(id):
	return ITENS.has(id)


static func nome(id):
	if ITENS.has(id):
		return ITENS[id]["nome"]
	return str(id)


static func peso(id):
	if ITENS.has(id):
		return float(ITENS[id]["peso"])
	return 1.0
