@abstract
class_name VNVariableManager
extends VNModule
## Variable Manager (RT §1): armazena valores, defaults, escopos e derivadas.
##
## É a autoridade sobre os **valores** das variáveis, mas não valida escritas:
## só o State Manager chama [method store] (RT §1, regra de dependência). Os
## demais módulos leem por [method read] (Condition Evaluator, Scheduler, UI)
## ou pelo State Manager (plugins, com permissão).
##
## IDs são sempre qualificados: [code]global.x[/code],
## [code]character.<personagem>.x[/code], [code]chapter.x[/code],
## [code]scene.x[/code], [code]plugin.<ns>.x[/code], [code]sys.…[/code] (DM §4.1).
## Iteração sobre mapas segue a ordem lexicográfica das chaves (RT §12.1).
##
## Specs: DM §4.1–§4.6; RT §3.1–§3.3, §5.1, §5.4, §6.5, §8.2–§8.4.
## Tarefa: M1-05.


func module_id() -> StringName:
	return &"variables"


# --- Definições -------------------------------------------------------------

## A variável existe (inclusive [code]sys.*[/code] e derivadas). Aliases de
## [code]renamed_from[/code] não contam: use [method resolve_alias] antes.
@abstract func has(id: String) -> bool

## Definição da variável (DM §4.2): [code]type[/code], [code]default[/code]
## efetivo, [code]persistence[/code], [code]constraints[/code],
## [code]derived[/code], [code]access[/code]. Vazio se não existe.
@abstract func get_definition(id: String) -> Dictionary

## IDs de todas as variáveis definidas, em ordem lexicográfica.
@abstract func ids() -> PackedStringArray

## Traduz uma chave antiga pelos aliases de [code]renamed_from[/code] (DM §12);
## devolve [param id] se não houver alias.
@abstract func resolve_alias(id: String) -> String

## Somente leitura: [code]sys.*[/code] ou derivada (DM §4.3, §4.5).
@abstract func is_read_only(id: String) -> bool

## O escopo da variável está ativo: [code]chapter.*[/code] só com capítulo
## ativo e [code]scene.*[/code] só com cena ativa (RT §6.2, verificação 5).
@abstract func is_scope_active(id: String) -> bool


# --- Valores ----------------------------------------------------------------

## Valor atual. Derivadas são recalculadas na leitura (pelo Condition
## Evaluator). Devolve [param fallback] se a variável não existe ou o escopo
## está inativo; quem precisa do erro confere [method has] e
## [method is_scope_active] antes.
@abstract func read(id: String, fallback: Variant = null) -> Variant

## Grava o valor já validado. **Só o State Manager chama** (RT §1).
## Também é o caminho do runtime para [code]sys.*[/code], pelo
## [method VNStateManager.set_system_value].
@abstract func store(id: String, value: Variant) -> void

## O valor atual é igual ao padrão efetivo ([code]is_default[/code], DM §5.1).
@abstract func is_default(id: String) -> bool


# --- Ciclo de vida por escopo (RT §6.5) -------------------------------------

## Novo jogo (RT §3.1 passo 1): zera tudo e aplica defaults, inclusive os
## [code]initial_values[/code] dos personagens. Não mexe em [code]profile[/code].
@abstract func reset_game() -> void

## Aplica as variáveis [code]profile[/code] lidas de [code]profile.json[/code]
## (RT §3.1 passo 2, §8.3 passo 3), traduzindo aliases.
@abstract func apply_profile(values: Dictionary) -> void

## Entrada em capítulo (RT §3.2 passo 1): instancia [code]chapter.*[/code] com os defaults.
@abstract func enter_chapter(chapter_id: String) -> void

## Saída de capítulo (RT §3.3 passo 3): descarta [code]chapter.*[/code].
@abstract func exit_chapter() -> void

## Início de cena (RT §5.1 passo 1): instancia [code]scene.*[/code] com os defaults.
@abstract func enter_scene(scene_id: String) -> void

## Fim de cena (RT §5.4 passo 3): descarta [code]scene.*[/code].
@abstract func exit_scene() -> void


# --- Save e perfil (RT §8.2–§8.4) -------------------------------------------

## Todas as variáveis com [code]persistence: save[/code] do escopo ativo,
## inclusive as que estão no padrão (RT §8.2). Derivadas e [code]session[/code] nunca.
@abstract func save_values() -> Dictionary

## Variáveis com [code]persistence: profile[/code], para [code]profile.json[/code].
@abstract func profile_values() -> Dictionary

## Aplica as variáveis de um save sobre os defaults e o perfil (RT §8.3
## passo 3), com as regras do RT §8.4 para save de versão antiga (alias,
## descarte, conversão de tipo, clamp). Devolve os avisos para o log.
@abstract func restore_save_values(values: Dictionary) -> PackedStringArray
