## WGSL Raymarcher Template
Template básico de um Ray Marcher em WGSL (WEBGPU). Tudo o que precisa para fazer o projeto esta aqui.

### ⚠️ Atenção

O projeto provavelmente não vai rodar em linux, já que a GPU não fica acessível pro WGSL.

### Instruções
Faça um fork do projeto, clone e abra no Visual Studio (ou outro software, mas recomendo esse)

Baixe (se no visual studio) -> **Name: Live Server - VS Marketplace Link:** [link para o marketplace](https://marketplace.visualstudio.com/items?itemName=ritwickdey.LiveServer)

Aperte ```CTRL + Shift + P``` e selecione ```Live Server```. Um browser com o projeto rodando deve abrir.

### Funções para implementar/complementar (olhe a sessão de notas para mais detalhes)
- ```sdf_round_box```
- ```sdf_sphere```
- ```sdf_torus```
- ```get_light```
- ```get_soft_shadow```
- ```get_normal```
- ```march```
- ```repeat```
- ```scene```
- ```transform_p```
- ```op_smooth_union```
- ```op_smooth_subtraction```
- ```op_smooth_intersection```
- ```preprocess```
- ```animate```
- ```render```

### Controles
Você pode controlar qualquer parametro com o GUI ao lado.

**Dica**: Você pode clicar no parametro e fazer um scroll para mudar ele de maneira smooth.
Para mover a camera, use WASDQEXZ. Para rodar, use as setas.

### Dicas
Procure pelos comentários no código para te ajudar. Dê uma olhada nos outros arquivos ```.wgsl``` além do ```raymarcher.wgsl```, várias funções que você vai precisar já estão disponíveis lá, prontas para usar.

Depois que criar uma cena nova, basta apertar ```PrintScene``` (copia para o clipboard automatico) e colar no arquivo ```scenes.js```.
O reconhecimento é automático. 

### Nota
Você pode calcular sua nota com base nas cenas que você fez. Você sempre pode comparar aqui (https://gubebra.itch.io/raymarching-webgpu)
- C: ```"Sphere", "SkyAndHS", "Multiple"```
- C+: ```"Rotation"```
- B: ```"Animation"```, ```"Outline"```
- B+: ```"Union"```, ```"Subtraction"```, ```"Intersection"```, ```"Blobs"```
- A: ```"Mod"```, ```"SoftShadows"```
- A+: Adicione uma nova primitiva geometrica ou ```"Fractal" ou "Weird"```. Você deve fazer sua própria função de fractal ou uma cena com uma geometria maluca.

+ Meio conceito: veja as dicas e creie uma cena nova interessante (não somente uma esfera e pronto)

### Entrega:
Via Blackboard, entregue o link do git.

---

## Projeto 3 — o que foi implementado

Técnica escolhida: **Ray Marching** (sphere tracing com SDFs), em WGSL/WebGPU.

**Cenas que renderizam:** todas as do gabarito — `Sphere`, `SkyAndHS`, `Multiple`, `Rotation`, `Animation`, `Outline`, `Union`, `Subtraction`, `Intersection`, `Blobs`, `Mod`, `SoftShadows`, `Fractal`, `Weird` — além da cena autoral **`Temple`**, que usa a **nova primitiva (cilindro)**.

### Arquivos alterados
| Arquivo | O que mudou |
|---|---|
| `src/shaders/shapes.wgsl` | SDFs de esfera (aceita escala → elipsoide), caixa arredondada, toro e **cilindro (nova primitiva)**. Rotação via quaternion aplicada ao ponto. |
| `src/shaders/raymarcher.wgsl` | `scene`, `march`, `get_normal`, `get_soft_shadow`, `get_light`, `repeat`, operações suaves, `animate`, `preprocess`, `render`, outline e ligação do Mandelbulb / fractal apoloniano. |
| `main.js` | Suporte ao tipo `Cylinder` (lista, GUI, buffers, `PrintScene`, uniform `cylinderCount` no índice 31). |
| `src/scenes.js` | Cena nova `Temple`. |

### Resumo do pipeline
1. **`preprocess`** (1 thread por objeto): posição animada = posição + amplitude·sen(t·vel); rotação = graus→radianos + rotação animada → quaternion. Salva em `transform_animated` e `quat`.
2. **`render`** (1 thread por pixel): monta o raio da câmera → `march` → ponto atingido → `get_light` → névoa → outline → gama.
3. **`march`**: anda pelo raio a distância devolvida por `scene(p)` até ficar < ε (acertou) ou passar do *far plane* (céu).
4. **`scene`**: chão (plano y=0) + cada objeto (repetição opcional → espaço local → SDF) combinado com união/subtração/interseção suaves (ordem garantida pela CPU).
5. **`get_light`**: Lambert × sombra suave + céu × oclusão de ambiente + especular Blinn-Phong.

### Nova primitiva: cilindro
`radius = [raio, meia-altura, —, arredondamento]`. Em coordenadas (distância radial, altura) o cilindro vira um retângulo 2D, então a SDF é a mesma ideia da caixa, só que em 2D. Pode ser adicionado pela GUI em *Objects → Cylinder(s) → AddObject*.

### Parâmetros
- Rotação dos objetos na GUI em **graus**; amplitude da rotação animada em **radianos**.
- `softShadowK`: pequeno = sombra dura (`SkyAndHS`), maior = sombra suave (`SoftShadows`).
- `op.x`: 0–1 união, 1–2 subtração, ≥2 interseção; `op.y` = suavidade k; `op.z > 1` liga repetição com período `op.w`.

Referências: Inigo Quilez — [SDFs](https://iquilezles.org/articles/distfunctions/), [smooth min](https://iquilezles.org/articles/smin/), [soft shadows](https://iquilezles.org/articles/rmshadows/).
