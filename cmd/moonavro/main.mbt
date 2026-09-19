///|
extern "js" fn read_text_file(path : String) -> String? =
  #| function(path) {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     return fs.readFileSync(path, 'utf8');
  #|   } catch (_) {
  #|     return undefined;
  #|   }
  #| }

///|
extern "js" fn read_binary_file(path : String) -> Bytes? =
  #| function(path) {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     return new Uint8Array(fs.readFileSync(path));
  #|   } catch (_) {
  #|     return undefined;
  #|   }
  #| }

///|
extern "js" fn write_binary_file(path : String, data : Bytes) -> Bool =
  #| function(path, data) {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     fs.writeFileSync(path, data);
  #|     return true;
  #|   } catch (_) {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn set_exit_code(code : Int) -> Unit =
  #| function(code) {
  #|   if (typeof process !== 'undefined') process.exitCode = code;
  #| }

///|
fn usage() -> Unit {
  println("MoonAvro - MoonBit-native Apache Avro toolkit")
  println("Usage:")
  println("  moonavro inspect <schema.avsc>")
  println("  moonavro canonical <schema.avsc>")
  println("  moonavro compatible <writer.avsc> <reader.avsc>")
  println("  moonavro encode <schema.avsc> <datum.json> <output.bin>")
  println("  moonavro decode <schema.avsc> <input.bin>")
  println("  moonavro decode-resolved <writer.avsc> <reader.avsc> <input.bin>")
  println("  moonavro pack <schema.avsc> <datum.json> <output.avro>")
  println("  moonavro unpack <input.avro>")
}

///|
fn find_command(args : Array[String]) -> (String, Int)? {
  for index, value in args {
    match value {
      "inspect"
      | "canonical"
      | "compatible"
      | "encode"
      | "decode"
      | "decode-resolved"
      | "pack"
      | "unpack" => return Some((value, index))
      _ => ()
    }
  }
  None
}

///|
fn load_schema(path : String) -> @avro.SchemaDocument? {
  let text = match read_text_file(path) {
    Some(value) => value
    None => {
      println("error: cannot read schema " + path)
      return None
    }
  }
  match @avro.parse_schema(text) {
    Ok(value) => Some(value)
    Err(error) => {
      println(
        "error: invalid Avro schema: " + Debug::to_repr(error).to_string(),
      )
      None
    }
  }
}

///|
fn load_datum(schema : @avro.SchemaDocument, path : String) -> @avro.Value? {
  let text = match read_text_file(path) {
    Some(value) => value
    None => {
      println("error: cannot read datum " + path)
      return None
    }
  }
  match @avro.value_from_json(schema, text) {
    Ok(value) => Some(value)
    Err(error) => {
      println(
        "error: invalid Avro JSON datum: " + Debug::to_repr(error).to_string(),
      )
      None
    }
  }
}

///|
fn run_inspect(args : Array[String], index : Int) -> Int {
  guard index + 1 < args.length() else {
    usage()
    return 2
  }
  let schema = match load_schema(args[index + 1]) {
    Some(value) => value
    None => return 2
  }
  println("root: " + schema.root.display_name())
  println("kind: " + schema.root.kind())
  println("named definitions: " + schema.definition_count().to_string())
  println("canonical: " + @avro.parsing_canonical_form(schema))
  println(
    "crc64-avro: " + @avro.fingerprint64_hex(@avro.schema_fingerprint64(schema)),
  )
  0
}

///|
fn run_canonical(args : Array[String], index : Int) -> Int {
  guard index + 1 < args.length() else {
    usage()
    return 2
  }
  match load_schema(args[index + 1]) {
    Some(schema) => {
      println(@avro.parsing_canonical_form(schema))
      0
    }
    None => 2
  }
}

///|
fn run_compatible(args : Array[String], index : Int) -> Int {
  guard index + 2 < args.length() else {
    usage()
    return 2
  }
  let writer = match load_schema(args[index + 1]) {
    Some(value) => value
    None => return 2
  }
  let reader = match load_schema(args[index + 2]) {
    Some(value) => value
    None => return 2
  }
  let report = @avro.check_compatibility(writer, reader)
  if report.compatible {
    println("COMPATIBLE")
    return 0
  }
  println("INCOMPATIBLE")
  for issue in report.issues {
    println(
      issue.path.to_string() +
      ": " +
      issue.message +
      " (" +
      issue.writer +
      " -> " +
      issue.reader +
      ")",
    )
  }
  1
}

