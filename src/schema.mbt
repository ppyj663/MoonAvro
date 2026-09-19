///|
/// Primitive types defined by the Avro data model.
pub(all) enum PrimitiveKind {
  Null
  Boolean
  Int
  Long
  Float
  Double
  Bytes
  String
} derive(Eq, Debug)

///|
pub fn PrimitiveKind::name(self : PrimitiveKind) -> String {
  match self {
    Null => "null"
    Boolean => "boolean"
    Int => "int"
    Long => "long"
    Float => "float"
    Double => "double"
    Bytes => "bytes"
    String => "string"
  }
}

///|
pub fn primitive_from_name(name : String) -> PrimitiveKind? {
  match name {
    "null" => Some(Null)
    "boolean" => Some(Boolean)
    "int" => Some(Int)
    "long" => Some(Long)
    "float" => Some(Float)
    "double" => Some(Double)
    "bytes" => Some(Bytes)
    "string" => Some(String)
    _ => None
  }
}

///|
/// Shared metadata for record, enum, and fixed schemas.
pub(all) struct NamedType {
  name : String
  namespace : String
  full_name : String
  aliases : Array[String]
  doc : String?
} derive(Eq, Debug)

///|
pub fn NamedType::new(
  name : String,
  namespace : String,
  aliases : Array[String],
  doc : String?,
) -> NamedType {
  let full_name = if namespace.is_empty() {
    name
  } else {
    namespace + "." + name
  }
  { name, namespace, full_name, aliases, doc, }
}

///|
/// A field in an Avro record schema.
pub(all) struct Field {
  name : String
  schema : Schema
  aliases : Array[String]
  doc : String?
  default : Value?
  order : String
  position : Int
} derive(Eq, Debug)

///|
pub fn Field::new(
  name : String,
  schema : Schema,
  position : Int,
  aliases? : Array[String] = [],
  doc? : String? = None,
  default? : Value? = None,
  order? : String = "ascending",
) -> Field {
  { name, schema, aliases, doc, default, order, position, }
}

///|
/// Supported Avro schemas. Named references remain explicit so recursive types
/// can be represented without creating an infinitely recursive value.
pub(all) enum Schema {
  Primitive(PrimitiveKind)
  Record(NamedType, Array[Field])
  Enum(NamedType, Array[String], String?)
  ArraySchema(Schema)
  MapSchema(Schema)
  Union(Array[Schema])
  Fixed(NamedType, Int)
  NamedRef(String)
} derive(Eq, Debug)

///|
pub fn Schema::kind(self : Schema) -> String {
  match self {
    Primitive(kind) => kind.name()
    Record(_, _) => "record"
    Enum(_, _, _) => "enum"
    ArraySchema(_) => "array"
    MapSchema(_) => "map"
    Union(_) => "union"
    Fixed(_, _) => "fixed"
    NamedRef(_) => "reference"
  }
}

///|
pub fn Schema::display_name(self : Schema) -> String {
  match self {
    Primitive(kind) => kind.name()
    Record(named, _) => named.full_name
    Enum(named, _, _) => named.full_name
    Fixed(named, _) => named.full_name
    NamedRef(name) => name
    ArraySchema(item) => "array<" + item.display_name() + ">"
    MapSchema(value) => "map<" + value.display_name() + ">"
    Union(branches) => {
      let buffer = StringBuilder::new()
      buffer.write_string("union[")
      for index, branch in branches {
        if index > 0 {
          buffer.write_string(",")
        }
        buffer.write_string(branch.display_name())
      }
      buffer.write_string("]")
      buffer.to_string()
    }
  }
}

///|
pub fn Schema::named_type(self : Schema) -> NamedType? {
  match self {
    Record(named, _) | Enum(named, _, _) | Fixed(named, _) => Some(named)
    _ => None
  }
}

///|
pub fn Schema::fields(self : Schema) -> Array[Field]? {
  match self {
    Record(_, fields) => Some(fields)
    _ => None
  }
}

///|
/// A root schema plus every named definition reachable from it.
pub(all) struct SchemaDocument {
  root : Schema
  definitions : Map[String, Schema]
} derive(Eq, Debug)

///|
pub fn SchemaDocument::new(
  root : Schema,
  definitions : Map[String, Schema],
) -> SchemaDocument {
  { root, definitions, }
}

///|
pub fn SchemaDocument::of(root : Schema) -> SchemaDocument {
  { root, definitions: Map::new(), }
}

///|
pub fn SchemaDocument::resolve(
  self : SchemaDocument,
  schema : Schema,
) -> Schema? {
  match schema {
    NamedRef(name) => self.definitions.get(name)
    other => Some(other)
  }
}

///|
pub fn SchemaDocument::definition(
  self : SchemaDocument,
  name : String,
) -> Schema? {
  self.definitions.get(name)
}

///|
pub fn SchemaDocument::definition_count(self : SchemaDocument) -> Int {
  self.definitions.size()
}

///|
pub fn SchemaDocument::all_names(self : SchemaDocument) -> Array[String] {
  let result : Array[String] = []
  for (name, _) in self.definitions.iter() {
    result.push(name)
  }
  result
}

///|
pub fn fullname(name : String, namespace : String) -> String {
  if name.contains(".") || namespace.is_empty() {
    name
  } else {
    namespace + "." + name
  }
}

///|
pub fn shortname(name : String) -> String {
  let parts = name.split(".").to_array()
  if parts.is_empty() {
    name
  } else {
    parts[parts.length() - 1].to_owned()
  }
}

///|
pub fn namespace_of(name : String) -> String {
  let parts = name.split(".").to_array()
  if parts.length() <= 1 {
    ""
  } else {
    parts[0:parts.length() - 1].join(".")
  }
}

///|
pub fn valid_name(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  for index, character in name {
    let first_ok = character == '_' || character.is_ascii_alphabetic()
    let rest_ok = first_ok || character.is_ascii_digit()
    if (index == 0 && !first_ok) || (index > 0 && !rest_ok) {
      return false
    }
  }
  true
}

///|
pub fn valid_fullname(name : String) -> Bool {
  let parts = name.split(".").to_array()
  if parts.is_empty() {
    return false
  }
  for part in parts {
    if !valid_name(part.to_owned()) {
      return false
    }
  }
  true
}
