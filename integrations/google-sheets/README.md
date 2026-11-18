# Sincronização do OBZ 2027 com a Planilha Mestra

A integração lê os eventos de alteração mensal do OBZ e sincroniza a aba Orçamento 2027 pelo Apps Script executado sob uma conta com permissão de edição. A aba Sincronização OBZ registra a situação por evento, incluindo os 12 valores salvos no OBZ.

## Ativação

1. Aplique a migração `sql/obz_sheet_sync.sql`.
2. No Supabase Vault, cadastre `obz_sheets_sync_token` com um segredo aleatório de pelo menos 32 caracteres.
3. Na Planilha Mestra, abra **Extensões → Apps Script** e adicione o conteúdo de `Code.gs`. Nas propriedades do script, cadastre `OBZ_SYNC_TOKEN` com o mesmo segredo e `SUPABASE_PUBLISHABLE_KEY` com a chave pública do projeto. Use a chave pública, nunca uma chave administrativa.
4. Execute `instalarSincronizacaoOBZ` com uma conta editora e autorize o acesso à planilha e à rede. A instalação registra o ponto inicial para processar alterações futuras.
5. Faça uma alteração real autorizada, confira o valor na aba Orçamento 2027 e consulte a situação em Sincronização OBZ.

A sincronização confere o centro, a natureza, o código contábil e a descrição. Escreve somente nos meses alterados da linha identificada, desde que a célula contenha o valor anterior esperado e não tenha fórmula. Registra para revisão fórmulas, valores divergentes e rubricas sem vínculo (incluindo a CBS do CDL IA enquanto a Planilha Mestra não tiver uma linha correspondente). Células originalmente calculadas requerem a definição da célula de entrada que deve ser atualizada. Os totais anuais são calculados pelas fórmulas existentes.
