///|
fn schema_json_string_array(values : Array[String]) -> Json {
  Json::array(values.map(value => Json::string(value)))
}

///|
fn schema_json_put_optional_string(
  object : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  match value {
    Some(text) => object.set(key, Json::string(text))
    None => ()
  }
}

///|
fn schema_json_named_properties(
  object : Map[String, Json],
  named : NamedType,
) -> Unit {
  object.set("name", Json::string(named.name))
  if !named.namespace_name.is_empty() {
    object.set("namespace", Json::string(named.namespace_name))
  }
  if !named.aliases.is_empty() {
    object.set("aliases", schema_json_string_array(named.aliases))
  }
  schema_json_put_optional_string(object, "doc", named.doc)
}

///|
fn schema_json_default(
  document : SchemaDocument,
  schema : Schema,
  value : Value,
  path : AvroPath,
) -> Result[Json, SchemaError] {
  match schema {
    Union(branches) =>
      match value {
        UnionValue(0, inner) if !branches.is_empty() =>
          schema_json_default(document, branches[0], inner, path)
        _ =>
          Err(InvalidDefault(path, "union default must use its first branch"))
      }
    _ =>
      match value_to_json_node(document, schema, value, path) {
        Ok(json) => Ok(json)
        Err(_) =>
          Err(
            InvalidDefault(path, "default cannot be represented as schema JSON"),
          )
      }
  }
}

///|
fn schema_json_node(
  document : SchemaDocument,
  schema : Schema,
  path : AvroPath,
) -> Result[Json, SchemaError] {
  match schema {
    Primitive(kind) => Ok(Json::string(kind.name()))
    NamedRef(name) => Ok(Json::string(name))
    Union(branches) => {
      let values : Array[Json] = []
      for index, branch in branches {
        match schema_json_node(document, branch, path.index(index)) {
          Ok(json) => values.push(json)
          Err(error) => return Err(error)
        }
      }
      Ok(Json::array(values))
    }
    ArraySchema(items) => {
      let object : Map[String, Json] = Map([])
      object.set("type", Json::string("array"))
      match schema_json_node(document, items, path.field("items")) {
        Ok(json) => object.set("items", json)
        Err(error) => return Err(error)
      }
      Ok(Json::object(object))
    }
    MapSchema(values) => {
      let object : Map[String, Json] = Map([])
      object.set("type", Json::string("map"))
      match schema_json_node(document, values, path.field("values")) {
        Ok(json) => object.set("values", json)
        Err(error) => return Err(error)
      }
      Ok(Json::object(object))
    }
    Record(named, fields) => {
      let object : Map[String, Json] = Map([])
      object.set("type", Json::string("record"))
      schema_json_named_properties(object, named)
      let field_nodes : Array[Json] = []
      for field in fields {
        let field_object : Map[String, Json] = Map([])
        field_object.set("name", Json::string(field.name))
        match
          schema_json_node(
            document,
            field.schema,
            path.field("fields").field(field.name).field("type"),
          ) {
          Ok(json) => field_object.set("type", json)
          Err(error) => return Err(error)
        }
        if !field.aliases.is_empty() {
          field_object.set("aliases", schema_json_string_array(field.aliases))
        }
        schema_json_put_optional_string(field_object, "doc", field.doc)
        if field.order != "ascending" {
          field_object.set("order", Json::string(field.order))
        }
        match field.default {
          Some(value) =>
            match
              schema_json_default(
                document,
                field.schema,
                value,
                path.field("fields").field(field.name).field("default"),
              ) {
              Ok(json) => field_object.set("default", json)
              Err(error) => return Err(error)
            }
          None => ()
        }
        field_nodes.push(Json::object(field_object))
      }
      object.set("fields", Json::array(field_nodes))
      Ok(Json::object(object))
    }
    Enum(named, symbols, default) => {
      let object : Map[String, Json] = Map([])
      object.set("type", Json::string("enum"))
      schema_json_named_properties(object, named)
      object.set("symbols", schema_json_string_array(symbols))
      schema_json_put_optional_string(object, "default", default)
      Ok(Json::object(object))
    }
    Fixed(named, size) => {
      let object : Map[String, Json] = Map([])
      object.set("type", Json::string("fixed"))
      schema_json_named_properties(object, named)
      object.set("size", Json::number(size.to_double()))
      Ok(Json::object(object))
    }
  }
}

///|
/// Serialize a parsed schema document as Avro schema JSON.
///
/// Unlike parsing canonical form, this preserves reader-relevant defaults,
/// aliases, documentation, and field ordering metadata. It is suitable for
/// embedding the writer schema in an Avro object container file.
pub fn schema_to_json(
  document : SchemaDocument,
  pretty? : Bool = false,
) -> Result[String, SchemaError] {
  match schema_json_node(document, document.root, AvroPath::root()) {
    Ok(json) => Ok(json.stringify(indent=if pretty { 2 } else { 0 }))
    Err(error) => Err(error)
  }
}
