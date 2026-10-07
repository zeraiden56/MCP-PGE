# Fase 1 — análise e matriz de integração

Pesquisa em 07/10/2026. Diretório inicialmente vazio, sem código ou instruções locais.
Análise apresentada ao usuário antes da Fase 2. Confirmação documental não equivale
a homologação de disponibilidade: nenhuma consulta real de processo foi executada.

## Matriz de capacidades

| Tribunal | Fonte oficial / documentação | Tipo | Autenticação | CNJ | Movimentos | Partes | Documentos | Situação e estratégia |
|---|---|---|---|---|---|---|---|---|
| TRF1 | [Endpoints CNJ][endpoints], [manual MNI TRF1][trf1] | DataJud HTTP POST/JSON; alternativa SOAP MNI | DataJud: chave pública rotativa; MNI: habilitação institucional a confirmar | Sim | Sim | Não no DataJud | Não no DataJud | DataJud implementável; MNI pending |
| TJMT | [Endpoints CNJ][endpoints], [MNI institucional TJMT][tjmt] | DataJud HTTP POST/JSON | Chave pública do CNJ | Sim | Sim | Não no DataJud | Não no DataJud | DataJud implementável; API direta pending |
| STJ | [Catálogo oficial STJ][stj], [endpoints CNJ][endpoints] | DataJud HTTP POST/JSON | Chave pública do CNJ | Sim, quando indexado | Sim | Não no DataJud | Não no DataJud | DataJud implementável |
| STF | [Integração de órgãos][stf], [Corte Aberta][corte] | MNI institucional e bases estatísticas; sem API pública adequada confirmada | Credenciamento para integração institucional; mecanismo técnico depende do acordo | Não confirmado para API pública | Não confirmado | Não confirmado | Não confirmado | unsupported no MCP; MNI pending |

TRF1, TJMT e STJ têm API pública documentada via CNJ. Os três aliases constam
expressamente do catálogo. STF não consta; não construir `api_publica_stf`.
Para STF: **Não foi possível confirmar uma API pública oficial adequada.**

Consulta pública web existe nos quatro tribunais, mas não constitui contrato de API:
[TRF1][webtrf1], [TJMT][webtjmt], [STJ][stj], [STF][webstf].
Não haverá scraping, automação de navegador, CAPTCHA ou tentativa de acessar rotas privadas.

## Contrato confirmado do DataJud

- `POST https://api-publica.datajud.cnj.jus.br/api_publica_trf1/_search`
- `POST https://api-publica.datajud.cnj.jus.br/api_publica_tjmt/_search`
- `POST https://api-publica.datajud.cnj.jus.br/api_publica_stj/_search`

[Autenticação][acesso]: header `Authorization: APIKey <chave>`; chave somente em
`DATAJUD_API_KEY`. Não copiar a chave da documentação para arquivos ou fixtures.
[Exemplo oficial][exemplo]: consulta `match` de `numeroProcesso`, normalizado em 20 dígitos.
[Glossário][glossario]: capas, assuntos, órgão julgador e movimentos; não há contrato
público para partes, documentos ou situação processual consolidada. Arrays vazios
nesses campos vêm acompanhados de capacidades `unsupported`; situação será `null`.

Limitações: atualização depende da remessa/indexação; ausência não prova inexistência;
um número pode produzir várias capas/instâncias. Retornar todas em `processos`,
preservando `id_origem`, `grau`, `tribunal_origem`, `fonte_consulta` e timestamps.
Paginação incompleta/timeout/shards com falha serão erros, nunca sucesso parcial em cache.
O serviço público resguarda sigilo; o cliente acrescentará filtro `nivelSigilo=0`
e exigirá confirmação desse nível em cada registro antes de normalizar ou persistir.

## Termos, limites e alternativas

[Termos DataJud][termos]: uso sujeito ao termo, restrições de finalidade comercial,
responsabilidade do consumidor e ausência de garantia de atualidade. Revisar o termo
integral antes de uso operacional. Não foi localizada quota numérica de requisições
nas páginas consultadas. Intervalo local de 1 segundo, até 2 retries, backoff e
`Retry-After` são decisões conservadoras do projeto, não limites oficiais anunciados.
Não testar endpoints com credenciais emprestadas ou automaticamente coletadas.

