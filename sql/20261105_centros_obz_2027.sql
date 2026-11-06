-- OBZ 2027: cadastros de centros da Planilha Mestra (21 centros operacionais).
-- Não contém valores financeiros e não altera pacotes já cadastrados.
-- Executar no SQL Editor do projeto Supabase de homologação após revisão.
begin;
insert into public.obz_centers (code,name,fiscal_year,source_name)
values
 ('CAMPANHAS','CAMPANHAS',2027,'Planilha Mestra OBZ 2027'),
 ('CDL_CULTURA','CDL CULTURA',2027,'Planilha Mestra OBZ 2027'),
 ('CDL_IA','CDL IA',2027,'Planilha Mestra OBZ 2027'),
 ('CDL_INOVACAO','CDL INOVAÇÃO',2027,'Planilha Mestra OBZ 2027'),
 ('CDL_JOVEM','CDL JOVEM',2027,'Planilha Mestra OBZ 2027'),
 ('CDL_MULHER','CDL MULHER',2027,'Planilha Mestra OBZ 2027'),
 ('CERTIFICACAO_DIGITAL','CERTIFICACAO DIGITAL',2027,'Planilha Mestra OBZ 2027'),
 ('COMERCIAL','COMERCIAL',2027,'Planilha Mestra OBZ 2027'),
 ('EVENTOS','EVENTOS',2027,'Planilha Mestra OBZ 2027'),
 ('FINANCEIRO','FINANCEIRO',2027,'Planilha Mestra OBZ 2027'),
 ('FORUM_CDL','FORUM CDL',2027,'Planilha Mestra OBZ 2027'),
 ('GOVERNANCA','GOVERNANÇA',2027,'Planilha Mestra OBZ 2027'),
 ('INFRAESTRUTURA','INFRAESTRUTURA',2027,'Planilha Mestra OBZ 2027'),
 ('LOCACAO_ESPACOS','LOCACAO DE SALAS E ESPACOS',2027,'Planilha Mestra OBZ 2027'),
 ('MARKETING','MARKETING',2027,'Planilha Mestra OBZ 2027'),
 ('MENSALIDADES_E_ASSOCIACOES','MENSALIDADES E ASSOCIACOES',2027,'Planilha Mestra OBZ 2027'),
 ('SERVICOS_DE_TERCEIROS','SERVIÇOS DE TERCEIROS',2027,'Planilha Mestra OBZ 2027'),
 ('REVISTA','REVISTA',2027,'Planilha Mestra OBZ 2027'),
 ('SPC_BRASIL','SPC BRASIL',2027,'Planilha Mestra OBZ 2027'),
 ('TECNOLOGIA_DA_INFORMACAO','TECNOLOGIA DA INFORMACAO',2027,'Planilha Mestra OBZ 2027'),
 ('TRANSPORTE','TRANSPORTE',2027,'Planilha Mestra OBZ 2027')
on conflict(code) do nothing;
commit;
-- Conferência: 21 centros + "(Geral)" (resumo consolidado, não deve virar pacote).
select code,name,status from public.obz_centers where fiscal_year=2027 order by name;