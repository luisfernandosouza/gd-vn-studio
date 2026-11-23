# Caminho rápido para o .pck de um plugin (spike M4-02): roda no Godot embutido sem abrir o editor.
#
#   godot --headless --path <cópia do plugin> --script <este arquivo> -- --ns fishing --out <x.pck>
#
# Empacota com PCKPacker o que o runtime precisa ler, sem compilar nada:
# - scripts, cenas e recursos em texto (.gd, .tscn, .tres, .json…), que o Godot carrega como estão;
# - assets já importados: o `.import` e os arquivos de `.godot/imported/` que ele aponta (o import
#   em si só roda, pelo editor, quando um asset do plugin muda);
# - um `global_script_class_cache.cfg` com SÓ as classes do plugin, lidas das linhas
#   `class_name`/`extends`. O export do editor põe ali também as classes do SDK, com os caminhos da
#   cópia de trabalho, e o runtime as registraria por cima das suas ao montar o pacote.
extends SceneTree

const TEXT_EXT := ["gd", "tscn", "tres", "json", "gdshader", "txt", "csv", "cfg"]
const CLASS_CACHE := "res://.godot/global_script_class_cache.cfg"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ns := args[args.find("--ns") + 1]
	var out := args[args.find("--out") + 1]
	var t0 := Time.get_ticks_usec()
	var files := {}        # caminho no pacote → arquivo de origem
	var classes := []
	_walk("res://vn_plugins/" + ns, files, classes)

	var cache_tmp := OS.get_cache_dir().path_join("vnpreview-class-cache-%d.cfg" % OS.get_process_id())
	var cfg := ConfigFile.new()
	cfg.set_value("", "list", classes)
	cfg.save(cache_tmp)
	files[CLASS_CACHE] = cache_tmp

	var packer := PCKPacker.new()
	var err := packer.pck_start(out)
	if err == OK:
		for target in files:
			err = packer.add_file(target, ProjectSettings.globalize_path(files[target]))
			if err != OK:
				break
	if err == OK:
		err = packer.flush()
	DirAccess.remove_absolute(cache_tmp)
	print(JSON.stringify({"ok": err == OK, "error": error_string(err), "files": files.size(),
		"classes": classes.map(func(c): return str(c["class"])), "pack_ms": (Time.get_ticks_usec() - t0) / 1000.0}))
	quit(0 if err == OK else 1)


func _walk(dir: String, files: Dictionary, classes: Array) -> void:
	for name in DirAccess.get_files_at(dir):
		var path := dir.path_join(name)
		var ext := name.get_extension()
		if ext == "import":
			files[path] = path
			var imp := ConfigFile.new()
			imp.load(path)
			for key in ["path", "path.s3tc", "path.etc2"]:
				var dest = imp.get_value("remap", key, "")
				if dest != "" and FileAccess.file_exists(dest):
					files[dest] = dest
		elif ext in TEXT_EXT:
			files[path] = path
			if ext == "gd":
				var c := _class_entry(path)
				if not c.is_empty():
					classes.append(c)
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), files, classes)


func _class_entry(path: String) -> Dictionary:
	var src := FileAccess.get_file_as_string(path)
	var name := _match(src, "(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	if name == "":
		return {}
	var base := _match(src, "(?m)^extends\\s+([A-Za-z_][A-Za-z0-9_.]*)")
	return {
		"base": StringName(base if base != "" else "RefCounted"),
		"class": StringName(name),
		"icon": "",
		"is_abstract": _match(src, "(?m)^(@abstract)\\b") != "",
		"is_tool": _match(src, "(?m)^(@tool)\\b") != "",
		"language": &"GDScript",
		"path": path,
	}


func _match(text: String, pattern: String) -> String:
	var re := RegEx.create_from_string(pattern)
	var m := re.search(text)
	return m.get_string(1) if m != null else ""
