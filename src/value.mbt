///|
/// Dynamic Avro data. Record and map entries use arrays to preserve insertion
/// order and deterministic diagnostics while still exposing lookup helpers.
pub(all) enum Value {
  NullValue
  BooleanValue(Bool)
  IntValue(Int)
  LongValue(Int64)
  FloatValue(Float)
  DoubleValue(Double)
  BytesValue(Bytes)
  StringValue(String)
  RecordValue(Array[(String, Value)])
  EnumValue(String)
  ArrayValue(Array[Value])
  MapValue(Array[(String, Value)])
  UnionValue(Int, Value)
  FixedValue(Bytes)
} derive(Eq, Debug)

///|
pub fn Value::kind(self : Value) -> String {
  match self {
    NullValue => "null"
    BooleanValue(_) => "boolean"
    IntValue(_) => "int"
    LongValue(_) => "long"
    FloatValue(_) => "float"
    DoubleValue(_) => "double"
    BytesValue(_) => "bytes"
    StringValue(_) => "string"
    RecordValue(_) => "record"
    EnumValue(_) => "enum"
    ArrayValue(_) => "array"
    MapValue(_) => "map"
    UnionValue(_, _) => "union"
    FixedValue(_) => "fixed"
  }
}

///|
pub fn Value::record(entries : Array[(String, Value)]) -> Value {
  RecordValue(entries)
}

///|
pub fn Value::array(items : Array[Value]) -> Value {
  ArrayValue(items)
}

///|
pub fn Value::map(entries : Array[(String, Value)]) -> Value {
  MapValue(entries)
}

///|
pub fn Value::union(branch : Int, value : Value) -> Value {
  UnionValue(branch, value)
}

///|
pub fn Value::get_field(self : Value, name : String) -> Value? {
  match self {
    RecordValue(entries) => {
      for (key, value) in entries {
        if key == name {
          return Some(value)
        }
      }
      None
    }
    _ => None
  }
}

///|
pub fn Value::get_key(self : Value, name : String) -> Value? {
  match self {
    MapValue(entries) => {
      for (key, value) in entries {
        if key == name {
          return Some(value)
        }
      }
      None
    }
    _ => None
  }
}

///|
pub fn Value::as_string(self : Value) -> String? {
  match self {
    StringValue(value) => Some(value)
    _ => None
  }
}

///|
pub fn Value::as_long(self : Value) -> Int64? {
  match self {
    LongValue(value) => Some(value)
    IntValue(value) => Some(value.to_int64())
    _ => None
  }
}

///|
pub fn Value::is_null(self : Value) -> Bool {
  self == NullValue
}
