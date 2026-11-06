# Militasdraw

Primeira versão de um editor nativo de diagramas e ideias para iPhone e iPad, escrito em Swift, SwiftUI e UIKit. Não usa WebView, Excalidraw nem dependências externas. Requer iOS/iPadOS 17 ou posterior.

## Abrir e executar

1. Abra `Militasdrawer.xcodeproj` no Xcode (validado com Xcode 26.2).
2. Selecione o scheme `Militasdrawer` e um simulador de iPhone ou iPad.
3. Execute com ⌘R.
4. Para um aparelho físico, configure seu Team em Signing & Capabilities. O identificador inicial é `com.victormilitao.Militasdrawer`; ajuste caso necessário.

## Ferramentas desta versão

- Retângulo, elipse e losango: escolha a ferramenta e arraste no quadro.
- Seta: arraste entre formas para conectar suas bordas. Ao mover uma forma, a conexão acompanha. Também permite setas livres. Para corrigir uma conexão, selecione a seta e arraste o círculo de uma das pontas até a forma desejada.
- Desenho livre: arraste com dedo ou Apple Pencil; espessura fixa nesta versão.
- Texto: escolha Texto e toque no quadro; para editar, selecione o texto e use o botão de edição.
- Seleção: toque para selecionar; arraste o objeto para mover. A lixeira apaga o selecionado.
- Duplicação: selecione um objeto e toque no botão Duplicar ao lado de desfazer/refazer no cabeçalho. A cópia aparece ligeiramente deslocada e fica selecionada. Dois toques no objeto continuam editando o texto.
- Cores: a paleta define a cor dos próximos elementos e altera a seleção atual.
- Navegação: use dois dedos ou a ferramenta Navegar; pinça amplia de 20% a 400%. O botão de porcentagem enquadra o desenho.
- Desfazer/refazer: botões no topo, com atalhos ⌘Z e ⇧⌘Z em teclado físico. Até 100 operações por sessão.
- Barra de ferramentas rolável no iPhone e centralizada no iPad. Retrato e paisagem suportados.

Mover uma seta diretamente a desconecta das formas. Excluir uma forma preserva suas setas como traços com a extremidade correspondente livre.

## Armazenamento

Os desenhos são salvos automaticamente em `Documents/desenhos.militasdrawer.json`, 350 ms após uma edição e quando o app deixa de estar ativo. A escrita é atômica. O arquivo contém os documentos, nomes, datas de atualização e o identificador do último desenho aberto. O histórico e o enquadramento são temporários.

O app abre diretamente no último desenho selecionado; na primeira abertura, cria um desenho em branco. O ícone superior esquerdo abre um painel lateral com todos os desenhos, ordenados pela última alteração, e o botão “Novo desenho”. Os nomes iniciais são automáticos (“Desenho 1”, “Desenho 2”…); toque no título do desenho para renomear. Nomes vazios são rejeitados e espaços nas extremidades são removidos. Abrir um desenho não altera sua data de atualização. A troca salva o desenho atual primeiro e é interrompida se a gravação falhar.

O quadro do formato anterior (`quadro.militasdrawer.json`) é migrado na primeira abertura, preservando o arquivo original. Se o arquivo existente não puder ser lido, o app preserva o original, informa o erro e desativa a gravação nessa sessão. Não existe sincronização em nuvem; remover o app pode remover os desenhos. Exclusão, importação e exportação ainda não estão implementadas.

## Estrutura

- `Militasdrawer/Core/Drawing.swift`: documento, geometria das conexões e histórico.
- `Militasdrawer/App/EditorStore.swift`: estado de edição, texto e persistência.
- `Militasdrawer/App/DrawingCanvas.swift`: renderização Core Graphics, seleção e gestos UIKit.
- `Militasdrawer/App/MilitasdrawerApp.swift`: interface SwiftUI adaptada ao tamanho disponível.
- `Tests/CoreTests`: conexão, exclusão, histórico e serialização.
- `Tests/UITests`: criação de formas, seta e texto, desfazer/refazer e reabertura do documento.

## Verificação

```sh
swift test
xcodebuild -project Militasdrawer.xcodeproj -scheme Militasdrawer \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Os testes de interface podem ser executados com ⌘U no Xcode, selecionando um simulador. Eles usam um quadro vazio no início e sobrescrevem o documento do app nesse simulador. Não execute o teste em um ambiente com desenhos que deseja preservar.

## Validação realizada

- Compilação Debug para iOS Simulator com Xcode 26.2.
- Quatro testes do núcleo aprovados.
- Fluxo de formas, seta, texto, desfazer/refazer e persistência aprovado no iPhone 17 Pro e iPad Pro de 11 polegadas, ambos com iOS 26.2.
- Testes de desenho livre, movimentação, exclusão e zoom aprovados nos dois simuladores.
- Capturas da interface em `docs/iphone-preview.png` e `docs/ipad-preview.png`.

## Limites e próximos passos

Esta é uma base funcional para desenvolvimento, não uma versão pronta para a App Store. Ainda faltam redimensionamento/rotação, seleção múltipla, agrupamento, imagens, roteamento de conectores, exportação e preparação da loja. Acessibilidade do conteúdo individual do quadro e suporte avançado ao Apple Pencil (pressão, rejeição de palma, hover) precisam evoluir. Gestos e latência do Pencil precisam de validação em aparelho físico.

O formato `.excalidraw` ainda não é compatível com o formato próprio do app.

## Ícone e preparação para TestFlight

O catálogo `Militasdrawer/Assets.xcassets` contém o ícone de camadas azul-escuro
(`#1E3A8A`) sobre fundo branco. O PNG mestre tem 1024 × 1024 pixels, sem canal
alfa; o Xcode gera os tamanhos necessários para iPhone e iPad. O desenho é
geometria própria inspirada no símbolo do cabeçalho. Para regenerar no macOS:

```sh
swift scripts/generate-app-icon.swift
```

O target usa `AppIcon` em Debug e Release. A versão inicial de testes continua
`0.1.0`, build `1`, com Bundle ID `com.victormilitao.Militasdrawer`.

O próximo passo é criar o registro no App Store Connect: Apps → + → Novo App,
plataforma iOS, nome Militasdraw, idioma principal Inglês (EUA), o Bundle
ID acima e SKU `militasdrawer-ios`. Criar o registro não publica o app na loja.
Depois, gerar um Archive no Xcode e enviar ao App Store Connect para TestFlight.
O upload, a configuração dos testadores e a análise beta são etapas separadas.

### Idiomas

O idioma-base do app é inglês americano, com tradução em português brasileiro.
O catálogo `Militasdrawer/Localizable.xcstrings` centraliza os textos da interface,
mensagens e acessibilidade. O iOS escolhe a tradução conforme os idiomas preferidos
do dispositivo ou o idioma definido para o app; o país do download não determina
o idioma. Idiomas sem tradução usam inglês como fallback.

## Validação da lista de desenhos

A compilação iOS e os fluxos de criação, troca e restauração foram validados no simulador. Os testes do núcleo cobrem a persistência de múltiplos desenhos.
