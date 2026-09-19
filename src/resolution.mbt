///|
/// One compatibility problem discovered while comparing writer and reader
/// schemas. A report can contain several independent missing fields.
pub(all) struct CompatibilityIssue {
  path : AvroPath
  writer : String
  reader : String
  message : String
} derive(Eq, Debug)

///|
pub(all) struct CompatibilityReport {
  compatible : Bool
  issues : Array[CompatibilityIssue]
} derive(Eq, Debug)

///|
fn dereference(document : SchemaDocument, schema : Schema) -> Schema {
  match schema {
    NamedRef(name) => document.definition(name).unwrap_or(schema)
    _ => schema
  }
}

///|
fn named_matches(writer : NamedType, reader : NamedType) -> Bool {
  if writer.full_name == reader.full_name {
    return true
  }
  for accepted in reader.aliases {
    if accepted == writer.full_name {
      return true
    }
  }
  false
}

///|
fn field_matches(writer : Field, reader : Field) -> Bool {
  if writer.name == reader.name {
    return true
  }
  for accepted in reader.aliases {
    if accepted == writer.name {
      return true
    }
  }
  false
}

///|
fn primitive_compatible(writer : PrimitiveKind, reader : PrimitiveKind) -> Bool {
  if writer == reader {
    return true
  }
  match (writer, reader) {
    (Int, Long | Float | Double) => true
    (Long, Float | Double) => true
    (Float, Double) => true
    (String, Bytes) | (Bytes, String) => true
    _ => false
  }
}

///|
fn schemas_compatible(
  writer_document : SchemaDocument,
  reader_document : SchemaDocument,
  writer_schema : Schema,
  reader_schema : Schema,
  active : Map[String, Bool],
) -> Bool {
  let writer = dereference(writer_document, writer_schema)
  let reader = dereference(reader_document, reader_schema)
  let pair_key = writer.display_name() + "->" + reader.display_name()
  if active.contains(pair_key) {
    return true
  }
  active.set(pair_key, true)
  let result = match (writer, reader) {
    (Primitive(left), Primitive(right)) => primitive_compatible(left, right)
    (Record(writer_name, writer_fields), Record(reader_name, reader_fields)) =>
      if !named_matches(writer_name, reader_name) {
        false
      } else {
        let mut valid = true
        for reader_field in reader_fields {
          let mut writer_match : Field? = None
          for writer_field in writer_fields {
            if field_matches(writer_field, reader_field) {
              writer_match = Some(writer_field)
              break
            }
          }
          match writer_match {
            Some(writer_field) =>
              if !schemas_compatible(
                  writer_document,
                  reader_document,
                  writer_field.schema,
                  reader_field.schema,
                  active,
                ) {
                valid = false
                break
              }
            None =>
              if reader_field.default is None {
                valid = false
                break
              }
          }
        }
        valid
      }
    (
      Enum(writer_name, writer_symbols, _),
      Enum(reader_name, reader_symbols, default),
    ) =>
      if !named_matches(writer_name, reader_name) {
        false
      } else {
        let mut valid = true
        for symbol in writer_symbols {
          if !reader_symbols.contains(symbol) && default is None {
            valid = false
            break
          }
        }
        valid
      }
    (Fixed(writer_name, writer_size), Fixed(reader_name, reader_size)) =>
      named_matches(writer_name, reader_name) && writer_size == reader_size
    (ArraySchema(writer_items), ArraySchema(reader_items)) =>
      schemas_compatible(
        writer_document, reader_document, writer_items, reader_items, active,
      )
    (MapSchema(writer_values), MapSchema(reader_values)) =>
      schemas_compatible(
        writer_document, reader_document, writer_values, reader_values, active,
      )
    (Union(writer_branches), Union(reader_branches)) => {
      let mut all_match = true
      for writer_branch in writer_branches {
        let mut one_match = false
        for reader_branch in reader_branches {
          if schemas_compatible(
              writer_document,
              reader_document,
              writer_branch,
              reader_branch,
              Map([]),
            ) {
            one_match = true
            break
          }
        }
        if !one_match {
          all_match = false
          break
        }
      }
      all_match
    }
    (Union(writer_branches), reader) => {
      let mut valid = true
      for branch in writer_branches {
        if !schemas_compatible(
            writer_document,
            reader_document,
            branch,
            reader,
            Map([]),
          ) {
          valid = false
          break
        }
      }
      valid
    }
    (writer, Union(reader_branches)) => {
      let mut valid = false
      for branch in reader_branches {
        if schemas_compatible(
            writer_document,
            reader_document,
            writer,
            branch,
            Map([]),
          ) {
          valid = true
          break
        }
      }
      valid
    }
    _ => false
  }
  active.remove(pair_key)
  result
}

