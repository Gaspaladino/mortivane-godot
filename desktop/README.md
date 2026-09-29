# Mortivane — versão desktop (Electron)

Empacota `MortivaneV98.html` como um aplicativo de desktop (Windows, Linux, Mac) pronto para
subir na Steam. O jogo continua sendo o mesmo HTML: o Electron só abre ele numa janela própria.

## Requisitos

- [Node.js](https://nodejs.org) 20 ou mais novo
- Na primeira vez, dentro desta pasta: `npm install`

## Comandos

| Comando | O que faz |
|---|---|
| `npm start` | Abre o jogo numa janela (modo desenvolvimento, com modo administrador) |
| `npm run build:win` | Gera `dist/win-unpacked/Mortivane.exe` e `dist/Mortivane-<versão>-win.zip` |
| `npm run build:win:full` | Igual ao anterior, mas grava o ícone e os dados no `.exe`. **Rode no Windows.** |
| `npm run build:linux` | Gera `dist/linux-unpacked/mortivane` |
| `npm run build:mac` | Gera o `.app` (rode num Mac) |

Todo comando copia antes o `MortivaneV98.html` da raiz do repositório para `game/index.html`.
Para publicar uma versão nova do jogo, basta editar o HTML e rodar o build de novo.

## O que muda na versão desktop

- Abre em tela cheia (lembra a escolha). **F11** ou **Alt+Enter** alternam.
- O menu ganha os botões **Tela cheia / Modo janela** e **Sair do jogo**.
- Na versão empacotada, o **modo administrador fica escondido**. Para testar com ele,
  rode `npm start` ou abra o executável com `--admin`.
- O save da run (botão **Continuar run** no menu) fica na pasta de dados do usuário:
  - Windows: `%APPDATA%\Mortivane`
  - Linux: `~/.config/Mortivane`
  - Mac: `~/Library/Application Support/Mortivane`

## Publicar na Steam

1. **Conta:** crie a conta em <https://partner.steamgames.com>, preencha os dados fiscais e bancários
   e pague a taxa Steam Direct (US$ 100 por jogo). Você recebe um **App ID**.
2. **Build:** rode `npm run build:win:full` num PC com Windows. O conteúdo de `dist/win-unpacked/`
   é o que vai para a Steam.
3. **Depot:** no Steamworks, em *SteamPipe → Depots*, configure o depot do Windows. Em
   *Installation → General*, defina a opção de inicialização com o executável `Mortivane.exe`.
4. **Upload:** use o **SteamPipe GUI** (Windows) ou o `steamcmd` com o *ContentBuilder* do SDK
   do Steamworks, apontando para `dist/win-unpacked/`.
5. **Página da loja:** cápsulas (imagens de capa nos tamanhos pedidos), pelo menos 5 screenshots,
   descrição, trailer (recomendado) e o questionário de conteúdo. Se alguma arte foi gerada por IA,
   declare no questionário.
6. **Prazos:** a página precisa ficar pública como "Em breve" por no mínimo 2 semanas, e o
   lançamento só pode acontecer 30 dias depois do pagamento da taxa. A Valve revisa a página e o
   build antes (alguns dias).

### Integração com a Steam (próximo passo, opcional)

Conquistas, overlay e saves na nuvem usam o SDK do Steamworks. Para Electron, a biblioteca mais
usada é o [`steamworks.js`](https://github.com/ceifa/steamworks.js). Ela precisa do App ID, então
fica para quando a conta existir. O **Steam Cloud** pode sincronizar a pasta de dados listada acima
sem nenhum código (configuração *Auto-Cloud* no Steamworks).
