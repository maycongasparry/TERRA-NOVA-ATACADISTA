# Terra Nova Distribuidora — versão de testes

Abra `index.html` em um navegador para testar. Os dados ficam somente no armazenamento local daquele navegador.

## Fluxos disponíveis

- Produtos e entrada de lotes com validade, custo e taxa fiscal de 0% a 3%.
- Venda com cliente, produto, quantidade, validade mínima, condição de pagamento, frete e conta de cobrança. A saída de estoque usa FEFO.
- Contas a receber, pagamentos parciais, referência de comprovante e despesas diárias.
- Cadastro de contas Banco do Brasil e Bradesco; movimentação bancária manual e vínculo com recebível do mesmo valor. A conciliação é opcional.

## Limites do protótipo local

`index.html` continua como demonstração local. O piloto conectado está em `piloto.html`.

Para execução local com servidor: `python3 -m http.server 8000 --directory terra-nova`, depois acesse `http://localhost:8000`.

## Piloto conectado ao Supabase

Abra `piloto.html` no GitHub Pages. Ele usa apenas a URL e a chave publishable do projeto Supabase; não há chave secreta no código.

1. Em `piloto.html`, crie seu usuário por e-mail e senha. Confirme o e-mail recebido e volte ao piloto para entrar.
2. O primeiro login exibirá “Aguardando vínculo de administrador”. No SQL Editor, execute `002_acesso_admin.sql` após trocar `EMAIL_DO_ADMIN` pelo e-mail confirmado. Execute uma vez.
3. Execute `003_modulos_operacionais.sql` no SQL Editor **uma vez**, após as etapas 001 e 002.
4. Execute `004_pedidos_multiplos.sql` **uma vez**, após 003. Publique `index.html`, `prototipo.html`, `piloto.html`, `piloto.js` e `modulos.js` na raiz. A página principal abrirá `piloto.html`; a antiga demonstração ficará em `prototipo.html`.

As onze abas conectadas incluem estoque, sugestão de compras, pedidos, financeiro, bancos, relatórios de vendas, representantes, campanhas, clientes, fornecedores e transportadoras. A venda aceita vários produtos e uma cobrança por pedido. O registro de venda, baixa por validade e criação do valor a receber são atômicos no banco. Pagamentos são registrados sem precisar conciliar. A conciliação manual exige lançamento de entrada e pagamento do mesmo valor. Um CSV de extrato com cabeçalho `data;valor;descricao;id` pode ser importado manualmente, até 1.000 lançamentos por arquivo. `id` é opcional; a repetição do mesmo arquivo é detectada por hash e número da linha quando não há id.

A sugestão de compras usa vendas dos últimos 30 dias, estoque não vencido e o período de cobertura escolhido. O faturamento por SKU serve para ordenar a prioridade. Sem histórico de vendas, a sugestão é zero. Avalie lead time, margem, sazonalidade e quantidades mínimas de compra antes de comprar.

Ainda não há captura de notas e comprovantes, várias parcelas no mesmo pedido, estorno de venda, cálculo tributário por UF, rastreio de carga, integração automática com bancos, emissão real de boletos nem importação automática de extrato. A opção "Boleto" apenas registra a forma de pagamento combinada. Não use o piloto como único controle financeiro da operação.

Os arquivos SQL são migrações sequenciais. Não repita uma etapa que já foi executada com sucesso.
