"""Gera o modelo do relatório de fechamento do dia (PDF) para aprovação da equipe.

Todos os valores são ILUSTRATIVOS e calculados em centavos (int), para que o
modelo feche no centavo como o sistema real. Nenhum dado pessoal é usado.

Uso: python3 gerar_modelo_relatorio.py [saida.pdf]
"""
import hashlib
import json
import sys
from pathlib import Path

from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

FONT_DIR = Path("/usr/share/fonts/truetype/liberation")
pdfmetrics.registerFont(TTFont("Sans", FONT_DIR / "LiberationSans-Regular.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Bold", FONT_DIR / "LiberationSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Italic", FONT_DIR / "LiberationSans-Italic.ttf"))
pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-Bold", italic="Sans-Italic")

# ---------- paleta ----------
INK = colors.HexColor("#1F1A24")
MUTED = colors.HexColor("#6B6475")
LINE = colors.HexColor("#D9D4DF")
BAND = colors.HexColor("#F5F2F8")
ACCENT = colors.HexColor("#5B2A6E")
OK = colors.HexColor("#1E7A46")
WARN = colors.HexColor("#A15C00")
BAD = colors.HexColor("#B42318")
INFO = colors.HexColor("#1D5FA8")

# ---------- estilos ----------
def st(name, **kw):
    base = dict(fontName="Sans", fontSize=8.5, leading=11, textColor=INK)
    base.update(kw)
    return ParagraphStyle(name, **base)

S_TITLE = st("title", fontName="Sans-Bold", fontSize=17, leading=21, textColor=ACCENT)
S_SUB = st("sub", fontSize=9.5, leading=13, textColor=MUTED)
S_H1 = st("h1", fontName="Sans-Bold", fontSize=12, leading=15, textColor=ACCENT, spaceBefore=10, spaceAfter=4)
S_H2 = st("h2", fontName="Sans-Bold", fontSize=9.5, leading=12, spaceBefore=6, spaceAfter=3)
S_BODY = st("body")
S_SMALL = st("small", fontSize=7.3, leading=9.3, textColor=MUTED)
S_CELL = st("cell", fontSize=7.6, leading=9.4)
S_CELL_B = st("cellb", fontName="Sans-Bold", fontSize=7.6, leading=9.4)
S_CELL_R = st("cellr", fontSize=7.6, leading=9.4, alignment=TA_RIGHT)
S_CELL_RB = st("cellrb", fontName="Sans-Bold", fontSize=7.6, leading=9.4, alignment=TA_RIGHT)
S_HEAD = st("head", fontName="Sans-Bold", fontSize=7, leading=8.6, textColor=MUTED)
S_HEAD_R = st("headr", fontName="Sans-Bold", fontSize=7, leading=8.6, textColor=MUTED, alignment=TA_RIGHT)
S_KPI_V = st("kpiv", fontName="Sans-Bold", fontSize=14, leading=17, alignment=TA_CENTER)
S_KPI_L = st("kpil", fontSize=7.2, leading=9, textColor=MUTED, alignment=TA_CENTER)


# ---------- dinheiro em centavos ----------
def brl(c, sign=False):
    neg = c < 0
    c = abs(c)
    s = f"{c // 100:,}".replace(",", ".") + f",{c % 100:02d}"
    if neg:
        return "−R$ " + s
    return ("+R$ " if sign and c else "R$ ") + s


def num(n):
    return f"{n:,}".replace(",", ".")


def rate_bps(amount, bps):
    """applyRate do money.ts: basis points, arredondamento half-up."""
    return (amount * bps + 5000) // 10000


def pct(a, b):
    return f"{(100 * a / b):.1f}".replace(".", ",") + "%" if b else "—"


# ---------- dados ilustrativos ----------
DIA = "20/12/2025"
DIA_SEMANA = "sábado"
PRECO = {"Inteira": 3600, "Meia-entrada e equivalentes": 1800, "Solidário (+1 kg alimento)": 2500, "Cortesia": 0}
TIPOS = list(PRECO)

# guichê: operador, fundo, vendas por tipo (int, meia, solid, cortesia),
# pagamento (dinheiro, débito, crédito, pix) proporcional, estorno em dinheiro, sangrias parciais, diferença na contagem
GUICHES = [
    # g, fundo,  qtd por tipo,        pix%, deb%, cred% (resto dinheiro), estorno_din, sangrias, dif
    (1, 30000, (118, 96, 22, 3), 38, 22, 18, 0, 150000, 0),
    (2, 30000, (104, 88, 19, 2), 40, 20, 20, 3600, 150000, -50),
    (3, 20000, (97, 81, 17, 1), 35, 25, 17, 0, 100000, 0),
    (4, 30000, (112, 90, 25, 4), 36, 24, 18, 0, 150000, -1200),
    (5, 25000, (91, 74, 14, 0), 42, 21, 16, 0, 100000, 0),
    (6, 20000, (86, 70, 12, 2), 39, 23, 19, 1800, 100000, 0),
    (7, 30000, (109, 93, 21, 3), 37, 22, 20, 0, 150000, 6300),
    (8, 20000, (72, 61, 10, 1), 41, 20, 18, 0, 50000, 0),
    (9, 15000, (58, 47, 8, 0), 44, 19, 17, 0, 50000, 100),
]
TOL_OK, TOL_JUST = 100, 5000  # até R$ 1,00 / R$ 1,01 a R$ 50,00 / acima: destacar
JUSTIFICATIVAS = {
    2: "Diferença dentro da tolerância; justificativa opcional.",
    4: "Operador informa troco entregue a maior a cliente às 20h40.",
    7: "Sobra em análise: possível venda em dinheiro não registrada. Destacado aos assinantes.",
    9: "Diferença dentro da tolerância; justificativa opcional.",
}


