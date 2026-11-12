# CDL Novo Hamburgo | OBZ 2027 — Avaliação UX e metodologia OBZ
Data: 12/11/2026
Escopo: experiência dos gestores nos 21 pacotes e 366 rubricas.
Status: propostas para homologação; não substituir o orçamento original.

## Entregas implementadas nesta branch
- Grade com linha por rubrica: valor-base (“esforço máximo”), ação/valor/consequência dos cenários intermediário e severo.
- Justificativa e alternativas na linha expansível da rubrica, sem navegação ao final da página.
- Distribuição mensal dos dois cenários, separada do valor-base da Planilha Mestra.
- Replicação da lógica de janeiro para fevereiro–dezembro: mesmo valor, mesma variação percentual ou mesma diferença em reais.
- Prévia com total anual e diferença, confirmação, possibilidade de desfazer antes de salvar.
- Atualização automática do total anual a partir dos 12 meses editados.
- Salvamento em lote transacional, auditoria, controle de concorrência, permissões por gestor e proteção contra troca de pacote com rascunho.
- Edição excepcional da base mensal pelo administrador, com replicação e aviso de divergência da fonte.
- Testes de regressão em GitHub Actions e consultas transacionais com rollback no Supabase.

## Backlog priorizado: etapa seguinte (não implementado nesta branch)

| Prioridade | Melhoria | Benefício ao gestor | Critério de aceite |
|---|---|---|---|
| P1 | Indicar premissa/driver da rubrica: quantidade × preço unitário, frequência e reajuste | Impede cortes genéricos e ajuda a desafiar necessidade, volume e preço | Gestor vê custo por unidade e recalcula estimativa anual |
| P1 | Classificar cada rubrica em obrigatória, contratual, estratégica e discricionária | Separa compromissos legais de escolhas gerenciais; não trata todas as rubricas como cortáveis | Classificação editável com justificativa para exceções e vencimento de contrato |
| P1 | Selecionar qual cenário do pacote será defendido ao comitê | Converte alternativas em decisão inequívoca | Somente um cenário é “defendido” por versão; revisão mostra impacto e justificativa |
| P1 | Integrar cenários detalhados ao Painel executivo e à aba Cenários | Acaba com simulador isolado do trabalho real | Total consolidado por cenário usa meses salvos e diferencia rubricas pendentes |
| P1 | Tornar explícita a completude dos dois cenários (ação + 12 meses + consequência) | Evita submissão com cortes sem trade-offs | Indicador e filtros por incompletude; eventual bloqueio depende de decisão de governança |
| P1 | Correção de sazonalidade e “aplicar de março em diante” | Facilita contratos com início/fim, indexadores e despesas não lineares | Usuário determina mês inicial/final e vê projeção antes de confirmar |
| P2 | Operações em lote sobre rubricas selecionadas | Reduz tempo de análise de contratos e despesas similares | Aplicar percentual/valor às rubricas marcadas com prévia, confirmação e undo |
| P2 | Edição por teclado e navegação horizontal acessível | Melhora o uso da grade por gestores | Tab segue sequência, Enter confirma campo e colunas fixas permanecem legíveis em telas menores |
| P2 | Rascunho local recuperável em caso de queda de conexão, com tempo e versão | Evita perda de preenchimento longo | Retomar rascunho só após validação de usuário, pacote e versão de linha |
| P2 | Relatório comparativo PDF para Conselho | Reduz compilação manual na governança | Pacote exporta base vs cenários, variação financeira, metas e consequências com data e versão |

## Princípios de metodologia
1. **Esforço máximo** é fotografia imutável da base 2027, não proposta de corte.
2. **Intermediário** preserva entregas prioritárias com ganhos plausíveis de eficiência.
3. **Severo** representa o menor esforço viável, com explicitacão de riscos, metas comprometidas e serviços eventualmente suspensos.
4. Cortes devem considerar custo fixo/variável, contratos, pessoas, compliance, sazonalidade e receita induzida. Nunca aplicar reduções lineares a rubricas sem analisar consequências.
5. A diferença financeira não é a única métrica de decisão. O comitê deve avaliar riscos, capacidade e alinhamento a RK/metas.
6. Rascunhos e simulações nunca substituem automaticamente orçamento aprovado, Planilha Mestra ou saldos de compras.

## Regras de homologação
- Testar ao menos um pacote com receitas e despesas.
- Verificar cenário intermediário de valor constante e variação percentual em meses sazonais.
- Verificar janeiro de base zero: replicação percentual deve ser bloqueada com orientação.
- Conferir total anual = soma 12 meses, inclusive valores negativos/deduções.
- Confirmar que salvar duas rubricas é atômico e bloquear concorrência/stale data.
- Testar o fluxo de edição com gestor e administrador (direitos distintos).
- Validar filtros, rolagem horizontal, celular, estado de salvamento e auditoria.
- Somente após esses testes mesclar no ramo de homologação.
