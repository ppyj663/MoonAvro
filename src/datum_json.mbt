///|
/// Errors produced while converting between Avro values and Avro's JSON data
/// encoding. This is distinct from schema JSON parsing.
pub(all) suberror DatumJsonError {
  DatumInvalidJson(String)
  DatumTypeMismatch(AvroPath, String, String)
  DatumMissingField(AvroPath, String)
  DatumUnknownEnumSymbol(AvroPath, String)
  DatumInvalidUnion(AvroPath, String)
  DatumInvalidBytes(AvroPath, String)
  DatumInvalidFixed(AvroPath, Int, Int)
  DatumUnknownReference(AvroPath, String)
  DatumValueMismatch(AvroPath, String, String)
} derive(Eq, Debug)

///|
fn json_kind(value : Json) -> String {
  match value {
    Null => "null"
    True | False => "boolean"
    Number(_, ..) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn bytes_from_json_string(
  text : String,
  path : AvroPath,
) -> Result[Bytes, DatumJsonError] {
  let output : Array[Byte] = []
  for character in text {
    let code = character.to_int()
    if code < 0 || code > 255 {
      return Err(
        DatumInvalidBytes(
          path, "Avro JSON bytes use Unicode code points from 0 through 255",
        ),
      )
    }
    output.push(code.to_byte())
  }
  Ok(Bytes::from_array(output))
}

///|
fn bytes_to_json_string(bytes : Bytes) -> String {
  let output = StringBuilder()
  for byte in bytes {
    output.write_char(byte.to_int().unsafe_to_char())
  }
  output.to_string()
}

///|
fn datum_union_label(document : SchemaDocument, schema : Schema) -> String {
  match schema {
    Primitive(kind) => kind.name()
    Record(named, _) | Enum(named, _, _) | Fixed(named, _) => named.name
    NamedRef(name) =>
      match document.definition(name) {
        Some(target) => datum_union_label(document, target)
        None => name
      }
    ArraySchema(_) => "array"
    MapSchema(_) => "map"
    Union(_) => "union"
  }
}

///|
fn value_from_json_node(
  document : SchemaDocument,
  schema : Schema,
  json : Json,
  path : AvroPath,
) -> Result[Value, DatumJsonError] {
  match schema {
    NamedRef(name) =>
      match document.definition(name) {
        Some(target) => value_from_json_node(document, target, json, path)
        None => Err(DatumUnknownReference(path, name))
      }
    Primitive(Null) =>
      if json is Null {
        Ok(NullValue)
      } else {
        Err(DatumTypeMismatch(path, "null", json_kind(json)))
      }
    Primitive(Boolean) =>
      match json {
        True => Ok(BooleanValue(true))
        False => Ok(BooleanValue(false))
        _ => Err(DatumTypeMismatch(path, "boolean", json_kind(json)))
      }
    Primitive(Int) =>
      match json {
        Number(number, ..) => {
          let value = number.to_int()
          if value.to_double() != number {
            Err(
              DatumTypeMismatch(path, "32-bit integer", "non-integral number"),
            )
          } else {
            Ok(IntValue(value))
          }
        }
        _ => Err(DatumTypeMismatch(path, "int", json_kind(json)))
      }
    Primitive(Long) =>
      match json {
        Number(number, ..) => {
          let value = number.to_int64()
          if value.to_double() != number {
            Err(
              DatumTypeMismatch(path, "64-bit integer", "non-integral number"),
            )
          } else {
            Ok(LongValue(value))
          }
        }
        _ => Err(DatumTypeMismatch(path, "long", json_kind(json)))
      }
    Primitive(Float) =>
      match json {
        Number(number, ..) => Ok(FloatValue(Float::from_double(number)))
        String("NaN") => Ok(FloatValue(@float.not_a_number))
        String("Infinity") => Ok(FloatValue(@float.infinity))
        String("-Infinity") => Ok(FloatValue(@float.neg_infinity))
        _ => Err(DatumTypeMismatch(path, "float", json_kind(json)))
      }
    Primitive(Double) =>
      match json {
        Number(number, ..) => Ok(DoubleValue(number))
        String("NaN") => Ok(DoubleValue(@double.not_a_number))
        String("Infinity") => Ok(DoubleValue(@double.infinity))
        String("-Infinity") => Ok(DoubleValue(@double.neg_infinity))
        _ => Err(DatumTypeMismatch(path, "double", json_kind(json)))
      }
    Primitive(Bytes) =>
      match json {
        String(text) =>
          match bytes_from_json_string(text, path) {
            Ok(value) => Ok(BytesValue(value))
            Err(error) => Err(error)
          }
        _ => Err(DatumTypeMismatch(path, "bytes string", json_kind(json)))
      }
    Primitive(String) =>
      match json {
        String(text) => Ok(StringValue(text))
        _ => Err(DatumTypeMismatch(path, "string", json_kind(json)))
      }
    Record(_, fields) => {
      guard json is Object(object) else {
        return Err(DatumTypeMismatch(path, "record object", json_kind(json)))
      }
      let entries : Array[(String, Value)] = []
      for field in fields {
        match object.get(field.name) {
          Some(node) =>
            match
              value_from_json_node(
                document,
                field.schema,
                node,
                path.field(field.name),
              ) {
              Ok(value) => entries.push((field.name, value))
              Err(error) => return Err(error)
            }
          None =>
            match field.default {
              Some(default) => entries.push((field.name, default))
              None => return Err(DatumMissingField(path, field.name))
            }
        }
      }
      Ok(RecordValue(entries))
    }
    Enum(_, symbols, _) =>
      match json {
        String(symbol) =>
          if symbols.contains(symbol) {
            Ok(EnumValue(symbol))
          } else {
            Err(DatumUnknownEnumSymbol(path, symbol))
          }
        _ => Err(DatumTypeMismatch(path, "enum string", json_kind(json)))
      }
    ArraySchema(items) => {
      guard json is Array(nodes) else {
        return Err(DatumTypeMismatch(path, "array", json_kind(json)))
      }
      let values : Array[Value] = []
      for index, node in nodes {
        match value_from_json_node(document, items, node, path.index(index)) {
          Ok(value) => values.push(value)
          Err(error) => return Err(error)
        }
      }
      Ok(ArrayValue(values))
    }
    MapSchema(values_schema) => {
      guard json is Object(object) else {
        return Err(DatumTypeMismatch(path, "map object", json_kind(json)))
      }
      let entries : Array[(String, Value)] = []
      for (key, node) in object.iter() {
        match
          value_from_json_node(document, values_schema, node, path.field(key)) {
          Ok(value) => entries.push((key, value))
          Err(error) => return Err(error)
        }
      }
      Ok(MapValue(entries))
    }
    Union(branches) => {
      if json is Null {
        for index, branch in branches {
          if branch is Primitive(Null) {
            return Ok(UnionValue(index, NullValue))
          }
        }
        return Err(DatumInvalidUnion(path, "union has no null branch"))
      }
      guard json is Object(object) else {
        return Err(
          DatumInvalidUnion(
            path, "non-null union datum must be a single-key object",
          ),
        )
      }
      if object.length() != 1 {
        return Err(
          DatumInvalidUnion(path, "union object must contain exactly one key"),
        )
      }
      for (label, node) in object.iter() {
        for index, branch in branches {
          if datum_union_label(document, branch) == label {
            return match
              value_from_json_node(document, branch, node, path.index(index)) {
              Ok(value) => Ok(UnionValue(index, value))
              Err(error) => Err(error)
            }
          }
        }
        return Err(DatumInvalidUnion(path, "unknown union branch " + label))
      }
      Err(DatumInvalidUnion(path, "empty union object"))
    }
    Fixed(_, size) =>
      match json {
        String(text) => {
          let bytes = match bytes_from_json_string(text, path) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          if bytes.length() != size {
            Err(DatumInvalidFixed(path, size, bytes.length()))
          } else {
            Ok(FixedValue(bytes))
          }
        }
        _ => Err(DatumTypeMismatch(path, "fixed string", json_kind(json)))
      }
  }
}

///|
/// Parse a datum in Avro's JSON encoding using a schema document.
pub fn value_from_json(
  document : SchemaDocument,
  text : StringView,
) -> Result[Value, DatumJsonError] {
  let json = @json.parse(text) catch {
    error => return Err(DatumInvalidJson(error.to_string()))
  }
  value_from_json_node(document, document.root, json, AvroPath::root())
}

///|
fn value_to_json_node(
  document : SchemaDocument,
  schema : Schema,
  value : Value,
  path : AvroPath,
) -> Result[Json, DatumJsonError] {
  match (schema, value) {
    (NamedRef(name), value) =>
      match document.definition(name) {
        Some(target) => value_to_json_node(document, target, value, path)
        None => Err(DatumUnknownReference(path, name))
      }
    (Primitive(Null), NullValue) => Ok(Json::null())
    (Primitive(Boolean), BooleanValue(value)) => Ok(value.to_json())
    (Primitive(Int), IntValue(value)) => Ok(value.to_json())
    (Primitive(Long), LongValue(value)) =>
      Ok(Json::number(value.to_double(), repr=value.to_string()))
    (Primitive(Float), FloatValue(value)) =>
      if value.is_nan() {
        Ok(Json::string("NaN"))
      } else if value.is_pos_inf() {
        Ok(Json::string("Infinity"))
      } else if value.is_neg_inf() {
        Ok(Json::string("-Infinity"))
      } else {
        Ok(value.to_json())
      }
    (Primitive(Double), DoubleValue(value)) =>
      if value.is_nan() {
        Ok(Json::string("NaN"))
      } else if value.is_pos_inf() {
        Ok(Json::string("Infinity"))
      } else if value.is_neg_inf() {
        Ok(Json::string("-Infinity"))
      } else {
        Ok(value.to_json())
      }
    (Primitive(Bytes), BytesValue(bytes)) =>
      Ok(Json::string(bytes_to_json_string(bytes)))
    (Primitive(String), StringValue(text)) => Ok(Json::string(text))
    (Record(_, fields), RecordValue(entries)) => {
      let object : Map[String, Json] = Map([])
      for field in fields {
        let mut found : Value? = None
        for (name, entry) in entries {
          if name == field.name {
            found = Some(entry)
            break
          }
        }
        guard found is Some(entry) else {
          return Err(DatumMissingField(path, field.name))
        }
        match
          value_to_json_node(
            document,
            field.schema,
            entry,
            path.field(field.name),
          ) {
          Ok(json) => object.set(field.name, json)
          Err(error) => return Err(error)
        }
      }
      Ok(Json::object(object))
    }
    (Enum(_, symbols, _), EnumValue(symbol)) =>
      if symbols.contains(symbol) {
        Ok(Json::string(symbol))
      } else {
        Err(DatumUnknownEnumSymbol(path, symbol))
      }
    (ArraySchema(items), ArrayValue(values)) => {
      let nodes : Array[Json] = []
      for index, entry in values {
        match value_to_json_node(document, items, entry, path.index(index)) {
          Ok(json) => nodes.push(json)
          Err(error) => return Err(error)
        }
      }
      Ok(Json::array(nodes))
    }
    (MapSchema(values_schema), MapValue(entries)) => {
      let object : Map[String, Json] = Map([])
      for (key, entry) in entries {
        match
          value_to_json_node(document, values_schema, entry, path.field(key)) {
          Ok(json) => object.set(key, json)
          Err(error) => return Err(error)
        }
      }
      Ok(Json::object(object))
    }
    (Union(branches), UnionValue(index, entry)) => {
      if index < 0 || index >= branches.length() {
        return Err(DatumInvalidUnion(path, "union index is outside schema"))
      }
      let branch = branches[index]
      if branch is Primitive(Null) {
        if entry is NullValue {
          Ok(Json::null())
        } else {
          Err(DatumValueMismatch(path, "null", entry.kind()))
        }
      } else {
        let node = match
          value_to_json_node(document, branch, entry, path.index(index)) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        Ok(Json::object(Map([(datum_union_label(document, branch), node)])))
      }
    }
    (Fixed(_, size), FixedValue(bytes)) =>
      if bytes.length() != size {
        Err(DatumInvalidFixed(path, size, bytes.length()))
      } else {
        Ok(Json::string(bytes_to_json_string(bytes)))
      }
    (schema, value) =>
      Err(DatumValueMismatch(path, schema.display_name(), value.kind()))
  }
}

///|
/// Convert a dynamic value to Avro's JSON datum encoding.
pub fn value_to_json(
  document : SchemaDocument,
  value : Value,
) -> Result[Json, DatumJsonError] {
  value_to_json_node(document, document.root, value, AvroPath::root())
}

///|
pub fn value_to_json_string(
  document : SchemaDocument,
  value : Value,
  pretty? : Bool = false,
) -> Result[String, DatumJsonError] {
  match value_to_json(document, value) {
    Ok(json) => Ok(json.stringify(indent=if pretty { 2 } else { 0 }))
    Err(error) => Err(error)
  }
}
