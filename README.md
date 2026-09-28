# Terra Nova Distribuidora — versão de testes

Abra `index.html` em um navegador para testar. Os dados ficam somente no armazenamento local daquele navegador.

## Fluxos disponíveis

- Produtos e entrada de lotes com validade, custo e taxa fiscal de 0% a 3%.
- Venda com cliente, produto, quantidade, validade mínima, condição de pagamento, frete e conta de cobrança. A saída de estoque usa FEFO.
- Contas a receber, pagamentos parciais, referência de comprovante e despesas diárias.
- Cadastro de contas Banco do Brasil e Bradesco; movimentação bancária manual e vínculo com recebível do mesmo valor. A conciliação é opcional.

## Pendências para operação real

Esta versão valida o fluxo. Ainda faltam autenticação, permissões, PostgreSQL/Supabase, armazenamento de anexos, importação de NF XML/foto, rastreio de entrega, cálculos tributários por UF, custo de capital, geração de boletos pelas APIs dos bancos, importação de extrato/Open Finance e implantação mobile. O botão Boleto não emite título bancário válido. Não usar com dados reais ou como controle financeiro de produção.

Para execução local com servidor: `python3 -m http.server 8000 --directory terra-nova`, depois acesse `http://localhost:8000`.