///|
fn add_issue(
  issues : Array[CompatibilityIssue],
  path : AvroPath,
  writer : Schema,
  reader : Schema,
  message : String,
) -> Unit {
  issues.push({
    path,
    writer: writer.display_name(),
    reader: reader.display_name(),
    message,
  })
}

///|
fn collect_compatibility_issues(
  writer_document : SchemaDocument,
  reader_document : SchemaDocument,
  writer_schema : Schema,
  reader_schema : Schema,
  path : AvroPath,
  issues : Array[CompatibilityIssue],
  active : Map[String, Bool],
) -> Unit {
  let writer = dereference(writer_document, writer_schema)
  let reader = dereference(reader_document, reader_schema)
  let pair_key = writer.display_name() + "->" + reader.display_name()
  if active.contains(pair_key) {
    return
  }
  active.set(pair_key, true)
  match (writer, reader) {
    (Primitive(left), Primitive(right)) =>
      if !primitive_compatible(left, right) {
        add_issue(
          issues, path, writer, reader, "primitive types cannot be promoted",
        )
      }
    (Record(writer_name, writer_fields), Record(reader_name, reader_fields)) =>
      if !named_matches(writer_name, reader_name) {
        add_issue(
          issues, path, writer, reader, "record full names or aliases do not match",
        )
      } else {
        for reader_field in reader_fields {
          let mut writer_match : Field? = None
          for writer_field in writer_fields {
            if field_matches(writer_field, reader_field) {
              writer_match = Some(writer_field)
              break
            }
          }
          match writer_match {
            Some(writer_field) =>
              collect_compatibility_issues(
                writer_document,
                reader_document,
                writer_field.schema,
                reader_field.schema,
                path.field(reader_field.name),
                issues,
                active,
              )
            None =>
              if reader_field.default is None {
                add_issue(
                  issues,
                  path.field(reader_field.name),
                  writer,
                  reader,
                  "reader field is missing from writer and has no default",
                )
              }
          }
        }
      }
    (
      Enum(writer_name, writer_symbols, _),
      Enum(reader_name, reader_symbols, default),
    ) =>
      if !named_matches(writer_name, reader_name) {
        add_issue(
          issues, path, writer, reader, "enum full names or aliases do not match",
        )
      } else {
        for symbol in writer_symbols {
          if !reader_symbols.contains(symbol) && default is None {
            add_issue(
              issues,
              path,
              writer,
              reader,
              "reader enum does not contain writer symbol " + symbol,
            )
          }
        }
      }
    (Fixed(writer_name, writer_size), Fixed(reader_name, reader_size)) => {
      if !named_matches(writer_name, reader_name) {
        add_issue(
          issues, path, writer, reader, "fixed full names or aliases do not match",
        )
      }
      if writer_size != reader_size {
        add_issue(issues, path, writer, reader, "fixed sizes differ")
      }
    }
    (ArraySchema(writer_items), ArraySchema(reader_items)) =>
      collect_compatibility_issues(
        writer_document,
        reader_document,
        writer_items,
        reader_items,
        path.field("items"),
        issues,
        active,
      )
    (MapSchema(writer_values), MapSchema(reader_values)) =>
      collect_compatibility_issues(
        writer_document,
        reader_document,
        writer_values,
        reader_values,
        path.field("values"),
        issues,
        active,
      )
    _ =>
      if !schemas_compatible(
          writer_document,
          reader_document,
          writer,
          reader,
          Map([]),
        ) {
        add_issue(
          issues, path, writer, reader, "schemas do not match Avro resolution rules",
        )
      }
  }
  active.remove(pair_key)
}

