///|
fn encode_schema_value(
  writer : BinaryWriter,
  document : SchemaDocument,
  schema : Schema,
  value : Value,
  path : AvroPath,
) -> Result[Unit, EncodeError] {
  match (schema, value) {
    (Primitive(Null), NullValue) => Ok(())
    (Primitive(Boolean), BooleanValue(value)) => {
      writer.write_boolean(value)
      Ok(())
    }
    (Primitive(Int), IntValue(value)) => {
      writer.write_int(value)
      Ok(())
    }
    (Primitive(Long), LongValue(value)) => {
      writer.write_long(value)
      Ok(())
    }
    (Primitive(Float), FloatValue(value)) => {
      writer.write_float(value)
      Ok(())
    }
    (Primitive(Double), DoubleValue(value)) => {
      writer.write_double(value)
      Ok(())
    }
    (Primitive(Bytes), BytesValue(value)) => {
      writer.write_bytes(value)
      Ok(())
    }
    (Primitive(String), StringValue(value)) => {
      writer.write_string(value)
      Ok(())
    }
    (Record(_, fields), RecordValue(entries)) => {
      for field in fields {
        let mut found : Value? = None
        for (name, entry) in entries {
          if name == field.name {
            found = Some(entry)
            break
          }
        }
        match found {
          None => return Err(MissingFieldValue(path, field.name))
          Some(entry) =>
            match
              encode_schema_value(
                writer,
                document,
                field.schema,
                entry,
                path.field(field.name),
              ) {
              Ok(_) => ()
              Err(error) => return Err(error)
            }
        }
      }
      Ok(())
    }
    (Enum(_, symbols, _), EnumValue(symbol)) => {
      let mut index = -1
      for position, candidate in symbols {
        if candidate == symbol {
          index = position
          break
        }
      }
      if index < 0 {
        Err(UnknownEnumSymbol(path, symbol))
      } else {
        writer.write_int(index)
        Ok(())
      }
    }
    (ArraySchema(items), ArrayValue(values)) => {
      if !values.is_empty() {
        writer.write_long(values.length().to_int64())
        for index, entry in values {
          match
            encode_schema_value(
              writer,
              document,
              items,
              entry,
              path.index(index),
            ) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
      }
      writer.write_long(0L)
      Ok(())
    }
    (MapSchema(values_schema), MapValue(entries)) => {
      if !entries.is_empty() {
        writer.write_long(entries.length().to_int64())
        for (key, entry) in entries {
          writer.write_string(key)
          match
            encode_schema_value(
              writer,
              document,
              values_schema,
              entry,
              path.field(key),
            ) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
      }
      writer.write_long(0L)
      Ok(())
    }
    (Union(branches), UnionValue(branch, entry)) => {
      if branch < 0 || branch >= branches.length() {
        return Err(InvalidUnionBranch(path, branch))
      }
      writer.write_int(branch)
      encode_schema_value(
        writer,
        document,
        branches[branch],
        entry,
        path.index(branch),
      )
    }
    (Fixed(_, size), FixedValue(bytes)) =>
      if bytes.length() != size {
        Err(FixedSizeMismatch(path, size, bytes.length()))
      } else {
        writer.write_raw(bytes[:])
        Ok(())
      }
    (NamedRef(name), entry) =>
      match document.definition(name) {
        Some(target) =>
          encode_schema_value(writer, document, target, entry, path)
        None => Err(UnresolvedName(path, name))
      }
    (expected, actual) =>
      Err(ValueMismatch(path, expected.display_name(), actual.kind()))
  }
}

///|
/// Encode a datum using the document's root schema.
pub fn encode(
  document : SchemaDocument,
  value : Value,
) -> Result[Bytes, EncodeError] {
  let writer = BinaryWriter::new()
  match
    encode_schema_value(
      writer,
      document,
      document.root,
      value,
      AvroPath::root(),
    ) {
    Ok(_) => Ok(writer.finish())
    Err(error) => Err(error)
  }
}

///|
/// Encode a datum using an explicitly selected schema in the same document.
pub fn encode_with_schema(
  document : SchemaDocument,
  schema : Schema,
  value : Value,
) -> Result[Bytes, EncodeError] {
  let writer = BinaryWriter::new()
  match encode_schema_value(writer, document, schema, value, AvroPath::root()) {
    Ok(_) => Ok(writer.finish())
    Err(error) => Err(error)
  }
}

///|
/// Append one datum to an existing writer. Container-file code uses this to
/// encode many objects into a single block without temporary framing.
pub fn encode_into(
  writer : BinaryWriter,
  document : SchemaDocument,
  value : Value,
) -> Result[Unit, EncodeError] {
  encode_schema_value(writer, document, document.root, value, AvroPath::root())
}