def split(total, pix, deb, cred):
    """Divide o total em pix/débito/crédito/dinheiro em centavos, sem perder centavo."""
    p = total * pix // 100 // 100 * 100   # valores em reais inteiros: os preços não têm centavos
    d = total * deb // 100 // 100 * 100
    c = total * cred // 100 // 100 * 100
    return total - p - d - c, d, c, p


guiche_rows = []
for g, fundo, q, pix, deb, cred, est, _, dif in GUICHES:
    venda = sum(n * PRECO[t] for n, t in zip(q, TIPOS))
    din, d, c, p = split(venda, pix, deb, cred)
    din = din - din % 100  # dinheiro em reais inteiros
    p = venda - din - d - c
    sang = (fundo + din - est) * 3 // 4 // 10000 * 10000   # sangrias parciais em notas de R$ 100
    esperado = fundo + din - est - sang
    contado = esperado + dif
    status = "Conciliado" if abs(dif) <= TOL_OK else ("Justificar" if abs(dif) <= TOL_JUST else "Destacar")
    guiche_rows.append(dict(g=g, fundo=fundo, q=q, venda=venda, din=din, deb=d, cred=c, pix=p, est=est,
                            sang=sang, esperado=esperado, contado=contado, dif=dif, status=status))

bil_venda = sum(r["venda"] for r in guiche_rows)
bil_est = sum(r["est"] for r in guiche_rows)
bil_din = sum(r["din"] for r in guiche_rows)
bil_deb = sum(r["deb"] for r in guiche_rows)
bil_cred = sum(r["cred"] for r in guiche_rows)
bil_pix = sum(r["pix"] for r in guiche_rows)
bil_dif = sum(r["dif"] for r in guiche_rows)
bil_fundos = sum(r["fundo"] for r in guiche_rows)
bil_sang_parc = sum(r["sang"] for r in guiche_rows)
bil_q = [sum(r["q"][i] for r in guiche_rows) for i in range(4)]
bil_ing = sum(bil_q)
bil_est_ing = 2 + 1  # 1 inteira (G2) e 1 meia (G6), estornos sempre totais

# online Zet (parcial até a sincronização das 22:47)
ON_Q = (1150, 1420, 230, 29)
on_liq = sum(n * PRECO[t] for n, t in zip(ON_Q, TIPOS))
on_taxa = rate_bps(on_liq, 1000)
on_bruto = on_liq + on_taxa
on_pedidos = 1012
on_est = 5 * 3600 + 3 * 1800   # 8 ingressos, só o valor do ingresso (a taxa não volta)
on_est_ing, on_est_ped = 8, 5
on_cb = 7200                   # contestação lançada hoje, venda de 29/11
maq = dict(pedidos=59, ingressos=131, deb=190800, cred=129600, pix=79500)
maq_liq = maq["deb"] + maq["cred"] + maq["pix"]
maq_taxa = rate_bps(maq_liq, 1000)
desc_ped, desc_liq = 3, 16200  # vendas de 18/12 sem webhook, descobertas hoje
on_total = on_liq - on_est - on_cb + maq_liq + desc_liq

# foods
LOJAS = [  # nome, vendas declaradas, comissão em basis points
    ("Loja 01", 1854300, 1500),
    ("Loja 02", 962050, 1200),
    ("Loja 03", 1310000, 1500),
    ("Loja 04", 487590, 1000),
    ("Loja 05", 725000, 1200),
]
food_rows = []
for nome, vendas, bps in LOJAS:
    com = rate_bps(vendas, bps)
    falta = 4530 if nome == "Loja 03" else 0
    pago = com - falta
    aberto = falta + (9800 if nome == "Loja 03" else 0)  # 98,00 de dias anteriores
    food_rows.append(dict(nome=nome, vendas=vendas, bps=bps, com=com, pago=pago, falta=falta, aberto=aberto))
food_com = sum(r["com"] for r in food_rows)
food_pago = sum(r["pago"] for r in food_rows)
food_falta = sum(r["falta"] for r in food_rows)

# tesouraria (nada fica de um dia para o outro)
tes_ini = 0
tes_fundos = bil_fundos
tes_rec_parc = bil_sang_parc
tes_rec_final = sum(r["contado"] for r in guiche_rows)
tes_food = food_pago  # repasses das lojas em dinheiro
despesa = 120000       # pagamento de despesa do evento com comprovante
tes_disp = tes_ini - tes_fundos + tes_rec_parc + tes_rec_final + tes_food
deposito = tes_disp - despesa
tes_fim = tes_disp - despesa - deposito
assert tes_fim == 0

