# SatanabeCleanUI v4.1

Dylib de aparência para o Satanabe External.

## Menu flutuante
- Liquid Glass: liga/desliga o efeito.
- Intensidade do Glass.
- Cor dos cards.
- Cor do destaque/bordas.
- Vídeo de fundo: liga/desliga.
- Fonte do vídeo: Original ou Personalizado.
- Escolher/trocar vídeo: abre o seletor de arquivos do iOS e copia o vídeo escolhido para o sandbox do app.
- Restaurar visual original.

As preferências ficam em NSUserDefaults. O vídeo personalizado fica em:
Library/Application Support/SatanabeCleanUI/background.mp4

A dylib não altera Supabase, keys ou lógica dos patches.

## GitHub
Estrutura:
.github/workflows/build.yml
Source/SatanabeCleanUI.mm
Makefile

Abra Actions > Build SatanabeCleanUI v4.1 > Run workflow.
Baixe o artifact SatanabeCleanUI-v4.

## eSign
Injete SatanabeCleanUI.dylib no executável do seu próprio app, assine novamente e instale.

## v4.1 crash fix
- O primeiro boot preserva o vídeo e o visual originais.
- Liquid Glass começa desligado.
- Corrigida recursão no UIVisualEffectView que podia crescer a árvore de views até o app encerrar.
- O watchdog do flutuante não reaplica o visual a cada segundo.