MNI TRF1 tem manual e WSDLs publicados, mas habilitação, permissões e escopo devem
ser confirmados com o tribunal. O material TJMT confirma integração institucional,
sem contrato público suficiente localizado para um cliente genérico. No STJ,
o próprio catálogo orienta DataJud. No STF, avaliar credenciamento MNI; bases CSV/XLSX
do Corte Aberta podem apoiar análises, mas não substituem consulta processual completa.

A [Portaria CNJ 316/2024 hospedada no STJ][portaria] trata de acesso ao datalake do
**CNJ**, não é documentação de uma API própria do STJ. Uma alternativa futura é
solicitar acesso institucional e contrato técnico adequado, sem inventar endpoints.

## Arquitetura decidida

Um servidor Ruby com SDK MCP oficial via stdio; quatro ferramentas genéricas.
Ferramentas delegam ao serviço, que resolve origem, verifica capacidades/cache,
consulta client, valida mapper e persiste transacionalmente no PostgreSQL.
TRF1/TJMT/STJ são adaptadores finos sobre DataJud; STF falha explicitamente.
Contrato canônico serializável permite substituir um client por RPC em outra
linguagem futuramente. Não há subprocessos arbitrários ou RPC remoto nesta versão.

Parser segue [Resolução CNJ 65][cnj]: todos os seis campos, módulo 97, zeros à
esquerda, tabela de segmentos e tribunais; unidade de origem preservada. Origem
0000 corresponde a tribunal; 9xxx pode corresponder a turma recursal e 9999 é
tratado distintamente. Não deduzir nome da vara nem grau atual só pelo número.
Recursos podem conservar número de origem: nesta versão não há busca federada
automática por tramitação no STJ/STF. Resolver é de origem, não de localização atual.

Banco guarda várias capas por número, com chave `(numero_cnj_normalizado, tribunal,
id_origem)`. Cache por origem/número; snapshot canônico e tabelas normalizadas são
atualizados na mesma transação. Sincronização registra tentativas sem resultado com
`processo_id` nulo e número pesquisado. Falhas não renovam TTL. Respostas públicas
validadas podem ser preservadas, opcionalmente, para auditoria no banco privado.
Conexão PostgreSQL direta, inclusive Supabase; schema privado sem exposição PostgREST.

[endpoints]: https://datajud-wiki.cnj.jus.br/api-publica/endpoints/
[acesso]: https://datajud-wiki.cnj.jus.br/api-publica/acesso/
[exemplo]: https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo1/
[glossario]: https://datajud-wiki.cnj.jus.br/api-publica/glossario/
[termos]: https://datajud-wiki.cnj.jus.br/api-publica/termo-uso/
[trf1]: https://www.trf1.jus.br/trf1/conteudo/NUGTI/MNI_Orienta%C3%A7%C3%B5es.pdf
[tjmt]: https://www.tjmt.jus.br/noticias/2015/7/tj-faz-a-1-integracao-sistema-externo-pje
[stj]: https://dadosabertos.web.stj.jus.br/dataset/api-publica-datajud
[stf]: https://portal.stf.jus.br/textos/verTexto.asp?pagina=orgaos&servico=processoIntegracaoOrgaoAssociado
[corte]: https://noticias.stf.jus.br/postsnoticias/corte-aberta-reune-dados-do-stf-em-paineis-interativos-e-bases-para-download/
[webtrf1]: https://www.trf1.jus.br/trf1/carta-de-servicos/carta-deservicos
[webtjmt]: https://wiki.tjmt.jus.br/images/6/65/Manual_-_PJe_-_2.0_-_Acesso_ao_PJe_.pdf
[webstf]: https://portal.stf.jus.br/processos/detalhe.asp?incidente=6470680
[cnj]: https://atos.cnj.jus.br/atos/detalhar/119
[portaria]: https://stj.jus.br/internet_docs/biblioteca/clippinglegislacao/Prt_pres_316_2024.pdf