# quebra/sobra líquida entra no resultado
venda_liq_dia = bil_venda - bil_est + on_total + food_com

# público
bil_entr_q = [bil_q[0] - 2, bil_q[1] - 1, bil_q[2], bil_q[3]]   # 3 cartões vendidos não passaram na catraca
bil_entr = sum(bil_entr_q)
ON_ENT_HOJE = (590, 710, 150, 30)
ON_ENT_ANTES = (880, 1030, 190, 30)
on_ent_q = [a + b for a, b in zip(ON_ENT_HOJE, ON_ENT_ANTES)]
on_ent = sum(on_ent_q)
on_previstos = 3832
on_nao_valid = on_previstos - on_ent

# ticket médio sobre quem entrou (valor pago pelos ingressos de quem entrou)
val_bil_entr = sum(n * PRECO[t] for n, t in zip(bil_entr_q, TIPOS))
val_on_entr = sum(n * PRECO[t] for n, t in zip(on_ent_q, TIPOS))
pess = bil_entr + on_ent
pess_sem_cort = pess - bil_entr_q[3] - on_ent_q[3]
tm_geral = (val_bil_entr + val_on_entr) // pess
tm_geral_sc = (val_bil_entr + val_on_entr) // pess_sem_cort
tm_bil = val_bil_entr // bil_entr
tm_bil_sc = val_bil_entr // (bil_entr - bil_entr_q[3])
tm_on = val_on_entr // on_ent
tm_on_sc = val_on_entr // (on_ent - on_ent_q[3])

# conta-corrente Zet (acumulado até hoje)
cc = dict(vendido=158_342_100 + on_liq + maq_liq + desc_liq, estornos=1_421_000 + on_est,
          contestacoes=90_300 + on_cb, repasses=138_000_000, taxas_saque=1_200)
cc_devido = cc["vendido"] - cc["estornos"] - cc["contestacoes"]
cc_saldo = cc_devido - cc["repasses"] - cc["taxas_saque"]
cc_risco = 9_874_500

snapshot = dict(dia=DIA, guiches=guiche_rows, online=dict(liq=on_liq, est=on_est, cb=on_cb, maq=maq_liq, desc=desc_liq),
                foods=food_rows, tesouraria=dict(deposito=deposito, despesa=despesa), publico=dict(bil=bil_entr, on=on_ent),
                catraca=dict(entradas=bil_entr_q, esperado=val_bil_entr, receita=bil_venda - bil_est))
HASH = hashlib.sha256(json.dumps(snapshot, sort_keys=True, default=str).encode()).hexdigest()


# ---------- helpers de layout ----------
def P(t, s=S_CELL):
    return Paragraph(t, s)


def status_chip(s):
    color = {"Conciliado": OK, "Justificar": WARN, "Destacar": BAD, "Pendente": INFO, "OK": OK,
             "Alerta": WARN, "Parcial": INFO}[s]
    return Paragraph(f'<font color="{color.hexval()}"><b>{s}</b></font>', S_CELL)


def table(data, widths, head_rows=1, total_rows=0, zebra=True, extra=None):
    t = Table(data, colWidths=widths, repeatRows=head_rows)
    cmds = [
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 2.2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.2),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
        ("LINEBELOW", (0, head_rows - 1), (-1, head_rows - 1), 0.8, ACCENT),
        ("LINEBELOW", (0, head_rows), (-1, -1 - total_rows), 0.25, LINE),
    ]
    if zebra:
        for i in range(head_rows, len(data) - total_rows):
            if (i - head_rows) % 2:
                cmds.append(("BACKGROUND", (0, i), (-1, i), BAND))
    if total_rows:
        cmds += [("LINEABOVE", (0, -total_rows), (-1, -total_rows), 0.8, INK),
                 ("BACKGROUND", (0, -total_rows), (-1, -1), colors.HexColor("#EEE8F3"))]
    if extra:
        cmds += extra
    t.setStyle(TableStyle(cmds))
    return t


def kpis(items):
    cells = [[P(v, S_KPI_V) for v, _ in items], [P(l, S_KPI_L) for _, l in items]]
    w = (A4[0] - 30 * mm) / len(items)
    t = Table(cells, colWidths=[w] * len(items))
    t.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.6, LINE),
        ("INNERGRID", (0, 0), (-1, -1), 0, colors.white),
        ("LINEAFTER", (0, 0), (-2, -1), 0.6, LINE),
        ("BACKGROUND", (0, 0), (-1, -1), BAND),
        ("TOPPADDING", (0, 0), (-1, 0), 7),
        ("BOTTOMPADDING", (0, 1), (-1, 1), 7),
    ]))
    return t


