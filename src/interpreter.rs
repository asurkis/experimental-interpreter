use crate::declare_enum_as;
use crate::parser::Tree;
use crate::util::replace_or_remove;
use std::collections::HashMap;

#[derive(Debug, Clone, Default)]
struct Context<'a> {
    variables: HashMap<&'a str, Value>,
}

#[derive(Debug, Clone)]
pub enum TypeInfo {
    Unit,
    Int64,
    Array(Box<TypeInfo>),
}

#[derive(Debug, Clone)]
pub enum Value {
    Unit,
    Int64(i64),
    Type(TypeInfo),
    Array(Vec<Value>),
}

impl TypeInfo {
    pub fn zero(&self) -> Value {
        match self {
            Self::Unit => Value::Unit,
            Self::Int64 => Value::Int64(0),
            Self::Array(_) => Value::Array(Vec::new()),
        }
    }
}

declare_enum_as!(Value, as_int64 copy Int64(x) -> i64);
declare_enum_as!(Value, into_type Type(x) -> TypeInfo);
declare_enum_as!(Value, as_type &Type(x) -> TypeInfo);
declare_enum_as!(Value, into_array Array(x) -> Vec<Value>);
// enum_as!(Value, as_array_ref &Array(x) -> Vec<Value>);
declare_enum_as!(Value, as_array_mut &mut Array(x) -> Vec<Value>);

fn interpret<'a>(ctx: &mut Context<'a>, tree: &'a Tree) -> Result<Value, String> {
    match tree {
        Tree::Atom(var) => ctx
            .variables
            .get(&var[..])
            .cloned()
            .ok_or_else(|| format!("Unknown variable {var:?}")),
        Tree::Array(arr) => {
            if arr.is_empty() {
                return Err("Empty array".into());
            }
            match &arr[0] {
                Tree::Atom(s) => match &s[..] {
                    "+" => {
                        let mut acc = interpret(ctx, &arr[1])?.as_int64()?;
                        for x in &arr[2..] {
                            acc = acc.wrapping_add(interpret(ctx, x)?.as_int64()?);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "-" => {
                        let mut acc = interpret(ctx, &arr[1])?.as_int64()?;
                        for x in &arr[2..] {
                            acc = acc.wrapping_sub(interpret(ctx, x)?.as_int64()?);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "*" => {
                        let mut acc = interpret(ctx, &arr[1])?.as_int64()?;
                        for x in &arr[2..] {
                            acc = acc.wrapping_mul(interpret(ctx, x)?.as_int64()?);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "/" => {
                        let mut acc = interpret(ctx, &arr[1])?.as_int64()?;
                        for x in &arr[2..] {
                            let y = interpret(ctx, x)?.as_int64()?;
                            if y == 0 {
                                return Err("Division by zero".into());
                            }
                            acc /= y;
                        }
                        Ok(Value::Int64(acc))
                    }
                    "let" => {
                        if arr.len() != 4 {
                            return Err("Variable binding must have variable name, value, and expression where the variable is used".into());
                        }
                        let var = arr[1].as_atom()?;
                        let val = interpret(ctx, &arr[2])?;
                        let old_val = ctx.variables.insert(&var[..], val);
                        let body = interpret(ctx, &arr[3]);
                        replace_or_remove(&mut ctx.variables, &var[..], old_val);
                        body
                    }
                    "var" => {
                        if arr.len() != 4 {
                            return Err(
                                "Variable declaration must have variable, name, type and expression where the variable is used".into()
                            );
                        }
                        let var = arr[1].as_atom()?;
                        let typ_val = interpret(ctx, &arr[2])?;
                        let typ = typ_val.as_type()?;
                        let old_val = ctx.variables.insert(&var[..], typ.zero());
                        let body = interpret(ctx, &arr[3]);
                        replace_or_remove(&mut ctx.variables, &var[..], old_val);
                        body
                    }
                    "seq" => {
                        let mut out = Value::Unit;
                        for x in &arr[1..] {
                            out = interpret(ctx, x)?;
                        }
                        Ok(out)
                    }
                    "set" => {
                        if arr.len() != 3 {
                            return Err("Need variable name and new value".into());
                        }
                        let var = arr[1].as_atom()?;
                        let val = interpret(ctx, &arr[2])?;
                        let pos = ctx
                            .variables
                            .get_mut(&var[..])
                            .ok_or_else(|| format!("Undeclared variable {var:?}"))?;
                        *pos = val;
                        Ok(Value::Unit)
                    }
                    "array" => {
                        let mut out = Vec::new();
                        for x in &arr[1..] {
                            out.push(interpret(ctx, x)?);
                        }
                        Ok(Value::Array(out))
                    }
                    "array-t" => {
                        if arr.len() != 2 {
                            return Err("Argument count mismatch".into());
                        }
                        let inner = interpret(ctx, &arr[1])?.into_type()?;
                        Ok(Value::Type(TypeInfo::Array(Box::new(inner))))
                    }
                    "array-get" => {
                        if arr.len() != 3 {
                            return Err("Argument count mismatch".into());
                        }
                        let index = interpret(ctx, &arr[1])?.as_int64()?;
                        let mut array = interpret(ctx, &arr[2])?.into_array()?;
                        if index < 0 || index as usize >= array.len() {
                            return Err(format!("Index out of bounds: {index}"));
                        }
                        Ok(array.swap_remove(index as usize))
                    }
                    "array-set" => {
                        if arr.len() != 4 {
                            return Err("Argument count mismatch".into());
                        }
                        let val = interpret(ctx, &arr[3])?;
                        let index = interpret(ctx, &arr[1])?.as_int64()?;
                        let var = arr[2].as_atom()?;
                        let array_pos = ctx
                            .variables
                            .get_mut(&var[..])
                            .ok_or_else(|| format!("Array {var:?} not found"))?
                            .as_array_mut()?;
                        if index < 0 || index as usize >= array_pos.len() {
                            return Err(format!("Index out of bounds: {index}"));
                        }
                        array_pos[index as usize] = val;
                        Ok(Value::Unit)
                    }
                    _ => Err(format!("Unknown function {s}")),
                },
                Tree::Array(_) => Err("Array used as function".into()),
                Tree::Int64(_) => Err("Number used as function".into()),
            }
        }
        &Tree::Int64(x) => Ok(Value::Int64(x)),
    }
}

pub fn parse_interpret(s: &str) -> Result<Value, String> {
    let mut ctx = Context::default();
    ctx.variables.insert("i64", Value::Type(TypeInfo::Int64));
    interpret(&mut ctx, &s.parse()?)
}