///|
/// Compare the writer schema against the reader schema and return all useful
/// diagnostics discovered in one traversal.
pub fn check_compatibility(
  writer : SchemaDocument,
  reader : SchemaDocument,
) -> CompatibilityReport {
  let issues : Array[CompatibilityIssue] = []
  collect_compatibility_issues(
    writer,
    reader,
    writer.root,
    reader.root,
    AvroPath::root(),
    issues,
    Map([]),
  )
  { compatible: issues.is_empty(), issues, }
}

///|
fn resolve_primitive_value(
  writer : PrimitiveKind,
  reader : PrimitiveKind,
  value : Value,
  path : AvroPath,
) -> Result[Value, ResolutionError] {
  if writer == reader {
    return Ok(value)
  }
  match (writer, reader, value) {
    (Int, Long, IntValue(number)) => Ok(LongValue(number.to_int64()))
    (Int, Float, IntValue(number)) => Ok(FloatValue(Float::from_int(number)))
    (Int, Double, IntValue(number)) => Ok(DoubleValue(number.to_double()))
    (Long, Float, LongValue(number)) =>
      Ok(FloatValue(Float::from_int64(number)))
    (Long, Double, LongValue(number)) => Ok(DoubleValue(number.to_double()))
    (Float, Double, FloatValue(number)) => Ok(DoubleValue(number.to_double()))
    (String, Bytes, StringValue(text)) => Ok(BytesValue(@utf8.encode(text)))
    (Bytes, String, BytesValue(bytes)) => {
      let decoded = @utf8.decode(bytes[:]) catch {
        _ =>
          return Err(
            InvalidResolvedValue(
              path, "writer bytes are not valid UTF-8 for string reader",
            ),
          )
      }
      Ok(StringValue(decoded))
    }
    _ => Err(Incompatible(path, writer.name(), reader.name()))
  }
}

