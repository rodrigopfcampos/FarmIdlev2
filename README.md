# Village Idle Farm

- `docs/GDD.md`: documento do jogo v2 (fonte da verdade). 🆕 marca o que mudou.
- `config/`: números do jogo (`levels.json`, `lots.json`, `mapConfig.json`, `crops.json`, `animals.json`). Nada de número fixo no código.
- `assets/map/farm_base_map.png`: fundo do mapa (1672×940).
- `tools/balance/`: modelo de terreno em TypeScript, base do simulador da fase 0.

Comandos (Node 22 + tsx):

- `npm run balance:lots`: recalcula `config/lots.json`
- `npm run balance:check`: confere mapa, lotes, cultivos, animais e documento (tem de terminar em "tudo verde")
- `python3 tools/balance/section6.py`: gera o texto da seção 6 a partir da config
