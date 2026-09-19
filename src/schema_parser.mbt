///|
fn json_required_string(
  object : Map[String, Json],
  property : String,
  path : AvroPath,
) -> Result[String, SchemaError] {
  match object.get(property) {
    None => Err(MissingProperty(path, property))
    Some(String(value)) => Ok(value)
    Some(_) => Err(InvalidProperty(path, property, "expected string"))
  }
}

///|
fn json_optional_string(
  object : Map[String, Json],
  property : String,
  path : AvroPath,
) -> Result[String?, SchemaError] {
  match object.get(property) {
    None => Ok(None)
    Some(String(value)) => Ok(Some(value))
    Some(_) => Err(InvalidProperty(path, property, "expected string"))
  }
}

///|
fn json_optional_strings(
  object : Map[String, Json],
  property : String,
  path : AvroPath,
) -> Result[Array[String], SchemaError] {
  match object.get(property) {
    None => Ok([])
    Some(Array(values)) => {
      let result : Array[String] = []
      for index, value in values {
        match value {
          String(text) => result.push(text)
          _ =>
            return Err(
              InvalidProperty(
                path.field(property).index(index),
                property,
                "expected string alias",
              ),
            )
        }
      }
      Ok(result)
    }
    Some(_) => Err(InvalidProperty(path, property, "expected string array"))
  }
}

///|
fn normalize_aliases(aliases : Array[String], ns : String) -> Array[String] {
  aliases.map(alias_name => fullname(alias_name, ns))
}