///|
fn resolve_value_with_schema(
  writer_document : SchemaDocument,
  reader_document : SchemaDocument,
  writer_schema : Schema,
  reader_schema : Schema,
  value : Value,
  path : AvroPath,
) -> Result[Value, ResolutionError] {
  let writer = dereference(writer_document, writer_schema)
  let reader = dereference(reader_document, reader_schema)
  match (writer, reader) {
    (Union(writer_branches), reader_schema) => {
      guard value is UnionValue(index, branch_value) else {
        return Err(InvalidResolvedValue(path, "writer union value expected"))
      }
      if index < 0 || index >= writer_branches.length() {
        return Err(
          InvalidResolvedValue(path, "writer union index out of range"),
        )
      }
      resolve_value_with_schema(
        writer_document,
        reader_document,
        writer_branches[index],
        reader_schema,
        branch_value,
        path.index(index),
      )
    }
    (writer_schema, Union(reader_branches)) => {
      for index, branch in reader_branches {
        if schemas_compatible(
            writer_document,
            reader_document,
            writer_schema,
            branch,
            Map([]),
          ) {
          return match
            resolve_value_with_schema(
              writer_document,
              reader_document,
              writer_schema,
              branch,
              value,
              path.index(index),
            ) {
            Ok(resolved) => Ok(UnionValue(index, resolved))
            Err(error) => Err(error)
          }
        }
      }
      Err(NoMatchingUnionBranch(path, writer_schema.display_name()))
    }
    (Primitive(writer_kind), Primitive(reader_kind)) =>
      resolve_primitive_value(writer_kind, reader_kind, value, path)
    (Record(writer_name, writer_fields), Record(reader_name, reader_fields)) => {
      if !named_matches(writer_name, reader_name) {
        return Err(
          Incompatible(path, writer_name.full_name, reader_name.full_name),
        )
      }
      guard value is RecordValue(writer_entries) else {
        return Err(InvalidResolvedValue(path, "record value expected"))
      }
      let result : Array[(String, Value)] = []
      for reader_field in reader_fields {
        let mut writer_field_match : Field? = None
        for writer_field in writer_fields {
          if field_matches(writer_field, reader_field) {
            writer_field_match = Some(writer_field)
            break
          }
        }
        match writer_field_match {
          None =>
            match reader_field.default {
              Some(default) => result.push((reader_field.name, default))
              None => return Err(MissingReaderDefault(path, reader_field.name))
            }
          Some(writer_field) => {
            let mut writer_value : Value? = None
            for (name, entry) in writer_entries {
              if name == writer_field.name {
                writer_value = Some(entry)
                break
              }
            }
            guard writer_value is Some(entry) else {
              return Err(
                InvalidResolvedValue(path, "decoded writer field is missing"),
              )
            }
            let resolved = match
              resolve_value_with_schema(
                writer_document,
                reader_document,
                writer_field.schema,
                reader_field.schema,
                entry,
                path.field(reader_field.name),
              ) {
              Ok(value) => value
              Err(error) => return Err(error)
            }
            result.push((reader_field.name, resolved))
          }
        }
      }
      Ok(RecordValue(result))
    }
    (Enum(writer_name, _, _), Enum(reader_name, reader_symbols, default)) => {
      if !named_matches(writer_name, reader_name) {
        return Err(
          Incompatible(path, writer_name.full_name, reader_name.full_name),
        )
      }
      guard value is EnumValue(symbol) else {
        return Err(InvalidResolvedValue(path, "enum value expected"))
      }
      if reader_symbols.contains(symbol) {
        Ok(EnumValue(symbol))
      } else {
        match default {
          Some(fallback) => Ok(EnumValue(fallback))
          None => Err(MissingEnumDefault(path, symbol))
        }
      }
    }
    (Fixed(writer_name, writer_size), Fixed(reader_name, reader_size)) =>
      if !named_matches(writer_name, reader_name) || writer_size != reader_size {
        Err(Incompatible(path, writer.display_name(), reader.display_name()))
      } else {
        Ok(value)
      }
    (ArraySchema(writer_items), ArraySchema(reader_items)) => {
      guard value is ArrayValue(values) else {
        return Err(InvalidResolvedValue(path, "array value expected"))
      }
      let result : Array[Value] = []
      for index, entry in values {
        match
          resolve_value_with_schema(
            writer_document,
            reader_document,
            writer_items,
            reader_items,
            entry,
            path.index(index),
          ) {
          Ok(resolved) => result.push(resolved)
          Err(error) => return Err(error)
        }
      }
      Ok(ArrayValue(result))
    }
    (MapSchema(writer_values), MapSchema(reader_values)) => {
      guard value is MapValue(entries) else {
        return Err(InvalidResolvedValue(path, "map value expected"))
      }
      let result : Array[(String, Value)] = []
      for (key, entry) in entries {
        match
          resolve_value_with_schema(
            writer_document,
            reader_document,
            writer_values,
            reader_values,
            entry,
            path.field(key),
          ) {
          Ok(resolved) => result.push((key, resolved))
          Err(error) => return Err(error)
        }
      }
      Ok(MapValue(result))
    }
    _ => Err(Incompatible(path, writer.display_name(), reader.display_name()))
  }
}

///|
/// Transform an already-decoded writer value into the reader schema.
pub fn resolve_value(
  writer : SchemaDocument,
  reader : SchemaDocument,
  value : Value,
) -> Result[Value, ResolutionError] {
  resolve_value_with_schema(
    writer,
    reader,
    writer.root,
    reader.root,
    value,
    AvroPath::root(),
  )
}

///|
pub(all) suberror ResolvedDecodeError {
  WriterDecode(DecodeError)
  SchemaResolution(ResolutionError)
} derive(Eq, Debug)

///|
/// Decode with the writer schema and immediately apply reader-schema evolution.
pub fn decode_resolved(
  writer : SchemaDocument,
  reader : SchemaDocument,
  bytes : Bytes,
) -> Result[Value, ResolvedDecodeError] {
  let writer_value = match decode(writer, bytes) {
    Ok(value) => value
    Err(error) => return Err(WriterDecode(error))
  }
  match resolve_value(writer, reader, writer_value) {
    Ok(value) => Ok(value)
    Err(error) => Err(SchemaResolution(error))
  }
}