def note(text):
    t = Table([[P(text, S_SMALL)]], colWidths=[A4[0] - 30 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F7F7F9")),
                           ("LINEBEFORE", (0, 0), (0, -1), 2, ACCENT),
                           ("LEFTPADDING", (0, 0), (-1, -1), 6), ("TOPPADDING", (0, 0), (-1, -1), 4),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
    return t


H = lambda t: P(t, S_HEAD)
HR = lambda t: P(t, S_HEAD_R)
R = lambda t: P(t, S_CELL_R)
RB = lambda t: P(t, S_CELL_RB)
B = lambda t: P(t, S_CELL_B)
W = A4[0] - 30 * mm


def on_page(canvas, doc):
    canvas.saveState()
    w, h = A4
    canvas.setFillColor(ACCENT)
    canvas.rect(0, h - 6 * mm, w, 6 * mm, stroke=0, fill=1)
    canvas.setFont("Sans-Bold", 7)
    canvas.setFillColor(colors.white)
    canvas.drawString(15 * mm, h - 4.2 * mm, "MODELO PARA APROVAÇÃO  ·  VALORES ILUSTRATIVOS")
    canvas.drawRightString(w - 15 * mm, h - 4.2 * mm, f"Rua Iluminada 2025  ·  Fechamento de {DIA}")
    canvas.setFont("Sans", 6.8)
    canvas.setFillColor(MUTED)
    canvas.drawString(15 * mm, 9 * mm, f"SHA-256 do conteúdo: {HASH[:16]}…{HASH[-8:]}   ·   Dia travado após as duas assinaturas; correções só como ajuste no dia seguinte.")
    canvas.drawRightString(w - 15 * mm, 9 * mm, f"Página {doc.page}")
    canvas.restoreState()


# ---------- conteúdo ----------
def build(out):
    doc = SimpleDocTemplate(out, pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm,
                            topMargin=13 * mm, bottomMargin=15 * mm,
                            title=f"Relatório de fechamento do dia {DIA} (modelo)",
                            author="Rua Iluminada 2025", subject="Modelo para aprovação da equipe")
    s = []

    # cabeçalho
    head = Table([[P("Relatório de Fechamento do Dia", S_TITLE),
                   P(f'<b>{DIA}</b> ({DIA_SEMANA})<br/>Situação: <font color="{WARN.hexval()}"><b>Aguardando assinaturas</b></font>', st("hr", alignment=TA_RIGHT, fontSize=9.5, leading=13))],
                  [P("Rua Iluminada Família Moletta 2025 · evento Zet #538", S_SUB),
                   P("Gerado em 20/12/2025 23:12 · versão 1", st("hr2", alignment=TA_RIGHT, fontSize=8, textColor=MUTED))]],
                 colWidths=[W * 0.62, W * 0.38])
    head.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "BOTTOM"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                              ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("LINEBELOW", (0, 1), (-1, 1), 1, ACCENT),
                              ("BOTTOMPADDING", (0, 1), (-1, 1), 5)]))
    s += [head, Spacer(1, 6)]
    s.append(note(
        "Este relatório segue o <b>dinheiro</b>: cada valor entra no dia em que foi pago, estornado ou creditado. "
        "A catraca e o borderô mostram <b>pessoas</b> e nunca viram valor de caixa. Todas as contas são feitas pelo banco de dados, "
        "em centavos. Os dados da Zet vêm do webhook e da sincronização com o painel (robô, só leitura), feita às <b>22:47</b>. "
        "O online só fecha à meia-noite; o que aparecer depois entra no relatório de amanhã como ajuste."))
    s.append(Spacer(1, 6))

    # resumo
    s.append(kpis([
        (brl(venda_liq_dia), "Venda líquida do dia<br/>(bilheteria + online + comissões)"),
        (num(pess), "Pessoas no evento<br/>(catraca + validados Zet)"),
        (brl(tm_geral), "Ticket médio<br/>(sobre quem entrou)"),
        ("4", "Pontos de atenção<br/>(ver seção 7)"),
    ]))

    # 1. bilheteria
    s.append(P("1. Bilheteria por guichê", S_H1))
    data = [[H("Guichê"), HR("Fundo de troco"), HR("Venda"), HR("Dinheiro"), HR("Débito"),
             HR("Crédito"), HR("PIX"), HR("Estornos"), HR("Sangrias no dia")]]
    for r in guiche_rows:
        data.append([P(f"Guichê {r['g']}"), R(brl(r["fundo"])), R(brl(r["venda"])),
                     R(brl(r["din"])), R(brl(r["deb"])), R(brl(r["cred"])), R(brl(r["pix"])),
                     R(brl(-r["est"]) if r["est"] else "—"), R(brl(r["sang"]))])
    data.append([B("Total"), RB(brl(bil_fundos)), RB(brl(bil_venda)), RB(brl(bil_din)),
                 RB(brl(bil_deb)), RB(brl(bil_cred)), RB(brl(bil_pix)), RB(brl(-bil_est)), RB(brl(bil_sang_parc))])
    s.append(table(data, [W * x for x in (.09, .105, .115, .11, .11, .11, .115, .10, .145)], total_rows=1))
    s.append(Spacer(1, 3))
    s.append(P("Cartão e PIX são das maquininhas PagBank de cada guichê. Os estornos da bilheteria são sempre totais e registrados com o meio de pagamento. "
               "Cada guichê fecha o <b>dinheiro</b> e a <b>maquininha</b>; os ingressos são conferidos no total da bilheteria (seção 1.2).", S_SMALL))

    s.append(P("Conferência do dinheiro de cada guichê", S_H2))
    data = [[H("Guichê"), HR("Fundo + dinheiro − estornos − sangrias"), HR("Esperado na gaveta"), HR("Contado"),
             HR("Diferença"), H("Situação")]]
    for r in guiche_rows:
        data.append([P(f"Guichê {r['g']}"),
                     R(f"{brl(r['fundo'])} + {brl(r['din'])} − {brl(r['est'])} − {brl(r['sang'])}"),
                     R(brl(r["esperado"])), R(brl(r["contado"])),
                     R(brl(r["dif"], sign=True) if r["dif"] else "R$ 0,00"), status_chip(r["status"])])
    data.append([B("Total"), R(""), RB(brl(sum(r["esperado"] for r in guiche_rows))),
                 RB(brl(sum(r["contado"] for r in guiche_rows))), RB(brl(bil_dif, sign=True)), P("")])
    s.append(table(data, [W * x for x in (.09, .37, .15, .13, .12, .14)], total_rows=1))
    s.append(Spacer(1, 3))
    s.append(P("Tolerância (configurável por evento): até R$ 1,00 conciliado, justificativa opcional · de R$ 1,01 a R$ 50,00 justificativa obrigatória · "
               "acima de R$ 50,00 destacado para os assinantes. Quebra e sobra viram lançamento contábil, nunca são apagadas.", S_SMALL))

    # 1.2 bilheteria x catraca (total dos 9 guichês)
    s.append(P("1.2 Bilheteria × catraca (total dos 9 guichês)", S_H2))
    data = [[H("Tipo do cartão RFID"), HR("Entradas (usos consumidos)"), HR("Preço"), HR("Valor esperado")]]
    for t, n in zip(TIPOS, bil_entr_q):
        data.append([P(t), R(num(n)), R(brl(PRECO[t])), R(brl(n * PRECO[t]))])
    data.append([B("Esperado pela catraca"), RB(num(bil_entr)), R(""), RB(brl(val_bil_entr))])
    rec_bil = bil_venda - bil_est
    dif_cat = rec_bil - val_bil_entr
    data.append([B("Receita dos 9 guichês (venda − estornos)"), R(""), R(""), RB(brl(rec_bil))])
    data.append([B("Diferença"), R(""), R(""),
                 P(f'<b>{brl(dif_cat, sign=True)}</b> ({pct(abs(dif_cat), val_bil_entr)}) · <font color="{OK.hexval()}"><b>OK</b></font>', S_CELL_R)])
    s.append(table(data, [W * x for x in (.40, .22, .16, .22)], total_rows=3))
    s.append(Spacer(1, 3))
    s.append(P("Hoje não há controle de quantos ingressos cada guichê vendeu, por isso a conferência é da <b>bilheteria inteira</b>: a soma dos 9 guichês "
               "tem de bater com as entradas RFID do dia × preço do tipo (conta cada uso consumido: o cartão é revendido várias vezes no dia, então não se contam cartões distintos). Diferença positiva pequena é normal "
               "(cartão vendido que ainda não passou); acima de 5% é alerta e acima de 10% é crítico. É uma conferência: o valor do caixa é sempre o contado "
               "e o da maquininha. <b>Modo opcional \"por guichê\"</b>: se o evento controlar os cartões entregues a cada guichê, esta tabela aparece também "
               "em cada guichê, junto com a coluna de ingressos vendidos.", S_SMALL))

    # 2. online
    s.append(P("2. Vendas online e na máquina da Zet", S_H1))
    s.append(P(f'<font color="{INFO.hexval()}"><b>Parcial até 22:47</b></font> (sincronização com a Zet). O dia online termina à meia-noite; a sincronização da madrugada completa os números.', S_SMALL))
    s.append(Spacer(1, 3))
    data = [[H("Linha"), HR("Pedidos"), HR("Ingressos"), HR("Pago pelo cliente"), HR("Taxa Zet (10%)"), HR("Líquido do evento")],
            [P("Vendas online do dia (data do pagamento)"), R(num(on_pedidos)), R(num(sum(ON_Q))), R(brl(on_bruto)), R(brl(on_taxa)), R(brl(on_liq))],
            [P("(−) Estornos do dia (só o ingresso; a taxa não volta)"), R(num(on_est_ped)), R(num(on_est_ing)), R("—"), R("—"), R(brl(-on_est))],
            [P("(−) Contestação lançada hoje (venda de 29/11, extrato Zet)"), R("1"), R("4"), R("—"), R("—"), R(brl(-on_cb))],
            [P("(+) Vendas na <b>máquina da Zet</b> (importadas pelo robô)"), R(num(maq["pedidos"])), R(num(maq["ingressos"])), R(brl(maq_liq + maq_taxa)), R(brl(maq_taxa)), R(brl(maq_liq))],
            [P(f"      por meio de pagamento: débito {brl(maq['deb'])} · crédito {brl(maq['cred'])} · PIX {brl(maq['pix'])}", S_SMALL), "", "", "", "", ""],
            [P("(+) Vendas de 18/12 sem webhook, descobertas hoje"), R(num(desc_ped)), R("6"), R(brl(desc_liq + rate_bps(desc_liq, 1000))), R(brl(rate_bps(desc_liq, 1000))), R(brl(desc_liq))],
            [B("Total online do dia (a receber da Zet)"), R(""), R(""), R(""), R(""), RB(brl(on_total))]]
    s.append(table(data, [W * x for x in (.40, .09, .09, .14, .13, .15)], total_rows=1, extra=[("SPAN", (0, 5), (-1, 5))]))

    # 3. foods
    foods_head = P("3. Foods: comissões e repasses", S_H1)
    data = [[H("Loja"), HR("Vendas declaradas"), HR("Comissão"), HR("Comissão devida"), HR("Repasse recebido"),
             HR("Falta de repasse hoje"), HR("Saldo em aberto")]]
    for r in food_rows:
        data.append([P(r["nome"]), R(brl(r["vendas"])), R(f"{r['bps'] / 100:.1f}%".replace(".", ",")), R(brl(r["com"])),
                     R(brl(r["pago"])), R(brl(-r["falta"]) if r["falta"] else "—"),
                     P(f'<font color="{BAD.hexval()}"><b>{brl(r["aberto"])}</b></font>', S_CELL_R) if r["aberto"] else R("—")])
    data.append([B("Total"), RB(brl(sum(r["vendas"] for r in food_rows))), R(""), RB(brl(food_com)), RB(brl(food_pago)),
                 RB(brl(-food_falta)), RB(brl(sum(r["aberto"] for r in food_rows)))])
    s.append(KeepTogether([foods_head, table(data, [W * x for x in (.13, .16, .10, .15, .15, .15, .16)], total_rows=1)]))
    s.append(Spacer(1, 3))
    s.append(P("Percentual vigente de cada loja na data (cadastro com vigência). Loja que paga menos gera <b>falta de repasse</b>: a dívida continua em aberto e o alerta aparece até ser paga no próximo caixa.", S_SMALL))

    # 4. tesouraria
    s.append(P("4. Tesouraria e sangrias", S_H1))
    data = [[H("Movimento"), HR("Valor"), H("Detalhe")],
            [P("Saldo inicial da tesouraria"), R(brl(tes_ini)), P("Nada fica de um dia para o outro")],
            [P("(−) Fundos de troco entregues aos 9 guichês"), R(brl(-tes_fundos)), P("Valor por operador, registrado na abertura")],
            [P("(+) Sangrias parciais recebidas durante o dia"), R(brl(tes_rec_parc)), P("Registradas na hora: quem entregou, quem recebeu")],
            [P("(+) Sangria final dos guichês (venda + fundo de troco)"), R(brl(tes_rec_final)), P("Valor contado na seção 1")],
            [P("(+) Repasses das lojas em dinheiro"), R(brl(tes_food)), P("Seção 3")],
            [P("(−) Pagamento de despesa do evento"), R(brl(-despesa)), P("Locação de gerador · comprovante anexado")],
            [P("(−) Depósito na conta do evento"), R(brl(-deposito)), P("Banco (conta cadastrada) · conciliar com o extrato de amanhã")],
            [B("Saldo final da tesouraria"), RB(brl(tes_fim)), P(f'<font color="{OK.hexval()}"><b>Zerada</b></font>')]]
    s.append(table(data, [W * .48, W * .16, W * .36], total_rows=1))

    # 5. público e ticket médio
    s.append(P("5. Público do dia (pessoas, não entra no valor do caixa)", S_H1))
    data = [[H("Entradas")] + [HR(t) for t in ("Inteira", "Meia e equiv.", "Solidário", "Cortesia", "Total")]]
    def row(lbl, q, bold=False):
        f = RB if bold else R
        return [B(lbl) if bold else P(lbl)] + [f(num(x)) for x in q] + [f(num(sum(q)))]
    data.append(row("Bilheteria (catraca, cartão RFID)", bil_entr_q))
    data.append(row("Online validados pela equipe Zet", on_ent_q))
    data.append(row("   – comprados hoje", ON_ENT_HOJE))
    data.append(row("   – comprados em dias anteriores", ON_ENT_ANTES))
    data.append(row("Total de pessoas no evento", [a + b for a, b in zip(bil_entr_q, on_ent_q)], bold=True))
    s.append(table(data, [W * x for x in (.36, .12, .13, .12, .12, .15)], total_rows=1))
    s.append(Spacer(1, 3))
    s.append(P(f"Online com visita marcada para hoje: {num(on_previstos)} ingressos · validados {num(on_ent)} · <b>não validados {num(on_nao_valid)}</b> "
               f"(não compareceu ou falha de validação; o valor continua sendo do evento). "
               f"Bilheteria: {num(bil_entr)} entradas de cartão RFID consumidas na catraca; a conferência com a receita dos guichês está na seção 1.2.", S_SMALL))

    s.append(P("6. Ticket médio (sobre quem entrou)", S_H1))
    data = [[H("Indicador"), HR("Valor pago pelos ingressos de quem entrou"), HR("Pessoas"), HR("Ticket médio"), HR("Sem cortesias")],
            [P("Geral"), R(brl(val_bil_entr + val_on_entr)), R(num(pess)), RB(brl(tm_geral)), R(brl(tm_geral_sc))],
            [P("Bilheteria"), R(brl(val_bil_entr)), R(num(bil_entr)), RB(brl(tm_bil)), R(brl(tm_bil_sc))],
            [P("Online (valor líquido de cada voucher validado)"), R(brl(val_on_entr)), R(num(on_ent)), RB(brl(tm_on)), R(brl(tm_on_sc))]]
    s.append(table(data, [W * x for x in (.34, .24, .12, .15, .15)]))
    s.append(Spacer(1, 3))
    tot_ent = [a + b for a, b in zip(bil_entr_q, on_ent_q)]
    s.append(P("Mix de quem entrou: " + " · ".join(f"{t} {pct(n, sum(tot_ent))}" for t, n in zip(TIPOS, tot_ent)) +
               ". A venda média do dia (líquido vendido ÷ ingressos vendidos) é um indicador comercial separado e não substitui o ticket médio.", S_SMALL))

    prev_head = P("Previsão dos próximos dias (ingressos online já vendidos)", S_H2)
    data = [[H("Data da visita"), HR("Já vendidos"), HR("Comparecimento histórico"), HR("Estimativa online")],
            [P("21/12/2025 (domingo)"), R("890"), R("94,2%"), R("838")],
            [P("22/12/2025 (segunda)"), R("577"), R("94,2%"), R("544")],
            [P("23/12/2025 (terça)"), R("403"), R("94,2%"), R("380")]]
    s.append(KeepTogether([prev_head, table(data, [W * x for x in (.34, .2, .24, .22)])]))

    # 7. conciliações
    s.append(P("7. Conciliações e pontos de atenção", S_H1))
    data = [[H("Conferência"), H("Resultado"), H("Situação")],
            [P("Webhooks Zet do dia processados (fila vazia, nenhum com falha)"), P("1.017 recebidos (1.012 vendas e 5 estornos), 1.017 processados"), status_chip("OK")],
            [P("Sincronização com a Zet (robô, 22:47): pedidos do painel × sistema"), P("Valores iguais; 3 vendas de 18/12 sem webhook importadas; 59 vendas da máquina importadas"), status_chip("OK")],
            [P("Vouchers das vendas importadas (botão Detalhes)"), P("1 pedido com ingressos pendentes: valor já lançado, público marcado como incompleto"), status_chip("Alerta")],
            [P("Maquininhas PagBank × guichês (Extrato EDI, D+1)"), P("Dia 19/12: diferença R$ 0,00 · dia 20/12 confere amanhã"), status_chip("Pendente")],
            [P("Extrato bancário: depósito da sangria de 19/12"), P("Crédito encontrado no valor exato"), status_chip("OK")],
            [P("Guichê 4: diferença de −R$ 12,00"), P(JUSTIFICATIVAS[4]), status_chip("Justificar")],
            [P("Guichê 7: sobra de +R$ 63,00"), P(JUSTIFICATIVAS[7]), status_chip("Destacar")],
            [P("Loja 03: falta de repasse"), P("Pagou R$ 45,30 a menos hoje; R$ 143,30 em aberto com os dias anteriores. Cobrar no próximo caixa."), status_chip("Alerta")],
            [P("Bilheteria × catraca (total dos 9 guichês)"), P(f"Receita dos guichês {brl(bil_venda - bil_est)} × esperado pela catraca {brl(val_bil_entr)}: diferença {brl(bil_venda - bil_est - val_bil_entr, sign=True)} ({pct(abs(bil_venda - bil_est - val_bil_entr), val_bil_entr)}), abaixo do limite de 5%"), status_chip("OK")]]
    s.append(table(data, [W * .36, W * .50, W * .14]))

    # 8. conta-corrente Zet
    s.append(P("8. Conta-corrente com a Zet (acumulado do evento até hoje)", S_H1))
    data = [[H("Linha"), HR("Valor")],
            [P("(+) Vendas líquidas (online + máquina da Zet)"), R(brl(cc["vendido"]))],
            [P("(−) Estornos"), R(brl(-cc["estornos"]))],
            [P("(−) Contestações (chargeback e devolução PIX), só pelo extrato da Zet"), R(brl(-cc["contestacoes"]))],
            [B("(=) Devido pela Zet ao evento"), RB(brl(cc_devido))],
            [P("(−) Repasses já recebidos (conferidos no extrato bancário)"), R(brl(-cc["repasses"]))],
            [P("(−) Taxas de saque"), R(brl(-cc["taxas_saque"]))],
            [B("(=) Saldo a receber da Zet"), RB(brl(cc_saldo))],
            [P("Valor ainda em risco (vendas dentro do prazo de estorno ou contestação)"), P(f'<font color="{WARN.hexval()}">{brl(cc_risco)}</font>', S_CELL_R)]]
    s.append(table(data, [W * .72, W * .28], extra=[("BACKGROUND", (0, 4), (-1, 4), colors.HexColor("#EEE8F3")),
                                                   ("BACKGROUND", (0, 7), (-1, 7), colors.HexColor("#EEE8F3"))], zebra=False))

    # 9. assinaturas
    qr = QrCodeWidget(f"RUA-ILUMINADA-2025|FECHAMENTO|2025-12-20|v1|sha256:{HASH}")
    b = qr.getBounds()
    size = 26 * mm
    d = Drawing(size, size, transform=[size / (b[2] - b[0]), 0, 0, size / (b[3] - b[1]), 0, 0])
    d.add(qr)
    sig = lambda n: [P(f"<b>Assinante designado {n}</b><br/>Nome: ______________________________<br/>Função: _____________________________"
                       f"<br/>Designação vigente desde: ___/___/______<br/>Assinado em: ___/___/______ às ___:___", S_CELL),
                     ]
    sigt = Table([[sig(1)[0], sig(2)[0]], [P("_" * 44, S_SMALL), P("_" * 44, S_SMALL)]], colWidths=[W * .5 - 16 * mm] * 2)
    sigt.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("TOPPADDING", (0, 1), (-1, 1), 14),
                              ("LEFTPADDING", (0, 0), (-1, -1), 0)]))
    block = Table([[sigt, d]], colWidths=[W - 30 * mm, 30 * mm])
    block.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0)]))
    s.append(KeepTogether([
        P("9. Aprovação", S_H1),
        P("As duas pessoas designadas no momento da assinatura assinam o <b>mesmo conteúdo</b> (o código abaixo). "
          "Depois das duas assinaturas, o dia é travado: nenhum valor muda. Correção posterior entra como ajuste no dia seguinte, "
          "com motivo e responsável, e a reabertura só é possível por administrador, com registro.", S_BODY),
        Spacer(1, 6), block,
        P(f"Código do conteúdo (SHA-256): {HASH}", S_SMALL),
    ]))

    # anexo: o que a equipe aprova
    s.append(PageBreak())
    s.append(P("Para a equipe: o que muda e o que precisa ser aprovado", S_H1))
    s.append(P("Esta página não faz parte do relatório diário; acompanha só o modelo.", S_SMALL))
    s.append(P("O que muda em relação ao relatório atual", S_H2))
    muda = [
        "O fechamento segue o dinheiro. A catraca e o borderô da Zet mostram pessoas e não entram mais no valor do caixa.",
        "Todas as contas são feitas pelo sistema, em centavos. O assistente de IA só orienta, não calcula nem grava valores.",
        "Online entra pelo valor líquido do evento (a taxa de 10% é da Zet). O estorno devolve só o ingresso.",
        "Entram duas fontes que o sistema antigo não via: vendas na máquina da Zet e contestações (chargeback e devolução PIX), trazidas pelo robô.",
        "Cada guichê fecha separado o dinheiro e a maquininha, com fundo de troco por operador e sangrias registradas na hora. Os ingressos são conferidos no total da bilheteria × catraca. A tesouraria termina o dia zerada.",
        "Falta de repasse das lojas fica em aberto e aparece todo dia até ser paga.",
        "Ticket médio calculado sobre quem entrou, com e sem cortesias; a venda média do dia fica como indicador comercial à parte.",
        "Duas assinaturas das pessoas designadas no momento, sobre o mesmo conteúdo. Depois disso o dia não muda.",
    ]
    s.append(table([[P("•"), P(t)] for t in muda], [W * .04, W * .96], head_rows=0, zebra=False,
                   extra=[("LINEBELOW", (0, 0), (-1, -1), 0.25, LINE)]))
    s.append(P("Itens para aprovação", S_H2))
    itens = [
        "Ordem e conteúdo das seções 1 a 9.",
        "Tolerâncias: até R$ 1,00 / R$ 1,01 a R$ 50,00 / acima de R$ 50,00 (valores configuráveis).",
        "Conferência dos ingressos da bilheteria no total dos 9 guichês × catraca (padrão), ou também por guichê (opcional, exige controle dos cartões entregues a cada guichê).",
        "Limites da conferência bilheteria × catraca: alerta acima de 5%, crítico acima de 10%.",
        "Online marcado como parcial no fechamento dos caixas e completado pela sincronização da madrugada.",
        "Vendas descobertas depois do fechamento entram como ajuste no dia seguinte, sem reabrir o dia.",
        "Vendas na máquina da Zet: mostradas na seção 2 ou também dentro do guichê que operou a máquina?",
        "Quem são os dois assinantes designados e quem pode reabrir um dia (somente administrador).",
        "Campos que faltam ou sobram para a equipe.",
    ]
    s.append(table([[P("[   ]"), P(t), P("")] for t in itens], [W * .07, W * .63, W * .30], head_rows=0, zebra=False,
                   extra=[("LINEBELOW", (0, 0), (-1, -1), 0.25, LINE)]))
    s.append(Spacer(1, 4))
    s.append(P("Observações da equipe:", S_BODY))
    for _ in range(6):
        s.append(P("_" * 118, S_SMALL))
        s.append(Spacer(1, 4))

    doc.build(s, onFirstPage=on_page, onLaterPages=on_page)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "modelo-relatorio-fechamento.pdf"
    build(out)
    print(out, HASH)