///|
fn run_encode(args : Array[String], index : Int) -> Int {
  guard index + 3 < args.length() else {
    usage()
    return 2
  }
  let schema = match load_schema(args[index + 1]) {
    Some(value) => value
    None => return 2
  }
  let datum = match load_datum(schema, args[index + 2]) {
    Some(value) => value
    None => return 2
  }
  let encoded = match @avro.encode(schema, datum) {
    Ok(value) => value
    Err(error) => {
      println("error: encode failed: " + Debug::to_repr(error).to_string())
      return 1
    }
  }
  if !write_binary_file(args[index + 3], encoded) {
    println("error: cannot write " + args[index + 3])
    return 2
  }
  println("encoded " + encoded.length().to_string() + " bytes")
  0
}

///|
fn run_decode(args : Array[String], index : Int) -> Int {
  guard index + 2 < args.length() else {
    usage()
    return 2
  }
  let schema = match load_schema(args[index + 1]) {
    Some(value) => value
    None => return 2
  }
  let bytes = match read_binary_file(args[index + 2]) {
    Some(value) => value
    None => {
      println("error: cannot read " + args[index + 2])
      return 2
    }
  }
  let value = match @avro.decode(schema, bytes) {
    Ok(value) => value
    Err(error) => {
      println("error: decode failed: " + Debug::to_repr(error).to_string())
      return 1
    }
  }
  match @avro.value_to_json_string(schema, value, pretty=true) {
    Ok(text) => {
      println(text)
      0
    }
    Err(error) => {
      println(
        "error: JSON rendering failed: " + Debug::to_repr(error).to_string(),
      )
      1
    }
  }
}

///|
fn run_decode_resolved(args : Array[String], index : Int) -> Int {
  guard index + 3 < args.length() else {
    usage()
    return 2
  }
  let writer = match load_schema(args[index + 1]) {
    Some(value) => value
    None => return 2
  }
  let reader = match load_schema(args[index + 2]) {
    Some(value) => value
    None => return 2
  }
  let bytes = match read_binary_file(args[index + 3]) {
    Some(value) => value
    None => {
      println("error: cannot read " + args[index + 3])
      return 2
    }
  }
  let value = match @avro.decode_resolved(writer, reader, bytes) {
    Ok(value) => value
    Err(error) => {
      println(
        "error: resolved decode failed: " + Debug::to_repr(error).to_string(),
      )
      return 1
    }
  }
  match @avro.value_to_json_string(reader, value, pretty=true) {
    Ok(text) => {
      println(text)
      0
    }
    Err(error) => {
      println(
        "error: JSON rendering failed: " + Debug::to_repr(error).to_string(),
      )
      1
    }
  }
}

///|
fn run_pack(args : Array[String], index : Int) -> Int {
  guard index + 3 < args.length() else {
    usage()
    return 2
  }
  let schema = match load_schema(args[index + 1]) {
    Some(value) => value
    None => return 2
  }
  let datum = match load_datum(schema, args[index + 2]) {
    Some(value) => value
    None => return 2
  }
  let container = match @avro.write_container(schema, [datum]) {
    Ok(value) => value
    Err(error) => {
      println(
        "error: container encode failed: " + Debug::to_repr(error).to_string(),
      )
      return 1
    }
  }
  if !write_binary_file(args[index + 3], container) {
    println("error: cannot write " + args[index + 3])
    return 2
  }
  println("wrote one record in " + container.length().to_string() + " bytes")
  0
}

///|
fn run_unpack(args : Array[String], index : Int) -> Int {
  guard index + 1 < args.length() else {
    usage()
    return 2
  }
  let bytes = match read_binary_file(args[index + 1]) {
    Some(value) => value
    None => {
      println("error: cannot read " + args[index + 1])
      return 2
    }
  }
  let container = match @avro.read_container(bytes) {
    Ok(value) => value
    Err(error) => {
      println(
        "error: container decode failed: " + Debug::to_repr(error).to_string(),
      )
      return 1
    }
  }
  println("schema: " + @avro.parsing_canonical_form(container.schema))
  println("records: " + container.values.length().to_string())
  for index, value in container.values {
    match @avro.value_to_json_string(container.schema, value) {
      Ok(text) => println(index.to_string() + ": " + text)
      Err(_) => println(index.to_string() + ": <cannot render>")
    }
  }
  0
}

///|
fn main {
  let args = @env.args()
  let code = match find_command(args) {
    Some(("inspect", index)) => run_inspect(args, index)
    Some(("canonical", index)) => run_canonical(args, index)
    Some(("compatible", index)) => run_compatible(args, index)
    Some(("encode", index)) => run_encode(args, index)
    Some(("decode", index)) => run_decode(args, index)
    Some(("decode-resolved", index)) => run_decode_resolved(args, index)
    Some(("pack", index)) => run_pack(args, index)
    Some(("unpack", index)) => run_unpack(args, index)
    _ => {
      usage()
      2
    }
  }
  set_exit_code(code)
}
