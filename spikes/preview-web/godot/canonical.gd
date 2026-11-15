# JSON canônico (JCS, RFC 8785) e SRI em GDScript, o bastante para o spike medir
# o custo de recalcular o content_hash no runtime (RT §3.0, passo 2).
# Limite conhecido: números não inteiros usam a representação curta do Godot,
# que coincide com a do JCS nos valores do demo, mas não em todos (expoentes).
class_name Canonical
extends RefCounted


static func jcs(v) -> String:
	var parts := PackedStringArray()
	_write(v, parts)
	return "".join(parts)


static func _write(v, out: PackedStringArray) -> void:
	match typeof(v):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			out.append("true" if v else "false")
		TYPE_INT:
			out.append(str(v))
		TYPE_FLOAT:
			if v == floor(v) and absf(v) < 1e21:
				out.append(str(int(v)))
			else:
				out.append(str(v))
		TYPE_STRING, TYPE_STRING_NAME:
			out.append(JSON.stringify(str(v)))
		TYPE_ARRAY:
			out.append("[")
			var first := true
			for x in v:
				if not first:
					out.append(",")
				first = false
				_write(x, out)
			out.append("]")
		TYPE_DICTIONARY:
			var keys: Array = v.keys()
			keys.sort()
			out.append("{")
			var first := true
			for k in keys:
				if not first:
					out.append(",")
				first = false
				out.append(JSON.stringify(str(k)))
				out.append(":")
				_write(v[k], out)
			out.append("}")


static func sri(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return "sha256-" + Marshalls.raw_to_base64(ctx.finish())
