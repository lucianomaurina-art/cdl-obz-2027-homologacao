const OBZ = {
  spreadsheet: '1MiRtyjsR4plGiaone1x-89DcyMX8UzsDmVKptzKZ9E4',
  sheetId: 587542658,
  endpoint: 'https://uswsagujxwcfvauulhzq.supabase.co/rest/v1/rpc/obz_sheet_changes',
  log: 'Sincronização OBZ'
};

function instalarSincronizacaoOBZ() {
  const props = PropertiesService.getScriptProperties();
  if (!props.getProperty('OBZ_CURSOR')) {
    props.setProperty('OBZ_CURSOR', consultarOBZ(null).cursor);
  }
  if (!ScriptApp.getProjectTriggers().some(trigger => trigger.getHandlerFunction() === 'sincronizarOBZ')) {
    ScriptApp.newTrigger('sincronizarOBZ').timeBased().everyMinutes(1).create();
  }
}

function consultarOBZ(cursor) {
  const props = PropertiesService.getScriptProperties();
  const key = props.getProperty('SUPABASE_PUBLISHABLE_KEY');
  const token = props.getProperty('OBZ_SYNC_TOKEN');
  if (!key || !token) throw new Error('Configure as propriedades da integração.');
  const response = UrlFetchApp.fetch(OBZ.endpoint, {
    method: 'post',
    contentType: 'application/json',
    headers: { apikey: key, 'x-obz-sync-token': token },
    payload: JSON.stringify({ p_after: cursor }),
    muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) throw new Error('Falha ao consultar OBZ: HTTP ' + response.getResponseCode());
  return JSON.parse(response.getContentText());
}

function normalizarOBZ(value) {
  return String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_|_$/g, '');
}

function centavosOBZ(value) {
  return typeof value === 'number' && Number.isFinite(value) ? Math.round(value * 100) : null;
}

function planejarOBZ(event, labels, values, formulas) {
  const [, center] = /^OBZ2027:(.+):\d+$/.exec(event.source_key) || [];
  const group = event.category === 'revenue' ? 'RECEITAS' : 'DESPESAS';
  const matches = [];
  if (center) labels.forEach(([name, type, , account, description], index) => {
    if (normalizarOBZ(name) === center && normalizarOBZ(type) === group &&
        String(account).trim() === String(event.account ?? '').trim() &&
        String(description).trim() === event.description.trim()) matches.push(index);
  });
  if (matches.length !== 1) return { reason: matches.length ? 'Rubrica duplicada na aba' : 'Rubrica sem vínculo na aba', writes: [] };
  const index = matches[0], writes = [], conflicts = [];
  for (let month = 0; month < 12; month++) {
    const amount = centavosOBZ(event.months[month]);
    const before = centavosOBZ(event.previous[month]);
    if (amount === before) continue;
    const current = centavosOBZ(values[index][month]);
    if (current === amount && amount !== null) continue;
    if (formulas[index][month] || current !== before || amount === null) conflicts.push(month + 1);
    else writes.push({ month, amount: event.months[month] });
  }
  return { row: index + 1, writes, reason: conflicts.length ? 'Fórmula ou divergência nos meses ' + conflicts.join(', ') : '' };
}

function sincronizarOBZ() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) return;
  try {
    const props = PropertiesService.getScriptProperties();
    const cursor = props.getProperty('OBZ_CURSOR');
    if (!cursor) throw new Error('Execute instalarSincronizacaoOBZ primeiro.');
    const events = consultarOBZ(cursor);
    if (!events.length) return;
    const book = SpreadsheetApp.openById(OBZ.spreadsheet);
    const sheet = book.getSheets().find(item => item.getSheetId() === OBZ.sheetId);
    if (!sheet) throw new Error('A aba Orçamento 2027 está indisponível.');
    const headers = sheet.getRange('G8:R8').getDisplayValues()[0];
    if (headers.join(' ') !== 'Jan Fev Mar Abr Mai Jun Jul Ago Set Out Nov Dez') throw new Error('Confira as colunas dos meses.');
    const log = book.getSheetByName(OBZ.log) || book.insertSheet(OBZ.log);
    if (!log.getLastRow()) log.appendRow(['Evento', 'Salvo em', 'Rubrica', 'Situação', 'Detalhe', ...headers]);
    const rowCount = sheet.getLastRow();
    const labels = sheet.getRange(1, 2, rowCount, 5).getDisplayValues();
    for (const event of events) {
      const seen = log.getRange(1, 1, log.getLastRow(), 1).createTextFinder('OBZ-' + event.id).matchEntireCell(true).findNext();
      if (!seen) {
        const grid = sheet.getRange(1, 7, rowCount, 12);
        const result = planejarOBZ(event,labels,grid.getValues(),grid.getFormulas());
        for (const write of result.writes) {
          const cell = sheet.getRange(result.row,7+write.month);
          if (cell.getFormula() || centavosOBZ(cell.getValue()) !== centavosOBZ(event.previous[write.month])) {
            throw new Error('Alteração concorrente na aba. A próxima execução vai reavaliar os valores.');
          }
          cell.setValue(write.amount);
        }
        SpreadsheetApp.flush();
        log.appendRow(['OBZ-' + event.id,event.saved_at,"'" + event.description,
          result.reason ? 'Revisar' : 'Sincronizado',result.reason,...event.months]);
        SpreadsheetApp.flush();
      }
      props.setProperty('OBZ_CURSOR',event.id);
    }
  } finally { lock.releaseLock(); }
}