///|
fn named_metadata(
  object : Map[String, Json],
  inherited_ns : String,
  path : AvroPath,
) -> Result[NamedType, SchemaError] {
  let declared_name = match json_required_string(object, "name", path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !valid_fullname(declared_name) {
    return Err(InvalidName(path.field("name"), declared_name))
  }
  let explicit_ns = match json_optional_string(object, "namespace", path) {
    Ok(Some(value)) => {
      if !value.is_empty() && !valid_fullname(value) {
        return Err(InvalidName(path.field("namespace"), value))
      }
      value
    }
    Ok(None) => inherited_ns
    Err(error) => return Err(error)
  }
  let actual_ns = if declared_name.contains(".") {
    namespace_of(declared_name)
  } else {
    explicit_ns
  }
  let actual_name = shortname(declared_name)
  let aliases = match json_optional_strings(object, "aliases", path) {
    Ok(value) => normalize_aliases(value, actual_ns)
    Err(error) => return Err(error)
  }
  let doc = match json_optional_string(object, "doc", path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(NamedType::new(actual_name, actual_ns, aliases, doc))
}

///|
fn schema_branch_key(schema : Schema) -> String {
  match schema {
    Primitive(kind) => kind.name()
    Record(named, _) | Enum(named, _, _) | Fixed(named, _) => named.full_name
    NamedRef(name) => name
    ArraySchema(_) => "array"
    MapSchema(_) => "map"
    Union(_) => "union"
  }
}

///|
fn parse_union(
  values : Array[Json],
  ns : String,
  path : AvroPath,
  definitions : Map[String, Schema],
) -> Result[Schema, SchemaError] {
  if values.is_empty() {
    return Err(InvalidSchema(path, "union must contain at least one branch"))
  }
  let branches : Array[Schema] = []
  let seen : Map[String, Bool] = Map([])
  for index, value in values {
    let branch_path = path.index(index)
    let branch = match parse_schema_json(value, ns, branch_path, definitions) {
      Ok(schema) => schema
      Err(error) => return Err(error)
    }
    if branch is Union(_) {
      return Err(NestedUnion(branch_path))
    }
    let key = schema_branch_key(branch)
    if seen.contains(key) {
      return Err(DuplicateUnionBranch(branch_path, key))
    }
    seen.set(key, true)
    branches.push(branch)
  }
  Ok(Union(branches))
}

///|
fn parse_default(
  value : Json,
  schema : Schema,
  path : AvroPath,
  definitions : Map[String, Schema],
) -> Result[Value, SchemaError] {
  match schema {
    Primitive(Null) =>
      match value {
        Null => Ok(NullValue)
        _ => Err(InvalidDefault(path, "expected null"))
      }
    Primitive(Boolean) =>
      match value {
        True => Ok(BooleanValue(true))
        False => Ok(BooleanValue(false))
        _ => Err(InvalidDefault(path, "expected boolean"))
      }
    Primitive(Int) =>
      match value {
        Number(number, ..) => {
          let integer = number.to_int()
          if integer.to_double() == number {
            Ok(IntValue(integer))
          } else {
            Err(InvalidDefault(path, "expected integral int"))
          }
        }
        _ => Err(InvalidDefault(path, "expected int"))
      }
    Primitive(Long) =>
      match value {
        Number(number, ..) => {
          let integer = number.to_int64()
          if integer.to_double() == number {
            Ok(LongValue(integer))
          } else {
            Err(InvalidDefault(path, "expected integral long"))
          }
        }
        _ => Err(InvalidDefault(path, "expected long"))
      }
    Primitive(Float) =>
      match value {
        Number(number, ..) => Ok(FloatValue(Float::from_double(number)))
        _ => Err(InvalidDefault(path, "expected float"))
      }
    Primitive(Double) =>
      match value {
        Number(number, ..) => Ok(DoubleValue(number))
        _ => Err(InvalidDefault(path, "expected double"))
      }
    Primitive(String) =>
      match value {
        String(text) => Ok(StringValue(text))
        _ => Err(InvalidDefault(path, "expected string"))
      }
    Primitive(Bytes) =>
      match value {
        String(text) => {
          let bytes : Array[Byte] = []
          for character in text {
            let code = character.to_int()
            if code < 0 || code > 255 {
              return Err(
                InvalidDefault(
                  path, "bytes default must contain code points 0..255",
                ),
              )
            }
            bytes.push(code.to_byte())
          }
          Ok(BytesValue(Bytes::from_array(bytes)))
        }
        _ => Err(InvalidDefault(path, "expected bytes string"))
      }
    ArraySchema(items) =>
      match value {
        Array(values) => {
          let result : Array[Value] = []
          for index, entry in values {
            match parse_default(entry, items, path.index(index), definitions) {
              Ok(parsed) => result.push(parsed)
              Err(error) => return Err(error)
            }
          }
          Ok(ArrayValue(result))
        }
        _ => Err(InvalidDefault(path, "expected array"))
      }
    MapSchema(values_schema) =>
      match value {
        Object(entries) => {
          let result : Array[(String, Value)] = []
          for (key, entry) in entries.iter() {
            match
              parse_default(entry, values_schema, path.field(key), definitions) {
              Ok(parsed) => result.push((key, parsed))
              Err(error) => return Err(error)
            }
          }
          Ok(MapValue(result))
        }
        _ => Err(InvalidDefault(path, "expected object"))
      }
    Record(_, fields) =>
      match value {
        Object(entries) => {
          let result : Array[(String, Value)] = []
          for field in fields {
            match entries.get(field.name) {
              Some(entry) =>
                match
                  parse_default(
                    entry,
                    field.schema,
                    path.field(field.name),
                    definitions,
                  ) {
                  Ok(parsed) => result.push((field.name, parsed))
                  Err(error) => return Err(error)
                }
              None =>
                match field.default {
                  Some(default) => result.push((field.name, default))
                  None =>
                    return Err(
                      InvalidDefault(
                        path.field(field.name),
                        "missing record field",
                      ),
                    )
                }
            }
          }
          Ok(RecordValue(result))
        }
        _ => Err(InvalidDefault(path, "expected record object"))
      }
    Enum(_, symbols, _) =>
      match value {
        String(symbol) =>
          if symbols.contains(symbol) {
            Ok(EnumValue(symbol))
          } else {
            Err(InvalidDefault(path, "unknown enum symbol " + symbol))
          }
        _ => Err(InvalidDefault(path, "expected enum symbol"))
      }
    Fixed(_, size) =>
      match value {
        String(text) => {
          let bytes : Array[Byte] = []
          for character in text {
            let code = character.to_int()
            if code < 0 || code > 255 {
              return Err(
                InvalidDefault(path, "fixed default contains invalid byte"),
              )
            }
            bytes.push(code.to_byte())
          }
          if bytes.length() != size {
            Err(InvalidDefault(path, "fixed default has wrong size"))
          } else {
            Ok(FixedValue(Bytes::from_array(bytes)))
          }
        }
        _ => Err(InvalidDefault(path, "expected fixed string"))
      }
    Union(branches) =>
      if branches.is_empty() {
        Err(InvalidDefault(path, "empty union"))
      } else {
        match parse_default(value, branches[0], path, definitions) {
          Ok(parsed) => Ok(UnionValue(0, parsed))
          Err(error) => Err(error)
        }
      }
    NamedRef(name) =>
      match definitions.get(name) {
        Some(target) => parse_default(value, target, path, definitions)
        None => Err(UnknownReference(path, name))
      }
  }
}

///|
fn parse_record(
  object : Map[String, Json],
  inherited_ns : String,
  path : AvroPath,
  definitions : Map[String, Schema],
) -> Result[Schema, SchemaError] {
  let named = match named_metadata(object, inherited_ns, path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if definitions.contains(named.full_name) {
    return Err(DuplicateName(path.field("name"), named.full_name))
  }
  definitions.set(named.full_name, NamedRef(named.full_name))
  let fields_json = match object.get("fields") {
    Some(Array(values)) => values
    None => return Err(MissingProperty(path, "fields"))
    Some(_) => return Err(InvalidProperty(path, "fields", "expected array"))
  }
  let fields : Array[Field] = []
  let seen : Map[String, Bool] = Map([])
  for index, value in fields_json {
    let field_path = path.field("fields").index(index)
    guard value is Object(field_object) else {
      return Err(InvalidSchema(field_path, "record field must be an object"))
    }
    let name = match json_required_string(field_object, "name", field_path) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if !valid_name(name) {
      return Err(InvalidName(field_path.field("name"), name))
    }
    if seen.contains(name) {
      return Err(DuplicateField(field_path, name))
    }
    seen.set(name, true)
    let field_schema_json = match field_object.get("type") {
      Some(value) => value
      None => return Err(MissingProperty(field_path, "type"))
    }
    let field_schema = match
      parse_schema_json(
        field_schema_json,
        named.namespace_name,
        field_path.field("type"),
        definitions,
      ) {
      Ok(schema) => schema
      Err(error) => return Err(error)
    }
    let aliases = match
      json_optional_strings(field_object, "aliases", field_path) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let doc = match json_optional_string(field_object, "doc", field_path) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let order = match json_optional_string(field_object, "order", field_path) {
      Ok(Some(value)) => {
        if value != "ascending" && value != "descending" && value != "ignore" {
          return Err(
            InvalidProperty(field_path, "order", "unknown field order"),
          )
        }
        value
      }
      Ok(None) => "ascending"
      Err(error) => return Err(error)
    }
    let default = match field_object.get("default") {
      None => None
      Some(default_json) =>
        match
          parse_default(
            default_json,
            field_schema,
            field_path.field("default"),
            definitions,
          ) {
          Ok(value) => Some(value)
          Err(error) => return Err(error)
        }
    }
    fields.push(
      Field::new(name, field_schema, index, aliases~, doc~, default~, order~),
    )
  }
  let schema = Record(named, fields)
  definitions.set(named.full_name, schema)
  Ok(schema)
}

///|
fn parse_enum(
  object : Map[String, Json],
  inherited_ns : String,
  path : AvroPath,
  definitions : Map[String, Schema],
) -> Result[Schema, SchemaError] {
  let named = match named_metadata(object, inherited_ns, path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if definitions.contains(named.full_name) {
    return Err(DuplicateName(path.field("name"), named.full_name))
  }
  let symbol_values = match object.get("symbols") {
    Some(Array(values)) => values
    None => return Err(MissingProperty(path, "symbols"))
    Some(_) => return Err(InvalidProperty(path, "symbols", "expected array"))
  }
  if symbol_values.is_empty() {
    return Err(InvalidProperty(path, "symbols", "must not be empty"))
  }
  let symbols : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for index, value in symbol_values {
    guard value is String(symbol) else {
      return Err(
        InvalidProperty(
          path.field("symbols").index(index),
          "symbols",
          "expected string",
        ),
      )
    }
    if !valid_name(symbol) {
      return Err(InvalidName(path.field("symbols").index(index), symbol))
    }
    if seen.contains(symbol) {
      return Err(DuplicateSymbol(path.field("symbols").index(index), symbol))
    }
    seen.set(symbol, true)
    symbols.push(symbol)
  }
  let default = match json_optional_string(object, "default", path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match default {
    Some(symbol) =>
      if !symbols.contains(symbol) {
        return Err(InvalidDefault(path.field("default"), "unknown enum symbol"))
      }
    None => ()
  }
  let schema = Enum(named, symbols, default)
  definitions.set(named.full_name, schema)
  Ok(schema)
}

///|
fn parse_fixed(
  object : Map[String, Json],
  inherited_ns : String,
  path : AvroPath,
  definitions : Map[String, Schema],
) -> Result[Schema, SchemaError] {
  let named = match named_metadata(object, inherited_ns, path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if definitions.contains(named.full_name) {
    return Err(DuplicateName(path.field("name"), named.full_name))
  }
  let size = match object.get("size") {
    Some(Number(number, ..)) => {
      let integer = number.to_int()
      if integer <= 0 || integer.to_double() != number {
        return Err(InvalidProperty(path, "size", "expected positive integer"))
      }
      integer
    }
    None => return Err(MissingProperty(path, "size"))
    Some(_) => return Err(InvalidProperty(path, "size", "expected number"))
  }
  let schema = Fixed(named, size)
  definitions.set(named.full_name, schema)
  Ok(schema)
}

///|
fn parse_schema_object(
  object : Map[String, Json],
  ns : String,
  path : AvroPath,
  definitions : Map[String, Schema],
) -> Result[Schema, SchemaError] {
  let type_value = match object.get("type") {
    Some(value) => value
    None => return Err(MissingProperty(path, "type"))
  }
  match type_value {
    String("record") => parse_record(object, ns, path, definitions)
    String("enum") => parse_enum(object, ns, path, definitions)
    String("fixed") => parse_fixed(object, ns, path, definitions)
    String("array") => {
      let items = match object.get("items") {
        Some(value) => value
        None => return Err(MissingProperty(path, "items"))
      }
      match parse_schema_json(items, ns, path.field("items"), definitions) {
        Ok(schema) => Ok(ArraySchema(schema))
        Err(error) => Err(error)
      }
    }
    String("map") => {
      let values = match object.get("values") {
        Some(value) => value
        None => return Err(MissingProperty(path, "values"))
      }
      match parse_schema_json(values, ns, path.field("values"), definitions) {
        Ok(schema) => Ok(MapSchema(schema))
        Err(error) => Err(error)
      }
    }
    other => parse_schema_json(other, ns, path.field("type"), definitions)
  }
}

///|
fn parse_schema_json(
  value : Json,
  ns : String,
  path : AvroPath,
  definitions : Map[String, Schema],
) -> Result[Schema, SchemaError] {
  match value {
    String(name) =>
      match primitive_from_name(name) {
        Some(kind) => Ok(Primitive(kind))
        None => {
          let resolved = fullname(name, ns)
          if definitions.contains(resolved) {
            Ok(NamedRef(resolved))
          } else if definitions.contains(name) {
            Ok(NamedRef(name))
          } else {
            Err(UnknownReference(path, resolved))
          }
        }
      }
    Array(values) => parse_union(values, ns, path, definitions)
    Object(object) => parse_schema_object(object, ns, path, definitions)
    _ => Err(InvalidSchema(path, "schema must be a string, object, or array"))
  }
}

///|
/// Parse and validate an Avro JSON schema document.
pub fn parse_schema(text : StringView) -> Result[SchemaDocument, SchemaError] {
  let json = @json.parse(text) catch {
    error => return Err(InvalidJson(error.to_string()))
  }
  let definitions : Map[String, Schema] = Map([])
  match parse_schema_json(json, "", AvroPath::root(), definitions) {
    Ok(root) => Ok(SchemaDocument::new(root, definitions))
    Err(error) => Err(error)
  }
}
